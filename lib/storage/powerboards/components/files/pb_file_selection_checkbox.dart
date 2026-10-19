import 'package:flutter/material.dart';

import '../../theme/pb_colors.dart';
import '../../theme/pb_tokens.dart';

class PbFileSelectionCheckbox extends StatelessWidget {
  const PbFileSelectionCheckbox({
    super.key,
    required this.checked,
    this.mixed = false,
    this.enabled = true,
    this.compactHitArea = false,
    required this.onPressed,
  });

  final bool checked;
  final bool mixed;
  final bool enabled;
  final bool compactHitArea;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = checked || mixed;
    final hitSize = compactHitArea ? 14.0 : 22.0;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          width: hitSize,
          height: hitSize,
          child: Center(
            child: Opacity(
              opacity: enabled ? 1 : 0.42,
              child: AnimatedContainer(
                duration: PbMotion.state,
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: active
                      ? PbColors.dynamicSurfaceActionPrimary
                      : enabled
                      ? PbColors.dynamicSurfacePanel
                      : PbColors.borderFaint,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: active ? PbColors.dynamicSurfaceActionPrimary : PbColors.customGray),
                ),
                child: active
                    ? CustomPaint(
                        painter: _PbFileSelectionCheckPainter(mixed: mixed),
                        size: const Size(14, 14),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PbFileSelectionCheckPainter extends CustomPainter {
  const _PbFileSelectionCheckPainter({required this.mixed});

  final bool mixed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = PbColors.dynamicSurfacePanel
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (mixed) {
      canvas.drawLine(Offset(size.width * 0.32, size.height * 0.5), Offset(size.width * 0.68, size.height * 0.5), paint);
      return;
    }

    final path = Path()
      ..moveTo(size.width * 0.33, size.height * 0.51)
      ..lineTo(size.width * 0.46, size.height * 0.63)
      ..lineTo(size.width * 0.69, size.height * 0.39);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PbFileSelectionCheckPainter oldDelegate) {
    return oldDelegate.mixed != mixed;
  }
}
