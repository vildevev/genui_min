// Renderer-agnostic scoring for repaired small-model A2UI output.
//
// Answers one question per raw model response: *would it render?* The checks
// are deliberately structural — no Flutter, no catalog instance, no widgets —
// so scoring can run from a pure-Dart CLI (`dart run tool/bench.dart`) over a
// corpus of captured model outputs. Each report also carries the [RepairLog]
// telemetry, which is how the corpus captures a model's failure-mode
// fingerprint (which repairs fire, and how often).
//
// Pure Dart, no Flutter deps.

import 'a2ui_repair.dart';

/// Component names in the default `styledMinimalCatalog()`. Scoring needs the
/// names only (not the catalog) to stay Flutter-free.
const Set<String> minimalComponentNames = {
  'Text',
  'Card',
  'Button',
  'Column',
  'Stat',
};

/// The result of scoring one raw model response through the repair pipeline.
final class ScoreReport {
  const ScoreReport({
    required this.name,
    required this.ok,
    required this.failures,
    required this.log,
    required this.rawChars,
  });

  /// Label for the scored response (bench case name, prompt, …).
  final String name;

  /// True when the repaired output satisfies every renderability check.
  final bool ok;

  /// Human-readable descriptions of each failed check (empty when [ok]).
  final List<String> failures;

  /// Which repair rules fired while repairing this response.
  final RepairLog log;

  /// Length of the raw model text (a cheap proxy for output budget).
  final int rawChars;
}

/// Repair [raw] exactly like the app would, then check that the result is
/// structurally renderable: a `createSurface` first, every `updateComponents`
/// targeting our surface, unique ids, known component types, all child refs
/// resolving, a real tree (no id used twice), and required props present.
ScoreReport scoreRawResponse(
  String raw, {
  required String name,
  String surfaceId = 'main',
  String catalogId = 'cat://bench',
  Set<String> componentNames = minimalComponentNames,
}) {
  final log = RepairLog();
  final failures = <String>[];
  final clean = repairRawResponse(
    raw,
    surfaceId: surfaceId,
    catalogId: catalogId,
    log: log,
  );
  final msgs = extractJsonObjects(clean);

  if (msgs.isEmpty) {
    return ScoreReport(
      name: name,
      ok: false,
      failures: ['no decodable JSON object in the repaired output'],
      log: log,
      rawChars: raw.length,
    );
  }

  // The pipeline must open with a createSurface pinned to our ids.
  final first = msgs.first;
  final cs = first['createSurface'];
  if (cs is! Map) {
    failures.add('first message is not a createSurface');
  } else {
    if (cs['surfaceId'] != surfaceId) {
      failures.add('createSurface targets "${cs['surfaceId']}"');
    }
    if (cs['catalogId'] != catalogId) {
      failures.add('createSurface uses catalog "${cs['catalogId']}"');
    }
  }

  final updates = msgs.where((m) => m['updateComponents'] is Map).toList();
  if (updates.isEmpty) {
    failures.add('no updateComponents message in the repaired output');
  }
  for (final u in updates) {
    _scoreUpdate(
      u['updateComponents'] as Map,
      failures: failures,
      surfaceId: surfaceId,
      componentNames: componentNames,
    );
  }

  return ScoreReport(
    name: name,
    ok: failures.isEmpty,
    failures: failures,
    log: log,
    rawChars: raw.length,
  );
}

void _scoreUpdate(
  Map uc, {
  required List<String> failures,
  required String surfaceId,
  required Set<String> componentNames,
}) {
  if (uc['surfaceId'] != surfaceId) {
    failures.add('updateComponents targets "${uc['surfaceId']}"');
  }
  final comps = uc['components'];
  if (comps is! List || comps.isEmpty) {
    failures.add('updateComponents has no components');
    return;
  }

  final byId = <String, Map>{};
  for (final c in comps) {
    if (c is! Map) {
      failures.add('component entry is not an object: $c');
      continue;
    }
    final id = c['id']?.toString() ?? '';
    if (id.isEmpty) {
      failures.add('component without id: $c');
    } else if (byId.containsKey(id)) {
      failures.add('duplicate component id "$id"');
    } else {
      byId[id] = c;
    }
  }
  if (byId.isEmpty) return;
  if (!byId.containsKey('root')) {
    failures.add('no component with id "root"');
  }

  // Tree property: every child ref resolves, and no id has two parents.
  final parents = <String, String>{};
  void checkRef(String from, Object? ref) {
    final id = ref.toString();
    if (!byId.containsKey(id)) {
      failures.add('"$from" references missing child "$id"');
    } else if (parents.containsKey(id)) {
      failures.add(
        '"$id" is a child of both "${parents[id]}" and "$from" (not a tree)',
      );
    } else {
      parents[id] = from;
    }
  }

  for (final e in byId.entries) {
    final id = e.key;
    final c = e.value;
    final type = c['component']?.toString() ?? '';
    if (!componentNames.contains(type)) {
      failures.add(
          '"$id" has unknown component type "${type.isEmpty ? "?" : type}"');
    }
    if (c['child'] != null) checkRef(id, c['child']);
    final children = c['children'];
    if (children is List) {
      for (final ref in children) {
        checkRef(id, ref);
      }
    }
    // Required props per component type (the styled minimal catalog).
    switch (type) {
      case 'Text':
        if (c['text'] is! String) {
          failures.add('Text "$id" has no text');
        }
      case 'Card':
        if (c['child'] is! String) {
          failures.add('Card "$id" has no child');
        }
      case 'Button':
        if (c['child'] is! String) {
          failures.add('Button "$id" has no label child');
        }
        final action = c['action'];
        if (action is! Map || action['event'] is! Map) {
          failures.add('Button "$id" has no action event');
        }
      case 'Column':
        if (c['children'] is! List || (c['children'] as List).isEmpty) {
          failures.add('Column "$id" has no children');
        }
      case 'Stat':
        if (c['value'] is! String) failures.add('Stat "$id" has no value');
    }
  }
}
