// LlmRunner backed by a local Ollama server (https://ollama.com).
//
// The laptop-and-no-phone development path for the genui_min pipeline: any
// Ollama model (gemma3:1b, llama3.2:3b, qwen2.5:3b, …) drives the exact same
// catalog → generate → repair → render flow as the on-device flutter_gemma
// backend. Ollama also supports schema-constrained decoding (`format`), so
// `responseFormat: updateComponentsOutputSchema(catalog)` makes invalid A2UI
// unrepresentable at the source — the repair pass stays as a safety net.
//
// Uses dart:io directly to keep the package dependency-free, which means this
// file is NOT web-compatible — that's why it hangs off its own entrypoint
// (`package:genui_min/ollama.dart`) rather than the main library export.

import 'dart:convert';
import 'dart:io';

import 'llm_runner.dart';

/// An [LlmRunner] talking to a local Ollama daemon over its HTTP API.
final class OllamaRunner implements LlmRunner {
  OllamaRunner({this.host = 'http://127.0.0.1:11434', required this.model});

  /// Base URL of the Ollama server, e.g. `http://127.0.0.1:11434`.
  final String host;

  /// Ollama model tag, e.g. `gemma3:1b` or `qwen2.5:3b:q4_K_M`.
  final String model;

  @override
  String get name => 'ollama:$model';

  /// Models installed on the server (`ollama pull …`), by tag.
  static Future<List<String>> listModels({
    String host = 'http://127.0.0.1:11434',
  }) async {
    final body = await _getJson(Uri.parse('$host/api/tags'), host: host);
    final models = body['models'];
    if (models is! List) return const [];
    return [
      for (final m in models)
        if (m is Map && m['name'] is String) m['name'] as String,
    ];
  }

  @override
  Future<String> generate(String prompt, {LlmGenerateOptions? options}) async {
    final options_ = options ?? const LlmGenerateOptions();
    final body = {
      'model': model,
      'prompt': prompt,
      'stream': false,
      if (options_.responseFormat is String || options_.responseFormat is Map)
        'format': options_.responseFormat,
      if (options_.disableThinking case final think?) 'think': !think,
      'options': {
        if (options_.temperature case final t?) 'temperature': t,
        if (options_.topK case final k?) 'top_k': k,
        if (options_.topP case final p?) 'top_p': p,
        if (options_.maxTokens case final m?) 'num_predict': m,
        if (options_.contextSize case final c?) 'num_ctx': c,
      },
    };

    final res = await _postJson(
      Uri.parse('$host/api/generate'),
      body,
      host: host,
    );
    final text = res['response'];
    if (text is! String || text.isEmpty) {
      throw StateError(
        'Ollama returned no response text '
        '(done_reason: ${res["done_reason"]}; thinking model? '
        'try disableThinking: true) — keys: ${res.keys.toList()}',
      );
    }
    return text;
  }
}

Future<Map<String, Object?>> _getJson(Uri uri, {required String host}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final res = await client.getUrl(uri).then((r) => r.close());
    return _decode(res, host);
  } on SocketException catch (e) {
    throw SocketException(
      'could not reach Ollama at $host — is `ollama serve` running?',
      address: e.address,
      port: e.port,
    );
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _postJson(
  Uri uri,
  Map<String, Object?> body, {
  required String host,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close().timeout(const Duration(minutes: 4));
    return _decode(res, host);
  } on SocketException catch (e) {
    throw SocketException(
      'could not reach Ollama at $host — is `ollama serve` running?',
      address: e.address,
      port: e.port,
    );
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _decode(
  HttpClientResponse res,
  String host,
) async {
  final text = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) {
    final err = text.length > 300 ? '${text.substring(0, 300)}…' : text;
    throw HttpException('Ollama at $host returned ${res.statusCode}: $err');
  }
  final decoded = jsonDecode(text);
  if (decoded is Map<String, Object?>) return decoded;
  if (decoded is Map) return Map<String, Object?>.from(decoded);
  throw FormatException(
    'unexpected Ollama response: '
    '${text.substring(0, text.length.clamp(0, 200))}',
  );
}
