/// genui_min — drive Google's [genui](https://pub.dev/packages/genui) / A2UI
/// renderer with a small **on-device** LLM.
///
/// The full genui `BasicCatalog` (18 widgets) needs a ~19,000-token system
/// prompt — far beyond what a ~2–4B on-device model can fit. genui_min makes
/// generative UI practical on small models with two pieces:
///
///  - [styledMinimalCatalog] — a 4-widget catalog (Text · Card · Button ·
///    Column) with polished, theme-aware renderers. ~4,700-token prompt.
///  - [repairRawResponse] / [repairUpdateComponents] — a deterministic repair
///    pass that fixes the mistakes small models reliably make (reused child
///    refs, missing button labels, missing root/createSurface, dangling refs)
///    before the output reaches the renderer.
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
///        catalogId: catalog.catalogId!);
///    ```
/// 4. Feed `clean` to a **fresh** genui transport each turn (the transport's
///    `flush()` closes its stream — rebuild controller/adapter/Conversation
///    per generation).
///
/// See `example/` for a complete, runnable demo.
library;

export 'src/a2ui_repair.dart';
export 'src/styled_catalog.dart';
