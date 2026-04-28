import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';

import 'chat.dart';
import 'new_chat_thread.dart';

typedef MultiThreadContentBuilder =
    Widget Function(BuildContext context, String threadPath, ChatThreadController controller, GlobalKey composerKey);

class MultiThreadView extends StatefulWidget {
  const MultiThreadView({
    super.key,
    required this.room,
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
    this.emptyState,
    this.inputContextMenuBuilder,
    this.inputOnPressedOutside,
  });

  final RoomClient room;
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
  final Widget? emptyState;
  final EditableTextContextMenuBuilder? inputContextMenuBuilder;
  final TapRegionCallback? inputOnPressedOutside;

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
    if (oldWidget.room == widget.room && oldWidget.controller == widget.controller) {
      return;
    }

    if (_ownsController) {
      _controller.dispose();
    }
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ChatThreadController(room: widget.room);
    _composerKey = GlobalKey();
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
    if (selectedThreadPath != null) {
      return widget.builder(context, selectedThreadPath, _controller, _composerKey);
    }

    return NewChatThread(
      key: ValueKey("new-thread-${widget.agentName}-${widget.newThreadResetVersion}"),
      room: widget.room,
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
      emptyState: widget.emptyState,
      inputContextMenuBuilder: widget.inputContextMenuBuilder,
      inputOnPressedOutside: widget.inputOnPressedOutside,
      builder: (context, threadPath) => widget.builder(context, threadPath, _controller, _composerKey),
    );
  }
}
