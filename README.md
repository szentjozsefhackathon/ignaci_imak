# ignaci_imak

Ignáci imák app.

## Getting Started

```shell
# create .env (add missing values)
cp .env.example .env

# get dependencies
flutter pub get

# create generated source files
dart run build_runner build

# create generated icons
dart run flutter_launcher_icons

# start app in emulator (Android/iOS)
flutter run

# OR as a web app

# download/generate database related files
dart tools/download_sqlite3_wasm.dart
dart compile js -O4 web/drift_worker.dart --output web/drift_worker.js

# start app in eg. Chrome
flutter run -d chrome
```

## License

This project is licensed under the MIT License.
