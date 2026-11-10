# Using `genui_min` With `flutter_gemma`

`genui_min` does not ship a model runtime. It gives you a small A2UI catalog and
a deterministic repair pass. Any local model can produce the raw text.

The example app uses `flutter_gemma` because it can run a Gemma `.task` model on
device.

## Minimal Loop

```dart
final catalog = styledMinimalCatalog();
final systemPrompt = minimalSystemPrompt(catalog);

final prompt = '$systemPrompt\n\n'
    'User request: ${userInput.trim()}\n'
    'Respond with ONLY the A2UI messages described above.';

final raw = await model.generate(prompt);

final clean = repairRawResponse(
  raw,
  surfaceId: 'main',
  catalogId: catalog.id,
);

final processor = MessageProcessor<ComponentImplementation>(
  catalogs: [catalog],
);
processor.processMessages(extractJsonObjects(clean));

// Render it with A2uiSurface(surface: processor.model.getSurface('main')!).
```

## Important Runtime Notes

- Create the surface in app code and let the model fill it.
- Use a fresh `MessageProcessor` for each generation. Each generation creates
  the surface again, and a second `createSurface` for the same surface is an
  error.
- Keep temperature moderate. The catalog is small enough that you do not need to
  force the model into brittle, ultra-low-temperature output.
- Prefer a model/context pair that leaves memory headroom. On-device generative
  UI fails quietly when the KV cache gets too large for the phone.
