import 'package:flutter_test/flutter_test.dart';
import 'package:genui_min/bench.dart';

void main() {
  final cases = loadBenchCases('bench/cases');

  test('corpus loads and every case repairs to a renderable tree', () {
    expect(cases, isNotEmpty);
    for (final c in cases) {
      final r = c.score;
      expect(
        r.ok,
        !c.expectedFail,
        reason: '${c.name}: ${r.failures.join('; ')}'
            '${c.expectedFail ? ' (expected-fail case now passes — drop the flag)' : ''}',
      );
    }
  });

  test('clean control output triggers only the createSurface injection', () {
    final control = cases.firstWhere((c) => c.name == 'clean-control');
    final r = control.score;
    expect(r.log.counts, {'inject:createSurface': 1});
  });

  test('captured comma-loss case recovers via brace re-balancing and pinning',
      () {
    final c = cases.firstWhere(
      (c) => c.name == 'missing-commas-between-elements',
    );
    final r = c.score;
    expect(r.log.counts,
        containsPair('json:rebalancedBraces', greaterThanOrEqualTo(1)));
    expect(r.log.counts, containsPair('surface:pinnedInventedSurfaceId', 1));
  });

  test('reused-child case fires exactly one clone', () {
    final c = cases.firstWhere((c) => c.name == 'reused-child-ref');
    final r = c.score;
    expect(r.log.counts['tree:clonedReusedChild'], 1);
    // The corpus-wide fingerprint is non-empty and stable in shape.
    expect(aggregateRuleCounts([r]).keys, everyElement(contains(':')));
  });

  test('failure-mode fingerprint aggregates across the corpus', () {
    final totals = aggregateRuleCounts(cases.map((c) => c.score));
    expect(totals['inject:createSurface'], greaterThanOrEqualTo(10));
    expect(totals.isNotEmpty, isTrue);
  });
}
