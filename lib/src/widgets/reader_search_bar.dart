import 'package:flutter/material.dart';

import 'reader_search_controller.dart';

/// A ready-made search bar widget for [ReaderSearchController].
///
/// Provides a text field, match count display, up/down navigation
/// buttons, and a close button.
///
/// Usage:
/// ```dart
/// ReaderSearchBar(
///   controller: mySearchController,
///   hintText: 'Search verses…',
/// )
/// ```
class ReaderSearchBar extends StatefulWidget {
  /// The search controller to drive.
  final ReaderSearchController controller;

  /// Placeholder text for the search field.
  final String hintText;

  /// Called when the search bar is closed via the close button.
  final VoidCallback? onClose;

  /// Whether to auto-focus the text field on mount.
  final bool autofocus;

  /// Background color of the search bar container.
  /// Defaults to [ColorScheme.surfaceContainerHighest].
  final Color? backgroundColor;

  /// Color of the bottom border.
  /// Defaults to [ColorScheme.outlineVariant].
  final Color? borderColor;

  /// Style for the search input text.
  /// Defaults to [TextTheme.bodyMedium].
  final TextStyle? inputTextStyle;

  /// Style for the match count display (e.g. "3 of 17").
  /// Defaults to [TextTheme.bodySmall] with [ColorScheme.onSurfaceVariant].
  final TextStyle? matchCountStyle;

  /// Color for the navigation and close icons.
  /// Defaults to the theme's icon color.
  final Color? iconColor;

  /// Content padding inside the text field.
  /// Defaults to `EdgeInsets.symmetric(horizontal: 8, vertical: 4)`.
  final EdgeInsets? contentPadding;

  /// Size of the navigation and close icons.
  /// Defaults to 18.
  final double iconSize;

  /// Minimum constraints for the icon buttons.
  /// Defaults to `BoxConstraints(minWidth: 28, minHeight: 28)`.
  final BoxConstraints? iconConstraints;

  const ReaderSearchBar({
    super.key,
    required this.controller,
    this.hintText = 'Search…',
    this.onClose,
    this.autofocus = true,
    this.backgroundColor,
    this.borderColor,
    this.inputTextStyle,
    this.matchCountStyle,
    this.iconColor,
    this.contentPadding,
    this.iconSize = 18,
    this.iconConstraints,
  });

  @override
  State<ReaderSearchBar> createState() => _ReaderSearchBarState();
}

class _ReaderSearchBarState extends State<ReaderSearchBar> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.controller.query);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    widget.controller.search(value);
  }

  void _onClose() {
    _textController.clear();
    widget.controller.clear();
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final btnConstraints = widget.iconConstraints ??
            const BoxConstraints(minWidth: 28, minHeight: 28);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: widget.backgroundColor ??
                colorScheme.surfaceContainerHighest,
          ),
          child: Row(
            children: [
              // Search field
              Expanded(
                child: TextField(
                  controller: _textController,
                  autofocus: widget.autofocus,
                  onChanged: _onChanged,
                  onSubmitted: (_) => widget.controller.nextMatch(),
                  textInputAction: TextInputAction.search,
                  style: widget.inputTextStyle ?? theme.textTheme.bodyMedium,
                  cursorHeight: 16,
                  cursorWidth: 1.5,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: (widget.inputTextStyle ?? theme.textTheme.bodyMedium)
                        ?.copyWith(color: (widget.inputTextStyle?.color ?? theme.textTheme.bodyMedium?.color)?.withValues(alpha: 0.5)),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    contentPadding: widget.contentPadding ??
                        const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                  ),
                ),
              ),

              // Match count display
              if (ctrl.isActive)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    ctrl.currentMatchDisplay,
                    style: widget.matchCountStyle ??
                        theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),

              // Previous match
              IconButton(
                icon: Icon(Icons.keyboard_arrow_up,
                    size: widget.iconSize, color: widget.iconColor),
                onPressed: ctrl.hasMatches ? ctrl.previousMatch : null,
                tooltip: 'Previous match',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: btnConstraints,
              ),

              // Next match
              IconButton(
                icon: Icon(Icons.keyboard_arrow_down,
                    size: widget.iconSize, color: widget.iconColor),
                onPressed: ctrl.hasMatches ? ctrl.nextMatch : null,
                tooltip: 'Next match',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: btnConstraints,
              ),

              // Close button
              IconButton(
                icon: Icon(Icons.close, size: widget.iconSize,
                    color: widget.iconColor),
                onPressed: _onClose,
                tooltip: 'Close search',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: btnConstraints,
              ),
            ],
          ),
        );
      },
    );
  }
}
