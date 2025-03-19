import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../meetings/meetings.dart';
import 'package:flutter/material.dart';

class MeetingControls extends StatelessWidget {
  MeetingControls({required this.controller, this.spacing = 5, super.key});

  final double spacing;
  final MeetingController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.room,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConnectionButton(controller: controller),
            if (controller.room.localParticipant != null) ...[
              SizedBox(width: spacing),
              CameraToggle(controller: controller),
              SizedBox(width: spacing),
              MicToggle(controller: controller),
            ],
          ],
        );
      },
    );
  }
}

class CameraToggle extends StatefulWidget {
  const CameraToggle({super.key, required this.controller});

  final MeetingController controller;

  @override
  State<StatefulWidget> createState() => _CameraToggleState();
}

class _CameraToggleState extends State<CameraToggle> {
  @override
  Widget build(BuildContext context) {
    final localParticipant = widget.controller.room.localParticipant;
    return ListenableBuilder(
      listenable: localParticipant!,
      builder: (context, _) {
        final enabled = localParticipant.isCameraEnabled();

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MeetingControlsButon(
              text: enabled ? "Turn off camera" : "Turn on camera",
              on: enabled,
              onColor: Colors.black,
              onForeground: Colors.white,
              offColor: Colors.red,
              offForeground: Colors.white,
              icon: (enabled ? Icons.videocam : Icons.videocam_off),
              onPressed: () {
                setState(() {
                  localParticipant.setCameraEnabled(!enabled);
                });
              },
            ),
            _ChangeSettings(kind: _DeviceKind.videoInput, room: widget.controller.room),
          ],
        );
      },
    );
  }
}

class MicToggle extends StatefulWidget {
  const MicToggle({super.key, required this.controller});

  final MeetingController controller;

  @override
  State<StatefulWidget> createState() => _MicToggleState();
}

class _MicToggleState extends State<MicToggle> {
  @override
  Widget build(BuildContext context) {
    final localParticipant = widget.controller.room.localParticipant;
    return ListenableBuilder(
      listenable: localParticipant!,
      builder: (context, _) {
        final enabled = localParticipant.isMicrophoneEnabled();

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MeetingControlsButon(
              text: enabled ? "Turn off mic" : "Turn on mic",
              on: enabled,
              onColor: Colors.black,
              onForeground: Colors.white,
              offColor: Colors.red,
              offForeground: Colors.white,
              icon: (enabled ? Icons.mic : Icons.mic_off),
              onPressed: () {
                setState(() {
                  localParticipant.setMicrophoneEnabled(!enabled);
                });
              },
            ),
            _ChangeSettings(kind: _DeviceKind.audioInput, room: widget.controller.room),
          ],
        );
      },
    );
  }
}

class ConnectionButton extends StatelessWidget {
  const ConnectionButton({super.key, required this.controller});

  final MeetingController controller;

  @override
  Widget build(BuildContext context) {
    final room = controller.room;

    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        return switch (room.connectionState) {
          livekit.ConnectionState.connected => _MeetingControlsButon(
              text: "Hangup",
              on: false,
              onColor: Colors.black,
              onForeground: Colors.white,
              offColor: Colors.red,
              offForeground: Colors.white,
              icon: Icons.phone,
              onPressed: () {
                controller.disconnect();
              },
            ),
          livekit.ConnectionState.disconnected => _MeetingControlsButon(
              text: "Connect",
              on: false,
              onColor: Colors.black,
              onForeground: Colors.white,
              offColor: Colors.black,
              offForeground: Colors.white,
              icon: Icons.phone,
              onPressed: () {
                controller.disconnect();
              },
            ),
          _ => const _MeetingControlsButon(
              text: "Connecting",
              on: false,
              onColor: Colors.black,
              onForeground: Colors.white,
              offColor: Colors.red,
              offForeground: Colors.white,
              icon: Icons.phone,
            ),
        };
      },
    );
  }
}

class _MeetingControlsButon extends StatelessWidget {
  const _MeetingControlsButon({
    required this.text,
    required this.icon,
    this.onPressed,
    this.onColor = const Color.fromRGBO(47, 45, 87, 1),
    this.offColor = Colors.transparent,
    this.onForeground = Colors.white,
    this.offForeground = Colors.black,
    this.on = false,
  });

  final void Function()? onPressed;
  final String text;
  final Color onColor;
  final Color offColor;
  final Color onForeground;
  final Color offForeground;
  final IconData icon;

  final bool on;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Tooltip(
          message: text,
          child: SizedBox(
            width: 40,
            height: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(100), color: on ? onColor : offColor),
              child: Center(child: Icon(icon, size: 22, color: on ? onForeground : (onPressed != null ? offForeground : Colors.grey))),
            ),
          ),
        ),
      ),
    );
  }
}

enum _DeviceKind { audioInput, audioOutput, videoInput }

class _ChangeSettings extends StatelessWidget {
  const _ChangeSettings({required this.kind, required this.room});

  final livekit.Room room;
  final _DeviceKind kind;

  void _selectVideoInput(BuildContext context, livekit.MediaDevice device) async {
    await room.setVideoInputDevice(device);
  }

  void _selectAudioInput(BuildContext context, livekit.MediaDevice device) async {
    await room.setAudioInputDevice(device);
  }

  void _selectAudioOutput(BuildContext context, livekit.MediaDevice device) async {
    await room.setAudioOutputDevice(device);
  }

  @override
  Widget build(BuildContext context) {
    return _ChangeDeviceButton(
      kind: kind,
      onChangeVideoInput: (device) => _selectVideoInput(context, device),
      onChangeAudioInput: (device) => _selectAudioInput(context, device),
      onChangeAudioOutput: (device) => _selectAudioOutput(context, device),
    );
  }
}

class _ChangeDeviceButton extends StatefulWidget {
  const _ChangeDeviceButton({
    required this.onChangeVideoInput,
    required this.onChangeAudioInput,
    required this.onChangeAudioOutput,
    this.kind,
  });

  final _DeviceKind? kind;

  final Function(livekit.MediaDevice device) onChangeVideoInput;
  final Function(livekit.MediaDevice device) onChangeAudioInput;
  final Function(livekit.MediaDevice device) onChangeAudioOutput;

  @override
  _ChangeDeviceButtonState createState() => _ChangeDeviceButtonState();
}

class _ChangeDeviceButtonState extends State<_ChangeDeviceButton> {
  bool _loaded = false;
  late SharedPreferences _preferences;
  late List<livekit.MediaDevice> _devices;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _load();

    _subscription = livekit.Hardware.instance.onDeviceChange.stream.listen((List<livekit.MediaDevice> devices) {
      _devices = _sanitizeDevices(devices);
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();

    super.dispose();
  }

  Future<void> _load() async {
    _preferences = await SharedPreferences.getInstance();
    _devices = await _getDevices();

    if (mounted) {
      setState(() {
        _loaded = true;
      });
    }
  }

  Future<List<livekit.MediaDevice>> _getDevices() async {
    final devices = await livekit.Hardware.instance.enumerateDevices();
    return _sanitizeDevices(devices);
  }

  List<livekit.MediaDevice> _sanitizeDevices(List<livekit.MediaDevice> devices) {
    return devices.where((d) => d.deviceId.isNotEmpty).toList();
  }

  void _updateDevice(String key, livekit.MediaDevice device, Function(livekit.MediaDevice) onChange) {
    onChange(device);
    _preferences.setString(key, device.deviceId);
    setState(() {});
  }

  void onChangeVideoInput(livekit.MediaDevice device) => _updateDevice("videoInput", device, widget.onChangeVideoInput);
  void onChangeAudioInput(livekit.MediaDevice device) => _updateDevice("audioInput", device, widget.onChangeAudioInput);
  void onChangeAudioOutput(livekit.MediaDevice device) => _updateDevice("audioOutput", device, widget.onChangeAudioOutput);

  final menuController = ShadContextMenuController();
  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Container();
    }

    final videoInput = _preferences.getString("videoInput");
    final audioInput = _preferences.getString("audioInput");
    final audioOutput = _preferences.getString("audioOutput");

    final videoInputs = _devices.where((d) => d.kind == "videoinput").toList();
    final audioInputs = _devices.where((d) => d.kind == "audioinput").toList();
    final audioOutputs = _devices.where((d) => d.kind == "audiooutput").toList();

    final selectedVideoDevice = videoInputs.where((device) => device.deviceId == videoInput).firstOrNull ?? videoInputs.firstOrNull;
    final selectedAudioInputDevice = audioInputs.where((device) => device.deviceId == audioInput).firstOrNull ?? audioInputs.firstOrNull;
    final selectedAudioOutputDevice =
        audioOutputs.where((device) => device.deviceId == audioOutput).firstOrNull ?? audioOutputs.firstOrNull;

    return ShadContextMenuRegion(
      controller: menuController,
      visible: menuController.isOpen,
      items: [
        if (widget.kind == null || widget.kind == _DeviceKind.videoInput)
          for (final device in videoInputs)
            ShadContextMenuItem(
              trailing: selectedVideoDevice == device ? Icon(Icons.check) : null,
              onPressed: () => onChangeVideoInput(device),
              child: Text(device.label),
            ),
        if (widget.kind == null || widget.kind == _DeviceKind.audioInput)
          for (final device in audioInputs)
            ShadContextMenuItem(
              trailing: selectedAudioInputDevice == device ? Icon(Icons.check) : null,
              onPressed: () => onChangeAudioInput(device),
              child: Text(device.label),
            ),
        if (kIsWeb && widget.kind == null || widget.kind == _DeviceKind.audioOutput)
          for (final device in audioOutputs)
            ShadContextMenuItem(
              trailing: selectedAudioOutputDevice == device ? Icon(Icons.check) : null,
              onPressed: () => onChangeAudioOutput(device),
              child: Text(device.label),
            ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            setState(() {
              menuController.setOpen(!menuController.isOpen);
            });
          },
          child: Icon(Icons.keyboard_arrow_down),
        ),
      ),
    );
  }
}
