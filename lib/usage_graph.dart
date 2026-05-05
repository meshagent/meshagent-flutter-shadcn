import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class UsageGraphPoint {
  const UsageGraphPoint({required this.periodStart, required this.value});

  final DateTime periodStart;
  final double value;
}

class UsageGraph extends StatefulWidget {
  const UsageGraph({
    super.key,
    required this.points,
    required this.title,
    required this.formatValue,
    this.summaryValue,
    this.highlightedPoints = const [],
  });

  final List<UsageGraphPoint> points;
  final String title;
  final String Function(double value) formatValue;
  final double? summaryValue;
  final List<UsageGraphPoint> highlightedPoints;

  @override
  State<UsageGraph> createState() => _UsageGraphState();
}

class _UsageGraphState extends State<UsageGraph> {
  int? _hoveredIndex;

  void _updateHoveredIndex(Offset position, _UsageGraphLayout layout) {
    final index = _UsageGraphGeometry.hoveredBarIndex(widget.points, position, layout);
    if (index == _hoveredIndex) {
      return;
    }

    setState(() {
      _hoveredIndex = index;
    });
  }

  void _clearHoveredIndex() {
    if (_hoveredIndex == null) {
      return;
    }

    setState(() {
      _hoveredIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final total = widget.summaryValue ?? widget.points.fold<double>(0.0, (total, point) => total + point.value);
    final totalLabel = widget.formatValue(total);
    final usesHourlyLabels = _usesHourlyLabels(widget.points);
    final averageValue = _averageReferenceValue(widget.points, usesHourlyLabels: usesHourlyLabels);
    final averageLabel = averageValue == null ? null : widget.formatValue(averageValue);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 280);
        final layout = _UsageGraphGeometry.layout(size: size, theme: theme, title: widget.title, totalLabel: totalLabel);

        return MouseRegion(
          onHover: (event) => _updateHoveredIndex(event.localPosition, layout),
          onExit: (_) => _clearHoveredIndex(),
          cursor: _hoveredIndex == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: SizedBox(
            height: size.height,
            width: double.infinity,
            child: CustomPaint(
              painter: _UsageGraphPainter(
                points: widget.points,
                highlightedPoints: widget.highlightedPoints,
                title: widget.title,
                totalLabel: totalLabel,
                averageValue: averageValue,
                averageLabel: averageLabel,
                hoveredIndex: _hoveredIndex,
                hoveredLabel: _hoveredIndex == null ? null : widget.formatValue(widget.points[_hoveredIndex!].value),
                hoveredDateLabel: _hoveredIndex == null
                    ? null
                    : _formatPeriodLabel(widget.points[_hoveredIndex!].periodStart, usesHourlyLabels),
                usesHourlyLabels: usesHourlyLabels,
                layout: layout,
                theme: theme,
              ),
            ),
          ),
        );
      },
    );
  }

  double? _averageReferenceValue(List<UsageGraphPoint> points, {required bool usesHourlyLabels}) {
    final completedPoints = points.where((point) => !_isCurrentPeriod(point.periodStart, usesHourlyLabels)).toList();
    final referencePoints = completedPoints.length >= 2 ? completedPoints : points;
    if (referencePoints.length < 2) {
      return null;
    }

    var total = 0.0;
    var maxValue = 0.0;
    for (final point in referencePoints) {
      total += point.value;
      maxValue = math.max(maxValue, point.value);
    }

    if (total <= 0.0 || maxValue <= 0.0) {
      return null;
    }

    final average = total / referencePoints.length;
    if ((maxValue - average).abs() < 0.000001) {
      return null;
    }

    return average;
  }
}

class _UsageGraphLayout {
  const _UsageGraphLayout({required this.chartRect, required this.titleOffset, required this.totalOffset, required this.axisDateOffset});

  final Rect chartRect;
  final Offset titleOffset;
  final Offset totalOffset;
  final double axisDateOffset;
}

class _UsageGraphGeometry {
  static const horizontalPadding = 32.0;
  static const _titleTop = 24.0;
  static const _titleTotalGap = 6.0;
  static const _totalChartGap = 14.0;
  static const _axisDateGap = 16.0;
  static const _bottomPadding = 8.0;

  static TextStyle titleStyle(ShadThemeData theme) {
    return theme.textTheme.muted.copyWith(color: labelTextColor(theme), fontSize: 14, fontWeight: FontWeight.w600);
  }

  static TextStyle totalStyle(ShadThemeData theme) {
    return theme.textTheme.h3.copyWith(color: theme.colorScheme.foreground, fontSize: 20, fontWeight: FontWeight.w700);
  }

  static TextStyle referenceLabelStyle(ShadThemeData theme) {
    return theme.textTheme.muted.copyWith(color: labelTextColor(theme), fontSize: 13);
  }

  static TextStyle axisDateStyle(ShadThemeData theme) {
    return theme.textTheme.muted.copyWith(color: labelTextColor(theme), fontSize: 13);
  }

  static Color chartSurfaceColor(ShadThemeData theme) {
    final alpha = _isDark(theme) ? 0.13 : 0.055;
    return Color.alphaBlend(_blueBase(theme).withValues(alpha: alpha), theme.colorScheme.background);
  }

  static Color chartEdgeColor(ShadThemeData theme) {
    return _blueBase(theme).withValues(alpha: _isDark(theme) ? 0.48 : 0.28);
  }

  static Color barColor(ShadThemeData theme) {
    return _isDark(theme) ? const Color(0xFF5FA8C4) : const Color(0xFF0B3A52);
  }

  static Color partialBarColor(ShadThemeData theme) {
    return _isDark(theme) ? const Color(0xFF8FCBE0) : const Color(0xFF7EA6B8);
  }

  static Color hoverColor(ShadThemeData theme) {
    return _isDark(theme) ? const Color(0xFF7EC4DE) : const Color(0xFF041F2E);
  }

  static Color ruleColor(ShadThemeData theme, {double alpha = 0.62}) {
    return _blueBase(theme).withValues(alpha: alpha);
  }

  static Color averageLineColor(ShadThemeData theme) {
    return barColor(theme);
  }

  static Color labelTextColor(ShadThemeData theme) {
    final alpha = _isDark(theme) ? 0.14 : 0.08;
    return Color.alphaBlend(_blueBase(theme).withValues(alpha: alpha), theme.colorScheme.foreground);
  }

  static Color valueTextColor(ShadThemeData theme) {
    return theme.colorScheme.foreground;
  }

  static Color _blueBase(ShadThemeData theme) {
    return _isDark(theme) ? const Color(0xFF79AFC4) : const Color(0xFF2F6F8F);
  }

  static bool isDark(ShadThemeData theme) {
    return _isDark(theme);
  }

  static bool _isDark(ShadThemeData theme) {
    return theme.brightness == Brightness.dark;
  }

  static _UsageGraphLayout layout({required Size size, required ShadThemeData theme, required String title, required String totalLabel}) {
    final maxTextWidth = math.max(0.0, math.min(280.0, size.width - (horizontalPadding * 2)));
    final titleHeight = _measureText(title, titleStyle(theme), maxTextWidth).height;
    final totalHeight = _measureText(totalLabel, totalStyle(theme), maxTextWidth).height;
    final axisDateHeight = _measureText('Apr 29', axisDateStyle(theme), maxTextWidth).height;
    final titleOffset = const Offset(horizontalPadding, _titleTop);
    final totalOffset = Offset(horizontalPadding, titleOffset.dy + titleHeight + _titleTotalGap);
    final chartTop = totalOffset.dy + totalHeight + _totalChartGap;
    final chartBottom = axisDateHeight + _axisDateGap + _bottomPadding;
    final chartRect = Rect.fromLTWH(
      horizontalPadding,
      chartTop,
      math.max(0.0, size.width - (horizontalPadding * 2)),
      math.max(0.0, size.height - chartTop - chartBottom),
    );

    return _UsageGraphLayout(chartRect: chartRect, titleOffset: titleOffset, totalOffset: totalOffset, axisDateOffset: _axisDateGap);
  }

  static Size _measureText(String text, TextStyle style, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);
    return painter.size;
  }

  static Rect barRect(List<UsageGraphPoint> points, int index, _UsageGraphLayout layout) {
    final rect = layout.chartRect;
    if (points.isEmpty || rect.width <= 0.0 || rect.height <= 0.0) {
      return Rect.zero;
    }

    final maxValue = points.fold<double>(0.0, (maxValue, point) => math.max(maxValue, point.value));
    final slotWidth = rect.width / points.length;
    final barWidth = math.min(42.0, math.max(2.0, slotWidth * 0.72));
    final point = points[index];
    final normalized = maxValue <= 0.0 ? 0.0 : point.value / maxValue;
    final height = rect.height * normalized;
    final centerX = rect.left + (slotWidth * index) + (slotWidth / 2);

    return Rect.fromLTWH(centerX - (barWidth / 2), rect.bottom - height, barWidth, height);
  }

  static int? hoveredBarIndex(List<UsageGraphPoint> points, Offset position, _UsageGraphLayout layout) {
    if (points.isEmpty) {
      return null;
    }

    for (var i = 0; i < points.length; i++) {
      final rect = barRect(points, i, layout);
      if (rect.height > 0.0 && rect.inflate(3.0).contains(position)) {
        return i;
      }
    }

    return null;
  }
}

class _UsageGraphPainter extends CustomPainter {
  const _UsageGraphPainter({
    required this.points,
    required this.highlightedPoints,
    required this.title,
    required this.totalLabel,
    required this.averageValue,
    required this.averageLabel,
    required this.hoveredIndex,
    required this.hoveredLabel,
    required this.hoveredDateLabel,
    required this.usesHourlyLabels,
    required this.layout,
    required this.theme,
  });

  final List<UsageGraphPoint> points;
  final List<UsageGraphPoint> highlightedPoints;
  final String title;
  final String totalLabel;
  final double? averageValue;
  final String? averageLabel;
  final int? hoveredIndex;
  final String? hoveredLabel;
  final String? hoveredDateLabel;
  final bool usesHourlyLabels;
  final _UsageGraphLayout layout;
  final ShadThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final textTheme = theme.textTheme;
    final chartRect = layout.chartRect;

    _paintFigureFrame(canvas, Offset.zero & size);
    _paintText(canvas, title, layout.titleOffset, _UsageGraphGeometry.titleStyle(theme));
    _paintText(canvas, totalLabel, layout.totalOffset, _UsageGraphGeometry.totalStyle(theme));

    if (points.isEmpty) {
      _paintText(canvas, 'No usage in this period', chartRect.center, textTheme.muted.copyWith(fontSize: 13), align: TextAlign.center);
      return;
    }

    final baselinePaint = Paint()
      ..color = _UsageGraphGeometry.ruleColor(theme, alpha: _UsageGraphGeometry.isDark(theme) ? 0.72 : 0.62)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(chartRect.left, chartRect.bottom), Offset(chartRect.right, chartRect.bottom), baselinePaint);

    final highlightedValuesByPeriod = _valuesByPeriod(highlightedPoints);
    for (var i = 0; i < points.length; i++) {
      final rect = _UsageGraphGeometry.barRect(points, i, layout);
      final isPartial = _isCurrentPeriod(points[i].periodStart, usesHourlyLabels);
      final color = i == hoveredIndex
          ? _UsageGraphGeometry.hoverColor(theme)
          : isPartial
          ? _UsageGraphGeometry.partialBarColor(theme)
          : _UsageGraphGeometry.barColor(theme);
      final barPaint = Paint()..color = color;
      canvas.drawRect(rect, barPaint);
      _paintHighlightedBarSegment(
        canvas,
        rect: rect,
        totalValue: points[i].value,
        highlightedValue: highlightedValuesByPeriod[_periodKey(points[i].periodStart, usesHourlyLabels)] ?? 0.0,
        barColor: color,
      );
    }

    _paintAverageReference(canvas, chartRect);

    final hoverIndex = hoveredIndex;
    final hoverLabel = hoveredLabel;
    final hoverDateLabel = hoveredDateLabel;
    if (hoverIndex != null && hoverLabel != null && hoverDateLabel != null && hoverIndex >= 0 && hoverIndex < points.length) {
      final barRect = _UsageGraphGeometry.barRect(points, hoverIndex, layout);
      if (barRect.height > 0.0) {
        _paintTooltip(canvas, dateLabel: hoverDateLabel, valueLabel: hoverLabel, tip: Offset(barRect.center.dx, barRect.top), size: size);
      }
    }

    final first = points.first.periodStart;
    final last = points.last.periodStart;
    _paintText(
      canvas,
      _formatAxisDate(first),
      Offset(chartRect.left, chartRect.bottom + layout.axisDateOffset),
      _UsageGraphGeometry.axisDateStyle(theme),
    );

    final lastPainter = _textPainter(_formatAxisDate(last), _UsageGraphGeometry.axisDateStyle(theme), TextAlign.right)..layout();
    lastPainter.paint(canvas, Offset(chartRect.right - lastPainter.width, chartRect.bottom + layout.axisDateOffset));
  }

  void _paintFigureFrame(Canvas canvas, Rect rect) {
    final surfacePaint = Paint()..color = _UsageGraphGeometry.chartSurfaceColor(theme);
    final edgePaint = Paint()
      ..color = _UsageGraphGeometry.chartEdgeColor(theme)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRect(rect, surfacePaint);
    canvas.drawRect(rect, edgePaint);
  }

  void _paintAverageReference(Canvas canvas, Rect chartRect) {
    final referenceValue = averageValue;
    final referenceLabel = averageLabel;
    if (referenceValue == null || referenceLabel == null) {
      return;
    }

    final maxValue = points.fold<double>(0.0, (maxValue, point) => math.max(maxValue, point.value));
    if (maxValue <= 0.0) {
      return;
    }

    final normalized = (referenceValue / maxValue).clamp(0.0, 1.0);
    final y = chartRect.bottom - (chartRect.height * normalized);
    final linePaint = Paint()
      ..color = _UsageGraphGeometry.averageLineColor(theme)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1;
    _paintDashedLine(canvas, Offset(chartRect.left, y), Offset(chartRect.right, y), linePaint);

    final label = 'avg $referenceLabel';
    final labelStyle = _UsageGraphGeometry.referenceLabelStyle(theme);
    final labelPainter = _textPainter(label, labelStyle, TextAlign.right)..layout();
    final labelY = (y - labelPainter.height - 4).clamp(chartRect.top, chartRect.bottom - labelPainter.height).toDouble();
    labelPainter.paint(canvas, Offset(chartRect.right - labelPainter.width, labelY));
  }

  void _paintHighlightedBarSegment(
    Canvas canvas, {
    required Rect rect,
    required double totalValue,
    required double highlightedValue,
    required Color barColor,
  }) {
    if (rect.height <= 0.0 || totalValue <= 0.0 || highlightedValue <= 0.0) {
      return;
    }

    final normalized = (highlightedValue / totalValue).clamp(0.0, 1.0);
    final segmentHeight = rect.height * normalized;
    final segmentRect = Rect.fromLTRB(rect.left, rect.bottom - segmentHeight, rect.right, rect.bottom);
    final segmentColor = Color.lerp(barColor, theme.colorScheme.foreground, 0.48)!;
    canvas.drawRect(segmentRect, Paint()..color = segmentColor);
  }

  Map<DateTime, double> _valuesByPeriod(List<UsageGraphPoint> points) {
    final valuesByPeriod = <DateTime, double>{};
    for (final point in points) {
      final key = _periodKey(point.periodStart, usesHourlyLabels);
      valuesByPeriod[key] = (valuesByPeriod[key] ?? 0.0) + point.value;
    }
    return valuesByPeriod;
  }

  void _paintDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 4.0;
    const dashGap = 5.0;
    var x = start.dx;
    while (x < end.dx) {
      canvas.drawLine(Offset(x, start.dy), Offset(math.min(x + dashWidth, end.dx), end.dy), paint);
      x += dashWidth + dashGap;
    }
  }

  void _paintTooltip(Canvas canvas, {required String dateLabel, required String valueLabel, required Offset tip, required Size size}) {
    final dateStyle = theme.textTheme.small.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: _UsageGraphGeometry.labelTextColor(theme),
    );
    final valueStyle = theme.textTheme.small.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: _UsageGraphGeometry.valueTextColor(theme),
    );
    final datePainter = _textPainter(dateLabel, dateStyle, TextAlign.center)..layout();
    final valuePainter = _textPainter(valueLabel, valueStyle, TextAlign.center)..layout();
    const horizontalPadding = 10.0;
    const verticalPadding = 7.0;
    const lineGap = 2.0;
    const notchHeight = 7.0;
    const notchWidth = 12.0;
    const gap = 6.0;
    const radius = 6.0;
    final contentWidth = math.max(datePainter.width, valuePainter.width);
    final contentHeight = datePainter.height + lineGap + valuePainter.height;
    final bubbleWidth = contentWidth + (horizontalPadding * 2);
    final bubbleHeight = contentHeight + (verticalPadding * 2);
    final minLeft = _UsageGraphGeometry.horizontalPadding;
    final maxLeft = math.max(minLeft, size.width - _UsageGraphGeometry.horizontalPadding - bubbleWidth);
    final left = (tip.dx - (bubbleWidth / 2)).clamp(minLeft, maxLeft).toDouble();
    final top = math.max(4.0, tip.dy - bubbleHeight - notchHeight - gap);
    final bubbleRect = Rect.fromLTWH(left, top, bubbleWidth, bubbleHeight);
    final notchCenterX = tip.dx.clamp(bubbleRect.left + radius + notchWidth, bubbleRect.right - radius - notchWidth).toDouble();
    final notchBaseY = bubbleRect.bottom;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(bubbleRect, const Radius.circular(radius)))
      ..moveTo(notchCenterX - (notchWidth / 2), notchBaseY)
      ..lineTo(notchCenterX, notchBaseY + notchHeight)
      ..lineTo(notchCenterX + (notchWidth / 2), notchBaseY)
      ..close();
    final shadowPaint = Paint()
      ..color = theme.colorScheme.foreground.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final fillPaint = Paint()..color = theme.colorScheme.card;
    final borderPaint = Paint()
      ..color = theme.colorScheme.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawPath(path.shift(const Offset(0, 2)), shadowPaint);
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
    final contentLeft = bubbleRect.left + horizontalPadding;
    final contentTop = bubbleRect.top + verticalPadding;
    datePainter.paint(canvas, Offset(contentLeft + ((contentWidth - datePainter.width) / 2), contentTop));
    valuePainter.paint(canvas, Offset(contentLeft + ((contentWidth - valuePainter.width) / 2), contentTop + datePainter.height + lineGap));
  }

  void _paintText(Canvas canvas, String text, Offset offset, TextStyle style, {TextAlign align = TextAlign.left}) {
    final painter = _textPainter(text, style, align)..layout(maxWidth: math.max(0.0, 280.0));
    painter.paint(canvas, offset);
  }

  TextPainter _textPainter(String text, TextStyle style, TextAlign align) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
  }

  String _formatAxisDate(DateTime date) => _formatPeriodLabel(date, usesHourlyLabels);

  @override
  bool shouldRepaint(covariant _UsageGraphPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.highlightedPoints != highlightedPoints ||
        oldDelegate.title != title ||
        oldDelegate.totalLabel != totalLabel ||
        oldDelegate.averageValue != averageValue ||
        oldDelegate.averageLabel != averageLabel ||
        oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.hoveredLabel != hoveredLabel ||
        oldDelegate.hoveredDateLabel != hoveredDateLabel ||
        oldDelegate.usesHourlyLabels != usesHourlyLabels ||
        oldDelegate.layout != layout ||
        oldDelegate.theme != theme;
  }
}

bool _usesHourlyLabels(List<UsageGraphPoint> points) {
  if (points.length < 2) {
    return false;
  }
  for (var i = 1; i < points.length; i++) {
    final previous = points[i - 1].periodStart;
    final current = points[i].periodStart;
    final delta = current.difference(previous).abs();
    if (delta < const Duration(hours: 23)) {
      return true;
    }
  }
  return false;
}

DateTime _periodKey(DateTime date, bool hourly) {
  return hourly ? _hourKey(date) : _dayKey(date);
}

DateTime _dayKey(DateTime date) {
  final localDate = date.toLocal();
  return DateTime(localDate.year, localDate.month, localDate.day);
}

DateTime _hourKey(DateTime date) {
  final localDate = date.toLocal();
  return DateTime(localDate.year, localDate.month, localDate.day, localDate.hour);
}

bool _isCurrentPeriod(DateTime date, bool hourly) {
  final now = DateTime.now();
  final localDate = date.toLocal();
  if (localDate.year != now.year || localDate.month != now.month || localDate.day != now.day) {
    return false;
  }
  return !hourly || localDate.hour == now.hour;
}

String _formatPeriodLabel(DateTime date, bool hourly) {
  final localDate = date.toLocal();
  return hourly ? DateFormat.MMMd().add_j().format(localDate) : DateFormat.MMMd().format(localDate);
}
