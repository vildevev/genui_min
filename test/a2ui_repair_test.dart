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
    test('clones a child reused by two parents (the Button-reuses-Text bug)', () {
      final msg = _uc([
        {'id': 'root', 'component': 'Column', 'children': ['card', 'btn']},
        {'id': 'card', 'component': 'Card', 'child': 'shared_text'},
        {'id': 'shared_text', 'component': 'Text', 'text': 'Glow tip'},
        {
          'id': 'btn',
          'component': 'Button',
          'child': 'shared_text', // <-- reused!
          'action': {'event': {'name': 'x', 'context': {}}},
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
    });

    test('drops dangling child references', () {
      final msg = _uc([
        {'id': 'root', 'component': 'Column', 'children': ['real', 'ghost']},
        {'id': 'real', 'component': 'Text', 'text': 'hi'},
      ]);
      final fixed = repairUpdateComponents(msg);
      expect(_byId(fixed, 'root')['children'], ['real']);
    });

    test('synthesizes a label for a Button missing its child', () {
      final msg = _uc([
        {'id': 'root', 'component': 'Column', 'children': ['btn']},
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
        {'id': 'root', 'component': 'Column', 'children': ['a']},
        {'id': 'a', 'component': 'Text', 'text': 'hi'},
        {'id': 'orphan', 'component': 'Text', 'text': 'nobody references me'},
      ]);
      final fixed = repairUpdateComponents(msg);
      expect(_comps(fixed).any((c) => c['id'] == 'orphan'), isFalse);
    });

    test('valid input passes through structurally intact', () {
      final msg = _uc([
        {'id': 'root', 'component': 'Column', 'children': ['c', 'b']},
        {'id': 'c', 'component': 'Card', 'child': 'ct'},
        {'id': 'ct', 'component': 'Text', 'text': 'tip'},
        {'id': 'b', 'component': 'Button', 'child': 'bl',
          'action': {'event': {'name': 'go', 'context': {}}}},
        {'id': 'bl', 'component': 'Text', 'text': 'OK'},
      ]);
      final fixed = repairUpdateComponents(msg);
      expect(_comps(fixed), hasLength(5));
      expect(_byId(fixed, 'root')['children'], ['c', 'b']);
    });
  });

  group('repairRawResponse', () {
    test('injects createSurface when absent and emits fenced messages', () {
      final raw = '```json\n'
          '{"version":"v0.9","updateComponents":{"surfaceId":"main",'
          '"components":[{"id":"root","component":"Text","text":"hi"}]}}\n```';
      final out = repairRawResponse(raw,
          surfaceId: 'main', catalogId: 'cat://x');
      expect(out, contains('"createSurface"'));
      expect(out, contains('"updateComponents"'));
      expect('```json'.allMatches(out).length, 2);
    });
  });
}
