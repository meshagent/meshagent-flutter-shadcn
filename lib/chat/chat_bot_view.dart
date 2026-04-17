import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'chat.dart';
import 'conversation_descriptor.dart';
import 'multi_thread_view.dart';
import 'thread_list_view.dart';

class ChatBotView extends StatefulWidget {
  const ChatBotView({
    super.key,
    required this.room,
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
    this.fileInThreadBuilder,
    this.chatInputBoxBuilder,
    this.openFile,
    this.toolsBuilder,
    this.inputPlaceholder,
    this.emptyStateTitle,
    this.emptyStateDescription,
    this.emptyState,
    this.inputContextMenuBuilder,
    this.inputOnPressedOutside,
    this.centerComposer = false,
    this.hideChatInput = false,
    this.showThreadList = true,
    this.threadListWidth = 280,
    this.threadListCollapsedHeight = 220,
    this.initialShowCompletedToolCalls = false,
    this.shouldShowAuthorNames = true,
  });

  final RoomClient room;
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
  final Widget Function(BuildContext context, String path)? fileInThreadBuilder;
  final Widget Function(BuildContext context, Widget chatBox)? chatInputBoxBuilder;
  final FutureOr<void> Function(String path)? openFile;
  final Widget Function(BuildContext, ChatThreadController, ChatThreadSnapshot)? toolsBuilder;
  final Widget? inputPlaceholder;
  final String? emptyStateTitle;
  final String? emptyStateDescription;
  final Widget? emptyState;
  final EditableTextContextMenuBuilder? inputContextMenuBuilder;
  final TapRegionCallback? inputOnPressedOutside;
  final bool centerComposer;
  final bool hideChatInput;
  final bool showThreadList;
  final double threadListWidth;
  final double threadListCollapsedHeight;
  final bool initialShowCompletedToolCalls;
  final bool shouldShowAuthorNames;

  @override
  State<ChatBotView> createState() => _ChatBotViewState();
}

class _ChatBotViewState extends State<ChatBotView> {
  late ChatThreadController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ChatThreadController(room: widget.room);
  }

  @override
  void didUpdateWidget(covariant ChatBotView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room == widget.room && oldWidget.controller == widget.controller) {
      return;
    }

    if (_ownsController) {
      _controller.dispose();
    }
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ChatThreadController(room: widget.room);
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
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

  Widget _buildThread(String path, ChatThreadController controller, {GlobalKey? composerKey}) {
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
      fileInThreadBuilder: widget.fileInThreadBuilder,
      chatInputBoxBuilder: (context, chatBox) => _buildChatInputBox(context, chatBox),
      openFile: widget.openFile,
      toolsBuilder: widget.toolsBuilder,
      inputPlaceholder: widget.inputPlaceholder,
      emptyStateTitle: widget.emptyStateTitle,
      emptyStateDescription: widget.emptyStateDescription,
      emptyState: widget.emptyState,
      inputContextMenuBuilder: widget.inputContextMenuBuilder,
      inputOnPressedOutside: widget.inputOnPressedOutside,
      agentName: widget.agentName,
      initialShowCompletedToolCalls: widget.initialShowCompletedToolCalls,
      shouldShowAuthorNames: widget.shouldShowAuthorNames,
    );
  }

  Widget _buildMultiThreadView(BuildContext context) {
    final agentName = widget.agentName;
    if (agentName == null || agentName.trim().isEmpty) {
      return const Center(
        child: ShadAlert.destructive(title: Text("Unable to start a new thread"), description: Text("No chat agent is selected.")),
      );
    }

    final content = MultiThreadView(
      room: widget.room,
      agentName: agentName.trim(),
      controller: _controller,
      selectedThreadPath: _normalizeSelectedThreadPath(widget.selectedThreadPath),
      onSelectedThreadPathChanged: widget.onSelectedThreadPathChanged,
      onSelectedThreadResolved: widget.onSelectedThreadResolved,
      newThreadResetVersion: widget.newThreadResetVersion,
      centerComposer: widget.centerComposer,
      emptyState: widget.emptyState,
      inputContextMenuBuilder: widget.inputContextMenuBuilder,
      inputOnPressedOutside: widget.inputOnPressedOutside,
      toolsBuilder: widget.toolsBuilder,
      builder: (context, path, controller, composerKey) => _buildThread(path, controller, composerKey: composerKey),
    );

    final threadListPath = _resolvedThreadListPath();
    if (!widget.showThreadList || threadListPath == null) {
      return content;
    }

    final selectedThreadPath = _normalizeSelectedThreadPath(widget.selectedThreadPath);
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSideBySide = constraints.maxWidth >= 920;
        final list = ChatThreadListView(
          room: widget.room,
          threadListPath: threadListPath,
          agentName: widget.agentName,
          selectedThreadPath: selectedThreadPath,
          selectedThreadDisplayName: widget.selectedThreadDisplayName,
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

    return _buildThread(_resolvedSingleThreadPath(), _controller);
  }
}
