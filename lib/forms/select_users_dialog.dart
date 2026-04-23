import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'select_users.dart';

Future<List<String>?> showSelectUsersDialog({
  required BuildContext context,
  required List<String> projectEmails,
  List<String> initialValue = const [],
  String title = 'Select users',
  String description = 'Choose one or more project users.',
  String confirmLabel = 'Apply',
  String cancelLabel = 'Cancel',
}) {
  return showShadDialog<List<String>>(
    context: context,
    builder: (context) => SelectUsersDialog(
      projectEmails: projectEmails,
      initialValue: initialValue,
      title: title,
      description: description,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
}

class SelectUsersDialog extends StatefulWidget {
  const SelectUsersDialog({
    super.key,
    required this.projectEmails,
    this.initialValue = const [],
    this.title = 'Select users',
    this.description = 'Choose one or more project users.',
    this.confirmLabel = 'Apply',
    this.cancelLabel = 'Cancel',
  });

  final List<String> projectEmails;
  final List<String> initialValue;
  final String title;
  final String description;
  final String confirmLabel;
  final String cancelLabel;

  @override
  State<SelectUsersDialog> createState() => _SelectUsersDialogState();
}

class _SelectUsersDialogState extends State<SelectUsersDialog> {
  late final controller = SelectUsersController(initialValue: widget.initialValue);
  late final textController = TextEditingController();
  final selectedUsers = ValueNotifier<List<String>>([]);

  List<String> _buildSelectedUsersResult() {
    final result = List<String>.of(controller.value);
    final pendingEmail = textController.text.trim();

    if (!SelectUsersController.emailRegex.hasMatch(pendingEmail)) {
      return result;
    }

    final exists = result.any((user) => user.toLowerCase() == pendingEmail.toLowerCase());
    if (!exists) {
      result.add(pendingEmail);
    }

    return result;
  }

  @override
  void initState() {
    super.initState();
    selectedUsers.value = List<String>.of(widget.initialValue);
  }

  @override
  void dispose() {
    controller.dispose();
    textController.dispose();
    selectedUsers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: Text(widget.title),
      description: Text(widget.description),
      constraints: const BoxConstraints(maxWidth: 560),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      actions: [
        ShadButton.outline(onPressed: () => Navigator.of(context).pop(), child: Text(widget.cancelLabel)),
        ValueListenableBuilder<List<String>>(
          valueListenable: selectedUsers,
          builder: (context, value, child) {
            return ShadButton(onPressed: () => Navigator.of(context).pop(_buildSelectedUsersResult()), child: Text(widget.confirmLabel));
          },
        ),
      ],
      child: SelectUsers(
        autofocus: true,
        projectEmails: widget.projectEmails,
        controller: controller,
        textController: textController,
        initialValue: widget.initialValue,
        onChanged: (value) {
          selectedUsers.value = value;
        },
      ),
    );
  }
}
