import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

final _typeConfigs = <String, ItemTypeConfig>{
  'item': const ItemTypeConfig(
    typeName: 'item',
    defaultHeight: 50.0,
    defaultConfidence: 0.5,
  ),
};

List<ReaderItem> _buildItems(int count) {
  return List.generate(
    count,
    (i) => ReaderItem(id: 'item_$i', typeKey: 'item', data: 'Item $i'),
  );
}

void main() {
  group('ReaderView', () {
    testWidgets('renders items from controller', (tester) async {
      final controller = ReaderController(
        items: _buildItems(20),
        typeConfigs: _typeConfigs,
        initialWidth: 390,
      );

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

      // First items should be visible
      expect(find.text('item_0'), findsOneWidget);
      expect(find.text('item_1'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('wraps items in MeasuredItem', (tester) async {
      final controller = ReaderController(
        items: _buildItems(10),
        typeConfigs: _typeConfigs,
        initialWidth: 390,
      );

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

      // MeasuredItem should be in the tree
      expect(find.byType(MeasuredItem), findsWidgets);

      controller.dispose();
    });

    testWidgets('respects padding parameter', (tester) async {
      final controller = ReaderController(
        items: _buildItems(10),
        typeConfigs: _typeConfigs,
        initialWidth: 390,
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderView(
            controller: controller,
            padding: const EdgeInsets.all(16),
            itemBuilder: (_, index, item) => SizedBox(
              height: 50,
              child: Text(item.id),
            ),
          ),
        ),
      );

      // Should render without error
      expect(find.text('item_0'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('swaps controller on widget update', (tester) async {
      final controller1 = ReaderController(
        items: _buildItems(5),
        typeConfigs: _typeConfigs,
        initialWidth: 390,
      );
      final controller2 = ReaderController(
        items: _buildItems(3),
        typeConfigs: _typeConfigs,
        initialWidth: 390,
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderView(
            controller: controller1,
            itemBuilder: (_, index, item) => SizedBox(
              height: 50,
              child: Text(item.id),
            ),
          ),
        ),
      );

      expect(find.text('item_4'), findsOneWidget);

      // Swap to controller2 (fewer items)
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ReaderView(
            controller: controller2,
            itemBuilder: (_, index, item) => SizedBox(
              height: 50,
              child: Text(item.id),
            ),
          ),
        ),
      );

      expect(find.text('item_4'), findsNothing);

      controller1.dispose();
      controller2.dispose();
    });

    testWidgets('scrolling works', (tester) async {
      final controller = ReaderController(
        items: _buildItems(100),
        typeConfigs: _typeConfigs,
        initialWidth: 390,
      );

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

      // item_0 should be visible initially
      expect(find.text('item_0'), findsOneWidget);

      // Fling to scroll down
      await tester.fling(find.byType(ReaderView), const Offset(0, -500), 1000);
      await tester.pumpAndSettle();

      // item_0 should no longer be visible
      expect(find.text('item_0'), findsNothing);

      controller.dispose();
    });
  });

  group('MeasuredItem', () {
    testWidgets('reports measured height after layout', (tester) async {
      double? reportedHeight;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: MeasuredItem(
              itemIndex: 0,
              onMeasured: (h) => reportedHeight = h,
              child: const SizedBox(height: 75, width: 100),
            ),
          ),
        ),
      );

      // Height is reported in a post-frame callback
      await tester.pump();

      expect(reportedHeight, 75.0);
    });

    testWidgets('reports new height when child size changes', (tester) async {
      final heights = <double>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: MeasuredItem(
              itemIndex: 0,
              onMeasured: (h) => heights.add(h),
              child: const SizedBox(height: 50, width: 100),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: MeasuredItem(
              itemIndex: 0,
              onMeasured: (h) => heights.add(h),
              child: const SizedBox(height: 80, width: 100),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(heights, contains(50.0));
      expect(heights, contains(80.0));
    });
  });
}
