// A minimal, *styled* A2UI catalog for small on-device LLMs.
//
// The stock basic catalog components render generic Material defaults (e.g. a
// full-width, left-aligned button). This catalog ships custom widget builders
// for the same A2UI component names (Text · Card · Button · Column) so the
// generated UI looks polished and theme-aware out of the box — a pill button
// that's centered, a padded rounded card, themed text, a centered/spaced
// column. Same component names + schemas as the basic catalog, so the model's
// A2UI JSON (and the system prompt) are unchanged; only the rendering differs.
//
// Pair with `repairRawResponse` (a2ui_repair.dart) for robustness across the
// small-model mistakes that prompting alone won't catch.

import 'dart:async';

import 'package:a2ui_agent/a2ui_agent.dart';
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart' as jsb;

/// A `Text` block. `variant` is `title` (large/bold) or `body` (default).
final ComponentImplementation styledText = ComponentImplementation(
  name: 'Text',
  schema: jsb.S.object(
    description: 'A block of text.',
    properties: {
      'text': jsb.S.string(description: 'The text content to display.'),
      'variant': jsb.S.string(
        description: 'Style hint: "title" for a heading, "body" for normal.',
        enumValues: ['title', 'body'],
      ),
    },
    required: ['text'],
  ),
  builder: (context, node, props, buildChild) {
    final text = props.string('text') ?? '';
    final isTitle = props.string('variant') == 'title';
    final theme = Theme.of(context);
    // No color for body → inherits the ambient DefaultTextStyle (so a label
    // inside a Button picks up the button's foreground color automatically).
    final style = isTitle
        ? TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.25,
            color: theme.colorScheme.onSurface,
          )
        : const TextStyle(fontSize: 15, height: 1.45);
    return Text(text, style: style, textAlign: TextAlign.center);
  },
);

/// A `Card` — a padded, rounded, theme-aware container around one child.
final ComponentImplementation styledCard = ComponentImplementation(
  name: 'Card',
  schema: jsb.S.object(
    description: 'A visual container (card) that groups a single child widget.',
    properties: {'child': CommonSchemas.componentId},
    required: ['child'],
  ),
  builder: (context, node, props, buildChild) {
    final theme = Theme.of(context);
    final childNode = props.child('child');
    final child = childNode == null ? null : buildChild(childNode);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .4),
        ),
      ),
      child: child,
    );
  },
);

/// A `Button` — a centered pill button that dispatches its `action` event.
final ComponentImplementation styledButton = ComponentImplementation(
  name: 'Button',
  schema: jsb.S.object(
    description: 'An interactive button that triggers an action when pressed.',
    properties: {
      'child': _described(
        CommonSchemas.componentId,
        'ID of the Text component used as the button label.',
      ),
      'action': CommonSchemas.action,
      'variant': jsb.S.string(
        description: 'Style hint.',
        enumValues: ['primary', 'borderless'],
      ),
    },
    required: ['child', 'action'],
  ),
  builder: (context, node, props, buildChild) {
    final labelNode = props.child('child');
    final label =
        labelNode == null ? const SizedBox.shrink() : buildChild(labelNode);
    final borderless = props.string('variant') == 'borderless';
    void onPressed() => unawaited(props.action('action')?.call());
    return Align(
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: borderless
            ? TextButton(onPressed: onPressed, child: label)
            : FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: label,
              ),
      ),
    );
  },
);

/// A `Column` — vertical layout, centered cross-axis by default, with spacing.
final ComponentImplementation styledColumn = ComponentImplementation(
  name: 'Column',
  schema: jsb.S.object(
    description: 'A layout widget that arranges its children vertically.',
    properties: {
      'children': _described(
        CommonSchemas.childList,
        'The list of child component IDs.',
      ),
      'justify': jsb.S.string(
        description: 'Main-axis alignment.',
        enumValues: ['start', 'center', 'end', 'spaceBetween'],
      ),
      'align': jsb.S.string(
        description: 'Cross-axis alignment.',
        enumValues: ['start', 'center', 'end', 'stretch'],
      ),
    },
    required: ['children'],
  ),
  builder: (context, node, props, buildChild) {
    final nodes = props.children('children');
    final cross = switch (props.string('align')) {
      'start' => CrossAxisAlignment.start,
      'end' => CrossAxisAlignment.end,
      'stretch' => CrossAxisAlignment.stretch,
      _ => CrossAxisAlignment.center,
    };
    final children = <Widget>[];
    for (var i = 0; i < nodes.length; i++) {
      if (i > 0) children.add(const SizedBox(height: 14));
      children.add(buildChild(nodes[i]));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: cross,
      children: children,
    );
  },
);

/// A `Stat` — a single metric readout: a large value, a caption label, and an
/// optional delta chip (`trend` up = positive/green, down = negative, flat =
/// neutral). Compose several inside a Column for a small dashboard.
final ComponentImplementation styledStat = ComponentImplementation(
  name: 'Stat',
  schema: jsb.S.object(
    description: 'A single metric readout: a large value, a short caption '
        'label, and an optional change indicator. Use this for any number or '
        'metric instead of a plain Text.',
    properties: {
      'value': jsb.S.string(
        description: 'The metric value, e.g. "66", "90%", "5 days".',
      ),
      'label': jsb.S.string(
        description: 'A short caption under the value, e.g. "Glow score".',
      ),
      'delta': jsb.S.string(
        description: 'Optional change text, e.g. "+4" or "up 6%".',
      ),
      'trend': jsb.S.string(
        description: 'Direction of the change, drives color and arrow.',
        enumValues: ['up', 'down', 'flat'],
      ),
    },
    required: ['value'],
  ),
  builder: (context, node, props, buildChild) {
    final value = props.string('value') ?? '';
    final label = props.string('label');
    final delta = props.string('delta');
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (Color deltaColor, IconData? arrow) = switch (props.string('trend')) {
      'up' => (const Color(0xFF4CAF50), Icons.arrow_upward),
      'down' => (cs.error, Icons.arrow_downward),
      _ => (cs.onSurfaceVariant, null),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.0,
            color: cs.primary,
          ),
        ),
        if (label != null && label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
        if (delta != null && delta.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (arrow != null) ...[
                Icon(arrow, size: 14, color: deltaColor),
                const SizedBox(width: 2),
              ],
              Text(
                delta,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: deltaColor,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  },
);

/// A `Row` — horizontal layout with spacing, mirroring the basic catalog's
/// Row schema so prompts stay standard. Compose into the catalog via
/// [styledMinimalCatalog] `extra` when a screen needs side-by-side children.
final ComponentImplementation styledRow = ComponentImplementation(
  name: 'Row',
  schema: jsb.S.object(
    description: 'A layout widget that arranges its children horizontally.',
    properties: {
      'children': _described(
        CommonSchemas.childList,
        'The list of child component IDs.',
      ),
      'justify': jsb.S.string(
        description: 'Main-axis alignment.',
        enumValues: [
          'start',
          'center',
          'end',
          'spaceBetween',
          'spaceAround',
          'spaceEvenly',
        ],
      ),
      'align': jsb.S.string(
        description: 'Cross-axis alignment.',
        enumValues: ['start', 'center', 'end', 'stretch'],
      ),
    },
    required: ['children'],
  ),
  builder: (context, node, props, buildChild) {
    final nodes = props.children('children');
    final main = switch (props.string('justify')) {
      'start' => MainAxisAlignment.start,
      'center' => MainAxisAlignment.center,
      'end' => MainAxisAlignment.end,
      'spaceBetween' => MainAxisAlignment.spaceBetween,
      'spaceAround' => MainAxisAlignment.spaceAround,
      'spaceEvenly' => MainAxisAlignment.spaceEvenly,
      _ => MainAxisAlignment.start,
    };
    final cross = switch (props.string('align')) {
      'start' => CrossAxisAlignment.start,
      'end' => CrossAxisAlignment.end,
      'stretch' => CrossAxisAlignment.stretch,
      _ => CrossAxisAlignment.center,
    };
    final children = <Widget>[];
    for (var i = 0; i < nodes.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 10));
      children.add(buildChild(nodes[i]));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: main,
      crossAxisAlignment: cross,
      children: children,
    );
  },
);

/// [schema], a common A2UI type, with its own [description].
jsb.Schema _described(jsb.Schema schema, String description) =>
    jsb.Schema.fromMap({...schema.value, 'description': description});

/// Concise A2UI rules + a worked few-shot example that keep small models on the
/// rails (unique ids, button with its own label, one child per Card).
const String minimalComponentRules = 'IMPORTANT component rules:\n'
    '- Every component "id" MUST be unique and appear as a child of EXACTLY ONE '
    'parent. NEVER reference the same id from two parents.\n'
    '- A Button MUST have its own dedicated child Text component for its label '
    '(create a new Text; do not reuse another component as the button\'s child).\n'
    '- A Card wraps ONE child (use a Column as that child for multiple things).\n'
    '- For any single number or metric (a score, a streak, a percentage), use a '
    'Stat (value + label) rather than a plain Text.';

const String minimalFewShotExample =
    'COMPLETE EXAMPLE of a card with a title and a button:\n'
    '```json\n'
    '{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[\n'
    '{"id":"root","component":"Column","children":["info_card","cta_button"]},\n'
    '{"id":"info_card","component":"Card","child":"card_text"},\n'
    '{"id":"card_text","component":"Text","text":"Drink water before coffee."},\n'
    '{"id":"cta_button","component":"Button","child":"cta_label","action":{"event":{"name":"cta_clicked","context":{}}}},\n'
    '{"id":"cta_label","component":"Text","text":"Got it"}\n'
    ']}}\n'
    '```\n'
    'Notice: `card_text` and `cta_label` are DIFFERENT components — the button '
    'never reuses the card\'s text.';

/// The id genui gave the A2UI v0.9 basic catalog, which the minimal catalog
/// has always used by default.
const String _defaultCatalogId =
    'https://a2ui.org/specification/v0_9/basic_catalog.json';

/// Build the minimal styled catalog. [catalogId] defaults to
/// `https://a2ui.org/specification/v0_9/basic_catalog.json`, the A2UI v0.9
/// basic catalog id that genui used.
///
/// [extra] composes optional components (e.g. [styledRow]) into the catalog —
/// by name, replacing the basic version if one exists. Every extra widens
/// what the model can build *and* grows the system prompt; check the cost
/// with [catalogPromptTokens] before shipping.
CatalogImplementation styledMinimalCatalog({
  String? catalogId,
  List<ComponentImplementation> extra = const [],
}) {
  final extrasByName = {for (final item in extra) item.name: item};
  final basics = [
    styledText,
    styledCard,
    styledButton,
    styledColumn,
    styledStat,
  ].where((item) => !extrasByName.containsKey(item.name));
  return CatalogImplementation(
    id: catalogId ?? _defaultCatalogId,
    components: [...basics, ...extra],
    instructions: '$minimalComponentRules\n\n$minimalFewShotExample',
  );
}

/// The joined system prompt for a given catalog (chat / create-only mode).
///
/// Built by `a2ui_agent` in its direct JSON format, which asks for A2UI JSON
/// in `<a2ui-json>` tags. [catalog]'s `instructions` are part of it.
String minimalSystemPrompt(CatalogApi catalog) {
  final A2uiRequestProcessor agent = A2uiGenerator(
    catalogs: [CatalogConfig(catalog)],
    inferenceFormatFactory: const DirectJsonFormatFactory(
      allowedMessages: ['createSurface', 'updateComponents'],
    ),
  ).createProcessor(
    A2uiRendererCapabilities.forCatalogIds(
      [catalog.id],
      version: A2uiProtocolVersion.v0_9,
    ),
  );
  return 'IMPORTANT: DO NOT update or modify surfaces created in previous '
      'turns. If the UI needs to change, you MUST create a NEW surface with a '
      'new unique `surfaceId`. You may only use `updateComponents` to '
      'populate the components of a freshly created surface.\n\n'
      '${agent.promptSnippet}';
}

/// Rough token cost of [catalog]'s system prompt (~4 chars/token heuristic —
/// good enough to compare catalogs, not a billing figure). This is the
/// prompt-size dial: every component you add spends from the small model's
/// context here.
int catalogPromptTokens(CatalogApi catalog) =>
    minimalSystemPrompt(catalog).length ~/ 4;
