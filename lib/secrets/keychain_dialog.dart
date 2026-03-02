import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _DeleteSecretButton extends StatefulWidget {
  const _DeleteSecretButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  State<_DeleteSecretButton> createState() => _DeleteSecretButtonState();
}

class _DeleteSecretButtonState extends State<_DeleteSecretButton> {
  bool isDeleting = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: isDeleting
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(LucideIcons.trash2, size: 16),
      onPressed: isDeleting
          ? null
          : () async {
              setState(() {
                isDeleting = true;
              });

              try {
                await widget.onPressed();
              } finally {
                if (mounted) {
                  setState(() {
                    isDeleting = false;
                  });
                }
              }
            },
    );
  }
}

class KeychainDialog extends StatefulWidget {
  const KeychainDialog({super.key, required this.room});

  final RoomClient room;

  @override
  State<KeychainDialog> createState() => _KeychainDialogState();
}

class _KeychainDialogState extends State<KeychainDialog> {
  late Future<List<SecretInfo>> _secretsFuture = widget.room.secrets.listSecrets();

  Future<void> _refreshSecrets() async {
    setState(() {
      _secretsFuture = widget.room.secrets.listSecrets();
    });
  }

  List<ShadTableCell> _header(TextStyle style) => [
    ShadTableCell(child: Text('Name', style: style)),
    ShadTableCell(child: Text('Delegated To', style: style)),
    ShadTableCell(child: Text('')),
  ];

  List<ShadTableCell> _row(SecretInfo secret) => [
    ShadTableCell(child: Text(secret.name, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ShadTableCell(child: Text(secret.delegatedTo ?? 'N/A', softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ShadTableCell(
      alignment: Alignment.centerRight,
      child: _DeleteSecretButton(
        onPressed: () async {
          await widget.room.secrets.deleteSecret(secretId: secret.id, delegatedTo: secret.delegatedTo);
          await _refreshSecrets();
        },
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SecretInfo>>(
      future: _secretsFuture,
      builder: (context, snapshot) {
        final theme = ShadTheme.of(context);
        final tt = theme.textTheme;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return ShadDialog(
            title: const Text('Keychain'),
            description: Text('Failed to load saved connections: ${snapshot.error}'),
            actions: [ShadButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
          );
        }

        final secrets = snapshot.data ?? const <SecretInfo>[];

        return ShadDialog(
          title: const Text('Keychain'),
          description: const Text('If you connect this room to an external application, you can remove the connection from here.'),
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 560),
          actions: [ShadButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
          child: SizedBox(
            width: 760,
            height: 420,
            child: secrets.isEmpty
                ? Center(child: Text('No connectors found.', style: tt.muted))
                : ShadTable.list(
                    pinnedRowCount: 1,
                    header: _header(tt.small.copyWith(fontWeight: FontWeight.bold)),
                    columnSpanExtent: (index) => switch (index) {
                      0 => const FractionalSpanExtent(0.4),
                      1 => const FractionalSpanExtent(0.4),
                      _ => const FractionalSpanExtent(0.2),
                    },
                    children: secrets.map(_row),
                  ),
          ),
        );
      },
    );
  }
}
