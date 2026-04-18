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

        assert len(valid) == 2
        assert valid[0]["type"] == "steps"
        assert valid[0]["value"] == 1000
        assert valid[1]["type"] == "sleep"
        assert valid[1]["value"] == 8.5

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

    # ── Y9: Non-numeric values rejected ──────────────────────────────

    def test_non_numeric_value_rejected(self) -> None:
        payload = {
            "metrics": [
                {"type": "steps", "value": "not-a-number"},
                {"type": "weight", "value": [1, 2, 3]},
                {"type": "bmi", "value": {"nested": True}},
                {"type": "heart_rate", "value": None},
            ]
        }

        valid = extract_valid_metrics(payload)
        assert valid == []

    def test_boolean_value_rejected(self) -> None:
        payload = {
            "metrics": [
                {"type": "steps", "value": True},
                {"type": "weight", "value": False},
            ]
        }

        valid = extract_valid_metrics(payload)
        assert valid == []

    def test_string_numeric_value_coerced(self) -> None:
        payload = {
            "metrics": [
                {"type": "steps", "value": "1000"},
                {"type": "weight", "value": "72.5"},
                {"type": "heart_rate", "value": "-3.14"},
            ]
        }

        valid = extract_valid_metrics(payload)

        assert len(valid) == 3
        assert valid[0]["value"] == 1000
        assert isinstance(valid[0]["value"], int)
        assert valid[1]["value"] == 72.5
        assert isinstance(valid[1]["value"], float)
        assert valid[2]["value"] == -3.14
        assert isinstance(valid[2]["value"], float)

    # ── Y9: Oversized type keys rejected ─────────────────────────────

    def test_oversized_type_key_rejected(self) -> None:
        payload = {
            "metrics": [
                {"type": "a" * 129, "value": 100},
                {"type": "a" * 128, "value": 200},
            ]
        }

        valid = extract_valid_metrics(payload)

        assert len(valid) == 1
        assert valid[0]["value"] == 200

    def test_type_at_exact_limit_accepted(self) -> None:
        payload = {
            "metrics": [
                {"type": "x" * 128, "value": 42},
            ]
        }

        valid = extract_valid_metrics(payload)
        assert len(valid) == 1

    # ── Y9: NaN/Inf values rejected ──────────────────────────────────

    def test_nan_value_rejected(self) -> None:
        payload = {
            "metrics": [
                {"type": "heart_rate", "value": float("nan")},
            ]
        }

        valid = extract_valid_metrics(payload)
        assert valid == []

    def test_inf_value_rejected(self) -> None:
        payload = {
            "metrics": [
                {"type": "steps", "value": float("inf")},
                {"type": "weight", "value": float("-inf")},
            ]
        }

        valid = extract_valid_metrics(payload)
        assert valid == []

    def test_nan_string_rejected(self) -> None:
        payload = {
            "metrics": [
                {"type": "steps", "value": "nan"},
                {"type": "weight", "value": "inf"},
                {"type": "bmi", "value": "-inf"},
            ]
        }

        valid = extract_valid_metrics(payload)
        assert valid == []

    # ── Y9: Metric count capped at 100 ──────────────────────────────

    def test_metrics_capped_at_100(self) -> None:
        payload = {"metrics": [{"type": f"metric_{i}", "value": i} for i in range(150)]}

        valid = extract_valid_metrics(payload)

        assert len(valid) == 100
        assert valid[0]["value"] == 0
        assert valid[-1]["value"] == 99

    def test_exactly_100_metrics_accepted(self) -> None:
        payload = {"metrics": [{"type": f"metric_{i}", "value": i} for i in range(100)]}

        valid = extract_valid_metrics(payload)
        assert len(valid) == 100

    # ── Y9: String field clamping ────────────────────────────────────

    def test_string_fields_clamped_to_64_chars(self) -> None:
        long_string = "a" * 100
        payload = {
            "metrics": [
                {
                    "type": "steps",
                    "value": 1000,
                    "unit": long_string,
                    "start_date": long_string,
                    "end_date": long_string,
                },
            ]
        }

        valid = extract_valid_metrics(payload)

        assert len(valid) == 1
        assert len(valid[0]["unit"]) == 64
        assert len(valid[0]["start_date"]) == 64
        assert len(valid[0]["end_date"]) == 64

    def test_short_string_fields_unchanged(self) -> None:
        payload = {
            "metrics": [
                {
                    "type": "steps",
                    "value": 1000,
                    "unit": "steps",
                    "start_date": "2024-01-01",
                    "end_date": "2024-01-02",
                },
            ]
        }

        valid = extract_valid_metrics(payload)

        assert valid[0]["unit"] == "steps"
        assert valid[0]["start_date"] == "2024-01-01"
        assert valid[0]["end_date"] == "2024-01-02"

    # ── Edge cases ───────────────────────────────────────────────────

    def test_empty_metrics_list(self) -> None:
        assert extract_valid_metrics({"metrics": []}) == []

    def test_missing_metrics_key(self) -> None:
        assert extract_valid_metrics({}) == []

    def test_metrics_not_a_list(self) -> None:
        assert extract_valid_metrics({"metrics": "not-a-list"}) == []

    def test_non_string_type_rejected(self) -> None:
        payload = {
            "metrics": [
                {"type": 123, "value": 100},
                {"type": None, "value": 200},
            ]
        }

        valid = extract_valid_metrics(payload)
        assert valid == []

    def test_value_missing_key_rejected(self) -> None:
        """Metric with type but literally no 'value' key is rejected."""
        payload = {
            "metrics": [
                {"type": "steps"},
            ]
        }

        valid = extract_valid_metrics(payload)
        assert valid == []

    def test_extra_fields_preserved(self) -> None:
        payload = {
            "metrics": [
                {"type": "steps", "value": 1000, "id": "abc", "custom": "data"},
            ]
        }

        valid = extract_valid_metrics(payload)

        assert len(valid) == 1
        assert valid[0]["id"] == "abc"
        assert valid[0]["custom"] == "data"


if __name__ == "__main__":
    unittest.main()
