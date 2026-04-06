"""Pure payload helpers used by the HealthPush webhook."""

from __future__ import annotations

from typing import Any


def extract_valid_metrics(payload: dict[str, Any]) -> list[dict[str, Any]]:
    """Return valid metrics from a webhook payload, preserving order."""
    metrics = payload.get("metrics")
    if not isinstance(metrics, list) or not metrics:
        return []

    valid_metrics: list[dict[str, Any]] = []
    for metric in metrics:
        if not isinstance(metric, dict):
            continue
        if "type" not in metric or "value" not in metric:
            continue
        valid_metrics.append(metric)

    return valid_metrics
