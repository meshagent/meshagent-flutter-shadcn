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
const String _disabledDeviceDescription = 'Check your device settings';
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

String _deviceLabel(livekit.MediaDevice? device, String fallbackPrefix) {
  final trimmedLabel = device?.label.trim();
  if (trimmedLabel != null && trimmedLabel.isNotEmpty) {
    return _normalizedDeviceLabel(trimmedLabel);
  }

  return 'Default $fallbackPrefix';
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

String _describeDeviceSwitchError(String label, Object error) {
  final message = '$error';
  if (message.contains('NotAllowedError')) {
    return '$label access was blocked by the browser or system.';
  }
  if (message.contains('NotFoundError')) {
    return 'The selected ${label.toLowerCase()} was not found.';
  }
  return 'Unable to switch ${label.toLowerCase()}: $message';
}

livekit.LocalTrackPublication<livekit.LocalVideoTrack>? _cameraPublication(livekit.LocalParticipant? participant) {
  final publication = participant?.getTrackPublicationBySource(livekit.TrackSource.camera);
  if (publication is! livekit.LocalTrackPublication<livekit.LocalVideoTrack>) {
    return null;
  }

  return publication;
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
              _ChangeSettings(room: controller.livekitRoom),
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
  bool _processing = false;

  String _describeCameraToggleError(Object error) {
    final message = '$error';
    if (message.contains('NotAllowedError')) {
      return 'Camera access was blocked by the browser or system.';
    }
    if (message.contains('NotFoundError')) {
      return 'The selected camera was not found.';
    }
    return 'Unable to change camera state: $message';
  }

  Future<void> _toggleCamera(livekit.LocalParticipant localParticipant, bool enabled) async {
    if (_processing) {
      return;
    }

    final toaster = ShadToaster.maybeOf(context);
    setState(() {
      _processing = true;
    });

    try {
      await localParticipant.setCameraEnabled(enabled);
    } catch (error) {
      toaster?.show(ShadToast.destructive(description: Text(_describeCameraToggleError(error))));
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localParticipant = widget.controller.livekitRoom.localParticipant;
    return ListenableBuilder(
      listenable: Listenable.merge([localParticipant!, widget.controller.pendingLocalMedia]),
      builder: (context, _) {
        final enabled = localParticipant.isCameraEnabled();
        final pending = widget.controller.pendingLocalMedia.cameraPending;
        final showEnabled = enabled || pending;

        return _MeetingControlsButon(
          text: pending
              ? "Starting camera"
              : enabled
              ? "Turn off camera"
              : "Turn on camera",
          on: showEnabled,
          onColor: Colors.black,
          onForeground: Colors.white,
          offColor: ShadTheme.of(context).colorScheme.destructive,
          offForeground: Colors.white,
          icon: showEnabled ? LucideIcons.video : LucideIcons.videoOff,
          loading: pending || _processing,
          onPressed: (_processing || pending) ? null : () => unawaited(_toggleCamera(localParticipant, !enabled)),
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
  bool _processing = false;

  String _describeMicrophoneToggleError(Object error) {
    final message = '$error';
    if (message.contains('NotAllowedError')) {
      return 'Microphone access was blocked by the browser or system.';
    }
    if (message.contains('NotFoundError')) {
      return 'The selected microphone was not found.';
    }
    return 'Unable to change microphone state: $message';
  }

  Future<void> _toggleMicrophone(livekit.LocalParticipant localParticipant, bool enabled) async {
    if (_processing) {
      return;
    }

    final toaster = ShadToaster.maybeOf(context);
    setState(() {
      _processing = true;
    });

    try {
      await localParticipant.setMicrophoneEnabled(enabled);
    } catch (error) {
      toaster?.show(ShadToast.destructive(description: Text(_describeMicrophoneToggleError(error))));
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localParticipant = widget.controller.livekitRoom.localParticipant;
    return ListenableBuilder(
      listenable: Listenable.merge([localParticipant!, widget.controller.pendingLocalMedia]),
      builder: (context, _) {
        final enabled = localParticipant.isMicrophoneEnabled();
        final pending = widget.controller.pendingLocalMedia.microphonePending;
        final showEnabled = enabled || pending;

        return _MeetingControlsButon(
          text: pending
              ? "Starting mic"
              : enabled
              ? "Turn off mic"
              : "Turn on mic",
          on: showEnabled,
          onColor: Colors.black,
          onForeground: Colors.white,
          offColor: ShadTheme.of(context).colorScheme.destructive,
          offForeground: Colors.white,
          icon: showEnabled ? LucideIcons.mic : LucideIcons.micOff,
          loading: pending || _processing,
          onPressed: (_processing || pending) ? null : () => unawaited(_toggleMicrophone(localParticipant, !enabled)),
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
              unawaited(controller.connect());
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
            loading: true,
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
    this.loading = false,
  });

  final void Function()? onPressed;
  final String text;
  final Color onColor;
  final Color offColor;
  final Color onForeground;
  final Color offForeground;
  final IconData icon;

  final bool on;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = on ? onForeground : (onPressed != null ? offForeground : Colors.grey);

    return Tooltip(
      message: text,
      child: ShadIconButton(
        width: 48,
        height: 48,
        onPressed: onPressed,
        backgroundColor: on ? onColor : offColor,
        foregroundColor: foregroundColor,
        icon: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(foregroundColor)),
              )
            : Icon(icon, size: 22),
      ),
    );
  }
}

class _ChangeSettings extends StatelessWidget {
  const _ChangeSettings({required this.room});

  static const Duration _minimumPendingDuration = Duration(milliseconds: 350);

  final livekit.Room room;

  Future<void> _runWithMinimumPendingDuration(Future<void> Function() action) async {
    final startedAt = DateTime.now();
    await action();
    final remaining = _minimumPendingDuration - DateTime.now().difference(startedAt);
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  Future<void> _runCameraDeviceSwitch(BuildContext context, Future<void> Function() action) async {
    final controller = MeetingController.maybeOf(context);
    final shouldShowPending = room.localParticipant?.isCameraEnabled() ?? false;
    if (shouldShowPending) {
      controller?.pendingLocalMedia.setCameraPending(true);
    }

    try {
      await _runWithMinimumPendingDuration(action);
    } finally {
      if (shouldShowPending) {
        controller?.pendingLocalMedia.setCameraPending(false);
      }
    }
  }

  Future<void> _runMicrophoneDeviceSwitch(BuildContext context, Future<void> Function() action) async {
    final controller = MeetingController.maybeOf(context);
    final shouldShowPending = room.localParticipant?.isMicrophoneEnabled() ?? false;
    if (shouldShowPending) {
      controller?.pendingLocalMedia.setMicrophonePending(true);
    }

    try {
      await _runWithMinimumPendingDuration(action);
    } finally {
      if (shouldShowPending) {
        controller?.pendingLocalMedia.setMicrophonePending(false);
      }
    }
  }

  Future<void> _selectVideoInput(BuildContext context, livekit.MediaDevice device) async {
    final track = _cameraPublication(room.localParticipant)?.track;

    await _runCameraDeviceSwitch(context, () async {
      await room.setVideoInputDevice(device);
      await track?.restartTrack(livekit.CameraCaptureOptions(deviceId: device.deviceId));
    });
  }

  Future<void> _selectAudioInput(BuildContext context, livekit.MediaDevice device) async {
    await _runMicrophoneDeviceSwitch(context, () => room.setAudioInputDevice(device));
  }

  Future<void> _selectAudioOutput(BuildContext context, livekit.MediaDevice device) async {
    await room.setAudioOutputDevice(device);
  }

  @override
  Widget build(BuildContext context) {
    return _ChangeDeviceButton(
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
    this.selectedVideoInputDeviceId,
    this.selectedAudioInputDeviceId,
    this.selectedAudioOutputDeviceId,
  });

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
  static const BoxConstraints _dialogConstraints = BoxConstraints(maxWidth: 560);

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

  Future<void> _loadDevices() async {
    _devices = await _getDevices();
    await _syncUnavailableSelections();
    if (mounted) {
      setState(() {});
    }
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

  Future<void> _showDialog() async {
    await _loadDevices();
    if (!mounted) {
      return;
    }

    await showShadDialog<void>(
      context: context,
      builder: (dialogContext) => _ChangeDeviceDialog(
        preferences: _preferences,
        initialDevices: List<livekit.MediaDevice>.of(_devices),
        onChangeVideoInput: onChangeVideoInput,
        onChangeAudioInput: onChangeAudioInput,
        onChangeAudioOutput: onChangeAudioOutput,
        syncUnavailableSelections: _syncUnavailableSelections,
        dialogConstraints: _dialogConstraints,
        selectedVideoInputDeviceId: widget.selectedVideoInputDeviceId,
        selectedAudioInputDeviceId: widget.selectedAudioInputDeviceId,
        selectedAudioOutputDeviceId: widget.selectedAudioOutputDeviceId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(width: 48, height: 48);
    }

    return Tooltip(
      message: "Device settings",
      child: ShadIconButton.outline(
        width: 48,
        height: 48,
        onPressed: () => unawaited(_showDialog()),
        icon: const Icon(LucideIcons.settings, size: 22),
      ),
    );
  }
}

class _ChangeDeviceDialog extends StatefulWidget {
  const _ChangeDeviceDialog({
    required this.preferences,
    required this.initialDevices,
    required this.onChangeVideoInput,
    required this.onChangeAudioInput,
    required this.onChangeAudioOutput,
    required this.syncUnavailableSelections,
    required this.dialogConstraints,
    this.selectedVideoInputDeviceId,
    this.selectedAudioInputDeviceId,
    this.selectedAudioOutputDeviceId,
  });

  final SharedPreferences preferences;
  final List<livekit.MediaDevice> initialDevices;
  final Future<void> Function(livekit.MediaDevice) onChangeVideoInput;
  final Future<void> Function(livekit.MediaDevice) onChangeAudioInput;
  final Future<void> Function(livekit.MediaDevice) onChangeAudioOutput;
  final Future<void> Function() syncUnavailableSelections;
  final BoxConstraints dialogConstraints;
  final String? Function()? selectedVideoInputDeviceId;
  final String? Function()? selectedAudioInputDeviceId;
  final String? Function()? selectedAudioOutputDeviceId;

  @override
  State<_ChangeDeviceDialog> createState() => _ChangeDeviceDialogState();
}

class _ChangeDeviceDialogState extends State<_ChangeDeviceDialog> {
  late List<livekit.MediaDevice> _devices = widget.initialDevices;
  StreamSubscription<List<livekit.MediaDevice>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = livekit.Hardware.instance.onDeviceChange.stream.listen((devices) {
      if (!mounted) {
        return;
      }

      setState(() {
        _devices = _sanitizeDevices(devices);
      });
      unawaited(_syncAfterDeviceChange());
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  List<livekit.MediaDevice> _sanitizeDevices(List<livekit.MediaDevice> devices) {
    return devices.where((device) => device.deviceId.isNotEmpty).toList();
  }

  Future<void> _syncAfterDeviceChange() async {
    await widget.syncUnavailableSelections();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _runDeviceChange(String label, Future<void> Function(livekit.MediaDevice) onChange, livekit.MediaDevice device) async {
    try {
      await onChange(device);
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ShadToaster.maybeOf(context)?.show(ShadToast.destructive(description: Text(_describeDeviceSwitchError(label, error))));
      debugPrint('Unable to switch device ${device.deviceId}: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoInput = widget.selectedVideoInputDeviceId?.call() ?? widget.preferences.getString("videoInput");
    final audioInput = widget.selectedAudioInputDeviceId?.call() ?? widget.preferences.getString("audioInput");
    final audioOutput = widget.selectedAudioOutputDeviceId?.call() ?? widget.preferences.getString("audioOutput");

    final videoInputs = _devices.where((device) => device.kind == "videoinput").toList();
    final audioInputs = _devices.where((device) => device.kind == "audioinput").toList();
    final audioOutputs = _devices.where((device) => device.kind == "audiooutput").toList();

    final visibleVideoInputs = _menuDevices(videoInputs);
    final visibleAudioInputs = _menuDevices(audioInputs);
    final visibleAudioOutputs = _menuDevices(audioOutputs);

    final selectedVideoDevice = _selectedMenuDevice(videoInputs, videoInput);
    final selectedAudioInputDevice = _selectedMenuDevice(audioInputs, audioInput);
    final selectedAudioOutputDevice = _selectedMenuDevice(audioOutputs, audioOutput);

    return ShadDialog(
      title: const Text("Device settings"),
      description: const Text("Choose your camera, microphone, and speakers."),
      constraints: widget.dialogConstraints,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      actions: [
        ShadButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text("Done"),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DeviceSettingsSection(
                label: "Camera",
                devices: visibleVideoInputs,
                selectedDevice: selectedVideoDevice,
                onChange: (device) => _runDeviceChange("Camera", widget.onChangeVideoInput, device),
                icon: LucideIcons.video,
                disabledIcon: LucideIcons.videoOff,
                disabledLabel: "Camera disabled",
                disabledDescription: _disabledDeviceDescription,
              ),
              const SizedBox(height: 16),
              _DeviceSettingsSection(
                label: "Microphone",
                devices: visibleAudioInputs,
                selectedDevice: selectedAudioInputDevice,
                onChange: (device) => _runDeviceChange("Microphone", widget.onChangeAudioInput, device),
                icon: LucideIcons.mic,
                disabledIcon: LucideIcons.micOff,
                disabledLabel: "Microphone disabled",
                disabledDescription: _disabledDeviceDescription,
              ),
              if (kIsWeb) ...[
                const SizedBox(height: 16),
                _DeviceSettingsSection(
                  label: "Speakers",
                  devices: visibleAudioOutputs,
                  selectedDevice: selectedAudioOutputDevice,
                  onChange: (device) => _runDeviceChange("Speakers", widget.onChangeAudioOutput, device),
                  icon: LucideIcons.volume2,
                  disabledIcon: LucideIcons.volumeOff,
                  disabledLabel: "Speakers disabled",
                  disabledDescription: _disabledDeviceDescription,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceSettingsSection extends StatelessWidget {
  const _DeviceSettingsSection({
    required this.label,
    required this.devices,
    required this.selectedDevice,
    required this.onChange,
    required this.icon,
    required this.disabledIcon,
    required this.disabledLabel,
    required this.disabledDescription,
  });

  final String label;
  final List<livekit.MediaDevice> devices;
  final livekit.MediaDevice? selectedDevice;
  final Future<void> Function(livekit.MediaDevice) onChange;
  final IconData icon;
  final IconData disabledIcon;
  final String disabledLabel;
  final String disabledDescription;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isDisabled = selectedDevice == null;
    final accentColor = isDisabled ? theme.colorScheme.destructive : theme.colorScheme.foreground;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(isDisabled ? disabledIcon : icon, size: 18, color: accentColor),
            const SizedBox(width: 10),
            Text(label, style: theme.textTheme.large.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 10),
        if (isDisabled)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.destructive),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(disabledLabel, style: theme.textTheme.small.copyWith(color: theme.colorScheme.destructive)),
                const SizedBox(height: 4),
                Text(disabledDescription, style: theme.textTheme.muted.copyWith(color: theme.colorScheme.destructive)),
              ],
            ),
          )
        else
          ...devices.map(
            (device) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DeviceOptionTile(
                label: _deviceLabel(device, label),
                selected: device.deviceId == selectedDevice?.deviceId,
                onTap: () => unawaited(onChange(device)),
              ),
            ),
          ),
      ],
    );
  }
}

class _DeviceOptionTile extends StatelessWidget {
  const _DeviceOptionTile({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final borderColor = selected ? theme.colorScheme.foreground : theme.colorScheme.border;
    final backgroundColor = selected ? theme.colorScheme.card : theme.colorScheme.background;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
              if (selected) const Icon(LucideIcons.check, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
