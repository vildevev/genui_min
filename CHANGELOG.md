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
