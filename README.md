# flutter_shelly

Local Flutter client for Shelly Gen2+/Gen3/Gen4 devices via RPC (`/rpc`), focused on
energy metering and activity analysis.

## Features

- Shelly RPC over HTTP (`Shelly.GetStatus`, `Shelly.GetDeviceInfo`, `Switch.GetStatus`, `Switch.Set`)
- Optional Shelly digest auth support
- Energy usage parsing from `Switch.GetStatus` (`apower`, `aenergy`, `ret_aenergy`)
- Multi-slot support (for example power strips via `switch:0..n`)
- Short-range series via `aenergy.by_minute` + `aenergy.minute_ts`
- Period aggregation (`300`, `900`, `1800`, `3600` seconds) from available switch series
- Activity detection from energy time series (similar to `flutter_tapo`)

## Getting Started

You need the device IP address in your local network. If RPC auth is enabled on the
device, also pass username/password.

```dart
import 'package:flutter_shelly/flutter_shelly.dart';

final client = HttpShellyApiClient(
  host: '192.168.1.80',
  username: 'admin', // optional
  password: 'secret', // optional
);

final info = await client.getDeviceInfo();
final usage = await client.getEnergyUsage(id: 0);
print('Model: ${info.model}');
print('Power: ${usage.activePowerW} W');
```

## PlusPlugS / PowerStrip Energy Access

```dart
final usage = await client.getEnergyUsage(id: 0); // slot id
print('Power: ${usage.activePowerW} W');
print('Total: ${usage.totalActiveEnergyWh} Wh');
print('by_minute: ${usage.byMinuteMilliWattHours}');
```

## Activity Detection

```dart
final activityInterval = ShellyEnergyDataInterval.activity(
  startDate: DateTime(2026, 1, 1),
  endDate: DateTime(2026, 1, 1, 12),
);

final activityData = await client.getEnergyData(activityInterval);
for (final activity in activityData.activities()) {
  print('${activity.start} -> ${activity.end} (${activity.energyWh} Wh)');
}
```

## Notes

- The device must be reachable in your local network.
- For PlusPlugS/PowerStrip, the relevant path is `switch:<id>.aenergy` from `Switch.GetStatus`/`Shelly.GetStatus`.
- `aenergy.by_minute` is short retention (latest complete minutes). For day/week/month views, store `aenergy.total` over time and aggregate externally (same pattern Home Assistant uses with recorder/statistics).
- `EMData`/`EM1Data` calls are device-dependent and are not available on many switch-only devices.
