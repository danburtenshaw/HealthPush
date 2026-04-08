"""Webhook handler for the HealthPush integration."""

from __future__ import annotations

import hmac
from http import HTTPStatus
import json
import logging
import re
from typing import TYPE_CHECKING, Any

from aiohttp import web
from homeassistant.components.webhook import (
    async_register as webhook_register,
    async_unregister as webhook_unregister,
)
from homeassistant.helpers.dispatcher import async_dispatcher_send

from .const import CONF_WEBHOOK_SECRET, DOMAIN
from .payloads import extract_valid_metrics
from .sensor import _signal_for_entry

if TYPE_CHECKING:
    from homeassistant.config_entries import ConfigEntry
    from homeassistant.core import HomeAssistant

_LOGGER = logging.getLogger(__name__)

# Maximum accepted payload size (512 KiB).
_MAX_PAYLOAD_SIZE = 512 * 1024

# Strip control characters (including CR/LF) from values that originate in the
# request payload before they hit the log stream, so a malicious client cannot
# inject forged log lines or escape sequences.
_CONTROL_CHAR_RE = re.compile(r"[\x00-\x1f\x7f]")
_MAX_LOGGED_DEVICE_NAME = 64


def _sanitize_for_log(value: Any) -> str:
    """Return a log-safe representation of an untrusted payload value."""
    text = str(value) if value is not None else "unknown"
    cleaned = _CONTROL_CHAR_RE.sub("?", text)
    if len(cleaned) > _MAX_LOGGED_DEVICE_NAME:
        cleaned = cleaned[:_MAX_LOGGED_DEVICE_NAME] + "..."
    return cleaned


def register_webhook(hass: HomeAssistant, entry: ConfigEntry) -> None:
    """Register the webhook endpoint for a config entry."""
    webhook_id: str = entry.data["webhook_id"]

    webhook_register(
        hass,
        domain=DOMAIN,
        name=f"HealthPush ({entry.title})",
        webhook_id=webhook_id,
        handler=_build_handler(entry),
        allowed_methods=["POST"],
    )
    _LOGGER.debug("Registered HealthPush webhook: %s", webhook_id)


def unregister_webhook(hass: HomeAssistant, entry: ConfigEntry) -> None:
    """Remove the webhook endpoint for a config entry."""
    webhook_id: str = entry.data["webhook_id"]
    webhook_unregister(hass, webhook_id)
    _LOGGER.debug("Unregistered HealthPush webhook: %s", webhook_id)


async def _read_and_parse(
    request: web.Request,
) -> tuple[dict[str, Any] | None, web.Response | None]:
    """Read the request body, enforce size limits, and parse JSON.

    Returns ``(data, None)`` on success or ``(None, error_response)`` on failure.
    Consolidating the three size/parse failure paths here keeps the main webhook
    handler below the return-count complexity threshold.
    """
    if request.content_length is not None and request.content_length > _MAX_PAYLOAD_SIZE:
        _LOGGER.warning(
            "HealthPush webhook payload too large (%s bytes)",
            request.content_length,
        )
        return None, web.Response(
            status=HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
            text="Payload too large",
        )
    try:
        body: bytes = await request.read()
    except Exception as exc:  # noqa: BLE001 — aiohttp may raise several types during read
        _LOGGER.warning("HealthPush webhook body read failed: %s", exc)
        return None, web.Response(
            status=HTTPStatus.BAD_REQUEST,
            text="Could not read body",
        )
    if len(body) > _MAX_PAYLOAD_SIZE:
        return None, web.Response(
            status=HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
            text="Payload too large",
        )
    try:
        return json.loads(body), None
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        _LOGGER.warning("HealthPush webhook received invalid JSON: %s", exc)
        return None, web.Response(
            status=HTTPStatus.BAD_REQUEST,
            text="Invalid JSON",
        )


def _build_handler(entry: ConfigEntry) -> Any:
    """Return an async webhook handler bound to a specific config entry.

    ``hass`` is intentionally not an argument here — it is passed to the inner
    handler by Home Assistant's webhook machinery on each request.
    """
    secret: str = entry.data.get(CONF_WEBHOOK_SECRET, "")

    async def _handle_webhook(
        hass: HomeAssistant,
        _webhook_id: str,
        request: web.Request,
    ) -> web.Response:
        """Process an incoming webhook request from the iOS app."""
        data, err = await _read_and_parse(request)
        if err is not None or data is None:
            return err or web.Response(status=HTTPStatus.BAD_REQUEST)

        if secret:
            provided = request.headers.get("X-Webhook-Secret", "")
            if not hmac.compare_digest(provided, secret):
                _LOGGER.warning("HealthPush webhook secret mismatch")
                return web.Response(
                    status=HTTPStatus.UNAUTHORIZED,
                    text="Invalid webhook secret",
                )

        metrics: list[dict[str, Any]] | None = data.get("metrics")
        if not isinstance(metrics, list) or not metrics:
            _LOGGER.warning("HealthPush webhook payload missing 'metrics' list")
            return web.Response(
                status=HTTPStatus.BAD_REQUEST,
                text="Missing or empty 'metrics' array",
            )

        valid_metrics = extract_valid_metrics(data)
        if not valid_metrics:
            return web.Response(
                status=HTTPStatus.BAD_REQUEST,
                text="No valid metrics in payload",
            )

        entry_data = hass.data[DOMAIN].get(entry.entry_id, {})

        _LOGGER.debug(
            "HealthPush received %d metric(s) from %s",
            len(valid_metrics),
            _sanitize_for_log(data.get("device_name")),
        )

        async_dispatcher_send(
            hass,
            _signal_for_entry(entry.entry_id),
            valid_metrics,
        )

        entry_data["last_timestamp"] = data.get("timestamp")
        entry_data["last_device_name"] = data.get("device_name")

        return web.Response(
            status=HTTPStatus.OK,
            text=f"Accepted {len(valid_metrics)} metric(s)",
        )

    return _handle_webhook
