import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart' show BaseChatClient;

import 'chat.dart';
import 'dataset_chat_thread.dart';
import 'new_chat_thread.dart';

typedef MultiThreadContentBuilder =
    Widget Function(BuildContext context, String threadPath, ChatThreadController controller, GlobalKey composerKey);

class MultiThreadView extends StatefulWidget {
  const MultiThreadView({
    super.key,
    required this.room,
    this.chatClient,
    this.disposeChatClient = false,
    required this.agentName,
    required this.builder,
    this.controller,
    this.toolkit = "chat",
    this.tool = "new_thread",
    this.toolsBuilder,
    this.selectedThreadPath,
    this.onSelectedThreadPathChanged,
    this.onSelectedThreadResolved,
    this.newThreadResetVersion = 0,
    this.centerComposer = true,
    this.showCenteredComposerTitle = true,
    this.showUsageFooter = false,
    this.emptyState,
    this.inputPlaceholder,
    this.inputContextMenuBuilder,
    this.inputOnPressedOutside,
    this.onAttachmentOpen,
    this.onAttachmentRemoved,
    this.fileDropOverlayBuilder,
    this.modelController,
    this.customInputBuilder,
    this.newThreadWrapperBuilder,
  });

  final RoomClient room;
  final BaseChatClient? chatClient;
  final bool disposeChatClient;
  final String agentName;
  final MultiThreadContentBuilder builder;
  final ChatThreadController? controller;
  final String toolkit;
  final String tool;
  final NewChatThreadToolsBuilder? toolsBuilder;
  final String? selectedThreadPath;
  final ValueChanged<String?>? onSelectedThreadPathChanged;
  final void Function(String? path, String? displayName)? onSelectedThreadResolved;
  final int newThreadResetVersion;
  final bool centerComposer;
  final bool showCenteredComposerTitle;
  final bool showUsageFooter;
  final Widget? emptyState;
  final Widget? inputPlaceholder;
  final EditableTextContextMenuBuilder? inputContextMenuBuilder;
  final TapRegionCallback? inputOnPressedOutside;
  final ValueChanged<FileAttachment>? onAttachmentOpen;
  final ValueChanged<FileAttachment>? onAttachmentRemoved;
  final FileDropOverlayBuilder? fileDropOverlayBuilder;
  final DatasetChatModelController? modelController;
  final ChatThreadCustomInputBuilder? customInputBuilder;
  final NewChatThreadWrapperBuilder? newThreadWrapperBuilder;

  @override
  State<MultiThreadView> createState() => _MultiThreadViewState();
}

class _MultiThreadViewState extends State<MultiThreadView> {
  late ChatThreadController _controller;
  late bool _ownsController;
  late GlobalKey _composerKey;

  String? _normalizeSelectedThreadPath(String? path) {
    final normalized = path?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ChatThreadController(room: widget.room);
    _composerKey = GlobalKey();
  }

  @override
  void didUpdateWidget(covariant MultiThreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = oldWidget.room != widget.room || oldWidget.controller != widget.controller;
    final agentChanged = oldWidget.agentName != widget.agentName;

    if (controllerChanged) {
      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? ChatThreadController(room: widget.room);
      _composerKey = GlobalKey();
    }

    if (agentChanged) {
      _controller.clear();
      _composerKey = GlobalKey();
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedThreadPath = _normalizeSelectedThreadPath(widget.selectedThreadPath);

    return NewChatThread(
      key: ValueKey("new-thread-${widget.agentName}-${widget.newThreadResetVersion}"),
      room: widget.room,
      chatClient: widget.chatClient,
      disposeChatClient: widget.disposeChatClient,
      agentName: widget.agentName,
      controller: _controller,
      composerKey: _composerKey,
      toolkit: widget.toolkit,
      tool: widget.tool,
      toolsBuilder: widget.toolsBuilder,
      selectedThreadPath: selectedThreadPath,
      onThreadPathChanged: widget.onSelectedThreadPathChanged,
      onThreadResolved: widget.onSelectedThreadResolved,
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
      modelController: widget.modelController,
      customInputBuilder: widget.customInputBuilder,
      newThreadWrapperBuilder: widget.newThreadWrapperBuilder,
      builder: (context, threadPath) => widget.builder(context, threadPath, _controller, _composerKey),
    );
  }
}
