import 'package:shadcn_ui/shadcn_ui.dart';

import '../meetings/audio_visualization.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:webrtc_interface/webrtc_interface.dart';
import './meetings.dart';

class ParticipantCamerasList extends StatefulWidget {
  ParticipantCamerasList({required this.controller, this.padding = EdgeInsets.zero, this.spacing = 10, super.key});

  final double spacing;
  final EdgeInsets padding;
  final MeetingController controller;

  @override
  State createState() => _ParticipantCamerasListState();
}

class _ParticipantCamerasListState extends State<ParticipantCamerasList> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: widget.controller.room,
      builder: (context, _) => ListView(
        padding: widget.padding,
        scrollDirection: Axis.horizontal,
        children: [
          if (controller.room.localParticipant != null)
            ParticipantTile(room: controller.room, participant: controller.room.localParticipant!),
          SizedBox(width: widget.spacing),
          ...controller.room.remoteParticipants.values.map(
            (participant) => Padding(
              padding: EdgeInsets.only(right: widget.spacing),
              child: ParticipantTile(room: controller.room, participant: participant),
            ),
          ),
        ],
      ),
    );
  }
}

class ParticipantTile extends StatelessWidget {
  ParticipantTile({super.key, required this.room, required this.participant});

  final Room room;
  final Participant participant;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: participant,
      builder: (context, _) {
        final track = participant.trackPublications.values.map((x) => x.track).whereType<VideoTrack>().firstOrNull;
        return AspectRatio(
          aspectRatio: 4 / 3,
          child: _CameraBox(
            muted: participant.isMuted,
            camera: track != null
                ? VideoTrackRenderer(track, fit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : (participant.kind == ParticipantKind.AGENT
                    ? AudioWave(room: room, participant: participant)
                    : ColoredBox(color: ShadTheme.of(context).colorScheme.foreground)),
            participantName: participant.name,
          ),
        );
      },
    );
  }
}

class _ParticipantOverlay extends StatefulWidget {
  const _ParticipantOverlay({required this.name, required this.muted, this.showName = true});

  final String name;
  final bool muted;
  final bool showName;

  @override
  _ParticipantOverlayState createState() => _ParticipantOverlayState();
}

class _ParticipantOverlayState extends State<_ParticipantOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    const begin = 0.0;
    const end = 1.0;

    _animationController = AnimationController(
      value: widget.showName ? end : begin,
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _animation = CurvedAnimation(parent: _animationController, curve: Curves.easeOut);
  }

  @override
  void didUpdateWidget(covariant _ParticipantOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showName != oldWidget.showName) {
      widget.showName ? _animationController.forward() : _animationController.reverse();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const audioIconSize = 16.0;
    const audioIconColor = Colors.white;
    const textStyle = TextStyle(color: audioIconColor, fontSize: 11, fontWeight: FontWeight.w500);

    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0x992f2d57)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(widget.muted ? Icons.mic_off : Icons.mic, color: audioIconColor, size: audioIconSize),
          if (widget.name.isNotEmpty)
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Flexible(
                  child: SizedBox(
                    height: audioIconSize,
                    child: ClipRect(child: Align(alignment: Alignment.centerLeft, widthFactor: _animation.value, child: child)),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 1, right: 3),
                child: Text(widget.name, style: textStyle, overflow: TextOverflow.ellipsis),
              ),
            ),
        ],
      ),
    );
  }
}

class _CameraBox extends StatelessWidget {
  const _CameraBox({required this.camera, required this.participantName, this.muted = false});

  final Widget camera;
  final String participantName;
  final bool muted;
  final bool showName = true;
  final Alignment overlayAlignment = Alignment.bottomLeft;
  final BoxDecoration decoration = const BoxDecoration(
    border: Border(
      top: BorderSide(color: Colors.white, width: 2.0),
      bottom: BorderSide(color: Colors.white, width: 2.0),
      left: BorderSide(color: Colors.white, width: 2.0),
      right: BorderSide(color: Colors.white, width: 2.0),
    ),
    borderRadius: BorderRadius.all(Radius.circular(8.0)),
    boxShadow: [BoxShadow(blurRadius: 5, color: Color.fromARGB(50, 0, 0, 0))],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: ClipRRect(
        borderRadius: decoration.borderRadius!,
        child: Stack(
          children: [
            camera,
            Align(
              alignment: overlayAlignment,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: IntrinsicWidth(child: _ParticipantOverlay(name: participantName, muted: muted, showName: showName)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
