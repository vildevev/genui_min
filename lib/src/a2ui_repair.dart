// Deterministic "repair" pass for A2UI v0.9 output from small on-device LLMs.
//
// Small models (e.g. Gemma 4 E2B) reliably emit *structurally* valid A2UI but
// make a handful of recurring semantic mistakes. Rather than hope prompting
// catches them all, we repair the parsed message before handing it to the
// genui renderer — the same "be forgiving, never look broken" philosophy a
// production generative-UI surface needs.
//
// Fixes applied (all idempotent):
//   1. Reused child references — a component used as a child by >1 parent
//      (the classic "Button reuses the Card's Text"). Each extra reference gets
//      a fresh deep-cloned copy so the component tree is a real tree.
//   2. Missing/dangling child refs — children pointing at ids that don't exist
//      are dropped; a Button with no usable label gets a synthesized Text.
//   3. Missing `root` — if no component has id "root", the unreferenced
//      top-level node is promoted (or all roots are wrapped in a Column).
//   4. Required props — `Text` without `text` gets "", `Button` without
//      `action` gets a default no-op event.
//   5. Invented `surfaceId` — the model renames the surface, so the update
//      targets a surface that was never created; it's pinned back to ours.
//   6. Malformed JSON — a missing `}` that nests a sibling object, or a
//      missing comma between elements (`}{`), is repaired before decoding.
//
// Pure Dart, no Flutter deps — unit-testable on the host.

import 'dart:convert';

/// Extract candidate JSON objects from raw LLM text (handles ```json fences,
/// surrounding prose, and multiple concatenated objects) by scanning for
/// balanced top-level braces.
Map<String, dynamic>? _tryDecodeMap(String s) {
  try {
    final decoded = jsonDecode(s);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Best-effort fixer for the most common small-model JSON error: a missing
/// closing brace that nests what should be a *sibling* object (e.g. a component
/// emitted inside the previous component instead of after it). Walks the text
/// tracking object/array context; when an object is expecting a key but instead
/// sees `{`, it closes that object first (the brace the model forgot) and drops
/// the now-surplus trailing brace. Returns a re-balanced string to re-parse.
String _relaxBraces(String s) {
  final out = StringBuffer();
  final stack = <String>[]; // '{' for objects, '[' for arrays
  var inString = false, escaped = false, expectKey = false, strIsKey = false;
  // A separator comma the model wrote, held until we know what follows.
  var pendingComma = false;
  // True right after a completed value or closed container — the next
  // value/key/element must be separated by a comma. If the model forgot it
  // (e.g. `}{` between array elements), we insert one.
  var afterValue = false;

  // Emit the separator before a new value/key/element: flush a held comma, or
  // insert a missing one.
  void sep() {
    if (pendingComma) {
      out.write(',');
      pendingComma = false;
    } else if (afterValue) {
      out.write(',');
    }
    afterValue = false;
  }

  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (inString) {
      out.write(ch);
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
        afterValue = !strIsKey; // a value string completes a value
      }
      continue;
    }
    switch (ch) {
      case '"':
        sep();
        strIsKey = expectKey; // a string in key position is a key, not a value
        expectKey = false;
        inString = true;
        out.write(ch);
      case '{':
        if (stack.isNotEmpty && stack.last == '{' && expectKey) {
          // Keyless object: the enclosing object should have closed here.
          out.write('}');
          stack.removeLast();
        }
        sep();
        stack.add('{');
        expectKey = true;
        out.write(ch);
      case '[':
        sep();
        stack.add('[');
        expectKey = false;
        out.write(ch);
      case '}':
        pendingComma = false; // drop a trailing comma
        if (stack.isNotEmpty && stack.last == '{') {
          stack.removeLast();
          out.write(ch);
        } // else surplus/misplaced — drop it
        expectKey = false;
        afterValue = true;
      case ']':
        pendingComma = false; // drop a trailing comma
        if (stack.isNotEmpty && stack.last == '[') {
          stack.removeLast();
          out.write(ch);
        } // else drop
        expectKey = false;
        afterValue = true;
      case ':':
        pendingComma = false;
        expectKey = false;
        afterValue = false;
        out.write(ch);
      case ',':
        pendingComma = true;
        afterValue = false;
        expectKey = stack.isNotEmpty && stack.last == '{';
      case ' ':
      case '\t':
      case '\n':
      case '\r':
        out.write(ch);
      default:
        // A bare literal (number / true / false / null). Only the FIRST char
        // starts a new value (may need a separator); the rest continue it.
        if (!afterValue) sep();
        out.write(ch);
        afterValue = true;
    }
  }
  while (stack.isNotEmpty) {
    out.write(stack.removeLast() == '{' ? '}' : ']');
  }
  return out.toString();
}

List<Map<String, dynamic>> extractJsonObjects(String raw) {
  final out = <Map<String, dynamic>>[];
  var depth = 0;
  var start = -1;
  var inString = false;
  var escaped = false;
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{') {
      if (depth == 0) start = i;
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0 && start >= 0) {
        final slice = raw.substring(start, i + 1);
        Map<String, dynamic>? decoded = _tryDecodeMap(slice);
        // Tolerate the common small-model brace error (a missing `}` that nests
        // what should be a sibling object) by re-balancing and retrying.
        decoded ??= _tryDecodeMap(_relaxBraces(slice));
        if (decoded != null) out.add(decoded);
        start = -1;
      }
    }
  }
  return out;
}

/// Repair a single `updateComponents` message in place-safe fashion, returning
/// a new repaired message map. Non-updateComponents messages pass through.
Map<String, dynamic> repairUpdateComponents(Map<String, dynamic> message) {
  final uc = message['updateComponents'];
  if (uc is! Map) return message;
  final rawComps = uc['components'];
  if (rawComps is! List || rawComps.isEmpty) return message;

  // Deep-copy components into a mutable, id-indexed map.
  final byId = <String, Map<String, dynamic>>{};
  final order = <String>[];
  for (final c in rawComps) {
    if (c is! Map) continue;
    final m = Map<String, dynamic>.from(c);
    final id = m['id']?.toString();
    if (id == null || id.isEmpty) continue;
    byId[id] = m;
    order.add(id);
  }
  if (byId.isEmpty) return message;

  var counter = 0;
  String freshId(String base) => '${base}_r${++counter}';

  // Deep-clone a subtree rooted at [id], assigning fresh ids throughout.
  // Returns the new root id. Depth-bounded to guard against cycles.
  String cloneSubtree(String id, [int depth = 0]) {
    final src = byId[id]!;
    final copy = Map<String, dynamic>.from(src);
    final nid = freshId(id);
    copy['id'] = nid;
    if (depth < 12) {
      final child = copy['child'];
      if (child is String && byId.containsKey(child)) {
        copy['child'] = cloneSubtree(child, depth + 1);
      }
      final children = copy['children'];
      if (children is List) {
        copy['children'] = [
          for (final c in children)
            if (byId.containsKey(c.toString()))
              cloneSubtree(c.toString(), depth + 1)
            else
              c,
        ];
      }
    }
    byId[nid] = copy;
    order.add(nid);
    return nid;
  }

  // Walk the tree from each parent, claiming children. A child already claimed
  // by another parent is deep-cloned so every node has exactly one parent.
  final claimed = <String>{};
  void claim(String id, [int depth = 0]) {
    if (depth > 24) return; // cycle guard
    final node = byId[id];
    if (node == null) return;

    // Single child (Card, Button label).
    final child = node['child'];
    if (child is String) {
      if (!byId.containsKey(child)) {
        node.remove('child');
      } else {
        var cid = child;
        if (claimed.contains(cid)) cid = cloneSubtree(cid);
        node['child'] = cid;
        claimed.add(cid);
        claim(cid, depth + 1);
      }
    }

    // Children list (Column).
    final children = node['children'];
    if (children is List) {
      final fixed = <String>[];
      for (final raw in children) {
        final ref = raw.toString();
        if (!byId.containsKey(ref)) continue; // drop dangling
        var cid = ref;
        if (claimed.contains(cid)) cid = cloneSubtree(cid);
        fixed.add(cid);
        claimed.add(cid);
        claim(cid, depth + 1);
      }
      node['children'] = fixed;
    }
  }

  // Determine the root: prefer id "root"; else the first node nobody references.
  final referenced = <String>{};
  for (final id in [...order]) {
    final n = byId[id]!;
    if (n['child'] is String) referenced.add(n['child'] as String);
    if (n['children'] is List) {
      referenced.addAll((n['children'] as List).map((e) => e.toString()));
    }
  }
  String rootId;
  if (byId.containsKey('root')) {
    rootId = 'root';
  } else {
    final unref = order.where((id) => !referenced.contains(id)).toList();
    if (unref.length == 1) {
      // Promote the lone top-level node to "root".
      final node = byId.remove(unref.first)!;
      node['id'] = 'root';
      byId['root'] = node;
      order[order.indexOf(unref.first)] = 'root';
      rootId = 'root';
    } else {
      // Wrap all top-level nodes in a new root Column.
      byId['root'] = {
        'id': 'root',
        'component': 'Column',
        'children': unref.isEmpty ? [order.first] : unref,
      };
      order.insert(0, 'root');
      rootId = 'root';
    }
  }

  claimed.add(rootId);
  claim(rootId);

  // Per-component property fixes.
  for (final id in [...order]) {
    final n = byId[id];
    if (n == null) continue;
    final type = n['component']?.toString();
    switch (type) {
      case 'Text':
        n['text'] ??= '';
      case 'Button':
        // Button needs an action.
        if (n['action'] is! Map) {
          n['action'] = {
            'event': {'name': 'action', 'context': <String, dynamic>{}},
          };
        }
        // Button needs a label child.
        if (n['child'] is! String || !byId.containsKey(n['child'])) {
          final labelId = freshId('label');
          byId[labelId] = {'id': labelId, 'component': 'Text', 'text': 'OK'};
          order.add(labelId);
          n['child'] = labelId;
        }
    }
  }

  // Emit only components reachable from root (drop orphans), root first.
  final reachable = <String>[];
  final seen = <String>{};
  void collect(String id, [int depth = 0]) {
    if (depth > 24 || seen.contains(id)) return;
    final n = byId[id];
    if (n == null) return;
    seen.add(id);
    reachable.add(id);
    if (n['child'] is String) collect(n['child'] as String, depth + 1);
    if (n['children'] is List) {
      for (final c in (n['children'] as List)) {
        collect(c.toString(), depth + 1);
      }
    }
  }

  collect(rootId);

  return {
    ...message,
    'updateComponents': {
      ...uc,
      'components': [for (final id in reachable) byId[id]!],
    },
  };
}

/// Full pipeline: take raw model text, return clean fenced A2UI JSON messages
/// ready to feed a genui transport — a `createSurface` (injected if absent)
/// followed by the repaired `updateComponents`.
String repairRawResponse(
  String raw, {
  required String surfaceId,
  required String catalogId,
}) {
  final msgs = extractJsonObjects(raw);
  final hasCreate = msgs.any((m) => m.containsKey('createSurface'));
  final out = <Map<String, dynamic>>[];

  if (!hasCreate) {
    out.add({
      'version': 'v0.9',
      'createSurface': {
        'surfaceId': surfaceId,
        'catalogId': catalogId,
        'sendDataModel': true,
      },
    });
  }
  for (final m in msgs) {
    if (m.containsKey('updateComponents')) {
      final repaired = repairUpdateComponents(m);
      // Small models freely invent their own surfaceId (e.g. "week_summary"),
      // so the components target a surface that was never created and nothing
      // mounts. Force every update onto the surface we actually created.
      final uc = repaired['updateComponents'];
      if (uc is Map) uc['surfaceId'] = surfaceId;
      out.add(repaired);
    } else if (m.containsKey('createSurface')) {
      // Likewise pin a model-emitted createSurface to our surface + catalog.
      final cs = Map<String, dynamic>.from(m['createSurface'] as Map);
      cs['surfaceId'] = surfaceId;
      cs['catalogId'] = catalogId;
      out.add({...m, 'createSurface': cs});
    } else {
      out.add(m);
    }
  }

  return out
      .map(
        (m) => '```json\n${const JsonEncoder.withIndent('  ').convert(m)}\n```',
      )
      .join('\n');
}
