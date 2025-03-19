import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';

class AudioPreview extends StatefulWidget {
  AudioPreview({super.key, required this.url});

  final Uri url;

  @override
  State createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<AudioPreview> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AudioAttachment(autoPlay: false, url: widget.url.toString());
  }
}

class VideoPreview extends StatefulWidget {
  VideoPreview({super.key, required this.url, required this.fit});

  final BoxFit fit;
  final Uri url;

  @override
  State createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VideoAttachment(videoUrl: widget.url.toString());
  }
}

class VideoAttachment extends StatefulWidget {
  const VideoAttachment({
    // ignore: unused_element
    super.key,
    required this.videoUrl,
    // ignore: unused_element
    this.autoPlay = false,
    // ignore: unused_element
    this.onPlay,
    // ignore: unused_element
    this.onPreviewStarted,
    // ignore: unused_element
    this.onPositionChanged,
    // ignore: unused_element
    this.onPreviewPaused,
    // ignore: unused_element
    this.onPreviewStopped,
    // ignore: unused_element
    this.playOnTap = false,
    // ignore: unused_element
    this.timelineSource,
  });

  final bool autoPlay;

  final void Function()? onPlay;

  final String videoUrl;
  final void Function(Duration position)? onPreviewStarted;
  final void Function(Duration position)? onPositionChanged;
  final void Function()? onPreviewPaused;
  final void Function()? onPreviewStopped;
  final Object? timelineSource;

  final bool playOnTap;

  @override
  State<StatefulWidget> createState() => _VideoAttachmentState();
}

class _VideoAttachmentState extends State<VideoAttachment> {
  bool isLoaded = false;

  VideoPlayerController? controller;
  ChewieController? chewieController;

  @override
  void initState() {
    super.initState();
    reset();
  }

  void reset() {
    controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    chewieController = ChewieController(
      customControls: const MaterialControls(),
      showControlsOnInitialize: false,
      hideControlsTimer: const Duration(milliseconds: 1000),
      showControls: widget.onPlay == null,
      videoPlayerController: controller!,
    );
    controller!.initialize().then((value) {
      if (mounted) {
        setState(() {
          isLoaded = true;
        });
      }

      if (widget.autoPlay) {
        controller!.play();
      }
    });
    controller!.addListener(() {
      if (controller!.value.hasError) {
        controller!.dispose();
        reset();
      }

      final v = controller!.value;
      final currentlyPlaying =
          v.isPlaying /*&&
          controller!.value.position != controller!.value.duration &&
          controller!.value.position > Duration.zero*/
          ;

      if (playing != currentlyPlaying) {
        playing = currentlyPlaying;
        if (!playing) {
          if (widget.onPreviewPaused != null) {
            widget.onPreviewPaused!();
          }
        } else {
          if (widget.onPreviewStarted != null) {
            widget.onPreviewStarted!(v.duration);
          }
        }
      }

      if (widget.onPositionChanged != null) {
        controller!.position.then((duration) => widget.onPositionChanged!(duration ?? Duration.zero));
      }

      if (mounted) {
        setState(() {});
      }
    });
  }

  bool playing = false;

  @override
  void dispose() {
    super.dispose();
    if (playing) {
      if (widget.onPreviewStopped != null) {
        widget.onPreviewStopped!();
      }
    }
    chewieController?.dispose();
    controller?.dispose();
  }

  Widget buildPlayer(BuildContext context) {
    if (controller != null) {
      return LayoutBuilder(
        builder: (builder, constraints) {
          return isLoaded ? Chewie(controller: chewieController!) : SizedBox();
        },
      );
    } else {
      return Container(color: Color.from(alpha: 1, red: 0, green: 0, blue: 0));
    }
  }

  bool processing = false;

  Widget _wrapTap(Widget child) {
    if (!widget.playOnTap) {
      return child;
    }

    return GestureDetector(
      onTap: () {
        if (controller?.value.isPlaying == true) {
          controller!.pause();
        } else {
          controller!.play();
        }
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (controller?.value.isInitialized != true) {
      return AspectRatio(aspectRatio: 1, child: Container(color: Color.from(alpha: 1, red: 0, green: 0, blue: 0)));
    }

    var scale = 1.0;

    final parentTransform = context.findAncestorWidgetOfExactType<Transform>();
    if (parentTransform != null) {
      final matrix = parentTransform.transform.clone()..invert();
      scale = matrix.getMaxScaleOnAxis();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          cursor: widget.playOnTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: _wrapTap(
            AspectRatio(
              aspectRatio: controller!.value.size.width / controller!.value.size.height,
              child: Container(
                color: Color.from(alpha: 1, red: 0, green: 0, blue: 0),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: buildPlayer(context)),
                    if (widget.onPlay != null)
                      Center(
                        child: Container(
                          decoration: BoxDecoration(color: const Color.fromARGB(80, 0, 0, 0), borderRadius: BorderRadius.circular(500)),
                          padding: EdgeInsets.all(15 * scale),
                          child: IgnorePointer(
                            ignoring: processing,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (controller?.value.isInitialized == true && controller?.value.isPlaying == false)
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () async {
                                        if (controller?.value.isPlaying != false || processing) {
                                          return;
                                        }
                                        setState(() {
                                          processing = true;
                                        });
                                        try {
                                          if (widget.onPlay != null) {
                                            widget.onPlay!();
                                          } else {
                                            await controller!.play();
                                          }
                                        } catch (err) {
                                          debugPrint(err.toString());
                                        }
                                        if (mounted) {
                                          setState(() {
                                            processing = false;
                                          });
                                        }
                                      },
                                      child: Icon(
                                        Icons.play_arrow,
                                        color: Color.from(alpha: 1, red: 1, green: 1, blue: 1),
                                        size: 30 * scale,
                                      ),
                                    ),
                                  ),
                                if (controller?.value.isInitialized == true && controller?.value.isPlaying == true)
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () async {
                                        if (controller?.value.isPlaying != true || processing) {
                                          return;
                                        }

                                        setState(() {
                                          processing = true;
                                        });
                                        try {
                                          await controller!.pause();
                                        } catch (err) {
                                          debugPrint(err.toString());
                                        }
                                        if (mounted) {
                                          setState(() {
                                            processing = false;
                                          });
                                        }
                                      },
                                      child: Icon(Icons.pause, color: Color.from(alpha: 1, red: 1, green: 1, blue: 1), size: 30 * scale),
                                    ),
                                  ),
                                if (controller?.value.isInitialized == true && controller?.value.isPlaying == true)
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () async {
                                        if (controller?.value.isPlaying != true || processing) {
                                          return;
                                        }
                                        setState(() {
                                          processing = true;
                                        });
                                        try {
                                          await controller!.pause();
                                          await controller!.seekTo(Duration.zero);

                                          if (widget.onPreviewStopped != null) {
                                            widget.onPreviewStopped!();
                                          }
                                        } catch (err) {
                                          debugPrint(err.toString());
                                        }

                                        if (mounted) {
                                          setState(() {
                                            processing = false;
                                          });
                                        }
                                      },
                                      child: Container(
                                        padding: EdgeInsets.all(3 * scale),
                                        child: Container(
                                          color: Color.from(alpha: 1, red: 1, green: 1, blue: 1),
                                          width: 20 * scale,
                                          height: 20 * scale,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AudioAttachment extends StatefulWidget {
  const _AudioAttachment({required this.autoPlay, required this.url});

  final bool autoPlay;
  final String url;

  @override
  State createState() => _AudioAttachmentState();
}

class _AudioAttachmentState extends State<_AudioAttachment> {
  AudioPlayer? player;

  @override
  void dispose() {
    super.dispose();
    player?.dispose();
  }

  @override
  void initState() {
    super.initState();

    player = AudioPlayer();
    start();
  }

  void start() async {
    await player!.setAudioSource(AudioSource.uri(Uri.parse(widget.url)));
    if (mounted) {
      if (widget.autoPlay) {
        player!.play();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return player == null
        ? const CircularProgressIndicator()
        : StreamBuilder(
            stream: player!.playerStateStream,
            builder: (context, snapshot) => ShadButton(
              onPressed: () {
                if (snapshot.data?.playing == true) {
                  player!.pause();
                } else {
                  player!.play();
                }
              },
              leading: snapshot.data?.playing == true ? const Icon(size: 16, LucideIcons.pause) : const Icon(size: 16, LucideIcons.play),
              child: snapshot.data?.playing == true ? const Text("Pause") : const Text("Play"),
            ),
          );
  }
}
