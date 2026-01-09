import 'package:flutter/material.dart';
import 'package:meshagent/meshagent.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

enum FileBrowserSelectionMode { files, folders }

class FileBrowser extends StatefulWidget {
  const FileBrowser({
    super.key,
    required this.room,
    this.initialPath = "",
    this.multiple = false,
    this.onSelectionChanged,
    this.selectionMode = FileBrowserSelectionMode.files,
    this.rootLabel = "Files",
  });

  final RoomClient room;
  final String initialPath;
  final bool multiple;
  final void Function(List<String> selection)? onSelectionChanged;
  final FileBrowserSelectionMode selectionMode;
  final String rootLabel;

  @override
  State createState() => _FileBrowser();
}

class _FileBrowser extends State<FileBrowser> {
  String path = "";

  List<StorageEntry>? files;
  final Set<String> selection = {};

  @override
  void initState() {
    super.initState();
    path = widget.initialPath;

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

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final tt = theme.textTheme;
    final cs = theme.colorScheme;

    if (files == null) {
      return Center(child: CircularProgressIndicator());
    }

    final filteredFiles = widget.selectionMode == FileBrowserSelectionMode.folders ? files!.where((x) => x.isFolder) : files!;

    final fileItems = path.split("/");

    return Column(
      spacing: 1,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: .only(top: 10.0, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Path: ",
                style: tt.small.copyWith(fontWeight: FontWeight.bold, color: cs.primary),
              ),
              Expanded(
                child: ShadBreadcrumb(
                  separator: Icon(LucideIcons.chevronRight, size: 16),
                  children: [
                    ShadBreadcrumbLink(
                      onPressed: () {
                        setState(() {
                          if (widget.selectionMode == FileBrowserSelectionMode.folders) {
                            selection
                              ..clear()
                              ..add("");
                          }
                          path = "";
                          load();
                        });
                      },
                      child: const Text('Home'),
                    ),

                    if (path != "")
                      for (final segment in fileItems.indexed)
                        ShadBreadcrumbLink(
                          onPressed: () {
                            String segmentPath = "";

                            for (int i = 0; i <= segment.$1; i++) {
                              if (segmentPath.isNotEmpty) {
                                segmentPath += "/";
                              }

                              segmentPath += fileItems[i];
                            }

                            if (widget.selectionMode == FileBrowserSelectionMode.folders) {
                              setState(() {
                                final fullPath = segmentPath;
                                selection
                                  ..clear()
                                  ..add(fullPath);
                                path = segmentPath;

                                load();
                              });
                            } else {
                              setState(() {
                                path = segmentPath;

                                load();
                              });
                            }
                          },
                          child: Text(segment.$2),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final file in filteredFiles)
                ShadButton.ghost(
                  backgroundColor: selection.contains(join(path, file.name)) ? theme.colorScheme.selection : null,
                  decoration: selection.contains(join(path, file.name))
                      ? ShadDecoration(border: ShadBorder.all(radius: BorderRadius.all(Radius.zero)))
                      : null,
                  mainAxisAlignment: MainAxisAlignment.start,
                  onPressed: () {
                    if (file.isFolder) {
                      if (widget.selectionMode == FileBrowserSelectionMode.folders) {
                        // note: only single folder selection is supported
                        final fullPath = join(path, file.name);
                        setState(() {
                          if (selection.contains(fullPath)) {
                            selection.clear();
                          } else {
                            selection
                              ..clear()
                              ..add(fullPath);
                          }
                          path = fullPath;
                          load();
                        });
                      } else {
                        setState(() {
                          path = join(path, file.name);
                          selection.clear();
                          load();
                        });
                      }
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
