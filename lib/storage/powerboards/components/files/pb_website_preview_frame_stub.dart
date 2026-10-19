import 'package:flutter/material.dart';

class PbWebsitePreviewFrame extends StatelessWidget {
  const PbWebsitePreviewFrame({super.key, this.htmlDocument, this.url}) : assert(htmlDocument != null || url != null);

  final String? htmlDocument;
  final Uri? url;

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Website preview is available in the web app.', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
