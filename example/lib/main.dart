// genui_min example — drive the real genui renderer with a small on-device LLM.
//
// Two modes:
//   • "Use sample output" — instantly renders a canned model response (which
//     deliberately contains a small-model mistake) so you can see the repair +
//     render with NO model download. Great for a first look.
//   • "Download model" + "Generate" — runs a real on-device Gemma model via
//     flutter_gemma. Pass --dart-define=HF_TOKEN=hf_xxx and expect a few-GB
//     download. (On iOS, large models need the increased-memory-limit
//     entitlement.)

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:genui/genui.dart';
import 'package:genui_min/genui_min.dart';

const _hfToken = String.fromEnvironment('HF_TOKEN');

// A small .task model with a large-enough context for the ~4.7k-token prompt.
const _modelUrl =
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/'
    'resolve/main/gemma-3n-E2B-it-int4.task';

// A canned model response WITH the classic small-model bug: `tip_text` is
// reused as both the Card's child and the Button's child. The repair pass
// clones it so both render correctly — demonstrating why the repair matters.
const _sampleRaw = '''
```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
{"id":"root","component":"Column","children":["tip_card","more_btn"]},
{"id":"tip_card","component":"Card","child":"tip_text"},
{"id":"tip_text","component":"Text","variant":"title","text":"Glow tip"},
{"id":"body","component":"Text","text":"Apply SPF every morning, rain or shine."},
{"id":"more_btn","component":"Button","child":"tip_text","action":{"event":{"name":"learn_more","context":{}}}}
]}}
```
''';

const _promptGallery = [
  'A card titled "Glow tip" with one short sentence and a button.',
  'A weekly habit summary card with a big percentage stat and a button.',
  'A shopping list action card with three short lines and a "Plan dinner" button.',
  'A matchday watch party card with kickoff time, neighborhood, and an RSVP button.',
  'A progress metric card with a large score, supportive copy, and a next-step button.',
];

void main() => runApp(const GenuiMinApp());

class GenuiMinApp extends StatelessWidget {
  const GenuiMinApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'genui_min',
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFFD9B36A),
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const DemoPage(),
      );
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});
  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _catalog = styledMinimalCatalog();
  late final _systemPrompt = minimalSystemPrompt(_catalog);

  // genui pipeline — rebuilt per render (flush() closes the adapter stream).
  late SurfaceController _controller = SurfaceController(catalogs: [_catalog]);
  late A2uiTransportAdapter _adapter = A2uiTransportAdapter();
  late Conversation _convo = Conversation(
    controller: _controller,
    transport: _adapter,
  );

  final _input = TextEditingController(
    text: 'A card titled "Glow tip" with one short sentence and a button.',
  );
  String _raw = '';
  String? _error;
  bool _busy = false;

  // Model state (optional live mode).
  InferenceModel? _model;
  int _progress = 0;
  String _status = '';

  void _resetPipeline() {
    try {
      _convo.dispose();
    } catch (_) {}
    _controller = SurfaceController(catalogs: [_catalog]);
    _adapter = A2uiTransportAdapter();
    _convo = Conversation(controller: _controller, transport: _adapter);
  }

  Future<void> _render(String raw) async {
    setState(() {
      _busy = true;
      _error = null;
      _raw = raw;
    });
    _resetPipeline();
    try {
      final clean = repairRawResponse(
        raw,
        surfaceId: 'main',
        catalogId: _catalog.catalogId!,
      );
      _adapter.addChunk(clean);
      await _adapter.flush();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadAndLoad() async {
    if (_hfToken.isEmpty) {
      setState(
        () => _status = 'Pass --dart-define=HF_TOKEN=hf_xxx to download.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Downloading…';
    });
    try {
      await FlutterGemma.initialize(huggingFaceToken: _hfToken);
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(_modelUrl, token: _hfToken)
          .withProgress((p) => setState(() => _progress = p))
          .install();
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 8192,
        preferredBackend: PreferredBackend.cpu,
      );
      setState(() => _status = 'Model ready.');
    } catch (e) {
      setState(() => _status = 'Model error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    final model = _model;
    if (model == null) {
      setState(() => _status = 'Download the model first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final prompt = '$_systemPrompt\n\nUser request: ${_input.text.trim()}\n'
          'Respond with ONLY the A2UI messages described above — no prose.';
      final chat = await model.createChat(temperature: .6, topK: 40, topP: .9);
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
      final res = await chat.generateChatResponse();
      await chat.close();
      final text = res is TextResponse ? res.token : res.toString();
      await _render(text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _convo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('genui_min — on-device generative UI')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _input,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Ask for a UI',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final prompt in _promptGallery)
                  ActionChip(
                    label: Text(prompt),
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() => _input.text = prompt);
                          },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _render(_sampleRaw),
                  child: const Text('Use sample output'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _downloadAndLoad,
                  child: Text(
                    _progress > 0 && _progress < 100
                        ? 'Downloading $_progress%'
                        : 'Download model',
                  ),
                ),
                FilledButton(
                  onPressed: (_busy || _model == null) ? null : _generate,
                  child: const Text('Generate'),
                ),
              ],
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_status, style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 20),
            const Text('RENDERED', style: _label),
            const SizedBox(height: 8),
            ValueListenableBuilder<ConversationState>(
              valueListenable: _convo.state,
              builder: (context, state, _) {
                if (state.surfaces.isEmpty) {
                  return const Text('— nothing rendered yet —');
                }
                return Column(
                  children: [
                    for (final id in state.surfaces)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Surface(
                            surfaceContext: _controller.contextFor(id),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Text('RAW MODEL OUTPUT', style: _label),
            const SizedBox(height: 8),
            if (_error != null)
              Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.redAccent),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.black26,
              child: SelectableText(
                _raw.isEmpty ? '—' : _raw,
                style: const TextStyle(fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _label = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
