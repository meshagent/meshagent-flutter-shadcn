import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_tokens.dart';
import '../../theme/pb_typography.dart';
import '../menus/pb_menu_anchor.dart';
import '../menus/pb_menu_card.dart';
import '../menus/pb_menu_list.dart';
import '../menus/pb_menu_option.dart';
import '../menus/pb_sidepane_item_menu.dart';
import '../primitives/pb_empty_state.dart';
import '../primitives/pb_spinning_icon.dart';
import '../primitives/pb_svg_icon.dart';
import 'pb_archive_extract.dart';
import 'pb_file_menus.dart';
import 'pb_files_data.dart';
import 'pb_files_layout_values.dart';

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

class PbFilesTable extends StatefulWidget {
  const PbFilesTable({
    super.key,
    required this.padding,
    required this.items,
    required this.selectedIds,
    required this.sortKey,
    required this.sortDirectionDescending,
    required this.previewFileId,
    required this.keyboardPreviewFileId,
    required this.keyboardPreviewDirection,
    this.savingIds = const {},
    this.extractingArchiveIds = const <String>{},
    required this.hasActiveFilter,
    required this.onSortChanged,
    required this.onToggleSelection,
    required this.onToggleVisibleSelection,
    required this.onItemPressed,
    required this.onBrowseFolder,
    required this.onRemoveProcessingRow,
    required this.onLinkedThreadPressed,
    this.onAskAgent,
    this.onShare,
    this.onExtract,
    this.onDownload,
    this.onMoveTo,
    this.onRename,
    this.onDelete,
  });

  final PbFilesPanelPadding padding;
  final List<PbFilesItemData> items;
  final Set<String> selectedIds;
  final PbFilesSortKey sortKey;
  final bool sortDirectionDescending;
  final String? previewFileId;
  final String? keyboardPreviewFileId;
  final int keyboardPreviewDirection;
  final Set<String> savingIds;
  final Set<String> extractingArchiveIds;
  final bool hasActiveFilter;
  final ValueChanged<PbFilesSortKey> onSortChanged;
  final ValueChanged<String> onToggleSelection;
  final VoidCallback onToggleVisibleSelection;
  final ValueChanged<PbFilesItemData> onItemPressed;
  final ValueChanged<PbFilesItemData> onBrowseFolder;
  final ValueChanged<PbFilesItemData> onRemoveProcessingRow;
  final PbFilesLinkedThreadHandler onLinkedThreadPressed;
  final ValueChanged<PbFilesItemData>? onAskAgent;
  final ValueChanged<PbFilesItemData>? onShare;
  final ValueChanged<PbFilesItemData>? onExtract;
  final ValueChanged<PbFilesItemData>? onDownload;
  final ValueChanged<PbFilesItemData>? onMoveTo;
  final ValueChanged<PbFilesItemData>? onRename;
  final ValueChanged<PbFilesItemData>? onDelete;

  @override
  State<PbFilesTable> createState() => _FilesTableState();
}

class _FilesTableState extends State<PbFilesTable> {
  String? _hoveredRowId;
  String? _menuOpenRowId;
  bool _suppressHoverUntilPointerMove = false;

  bool _isSelectableRow(PbFilesItemData item) {
    return item.kind == PbFilesItemKind.file || item.kind == PbFilesItemKind.folder;
  }

  @override
  void didUpdateWidget(covariant PbFilesTable oldWidget) {
    super.didUpdateWidget(oldWidget);

    final keyboardPreviewChanged =
        widget.keyboardPreviewFileId != null &&
        (widget.keyboardPreviewFileId != oldWidget.keyboardPreviewFileId ||
            widget.keyboardPreviewDirection != oldWidget.keyboardPreviewDirection);

    if (keyboardPreviewChanged) {
      _suppressHoverUntilPointerMove = true;
      _hoveredRowId = null;
    } else if (widget.keyboardPreviewFileId == null && oldWidget.keyboardPreviewFileId != null) {
      _suppressHoverUntilPointerMove = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectableItems = widget.items.where(_isSelectableRow).toList(growable: false);
    final allSelected = selectableItems.isNotEmpty && selectableItems.every((item) => widget.selectedIds.contains(item.id));
    final partiallySelected = !allSelected && selectableItems.any((item) => widget.selectedIds.contains(item.id));

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(0.0, constraints.maxWidth - widget.padding.left - widget.padding.right);
        final contentPadding = EdgeInsets.only(left: widget.padding.left, right: widget.padding.right);
        final columns = _FilesTableColumns.resolve(contentWidth);
        final hasItems = widget.items.isNotEmpty;
        final header = hasItems
            ? _FilesTableHeader(
                columns: columns,
                allSelected: allSelected,
                partiallySelected: partiallySelected,
                sortKey: widget.sortKey,
                sortDirectionDescending: widget.sortDirectionDescending,
                onSortChanged: widget.onSortChanged,
                onToggleVisibleSelection: widget.onToggleVisibleSelection,
              )
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) Padding(padding: contentPadding, child: header),
            Expanded(
              child: !hasItems
                  ? Padding(
                      padding: contentPadding,
                      child: _FilesEmptyState(noResults: widget.hasActiveFilter),
                    )
                  : ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 30),
                        clipBehavior: Clip.hardEdge,
                        itemCount: widget.items.length,
                        itemBuilder: (context, index) {
                          final item = widget.items[index];
                          final selectable = _isSelectableRow(item);
                          final selected = selectable && widget.selectedIds.contains(item.id);
                          final previousSelected =
                              index > 0 &&
                              _isSelectableRow(widget.items[index - 1]) &&
                              widget.selectedIds.contains(widget.items[index - 1].id);
                          final nextSelected =
                              index < widget.items.length - 1 &&
                              _isSelectableRow(widget.items[index + 1]) &&
                              widget.selectedIds.contains(widget.items[index + 1].id);
                          final nextStateful = index < widget.items.length - 1 && _isStatefulRow(widget.items[index + 1]);
                          final extractDisabled = widget.extractingArchiveIds.contains(item.id);
                          final showExtract = widget.onExtract != null && pbCanExtractArchive(item.toAttachmentData());

                          return Padding(
                            padding: contentPadding,
                            child: _PbFilesTableRow(
                              item: item,
                              columns: columns,
                              selected: selected,
                              selectionMode: widget.selectedIds.isNotEmpty,
                              active: item.id == widget.previewFileId,
                              keyboardFocused: item.id == widget.keyboardPreviewFileId,
                              keyboardPreviewDirection: widget.keyboardPreviewDirection,
                              saving: widget.savingIds.contains(item.id),
                              hoverSuppressed: _suppressHoverUntilPointerMove,
                              previousSelected: previousSelected,
                              nextSelected: nextSelected,
                              beforeStateRow: nextStateful,
                              last: index == widget.items.length - 1,
                              showExtract: showExtract,
                              extractDisabled: extractDisabled,
                              onPressed: () => widget.onItemPressed(item),
                              onToggleSelection: selectable ? () => widget.onToggleSelection(item.id) : () {},
                              onBrowseFolder: () => widget.onBrowseFolder(item),
                              onRemoveProcessingRow: () => widget.onRemoveProcessingRow(item),
                              onLinkedThreadPressed: (thread) => widget.onLinkedThreadPressed(item, thread),
                              onAskAgent: widget.onAskAgent == null ? null : () => widget.onAskAgent!(item),
                              onShare: widget.onShare == null ? null : () => widget.onShare!(item),
                              onExtract: widget.onExtract == null || extractDisabled ? null : () => widget.onExtract!(item),
                              onDownload: widget.onDownload == null ? null : () => widget.onDownload!(item),
                              onMoveTo: widget.onMoveTo == null ? null : () => widget.onMoveTo!(item),
                              onRename: widget.onRename == null ? null : () => widget.onRename!(item),
                              onDelete: widget.onDelete == null ? null : () => widget.onDelete!(item),
                              onHoverChanged: (hovered) => setState(() {
                                if (hovered) {
                                  _hoveredRowId = item.id;
                                } else if (_hoveredRowId == item.id) {
                                  _hoveredRowId = null;
                                }
                              }),
                              onHoverResumed: () => setState(() {
                                _suppressHoverUntilPointerMove = false;
                                if (widget.selectedIds.isEmpty) {
                                  _hoveredRowId = item.id;
                                }
                              }),
                              onMenuOpenChanged: (open) => setState(() {
                                if (open) {
                                  _menuOpenRowId = item.id;
                                } else if (_menuOpenRowId == item.id) {
                                  _menuOpenRowId = null;
                                }
                              }),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  bool _isStatefulRow(PbFilesItemData item) {
    return widget.selectedIds.contains(item.id) || item.id == widget.previewFileId || item.id == _hoveredRowId || item.id == _menuOpenRowId;
  }
}

class _FilesTableColumns {
  const _FilesTableColumns({
    required this.showType,
    required this.showSize,
    required this.showThread,
    required this.showCreator,
    required this.showCreatorName,
    required this.responsiveSort,
    required this.compact,
    required this.gap,
    required this.nameWidth,
    required this.typeWidth,
    required this.threadWidth,
    required this.creatorWidth,
    required this.sizeWidth,
    required this.updatedWidth,
  });

  static const selectWidth = 28.0;
  static const optionsWidth = 32.0;

  final bool showType;
  final bool showSize;
  final bool showThread;
  final bool showCreator;
  final bool showCreatorName;
  final bool responsiveSort;
  final bool compact;
  final double gap;
  final double nameWidth;
  final double typeWidth;
  final double threadWidth;
  final double creatorWidth;
  final double sizeWidth;
  final double updatedWidth;

  static _FilesTableColumns resolve(double width) {
    final compact = width <= 560;
    final gap = compact ? 12.0 : (width <= 720 ? 14.0 : 20.0);
    final horizontalPadding = compact ? 8.0 : 10.0;
    final innerWidth = math.max(0.0, width - 2 - (horizontalPadding * 2));
    final showType = width > 1180;
    final showSize = width > 720;
    const showThread = false;
    const showCreator = false;
    const showCreatorName = false;
    final responsiveSort = width <= 720;
    final widths = _resolveWidths(width: width, innerWidth: innerWidth, gap: gap);

    return _FilesTableColumns(
      showType: showType,
      showSize: showSize,
      showThread: showThread,
      showCreator: showCreator,
      showCreatorName: showCreatorName,
      responsiveSort: responsiveSort,
      compact: compact,
      gap: gap,
      nameWidth: widths.name,
      typeWidth: widths.type,
      threadWidth: 0,
      creatorWidth: 0,
      sizeWidth: widths.size,
      updatedWidth: widths.updated,
    );
  }

  static _FilesTableTrackWidths _resolveWidths({required double width, required double innerWidth, required double gap}) {
    if (width > 1180) {
      final trackWidths = _resolveFlexibleTracks(innerWidth - selectWidth - optionsWidth - (gap * 5), const [
        _FilesTableFlexTrack(min: 240, flex: 3.875),
        _FilesTableFlexTrack(min: 132, flex: 1.75),
        _FilesTableFlexTrack(min: 96, flex: 0.875),
        _FilesTableFlexTrack(min: 128, flex: 0.875),
      ]);

      return _FilesTableTrackWidths(name: trackWidths[0], type: trackWidths[1], size: trackWidths[2], updated: trackWidths[3]);
    }

    if (width > 720) {
      const size = 104.0;
      const updated = 128.0;
      return _FilesTableTrackWidths(
        name: _remainingName(innerWidth, min: 180, fixed: selectWidth + size + updated + optionsWidth, gaps: gap * 4),
        size: size,
        updated: updated,
      );
    }

    if (width > 560) {
      const updated = 148.0;
      return _FilesTableTrackWidths(
        name: _remainingName(innerWidth, min: 150, fixed: selectWidth + updated + optionsWidth, gaps: gap * 3),
        updated: updated,
      );
    }

    const updated = 96.0;
    return _FilesTableTrackWidths(
      name: _remainingName(innerWidth, min: 112, fixed: selectWidth + updated + optionsWidth, gaps: gap * 3),
      updated: updated,
    );
  }

  static double _remainingName(double innerWidth, {required double min, required double fixed, required double gaps}) {
    return math.max(min, innerWidth - fixed - gaps);
  }

  static List<double> _resolveFlexibleTracks(double available, List<_FilesTableFlexTrack> tracks) {
    final frozen = List<bool>.filled(tracks.length, false);

    while (true) {
      final frozenWidth = _sumFrozenWidths(tracks, frozen);
      final flexTotal = _sumUnfrozenFlex(tracks, frozen);
      if (flexTotal <= 0) {
        return [for (var index = 0; index < tracks.length; index++) tracks[index].min];
      }

      final flexUnit = math.max(0.0, available - frozenWidth) / flexTotal;
      var changed = false;

      for (var index = 0; index < tracks.length; index++) {
        if (!frozen[index] && tracks[index].flex * flexUnit < tracks[index].min) {
          frozen[index] = true;
          changed = true;
        }
      }

      if (!changed) {
        return [for (var index = 0; index < tracks.length; index++) frozen[index] ? tracks[index].min : tracks[index].flex * flexUnit];
      }
    }
  }

  static double _sumFrozenWidths(List<_FilesTableFlexTrack> tracks, List<bool> frozen) {
    var total = 0.0;
    for (var index = 0; index < tracks.length; index++) {
      if (frozen[index]) {
        total += tracks[index].min;
      }
    }
    return total;
  }

  static double _sumUnfrozenFlex(List<_FilesTableFlexTrack> tracks, List<bool> frozen) {
    var total = 0.0;
    for (var index = 0; index < tracks.length; index++) {
      if (!frozen[index]) {
        total += tracks[index].flex;
      }
    }
    return total;
  }
}

class _FilesTableFlexTrack {
  const _FilesTableFlexTrack({required this.min, required this.flex});

  final double min;
  final double flex;
}

class _FilesTableTrackWidths {
  const _FilesTableTrackWidths({required this.name, this.type = 0, this.size = 0, required this.updated});

  final double name;
  final double type;
  final double size;
  final double updated;
}

class _FilesTableHeader extends StatelessWidget {
  const _FilesTableHeader({
    required this.columns,
    required this.allSelected,
    required this.partiallySelected,
    required this.sortKey,
    required this.sortDirectionDescending,
    required this.onSortChanged,
    required this.onToggleVisibleSelection,
  });

  final _FilesTableColumns columns;
  final bool allSelected;
  final bool partiallySelected;
  final PbFilesSortKey sortKey;
  final bool sortDirectionDescending;
  final ValueChanged<PbFilesSortKey> onSortChanged;
  final VoidCallback onToggleVisibleSelection;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: Colors.transparent),
      ),
      padding: EdgeInsets.symmetric(horizontal: columns.compact ? 8 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _FilesTableColumns.selectWidth,
            child: Center(
              child: _FilesCheckbox(
                checked: allSelected,
                mixed: partiallySelected,
                compactHitArea: true,
                onPressed: onToggleVisibleSelection,
              ),
            ),
          ),
          SizedBox(width: columns.gap),
          SizedBox(
            width: columns.nameWidth,
            child: _FilesSortButton(
              label: 'Name',
              sortKey: PbFilesSortKey.name,
              activeKey: sortKey,
              descending: sortDirectionDescending,
              onPressed: onSortChanged,
            ),
          ),
          if (columns.showType) ...[
            SizedBox(width: columns.gap),
            SizedBox(
              width: columns.typeWidth,
              child: _FilesSortButton(
                label: 'Type',
                sortKey: PbFilesSortKey.type,
                activeKey: sortKey,
                descending: sortDirectionDescending,
                onPressed: onSortChanged,
              ),
            ),
          ],
          if (columns.showSize) ...[
            SizedBox(width: columns.gap),
            SizedBox(
              width: columns.sizeWidth,
              child: _FilesSortButton(
                label: 'Size',
                sortKey: PbFilesSortKey.size,
                activeKey: sortKey,
                descending: sortDirectionDescending,
                onPressed: onSortChanged,
              ),
            ),
          ],
          if (columns.showThread) ...[
            SizedBox(width: columns.gap),
            SizedBox(
              width: columns.threadWidth,
              child: _FilesSortButton(
                label: 'Linked thread',
                sortKey: PbFilesSortKey.thread,
                activeKey: sortKey,
                descending: sortDirectionDescending,
                onPressed: onSortChanged,
              ),
            ),
          ],
          if (columns.showCreator) ...[
            SizedBox(width: columns.gap),
            SizedBox(
              width: columns.creatorWidth,
              child: _FilesSortButton(
                label: 'Created by',
                sortKey: PbFilesSortKey.creator,
                activeKey: sortKey,
                descending: sortDirectionDescending,
                onPressed: onSortChanged,
                iconOnlyLabel: !columns.showCreatorName,
              ),
            ),
          ],
          SizedBox(width: columns.gap),
          SizedBox(
            width: columns.updatedWidth,
            child: columns.responsiveSort
                ? _FilesResponsiveSortButton(sortKey: sortKey, descending: sortDirectionDescending, onPressed: onSortChanged)
                : _FilesSortButton(
                    label: 'Last updated',
                    sortKey: PbFilesSortKey.updated,
                    activeKey: sortKey,
                    descending: sortDirectionDescending,
                    onPressed: onSortChanged,
                  ),
          ),
          SizedBox(width: columns.gap),
          const SizedBox(width: _FilesTableColumns.optionsWidth),
        ],
      ),
    );
  }
}

class _FilesSortButton extends StatelessWidget {
  const _FilesSortButton({
    required this.label,
    required this.sortKey,
    required this.activeKey,
    required this.descending,
    required this.onPressed,
    this.iconOnlyLabel = false,
  });

  final String label;
  final PbFilesSortKey sortKey;
  final PbFilesSortKey activeKey;
  final bool descending;
  final ValueChanged<PbFilesSortKey> onPressed;
  final bool iconOnlyLabel;

  @override
  Widget build(BuildContext context) {
    final active = sortKey == activeKey;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onPressed(sortKey),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!iconOnlyLabel)
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PowerboardsTypography.smallStrong.copyWith(
                    color: active ? PbColors.textBody : PbColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (!iconOnlyLabel) const SizedBox(width: 6),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: active ? 1 : 0,
              child: AnimatedRotation(
                turns: active && !descending ? 0.5 : 0,
                duration: const Duration(milliseconds: 140),
                child: const PbSvgIcon(assetName: 'chevron-down', size: 14, color: PbColors.textBody),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilesResponsiveSortButton extends StatefulWidget {
  const _FilesResponsiveSortButton({required this.sortKey, required this.descending, required this.onPressed});

  final PbFilesSortKey sortKey;
  final bool descending;
  final ValueChanged<PbFilesSortKey> onPressed;

  @override
  State<_FilesResponsiveSortButton> createState() => _FilesResponsiveSortButtonState();
}

class _FilesResponsiveSortButtonState extends State<_FilesResponsiveSortButton> {
  bool _open = false;

  void _closeMenu() {
    if (_open) {
      setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PbMenuAnchor(
      placement: PbMenuAnchorPlacement.bottomRight,
      gap: 6,
      triggerHeight: 28,
      onDismiss: _closeMenu,
      panel: _open
          ? PbMenuCard(
              width: 220,
              child: PbMenuList(
                children: [
                  for (final key in PbFilesSortKey.values.where((key) => key != PbFilesSortKey.thread && key != PbFilesSortKey.creator))
                    PbMenuOption(
                      title: key.label,
                      singleLine: true,
                      selected: key == widget.sortKey,
                      selectedSurface: key == widget.sortKey,
                      trailingIconAssetName: key == widget.sortKey ? 'circle-check-big' : null,
                      onPressed: () {
                        widget.onPressed(key);
                        _closeMenu();
                      },
                    ),
                ],
              ),
            )
          : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Sort:',
                style: PowerboardsTypography.smallStrong.copyWith(color: PbColors.textMuted, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.sortKey.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PowerboardsTypography.smallStrong.copyWith(color: PbColors.textBody, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 140),
                child: const PbSvgIcon(assetName: 'chevron-down', size: 14, color: PbColors.textBody),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PbFilesTableRow extends StatefulWidget {
  const _PbFilesTableRow({
    required this.item,
    required this.columns,
    required this.selected,
    required this.selectionMode,
    required this.active,
    required this.keyboardFocused,
    required this.keyboardPreviewDirection,
    required this.saving,
    required this.hoverSuppressed,
    required this.previousSelected,
    required this.nextSelected,
    required this.beforeStateRow,
    required this.last,
    required this.showExtract,
    required this.extractDisabled,
    required this.onPressed,
    required this.onToggleSelection,
    required this.onBrowseFolder,
    required this.onRemoveProcessingRow,
    required this.onLinkedThreadPressed,
    this.onAskAgent,
    this.onShare,
    this.onExtract,
    this.onDownload,
    this.onMoveTo,
    this.onRename,
    this.onDelete,
    required this.onHoverChanged,
    required this.onHoverResumed,
    required this.onMenuOpenChanged,
  });

  final PbFilesItemData item;
  final _FilesTableColumns columns;
  final bool selected;
  final bool selectionMode;
  final bool active;
  final bool keyboardFocused;
  final int keyboardPreviewDirection;
  final bool saving;
  final bool hoverSuppressed;
  final bool previousSelected;
  final bool nextSelected;
  final bool beforeStateRow;
  final bool last;
  final bool showExtract;
  final bool extractDisabled;
  final VoidCallback onPressed;
  final VoidCallback onToggleSelection;
  final VoidCallback onBrowseFolder;
  final VoidCallback onRemoveProcessingRow;
  final ValueChanged<String> onLinkedThreadPressed;
  final VoidCallback? onAskAgent;
  final VoidCallback? onShare;
  final VoidCallback? onExtract;
  final VoidCallback? onDownload;
  final VoidCallback? onMoveTo;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onHoverResumed;
  final ValueChanged<bool> onMenuOpenChanged;

  @override
  State<_PbFilesTableRow> createState() => _PbFilesTableRowState();
}

class _PbFilesTableRowState extends State<_PbFilesTableRow> {
  bool _hovered = false;
  bool _pressed = false;
  bool _menuOpen = false;

  bool get _processing => widget.item.kind == PbFilesItemKind.processing || widget.item.kind == PbFilesItemKind.processingError;

  @override
  void didUpdateWidget(covariant _PbFilesTableRow oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.keyboardFocused && (!oldWidget.keyboardFocused || oldWidget.keyboardPreviewDirection != widget.keyboardPreviewDirection)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        Scrollable.ensureVisible(
          context,
          duration: PbMotion.chevron,
          curve: Curves.easeOut,
          alignmentPolicy: widget.keyboardPreviewDirection < 0
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      });
    }

    if (widget.selectionMode && !oldWidget.selectionMode && _hovered) {
      _hovered = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onHoverChanged(false);
        }
      });
    }

    if (oldWidget.hoverSuppressed && !widget.hoverSuppressed && _hovered && !widget.selectionMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onHoverChanged(true);
        }
      });
    }

    if (widget.selectionMode && _menuOpen) {
      _menuOpen = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onMenuOpenChanged(false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuOpen = _menuOpen && !widget.selectionMode;
    final hovered = _hovered && !widget.hoverSuppressed && !widget.selectionMode;
    final normalHovered = hovered && !_processing;
    final processingHovered = hovered && _processing;
    final processingMenuOpen = menuOpen && _processing;
    final stateful = !_processing && (widget.selected || widget.active || _pressed || menuOpen);
    final menuVisible = !widget.selectionMode && (normalHovered || processingHovered || _pressed || menuOpen);
    final hideDivider = widget.last || stateful || normalHovered || processingHovered || processingMenuOpen || widget.beforeStateRow;
    final radius = _processing ? BorderRadius.circular(processingHovered || processingMenuOpen ? 10 : 0) : _selectionRadius();
    final backgroundColor = _processing
        ? processingMenuOpen
              ? Color.lerp(PbColors.dynamicSurfacePanel, PbColors.dynamicSurfacePanelSoft, 0.72)
              : processingHovered
              ? Color.lerp(PbColors.dynamicSurfacePanelSoft, PbColors.dynamicSurfacePanel, 0.56)
              : Colors.transparent
        : widget.selected || widget.active || _pressed
        ? PbColors.dynamicCustomStateSelectedSurface
        : menuOpen
        ? PbColors.dynamicCustomMenuOpenSurface
        : null;
    final gradient = !_processing && normalHovered && !stateful
        ? LinearGradient(
            colors: [PbColors.dynamicSurfacePanel, PbColors.dynamicSurfacePanelSoft],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : null;
    final borderColor = _processing
        ? processingHovered
              ? PbColors.borderSoft.withValues(alpha: 0.86)
              : Colors.transparent
        : widget.active || _pressed
        ? widget.keyboardFocused
              ? PbColors.dynamicCustomRailSelectedSurface
              : PbColors.dynamicCustomStateSelectedBorder
        : Colors.transparent;
    final shadow = _processing
        ? null
        : widget.keyboardFocused
        ? [BoxShadow(color: PbColors.dynamicCustomRailSelectedSurface, blurRadius: 0, spreadRadius: 1)]
        : normalHovered && !stateful
        ? PbShadows.stateHover
        : _pressed
        ? PbShadows.statePressedInset
        : null;
    final menuLabels = switch (widget.item.kind) {
      PbFilesItemKind.processing => ['Cancel process'],
      PbFilesItemKind.processingError => ['Delete'],
      PbFilesItemKind.folder => [
        'Browse folder',
        if (widget.onAskAgent != null) 'Ask agent',
        if (widget.onDownload != null) 'Download as zip',
        if (widget.onRename != null) widget.item.renameActionLabelOverride ?? 'Rename',
        if (widget.onMoveTo != null) 'Move to...',
        if (widget.onDelete != null) 'Delete',
      ],
      PbFilesItemKind.file => [
        'Open',
        if (widget.onAskAgent != null) 'Ask agent',
        if (widget.onShare != null) 'Share',
        if (widget.showExtract) pbArchiveExtractMenuLabel,
        if (widget.onDownload != null) 'Download',
        if (widget.onRename != null) widget.item.renameActionLabelOverride ?? 'Rename',
        if (widget.onMoveTo != null) 'Move to...',
        if (widget.onDelete != null) 'Delete',
      ],
    };
    final rowMenuWidth = _menuWidthForLabels(context, menuLabels, min: 204, max: 280);

    return MouseRegion(
      cursor: _processing ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        if (!widget.selectionMode && !widget.hoverSuppressed) {
          widget.onHoverChanged(true);
        }
      },
      onHover: (_) {
        if (widget.hoverSuppressed) {
          widget.onHoverResumed();
        }
      },
      onExit: (_) {
        setState(() {
          _hovered = false;
          _pressed = false;
        });
        widget.onHoverChanged(false);
      },
      child: Listener(
        onPointerDown: _processing ? null : (_) => setState(() => _pressed = true),
        onPointerUp: _processing ? null : (_) => setState(() => _pressed = false),
        onPointerCancel: _processing ? null : (_) => setState(() => _pressed = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _processing ? null : widget.onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: EdgeInsets.symmetric(horizontal: widget.columns.compact ? 8 : 10, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              gradient: gradient,
              borderRadius: radius,
              border: Border.all(color: borderColor),
              boxShadow: shadow,
            ),
            foregroundDecoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: hideDivider ? Colors.transparent : PbColors.borderFaint)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: _FilesTableColumns.selectWidth,
                  child: Center(
                    child: _FilesCheckbox(checked: widget.selected, onPressed: widget.onToggleSelection),
                  ),
                ),
                SizedBox(width: widget.columns.gap),
                SizedBox(width: widget.columns.nameWidth, child: _nameCell()),
                if (widget.columns.showType) ...[
                  SizedBox(width: widget.columns.gap),
                  SizedBox(width: widget.columns.typeWidth, child: _mutedCell(widget.item.type)),
                ],
                if (widget.columns.showSize) ...[
                  SizedBox(width: widget.columns.gap),
                  SizedBox(width: widget.columns.sizeWidth, child: _mutedCell(widget.item.sizeLabel)),
                ],
                if (widget.columns.showThread) ...[
                  SizedBox(width: widget.columns.gap),
                  SizedBox(width: widget.columns.threadWidth, child: _threadCell()),
                ],
                if (widget.columns.showCreator) ...[
                  SizedBox(width: widget.columns.gap),
                  SizedBox(width: widget.columns.creatorWidth, child: _creatorCell()),
                ],
                SizedBox(width: widget.columns.gap),
                SizedBox(
                  width: widget.columns.updatedWidth,
                  child: Align(
                    alignment: widget.columns.responsiveSort ? Alignment.centerRight : Alignment.centerLeft,
                    child: _mutedCell(widget.item.updatedLabel),
                  ),
                ),
                SizedBox(width: widget.columns.gap),
                SizedBox(
                  width: _FilesTableColumns.optionsWidth,
                  height: 32,
                  child: widget.selectionMode
                      ? const SizedBox.shrink()
                      : AnimatedOpacity(
                          duration: PbMotion.state,
                          opacity: menuVisible ? 1 : 0,
                          child: IgnorePointer(
                            ignoring: !menuVisible,
                            child: PbSidepaneItemMenu(
                              size: 32,
                              panelWidth: rowMenuWidth,
                              onOpenChanged: (open) {
                                setState(() => _menuOpen = open);
                                widget.onMenuOpenChanged(open);
                              },
                              panelBuilder: (closeMenu) => PbFilesRowMenu(
                                item: widget.item,
                                onOpen: widget.onPressed,
                                onBrowseFolder: widget.onBrowseFolder,
                                onRemoveProcessingRow: widget.onRemoveProcessingRow,
                                onAskAgent: widget.item.kind == PbFilesItemKind.file || widget.item.kind == PbFilesItemKind.folder
                                    ? widget.onAskAgent
                                    : null,
                                onShare: widget.item.kind == PbFilesItemKind.file ? widget.onShare : null,
                                showExtract: widget.item.kind == PbFilesItemKind.file && widget.showExtract,
                                onExtract: widget.item.kind == PbFilesItemKind.file ? widget.onExtract : null,
                                onDownload: widget.item.kind == PbFilesItemKind.file || widget.item.kind == PbFilesItemKind.folder
                                    ? widget.onDownload
                                    : null,
                                onMoveTo: widget.item.kind == PbFilesItemKind.file || widget.item.kind == PbFilesItemKind.folder
                                    ? widget.onMoveTo
                                    : null,
                                onRename: widget.onRename,
                                onDelete: widget.onDelete,
                                onDismiss: closeMenu,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BorderRadius _selectionRadius() {
    if (!widget.selected) {
      final menuOpen = _menuOpen && !widget.selectionMode;
      final hovered = _hovered && !widget.hoverSuppressed && !widget.selectionMode;
      return BorderRadius.circular(widget.active || _pressed || menuOpen || hovered ? 10 : 0);
    }

    if (!widget.previousSelected && !widget.nextSelected) {
      return BorderRadius.circular(10);
    }

    if (!widget.previousSelected && widget.nextSelected) {
      return const BorderRadius.vertical(top: Radius.circular(10));
    }

    if (widget.previousSelected && !widget.nextSelected) {
      return const BorderRadius.vertical(bottom: Radius.circular(10));
    }

    return BorderRadius.zero;
  }

  Widget _nameCell() {
    final iconName = _processing
        ? widget.item.kind == PbFilesItemKind.processingError
              ? 'triangle-alert'
              : 'loader-circle'
        : widget.saving
        ? 'loader-circle'
        : widget.item.iconAssetName;
    final iconColor = widget.item.kind == PbFilesItemKind.processingError
        ? PbColors.customAlert
        : widget.saving
        ? PbColors.textMuted
        : _processing
        ? PbColors.textMuted
        : widget.item.iconColor;

    return Row(
      children: [
        (_processing && widget.item.kind == PbFilesItemKind.processing) || widget.saving
            ? PbSpinningIcon(assetName: iconName, size: 26, color: iconColor)
            : PbSvgIcon(assetName: iconName, size: 26, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PowerboardsTypography.button.copyWith(
                  color: widget.item.kind == PbFilesItemKind.processingError
                      ? PbColors.customAlert
                      : _processing
                      ? PbColors.textMuted
                      : PbColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mutedCell(String value) {
    if (_processing) {
      return const SizedBox.shrink();
    }

    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: PowerboardsTypography.small.copyWith(color: PbColors.textMuted, fontWeight: FontWeight.w500),
    );
  }

  Widget _threadCell() {
    if (_processing) {
      return const SizedBox.shrink();
    }

    final threads = widget.item.linkedThreadTargets;
    if (threads.isEmpty) {
      return _mutedCell('-');
    }

    if (widget.selectionMode) {
      return _mutedCell(threads.length == 1 ? threads.first : 'Multiple');
    }

    if (threads.length == 1) {
      return _FileLinkedThreadButton(label: threads.first, onPressed: () => widget.onLinkedThreadPressed(threads.first));
    }

    return _FileLinkedThreadMenu(threads: threads, onThreadPressed: widget.onLinkedThreadPressed);
  }

  Widget _creatorCell() {
    if (_processing) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: widget.columns.showCreatorName ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: PbColors.dynamicPrimaryGradient, begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.item.creatorInitials,
            style: PowerboardsTypography.textXSmall.copyWith(color: PbColors.textInverse, fontWeight: FontWeight.w600),
          ),
        ),
        if (widget.columns.showCreatorName) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.item.creator,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PowerboardsTypography.small.copyWith(color: PbColors.textBody, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ],
    );
  }
}

class _FileLinkedThreadButton extends StatefulWidget {
  const _FileLinkedThreadButton({required this.label, required this.onPressed, this.selected = false});

  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  State<_FileLinkedThreadButton> createState() => _FileLinkedThreadButtonState();
}

class _FileLinkedThreadButtonState extends State<_FileLinkedThreadButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: PowerboardsTypography.small.copyWith(
              color: active ? PbColors.textPrimary : PbColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _FileLinkedThreadMenu extends StatefulWidget {
  const _FileLinkedThreadMenu({required this.threads, required this.onThreadPressed});

  final List<String> threads;
  final ValueChanged<String> onThreadPressed;

  @override
  State<_FileLinkedThreadMenu> createState() => _FileLinkedThreadMenuState();
}

class _FileLinkedThreadMenuState extends State<_FileLinkedThreadMenu> {
  bool _open = false;

  void _closeMenu() {
    if (_open) {
      setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = _menuWidthForLabels(context, widget.threads, min: 220, max: 420);

    return PbMenuAnchor(
      placement: PbMenuAnchorPlacement.bottomLeft,
      gap: 6,
      triggerHeight: 28,
      onDismiss: _closeMenu,
      panel: _open
          ? PbMenuCard(
              width: width,
              child: PbMenuList(
                children: [
                  for (final thread in widget.threads)
                    PbMenuOption(
                      title: thread,
                      trailingIconAssetName: 'arrow-up-right',
                      singleLine: true,
                      onPressed: () {
                        widget.onThreadPressed(thread);
                        _closeMenu();
                      },
                    ),
                ],
              ),
            )
          : null,
      child: _FileLinkedThreadButton(label: 'Multiple', selected: _open, onPressed: () => setState(() => _open = !_open)),
    );
  }
}

class _FilesCheckbox extends StatelessWidget {
  const _FilesCheckbox({required this.checked, this.mixed = false, this.compactHitArea = false, required this.onPressed});

  final bool checked;
  final bool mixed;
  final bool compactHitArea;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = checked || mixed;
    final hitSize = compactHitArea ? 14.0 : 22.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: hitSize,
          height: hitSize,
          child: Center(
            child: AnimatedContainer(
              duration: PbMotion.state,
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: active ? PbColors.dynamicSurfaceActionPrimary : PbColors.dynamicSurfacePanel,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: active ? PbColors.dynamicSurfaceActionPrimary : PbColors.customGray),
              ),
              child: active
                  ? CustomPaint(
                      painter: _FilesCheckPainter(mixed: mixed),
                      size: const Size(14, 14),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilesCheckPainter extends CustomPainter {
  const _FilesCheckPainter({required this.mixed});

  final bool mixed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = PbColors.dynamicSurfacePanel
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (mixed) {
      canvas.drawLine(Offset(size.width * 0.32, size.height * 0.5), Offset(size.width * 0.68, size.height * 0.5), paint);
      return;
    }

    final path = Path()
      ..moveTo(size.width * 0.33, size.height * 0.51)
      ..lineTo(size.width * 0.46, size.height * 0.63)
      ..lineTo(size.width * 0.69, size.height * 0.39);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FilesCheckPainter oldDelegate) {
    return oldDelegate.mixed != mixed;
  }
}

class _FilesEmptyState extends StatelessWidget {
  const _FilesEmptyState({required this.noResults});

  final bool noResults;

  @override
  Widget build(BuildContext context) {
    const sourceMainHeaderHeight = 142.0;
    const sourceTopFactor = 0.334;
    const tableTopOffset = -sourceMainHeaderHeight * (1 - sourceTopFactor);

    return PbEmptyState(
      iconAssetName: noResults ? 'logs' : 'image',
      title: noResults ? 'Try again' : 'Add files here',
      subtitle: noResults
          ? 'No results here yet. Clear the filter or try a different keyword.'
          : 'No files here yet. Start adding documents and media to share, or discuss.',
      topFactor: sourceTopFactor,
      topOffset: tableTopOffset,
    );
  }
}
