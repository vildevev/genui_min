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
  });

  testWidgets('streaming runner assembles chunks and reports progress', (
    tester,
  ) async {
    final key = GlobalKey<GenuiMinSurfaceState>();
    final chunks = <String>[];
    // The stream stays open after its chunks (the gate never completes), so
    // the test ends while the generation is in flight: awaiting the full
    // generate and pumping afterwards deadlocks the FakeAsync frame
    // pipeline. Chunk assembly and callbacks are what's under test here;
    // the final repaired render is covered by the raw-render tests.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenuiMinSurface(
            key: key,
            runner: _GatedStreamRunner(),
            onChunk: chunks.add,
          ),
        ),
      ),
    );

    unawaited(key.currentState!.generate('a streaming card'));
    // Chunks flow through microtasks (and the parser) — give the real event
    // loop a window to deliver them; no pumping needed.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(chunks, hasLength(greaterThan(1)));
    expect(chunks.join(), _GatedStreamRunner.response);
    expect(key.currentState!.isBusy, isTrue);
    await expectLater(
      () => key.currentState!.generate('two'),
      throwsA(isA<StateError>()),
    );
  });

  testWidgets('history feeds taps into the next prompt', (tester) async {
    final key = GlobalKey<GenuiMinSurfaceState>();
    final runner = _GatedRecordingRunner();
    // Turn 1 renders through the raw path (harness-friendly): its button tap
    // lands in the surface's history.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GenuiMinSurface(key: key, raw: _rawWithBug)),
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    // Swap in the gated recording runner (same GlobalKey → same state, same
    // history) and ask for the next turn. The prompt is recorded
    // synchronously when generate() is called; the generation then stays in
    // flight for the rest of the test.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GenuiMinSurface(key: key, runner: runner)),
      ),
    );
    unawaited(key.currentState!.generate('another card'));

    expect(runner.prompts, hasLength(1));
    expect(runner.prompts.single, contains('Conversation so far'));
    expect(runner.prompts.single, contains('user tapped button "go"'));
    expect(runner.prompts.single, contains('User request: another card'));
  });
}

/// The full A2UI response, streamed in small chunks and then held open
/// forever — the generation never completes.
class _GatedStreamRunner implements LlmRunner, LlmStreamRunner {
  static const response = '''
```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
{"id":"root","component":"Text","text":"Streamed"}]}}
```
''';

  @override
  String get name => 'gated-stream';

  @override
  Future<String> generate(
    String prompt, {
    LlmGenerateOptions? options,
  }) async =>
      response;

  @override
  Stream<String> streamGenerate(
    String prompt, {
    LlmGenerateOptions? options,
  }) async* {
    for (var i = 0; i < response.length; i += 12) {
      yield response.substring(i, (i + 12).clamp(0, response.length));
    }
    // Hold the stream open: completing it would run the render/flush chain,
    // which cannot be awaited under FakeAsync (see the busy-guard test).
    await Completer<void>().future;
  }
}

/// A runner that records every prompt synchronously, then never answers.
class _GatedRecordingRunner implements LlmRunner {
  final prompts = <String>[];

  @override
  String get name => 'gated-recording';

  @override
  Future<String> generate(
    String prompt, {
    LlmGenerateOptions? options,
  }) async {
    prompts.add(prompt);
    await Completer<void>().future;
    return '';
  }
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
