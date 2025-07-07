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

enum UploadStatus { initial, uploading, completed, failed }

abstract class FileUpload extends ChangeNotifier {
  FileUpload({required this.path, this.size = 0});

  UploadStatus _status = UploadStatus.initial;

  UploadStatus get status => _status;

  @protected
  set status(UploadStatus value) {
    if (_status != value) {
      _status = value;
      notifyListeners();
    }
  }

  String path;
  int size;

  int get bytesUploaded;

  Future get done;

  String get filename => path.split("/").last;

  void startUpload();
}

class MeshagentFileUpload extends FileUpload {
  MeshagentFileUpload({required this.room, required super.path, required this.dataStream, super.size = 0}) {
    _upload();
  }

  // Requires to manually call startUpload()
  MeshagentFileUpload.deffered({required this.room, required super.path, required this.dataStream, super.size = 0});

  final RoomClient room;

  final Stream<List<int>> dataStream;

  final _completer = Completer();

  int _bytesUploaded = 0;

  @override
  int get bytesUploaded => _bytesUploaded;

  @override
  Future get done => _completer.future;

  final _downloadUrlCompleter = Completer<Uri>();

  Future<Uri> get downloadUrl => _downloadUrlCompleter.future;

  @override
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

  Future<FileUpload> uploadFile(String path, Stream<Uint8List> dataStream, int size) async {
    final uploader = MeshagentFileUpload(room: room, path: path, dataStream: dataStream, size: size);
    uploader.addListener(notifyListeners);

    _attachmentUploads.add(uploader);
    notifyListeners();

    return uploader;
  }

  Future<FileUpload> uploadFileDeferred(String path, Stream<Uint8List> dataStream, int size) async {
    final uploader = MeshagentFileUpload.deffered(room: room, path: path, dataStream: dataStream, size: size);

    uploader.addListener(notifyListeners);

    _attachmentUploads.add(uploader);
    notifyListeners();

    return uploader;
  }

  String get text {
    return textFieldController.text;
  }

  void removeFileUpload(FileUpload upload) {
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

  void send({
    required MeshDocument thread,
    required String path,
    required ChatMessage message,
    void Function(ChatMessage)? onMessageSent,
  }) async {
    if (message.text.trim().isNotEmpty || message.attachments.isNotEmpty) {
      final messages = thread.root.getChildren().whereType<MeshElement>().firstWhere((x) => x.tagName == "messages");

      final m = messages.createChildElement("message", {
        "id": const Uuid().v4().toString(),
        "text": message.text,
        "created_at": DateTime.now().toUtc().toIso8601String(),
        "author_name": room.localParticipant!.getAttribute("name"),
        "author_ref": null,
      });

      for (final path in message.attachments) {
        m.createChildElement("file", {"path": path});
      }

      for (final participant in getOnlineParticipants(thread)) {
        room.messaging.sendMessage(
          to: participant,
          type: "chat",
          message: {
            "path": path,
            "text": message.text,
            "attachments": message.attachments.map((a) => {"path": a}).toList(),
          },
        );
      }

      onMessageSent?.call(message);

      clear();
    }
  }

  @override
  void dispose() {
    super.dispose();

    textFieldController.dispose();

    for (final upload in _attachmentUploads) {
      upload.removeListener(notifyListeners);
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

    this.initialMessage,
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

  final ChatMessage? initialMessage;

  final ChatThreadController? controller;

  final void Function(ChatMessage)? onMessageSent;
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
      key: ValueKey(widget.path),
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

          initialMessage: widget.initialMessage,

          onMessageSent: widget.onMessageSent,
          controller: widget.controller,
          attachmentBuilder: widget.attachmentBuilder,
          fileInThreadBuilder: widget.fileInThreadBuilder,
        );
      },
    );
  }
}

class ChatThreadAttachButton extends StatelessWidget {
  const ChatThreadAttachButton({required this.controller, super.key});

  final ChatThreadController controller;

  Future<void> _onSelectAttachment() async {
    final picked = await FilePicker.platform.pickFiles(dialogTitle: "Select files", allowMultiple: true, withReadStream: true);

    if (picked == null) {
      return;
    }

    for (final file in picked.files) {
      controller.uploadFile(file.name, file.readStream!.map(Uint8List.fromList), file.size);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShadTooltip(
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
    this.leading,
  });

  final RoomClient room;
  final void Function(String, List<FileUpload>) onSend;
  final void Function(String, List<FileUpload>)? onChanged;
  final ChatThreadController controller;
  final Widget Function(BuildContext context, FileUpload upload)? attachmentBuilder;
  final Widget? leading;
  @override
  State createState() => _ChatThreadInput();
}

class _ChatThreadInput extends State<ChatThreadInput> {
  bool showSendButton = false;
  bool allAttachmentsUploaded = true;

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

    setState(() {
      text = newText;
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

    widget.controller.addListener(_onChanged);
    ClipboardEvents.instance?.registerPasteEventListener(onPasteEvent);
  }

  @override
  void dispose() {
    super.dispose();

    focusNode.dispose();
    ClipboardEvents.instance?.unregisterPasteEventListener(onPasteEvent);
  }

  Future<DataReaderFile> _getFile(DataReader reader, SimpleFileFormat? format) {
    final completer = Completer<DataReaderFile>();

    reader.getFile(format, completer.complete, onError: completer.completeError);

    return completer.future;
  }

  Future<void> onFileDrop(name, dataStream, size) async {
    widget.controller.uploadFile(name, dataStream, size ?? 0);
  }

  void onPasteEvent(ClipboardReadEvent event) async {
    if (focusNode.hasFocus) {
      final reader = await event.getClipboardReader();

      final name = (await reader.getSuggestedName());
      if (name != null) {
        final fmt = _preferredFormats.firstWhereOrNull((f) => reader.canProvide(f));
        final file = await _getFile(reader, fmt);

        await onFileDrop(name, file.getStream(), file.fileSize);
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
              child: LayoutBuilder(
                builder:
                    (context, constraints) => SizedBox(
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

        ShadInput(
          crossAxisAlignment: CrossAxisAlignment.end,
          constraints: BoxConstraints(maxHeight: 200),
          inputPadding: EdgeInsets.all(2),
          leading: widget.leading,
          trailing:
              showSendButton && allAttachmentsUploaded
                  ? ShadTooltip(
                    waitDuration: Duration(seconds: 1),
                    builder: (context) => Text("Send"),
                    child: ShadGestureDetector(
                      cursor: SystemMouseCursors.click,
                      onTap: () {
                        widget.onSend(widget.controller.text, widget.controller.attachmentUploads);
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
            border: ShadBorder.all(radius: BorderRadius.circular(15)),
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

    this.initialMessage,

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

  final ChatMessage? initialMessage;
  final void Function(ChatMessage message)? onMessageSent;
  final ChatThreadController? controller;
  final Widget Function(BuildContext context, FileUpload upload)? attachmentBuilder;
  final Widget Function(BuildContext context, String path)? fileInThreadBuilder;

  @override
  State createState() => _ChatThread();
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.mine, required this.text});

  final bool mine;
  final String text;

  @override
  Widget build(BuildContext context) {
    final mdColor =
        ShadTheme.of(context).textTheme.p.color ?? DefaultTextStyle.of(context).style.color ?? ShadTheme.of(context).colorScheme.foreground;
    final baseFontSize = MediaQuery.of(context).textScaler.scale((DefaultTextStyle.of(context).style.fontSize ?? 14));

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: EdgeInsets.only(top: 8, right: mine ? 0 : 50, left: mine ? 50 : 0),
      decoration: BoxDecoration(color: ShadTheme.of(context).ghostButtonTheme.hoverBackgroundColor, borderRadius: BorderRadius.circular(8)),
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
                style: TextStyle(color: ShadTheme.of(context).linkButtonTheme.foregroundColor, decoration: TextDecoration.underline),
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
          data: text,
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

    if (widget.initialMessage != null) {
      final threadMessages = widget.document.root.getChildren().whereType<MeshElement>().where((x) => x.tagName == "messages").firstOrNull;
      final initialMessage =
          threadMessages?.getChildren().whereType<MeshElement>().where((x) => x.attributes["id"] == widget.initialMessage?.id).firstOrNull;

      if (initialMessage != null) {
        controller.send(thread: widget.document, path: widget.path, message: widget.initialMessage!, onMessageSent: widget.onMessageSent);
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

            if (text.isNotEmpty) ChatBubble(mine: mine, text: message.getAttribute("text")),
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
      onFileDrop: (name, dataStream, size) async {
        widget.controller?.uploadFile(name, dataStream, size ?? 0);
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
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 912),
              child: Container(
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
            ),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 912),
                child: ChatThreadInput(
                  leading: ChatThreadAttachButton(controller: controller),
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
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();

    if (widget.controller == null) {
      controller.dispose();
    }

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

          return SizedBox(width: 300, height: 300, child: ColoredBox(color: ShadTheme.of(context).colorScheme.background));
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
        final fmt = _preferredFormats.firstWhereOrNull(reader.canProvide);
        final file = await _getFile(reader, fmt);

        await widget.onFileDrop(name, file.getStream(), file.fileSize);
      } catch (err, st) {
        debugPrint('Error dropping file: $err\n$st');
      }
    }
  }
}
