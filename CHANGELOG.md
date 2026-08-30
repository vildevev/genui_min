## 0.2.0

Three additions aimed at making genui_min a toolbox for small-model A2UI,
not just a Flutter package:

- **Repair telemetry + bench corpus.** `repairRawResponse` /
  `repairUpdateComponents` now take an optional `RepairLog` reporting which
  repair rules fired (stable ids in `RepairRules`). New pure-Dart scorer
  (`scoreRawResponse`) answers "would it render?" structurally; a corpus of
  raw model outputs lives in `bench/cases/` with `dart run tool/bench.dart`
  to score it (PASS/FAIL/XFAIL + corpus-wide failure-mode fingerprint).
  The old `test/fixtures/*.raw.txt` files migrated into the corpus.
- **Model-runner abstraction + Ollama adapter.** `LlmRunner` is the
  one-method model contract; `OllamaRunner`
  (`package:genui_min/ollama.dart`) drives any local Ollama model, with
  sampler/context options and schema-constrained decoding via
  `responseFormat`. The example app now runs sample / on-device-Gemma /
  Ollama backends interchangeably and shows the repair log per render.
- **Constrained decoding from the catalog.**
  `updateComponentsOutputSchema(catalog)` derives a JSON Schema from the
  same catalog that builds the system prompt (every component branch gets a
  required unique `id`); `updateComponentsGbnf(catalog)` converts it to a
  GBNF grammar for llama.cpp-family samplers. Generated artifacts live in
  `grammar/` and a freshness test keeps them in sync with the catalog
  (regen: `GENUI_MIN_REGEN=1 flutter test test/constrained_test.dart`).
  Verified live against a local Ollama: qwen3:4b unconstrained produced
  undecodable JSON (captured as the first XFAIL corpus case); with the
  schema, a renderable tree and zero semantic repairs.
- **Component gallery** (`gallery/`): a web-buildable, model-free app that
  renders every catalog widget through the real pipeline (variants, props
  from the live schema, A2UI JSON), plus a live A2UI playground with the
  repair log and composed example cards.
- New docs: `doc/bench.md` (corpus format + contributing cases),
  `doc/constrained.md` (schema/grammar usage + limitations). CI now runs
  the bench too. `tool/live_check.dart` manually scores a local model
  constrained vs unconstrained.

## 0.1.1

- Added CI for formatting, analysis, package tests, and example analysis.
- Added proof notes documenting the offline iPhone/Gemma test setup, prompt
  budget comparison, screenshots, and recurring small-model failure modes.
- Added fixture files for repaired A2UI failure modes and a fixture-driven
  regression test.
- Added a prompt gallery to the example app for realistic card-generation
  trials.
- Added a `flutter_gemma` integration guide and launch-note draft.

## 0.1.0

- Initial release.
- `styledMinimalCatalog()` — a 4-widget (Text/Card/Button/Column), theme-aware
  genui catalog whose system prompt is ~4.7k tokens (vs ~19k for the full
  basic catalog), so it fits a small on-device LLM's context.
- `repairRawResponse()` / `repairUpdateComponents()` — deterministic repair of
  small-model A2UI output (reused child refs, missing button labels, missing
  root/createSurface, dangling refs, required props).
- Runnable example driving the catalog with `flutter_gemma` (Gemma .task model)
  plus a zero-setup "sample output" mode.
