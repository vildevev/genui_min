// The package thesis is prompt size: a small on-device model only works if
// the catalog's system prompt leaves it room to answer. These tests turn
// that thesis into a CI gate — any catalog change (or `extra` component)
// that grows the prompt shows up here before it ships.
import 'package:flutter_test/flutter_test.dart';
import 'package:genui_min/genui_min.dart';

void main() {
  test('default catalog stays under the small-model prompt budget', () {
    // ~4,680 actual (chars/4 heuristic) vs ~19,350 for genui's full
    // BasicCatalog. The ceiling is the contract, not the exact number:
    // small doc tweaks may move it, new components should fail this.
    expect(catalogPromptTokens(styledMinimalCatalog()), lessThan(5200));
  });

  test('every extra component pays a visible, bounded prompt cost', () {
    final base = catalogPromptTokens(styledMinimalCatalog());
    final withRow = catalogPromptTokens(
      styledMinimalCatalog(extra: [styledRow]),
    );
    // Row is a compact schema (~650 tokens); keep additions in that class.
    expect(withRow - base, lessThan(1000));
    // And composition actually works — the extra renders through the same
    // pipeline (covered in the surface tests); here we just pin the dial.
    expect(withRow, greaterThan(base));
  });
}
