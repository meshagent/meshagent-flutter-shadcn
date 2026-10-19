import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_solidart/flutter_solidart.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../menus/pb_menu_card.dart';
import '../primitives/pb_progress_bar.dart';
import '../primitives/pb_svg_icon.dart';
import '../../theme/pb_colors.dart';
import '../../theme/pb_typography.dart';

typedef PbUploadProgressTitleBuilder = String Function(List<UploadProgressItem> uploads, bool isCompleted);
typedef PbUploadProgressNameBuilder = String Function(UploadProgressItem item);

enum UploadProgressItemStatus { uploading, completed, failed }

class UploadProgressItem {
  UploadProgressItem({required this.upload, required this.totalBytes});

  final MeshagentFileUpload upload;
  final int totalBytes;
  UploadProgressItemStatus status = UploadProgressItemStatus.uploading;
  Object? error;

  bool get failed => status == UploadProgressItemStatus.failed;
  bool get completed => status == UploadProgressItemStatus.completed;
}

class UploadProgressNotifications {
  UploadProgressNotifications({required this.popoverController});

  final ShadPopoverController popoverController;

  final _uploads = Signal<List<UploadProgressItem>>([]);
  final _isCompleted = Signal<bool>(false);
  final _activeUploads = <Future<void>>[];

  late final isCompletedVN = _isCompleted.toValueNotifier();
  late final uploadsVN = _uploads.toValueNotifier();

  bool _running = false;
  bool _resetUploads = true;
  Timer? _autoHideTimer;

  void addUpload(MeshagentFileUpload upload, int totalBytes) {
    _autoHideTimer?.cancel();
    _isCompleted.value = false;

    final item = UploadProgressItem(upload: upload, totalBytes: totalBytes);
    _uploads.value = _resetUploads ? [item] : [..._uploads.value, item];
    _resetUploads = false;
    _activeUploads.add(
      upload.done
          .then((_) {
            item.status = UploadProgressItemStatus.completed;
            _notifyUploadsChanged();
          })
          .catchError((Object error) {
            item.status = UploadProgressItemStatus.failed;
            item.error = error;
            _notifyUploadsChanged();
          }),
    );

    _ensureRunning();
  }

  void _notifyUploadsChanged() {
    _uploads.value = [..._uploads.value];
  }

  void dispose() {
    _autoHideTimer?.cancel();
    _uploads.dispose();
    _isCompleted.dispose();
  }

  void _ensureRunning() {
    if (_running) return;

    _running = true;
    _run();
  }

  Future<void> _run() async {
    if (!popoverController.isOpen) {
      popoverController.show();
    }

    try {
      while (_activeUploads.isNotEmpty) {
        await _activeUploads.removeAt(0);
      }
      _resetUploads = true;
      _isCompleted.value = true;
      _autoHideTimer?.cancel();
      final hasFailures = _uploads.value.any((item) => item.failed);
      _autoHideTimer = Timer(Duration(seconds: hasFailures ? 6 : 3), hide);
    } finally {
      _running = false;
    }
  }

  void hide() {
    _autoHideTimer?.cancel();
    popoverController.hide();
  }
}

class PbUploadProgressPopover extends StatelessWidget {
  const PbUploadProgressPopover({
    super.key,
    required this.uploadsListenable,
    required this.isCompletedListenable,
    required this.onClose,
    required this.titleBuilder,
    required this.nameBuilder,
  });

  final ValueListenable<List<UploadProgressItem>> uploadsListenable;
  final ValueListenable<bool> isCompletedListenable;
  final VoidCallback onClose;
  final PbUploadProgressTitleBuilder titleBuilder;
  final PbUploadProgressNameBuilder nameBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<UploadProgressItem>>(
      valueListenable: uploadsListenable,
      builder: (context, uploads, _) {
        if (uploads.isEmpty) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<bool>(
          valueListenable: isCompletedListenable,
          builder: (context, isCompleted, _) {
            return PbMenuCard(
              width: 380,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: DefaultTextStyle.merge(
                  textAlign: TextAlign.left,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                titleBuilder(uploads, isCompleted),
                                textAlign: TextAlign.left,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PowerboardsTypography.label.copyWith(color: PbColors.textPrimary),
                              ),
                            ),
                          ),
                          _UploadProgressCloseButton(onPressed: onClose),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 230),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < uploads.length; i++)
                                _UploadProgressRow(item: uploads[i], name: nameBuilder(uploads[i]), isLast: i == uploads.length - 1),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _UploadProgressCloseButton extends StatefulWidget {
  const _UploadProgressCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_UploadProgressCloseButton> createState() => _UploadProgressCloseButtonState();
}

class _UploadProgressCloseButtonState extends State<_UploadProgressCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Close',
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        label: 'Close upload progress',
        button: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _hovered ? PbColors.borderFaint : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Opacity(
                opacity: _hovered ? 1 : 0.45,
                child: const PbSvgIcon(assetName: 'x', size: 18, color: PbColors.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadProgressRow extends StatelessWidget {
  const _UploadProgressRow({required this.item, required this.name, required this.isLast});

  final UploadProgressItem item;
  final String name;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: item.upload,
      builder: (context, _) {
        final percent = item.totalBytes > 0 ? (item.upload.bytesUploaded / item.totalBytes).clamp(0.0, 1.0) : 1.0;
        final failed = item.failed;
        final completed = item.completed;
        final value = failed || completed ? 1.0 : percent;
        final color = failed ? PbColors.customAlert : PbColors.statusOnline;

        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                textAlign: TextAlign.left,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PowerboardsTypography.meta.copyWith(color: failed ? PbColors.customAlert : PbColors.textMuted),
              ),
              const SizedBox(height: 6),
              PbProgressBar(value: value, color: color),
            ],
          ),
        );
      },
    );
  }
}
