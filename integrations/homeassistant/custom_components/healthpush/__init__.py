"""The HealthPush integration — receive Apple Health data from the iOS app."""

from __future__ import annotations

import logging
from typing import Any

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant

from .const import DOMAIN
from .webhook import register_webhook, unregister_webhook

_LOGGER = logging.getLogger(__name__)

PLATFORMS: list[Platform] = [Platform.SENSOR]


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Set up HealthPush from a config entry."""
    hass.data.setdefault(DOMAIN, {})

    # Per-entry runtime storage shared between webhook handler and sensors.
    entry_data: dict[str, Any] = {
        "sensors": {},
        "unsub_dispatcher": None,
        "last_timestamp": None,
        "last_device_name": None,
    }
    hass.data[DOMAIN][entry.entry_id] = entry_data

    # Register the webhook so the iOS app can start posting data.
    register_webhook(hass, entry)

    # Set up sensor platform and register the sensor entities for this entry.
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)

    _LOGGER.info(
        "HealthPush integration loaded for '%s' (webhook: %s)",
        entry.title,
        entry.data.get("webhook_id"),
    )
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload a HealthPush config entry."""
    # Tear down sensor platform first.
    unload_ok = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)

    if unload_ok:
        # Disconnect the dispatcher subscription.
        entry_data: dict[str, Any] = hass.data[DOMAIN].pop(entry.entry_id, {})
        unsub = entry_data.get("unsub_dispatcher")
        if unsub is not None:
            unsub()

        # Remove the webhook endpoint.
        unregister_webhook(hass, entry)

        _LOGGER.info("HealthPush integration unloaded for '%s'", entry.title)

    return unload_ok
