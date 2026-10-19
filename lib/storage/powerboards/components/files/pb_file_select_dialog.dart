import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_typography.dart';
import '../dialogs/pb_dialog.dart';
import '../menus/pb_switcher_dropdown_field.dart';
import '../primitives/pb_svg_icon.dart';
import 'pb_file_selection_checkbox.dart';

class PbFileSelectDialog extends StatefulWidget {
  const PbFileSelectDialog({
    super.key,
    required this.rooms,
    required this.selectedRoom,
    required this.fileBrowser,
    required this.canAdd,
    required this.onRoomSelected,
    required this.onAddPressed,
    required this.onClose,
  });

  final List<String> rooms;
  final String selectedRoom;
  final Widget fileBrowser;
  final bool canAdd;
  final ValueChanged<String> onRoomSelected;
  final VoidCallback onAddPressed;
  final VoidCallback onClose;

  @override
  State<PbFileSelectDialog> createState() => _PbFileSelectDialogState();
}

class _PbFileSelectDialogState extends State<PbFileSelectDialog> {
  bool _roomMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    return PbDialogShell(
      title: 'Select files',
      subtitle: 'Attach files from this room',
      bodyExpanded: true,
      onClose: widget.onClose,
      surfacePadding: EdgeInsets.zero,
      headerPadding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      actionsPadding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
      headerBodySpacing: 24,
      bodyActionsSpacing: 0,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: PbSwitcherDropdownField(
              key: const ValueKey('pb-file-select-room-switcher'),
              value: widget.selectedRoom,
              items: widget.rooms,
              menuOpen: _roomMenuOpen,
              onMenuOpenChanged: (open) => setState(() => _roomMenuOpen = open),
              onItemSelected: (room) {
                setState(() => _roomMenuOpen = false);
                widget.onRoomSelected(room);
              },
              emptyLabel: 'No rooms found',
            ),
          ),
          Expanded(child: widget.fileBrowser),
        ],
      ),
      actions: PbDialogActions(
        secondaryLabel: 'Cancel',
        primaryLabel: 'Add',
        onSecondaryPressed: widget.onClose,
        onPrimaryPressed: widget.canAdd ? widget.onAddPressed : null,
      ),
    );
  }
}

class PbFilesMoveDestinationDialog extends StatefulWidget {
  const PbFilesMoveDestinationDialog({
    super.key,
    required this.rooms,
    required this.selectedRoom,
    required this.fileBrowser,
    required this.itemCount,
    required this.canConfirm,
    required this.onRoomSelected,
    required this.onConfirm,
    required this.onClose,
  });

  final List<String> rooms;
  final String selectedRoom;
  final Widget fileBrowser;
  final int itemCount;
  final bool canConfirm;
  final ValueChanged<String> onRoomSelected;
  final ValueChanged<bool> onConfirm;
  final VoidCallback onClose;

  @override
  State<PbFilesMoveDestinationDialog> createState() => _PbFilesMoveDestinationDialogState();
}

class _PbFilesMoveDestinationDialogState extends State<PbFilesMoveDestinationDialog> {
  bool _roomMenuOpen = false;
  bool _copyFilesInstead = false;

  @override
  Widget build(BuildContext context) {
    return PbDialogShell(
      title: 'Move files to',
      subtitle: _moveDestinationDescription(widget.itemCount),
      bodyExpanded: true,
      maxHeight: 700,
      viewportVerticalInset: 120,
      onClose: widget.onClose,
      surfacePadding: EdgeInsets.zero,
      headerPadding: const EdgeInsets.fromLTRB(30, 30, 30, 0),
      actionsPadding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
      headerBodySpacing: 24,
      bodyActionsSpacing: 18,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 0, 30, 16),
            child: PbSwitcherDropdownField(
              key: const ValueKey('pb-files-move-room-switcher'),
              value: widget.selectedRoom,
              items: widget.rooms,
              menuOpen: _roomMenuOpen,
              onMenuOpenChanged: (open) => setState(() => _roomMenuOpen = open),
              onItemSelected: (room) {
                setState(() => _roomMenuOpen = false);
                widget.onRoomSelected(room);
              },
              emptyLabel: 'No rooms found',
            ),
          ),
          Expanded(child: widget.fileBrowser),
        ],
      ),
      actions: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CopyFilesInsteadToggle(checked: _copyFilesInstead, onChanged: (checked) => setState(() => _copyFilesInstead = checked)),
          const SizedBox(height: 18),
          PbDialogActions(
            secondaryLabel: 'Cancel',
            primaryLabel: _copyFilesInstead ? 'Copy files to' : 'Move files to',
            onSecondaryPressed: widget.onClose,
            onPrimaryPressed: widget.canConfirm ? () => widget.onConfirm(_copyFilesInstead) : null,
          ),
        ],
      ),
    );
  }
}

class _CopyFilesInsteadToggle extends StatelessWidget {
  const _CopyFilesInsteadToggle({required this.checked, required this.onChanged});

  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    void toggle() => onChanged(!checked);

    return Semantics(
      label: 'Copy files instead',
      checked: checked,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('pb-files-copy-instead-toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: toggle,
          child: Row(
            children: [
              PbFileSelectionCheckbox(checked: checked, onPressed: toggle),
              const SizedBox(width: 12),
              Text('Copy files instead.', style: PowerboardsTypography.button),
            ],
          ),
        ),
      ),
    );
  }
}

String _moveDestinationDescription(int itemCount) {
  final count = itemCount.clamp(1, 9999);
  return 'Choose a destination for $count selected ${count == 1 ? 'item' : 'items'}.';
}

class PbFileSelectBreadcrumb extends StatelessWidget {
  const PbFileSelectBreadcrumb({super.key, required this.currentPath, required this.onRootPressed, required this.onSegmentPressed});

  final String currentPath;
  final VoidCallback onRootPressed;
  final ValueChanged<int> onSegmentPressed;

  @override
  Widget build(BuildContext context) {
    final segments = currentPath.split('/').where((part) => part.isNotEmpty).toList(growable: false);
    final visibleSegments = segments.length <= 2 ? segments : ['...', segments.last];

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 10),
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            _FileSelectBreadcrumbText(label: 'Browse', active: currentPath.isEmpty, onPressed: currentPath.isEmpty ? null : onRootPressed),
            for (var index = 0; index < visibleSegments.length; index++) ...[
              const _FileSelectBreadcrumbChevron(),
              Flexible(
                flex: index == visibleSegments.length - 1 ? 2 : 1,
                child: _FileSelectBreadcrumbText(
                  label: visibleSegments[index],
                  active: index == visibleSegments.length - 1,
                  onPressed: visibleSegments[index] == '...' || index == visibleSegments.length - 1 ? null : () => onSegmentPressed(index),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PbFileSelectStatus extends StatelessWidget {
  const PbFileSelectStatus({super.key, required this.message, this.loading = false}) : empty = false;

  const PbFileSelectStatus.empty({super.key, required this.message}) : loading = false, empty = true;

  final String message;
  final bool loading;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: PbColors.customBlue)),
              const SizedBox(height: 14),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: empty ? PowerboardsTypography.listEmptyState : PowerboardsTypography.meta.copyWith(color: PbColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileSelectBreadcrumbText extends StatefulWidget {
  const _FileSelectBreadcrumbText({required this.label, required this.active, this.onPressed});

  final String label;
  final bool active;
  final VoidCallback? onPressed;

  @override
  State<_FileSelectBreadcrumbText> createState() => _FileSelectBreadcrumbTextState();
}

class _FileSelectBreadcrumbTextState extends State<_FileSelectBreadcrumbText> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final clickable = widget.onPressed != null;

    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: clickable ? (_) => setState(() => _hovered = true) : null,
      onExit: clickable ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (widget.active ? PowerboardsTypography.labelSmall : PowerboardsTypography.meta).copyWith(
              color: widget.active || _hovered ? PbColors.textPrimary : PbColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _FileSelectBreadcrumbChevron extends StatelessWidget {
  const _FileSelectBreadcrumbChevron();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: PbSvgIcon(assetName: 'chevron-right', size: 16, color: PbColors.textSubtle),
    );
  }
}
