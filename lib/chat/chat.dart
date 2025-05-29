import 'dart:async';

import 'package:collection/collection.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';
import "package:url_launcher/url_launcher.dart";
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'package:meshagent/document.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter/meshagent_flutter.dart';
import 'package:meshagent_flutter_shadcn/chat/jumping_dots.dart';
import 'package:meshagent_flutter_shadcn/meetings/meetings.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';
import 'package:meshagent_flutter_shadcn/file_preview/image.dart';

import 'package:livekit_client/livekit_client.dart' as livekit;

const webPDFFormat = SimpleFileFormat(uniformTypeIdentifiers: ['com.adobe.pdf'], mimeTypes: ['web application/pdf']);

abstract class FileUpload extends ChangeNotifier {
  FileUpload({required this.path});

  final String path;

  int get bytesUploaded;

  Future get done;

  String get filename {
    return path.split("/").last;
  }
}

class MeshagentFileUpload extends FileUpload {
  MeshagentFileUpload({required this.room, required super.path, required this.dataStream}) {
    _upload();
  }

  final RoomClient room;

  final Stream<List<int>> dataStream;

  final _completer = Completer();

  int _bytesUploaded = 0;

  @override
  int get bytesUploaded => _bytesUploaded;

  @override
  Future get done {
    return _completer.future;
  }

  final _downloadUrlCompleter = Completer<Uri>();

  Future<Uri> get downloadUrl {
    return _downloadUrlCompleter.future;
  }

  void _upload() async {
    try {
      final handle = await room.storage.open(path, overwrite: true);

      try {
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

      final url = await room.storage.downloadUrl(path);
      _downloadUrlCompleter.complete(Uri.parse(url));
    } catch (err) {
      _completer.completeError(err);
      _downloadUrlCompleter.completeError(err);
    }
  }
}

// ignore: depend_on_referenced_packages
typedef PreviousMeshElementMapper = (MeshElement element, MeshElement? previous) Function(MeshElement);
PreviousMeshElementMapper mapMeshElement() {
  MeshElement? previous;

  return (element) {
    final result = (element, previous);

    previous = element;
    return result;
  };
}

class ChatThreadController extends ChangeNotifier {
  ChatThreadController({required this.room}) {
    textFieldController.addListener(() {
      notifyListeners();
    });
  }

  final RoomClient room;
  final TextEditingController textFieldController = ShadTextEditingController();
  final List<FileUpload> _attachmentUploads = [];

  List<FileUpload> get attachmentUploads => List<FileUpload>.unmodifiable(_attachmentUploads);

  Future<FileUpload> uploadFile(String path, Stream<Uint8List> dataStream) async {
    final uploader = MeshagentFileUpload(room: room, path: path, dataStream: dataStream);

    _attachmentUploads.add(uploader);
    notifyListeners();

    return uploader;
  }

  String get text {
    return textFieldController.text;
  }

  void removeFileUpload(FileUpload upload) {
    _attachmentUploads.remove(upload);

    notifyListeners();
  }

  void clear() {
    textFieldController.clear();
    _attachmentUploads.clear();

    notifyListeners();
  }

  Iterable<String> getParticipantNames(MeshDocument document) sync* {
    for (final child in document.root.getChildren().whereType<MeshElement>()) {
      if (child.tagName == "members") {
        for (final member in child.getChildren().whereType<MeshElement>()) {
          yield member.attributes["name"];
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

  void send(
    MeshDocument document,
    String path,
    String value,
    List<FileUpload> attachments,
    Function(String message, List<FileUpload> attachments)? onMessageSent,
  ) async {
    if (value.trim().isNotEmpty || attachments.isNotEmpty) {
      final messages = document.root.getChildren().whereType<MeshElement>().firstWhere((x) => x.tagName == "messages");

      final message = messages.createChildElement("message", {
        "id": const Uuid().v4().toString(),
        "text": value,
        "created_at": DateTime.now().toUtc().toIso8601String(),
        "author_name": room.localParticipant!.getAttribute("name"),
        "author_ref": null,
      });

      for (final attachment in attachments) {
        message.createChildElement("file", {"path": attachment.path});
      }

      for (final participant in getOnlineParticipants(document)) {
        room.messaging.sendMessage(
          to: participant,
          type: "chat",
          message: {
            "path": path,
            "text": value,
            "attachments": attachments.map((a) => {"path": a.path}).toList(),
          },
        );
      }

      onMessageSent?.call(value, attachments);
    }
  }

  @override
  void dispose() {
    super.dispose();

    textFieldController.dispose();

    for (final upload in _attachmentUploads) {
      upload.done.ignore();
      upload.dispose();
    }
  }
}

class ChatThreadLoader extends StatefulWidget {
  const ChatThreadLoader({
    super.key,
    this.participants,
    required this.path,
    required this.room,

    this.startChatCentered = false,
    this.participantNames,
    this.participantNameBuilder,

    this.initialMessageID,
    this.initialMessageText,
    this.initialMessageAttachments,
    this.controller,

    this.onMessageSent,
    this.includeLocalParticipant = true,

    this.waitingForParticipantsBuilder,
    this.attachmentBuilder,
    this.fileInThreadBuilder,
  });

  final List<Participant>? participants;
  final List<String>? participantNames;
  final String path;
  final RoomClient room;
  final bool startChatCentered;
  final bool includeLocalParticipant;

  final Widget Function(String, DateTime)? participantNameBuilder;
  final Widget Function(BuildContext, List<String>)? waitingForParticipantsBuilder;

  final String? initialMessageID;
  final String? initialMessageText;
  final List<FileUpload>? initialMessageAttachments;
  final ChatThreadController? controller;

  final void Function(String message, List<FileUpload> attachments)? onMessageSent;
  final Widget Function(BuildContext context, FileUpload upload)? attachmentBuilder;
  final Widget Function(BuildContext context, String path)? fileInThreadBuilder;

  @override
  State createState() => _ChatThreadLoader();
}

class _ChatThreadLoader extends State<ChatThreadLoader> {
  void ensureParticipants(MeshDocument document) {
    final participants = <Participant>[
      if (widget.participants != null) ...widget.participants!,
      if (widget.includeLocalParticipant) widget.room.localParticipant!,
    ];

    if (widget.participants != null || widget.participantNames != null) {
      Set<String> existing = {};

      for (final child in document.root.getChildren().whereType<MeshElement>()) {
        if (child.tagName == "members") {
          for (final member in child.getChildren().whereType<MeshElement>()) {
            existing.add(member.getAttribute("name"));
          }

          for (final part in participants) {
            if (!existing.contains(part.getAttribute("name"))) {
              child.createChildElement("member", {"name": part.getAttribute("name")});
              existing.add(part.getAttribute("name"));
            }
          }

          if (widget.participantNames != null) {
            for (final part in widget.participantNames!) {
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
      path: widget.path,
      room: widget.room,
      builder: (context, document, error) {
        if (error != null) {
          return Center(child: Text("Unable to load thread", style: ShadTheme.of(context).textTheme.p));
        }

        if (document == null) {
          return Center(child: CircularProgressIndicator());
        }

        ensureParticipants(document);

        return ChatThread(
          path: widget.path,
          document: document,
          room: widget.room,
          participantNameBuilder: widget.participantNameBuilder,
          waitingForParticipantsBuilder: widget.waitingForParticipantsBuilder,

          initialMessageID: widget.initialMessageID,
          initialMessageText: widget.initialMessageText,
          initialMessageAttachments: widget.initialMessageAttachments,

          onMessageSent: widget.onMessageSent,
          controller: widget.controller,
          attachmentBuilder: widget.attachmentBuilder,
          fileInThreadBuilder: widget.fileInThreadBuilder,
        );
      },
    );
  }
}

class ChatThreadInput extends StatefulWidget {
  const ChatThreadInput({
    super.key,
    required this.room,
    required this.onSend,
    required this.controller,
    this.onChanged,
    this.attachmentBuilder,
  });

  final RoomClient room;
  final void Function(String, List<FileUpload>) onSend;
  final void Function(String, List<FileUpload>)? onChanged;
  final ChatThreadController controller;
  final Widget Function(BuildContext context, FileUpload upload)? attachmentBuilder;

  @override
  State createState() => _ChatThreadInput();
}

class _ChatThreadInput extends State<ChatThreadInput> {
  bool showSendButton = false;

  String text = "";
  List<FileUpload> attachments = [];

  late final focusNode = FocusNode(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
        widget.onSend(widget.controller.text, widget.controller.attachmentUploads);

        widget.controller.textFieldController.clear();

        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    },
  );

  void _onChanged() {
    final newText = widget.controller.text;
    final newAttachments = widget.controller.attachmentUploads;

    if (newText != text || newAttachments != attachments) {
      text = newText;
      attachments = newAttachments;

      widget.onChanged?.call(text, attachments);
      setShowSendButton();
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

    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    super.dispose();

    focusNode.dispose();
  }

  Future<void> _onSelectAttachment() async {
    final picked = await FilePicker.platform.pickFiles(dialogTitle: "Select files", allowMultiple: true, withReadStream: true);

    if (picked == null) {
      return;
    }

    for (final file in picked.files) {
      widget.controller.uploadFile(file.name, file.readStream!.map(Uint8List.fromList));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListenableBuilder(
          listenable: widget.controller,
          builder: (context, child) {
            if (attachments.isEmpty) {
              return SizedBox.shrink();
            }

            return Padding(
              padding: EdgeInsets.only(bottom: 5),
              child: SizedBox(
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

                      return FileDefaultPreviewCard(
                        icon: LucideIcons.file,
                        text: attachment.filename,
                        onClose: () {
                          widget.controller.removeFileUpload(attachment);
                        },
                      );

                      //                  return Container(
                      //                    key: ValueKey(attachment.path),
                      //                    width: 200.0,
                      //                    height: 250.0,
                      //                    decoration: BoxDecoration(
                      //                      border: Border.all(color: ShadTheme.of(context).colorScheme.border),
                      //                      borderRadius: BorderRadius.circular(8),
                      //                    ),
                      //                    child: Column(
                      //                      crossAxisAlignment: CrossAxisAlignment.end,
                      //                      children: [
                      //                        Container(
                      //                          padding: EdgeInsets.only(left: 15),
                      //                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: ShadTheme.of(context).colorScheme.border))),
                      //                          child: Row(
                      //                            mainAxisAlignment: MainAxisAlignment.center,
                      //                            children: [
                      //                              Expanded(
                      //                                child: Text(
                      //                                  attachment.filename,
                      //                                  overflow: TextOverflow.ellipsis,
                      //                                  style: ShadTheme.of(context).textTheme.small,
                      //                                ),
                      //                              ),
                      //
                      //                              ShadIconButton.ghost(
                      //                                onPressed: () {
                      //                                  attachmentController.remove(attachment);
                      //                                },
                      //                                icon: Icon(LucideIcons.x),
                      //                              ),
                      //                            ],
                      //                          ),
                      //                        ),
                      //                        Expanded(child: SizedBox(width: 200, child: _AttachmentPreview(room: widget.room, path: attachment.path))),
                      //                      ],
                      //                    ),
                      //                  );
                    },
                  ),
                ),
              ),
            );
          },
        ),

        ShadInput(
          inputPadding: EdgeInsets.all(2),
          leading: ShadTooltip(
            waitDuration: Duration(seconds: 1),
            builder: (context) => Text("Attach"),
            child: ShadGestureDetector(
              cursor: SystemMouseCursors.click,
              onTap: _onSelectAttachment,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(shape: BoxShape.circle, color: ShadTheme.of(context).colorScheme.foreground),
                child: Icon(LucideIcons.paperclip, color: ShadTheme.of(context).colorScheme.background),
              ),
            ),
          ),
          trailing:
              showSendButton
                  ? ShadTooltip(
                    waitDuration: Duration(seconds: 1),
                    builder: (context) => Text("Send"),
                    child: ShadGestureDetector(
                      cursor: SystemMouseCursors.click,
                      onTap: () {
                        widget.onSend(widget.controller.text, widget.controller.attachmentUploads);
                        widget.controller.clear();
                      },
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: ShadTheme.of(context).colorScheme.foreground),
                        child: Icon(LucideIcons.arrowUp, color: ShadTheme.of(context).colorScheme.background),
                      ),
                    ),
                  )
                  : null,
          padding: EdgeInsets.only(left: 5, right: 5, top: 5, bottom: 5),
          decoration: ShadDecoration(
            secondaryFocusedBorder: ShadBorder.none,
            secondaryBorder: ShadBorder.none,
            color: ShadTheme.of(context).ghostButtonTheme.hoverBackgroundColor,
            border: ShadBorder.all(radius: BorderRadius.circular(30)),
          ),
          maxLines: null,
          placeholder: Text("Message"),
          focusNode: focusNode,
          controller: widget.controller.textFieldController,
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
    this.participantNameBuilder,

    this.initialMessageID,
    this.initialMessageText,
    this.initialMessageAttachments,

    this.onMessageSent,
    this.controller,
    this.waitingForParticipantsBuilder,
    this.attachmentBuilder,
    this.fileInThreadBuilder,
  });

  final Widget Function(BuildContext, List<String>)? waitingForParticipantsBuilder;

  final String path;
  final MeshDocument document;
  final RoomClient room;
  final bool startChatCentered;
  final Widget Function(String, DateTime)? participantNameBuilder;

  final String? initialMessageID;
  final String? initialMessageText;
  final List<FileUpload>? initialMessageAttachments;
  final void Function(String message, List<FileUpload> attachments)? onMessageSent;
  final ChatThreadController? controller;
  final Widget Function(BuildContext context, FileUpload upload)? attachmentBuilder;
  final Widget Function(BuildContext context, String path)? fileInThreadBuilder;

  @override
  State createState() => _ChatThread();
}

class _ChatThread extends State<ChatThread> {
  late StreamSubscription<RoomEvent> sub;

  Map<String, Timer> typing = {};
  Set<String> thinking = {};
  Iterable<MeshElement> messages = [];

  late final ChatThreadController controller;

  Iterable<MeshElement> _getMessages() {
    final threadMessages = widget.document.root.getChildren().whereType<MeshElement>().where((x) => x.tagName == "messages").firstOrNull;

    return (threadMessages?.getChildren() ?? []).whereType<MeshElement>();
  }

  @override
  void initState() {
    super.initState();

    controller = widget.controller ?? ChatThreadController(room: widget.room);

    if (widget.initialMessageID != null) {
      final threadMessages = widget.document.root.getChildren().whereType<MeshElement>().where((x) => x.tagName == "messages").firstOrNull;
      final initialMessage =
          threadMessages?.getChildren().whereType<MeshElement>().where((x) => x.attributes["id"] == widget.initialMessageID).firstOrNull;

      if (initialMessage == null) {
        controller.send(
          widget.document,
          widget.path,
          widget.initialMessageText ?? "",
          widget.initialMessageAttachments ?? [],
          widget.onMessageSent,
        );
      }
    }

    sub = widget.room.listen(onRoomMessage);
    widget.document.addListener(onDocumentChanged);
    messages = _getMessages();

    checkParticipants();
  }

  void onDocumentChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      messages = _getMessages();
    });

    checkParticipants();
  }

  void onRoomMessage(RoomEvent event) {
    if (!mounted) {
      return;
    }

    if (event is RoomMessageEvent) {
      if (event.message.type.startsWith("participant")) {
        checkParticipants();
      }

      if (event.message.fromParticipantId == widget.room.localParticipant!.id) {
        return;
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
      } else if (event.message.type == "thinking" && event.message.message["path"] == widget.path) {
        if (event.message.message["thinking"] == true) {
          thinking.add(event.message.fromParticipantId);
        } else {
          thinking.remove(event.message.fromParticipantId);
        }

        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  Set<String> offlineParticipants = {};

  void checkParticipants() {
    final parts = controller.getOfflineParticipants(widget.document).toSet();
    if (!setEquals(parts, offlineParticipants)) {
      offlineParticipants = parts;
      if (!mounted) {
        return;
      }
      setState(() {});
    }
  }

  Widget buildFileInThread(BuildContext context, String path) {
    return ShadGestureDetector(
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
                    final url = await widget.room.storage.downloadUrl(path);

                    launchUrl(Uri.parse(url));
                  },
                  child: Text("Download"),
                ),
              ],
              child: FilePreview(room: widget.room, path: path, fit: BoxFit.cover),
            );
          },
        );
      },
      child:
          widget.fileInThreadBuilder != null
              ? widget.fileInThreadBuilder!(context, path)
              : ChatThreadPreview(room: widget.room, path: path),
    );
  }

  Widget buildMessage(BuildContext context, MeshElement message, MeshElement? previous) {
    final isSameAuthor = message.attributes["author_name"] == previous?.attributes["author_name"];
    final mine = message.attributes["author_name"] == widget.room.localParticipant!.getAttribute("name");

    final mdColor =
        ShadTheme.of(context).textTheme.p.color ?? DefaultTextStyle.of(context).style.color ?? ShadTheme.of(context).colorScheme.foreground;
    final baseFontSize = MediaQuery.of(context).textScaler.scale((DefaultTextStyle.of(context).style.fontSize ?? 14));

    final text = message.getAttribute("text");

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 912),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isSameAuthor && widget.participantNameBuilder != null)
              widget.participantNameBuilder!(message.attributes["author_name"], DateTime.parse(message.attributes["created_at"])),

            if (text.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                margin: EdgeInsets.only(top: 8, right: mine ? 0 : 50, left: mine ? 50 : 0),
                decoration: BoxDecoration(
                  color: ShadTheme.of(context).ghostButtonTheme.hoverBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
                  child: MarkdownWidget(
                    padding: const EdgeInsets.all(0),
                    config: MarkdownConfig(
                      configs: [
                        HrConfig(color: mdColor),
                        H1Config(style: TextStyle(fontSize: baseFontSize * 2, color: mdColor, fontWeight: FontWeight.bold)),
                        H2Config(style: TextStyle(fontSize: baseFontSize * 1.8, color: mdColor, inherit: false)),
                        H3Config(style: TextStyle(fontSize: baseFontSize * 1.6, color: mdColor, inherit: false)),
                        H4Config(style: TextStyle(fontSize: baseFontSize * 1.4, color: mdColor, inherit: false)),
                        H5Config(style: TextStyle(fontSize: baseFontSize * 1.2, color: mdColor, inherit: false)),
                        H6Config(style: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false)),
                        PreConfig(
                          decoration: BoxDecoration(color: ShadTheme.of(context).cardTheme.backgroundColor),
                          textStyle: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false),
                        ),
                        PConfig(textStyle: TextStyle(fontSize: baseFontSize * 1.0, color: mdColor, inherit: false)),
                        CodeConfig(style: GoogleFonts.sourceCodePro(fontSize: baseFontSize * 1.0, color: mdColor)),
                        BlockquoteConfig(textColor: mdColor),
                        LinkConfig(
                          style: TextStyle(
                            color: ShadTheme.of(context).linkButtonTheme.foregroundColor,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        ListConfig(
                          marker: (isOrdered, depth, index) {
                            return Padding(padding: EdgeInsets.only(right: 5), child: Text("${index + 1}.", textAlign: TextAlign.right));
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
                    data: message.getAttribute("text"),
                  ),
                ),
              ),
            for (final attachment in message.getChildren())
              Container(
                margin: EdgeInsets.only(top: 8),
                child: Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: buildFileInThread(context, (attachment as MeshElement).getAttribute("path")),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (offlineParticipants.isNotEmpty && widget.waitingForParticipantsBuilder != null) {
      return widget.waitingForParticipantsBuilder!(context, offlineParticipants.toList());
    }
    bool bottomAlign = !widget.startChatCentered || messages.isNotEmpty;

    final rendredMessages = messages.map(mapMeshElement()).map<Widget>((item) => buildMessage(context, item.$1, item.$2)).toList().reversed;

    return FileDropArea(
      onFileDrop: (name, dataStream) async {
        widget.controller?.uploadFile(name, dataStream);
      },

      child: Column(
        mainAxisAlignment: bottomAlign ? MainAxisAlignment.end : MainAxisAlignment.center,
        children: [
          Expanded(child: ListView(reverse: true, padding: EdgeInsets.all(16), children: rendredMessages.toList())),

          if (!bottomAlign)
            if (controller.getOnlineParticipants(widget.document).firstOrNull != null)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20, horizontal: 50),
                child: Text(
                  controller.getOnlineParticipants(widget.document).first.getAttribute("empty_state_title") ?? "How can I help you?",
                  style: ShadTheme.of(context).textTheme.h3,
                ),
              ),

          if ((typing.isNotEmpty || thinking.isNotEmpty))
            Container(
              width: double.infinity,
              height: 30,
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

          Padding(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 912),
                child: ChatThreadInput(
                  room: widget.room,
                  onSend: (value, attachments) {
                    controller.send(widget.document, widget.path, value, attachments, widget.onMessageSent);
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
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();

    controller.dispose();

    sub.cancel();
    widget.document.removeListener(onDocumentChanged);
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
              width: 300,
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ImagePreview(key: ValueKey(path), url: Uri.parse(snapshot.data!), fit: BoxFit.cover),
              ),
            );
          }

          return ColoredBox(color: ShadTheme.of(context).colorScheme.background);
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

class JoinMeetingButton extends StatelessWidget {
  const JoinMeetingButton({super.key, required this.controller});

  final MeetingController controller;

  @override
  Widget build(BuildContext context) {
    return ShadButton.outline(
      leading: Icon(LucideIcons.mic),
      enabled: controller.livekitRoom.connectionState == livekit.ConnectionState.disconnected,
      onPressed: () async {
        await controller.connect(livekit.FastConnectOptions(microphone: livekit.TrackOption(enabled: true)));
      },
      child: Text("Voice"),
    );
  }
}

typedef FileDropCallback = Future<void> Function(String name, Stream<Uint8List> dataStream);

class FileDropArea extends StatefulWidget {
  final FileDropCallback onFileDrop;
  final Widget child;

  const FileDropArea({super.key, required this.onFileDrop, required this.child});

  @override
  FileDropAreaState createState() => FileDropAreaState();
}

class FileDropAreaState extends State<FileDropArea> {
  bool _dragging = false;

  static const _preferredFormats = [
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

  Future<Stream<Uint8List>> _getStream(DataReader reader, SimpleFileFormat? format) {
    final completer = Completer<Stream<Uint8List>>();

    reader.getFile(format, (file) => completer.complete(file.getStream()), onError: (e) => completer.completeError(e));

    return completer.future;
  }

  @override
  void initState() {
    super.initState();

    final events = ClipboardEvents.instance;
    events?.registerPasteEventListener(onPasteEvent);
  }

  @override
  void dispose() {
    super.dispose();

    final events = ClipboardEvents.instance;
    events?.unregisterPasteEventListener(onPasteEvent);
  }

  void onPasteEvent(ClipboardReadEvent event) async {
    final reader = await event.getClipboardReader();
    final name = (await reader.getSuggestedName())!;
    final fmt = _preferredFormats.firstWhereOrNull((f) => reader.canProvide(f));
    final stream = await _getStream(reader, fmt);

    await widget.onFileDrop(name, stream);
  }

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: const [...Formats.standardFormats, Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDragOver,
      onDropLeave: _onDragLeave,
      onPerformDrop: _onDrop,
      child: Stack(children: [widget.child, if (_dragging) Positioned.fill(child: Container(color: Colors.blue.withValues(alpha: 0.1)))]),
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
        final fmt = _preferredFormats.firstWhereOrNull((f) => reader.canProvide(f));
        final stream = await _getStream(reader, fmt);

        await widget.onFileDrop(name, stream);
      } catch (err, st) {
        debugPrint('Error dropping file: $err\n$st');
      }
    }
  }
}
