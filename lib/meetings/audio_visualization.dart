import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:siri_wave/siri_wave.dart';

class AudioWave extends StatefulWidget {
  const AudioWave({
    required this.room,
    required this.participant,
    super.key,
    this.alignment = Alignment.center,
    this.backgroundColor = const Color.from(
      alpha: 1,
      red: 1,
      green: 1,
      blue: 1,
    ),
  });

  final Room room;
  final Participant participant;
  final Alignment alignment;
  final Color backgroundColor;

  @override
  State createState() => _AudioWaveState();
}

class _AudioWaveState extends State<AudioWave> {
  @override
  void initState() {
    super.initState();

    controller = IOS7SiriWaveformController();
    controller.amplitude = 1.0;
    controller.color = widget.backgroundColor;

    timer = Timer.periodic(const Duration(milliseconds: 1000 ~/ 30), onTick);

    //widget.participant.addListener(onParticipantChange);
    //widget.participant.events.listen(onParticipantEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onParticipantUpdated();
      });
    });

    widget.participant.addListener(onParticipantUpdated);
  }

  @override
  void dispose() {
    super.dispose();

    widget.participant.removeListener(onParticipantUpdated);
    timer.cancel();
  }

  late StreamSubscription sub;
  bool listening = false;

  void onParticipantUpdated() {
    if (mounted) {
      setState(() {
        thinking =
            widget.participant.attributes["lk.agent.state"] == "thinking";

        listening = widget.participant.attributes["busy"] != "true";

        if (!widget.participant.isSpeaking) {
          controller.amplitude = .2;
          controller.speed = 0.05;
          controller.frequency = 1;
          controller.color = Color.from(alpha: .2, red: 0, green: 0, blue: 0);
        } else {
          controller.amplitude = audioLevel;
          controller.frequency = 6;
          controller.speed = 0.2;
          controller.color = Color.from(alpha: 1, red: 0, green: 0, blue: 0);
        }
      });
    }
  }

  bool hasReceivedLevels = false;
  late IOS7SiriWaveformController controller;

  void onTick(Timer t) async {
    final track =
        widget.participant.audioTrackPublications
            .where((x) => !x.muted)
            .firstOrNull
            ?.track;

    final receiver = (track as AudioTrack?)?.receiver;

    final stats = await receiver?.getStats();
    if (stats != null) {
      statsReport = stats;
      for (var stat in stats) {
        if (stat.type == "inbound-rtp") {
          final levels = stat.values["audioLevel"];
          if (levels != null) {
            if (mounted) {
              setState(() {
                if (!thinking) {
                  audioLevel = (levels as num).toDouble();
                  controller.amplitude = audioLevel;
                }
                hasReceivedLevels = true;
              });
            }
          }
        }
      }
    }
  }

  double audioLevel = 0;
  List<StatsReport>? statsReport;
  bool thinking = true;

  late Timer timer;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: 800),
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        //gradient: RadialGradient(
        //    colors: [filledButtonColor, darken(filledButtonColor, 20)]),
        //borderRadius: BorderRadius.circular(10),
      ),
      child: Opacity(
        opacity: hasReceivedLevels ? 1 : 0.1,
        child: SiriWaveform.ios7(controller: controller),
      ),
    );
  }
}
