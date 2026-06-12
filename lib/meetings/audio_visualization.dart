import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:siri_wave/siri_wave.dart';

enum AudioWaveStyle { legacy, ribbon }

class AudioWave extends StatefulWidget {
  const AudioWave({
    required this.room,
    required this.participant,
    super.key,
    this.alignment = Alignment.center,
    this.backgroundColor = const Color.from(alpha: 1, red: 1, green: 1, blue: 1),
    this.speakingColor = const Color.from(alpha: .2, red: 0, green: 0, blue: 0),
    this.notSpeakingColor = const Color.from(alpha: 1, red: 0, green: 0, blue: 0),
    this.style = AudioWaveStyle.ribbon,
  });

  final Room room;
  final Participant participant;
  final Alignment alignment;
  final Color backgroundColor;
  final Color speakingColor;
  final Color notSpeakingColor;
  final AudioWaveStyle style;

  @override
  State createState() => _AudioWaveState();
}

class _AudioWaveState extends State<AudioWave> {
  late final IOS7SiriWaveformController _legacyController;

  @override
  void initState() {
    super.initState();

    _legacyController = IOS7SiriWaveformController()
      ..amplitude = 1.0
      ..color = widget.backgroundColor;

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
        thinking = widget.participant.attributes["lk.agent.state"] == "thinking";

        listening = widget.participant.attributes["busy"] != "true";

        if (widget.style == AudioWaveStyle.legacy) {
          if (!widget.participant.isSpeaking) {
            _legacyController
              ..amplitude = .2
              ..speed = 0.05
              ..frequency = 1
              ..color = widget.speakingColor;
          } else {
            _legacyController
              ..amplitude = audioLevel
              ..frequency = 6
              ..speed = 0.2
              ..color = widget.notSpeakingColor;
          }
        }
      });
    }
  }

  bool hasReceivedLevels = false;
  double _visualLevel = 0;
  double _phase = 0;

  void onTick(Timer t) async {
    _phase += thinking ? 0.025 : 0.055;

    final track = widget.participant.audioTrackPublications.where((x) => !x.muted).firstOrNull?.track;

    final receiver = (track as AudioTrack?)?.receiver;

    final stats = await receiver?.getStats();
    if (stats != null) {
      statsReport = stats;
      for (var stat in stats) {
        if (stat.type == "inbound-rtp") {
          final levels = stat.values["audioLevel"];
          if (levels != null) {
            if (!thinking) {
              audioLevel = (levels as num).toDouble();
            }
            if (widget.style == AudioWaveStyle.legacy) {
              _legacyController.amplitude = audioLevel;
            }
            hasReceivedLevels = true;
          }
        }
      }
    }

    if (!mounted) {
      return;
    }

    final targetLevel = thinking ? 0.18 : (widget.participant.isSpeaking ? math.max(audioLevel, 0.28) : 0.1);
    setState(() {
      _visualLevel += (targetLevel - _visualLevel) * 0.18;
    });
  }

  double audioLevel = 0;
  List<StatsReport>? statsReport;
  bool thinking = true;

  late Timer timer;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: 800),
      decoration: BoxDecoration(color: widget.backgroundColor),
      child: Opacity(
        opacity: hasReceivedLevels ? 1 : 0.1,
        child: widget.style == AudioWaveStyle.legacy
            ? SiriWaveform.ios7(controller: _legacyController)
            : CustomPaint(
                painter: _AudioRibbonPainter(
                  level: _visualLevel,
                  phase: _phase,
                  speaking: widget.participant.isSpeaking,
                  thinking: thinking,
                  primaryColor: widget.notSpeakingColor,
                  secondaryColor: widget.speakingColor,
                ),
                child: const SizedBox.expand(),
              ),
      ),
    );
  }
}

class _AudioRibbonPainter extends CustomPainter {
  const _AudioRibbonPainter({
    required this.level,
    required this.phase,
    required this.speaking,
    required this.thinking,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final double level;
  final double phase;
  final bool speaking;
  final bool thinking;
  final Color primaryColor;
  final Color secondaryColor;

  static const _blue = Color(0xFF1FB7FF);
  static const _cyan = Color(0xFF22D3EE);
  static const _violet = Color(0xFF635BFF);
  static const _teal = Color(0xFF20D6A2);
  static const _mint = Color(0xFF8CEED7);
  static const _lavender = Color(0xFFDBD7FF);
  static const _ice = Color(0xFFE8FBFF);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final rect = Offset.zero & size;
    final height = size.height;
    final resolvedLevel = level.clamp(0.05, 1.0);
    final energy = speaking
        ? 1.0
        : thinking
        ? 0.72
        : 0.42;
    final baseAmplitude = height * (0.12 + resolvedLevel * 0.30) * energy;

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(24, height * 0.20)
      ..color = _cyan.withValues(alpha: speaking ? 0.14 : 0.07)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawPath(_centerPath(size: size, amplitude: baseAmplitude * 0.52, phaseOffset: 0), glowPaint);

    final rearPath = _ribbonPath(
      size: size,
      amplitude: baseAmplitude * 0.96,
      phaseOffset: math.pi * 0.62,
      thickness: height * (0.10 + resolvedLevel * 0.09),
    );
    final rearPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Color.lerp(_mint, secondaryColor, 0.16)!.withValues(alpha: 0.14),
          Color.lerp(_teal, secondaryColor, 0.20)!.withValues(alpha: 0.44),
          Color.lerp(_cyan, secondaryColor, 0.12)!.withValues(alpha: 0.38),
          Color.lerp(_mint, secondaryColor, 0.16)!.withValues(alpha: 0.14),
        ],
        stops: const [0, 0.22, 0.78, 1],
      ).createShader(rect);
    canvas.drawPath(rearPath, rearPaint);

    final frontPath = _ribbonPath(size: size, amplitude: baseAmplitude, phaseOffset: 0, thickness: height * (0.13 + resolvedLevel * 0.16));
    final frontPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Color.lerp(_ice, primaryColor, 0.34)!.withValues(alpha: 0.26),
          Color.lerp(_cyan, primaryColor, 0.10)!.withValues(alpha: 0.78),
          Color.lerp(_blue, primaryColor, 0.18)!.withValues(alpha: 0.82),
          Color.lerp(_violet, primaryColor, 0.18)!.withValues(alpha: 0.72),
          Color.lerp(_cyan, primaryColor, 0.06)!.withValues(alpha: 0.74),
          Color.lerp(_ice, primaryColor, 0.32)!.withValues(alpha: 0.26),
        ],
        stops: const [0, 0.12, 0.38, 0.58, 0.84, 1],
      ).createShader(rect);
    canvas.drawPath(frontPath, frontPaint);

    final centerBlendPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(12, height * 0.08)
      ..shader = LinearGradient(
        colors: [
          _ice.withValues(alpha: 0.10),
          _lavender.withValues(alpha: speaking ? 0.32 : 0.20),
          Colors.white.withValues(alpha: speaking ? 0.52 : 0.34),
          _lavender.withValues(alpha: speaking ? 0.26 : 0.16),
          _ice.withValues(alpha: 0.10),
        ],
        stops: const [0, 0.22, 0.48, 0.78, 1],
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(_centerPath(size: size, amplitude: baseAmplitude * 0.36, phaseOffset: math.pi * 0.18), centerBlendPaint);

    final highlightPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: speaking ? 0.12 : 0.06),
          Colors.white.withValues(alpha: speaking ? 0.36 : 0.18),
          Colors.white.withValues(alpha: speaking ? 0.12 : 0.06),
        ],
        stops: const [0.08, 0.42, 0.92],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.5, height * 0.018);
    canvas.drawPath(_centerPath(size: size, amplitude: baseAmplitude * 0.78, phaseOffset: 0), highlightPaint);
  }

  Path _centerPath({required Size size, required double amplitude, required double phaseOffset}) {
    final path = Path();
    final samples = math.max(36, (size.width / 10).round());
    for (var i = 0; i <= samples; i++) {
      final progress = i / samples;
      final x = progress * size.width;
      final envelope = math.sin(math.pi * progress).clamp(0.0, 1.0);
      final wave =
          math.sin(progress * math.pi * 5.0 + phase + phaseOffset) * 0.62 +
          math.sin(progress * math.pi * 11.0 - phase * 1.35 + phaseOffset) * 0.38;
      final y = size.height / 2 + wave * amplitude * envelope;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  Path _ribbonPath({required Size size, required double amplitude, required double phaseOffset, required double thickness}) {
    final upper = <Offset>[];
    final lower = <Offset>[];
    final samples = math.max(44, (size.width / 8).round());

    for (var i = 0; i <= samples; i++) {
      final progress = i / samples;
      final x = progress * size.width;
      final envelope = math.sin(math.pi * progress).clamp(0.0, 1.0);
      final taper = math.pow(envelope, 1.42).toDouble();
      final localThickness = thickness * taper * (0.70 + level * 0.30);
      final wave =
          math.sin(progress * math.pi * 4.6 + phase + phaseOffset) * 0.58 +
          math.sin(progress * math.pi * 10.4 - phase * 1.18 + phaseOffset) * 0.42;
      final y = size.height / 2 + wave * amplitude * envelope;
      upper.add(Offset(x, y - localThickness));
      lower.add(Offset(x, y + localThickness));
    }

    final path = Path()..moveTo(upper.first.dx, upper.first.dy);
    for (final point in upper.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    for (final point in lower.reversed) {
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _AudioRibbonPainter oldDelegate) {
    return oldDelegate.level != level ||
        oldDelegate.phase != phase ||
        oldDelegate.speaking != speaking ||
        oldDelegate.thinking != thinking ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
