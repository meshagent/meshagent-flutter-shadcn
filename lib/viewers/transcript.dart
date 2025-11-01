import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/viewers/viewers.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class TranscriptViewer extends StatefulWidget {
  const TranscriptViewer({super.key, required this.document});

  final MeshDocument document;

  @override
  State createState() => _Transcript();
}

class _Transcript extends State<TranscriptViewer> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierBuilder(
      source: widget.document,
      builder: (context) {
        final segments = widget.document.root.getElementsByTagName("segment");
        return SelectionArea(
          child: ListView(padding: EdgeInsets.all(16), children: [for (final segment in segments) TranscriptSegment(segment: segment)]),
        );
      },
    );
  }
}

class TranscriptSegment extends StatefulWidget {
  const TranscriptSegment({super.key, required this.segment});

  final MeshElement segment;

  @override
  State createState() => _TranscriptSegment();
}

class _TranscriptSegment extends State<TranscriptSegment> {
  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ChangeNotifierBuilder(
      source: widget.segment,
      builder:
          (context) => Container(
            margin: EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${widget.segment.getAttribute("participant_name") ?? ""}: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: widget.segment.getAttribute("text") as String? ?? ""),
                ],
                style: theme.textTheme.p.copyWith(color: theme.colorScheme.foreground),
              ),
            ),
          ),
    );
  }
}
