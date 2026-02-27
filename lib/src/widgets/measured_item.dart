import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A widget that measures its child after layout and reports the height.
///
/// Used internally by [ReaderView] to get Tier 3 (ground truth) heights.
/// The measurement happens in a post-frame callback, so it doesn't
/// affect the build phase.
class MeasuredItem extends SingleChildRenderObjectWidget {
  /// Called after layout with the measured height.
  final ValueChanged<double> onMeasured;

  /// The global item index (for tracking which item was measured).
  final int itemIndex;

  const MeasuredItem({
    super.key,
    required super.child,
    required this.onMeasured,
    required this.itemIndex,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMeasuredItem(onMeasured: onMeasured, itemIndex: itemIndex);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasuredItem renderObject,
  ) {
    renderObject
      ..onMeasured = onMeasured
      ..itemIndex = itemIndex;
  }
}

class _RenderMeasuredItem extends RenderProxyBox {
  ValueChanged<double> onMeasured;
  int itemIndex;
  double? _lastReportedHeight;

  _RenderMeasuredItem({required this.onMeasured, required this.itemIndex});

  @override
  void performLayout() {
    super.performLayout();

    // Report height if it changed
    final newHeight = size.height;
    if (_lastReportedHeight == null || _lastReportedHeight != newHeight) {
      _lastReportedHeight = newHeight;

      // Schedule callback to avoid calling during layout
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onMeasured(newHeight);
      });
    }
  }
}
