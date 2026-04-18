"""Pure payload helpers used by the HealthPush webhook."""

from __future__ import annotations

import logging
import math
import re
from typing import Any

_LOGGER = logging.getLogger(__name__)

# Hard ceiling on the number of metrics accepted per payload.
_MAX_METRICS_PER_PAYLOAD = 100

# Size limits for individual field values.
_MAX_TYPE_LENGTH = 128
_MAX_STRING_FIELD_LENGTH = 64

# String fields that are clamped to _MAX_STRING_FIELD_LENGTH when present.
_CLAMPED_STRING_FIELDS = ("unit", "start_date", "end_date")

# Strip control characters (including CR/LF) from values that originate in the
# request payload before they hit the log stream, so a malicious client cannot
# inject forged log lines or escape sequences.
_CONTROL_CHAR_RE = re.compile(r"[\x00-\x1f\x7f]")
_MAX_LOG_VALUE_LENGTH = 64


def sanitize_for_log(value: Any) -> str:
    """Return a log-safe representation of an untrusted payload value."""
    text = str(value) if value is not None else "unknown"
    # Belt-and-braces: the regex already strips \r and \n, but the explicit
    # str.replace() calls are also there so static analyzers (CodeQL's
    # py/log-injection in particular) recognize this as a sanitizer.
    cleaned = _CONTROL_CHAR_RE.sub("?", text).replace("\r", "?").replace("\n", "?")
    if len(cleaned) > _MAX_LOG_VALUE_LENGTH:
        cleaned = cleaned[:_MAX_LOG_VALUE_LENGTH] + "..."
    return cleaned


def _coerce_numeric(raw: Any) -> float | int | None:
    """Coerce *raw* to a numeric value, returning ``None`` on failure.

    Accepts ``int``, ``float``, and string representations of numbers.
    Rejects NaN, Inf, and anything that cannot be interpreted as a finite
    number.
    """
    if isinstance(raw, bool):
        # bool is a subclass of int in Python; reject it explicitly.
        return None

    if isinstance(raw, (int, float)):
        return raw if math.isfinite(raw) else None

    if not isinstance(raw, str):
        return None

    try:
        value = float(raw)
    except (ValueError, OverflowError):
        return None

    if not math.isfinite(value):
        return None

    # Preserve int representation when the string has no fractional part.
    if value == int(value) and "." not in raw:
        value = int(value)
    return value


def _validate_metric(metric: Any) -> dict[str, Any] | None:
    """Validate a single metric entry; return the sanitized dict, or ``None``."""
    if not isinstance(metric, dict):
        return None

    raw_type = metric.get("type")
    if not isinstance(raw_type, str):
        return None
    if len(raw_type) > _MAX_TYPE_LENGTH:
        _LOGGER.debug(
            "HealthPush metric skipped: type key exceeds %d chars",
            _MAX_TYPE_LENGTH,
        )
        return None

    raw_value = metric.get("value")
    if raw_value is None:
        return None

    coerced_value = _coerce_numeric(raw_value)
    if coerced_value is None:
        _LOGGER.debug(
            "HealthPush metric skipped: non-numeric or non-finite value for type '%s'",
            sanitize_for_log(raw_type),
        )
        return None

    validated: dict[str, Any] = {**metric, "value": coerced_value}
    for field in _CLAMPED_STRING_FIELDS:
        if field in validated and isinstance(validated[field], str):
            validated[field] = validated[field][:_MAX_STRING_FIELD_LENGTH]
    return validated


def extract_valid_metrics(payload: dict[str, Any]) -> list[dict[str, Any]]:
    """Return valid metrics from a webhook payload, preserving order.

    Applies the following validation rules to each metric:
    - Must be a ``dict`` containing both ``type`` (str, <= 128 chars) and
      ``value`` (numeric and finite).
    - ``value`` is coerced from string when possible; NaN/Inf are rejected.
    - Optional string fields (``unit``, ``start_date``, ``end_date``) are
      clamped to 64 characters.
    - The overall result is capped at 100 metrics.
    """
    metrics = payload.get("metrics")
    if not isinstance(metrics, list) or not metrics:
        return []

    valid_metrics: list[dict[str, Any]] = []
    for metric in metrics:
        validated = _validate_metric(metric)
        if validated is None:
            continue

        valid_metrics.append(validated)

        if len(valid_metrics) >= _MAX_METRICS_PER_PAYLOAD:
            _LOGGER.warning(
                "HealthPush payload truncated: more than %d metrics received",
                _MAX_METRICS_PER_PAYLOAD,
            )
            break

    return valid_metrics
