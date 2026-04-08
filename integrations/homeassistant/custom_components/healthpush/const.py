"""Constants for the HealthPush integration."""

from __future__ import annotations

from typing import Any, Final

DOMAIN: Final = "healthpush"
# S105 false positive: this is the name of a voluptuous config-schema key,
# not the value of a secret. The actual secret value is entered by the user.
CONF_WEBHOOK_SECRET: Final = "webhook_secret"  # noqa: S105

# Metric type definitions.
# Each key is the metric type string sent by the iOS app (sensorEntitySuffix).
# Fields:
#   name                — Human-readable name
#   unit                — Unit of measurement in HA
#   device_class        — HA SensorDeviceClass string (or None)
#   state_class         — HA SensorStateClass string
#   icon                — MDI icon override (or None to let HA pick)
#   suggested_precision — decimal places for display
METRIC_DEFINITIONS: Final[dict[str, dict[str, Any]]] = {
    # ── Activity ─────────────────────────────────────────────────────────
    "steps": {
        "name": "Steps",
        "unit": "steps",
        "device_class": None,
        "state_class": "total_increasing",
        "icon": "mdi:walk",
        "suggested_precision": 0,
    },
    "active_energy": {
        "name": "Active Energy",
        "unit": "kcal",
        "device_class": "energy",
        "state_class": "total_increasing",
        "icon": "mdi:fire",
        "suggested_precision": 0,
    },
    "resting_energy": {
        "name": "Resting Energy",
        "unit": "kcal",
        "device_class": "energy",
        "state_class": "total_increasing",
        "icon": "mdi:fire-circle",
        "suggested_precision": 0,
    },
    "walking_running_distance": {
        "name": "Walking + Running Distance",
        "unit": "km",
        "device_class": "distance",
        "state_class": "total_increasing",
        "icon": None,
        "suggested_precision": 2,
    },
    "cycling_distance": {
        "name": "Cycling Distance",
        "unit": "km",
        "device_class": "distance",
        "state_class": "total_increasing",
        "icon": "mdi:bicycle",
        "suggested_precision": 2,
    },
    "flights_climbed": {
        "name": "Flights Climbed",
        "unit": "flights",
        "device_class": None,
        "state_class": "total_increasing",
        "icon": "mdi:stairs-up",
        "suggested_precision": 0,
    },
    "exercise_minutes": {
        "name": "Exercise Minutes",
        "unit": "min",
        "device_class": "duration",
        "state_class": "total_increasing",
        "icon": "mdi:run",
        "suggested_precision": 0,
    },
    "stand_time": {
        "name": "Stand Time",
        "unit": "min",
        "device_class": "duration",
        "state_class": "total_increasing",
        "icon": "mdi:human-handsup",
        "suggested_precision": 0,
    },
    "move_time": {
        "name": "Move Time",
        "unit": "min",
        "device_class": "duration",
        "state_class": "total_increasing",
        "icon": "mdi:human-greeting",
        "suggested_precision": 0,
    },
    # ── Body Measurements ────────────────────────────────────────────────
    "weight": {
        "name": "Weight",
        "unit": "kg",
        "device_class": "weight",
        "state_class": "measurement",
        "icon": None,
        "suggested_precision": 1,
    },
    "bmi": {
        "name": "BMI",
        "unit": "kg/m\u00b2",
        "device_class": None,
        "state_class": "measurement",
        "icon": "mdi:human",
        "suggested_precision": 1,
    },
    "body_fat": {
        "name": "Body Fat",
        "unit": "%",
        "device_class": None,
        "state_class": "measurement",
        "icon": "mdi:percent",
        "suggested_precision": 1,
    },
    "height": {
        "name": "Height",
        "unit": "cm",
        "device_class": "distance",
        "state_class": "measurement",
        "icon": "mdi:human-male-height",
        "suggested_precision": 1,
    },
    "lean_body_mass": {
        "name": "Lean Body Mass",
        "unit": "kg",
        "device_class": "weight",
        "state_class": "measurement",
        "icon": "mdi:weight-lifter",
        "suggested_precision": 1,
    },
    # ── Heart ────────────────────────────────────────────────────────────
    "heart_rate": {
        "name": "Heart Rate",
        "unit": "bpm",
        "device_class": None,
        "state_class": "measurement",
        "icon": "mdi:heart-pulse",
        "suggested_precision": 0,
    },
    "resting_heart_rate": {
        "name": "Resting Heart Rate",
        "unit": "bpm",
        "device_class": None,
        "state_class": "measurement",
        "icon": "mdi:heart",
        "suggested_precision": 0,
    },
    "hrv": {
        "name": "Heart Rate Variability",
        "unit": "ms",
        "device_class": None,
        "state_class": "measurement",
        "icon": "mdi:heart-flash",
        "suggested_precision": 0,
    },
    "blood_pressure_systolic": {
        "name": "Blood Pressure Systolic",
        "unit": "mmHg",
        "device_class": None,
        "state_class": "measurement",
        "icon": "mdi:heart-plus",
        "suggested_precision": 0,
    },
    "blood_pressure_diastolic": {
        "name": "Blood Pressure Diastolic",
        "unit": "mmHg",
        "device_class": None,
        "state_class": "measurement",
        "icon": "mdi:heart-minus",
        "suggested_precision": 0,
    },
    # ── Respiratory & Vitals ─────────────────────────────────────────────
    "blood_oxygen": {
        "name": "Blood Oxygen",
        "unit": "%",
        "device_class": None,
        "state_class": "measurement",
        "icon": "mdi:lungs",
        "suggested_precision": 1,
    },
    "respiratory_rate": {
        "name": "Respiratory Rate",
        "unit": "breaths/min",
        "device_class": None,
        "state_class": "measurement",
        "icon": "mdi:lungs",
        "suggested_precision": 0,
    },
    "body_temperature": {
        "name": "Body Temperature",
        "unit": "\u00b0C",
        "device_class": "temperature",
        "state_class": "measurement",
        "icon": None,
        "suggested_precision": 1,
    },
    # ── Sleep ────────────────────────────────────────────────────────────
    "sleep": {
        "name": "Sleep",
        "unit": "h",
        "device_class": "duration",
        "state_class": "measurement",
        "icon": "mdi:sleep",
        "suggested_precision": 1,
    },
    # ── Nutrition ────────────────────────────────────────────────────────
    "dietary_energy": {
        "name": "Dietary Energy",
        "unit": "kcal",
        "device_class": "energy",
        "state_class": "total_increasing",
        "icon": "mdi:food-apple",
        "suggested_precision": 0,
    },
    "water_intake": {
        "name": "Water Intake",
        "unit": "mL",
        "device_class": "volume",
        "state_class": "total_increasing",
        "icon": "mdi:cup-water",
        "suggested_precision": 0,
    },
}
