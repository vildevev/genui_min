// A minimal, *styled* genui catalog for small on-device LLMs.
//
// genui's stock `BasicCatalogItems` render generic Material defaults (e.g. a
// full-width, left-aligned button). This catalog ships custom widget builders
// for the same A2UI component names (Text · Card · Button · Column) so the
// generated UI looks polished and theme-aware out of the box — a pill button
// that's centered, a padded rounded card, themed text, a centered/spaced
// column. Same component names + schemas as the basic catalog, so the model's
// A2UI JSON (and the system prompt) are unchanged; only the rendering differs.
//
// Pair with `repairRawResponse` (a2ui_repair.dart) for robustness across the
// small-model mistakes that prompting alone won't catch.

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart' as jsb;

/// A `Text` block. `variant` is `title` (large/bold) or `body` (default).
final CatalogItem styledText = CatalogItem(
  name: 'Text',
  dataSchema: jsb.S.object(
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
  widgetBuilder: (ctx) {
    final data = ctx.data as JsonMap;
    final text = (data['text'] ?? '').toString();
    final isTitle = data['variant']?.toString() == 'title';
    final theme = Theme.of(ctx.buildContext);
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
final CatalogItem styledCard = CatalogItem(
  name: 'Card',
  dataSchema: jsb.S.object(
    description: 'A visual container (card) that groups a single child widget.',
    properties: {'child': A2uiSchemas.componentReference()},
    required: ['child'],
  ),
  widgetBuilder: (ctx) {
    final data = ctx.data as JsonMap;
    final theme = Theme.of(ctx.buildContext);
    final child = ctx.buildChild((data['child'] ?? '').toString());
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
final CatalogItem styledButton = CatalogItem(
  name: 'Button',
  dataSchema: jsb.S.object(
    description: 'An interactive button that triggers an action when pressed.',
    properties: {
      'child': A2uiSchemas.componentReference(
        description: 'ID of the Text component used as the button label.',
      ),
      'action': A2uiSchemas.action(),
      'variant': jsb.S.string(
        description: 'Style hint.',
        enumValues: ['primary', 'borderless'],
      ),
    },
    required: ['child', 'action'],
  ),
  widgetBuilder: (ctx) {
    final data = ctx.data as JsonMap;
    final label = ctx.buildChild((data['child'] ?? '').toString());
    final borderless = data['variant']?.toString() == 'borderless';
    void onPressed() => _dispatchAction(ctx, data['action']);
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
final CatalogItem styledColumn = CatalogItem(
  name: 'Column',
  dataSchema: jsb.S.object(
    description: 'A layout widget that arranges its children vertically.',
    properties: {
      'children': A2uiSchemas.componentArrayReference(
        description: 'The list of child component IDs.',
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
  widgetBuilder: (ctx) {
    final data = ctx.data as JsonMap;
    final childrenRaw = data['children'];
    final ids = childrenRaw is List
        ? childrenRaw.map((e) => e.toString()).toList()
        : const <String>[];
    final cross = switch (data['align']?.toString()) {
      'start' => CrossAxisAlignment.start,
      'end' => CrossAxisAlignment.end,
      'stretch' => CrossAxisAlignment.stretch,
      _ => CrossAxisAlignment.center,
    };
    final children = <Widget>[];
    for (var i = 0; i < ids.length; i++) {
      if (i > 0) children.add(const SizedBox(height: 14));
      children.add(ctx.buildChild(ids[i]));
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
final CatalogItem styledStat = CatalogItem(
  name: 'Stat',
  dataSchema: jsb.S.object(
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
  widgetBuilder: (ctx) {
    final data = ctx.data as JsonMap;
    final value = (data['value'] ?? '').toString();
    final label = data['label']?.toString();
    final delta = data['delta']?.toString();
    final theme = Theme.of(ctx.buildContext);
    final cs = theme.colorScheme;
    final (Color deltaColor, IconData? arrow) = switch (data['trend']
        ?.toString()) {
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

void _dispatchAction(CatalogItemContext ctx, Object? action) {
  if (action is! Map) return;
  final event = action['event'];
  if (event is! Map) return;
  ctx.dispatchEvent(
    UserActionEvent(
      name: (event['name'] ?? 'action').toString(),
      sourceComponentId: ctx.id,
      context: event['context'] is Map
          ? Map<String, Object?>.from(event['context'] as Map)
          : <String, Object?>{},
    ),
  );
}

/// Concise A2UI rules + a worked few-shot example that keep small models on the
/// rails (unique ids, button with its own label, one child per Card).
const String minimalComponentRules =
    'IMPORTANT component rules:\n'
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

/// Build the minimal styled catalog. [catalogId] defaults to the A2UI basic
/// catalog id so it interops with the basic-catalog system prompt scaffolding.
Catalog styledMinimalCatalog({String? catalogId}) => Catalog(
  [styledText, styledCard, styledButton, styledColumn, styledStat],
  functions: const [],
  catalogId: catalogId ?? basicCatalogId,
  systemPromptFragments: [
    BasicCatalogItems.basicCatalogRules,
    minimalComponentRules,
    minimalFewShotExample,
  ],
);

/// The joined system prompt for a given catalog (chat / create-only mode).
String minimalSystemPrompt(Catalog catalog) =>
    PromptBuilder.chat(catalog: catalog).systemPromptJoined();
