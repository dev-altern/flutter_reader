import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:reader_engine/reader_engine.dart';

/// Pre-measures text content using [TextPainter] to produce Tier 2 height
/// estimates without rendering any widgets.
///
/// This is significantly more accurate than default type-based estimates
/// (Tier 1) because it accounts for actual text length, line wrapping,
/// and font metrics — but cheaper than full widget layout (Tier 3).
///
/// Reuses a single [TextPainter] across all measurements to avoid
/// per-call native resource allocation. Call [dispose] when done.
///
/// Usage:
/// ```dart
/// final premeasurer = TextPremeasurer();
///
/// // One-off measurement
/// final estimate = premeasurer.measureText(
///   text: 'Hello world...',
///   style: TextStyle(fontSize: 16),
///   maxWidth: 390,
///   padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
/// );
///
/// // Create an estimator function for ItemTypeConfig
/// final config = ItemTypeConfig(
///   typeName: 'verse',
///   defaultHeight: 56,
///   estimator: premeasurer.createEstimator(
///     textExtractor: (data) => data['text'] as String,
///     style: TextStyle(fontSize: 16),
///     padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
///   ),
/// );
///
/// // When done
/// premeasurer.dispose();
/// ```
class TextPremeasurer {
  final TextPainter _painter = TextPainter(
    textDirection: ui.TextDirection.ltr,
  );

  /// Measures the height of [text] laid out at [maxWidth] with the given [style].
  ///
  /// Optionally includes [padding] around the text. Returns a [HeightEstimate]
  /// with high confidence (0.85–0.95) since TextPainter is very accurate for
  /// single-style text blocks.
  HeightEstimate measureText({
    required String text,
    required TextStyle style,
    required double maxWidth,
    EdgeInsets padding = EdgeInsets.zero,
    int? maxLines,
    StrutStyle? strutStyle,
  }) {
    final availableWidth = maxWidth - padding.horizontal;
    if (availableWidth <= 0) {
      return (height: padding.vertical, confidence: 0.5);
    }

    _painter
      ..text = TextSpan(text: text, style: style)
      ..maxLines = maxLines
      ..strutStyle = strutStyle;
    _painter.layout(maxWidth: availableWidth);

    final height = _painter.height + padding.vertical;
    return (height: height, confidence: 0.9);
  }

  /// Measures the height of a [TextSpan] (rich text) laid out at [maxWidth].
  HeightEstimate measureTextSpan({
    required TextSpan textSpan,
    required double maxWidth,
    EdgeInsets padding = EdgeInsets.zero,
    int? maxLines,
    StrutStyle? strutStyle,
  }) {
    final availableWidth = maxWidth - padding.horizontal;
    if (availableWidth <= 0) {
      return (height: padding.vertical, confidence: 0.5);
    }

    _painter
      ..text = textSpan
      ..maxLines = maxLines
      ..strutStyle = strutStyle;
    _painter.layout(maxWidth: availableWidth);

    final height = _painter.height + padding.vertical;

    // Rich text may have inline spans with different sizes.
    return (height: height, confidence: 0.85);
  }

  /// Creates an estimator function suitable for [ItemTypeConfig.estimator].
  ///
  /// [textExtractor] pulls the text string from the item's data payload.
  /// [style] is the base text style used for rendering.
  /// [padding] accounts for container padding around the text.
  HeightEstimate Function(dynamic data, double availableWidth) createEstimator({
    required String Function(dynamic data) textExtractor,
    required TextStyle style,
    EdgeInsets padding = EdgeInsets.zero,
    int? maxLines,
    StrutStyle? strutStyle,
  }) {
    return (data, availableWidth) {
      final text = textExtractor(data);
      return measureText(
        text: text,
        style: style,
        maxWidth: availableWidth,
        padding: padding,
        maxLines: maxLines,
        strutStyle: strutStyle,
      );
    };
  }

  /// Creates an estimator for rich text items.
  ///
  /// [spanBuilder] constructs a [TextSpan] from the item's data payload.
  HeightEstimate Function(dynamic data, double availableWidth)
      createRichEstimator({
    required TextSpan Function(dynamic data) spanBuilder,
    EdgeInsets padding = EdgeInsets.zero,
    int? maxLines,
    StrutStyle? strutStyle,
  }) {
    return (data, availableWidth) {
      final span = spanBuilder(data);
      return measureTextSpan(
        textSpan: span,
        maxWidth: availableWidth,
        padding: padding,
        maxLines: maxLines,
        strutStyle: strutStyle,
      );
    };
  }

  /// Releases native resources held by the internal [TextPainter].
  /// Must be called when this premeasurer is no longer needed.
  void dispose() {
    _painter.dispose();
  }
}
