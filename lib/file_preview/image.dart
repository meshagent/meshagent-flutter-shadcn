import 'dart:typed_data';

import 'package:flutter/material.dart';
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
    return svgExtensions.contains(pathExt) ||
        svgExtensions.contains(queryPathExt);
  }

  Widget _previewUnavailable(BuildContext context) {
    return Center(
      child: Text(
        "No preview available",
        style: ShadTheme.of(context).textTheme.large.copyWith(
          color: ShadTheme.of(context).colorScheme.mutedForeground,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth ? constraints.maxWidth : null;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : null;
        final fallback = _previewUnavailable(context);

        if (isSvg) {
          return SvgPicture.network(
            url.toString(),
            fit: fit,
            width: width,
            height: height,
            placeholderBuilder: (context) =>
                Center(child: CircularProgressIndicator()),
            errorBuilder: (_, _, _) => fallback,
          );
        }

        return UniversalImage(
          url.toString(),
          fit: fit,
          width: width,
          height: height,
          placeholder: Center(child: CircularProgressIndicator()),
          errorPlaceholder: fallback,
        );
      },
    );
  }
}

class ImageDataPreview extends StatelessWidget {
  const ImageDataPreview({
    super.key,
    required this.data,
    required this.path,
    required this.fit,
    this.mimeType,
  });

  final Uint8List data;
  final String path;
  final BoxFit fit;
  final String? mimeType;

  bool get isSvg {
    final normalizedMimeType = mimeType?.trim().toLowerCase();
    if (normalizedMimeType == 'image/svg+xml' ||
        normalizedMimeType == 'image/svg' ||
        normalizedMimeType == 'public.svg-image') {
      return true;
    }

    final base = basename(path);
    if (base.isEmpty || !base.contains('.')) {
      return false;
    }
    return svgExtensions.contains(base.split('.').last.toLowerCase());
  }

  Widget _previewUnavailable(BuildContext context) {
    return Center(
      child: Text(
        'No preview available',
        style: ShadTheme.of(context).textTheme.large.copyWith(
          color: ShadTheme.of(context).colorScheme.mutedForeground,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth ? constraints.maxWidth : null;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : null;
        final fallback = _previewUnavailable(context);

        if (isSvg) {
          return SvgPicture.memory(
            data,
            fit: fit,
            width: width,
            height: height,
            placeholderBuilder: (context) =>
                const Center(child: CircularProgressIndicator()),
            errorBuilder: (_, _, _) => fallback,
          );
        }

        return UniversalImage(
          data,
          fit: fit,
          width: width,
          height: height,
          placeholder: const Center(child: CircularProgressIndicator()),
          errorPlaceholder: fallback,
        );
      },
    );
  }
}
