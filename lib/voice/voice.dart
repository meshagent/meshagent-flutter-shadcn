import 'package:flutter/material.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/meetings/audio_visualization.dart';
import 'package:meshagent_flutter_shadcn/meetings/meetings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

class VoiceAgentCaller extends StatefulWidget {
  const VoiceAgentCaller({
    super.key,
    required this.meeting,
    required this.participant,
    this.getBreakoutRoom,
    this.transcribe = false,
    this.allowToggleTranscribe = true,
  });

  final RemoteParticipant participant;
  final MeetingController meeting;

  final Future<String?> Function(BuildContext)? getBreakoutRoom;

  final bool transcribe;
  final bool allowToggleTranscribe;

  @override
  State createState() => _VoiceAgentCaller();
}

class _VoiceAgentCaller extends State<VoiceAgentCaller> {
  late bool transcribe = widget.transcribe;

  @override
  Widget build(BuildContext context) {
    final meeting = widget.meeting;
    final getBreakoutRoom = widget.getBreakoutRoom;
    final participant = widget.participant;
    final allowToggleTranscribe = widget.allowToggleTranscribe;

    return Center(
      child: ListenableBuilder(
        listenable: meeting,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            if (meeting.livekitRoom.connectionState == livekit.ConnectionState.disconnected) ...[
              ShadButton(
                onPressed: () async {
                  final breakout = getBreakoutRoom != null ? await getBreakoutRoom(context) : const Uuid().v4();
                  if (breakout == null) {
                    return;
                  }
                  await meeting.configure(breakoutRoom: breakout);
                  await meeting.connect(livekit.FastConnectOptions(microphone: livekit.TrackOption(enabled: true)));
                  await meeting.room.messaging.sendMessage(
                    to: participant,
                    type: "voice_call",
                    message: {
                      "breakout_room": breakout,
                      if (transcribe)
                        "transcript_path":
                            "transcripts/${participant.getAttribute("name")}/${meeting.room.localParticipant!.getAttribute("name")}/${DateTime.now().toIso8601String()}.transcript",
                    },
                  );
                },
                child: Text("Start Voice Session"),
              ),
              if (allowToggleTranscribe)
                ShadCheckbox(
                  onChanged: (value) {
                    setState(() {
                      transcribe = value;
                    });
                  },
                  label: Text("Transcribe", style: ShadTheme.of(context).textTheme.small),
                  value: transcribe,
                ),
            ],
            if (meeting.livekitRoom.connectionState != livekit.ConnectionState.disconnected) ...[
              ListenableBuilder(
                listenable: meeting.livekitRoom,
                builder: (c, _) {
                  final participant = meeting.livekitRoom.remoteParticipants.values.firstOrNull;
                  return participant == null
                      ? Container(constraints: BoxConstraints(maxWidth: 800), child: AspectRatio(aspectRatio: 1.25))
                      : Padding(
                          padding: EdgeInsets.all(30),
                          child: AspectRatio(
                            aspectRatio: 1.25,
                            child: AudioWave(
                              room: meeting.livekitRoom,
                              participant: participant,
                              backgroundColor: ShadTheme.of(context).colorScheme.background,
                              speakingColor: Colors.green,
                              notSpeakingColor: Colors.green.withAlpha(50),
                            ),
                          ),
                        );
                },
              ),
              if (meeting.livekitRoom.connectionState == livekit.ConnectionState.connected) MeetingControls(controller: meeting),
            ],
          ],
        ),
      ),
    );
  }
}
