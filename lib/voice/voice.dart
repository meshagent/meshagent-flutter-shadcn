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
    this.emptyStateAvailableWidth,
    this.transcribe = false,
    this.allowToggleTranscribe = true,
    this.emptyStateTitle = "Start an audio session",
    this.emptyStateDescription = "Connect with this agent using your microphone.",
  });

  final RemoteParticipant participant;
  final MeetingController meeting;

  final Future<String?> Function(BuildContext)? getBreakoutRoom;
  final double? emptyStateAvailableWidth;

  final bool transcribe;
  final bool allowToggleTranscribe;
  final String emptyStateTitle;
  final String emptyStateDescription;

  @override
  State createState() => _VoiceAgentCaller();
}

class _VoiceAgentCaller extends State<VoiceAgentCaller> {
  static const double _disconnectedStateVerticalOffset = -40;
  static const double _horizontalControlsMinWidth = 520;
  static const double _mobilePrimaryButtonMaxWidth = 360;
  static const double _mobileScreenWidthMax = 600;

  late bool transcribe = widget.transcribe;

  @override
  Widget build(BuildContext context) {
    final meeting = widget.meeting;
    final getBreakoutRoom = widget.getBreakoutRoom;
    final participant = widget.participant;
    final allowToggleTranscribe = widget.allowToggleTranscribe;
    final emptyStateTitle = widget.emptyStateTitle.trim();
    final emptyStateDescription = widget.emptyStateDescription.trim();
    final emptyStateAvailableWidth = widget.emptyStateAvailableWidth;
    final isMobileScreen = MediaQuery.sizeOf(context).width < _mobileScreenWidthMax;

    return Center(
      child: ListenableBuilder(
        listenable: meeting,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            if (meeting.livekitRoom.connectionState == livekit.ConnectionState.disconnected) ...[
              LayoutBuilder(
                builder: (context, constraints) => Transform.translate(
                  offset: const Offset(0, _disconnectedStateVerticalOffset),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _VoiceEmptyStateContent(
                              title: emptyStateTitle,
                              description: emptyStateDescription,
                              availableWidth: emptyStateAvailableWidth ?? constraints.maxWidth,
                            ),
                            const SizedBox(height: 24),
                            LayoutBuilder(
                              builder: (context, controlsConstraints) {
                                final controlsAvailableWidth = emptyStateAvailableWidth ?? controlsConstraints.maxWidth;
                                final horizontalControls = allowToggleTranscribe && controlsAvailableWidth >= _horizontalControlsMinWidth;
                                final mobileButtonWidth = controlsAvailableWidth.clamp(220.0, _mobilePrimaryButtonMaxWidth).toDouble();

                                final startButton = ShadButton(
                                  width: isMobileScreen && !horizontalControls ? mobileButtonWidth : null,
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
                                  child: const Text("Start session"),
                                );

                                final transcribeCheckbox = ShadCheckbox(
                                  onChanged: (value) {
                                    setState(() {
                                      transcribe = value;
                                    });
                                  },
                                  label: Text("Transcribe", style: ShadTheme.of(context).textTheme.small),
                                  value: transcribe,
                                );

                                if (horizontalControls) {
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [startButton, const SizedBox(width: 32), transcribeCheckbox],
                                  );
                                }

                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    startButton,
                                    if (allowToggleTranscribe) ...[const SizedBox(height: 16), transcribeCheckbox],
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
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
                              backgroundColor: Colors.transparent,
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

class _VoiceEmptyStateContent extends StatelessWidget {
  const _VoiceEmptyStateContent({required this.title, required this.description, required this.availableWidth});

  static const double _descriptionVisibilityMinWidth = 480;
  static const double _mobileScreenWidthMax = 600;

  final String title;
  final String description;
  final double availableWidth;

  double _titleScale(double width) {
    if (width >= 820) {
      return 1;
    }
    if (width <= 440) {
      return 0.72;
    }
    return 0.72 + ((width - 440) / 380) * 0.28;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isMobileScreen = MediaQuery.sizeOf(context).width < _mobileScreenWidthMax;
    final scale = _titleScale(availableWidth);
    final titleStyle = theme.textTheme.h1;
    final titleFontSize = (titleStyle.fontSize ?? 64) * scale;
    final showDescription = description.isNotEmpty && (availableWidth >= _descriptionVisibilityMinWidth || isMobileScreen);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: titleStyle.copyWith(fontSize: titleFontSize),
          textAlign: TextAlign.center,
        ),
        if (showDescription) ...[const SizedBox(height: 8), Text(description, style: theme.textTheme.p, textAlign: TextAlign.center)],
      ],
    );
  }
}
