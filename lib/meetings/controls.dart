import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../meetings/meetings.dart';
import 'package:flutter/material.dart';

const String _defaultDeviceLabelPrefix = 'Default - ';
const String _builtInDeviceLabelSuffix = ' (Built-in)';
const List<String> _builtInDeviceLabelPrefixes = ['macbook ', 'built-in ', 'internal '];

bool _isDefaultAliasDevice(livekit.MediaDevice device) {
  return device.deviceId == 'default' || device.label.trim().startsWith(_defaultDeviceLabelPrefix);
}

String _normalizedDeviceLabel(String label) {
  var trimmedLabel = label.trim();
  if (trimmedLabel.startsWith(_defaultDeviceLabelPrefix)) {
    trimmedLabel = trimmedLabel.substring(_defaultDeviceLabelPrefix.length).trim();
  }

  if (_shouldStripBuiltInSuffix(trimmedLabel)) {
    return trimmedLabel.substring(0, trimmedLabel.length - _builtInDeviceLabelSuffix.length).trim();
  }

  return trimmedLabel;
}

bool _shouldStripBuiltInSuffix(String label) {
  if (!label.endsWith(_builtInDeviceLabelSuffix)) {
    return false;
  }

  final normalizedLabel = label.toLowerCase();
  return !_builtInDeviceLabelPrefixes.any((prefix) => normalizedLabel.startsWith(prefix));
}

livekit.MediaDevice? _matchingPhysicalDevice(livekit.MediaDevice device, List<livekit.MediaDevice> devices) {
  final normalizedLabel = _normalizedDeviceLabel(device.label);
  final groupId = device.groupId?.trim();

  return devices.firstWhereOrNull((candidate) {
    if (candidate.kind != device.kind || candidate.deviceId == device.deviceId || _isDefaultAliasDevice(candidate)) {
      return false;
    }

    final candidateGroupId = candidate.groupId?.trim();
    if (groupId != null && groupId.isNotEmpty && candidateGroupId == groupId) {
      return true;
    }

    return _normalizedDeviceLabel(candidate.label) == normalizedLabel;
  });
}

List<livekit.MediaDevice> _menuDevices(List<livekit.MediaDevice> devices) {
  return devices
      .where((device) {
        if (!_isDefaultAliasDevice(device)) {
          return true;
        }

        return _matchingPhysicalDevice(device, devices) == null;
      })
      .toList(growable: false);
}

livekit.MediaDevice? _selectedMenuDevice(List<livekit.MediaDevice> devices, String? selectedDeviceId) {
  final visibleDevices = _menuDevices(devices);
  if (visibleDevices.isEmpty) {
    return null;
  }

  if (selectedDeviceId == null || selectedDeviceId.isEmpty) {
    return visibleDevices.first;
  }

  final exactDevice = devices.firstWhereOrNull((device) => device.deviceId == selectedDeviceId);
  if (exactDevice == null) {
    return visibleDevices.first;
  }

  return _matchingPhysicalDevice(exactDevice, visibleDevices) ??
      visibleDevices.firstWhereOrNull((device) => device.deviceId == exactDevice.deviceId) ??
      visibleDevices.first;
}

class MeetingControls extends StatelessWidget {
  const MeetingControls({required this.controller, this.spacing = 5, super.key});

  final double spacing;
  final MeetingController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.livekitRoom,
      builder: (context, _) {
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: spacing,
          runSpacing: spacing,
          children: [
            ConnectionButton(controller: controller),
            if (controller.livekitRoom.localParticipant != null) ...[
              MicToggle(controller: controller),
              CameraToggle(controller: controller),
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
    final localParticipant = widget.controller.livekitRoom.localParticipant;
    return ListenableBuilder(
      listenable: localParticipant!,
      builder: (context, _) {
        final enabled = localParticipant.isCameraEnabled();

        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            _MeetingControlsButon(
              text: enabled ? "Turn off camera" : "Turn on camera",
              on: enabled,
              onColor: Colors.black,
              onForeground: Colors.white,
              offColor: ShadTheme.of(context).colorScheme.destructive,
              offForeground: Colors.white,
              icon: enabled ? LucideIcons.video : LucideIcons.videoOff,
              onPressed: () {
                setState(() {
                  localParticipant.setCameraEnabled(!enabled);
                });
              },
            ),
            _ChangeSettings(kind: _DeviceKind.videoInput, room: widget.controller.livekitRoom),
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
    final localParticipant = widget.controller.livekitRoom.localParticipant;
    return ListenableBuilder(
      listenable: localParticipant!,
      builder: (context, _) {
        final enabled = localParticipant.isMicrophoneEnabled();

        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            _MeetingControlsButon(
              text: enabled ? "Turn off mic" : "Turn on mic",
              on: enabled,
              onColor: Colors.black,
              onForeground: Colors.white,
              offColor: ShadTheme.of(context).colorScheme.destructive,
              offForeground: Colors.white,
              icon: enabled ? LucideIcons.mic : LucideIcons.micOff,
              onPressed: () {
                setState(() {
                  localParticipant.setMicrophoneEnabled(!enabled);
                });
              },
            ),
            _ChangeSettings(kind: _DeviceKind.audioInput, room: widget.controller.livekitRoom),
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
    final room = controller.livekitRoom;

    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        return switch (room.connectionState) {
          livekit.ConnectionState.connected => _MeetingControlsButon(
            text: "Hangup",
            on: false,
            onColor: Colors.black,
            onForeground: Colors.white,
            offColor: ShadTheme.of(context).colorScheme.destructive,
            offForeground: Colors.white,
            icon: LucideIcons.phone,
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
            icon: LucideIcons.phone,
            onPressed: () {
              controller.disconnect();
            },
          ),
          _ => _MeetingControlsButon(
            text: "Connecting",
            on: false,
            onColor: Colors.black,
            onForeground: Colors.white,
            offColor: ShadTheme.of(context).colorScheme.destructive,
            offForeground: Colors.white,
            icon: LucideIcons.phone,
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
    return Tooltip(
      message: text,
      child: ShadIconButton(
        width: 48,
        height: 48,
        onPressed: onPressed,
        backgroundColor: on ? onColor : offColor,
        foregroundColor: on ? onForeground : (onPressed != null ? offForeground : Colors.grey),
        icon: Icon(icon, size: 22),
      ),
    );
  }
}

enum _DeviceKind { audioInput, audioOutput, videoInput }

class _ChangeSettings extends StatelessWidget {
  const _ChangeSettings({required this.kind, required this.room});

  final livekit.Room room;
  final _DeviceKind kind;

  Future<void> _selectVideoInput(BuildContext context, livekit.MediaDevice device) async {
    await room.setVideoInputDevice(device);
  }

  Future<void> _selectAudioInput(BuildContext context, livekit.MediaDevice device) async {
    await room.setAudioInputDevice(device);
  }

  Future<void> _selectAudioOutput(BuildContext context, livekit.MediaDevice device) async {
    await room.setAudioOutputDevice(device);
  }

  @override
  Widget build(BuildContext context) {
    return _ChangeDeviceButton(
      kind: kind,
      onChangeVideoInput: (device) => _selectVideoInput(context, device),
      onChangeAudioInput: (device) => _selectAudioInput(context, device),
      onChangeAudioOutput: (device) => _selectAudioOutput(context, device),
      selectedVideoInputDeviceId: () => room.selectedVideoInputDeviceId,
      selectedAudioInputDeviceId: () => room.selectedAudioInputDeviceId,
      selectedAudioOutputDeviceId: () => room.selectedAudioOutputDeviceId,
    );
  }
}

class _ChangeDeviceButton extends StatefulWidget {
  const _ChangeDeviceButton({
    required this.onChangeVideoInput,
    required this.onChangeAudioInput,
    required this.onChangeAudioOutput,
    this.kind,
    this.selectedVideoInputDeviceId,
    this.selectedAudioInputDeviceId,
    this.selectedAudioOutputDeviceId,
  });

  final _DeviceKind? kind;

  final Future<void> Function(livekit.MediaDevice device) onChangeVideoInput;
  final Future<void> Function(livekit.MediaDevice device) onChangeAudioInput;
  final Future<void> Function(livekit.MediaDevice device) onChangeAudioOutput;
  final String? Function()? selectedVideoInputDeviceId;
  final String? Function()? selectedAudioInputDeviceId;
  final String? Function()? selectedAudioOutputDeviceId;

  @override
  _ChangeDeviceButtonState createState() => _ChangeDeviceButtonState();
}

class _ChangeDeviceButtonState extends State<_ChangeDeviceButton> {
  bool _loaded = false;
  late SharedPreferences _preferences;
  late List<livekit.MediaDevice> _devices;
  StreamSubscription? _subscription;
  bool _syncingUnavailableSelections = false;

  @override
  void initState() {
    super.initState();
    _load();

    _subscription = livekit.Hardware.instance.onDeviceChange.stream.listen((List<livekit.MediaDevice> devices) {
      _devices = _sanitizeDevices(devices);
      if (mounted) {
        setState(() {});
      }
      unawaited(_syncUnavailableSelections());
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

    await _syncUnavailableSelections();
  }

  Future<List<livekit.MediaDevice>> _getDevices() async {
    final devices = await livekit.Hardware.instance.enumerateDevices();
    return _sanitizeDevices(devices);
  }

  List<livekit.MediaDevice> _sanitizeDevices(List<livekit.MediaDevice> devices) {
    return devices.where((d) => d.deviceId.isNotEmpty).toList();
  }

  String? _selectedDeviceIdForPreferenceKey(String key) {
    return switch (key) {
      "videoInput" => widget.selectedVideoInputDeviceId?.call() ?? _preferences.getString(key),
      "audioInput" => widget.selectedAudioInputDeviceId?.call() ?? _preferences.getString(key),
      "audioOutput" => widget.selectedAudioOutputDeviceId?.call() ?? _preferences.getString(key),
      _ => _preferences.getString(key),
    };
  }

  String? Function()? _selectedDeviceIdGetterForPreferenceKey(String key) {
    return switch (key) {
      "videoInput" => widget.selectedVideoInputDeviceId,
      "audioInput" => widget.selectedAudioInputDeviceId,
      "audioOutput" => widget.selectedAudioOutputDeviceId,
      _ => null,
    };
  }

  Future<void> _updateDevice(String key, livekit.MediaDevice device, Future<void> Function(livekit.MediaDevice) onChange) async {
    await onChange(device);
    final selectedDeviceIdGetter = _selectedDeviceIdGetterForPreferenceKey(key);
    if (selectedDeviceIdGetter != null && selectedDeviceIdGetter() != device.deviceId) {
      throw StateError('Unable to switch $key to ${device.deviceId}');
    }
    await _preferences.setString(key, device.deviceId);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _syncUnavailableSelection({
    required String preferenceKey,
    required List<livekit.MediaDevice> devices,
    required Future<void> Function(livekit.MediaDevice) onChange,
  }) async {
    final visibleDevices = _menuDevices(devices);
    final selectedDeviceId = _selectedDeviceIdForPreferenceKey(preferenceKey);
    final selectedDevice = selectedDeviceId == null ? null : devices.firstWhereOrNull((device) => device.deviceId == selectedDeviceId);

    if (visibleDevices.isEmpty) {
      if (_preferences.containsKey(preferenceKey)) {
        await _preferences.remove(preferenceKey);
      }
      return;
    }

    if (selectedDeviceId == null || selectedDeviceId.isEmpty || selectedDevice != null) {
      return;
    }

    final fallbackDevice = visibleDevices.first;
    await onChange(fallbackDevice);
    await _preferences.setString(preferenceKey, fallbackDevice.deviceId);
  }

  Future<void> _syncUnavailableSelections() async {
    if (!_loaded || _syncingUnavailableSelections) {
      return;
    }

    _syncingUnavailableSelections = true;
    try {
      await _syncUnavailableSelection(
        preferenceKey: "videoInput",
        devices: _devices.where((device) => device.kind == "videoinput").toList(growable: false),
        onChange: widget.onChangeVideoInput,
      );
      await _syncUnavailableSelection(
        preferenceKey: "audioInput",
        devices: _devices.where((device) => device.kind == "audioinput").toList(growable: false),
        onChange: widget.onChangeAudioInput,
      );
      await _syncUnavailableSelection(
        preferenceKey: "audioOutput",
        devices: _devices.where((device) => device.kind == "audiooutput").toList(growable: false),
        onChange: widget.onChangeAudioOutput,
      );
    } finally {
      _syncingUnavailableSelections = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> onChangeVideoInput(livekit.MediaDevice device) => _updateDevice("videoInput", device, widget.onChangeVideoInput);
  Future<void> onChangeAudioInput(livekit.MediaDevice device) => _updateDevice("audioInput", device, widget.onChangeAudioInput);
  Future<void> onChangeAudioOutput(livekit.MediaDevice device) => _updateDevice("audioOutput", device, widget.onChangeAudioOutput);

  final menuController = ShadContextMenuController();

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Container();
    }

    final videoInput = _selectedDeviceIdForPreferenceKey("videoInput");
    final audioInput = _selectedDeviceIdForPreferenceKey("audioInput");
    final audioOutput = _selectedDeviceIdForPreferenceKey("audioOutput");

    final videoInputs = _devices.where((d) => d.kind == "videoinput").toList();
    final audioInputs = _devices.where((d) => d.kind == "audioinput").toList();
    final audioOutputs = _devices.where((d) => d.kind == "audiooutput").toList();

    final visibleVideoInputs = _menuDevices(videoInputs);
    final visibleAudioInputs = _menuDevices(audioInputs);
    final visibleAudioOutputs = _menuDevices(audioOutputs);

    final selectedVideoDevice = _selectedMenuDevice(videoInputs, videoInput);
    final selectedAudioInputDevice = _selectedMenuDevice(audioInputs, audioInput);
    final selectedAudioOutputDevice = _selectedMenuDevice(audioOutputs, audioOutput);

    return ShadContextMenuRegion(
      controller: menuController,
      visible: menuController.isOpen,
      items: [
        if (widget.kind == null || widget.kind == _DeviceKind.videoInput)
          for (final device in visibleVideoInputs)
            ShadContextMenuItem(
              trailing: selectedVideoDevice == device ? Icon(Icons.check) : null,
              onPressed: () => unawaited(_runDeviceChange(onChangeVideoInput, device)),
              child: Text(_normalizedDeviceLabel(device.label)),
            ),
        if (widget.kind == null || widget.kind == _DeviceKind.audioInput)
          for (final device in visibleAudioInputs)
            ShadContextMenuItem(
              trailing: selectedAudioInputDevice == device ? Icon(Icons.check) : null,
              onPressed: () => unawaited(_runDeviceChange(onChangeAudioInput, device)),
              child: Text(_normalizedDeviceLabel(device.label)),
            ),
        if (kIsWeb && widget.kind == null || widget.kind == _DeviceKind.audioOutput)
          for (final device in visibleAudioOutputs)
            ShadContextMenuItem(
              trailing: selectedAudioOutputDevice == device ? Icon(Icons.check) : null,
              onPressed: () => unawaited(_runDeviceChange(onChangeAudioOutput, device)),
              child: Text(_normalizedDeviceLabel(device.label)),
            ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: "Change device",
          child: ShadIconButton.ghost(
            width: 28,
            height: 48,
            onPressed: () {
              setState(() {
                menuController.setOpen(!menuController.isOpen);
              });
            },
            icon: const Icon(LucideIcons.chevronDown, size: 18),
          ),
        ),
      ),
    );
  }

  Future<void> _runDeviceChange(Future<void> Function(livekit.MediaDevice) onChange, livekit.MediaDevice device) async {
    try {
      await onChange(device);
    } catch (error) {
      debugPrint('Unable to switch device ${device.deviceId}: $error');
    }
  }
}
