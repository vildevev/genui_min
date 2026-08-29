/// genui_min + Ollama — drive the pipeline from a local Ollama server.
///
/// Separate entrypoint (not exported by the main library) because the adapter
/// uses `dart:io` for HTTP; Flutter web apps should not import this file.
///
/// ```dart
/// final runner = OllamaRunner(model: 'gemma3:1b');
/// final raw = await runner.generate(prompt,
///     options: LlmGenerateOptions(contextSize: 8192));
/// final clean = repairRawResponse(raw,
///     surfaceId: 'main', catalogId: catalog.catalogId!);
/// ```
library;

export 'src/llm_runner.dart';
export 'src/ollama_runner.dart';
