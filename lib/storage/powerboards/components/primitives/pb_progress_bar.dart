import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';

class PbProgressBar extends StatelessWidget {
  const PbProgressBar({
    super.key,
    required this.value,
    this.color = PbColors.statusOnline,
    this.backgroundColor = PbColors.borderFaint,
    this.height = 5,
    this.minVisualValue = 0,
  });

  final double? value;
  final Color color;
  final Color backgroundColor;
  final double height;
  final double minVisualValue;

  @override
  Widget build(BuildContext context) {
    final clampedValue = value?.clamp(0.0, 1.0);
    if (clampedValue == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(minHeight: height, backgroundColor: backgroundColor, color: color),
      );
    }

    final visualValue = clampedValue >= 1.0 ? 1.0 : math.max(clampedValue, minVisualValue);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: height,
          decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(999)),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: constraints.maxWidth * visualValue,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
              ),
            ],
          ),
        );
      },
    );
  }
}
