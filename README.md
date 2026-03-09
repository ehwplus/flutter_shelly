# flutter_shelly

Local Flutter client for Shelly Gen2+/Gen3/Gen4 devices via RPC (`/rpc`), focused on
energy metering and activity analysis.

## Features

- Shelly RPC over HTTP (`Shelly.GetStatus`, `Shelly.GetDeviceInfo`, `Switch.GetStatus`, `Switch.Set`)
- Optional Shelly digest auth support
- Energy usage parsing from `Switch.GetStatus` (`apower`, `aenergy`, `ret_aenergy`)
- Historical energy data via `EMData.GetData` / `EM1Data.GetData`
- Query all available Shelly periods (`300`, `900`, `1800`, `3600` seconds)
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

## Historical Energy Data

```dart
final interval = ShellyEnergyDataInterval.hourly(
  startDate: DateTime(2026, 1, 1),
  endDate: DateTime(2026, 1, 2),
  componentId: 0,
  rpcNamespace: 'EMData', // or EM1Data
);

final data = await client.getEnergyData(interval);
for (final point in data.points) {
  print('${point.start}: ${point.energyWh} Wh');
}
```

## All Available Periods

```dart
final allPeriods = await client.getEnergyDataForAllPeriods(
  startDate: DateTime(2026, 1, 1),
  endDate: DateTime(2026, 1, 2),
  componentId: 0,
  rpcNamespace: 'EMData',
);

for (final entry in allPeriods.entries) {
  print('${entry.key.apiName}: ${entry.value.points.length} points');
}
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
- `EMData.GetData`/`EM1Data.GetData` availability depends on the specific Shelly device and firmware.
- For multi-channel devices (for example power strips), query each component ID separately.
