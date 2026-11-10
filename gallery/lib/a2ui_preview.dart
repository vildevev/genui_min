// Renders raw A2UI text through the REAL genui_min pipeline — repair pass
// included — into a live A2uiSurface. This is not a hand-built mock of the
// components: whatever you pass in goes through exactly what a model's output
// would.

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
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
  final CatalogImplementation catalog;
  final double? height;
  final void Function(RepairLog log)? onLog;

  @override
  State<A2uiPreview> createState() => _A2uiPreviewState();
}

class _A2uiPreviewState extends State<A2uiPreview> {
  late final MessageProcessor<ComponentImplementation> _processor =
      MessageProcessor(
    catalogs: [widget.catalog],
    validationConfig: ValidationConfig.relaxed,
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
        catalogId: widget.catalog.id,
        log: log,
      );
      // Report after this frame so callers can setState safely.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onLog?.call(log));
      _processor.processMessages(extractJsonObjects(clean));
    } catch (e) {
      _error = '$e';
    }
  }

  @override
  void dispose() {
    _processor.dispose();
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
          : _processor.model.allSurfaces.isEmpty
              ? const Center(
                  child: Text('— nothing rendered —',
                      style: TextStyle(fontSize: 12)),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final surface in _processor.model.allSurfaces)
                              A2uiSurface(
                                key: ObjectKey(surface),
                                surface: surface,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
