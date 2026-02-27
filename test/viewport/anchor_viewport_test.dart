import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

ReaderEngine _buildEngine({int count = 100, double itemHeight = 50.0}) {
  final items = List.generate(
    count,
    (i) => ReaderItem(id: 'item_$i', typeKey: 'item', data: null),
  );
  final registry = ItemRegistry.build(
    items: items,
    typeConfigs: {
      'item': ItemTypeConfig(
        typeName: 'item',
        defaultHeight: itemHeight,
        defaultConfidence: 0.5,
      ),
    },
    initialWidth: 390,
  );
  final engine = ReaderEngine(registry: registry);
  engine.setViewportHeight(500);
  return engine;
}

void main() {
  group('AnchorTracker', () {
    late ReaderEngine engine;
    late AnchorTracker anchor;

    setUp(() {
      engine = _buildEngine();
      anchor = AnchorTracker(engine: engine);
    });

    test('initial state is index 0 offset 0', () {
      expect(anchor.anchorIndex, 0);
      expect(anchor.anchorVisualOffset, 0.0);
    });

    test('onScroll updates anchor index and visual offset', () {
      // Scroll to 200px — item 4 at height 50 each
      anchor.onScroll(200, 500);

      expect(anchor.anchorIndex, 4); // 200 / 50 = item 4
      expect(anchor.anchorVisualOffset, closeTo(0, 0.1));
    });

    test('onScroll mid-item sets fractional visual offset', () {
      // Scroll to 225px — item 4 starts at 200, so visual offset = -25
      anchor.onScroll(225, 500);

      expect(anchor.anchorIndex, 4);
      expect(anchor.anchorVisualOffset, closeTo(-25, 0.1));
    });

    test('computeCompensation returns 0 when nothing changed', () {
      anchor.onScroll(200, 500);

      final comp = anchor.computeCompensation(200);
      expect(comp, closeTo(0, 0.1));
    });

    test('snapshot and restore preserve state', () {
      anchor.onScroll(300, 500);

      final snap = anchor.snapshot();
      expect(snap.index, anchor.anchorIndex);
      expect(snap.visualOffset, anchor.anchorVisualOffset);

      anchor.reset();
      expect(anchor.anchorIndex, 0);

      anchor.restore(snap);
      expect(anchor.anchorIndex, snap.index);
      expect(anchor.anchorVisualOffset, snap.visualOffset);
    });

    test('reset clears state', () {
      anchor.onScroll(500, 500);
      anchor.reset();

      expect(anchor.anchorIndex, 0);
      expect(anchor.anchorVisualOffset, 0.0);
    });
  });
}
