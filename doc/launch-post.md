# Launch Note Draft

On-device generative UI works when the catalog fits the model.

Most "AI builds your interface" demos quietly call a large cloud model. I wanted
the opposite: a small local model on an iPhone emitting UI instructions, with no
server and no API key.

`genui_min` is a tiny styled catalog for Google's `genui` / A2UI renderer. It
keeps the practical building blocks: `Text`, `Card`, `Button`, `Column`, and a
`Stat` widget for metric cards. The result is a much smaller system prompt:
about 4.7k tokens instead of about 19k for the full `BasicCatalog`.

That size difference matters. A 2B-class model can fit the protocol, the user
request, and the answer inside an 8k context window.

The second half is less glamorous and more important: repair. Small models get
close, but they reuse child references, skip `createSurface`, invent surface
ids, forget button labels, and sometimes drop a comma or brace. `genui_min`
repairs those predictable mistakes deterministically before handing the message
to the renderer.

The demo has run on an iPhone in airplane mode with Gemma 3n E2B. The model
emits A2UI; `genui_min` repairs it; `genui` renders real themed Flutter widgets.

Repo: https://github.com/vildevev/genui_min
