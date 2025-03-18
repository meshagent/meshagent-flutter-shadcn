import 'package:meshagent/document.dart' as docs;
import 'package:flutter/widgets.dart';

class ChangeNotifierBuilder extends StatefulWidget {
  ChangeNotifierBuilder({required this.source, super.key, required this.builder});

  final docs.ChangeEmitter source;
  final Widget Function(BuildContext) builder;

  @override
  State createState() => _ChangeNotifierBuilderState();
}

class _ChangeNotifierBuilderState extends State<ChangeNotifierBuilder> {
  @override
  void initState() {
    super.initState();

    widget.source.addListener(this.onDocumentChanged);
  }

  @override
  void dispose() {
    super.dispose();
    widget.source.removeListener(this.onDocumentChanged);
  }

  void onDocumentChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context);
  }
}
