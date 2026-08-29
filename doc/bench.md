# The bench: scoring small-model A2UI output

The bench answers one question per raw model response — **would it render?**
— and records *which* repairs were needed to get there. Run across a corpus
of captured outputs, that becomes a model's **failure-mode fingerprint**:
what it gets wrong, how often, and whether the deterministic repair pass
covers it.

## Running it

```bash
flutter pub get
dart run tool/bench.dart              # score the whole corpus
dart run tool/bench.dart --verbose    # + prompts, failures, raw output
dart run tool/bench.dart --filter gemma
dart run tool/bench.dart --json       # machine-readable (CI-friendly)
```

The command exits non-zero when any case (that isn't marked
`expectedFail`) fails to repair into a renderable tree, and the corpus is
also run as a Flutter test (`test/bench_corpus_test.dart`), so regressions
in the repair pass can't land silently.

Example output:

```
PASS  missing-brace-nests-sibling  [gemma-3n-e2b-it-int4, captured]
      repairs: json:rebalancedBraces×1, inject:createSurface×1
XFAIL  stray-quote-before-object  [qwen3:4b, captured]
      repairs: inject:createSurface×1

11/12 cases repair to a renderable tree (4 captured verbatim, 1 known-limitation XFAIL).
```

## The corpus

One JSON file per case in `bench/cases/`:

```json
{
  "name": "reused-child-ref",
  "model": "gemma-3n-e2b-it-int4",
  "provenance": "captured",
  "prompt": "A card titled \"Glow tip\" with one short sentence and a button.",
  "raw": "```json\n{\"version\":\"v0.9\",…}\n```"
}
```

- `model` — what produced the output. Anything goes; the corpus is how we
  compare models.
- `provenance` — `"captured"` (verbatim from a real run) or `"synthesized"`
  (hand-built from a documented failure mode). Honesty here is what makes
  the corpus trustworthy.
- `raw` — the model's response **exactly as received**: fences, prose, and
  bugs included. Don't clean it up; the mess is the point.
- `expectedFail` (optional) — true when the repair pipeline is known not to
  fix this output yet. XFAIL cases document the repair pass's limits and
  are an open invitation to improve it; if one starts passing, the test
  will tell you to drop the flag.

## Scoring

`scoreRawResponse()` (`lib/src/scoring.dart`, pure Dart) runs the standard
`repairRawResponse` pipeline, then checks the result structurally:

- opens with a `createSurface` pinned to our surface + catalog,
- every `updateComponents` targets our surface,
- unique ids, a `root` exists, all component types are in the catalog,
- all child references resolve, and no id has two parents (real tree),
- required props per component (`Text.text`, `Button.child/action`,
  `Card.child`, `Column.children`, `Stat.value`).

The `RepairLog` telemetry (`rule×count`, e.g. `tree:clonedReusedChild×2`)
is the fingerprint; rule ids are stable strings in `RepairRules`.

## Contributing a case

The easiest meaningful contribution to genui_min:

1. Pick a prompt from `bench/prompts.txt` (or bring your own).
2. Run it through your model with the minimal system prompt — e.g. the
   example app, or `dart run tool/live_check.dart <model> "<prompt>"`
   against a local Ollama.
3. Save the **raw** output as `bench/cases/<slug>.case.json` (schema above).
4. `dart run tool/bench.dart` — if your case fails and shouldn't, you just
   found a repair-pass gap. PRs that close those gaps are the best kind.

## Live checking against a local model

`tool/live_check.dart` runs one prompt through a local Ollama model twice —
unconstrained and schema-constrained — and scores both:

```bash
ollama serve
dart run tool/live_check.dart qwen3:4b "A streak reminder card with a big number"
```

It needs a running model server, so it stays a manual tool (unlike
`tool/bench.dart`, which is deterministic and CI-safe).
