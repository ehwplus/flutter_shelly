# flutter_shelly example

Demo app for testing `flutter_shelly` against local Shelly devices.

## Features in the demo

- connect to a Shelly device (host/url, port, optional HTTPS)
- optional RPC auth (username/password)
- load device info and full status
- read current switch energy usage
- select slot/switch (`switch:0..n`) for multi-channel devices
- load aggregated consumption from `aenergy.by_minute` for periods (`300`, `900`, `1800`, `3600` seconds)
- evaluate activities from loaded time series

## Run

```bash
cd example
flutter pub get
flutter run
```

## Notes for iOS/macOS local networking

When communicating with local devices via HTTP, allow local networking in the app
entitlements/plist (same as in the package README recommendations).
