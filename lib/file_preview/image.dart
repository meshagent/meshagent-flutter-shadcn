import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

final svgExtensions = <String>{"svg", "svgz"};

class ImagePreview extends StatelessWidget {
  const ImagePreview({super.key, required this.url, required this.fit});

  final BoxFit fit;
  final Uri url;

  String _ext(String path) {
    final base = basename(path);
    if (base.isEmpty) return "";
    return base.split(".").last.toLowerCase();
  }

  bool get isSvg {
    final pathExt = _ext(url.path);
    final queryPathExt = _ext(url.queryParameters['path'] ?? "");
    return svgExtensions.contains(pathExt) || svgExtensions.contains(queryPathExt);
  }

  @override
  Widget build(BuildContext context) {
    if (isSvg) {
      return SvgPicture.network(url.toString(), fit: fit);
    }
    return UniversalImage(url.toString(), fit: fit);
  }
}
