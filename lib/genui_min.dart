/// genui_min — drive the A2UI Flutter renderer
/// ([a2ui_flutter](https://pub.dev/packages/a2ui_flutter)) with a small
/// **on-device** LLM.
///
/// The full A2UI basic catalog (18 widgets) needs a ~9,750-token system
/// prompt — far beyond what a ~2–4B on-device model can fit. genui_min makes
/// generative UI practical on small models with four pieces:
///
///  - [styledMinimalCatalog] — a 5-widget catalog (Text · Card · Button ·
///    Column · Stat) with polished, theme-aware renderers. ~2,700-token prompt.
///  - [repairRawResponse] / [repairUpdateComponents] — a deterministic repair
///    pass that fixes the mistakes small models reliably make (reused child
///    refs, missing button labels, missing root/createSurface, dangling refs)
///    before the output reaches the renderer, with [RepairLog] telemetry of
///    exactly which rules fired.
///  - [LlmRunner] — a one-method model interface, plus an Ollama adapter
///    (`package:genui_min/ollama.dart`) for laptop development without a
///    phone.
///  - [updateComponentsOutputSchema] / [updateComponentsGbnf] — constrained
///    decoding derived from the catalog: hand the schema to Ollama's
///    structured outputs or the grammar to any llama.cpp sampler, and
///    invalid A2UI becomes unrepresentable.
///
/// ## Recipe (proven on Gemma 4 E2B, on an iPhone, fully offline)
///
/// 1. Build the catalog + system prompt:
///    ```dart
///    final catalog = styledMinimalCatalog();
///    final systemPrompt = minimalSystemPrompt(catalog);
///    ```
/// 2. Generate with any on-device LLM (≈8k context recommended) — e.g.
///    `flutter_gemma`. Prefix the user request with [systemPrompt].
/// 3. Repair the raw output:
///    ```dart
///    final clean = repairRawResponse(raw, surfaceId: 'main',
///        catalogId: catalog.id);
///    ```
/// 4. Feed `extractJsonObjects(clean)` to a **fresh** `a2ui_core`
///    `MessageProcessor` each turn (each turn creates the surface again, and
///    a second `createSurface` for the same surface is an error), and render
///    its surfaces with `A2uiSurface`.
///
/// See `example/` for a complete, runnable demo and `doc/bench.md` for the
/// repair-scoring corpus (`dart run tool/bench.dart`).
library;

export 'src/a2ui_repair.dart';
export 'src/constrained.dart';
export 'src/gbnf.dart';
export 'src/genui_min_surface.dart';
export 'src/llm_runner.dart';
export 'src/styled_catalog.dart';
