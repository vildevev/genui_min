// genui_min gallery — the component library, visualized.
//
// Every widget in `styledMinimalCatalog()` rendered through the REAL pipeline
// (A2UI JSON → repair pass → genui Surface), with the props and raw JSON that
// drive it, a live playground for pasting/editing A2UI (model optional —
// break the JSON on purpose and watch the repair log), and composed examples.
//
// Web-friendly and model-free: `flutter run` (or build for web and host).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:genui_min/genui_min.dart';

import 'a2ui_preview.dart';
import 'catalog_info.dart';

void main() => runApp(const GalleryApp());

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'genui_min gallery',
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFFD9B36A),
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const GalleryHome(),
      );
}

class GalleryHome extends StatelessWidget {
  const GalleryHome({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = styledMinimalCatalog();
    final promptChars = minimalSystemPrompt(catalog).length;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('genui_min — component gallery'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Components'),
              Tab(text: 'Playground'),
              Tab(text: 'Examples'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ComponentsTab(catalog: catalog, promptChars: promptChars),
            const PlaygroundTab(),
            ExamplesTab(catalog: catalog),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Components

class ComponentsTab extends StatelessWidget {
  const ComponentsTab({
    super.key,
    required this.catalog,
    required this.promptChars,
  });

  final Catalog catalog;
  final int promptChars;

  @override
  Widget build(BuildContext context) {
    final library = componentLibrary(catalog);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Every component in the minimal catalog, rendered through the real '
          'pipeline. 5 widgets → a system prompt of roughly '
          '${(promptChars / 4000).toStringAsFixed(1)}k tokens that fits a '
          '2–4B on-device model.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Every component also carries the implicit props id (unique; one '
          'component uses "root") and component (its type name). "?" marks '
          'optional props.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        for (final info in library) ...[
          _ComponentCard(info: info, catalog: catalog),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _ComponentCard extends StatelessWidget {
  const _ComponentCard({required this.info, required this.catalog});

  final ComponentInfo info;
  final Catalog catalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  info.name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    info.description,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final v in info.variants)
                  SizedBox(
                    width: 240,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v.label,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(letterSpacing: .5),
                        ),
                        const SizedBox(height: 6),
                        A2uiPreview(raw: v.raw, catalog: catalog, height: 210),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in info.props)
                  InputChip(
                    label: Text(
                      p.name + (p.required ? '' : '?'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    tooltip: p.enumValues != null
                        ? '${p.description}\nenum: ${p.enumValues!.join(" | ")}'
                        : p.description,
                  ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                'A2UI JSON · ${info.variants.first.label}',
                style: theme.textTheme.labelSmall,
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  color: Colors.black26,
                  child: SelectableText(
                    _pretty(info.variants.first.raw),
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Playground

class PlaygroundTab extends StatefulWidget {
  const PlaygroundTab({super.key});

  @override
  State<PlaygroundTab> createState() => _PlaygroundTabState();
}

class _PlaygroundTabState extends State<PlaygroundTab> {
  final _catalog = styledMinimalCatalog();
  final _input = TextEditingController(text: playgroundSeed);
  String _raw = '';
  String _repairs = '';
  String? _error;
  var _renderKey = 0;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _render() {
    final log = RepairLog();
    try {
      // Repair here (not inside the preview) so the log reflects the user's
      // input; the preview's own repair pass is idempotent on clean input.
      repairRawResponse(
        _input.text,
        surfaceId: 'main',
        catalogId: _catalog.catalogId!,
        log: log,
      );
      setState(() {
        _raw = _input.text;
        _repairs = log.toString();
        _error = null;
        _renderKey++;
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Paste or edit A2UI — model optional. This runs the exact repair '
          'pass + renderer a model response would go through; break the JSON '
          'on purpose and watch the repair log explain what was fixed. The '
          "seed contains the classic \"button reuses the card's text\" bug.",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          maxLines: 10,
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Raw A2UI (fences and bugs allowed)',
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(onPressed: _render, child: const Text('Render')),
            OutlinedButton(
              onPressed: () => setState(() => _input.text = playgroundSeed),
              child: const Text('Reset seed'),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text('Error: $_error',
              style: const TextStyle(color: Colors.redAccent)),
        ],
        if (_raw.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('RENDERED', style: _label),
          if (_repairs.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('repairs: $_repairs', style: _mono),
          ],
          const SizedBox(height: 8),
          A2uiPreview(
            key: ValueKey(_renderKey),
            raw: _raw,
            catalog: _catalog,
            height: 320,
          ),
        ],
      ],
    );
  }
}

// ----------------------------------------------------------------- Examples

class ExamplesTab extends StatelessWidget {
  const ExamplesTab({super.key, required this.catalog});

  final Catalog catalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Composed cards in the shape the catalog is designed for: a '
          'message, a metric, an action — all generated trees.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final e in galleryExamples) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(e.title, style: theme.textTheme.titleMedium),
                      const SizedBox(width: 10),
                      Text(e.subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 12),
                  A2uiPreview(raw: e.raw, catalog: catalog, height: 360),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('A2UI JSON', style: theme.textTheme.labelSmall),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        color: Colors.black26,
                        child: SelectableText(
                          _pretty(e.raw),
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

String _pretty(String rawJson) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(rawJson));
  } catch (_) {
    return rawJson;
  }
}

const _label = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
const _mono = TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.4);
