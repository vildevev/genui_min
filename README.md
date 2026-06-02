# genui_min

**Drive Google's [genui](https://pub.dev/packages/genui) / [A2UI](https://a2ui.org) renderer with a small, on-device LLM.**

genui is great, but its full `BasicCatalog` (18 widgets) produces a **~19,000-token system prompt**. A ~2–4B model running on a phone simply can't fit that *and* generate a response. `genui_min` makes on-device generative UI practical:

- 🪶 **A minimal, styled catalog** — `Text · Card · Button · Column` with polished, theme-aware renderers. System prompt drops to **~4,700 tokens**.
- 🩹 **A deterministic repair pass** — small models reliably make a handful of A2UI mistakes (reusing a child node, forgetting a button label, skipping `createSurface`). `genui_min` fixes them *before* rendering, so output is robust across prompts, not just lucky ones.

Proven end-to-end on **Gemma 4 E2B on an iPhone, fully offline**: on-device model → valid A2UI v0.9 → the real genui renderer → live Flutter widgets.

| | full `BasicCatalog` | `genui_min` |
|---|---|---|
| widgets | 18 | 4 |
| system prompt | ~19,350 tokens | ~4,736 tokens |
| fits a 2–4B model @ 8k ctx | ❌ | ✅ |

---

## Quick start

```dart
import 'package:genui/genui.dart';
import 'package:genui_min/genui_min.dart';

// 1. Build the catalog + system prompt.
final catalog = styledMinimalCatalog();
final systemPrompt = minimalSystemPrompt(catalog);

// 2. Generate with ANY on-device LLM (e.g. flutter_gemma). ~8k context.
final raw = await yourModel.generate(
  '$systemPrompt\n\nUser request: ${userInput}\n'
  'Respond with ONLY the A2UI messages described above.',
);

// 3. Repair the raw model output (and inject createSurface if missing).
final clean = repairRawResponse(
  raw,
  surfaceId: 'main',
  catalogId: catalog.catalogId!,
);

// 4. Feed `clean` to a FRESH genui transport (see gotcha #3), then render
//    the resulting surface with genui's `Surface` widget.
```

See [`example/`](example/) for a complete app that wires this to `flutter_gemma`, plus a zero-setup "sample output" mode.

---

## Why these pieces

### 1. The catalog is the prompt-size lever
genui builds the system prompt from the JSON schema of **every** widget in the catalog. Trim the catalog and the prompt shrinks proportionally. Four components cover most "card + actions" generative UI and bring the prompt to a size a small model can actually work with.

`styledMinimalCatalog()` ships **custom renderers** (not genui's stock Material widgets): a centered pill `Button`, a padded rounded `Card`, theme-aware `Text`, and a centered, spaced `Column`. Same A2UI component names and schemas — only the rendering is nicer.

### 2. Small models need a deterministic repair pass
Prompting alone won't stop a 2B model from occasionally reusing a component id under two parents or forgetting a button's label. `repairUpdateComponents()` makes the output safe to render:

- **Reused child references** → the shared subtree is deep-cloned so the tree is a real tree.
- **Missing / dangling child refs** → dropped; a `Button` with no usable label gets a synthesized `Text`.
- **Missing `root`** → the unreferenced top-level node is promoted (or all roots wrapped in a `Column`).
- **Required props** → `Text` without `text` gets `""`; `Button` without `action` gets a no-op event.
- Orphan components (unreachable from `root`) are dropped.

It's pure Dart and unit-tested (`test/a2ui_repair_test.dart`).

### 3. Three integration gotchas (learned the hard way)

- **Rebuild the genui transport every turn.** `A2uiTransportAdapter.flush()` permanently *closes* its input stream — reusing it throws `Bad state: Cannot add event after closing`. Create a fresh `SurfaceController` + `A2uiTransportAdapter` + `Conversation` per generation.
- **The app should create the surface, the model just fills it.** Small models reliably emit `updateComponents` but often skip the `createSurface` bootstrap. `repairRawResponse` injects `createSurface` for you if it's absent.
- **Pick the model for memory, not just quality.** A bigger context window means a bigger KV cache. On an 8 GB iPhone, **Gemma 4 E2B (2.6 GB)** runs comfortably at an 8k context; **E4B (3.7 GB)** OOMs during KV-cache allocation. Smaller model = the headroom the larger context needs.

---

## Install

```yaml
dependencies:
  genui_min: ^0.1.0
  genui: ^0.9.0
```

`genui_min` is renderer-only — bring your own on-device LLM (e.g. [`flutter_gemma`](https://pub.dev/packages/flutter_gemma)). On iOS, large-model inference needs the `com.apple.developer.kernel.increased-memory-limit` entitlement (a paid Apple Developer account).

## Run the example

```bash
cd example
flutter pub get
# Provide a Hugging Face token for the model download:
flutter run --dart-define=HF_TOKEN=hf_xxx
```

Tap **Use sample output** to see the catalog + repair + render with no model at all, or download the Gemma model and generate from a prompt.

## Acknowledgements

Built on [`genui`](https://pub.dev/packages/genui) (© The Flutter Authors, BSD-3-Clause) and the [A2UI](https://a2ui.org) protocol. MIT licensed.
