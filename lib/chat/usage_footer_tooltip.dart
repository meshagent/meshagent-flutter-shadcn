import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class UsageFooterTooltip extends StatefulWidget {
  const UsageFooterTooltip({super.key, required this.child, required this.tooltip});

  final Widget child;
  final Widget tooltip;

  @override
  State<UsageFooterTooltip> createState() => _UsageFooterTooltipState();
}

class _UsageFooterTooltipState extends State<UsageFooterTooltip> {
  final ShadTooltipController _controller = ShadTooltipController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadTooltip(
      controller: _controller,
      builder: (context) => widget.tooltip,
      child: MouseRegion(onEnter: (_) => _controller.show(), onExit: (_) => _controller.hide(), child: widget.child),
    );
  }
}
