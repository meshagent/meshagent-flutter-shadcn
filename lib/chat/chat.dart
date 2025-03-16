import 'package:file_picker/file_picker.dart';
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

import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

// ignore: depend_on_referenced_packages

import "package:meshagent_flutter_shadcn/viewers/viewers.dart";

class MessagingPane extends StatefulWidget {
  MessagingPane({
    super.key,
    required this.projectId,
    required this.room,
    required this.meeting,
    required this.showParticipants,
    required this.showChat,
    required this.defaultAgent,
    required this.startChatCentered,
    required this.emptyParticipantsBuilder,
    required this.actionsBuilder,
  });

  final List<Widget> Function(BuildContext) actionsBuilder;
  final Widget Function(BuildContext)? emptyParticipantsBuilder;
  final bool startChatCentered;
  final String? defaultAgent;
  final bool showChat;
  final bool showParticipants;
  final String projectId;
  final RoomClient room;
  final MeetingController? meeting;

  @override
  State createState() => _MessagingPaneState();
}

class _MessagingPaneState extends State<MessagingPane> {
  final typing = Map<String, Timer>();
  final thinking = Set<String>();

  @override
  void initState() {
    super.initState();

    widget.room.messaging.enable();
    sub = widget.room.listen(onRoomMessage);
  }

  late StreamSubscription<RoomEvent> sub;

  String partial = "";

  void onRoomMessage(RoomEvent event) {
    if (!mounted) {
      return;
    }

    if (event is RoomMessageEvent) {
      if (event.message.type == "openai.event") {
        if (event.message.message["type"] == "response.output_text.delta") {
          partial += event.message.message["delta"];
          if (!mounted) {
            return;
          }
        }
      } else if (event.message.type == "chat") {
        addMessage(event.message.fromParticipantId, event.message);
      } else if (event.message.type == "typing") {
        typing[event.message.fromParticipantId]?.cancel();
        typing[event.message.fromParticipantId] = Timer(
          Duration(seconds: 1),
          () {
            typing.remove(event.message.fromParticipantId);
            if (mounted) {
              setState(() {});
            }
          },
        );
        if (mounted) {
          setState(() {});
        }
      } else if (event.message.type == "thinking") {
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
    if (event.name == "room.connect" || event.name == "room.disconnect") {
      if (!widget.room.messaging.remoteParticipants.contains(
        selectedParticipant,
      )) {
        selectedParticipant = null;
      }
      if (mounted) {
        setState(() {});
      }
    }

    final agents = widget.room.messaging.remoteParticipants
        .where((p) => p.role == "agent")
        .toList();
    if (selectedParticipant == null && agents.isNotEmpty) {
      if (widget.defaultAgent == null) {
        selectedParticipant = agents.first;
      } else {
        selectedParticipant = agents
            .where(
              (a) => a.getAttribute("name") == widget.defaultAgent,
            )
            .firstOrNull;
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  void addMessage(String threadId, RoomMessage message) {
    if (!mounted) return;
    setState(() {
      if (messages[threadId] == null) {
        messages[threadId] = [];
      }
      if (unreadMessages[threadId] == null) {
        unreadMessages[threadId] = 0;
      }
      if (selectedParticipant?.id != threadId) {
        unreadMessages[threadId] = unreadMessages[threadId]! + 1;
        if (selectedParticipant == null) {
          selectedParticipant = widget.room.messaging.remoteParticipants
              .where((x) => x.id == threadId)
              .firstOrNull;
        }
      }

      messages[threadId]!.insert(0, message);
    });
  }

  @override
  void dispose() {
    widget.room.messaging.disable();
    super.dispose();

    focusNode.dispose();
    controller.dispose();

    sub.cancel();
  }

  Widget participantEntry(BuildContext context, Participant participant) {
    final me = widget.room.localParticipant!.id == participant.id;
    final name = me
        ? "${participant.getAttribute("name")} (me)"
        : participant.getAttribute("name");
    final color =
        me ? Colors.green : ShadTheme.of(context).colorScheme.foreground;
    final icon =
        (participant is RemoteParticipant && participant.role == "agent")
            ? Icon(LucideIcons.bot, color: color)
            : Icon(LucideIcons.user, color: color);
    List<Widget> prefix = [];

    if (unreadMessages[participant.id] != null &&
        unreadMessages[participant.id] != 0) {
      prefix.add(
        Container(
          width: 16,
          height: 16,
          alignment: Alignment.center,
          margin: EdgeInsets.only(right: 10),
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red),
          child: Text(
            "${unreadMessages[participant.id]}",
            style: TextStyle(
              color: ShadTheme.of(context).colorScheme.background,
              fontSize: 12,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
      );
    } else {}

    return ShadContextMenuRegion(
      items: [
        ShadContextMenuItem(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: participant.id));
          },
          child: Text("Copy Participant ID"),
        ),
        ShadContextMenuItem(
          onPressed: () {
            widget.room.messaging.sendMessage(
              to: participant,
              type: "dismiss",
              message: {},
            );
            setState(() {
              selectedParticipant = null;
            });
          },
          child: Text("Dismiss"),
        ),
      ],
      child: Row(
        children: [
          Expanded(
            child: selectedParticipant?.id == participant.id
                ? ShadButton.secondary(
                    mainAxisAlignment: MainAxisAlignment.start,
                    child: Expanded(
                      child: Row(
                        children: [
                          ...prefix,
                          Expanded(
                            child: Text(
                              name,
                              textAlign: TextAlign.left,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: me ? color : null),
                            ),
                          ),
                          icon,
                        ],
                      ),
                    ),
                  )
                : ShadButton.ghost(
                    onTapDown: (_) {
                      setState(() {
                        selectedParticipant = participant;
                        if (unreadMessages[participant.id] != null) {
                          unreadMessages[participant.id] = 0;
                        }
                      });
                    },
                    mainAxisAlignment: MainAxisAlignment.start,
                    child: Expanded(
                      child: Row(
                        children: [
                          ...prefix,
                          Expanded(
                            child: Text(
                              name,
                              textAlign: TextAlign.left,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: me ? color : null),
                            ),
                          ),
                          icon,
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  final unreadMessages = <String, int>{};
  final messages = <String, List<RoomMessage>>{};

  Participant? _selectedParticipant;
  Participant? get selectedParticipant {
    return _selectedParticipant;
  }

  Future<MeshDocument>? threadFuture;

  String? threadId;

  set selectedParticipant(Participant? participant) {
    _selectedParticipant = participant;
    if (participant != null) {
      thread = null;

      final newThreadId =
          "${participant.getAttribute("name")}-${widget.room.localParticipant!.getAttribute("name")}";

      if (threadId == newThreadId) {
        return;
      }

      if (threadId != null) {
        widget.room.sync.close(".threads/${threadId}.thread");
      }

      thread = null;
      threadError = null;
      threadId = newThreadId;

      threadFuture = widget.room.sync.open(".threads/${threadId}.thread");

      threadFuture!.then((doc) {
        if (threadId != newThreadId) {
          return;
        }
        setState(() {
          thread = doc;
        });

        thread!.addListener(() {
          if (!mounted) return;
          setState(() {});
        });

        widget.room.messaging.sendMessage(
          to: participant,
          type: "opened",
          message: {"thread_id": newThreadId},
        );
      }).catchError((err) {
        print(err);
        threadError = err;
      });
    }
  }

  Object? threadError;

  late final focusNode = FocusNode(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed) {
        send();
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    },
  );
  MeshDocument? thread;

  void send() async {
    if (controller.text.trim().isNotEmpty) {
      addMessage(
        selectedParticipant!.id,
        RoomMessage(
          local: true,
          fromParticipantId: widget.room.localParticipant!.id,
          type: "chat",
          message: {
            "text": controller.text,
            "attachments": attachments.map((a) => a.json).toList()
          },
        ),
      );

      final messages = thread!.root
          .getChildren()
          .whereType<MeshElement>()
          .firstWhere((x) => x.tagName == "messages");

      messages.createChildElement("message", {
        "id": const Uuid().v4().toString(),
        "text": controller.text,
        "created_at": DateTime.now().toUtc().toIso8601String(),
        "author_name": widget.room.localParticipant!.getAttribute("name"),
        "author_ref": null
      });

      widget.room.messaging.sendMessage(
        to: selectedParticipant!,
        type: "chat",
        message: {
          "thread_id": threadId,
          "text": controller.text,
          "attachments": attachments.map((a) => a.json).toList()
        },
      );

      attachments.clear();
      controller.text = "";
      setState(() {});
    }
  }

  final controller = ShadTextEditingController();

  Widget buildMessage(BuildContext context, MeshElement message) {
    bool mine = message.attributes["author_name"] ==
        widget.room.localParticipant!.getAttribute("name");
    final mdColor = ShadTheme.of(context).textTheme.p.color ??
        DefaultTextStyle.of(context).style.color ??
        ShadTheme.of(context).colorScheme.foreground;
    final baseFontSize = MediaQuery.of(
      context,
    ).textScaler.scale((DefaultTextStyle.of(context).style.fontSize ?? 14));

    return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            margin: EdgeInsets.only(
              top: 8,
              right: mine ? 0 : 50,
              left: mine ? 50 : 0,
            ),
            decoration: BoxDecoration(
              color:
                  ShadTheme.of(context).ghostButtonTheme.hoverBackgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.0)),
              child: MarkdownWidget(
                padding: const EdgeInsets.all(0),
                config: MarkdownConfig(
                  configs: [
                    HrConfig(color: mdColor),
                    H1Config(
                      style: TextStyle(
                        fontSize: baseFontSize * 2,
                        color: mdColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    H2Config(
                      style: TextStyle(
                        fontSize: baseFontSize * 1.8,
                        color: mdColor,
                        inherit: false,
                      ),
                    ),
                    H3Config(
                      style: TextStyle(
                        fontSize: baseFontSize * 1.6,
                        color: mdColor,
                        inherit: false,
                      ),
                    ),
                    H4Config(
                      style: TextStyle(
                        fontSize: baseFontSize * 1.4,
                        color: mdColor,
                        inherit: false,
                      ),
                    ),
                    H5Config(
                      style: TextStyle(
                        fontSize: baseFontSize * 1.2,
                        color: mdColor,
                        inherit: false,
                      ),
                    ),
                    H6Config(
                      style: TextStyle(
                        fontSize: baseFontSize * 1.0,
                        color: mdColor,
                        inherit: false,
                      ),
                    ),
                    PreConfig(
                      decoration: BoxDecoration(
                          color:
                              ShadTheme.of(context).cardTheme.backgroundColor),
                      textStyle: TextStyle(
                        fontSize: baseFontSize * 1.0,
                        color: mdColor,
                        inherit: false,
                      ),
                    ),
                    PConfig(
                      textStyle: TextStyle(
                        fontSize: baseFontSize * 1.0,
                        color: mdColor,
                        inherit: false,
                      ),
                    ),
                    CodeConfig(
                      style: GoogleFonts.sourceCodePro(
                        fontSize: baseFontSize * 1.0,
                        color: mdColor,
                      ),
                    ),
                    BlockquoteConfig(textColor: mdColor),
                    LinkConfig(
                        style: TextStyle(
                            color: ShadTheme.of(context)
                                .linkButtonTheme
                                .foregroundColor,
                            decoration: TextDecoration.underline)),
                    ListConfig(marker: (isOrdered, depth, index) {
                      return Padding(
                          padding: EdgeInsets.only(right: 5),
                          child: Text(
                            "${index + 1}.",
                            textAlign: TextAlign.right,
                          ));
                    }),
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
                    description: Text(
                        (attachment as MeshElement).getAttribute("filename"))))
        ]);
  }

  Widget buildParticipants(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(4),
      children: [
        if (widget.room.messaging.remoteParticipants.isEmpty &&
            widget.emptyParticipantsBuilder != null)
          widget.emptyParticipantsBuilder!(context),
        participantEntry(context, widget.room.localParticipant!),
        for (final participant in widget.room.messaging.remoteParticipants)
          participantEntry(context, participant),
      ],
    );
  }

  bool showSend = false;
  List<JsonResponse> attachments = [];

  Widget buildMessages(BuildContext context) {
    final threadMessages = thread?.root
        .getChildren()
        .whereType<MeshElement>()
        .where((x) => x.tagName == "messages")
        .firstOrNull;

    bool bottomAlign = widget.startChatCentered ||
        (messages[selectedParticipant?.id ?? ""] ?? []).isNotEmpty;
    return Column(
      mainAxisAlignment:
          bottomAlign ? MainAxisAlignment.end : MainAxisAlignment.center,
      children: [
        if (selectedParticipant == null)
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  widget.showParticipants
                      ? "Select a participant to send messages"
                      : "Waiting for a participant to join",
                  textAlign: TextAlign.center,
                  style: ShadTheme.of(context).textTheme.muted,
                ),
              ),
            ),
          ),
        if (selectedParticipant != null) ...[
          Expanded(
            child: threadError != null
                ? Center(
                    child: Text("Unable to load thread",
                        style: ShadTheme.of(context).textTheme.p))
                : thread == null
                    ? Center(child: CircularProgressIndicator())
                    : ListView(
                        reverse: true,
                        padding: EdgeInsets.all(16),
                        children: [
                          if (partial != "")
                            Text(
                              partial,
                              style: ShadTheme.of(context).textTheme.p,
                            ),
                          for (final message
                              in (threadMessages?.getChildren() ?? []).reversed)
                            buildMessage(context, message as MeshElement),
                        ],
                      ),
          ),
          if (!bottomAlign)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 20, horizontal: 50),
              child: Text(
                selectedParticipant?.getAttribute("empty_state_title") ??
                    "How can I help you?",
                style: ShadTheme.of(context).textTheme.h3,
              ),
            ),
          if (selectedParticipant != null &&
              (typing.containsKey(selectedParticipant?.id) == true ||
                  thinking.contains(selectedParticipant?.id)))
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
                    description: Row(children: [
                      Expanded(child: Text(attachment.json['filename'])),
                      ShadIconButton.ghost(
                          onPressed: () {
                            setState(() {
                              attachments.remove(attachment);
                            });
                          },
                          icon: Icon(LucideIcons.x))
                    ]))),
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
                          arguments: {
                            "title": "Attach a file",
                            "description": "You can select PDFs or Office Docs"
                          });

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
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ShadTheme.of(context).colorScheme.foreground,
                      ),
                      child: Icon(
                        LucideIcons.paperclip,
                        color: ShadTheme.of(
                          context,
                        ).colorScheme.background,
                      ),
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
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ShadTheme.of(
                                context,
                              ).colorScheme.foreground,
                            ),
                            child: Icon(
                              LucideIcons.arrowUp,
                              color: ShadTheme.of(
                                context,
                              ).colorScheme.background,
                            ),
                          ),
                        ),
                      )
                    : null,
                padding: EdgeInsets.only(
                  left: 5,
                  right: 5,
                  top: 5,
                  bottom: 5,
                ),
                decoration: ShadDecoration(
                  secondaryFocusedBorder: ShadBorder.none,
                  secondaryBorder: ShadBorder.none,
                  color: ShadTheme.of(
                    context,
                  ).ghostButtonTheme.hoverBackgroundColor,
                  border: ShadBorder.all(radius: BorderRadius.circular(30)),
                ),
                onChanged: (value) {
                  if (!value.isEmpty != showSend) {
                    setState(() {
                      showSend = !value.isEmpty;
                    });
                  }

                  final part = selectedParticipant;

                  if (part != null) {
                    widget.room.messaging.sendMessage(
                      to: part,
                      type: "typing",
                      message: {},
                    );
                  }
                },
                enabled: selectedParticipant is! RemoteParticipant ||
                    ((selectedParticipant as RemoteParticipant).role !=
                            "agent" ||
                        (selectedParticipant as RemoteParticipant)
                                .getAttribute("busy") !=
                            true),
                maxLines: null,
                placeholder: selectedParticipant is! RemoteParticipant ||
                        ((selectedParticipant as RemoteParticipant).role !=
                                "agent" ||
                            (selectedParticipant as RemoteParticipant)
                                    .getAttribute("busy") !=
                                true)
                    ? Text("Message")
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(),
                        ),
                      ),
                focusNode: focusNode,
                //textInputAction: TextInputAction.newline,
                controller: controller,
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showParticipants && !widget.showChat) {
      return buildParticipants(context);
    }
    if (!widget.showParticipants && widget.showChat) {
      return buildMessages(context);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 60,
          padding: EdgeInsets.only(left: 10, right: 10, top: 10),
          child: Row(
            children: [
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Messaging",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              ...widget.actionsBuilder(context)
            ],
          ),
        ),
        Expanded(
          child: ChangeNotifierBuilder(
            source: widget.room.messaging,
            builder: (context) => ShadResizablePanelGroup(
              axis: Axis.vertical,
              showHandle: true,
              dividerSize: 1,
              dividerThickness: 1,
              children: [
                ShadResizablePanel(
                  id: "participants",
                  minSize: 0,
                  defaultSize: .25,
                  child: buildParticipants(context),
                ),
                ShadResizablePanel(
                  id: "messages",
                  defaultSize: .75,
                  child: buildMessages(context),
                ),
              ],
            ),
          ),
        ),
      ],
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
      enabled: controller.room.connectionState ==
          livekit.ConnectionState.disconnected,
      onPressed: () async {
        await controller.connect(
          livekit.FastConnectOptions(
            microphone: livekit.TrackOption(enabled: true),
          ),
        );
      },
      child: Text("Voice"),
    );
  }
}
