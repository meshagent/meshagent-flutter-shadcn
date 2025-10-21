import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:rfw/formats.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'package:meshagent/document.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter/meshagent_flutter.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';
import 'package:meshagent_flutter_shadcn/file_preview/image.dart';
import 'package:meshagent_flutter_shadcn/meetings/meetings.dart';

import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:rfw/rfw.dart';

import 'jumping_dots.dart';
import 'outbound_delivery_status.dart';

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
  MeshagentFileUpload.deferred({required this.room, required super.path, required this.dataStream, super.size = 0});

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

class ChatThreadController extends ChangeNotifier {
  ChatThreadController({required this.room}) {
    textFieldController.addListener(notifyListeners);
  }

  final List<MessageToolkit> toolkits = [];
  final RoomClient room;
  final TextEditingController textFieldController = ShadTextEditingController();
  final List<FileUpload> _attachmentUploads = [];
  final OutboundMessageStatusQueue outboundStatus = OutboundMessageStatusQueue();

  List<FileUpload> get attachmentUploads => List<FileUpload>.unmodifiable(_attachmentUploads);

  bool toggleToolkit(MessageToolkit toolkit) {
    if (toolkits.contains(toolkit)) {
      toolkits.remove(toolkit);
      return false;
    } else {
      toolkits.add(toolkit);
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

  Future<FileUpload> uploadFile(String path, Stream<Uint8List> dataStream, int size) async {
    final uploader = MeshagentFileUpload(room: room, path: path, dataStream: dataStream, size: size);
    uploader.addListener(notifyListeners);

    _attachmentUploads.add(uploader);
    notifyListeners();

    return uploader;
  }

  Future<FileUpload> uploadFileDeferred(String path, Stream<Uint8List> dataStream, int size) async {
    final uploader = MeshagentFileUpload.deferred(room: room, path: path, dataStream: dataStream, size: size);

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

  Future<void> sendMessageToParticipant({required Participant participant, required String path, required ChatMessage message}) async {
    if (message.text.trim().isNotEmpty || message.attachments.isNotEmpty) {
      await room.messaging.sendMessage(
        to: participant,
        type: "chat",
        message: {
          "toolkits": [for (final tk in toolkits) tk.toJson()],
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

  Future<void> send({
    required MeshDocument thread,
    required String path,
    required ChatMessage message,
    void Function(ChatMessage)? onMessageSent,
  }) async {
    if (message.text.trim().isNotEmpty || message.attachments.isNotEmpty) {
      insertMessage(thread: thread, message: message);

      final List<Future<void>> sentMessages = [];
      for (final participant in getOnlineParticipants(thread)) {
        sentMessages.add(sendMessageToParticipant(participant: participant, path: path, message: message));
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
      upload.done.ignore();
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
  });

  final String path;
  final RoomClient room;
  final List<Participant>? participants;
  final List<String>? participantNames;
  final bool includeLocalParticipant;
  final Widget Function(BuildContext, MeshDocument)? builder;

  void _ensureParticipants(MeshDocument document) {
    final participantsList = <Participant>[if (participants != null) ...participants!, if (includeLocalParticipant) room.localParticipant!];

    if (participants != null || participantNames != null) {
      Set<String> existing = {};

      for (final child in document.root.getChildren().whereType<MeshElement>()) {
        if (child.tagName == "members") {
          for (final member in child.getChildren().whereType<MeshElement>()) {
            existing.add(member.getAttribute("name"));
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
          return const Center(child: CircularProgressIndicator());
        }

        _ensureParticipants(document);

        return builder?.call(context, document) ?? ChatThread(path: path, document: document, room: room);
      },
    );
  }
}

class ChatThreadAttachButton extends StatefulWidget {
  const ChatThreadAttachButton({required this.controller, super.key, this.optionalToolkits = const []});

  final List<MessageToolkit> optionalToolkits;

  final ChatThreadController controller;

  @override
  State createState() => _ChatThreadAttachButton();
}

class _ChatThreadAttachButton extends State<ChatThreadAttachButton> {
  Future<void> _onSelectAttachment() async {
    final picked = await FilePicker.platform.pickFiles(dialogTitle: "Select files", allowMultiple: true, withReadStream: true);

    if (picked == null) {
      return;
    }

    for (final file in picked.files) {
      widget.controller.uploadFile(file.name, file.readStream!.map(Uint8List.fromList), file.size);
    }
  }

  ShadPopoverController popoverController = ShadPopoverController();

  @override
  void dispose() {
    super.dispose();
    popoverController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadContextMenu(
      constraints: BoxConstraints(minWidth: 175),
      anchor: ShadAnchorAuto(followerAnchor: Alignment.topRight, targetAnchor: Alignment.topLeft),
      items: [
        ShadContextMenuItem(leading: Icon(LucideIcons.paperclip), onPressed: _onSelectAttachment, child: Text("Attach a file...")),

        for (final tk in widget.optionalToolkits)
          Builder(
            builder:
                (context) => ShadContextMenuItem(
                  textStyle:
                      widget.controller.toolkits.contains(tk)
                          ? ShadTheme.of(context).contextMenuTheme.textStyle!.copyWith(color: Colors.blue)
                          : null,
                  leading: Icon(tk.icon, color: widget.controller.toolkits.contains(tk) ? Colors.blue : null),
                  onPressed: () => widget.controller.toggleToolkit(tk),

                  trailing:
                      widget.controller.toolkits.contains(tk)
                          ? Icon(LucideIcons.check, color: widget.controller.toolkits.contains(tk) ? Colors.blue : null)
                          : null,
                  child: Text(tk.text),
                ),
          ),
      ],
      controller: popoverController,
      child: GestureDetector(
        onTap: () {
          popoverController.toggle();
        },
        child: SizedBox(width: 22, height: 22, child: Icon(LucideIcons.plus)),
      ),
    );
  }
}

abstract class MessageToolkit {
  MessageToolkit({required this.icon, required this.text});

  final String text;
  final IconData icon;

  Map<String, dynamic> toJson();
}

class MessageRequiredToolkit extends MessageToolkit {
  MessageRequiredToolkit({required super.icon, required this.toolkit, required super.text});

  final RequiredToolkit toolkit;

  @override
  Map<String, dynamic> toJson() {
    return {"required_toolkit": toolkit.toJson()};
  }
}

class MessageLLMToolkit extends MessageToolkit {
  MessageLLMToolkit({required super.icon, required this.config, required super.text});

  final Map<String, dynamic> config;

  @override
  Map<String, dynamic> toJson() {
    return {"llm": config};
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
    this.trailing,
  });

  final RoomClient room;
  final void Function(String, List<FileUpload>) onSend;
  final void Function(String, List<FileUpload>)? onChanged;
  final ChatThreadController controller;
  final Widget Function(BuildContext context, FileUpload upload)? attachmentBuilder;
  final Widget? leading;
  final Widget? trailing;
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
      mainAxisSize: MainAxisSize.min,
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
          inputPadding: EdgeInsets.all(2),
          leading: widget.leading,

          trailing:
              widget.trailing ??
              (showSendButton && allAttachmentsUploaded
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
                  : null),

          padding: EdgeInsets.only(left: 5, right: 5, top: 5, bottom: 5),
          decoration: ShadDecoration(
            secondaryFocusedBorder: ShadBorder.none,
            secondaryBorder: ShadBorder.none,
            color: ShadTheme.of(context).ghostButtonTheme.hoverBackgroundColor,
            border: ShadBorder.all(radius: BorderRadius.circular(15)),
          ),
          maxLines: 8,
          minLines: 1,
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
    this.initialMessage,
    this.onMessageSent,
    this.controller,

    this.participantNameBuilder,
    this.waitingForParticipantsBuilder,
    this.attachmentBuilder,
    this.fileInThreadBuilder,
    this.inputLeadingBuilder,
  });

  final String path;
  final MeshDocument document;
  final RoomClient room;
  final bool startChatCentered;
  final ChatMessage? initialMessage;
  final void Function(ChatMessage message)? onMessageSent;
  final ChatThreadController? controller;

  final Widget Function(String, DateTime)? participantNameBuilder;
  final Widget Function(BuildContext, List<String>)? waitingForParticipantsBuilder;
  final Widget Function(BuildContext context, FileUpload upload)? attachmentBuilder;
  final Widget Function(BuildContext context, String path)? fileInThreadBuilder;
  final Widget Function(BuildContext, ChatThreadController)? inputLeadingBuilder;

  @override
  State createState() => _ChatThreadState();
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
                showTyping: state.typing.isNotEmpty || state.thinking.isNotEmpty,
                participantNameBuilder: widget.participantNameBuilder,
                fileInThreadBuilder: widget.fileInThreadBuilder,
                currentStatusEntry: _currentStatusEntry,
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 912),
                    child: ChatThreadInput(
                      leading: widget.inputLeadingBuilder == null ? null : widget.inputLeadingBuilder!(context, controller),
                      trailing:
                          state.thinking.isNotEmpty
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
            ],
          ),
        );
      },
    );
  }
}

class ChatThreadMessages extends StatelessWidget {
  const ChatThreadMessages({
    super.key,
    required this.room,
    required this.messages,
    required this.online,

    this.startChatCentered = false,
    this.showTyping = false,
    this.participantNameBuilder,
    this.fileInThreadBuilder,
    this.currentStatusEntry,
  });

  final RoomClient room;
  final bool startChatCentered;
  final bool showTyping;
  final List<MeshElement> messages;
  final List<Participant> online;
  final OutboundEntry? currentStatusEntry;

  final Widget Function(String, DateTime)? participantNameBuilder;
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
    final isSameAuthor = message.attributes["author_name"] == previous?.attributes["author_name"];
    final mine = message.attributes["author_name"] == room.localParticipant!.getAttribute("name");

    final text = message.getAttribute("text");
    final id = message.getAttribute("id");

    if (message.tagName == "reasoning") {
      return ReasoningTrace(previous: previous, message: message, next: next);
    }
    if (message.tagName == "exec") {
      return ShellLine(previous: previous, message: message, next: next);
    }
    if (message.tagName == "ui") {
      return DynamicUI(room: room, previous: previous, message: message, next: next);
    }

    return Center(
      key: ValueKey(id),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 912),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isSameAuthor && participantNameBuilder != null)
              participantNameBuilder!(message.attributes["author_name"], DateTime.parse(message.attributes["created_at"])),

            if (text is String && text.isNotEmpty) ChatBubble(mine: mine, text: message.getAttribute("text")),

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
      child: Column(
        mainAxisAlignment: bottomAlign ? MainAxisAlignment.end : MainAxisAlignment.center,
        children: [
          Expanded(child: ListView(reverse: true, padding: EdgeInsets.all(16), children: messageWidgets)),

          if (!bottomAlign)
            if (online.firstOrNull != null)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20, horizontal: 50),
                child: Text(
                  online.first.getAttribute("empty_state_title") ?? "How can I help you?",
                  style: ShadTheme.of(context).textTheme.h3,
                ),
              ),

          if (showTyping)
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
        ],
      ),
    );
  }
}

class ChatThreadSnapshot {
  ChatThreadSnapshot({required this.messages, required this.online, required this.offline, required this.typing, required this.thinking});

  final List<MeshElement> messages;
  final List<Participant> online;
  final List<String> offline;
  final List<String> typing;
  final List<String> thinking;
}

class ChatThreadBuilder extends StatefulWidget {
  const ChatThreadBuilder({
    super.key,
    required this.path,
    required this.document,
    required this.room,
    required this.controller,
    required this.builder,
  });

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
  List<MeshElement> messages = [];

  @override
  void initState() {
    super.initState();

    sub = widget.room.listen(_onRoomMessage);
    widget.document.addListener(_onDocumentChanged);

    _getParticipants();
    _getMessages();
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
      if (event.message.type.startsWith("participant")) {
        _getParticipants();
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

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      ChatThreadSnapshot(
        messages: messages,
        online: onlineParticipants.toList(),
        offline: offlineParticipants.toList(),
        typing: typing.keys.toList(),
        thinking: thinking.toList(),
      ),
    );
  }
}

class DynamicUI extends StatefulWidget {
  const DynamicUI({super.key, required this.room, required this.previous, required this.message, required this.next});

  final RoomClient room;
  final MeshElement? previous;
  final MeshElement message;
  final MeshElement? next;

  @override
  State createState() => _DynamicUI();
}

class _DynamicUI extends State<DynamicUI> {
  final _runtime = Runtime();
  final _data = DynamicContent();

  static const LibraryName coreName = LibraryName(<String>['core', 'widgets']);
  static const LibraryName mainName = LibraryName(<String>['main']);

  @override
  void initState() {
    super.initState();
    // Local widget library:
    _runtime.update(coreName, createCoreWidgets());
    // Remote widget library:

    updateData();
    updateWidget();

    widget.message.addListener(onUpdated);
  }

  @override
  void dispose() {
    super.dispose();
    widget.message.removeListener(onUpdated);

    _runtime.dispose();
  }

  void onUpdated() {
    error = null;
    updateData();
    updateWidget();
  }

  RemoteWidgetLibrary? _remoteWidgets;
  Exception? error;

  void updateWidget() async {
    final renderer = widget.message.getAttribute("renderer");
    final widgetName = widget.message.getAttribute("widget");
    final data = widget.message.getAttribute("data");

    Response? response;
    if (renderer is String && widgetName is String) {
      try {
        setState(() {
          error = null;
        });
        if (data == null) {
          return;
        }
        response = await widget.room.agents.invokeTool(
          toolkit: renderer,
          tool: widgetName,
          arguments: {"platform": "flutter", "output": "rfw", "data": data},
        );

        final resp = response;
        if (resp is TextResponse) {
          if (!mounted) return;
          setState(() {
            _remoteWidgets = parseLibraryFile(resp.text);
            _runtime.update(mainName, _remoteWidgets!);
          });
        } else if (resp is JsonResponse) {
          if (!mounted) return;

          setState(() {
            final markup = resp.json["markup"];
            final data = resp.json["data"];

            if (data != null) {
              _data.update("serverData", data);
            }

            _remoteWidgets = parseLibraryFile(markup);
            _runtime.update(mainName, _remoteWidgets!);
          });
        } else {
          throw Exception("Expected text response from server");
        }
      } on RoomServerException catch (e) {
        if (!mounted) return;
        setState(() {
          error = e;
        });
      } on ParserException catch (e) {
        if (!mounted) return;
        setState(() {
          error = Exception(
            "${e.message} at ${e.line}, ${e.column}:\n${(response as TextResponse).text.split("\n").mapIndexed((i, s) => "${i + 1}: $s").join("\n")}",
          );
        });
      }
    } else {
      _remoteWidgets = null;
    }
  }

  void updateData() {
    try {
      final json = widget.message.getAttribute("data");
      if (json != null) {
        final data = jsonDecode(json);

        // Configuration data:
        _data.update('data', data);
      } else {
        _data.update('data', {});
      }
    } catch (e) {
      _data.update('error', e.toString());
    }
  }

  void onEvent(String name, DynamicMap? data) async {
    try {
      if (name == "invoke") {
        await widget.room.agents.invokeTool(
          toolkit: data!["toolkit"] as String,
          tool: data["tool"] as String,
          arguments: data["arguments"] as Map<String, dynamic>,
        );
      } else if (name == "open") {
        await launchUrl(Uri.parse(data!["url"] as String), webOnlyWindowName: data["target"] as String?);
      } else {
        showShadDialog(context: context, builder: (context) => ShadDialog.alert(title: Text("Unknown event received $name")));
      }
    } on Exception catch (ex) {
      if (!mounted) {
        return;
      }
      showShadDialog(
        context: context,
        builder: (context) => ShadDialog.alert(title: Text("Unable to process event $name, data: $data, error: $ex")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return SelectableText("$error", style: ShadTheme.of(context).textTheme.p);
    }
    if (_remoteWidgets == null) {
      return Container();
    }
    return RemoteWidget(runtime: _runtime, data: _data, widget: const FullyQualifiedWidgetName(mainName, 'root'), onEvent: onEvent);
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
    final mdColor = (ShadTheme.of(context).textTheme.p.color ??
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
                    data: widget.message.attributes["summary"] ?? "",
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
              decoration: BoxDecoration(border: Border(bottom: border), color: ShadTheme.of(context).colorScheme.secondary),
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
                        TextSpan(text: widget.message.attributes["command"], style: GoogleFonts.sourceCodePro()),
                        TextSpan(text: " "),
                        if (widget.message.attributes["result"] != null) ...[
                          TextSpan(text: "\n"),
                          TextSpan(text: widget.message.attributes["result"].trim(), style: GoogleFonts.sourceCodePro()),
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
