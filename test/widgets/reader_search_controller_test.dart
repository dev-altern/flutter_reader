import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

ReaderController _buildController({
  List<ReaderItem>? items,
  int count = 20,
}) {
  final list = items ??
      List.generate(
        count,
        (i) => ReaderItem(
          id: 'item_$i',
          typeKey: 'text',
          data: 'This is item number $i with some searchable text.',
        ),
      );
  return ReaderController(
    items: list,
    typeConfigs: {
      'text': const ItemTypeConfig(
        typeName: 'text',
        defaultHeight: 50.0,
        defaultConfidence: 0.5,
      ),
      'header': const ItemTypeConfig(
        typeName: 'header',
        defaultHeight: 40.0,
        defaultConfidence: 0.9,
      ),
    },
    initialWidth: 390,
  );
}

void main() {
  group('SearchMatch', () {
    test('matchedText extracts correct substring', () {
      final match = SearchMatch(
        itemIndex: 0,
        itemId: 'item_0',
        text: 'Hello world',
        matchStart: 6,
        matchEnd: 11,
      );

      expect(match.matchedText, 'world');
    });
  });

  group('ReaderSearchController', () {
    late ReaderController reader;
    late ReaderSearchController search;

    setUp(() {
      reader = _buildController();
      search = ReaderSearchController(
        reader: reader,
        textExtractors: {
          'text': (data) => data as String,
        },
        debounceDuration: Duration.zero,
      );
    });

    tearDown(() {
      reader.dispose();
    });

    test('initial state is inactive with no matches', () {
      expect(search.isActive, isFalse);
      expect(search.query, '');
      expect(search.matches, isEmpty);
      expect(search.matchCount, 0);
      expect(search.hasMatches, isFalse);
      expect(search.currentMatchIndex, -1);
      expect(search.currentMatch, isNull);
      expect(search.currentMatchDisplay, '');
    });

    test('search finds matches', () {
      search.search('item number');

      expect(search.isActive, isTrue);
      expect(search.query, 'item number');
      expect(search.matchCount, 20); // Every item has "item number"
      expect(search.hasMatches, isTrue);
      expect(search.currentMatchIndex, 0);
      expect(search.currentMatch, isNotNull);
      expect(search.currentMatch!.itemIndex, 0);
    });

    test('search is case-insensitive', () {
      search.search('ITEM NUMBER');

      expect(search.matchCount, 20);
    });

    test('search trims whitespace', () {
      search.search('  item number  ');

      expect(search.query, 'item number');
      expect(search.matchCount, 20);
    });

    test('empty query clears search', () {
      search.search('item');
      expect(search.isActive, isTrue);

      search.search('');
      expect(search.isActive, isFalse);
      expect(search.matches, isEmpty);
    });

    test('whitespace-only query clears search', () {
      search.search('item');
      expect(search.isActive, isTrue);

      search.search('   ');
      expect(search.isActive, isFalse);
    });

    test('no results sets proper state', () {
      search.search('xyznonexistent');

      expect(search.isActive, isTrue);
      expect(search.hasMatches, isFalse);
      expect(search.matchCount, 0);
      expect(search.currentMatchIndex, -1);
      expect(search.currentMatch, isNull);
      expect(search.currentMatchDisplay, 'No results');
    });

    test('currentMatchDisplay shows position', () {
      search.search('item number');

      expect(search.currentMatchDisplay, '1 of 20');
    });

    test('nextMatch advances index', () {
      search.search('item number');
      expect(search.currentMatchIndex, 0);

      search.nextMatch();
      expect(search.currentMatchIndex, 1);

      search.nextMatch();
      expect(search.currentMatchIndex, 2);
    });

    test('nextMatch wraps around', () {
      search.search('item number');

      // Jump to last
      for (var i = 0; i < 19; i++) {
        search.nextMatch();
      }
      expect(search.currentMatchIndex, 19);

      // Wraps to first
      search.nextMatch();
      expect(search.currentMatchIndex, 0);
    });

    test('previousMatch goes backwards', () {
      search.search('item number');
      search.nextMatch(); // index 1
      search.nextMatch(); // index 2

      search.previousMatch();
      expect(search.currentMatchIndex, 1);
    });

    test('previousMatch wraps to last', () {
      search.search('item number');
      expect(search.currentMatchIndex, 0);

      search.previousMatch();
      expect(search.currentMatchIndex, 19);
    });

    test('jumpToMatch sets index directly', () {
      search.search('item number');

      search.jumpToMatch(10);
      expect(search.currentMatchIndex, 10);
    });

    test('jumpToMatch ignores out-of-range index', () {
      search.search('item number');
      search.jumpToMatch(5);

      search.jumpToMatch(-1);
      expect(search.currentMatchIndex, 5); // Unchanged

      search.jumpToMatch(100);
      expect(search.currentMatchIndex, 5); // Unchanged
    });

    test('nextMatch/previousMatch do nothing with no matches', () {
      search.search('xyznonexistent');

      search.nextMatch();
      expect(search.currentMatchIndex, -1);

      search.previousMatch();
      expect(search.currentMatchIndex, -1);
    });

    test('clear resets all state', () {
      search.search('item');
      expect(search.isActive, isTrue);

      search.clear();
      expect(search.isActive, isFalse);
      expect(search.query, '');
      expect(search.matches, isEmpty);
      expect(search.matchCount, 0);
      expect(search.currentMatchIndex, -1);
    });

    test('isItemMatch returns true for matched items', () {
      search.search('item number');

      expect(search.isItemMatch(0), isTrue);
      expect(search.isItemMatch(5), isTrue);
    });

    test('isCurrentMatch returns true only for current match item', () {
      search.search('item number');

      expect(search.isCurrentMatch(0), isTrue);
      expect(search.isCurrentMatch(1), isFalse);

      search.nextMatch();
      expect(search.isCurrentMatch(0), isFalse);
      expect(search.isCurrentMatch(1), isTrue);
    });

    test('notifies listeners on search', () {
      var count = 0;
      search.addListener(() => count++);

      search.search('item');
      expect(count, 1);
    });

    test('notifies listeners on clear', () {
      search.search('item');
      var count = 0;
      search.addListener(() => count++);

      search.clear();
      expect(count, 1);
    });

    test('notifies listeners on nextMatch', () {
      search.search('item');
      var count = 0;
      search.addListener(() => count++);

      search.nextMatch();
      expect(count, 1);
    });

    test('notifies listeners on previousMatch', () {
      search.search('item');
      var count = 0;
      search.addListener(() => count++);

      search.previousMatch();
      expect(count, 1);
    });

    test('notifies listeners on jumpToMatch', () {
      search.search('item');
      var count = 0;
      search.addListener(() => count++);

      search.jumpToMatch(5);
      expect(count, 1);
    });

    test('finds multiple matches within a single item', () {
      final controller = _buildController(
        items: [
          ReaderItem(
            id: 'item_0',
            typeKey: 'text',
            data: 'the cat and the dog and the bird',
          ),
        ],
      );
      final s = ReaderSearchController(
        reader: controller,
        textExtractors: {'text': (data) => data as String},
        debounceDuration: Duration.zero,
      );

      s.search('the');
      expect(s.matchCount, 3); // "the" appears 3 times
      expect(s.matches[0].matchStart, 0);
      expect(s.matches[1].matchStart, 12);
      expect(s.matches[2].matchStart, 24);

      controller.dispose();
    });

    test('skips items with no matching extractor', () {
      final controller = _buildController(
        items: [
          ReaderItem(id: 'h_1', typeKey: 'header', data: 'Chapter One'),
          ReaderItem(
            id: 'item_0',
            typeKey: 'text',
            data: 'searchable text',
          ),
        ],
      );
      final s = ReaderSearchController(
        reader: controller,
        textExtractors: {
          'text': (data) => data as String,
          // No extractor for 'header'
        },
        debounceDuration: Duration.zero,
      );

      s.search('Chapter');
      expect(s.matchCount, 0); // Header is not searchable

      s.search('searchable');
      expect(s.matchCount, 1);

      controller.dispose();
    });

    test('handles extractor that throws', () {
      final controller = _buildController(
        items: [
          ReaderItem(id: 'item_0', typeKey: 'text', data: null),
          ReaderItem(
            id: 'item_1',
            typeKey: 'text',
            data: 'valid text',
          ),
        ],
      );
      final s = ReaderSearchController(
        reader: controller,
        textExtractors: {
          'text': (data) => data as String, // Will throw on null
        },
        debounceDuration: Duration.zero,
      );

      // Should not throw — bad item is skipped
      s.search('valid');
      expect(s.matchCount, 1);
      expect(s.matches[0].itemId, 'item_1');

      controller.dispose();
    });

    test('match records correct offsets', () {
      search.search('item number 5');

      final match =
          search.matches.where((m) => m.itemId == 'item_5').firstOrNull;
      expect(match, isNotNull);
      expect(match!.matchedText, 'item number 5');
    });

    test('re-searching updates matches', () {
      search.search('item number 1');
      // Matches: item_1, item_10..item_19 = 11 matches
      final countFirst = search.matchCount;
      expect(countFirst, greaterThan(0));

      search.search('item number 0');
      expect(search.matchCount, 1); // Only item_0
      expect(search.currentMatchIndex, 0);
    });
  });
}
