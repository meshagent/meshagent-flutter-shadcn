import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_tokens.dart';
import '../../theme/pb_typography.dart';
import '../layouts/pb_thread_header.dart';
import '../menus/pb_menu_anchor.dart';
import '../menus/pb_menu_card.dart';
import '../menus/pb_menu_filter_field.dart';
import '../menus/pb_menu_list.dart';
import '../menus/pb_menu_option.dart';
import '../primitives/pb_button.dart';
import '../primitives/pb_svg_icon.dart';
import 'pb_files_layout_values.dart';

class PbFilesHeader extends StatelessWidget {
  const PbFilesHeader({
    super.key,
    required this.currentPath,
    required this.folderLabelForPath,
    required this.roomPanelExpanded,
    required this.padding,
    this.showRoomPanelControls = true,
    required this.onBreadcrumbPressed,
    required this.onOpenRecentFiles,
    required this.onRoomPanelToggle,
  });

  final String currentPath;
  final String Function(String path) folderLabelForPath;
  final bool roomPanelExpanded;
  final PbFilesPanelPadding padding;
  final bool showRoomPanelControls;
  final ValueChanged<String> onBreadcrumbPressed;
  final VoidCallback onOpenRecentFiles;
  final VoidCallback onRoomPanelToggle;

  @override
  Widget build(BuildContext context) {
    final crumbs = _crumbs();

    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: EdgeInsets.fromLTRB(padding.left, 19, padding.right, 19),
      child: Row(
        children: [
          Expanded(
            child: _FilesBreadcrumb(crumbs: crumbs, onPressed: onBreadcrumbPressed),
          ),
          if (showRoomPanelControls) const SizedBox(width: 24),
          if (showRoomPanelControls)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!roomPanelExpanded) PbThreadHeaderQuaternaryButton(label: 'Recently opened files', onPressed: onOpenRecentFiles),
                if (!roomPanelExpanded) const SizedBox(width: 6),
                PbThreadPanelToggle(expanded: roomPanelExpanded, onPressed: onRoomPanelToggle),
              ],
            ),
        ],
      ),
    );
  }

  List<_FilesCrumb> _crumbs() {
    if (currentPath.isEmpty) {
      return const [_FilesCrumb(label: 'Files', path: '')];
    }

    final parts = currentPath.split('/');
    var path = '';
    return [
      const _FilesCrumb(label: 'Files', path: ''),
      for (final part in parts) _FilesCrumb(label: folderLabelForPath(path = path.isEmpty ? part : '$path/$part'), path: path),
    ];
  }
}

class PbFilesToolbarTrailingAction {
  const PbFilesToolbarTrailingAction({
    required this.label,
    required this.iconAssetName,
    required this.onPressed,
    this.width = 164,
    this.backgroundColor,
    this.pressedBackgroundColor,
    this.borderColor,
    this.pressedBorderColor,
    this.foregroundColor,
  });

  final String label;
  final String iconAssetName;
  final VoidCallback? onPressed;
  final double width;
  final Color? backgroundColor;
  final Color? pressedBackgroundColor;
  final Color? borderColor;
  final Color? pressedBorderColor;
  final Color? foregroundColor;
}

class PbFilesToolbar extends StatelessWidget {
  const PbFilesToolbar({
    super.key,
    required this.hasSelection,
    required this.selectedCount,
    required this.currentPath,
    required this.filterController,
    required this.filterEnabled,
    required this.responsiveMode,
    required this.padding,
    required this.onFilterChanged,
    required this.onCreateFolder,
    this.onInstallWebServer,
    required this.onCreateTextFile,
    required this.onUpload,
    this.onAskCurrentFolder,
    this.showAskAgent = true,
    this.trailingAction,
    this.v17WebsiteActionsEnabled = false,
    this.showWebServerPreview = false,
    this.webServerPreviewActive = false,
    this.onPreviewWebServer,
    required this.onClearSelection,
    this.onMoveSelection,
    required this.onDeleteSelection,
    required this.onDownloadSelection,
  });

  final bool hasSelection;
  final int selectedCount;
  final String currentPath;
  final TextEditingController filterController;
  final bool filterEnabled;
  final PbFilesResponsiveMode responsiveMode;
  final PbFilesPanelPadding padding;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback? onCreateFolder;
  final VoidCallback? onInstallWebServer;
  final VoidCallback? onCreateTextFile;
  final VoidCallback? onUpload;
  final VoidCallback? onAskCurrentFolder;
  final bool showAskAgent;
  final PbFilesToolbarTrailingAction? trailingAction;
  final bool v17WebsiteActionsEnabled;
  final bool showWebServerPreview;
  final bool webServerPreviewActive;
  final VoidCallback? onPreviewWebServer;
  final VoidCallback onClearSelection;
  final VoidCallback? onMoveSelection;
  final VoidCallback? onDeleteSelection;
  final VoidCallback? onDownloadSelection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackedActions =
            responsiveMode == PbFilesResponsiveMode.mobile ||
            responsiveMode == PbFilesResponsiveMode.overlay && constraints.maxWidth <= PbBreakpoints.shellMobile;
        final webServerTrailingAction = v17WebsiteActionsEnabled && showWebServerPreview
            ? PbFilesToolbarTrailingAction(
                label: 'Preview',
                iconAssetName: 'globe',
                onPressed: onPreviewWebServer,
                width: 134,
                backgroundColor: webServerPreviewActive ? PbColors.statusOnline : PbColors.dynamicSurfacePanelSoft,
                pressedBackgroundColor: webServerPreviewActive ? PbColors.statusOnline : PbColors.dynamicSurfacePanelSoft,
                borderColor: webServerPreviewActive ? PbColors.statusOnline : PbColors.borderSoft,
                pressedBorderColor: webServerPreviewActive ? PbColors.statusOnline : PbColors.borderSoft,
                foregroundColor: webServerPreviewActive ? PbColors.textInverse : PbColors.textMuted,
              )
            : v17WebsiteActionsEnabled && currentPath.isEmpty && onInstallWebServer != null
            ? PbFilesToolbarTrailingAction(label: 'New website', iconAssetName: 'folder-code', onPressed: onInstallWebServer, width: 164)
            : null;
        final resolvedTrailingAction = trailingAction ?? webServerTrailingAction;
        final availableWidth = math.max(0, constraints.maxWidth - padding.left - padding.right).toDouble();
        final actionLayout = _FilesToolbarActionLayout.resolve(
          maxWidth: availableWidth,
          stackedActions: stackedActions,
          trailingAction: resolvedTrailingAction,
        );
        final compactSelectionActions = constraints.maxWidth < 960 && !stackedActions;
        final createActions = _FilesCreateActions(
          combineCreateActions: actionLayout.combineCreateActions,
          iconOnlyActions: actionLayout.iconOnlyActions,
          fullWidth: stackedActions,
          onCreateFolder: onCreateFolder,
          onCreateTextFile: onCreateTextFile,
          onUpload: onUpload,
          onAskCurrentFolder: onAskCurrentFolder,
          showAskAgent: showAskAgent,
          trailingAction: resolvedTrailingAction,
        );
        final filterField = PbMenuFilterField(
          placeholder: 'Filter...',
          height: PbSizes.buttonTertiaryHeight,
          margin: EdgeInsets.zero,
          controller: filterController,
          enabled: filterEnabled,
          onChanged: onFilterChanged,
        );

        return Container(
          constraints: const BoxConstraints(minHeight: 66),
          padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 28),
          child: Transform.translate(
            offset: const Offset(0, -8),
            child: stackedActions
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasSelection)
                        _FilesSelectionActions(
                          selectedCount: selectedCount,
                          stretch: true,
                          showCount: false,
                          onDeleteSelection: onDeleteSelection,
                          onClearSelection: onClearSelection,
                          onMoveSelection: onMoveSelection,
                          onDownloadSelection: onDownloadSelection,
                        )
                      else
                        createActions,
                      const SizedBox(height: 10),
                      if (hasSelection) _FilesSelectionCountRow(selectedCount: selectedCount) else filterField,
                    ],
                  )
                : Row(
                    children: [
                      if (hasSelection)
                        _FilesSelectionActions(
                          selectedCount: selectedCount,
                          iconOnly: compactSelectionActions,
                          onDeleteSelection: onDeleteSelection,
                          onClearSelection: onClearSelection,
                          onMoveSelection: onMoveSelection,
                          onDownloadSelection: onDownloadSelection,
                        )
                      else
                        createActions,
                      const SizedBox(width: 10),
                      if (!hasSelection)
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 220, maxWidth: 320), child: filterField),
                          ),
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

enum _FilesToolbarAction { create, createFolder, createTextFile, upload, askAgent, trailing }

class _FilesToolbarActionLayout {
  const _FilesToolbarActionLayout({required this.combineCreateActions, required this.iconOnlyActions});

  static const _filterGap = 10.0;
  static const _minimumFilterWidth = 220.0;
  static const _actionGap = 10.0;
  static const _iconButtonWidth = 48.0;
  static const _fullWidths = <_FilesToolbarAction, double>{
    _FilesToolbarAction.create: 132,
    _FilesToolbarAction.createFolder: 148,
    _FilesToolbarAction.createTextFile: 164,
    _FilesToolbarAction.upload: 132,
    _FilesToolbarAction.askAgent: 148,
  };

  final bool combineCreateActions;
  final Set<_FilesToolbarAction> iconOnlyActions;

  static _FilesToolbarActionLayout resolve({
    required double maxWidth,
    required bool stackedActions,
    required PbFilesToolbarTrailingAction? trailingAction,
  }) {
    if (trailingAction == null) {
      return _FilesToolbarActionLayout(
        combineCreateActions: stackedActions,
        iconOnlyActions: !stackedActions && maxWidth < 620
            ? const <_FilesToolbarAction>{
                _FilesToolbarAction.createFolder,
                _FilesToolbarAction.createTextFile,
                _FilesToolbarAction.upload,
                _FilesToolbarAction.askAgent,
              }
            : const <_FilesToolbarAction>{},
      );
    }

    if (stackedActions) {
      return const _FilesToolbarActionLayout(combineCreateActions: true, iconOnlyActions: <_FilesToolbarAction>{});
    }

    const directActions = <_FilesToolbarAction>[
      _FilesToolbarAction.createFolder,
      _FilesToolbarAction.createTextFile,
      _FilesToolbarAction.upload,
      _FilesToolbarAction.askAgent,
      _FilesToolbarAction.trailing,
    ];
    if (_fits(maxWidth, directActions, const <_FilesToolbarAction>{}, trailingAction)) {
      return const _FilesToolbarActionLayout(combineCreateActions: false, iconOnlyActions: <_FilesToolbarAction>{});
    }

    const combinedActions = <_FilesToolbarAction>[
      _FilesToolbarAction.create,
      _FilesToolbarAction.upload,
      _FilesToolbarAction.askAgent,
      _FilesToolbarAction.trailing,
    ];
    final iconOnly = <_FilesToolbarAction>{};
    for (final action in const <_FilesToolbarAction>[
      _FilesToolbarAction.trailing,
      _FilesToolbarAction.askAgent,
      _FilesToolbarAction.upload,
      _FilesToolbarAction.create,
    ]) {
      if (_fits(maxWidth, combinedActions, iconOnly, trailingAction)) {
        break;
      }
      iconOnly.add(action);
    }

    return _FilesToolbarActionLayout(combineCreateActions: true, iconOnlyActions: Set.unmodifiable(iconOnly));
  }

  static bool _fits(
    double maxWidth,
    List<_FilesToolbarAction> actions,
    Set<_FilesToolbarAction> iconOnly,
    PbFilesToolbarTrailingAction trailingAction,
  ) {
    final actionWidth = actions.fold<double>(
      0,
      (sum, action) =>
          sum +
          (iconOnly.contains(action)
              ? _iconButtonWidth
              : action == _FilesToolbarAction.trailing
              ? trailingAction.width
              : _fullWidths[action]!),
    );
    final actionGaps = math.max(0, actions.length - 1) * _actionGap;
    return actionWidth + actionGaps + _filterGap + _minimumFilterWidth <= maxWidth;
  }
}

class _FilesCrumb {
  const _FilesCrumb({required this.label, required this.path});

  final String label;
  final String path;
}

double _menuWidthForLabels(
  BuildContext context,
  Iterable<String> labels, {
  double min = 220,
  double max = 420,
  TextStyle? style,
  double chrome = 96,
}) {
  final textStyle = style ?? PowerboardsTypography.labelSmall;
  final textDirection = Directionality.of(context);
  final longest = labels.fold<double>(0, (width, label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      maxLines: 1,
      textDirection: textDirection,
    )..layout();

    return math.max(width, painter.width);
  });

  return (longest + chrome).clamp(min, max).toDouble();
}

class _FilesBreadcrumb extends StatefulWidget {
  const _FilesBreadcrumb({required this.crumbs, required this.onPressed});

  final List<_FilesCrumb> crumbs;
  final ValueChanged<String> onPressed;

  @override
  State<_FilesBreadcrumb> createState() => _FilesBreadcrumbState();
}

class _FilesBreadcrumbState extends State<_FilesBreadcrumb> {
  static const _layoutSlack = 2.0;
  static const _overflowButtonWidth = 40.0;
  static const _overflowButtonHeight = 28.0;

  bool _overflowOpen = false;

  void _closeOverflow() {
    if (_overflowOpen) {
      setState(() => _overflowOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crumbs = widget.crumbs;
        final current = crumbs.last;
        final layout = _resolveLayout(context, constraints.maxWidth, crumbs);

        return Row(
          children: [
            if (layout.hidden.isNotEmpty) ...[
              _FilesBreadcrumbOverflowButton(
                width: _overflowButtonWidth,
                height: _overflowButtonHeight,
                crumbs: layout.hidden,
                open: _overflowOpen,
                onOpenChanged: (open) => setState(() => _overflowOpen = open),
                onPressed: (path) {
                  _closeOverflow();
                  widget.onPressed(path);
                },
              ),
              const _FilesBreadcrumbSeparator(),
            ],
            for (final crumb in layout.visibleAncestors) ...[
              _FilesBreadcrumbButton(crumb: crumb, current: false, onPressed: widget.onPressed),
              const _FilesBreadcrumbSeparator(),
            ],
            Flexible(
              child: _FilesBreadcrumbButton(crumb: current, current: true, onPressed: widget.onPressed),
            ),
          ],
        );
      },
    );
  }

  _FilesBreadcrumbLayout _resolveLayout(BuildContext context, double availableWidth, List<_FilesCrumb> crumbs) {
    if (crumbs.length <= 1 || availableWidth <= 0) {
      return const _FilesBreadcrumbLayout();
    }

    final current = crumbs.last;
    final visibleAncestors = crumbs.take(crumbs.length - 1).toList();
    if (_breadcrumbWidth(context, current: current, visibleAncestors: visibleAncestors, hiddenAncestors: const []) <= availableWidth) {
      return _FilesBreadcrumbLayout(visibleAncestors: visibleAncestors);
    }

    final hidden = <_FilesCrumb>[];
    while (visibleAncestors.isNotEmpty &&
        _breadcrumbWidth(context, current: current, visibleAncestors: visibleAncestors, hiddenAncestors: hidden) > availableWidth) {
      hidden.add(visibleAncestors.removeAt(0));
    }

    return _FilesBreadcrumbLayout(hidden: hidden, visibleAncestors: visibleAncestors);
  }

  double _breadcrumbWidth(
    BuildContext context, {
    required _FilesCrumb current,
    required List<_FilesCrumb> visibleAncestors,
    required List<_FilesCrumb> hiddenAncestors,
  }) {
    final separatorWidth = (visibleAncestors.length + (hiddenAncestors.isEmpty ? 0 : 1)) * 34;
    final overflowWidth = hiddenAncestors.isEmpty ? 0.0 : _overflowButtonWidth;
    final visibleWidth = visibleAncestors.fold<double>(0, (width, crumb) => width + _measureBreadcrumbLabel(context, crumb.label));

    return overflowWidth + separatorWidth + visibleWidth + _measureBreadcrumbLabel(context, current.label);
  }

  double _measureBreadcrumbLabel(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: PowerboardsTypography.h2),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();

    return painter.width.ceilToDouble() + _layoutSlack;
  }
}

class _FilesBreadcrumbLayout {
  const _FilesBreadcrumbLayout({this.hidden = const [], this.visibleAncestors = const []});

  final List<_FilesCrumb> hidden;
  final List<_FilesCrumb> visibleAncestors;
}

class _FilesBreadcrumbOverflowButton extends StatelessWidget {
  const _FilesBreadcrumbOverflowButton({
    required this.width,
    required this.height,
    required this.crumbs,
    required this.open,
    required this.onOpenChanged,
    required this.onPressed,
  });

  final double width;
  final double height;
  final List<_FilesCrumb> crumbs;
  final bool open;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<String> onPressed;

  @override
  Widget build(BuildContext context) {
    final menuWidth = _menuWidthForLabels(context, crumbs.map((crumb) => crumb.label), min: 220, max: 420);

    return PbMenuAnchor(
      placement: PbMenuAnchorPlacement.bottomLeft,
      gap: 6,
      triggerHeight: height,
      onDismiss: () => onOpenChanged(false),
      panel: open
          ? PbMenuCard(
              width: menuWidth,
              child: PbMenuList(
                children: [
                  for (final crumb in crumbs.reversed)
                    PbMenuOption(
                      title: crumb.label,
                      leadingIconAssetName: 'folder',
                      singleLine: true,
                      onPressed: () => onPressed(crumb.path),
                    ),
                ],
              ),
            )
          : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onOpenChanged(!open),
          child: SizedBox(
            width: width,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: open ? PbColors.dynamicSurfaceAccentSoft : PbColors.dynamicSurfacePanel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: open ? PbColors.dynamicBorderStateSelected : PbColors.borderSoft),
              ),
              child: const Center(
                child: PbSvgIcon(assetName: 'ellipsis', size: 18, color: PbColors.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilesBreadcrumbButton extends StatelessWidget {
  const _FilesBreadcrumbButton({required this.crumb, required this.current, required this.onPressed});

  final _FilesCrumb crumb;
  final bool current;
  final ValueChanged<String> onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: current ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: current ? null : () => onPressed(crumb.path),
        child: Text(
          crumb.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: PowerboardsTypography.h2.copyWith(color: current ? PbColors.textPrimary : PbColors.textMuted),
        ),
      ),
    );
  }
}

class _FilesBreadcrumbSeparator extends StatelessWidget {
  const _FilesBreadcrumbSeparator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 34,
      child: Center(
        child: PbSvgIcon(assetName: 'chevron-right', size: 18, color: PbColors.textSubtle),
      ),
    );
  }
}

class _FilesCreateActions extends StatefulWidget {
  const _FilesCreateActions({
    required this.combineCreateActions,
    required this.iconOnlyActions,
    required this.fullWidth,
    required this.onCreateFolder,
    required this.onCreateTextFile,
    required this.onUpload,
    this.onAskCurrentFolder,
    this.showAskAgent = true,
    this.trailingAction,
  });

  final bool combineCreateActions;
  final Set<_FilesToolbarAction> iconOnlyActions;
  final bool fullWidth;
  final VoidCallback? onCreateFolder;
  final VoidCallback? onCreateTextFile;
  final VoidCallback? onUpload;
  final VoidCallback? onAskCurrentFolder;
  final bool showAskAgent;
  final PbFilesToolbarTrailingAction? trailingAction;

  @override
  State<_FilesCreateActions> createState() => _FilesCreateActionsState();
}

class _FilesCreateActionsState extends State<_FilesCreateActions> {
  bool _createOpen = false;

  bool _iconOnly(_FilesToolbarAction action) {
    return widget.iconOnlyActions.contains(action);
  }

  void _closeCreateMenu() {
    if (_createOpen) {
      setState(() => _createOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.combineCreateActions) {
      final createFolderIconOnly = _iconOnly(_FilesToolbarAction.createFolder);
      final createTextFileIconOnly = _iconOnly(_FilesToolbarAction.createTextFile);
      final uploadIconOnly = _iconOnly(_FilesToolbarAction.upload);
      final askAgentIconOnly = _iconOnly(_FilesToolbarAction.askAgent);
      final trailingAction = widget.trailingAction;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilesToolbarButton(
            label: 'New folder',
            iconAssetName: 'folder-plus',
            iconOnly: createFolderIconOnly,
            width: createFolderIconOnly ? 48 : 148,
            contentOffset: createFolderIconOnly ? Offset.zero : const Offset(-2, 0),
            onPressed: widget.onCreateFolder,
          ),
          const SizedBox(width: 10),
          _FilesToolbarButton(
            label: 'New text file',
            iconAssetName: 'file-plus-corner',
            iconOnly: createTextFileIconOnly,
            width: createTextFileIconOnly ? 48 : 164,
            contentOffset: createTextFileIconOnly ? Offset.zero : const Offset(-2, 0),
            onPressed: widget.onCreateTextFile,
          ),
          const SizedBox(width: 10),
          _FilesToolbarButton(
            label: 'Upload',
            iconAssetName: 'arrow-up-from-line',
            iconOnly: uploadIconOnly,
            width: uploadIconOnly ? 48 : 132,
            onPressed: widget.onUpload,
          ),
          const SizedBox(width: 10),
          if (widget.showAskAgent)
            _FilesToolbarButton(
              label: 'Ask agent',
              iconAssetName: 'message-square-plus',
              iconOnly: askAgentIconOnly,
              width: askAgentIconOnly ? 48 : 148,
              onPressed: widget.onAskCurrentFolder,
            ),
          if (trailingAction != null) ...[const SizedBox(width: 10), _buildTrailingAction(trailingAction, fullWidth: false)],
        ],
      );
    }

    final createIconOnly = _iconOnly(_FilesToolbarAction.create);

    final createButton = PbMenuAnchor(
      placement: PbMenuAnchorPlacement.bottomLeft,
      gap: 6,
      triggerHeight: PbSizes.buttonTertiaryHeight,
      onDismiss: _closeCreateMenu,
      panel: _createOpen
          ? PbMenuCard(
              width: 220,
              child: PbMenuList(
                children: [
                  PbMenuOption(
                    title: 'New folder',
                    leadingIconAssetName: 'folder-plus',
                    singleLine: true,
                    onPressed: widget.onCreateFolder == null
                        ? null
                        : () {
                            _closeCreateMenu();
                            widget.onCreateFolder?.call();
                          },
                  ),
                  PbMenuOption(
                    title: 'New text file',
                    leadingIconAssetName: 'file-plus-corner',
                    singleLine: true,
                    onPressed: widget.onCreateTextFile == null
                        ? null
                        : () {
                            _closeCreateMenu();
                            widget.onCreateTextFile?.call();
                          },
                  ),
                ],
              ),
            )
          : null,
      child: _FilesToolbarButton(
        label: 'Create',
        iconAssetName: 'plus',
        iconOnly: createIconOnly,
        fullWidth: widget.fullWidth,
        width: widget.fullWidth ? null : (createIconOnly ? 48 : 132),
        contentOffset: createIconOnly ? Offset.zero : const Offset(-3, 0),
        selected: _createOpen,
        onPressed: () => setState(() => _createOpen = !_createOpen),
      ),
    );
    final uploadIconOnly = _iconOnly(_FilesToolbarAction.upload);
    final uploadButton = _FilesToolbarButton(
      label: 'Upload',
      iconAssetName: 'arrow-up-from-line',
      iconOnly: uploadIconOnly,
      fullWidth: widget.fullWidth,
      width: widget.fullWidth ? null : (uploadIconOnly ? 48 : 132),
      onPressed: widget.onUpload,
    );
    final askAgentIconOnly = _iconOnly(_FilesToolbarAction.askAgent);
    final askAgentButton = _FilesToolbarButton(
      label: 'Ask agent',
      iconAssetName: 'message-square-plus',
      iconOnly: askAgentIconOnly,
      fullWidth: widget.fullWidth,
      width: widget.fullWidth ? null : (askAgentIconOnly ? 48 : 148),
      onPressed: widget.onAskCurrentFolder,
    );

    final buttons = <Widget>[
      createButton,
      uploadButton,
      if (widget.showAskAgent) askAgentButton,
      if (widget.trailingAction case final trailingAction?) _buildTrailingAction(trailingAction, fullWidth: widget.fullWidth),
    ];

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        for (var index = 0; index < buttons.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          if (widget.fullWidth) Expanded(child: buttons[index]) else buttons[index],
        ],
      ],
    );
  }

  Widget _buildTrailingAction(PbFilesToolbarTrailingAction action, {required bool fullWidth}) {
    final iconOnly = _iconOnly(_FilesToolbarAction.trailing);
    return _FilesToolbarButton(
      label: action.label,
      iconAssetName: action.iconAssetName,
      iconOnly: iconOnly,
      fullWidth: fullWidth,
      width: fullWidth ? null : (iconOnly ? 48 : action.width),
      backgroundColor: action.backgroundColor,
      pressedBackgroundColor: action.pressedBackgroundColor,
      borderColor: action.borderColor,
      pressedBorderColor: action.pressedBorderColor,
      foregroundColor: action.foregroundColor,
      onPressed: action.onPressed,
    );
  }
}

class _FilesSelectionActions extends StatelessWidget {
  const _FilesSelectionActions({
    required this.selectedCount,
    required this.onDeleteSelection,
    required this.onClearSelection,
    this.onMoveSelection,
    required this.onDownloadSelection,
    this.stretch = false,
    this.showCount = true,
    this.iconOnly = false,
  });

  final int selectedCount;
  final VoidCallback? onDeleteSelection;
  final VoidCallback onClearSelection;
  final VoidCallback? onMoveSelection;
  final VoidCallback? onDownloadSelection;
  final bool stretch;
  final bool showCount;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final deleteButton = _FilesToolbarButton(
      label: 'Delete',
      iconAssetName: 'trash-2',
      alert: true,
      fullWidth: stretch,
      onPressed: onDeleteSelection,
    );
    final deselectButton = _FilesToolbarButton(
      label: 'Deselect',
      iconAssetName: 'circle-x',
      iconOnly: iconOnly,
      fullWidth: stretch,
      width: iconOnly ? 48 : null,
      onPressed: onClearSelection,
    );
    final downloadButton = _FilesToolbarButton(
      label: 'Download',
      iconAssetName: 'arrow-down-to-line',
      iconOnly: iconOnly,
      fullWidth: stretch,
      width: iconOnly ? 48 : null,
      onPressed: onDownloadSelection,
    );
    final moveButton = _FilesToolbarButton(
      label: 'Move to',
      iconAssetName: 'folder-symlink',
      iconOnly: iconOnly,
      fullWidth: stretch,
      width: iconOnly ? 48 : null,
      onPressed: onMoveSelection,
    );
    final buttons = Row(
      mainAxisSize: stretch ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (stretch) Expanded(child: deselectButton) else deselectButton,
        if (onMoveSelection != null) ...[const SizedBox(width: 10), if (stretch) Expanded(child: moveButton) else moveButton],
        const SizedBox(width: 10),
        if (stretch) Expanded(child: downloadButton) else downloadButton,
        const SizedBox(width: 10),
        if (stretch) Expanded(child: deleteButton) else deleteButton,
        if (showCount) ...[const SizedBox(width: 18), Flexible(child: _FilesSelectionCountText(selectedCount: selectedCount))],
      ],
    );

    return stretch ? buttons : Flexible(child: buttons);
  }
}

class _FilesSelectionCountRow extends StatelessWidget {
  const _FilesSelectionCountRow({required this.selectedCount});

  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PbSizes.buttonTertiaryHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: _FilesSelectionCountText(selectedCount: selectedCount),
      ),
    );
  }
}

class _FilesSelectionCountText extends StatelessWidget {
  const _FilesSelectionCountText({required this.selectedCount});

  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$selectedCount selected',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: PowerboardsTypography.smallStrong.copyWith(color: PbColors.textPrimary),
    );
  }
}

class _FilesToolbarButton extends StatefulWidget {
  const _FilesToolbarButton({
    required this.label,
    this.iconAssetName,
    this.iconOnly = false,
    this.fullWidth = false,
    this.width,
    this.contentOffset = Offset.zero,
    this.alert = false,
    this.selected = false,
    this.backgroundColor,
    this.pressedBackgroundColor,
    this.borderColor,
    this.pressedBorderColor,
    this.foregroundColor,
    this.onPressed,
  });

  final String label;
  final String? iconAssetName;
  final bool iconOnly;
  final bool fullWidth;
  final double? width;
  final Offset contentOffset;
  final bool alert;
  final bool selected;
  final Color? backgroundColor;
  final Color? pressedBackgroundColor;
  final Color? borderColor;
  final Color? pressedBorderColor;
  final Color? foregroundColor;
  final VoidCallback? onPressed;

  @override
  State<_FilesToolbarButton> createState() => _FilesToolbarButtonState();
}

class _FilesToolbarButtonState extends State<_FilesToolbarButton> {
  @override
  Widget build(BuildContext context) {
    if (widget.alert) {
      return _FilesAlertToolbarButton(
        label: widget.label,
        iconAssetName: widget.iconAssetName,
        fullWidth: widget.fullWidth,
        onPressed: widget.onPressed,
      );
    }

    final button = PbButton(
      iconAssetName: widget.iconAssetName,
      label: widget.label,
      variant: PbButtonVariant.primary,
      iconOnly: widget.iconOnly,
      iconOnlySize: PbSizes.buttonTertiaryHeight,
      height: widget.fullWidth ? 44 : PbSizes.buttonTertiaryHeight,
      horizontalPadding: widget.fullWidth ? 14 : 16,
      iconSize: 18,
      iconGap: 8,
      contentOffset: widget.contentOffset,
      backgroundColor: widget.backgroundColor,
      pressedBackgroundColor: widget.pressedBackgroundColor,
      borderColor: widget.borderColor,
      pressedBorderColor: widget.pressedBorderColor,
      foregroundColor: widget.foregroundColor,
      onPressed: widget.onPressed,
    );

    final sizedButton = SizedBox(width: widget.width, child: button);
    if (!widget.iconOnly) {
      return sizedButton;
    }

    return Tooltip(message: widget.label, child: sizedButton);
  }
}

class _FilesAlertToolbarButton extends StatefulWidget {
  const _FilesAlertToolbarButton({required this.label, this.iconAssetName, this.fullWidth = false, this.onPressed});

  final String label;
  final String? iconAssetName;
  final bool fullWidth;
  final VoidCallback? onPressed;

  @override
  State<_FilesAlertToolbarButton> createState() => _FilesAlertToolbarButtonState();
}

class _FilesAlertToolbarButtonState extends State<_FilesAlertToolbarButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _pressed;
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
        child: Transform.translate(
          offset: Offset(0, active && !_pressed ? -1 : 0),
          child: AnimatedContainer(
            duration: PbMotion.state,
            height: widget.fullWidth ? 44 : PbSizes.buttonTertiaryHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: PbColors.customRose,
              borderRadius: BorderRadius.circular(PbRadii.small),
              border: Border.all(color: PbColors.customRose),
              boxShadow: _pressed
                  ? PbShadows.statePressedInset
                  : active
                  ? PbShadows.stateHover
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.iconAssetName != null) PbSvgIcon(assetName: widget.iconAssetName!, size: 18, color: PbColors.textInverse),
                if (widget.iconAssetName != null) const SizedBox(width: 8),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PowerboardsTypography.button.copyWith(color: PbColors.textInverse),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
