import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_tokens.dart';
import '../../theme/pb_typography.dart';
import '../primitives/pb_svg_icon.dart';
import 'pb_file_selection_checkbox.dart';

class PbDialogFileListItemData {
  const PbDialogFileListItemData({
    required this.id,
    required this.title,
    required this.iconAssetName,
    required this.iconColor,
    this.depth = 1,
    this.enabled = true,
    this.selectionEnabled = true,
    this.visuallyDisabled = false,
  });

  final String id;
  final String title;
  final String iconAssetName;
  final Color iconColor;
  final int depth;
  final bool enabled;
  final bool selectionEnabled;
  final bool visuallyDisabled;
}

class PbDialogFileList extends StatefulWidget {
  const PbDialogFileList({
    super.key,
    required this.items,
    this.selectedIds = const {},
    this.showCheckboxes = false,
    this.framed = true,
    this.rowMargin = const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
    this.rowPadding = const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    this.listPadding = const EdgeInsets.symmetric(vertical: 6),
    this.clipBehavior = Clip.hardEdge,
    this.onToggleSelection,
    this.onItemPressed,
  });

  const PbDialogFileList.unframed({
    super.key,
    required this.items,
    this.selectedIds = const {},
    this.showCheckboxes = false,
    this.listPadding = const EdgeInsets.symmetric(vertical: 8),
    this.clipBehavior = Clip.none,
    this.onToggleSelection,
    this.onItemPressed,
  }) : framed = false,
       rowMargin = EdgeInsets.zero,
       rowPadding = const EdgeInsets.all(11);

  final List<PbDialogFileListItemData> items;
  final Set<String> selectedIds;
  final bool showCheckboxes;
  final bool framed;
  final EdgeInsetsGeometry rowMargin;
  final EdgeInsetsGeometry rowPadding;
  final EdgeInsetsGeometry listPadding;
  final Clip clipBehavior;
  final ValueChanged<String>? onToggleSelection;
  final ValueChanged<PbDialogFileListItemData>? onItemPressed;

  @override
  State<PbDialogFileList> createState() => _PbDialogFileListState();
}

class _PbDialogFileListState extends State<PbDialogFileList> {
  String? _hoveredId;
  String? _pressedId;

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      primary: false,
      clipBehavior: widget.clipBehavior,
      padding: widget.listPadding,
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final selected = widget.selectedIds.contains(item.id);
        final pressed = _pressedId == item.id;
        final hovered = _hoveredId == item.id;
        final nextItem = index < widget.items.length - 1 ? widget.items[index + 1] : null;
        final previousSelected = index > 0 && widget.selectedIds.contains(widget.items[index - 1].id);
        final nextSelected = nextItem != null && widget.selectedIds.contains(nextItem.id);
        final nextInteractive =
            nextItem != null &&
            ((widget.onItemPressed != null && nextItem.enabled) || (widget.onToggleSelection != null && nextItem.selectionEnabled));
        final beforeActiveRow =
            nextSelected || (nextItem != null && _pressedId == nextItem.id) || (_hoveredId == nextItem?.id && nextInteractive);

        return _PbDialogFileListRow(
          item: item,
          selected: selected,
          pressed: pressed,
          hovered: hovered,
          showCheckbox: widget.showCheckboxes,
          previousSelected: previousSelected,
          nextSelected: nextSelected,
          beforeActiveRow: beforeActiveRow,
          last: index == widget.items.length - 1,
          rowMargin: widget.rowMargin,
          rowPadding: widget.rowPadding,
          onHoverChanged: (isHovered) => setState(() {
            if (isHovered) {
              _hoveredId = item.id;
            } else if (_hoveredId == item.id) {
              _hoveredId = null;
            }
          }),
          onPressedChanged: (isPressed) => setState(() {
            if (isPressed) {
              _pressedId = item.id;
            } else if (_pressedId == item.id) {
              _pressedId = null;
            }
          }),
          onPressed: widget.onItemPressed == null || !item.enabled ? null : () => widget.onItemPressed!(item),
          checkboxEnabled: widget.showCheckboxes && item.selectionEnabled && widget.onToggleSelection != null,
          onToggleSelection: widget.onToggleSelection == null || !item.selectionEnabled ? null : () => widget.onToggleSelection!(item.id),
        );
      },
    );

    if (!widget.framed) {
      return ClipRect(clipper: const _PbDialogFileListOverflowClipper(), child: list);
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PbColors.borderSoft),
        color: PbColors.dynamicSurfacePanel,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(11), child: list),
    );
  }
}

class _PbDialogFileListOverflowClipper extends CustomClipper<Rect> {
  const _PbDialogFileListOverflowClipper();

  static const double _horizontalOverflow = 36;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(-_horizontalOverflow, 0, size.width + _horizontalOverflow, size.height);
  }

  @override
  bool shouldReclip(_PbDialogFileListOverflowClipper oldClipper) {
    return false;
  }
}

class _PbDialogFileListRow extends StatelessWidget {
  const _PbDialogFileListRow({
    required this.item,
    required this.selected,
    required this.pressed,
    required this.hovered,
    required this.showCheckbox,
    required this.previousSelected,
    required this.nextSelected,
    required this.beforeActiveRow,
    required this.last,
    required this.rowMargin,
    required this.rowPadding,
    required this.onHoverChanged,
    required this.onPressedChanged,
    required this.onPressed,
    required this.checkboxEnabled,
    required this.onToggleSelection,
  });

  final PbDialogFileListItemData item;
  final bool selected;
  final bool pressed;
  final bool hovered;
  final bool showCheckbox;
  final bool previousSelected;
  final bool nextSelected;
  final bool beforeActiveRow;
  final bool last;
  final EdgeInsetsGeometry rowMargin;
  final EdgeInsetsGeometry rowPadding;
  final ValueChanged<bool> onHoverChanged;
  final ValueChanged<bool> onPressedChanged;
  final VoidCallback? onPressed;
  final bool checkboxEnabled;
  final VoidCallback? onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final interactive = onPressed != null || onToggleSelection != null;
    final stateful = selected || pressed;
    final effectiveHovered = hovered && interactive;
    final hideDivider = last || stateful || effectiveHovered || beforeActiveRow;
    final backgroundColor = selected || pressed ? PbColors.dynamicCustomStateSelectedSurface : null;
    final gradient = effectiveHovered && !stateful
        ? LinearGradient(
            colors: [PbColors.dynamicSurfacePanel, PbColors.dynamicSurfacePanelSoft],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : null;
    final borderColor = pressed || selected
        ? PbColors.dynamicCustomStateSelectedBorder
        : effectiveHovered
        ? PbColors.borderSoft
        : Colors.transparent;
    final shadow = effectiveHovered && !stateful
        ? PbShadows.stateHover
        : pressed
        ? PbShadows.statePressedInset
        : null;

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: interactive ? (_) => onHoverChanged(true) : null,
      onExit: (_) {
        onHoverChanged(false);
        onPressedChanged(false);
      },
      child: Listener(
        onPointerDown: interactive ? (_) => onPressedChanged(true) : null,
        onPointerUp: interactive ? (_) => onPressedChanged(false) : null,
        onPointerCancel: interactive ? (_) => onPressedChanged(false) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed ?? onToggleSelection,
          child: Container(
            key: ValueKey('pb-dialog-file-list-row-${item.id}'),
            constraints: const BoxConstraints(minHeight: 54),
            margin: rowMargin,
            padding: rowPadding,
            decoration: BoxDecoration(
              color: backgroundColor,
              gradient: gradient,
              borderRadius: _selectionRadius(),
              border: Border.all(color: borderColor),
              boxShadow: shadow,
            ),
            foregroundDecoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: hideDivider ? Colors.transparent : PbColors.borderFaint)),
            ),
            child: Opacity(
              opacity: item.visuallyDisabled ? 0.42 : 1,
              child: Row(
                children: [
                  if (showCheckbox) ...[
                    SizedBox(
                      width: 28,
                      child: Center(
                        child: PbFileSelectionCheckbox(checked: selected, enabled: checkboxEnabled, onPressed: onToggleSelection ?? () {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  SizedBox(width: ((item.depth - 1).clamp(0, 6)) * 18.0),
                  PbSvgIcon(assetName: item.iconAssetName, size: 26, color: item.iconColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: PowerboardsTypography.button),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  BorderRadius _selectionRadius() {
    if (!selected) {
      return BorderRadius.circular((hovered && (onPressed != null || onToggleSelection != null)) || pressed ? 10 : 0);
    }
    if (!previousSelected && !nextSelected) {
      return BorderRadius.circular(10);
    }
    if (!previousSelected && nextSelected) {
      return const BorderRadius.vertical(top: Radius.circular(10));
    }
    if (previousSelected && !nextSelected) {
      return const BorderRadius.vertical(bottom: Radius.circular(10));
    }
    return BorderRadius.zero;
  }
}
