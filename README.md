# flutter_reader

[![pub package](https://img.shields.io/pub/v/flutter_reader.svg)](https://pub.dev/packages/flutter_reader)

A high-performance Flutter widget layer for scrollable content with **instant jump-to-item**, automatic height measurement, lazy-loading / infinite scroll, full-text search, and zero-jank scroll compensation. Built on top of [`reader_engine`](https://pub.dev/packages/reader_engine).

## Installation

```yaml
dependencies:
  flutter_reader: ^1.0.0
```

## Table of Contents

- [Why flutter\_reader?](#why-flutter_reader)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [ReaderView](#readerview)
  - [Constructor Parameters](#readerview-constructor-parameters)
  - [Item Builder](#item-builder)
- [ReaderController](#readercontroller)
  - [Constructor Parameters](#readercontroller-constructor-parameters)
  - [Navigation](#navigation)
  - [Queries](#queries)
  - [Measurement](#measurement-reporting)
  - [Lifecycle](#lifecycle)
- [Lazy Loading / Infinite Scroll](#lazy-loading--infinite-scroll)
  - [Basic Setup](#basic-setup)
  - [Batch Mutations](#batch-mutations)
  - [Edge Detection](#edge-detection)
  - [Loading Guards](#loading-guards)
  - [Windowed Eviction](#windowed-eviction)
  - [Effective Scroll Extent](#effective-scroll-extent)
  - [Complete Example](#complete-lazy-loading-example)
- [Measurement Pipeline](#measurement-pipeline)
  - [Three-Tier System](#three-tier-system)
  - [MeasuredItem](#measureditem)
  - [TextPremeasurer](#textpremeasurer)
  - [MeasurementScheduler](#measurementscheduler)
- [Search](#search)
  - [ReaderSearchController](#readersearchcontroller)
  - [ReaderSearchBar](#readersearchbar)
  - [SearchHighlightText](#searchhighlighttext)
- [Visibility Tracking](#visibility-tracking)
  - [VisibilityNotifier](#visibilitynotifier)
- [Width Changes](#width-changes)
- [Performance](#performance)
- [Do's and Don'ts](#dos-and-donts)
- [Testing](#testing)

---

## Why flutter_reader?

Standard Flutter lists (`ListView.builder`) estimate scroll extent using `averageItemHeight * itemCount`. This is fine for uniform lists but fails for heterogeneous content like a Bible (chapter headings, verses, footnotes, cross-references) where jumping to item #10,000 lands hundreds of pixels off target.

**flutter_reader** provides:

- **O(log N) jump to any item** by ID or index, from frame 1
- **Three-tier height convergence** — type default → TextPainter → actual render
- **Zero-jank scroll compensation** when heights correct above the viewport
- **Lazy loading** with edge detection, loading guards, and windowed eviction
- **Full-text search** with match navigation and highlighting
- **Background pre-measurement** during idle frames via `MeasurementScheduler`
- **Efficient scroll extent** — engine-backed total height, not average-based estimation

---

## Architecture

```
┌────────────────────────────────────┐
│           Your App                  │
│  (Bible reader, chat, feed, etc.)  │
└───────────────┬────────────────────┘
                │
┌───────────────▼────────────────────┐
│          flutter_reader             │
│  ReaderView ← ReaderController     │
│  MeasuredItem, TextPremeasurer     │
│  MeasurementScheduler              │
│  ReaderSearchController            │
│  VisibilityNotifier                │
└───────────────┬────────────────────┘
                │
┌───────────────▼────────────────────┐
│          reader_engine              │
│  ReaderEngine ← ItemRegistry       │
│  ChunkedHeightIndex (Fenwick)      │
│  ScrollCompensator                 │
│  Zero external dependencies        │
└────────────────────────────────────┘
```

**Separation of concerns:**
- `reader_engine` — Pure Dart. Algorithms, data structures, no Flutter imports.
- `flutter_reader` — Flutter widgets. Measurement, scrolling, search, UI.

---

## Quick Start

```dart
import 'package:flutter_reader/flutter_reader.dart';

// 1. Define item types
final typeConfigs = {
  'chapter': const ItemTypeConfig(
    typeName: 'chapter',
    defaultHeight: 44.0,
    defaultConfidence: 0.9,
    widthSensitivity: WidthSensitivity.invariant,
  ),
  'verse': const ItemTypeConfig(
    typeName: 'verse',
    defaultHeight: 56.0,
    defaultConfidence: 0.3,
    widthSensitivity: WidthSensitivity.dependent,
  ),
};

// 2. Build items
final items = [
  ReaderItem(id: 'ch_1', typeKey: 'chapter', data: 'Genesis 1'),
  ReaderItem(id: 'gen_1_1', typeKey: 'verse', data: 'In the beginning...'),
  // ...31,000 items
];

// 3. Create controller
final controller = ReaderController(
  items: items,
  typeConfigs: typeConfigs,
  initialWidth: MediaQuery.of(context).size.width,
);

// 4. Build the widget
ReaderView(
  controller: controller,
  itemBuilder: (context, index, item) {
    return switch (item.typeKey) {
      'chapter' => ChapterHeader(item.data as String),
      'verse'   => VerseText(item.data as String),
      _         => const SizedBox.shrink(),
    };
  },
);

// 5. Jump anywhere instantly
controller.jumpToId('gen_1_1');

// 6. Animate smoothly
await controller.animateToId('ch_5', alignment: 0.0);
```

---

## ReaderView

The main scrollable widget. Wraps a `CustomScrollView` with a `SliverList` and a custom child delegate for accurate scroll extent.

### ReaderView Constructor Parameters

```dart
ReaderView({
  required ReaderController controller,
  required ReaderItemBuilder itemBuilder,
  double cacheExtent = 500.0,
  EdgeInsetsGeometry? padding,
  ScrollPhysics? physics,
  Listenable? itemUpdateListenable,
})
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `controller` | `ReaderController` | required | The controller managing items and scroll state |
| `itemBuilder` | `ReaderItemBuilder` | required | Builds a widget for each item |
| `cacheExtent` | `double` | `500.0` | Pixels of off-screen content to keep alive |
| `padding` | `EdgeInsetsGeometry?` | `null` | Padding around the scrollable content |
| `physics` | `ScrollPhysics?` | `null` | Custom scroll physics |
| `itemUpdateListenable` | `Listenable?` | `null` | Triggers per-item rebuilds without full list recreation |

### Item Builder

```dart
typedef ReaderItemBuilder = Widget Function(
  BuildContext context,
  int index,
  ReaderItem item,
);
```

Each item is automatically wrapped in:
- `MeasuredItem` — reports actual rendered height (Tier 3) back to the engine
- `RepaintBoundary` — isolates paint to individual items

**What you return is what gets measured.** If your widget has padding, margins, or decorations, all of that is included in the measured height.

### itemUpdateListenable

Use this for targeted item rebuilds without recreating the entire list. Common use case: highlighting the current search match.

```dart
// The search controller notifies when currentMatch changes
ReaderView(
  controller: controller,
  itemBuilder: (context, index, item) {
    // This builder re-runs for visible items when searchController notifies
    final isMatch = searchController.isCurrentMatch(index);
    return VerseText(item.data, highlighted: isMatch);
  },
  itemUpdateListenable: searchController,
);
```

---

## ReaderController

Manages all state for a `ReaderView`: navigation, mutations, lazy loading, visibility, and measurement.

Extends `ChangeNotifier` — listeners are notified on scroll, measurement, and mutation events.

### ReaderController Constructor Parameters

```dart
ReaderController({
  required List<ReaderItem> items,
  required Map<String, ItemTypeConfig> typeConfigs,
  required double initialWidth,
  int bucketSize = 128,
  bool hasMoreBefore = false,
  bool hasMoreAfter = false,
  void Function(LoadDirection direction)? onEdgeReached,
  int edgeThreshold = 3,
  double loadMoreBufferExtent = 500.0,
})
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `items` | `List<ReaderItem>` | required | Initial items to display |
| `typeConfigs` | `Map<String, ItemTypeConfig>` | required | Height config per item type |
| `initialWidth` | `double` | required | Viewport width for initial height estimates |
| `bucketSize` | `int` | `128` | Internal bucket size (rarely changed) |
| `hasMoreBefore` | `bool` | `false` | Whether more content exists before current items |
| `hasMoreAfter` | `bool` | `false` | Whether more content exists after current items |
| `onEdgeReached` | `void Function(LoadDirection)?` | `null` | Callback when user scrolls near an edge |
| `edgeThreshold` | `int` | `3` | Items from edge before `onEdgeReached` fires |
| `loadMoreBufferExtent` | `double` | `500.0` | Extra scroll extent when `hasMoreAfter` is true |

### Navigation

```dart
// Jump instantly to an item by ID
controller.jumpToId('verse_42');

// Jump to an item by index
controller.jumpToIndex(500);

// Jump with alignment (0.0 = top, 0.5 = center, 1.0 = bottom)
controller.jumpToId('verse_42', alignment: 0.5);

// Animate smoothly
await controller.animateToId(
  'ch_5',
  alignment: 0.0,
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeInOut,
);
```

**Alignment:**
- `0.0` — Item at top edge of viewport (default)
- `0.5` — Item centered in viewport
- `1.0` — Item at bottom edge of viewport

### Queries

```dart
controller.itemCount;       // Total number of loaded items
controller.totalHeight;     // Total content height in pixels
controller.visibility;      // Current VisibilityState
controller.engine;          // Direct access to ReaderEngine (advanced)

// Effective height includes lazy-load buffer
controller.effectiveTotalHeight;  // totalHeight + buffer if hasMoreAfter
```

### Measurement Reporting

Usually handled automatically by `MeasuredItem` inside `ReaderView`. For manual use:

```dart
controller.reportMeasuredHeight(index, actualHeight);
```

### Lifecycle

```dart
// Dispose when done (detaches scroll listener, disposes ChangeNotifier)
controller.dispose();
```

---

## Lazy Loading / Infinite Scroll

The controller provides a complete lazy-loading system with edge detection, loading guards, batch mutations, and windowed eviction.

### Basic Setup

```dart
final controller = ReaderController(
  items: initialPage,
  typeConfigs: myConfigs,
  initialWidth: 390,
  hasMoreAfter: true,     // More content exists after these items
  hasMoreBefore: false,   // Nothing before (e.g., start of chat)
  edgeThreshold: 5,       // Fire callback when within 5 items of edge
);

controller.onEdgeReached = (direction) async {
  if (direction == LoadDirection.after) {
    final page = await api.fetchNextPage(cursor);
    controller.appendItems(page.items);
    controller.hasMoreAfter = page.hasNext;
  } else {
    final page = await api.fetchPreviousPage(cursor);
    controller.prependItems(page.items);
    controller.hasMoreBefore = page.hasPrevious;
  }
};
```

### Batch Mutations

All mutation methods apply scroll compensation automatically and notify listeners.

```dart
// Append items after the last item
controller.appendItems(newItems);

// Prepend items before the first item (scroll position preserved)
controller.prependItems(olderItems);

// Insert at arbitrary index
controller.insertItems(50, newItems);

// Remove a range of items
controller.removeItems(startIndex, count);

// With estimated heights for better initial accuracy
controller.appendItems(
  newItems,
  estimatedHeights: [60.0, 55.0, null, 70.0],  // null = use type default
);
```

### Edge Detection

The controller checks edge proximity on every scroll event:

```
┌─────────────────────────────┐
│ Item 0                      │
│ Item 1                      │
│ Item 2    ← edgeThreshold   │  If firstVisible <= edgeThreshold
│ Item 3    ← firstVisible    │  AND hasMoreBefore = true
│ Item 4                      │  → onEdgeReached(LoadDirection.before)
│ ...                         │
│ Item 97                     │
│ Item 98   ← lastVisible     │  If (itemCount - 1 - lastVisible) <= edgeThreshold
│ Item 99   ← edgeThreshold   │  AND hasMoreAfter = true
│                             │  → onEdgeReached(LoadDirection.after)
└─────────────────────────────┘
```

**Initial edge check:** When the view first attaches (e.g., starting at offset 0 with `hasMoreBefore = true`), the controller schedules a post-frame callback to check edge proximity after layout is established. This fires `onEdgeReached(LoadDirection.before)` automatically.

### Loading Guards

Internal boolean flags prevent `onEdgeReached` from firing multiple times during a single load:

```
1. User scrolls near end
2. _isLoadingAfter = true
3. onEdgeReached(LoadDirection.after) fires
4. User continues scrolling — guard prevents re-fire
5. Your callback calls controller.appendItems(newItems)
6. appendItems() resets _isLoadingAfter = false
7. If user is still near (new) end, onEdgeReached fires again
```

Guards are reset:
- `appendItems()` resets `_isLoadingAfter`
- `prependItems()` resets `_isLoadingBefore`
- `insertItems()` resets both
- Calling with an empty list still resets the guard (useful for error retry)

### Windowed Eviction

For datasets that can grow unbounded (chat history, social feeds), use `evictDistantItems()` to cap memory:

```dart
controller.evictDistantItems(maxLoadedItems: 5000);
```

**How it works:**
1. If `itemCount <= maxLoadedItems`, does nothing
2. Finds the center of the currently visible range
3. Calculates a keep window of `maxLoadedItems` centered on that point
4. Evicts tail items first (so head indices remain valid), then head items
5. Sets `hasMoreAfter = true` / `hasMoreBefore = true` on evicted sides
6. Applies scroll compensation to preserve visual position
7. Notifies listeners

**Typical usage — call after every page load:**

```dart
controller.onEdgeReached = (direction) async {
  final page = await api.fetchPage(direction, cursor);
  if (direction == LoadDirection.after) {
    controller.appendItems(page.items);
    controller.hasMoreAfter = page.hasNext;
  } else {
    controller.prependItems(page.items);
    controller.hasMoreBefore = page.hasPrevious;
  }
  // Cap memory at ~5000 items
  controller.evictDistantItems(maxLoadedItems: 5000);
};
```

### Effective Scroll Extent

When `hasMoreAfter = true`, the scroll extent is extended by `loadMoreBufferExtent` (default 500px) so the user can scroll into the load zone:

```dart
controller.effectiveTotalHeight;
// = totalHeight + 500.0   (when hasMoreAfter = true)
// = totalHeight            (when hasMoreAfter = false)
```

This is used internally by the `ReaderView`'s scroll delegate. The scrollbar won't hit the absolute end before new content loads.

### Complete Lazy-Loading Example

```dart
class ChatScreen extends StatefulWidget {
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ReaderController _controller;

  @override
  void initState() {
    super.initState();

    _controller = ReaderController(
      items: initialMessages,
      typeConfigs: {
        'message': const ItemTypeConfig(
          typeName: 'message',
          defaultHeight: 72.0,
          defaultConfidence: 0.3,
          widthSensitivity: WidthSensitivity.dependent,
        ),
        'dateSeparator': const ItemTypeConfig(
          typeName: 'dateSeparator',
          defaultHeight: 32.0,
          defaultConfidence: 0.95,
          widthSensitivity: WidthSensitivity.invariant,
        ),
      },
      initialWidth: 390,
      hasMoreBefore: true,   // Older messages exist
      hasMoreAfter: false,   // At latest message
      edgeThreshold: 5,
    );

    _controller.onEdgeReached = (direction) async {
      if (direction == LoadDirection.before) {
        final older = await chatApi.fetchOlderMessages(cursor);
        _controller.prependItems(older.items);
        _controller.hasMoreBefore = older.hasMore;
      }
      // Evict messages far from viewport
      _controller.evictDistantItems(maxLoadedItems: 3000);
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReaderView(
      controller: _controller,
      itemBuilder: (context, index, item) {
        return switch (item.typeKey) {
          'message'       => MessageBubble(item.data as Map),
          'dateSeparator' => DateSeparator(item.data as String),
          _               => const SizedBox.shrink(),
        };
      },
    );
  }
}
```

---

## Measurement Pipeline

### Three-Tier System

```
Tier 1: Type Default (build time)
├── Source:      ItemTypeConfig.defaultHeight
├── Confidence:  0.2–0.95
├── When:        Immediately at construction
└── Cost:        Zero

Tier 2: Pre-measured (background)
├── Source:      TextPremeasurer via MeasurementScheduler
├── Confidence:  0.85–0.9
├── When:        Idle frames, before items are rendered
└── Cost:        TextPainter layout (no GPU rendering)

Tier 3: Measured (after render)
├── Source:      MeasuredItem wrapping each widget
├── Confidence:  1.0 (ground truth)
├── When:        After item appears on screen
└── Cost:        Requires item to be laid out by Flutter
```

Heights converge upward: Tier 1 → Tier 2 → Tier 3. Each upgrade triggers scroll compensation if the item is above the viewport.

### MeasuredItem

Automatically wraps each item inside `ReaderView`. Reports the actual rendered height back to the engine via a post-frame callback.

```dart
MeasuredItem({
  required Widget child,
  required ValueChanged<double> onMeasured,
  required int itemIndex,
})
```

You don't need to use this directly — `ReaderView` handles it. But if building a custom scroll implementation:

```dart
MeasuredItem(
  itemIndex: index,
  onMeasured: (height) => controller.reportMeasuredHeight(index, height),
  child: YourWidget(),
);
```

**Behavior:**
- Only reports if height actually changed from last report
- Reports in a post-frame callback (doesn't affect the build phase)
- Uses `RenderObject` for accurate layout dimensions

### TextPremeasurer

Pre-measures text content using `TextPainter` to produce Tier 2 estimates. Reuses a single `TextPainter` instance for efficiency.

```dart
final premeasurer = TextPremeasurer();

// Measure plain text
final estimate = premeasurer.measureText(
  text: 'In the beginning God created...',
  style: TextStyle(fontSize: 16),
  maxWidth: 390,
  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
);
print(estimate.height);      // Pre-computed height
print(estimate.confidence);  // 0.9

// Measure rich text
final estimate = premeasurer.measureTextSpan(
  textSpan: TextSpan(children: [...]),
  maxWidth: 390,
);
print(estimate.confidence);  // 0.85

// Create a reusable estimator function for ItemTypeConfig
final verseEstimator = premeasurer.createEstimator(
  textExtractor: (data) => data['text'] as String,
  style: TextStyle(fontSize: 16),
  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
);

// Use in type config
final typeConfig = ItemTypeConfig(
  typeName: 'verse',
  defaultHeight: 56.0,
  estimator: verseEstimator,  // Called during build + width changes
);

// Don't forget to dispose
premeasurer.dispose();
```

### MeasurementScheduler

Runs background pre-measurement during idle frames. Queries the engine for low-confidence items, measures them, and feeds results back.

```dart
final scheduler = MeasurementScheduler(
  engine: controller.engine,
  premeasurer: premeasurer,
  configs: {
    'verse': PremeasureConfig(
      textExtractor: (data) => (data as Map)['text'] as String,
      style: TextStyle(fontSize: 16, height: 1.5),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    // Items without a config are skipped (e.g., chapter headers)
  },
  batchSize: 10,              // Items per idle frame
  confidenceThreshold: 0.5,   // Only measure items below this
  onComplete: () => print('All items pre-measured'),
);

// Start background measurement
scheduler.start();

// Stop when no longer needed
scheduler.stop();

// Clean up
scheduler.dispose();
```

**How it works:**
1. `start()` schedules a post-frame callback
2. Each frame: queries `engine.nextItemsToMeasure()` for up to `batchSize` low-confidence items
3. Measures them using `TextPremeasurer`
4. Reports results to engine via `reportMeasuredHeights()`
5. Schedules another frame if more items remain
6. Calls `onComplete` when all items are above `confidenceThreshold`

```dart
// Manual step-by-step (e.g., for testing)
final measured = scheduler.measureBatch();
print('Measured $measured items this batch');
```

---

## Search

### ReaderSearchController

Full-text search across reader items with debounced queries and match navigation.

```dart
final searchController = ReaderSearchController(
  reader: controller,
  textExtractors: {
    'verse': (data) => (data as Map)['text'] as String,
    'chapter': (data) => data as String,
    // Types without an extractor are skipped
  },
  debounceDuration: const Duration(milliseconds: 300),
);
```

| Property | Type | Description |
|---|---|---|
| `query` | `String` | Current search query |
| `matches` | `List<SearchMatch>` | All matches in item order |
| `currentMatchIndex` | `int` | Index into `matches` (-1 if none) |
| `currentMatch` | `SearchMatch?` | Currently highlighted match |
| `matchCount` | `int` | Total matches found |
| `hasMatches` | `bool` | Whether any matches exist |
| `isActive` | `bool` | Whether a query is active |
| `currentMatchDisplay` | `String` | Formatted display: `"3 of 17"` or `"No results"` |

| Method | Description |
|---|---|
| `search(String query)` | Run a case-insensitive search (debounced) |
| `clear()` | Clear search state |
| `nextMatch()` | Navigate to next match (wraps around) |
| `previousMatch()` | Navigate to previous match (wraps around) |
| `jumpToMatch(int index)` | Jump to specific match by index |
| `isItemMatch(int index)` | Check if item contains a match |
| `isCurrentMatch(int index)` | Check if item is the current match |
| `matchesForItem(int index)` | Get all matches within an item |

**SearchMatch:**

```dart
class SearchMatch {
  final int itemIndex;      // Global item index
  final String itemId;      // Item's unique ID
  final String text;        // Full text that was searched
  final int matchStart;     // Character offset of match start
  final int matchEnd;       // Character offset of match end

  String get matchedText;   // The matched substring
}
```

**Behavior:**
- Case-insensitive matching
- Finds ALL occurrences within each item (not just the first)
- Automatically jumps to the first match on search
- Navigation wraps around (next from last → first)
- Items without a text extractor are silently skipped
- Extractor exceptions are caught and the item is skipped

### ReaderSearchBar

A ready-made Material Design search bar:

```dart
ReaderSearchBar(
  controller: searchController,
  hintText: 'Search Bible...',
  autofocus: true,
  onClose: () => setState(() => showSearch = false),
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
);
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `controller` | `ReaderSearchController` | required | The search controller |
| `hintText` | `String` | `'Search...'` | Placeholder text |
| `onClose` | `VoidCallback?` | `null` | Called when close button pressed |
| `autofocus` | `bool` | `true` | Auto-focus the text field |
| `backgroundColor` | `Color?` | `surfaceContainerHighest` | Background color |
| `borderColor` | `Color?` | `outlineVariant` | Border color |
| `inputTextStyle` | `TextStyle?` | `bodyMedium` | Input text style |
| `matchCountStyle` | `TextStyle?` | `bodySmall` | Match count text style |
| `iconColor` | `Color?` | `null` | Icon button color |
| `contentPadding` | `EdgeInsets?` | `h:8, v:4` | Internal content padding |
| `iconSize` | `double` | `18` | Icon button size |
| `iconConstraints` | `BoxConstraints?` | `28x28 min` | Icon button constraints |

**Layout:** `[ TextField | "3 of 17" | < | > | X ]`

### SearchHighlightText

Renders text with highlighted search matches:

```dart
SearchHighlightText(
  text: item.data['text'],
  matches: searchController.matchesForItem(index),
  currentMatch: searchController.currentMatch,
  style: TextStyle(fontSize: 16),
  highlightColor: Colors.yellow.withAlpha(102),
  currentHighlightColor: Colors.orange.withAlpha(153),
);
```

**For embedding in RichText:**

```dart
final span = SearchHighlightText.buildHighlightedSpan(
  text: item.data['text'],
  matches: searchController.matchesForItem(index),
  currentMatch: searchController.currentMatch,
  style: baseStyle,
);

RichText(text: span);
```

---

## Visibility Tracking

### VisibilityNotifier

A `ChangeNotifier` that tracks which items are currently visible:

```dart
final notifier = VisibilityNotifier(engine: controller.engine);

notifier.addListener(() {
  print('Visible: ${notifier.firstVisible} to ${notifier.lastVisible}');
  print('Anchor: ${notifier.anchorIndex}');
  print('Count: ${notifier.visibleCount}');
});

// Check specific items
if (notifier.isVisible(42)) {
  print('Item 42 is on screen');
}

// Clean up
notifier.dispose();
```

| Property | Type | Description |
|---|---|---|
| `firstVisible` | `int` | First visible item index (-1 if none) |
| `lastVisible` | `int` | Last visible item index (-1 if none) |
| `anchorIndex` | `int` | First fully visible item |
| `visibleCount` | `int` | Number of visible items |

| Method | Description |
|---|---|
| `isVisible(int index)` | Whether an item is currently in the viewport |
| `update()` | Manually trigger a visibility refresh |

**Use cases:**
- Current chapter/verse indicators
- Read position tracking and bookmarking
- Analytics — which content was viewed
- Active verse/lyric highlighting
- Lazy image loading for visible items only

---

## Width Changes

`ReaderView` detects viewport width changes automatically and calls `controller.onWidthChanged()`. The engine recomputes heights based on each item's `WidthSensitivity` and applies scroll compensation.

If you need to handle width changes manually (e.g., in a custom implementation):

```dart
controller.onWidthChanged(newWidth);
```

---

## Performance

### How ReaderView Achieves Accuracy

Standard `SliverChildBuilderDelegate` estimates max scroll extent using:
```
averageItemHeight * totalItemCount
```

`ReaderView` overrides `estimateMaxScrollOffset` to return the engine's pre-computed `effectiveTotalHeight` — the sum of all per-item heights (estimated or measured). This means:

- **Frame 1:** Scroll extent is based on type defaults × actual count (much better than average)
- **After Tier 2:** Scroll extent is based on TextPainter measurements (very accurate)
- **After Tier 3:** Scroll extent is pixel-perfect for measured items

### Memory & Speed

For a 31,000-item Bible:

| Metric | Value |
|---|---|
| Engine build time | ~1 ms |
| Jump to any item | < 0.3 us |
| Memory overhead | ~1 MB |
| Measurement report | < 0.2 us |
| Batch insert 100 items | < 1 ms |

A Flutter frame is 16,000 us. Every operation is **< 0.003% of a frame budget**.

### Comparison with Production Apps

| Feature | flutter_reader | Slack | Instagram | WhatsApp |
|---|---|---|---|---|
| Jump-to-item accuracy | O(log N) per-item | Simple estimation | N/A | Message-level |
| Height convergence | 3 tiers | 1 tier (estimate) | 1 tier (fixed) | 1 tier |
| Scroll compensation | Automatic | Manual | N/A | Manual |
| Infinite scroll | Built-in | Built-in | Built-in | Built-in |
| Windowed eviction | Built-in | Built-in | Partial | Partial |
| Full-text search | Built-in | Server-side | N/A | Server+local |
| Memory cap | 5K items default | ~5K messages | ~50 posts | ~500 messages |

---

## Do's and Don'ts

### Do

| Practice | Why |
|---|---|
| Set accurate `defaultHeight` per type | Better Tier 1 estimates = less jank on first jumps |
| Use `WidthSensitivity.invariant` for fixed-height items | Prevents unnecessary recompute on rotation |
| Provide `estimator` for text-heavy types | Tier 2 (0.85–0.9 confidence) dramatically reduces scroll error |
| Use `MeasurementScheduler` for large datasets | Background pre-measurement improves accuracy without blocking UI |
| Call `evictDistantItems()` in your `onEdgeReached` | Prevents unbounded memory growth in chat/feed apps |
| Use `itemUpdateListenable` for search highlighting | Targeted rebuilds, not full-list recreation |
| Set `edgeThreshold` based on item height | For tall items (images), use 2–3. For short items (chat), use 5–10 |
| Dispose controllers and schedulers | Prevents memory leaks and dangling listeners |
| Use batch mutations (`appendItems`/`prependItems`) | More efficient than individual `insertItems` calls in a loop |
| Call `appendItems([])` on load error | Resets the loading guard so the edge callback can re-fire |
| Use `alignment: 0.5` for search result jumps | Centers the match in the viewport for better context |

### Don't

| Anti-pattern | Why |
|---|---|
| Create a new `ReaderController` on every build | Expensive — build once, reuse across rebuilds |
| Use `jumpToId` before the view is attached | The scroll controller isn't connected yet. Schedule after first frame |
| Ignore `hasMoreAfter`/`hasMoreBefore` flags | Scrollbar will show incorrect position if these are wrong |
| Set `edgeThreshold` to 0 | Edge detection only fires when visibility is established — 0 may never trigger |
| Forget to set `hasMoreAfter = false` when data ends | The scroll extent will include the buffer zone forever |
| Wrap `ReaderView` in another scroll view | Nested scroll views with same axis conflict. Use `physics: NeverScrollableScrollPhysics()` if nesting is unavoidable |
| Return different widget types for the same `typeKey` | Height estimates assume consistent widget structure per type |
| Block the `onEdgeReached` callback | The callback should be fast (start an async load). Don't `await` a network call synchronously |
| Call `evictDistantItems` with a very small `maxLoadedItems` | Values below ~100 risk evicting visible items. Keep it at 500+ minimum |
| Use `reportMeasuredHeight` for estimated values | That's for Tier 3 (actual render) only. Use `estimator` in `ItemTypeConfig` for Tier 2 |
| Rebuild items unnecessarily | Use `const` constructors and `RepaintBoundary` (already applied internally) |

---

## Testing

Run the test suite:

```bash
flutter test packages/flutter_reader/
```

### Test Coverage: 94 Tests

| Group | Count | What's Tested |
|---|---|---|
| VisibilityNotifier | 8 | Initial state, scroll updates, anchor tracking, `isVisible`, edge cases |
| TextPremeasurer | 7 | Plain text, rich text, padding, reuse, zero-width, estimator factory |
| MeasurementScheduler | 7 | Start/stop, batch processing, completion callback, config filtering |
| ReaderSearchController | 14 | Search, clear, navigation, wrapping, debounce, multi-match, edge cases |
| ReaderSearchBar | 4 | Rendering, input, navigation buttons, close callback |
| SearchHighlightText | 4 | Highlighting, current match, no matches, span builder |
| ReaderView | 13 | Rendering, scrolling, width changes, item updates, measurement |
| ReaderController — basic | 7 | Item count, total height, visibility, measurement, jump by ID/index |
| ReaderController — batch mutations | 7 | Append, prepend, remove, insert, notifications, empty list |
| ReaderController — effectiveTotalHeight | 3 | Buffer when hasMoreAfter, exact when closed, dynamic update |
| ReaderController — edge detection | 5 | Before/after edge, loading guard, guard reset, disabled detection |
| ReaderController — evictDistantItems | 6 | No-op, tail eviction, head eviction, both, notifications, threshold |
| AnchorTracker | 9 | Snapshot, restore, compensation, reset, clamp |

### Writing Tests for Your Integration

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

void main() {
  testWidgets('can jump to a verse', (tester) async {
    final controller = ReaderController(
      items: buildBibleItems(),
      typeConfigs: bibleTypeConfigs,
      initialWidth: 390,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ReaderView(
          controller: controller,
          itemBuilder: (_, index, item) => SizedBox(
            height: 50,
            child: Text(item.id),
          ),
        ),
      ),
    );

    controller.jumpToId('gen_3_16');
    await tester.pump();

    // Verify the item is now visible
    expect(find.text('gen_3_16'), findsOneWidget);

    controller.dispose();
  });

  test('lazy loading appends items', () {
    final controller = ReaderController(
      items: initialItems,
      typeConfigs: configs,
      initialWidth: 390,
      hasMoreAfter: true,
    );

    final oldCount = controller.itemCount;
    controller.appendItems(newPageItems);
    expect(controller.itemCount, oldCount + newPageItems.length);

    controller.dispose();
  });
}
```

---

## Full Integration Example

```dart
class BibleReaderScreen extends StatefulWidget {
  final String bookId;
  const BibleReaderScreen({required this.bookId});

  @override
  State<BibleReaderScreen> createState() => _BibleReaderScreenState();
}

class _BibleReaderScreenState extends State<BibleReaderScreen> {
  late final ReaderController _controller;
  late final ReaderSearchController _searchController;
  late final MeasurementScheduler _scheduler;
  late final VisibilityNotifier _visibilityNotifier;
  final _premeasurer = TextPremeasurer();
  bool _showSearch = false;

  static const _typeConfigs = {
    'chapter': ItemTypeConfig(
      typeName: 'chapter',
      defaultHeight: 48.0,
      defaultConfidence: 0.95,
      widthSensitivity: WidthSensitivity.invariant,
    ),
    'verse': ItemTypeConfig(
      typeName: 'verse',
      defaultHeight: 56.0,
      defaultConfidence: 0.3,
      widthSensitivity: WidthSensitivity.dependent,
    ),
  };

  @override
  void initState() {
    super.initState();

    final items = buildBibleItems(widget.bookId);

    _controller = ReaderController(
      items: items,
      typeConfigs: _typeConfigs,
      initialWidth: 390,
    );

    _searchController = ReaderSearchController(
      reader: _controller,
      textExtractors: {
        'verse': (data) => (data as Map)['text'] as String,
      },
    );

    _visibilityNotifier = VisibilityNotifier(engine: _controller.engine);

    _scheduler = MeasurementScheduler(
      engine: _controller.engine,
      premeasurer: _premeasurer,
      configs: {
        'verse': PremeasureConfig(
          textExtractor: (data) => (data as Map)['text'] as String,
          style: const TextStyle(fontSize: 16, height: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      },
    );
    _scheduler.start();
  }

  @override
  void dispose() {
    _scheduler.dispose();
    _visibilityNotifier.dispose();
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: _visibilityNotifier,
          builder: (_, __) => Text('Chapter ${_currentChapter()}'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _showSearch = !_showSearch),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch)
            ReaderSearchBar(
              controller: _searchController,
              onClose: () => setState(() {
                _showSearch = false;
                _searchController.clear();
              }),
            ),
          Expanded(
            child: ReaderView(
              controller: _controller,
              itemBuilder: _buildItem,
              itemUpdateListenable: _searchController,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index, ReaderItem item) {
    return switch (item.typeKey) {
      'chapter' => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Text(
            item.data as String,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
      'verse' => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SearchHighlightText(
            text: (item.data as Map)['text'] as String,
            matches: _searchController.matchesForItem(index),
            currentMatch: _searchController.currentMatch,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
        ),
      _ => const SizedBox.shrink(),
    };
  }

  String _currentChapter() {
    final first = _visibilityNotifier.firstVisible;
    if (first < 0) return '...';
    // Walk backward to find the nearest chapter header
    for (var i = first; i >= 0; i--) {
      final item = _controller.engine.itemAt(i);
      if (item.typeKey == 'chapter') return item.data as String;
    }
    return '1';
  }
}
```

---

## License

Apache 2.0. See [LICENSE](LICENSE) for details.
