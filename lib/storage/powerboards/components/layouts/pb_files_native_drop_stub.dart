import 'package:flutter/foundation.dart';

class PbNativeFilesDropBinding {
  PbNativeFilesDropBinding({
    required bool Function(double x, double y) hitTest,
    required VoidCallback onEntered,
    required VoidCallback onExited,
    required ValueChanged<List<String>> onDropped,
  });

  void dispose() {}
}
