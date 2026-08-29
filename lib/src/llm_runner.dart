// A minimal, runner-agnostic interface to an LLM.
//
// `genui_min` is deliberately renderer-only and model-agnostic: any source of
// text can drive the pipeline as long as it can complete a prompt. This
// interface is that contract — one method, plain text in, plain text out.
// Implementations shipped separately:
//
//   * `OllamaRunner` (package:genui_min/ollama.dart) — any local Ollama model;
//     great for developing the pipeline on a laptop with no phone required.
//   * flutter_gemma / MediaPipe wrappers — see the example app, which adapts
//     an on-device Gemma chat to this interface in ~15 lines.
//
// Pure Dart, no Flutter deps.

/// Sampling and output-budget knobs for a single [LlmRunner.generate] call.
///
/// Runners map these onto their native options (Ollama `options`, MediaPipe
/// sampler config, …) and ignore what they don't support.
class LlmGenerateOptions {
  const LlmGenerateOptions({
    this.temperature,
    this.topK,
    this.topP,
    this.maxTokens,
    this.contextSize,
    this.responseFormat,
    this.disableThinking,
  });

  /// Sampling temperature (typ. 0.0–1.0).
  final double? temperature;

  /// Top-K sampling size.
  final int? topK;

  /// Top-P (nucleus) sampling mass.
  final double? topP;

  /// Maximum tokens to generate for this response.
  final int? maxTokens;

  /// Total context window (prompt + response) the runner should allocate,
  /// e.g. 8192 for the minimal catalog on a small model.
  final int? contextSize;

  /// Constrained decoding: `'json'` for plain JSON mode, or a JSON Schema
  /// map (see `updateComponentsOutputSchema`) for schema-constrained output.
  /// Ignored by runners without grammar support — keep the repair pass in
  /// front of the renderer regardless.
  final Object? responseFormat;

  /// Disable reasoning/"thinking" mode on models that have one (e.g. Qwen3).
  /// Constrained decoding + long thinking traces is where small models burn
  /// their token budget, so the pipeline default is off.
  final bool? disableThinking;
}

/// A source of completions: on-device or remote, quantized or not — the
/// pipeline doesn't care.
abstract interface class LlmRunner {
  /// Human-readable runner label for logs/UI, e.g. `ollama:gemma3:2b`.
  String get name;

  /// Complete [prompt] and return the raw response text (prose, fences, and
  /// model bugs included — the repair pass cleans up after).
  Future<String> generate(String prompt, {LlmGenerateOptions? options});
}
