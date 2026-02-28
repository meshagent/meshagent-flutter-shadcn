import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:interactive_viewer_2/interactive_viewer_2.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat_bubble_markdown_config.dart';
import 'package:meshagent_flutter_shadcn/code_language_resolver.dart';
import 'package:meshagent_flutter_shadcn/storage/file_browser.dart';
import 'package:meshagent_flutter_shadcn/ui/ui.dart';
import 'package:re_highlight/styles/monokai-sublime.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:super_native_extensions/raw_clipboard.dart' as raw;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:meshagent_flutter/meshagent_flutter.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';
import 'package:meshagent_flutter_shadcn/file_preview/image.dart';

import 'outbound_delivery_status.dart';
import 'folder_drop.dart';

const webPDFFormat = SimpleFileFormat(uniformTypeIdentifiers: ['com.adobe.pdf'], mimeTypes: ['web application/pdf']);

enum UploadStatus { initial, uploading, completed, failed }

Set<String> _threadParticipantNames(MeshDocument thread) {
  final members = thread.root.getElementsByTagName("members").firstOrNull?.getElementsByTagName("member") ?? const <MeshElement>[];
  final names = <String>{};
  for (final member in members) {
    final name = member.getAttribute("name");
    if (name is String) {
      final normalized = name.trim();
      if (normalized.isNotEmpty) {
        names.add(normalized);
      }
    }
  }
  return names;
}

bool _shouldShowAuthorNames({required MeshDocument thread, String? localParticipantName}) {
  final participantNames = _threadParticipantNames(thread);
  final normalizedLocal = localParticipantName?.trim();
  if (normalizedLocal != null && normalizedLocal.isNotEmpty && !participantNames.contains(normalizedLocal)) {
    participantNames.add(normalizedLocal);
  }
  return participantNames.length > 2;
}

class FileAttachment extends ChangeNotifier {
  FileAttachment({required this.path, UploadStatus initialStatus = UploadStatus.initial}) : _status = initialStatus;

  UploadStatus _status;

  UploadStatus get status => _status;

  @protected
  set status(UploadStatus value) {
    if (_status != value) {
      _status = value;
      notifyListeners();
    }
  }

  String path;
  String get filename => path.split("/").last;
}

class MeshagentFileUpload extends FileAttachment {
  MeshagentFileUpload({required this.room, required super.path, required this.dataStream, this.size = 0}) {
    _upload();
  }

  // Requires to manually call startUpload()
  MeshagentFileUpload.deferred({required this.room, required super.path, required this.dataStream, this.size = 0});

  int size;

  final RoomClient room;

  final Stream<List<int>> dataStream;

  final _completer = Completer();

  int _bytesUploaded = 0;

  int get bytesUploaded => _bytesUploaded;

  Future get done => _completer.future;

  final _downloadUrlCompleter = Completer<Uri>();

  Future<Uri> get downloadUrl => _downloadUrlCompleter.future;

  void startUpload() {
    _upload();
  }

  void _upload() async {
    if (status != UploadStatus.initial) {
      throw StateError("upload already started or completed");
    }

    try {
      final handle = await room.storage.open(path, overwrite: true);

      try {
        status = UploadStatus.uploading;
        notifyListeners();

        await for (final len in dataStream.asyncMap((item) async {
          await room.storage.write(handle, Uint8List.fromList(item));

          return item.length;
        })) {
          _bytesUploaded += len;
          notifyListeners();
        }
      } finally {
        await room.storage.close(handle);
      }

      _completer.complete();

      status = UploadStatus.completed;
      notifyListeners();

      final url = await room.storage.downloadUrl(path);
      _downloadUrlCompleter.complete(Uri.parse(url));
    } catch (err) {
      status = UploadStatus.failed;
      notifyListeners();

      _completer.completeError(err);
      _downloadUrlCompleter.completeError(err);
    }
  }
}

class ChatThreadController extends ChangeNotifier {
  ChatThreadController({required this.room}) {
    textFieldController.addListener(notifyListeners);
  }

  final List<ToolkitBuilderOption> toolkits = [];
  final RoomClient room;
  final TextEditingController textFieldController = ShadTextEditingController();
  final List<FileAttachment> _attachmentUploads = [];
  final OutboundMessageStatusQueue outboundStatus = OutboundMessageStatusQueue();

  bool _listening = false;

  bool get listening {
    return _listening;
  }

  set listening(bool value) {
    if (value != _listening) {
      _listening = value;
      notifyListeners();
    }
  }

  List<FileAttachment> get attachmentUploads => List<FileAttachment>.unmodifiable(_attachmentUploads);

  bool toggleToolkit(ToolkitBuilderOption toolkit) {
    if (toolkits.contains(toolkit)) {
      toolkits.remove(toolkit);
      notifyListeners();
      return false;
    } else {
      toolkits.add(toolkit);
      notifyListeners();
      return true;
    }
  }

  Future<void> cancel(String path, MeshDocument thread) async {
    for (final participant in getOnlineParticipants(thread)) {
      if (participant is RemoteParticipant && participant.role == "agent") {
        await room.messaging.sendMessage(to: participant, type: "cancel", message: {"path": path});
      }
    }
  }

  Future<FileAttachment> uploadFile(String path, Stream<Uint8List> dataStream, int size) async {
    final uploader = MeshagentFileUpload(room: room, path: path, dataStream: dataStream, size: size);
    uploader.addListener(notifyListeners);

    _attachmentUploads.add(uploader);
    notifyListeners();

    return uploader;
  }

  Future<FileAttachment> uploadFileDeferred(String path, Stream<Uint8List> dataStream, int size) async {
    final uploader = MeshagentFileUpload.deferred(room: room, path: path, dataStream: dataStream, size: size);

    uploader.addListener(notifyListeners);

    _attachmentUploads.add(uploader);
    notifyListeners();

    return uploader;
  }

  FileAttachment attachFile(String path) {
    final attachment = FileAttachment(path: path, initialStatus: UploadStatus.completed);
    attachment.addListener(notifyListeners);
    _attachmentUploads.add(attachment);
    notifyListeners();
    return attachment;
  }

  String get text {
    return textFieldController.text;
  }

  void removeFileUpload(FileAttachment upload) {
    upload.removeListener(notifyListeners);

    _attachmentUploads.remove(upload);

    notifyListeners();
  }

  void clear() {
    for (final upload in _attachmentUploads) {
      upload.removeListener(notifyListeners);
    }

    textFieldController.clear();
    _attachmentUploads.clear();

    notifyListeners();
  }

  Iterable<String> getParticipantNames(MeshDocument document) sync* {
    for (final child in document.root.getChildren().whereType<MeshElement>()) {
      if (child.tagName == "members") {
        for (final member in child.getChildren().whereType<MeshElement>()) {
          if (member.getAttribute("name") != null) {
            yield member.getAttribute("name");
          }
        }
      }
    }
  }

  Iterable<String> getOfflineParticipants(MeshDocument document) sync* {
    for (final participantName in getParticipantNames(document)) {
      bool found = false;
      if (room.messaging.remoteParticipants.where((x) => x.getAttribute("name") == participantName).isNotEmpty ||
          participantName == room.localParticipant?.getAttribute("name")) {
        found = true;
      }
      if (!found) {
        yield participantName;
      }
    }
  }

  Iterable<Participant> getOnlineParticipants(MeshDocument document) sync* {
    for (final participantName in getParticipantNames(document)) {
      if (participantName == room.localParticipant?.getAttribute("name")) {
        yield room.localParticipant!;
      }
      for (final part in room.messaging.remoteParticipants.where((x) => x.getAttribute("name") == participantName)) {
        yield part;
      }
    }
  }

  Future<void> sendMessageToParticipant({
    required Participant participant,
    required String path,
    required ChatMessage message,
    String messageType = "chat",
  }) async {
    if (message.text.trim().isNotEmpty || message.attachments.isNotEmpty) {
      final tools = [for (final tk in toolkits) (await tk.build(room)).toJson()];
      await room.messaging.sendMessage(
        to: participant,
        type: messageType,
        message: {
          "tools": tools,
          "path": path,
          "text": message.text,
          "attachments": message.attachments.map((a) => {"path": a}).toList(),
        },
      );
    }
  }

  void insertMessage({required MeshDocument thread, required ChatMessage message}) {
    final messages = thread.root.getChildren().whereType<MeshElement>().firstWhere((x) => x.tagName == "messages");

    final m = messages.createChildElement("message", {
      "id": message.id,
      "text": message.text,
      "created_at": DateTime.now().toUtc().toIso8601String(),
      "author_name": room.localParticipant!.getAttribute("name"),
      "author_ref": null,
    });

    for (final path in message.attachments) {
      m.createChildElement("file", {"path": path});
    }
  }

  bool _notifyOnSend = true;

  bool get notifyOnSend {
    return _notifyOnSend;
  }

  set notifyOnSend(bool value) {
    _notifyOnSend = value;
    notifyListeners();
  }

  Future<void> send({
    required MeshDocument thread,
    required String path,
    required ChatMessage message,
    String messageType = "chat",
    void Function(ChatMessage)? onMessageSent,
  }) async {
    if (message.text.trim().isNotEmpty || message.attachments.isNotEmpty) {
      insertMessage(thread: thread, message: message);

      final List<Future<void>> sentMessages = [];
      if (notifyOnSend) {
        for (final participant in getOnlineParticipants(thread)) {
          sentMessages.add(sendMessageToParticipant(participant: participant, path: path, message: message, messageType: messageType));
        }
      }

      outboundStatus.markSending(message.id);

      await Future.wait(sentMessages);

      outboundStatus.markDelivered(message.id);

      onMessageSent?.call(message);

      clear();
    }
  }

  @override
  void dispose() {
    super.dispose();

    textFieldController.dispose();
    outboundStatus.dispose();

    for (final upload in _attachmentUploads) {
      upload.removeListener(notifyListeners);
      if (upload is MeshagentFileUpload) {
        upload.done.ignore();
      }
      upload.dispose();
    }
  }
}

class ChatThreadLoader extends StatelessWidget {
  const ChatThreadLoader({
    super.key,
    required this.path,
    required this.room,
    this.participants,
    this.participantNames,
    this.includeLocalParticipant = true,
    this.builder,
    this.loadingBuilder,
  });

  final String path;
  final RoomClient room;
  final List<Participant>? participants;
  final List<String>? participantNames;
  final bool includeLocalParticipant;
  final Widget Function(BuildContext, MeshDocument)? builder;
  final Widget Function(BuildContext)? loadingBuilder;

  void _ensureParticipants(MeshDocument document) {
    final participantsList = <Participant>[if (participants != null) ...participants!, if (includeLocalParticipant) room.localParticipant!];

    if (participants != null || participantNames != null) {
      Set<String> existing = {};

      for (final child in document.root.getChildren().whereType<MeshElement>()) {
        if (child.tagName == "members") {
          for (final member in child.getChildren().whereType<MeshElement>()) {
            if (member.getAttribute("name") != null) {
              existing.add(member.getAttribute("name"));
            }
          }

          for (final part in participantsList) {
            if (!existing.contains(part.getAttribute("name"))) {
              child.createChildElement("member", {"name": part.getAttribute("name")});
              existing.add(part.getAttribute("name"));
            }
          }

          if (participantNames != null) {
            for (final part in participantNames!) {
              if (!existing.contains(part)) {
                child.createChildElement("member", {"name": part});
                existing.add(part);
              }
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DocumentConnectionScope(
      key: ValueKey(path),
      path: path,
      room: room,
      builder: (context, document, error) {
        if (error != null) {
          return Center(child: Text("Unable to load thread", style: ShadTheme.of(context).textTheme.p));
        }

        if (document == null) {
          return loadingBuilder == null ? const Center(child: CircularProgressIndicator()) : loadingBuilder!(context);
        }
        _ensureParticipants(document);

        return builder?.call(context, document) ?? ChatThread(path: path, document: document, room: room);
      },
    );
  }
}

double chatThreadFeedHorizontalPadding(double maxWidth) {
  return maxWidth > 912 ? (maxWidth - 912) / 2 : 16;
}

double chatThreadStatusHorizontalPadding(double maxWidth) {
  return maxWidth > 912 ? (maxWidth - 912) / 2 : 15;
}

class ChatThreadInputFrame extends StatelessWidget {
  const ChatThreadInputFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      child: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 912), child: child),
      ),
    );
  }
}

class ChatThreadViewportBody extends StatelessWidget {
  const ChatThreadViewportBody({
    super.key,
    required this.children,
    this.bottomAlign = true,
    this.centerContent,
    this.bottomSpacer = 0,
    this.overlays = const [],
  });

  final List<Widget> children;
  final bool bottomAlign;
  final Widget? centerContent;
  final double bottomSpacer;
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              mainAxisAlignment: bottomAlign ? MainAxisAlignment.end : MainAxisAlignment.center,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => ListView(
                      reverse: true,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.symmetric(vertical: 16, horizontal: chatThreadFeedHorizontalPadding(constraints.maxWidth)),
                      children: children,
                    ),
                  ),
                ),
                if (!bottomAlign && centerContent != null) centerContent!,
                if (bottomSpacer > 0) SizedBox(height: bottomSpacer),
              ],
            ),
          ),
          ...overlays,
        ],
      ),
    );
  }
}

class ChatThreadAttachButton extends StatefulWidget {
  const ChatThreadAttachButton({
    required this.controller,
    super.key,
    this.toolkits = const [],
    this.alwaysShowAttachFiles,
    this.availableConnectors = const [],
    this.onConnectorSetup,
    this.agentName,
  });

  final String? agentName;
  final bool? alwaysShowAttachFiles;

  final List<ToolkitBuilderOption> toolkits;

  final ChatThreadController controller;

  final List<Connector> availableConnectors;

  final Future<void> Function(Connector connector)? onConnectorSetup;

  @override
  State createState() => _ChatThreadAttachButton();
}

class _ChatThreadAttachButton extends State<ChatThreadAttachButton> {
  Future<void> _onSelectAttachment(ToolkitBuilderOption? storage) async {
    final picked = await FilePicker.platform.pickFiles(dialogTitle: "Select files", allowMultiple: true, withReadStream: true);

    if (picked == null) {
      return;
    }

    for (final file in picked.files) {
      await widget.controller.uploadFile(file.name, file.readStream!.map(Uint8List.fromList), file.size);
    }

    if (storage != null) {
      if (!widget.controller.toolkits.contains(storage)) {
        widget.controller.toggleToolkit(storage);
        setState(() {});
      }
    }
  }

  Future<void> _onSelectPhoto(ToolkitBuilderOption? storage) async {
    final picker = ImagePicker();

    List<XFile> picked = const [];
    try {
      picked = await picker.pickMultipleMedia(); // images and videos
    } catch (_) {
      // Older web/mobile builds may not support pickMultipleMedia.
    }
    if (picked.isEmpty) {
      try {
        picked = await picker.pickMultiImage(); // at least images
      } catch (_) {
        // As a last resort, single image (some platforms).
        final single = await picker.pickImage(source: ImageSource.gallery);
        if (single != null) picked = [single];
      }
    }
    if (picked.isEmpty) return;

    final names = PhotoNamer.generateBatchNames(picked);

    for (var i = 0; i < picked.length; i++) {
      final file = picked[i];
      final fileName = names[i];
      final size = await file.length();
      final stream = file.openRead();

      await widget.controller.uploadFile(fileName, stream, size);
    }

    if (storage != null) {
      if (!widget.controller.toolkits.contains(storage)) {
        widget.controller.toggleToolkit(storage);
        setState(() {});
      }
    }
  }

  Future<void> _onBrowseFiles(ToolkitBuilderOption? storage) async {
    List<String> picked = [];
    await showShadDialog(
      context: context,

      builder: (context) => ShadDialog(
        title: Text("Select files"),
        scrollable: false,
        description: Text("Attach files from this room"),
        actions: [
          ShadButton.secondary(
            onPressed: () {
              picked.clear();
              Navigator.of(context).pop([]);
            },
            child: Text("Cancel"),
          ),
          ShadButton.secondary(
            onPressed: () {
              Navigator.of(context).pop(picked);
            },
            child: Text("OK"),
          ),
        ],
        child: SizedBox(
          width: 500,
          height: 400,
          child: ShadCard(
            child: FileBrowser(
              onSelectionChanged: (selection) {
                picked = selection;
              },
              room: widget.controller.room,
              multiple: true,
            ),
          ),
        ),
      ),
    );

    for (final f in picked) {
      widget.controller.attachFile(f);
    }
  }

  ShadPopoverController popoverController = ShadPopoverController();
  ShadPopoverController addMcpController = ShadPopoverController();

  @override
  void dispose() {
    super.dispose();
    popoverController.dispose();
  }

  Set<Connector> setup = {};

  @override
  Widget build(BuildContext context) {
    if (widget.toolkits.isEmpty && widget.alwaysShowAttachFiles != true) {
      return SizedBox(width: 0, height: 22);
    }

    final storageToolkit = widget.toolkits.where((x) => x is StaticToolkitBuilderOption && x.config is StorageConfig).firstOrNull;
    final canUpload = widget.alwaysShowAttachFiles == true || storageToolkit != null;

    return ListenableBuilder(
      listenable: popoverController,
      builder: (context, _) => Wrap(
        alignment: WrapAlignment.start,
        runAlignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ShadContextMenu(
            constraints: BoxConstraints(minWidth: 175),
            anchor: ShadAnchorAuto(followerAnchor: Alignment.topRight, targetAnchor: Alignment.topLeft),
            items: [
              if (canUpload) ...[
                if (!kIsWeb)
                  ShadContextMenuItem(
                    leading: Icon(LucideIcons.imageUp),
                    onPressed: () => _onSelectPhoto(storageToolkit),
                    child: Text("Upload a photo..."),
                  ),
                ShadContextMenuItem(
                  leading: Icon(LucideIcons.paperclip),
                  onPressed: () => _onSelectAttachment(storageToolkit),
                  child: Text("Upload a file..."),
                ),
              ],
              ShadContextMenuItem(
                leading: Icon(LucideIcons.download),
                onPressed: () => _onBrowseFiles(storageToolkit),
                child: Text("Add from room..."),
              ),

              if (widget.toolkits.isNotEmpty) ShadSeparator.horizontal(margin: EdgeInsets.symmetric(vertical: 3)),

              for (final tk in widget.toolkits)
                Builder(
                  builder: (context) => ShadContextMenuItem(
                    textStyle: widget.controller.toolkits.contains(tk)
                        ? ShadTheme.of(context).contextMenuTheme.textStyle!.copyWith(color: Colors.blue)
                        : null,
                    leading: Icon(tk.icon, color: widget.controller.toolkits.contains(tk) ? Colors.blue : null),
                    onPressed: () {
                      widget.controller.toggleToolkit(tk);
                    },
                    trailing: widget.controller.toolkits.contains(tk)
                        ? Icon(LucideIcons.check, color: widget.controller.toolkits.contains(tk) ? Colors.blue : null)
                        : null,
                    child: Text(tk.text),
                  ),
                ),
            ],
            controller: popoverController,
            child: ShadIconButton.ghost(
              hoverBackgroundColor: ShadTheme.of(context).colorScheme.background,
              decoration: ShadDecoration(shape: BoxShape.circle),
              onPressed: popoverController.isOpen
                  ? null
                  : () {
                      popoverController.toggle();
                    },
              iconSize: 16,
              width: 32,
              height: 32,
              icon: Icon(LucideIcons.plus),
            ),
          ),
          for (final tool in widget.controller.toolkits) ...[
            ShadButton.ghost(
              trailing: Icon(LucideIcons.x),
              hoverBackgroundColor: ShadTheme.of(context).colorScheme.background,
              decoration: ShadDecoration(border: ShadBorder.all(radius: BorderRadius.circular(30))),
              child: Text(tool.selectedText),
              onPressed: () {
                setState(() {
                  widget.controller.toggleToolkit(tool);
                });
              },
            ),
            if (tool is ConnectorToolkitBuilderOption) ...[
              if (widget.agentName != null)
                ShadContextMenu(
                  controller: addMcpController,
                  constraints: BoxConstraints(minWidth: 175),
                  anchor: ShadAnchorAuto(followerAnchor: Alignment.topRight, targetAnchor: Alignment.topLeft),
                  items: [
                    if (widget.availableConnectors.isEmpty) ShadContextMenuItem(child: Text("No connectors are configured for this room")),
                    for (final connector in widget.availableConnectors)
                      ConnectorContextMenuItem(
                        selected:
                            widget.controller.toolkits.whereType<ConnectorToolkitBuilderOption>().firstOrNull?.connectors.firstWhereOrNull(
                              (c) => c.name == connector.name,
                            ) !=
                            null,
                        agentName: widget.agentName!,
                        room: widget.controller.room,
                        connector: connector,
                        onSelectedChanged: (selected) async {
                          if (!selected) {
                            widget.controller.toolkits.whereType<ConnectorToolkitBuilderOption>().firstOrNull?.connectors.removeWhere(
                              (c) => c.name == connector.name,
                            );
                            setState(() {});
                          } else {
                            await widget.onConnectorSetup!(connector);
                            var mcp =
                                widget.controller.toolkits.firstWhereOrNull((c) => c is ConnectorToolkitBuilderOption)
                                    as ConnectorToolkitBuilderOption?;
                            if (mounted) {
                              if (mcp!.connectors.firstWhereOrNull((c) => c.name == connector.name) == null) {
                                setState(() {
                                  mcp.connectors.add(connector);
                                });
                              }
                            }
                          }
                        },
                        onConnectorSetup: widget.onConnectorSetup,
                      ),
                  ],
                  child: ListenableBuilder(
                    listenable: addMcpController,
                    builder: (context, _) => ShadButton.ghost(
                      decoration: ShadDecoration(border: ShadBorder.all(radius: BorderRadius.circular(30))),

                      onPressed: addMcpController.isOpen
                          ? null
                          : () {
                              addMcpController.setOpen(true);
                            },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [Icon(LucideIcons.cable), Text("${tool.connectors.length}"), Icon(LucideIcons.chevronDown)],
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class ConnectorContextMenuItem extends StatefulWidget {
  const ConnectorContextMenuItem({
    required this.room,
    required this.agentName,
    required this.connector,
    super.key,
    required this.onConnectorSetup,
    required this.selected,
    required this.onSelectedChanged,
  });

  final RoomClient room;
  final Connector connector;
  final String agentName;
  final bool selected;

  final void Function(bool selected)? onSelectedChanged;

  final Future<void> Function(Connector connector)? onConnectorSetup;

  @override
  State createState() => _ConnectorContextMenuItem();
}

class _ConnectorContextMenuItem extends State<ConnectorContextMenuItem> {
  bool? connected;

  @override
  void initState() {
    super.initState();
    widget.connector.isConnected(widget.room, widget.agentName).then((value) {
      if (mounted) {
        setState(() {
          connected = value;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShadContextMenuItem(
      trailing: Visibility(
        maintainSize: true,
        maintainState: true,
        maintainAnimation: true,
        visible: connected != null,
        child: connected != true
            ? Text("Connect", style: TextStyle(color: ShadTheme.of(context).colorScheme.mutedForeground))
            : ShadSwitch(
                onChanged: (value) {
                  if (widget.onSelectedChanged != null) {
                    widget.onSelectedChanged!(value);
                  }
                },
                value: widget.selected,
              ),
      ),
      onPressed: () async {
        if (widget.onSelectedChanged != null) {
          widget.onSelectedChanged!(!widget.selected);
        }
      },
      child: Text(widget.connector.name),
    );
  }
}

abstract class ToolkitBuilderOption {
  ToolkitBuilderOption({required this.icon, required this.text, required this.selectedText});

  final String text;
  final String selectedText;
  final IconData icon;

  Future<ToolkitConfig> build(RoomClient room);
}

class StaticToolkitBuilderOption extends ToolkitBuilderOption {
  StaticToolkitBuilderOption({required super.icon, required super.text, required super.selectedText, required this.config});

  final ToolkitConfig config;
  @override
  Future<ToolkitConfig> build(RoomClient room) async {
    return config;
  }
}

class ConnectorToolkitBuilderOption extends ToolkitBuilderOption {
  ConnectorToolkitBuilderOption({required super.icon, required super.text, required super.selectedText, required this.connectors});

  final List<Connector> connectors;

  @override
  Future<ToolkitConfig> build(RoomClient room) async {
    //for (final connector in connectors) {
    //await connector.authenticate(room);

    // TODO: connector.server.copyWith(authorization: await connector.authenticate(room))
    //}

    final servers = [for (final connector in connectors) connector.server];
    return MCPConfig(servers: servers);
  }
}

class ChatThreadInput extends StatefulWidget {
  const ChatThreadInput({
    super.key,
    required this.room,
    required this.onSend,
    required this.controller,
    this.placeholder,
    this.onChanged,
    this.attachmentBuilder,
    this.leading,
    this.trailing,
    this.header,
    this.footer,
    this.onClear,
  });

  final Widget? placeholder;

  final RoomClient room;
  final void Function(String, List<FileAttachment>) onSend;
  final void Function(String, List<FileAttachment>)? onChanged;
  final void Function()? onClear;
  final ChatThreadController controller;
  final Widget Function(BuildContext context, FileAttachment upload)? attachmentBuilder;
  final Widget? leading;
  final Widget? trailing;
  final Widget? header;
  final Widget? footer;
  @override
  State createState() => _ChatThreadInput();
}

class _ChatThreadInput extends State<ChatThreadInput> {
  bool showSendButton = false;
  bool allAttachmentsUploaded = true;

  String text = "";
  List<FileAttachment> attachments = [];

  late final focusNode = FocusNode(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
        widget.onSend(widget.controller.text, widget.controller.attachmentUploads);

        widget.controller.textFieldController.clear();

        return KeyEventResult.handled;
      }

      if (event is KeyDownEvent && event.character == "l" && HardwareKeyboard.instance.isControlPressed) {
        if (widget.onClear != null) {
          widget.onClear!();
        }
      }

      return KeyEventResult.ignored;
    },
  );

  void _onTextChanged() {
    final newText = widget.controller.text;

    setState(() {
      text = newText;
    });

    widget.onChanged?.call(text, attachments);

    setShowSendButton();
  }

  void _onChanged() {
    final newAttachments = widget.controller.attachmentUploads;

    setState(() {
      attachments = newAttachments;
    });

    widget.onChanged?.call(text, attachments);

    setShowSendButton();

    bool allCompleted = true;
    if (attachments.isNotEmpty) {
      allCompleted = attachments.every((upload) => (upload.status == UploadStatus.completed));
    }
    if (allCompleted != allAttachmentsUploaded) {
      setState(() {
        allAttachmentsUploaded = allCompleted;
      });
    }
  }

  void setShowSendButton() {
    final value = text.isNotEmpty || attachments.isNotEmpty;

    if (showSendButton != value) {
      setState(() {
        showSendButton = value;
      });
    }
  }

  @override
  void initState() {
    super.initState();

    widget.controller.textFieldController.addListener(_onTextChanged);
    widget.controller.addListener(_onChanged);
    ClipboardEvents.instance?.registerPasteEventListener(onPasteEvent);
  }

  @override
  void dispose() {
    super.dispose();

    widget.controller.removeListener(_onChanged);
    widget.controller.textFieldController.removeListener(_onTextChanged);

    focusNode.dispose();
    ClipboardEvents.instance?.unregisterPasteEventListener(onPasteEvent);
  }

  Future<DataReaderFile> _getFile(DataReader reader, SimpleFileFormat? format) {
    final completer = Completer<DataReaderFile>();

    reader.getFile(format, completer.complete, onError: completer.completeError);

    return completer.future;
  }

  Future<void> onFileDrop(String name, Stream<Uint8List> dataStream, int size) async {
    widget.controller.uploadFile(name, dataStream, size);
  }

  void onPasteEvent(ClipboardReadEvent event) async {
    if (focusNode.hasFocus) {
      final reader = await event.getClipboardReader();

      final name = (await reader.getSuggestedName());
      if (name != null) {
        final fmt = _preferredFormats.firstWhereOrNull((f) => reader.canProvide(f));
        final file = await _getFile(reader, fmt);

        await onFileDrop(name, file.getStream(), file.fileSize ?? 0);
      } else {
        if (reader.canProvide(Formats.plainText)) {
          final text = await reader.readValue(Formats.plainText);
          if (text != null) {
            onTextPaste(text);
          }
        }
      }
    }
  }

  void onTextPaste(String text) async {
    final controller = widget.controller;

    final currentText = controller.textFieldController.text;
    final selection = controller.textFieldController.selection;

    // Get the text before and after the selection
    final textBefore = currentText.substring(0, selection.start);
    final textAfter = currentText.substring(selection.end);

    // Construct the new text
    final newText = textBefore + text + textAfter;

    // Calculate the new selection (cursor at the end of the inserted text)
    final newSelection = TextSelection.collapsed(offset: textBefore.length + text.length);

    // Update the controller's value
    controller.textFieldController.value = TextEditingValue(text: newText, selection: newSelection);
  }

  @override
  Widget build(BuildContext context) {
    final trailer =
        widget.trailing ??
        (showSendButton && allAttachmentsUploaded
            ? ShadTooltip(
                waitDuration: Duration(seconds: 1),
                builder: (context) => Text("Send"),
                child: ShadIconButton(
                  cursor: SystemMouseCursors.click,
                  onPressed: () {
                    widget.onSend(widget.controller.text, widget.controller.attachmentUploads);
                  },
                  width: 32,
                  height: 32,
                  iconSize: 16,
                  decoration: ShadDecoration(shape: BoxShape.circle, color: ShadTheme.of(context).colorScheme.foreground),
                  icon: Icon(LucideIcons.arrowUp, color: ShadTheme.of(context).colorScheme.background),
                ),
              )
            : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.header != null) widget.header!,
        ShadInput(
          contextMenuBuilder: (context, editableTextState) =>
              AdaptiveTextSelectionToolbar.editableText(editableTextState: editableTextState),
          top: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              if (attachments.isEmpty) {
                return SizedBox.shrink();
              }

              return Padding(
                padding: EdgeInsets.all(8),
                child: LayoutBuilder(
                  builder: (context, constraints) => SizedBox(
                    height: 40,
                    child: Center(
                      child: ListView.separated(
                        itemCount: attachments.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 10),
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (context, index) {
                          final attachment = attachments[index];

                          if (widget.attachmentBuilder != null) {
                            return widget.attachmentBuilder!(context, attachment);
                          }

                          return FileDefaultAttachmentPreview(
                            attachment: attachment,
                            maxWidth: constraints.maxWidth - 50,
                            onRemove: () {
                              widget.controller.removeFileUpload(attachment);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          crossAxisAlignment: CrossAxisAlignment.center,
          inputPadding: EdgeInsets.all(2),
          leading: widget.leading ?? SizedBox(width: 3),
          trailing: widget.footer == null ? trailer : null,
          padding: EdgeInsets.only(left: 5, right: 5, top: widget.footer == null ? 5 : 10, bottom: 5),
          decoration: ShadDecoration(
            secondaryFocusedBorder: ShadBorder.none,
            secondaryBorder: ShadBorder.none,
            color: ShadTheme.of(context).ghostButtonTheme.hoverBackgroundColor,
            border: ShadBorder.all(radius: BorderRadius.circular(20)),
          ),
          maxLines: 8,
          minLines: 1,
          placeholder: widget.placeholder,
          focusNode: focusNode,
          controller: widget.controller.textFieldController,
          bottom: widget.footer == null
              ? null
              : Padding(
                  padding: EdgeInsets.only(left: 5, right: 5, top: 5, bottom: 0),
                  child: Row(
                    children: [
                      Expanded(child: widget.footer!),
                      ?trailer,
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class ChatThread extends StatefulWidget {
  const ChatThread({
    super.key,
    required this.path,
    required this.document,
    required this.room,

    this.startChatCentered = false,
    this.initialMessage,
    this.onMessageSent,
    this.controller,

    this.messageHeaderBuilder,
    this.waitingForParticipantsBuilder,
    this.attachmentBuilder,
    this.fileInThreadBuilder,
    this.toolsBuilder,

    this.agentName,
  });

  final String? agentName;

  final String path;
  final MeshDocument document;
  final RoomClient room;
  final bool startChatCentered;
  final ChatMessage? initialMessage;
  final void Function(ChatMessage message)? onMessageSent;
  final ChatThreadController? controller;

  final Widget Function(BuildContext, MeshDocument, MeshElement)? messageHeaderBuilder;
  final Widget Function(BuildContext, List<String>)? waitingForParticipantsBuilder;
  final Widget Function(BuildContext context, FileAttachment upload)? attachmentBuilder;
  final Widget Function(BuildContext context, String path)? fileInThreadBuilder;
  final Widget Function(BuildContext, ChatThreadController, ChatThreadSnapshot)? toolsBuilder;

  @override
  State createState() => _ChatThreadState();
}

class ChatBubble extends StatefulWidget {
  const ChatBubble({super.key, this.room, required this.mine, required this.text, this.onDelete});

  final RoomClient? room;
  final bool mine;
  final String text;
  final VoidCallback? onDelete;

  @override
  State createState() => _ChatBubble();
}

class _ChatBubble extends State<ChatBubble> {
  bool hovering = false;

  final optionsController = ShadContextMenuController();

  @override
  void initState() {
    super.initState();

    optionsController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    super.dispose();
    optionsController.dispose();
  }

  Future<void> _onCopy() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;

    final text = widget.text;
    final html = md.markdownToHtml(text, extensionSet: md.ExtensionSet.gitHubFlavored, inlineSyntaxes: const [], blockSyntaxes: const []);

    final reps = <raw.DataRepresentation>[
      raw.DataRepresentation.simple(format: "text/plain", data: text),
      raw.DataRepresentation.simple(format: "text/html", data: html),
    ];

    if (!kIsWeb) {
      reps.insertAll(0, [
        raw.DataRepresentation.simple(format: "public.utf8-plain-text", data: text),
        raw.DataRepresentation.simple(format: "public.plain-text", data: text),
        raw.DataRepresentation.simple(format: "public.html", data: html),
      ]);
    }

    await clipboard.write([DataWriterItem(suggestedName: "meshwidget.widget")..add(EncodedData(reps))]);
  }

  Future<void> _onSave(RoomClient room) async {
    final fileNameController = TextEditingController();
    String path = "";

    showShadDialog<void>(
      context: context,
      builder: (context) {
        final theme = ShadTheme.of(context);
        final tt = theme.textTheme;

        return ShadDialog(
          title: Text("Save comment file as ..."),
          crossAxisAlignment: CrossAxisAlignment.start,
          constraints: BoxConstraints(maxWidth: 700, maxHeight: 544),
          scrollable: false,
          actions: [
            ShadButton.secondary(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("Cancel"),
            ),
            ShadButton(
              onPressed: () async {
                final f = fileNameController.text.trim();
                String fileName = f.isEmpty ? "chat-comment.md" : f;

                if (!fileName.endsWith(".md")) {
                  fileName = "$fileName.md";
                }

                final fullPath = path.isEmpty ? fileName : "$path/$fileName";

                // Check if file exists
                final exists = await room.storage.exists(fullPath);

                if (exists && context.mounted) {
                  // Show overwrite confirmation
                  final overwrite = await showShadDialog<bool>(
                    context: context,
                    builder: (context) => ShadDialog(
                      title: Text("File already exists"),
                      description: Text(
                        "A file with the name '$fileName' already exists in the selected folder. Do you want to overwrite it?",
                      ),
                      actions: [
                        ShadButton.secondary(
                          onPressed: () {
                            Navigator.of(context).pop(false);
                          },
                          child: Text("Cancel"),
                        ),
                        ShadButton(
                          onPressed: () {
                            Navigator.of(context).pop(true);
                          },
                          child: Text("Overwrite"),
                        ),
                      ],
                    ),
                  );

                  if (overwrite != true) {
                    return;
                  }
                }

                final handle = await widget.room?.storage.open(fullPath, overwrite: true);

                if (handle == null) {
                  return;
                }

                await room.storage.write(handle, utf8.encode(widget.text));
                await room.storage.close(handle);

                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: Text("Save"),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FileBrowser(
                  onSelectionChanged: (selection) {
                    path = selection.join("/");
                  },
                  room: room,
                  multiple: false,
                  selectionMode: FileBrowserSelectionMode.folders,
                  rootLabel: "Folders",
                ),
              ),
              Padding(
                padding: .only(top: 12.0),
                child: ShadInputFormField(
                  label: Text('Enter File Name', style: tt.small.copyWith(fontWeight: FontWeight.bold)),
                  placeholder: const Text('chat-comment.md'),
                  keyboardType: TextInputType.emailAddress,
                  controller: fileNameController,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onDelete() {
    showShadDialog<void>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text("Delete Message"),
        description: Text("Are you sure you want to delete this message? This action cannot be undone."),
        actions: [
          ShadButton.secondary(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text("Cancel"),
          ),
          ShadButton(
            onPressed: () {
              widget.onDelete?.call();
              Navigator.of(context).pop();
            },
            child: Text("Delete"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final cs = theme.colorScheme;
    final text = widget.text;
    final mine = widget.mine;
    final openOptions = optionsController.isOpen || hovering;

    final actions = Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Opacity(
            opacity: openOptions ? 1 : 0,
            child: Padding(
              padding: EdgeInsets.only(bottom: 5),
              child: ShadContextMenuRegion(
                controller: optionsController,
                constraints: const BoxConstraints(minWidth: 200),
                items: [
                  ShadContextMenuItem(height: 40, onPressed: _onCopy, child: Text('Copy')),

                  if (widget.room != null)
                    ShadContextMenuItem(
                      height: 40,
                      onPressed: () {
                        _onSave(widget.room!);
                      },
                      child: Text('Save as...'),
                    ),

                  if (widget.onDelete != null) ShadContextMenuItem(height: 40, onPressed: _onDelete, child: Text('Delete')),
                ],
                child: ShadButton.ghost(
                  height: 30,
                  width: 30,
                  padding: EdgeInsets.zero,
                  onPressed: optionsController.show,
                  child: Icon(LucideIcons.ellipsis, size: 18, color: cs.mutedForeground),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return ShadGestureDetector(
      onHoverChange: (h) {
        setState(() {
          hovering = h;
        });
      },
      onLongPress: optionsController.show,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 5),
        color: Colors.transparent,
        child: Container(
          margin: EdgeInsets.only(top: 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (mine) actions,
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: theme.ghostButtonTheme.hoverBackgroundColor, borderRadius: BorderRadius.circular(8)),
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
                    child: MarkdownWidget(
                      padding: const EdgeInsets.all(0),
                      config: buildChatBubbleMarkdownConfig(context, threadTypography: true),
                      shrinkWrap: true,
                      selectable: kIsWeb,

                      /*builders: {
      "code": CodeElementBuilder(
          document: ChatDocumentProvider.of(context).document,
          api: TimuApiProvider.of(context).api,
          layer: layer),
},*/
                      data: text,
                    ),
                  ),
                ),
              ),
              if (!mine) actions,
            ],
          ),
        ),
      ),
    );
  }
}

class ChatMessage {
  const ChatMessage({required this.id, required this.text, this.attachments = const []});

  final String id;
  final String text;
  final List<String> attachments;
}

class _ChatThreadState extends State<ChatThread> {
  late final ChatThreadController controller;
  OutboundEntry? _currentStatusEntry;

  @override
  void initState() {
    super.initState();

    controller = widget.controller ?? ChatThreadController(room: widget.room);

    if (widget.initialMessage != null) {
      controller.send(thread: widget.document, path: widget.path, message: widget.initialMessage!, onMessageSent: widget.onMessageSent);
    }

    controller.outboundStatus.addListener(() {
      setState(() {
        _currentStatusEntry = controller.outboundStatus.currentEntry();
      });
    });
  }

  @override
  void dispose() {
    super.dispose();

    if (widget.controller == null) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChatThreadBuilder(
      path: widget.path,
      document: widget.document,
      room: widget.room,
      controller: controller,
      agentName: widget.agentName,
      builder: (context, state) {
        if (state.offline.isNotEmpty && widget.waitingForParticipantsBuilder != null) {
          return widget.waitingForParticipantsBuilder!(context, state.offline.toList());
        }

        bool bottomAlign = !widget.startChatCentered || state.messages.isNotEmpty;

        return FileDropArea(
          onFileDrop: (name, dataStream, size) async {
            widget.controller?.uploadFile(name, dataStream, size ?? 0);
          },

          child: Column(
            mainAxisAlignment: bottomAlign ? MainAxisAlignment.end : MainAxisAlignment.center,
            children: [
              ChatThreadMessages(
                room: widget.room,
                path: widget.path,
                agentName: widget.agentName,
                startChatCentered: widget.startChatCentered,
                messages: state.messages,
                online: state.online,
                showTyping: (state.threadStatusMode != null) && state.listening.isEmpty,
                showListening: state.listening.isNotEmpty,
                threadStatus: state.threadStatus,
                threadStatusMode: state.threadStatusMode,
                onCancel: () {
                  controller.cancel(widget.path, widget.document);
                },
                messageHeaderBuilder: widget.messageHeaderBuilder,
                fileInThreadBuilder: widget.fileInThreadBuilder,
                currentStatusEntry: _currentStatusEntry,
              ),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => ChatThreadInputFrame(
                  child: ChatThreadInput(
                    onClear: () {
                      final participant = widget.room.messaging.remoteParticipants.firstWhereOrNull(
                        (x) => x.getAttribute("name") == widget.agentName,
                      );
                      if (participant != null) {
                        widget.room.messaging.sendMessage(to: participant, type: "clear", message: {"path": widget.path});
                      }
                    },
                    leading: controller.toolkits.isNotEmpty
                        ? null
                        : widget.toolsBuilder == null
                        ? null
                        : widget.toolsBuilder!(context, controller, state),
                    footer: controller.toolkits.isEmpty
                        ? null
                        : widget.toolsBuilder == null
                        ? null
                        : widget.toolsBuilder!(context, controller, state),
                    trailing: null,
                    room: widget.room,
                    onSend: (value, attachments) {
                      final messageType = state.threadStatusMode == "steerable" ? "steer" : "chat";
                      controller.send(
                        thread: widget.document,
                        path: widget.path,
                        message: ChatMessage(id: const Uuid().v4(), text: value, attachments: attachments.map((x) => x.path).toList()),
                        messageType: messageType,
                        onMessageSent: widget.onMessageSent,
                      );
                    },
                    onChanged: (value, attachments) {
                      for (final part in controller.getOnlineParticipants(widget.document)) {
                        if (part.id != widget.room.localParticipant?.id) {
                          widget.room.messaging.sendMessage(to: part, type: "typing", message: {"path": widget.path});
                        }
                      }
                    },
                    controller: controller,
                    attachmentBuilder: widget.attachmentBuilder,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

typedef MessageBuilder =
    Widget Function({
      Key? key,
      required RoomClient room,
      required MeshElement? previous,
      required MeshElement message,
      required MeshElement? next,
    });

class ChatThreadMessages extends StatefulWidget {
  const ChatThreadMessages({
    super.key,
    required this.room,
    required this.path,
    required this.messages,
    required this.online,

    this.startChatCentered = false,
    this.showTyping = false,
    this.showListening = false,
    this.threadStatus,
    this.threadStatusMode,
    this.onCancel,
    this.agentName,
    this.messageHeaderBuilder,
    this.fileInThreadBuilder,
    this.currentStatusEntry,
    this.messageBuilders,
  });

  final Map<String, MessageBuilder>? messageBuilders;

  final RoomClient room;
  final String path;
  final String? agentName;
  final bool startChatCentered;
  final bool showTyping;
  final bool showListening;
  final String? threadStatus;
  final String? threadStatusMode;
  final void Function()? onCancel;
  final List<MeshElement> messages;
  final List<Participant> online;
  final OutboundEntry? currentStatusEntry;

  final Widget Function(BuildContext, MeshDocument, MeshElement)? messageHeaderBuilder;
  final Widget Function(BuildContext context, String path)? fileInThreadBuilder;

  @override
  State<ChatThreadMessages> createState() => _ChatThreadMessagesState();
}

class _ChatThreadMessagesState extends State<ChatThreadMessages> {
  RoomClient get room => widget.room;
  String get path => widget.path;
  String? get agentName => widget.agentName;
  bool get startChatCentered => widget.startChatCentered;
  bool get showTyping => widget.showTyping;
  bool get showListening => widget.showListening;
  String? get threadStatus => widget.threadStatus;
  String? get threadStatusMode => widget.threadStatusMode;
  void Function()? get onCancel => widget.onCancel;
  List<MeshElement> get messages => widget.messages;
  List<Participant> get online => widget.online;
  OutboundEntry? get currentStatusEntry => widget.currentStatusEntry;
  Map<String, MessageBuilder>? get messageBuilders => widget.messageBuilders;
  Widget Function(BuildContext, MeshDocument, MeshElement)? get messageHeaderBuilder => widget.messageHeaderBuilder;
  Widget Function(BuildContext context, String path)? get fileInThreadBuilder => widget.fileInThreadBuilder;

  final OverlayPortalController _imageViewerController = OverlayPortalController();
  List<_ThreadFeedImage> _overlayImages = const <_ThreadFeedImage>[];
  int _overlayInitialIndex = 0;
  LocalHistoryEntry? _imageViewerHistoryEntry;

  void _hideThreadImageViewer() {
    _imageViewerController.hide();
    if (mounted) {
      setState(() {});
    }
  }

  void _closeThreadImageViewer() {
    final historyEntry = _imageViewerHistoryEntry;
    if (historyEntry != null) {
      _imageViewerHistoryEntry = null;
      historyEntry.remove();
      return;
    }
    _hideThreadImageViewer();
  }

  void _openThreadImageViewer(BuildContext context, {required List<_ThreadFeedImage> images, required int initialIndex}) {
    if (images.isEmpty) {
      return;
    }

    final route = ModalRoute.of(context);
    if (_imageViewerHistoryEntry == null && route != null) {
      final historyEntry = LocalHistoryEntry(
        onRemove: () {
          _imageViewerHistoryEntry = null;
          _hideThreadImageViewer();
        },
      );
      _imageViewerHistoryEntry = historyEntry;
      route.addLocalHistoryEntry(historyEntry);
    }

    final clampedInitialIndex = initialIndex.clamp(0, images.length - 1);
    setState(() {
      _overlayImages = List<_ThreadFeedImage>.unmodifiable(images);
      _overlayInitialIndex = clampedInitialIndex;
    });
    _imageViewerController.show();
  }

  @override
  void dispose() {
    final historyEntry = _imageViewerHistoryEntry;
    _imageViewerHistoryEntry = null;
    historyEntry?.remove();
    super.dispose();
  }

  List<_ThreadFeedImage> _collectThreadImages() {
    final imagesInThread = <_ThreadFeedImage>[];

    for (final message in messages) {
      for (final attachment in message.getChildren().whereType<MeshElement>()) {
        if (attachment.tagName != "image") {
          continue;
        }

        final imageIdAttribute = attachment.getAttribute("id");
        final imageId = (imageIdAttribute is String && imageIdAttribute.trim().isNotEmpty) ? imageIdAttribute.trim() : null;
        if (imageId == null) {
          continue;
        }
        final attachmentElementId = attachment.id;
        if (attachmentElementId == null || attachmentElementId.trim().isEmpty) {
          continue;
        }

        final mimeTypeAttribute = attachment.getAttribute("mime_type");
        final mimeType = mimeTypeAttribute is String ? mimeTypeAttribute : null;
        final statusAttribute = attachment.getAttribute("status");
        final status = statusAttribute is String ? statusAttribute.trim() : null;
        final statusDetailAttribute = attachment.getAttribute("status_detail");
        final statusDetail = statusDetailAttribute is String ? statusDetailAttribute.trim() : null;
        final width = _parsePositiveDimension(attachment.getAttribute("width"));
        final height = _parsePositiveDimension(attachment.getAttribute("height"));

        imagesInThread.add(
          _ThreadFeedImage(
            attachmentElementId: attachmentElementId,
            imageId: imageId,
            mimeType: mimeType,
            status: status,
            statusDetail: statusDetail,
            widthPx: width,
            heightPx: height,
          ),
        );
      }
    }

    return imagesInThread;
  }

  String _sanitizePath(String path) {
    return path.replaceFirst(RegExp(r'^/'), '');
  }

  Widget _buildFileInThread(BuildContext context, String path) {
    path = _sanitizePath(path);

    return ShadGestureDetector(
      cursor: SystemMouseCursors.click,
      onTap: () {
        showShadDialog(
          context: context,
          builder: (context) {
            return ShadDialog(
              crossAxisAlignment: CrossAxisAlignment.start,
              title: Text("File: $path"),
              actions: [
                ShadButton(
                  onPressed: () async {
                    final url = await room.storage.downloadUrl(path);

                    launchUrl(Uri.parse(url));
                  },
                  child: Text("Download"),
                ),
              ],
              child: FilePreview(room: room, path: path, fit: BoxFit.cover),
            );
          },
        );
      },
      child: fileInThreadBuilder != null ? fileInThreadBuilder!(context, path) : ChatThreadPreview(room: room, path: path),
    );
  }

  Widget _buildImageInThread(BuildContext context, MeshElement attachment, {required List<_ThreadFeedImage> feedImages}) {
    final imageIdAttribute = attachment.getAttribute("id");
    final imageId = (imageIdAttribute is String && imageIdAttribute.trim().isNotEmpty) ? imageIdAttribute.trim() : null;

    final mimeTypeAttribute = attachment.getAttribute("mime_type");
    final mimeType = mimeTypeAttribute is String ? mimeTypeAttribute : null;
    final statusAttribute = attachment.getAttribute("status");
    final status = statusAttribute is String ? statusAttribute.trim() : null;
    final statusDetailAttribute = attachment.getAttribute("status_detail");
    final statusDetail = statusDetailAttribute is String ? statusDetailAttribute.trim() : null;
    final width = _parsePositiveDimension(attachment.getAttribute("width"));
    final height = _parsePositiveDimension(attachment.getAttribute("height"));
    final initialIndex = feedImages.indexWhere((entry) => entry.attachmentElementId == attachment.id);

    VoidCallback? onOpenFullscreen;
    if (initialIndex >= 0 && feedImages.isNotEmpty) {
      onOpenFullscreen = () {
        _openThreadImageViewer(context, images: feedImages, initialIndex: initialIndex);
      };
    }

    return ChatThreadImageAttachment(
      room: room,
      imageId: imageId,
      fallbackMimeType: mimeType,
      status: status,
      statusDetail: statusDetail,
      widthPx: width,
      heightPx: height,
      roundedCorners: false,
      onOpenFullscreen: onOpenFullscreen,
    );
  }

  double? _parsePositiveDimension(Object? value) {
    if (value is num) {
      final dimension = value.toDouble();
      return dimension > 0 ? dimension : null;
    }

    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    return null;
  }

  Widget _buildAttachmentInThread(BuildContext context, MeshElement attachment, {required List<_ThreadFeedImage> feedImages}) {
    if (attachment.tagName == "image") {
      return _buildImageInThread(context, attachment, feedImages: feedImages);
    }

    final pathAttribute = attachment.getAttribute("path");
    if (pathAttribute is! String || pathAttribute.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildFileInThread(context, pathAttribute);
  }

  bool _defaultHeaderWillRender({required MeshElement message}) {
    final doc = message.doc;
    if (doc is! MeshDocument) {
      return false;
    }

    final localParticipantName = room.localParticipant?.getAttribute("name");
    return _shouldShowAuthorNames(thread: doc, localParticipantName: localParticipantName is String ? localParticipantName : null);
  }

  Widget _buildMessage(
    BuildContext context,
    MeshElement? previous,
    MeshElement message,
    MeshElement? next, {
    required List<_ThreadFeedImage> feedImages,
  }) {
    final isSameAuthor = message.getAttribute("author_name") == previous?.getAttribute("author_name");
    final localParticipantName = room.localParticipant?.getAttribute("name");
    final mine = message.getAttribute("author_name") == localParticipantName;
    final useDefaultHeaderBuilder = messageHeaderBuilder == null;
    final shouldShowHeader = !isSameAuthor && (!useDefaultHeaderBuilder || _defaultHeaderWillRender(message: message));

    final text = message.getAttribute("text");
    final hasText = text is String && text.isNotEmpty;
    final attachments = message.getChildren().whereType<MeshElement>().toList();
    final id = message.getAttribute("id");

    if (messageBuilders?[message.tagName] != null) {
      return messageBuilders![message.tagName]!(room: room, previous: previous, message: message, next: next);
    }

    if (message.tagName == "reasoning") {
      final summary = (message.getAttribute("summary") ?? "").toString().trim();
      if (summary.isEmpty) {
        return const SizedBox.shrink();
      }
      return ReasoningTrace(previous: previous, message: message, next: next);
    }
    if (message.tagName == "exec") {
      return ShellLine(previous: previous, message: message, next: next);
    }
    if (message.tagName == "event") {
      return EventLine(previous: previous, message: message, next: next, room: room, path: path, agentName: agentName);
    }

    return SizedBox(
      key: ValueKey(id),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shouldShowHeader)
            Container(
              margin: EdgeInsets.only(right: mine ? 0 : 50, left: mine ? 50 : 0, bottom: 6),
              child: Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child:
                    messageHeaderBuilder?.call(context, message.doc as MeshDocument, message) ??
                    defaultMessageHeaderBuilder(
                      context,
                      message.doc as MeshDocument,
                      message,
                      localParticipantName: localParticipantName is String ? localParticipantName : null,
                    ),
              ),
            ),

          if (hasText)
            Padding(
              padding: EdgeInsets.only(top: 0),
              child: ChatBubble(room: room, mine: mine, text: message.getAttribute("text"), onDelete: message.delete),
            ),

          for (final attachment in attachments.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Container(
                margin: EdgeInsets.only(top: 0),
                child: Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: _buildAttachmentInThread(context, attachment.$2, feedImages: feedImages),
                ),
              ),
            ),

          if (currentStatusEntry != null && currentStatusEntry?.messageId == id)
            Padding(
              padding: EdgeInsets.only(top: 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  currentStatusEntry!.state.status.name,
                  style: ShadTheme.of(context).textTheme.p.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(currentStatusEntry!.state.status.colorValue),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool bottomAlign = !startChatCentered || messages.isNotEmpty;
    final feedImages = _collectThreadImages();

    final messageWidgets = <Widget>[];
    for (var message in messages.indexed) {
      final previous = message.$1 > 0 ? messages[message.$1 - 1] : null;
      final next = message.$1 < messages.length - 1 ? messages[message.$1 + 1] : null;

      final messageWidget = Container(
        key: ValueKey(message.$2.id),
        child: _buildMessage(context, previous, message.$2, next, feedImages: feedImages),
      );

      if (messageWidgets.isNotEmpty) {
        messageWidgets.insert(0, const SizedBox(height: 12));
      }
      messageWidgets.insert(0, messageWidget);
    }
    final threadView = ChatThreadViewportBody(
      bottomAlign: bottomAlign,
      centerContent: !bottomAlign && online.firstOrNull != null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 50),
              child: Text(
                online.first.getAttribute("empty_state_title") ?? "How can I help you?",
                style: ShadTheme.of(context).textTheme.h3,
              ),
            )
          : null,
      bottomSpacer: showTyping ? 20 : 0,
      overlays: [
        if (showTyping)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: EdgeInsets.symmetric(horizontal: chatThreadStatusHorizontalPadding(constraints.maxWidth)),
                child: ChatThreadProcessingStatusRow(
                  text: (threadStatus?.trim().isNotEmpty ?? false) ? threadStatus!.trim() : "Thinking",
                  onCancel: threadStatusMode != null ? onCancel : null,
                ),
              ),
            ),
          ),
        if (showListening)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 912),
                child: SizedBox(
                  height: 1,
                  child: LinearProgressIndicator(
                    backgroundColor: ShadTheme.of(context).colorScheme.background,
                    color: ShadTheme.of(context).colorScheme.mutedForeground,
                  ),
                ),
              ),
            ),
          ),
      ],
      children: messageWidgets,
    );

    return Expanded(
      child: OverlayPortal(
        controller: _imageViewerController,
        overlayLocation: OverlayChildLocation.rootOverlay,
        overlayChildBuilder: (context) {
          if (_overlayImages.isEmpty) {
            return const SizedBox.shrink();
          }
          return _ThreadImageGalleryPage(
            room: room,
            images: _overlayImages,
            initialIndex: _overlayInitialIndex,
            onClose: _closeThreadImageViewer,
          );
        },
        child: threadView,
      ),
    );
  }
}

class _ThreadImageRecord {
  const _ThreadImageRecord({required this.data, required this.mimeType});

  final Uint8List data;
  final String mimeType;
}

class _ThreadFeedImage {
  const _ThreadFeedImage({
    required this.attachmentElementId,
    required this.imageId,
    this.mimeType,
    this.status,
    this.statusDetail,
    this.widthPx,
    this.heightPx,
  });

  final String attachmentElementId;
  final String imageId;
  final String? mimeType;
  final String? status;
  final String? statusDetail;
  final double? widthPx;
  final double? heightPx;
}

class ChatThreadImageAttachment extends StatefulWidget {
  const ChatThreadImageAttachment({
    super.key,
    required this.room,
    required this.imageId,
    this.fallbackMimeType,
    this.status,
    this.statusDetail,
    this.widthPx,
    this.heightPx,
    this.roundedCorners = true,
    this.onOpenFullscreen,
  });

  final RoomClient room;
  final String? imageId;
  final String? fallbackMimeType;
  final String? status;
  final String? statusDetail;
  final double? widthPx;
  final double? heightPx;
  final bool roundedCorners;
  final VoidCallback? onOpenFullscreen;

  @override
  State<ChatThreadImageAttachment> createState() => _ChatThreadImageAttachmentState();
}

class _ChatThreadImageAttachmentState extends State<ChatThreadImageAttachment> {
  late Future<_ThreadImageRecord?> _lookup;

  @override
  void initState() {
    super.initState();
    _lookup = _loadImage();
  }

  @override
  void didUpdateWidget(covariant ChatThreadImageAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageId != widget.imageId || oldWidget.room != widget.room) {
      _lookup = _loadImage();
    }
  }

  Future<_ThreadImageRecord?> _loadImage() async {
    final imageId = widget.imageId;
    if (imageId == null || imageId.trim().isEmpty) {
      return null;
    }

    final rows = await widget.room.database.search(table: "images", where: {"id": imageId}, limit: 1, select: ["data", "mime_type"]);
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final data = row["data"];
    if (data is! Uint8List) {
      return null;
    }

    final value = row["mime_type"];
    final mimeType = (value is String && value.trim().isNotEmpty) ? value : (widget.fallbackMimeType ?? "image/png");

    return _ThreadImageRecord(data: data, mimeType: mimeType);
  }

  bool _isSvg(String mimeType) {
    final normalized = mimeType.toLowerCase();
    return normalized == "image/svg+xml" || normalized == "image/svg";
  }

  bool _isGeneratingStatus(String? status) {
    if (status == null || status.trim().isEmpty) {
      return false;
    }

    final normalized = status.toLowerCase();
    return normalized == "generating" ||
        normalized == "in_progress" ||
        normalized == "queued" ||
        normalized == "running" ||
        normalized == "pending";
  }

  bool _isFailedStatus(String? status) {
    if (status == null) {
      return false;
    }
    final normalized = status.toLowerCase();
    return normalized == "failed" || normalized == "cancelled";
  }

  Size _displaySize() {
    const maxPreviewEdge = 312.5;
    const fallbackPreviewEdge = 312.5;

    final rawWidth = widget.widthPx;
    final rawHeight = widget.heightPx;
    if (rawWidth == null || rawHeight == null || rawWidth <= 0 || rawHeight <= 0) {
      return const Size(fallbackPreviewEdge, fallbackPreviewEdge);
    }

    final largestEdge = math.max(rawWidth, rawHeight);
    if (largestEdge <= maxPreviewEdge) {
      return Size(rawWidth, rawHeight);
    }

    final scale = maxPreviewEdge / largestEdge;
    return Size(rawWidth * scale, rawHeight * scale);
  }

  String _defaultImageExtension(String mimeType) {
    switch (mimeType.trim().toLowerCase()) {
      case "image/jpeg":
      case "image/jpg":
        return "jpg";
      case "image/gif":
        return "gif";
      case "image/webp":
        return "webp";
      case "image/svg+xml":
      case "image/svg":
      case "public.svg-image":
        return "svg";
      case "image/tiff":
      case "image/tif":
        return "tiff";
      case "image/bmp":
        return "bmp";
      case "image/heic":
        return "heic";
      case "image/heif":
        return "heif";
      case "image/x-icon":
      case "image/vnd.microsoft.icon":
        return "ico";
      case "image/png":
      default:
        return "png";
    }
  }

  String _suggestedFileName(String mimeType) {
    return "image.${_defaultImageExtension(mimeType)}";
  }

  String _ensureFileNameExtension(String rawPath, String mimeType) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return _suggestedFileName(mimeType);
    }

    final slash = trimmed.lastIndexOf("/");
    final fileName = slash == -1 ? trimmed : trimmed.substring(slash + 1);

    if (fileName.isEmpty) {
      final suggested = _suggestedFileName(mimeType);
      return trimmed.endsWith("/") ? "$trimmed$suggested" : "$trimmed/$suggested";
    }

    if (fileName.contains(".")) {
      return trimmed;
    }

    return "$trimmed.${_defaultImageExtension(mimeType)}";
  }

  FileFormat? _clipboardImageFormat(String mimeType) {
    switch (mimeType.trim().toLowerCase()) {
      case "image/jpeg":
      case "image/jpg":
        return Formats.jpeg;
      case "image/gif":
        return Formats.gif;
      case "image/webp":
        return Formats.webp;
      case "image/svg+xml":
      case "image/svg":
      case "public.svg-image":
        return Formats.svg;
      case "image/tiff":
      case "image/tif":
        return Formats.tiff;
      case "image/bmp":
        return Formats.bmp;
      case "image/heic":
        return Formats.heic;
      case "image/heif":
        return Formats.heif;
      case "image/x-icon":
      case "image/vnd.microsoft.icon":
        return Formats.ico;
      case "image/png":
        return Formats.png;
      default:
        return null;
    }
  }

  Future<void> _onCopyImage(_ThreadImageRecord image) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return;
    }

    final mimeType = image.mimeType.trim().toLowerCase();
    final format = _clipboardImageFormat(mimeType);
    final item = DataWriterItem(suggestedName: _suggestedFileName(mimeType));
    if (format != null) {
      item.add(format(image.data));
    } else {
      item.add(EncodedData([raw.DataRepresentation.simple(format: mimeType, data: image.data)]));
    }

    await clipboard.write([item]);
  }

  Future<void> _onSaveImage(_ThreadImageRecord image) async {
    final fileNameController = TextEditingController(text: _suggestedFileName(image.mimeType));
    String selectedFolder = "";

    await showShadDialog<void>(
      context: context,
      builder: (context) {
        final theme = ShadTheme.of(context);
        final tt = theme.textTheme;

        return ShadDialog(
          title: const Text("Save image as ..."),
          crossAxisAlignment: CrossAxisAlignment.start,
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 544),
          scrollable: false,
          actions: [
            ShadButton.secondary(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
            ShadButton(
              onPressed: () async {
                final value = fileNameController.text.trim();
                var fullPath = value.isEmpty ? _suggestedFileName(image.mimeType) : value;

                if (!fullPath.contains("/")) {
                  fullPath = selectedFolder.isEmpty ? fullPath : "$selectedFolder/$fullPath";
                }
                fullPath = _ensureFileNameExtension(fullPath, image.mimeType);

                final exists = await widget.room.storage.exists(fullPath);
                if (exists && context.mounted) {
                  final overwrite = await showShadDialog<bool>(
                    context: context,
                    builder: (context) => ShadDialog(
                      title: const Text("File already exists"),
                      description: Text("A file at '$fullPath' already exists in room storage. Do you want to overwrite it?"),
                      actions: [
                        ShadButton.secondary(
                          onPressed: () {
                            Navigator.of(context).pop(false);
                          },
                          child: const Text("Cancel"),
                        ),
                        ShadButton(
                          onPressed: () {
                            Navigator.of(context).pop(true);
                          },
                          child: const Text("Overwrite"),
                        ),
                      ],
                    ),
                  );

                  if (overwrite != true) {
                    return;
                  }
                }

                final handle = await widget.room.storage.open(fullPath, overwrite: true);
                await widget.room.storage.write(handle, image.data);
                await widget.room.storage.close(handle);

                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text("Save"),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FileBrowser(
                  onSelectionChanged: (selection) {
                    selectedFolder = selection.join("/");
                  },
                  room: widget.room,
                  multiple: false,
                  selectionMode: FileBrowserSelectionMode.folders,
                  rootLabel: "Folders",
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ShadInputFormField(
                  label: Text("File name or path", style: tt.small.copyWith(fontWeight: FontWeight.bold)),
                  placeholder: Text(_suggestedFileName(image.mimeType)),
                  controller: fileNameController,
                ),
              ),
            ],
          ),
        );
      },
    );
    fileNameController.dispose();
  }

  Widget _wrapContextMenu({required _ThreadImageRecord image, required Widget child}) {
    return ShadContextMenuRegion(
      items: [
        ShadContextMenuItem(height: 40, onPressed: () => _onSaveImage(image), child: const Text("Save As...")),
        ShadContextMenuItem(height: 40, onPressed: () => _onCopyImage(image), child: const Text("Copy")),
      ],
      child: child,
    );
  }

  Widget _wrapWithCorners(Widget child) {
    if (!widget.roundedCorners) {
      return child;
    }
    return ClipRRect(borderRadius: BorderRadius.circular(16), child: child);
  }

  Widget _wrapTapTarget(Widget child) {
    if (widget.onOpenFullscreen == null) {
      return child;
    }

    return ShadGestureDetector(cursor: SystemMouseCursors.zoomIn, onTap: widget.onOpenFullscreen, child: child);
  }

  Widget _buildPlaceholder(BuildContext context, {required bool showSpinner, String? label}) {
    final size = _displaySize();
    final trimmedLabel = label == null ? "" : label.trim();

    return SizedBox(
      width: size.width,
      height: size.height,
      child: _wrapWithCorners(
        ColoredBox(
          color: ShadTheme.of(context).colorScheme.background,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSpinner)
                  SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(LucideIcons.imageOff, size: 20, color: ShadTheme.of(context).colorScheme.mutedForeground),
                if (trimmedLabel.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      trimmedLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: ShadTheme.of(context).textTheme.small.copyWith(color: ShadTheme.of(context).colorScheme.mutedForeground),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status?.trim();
    final hasImageId = widget.imageId != null && widget.imageId!.trim().isNotEmpty;
    final statusDetail = widget.statusDetail?.trim();

    if (!hasImageId) {
      if (_isFailedStatus(status)) {
        return FileDefaultPreviewCard(icon: LucideIcons.imageOff, text: statusDetail?.isNotEmpty == true ? statusDetail! : "Image failed");
      }

      return _buildPlaceholder(context, showSpinner: true, label: statusDetail?.isNotEmpty == true ? statusDetail : "Generating image");
    }

    return FutureBuilder<_ThreadImageRecord?>(
      future: _lookup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildPlaceholder(context, showSpinner: true, label: statusDetail?.isNotEmpty == true ? statusDetail : "Loading image");
        }

        final image = snapshot.data;
        if (image == null) {
          if (_isGeneratingStatus(status)) {
            return _buildPlaceholder(
              context,
              showSpinner: true,
              label: statusDetail?.isNotEmpty == true ? statusDetail : "Generating image",
            );
          }
          if (_isFailedStatus(status)) {
            return FileDefaultPreviewCard(
              icon: LucideIcons.imageOff,
              text: statusDetail?.isNotEmpty == true ? statusDetail! : "Image failed",
            );
          }
          return const FileDefaultPreviewCard(icon: LucideIcons.imageOff, text: "Image unavailable");
        }

        final imageWidget = _isSvg(image.mimeType)
            ? SvgPicture.memory(image.data, fit: (widget.widthPx != null && widget.heightPx != null) ? BoxFit.contain : BoxFit.cover)
            : Image.memory(image.data, fit: (widget.widthPx != null && widget.heightPx != null) ? BoxFit.contain : BoxFit.cover);
        final size = _displaySize();

        final imageContainer = SizedBox(width: size.width, height: size.height, child: _wrapWithCorners(imageWidget));
        return _wrapContextMenu(image: image, child: _wrapTapTarget(imageContainer));
      },
    );
  }
}

class _ThreadImageGalleryPage extends StatefulWidget {
  const _ThreadImageGalleryPage({required this.room, required this.images, required this.initialIndex, required this.onClose});

  final RoomClient room;
  final List<_ThreadFeedImage> images;
  final int initialIndex;
  final VoidCallback onClose;

  @override
  State<_ThreadImageGalleryPage> createState() => _ThreadImageGalleryPageState();
}

class _ThreadImageGalleryPageState extends State<_ThreadImageGalleryPage> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changePage(int nextIndex) {
    if (nextIndex < 0 || nextIndex >= widget.images.length) {
      return;
    }
    _controller.animateToPage(nextIndex, duration: const Duration(milliseconds: 180), curve: Curves.easeInOut);
  }

  String _defaultImageExtension(String mimeType) {
    switch (mimeType.trim().toLowerCase()) {
      case "image/jpeg":
      case "image/jpg":
        return "jpg";
      case "image/gif":
        return "gif";
      case "image/webp":
        return "webp";
      case "image/svg+xml":
      case "image/svg":
      case "public.svg-image":
        return "svg";
      case "image/tiff":
      case "image/tif":
        return "tiff";
      case "image/bmp":
        return "bmp";
      case "image/heic":
        return "heic";
      case "image/heif":
        return "heif";
      case "image/x-icon":
      case "image/vnd.microsoft.icon":
        return "ico";
      case "image/png":
      default:
        return "png";
    }
  }

  String _suggestedFileName(String mimeType) {
    return "image.${_defaultImageExtension(mimeType)}";
  }

  String _ensureFileNameExtension(String rawPath, String mimeType) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return _suggestedFileName(mimeType);
    }

    final slash = trimmed.lastIndexOf("/");
    final fileName = slash == -1 ? trimmed : trimmed.substring(slash + 1);

    if (fileName.isEmpty) {
      final suggested = _suggestedFileName(mimeType);
      return trimmed.endsWith("/") ? "$trimmed$suggested" : "$trimmed/$suggested";
    }

    if (fileName.contains(".")) {
      return trimmed;
    }

    return "$trimmed.${_defaultImageExtension(mimeType)}";
  }

  FileFormat? _clipboardImageFormat(String mimeType) {
    switch (mimeType.trim().toLowerCase()) {
      case "image/jpeg":
      case "image/jpg":
        return Formats.jpeg;
      case "image/gif":
        return Formats.gif;
      case "image/webp":
        return Formats.webp;
      case "image/svg+xml":
      case "image/svg":
      case "public.svg-image":
        return Formats.svg;
      case "image/tiff":
      case "image/tif":
        return Formats.tiff;
      case "image/bmp":
        return Formats.bmp;
      case "image/heic":
        return Formats.heic;
      case "image/heif":
        return Formats.heif;
      case "image/x-icon":
      case "image/vnd.microsoft.icon":
        return Formats.ico;
      case "image/png":
        return Formats.png;
      default:
        return null;
    }
  }

  Future<_ThreadImageRecord?> _loadCurrentImage() async {
    final entry = widget.images[_currentIndex];
    final rows = await widget.room.database.search(table: "images", where: {"id": entry.imageId}, limit: 1, select: ["data", "mime_type"]);
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final data = row["data"];
    if (data is! Uint8List) {
      return null;
    }

    final mimeTypeValue = row["mime_type"];
    final mimeType = (mimeTypeValue is String && mimeTypeValue.trim().isNotEmpty) ? mimeTypeValue : (entry.mimeType ?? "image/png");
    return _ThreadImageRecord(data: data, mimeType: mimeType);
  }

  Future<void> _copyImageRecord(_ThreadImageRecord image) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return;
    }

    final mimeType = image.mimeType.trim().toLowerCase();
    final format = _clipboardImageFormat(mimeType);
    final item = DataWriterItem(suggestedName: _suggestedFileName(mimeType));
    if (format != null) {
      item.add(format(image.data));
    } else {
      item.add(EncodedData([raw.DataRepresentation.simple(format: mimeType, data: image.data)]));
    }

    await clipboard.write([item]);
  }

  Future<void> _onCopyCurrentImage() async {
    final image = await _loadCurrentImage();
    if (image == null) {
      return;
    }
    await _copyImageRecord(image);
  }

  Future<void> _saveImageRecord(_ThreadImageRecord image) async {
    if (!mounted) {
      return;
    }
    final fileNameController = TextEditingController(text: _suggestedFileName(image.mimeType));
    String selectedFolder = "";

    await showShadDialog<void>(
      context: context,
      builder: (context) {
        final theme = ShadTheme.of(context);
        final tt = theme.textTheme;

        return ShadDialog(
          title: const Text("Save image as ..."),
          crossAxisAlignment: CrossAxisAlignment.start,
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 544),
          scrollable: false,
          actions: [
            ShadButton.secondary(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
            ShadButton(
              onPressed: () async {
                final value = fileNameController.text.trim();
                var fullPath = value.isEmpty ? _suggestedFileName(image.mimeType) : value;

                if (!fullPath.contains("/")) {
                  fullPath = selectedFolder.isEmpty ? fullPath : "$selectedFolder/$fullPath";
                }
                fullPath = _ensureFileNameExtension(fullPath, image.mimeType);

                final exists = await widget.room.storage.exists(fullPath);
                if (exists && context.mounted) {
                  final overwrite = await showShadDialog<bool>(
                    context: context,
                    builder: (context) => ShadDialog(
                      title: const Text("File already exists"),
                      description: Text("A file at '$fullPath' already exists in room storage. Do you want to overwrite it?"),
                      actions: [
                        ShadButton.secondary(
                          onPressed: () {
                            Navigator.of(context).pop(false);
                          },
                          child: const Text("Cancel"),
                        ),
                        ShadButton(
                          onPressed: () {
                            Navigator.of(context).pop(true);
                          },
                          child: const Text("Overwrite"),
                        ),
                      ],
                    ),
                  );

                  if (overwrite != true) {
                    return;
                  }
                }

                final handle = await widget.room.storage.open(fullPath, overwrite: true);
                await widget.room.storage.write(handle, image.data);
                await widget.room.storage.close(handle);

                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text("Save"),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FileBrowser(
                  onSelectionChanged: (selection) {
                    selectedFolder = selection.join("/");
                  },
                  room: widget.room,
                  multiple: false,
                  selectionMode: FileBrowserSelectionMode.folders,
                  rootLabel: "Folders",
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ShadInputFormField(
                  label: Text("File name or path", style: tt.small.copyWith(fontWeight: FontWeight.bold)),
                  placeholder: Text(_suggestedFileName(image.mimeType)),
                  controller: fileNameController,
                ),
              ),
            ],
          ),
        );
      },
    );
    fileNameController.dispose();
  }

  Future<void> _onSaveCurrentImage() async {
    final image = await _loadCurrentImage();
    if (image == null) {
      return;
    }
    await _saveImageRecord(image);
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = _currentIndex > 0;
    final canGoForward = _currentIndex < widget.images.length - 1;

    return Positioned.fill(
      child: Material(
        color: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.images.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final image = widget.images[index];
                    return _ThreadFullscreenImage(
                      room: widget.room,
                      imageId: image.imageId,
                      fallbackMimeType: image.mimeType,
                      status: image.status,
                      statusDetail: image.statusDetail,
                      onCopyImage: _copyImageRecord,
                      onSaveImage: _saveImageRecord,
                    );
                  },
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: ShadIconButton.ghost(
                  icon: Icon(LucideIcons.x, color: Colors.white),
                  onPressed: widget.onClose,
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    ShadButton.ghost(
                      onPressed: _onCopyCurrentImage,
                      leading: const Icon(LucideIcons.copy, size: 16, color: Colors.white),
                      child: Text("Copy", style: ShadTheme.of(context).textTheme.small.copyWith(color: Colors.white)),
                    ),
                    ShadButton.ghost(
                      onPressed: _onSaveCurrentImage,
                      leading: const Icon(LucideIcons.save, size: 16, color: Colors.white),
                      child: Text("Save As...", style: ShadTheme.of(context).textTheme.small.copyWith(color: Colors.white)),
                    ),
                  ],
                ),
              ),
              if (widget.images.length > 1)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Text(
                    "${_currentIndex + 1} / ${widget.images.length}",
                    style: ShadTheme.of(context).textTheme.small.copyWith(color: Colors.white.withAlpha(220)),
                  ),
                ),
              if (widget.images.length > 1)
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: ShadIconButton.ghost(
                      icon: Icon(LucideIcons.chevronLeft, color: canGoBack ? Colors.white : Colors.white30),
                      onPressed: canGoBack ? () => _changePage(_currentIndex - 1) : null,
                    ),
                  ),
                ),
              if (widget.images.length > 1)
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: ShadIconButton.ghost(
                      icon: Icon(LucideIcons.chevronRight, color: canGoForward ? Colors.white : Colors.white30),
                      onPressed: canGoForward ? () => _changePage(_currentIndex + 1) : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadFullscreenImage extends StatelessWidget {
  const _ThreadFullscreenImage({
    required this.room,
    required this.imageId,
    this.fallbackMimeType,
    this.status,
    this.statusDetail,
    this.onCopyImage,
    this.onSaveImage,
  });

  final RoomClient room;
  final String imageId;
  final String? fallbackMimeType;
  final String? status;
  final String? statusDetail;
  final Future<void> Function(_ThreadImageRecord image)? onCopyImage;
  final Future<void> Function(_ThreadImageRecord image)? onSaveImage;

  Future<_ThreadImageRecord?> _loadImage() async {
    final rows = await room.database.search(table: "images", where: {"id": imageId}, limit: 1, select: ["data", "mime_type"]);
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final data = row["data"];
    if (data is! Uint8List) {
      return null;
    }

    final mimeTypeValue = row["mime_type"];
    final mimeType = (mimeTypeValue is String && mimeTypeValue.trim().isNotEmpty) ? mimeTypeValue : (fallbackMimeType ?? "image/png");

    return _ThreadImageRecord(data: data, mimeType: mimeType);
  }

  bool _isSvg(String mimeType) {
    final normalized = mimeType.toLowerCase();
    return normalized == "image/svg+xml" || normalized == "image/svg";
  }

  bool _isGeneratingStatus(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }

    final normalized = value.toLowerCase();
    return normalized == "generating" ||
        normalized == "in_progress" ||
        normalized == "queued" ||
        normalized == "running" ||
        normalized == "pending";
  }

  bool _isFailedStatus(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    final normalized = value.toLowerCase();
    return normalized == "failed" || normalized == "cancelled";
  }

  @override
  Widget build(BuildContext context) {
    final detail = statusDetail?.trim();
    final normalizedStatus = status?.trim();

    return FutureBuilder<_ThreadImageRecord?>(
      future: _loadImage(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        final image = snapshot.data;
        if (image == null) {
          if (_isGeneratingStatus(normalizedStatus)) {
            return Center(
              child: Text(
                detail?.isNotEmpty == true ? detail! : "Generating image",
                style: ShadTheme.of(context).textTheme.p.copyWith(color: Colors.white70),
              ),
            );
          }

          final message = _isFailedStatus(normalizedStatus) ? (detail?.isNotEmpty == true ? detail! : "Image failed") : "Image unavailable";
          return Center(
            child: Text(message, style: ShadTheme.of(context).textTheme.p.copyWith(color: Colors.white70)),
          );
        }

        final imageWidget = _isSvg(image.mimeType)
            ? SvgPicture.memory(image.data, fit: BoxFit.contain)
            : Image.memory(image.data, fit: BoxFit.contain);

        final viewer = InteractiveViewer2(
          child: Center(
            child: Padding(padding: const EdgeInsets.all(24), child: imageWidget),
          ),
        );
        if (onCopyImage == null && onSaveImage == null) {
          return viewer;
        }

        return ShadContextMenuRegion(
          items: [
            if (onSaveImage != null) ShadContextMenuItem(height: 40, onPressed: () => onSaveImage!(image), child: const Text("Save As...")),
            if (onCopyImage != null) ShadContextMenuItem(height: 40, onPressed: () => onCopyImage!(image), child: const Text("Copy")),
          ],
          child: viewer,
        );
      },
    );
  }
}

class _CyclingProgressIndicator extends StatefulWidget {
  const _CyclingProgressIndicator({this.strokeWidth = 2});

  final double strokeWidth;

  @override
  State<_CyclingProgressIndicator> createState() => _CyclingProgressIndicatorState();
}

class _CyclingProgressIndicatorState extends State<_CyclingProgressIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _colorAt(BuildContext context, double t) {
    final colorScheme = ShadTheme.of(context).colorScheme;
    final palette = [colorScheme.primary, colorScheme.foreground, colorScheme.mutedForeground, colorScheme.primary];

    final segmentCount = palette.length - 1;
    final scaled = t * segmentCount;
    final index = scaled.floor().clamp(0, segmentCount - 1);
    final localT = (scaled - index).clamp(0.0, 1.0);
    final eased = Curves.easeInOut.transform(localT);
    return Color.lerp(palette[index], palette[index + 1], eased) ?? colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CircularProgressIndicator(
        strokeWidth: widget.strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(_colorAt(context, _controller.value)),
      ),
    );
  }
}

class _ProcessingStatusText extends StatefulWidget {
  const _ProcessingStatusText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_ProcessingStatusText> createState() => _ProcessingStatusTextState();
}

class _ProcessingStatusTextState extends State<_ProcessingStatusText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Shader _sweepShader(BuildContext context, Rect rect, double t) {
    final colorScheme = ShadTheme.of(context).colorScheme;
    final centerX = -1.4 + (t * 2.8);
    final highlight = colorScheme.background.withAlpha(210);

    return LinearGradient(
      begin: Alignment(centerX - 0.45, 0),
      end: Alignment(centerX + 0.45, 0),
      colors: [Colors.transparent, highlight, Colors.transparent],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(rect);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final text = Text(widget.text, style: widget.style);
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            text,
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) => _sweepShader(context, rect, _controller.value),
              child: Text(widget.text, style: widget.style.copyWith(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}

class ChatThreadProcessingStatusRow extends StatelessWidget {
  const ChatThreadProcessingStatusRow({super.key, required this.text, this.onCancel});

  final String text;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(width: 10),
        if (onCancel != null)
          ShadGestureDetector(
            cursor: SystemMouseCursors.click,
            onTapDown: (_) {
              onCancel!();
            },
            child: ShadTooltip(
              builder: (context) => const Text("Stop"),
              child: SizedBox(
                width: 24,
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Positioned.fill(child: _CyclingProgressIndicator(strokeWidth: 2)),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: ShadTheme.of(context).colorScheme.foreground),
                      child: Icon(LucideIcons.x, color: ShadTheme.of(context).colorScheme.background, size: 12),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          const SizedBox(width: 13, height: 13, child: _CyclingProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Expanded(
          child: _ProcessingStatusText(
            text: text,
            style: TextStyle(fontSize: 13, color: ShadTheme.of(context).colorScheme.mutedForeground),
          ),
        ),
      ],
    );
  }
}

Widget defaultMessageHeaderBuilder(BuildContext context, MeshDocument thread, MeshElement message, {String? localParticipantName}) {
  final name = message.getAttribute("author_name") ?? "";
  final createdAt = message.getAttribute("created_at") == null ? DateTime.now() : DateTime.parse(message.getAttribute("created_at"));
  if (_shouldShowAuthorNames(thread: thread, localParticipantName: localParticipantName)) {
    return Container(
      padding: EdgeInsets.only(left: 8, right: 8),
      width: ((message.getAttribute("text") as String?)?.isEmpty ?? true) ? 250 : double.infinity,
      child: SelectionArea(
        child: Row(
          children: [
            Text(
              name.split("@").first,
              style: ShadTheme.of(context).textTheme.small.copyWith(color: ShadTheme.of(context).colorScheme.foreground),
              overflow: TextOverflow.ellipsis,
            ),
            Spacer(),
            Text(
              timeAgo(createdAt),
              style: ShadTheme.of(context).textTheme.small.copyWith(color: ShadTheme.of(context).colorScheme.mutedForeground),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  } else {
    return SizedBox(height: 0);
  }
}

class ThreadToolkitBuilder {
  ThreadToolkitBuilder({required this.name});

  final String name;
}

class ChatThreadSnapshot {
  ChatThreadSnapshot({
    required this.messages,
    required this.online,
    required this.offline,
    required this.typing,
    required this.listening,
    required this.availableTools,
    required this.agentOnline,
    required this.threadStatus,
    required this.threadStatusMode,
  });

  final bool agentOnline;
  final List<MeshElement> messages;
  final List<Participant> online;
  final List<String> offline;
  final List<String> typing;
  final List<String> listening;
  final List<ThreadToolkitBuilder> availableTools;
  final String? threadStatus;
  final String? threadStatusMode;
}

class ChatThreadBuilder extends StatefulWidget {
  const ChatThreadBuilder({
    super.key,
    required this.path,
    required this.document,
    required this.room,
    required this.controller,
    required this.builder,
    this.agentName,
  });

  final String? agentName;
  final String path;
  final MeshDocument document;
  final RoomClient room;
  final ChatThreadController controller;
  final Widget Function(BuildContext, ChatThreadSnapshot state) builder;

  @override
  State createState() => _ChatThreadBuilder();
}

class _ChatThreadBuilder extends State<ChatThreadBuilder> {
  late StreamSubscription<RoomEvent> sub;

  Set<Participant> onlineParticipants = {};
  Set<String> offlineParticipants = {};
  Map<String, Timer> typing = {};
  Set<String> listening = {};
  List<MeshElement> messages = [];
  String? threadStatus;
  String? threadStatusMode;

  @override
  void initState() {
    super.initState();

    sub = widget.room.listen(_onRoomMessage);
    widget.room.messaging.addListener(_onMessagingChanged);
    widget.document.addListener(_onDocumentChanged);

    _getParticipants();
    _getMessages();
    _getThreadStatus();

    _checkAgent();
  }

  bool agentOnline = false;
  void _checkAgent() {
    final agent = widget.room.messaging.remoteParticipants.firstWhereOrNull((x) => x.getAttribute("name") == widget.agentName);
    final online = agent != null;
    if (online != agentOnline) {
      if (!mounted) {
        return;
      }
      setState(() {
        agentOnline = online;
      });

      if (online) {
        widget.room.messaging.sendMessage(to: agent, type: "opened", message: {"path": widget.path});
        widget.room.messaging.sendMessage(to: agent, type: "get_thread_toolkit_builders", message: {"path": widget.path});
      }
    }
  }

  @override
  void dispose() {
    super.dispose();

    sub.cancel();
    widget.room.messaging.removeListener(_onMessagingChanged);
    widget.document.removeListener(_onDocumentChanged);
  }

  void _onDocumentChanged() {
    if (!mounted) {
      return;
    }

    _getParticipants();
    _getMessages();
    _getThreadStatus();
  }

  void _onMessagingChanged() {
    if (!mounted) {
      return;
    }

    _getParticipants();
    _getThreadStatus();
    _checkAgent();
  }

  void _onRoomMessage(RoomEvent event) {
    if (!mounted) {
      return;
    }

    if (event is RoomMessageEvent) {
      _getThreadStatus();

      if (event.message.type == "set_thread_tool_providers") {
        if (mounted) {
          setState(() {
            availableTools = [for (final json in event.message.message["tool_providers"] as List) ThreadToolkitBuilder(name: json["name"])];
          });
        }
      }

      if (event.message.type.startsWith("participant")) {
        _getParticipants();
        _checkAgent();
      }

      if (event.message.type == "typing" && event.message.message["path"] == widget.path) {
        // TODO: verify thread_id matches
        typing[event.message.fromParticipantId]?.cancel();
        typing[event.message.fromParticipantId] = Timer(Duration(seconds: 1), () {
          typing.remove(event.message.fromParticipantId);
          if (mounted) {
            setState(() {});
          }
        });
        if (mounted) {
          setState(() {});
        }
      } else if (event.message.type == "listening" && event.message.message["path"] == widget.path) {
        if (event.message.message["listening"] == true) {
          listening.add(event.message.fromParticipantId);
        } else {
          listening.remove(event.message.fromParticipantId);
        }

        widget.controller.listening = listening.isNotEmpty;
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  void _getParticipants() {
    final online = widget.controller.getOnlineParticipants(widget.document).toSet();
    if (!setEquals(online, onlineParticipants)) {
      onlineParticipants = online;
      if (!mounted) {
        return;
      }
      setState(() {});
    }

    final offline = widget.controller.getOfflineParticipants(widget.document).toSet();
    if (!setEquals(offline, offlineParticipants)) {
      offlineParticipants = offline;
      if (!mounted) {
        return;
      }
      setState(() {});
    }
  }

  void _getMessages() {
    final threadMessages = widget.document.root.getChildren().whereType<MeshElement>().where((x) => x.tagName == "messages").firstOrNull;
    messages = (threadMessages?.getChildren() ?? []).whereType<MeshElement>().toList();
    setState(() {});
  }

  void _getThreadStatus() {
    final keyCandidates = <String>{"thread.status.${widget.path}"};
    final textKeyCandidates = <String>{"thread.status.text.${widget.path}"};
    final modeKeyCandidates = <String>{"thread.status.mode.${widget.path}"};
    if (widget.path.startsWith("/")) {
      keyCandidates.add("thread.status.${widget.path.substring(1)}");
      textKeyCandidates.add("thread.status.text.${widget.path.substring(1)}");
      modeKeyCandidates.add("thread.status.mode.${widget.path.substring(1)}");
    } else {
      keyCandidates.add("thread.status./${widget.path}");
      textKeyCandidates.add("thread.status.text./${widget.path}");
      modeKeyCandidates.add("thread.status.mode./${widget.path}");
    }

    final candidates = <Participant>[];
    final localParticipant = widget.room.localParticipant;
    if (localParticipant != null) {
      candidates.add(localParticipant);
    }

    if (widget.agentName != null) {
      candidates.addAll(
        widget.room.messaging.remoteParticipants.where((participant) => participant.getAttribute("name") == widget.agentName),
      );
    }

    candidates.addAll(widget.room.messaging.remoteParticipants.where((participant) => participant.role == "agent"));
    candidates.addAll(widget.room.messaging.remoteParticipants);

    String? nextStatus;
    String? nextMode;
    for (final participant in candidates) {
      if (nextStatus == null) {
        for (final key in textKeyCandidates) {
          final value = participant.getAttribute(key);
          if (value is String && value.trim().isNotEmpty) {
            nextStatus = value.trim();
            break;
          }
        }
      }
      if (nextStatus == null) {
        for (final key in keyCandidates) {
          final value = participant.getAttribute(key);
          if (value is String && value.trim().isNotEmpty) {
            nextStatus = value.trim();
            break;
          }
        }
      }

      if (nextMode == null) {
        for (final key in modeKeyCandidates) {
          final value = participant.getAttribute(key);
          if (value is String) {
            final normalized = value.trim().toLowerCase();
            if (normalized == "busy" || normalized == "steerable") {
              nextMode = normalized;
              break;
            }
          }
        }
      }

      if (nextStatus != null && nextMode != null) {
        break;
      }
    }

    if (nextMode == null && nextStatus != null) {
      nextMode = "busy";
    }

    if (nextStatus == threadStatus && nextMode == threadStatusMode) {
      return;
    }

    if (!mounted) {
      threadStatus = nextStatus;
      threadStatusMode = nextMode;
      return;
    }

    setState(() {
      threadStatus = nextStatus;
      threadStatusMode = nextMode;
    });
  }

  List<ThreadToolkitBuilder> availableTools = [];

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      ChatThreadSnapshot(
        messages: messages,
        agentOnline: agentOnline,
        online: onlineParticipants.toList(),
        offline: offlineParticipants.toList(),
        typing: typing.keys.toList(),
        listening: listening.toList(),
        availableTools: availableTools.toList(),
        threadStatus: threadStatus,
        threadStatusMode: threadStatusMode,
      ),
    );
  }
}

class ReasoningTrace extends StatefulWidget {
  const ReasoningTrace({super.key, required this.previous, required this.message, required this.next});

  final MeshElement? previous;
  final MeshElement message;
  final MeshElement? next;

  @override
  State<ReasoningTrace> createState() => _ReasoningTrace();
}

class _ReasoningTrace extends State<ReasoningTrace> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: 0, bottom: 0, right: 50, left: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(right: 16, left: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MarkdownWidget(
                    padding: const EdgeInsets.all(0),
                    config: buildChatBubbleMarkdownConfig(context, threadTypography: true),
                    shrinkWrap: true,
                    selectable: true,

                    /*builders: {
      "code": CodeElementBuilder(
          document: ChatDocumentProvider.of(context).document,
          api: TimuApiProvider.of(context).api,
          layer: layer),
},*/
                    data: widget.message.getAttribute("summary") ?? "",
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ShellLine extends StatefulWidget {
  const ShellLine({super.key, required this.previous, required this.message, required this.next});

  final MeshElement? previous;
  final MeshElement message;
  final MeshElement? next;

  @override
  State<ShellLine> createState() => _ShellLineState();
}

class _ShellLineState extends State<ShellLine> {
  String trim(String l) {
    if (l.length < 1024) {
      return l;
    }
    return "${l.substring(0, 1024)}...";
  }

  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final border = BorderSide(color: ShadTheme.of(context).cardTheme.border!.bottom!.color!);
    return Container(
      margin: EdgeInsets.only(top: 0, bottom: 0, right: 50, left: 5),
      decoration: BoxDecoration(
        color: ShadTheme.of(context).colorScheme.background,
        border: Border(
          left: border,
          right: border,
          top: widget.previous?.tagName != widget.message.tagName ? border : BorderSide.none,
          bottom: border,
        ),
        borderRadius: BorderRadius.only(
          topLeft: widget.previous?.tagName != widget.message.tagName ? Radius.circular(10) : Radius.zero,
          topRight: widget.previous?.tagName != widget.message.tagName ? Radius.circular(10) : Radius.zero,
          bottomRight: widget.next?.tagName == widget.message.tagName ? Radius.zero : Radius.circular(10),
          bottomLeft: widget.next?.tagName == widget.message.tagName ? Radius.zero : Radius.circular(10),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.previous?.tagName != widget.message.tagName)
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: border),
                color: ShadTheme.of(context).colorScheme.secondary,
              ),
              padding: EdgeInsets.only(left: 16, right: 16),
              child: Row(
                children: [
                  Icon(LucideIcons.terminal),
                  SizedBox(width: 10),
                  Expanded(child: Text("Terminal", style: ShadTheme.of(context).textTheme.p)),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.only(right: 16, left: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShadGestureDetector(
                  cursor: SystemMouseCursors.click,
                  onTap: () {
                    setState(() {
                      expanded = !expanded;
                    });
                  },
                  child: Padding(padding: EdgeInsets.all(3), child: Icon(expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight)),
                ),

                Expanded(
                  child: SelectableText.rich(
                    maxLines: expanded ? null : 1,
                    TextSpan(
                      children: [
                        TextSpan(text: widget.message.getAttribute("command"), style: GoogleFonts.sourceCodePro()),
                        if (expanded) ...[
                          TextSpan(text: "\n"),
                          if (widget.message.getAttribute("result") != null) ...[
                            TextSpan(text: "\n"),
                            TextSpan(text: trim(widget.message.getAttribute("result")), style: GoogleFonts.sourceCodePro()),
                          ],
                          if (widget.message.getAttribute("stdout") != null) ...[
                            TextSpan(text: "\n"),
                            TextSpan(text: trim(widget.message.getAttribute("stdout")), style: GoogleFonts.sourceCodePro()),
                          ],
                          if (widget.message.getAttribute("stderr") != null) ...[
                            TextSpan(text: "\n"),
                            TextSpan(
                              text: trim(widget.message.getAttribute("stderr")),
                              style: GoogleFonts.sourceCodePro(color: Colors.red),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EventLine extends StatefulWidget {
  const EventLine({
    super.key,
    required this.previous,
    required this.message,
    required this.next,
    required this.room,
    required this.path,
    this.agentName,
  });

  final MeshElement? previous;
  final MeshElement message;
  final MeshElement? next;
  final RoomClient room;
  final String path;
  final String? agentName;

  @override
  State<EventLine> createState() => _EventLineState();
}

class _EventLineState extends State<EventLine> {
  bool sendingApprovalDecision = false;

  String _humanize(String value) {
    if (value.trim().isEmpty) {
      return "";
    }

    final normalized = value.replaceAll(RegExp(r"[._-]+"), " ").trim();
    final parts = normalized.split(RegExp(r"\s+"));
    return parts.where((part) => part.isNotEmpty).map((part) => "${part[0].toUpperCase()}${part.substring(1)}").join(" ");
  }

  String _defaultHeadline({required String kind, required String state, required String eventName}) {
    if (kind == "plan") {
      return state == "completed" ? "Plan Ready" : "Planning";
    }
    if (kind == "diff") {
      return state == "completed" ? "Diff Ready" : "Preparing Diff";
    }
    if (kind == "exec") {
      return state == "completed" ? "Command Complete" : "Running Command";
    }
    if (kind == "message") {
      return state == "completed" ? "Response Ready" : "Composing Response";
    }
    if (kind == "turn") {
      return state == "completed" ? "Turn Complete" : "Thinking";
    }

    if (eventName.trim().isNotEmpty) {
      final tail = eventName.split(".").last;
      return _humanize(tail);
    }

    return "";
  }

  bool _useSummaryAsHeadline({required String summary, required String method, required String eventName}) {
    if (summary.trim().isEmpty) {
      return false;
    }

    final lower = summary.toLowerCase();
    if (lower == method.toLowerCase()) {
      return false;
    }
    if (lower == eventName.toLowerCase()) {
      return false;
    }
    if (method.trim().isNotEmpty && lower.startsWith(method.toLowerCase())) {
      return false;
    }
    return true;
  }

  List<String> _detailLines(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return const [];
    }

    if (value.startsWith("[") && value.endsWith("]")) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.whereType<String>().map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
        }
      } catch (_) {}
    }

    return value.split(RegExp(r"\r?\n")).map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
  }

  String _displayText({required String headline}) {
    return headline;
  }

  String? _languageFromDiffHeaderPath(String value) {
    final path = value.trim();
    if (path.isEmpty || path == "/dev/null") {
      return null;
    }

    final normalized = path.startsWith("a/") || path.startsWith("b/") ? path.substring(2) : path;
    return resolveLanguageIdForFilename(normalized);
  }

  String? _singleDiffPathFromHeadline(String headline) {
    final trimmed = headline.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final withPath = trimmed.replaceFirst(RegExp(r"^(edited|added|deleted)\s+", caseSensitive: false), "");
    if (withPath == trimmed) {
      return null;
    }

    if (RegExp(r"^\d+\s+files?\b", caseSensitive: false).hasMatch(withPath)) {
      return null;
    }

    final withoutCounts = withPath.replaceFirst(RegExp(r"\s+\(\+\d+\s+-\d+\)\s*$"), "").trim();
    if (withoutCounts.isEmpty) {
      return null;
    }

    final moveParts = withoutCounts.split(RegExp(r"\s*(?:→|->)\s*"));
    final candidate = moveParts.isNotEmpty ? moveParts.last.trim() : withoutCounts;
    return candidate.isEmpty ? withoutCounts : candidate;
  }

  String? _languageFromDiffHeadline(String headline) {
    final path = _singleDiffPathFromHeadline(headline);
    if (path == null || path.isEmpty) {
      return null;
    }
    return _languageFromDiffHeaderPath(path);
  }

  TextSpan _diffLineSpan({required BuildContext context, required String line, required String? languageId, required TextStyle textStyle}) {
    if (line.isEmpty) {
      return TextSpan(text: "", style: textStyle);
    }

    if (languageId == null) {
      return highlightCodeSpanWithReHighlight(
        context: context,
        code: line,
        languageOrFilename: "diff",
        textStyle: textStyle,
        theme: monokaiSublimeTheme,
        fallbackLanguageId: "diff",
      );
    }

    if (line.startsWith("+") || line.startsWith("-") || line.startsWith(" ")) {
      final marker = line.substring(0, 1);
      final rest = line.length > 1 ? line.substring(1) : "";
      return TextSpan(
        style: textStyle,
        children: [
          TextSpan(text: marker, style: textStyle),
          highlightCodeSpanWithReHighlight(
            context: context,
            code: rest,
            languageOrFilename: languageId,
            textStyle: textStyle,
            theme: monokaiSublimeTheme,
          ),
        ],
      );
    }

    return highlightCodeSpanWithReHighlight(
      context: context,
      code: line,
      languageOrFilename: languageId,
      textStyle: textStyle,
      theme: monokaiSublimeTheme,
    );
  }

  List<Map<String, dynamic>> _parseUnifiedDiff(String diff, {String? defaultLanguageId}) {
    final results = <Map<String, dynamic>>[];
    int? oldLine;
    int? newLine;
    String? currentLanguageId = defaultLanguageId;
    final hunk = RegExp(r"^@@\s*-(\d+)(?:,\d+)?\s+\+(\d+)(?:,\d+)?\s*@@");

    for (final line in diff.split(RegExp(r"\r?\n"))) {
      if (line.isEmpty) {
        continue;
      }

      if (line.startsWith("--- ")) {
        final language = _languageFromDiffHeaderPath(line.substring(4));
        if (language != null) {
          currentLanguageId = language;
        }
        continue;
      }

      if (line.startsWith("+++ ")) {
        final language = _languageFromDiffHeaderPath(line.substring(4));
        if (language != null) {
          currentLanguageId = language;
        }
        continue;
      }

      final hunkMatch = hunk.firstMatch(line);
      if (hunkMatch != null) {
        oldLine = int.tryParse(hunkMatch.group(1) ?? "");
        newLine = int.tryParse(hunkMatch.group(2) ?? "");
        continue;
      }

      if (line.startsWith(r"\ No newline at end of file")) {
        continue;
      }

      if (oldLine == null || newLine == null) {
        continue;
      }

      if (line.startsWith("+")) {
        results.add({"old": null, "new": newLine, "text": line, "language": currentLanguageId});
        newLine += 1;
        continue;
      }

      if (line.startsWith("-")) {
        results.add({"old": oldLine, "new": null, "text": line, "language": currentLanguageId});
        oldLine += 1;
        continue;
      }

      if (line.startsWith(" ")) {
        results.add({"old": oldLine, "new": newLine, "text": line, "language": currentLanguageId});
        oldLine += 1;
        newLine += 1;
        continue;
      }
    }

    return results;
  }

  List<Map<String, dynamic>> _extractDiffLinesFromRaw({required String raw, required String headline}) {
    if (raw.trim().isEmpty) {
      return const [];
    }

    final headlineLanguageId = _languageFromDiffHeadline(headline);

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const [];
      }

      final itemCandidates = <dynamic>[decoded["item"], (decoded["msg"] is Map) ? (decoded["msg"] as Map)["item"] : null, decoded];

      final results = <Map<String, dynamic>>[];
      for (final candidate in itemCandidates) {
        if (candidate is! Map) {
          continue;
        }
        final changes = candidate["changes"];
        if (changes is! List) {
          continue;
        }

        for (final change in changes) {
          if (change is! Map) {
            continue;
          }
          final diff = change["diff"];
          if (diff is! String || diff.trim().isEmpty) {
            continue;
          }

          String? languageId;
          final changePath = change["path"];
          if (changePath is String) {
            languageId = _languageFromDiffHeaderPath(changePath);
          }
          final rawKind = change["kind"];
          if (languageId == null && rawKind is Map) {
            final movePath = rawKind["movePath"] ?? rawKind["move_path"];
            if (movePath is String) {
              languageId = _languageFromDiffHeaderPath(movePath);
            }
          }
          languageId ??= headlineLanguageId;

          results.addAll(_parseUnifiedDiff(diff, defaultLanguageId: languageId));
        }

        if (results.isNotEmpty) {
          return results;
        }
      }
    } catch (_) {}

    return const [];
  }

  Future<void> _sendApprovalDecision({required String approvalId, required bool approve}) async {
    if (sendingApprovalDecision) {
      return;
    }

    final candidates = <RemoteParticipant>[];
    if (widget.agentName != null) {
      candidates.addAll(
        widget.room.messaging.remoteParticipants.where((participant) => participant.getAttribute("name") == widget.agentName),
      );
    }
    candidates.addAll(widget.room.messaging.remoteParticipants.where((participant) => participant.role == "agent"));

    final recipients = candidates.toSet().toList();
    if (recipients.isEmpty) {
      return;
    }

    setState(() {
      sendingApprovalDecision = true;
    });

    try {
      await Future.wait([
        for (final participant in recipients)
          widget.room.messaging.sendMessage(
            to: participant,
            type: approve ? "approved" : "rejected",
            message: {"path": widget.path, "approval_id": approvalId},
          ),
      ]);
    } finally {
      if (mounted) {
        setState(() {
          sendingApprovalDecision = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const supportedKinds = {"exec", "tool", "web", "search", "diff", "image", "approval", "collab", "plan"};

    final method = (widget.message.getAttribute("method") as String?) ?? "agent/event";
    final eventName =
        (widget.message.getAttribute("name") as String?) ??
        (widget.message.getAttribute("event_type") as String?) ??
        method.replaceAll("/", ".");
    final kind = ((widget.message.getAttribute("kind") as String?) ?? "").trim().toLowerCase();
    if (!supportedKinds.contains(kind)) {
      return SizedBox.shrink();
    }
    final state = ((widget.message.getAttribute("state") as String?) ?? "info").toLowerCase();
    final inProgress = state == "in_progress" || state == "running" || state == "queued";
    final summary = ((widget.message.getAttribute("summary") as String?) ?? method).trim();
    final headlineAttr = ((widget.message.getAttribute("headline") as String?) ?? "").trim();
    final detailsAttr = ((widget.message.getAttribute("details") as String?) ?? "").trim();
    final approvalId =
        (((widget.message.getAttribute("item_id") as String?) ?? (widget.message.getAttribute("approval_id") as String?) ?? "")).trim();
    final raw = ((widget.message.getAttribute("data") as String?) ?? "").trim();
    final useSummaryAsHeadline = _useSummaryAsHeadline(summary: summary, method: method, eventName: eventName);
    var headline = headlineAttr.isNotEmpty
        ? headlineAttr
        : (useSummaryAsHeadline ? summary : _defaultHeadline(kind: kind, state: state, eventName: eventName));
    if (headline.trim().isEmpty) {
      return SizedBox.shrink();
    }
    final details = _detailLines(detailsAttr);
    var detailLines = details;
    if (kind == "web" && details.isNotEmpty) {
      headline = details.first;
      detailLines = details.skip(1).toList();
    } else if (kind == "exec") {
      detailLines = details.toList();
    }
    final diffLines = kind == "diff" ? _extractDiffLinesFromRaw(raw: raw, headline: headline) : const <Map<String, dynamic>>[];
    final displayText = _displayText(headline: headline);
    final canApprove = kind == "approval" && inProgress && approvalId.isNotEmpty;

    Color textColor;
    if (state == "failed") {
      textColor = ShadTheme.of(context).colorScheme.destructive;
    } else if (state == "cancelled") {
      textColor = ShadTheme.of(context).colorScheme.mutedForeground;
    } else if (state == "completed") {
      textColor = ShadTheme.of(context).colorScheme.foreground;
    } else if (inProgress) {
      textColor = ShadTheme.of(context).colorScheme.primary;
    } else {
      textColor = ShadTheme.of(context).colorScheme.foreground;
    }

    return Container(
      margin: EdgeInsets.only(top: 0, bottom: 0, right: 50, left: 5),
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectionArea(
                    child: Text(
                      displayText,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor, height: 1.3),
                    ),
                  ),
                ),
              ],
            ),
            if (diffLines.isNotEmpty)
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(top: 0),
                child: Padding(
                  padding: EdgeInsets.only(left: 14),
                  child: Column(
                    children: [
                      for (final line in diffLines.indexed)
                        Builder(
                          builder: (context) {
                            final lineText = (line.$2["text"] as String?) ?? "";
                            final languageId = line.$2["language"];
                            final lineBackground = diffLineBackgroundColor(lineText);
                            final numberColor = lineBackground != null
                                ? const Color(0xFFE5E7EB).withAlpha(220)
                                : ShadTheme.of(context).colorScheme.mutedForeground;
                            final lineStyle = GoogleFonts.sourceCodePro(
                              fontSize: 12,
                              color: lineBackground != null ? const Color(0xFFE5E7EB) : textColor.withAlpha(220),
                              height: 1.3,
                            );

                            return Padding(
                              padding: EdgeInsets.only(bottom: line.$1 < diffLines.length - 1 ? 2 : 0),
                              child: Container(
                                decoration: BoxDecoration(color: lineBackground, borderRadius: BorderRadius.circular(4)),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 42,
                                      child: Text(
                                        line.$2["old"] is int ? "${line.$2["old"]}" : "",
                                        textAlign: TextAlign.right,
                                        style: GoogleFonts.sourceCodePro(fontSize: 11, color: numberColor),
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    SizedBox(
                                      width: 42,
                                      child: Text(
                                        line.$2["new"] is int ? "${line.$2["new"]}" : "",
                                        textAlign: TextAlign.right,
                                        style: GoogleFonts.sourceCodePro(fontSize: 11, color: numberColor),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: SelectableText.rich(
                                        _diffLineSpan(
                                          context: context,
                                          line: lineText,
                                          languageId: languageId is String ? languageId : null,
                                          textStyle: lineStyle,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            if (detailLines.isNotEmpty && kind != "diff")
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(top: 0),
                child: SelectionArea(
                  child: Text(detailLines.join("\n"), style: TextStyle(color: textColor.withAlpha(220), height: 1.3)),
                ),
              ),
            if (canApprove)
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(top: 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShadButton(
                      enabled: !sendingApprovalDecision,
                      onPressed: () {
                        _sendApprovalDecision(approvalId: approvalId, approve: true);
                      },
                      child: Text("Approve"),
                    ),
                    ShadButton.outline(
                      enabled: !sendingApprovalDecision,
                      onPressed: () {
                        _sendApprovalDecision(approvalId: approvalId, approve: false);
                      },
                      child: Text("Reject"),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatThreadPreview extends StatelessWidget {
  const ChatThreadPreview({super.key, required this.room, required this.path});

  final RoomClient room;
  final String path;

  @override
  Widget build(BuildContext context) {
    final ext = path.split(".").last.toLowerCase();

    if (imageExtensions.contains(ext)) {
      const previewEdge = 312.5;
      return FutureBuilder(
        future: room.storage.downloadUrl(path),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return SizedBox(
              width: previewEdge,
              height: previewEdge,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ImagePreview(key: ValueKey(path), url: Uri.parse(snapshot.data!), fit: BoxFit.cover),
              ),
            );
          }

          return SizedBox(
            width: previewEdge,
            height: previewEdge,
            child: ColoredBox(color: ShadTheme.of(context).colorScheme.background),
          );
        },
      );
    }

    return FileDefaultPreviewCard(
      icon: LucideIcons.file,
      text: path.split("/").last,
      onDownload: () async {
        final url = await room.storage.downloadUrl(path);

        launchUrl(Uri.parse(url));
      },
    );
  }
}

typedef FileDropCallback = Future<void> Function(String name, Stream<Uint8List> dataStream, int? fileSize);
typedef TextPasteCallback = Future<void> Function(String text);

class FileDropArea extends StatefulWidget {
  final FileDropCallback onFileDrop;

  final Widget child;

  const FileDropArea({super.key, required this.onFileDrop, required this.child});

  @override
  FileDropAreaState createState() => FileDropAreaState();
}

const _preferredFormats = [
  Formats.mp4,
  Formats.mov,
  Formats.mkv,
  Formats.pdf,
  webPDFFormat,
  Formats.png,
  Formats.jpeg,
  Formats.heic,
  Formats.tiff,
  Formats.webp,
];

class FileDropAreaState extends State<FileDropArea> {
  bool _dragging = false;

  Future<DataReaderFile> _getFile(DataReader reader, SimpleFileFormat? format) {
    final completer = Completer<DataReaderFile>();

    reader.getFile(format, completer.complete, onError: completer.completeError);

    return completer.future;
  }

  Future<T> _getValue<T extends Object>(DataReader reader, ValueFormat<T> format) {
    final completer = Completer<T>();

    reader.getValue(format, completer.complete, onError: completer.completeError);

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: const [...Formats.standardFormats, Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDragOver,
      onDropLeave: _onDragLeave,
      onPerformDrop: _onDrop,
      child: Stack(
        children: [
          widget.child,
          if (_dragging) Positioned.fill(child: Container(color: Colors.blue.withValues(alpha: 0.1))),
        ],
      ),
    );
  }

  DropOperation _onDragOver(DropOverEvent event) {
    setState(() => _dragging = true);

    return event.session.allowedOperations.contains(DropOperation.copy) ? DropOperation.copy : DropOperation.none;
  }

  void _onDragLeave(DropEvent event) {
    setState(() => _dragging = false);
  }

  Future<void> _onDrop(PerformDropEvent event) async {
    setState(() => _dragging = false);

    final readers = event.session.items.map((m) => m.dataReader).toList();

    for (final reader in readers) {
      if (reader == null) continue;

      try {
        FolderDropPayload? folderPayload;
        if (reader.canProvide(Formats.fileUri)) {
          try {
            final namedUri = await _getValue(reader, Formats.fileUri);

            folderPayload = await resolveFolderDrop(namedUri);
          } catch (err, st) {
            debugPrint('Error reading dropped folder uri: $err\n$st');
          }
        }

        if (kIsWeb && folderPayload == null) {
          try {
            final rawItem = reader.rawReader;

            if (rawItem != null) {
              final result = rawItem.getDataForFormat('web:entry');
              final entryData = await result.$1;
              if (entryData != null) {
                folderPayload = await resolveFolderDropFromEntry(entryData);
              }
            }
          } catch (err, st) {
            debugPrint('Error reading dropped folder entry on web: $err\n$st');
          }
        }

        if (folderPayload != null) {
          for (final file in folderPayload.files) {
            final relativePath = file.relativePath.replaceAll('\\', '/');
            final uploadPath = relativePath.isEmpty ? folderPayload.folderName : '${folderPayload.folderName}/$relativePath';

            await widget.onFileDrop(uploadPath, file.dataStream, file.fileSize);
          }
          continue;
        }

        final name = (await reader.getSuggestedName())!;
        final fmt = _preferredFormats.firstWhereOrNull(reader.canProvide);
        final file = await _getFile(reader, fmt);

        await widget.onFileDrop(name, file.getStream(), file.fileSize);
      } catch (err, st) {
        debugPrint('Error dropping file: $err\n$st');
      }
    }
  }
}

class PhotoNamer {
  /// Example:
  /// IMG_20251211_173812.JPG
  /// IMG_20251211_173812_1.JPG
  /// IMG_20251211_173812_2.MOV
  static List<String> generateBatchNames(List<XFile> files) {
    if (files.isEmpty) return const [];

    final base = _base();
    final result = <String>[];

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final ext = _ext(file.name);

      final candidate = i == 0 ? '$base.$ext' : '${base}_$i.$ext';
      result.add(candidate);
    }

    return result;
  }

  static String _base() {
    final dt = DateTime.now();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return 'IMG_$y$m${d}_$hh$mm$ss';
  }

  static String _ext(String originalName) {
    final dotIndex = originalName.lastIndexOf('.');
    final rawExt = dotIndex == -1 ? '' : originalName.substring(dotIndex + 1).toUpperCase();

    if (rawExt.isEmpty) return 'JPG';

    return rawExt;
  }
}
