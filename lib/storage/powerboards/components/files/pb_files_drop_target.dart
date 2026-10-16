import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_tokens.dart';
import '../../theme/pb_typography.dart';
import '../layouts/pb_files_native_drop.dart';
import '../primitives/pb_svg_icon.dart';
import 'pb_files_layout_values.dart';

class PbFilesDropTargetLayer extends StatefulWidget {
  const PbFilesDropTargetLayer({
    super.key,
    required this.child,
    required this.dropTargetTop,
    required this.padding,
    required this.onFilesDropped,
  });

  final Widget child;
  final double dropTargetTop;
  final PbFilesPanelPadding padding;
  final ValueChanged<List<String>> onFilesDropped;

  @override
  State<PbFilesDropTargetLayer> createState() => _PbFilesDropTargetLayerState();
}

class _PbFilesDropTargetLayerState extends State<PbFilesDropTargetLayer> {
  final GlobalKey _targetKey = GlobalKey();
  PbNativeFilesDropBinding? _nativeDropBinding;
  bool _nativeDropTargetActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureNativeBinding());
  }

  @override
  void dispose() {
    _nativeDropBinding?.dispose();
    super.dispose();
  }

  void _ensureNativeBinding() {
    if (!mounted || _nativeDropBinding != null) {
      return;
    }

    _nativeDropBinding = PbNativeFilesDropBinding(
      hitTest: _hitTest,
      onEntered: () => _setNativeDropTargetActive(true),
      onExited: () => _setNativeDropTargetActive(false),
      onDropped: widget.onFilesDropped,
    );
  }

  bool _hitTest(double x, double y) {
    final renderObject = _targetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }

    final local = renderObject.globalToLocal(Offset(x, y));
    return (Offset.zero & renderObject.size).contains(local);
  }

  void _setNativeDropTargetActive(bool active) {
    if (!mounted || _nativeDropTargetActive == active) {
      return;
    }

    setState(() => _nativeDropTargetActive = active);
  }

  @override
  Widget build(BuildContext context) {
    _ensureNativeBinding();

    return DragTarget<Object>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (_) => widget.onFilesDropped(const ['Uploading file']),
      builder: (context, candidateData, rejectedData) {
        final dropTargetActive = candidateData.isNotEmpty || _nativeDropTargetActive;

        return SizedBox.expand(
          key: _targetKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              Positioned.fill(
                child: PbFilesDropTargetOverlayLayer(active: dropTargetActive, top: widget.dropTargetTop, padding: widget.padding),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PbFilesDropTargetOverlayLayer extends StatelessWidget {
  const PbFilesDropTargetOverlayLayer({
    super.key,
    required this.active,
    required this.top,
    required this.padding,
    this.title = 'Drop files here',
    this.bottom = 30,
  });

  final bool active;
  final double top;
  final PbFilesPanelPadding padding;
  final String title;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: active ? 1 : 0,
          child: PbFilesDropTargetOverlay(padding: padding, title: title, bottom: bottom),
        ),
      ),
    );
  }
}

class PbFilesDropTargetOverlay extends StatelessWidget {
  const PbFilesDropTargetOverlay({super.key, required this.padding, this.title = 'Drop files here', this.bottom = 30});

  final PbFilesPanelPadding padding;
  final String title;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PbRadii.medium),
          color: PbColors.dynamicCustomStateSelectedSurface.withValues(alpha: 0.54),
          boxShadow: PbShadows.card,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PbRadii.medium),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: CustomPaint(
              painter: const _FilesDropTargetFramePainter(),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Color.lerp(PbColors.dynamicCustomStateSelectedSurface, PbColors.dynamicSurfacePanel, 0.76),
                        borderRadius: BorderRadius.circular(PbRadii.small),
                        boxShadow: [PbShadows.softFromTextMuted(0.10)],
                      ),
                      alignment: Alignment.center,
                      child: PbSvgIcon(assetName: 'arrow-down-to-line', size: 22, color: PbColors.dynamicCustomRailSelectedSurface),
                    ),
                    const SizedBox(width: 12),
                    Text(title, style: PowerboardsTypography.h2.copyWith(color: PbColors.textPrimary)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilesDropTargetFramePainter extends CustomPainter {
  const _FilesDropTargetFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = PbColors.dynamicCustomStateSelectedBorder
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(PbRadii.medium));
    final path = Path()..addRRect(rrect);
    const dashLength = 3.5;
    const dashGap = 3.5;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashLength + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FilesDropTargetFramePainter oldDelegate) {
    return false;
  }
}
