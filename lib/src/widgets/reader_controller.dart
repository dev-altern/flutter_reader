import 'package:flutter/widgets.dart';
import 'package:reader_engine/reader_engine.dart';

/// Controls a [ReaderView]. Provides jump, scroll, query, and lazy-loading
/// operations.
///
/// Usage:
/// ```dart
/// final controller = ReaderController(
///   items: myItems,
///   typeConfigs: myConfigs,
///   initialWidth: MediaQuery.of(context).size.width,
/// );
///
/// // Jump to an item
/// controller.jumpToId('verse_john_3_16');
///
/// // Get current visible items
/// final visible = controller.visibility;
/// ```
///
/// For lazy loading / infinite scroll:
/// ```dart
/// final controller = ReaderController(
///   items: initialPage,
///   typeConfigs: myConfigs,
///   initialWidth: 390,
///   hasMoreAfter: true,
///   edgeThreshold: 5,
/// );
///
/// controller.onEdgeReached = (direction) async {
///   final page = await api.fetchPage(direction, cursor);
///   if (direction == LoadDirection.after) {
///     controller.appendItems(page.items);
///     controller.hasMoreAfter = page.hasNext;
///   } else {
///     controller.prependItems(page.items);
///     controller.hasMoreBefore = page.hasPrevious;
///   }
/// };
/// ```
class ReaderController extends ChangeNotifier {
  late final ReaderEngine _engine;
  ScrollController? _scrollController;

  /// Whether the view is in reverse (chat) mode.
  bool _reverse = false;

  // ── Lazy-loading state ──────────────────────────────────────────────

  /// Whether there is more content available before the current items.
  bool hasMoreBefore;

  /// Whether there is more content available after the current items.
  bool hasMoreAfter;

  /// Called when scroll reaches within [edgeThreshold] items of an edge.
  ///
  /// Set this to trigger data fetching when the user scrolls near the
  /// beginning or end of loaded content.
  void Function(LoadDirection direction)? onEdgeReached;

  /// How many items from the edge before [onEdgeReached] fires.
  final int edgeThreshold;

  /// Extra scroll extent (pixels) added beyond [totalHeight] when
  /// [hasMoreAfter] is true. Prevents the scroll bar from hitting the
  /// absolute end before new content loads.
  final double loadMoreBufferExtent;

  bool _isLoadingBefore = false;
  bool _isLoadingAfter = false;

  ReaderController({
    required List<ReaderItem> items,
    required Map<String, ItemTypeConfig> typeConfigs,
    required double initialWidth,
    int bucketSize = 128,
    this.hasMoreBefore = false,
    this.hasMoreAfter = false,
    this.onEdgeReached,
    this.edgeThreshold = 3,
    this.loadMoreBufferExtent = 500.0,
  }) {
    final registry = ItemRegistry.build(
      items: items,
      typeConfigs: typeConfigs,
      initialWidth: initialWidth,
      bucketSize: bucketSize,
    );
    _engine = ReaderEngine(registry: registry);
  }

  /// The underlying engine (for advanced use).
  ReaderEngine get engine => _engine;

  /// Whether the controller is in reverse (chat) mode.
  bool get isReverse => _reverse;

  /// Total scroll extent including any lazy-load buffer.
  ///
  /// When [hasMoreAfter] is true, adds [loadMoreBufferExtent] to
  /// [totalHeight] so the user can scroll into the load zone.
  double get effectiveTotalHeight =>
      hasMoreAfter ? _engine.totalHeight + loadMoreBufferExtent : _engine.totalHeight;

  // ── Attach / Detach ─────────────────────────────────────────────────

  /// Attach to a ScrollController. Called internally by [ReaderView].
  ///
  /// When [reverse] is true, scroll compensation from height measurements
  /// is suppressed (the reversed CustomScrollView handles bottom-pinning
  /// naturally).
  void attach(ScrollController scrollController, {bool reverse = false}) {
    _scrollController = scrollController;
    _reverse = reverse;
    _scrollController!.addListener(_onScroll);
    // The first frame establishes layout and viewport dimensions.
    // Schedule the initial edge check for the frame after that, when
    // visibility state is valid.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController != null && _scrollController!.hasClients) {
          _engine.reportScrollOffset(_scrollController!.offset);
          _checkEdgeProximity();
        }
      });
    });
  }

  /// Detach from the ScrollController.
  void detach() {
    _scrollController?.removeListener(_onScroll);
    _scrollController = null;
  }

  // ── Navigation ──────────────────────────────────────────────────────

  /// Jump to item by ID.
  ///
  /// [alignment] controls where in the viewport the item lands:
  /// 0.0 = top edge (default), 0.5 = centered, 1.0 = bottom edge.
  void jumpToId(String id, {double alignment = 0.0}) {
    final result = _engine.jumpToId(id);
    if (result != null && _scrollController != null) {
      if (_reverse) {
        _scrollController!.jumpTo(0);
      } else {
        _scrollController!.jumpTo(_alignedOffset(result.pixelOffset, alignment));
      }
    }
  }

  /// Jump to item by index.
  ///
  /// [alignment] controls where in the viewport the item lands:
  /// 0.0 = top edge (default), 0.5 = centered, 1.0 = bottom edge.
  void jumpToIndex(int index, {double alignment = 0.0}) {
    if (_reverse) {
      // In reverse mode, index 0 is at the bottom (newest).
      // To show the last appended item, jump to offset 0.
      if (index >= _engine.itemCount - 1) {
        _scrollController?.jumpTo(0);
      } else {
        final result = _engine.jumpToIndex(index);
        if (_scrollController != null) {
          _scrollController!.jumpTo(
            _alignedOffset(result.pixelOffset, alignment),
          );
        }
      }
    } else {
      final result = _engine.jumpToIndex(index);
      if (_scrollController != null) {
        _scrollController!.jumpTo(_alignedOffset(result.pixelOffset, alignment));
      }
    }
  }

  /// Animate to item by ID.
  ///
  /// [alignment] controls where in the viewport the item lands:
  /// 0.0 = top edge (default), 0.5 = centered, 1.0 = bottom edge.
  Future<void> animateToId(
    String id, {
    double alignment = 0.0,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final result = _engine.jumpToId(id);
    if (result != null && _scrollController != null) {
      if (_reverse) {
        await _scrollController!.animateTo(
          0,
          duration: duration,
          curve: curve,
        );
      } else {
        await _scrollController!.animateTo(
          _alignedOffset(result.pixelOffset, alignment),
          duration: duration,
          curve: curve,
        );
      }
    }
  }

  /// Scroll to the end of the list.
  ///
  /// In normal mode, scrolls to the last item.
  /// In reverse mode, scrolls to offset 0 (the bottom/newest).
  void scrollToEnd() {
    if (_scrollController == null) return;
    if (_reverse) {
      _scrollController!.jumpTo(0);
    } else if (_engine.itemCount > 0) {
      jumpToIndex(_engine.itemCount - 1, alignment: 1.0);
    }
  }

  /// Whether the scroll position is currently at the end.
  ///
  /// In reverse mode, "at end" means offset ~0 (bottom).
  /// In normal mode, "at end" means offset ~maxScrollExtent.
  bool get isAtEnd {
    if (_scrollController == null || !_scrollController!.hasClients) {
      return true;
    }
    if (_reverse) {
      return _scrollController!.offset < 1.0;
    } else {
      final pos = _scrollController!.position;
      return pos.maxScrollExtent - pos.pixels < 1.0;
    }
  }

  double _alignedOffset(double itemOffset, double alignment) {
    if (alignment <= 0.0 || _scrollController == null) return itemOffset;
    final viewportHeight = _scrollController!.position.viewportDimension;
    final maxExtent = _scrollController!.position.maxScrollExtent;
    final adjusted = itemOffset - viewportHeight * alignment;
    return adjusted.clamp(0.0, maxExtent);
  }

  // ── Queries ─────────────────────────────────────────────────────────

  /// Current visibility state.
  VisibilityState get visibility => _engine.visibility;

  /// Total content height.
  double get totalHeight => _engine.totalHeight;

  /// Total item count.
  int get itemCount => _engine.itemCount;

  // ── Measurement ─────────────────────────────────────────────────────

  /// Report a measured height (called by [MeasuredItem]).
  ///
  /// In reverse mode, scroll compensation is suppressed — the reversed
  /// [CustomScrollView] handles bottom-pinning automatically via its
  /// growth direction.
  void reportMeasuredHeight(int index, double height) {
    final result = _engine.reportMeasuredHeight(index, height);
    if (!_reverse && result.scrollCompensation != 0.0 && _scrollController != null) {
      final newOffset = _scrollController!.offset + result.scrollCompensation;
      _scrollController!.jumpTo(newOffset);
    }
  }

  /// Handle viewport width change.
  void onWidthChanged(double newWidth) {
    _engine.setViewportHeight(
      _scrollController?.position.viewportDimension ?? 0,
    );
    final compensation = _engine.onWidthChanged(newWidth);
    if (!_reverse && compensation != 0.0 && _scrollController != null) {
      _scrollController!.jumpTo(_scrollController!.offset + compensation);
    }
  }

  // ── Batch Mutations (Lazy Loading) ──────────────────────────────────

  /// Appends [items] after the last item.
  ///
  /// Resets the "after" loading guard so that [onEdgeReached] can fire
  /// again when the user scrolls to the new end.
  void appendItems(List<ReaderItem> items, {List<double?>? estimatedHeights}) {
    _isLoadingAfter = false;
    if (items.isEmpty) {
      notifyListeners();
      return;
    }
    final compensation = _engine.insertItems(
      _engine.itemCount,
      items,
      estimatedHeights: estimatedHeights,
    );
    if (!_reverse) {
      _applyCompensation(compensation);
    }
    notifyListeners();
  }

  /// Prepends [items] before the first item.
  ///
  /// Scroll compensation is applied automatically so the user's current
  /// view position is preserved. Resets the "before" loading guard.
  void prependItems(List<ReaderItem> items, {List<double?>? estimatedHeights}) {
    _isLoadingBefore = false;
    if (items.isEmpty) {
      notifyListeners();
      return;
    }
    final compensation = _engine.insertItems(
      0,
      items,
      estimatedHeights: estimatedHeights,
    );
    _applyCompensation(compensation);
    notifyListeners();
  }

  /// Inserts [items] at an arbitrary [index].
  ///
  /// Resets both loading guards.
  void insertItems(
    int index,
    List<ReaderItem> items, {
    List<double?>? estimatedHeights,
  }) {
    _isLoadingBefore = false;
    _isLoadingAfter = false;
    if (items.isEmpty) {
      notifyListeners();
      return;
    }
    final compensation = _engine.insertItems(
      index,
      items,
      estimatedHeights: estimatedHeights,
    );
    if (!_reverse) {
      _applyCompensation(compensation);
    }
    notifyListeners();
  }

  /// Removes [count] items starting at [startIndex].
  void removeItems(int startIndex, int count) {
    if (count <= 0) return;
    final compensation = _engine.removeItems(startIndex, count);
    if (!_reverse) {
      _applyCompensation(compensation);
    }
    notifyListeners();
  }

  /// Evicts items far from the current viewport to cap memory usage.
  ///
  /// Keeps up to [maxLoadedItems] centered around the visible range.
  /// Evicted regions automatically set [hasMoreBefore] / [hasMoreAfter]
  /// so [onEdgeReached] will fire when the user scrolls back.
  ///
  /// Call this from your [onEdgeReached] handler after appending/prepending
  /// new pages, e.g.:
  /// ```dart
  /// controller.onEdgeReached = (dir) async {
  ///   final page = await api.fetchPage(dir, cursor);
  ///   if (dir == LoadDirection.after) {
  ///     controller.appendItems(page.items);
  ///   } else {
  ///     controller.prependItems(page.items);
  ///   }
  ///   controller.evictDistantItems();
  /// };
  /// ```
  void evictDistantItems({int maxLoadedItems = 5000}) {
    final count = _engine.itemCount;
    if (count <= maxLoadedItems) return;

    final vis = _engine.visibility;
    final center = vis.firstVisible >= 0
        ? (vis.firstVisible + vis.lastVisible) ~/ 2
        : 0;
    final half = maxLoadedItems ~/ 2;

    final keepStart = (center - half).clamp(0, count);
    final keepEnd = (center + half).clamp(0, count);

    // Evict tail first (higher indices, so keepStart stays valid).
    if (keepEnd < count) {
      final tailCount = count - keepEnd;
      final compensation = _engine.removeItems(keepEnd, tailCount);
      if (!_reverse) _applyCompensation(compensation);
      hasMoreAfter = true;
    }

    // Evict head.
    if (keepStart > 0) {
      final compensation = _engine.removeItems(0, keepStart);
      _applyCompensation(compensation);
      hasMoreBefore = true;
    }

    notifyListeners();
  }

  void _applyCompensation(double compensation) {
    if (compensation != 0.0 && _scrollController != null) {
      _scrollController!.jumpTo(_scrollController!.offset + compensation);
    }
  }

  // ── Scroll Listener ─────────────────────────────────────────────────

  void _onScroll() {
    if (_scrollController == null) return;
    _engine.reportScrollOffset(_scrollController!.offset);
    _checkEdgeProximity();
    notifyListeners();
  }

  void _checkEdgeProximity() {
    if (onEdgeReached == null) return;

    final vis = _engine.visibility;
    if (vis.firstVisible < 0) return;

    if (hasMoreBefore && !_isLoadingBefore) {
      if (vis.firstVisible <= edgeThreshold) {
        _isLoadingBefore = true;
        onEdgeReached!(LoadDirection.before);
      }
    }

    if (hasMoreAfter && !_isLoadingAfter) {
      final distanceFromEnd = _engine.itemCount - 1 - vis.lastVisible;
      if (distanceFromEnd <= edgeThreshold) {
        _isLoadingAfter = true;
        onEdgeReached!(LoadDirection.after);
      }
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}
