import 'package:flutter/widgets.dart';
import 'package:reader_engine/reader_engine.dart';

/// Tracks a visual anchor item and its pixel offset from the viewport top.
///
/// When item heights change (due to measurement convergence or width changes),
/// [AnchorTracker] computes the scroll adjustment needed to keep the anchor
/// item visually pinned to the same position.
///
/// This is the Flutter-side counterpart to the engine's [ScrollCompensator].
/// While the engine tracks compensation at the data level, this class bridges
/// the gap by monitoring the actual [ScrollController].
///
/// Usage:
/// ```dart
/// final anchor = AnchorTracker(engine: myEngine);
///
/// // Call on every scroll
/// anchor.onScroll(scrollController.offset, viewportHeight);
///
/// // After a height change, get compensation
/// final delta = anchor.computeCompensation();
/// if (delta != 0) {
///   scrollController.jumpTo(scrollController.offset + delta);
/// }
/// ```
class AnchorTracker {
  final ReaderEngine engine;

  int _anchorIndex = 0;
  double _anchorVisualOffset = 0.0;

  AnchorTracker({required this.engine});

  /// The index of the current anchor item.
  int get anchorIndex => _anchorIndex;

  /// The anchor's visual offset from the top of the viewport (in pixels).
  double get anchorVisualOffset => _anchorVisualOffset;

  /// Updates the anchor based on the current scroll position.
  ///
  /// Call this on every scroll event. Picks the first visible item as
  /// the anchor and records its visual offset from the viewport top.
  void onScroll(double scrollOffset, double viewportHeight) {
    if (engine.itemCount == 0) return;

    final (first, _) = engine.registry.visibleRange(scrollOffset, viewportHeight);
    if (first < 0) return;

    _anchorIndex = first;
    final anchorAbsoluteOffset = engine.registry.offsetOfIndex(first);
    _anchorVisualOffset = anchorAbsoluteOffset - scrollOffset;
  }

  /// Computes the scroll compensation needed to restore the anchor's
  /// visual position after a layout change.
  ///
  /// Returns the pixel delta to add to the current scroll offset.
  /// A positive value means "scroll down" (content above grew).
  double computeCompensation(double currentScrollOffset) {
    if (engine.itemCount == 0) return 0.0;

    final anchorNow = engine.registry.offsetOfIndex(
      _anchorIndex.clamp(0, engine.itemCount - 1),
    );
    final expectedScroll = anchorNow - _anchorVisualOffset;
    return expectedScroll - currentScrollOffset;
  }

  /// Captures the current anchor state as a snapshot that can be
  /// restored later (e.g., across rebuilds).
  AnchorSnapshot snapshot() {
    return AnchorSnapshot(
      index: _anchorIndex,
      visualOffset: _anchorVisualOffset,
    );
  }

  /// Restores a previously captured anchor state.
  void restore(AnchorSnapshot snapshot) {
    _anchorIndex = snapshot.index;
    _anchorVisualOffset = snapshot.visualOffset;
  }

  /// Resets the anchor to the start.
  void reset() {
    _anchorIndex = 0;
    _anchorVisualOffset = 0.0;
  }
}

/// An immutable snapshot of anchor state.
class AnchorSnapshot {
  final int index;
  final double visualOffset;

  const AnchorSnapshot({required this.index, required this.visualOffset});
}
