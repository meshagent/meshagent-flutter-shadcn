import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_typography.dart';

class PbMenuFilterField extends StatefulWidget {
  const PbMenuFilterField({
    super.key,
    this.placeholder = 'Filter...',
    this.focused,
    this.hovered,
    this.height = 40,
    this.margin = const EdgeInsets.only(bottom: 4),
    this.controller,
    this.onChanged,
    this.enabled = true,
  });

  final String placeholder;
  final bool? focused;
  final bool? hovered;
  final double height;
  final EdgeInsetsGeometry margin;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  State<PbMenuFilterField> createState() => _PbMenuFilterFieldState();
}

class _PbMenuFilterFieldState extends State<PbMenuFilterField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant PbMenuFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.enabled && (widget.focused ?? _focusNode.hasFocus);
    final hovered = widget.enabled && (widget.hovered ?? _hovered);

    final boxShadow = focused
        ? const [
            BoxShadow(color: Color.fromRGBO(199, 216, 255, 0.36), blurRadius: 0, spreadRadius: 3),
            BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.06), blurRadius: 30, offset: Offset(0, 12)),
          ]
        : hovered
        ? const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.12), blurRadius: 30, offset: Offset(0, 14))]
        : null;

    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.text : SystemMouseCursors.basic,
      onEnter: widget.enabled && widget.hovered == null ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.enabled && widget.hovered == null ? (_) => setState(() => _hovered = false) : null,
      child: Transform.translate(
        offset: Offset(0, hovered && !focused ? -1 : 0),
        child: Container(
          height: widget.height,
          margin: widget.margin,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: focused ? PbColors.borderStateSelected : PbColors.borderSoft),
            color: widget.enabled ? PbColors.surfacePanel.withValues(alpha: 0.88) : PbColors.surfacePanelSoft.withValues(alpha: 0.64),
            boxShadow: boxShadow,
          ),
          child: TextField(
            enabled: widget.enabled,
            controller: _controller,
            focusNode: _focusNode,
            onChanged: widget.enabled ? widget.onChanged : null,
            cursorColor: PbColors.textPrimary,
            style: PowerboardsTypography.p.copyWith(
              fontSize: 14,
              height: 1.3,
              color: widget.enabled ? PbColors.textPrimary : PbColors.textMuted,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: widget.placeholder,
              hintStyle: PowerboardsTypography.p.copyWith(
                fontSize: 14,
                height: 1.3,
                color: widget.enabled ? PbColors.textMuted : PbColors.textMuted.withValues(alpha: 0.62),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
