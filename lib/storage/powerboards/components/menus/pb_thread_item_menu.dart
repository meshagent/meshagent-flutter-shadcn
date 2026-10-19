import 'package:flutter/material.dart';

import 'pb_menu_list.dart';
import 'pb_menu_option.dart';

class PbThreadItemMenu extends StatelessWidget {
  const PbThreadItemMenu({super.key, this.onRename, this.onDelete, this.onDismiss});

  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return PbMenuList(
      children: [
        PbMenuOption(
          title: 'Rename',
          leadingIconAssetName: 'text-cursor',
          singleLine: true,
          onPressed: () => _runMenuAction(onRename, onDismiss),
        ),
        PbMenuOption(
          title: 'Delete',
          leadingIconAssetName: 'trash-alert',
          singleLine: true,
          alert: true,
          onPressed: () => _runMenuAction(onDelete, onDismiss),
        ),
      ],
    );
  }
}

void _runMenuAction(VoidCallback? action, VoidCallback? dismiss) {
  action?.call();
  dismiss?.call();
}
