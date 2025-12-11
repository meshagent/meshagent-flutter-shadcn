import 'package:flutter/material.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/meetings/audio_visualization.dart';
import 'package:meshagent_flutter_shadcn/meetings/meetings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

class VoiceAgentCaller extends StatelessWidget {
  const VoiceAgentCaller({super.key, required this.meeting, required this.participant, this.getBreakoutRoom});

  final RemoteParticipant participant;
  final MeetingController meeting;

  final Future<String?> Function(BuildContext)? getBreakoutRoom;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ListenableBuilder(
        listenable: meeting,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (meeting.livekitRoom.connectionState == livekit.ConnectionState.disconnected)
              ShadButton.outline(
                onPressed: () async {
                  final breakout = getBreakoutRoom != null ? await getBreakoutRoom!(context) : const Uuid().v4();
                  if (breakout == null) {
                    return;
                  }
                  await meeting.configure(breakoutRoom: breakout);
                  await meeting.connect(livekit.FastConnectOptions(microphone: livekit.TrackOption(enabled: true)));
                  await meeting.room.messaging.sendMessage(to: participant, type: "voice_call", message: {"breakout_room": breakout});
                },
                child: Text("Start Voice Session"),
              ),
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
