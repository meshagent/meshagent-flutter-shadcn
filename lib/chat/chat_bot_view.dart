import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart' show BaseChatClient, MessagingChatClient;
import 'package:shadcn_ui/shadcn_ui.dart';

import 'chat.dart';
import 'conversation_descriptor.dart';
import 'dataset_chat_thread.dart';
import 'multi_thread_view.dart';
import 'thread_list_view.dart';

typedef DatasetChatThreadWrapperBuilder =
    Widget Function(BuildContext context, String path, Widget thread, DatasetChatModelController modelController);
typedef DatasetChatNewThreadWrapperBuilder =
    Widget Function(BuildContext context, Widget newThread, DatasetChatModelController modelController);

class ChatBotView extends StatefulWidget {
  const ChatBotView({
    super.key,
    required this.room,
    this.chatClient,
    this.disposeChatClient = false,
    this.agentName,
    this.threadDisplayMode = ChatThreadDisplayMode.singleThread,
    this.threadDir,
    this.threadListPath,
    this.documentPath,
    this.controller,
    this.selectedThreadPath,
    this.selectedThreadDisplayName,
    this.onSelectedThreadPathChanged,
    this.onSelectedThreadResolved,
    this.onThreadStartActivityChanged,
    this.newThreadResetVersion = 0,
    this.participants,
    this.participantNames,
    this.includeLocalParticipant = true,
    this.startChatCentered = false,
    this.initialMessage,
    this.onMessageSent,
    this.messageHeaderBuilder,
    this.waitingForParticipantsBuilder,
    this.attachmentBuilder,
    this.onAttachmentOpen,
    this.onAttachmentRemoved,
    this.fileInThreadBuilder,
    this.chatInputBoxBuilder,
    this.customInputBuilder,
    this.openFile,
    this.fileDropOverlayBuilder,
    this.toolsBuilder,
    this.inputPlaceholder,
    this.emptyStateTitle,
    this.emptyStateDescription,
    this.emptyState,
    this.inputContextMenuBuilder,
    this.inputOnPressedOutside,
    this.mobileStorageSaveSurfacePresenter,
    this.mobileUnderHeaderContentPadding,
    this.centerComposer = false,
    this.showCenteredComposerTitle = true,
    this.hideChatInput = false,
    this.showThreadList = true,
    this.threadListWidth = 280,
    this.threadListCollapsedHeight = 220,
    this.initialShowCompletedToolCalls = false,
    this.shouldShowAuthorNames = true,
    this.showUsageFooter = false,
    this.datasetThreadWrapperBuilder,
    this.datasetNewThreadWrapperBuilder,
  });

  final RoomClient room;
  final BaseChatClient? chatClient;
  final bool disposeChatClient;
  final String? agentName;
  final ChatThreadDisplayMode threadDisplayMode;
  final String? threadDir;
  final String? threadListPath;
  final String? documentPath;
  final ChatThreadController? controller;
  final String? selectedThreadPath;
  final String? selectedThreadDisplayName;
  final ValueChanged<String?>? onSelectedThreadPathChanged;
  final void Function(String? path, String? displayName)? onSelectedThreadResolved;
  final ValueChanged<bool>? onThreadStartActivityChanged;
  final int newThreadResetVersion;
  final List<Participant>? participants;
  final List<String>? participantNames;
  final bool includeLocalParticipant;
  final bool startChatCentered;
  final ChatMessage? initialMessage;
  final void Function(ChatMessage message)? onMessageSent;
  final Widget Function(BuildContext, MeshDocument, MeshElement)? messageHeaderBuilder;
  final Widget Function(BuildContext, List<String>)? waitingForParticipantsBuilder;
  final Widget Function(BuildContext context, FileAttachment upload)? attachmentBuilder;
  final ValueChanged<FileAttachment>? onAttachmentOpen;
  final ValueChanged<FileAttachment>? onAttachmentRemoved;
  final Widget Function(BuildContext context, String path)? fileInThreadBuilder;
  final Widget Function(BuildContext context, Widget chatBox)? chatInputBoxBuilder;
  final ChatThreadCustomInputBuilder? customInputBuilder;
  final FutureOr<void> Function(String path)? openFile;
  final FileDropOverlayBuilder? fileDropOverlayBuilder;
  final Widget Function(BuildContext, ChatThreadController, ChatThreadSnapshot)? toolsBuilder;
  final Widget? inputPlaceholder;
  final String? emptyStateTitle;
  final String? emptyStateDescription;
  final Widget? emptyState;
  final EditableTextContextMenuBuilder? inputContextMenuBuilder;
  final TapRegionCallback? inputOnPressedOutside;
  final ThreadStorageSaveSurfacePresenter? mobileStorageSaveSurfacePresenter;
  final double? mobileUnderHeaderContentPadding;
  final bool centerComposer;
  final bool showCenteredComposerTitle;
  final bool hideChatInput;
  final bool showThreadList;
  final double threadListWidth;
  final double threadListCollapsedHeight;
  final bool initialShowCompletedToolCalls;
  final bool shouldShowAuthorNames;
  final bool showUsageFooter;
  final DatasetChatThreadWrapperBuilder? datasetThreadWrapperBuilder;
  final DatasetChatNewThreadWrapperBuilder? datasetNewThreadWrapperBuilder;

  @override
  State<ChatBotView> createState() => _ChatBotViewState();
}

class _ChatBotViewState extends State<ChatBotView> {
  late ChatThreadController _controller;
  late bool _ownsController;
  final Map<String, DatasetChatModelController> _datasetModelControllers = <String, DatasetChatModelController>{};
  late final DatasetChatModelController _newThreadModelController;
  MessagingChatClient? _ownedChatClient;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ChatThreadController(room: widget.room);
    _newThreadModelController = DatasetChatModelController();
  }

  @override
  void didUpdateWidget(covariant ChatBotView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room || oldWidget.controller != widget.controller) {
      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? ChatThreadController(room: widget.room);
    }
    if (oldWidget.room != widget.room || oldWidget.agentName != widget.agentName || oldWidget.chatClient != widget.chatClient) {
      _disposeOwnedChatClient();
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    _disposeOwnedChatClient(disposeInjected: widget.disposeChatClient);
    for (final controller in _datasetModelControllers.values) {
      controller.removeListener(_handleDatasetModelControllerChanged);
      controller.dispose();
    }
    _datasetModelControllers.clear();
    _newThreadModelController.dispose();
    super.dispose();
  }

  String? _normalizeSelectedThreadPath(String? path) {
    final normalized = path?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String _resolvedSingleThreadPath() {
    final documentPath = widget.documentPath;
    if (documentPath != null && documentPath.trim().isNotEmpty) {
      return documentPath.trim();
    }

    return chatDocumentPath(widget.agentName, threadDir: widget.threadDir);
  }

  String? _resolvedThreadListPath() {
    return resolvedThreadListPath(widget.threadListPath, threadDir: widget.threadDir, agentName: widget.agentName);
  }

  BaseChatClient? _agentChatClient() {
    final injected = widget.chatClient;
    if (injected != null) {
      return injected;
    }
    final agentName = widget.agentName?.trim();
    if (agentName == null || agentName.isEmpty) {
      return null;
    }
    final existing = _ownedChatClient;
    if (existing != null) {
      return existing;
    }
    final created = MessagingChatClient(room: widget.room, agentName: agentName);
    _ownedChatClient = created;
    unawaited(created.start());
    return created;
  }

  void _disposeOwnedChatClient({bool disposeInjected = false}) {
    final owned = _ownedChatClient;
    _ownedChatClient = null;
    if (owned != null) {
      unawaited(owned.stop());
    }
    if (disposeInjected) {
      unawaited(widget.chatClient?.stop());
    }
  }

  Widget _buildChatInputBox(BuildContext context, Widget chatBox) {
    if (widget.hideChatInput) {
      return const SizedBox.shrink();
    }

    final builder = widget.chatInputBoxBuilder;
    if (builder == null) {
      return chatBox;
    }
    return builder(context, chatBox);
  }

  DatasetChatModelController _datasetModelControllerFor(String path) {
    return _datasetModelControllers.putIfAbsent(path, () {
      final controller = DatasetChatModelController();
      controller.addListener(_handleDatasetModelControllerChanged);
      return controller;
    });
  }

  void _handleDatasetModelControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Set<String> _activeDatasetThreadPaths() {
    return {
      for (final entry in _datasetModelControllers.entries)
        if (entry.value.isLocked) entry.key,
    };
  }

  void _seedResolvedThreadModelController(String? path) {
    final normalizedPath = path?.trim();
    if (normalizedPath == null ||
        normalizedPath.isEmpty ||
        (!normalizedPath.startsWith('dataset://') && !normalizedPath.startsWith('tmp://'))) {
      return;
    }
    _datasetModelControllerFor(normalizedPath).replaceModelsFrom(_newThreadModelController);
  }

  Widget _buildAgentMessageThread(BuildContext context, String path, ChatThreadController controller, {GlobalKey? composerKey}) {
    final modelController = _datasetModelControllerFor(path);
    final thread = DatasetChatThread(
      key: ValueKey(path),
      path: path,
      chatClient: _agentChatClient(),
      controller: controller,
      composerKey: composerKey,
      agentName: widget.agentName,
      emptyStateTitle: widget.emptyStateTitle,
      emptyStateDescription: widget.emptyStateDescription,
      openFile: widget.openFile,
      attachmentRenderer: (context, path) => ChatThreadPreview(room: widget.room, path: path),
      toolsBuilder: widget.toolsBuilder,
      inputPlaceholder: widget.inputPlaceholder,
      attachmentBuilder: widget.attachmentBuilder,
      inputContextMenuBuilder: widget.inputContextMenuBuilder,
      inputOnPressedOutside: widget.inputOnPressedOutside,
      customInputBuilder: widget.customInputBuilder,
      onFileDrop: (name, dataStream, size) => controller.uploadFile(name, dataStream, size ?? 0),
      fileDropOverlayBuilder: widget.fileDropOverlayBuilder,
      localParticipant: widget.room.localParticipant,
      generatedImageAttachmentRenderer: (context, image, onOpenFullscreen) => ChatThreadImageAttachment(
        room: widget.room,
        imageId: image.imageId,
        imageUri: image.uri,
        fallbackMimeType: image.mimeType,
        status: image.status,
        statusDetail: image.statusDetail,
        widthPx: image.width,
        heightPx: image.height,
        roundedCorners: false,
        onOpenFullscreen: onOpenFullscreen,
      ),
      imageGalleryBuilder: (context, images, initialIndex, onClose) =>
          ChatThreadImageGalleryPage(room: widget.room, images: images, initialIndex: initialIndex, onClose: onClose),
      modelController: modelController,
      initialShowCompletedToolCalls: widget.initialShowCompletedToolCalls,
      showUsageFooter: widget.showUsageFooter,
    );
    if (!path.startsWith('dataset://') && !path.startsWith('tmp://')) {
      return thread;
    }
    return widget.datasetThreadWrapperBuilder?.call(context, path, thread, modelController) ?? thread;
  }

  Widget _buildThread(BuildContext context, String path, ChatThreadController controller, {GlobalKey? composerKey}) {
    if (widget.threadDisplayMode == ChatThreadDisplayMode.multiThreadComposer && _agentChatClient() != null) {
      return _buildAgentMessageThread(context, path, controller, composerKey: composerKey);
    }

    if (path.startsWith('dataset://') || path.startsWith('tmp://')) {
      final modelController = _datasetModelControllerFor(path);
      final thread = RoomDatasetChatThread(
        key: ValueKey(path),
        path: path,
        room: widget.room,
        controller: controller,
        composerKey: composerKey,
        agentName: widget.agentName,
        emptyStateTitle: widget.emptyStateTitle,
        emptyStateDescription: widget.emptyStateDescription,
        openFile: widget.openFile,
        toolsBuilder: widget.toolsBuilder,
        inputPlaceholder: widget.inputPlaceholder,
        attachmentBuilder: widget.attachmentBuilder,
        inputContextMenuBuilder: widget.inputContextMenuBuilder,
        inputOnPressedOutside: widget.inputOnPressedOutside,
        customInputBuilder: widget.customInputBuilder,
        fileDropOverlayBuilder: widget.fileDropOverlayBuilder,
        modelController: modelController,
        initialShowCompletedToolCalls: widget.initialShowCompletedToolCalls,
        showUsageFooter: widget.showUsageFooter,
      );
      return widget.datasetThreadWrapperBuilder?.call(context, path, thread, modelController) ?? thread;
    }

    return ChatThread(
      key: ValueKey(path),
      path: path,
      room: widget.room,
      composerKey: composerKey,
      participants: widget.participants,
      participantNames: widget.participantNames,
      includeLocalParticipant: widget.includeLocalParticipant,
      startChatCentered: widget.startChatCentered,
      initialMessage: widget.threadDisplayMode == ChatThreadDisplayMode.singleThread ? widget.initialMessage : null,
      onMessageSent: widget.onMessageSent,
      controller: controller,
      messageHeaderBuilder: widget.messageHeaderBuilder,
      waitingForParticipantsBuilder: widget.waitingForParticipantsBuilder,
      attachmentBuilder: widget.attachmentBuilder,
      onAttachmentOpen: widget.onAttachmentOpen,
      onAttachmentRemoved: widget.onAttachmentRemoved,
      fileInThreadBuilder: widget.fileInThreadBuilder,
      chatInputBoxBuilder: (context, chatBox) => _buildChatInputBox(context, chatBox),
      customInputBuilder: widget.customInputBuilder,
      openFile: widget.openFile,
      fileDropOverlayBuilder: widget.fileDropOverlayBuilder,
      toolsBuilder: widget.toolsBuilder,
      inputPlaceholder: widget.inputPlaceholder,
      emptyStateTitle: widget.emptyStateTitle,
      emptyStateDescription: widget.emptyStateDescription,
      emptyState: widget.emptyState,
      inputContextMenuBuilder: widget.inputContextMenuBuilder,
      inputOnPressedOutside: widget.inputOnPressedOutside,
      mobileStorageSaveSurfacePresenter: widget.mobileStorageSaveSurfacePresenter,
      mobileUnderHeaderContentPadding: widget.mobileUnderHeaderContentPadding,
      agentName: widget.agentName,
      initialShowCompletedToolCalls: widget.initialShowCompletedToolCalls,
      shouldShowAuthorNames: widget.shouldShowAuthorNames,
      showUsageFooter: widget.showUsageFooter,
    );
  }

  Widget _buildMultiThreadView(BuildContext context) {
    final agentName = widget.agentName;
    if (agentName == null || agentName.trim().isEmpty) {
      return const Center(
        child: ShadAlert.destructive(title: Text("Unable to start a new thread"), description: Text("No chat agent is selected.")),
      );
    }

    final chatClient = _agentChatClient();
    final content = MultiThreadView(
      room: widget.room,
      chatClient: chatClient,
      agentName: agentName.trim(),
      controller: _controller,
      selectedThreadPath: _normalizeSelectedThreadPath(widget.selectedThreadPath),
      onSelectedThreadPathChanged: widget.onSelectedThreadPathChanged,
      onSelectedThreadResolved: (path, displayName) {
        _seedResolvedThreadModelController(path);
        widget.onSelectedThreadResolved?.call(path, displayName);
      },
      onThreadStartActivityChanged: widget.onThreadStartActivityChanged,
      newThreadResetVersion: widget.newThreadResetVersion,
      centerComposer: widget.centerComposer,
      showCenteredComposerTitle: widget.showCenteredComposerTitle,
      showUsageFooter: widget.showUsageFooter,
      emptyState: widget.emptyState,
      inputPlaceholder: widget.inputPlaceholder,
      inputContextMenuBuilder: widget.inputContextMenuBuilder,
      inputOnPressedOutside: widget.inputOnPressedOutside,
      onAttachmentOpen: widget.onAttachmentOpen,
      onAttachmentRemoved: widget.onAttachmentRemoved,
      fileDropOverlayBuilder: widget.fileDropOverlayBuilder,
      toolsBuilder: widget.toolsBuilder,
      modelController: _newThreadModelController,
      customInputBuilder: widget.customInputBuilder,
      newThreadWrapperBuilder: widget.datasetNewThreadWrapperBuilder,
      builder: (context, path, controller, composerKey) => _buildThread(context, path, controller, composerKey: composerKey),
    );

    final threadListPath = _resolvedThreadListPath();
    if (!widget.showThreadList || threadListPath == null || chatClient == null) {
      return content;
    }

    final selectedThreadPath = _normalizeSelectedThreadPath(widget.selectedThreadPath);
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSideBySide = constraints.maxWidth >= 920;
        final list = ChatThreadListView(
          room: widget.room,
          chatClient: chatClient,
          threadListPath: "agent://threads",
          agentName: widget.agentName,
          selectedThreadPath: selectedThreadPath,
          selectedThreadDisplayName: widget.selectedThreadDisplayName,
          activeThreadPaths: _activeDatasetThreadPaths(),
          onSelectedThreadPathChanged: widget.onSelectedThreadPathChanged ?? (_) {},
          onSelectedThreadResolved: widget.onSelectedThreadResolved,
          newThreadResetVersion: widget.newThreadResetVersion,
        );

        if (showSideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: content),
              const SizedBox(width: 12),
              SizedBox(width: widget.threadListWidth, child: list),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: content),
            const SizedBox(height: 12),
            SizedBox(height: widget.threadListCollapsedHeight, child: list),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.threadDisplayMode == ChatThreadDisplayMode.multiThreadComposer) {
      return _buildMultiThreadView(context);
    }

    return _buildThread(context, _resolvedSingleThreadPath(), _controller);
  }
}
