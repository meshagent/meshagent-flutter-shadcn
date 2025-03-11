import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:synchronized/synchronized.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;

class PdfPreview extends StatefulWidget {
  const PdfPreview({
    super.key,
    this.pageNumber = 0,
    required this.url,
    this.backgroundColor = const Color.from(
      alpha: 1,
      red: 1,
      green: 1,
      blue: 1,
    ),
    required this.fit,
  });

  final BoxFit fit;
  final Uri url;
  final Color backgroundColor;
  final int pageNumber;

  @override
  State createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<PdfPreview> {
  

  @override
  void initState() {
    super.initState();
    PdfDocument.openUri(widget.url).then((d) {
      if (mounted) {
        setState(() {
          doc = d;
        });
      } else {
        d.dispose();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    doc?.dispose();
  }

  PdfDocument? doc;

  @override
  Widget build(BuildContext context) {
    if(doc != null) {
          return ListView.builder(
            itemCount: doc!.pages.length,
            itemBuilder: (context, index) => Padding(padding: EdgeInsets.all(30), child: PdfPage(document: doc!, pageNumber: index, backgroundColor: widget.backgroundColor, fit: widget.fit)));
    } else {
      return Container();
    }
  }
}

class PdfPage extends StatefulWidget {
  PdfPage({ super.key, required this.document, required this.pageNumber, required this.backgroundColor, required this.fit });

  final PdfDocument document;
  final int pageNumber;
  final Color backgroundColor;
  final BoxFit fit;

  @override
  State createState() => _PdfPageState();
}

class _PdfPageState extends State<PdfPage> {
  static final _lock = Lock();

  static Future<T?> queue<T>(Future<T?> Function() op) async {
    return await _lock.synchronized(op);
  }

  bool loaded = false;
  bool loading = false;
  ui.Image? image;

  Size loadedSize = Size.zero;

  PdfPageRenderCancellationToken? cancellationToken;

  void render(PdfDocument doc, Size size, int pageNumber, double scale) async {
    final mq = MediaQuery.of(context);
    size = size * scale * mq.devicePixelRatio;
    final maxSize = mq.size * mq.devicePixelRatio;
    if (size.width > maxSize.width || size.height > maxSize.height) {
      size =
          size *
          (math.min(maxSize.width / size.width, maxSize.height / size.height));
    }
    if ((!loaded || size != loadedSize) && !loading && size != Size.zero) {
      debugPrint("loading pdf $size vs $loadedSize $loaded");

      loaded = true;
      loading = true;
      await queue(() async {
        if (pageNumber >= doc.pages.length) {
          loading = false;
          return;
        }
        final page = doc.pages[pageNumber];
        cancellationToken = page.createCancellationToken();

        final pageImage = await page.render(
          x: 0,
          y: 0,
          fullWidth: (size.width),
          fullHeight: (size.width * page.height / page.width), // (size.height),
          backgroundColor: widget.backgroundColor,
          cancellationToken: cancellationToken,
        );

        cancellationToken = null;
        if (pageImage == null) {
          loading = false;
          return;
        }
        if (!mounted) {
          pageImage.dispose();
          return;
        }
        final renderedPage = await pageImage.createImage();

        if (image != null) {
          image!.dispose();
          image = null;
        }
        loadedSize = size;
        image = renderedPage;
        pageImage.dispose();
        if (mounted) {
          loading = false;
          setState(() {
            image = renderedPage;
          });
        } else {
          if (image != null) {
            image!.dispose();
            image = null;
          }
        }
      }).catchError((err) {
        debugPrint("Unable to load pdf document $err");
      });
    }
  }

  void renderAtScreenSize(PdfDocument doc, int pageNumber, RenderBox ro) {
    final screenSize =
        ro.localToGlobal(Offset(ro.size.width, ro.size.height)) -
        ro.localToGlobal(Offset.zero);

    render(doc, Size(screenSize.dx, screenSize.dy), pageNumber, 1.0);
  }

  int get page {
    return widget.pageNumber;
  }

  @override
  Widget build(BuildContext context) {

    final doc = widget.document;
  return AspectRatio(
      aspectRatio:
         (doc!.pages[page].width / doc!.pages[page].height),
      child: LayoutBuilder(
        builder: (context, constraints) {
         
          final ro = context.findRenderObject() as RenderBox?;

          if (ro != null && ro.hasSize) {
            renderAtScreenSize(doc!, page, ro);
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                final ro = context.findRenderObject() as RenderBox;
                renderAtScreenSize(doc!, page, ro);
              }
            });
          }
        

          if (image != null) {
            if (constraints.hasBoundedHeight && constraints.hasBoundedWidth) {
              return FittedBox(
                clipBehavior: Clip.antiAlias,
                fit: widget.fit,
                child: SizedBox(
                  width: image!.width.toDouble(),
                  height: image!.height.toDouble(),
                  child: CustomPaint(painter: _ImagePainter(image!)),
                ),
              );
            } else if (constraints.hasBoundedHeight) {
              return SizedBox(
                width:
                    constraints.maxHeight *
                    image!.width.toDouble() /
                    image!.height.toDouble(),
                height: constraints.maxHeight,
                child: CustomPaint(painter: _ImagePainter(image!)),
              );
            } else if (constraints.hasBoundedWidth) {
              return SizedBox(
                width: constraints.maxWidth,
                height:
                    constraints.maxWidth *
                    image!.height.toDouble() /
                    image!.width.toDouble(),
                child: CustomPaint(painter: _ImagePainter(image!)),
              );
            } else {
              return SizedBox(
                width: image!.width.toDouble(),
                height: image!.height.toDouble(),
                child: CustomPaint(painter: _ImagePainter(image!)),
              );
            }
          } else {
            return ColoredBox(color: widget.backgroundColor);
          }
        },
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  _ImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width.toDouble(), size.height.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) {
    return image != oldDelegate.image;
  }
}
