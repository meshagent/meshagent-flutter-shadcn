import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const String roomClientTimeoutAnnotation = 'meshagent.client.timeout';
const Duration defaultRoomClientIdleTimeout = Duration(minutes: 60);
const Duration defaultRoomClientIdleWarningDuration = Duration(seconds: 30);

Duration roomClientIdleTimeoutFromAnnotations(Map<String, String> annotations) {
  final rawMinutes = annotations[roomClientTimeoutAnnotation]?.trim();
  if (rawMinutes == null || rawMinutes.isEmpty) {
    return defaultRoomClientIdleTimeout;
  }

  final minutes = double.tryParse(rawMinutes);
  if (minutes == null || !minutes.isFinite || minutes <= 0) {
    return defaultRoomClientIdleTimeout;
  }

  return Duration(microseconds: (minutes * Duration.microsecondsPerMinute).round());
}

class RoomIdleDisconnectGuard extends StatefulWidget {
  const RoomIdleDisconnectGuard({
    super.key,
    required this.idleTimeout,
    required this.isMeetingActive,
    required this.onIdleDisconnect,
    required this.child,
    this.warningDuration = defaultRoomClientIdleWarningDuration,
    this.checkInterval = const Duration(seconds: 1),
    this.clock,
  });

  final Duration idleTimeout;
  final Duration warningDuration;
  final Duration checkInterval;
  final DateTime Function()? clock;
  final bool Function() isMeetingActive;
  final VoidCallback onIdleDisconnect;
  final Widget child;

  @override
  State<RoomIdleDisconnectGuard> createState() => _RoomIdleDisconnectGuardState();
}

class _RoomIdleDisconnectGuardState extends State<RoomIdleDisconnectGuard> {
  late DateTime _lastActivity;
  DateTime? _warningStartedAt;
  Timer? _timer;
  bool _disconnected = false;

  @override
  void initState() {
    super.initState();
    _lastActivity = _now();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant RoomIdleDisconnectGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.idleTimeout != widget.idleTimeout ||
        oldWidget.warningDuration != widget.warningDuration ||
        oldWidget.checkInterval != widget.checkInterval) {
      _recordActivity();
      _startTimer();
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    _recordActivity();
    return false;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.checkInterval, (_) => _checkIdle());
  }

  void _recordActivity() {
    if (_disconnected) return;
    _lastActivity = _now();
    _cancelWarning();
  }

  void _cancelWarning() {
    if (_warningStartedAt == null) return;
    _warningStartedAt = null;
    if (mounted) {
      unawaited(ShadToaster.of(context).hide());
    }
  }

  void _checkIdle() {
    if (!mounted || _disconnected) return;

    if (widget.isMeetingActive()) {
      _cancelWarning();
      return;
    }

    final now = _now();
    final idleFor = now.difference(_lastActivity);
    final warningThreshold = widget.idleTimeout > widget.warningDuration ? widget.idleTimeout - widget.warningDuration : Duration.zero;
    if (idleFor < warningThreshold) {
      _cancelWarning();
      return;
    }

    final warningStartedAt = _warningStartedAt;
    if (warningStartedAt == null) {
      _warningStartedAt = now;
      final warningSeconds = widget.warningDuration.inSeconds;
      ShadToaster.of(context).show(
        ShadToast(
          title: const Text('Room inactive'),
          description: Text('This room will be shut down in $warningSeconds seconds due to inactivity.'),
          duration: widget.warningDuration,
          action: ShadButton.outline(onPressed: _recordActivity, child: const Text('Stay connected')),
        ),
      );
      return;
    }

    if (now.difference(warningStartedAt) < widget.warningDuration) {
      return;
    }

    _disconnected = true;
    _timer?.cancel();
    widget.onIdleDisconnect();
  }

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _recordActivity(),
      onHover: (_) => _recordActivity(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _recordActivity(),
        onPointerMove: (_) => _recordActivity(),
        onPointerUp: (_) => _recordActivity(),
        onPointerSignal: (_) => _recordActivity(),
        child: widget.child,
      ),
    );
  }
}
