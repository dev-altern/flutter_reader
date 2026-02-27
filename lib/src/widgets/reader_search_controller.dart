import 'dart:async';

import 'package:flutter/foundation.dart';

import 'reader_controller.dart';

/// A single search match within the reader's item list.
class SearchMatch {
  /// The global item index in the reader.
  final int itemIndex;

  /// The item's unique ID.
  final String itemId;

  /// The extracted text that was searched.
  final String text;

  /// Character offset where the match starts in [text].
  final int matchStart;

  /// Character offset where the match ends in [text].
  final int matchEnd;

  const SearchMatch({
    required this.itemIndex,
    required this.itemId,
    required this.text,
    required this.matchStart,
    required this.matchEnd,
  });

  /// The matched substring.
  String get matchedText => text.substring(matchStart, matchEnd);
}

/// Controls text search across reader items with next/prev navigation.
///
/// Requires a [ReaderController] for item access and jump navigation,
/// and a map of [textExtractors] that define how to pull searchable
/// text from each item type's data payload.
///
/// Usage:
/// ```dart
/// final search = ReaderSearchController(
///   reader: myReaderController,
///   textExtractors: {
///     'verse': (data) => data['text'] as String,
///     'chapter': (data) => data as String,
///   },
/// );
///
/// search.search('faith');
/// print('${search.currentMatchDisplay}'); // "1 of 5"
/// search.nextMatch();    // jumps to match 2
/// search.previousMatch(); // back to match 1
/// search.clear();
/// ```
class ReaderSearchController extends ChangeNotifier {
  final ReaderController reader;

  /// Maps item `typeKey` to a function that extracts searchable text
  /// from the item's `data` payload. Items whose typeKey is not in
  /// this map are skipped during search.
  final Map<String, String Function(dynamic data)> textExtractors;

  /// How long to wait after the last keystroke before executing the search.
  /// Set to [Duration.zero] to disable debouncing.
  final Duration debounceDuration;

  String _query = '';
  List<SearchMatch> _matches = const [];
  int _currentIndex = -1;
  Timer? _debounceTimer;

  ReaderSearchController({
    required this.reader,
    required this.textExtractors,
    this.debounceDuration = const Duration(milliseconds: 300),
  });

  // ── Getters ────────────────────────────────────────────────────────

  /// The current search query, or empty string if inactive.
  String get query => _query;

  /// All matches for the current query, in item order.
  List<SearchMatch> get matches => _matches;

  /// Index into [matches] for the current highlighted match.
  int get currentMatchIndex => _currentIndex;

  /// The currently highlighted match, or null.
  SearchMatch? get currentMatch =>
      _currentIndex >= 0 && _currentIndex < _matches.length
          ? _matches[_currentIndex]
          : null;

  /// Total number of matches.
  int get matchCount => _matches.length;

  /// Whether there are any matches.
  bool get hasMatches => _matches.isNotEmpty;

  /// Whether a search is active (query is non-empty).
  bool get isActive => _query.isNotEmpty;

  /// Display string like "3 of 17", or empty if no matches.
  String get currentMatchDisplay => hasMatches
      ? '${_currentIndex + 1} of $matchCount'
      : isActive
          ? 'No results'
          : '';

  /// Whether the item at [index] is one of the current matches.
  bool isItemMatch(int index) {
    return _matchIndices.contains(index);
  }

  /// Whether the item at [index] is the *current* highlighted match.
  bool isCurrentMatch(int index) {
    final match = currentMatch;
    return match != null && match.itemIndex == index;
  }

  /// Returns all matches for the item at [index].
  List<SearchMatch> matchesForItem(int index) {
    if (!_matchIndices.contains(index)) return const [];
    return _matches.where((m) => m.itemIndex == index).toList();
  }

  // ── Actions ────────────────────────────────────────────────────────

  /// Run a case-insensitive search across all items.
  ///
  /// Populates [matches] and jumps to the first result.
  /// If the query is empty, clears the search.
  void search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _debounceTimer?.cancel();
      clear();
      return;
    }

    _query = trimmed;

    if (debounceDuration == Duration.zero) {
      _executeSearch(trimmed);
    } else {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounceDuration, () {
        _executeSearch(trimmed);
      });
    }
  }

  void _executeSearch(String query) {
    _matches = _findMatches(query);
    _matchIndices = {for (final m in _matches) m.itemIndex};

    if (_matches.isNotEmpty) {
      _currentIndex = 0;
      _jumpToCurrent();
    } else {
      _currentIndex = -1;
    }

    notifyListeners();
  }

  /// Clear the search state.
  void clear() {
    _debounceTimer?.cancel();
    _query = '';
    _matches = const [];
    _matchIndices = const {};
    _currentIndex = -1;
    notifyListeners();
  }

  /// Jump to the next match (wraps around to the first).
  void nextMatch() {
    if (_matches.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _matches.length;
    _jumpToCurrent();
    notifyListeners();
  }

  /// Jump to the previous match (wraps around to the last).
  void previousMatch() {
    if (_matches.isEmpty) return;
    _currentIndex =
        (_currentIndex - 1 + _matches.length) % _matches.length;
    _jumpToCurrent();
    notifyListeners();
  }

  /// Jump to a specific match by its index in [matches].
  void jumpToMatch(int matchIndex) {
    if (matchIndex < 0 || matchIndex >= _matches.length) return;
    _currentIndex = matchIndex;
    _jumpToCurrent();
    notifyListeners();
  }

  // ── Private ────────────────────────────────────────────────────────

  Set<int> _matchIndices = const {};

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _query = '';
    _matches = const [];
    _matchIndices = const {};
    _currentIndex = -1;
    super.dispose();
  }

  void _jumpToCurrent() {
    final match = currentMatch;
    if (match == null) return;
    reader.jumpToIndex(match.itemIndex, alignment: 0.3);
  }

  List<SearchMatch> _findMatches(String query) {
    final lowerQuery = query.toLowerCase();
    final results = <SearchMatch>[];
    final engine = reader.engine;

    for (var i = 0; i < engine.itemCount; i++) {
      final item = engine.itemAt(i);
      final extractor = textExtractors[item.typeKey];
      if (extractor == null) continue;

      String text;
      try {
        text = extractor(item.data);
      } catch (e) {
        assert(() {
          debugPrint(
            'ReaderSearchController: Text extractor for typeKey '
            '"${item.typeKey}" threw on item "${item.id}": $e',
          );
          return true;
        }());
        continue;
      }

      final lowerText = text.toLowerCase();
      var searchFrom = 0;

      while (true) {
        final pos = lowerText.indexOf(lowerQuery, searchFrom);
        if (pos == -1) break;

        results.add(SearchMatch(
          itemIndex: i,
          itemId: item.id,
          text: text,
          matchStart: pos,
          matchEnd: pos + query.length,
        ));

        searchFrom = pos + 1;
      }
    }

    return results;
  }
}
