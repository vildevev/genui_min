// The bench corpus: small JSON case files describing one raw model response
// each. Lives in `bench/cases/*.case.json`; loaded by `tool/bench.dart` and by
// the corpus regression test so both always score the same data.
//
// Contributing a case is the easiest meaningful contribution: run a prompt
// through your model, save the *raw* output (prose and all), and add a case
// file — see doc/bench.md.
//
// Pure Dart, no Flutter deps (uses dart:io, so it is NOT exported from the
// main library — import `package:genui_min/bench.dart` instead).

import 'dart:convert';
import 'dart:io';

import 'scoring.dart';

/// One bench case: a prompt, the model's raw response, and where it came from.
final class BenchCase {
  const BenchCase({
    required this.name,
    required this.model,
    required this.provenance,
    required this.prompt,
    required this.raw,
    this.expectedFail = false,
  });

  /// Short slug identifying the case (also its file name).
  final String name;

  /// Model that produced [raw], e.g. `gemma-3n-e2b-it-int4`.
  final String model;

  /// `captured` (verbatim model output) or `synthesized` (hand-built from a
  /// documented failure mode). Honest provenance keeps the corpus trustworthy.
  final String provenance;

  /// The user prompt that elicited [raw].
  final String prompt;

  /// The model's raw response, exactly as received — fences, prose, bugs.
  final String raw;

  /// True when the repair pipeline is KNOWN not to fix this output yet.
  /// Expected-fail cases document the limits of the repair pass (and invite a
  /// contributor to fix it): the bench reports them as XFAIL instead of
  /// failing the run.
  final bool expectedFail;

  ScoreReport get score => scoreRawResponse(raw, name: name);

  factory BenchCase.fromJson(Map<String, Object?> json,
      {String? fallbackName}) {
    return BenchCase(
      name: (json['name'] as String?) ?? fallbackName ?? 'unnamed',
      model: (json['model'] as String?) ?? 'unknown',
      provenance: (json['provenance'] as String?) ?? 'synthesized',
      prompt: (json['prompt'] as String?) ?? '',
      raw: (json['raw'] as String?) ??
          (throw const FormatException(
            'bench case is missing its "raw" field',
          )),
      expectedFail: (json['expectedFail'] as bool?) ?? false,
    );
  }
}

/// Load every `*.case.json` in [directory] (recursively), sorted by path so
/// output is stable across runs and platforms.
List<BenchCase> loadBenchCases(String directory) {
  final dir = Directory(directory);
  if (!dir.existsSync()) {
    throw FileSystemException('bench corpus directory not found', directory);
  }
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.case.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      BenchCase.fromJson(
        jsonDecode(f.readAsStringSync()) as Map<String, Object?>,
        fallbackName: f.uri.pathSegments.last.replaceAll('.case.json', ''),
      ),
  ];
}

/// Aggregate per-rule repair counts across reports — a corpus-wide
/// failure-mode fingerprint.
Map<String, int> aggregateRuleCounts(Iterable<ScoreReport> reports) {
  final totals = <String, int>{};
  for (final r in reports) {
    r.log.counts.forEach((rule, n) => totals[rule] = (totals[rule] ?? 0) + n);
  }
  return totals;
}
