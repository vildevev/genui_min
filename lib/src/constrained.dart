// Constrained decoding for small models: derive, from the SAME catalog that
// builds the system prompt, the exact output contract — as a JSON Schema for
// runtimes with structured outputs (Ollama `format`, …) and as a GBNF grammar
// for llama.cpp-family grammar sampling.
//
// With the schema applied at decode time, the model cannot produce invalid
// A2UI — no reused child ids, no invented surfaceIds, no missing required
// props, no malformed JSON. The deterministic repair pass stays in front of
// the renderer as a safety net (and because unconstrained runners still
// exist), but with constrained decoding it should log zero repairs.
//
// The schema asks for ONE `updateComponents` message (object root — the shape
// Ollama's structured outputs prefer); `createSurface` is injected
// deterministically by `repairRawResponse`, so the model never needs to emit
// it.

import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:json_schema_builder/json_schema_builder.dart' as jsb;

import 'gbnf.dart';

/// JSON Schema (as a plain map) describing the one message the model should
/// emit for [catalog]: `{"version":"v0.9","updateComponents":{…}}`.
///
/// Built from the catalog's component schemas, in the shape of genui's
/// `A2uiSchemas.updateComponentsSchema`, then post-processed: every component
/// branch gets a required, unique `id` (ordered `id, component, …` to match
/// the few-shot example), because the renderer keys components by id and the
/// repair pass drops id-less entries.
Map<String, Object?> updateComponentsOutputSchema(CatalogApi catalog) {
  final schema = jsb.S.object(
    title: 'genui_min updateComponents message',
    description:
        'Exactly one A2UI v0.9 updateComponents message describing the UI '
        'tree as a flat list of components (one with id "root").',
    properties: {
      'version': jsb.S.string(constValue: 'v0.9'),
      'updateComponents': _updateComponentsSchema(catalog),
    },
    required: ['version', 'updateComponents'],
    additionalProperties: false,
  );

  // Schema.value may share storage with the CommonSchemas constants the
  // catalog reuses — deep-copy before mutating.
  final map = jsonDecode(jsonEncode(schema.value)) as Map<String, Object?>;
  _removeCommonTypesRefs(map);
  _requireComponentIds(map);
  return map;
}

/// The schema as pretty-printed JSON — hand this to Ollama's `format` field
/// (or any structured-output API) verbatim.
String updateComponentsOutputSchemaJson(CatalogApi catalog) =>
    const JsonEncoder.withIndent('  ').convert(
      updateComponentsOutputSchema(catalog),
    );

/// The same contract as a GBNF grammar for llama.cpp-family samplers.
String updateComponentsGbnf(CatalogApi catalog) =>
    gbnfFromJsonSchema(updateComponentsOutputSchema(catalog));

/// The `updateComponents` body for [catalog]: a flat list of components,
/// each matching one of the catalog's component schemas.
jsb.Schema _updateComponentsSchema(CatalogApi catalog) => jsb.S.object(
      description:
          'Updates a surface with a new set of components. This message can '
          'be sent multiple times to update the component tree of an existing '
          'surface. One of the components in one of the components lists MUST '
          "have an 'id' of 'root' to serve as the root of the component tree. "
          'The createSurface message MUST have been previously sent with the '
          "'catalogId' that is in this message.",
      properties: {
        'surfaceId': jsb.S.string(
          description: 'The unique identifier for the UI surface.',
        ),
        'components': jsb.S.list(
          description: 'A flat list of component definitions.',
          minItems: 1,
          items: jsb.S.combined(
            oneOf: [
              for (final component in catalog.components.values)
                _componentSchema(component),
            ],
            description:
                'Must match one of the component definitions in the catalog.',
          ),
        ),
      },
      required: ['surfaceId', 'components'],
    );

/// [component]'s schema with its name as a required `component` property.
jsb.Schema _componentSchema(ComponentApi component) {
  final schema = component.schema.value;
  return jsb.Schema.fromMap({
    ...schema,
    'properties': {
      ...?schema['properties'] as Map<String, Object?>?,
      'component': {
        'type': 'string',
        'enum': [component.name],
      },
    },
    'required': ['component', ...?schema['required'] as List<Object?>?],
  });
}

/// Removes the `commonTypesRef` markers that `a2ui_core`'s `CommonSchemas`
/// carry, which are not JSON Schema keywords.
void _removeCommonTypesRefs(Object? node) {
  if (node is Map) {
    node.remove('commonTypesRef');
    node.values.forEach(_removeCommonTypesRefs);
  } else if (node is List) {
    node.forEach(_removeCommonTypesRefs);
  }
}

void _requireComponentIds(Map<String, Object?> schema) {
  final properties = schema['properties'];
  final update = properties is Map ? properties['updateComponents'] : null;
  final updateProps = update is Map ? update['properties'] : null;
  final components = updateProps is Map ? updateProps['components'] : null;
  final items = components is Map ? components['items'] : null;
  final oneOf = items is Map ? items['oneOf'] : null;
  if (oneOf is! List) return;

  for (final alt in oneOf) {
    if (alt is! Map || alt['type'] != 'object') continue;
    final props = alt['properties'];
    final component = props is Map ? props['component'] : null;
    if (component is! Map) continue; // not a component branch

    // Order id, component, then the rest — the order the few-shot example
    // teaches, so constrained decoding doesn't fight the model's priors.
    final rest = <String, Object?>{};
    for (final e in props.entries) {
      if (e.key == 'component' || e.key == 'id') continue;
      rest[e.key] = e.value;
    }
    alt['properties'] = {
      'id': {
        'type': 'string',
        'description':
            'Unique component id. Exactly one component in the whole '
                'list must use the id "root".',
      },
      'component': component,
      ...rest,
    };
    final required = (alt['required'] as List?)?.toList() ?? <Object?>[];
    alt['required'] = ['id', ...required.where((r) => r != 'id')];
  }
}
