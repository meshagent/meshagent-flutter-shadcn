import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

bool get _shouldUseMeetingWakeLock => !kIsWeb || kReleaseMode;

class WakeLocker extends StatefulWidget {
  const WakeLocker({super.key, required this.child});

  final Widget child;

  @override
  State createState() => _WakeLocker();
}

class _WakeLocker extends State<WakeLocker> {
  static int refCount = 0;

  @override
  void initState() {
    super.initState();
    refCount++;
    if (_shouldUseMeetingWakeLock && refCount == 1) {
      WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    refCount--;
    if (_shouldUseMeetingWakeLock && refCount == 0) {
      WakelockPlus.disable();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
