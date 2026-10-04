# Changelog

## Unreleased

* ReaderController: in reverse (chat) mode, `jumpToId`, `jumpToIndex` and `animateToId` now reach the requested item at the requested alignment. `jumpToId` and `animateToId` used to scroll to the newest item, and `jumpToIndex` used forward-mode offsets.
* ReaderController: reverse-mode jumps re-aim once the items they scrolled past report their real heights, and stop if a newer jump starts or the user moves the list.

## 1.0.0

* Initial release.
* ReaderView: CustomScrollView-based scrollable widget with engine-backed scroll extent.
* ReaderController: ChangeNotifier coordinator with navigation, mutations, lazy-loading, and visibility.
* MeasuredItem: Automatic Tier 3 height reporting via post-frame callbacks.
* TextPremeasurer: TextPainter-based Tier 2 height estimation.
* MeasurementScheduler: Background pre-measurement during idle frames.
* ReaderSearchController: Full-text search with debounced queries and match navigation.
* ReaderSearchBar: Material Design search bar with match counter and navigation.
* SearchHighlightText: Text rendering with highlighted search matches.
* VisibilityNotifier: ChangeNotifier for tracking visible items.
* Lazy-loading with edge detection, loading guards, and windowed eviction.
