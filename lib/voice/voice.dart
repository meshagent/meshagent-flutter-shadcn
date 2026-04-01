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
    this.showDisconnectedAction = true,
    this.emptyStateTitle = "Start an audio session",
    this.emptyStateDescription = "Connect with this agent using your microphone.",
    this.connectedControlsBuilder,
  });

  final RemoteParticipant participant;
  final MeetingController meeting;

  final Future<String?> Function(BuildContext)? getBreakoutRoom;
  final double? emptyStateAvailableWidth;

  final bool transcribe;
  final bool allowToggleTranscribe;
  final bool showDisconnectedAction;
  final String emptyStateTitle;
  final String emptyStateDescription;
  final Widget Function(BuildContext context, MeetingController meeting)? connectedControlsBuilder;

  @override
  State createState() => _VoiceAgentCaller();
}

class _VoiceAgentCaller extends State<VoiceAgentCaller> {
  static const double _horizontalControlsMinWidth = 520;
  static const double _mobilePrimaryButtonMaxWidth = 360;
  static const double _mobileScreenWidthMax = 600;
  static const double _connectedControlsReservedHeight = 150;
  static const double _compactConnectedControlsReservedHeight = 220;

  late bool transcribe = widget.transcribe;

  String _describeStartSessionError(Object error) {
    final message = '$error';
    if (message.contains('NotAllowedError')) {
      return 'Microphone access was blocked by the browser or system.';
    }
    if (message.contains('NotFoundError')) {
      return 'The selected microphone was not found.';
    }
    return 'Unable to start session: $message';
  }

  @override
  Widget build(BuildContext context) {
    final meeting = widget.meeting;
    final getBreakoutRoom = widget.getBreakoutRoom;
    final participant = widget.participant;
    final allowToggleTranscribe = widget.allowToggleTranscribe;
    final showDisconnectedAction = widget.showDisconnectedAction;
    final emptyStateTitle = widget.emptyStateTitle.trim();
    final emptyStateDescription = widget.emptyStateDescription.trim();
    final emptyStateAvailableWidth = widget.emptyStateAvailableWidth;
    final isMobileScreen = MediaQuery.sizeOf(context).width < _mobileScreenWidthMax;

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) => ListenableBuilder(
          listenable: meeting,
          builder: (context, _) {
            if (meeting.livekitRoom.connectionState == livekit.ConnectionState.disconnected) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 16,
                children: [
                  AudioAgentEmptyState(
                    title: emptyStateTitle,
                    description: emptyStateDescription,
                    availableWidth: emptyStateAvailableWidth ?? constraints.maxWidth,
                    action: !showDisconnectedAction
                        ? null
                        : LayoutBuilder(
                            builder: (context, controlsConstraints) {
                              final controlsAvailableWidth = emptyStateAvailableWidth ?? controlsConstraints.maxWidth;
                              final horizontalControls = allowToggleTranscribe && controlsAvailableWidth >= _horizontalControlsMinWidth;
                              final mobileButtonWidth = controlsAvailableWidth.clamp(220.0, _mobilePrimaryButtonMaxWidth).toDouble();

                              final startButton = ShadButton(
                                width: isMobileScreen && !horizontalControls ? mobileButtonWidth : null,
                                onPressed: () async {
                                  final toaster = ShadToaster.maybeOf(context);

                                  try {
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
                                  } catch (error) {
                                    toaster?.show(ShadToast.destructive(description: Text(_describeStartSessionError(error))));
                                  }
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
                  ),
                ],
              );
            }

            final controls = meeting.livekitRoom.connectionState == livekit.ConnectionState.connected
                ? (widget.connectedControlsBuilder?.call(context, meeting) ?? MeetingControls(controller: meeting))
                : null;

            final availableHeight = constraints.hasBoundedHeight ? constraints.maxHeight : 500.0;
            final reservedControlsHeight = controls == null
                ? 0.0
                : constraints.maxWidth < 420
                ? _compactConnectedControlsReservedHeight
                : _connectedControlsReservedHeight;
            final waveMaxHeight = (availableHeight - reservedControlsHeight).clamp(180.0, 360.0);

            return Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 16,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: waveMaxHeight),
                  child: ListenableBuilder(
                    listenable: meeting.livekitRoom,
                    builder: (c, _) {
                      final participant = meeting.livekitRoom.remoteParticipants.values.firstOrNull;
                      return participant == null
                          ? const SizedBox(width: 320, height: 180)
                          : Padding(
                              padding: const EdgeInsets.all(24),
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
                ),
                if (controls != null) controls,
              ],
            );
          },
        ),
      ),
    );
  }
}

class AudioAgentEmptyState extends StatelessWidget {
  const AudioAgentEmptyState({
    super.key,
    required this.title,
    required this.description,
    required this.availableWidth,
    this.action,
    this.verticalOffset = defaultVerticalOffset,
  });

  static const double defaultVerticalOffset = -40;
  static const double _contentMaxWidth = 640;
  static const double _horizontalPadding = 24;

  final String title;
  final String description;
  final double availableWidth;
  final Widget? action;
  final double verticalOffset;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, verticalOffset),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AudioAgentEmptyStateContent(title: title, description: description, availableWidth: availableWidth),
                if (action != null) ...[const SizedBox(height: 24), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AudioAgentEmptyStateContent extends StatelessWidget {
  const AudioAgentEmptyStateContent({super.key, required this.title, required this.description, required this.availableWidth});

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
