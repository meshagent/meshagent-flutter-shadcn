import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import 'package:meshagent/document.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter/meshagent_flutter.dart';
import 'package:meshagent_flutter_shadcn/chat/jumping_dots.dart';
import 'package:meshagent_flutter_shadcn/meetings/meetings.dart';
import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';

import 'package:livekit_client/livekit_client.dart' as livekit;

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

class MeshagentFileAttachment {
  MeshagentFileAttachment(this.path);

  final String path;

  String get filename {
    final lastSlashIndex = path.lastIndexOf('/');

    if (lastSlashIndex == -1) {
      return path;
    }

    return path.substring(lastSlashIndex + 1);
  }
}

class MeshagentFileAttachmentController extends ValueNotifier<List<MeshagentFileAttachment>> {
  MeshagentFileAttachmentController() : super([]);

  void add(MeshagentFileAttachment attachment) {
    value = [...value, attachment];
  }

  void remove(MeshagentFileAttachment attachment) {
    value = value.where((x) => x != attachment).toList();
  }

  void clear() {
    value = [];
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

    this.onMessageSent,
    this.attachmentController,
    this.onSelectAttachment,
  });

  final List<Participant>? participants;
  final List<String>? participantNames;
  final String path;
  final RoomClient room;
  final bool startChatCentered;
  final Widget Function(String, DateTime)? participantNameBuilder;

  final String? initialMessageID;
  final String? initialMessageText;
  final List<MeshagentFileAttachment>? initialMessageAttachments;

  final MeshagentFileAttachmentController? attachmentController;
  final void Function(String message, List<MeshagentFileAttachment> attachments)? onMessageSent;
  final void Function(MeshagentFileAttachmentController controller)? onSelectAttachment;

  @override
  State createState() => _ChatThreadLoader();
}

class _ChatThreadLoader extends State<ChatThreadLoader> {
  void ensureParticipants(MeshDocument document) {
    if (widget.participants != null || widget.participantNames != null) {
      Set<String> existing = {};

      for (final child in document.root.getChildren().whereType<MeshElement>()) {
        if (child.tagName == "members") {
          for (final member in child.getChildren().whereType<MeshElement>()) {
            existing.add(member.getAttribute("name"));
          }

          if (widget.participants != null) {
            for (final part in widget.participants!) {
              if (!existing.contains(part.getAttribute("name"))) {
                child.createChildElement("member", {"name": part.getAttribute("name")});
                existing.add(part.getAttribute("name"));
              }
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

          initialMessageID: widget.initialMessageID,
          initialMessageText: widget.initialMessageText,
          initialMessageAttachments: widget.initialMessageAttachments,

          onMessageSent: widget.onMessageSent,
          attachmentController: widget.attachmentController,
          onSelectAttachment: widget.onSelectAttachment,
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

    this.onMessageSent,
    this.onSelectAttachment,
    this.attachmentController,

    this.onChanged,
  });

  final RoomClient room;
  final void Function(String, List<MeshagentFileAttachment>) onSend;
  final void Function(String, List<MeshagentFileAttachment>)? onChanged;

  final MeshagentFileAttachmentController? attachmentController;
  final void Function(MeshagentFileAttachmentController controller)? onSelectAttachment;
  final void Function(String message, List<MeshagentFileAttachment> attachments)? onMessageSent;

  @override
  State createState() => _ChatThreadInput();
}

class _ChatThreadInput extends State<ChatThreadInput> {
  final controller = ShadTextEditingController();
  late final MeshagentFileAttachmentController attachmentController;
  bool showSendButton = false;

  late final focusNode = FocusNode(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
        widget.onSend(controller.text, attachmentController.value);

        controller.text = "";
        attachmentController.clear();

        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    },
  );

  void _onChanged() {
    widget.onChanged?.call(controller.text, attachmentController.value);

    setShowSendButton();
  }

  void setShowSendButton() {
    final value = controller.text.isNotEmpty || attachmentController.value.isNotEmpty;

    if (showSendButton != value) {
      setState(() {
        showSendButton = value;
      });
    }
  }

  @override
  void initState() {
    super.initState();

    if (widget.attachmentController != null) {
      attachmentController = widget.attachmentController!;
    } else {
      attachmentController = MeshagentFileAttachmentController();
    }

    attachmentController.addListener(_onChanged);
    controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    super.dispose();

    focusNode.dispose();
    controller.dispose();
    attachmentController.dispose();
  }

  Future<void> _onSelectAttachment() async {
    if (widget.onSelectAttachment != null) {
      widget.onSelectAttachment!(attachmentController);
      return;
    }

    final picked = await FilePicker.platform.pickFiles(dialogTitle: "Select files", allowMultiple: true, withReadStream: true);

    if (picked == null) {
      return;
    }

    for (final PlatformFile file in picked.files) {
      final stream = file.readStream!.map((x) => Uint8List.fromList(x));
      final builder = await stream.fold<BytesBuilder>(BytesBuilder(), (builder, chunk) {
        builder.add(chunk);
        return builder;
      });

      final data = builder.takeBytes();
      final fileName = "/${file.name}";

      final handle = await widget.room.storage.open(fileName);
      await widget.room.storage.write(handle, data);
      await widget.room.storage.close(handle);

      if (mounted) {
        attachmentController.add(MeshagentFileAttachment(fileName));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<List<MeshagentFileAttachment>>(
          valueListenable: attachmentController,
          builder: (context, attachments, child) {
            if (attachments.isEmpty) {
              return SizedBox.shrink();
            }

            return SizedBox(
              width: double.infinity,
              height: 250.0,
              child: ListView.separated(
                itemCount: attachments.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final attachment = attachments[index];

                  return Container(
                    key: ValueKey(attachment.path),
                    width: 200.0,
                    height: 250.0,
                    decoration: BoxDecoration(
                      border: Border.all(color: ShadTheme.of(context).colorScheme.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: EdgeInsets.only(left: 15),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: ShadTheme.of(context).colorScheme.border))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  attachment.filename,
                                  overflow: TextOverflow.ellipsis,
                                  style: ShadTheme.of(context).textTheme.small,
                                ),
                              ),

                              ShadIconButton.ghost(
                                onPressed: () {
                                  attachmentController.remove(attachment);
                                },
                                icon: Icon(LucideIcons.x),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: SizedBox(width: 200, child: _AttachmentPreview(room: widget.room, path: attachment.path))),
                      ],
                    ),
                  );
                },
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
                        widget.onSend(controller.text, attachmentController.value);
                        controller.text = "";
                        attachmentController.clear();
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
          controller: controller,
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
    this.attachmentController,
    this.onSelectAttachment,
  });

  final String path;
  final MeshDocument document;
  final RoomClient room;
  final bool startChatCentered;
  final Widget Function(String, DateTime)? participantNameBuilder;

  final String? initialMessageID;
  final String? initialMessageText;
  final List<MeshagentFileAttachment>? initialMessageAttachments;
  final void Function(String message, List<MeshagentFileAttachment> attachments)? onMessageSent;

  final MeshagentFileAttachmentController? attachmentController;
  final void Function(MeshagentFileAttachmentController controller)? onSelectAttachment;

  @override
  State createState() => _ChatThread();
}

class _ChatThread extends State<ChatThread> {
  late StreamSubscription<RoomEvent> sub;

  Map<String, Timer> typing = {};
  Set<String> thinking = {};
  Iterable<MeshElement> messages = [];

  Iterable<MeshElement> _getMessages() {
    final threadMessages = widget.document.root.getChildren().whereType<MeshElement>().where((x) => x.tagName == "messages").firstOrNull;

    return (threadMessages?.getChildren() ?? []).whereType<MeshElement>();
  }

  @override
  void initState() {
    super.initState();

    if (widget.initialMessageID != null) {
      final threadMessages = widget.document.root.getChildren().whereType<MeshElement>().where((x) => x.tagName == "messages").firstOrNull;
      final initialMessage =
          threadMessages?.getChildren().whereType<MeshElement>().where((x) => x.attributes["id"] == widget.initialMessageID).firstOrNull;

      if (initialMessage == null) {
        send(widget.initialMessageText ?? "", widget.initialMessageAttachments ?? []);
      }
    }

    sub = widget.room.listen(onRoomMessage);
    widget.document.addListener(onDocumentChanged);
    messages = _getMessages();
  }

  void onDocumentChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      messages = _getMessages();
    });
  }

  void onRoomMessage(RoomEvent event) {
    if (!mounted) {
      return;
    }

    if (event is RoomMessageEvent) {
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

  Iterable<String> getParticipantNames() sync* {
    for (final child in widget.document.root.getChildren().whereType<MeshElement>()) {
      if (child.tagName == "members") {
        for (final member in child.getChildren().whereType<MeshElement>()) {
          yield member.attributes["name"];
        }
      }
    }
  }

  Iterable<RemoteParticipant> getOnlineParticipants() sync* {
    for (final participantName in getParticipantNames()) {
      for (final part in widget.room.messaging.remoteParticipants.where((x) => x.getAttribute("name") == participantName)) {
        yield part;
      }
    }
  }

  void send(String value, List<MeshagentFileAttachment> attachments) async {
    if (value.trim().isNotEmpty || attachments.isNotEmpty) {
      final messages = widget.document.root.getChildren().whereType<MeshElement>().firstWhere((x) => x.tagName == "messages");

      final message = messages.createChildElement("message", {
        "id": const Uuid().v4().toString(),
        "text": value,
        "created_at": DateTime.now().toUtc().toIso8601String(),
        "author_name": widget.room.localParticipant!.getAttribute("name"),
        "author_ref": null,
      });

      for (final attachment in attachments) {
        message.createChildElement("file", {"path": attachment.path});
      }

      for (final participant in getOnlineParticipants()) {
        widget.room.messaging.sendMessage(
          to: participant,
          type: "chat",
          message: {
            "path": widget.path,
            "text": value,
            "attachments": attachments.map((a) => {"path": a.path}).toList(),
          },
        );
      }

      widget.onMessageSent?.call(value, attachments);
    }
  }

  Widget buildMessage(BuildContext context, MeshElement message, MeshElement? previous) {
    final isSameAuthor = message.attributes["author_name"] == previous?.attributes["author_name"];
    final mine = message.attributes["author_name"] == widget.room.localParticipant!.getAttribute("name");

    final mdColor =
        ShadTheme.of(context).textTheme.p.color ?? DefaultTextStyle.of(context).style.color ?? ShadTheme.of(context).colorScheme.foreground;
    final baseFontSize = MediaQuery.of(context).textScaler.scale((DefaultTextStyle.of(context).style.fontSize ?? 14));

    final text = message.getAttribute("text");

    return Column(
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
                data: message.getAttribute("text"),
              ),
            ),
          ),
        for (final attachment in message.getChildren())
          Container(
            margin: EdgeInsets.only(top: 8),
            child: Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: SizedBox(
                width: 300,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: FilePreview(room: widget.room, path: (attachment as MeshElement).getAttribute("path")),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool bottomAlign = !widget.startChatCentered || messages.isNotEmpty;

    final rendredMessages = messages.map(mapMeshElement()).map<Widget>((item) => buildMessage(context, item.$1, item.$2)).toList().reversed;

    return Column(
      mainAxisAlignment: bottomAlign ? MainAxisAlignment.end : MainAxisAlignment.center,
      children: [
        Expanded(child: ListView(reverse: true, padding: EdgeInsets.all(16), children: rendredMessages.toList())),

        if (!bottomAlign)
          if (getOnlineParticipants().firstOrNull != null)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 20, horizontal: 50),
              child: Text(
                getOnlineParticipants().first.getAttribute("empty_state_title") ?? "How can I help you?",
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
          child: ChatThreadInput(
            room: widget.room,
            onSend: (value, attachments) {
              send(value, attachments);
            },
            onChanged: (value, attachments) {
              for (final part in getOnlineParticipants()) {
                widget.room.messaging.sendMessage(to: part, type: "typing", message: {"path": widget.path});
              }
            },
            onSelectAttachment: widget.onSelectAttachment,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    super.dispose();

    sub.cancel();
    widget.document.removeListener(onDocumentChanged);
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.room, required this.path});

  final RoomClient room;
  final String path;

  String _getFileExtension(String filename) {
    final lastDotIndex = filename.lastIndexOf('.');

    if (lastDotIndex == -1) {
      return '';
    }

    return filename.substring(lastDotIndex + 1);
  }

  static const filePreviewExtensions = {'jpg', 'gif', 'png', 'webp', 'mp3', 'wav', 'ogg', 'pdf'};

  static const textFiles = {'txt', 'csv', 'json', 'xml'};

  static const documentFiles = {'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx'};

  static const presentationFiles = {'ppt', 'pptx'};

  static const audioFiles = {
    'aac',
    'm4a',
    'ogg',
    'opus',
    'wma',
    'amr',
    'flac',
    'alac',
    'aiff',
    'ape',
    'wv',
    'tta',
    'caf',
    'dff',
    'dsf',
    'mka',
    'pcm',
    'mod',
    'xm',
    's3m',
    'it',
    'mid',
    'midi',
  };

  static const archiveFiles = {'zip', 'tar', 'gz', 'bz2', 'xz', '7z', 'rar', 'iso', 'dmg'};

  static const videoFiles = {'mp4', 'avi', 'mov', 'mkv', 'flv', 'wmv', 'webm', 'mpeg', 'mpg', '3gp', '3g2', 'rmvb', 'rm'};

  @override
  Widget build(BuildContext context) {
    final ext = _getFileExtension(path);
    IconData icon = LucideIcons.file;

    if (filePreviewExtensions.contains(ext)) {
      return FilePreview(room: room, path: path, fit: BoxFit.cover);
    }

    if (audioFiles.contains(ext)) {
      icon = LucideIcons.fileAudio;
    } else if (textFiles.contains(ext)) {
      icon = LucideIcons.fileText;
    } else if (documentFiles.contains(ext)) {
      icon = LucideIcons.fileText;
    } else if (archiveFiles.contains(ext)) {
      icon = LucideIcons.fileArchive;
    } else if (presentationFiles.contains(ext)) {
      icon = LucideIcons.fileChartPie;
    } else if (videoFiles.contains(ext)) {
      icon = LucideIcons.fileVideo;
    }

    return Icon(icon, size: 100, color: ShadTheme.of(context).colorScheme.foreground);
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
