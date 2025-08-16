# ignaci_imak

Ignáci imák app.

## Getting Started

```shell
# get dependencies
flutter pub get

# create generated source files
dart run build_runner build

# create generated env variables and flavors
dart run dart_define generate --FLAVOR=development

# create generated icons
dart run flutter_launcher_icons

# start app in emulator (Android/iOS)
flutter run --dart-define-from-file dart_define.json

# OR start app in eg. Chrome
flutter run -d chrome --dart-define-from-file dart_define.json
```

## License

This project is licensed under the MIT License.
