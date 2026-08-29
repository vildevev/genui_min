// genui_min live check — run one prompt through a LOCAL Ollama model, twice:
// unconstrained vs schema-constrained, both scored by the bench scorer.
//
//   ollama serve                       # needs a running Ollama
//   flutter pub get
//   dart run tool/live_check.dart [model] [prompt]
//
// Defaults: qwen3:4b and the weekly-summary gallery prompt. This is a manual
// dev utility (unlike tool/bench.dart it needs a live model server), handy
// for capturing new corpus cases and sanity-checking the constrained schema
// against models you actually run.

import 'dart:convert';
import 'dart:io';

import 'package:genui_min/bench.dart';
import 'package:genui_min/ollama.dart';

const defaultPrompt = 'A weekly habit summary card with a big percentage '
    'stat and a button.';

Future<void> main(List<String> args) async {
  final model = args.isNotEmpty ? args.first : 'qwen3:4b';
  final prompt = args.length > 1 ? args.sublist(1).join(' ') : defaultPrompt;

  final models = await OllamaRunner.listModels();
  if (!models.contains(model)) {
    stderr.writeln('model "$model" not in local Ollama ($models)');
    exitCode = 2;
    return;
  }

  final schema = jsonDecode(
    File('grammar/a2ui-min.schema.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final runner = OllamaRunner(model: model);

  Future<void> run(String label, LlmGenerateOptions options) async {
    print('=== $label ($model) ===');
    final raw = await runner.generate(
      'You generate A2UI v0.9 updateComponents messages for a Flutter card '
      'UI. Components form a flat list with unique ids; exactly one has id '
      '"root"; children are referenced by id; a Button has its own Text '
      'label.\n\nUser request: $prompt\n\nRespond with ONLY the A2UI JSON '
      'message.',
      options: options,
    );
    print(raw);
    final r = scoreRawResponse(raw, name: label.toLowerCase());
    print('renderable: ${r.ok}  failures: ${r.failures}');
    print('repairs:    ${r.log}\n');
  }

  await run(
    'UNCONSTRAINED',
    const LlmGenerateOptions(contextSize: 4096, temperature: .6),
  );
  await run(
    'SCHEMA-CONSTRAINED',
    LlmGenerateOptions(
      contextSize: 4096,
      temperature: .6,
      disableThinking: true,
      responseFormat: schema,
    ),
  );
}
