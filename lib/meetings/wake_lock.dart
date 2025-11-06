import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
    if (refCount == 1) {
      WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    refCount--;
    if (refCount == 0) {
      WakelockPlus.disable();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
