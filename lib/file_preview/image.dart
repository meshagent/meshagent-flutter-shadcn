import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ImagePreview extends StatelessWidget {
  const ImagePreview({super.key, required this.url, required this.fit});

  final BoxFit fit;
  final Uri url;

  @override
  Widget build(BuildContext context) {
    if (url.path.endsWith(".svg")) {
      return SvgPicture.network(url.toString(), fit: fit);
    }
    return UniversalImage(url.toString(), fit: fit);
  }
}
