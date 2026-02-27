import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:reader_engine/reader_engine.dart';

import 'text_premeasurer.dart';

/// Configuration for how to pre-measure a given item type.
///
/// Maps an item's [typeKey] to the [TextStyle] and [padding] used to
/// render it, plus a [textExtractor] to pull the string from the data payload.
class PremeasureConfig {
  final String Function(dynamic data) textExtractor;
  final TextStyle style;
  final EdgeInsets padding;

  const PremeasureConfig({
    required this.textExtractor,
    required this.style,
    this.padding = EdgeInsets.zero,
  });
}

/// Schedules background pre-measurement of low-confidence items during
/// idle frames, avoiding UI jank.
///
/// Picks the lowest-confidence items from the engine, pre-measures them
/// with [TextPremeasurer], and feeds the results back. Runs automatically
/// after each frame when there's remaining idle time.
///
/// Usage:
/// ```dart
/// final scheduler = MeasurementScheduler(
///   engine: controller.engine,
///   premeasurer: TextPremeasurer(),
///   configs: {
///     'verse': PremeasureConfig(
///       textExtractor: (data) => data['text'],
///       style: TextStyle(fontSize: 16),
///       padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
///     ),
///   },
/// );
///
/// scheduler.start();
/// // ...later...
/// scheduler.stop();
/// ```
class MeasurementScheduler {
  final ReaderEngine engine;
  final TextPremeasurer premeasurer;
  final Map<String, PremeasureConfig> configs;

  /// Max items to measure per idle callback.
  final int batchSize;

  /// Only measure items below this confidence threshold.
  final double confidenceThreshold;

  /// Called when all items have been measured above the confidence threshold
  /// (i.e. no more candidates remain). Only fires once per [start] cycle.
  final VoidCallback? onComplete;

  bool _running = false;
  bool _scheduled = false;

  MeasurementScheduler({
    required this.engine,
    required this.premeasurer,
    required this.configs,
    this.batchSize = 10,
    this.confidenceThreshold = 0.5,
    this.onComplete,
  });

  /// Whether the scheduler is currently running.
  bool get isRunning => _running;

  /// Start scheduling background measurements.
  void start() {
    if (_running) return;
    _running = true;
    _scheduleNext();
  }

  /// Stop scheduling. Any in-progress batch will complete, but no
  /// further batches will be scheduled.
  void stop() {
    _running = false;
  }

  /// Stop scheduling and release resources held by the premeasurer.
  void dispose() {
    stop();
    premeasurer.dispose();
  }

  /// Run a single batch synchronously (useful for testing).
  int measureBatch() {
    return _processBatch();
  }

  void _scheduleNext() {
    if (!_running || _scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_running) return;

      final measured = _processBatch();

      // If we measured items, schedule another pass.
      if (measured > 0) {
        _scheduleNext();
      } else {
        _running = false;
        onComplete?.call();
      }
    });
  }

  int _processBatch() {
    final candidates = engine.nextItemsToMeasure(
      count: batchSize,
      threshold: confidenceThreshold,
    );

    if (candidates.isEmpty) return 0;

    final measurements = <int, double>{};
    final width = engine.registry.currentWidth;

    for (final index in candidates) {
      final item = engine.itemAt(index);
      final config = configs[item.typeKey];
      if (config == null) continue;

      try {
        final text = config.textExtractor(item.data);
        final estimate = premeasurer.measureText(
          text: text,
          style: config.style,
          maxWidth: width,
          padding: config.padding,
        );
        measurements[index] = estimate.height;
      } catch (_) {
        // Skip items whose data can't be extracted.
      }
    }

    if (measurements.isNotEmpty) {
      engine.reportMeasuredHeights(measurements);
    }

    return measurements.length;
  }
}
