import 'package:flutter/material.dart';

import 'email_address.dart';
import 'multi_select_autocomplete.dart';

class SelectUsersController extends MultiSelectController {
  SelectUsersController({super.initialValue});

  static final emailRegex = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");

  @override
  bool canAddItem(String item) => emailRegex.hasMatch(item);
}

class SelectUsers extends StatefulWidget {
  const SelectUsers({
    super.key,
    required this.projectEmails,
    required this.onChanged,
    this.controller,
    this.textController,
    this.autofocus = false,
    this.focusNode,
    this.initialValue = const [],
  });

  final List<String> projectEmails;
  final void Function(List<String>) onChanged;
  final SelectUsersController? controller;
  final TextEditingController? textController;
  final bool autofocus;
  final FocusNode? focusNode;
  final List<String> initialValue;

  @override
  State createState() => _SelectUsersState();
}

class _SelectUsersState extends State<SelectUsers> {
  late final controller = widget.controller ?? SelectUsersController(initialValue: widget.initialValue);
  late final textController = widget.textController ?? TextEditingController();
  late final focusNode = widget.focusNode ?? FocusNode();

  bool updatingText = false;

  void onFocusChange() {
    if (!focusNode.hasFocus) {
      final text = textController.text.trim();
      if (text.isEmpty) {
        return;
      }

      if (SelectUsersController.emailRegex.hasMatch(text)) {
        controller.add(text);
        textController.clear();
      }
    }
  }

  void onTextChanged() {
    if (updatingText) {
      return;
    }

    final text = textController.text;
    if (text.isEmpty) {
      return;
    }

    final list = parseEmailList(text);
    if (list.isEmpty) {
      return;
    }

    if (list.length == 1) {
      if (text.endsWith(' ') || text.endsWith(',')) {
        final email = list[0].sanitizedAddress.trim();

        controller.add(email);
        textController.clear();
      }

      return;
    }

    for (int i = 0; i < list.length - 1; i++) {
      final email = list[i].sanitizedAddress.trim();

      if (SelectUsersController.emailRegex.hasMatch(email)) {
        controller.add(email);
      }
    }

    final remainder = list.last.sanitizedAddress.trim();

    updatingText = true;
    textController.value = textController.value.copyWith(
      text: remainder,
      selection: TextSelection.collapsed(offset: remainder.length),
      composing: TextRange.empty,
    );
    updatingText = false;
  }

  @override
  void initState() {
    super.initState();

    textController.addListener(onTextChanged);
    focusNode.addListener(onFocusChange);
  }

  @override
  void dispose() {
    textController.removeListener(onTextChanged);
    focusNode.removeListener(onFocusChange);

    if (widget.controller == null) {
      controller.dispose();
    }
    if (widget.focusNode == null) {
      focusNode.dispose();
    }
    if (widget.textController == null) {
      textController.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiSelectAutocomplete(
    controller: controller,
    textController: textController,
    autofocus: widget.autofocus,
    focusNode: focusNode,
    onChanged: widget.onChanged,
    initialValue: widget.initialValue,
    placeholder: const Text('Type an email'),
    minimumSearchLength: 1,
    search: (query) async {
      final users = widget.projectEmails;

      if (query.isEmpty) {
        return users;
      }

      final lower = query.toLowerCase();
      return users.where((email) => email.toLowerCase().contains(lower)).toList();
    },
  );
}
