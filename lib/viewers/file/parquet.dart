import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:path/path.dart' as pathlib;

class ParquetViewer extends StatefulWidget {
  const ParquetViewer({super.key, required this.client, required this.path});

  final RoomClient client;
  final String path;

  @override
  State createState() => _ParquetViewer();
}

class _ParquetViewer extends State<ParquetViewer> {
  var rows = [];
  var columns = [];

  late String defaultTableName = pathlib.withoutExtension(
    pathlib.basename(widget.path),
  );
  late String queryValue = "select * from ${defaultTableName}";

  void query() async {
    try {
      final data =
          await widget.client.agents.invokeTool(
                toolkit: "meshagent.duckdb",
                tool: "duckdb_query",
                arguments: {"database": dbName, "query": queryValue},
              )
              as JsonResponse;

      if (mounted) {
        setState(() {
          columns = data.json["columns"];
          rows = data.json["rows"];
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          rows = [
            {"error": err.toString()},
          ];
          columns = ["error"];
        });
      }
    }
  }

  var dbName = "temp";
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        "Use duckdb tools to load this parquet file into a database.",
      ),
    );
  
  }
}
