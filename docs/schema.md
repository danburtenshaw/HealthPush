# v1 Schema Contract

This document defines the frozen v1 data contract for HealthPush exports. Once a user's first sync occurs under this schema, the record shape, canonical units, and file layout are locked.

## Record Shape

Each health data record contains the following fields:

| Field                | Type     | Description                                                    |
|----------------------|----------|----------------------------------------------------------------|
| `schemaVersion`      | string   | Always `"1.0"` for this contract.                              |
| `uuid`               | string   | HealthKit sample UUID or deterministic v5 UUID for aggregates. |
| `metric.key`         | string   | Stable HealthPush key (e.g. `"heart_rate"`), uses `fileStem`.  |
| `metric.hkIdentifier`| string   | HealthKit type identifier (e.g. `"HKQuantityTypeIdentifierHeartRate"`). |
| `metric.kind`        | string   | One of `"quantity"`, `"cumulative"`, or `"category"`.          |
| `value`              | number   | Numeric measurement value.                                     |
| `unit`               | string   | Canonical unit string (see table below).                       |
| `startDate`          | string   | ISO 8601 UTC with fractional seconds, trailing `Z`.            |
| `endDate`            | string   | ISO 8601 UTC with fractional seconds, trailing `Z`.            |
| `tzOffset`           | string   | Local timezone offset at sample time, formatted `+HH:MM` or `-HH:MM`. |
| `source.name`        | string   | Source device or app name.                                     |
| `source.bundleId`    | string   | Source app bundle identifier (may be empty).                   |
| `aggregation`        | string   | `"raw"` for discrete samples, `"sum"` for cumulative aggregates. |
| `categoryValue`      | int?     | HealthKit category value (only for category types, null otherwise). |
| `deleted`            | bool     | `true` if this record is a tombstone marking deletion.         |
| `deletedAt`          | string?  | ISO 8601 timestamp of deletion (null if not deleted).          |

## Canonical Units

| Domain     | Unit         | Notes                                      |
|------------|--------------|--------------------------------------------|
| Mass       | `kg`         |                                            |
| Length     | `m`          |                                            |
| Energy     | `kcal`       |                                            |
| Time       | `s`          | Exercise time, stand time, sleep duration  |
| Temperature| `degC`       |                                            |
| Pressure   | `mmHg`       | Blood pressure                             |
| Rate       | `count/min`  | Heart rate, respiratory rate               |
| HRV        | `ms`         | Heart rate variability                     |
| Volume     | `mL`         | Water intake                               |
| Ratio      | `fraction`   | SpO2, body fat (0.0-1.0 range)             |
| Count      | `count`      | Steps, flights climbed, stand hours        |
| VO2Max     | `mL/kg/min`  |                                            |
| Glucose    | `mg/dL`      |                                            |

## JSON Record Example

```json
{
  "schemaVersion": "1.0",
  "uuid": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "metric": {
    "key": "heart_rate",
    "hkIdentifier": "HKQuantityTypeIdentifierHeartRate",
    "kind": "quantity"
  },
  "value": 72.0,
  "unit": "count/min",
  "startDate": "2026-04-09T12:00:00.000Z",
  "endDate": "2026-04-09T12:00:00.000Z",
  "tzOffset": "+01:00",
  "source": {
    "name": "Apple Watch",
    "bundleId": "com.apple.health"
  },
  "aggregation": "raw",
  "categoryValue": null,
  "deleted": false,
  "deletedAt": null
}
```

## File Layout

Data files are stored in a hierarchical path structure:

```
{prefix}/v1/{metric.key}/{YYYY}/{MM}/{DD}/data.jsonl
{prefix}/v1/{metric.key}/{YYYY}/{MM}/{DD}/_manifest.json
```

- `data.jsonl` contains newline-delimited JSON (one record per line, no array wrapper).
- `_manifest.json` is a sidecar with metadata about the data file.

### Manifest Example

```json
{
  "schemaVersion": "1.0",
  "metric": "heart_rate",
  "date": "2026-04-09",
  "recordCount": 42,
  "lastModified": "2026-04-09T14:30:00.000Z"
}
```

## CSV Column Order

When exporting as CSV, the column order is:

```
uuid,startDate,endDate,tzOffset,value,unit,aggregation,sourceName,sourceBundleId,schemaVersion
```

## Tombstones

When a record is deleted, a tombstone is emitted with `deleted: true` and `deletedAt` set to the deletion timestamp. Tombstones are included in the output so downstream consumers know the record was removed.

## Compatibility

- The `schemaVersion` field allows future schema evolution while maintaining backward compatibility.
- Consumers should ignore unknown fields for forward compatibility.
- The aggregate UUID is deterministic: `SHA256(dateString:metric.rawValue:aggregation)` with UUID v5 version bits.
