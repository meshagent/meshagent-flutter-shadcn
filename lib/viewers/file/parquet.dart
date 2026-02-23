import 'package:flutter/widgets.dart';
import 'package:meshagent/agents_client.dart';
import 'package:meshagent/room_server_client.dart';
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

  late String defaultTableName = pathlib.withoutExtension(pathlib.basename(widget.path));
  late String queryValue = "select * from $defaultTableName";

  void query() async {
    try {
      final result = await widget.client.agents.invokeTool(
        toolkit: "meshagent.duckdb",
        tool: "duckdb_query",
        input: ToolContentInput(JsonContent(json: {"database": dbName, "query": queryValue})),
      );

      final data = switch (result) {
        ToolContentOutput(:final content) when content is JsonContent => content,
        ToolStreamOutput() => throw RoomServerException("duckdb_query returned a stream; expected JSON"),
        ToolContentOutput(:final content) => throw RoomServerException(
          "duckdb_query returned unexpected content type: ${content.runtimeType}",
        ),
      };

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
    return Center(child: Text("Use duckdb tools to load this parquet file into a database."));
  }
}
