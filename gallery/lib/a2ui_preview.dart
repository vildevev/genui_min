// Renders raw A2UI text through the REAL genui_min pipeline — repair pass
// included — into a live Surface. This is not a hand-built mock of the
// components: whatever you pass in goes through exactly what a model's output
// would.

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:genui_min/genui_min.dart';

class A2uiPreview extends StatefulWidget {
  const A2uiPreview({
    super.key,
    required this.raw,
    required this.catalog,
    this.height,
    this.onLog,
  });

  /// Raw A2UI text (fences/prose/bugs allowed — it gets repaired).
  final String raw;
  final Catalog catalog;
  final double? height;
  final void Function(RepairLog log)? onLog;

  @override
  State<A2uiPreview> createState() => _A2uiPreviewState();
}

class _A2uiPreviewState extends State<A2uiPreview> {
  late final SurfaceController _controller = SurfaceController(
    catalogs: [widget.catalog],
  );
  late final A2uiTransportAdapter _adapter = A2uiTransportAdapter();
  late final Conversation _convo = Conversation(
    controller: _controller,
    transport: _adapter,
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    final log = RepairLog();
    try {
      final clean = repairRawResponse(
        widget.raw,
        surfaceId: 'main',
        catalogId: widget.catalog.catalogId!,
        log: log,
      );
      // Report after this frame so callers can setState safely.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onLog?.call(log));
      _adapter.addChunk(clean);
      _adapter.flush().catchError((Object e) {
        if (mounted) setState(() => _error = '$e');
      });
    } catch (e) {
      _error = '$e';
    }
  }

  @override
  void dispose() {
    _convo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: widget.height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: .35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: .5),
        ),
      ),
      child: _error != null
          ? Text('render error: $_error',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12))
          : ValueListenableBuilder<ConversationState>(
              valueListenable: _convo.state,
              builder: (context, state, _) {
                if (state.surfaces.isEmpty) {
                  return const Center(
                    child: Text('— nothing rendered —',
                        style: TextStyle(fontSize: 12)),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final id in state.surfaces)
                              Surface(
                                surfaceContext: _controller.contextFor(id),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
