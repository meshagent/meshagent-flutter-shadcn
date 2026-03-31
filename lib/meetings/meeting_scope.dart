import 'package:meshagent_flutter/meshagent_flutter.dart';
import 'package:meshagent/room_server_client.dart';
import 'package:meshagent_flutter_shadcn/meetings/wake_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import "package:logging/logging.dart";
import 'package:shadcn_ui/shadcn_ui.dart';

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
    if (controller.isConnected) {
      controller.disconnect().catchError((err) {
        Logger.root.warning("unable to disconnect $err");
      });
    }
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WakeLocker(
      child: ShadToaster(
        child: _MeetingControllerData(controller: controller, child: widget.builder(context, controller)),
      ),
    );
  }
}

class PendingLocalMediaState extends ChangeNotifier {
  bool _cameraPending = false;
  bool _microphonePending = false;
  bool _cameraAwaitingEnableConfirmation = false;
  bool _microphoneAwaitingEnableConfirmation = false;

  bool get cameraPending => _cameraPending;
  bool get microphonePending => _microphonePending;

  void setCameraPending(bool value, {bool awaitEnableConfirmation = false}) {
    if (_cameraPending == value && _cameraAwaitingEnableConfirmation == awaitEnableConfirmation) {
      return;
    }

    _cameraPending = value;
    _cameraAwaitingEnableConfirmation = value && awaitEnableConfirmation;
    notifyListeners();
  }

  void setMicrophonePending(bool value, {bool awaitEnableConfirmation = false}) {
    if (_microphonePending == value && _microphoneAwaitingEnableConfirmation == awaitEnableConfirmation) {
      return;
    }

    _microphonePending = value;
    _microphoneAwaitingEnableConfirmation = value && awaitEnableConfirmation;
    notifyListeners();
  }

  void setPending({
    required bool cameraPending,
    required bool microphonePending,
    bool cameraAwaitEnableConfirmation = false,
    bool microphoneAwaitEnableConfirmation = false,
  }) {
    if (_cameraPending == cameraPending &&
        _microphonePending == microphonePending &&
        _cameraAwaitingEnableConfirmation == (cameraPending && cameraAwaitEnableConfirmation) &&
        _microphoneAwaitingEnableConfirmation == (microphonePending && microphoneAwaitEnableConfirmation)) {
      return;
    }

    _cameraPending = cameraPending;
    _microphonePending = microphonePending;
    _cameraAwaitingEnableConfirmation = cameraPending && cameraAwaitEnableConfirmation;
    _microphoneAwaitingEnableConfirmation = microphonePending && microphoneAwaitEnableConfirmation;
    notifyListeners();
  }

  void clear() {
    setPending(cameraPending: false, microphonePending: false);
  }
}

class MeetingController extends ChangeNotifier {
  MeetingController({required this.room, livekit.RoomOptions? roomOptions})
    : livekitRoom = livekit.Room(roomOptions: roomOptions ?? livekit.RoomOptions()) {
    livekitRoom.addListener(_onRoomChanged);
    _syncObservedLocalParticipant();
  }

  final RoomClient room;
  LivekitConnectionInfo? _config;
  final livekit.Room livekitRoom;
  final PendingLocalMediaState pendingLocalMedia = PendingLocalMediaState();
  livekit.LocalParticipant? _observedLocalParticipant;

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

  void _syncObservedLocalParticipant() {
    final localParticipant = livekitRoom.localParticipant;
    if (_observedLocalParticipant == localParticipant) {
      return;
    }

    _observedLocalParticipant?.removeListener(_onLocalParticipantChanged);
    _observedLocalParticipant = localParticipant;
    _observedLocalParticipant?.addListener(_onLocalParticipantChanged);
  }

  void _onLocalParticipantChanged() {
    _syncPendingLocalMediaState();
    notifyListeners();
  }

  void _syncPendingLocalMediaState() {
    if (livekitRoom.connectionState == livekit.ConnectionState.disconnected) {
      pendingLocalMedia.clear();
      return;
    }

    final localParticipant = _observedLocalParticipant;
    if (pendingLocalMedia._cameraAwaitingEnableConfirmation && (localParticipant?.isCameraEnabled() ?? false)) {
      pendingLocalMedia.setCameraPending(false);
    }
    if (pendingLocalMedia._microphoneAwaitingEnableConfirmation && (localParticipant?.isMicrophoneEnabled() ?? false)) {
      pendingLocalMedia.setMicrophonePending(false);
    }
  }

  void _onRoomChanged() {
    _syncObservedLocalParticipant();
    _syncPendingLocalMediaState();
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

    pendingLocalMedia.setPending(
      cameraPending: fastConnectOptions?.camera.enabled == true,
      microphonePending: fastConnectOptions?.microphone.enabled == true,
      cameraAwaitEnableConfirmation: fastConnectOptions?.camera.enabled == true,
      microphoneAwaitEnableConfirmation: fastConnectOptions?.microphone.enabled == true,
    );
    try {
      await livekitRoom.connect(config.url, config.token, fastConnectOptions: fastConnectOptions);
      _syncPendingLocalMediaState();
    } catch (error) {
      pendingLocalMedia.clear();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    pendingLocalMedia.clear();
    await livekitRoom.disconnect();
  }

  bool get isConnected {
    return livekitRoom.connectionState != livekit.ConnectionState.disconnected;
  }

  @override
  void dispose() {
    livekitRoom.removeListener(_onRoomChanged);
    _observedLocalParticipant?.removeListener(_onLocalParticipantChanged);
    pendingLocalMedia.dispose();
    super.dispose();
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
