import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/pb_attachment_file_metadata.dart';
import '../../models/pb_agent_display.dart';
import '../../theme/pb_colors.dart';
import '../../theme/pb_tokens.dart';
import '../../theme/pb_typography.dart';
import '../files/pb_archive_extract.dart';
import '../files/pb_file_menus.dart';
import '../files/pb_sidepane_file_list.dart';
import '../files/pb_file_preview_state_card.dart';
import '../menus/pb_menu_anchor.dart';
import '../menus/pb_menu_card.dart';
import '../menus/pb_menu_list.dart';
import '../menus/pb_menu_option.dart';
import '../menus/pb_sidepane_item_menu.dart';
import '../menus/pb_thread_item_menu.dart';
import '../primitives/pb_avatar.dart';
import '../primitives/pb_button.dart';
import '../primitives/pb_svg_icon.dart';

enum PbRoomPanelTab { agents, files }

enum PbAgentStatusTone { online, amber, gray, error }

const double pbShellCompactBreakpoint = PbBreakpoints.shellCompact;
const double pbShellMobileBreakpoint = PbBreakpoints.shellMobile;
const double pbRoomPanelStackBreakpoint = PbBreakpoints.roomPanelStack;

const double _sidepaneInlinePadding = 22;
const double _sidepaneScrollTopPadding = 8;
const double _sidepaneListTopHoverClearance = 2;
const double _sidepaneCardListVisualOffset = _sidepaneScrollTopPadding - _sidepaneListTopHoverClearance;
const double _sidepaneScrollBottomPadding = 24;
const double _sidepaneDescriptionToListGap = 20;
const double _sidepaneListToActionsGap = 20;
const double _sidepaneActionsHeight = 36;
const double _sidepaneActionsToDividerGap = 30;
const double _sidepaneDescriptionHeight = 14 * 1.4;
const double _sidepaneDividerMaxHeightFactor = 0.5;
const int _agentListScrollThreshold = 3;
const double _agentCardMinHeight = 70;
const double _agentListGap = 10;

class PbRoomPanel extends StatefulWidget {
  const PbRoomPanel({
    super.key,
    this.initialTab = PbRoomPanelTab.agents,
    this.selectedTab,
    this.onTabSelected,
    this.onFilePreviewOpenChanged,
    this.onFilePreviewFullscreenChanged,
    this.onFilePreviewSelected,
    this.onUnavailableFileSelected,
    this.initialPreviewFile,
    this.initialFilePreviewOpen = false,
    this.agents,
    this.selectedAgentId,
    this.selectedAgentTitle,
    this.onAgentSelected,
    this.onAgentItemSelected,
    this.onManageAgents,
    this.agentsExpanded,
    this.onAgentsExpandedChanged,
    this.showThreadsSection = true,
    this.showFilesTab = true,
    this.filesTabLabel = 'Files',
    this.filesPanelDescription = 'Browse attachments by selected thread.',
    this.filesEmptyState = const PbSidepaneFileEmptyStateData(title: 'No files here yet', subtitle: 'Files attached will show up here.'),
    this.attachments,
    this.filePreviewBuilder,
    this.filePreviewSourceBuilder,
    this.onAskFileAgent,
    this.onShareFile,
    this.onExtractArchiveFile,
    this.onDownloadFile,
    this.onSaveFileCopyAs,
    required this.threads,
    this.threadItems,
    this.selectedThreadId,
    required this.selectedThreadTitle,
    required this.onThreadSelected,
    this.onThreadItemSelected,
    this.onThreadRename,
    this.onThreadDelete,
    required this.onCreateThread,
    this.filePreviewResizing = false,
    this.borderOnTop = false,
    this.responsiveOverlay = false,
    this.responsiveOverlayMobile = false,
    this.openFilePreviewAsFullscreen = false,
    this.onResponsiveOverlayClose,
  });

  final PbRoomPanelTab initialTab;
  final PbRoomPanelTab? selectedTab;
  final ValueChanged<PbRoomPanelTab>? onTabSelected;
  final ValueChanged<bool>? onFilePreviewOpenChanged;
  final ValueChanged<bool>? onFilePreviewFullscreenChanged;
  final ValueChanged<PbAttachmentListItemData>? onFilePreviewSelected;
  final ValueChanged<PbAttachmentListItemData>? onUnavailableFileSelected;
  final PbAttachmentListItemData? initialPreviewFile;
  final bool initialFilePreviewOpen;
  final List<PbAgentListItemData>? agents;
  final String? selectedAgentId;
  final String? selectedAgentTitle;
  final ValueChanged<String>? onAgentSelected;
  final ValueChanged<PbAgentListItemData>? onAgentItemSelected;
  final VoidCallback? onManageAgents;
  final bool? agentsExpanded;
  final ValueChanged<bool>? onAgentsExpandedChanged;
  final bool showThreadsSection;
  final bool showFilesTab;
  final String filesTabLabel;
  final String filesPanelDescription;
  final PbSidepaneFileEmptyStateData filesEmptyState;
  final List<PbAttachmentListItemData>? attachments;
  final Widget Function(PbAttachmentListItemData file)? filePreviewBuilder;
  final PbFilePreviewSource? Function(PbAttachmentListItemData file)? filePreviewSourceBuilder;
  final ValueChanged<PbAttachmentListItemData>? onAskFileAgent;
  final ValueChanged<PbAttachmentListItemData>? onShareFile;
  final ValueChanged<PbAttachmentListItemData>? onExtractArchiveFile;
  final ValueChanged<PbAttachmentListItemData>? onDownloadFile;
  final ValueChanged<PbAttachmentListItemData>? onSaveFileCopyAs;
  final List<String> threads;
  final List<PbThreadListItemData>? threadItems;
  final String? selectedThreadId;
  final String? selectedThreadTitle;
  final ValueChanged<String> onThreadSelected;
  final ValueChanged<PbThreadListItemData>? onThreadItemSelected;
  final ValueChanged<PbThreadListItemData>? onThreadRename;
  final ValueChanged<PbThreadListItemData>? onThreadDelete;
  final VoidCallback onCreateThread;
  final bool filePreviewResizing;
  final bool borderOnTop;
  final bool responsiveOverlay;
  final bool responsiveOverlayMobile;
  final bool openFilePreviewAsFullscreen;
  final VoidCallback? onResponsiveOverlayClose;

  @override
  State<PbRoomPanel> createState() => _PbRoomPanelState();
}

class _PbRoomPanelState extends State<PbRoomPanel> {
  late PbRoomPanelTab _selectedTab = widget.initialTab;
  late bool _filePreviewOpen = widget.initialFilePreviewOpen;
  late bool _filePreviewFullscreen = widget.initialFilePreviewOpen && widget.openFilePreviewAsFullscreen;
  late PbAttachmentListItemData _previewFile = widget.initialPreviewFile ?? _placeholderPreviewFile;
  Object? _filePreviewDraftKey;
  String? _filePreviewDraftText;

  static const PbAttachmentListItemData _placeholderPreviewFile = PbAttachmentListItemData(
    title: 'File name.ext',
    subtitle: 'Type',
    fileType: PbAttachmentFileType.generic,
  );

  static const _agents = [
    PbAgentListItemData(title: 'Assistant', status: 'Connected', icon: 'bot', selected: true),
    PbAgentListItemData(title: 'Research', status: 'Connecting...', icon: 'search', statusTone: PbAgentStatusTone.amber),
    PbAgentListItemData(title: 'Builder', status: 'Not connected...', icon: 'pencil-ruler', statusTone: PbAgentStatusTone.gray),
    PbAgentListItemData(title: 'Coordinator', status: 'Connected', icon: 'messages-square'),
  ];

  static const _attachments = [
    PbAttachmentListItemData(title: 'File name.ext', subtitle: 'Type', fileType: PbAttachmentFileType.generic),
    PbAttachmentListItemData(title: 'May 12 notes', subtitle: 'Meeting note', fileType: PbAttachmentFileType.document),
    PbAttachmentListItemData(title: 'Q2 roadmap.pdf', subtitle: 'PDF', fileType: PbAttachmentFileType.document),
    PbAttachmentListItemData(title: 'Agent handoff.md', subtitle: 'Markdown', fileType: PbAttachmentFileType.document),
    PbAttachmentListItemData(title: 'Design review.mov', subtitle: 'Video', fileType: PbAttachmentFileType.video),
    PbAttachmentListItemData(title: 'Spec comments.txt', subtitle: 'Text', fileType: PbAttachmentFileType.document),
    PbAttachmentListItemData(title: 'Ops checklist.csv', subtitle: 'Spreadsheet', fileType: PbAttachmentFileType.spreadsheet),
    PbAttachmentListItemData(title: 'Launch screenshots.zip', subtitle: 'Archive', fileType: PbAttachmentFileType.archive),
    PbAttachmentListItemData(title: 'Stakeholder summary.docx', subtitle: 'Document', fileType: PbAttachmentFileType.document),
    PbAttachmentListItemData(title: 'Weekly sync.m4a', subtitle: 'Audio', fileType: PbAttachmentFileType.sound),
    PbAttachmentListItemData(title: 'Data export.json', subtitle: 'JSON', fileType: PbAttachmentFileType.code),
    PbAttachmentListItemData(title: 'Partner brief.key', subtitle: 'Presentation', fileType: PbAttachmentFileType.presentation),
    PbAttachmentListItemData(title: 'Budget model.xlsx', subtitle: 'Spreadsheet', fileType: PbAttachmentFileType.spreadsheet),
    PbAttachmentListItemData(title: 'API contract.yaml', subtitle: 'YAML', fileType: PbAttachmentFileType.code),
    PbAttachmentListItemData(title: 'Field notes.pages', subtitle: 'Document', fileType: PbAttachmentFileType.document),
    PbAttachmentListItemData(title: 'Board export.png', subtitle: 'Image', fileType: PbAttachmentFileType.image),
    PbAttachmentListItemData(title: 'Legal approval.pdf', subtitle: 'PDF', fileType: PbAttachmentFileType.document),
    PbAttachmentListItemData(title: 'Agent matrix.numbers', subtitle: 'Spreadsheet', fileType: PbAttachmentFileType.spreadsheet),
    PbAttachmentListItemData(title: 'QA pass checklist.md', subtitle: 'Markdown', fileType: PbAttachmentFileType.document),
    PbAttachmentListItemData(title: 'Transcript.srt', subtitle: 'Captions', fileType: PbAttachmentFileType.transcript),
    PbAttachmentListItemData(title: 'Training deck.pptx', subtitle: 'Presentation', fileType: PbAttachmentFileType.presentation),
    PbAttachmentListItemData(title: 'Release notes.rtf', subtitle: 'Rich text', fileType: PbAttachmentFileType.document),
  ];

  PbRoomPanelTab get _activeTab {
    final selectedTab = widget.selectedTab ?? _selectedTab;
    if (!widget.showFilesTab && selectedTab == PbRoomPanelTab.files) {
      return PbRoomPanelTab.agents;
    }
    return selectedTab;
  }

  @override
  void didUpdateWidget(covariant PbRoomPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedTab != null && widget.selectedTab != oldWidget.selectedTab) {
      _selectedTab = widget.selectedTab!;
    }

    if (!widget.showFilesTab && _selectedTab == PbRoomPanelTab.files) {
      _selectedTab = PbRoomPanelTab.agents;
    }

    if (widget.initialFilePreviewOpen != oldWidget.initialFilePreviewOpen) {
      _filePreviewOpen = widget.initialFilePreviewOpen;
      if (widget.initialFilePreviewOpen && widget.openFilePreviewAsFullscreen) {
        _filePreviewFullscreen = true;
      }
    }

    final nextPreviewFile = widget.initialPreviewFile;
    if (nextPreviewFile != null && nextPreviewFile != oldWidget.initialPreviewFile) {
      _previewFile = nextPreviewFile;
      _clearFilePreviewDraft();
    }

    if (widget.openFilePreviewAsFullscreen && !oldWidget.openFilePreviewAsFullscreen && _filePreviewOpen) {
      _filePreviewFullscreen = true;
    }
  }

  void _selectTab(PbRoomPanelTab tab) {
    if (tab == PbRoomPanelTab.files && !widget.showFilesTab) {
      return;
    }

    if (widget.selectedTab == null) {
      setState(() => _selectedTab = tab);
    }

    widget.onTabSelected?.call(tab);
  }

  void _openFilePreview(PbAttachmentListItemData file) {
    if (file.previewState == PbAttachmentPreviewState.unavailable) {
      widget.onUnavailableFileSelected?.call(file);
      return;
    }
    setState(() {
      if (_previewTextSourceChanged(_previewFile, file, null, null)) {
        _clearFilePreviewDraft();
      }
      _previewFile = file;
      _filePreviewOpen = true;
      _filePreviewFullscreen = widget.openFilePreviewAsFullscreen;
    });
    widget.onFilePreviewSelected?.call(file);
    widget.onFilePreviewOpenChanged?.call(true);
    widget.onFilePreviewFullscreenChanged?.call(widget.openFilePreviewAsFullscreen);
  }

  void _setFilePreviewFullscreen(bool fullscreen) {
    setState(() => _filePreviewFullscreen = fullscreen);
    widget.onFilePreviewFullscreenChanged?.call(fullscreen);
  }

  void _closeFilePreview() {
    setState(() {
      _filePreviewOpen = false;
      _filePreviewFullscreen = false;
      _clearFilePreviewDraft();
    });
    widget.onFilePreviewOpenChanged?.call(false);
    widget.onFilePreviewFullscreenChanged?.call(false);
  }

  Object _filePreviewDraftKeyFor(PbAttachmentListItemData file, Object? sourceKey) {
    return sourceKey ?? file.path ?? '${file.title}|${file.subtitle}|${file.fileType.name}';
  }

  String? _filePreviewDraftTextFor(Object draftKey) {
    return _filePreviewDraftKey == draftKey ? _filePreviewDraftText : null;
  }

  bool _filePreviewDraftDirtyFor(Object draftKey) {
    return _filePreviewDraftKey == draftKey && _filePreviewDraftText != null;
  }

  void _setFilePreviewDraftText(Object draftKey, String text) {
    if (_filePreviewDraftKey == draftKey && _filePreviewDraftText == text) {
      return;
    }

    setState(() {
      _filePreviewDraftKey = draftKey;
      _filePreviewDraftText = text;
    });
  }

  void _clearFilePreviewDraftFor(Object draftKey) {
    if (_filePreviewDraftKey != draftKey) {
      return;
    }

    setState(_clearFilePreviewDraft);
  }

  void _clearFilePreviewDraft() {
    _filePreviewDraftKey = null;
    _filePreviewDraftText = null;
  }

  Widget _buildPanelContent({
    required bool showInlineBorder,
    required EdgeInsetsGeometry padding,
    Color backgroundColor = PbColors.surfacePanelWash,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: !showInlineBorder
            ? null
            : widget.borderOnTop
            ? const Border(top: BorderSide(color: PbColors.borderSoft))
            : const Border(left: BorderSide(color: PbColors.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PbRoomTabs(
            selectedTab: _activeTab,
            showFilesTab: widget.showFilesTab,
            filesTabLabel: widget.filesTabLabel,
            onTabSelected: _selectTab,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -4),
              child: _activeTab == PbRoomPanelTab.agents
                  ? _AgentsPanel(
                      agents: widget.agents ?? _agents,
                      threads: widget.threads,
                      threadItems: widget.threadItems,
                      selectedAgentId: widget.selectedAgentId,
                      selectedAgentTitle: widget.selectedAgentTitle,
                      onAgentSelected: widget.onAgentSelected,
                      onAgentItemSelected: widget.onAgentItemSelected,
                      onManageAgents: widget.onManageAgents,
                      agentsExpanded: widget.agentsExpanded,
                      onAgentsExpandedChanged: widget.onAgentsExpandedChanged,
                      showThreadsSection: widget.showThreadsSection,
                      selectedThreadId: widget.selectedThreadId,
                      selectedThreadTitle: widget.selectedThreadTitle,
                      onThreadSelected: widget.onThreadSelected,
                      onThreadItemSelected: widget.onThreadItemSelected,
                      onThreadRename: widget.onThreadRename,
                      onThreadDelete: widget.onThreadDelete,
                      onCreateThread: widget.onCreateThread,
                    )
                  : _FilesPanel(
                      attachments: widget.attachments ?? _attachments,
                      description: widget.filesPanelDescription,
                      emptyState: widget.filesEmptyState,
                      onPreviewFile: _openFilePreview,
                      onAskFileAgent: widget.onAskFileAgent,
                      onShareFile: widget.onShareFile,
                      onExtractArchiveFile: widget.onExtractArchiveFile,
                      onDownloadFile: widget.onDownloadFile,
                      onSaveFileCopyAs: widget.onSaveFileCopyAs,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPane({required bool showInlineBorder}) {
    final previewFullscreen = _filePreviewFullscreen || widget.openFilePreviewAsFullscreen;
    final previewSource = _previewFile.previewState == PbAttachmentPreviewState.none
        ? widget.filePreviewSourceBuilder?.call(_previewFile)
        : null;
    final previewContentChild = previewSource?.buildChild(previewFullscreen);
    final draftKey = _filePreviewDraftKeyFor(_previewFile, previewSource?.sourceKey);

    return PbFilePreviewPane(
      file: _previewFile,
      fullscreen: previewFullscreen,
      resizing: widget.filePreviewResizing,
      borderOnTop: widget.borderOnTop,
      showInlineBorder: showInlineBorder,
      hideFullscreenToggle: widget.responsiveOverlay,
      onAskAgent: !(_previewFile.showAskAgentAction) || widget.onAskFileAgent == null ? null : () => widget.onAskFileAgent!(_previewFile),
      onShare: widget.onShareFile == null ? null : () => widget.onShareFile!(_previewFile),
      onExtractArchive: widget.onExtractArchiveFile == null || !pbCanExtractArchive(_previewFile)
          ? null
          : () => widget.onExtractArchiveFile!(_previewFile),
      onDownload: widget.onDownloadFile == null ? null : () => widget.onDownloadFile!(_previewFile),
      onToggleFullscreen: () => _setFilePreviewFullscreen(!_filePreviewFullscreen),
      onClose: _closeFilePreview,
      previewContentChild: previewContentChild,
      loadText: previewSource?.loadText,
      headerLeading: previewSource?.headerLeading,
      hideToolbarActions: previewSource?.hideToolbarActions ?? false,
      onSave: previewSource?.onSave,
      onSaveTextRequested: previewSource?.saveText,
      sourceKey: previewSource?.sourceKey,
      draftText: _filePreviewDraftTextFor(draftKey),
      draftDirty: _filePreviewDraftDirtyFor(draftKey),
      onDraftTextChanged: (text) => _setFilePreviewDraftText(draftKey, text),
      onDraftSaved: () => _clearFilePreviewDraftFor(draftKey),
      child: previewSource == null && _previewFile.previewState == PbAttachmentPreviewState.none
          ? widget.filePreviewBuilder?.call(_previewFile)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.responsiveOverlay) {
      return PbResponsiveRoomPanelOverlayFrame(
        mobile: widget.responsiveOverlayMobile,
        onClose: widget.onResponsiveOverlayClose,
        preview: _filePreviewOpen ? _buildPreviewPane(showInlineBorder: false) : null,
        child: _buildPanelContent(
          showInlineBorder: false,
          backgroundColor: Colors.transparent,
          padding: const EdgeInsets.fromLTRB(_sidepaneInlinePadding, 26, _sidepaneInlinePadding, 0),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: _filePreviewOpen ? 0 : 1,
          child: IgnorePointer(
            ignoring: _filePreviewOpen,
            child: _buildPanelContent(
              showInlineBorder: true,
              padding: const EdgeInsets.fromLTRB(_sidepaneInlinePadding, 29, _sidepaneInlinePadding, 0),
            ),
          ),
        ),
        if (_filePreviewOpen) Positioned.fill(child: _buildPreviewPane(showInlineBorder: true)),
      ],
    );
  }
}

class PbResponsiveRoomPanelOverlayFrame extends StatelessWidget {
  const PbResponsiveRoomPanelOverlayFrame({super.key, required this.child, this.preview, this.mobile = false, this.onClose});

  final Widget child;
  final Widget? preview;
  final bool mobile;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final sidePadding = mobile ? 12.0 : 16.0;

    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxSheetHeight = mobile
              ? math.min(constraints.maxHeight * 0.8, constraints.maxHeight - 32)
              : math.min(680.0, constraints.maxHeight - 80);

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: ColoredBox(color: PbColors.surfaceRailActive.withValues(alpha: 0.52)),
                  ),
                ),
              ),
              if (preview == null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(sidePadding, 0, sidePadding, sidePadding),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxSheetHeight, maxWidth: double.infinity),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.08), blurRadius: 80, offset: Offset(0, 30))],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: PbColors.borderSoft),
                              gradient: const LinearGradient(
                                colors: [PbColors.surfacePanel, PbColors.surfacePanelSoft],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(child: child),
                                Positioned(
                                  top: 18,
                                  right: 16,
                                  child: _GhostIcon(assetName: 'x', onPressed: onClose),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Positioned.fill(child: preview!),
            ],
          );
        },
      ),
    );
  }
}

class PbRoomTabs extends StatefulWidget {
  const PbRoomTabs({
    super.key,
    required this.selectedTab,
    this.showFilesTab = true,
    this.filesTabLabel = 'Files',
    required this.onTabSelected,
  });

  final PbRoomPanelTab selectedTab;
  final bool showFilesTab;
  final String filesTabLabel;
  final ValueChanged<PbRoomPanelTab> onTabSelected;

  @override
  State<PbRoomTabs> createState() => _PbRoomTabsState();
}

class _PbRoomTabsState extends State<PbRoomTabs> {
  PbRoomPanelTab? _hoveredTab;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Stack(
        alignment: Alignment.bottomLeft,
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 1,
              child: DecoratedBox(decoration: BoxDecoration(color: PbColors.borderSoft)),
            ),
          ),
          Row(
            children: [
              _RoomTab(
                label: 'Agents',
                selected: widget.selectedTab == PbRoomPanelTab.agents,
                hovered: _hoveredTab == PbRoomPanelTab.agents,
                selectedSuppressed: _hoveredTab != null && _hoveredTab != PbRoomPanelTab.agents,
                onHoverChanged: (hovered) => setState(() => _hoveredTab = hovered ? PbRoomPanelTab.agents : null),
                onPressed: () => widget.onTabSelected(PbRoomPanelTab.agents),
              ),
              if (widget.showFilesTab) ...[
                const SizedBox(width: 24),
                _RoomTab(
                  label: widget.filesTabLabel,
                  selected: widget.selectedTab == PbRoomPanelTab.files,
                  hovered: _hoveredTab == PbRoomPanelTab.files,
                  selectedSuppressed: _hoveredTab != null && _hoveredTab != PbRoomPanelTab.files,
                  onHoverChanged: (hovered) => setState(() => _hoveredTab = hovered ? PbRoomPanelTab.files : null),
                  onPressed: () => widget.onTabSelected(PbRoomPanelTab.files),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class PbStaticRoomTabs extends StatelessWidget {
  const PbStaticRoomTabs({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(label, style: PowerboardsTypography.label.copyWith(color: PbColors.textPrimary)),
      ),
    );
  }
}

class _RoomTab extends StatelessWidget {
  const _RoomTab({
    required this.label,
    required this.selected,
    required this.hovered,
    required this.selectedSuppressed,
    required this.onHoverChanged,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool hovered;
  final bool selectedSuppressed;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final showUnderline = hovered || (selected && !selectedSuppressed);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(label, style: PowerboardsTypography.label.copyWith(color: selected ? PbColors.textPrimary : PbColors.textMuted)),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: -1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: 3,
                transform: Matrix4.diagonal3Values(showUnderline ? 1 : 0.82, 1, 1),
                decoration: BoxDecoration(
                  color: showUnderline ? PbColors.customBrandInk : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PbRoomPanelDescription extends StatelessWidget {
  const PbRoomPanelDescription(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: PowerboardsTypography.meta.copyWith(color: PbColors.textMuted));
  }
}

class _AgentsPanel extends StatefulWidget {
  const _AgentsPanel({
    required this.agents,
    required this.threads,
    this.threadItems,
    this.selectedAgentId,
    this.selectedAgentTitle,
    this.onAgentSelected,
    this.onAgentItemSelected,
    this.onManageAgents,
    this.agentsExpanded,
    this.onAgentsExpandedChanged,
    this.showThreadsSection = true,
    this.selectedThreadId,
    required this.selectedThreadTitle,
    required this.onThreadSelected,
    this.onThreadItemSelected,
    this.onThreadRename,
    this.onThreadDelete,
    required this.onCreateThread,
  });

  final List<PbAgentListItemData> agents;
  final List<String> threads;
  final List<PbThreadListItemData>? threadItems;
  final String? selectedAgentId;
  final String? selectedAgentTitle;
  final ValueChanged<String>? onAgentSelected;
  final ValueChanged<PbAgentListItemData>? onAgentItemSelected;
  final VoidCallback? onManageAgents;
  final bool? agentsExpanded;
  final ValueChanged<bool>? onAgentsExpandedChanged;
  final bool showThreadsSection;
  final String? selectedThreadId;
  final String? selectedThreadTitle;
  final ValueChanged<String> onThreadSelected;
  final ValueChanged<PbThreadListItemData>? onThreadItemSelected;
  final ValueChanged<PbThreadListItemData>? onThreadRename;
  final ValueChanged<PbThreadListItemData>? onThreadDelete;
  final VoidCallback onCreateThread;

  @override
  State<_AgentsPanel> createState() => _AgentsPanelState();
}

class _AgentsPanelState extends State<_AgentsPanel> {
  bool _agentsExpanded = true;
  late String _selectedAgentKey = _initialSelectedAgentKey();

  bool get _effectiveAgentsExpanded => widget.agentsExpanded ?? _agentsExpanded;

  void _setAgentsExpanded(bool expanded) {
    if (widget.agentsExpanded == null) {
      setState(() => _agentsExpanded = expanded);
    }

    widget.onAgentsExpandedChanged?.call(expanded);
  }

  String _initialSelectedAgentKey() {
    final selectedId = widget.selectedAgentId;
    if (selectedId != null) {
      for (final agent in widget.agents) {
        if (agent.id == selectedId) {
          return agent.identity;
        }
      }
    }

    final selectedTitle = widget.selectedAgentTitle;
    if (selectedTitle != null) {
      for (final agent in widget.agents) {
        if (agent.title == selectedTitle) {
          return agent.identity;
        }
      }
    }

    if (widget.agents.isEmpty) {
      return '';
    }

    return widget.agents.firstWhere((agent) => agent.selected, orElse: () => widget.agents.first).identity;
  }

  @override
  void didUpdateWidget(covariant _AgentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final selectedId = widget.selectedAgentId;
    if (selectedId != null) {
      for (final agent in widget.agents) {
        if (agent.id == selectedId && agent.identity != _selectedAgentKey) {
          _selectedAgentKey = agent.identity;
          break;
        }
      }
    } else {
      final selectedTitle = widget.selectedAgentTitle;
      if (selectedTitle != null) {
        for (final agent in widget.agents) {
          if (agent.title == selectedTitle) {
            if (agent.identity != _selectedAgentKey) {
              _selectedAgentKey = agent.identity;
            }
            break;
          }
        }
      }
    }

    if (!widget.agents.any((agent) => agent.identity == _selectedAgentKey) && widget.agents.isNotEmpty) {
      _selectedAgentKey = widget.agents.first.identity;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.agents.isEmpty) {
      return _EmptyAgentsPanel(onManageAgents: widget.onManageAgents);
    }

    final selectedAgent = widget.agents.firstWhere((agent) => agent.identity == _selectedAgentKey, orElse: () => widget.agents.first);
    final agentsExpanded = _effectiveAgentsExpanded;
    final visibleAgents = agentsExpanded ? widget.agents : [selectedAgent];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactLayout = constraints.maxHeight < 520;
        final fixedSection = _AgentsFixedSection(
          agents: visibleAgents,
          selectedAgentKey: _selectedAgentKey,
          expanded: agentsExpanded,
          canToggleExpanded: widget.agents.length > 1,
          panelHeight: constraints.maxHeight,
          compactLayout: compactLayout,
          onManageAgents: widget.onManageAgents,
          showDivider: widget.showThreadsSection,
          onAgentSelected: (agent) {
            setState(() => _selectedAgentKey = agent.identity);
            widget.onAgentSelected?.call(agent.title);
            widget.onAgentItemSelected?.call(agent);
          },
          onToggleExpanded: () => _setAgentsExpanded(!agentsExpanded),
        );
        final threadsSection = widget.showThreadsSection
            ? _ThreadsSection(
                threads: widget.threads,
                threadItems: widget.threadItems,
                selectedThreadId: widget.selectedThreadId,
                selectedThread: widget.selectedThreadTitle,
                compactLayout: compactLayout,
                onCreateThread: widget.onCreateThread,
                onThreadSelected: widget.onThreadSelected,
                onThreadItemSelected: widget.onThreadItemSelected,
                onThreadRename: widget.onThreadRename,
                onThreadDelete: widget.onThreadDelete,
              )
            : null;

        if (compactLayout) {
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              fixedSection,
              if (threadsSection != null) ...[const SizedBox(height: 30), threadsSection],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            fixedSection,
            if (threadsSection != null) ...[const SizedBox(height: 30), Expanded(child: threadsSection)],
          ],
        );
      },
    );
  }
}

class _EmptyAgentsPanel extends StatelessWidget {
  const _EmptyAgentsPanel({this.onManageAgents});

  final VoidCallback? onManageAgents;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _RoomPanelDescription('Install an agent in this room to get started.'),
        const SizedBox(height: 20),
        PbTertiaryButton.solid(label: 'Install an Agent', onPressed: onManageAgents),
      ],
    );
  }
}

class _RoomPanelDescription extends StatelessWidget {
  const _RoomPanelDescription(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: PowerboardsTypography.meta.copyWith(color: PbColors.textMuted));
  }
}

class _AgentsFixedSection extends StatelessWidget {
  const _AgentsFixedSection({
    required this.agents,
    required this.selectedAgentKey,
    required this.expanded,
    required this.canToggleExpanded,
    required this.panelHeight,
    required this.compactLayout,
    this.onManageAgents,
    required this.showDivider,
    required this.onAgentSelected,
    required this.onToggleExpanded,
  });

  final List<PbAgentListItemData> agents;
  final String selectedAgentKey;
  final bool expanded;
  final bool canToggleExpanded;
  final double panelHeight;
  final bool compactLayout;
  final VoidCallback? onManageAgents;
  final bool showDivider;
  final ValueChanged<PbAgentListItemData> onAgentSelected;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final description = showDivider ? 'Browse threads by selected agent.' : 'Browse agents in this room.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoomPanelDescription(description),
        SizedBox(height: _sidepaneDescriptionToListGap + (compactLayout ? _sidepaneListTopHoverClearance : 0)),
        Transform.translate(
          offset: const Offset(0, _sidepaneCardListVisualOffset),
          child: _AgentGroup(
            agents: agents,
            selectedAgentKey: selectedAgentKey,
            expanded: expanded,
            panelHeight: panelHeight,
            onAgentSelected: onAgentSelected,
          ),
        ),
        const SizedBox(height: _sidepaneListToActionsGap),
        _AgentActions(
          expanded: expanded,
          canToggleExpanded: canToggleExpanded,
          onManageAgents: onManageAgents,
          onToggleExpanded: onToggleExpanded,
        ),
        if (showDivider) ...[
          const SizedBox(height: _sidepaneActionsToDividerGap),
          const Divider(height: 1, thickness: 1, color: PbColors.borderSoft),
        ],
      ],
    );
  }
}

class _AgentGroup extends StatefulWidget {
  const _AgentGroup({
    required this.agents,
    required this.selectedAgentKey,
    required this.expanded,
    required this.panelHeight,
    required this.onAgentSelected,
  });

  final List<PbAgentListItemData> agents;
  final String selectedAgentKey;
  final bool expanded;
  final double panelHeight;
  final ValueChanged<PbAgentListItemData> onAgentSelected;

  @override
  State<_AgentGroup> createState() => _AgentGroupState();
}

class _AgentGroupState extends State<_AgentGroup> {
  static const double _selectedRevealInset = 12;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _scrollRegionKey = GlobalKey();
  final Map<String, GlobalKey> _agentKeys = {};
  String? _lastRevealSignature;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.expanded) {
      _lastRevealSignature = null;
      return _AgentList(agents: widget.agents, selectedAgentKey: widget.selectedAgentKey, onAgentSelected: widget.onAgentSelected);
    }

    final contentHeight = _agentListHeight(widget.agents.length);
    final maxHeight = _agentListMaxHeight(widget.panelHeight);

    if (widget.agents.length <= _agentListScrollThreshold || contentHeight <= maxHeight) {
      _lastRevealSignature = null;
      return _AgentList(agents: widget.agents, selectedAgentKey: widget.selectedAgentKey, onAgentSelected: widget.onAgentSelected);
    }

    _scheduleSelectedAgentReveal();

    return SizedBox(
      height: maxHeight,
      child: _SidepaneScrollViewport.separated(
        controller: _scrollController,
        viewportKey: _scrollRegionKey,
        itemCount: widget.agents.length,
        gap: _agentListGap,
        expand: false,
        topPadding: _sidepaneListTopHoverClearance,
        itemBuilder: (context, index) {
          final agent = widget.agents[index];

          return KeyedSubtree(
            key: _keyForAgent(agent.identity),
            child: PbAgentCard(
              data: agent.copyWith(selected: agent.identity == widget.selectedAgentKey),
              onPressed: () => widget.onAgentSelected(agent),
            ),
          );
        },
      ),
    );
  }

  GlobalKey _keyForAgent(String title) {
    return _agentKeys.putIfAbsent(title, GlobalKey.new);
  }

  void _scheduleSelectedAgentReveal() {
    final selectedIndex = widget.agents.indexWhere((agent) => agent.identity == widget.selectedAgentKey);
    if (selectedIndex == -1) {
      _lastRevealSignature = null;
      return;
    }

    final revealSignature = '${widget.selectedAgentKey}:${widget.agents.length}:${widget.expanded}';
    if (_lastRevealSignature == revealSignature) {
      return;
    }
    _lastRevealSignature = revealSignature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      if (!_revealBuiltSelectedAgent(widget.selectedAgentKey)) {
        _jumpToEstimatedSelectedAgent(selectedIndex);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _revealBuiltSelectedAgent(widget.selectedAgentKey);
          }
        });
      }
    });
  }

  bool _revealBuiltSelectedAgent(String selectedKey) {
    final context = _agentKeys[selectedKey]?.currentContext;
    final scrollRegionContext = _scrollRegionKey.currentContext;

    if (context == null || scrollRegionContext == null) {
      return false;
    }

    final selectedBox = context.findRenderObject();
    final scrollRegionBox = scrollRegionContext.findRenderObject();

    if (selectedBox is! RenderBox || scrollRegionBox is! RenderBox) {
      return false;
    }

    final selectedOffset = selectedBox.localToGlobal(Offset.zero);
    final scrollRegionOffset = scrollRegionBox.localToGlobal(Offset.zero);
    final selectedTop = selectedOffset.dy;
    final selectedBottom = selectedTop + selectedBox.size.height;
    final topEdge = scrollRegionOffset.dy + _selectedRevealInset;
    final bottomEdge = scrollRegionOffset.dy + scrollRegionBox.size.height - _selectedRevealInset;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;

    if (selectedTop < topEdge) {
      _scrollController.jumpTo((_scrollController.offset + selectedTop - topEdge).clamp(0, maxScrollExtent));
      return true;
    }

    if (selectedBottom > bottomEdge) {
      _scrollController.jumpTo((_scrollController.offset + selectedBottom - bottomEdge).clamp(0, maxScrollExtent));
    }

    return true;
  }

  void _jumpToEstimatedSelectedAgent(int selectedIndex) {
    final scrollRegionContext = _scrollRegionKey.currentContext;
    final scrollRegionBox = scrollRegionContext?.findRenderObject();
    if (scrollRegionBox is! RenderBox) {
      return;
    }

    final selectedTop = _sidepaneListTopHoverClearance + (selectedIndex * (_agentCardMinHeight + _agentListGap));
    final selectedBottom = selectedTop + _agentCardMinHeight;
    final visibleTop = _scrollController.offset + _selectedRevealInset;
    final visibleBottom = _scrollController.offset + scrollRegionBox.size.height - _selectedRevealInset;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;

    if (selectedTop < visibleTop) {
      _scrollController.jumpTo((selectedTop - _selectedRevealInset).clamp(0, maxScrollExtent));
      return;
    }

    if (selectedBottom > visibleBottom) {
      _scrollController.jumpTo((selectedBottom - scrollRegionBox.size.height + _selectedRevealInset).clamp(0, maxScrollExtent));
    }
  }

  double _agentListHeight(int count) {
    if (count <= 0) {
      return 0;
    }

    return _sidepaneListTopHoverClearance + (_agentCardMinHeight * count) + (_agentListGap * (count - 1));
  }

  double _agentListMaxHeight(double panelHeight) {
    final dividerTarget = panelHeight * _sidepaneDividerMaxHeightFactor;
    const fixedHeightBeforeDivider =
        _sidepaneDescriptionHeight +
        _sidepaneDescriptionToListGap +
        _sidepaneListToActionsGap +
        _sidepaneActionsHeight +
        _sidepaneActionsToDividerGap;
    final minimumScrollableHeight = _agentListHeight(_agentListScrollThreshold);

    return (dividerTarget - fixedHeightBeforeDivider).clamp(minimumScrollableHeight, double.infinity);
  }
}

class _AgentList extends StatelessWidget {
  const _AgentList({required this.agents, required this.selectedAgentKey, required this.onAgentSelected});

  final List<PbAgentListItemData> agents;
  final String selectedAgentKey;
  final ValueChanged<PbAgentListItemData> onAgentSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: _sidepaneListTopHoverClearance),
        child: Column(
          children: [
            for (var i = 0; i < agents.length; i++) ...[
              PbAgentCard(
                data: agents[i].copyWith(selected: agents[i].identity == selectedAgentKey),
                onPressed: () => onAgentSelected(agents[i]),
              ),
              if (i != agents.length - 1) const SizedBox(height: _agentListGap),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgentActions extends StatelessWidget {
  const _AgentActions({required this.expanded, required this.canToggleExpanded, this.onManageAgents, required this.onToggleExpanded});

  final bool expanded;
  final bool canToggleExpanded;
  final VoidCallback? onManageAgents;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        PbTertiaryButton.solid(label: 'Manage', onPressed: onManageAgents),
        if (canToggleExpanded) PbTertiaryButton(label: expanded ? 'Show less' : 'Show more', onPressed: onToggleExpanded),
      ],
    );
  }
}

class _ThreadsSection extends StatefulWidget {
  const _ThreadsSection({
    required this.threads,
    this.threadItems,
    this.selectedThreadId,
    required this.selectedThread,
    required this.compactLayout,
    required this.onCreateThread,
    required this.onThreadSelected,
    this.onThreadItemSelected,
    this.onThreadRename,
    this.onThreadDelete,
  });

  final List<String> threads;
  final List<PbThreadListItemData>? threadItems;
  final String? selectedThreadId;
  final String? selectedThread;
  final bool compactLayout;
  final VoidCallback onCreateThread;
  final ValueChanged<String> onThreadSelected;
  final ValueChanged<PbThreadListItemData>? onThreadItemSelected;
  final ValueChanged<PbThreadListItemData>? onThreadRename;
  final ValueChanged<PbThreadListItemData>? onThreadDelete;

  @override
  State<_ThreadsSection> createState() => _ThreadsSectionState();
}

class _ThreadsSectionState extends State<_ThreadsSection> {
  static const double _selectedRevealInset = 12;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _scrollRegionKey = GlobalKey();
  final Map<String, GlobalKey> _threadKeys = {};
  String? _lastRevealSignature;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threadItems = widget.threadItems ?? [for (final thread in widget.threads) PbThreadListItemData(id: thread, title: thread)];
    if (widget.compactLayout || widget.selectedThread == null) {
      _lastRevealSignature = null;
    } else {
      _scheduleSelectedThreadReveal(threadItems);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: widget.compactLayout ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Text('Threads', style: PowerboardsTypography.label),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.only(bottom: 6), child: _newThreadChip()),
        if (widget.compactLayout)
          for (var i = 0; i < threadItems.length; i++) ...[
            _threadChip(threadItems[i]),
            if (i != threadItems.length - 1) const SizedBox(height: 8),
          ]
        else
          _SidepaneScrollViewport.separated(
            controller: _scrollController,
            viewportKey: _scrollRegionKey,
            itemCount: threadItems.length,
            gap: 8,
            itemBuilder: (context, index) {
              final thread = threadItems[index];

              return KeyedSubtree(key: _keyForThread(thread.id), child: _threadChip(thread));
            },
          ),
      ],
    );
  }

  Widget _newThreadChip() {
    return PbThreadChip(title: 'New Thread...', create: true, selected: widget.selectedThread == null, onPressed: widget.onCreateThread);
  }

  Widget _threadChip(PbThreadListItemData thread) {
    final selectedThreadId = widget.selectedThreadId;
    final selected = selectedThreadId == null ? thread.title == widget.selectedThread : thread.id == selectedThreadId;
    final actionsEnabled = thread.actionsEnabled;

    return PbThreadChip(
      title: thread.title,
      selected: selected,
      onPressed: () {
        widget.onThreadSelected(thread.title);
        widget.onThreadItemSelected?.call(thread);
      },
      onRename: !actionsEnabled || widget.onThreadRename == null ? null : () => widget.onThreadRename!(thread),
      onDelete: !actionsEnabled || widget.onThreadDelete == null ? null : () => widget.onThreadDelete!(thread),
    );
  }

  GlobalKey _keyForThread(String title) {
    return _threadKeys.putIfAbsent(title, GlobalKey.new);
  }

  void _scheduleSelectedThreadReveal(List<PbThreadListItemData> threads) {
    final selectedThreadId = widget.selectedThreadId;
    final selectedThread = selectedThreadId ?? widget.selectedThread;
    String? selectedKey = selectedThreadId;
    if (selectedKey == null) {
      for (final thread in threads) {
        if (thread.title == selectedThread) {
          selectedKey = thread.id;
          break;
        }
      }
    }
    if (selectedThread == null || selectedKey == null || !threads.any((thread) => thread.id == selectedKey)) {
      _lastRevealSignature = null;
      return;
    }

    final revealSignature = '$selectedKey:${threads.length}:${widget.compactLayout}';
    if (_lastRevealSignature == revealSignature) {
      return;
    }
    _lastRevealSignature = revealSignature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      final context = _threadKeys[selectedKey]?.currentContext;
      final scrollRegionContext = _scrollRegionKey.currentContext;

      if (context == null || scrollRegionContext == null) {
        return;
      }

      final selectedBox = context.findRenderObject();
      final scrollRegionBox = scrollRegionContext.findRenderObject();

      if (selectedBox is! RenderBox || scrollRegionBox is! RenderBox) {
        return;
      }

      final selectedOffset = selectedBox.localToGlobal(Offset.zero);
      final scrollRegionOffset = scrollRegionBox.localToGlobal(Offset.zero);
      final selectedTop = selectedOffset.dy;
      final selectedBottom = selectedTop + selectedBox.size.height;
      final topEdge = scrollRegionOffset.dy + _selectedRevealInset;
      final bottomEdge = scrollRegionOffset.dy + scrollRegionBox.size.height - _selectedRevealInset;
      final maxScrollExtent = _scrollController.position.maxScrollExtent;

      if (selectedTop < topEdge) {
        _scrollController.jumpTo((_scrollController.offset + selectedTop - topEdge).clamp(0, maxScrollExtent));
        return;
      }

      if (selectedBottom > bottomEdge) {
        _scrollController.jumpTo((_scrollController.offset + selectedBottom - bottomEdge).clamp(0, maxScrollExtent));
      }
    });
  }
}

class PbAgentCard extends StatefulWidget {
  const PbAgentCard({super.key, required this.data, this.onPressed});

  final PbAgentListItemData data;
  final VoidCallback? onPressed;

  @override
  State<PbAgentCard> createState() => _PbAgentCardState();
}

class _PbAgentCardState extends State<PbAgentCard> {
  bool _hovered = false;
  bool _hoverSuppressed = false;
  bool _pressed = false;

  Color get _statusColor {
    return switch (widget.data.statusTone) {
      PbAgentStatusTone.online => PbColors.statusOnline,
      PbAgentStatusTone.amber => PbColors.customAmber,
      PbAgentStatusTone.gray => PbColors.customGray,
      PbAgentStatusTone.error => PbColors.alert,
    };
  }

  @override
  Widget build(BuildContext context) {
    final hovered = _hovered && !_hoverSuppressed;
    final lifted = hovered && !_pressed;
    final showSelectionAffordance = !widget.data.selected && (hovered || _pressed);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _hoverSuppressed = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          setState(() {
            _pressed = false;
            _hoverSuppressed = true;
          });
          widget.onPressed?.call();
        },
        child: AnimatedContainer(
          duration: _pressed ? Duration.zero : const Duration(milliseconds: 160),
          curve: Curves.ease,
          transform: Matrix4.translationValues(0, lifted ? -1 : 0, 0),
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: widget.data.selected || _pressed ? PbColors.customStateSelectedSurface : PbColors.surfacePanel,
            gradient: widget.data.selected || _pressed
                ? null
                : const LinearGradient(
                    colors: [PbColors.surfacePanel, PbColors.surfacePanelSoft],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: widget.data.selected || _pressed ? PbColors.customStateSelectedBorder : PbColors.borderSoft),
            boxShadow: _pressed
                ? const [
                    BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.08), blurRadius: 2, offset: Offset(0, 1), blurStyle: BlurStyle.inner),
                  ]
                : lifted
                ? const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.12), blurRadius: 30, offset: Offset(0, 14))]
                : null,
          ),
          child: Row(
            children: [
              _SideIconFrame(assetName: widget.data.icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            pbDisplayAgentName(widget.data.title),
                            style: PowerboardsTypography.button,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4.5),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: _statusColor),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.data.status,
                            style: PowerboardsTypography.textXSmall.copyWith(fontWeight: FontWeight.w500, color: PbColors.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (widget.data.selected)
                const SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(
                    child: PbSvgIcon(assetName: 'circle-check-big', size: 20, color: PbColors.customBrandInk),
                  ),
                )
              else if (showSelectionAffordance)
                const _GhostIcon(assetName: 'circle', selectionAffordance: true)
              else
                const SizedBox(width: 38, height: 38),
            ],
          ),
        ),
      ),
    );
  }
}

class PbThreadChip extends StatefulWidget {
  const PbThreadChip({
    super.key,
    required this.title,
    this.selected = false,
    this.create = false,
    this.onPressed,
    this.onRename,
    this.onDelete,
  });

  final String title;
  final bool selected;
  final bool create;
  final VoidCallback? onPressed;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  State<PbThreadChip> createState() => _PbThreadChipState();
}

class _PbThreadChipState extends State<PbThreadChip> {
  bool _hovered = false;
  bool _hoverSuppressed = false;
  bool _pressed = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final hovered = _hovered && !_hoverSuppressed;
    final lifted = hovered && !_pressed;
    final showHoverShadow = lifted && !_menuOpen;
    final active = widget.selected || _pressed || _menuOpen;
    final selectedBackground = widget.selected || _pressed;
    final selectedBorder = selectedBackground && !_menuOpen;
    final hoverSurface = showHoverShadow;
    final hoverBackground = hoverSurface && !widget.selected;
    final menuOpenBackground = _menuOpen && !widget.selected;
    final showAction = (widget.create && !widget.selected) || _menuOpen || hovered || _pressed;
    final showSelectedMark = widget.selected && !_menuOpen && !hovered && !_pressed;
    final stateDuration = hovered || _pressed || _menuOpen ? const Duration(milliseconds: 160) : Duration.zero;
    final hasThreadActions = widget.onRename != null || widget.onDelete != null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _hoverSuppressed = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          setState(() {
            _pressed = false;
            _hoverSuppressed = true;
          });
          widget.onPressed?.call();
        },
        child: AnimatedContainer(
          duration: _pressed ? Duration.zero : stateDuration,
          curve: Curves.ease,
          transform: Matrix4.translationValues(0, lifted ? -1 : 0, 0),
          constraints: const BoxConstraints(minHeight: 40),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: showHoverShadow
                ? const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.12), blurRadius: 30, offset: Offset(0, 14))]
                : null,
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
            decoration: BoxDecoration(
              color: menuOpenBackground
                  ? PbColors.customMenuOpenSurface
                  : selectedBackground
                  ? PbColors.customStateSelectedSurface
                  : hoverBackground
                  ? PbColors.surfacePanel
                  : Colors.transparent,
              gradient: hoverBackground
                  ? const LinearGradient(
                      colors: [PbColors.surfacePanel, PbColors.surfacePanelSoft],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    )
                  : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _menuOpen
                    ? Colors.transparent
                    : selectedBorder
                    ? PbColors.customStateSelectedBorder
                    : hoverSurface
                    ? PbColors.borderSoft
                    : Colors.transparent,
              ),
              boxShadow: _pressed
                  ? const [
                      BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.08), blurRadius: 2, offset: Offset(0, 1), blurStyle: BlurStyle.inner),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: PowerboardsTypography.button.copyWith(color: active ? PbColors.textPrimary : PbColors.textBody),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 38,
                  height: 38,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity: showSelectedMark ? 1 : 0,
                        child: const PbSvgIcon(assetName: 'circle-check-big', size: 20, color: PbColors.customBrandInk),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity: showAction && (widget.create || hasThreadActions) ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !showAction || (!widget.create && !hasThreadActions),
                          child: widget.create
                              ? const _GhostIcon(assetName: 'plus', color: PbColors.textPrimary, opacity: 1)
                              : hasThreadActions
                              ? PbSidepaneItemMenu(
                                  onOpenChanged: (open) => setState(() => _menuOpen = open),
                                  panelBuilder: (closeMenu) =>
                                      PbThreadItemMenu(onRename: widget.onRename, onDelete: widget.onDelete, onDismiss: closeMenu),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilesPanel extends StatelessWidget {
  const _FilesPanel({
    required this.attachments,
    required this.description,
    required this.emptyState,
    required this.onPreviewFile,
    this.onAskFileAgent,
    this.onShareFile,
    this.onExtractArchiveFile,
    this.onDownloadFile,
    this.onSaveFileCopyAs,
  });

  final List<PbAttachmentListItemData> attachments;
  final String description;
  final PbSidepaneFileEmptyStateData emptyState;
  final ValueChanged<PbAttachmentListItemData> onPreviewFile;
  final ValueChanged<PbAttachmentListItemData>? onAskFileAgent;
  final ValueChanged<PbAttachmentListItemData>? onShareFile;
  final ValueChanged<PbAttachmentListItemData>? onExtractArchiveFile;
  final ValueChanged<PbAttachmentListItemData>? onDownloadFile;
  final ValueChanged<PbAttachmentListItemData>? onSaveFileCopyAs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoomPanelDescription(description),
        const SizedBox(height: 20),
        _AttachmentList(
          attachments: attachments,
          emptyState: emptyState,
          onPreviewFile: onPreviewFile,
          onAskFileAgent: onAskFileAgent,
          onShareFile: onShareFile,
          onExtractArchiveFile: onExtractArchiveFile,
          onDownloadFile: onDownloadFile,
          onSaveFileCopyAs: onSaveFileCopyAs,
        ),
      ],
    );
  }
}

class _AttachmentList extends StatelessWidget {
  const _AttachmentList({
    required this.attachments,
    required this.emptyState,
    required this.onPreviewFile,
    this.onAskFileAgent,
    this.onShareFile,
    this.onExtractArchiveFile,
    this.onDownloadFile,
    this.onSaveFileCopyAs,
  });

  final List<PbAttachmentListItemData> attachments;
  final PbSidepaneFileEmptyStateData emptyState;
  final ValueChanged<PbAttachmentListItemData> onPreviewFile;
  final ValueChanged<PbAttachmentListItemData>? onAskFileAgent;
  final ValueChanged<PbAttachmentListItemData>? onShareFile;
  final ValueChanged<PbAttachmentListItemData>? onExtractArchiveFile;
  final ValueChanged<PbAttachmentListItemData>? onDownloadFile;
  final ValueChanged<PbAttachmentListItemData>? onSaveFileCopyAs;

  @override
  Widget build(BuildContext context) {
    return PbSidepaneFileList(
      files: [
        for (final attachment in attachments)
          PbSidepaneFileListItem(
            data: attachment,
            onPressed: () => onPreviewFile(attachment),
            onAskAgent: !attachment.showAskAgentAction || onAskFileAgent == null ? null : () => onAskFileAgent!(attachment),
            onShare: onShareFile == null ? null : () => onShareFile!(attachment),
            onExtract: onExtractArchiveFile == null || !pbCanExtractArchive(attachment) ? null : () => onExtractArchiveFile!(attachment),
            onDownload: onDownloadFile == null ? null : () => onDownloadFile!(attachment),
            onSaveCopyAs: !attachment.showSaveCopyAsAction || onSaveFileCopyAs == null ? null : () => onSaveFileCopyAs!(attachment),
          ),
      ],
      emptyState: emptyState,
      gap: 10,
      topPadding: _sidepaneListTopHoverClearance,
    );
  }
}

class _SidepaneScrollViewport extends StatelessWidget {
  const _SidepaneScrollViewport.separated({
    required this.itemCount,
    required this.itemBuilder,
    required this.gap,
    this.controller,
    this.expand = true,
    this.topPadding = _sidepaneScrollTopPadding,
    this.viewportKey,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double gap;
  final ScrollController? controller;
  final bool expand;
  final double topPadding;
  final Key? viewportKey;

  @override
  Widget build(BuildContext context) {
    final viewport = LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth + (_sidepaneInlinePadding * 2);

        return OverflowBox(
          alignment: Alignment.center,
          minWidth: viewportWidth,
          maxWidth: viewportWidth,
          minHeight: constraints.maxHeight,
          maxHeight: constraints.maxHeight,
          child: SizedBox(
            key: viewportKey,
            width: viewportWidth,
            height: constraints.maxHeight,
            child: ListView.separated(
              controller: controller,
              clipBehavior: Clip.hardEdge,
              padding: EdgeInsets.fromLTRB(_sidepaneInlinePadding, topPadding, _sidepaneInlinePadding, _sidepaneScrollBottomPadding),
              itemCount: itemCount,
              separatorBuilder: (_, _) => SizedBox(height: gap),
              itemBuilder: itemBuilder,
            ),
          ),
        );
      },
    );

    return expand ? Expanded(child: viewport) : viewport;
  }
}

class PbAttachmentCard extends StatefulWidget {
  const PbAttachmentCard({
    super.key,
    required this.data,
    this.onPressed,
    this.onAskAgent,
    this.onShare,
    this.onExtractArchive,
    this.onDownload,
    this.emptyState = false,
  });

  final PbAttachmentListItemData data;
  final VoidCallback? onPressed;
  final VoidCallback? onAskAgent;
  final VoidCallback? onShare;
  final VoidCallback? onExtractArchive;
  final VoidCallback? onDownload;
  final bool emptyState;

  @override
  State<PbAttachmentCard> createState() => _PbAttachmentCardState();
}

class _PbAttachmentCardState extends State<PbAttachmentCard> {
  bool _hovered = false;
  bool _pressed = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final lifted = !widget.emptyState && _hovered && !_pressed && !_menuOpen;
    final showAction = !widget.emptyState && (_hovered || _pressed || _menuOpen);
    final iconAssetName = widget.emptyState ? 'file-text' : widget.data.iconAssetName;
    final iconColor = widget.emptyState ? PbColors.textSubtle : widget.data.iconColor;

    return MouseRegion(
      cursor: widget.emptyState ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: widget.emptyState ? null : (_) => setState(() => _hovered = true),
      onExit: widget.emptyState
          ? null
          : (_) => setState(() {
              _hovered = false;
              _pressed = false;
            }),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: widget.emptyState ? null : (_) => setState(() => _pressed = true),
        onPointerUp: widget.emptyState ? null : (_) => setState(() => _pressed = false),
        onPointerCancel: widget.emptyState ? null : (_) => setState(() => _pressed = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.emptyState ? null : widget.onPressed,
          child: Transform.translate(
            offset: Offset(0, lifted ? -1 : 0),
            child: AnimatedContainer(
              duration: _pressed ? Duration.zero : const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 68),
              padding: const EdgeInsets.fromLTRB(21, 11, 12, 11),
              decoration: BoxDecoration(
                color: widget.emptyState
                    ? null
                    : _menuOpen
                    ? PbColors.customMenuOpenSurface
                    : _pressed
                    ? PbColors.customStateSelectedSurface
                    : null,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.emptyState
                      ? PbColors.borderSoft.withValues(alpha: 0.92)
                      : _menuOpen
                      ? Colors.transparent
                      : _pressed
                      ? PbColors.customStateSelectedBorder
                      : PbColors.borderSoft,
                ),
                gradient: widget.emptyState
                    ? LinearGradient(
                        colors: [
                          Color.lerp(PbColors.surfacePanel, PbColors.surfacePanelSoft, 0.08)!,
                          PbColors.surfacePanelSoft.withValues(alpha: 0.96),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      )
                    : _menuOpen || _pressed
                    ? null
                    : const LinearGradient(
                        colors: [PbColors.surfacePanel, PbColors.surfacePanelSoft],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                boxShadow: widget.emptyState
                    ? null
                    : _menuOpen
                    ? null
                    : _pressed
                    ? const [
                        BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.08), blurRadius: 2, offset: Offset(0, 1), blurStyle: BlurStyle.inner),
                      ]
                    : lifted
                    ? const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.12), blurRadius: 30, offset: Offset(0, 14))]
                    : null,
              ),
              child: Row(
                children: [
                  PbSvgIcon(assetName: iconAssetName, size: 28, color: iconColor),
                  const SizedBox(width: 23),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.data.title,
                          style: widget.emptyState ? PowerboardsTypography.listEmptyState : PowerboardsTypography.button,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4.5),
                        Text(
                          widget.data.subtitle,
                          style: PowerboardsTypography.textXSmall.copyWith(
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: widget.emptyState ? PbColors.textSubtle : PbColors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!widget.emptyState) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity: showAction ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !showAction,
                          child: PbSidepaneItemMenu(
                            onOpenChanged: (open) => setState(() => _menuOpen = open),
                            panelBuilder: (closeMenu) => PbFileItemMenu(
                              onOpen: widget.onPressed,
                              onAskAgent: widget.onAskAgent,
                              onExtract: widget.onExtractArchive,
                              onDownload: widget.onDownload,
                              onDismiss: closeMenu,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _FilePreviewContentMode {
  editableDocument,
  code,
  image,
  video,
  pagedDocument,
  transcript,
  thread;

  static _FilePreviewContentMode fromFile(PbAttachmentListItemData file) {
    return switch (file.fileType) {
      PbAttachmentFileType.codeGeneric ||
      PbAttachmentFileType.script ||
      PbAttachmentFileType.code ||
      PbAttachmentFileType.key ||
      PbAttachmentFileType.settings => _FilePreviewContentMode.code,
      PbAttachmentFileType.image => _FilePreviewContentMode.image,
      PbAttachmentFileType.video ||
      PbAttachmentFileType.mediaGeneric ||
      PbAttachmentFileType.sound ||
      PbAttachmentFileType.music => _FilePreviewContentMode.video,
      PbAttachmentFileType.pdf || PbAttachmentFileType.presentation => _FilePreviewContentMode.pagedDocument,
      PbAttachmentFileType.transcript => _FilePreviewContentMode.transcript,
      PbAttachmentFileType.thread => _FilePreviewContentMode.thread,
      _ => _FilePreviewContentMode.editableDocument,
    };
  }

  bool get hasHeaderSaveAction {
    return switch (this) {
      _FilePreviewContentMode.editableDocument || _FilePreviewContentMode.code => true,
      _ => false,
    };
  }

  bool get usesEdgeToEdgeSurface {
    return switch (this) {
      _FilePreviewContentMode.editableDocument ||
      _FilePreviewContentMode.code ||
      _FilePreviewContentMode.image ||
      _FilePreviewContentMode.video ||
      _FilePreviewContentMode.pagedDocument ||
      _FilePreviewContentMode.transcript ||
      _FilePreviewContentMode.thread => true,
    };
  }
}

class PbFilePreviewSource {
  const PbFilePreviewSource({
    this.child,
    this.childBuilder,
    this.loadText,
    this.saveText,
    this.headerLeading,
    this.hideToolbarActions = false,
    this.onSave,
    this.sourceKey,
  });

  final Widget? child;
  final Widget Function(bool fullscreen)? childBuilder;
  final Future<String> Function()? loadText;
  final Future<void> Function(String text)? saveText;
  final Widget? headerLeading;
  final bool hideToolbarActions;
  final Future<void> Function()? onSave;
  final Object? sourceKey;

  Widget? buildChild(bool fullscreen) {
    return childBuilder?.call(fullscreen) ?? child;
  }
}

class PbFilePreviewPane extends StatefulWidget {
  const PbFilePreviewPane({
    super.key,
    required this.file,
    required this.fullscreen,
    this.resizing = false,
    this.borderOnTop = false,
    this.showInlineBorder = true,
    this.hideFullscreenToggle = false,
    this.child,
    this.previewContentChild,
    this.loadText,
    this.headerLeading,
    this.hideToolbarActions = false,
    this.onAskAgent,
    this.onShare,
    this.showExtractArchive = false,
    this.extractArchiveDisabled = false,
    this.onExtractArchive,
    this.onDownload,
    this.onSave,
    this.onToggleFullscreen,
    this.onClose,
    this.onSaveRequested,
    this.onSaveTextRequested,
    this.sourceKey,
    this.draftText,
    this.draftDirty,
    this.onDraftTextChanged,
    this.onDraftSaved,
  });

  final PbAttachmentListItemData file;
  final bool fullscreen;
  final bool resizing;
  final bool borderOnTop;
  final bool showInlineBorder;
  final bool hideFullscreenToggle;
  final Widget? child;
  final Widget? previewContentChild;
  final Future<String> Function()? loadText;
  final Widget? headerLeading;
  final bool hideToolbarActions;
  final VoidCallback? onAskAgent;
  final VoidCallback? onShare;
  final bool showExtractArchive;
  final bool extractArchiveDisabled;
  final VoidCallback? onExtractArchive;
  final VoidCallback? onDownload;
  final Future<void> Function()? onSave;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onClose;
  final Future<void> Function()? onSaveRequested;
  final Future<void> Function(String text)? onSaveTextRequested;
  final Object? sourceKey;
  final String? draftText;
  final bool? draftDirty;
  final ValueChanged<String>? onDraftTextChanged;
  final VoidCallback? onDraftSaved;

  @override
  State<PbFilePreviewPane> createState() => _PbFilePreviewPaneState();
}

class _PbFilePreviewPaneState extends State<PbFilePreviewPane> {
  bool _dirty = false;
  bool _saving = false;
  String? _editedText;

  static const _stateAlignment = Alignment.center;
  static const _localSaveProcessingStep = Duration(milliseconds: 850);

  bool get _effectiveDirty => widget.draftDirty ?? _dirty;

  String? get _effectiveEditedText => widget.draftDirty == null ? _editedText : widget.draftText;

  @override
  void didUpdateWidget(covariant PbFilePreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.file.title != widget.file.title ||
        oldWidget.file.path != widget.file.path ||
        oldWidget.file.fileType != widget.file.fileType ||
        oldWidget.file.previewState != widget.file.previewState ||
        oldWidget.sourceKey != widget.sourceKey) {
      _dirty = false;
      _saving = false;
      _editedText = null;
    }
  }

  void _updateEditedText(String editedText) {
    if (_saving) {
      return;
    }

    setState(() {
      _dirty = true;
      _editedText = editedText;
    });
    widget.onDraftTextChanged?.call(editedText);
  }

  Future<void> _saveEdits() async {
    if (!_effectiveDirty || _saving) {
      return;
    }

    setState(() => _saving = true);

    try {
      final saveTextRequested = widget.onSaveTextRequested;
      final editedText = _effectiveEditedText;
      final saveRequested = widget.onSaveRequested;
      if (saveTextRequested != null && editedText != null) {
        await saveTextRequested(editedText);
      } else if (saveRequested == null) {
        await Future<void>.delayed(_localSaveProcessingStep);
      } else {
        await saveRequested();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _dirty = false;
      _saving = false;
      _editedText = null;
    });
    widget.onDraftSaved?.call();
  }

  Future<void> _saveSource() async {
    final save = widget.onSave;
    if (save == null || _saving) {
      return;
    }

    setState(() => _saving = true);
    try {
      await save();
    } catch (_) {
      // The source owns any user-facing save error state.
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final fullscreen = widget.fullscreen;
    final previewState = file.previewState;
    final hasPreviewState = previewState != PbAttachmentPreviewState.none;
    final contentMode = _FilePreviewContentMode.fromFile(file);
    final showEditorHeaderSaveAction =
        widget.child == null && widget.previewContentChild == null && !hasPreviewState && contentMode.hasHeaderSaveAction;
    final showSourceHeaderSaveAction = widget.onSave != null;
    final showHeaderSaveAction = showEditorHeaderSaveAction || showSourceHeaderSaveAction;
    final edgeToEdgeSurface =
        !hasPreviewState && (widget.child != null || widget.previewContentChild != null || contentMode.usesEdgeToEdgeSurface);
    final effectiveDirty = _effectiveDirty;
    final effectiveEditedText = _effectiveEditedText;

    return Container(
      padding: fullscreen ? EdgeInsets.zero : const EdgeInsets.fromLTRB(22, 18, 22, 24),
      decoration: BoxDecoration(
        color: PbColors.surfacePanelWash,
        border: fullscreen || !widget.showInlineBorder
            ? null
            : widget.borderOnTop
            ? const Border(top: BorderSide(color: PbColors.borderSoft))
            : const Border(left: BorderSide(color: PbColors.borderSoft)),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final toolbarState = _FilePreviewToolbarState.resolve(
                context,
                width: constraints.maxWidth,
                resizing: widget.resizing,
                hasExtract: widget.showExtractArchive || widget.onExtractArchive != null,
                reservedWidth: showHeaderSaveAction ? _FilePreviewHeaderSaveAction.width(context) + 6 : 0,
              );

              return Container(
                height: fullscreen ? 82 : null,
                padding: fullscreen ? const EdgeInsets.symmetric(horizontal: 28) : EdgeInsets.zero,
                decoration: fullscreen
                    ? const BoxDecoration(
                        border: Border(bottom: BorderSide(color: PbColors.borderSoft)),
                      )
                    : null,
                child: Row(
                  children: [
                    widget.headerLeading ?? PbSvgIcon(assetName: file.iconAssetName, size: 24, color: file.iconColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        file.title,
                        style: fullscreen ? PowerboardsTypography.h4 : PowerboardsTypography.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 7),
                    if (showHeaderSaveAction) ...[
                      _FilePreviewHeaderSaveAction(
                        enabled: showSourceHeaderSaveAction || effectiveDirty,
                        saving: _saving,
                        onPressed: showSourceHeaderSaveAction ? _saveSource : _saveEdits,
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (!widget.hideToolbarActions)
                      _FilePreviewToolbar(
                        state: toolbarState,
                        showAskAgent: file.showAskAgentAction,
                        onAskAgent: widget.onAskAgent,
                        showExtractArchive: widget.showExtractArchive || widget.onExtractArchive != null,
                        extractArchiveDisabled: widget.extractArchiveDisabled,
                        onExtractArchive: widget.onExtractArchive,
                        onDownload: widget.onDownload,
                      ),
                    if (!widget.hideFullscreenToggle)
                      _GhostIcon(assetName: fullscreen ? 'minimize-2' : 'maximize-2', size: 40, onPressed: widget.onToggleFullscreen),
                    _GhostIcon(assetName: 'x', size: 40, onPressed: widget.onClose),
                  ],
                ),
              );
            },
          ),
          if (!fullscreen) const SizedBox(height: 14),
          Expanded(
            child: Container(
              key: const ValueKey('file-preview-content-frame'),
              width: double.infinity,
              margin: fullscreen ? EdgeInsets.zero : null,
              padding: fullscreen || edgeToEdgeSurface ? EdgeInsets.zero : const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(fullscreen ? 0 : 14),
                border: fullscreen ? null : Border.all(color: PbColors.borderSoft),
                gradient: fullscreen || hasPreviewState
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFAFFFFFF), PbColors.surfacePanel],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                color: fullscreen || hasPreviewState ? PbColors.surfacePanelWash : null,
                boxShadow: fullscreen
                    ? null
                    : const [BoxShadow(color: Color.fromRGBO(255, 255, 255, 0.5), blurRadius: 0, offset: Offset(0, 1))],
              ),
              child: hasPreviewState
                  ? Align(
                      alignment: _stateAlignment,
                      child: PbFilePreviewStateCard(
                        file: file,
                        state: previewState,
                        showExtractArchive: widget.showExtractArchive || widget.onExtractArchive != null,
                        extractArchiveDisabled: widget.extractArchiveDisabled,
                        onExtractArchive: widget.onExtractArchive,
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(
                        fullscreen
                            ? 0
                            : edgeToEdgeSurface
                            ? 13
                            : 10,
                      ),
                      child:
                          widget.child ??
                          _FilePreviewContent(
                            file: file,
                            mode: contentMode,
                            fullscreen: fullscreen,
                            previewContentChild: widget.previewContentChild,
                            loadText: widget.loadText,
                            sourceKey: widget.sourceKey,
                            draftText: effectiveEditedText,
                            onEdited: _updateEditedText,
                          ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilePreviewHeaderSaveAction extends StatelessWidget {
  const _FilePreviewHeaderSaveAction({required this.enabled, required this.saving, required this.onPressed});

  final bool enabled;
  final bool saving;
  final VoidCallback onPressed;

  static double width(BuildContext context) {
    double textWidth(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: PowerboardsTypography.button),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    return (14 * 2) + 16 + 8 + math.max(textWidth('Save'), textWidth('Saving'));
  }

  @override
  Widget build(BuildContext context) {
    final active = enabled && !saving;
    final backgroundColor = active ? PbColors.statusPositive : PbColors.surfacePanelSoft;
    final foregroundColor = active ? PbColors.textInverse : PbColors.textSubtle;
    final borderColor = active ? PbColors.statusPositive : PbColors.borderSoft;

    return Semantics(
      button: true,
      enabled: enabled && !saving,
      label: saving ? 'Saving' : 'Save',
      child: IgnorePointer(
        ignoring: !enabled || saving,
        child: PbButton(
          iconAssetName: saving ? 'loader-circle' : 'save',
          iconSpinning: saving,
          label: saving ? 'Saving' : 'Save',
          variant: PbButtonVariant.secondary,
          height: 36,
          horizontalPadding: 14,
          iconSize: 16,
          iconGap: 8,
          backgroundColor: backgroundColor,
          borderColor: borderColor,
          foregroundColor: foregroundColor,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _FilePreviewContent extends StatelessWidget {
  const _FilePreviewContent({
    required this.file,
    required this.mode,
    required this.fullscreen,
    required this.onEdited,
    this.previewContentChild,
    this.loadText,
    this.sourceKey,
    this.draftText,
  });

  final PbAttachmentListItemData file;
  final _FilePreviewContentMode mode;
  final bool fullscreen;
  final ValueChanged<String> onEdited;
  final Widget? previewContentChild;
  final Future<String> Function()? loadText;
  final Object? sourceKey;
  final String? draftText;

  @override
  Widget build(BuildContext context) {
    final child = previewContentChild;
    if (child != null && (mode == _FilePreviewContentMode.editableDocument || mode == _FilePreviewContentMode.code)) {
      return child;
    }

    return switch (mode) {
      _FilePreviewContentMode.editableDocument => _EditableDocumentPreview(
        file: file,
        fullscreen: fullscreen,
        loadText: loadText,
        sourceKey: sourceKey,
        draftText: draftText,
        onEdited: onEdited,
      ),
      _FilePreviewContentMode.code => _CodeFilePreview(
        file: file,
        fullscreen: fullscreen,
        loadText: loadText,
        sourceKey: sourceKey,
        draftText: draftText,
        onEdited: onEdited,
      ),
      _FilePreviewContentMode.image => _ImageFilePreview(child: previewContentChild),
      _FilePreviewContentMode.video => _VideoFilePreview(child: previewContentChild),
      _FilePreviewContentMode.pagedDocument => _PagedFilePreview(fullscreen: fullscreen, file: file, child: previewContentChild),
      _FilePreviewContentMode.transcript => _TranscriptFilePreview(fullscreen: fullscreen, child: previewContentChild),
      _FilePreviewContentMode.thread => _ThreadFilePreview(file: file, fullscreen: fullscreen, child: previewContentChild),
    };
  }
}

class _EditableDocumentPreview extends StatefulWidget {
  const _EditableDocumentPreview({
    required this.file,
    required this.fullscreen,
    required this.onEdited,
    this.loadText,
    this.sourceKey,
    this.draftText,
  });

  final PbAttachmentListItemData file;
  final bool fullscreen;
  final ValueChanged<String> onEdited;
  final Future<String> Function()? loadText;
  final Object? sourceKey;
  final String? draftText;

  @override
  State<_EditableDocumentPreview> createState() => _EditableDocumentPreviewState();
}

const Color _editableDocumentSelectionColor = Color(0x332563EB);
const Color _codeEditorSelectionColor = Color(0x665EA2FF);
const String _editorIndent = '  ';

class _EditorScrollBehavior extends MaterialScrollBehavior {
  const _EditorScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices {
    return {...super.dragDevices}..remove(PointerDeviceKind.mouse);
  }
}

const _editorScrollBehavior = _EditorScrollBehavior();

class _FlushVerticalScrollView extends StatefulWidget {
  const _FlushVerticalScrollView({required this.child, this.padding, this.scrollbarKey});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Key? scrollbarKey;

  @override
  State<_FlushVerticalScrollView> createState() => _FlushVerticalScrollViewState();
}

class _FlushVerticalScrollViewState extends State<_FlushVerticalScrollView> {
  final ScrollController _scrollController = ScrollController();
  bool _hovered = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ScrollConfiguration(
        behavior: _editorScrollBehavior,
        child: Scrollbar(
          key: widget.scrollbarKey,
          controller: _scrollController,
          thumbVisibility: _hovered,
          interactive: true,
          notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
          child: SingleChildScrollView(controller: _scrollController, padding: widget.padding, child: widget.child),
        ),
      ),
    );
  }
}

bool _isEditorTabEvent(KeyEvent event) {
  return event.logicalKey == LogicalKeyboardKey.tab && (event is KeyDownEvent || event is KeyRepeatEvent);
}

bool _previewTextSourceChanged(PbAttachmentListItemData oldFile, PbAttachmentListItemData file, Object? oldSourceKey, Object? sourceKey) {
  return oldSourceKey != sourceKey ||
      oldFile.path != file.path ||
      oldFile.title != file.title ||
      oldFile.fileType != file.fileType ||
      oldFile.previewState != file.previewState;
}

void _setEditorTextPreservingSelection(TextEditingController controller, String text) {
  if (controller.text == text) {
    return;
  }

  final selection = controller.selection;
  final TextSelection nextSelection;
  if (selection.isValid) {
    int clampOffset(int offset) => offset.clamp(0, text.length).toInt();

    nextSelection = TextSelection(
      baseOffset: clampOffset(selection.baseOffset),
      extentOffset: clampOffset(selection.extentOffset),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  } else {
    nextSelection = TextSelection.collapsed(offset: text.length);
  }

  controller.value = TextEditingValue(text: text, selection: nextSelection, composing: TextRange.empty);
}

int _lineStartForOffset(String text, int offset) {
  if (text.isEmpty || offset <= 0) {
    return 0;
  }

  return text.lastIndexOf('\n', math.min(offset, text.length) - 1) + 1;
}

TextEditingValue _insertEditorIndent(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid) {
    return value;
  }

  if (selection.isCollapsed) {
    final offset = selection.start;
    return value.copyWith(
      text: value.text.replaceRange(offset, offset, _editorIndent),
      selection: TextSelection.collapsed(offset: offset + _editorIndent.length),
      composing: TextRange.empty,
    );
  }

  return _indentSelectedLines(value);
}

TextEditingValue _indentSelectedLines(TextEditingValue value) {
  final text = value.text;
  final selection = value.selection;
  final start = selection.start;
  var end = selection.end;
  if (end > start && end <= text.length && text[end - 1] == '\n') {
    end--;
  }

  final blockStart = _lineStartForOffset(text, start);
  final block = text.substring(blockStart, end);
  final lineStarts = <int>[blockStart];
  for (var index = 0; index < block.length; index++) {
    if (block.codeUnitAt(index) == 10 && index + 1 < block.length) {
      lineStarts.add(blockStart + index + 1);
    }
  }

  final indentedBlock = block.split('\n').map((line) => '$_editorIndent$line').join('\n');
  final nextText = text.replaceRange(blockStart, end, indentedBlock);

  int deltaForOffset(int offset) {
    return lineStarts.where((lineStart) => lineStart <= offset).length * _editorIndent.length;
  }

  return value.copyWith(
    text: nextText,
    selection: TextSelection(
      baseOffset: selection.baseOffset + deltaForOffset(selection.baseOffset),
      extentOffset: selection.extentOffset + deltaForOffset(selection.extentOffset),
    ),
    composing: TextRange.empty,
  );
}

TextEditingValue _outdentSelectedLines(TextEditingValue value) {
  final text = value.text;
  final selection = value.selection;
  if (!selection.isValid || text.isEmpty) {
    return value;
  }

  final blockStart = _lineStartForOffset(text, selection.start);
  var blockEnd = selection.end;
  if (selection.isCollapsed) {
    final nextNewline = text.indexOf('\n', selection.end);
    blockEnd = nextNewline == -1 ? text.length : nextNewline;
  } else if (blockEnd > selection.start && blockEnd <= text.length && text[blockEnd - 1] == '\n') {
    blockEnd--;
  }

  final block = text.substring(blockStart, blockEnd);
  final removals = <({int start, int count})>[];
  final lines = block.split('\n');
  final outdented = StringBuffer();
  var lineOffset = blockStart;

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final removeCount = line.startsWith(_editorIndent)
        ? _editorIndent.length
        : line.startsWith('\t') || line.startsWith(' ')
        ? 1
        : 0;
    removals.add((start: lineOffset, count: removeCount));
    outdented.write(line.substring(removeCount));
    if (index != lines.length - 1) {
      outdented.write('\n');
    }
    lineOffset += line.length + 1;
  }

  int removedBefore(int offset) {
    var removed = 0;
    for (final removal in removals) {
      if (removal.count == 0 || offset <= removal.start) {
        continue;
      }

      removed += math.min(removal.count, offset - removal.start);
    }
    return removed;
  }

  return value.copyWith(
    text: text.replaceRange(blockStart, blockEnd, outdented.toString()),
    selection: TextSelection(
      baseOffset: selection.baseOffset - removedBefore(selection.baseOffset),
      extentOffset: selection.extentOffset - removedBefore(selection.extentOffset),
    ),
    composing: TextRange.empty,
  );
}

class _EditableDocumentPreviewState extends State<_EditableDocumentPreview> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _loading = false;
  bool _hovered = false;
  Object? _loadError;
  int _loadGeneration = 0;

  static String _documentTextFor(PbAttachmentListItemData file) {
    return 'The preview shell keeps text-based files inside a controlled '
        'document surface so Powerboards typography can stay consistent across '
        'editable notes, markdown, and plain text.\n\n'
        'Edits use the product body rhythm, and the active save action stays '
        'in the header so the same affordance works in the docked pane and '
        'fullscreen preview.\n\n'
        'Sample checklist\n'
        '- Confirm preview mode\n'
        '- Keep document padding only for editable content\n'
        '- Preserve Inter for authored text';
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode.onKeyEvent = _handleKeyEvent;
    final draftText = widget.draftText;
    if (draftText == null) {
      _loadText();
    } else {
      _controller.text = draftText;
    }
  }

  @override
  void didUpdateWidget(covariant _EditableDocumentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_previewTextSourceChanged(oldWidget.file, widget.file, oldWidget.sourceKey, widget.sourceKey)) {
      _loadText();
      return;
    }

    final draftText = widget.draftText;
    if (draftText != null && draftText != oldWidget.draftText) {
      _setEditorTextPreservingSelection(_controller, draftText);
    }
  }

  Future<void> _loadText() async {
    final generation = ++_loadGeneration;
    final loader = widget.loadText;

    if (loader == null) {
      setState(() {
        _loading = false;
        _loadError = null;
        _setEditorTextPreservingSelection(_controller, _documentTextFor(widget.file));
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final text = await loader();
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _setEditorTextPreservingSelection(_controller, text);
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_isEditorTabEvent(event)) {
      return KeyEventResult.ignored;
    }

    final nextValue = HardwareKeyboard.instance.isShiftPressed
        ? _outdentSelectedLines(_controller.value)
        : _insertEditorIndent(_controller.value);
    _controller.value = nextValue;
    widget.onEdited(nextValue.text);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = widget.fullscreen ? 48.0 : 26.0;
    final verticalPadding = widget.fullscreen ? 40.0 : 28.0;

    Widget statusSurface(Widget child) {
      return Container(color: PbColors.surfacePanel, alignment: Alignment.center, child: child);
    }

    if (_loading) {
      return statusSurface(const CircularProgressIndicator(color: PbColors.textSubtle));
    }

    final loadError = _loadError;
    if (loadError != null) {
      return statusSurface(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Unable to load file: $loadError',
            textAlign: TextAlign.center,
            style: PowerboardsTypography.meta.copyWith(color: PbColors.alert),
          ),
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        color: PbColors.surfacePanel,
        child: ScrollConfiguration(
          behavior: _editorScrollBehavior,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: _hovered,
            interactive: true,
            notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Align(
                alignment: widget.fullscreen ? Alignment.topCenter : Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: widget.fullscreen ? 760 : 680),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding + 20),
                    child: TextSelectionTheme(
                      key: const ValueKey('editable-document-selection-theme'),
                      data: const TextSelectionThemeData(
                        cursorColor: PbColors.textPrimary,
                        selectionColor: _editableDocumentSelectionColor,
                        selectionHandleColor: PbColors.customBlue,
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        cursorColor: PbColors.textPrimary,
                        enableInteractiveSelection: true,
                        keyboardType: TextInputType.multiline,
                        minLines: 14,
                        maxLines: null,
                        onChanged: widget.onEdited,
                        style: PowerboardsTypography.p,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Type here',
                          hintStyle: PowerboardsTypography.p.copyWith(color: PbColors.textMuted),
                          isCollapsed: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeFilePreview extends StatefulWidget {
  const _CodeFilePreview({
    required this.file,
    required this.fullscreen,
    required this.onEdited,
    this.loadText,
    this.sourceKey,
    this.draftText,
  });

  final PbAttachmentListItemData file;
  final bool fullscreen;
  final ValueChanged<String> onEdited;
  final Future<String> Function()? loadText;
  final Object? sourceKey;
  final String? draftText;

  static const List<List<_CodeToken>> _dartLines = [
    [
      _CodeToken('import', _CodeTokenTone.keyword),
      _CodeToken(' '),
      _CodeToken("'package:flutter/material.dart'", _CodeTokenTone.string),
      _CodeToken(';'),
    ],
    [],
    [_CodeToken('class', _CodeTokenTone.keyword), _CodeToken(' '), _CodeToken('PreviewRule', _CodeTokenTone.type), _CodeToken(' {')],
    [_CodeToken('  const', _CodeTokenTone.keyword), _CodeToken(' '), _CodeToken('PreviewRule', _CodeTokenTone.type), _CodeToken('({')],
    [_CodeToken('    required', _CodeTokenTone.keyword), _CodeToken(' '), _CodeToken('this', _CodeTokenTone.keyword), _CodeToken('.mode,')],
    [
      _CodeToken('    required', _CodeTokenTone.keyword),
      _CodeToken(' '),
      _CodeToken('this', _CodeTokenTone.keyword),
      _CodeToken('.edgeToEdge,'),
    ],
    [_CodeToken('  });')],
    [],
    [_CodeToken('  final', _CodeTokenTone.keyword), _CodeToken(' '), _CodeToken('String', _CodeTokenTone.type), _CodeToken(' mode;')],
    [_CodeToken('  final', _CodeTokenTone.keyword), _CodeToken(' '), _CodeToken('bool', _CodeTokenTone.type), _CodeToken(' edgeToEdge;')],
    [_CodeToken('}')],
    [],
    [_CodeToken('final', _CodeTokenTone.keyword), _CodeToken(' rules = [')],
    [
      _CodeToken('  PreviewRule', _CodeTokenTone.type),
      _CodeToken('(mode: '),
      _CodeToken("'editableText'", _CodeTokenTone.string),
      _CodeToken(', edgeToEdge: '),
      _CodeToken('false', _CodeTokenTone.literal),
      _CodeToken('),'),
    ],
    [
      _CodeToken('  PreviewRule', _CodeTokenTone.type),
      _CodeToken('(mode: '),
      _CodeToken("'media'", _CodeTokenTone.string),
      _CodeToken(', edgeToEdge: '),
      _CodeToken('true', _CodeTokenTone.literal),
      _CodeToken('),'),
    ],
    [
      _CodeToken('  PreviewRule', _CodeTokenTone.type),
      _CodeToken('(mode: '),
      _CodeToken("'pagedDocument'", _CodeTokenTone.string),
      _CodeToken(', edgeToEdge: '),
      _CodeToken('true', _CodeTokenTone.literal),
      _CodeToken('),'),
    ],
    [_CodeToken('];')],
  ];

  static const List<List<_CodeToken>> _jsonLines = [
    [_CodeToken('{')],
    [_CodeToken('  "previewMode"', _CodeTokenTone.string), _CodeToken(': '), _CodeToken('"media"', _CodeTokenTone.string), _CodeToken(',')],
    [_CodeToken('  "edgeToEdge"', _CodeTokenTone.string), _CodeToken(': '), _CodeToken('true', _CodeTokenTone.literal), _CodeToken(',')],
    [_CodeToken('  "zoom"', _CodeTokenTone.string), _CodeToken(': '), _CodeToken('1.25', _CodeTokenTone.number)],
    [_CodeToken('}')],
  ];

  static const List<List<_CodeToken>> _yamlLines = [
    [_CodeToken('previewMode', _CodeTokenTone.attribute), _CodeToken(': '), _CodeToken('media', _CodeTokenTone.string)],
    [_CodeToken('edgeToEdge', _CodeTokenTone.attribute), _CodeToken(': '), _CodeToken('true', _CodeTokenTone.literal)],
    [_CodeToken('fitModes', _CodeTokenTone.attribute), _CodeToken(':')],
    [_CodeToken('  - '), _CodeToken('fit', _CodeTokenTone.string)],
    [_CodeToken('  - '), _CodeToken('actualSize', _CodeTokenTone.string)],
  ];

  static const List<List<_CodeToken>> _shellLines = [
    [_CodeToken('#!/usr/bin/env bash', _CodeTokenTone.comment)],
    [_CodeToken('set', _CodeTokenTone.keyword), _CodeToken(' -euo pipefail')],
    [],
    [_CodeToken('flutter', _CodeTokenTone.command), _CodeToken(' test '), _CodeToken('test/widget_test.dart', _CodeTokenTone.string)],
    [_CodeToken('echo', _CodeTokenTone.command), _CodeToken(' '), _CodeToken('"Preview checks complete"', _CodeTokenTone.string)],
  ];

  static List<List<_CodeToken>> _linesFor(String title) {
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.endsWith('.json')) {
      return _jsonLines;
    }
    if (lowerTitle.endsWith('.yaml') || lowerTitle.endsWith('.yml')) {
      return _yamlLines;
    }
    if (lowerTitle.endsWith('.sh')) {
      return _shellLines;
    }
    return _dartLines;
  }

  static String _plainTextFor(String title) {
    return _linesFor(title).map((line) => line.map((token) => token.text).join()).join('\n');
  }

  @override
  State<_CodeFilePreview> createState() => _CodeFilePreviewState();
}

class _CodeFilePreviewState extends State<_CodeFilePreview> {
  static const _codePreviewSurfaceKey = ValueKey('code-preview-surface');
  static const _codeGutterWidth = 28.0;
  static const _codeGutterGap = 12.0;
  static const _averageCodeGlyphWidth = 9.0;

  late final _CodeTextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  bool _loading = false;
  bool _hovered = false;
  bool _wordWrap = false;
  Object? _loadError;
  int _loadGeneration = 0;

  int get _lineCount => _controller.text.split('\n').length;

  int get _longestLineLength {
    return _controller.text.split('\n').fold(0, (longest, line) => math.max(longest, line.length));
  }

  List<double> _lineHeights({
    required TextStyle style,
    required double lineHeight,
    required double codeWidth,
    required TextDirection textDirection,
    required TextScaler textScaler,
  }) {
    if (!_wordWrap) {
      return List<double>.filled(_lineCount, lineHeight);
    }

    return _controller.text
        .split('\n')
        .map((line) {
          if (line.isEmpty) {
            return lineHeight;
          }

          final painter = TextPainter(
            text: TextSpan(text: line, style: style),
            textDirection: textDirection,
            textScaler: textScaler,
          )..layout(maxWidth: codeWidth);
          final height = math.max(lineHeight, painter.height);
          painter.dispose();
          return height;
        })
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _controller = _CodeTextEditingController(text: '');
    _focusNode.onKeyEvent = _handleKeyEvent;
    final draftText = widget.draftText;
    if (draftText == null) {
      _loadText();
    } else {
      _controller.text = draftText;
    }
  }

  @override
  void didUpdateWidget(covariant _CodeFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_previewTextSourceChanged(oldWidget.file, widget.file, oldWidget.sourceKey, widget.sourceKey)) {
      _loadText();
      return;
    }

    final draftText = widget.draftText;
    if (draftText != null && draftText != oldWidget.draftText) {
      _setEditorTextPreservingSelection(_controller, draftText);
    }
  }

  Future<void> _loadText() async {
    final generation = ++_loadGeneration;
    final loader = widget.loadText;

    if (loader == null) {
      setState(() {
        _loading = false;
        _loadError = null;
        _setEditorTextPreservingSelection(_controller, _CodeFilePreview._plainTextFor(widget.file.title));
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final text = await loader();
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _setEditorTextPreservingSelection(_controller, text);
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    widget.onEdited(value);
    setState(() {});
  }

  void _setWordWrap(bool enabled) {
    if (enabled && _horizontalController.hasClients) {
      _horizontalController.jumpTo(0);
    }
    setState(() => _wordWrap = enabled);
  }

  Widget _buildWordWrapControl() {
    return MergeSemantics(
      key: const ValueKey('code-preview-word-wrap-control'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              key: const ValueKey('code-preview-word-wrap-checkbox'),
              value: _wordWrap,
              onChanged: (value) => _setWordWrap(value ?? false),
              activeColor: PbColors.customBlue,
              checkColor: PbColors.textInverse,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: _wordWrap ? PbColors.customBlue : _CodeTokenTone.comment.color, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () => _setWordWrap(!_wordWrap),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                _wordWrap ? 'Word wrap: On' : 'Word wrap: Off',
                style: PowerboardsTypography.button.copyWith(color: _CodeTokenTone.plain.color),
              ),
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_isEditorTabEvent(event)) {
      return KeyEventResult.ignored;
    }

    final nextValue = HardwareKeyboard.instance.isShiftPressed
        ? _outdentSelectedLines(_controller.value)
        : _insertEditorIndent(_controller.value);
    _controller.value = nextValue;
    widget.onEdited(nextValue.text);
    setState(() {});
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final codePadding = widget.fullscreen ? const EdgeInsets.fromLTRB(22, 40, 22, 36) : const EdgeInsets.fromLTRB(10, 24, 10, 22);
    final codeStyle = PowerboardsTypography.customCodeDisplay.copyWith(color: _CodeTokenTone.plain.color);
    final lineHeight = (codeStyle.fontSize ?? 15) * (codeStyle.height ?? (22 / 15));

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        key: _codePreviewSurfaceKey,
        color: PbColors.customCodeSurface,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: PbColors.textInverse))
            : _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Unable to load file: $_loadError',
                    textAlign: TextAlign.center,
                    style: PowerboardsTypography.meta.copyWith(color: PbColors.alert),
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final availableCodeWidth = math.max(
                    1.0,
                    constraints.maxWidth - codePadding.horizontal - _codeGutterWidth - _codeGutterGap,
                  );
                  final codeWidth = _wordWrap
                      ? availableCodeWidth
                      : math.max(math.max(availableCodeWidth, 320.0), (_longestLineLength * _averageCodeGlyphWidth) + 22.0);
                  final lineHeights = _lineHeights(
                    style: codeStyle,
                    lineHeight: lineHeight,
                    codeWidth: codeWidth,
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  );

                  return Column(
                    children: [
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: _editorScrollBehavior,
                          child: Scrollbar(
                            key: const ValueKey('code-preview-horizontal-scrollbar'),
                            controller: _horizontalController,
                            thumbVisibility: _hovered && !_wordWrap,
                            interactive: true,
                            notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
                            child: Scrollbar(
                              key: const ValueKey('code-preview-vertical-scrollbar'),
                              controller: _verticalController,
                              thumbVisibility: _hovered,
                              interactive: true,
                              notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
                              child: SingleChildScrollView(
                                controller: _verticalController,
                                child: Padding(
                                  padding: codePadding,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        key: const ValueKey('code-preview-line-number-gutter'),
                                        width: _codeGutterWidth,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            for (var index = 0; index < _lineCount; index++)
                                              SizedBox(
                                                key: ValueKey('code-preview-line-number-${index + 1}'),
                                                height: lineHeights[index],
                                                child: Text(
                                                  '${index + 1}',
                                                  textAlign: TextAlign.right,
                                                  style: codeStyle.copyWith(color: _CodeTokenTone.comment.color),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: _codeGutterGap),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          controller: _horizontalController,
                                          scrollDirection: Axis.horizontal,
                                          physics: _wordWrap ? const NeverScrollableScrollPhysics() : null,
                                          child: TextSelectionTheme(
                                            key: const ValueKey('code-editor-selection-theme'),
                                            data: const TextSelectionThemeData(
                                              cursorColor: PbColors.textInverse,
                                              selectionColor: _codeEditorSelectionColor,
                                              selectionHandleColor: Color(0xFF5EA2FF),
                                            ),
                                            child: SizedBox(
                                              width: codeWidth,
                                              child: TextField(
                                                controller: _controller,
                                                focusNode: _focusNode,
                                                cursorColor: PbColors.textInverse,
                                                enableInteractiveSelection: true,
                                                keyboardType: TextInputType.multiline,
                                                minLines: _lineCount,
                                                maxLines: null,
                                                onChanged: _handleChanged,
                                                style: codeStyle,
                                                decoration: InputDecoration(
                                                  border: InputBorder.none,
                                                  contentPadding: EdgeInsets.zero,
                                                  hintText: 'Type here',
                                                  hintStyle: codeStyle.copyWith(color: _CodeTokenTone.comment.color),
                                                  isCollapsed: true,
                                                ),
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
                          ),
                        ),
                      ),
                      Container(
                        key: const ValueKey('code-preview-footer'),
                        width: double.infinity,
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.centerLeft,
                        decoration: const BoxDecoration(
                          color: Color(0xFF111827),
                          border: Border(top: BorderSide(color: Color(0xFF334155))),
                        ),
                        child: _buildWordWrapControl(),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

enum _CodeTokenTone {
  plain(Color(0xFFE6EDF7)),
  keyword(Color(0xFFC084FC)),
  type(Color(0xFF7DD3FC)),
  string(Color(0xFFA7F3D0)),
  literal(Color(0xFFFDBA74)),
  number(Color(0xFFF0ABFC)),
  attribute(Color(0xFF93C5FD)),
  comment(Color(0xFF6B7280)),
  command(Color(0xFFFDE68A));

  const _CodeTokenTone(this.color);

  final Color color;
}

class _CodeToken {
  const _CodeToken(this.text, [this.tone = _CodeTokenTone.plain]);

  final String text;
  final _CodeTokenTone tone;
}

class _CodeTextEditingController extends TextEditingController {
  _CodeTextEditingController({required super.text});

  static final RegExp _tokenPattern = RegExp(
    r'''("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|//.*|#.*|\b(?:import|class|const|required|this|final|bool|String|set|true|false|null|return|void|if|else|for|while|extends|async|await)\b|\b(?:flutter|echo)\b|\b\d+(?:\.\d+)?\b|\b[A-Z][A-Za-z0-9_]*\b|\b[A-Za-z_][A-Za-z0-9_-]*(?=:))''',
  );
  static final RegExp _numberPattern = RegExp(r'^\d+(?:\.\d+)?$');
  static final RegExp _typePattern = RegExp(r'^[A-Z][A-Za-z0-9_]*$');
  static const Set<String> _literalTokens = {'true', 'false', 'null'};
  static const Set<String> _commandTokens = {'flutter', 'echo'};

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    return highlightCode(text, style: style);
  }

  static TextSpan highlightCode(String code, {TextStyle? style}) {
    final baseStyle = style ?? PowerboardsTypography.customCodeDisplay;
    final children = <TextSpan>[];
    var currentIndex = 0;

    for (final match in _tokenPattern.allMatches(code)) {
      if (match.start > currentIndex) {
        children.add(
          TextSpan(
            text: code.substring(currentIndex, match.start),
            style: baseStyle.copyWith(color: _CodeTokenTone.plain.color),
          ),
        );
      }

      final token = match.group(0)!;
      children.add(
        TextSpan(
          text: token,
          style: baseStyle.copyWith(color: _toneFor(token).color),
        ),
      );
      currentIndex = match.end;
    }

    if (currentIndex < code.length) {
      children.add(
        TextSpan(
          text: code.substring(currentIndex),
          style: baseStyle.copyWith(color: _CodeTokenTone.plain.color),
        ),
      );
    }

    return TextSpan(style: baseStyle, children: children);
  }

  static _CodeTokenTone _toneFor(String token) {
    if (token.startsWith('//') || token.startsWith('#')) {
      return _CodeTokenTone.comment;
    }
    if (token.startsWith('"') || token.startsWith("'")) {
      return _CodeTokenTone.string;
    }
    if (_literalTokens.contains(token)) {
      return _CodeTokenTone.literal;
    }
    if (_commandTokens.contains(token)) {
      return _CodeTokenTone.command;
    }
    if (_numberPattern.hasMatch(token)) {
      return _CodeTokenTone.number;
    }
    if (_typePattern.hasMatch(token)) {
      return _CodeTokenTone.type;
    }
    if (token.contains('-') || token == 'previewMode' || token == 'fitModes') {
      return _CodeTokenTone.attribute;
    }
    return _CodeTokenTone.keyword;
  }
}

enum _ImagePreviewFitMode {
  fit('Fit'),
  actualSize('Actual size');

  const _ImagePreviewFitMode(this.label);

  final String label;
}

class PbImagePreviewAvailabilityNotification extends Notification {
  const PbImagePreviewAvailabilityNotification({required this.available});

  final bool available;
}

class _ImageFilePreview extends StatefulWidget {
  const _ImageFilePreview({this.child});

  final Widget? child;

  @override
  State<_ImageFilePreview> createState() => _ImageFilePreviewState();
}

class _ImageFilePreviewState extends State<_ImageFilePreview> {
  static const _naturalSize = Size(2520, 4080);
  static const _zoomSteps = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];
  static const _defaultZoomIndex = 2;
  static const _imageViewportKey = ValueKey('image-preview-viewport');
  static const _imageSurfaceKey = ValueKey('image-preview-surface');
  static const _imagePanTransformKey = ValueKey('image-preview-pan-transform');

  _ImagePreviewFitMode _fitMode = _ImagePreviewFitMode.fit;
  int _zoomIndex = _defaultZoomIndex;
  bool _menuOpen = false;
  bool _spacePanActive = false;
  bool _contentAvailable = true;
  Offset _panOffset = Offset.zero;
  final FocusNode _focusNode = FocusNode(debugLabel: 'Image preview pan');
  final GlobalKey _viewportMeasureKey = GlobalKey();

  double get _zoom => _zoomSteps[_zoomIndex];

  String get _controlLabel {
    if (_zoomIndex == _defaultZoomIndex) {
      return _fitMode.label;
    }
    return '${(_zoom * 100).round()}%';
  }

  bool get _canZoomOut {
    final minimumIndex = _fitMode == _ImagePreviewFitMode.fit ? _defaultZoomIndex : 0;
    return _zoomIndex > minimumIndex;
  }

  bool get _canZoomIn => _zoomIndex < _zoomSteps.length - 1;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _zoomOut() {
    if (!_canZoomOut) {
      return;
    }
    setState(() => _zoomIndex = math.max(0, _zoomIndex - 1));
  }

  void _zoomIn() {
    if (!_canZoomIn) {
      return;
    }
    setState(() => _zoomIndex = math.min(_zoomSteps.length - 1, _zoomIndex + 1));
  }

  void _setFitMode(_ImagePreviewFitMode mode) {
    setState(() {
      _fitMode = mode;
      _zoomIndex = _defaultZoomIndex;
      _menuOpen = false;
      _panOffset = Offset.zero;
    });
  }

  Size _contentSize(Size available) {
    if (widget.child != null) {
      final baseSize = switch (_fitMode) {
        _ImagePreviewFitMode.fit => available,
        _ImagePreviewFitMode.actualSize => Size(available.width * 1.16, available.height * 1.16),
      };
      return Size(baseSize.width * _zoom, baseSize.height * _zoom);
    }

    final scale = switch (_fitMode) {
      _ImagePreviewFitMode.fit => math.min(available.width / _naturalSize.width, available.height / _naturalSize.height),
      _ImagePreviewFitMode.actualSize => 1.0,
    };
    final clampedScale = math.max(0.1, scale) * _zoom;
    return Size(_naturalSize.width * clampedScale, _naturalSize.height * clampedScale);
  }

  bool _canPan(Size available, Size content) {
    return content.width > available.width + 1 || content.height > available.height + 1;
  }

  Offset _clampPanOffset(Offset offset, Size available, Size content) {
    final maxX = math.max(0.0, (content.width - available.width) / 2);
    final maxY = math.max(0.0, (content.height - available.height) / 2);
    return Offset(offset.dx.clamp(-maxX, maxX).toDouble(), offset.dy.clamp(-maxY, maxY).toDouble());
  }

  Size _measuredViewportSize(Size fallback) {
    final renderObject = _viewportMeasureKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size;
    }
    return fallback;
  }

  void _syncStoredPanOffset(Offset clampedOffset) {
    if ((_panOffset - clampedOffset).distance < 0.5) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() => _panOffset = clampedOffset);
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent && !_spacePanActive) {
      setState(() => _spacePanActive = true);
    } else if (event is KeyUpEvent && _spacePanActive) {
      setState(() => _spacePanActive = false);
    }

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<PbImagePreviewAvailabilityNotification>(
      onNotification: (notification) {
        if (_contentAvailable != notification.available) {
          setState(() {
            _contentAvailable = notification.available;
            if (!_contentAvailable) {
              _menuOpen = false;
              _panOffset = Offset.zero;
            }
          });
        }
        return true;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: PbColors.surfacePanel,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final available = Size(constraints.maxWidth, constraints.maxHeight);
                  final imageSize = _contentSize(available);
                  final canPan = _contentAvailable && _canPan(available, imageSize);
                  final panOffset = _clampPanOffset(canPan ? _panOffset : Offset.zero, available, imageSize);
                  _syncStoredPanOffset(panOffset);

                  return Focus(
                    focusNode: _focusNode,
                    onKeyEvent: _contentAvailable ? _handleKeyEvent : null,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: _contentAvailable ? (_) => _focusNode.requestFocus() : null,
                      onPanStart: canPan ? (_) => _focusNode.requestFocus() : null,
                      onPanUpdate: canPan
                          ? (details) {
                              final viewportSize = _measuredViewportSize(available);
                              setState(() {
                                _panOffset = _clampPanOffset(_panOffset + details.delta, viewportSize, imageSize);
                              });
                            }
                          : null,
                      child: MouseRegion(
                        cursor: canPan ? (_spacePanActive ? SystemMouseCursors.grabbing : SystemMouseCursors.grab) : MouseCursor.defer,
                        child: SizedBox(
                          key: _imageViewportKey,
                          width: available.width,
                          height: available.height,
                          child: ClipRect(
                            key: _viewportMeasureKey,
                            child: OverflowBox(
                              minWidth: 0,
                              minHeight: 0,
                              maxWidth: double.infinity,
                              maxHeight: double.infinity,
                              alignment: Alignment.center,
                              child: Transform.translate(
                                key: _imagePanTransformKey,
                                offset: panOffset,
                                child: SizedBox(
                                  width: imageSize.width,
                                  height: imageSize.height,
                                  child: widget.child == null
                                      ? CustomPaint(key: _imageSurfaceKey, painter: _SampleImagePainter())
                                      : DecoratedBox(
                                          key: _imageSurfaceKey,
                                          decoration: const BoxDecoration(color: PbColors.surfacePanel),
                                          child: widget.child,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_contentAvailable)
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: _ImagePreviewControlBar(
                fitMode: _fitMode,
                label: _controlLabel,
                menuOpen: _menuOpen,
                canZoomOut: _canZoomOut,
                canZoomIn: _canZoomIn,
                onZoomOut: _zoomOut,
                onZoomIn: _zoomIn,
                onMenuOpenChanged: (open) => setState(() => _menuOpen = open),
                onFitModeSelected: _setFitMode,
              ),
            ),
        ],
      ),
    );
  }
}

class _ImagePreviewControlBar extends StatelessWidget {
  const _ImagePreviewControlBar({
    required this.fitMode,
    required this.label,
    required this.menuOpen,
    required this.canZoomOut,
    required this.canZoomIn,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onMenuOpenChanged,
    required this.onFitModeSelected,
  });

  final _ImagePreviewFitMode fitMode;
  final String label;
  final bool menuOpen;
  final bool canZoomOut;
  final bool canZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final ValueChanged<bool> onMenuOpenChanged;
  final ValueChanged<_ImagePreviewFitMode> onFitModeSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: PbColors.surfacePanel.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: PbColors.borderSoft),
          boxShadow: const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.12), blurRadius: 22, offset: Offset(0, 10))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ImagePreviewZoomButton(assetName: 'zoom-out', enabled: canZoomOut, onPressed: onZoomOut),
            const SizedBox(width: 6),
            SizedBox(
              width: 128,
              child: _ImageFitModeMenu(
                fitMode: fitMode,
                label: label,
                open: menuOpen,
                onOpenChanged: onMenuOpenChanged,
                onFitModeSelected: onFitModeSelected,
              ),
            ),
            const SizedBox(width: 6),
            _ImagePreviewZoomButton(assetName: 'zoom-in', enabled: canZoomIn, onPressed: onZoomIn),
          ],
        ),
      ),
    );
  }
}

class _ImagePreviewZoomButton extends StatelessWidget {
  const _ImagePreviewZoomButton({required this.assetName, required this.enabled, required this.onPressed});

  final String assetName;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onPressed : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: PbSvgIcon(assetName: assetName, size: 18, color: enabled ? PbColors.textPrimary : PbColors.textSubtle),
          ),
        ),
      ),
    );
  }
}

class _ImageFitModeMenu extends StatelessWidget {
  const _ImageFitModeMenu({
    required this.fitMode,
    required this.label,
    required this.open,
    required this.onOpenChanged,
    required this.onFitModeSelected,
  });

  final _ImagePreviewFitMode fitMode;
  final String label;
  final bool open;
  final ValueChanged<bool> onOpenChanged;
  final ValueChanged<_ImagePreviewFitMode> onFitModeSelected;

  @override
  Widget build(BuildContext context) {
    return PbMenuAnchor(
      placement: PbMenuAnchorPlacement.bottomLeft,
      gap: 8,
      onDismiss: () => onOpenChanged(false),
      panel: open
          ? PbMenuCard(
              width: 148,
              child: PbMenuList(
                children: [
                  for (final mode in _ImagePreviewFitMode.values)
                    PbMenuOption(
                      title: mode.label,
                      singleLine: true,
                      selected: mode == fitMode,
                      selectedSurface: mode == fitMode,
                      trailingIconAssetName: mode == fitMode ? 'circle-check-big' : null,
                      onPressed: () => onFitModeSelected(mode),
                    ),
                ],
              ),
            )
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onOpenChanged(!open),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 36,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: open ? PbColors.surfaceStateSelected : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(label, style: PowerboardsTypography.button, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                const PbSvgIcon(assetName: 'chevron-down', size: 16, color: PbColors.textPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SampleImagePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFCFE5FF), Color(0xFFF8FBFF)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, skyPaint);

    final stripePaint = Paint()
      ..color = const Color(0xFFC8D7E8).withValues(alpha: 0.62)
      ..strokeWidth = 2;
    for (final y in [size.height * 0.22, size.height * 0.34, size.height * 0.78]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 8), stripePaint);
    }

    final branchPaint = Paint()
      ..color = const Color(0xFF1F2937)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(size.width * 0.42, size.height * 0.82), Offset(size.width * 0.72, size.height * 0.66), branchPaint);

    final leafPaint = Paint()..color = const Color(0xFF6E8F6C);
    for (final leaf in [
      Offset(size.width * 0.76, size.height * 0.63),
      Offset(size.width * 0.82, size.height * 0.66),
      Offset(size.width * 0.88, size.height * 0.70),
    ]) {
      canvas.drawOval(Rect.fromCenter(center: leaf, width: 34, height: 18), leafPaint);
    }

    canvas.drawCircle(Offset(size.width * 0.04, size.height * 0.98), 42, Paint()..color = PbColors.customRose);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _VideoFilePreview extends StatelessWidget {
  const _VideoFilePreview({this.child});

  final Widget? child;

  static const _videoAspectRatio = 9 / 16;

  @override
  Widget build(BuildContext context) {
    final previewChild = child;
    if (previewChild != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              width: constraints.maxWidth * 0.88,
              height: constraints.maxHeight * 0.88,
              child: ClipRRect(borderRadius: BorderRadius.circular(18), child: previewChild),
            );
          },
        ),
      );
    }

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth * 0.84;
          final maxHeight = constraints.maxHeight * 0.92;
          final widthFromHeight = maxHeight * _videoAspectRatio;
          final frameWidth = math.min(maxWidth, widthFromHeight);
          final frameHeight = frameWidth / _videoAspectRatio;

          return SizedBox(
            width: frameWidth,
            height: frameHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(color: PbColors.surfacePanel, borderRadius: BorderRadius.circular(26)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 28, 22, 18),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Text('8:49', style: PowerboardsTypography.labelSmall),
                                const Spacer(),
                                Container(
                                  width: 42,
                                  height: 10,
                                  decoration: BoxDecoration(color: PbColors.textPrimary, borderRadius: BorderRadius.circular(10)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 70),
                            const Text('Start a new thread', style: PowerboardsTypography.h4),
                            const Spacer(),
                            Container(
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: PbColors.textPrimary),
                              ),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'Type a message or @assistant',
                                style: PowerboardsTypography.meta.copyWith(color: PbColors.textMuted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(color: PbColors.surfaceActionPrimary.withValues(alpha: 0.9), shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const PbSvgIcon(assetName: 'file-play', size: 30, color: PbColors.textInverse),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PagedFilePreview extends StatelessWidget {
  const _PagedFilePreview({required this.fullscreen, required this.file, this.child});

  static const _surfaceColor = Color(0xFFEFF4FB);
  static const _fallbackSurfaceColor = Color(0xFFF2F4F8);

  final bool fullscreen;
  final PbAttachmentListItemData file;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final previewChild = child;
    if (previewChild != null) {
      return _PagedPreviewSurface(fullscreen: fullscreen, flush: file.fileType == PbAttachmentFileType.pdf, child: previewChild);
    }

    return Container(
      color: _fallbackSurfaceColor,
      child: _FlushVerticalScrollView(
        scrollbarKey: const ValueKey('paged-preview-vertical-scrollbar'),
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: fullscreen ? 72 : 16, vertical: fullscreen ? 38 : 18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                children: [
                  _PreviewPage(
                    title: file.fileType == PbAttachmentFileType.presentation ? 'Product Review' : 'Executive Summary',
                    subtitle: 'Prepared for the launch planning workspace preview.',
                  ),
                  const SizedBox(height: 18),
                  const _PreviewPage(title: 'Key Takeaways', subtitle: 'Preview pages own their internal gutters and outlines.'),
                  const SizedBox(height: 18),
                  const _PreviewPage(title: 'Next Steps', subtitle: 'The app shell does not add extra document padding here.'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PagedPreviewSurface extends StatelessWidget {
  const _PagedPreviewSurface({required this.fullscreen, required this.flush, required this.child});

  final bool fullscreen;
  final bool flush;
  final Widget child;

  EdgeInsets get _inset => fullscreen || flush ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 14, 16, 18);

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('paged-preview-surface'),
      color: _PagedFilePreview._surfaceColor,
      child: Stack(
        children: [
          Positioned.fill(
            left: _inset.left,
            top: _inset.top,
            right: _inset.right,
            bottom: _inset.bottom,
            child: ClipRRect(borderRadius: BorderRadius.circular(fullscreen ? 0 : 9), child: child),
          ),
        ],
      ),
    );
  }
}

class _PreviewPage extends StatelessWidget {
  const _PreviewPage({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520 || constraints.maxHeight < 240;
          final tight = constraints.maxHeight < 150;
          final padding = compact ? (tight ? 16.0 : 20.0) : 36.0;
          final titleStyle = compact ? PowerboardsTypography.h4 : PowerboardsTypography.h1;
          final subtitleStyle = compact ? PowerboardsTypography.small : PowerboardsTypography.meta;
          final subtitleLines = tight ? 1 : (compact ? 2 : 3);

          return Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: PbColors.surfacePanel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PbColors.borderSoft),
              boxShadow: const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.06), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: titleStyle, maxLines: 2),
                SizedBox(height: compact ? 8 : 12),
                Text(subtitle, style: subtitleStyle, maxLines: subtitleLines, overflow: TextOverflow.ellipsis),
                const Spacer(),
                Row(
                  children: [
                    for (final label in ['Adoption', 'Factory', 'Bridge']) ...[
                      Expanded(
                        child: Text(
                          label,
                          style: PowerboardsTypography.labelSmall.copyWith(color: PbColors.customBlue),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (label != 'Bridge') const SizedBox(width: 16),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ThreadFilePreview extends StatelessWidget {
  const _ThreadFilePreview({required this.file, required this.fullscreen, this.child});

  final PbAttachmentListItemData file;
  final bool fullscreen;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final previewChild = child;

    if (previewChild != null) {
      return Container(color: PbColors.surfacePanel, child: previewChild);
    }

    return Container(
      key: const ValueKey('thread-preview-surface'),
      color: PbColors.surfacePanel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth ? constraints.maxWidth : 1000.0;
          final stackMaxWidth = width > 1400 ? width * 0.8 : width;
          final sidePadding = width < 760 ? 20.0 : 30.0;
          final messageGap = width < 760 ? 12.0 : 16.0;

          return _FlushVerticalScrollView(
            scrollbarKey: const ValueKey('thread-preview-vertical-scrollbar'),
            padding: EdgeInsets.fromLTRB(sidePadding, 6, sidePadding - 2, 8),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: stackMaxWidth),
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ThreadPreviewMessage(
                        initials: 'JP',
                        speaker: 'Jesse Park',
                        meta: '10:24 AM',
                        text:
                            'Can we make the file preview rules explicit enough that a thread saved as a file still feels like Powerboards?',
                        tone: _ThreadPreviewMessageTone.user,
                        gap: messageGap,
                      ),
                      _ThreadPreviewMessage(
                        speaker: 'Assistant',
                        meta: '10:25 AM',
                        text:
                            'Yes. Thread files should use the preview typography layer, preview surfaces, and the same code-display treatment as code files.',
                        tone: _ThreadPreviewMessageTone.assistant,
                        gap: messageGap,
                      ),
                      _ThreadPreviewMessage(
                        initials: 'JP',
                        speaker: 'Jesse Park',
                        meta: '10:27 AM',
                        text: 'Let us include a tiny code example so the preview proves the mixed-content rule.',
                        code:
                            'final preview = ThreadFilePreview(\n'
                            '  typography: PowerboardsTypography.p,\n'
                            '  codeStyle: PowerboardsTypography.customCodeDisplay,\n'
                            '  usesTokenColors: true,\n'
                            ');',
                        tone: _ThreadPreviewMessageTone.user,
                        gap: messageGap,
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _ThreadPreviewMessageTone { user, assistant }

class _ThreadPreviewMessage extends StatelessWidget {
  const _ThreadPreviewMessage({
    required this.speaker,
    required this.meta,
    required this.text,
    required this.tone,
    this.initials,
    this.code,
    this.gap = 16,
    this.isLast = false,
  });

  final String speaker;
  final String meta;
  final String text;
  final _ThreadPreviewMessageTone tone;
  final String? initials;
  final String? code;
  final double gap;
  final bool isLast;

  bool get _assistant => tone == _ThreadPreviewMessageTone.assistant;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: ValueKey(_assistant ? 'thread-preview-assistant-message-row' : 'thread-preview-user-message-row'),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: PbColors.borderFaint)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ThreadPreviewAvatar(assistant: _assistant, initials: initials ?? 'AI'),
            SizedBox(width: gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                speaker,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PowerboardsTypography.smallStrong.copyWith(color: PbColors.textPrimary),
                              ),
                              if (_assistant) const _ThreadPreviewRolePill(label: 'Agent'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PowerboardsTypography.small.copyWith(color: PbColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Text(text, style: PowerboardsTypography.p),
                  if (code != null) ...[const SizedBox(height: 14), _ThreadPreviewCodeBlock(code: code!)],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadPreviewRolePill extends StatelessWidget {
  const _ThreadPreviewRolePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: PbColors.customBadgeBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PbColors.customBadgeBorder),
      ),
      child: Text(label, style: PowerboardsTypography.badge.copyWith(color: PbColors.customBadgeText)),
    );
  }
}

class _ThreadPreviewAvatar extends StatelessWidget {
  const _ThreadPreviewAvatar({required this.assistant, required this.initials});

  final bool assistant;
  final String initials;

  @override
  Widget build(BuildContext context) {
    if (assistant) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            colors: [PbColors.surfacePanel, PbColors.surfacePanelSoft],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border.all(color: PbColors.borderSoft),
        ),
        alignment: Alignment.center,
        child: Text(initials, style: PowerboardsTypography.customAvatarInitials.copyWith(color: PbColors.customBrandInk)),
      );
    }
    return PbAvatar(initials: initials, size: 40, textStyle: PowerboardsTypography.customAvatarInitials);
  }
}

class _ThreadPreviewCodeBlock extends StatelessWidget {
  const _ThreadPreviewCodeBlock({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final codeStyle = PowerboardsTypography.customCodeDisplay.copyWith(color: _CodeTokenTone.plain.color);

    return Container(
      key: const ValueKey('thread-preview-code-block'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: PbColors.customCodeSurface, borderRadius: BorderRadius.circular(8)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(_CodeTextEditingController.highlightCode(code, style: codeStyle), key: const ValueKey('thread-preview-code-text')),
      ),
    );
  }
}

class PbTranscriptPreviewData {
  const PbTranscriptPreviewData({required this.dateLabel, required this.detailLabel, required this.participants, required this.turns});

  final String dateLabel;
  final String detailLabel;
  final List<PbTranscriptPreviewParticipant> participants;
  final List<PbTranscriptPreviewTurn> turns;
}

class PbTranscriptPreviewParticipant {
  const PbTranscriptPreviewParticipant({required this.label, required this.initials, this.isAgentLike = false});

  final String label;
  final String initials;
  final bool isAgentLike;
}

class PbTranscriptPreviewTurn {
  const PbTranscriptPreviewTurn({required this.timestamp, required this.speaker, required this.text});

  final String timestamp;
  final String speaker;
  final String text;
}

class PbTranscriptPreviewContent extends StatelessWidget {
  const PbTranscriptPreviewContent({super.key, required this.data, required this.fullscreen, this.emptyStateFile});

  final PbTranscriptPreviewData data;
  final bool fullscreen;
  final PbAttachmentListItemData? emptyStateFile;

  @override
  Widget build(BuildContext context) {
    if (data.turns.isEmpty) {
      return Container(
        color: PbColors.surfacePanel,
        alignment: Alignment.center,
        child: PbFilePreviewStateCard(
          file: emptyStateFile ?? PbAttachmentListItemData.fromFileName(title: 'transcript.transcript'),
          state: PbAttachmentPreviewState.unavailable,
          label: 'No transcript available',
        ),
      );
    }

    final padding = fullscreen ? const EdgeInsets.fromLTRB(58, 44, 58, 64) : const EdgeInsets.fromLTRB(32, 30, 32, 42);

    return Container(
      color: PbColors.surfacePanel,
      child: SelectionArea(
        child: _FlushVerticalScrollView(
          scrollbarKey: const ValueKey('transcript-preview-vertical-scrollbar'),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: fullscreen ? 720 : 620),
              child: Padding(
                padding: padding,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final inlineAvatars = constraints.maxWidth >= 430 && data.participants.isNotEmpty;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (inlineAvatars)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _TranscriptHeading(dateLabel: data.dateLabel, detailLabel: data.detailLabel),
                              ),
                              const SizedBox(width: 18),
                              _TranscriptAvatarStack(participants: data.participants),
                            ],
                          )
                        else ...[
                          _TranscriptHeading(dateLabel: data.dateLabel, detailLabel: data.detailLabel),
                          if (data.participants.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _TranscriptAvatarStack(participants: data.participants),
                          ],
                        ],
                        const SizedBox(height: 34),
                        const Divider(color: PbColors.borderSoft),
                        const SizedBox(height: 34),
                        for (final turn in data.turns) _TranscriptTurn(timestamp: turn.timestamp, speaker: turn.speaker, text: turn.text),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TranscriptFilePreview extends StatelessWidget {
  const _TranscriptFilePreview({required this.fullscreen, this.child});

  final bool fullscreen;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final padding = fullscreen ? const EdgeInsets.fromLTRB(58, 44, 58, 64) : const EdgeInsets.fromLTRB(32, 30, 32, 42);
    final previewChild = child;

    if (previewChild != null) {
      return Container(color: PbColors.surfacePanel, child: previewChild);
    }

    return Container(
      color: PbColors.surfacePanel,
      child: _FlushVerticalScrollView(
        scrollbarKey: const ValueKey('transcript-preview-fallback-vertical-scrollbar'),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: fullscreen ? 720 : 620),
            child: Padding(
              padding: padding,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final inlineAvatars = constraints.maxWidth >= 430;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (inlineAvatars)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Expanded(child: _TranscriptHeading()),
                            SizedBox(width: 18),
                            _TranscriptAvatarStack(),
                          ],
                        )
                      else ...[
                        const _TranscriptHeading(),
                        const SizedBox(height: 14),
                        const _TranscriptAvatarStack(),
                      ],
                      const SizedBox(height: 34),
                      const Divider(color: PbColors.borderSoft),
                      const SizedBox(height: 34),
                      const _TranscriptTurn(
                        timestamp: '00:00:00',
                        speaker: 'Dinesh',
                        text: "Hi, I'm checking to see if the transcription works. I turned it on. Can you hear me?",
                      ),
                      const _TranscriptTurn(
                        timestamp: '00:00:00',
                        speaker: 'Assistant voice',
                        text: 'Yes, I can hear you loud and clear. The transcription seems to be working fine.',
                      ),
                      const _TranscriptTurn(
                        timestamp: '00:00:23',
                        speaker: 'Dinesh',
                        text: "I'm trying to see where the transcript is saved so we can find it later.",
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TranscriptHeading extends StatelessWidget {
  const _TranscriptHeading({this.dateLabel = 'March 31, 2026', this.detailLabel = 'Transcript   7:29p - 2 mins'});

  final String dateLabel;
  final String detailLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dateLabel, style: PowerboardsTypography.h1),
        const SizedBox(height: 12),
        Text(detailLabel, style: PowerboardsTypography.large),
      ],
    );
  }
}

class _TranscriptAvatarStack extends StatelessWidget {
  const _TranscriptAvatarStack({
    this.participants = const [
      PbTranscriptPreviewParticipant(label: 'Dinesh', initials: 'DD'),
      PbTranscriptPreviewParticipant(label: 'Assistant', initials: 'AI', isAgentLike: true),
    ],
  });

  static const _avatarSize = 28.0;
  final List<PbTranscriptPreviewParticipant> participants;

  @override
  Widget build(BuildContext context) {
    final visibleParticipants = participants.take(4).toList(growable: false);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < visibleParticipants.length; index++) ...[
          _TranscriptParticipantAvatar(participant: visibleParticipants[index], size: _avatarSize),
          if (index != visibleParticipants.length - 1) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

class _TranscriptParticipantAvatar extends StatelessWidget {
  const _TranscriptParticipantAvatar({required this.participant, required this.size});

  final PbTranscriptPreviewParticipant participant;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (participant.isAgentLike) {
      return Tooltip(
        message: participant.label,
        child: _TranscriptAssistantAvatar(size: size),
      );
    }

    return Tooltip(
      message: participant.label,
      child: PbAvatar(
        initials: participant.initials,
        size: size,
        textStyle: const TextStyle(
          fontFamily: PowerboardsTypography.fontFamily,
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: PbColors.textInverse,
        ),
      ),
    );
  }
}

class _TranscriptAssistantAvatar extends StatelessWidget {
  const _TranscriptAssistantAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [PbColors.surfacePanel, PbColors.surfacePanelSoft],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: PbColors.borderSoft),
      ),
      child: const PbSvgIcon(assetName: 'bot', size: 15, color: PbColors.textPrimary),
    );
  }
}

class _TranscriptTurn extends StatelessWidget {
  const _TranscriptTurn({required this.timestamp, required this.speaker, required this.text});

  final String timestamp;
  final String speaker;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(timestamp, style: PowerboardsTypography.meta.copyWith(color: PbColors.textMuted)),
          const SizedBox(height: 6),
          Text('$speaker:', style: PowerboardsTypography.h4),
          const SizedBox(height: 8),
          Text(text, style: PowerboardsTypography.p),
        ],
      ),
    );
  }
}

enum _FilePreviewToolbarStateId { full, downloadIcon, downloadMenu, allMenu }

enum _FilePreviewAction {
  askAgent('Ask agent', 'message-square-plus'),
  extract(pbArchiveExtractMenuLabel, 'folder-archive'),
  download('Download', 'arrow-down-to-line');

  const _FilePreviewAction(this.label, this.iconAssetName);

  final String label;
  final String iconAssetName;
}

class _FilePreviewToolbarState {
  const _FilePreviewToolbarState({required this.id, required this.iconOnly, required this.inMenu});

  static const _titleFitWidth = 176.0;
  static const _headerGap = 7.0;
  static const _toolbarGap = 6.0;
  static const _buttonInlinePadding = 16.0;
  static const _buttonIconSize = 18.0;
  static const _buttonIconGap = 10.0;
  static const _iconButtonSize = 40.0;

  static const full = _FilePreviewToolbarState(id: _FilePreviewToolbarStateId.full, iconOnly: {}, inMenu: {});
  static const downloadIcon = _FilePreviewToolbarState(
    id: _FilePreviewToolbarStateId.downloadIcon,
    iconOnly: {_FilePreviewAction.download},
    inMenu: {},
  );
  static const downloadMenu = _FilePreviewToolbarState(
    id: _FilePreviewToolbarStateId.downloadMenu,
    iconOnly: {},
    inMenu: {_FilePreviewAction.download},
  );
  static const allMenu = _FilePreviewToolbarState(
    id: _FilePreviewToolbarStateId.allMenu,
    iconOnly: {},
    inMenu: {_FilePreviewAction.download, _FilePreviewAction.extract, _FilePreviewAction.askAgent},
  );

  static const _displayStates = [full, downloadIcon, downloadMenu, allMenu];
  static const _stableStates = [full, downloadMenu, allMenu];

  final _FilePreviewToolbarStateId id;
  final Set<_FilePreviewAction> iconOnly;
  final Set<_FilePreviewAction> inMenu;

  bool isIconOnly(_FilePreviewAction action) => iconOnly.contains(action);
  bool isInMenu(_FilePreviewAction action) => inMenu.contains(action);

  static _FilePreviewToolbarState resolve(
    BuildContext context, {
    required double width,
    required bool resizing,
    required bool hasExtract,
    double reservedWidth = 0,
  }) {
    final states = resizing ? _displayStates : _stableStates;

    for (final state in states) {
      if (_fits(context, width, state, hasExtract: hasExtract, reservedWidth: reservedWidth)) {
        return state;
      }
    }

    return allMenu;
  }

  static bool _fits(
    BuildContext context,
    double width,
    _FilePreviewToolbarState state, {
    required bool hasExtract,
    required double reservedWidth,
  }) {
    final availableTitleWidth = width - _toolbarWidth(context, state, hasExtract: hasExtract) - _headerGap - reservedWidth;
    return availableTitleWidth >= _titleFitWidth;
  }

  static double _toolbarWidth(BuildContext context, _FilePreviewToolbarState state, {required bool hasExtract}) {
    final visibleWidths = <double>[
      for (final action in _FilePreviewAction.values)
        if (action != _FilePreviewAction.extract || hasExtract)
          if (!state.isInMenu(action)) state.isIconOnly(action) ? _iconButtonSize : _buttonWidth(context, action.label),
      if (state.inMenu.isNotEmpty) _iconButtonSize,
      _iconButtonSize,
      _iconButtonSize,
    ];
    final gaps = (visibleWidths.length - 1).clamp(0, double.infinity) * _toolbarGap;

    return visibleWidths.fold<double>(0, (sum, width) => sum + width) + gaps;
  }

  static double _buttonWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: PowerboardsTypography.button),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();

    return (_buttonInlinePadding * 2) + _buttonIconSize + _buttonIconGap + painter.width;
  }
}

class _FilePreviewToolbar extends StatelessWidget {
  const _FilePreviewToolbar({
    required this.state,
    this.showAskAgent = true,
    this.onAskAgent,
    this.showExtractArchive = false,
    this.extractArchiveDisabled = false,
    this.onExtractArchive,
    this.onDownload,
  });

  final _FilePreviewToolbarState state;
  final bool showAskAgent;
  final VoidCallback? onAskAgent;
  final bool showExtractArchive;
  final bool extractArchiveDisabled;
  final VoidCallback? onExtractArchive;
  final VoidCallback? onDownload;

  VoidCallback? _handlerFor(_FilePreviewAction action) {
    return switch (action) {
      _FilePreviewAction.askAgent => onAskAgent,
      _FilePreviewAction.extract => extractArchiveDisabled ? null : onExtractArchive,
      _FilePreviewAction.download => onDownload,
    };
  }

  @override
  Widget build(BuildContext context) {
    final availableActions = [
      if (showAskAgent) _FilePreviewAction.askAgent,
      if (showExtractArchive || onExtractArchive != null) _FilePreviewAction.extract,
      _FilePreviewAction.download,
    ];
    final visibleActions = availableActions.where((action) => !state.isInMenu(action)).toList();

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in visibleActions) ...[
            _FilePreviewActionButton(
              key: ValueKey('${state.id.name}-${action.name}'),
              action: action,
              iconOnly: state.isIconOnly(action),
              onPressed: _handlerFor(action),
            ),
            const SizedBox(width: 6),
          ],
          if (state.inMenu.isNotEmpty) ...[
            PbSidepaneItemMenu(
              size: 40,
              panelBuilder: (closeMenu) => PbFilePreviewPaneOptionsMenu(
                showAskAgent: showAskAgent && state.isInMenu(_FilePreviewAction.askAgent),
                showShare: false,
                showExtract: (showExtractArchive || onExtractArchive != null) && state.isInMenu(_FilePreviewAction.extract),
                showDownload: state.isInMenu(_FilePreviewAction.download),
                onAskAgent: onAskAgent,
                onExtract: extractArchiveDisabled ? null : onExtractArchive,
                onDownload: onDownload,
                onDismiss: closeMenu,
              ),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _FilePreviewActionButton extends StatelessWidget {
  const _FilePreviewActionButton({super.key, required this.action, required this.iconOnly, this.onPressed});

  final _FilePreviewAction action;
  final bool iconOnly;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      child: PbButton(
        key: ValueKey(iconOnly),
        iconAssetName: action.iconAssetName,
        label: action.label,
        variant: PbButtonVariant.secondary,
        iconOnly: iconOnly,
        iconOnlySize: 40,
        height: 36,
        horizontalPadding: 16,
        iconGap: 10,
        onPressed: onPressed,
      ),
    );
  }
}

class _SideIconFrame extends StatelessWidget {
  const _SideIconFrame({required this.assetName});

  final String assetName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: PbColors.surfacePanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PbColors.borderSoft),
      ),
      alignment: Alignment.center,
      child: PbSvgIcon(assetName: assetName, size: 22, color: PbColors.customBrandInk),
    );
  }
}

class _GhostIcon extends StatefulWidget {
  const _GhostIcon({required this.assetName, this.size = 38, this.selectionAffordance = false, this.color, this.opacity, this.onPressed});

  final String assetName;
  final double size;
  final bool selectionAffordance;
  final Color? color;
  final double? opacity;
  final VoidCallback? onPressed;

  @override
  State<_GhostIcon> createState() => _GhostIconState();
}

class _GhostIconState extends State<_GhostIcon> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _pressed;
    final iconColor = widget.color ?? (active || widget.selectionAffordance ? PbColors.customBrandInk : PbColors.customBrandInk);
    final iconOpacity =
        widget.opacity ??
        (active
            ? 1.0
            : widget.selectionAffordance
            ? 0.5
            : 0.3);

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
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              scale: _pressed ? 0.96 : 1,
              child: PbSvgIcon(
                assetName: widget.assetName,
                size: 18,
                color: iconColor.withValues(alpha: iconOpacity),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PbAgentListItemData {
  const PbAgentListItemData({
    this.id,
    required this.title,
    required this.status,
    required this.icon,
    this.statusTone = PbAgentStatusTone.online,
    this.selected = false,
  });

  final String? id;
  final String title;
  final String status;
  final String icon;
  final PbAgentStatusTone statusTone;
  final bool selected;

  String get identity => id ?? title;

  PbAgentListItemData copyWith({String? id, String? title, String? status, String? icon, PbAgentStatusTone? statusTone, bool? selected}) {
    return PbAgentListItemData(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      icon: icon ?? this.icon,
      statusTone: statusTone ?? this.statusTone,
      selected: selected ?? this.selected,
    );
  }
}

class PbThreadListItemData {
  const PbThreadListItemData({required this.id, required this.title, this.actionsEnabled = true});

  final String id;
  final String title;
  final bool actionsEnabled;
}
