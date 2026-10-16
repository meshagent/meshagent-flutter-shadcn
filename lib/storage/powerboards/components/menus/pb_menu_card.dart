import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';

class PbMenuCard extends StatelessWidget {
  const PbMenuCard({super.key, required this.child, this.width});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PbColors.menuCardBorder),
        gradient: const LinearGradient(
          colors: [PbColors.surfacePanel, PbColors.surfacePanelSoft],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.14), blurRadius: 40, offset: Offset(0, 18))],
      ),
      child: child,
    );
  }
}
