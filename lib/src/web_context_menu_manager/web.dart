import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as html;

import 'enable_web_context_menu.dart';

class WebContextMenuManager extends StatefulWidget {
  const WebContextMenuManager({super.key, required this.child});

  final Widget child;

  @override
  State<WebContextMenuManager> createState() => _WebContextMenuManagerState();
}

class _WebContextMenuManagerState extends State<WebContextMenuManager> {
  late final JSFunction listener;

  void _removeExistingCtxHandlers() {
    try {
      final fn = html.window['removeExistingCtxHandlers'] as JSFunction;
      fn.callAsFunction();
    } catch (_) {}
  }

  bool _allowBrowserMenuForEvent(html.Event event) {
    final mouseEvent = event as html.MouseEvent;
    final point = Offset(mouseEvent.clientX.toDouble(), mouseEvent.clientY.toDouble());
    for (final rect in EnableWebContextRegistry.rects) {
      if (rect.contains(point)) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();

    _removeExistingCtxHandlers();
    listener = ((html.MouseEvent event) {
      if (!_allowBrowserMenuForEvent(event)) {
        event.preventDefault();
      }
    }).toJS;

    html.document.addEventListener('contextmenu', listener, (html.AddEventListenerOptions(capture: true) as JSAny));
  }

  @override
  void dispose() {
    html.document.removeEventListener('contextmenu', listener, (html.EventListenerOptions(capture: true) as JSAny));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
