import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'pb_file_preview_menu_scope.dart';

class PbWebsitePreviewFrame extends StatefulWidget {
  const PbWebsitePreviewFrame({super.key, this.htmlDocument, this.url}) : assert(htmlDocument != null || url != null);

  final String? htmlDocument;
  final Uri? url;

  @override
  State<PbWebsitePreviewFrame> createState() => _PbWebsitePreviewFrameState();
}

class _PbWebsitePreviewFrameState extends State<PbWebsitePreviewFrame> {
  static int _nextViewId = 0;

  web.HTMLIFrameElement? _iframe;
  bool _pointerEventsEnabled = true;
  late String _viewType = _registerViewType(htmlDocument: widget.htmlDocument, url: widget.url);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setPointerEventsEnabled(!PbFilePreviewMenuScope.menuOpen(context));
  }

  @override
  void didUpdateWidget(covariant PbWebsitePreviewFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.htmlDocument != widget.htmlDocument || oldWidget.url != widget.url) {
      _viewType = _registerViewType(htmlDocument: widget.htmlDocument, url: widget.url);
    }
  }

  String _registerViewType({required String? htmlDocument, required Uri? url}) {
    final viewType = 'pb-website-preview-${_nextViewId++}';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (viewId) {
      final iframe = web.HTMLIFrameElement()
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = 'white';
      if (url != null) {
        iframe.src = url.toString();
      } else {
        iframe.srcdoc = (htmlDocument ?? '').toJS;
      }
      iframe.setAttribute('sandbox', 'allow-same-origin allow-scripts allow-forms allow-popups allow-popups-to-escape-sandbox');
      _iframe = iframe;
      _applyPointerEvents();
      return iframe;
    });
    return viewType;
  }

  void _setPointerEventsEnabled(bool enabled) {
    if (_pointerEventsEnabled == enabled) {
      return;
    }
    _pointerEventsEnabled = enabled;
    _applyPointerEvents();
  }

  void _applyPointerEvents() {
    _iframe?.style.pointerEvents = _pointerEventsEnabled ? 'auto' : 'none';
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(key: ValueKey<String>(_viewType), viewType: _viewType);
  }
}
