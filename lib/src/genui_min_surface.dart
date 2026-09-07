// The five-line integration: one widget that absorbs every "gotcha" from the
// docs. Render raw model output directly (`raw:`), or hand it an `LlmRunner`
// and drive it with `generate()` via a GlobalKey. It rebuilds the genui
// transport per turn (flush() closes the stream), injects/repairs via
// `repairRawResponse`, renders through a real Surface, and reports button
// taps (`onAction`), streamed chunks (`onChunk`), repairs (`onRepair`), and
// failures (`onError`). Runners that also implement `LlmStreamRunner` get a
// live preview while the model writes; past requests and taps feed the next
// prompt (multi-turn).

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

import 'llm_runner.dart';
import 'styled_catalog.dart';
import 'a2ui_repair.dart';

/// A ready-made generative-UI surface driven by small-model A2UI output.
///
/// ```dart
/// final _surfaceKey = GlobalKey<GenuiMinSurfaceState>();
///
/// GenuiMinSurface(
///   key: _surfaceKey,
///   runner: OllamaRunner(model: 'qwen3:4b'),   // or flutter_gemma-backed
///   onAction: (action) => print('tap: ${action.name}'),
///   onRepair: (log) => analytics('repairs', log.counts),
/// )
/// // …
/// await _surfaceKey.currentState!.generate('A weekly summary card');
/// ```
///
/// Or, when you already hold the model's raw text, skip the runner entirely:
///
/// ```dart
/// GenuiMinSurface(raw: modelOutput)
/// ```
///
/// If [runner] also implements [LlmStreamRunner], [generate] streams the
/// response into a live preview as it is written (with [onChunk] per chunk);
/// the final repaired render replaces the preview. Previous requests and
/// tapped buttons are folded into each prompt — see [maxHistoryTurns].
class GenuiMinSurface extends StatefulWidget {
  const GenuiMinSurface({
    super.key,
    this.raw,
    this.runner,
    this.catalog,
    this.surfaceId = 'main',
    this.generateOptions,
    this.onAction,
    this.onChunk,
    this.onRepair,
    this.onError,
    this.padding = const EdgeInsets.all(16),
    this.emptyPlaceholder,
    this.maxHistoryTurns = 8,
  }) : assert(
          raw == null || runner == null,
          'Provide raw model output OR a runner to generate with, not both.',
        );

  /// Raw model output to render (fences, prose and bugs welcome — it is
  /// repaired first). When null, drive the surface with
  /// [GenuiMinSurfaceState.generate].
  final String? raw;

  /// The model to generate with. Required only for [GenuiMinSurfaceState].
  final LlmRunner? runner;

  /// Catalog to render with (and build the prompt from). Defaults to
  /// [styledMinimalCatalog].
  final Catalog? catalog;

  /// A2UI surface id. One surface per widget; defaults to 'main'.
  final String surfaceId;

  /// Sampling/context options forwarded to [LlmRunner.generate].
  final LlmGenerateOptions? generateOptions;

  /// A Button inside the generated UI was tapped. Fires once per tap with
  /// the event the model attached to that button.
  final void Function(UserActionEvent action)? onAction;

  /// A chunk of the model's response arrived while streaming (the runner
  /// implements [LlmStreamRunner]). Fires during [generate], before the
  /// repaired render.
  final void Function(String chunk)? onChunk;

  /// The repair pass ran on the last render — [RepairLog.counts] says which
  /// rules fired. Zero entries means the model output was already clean.
  final void Function(RepairLog log)? onRepair;

  /// Generation or rendering failed. The error is also shown above the
  /// surface's previous content, which is kept.
  final void Function(Object error)? onError;

  /// Padding around the rendered surface.
  final EdgeInsetsGeometry padding;

  /// Shown before the first successful render.
  final Widget? emptyPlaceholder;

  /// How many past requests/taps to fold into each [generate] prompt
  /// (multi-turn). Every entry spends the small model's context, so keep
  /// this tight; `clearHistory()` resets the conversation. Prompt growth
  /// from history is on top of [catalogPromptTokens]'s system-prompt cost.
  final int maxHistoryTurns;

  @override
  State<GenuiMinSurface> createState() => GenuiMinSurfaceState();
}

class GenuiMinSurfaceState extends State<GenuiMinSurface> {
  late final Catalog _catalog = widget.catalog ?? styledMinimalCatalog();

  late SurfaceController _controller = SurfaceController(catalogs: [_catalog]);
  late A2uiTransportAdapter _adapter = A2uiTransportAdapter();
  late Conversation _convo = Conversation(
    controller: _controller,
    transport: _adapter,
  );
  StreamSubscription<ChatMessage>? _actions;
  Object? _error;
  var _busy = false;

  /// Multi-turn transcript: user requests and tapped buttons, oldest first.
  final ListQueue<String> _history = ListQueue<String>();

  @override
  void initState() {
    super.initState();
    _listenForActions();
    final raw = widget.raw;
    if (raw != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => render(raw));
    }
  }

  @override
  void didUpdateWidget(covariant GenuiMinSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.raw != null && widget.raw != oldWidget.raw && !_busy) {
      render(widget.raw!);
    }
  }

  void _listenForActions() {
    // Button taps come back as ChatMessages carrying a UiInteractionPart;
    // unwrap the UserActionEvent map for the app.
    _actions = _controller.onSubmit.listen((message) {
      for (final part in message.parts.uiInteractionParts) {
        try {
          final payload = jsonDecode(part.interaction);
          final action = payload is Map ? payload['action'] : null;
          if (action is! Map) continue;
          final context = action['context'] is Map
              ? Map<String, Object?>.from(action['context'] as Map)
              : <String, Object?>{};
          widget.onAction?.call(
            UserActionEvent(
              surfaceId: action['surfaceId'] as String?,
              name: (action['name'] ?? '').toString(),
              sourceComponentId: (action['sourceComponentId'] ?? '').toString(),
              context: context,
            ),
          );
          _remember('user tapped button "${(action['name'] ?? '').toString()}"'
              '${context.isEmpty ? '' : ' with ${jsonEncode(context)}'}');
        } catch (_) {
          // A malformed interaction part should never break the surface.
        }
      }
    });
  }

  /// Append to the transcript, dropping the oldest turns past
  /// [GenuiMinSurface.maxHistoryTurns].
  void _remember(String turn) {
    if (widget.maxHistoryTurns <= 0) return;
    _history.addLast(turn);
    while (_history.length > widget.maxHistoryTurns) {
      _history.removeFirst();
    }
  }

  /// Forget all past requests and taps — the next [generate] starts fresh.
  void clearHistory() => _history.clear();

  /// Whether a [generate] call is in flight.
  bool get isBusy => _busy;

  /// Generate with the configured [GenuiMinSurface.runner] and render the
  /// result. Returns the raw model text (also available for debugging).
  /// Throws [StateError] if a generation is already in flight or the widget
  /// was created without a runner. If the runner implements
  /// [LlmStreamRunner], chunks stream into a live preview as they arrive and
  /// [GenuiMinSurface.onChunk] fires per chunk; the final repaired render
  /// replaces the preview.
  Future<String> generate(String userRequest) async {
    if (_busy) {
      throw StateError(
        'GenuiMinSurface is already generating — check `isBusy` before '
        'calling `generate` again.',
      );
    }
    final runner = widget.runner;
    if (runner == null) {
      throw StateError(
        'GenuiMinSurface was created without a runner — pass `raw:` to render '
        'existing text, or provide `runner:` to generate.',
      );
    }
    _remember('user: $userRequest');
    final prompt = _buildPrompt(userRequest);
    _busy = true;
    try {
      final String raw;
      if (runner case final LlmStreamRunner streamRunner) {
        raw = await _generateStreaming(streamRunner, prompt);
      } else {
        raw = await runner.generate(prompt, options: widget.generateOptions);
      }
      await render(raw);
      return raw;
    } finally {
      _busy = false;
    }
  }

  /// The system prompt plus the multi-turn transcript plus this turn's ask.
  String _buildPrompt(String userRequest) {
    final prompt = StringBuffer(minimalSystemPrompt(_catalog));
    if (_history.isNotEmpty) {
      prompt
        ..writeln()
        ..writeln()
        ..writeln(
          'Conversation so far (regenerate the FULL surface each turn):',
        )
        ..writeAll(_history.map((turn) => '- $turn'), '\n');
    }
    prompt
      ..writeln()
      ..writeln()
      ..writeln('User request: $userRequest')
      ..write(
          'Respond with ONLY the A2UI messages described above — no prose.');
    return prompt.toString();
  }

  /// Stream the response into a live preview transport while the model
  /// writes, so users see something in seconds instead of tens of seconds.
  /// The caller then runs the normal repaired [render], which replaces the
  /// (unrepaired) preview.
  Future<String> _generateStreaming(
      LlmStreamRunner runner, String prompt) async {
    final buffer = StringBuffer();
    _freshConversation();
    setState(() => _error = null);
    try {
      await for (final chunk
          in runner.streamGenerate(prompt, options: widget.generateOptions)) {
        buffer.write(chunk);
        _adapter.addChunk(chunk);
        widget.onChunk?.call(chunk);
      }
      await _adapter.flush();
    } catch (e) {
      setState(() => _error = e);
      widget.onError?.call(e);
    }
    return buffer.toString();
  }

  /// Tear down and rebuild the transport trio. The transport's flush()
  /// closes its input stream — a fresh controller/adapter/conversation per
  /// render is required, not optional.
  void _freshConversation() {
    _actions?.cancel();
    _actions = null;
    _convo.dispose();
    _adapter.dispose();
    _controller.dispose();
    _controller = SurfaceController(catalogs: [_catalog]);
    _adapter = A2uiTransportAdapter();
    _convo = Conversation(controller: _controller, transport: _adapter);
    _listenForActions();
  }

  /// Repair and render [raw] model output, replacing whatever was shown.
  Future<void> render(String raw) async {
    _freshConversation();
    // Clear the error only after the new conversation is wired up: the build
    // triggered from here (e.g. via didUpdateWidget) must observe the new
    // conversation's state, not re-read the disposed one.
    setState(() => _error = null);
    try {
      final log = RepairLog();
      final clean = repairRawResponse(
        raw,
        surfaceId: widget.surfaceId,
        catalogId: _catalog.catalogId!,
        log: log,
      );
      widget.onRepair?.call(log);
      _adapter.addChunk(clean);
      await _adapter.flush();
    } catch (e) {
      setState(() => _error = e);
      widget.onError?.call(e);
    }
  }

  @override
  void dispose() {
    _actions?.cancel();
    _convo.dispose();
    _adapter.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: ValueListenableBuilder<ConversationState>(
        valueListenable: _convo.state,
        builder: (context, state, _) {
          final surfaces = state.surfaces.toList();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Render failures don't wipe the last good surface — the error
              // is shown above the kept content.
              if (_error != null)
                Text(
                  'render error: $_error',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              for (final id in surfaces)
                Surface(surfaceContext: _controller.contextFor(id)),
              if (_error == null && surfaces.isEmpty)
                widget.emptyPlaceholder ?? const SizedBox.shrink(),
            ],
          );
        },
      ),
    );
  }
}
