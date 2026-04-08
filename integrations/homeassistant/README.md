# HealthPush — Home Assistant Integration

A custom Home Assistant integration that receives Apple Health data pushed from
the [HealthPush iOS app](https://github.com/danburtenshaw/HealthPush). No polling, no
cloud services — data flows directly from your iPhone to your Home Assistant
instance over your local network.

Background delivery still depends on iOS scheduling. Run one manual sync after
setup, then treat unattended updates as best-effort rather than exact.

## Installation

### HACS (recommended)

1. Open HACS in your Home Assistant UI.
2. Go to **Integrations** and click the three-dot menu in the top right.
3. Choose **Custom repositories**.
4. Add the repository URL and select **Integration** as the category.
5. Search for "HealthPush" and install it.
6. Restart Home Assistant.

### Manual

Copy the `custom_components/healthpush/` directory into your Home Assistant
`config/custom_components/` folder:

```bash
cp -r custom_components/healthpush/ /path/to/homeassistant/config/custom_components/healthpush/
```

Restart Home Assistant after copying.

## Configuration

1. In Home Assistant go to **Settings > Devices & Services > Add Integration**.
2. Search for **HealthPush**.
3. Enter a friendly name for the device (e.g. "My iPhone").
4. Optionally enter a webhook secret. If provided, the iOS app must send the
   same secret in the `X-Webhook-Secret` HTTP header.
5. The next screen shows the webhook URL. Copy it and paste it into the
   HealthPush iOS app's destination settings.
6. Click **Submit** to finish.
7. Run one manual sync from the iOS app so Home Assistant receives the first
   payload immediately.

## How it works

```text
iPhone                       Home Assistant
  |                               |
  |  POST /api/webhook/<id>       |
  |  { metrics: [...] }    ----->  |
  |                               |-- webhook.py validates & parses
  |                               |-- sensor.py creates/updates entities
  |       200 OK            <---- |
```

The integration registers a webhook endpoint. When the iOS app pushes health
data, the webhook handler validates the payload structure and optional secret,
then dispatches the metrics to sensor entities.

Sensor entities are registered up front and restore their last known state after
Home Assistant restarts. They update automatically as new webhook payloads
arrive.

## Supported Metrics

| Metric                      | Unit        | State Class       | Device Class |
|-----------------------------|-------------|-------------------|--------------|
| `steps`                     | steps       | total_increasing  | —            |
| `active_energy`             | kcal        | total_increasing  | energy       |
| `resting_energy`            | kcal        | total_increasing  | energy       |
| `walking_running_distance`  | km          | total_increasing  | distance     |
| `cycling_distance`          | km          | total_increasing  | distance     |
| `flights_climbed`           | flights     | total_increasing  | —            |
| `exercise_minutes`          | min         | total_increasing  | duration     |
| `stand_time`                | min         | total_increasing  | duration     |
| `move_time`                 | min         | total_increasing  | duration     |
| `weight`                    | kg          | measurement       | weight       |
| `bmi`                       | kg/m²       | measurement       | —            |
| `body_fat`                  | %           | measurement       | —            |
| `height`                    | cm          | measurement       | distance     |
| `lean_body_mass`            | kg          | measurement       | weight       |
| `heart_rate`                | bpm         | measurement       | —            |
| `resting_heart_rate`        | bpm         | measurement       | —            |
| `hrv`                       | ms          | measurement       | —            |
| `blood_pressure_systolic`   | mmHg        | measurement       | —            |
| `blood_pressure_diastolic`  | mmHg        | measurement       | —            |
| `blood_oxygen`              | %           | measurement       | —            |
| `respiratory_rate`          | breaths/min | measurement       | —            |
| `body_temperature`          | °C          | measurement       | temperature  |
| `sleep`                     | h           | measurement       | duration     |
| `dietary_energy`            | kcal        | total_increasing  | energy       |
| `water_intake`              | mL          | total_increasing  | volume       |

## Webhook Payload Format

The iOS app sends a JSON POST to the webhook URL:

```json
{
  "device_name": "My iPhone",
  "timestamp": "2026-03-22T10:30:00Z",
  "metrics": [
    {
      "type": "steps",
      "value": 8432,
      "unit": "count",
      "start_date": "2026-03-22T00:00:00Z",
      "end_date": "2026-03-22T10:30:00Z"
    },
    {
      "type": "heart_rate",
      "value": 72,
      "unit": "bpm",
      "start_date": "2026-03-22T10:25:00Z",
      "end_date": "2026-03-22T10:30:00Z"
    }
  ]
}
```

If a webhook secret is configured, the app must include it as an HTTP header:

```http
X-Webhook-Secret: your-secret-here
```

## Entity Attributes

Each sensor entity exposes these extra state attributes:

- `start_date` — The start of the measurement period
- `end_date` — The end of the measurement period
- `source_unit` — The unit as reported by the iOS app

## Automations

Example automation that sends a notification when your step count passes 10,000:

```yaml
automation:
  - alias: "Daily step goal reached"
    trigger:
      - platform: numeric_state
        entity_id: sensor.healthpush_steps
        above: 10000
    action:
      - service: notify.mobile_app
        data:
          title: "Step Goal"
          message: "You've hit 10,000 steps today!"
```

## Troubleshooting

- **Sensors show unknown**: Trigger a manual sync from the HealthPush iOS app
  so Home Assistant receives the first payload for that metric.
- **401 Unauthorized**: The webhook secret in the iOS app does not match the
  one configured in Home Assistant. Re-check both sides.
- **Webhook URL not reachable**: Make sure your Home Assistant instance is
  accessible from your iPhone. If using Nabu Casa or an HTTPS reverse proxy,
  use the external URL shown during setup.
- **Updates are delayed**: Background sync timing depends on iOS. The selected
  sync frequency is a minimum interval, not a guaranteed cadence.
- Check Home Assistant logs under **Settings > System > Logs** and filter for
  `healthpush` for detailed debug messages.

## Development

Run the integration tests:

```bash
cd integrations/homeassistant
python -m pytest
```

## License

MIT — see the repository root LICENSE file.
