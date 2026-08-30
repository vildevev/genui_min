// Catalog metadata + demo A2UI snippets for the gallery: what each component
// is, which props it takes (straight from the live schema — this file never
// duplicates it by hand), and the raw JSON that renders each variant.

import 'package:genui/genui.dart';
import 'package:genui_min/genui_min.dart';

/// One named variant of a component, as raw A2UI the preview can render.
final class ComponentVariant {
  const ComponentVariant(this.label, this.raw);

  final String label;

  /// A complete `updateComponents` message (createSurface is injected by the
  /// repair pass — exactly like a real model response would need).
  final String raw;
}

/// UI-agnostic info about one catalog item, props extracted from its schema.
final class ComponentInfo {
  ComponentInfo._(this.name, this.description, this.variants, this.props);

  final String name;
  final String description;
  final List<ComponentVariant> variants;

  /// `id` and `component` are documented once globally; these are the rest.
  final List<ComponentProp> props;

  static ComponentInfo fromItem(
    CatalogItem item,
    List<ComponentVariant> variants,
  ) {
    final schema = item.dataSchema.value;
    final description = (schema['description'] as String?) ?? '';
    final required = (schema['required'] as List?)?.cast<String>() ?? const [];
    final properties = schema['properties'] as Map? ?? {};
    final props = <ComponentProp>[];
    for (final e in properties.entries) {
      if (e.key == 'id' || e.key == 'component') continue;
      final p = e.value as Map;
      props.add(ComponentProp(
        e.key as String,
        (p['description'] as String?) ?? '',
        enumValues: (p['enum'] as List?)?.cast<String>(),
        required: required.contains(e.key),
      ));
    }
    return ComponentInfo._(item.name, description, variants, props);
  }
}

final class ComponentProp {
  const ComponentProp(this.name, this.description,
      {this.enumValues, this.required = false});

  final String name;
  final String description;
  final List<String>? enumValues;
  final bool required;
}

String _msg(String componentsJson) =>
    '{"version":"v0.9","updateComponents":{"surfaceId":"main",'
    '"components":$componentsJson}}';

/// The gallery's component library — one entry per minimal-catalog widget,
/// variants included, driven by the same [styledMinimalCatalog] the model
/// prompt is built from.
List<ComponentInfo> componentLibrary(Catalog catalog) {
  final byName = {for (final item in catalog.items) item.name: item};

  ComponentInfo info(String name, List<ComponentVariant> variants) =>
      ComponentInfo.fromItem(byName[name]!, variants);

  return [
    info('Text', [
      ComponentVariant(
        'body',
        _msg('[{"id":"root","component":"Text",'
            '"text":"Apply SPF every morning, rain or shine."}]'),
      ),
      ComponentVariant(
        'title',
        _msg('[{"id":"root","component":"Text","variant":"title",'
            '"text":"Glow tip"}]'),
      ),
    ]),
    info('Card', [
      ComponentVariant(
        'default',
        _msg('[{"id":"root","component":"Card","child":"t"},'
            '{"id":"t","component":"Text","variant":"title",'
            '"text":"Weekly brief"}]'),
      ),
    ]),
    info('Button', [
      ComponentVariant(
        'primary',
        _msg('[{"id":"root","component":"Button","child":"l",'
            '"action":{"event":{"name":"got_it","context":{}}}},'
            '{"id":"l","component":"Text","text":"Got it"}]'),
      ),
      ComponentVariant(
        'borderless',
        _msg('[{"id":"root","component":"Button","variant":"borderless",'
            '"child":"l","action":{"event":{"name":"more","context":{}}}},'
            '{"id":"l","component":"Text","text":"Tell me more"}]'),
      ),
    ]),
    info('Column', [
      ComponentVariant(
        'composed',
        _msg('[{"id":"root","component":"Column","children":["t","b","btn"]},'
            '{"id":"t","component":"Text","variant":"title","text":"Morning"},'
            '{"id":"b","component":"Text","text":"Two liters by noon."},'
            '{"id":"btn","component":"Button","child":"bl",'
            '"action":{"event":{"name":"log","context":{}}}},'
            '{"id":"bl","component":"Text","text":"Log water"}]'),
      ),
    ]),
    info('Stat', [
      ComponentVariant(
        'up',
        _msg('[{"id":"root","component":"Stat","value":"66",'
            '"label":"Glow score","delta":"+4","trend":"up"}]'),
      ),
      ComponentVariant(
        'down',
        _msg('[{"id":"root","component":"Stat","value":"42",'
            '"label":"Sleep debt","delta":"-1h","trend":"down"}]'),
      ),
      ComponentVariant(
        'flat',
        _msg('[{"id":"root","component":"Stat","value":"5",'
            '"label":"Day streak","delta":"+0","trend":"flat"}]'),
      ),
    ]),
  ];
}

/// Composed, realistic cards for the Examples tab.
final class GalleryExample {
  const GalleryExample(this.title, this.subtitle, this.raw);

  final String title;
  final String subtitle;
  final String raw;
}

const galleryExamples = [
  GalleryExample(
    'Today synthesis',
    'title · Stat · summary · button',
    '{"version":"v0.9","updateComponents":{"surfaceId":"main","components":['
        '{"id":"root","component":"Column","children":["t","s","b","btn"]},'
        '{"id":"t","component":"Text","variant":"title","text":"Today"},'
        '{"id":"s","component":"Stat","value":"72","label":"Glow score",'
        '"delta":"+6","trend":"up"},'
        '{"id":"b","component":"Card","child":"bt"},'
        '{"id":"bt","component":"Text","text":"Sleep held your score up last night."},'
        '{"id":"btn","component":"Button","child":"bl",'
        '"action":{"event":{"name":"details","context":{}}}},'
        '{"id":"bl","component":"Text","text":"See breakdown"}]}}',
  ),
  GalleryExample(
    'Weekly brief',
    'title · Stat · recap · borderless button',
    '{"version":"v0.9","updateComponents":{"surfaceId":"main","components":['
        '{"id":"root","component":"Column","children":["t","s","recap","btn"]},'
        '{"id":"t","component":"Text","variant":"title","text":"Weekly brief"},'
        '{"id":"s","component":"Stat","value":"66","label":"Glow score",'
        '"delta":"up 6%","trend":"up"},'
        '{"id":"recap","component":"Card","child":"rt"},'
        '{"id":"rt","component":"Text","text":"Consistent mornings carried the week."},'
        '{"id":"btn","component":"Button","variant":"borderless","child":"bl",'
        '"action":{"event":{"name":"share","context":{}}}},'
        '{"id":"bl","component":"Text","text":"Share"}]}}',
  ),
  GalleryExample(
    'Watch party invite',
    'title · details card · RSVP button',
    '{"version":"v0.9","updateComponents":{"surfaceId":"main","components":['
        '{"id":"root","component":"Column","children":["t","card","btn"]},'
        '{"id":"t","component":"Text","variant":"title","text":"Matchday"},'
        '{"id":"card","component":"Card","child":"ct"},'
        '{"id":"ct","component":"Text","text":"Kickoff 19:45 at The Crown, '
        'Northside. Doors at 18:30 — first pint on the house."},'
        '{"id":"btn","component":"Button","child":"bl",'
        '"action":{"event":{"name":"rsvp","context":{}}}},'
        '{"id":"bl","component":"Text","text":"I\'m in"}]}}',
  ),
];

/// The playground's starting point — the classic small-model bug included, so
/// the repair pass has something to do on the first click.
const playgroundSeed = '''
```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
{"id":"root","component":"Column","children":["tip_card","more_btn"]},
{"id":"tip_card","component":"Card","child":"tip_text"},
{"id":"tip_text","component":"Text","variant":"title","text":"Glow tip"},
{"id":"more_btn","component":"Button","child":"tip_text","action":{"event":{"name":"learn_more","context":{}}}}
]}}
```
''';
