import 'package:flutter/material.dart';

import 'pb_menu_divider.dart';

class PbMenuList extends StatelessWidget {
  const PbMenuList({super.key, required this.children, this.gap = 4});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1 && children[i] is! PbMenuDivider) SizedBox(height: gap),
        ],
      ],
    );
  }
}
