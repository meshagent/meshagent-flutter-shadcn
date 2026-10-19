import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart';

class PbNativeFilesDropBinding {
  PbNativeFilesDropBinding({
    required bool Function(double x, double y) hitTest,
    required VoidCallback onEntered,
    required VoidCallback onExited,
    required ValueChanged<List<String>> onDropped,
    // Keep public callback names while storing private fields.
    // ignore: prefer_initializing_formals
  }) : _hitTest = hitTest,
       // ignore: prefer_initializing_formals
       _onEntered = onEntered,
       // ignore: prefer_initializing_formals
       _onExited = onExited,
       // ignore: prefer_initializing_formals
       _onDropped = onDropped {
    _dragEnterListener = ((Event event) {
      _handleDragEnter(event as DragEvent);
    }).toJS;
    _dragOverListener = ((Event event) {
      _handleDragOver(event as DragEvent);
    }).toJS;
    _dragLeaveListener = ((Event event) {
      _handleDragLeave(event as DragEvent);
    }).toJS;
    _dropListener = ((Event event) {
      _handleDrop(event as DragEvent);
    }).toJS;
    _resetListener = ((Event event) {
      _resetDropTarget();
    }).toJS;

    window.addEventListener('dragenter', _dragEnterListener);
    window.addEventListener('dragover', _dragOverListener);
    window.addEventListener('dragleave', _dragLeaveListener);
    window.addEventListener('drop', _dropListener);
    window.addEventListener('dragend', _resetListener);
    window.addEventListener('blur', _resetListener);
  }

  final bool Function(double x, double y) _hitTest;
  final VoidCallback _onEntered;
  final VoidCallback _onExited;
  final ValueChanged<List<String>> _onDropped;

  late final EventListener _dragEnterListener;
  late final EventListener _dragOverListener;
  late final EventListener _dragLeaveListener;
  late final EventListener _dropListener;
  late final EventListener _resetListener;

  int _fileDragDepth = 0;
  bool _active = false;

  void dispose() {
    window.removeEventListener('dragenter', _dragEnterListener);
    window.removeEventListener('dragover', _dragOverListener);
    window.removeEventListener('dragleave', _dragLeaveListener);
    window.removeEventListener('drop', _dropListener);
    window.removeEventListener('dragend', _resetListener);
    window.removeEventListener('blur', _resetListener);
  }

  bool _isFilesDragData(DragEvent event) {
    final dataTransfer = event.dataTransfer;
    if (dataTransfer == null) {
      return false;
    }

    final types = dataTransfer.types.toDart.map((type) => type.toDart);
    return types.contains('Files') || types.contains('application/x-moz-file');
  }

  bool _contains(DragEvent event) {
    return _hitTest(event.clientX.toDouble(), event.clientY.toDouble());
  }

  void _setActive(bool active) {
    if (_active == active) {
      return;
    }

    _active = active;
    if (active) {
      _onEntered();
    } else {
      _onExited();
    }
  }

  void _handleDragEnter(DragEvent event) {
    if (!_isFilesDragData(event) || !_contains(event)) {
      return;
    }

    event.preventDefault();
    _fileDragDepth += 1;
    _setActive(true);
  }

  void _handleDragOver(DragEvent event) {
    if (!_isFilesDragData(event) || !_contains(event)) {
      return;
    }

    event.preventDefault();
    event.dataTransfer?.dropEffect = 'copy';
    _setActive(true);
  }

  void _handleDragLeave(DragEvent event) {
    if (!_isFilesDragData(event)) {
      return;
    }

    if (!_contains(event)) {
      _resetDropTarget();
      return;
    }

    _fileDragDepth = _fileDragDepth > 0 ? _fileDragDepth - 1 : 0;
    if (_fileDragDepth == 0) {
      _setActive(false);
    }
  }

  void _handleDrop(DragEvent event) {
    if (!_isFilesDragData(event) || (!_active && !_contains(event))) {
      return;
    }

    event.preventDefault();
    final fileList = event.dataTransfer?.files;
    final names = <String>[];
    if (fileList != null) {
      for (var index = 0; index < fileList.length; index += 1) {
        final name = fileList.item(index)?.name.trim();
        if (name != null && name.isNotEmpty) {
          names.add(name);
        }
      }
    }

    _onDropped(names.isEmpty ? const ['Uploading file'] : names);
    _resetDropTarget();
  }

  void _resetDropTarget() {
    _fileDragDepth = 0;
    _setActive(false);
  }
}
