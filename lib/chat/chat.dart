import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/storage/file_browser.dart';
import 'package:meshagent_flutter_shadcn/ui/ui.dart';
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

import 'jumping_dots.dart';
import 'outbound_delivery_status.dart';

const webPDFFormat = SimpleFileFormat(uniformTypeIdentifiers: ['com.adobe.pdf'], mimeTypes: ['web application/pdf']);

enum UploadStatus { initial, uploading, completed, failed }

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
  bool _thinking = false;

  bool get thinking {
    return _thinking;
  }

  set thinking(bool value) {
    if (value != _thinking) {
      _thinking = value;
      notifyListeners();
    }
  }

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

  Future<void> sendMessageToParticipant({required Participant participant, required String path, required ChatMessage message}) async {
    if (message.text.trim().isNotEmpty || message.attachments.isNotEmpty) {
      final tools = [for (final tk in toolkits) (await tk.build(room)).toJson()];
      await room.messaging.sendMessage(
        to: participant,
        type: "chat",
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
    void Function(ChatMessage)? onMessageSent,
  }) async {
    if (message.text.trim().isNotEmpty || message.attachments.isNotEmpty) {
      insertMessage(thread: thread, message: message);

      final List<Future<void>> sentMessages = [];
      if (notifyOnSend) {
        for (final participant in getOnlineParticipants(thread)) {
          sentMessages.add(sendMessageToParticipant(participant: participant, path: path, message: message));
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
        if (!widget.controller.thinking) {
          widget.onSend(widget.controller.text, widget.controller.attachmentUploads);

          widget.controller.textFieldController.clear();
        }

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
                      if (trailer != null) trailer,
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

  void _onCopy() {
    SystemClipboard.instance!.write([
      DataWriterItem(suggestedName: "meshwidget.widget")..add(
        EncodedData([
          raw.DataRepresentation.simple(
            format: "text/html",
            data: md.markdownToHtml(widget.text, extensionSet: md.ExtensionSet.gitHubFlavored, inlineSyntaxes: [], blockSyntaxes: []),
          ),
          raw.DataRepresentation.simple(format: "text/plain", data: widget.text),
        ]),
      ),
    ]);
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
    final tt = theme.textTheme;
    final mdColor = tt.p.color ?? DefaultTextStyle.of(context).style.color ?? cs.foreground;
    final baseFontSize = MediaQuery.of(context).textScaler.scale((DefaultTextStyle.of(context).style.fontSize ?? 14));
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
                constraints: const BoxConstraints(minWidth: 150),
                items: [
                  ShadContextMenuItem(onPressed: _onCopy, child: Text('Copy')),
                  if (widget.room != null)
                    ShadContextMenuItem(
                      onPressed: () {
                        _onSave(widget.room!);
                      },
                      child: Text('Save as...'),
                    ),

                  if (mine && widget.onDelete != null) ShadContextMenuItem(onPressed: _onDelete, child: Text('Delete')),
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
      child: Container(
        padding: EdgeInsets.all(5),
        color: Colors.transparent,
        child: Container(
          margin: EdgeInsets.only(top: 8),
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
                      config: MarkdownConfig(
                        configs: [
                          HrConfig(color: mdColor),
                          H1Config(
                            style: TextStyle(fontSize: baseFontSize * 2, color: mdColor, fontWeight: FontWeight.bold),
                          ),
                          H2Config(
                            style: TextStyle(fontSize: baseFontSize * 1.8, color: mdColor, inherit: false),
                          ),
                          H3Config(
                            style: TextStyle(fontSize: baseFontSize * 1.6, color: mdColor, inherit: false),
                          ),
                          H4Config(
                            style: TextStyle(fontSize: baseFontSize * 1.4, color: mdColor, inherit: false),
                          ),
                          H5Config(
                            style: TextStyle(fontSize: baseFontSize * 1.2, color: mdColor, inherit: false),
                          ),
                          H6Config(
                            style: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false),
                          ),
                          PreConfig(
                            decoration: BoxDecoration(color: theme.cardTheme.backgroundColor),
                            textStyle: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false),
                          ),
                          PConfig(
                            textStyle: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false),
                          ),
                          CodeConfig(
                            style: GoogleFonts.sourceCodePro(fontSize: baseFontSize * 1.0, color: mdColor),
                          ),
                          BlockquoteConfig(textColor: mdColor),
                          LinkConfig(
                            style: TextStyle(color: theme.linkButtonTheme.foregroundColor, decoration: TextDecoration.underline),
                          ),
                          ListConfig(
                            marker: (isOrdered, depth, index) {
                              return Padding(
                                padding: EdgeInsets.only(right: 5),
                                child: Text("${index + 1}.", textAlign: TextAlign.right),
                              );
                            },
                          ),
                        ],
                      ),
                      shrinkWrap: true,
                      selectable: true,

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
                startChatCentered: widget.startChatCentered,
                messages: state.messages,
                online: state.online,
                showTyping: (state.typing.isNotEmpty || state.thinking.isNotEmpty) && state.listening.isEmpty,
                showListening: state.listening.isNotEmpty,
                messageHeaderBuilder: widget.messageHeaderBuilder,
                fileInThreadBuilder: widget.fileInThreadBuilder,
                currentStatusEntry: _currentStatusEntry,
              ),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 912),
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
                        trailing: state.thinking.isNotEmpty
                            ? ShadGestureDetector(
                                cursor: SystemMouseCursors.click,
                                onTapDown: (_) {
                                  controller.cancel(widget.path, widget.document);
                                },
                                child: ShadTooltip(
                                  builder: (context) => Text("Stop"),
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: ShadTheme.of(context).colorScheme.foreground),
                                    child: Icon(LucideIcons.x, color: ShadTheme.of(context).colorScheme.background),
                                  ),
                                ),
                              )
                            : null,
                        room: widget.room,
                        onSend: (value, attachments) {
                          controller.send(
                            thread: widget.document,
                            path: widget.path,
                            message: ChatMessage(id: const Uuid().v4(), text: value, attachments: attachments.map((x) => x.path).toList()),
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

class ChatThreadMessages extends StatelessWidget {
  const ChatThreadMessages({
    super.key,
    required this.room,
    required this.messages,
    required this.online,

    this.startChatCentered = false,
    this.showTyping = false,
    this.showListening = false,
    this.messageHeaderBuilder,
    this.fileInThreadBuilder,
    this.currentStatusEntry,
    this.messageBuilders,
  });

  final Map<String, MessageBuilder>? messageBuilders;

  final RoomClient room;
  final bool startChatCentered;
  final bool showTyping;
  final bool showListening;
  final List<MeshElement> messages;
  final List<Participant> online;
  final OutboundEntry? currentStatusEntry;

  final Widget Function(BuildContext, MeshDocument, MeshElement)? messageHeaderBuilder;
  final Widget Function(BuildContext context, String path)? fileInThreadBuilder;

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

  Widget _buildMessage(BuildContext context, MeshElement? previous, MeshElement message, MeshElement? next) {
    final isSameAuthor = message.getAttribute("author_name") == previous?.getAttribute("author_name");
    final mine = message.getAttribute("author_name") == room.localParticipant!.getAttribute("name");

    final text = message.getAttribute("text");
    final id = message.getAttribute("id");

    if (messageBuilders?[message.tagName] != null) {
      return messageBuilders![message.tagName]!(room: room, previous: previous, message: message, next: next);
    }

    if (message.tagName == "reasoning") {
      return ReasoningTrace(previous: previous, message: message, next: next);
    }
    if (message.tagName == "exec") {
      return ShellLine(previous: previous, message: message, next: next);
    }

    return SizedBox(
      key: ValueKey(id),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSameAuthor)
            Container(
              margin: EdgeInsets.only(top: 8, right: mine ? 0 : 50, left: mine ? 50 : 0),
              child: Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: (messageHeaderBuilder ?? defaultMessageHeaderBuilder)(context, message.doc as MeshDocument, message),
              ),
            ),

          if (text is String && text.isNotEmpty)
            ChatBubble(room: room, mine: mine, text: message.getAttribute("text"), onDelete: message.delete),

          for (final attachment in message.getChildren())
            Container(
              margin: EdgeInsets.only(top: 8),
              child: Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: _buildFileInThread(context, (attachment as MeshElement).getAttribute("path")),
              ),
            ),

          if (currentStatusEntry != null && currentStatusEntry?.messageId == id)
            Padding(
              padding: EdgeInsets.only(top: 5),
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

    final messageWidgets = <Widget>[];
    for (var message in messages.indexed) {
      final previous = message.$1 > 0 ? messages[message.$1 - 1] : null;
      final next = message.$1 < messages.length - 1 ? messages[message.$1 + 1] : null;

      messageWidgets.insert(0, Container(key: ValueKey(message.$2.id), child: _buildMessage(context, previous, message.$2, next)));
    }
    return Expanded(
      child: Center(
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
                        padding: EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: constraints.maxWidth > 912 ? (constraints.maxWidth - 912) / 2 : 16,
                        ),
                        children: messageWidgets,
                      ),
                    ),
                  ),

                  if (!bottomAlign)
                    if (online.firstOrNull != null)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 20, horizontal: 50),
                        child: Text(
                          online.first.getAttribute("empty_state_title") ?? "How can I help you?",
                          style: ShadTheme.of(context).textTheme.h3,
                        ),
                      ),
                  if (showTyping) SizedBox(height: 20),
                ],
              ),
            ),
            if (showTyping)
              Positioned(
                left: 0,
                bottom: 0,
                right: 0,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 912),
                    child: Container(
                      width: double.infinity,
                      height: 15,
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 100,
                        child: JumpingDots(
                          color: ShadTheme.of(context).colorScheme.foreground,
                          radius: 8,
                          verticalOffset: -15,
                          numberOfDots: 3,
                          animationDuration: const Duration(milliseconds: 200),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (showListening)
              Positioned(
                left: 0,
                bottom: 0,
                right: 0,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 912),
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
        ),
      ),
    );
  }
}

Widget defaultMessageHeaderBuilder(BuildContext context, MeshDocument thread, MeshElement message) {
  final name = message.getAttribute("author_name") ?? "";
  final createdAt = message.getAttribute("created_at") == null ? DateTime.now() : DateTime.parse(message.getAttribute("created_at"));
  final members = thread.root.getElementsByTagName("members").firstOrNull?.getElementsByTagName("member") ?? [];
  if (members.length > 2) {
    return Container(
      padding: EdgeInsets.only(top: 16, left: 8, right: 8),
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
    required this.thinking,
    required this.listening,
    required this.availableTools,
    required this.agentOnline,
  });

  final bool agentOnline;
  final List<MeshElement> messages;
  final List<Participant> online;
  final List<String> offline;
  final List<String> typing;
  final List<String> thinking;
  final List<String> listening;
  final List<ThreadToolkitBuilder> availableTools;
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
  Set<String> thinking = {};
  Set<String> listening = {};
  List<MeshElement> messages = [];

  @override
  void initState() {
    super.initState();

    sub = widget.room.listen(_onRoomMessage);
    widget.document.addListener(_onDocumentChanged);

    _getParticipants();
    _getMessages();

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
    widget.document.removeListener(_onDocumentChanged);
  }

  void _onDocumentChanged() {
    if (!mounted) {
      return;
    }

    _getParticipants();
    _getMessages();
  }

  void _onRoomMessage(RoomEvent event) {
    if (!mounted) {
      return;
    }

    if (event is RoomMessageEvent) {
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
      } else if (event.message.type == "thinking" && event.message.message["path"] == widget.path) {
        if (event.message.message["thinking"] == true) {
          thinking.add(event.message.fromParticipantId);
        } else {
          thinking.remove(event.message.fromParticipantId);
        }

        widget.controller.thinking = thinking.isNotEmpty;
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
        thinking: thinking.toList(),
        listening: listening.toList(),
        availableTools: availableTools.toList(),
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
    final mdColor =
        (ShadTheme.of(context).textTheme.p.color ??
                DefaultTextStyle.of(context).style.color ??
                ShadTheme.of(context).colorScheme.foreground)
            .withAlpha(180);
    final baseFontSize = MediaQuery.of(context).textScaler.scale((DefaultTextStyle.of(context).style.fontSize ?? 14));

    final border = BorderSide(color: ShadTheme.of(context).cardTheme.border!.bottom!.color!);
    return Container(
      margin: EdgeInsets.only(
        top: widget.previous?.tagName != widget.message.tagName ? 16 : 0,
        bottom: widget.next?.tagName != widget.message.tagName ? 8 : 0,
        right: 50,
      ),
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
          Padding(
            padding: EdgeInsets.only(top: 16, bottom: 16, right: 16, left: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MarkdownWidget(
                    padding: const EdgeInsets.all(0),
                    config: MarkdownConfig(
                      configs: [
                        HrConfig(color: mdColor),
                        H1Config(
                          style: TextStyle(fontSize: baseFontSize * 2, color: mdColor, fontWeight: FontWeight.bold),
                        ),
                        H2Config(
                          style: TextStyle(fontSize: baseFontSize * 1.8, color: mdColor, inherit: false),
                        ),
                        H3Config(
                          style: TextStyle(fontSize: baseFontSize * 1.6, color: mdColor, inherit: false),
                        ),
                        H4Config(
                          style: TextStyle(fontSize: baseFontSize * 1.4, color: mdColor, inherit: false),
                        ),
                        H5Config(
                          style: TextStyle(fontSize: baseFontSize * 1.2, color: mdColor, inherit: false),
                        ),
                        H6Config(
                          style: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false),
                        ),
                        PreConfig(
                          decoration: BoxDecoration(color: ShadTheme.of(context).cardTheme.backgroundColor),
                          textStyle: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false),
                        ),
                        PConfig(
                          textStyle: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false),
                        ),
                        CodeConfig(
                          style: GoogleFonts.sourceCodePro(fontSize: baseFontSize * 1.0, color: mdColor),
                        ),
                        BlockquoteConfig(textColor: mdColor),
                        LinkConfig(
                          style: TextStyle(
                            color: ShadTheme.of(context).linkButtonTheme.foregroundColor,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        ListConfig(
                          marker: (isOrdered, depth, index) {
                            return Padding(
                              padding: EdgeInsets.only(right: 5),
                              child: Text("${index + 1}.", textAlign: TextAlign.right),
                            );
                          },
                        ),
                      ],
                    ),
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
      margin: EdgeInsets.only(
        top: widget.previous?.tagName != widget.message.tagName ? 16 : 0,
        bottom: widget.next?.tagName != widget.message.tagName ? 8 : 0,
        right: 50,
      ),
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
              padding: EdgeInsets.only(top: 14, bottom: 14, left: 16, right: 16),
              child: Row(
                children: [
                  Icon(LucideIcons.terminal),
                  SizedBox(width: 10),
                  Expanded(child: Text("Terminal", style: ShadTheme.of(context).textTheme.p)),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: 16, bottom: 16, right: 16, left: 8),
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

class ChatThreadPreview extends StatelessWidget {
  const ChatThreadPreview({super.key, required this.room, required this.path});

  final RoomClient room;
  final String path;

  @override
  Widget build(BuildContext context) {
    final ext = path.split(".").last.toLowerCase();

    if (imageExtensions.contains(ext)) {
      return FutureBuilder(
        future: room.storage.downloadUrl(path),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return SizedBox(
              width: 250,
              height: 250,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ImagePreview(key: ValueKey(path), url: Uri.parse(snapshot.data!), fit: BoxFit.cover),
              ),
            );
          }

          return SizedBox(width: 250, height: 250, child: ColoredBox(color: ShadTheme.of(context).colorScheme.background));
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
