import 'package:flutter/material.dart';

import 'reader_search_controller.dart';

/// Renders [text] with search match highlighting.
///
/// All [matches] are highlighted with [highlightColor], and the
/// [currentMatch] (if present) uses [currentHighlightColor] instead.
///
/// Usage:
/// ```dart
/// SearchHighlightText(
///   text: verseText,
///   matches: searchController.matchesForItem(index),
///   currentMatch: searchController.currentMatch,
///   style: Theme.of(context).textTheme.bodyLarge,
/// )
/// ```
class SearchHighlightText extends StatelessWidget {
  /// The full text to display.
  final String text;

  /// Matches to highlight within [text].
  final List<SearchMatch> matches;

  /// The currently focused match (highlighted differently).
  final SearchMatch? currentMatch;

  /// Base text style.
  final TextStyle? style;

  /// Background color for all matches.
  final Color? highlightColor;

  /// Background color for the current/focused match.
  final Color? currentHighlightColor;

  /// Max lines for the text.
  final int? maxLines;

  /// Overflow behavior.
  final TextOverflow? overflow;

  const SearchHighlightText({
    super.key,
    required this.text,
    this.matches = const [],
    this.currentMatch,
    this.style,
    this.highlightColor,
    this.currentHighlightColor,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final defaultHighlight =
        highlightColor ?? Colors.yellow.withValues(alpha: 0.4);
    final currentHighlight =
        currentHighlightColor ?? Colors.orange.withValues(alpha: 0.6);

    return Text.rich(
      buildHighlightedSpan(
        text: text,
        matches: matches,
        currentMatch: currentMatch,
        style: style,
        highlightColor: defaultHighlight,
        currentHighlightColor: currentHighlight,
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  /// Builds a [TextSpan] tree with highlighted match regions.
  ///
  /// Can be used standalone when you need to embed highlighted text
  /// inside a larger [RichText] or [Text.rich] widget.
  static TextSpan buildHighlightedSpan({
    required String text,
    required List<SearchMatch> matches,
    SearchMatch? currentMatch,
    TextStyle? style,
    Color highlightColor = const Color(0x66FFEB3B),
    Color currentHighlightColor = const Color(0x99FF9800),
  }) {
    if (matches.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    // Sort matches by start position.
    final sorted = [...matches]..sort((a, b) => a.matchStart - b.matchStart);

    final spans = <TextSpan>[];
    var cursor = 0;

    for (final match in sorted) {
      // Add text before this match.
      if (match.matchStart > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.matchStart)));
      }

      // Determine highlight color.
      final isCurrent = currentMatch != null &&
          match.itemIndex == currentMatch.itemIndex &&
          match.matchStart == currentMatch.matchStart &&
          match.matchEnd == currentMatch.matchEnd;

      spans.add(TextSpan(
        text: text.substring(match.matchStart, match.matchEnd),
        style: TextStyle(
          backgroundColor: isCurrent ? currentHighlightColor : highlightColor,
        ),
      ));

      cursor = match.matchEnd;
    }

    // Add remaining text after the last match.
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return TextSpan(style: style, children: spans);
  }
}
