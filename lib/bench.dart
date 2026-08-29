/// genui_min bench — score raw small-model A2UI output against the repair
/// pipeline.
///
/// Pure Dart (uses dart:io for corpus loading), so import this entrypoint
/// from CLI tools; the main `package:genui_min/genui_min.dart` stays web-safe.
library;

export 'src/a2ui_repair.dart';
export 'src/bench_corpus.dart';
export 'src/scoring.dart';
