import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../primitives/pb_svg_icon.dart';
import 'pb_menu_anchor.dart';
import 'pb_menu_card.dart';

typedef PbSidepaneMenuBuilder = Widget Function(VoidCallback closeMenu);

class PbSidepaneItemMenu extends StatefulWidget {
  const PbSidepaneItemMenu({super.key, required this.panelBuilder, this.size = 38, this.panelWidth = 204, this.onOpenChanged});

  final PbSidepaneMenuBuilder panelBuilder;
  final double size;
  final double panelWidth;
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<PbSidepaneItemMenu> createState() => _PbSidepaneItemMenuState();
}

class _PbSidepaneItemMenuState extends State<PbSidepaneItemMenu> {
  bool _open = false;

  void _setOpen(bool open) {
    if (_open == open) {
      return;
    }

    setState(() => _open = open);
    widget.onOpenChanged?.call(open);
  }

  void _closeMenu() {
    if (!_open) {
      return;
    }

    _setOpen(false);
  }

  void _toggleMenu() => _setOpen(!_open);

  @override
  Widget build(BuildContext context) {
    return PbMenuAnchor(
      placement: PbMenuAnchorPlacement.bottomRight,
      gap: 2,
      onDismiss: _closeMenu,
      panel: _open ? PbMenuCard(width: widget.panelWidth, child: widget.panelBuilder(_closeMenu)) : null,
      child: _SidepaneMenuGhostIcon(assetName: 'ellipsis', size: widget.size, selected: _open, onPressed: _toggleMenu),
    );
  }
}

class _SidepaneMenuGhostIcon extends StatefulWidget {
  const _SidepaneMenuGhostIcon({required this.assetName, this.size = 38, this.selected = false, this.onPressed});

  final String assetName;
  final double size;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  State<_SidepaneMenuGhostIcon> createState() => _SidepaneMenuGhostIconState();
}

class _SidepaneMenuGhostIconState extends State<_SidepaneMenuGhostIcon> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered || _pressed;
    final iconOpacity = active ? 1.0 : 0.3;

    return MouseRegion(
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
          widget.onPressed?.call();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              scale: _pressed ? 0.96 : 1,
              child: PbSvgIcon(
                assetName: widget.assetName,
                size: 18,
                color: PbColors.customBrandInk.withValues(alpha: iconOpacity),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
