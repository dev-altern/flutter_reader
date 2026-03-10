import 'package:flutter/widgets.dart';
import 'package:reader_engine/reader_engine.dart';

import '../viewport/anchor_viewport.dart';
import 'measured_item.dart';
import 'reader_controller.dart';

/// Builder function for rendering items.
typedef ReaderItemBuilder =
    Widget Function(BuildContext context, int index, ReaderItem item);

/// A high-performance scrollable list with O(log N) jump-to-item.
///
/// Drop-in replacement for [ListView.builder] with:
/// - Instant jump to any item by ID or index
/// - Automatic height measurement and convergence
/// - Zero-jank scroll compensation on height corrections
/// - Efficient width-change handling
/// - Accurate scroll extent from frame 1 (engine-backed)
/// - **Reverse mode** for chat-style bottom-pinned scrolling
///
/// Usage:
/// ```dart
/// // Standard (reader/document mode)
/// ReaderView(
///   controller: myReaderController,
///   itemBuilder: (context, index, item) {
///     return switch (item.typeKey) {
///       'verse' => VerseWidget(item.data),
///       'header' => HeaderWidget(item.data),
///       _ => Text('Unknown: ${item.id}'),
///     };
///   },
/// )
///
/// // Chat mode (reversed, pinned to bottom)
/// ReaderView(
///   controller: myReaderController,
///   reverse: true,
///   itemBuilder: (context, index, item) => MessageBubble(item.data),
/// )
/// ```
class ReaderView extends StatefulWidget {
  /// The controller managing items, heights, and navigation.
  final ReaderController controller;

  /// Builds the widget for each item.
  final ReaderItemBuilder itemBuilder;

  /// Pixel extent to pre-build beyond the visible viewport (each direction).
  /// Higher values reduce pop-in but use more memory.
  /// Defaults to 500.0 (~8-10 items at typical heights).
  final double cacheExtent;

  /// Optional padding around the list.
  final EdgeInsetsGeometry? padding;

  /// Optional scroll physics.
  final ScrollPhysics? physics;

  /// Optional listenable that triggers per-item rebuilds without
  /// recreating the entire ListView. Useful for search highlighting
  /// or other item-level state that changes independently of scroll.
  final Listenable? itemUpdateListenable;

  /// Whether the list scrolls in reverse (newest items at bottom).
  ///
  /// When true:
  /// - The scroll view is reversed (items grow from bottom to top)
  /// - New items appended via [ReaderController.appendItems] appear at the
  ///   bottom and the list stays pinned there
  /// - Scroll compensation from height corrections is suppressed when
  ///   the user is at the bottom edge
  /// - Keyboard open/close naturally keeps the bottom position
  ///
  /// This is the standard pattern for chat UIs.
  final bool reverse;

  const ReaderView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.cacheExtent = 500.0,
    this.padding,
    this.physics,
    this.itemUpdateListenable,
    this.reverse = false,
  });

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  late ScrollController _scrollController;
  late AnchorTracker _anchorTracker;
  double _lastViewportHeight = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    if (!widget.reverse) {
      _scrollController.addListener(_onScrollForAnchor);
    }
    _anchorTracker = AnchorTracker(engine: widget.controller.engine);
    widget.controller.attach(_scrollController, reverse: widget.reverse);
  }

  @override
  void didUpdateWidget(ReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (widget.reverse) {
        // In reverse mode, no anchor tracking needed — just swap.
        oldWidget.controller.detach();
        widget.controller.attach(_scrollController, reverse: widget.reverse);
      } else {
        // Snapshot the anchor position before swapping controllers.
        final snap = _anchorTracker.snapshot();

        oldWidget.controller.detach();
        _anchorTracker = AnchorTracker(engine: widget.controller.engine);
        widget.controller.attach(_scrollController, reverse: widget.reverse);

        // Restore anchor so the user sees the same visual position.
        _anchorTracker.restore(snap);
        final compensation =
            _anchorTracker.computeCompensation(_scrollController.offset);
        if (compensation.abs() > 0.5) {
          _scrollController.jumpTo(_scrollController.offset + compensation);
        }
      }
    }
  }

  void _onScrollForAnchor() {
    if (_scrollController.hasClients) {
      _anchorTracker.onScroll(
        _scrollController.offset,
        _scrollController.position.viewportDimension,
      );
    }
  }

  @override
  void dispose() {
    if (!widget.reverse) {
      _scrollController.removeListener(_onScrollForAnchor);
    }
    widget.controller.detach();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sliverList = SliverList(
      delegate: _ReaderChildDelegate(
        controller: widget.controller,
        reverse: widget.reverse,
        builder: (context, rawIndex) {
          // In reverse mode, flip the index so item 0 (oldest) renders
          // at the bottom of the reversed CustomScrollView.
          final index = widget.reverse
              ? widget.controller.itemCount - 1 - rawIndex
              : rawIndex;

          if (index < 0 || index >= widget.controller.itemCount) {
            return const SizedBox.shrink();
          }

          final item = widget.controller.engine.itemAt(index);

          // Build the item, optionally wrapped in a per-item
          // ListenableBuilder for targeted rebuilds (e.g. search).
          Widget buildChild() =>
              widget.itemBuilder(context, index, item);

          final child = widget.itemUpdateListenable != null
              ? ListenableBuilder(
                  listenable: widget.itemUpdateListenable!,
                  builder: (context, _) => buildChild(),
                )
              : buildChild();

          return MeasuredItem(
            itemIndex: index,
            onMeasured: (h) {
              widget.controller.reportMeasuredHeight(index, h);
            },
            child: RepaintBoundary(child: child),
          );
        },
        childCount: widget.controller.itemCount,
      ),
    );

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        final height = notification.metrics.viewportDimension;
        if (height != _lastViewportHeight) {
          _lastViewportHeight = height;
          widget.controller.engine.setViewportHeight(height);
        }
        return false;
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: widget.physics,
        cacheExtent: widget.cacheExtent,
        reverse: widget.reverse,
        slivers: [
          if (widget.padding != null)
            SliverPadding(padding: widget.padding!, sliver: sliverList)
          else
            sliverList,
        ],
      ),
    );
  }
}

/// Custom [SliverChildBuilderDelegate] that overrides scroll extent
/// estimation to use the engine's pre-computed total height.
///
/// Without this, Flutter estimates scroll extent from the average height
/// of laid-out items, which causes scroll thumb jumps and inaccurate
/// large-distance jumps.
class _ReaderChildDelegate extends SliverChildBuilderDelegate {
  final ReaderController controller;
  final bool reverse;

  _ReaderChildDelegate({
    required this.controller,
    required NullableIndexedWidgetBuilder builder,
    int? childCount,
    this.reverse = false,
  }) : super(builder, childCount: childCount);

  @override
  double? estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) {
    return controller.effectiveTotalHeight;
  }
}
