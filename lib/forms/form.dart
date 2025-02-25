import 'package:flutter/widgets.dart';
import 'package:meshagent/document.dart' as doc;
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/viewers/viewers.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FormDocumentViewer extends StatelessWidget {
  const FormDocumentViewer({
    super.key,
    required this.client,
    required this.document,
  });
  final RoomClient client;
  final MeshDocument document;
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierBuilder(
      source: document,
      builder:
          (context) =>
              document.root.getChildren().isEmpty
                  ? Container()
                  : Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15),
                    child: ShadCard(
                      title:
                          document.root.getAttribute("title") != null
                              ? Text(document.root.getAttribute("title"))
                              : null,
                      description:
                          document.root.getAttribute("description") != null
                              ? Text(document.root.getAttribute("description"))
                              : null,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final fieldElement
                                in document.root.getChildren()) ...[
                              FormDocumentField(
                                element: fieldElement as doc.Element,
                              ),
                              const SizedBox(height: 26),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
    );
  }
}

class FormDocumentField extends StatelessWidget {
  const FormDocumentField({super.key, required this.element});
  final doc.Element element;
  @override
  Widget build(BuildContext context) {
    return switch (element.tagName) {
      "select" => FormDocumentSelect(element: element),
      "input" => FormDocumentInput(element: element),
      _ => throw new Exception("Unexpected form field type"),
    };
  }
}

class FormDocumentSelect extends StatelessWidget {
  const FormDocumentSelect({super.key, required this.element});
  final doc.Element element;
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierBuilder(
      source: element,
      builder:
          (context) => ShadSelectFormField<String?>(
            selectedOptionBuilder: (context, value) => Text("${value ?? ''}"),
            placeholder: Text("pick a value"),
            label:
                element.getAttribute("label") == null
                    ? null
                    : Text(element.getAttribute("label")),
            description:
                element.getAttribute("description") == null
                    ? null
                    : Text(element.getAttribute("description")),
            options: [
              for (final option
                  in element.getChildren().whereType<doc.Element>())
                ShadOption<String?>(
                  value: option.getAttribute("value"),
                  child: Text(option.getAttribute("text")),
                ),
            ],
          ),
    );
  }
}

class FormDocumentInput extends StatelessWidget {
  const FormDocumentInput({super.key, required this.element});
  final doc.Element element;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierBuilder(
      source: element,
      builder:
          (context) => ShadInputFormField(
            label:
                element.getAttribute("label") == null
                    ? null
                    : Text(element.getAttribute("label")),
            description:
                element.getAttribute("description") == null
                    ? null
                    : Text(element.getAttribute("description")),
          ),
    );
  }
}
