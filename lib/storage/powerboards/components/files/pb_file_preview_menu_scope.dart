import 'package:flutter/widgets.dart';

class PbFilePreviewMenuScope extends InheritedNotifier<ValueNotifier<bool>> {
  const PbFilePreviewMenuScope({super.key, required ValueNotifier<bool> notifier, required super.child}) : super(notifier: notifier);

  static bool menuOpen(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PbFilePreviewMenuScope>();
    return scope?.notifier?.value ?? false;
  }
}
