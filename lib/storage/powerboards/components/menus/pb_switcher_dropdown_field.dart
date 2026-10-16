import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_tokens.dart';
import '../../theme/pb_typography.dart';
import '../primitives/pb_svg_icon.dart';
import 'pb_menu_anchor.dart';
import 'pb_switcher_menu.dart';

class PbSwitcherDropdownField extends StatefulWidget {
  const PbSwitcherDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.menuOpen,
    required this.onMenuOpenChanged,
    required this.onItemSelected,
    this.onCreateItemPressed,
    this.actionLabel = 'New Item',
    this.emptyLabel = 'No items found',
    this.filterPlaceholder = 'Filter...',
  });

  final String value;
  final List<String> items;
  final bool menuOpen;
  final ValueChanged<bool> onMenuOpenChanged;
  final ValueChanged<String> onItemSelected;
  final Future<String?> Function()? onCreateItemPressed;
  final String actionLabel;
  final String emptyLabel;
  final String filterPlaceholder;

  @override
  State<PbSwitcherDropdownField> createState() => _PbSwitcherDropdownFieldState();
}

class _PbSwitcherDropdownFieldState extends State<PbSwitcherDropdownField> {
  final TextEditingController _filterController = TextEditingController();

  bool _hovered = false;
  bool _pressed = false;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedSurface = _pressed || widget.menuOpen;
    final filtering = _filterController.text.trim().isNotEmpty;
    final actionLabel = filtering
        ? 'Clear results'
        : widget.onCreateItemPressed == null
        ? null
        : widget.actionLabel;

    return LayoutBuilder(
      builder: (context, constraints) {
        final menuWidth = constraints.hasBoundedWidth ? constraints.maxWidth : 320.0;

        return PbMenuAnchor(
          placement: PbMenuAnchorPlacement.bottomLeft,
          gap: 8,
          preferAboveWhenOverflow: true,
          onDismiss: () => widget.onMenuOpenChanged(false),
          panel: widget.menuOpen
              ? Material(
                  type: MaterialType.transparency,
                  child: PbSwitcherMenu(
                    width: menuWidth,
                    filterPlaceholder: widget.filterPlaceholder,
                    filterController: _filterController,
                    onFilterChanged: (_) => setState(() {}),
                    actionLabel: actionLabel,
                    actionLeadingIconAssetName: 'plus',
                    actionLeadingIconTurns: filtering ? -0.125 : 0,
                    onActionPressed: filtering ? _clearFilter : _createItem,
                    items: _menuItems,
                    emptyLabel: widget.emptyLabel,
                    onItemPressed: _selectItem,
                  ),
                )
              : null,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() {
              _hovered = false;
              _pressed = false;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) {
                setState(() => _pressed = false);
                widget.onMenuOpenChanged(!widget.menuOpen);
              },
              onTapCancel: () => setState(() => _pressed = false),
              child: Transform.translate(
                offset: Offset(0, _hovered && !_pressed && !widget.menuOpen ? -1 : 0),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(PbRadii.small),
                    border: Border.all(color: selectedSurface ? PbColors.borderStateSelected : PbColors.borderSoft),
                    color: selectedSurface ? PbColors.surfaceStateSelected : PbColors.surfacePanel,
                    boxShadow: _hovered && !_pressed && !widget.menuOpen ? PbShadows.stateHover : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PowerboardsTypography.button.copyWith(color: PbColors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      AnimatedRotation(
                        turns: widget.menuOpen ? -0.5 : 0,
                        duration: PbMotion.chevron,
                        curve: Curves.easeOutCubic,
                        child: const PbSvgIcon(assetName: 'chevron-down', size: 16, color: PbColors.customBrandInk),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _createItem() async {
    final item = await widget.onCreateItemPressed?.call();
    if (!mounted || item == null || item.isEmpty) {
      return;
    }

    _filterController.clear();
    widget.onItemSelected(item);
  }

  void _clearFilter() {
    _filterController.clear();
    setState(() {});
  }

  void _selectItem(String item) {
    _filterController.clear();
    widget.onItemSelected(item);
  }

  List<PbSwitcherMenuItem> get _menuItems {
    final query = _filterController.text.trim().toLowerCase();

    return widget.items
        .where((item) => query.isEmpty || item.toLowerCase().contains(query))
        .map((item) => PbSwitcherMenuItem(title: item, selected: item == widget.value))
        .toList(growable: false);
  }
}
