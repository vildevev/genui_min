# Contributing to genui_min

Thanks for your interest in contributing! This is a small, focused package, so
contributions that keep it minimal and on-device-friendly are especially welcome.

## Getting started

```bash
git clone https://github.com/vildevev/genui_min.git
cd genui_min
flutter pub get
```

Run the example app:

```bash
cd example
flutter pub get
flutter run            # tap "Use sample output" to try it without a model
```

## Before you open a PR

Please make sure these pass locally — CI runs the same checks:

```bash
flutter analyze
flutter test
dart format --set-exit-if-changed .
dart run tool/bench.dart
```

## Guidelines

- **Keep the catalog minimal.** The whole point is a small system prompt that
  fits on a phone. New widgets should earn their token cost.
- **Keep the repair pass deterministic.** No network calls, no model calls — it
  exists to fix small-model output cheaply and predictably.
- **Add a test.** Repair-pass behavior changes should come with a case in
  `test/a2ui_repair_test.dart` — or better, a corpus case in `bench/cases/`
  (see `doc/bench.md`); captured raw model outputs are the best regression
  fixtures.
- **Match the existing style.** Run `dart format` and follow the surrounding code.

## Reporting issues

Open an issue at https://github.com/vildevev/genui_min/issues with:
- what you expected vs. what happened
- a minimal repro (the model output / JSON that triggered it, if relevant)
- your Flutter / Dart version (`flutter --version`)

By contributing, you agree that your contributions will be licensed under the
MIT License.
