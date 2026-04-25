import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/data_grid/in_memory_table.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class TsvPreview extends StatefulWidget {
  const TsvPreview({super.key, required this.filename, required this.room});

  final String filename;
  final RoomClient room;

  @override
  State<TsvPreview> createState() => _TsvPreviewState();
}

class _TsvPreviewState extends State<TsvPreview> {
  late Future<_TsvData> _data = _load();

  @override
  void didUpdateWidget(covariant TsvPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filename != widget.filename || oldWidget.room != widget.room) {
      _data = _load();
    }
  }

  Future<_TsvData> _load() async {
    final content = await widget.room.storage.download(widget.filename);
    return _parseTsv(utf8.decode(content.data, allowMalformed: true));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TsvData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Unable to load TSV preview: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: ShadTheme.of(context).colorScheme.destructive),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        if (data.columns.isEmpty) {
          return Center(child: Text('No rows found', style: ShadTheme.of(context).textTheme.muted));
        }

        return LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: InMemoryTable(
              columns: data.columns,
              rows: data.rows,
              maxHeight: constraints.maxHeight.isFinite ? math.max(0, constraints.maxHeight - 24) : 720,
              autoSizeColumns: true,
              autoSizeRows: true,
              showLeadingOuterBorders: true,
              showRowHeaders: false,
            ),
          ),
        );
      },
    );
  }
}

class _TsvData {
  const _TsvData({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<String>> rows;
}

_TsvData _parseTsv(String text) {
  final lines = const LineSplitter().convert(text).where((line) => line.trim().isNotEmpty).toList();
  if (lines.isEmpty) {
    return const _TsvData(columns: [], rows: []);
  }

  final columns = lines.first.split('\t');
  final rows = [for (final line in lines.skip(1)) line.split('\t')];
  return _TsvData(columns: columns, rows: rows);
}
