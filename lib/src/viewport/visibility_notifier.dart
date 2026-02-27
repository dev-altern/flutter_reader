import 'package:flutter/foundation.dart';
import 'package:reader_engine/reader_engine.dart';

/// A [ChangeNotifier] that tracks which items are currently visible
/// in the reader viewport.
///
/// Attach to a [ReaderEngine] to receive visibility updates.
/// Useful for:
/// - "Current chapter" indicators
/// - Read position tracking / bookmarks
/// - Analytics (which items were seen)
/// - Lyrics sync / active verse highlighting
///
/// Usage:
/// ```dart
/// final notifier = VisibilityNotifier(engine: myEngine);
///
/// // Listen for changes
/// notifier.addListener(() {
///   print('Visible: ${notifier.firstVisible} to ${notifier.lastVisible}');
///   print('Anchor: ${notifier.anchorIndex}');
/// });
///
/// // In your scroll handler
/// notifier.update();
/// ```
class VisibilityNotifier extends ChangeNotifier {
  final ReaderEngine engine;

  int _firstVisible = -1;
  int _lastVisible = -1;
  int _anchorIndex = 0;

  VisibilityNotifier({required this.engine}) {
    engine.onVisibilityChanged = _onVisibilityChanged;
  }

  /// First visible item index, or -1 if nothing is visible.
  int get firstVisible => _firstVisible;

  /// Last visible item index, or -1 if nothing is visible.
  int get lastVisible => _lastVisible;

  /// The anchor item (first fully visible item).
  int get anchorIndex => _anchorIndex;

  /// Number of visible items.
  int get visibleCount =>
      _firstVisible >= 0 ? _lastVisible - _firstVisible + 1 : 0;

  /// Whether [index] is currently visible.
  bool isVisible(int index) => index >= _firstVisible && index <= _lastVisible;

  /// Manually trigger an update (e.g., after a jump).
  void update() {
    _onVisibilityChanged(engine.visibility);
  }

  void _onVisibilityChanged(VisibilityState state) {
    if (state.firstVisible != _firstVisible ||
        state.lastVisible != _lastVisible ||
        state.anchorIndex != _anchorIndex) {
      _firstVisible = state.firstVisible;
      _lastVisible = state.lastVisible;
      _anchorIndex = state.anchorIndex;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    engine.onVisibilityChanged = null;
    super.dispose();
  }
}
