import 'package:meshagent/livekit_client.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/meetings/wake_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import "package:logging/logging.dart";

Future<livekit.RoomOptions> getSavedRoomOptions() async {
  livekit.RoomOptions? savedRoomOptions;
  final preferences = await SharedPreferences.getInstance();
  final preferedVideoDeviceId = preferences.getString("videoInput");
  final preferedAudioInputDeviceId = preferences.getString("audioInput");
  final preferedAudioOutputDeviceId = preferences.getString("audioOutput");

  savedRoomOptions = livekit.RoomOptions(
    defaultScreenShareCaptureOptions: const livekit.ScreenShareCaptureOptions(useiOSBroadcastExtension: true, preferCurrentTab: false),
    defaultCameraCaptureOptions: livekit.CameraCaptureOptions(deviceId: preferedVideoDeviceId),
    defaultAudioCaptureOptions: livekit.AudioCaptureOptions(deviceId: preferedAudioInputDeviceId),
    defaultAudioOutputOptions: livekit.AudioOutputOptions(deviceId: preferedAudioOutputDeviceId),
  );

  return savedRoomOptions;
}

class MeetingScope extends StatefulWidget {
  const MeetingScope({super.key, required this.client, this.breakoutRoom, required this.builder, this.roomOptions});

  final livekit.RoomOptions? roomOptions;
  final RoomClient client;
  final String? breakoutRoom;
  final Widget Function(BuildContext, MeetingController) builder;

  @override
  State createState() => _MeetingScopeState();
}

class _MeetingScopeState extends State<MeetingScope> {
  late final MeetingController controller = MeetingController(room: widget.client, roomOptions: widget.roomOptions);

  @override
  void initState() {
    super.initState();
    controller.configure(breakoutRoom: widget.breakoutRoom);
  }

  @override
  void dispose() {
    super.dispose();
    if (controller.isConnected) {
      controller.disconnect().catchError((err) {
        Logger.root.warning("unable to disconnect $err");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WakeLocker(
      child: _MeetingControllerData(controller: controller, child: widget.builder(context, controller)),
    );
  }
}

class MeetingController extends ChangeNotifier {
  MeetingController({required this.room, livekit.RoomOptions? roomOptions})
    : livekitRoom = livekit.Room(roomOptions: roomOptions ?? livekit.RoomOptions()) {
    livekitRoom.addListener(_onRoomChanged);
  }

  final RoomClient room;
  LivekitConnectionInfo? _config;
  final livekit.Room livekitRoom;

  LivekitConnectionInfo? get config {
    return _config;
  }

  Object? _configurationError;
  Object? get configurationError {
    return _configurationError;
  }

  bool get hasParticipantsWithVideo {
    return livekitRoom.localParticipant?.videoTrackPublications.where((pub) => !pub.muted).isNotEmpty == true ||
        livekitRoom.remoteParticipants.values
            .where((p) => p.videoTrackPublications.where((pub) => !pub.muted).isNotEmpty == true)
            .isNotEmpty;
  }

  void _onRoomChanged() {
    notifyListeners();
  }

  Future<void> configure({String? breakoutRoom}) async {
    if (livekitRoom.connectionState != livekit.ConnectionState.disconnected) {
      throw Exception("You cannot reconfigure while the controller is connected");
    }
    _config = null;
    _configurationError = null;
    notifyListeners();
    try {
      _config = await room.livekit.getConnectionInfo(breakoutRoom: breakoutRoom);
      notifyListeners();
    } catch (err) {
      _configurationError = err;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> connect([livekit.FastConnectOptions? fastConnectOptions]) async {
    final config = _config;
    if (config == null) {
      throw Exception("The controller has not been configured");
    }
    await livekitRoom.connect(config.url, config.token, fastConnectOptions: fastConnectOptions);
  }

  Future<void> disconnect() async {
    await livekitRoom.disconnect();
  }

  bool get isConnected {
    return livekitRoom.connectionState != livekit.ConnectionState.disconnected;
  }

  static MeetingController of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_MeetingControllerData>()!.controller;
  }

  static MeetingController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_MeetingControllerData>()?.controller;
  }
}

class _MeetingControllerData extends InheritedWidget {
  const _MeetingControllerData({required this.controller, required super.child});

  final MeetingController controller;

  @override
  bool updateShouldNotify(_MeetingControllerData oldWidget) {
    return oldWidget.controller != controller;
  }
}
