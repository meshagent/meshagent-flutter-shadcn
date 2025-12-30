import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfPreview extends StatelessWidget {
  const PdfPreview({super.key, this.pageNumber = 1, required this.url});

  final Uri url;
  final int pageNumber;

  @override
  Widget build(BuildContext context) {
    return PdfViewer.uri(url, initialPageNumber: pageNumber);
  }
}
