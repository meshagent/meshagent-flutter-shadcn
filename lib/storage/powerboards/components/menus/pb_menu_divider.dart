import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';

class PbMenuDivider extends StatelessWidget {
  const PbMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: PbColors.borderSoft);
  }
}
