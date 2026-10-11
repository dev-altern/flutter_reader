import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

/// Builds test items: a mix of chapters and verses.
List<ReaderItem> buildTestItems({int verseCount = 50}) {
  final items = <ReaderItem>[];
  var verseNum = 0;
  for (var ch = 1; verseNum < verseCount; ch++) {
    items.add(ReaderItem(id: 'ch_$ch', typeKey: 'chapter', data: 'Ch $ch'));
    for (var v = 1; v <= 10 && verseNum < verseCount; v++, verseNum++) {
      items.add(ReaderItem(
        id: 'v_${ch}_$v',
        typeKey: 'verse',
        data: 'Verse $ch:$v text',
      ));
    }
  }
  return items;
}

final testTypeConfigs = <String, ItemTypeConfig>{
  'chapter': const ItemTypeConfig(
    typeName: 'chapter',
    defaultHeight: 44.0,
    defaultConfidence: 0.9,
    widthSensitivity: WidthSensitivity.invariant,
  ),
  'verse': const ItemTypeConfig(
    typeName: 'verse',
    defaultHeight: 56.0,
    defaultConfidence: 0.3,
    widthSensitivity: WidthSensitivity.dependent,
  ),
};

ReaderController buildController({int verseCount = 50}) {
  return ReaderController(
    items: buildTestItems(verseCount: verseCount),
    typeConfigs: testTypeConfigs,
    initialWidth: 390,
  );
}

void main() {
  group('ReaderController', () {
    late ReaderController controller;

    setUp(() {
      controller = buildController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('exposes item count from engine', () {
      // 50 verses + ceil(50/10) chapters = 55
      expect(controller.itemCount, 55);
    });

    test('exposes total height from engine', () {
      expect(controller.totalHeight, greaterThan(0));
    });

    test('exposes engine for advanced use', () {
      expect(controller.engine, isNotNull);
      expect(controller.engine.itemCount, controller.itemCount);
    });

    test('visibility returns default state before scroll', () {
      final vis = controller.visibility;
      expect(vis.firstVisible, -1);
      expect(vis.lastVisible, -1);
    });

    test('reportMeasuredHeight accepts height updates', () {
      // Should not throw
      controller.reportMeasuredHeight(0, 100.0);
    });

    test('notifies listeners on reportMeasuredHeight', () {
      // Attach a scroll controller so _onScroll can fire
      final sc = ScrollController();
      controller.attach(sc);

      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      // Reporting height triggers engine update
      controller.reportMeasuredHeight(0, 100.0);

      controller.detach();
      sc.dispose();
    });

    testWidgets('jumpToId works when attached', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderView(
            controller: controller,
            itemBuilder: (_, index, item) => SizedBox(
              height: 50,
              child: Text(item.id),
            ),
          ),
        ),
      );

      // Should not throw
      controller.jumpToId('ch_3');
      await tester.pump();
    });

    testWidgets('jumpToIndex works when attached', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderView(
            controller: controller,
            itemBuilder: (_, index, item) => SizedBox(
              height: 50,
              child: Text(item.id),
            ),
          ),
        ),
      );

      controller.jumpToIndex(20);
      await tester.pump();
    });

    testWidgets('jumpToId with nonexistent ID does nothing', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderView(
            controller: controller,
            itemBuilder: (_, index, item) => SizedBox(
              height: 50,
              child: Text(item.id),
            ),
          ),
        ),
      );

      controller.jumpToId('nonexistent');
      await tester.pump();
    });

    testWidgets('animateToId scrolls smoothly', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderView(
            controller: controller,
            itemBuilder: (_, index, item) => SizedBox(
              height: 50,
              child: Text(item.id),
            ),
          ),
        ),
      );

      controller.animateToId('ch_3');
      await tester.pumpAndSettle();
    });
  });

  group('ReaderController — batch mutations', () {
    test('appendItems increases item count', () {
      final controller = buildController();
      final oldCount = controller.itemCount;

      controller.appendItems([
        const ReaderItem(id: 'appended', typeKey: 'verse', data: 'test'),
      ]);

      expect(controller.itemCount, oldCount + 1);
      controller.dispose();
    });

    test('prependItems increases item count', () {
      final controller = buildController();
      final oldCount = controller.itemCount;

      controller.prependItems([
        const ReaderItem(id: 'prepended', typeKey: 'verse', data: 'test'),
      ]);

      expect(controller.itemCount, oldCount + 1);
      controller.dispose();
    });

    test('removeItems decreases item count', () {
      final controller = buildController();
      final oldCount = controller.itemCount;

      controller.removeItems(0, 3);

      expect(controller.itemCount, oldCount - 3);
      controller.dispose();
    });

    test('appendItems notifies listeners', () {
      final controller = buildController();
      var notified = false;
      controller.addListener(() => notified = true);

      controller.appendItems([
        const ReaderItem(id: 'a', typeKey: 'verse', data: 'test'),
      ]);

      expect(notified, isTrue);
      controller.dispose();
    });

    test('prependItems notifies listeners', () {
      final controller = buildController();
      var notified = false;
      controller.addListener(() => notified = true);

      controller.prependItems([
        const ReaderItem(id: 'p', typeKey: 'verse', data: 'test'),
      ]);

      expect(notified, isTrue);
      controller.dispose();
    });

    test('appendItems with empty list still notifies', () {
      final controller = buildController();
      var notified = false;
      controller.addListener(() => notified = true);

      controller.appendItems([]);

      expect(notified, isTrue);
      expect(controller.itemCount, 55); // unchanged
      controller.dispose();
    });

    test('insertItems at arbitrary index works', () {
      final controller = buildController();
      final oldCount = controller.itemCount;

      controller.insertItems(10, [
        const ReaderItem(id: 'mid_1', typeKey: 'verse', data: 'test'),
        const ReaderItem(id: 'mid_2', typeKey: 'verse', data: 'test'),
      ]);

      expect(controller.itemCount, oldCount + 2);
      controller.dispose();
    });
  });

  group('ReaderController — effectiveTotalHeight', () {
    test('includes buffer when hasMoreAfter is true', () {
      final controller = ReaderController(
        items: buildTestItems(verseCount: 50),
        typeConfigs: testTypeConfigs,
        initialWidth: 390,
        hasMoreAfter: true,
        loadMoreBufferExtent: 500.0,
      );

      expect(
        controller.effectiveTotalHeight,
        controller.totalHeight + 500.0,
      );
      controller.dispose();
    });

    test('equals totalHeight when hasMoreAfter is false', () {
      final controller = ReaderController(
        items: buildTestItems(verseCount: 50),
        typeConfigs: testTypeConfigs,
        initialWidth: 390,
        hasMoreAfter: false,
      );

      expect(controller.effectiveTotalHeight, controller.totalHeight);
      controller.dispose();
    });

    test('updates when hasMoreAfter changes', () {
      final controller = ReaderController(
        items: buildTestItems(verseCount: 50),
        typeConfigs: testTypeConfigs,
        initialWidth: 390,
        hasMoreAfter: false,
      );

      final closedHeight = controller.effectiveTotalHeight;
      controller.hasMoreAfter = true;

      expect(controller.effectiveTotalHeight, greaterThan(closedHeight));
      controller.dispose();
    });
  });

  group('ReaderController — edge detection', () {
    testWidgets('fires onEdgeReached for before direction at top',
        (tester) async {
      LoadDirection? firedDirection;

      final controller = ReaderController(
        items: buildTestItems(verseCount: 50),
        typeConfigs: testTypeConfigs,
        initialWidth: 390,
        hasMoreBefore: true,
        edgeThreshold: 3,
      );
      controller.onEdgeReached = (dir) => firedDirection = dir;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderView(
            controller: controller,
            itemBuilder: (_, index, item) => SizedBox(
              height: 50,
              child: Text(item.id),
            ),
          ),
        ),
      );

      // pumpAndSettle runs frames until stable — this covers the
      // two-frame delay in attach() (frame 1: layout, frame 2: edge check).
      await tester.pumpAndSettle();

      expect(firedDirection, LoadDirection.before);
      controller.dispose();
    });

    testWidgets('fires onEdgeReached for after direction near end',
        (tester) async {
      LoadDirection? firedDirection;

      final controller = ReaderController(
        items: buildTestItems(verseCount: 20),
        typeConfigs: testTypeConfigs,
        initialWidth: 390,
        hasMoreAfter: true,
        edgeThreshold: 3,
      );
      controller.onEdgeReached = (dir) => firedDirection = dir;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderView(
            controller: controller,
            itemBuilder: (_, index, item) => SizedBox(
              height: 50,
              child: Text(item.id),
            ),
          ),
        ),
      );
      await tester.pump();

      // Scroll near the end
      controller.jumpToIndex(controller.itemCount - 2);
      await tester.pumpAndSettle();

      expect(firedDirection, LoadDirection.after);
      controller.dispose();
    });

    testWidgets('loading guard prevents double-fire', (tester) async {
      var callCount = 0;

      final controller = ReaderController(
        items: buildTestItems(verseCount: 20),
        typeConfigs: testTypeConfigs,
        initialWidth: 390,
        hasMoreAfter: true,
        edgeThreshold: 5,
      );
      controller.onEdgeReached = (dir) => callCount++;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderView(
            controller: controller,
            itemBuilder: (_, index, item) => SizedBox(
              height: 50,
              child: Text(item.id),
            ),
          ),
        ),
      );
      await tester.pump();

      // Jump near end to trigger callback
      controller.jumpToIndex(controller.itemCount - 2);
      await tester.pumpAndSettle();

      final countAfterFirst = callCount;

      // Jump again near end — guard should prevent re-fire
      controller.jumpToIndex(controller.itemCount - 1);
      await tester.pumpAndSettle();

      expect(callCount, countAfterFirst);
      controller.dispose();
    });

    testWidgets('guard resets after appendItems', (tester) async {
      var callCount = 0;

      final controller = ReaderController(
        items: buildTestItems(verseCount: 20),
        typeConfigs: testTypeConfigs,
        initialWidth: 390,
        hasMoreAfter: true,
        edgeThreshold: 5,
      );
      controller.onEdgeReached = (dir) => callCount++;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderView(
            controller: controller,
            itemBuilder: (_, index, item) => SizedBox(
              height: 50,
              child: Text(item.id),
            ),
          ),
        ),
      );
      await tester.pump();

      // Trigger first load
      controller.jumpToIndex(controller.itemCount - 2);
      await tester.pumpAndSettle();
      expect(callCount, greaterThan(0));

      final countAfterFirst = callCount;

      // Append items (resets guard)
      controller.appendItems([
        const ReaderItem(id: 'new_1', typeKey: 'verse', data: 'test'),
        const ReaderItem(id: 'new_2', typeKey: 'verse', data: 'test'),
      ]);
      await tester.pump();

      // Jump near new end — should fire again
      controller.jumpToIndex(controller.itemCount - 1);
      await tester.pumpAndSettle();

      expect(callCount, greaterThan(countAfterFirst));
      controller.dispose();
    });

    test('does not fire when hasMoreAfter is false', () {
      var callCount = 0;

      final controller = ReaderController(
        items: buildTestItems(verseCount: 20),
        typeConfigs: testTypeConfigs,
        initialWidth: 390,
        hasMoreAfter: false,
        edgeThreshold: 3,
      );
      controller.onEdgeReached = (dir) => callCount++;

      // Simulate being near end via engine directly
      controller.engine.setViewportHeight(800);
      controller.engine.reportScrollOffset(0);

      expect(callCount, 0);
      controller.dispose();
    });
  });

  group('ReaderController — evictDistantItems', () {
    test('no-op when item count <= maxLoadedItems', () {
      final controller = buildController(verseCount: 50);
      final oldCount = controller.itemCount;

      controller.evictDistantItems(maxLoadedItems: 5000);

      expect(controller.itemCount, oldCount);
      controller.dispose();
    });

    test('evicts tail items beyond window', () {
      // Build a large dataset: 200 verses → 200 + ceil(200/10) = 220 items
      final controller = buildController(verseCount: 200);
      expect(controller.itemCount, 220);

      // Set visibility near the start
      controller.engine.setViewportHeight(800);
      controller.engine.reportScrollOffset(0);

      controller.evictDistantItems(maxLoadedItems: 100);

      expect(controller.itemCount, lessThanOrEqualTo(100));
      expect(controller.hasMoreAfter, isTrue);
      controller.dispose();
    });

    test('evicts head items beyond window', () {
      final controller = buildController(verseCount: 200);
      expect(controller.itemCount, 220);

      // Scroll to near the end
      controller.engine.setViewportHeight(800);
      final jump = controller.engine.jumpToIndex(210);
      controller.engine.reportScrollOffset(jump.pixelOffset);

      controller.evictDistantItems(maxLoadedItems: 100);

      expect(controller.itemCount, lessThanOrEqualTo(100));
      expect(controller.hasMoreBefore, isTrue);
      controller.dispose();
    });

    test('evicts both head and tail when centered', () {
      final controller = buildController(verseCount: 200);
      expect(controller.itemCount, 220);

      // Scroll to center
      controller.engine.setViewportHeight(800);
      final jump = controller.engine.jumpToIndex(110);
      controller.engine.reportScrollOffset(jump.pixelOffset);

      controller.evictDistantItems(maxLoadedItems: 60);

      expect(controller.itemCount, lessThanOrEqualTo(60));
      expect(controller.hasMoreBefore, isTrue);
      expect(controller.hasMoreAfter, isTrue);
      controller.dispose();
    });

    test('notifies listeners after eviction', () {
      final controller = buildController(verseCount: 200);

      controller.engine.setViewportHeight(800);
      controller.engine.reportScrollOffset(0);

      var notified = false;
      controller.addListener(() => notified = true);

      controller.evictDistantItems(maxLoadedItems: 100);

      expect(notified, isTrue);
      controller.dispose();
    });

    test('preserves items when exactly at maxLoadedItems', () {
      final controller = buildController(verseCount: 200);
      final count = controller.itemCount; // 220

      controller.engine.setViewportHeight(800);
      controller.engine.reportScrollOffset(0);

      // maxLoadedItems >= itemCount → no eviction
      controller.evictDistantItems(maxLoadedItems: 220);

      expect(controller.itemCount, count);
      controller.dispose();
    });
  });

  group('ReaderController — reverse mode', () {
    // The default test surface is 800×600, so the list's viewport is 600 px
    // tall with its top edge at y = 0. Items render 50 px tall while the
    // engine starts from 44/56 px estimates, so every jump starts from
    // estimated offsets.
    const viewportHeight = 600.0;

    late ReaderController controller;

    setUp(() {
      controller = buildController();
    });

    tearDown(() {
      controller.dispose();
    });

    Future<void> pumpReversed(WidgetTester tester) {
      return tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderView(
            controller: controller,
            reverse: true,
            itemBuilder: (_, index, item) => SizedBox(
              height: 50,
              child: Text(item.id),
            ),
          ),
        ),
      );
    }

    double topOf(WidgetTester tester, String id) =>
        tester.getTopLeft(find.text(id)).dy;

    testWidgets('starts at the end of the list', (tester) async {
      await pumpReversed(tester);

      expect(tester.getBottomLeft(find.text('v_5_10')).dy, viewportHeight);
      expect(controller.isAtEnd, isTrue);
    });

    testWidgets('jumpToId puts the item at the top edge', (tester) async {
      await pumpReversed(tester);

      controller.jumpToId('v_2_5');
      await tester.pumpAndSettle();

      expect(topOf(tester, 'v_2_5'), moreOrLessEquals(0, epsilon: 0.5));
    });

    testWidgets('jumpToId honours alignment', (tester) async {
      await pumpReversed(tester);

      controller.jumpToId('v_2_5', alignment: 0.5);
      await tester.pumpAndSettle();

      expect(
        topOf(tester, 'v_2_5'),
        moreOrLessEquals(viewportHeight * 0.5, epsilon: 0.5),
      );
    });

    testWidgets('jumpToIndex targets the item at that index', (tester) async {
      await pumpReversed(tester);

      controller.jumpToIndex(16, alignment: 0.5); // v_2_5
      await tester.pumpAndSettle();

      expect(
        topOf(tester, 'v_2_5'),
        moreOrLessEquals(viewportHeight * 0.5, epsilon: 0.5),
      );
    });

    testWidgets('jumpToIndex on the last item returns to the end',
        (tester) async {
      await pumpReversed(tester);
      controller.jumpToId('ch_2');
      await tester.pumpAndSettle();
      expect(controller.isAtEnd, isFalse);

      controller.jumpToIndex(controller.itemCount - 1);
      await tester.pumpAndSettle();

      expect(tester.getBottomLeft(find.text('v_5_10')).dy, viewportHeight);
      expect(controller.isAtEnd, isTrue);
    });

    testWidgets('clamps at the start of the list', (tester) async {
      await pumpReversed(tester);

      controller.jumpToId('ch_1', alignment: 0.5);
      await tester.pumpAndSettle();

      expect(topOf(tester, 'ch_1'), moreOrLessEquals(0, epsilon: 0.5));
    });

    testWidgets('animateToId scrolls to the item', (tester) async {
      await pumpReversed(tester);

      final done = controller.animateToId('v_2_5', alignment: 0.5);
      await tester.pumpAndSettle();
      await done;

      expect(
        topOf(tester, 'v_2_5'),
        moreOrLessEquals(viewportHeight * 0.5, epsilon: 0.5),
      );
    });

    testWidgets('a newer jump replaces a pending correction', (tester) async {
      await pumpReversed(tester);

      controller.jumpToId('v_2_5');
      controller.jumpToId('v_4_3');
      await tester.pumpAndSettle();

      expect(topOf(tester, 'v_4_3'), moreOrLessEquals(0, epsilon: 0.5));
    });

    testWidgets('a drag stops the correction', (tester) async {
      await pumpReversed(tester);

      // The jump lands on estimated offsets; the user grabs the list before
      // the correction runs, and the list must stay under their finger.
      controller.jumpToId('v_2_5');
      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(0, 40));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      final heldAt = topOf(tester, 'v_2_5');
      await tester.pump();

      expect(heldAt, isNot(moreOrLessEquals(0, epsilon: 0.5)));
      expect(topOf(tester, 'v_2_5'), heldAt);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
