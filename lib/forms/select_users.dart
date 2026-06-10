import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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

enum SelectSubjectType { user, agent, group, serviceAccount, projectUsers, projectDevelopers, projectAgents }

class SelectSubjectsController extends MultiSelectController {
  SelectSubjectsController({required this.subjectsByKey, required this.allowNewUserEmail, super.initialValue});

  final Map<String, AccessSubject> subjectsByKey;
  final bool allowNewUserEmail;

  @override
  FutureOr<bool> canAddItem(String item) {
    if (subjectsByKey.containsKey(item)) {
      return true;
    }
    return allowNewUserEmail && SelectUsersController.emailRegex.hasMatch(item);
  }
}

class SelectSubjects extends StatefulWidget {
  const SelectSubjects({
    super.key,
    required this.client,
    required this.projectId,
    required this.onChanged,
    this.allowedTypes = const {SelectSubjectType.user, SelectSubjectType.agent, SelectSubjectType.group},
    this.controller,
    this.textController,
    this.autofocus = false,
    this.focusNode,
    this.initialValue = const [],
    this.allowNewUserEmail = false,
    this.maxSelected,
    this.placeholder,
  });

  final Meshagent client;
  final String projectId;
  final Set<SelectSubjectType> allowedTypes;
  final void Function(List<AccessSubject>) onChanged;
  final SelectSubjectsController? controller;
  final TextEditingController? textController;
  final bool autofocus;
  final FocusNode? focusNode;
  final List<AccessSubject> initialValue;
  final bool allowNewUserEmail;
  final int? maxSelected;
  final Widget? placeholder;

  @override
  State<SelectSubjects> createState() => _SelectSubjectsState();
}

class _SubjectOption {
  const _SubjectOption({required this.key, required this.subject, required this.label, required this.kindLabel, required this.icon});

  final String key;
  final AccessSubject subject;
  final String label;
  final String kindLabel;
  final IconData icon;
}

class _SelectSubjectsState extends State<SelectSubjects> {
  late final textController = widget.textController ?? TextEditingController();
  late final focusNode = widget.focusNode ?? FocusNode();
  late final SelectSubjectsController controller;

  final optionsByKey = <String, _SubjectOption>{};
  final subjectsByKey = <String, AccessSubject>{};

  bool updatingText = false;

  @override
  void initState() {
    super.initState();
    controller =
        widget.controller ??
        SelectSubjectsController(
          subjectsByKey: subjectsByKey,
          allowNewUserEmail: widget.allowNewUserEmail && widget.allowedTypes.contains(SelectSubjectType.user),
          initialValue: widget.initialValue.map(_subjectKey).toList(),
        );
    for (final subject in widget.initialValue) {
      _cacheOption(_optionFromSubject(subject));
    }
    textController.addListener(_onTextChanged);
    focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    textController.removeListener(_onTextChanged);
    focusNode.removeListener(_onFocusChange);
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

  static String _subjectKey(AccessSubject subject) {
    if (subject.type == 'userset') {
      return 'userset:${subject.objectType ?? ''}:${subject.id}:${subject.relation ?? ''}';
    }
    if (subject.type == 'user' && subject.id.isEmpty && subject.email != null) {
      return subject.email!;
    }
    return '${subject.type}:${subject.id}';
  }

  String _subjectLabel(AccessSubject subject) {
    final email = subject.email;
    final name = subject.name;
    final firstName = subject.firstName;
    final lastName = subject.lastName;
    final fullName = [firstName, lastName].whereType<String>().where((part) => part.trim().isNotEmpty).join(' ');
    if (email != null && email.isNotEmpty && fullName.isNotEmpty) {
      return '$fullName <$email>';
    }
    if (email != null && email.isNotEmpty && name != null && name.isNotEmpty) {
      return '$name <$email>';
    }
    if (email != null && email.isNotEmpty) {
      return email;
    }
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return subject.id;
  }

  _SubjectOption _optionFromSubject(AccessSubject subject) {
    return switch (subject.type) {
      'agent' => _SubjectOption(
        key: _subjectKey(subject),
        subject: subject,
        label: _subjectLabel(subject),
        kindLabel: 'Agent',
        icon: LucideIcons.bot,
      ),
      'group' => _SubjectOption(
        key: _subjectKey(subject),
        subject: subject,
        label: _subjectLabel(subject),
        kindLabel: 'Group',
        icon: LucideIcons.users,
      ),
      'service_account' => _SubjectOption(
        key: _subjectKey(subject),
        subject: subject,
        label: _subjectLabel(subject),
        kindLabel: 'Service Account',
        icon: LucideIcons.keyRound,
      ),
      'userset' => _SubjectOption(
        key: _subjectKey(subject),
        subject: subject,
        label: switch (subject.relation) {
          'agent' => 'All project agents',
          'developer' => 'All project developers',
          _ => 'All project users',
        },
        kindLabel: 'Project',
        icon: subject.relation == 'agent' ? LucideIcons.bot : LucideIcons.users,
      ),
      _ => _SubjectOption(
        key: _subjectKey(subject),
        subject: subject,
        label: _subjectLabel(subject),
        kindLabel: 'User',
        icon: LucideIcons.user,
      ),
    };
  }

  void _cacheOption(_SubjectOption option) {
    optionsByKey[option.key] = option;
    subjectsByKey[option.key] = option.subject;
  }

  bool _isAllowedResolvedSubject(AccessSubject subject) {
    return switch (subject.type) {
      'user' => widget.allowedTypes.contains(SelectSubjectType.user),
      'agent' => widget.allowedTypes.contains(SelectSubjectType.agent),
      'group' => widget.allowedTypes.contains(SelectSubjectType.group),
      'service_account' => widget.allowedTypes.contains(SelectSubjectType.serviceAccount),
      'userset' => true,
      _ => false,
    };
  }

  void _onTextChanged() {
    if (updatingText || !widget.allowNewUserEmail || !widget.allowedTypes.contains(SelectSubjectType.user)) {
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
    if (list.length == 1 && !(text.endsWith(' ') || text.endsWith(','))) {
      return;
    }
    for (final item in list) {
      final email = item.sanitizedAddress.trim();
      if (SelectUsersController.emailRegex.hasMatch(email)) {
        controller.add(email);
      }
    }
    updatingText = true;
    textController.clear();
    updatingText = false;
  }

  void _onFocusChange() {
    if (focusNode.hasFocus || !widget.allowNewUserEmail || !widget.allowedTypes.contains(SelectSubjectType.user)) {
      return;
    }
    final text = textController.text.trim();
    if (SelectUsersController.emailRegex.hasMatch(text)) {
      controller.add(text);
      textController.clear();
    }
  }

  AccessSubject _subjectForKey(String key) {
    final subject = subjectsByKey[key];
    if (subject != null) {
      return subject;
    }
    return AccessSubject(type: 'user', id: '', email: key);
  }

  Future<List<String>> _search(String query) async {
    final lower = query.toLowerCase();
    final options = <_SubjectOption>[];

    if (widget.allowedTypes.contains(SelectSubjectType.projectUsers)) {
      options.add(_optionFromSubject(AccessSubject(type: 'userset', id: widget.projectId, objectType: 'project', relation: 'member')));
    }
    if (widget.allowedTypes.contains(SelectSubjectType.projectDevelopers)) {
      options.add(_optionFromSubject(AccessSubject(type: 'userset', id: widget.projectId, objectType: 'project', relation: 'developer')));
    }
    if (widget.allowedTypes.contains(SelectSubjectType.projectAgents)) {
      options.add(_optionFromSubject(AccessSubject(type: 'userset', id: widget.projectId, objectType: 'project', relation: 'agent')));
    }

    final futures = <Future<void>>[];
    if (widget.allowedTypes.contains(SelectSubjectType.user)) {
      futures.add(() async {
        final users = await widget.client.getUsersInProject(widget.projectId, pageSize: 100, filter: query);
        options.addAll(
          users.map(
            (user) => _optionFromSubject(
              AccessSubject(type: 'user', id: user.id, email: user.email, firstName: user.firstName, lastName: user.lastName),
            ),
          ),
        );
      }());
    }
    if (widget.allowedTypes.contains(SelectSubjectType.agent)) {
      futures.add(() async {
        final agents = await widget.client.listAgents(projectId: widget.projectId, pageSize: 100, filter: query);
        options.addAll(agents.map((agent) => _optionFromSubject(AccessSubject(type: 'agent', id: agent.id, name: agent.name))));
      }());
    }
    if (widget.allowedTypes.contains(SelectSubjectType.group)) {
      futures.add(() async {
        final groups = await widget.client.listGroups(projectId: widget.projectId, pageSize: 100, filter: query);
        options.addAll(
          groups.map(
            (group) =>
                _optionFromSubject(AccessSubject(type: 'group', id: group.id, name: group.displayName ?? group.name, email: group.email)),
          ),
        );
      }());
    }
    if (widget.allowedTypes.contains(SelectSubjectType.serviceAccount)) {
      futures.add(() async {
        final page = await widget.client.listServiceAccountsPage(widget.projectId, pageSize: 100, filter: query);
        options.addAll(
          page.serviceAccounts.map(
            (serviceAccount) => _optionFromSubject(
              AccessSubject(
                type: 'service_account',
                id: serviceAccount.id,
                name: serviceAccount.displayName ?? serviceAccount.name,
                email: serviceAccount.email,
              ),
            ),
          ),
        );
      }());
    }

    if (SelectUsersController.emailRegex.hasMatch(query)) {
      futures.add(() async {
        try {
          final subject = await widget.client.resolveSubject(widget.projectId, query);
          if (_isAllowedResolvedSubject(subject)) {
            options.add(_optionFromSubject(subject));
          }
        } on NotFoundException {
          // Unresolved typed subjects should simply not appear in the search result.
        }
      }());
    }

    await Future.wait(futures);

    if (widget.allowNewUserEmail &&
        widget.allowedTypes.contains(SelectSubjectType.user) &&
        SelectUsersController.emailRegex.hasMatch(query)) {
      options.add(_optionFromSubject(AccessSubject(type: 'user', id: '', email: query)));
    }

    final filtered = options.where(
      (option) => query.isEmpty || option.label.toLowerCase().contains(lower) || option.kindLabel.toLowerCase().contains(lower),
    );
    final keys = <String>[];
    for (final option in filtered) {
      _cacheOption(option);
      if (!keys.contains(option.key)) {
        keys.add(option.key);
      }
    }
    return keys;
  }

  Widget _optionBuilder(BuildContext context, String key) {
    final option = optionsByKey[key];
    if (option == null) {
      return Text(key, overflow: TextOverflow.ellipsis);
    }
    final theme = ShadTheme.of(context);
    final textStyle = theme.textTheme.p.copyWith(color: theme.colorScheme.popoverForeground);
    return Row(
      children: [
        Icon(option.icon, size: 16, color: theme.colorScheme.popoverForeground),
        const SizedBox(width: 8),
        Expanded(
          child: Text(option.label, style: textStyle, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Text(option.kindLabel, style: theme.textTheme.muted.copyWith(fontSize: 12, color: theme.colorScheme.mutedForeground)),
      ],
    );
  }

  Widget _selectedItemBuilder(BuildContext context, String key) {
    final option = optionsByKey[key];
    final subject = option?.subject;
    final label = subject?.name ?? subject?.email ?? option?.label ?? key;
    return Text(label, overflow: TextOverflow.ellipsis);
  }

  @override
  Widget build(BuildContext context) => MultiSelectAutocomplete(
    controller: controller,
    textController: textController,
    autofocus: widget.autofocus,
    focusNode: focusNode,
    onChanged: (keys) => widget.onChanged(keys.map(_subjectForKey).toList()),
    initialValue: widget.initialValue.map(_subjectKey).toList(),
    placeholder: widget.placeholder ?? const Text('Search users, agents, groups, or service accounts'),
    minimumSearchLength: 0,
    maxSelected: widget.maxSelected,
    search: _search,
    optionBuilder: _optionBuilder,
    selectedItemBuilder: _selectedItemBuilder,
  );
}
