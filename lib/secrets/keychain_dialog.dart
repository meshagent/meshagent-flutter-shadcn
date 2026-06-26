import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../forms/metadata_editors.dart';
import '../ui/coordinated_context_menu.dart';

const _customSecretType = '__custom__';

const _secretTypeOptions = <_SecretTypeOption>[
  _SecretTypeOption(label: 'Opaque', value: 'opaque'),
  _SecretTypeOption(label: 'OAuth credentials', value: 'oauth'),
  _SecretTypeOption(label: 'Text', value: 'text/plain'),
  _SecretTypeOption(label: 'JSON', value: 'application/json'),
  _SecretTypeOption(label: 'Binary', value: 'application/octet-stream'),
];

class KeychainDialog extends StatelessWidget {
  const KeychainDialog({super.key, required this.client, required this.projectId});

  final Meshagent client;
  final String projectId;

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: const Text('Keychain'),
      description: const Text('Manage user secrets and proxy access for service accounts.'),
      constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
      actions: [ShadButton.outline(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      child: SizedBox(
        width: 820,
        height: 560,
        child: UserSecretsPane(client: client, projectId: projectId),
      ),
    );
  }
}

class UserSecretsPane extends StatefulWidget {
  const UserSecretsPane({super.key, required this.client, required this.projectId});

  final Meshagent client;
  final String projectId;

  @override
  State<UserSecretsPane> createState() => _UserSecretsPaneState();
}

class _UserSecretsPaneState extends State<UserSecretsPane> {
  late Future<_UserSecretsData> _future;
  String _filter = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _error = null;
      _future = _load();
    });
  }

  Future<_UserSecretsData> _load() async {
    final results = await Future.wait([
      widget.client.listUserSecrets(pageSize: 100, filter: _filter.trim().isEmpty ? null : _filter.trim()),
      widget.client.listServiceAccountsPage(widget.projectId, pageSize: 100),
    ]);
    return _UserSecretsData(
      secrets: (results[0] as SecretsPage).secrets,
      serviceAccounts: (results[1] as ServiceAccountsPage).serviceAccounts,
    );
  }

  Future<void> _openEditDialog({Secret? secret}) async {
    final saved = await showShadSheet<Secret>(
      context: context,
      side: ShadSheetSide.right,
      builder: (context) => UserSecretEditorSheet(client: widget.client, projectId: widget.projectId, secret: secret),
    );
    if (saved != null) {
      _reload();
    }
  }

  Future<void> _openPermissions(Secret secret, List<ServiceAccount> serviceAccounts) async {
    await showShadSheet<void>(
      context: context,
      side: ShadSheetSide.right,
      builder: (context) => _SecretPermissionsSheet(
        client: widget.client,
        projectId: widget.projectId,
        secret: secret,
        serviceAccounts: serviceAccounts,
        onChanged: _reload,
      ),
    );
  }

  Future<void> _deleteSecret(Secret secret) async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Delete Secret'),
        description: Text('Delete "${secret.name}"? This cannot be undone.'),
        actions: [
          ShadButton.outline(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ShadButton.destructive(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.client.deleteUserSecret(secret.id);
      if (!mounted) return;
      _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: FutureBuilder<_UserSecretsData>(
        future: _future,
        builder: (context, snapshot) {
          final theme = ShadTheme.of(context);
          final data = snapshot.data;
          final secrets = data?.secrets ?? const <Secret>[];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      key: const Key('user-secrets-search'),
                      placeholder: const Text('Search secrets'),
                      onChanged: (value) {
                        _filter = value;
                        _reload();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadButton(
                    key: const Key('new-user-secret'),
                    onPressed: () => _openEditDialog(),
                    leading: const Icon(LucideIcons.plus),
                    child: const Text('New Secret'),
                  ),
                  const SizedBox(width: 8),
                  ShadIconButton.outline(onPressed: _reload, icon: const Icon(LucideIcons.refreshCw)),
                ],
              ),
              if (_error != null) ...[const SizedBox(height: 12), ShadAlert.destructive(description: Text(_error!))],
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: snapshot.hasError
                      ? Center(child: Text(_friendlyError(snapshot.error!)))
                      : snapshot.connectionState == ConnectionState.waiting && data == null
                      ? const Center(child: CircularProgressIndicator())
                      : secrets.isEmpty
                      ? const Center(child: Text('No secrets found'))
                      : Column(
                          children: [
                            _SecretListHeader(theme: theme),
                            Divider(height: 1, color: theme.colorScheme.border),
                            Expanded(
                              child: ListView.separated(
                                itemCount: secrets.length,
                                separatorBuilder: (_, _) => Divider(height: 1, color: theme.colorScheme.border),
                                itemBuilder: (context, index) {
                                  final secret = secrets[index];
                                  return _SecretListRow(
                                    secret: secret,
                                    onEdit: () => _openEditDialog(secret: secret),
                                    onPermissions: () => _openPermissions(secret, data?.serviceAccounts ?? const <ServiceAccount>[]),
                                    onDelete: () => _deleteSecret(secret),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SecretListHeader extends StatelessWidget {
  const _SecretListHeader({required this.theme});

  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text('Name', style: theme.textTheme.small.copyWith(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 2,
            child: Text('Type', style: theme.textTheme.small.copyWith(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 3,
            child: Text('Version', style: theme.textTheme.small.copyWith(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 2,
            child: Text('Properties', style: theme.textTheme.small.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }
}

class _SecretListRow extends StatelessWidget {
  const _SecretListRow({required this.secret, required this.onEdit, required this.onPermissions, required this.onDelete});

  final Secret secret;
  final VoidCallback onEdit;
  final VoidCallback onPermissions;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(secret.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(secret.type, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 3, child: Text(secret.currentVersionId ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(secret.httpOnly ? 'HTTP only' : '-', maxLines: 1, overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: 36,
            child: _SecretActionsButton(onEdit: onEdit, onPermissions: onPermissions, onDelete: onDelete),
          ),
        ],
      ),
    );
  }
}

class _SecretActionsButton extends StatefulWidget {
  const _SecretActionsButton({required this.onEdit, required this.onPermissions, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onPermissions;
  final VoidCallback onDelete;

  @override
  State<_SecretActionsButton> createState() => _SecretActionsButtonState();
}

class _SecretActionsButtonState extends State<_SecretActionsButton> {
  final ShadContextMenuController _controller = ShadContextMenuController();

  @override
  Widget build(BuildContext context) {
    return CoordinatedShadContextMenu(
      controller: _controller,
      constraints: const BoxConstraints(minWidth: 180),
      estimatedMenuWidth: 180,
      estimatedMenuHeight: 120,
      items: [
        ShadContextMenuItem(leading: const Icon(LucideIcons.pencil, size: 16), onPressed: widget.onEdit, child: const Text('Edit')),
        ShadContextMenuItem(
          leading: const Icon(LucideIcons.shield, size: 16),
          onPressed: widget.onPermissions,
          child: const Text('Permissions...'),
        ),
        ShadContextMenuItem(leading: const Icon(LucideIcons.trash, size: 16), onPressed: widget.onDelete, child: const Text('Delete')),
      ],
      child: ShadIconButton.ghost(
        width: 32,
        height: 32,
        onPressed: () => _controller.toggle(),
        icon: const Icon(LucideIcons.ellipsisVertical, size: 16),
      ),
    );
  }
}

class _SecretPermissionsSheet extends StatefulWidget {
  const _SecretPermissionsSheet({
    required this.client,
    required this.projectId,
    required this.secret,
    required this.serviceAccounts,
    required this.onChanged,
  });

  final Meshagent client;
  final String projectId;
  final Secret secret;
  final List<ServiceAccount> serviceAccounts;
  final VoidCallback onChanged;

  @override
  State<_SecretPermissionsSheet> createState() => _SecretPermissionsSheetState();
}

class _SecretPermissionsSheetState extends State<_SecretPermissionsSheet> {
  late Future<List<ProjectRoomGrant>> _accessFuture;
  AccessSubject? _subject;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reloadAccess();
  }

  void _reloadAccess() {
    setState(() {
      _error = null;
      _accessFuture = widget.client.getResourcePolicy(projectId: widget.projectId, resourceType: 'secret', resourceId: widget.secret.id);
    });
  }

  Future<void> _grant() async {
    final subject = _subject;
    if (subject == null) {
      setState(() => _error = 'Select a service account.');
      return;
    }
    try {
      await widget.client.grantResourcePolicy(
        projectId: widget.projectId,
        resourceType: 'secret',
        resourceId: widget.secret.id,
        subject: subject,
        roles: const ['use_proxy'],
      );
      if (!mounted) return;
      _reloadAccess();
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _revoke(AccessSubject subject) async {
    try {
      await widget.client.revokeResourcePolicy(
        projectId: widget.projectId,
        resourceType: 'secret',
        resourceId: widget.secret.id,
        subject: subject,
      );
      if (!mounted) return;
      _reloadAccess();
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final subjects = [
      AccessSubject(type: 'userset', id: widget.projectId, objectType: 'project', relation: 'service_account'),
      for (final account in widget.serviceAccounts)
        AccessSubject(type: 'service_account', id: account.id, name: account.name, email: account.email),
    ];
    return ShadSheet(
      scrollable: false,
      title: Text('${widget.secret.name} permissions'),
      description: const Text('Manage which service accounts can use this secret through the proxy.'),
      constraints: const BoxConstraints(minWidth: 560, maxWidth: 560),
      child: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ShadSelect<String>(
                    key: const Key('secret-proxy-service-account'),
                    initialValue: _subject == null ? null : _secretProxySubjectKey(_subject!),
                    minWidth: 280,
                    placeholder: const Text('Service account'),
                    selectedOptionBuilder: (context, value) {
                      final subject = _secretProxySubjectByKey(subjects, value);
                      return Text(
                        subject == null ? value : _secretProxySubjectLabel(subject, widget.serviceAccounts),
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                    options: [
                      for (final subject in subjects)
                        ShadOption<String>(
                          value: _secretProxySubjectKey(subject),
                          child: Text(_secretProxySubjectLabel(subject, widget.serviceAccounts), overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _subject = value == null ? null : _secretProxySubjectByKey(subjects, value);
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                ShadButton(
                  key: const Key('grant-secret-proxy-access'),
                  onPressed: _grant,
                  leading: const Icon(LucideIcons.plus),
                  child: const Text('Add'),
                ),
              ],
            ),
            if (_error != null) ...[const SizedBox(height: 12), ShadAlert.destructive(description: Text(_error!))],
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<ProjectRoomGrant>>(
                future: _accessFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text(_friendlyError(snapshot.error!)));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final grants = snapshot.data!;
                  if (grants.isEmpty) {
                    return const Center(child: Text('No service accounts have proxy access.'));
                  }
                  return ListView.separated(
                    itemCount: grants.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: theme.colorScheme.border),
                    itemBuilder: (context, index) {
                      final grant = grants[index];
                      final subject = grant.subject;
                      final subjectKey = _secretProxySubjectKey(subject);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _secretProxySubjectLabel(subject, widget.serviceAccounts),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    grant.directRoles.join(', '),
                                    style: theme.textTheme.muted,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            ShadButton.outline(
                              key: Key('revoke-secret-proxy-access-$subjectKey'),
                              onPressed: () => _revoke(subject),
                              leading: const Icon(LucideIcons.circleX),
                              child: const Text('Revoke'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UserSecretEditorSheet extends StatefulWidget {
  const UserSecretEditorSheet({super.key, required this.client, required this.projectId, this.secret});

  final Meshagent client;
  final String projectId;
  final Secret? secret;

  @override
  State<UserSecretEditorSheet> createState() => _UserSecretEditorSheetState();
}

class _UserSecretEditorSheetState extends State<UserSecretEditorSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.secret?.name ?? '');
  late final TextEditingController _customType = TextEditingController(text: _initialCustomType);
  late final JsonMetadataEditingController _metadata = JsonMetadataEditingController(
    value: widget.secret?.metadata ?? const <String, dynamic>{},
  );
  late Map<String, String> _annotations = _stringAnnotations(widget.secret?.annotations ?? const <String, dynamic>{});
  final TextEditingController _value = TextEditingController();
  late String _selectedType = _initialSelectedType;
  late bool _httpOnly = widget.secret?.httpOnly ?? false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.secret != null;
  String get _initialSelectedType {
    final type = widget.secret?.type;
    if (type == null || type.isEmpty) {
      return 'opaque';
    }
    return _secretTypeOptions.any((option) => option.value == type) ? type : _customSecretType;
  }

  String get _initialCustomType {
    final type = widget.secret?.type;
    if (type == null || type.isEmpty) {
      return '';
    }
    return _secretTypeOptions.any((option) => option.value == type) ? '' : type;
  }

  @override
  void dispose() {
    _name.dispose();
    _customType.dispose();
    _metadata.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final type = _selectedType == _customSecretType ? _customType.text.trim() : _selectedType;
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (type.isEmpty) {
      setState(() => _error = 'Type is required.');
      return;
    }
    final Map<String, dynamic> metadata;
    try {
      metadata = _metadata.parse(label: 'Metadata');
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final Secret secret;
      if (_editing) {
        secret = await widget.client.updateUserSecret(
          widget.secret!.id,
          name: name,
          type: type,
          httpOnly: _httpOnly,
          metadata: metadata,
          annotations: Map<String, dynamic>.from(_annotations),
        );
      } else {
        secret = await widget.client.createUserSecret(
          projectId: widget.projectId,
          name: name,
          type: type,
          httpOnly: _httpOnly,
          metadata: metadata,
          annotations: Map<String, dynamic>.from(_annotations),
        );
      }

      if (_value.text.isNotEmpty) {
        await widget.client.createUserSecretVersion(secret.id, value: Uint8List.fromList(utf8.encode(_value.text)));
      }

      if (!mounted) return;
      Navigator.of(context).pop(secret);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShadSheet(
      scrollable: false,
      title: Text(_editing ? 'Edit Secret' : 'New Secret'),
      description: Text(_editing ? 'Update metadata or set a new secret value.' : 'Create a user-owned secret.'),
      constraints: const BoxConstraints(minWidth: 560, maxWidth: 560),
      actions: [
        ShadButton.outline(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ShadButton(key: const Key('save-user-secret'), onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save')),
      ],
      child: SizedBox(
        width: 560,
        child: Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LabeledField(
                  label: 'Name',
                  child: ShadInput(key: const Key('secret-name-input'), controller: _name, placeholder: const Text('Secret name')),
                ),
                const SizedBox(height: 10),
                _LabeledField(
                  label: 'Type',
                  child: ShadSelect<String>(
                    key: const Key('secret-type-select'),
                    initialValue: _selectedType,
                    minWidth: 300,
                    selectedOptionBuilder: (context, value) => Text(_secretTypeLabel(value)),
                    options: [
                      for (final option in _secretTypeOptions) ShadOption<String>(value: option.value, child: Text(option.label)),
                      const ShadOption<String>(value: _customSecretType, child: Text('Custom')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedType = value);
                    },
                  ),
                ),
                if (_selectedType == _customSecretType) ...[
                  const SizedBox(height: 10),
                  _LabeledField(
                    label: 'Custom type',
                    child: ShadInput(
                      key: const Key('secret-custom-type-input'),
                      controller: _customType,
                      placeholder: const Text('application/x-custom-secret'),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _LabeledField(
                  label: _editing ? 'New value' : 'Value',
                  child: ShadTextarea(
                    key: const Key('secret-value-input'),
                    controller: _value,
                    placeholder: Text(_editing ? 'Optional. Saving a value creates a new version.' : 'Secret value'),
                    minHeight: 120,
                    maxHeight: 220,
                  ),
                ),
                const SizedBox(height: 10),
                _LabeledField(
                  label: 'Metadata',
                  child: JsonMetadataEditor(key: const Key('secret-metadata-input'), controller: _metadata, minHeight: 100, maxHeight: 180),
                ),
                const SizedBox(height: 10),
                AnnotationsField(
                  key: const Key('secret-annotations-input'),
                  value: _annotations,
                  onChanged: (value) => setState(() => _annotations = value),
                ),
                const SizedBox(height: 10),
                ShadCheckbox(label: const Text('HTTP only'), value: _httpOnly, onChanged: (value) => setState(() => _httpOnly = value)),
                if (_error != null) ...[const SizedBox(height: 10), ShadAlert.destructive(description: Text(_error!))],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.small),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _UserSecretsData {
  const _UserSecretsData({required this.secrets, required this.serviceAccounts});

  final List<Secret> secrets;
  final List<ServiceAccount> serviceAccounts;
}

class _SecretTypeOption {
  const _SecretTypeOption({required this.label, required this.value});

  final String label;
  final String value;
}

ServiceAccount? _serviceAccountById(List<ServiceAccount> accounts, String id) {
  for (final account in accounts) {
    if (account.id == id) {
      return account;
    }
  }
  return null;
}

String _serviceAccountLabel(ServiceAccount account) {
  final name = account.displayName ?? account.name;
  final email = account.email;
  if (email == null || email.isEmpty || email == name) {
    return name;
  }
  return '$name <$email>';
}

String _secretProxySubjectKey(AccessSubject subject) {
  if (subject.type == 'userset') {
    return '${subject.type}:${subject.objectType ?? ''}:${subject.id}:${subject.relation ?? ''}';
  }
  return '${subject.type}:${subject.id}';
}

AccessSubject? _secretProxySubjectByKey(List<AccessSubject> subjects, String key) {
  for (final subject in subjects) {
    if (_secretProxySubjectKey(subject) == key) {
      return subject;
    }
  }
  return null;
}

String _secretProxySubjectLabel(AccessSubject subject, List<ServiceAccount> serviceAccounts) {
  if (subject.type == 'userset' && subject.objectType == 'project' && subject.relation == 'service_account') {
    return 'All service accounts';
  }
  if (subject.type == 'service_account') {
    final account = _serviceAccountById(serviceAccounts, subject.id);
    if (account != null) {
      return _serviceAccountLabel(account);
    }
  }
  return subject.email ?? subject.name ?? subject.id;
}

String _secretTypeLabel(String value) {
  for (final option in _secretTypeOptions) {
    if (option.value == value) {
      return option.label;
    }
  }
  if (value == _customSecretType) {
    return 'Custom';
  }
  return value;
}

String _friendlyError(Object error) {
  if (error is MeshagentException) {
    return error.displayMessage;
  }
  final message = '$error';
  const prefix = 'Exception: ';
  return message.startsWith(prefix) ? message.substring(prefix.length) : message;
}

Map<String, String> _stringAnnotations(Map<String, dynamic> value) {
  return {for (final entry in value.entries) entry.key: _annotationValueToString(entry.value)};
}

String _annotationValueToString(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return jsonEncode(value);
}
