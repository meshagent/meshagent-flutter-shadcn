import 'package:flutter/material.dart';

class EnableWebContextRegistry {
  static final _registry = <UniqueKey, Rect>{};

  static void register(UniqueKey id, Rect rect) {
    _registry[id] = rect;
  }

  static void unregister(UniqueKey id) {
    _registry.remove(id);
  }

  static Iterable<Rect> get rects => _registry.values;
}

class EnableWebContextMenu extends StatefulWidget {
  const EnableWebContextMenu({super.key, required this.child});

  final Widget child;

  @override
  State<EnableWebContextMenu> createState() => _EnableWebContextMenuState();
}

class _EnableWebContextMenuState extends State<EnableWebContextMenu> with WidgetsBindingObserver {
  final key = GlobalKey();
  final id = UniqueKey();

  void _updatePosition() {
    if (!mounted) {
      return;
    }

    final ctx = key.currentContext;
    if (ctx == null) {
      return;
    }

    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }

    final position = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    final rect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
    EnableWebContextRegistry.register(id, rect);
  }

  void _scheduleUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _updatePosition();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleUpdate();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _scheduleUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    EnableWebContextRegistry.unregister(id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleUpdate();
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _scheduleUpdate();
            return false;
          },
          child: Container(key: key, child: widget.child),
        ),
      ),
    );
  }
}
