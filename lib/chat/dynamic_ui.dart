import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:rfw/formats.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rfw/rfw.dart';

class DynamicUI extends StatefulWidget {
  const DynamicUI({super.key, required this.room, required this.previous, required this.message, required this.next});

  final RoomClient room;
  final MeshElement? previous;
  final MeshElement message;
  final MeshElement? next;

  @override
  State createState() => _DynamicUI();
}

class _DynamicUI extends State<DynamicUI> {
  final _runtime = Runtime();
  final _data = DynamicContent();

  static const LibraryName coreName = LibraryName(<String>['core', 'widgets']);
  static const LibraryName mainName = LibraryName(<String>['main']);

  @override
  void initState() {
    super.initState();
    // Local widget library:
    _runtime.update(coreName, createCoreWidgets());
    // Remote widget library:

    updateData();
    updateWidget();

    widget.message.addListener(onUpdated);
  }

  @override
  void dispose() {
    super.dispose();
    widget.message.removeListener(onUpdated);

    _runtime.dispose();
  }

  void onUpdated() {
    error = null;
    updateData();
    updateWidget();
  }

  RemoteWidgetLibrary? _remoteWidgets;
  Exception? error;

  void updateWidget() async {
    final renderer = widget.message.getAttribute("renderer");
    final widgetName = widget.message.getAttribute("widget");
    final data = widget.message.getAttribute("data");

    Content? response;
    if (renderer is String && widgetName is String) {
      try {
        setState(() {
          error = null;
        });
        if (data == null) {
          return;
        }
        final result = await widget.room.agents.invokeTool(
          toolkit: renderer,
          tool: widgetName,
          input: ToolContentInput(JsonContent(json: {"platform": "flutter", "output": "rfw", "data": data})),
        );
        response = switch (result) {
          ToolContentOutput(:final content) => content,
          ToolStreamOutput() => throw RoomServerException("dynamic UI renderer returned a stream; expected a single content"),
        };

        final resp = response;
        if (resp is TextContent) {
          if (!mounted) return;
          setState(() {
            _remoteWidgets = parseLibraryFile(resp.text);
            _runtime.update(mainName, _remoteWidgets!);
          });
        } else if (resp is JsonContent) {
          if (!mounted) return;

          setState(() {
            final markup = resp.json["markup"];
            final data = resp.json["data"];

            if (data != null) {
              _data.update("serverData", data);
            }

            _remoteWidgets = parseLibraryFile(markup);
            _runtime.update(mainName, _remoteWidgets!);
          });
        } else {
          throw Exception("Expected text response from server");
        }
      } on RoomServerException catch (e) {
        if (!mounted) return;
        setState(() {
          error = e;
        });
      } on ParserException catch (e) {
        if (!mounted) return;
        setState(() {
          error = Exception(
            "${e.message} at ${e.line}, ${e.column}:\n${(response as TextContent).text.split("\n").mapIndexed((i, s) => "${i + 1}: $s").join("\n")}",
          );
        });
      }
    } else {
      _remoteWidgets = null;
    }
  }

  void updateData() {
    try {
      final json = widget.message.getAttribute("data");
      if (json != null) {
        final data = jsonDecode(json);

        // Configuration data:
        _data.update('data', data);
      } else {
        _data.update('data', {});
      }
    } catch (e) {
      _data.update('error', e.toString());
    }
  }

  void onEvent(String name, DynamicMap? data) async {
    try {
      if (name == "invoke") {
        await widget.room.agents.invokeTool(
          toolkit: data!["toolkit"] as String,
          tool: data["tool"] as String,
          input: ToolContentInput(JsonContent(json: data["arguments"] as Map<String, dynamic>)),
        );
      } else if (name == "open") {
        await launchUrl(Uri.parse(data!["url"] as String), webOnlyWindowName: data["target"] as String?);
      } else {
        showShadDialog(
          context: context,
          builder: (context) => ShadDialog.alert(title: Text("Unknown event received $name")),
        );
      }
    } on Exception catch (ex) {
      if (!mounted) {
        return;
      }
      showShadDialog(
        context: context,
        builder: (context) => ShadDialog.alert(title: Text("Unable to process event $name, data: $data, error: $ex")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return SelectableText("$error", style: ShadTheme.of(context).textTheme.p);
    }
    if (_remoteWidgets == null) {
      return Container();
    }
    return RemoteWidget(runtime: _runtime, data: _data, widget: const FullyQualifiedWidgetName(mainName, 'root'), onEvent: onEvent);
  }
}
