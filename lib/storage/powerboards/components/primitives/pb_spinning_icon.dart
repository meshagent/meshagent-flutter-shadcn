import 'package:flutter/material.dart';

import 'pb_svg_icon.dart';

class PbSpinningIcon extends StatefulWidget {
  const PbSpinningIcon({
    super.key,
    required this.assetName,
    required this.color,
    this.size = 26,
    this.duration = const Duration(milliseconds: 900),
  });

  final String assetName;
  final Color color;
  final double size;
  final Duration duration;

  @override
  State<PbSpinningIcon> createState() => _PbSpinningIconState();
}

class _PbSpinningIconState extends State<PbSpinningIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..repeat();
  }

  @override
  void didUpdateWidget(covariant PbSpinningIcon oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: PbSvgIcon(assetName: widget.assetName, size: widget.size, color: widget.color),
    );
  }
}
