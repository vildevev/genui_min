# Constrained decoding: making invalid A2UI unrepresentable

The repair pass fixes small-model mistakes *after* generation. Constrained
decoding prevents them *at generation*: the sampler is only allowed to emit
JSON that matches the output contract, so malformed JSON, unknown component
types, missing `id`s, and invented enum values simply cannot occur.

genui_min derives that contract from the **same catalog** that builds the
system prompt — one source of truth, three artifacts:

| API | What it's for |
|---|---|
| `updateComponentsOutputSchema(catalog)` | JSON Schema (map) |
| `updateComponentsGbnf(catalog)` | GBNF grammar (llama.cpp family) |
| `grammar/a2ui-min.schema.json`, `grammar/a2ui-min.gbnf` | pre-generated copies of both |

The schema asks for **one `updateComponents` message** (an object root — the
shape Ollama's structured outputs prefer). `createSurface` is injected
deterministically by `repairRawResponse`, so the model never wastes tokens
on it.

## With Ollama (one line)

```dart
final catalog = styledMinimalCatalog();
final runner = OllamaRunner(model: 'qwen3:4b');   // package:genui_min/ollama.dart

final raw = await runner.generate(
  prompt,
  options: LlmGenerateOptions(
    contextSize: 8192,
    disableThinking: true,               // thinking models: keep the budget
    responseFormat: updateComponentsOutputSchema(catalog),
  ),
);
final clean = repairRawResponse(raw,
    surfaceId: 'main', catalogId: catalog.catalogId!);  // safety net
```

**Verified live** (see `doc/proof.md` for the on-device story): qwen3:4b
unconstrained produced undecodable JSON (`,"{"` stray-quote bug — captured
as an XFAIL bench case); the same model with the schema emitted a perfect
flat component tree and scored `renderable: true` with zero semantic
repairs. Constrained decoding fixes *structure*; the system prompt still
drives *content* — you want both.

## With llama.cpp / LM Studio

Hand the grammar file to any GBNF-capable sampler:

```bash
llama-cli -m model.gguf --grammar-file grammar/a2ui-min.gbnf -p "$PROMPT"
```

Or generate it yourself for a custom catalog:

```dart
updateComponentsGbnf(catalog);   // String, ready for --grammar-file
```

## Keeping the artifacts honest

`grammar/` is generated, and `test/constrained_test.dart` fails if it drifts
from the catalog. After changing the catalog, regenerate:

```bash
GENUI_MIN_REGEN=1 flutter test test/constrained_test.dart
```

The test also validates a known-good message against the schema (and rejects
bad ones), so the contract can't silently rot.

## Known limitations

- **Property order is fixed** in the GBNF grammar (schema order: `id`,
  `component`, then props). Constrained decoding walks one path anyway;
  in practice small models follow the few-shot order.
- **Optional props are ordered too**, and in objects with *no* required
  props they're all-or-nothing (none or all, in order). No such object
  exists in the minimal catalog today.
- **Schemas constrain shape, not sense.** A model can still write a
  semantically odd tree (a Card whose child is a Button label, say). The
  system prompt's few-shot example is what teaches good trees.
- `gbnfFromJsonSchema()` supports the JSON Schema subset genui emits
  (objects, enums, arrays, `oneOf`) and falls back to permissive JSON for
  anything unrecognized — generation never dead-ends.
