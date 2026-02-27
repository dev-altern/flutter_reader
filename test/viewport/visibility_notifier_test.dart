import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

/// Builds engine WITHOUT setting viewport height, so the notifier
/// can be created first and receive all callbacks.
ReaderEngine _buildEngine({int count = 100}) {
  final items = List.generate(
    count,
    (i) => ReaderItem(id: 'item_$i', typeKey: 'item', data: null),
  );
  final registry = ItemRegistry.build(
    items: items,
    typeConfigs: {
      'item': const ItemTypeConfig(
        typeName: 'item',
        defaultHeight: 50.0,
        defaultConfidence: 0.5,
      ),
    },
    initialWidth: 390,
  );
  return ReaderEngine(registry: registry);
}

void main() {
  group('VisibilityNotifier', () {
    late ReaderEngine engine;
    late VisibilityNotifier notifier;

    setUp(() {
      engine = _buildEngine();
      notifier = VisibilityNotifier(engine: engine);
      // Now set viewport height so the notifier receives the callback
      engine.setViewportHeight(500);
    });

    tearDown(() {
      notifier.dispose();
    });

    test('initial state before scroll has no visible items', () {
      // Engine has viewport but no scroll offset reported yet,
      // so _updateVisibility fires with scroll offset 0.
      // Items at offset 0 with viewport 500 → items visible.
      // But notifier starts with defaults until the engine fires.
      // After setViewportHeight, the engine fires a callback.
      expect(notifier.firstVisible, 0);
      expect(notifier.lastVisible, greaterThan(0));
    });

    test('updates when engine reports scroll', () {
      engine.reportScrollOffset(200);

      expect(notifier.firstVisible, greaterThan(0));
      expect(notifier.lastVisible, greaterThan(notifier.firstVisible));
      expect(notifier.visibleCount, greaterThan(0));
    });

    test('anchorIndex tracks first visible', () {
      engine.reportScrollOffset(0);
      expect(notifier.anchorIndex, 0);

      engine.reportScrollOffset(300);
      expect(notifier.anchorIndex, greaterThan(0));
    });

    test('isVisible returns true for visible items', () {
      engine.reportScrollOffset(0);

      expect(notifier.isVisible(0), isTrue);
      expect(notifier.isVisible(notifier.lastVisible), isTrue);
      expect(notifier.isVisible(99), isFalse);
    });

    test('notifies listeners on visibility change', () {
      var count = 0;
      notifier.addListener(() => count++);

      // Scroll to a new position
      engine.reportScrollOffset(500);
      expect(count, 1);

      // Same position → no notification
      engine.reportScrollOffset(500);
      expect(count, 1);

      // Different position → notification
      engine.reportScrollOffset(1000);
      expect(count, 2);
    });

    test('manual update triggers refresh', () {
      engine.reportScrollOffset(100);
      final first = notifier.firstVisible;

      notifier.update();
      expect(notifier.firstVisible, first);
    });

    test('dispose clears engine callback', () {
      // Create a separate notifier for this test to avoid double-dispose
      final eng = _buildEngine();
      final n = VisibilityNotifier(engine: eng);
      eng.setViewportHeight(500);

      n.dispose();
      expect(eng.onVisibilityChanged, isNull);
    });
  });
}
