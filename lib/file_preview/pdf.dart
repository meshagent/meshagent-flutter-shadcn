import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfPreview extends StatefulWidget {
  const PdfPreview({super.key, this.pageNumber = 1, required this.path, required this.room});

  final String path;
  final RoomClient room;
  final int pageNumber;

  @override
  State<PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<PdfPreview> {
  late Future<Uint8List> _pdfData = _loadPdfData();

  @override
  void didUpdateWidget(covariant PdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.room != widget.room) {
      _pdfData = _loadPdfData();
    }
  }

  Future<Uint8List> _loadPdfData() async {
    final content = await widget.room.storage.download(widget.path);
    return Uint8List.fromList(content.data);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _pdfData,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Unable to load PDF: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return PdfViewer.data(data, sourceName: widget.path, initialPageNumber: widget.pageNumber);
      },
    );
  }
}
