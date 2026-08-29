// genui_min bench — score the small-model A2UI repair corpus.
//
//   flutter pub get
//   dart run tool/bench.dart [--verbose] [--json] [--filter <slug>]
//
// Exits non-zero when any case fails to repair into a renderable tree, so it
// can run in CI. See doc/bench.md for the corpus format and how to add cases.

import 'dart:convert';
import 'dart:io';

import 'package:genui_min/bench.dart';

void main(List<String> args) {
  var verbose = false, asJson = false, filter = '';
  var corpus = 'bench/cases';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--verbose' || '-v':
        verbose = true;
      case '--json':
        asJson = true;
      case '--filter':
        filter = args[++i];
      case '--corpus':
        corpus = args[++i];
      case _:
        stderr.writeln('unknown flag: ${args[i]}');
        stderr.writeln(
          'usage: dart run tool/bench.dart [--verbose] [--json] '
          '[--filter <slug>] [--corpus <dir>]',
        );
        exit(2);
    }
  }

  final cases = loadBenchCases(corpus).where((c) {
    final needle = filter.toLowerCase();
    return needle.isEmpty ||
        c.name.toLowerCase().contains(needle) ||
        c.model.toLowerCase().contains(needle);
  }).toList();
  if (cases.isEmpty) {
    stderr.writeln('no bench cases matched in $corpus');
    exit(2);
  }

  final reports = [for (final c in cases) (c, c.score)];

  if (asJson) {
    final ruleTotals = aggregateRuleCounts(reports.map((e) => e.$2));
    print(
      jsonEncode({
        'cases': [
          for (final (c, r) in reports)
            {
              'name': c.name,
              'model': c.model,
              'provenance': c.provenance,
              'ok': r.ok,
              'failures': r.failures,
              'repairs': r.log.counts,
              'rawChars': r.rawChars,
            },
        ],
        'passed': reports.where((e) => e.$2.ok).length,
        'total': reports.length,
        'ruleTotals': ruleTotals,
      }),
    );
  } else {
    print('genui_min bench — ${reports.length} case(s) from $corpus\n');
    for (final (c, r) in reports) {
      final flag = switch (r.ok) {
        true when c.expectedFail => 'XPASS', // limitation fixed — drop the flag
        false when c.expectedFail => 'XFAIL',
        _ => r.ok ? 'PASS' : 'FAIL',
      };
      print('$flag  ${c.name}  [${c.model}, ${c.provenance}]');
      print('      repairs: ${r.log}');
      if (verbose) {
        if (c.prompt.isNotEmpty) print('      prompt:  ${c.prompt}');
        for (final f in r.failures) print('      FAILURE: $f');
        print('      raw (${r.rawChars} chars):');
        for (final line in c.raw.split('\n')) {
          print('        | $line');
        }
      }
    }

    final passing = reports.where((e) => e.$2.ok).length;
    final xfail = reports.where((e) => !e.$2.ok && e.$1.expectedFail).length;
    final captured = reports.where((e) => e.$1.provenance == 'captured').length;
    print('\n$passing/${reports.length} cases repair to a renderable tree '
        '($captured captured verbatim, $xfail known-limitation XFAIL).');
    final ruleTotals = aggregateRuleCounts(reports.map((e) => e.$2));
    if (ruleTotals.isNotEmpty) {
      print('\nRepairs fired across the corpus:');
      final sorted = ruleTotals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted) {
        print('  ${e.value.toString().padLeft(4)}×  ${e.key}');
      }
    }
  }

  exitCode = reports.every((e) => e.$2.ok || e.$1.expectedFail) ? 0 : 1;
}
