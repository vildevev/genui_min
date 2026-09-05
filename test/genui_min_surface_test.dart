import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui_min/genui_min.dart';

const _rawWithBug = '''
```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
{"id":"root","component":"Column","children":["t","b"]},
{"id":"t","component":"Text","variant":"title","text":"Glow tip"},
{"id":"b","component":"Button","child":"l","action":{"event":{"name":"go","context":{}}}},
{"id":"l","component":"Text","text":"Go"}
]}}
```
''';

/// The repair/flush path runs on the real event loop (stream closes, parser
/// transformer, broadcast done events) and never settles under FakeAsync on
/// its own — a short real-async window plus a settle is required.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders repaired raw output and reports the repair log', (
    tester,
  ) async {
    RepairLog? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenuiMinSurface(
            raw: _rawWithBug,
            onRepair: (log) => reported = log,
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('Glow tip'), findsOneWidget);
    expect(find.text('Go'), findsOneWidget);
    expect(reported, isNotNull);
    expect(reported!.counts['inject:createSurface'], 1);
  });

  testWidgets('onAction fires when a generated button is tapped', (
    tester,
  ) async {
    final actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenuiMinSurface(
            raw: _rawWithBug,
            onAction: (action) => actions.add(action.name),
          ),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(actions, ['go']);
  });

  testWidgets('re-renders when raw changes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenuiMinSurface(raw: _rawWithBug),
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('Glow tip'), findsOneWidget);

    const replaced = '''
```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
{"id":"root","component":"Text","text":"Replaced"}]}}
```
''';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GenuiMinSurface(raw: replaced)),
      ),
    );
    await _settle(tester);
    expect(find.text('Replaced'), findsOneWidget);
    expect(find.text('Glow tip'), findsNothing);
  });

  testWidgets('generate without a runner surfaces a clear contract error', (
    tester,
  ) async {
    final key = GlobalKey<GenuiMinSurfaceState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GenuiMinSurface(key: key)),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      () => key.currentState!.generate('x'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('without a runner'),
        ),
      ),
    );
  });

  testWidgets('generate throws while a generation is already in flight', (
    tester,
  ) async {
    final key = GlobalKey<GenuiMinSurfaceState>();
    // The gate is never opened, so the generation stays in flight for the
    // whole test — no render/flush runs, keeping the test free of the
    // FakeAsync-unfriendly transport teardown.
    final gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenuiMinSurface(
            key: key,
            runner: _GatedRunner(gate),
          ),
        ),
      ),
    );

    // Leave the generation deliberately in flight (the gate never opens):
    // awaiting it would run the render/flush chain, which never completes
    // under FakeAsync. The guard behavior is what's under test here.
    unawaited(key.currentState!.generate('one'));
    expect(key.currentState!.isBusy, isTrue);
    await expectLater(
      () => key.currentState!.generate('two'),
      throwsA(isA<StateError>()),
    );
    expect(key.currentState!.isBusy, isTrue);
    // Leave `first` deliberately in flight (the gate never opens): awaiting
    // it would run the render/flush chain, which never completes under
    // FakeAsync. The guard behavior is what's under test here.
  });
}

/// A runner whose future is held open by [gate] so a generation can be
/// observed while in flight.
class _GatedRunner implements LlmRunner {
  _GatedRunner(this._gate);

  final Completer<void> _gate;

  @override
  String get name => 'gated';

  @override
  Future<String> generate(
    String prompt, {
    LlmGenerateOptions? options,
  }) async {
    await _gate.future;
    return '''
```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
{"id":"root","component":"Text","text":"Done"}]}}
```
''';
  }
}
