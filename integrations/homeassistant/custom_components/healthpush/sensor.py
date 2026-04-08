"""Sensor platform for the HealthPush integration."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any

from homeassistant.components.sensor import (
    SensorDeviceClass,
    SensorEntity,
    SensorStateClass,
)
from homeassistant.const import STATE_UNAVAILABLE, STATE_UNKNOWN
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.restore_state import RestoreEntity

from .const import DOMAIN, METRIC_DEFINITIONS

if TYPE_CHECKING:
    from homeassistant.config_entries import ConfigEntry
    from homeassistant.helpers.entity_platform import AddEntitiesCallback

_LOGGER = logging.getLogger(__name__)

# Dispatcher signal name template.  One signal per config entry.
SIGNAL_NEW_DATA = f"{DOMAIN}_new_data_{{entry_id}}"

# Maps string names to the HA enum members.
_STATE_CLASS_MAP: dict[str, SensorStateClass] = {
    "measurement": SensorStateClass.MEASUREMENT,
    "total_increasing": SensorStateClass.TOTAL_INCREASING,
    "total": SensorStateClass.TOTAL,
}

_DEVICE_CLASS_MAP: dict[str, SensorDeviceClass] = {
    "weight": SensorDeviceClass.WEIGHT,
    "temperature": SensorDeviceClass.TEMPERATURE,
    "distance": SensorDeviceClass.DISTANCE,
    "duration": SensorDeviceClass.DURATION,
    "energy": SensorDeviceClass.ENERGY,
    "volume": SensorDeviceClass.VOLUME,
}


def _signal_for_entry(entry_id: str) -> str:
    """Return the dispatcher signal name for a config entry."""
    return SIGNAL_NEW_DATA.format(entry_id=entry_id)


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up HealthPush sensor entities from a config entry."""
    entry_data: dict[str, Any] = hass.data[DOMAIN][entry.entry_id]
    known_sensors: dict[str, HealthPushSensor] = entry_data["sensors"]

    if not known_sensors:
        sensors = [
            HealthPushSensor(entry=entry, metric_type=metric_type)
            for metric_type in METRIC_DEFINITIONS
        ]
        known_sensors.update({sensor.metric_type: sensor for sensor in sensors})
        async_add_entities(sensors)

    @callback
    def _handle_new_data(metrics: list[dict[str, Any]]) -> None:
        """Update registered sensors from the latest webhook payload."""
        for metric in metrics:
            try:
                metric_type: str = metric["type"]
                if metric_type not in METRIC_DEFINITIONS:
                    _LOGGER.warning(
                        "Ignoring unknown metric type '%s' from HealthPush",
                        metric_type,
                    )
                    continue

                known_sensors[metric_type].update_from_metric(metric)
            except Exception:
                _LOGGER.exception("Error processing metric '%s'", metric.get("type", "?"))

    # Subscribe to webhook data dispatches for this config entry.
    entry_data["unsub_dispatcher"] = async_dispatcher_connect(
        hass,
        _signal_for_entry(entry.entry_id),
        _handle_new_data,
    )


class HealthPushSensor(SensorEntity, RestoreEntity):
    """Representation of a single health metric as an HA sensor."""

    _attr_has_entity_name = True
    _attr_should_poll = False

    def __init__(
        self,
        entry: ConfigEntry,
        metric_type: str,
        initial_metric: dict[str, Any] | None = None,
    ) -> None:
        """Initialise the sensor."""
        defn = METRIC_DEFINITIONS[metric_type]

        self._entry = entry
        self._metric_type = metric_type

        # Stable unique id: <entry_id>_<metric_type>
        self._attr_unique_id = f"{entry.entry_id}_{metric_type}"
        self._attr_name = defn["name"]
        self._attr_native_unit_of_measurement = defn["unit"]

        if defn["device_class"] is not None:
            self._attr_device_class = _DEVICE_CLASS_MAP.get(defn["device_class"])

        state_class_str: str | None = defn.get("state_class")
        if state_class_str is not None:
            self._attr_state_class = _STATE_CLASS_MAP.get(state_class_str)

        if defn["icon"] is not None:
            self._attr_icon = defn["icon"]

        self._attr_suggested_display_precision = defn.get("suggested_precision")

        self._attr_native_value = (
            initial_metric.get("value") if initial_metric is not None else None
        )
        self._extra: dict[str, Any] = (
            self._extra_from_metric(initial_metric) if initial_metric is not None else {}
        )

    @property
    def metric_type(self) -> str:
        """Expose metric type for registration helpers."""
        return self._metric_type

    # ---- Device grouping ----

    @property
    def device_info(self) -> DeviceInfo:
        """Group all sensors under one device per config entry."""
        return DeviceInfo(
            identifiers={(DOMAIN, self._entry.entry_id)},
            name=self._entry.data.get("name", "HealthPush"),
            manufacturer="HealthPush",
            model="iOS App",
            entry_type=None,
        )

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        """Return extra attributes stored alongside the sensor value."""
        return self._extra

    async def async_added_to_hass(self) -> None:
        """Restore the last known state after Home Assistant restarts."""
        await super().async_added_to_hass()

        if self._attr_native_value is not None:
            return

        last_state = await self.async_get_last_state()
        if last_state is None:
            return

        if last_state.state in {STATE_UNKNOWN, STATE_UNAVAILABLE}:
            return

        try:
            restored_value: Any
            if "." in last_state.state:
                restored_value = float(last_state.state)
            else:
                restored_value = int(last_state.state)
        except ValueError:
            restored_value = last_state.state

        self._attr_native_value = restored_value
        self._extra = dict(last_state.attributes)

    # ---- Data helpers ----

    @callback
    def set_initial_value(self, metric: dict[str, Any]) -> None:
        """Update value before the entity is registered with HA.

        This must NOT call async_write_ha_state because the entity
        does not have a hass reference yet.
        """
        self._attr_native_value = metric.get("value")
        self._extra = self._extra_from_metric(metric)

    @callback
    def update_from_metric(self, metric: dict[str, Any]) -> None:
        """Update the sensor with a new metric payload from the webhook."""
        self._attr_native_value = metric.get("value")
        self._extra = self._extra_from_metric(metric)
        self.async_write_ha_state()

    @staticmethod
    def _extra_from_metric(metric: dict[str, Any]) -> dict[str, Any]:
        """Extract extra state attributes from a raw metric dict."""
        attrs: dict[str, Any] = {}
        if "start_date" in metric:
            attrs["start_date"] = metric["start_date"]
        if "end_date" in metric:
            attrs["end_date"] = metric["end_date"]
        if "unit" in metric:
            attrs["source_unit"] = metric["unit"]
        return attrs
