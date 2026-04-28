import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/ui/coordinated_context_menu.dart';
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

        final transcriptMeta = _transcriptMeta(segments);

        return SelectionArea(
          contextMenuBuilder: (context, selectableRegionState) =>
              AdaptiveTextSelectionToolbar.selectableRegion(selectableRegionState: selectableRegionState),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TranscriptHeader(meta: transcriptMeta),
              const SizedBox(height: 32),
              for (final segment in segments) TranscriptSegment(segment: segment, transcriptStartTime: transcriptMeta.startTime),
            ],
          ),
        );
      },
    );
  }
}

class _TranscriptMeta {
  const _TranscriptMeta({required this.startTime, required this.endTime, required this.participants});

  final DateTime? startTime;
  final DateTime? endTime;
  final List<_TranscriptParticipant> participants;

  Duration? get duration {
    if (startTime == null || endTime == null) {
      return null;
    }
    return endTime!.difference(startTime!);
  }
}

_TranscriptMeta _transcriptMeta(List<MeshElement> segments) {
  DateTime? first;
  DateTime? last;
  final participantsByLabel = <String, _TranscriptParticipant>{};

  for (final segment in segments) {
    final parsed = _tryParseSegmentTime(segment);
    if (parsed != null) {
      first ??= parsed;
      last = parsed;
    }

    final participant = _transcriptParticipant(segment);
    if (participant != null) {
      participantsByLabel.putIfAbsent(participant.label, () => participant);
    }
  }

  return _TranscriptMeta(startTime: first, endTime: last, participants: participantsByLabel.values.toList(growable: false));
}

DateTime? _tryParseSegmentTime(MeshElement segment) {
  final value = segment.getAttribute("time");
  if (value is! String || value.trim().isEmpty) {
    return null;
  }

  return DateTime.tryParse(value);
}

class _TranscriptParticipant {
  const _TranscriptParticipant({required this.label, required this.initials, required this.isAgentLike});

  final String label;
  final String initials;
  final bool isAgentLike;
}

_TranscriptParticipant? _transcriptParticipant(MeshElement segment) {
  final rawName = segment.getAttribute("participant_name");
  if (rawName is! String) {
    return null;
  }

  final label = rawName.trim();
  if (label.isEmpty) {
    return null;
  }

  final rawRole = segment.getAttribute("participant_role");
  final role = rawRole is String ? rawRole.trim().toLowerCase() : "";
  final isEmail = label.contains("@");
  final isAgentLike = !isEmail || role == "agent" || role == "assistant";
  return _TranscriptParticipant(
    label: label,
    initials: isEmail ? _userAvatarInitialsFromEmail(label) : _singleInitial(label),
    isAgentLike: isAgentLike,
  );
}

String _singleInitial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return "U";
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

String _userAvatarInitialsFromEmail(String email) {
  final normalizedEmail = email.trim();
  if (normalizedEmail.isEmpty) {
    return "U";
  }

  final local = normalizedEmail.split("@").first;
  final parts = local.split(RegExp(r"[-._ ]+")).where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2) {
    return "${_singleInitial(parts[0])}${_singleInitial(parts[1])}";
  }
  if (parts.length == 1) {
    return _singleInitial(parts[0]);
  }

  return "U";
}

String _formatTranscriptTimecode(Duration elapsed) {
  final totalSeconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  String twoDigits(int value) => value.toString().padLeft(2, '0');

  return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
}

String? _formatTranscriptHeaderDate(BuildContext context, DateTime? startTime) {
  if (startTime == null) {
    return null;
  }

  final local = startTime.toLocal();
  final month = MaterialLocalizations.of(context).formatMonthYear(local).split(" ").first;
  return "$month ${local.day}, ${local.year}";
}

String? _formatTranscriptHeaderTime(BuildContext context, DateTime? startTime) {
  if (startTime == null) {
    return null;
  }

  final local = startTime.toLocal();
  final formatted = MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: false);
  return formatted.replaceAll(" AM", "a").replaceAll(" PM", "p");
}

String? _formatTranscriptDuration(Duration? duration) {
  if (duration == null) {
    return null;
  }

  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  if (totalSeconds < 60) {
    final seconds = totalSeconds == 1 ? "1 sec" : "$totalSeconds secs";
    return seconds;
  }

  final totalMinutes = duration.inMinutes;
  if (totalMinutes < 60) {
    final minutes = totalMinutes == 1 ? "1 min" : "$totalMinutes mins";
    return minutes;
  }

  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (minutes == 0) {
    return hours == 1 ? "1 hr" : "$hours hrs";
  }

  final hoursLabel = hours == 1 ? "1 hr" : "$hours hrs";
  final minutesLabel = minutes == 1 ? "1 min" : "$minutes mins";
  return "$hoursLabel $minutesLabel";
}

class _TranscriptHeader extends StatelessWidget {
  const _TranscriptHeader({required this.meta});

  final _TranscriptMeta meta;
  static const double _emptyStateTitleMinScale = 0.72;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final dateText = _formatTranscriptHeaderDate(context, meta.startTime);
    final h1Style = theme.textTheme.h1;
    final headerTitleSize = (h1Style.fontSize ?? 36) * _emptyStateTitleMinScale;
    final headerMetaSize = theme.textTheme.p.fontSize ?? 16;
    final detailParts = <String>[
      "Transcript",
      ?_formatTranscriptHeaderTime(context, meta.startTime),
      ?_formatTranscriptDuration(meta.duration),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: dateText == null
                  ? const SizedBox.shrink()
                  : Text(
                      dateText,
                      style: h1Style.copyWith(color: theme.colorScheme.foreground, fontSize: headerTitleSize),
                    ),
            ),
            if (meta.participants.isNotEmpty) ...[
              const SizedBox(width: 16),
              _TranscriptParticipantsButton(participants: meta.participants),
            ],
          ],
        ),
        if (dateText != null) const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              "Transcript",
              style: theme.textTheme.large.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.foreground,
                fontSize: headerMetaSize,
              ),
            ),
            if (detailParts.length > 1)
              Text(
                detailParts.skip(1).join(" - "),
                style: theme.textTheme.large.copyWith(color: theme.colorScheme.mutedForeground, fontSize: headerMetaSize),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Divider(color: theme.colorScheme.border),
      ],
    );
  }
}

class _TranscriptParticipantsButton extends StatefulWidget {
  const _TranscriptParticipantsButton({required this.participants});

  final List<_TranscriptParticipant> participants;

  @override
  State<_TranscriptParticipantsButton> createState() => _TranscriptParticipantsButtonState();
}

class _TranscriptParticipantsButtonState extends State<_TranscriptParticipantsButton> {
  static const double _avatarDiameter = 32;
  static const double _menuAvatarDiameter = 24;
  static const double _overlapOffset = 24;
  static const double _headerAvatarDiameter = 40;
  static const Color _avatarAccent = Color(0xFFE4E4FF);
  static const double _menuWidth = 320;
  static const double _menuHeaderHeight = 53;
  static const double _menuRowHeight = 40;

  late final ShadContextMenuController _popoverController = ShadContextMenuController();
  final ShadStatesController _statesController = ShadStatesController();

  @override
  void dispose() {
    _popoverController.dispose();
    _statesController.dispose();
    super.dispose();
  }

  Widget _avatar(_TranscriptParticipant participant, {required bool hovered, double diameter = _avatarDiameter, bool withTooltip = true}) {
    final theme = ShadTheme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final hoverBackgroundColor = theme.outlineButtonTheme.hoverBackgroundColor ?? _avatarAccent;
    final baseFontSize = tt.small.fontSize ?? 14;
    final fontSize = baseFontSize * (diameter / _headerAvatarDiameter);
    final backgroundColor = participant.isAgentLike ? cs.card : (hovered ? hoverBackgroundColor : _avatarAccent);
    final avatar = Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: Border.all(color: cs.border, strokeAlign: BorderSide.strokeAlignOutside),
      ),
      child: participant.isAgentLike
          ? Icon(LucideIcons.bot, size: fontSize + 2, color: cs.foreground)
          : Text(
              participant.initials,
              style: tt.small.copyWith(fontWeight: FontWeight.w700, color: cs.foreground, fontSize: fontSize),
            ),
    );

    if (!withTooltip) {
      return avatar;
    }

    return Tooltip(message: participant.label, child: avatar);
  }

  Widget _buildOverlapAvatars(Set<ShadState> states) {
    final hovered = states.contains(ShadState.hovered);
    final width = _avatarDiameter + (widget.participants.length - 1) * _overlapOffset;

    return SizedBox(
      width: width,
      height: _avatarDiameter,
      child: Stack(
        children: List.generate(widget.participants.length, (index) {
          final participant = widget.participants[index];
          return Positioned(
            left: index * _overlapOffset,
            child: _avatar(participant, hovered: hovered),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final tt = theme.textTheme;
    final trigger = widget.participants.length <= 3
        ? ValueListenableBuilder(
            valueListenable: _statesController,
            builder: (context, states, _) {
              return ShadButton.ghost(
                statesController: _statesController,
                backgroundColor: Colors.transparent,
                hoverBackgroundColor: Colors.transparent,
                padding: EdgeInsets.zero,
                onPressed: _popoverController.toggle,
                decoration: ShadDecoration.none,
                child: _buildOverlapAvatars(states),
              );
            },
          )
        : ShadButton.outline(
            leading: const Icon(LucideIcons.users),
            onPressed: _popoverController.toggle,
            child: Text("+${widget.participants.length}"),
          );

    return CoordinatedShadContextMenu(
      controller: _popoverController,
      constraints: const BoxConstraints(minWidth: _menuWidth, maxWidth: _menuWidth),
      estimatedMenuWidth: _menuWidth,
      estimatedMenuHeight: _menuHeaderHeight + widget.participants.length * _menuRowHeight,
      items: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Text(
                "Speakers",
                style: tt.large.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.foreground, fontSize: tt.p.fontSize),
              ),
            ),
            for (final participant in widget.participants)
              ShadContextMenuItem(
                height: _menuRowHeight,
                leading: _avatar(participant, hovered: false, diameter: _menuAvatarDiameter, withTooltip: false),
                onPressed: _popoverController.hide,
                child: Text(participant.label, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ],
      child: trigger,
    );
  }
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
