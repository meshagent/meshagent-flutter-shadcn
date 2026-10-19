import 'package:flutter/material.dart';

import '../../models/pb_agent_display.dart';
import '../../theme/pb_colors.dart';
import '../../theme/pb_typography.dart';
import '../primitives/pb_svg_icon.dart';

class PbThreadHeader extends StatelessWidget {
  const PbThreadHeader({
    super.key,
    this.title = 'Launch planning',
    this.agentName = 'Assistant',
    this.agentContextLabel = 'Thread with',
    this.selectedThreadTitle,
    this.titleResolving = false,
    this.roomPanelExpanded = true,
    this.blankRoom = false,
    this.onTitlePressed,
    this.onRoomPanelToggle,
    this.onOpenAllAgentsAndThreads,
  });

  final String title;
  final String agentName;
  final String agentContextLabel;
  final String? selectedThreadTitle;
  final bool titleResolving;
  final bool roomPanelExpanded;
  final bool blankRoom;
  final VoidCallback? onTitlePressed;
  final VoidCallback? onRoomPanelToggle;
  final VoidCallback? onOpenAllAgentsAndThreads;

  String get _selectedThreadTitle => selectedThreadTitle ?? title;
  VoidCallback? get _titleAction => onOpenAllAgentsAndThreads ?? onTitlePressed;

  @override
  Widget build(BuildContext context) {
    if (blankRoom) {
      return Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.fromLTRB(30, 19, 28, 19),
        child: const Row(children: [Expanded(child: _BlankRoomTitle())]),
      );
    }

    final threadTitleButton = _ThreadTitleButton(title: _selectedThreadTitle, resolving: titleResolving, onPressed: _titleAction);

    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.fromLTRB(30, 19, 28, 19),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 560;
          final titleGroup = _ThreadTitleGroup(
            titleButton: threadTitleButton,
            agentName: agentName,
            agentContextLabel: agentContextLabel,
            stacked: stacked,
          );
          final actions = _ThreadHeaderActions(
            roomPanelExpanded: roomPanelExpanded,
            onRoomPanelToggle: onRoomPanelToggle,
            onOpenAllAgentsAndThreads: onOpenAllAgentsAndThreads,
          );

          if (stacked) {
            return SizedBox(
              height: 72,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleGroup),
                  const SizedBox(width: 16),
                  SizedBox(
                    height: 38,
                    child: Align(alignment: Alignment.topRight, child: actions),
                  ),
                ],
              ),
            );
          }

          return Row(
            children: [
              Expanded(child: titleGroup),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _BlankRoomTitle extends StatelessWidget {
  const _BlankRoomTitle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('Welcome', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: PowerboardsTypography.h1),
      ),
    );
  }
}

class _ThreadTitleGroup extends StatelessWidget {
  const _ThreadTitleGroup({required this.titleButton, required this.agentName, required this.agentContextLabel, required this.stacked});

  final Widget titleButton;
  final String agentName;
  final String agentContextLabel;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final meta = _ThreadMeta(agentName: agentName, agentContextLabel: agentContextLabel);

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [titleButton, const SizedBox(height: 6), meta],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: titleButton),
        const SizedBox(width: 20),
        Flexible(child: meta),
      ],
    );
  }
}

class _ThreadTitleButton extends StatefulWidget {
  const _ThreadTitleButton({required this.title, this.resolving = false, this.onPressed});

  final String title;
  final bool resolving;
  final VoidCallback? onPressed;

  @override
  State<_ThreadTitleButton> createState() => _ThreadTitleButtonState();
}

class _ThreadTitleButtonState extends State<_ThreadTitleButton> with SingleTickerProviderStateMixin {
  late final AnimationController _resolvingController;
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _resolvingController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _syncResolvingAnimation();
  }

  @override
  void didUpdateWidget(covariant _ThreadTitleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resolving != widget.resolving) {
      _syncResolvingAnimation();
    }
  }

  @override
  void dispose() {
    _resolvingController.dispose();
    super.dispose();
  }

  void _syncResolvingAnimation() {
    if (widget.resolving) {
      _resolvingController.repeat();
      return;
    }

    _resolvingController
      ..stop()
      ..value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onPressed != null;
    final lifted = interactive && _hovered && !_pressed;
    final title = Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: PowerboardsTypography.h2);
    final resolvingIdleColor = PbColors.customBrandInk.withValues(alpha: 0.62);
    final resolvingSweepColor = PbColors.customBrandInk.withValues(alpha: 0.3);
    final resolvingPeakColor = PbColors.customBrandInk.withValues(alpha: 0.86);
    final titleContent = widget.resolving
        ? AnimatedBuilder(
            animation: _resolvingController,
            child: title,
            builder: (context, child) => ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) {
                final width = bounds.width.isFinite && bounds.width > 0 ? bounds.width : 160.0;
                final shimmerWidth = width * 0.72;
                final left = -shimmerWidth + (width + shimmerWidth * 2) * _resolvingController.value;
                return LinearGradient(
                  colors: [resolvingIdleColor, resolvingSweepColor, resolvingPeakColor, resolvingSweepColor, resolvingIdleColor],
                  stops: const [0, 0.35, 0.5, 0.65, 1],
                ).createShader(Rect.fromLTWH(left, 0, shimmerWidth, bounds.height));
              },
              child: child,
            ),
          )
        : title;

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
      onExit: interactive
          ? (_) => setState(() {
              _hovered = false;
              _pressed = false;
            })
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: interactive ? (_) => setState(() => _pressed = true) : null,
        onTapUp: interactive
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: interactive ? () => setState(() => _pressed = false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.ease,
          transform: Matrix4.translationValues(0, lifted ? -1 : 0, 0),
          constraints: const BoxConstraints(minHeight: 38),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Flexible(child: titleContent)],
          ),
        ),
      ),
    );
  }
}

class _ThreadMeta extends StatelessWidget {
  const _ThreadMeta({required this.agentName, required this.agentContextLabel});

  final String agentName;
  final String agentContextLabel;

  @override
  Widget build(BuildContext context) {
    final displayAgentName = pbDisplayAgentName(agentName);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 52) {
          return const SizedBox.shrink();
        }

        if (constraints.maxWidth < 104) {
          return const _ThreadAgentPill();
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                agentContextLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: PowerboardsTypography.meta.copyWith(color: PbColors.textMuted),
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                displayAgentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: PowerboardsTypography.meta.copyWith(color: PbColors.textMuted, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 7),
            const _ThreadAgentPill(),
          ],
        );
      },
    );
  }
}

class _ThreadAgentPill extends StatelessWidget {
  const _ThreadAgentPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: PbColors.surfaceAccentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PbColors.customStateSelectedBorder),
      ),
      child: Transform.translate(
        offset: const Offset(0, -1),
        child: Text(
          'Agent',
          style: PowerboardsTypography.badge.copyWith(color: PbColors.surfaceRailActive, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ThreadHeaderActions extends StatelessWidget {
  const _ThreadHeaderActions({required this.roomPanelExpanded, this.onRoomPanelToggle, this.onOpenAllAgentsAndThreads});

  final bool roomPanelExpanded;
  final VoidCallback? onRoomPanelToggle;
  final VoidCallback? onOpenAllAgentsAndThreads;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!roomPanelExpanded) PbThreadHeaderQuaternaryButton(label: 'All agents & threads', onPressed: onOpenAllAgentsAndThreads),
        if (!roomPanelExpanded) const SizedBox(width: 6),
        PbThreadPanelToggle(expanded: roomPanelExpanded, onPressed: onRoomPanelToggle),
      ],
    );
  }
}

class PbThreadHeaderQuaternaryButton extends StatefulWidget {
  const PbThreadHeaderQuaternaryButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<PbThreadHeaderQuaternaryButton> createState() => _PbThreadHeaderQuaternaryButtonState();
}

class _PbThreadHeaderQuaternaryButtonState extends State<PbThreadHeaderQuaternaryButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onPressed != null;

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
      onExit: interactive
          ? (_) => setState(() {
              _hovered = false;
              _pressed = false;
            })
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: interactive ? (_) => setState(() => _pressed = true) : null,
        onTapUp: interactive
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: interactive ? () => setState(() => _pressed = false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.ease,
          transform: Matrix4.translationValues(0, _hovered && !_pressed ? -1 : 0, 0),
          constraints: const BoxConstraints(minHeight: 28),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: PowerboardsTypography.badge.copyWith(
              fontWeight: FontWeight.w800,
              color: _hovered ? Color.lerp(PbColors.surfaceRailActive, PbColors.customBlue, 0.18) : PbColors.surfaceRailActive,
            ),
          ),
        ),
      ),
    );
  }
}

class PbThreadPanelToggle extends StatefulWidget {
  const PbThreadPanelToggle({super.key, required this.expanded, this.onPressed});

  final bool expanded;
  final VoidCallback? onPressed;

  @override
  State<PbThreadPanelToggle> createState() => _PbThreadPanelToggleState();
}

class _PbThreadPanelToggleState extends State<PbThreadPanelToggle> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onPressed != null;
    final active = _hovered || _pressed;

    return Tooltip(
      message: widget.expanded ? 'Hide panel' : 'Show panel',
      child: MouseRegion(
        cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
        onExit: interactive
            ? (_) => setState(() {
                _hovered = false;
                _pressed = false;
              })
            : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: interactive ? (_) => setState(() => _pressed = true) : null,
          onTapUp: interactive
              ? (_) {
                  setState(() => _pressed = false);
                  widget.onPressed?.call();
                }
              : null,
          onTapCancel: interactive ? () => setState(() => _pressed = false) : null,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: AnimatedScale(
                duration: const Duration(milliseconds: 120),
                scale: _pressed ? 0.96 : 1,
                child: PbSvgIcon(
                  assetName: widget.expanded ? 'panel-right-close' : 'panel-right-open',
                  size: 18,
                  color: PbColors.customBrandInk.withValues(alpha: active ? 1 : 0.3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
