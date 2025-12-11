import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileBrowser extends StatefulWidget {
  const FileBrowser({super.key, required this.room, this.initialPath = "", this.multiple = false, this.onSelectionChanged});

  final RoomClient room;
  final String initialPath;
  final bool multiple;
  final void Function(List<String> selection)? onSelectionChanged;

  @override
  State createState() => _FileBrowser();
}

class _FileBrowser extends State<FileBrowser> {
  String path = "";

  List<StorageEntry>? files;

  @override
  void initState() {
    super.initState();
    load();
  }

  void load() async {
    files = (await widget.room.storage.list(path)).where((x) => !x.name.startsWith(".")).toList();
    if (mounted) {
      setState(() {});
    }
  }

  String join(String path1, String path2) {
    if (path1 == "") {
      return path2;
    } else {
      return "$path1/$path2";
    }
  }

  final Set<String> selection = {};

  @override
  Widget build(BuildContext context) {
    if (files == null) {
      return Center(child: CircularProgressIndicator());
    } else {
      return Column(
        spacing: 1,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShadButton.ghost(
                onPressed: () {
                  setState(() {
                    path = "";
                    load();
                  });
                },
                child: Text("Files"),
              ),
              if (path != "")
                for (final segment in path.split("/").indexed) ...[
                  Text("/"),
                  ShadButton.ghost(
                    onPressed: () {
                      var segmentPath = "";
                      for (var i = 0; i <= segment.$1; i++) {
                        if (segmentPath.isNotEmpty) {
                          segmentPath += "/";
                        }
                        segmentPath += segment.$2;
                      }
                      setState(() {
                        path = segmentPath;
                        load();
                      });
                    },
                    child: Text(segment.$2),
                  ),
                ],
            ],
          ),
          Expanded(
            child: ListView(
              children: [
                for (final file in files!)
                  ShadButton.ghost(
                    backgroundColor: selection.contains(join(path, file.name)) ? ShadTheme.of(context).colorScheme.selection : null,
                    decoration: selection.contains(join(path, file.name))
                        ? ShadDecoration(border: ShadBorder.all(radius: BorderRadius.all(Radius.zero)))
                        : null,
                    mainAxisAlignment: MainAxisAlignment.start,
                    onPressed: () {
                      if (file.isFolder) {
                        setState(() {
                          path = join(path, file.name);
                          selection.clear();
                          load();
                        });
                      } else {
                        setState(() {
                          final fullPath = join(path, file.name);
                          if (widget.multiple) {
                            if (!selection.contains(fullPath)) {
                              selection.add(fullPath);
                            } else {
                              selection.remove(fullPath);
                            }
                          } else {
                            if (selection.contains(fullPath)) {
                              selection.clear();
                            } else {
                              selection.add(fullPath);
                            }
                          }
                        });
                      }
                      if (widget.onSelectionChanged != null) {
                        widget.onSelectionChanged!(selection.toList());
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        Icon(
                          selection.contains(join(path, file.name))
                              ? LucideIcons.check
                              : (file.isFolder ? LucideIcons.folder : LucideIcons.file),
                          color: (file.isFolder ? Color.fromARGB(0xff, 0xe0, 0xa0, 0x30) : null),
                        ),
                        Text(file.name, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }
  }
}
