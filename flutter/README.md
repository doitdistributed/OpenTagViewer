# OpenTagViewer – Flutter/Dart

A cross-platform Flutter/Dart port of the [OpenTagViewer Android app](https://github.com/parawanderer/OpenTagViewer).

> [!WARNING]
> This Flutter version is a community implementation of the same concept.
> It is **not** affiliated with Apple Inc. or Google LLC.

---

## Features

- Sign in with your Apple ID (including 2FA via Trusted Device or SMS)
- Import your AirTag data from the `.zip` export produced by the
  [OpenTagViewer macOS app](https://github.com/parawanderer/OpenTagViewer/wiki/How-To:-Export-AirTags-From-Mac)
- View all beacon locations on an interactive OpenStreetMap-based map
  (no Google Maps API key required)
- Browse full location history with a date-range picker
- Customise the display name and emoji for each beacon
- Light & Dark mode via Material 3

---

## Project Structure

```
flutter/
├── lib/
│   ├── main.dart                  # App entry point & routing
│   ├── models/
│   │   ├── apple_user_data.dart
│   │   ├── beacon_information.dart
│   │   └── beacon_location_report.dart
│   ├── screens/
│   │   ├── login_screen.dart
│   │   ├── device_list_screen.dart
│   │   ├── map_screen.dart
│   │   ├── history_screen.dart
│   │   ├── device_info_screen.dart
│   │   └── settings_screen.dart
│   ├── services/
│   │   ├── anisette_service.dart
│   │   ├── apple_auth_service.dart
│   │   ├── beacon_import_service.dart
│   │   └── beacon_report_service.dart
│   └── state/
│       └── app_state.dart
└── test/
    ├── models_test.dart
    ├── beacon_import_service_test.dart
    └── services_test.dart
```

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.0

### Install dependencies

```bash
cd flutter
flutter pub get
```

### Run the app

```bash
# Android
flutter run

# iOS
flutter run -d <ios-device-id>
```

### Run tests

```bash
flutter test
```

---

## How It Works

The Flutter app follows the same architecture as the Android app:

1. **Authentication** – The app logs in to your Apple ID via an
   [Anisette server](https://github.com/SideStore/anisette-servers).
   Credentials are stored securely using `flutter_secure_storage`.

2. **Import** – You export your AirTag data once from a Mac using the
   OpenTagViewer macOS export tool. The resulting `.zip` is imported
   into the app.

3. **Location reports** – The app periodically queries Apple's FindMy
   network (via the Anisette server backend) for the latest location of
   each beacon.

4. **Map** – Locations are shown using `flutter_map` with OpenStreetMap
   tiles (no API key needed).

---

## Platform Support

| Platform | Status  |
|----------|---------|
| Android  | ✅ Supported |
| iOS      | ✅ Supported |
| Web      | 🔶 Untested |
| macOS    | 🔶 Untested |
| Windows  | 🔶 Untested |
| Linux    | 🔶 Untested |

---

## Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_map` + `latlong2` | Map display (OpenStreetMap) |
| `provider` | State management |
| `flutter_secure_storage` | Secure credential storage |
| `shared_preferences` | Settings persistence |
| `file_picker` | Import `.zip` files |
| `archive` | Zip decompression |
| `xml` | plist / XML parsing |
| `http` | HTTP requests |

---

## Contributing

Contributions are welcome. See the main
[OpenTagViewer contributing guide](../README.md#contributing) for details.
