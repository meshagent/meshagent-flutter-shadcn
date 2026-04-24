import 'package:cached_value/cached_value.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/style/style.dart';
import '../../helpers/label_generator.dart';
import 'header_label_scope.dart';

/// When a header has an extent with less than this value,
/// it should not render a label.
const _kMinimalLabelRenderingThreshold = 10.0;

enum HeaderStyleState { normal, selected, highlighted }

class HeaderItem extends StatefulWidget {
  final HeaderStyleState styleState;

  /// The global index of this header.
  final int index;

  /// The axis in which this item is in.
  /// It defines if this is whether a column
  final Axis axis;

  /// The size in pixels that this item will assume in the main axis [axis].
  final double extent;

  final SwayzeStyle swayzeStyle;

  const HeaderItem({
    Key? key,
    required this.index,
    required this.axis,
    required this.extent,
    required this.styleState,
    required this.swayzeStyle,
  }) : super(key: key);

  @override
  State<HeaderItem> createState() => _HeaderItemState();
}

class _HeaderItemState extends State<HeaderItem> {
  SwayzeHeaderPalette _getHeaderPalette(SwayzeStyle swayzeStyle, HeaderStyleState mode) {
    if (widget.styleState == HeaderStyleState.selected) {
      return swayzeStyle.selectedHeaderPalette;
    }

    if (widget.styleState == HeaderStyleState.highlighted) {
      return swayzeStyle.highlightedHeaderPalette;
    }

    return swayzeStyle.defaultHeaderPalette;
  }

  @override
  Widget build(BuildContext context) {
    final label =
        SwayzeHeaderLabelScope.maybeOf(context)?.labelFor(axis: widget.axis, index: widget.index) ??
        generateLabelForIndex(widget.axis, widget.index);
    final swayzeStyle = widget.swayzeStyle;
    final headerPalette = _getHeaderPalette(swayzeStyle, widget.styleState);
    final textStyle = swayzeStyle.headerTextStyle.copyWith(color: headerPalette.foreground);

    return _HeaderItemPainter(
      textStyle: textStyle,
      backgroundColor: widget.styleState != HeaderStyleState.normal ? headerPalette.background : null,
      axis: widget.axis,
      extent: widget.extent,
      index: widget.index,
      label: label,
      padding: widget.axis == Axis.horizontal ? swayzeStyle.columnHeaderPadding : swayzeStyle.rowHeaderPadding,
      swayzeStyle: swayzeStyle,
    );
  }
}

/// Represents a single item in a [Header] display.
///
/// It renders a [_HeaderSeparator] on its trailing edge.
class _HeaderItemPainter extends SingleChildRenderObjectWidget {
  /// The global index of this header.
  final int index;

  /// The axis in which this item is in.
  /// It defines if this is whether a column
  final Axis axis;

  /// The size in pixels that this item will assume in the main axis [axis].
  final double extent;

  final TextStyle textStyle;
  final Color? backgroundColor;
  final String label;
  final EdgeInsets padding;
  final SwayzeStyle swayzeStyle;

  _HeaderItemPainter({
    Key? key,
    required this.index,
    required this.axis,
    required this.extent,
    required this.textStyle,
    required this.label,
    required this.padding,
    this.backgroundColor,
    required this.swayzeStyle,
  }) : super(
         key: key,
         child: _HeaderSeparator(swayzeStyle: swayzeStyle),
       );

  @override
  _RenderHeaderItem createRenderObject(BuildContext context) {
    return _RenderHeaderItem(
      axis: axis,
      textStyle: textStyle,
      backgroundColor: backgroundColor,
      mainAxisExtent: extent,
      label: label,
      padding: padding,
      cellSeparatorStrokeWidth: swayzeStyle.cellSeparatorStrokeWidth,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderHeaderItem renderObject) {
    super.updateRenderObject(context, renderObject);
    renderObject.axis = axis;
    renderObject.label = label;
    renderObject.backgroundColor = backgroundColor;
    renderObject.textStyle = textStyle;
    renderObject.mainAxisExtent = extent;
    renderObject.padding = padding;
    renderObject.cellSeparatorStrokeWidth = swayzeStyle.cellSeparatorStrokeWidth;
  }
}

class _RenderHeaderItem extends RenderBox with RenderObjectWithChildMixin<RenderBox> {
  String _label;

  String get label => _label;

  set label(String value) {
    if (_label == value) {
      return;
    }
    _label = value;
    markNeedsSemanticsUpdate();
    markNeedsPaint();
  }

  /// The axis in which this item is in.
  /// It defines if this is whether a column or a row.
  Axis _axis;

  Axis get axis => _axis;

  set axis(Axis value) {
    _axis = value;
    markNeedsLayout();
  }

  /// TextStyle to be applied to the header.
  TextStyle _textStyle;

  TextStyle get textStyle => _textStyle;

  set textStyle(TextStyle value) {
    _textStyle = value;
    markNeedsLayout();
  }

  /// The extend of the header in the main axis
  double _mainAxisExtent;

  double get mainAxisExtent => _mainAxisExtent;

  set mainAxisExtent(double value) {
    _mainAxisExtent = value;
    markNeedsLayout();
  }

  EdgeInsets _padding;

  EdgeInsets get padding => _padding;

  set padding(EdgeInsets value) {
    if (_padding == value) {
      return;
    }
    _padding = value;
    markNeedsLayout();
  }

  /// Background color is given by the parent widget and on the setter method
  ///
  /// Background changes do not alter the shape of the header, therefore it
  /// only needs to be marked for paint and not layout.
  Color? _backgroundColor;

  Color? get backgroundColor => _backgroundColor;

  set backgroundColor(Color? value) {
    _backgroundColor = value;
    markNeedsPaint();
  }

  /// See [SwayzeStyle.cellSeparatorStrokeWidth]
  double _cellSeparatorStrokeWidth;

  double get cellSeparatorStrokeWidth => _cellSeparatorStrokeWidth;

  set cellSeparatorStrokeWidth(double value) {
    _cellSeparatorStrokeWidth = value;
    markNeedsPaint();
  }

  late final backgroundPaintCache = CachedValue(() {
    if (backgroundColor == null) {
      return null;
    }
    return Paint()
      ..color = backgroundColor!
      ..style = PaintingStyle.fill;
  }).withDependency<Color?>(() => backgroundColor);

  /// Text painters may be a little expensive for the paint cycle.
  /// This field caches it to be reused across frames.
  late final textPainterCache =
      CachedValue(() {
            final textSpan = TextSpan(text: label, style: textStyle);
            final contentWidth = (size.width - padding.horizontal).clamp(0.0, double.infinity) as double;

            return TextPainter(
              text: textSpan,
              textAlign: axis == Axis.horizontal ? TextAlign.left : TextAlign.center,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              ellipsis: '...',
            )..layout(minWidth: 0, maxWidth: contentWidth);
          })
          .withDependency<String>(() => label)
          .withDependency<TextStyle>(() => textStyle)
          .withDependency<Size>(() => size)
          .withDependency<EdgeInsets>(() => padding)
          .withDependency<Axis>(() => axis);

  _RenderHeaderItem({
    required Axis axis,
    required TextStyle textStyle,
    required double mainAxisExtent,
    required String label,
    required EdgeInsets padding,
    required double cellSeparatorStrokeWidth,
    Color? backgroundColor,
  }) : _axis = axis,
       _label = label,
       _textStyle = textStyle,
       _backgroundColor = backgroundColor,
       _mainAxisExtent = mainAxisExtent,
       _padding = padding,
       _cellSeparatorStrokeWidth = cellSeparatorStrokeWidth;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isReadOnly = true
      ..label = label
      ..textDirection = TextDirection.ltr;
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = axis == Axis.horizontal ? mainAxisExtent : 0.0;
    final height = axis == Axis.horizontal ? 0.0 : mainAxisExtent;
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() {
    final childSize = axis == Axis.horizontal ? Size(cellSeparatorStrokeWidth, size.height) : Size(size.width, cellSeparatorStrokeWidth);

    final childConstrains = BoxConstraints.tight(childSize);

    child!.layout(childConstrains);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);

    final backgroundPaint = backgroundPaintCache.value;

    if (backgroundPaint != null) {
      context.canvas.drawRect(offset & size, backgroundPaint);
    }

    if (mainAxisExtent >= _kMinimalLabelRenderingThreshold) {
      final textPainter = textPainterCache.value;
      final contentWidth = (size.width - padding.horizontal).clamp(0.0, double.infinity) as double;
      final contentHeight = (size.height - padding.vertical).clamp(0.0, double.infinity) as double;

      if (contentWidth > 0 && contentHeight > 0) {
        final textHorizontalOffset = switch (axis) {
          Axis.horizontal => padding.left,
          Axis.vertical => padding.left + (contentWidth - textPainter.width) / 2,
        };
        final textVerticalOffset = padding.top + (contentHeight - textPainter.height) / 2;
        textPainter.paint(context.canvas, offset + Offset(textHorizontalOffset, textVerticalOffset));
      }
    }

    final childOffset = axis == Axis.horizontal
        ? Offset(size.width - cellSeparatorStrokeWidth, 0)
        : Offset(0, size.height - cellSeparatorStrokeWidth);
    context.paintChild(child!, childOffset + offset);
  }
}

class _HeaderSeparator extends StatelessWidget {
  final SwayzeStyle swayzeStyle;

  const _HeaderSeparator({Key? key, required this.swayzeStyle}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: swayzeStyle.headerSeparatorColor);
  }
}
