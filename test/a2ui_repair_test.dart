import 'package:flutter_test/flutter_test.dart';
import 'package:genui_min/genui_min.dart';

Map<String, dynamic> _uc(List<Map<String, dynamic>> components) => {
      'version': 'v0.9',
      'updateComponents': {'surfaceId': 'main', 'components': components},
    };

List<Map<String, dynamic>> _comps(Map<String, dynamic> repaired) =>
    ((repaired['updateComponents'] as Map)['components'] as List)
        .cast<Map<String, dynamic>>();

Map<String, dynamic> _byId(Map<String, dynamic> repaired, String id) =>
    _comps(repaired).firstWhere((c) => c['id'] == id);

void main() {
  group('extractJsonObjects', () {
    test('pulls a fenced json object out of prose', () {
      final raw = 'Sure! Here:\n```json\n{"version":"v0.9","a":1}\n```\nDone.';
      final objs = extractJsonObjects(raw);
      expect(objs, hasLength(1));
      expect(objs.first['a'], 1);
    });

    test('ignores braces inside strings', () {
      final objs = extractJsonObjects('{"text":"a } b { c"}');
      expect(objs, hasLength(1));
      expect(objs.first['text'], 'a } b { c');
    });

    test('handles multiple objects', () {
      final objs = extractJsonObjects('{"x":1} junk {"y":2}');
      expect(objs.map((e) => e.keys.first), ['x', 'y']);
    });
  });

  group('repairUpdateComponents', () {
    test(
      'clones a child reused by two parents (the Button-reuses-Text bug)',
      () {
        final msg = _uc([
          {
            'id': 'root',
            'component': 'Column',
            'children': ['card', 'btn'],
          },
          {'id': 'card', 'component': 'Card', 'child': 'shared_text'},
          {'id': 'shared_text', 'component': 'Text', 'text': 'Glow tip'},
          {
            'id': 'btn',
            'component': 'Button',
            'child': 'shared_text', // <-- reused!
            'action': {
              'event': {'name': 'x', 'context': {}},
            },
          },
        ]);
        final fixed = repairUpdateComponents(msg);
        final card = _byId(fixed, 'card');
        final btn = _byId(fixed, 'btn');
        // Each parent now points at a DIFFERENT child id.
        expect(card['child'], isNot(equals(btn['child'])));
        // Both children exist and are Text with the same content.
        final cardChild = _byId(fixed, card['child'] as String);
        final btnChild = _byId(fixed, btn['child'] as String);
        expect(cardChild['component'], 'Text');
        expect(btnChild['component'], 'Text');
        expect(cardChild['text'], 'Glow tip');
      },
    );

    test('drops dangling child references', () {
      final msg = _uc([
        {
          'id': 'root',
          'component': 'Column',
          'children': ['real', 'ghost'],
        },
        {'id': 'real', 'component': 'Text', 'text': 'hi'},
      ]);
      final fixed = repairUpdateComponents(msg);
      expect(_byId(fixed, 'root')['children'], ['real']);
    });

    test('synthesizes a label for a Button missing its child', () {
      final msg = _uc([
        {
          'id': 'root',
          'component': 'Column',
          'children': ['btn'],
        },
        {'id': 'btn', 'component': 'Button'},
      ]);
      final fixed = repairUpdateComponents(msg);
      final btn = _byId(fixed, 'btn');
      expect(btn['action'], isA<Map>()); // default action added
      expect(btn['child'], isA<String>());
      expect(_byId(fixed, btn['child'] as String)['component'], 'Text');
    });

    test('promotes a lone top-level node to root when root is missing', () {
      final msg = _uc([
        {'id': 'mycard', 'component': 'Card', 'child': 't'},
        {'id': 't', 'component': 'Text', 'text': 'hi'},
      ]);
      final fixed = repairUpdateComponents(msg);
      expect(_comps(fixed).any((c) => c['id'] == 'root'), isTrue);
    });

    test('Text without text gets an empty string', () {
      final msg = _uc([
        {'id': 'root', 'component': 'Text'},
      ]);
      final fixed = repairUpdateComponents(msg);
      expect(_byId(fixed, 'root')['text'], '');
    });

    test('drops orphan components not reachable from root', () {
      final msg = _uc([
        {
          'id': 'root',
          'component': 'Column',
          'children': ['a'],
        },
        {'id': 'a', 'component': 'Text', 'text': 'hi'},
        {'id': 'orphan', 'component': 'Text', 'text': 'nobody references me'},
      ]);
      final fixed = repairUpdateComponents(msg);
      expect(_comps(fixed).any((c) => c['id'] == 'orphan'), isFalse);
    });

    test('valid input passes through structurally intact', () {
      final msg = _uc([
        {
          'id': 'root',
          'component': 'Column',
          'children': ['c', 'b'],
        },
        {'id': 'c', 'component': 'Card', 'child': 'ct'},
        {'id': 'ct', 'component': 'Text', 'text': 'tip'},
        {
          'id': 'b',
          'component': 'Button',
          'child': 'bl',
          'action': {
            'event': {'name': 'go', 'context': {}},
          },
        },
        {'id': 'bl', 'component': 'Text', 'text': 'OK'},
      ]);
      final fixed = repairUpdateComponents(msg);
      expect(_comps(fixed), hasLength(5));
      expect(_byId(fixed, 'root')['children'], ['c', 'b']);
    });
  });

  group('RepairLog telemetry', () {
    test('counts each fired rule with component-level details', () {
      final raw = '```json\n'
          '{"version":"v0.9","updateComponents":{"surfaceId":"other",'
          '"components":[{"id":"root","component":"Column","children":["c","b"]},'
          '{"id":"c","component":"Card","child":"t"},'
          '{"id":"t","component":"Text","text":"tip"},'
          '{"id":"b","component":"Button"}]}}\n```';
      final log = RepairLog();
      repairRawResponse(raw, surfaceId: 'main', catalogId: 'cat://x', log: log);
      expect(log.counts['inject:createSurface'], 1);
      expect(log.counts['surface:pinnedInventedSurfaceId'], 1);
      expect(log.counts['props:defaultedButtonAction'], 1);
      expect(log.counts['props:synthesizedButtonLabel'], 1);
      expect(
        log.details['props:synthesizedButtonLabel'],
        contains('b'),
      );
      expect(log.total, log.counts.values.reduce((a, b) => a + b));
      expect(log.toString(), contains('props:synthesizedButtonLabel×1'));
    });

    test('clean output reports no repairs beyond the createSurface inject', () {
      final raw = '```json\n'
          '{"version":"v0.9","updateComponents":{"surfaceId":"main",'
          '"components":[{"id":"root","component":"Text","text":"hi"}]}}\n```';
      final log = RepairLog();
      repairRawResponse(raw, surfaceId: 'main', catalogId: 'cat://x', log: log);
      expect(log.counts, {'inject:createSurface': 1});
      expect(log.isEmpty, isFalse);
    });

    test('json recovery is observable through the log', () {
      final raw = '{"a":1} {"c" 3}'; // second slice closes but won't decode
      final log = RepairLog();
      final objs = extractJsonObjects(raw, log: log);
      expect(objs, hasLength(1));
      expect(log.counts['json:droppedUndecodableObject'], 1);
    });
  });

  group('repairRawResponse', () {
    test('injects createSurface when absent and emits fenced messages', () {
      final raw = '```json\n'
          '{"version":"v0.9","updateComponents":{"surfaceId":"main",'
          '"components":[{"id":"root","component":"Text","text":"hi"}]}}\n```';
      final out = repairRawResponse(
        raw,
        surfaceId: 'main',
        catalogId: 'cat://x',
      );
      expect(out, contains('"createSurface"'));
      expect(out, contains('"updateComponents"'));
      expect('```json'.allMatches(out).length, 2);
    });

    test('recovers from a missing brace that nests a sibling component', () {
      // Real Gemma output: it forgot to close `cta_button`, so `cta_label`
      // got nested inside it as a keyless object (invalid JSON). Without the
      // brace-fixer the whole message is unparseable and nothing renders.
      final raw = '```json\n'
          '{"version":"v0.9","updateComponents":{"surfaceId":"main",'
          '"components":[{"id":"root","component":"Column",'
          '"children":["title_text","cta_button"]},'
          '{"id":"title_text","component":"Text","text":"Hi"},'
          '{"id":"cta_button","component":"Button","child":"cta_label",'
          '"action":{"event":{"name":"got_it"}},'
          '{"id":"cta_label","component":"Text","text":"Got it"}}]}}\n```';
      final objs = extractJsonObjects(raw);
      expect(objs, isNotEmpty, reason: 'brace-fixer should recover the object');
      final comps = objs.first['updateComponents']['components'] as List;
      final ids = comps.map((c) => c['id']).toList();
      expect(
        ids,
        containsAll(['root', 'title_text', 'cta_button', 'cta_label']),
      );

      // And the full pipeline renders it (button label survives).
      final out = repairRawResponse(
        raw,
        surfaceId: 'main',
        catalogId: 'cat://x',
      );
      expect(out, contains('"id": "cta_button"'));
      expect(out, contains('"id": "cta_label"'));
    });

    test('recovers from missing commas between array elements', () {
      // Real Gemma output: dropped the comma between two component objects
      // (`}` directly followed by `{`), which makes the whole message
      // unparseable → empty surface. The fixer inserts the missing separators.
      final raw = '```json\n'
          '{"version":"v0.9","updateComponents":{"surfaceId":"journey_surface",'
          '"components":[\n'
          '{"id":"root","component":"Column","children":["a","b"]}\n' // no comma
          '{"id":"a","component":"Text","text":"hi"},\n'
          '{"id":"b","component":"Stat","value":"10","label":"Glow score"}\n'
          ']}}\n```';
      final objs = extractJsonObjects(raw);
      expect(objs, isNotEmpty, reason: 'missing-comma fixer should recover it');
      final comps = objs.first['updateComponents']['components'] as List;
      expect(comps.map((c) => c['id']), containsAll(['root', 'a', 'b']));
      expect(comps.firstWhere((c) => c['id'] == 'b')['value'], '10');
    });

    test('rewrites a model-invented surfaceId to the created surface', () {
      // The model targets a surface it made up ("week_summary"); without the
      // fix the components mount on a surface that was never created.
      final raw = '```json\n'
          '{"version":"v0.9","updateComponents":{"surfaceId":"week_summary",'
          '"components":[{"id":"root","component":"Text","text":"hi"}]}}\n```';
      final out = repairRawResponse(
        raw,
        surfaceId: 'main',
        catalogId: 'cat://x',
      );
      expect(out, contains('"surfaceId": "main"'));
      expect(out, isNot(contains('week_summary')));
    });
  });
}
