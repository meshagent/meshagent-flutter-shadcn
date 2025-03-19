import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:meshagent/document.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/chat/jumping_dots.dart';
import 'package:meshagent_flutter_shadcn/meetings/meetings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:meshagent_flutter/meshagent_flutter.dart';

import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

// ignore: depend_on_referenced_packages

class ChatThreadLoader extends StatefulWidget {
  const ChatThreadLoader(
      {super.key, this.participants, required this.path, required this.room, this.startChatCentered = false, this.participantNames});

  final List<Participant>? participants;
  final List<String>? participantNames;
  final String path;
  final RoomClient room;
  final bool startChatCentered;

  @override
  State createState() => _ChatThreadLoader();
}

class _ChatThreadLoader extends State<ChatThreadLoader> {
  Future<MeshDocument>? threadFuture;

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
                existing.add(part.getAttribute("name").getAttribute("name"));
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

        return ChatThread(path: widget.path, document: document, room: widget.room);
      },
    );
  }
}

class ChatThread extends StatefulWidget {
  const ChatThread({super.key, required this.path, required this.document, required this.room, this.startChatCentered = false});

  final String path;
  final MeshDocument document;
  final RoomClient room;
  final bool startChatCentered;

  @override
  State createState() => _ChatThread();
}

class _ChatThread extends State<ChatThread> {
  bool showSend = false;

  List<JsonResponse> attachments = [];
  late StreamSubscription<RoomEvent> sub;

  Map<String, Timer> typing = {};
  Set<String> thinking = {};

  @override
  void initState() {
    super.initState();
    sub = widget.room.listen(onRoomMessage);
    widget.document.addListener(onDocumentChanged);
  }

  void onDocumentChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
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

  void send() async {
    if (controller.text.trim().isNotEmpty) {
      final messages = widget.document.root.getChildren().whereType<MeshElement>().firstWhere((x) => x.tagName == "messages");

      messages.createChildElement("message", {
        "id": const Uuid().v4().toString(),
        "text": controller.text,
        "created_at": DateTime.now().toUtc().toIso8601String(),
        "author_name": widget.room.localParticipant!.getAttribute("name"),
        "author_ref": null,
      });

      for (final participant in getOnlineParticipants()) {
        widget.room.messaging.sendMessage(
          to: participant,
          type: "chat",
          message: {"path": widget.path, "text": controller.text, "attachments": attachments.map((a) => a.json).toList()},
        );
      }

      attachments.clear();
      controller.text = "";
      setState(() {});
    }
  }

  final controller = ShadTextEditingController();

  Widget buildMessage(BuildContext context, MeshElement message) {
    bool mine = message.attributes["author_name"] == widget.room.localParticipant!.getAttribute("name");
    final mdColor =
        ShadTheme.of(context).textTheme.p.color ?? DefaultTextStyle.of(context).style.color ?? ShadTheme.of(context).colorScheme.foreground;
    final baseFontSize = MediaQuery.of(context).textScaler.scale((DefaultTextStyle.of(context).style.fontSize ?? 14));

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
          Padding(
            padding: EdgeInsets.only(top: 10),
            child: ShadCard(
              width: double.infinity,
              padding: EdgeInsets.all(10),
              description: Text((attachment as MeshElement).getAttribute("filename")),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.document;
    final threadMessages = thread.root.getChildren().whereType<MeshElement>().where((x) => x.tagName == "messages").firstOrNull;

    bool bottomAlign = !widget.startChatCentered || (threadMessages?.getChildren() ?? []).isNotEmpty;
    return Column(
      mainAxisAlignment: bottomAlign ? MainAxisAlignment.end : MainAxisAlignment.center,
      children: [
        Expanded(
          child: ListView(
            reverse: true,
            padding: EdgeInsets.all(16),
            children: [for (final message in (threadMessages?.getChildren() ?? []).reversed) buildMessage(context, message as MeshElement)],
          ),
        ),
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
        for (final attachment in attachments)
          Padding(
            padding: EdgeInsets.all(10),
            child: ShadCard(
              padding: EdgeInsets.only(left: 15),
              width: double.infinity,
              description: Row(
                children: [
                  Expanded(child: Text(attachment.json['filename'])),
                  ShadIconButton.ghost(
                    onPressed: () {
                      setState(() {
                        attachments.remove(attachment);
                      });
                    },
                    icon: Icon(LucideIcons.x),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) => ShadInput(
              inputPadding: EdgeInsets.all(2),
              leading: ShadTooltip(
                waitDuration: Duration(seconds: 1),
                builder: (context) => Text("Attach"),
                child: ShadGestureDetector(
                  cursor: SystemMouseCursors.click,
                  onTap: () async {
                    final response = await widget.room.agents.invokeTool(
                      toolkit: "meshagent.markitdown",
                      tool: "markitdown_from_user",
                      arguments: {"title": "Attach a file", "description": "You can select PDFs or Office Docs"},
                    );

                    if (!mounted) {
                      return;
                    }
                    if (response is JsonResponse) {
                      setState(() {
                        attachments.add(response);
                      });
                    }
                  },
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: ShadTheme.of(context).colorScheme.foreground),
                    child: Icon(LucideIcons.paperclip, color: ShadTheme.of(context).colorScheme.background),
                  ),
                ),
              ),
              trailing: showSend
                  ? ShadTooltip(
                      waitDuration: Duration(seconds: 1),
                      builder: (context) => Text("Send"),
                      child: ShadGestureDetector(
                        cursor: SystemMouseCursors.click,
                        onTap: () {
                          send();
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
              onChanged: (value) {
                if (!value.isEmpty != showSend) {
                  setState(() {
                    showSend = !value.isEmpty;
                  });
                }

                for (final part in getOnlineParticipants()) {
                  widget.room.messaging.sendMessage(to: part, type: "typing", message: {"path": widget.path});
                }
              },

              maxLines: null,
              placeholder: Text("Message"),
              focusNode: focusNode,
              //textInputAction: TextInputAction.newline,
              controller: controller,
            ),
          ),
        ),
      ],
    );
  }

  late final focusNode = FocusNode(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
        send();
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    },
  );

  @override
  void dispose() {
    super.dispose();
    focusNode.dispose();
    controller.dispose();
    sub.cancel();
    widget.document.removeListener(onDocumentChanged);
  }
}

class JoinMeetingButton extends StatelessWidget {
  const JoinMeetingButton({super.key, required this.controller});

  final MeetingController controller;

  @override
  Widget build(BuildContext context) {
    return ShadButton.outline(
      leading: Icon(LucideIcons.mic),
      enabled: controller.room.connectionState == livekit.ConnectionState.disconnected,
      onPressed: () async {
        await controller.connect(livekit.FastConnectOptions(microphone: livekit.TrackOption(enabled: true)));
      },
      child: Text("Voice"),
    );
  }
}
