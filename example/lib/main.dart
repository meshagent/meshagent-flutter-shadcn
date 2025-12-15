import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter/meshagent_flutter.dart';
import 'package:meshagent_flutter_shadcn/meshagent_flutter_shadcn.dart';
import 'package:meshagent_flutter_shadcn/storage/file_browser.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// Replace these placeholders with values from your Meshagent project.
const projectId = 'insert-project-id';
const roomName = 'insert-room-name';
const roomUrl = 'wss://api.meshagent.com/rooms/$roomName';
const apiKey = '';

void main() {
  runApp(const MeshagentExampleApp());
}

class MeshagentExampleApp extends StatelessWidget {
  const MeshagentExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final token = ParticipantToken(name: 'mega-man');
    token.addRoomGrant(roomName);
    token.addRoleGrant("agent");
    token.addApiGrant(ApiScope.agentDefault());

    return ShadTheme(
      data: ShadThemeData(),
      child: MaterialApp(
        title: 'Meshagent Flutter Example',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        home: RoomConnectionScope(
          authorization: staticAuthorization(
            projectId: projectId,
            roomName: roomName,
            url: Uri.parse(roomUrl),
            jwt: token.toJwt(apiKey: apiKey),
          ),
          builder: (context, room) => MeshagentRoomView(room: room),
        ),
      ),
    );
  }
}

class MeshagentRoomView extends StatefulWidget {
  const MeshagentRoomView({super.key, required this.room});

  final RoomClient room;

  @override
  State<MeshagentRoomView> createState() => _MeshagentRoomViewState();
}

class _MeshagentRoomViewState extends State<MeshagentRoomView> {
  Key _fileBrowserKey = UniqueKey();
  MeshagentFileUpload? _currentUpload;
  VoidCallback? _uploadListener;

  bool get _isUploading {
    final upload = _currentUpload;
    if (upload == null) {
      return false;
    }

    return upload.status == UploadStatus.initial || upload.status == UploadStatus.uploading;
  }

  @override
  void dispose() {
    _removeUploadListener();
    super.dispose();
  }

  void _removeUploadListener() {
    if (_currentUpload != null && _uploadListener != null) {
      _currentUpload!.removeListener(_uploadListener!);
    }
  }

  void _trackUpload(MeshagentFileUpload upload) {
    _removeUploadListener();

    _uploadListener = () {
      if (mounted) {
        setState(() {});
      }
    };

    setState(() {
      _currentUpload = upload..addListener(_uploadListener!);
    });
  }

  Stream<List<int>> _chunkedBytes(Uint8List data, {int chunkSize = 64 * 1024}) async* {
    for (var offset = 0; offset < data.length; offset += chunkSize) {
      final end = math.min(offset + chunkSize, data.length);
      yield data.sublist(offset, end);
    }
  }

  String _uploadStatusText(MeshagentFileUpload upload) {
    switch (upload.status) {
      case UploadStatus.initial:
        return 'Preparing to upload ${upload.filename}...';
      case UploadStatus.uploading:
        final uploadedKb = (upload.bytesUploaded / 1024).toStringAsFixed(1);
        final totalKb = upload.size > 0 ? (upload.size / 1024).toStringAsFixed(1) : '?';
        return 'Uploading ${upload.filename} ($uploadedKb KB of $totalKb KB)';
      case UploadStatus.completed:
        return 'Upload completed for ${upload.filename}.';
      case UploadStatus.failed:
        return 'Upload failed for ${upload.filename}. Please try again.';
    }
  }

  double? _uploadProgress(MeshagentFileUpload upload) {
    if (upload.size <= 0) {
      return null;
    }

    return upload.bytesUploaded / upload.size;
  }

  Future<void> _uploadFile() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) {
      return;
    }

    final file = picked.files.first;
    final bytes = file.bytes;

    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to read the selected file.')));
      }
      return;
    }

    try {
      final upload = MeshagentFileUpload(room: widget.room, path: file.name, dataStream: _chunkedBytes(bytes), size: bytes.length);

      _trackUpload(upload);

      await upload.done;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded "${file.name}" to the room.')));
        setState(() {
          _fileBrowserKey = UniqueKey();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $error')));
      }
    } finally {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meshagent Room')),
      body: FutureBuilder(
        future: widget.room.ready,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: _StatusCard(title: 'Connecting...', details: 'Waiting for the WebSocket connection to be ready.', spinner: true),
            );
          }

          final connectedRoomName = widget.room.roomName ?? roomName;
          final connectedRoomUrl = widget.room.roomUrl ?? roomUrl;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusCard(title: 'Connected', details: 'Connected to room "$connectedRoomName" at "$connectedRoomUrl".'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isUploading ? null : _uploadFile,
                      icon: _isUploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file),
                      label: Text(_isUploading ? 'Uploading...' : 'Upload a file'),
                    ),
                    const SizedBox(width: 12),
                    const Text('Select a file to upload it into the current room'),
                  ],
                ),
                const SizedBox(height: 16),
                if (_currentUpload != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Upload status', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(_uploadStatusText(_currentUpload!)),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: _uploadProgress(_currentUpload!), minHeight: 6),
                          if (_currentUpload!.status == UploadStatus.completed) ...[
                            const SizedBox(height: 8),
                            FutureBuilder<Uri>(
                              future: _currentUpload!.downloadUrl,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Text('Generating download link...');
                                }

                                if (snapshot.hasError) {
                                  return Text('Download link unavailable: ${snapshot.error}');
                                }

                                final url = snapshot.data;
                                if (url == null) {
                                  return const SizedBox.shrink();
                                }

                                return ElevatedButton.icon(
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: url.toString()));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(const SnackBar(content: Text('Download link copied to clipboard.')));
                                    }
                                  },
                                  icon: const Icon(Icons.copy),
                                  label: const Text('Copy download link'),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Room files', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          Expanded(
                            child: FileBrowser(key: _fileBrowserKey, room: widget.room),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.title, required this.details, this.spinner = false});

  final String title;
  final String details;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(details, textAlign: TextAlign.center),
            if (spinner) ...[const SizedBox(height: 24), const CircularProgressIndicator()],
          ],
        ),
      ),
    );
  }
}
