from __future__ import annotations

from pathlib import Path
import sys
import unittest

MODULE_DIR = Path(__file__).resolve().parents[1] / "custom_components" / "healthpush"
sys.path.insert(0, str(MODULE_DIR))

# E402: import must follow sys.path manipulation to find the local payloads module.
from payloads import extract_valid_metrics  # noqa: E402


class PayloadTests(unittest.TestCase):
    def test_extract_valid_metrics_filters_invalid_entries(self) -> None:
        payload = {
            "metrics": [
                {"type": "steps", "value": 1000},
                {"type": "heart_rate"},
                ["not-a-dict"],
                {"value": 72},
                {"type": "sleep", "value": 8.5},
            ]
        }

        valid = extract_valid_metrics(payload)

        assert valid == [{"type": "steps", "value": 1000}, {"type": "sleep", "value": 8.5}]

    def test_extract_valid_metrics_preserves_duplicate_ids(self) -> None:
        payload = {
            "metrics": [
                {"id": "same-id", "type": "steps", "value": 4200},
                {"id": "same-id", "type": "steps", "value": 8400},
            ]
        }

        valid = extract_valid_metrics(payload)

        assert len(valid) == 2
        assert valid[0]["value"] == 4200
        assert valid[1]["value"] == 8400


if __name__ == "__main__":
    unittest.main()
