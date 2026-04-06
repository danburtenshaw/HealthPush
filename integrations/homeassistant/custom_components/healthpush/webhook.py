"""Webhook handler for the HealthPush integration."""

from __future__ import annotations

import hmac
import json
import logging
from http import HTTPStatus
from typing import Any

from aiohttp import web

from homeassistant.components.webhook import (
    async_register as webhook_register,
    async_unregister as webhook_unregister,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.dispatcher import async_dispatcher_send

from .const import CONF_WEBHOOK_SECRET, DOMAIN
from .payloads import extract_valid_metrics
from .sensor import _signal_for_entry

_LOGGER = logging.getLogger(__name__)

# Maximum accepted payload size (512 KiB).
_MAX_PAYLOAD_SIZE = 512 * 1024


def register_webhook(hass: HomeAssistant, entry: ConfigEntry) -> None:
    """Register the webhook endpoint for a config entry."""
    webhook_id: str = entry.data["webhook_id"]

    webhook_register(
        hass,
        domain=DOMAIN,
        name=f"HealthPush ({entry.title})",
        webhook_id=webhook_id,
        handler=_build_handler(hass, entry),
        allowed_methods=["POST"],
    )
    _LOGGER.debug("Registered HealthPush webhook: %s", webhook_id)


def unregister_webhook(hass: HomeAssistant, entry: ConfigEntry) -> None:
    """Remove the webhook endpoint for a config entry."""
    webhook_id: str = entry.data["webhook_id"]
    webhook_unregister(hass, webhook_id)
    _LOGGER.debug("Unregistered HealthPush webhook: %s", webhook_id)


def _build_handler(hass: HomeAssistant, entry: ConfigEntry) -> Any:
    """Return an async webhook handler bound to a specific config entry."""
    secret: str = entry.data.get(CONF_WEBHOOK_SECRET, "")

    async def _handle_webhook(
        hass: HomeAssistant,
        webhook_id: str,
        request: web.Request,
    ) -> web.Response:
        """Process an incoming webhook request from the iOS app."""
        # --- Size guard ---
        if (
            request.content_length is not None
            and request.content_length > _MAX_PAYLOAD_SIZE
        ):
            _LOGGER.warning(
                "HealthPush webhook payload too large (%s bytes)",
                request.content_length,
            )
            return web.Response(
                status=HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                text="Payload too large",
            )

        # --- Parse JSON ---
        try:
            body: bytes = await request.read()
            if len(body) > _MAX_PAYLOAD_SIZE:
                return web.Response(
                    status=HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                    text="Payload too large",
                )
            data: dict[str, Any] = json.loads(body)
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            _LOGGER.warning("HealthPush webhook received invalid JSON: %s", exc)
            return web.Response(
                status=HTTPStatus.BAD_REQUEST,
                text="Invalid JSON",
            )

        # --- Authenticate ---
        if secret:
            provided = request.headers.get("X-Webhook-Secret", "")
            if not hmac.compare_digest(provided, secret):
                _LOGGER.warning("HealthPush webhook secret mismatch")
                return web.Response(
                    status=HTTPStatus.UNAUTHORIZED,
                    text="Invalid webhook secret",
                )

        # --- Validate metrics ---
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

        # --- Dispatch to sensors ---
        _LOGGER.debug(
            "HealthPush received %d metric(s) from %s",
            len(valid_metrics),
            data.get("device_name", "unknown"),
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
