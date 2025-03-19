import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

String timeAgo(DateTime d) {
  Duration diff = DateTime.now().difference(d);
  String ago;
  if (diff.inDays > 365) {
    ago = "${(diff.inDays / 365).floor()} ${(diff.inDays / 365).floor() == 1 ? "year" : "years"}";
  } else if (diff.inDays > 30) {
    ago = "${(diff.inDays / 30).floor()} ${(diff.inDays / 30).floor() == 1 ? "month" : "months"}";
  } else if (diff.inDays > 7) {
    ago = "${(diff.inDays / 7).floor()} ${(diff.inDays / 7).floor() == 1 ? "week" : "weeks"}";
  } else if (diff.inDays > 0) {
    ago = "${diff.inDays} ${diff.inDays == 1 ? "day" : "days"}";
  } else if (diff.inHours > 0) {
    ago = "${diff.inHours} ${diff.inHours == 1 ? "hour" : "hours"}";
  } else if (diff.inMinutes > 0) {
    ago = "${diff.inMinutes} ${diff.inMinutes == 1 ? "minute" : "minutes"}";
  } else if (diff.inDays < -365) {
    ago = "${(diff.inDays / 365).floor().abs()} ${(diff.inDays / 365).floor() == -1 ? "year" : "years"}";
  } else if (diff.inDays < -30) {
    ago = "${(diff.inDays / 30).floor().abs()} ${(diff.inDays / 30).floor() == -1 ? "month" : "months"}";
  } else if (diff.inDays < -7) {
    ago = "${(diff.inDays / 7).floor().abs()} ${(diff.inDays / 7).floor() == -1 ? "week" : "weeks"}";
  } else if (diff.inDays < 0) {
    ago = "${diff.inDays.abs()} ${diff.inDays == -1 ? "day" : "days"}";
  } else if (diff.inHours < 0) {
    ago = "${diff.inHours.abs()} ${diff.inHours == -1 ? "hour" : "hours"}";
  } else if (diff.inMinutes < 0) {
    ago = "${diff.inMinutes.abs()} ${diff.inMinutes == -1 ? "minute" : "minutes"}";
  } else {
    return "just now";
  }
  if (diff.inSeconds < 0) {
    return "in $ago";
  } else {
    return "$ago ago";
  }
}

class CenteredScrollable extends StatelessWidget {
  const CenteredScrollable({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        children: [
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(20.0),
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ],
      ),
    );
  }
}

class ControlledForm extends StatefulWidget {
  const ControlledForm({super.key, required this.builder, this.initialValue = const {}, this.controller});

  final Widget Function(BuildContext context, FormController controller, GlobalKey<ShadFormState> key) builder;
  final Map<String, Object> initialValue;
  final FormController? controller;

  @override
  State createState() => _ControlledFormState();
}

class _ControlledFormState extends State<ControlledForm> {
  final key = GlobalKey<ShadFormState>();
  late final controller = widget.controller ?? FormController();

  @override
  void initState() {
    super.initState();
    controller.addListener(onControllerChanged);
  }

  void onControllerChanged() {
    if (!mounted) return;

    setState(() {});
  }

  @override
  void dispose() {
    super.dispose();
    if (controller != widget.controller) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShadForm(
      key: key,
      enabled: controller.enabled,
      initialValue: widget.initialValue,
      child: widget.builder(context, controller, key),
    );
  }
}

class FormController extends ChangeNotifier {
  FormController();

  bool _enabled = true;
  bool get enabled {
    return _enabled;
  }

  set enabled(bool value) {
    if (value != _enabled) {
      _enabled = value;
      notifyListeners();
    }
  }
}
