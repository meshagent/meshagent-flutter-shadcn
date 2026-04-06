import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
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
        if (segments.isEmpty) {
          return const _TranscriptEmptyState();
        }

        final transcriptStartTime = _firstSegmentTime(segments);

        return SelectionArea(
          child: ListView(
            padding: EdgeInsets.all(16),
            children: [for (final segment in segments) TranscriptSegment(segment: segment, transcriptStartTime: transcriptStartTime)],
          ),
        );
      },
    );
  }
}

DateTime? _firstSegmentTime(List<MeshElement> segments) {
  for (final segment in segments) {
    final parsed = _tryParseSegmentTime(segment);
    if (parsed != null) {
      return parsed;
    }
  }

  return null;
}

DateTime? _tryParseSegmentTime(MeshElement segment) {
  final value = segment.getAttribute("time");
  if (value is! String || value.trim().isEmpty) {
    return null;
  }

  return DateTime.tryParse(value);
}

String _formatTranscriptTimecode(Duration elapsed) {
  final totalSeconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  String twoDigits(int value) => value.toString().padLeft(2, '0');

  return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
}

class _TranscriptEmptyState extends StatelessWidget {
  const _TranscriptEmptyState();

  static const double _verticalOffset = -48;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.translate(
        offset: const Offset(0, _verticalOffset),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [ChatThreadEmptyStateContent(title: "No transcript available", titleScaleOverride: 0.72)],
            ),
          ),
        ),
      ),
    );
  }
}

class TranscriptSegment extends StatefulWidget {
  const TranscriptSegment({super.key, required this.segment, required this.transcriptStartTime});

  final MeshElement segment;
  final DateTime? transcriptStartTime;

  @override
  State createState() => _TranscriptSegment();
}

class _TranscriptSegment extends State<TranscriptSegment> {
  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final textStyle = theme.textTheme.p.copyWith(color: theme.colorScheme.foreground, fontSize: 14, height: 24 / 14);
    final segmentTime = _tryParseSegmentTime(widget.segment);
    final elapsedTime = (segmentTime != null && widget.transcriptStartTime != null)
        ? segmentTime.difference(widget.transcriptStartTime!)
        : null;
    final timecodeStyle = theme.textTheme.muted.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.mutedForeground,
    );

    return ChangeNotifierBuilder(
      source: widget.segment,
      builder: (context) => Container(
        margin: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (elapsedTime != null) ...[Text(_formatTranscriptTimecode(elapsedTime), style: timecodeStyle), const SizedBox(height: 4)],
            Text('${widget.segment.getAttribute("participant_name") ?? ""}:', style: textStyle.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(widget.segment.getAttribute("text") as String? ?? "", style: textStyle),
          ],
        ),
      ),
    );
  }
}
