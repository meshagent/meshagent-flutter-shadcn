import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:interactive_viewer_2/interactive_viewer_2.dart';
import 'package:meshagent/meshagent.dart';
import 'package:meshagent_agents/meshagent_agents.dart'
    show
        AgentMessage,
        AgentClientToolCallRequested,
        AgentThreadMessage,
        AgentThreadStatus,
        AgentToolCallArgumentsDelta,
        AgentToolCallEnded,
        AgentToolCallPending,
        AgentUsageUpdated,
        CapabilitiesRequest,
        CapabilitiesResponse,
        CloseThread,
        ClientToolkitDescription,
        OpenThread,
        ToolChoice,
        ToolkitCapabilities,
        TurnStart,
        TurnStartAccepted,
        TurnStartRejected,
        TurnStarted,
        TurnSteer,
        TurnSteerAccepted,
        TurnSteerRejected,
        TurnSteered,
        TurnMcpConfig,
        agentRoomMessageType,
        agentThreadClearType,
        agentThreadClearedType,
        agentThreadStatusType,
        agentToolApproveType,
        agentToolCallArgumentsDeltaType,
        agentToolCallEndedType,
        agentToolCallInProgressType,
        agentToolCallPendingType,
        agentToolCallStartedType,
        agentToolRejectType,
        agentTurnEndedType,
        agentTurnInterruptedType,
        agentTurnInterruptAcceptedType,
        agentTurnInterruptType,
        agentTurnStartedType,
        agentTurnStartAcceptedType,
        agentTurnStartRejectedType,
        agentTurnStartType,
        agentTurnSteeredType,
        agentTurnSteerAcceptedType,
        agentTurnSteerRejectedType,
        agentTurnSteerType,
        agentUsageUpdatedType;
import 'package:meshagent_flutter_shadcn/chat_bubble_markdown_config.dart';
import 'package:meshagent_flutter_shadcn/code_editor.dart';
import 'package:meshagent_flutter_shadcn/code_language_resolver.dart';
import 'package:meshagent_flutter_shadcn/markdown_viewer.dart';
import 'package:meshagent_flutter_shadcn/storage/file_browser.dart';
import 'package:meshagent_flutter_shadcn/thread_typography.dart';
import 'package:meshagent_flutter_shadcn/ui/coordinated_context_menu.dart';
import 'package:meshagent_flutter_shadcn/ui/ui.dart';
import 'package:meshagent_flutter_shadcn/src/web_context_menu_manager/enable_web_context_menu.dart';
import 'package:meshagent_flutter_shadcn/chat/thread_attachment_share.dart';
import 'package:meshagent_flutter_shadcn/chat/tool_call_status_accumulator.dart';
import 'package:mime/mime.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/monokai-sublime.dart';
import 'package:record/record.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:super_native_extensions/raw_clipboard.dart' as raw;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:meshagent_flutter_shadcn/file_preview/file_preview.dart';
import 'package:meshagent_flutter_shadcn/file_preview/image.dart';

import 'ansi.dart';
import 'outbound_delivery_status.dart';
import 'folder_drop.dart';
import 'usage_footer_tooltip.dart';

const webPDFFormat = SimpleFileFormat(uniformTypeIdentifiers: ['com.adobe.pdf'], mimeTypes: ['web application/pdf']);
const List<String> _emojiFontFamilyFallback = <String>['Apple Color Emoji', 'Segoe UI Emoji', 'Noto Color Emoji'];
const double _chatBubbleContentHorizontalPadding = 16;
const double _chatBubbleContentTopPadding = 4;
const double _chatBubbleContentBottomPadding = 2;
const double _mobileReactionFlowDialogMaxWidth = 420;
const double _mobileReactionFlowDialogViewportTopGap = 20;
const double _mobileReactionFlowDialogMaxHeightFactor = 0.72;
const double _mobileReactionFlowDialogCornerRadius = 28;
const double _mobileReactionFlowDialogTopPadding = 30;
const double _mobileReactionFlowDialogBottomPadding = 28;
const double _mobileStorageSaveFlowDialogMaxWidth = 420;
const double _mobileStorageSaveFlowDialogViewportTopGap = 20;

@visibleForTesting
String deduplicateRepeatedChatBubbleText(String text) {
  final trimmed = text.trim();
  if (trimmed.length < 40) {
    return text;
  }

  final starts = <String>[
    'The web service has been successfully installed in this room.',
    'The webserver service has been successfully installed in this room.',
    'The webserver service is already installed in this room.',
    'Installed the webserver service in this room.',
    'I set up the webserver service for this room so we can publish the website here.',
    'Created the ',
    "Here's the link to your webserver:",
    "Here\u2019s the link to your webserver:",
    'The new webserver URL is:',
  ];
  for (final start in starts) {
    final first = trimmed.indexOf(start);
    if (first == -1) {
      continue;
    }
    final second = trimmed.indexOf(start, first + start.length);
    if (second == -1) {
      continue;
    }
    final leading = trimmed.substring(0, second).trim();
    final repeated = trimmed.substring(second).trim();
    if (leading == repeated) {
      return leading;
    }
  }

  return text;
}

@visibleForTesting
String suppressAgentOnlyChatContext(String text) {
  const marker = '\n\nAdditional context:\n';
  final markerIndex = text.indexOf(marker);
  if (markerIndex == -1) {
    return text;
  }

  final visibleText = text.substring(0, markerIndex).trimRight();
  return visibleText.isEmpty ? text : visibleText;
}

String _visibleChatBubbleText(BuildContext context, String text) {
  var visibleText = text;
  if (ThreadTypographyOverride.suppressAgentOnlyChatContextOf(context)) {
    visibleText = suppressAgentOnlyChatContext(visibleText);
  }
  if (ThreadTypographyOverride.suppressRepeatedChatBubbleTextOf(context)) {
    visibleText = deduplicateRepeatedChatBubbleText(visibleText);
  }
  return visibleText;
}

const int _audioInputSampleRate = 24000;
const int _audioInputChannels = 1;
const Duration _audioInputFlushInterval = Duration(milliseconds: 250);
const int _audioInputFlushBytes = _audioInputSampleRate * _audioInputChannels * 2 ~/ 4;
const int _minimumRealtimeAudioBytes = _audioInputSampleRate * _audioInputChannels * 2 ~/ 10;
const double _audioInputSilenceLevelThreshold = 0.004;
const double _audioWaveformBarWidth = 2;
const double _audioWaveformBarGap = 2;
const int _audioWaveformMinBars = 16;
const EdgeInsets _chatBubbleContentPadding = EdgeInsets.only(
  left: _chatBubbleContentHorizontalPadding,
  right: _chatBubbleContentHorizontalPadding,
  top: _chatBubbleContentTopPadding,
  bottom: _chatBubbleContentBottomPadding,
);

EdgeInsets _resolvedChatBubbleContentPadding(BuildContext context) {
  return ThreadTypographyOverride.maybeBubbleContentPaddingOf(context) ?? _chatBubbleContentPadding;
}

double _resolvedChatBubbleHorizontalPadding(BuildContext context) {
  return _resolvedChatBubbleContentPadding(context).left;
}

enum UploadStatus { initial, uploading, completed, failed }

const double _mobileScreenWidthMax = 600;
const double _mobileComposerPillCornerRadius = 999;
const double _mobileComposerCornerRadius = 18;

class ChatContextLayoutOverride extends InheritedWidget {
  const ChatContextLayoutOverride({super.key, required this.useMobileLayout, required super.child});

  final bool useMobileLayout;

  static bool? maybeUseMobileLayoutOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ChatContextLayoutOverride>()?.useMobileLayout;
  }

  @override
  bool updateShouldNotify(covariant ChatContextLayoutOverride oldWidget) {
    return useMobileLayout != oldWidget.useMobileLayout;
  }
}

bool _usesMobileContextLayout(BuildContext context) {
  final overriddenValue = ChatContextLayoutOverride.maybeUseMobileLayoutOf(context);
  if (overriddenValue != null) {
    return overriddenValue;
  }

  return MediaQuery.sizeOf(context).width < _mobileScreenWidthMax;
}

bool _usesNativeMobileReactionFlowDialog(BuildContext context) {
  if (kIsWeb || !_usesMobileContextLayout(context)) {
    return false;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    TargetPlatform.fuchsia || TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => false,
  };
}

String _defaultSuggestedFileNameFromPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return "file";
  }

  if (trimmed.startsWith("data:")) {
    final commaIndex = trimmed.indexOf(",");
    final header = commaIndex == -1 ? trimmed.substring(5) : trimmed.substring(5, commaIndex);
    final mimeType = header.split(";").first.trim().toLowerCase();
    final extension = extensionFromMime(mimeType);
    return extension == null || extension.isEmpty ? "attachment" : "attachment.$extension";
  }

  final slash = trimmed.lastIndexOf("/");
  if (slash < 0 || slash == trimmed.length - 1) {
    return trimmed.isEmpty ? "file" : trimmed;
  }

  return trimmed.substring(slash + 1);
}

String _applySuggestedFileExtension(String rawPath, {required String suggestedFileName}) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) {
    return suggestedFileName;
  }

  final lastSlash = trimmed.lastIndexOf("/");
  final fileName = lastSlash >= 0 ? trimmed.substring(lastSlash + 1) : trimmed;
  if (fileName.contains(".")) {
    return trimmed;
  }

  final suggestedDot = suggestedFileName.lastIndexOf(".");
  if (suggestedDot <= 0 || suggestedDot == suggestedFileName.length - 1) {
    return trimmed;
  }

  final extension = suggestedFileName.substring(suggestedDot);
  return "$trimmed$extension";
}

class ThreadStorageSaveSurfaceRequest {
  const ThreadStorageSaveSurfaceRequest({
    required this.room,
    required this.title,
    required this.suggestedFileName,
    required this.fileNameLabel,
    required this.loadContent,
  });

  final RoomClient room;
  final String title;
  final String suggestedFileName;
  final String fileNameLabel;
  final Future<FileContent> Function() loadContent;
}

typedef ThreadStorageSaveSurfacePresenter = Future<void> Function(BuildContext context, ThreadStorageSaveSurfaceRequest request);

String _normalizeEmojiPresentationKey(String value) {
  return value.replaceAll('\u{FE0F}', '').replaceAll('\u{FE0E}', '').replaceAll('\u{200D}', '').trim();
}

String _primaryEmojiFontFamily() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return 'Apple Color Emoji';
    case TargetPlatform.windows:
      return 'Segoe UI Emoji';
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
      return 'Noto Color Emoji';
  }
}

TextStyle _emojiTextStyle({double size = 14}) {
  return TextStyle(
    inherit: false,
    fontSize: size,
    height: 1,
    fontFamily: _primaryEmojiFontFamily(),
    fontFamilyFallback: _emojiFontFamilyFallback,
  );
}

List<Widget> _buildReactionOptionButtons({
  required BuildContext context,
  required List<String> reactionOptions,
  required String? selectedReaction,
  required ValueChanged<String> onSelected,
  required double buttonSize,
  required double emojiSize,
}) {
  final theme = ShadTheme.of(context);
  return <Widget>[
    for (final reaction in reactionOptions)
      Builder(
        builder: (context) {
          final selected =
              selectedReaction != null && _normalizeEmojiPresentationKey(selectedReaction) == _normalizeEmojiPresentationKey(reaction);
          return ShadButton.ghost(
            width: buttonSize,
            height: buttonSize,
            padding: EdgeInsets.zero,
            backgroundColor: selected ? theme.colorScheme.foreground.withValues(alpha: 0.16) : null,
            hoverBackgroundColor: selected
                ? theme.colorScheme.foreground.withValues(alpha: 0.24)
                : theme.colorScheme.muted.withValues(alpha: 0.55),
            onPressed: () => onSelected(reaction),
            child: Text(reaction, style: _emojiTextStyle(size: emojiSize)),
          );
        },
      ),
  ];
}

Future<void> _showReactionPickerSurface(
  BuildContext context, {
  required List<String> reactionOptions,
  required String? selectedReaction,
  required ValueChanged<String> onSelected,
}) async {
  if (_usesNativeMobileReactionFlowDialog(context)) {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (dialogContext) =>
          _ReactionPickerFlowDialog(reactionOptions: reactionOptions, selectedReaction: selectedReaction, onSelected: onSelected),
    );
    return;
  }

  await showShadDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _ReactionPickerDesktopDialog(reactionOptions: reactionOptions, selectedReaction: selectedReaction, onSelected: onSelected),
  );
}

Future<bool> _showStorageOverwriteConfirmation(BuildContext context, {required String title, required String message}) async {
  final overwrite = await showShadDialog<bool>(
    context: context,
    builder: (dialogContext) => ShadDialog(
      title: Text(title),
      description: Text(message),
      actions: [
        ShadButton.secondary(
          onPressed: () {
            Navigator.of(dialogContext).pop(false);
          },
          child: const Text("Cancel"),
        ),
        ShadButton(
          onPressed: () {
            Navigator.of(dialogContext).pop(true);
          },
          child: const Text("Overwrite"),
        ),
      ],
    ),
  );

  return overwrite == true;
}

Future<void> _showThreadStorageSaveSurface(
  BuildContext context, {
  required RoomClient room,
  required String title,
  required String suggestedFileName,
  required String fileNameLabel,
  required Future<FileContent> Function() loadContent,
  ThreadStorageSaveSurfacePresenter? mobilePresenter,
}) async {
  if (mobilePresenter != null) {
    await mobilePresenter(
      context,
      ThreadStorageSaveSurfaceRequest(
        room: room,
        title: title,
        suggestedFileName: suggestedFileName,
        fileNameLabel: fileNameLabel,
        loadContent: loadContent,
      ),
    );
    return;
  }

  if (_usesNativeMobileReactionFlowDialog(context)) {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (dialogContext) => _ThreadStorageSaveFlowDialog(
        room: room,
        title: title,
        suggestedFileName: suggestedFileName,
        fileNameLabel: fileNameLabel,
        loadContent: loadContent,
      ),
    );
    return;
  }

  await showShadDialog<void>(
    context: context,
    builder: (dialogContext) => _ThreadStorageSaveDesktopDialog(
      room: room,
      title: title,
      suggestedFileName: suggestedFileName,
      fileNameLabel: fileNameLabel,
      loadContent: loadContent,
    ),
  );
}

List<String> _parseEventDetailLines(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return const [];
  }

  if (value.startsWith("[") && value.endsWith("]")) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.whereType<String>().map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
      }
    } catch (_) {}
  }

  return value.split(RegExp(r"\r?\n")).map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
}

const Set<String> _toolCallItemTypes = {"tool_call", "function_call", "mcp_call", "shell_call", "local_shell_call"};

bool _isToolOrShellCallEvent(MeshElement message) {
  final kind = ((message.getAttribute("kind") as String?) ?? "").trim().toLowerCase();
  if (message.tagName == "exec" || kind == "exec") {
    return true;
  }

  if (message.tagName != "event") {
    return false;
  }

  final itemType = ((message.getAttribute("item_type") as String?) ?? "").trim().toLowerCase();
  if (kind == "tool" || _toolCallItemTypes.contains(itemType)) {
    return true;
  }

  final method = (message.getAttribute("method") as String?) ?? "agent/event";
  final summary = ((message.getAttribute("summary") as String?) ?? method).trim();
  final headlineAttr = ((message.getAttribute("headline") as String?) ?? "").trim();
  final detailLines = _parseEventDetailLines(((message.getAttribute("details") as String?) ?? "").trim());
  final resolvedHeadlineForFiltering = (headlineAttr.isNotEmpty ? headlineAttr : summary).trim().toLowerCase();

  return (resolvedHeadlineForFiltering == "called tool" ||
          resolvedHeadlineForFiltering.startsWith("called tool:") ||
          resolvedHeadlineForFiltering == "calling tool" ||
          resolvedHeadlineForFiltering.startsWith("calling tool:")) &&
      detailLines.isNotEmpty &&
      detailLines.every((line) => line.trimLeft().toLowerCase().startsWith("tool:"));
}

bool _shouldHideToolOrShellCallEvent(MeshElement message, {required bool showCompletedToolCalls}) {
  return !showCompletedToolCalls && _isToolOrShellCallEvent(message);
}

const Set<String> _supportedThreadEventKinds = {
  "exec",
  "tool",
  "web",
  "search",
  "diff",
  "image",
  "approval",
  "collab",
  "plan",
  "thread",
  "file",
};

bool _isThreadAttachmentElement(MeshElement element) {
  return element.tagName == "file" || element.tagName == "image";
}

bool _hasRenderableStandardThreadMessageContent(MeshElement message) {
  if (message.tagName != "message") {
    return true;
  }

  final text = message.getAttribute("text");
  final trimmedText = text is String ? text.trim() : "";
  if (trimmedText.isNotEmpty) {
    return true;
  }

  return message.getChildren().whereType<MeshElement>().any(_isThreadAttachmentElement);
}

bool _hasCompleteStandardThreadMessageIdentity(MeshElement message) {
  if (message.tagName != "message") {
    return true;
  }

  final authorName = message.getAttribute("author_name");
  final role = message.getAttribute("role");
  return authorName is String && authorName.trim().isNotEmpty && role is String && role.trim().isNotEmpty;
}

bool _threadMessageHasId(MeshElement message, String id) {
  final normalizedId = id.trim();
  if (normalizedId.isEmpty) {
    return false;
  }
  final attributeId = message.getAttribute("id");
  if (attributeId is String && attributeId.trim() == normalizedId) {
    return true;
  }

  final elementId = message.id;
  if (elementId != null && elementId.trim() == normalizedId) {
    return true;
  }

  return false;
}

AgentMessage? _agentMessageFromRoomPayload(Object? message) {
  final rawPayload = message is Map && message["type"] is String ? message : (message is Map ? message["payload"] : null);
  if (rawPayload is! Map) {
    return null;
  }
  try {
    return AgentMessage.fromJson(Map<String, dynamic>.from(rawPayload));
  } catch (_) {
    return _legacyAgentStatusMessageFromPayload(Map<String, dynamic>.from(rawPayload));
  }
}

AgentMessage? _legacyAgentStatusMessageFromPayload(Map<String, dynamic> payload) {
  final type = payload["type"];
  if (type is! String) {
    return null;
  }
  final hydrated = Map<String, dynamic>.from(payload);
  switch (type) {
    case agentToolCallArgumentsDeltaType:
      hydrated.putIfAbsent("turn_id", () => "");
      break;
    case agentToolCallPendingType:
    case agentToolCallInProgressType:
    case agentToolCallStartedType:
      hydrated.putIfAbsent("turn_id", () => "");
      hydrated.putIfAbsent("toolkit", () => "");
      hydrated.putIfAbsent("tool", () => "");
      break;
    case agentToolCallEndedType:
      hydrated.putIfAbsent("turn_id", () => "");
      break;
    default:
      return null;
  }
  try {
    return AgentMessage.fromJson(hydrated);
  } catch (_) {
    return null;
  }
}

bool _pendingAgentMessageIsOptimisticallyRendered({required PendingAgentMessage pending, required Iterable<MeshElement> messages}) {
  if (pending.messageType == agentTurnSteerType || pending.matchByContentOnly) {
    return false;
  }
  return pending.awaitingApplication || !messages.any((message) => _threadMessageHasId(message, pending.messageId));
}

List<String> _threadAttachmentPaths(MeshElement message) {
  return message
      .getChildren()
      .whereType<MeshElement>()
      .where(_isThreadAttachmentElement)
      .map((attachment) => attachment.getAttribute("path"))
      .whereType<String>()
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
}

bool _threadMessageContentMatchesPendingAgentMessage(MeshElement message, PendingAgentMessage pending) {
  final pendingText = pending.text.trim();
  final text = message.getAttribute("text");
  if (pendingText.isNotEmpty && (text is! String || text.trim() != pendingText)) {
    return false;
  }

  final pendingAttachments = pending.attachments
      .map((attachment) => attachment.url.trim())
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
  if (pendingAttachments.isEmpty) {
    return true;
  }

  return const ListEquality<String>().equals(_threadAttachmentPaths(message), pendingAttachments);
}

bool _threadMessageMatchesPendingAgentMessage(MeshElement message, PendingAgentMessage pending) {
  if (message.tagName != "message") {
    return false;
  }

  if (!_hasCompleteStandardThreadMessageIdentity(message)) {
    return false;
  }

  if (_threadMessageHasId(message, pending.messageId)) {
    return _threadMessageContentMatchesPendingAgentMessage(message, pending);
  }

  if (!pending.matchByContentOnly) {
    return false;
  }

  final role = message.getAttribute("role");
  if (role is String && role.trim().toLowerCase() == "agent") {
    return false;
  }

  return _threadMessageContentMatchesPendingAgentMessage(message, pending);
}

bool _shouldRenderThreadMessageElement(MeshElement message, {required bool showCompletedToolCalls}) {
  if (_shouldHideToolOrShellCallEvent(message, showCompletedToolCalls: showCompletedToolCalls)) {
    return false;
  }

  if (message.tagName == "reasoning") {
    final summary = (message.getAttribute("summary") ?? "").toString().trim();
    return summary.isNotEmpty;
  }

  if (message.tagName == "message") {
    return _hasCompleteStandardThreadMessageIdentity(message) && _hasRenderableStandardThreadMessageContent(message);
  }

  if (message.tagName != "event") {
    return true;
  }

  final kind = ((message.getAttribute("kind") as String?) ?? "").trim().toLowerCase();
  if (!_supportedThreadEventKinds.contains(kind)) {
    return false;
  }
  return true;
}

class _ImageMime {
  static String normalize(String mimeType) {
    return mimeType.trim().toLowerCase();
  }

  static bool isSvg(String mimeType) {
    switch (normalize(mimeType)) {
      case "image/svg+xml":
      case "image/svg":
      case "public.svg-image":
        return true;
      default:
        return false;
    }
  }

  static String defaultExtension(String mimeType) {
    switch (normalize(mimeType)) {
      case "image/jpeg":
      case "image/jpg":
        return "jpg";
      case "image/gif":
        return "gif";
      case "image/webp":
        return "webp";
      case "image/svg+xml":
      case "image/svg":
      case "public.svg-image":
        return "svg";
      case "image/tiff":
      case "image/tif":
        return "tiff";
      case "image/bmp":
        return "bmp";
      case "image/heic":
        return "heic";
      case "image/heif":
        return "heif";
      case "image/x-icon":
      case "image/vnd.microsoft.icon":
        return "ico";
      case "image/png":
      default:
        return "png";
    }
  }

  static String suggestedFileName(String mimeType) {
    return "image.${defaultExtension(mimeType)}";
  }

  static FileFormat? clipboardFormat(String mimeType) {
    switch (normalize(mimeType)) {
      case "image/jpeg":
      case "image/jpg":
        return Formats.jpeg;
      case "image/gif":
        return Formats.gif;
      case "image/webp":
        return Formats.webp;
      case "image/svg+xml":
      case "image/svg":
      case "public.svg-image":
        return Formats.svg;
      case "image/tiff":
      case "image/tif":
        return Formats.tiff;
      case "image/bmp":
        return Formats.bmp;
      case "image/heic":
        return Formats.heic;
      case "image/heif":
        return Formats.heif;
      case "image/x-icon":
      case "image/vnd.microsoft.icon":
        return Formats.ico;
      case "image/png":
        return Formats.png;
      default:
        return null;
    }
  }
}

bool _supportsAgentMessages(Participant participant) {
  if (participant is! RemoteParticipant) {
    return false;
  }

  return participant.getAttribute("supports_agent_messages") == true;
}

bool _supportsMcp(Participant participant) {
  if (participant is! RemoteParticipant) {
    return false;
  }

  return participant.getAttribute("supports_mcp") == true;
}

String _displayParticipantName(BuildContext context, String name) {
  final baseName = name.split("@").first.trim();
  if (baseName.isEmpty || !ThreadTypographyOverride.normalizeParticipantDisplayNameOf(context)) {
    return baseName;
  }

  final buffer = StringBuffer();
  var capitalizeNext = true;
  for (final char in baseName.characters) {
    final isLetter = RegExp(r'[A-Za-z]').hasMatch(char);
    if (capitalizeNext && isLetter) {
      buffer.write(char.toUpperCase());
      capitalizeNext = false;
      continue;
    }

    buffer.write(char);
    capitalizeNext = char == '.' || char == ' ' || char == '_' || char == '-';
  }

  return buffer.toString();
}

String? _normalizeAgentAttachmentUrl(String path) {
  final trimmedPath = path.trim();
  if (trimmedPath.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(trimmedPath);
  if (uri != null && uri.scheme.isNotEmpty) {
    return trimmedPath;
  }

  final roomPath = trimmedPath.startsWith("/") ? trimmedPath.substring(1) : trimmedPath;
  if (roomPath.isEmpty) {
    return null;
  }

  return "room:///$roomPath";
}

String _connectorSelectionKey(Connector connector) {
  return jsonEncode({
    "name": connector.name,
    "server": connector.server.toJson(),
    if (connector.oauth != null) "oauth": connector.oauth!.toJson(),
  });
}

List<AgentInputContent> _agentInputContentFromMessage(ChatMessage message) {
  final content = <AgentInputContent>[];
  if (message.text.trim().isNotEmpty) {
    content.add(AgentTextContent(text: message.text));
  }

  for (final attachment in message.attachments) {
    final normalizedUrl = _normalizeAgentAttachmentUrl(attachment);
    if (normalizedUrl == null) {
      continue;
    }
    content.add(AgentFileContent(url: normalizedUrl));
  }

  return content;
}

class AgentToolChoice {
  const AgentToolChoice({required this.toolkitName, required this.toolName});

  final String toolkitName;
  final String toolName;

  Map<String, dynamic> toJson() {
    return {"toolkit_name": toolkitName, "tool_name": toolName};
  }
}

class PendingAgentMessage {
  const PendingAgentMessage({
    required this.messageId,
    required this.messageType,
    required this.threadPath,
    required this.text,
    required this.attachments,
    this.senderName,
    this.createdAt,
    this.matchByContentOnly = false,
    this.awaitingAcceptance = false,
    this.awaitingApplication = false,
    this.awaitingOnline = false,
  });

  final String messageId;
  final String messageType;
  final String threadPath;
  final String text;
  final List<AgentFileContent> attachments;
  final String? senderName;
  final DateTime? createdAt;
  final bool matchByContentOnly;
  final bool awaitingAcceptance;
  final bool awaitingApplication;
  final bool awaitingOnline;

  bool get hasVisibleContent => text.trim().isNotEmpty || attachments.isNotEmpty;

  static ({String text, List<AgentFileContent> attachments}) _parseContent(Object? content) {
    final textParts = <String>[];
    final attachments = <AgentFileContent>[];
    if (content is List) {
      for (final item in content) {
        if (item is! Map) {
          continue;
        }
        final type = item["type"];
        if (type == "text") {
          final text = item["text"];
          if (text is String && text.trim().isNotEmpty) {
            textParts.add(text);
          }
        } else if (type == "file") {
          final url = item["url"];
          if (url is String && url.trim().isNotEmpty) {
            final name = item["name"];
            attachments.add(AgentFileContent(url: url.trim(), name: name is String && name.trim().isNotEmpty ? name.trim() : null));
          }
        }
      }
    }
    return (text: textParts.join("\n\n"), attachments: attachments);
  }

  static ({String text, List<AgentFileContent> attachments}) _parseAgentContent(List<AgentInputContent> content) {
    return _parseContent(content.map((item) => item.toJson()).toList());
  }

  factory PendingAgentMessage.fromQueueJson(Map<String, dynamic> json) {
    final parsedContent = _parseContent(json["content"]);
    final senderName = json["sender_name"];
    final messageType = json["message_type"];
    final messageId = json["message_id"];
    final threadPath = json["thread_id"];
    final createdAt = json["created_at"];
    return PendingAgentMessage(
      messageId: messageId is String ? messageId : const Uuid().v4(),
      messageType: messageType is String ? messageType : agentTurnSteerType,
      threadPath: threadPath is String ? threadPath : "",
      text: parsedContent.text,
      attachments: parsedContent.attachments,
      senderName: senderName is String && senderName.trim().isNotEmpty ? senderName.trim() : null,
      createdAt: createdAt is String ? DateTime.tryParse(createdAt) : null,
      matchByContentOnly: false,
      awaitingApplication: true,
      awaitingOnline: false,
    );
  }

  factory PendingAgentMessage.fromAcceptedMessage(TurnStartAccepted message) {
    final parsedContent = _parseAgentContent(message.content);
    return PendingAgentMessage(
      messageId: message.sourceMessageId.trim().isNotEmpty ? message.sourceMessageId.trim() : const Uuid().v4(),
      messageType: message is TurnSteerAccepted ? agentTurnSteerType : agentTurnStartType,
      threadPath: message.threadId,
      text: parsedContent.text,
      attachments: parsedContent.attachments,
      senderName: message.senderName?.trim().isNotEmpty == true ? message.senderName!.trim() : null,
      matchByContentOnly: false,
      awaitingAcceptance: false,
      awaitingApplication: true,
      awaitingOnline: false,
    );
  }

  factory PendingAgentMessage.fromTurnInputMessage(AgentThreadMessage message) {
    final content = switch (message) {
      TurnStart() => message.content,
      TurnSteer() => message.content,
      _ => const <AgentInputContent>[],
    };
    final parsedContent = _parseAgentContent(content);
    return PendingAgentMessage(
      messageId: message.messageId.trim().isNotEmpty ? message.messageId.trim() : const Uuid().v4(),
      messageType: message.type,
      threadPath: message.threadId,
      text: parsedContent.text,
      attachments: parsedContent.attachments,
      senderName: message.senderName?.trim().isNotEmpty == true ? message.senderName!.trim() : null,
      createdAt: message.createdAtUtc,
      matchByContentOnly: false,
      awaitingAcceptance: true,
      awaitingApplication: true,
      awaitingOnline: false,
    );
  }
}

class ChatSendCancelledException implements Exception {
  const ChatSendCancelledException();

  @override
  String toString() => "send cancelled";
}

class _PendingSendWait {
  _PendingSendWait({required this.messageId, required this.threadPath});

  final String messageId;
  final String threadPath;
  final Completer<void> cancelled = Completer<void>();
  VoidCallback? detach;

  void cancel() {
    if (!cancelled.isCompleted) {
      cancelled.complete();
    }
    detach?.call();
  }
}

final Expando<AgentThreadMessageStatusStore> _agentThreadMessageStatusStores = Expando<AgentThreadMessageStatusStore>();

AgentThreadMessageStatusStore _agentThreadMessageStatusStore(RoomClient room) {
  final existing = _agentThreadMessageStatusStores[room];
  if (existing != null) {
    return existing;
  }

  final created = AgentThreadMessageStatusStore();
  _agentThreadMessageStatusStores[room] = created;
  return created;
}

bool trackAgentThreadStatusMessage({required RoomClient room, required AgentMessage message}) {
  return _agentThreadMessageStatusStore(room).apply(message);
}

bool trackAgentThreadStatusMessageInStore({required AgentThreadMessageStatusStore store, required AgentMessage message, String? path}) {
  return store.apply(message, path: path);
}

bool trackAgentThreadStatusPayload({required RoomClient room, required Map<String, dynamic> payload}) {
  final message = _agentMessageFromRoomPayload(payload);
  return message != null && trackAgentThreadStatusMessage(room: room, message: message);
}

int? _positiveIntValue(Object? value) {
  final parsed = switch (value) {
    int() => value,
    BigInt() => value.toInt(),
    num() when value.isFinite => value.toInt(),
    _ => int.tryParse(value?.toString() ?? ""),
  };
  return parsed != null && parsed > 0 ? parsed : null;
}

int? _nonNegativeIntValue(Object? value) {
  final parsed = switch (value) {
    int() => value,
    BigInt() => value.toInt(),
    num() when value.isFinite => value.toInt(),
    _ => int.tryParse(value?.toString() ?? ""),
  };
  return parsed != null && parsed >= 0 ? parsed : null;
}

class _AgentThreadMessageStatus {
  const _AgentThreadMessageStatus({
    this.text,
    this.startedAt,
    this.mode,
    this.turnId,
    this.pendingItemId,
    this.totalBytes,
    this.totalBytesFromStatus = false,
    this.linesAdded,
    this.linesRemoved,
  });

  final String? text;
  final DateTime? startedAt;
  final String? mode;
  final String? turnId;
  final String? pendingItemId;
  final int? totalBytes;
  final bool totalBytesFromStatus;
  final int? linesAdded;
  final int? linesRemoved;
}

class AgentThreadMessageStatusStore {
  static const Duration _maxRemoteStatusClockSkew = Duration(minutes: 2);

  final Set<String> _touchedThreadPaths = <String>{};
  final Map<String, _AgentThreadMessageStatus> _statusByThreadPath = <String, _AgentThreadMessageStatus>{};
  final Map<String, LinkedHashMap<String, PendingAgentMessage>> _pendingMessagesByThreadPath =
      <String, LinkedHashMap<String, PendingAgentMessage>>{};
  final Map<String, LiveToolCallAccumulator> _toolCallAccumulatorsByThreadPath = <String, LiveToolCallAccumulator>{};

  bool apply(AgentMessage message, {String? path}) {
    if (message is! AgentThreadMessage || message.threadId.trim().isEmpty) {
      return false;
    }
    final normalizedThreadPath = message.threadId.trim();

    switch (message.type) {
      case agentThreadStatusType:
        _touchedThreadPaths.add(normalizedThreadPath);
        return message is AgentThreadStatus && _applyStatus(normalizedThreadPath, message);
      case agentTurnStartType:
      case agentTurnSteerType:
        _touchedThreadPaths.add(normalizedThreadPath);
        return _applyTurnInput(normalizedThreadPath, message);
      case agentTurnStartAcceptedType:
      case agentTurnSteerAcceptedType:
        _touchedThreadPaths.add(normalizedThreadPath);
        return message is TurnStartAccepted && _applyAccepted(normalizedThreadPath, message);
      case agentTurnStartedType:
        _touchedThreadPaths.add(normalizedThreadPath);
        return message is TurnStarted && _markPendingApplied(normalizedThreadPath, message.sourceMessageId, turnId: message.turnId);
      case agentTurnSteeredType:
        _touchedThreadPaths.add(normalizedThreadPath);
        return message is TurnSteered && _markPendingApplied(normalizedThreadPath, message.sourceMessageId);
      case agentToolCallArgumentsDeltaType:
        _touchedThreadPaths.add(normalizedThreadPath);
        return message is AgentToolCallArgumentsDelta && _applyToolCallArgumentsDelta(normalizedThreadPath, message);
      case agentToolCallPendingType:
      case agentToolCallInProgressType:
      case agentToolCallStartedType:
        _touchedThreadPaths.add(normalizedThreadPath);
        return message is AgentToolCallPending && _applyToolCallLifecycle(normalizedThreadPath, message);
      case agentToolCallEndedType:
        _touchedThreadPaths.add(normalizedThreadPath);
        return message is AgentToolCallEnded && _clearToolCallBytes(normalizedThreadPath, message);
      case agentTurnStartRejectedType:
      case agentTurnSteerRejectedType:
        _touchedThreadPaths.add(normalizedThreadPath);
        final sourceMessageId = switch (message) {
          TurnStartRejected() => message.sourceMessageId,
          TurnSteerRejected() => message.sourceMessageId,
          _ => null,
        };
        return sourceMessageId != null && _removePending(normalizedThreadPath, sourceMessageId);
      case agentTurnEndedType:
      case agentThreadClearedType:
        _touchedThreadPaths.add(normalizedThreadPath);
        final hadPending = _pendingMessagesByThreadPath.remove(normalizedThreadPath)?.isNotEmpty == true;
        final hadStatus = _statusByThreadPath.remove(normalizedThreadPath) != null;
        final hadTools = _toolCallAccumulatorsByThreadPath.remove(normalizedThreadPath)?.isEmpty == false;
        return hadPending || hadStatus || hadTools;
    }

    return false;
  }

  bool hasThread(String path) => _touchedThreadPaths.contains(path.trim());

  void clearThread(String path) {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return;
    }
    _touchedThreadPaths.remove(normalizedPath);
    _statusByThreadPath.remove(normalizedPath);
    _pendingMessagesByThreadPath.remove(normalizedPath);
    _toolCallAccumulatorsByThreadPath.remove(normalizedPath);
  }

  ChatThreadStatusState state({required String path, ChatThreadStatusState? previous, required bool supportsAgentMessages}) {
    final normalizedPath = path.trim();
    final status = _statusByThreadPath[normalizedPath];
    final pendingMessages = List<PendingAgentMessage>.unmodifiable(
      _pendingMessagesByThreadPath[normalizedPath]?.values ?? const <PendingAgentMessage>[],
    );

    if (status == null && pendingMessages.isEmpty) {
      return ChatThreadStatusState(supportsAgentMessages: supportsAgentMessages);
    }

    var startedAt = status?.startedAt;
    if (status?.text != null) startedAt ??= DateTime.now();

    return ChatThreadStatusState(
      text: status?.text,
      startedAt: startedAt,
      mode: status?.text == null ? status?.mode : status?.mode ?? "busy",
      turnId: status?.turnId,
      pendingMessages: pendingMessages,
      pendingItemId: status?.pendingItemId,
      totalBytes: status?.totalBytes,
      linesAdded: status?.linesAdded,
      linesRemoved: status?.linesRemoved,
      supportsAgentMessages: true,
    );
  }

  bool _applyStatus(String threadPath, AgentThreadStatus message) {
    final rawStatus = message.status;
    final rawMode = message.mode;
    final rawStartedAt = message.startedAt;
    final rawTurnId = message.turnId;
    final rawPendingItemId = message.pendingItemId;
    final rawTotalBytes = message.totalBytes;
    final rawLinesAdded = message.linesAdded;
    final rawLinesRemoved = message.linesRemoved;
    final previous = _statusByThreadPath[threadPath];

    final text = rawStatus is String && rawStatus.trim().isNotEmpty ? rawStatus.trim() : null;
    final mode = rawMode is String && (rawMode.trim().toLowerCase() == "busy" || rawMode.trim().toLowerCase() == "steerable")
        ? rawMode.trim().toLowerCase()
        : null;
    final parsedStartedAt = rawStartedAt is String && rawStartedAt.trim().isNotEmpty ? DateTime.tryParse(rawStartedAt.trim()) : null;
    final turnId = rawTurnId is String && rawTurnId.trim().isNotEmpty ? rawTurnId.trim() : null;
    final pendingItemId = rawPendingItemId is String && rawPendingItemId.trim().isNotEmpty ? rawPendingItemId.trim() : null;
    final sameStatusOperation =
        previous != null && previous.text == text && previous.turnId == turnId && previous.pendingItemId == pendingItemId;
    final startedAt = text == null
        ? null
        : _statusStartedAt(parsedStartedAt: parsedStartedAt, previousStartedAt: sameStatusOperation ? previous.startedAt : null);
    final parsedTotalBytes = _positiveIntValue(rawTotalBytes);
    final linesAdded =
        _nonNegativeIntValue(rawLinesAdded) ?? (rawLinesAdded == null && previous?.text == text ? previous?.linesAdded : null);
    final linesRemoved =
        _nonNegativeIntValue(rawLinesRemoved) ?? (rawLinesRemoved == null && previous?.text == text ? previous?.linesRemoved : null);
    final totalBytes =
        parsedTotalBytes ??
        _toolArgumentBytes(threadPath, pendingItemId) ??
        (rawTotalBytes == null && previous?.text == text ? previous?.totalBytes : null);
    final totalBytesFromStatus = parsedTotalBytes != null;

    if (text == null &&
        mode == null &&
        startedAt == null &&
        turnId == null &&
        pendingItemId == null &&
        totalBytes == null &&
        linesAdded == null &&
        linesRemoved == null) {
      _statusByThreadPath.remove(threadPath);
      return true;
    }

    final next = _AgentThreadMessageStatus(
      text: text,
      startedAt: startedAt,
      mode: mode,
      turnId: turnId,
      pendingItemId: pendingItemId,
      totalBytes: totalBytes,
      totalBytesFromStatus: totalBytesFromStatus,
      linesAdded: linesAdded,
      linesRemoved: linesRemoved,
    );
    if (previous != null &&
        previous.text == next.text &&
        previous.mode == next.mode &&
        previous.turnId == next.turnId &&
        previous.pendingItemId == next.pendingItemId &&
        previous.totalBytes == next.totalBytes &&
        previous.totalBytesFromStatus == next.totalBytesFromStatus &&
        previous.linesAdded == next.linesAdded &&
        previous.linesRemoved == next.linesRemoved &&
        previous.startedAt?.millisecondsSinceEpoch == next.startedAt?.millisecondsSinceEpoch) {
      return false;
    }

    _statusByThreadPath[threadPath] = next;
    return true;
  }

  DateTime _statusStartedAt({required DateTime? parsedStartedAt, required DateTime? previousStartedAt}) {
    if (previousStartedAt != null) {
      return previousStartedAt;
    }
    final now = DateTime.now();
    if (parsedStartedAt == null) {
      return now;
    }
    final localStartedAt = parsedStartedAt.toLocal();
    final skew = now.difference(localStartedAt).abs();
    if (skew > _maxRemoteStatusClockSkew) {
      return now;
    }
    return localStartedAt;
  }

  bool _applyToolCallArgumentsDelta(String threadPath, AgentToolCallArgumentsDelta message) {
    final itemId = message.itemId;
    if (itemId.trim().isEmpty) {
      return false;
    }
    final normalizedItemId = itemId.trim();

    final delta = message.delta;
    final deltaBytes = utf8.encode(delta).length;
    if (deltaBytes <= 0) {
      return false;
    }

    final accumulator = _toolCallAccumulatorsByThreadPath.putIfAbsent(threadPath, () => LiveToolCallAccumulator());
    final status = _statusByThreadPath[threadPath];
    final snapshot = accumulator.appendDelta(itemId: normalizedItemId, delta: delta, fallbackText: status?.text);

    if (status == null || status.text == null || status.text!.trim().isEmpty) {
      return false;
    }

    final isStatusItem =
        status.pendingItemId == null || status.pendingItemId == normalizedItemId || accumulator.hasSingleItem(normalizedItemId);
    if (!isStatusItem) {
      return false;
    }
    final nextPendingItemId = status.pendingItemId == null || status.pendingItemId == normalizedItemId
        ? status.pendingItemId ?? normalizedItemId
        : normalizedItemId;

    final nextStatusText = snapshot.text ?? status.text;
    final nextTotalBytesForStatus = snapshot.totalBytes == null
        ? status.totalBytes
        : math.max(status.totalBytes ?? 0, snapshot.totalBytes!);
    if (status.text == nextStatusText &&
        status.totalBytes == nextTotalBytesForStatus &&
        status.linesAdded == (snapshot.linesAdded ?? status.linesAdded) &&
        status.linesRemoved == (snapshot.linesRemoved ?? status.linesRemoved)) {
      return false;
    }

    _statusByThreadPath[threadPath] = _AgentThreadMessageStatus(
      text: nextStatusText,
      startedAt: status.startedAt,
      mode: status.mode,
      turnId: status.turnId,
      pendingItemId: nextPendingItemId,
      totalBytes: nextTotalBytesForStatus,
      totalBytesFromStatus: false,
      linesAdded: snapshot.linesAdded ?? status.linesAdded,
      linesRemoved: snapshot.linesRemoved ?? status.linesRemoved,
    );
    return true;
  }

  bool _applyToolCallLifecycle(String threadPath, AgentToolCallPending message) {
    final itemId = message.itemId.trim().isNotEmpty ? message.itemId.trim() : null;
    if (itemId == null) {
      return false;
    }
    final accumulator = _toolCallAccumulatorsByThreadPath.putIfAbsent(threadPath, () => LiveToolCallAccumulator());
    final existing = accumulator[itemId];
    final tool = message.tool.trim().isNotEmpty ? message.tool.trim() : existing?.tool ?? "";
    final arguments = message.arguments ?? existing?.arguments;

    final status = _statusByThreadPath[threadPath];
    final snapshot = accumulator.upsert(itemId: itemId, tool: tool, arguments: arguments, fallbackText: status?.text);
    if (status == null || status.text == null || status.text!.trim().isEmpty) {
      return false;
    }
    final nextPendingItemId = status.pendingItemId == null || status.pendingItemId == itemId || accumulator.hasSingleItem(itemId)
        ? itemId
        : status.pendingItemId;
    final nextTotalBytesForStatus = snapshot.totalBytes == null
        ? status.totalBytes
        : math.max(status.totalBytes ?? 0, snapshot.totalBytes!);
    if (nextPendingItemId == status.pendingItemId &&
        snapshot.text == status.text &&
        snapshot.linesAdded == null &&
        snapshot.linesRemoved == null &&
        nextTotalBytesForStatus == status.totalBytes) {
      return false;
    }
    _statusByThreadPath[threadPath] = _AgentThreadMessageStatus(
      text: snapshot.text ?? status.text,
      startedAt: status.startedAt,
      mode: status.mode,
      turnId: status.turnId,
      pendingItemId: nextPendingItemId,
      totalBytes: nextTotalBytesForStatus,
      totalBytesFromStatus: false,
      linesAdded: snapshot.linesAdded ?? status.linesAdded,
      linesRemoved: snapshot.linesRemoved ?? status.linesRemoved,
    );
    return true;
  }

  int? _toolArgumentBytes(String threadPath, String? itemId) {
    if (itemId == null || itemId.trim().isEmpty) {
      return null;
    }
    final bytes = _toolCallAccumulatorsByThreadPath[threadPath]?.totalBytes(itemId.trim());
    return bytes != null && bytes > 0 ? bytes : null;
  }

  bool _clearToolCallBytes(String threadPath, AgentToolCallEnded message) {
    final itemId = message.itemId.trim().isNotEmpty ? message.itemId.trim() : null;
    var hadBytes = false;
    if (itemId != null) {
      final accumulator = _toolCallAccumulatorsByThreadPath[threadPath];
      hadBytes = accumulator?.remove(itemId) == true;
      if (accumulator != null && accumulator.isEmpty) {
        _toolCallAccumulatorsByThreadPath.remove(threadPath);
      }
    }

    final status = _statusByThreadPath[threadPath];
    if (status?.totalBytes == null || (itemId != null && status?.pendingItemId != itemId)) {
      return hadBytes;
    }
    _statusByThreadPath[threadPath] = _AgentThreadMessageStatus(
      text: status?.text,
      startedAt: status?.startedAt,
      mode: status?.mode,
      turnId: status?.turnId,
      pendingItemId: status?.pendingItemId,
    );
    return true;
  }

  bool _applyTurnInput(String threadPath, AgentThreadMessage message) {
    final parsedMessage = PendingAgentMessage.fromTurnInputMessage(message);
    if (parsedMessage.messageId.trim().isEmpty) {
      return false;
    }
    return _upsertPendingMessage(threadPath, parsedMessage);
  }

  bool _applyAccepted(String threadPath, TurnStartAccepted message) {
    final parsedMessage = PendingAgentMessage.fromAcceptedMessage(message);
    if (parsedMessage.messageId.trim().isEmpty) {
      return false;
    }
    final pendingMessages = _pendingMessagesByThreadPath.putIfAbsent(threadPath, LinkedHashMap<String, PendingAgentMessage>.new);
    final existing = pendingMessages[parsedMessage.messageId];
    if (existing == null && parsedMessage.text.trim().isEmpty && parsedMessage.attachments.isEmpty) {
      if (pendingMessages.isEmpty) {
        _pendingMessagesByThreadPath.remove(threadPath);
      }
      return false;
    }
    final nextMessage = existing == null
        ? parsedMessage
        : PendingAgentMessage(
            messageId: existing.messageId,
            messageType: existing.messageType,
            threadPath: existing.threadPath,
            text: existing.text,
            attachments: existing.attachments,
            senderName: existing.senderName,
            createdAt: existing.createdAt,
            matchByContentOnly: existing.matchByContentOnly,
            awaitingAcceptance: false,
            awaitingApplication: existing.awaitingApplication,
            awaitingOnline: existing.awaitingOnline,
          );
    return _upsertPendingMessage(threadPath, nextMessage);
  }

  bool _upsertPendingMessage(String threadPath, PendingAgentMessage message) {
    final pendingMessages = _pendingMessagesByThreadPath.putIfAbsent(threadPath, LinkedHashMap<String, PendingAgentMessage>.new);
    if (!message.hasVisibleContent) {
      final removed = pendingMessages.remove(message.messageId) != null;
      if (pendingMessages.isEmpty) {
        _pendingMessagesByThreadPath.remove(threadPath);
      }
      return removed;
    }
    final existing = pendingMessages[message.messageId];
    if (existing != null &&
        existing.messageType == message.messageType &&
        existing.text == message.text &&
        const DeepCollectionEquality().equals(
          existing.attachments.map((attachment) => attachment.toJson()).toList(growable: false),
          message.attachments.map((attachment) => attachment.toJson()).toList(growable: false),
        ) &&
        existing.senderName == message.senderName &&
        existing.awaitingAcceptance == message.awaitingAcceptance &&
        existing.awaitingApplication == message.awaitingApplication) {
      return false;
    }
    pendingMessages[message.messageId] = message;
    return true;
  }

  bool _markPendingApplied(String threadPath, Object? sourceMessageId, {Object? turnId}) {
    var changed = false;
    final pendingMessages = _pendingMessagesByThreadPath[threadPath];
    final normalizedSourceMessageId = sourceMessageId is String ? sourceMessageId.trim() : "";
    if (normalizedSourceMessageId.isNotEmpty) {
      final existing = pendingMessages?[normalizedSourceMessageId];
      if (existing != null && existing.awaitingApplication) {
        if (existing.messageType == agentTurnSteerType) {
          pendingMessages!.remove(normalizedSourceMessageId);
          if (pendingMessages.isEmpty) {
            _pendingMessagesByThreadPath.remove(threadPath);
          }
        } else {
          pendingMessages![normalizedSourceMessageId] = PendingAgentMessage(
            messageId: existing.messageId,
            messageType: existing.messageType,
            threadPath: existing.threadPath,
            text: existing.text,
            attachments: existing.attachments,
            senderName: existing.senderName,
            createdAt: existing.createdAt,
            matchByContentOnly: existing.matchByContentOnly,
            awaitingAcceptance: existing.awaitingAcceptance,
            awaitingApplication: false,
            awaitingOnline: existing.awaitingOnline,
          );
        }
        changed = true;
      }
    }

    if (turnId is String && turnId.trim().isNotEmpty) {
      final previous = _statusByThreadPath[threadPath];
      final normalizedTurnId = turnId.trim();
      if (previous?.turnId != normalizedTurnId) {
        final startedAt = previous?.text != null && previous?.turnId != null ? DateTime.now() : previous?.startedAt;
        _statusByThreadPath[threadPath] = _AgentThreadMessageStatus(
          text: previous?.text,
          startedAt: startedAt,
          mode: previous?.mode,
          turnId: normalizedTurnId,
          pendingItemId: previous?.pendingItemId,
          totalBytes: previous?.totalBytes,
          linesAdded: previous?.linesAdded,
          linesRemoved: previous?.linesRemoved,
        );
        changed = true;
      }
    }

    return changed;
  }

  bool _removePending(String threadPath, Object? sourceMessageId, {Object? turnId}) {
    final pendingMessages = _pendingMessagesByThreadPath[threadPath];
    final normalizedSourceMessageId = sourceMessageId is String ? sourceMessageId.trim() : "";
    final changed = normalizedSourceMessageId.isNotEmpty && pendingMessages?.remove(normalizedSourceMessageId) != null;
    if (pendingMessages != null && pendingMessages.isEmpty) {
      _pendingMessagesByThreadPath.remove(threadPath);
    }

    if (turnId is String && turnId.trim().isNotEmpty) {
      final previous = _statusByThreadPath[threadPath];
      final normalizedTurnId = turnId.trim();
      if (previous?.turnId != normalizedTurnId) {
        final startedAt = previous?.text != null && previous?.turnId != null ? DateTime.now() : previous?.startedAt;
        _statusByThreadPath[threadPath] = _AgentThreadMessageStatus(
          text: previous?.text,
          startedAt: startedAt,
          mode: previous?.mode,
          turnId: normalizedTurnId,
          pendingItemId: previous?.pendingItemId,
          totalBytes: previous?.totalBytes,
          linesAdded: previous?.linesAdded,
          linesRemoved: previous?.linesRemoved,
        );
        return true;
      }
    }

    return changed;
  }
}

class ChatThreadStatusState {
  const ChatThreadStatusState({
    this.text,
    this.startedAt,
    this.mode,
    this.turnId,
    this.pendingMessages = const [],
    this.pendingItemId,
    this.totalBytes,
    this.linesAdded,
    this.linesRemoved,
    this.supportsAgentMessages = false,
  });

  final String? text;
  final DateTime? startedAt;
  final String? mode;
  final String? turnId;
  final List<PendingAgentMessage> pendingMessages;
  final String? pendingItemId;
  final int? totalBytes;
  final int? linesAdded;
  final int? linesRemoved;
  final bool supportsAgentMessages;

  bool get hasStatus => text != null && text!.trim().isNotEmpty;
}

bool shouldShowChatThreadStatus(ChatThreadStatusState status) {
  return status.hasStatus;
}

ChatThreadStatusState resolveChatThreadStatus({
  required RoomClient room,
  required String path,
  String? agentName,
  ChatThreadStatusState? previous,
}) {
  final candidates = <Participant>[
    if (agentName != null)
      ...room.messaging.remoteParticipants.where((participant) => participant.getAttribute("name") == agentName)
    else
      ...room.messaging.remoteParticipants,
  ];
  final messageStatusStore = _agentThreadMessageStatusStore(room);
  return resolveChatThreadStatusFromStore(
    store: messageStatusStore,
    path: path,
    previous: previous,
    supportsAgentMessages: candidates.any(_supportsAgentMessages),
  );
}

ChatThreadStatusState resolveChatThreadStatusFromStore({
  required AgentThreadMessageStatusStore store,
  required String path,
  ChatThreadStatusState? previous,
  bool supportsAgentMessages = true,
}) {
  final hasMessageStatus = store.hasThread(path);
  final messageState = store.state(path: path, previous: previous, supportsAgentMessages: hasMessageStatus || supportsAgentMessages);

  String? nextStatus = messageState.text;
  String? nextMode = messageState.mode;
  DateTime? nextStartedAt = messageState.startedAt;
  String? nextTurnId = messageState.turnId;
  List<PendingAgentMessage> nextPendingMessages = messageState.pendingMessages;
  String? nextPendingItemId = messageState.pendingItemId;
  int? nextTotalBytes = messageState.totalBytes;
  int? nextLinesAdded = messageState.linesAdded;
  int? nextLinesRemoved = messageState.linesRemoved;
  bool nextSupportsAgentMessages = messageState.supportsAgentMessages;

  if (nextStatus != null) {
    nextMode ??= "busy";
    nextStartedAt ??= DateTime.now();
  }

  return ChatThreadStatusState(
    text: nextStatus,
    startedAt: nextStartedAt,
    mode: nextMode,
    turnId: nextTurnId,
    pendingMessages: nextPendingMessages,
    pendingItemId: nextPendingItemId,
    totalBytes: nextTotalBytes,
    linesAdded: nextLinesAdded,
    linesRemoved: nextLinesRemoved,
    supportsAgentMessages: nextSupportsAgentMessages,
  );
}

class ChatThreadStatusIndicator extends StatelessWidget {
  const ChatThreadStatusIndicator({
    super.key,
    required this.statusText,
    this.startedAt,
    this.totalBytes,
    this.linesAdded,
    this.linesRemoved,
    this.reserveSpace = false,
    this.size = 14,
    this.strokeWidth = 2,
  });

  final String? statusText;
  final DateTime? startedAt;
  final int? totalBytes;
  final int? linesAdded;
  final int? linesRemoved;
  final bool reserveSpace;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final normalizedStatusText = statusText?.trim() ?? "";
    final placeholder = SizedBox(width: size, height: size);
    if (normalizedStatusText.isEmpty) {
      return reserveSpace ? placeholder : const SizedBox.shrink();
    }

    return SizedBox(
      width: size,
      height: size,
      child: ShadTooltip(
        waitDuration: const Duration(milliseconds: 300),
        builder: (context) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            formatChatThreadStatusText(
              normalizedStatusText,
              startedAt: startedAt,
              totalBytes: totalBytes,
              linesAdded: linesAdded,
              linesRemoved: linesRemoved,
            ),
            style: ShadTheme.of(context).textTheme.small,
          ),
        ),
        child: _CyclingProgressIndicator(strokeWidth: strokeWidth),
      ),
    );
  }
}

class FileAttachment extends ChangeNotifier {
  FileAttachment({required this.path, this.mimeType, this.displayName, UploadStatus initialStatus = UploadStatus.initial})
    : _status = initialStatus;

  UploadStatus _status;

  UploadStatus get status => _status;

  @protected
  set status(UploadStatus value) {
    if (_status != value) {
      _status = value;
      notifyListeners();
    }
  }

  String path;
  final String? mimeType;
  final String? displayName;
  String get filename {
    final explicitName = displayName?.trim();
    if (explicitName != null && explicitName.isNotEmpty) {
      return explicitName;
    }

    return _defaultSuggestedFileNameFromPath(path);
  }
}

class MeshagentFileUpload extends FileAttachment {
  MeshagentFileUpload({required this.room, required super.path, required this.dataStream, this.size = 0, super.mimeType}) {
    _upload();
  }

  // Requires to manually call startUpload()
  MeshagentFileUpload.deferred({required this.room, required super.path, required this.dataStream, this.size = 0, super.mimeType});

  int size;

  final RoomClient room;

  final Stream<List<int>> dataStream;

  final _completer = Completer();

  int _bytesUploaded = 0;

  int get bytesUploaded => _bytesUploaded;

  Future get done => _completer.future;

  final _downloadUrlCompleter = Completer<Uri>();

  Future<Uri> get downloadUrl => _downloadUrlCompleter.future;

  void startUpload() {
    _upload();
  }

  void _upload() async {
    if (status != UploadStatus.initial) {
      throw StateError("upload already started or completed");
    }

    try {
      status = UploadStatus.uploading;
      notifyListeners();

      Stream<Uint8List> trackedStream() async* {
        await for (final item in dataStream) {
          final chunk = item is Uint8List ? item : Uint8List.fromList(item);
          yield chunk;
          _bytesUploaded += chunk.length;
          notifyListeners();
        }
      }

      await room.storage.uploadStream(path, trackedStream(), overwrite: true, size: size > 0 ? size : null, mimeType: mimeType);

      _completer.complete();

      status = UploadStatus.completed;
      notifyListeners();

      final url = await room.storage.downloadUrl(path);
      _downloadUrlCompleter.complete(Uri.parse(url));
    } catch (err) {
      status = UploadStatus.failed;
      notifyListeners();

      _completer.completeError(err);
      _downloadUrlCompleter.completeError(err);
    }
  }
}

class ChatThreadController extends ChangeNotifier {
  ChatThreadController({required this.room}) {
    textFieldController.addListener(notifyListeners);
  }

  final RoomClient? room;
  final TextEditingController textFieldController = ShadTextEditingController();
  final ScrollController threadScrollController = ScrollController();
  final List<FileAttachment> _attachmentUploads = [];
  final OutboundMessageStatusQueue outboundStatus = OutboundMessageStatusQueue();
  final LinkedHashMap<String, PendingAgentMessage> _pendingAgentMessages = LinkedHashMap<String, PendingAgentMessage>();
  final LinkedHashMap<String, _PendingSendWait> _pendingSendWaits = LinkedHashMap<String, _PendingSendWait>();
  final Set<String> _enabledToolkits = <String>{};
  final LinkedHashMap<String, Connector> _selectedMcpConnectors = LinkedHashMap<String, Connector>();
  final LinkedHashMap<String, Toolkit> _clientToolkits = LinkedHashMap<String, Toolkit>();
  final Map<String, ({ToolResponseSentListener listener, ToolContext context, Content response})> _pendingClientToolResponseCallbacks =
      <String, ({ToolResponseSentListener listener, ToolContext context, Content response})>{};

  RoomClient _requireRoom(String operation) {
    final room = this.room;
    if (room == null) {
      throw StateError('$operation requires a room.');
    }
    return room;
  }

  bool isToolkitEnabled(String toolkitName) {
    return _enabledToolkits.contains(toolkitName);
  }

  bool toggleToolkit(String toolkitName) {
    if (_enabledToolkits.contains(toolkitName)) {
      _enabledToolkits.remove(toolkitName);
      notifyListeners();
      return false;
    }

    _enabledToolkits.add(toolkitName);
    notifyListeners();
    return true;
  }

  List<Connector> get selectedMcpConnectors {
    return List<Connector>.unmodifiable(_selectedMcpConnectors.values);
  }

  bool isMcpConnectorSelected(Connector connector) {
    return _selectedMcpConnectors.containsKey(_connectorSelectionKey(connector));
  }

  void setMcpConnectorSelected(Connector connector, bool selected) {
    final key = _connectorSelectionKey(connector);
    if (selected) {
      _selectedMcpConnectors[key] = connector;
      notifyListeners();
      return;
    }

    if (_selectedMcpConnectors.remove(key) != null) {
      notifyListeners();
    }
  }

  void clearMcpConnectorSelections({bool notify = true}) {
    if (_selectedMcpConnectors.isEmpty) {
      return;
    }

    _selectedMcpConnectors.clear();
    if (notify) {
      notifyListeners();
    }
  }

  List<Toolkit> get clientToolkits {
    return List<Toolkit>.unmodifiable(_clientToolkits.values);
  }

  List<ClientToolkitDescription> get clientToolkitDescriptions {
    final descriptions = <ClientToolkitDescription>[];
    for (final toolkit in _clientToolkits.values) {
      for (final tool in toolkit.tools) {
        if (tool is! FunctionTool) {
          continue;
        }
        final title = tool.title?.trim();
        final description = tool.description?.trim();
        descriptions.add(
          ClientToolkitDescription(
            name: tool.name,
            title: title != null && title.isNotEmpty ? title : null,
            description: description != null && description.isNotEmpty ? description : null,
            inputSchema: Map<String, dynamic>.from(tool.inputSchema),
          ),
        );
      }
    }
    return descriptions;
  }

  void addClientToolkit(Toolkit toolkit) {
    final normalizedName = toolkit.name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(toolkit.name, 'toolkit.name', 'Client toolkit name is required.');
    }
    _clientToolkits[normalizedName] = toolkit;
    notifyListeners();
  }

  void removeClientToolkit(String toolkitName) {
    if (_clientToolkits.remove(toolkitName.trim()) != null) {
      notifyListeners();
    }
  }

  Future<Content> executeClientToolCall(AgentClientToolCallRequested request) async {
    for (final toolkit in _clientToolkits.values) {
      final tool = toolkit.tools.where((tool) => tool.name == request.tool).firstOrNull;
      if (tool == null) {
        continue;
      }
      try {
        final context = const ToolContext();
        final output = await toolkit.execute(
          context,
          request.tool,
          ToolContentInput(JsonContent(json: Map<String, dynamic>.from(request.arguments))),
        );
        if (output is ToolContentOutput) {
          if (tool is ToolResponseSentListener) {
            final listener = tool as ToolResponseSentListener;
            _pendingClientToolResponseCallbacks[request.requestId] = (listener: listener, context: context, response: output.content);
          }
          return output.content;
        }
        return ErrorContent(text: "Client toolkit '${request.tool}' returned a streaming response, which is not supported.");
      } catch (error) {
        return ErrorContent(text: "Client toolkit '${request.tool}' failed: $error");
      }
    }
    return ErrorContent(text: "Client toolkit '${request.tool}' is not registered.");
  }

  Future<void> finishClientToolCallResponse(AgentClientToolCallRequested request, {required bool responseSent}) async {
    final pending = _pendingClientToolResponseCallbacks.remove(request.requestId);
    if (!responseSent || pending == null) {
      return;
    }
    try {
      await pending.listener.onToolResponseSent(pending.context, pending.response);
    } catch (_) {}
  }

  void scrollThreadToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!threadScrollController.hasClients) {
        return;
      }

      final targetOffset = threadScrollController.position.minScrollExtent;
      if (animated) {
        unawaited(threadScrollController.animateTo(targetOffset, duration: const Duration(milliseconds: 180), curve: Curves.easeOut));
      } else {
        threadScrollController.jumpTo(targetOffset);
      }
    });
  }

  void resetThreadScrollPosition() {
    if (!threadScrollController.hasClients) {
      return;
    }

    threadScrollController.jumpTo(threadScrollController.position.minScrollExtent);
  }

  bool _listening = false;

  bool get listening {
    return _listening;
  }

  set listening(bool value) {
    if (value != _listening) {
      _listening = value;
      notifyListeners();
    }
  }

  List<FileAttachment> get attachmentUploads => List<FileAttachment>.unmodifiable(_attachmentUploads);

  List<PendingAgentMessage> get pendingAgentMessages => List<PendingAgentMessage>.unmodifiable(_pendingAgentMessages.values);

  List<PendingAgentMessage> pendingAgentMessagesForPath(String path) {
    return List<PendingAgentMessage>.unmodifiable(_pendingAgentMessages.values.where((message) => message.threadPath == path));
  }

  Iterable<RemoteParticipant> getAgentParticipants(MeshDocument document, {String? participantName}) sync* {
    final normalizedParticipantName = participantName?.trim();
    for (final participant in getOnlineParticipants(document).whereType<RemoteParticipant>()) {
      if (normalizedParticipantName != null &&
          normalizedParticipantName.isNotEmpty &&
          participant.getAttribute("name") != normalizedParticipantName) {
        continue;
      }
      if (_supportsAgentMessages(participant)) {
        yield participant;
      }
    }
  }

  void _markPendingAgentMessage({required PendingAgentMessage message}) {
    if (!message.hasVisibleContent) {
      return;
    }
    _pendingAgentMessages[message.messageId] = message;
    notifyListeners();
  }

  void markPendingAgentMessage(PendingAgentMessage message) {
    _markPendingAgentMessage(message: message);
  }

  void _clearPendingAgentMessage(String? messageId) {
    if (messageId == null || messageId.trim().isEmpty) {
      return;
    }

    if (_pendingAgentMessages.remove(messageId) != null) {
      notifyListeners();
    }
  }

  void _markPendingAgentMessageAccepted(String? messageId) {
    if (messageId == null || messageId.trim().isEmpty) {
      return;
    }

    final existing = _pendingAgentMessages[messageId];
    if (existing == null || !existing.awaitingAcceptance) {
      return;
    }

    _pendingAgentMessages[messageId] = PendingAgentMessage(
      messageId: existing.messageId,
      messageType: existing.messageType,
      threadPath: existing.threadPath,
      text: existing.text,
      attachments: existing.attachments,
      senderName: existing.senderName,
      createdAt: existing.createdAt,
      matchByContentOnly: existing.matchByContentOnly,
      awaitingAcceptance: false,
      awaitingApplication: true,
      awaitingOnline: false,
    );
    notifyListeners();
  }

  void _markPendingAgentMessageApplied(String? messageId) {
    if (messageId == null || messageId.trim().isEmpty) {
      return;
    }

    final existing = _pendingAgentMessages[messageId];
    if (existing == null || !existing.awaitingApplication) {
      return;
    }

    if (existing.messageType == agentTurnSteerType) {
      _pendingAgentMessages.remove(messageId);
      notifyListeners();
      return;
    }

    _pendingAgentMessages[messageId] = PendingAgentMessage(
      messageId: existing.messageId,
      messageType: existing.messageType,
      threadPath: existing.threadPath,
      text: existing.text,
      attachments: existing.attachments,
      senderName: existing.senderName,
      createdAt: existing.createdAt,
      matchByContentOnly: existing.matchByContentOnly,
      awaitingAcceptance: existing.awaitingAcceptance,
      awaitingApplication: false,
      awaitingOnline: existing.awaitingOnline,
    );
    notifyListeners();
  }

  void _setPendingAgentMessageAwaitingOnline(String? messageId, bool awaitingOnline) {
    if (messageId == null || messageId.trim().isEmpty) {
      return;
    }

    final existing = _pendingAgentMessages[messageId];
    if (existing == null || existing.awaitingOnline == awaitingOnline) {
      return;
    }

    _pendingAgentMessages[messageId] = PendingAgentMessage(
      messageId: existing.messageId,
      messageType: existing.messageType,
      threadPath: existing.threadPath,
      text: existing.text,
      attachments: existing.attachments,
      senderName: existing.senderName,
      createdAt: existing.createdAt,
      matchByContentOnly: existing.matchByContentOnly,
      awaitingAcceptance: existing.awaitingAcceptance,
      awaitingApplication: existing.awaitingApplication,
      awaitingOnline: awaitingOnline,
    );
    notifyListeners();
  }

  void clearPendingAgentMessages() {
    if (_pendingAgentMessages.isEmpty) {
      return;
    }

    _pendingAgentMessages.clear();
    notifyListeners();
  }

  void clearPendingAgentMessagesForThread(String threadPath) {
    if (threadPath.trim().isEmpty || _pendingAgentMessages.isEmpty) {
      return;
    }

    var changed = false;
    _pendingAgentMessages.removeWhere((_, message) {
      if (message.threadPath != threadPath) {
        return false;
      }
      changed = true;
      return true;
    });
    if (changed) {
      notifyListeners();
    }
  }

  void handleAgentMessage(AgentMessage message) {
    final type = message.type;
    final normalizedSourceMessageId = switch (message) {
      TurnStartAccepted() => message.sourceMessageId,
      TurnStartRejected() => message.sourceMessageId,
      TurnSteerRejected() => message.sourceMessageId,
      TurnStarted() => message.sourceMessageId,
      TurnSteered() => message.sourceMessageId,
      _ => null,
    };
    final normalizedThreadPath = message is AgentThreadMessage ? message.threadId.trim() : "";

    if (type == agentTurnStartType || type == agentTurnSteerType) {
      if (message is! AgentThreadMessage) {
        return;
      }
      final pendingMessage = PendingAgentMessage.fromTurnInputMessage(message);
      if (pendingMessage.threadPath.trim().isNotEmpty) {
        _markPendingAgentMessage(message: pendingMessage);
      }
      return;
    }

    if (type == agentTurnStartAcceptedType || type == agentTurnSteerAcceptedType) {
      if (normalizedSourceMessageId != null && _pendingAgentMessages.containsKey(normalizedSourceMessageId)) {
        _markPendingAgentMessageAccepted(normalizedSourceMessageId);
      } else if (message is TurnStartAccepted) {
        final pendingMessage = PendingAgentMessage.fromAcceptedMessage(message);
        if (pendingMessage.threadPath.trim().isNotEmpty && pendingMessage.hasVisibleContent) {
          _markPendingAgentMessage(message: pendingMessage);
        }
      }
      return;
    }

    if (type == agentTurnStartedType || type == agentTurnSteeredType) {
      _markPendingAgentMessageApplied(normalizedSourceMessageId);
      return;
    }

    if (type == agentTurnInterruptAcceptedType || type == agentTurnInterruptedType) {
      return;
    }

    if (type == agentTurnStartRejectedType || type == agentTurnSteerRejectedType) {
      _clearPendingAgentMessage(normalizedSourceMessageId);
      final errorMessage = switch (message) {
        TurnStartRejected() => message.error.message,
        TurnSteerRejected() => message.error.message,
        _ => null,
      };
      outboundStatus.markFailed(
        normalizedSourceMessageId ?? "",
        errorMessage != null && errorMessage.trim().isNotEmpty ? errorMessage.trim() : "Message rejected",
      );
      return;
    }

    if (type == agentTurnEndedType || type == agentThreadClearedType) {
      clearPendingAgentMessagesForThread(normalizedThreadPath);
    }
  }

  void handleAgentMessagePayload(Map<String, dynamic> payload) {
    final message = _agentMessageFromRoomPayload(payload);
    if (message != null) {
      handleAgentMessage(message);
    }
  }

  List<RemoteParticipant> _uniqueRemoteParticipantsById(Iterable<RemoteParticipant> participants) {
    final seenParticipantIds = <String>{};
    final uniqueParticipants = <RemoteParticipant>[];
    for (final participant in participants) {
      if (seenParticipantIds.add(participant.id)) {
        uniqueParticipants.add(participant);
      }
    }
    return uniqueParticipants;
  }

  List<RemoteParticipant> _matchingRecipients({
    required MeshDocument thread,
    required bool useAgentMessages,
    required String? participantName,
  }) {
    final normalizedParticipantName = participantName?.trim();
    if (useAgentMessages) {
      return _uniqueRemoteParticipantsById(getAgentParticipants(thread, participantName: normalizedParticipantName));
    }

    return _uniqueRemoteParticipantsById(
      getOnlineParticipants(thread).whereType<RemoteParticipant>().where((participant) {
        if (normalizedParticipantName == null || normalizedParticipantName.isEmpty) {
          return true;
        }
        return participant.getAttribute("name") == normalizedParticipantName;
      }),
    );
  }

  bool hasPendingSendWait(String threadPath) {
    return _pendingSendWaits.values.any((wait) => wait.threadPath == threadPath);
  }

  void cancelPendingSend(String threadPath) {
    final waits = _pendingSendWaits.values.where((wait) => wait.threadPath == threadPath).toList();
    for (final wait in waits) {
      wait.cancel();
    }
  }

  Future<List<RemoteParticipant>> _waitForRecipients({
    required MeshDocument thread,
    required String path,
    required String messageId,
    required bool useAgentMessages,
    required String? participantName,
  }) async {
    final room = _requireRoom('Waiting for recipients');
    final existing = _pendingSendWaits.remove(messageId);
    existing?.cancel();

    final wait = _PendingSendWait(messageId: messageId, threadPath: path);
    _pendingSendWaits[messageId] = wait;
    _setPendingAgentMessageAwaitingOnline(messageId, true);
    notifyListeners();

    final completer = Completer<List<RemoteParticipant>>();

    void listener() {
      if (completer.isCompleted) {
        return;
      }

      final recipients = _matchingRecipients(thread: thread, useAgentMessages: useAgentMessages, participantName: participantName);
      if (recipients.isNotEmpty) {
        completer.complete(recipients);
      }
    }

    void finish() {
      final removed = _pendingSendWaits.remove(messageId);
      if (identical(removed, wait)) {
        room.messaging.removeListener(listener);
        wait.detach = null;
      }
      _setPendingAgentMessageAwaitingOnline(messageId, false);
      notifyListeners();
    }

    wait.detach = () {
      room.messaging.removeListener(listener);
      wait.detach = null;
    };
    room.messaging.addListener(listener);
    listener();

    try {
      return await Future.any([
        completer.future,
        wait.cancelled.future.then<List<RemoteParticipant>>((_) => throw const ChatSendCancelledException()),
      ]);
    } finally {
      finish();
    }
  }

  Future<void> cancel(String path, MeshDocument thread, {bool useAgentMessages = false, String? turnId, String? participantName}) async {
    if (hasPendingSendWait(path)) {
      cancelPendingSend(path);
      return;
    }

    if (useAgentMessages) {
      final room = _requireRoom('Canceling an agent turn');
      if (turnId == null || turnId.trim().isEmpty) {
        return;
      }

      await Future.wait([
        for (final participant in getAgentParticipants(thread, participantName: participantName))
          room.messaging.sendMessage(
            to: participant,
            type: agentRoomMessageType,
            message: {"type": agentTurnInterruptType, "thread_id": path, "turn_id": turnId},
          ),
      ]);
      return;
    }

    final room = _requireRoom('Canceling a thread');
    for (final participant in getOnlineParticipants(thread).whereType<RemoteParticipant>()) {
      final normalizedParticipantName = participantName?.trim();
      if (normalizedParticipantName != null &&
          normalizedParticipantName.isNotEmpty &&
          participant.getAttribute("name") != normalizedParticipantName) {
        continue;
      }
      if (participant.role == "agent") {
        await room.messaging.sendMessage(to: participant, type: "cancel", message: {"path": path});
      }
    }
  }

  Future<void> clearThread(String path, MeshDocument thread, {bool useAgentMessages = false, String? participantName}) async {
    if (useAgentMessages) {
      final room = _requireRoom('Clearing an agent thread');
      await Future.wait([
        for (final participant in getAgentParticipants(thread, participantName: participantName))
          room.messaging.sendMessage(
            to: participant,
            type: agentRoomMessageType,
            message: {"type": agentThreadClearType, "thread_id": path},
          ),
      ]);
      return;
    }

    final room = _requireRoom('Clearing a thread');
    final normalizedParticipantName = participantName?.trim();
    final participant = room.messaging.remoteParticipants.firstWhereOrNull((x) {
      if (normalizedParticipantName == null || normalizedParticipantName.isEmpty) {
        return true;
      }
      return x.getAttribute("name") == normalizedParticipantName;
    });
    if (participant != null) {
      await room.messaging.sendMessage(to: participant, type: "clear", message: {"path": path});
    }
  }

  Future<FileAttachment> uploadFile(String path, Stream<Uint8List> dataStream, int size, {String? mimeType}) async {
    final room = this.room;
    if (room == null) {
      throw StateError('File uploads require a room storage provider.');
    }
    final uploader = MeshagentFileUpload(room: room, path: path, dataStream: dataStream, size: size, mimeType: mimeType);
    uploader.addListener(notifyListeners);

    _attachmentUploads.add(uploader);
    notifyListeners();

    return uploader;
  }

  Future<FileAttachment> uploadFileDeferred(String path, Stream<Uint8List> dataStream, int size, {String? mimeType}) async {
    final room = this.room;
    if (room == null) {
      throw StateError('File uploads require a room storage provider.');
    }
    final uploader = MeshagentFileUpload.deferred(room: room, path: path, dataStream: dataStream, size: size, mimeType: mimeType);

    uploader.addListener(notifyListeners);

    _attachmentUploads.add(uploader);
    notifyListeners();

    return uploader;
  }

  FileAttachment attachFile(String path, {String? mimeType, String? displayName}) {
    final attachment = FileAttachment(path: path, mimeType: mimeType, displayName: displayName, initialStatus: UploadStatus.completed);
    attachment.addListener(notifyListeners);
    _attachmentUploads.add(attachment);
    notifyListeners();
    return attachment;
  }

  String get text {
    return textFieldController.text;
  }

  void removeFileUpload(FileAttachment upload) {
    upload.removeListener(notifyListeners);

    _attachmentUploads.remove(upload);

    notifyListeners();
  }

  void clear() {
    for (final upload in _attachmentUploads) {
      upload.removeListener(notifyListeners);
    }

    textFieldController.clear();
    _attachmentUploads.clear();

    notifyListeners();
  }

  Iterable<String> getParticipantNames(MeshDocument document) sync* {
    final seenParticipantNames = <String>{};
    for (final child in document.root.getChildren().whereType<MeshElement>()) {
      if (child.tagName == "members") {
        for (final member in child.getChildren().whereType<MeshElement>()) {
          final participantName = member.getAttribute("name");
          if (participantName is String && participantName.isNotEmpty && seenParticipantNames.add(participantName)) {
            yield participantName;
          }
        }
      }
    }
  }

  Iterable<String> getOfflineParticipants(MeshDocument document) sync* {
    final room = _requireRoom('Resolving offline participants');
    for (final participantName in getParticipantNames(document)) {
      bool found = false;
      if (room.messaging.remoteParticipants.where((x) => x.getAttribute("name") == participantName).isNotEmpty ||
          participantName == room.localParticipant?.getAttribute("name")) {
        found = true;
      }
      if (!found) {
        yield participantName;
      }
    }
  }

  Iterable<Participant> getOnlineParticipants(MeshDocument document) sync* {
    final room = _requireRoom('Resolving online participants');
    final seenParticipantIds = <String>{};
    for (final participantName in getParticipantNames(document)) {
      if (participantName == room.localParticipant?.getAttribute("name")) {
        final localParticipant = room.localParticipant;
        if (localParticipant != null && seenParticipantIds.add(localParticipant.id)) {
          yield localParticipant;
        }
      }
      for (final part in room.messaging.remoteParticipants.where((x) => x.getAttribute("name") == participantName)) {
        if (seenParticipantIds.add(part.id)) {
          yield part;
        }
      }
    }
  }

  Future<void> sendMessageToParticipant({
    required Participant participant,
    required String path,
    required ChatMessage message,
    String messageType = "chat",
    bool useAgentMessages = false,
    String? turnId,
    TurnMcpConfig? mcp,
    List<ClientToolkitDescription>? clientToolkits,
    AgentToolChoice? toolChoice,
    String? remoteMessageText,
    bool store = false,
  }) async {
    if (message.text.trim().isNotEmpty || message.attachments.isNotEmpty) {
      final room = _requireRoom('Sending a participant message');
      final remoteMessage = remoteMessageText == null
          ? message
          : ChatMessage(id: message.id, text: remoteMessageText, attachments: message.attachments);
      if (useAgentMessages) {
        final isSteer = messageType == "steer";
        final payload = isSteer
            ? TurnSteer(
                threadId: path,
                messageId: remoteMessage.id,
                turnId: turnId != null && turnId.trim().isNotEmpty ? turnId.trim() : remoteMessage.id,
                content: _agentInputContentFromMessage(remoteMessage),
              )
            : TurnStart(
                threadId: path,
                messageId: remoteMessage.id,
                content: _agentInputContentFromMessage(remoteMessage),
                mcp: mcp,
                clientToolkits: clientToolkits != null && clientToolkits.isNotEmpty ? clientToolkits : null,
                toolChoice: toolChoice == null ? null : ToolChoice(toolkitName: toolChoice.toolkitName, toolName: toolChoice.toolName),
              );
        await room.messaging.sendMessage(to: participant, type: agentRoomMessageType, message: payload.toJson());
        return;
      }

      await room.messaging.sendMessage(
        to: participant,
        type: messageType,
        message: {
          "path": path,
          "text": remoteMessage.text,
          "attachments": remoteMessage.attachments.map((a) => {"path": a}).toList(),
          "store": store,
        },
      );
    }
  }

  void insertMessage({required MeshDocument thread, required ChatMessage message}) {
    final room = _requireRoom('Inserting a local message');
    final messages = thread.root.getChildren().whereType<MeshElement>().firstWhere((x) => x.tagName == "messages");

    final m = messages.createChildElement("message", {
      "id": message.id,
      "text": message.text,
      "created_at": DateTime.now().toUtc().toIso8601String(),
      "author_name": room.localParticipant!.getAttribute("name"),
      "author_ref": null,
      "role": "user",
    });

    for (final path in message.attachments) {
      m.createChildElement("file", {"path": path});
    }
  }

  bool _notifyOnSend = true;

  bool get notifyOnSend {
    return _notifyOnSend;
  }

  set notifyOnSend(bool value) {
    _notifyOnSend = value;
    notifyListeners();
  }

  Future<void> send({
    required MeshDocument thread,
    required String path,
    required ChatMessage message,
    String messageType = "chat",
    String? remoteStoreParticipantName,
    bool storeLocally = true,
    bool useAgentMessages = false,
    String? turnId,
    TurnMcpConfig? mcp,
    List<ClientToolkitDescription>? clientToolkits,
    AgentToolChoice? toolChoice,
    String? remoteMessageText,
    void Function(ChatMessage)? onMessageSent,
  }) async {
    if (message.text.trim().isNotEmpty || message.attachments.isNotEmpty) {
      if (storeLocally) {
        insertMessage(thread: thread, message: message);
      }

      final normalizedParticipantName = remoteStoreParticipantName?.trim();
      if (useAgentMessages) {
        final room = _requireRoom('Sending an agent message');
        final senderName = room.localParticipant?.getAttribute("name");
        _markPendingAgentMessage(
          message: PendingAgentMessage(
            messageId: message.id,
            messageType: messageType == "steer" ? agentTurnSteerType : agentTurnStartType,
            threadPath: path,
            text: message.text,
            attachments: [for (final attachment in message.attachments) AgentFileContent(url: attachment)],
            senderName: senderName is String && senderName.trim().isNotEmpty ? senderName.trim() : null,
            createdAt: DateTime.now(),
            matchByContentOnly: false,
            awaitingAcceptance: true,
            awaitingApplication: true,
            awaitingOnline: false,
          ),
        );
      }

      outboundStatus.markSending(message.id);

      try {
        final List<Future<void>> sentMessages = [];
        if (notifyOnSend) {
          var participants = _matchingRecipients(
            thread: thread,
            useAgentMessages: useAgentMessages,
            participantName: normalizedParticipantName,
          );
          if (participants.isEmpty) {
            final shouldWaitForRecipient = useAgentMessages || (normalizedParticipantName != null && normalizedParticipantName.isNotEmpty);
            if (!shouldWaitForRecipient) {
              throw StateError("no matching recipients are available for '$path'");
            }
            participants = await _waitForRecipients(
              thread: thread,
              path: path,
              messageId: message.id,
              useAgentMessages: useAgentMessages,
              participantName: normalizedParticipantName,
            );
          }

          for (final participant in participants) {
            final participantName = participant.getAttribute("name");
            final shouldStoreRemotely =
                remoteStoreParticipantName != null && participantName is String && participantName == remoteStoreParticipantName;
            sentMessages.add(
              sendMessageToParticipant(
                participant: participant,
                path: path,
                message: message,
                messageType: messageType,
                useAgentMessages: useAgentMessages,
                turnId: turnId,
                mcp: mcp,
                clientToolkits: messageType == "steer" ? null : clientToolkits,
                toolChoice: toolChoice,
                remoteMessageText: remoteMessageText,
                store: shouldStoreRemotely,
              ),
            );
          }
        }

        await Future.wait(sentMessages);
        outboundStatus.markDelivered(message.id);
        onMessageSent?.call(message);
      } on ChatSendCancelledException {
        outboundStatus.clear(message.id);
        if (useAgentMessages) {
          _clearPendingAgentMessage(message.id);
        }
        rethrow;
      } catch (error, stackTrace) {
        outboundStatus.markFailed(message.id, error, stackTrace);
        if (useAgentMessages) {
          _clearPendingAgentMessage(message.id);
        }
        rethrow;
      }
    }
  }

  @override
  void dispose() {
    _pendingClientToolResponseCallbacks.clear();
    textFieldController.removeListener(notifyListeners);
    threadScrollController.dispose();
    textFieldController.dispose();
    outboundStatus.dispose();

    for (final upload in _attachmentUploads) {
      upload.removeListener(notifyListeners);
      if (upload is MeshagentFileUpload) {
        upload.done.ignore();
      }
      upload.dispose();
    }

    super.dispose();
  }
}

double chatThreadFeedHorizontalPadding(double maxWidth) {
  return maxWidth > 912 ? (maxWidth - 912) / 2 : 16;
}

double chatThreadStatusHorizontalPadding(double maxWidth) {
  return maxWidth > 912 ? (maxWidth - 912) / 2 : 15;
}

class ChatThreadInputFrame extends StatelessWidget {
  const ChatThreadInputFrame({super.key, required this.child, this.hasFooter = false});

  final Widget child;
  final bool hasFooter;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = _usesMobileContextLayout(context) && MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomPadding = keyboardOpen ? 4.0 : (hasFooter ? 4.0 : 8.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(15, 8, 15, bottomPadding),
      child: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 912), child: child),
      ),
    );
  }
}

class ChatThreadViewportBody extends StatefulWidget {
  const ChatThreadViewportBody({
    super.key,
    required this.children,
    this.scrollController,
    this.bottomAlign = true,
    this.centerContent,
    this.bottomSpacer = 0,
    this.bottomSpacerKey,
    this.bottomSpacerAnimationDuration = Duration.zero,
    this.bottomSpacerAnimationCurve = Curves.easeOutCubic,
    this.overlays = const [],
    this.tapRegionGroupId,
    this.mobileUnderHeaderContentPadding,
  });

  final List<Widget> children;
  final ScrollController? scrollController;
  final bool bottomAlign;
  final Widget? centerContent;
  final double bottomSpacer;
  final Key? bottomSpacerKey;
  final Duration bottomSpacerAnimationDuration;
  final Curve bottomSpacerAnimationCurve;
  final List<Widget> overlays;
  final Object? tapRegionGroupId;
  final double? mobileUnderHeaderContentPadding;

  @override
  State<ChatThreadViewportBody> createState() => _ChatThreadViewportBodyState();
}

class _ChatThreadViewportBodyState extends State<ChatThreadViewportBody> {
  double? _lastKeyboardInset;
  double _pendingKeyboardInsetDelta = 0;
  bool _keyboardAdjustmentScheduled = false;

  void _scheduleKeyboardOffsetAdjustment(double delta) {
    if (widget.scrollController == null || delta.abs() < 0.5) {
      return;
    }

    _pendingKeyboardInsetDelta += delta;
    if (_keyboardAdjustmentScheduled) {
      return;
    }

    _keyboardAdjustmentScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardAdjustmentScheduled = false;
      if (!mounted) {
        _pendingKeyboardInsetDelta = 0;
        return;
      }

      final scrollController = widget.scrollController;
      if (scrollController == null || !scrollController.hasClients) {
        _pendingKeyboardInsetDelta = 0;
        return;
      }

      final delta = _pendingKeyboardInsetDelta;
      _pendingKeyboardInsetDelta = 0;
      if (delta.abs() < 0.5) {
        return;
      }

      final position = scrollController.position;
      if (position.pixels <= position.minScrollExtent + 1) {
        return;
      }

      final nextOffset = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
      if ((nextOffset - position.pixels).abs() < 0.5) {
        return;
      }

      scrollController.jumpTo(nextOffset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final lastKeyboardInset = _lastKeyboardInset;
    _lastKeyboardInset = keyboardInset;
    if (_usesMobileContextLayout(context) && lastKeyboardInset != null && (keyboardInset - lastKeyboardInset).abs() >= 0.5) {
      _scheduleKeyboardOffsetAdjustment(keyboardInset - lastKeyboardInset);
    }

    final keyboardDismissBehavior = _usesMobileContextLayout(context)
        ? ScrollViewKeyboardDismissBehavior.manual
        : ScrollViewKeyboardDismissBehavior.onDrag;
    final underHeaderContentPadding = _usesMobileContextLayout(context) ? (widget.mobileUnderHeaderContentPadding ?? 40.0) : 0.0;
    final dismissKeyboardOnTap = _usesMobileContextLayout(context) && keyboardInset > 0
        ? () => FocusManager.instance.primaryFocus?.unfocus()
        : null;

    return Center(
      child: Stack(
        children: [
          if (widget.bottomAlign && widget.centerContent != null && widget.children.isEmpty)
            Positioned.fill(
              child: IgnorePointer(child: Center(child: widget.centerContent!)),
            ),
          Positioned.fill(
            child: Column(
              mainAxisAlignment: widget.bottomAlign ? MainAxisAlignment.end : MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        top: -underHeaderContentPadding,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: dismissKeyboardOnTap,
                          child: TextFieldTapRegion(
                            groupId: widget.tapRegionGroupId,
                            child: LayoutBuilder(
                              builder: (context, constraints) => ListView(
                                controller: widget.scrollController,
                                reverse: true,
                                keyboardDismissBehavior: keyboardDismissBehavior,
                                padding: EdgeInsets.only(
                                  top: underHeaderContentPadding,
                                  bottom: 16,
                                  left: chatThreadFeedHorizontalPadding(constraints.maxWidth),
                                  right: chatThreadFeedHorizontalPadding(constraints.maxWidth),
                                ),
                                children: widget.children,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.bottomAlign && widget.centerContent != null) widget.centerContent!,
                AnimatedContainer(
                  key: widget.bottomSpacerKey,
                  duration: widget.bottomSpacerAnimationDuration,
                  curve: widget.bottomSpacerAnimationCurve,
                  height: widget.bottomSpacer,
                ),
              ],
            ),
          ),
          ...widget.overlays,
        ],
      ),
    );
  }
}

class ChatThreadToolArea extends StatelessWidget {
  const ChatThreadToolArea({super.key, this.leading, this.footer});

  final Widget? leading;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    final footer = this.footer;
    if (leading == null && footer == null) {
      return const SizedBox.shrink();
    }
    if (leading == null) {
      return footer!;
    }
    if (footer == null) {
      return leading;
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [leading, footer]);
  }
}

ChatThreadToolArea resolveChatThreadToolArea(Widget? tools) {
  if (tools == null) {
    return const ChatThreadToolArea();
  }
  if (tools is ChatThreadToolArea) {
    return tools;
  }
  return ChatThreadToolArea(leading: tools);
}

typedef ChatThreadCustomInputBuilder = Widget Function(BuildContext context, ChatThreadInputConfig config, Widget defaultInput);

class ChatThreadInputConfig {
  const ChatThreadInputConfig({
    required this.controller,
    required this.snapshot,
    required this.placeholder,
    required this.sendEnabled,
    required this.sendDisabledReason,
    required this.readOnly,
    required this.onSend,
    this.threadErrorMessage,
    this.onSendWithAgentText,
    this.onChanged,
    this.onClear,
    this.onInterrupt,
    this.onCancelSend,
    this.sendPendingText,
    this.attachmentBuilder,
    this.onAttachmentOpen,
    this.onAttachmentRemoved,
    this.onFileDrop,
    this.leading,
    this.trailing,
    this.header,
    this.footer,
    this.audioInputEnabled = false,
    this.automaticAudioTurnDetection = false,
    this.onAudioRecordingStart,
    this.onExternalAudioRecordingStart,
    this.onExternalAudioRecordingStop,
    this.onAudioChunk,
    this.contextMenuBuilder,
    this.onPressedOutside,
    this.tapRegionGroupId,
    this.room,
  });

  final ChatThreadController controller;
  final ChatThreadSnapshot snapshot;
  final Widget? placeholder;
  final bool sendEnabled;
  final String? sendDisabledReason;
  final bool readOnly;
  final Future<void> Function(String, List<FileAttachment>) onSend;
  final String? threadErrorMessage;
  final Future<void> Function(String visibleText, String agentText, List<FileAttachment> attachments)? onSendWithAgentText;
  final void Function(String, List<FileAttachment>)? onChanged;
  final VoidCallback? onClear;
  final VoidCallback? onInterrupt;
  final VoidCallback? onCancelSend;
  final String? sendPendingText;
  final Widget Function(BuildContext context, FileAttachment upload)? attachmentBuilder;
  final ValueChanged<FileAttachment>? onAttachmentOpen;
  final ValueChanged<FileAttachment>? onAttachmentRemoved;
  final Future<void> Function(String name, Stream<Uint8List> dataStream, int size)? onFileDrop;
  final Widget? leading;
  final Widget? trailing;
  final Widget? header;
  final Widget? footer;
  final bool audioInputEnabled;
  final bool automaticAudioTurnDetection;
  final Future<void> Function()? onAudioRecordingStart;
  final Future<void> Function()? onExternalAudioRecordingStart;
  final Future<void> Function()? onExternalAudioRecordingStop;
  final Future<void> Function(Uint8List chunk, {required bool finalChunk})? onAudioChunk;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final TapRegionCallback? onPressedOutside;
  final Object? tapRegionGroupId;
  final RoomClient? room;
}

typedef ChatThreadAttachmentMenuItemsBuilder =
    List<ShadContextMenuItem> Function(BuildContext context, ChatThreadController controller, ShadPopoverController popoverController);

class ClientResponseDialogToolkit extends Toolkit {
  ClientResponseDialogToolkit({
    required BuildContext context,
    required super.name,
    super.title,
    super.description,
    required Map<String, dynamic> inputSchema,
  }) : super(
         tools: [ClientResponseDialogTool(context: context, name: name, title: title, description: description, inputSchema: inputSchema)],
       );
}

class ClientResponseDialogTool extends FunctionTool {
  ClientResponseDialogTool({required BuildContext context, required super.name, super.title, super.description, required super.inputSchema})
    : navigator = Navigator.of(context, rootNavigator: true);

  final NavigatorState navigator;

  @override
  Future<Content> execute(ToolContext context, Map<String, dynamic> arguments) async {
    if (!navigator.mounted) {
      return ErrorContent(text: "Client toolkit request could not be shown because the chat view is no longer mounted.");
    }

    final responseController = CodeLineEditingController.fromText(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{"answer": ""}),
    );
    Object? responseError;
    final resolvedTitle = title?.trim().isNotEmpty == true ? title!.trim() : name;
    final resolvedDescription = description?.trim().isNotEmpty == true
        ? description!.trim()
        : "The agent requested a response from this client-side tool.";

    try {
      final response = await showShadDialog<Content>(
        context: navigator.context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => ShadDialog(
            title: Text(resolvedTitle),
            description: Text(resolvedDescription),
            actions: [
              ShadButton.secondary(
                onPressed: () => Navigator.of(context).pop(ErrorContent(text: "Client toolkit request was cancelled.")),
                child: const Text("Cancel"),
              ),
              ShadButton(
                onPressed: () {
                  try {
                    final parsed = jsonDecode(responseController.text);
                    if (parsed is! Map) {
                      throw const FormatException("Response must be a JSON object.");
                    }
                    Navigator.of(context).pop(JsonContent(json: parsed.map((key, value) => MapEntry(key.toString(), value))));
                  } catch (error) {
                    setDialogState(() => responseError = error);
                  }
                },
                child: const Text("Send"),
              ),
            ],
            child: SizedBox(
              width: 680,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (arguments.isNotEmpty) ...[
                    Text("Arguments", style: ShadTheme.of(context).textTheme.small),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: ShadTheme.of(context).colorScheme.muted, borderRadius: BorderRadius.circular(8)),
                      child: Text(const JsonEncoder.withIndent('  ').convert(arguments)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text("Response", style: ShadTheme.of(context).textTheme.small),
                  const SizedBox(height: 6),
                  Expanded(
                    child: CodeEditor(
                      style: CodeEditorStyle(
                        fontSize: 14,
                        fontFamily: ThreadTypographyOverride.maybeCodeFontFamilyOf(context) ?? defaultThreadCodeFontFamily,
                        codeTheme: CodeHighlightTheme(
                          languages: {'default': CodeHighlightThemeMode(mode: langJson)},
                          theme: monokaiSublimeTheme,
                        ),
                      ),
                      controller: responseController,
                      onChanged: (_) {
                        if (responseError != null) {
                          setDialogState(() => responseError = null);
                        }
                      },
                    ),
                  ),
                  if (responseError != null) ...[
                    const SizedBox(height: 8),
                    ShadAlert.destructive(description: Text("$responseError", maxLines: 3)),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
      return response ?? ErrorContent(text: "Client toolkit request was cancelled.");
    } finally {
      responseController.dispose();
    }
  }
}

class ChatThreadAttachButton extends StatefulWidget {
  const ChatThreadAttachButton({
    required this.controller,
    super.key,
    this.alwaysShowAttachFiles,
    this.availableRooms,
    this.connectRoomClient,
    this.agentName,
    this.showMcpConnectors = false,
    this.menuItemsBuilder,
    this.additionalMenuItemsBuilder,
    this.inlineAttachments = false,
    this.acceptedMimeTypes = const <String>[],
  });

  final bool? alwaysShowAttachFiles;
  final ChatThreadController controller;
  final Future<List<Room>> Function()? availableRooms;
  final Future<RoomClient> Function(String roomName)? connectRoomClient;
  final String? agentName;
  final bool showMcpConnectors;
  final ChatThreadAttachmentMenuItemsBuilder? menuItemsBuilder;
  final ChatThreadAttachmentMenuItemsBuilder? additionalMenuItemsBuilder;
  final bool inlineAttachments;
  final List<String> acceptedMimeTypes;

  @override
  State createState() => _ChatThreadAttachButton();
}

class _ChatThreadAttachButton extends State<ChatThreadAttachButton> {
  final ShadPopoverController popoverController = ShadPopoverController();

  bool get _canShowMcpConnectors {
    final normalizedAgentName = widget.agentName?.trim();
    return widget.showMcpConnectors && normalizedAgentName != null && normalizedAgentName.isNotEmpty;
  }

  bool get _canUseInlineAttachments => widget.inlineAttachments && widget.controller.room == null;

  bool get _canUseInlinePhotoPicker {
    if (!_canUseInlineAttachments || kIsWeb) {
      return false;
    }
    final accepted = widget.acceptedMimeTypes;
    if (accepted.isEmpty) {
      return true;
    }
    return accepted.any((value) {
      final normalized = value.trim().toLowerCase();
      return normalized == "*" || normalized == "*/*" || normalized == "image/*" || normalized.startsWith("image/");
    });
  }

  bool _acceptsMimeType(String mimeType) {
    final normalizedMimeType = mimeType.split(";").first.trim().toLowerCase();
    if (normalizedMimeType.isEmpty) {
      return widget.acceptedMimeTypes.isEmpty;
    }
    if (widget.acceptedMimeTypes.isEmpty) {
      return true;
    }
    return widget.acceptedMimeTypes.any((value) {
      final normalized = value.trim().toLowerCase();
      if (normalized == "*" || normalized == "*/*") {
        return true;
      }
      if (normalized.endsWith("/*")) {
        return normalizedMimeType.startsWith(normalized.substring(0, normalized.length - 1));
      }
      return normalized == normalizedMimeType;
    });
  }

  String _guessMimeType(String name, {List<int>? headerBytes}) {
    final guessed = lookupMimeType(name, headerBytes: headerBytes);
    if (guessed != null && guessed.isNotEmpty) {
      return guessed;
    }
    return "application/octet-stream";
  }

  Future<Uint8List> _readByteStream(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _showUnsupportedAttachmentToast(String name, String mimeType) {
    if (!mounted) {
      return;
    }
    ShadToaster.of(context).show(
      ShadToast.destructive(
        title: const Text("Attachment not supported"),
        description: Text("$name uses $mimeType, which the selected model does not accept."),
      ),
    );
  }

  void _attachInlineData({required String name, required String mimeType, required Uint8List data}) {
    final encodedData = base64Encode(data);
    widget.controller.attachFile("data:$mimeType;base64,$encodedData", mimeType: mimeType, displayName: name);
  }

  Future<String> _resolveImportedPath(String requestedPath) async {
    final room = widget.controller._requireRoom('Resolving imported attachment path');
    String candidate = requestedPath.split("/").last;
    final dotIndex = candidate.lastIndexOf('.');
    final stem = dotIndex > 0 ? candidate.substring(0, dotIndex) : candidate;
    final extension = dotIndex > 0 ? candidate.substring(dotIndex) : '';

    for (var i = 1; ; i++) {
      final candidateExists = await room.storage.exists(candidate);
      if (!candidateExists) {
        return candidate;
      }

      final suffix = i == 1 ? ' copy' : ' copy $i';
      candidate = '$stem$suffix$extension';
    }
  }

  Future<String> _importFile({required RoomClient sourceRoom, required String sourcePath}) async {
    final room = widget.controller._requireRoom('Importing attachment from room');
    final content = await sourceRoom.storage.download(sourcePath);
    final destinationPath = await _resolveImportedPath(sourcePath);

    await room.storage.uploadStream(destinationPath, Stream.value(content.data), overwrite: true, size: content.data.length);

    return destinationPath;
  }

  Future<void> _onSelectAttachment() async {
    final picked = await FilePicker.pickFiles(dialogTitle: "Select files", allowMultiple: true, withReadStream: true);

    if (picked == null) {
      return;
    }

    for (final file in picked.files) {
      if (_canUseInlineAttachments) {
        final readStream = file.readStream;
        if (readStream == null) {
          continue;
        }
        final data = await _readByteStream(readStream);
        final mimeType = _guessMimeType(file.name, headerBytes: data);
        if (!_acceptsMimeType(mimeType)) {
          _showUnsupportedAttachmentToast(file.name, mimeType);
          continue;
        }
        _attachInlineData(name: file.name, mimeType: mimeType, data: data);
        continue;
      }
      await widget.controller.uploadFile(file.name, file.readStream!.map(Uint8List.fromList), file.size);
    }
  }

  Future<void> _onSelectPhoto() async {
    final picker = ImagePicker();

    List<XFile> picked = const [];
    try {
      picked = await picker.pickMultipleMedia(); // images and videos
    } catch (_) {
      // Older web/mobile builds may not support pickMultipleMedia.
    }
    if (picked.isEmpty) {
      try {
        picked = await picker.pickMultiImage(); // at least images
      } catch (_) {
        // As a last resort, single image (some platforms).
        final single = await picker.pickImage(source: ImageSource.gallery);
        if (single != null) picked = [single];
      }
    }
    if (picked.isEmpty) return;

    final names = PhotoNamer.generateBatchNames(picked);

    for (var i = 0; i < picked.length; i++) {
      final file = picked[i];
      final fileName = names[i];
      if (_canUseInlineAttachments) {
        final data = await file.readAsBytes();
        final mimeType = _guessMimeType(fileName, headerBytes: data);
        if (!_acceptsMimeType(mimeType)) {
          _showUnsupportedAttachmentToast(fileName, mimeType);
          continue;
        }
        _attachInlineData(name: fileName, mimeType: mimeType, data: data);
        continue;
      }
      final size = await file.length();
      final stream = file.openRead();

      await widget.controller.uploadFile(fileName, stream, size);
    }
  }

  Future<void> _onBrowseFiles() async {
    final room = widget.controller._requireRoom('Browsing room attachments');
    final currentRoomName = room.roomName?.trim() ?? "";
    String selectedRoomName = currentRoomName;
    RoomClient selectedRoomClient = room;
    bool resolvingRoom = false;
    bool resolveError = false;
    List<String> picked = [];

    var roomOptions = [selectedRoomName];
    if (widget.availableRooms != null) {
      try {
        final loaded = await widget.availableRooms!();
        roomOptions = {selectedRoomName, ...loaded.map((r) => r.name).where((n) => n.isNotEmpty)}.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      } catch (_) {}
    }

    if (!mounted) {
      return;
    }

    await showShadDialog(
      context: context,

      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ShadDialog(
          title: Text("Select files"),
          scrollable: false,
          description: Text("Attach files from this room"),
          actions: [
            ShadButton.secondary(
              onPressed: () {
                picked.clear();
                Navigator.of(context).pop([]);
              },
              child: Text("Cancel"),
            ),
            ShadButton.secondary(
              onPressed: () {
                Navigator.of(context).pop(picked);
              },
              child: Text("OK"),
            ),
          ],
          child: SizedBox(
            width: 500,
            height: 450,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (roomOptions.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ShadSelect<String>(
                        initialValue: selectedRoomName,
                        selectedOptionBuilder: (context, value) => Text(value),
                        options: [for (final option in roomOptions) ShadOption<String>(value: option, child: Text(option))],
                        onChanged: (value) async {
                          if (value == null || value == selectedRoomName || widget.connectRoomClient == null) {
                            return;
                          }

                          setDialogState(() {
                            resolvingRoom = true;
                            resolveError = false;
                          });

                          RoomClient? nextRoomClient;
                          if (value == currentRoomName) {
                            nextRoomClient = room;
                          } else {
                            try {
                              nextRoomClient = await widget.connectRoomClient!(value);
                            } catch (_) {}
                          }

                          if (nextRoomClient == null) {
                            setDialogState(() {
                              resolvingRoom = false;
                              resolveError = true;
                            });
                          } else {
                            if (!identical(room, selectedRoomClient) && !identical(nextRoomClient, selectedRoomClient)) {
                              selectedRoomClient.dispose();
                            }

                            setDialogState(() {
                              selectedRoomName = value;
                              selectedRoomClient = nextRoomClient!;
                              picked = [];
                              resolvingRoom = false;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                Expanded(
                  child: ShadCard(
                    child: resolvingRoom
                        ? const Center(child: CircularProgressIndicator())
                        : resolveError
                        ? const Center(child: Text("Room failed to connect"))
                        : FileBrowser(
                            key: ValueKey(selectedRoomName),
                            onSelectionChanged: (selection) {
                              picked = selection;
                            },
                            room: selectedRoomClient,
                            multiple: true,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final f in picked) {
      if (identical(selectedRoomClient, room)) {
        widget.controller.attachFile(f);
      } else {
        final importedPath = await _importFile(sourceRoom: selectedRoomClient, sourcePath: f);
        widget.controller.attachFile(importedPath);
      }
    }
  }

  Widget _buildAttachButton(BuildContext context) {
    final customItems = widget.menuItemsBuilder?.call(context, widget.controller, popoverController);
    final additionalItems = widget.additionalMenuItemsBuilder?.call(context, widget.controller, popoverController);
    final canUseRoomAttachments = widget.controller.room != null;
    final canUseInlineAttachments = _canUseInlineAttachments;
    final defaultItemCount = canUseRoomAttachments
        ? (kIsWeb ? 1 : 2) + 1
        : canUseInlineAttachments
        ? (_canUseInlinePhotoPicker ? 2 : 1)
        : 0;
    final attachMenuItemCount = (customItems?.length ?? defaultItemCount) + (additionalItems?.length ?? 0);
    final showMcpMenuItem = _canShowMcpConnectors;
    final attachMenuHeight = (attachMenuItemCount + (showMcpMenuItem ? 1 : 0)) * 40.0;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => ListenableBuilder(
        listenable: popoverController,
        builder: (context, _) => CoordinatedShadContextMenu(
          constraints: const BoxConstraints(minWidth: 175),
          estimatedMenuWidth: 175,
          estimatedMenuHeight: attachMenuHeight,
          items: [
            if (customItems != null)
              ...customItems
            else if (canUseRoomAttachments || canUseInlineAttachments) ...[
              if (canUseRoomAttachments && !kIsWeb || canUseInlineAttachments && _canUseInlinePhotoPicker)
                ShadContextMenuItem(
                  leading: const Icon(LucideIcons.imageUp),
                  onPressed: _onSelectPhoto,
                  child: const Text("Upload a photo..."),
                ),
              ShadContextMenuItem(
                leading: const Icon(LucideIcons.paperclip),
                onPressed: _onSelectAttachment,
                child: const Text("Upload a file..."),
              ),
              if (canUseRoomAttachments)
                ShadContextMenuItem(
                  leading: const Icon(LucideIcons.download),
                  onPressed: _onBrowseFiles,
                  child: const Text("Add from room..."),
                ),
            ],
            ...?additionalItems,
            if (showMcpMenuItem)
              ShadContextMenuItem(
                leading: const Icon(LucideIcons.plug),
                trailing: widget.controller.isToolkitEnabled("mcp") ? const Icon(LucideIcons.check, size: 16) : null,
                onPressed: () {
                  widget.controller.toggleToolkit("mcp");
                },
                child: const Text("MCP"),
              ),
          ],
          controller: popoverController,
          child: ShadIconButton.ghost(
            hoverBackgroundColor: ShadTheme.of(context).colorScheme.background,
            decoration: const ShadDecoration(shape: BoxShape.circle),
            onPressed: popoverController.toggle,
            iconSize: 16,
            width: 32,
            height: 32,
            icon: const Icon(LucideIcons.plus),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    popoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canShowAttachmentMenu =
        widget.menuItemsBuilder != null ||
        widget.additionalMenuItemsBuilder != null ||
        widget.controller.room != null ||
        _canUseInlineAttachments;
    final showAttachFiles = widget.alwaysShowAttachFiles != false && canShowAttachmentMenu;

    if (!showAttachFiles && !_canShowMcpConnectors) {
      return const SizedBox(width: 0, height: 22);
    }

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final showMcpConnectors = _canShowMcpConnectors && widget.controller.isToolkitEnabled("mcp");
        if (!showAttachFiles && !showMcpConnectors) {
          return const SizedBox(width: 0, height: 22);
        }

        return showAttachFiles ? _buildAttachButton(context) : const SizedBox(width: 0, height: 22);
      },
    );
  }
}

class ChatThreadMcpFooter extends StatefulWidget {
  const ChatThreadMcpFooter({
    required this.controller,
    super.key,
    required this.agentName,
    this.showMcpConnectors = false,
    this.availableConnectors,
    this.onConnectorSetup,
    this.onAddMcpConnector,
  });

  final ChatThreadController controller;
  final String? agentName;
  final bool showMcpConnectors;
  final Future<List<Connector>> Function()? availableConnectors;
  final Future<void> Function(Connector connector)? onConnectorSetup;
  final Future<void> Function()? onAddMcpConnector;

  @override
  State createState() => _ChatThreadMcpFooterState();
}

class _ChatThreadMcpFooterState extends State<ChatThreadMcpFooter> {
  final Map<String, bool> _connectedConnectors = <String, bool>{};
  final ShadPopoverController _connectorPopoverController = ShadPopoverController();
  int _connectorRefreshEpoch = 0;
  List<Connector> _availableConnectors = const <Connector>[];
  Object? _availableConnectorsError;
  bool _loadingAvailableConnectors = false;
  bool _loadingConnectorState = false;
  String? _connectingConnectorName;

  bool get _canShowMcpConnectors {
    final normalizedAgentName = widget.agentName?.trim();
    return widget.showMcpConnectors && normalizedAgentName != null && normalizedAgentName.isNotEmpty && widget.availableConnectors != null;
  }

  List<Connector> get _selectedConnectorList {
    return widget.controller.selectedMcpConnectors;
  }

  @override
  void initState() {
    super.initState();
    _connectorPopoverController.addListener(_onConnectorPopoverChanged);
  }

  @override
  void didUpdateWidget(covariant ChatThreadMcpFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.agentName != widget.agentName || oldWidget.controller.room != widget.controller.room) {
      widget.controller.clearMcpConnectorSelections(notify: false);
      _connectorRefreshEpoch++;
      _availableConnectors = const <Connector>[];
      _availableConnectorsError = null;
      _connectedConnectors.clear();
    }

    if (oldWidget.agentName != widget.agentName ||
        oldWidget.showMcpConnectors != widget.showMcpConnectors ||
        oldWidget.controller.room != widget.controller.room) {
      unawaited(_refreshConnectorState(loadAvailableConnectors: _connectorPopoverController.isOpen));
    }
  }

  void _onConnectorPopoverChanged() {
    if (_connectorPopoverController.isOpen) {
      unawaited(_refreshConnectorState(loadAvailableConnectors: true));
    }
  }

  Future<void> _refreshConnectorState({bool loadAvailableConnectors = false}) async {
    final refreshEpoch = ++_connectorRefreshEpoch;
    if (!_canShowMcpConnectors) {
      if (!mounted) {
        return;
      }
      setState(() {
        _availableConnectors = const <Connector>[];
        _availableConnectorsError = null;
        _loadingAvailableConnectors = false;
        _loadingConnectorState = false;
        _connectedConnectors.clear();
      });
      return;
    }

    List<Connector> connectors = _availableConnectors;
    if (loadAvailableConnectors || connectors.isEmpty) {
      final loader = widget.availableConnectors;
      if (loader == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _availableConnectors = const <Connector>[];
          _availableConnectorsError = null;
          _loadingAvailableConnectors = false;
          _loadingConnectorState = false;
          _connectedConnectors.clear();
        });
        return;
      }

      setState(() {
        _loadingAvailableConnectors = true;
        _availableConnectorsError = null;
      });

      try {
        connectors = await loader();
      } catch (error) {
        if (!mounted || refreshEpoch != _connectorRefreshEpoch) {
          return;
        }
        setState(() {
          _availableConnectors = const <Connector>[];
          _availableConnectorsError = error;
          _loadingAvailableConnectors = false;
          _loadingConnectorState = false;
          _connectedConnectors.clear();
        });
        return;
      }
    }

    setState(() {
      _loadingAvailableConnectors = loadAvailableConnectors;
      _loadingConnectorState = true;
    });

    final normalizedAgentName = widget.agentName!.trim();
    final room = widget.controller.room;
    if (room == null) {
      if (!mounted || refreshEpoch != _connectorRefreshEpoch) {
        return;
      }
      setState(() {
        _availableConnectors = connectors;
        _availableConnectorsError = null;
        _loadingAvailableConnectors = false;
        _loadingConnectorState = false;
        _connectedConnectors.clear();
      });
      return;
    }
    final statuses = await Future.wait(
      connectors.map((connector) async {
        try {
          final connected = await connector.isConnected(room, normalizedAgentName);
          return MapEntry(_connectorSelectionKey(connector), connected);
        } catch (_) {
          return MapEntry(_connectorSelectionKey(connector), false);
        }
      }),
    );

    if (!mounted || refreshEpoch != _connectorRefreshEpoch) {
      return;
    }

    setState(() {
      _availableConnectors = connectors;
      _availableConnectorsError = null;
      _loadingAvailableConnectors = false;
      _loadingConnectorState = false;
      _connectedConnectors
        ..clear()
        ..addEntries(statuses);
    });
  }

  Future<void> _connectConnector(Connector connector) async {
    final onConnectorSetup = widget.onConnectorSetup;
    if (onConnectorSetup == null || _connectingConnectorName != null) {
      return;
    }

    _connectorPopoverController.hide();
    setState(() {
      _connectingConnectorName = connector.name;
    });

    try {
      await onConnectorSetup(connector);
      widget.controller.setMcpConnectorSelected(connector, true);
    } catch (error) {
      if (mounted) {
        ShadToaster.of(
          context,
        ).show(ShadToast.destructive(title: Text("Unable to connect ${connector.name}"), description: Text("$error")));
      }
    } finally {
      if (mounted) {
        setState(() {
          _connectingConnectorName = null;
        });
      }
      await _refreshConnectorState();
    }
  }

  Future<void> _toggleConnectorSelection(Connector connector) async {
    if (widget.controller.isMcpConnectorSelected(connector)) {
      widget.controller.setMcpConnectorSelected(connector, false);
      return;
    }

    final connectorKey = _connectorSelectionKey(connector);
    final isConnected = _connectedConnectors[connectorKey] == true;
    final connectorRef = Connector.buildConnectorRef(server: connector.server, oauth: connector.oauth);
    final requiresSetup = connectorRef != null || connector.oauth != null;
    if (isConnected || !requiresSetup) {
      widget.controller.setMcpConnectorSelected(connector, true);
      return;
    }

    await _connectConnector(connector);
  }

  Future<void> _addMcpConnector() async {
    final onAddMcpConnector = widget.onAddMcpConnector;
    if (onAddMcpConnector == null) {
      return;
    }

    _connectorPopoverController.hide();
    try {
      await onAddMcpConnector();
    } finally {
      await _refreshConnectorState(loadAvailableConnectors: true);
    }
  }

  Widget _buildMcpConnectorControl(BuildContext context) {
    final selectedConnectors = _selectedConnectorList;
    final isLoading = _loadingAvailableConnectors || _loadingConnectorState;
    final estimatedMenuHeight = math.max(48.0, (_availableConnectors.length + (widget.onAddMcpConnector != null ? 1 : 0)) * 40.0);
    final menuItems = <Widget>[
      if (_loadingAvailableConnectors && _availableConnectors.isEmpty) const ShadContextMenuItem(child: Text("Loading connectors...")),
      if (!_loadingAvailableConnectors && _availableConnectorsError != null)
        ShadContextMenuItem(
          leading: const Icon(LucideIcons.refreshCw),
          onPressed: () => _refreshConnectorState(loadAvailableConnectors: true),
          child: const Text("Unable to load connectors"),
        ),
      if (!_loadingAvailableConnectors && _availableConnectorsError == null && _availableConnectors.isEmpty)
        const ShadContextMenuItem(child: Text("No connectors are configured for this room")),
      for (final connector in _availableConnectors)
        Builder(
          builder: (context) {
            final connectorKey = _connectorSelectionKey(connector);
            final selected = widget.controller.isMcpConnectorSelected(connector);
            final isConnected = _connectedConnectors[connectorKey] == true;
            final connectorRef = Connector.buildConnectorRef(server: connector.server, oauth: connector.oauth);
            final requiresSetup = connectorRef != null || connector.oauth != null;

            Widget? trailing;
            if (_connectingConnectorName == connector.name) {
              trailing = const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2));
            } else if (selected) {
              trailing = const Icon(LucideIcons.check, size: 16);
            } else if (isConnected || !requiresSetup) {
              trailing = Text(
                "Connected",
                style: ShadTheme.of(context).textTheme.small.copyWith(color: ShadTheme.of(context).colorScheme.mutedForeground),
              );
            } else {
              trailing = Text(
                "Connect",
                style: ShadTheme.of(context).textTheme.small.copyWith(color: ShadTheme.of(context).colorScheme.mutedForeground),
              );
            }

            return ShadContextMenuItem(
              enabled: _connectingConnectorName == null,
              trailing: trailing,
              onPressed: () => _toggleConnectorSelection(connector),
              child: Text(connector.name),
            );
          },
        ),
      if (widget.onAddMcpConnector != null) const ShadSeparator.horizontal(margin: EdgeInsets.symmetric(vertical: 3)),
      if (widget.onAddMcpConnector != null)
        ShadContextMenuItem(
          leading: const Icon(LucideIcons.plus),
          enabled: _connectingConnectorName == null,
          onPressed: _addMcpConnector,
          child: const Text("Add..."),
        ),
    ];

    return ListenableBuilder(
      listenable: _connectorPopoverController,
      builder: (context, _) => CoordinatedShadContextMenu(
        constraints: const BoxConstraints(minWidth: 220),
        estimatedMenuWidth: 220,
        estimatedMenuHeight: estimatedMenuHeight,
        items: menuItems,
        controller: _connectorPopoverController,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _connectingConnectorName == null ? _connectorPopoverController.toggle : null,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              ShadBadge.outline(child: const Text("MCP")),
              for (final connector in selectedConnectors.take(4)) ShadBadge(child: Text(connector.name)),
              if (selectedConnectors.length > 4) ShadBadge(child: Text("+${selectedConnectors.length - 4}")),
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  "Add",
                  style: ShadTheme.of(context).textTheme.small.copyWith(color: ShadTheme.of(context).colorScheme.foreground),
                ),
              ),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.only(left: 2),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _connectorPopoverController.removeListener(_onConnectorPopoverChanged);
    _connectorPopoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showMcpConnectors = _canShowMcpConnectors && widget.controller.isToolkitEnabled("mcp");
    if (!showMcpConnectors) {
      return const SizedBox.shrink();
    }

    return Align(alignment: Alignment.centerLeft, child: _buildMcpConnectorControl(context));
  }
}

double _audioLevelFromPcm16(Uint8List chunk) {
  if (chunk.length < 2) {
    return 0;
  }
  var total = 0.0;
  var samples = 0;
  final data = ByteData.sublistView(chunk);
  for (var offset = 0; offset + 1 < chunk.length; offset += 2) {
    final sample = data.getInt16(offset, Endian.little) / 32768.0;
    total += sample * sample;
    samples += 1;
  }
  if (samples == 0) {
    return 0;
  }
  return math.sqrt(total / samples).clamp(0.0, 1.0);
}

int _audioWaveformBarCountForWidth(double width) {
  if (width <= 0) {
    return _audioWaveformMinBars;
  }
  return math.max(_audioWaveformMinBars, (width / (_audioWaveformBarWidth + _audioWaveformBarGap)).floor());
}

class _AudioWaveformPainter extends CustomPainter {
  const _AudioWaveformPainter({required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _audioWaveformBarWidth;
    final count = _audioWaveformBarCountForWidth(size.width);
    final gap = count <= 1 ? 0.0 : math.max(0.0, (size.width - (_audioWaveformBarWidth * count)) / (count - 1));
    for (var index = 0; index < count; index += 1) {
      final levelIndex = levels.length - count + index;
      final hasLevel = levelIndex >= 0;
      final rawLevel = hasLevel ? levels[levelIndex].clamp(0.0, 1.0) : 0.0;
      final active = rawLevel > 0.005;
      final level = active ? math.sqrt(rawLevel) * 0.9 : 0.0;
      final height = active ? math.max(4.0, size.height * level) : 1.0;
      paint.color = color.withValues(alpha: active ? 0.66 : 0.24);
      final x = (_audioWaveformBarWidth / 2) + (index * (_audioWaveformBarWidth + gap));
      canvas.drawLine(Offset(x, (size.height - height) / 2), Offset(x, (size.height + height) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AudioWaveformPainter oldDelegate) =>
      oldDelegate.color != color || !const ListEquality<double>().equals(oldDelegate.levels, levels);
}

class ChatThreadInput extends StatefulWidget {
  const ChatThreadInput({
    super.key,
    required this.onSend,
    required this.controller,
    this.room,
    this.autoFocus = true,
    this.focusTrigger,
    this.sendEnabled = true,
    this.sendDisabledReason,
    this.readOnly = false,
    this.clearOnSend = true,
    this.placeholder,
    this.onChanged,
    this.attachmentBuilder,
    this.onAttachmentOpen,
    this.onAttachmentRemoved,
    this.onFileDrop,
    this.leading,
    this.trailing,
    this.header,
    this.footer,
    this.audioInputEnabled = false,
    this.automaticAudioTurnDetection = false,
    this.onAudioRecordingStart,
    this.onExternalAudioRecordingStart,
    this.onExternalAudioRecordingStop,
    this.onAudioChunk,
    this.onClear,
    this.onInterrupt,
    this.onCancelSend,
    this.sendPendingText,
    this.contextMenuBuilder,
    this.onPressedOutside,
    this.tapRegionGroupId,
  });

  final Widget? placeholder;
  final bool autoFocus;
  final Object? focusTrigger;
  final bool sendEnabled;
  final String? sendDisabledReason;
  final bool readOnly;
  final bool clearOnSend;

  final RoomClient? room;
  final Future<void> Function(String, List<FileAttachment>) onSend;
  final void Function(String, List<FileAttachment>)? onChanged;
  final void Function()? onClear;
  final void Function()? onInterrupt;
  final void Function()? onCancelSend;
  final String? sendPendingText;
  final ChatThreadController controller;
  final Widget Function(BuildContext context, FileAttachment upload)? attachmentBuilder;
  final ValueChanged<FileAttachment>? onAttachmentOpen;
  final ValueChanged<FileAttachment>? onAttachmentRemoved;
  final Future<void> Function(String name, Stream<Uint8List> dataStream, int size)? onFileDrop;
  final Widget? leading;
  final Widget? trailing;
  final Widget? header;
  final Widget? footer;
  final bool audioInputEnabled;
  final bool automaticAudioTurnDetection;
  final Future<void> Function()? onAudioRecordingStart;
  final Future<void> Function()? onExternalAudioRecordingStart;
  final Future<void> Function()? onExternalAudioRecordingStop;
  final Future<void> Function(Uint8List chunk, {required bool finalChunk})? onAudioChunk;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final TapRegionCallback? onPressedOutside;
  final Object? tapRegionGroupId;
  @override
  State createState() => _ChatThreadInput();
}

class _ChatThreadInput extends State<ChatThreadInput> {
  bool showSendButton = false;
  bool allAttachmentsUploaded = true;
  bool sending = false;
  bool recordingAudio = false;
  bool stoppingAudio = false;
  int composerLineCount = 1;

  String text = "";
  List<FileAttachment> attachments = [];
  AudioRecorder? _audioRecorder;
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  Timer? _audioFlushTimer;
  final BytesBuilder _audioBuffer = BytesBuilder(copy: false);
  Future<void> _audioFlushTail = Future<void>.value();
  Future<void> _audioSendTail = Future<void>.value();
  int _submittedAudioByteCount = 0;
  bool _sentAudibleAudioThisRecording = false;
  final List<double> _audioLevels = [];
  int _audioLevelCapacity = _audioWaveformMinBars;

  void _syncDraftStateFromController({bool triggerExternalOnChanged = false}) {
    final nextText = widget.controller.text;
    final nextAttachments = widget.controller.attachmentUploads;
    final nextAllAttachmentsUploaded =
        nextAttachments.isEmpty || nextAttachments.every((upload) => upload.status == UploadStatus.completed);
    final nextShowSendButton = nextText.isNotEmpty || nextAttachments.isNotEmpty;

    text = nextText;
    attachments = nextAttachments;
    allAttachmentsUploaded = nextAllAttachmentsUploaded;
    showSendButton = nextShowSendButton;

    if (triggerExternalOnChanged) {
      widget.onChanged?.call(text, attachments);
    }
  }

  void _showSendDisabledToast() {
    if (!mounted) {
      return;
    }

    final description = widget.sendDisabledReason?.trim();
    ShadToaster.of(context).show(
      ShadToast.destructive(
        title: const Text("Unable to send message"),
        description: Text(
          description != null && description.isNotEmpty
              ? description
              : "Wait for the current turn to start before sending another message.",
        ),
      ),
    );
  }

  Future<void> _handleSend() async {
    if (sending) {
      return;
    }

    if (widget.readOnly) {
      return;
    }

    if (!widget.sendEnabled) {
      _showSendDisabledToast();
      return;
    }

    final draftText = widget.controller.text;
    final draftAttachments = widget.controller.attachmentUploads;
    setState(() {
      sending = true;
    });
    final sendFuture = widget.onSend(draftText, draftAttachments);
    if (widget.clearOnSend) {
      widget.controller.clear();
    }
    widget.controller.scrollThreadToBottom();
    _restoreComposerFocus();

    try {
      await sendFuture;
    } on ChatSendCancelledException {
      if (!mounted) {
        return;
      }

      if (widget.controller.textFieldController.text.isEmpty && widget.controller.attachmentUploads.isEmpty) {
        widget.controller.textFieldController.text = draftText;
        for (final attachment in draftAttachments) {
          if (attachment.status == UploadStatus.completed) {
            widget.controller.attachFile(attachment.path);
          }
        }
      }
      _restoreComposerFocus();
    } catch (error) {
      if (!mounted) {
        return;
      }

      if (widget.controller.textFieldController.text.isEmpty && widget.controller.attachmentUploads.isEmpty) {
        widget.controller.textFieldController.text = draftText;
        for (final attachment in draftAttachments) {
          if (attachment.status == UploadStatus.completed) {
            widget.controller.attachFile(attachment.path);
          }
        }
      }

      ShadToaster.of(context).show(ShadToast.destructive(title: const Text("Unable to send message"), description: Text("$error")));
      _restoreComposerFocus();
    } finally {
      if (mounted) {
        setState(() {
          sending = false;
        });
      }
      _restoreComposerFocus();
    }
  }

  Future<void> _handleSendAction() async {
    if (recordingAudio) {
      await _stopAudioRecording(submit: true);
      _resetAudioDraft();
      return;
    }
    await _handleSend();
    _resetAudioDraft();
  }

  void _resetAudioDraft() {
    if (_audioLevels.isEmpty) {
      return;
    }
    setState(() {
      _audioLevels.clear();
    });
  }

  void _syncAudioLevelCapacity(double width) {
    final nextCapacity = _audioWaveformBarCountForWidth(width);
    if (_audioLevelCapacity == nextCapacity) {
      return;
    }
    _audioLevelCapacity = nextCapacity;
    if (_audioLevels.length > _audioLevelCapacity) {
      _audioLevels.removeRange(0, _audioLevels.length - _audioLevelCapacity);
    }
  }

  void _appendAudioLevel(double level) {
    _audioLevels.add(level);
    if (_audioLevels.length > _audioLevelCapacity) {
      _audioLevels.removeRange(0, _audioLevels.length - _audioLevelCapacity);
    }
  }

  Future<void> _enqueueAudioChunk(Uint8List chunk, {required bool finalChunk}) {
    final onAudioChunk = widget.onAudioChunk;
    if (onAudioChunk == null) {
      return Future<void>.value();
    }
    final previousSend = _audioSendTail;
    final send = previousSend.then((_) => onAudioChunk(chunk, finalChunk: finalChunk));
    _audioSendTail = send.catchError((_) {});
    return send;
  }

  Future<void> _flushAudioBuffer() {
    final previousFlush = _audioFlushTail;
    final flush = previousFlush.then((_) => _flushAudioBufferNow());
    _audioFlushTail = flush.catchError((_) {});
    return flush;
  }

  Future<void> _flushAudioBufferNow() {
    if (_audioBuffer.isEmpty) {
      return Future<void>.value();
    }
    final chunk = _audioBuffer.takeBytes();
    _submittedAudioByteCount += chunk.length;
    return _enqueueAudioChunk(chunk, finalChunk: false);
  }

  Future<void> _startAudioRecording() async {
    if (recordingAudio || widget.readOnly || !widget.audioInputEnabled) {
      return;
    }
    final onExternalAudioRecordingStart = widget.onExternalAudioRecordingStart;
    if (widget.automaticAudioTurnDetection && onExternalAudioRecordingStart != null) {
      setState(() {
        _audioBuffer.clear();
        _submittedAudioByteCount = 0;
        _sentAudibleAudioThisRecording = false;
        _audioLevels.clear();
        recordingAudio = true;
        stoppingAudio = false;
      });
      try {
        await onExternalAudioRecordingStart();
      } catch (error) {
        if (mounted) {
          setState(() {
            recordingAudio = false;
            stoppingAudio = false;
          });
          ShadToaster.of(
            context,
          ).show(ShadToast.destructive(title: const Text("Unable to start audio thread"), description: Text("$error")));
        }
      }
      return;
    }
    final recorder = AudioRecorder();
    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      await recorder.dispose();
      if (!mounted) {
        return;
      }
      ShadToaster.of(context).show(const ShadToast.destructive(title: Text("Microphone access is required")));
      return;
    }
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _audioInputSampleRate,
        numChannels: _audioInputChannels,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    if (!mounted) {
      await recorder.stop();
      await recorder.dispose();
      return;
    }
    setState(() {
      _audioRecorder = recorder;
      _audioBuffer.clear();
      _submittedAudioByteCount = 0;
      _sentAudibleAudioThisRecording = false;
      _audioLevels.clear();
      recordingAudio = true;
      stoppingAudio = false;
    });
    final onAudioRecordingStart = widget.onAudioRecordingStart;
    if (widget.automaticAudioTurnDetection && onAudioRecordingStart != null) {
      unawaited(
        onAudioRecordingStart().catchError((Object error) {
          if (!mounted) {
            return;
          }
          ShadToaster.of(
            context,
          ).show(ShadToast.destructive(title: const Text("Unable to start audio thread"), description: Text("$error")));
        }),
      );
    }
    _audioFlushTimer?.cancel();
    if (!widget.automaticAudioTurnDetection) {
      _audioFlushTimer = Timer.periodic(_audioInputFlushInterval, (_) {
        unawaited(_flushAudioBuffer());
      });
    }
    _audioStreamSubscription = stream.listen(
      (chunk) {
        if (!mounted || chunk.isEmpty) {
          return;
        }
        final level = _audioLevelFromPcm16(chunk);
        if (widget.automaticAudioTurnDetection) {
          if (level >= _audioInputSilenceLevelThreshold) {
            _sentAudibleAudioThisRecording = true;
          }
          if (_sentAudibleAudioThisRecording) {
            _submittedAudioByteCount += chunk.length;
            unawaited(_enqueueAudioChunk(chunk, finalChunk: false));
          }
        } else {
          _audioBuffer.add(chunk);
          if (_audioBuffer.length >= _audioInputFlushBytes) {
            unawaited(_flushAudioBuffer());
          }
        }
        setState(() {
          _appendAudioLevel(level);
        });
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        setState(() {
          recordingAudio = false;
          stoppingAudio = false;
        });
        ShadToaster.of(context).show(ShadToast.destructive(title: const Text("Unable to record audio"), description: Text("$error")));
      },
    );
  }

  Future<void> _stopAudioRecording({required bool submit}) async {
    if (!recordingAudio || stoppingAudio) {
      return;
    }
    setState(() {
      stoppingAudio = true;
    });
    final recorder = _audioRecorder;
    _audioRecorder = null;
    _audioFlushTimer?.cancel();
    _audioFlushTimer = null;
    if (widget.automaticAudioTurnDetection && recorder == null && widget.onExternalAudioRecordingStop != null) {
      await widget.onExternalAudioRecordingStop!();
      if (!mounted) {
        return;
      }
      setState(() {
        recordingAudio = false;
        stoppingAudio = false;
      });
      _submittedAudioByteCount = 0;
      _sentAudibleAudioThisRecording = false;
      return;
    }
    if (recorder != null) {
      await recorder.stop();
    }
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    if (recorder != null) {
      await recorder.dispose();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      recordingAudio = false;
      stoppingAudio = false;
    });
    if (!submit) {
      _audioBuffer.clear();
      _submittedAudioByteCount = 0;
      _sentAudibleAudioThisRecording = false;
      return;
    }
    if (widget.automaticAudioTurnDetection) {
      await _audioSendTail;
    } else {
      await _flushAudioBuffer();
      await _audioFlushTail;
      await _audioSendTail;
      if (_submittedAudioByteCount < _minimumRealtimeAudioBytes) {
        _audioBuffer.clear();
        _submittedAudioByteCount = 0;
        return;
      }
    }
    await _enqueueAudioChunk(Uint8List(0), finalChunk: true);
    _submittedAudioByteCount = 0;
    _sentAudibleAudioThisRecording = false;
  }

  Future<void> _cancelAudioRecording() async {
    if (recordingAudio) {
      await _stopAudioRecording(submit: false);
    }
    _resetAudioDraft();
  }

  late final focusNode = FocusNode(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
        unawaited(_handleSendAction());

        return KeyEventResult.handled;
      }

      if (event is KeyDownEvent && event.character == "l" && HardwareKeyboard.instance.isControlPressed) {
        if (widget.onClear != null) {
          widget.onClear!();
        }
      }

      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        if (widget.onInterrupt != null) {
          widget.onInterrupt!();
          return KeyEventResult.handled;
        }
      }

      return KeyEventResult.ignored;
    },
  );

  Widget _wrapAccessoryTapRegion(Widget child) {
    return TextFieldTapRegion(
      groupId: widget.tapRegionGroupId ?? EditableText,
      child: Listener(behavior: HitTestBehavior.translucent, onPointerDown: (_) => _keepComposerFocusForAccessoryTap(), child: child),
    );
  }

  void _onTextChanged() {
    final newText = widget.controller.text;

    setState(() {
      text = newText;
    });

    widget.onChanged?.call(text, attachments);

    setShowSendButton();
  }

  void _onChanged() {
    final newAttachments = widget.controller.attachmentUploads;

    setState(() {
      attachments = newAttachments;
    });

    widget.onChanged?.call(text, attachments);

    setShowSendButton();

    bool allCompleted = true;
    if (attachments.isNotEmpty) {
      allCompleted = attachments.every((upload) => (upload.status == UploadStatus.completed));
    }
    if (allCompleted != allAttachmentsUploaded) {
      setState(() {
        allAttachmentsUploaded = allCompleted;
      });
    }
  }

  void setShowSendButton() {
    final value = text.isNotEmpty || attachments.isNotEmpty;

    if (showSendButton != value) {
      setState(() {
        showSendButton = value;
      });
    }
  }

  void _onComposerLineCountChanged(int value) {
    if (composerLineCount == value) {
      return;
    }

    setState(() {
      composerLineCount = value;
    });
  }

  void _scheduleAutoFocus() {
    if (!widget.autoFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.autoFocus || focusNode.hasFocus) {
        return;
      }
      focusNode.requestFocus();
    });
  }

  void _restoreComposerFocus() {
    if (!mounted || widget.readOnly) {
      return;
    }

    if (!focusNode.hasFocus) {
      focusNode.requestFocus();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.readOnly || focusNode.hasFocus) {
        return;
      }
      focusNode.requestFocus();
    });
  }

  void _keepComposerFocusForAccessoryTap() {
    _restoreComposerFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreComposerFocus();
    });
  }

  @override
  void initState() {
    super.initState();

    _syncDraftStateFromController();
    widget.controller.textFieldController.addListener(_onTextChanged);
    widget.controller.addListener(_onChanged);
    ClipboardEvents.instance?.registerPasteEventListener(onPasteEvent);
    _scheduleAutoFocus();
  }

  @override
  void didUpdateWidget(covariant ChatThreadInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      oldWidget.controller.textFieldController.removeListener(_onTextChanged);
      _syncDraftStateFromController();
      widget.controller.textFieldController.addListener(_onTextChanged);
      widget.controller.addListener(_onChanged);
    }
    if ((!oldWidget.autoFocus && widget.autoFocus) || oldWidget.focusTrigger != widget.focusTrigger) {
      _scheduleAutoFocus();
    }
    if (oldWidget.audioInputEnabled && !widget.audioInputEnabled && recordingAudio) {
      unawaited(_cancelAudioRecording());
    }
  }

  @override
  void dispose() {
    _audioFlushTimer?.cancel();
    _audioBuffer.clear();
    _submittedAudioByteCount = 0;
    _sentAudibleAudioThisRecording = false;
    if (recordingAudio && widget.automaticAudioTurnDetection && _audioRecorder == null) {
      final onExternalAudioRecordingStop = widget.onExternalAudioRecordingStop;
      if (onExternalAudioRecordingStop != null) {
        unawaited(onExternalAudioRecordingStop());
      }
    }
    unawaited(_audioStreamSubscription?.cancel());
    unawaited(_audioRecorder?.dispose());
    widget.controller.removeListener(_onChanged);
    widget.controller.textFieldController.removeListener(_onTextChanged);

    focusNode.dispose();
    ClipboardEvents.instance?.unregisterPasteEventListener(onPasteEvent);
    super.dispose();
  }

  Future<DataReaderFile> _getFile(DataReader reader, SimpleFileFormat? format) {
    final completer = Completer<DataReaderFile>();

    reader.getFile(format, completer.complete, onError: completer.completeError);

    return completer.future;
  }

  Future<void> onFileDrop(String name, Stream<Uint8List> dataStream, int size) async {
    if (widget.readOnly) {
      return;
    }
    final onFileDrop = widget.onFileDrop;
    if (onFileDrop != null) {
      await onFileDrop(name, dataStream, size);
      return;
    }
    if (widget.room == null) {
      return;
    }
    await widget.controller.uploadFile(name, dataStream, size);
  }

  void onPasteEvent(ClipboardReadEvent event) async {
    if (focusNode.hasFocus && !widget.readOnly) {
      final reader = await event.getClipboardReader();

      for (final item in reader.items) {
        final name = (await item.getSuggestedName());
        if (name != null) {
          final fmt = _preferredFormats.firstWhereOrNull((f) => item.canProvide(f));
          final file = await _getFile(item, fmt);

          await onFileDrop(name, file.getStream(), file.fileSize ?? 0);
        } else {
          if (item.canProvide(Formats.plainText)) {
            final text = await item.readValue(Formats.plainText);
            if (text != null) {
              onTextPaste(text);
            }
          }
        }
      }
    }
  }

  void onTextPaste(String text) async {
    if (widget.readOnly) {
      return;
    }
    final controller = widget.controller;

    final currentText = controller.textFieldController.text;
    final selection = controller.textFieldController.selection;

    // Get the text before and after the selection
    final textBefore = currentText.substring(0, selection.start);
    final textAfter = currentText.substring(selection.end);

    // Construct the new text
    final newText = textBefore + text + textAfter;

    // Calculate the new selection (cursor at the end of the inserted text)
    final newSelection = TextSelection.collapsed(offset: textBefore.length + text.length);

    // Update the controller's value
    controller.textFieldController.value = TextEditingValue(text: newText, selection: newSelection);
  }

  Widget _buildAudioRecorderComposer(BuildContext context, {required ShadThemeData theme, required Widget sendButton}) {
    final automaticMode = widget.automaticAudioTurnDetection;
    final leadingButton = automaticMode
        ? _wrapAccessoryTapRegion(
            ShadTooltip(
              waitDuration: const Duration(seconds: 1),
              builder: (context) => Text(recordingAudio ? "Mute microphone" : "Unmute microphone"),
              child: ShadGestureDetector(
                cursor: stoppingAudio ? SystemMouseCursors.basic : SystemMouseCursors.click,
                onTapDown: stoppingAudio
                    ? null
                    : (_) {
                        if (recordingAudio) {
                          unawaited(_stopAudioRecording(submit: false));
                        } else {
                          unawaited(_startAudioRecording());
                        }
                      },
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Icon(recordingAudio ? LucideIcons.mic : LucideIcons.micOff, size: 16, color: theme.colorScheme.foreground),
                  ),
                ),
              ),
            ),
          )
        : _wrapAccessoryTapRegion(
            ShadTooltip(
              waitDuration: const Duration(seconds: 1),
              builder: (context) => const Text("Cancel recording"),
              child: ShadGestureDetector(
                cursor: stoppingAudio ? SystemMouseCursors.basic : SystemMouseCursors.click,
                onTapDown: stoppingAudio ? null : (_) => unawaited(_cancelAudioRecording()),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(child: Icon(LucideIcons.square, size: 16, fill: 1, color: theme.colorScheme.foreground)),
                ),
              ),
            ),
          );
    final trailingButton = automaticMode
        ? _wrapAccessoryTapRegion(
            ShadTooltip(
              waitDuration: const Duration(seconds: 1),
              builder: (context) => const Text("Stop recording"),
              child: ShadGestureDetector(
                cursor: stoppingAudio ? SystemMouseCursors.basic : SystemMouseCursors.click,
                onTapDown: stoppingAudio
                    ? null
                    : (_) {
                        unawaited(() async {
                          widget.onInterrupt?.call();
                          await _stopAudioRecording(submit: true);
                          _resetAudioDraft();
                        }());
                      },
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(child: Icon(LucideIcons.square, size: 16, fill: 1, color: theme.colorScheme.foreground)),
                ),
              ),
            ),
          )
        : sendButton;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: theme.radius.resolve(Directionality.of(context)),
        border: Border.all(color: theme.colorScheme.border, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          leadingButton,
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _syncAudioLevelCapacity(constraints.maxWidth);
                return SizedBox(
                  height: 32,
                  child: CustomPaint(
                    painter: _AudioWaveformPainter(levels: List<double>.of(_audioLevels), color: theme.colorScheme.foreground),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          trailingButton,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    Widget wrapReadOnlyControls(Widget child) {
      if (!widget.readOnly) {
        return child;
      }

      return IgnorePointer(ignoring: true, child: Opacity(opacity: 0.6, child: child));
    }

    final cancelSendButton = _wrapAccessoryTapRegion(
      ShadTooltip(
        waitDuration: const Duration(seconds: 1),
        builder: (context) =>
            Text(widget.sendPendingText?.trim().isNotEmpty == true ? widget.sendPendingText!.trim() : "Waiting for agent to come online."),
        child: ShadGestureDetector(
          cursor: widget.onCancelSend == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
          onTapDown: widget.onCancelSend == null
              ? null
              : (_) {
                  _restoreComposerFocus();
                  widget.onCancelSend!();
                },
          child: Opacity(
            opacity: widget.onCancelSend == null ? 0.55 : 1,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Positioned.fill(
                    child: Padding(padding: EdgeInsets.all(1), child: _CyclingProgressIndicator(strokeWidth: 2)),
                  ),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.background),
                    child: Icon(LucideIcons.x, color: theme.colorScheme.foreground, size: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final sendButton = _wrapAccessoryTapRegion(
      ShadTooltip(
        waitDuration: const Duration(seconds: 1),
        builder: (context) => Text(
          widget.sendEnabled
              ? "Send"
              : (widget.sendDisabledReason?.trim().isNotEmpty ?? false)
              ? widget.sendDisabledReason!.trim()
              : "Wait for the current turn to start",
        ),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          descendantsAreFocusable: false,
          descendantsAreTraversable: false,
          child: ShadGestureDetector(
            cursor: widget.sendEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            onTapDown: (_) {
              _restoreComposerFocus();
            },
            onTap: widget.sendEnabled
                ? () {
                    unawaited(_handleSendAction());
                  }
                : null,
            child: Opacity(
              opacity: widget.sendEnabled ? 1 : 0.55,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.foreground),
                child: Center(child: Icon(LucideIcons.arrowUp, color: theme.colorScheme.background, size: 16)),
              ),
            ),
          ),
        ),
      ),
    );
    final micButton = widget.audioInputEnabled
        ? _wrapAccessoryTapRegion(
            ShadTooltip(
              waitDuration: const Duration(seconds: 1),
              builder: (context) => const Text("Record audio"),
              child: ShadGestureDetector(
                cursor: widget.readOnly ? SystemMouseCursors.basic : SystemMouseCursors.click,
                onTapDown: widget.readOnly ? null : (_) => unawaited(_startAudioRecording()),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(child: Icon(LucideIcons.mic, size: 16, color: theme.colorScheme.foreground)),
                ),
              ),
            ),
          )
        : null;
    const reservedControlSlot = SizedBox(width: 32, height: 32);
    final composerLeading = () {
      final controls = <Widget>[];
      if (widget.leading != null) {
        controls.add(_wrapAccessoryTapRegion(wrapReadOnlyControls(widget.leading!)));
      }
      if (controls.isEmpty) {
        return const SizedBox(width: 3);
      }
      return Row(mainAxisSize: MainAxisSize.min, children: controls);
    }();
    final primaryTrailer =
        widget.trailing ??
        (sending
            ? cancelSendButton
            : showSendButton && allAttachmentsUploaded
            ? sendButton
            : null);
    final trailer = () {
      final controls = <Widget>[];
      if (micButton != null && !sending) {
        controls.add(micButton);
      }
      if (primaryTrailer != null) {
        if (controls.isNotEmpty) {
          controls.add(const SizedBox(width: 4));
        }
        controls.add(primaryTrailer);
      } else {
        if (controls.isNotEmpty) {
          controls.add(const SizedBox(width: 4));
        }
        controls.add(
          const Visibility(visible: false, maintainState: true, maintainAnimation: true, maintainSize: true, child: reservedControlSlot),
        );
      }
      if (controls.length == 1) {
        return controls.single;
      }
      return Row(mainAxisSize: MainAxisSize.min, children: controls);
    }();
    final inputTrailer = widget.footer == null ? trailer : null;
    final reservedFooterTrailer = trailer;
    if (recordingAudio) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.header != null) widget.header!,
          _buildAudioRecorderComposer(context, theme: theme, sendButton: sendButton),
          if (widget.footer != null) Padding(padding: const EdgeInsets.only(top: 6), child: widget.footer!),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.header != null) widget.header!,
        EnableWebContextMenu(
          child: ShadInput(
            groupId: widget.tapRegionGroupId,
            contextMenuBuilder:
                widget.contextMenuBuilder ??
                (context, editableTextState) => AdaptiveTextSelectionToolbar.editableText(editableTextState: editableTextState),
            onPressedOutside: widget.onPressedOutside,
            top: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                if (attachments.isEmpty) {
                  return SizedBox.shrink();
                }

                return _wrapAccessoryTapRegion(
                  wrapReadOnlyControls(
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: LayoutBuilder(
                        builder: (context, constraints) => SizedBox(
                          height: 40,
                          child: Center(
                            child: ListView.separated(
                              itemCount: attachments.length,
                              separatorBuilder: (context, index) => const SizedBox(width: 10),
                              scrollDirection: Axis.horizontal,
                              itemBuilder: (context, index) {
                                final attachment = attachments[index];

                                if (widget.attachmentBuilder != null) {
                                  return widget.attachmentBuilder!(context, attachment);
                                }

                                return FileDefaultAttachmentPreview(
                                  key: ValueKey(attachment.path),
                                  attachment: attachment,
                                  maxWidth: constraints.maxWidth - 50,
                                  onOpen: widget.onAttachmentOpen == null ? null : () => widget.onAttachmentOpen!(attachment),
                                  onRemove: () {
                                    widget.controller.removeFileUpload(attachment);
                                    widget.onAttachmentRemoved?.call(attachment);
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            crossAxisAlignment: CrossAxisAlignment.center,
            inputPadding: EdgeInsets.all(2),
            leading: composerLeading,
            trailing: inputTrailer,
            padding: EdgeInsets.only(left: 5, right: 5, top: widget.footer == null ? 5 : 10, bottom: widget.footer == null ? 5 : 0),
            onLineCountChange: _onComposerLineCountChanged,
            decoration: (() {
              final theme = ShadTheme.of(context);
              final usesCompactMobileComposerShape = _usesMobileContextLayout(context) && attachments.isEmpty && composerLineCount <= 1;
              final composerRadius = _usesMobileContextLayout(context)
                  ? BorderRadius.circular(usesCompactMobileComposerShape ? _mobileComposerPillCornerRadius : _mobileComposerCornerRadius)
                  : theme.radius.resolve(Directionality.of(context));
              final composerBorder = ShadBorder.all(
                radius: composerRadius,
                color: theme.colorScheme.border,
                width: 2,
                padding: EdgeInsets.zero,
              );
              final focusedComposerBorder = ShadBorder.all(
                radius: composerRadius,
                color: theme.colorScheme.ring,
                width: 2,
                padding: EdgeInsets.zero,
              );
              return ShadDecoration(
                color: theme.colorScheme.card,
                border: composerBorder,
                focusedBorder: focusedComposerBorder,
                secondaryBorder: ShadBorder.none,
                secondaryFocusedBorder: ShadBorder.none,
                disableSecondaryBorder: true,
              );
            })(),
            maxLines: 8,
            minLines: 1,
            placeholder: widget.placeholder,
            focusNode: focusNode,
            controller: widget.controller.textFieldController,
            readOnly: widget.readOnly,
            bottom: widget.footer == null
                ? null
                : Padding(
                    padding: EdgeInsets.only(left: 5, right: 5, top: 5, bottom: 5),
                    child: Row(
                      children: [
                        Expanded(child: _wrapAccessoryTapRegion(wrapReadOnlyControls(widget.footer!))),
                        _wrapAccessoryTapRegion(reservedFooterTrailer),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class ChatThread extends StatefulWidget {
  const ChatThread({
    super.key,
    required this.path,
    required this.room,
    this.composerKey,
    this.participants,
    this.participantNames,
    this.includeLocalParticipant = true,

    this.startChatCentered = false,
    this.initialMessage,
    this.onMessageSent,
    this.controller,

    this.messageHeaderBuilder,
    this.waitingForParticipantsBuilder,
    this.attachmentBuilder,
    this.onAttachmentOpen,
    this.onAttachmentRemoved,
    this.fileInThreadBuilder,
    this.chatInputBoxBuilder,
    this.customInputBuilder,
    this.openFile,
    this.fileDropOverlayBuilder,
    this.toolsBuilder,
    this.inputPlaceholder,
    this.emptyStateTitle,
    this.emptyStateDescription,
    this.emptyState,

    this.agentName,
    this.onVisibleMessagesEmpty,
    this.initialShowCompletedToolCalls = false,
    this.shouldShowAuthorNames = true,
    this.showUsageFooter = false,
    this.inputContextMenuBuilder,
    this.inputOnPressedOutside,
    this.mobileStorageSaveSurfacePresenter,
    this.mobileUnderHeaderContentPadding,
  });

  final String? agentName;

  final String path;
  final RoomClient room;
  final GlobalKey? composerKey;
  final List<Participant>? participants;
  final List<String>? participantNames;
  final bool includeLocalParticipant;
  final bool startChatCentered;
  final ChatMessage? initialMessage;
  final void Function(ChatMessage message)? onMessageSent;
  final ChatThreadController? controller;
  final Widget? inputPlaceholder;
  final String? emptyStateTitle;
  final String? emptyStateDescription;
  final Widget? emptyState;
  final FutureOr<void> Function()? onVisibleMessagesEmpty;
  final bool initialShowCompletedToolCalls;
  final bool shouldShowAuthorNames;
  final bool showUsageFooter;

  final Widget Function(BuildContext, MeshDocument, MeshElement)? messageHeaderBuilder;
  final Widget Function(BuildContext, List<String>)? waitingForParticipantsBuilder;
  final Widget Function(BuildContext context, FileAttachment upload)? attachmentBuilder;
  final ValueChanged<FileAttachment>? onAttachmentOpen;
  final ValueChanged<FileAttachment>? onAttachmentRemoved;
  final Widget Function(BuildContext context, String path)? fileInThreadBuilder;
  final Widget Function(BuildContext context, Widget chatBox)? chatInputBoxBuilder;
  final ChatThreadCustomInputBuilder? customInputBuilder;
  final FutureOr<void> Function(String path)? openFile;
  final FileDropOverlayBuilder? fileDropOverlayBuilder;
  final Widget Function(BuildContext, ChatThreadController, ChatThreadSnapshot)? toolsBuilder;
  final EditableTextContextMenuBuilder? inputContextMenuBuilder;
  final TapRegionCallback? inputOnPressedOutside;
  final ThreadStorageSaveSurfacePresenter? mobileStorageSaveSurfacePresenter;
  final double? mobileUnderHeaderContentPadding;

  @override
  State createState() => _ChatThreadState();
}

class ChatBubble extends StatefulWidget {
  const ChatBubble({
    super.key,
    this.room,
    required this.mine,
    required this.text,
    this.onDelete,
    this.reactionActionBuilder,
    this.showReactionAction = false,
    this.onReactFromMenu,
    this.mobileStorageSaveSurfacePresenter,
    this.fullWidth = false,
    this.accented = false,
    this.backgroundColor,
    this.borderColor,
    this.textColor,
    this.selectable = true,
    this.showActionRail = true,
    this.onTap,
  });

  final RoomClient? room;
  final bool mine;
  final String text;
  final VoidCallback? onDelete;
  final Widget Function(ShadContextMenuController controller)? reactionActionBuilder;
  final bool showReactionAction;
  final VoidCallback? onReactFromMenu;
  final ThreadStorageSaveSurfacePresenter? mobileStorageSaveSurfacePresenter;
  final bool fullWidth;
  final bool accented;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? textColor;
  final bool selectable;
  final bool showActionRail;
  final VoidCallback? onTap;

  @override
  State createState() => _ChatBubble();
}

class _ChatBubble extends State<ChatBubble> {
  static const double _actionSlotSize = 30;
  static const double _actionGap = 6;
  static const double _bubbleRadius = 16;
  static const Duration _menuReverseDuration = Duration(milliseconds: 150);
  static ShadContextMenuController? _activeOptionsController;

  bool hovering = false;
  bool _keepingActionsVisible = false;
  Timer? _actionVisibilityTimer;

  final optionsController = ShadContextMenuController();
  final Object _contextMenuGroupId = Object();
  final reactionController = ShadContextMenuController();

  @override
  void initState() {
    super.initState();

    optionsController.addListener(_handleOptionsControllerChanged);
    reactionController.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _actionVisibilityTimer?.cancel();
    if (identical(_activeOptionsController, optionsController)) {
      _activeOptionsController = null;
    }
    optionsController.removeListener(_handleOptionsControllerChanged);
    reactionController.removeListener(_handleControllerChanged);
    optionsController.dispose();
    reactionController.dispose();
    super.dispose();
  }

  void _handleOptionsControllerChanged() {
    if (optionsController.isOpen) {
      final activeOptionsController = _activeOptionsController;
      if (!identical(activeOptionsController, optionsController)) {
        activeOptionsController?.hide();
        _activeOptionsController = optionsController;
      }
    } else if (identical(_activeOptionsController, optionsController)) {
      _activeOptionsController = null;
    }

    _handleControllerChanged();
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }

    _syncActionVisibilityForMenuState();
    setState(() {});
  }

  void _syncActionVisibilityForMenuState() {
    final menuOpen = optionsController.isOpen || reactionController.isOpen;
    if (menuOpen) {
      _actionVisibilityTimer?.cancel();
      _keepingActionsVisible = true;
      return;
    }

    if (hovering) {
      _actionVisibilityTimer?.cancel();
      return;
    }

    _scheduleActionVisibilityHide();
  }

  void _scheduleActionVisibilityHide() {
    _actionVisibilityTimer?.cancel();
    _actionVisibilityTimer = Timer(_menuReverseDuration, () {
      if (!mounted || hovering || optionsController.isOpen || reactionController.isOpen) {
        return;
      }

      setState(() {
        _keepingActionsVisible = false;
      });
    });
  }

  Future<void> _onCopy() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;

    final text = _visibleChatBubbleText(context, widget.text);
    final html = md.markdownToHtml(text, extensionSet: md.ExtensionSet.gitHubFlavored, inlineSyntaxes: const [], blockSyntaxes: const []);

    final reps = <raw.DataRepresentation>[
      raw.DataRepresentation.simple(format: "text/plain", data: text),
      raw.DataRepresentation.simple(format: "text/html", data: html),
    ];

    if (!kIsWeb) {
      reps.insertAll(0, [
        raw.DataRepresentation.simple(format: "public.utf8-plain-text", data: text),
        raw.DataRepresentation.simple(format: "public.plain-text", data: text),
        raw.DataRepresentation.simple(format: "public.html", data: html),
      ]);
    }

    await clipboard.write([DataWriterItem()..add(EncodedData(reps))]);
  }

  Future<void> _onSave(RoomClient room) async {
    await _showThreadStorageSaveSurface(
      context,
      room: room,
      title: "Save comment file as ...",
      suggestedFileName: "chat-comment.md",
      fileNameLabel: "Enter File Name",
      mobilePresenter: widget.mobileStorageSaveSurfacePresenter,
      loadContent: () async {
        final bytes = Uint8List.fromList(utf8.encode(widget.text));
        return FileContent(data: bytes, name: "chat-comment.md", mimeType: "text/markdown");
      },
    );
  }

  void _onDelete() {
    showShadDialog<void>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text("Delete Message"),
        description: Text("Are you sure you want to delete this message? This action cannot be undone."),
        actions: [
          ShadButton.secondary(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text("Cancel"),
          ),
          ShadButton(
            onPressed: () {
              widget.onDelete?.call();
              Navigator.of(context).pop();
            },
            child: Text("Delete"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final cs = theme.colorScheme;
    final text = _visibleChatBubbleText(context, widget.text);
    final mine = widget.mine;
    final bubbleColor = widget.backgroundColor ?? (widget.accented || mine ? cs.accent : cs.background);
    final bubbleBorderColor = widget.borderColor;
    final markdownLinkColor = mine
        ? ThreadTypographyOverride.maybeMineBubbleLinkColorOf(context) ?? ThreadTypographyOverride.maybeLinkColorOf(context)
        : ThreadTypographyOverride.maybeLinkColorOf(context);
    final showActions =
        widget.showActionRail && (hovering || optionsController.isOpen || reactionController.isOpen || _keepingActionsVisible);
    final canLongPressReact =
        (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) && widget.onReactFromMenu != null;
    final optionItemCount = 1 + (canLongPressReact ? 1 : 0) + (widget.room != null ? 1 : 0) + (widget.onDelete != null ? 1 : 0);

    final optionsAction = IgnorePointer(
      ignoring: !showActions,
      child: Opacity(
        opacity: showActions ? 1 : 0,
        child: Padding(
          padding: EdgeInsets.only(bottom: 5),
          child: CoordinatedShadContextMenu(
            controller: optionsController,
            groupId: _contextMenuGroupId,
            constraints: const BoxConstraints(minWidth: 200),
            estimatedMenuWidth: 200,
            estimatedMenuHeight: optionItemCount * 40.0 + 8.0,
            popoverReverseDuration: _menuReverseDuration,
            items: [
              ShadContextMenuItem(height: 40, onPressed: _onCopy, child: Text('Copy')),
              if (canLongPressReact) ShadContextMenuItem(height: 40, onPressed: widget.onReactFromMenu, child: Text('React')),
              if (widget.room != null)
                ShadContextMenuItem(
                  height: 40,
                  onPressed: () {
                    _onSave(widget.room!);
                  },
                  child: Text('Save as...'),
                ),
              if (widget.onDelete != null) ShadContextMenuItem(height: 40, onPressed: _onDelete, child: Text('Delete')),
            ],
            child: ShadButton.ghost(
              height: 30,
              width: 30,
              padding: EdgeInsets.zero,
              onPressed: optionsController.toggle,
              child: Icon(LucideIcons.ellipsis, size: 18, color: cs.mutedForeground),
            ),
          ),
        ),
      ),
    );

    final reactAction = SizedBox(
      width: _actionSlotSize,
      height: 35,
      child: IgnorePointer(
        ignoring: !(showActions && widget.showReactionAction),
        child: Opacity(
          opacity: showActions && widget.showReactionAction ? 1 : 0,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: widget.reactionActionBuilder?.call(reactionController) ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    final actions = Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (mine) ...[
            reactAction,
            const SizedBox(width: _actionGap),
            optionsAction,
          ] else ...[
            optionsAction,
            const SizedBox(width: _actionGap),
            reactAction,
          ],
        ],
      ),
    );

    final bubble = Container(
      padding: _resolvedChatBubbleContentPadding(context),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(_bubbleRadius),
        border: bubbleBorderColor == null ? null : Border.all(color: bubbleBorderColor),
      ),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
        child: MarkdownViewer(
          markdown: text,
          padding: const EdgeInsets.all(0),
          threadTypography: true,
          shrinkWrap: true,
          selectable: widget.selectable && kIsWeb,
          color: widget.textColor,
          linkColor: markdownLinkColor,
        ),
      ),
    );

    final content = widget.fullWidth
        ? widget.showActionRail
              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SizedBox(width: double.infinity, child: bubble),
                    Positioned(bottom: 0, right: 0, child: actions),
                  ],
                )
              : SizedBox(width: double.infinity, child: bubble)
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (mine && widget.showActionRail) actions,
              Expanded(child: bubble),
              if (!mine && widget.showActionRail) actions,
            ],
          );

    return TapRegion(
      groupId: _contextMenuGroupId,
      onTapOutside: (_) {
        if (widget.showActionRail) {
          optionsController.hide();
          reactionController.hide();
        }
      },
      child: ShadGestureDetector(
        onHoverChange: (h) {
          if (!widget.showActionRail) {
            return;
          }
          _actionVisibilityTimer?.cancel();
          setState(() {
            hovering = h;
            if (h) {
              _keepingActionsVisible = true;
            }
          });

          if (!h && !optionsController.isOpen && !reactionController.isOpen) {
            _scheduleActionVisibilityHide();
          }
        },
        onLongPress: widget.showActionRail ? optionsController.show : null,
        onTap: widget.onTap,
        cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 5),
          color: Colors.transparent,
          child: Container(margin: EdgeInsets.only(top: 0), child: content),
        ),
      ),
    );
  }
}

class ChatMessage {
  const ChatMessage({required this.id, required this.text, this.attachments = const []});

  final String id;
  final String text;
  final List<String> attachments;
}

class AgentUsageSnapshot {
  const AgentUsageSnapshot({
    required this.threadPath,
    required this.contextUsedTokens,
    required this.contextTotalTokens,
    required this.totalTokens,
    required this.usage,
    this.compactionMode,
    this.compactionThreshold,
    this.turnId,
  });

  final String threadPath;
  final String? turnId;
  final int contextUsedTokens;
  final int? contextTotalTokens;
  final String? compactionMode;
  final int? compactionThreshold;
  final double? totalTokens;
  final Map<String, double> usage;

  static AgentUsageSnapshot? fromPayload(Map<String, Object?> payload) {
    if (payload["type"] != agentUsageUpdatedType) {
      return null;
    }

    final rawThreadPath = payload["thread_id"];
    if (rawThreadPath is! String || rawThreadPath.trim().isEmpty) {
      return null;
    }

    final rawContextWindow = payload["context_window"];
    if (rawContextWindow is! Map) {
      return null;
    }

    final rawUsedTokens = rawContextWindow["used_tokens"];
    final usedTokens = _asInt(rawUsedTokens);
    if (usedTokens == null) {
      return null;
    }

    final rawTotalTokens = rawContextWindow["total_tokens"];
    final totalContextTokens = rawTotalTokens == null ? null : _asInt(rawTotalTokens);
    final rawCompactionMode = rawContextWindow["compaction_mode"];
    final compactionMode = rawCompactionMode is String && rawCompactionMode.trim().isNotEmpty ? rawCompactionMode.trim() : null;
    final rawCompactionThreshold = rawContextWindow["compaction_threshold"];
    final compactionThreshold = rawCompactionThreshold == null ? null : _asInt(rawCompactionThreshold);

    final totalTokens = _usageTotalTokens(payload["usage"]);
    final usage = _usageValues(payload["usage"]);

    final rawTurnId = payload["turn_id"];
    return AgentUsageSnapshot(
      threadPath: rawThreadPath.trim(),
      turnId: rawTurnId is String && rawTurnId.trim().isNotEmpty ? rawTurnId.trim() : null,
      contextUsedTokens: usedTokens,
      contextTotalTokens: totalContextTokens,
      compactionMode: compactionMode,
      compactionThreshold: compactionThreshold,
      totalTokens: totalTokens,
      usage: usage,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double && value.isFinite) {
      return value.toInt();
    }
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is int) {
      return value.toDouble();
    }
    if (value is double && value.isFinite) {
      return value;
    }
    return null;
  }

  static double? _usageTotalTokens(Object? rawUsage) {
    if (rawUsage is! Map) {
      return null;
    }

    final explicitTotal = _sumUsageKeys(rawUsage, const {"total_tokens"});
    if (explicitTotal != null) {
      return explicitTotal;
    }

    final inputTokens = _sumUsageKeys(rawUsage, const {
      "input_tokens",
      "audio_input_tokens",
      "image_input_tokens",
      "cache_creation_input_tokens",
      "cache_read_input_tokens",
    });
    final outputTokens = _sumUsageKeys(rawUsage, const {"output_tokens", "audio_output_tokens", "image_output_tokens"});
    final cachedTokens = _sumUsageKeys(rawUsage, const {"cached_tokens", "audio_cached_tokens", "image_cached_tokens"});
    final reasoningTokens = _sumUsageKeys(rawUsage, const {"reasoning_tokens"});

    var total = 0.0;
    var hasTotal = false;
    if (inputTokens != null) {
      total += inputTokens;
      hasTotal = true;
    } else if (cachedTokens != null) {
      total += cachedTokens;
      hasTotal = true;
    }
    if (outputTokens != null) {
      total += outputTokens;
      hasTotal = true;
    } else if (reasoningTokens != null) {
      total += reasoningTokens;
      hasTotal = true;
    }
    return hasTotal ? total : null;
  }

  static Map<String, double> _usageValues(Object? rawUsage) {
    if (rawUsage is! Map) {
      return const {};
    }
    final usage = <String, double>{};
    for (final entry in rawUsage.entries) {
      final key = entry.key;
      if (key is! String || key.trim().isEmpty) {
        continue;
      }
      final value = _asDouble(entry.value);
      if (value == null) {
        continue;
      }
      usage[key.trim()] = value;
    }
    return Map.unmodifiable(usage);
  }

  static double? _sumUsageKeys(Map rawUsage, Set<String> names) {
    var total = 0.0;
    var found = false;
    for (final entry in rawUsage.entries) {
      if (!_usageKeyMatches(entry.key, names)) {
        continue;
      }
      final numericValue = _asDouble(entry.value);
      if (numericValue == null) {
        continue;
      }
      total += numericValue;
      found = true;
    }
    return found ? total : null;
  }

  static bool _usageKeyMatches(Object? key, Set<String> names) {
    if (key is! String) {
      return false;
    }
    for (final name in names) {
      if (key == name || key.endsWith(".$name")) {
        return true;
      }
    }
    return false;
  }
}

bool shouldReplaceAgentUsageSnapshot(AgentUsageSnapshot? current, AgentUsageSnapshot next) {
  if (current != null && current.contextUsedTokens > 0 && next.contextUsedTokens == 0 && next.usage.isEmpty) {
    return false;
  }
  return true;
}

class _ChatThreadState extends State<ChatThread> {
  late final ChatThreadController controller;
  late Key _composerInputKey;
  late final Object _composerTapRegionGroupId = Object();
  bool _didNotifyVisibleMessagesEmpty = false;
  late bool _showCompletedToolCalls;
  MeshDocument? _managedDocument;
  Object? _documentError;
  int _documentGeneration = 0;
  bool _managesDocumentConnection = false;
  bool _initialMessageSent = false;

  MeshDocument? get _resolvedDocument => _managedDocument;

  bool _shouldStoreLocally({required bool hasConfiguredAgent, required bool useAgentMessages}) {
    return !hasConfiguredAgent && !useAgentMessages;
  }

  List<PendingAgentMessage> _combinedPendingMessages(ChatThreadSnapshot state) {
    final combined = <String, PendingAgentMessage>{};
    for (final message in controller.pendingAgentMessagesForPath(widget.path)) {
      combined[message.messageId] = message;
    }
    for (final message in state.pendingMessages) {
      combined[message.messageId] = message;
    }
    final values = combined.values
        .where(
          (pending) =>
              pending.awaitingApplication ||
              !state.messages.any(
                (message) =>
                    _shouldRenderThreadMessageElement(message, showCompletedToolCalls: _showCompletedToolCalls) &&
                    _threadMessageMatchesPendingAgentMessage(message, pending),
              ),
        )
        .toList();
    return [...values.where((message) => !message.awaitingAcceptance), ...values.where((message) => message.awaitingAcceptance)];
  }

  bool _isWaitingForTurnStart({required ChatThreadSnapshot state, required List<PendingAgentMessage> pendingMessages}) {
    if (!state.supportsAgentMessages || state.threadTurnId != null) {
      return false;
    }

    return pendingMessages.any((message) => message.messageType == agentTurnStartType);
  }

  bool _canInterruptActiveTurn({required ChatThreadSnapshot state, required List<PendingAgentMessage> pendingMessages}) {
    return state.supportsAgentMessages && state.threadTurnId != null && pendingMessages.isNotEmpty;
  }

  void _ensureParticipants(MeshDocument document) {
    final participantsList = <Participant>[
      if (widget.participants != null) ...widget.participants!,
      if (widget.includeLocalParticipant && widget.room.localParticipant != null) widget.room.localParticipant!,
    ];

    if (widget.participants == null && widget.participantNames == null) {
      return;
    }

    final existing = <String>{};
    for (final child in document.root.getChildren().whereType<MeshElement>()) {
      if (child.tagName != "members") {
        continue;
      }

      for (final member in child.getChildren().whereType<MeshElement>()) {
        final name = member.getAttribute("name");
        if (name is String && name.isNotEmpty) {
          existing.add(name);
        }
      }

      for (final participant in participantsList) {
        final name = participant.getAttribute("name");
        if (name is String && name.isNotEmpty && !existing.contains(name)) {
          child.createChildElement("member", {"name": name});
          existing.add(name);
        }
      }

      if (widget.participantNames != null) {
        for (final participantName in widget.participantNames!) {
          if (!existing.contains(participantName)) {
            child.createChildElement("member", {"name": participantName});
            existing.add(participantName);
          }
        }
      }
    }
  }

  Future<void> _closeManagedDocument({required RoomClient room, required String path}) async {
    try {
      await room.sync.close(path);
    } catch (_) {}
  }

  Future<void> _syncManagedDocument({required int generation, required RoomClient room, required String path}) async {
    var nextRetryCount = 0;

    while (generation == _documentGeneration) {
      try {
        final document = await room.sync.open(path);

        if (!mounted || generation != _documentGeneration) {
          await _closeManagedDocument(room: room, path: path);
          return;
        }

        setState(() {
          _managedDocument = document;
          _documentError = null;
        });
        _maybeSendInitialMessage();
        return;
      } catch (error) {
        if (!mounted || generation != _documentGeneration) {
          return;
        }

        setState(() {
          _managedDocument = null;
          _documentError = error;
        });

        final delay = math.min(60000, math.pow(2, nextRetryCount).toInt() * 500);
        nextRetryCount++;
        await Future.delayed(Duration(milliseconds: delay));

        if (!mounted || generation != _documentGeneration) {
          return;
        }
      }
    }
  }

  void _startManagedSync() {
    final generation = ++_documentGeneration;
    _managesDocumentConnection = true;
    unawaited(_syncManagedDocument(generation: generation, room: widget.room, path: widget.path));
  }

  void _configureDocumentSource() {
    _documentError = null;
    _managedDocument = null;
    _startManagedSync();
  }

  void _maybeSendInitialMessage() {
    final initialMessage = widget.initialMessage;
    final document = _resolvedDocument;
    if (_initialMessageSent || initialMessage == null || document == null) {
      return;
    }

    _initialMessageSent = true;
    final normalizedAgentName = widget.agentName?.trim();
    final hasConfiguredAgent = normalizedAgentName != null && normalizedAgentName.isNotEmpty;
    final clientToolkits = controller.clientToolkitDescriptions;
    final useAgentMessages = hasConfiguredAgent
        ? controller.getAgentParticipants(document, participantName: normalizedAgentName).isNotEmpty
        : controller.getAgentParticipants(document).isNotEmpty;
    controller.send(
      thread: document,
      path: widget.path,
      message: initialMessage,
      remoteStoreParticipantName: hasConfiguredAgent ? normalizedAgentName : null,
      storeLocally: _shouldStoreLocally(hasConfiguredAgent: hasConfiguredAgent, useAgentMessages: useAgentMessages),
      useAgentMessages: useAgentMessages,
      clientToolkits: clientToolkits.isEmpty ? null : clientToolkits,
      onMessageSent: widget.onMessageSent,
    );
  }

  Future<void> _clearThread(MeshDocument document, ChatThreadSnapshot state) async {
    await controller.clearThread(widget.path, document, useAgentMessages: state.supportsAgentMessages, participantName: widget.agentName);
  }

  ChatThreadToolArea _buildToolArea(BuildContext context, ChatThreadSnapshot state) {
    return resolveChatThreadToolArea(widget.toolsBuilder == null ? null : widget.toolsBuilder!(context, controller, state));
  }

  ChatThreadSnapshot _buildLoadingSnapshot() {
    final agent = widget.room.messaging.remoteParticipants.firstWhereOrNull(
      (participant) => participant.getAttribute("name") == widget.agentName,
    );
    return ChatThreadSnapshot(
      messages: const [],
      online: agent == null ? const [] : [agent],
      offline: const [],
      typing: const [],
      listening: const [],
      agentOnline: agent != null,
      threadStatus: null,
      threadStatusStartedAt: null,
      threadStatusMode: null,
      threadStatusTotalBytes: null,
      threadStatusLinesAdded: null,
      threadStatusLinesRemoved: null,
      supportsAgentMessages: agent != null && _supportsAgentMessages(agent),
      supportsMcp: agent != null && _supportsMcp(agent),
      toolkits: const {},
      threadTurnId: null,
      pendingMessages: controller.pendingAgentMessagesForPath(widget.path),
      pendingItemId: null,
      usage: null,
    );
  }

  Future<TurnMcpConfig?> _buildMcpTurnConfig({required ChatThreadSnapshot state}) async {
    if (!state.supportsMcp || !controller.isToolkitEnabled("mcp")) {
      return null;
    }

    final servers = [for (final connector in controller.selectedMcpConnectors) connector.server.toJson()];
    if (servers.isEmpty) {
      return null;
    }
    return TurnMcpConfig(servers: servers);
  }

  Widget? _buildUsageFooter(BuildContext context, AgentUsageSnapshot? usage) {
    if (!widget.showUsageFooter) {
      return null;
    }

    final theme = ShadTheme.of(context);
    final label = usage == null ? "" : _formatUsageFooter(usage);
    final text = Text(
      label,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: theme.textTheme.small.copyWith(color: theme.colorScheme.mutedForeground, fontSize: 11),
    );
    if (usage == null) {
      return text;
    }
    return UsageFooterTooltip(
      tooltip: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Text(_formatUsageTooltip(usage), style: ShadTheme.of(context).textTheme.small),
      ),
      child: text,
    );
  }

  String _formatUsageFooter(AgentUsageSnapshot usage) {
    var contextLabel = _formatTokenCount(usage.contextUsedTokens);
    final contextLimitTokens = usage.compactionThreshold ?? usage.contextTotalTokens;
    if (contextLimitTokens != null) {
      contextLabel = "$contextLabel/${_formatTokenCount(contextLimitTokens)}";
    }
    return "context $contextLabel";
  }

  String _formatUsageTooltip(AgentUsageSnapshot usage) {
    final entries = usage.usage.entries.toList()..sort((left, right) => left.key.compareTo(right.key));
    final lines = <String>["context used: ${_formatTokenCount(usage.contextUsedTokens)}"];
    final compactionMode = usage.compactionMode;
    if (compactionMode != null) {
      lines.add("context management: $compactionMode");
      final threshold = usage.compactionThreshold;
      if (threshold != null) {
        lines.add("context threshold: ${_formatTokenCount(threshold)}");
      }
    }
    final contextTotalTokens = usage.contextTotalTokens;
    if (usage.compactionThreshold != null && contextTotalTokens != null) {
      lines.add("model window: ${_formatTokenCount(contextTotalTokens)}");
    }
    lines.addAll(entries.map((entry) => "${entry.key}: ${_formatTokenCount(entry.value)}"));
    return lines.join("\n");
  }

  String _formatTokenCount(num value) {
    final count = value.toDouble();
    final magnitude = count.abs();
    if (magnitude >= 1000000) {
      return "${_trimFixed(count / 1000000)}M";
    }
    if (magnitude >= 1000) {
      return "${_trimFixed(count / 1000)}K";
    }
    return count.round().toString();
  }

  String _trimFixed(double value) {
    final fixed = value.toStringAsFixed(1);
    if (fixed.endsWith(".0")) {
      return fixed.substring(0, fixed.length - 2);
    }
    return fixed;
  }

  Widget _buildComposerWithUsageFooter(BuildContext context, {required Widget input, required AgentUsageSnapshot? usage}) {
    final usageFooter = _buildUsageFooter(context, usage);
    if (usageFooter == null) {
      return input;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        input,
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 3, right: 8),
          child: Align(alignment: Alignment.centerRight, child: usageFooter),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();

    controller = widget.controller ?? ChatThreadController(room: widget.room);
    _composerInputKey = widget.composerKey ?? GlobalObjectKey(controller);
    _showCompletedToolCalls = widget.initialShowCompletedToolCalls;
    _configureDocumentSource();
    _maybeSendInitialMessage();
  }

  @override
  void dispose() {
    _documentGeneration++;
    if (_managesDocumentConnection) {
      unawaited(_closeManagedDocument(room: widget.room, path: widget.path));
    }
    if (widget.controller == null) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composerKey != widget.composerKey) {
      _composerInputKey = widget.composerKey ?? GlobalObjectKey(controller);
    }
    if (oldWidget.path != widget.path) {
      _didNotifyVisibleMessagesEmpty = false;
    }

    if (oldWidget.path == widget.path && oldWidget.room == widget.room) {
      if (oldWidget.initialMessage != widget.initialMessage) {
        _initialMessageSent = false;
        _maybeSendInitialMessage();
      }
      return;
    }

    final oldRoom = oldWidget.room;
    final oldPath = oldWidget.path;
    final shouldCloseOld = _managesDocumentConnection;
    _documentGeneration++;
    _initialMessageSent = false;

    setState(() {
      _managedDocument = null;
      _documentError = null;
      _managesDocumentConnection = false;
      _composerInputKey = widget.composerKey ?? GlobalObjectKey(controller);
      _configureDocumentSource();
    });

    if (shouldCloseOld) {
      unawaited(_closeManagedDocument(room: oldRoom, path: oldPath));
    }
    _maybeSendInitialMessage();
  }

  void _handleVisibleMessages(List<MeshElement> messages) {
    final onVisibleMessagesEmpty = widget.onVisibleMessagesEmpty;
    if (onVisibleMessagesEmpty == null) {
      return;
    }

    final hasVisibleMessages = messages.any(
      (message) => _shouldRenderThreadMessageElement(message, showCompletedToolCalls: _showCompletedToolCalls),
    );
    if (hasVisibleMessages) {
      _didNotifyVisibleMessagesEmpty = false;
      return;
    }

    if (_didNotifyVisibleMessagesEmpty) {
      return;
    }

    _didNotifyVisibleMessagesEmpty = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(Future.sync(onVisibleMessagesEmpty));
    });
  }

  Widget _buildInputChatBox(
    BuildContext context,
    MeshDocument document,
    List<PendingAgentMessage> pendingMessages,
    ChatThreadSnapshot state,
  ) {
    final waitingForTurnStart = _isWaitingForTurnStart(state: state, pendingMessages: pendingMessages);
    final waitingForOnlineMessage = pendingMessages.firstWhereOrNull((message) => message.awaitingOnline);
    final canInterruptActiveTurn = _canInterruptActiveTurn(state: state, pendingMessages: pendingMessages);
    final toolArea = _buildToolArea(context, state);
    final config = ChatThreadInputConfig(
      controller: controller,
      snapshot: state,
      placeholder: widget.inputPlaceholder,
      sendEnabled: !waitingForTurnStart,
      sendDisabledReason: waitingForTurnStart ? "Wait for the previous message to start before sending another one." : null,
      readOnly: false,
      onClear: () {
        _clearThread(document, state);
      },
      onInterrupt: canInterruptActiveTurn
          ? () {
              controller.cancel(
                widget.path,
                document,
                useAgentMessages: state.supportsAgentMessages,
                turnId: state.threadTurnId,
                participantName: widget.agentName,
              );
            }
          : null,
      onCancelSend: controller.hasPendingSendWait(widget.path)
          ? () {
              controller.cancelPendingSend(widget.path);
            }
          : null,
      sendPendingText: waitingForOnlineMessage == null
          ? null
          : "Waiting for ${_displayParticipantName(context, widget.agentName ?? "agent")} to come online.",
      leading: toolArea.leading,
      footer: toolArea.footer,
      room: widget.room,
      onSend: (value, attachments) async {
        final messageType = state.threadStatusMode == "steerable" && state.threadTurnId != null ? "steer" : "chat";
        final normalizedAgentName = widget.agentName?.trim();
        final hasConfiguredAgent = normalizedAgentName != null && normalizedAgentName.isNotEmpty;
        final mcp = await _buildMcpTurnConfig(state: state);
        final clientToolkits = controller.clientToolkitDescriptions;
        await controller.send(
          thread: document,
          path: widget.path,
          message: ChatMessage(id: const Uuid().v4(), text: value, attachments: attachments.map((x) => x.path).toList()),
          messageType: messageType,
          remoteStoreParticipantName: hasConfiguredAgent ? normalizedAgentName : null,
          storeLocally: _shouldStoreLocally(hasConfiguredAgent: hasConfiguredAgent, useAgentMessages: state.supportsAgentMessages),
          useAgentMessages: state.supportsAgentMessages,
          turnId: state.threadTurnId,
          mcp: mcp,
          clientToolkits: messageType == "steer" || clientToolkits.isEmpty ? null : clientToolkits,
          onMessageSent: widget.onMessageSent,
        );
      },
      onSendWithAgentText: (visibleText, agentText, attachments) async {
        final messageType = state.threadStatusMode == "steerable" && state.threadTurnId != null ? "steer" : "chat";
        final normalizedAgentName = widget.agentName?.trim();
        final hasConfiguredAgent = normalizedAgentName != null && normalizedAgentName.isNotEmpty;
        final mcp = await _buildMcpTurnConfig(state: state);
        final clientToolkits = controller.clientToolkitDescriptions;
        await controller.send(
          thread: document,
          path: widget.path,
          message: ChatMessage(id: const Uuid().v4(), text: visibleText, attachments: attachments.map((x) => x.path).toList()),
          messageType: messageType,
          remoteStoreParticipantName: hasConfiguredAgent ? normalizedAgentName : null,
          storeLocally: _shouldStoreLocally(hasConfiguredAgent: hasConfiguredAgent, useAgentMessages: state.supportsAgentMessages),
          useAgentMessages: state.supportsAgentMessages,
          turnId: state.threadTurnId,
          mcp: mcp,
          clientToolkits: messageType == "steer" || clientToolkits.isEmpty ? null : clientToolkits,
          remoteMessageText: agentText,
          onMessageSent: widget.onMessageSent,
        );
      },
      onChanged: (value, attachments) {
        for (final participant in controller.getOnlineParticipants(document)) {
          if (participant.id != widget.room.localParticipant?.id) {
            widget.room.messaging.sendMessage(to: participant, type: "typing", message: {"path": widget.path});
          }
        }
      },
      attachmentBuilder: widget.attachmentBuilder,
      onAttachmentOpen: widget.onAttachmentOpen,
      onAttachmentRemoved: widget.onAttachmentRemoved,
      contextMenuBuilder: widget.inputContextMenuBuilder,
      onPressedOutside: widget.inputOnPressedOutside,
      tapRegionGroupId: _composerTapRegionGroupId,
    );
    final defaultInput = ChatThreadInput(
      key: _composerInputKey,
      focusTrigger: controller,
      sendEnabled: config.sendEnabled,
      sendDisabledReason: config.sendDisabledReason,
      placeholder: config.placeholder,
      onClear: config.onClear,
      onInterrupt: config.onInterrupt,
      onCancelSend: config.onCancelSend,
      sendPendingText: config.sendPendingText,
      leading: config.leading,
      footer: config.footer,
      trailing: null,
      room: config.room,
      onSend: config.onSend,
      onChanged: config.onChanged,
      controller: config.controller,
      attachmentBuilder: config.attachmentBuilder,
      onAttachmentOpen: config.onAttachmentOpen,
      onAttachmentRemoved: config.onAttachmentRemoved,
      contextMenuBuilder: config.contextMenuBuilder,
      onPressedOutside: config.onPressedOutside,
      tapRegionGroupId: config.tapRegionGroupId,
    );
    return widget.customInputBuilder?.call(context, config, defaultInput) ?? defaultInput;
  }

  Widget _buildConnectingInputBox(BuildContext context) {
    final state = _buildLoadingSnapshot();
    final toolArea = _buildToolArea(context, state);
    final config = ChatThreadInputConfig(
      controller: controller,
      snapshot: state,
      placeholder: widget.inputPlaceholder,
      sendEnabled: false,
      sendDisabledReason: _documentError == null ? "Thread is loading." : "Thread is reconnecting.",
      readOnly: false,
      leading: toolArea.leading,
      footer: toolArea.footer,
      room: widget.room,
      onSend: (value, attachments) async {},
      attachmentBuilder: widget.attachmentBuilder,
      onAttachmentOpen: widget.onAttachmentOpen,
      onAttachmentRemoved: widget.onAttachmentRemoved,
      contextMenuBuilder: widget.inputContextMenuBuilder,
      onPressedOutside: widget.inputOnPressedOutside,
      tapRegionGroupId: _composerTapRegionGroupId,
    );
    final defaultInput = ChatThreadInput(
      key: _composerInputKey,
      focusTrigger: controller,
      sendEnabled: config.sendEnabled,
      sendDisabledReason: config.sendDisabledReason,
      readOnly: config.readOnly,
      placeholder: config.placeholder,
      leading: config.leading,
      footer: config.footer,
      trailing: null,
      room: config.room,
      onSend: config.onSend,
      controller: config.controller,
      attachmentBuilder: config.attachmentBuilder,
      onAttachmentOpen: config.onAttachmentOpen,
      onAttachmentRemoved: config.onAttachmentRemoved,
      contextMenuBuilder: config.contextMenuBuilder,
      onPressedOutside: config.onPressedOutside,
      tapRegionGroupId: config.tapRegionGroupId,
    );
    return widget.customInputBuilder?.call(context, config, defaultInput) ?? defaultInput;
  }

  Widget _buildResolvedThread(BuildContext context, MeshDocument document) {
    _ensureParticipants(document);

    return ChatThreadBuilder(
      path: widget.path,
      document: document,
      room: widget.room,
      controller: controller,
      agentName: widget.agentName,
      builder: (context, state) {
        if (state.offline.isNotEmpty && widget.waitingForParticipantsBuilder != null) {
          return widget.waitingForParticipantsBuilder!(context, state.offline.toList());
        }

        _handleVisibleMessages(state.messages);

        final hasVisibleMessages = state.messages.any(
          (message) => _shouldRenderThreadMessageElement(message, showCompletedToolCalls: _showCompletedToolCalls),
        );
        final bottomAlign = !widget.startChatCentered || hasVisibleMessages;

        return ShadContextMenuBoundary(
          child: FileDropArea(
            onFileDrop: (name, dataStream, size) async {
              controller.uploadFile(name, dataStream, size ?? 0);
            },
            overlayBuilder: widget.fileDropOverlayBuilder,
            child: Column(
              mainAxisAlignment: bottomAlign ? MainAxisAlignment.end : MainAxisAlignment.center,
              children: [
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    return ChatThreadMessages(
                      room: widget.room,
                      path: widget.path,
                      scrollController: controller.threadScrollController,
                      composerTapRegionGroupId: _composerTapRegionGroupId,
                      agentName: widget.agentName,
                      shouldShowAuthorNames: widget.shouldShowAuthorNames,
                      showCompletedToolCalls: _showCompletedToolCalls,
                      onShowCompletedToolCallsChanged: (value) {
                        setState(() {
                          _showCompletedToolCalls = value;
                        });
                      },
                      startChatCentered: widget.startChatCentered,
                      messages: state.messages,
                      online: state.online,
                      showTyping:
                          shouldShowChatThreadStatus(
                            ChatThreadStatusState(
                              text: state.threadStatus,
                              startedAt: state.threadStatusStartedAt,
                              mode: state.threadStatusMode,
                              totalBytes: state.threadStatusTotalBytes,
                              linesAdded: state.threadStatusLinesAdded,
                              linesRemoved: state.threadStatusLinesRemoved,
                            ),
                          ) &&
                          state.listening.isEmpty,
                      showListening: state.listening.isNotEmpty,
                      threadStatus: state.threadStatus,
                      threadStatusStartedAt: state.threadStatusStartedAt,
                      threadStatusMode: state.threadStatusMode,
                      threadStatusTotalBytes: state.threadStatusTotalBytes,
                      threadStatusLinesAdded: state.threadStatusLinesAdded,
                      threadStatusLinesRemoved: state.threadStatusLinesRemoved,
                      pendingMessages: _combinedPendingMessages(state),
                      pendingItemId: state.pendingItemId,
                      onCancel: () {
                        controller.cancel(
                          widget.path,
                          document,
                          useAgentMessages: state.supportsAgentMessages,
                          turnId: state.threadTurnId,
                          participantName: widget.agentName,
                        );
                      },
                      messageHeaderBuilder: widget.messageHeaderBuilder,
                      fileInThreadBuilder: widget.fileInThreadBuilder,
                      openFile: widget.openFile,
                      emptyStateTitle: widget.emptyStateTitle,
                      emptyStateDescription: widget.emptyStateDescription,
                      emptyState: widget.emptyState,
                      mobileStorageSaveSurfacePresenter: widget.mobileStorageSaveSurfacePresenter,
                      mobileUnderHeaderContentPadding: widget.mobileUnderHeaderContentPadding,
                    );
                  },
                ),
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final pendingMessages = _combinedPendingMessages(state);
                    final hasThreadStatus = state.threadStatus != null && state.threadStatus!.trim().isNotEmpty;
                    final queuedPendingMessages = hasThreadStatus
                        ? pendingMessages
                              .where(
                                (message) =>
                                    (message.messageType == agentTurnStartType || message.messageType == agentTurnSteerType) &&
                                    !_pendingAgentMessageIsOptimisticallyRendered(pending: message, messages: state.messages),
                              )
                              .toList(growable: false)
                        : const <PendingAgentMessage>[];
                    final canInterruptActiveTurn = _canInterruptActiveTurn(state: state, pendingMessages: pendingMessages);
                    return ChatThreadInputFrame(
                      hasFooter: widget.showUsageFooter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (queuedPendingMessages.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(width: 10),
                                  const SizedBox(width: 24, height: 24),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          "Pending messages:",
                                          style: threadTypographyTextStyle(
                                            context,
                                            TextStyle(fontSize: 13, color: ShadTheme.of(context).colorScheme.mutedForeground),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        for (final pending in queuedPendingMessages)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 4),
                                            child: Text(
                                              [
                                                if (pending.senderName != null) "${_displayParticipantName(context, pending.senderName!)}:",
                                                if (pending.text.trim().isNotEmpty) pending.text.trim(),
                                                if (pending.attachments.isNotEmpty)
                                                  "${pending.attachments.length} attachment${pending.attachments.length == 1 ? "" : "s"}",
                                                if (pending.awaitingOnline)
                                                  "(waiting for @${_displayParticipantName(context, widget.agentName ?? "agent")} to come online)",
                                              ].join(" "),
                                              style: threadTypographyTextStyle(
                                                context,
                                                TextStyle(fontSize: 13, color: ShadTheme.of(context).colorScheme.mutedForeground),
                                              ),
                                            ),
                                          ),
                                        if (canInterruptActiveTurn)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: _ProcessingStatusText(
                                              text: "Messages will be processed shortly. Press Esc to interrupt and send now.",
                                              style: threadTypographyTextStyle(
                                                context,
                                                TextStyle(fontSize: 13, color: ShadTheme.of(context).colorScheme.mutedForeground),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          _buildComposerWithUsageFooter(
                            context,
                            input: widget.chatInputBoxBuilder != null
                                ? widget.chatInputBoxBuilder!(context, _buildInputChatBox(context, document, pendingMessages, state))
                                : _buildInputChatBox(context, document, pendingMessages, state),
                            usage: state.usage,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingThreadWithoutDocument(BuildContext context, List<PendingAgentMessage> pendingMessages) {
    final state = _buildLoadingSnapshot();
    final input = widget.chatInputBoxBuilder != null
        ? widget.chatInputBoxBuilder!(context, _buildConnectingInputBox(context))
        : _buildConnectingInputBox(context);

    return ShadContextMenuBoundary(
      child: FileDropArea(
        onFileDrop: (name, dataStream, size) async {
          controller.uploadFile(name, dataStream, size ?? 0);
        },
        overlayBuilder: widget.fileDropOverlayBuilder,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ChatThreadMessages(
              room: widget.room,
              path: widget.path,
              scrollController: controller.threadScrollController,
              composerTapRegionGroupId: _composerTapRegionGroupId,
              agentName: widget.agentName,
              shouldShowAuthorNames: widget.shouldShowAuthorNames,
              showCompletedToolCalls: _showCompletedToolCalls,
              onShowCompletedToolCallsChanged: (value) {
                setState(() {
                  _showCompletedToolCalls = value;
                });
              },
              startChatCentered: widget.startChatCentered,
              messages: const [],
              online: _buildLoadingSnapshot().online,
              pendingMessages: pendingMessages,
              emptyStateTitle: widget.emptyStateTitle,
              emptyStateDescription: widget.emptyStateDescription,
              emptyState: widget.emptyState,
              fileInThreadBuilder: widget.fileInThreadBuilder,
              openFile: widget.openFile,
              mobileStorageSaveSurfacePresenter: widget.mobileStorageSaveSurfacePresenter,
              mobileUnderHeaderContentPadding: widget.mobileUnderHeaderContentPadding,
            ),
            ChatThreadInputFrame(
              hasFooter: widget.showUsageFooter,
              child: _buildComposerWithUsageFooter(context, input: input, usage: state.usage),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectingThread(BuildContext context) {
    final state = _buildLoadingSnapshot();
    final input = widget.chatInputBoxBuilder != null
        ? widget.chatInputBoxBuilder!(context, _buildConnectingInputBox(context))
        : _buildConnectingInputBox(context);

    return Column(
      children: [
        if (_documentError == null)
          const Expanded(child: SizedBox.shrink())
        else
          Expanded(
            child: Center(child: Text("Unable to load thread", style: ShadTheme.of(context).textTheme.p)),
          ),
        ChatThreadInputFrame(
          hasFooter: widget.showUsageFooter,
          child: _buildComposerWithUsageFooter(context, input: input, usage: state.usage),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = _resolvedDocument;
    if (document == null) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final pendingMessages = controller.pendingAgentMessagesForPath(widget.path);
          if (_documentError == null && pendingMessages.isNotEmpty) {
            return _buildPendingThreadWithoutDocument(context, pendingMessages);
          }
          return _buildConnectingThread(context);
        },
      );
    }

    return _buildResolvedThread(context, document);
  }
}

typedef MessageBuilder =
    Widget Function({
      Key? key,
      required RoomClient room,
      required MeshElement? previous,
      required MeshElement message,
      required MeshElement? next,
    });

class ChatThreadMessages extends StatefulWidget {
  const ChatThreadMessages({
    super.key,
    required this.room,
    required this.path,
    required this.scrollController,
    this.composerTapRegionGroupId,
    required this.messages,
    required this.online,
    required this.showCompletedToolCalls,
    this.shouldShowAuthorNames = true,

    this.startChatCentered = false,
    this.showTyping = false,
    this.showListening = false,
    this.threadStatus,
    this.threadStatusStartedAt,
    this.threadStatusMode,
    this.threadStatusTotalBytes,
    this.threadStatusLinesAdded,
    this.threadStatusLinesRemoved,
    this.pendingMessages = const [],
    this.pendingItemId,
    this.onCancel,
    this.agentName,
    this.messageHeaderBuilder,
    this.fileInThreadBuilder,
    this.openFile,
    this.messageBuilders,
    this.emptyStateTitle,
    this.emptyStateDescription,
    this.emptyState,
    this.onShowCompletedToolCallsChanged,
    this.mobileStorageSaveSurfacePresenter,
    this.mobileUnderHeaderContentPadding,
  });

  final Map<String, MessageBuilder>? messageBuilders;

  final RoomClient? room;
  final String path;
  final ScrollController scrollController;
  final Object? composerTapRegionGroupId;
  final String? agentName;
  final bool shouldShowAuthorNames;
  final bool showCompletedToolCalls;
  final bool startChatCentered;
  final bool showTyping;
  final bool showListening;
  final String? threadStatus;
  final DateTime? threadStatusStartedAt;
  final String? threadStatusMode;
  final int? threadStatusTotalBytes;
  final int? threadStatusLinesAdded;
  final int? threadStatusLinesRemoved;
  final List<PendingAgentMessage> pendingMessages;
  final String? pendingItemId;
  final void Function()? onCancel;
  final List<MeshElement> messages;
  final List<Participant> online;
  final String? emptyStateTitle;
  final String? emptyStateDescription;
  final Widget? emptyState;
  final ValueChanged<bool>? onShowCompletedToolCallsChanged;
  final ThreadStorageSaveSurfacePresenter? mobileStorageSaveSurfacePresenter;
  final double? mobileUnderHeaderContentPadding;

  final Widget Function(BuildContext, MeshDocument, MeshElement)? messageHeaderBuilder;
  final Widget Function(BuildContext context, String path)? fileInThreadBuilder;
  final FutureOr<void> Function(String path)? openFile;

  @override
  State<ChatThreadMessages> createState() => _ChatThreadMessagesState();
}

class ChatThreadMessageView extends StatelessWidget {
  const ChatThreadMessageView({
    super.key,
    this.room,
    required this.mine,
    required this.isAgentMessage,
    required this.text,
    required this.authorName,
    required this.createdAt,
    this.shouldShowHeader = true,
    this.header,
    this.attachmentWidgets = const [],
    this.trailing,
    this.onDelete,
    this.reactionActionBuilder,
    this.showReactionAction = false,
    this.onReactFromMenu,
    this.mobileStorageSaveSurfacePresenter,
    this.bubbleColor,
    this.bubbleBorderColor,
    this.useDefaultBubbleBorder = true,
    this.textColor,
    this.selectable = true,
    this.showBubbleActions = true,
    this.onTap,
  });

  static const double chatBubbleHorizontalInset = 5;
  static const double chatBubbleActionRailWidth = 80;
  static const double chatBubbleSiblingSpacing = 6;
  static const double chatMessageStackSpacing = 38;

  final RoomClient? room;
  final bool mine;
  final bool isAgentMessage;
  final String? text;
  final String authorName;
  final DateTime createdAt;
  final bool shouldShowHeader;
  final Widget? header;
  final List<Widget> attachmentWidgets;
  final Widget? trailing;
  final VoidCallback? onDelete;
  final Widget Function(ShadContextMenuController controller)? reactionActionBuilder;
  final bool showReactionAction;
  final VoidCallback? onReactFromMenu;
  final ThreadStorageSaveSurfacePresenter? mobileStorageSaveSurfacePresenter;
  final Color? bubbleColor;
  final Color? bubbleBorderColor;
  final bool useDefaultBubbleBorder;
  final Color? textColor;
  final bool selectable;
  final bool showBubbleActions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final messageText = text;
    final hasText = messageText != null && messageText.trim().isNotEmpty;
    final resolvedBubbleColor =
        bubbleColor ??
        (isAgentMessage
            ? ThreadTypographyOverride.maybeAgentBubbleColorOf(context)
            : mine
            ? ThreadTypographyOverride.maybeMineBubbleColorOf(context)
            : ThreadTypographyOverride.maybeOtherHumanBubbleColorOf(context));
    final resolvedTextColor =
        textColor ??
        (isAgentMessage
            ? null
            : mine
            ? ThreadTypographyOverride.maybeMineBubbleTextColorOf(context)
            : ThreadTypographyOverride.maybeOtherHumanBubbleTextColorOf(context));
    final resolvedBubbleBorderColor =
        bubbleBorderColor ??
        (useDefaultBubbleBorder && isAgentMessage ? ThreadTypographyOverride.maybeAgentBubbleBorderColorOf(context) : null);
    final headerLeftInset = mine ? chatBubbleHorizontalInset + chatBubbleActionRailWidth : chatBubbleHorizontalInset;
    final headerRightInset = mine || isAgentMessage || !showBubbleActions
        ? chatBubbleHorizontalInset
        : chatBubbleHorizontalInset + chatBubbleActionRailWidth;
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shouldShowHeader)
          Container(
            margin: EdgeInsets.only(left: headerLeftInset, right: headerRightInset, bottom: 6),
            child: Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: header ?? ChatThreadAuthorHeader(authorName: authorName, createdAt: createdAt, text: messageText),
            ),
          ),
        if (hasText)
          Padding(
            padding: const EdgeInsets.only(top: 0),
            child: ChatBubble(
              room: room,
              mine: mine,
              fullWidth: isAgentMessage,
              accented: !isAgentMessage,
              text: messageText,
              onDelete: onDelete,
              mobileStorageSaveSurfacePresenter: mobileStorageSaveSurfacePresenter,
              reactionActionBuilder: reactionActionBuilder,
              showReactionAction: showReactionAction,
              onReactFromMenu: onReactFromMenu,
              backgroundColor: resolvedBubbleColor,
              borderColor: resolvedBubbleBorderColor,
              textColor: resolvedTextColor,
              selectable: selectable,
              showActionRail: showBubbleActions,
              onTap: onTap,
            ),
          ),
        for (var i = 0; i < attachmentWidgets.length; i++) ...[
          if (hasText || i > 0) const SizedBox(height: chatBubbleSiblingSpacing),
          _buildAttachmentWidget(context, attachmentWidgets[i]),
        ],
        ?trailing,
      ],
    );
  }

  Widget _buildAttachmentWidget(BuildContext context, Widget attachmentWidget) {
    final attachmentInset = ThreadTypographyOverride.alignAttachmentEdgesWithBubblesOf(context)
        ? chatBubbleHorizontalInset
        : chatBubbleHorizontalInset + _resolvedChatBubbleHorizontalPadding(context);
    return Padding(
      key: attachmentWidget.key == null ? null : ValueKey<Object>(attachmentWidget.key!),
      padding: EdgeInsets.only(left: attachmentInset, right: attachmentInset),
      child: Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: attachmentWidget),
    );
  }
}

class PendingChatThreadMessage extends StatelessWidget {
  const PendingChatThreadMessage({
    super.key,
    required this.room,
    required this.message,
    this.shouldShowAuthorNames = true,
    this.mobileStorageSaveSurfacePresenter,
  });

  final RoomClient? room;
  final PendingAgentMessage message;
  final bool shouldShowAuthorNames;
  final ThreadStorageSaveSurfacePresenter? mobileStorageSaveSurfacePresenter;

  @override
  Widget build(BuildContext context) {
    final localParticipantName = room?.localParticipant?.getAttribute("name");
    final authorName = message.senderName ?? (localParticipantName is String ? localParticipantName : "");
    final createdAt = message.createdAt ?? DateTime.now();
    final opacity = message.awaitingOnline ? 0.72 : 1.0;

    return Opacity(
      opacity: opacity,
      child: SizedBox(
        key: ValueKey("pending-agent-message:${message.messageId}"),
        child: ChatThreadMessageView(
          room: room,
          mine: true,
          isAgentMessage: false,
          text: message.text,
          authorName: authorName,
          createdAt: createdAt,
          shouldShowHeader: shouldShowAuthorNames,
          mobileStorageSaveSurfacePresenter: mobileStorageSaveSurfacePresenter,
          attachmentWidgets: [
            for (final indexedAttachment in message.attachments.indexed)
              _buildAttachmentPreview(context, indexedAttachment.$2, attachmentIndex: indexedAttachment.$1),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview(BuildContext context, AgentFileContent attachment, {required int attachmentIndex}) {
    final trimmed = attachment.url.trim();
    final isInlineImage = trimmed.startsWith("data:image/");
    final displayName = attachment.name?.trim().isNotEmpty == true ? attachment.name!.trim() : _defaultSuggestedFileNameFromPath(trimmed);
    final canOpenInline = trimmed.startsWith("data:");
    final preview = isInlineImage
        ? ChatThreadImageAttachment(
            room: room,
            imageId: null,
            imageUri: trimmed,
            onOpenFullscreen: canOpenInline ? () => unawaited(_showPendingAttachmentPreview(context, attachment)) : null,
          )
        : FileDefaultPreviewCard(
            icon: LucideIcons.paperclip,
            text: displayName,
            useThreadAttachmentStyle: ThreadTypographyOverride.useThreadAttachmentStyleOf(context),
            showActionIcon: canOpenInline,
          );
    final child = canOpenInline && !isInlineImage
        ? MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: () => unawaited(_showPendingAttachmentPreview(context, attachment)), child: preview),
          )
        : preview;
    return KeyedSubtree(
      key: ValueKey(_pendingAttachmentWidgetKey(attachment, attachmentIndex)),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 312.5), child: child),
      ),
    );
  }

  String _pendingAttachmentWidgetKey(AgentFileContent attachment, int attachmentIndex) {
    final name = attachment.name?.trim() ?? "";
    final trimmed = attachment.url.trim();
    return "pending-agent-attachment:${message.messageId}:$attachmentIndex:$name:${trimmed.length}:${trimmed.hashCode}";
  }

  Future<void> _showPendingAttachmentPreview(BuildContext context, AgentFileContent attachment) {
    return showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (context) => _PendingAgentAttachmentViewer(attachment: attachment),
    );
  }
}

class _PendingAgentAttachmentViewer extends StatelessWidget {
  const _PendingAgentAttachmentViewer({required this.attachment});

  final AgentFileContent attachment;

  @override
  Widget build(BuildContext context) {
    final displayName = attachment.name?.trim().isNotEmpty == true
        ? attachment.name!.trim()
        : _defaultSuggestedFileNameFromPath(attachment.url);
    final decoded = _decodePendingDataUrl(attachment.url);
    final colorScheme = ShadTheme.of(context).colorScheme;
    return Dialog.fullscreen(
      backgroundColor: colorScheme.background,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      style: threadTypographyTextStyle(context, const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ShadButton.ghost(onPressed: () => Navigator.of(context).pop(), child: const Icon(LucideIcons.x)),
                ],
              ),
            ),
            Expanded(
              child: decoded == null
                  ? Center(
                      child: FileDefaultPreviewCard(
                        icon: LucideIcons.paperclip,
                        text: displayName,
                        useThreadAttachmentStyle: ThreadTypographyOverride.useThreadAttachmentStyleOf(context),
                      ),
                    )
                  : _PendingAgentAttachmentPreview(mimeType: decoded.mimeType, data: decoded.data, displayName: displayName),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingAgentAttachmentPreview extends StatelessWidget {
  const _PendingAgentAttachmentPreview({required this.mimeType, required this.data, required this.displayName});

  final String mimeType;
  final Uint8List data;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    if (mimeType.startsWith('image/')) {
      return InteractiveViewer(child: Center(child: Image.memory(data)));
    }
    if (mimeType == 'application/pdf') {
      return PdfViewer.data(data, sourceName: displayName);
    }
    if (mimeType.startsWith('text/') || mimeType == 'application/json' || mimeType == 'application/yaml') {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SelectableText(
          utf8.decode(data, allowMalformed: true),
          style: threadTypographyTextStyle(context, ShadTheme.of(context).textTheme.p),
        ),
      );
    }
    return Center(
      child: FileDefaultPreviewCard(
        icon: LucideIcons.paperclip,
        text: displayName,
        useThreadAttachmentStyle: ThreadTypographyOverride.useThreadAttachmentStyleOf(context),
      ),
    );
  }
}

({String mimeType, Uint8List data})? _decodePendingDataUrl(String url) {
  final match = RegExp(r'^data:([^;,]+)?(;base64)?,(.*)$', dotAll: true).firstMatch(url.trim());
  if (match == null) {
    return null;
  }
  final mimeType = match.group(1)?.trim();
  final body = match.group(3);
  if (body == null) {
    return null;
  }
  try {
    final data = match.group(2) == ';base64' ? base64Decode(body) : Uint8List.fromList(utf8.encode(Uri.decodeComponent(body)));
    return (mimeType: mimeType == null || mimeType.isEmpty ? 'application/octet-stream' : mimeType, data: Uint8List.fromList(data));
  } catch (_) {
    return null;
  }
}

class _ChatThreadMessagesState extends State<ChatThreadMessages> {
  static const double _statusBottomSpacer = 20;
  static const Duration _statusCollapseDelay = Duration(milliseconds: 500);
  static const Duration _statusAnimationDuration = Duration(seconds: 1);
  static const Curve _statusAnimationCurve = Curves.easeInOutCubicEmphasized;
  static const Key _statusBottomSpacerKey = ValueKey("chat-thread-status-bottom-spacer");
  static const int _maxImageCacheBytes = 64 * 1024 * 1024;

  static const List<String> _defaultReactionOptions = <String>[
    "👍",
    "👎",
    "❤️",
    "❤️‍🔥",
    "❤️‍🩹",
    "😂",
    "🤣",
    "😄",
    "😁",
    "😆",
    "🙂",
    "😊",
    "😉",
    "😍",
    "😘",
    "😜",
    "🤪",
    "😎",
    "🤩",
    "🥳",
    "😮",
    "😯",
    "😲",
    "😢",
    "😭",
    "😡",
    "😤",
    "🤔",
    "🤨",
    "😴",
    "😬",
    "🙃",
    "🫠",
    "👀",
    "🙌",
    "👏",
    "🙏",
    "🤝",
    "💪",
    "🔥",
    "✨",
    "💯",
    "✅",
    "❌",
    "⚠️",
    "❓",
    "💡",
    "🧪",
    "🛠️",
    "🐛",
    "🚀",
    "📌",
    "📎",
    "📝",
    "📷",
    "🎉",
    "🎊",
    "🎈",
    "🎁",
    "🏆",
    "⭐",
    "🌟",
    "⚡",
    "☕",
    "🍕",
    "🍻",
    "🤖",
  ];
  static const String _reactionTargetMessage = "message";
  static const String _reactionTargetAttachment = "attachment";
  static const Map<String, String> _reactionEmojiCanonicalByKey = <String, String>{"❤": "❤️", "♥": "❤️", "⚠": "⚠️", "🛠": "🛠️"};

  RoomClient get room => widget.room!;
  String get path => widget.path;
  String? get agentName => widget.agentName;
  bool get startChatCentered => widget.startChatCentered;
  bool get showTyping => widget.showTyping;
  bool get showListening => widget.showListening;
  String? get threadStatus => widget.threadStatus;
  DateTime? get threadStatusStartedAt => widget.threadStatusStartedAt;
  String? get threadStatusMode => widget.threadStatusMode;
  int? get threadStatusTotalBytes => widget.threadStatusTotalBytes;
  int? get threadStatusLinesAdded => widget.threadStatusLinesAdded;
  int? get threadStatusLinesRemoved => widget.threadStatusLinesRemoved;
  String? get pendingItemId => widget.pendingItemId;
  void Function()? get onCancel => widget.onCancel;
  List<MeshElement> get messages => widget.messages;
  List<Participant> get online => widget.online;
  String? get emptyStateTitle => widget.emptyStateTitle;
  String? get emptyStateDescription => widget.emptyStateDescription;
  Widget? get emptyState => widget.emptyState;
  Map<String, MessageBuilder>? get messageBuilders => widget.messageBuilders;
  Widget Function(BuildContext, MeshDocument, MeshElement)? get messageHeaderBuilder => widget.messageHeaderBuilder;
  Widget Function(BuildContext context, String path)? get fileInThreadBuilder => widget.fileInThreadBuilder;
  FutureOr<void> Function(String path)? get openFile => widget.openFile;
  ThreadStorageSaveSurfacePresenter? get mobileStorageSaveSurfacePresenter => widget.mobileStorageSaveSurfacePresenter;

  final OverlayPortalController _imageViewerController = OverlayPortalController();
  List<ChatThreadFeedImage> _overlayImages = const <ChatThreadFeedImage>[];
  int _overlayInitialIndex = 0;
  LocalHistoryEntry? _imageViewerHistoryEntry;
  final LinkedHashMap<String, _ThreadImageRecord> _imageCache = LinkedHashMap<String, _ThreadImageRecord>();
  final LinkedHashMap<String, int> _imageCacheSizes = LinkedHashMap<String, int>();
  final Map<String, Future<_ThreadImageRecord?>> _imageInFlight = <String, Future<_ThreadImageRecord?>>{};
  int _imageCacheBytes = 0;
  bool _attachmentShareInFlight = false;
  Timer? _statusCollapseTimer;
  bool _statusSlotVisible = false;
  String? _lastThreadStatus;
  DateTime? _lastThreadStatusStartedAt;
  String? _lastThreadStatusMode;
  int? _lastThreadStatusTotalBytes;
  int? _lastThreadStatusLinesAdded;
  int? _lastThreadStatusLinesRemoved;

  @override
  void initState() {
    super.initState();
    _statusSlotVisible = false;
    _rememberThreadStatus();
    if (showTyping) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !showTyping || _statusSlotVisible) {
          return;
        }
        setState(() {
          _statusSlotVisible = true;
        });
      });
    }
  }

  @override
  void didUpdateWidget(covariant ChatThreadMessages oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncStatusSlot();
  }

  void _rememberThreadStatus() {
    if (!showTyping) {
      return;
    }

    final normalizedStatus = threadStatus?.trim();
    if (normalizedStatus != null && normalizedStatus.isNotEmpty) {
      _lastThreadStatus = normalizedStatus;
    } else {
      _lastThreadStatus = "Thinking";
    }
    _lastThreadStatusStartedAt = threadStatusStartedAt;
    _lastThreadStatusMode = threadStatusMode;
    _lastThreadStatusTotalBytes = threadStatusTotalBytes;
    _lastThreadStatusLinesAdded = threadStatusLinesAdded;
    _lastThreadStatusLinesRemoved = threadStatusLinesRemoved;
  }

  void _syncStatusSlot() {
    if (showTyping) {
      _statusCollapseTimer?.cancel();
      _statusCollapseTimer = null;
      _rememberThreadStatus();
      if (!_statusSlotVisible) {
        setState(() {
          _statusSlotVisible = true;
        });
      }
      return;
    }

    if (!_statusSlotVisible || _statusCollapseTimer != null) {
      return;
    }

    _statusCollapseTimer = Timer(_statusCollapseDelay, () {
      _statusCollapseTimer = null;
      if (!mounted || showTyping) {
        return;
      }
      setState(() {
        _statusSlotVisible = false;
      });
    });
  }

  String _statusDisplayText() {
    final normalizedStatus = threadStatus?.trim();
    if (showTyping) {
      return normalizedStatus != null && normalizedStatus.isNotEmpty ? normalizedStatus : "Thinking";
    }
    return _lastThreadStatus ?? "Thinking";
  }

  String? _localParticipantName() {
    final name = room.localParticipant?.getAttribute("name");
    if (name is! String) {
      return null;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String? _normalizeReactionValue(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.characters.length != 1) {
      return null;
    }
    final emoji = trimmed.characters.first;
    final emojiKey = _normalizeEmojiPresentationKey(emoji);
    return _reactionEmojiCanonicalByKey[emojiKey] ?? emoji;
  }

  bool _isTerminalStackMessage(MeshElement? message) => message?.tagName == "exec";

  double _threadFeedStackSpacingBetween(MeshElement? previous, MeshElement current) {
    if (_isTerminalStackMessage(previous) && _isTerminalStackMessage(current)) {
      return 0.0;
    }

    return ThreadTypographyOverride.maybeThreadFeedItemSpacingOf(context) ?? ChatThreadMessageView.chatMessageStackSpacing;
  }

  String? _normalizeReactionUserName(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed.toLowerCase();
  }

  bool _isLocalReactionAuthor(MeshElement reactionElement, {required String? normalizedLocalUserName}) {
    final reactionUserName = _normalizeReactionUserName(reactionElement.getAttribute("user_name"));
    if (normalizedLocalUserName != null && reactionUserName == normalizedLocalUserName) {
      return true;
    }

    return false;
  }

  List<MeshElement> _reactionElements({required MeshElement message}) {
    final reactions = <MeshElement>[];
    for (final child in message.getChildren().whereType<MeshElement>()) {
      if (child.tagName != "reaction") {
        continue;
      }
      reactions.add(child);
    }
    return reactions;
  }

  void _createReactionElement({required MeshElement message, required Map<String, Object?> attributes}) {
    message.createChildElement("reaction", attributes);
  }

  String? _normalizeReactionAttachmentRef(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String _reactionUsersTooltipText(Iterable<String> userNames) {
    final names = userNames.map((name) => name.trim()).where((name) => name.isNotEmpty).toSet().toList()
      ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));

    if (names.isEmpty) {
      return "No users";
    }

    const maxNames = 10;
    if (names.length <= maxNames) {
      return names.join(", ");
    }

    final shown = names.take(maxNames).join(", ");
    final othersCount = names.length - maxNames;
    return "$shown, and $othersCount others";
  }

  String? _reactionAttachmentRefFromElement(MeshElement reactionElement) {
    return _normalizeReactionAttachmentRef(reactionElement.getAttribute("attachment_ref"));
  }

  String _reactionTargetFromElement(MeshElement reactionElement) {
    final attachmentRef = _reactionAttachmentRefFromElement(reactionElement);
    final targetRaw = reactionElement.getAttribute("target");
    if (targetRaw is! String) {
      return attachmentRef == null ? _reactionTargetMessage : _reactionTargetAttachment;
    }

    final normalized = targetRaw.trim().toLowerCase();
    if (normalized == _reactionTargetAttachment) {
      return attachmentRef == null ? _reactionTargetMessage : _reactionTargetAttachment;
    }
    if (normalized == _reactionTargetMessage) {
      return _reactionTargetMessage;
    }
    return attachmentRef == null ? _reactionTargetMessage : _reactionTargetAttachment;
  }

  List<MeshElement> _reactionElementsForTarget({required MeshElement message, required String target, String? attachmentRef}) {
    final normalizedTarget = target.trim().toLowerCase();
    final normalizedAttachmentRef = _normalizeReactionAttachmentRef(attachmentRef);
    final effectiveTarget = normalizedTarget == _reactionTargetAttachment && normalizedAttachmentRef != null
        ? _reactionTargetAttachment
        : _reactionTargetMessage;

    final reactions = <MeshElement>[];
    for (final reactionElement in _reactionElements(message: message)) {
      if (_reactionTargetFromElement(reactionElement) != effectiveTarget) {
        continue;
      }
      if (effectiveTarget == _reactionTargetAttachment) {
        final reactionAttachmentRef = _reactionAttachmentRefFromElement(reactionElement);
        if (reactionAttachmentRef != normalizedAttachmentRef) {
          continue;
        }
      }
      reactions.add(reactionElement);
    }
    return reactions;
  }

  String? _selectedReactionForTarget({required MeshElement message, required String target, String? attachmentRef}) {
    final normalizedLocalUserName = _normalizeReactionUserName(_localParticipantName());
    if (normalizedLocalUserName == null) {
      return null;
    }

    final normalizedTarget = target.trim().toLowerCase();
    final normalizedAttachmentRef = _normalizeReactionAttachmentRef(attachmentRef);
    final effectiveTarget = normalizedTarget == _reactionTargetAttachment && normalizedAttachmentRef != null
        ? _reactionTargetAttachment
        : _reactionTargetMessage;

    for (final reactionElement in _reactionElementsForTarget(
      message: message,
      target: effectiveTarget,
      attachmentRef: normalizedAttachmentRef,
    )) {
      if (!_isLocalReactionAuthor(reactionElement, normalizedLocalUserName: normalizedLocalUserName)) {
        continue;
      }
      final value = _normalizeReactionValue(reactionElement.getAttribute("value"));
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  Future<void> _showReactionPickerDialog(
    BuildContext context, {
    required String? selectedReaction,
    required ValueChanged<String> onSelected,
  }) async {
    await _showReactionPickerSurface(
      context,
      reactionOptions: _defaultReactionOptions,
      selectedReaction: selectedReaction,
      onSelected: onSelected,
    );
  }

  void _toggleReaction({
    required MeshElement message,
    required String reaction,
    String target = _reactionTargetMessage,
    String? attachmentRef,
    bool removeIfSame = false,
  }) {
    final userName = _localParticipantName();
    final normalizedUserName = _normalizeReactionUserName(userName);
    if (normalizedUserName == null) {
      return;
    }
    final normalizedValue = _normalizeReactionValue(reaction);
    if (normalizedValue == null) {
      return;
    }

    final normalizedTarget = target.trim().toLowerCase();
    final normalizedAttachmentRef = _normalizeReactionAttachmentRef(attachmentRef);
    final effectiveTarget = normalizedTarget == _reactionTargetAttachment && normalizedAttachmentRef != null
        ? _reactionTargetAttachment
        : _reactionTargetMessage;
    final reactions = _reactionElementsForTarget(message: message, target: effectiveTarget, attachmentRef: normalizedAttachmentRef);

    final mine = <MeshElement>[];
    final mineWithSameValue = <MeshElement>[];
    for (final reactionElement in reactions) {
      if (!_isLocalReactionAuthor(reactionElement, normalizedLocalUserName: normalizedUserName)) {
        continue;
      }
      mine.add(reactionElement);
      final existingValue = _normalizeReactionValue(reactionElement.getAttribute("value"));
      if (existingValue == normalizedValue) {
        mineWithSameValue.add(reactionElement);
      }
    }

    if (mineWithSameValue.isNotEmpty) {
      if (removeIfSame) {
        for (final reactionElement in mineWithSameValue) {
          reactionElement.delete();
        }
      }
      return;
    }

    for (final reactionElement in mine) {
      reactionElement.delete();
    }

    final attrs = <String, Object?>{
      "user_name": userName,
      "value": normalizedValue,
      "target": effectiveTarget,
      "created_at": DateTime.now().toUtc().toIso8601String(),
    };
    if (effectiveTarget == _reactionTargetAttachment && normalizedAttachmentRef != null) {
      attrs["attachment_ref"] = normalizedAttachmentRef;
    }

    _createReactionElement(message: message, attributes: attrs);
  }

  Widget _buildReactionRow(
    BuildContext context, {
    required MeshElement message,
    required bool mine,
    String target = _reactionTargetMessage,
    String? attachmentRef,
    bool showAddWhenEmpty = true,
    List<Widget> leadingActions = const <Widget>[],
  }) {
    final localUserName = _localParticipantName();
    final normalizedLocalUserName = _normalizeReactionUserName(localUserName);
    final normalizedTarget = target.trim().toLowerCase();
    final normalizedAttachmentRef = _normalizeReactionAttachmentRef(attachmentRef);
    final effectiveTarget = normalizedTarget == _reactionTargetAttachment && normalizedAttachmentRef != null
        ? _reactionTargetAttachment
        : _reactionTargetMessage;
    final grouped = <String, Set<String>>{};
    final groupedDisplayNames = <String, Map<String, String>>{};
    final mineValues = <String>{};

    for (final reactionElement in _reactionElementsForTarget(
      message: message,
      target: effectiveTarget,
      attachmentRef: normalizedAttachmentRef,
    )) {
      final value = _normalizeReactionValue(reactionElement.getAttribute("value"));
      if (value == null) {
        continue;
      }
      final userName = _normalizeReactionUserName(reactionElement.getAttribute("user_name"));
      if (userName == null) {
        continue;
      }
      final displayNameRaw = reactionElement.getAttribute("user_name");
      final displayName = displayNameRaw is String && displayNameRaw.trim().isNotEmpty ? displayNameRaw.trim() : userName;
      grouped.putIfAbsent(value, () => <String>{}).add(userName);
      groupedDisplayNames.putIfAbsent(value, () => <String, String>{})[userName] = displayName;
      if (_isLocalReactionAuthor(reactionElement, normalizedLocalUserName: normalizedLocalUserName)) {
        mineValues.add(value);
      }
    }

    final entries = grouped.entries.toList()..sort((left, right) => left.key.compareTo(right.key));
    String? selectedReaction = entries.firstWhereOrNull((entry) => mineValues.contains(entry.key))?.key;
    final hasSelectedReaction = selectedReaction != null;
    final showAddButton = localUserName != null && !hasSelectedReaction && (showAddWhenEmpty || grouped.isNotEmpty);

    if (grouped.isEmpty && !showAddButton && leadingActions.isEmpty) {
      return const SizedBox.shrink();
    }

    final alignment = mine ? Alignment.centerRight : Alignment.centerLeft;
    final theme = ShadTheme.of(context);

    return Container(
      margin: EdgeInsets.only(top: 6, right: mine ? 0 : 50, left: mine ? 50 : 0),
      child: Align(
        alignment: alignment,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...leadingActions,
            for (final entry in entries)
              Builder(
                builder: (context) {
                  final users = entry.value;
                  final tooltipText = _reactionUsersTooltipText(groupedDisplayNames[entry.key]?.values ?? const <String>[]);
                  final isMine = mineValues.contains(entry.key);
                  final isMobileReactionChip = _usesMobileContextLayout(context);
                  final reactionEmojiSize = isMobileReactionChip ? 16.0 : 14.0;
                  final reactionEmojiYOffset = isMobileReactionChip ? 2.0 : 0.0;
                  final reactionCountYOffset = isMobileReactionChip ? 1.0 : 0.0;
                  final reactionCountStyle = theme.textTheme.small.copyWith(
                    fontWeight: isMine ? FontWeight.w700 : FontWeight.w500,
                    fontSize: isMobileReactionChip ? ((theme.textTheme.small.fontSize ?? 14) - 1) : null,
                    height: 1,
                  );
                  Widget reactionChip({required VoidCallback? onPressed}) {
                    return Tooltip(
                      message: tooltipText,
                      child: ShadButton.ghost(
                        padding: EdgeInsets.symmetric(horizontal: isMobileReactionChip ? 9 : 8, vertical: isMobileReactionChip ? 5 : 4),
                        backgroundColor: isMine ? theme.colorScheme.accent.withValues(alpha: 0.2) : theme.colorScheme.muted,
                        hoverBackgroundColor: isMine
                            ? theme.colorScheme.accent.withValues(alpha: 0.25)
                            : theme.colorScheme.muted.withValues(alpha: 0.7),
                        onPressed: onPressed,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Transform.translate(
                              offset: Offset(0, reactionEmojiYOffset),
                              child: Text(entry.key, style: _emojiTextStyle(size: reactionEmojiSize)),
                            ),
                            SizedBox(width: isMobileReactionChip ? 5 : 4),
                            Transform.translate(
                              offset: Offset(0, reactionCountYOffset),
                              child: Text("${users.length}", style: reactionCountStyle),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (localUserName == null) {
                    return reactionChip(onPressed: null);
                  }

                  if (hasSelectedReaction) {
                    return _ReactionPickerButton(
                      reactionOptions: _defaultReactionOptions,
                      selectedReaction: selectedReaction,
                      onSelected: (reaction) {
                        _toggleReaction(
                          message: message,
                          reaction: reaction,
                          target: effectiveTarget,
                          attachmentRef: normalizedAttachmentRef,
                          removeIfSame: true,
                        );
                      },
                      triggerBuilder: (onPressed) => reactionChip(onPressed: onPressed),
                    );
                  }

                  return reactionChip(
                    onPressed: () => _toggleReaction(
                      message: message,
                      reaction: entry.key,
                      target: effectiveTarget,
                      attachmentRef: normalizedAttachmentRef,
                    ),
                  );
                },
              ),
            if (showAddButton)
              _ReactionPickerButton(
                reactionOptions: _defaultReactionOptions,
                selectedReaction: selectedReaction,
                onSelected: (reaction) {
                  _toggleReaction(
                    message: message,
                    reaction: reaction,
                    target: effectiveTarget,
                    attachmentRef: normalizedAttachmentRef,
                    removeIfSame: true,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _hideThreadImageViewer() {
    _imageViewerController.hide();
    if (mounted) {
      setState(() {});
    }
  }

  void _closeThreadImageViewer() {
    final historyEntry = _imageViewerHistoryEntry;
    if (historyEntry != null) {
      _imageViewerHistoryEntry = null;
      historyEntry.remove();
      return;
    }
    _hideThreadImageViewer();
  }

  void _openThreadImageViewer(BuildContext context, {required List<ChatThreadFeedImage> images, required int initialIndex}) {
    if (images.isEmpty) {
      return;
    }

    final route = ModalRoute.of(context);
    if (_imageViewerHistoryEntry == null && route != null) {
      final historyEntry = LocalHistoryEntry(
        onRemove: () {
          _imageViewerHistoryEntry = null;
          _hideThreadImageViewer();
        },
      );
      _imageViewerHistoryEntry = historyEntry;
      route.addLocalHistoryEntry(historyEntry);
    }

    final clampedInitialIndex = initialIndex.clamp(0, images.length - 1);
    setState(() {
      _overlayImages = List<ChatThreadFeedImage>.unmodifiable(images);
      _overlayInitialIndex = clampedInitialIndex;
    });
    _imageViewerController.show();
  }

  @override
  void dispose() {
    _statusCollapseTimer?.cancel();
    final historyEntry = _imageViewerHistoryEntry;
    _imageViewerHistoryEntry = null;
    historyEntry?.remove();
    _imageCache.clear();
    _imageCacheSizes.clear();
    _imageInFlight.clear();
    _imageCacheBytes = 0;
    super.dispose();
  }

  List<ChatThreadFeedImage> _collectThreadImages() {
    final imagesInThread = <ChatThreadFeedImage>[];

    for (final message in messages) {
      for (final attachment in message.getChildren().whereType<MeshElement>()) {
        if (attachment.tagName != "image" && attachment.tagName != "file") {
          continue;
        }

        final pathAttribute = attachment.getAttribute("path");
        final path = pathAttribute is String ? _sanitizePath(pathAttribute) : null;
        if (path != null && path.trim().isNotEmpty && _isImageFilePath(path)) {
          final attachmentElementId = attachment.id;
          imagesInThread.add(
            ChatThreadFeedImage(
              attachmentElementId: attachmentElementId == null || attachmentElementId.trim().isEmpty ? "path:$path" : attachmentElementId,
              imageId: "",
              path: path,
            ),
          );
          continue;
        }

        if (attachment.tagName != "image") {
          continue;
        }

        final imageIdAttribute = attachment.getAttribute("id");
        final imageId = (imageIdAttribute is String && imageIdAttribute.trim().isNotEmpty) ? imageIdAttribute.trim() : null;
        if (imageId == null) {
          continue;
        }
        final attachmentElementId = attachment.id;
        if (attachmentElementId == null || attachmentElementId.trim().isEmpty) {
          continue;
        }

        final mimeTypeAttribute = attachment.getAttribute("mime_type");
        final mimeType = mimeTypeAttribute is String ? mimeTypeAttribute : null;
        final statusAttribute = attachment.getAttribute("status");
        final status = statusAttribute is String ? statusAttribute.trim() : null;
        final statusDetailAttribute = attachment.getAttribute("status_detail");
        final statusDetail = statusDetailAttribute is String ? statusDetailAttribute.trim() : null;
        final width = _parsePositiveDimension(attachment.getAttribute("width"));
        final height = _parsePositiveDimension(attachment.getAttribute("height"));

        imagesInThread.add(
          ChatThreadFeedImage(
            attachmentElementId: attachmentElementId,
            imageId: imageId,
            mimeType: mimeType,
            status: status,
            statusDetail: statusDetail,
            widthPx: width,
            heightPx: height,
          ),
        );
      }
    }

    return imagesInThread;
  }

  String _sanitizePath(String path) {
    return path.replaceFirst(RegExp(r'^/'), '');
  }

  bool _isImageFilePath(String path) {
    final lower = _sanitizePath(path).toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot <= 0 || dot == lower.length - 1) {
      return false;
    }
    final ext = lower.substring(dot + 1);
    return imageExtensions.contains(ext);
  }

  _ThreadImageRecord? _readCachedImageRecord(String path) {
    final record = _imageCache.remove(path);
    if (record == null) {
      return null;
    }

    final size = _imageCacheSizes.remove(path) ?? record.data.length;
    _imageCache[path] = record;
    _imageCacheSizes[path] = size;
    return record;
  }

  void _trimImageCache() {
    while (_imageCacheBytes > _maxImageCacheBytes && _imageCache.isNotEmpty) {
      final oldestPath = _imageCache.keys.first;
      _imageCache.remove(oldestPath);
      final removedSize = _imageCacheSizes.remove(oldestPath) ?? 0;
      _imageCacheBytes -= removedSize;
    }

    if (_imageCacheBytes < 0) {
      _imageCacheBytes = 0;
    }
  }

  void _cacheImageRecord(String path, _ThreadImageRecord record) {
    final size = record.data.length;

    final existingRecord = _imageCache.remove(path);
    if (existingRecord != null) {
      _imageCacheBytes -= _imageCacheSizes.remove(path) ?? existingRecord.data.length;
    }

    if (size > _maxImageCacheBytes) {
      _trimImageCache();
      return;
    }

    _imageCache[path] = record;
    _imageCacheSizes[path] = size;
    _imageCacheBytes += size;
    _trimImageCache();
  }

  Future<_ThreadImageRecord?> _loadImageRecord(String path) async {
    final cached = _readCachedImageRecord(path);
    if (cached != null) {
      return cached;
    }

    final inFlight = _imageInFlight[path];
    if (inFlight != null) {
      return inFlight;
    }

    final lookup = () async {
      final file = await room.storage.download(path);
      final mimeType = file.mimeType.trim().isNotEmpty ? file.mimeType.trim() : "image/png";
      final record = _ThreadImageRecord(data: file.data, mimeType: mimeType);
      _cacheImageRecord(path, record);
      return record;
    }();

    _imageInFlight[path] = lookup;
    try {
      return await lookup;
    } finally {
      if (identical(_imageInFlight[path], lookup)) {
        _imageInFlight.remove(path);
      }
    }
  }

  Future<void> _copyImageRecord(_ThreadImageRecord image) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return;
    }

    final mimeType = image.mimeType.trim().toLowerCase();
    final format = _ImageMime.clipboardFormat(mimeType);
    final item = DataWriterItem(suggestedName: _ImageMime.suggestedFileName(mimeType));
    if (format != null) {
      item.add(format(image.data));
    } else {
      item.add(EncodedData([raw.DataRepresentation.simple(format: mimeType, data: image.data)]));
    }

    await clipboard.write([item]);
  }

  Future<void> _downloadPath(String path) async {
    final url = await room.storage.downloadUrl(path);
    await launchUrl(Uri.parse(url));
  }

  Future<void> _saveStoragePath(String path) async {
    await _showThreadStorageSaveSurface(
      context,
      room: room,
      title: "Save file as ...",
      suggestedFileName: _defaultSuggestedFileNameFromPath(path),
      fileNameLabel: "File name or path",
      mobilePresenter: mobileStorageSaveSurfacePresenter,
      loadContent: () => room.storage.download(path),
    );
  }

  Future<void> _confirmDeleteMessage(MeshElement message) async {
    await showShadDialog<void>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text("Delete Message"),
        description: const Text("Are you sure you want to delete this message? This action cannot be undone."),
        actions: [
          ShadButton.secondary(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text("Cancel"),
          ),
          ShadButton(
            onPressed: () {
              message.delete();
              Navigator.of(context).pop();
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Future<void> _openPath(String path) async {
    if (widget.openFile != null) {
      await widget.openFile!(path);
      return;
    }

    showShadDialog(
      context: context,
      builder: (context) {
        return ShadDialog(
          crossAxisAlignment: CrossAxisAlignment.start,
          title: Text("File: $path"),
          actions: _usesMobileContextLayout(context)
              ? const <Widget>[]
              : [
                  ShadButton(
                    onPressed: () async {
                      await _downloadPath(path);
                    },
                    child: Text("Download"),
                  ),
                ],
          child: FilePreview(room: room, path: path, fit: BoxFit.contain),
        );
      },
    );
  }

  Widget _wrapWithCorners(Widget child) {
    return ClipRRect(borderRadius: BorderRadius.circular(16), child: child);
  }

  Widget _wrapTapTarget(Widget child, String path) {
    return ShadGestureDetector(
      cursor: SystemMouseCursors.click,
      onTap: () async {
        await _openPath(path);
      },
      child: child,
    );
  }

  Widget _buildFileImageInThread(
    BuildContext context,
    String path,
    _ThreadImageRecord? imageRecord,
    bool loading, {
    required List<ShadContextMenuItem> items,
    VoidCallback? onOpenFullscreen,
  }) {
    final imagePreview = SizedBox(
      width: 312.5,
      height: 312.5,
      child: _wrapWithCorners(
        ColoredBox(
          color: ShadTheme.of(context).colorScheme.background,
          child: imageRecord == null
              ? Center(
                  child: loading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(LucideIcons.imageOff, size: 20, color: ShadTheme.of(context).colorScheme.mutedForeground),
                )
              : _ImageMime.isSvg(imageRecord.mimeType)
              ? SvgPicture.memory(imageRecord.data, fit: BoxFit.cover)
              : UniversalImage(imageRecord.data, fit: BoxFit.cover),
        ),
      ),
    );
    final child = onOpenFullscreen == null
        ? _wrapTapTarget(imagePreview, path)
        : ShadGestureDetector(cursor: SystemMouseCursors.zoomIn, onTap: onOpenFullscreen, child: imagePreview);

    if (_usesMobileContextLayout(context)) {
      return CoordinatedShadContextMenuRegion(items: items, tapEnabled: false, child: child);
    }

    return CoordinatedShadContextMenuRegion(items: items, child: child);
  }

  Widget _buildFileInThread(BuildContext context, String path, {required List<ShadContextMenuItem> items}) {
    final child = _wrapTapTarget(
      fileInThreadBuilder != null ? fileInThreadBuilder!(context, path) : ChatThreadPreview(room: room, path: path),
      path,
    );

    if (_usesMobileContextLayout(context)) {
      return CoordinatedShadContextMenuRegion(items: items, tapEnabled: false, child: child);
    }

    return CoordinatedShadContextMenuRegion(items: items, child: child);
  }

  List<ShadContextMenuItem> _buildMobileAttachmentOptions({
    required MeshElement message,
    required String? attachmentRef,
    _ThreadImageRecord? imageRecord,
    String? path,
  }) {
    final canReact = attachmentRef != null && _localParticipantName() != null;
    final selectedReaction = canReact
        ? _selectedReactionForTarget(message: message, target: _reactionTargetAttachment, attachmentRef: attachmentRef)
        : null;

    return [
      if (imageRecord != null) ShadContextMenuItem(height: 40, onPressed: () => _copyImageRecord(imageRecord), child: const Text("Copy")),
      if (canReact)
        ShadContextMenuItem(
          height: 40,
          onPressed: () {
            _showReactionPickerDialog(
              context,
              selectedReaction: selectedReaction,
              onSelected: (reaction) {
                _toggleReaction(
                  message: message,
                  reaction: reaction,
                  target: _reactionTargetAttachment,
                  attachmentRef: attachmentRef,
                  removeIfSame: true,
                );
              },
            );
          },
          child: const Text("React"),
        ),
      if (path != null) ShadContextMenuItem(height: 40, onPressed: () => _saveStoragePath(path), child: const Text("Save as...")),
      ShadContextMenuItem(height: 40, onPressed: () => _confirmDeleteMessage(message), child: const Text("Delete")),
    ];
  }

  Widget _buildImageInThread(BuildContext context, MeshElement attachment, {required List<ChatThreadFeedImage> feedImages}) {
    final imageIdAttribute = attachment.getAttribute("id");
    final imageId = (imageIdAttribute is String && imageIdAttribute.trim().isNotEmpty) ? imageIdAttribute.trim() : null;

    final mimeTypeAttribute = attachment.getAttribute("mime_type");
    final mimeType = mimeTypeAttribute is String ? mimeTypeAttribute : null;
    final statusAttribute = attachment.getAttribute("status");
    final status = statusAttribute is String ? statusAttribute.trim() : null;
    final statusDetailAttribute = attachment.getAttribute("status_detail");
    final statusDetail = statusDetailAttribute is String ? statusDetailAttribute.trim() : null;
    final width = _parsePositiveDimension(attachment.getAttribute("width"));
    final height = _parsePositiveDimension(attachment.getAttribute("height"));
    final initialIndex = feedImages.indexWhere((entry) => entry.attachmentElementId == attachment.id);

    VoidCallback? onOpenFullscreen;
    if (initialIndex >= 0 && feedImages.isNotEmpty) {
      onOpenFullscreen = () {
        _openThreadImageViewer(context, images: feedImages, initialIndex: initialIndex);
      };
    }

    return ChatThreadImageAttachment(
      room: room,
      imageId: imageId,
      fallbackMimeType: mimeType,
      status: status,
      statusDetail: statusDetail,
      widthPx: width,
      heightPx: height,
      roundedCorners: false,
      onOpenFullscreen: onOpenFullscreen,
    );
  }

  double? _parsePositiveDimension(Object? value) {
    if (value is num) {
      final dimension = value.toDouble();
      return dimension > 0 ? dimension : null;
    }

    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    return null;
  }

  Widget _buildAttachmentInThread(
    BuildContext context,
    MeshElement message,
    bool mine,
    MeshElement attachment, {
    required int attachmentIndex,
    required List<ChatThreadFeedImage> feedImages,
  }) {
    Widget keyed(Widget child) {
      return KeyedSubtree(key: ValueKey(_threadAttachmentWidgetKey(message, attachment, attachmentIndex)), child: child);
    }

    final normalizedAttachmentRef = _normalizeReactionAttachmentRef(attachment.id);

    if (attachment.tagName == "image") {
      return keyed(
        Column(
          crossAxisAlignment: mine ? .end : .start,
          children: [
            _buildImageInThread(context, attachment, feedImages: feedImages),
            if (normalizedAttachmentRef != null)
              _buildReactionRow(
                context,
                message: message,
                mine: mine,
                target: _reactionTargetAttachment,
                attachmentRef: normalizedAttachmentRef,
              ),
          ],
        ),
      );
    }

    final pathAttribute = attachment.getAttribute("path");
    if (pathAttribute is! String || pathAttribute.trim().isEmpty) {
      return keyed(const SizedBox.shrink());
    }

    final normalizedPath = _sanitizePath(pathAttribute);

    if (attachment.tagName == "file" && _isImageFilePath(normalizedPath)) {
      final initialIndex = feedImages.indexWhere((entry) => entry.path == normalizedPath);
      final onOpenFullscreen = initialIndex < 0
          ? null
          : () {
              _openThreadImageViewer(context, images: feedImages, initialIndex: initialIndex);
            };
      return keyed(
        _ThreadImageLookup(
          lookupKey: normalizedPath,
          readCached: () => _readCachedImageRecord(normalizedPath),
          lookupImage: () => _loadImageRecord(normalizedPath),
          builder: (context, snapshot) {
            final imageRecord = snapshot.data;
            final loading = snapshot.connectionState != ConnectionState.done;
            final items = _usesMobileContextLayout(context)
                ? _buildMobileAttachmentOptions(
                    message: message,
                    attachmentRef: normalizedAttachmentRef,
                    imageRecord: imageRecord,
                    path: normalizedPath,
                  )
                : _buildAttachmentOptions(imageRecord: imageRecord, path: normalizedPath);

            return Column(
              crossAxisAlignment: mine ? .end : .start,
              children: [
                _buildFileImageInThread(context, normalizedPath, imageRecord, loading, items: items, onOpenFullscreen: onOpenFullscreen),
                if (normalizedAttachmentRef != null)
                  _buildReactionRow(
                    context,
                    message: message,
                    mine: mine,
                    target: _reactionTargetAttachment,
                    attachmentRef: normalizedAttachmentRef,
                    leadingActions: _buildAttachmentActions(imageRecord: imageRecord, path: normalizedPath),
                  ),
              ],
            );
          },
        ),
      );
    }

    return keyed(
      Column(
        crossAxisAlignment: mine ? .end : .start,
        children: [
          _buildFileInThread(
            context,
            normalizedPath,
            items: _usesMobileContextLayout(context)
                ? _buildMobileAttachmentOptions(message: message, attachmentRef: normalizedAttachmentRef, path: normalizedPath)
                : _buildAttachmentOptions(path: normalizedPath),
          ),
          if (normalizedAttachmentRef != null)
            _buildReactionRow(
              context,
              message: message,
              mine: mine,
              target: _reactionTargetAttachment,
              attachmentRef: normalizedAttachmentRef,
              leadingActions: _buildAttachmentActions(path: normalizedPath),
            ),
        ],
      ),
    );
  }

  String _threadAttachmentWidgetKey(MeshElement message, MeshElement attachment, int attachmentIndex) {
    final messageIdAttribute = message.getAttribute("id");
    final messageElementId = message.id;
    final messageId = messageIdAttribute is String && messageIdAttribute.trim().isNotEmpty
        ? messageIdAttribute.trim()
        : messageElementId == null || messageElementId.trim().isEmpty
        ? "message"
        : messageElementId.trim();
    final attachmentElementId = attachment.id?.trim();
    if (attachmentElementId != null && attachmentElementId.isNotEmpty) {
      return "thread-attachment:$messageId:element:$attachmentElementId";
    }

    final imageIdAttribute = attachment.getAttribute("id");
    if (imageIdAttribute is String && imageIdAttribute.trim().isNotEmpty) {
      return "thread-attachment:$messageId:image:${imageIdAttribute.trim()}";
    }

    final pathAttribute = attachment.getAttribute("path");
    if (pathAttribute is String && pathAttribute.trim().isNotEmpty) {
      return "thread-attachment:$messageId:path:${_sanitizePath(pathAttribute)}";
    }

    return "thread-attachment:$messageId:index:$attachmentIndex";
  }

  List<ShadContextMenuItem> _buildAttachmentOptions({_ThreadImageRecord? imageRecord, String? path}) {
    final isMobile = _usesMobileContextLayout(context);

    return [
      if (path != null)
        ShadContextMenuItem(
          height: 40,
          onPressed: () async {
            await _openPath(path);
          },
          leading: const Icon(LucideIcons.externalLink, size: 14),
          child: const Text("Open"),
        ),
      if (imageRecord != null)
        ShadContextMenuItem(
          height: 40,
          onPressed: () async {
            await _copyImageRecord(imageRecord);
          },
          leading: const Icon(LucideIcons.copy, size: 14),
          child: const Text("Copy"),
        ),
      if (path != null && !isMobile)
        ShadContextMenuItem(
          height: 40,
          onPressed: () async {
            await _downloadPath(path);
          },
          leading: const Icon(LucideIcons.download, size: 14),
          child: const Text("Download"),
        ),
    ];
  }

  List<Widget> _buildAttachmentActions({_ThreadImageRecord? imageRecord, String? path}) {
    if (_usesMobileContextLayout(context) && path != null && supportsNativeThreadAttachmentShare) {
      final theme = ShadTheme.of(context);

      return [
        Semantics(
          label: "Share attachment",
          button: true,
          child: ShadIconButton.ghost(
            width: 40,
            height: 40,
            padding: EdgeInsets.zero,
            icon: _attachmentShareInFlight
                ? SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(theme.colorScheme.mutedForeground)),
                  )
                : Icon(LucideIcons.share, size: 19, color: theme.colorScheme.mutedForeground),
            onPressed: _attachmentShareInFlight
                ? null
                : () async {
                    setState(() {
                      _attachmentShareInFlight = true;
                    });

                    try {
                      await shareThreadAttachment(context: context, room: room, path: path);
                    } catch (error) {
                      if (!mounted) {
                        return;
                      }

                      ShadToaster.of(
                        context,
                      ).show(ShadToast.destructive(title: const Text("Unable to share attachment"), description: Text("$error")));
                    } finally {
                      if (mounted) {
                        setState(() {
                          _attachmentShareInFlight = false;
                        });
                      }
                    }
                  },
          ),
        ),
      ];
    }

    final items = _buildAttachmentOptions(imageRecord: imageRecord, path: path);
    return [_AttachmentOptionsButton(items: items)];
  }

  bool _shouldRenderThreadMessage(MeshElement message) {
    return _shouldRenderThreadMessageElement(message, showCompletedToolCalls: widget.showCompletedToolCalls);
  }

  Widget _buildMessage(
    BuildContext context,
    MeshElement? previous,
    MeshElement message,
    MeshElement? next, {
    required List<ChatThreadFeedImage> feedImages,
  }) {
    final localParticipantName = room.localParticipant?.getAttribute("name");
    final localParticipantReactionName = _localParticipantName();
    final rawRole = message.getAttribute("role");
    final isAgentMessage = rawRole is String && rawRole.trim().toLowerCase() == "agent";
    final mine = !isAgentMessage && message.getAttribute("author_name") == localParticipantName;
    final useDefaultHeaderBuilder = messageHeaderBuilder == null;
    final shouldShowHeader = !useDefaultHeaderBuilder || widget.shouldShowAuthorNames;

    final id = message.getAttribute("id");
    final text = message.getAttribute("text");
    final messageText = text is String ? text : null;
    final attachments = message.getChildren().whereType<MeshElement>().where(_isThreadAttachmentElement).toList();
    final hasMessageLevelReactions = _reactionElementsForTarget(message: message, target: _reactionTargetMessage).isNotEmpty;
    final selectedMessageReaction = _selectedReactionForTarget(message: message, target: _reactionTargetMessage);

    if (messageBuilders?[message.tagName] != null) {
      return messageBuilders![message.tagName]!(room: room, previous: previous, message: message, next: next);
    }

    if (message.tagName == "reasoning") {
      final summary = (message.getAttribute("summary") ?? "").toString().trim();
      if (summary.isEmpty) {
        return const SizedBox.shrink();
      }
      return ReasoningTrace(previous: previous, message: message, next: next);
    }
    if (message.tagName == "exec") {
      return ShellLine(previous: previous, message: message, next: next);
    }
    if (message.tagName == "event") {
      return EventLine(
        previous: previous,
        message: message,
        next: next,
        room: room,
        path: path,
        agentName: agentName,
        showCompletedToolCalls: widget.showCompletedToolCalls,
        openFile: openFile,
        pendingItemId: pendingItemId,
        threadStatus: threadStatus,
        threadStatusStartedAt: threadStatusStartedAt,
      );
    }

    return SizedBox(
      key: ValueKey(id),
      child: ChatThreadMessageView(
        room: room,
        mine: mine,
        isAgentMessage: isAgentMessage,
        text: messageText,
        authorName: (message.getAttribute("author_name") ?? "").toString(),
        createdAt: _messageCreatedAt(message),
        shouldShowHeader: shouldShowHeader,
        header:
            messageHeaderBuilder?.call(context, message.doc as MeshDocument, message) ??
            defaultMessageHeaderBuilder(context, message, shouldShowAuthorNames: widget.shouldShowAuthorNames),
        onDelete: message.delete,
        mobileStorageSaveSurfacePresenter: mobileStorageSaveSurfacePresenter,
        reactionActionBuilder: localParticipantReactionName == null
            ? null
            : (controller) => _ReactionPickerButton(
                controller: controller,
                reactionOptions: _defaultReactionOptions,
                selectedReaction: selectedMessageReaction,
                onSelected: (reaction) {
                  _toggleReaction(message: message, reaction: reaction, target: _reactionTargetMessage, removeIfSame: true);
                },
              ),
        showReactionAction: localParticipantReactionName != null && !hasMessageLevelReactions,
        onReactFromMenu: localParticipantReactionName == null
            ? null
            : () {
                _showReactionPickerDialog(
                  context,
                  selectedReaction: selectedMessageReaction,
                  onSelected: (reaction) {
                    _toggleReaction(message: message, reaction: reaction, target: _reactionTargetMessage, removeIfSame: true);
                  },
                );
              },
        attachmentWidgets: [
          for (final indexedAttachment in attachments.indexed)
            _buildAttachmentInThread(
              context,
              message,
              mine,
              indexedAttachment.$2,
              attachmentIndex: indexedAttachment.$1,
              feedImages: feedImages,
            ),
        ],
        trailing: _buildReactionRow(context, message: message, mine: mine, target: _reactionTargetMessage, showAddWhenEmpty: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingApplicationMessages = widget.pendingMessages.where((message) => message.awaitingApplication).toList(growable: false);
    final visibleMessages = messages
        .where(_shouldRenderThreadMessage)
        .where((message) => !pendingApplicationMessages.any((pending) => _threadMessageMatchesPendingAgentMessage(message, pending)))
        .toList();
    const bool bottomAlign = true;
    final feedImages = _collectThreadImages();

    final messageWidgets = <Widget>[];
    for (var message in visibleMessages.indexed) {
      final previous = message.$1 > 0 ? visibleMessages[message.$1 - 1] : null;
      final next = message.$1 < visibleMessages.length - 1 ? visibleMessages[message.$1 + 1] : null;

      final messageWidget = Container(
        key: ValueKey(message.$2.id),
        child: _buildMessage(context, previous, message.$2, next, feedImages: feedImages),
      );

      if (messageWidgets.isNotEmpty) {
        final stackSpacing = _threadFeedStackSpacingBetween(previous, message.$2);
        messageWidgets.insert(0, SizedBox(height: stackSpacing));
      }
      messageWidgets.insert(0, messageWidget);
    }
    final pendingFeedMessages = widget.pendingMessages.where(
      (pending) => _pendingAgentMessageIsOptimisticallyRendered(pending: pending, messages: messages),
    );
    for (final pending in pendingFeedMessages) {
      if (messageWidgets.isNotEmpty) {
        messageWidgets.insert(
          0,
          SizedBox(height: ThreadTypographyOverride.maybeThreadFeedItemSpacingOf(context) ?? ChatThreadMessageView.chatMessageStackSpacing),
        );
      }
      messageWidgets.insert(
        0,
        PendingChatThreadMessage(
          room: room,
          message: pending,
          shouldShowAuthorNames: widget.shouldShowAuthorNames,
          mobileStorageSaveSurfacePresenter: mobileStorageSaveSurfacePresenter,
        ),
      );
    }

    final threadView = ChatThreadViewportBody(
      scrollController: widget.scrollController,
      tapRegionGroupId: widget.composerTapRegionGroupId,
      bottomAlign: bottomAlign,
      centerContent: null,
      bottomSpacer: _statusSlotVisible ? _statusBottomSpacer : 0,
      bottomSpacerKey: _statusBottomSpacerKey,
      bottomSpacerAnimationDuration: _statusAnimationDuration,
      bottomSpacerAnimationCurve: _statusAnimationCurve,
      overlays: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final displayStatus = _statusDisplayText();
              final cancelling = _isCancellingThreadStatusText(displayStatus);
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: chatThreadStatusHorizontalPadding(constraints.maxWidth)),
                child: AnimatedSize(
                  alignment: Alignment.bottomCenter,
                  duration: _statusAnimationDuration,
                  curve: _statusAnimationCurve,
                  child: _statusSlotVisible
                      ? ChatThreadProcessingStatusRow(
                          text: displayStatus,
                          startedAt: showTyping ? threadStatusStartedAt : _lastThreadStatusStartedAt,
                          totalBytes: showTyping ? threadStatusTotalBytes : _lastThreadStatusTotalBytes,
                          linesAdded: showTyping ? threadStatusLinesAdded : _lastThreadStatusLinesAdded,
                          linesRemoved: showTyping ? threadStatusLinesRemoved : _lastThreadStatusLinesRemoved,
                          onCancel: showTyping ? onCancel : null,
                          showCancelButton: (showTyping ? threadStatusMode : _lastThreadStatusMode) != null,
                          cancelEnabled: showTyping && !cancelling,
                        )
                      : const SizedBox.shrink(),
                ),
              );
            },
          ),
        ),
        if (showListening)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 912),
                child: SizedBox(
                  height: 1,
                  child: LinearProgressIndicator(
                    backgroundColor: ShadTheme.of(context).colorScheme.background,
                    color: ShadTheme.of(context).colorScheme.mutedForeground,
                  ),
                ),
              ),
            ),
          ),
      ],
      mobileUnderHeaderContentPadding: widget.mobileUnderHeaderContentPadding,
      children: messageWidgets,
    );
    final threadViewWithContextMenu = _usesMobileContextLayout(context)
        ? threadView
        : CoordinatedShadContextMenuRegion(
            constraints: const BoxConstraints(minWidth: 180),
            tapEnabled: false,
            items: [
              ShadContextMenuItem(
                onPressed: widget.onShowCompletedToolCallsChanged == null
                    ? null
                    : () => widget.onShowCompletedToolCallsChanged!(!widget.showCompletedToolCalls),
                leading: Icon(widget.showCompletedToolCalls ? LucideIcons.squareCheckBig : LucideIcons.square),
                child: const Text("Show tool calls"),
              ),
            ],
            child: threadView,
          );

    return Expanded(
      child: OverlayPortal(
        controller: _imageViewerController,
        overlayLocation: OverlayChildLocation.rootOverlay,
        overlayChildBuilder: (context) {
          if (_overlayImages.isEmpty) {
            return const SizedBox.shrink();
          }
          return ChatThreadImageGalleryPage(
            room: room,
            images: _overlayImages,
            initialIndex: _overlayInitialIndex,
            onClose: _closeThreadImageViewer,
          );
        },
        child: threadViewWithContextMenu,
      ),
    );
  }
}

class ChatThreadEmptyStateContent extends StatelessWidget {
  const ChatThreadEmptyStateContent({super.key, required this.title, this.description, this.titleScaleOverride});

  static const double _descriptionVisibilityMinWidth = 480;
  static const double _mobileScreenWidthMax = 600;

  final String title;
  final String? description;
  final double? titleScaleOverride;

  double _titleScale(double width) {
    if (width >= 820) {
      return 1;
    }
    if (width <= 440) {
      return 0.72;
    }
    return 0.72 + ((width - 440) / 380) * 0.28;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isMobileScreen = MediaQuery.sizeOf(context).width < _mobileScreenWidthMax;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = titleScaleOverride ?? _titleScale(constraints.maxWidth);
        final titleStyle = theme.textTheme.h1;
        final descriptionStyle = theme.textTheme.p.copyWith(height: 24 / 16);
        final titleFontSize = (titleStyle.fontSize ?? 64) * scale;
        final showDescription =
            description != null &&
            description!.trim().isNotEmpty &&
            (constraints.maxWidth >= _descriptionVisibilityMinWidth || isMobileScreen);

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: titleStyle.copyWith(fontSize: titleFontSize),
              ),
              if (showDescription) ...[const SizedBox(height: 8), Text(description!, textAlign: TextAlign.center, style: descriptionStyle)],
            ],
          ),
        );
      },
    );
  }
}

class _ReactionPickerButton extends StatefulWidget {
  const _ReactionPickerButton({
    required this.reactionOptions,
    required this.onSelected,
    this.controller,
    this.selectedReaction,
    this.triggerBuilder,
  });

  final ShadContextMenuController? controller;
  final List<String> reactionOptions;
  final ValueChanged<String> onSelected;
  final String? selectedReaction;
  final Widget Function(VoidCallback onPressed)? triggerBuilder;

  @override
  State<_ReactionPickerButton> createState() => _ReactionPickerButtonState();
}

class _ReactionPickerButtonState extends State<_ReactionPickerButton> {
  late final ShadContextMenuController _internalController = ShadContextMenuController();
  bool _didDispose = false;

  ShadContextMenuController get _controller => widget.controller ?? _internalController;

  void _onSelectReaction(String reaction) {
    widget.onSelected(reaction);
    _controller.hide();
  }

  Future<void> _handleTriggerPressed() async {
    if (_usesNativeMobileReactionFlowDialog(context)) {
      if (_controller.isOpen || _didDispose) {
        return;
      }

      _controller.show();
      try {
        await _showReactionPickerSurface(
          context,
          reactionOptions: widget.reactionOptions,
          selectedReaction: widget.selectedReaction,
          onSelected: widget.onSelected,
        );
      } finally {
        if (!_didDispose) {
          _controller.hide();
        }
      }
      return;
    }

    _controller.toggle();
  }

  @override
  void dispose() {
    _didDispose = true;
    if (widget.controller == null) {
      _internalController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usesNativeMobileFlowDialog = _usesNativeMobileReactionFlowDialog(context);
    final isMobile = _usesMobileContextLayout(context);
    final triggerSize = isMobile ? 40.0 : 30.0;
    final iconSize = isMobile ? 19.0 : 14.0;
    final trigger =
        widget.triggerBuilder?.call(_handleTriggerPressed) ??
        (usesNativeMobileFlowDialog
            ? ShadIconButton.ghost(
                width: triggerSize,
                height: triggerSize,
                padding: EdgeInsets.zero,
                icon: Icon(LucideIcons.smilePlus, size: iconSize),
                onPressed: _handleTriggerPressed,
              )
            : Tooltip(
                message: "Add reaction",
                child: ShadIconButton.ghost(
                  width: triggerSize,
                  height: triggerSize,
                  padding: EdgeInsets.zero,
                  icon: Icon(LucideIcons.smilePlus, size: iconSize),
                  onPressed: _handleTriggerPressed,
                ),
              ));

    if (usesNativeMobileFlowDialog) {
      return trigger;
    }

    return CoordinatedShadContextMenu(
      controller: _controller,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 220),
      estimatedMenuWidth: 220,
      estimatedMenuHeight: 280,
      popoverReverseDuration: _ChatBubble._menuReverseDuration,
      items: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _buildReactionOptionButtons(
                  context: context,
                  reactionOptions: widget.reactionOptions,
                  selectedReaction: widget.selectedReaction,
                  onSelected: _onSelectReaction,
                  buttonSize: 32,
                  emojiSize: 18,
                ),
              ),
            ),
          ),
        ),
      ],
      child: trigger,
    );
  }
}

class _ReactionPickerDesktopDialog extends StatelessWidget {
  const _ReactionPickerDesktopDialog({required this.reactionOptions, required this.selectedReaction, required this.onSelected});

  final List<String> reactionOptions;
  final String? selectedReaction;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: const Text("React"),
      constraints: const BoxConstraints(maxWidth: 320),
      actions: [ShadButton.ghost(onPressed: () => Navigator.of(context).pop(), child: const Text("Close"))],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _buildReactionOptionButtons(
              context: context,
              reactionOptions: reactionOptions,
              selectedReaction: selectedReaction,
              onSelected: (reaction) {
                onSelected(reaction);
                Navigator.of(context).pop();
              },
              buttonSize: 34,
              emojiSize: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionPickerFlowDialog extends StatelessWidget {
  const _ReactionPickerFlowDialog({required this.reactionOptions, required this.selectedReaction, required this.onSelected});

  final List<String> reactionOptions;
  final String? selectedReaction;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = math
        .max(
          280.0,
          math.min(
            mediaQuery.size.height - mediaQuery.padding.top - _mobileReactionFlowDialogViewportTopGap,
            mediaQuery.size.height * _mobileReactionFlowDialogMaxHeightFactor,
          ),
        )
        .toDouble();

    return Padding(
      padding: EdgeInsets.only(top: mediaQuery.padding.top + _mobileReactionFlowDialogViewportTopGap),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _mobileReactionFlowDialogMaxWidth, maxHeight: maxHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(_mobileReactionFlowDialogCornerRadius)),
              border: Border.all(color: theme.colorScheme.border),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: _mobileReactionFlowDialogTopPadding,
                  bottom: mediaQuery.padding.bottom + _mobileReactionFlowDialogBottomPadding,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 40),
                        Expanded(
                          child: Text(
                            "React",
                            textAlign: TextAlign.center,
                            style: theme.textTheme.large.copyWith(color: theme.colorScheme.foreground),
                          ),
                        ),
                        ShadIconButton.ghost(
                          width: 40,
                          height: 40,
                          padding: EdgeInsets.zero,
                          icon: Icon(LucideIcons.x, size: 20, color: theme.colorScheme.foreground),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      fit: FlexFit.loose,
                      child: SingleChildScrollView(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: _buildReactionOptionButtons(
                              context: context,
                              reactionOptions: reactionOptions,
                              selectedReaction: selectedReaction,
                              onSelected: (reaction) {
                                onSelected(reaction);
                                Navigator.of(context).pop();
                              },
                              buttonSize: 48,
                              emojiSize: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadStorageSaveDesktopDialog extends StatelessWidget {
  const _ThreadStorageSaveDesktopDialog({
    required this.room,
    required this.title,
    required this.suggestedFileName,
    required this.fileNameLabel,
    required this.loadContent,
  });

  final RoomClient room;
  final String title;
  final String suggestedFileName;
  final String fileNameLabel;
  final Future<FileContent> Function() loadContent;

  @override
  Widget build(BuildContext context) {
    return _ThreadStorageSaveSurfaceScaffold(
      room: room,
      title: title,
      suggestedFileName: suggestedFileName,
      fileNameLabel: fileNameLabel,
      loadContent: loadContent,
      useMobileFlowPresentation: false,
    );
  }
}

class _ThreadStorageSaveFlowDialog extends StatelessWidget {
  const _ThreadStorageSaveFlowDialog({
    required this.room,
    required this.title,
    required this.suggestedFileName,
    required this.fileNameLabel,
    required this.loadContent,
  });

  final RoomClient room;
  final String title;
  final String suggestedFileName;
  final String fileNameLabel;
  final Future<FileContent> Function() loadContent;

  @override
  Widget build(BuildContext context) {
    return _ThreadStorageSaveSurfaceScaffold(
      room: room,
      title: title,
      suggestedFileName: suggestedFileName,
      fileNameLabel: fileNameLabel,
      loadContent: loadContent,
      useMobileFlowPresentation: true,
    );
  }
}

class _ThreadStorageSaveSurfaceScaffold extends StatefulWidget {
  const _ThreadStorageSaveSurfaceScaffold({
    required this.room,
    required this.title,
    required this.suggestedFileName,
    required this.fileNameLabel,
    required this.loadContent,
    required this.useMobileFlowPresentation,
  });

  final RoomClient room;
  final String title;
  final String suggestedFileName;
  final String fileNameLabel;
  final Future<FileContent> Function() loadContent;
  final bool useMobileFlowPresentation;

  @override
  State<_ThreadStorageSaveSurfaceScaffold> createState() => _ThreadStorageSaveSurfaceScaffoldState();
}

class _ThreadStorageSaveSurfaceScaffoldState extends State<_ThreadStorageSaveSurfaceScaffold> {
  late final TextEditingController _fileNameController = TextEditingController();
  String _selectedFolder = "";
  bool _saving = false;

  String _resolvedFullPath() {
    final rawValue = _fileNameController.text.trim();
    var fullPath = rawValue.isEmpty ? widget.suggestedFileName : rawValue;

    if (!fullPath.contains("/")) {
      fullPath = _selectedFolder.isEmpty ? fullPath : "$_selectedFolder/$fullPath";
    }

    return _applySuggestedFileExtension(fullPath, suggestedFileName: widget.suggestedFileName);
  }

  Future<void> _onSavePressed() async {
    if (_saving) {
      return;
    }

    final fullPath = _resolvedFullPath();
    final exists = await widget.room.storage.exists(fullPath);
    if (exists && mounted) {
      final overwrite = await _showStorageOverwriteConfirmation(
        context,
        title: "File already exists",
        message: "A file at '$fullPath' already exists in room storage. Do you want to overwrite it?",
      );

      if (!overwrite || !mounted) {
        return;
      }
    }

    setState(() {
      _saving = true;
    });

    try {
      final content = await widget.loadContent();
      await widget.room.storage.uploadStream(
        fullPath,
        Stream.value(content.data),
        overwrite: true,
        size: content.data.length,
        name: _defaultSuggestedFileNameFromPath(fullPath),
        mimeType: content.mimeType,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Widget _buildSurfaceBody(BuildContext context) {
    final theme = ShadTheme.of(context);
    final tt = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: theme.colorScheme.background,
              child: FileBrowser(
                onSelectionChanged: (selection) {
                  setState(() {
                    _selectedFolder = selection.join("/");
                  });
                },
                room: widget.room,
                multiple: false,
                selectionMode: FileBrowserSelectionMode.folders,
                rootLabel: "Folders",
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: ShadInputFormField(
            label: Text(widget.fileNameLabel, style: tt.small.copyWith(fontWeight: FontWeight.bold)),
            placeholder: Text(widget.suggestedFileName),
            keyboardType: TextInputType.emailAddress,
            controller: _fileNameController,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileSurface(BuildContext context) {
    final theme = ShadTheme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = math.max(360.0, mediaQuery.size.height - mediaQuery.padding.top - _mobileStorageSaveFlowDialogViewportTopGap);
    return ShadMobileFlowDialogSurface(
      constraints: BoxConstraints(maxWidth: _mobileStorageSaveFlowDialogMaxWidth, minHeight: maxHeight, maxHeight: maxHeight),
      backgroundColor: theme.colorScheme.card,
      radius: const BorderRadius.vertical(top: Radius.circular(28)),
      border: Border.all(color: theme.colorScheme.border),
      shadows: null,
      padding: shadMobileFlowDialogCompactPadding.copyWith(bottom: mediaQuery.padding.bottom + shadMobileFlowDialogCompactPadding.bottom),
      title: ShadMobileFlowDialogCenteredTitleBar(
        title: Text(
          widget.title,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.large.copyWith(color: theme.colorScheme.foreground),
        ),
        onClose: _saving ? null : () => Navigator.of(context).pop(),
      ),
      description: null,
      body: _buildSurfaceBody(context),
      actions: [
        ShadButton.secondary(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text("Cancel")),
        ShadButton(
          onPressed: _saving ? null : _onSavePressed,
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Save"),
        ),
      ],
      gap: 16,
      actionsGap: 12,
      bodyBehavior: ShadMobileFlowDialogBodyBehavior.fill,
      usesHorizontalActionRow: true,
      keyboardInset: mediaQuery.viewInsets.bottom,
      hideActionsWhenKeyboardVisible: false,
    );
  }

  Widget _buildDesktopSurface(BuildContext context) {
    return ShadDialog(
      title: Text(widget.title),
      crossAxisAlignment: CrossAxisAlignment.start,
      constraints: const BoxConstraints(maxWidth: 700, maxHeight: 544),
      scrollable: false,
      actions: [
        ShadButton.secondary(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text("Cancel")),
        ShadButton(
          onPressed: _saving ? null : _onSavePressed,
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Save"),
        ),
      ],
      child: _buildSurfaceBody(context),
    );
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.useMobileFlowPresentation) {
      return _buildMobileSurface(context);
    }

    return _buildDesktopSurface(context);
  }
}

class _AttachmentOptionsButton extends StatefulWidget {
  const _AttachmentOptionsButton({required this.items});

  final List<Widget> items;

  @override
  State<_AttachmentOptionsButton> createState() => _AttachmentOptionsButtonState();
}

class _AttachmentOptionsButtonState extends State<_AttachmentOptionsButton> {
  final ShadContextMenuController _controller = ShadContextMenuController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = ShadTheme.of(context);
    final cs = theme.colorScheme;

    return CoordinatedShadContextMenu(
      controller: _controller,
      constraints: const BoxConstraints(minWidth: 180),
      estimatedMenuWidth: 180,
      estimatedMenuHeight: widget.items.length * 40.0 + 8.0,
      items: widget.items,
      child: Tooltip(
        message: "Attachment options",
        child: ShadIconButton.ghost(
          width: 30,
          height: 30,
          padding: EdgeInsets.zero,
          icon: Icon(LucideIcons.ellipsis, size: 18, color: cs.mutedForeground),
          onPressed: _controller.toggle,
        ),
      ),
    );
  }
}

class _ThreadImageRecord {
  const _ThreadImageRecord({required this.data, required this.mimeType});

  final Uint8List data;
  final String mimeType;
}

_ThreadImageRecord? _threadImageRecordFromDataUri(String imageUri, {String? fallbackMimeType}) {
  final trimmed = imageUri.trim();
  if (!trimmed.startsWith("data:")) {
    return null;
  }

  final commaIndex = trimmed.indexOf(",");
  if (commaIndex == -1) {
    return null;
  }

  final metadata = trimmed.substring(5, commaIndex);
  final encodedData = trimmed.substring(commaIndex + 1).trim();
  if (encodedData.isEmpty) {
    return null;
  }

  final metadataParts = metadata.split(";");
  final parsedMimeType = metadataParts.isNotEmpty ? metadataParts.first.trim() : "";
  final fallback = fallbackMimeType?.trim() ?? "";
  final mimeType = parsedMimeType.isNotEmpty ? parsedMimeType : (fallback.isNotEmpty ? fallback : "image/png");
  final isBase64 = metadataParts.any((part) => part.trim().toLowerCase() == "base64");

  try {
    final data = isBase64 ? base64Decode(encodedData) : Uint8List.fromList(utf8.encode(Uri.decodeComponent(encodedData)));
    return _ThreadImageRecord(data: data, mimeType: mimeType);
  } catch (_) {
    return null;
  }
}

Future<_ThreadImageRecord?> _loadGeneratedThreadImageRecord(RoomClient room, {required String imageId, String? fallbackMimeType}) async {
  final trimmedImageId = imageId.trim();
  if (trimmedImageId.isEmpty) {
    return null;
  }

  try {
    final table = await room.datasets.searchTable(
      table: "images",
      where: {"id": trimmedImageId},
      limit: 1,
      select: const ["data", "mime_type"],
    );
    final rows = table.toRows();
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final rawData = row["data"];
    final Uint8List data;
    if (rawData is Uint8List) {
      data = rawData;
    } else if (rawData is List<int>) {
      data = Uint8List.fromList(rawData);
    } else {
      return null;
    }

    final rawMimeType = row["mime_type"];
    final storedMimeType = rawMimeType is String ? rawMimeType.trim() : "";
    final fallback = fallbackMimeType?.trim() ?? "";
    final mimeType = storedMimeType.isNotEmpty ? storedMimeType : (fallback.isNotEmpty ? fallback : "image/png");
    return _ThreadImageRecord(data: data, mimeType: mimeType);
  } catch (_) {
    return null;
  }
}

Future<_ThreadImageRecord?> _loadGeneratedThreadImageRecordFromUri(
  RoomClient? room, {
  required String imageUri,
  String? fallbackMimeType,
}) async {
  final dataUriRecord = _threadImageRecordFromDataUri(imageUri, fallbackMimeType: fallbackMimeType);
  if (dataUriRecord != null) {
    return dataUriRecord;
  }

  if (room == null) {
    return null;
  }

  final parsed = Uri.tryParse(imageUri.trim());
  if (parsed == null || parsed.scheme != 'dataset') {
    return null;
  }
  final imageId = parsed.queryParameters['id']?.trim();
  if (imageId == null || imageId.isEmpty) {
    return null;
  }

  final pathParts = <String>[
    if (parsed.host.trim().isNotEmpty) parsed.host.trim(),
    ...parsed.pathSegments.where((part) => part.trim().isNotEmpty),
  ];
  if (pathParts.isEmpty) {
    return null;
  }
  final tableName = pathParts.last;
  final namespace = pathParts.length > 1 ? pathParts.sublist(0, pathParts.length - 1) : null;

  try {
    final table = await room.datasets.searchTable(
      table: tableName,
      namespace: namespace,
      where: {"id": imageId},
      limit: 1,
      select: const ["data", "mime_type"],
    );
    final rows = table.toRows();
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final rawData = row["data"];
    final Uint8List data;
    if (rawData is Uint8List) {
      data = rawData;
    } else if (rawData is List<int>) {
      data = Uint8List.fromList(rawData);
    } else {
      return null;
    }

    final rawMimeType = row["mime_type"];
    final storedMimeType = rawMimeType is String ? rawMimeType.trim() : "";
    final fallback = fallbackMimeType?.trim() ?? "";
    final mimeType = storedMimeType.isNotEmpty ? storedMimeType : (fallback.isNotEmpty ? fallback : "image/png");
    return _ThreadImageRecord(data: data, mimeType: mimeType);
  } catch (_) {
    return null;
  }
}

class _ThreadImageLookup extends StatefulWidget {
  const _ThreadImageLookup({required this.lookupKey, required this.readCached, required this.lookupImage, required this.builder});

  final Object lookupKey;
  final _ThreadImageRecord? Function() readCached;
  final Future<_ThreadImageRecord?> Function() lookupImage;
  final Widget Function(BuildContext context, AsyncSnapshot<_ThreadImageRecord?> snapshot) builder;

  @override
  State<_ThreadImageLookup> createState() => _ThreadImageLookupState();
}

class _ThreadImageLookupState extends State<_ThreadImageLookup> {
  late Future<_ThreadImageRecord?> _lookup;

  Future<_ThreadImageRecord?> _resolveLookup() {
    final cached = widget.readCached();
    if (cached != null) {
      return SynchronousFuture<_ThreadImageRecord?>(cached);
    }
    return widget.lookupImage();
  }

  @override
  void initState() {
    super.initState();
    _lookup = _resolveLookup();
  }

  @override
  void didUpdateWidget(covariant _ThreadImageLookup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lookupKey != widget.lookupKey) {
      _lookup = _resolveLookup();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ThreadImageRecord?>(future: _lookup, builder: widget.builder);
  }
}

class ChatThreadFeedImage {
  const ChatThreadFeedImage({
    required this.attachmentElementId,
    required this.imageId,
    this.path,
    this.imageUri,
    this.mimeType,
    this.status,
    this.statusDetail,
    this.widthPx,
    this.heightPx,
  });

  final String attachmentElementId;
  final String imageId;
  final String? path;
  final String? imageUri;
  final String? mimeType;
  final String? status;
  final String? statusDetail;
  final double? widthPx;
  final double? heightPx;
}

class ChatThreadImageAttachment extends StatefulWidget {
  const ChatThreadImageAttachment({
    super.key,
    this.room,
    required this.imageId,
    this.imageUri,
    this.fallbackMimeType,
    this.status,
    this.statusDetail,
    this.widthPx,
    this.heightPx,
    this.roundedCorners = true,
    this.onOpenFullscreen,
  });

  final RoomClient? room;
  final String? imageId;
  final String? imageUri;
  final String? fallbackMimeType;
  final String? status;
  final String? statusDetail;
  final double? widthPx;
  final double? heightPx;
  final bool roundedCorners;
  final VoidCallback? onOpenFullscreen;

  @override
  State<ChatThreadImageAttachment> createState() => _ChatThreadImageAttachmentState();
}

class _ChatThreadImageAttachmentState extends State<ChatThreadImageAttachment> {
  late Future<_ThreadImageRecord?> _lookup;

  @override
  void initState() {
    super.initState();
    _lookup = _loadImage();
  }

  @override
  void didUpdateWidget(covariant ChatThreadImageAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageId != widget.imageId || oldWidget.imageUri != widget.imageUri || oldWidget.room != widget.room) {
      _lookup = _loadImage();
    }
  }

  Future<_ThreadImageRecord?> _loadImage() async {
    final imageUri = widget.imageUri;
    if (imageUri != null && imageUri.trim().isNotEmpty) {
      final record = await _loadGeneratedThreadImageRecordFromUri(
        widget.room,
        imageUri: imageUri,
        fallbackMimeType: widget.fallbackMimeType,
      );
      if (record != null) {
        return record;
      }
    }

    final imageId = widget.imageId;
    if (imageId == null || imageId.trim().isEmpty) {
      return null;
    }

    final room = widget.room;
    if (room == null) {
      return null;
    }

    return _loadGeneratedThreadImageRecord(room, imageId: imageId, fallbackMimeType: widget.fallbackMimeType);
  }

  bool _isGeneratingStatus(String? status) {
    if (status == null || status.trim().isEmpty) {
      return false;
    }

    final normalized = status.toLowerCase();
    return normalized == "generating" ||
        normalized == "in_progress" ||
        normalized == "queued" ||
        normalized == "running" ||
        normalized == "pending";
  }

  bool _isFailedStatus(String? status) {
    if (status == null) {
      return false;
    }
    final normalized = status.toLowerCase();
    return normalized == "failed" || normalized == "cancelled";
  }

  Size _displaySize() {
    const maxPreviewEdge = 312.5;
    const fallbackPreviewEdge = 312.5;

    final rawWidth = widget.widthPx;
    final rawHeight = widget.heightPx;
    if (rawWidth == null || rawHeight == null || rawWidth <= 0 || rawHeight <= 0) {
      return const Size(fallbackPreviewEdge, fallbackPreviewEdge);
    }

    final largestEdge = math.max(rawWidth, rawHeight);
    if (largestEdge <= maxPreviewEdge) {
      return Size(rawWidth, rawHeight);
    }

    final scale = maxPreviewEdge / largestEdge;
    return Size(rawWidth * scale, rawHeight * scale);
  }

  String _ensureFileNameExtension(String rawPath, String mimeType) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return _ImageMime.suggestedFileName(mimeType);
    }

    final slash = trimmed.lastIndexOf("/");
    final fileName = slash == -1 ? trimmed : trimmed.substring(slash + 1);

    if (fileName.isEmpty) {
      final suggested = _ImageMime.suggestedFileName(mimeType);
      return trimmed.endsWith("/") ? "$trimmed$suggested" : "$trimmed/$suggested";
    }

    if (fileName.contains(".")) {
      return trimmed;
    }

    return "$trimmed.${_ImageMime.defaultExtension(mimeType)}";
  }

  Future<void> _onCopyImage(_ThreadImageRecord image) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return;
    }

    final mimeType = image.mimeType.trim().toLowerCase();
    final format = _ImageMime.clipboardFormat(mimeType);
    final item = DataWriterItem(suggestedName: _ImageMime.suggestedFileName(mimeType));
    if (format != null) {
      item.add(format(image.data));
    } else {
      item.add(EncodedData([raw.DataRepresentation.simple(format: mimeType, data: image.data)]));
    }

    await clipboard.write([item]);
  }

  Future<void> _onSaveImage(_ThreadImageRecord image) async {
    final room = widget.room;
    if (room == null) {
      return;
    }
    final fileNameController = TextEditingController(text: _ImageMime.suggestedFileName(image.mimeType));
    String selectedFolder = "";

    await showShadDialog<void>(
      context: context,
      builder: (context) {
        final theme = ShadTheme.of(context);
        final tt = theme.textTheme;

        return ShadDialog(
          title: const Text("Save image as ..."),
          crossAxisAlignment: CrossAxisAlignment.start,
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 544),
          scrollable: false,
          actions: [
            ShadButton.secondary(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
            ShadButton(
              onPressed: () async {
                final value = fileNameController.text.trim();
                var fullPath = value.isEmpty ? _ImageMime.suggestedFileName(image.mimeType) : value;

                if (!fullPath.contains("/")) {
                  fullPath = selectedFolder.isEmpty ? fullPath : "$selectedFolder/$fullPath";
                }
                fullPath = _ensureFileNameExtension(fullPath, image.mimeType);

                final exists = await room.storage.exists(fullPath);
                if (exists && context.mounted) {
                  final overwrite = await showShadDialog<bool>(
                    context: context,
                    builder: (context) => ShadDialog(
                      title: const Text("File already exists"),
                      description: Text("A file at '$fullPath' already exists in room storage. Do you want to overwrite it?"),
                      actions: [
                        ShadButton.secondary(
                          onPressed: () {
                            Navigator.of(context).pop(false);
                          },
                          child: const Text("Cancel"),
                        ),
                        ShadButton(
                          onPressed: () {
                            Navigator.of(context).pop(true);
                          },
                          child: const Text("Overwrite"),
                        ),
                      ],
                    ),
                  );

                  if (overwrite != true) {
                    return;
                  }
                }

                await room.storage.uploadStream(fullPath, Stream.value(image.data), overwrite: true, size: image.data.length);

                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text("Save"),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FileBrowser(
                  onSelectionChanged: (selection) {
                    selectedFolder = selection.join("/");
                  },
                  room: room,
                  multiple: false,
                  selectionMode: FileBrowserSelectionMode.folders,
                  rootLabel: "Files",
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ShadInputFormField(
                  label: Text("File name or path", style: tt.small.copyWith(fontWeight: FontWeight.bold)),
                  placeholder: Text(_ImageMime.suggestedFileName(image.mimeType)),
                  controller: fileNameController,
                ),
              ),
            ],
          ),
        );
      },
    );
    fileNameController.dispose();
  }

  Widget _wrapContextMenu({required _ThreadImageRecord image, required Widget child}) {
    if (_usesMobileContextLayout(context)) {
      return child;
    }

    return CoordinatedShadContextMenuRegion(
      items: [
        if (widget.room != null) ShadContextMenuItem(height: 40, onPressed: () => _onSaveImage(image), child: const Text("Save As...")),
        ShadContextMenuItem(height: 40, onPressed: () => _onCopyImage(image), child: const Text("Copy")),
      ],
      child: child,
    );
  }

  Widget _wrapWithCorners(Widget child) {
    if (!widget.roundedCorners) {
      return child;
    }
    return ClipRRect(borderRadius: BorderRadius.circular(16), child: child);
  }

  Widget _wrapTapTarget(Widget child) {
    if (widget.onOpenFullscreen == null) {
      return child;
    }

    return ShadGestureDetector(cursor: SystemMouseCursors.zoomIn, onTap: widget.onOpenFullscreen, child: child);
  }

  Widget _buildPlaceholder(BuildContext context, {required bool showSpinner, String? label}) {
    final size = _displaySize();
    final trimmedLabel = label == null ? "" : label.trim();

    return SizedBox(
      width: size.width,
      height: size.height,
      child: _wrapWithCorners(
        ColoredBox(
          color: ShadTheme.of(context).colorScheme.background,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSpinner)
                  SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(LucideIcons.imageOff, size: 20, color: ShadTheme.of(context).colorScheme.mutedForeground),
                if (trimmedLabel.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      trimmedLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: ShadTheme.of(context).textTheme.small.copyWith(color: ShadTheme.of(context).colorScheme.mutedForeground),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status?.trim();
    final hasImageId = widget.imageId != null && widget.imageId!.trim().isNotEmpty;
    final imageUri = widget.imageUri?.trim();
    final hasImageUri = imageUri != null && imageUri.isNotEmpty;
    final statusDetail = widget.statusDetail?.trim();

    if (!hasImageId && !hasImageUri) {
      if (_isFailedStatus(status)) {
        return FileDefaultPreviewCard(icon: LucideIcons.imageOff, text: statusDetail?.isNotEmpty == true ? statusDetail! : "Image failed");
      }
      final label = _isGeneratingStatus(status) ? "Generating image" : "Loading image";
      return _buildPlaceholder(context, showSpinner: true, label: statusDetail?.isNotEmpty == true ? statusDetail : label);
    }

    final parsedUri = imageUri == null ? null : Uri.tryParse(imageUri);
    if (!hasImageId && parsedUri != null && (parsedUri.scheme == "http" || parsedUri.scheme == "https")) {
      final size = _displaySize();
      return _wrapTapTarget(
        SizedBox(
          width: size.width,
          height: size.height,
          child: _wrapWithCorners(
            Image.network(
              imageUri!,
              fit: (widget.widthPx != null && widget.heightPx != null) ? BoxFit.contain : BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const FileDefaultPreviewCard(icon: LucideIcons.imageOff, text: "Image unavailable"),
            ),
          ),
        ),
      );
    }

    return FutureBuilder<_ThreadImageRecord?>(
      future: _lookup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildPlaceholder(context, showSpinner: true);
        }

        final image = snapshot.data;
        if (image == null) {
          if (_isGeneratingStatus(status)) {
            return _buildPlaceholder(
              context,
              showSpinner: true,
              label: statusDetail?.isNotEmpty == true ? statusDetail : "Generating image",
            );
          }
          if (_isFailedStatus(status)) {
            return FileDefaultPreviewCard(
              icon: LucideIcons.imageOff,
              text: statusDetail?.isNotEmpty == true ? statusDetail! : "Image failed",
            );
          }
          return const FileDefaultPreviewCard(icon: LucideIcons.imageOff, text: "Image unavailable");
        }

        final imageWidget = _ImageMime.isSvg(image.mimeType)
            ? SvgPicture.memory(image.data, fit: (widget.widthPx != null && widget.heightPx != null) ? BoxFit.contain : BoxFit.cover)
            : Image.memory(image.data, fit: (widget.widthPx != null && widget.heightPx != null) ? BoxFit.contain : BoxFit.cover);
        final size = _displaySize();

        final imageContainer = SizedBox(width: size.width, height: size.height, child: _wrapWithCorners(imageWidget));
        return _wrapContextMenu(image: image, child: _wrapTapTarget(imageContainer));
      },
    );
  }
}

class ChatThreadImageGalleryPage extends StatefulWidget {
  const ChatThreadImageGalleryPage({super.key, this.room, required this.images, required this.initialIndex, required this.onClose});

  final RoomClient? room;
  final List<ChatThreadFeedImage> images;
  final int initialIndex;
  final VoidCallback onClose;

  @override
  State<ChatThreadImageGalleryPage> createState() => _ThreadImageGalleryPageState();
}

class _ThreadImageGalleryPageState extends State<ChatThreadImageGalleryPage> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changePage(int nextIndex) {
    if (nextIndex < 0 || nextIndex >= widget.images.length) {
      return;
    }
    _controller.animateToPage(nextIndex, duration: const Duration(milliseconds: 180), curve: Curves.easeInOut);
  }

  String _ensureFileNameExtension(String rawPath, String mimeType) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return _ImageMime.suggestedFileName(mimeType);
    }

    final slash = trimmed.lastIndexOf("/");
    final fileName = slash == -1 ? trimmed : trimmed.substring(slash + 1);

    if (fileName.isEmpty) {
      final suggested = _ImageMime.suggestedFileName(mimeType);
      return trimmed.endsWith("/") ? "$trimmed$suggested" : "$trimmed/$suggested";
    }

    if (fileName.contains(".")) {
      return trimmed;
    }

    return "$trimmed.${_ImageMime.defaultExtension(mimeType)}";
  }

  Future<_ThreadImageRecord?> _loadCurrentImage() async {
    final entry = widget.images[_currentIndex];
    final room = widget.room;
    final path = entry.path?.trim();
    if (room != null && path != null && path.isNotEmpty) {
      final file = await room.storage.download(path);
      final mimeType = file.mimeType.trim().isNotEmpty ? file.mimeType.trim() : (entry.mimeType ?? "image/png");
      return _ThreadImageRecord(data: file.data, mimeType: mimeType);
    }

    final imageUri = entry.imageUri?.trim();
    if (imageUri != null && imageUri.isNotEmpty) {
      final record = await _loadGeneratedThreadImageRecordFromUri(widget.room, imageUri: imageUri, fallbackMimeType: entry.mimeType);
      if (record != null) {
        return record;
      }
    }
    if (entry.imageId.trim().isEmpty) {
      return null;
    }
    if (room == null) {
      return null;
    }
    return _loadGeneratedThreadImageRecord(room, imageId: entry.imageId, fallbackMimeType: entry.mimeType);
  }

  Future<void> _copyImageRecord(_ThreadImageRecord image) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return;
    }

    final mimeType = image.mimeType.trim().toLowerCase();
    final format = _ImageMime.clipboardFormat(mimeType);
    final item = DataWriterItem(suggestedName: _ImageMime.suggestedFileName(mimeType));
    if (format != null) {
      item.add(format(image.data));
    } else {
      item.add(EncodedData([raw.DataRepresentation.simple(format: mimeType, data: image.data)]));
    }

    await clipboard.write([item]);
  }

  Future<void> _onCopyCurrentImage() async {
    final image = await _loadCurrentImage();
    if (image == null) {
      return;
    }
    await _copyImageRecord(image);
  }

  Future<void> _saveImageRecord(_ThreadImageRecord image) async {
    if (!mounted) {
      return;
    }
    final room = widget.room;
    if (room == null) {
      return;
    }
    final fileNameController = TextEditingController(text: _ImageMime.suggestedFileName(image.mimeType));
    String selectedFolder = "";

    await showShadDialog<void>(
      context: context,
      builder: (context) {
        final theme = ShadTheme.of(context);
        final tt = theme.textTheme;

        return ShadDialog(
          title: const Text("Save image as ..."),
          crossAxisAlignment: CrossAxisAlignment.start,
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 544),
          scrollable: false,
          actions: [
            ShadButton.secondary(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
            ShadButton(
              onPressed: () async {
                final value = fileNameController.text.trim();
                var fullPath = value.isEmpty ? _ImageMime.suggestedFileName(image.mimeType) : value;

                if (!fullPath.contains("/")) {
                  fullPath = selectedFolder.isEmpty ? fullPath : "$selectedFolder/$fullPath";
                }
                fullPath = _ensureFileNameExtension(fullPath, image.mimeType);

                final exists = await room.storage.exists(fullPath);
                if (exists && context.mounted) {
                  final overwrite = await showShadDialog<bool>(
                    context: context,
                    builder: (context) => ShadDialog(
                      title: const Text("File already exists"),
                      description: Text("A file at '$fullPath' already exists in room storage. Do you want to overwrite it?"),
                      actions: [
                        ShadButton.secondary(
                          onPressed: () {
                            Navigator.of(context).pop(false);
                          },
                          child: const Text("Cancel"),
                        ),
                        ShadButton(
                          onPressed: () {
                            Navigator.of(context).pop(true);
                          },
                          child: const Text("Overwrite"),
                        ),
                      ],
                    ),
                  );

                  if (overwrite != true) {
                    return;
                  }
                }

                await room.storage.uploadStream(fullPath, Stream.value(image.data), overwrite: true, size: image.data.length);

                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text("Save"),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FileBrowser(
                  onSelectionChanged: (selection) {
                    selectedFolder = selection.join("/");
                  },
                  room: room,
                  multiple: false,
                  selectionMode: FileBrowserSelectionMode.folders,
                  rootLabel: "Files",
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ShadInputFormField(
                  label: Text("File name or path", style: tt.small.copyWith(fontWeight: FontWeight.bold)),
                  placeholder: Text(_ImageMime.suggestedFileName(image.mimeType)),
                  controller: fileNameController,
                ),
              ),
            ],
          ),
        );
      },
    );
    fileNameController.dispose();
  }

  Future<void> _onSaveCurrentImage() async {
    final image = await _loadCurrentImage();
    if (image == null) {
      return;
    }
    await _saveImageRecord(image);
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = _currentIndex > 0;
    final canGoForward = _currentIndex < widget.images.length - 1;

    return Positioned.fill(
      child: Material(
        color: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.images.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final image = widget.images[index];
                    return _ThreadFullscreenImage(
                      room: widget.room,
                      path: image.path,
                      imageId: image.imageId,
                      imageUri: image.imageUri,
                      fallbackMimeType: image.mimeType,
                      status: image.status,
                      statusDetail: image.statusDetail,
                      onCopyImage: _copyImageRecord,
                      onSaveImage: widget.room == null ? null : _saveImageRecord,
                    );
                  },
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: ShadIconButton.ghost(
                  icon: Icon(LucideIcons.x, color: Colors.white),
                  onPressed: widget.onClose,
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    ShadButton.ghost(
                      onPressed: _onCopyCurrentImage,
                      leading: const Icon(LucideIcons.copy, size: 16, color: Colors.white),
                      child: Text("Copy", style: ShadTheme.of(context).textTheme.small.copyWith(color: Colors.white)),
                    ),
                    ShadButton.ghost(
                      onPressed: widget.room == null ? null : _onSaveCurrentImage,
                      leading: const Icon(LucideIcons.save, size: 16, color: Colors.white),
                      child: Text("Save As...", style: ShadTheme.of(context).textTheme.small.copyWith(color: Colors.white)),
                    ),
                  ],
                ),
              ),
              if (widget.images.length > 1)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Text(
                    "${_currentIndex + 1} / ${widget.images.length}",
                    style: ShadTheme.of(context).textTheme.small.copyWith(color: Colors.white.withAlpha(220)),
                  ),
                ),
              if (widget.images.length > 1)
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: ShadIconButton.ghost(
                      icon: Icon(LucideIcons.chevronLeft, color: canGoBack ? Colors.white : Colors.white30),
                      onPressed: canGoBack ? () => _changePage(_currentIndex - 1) : null,
                    ),
                  ),
                ),
              if (widget.images.length > 1)
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: ShadIconButton.ghost(
                      icon: Icon(LucideIcons.chevronRight, color: canGoForward ? Colors.white : Colors.white30),
                      onPressed: canGoForward ? () => _changePage(_currentIndex + 1) : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadFullscreenImage extends StatelessWidget {
  const _ThreadFullscreenImage({
    required this.room,
    required this.imageId,
    this.path,
    this.imageUri,
    this.fallbackMimeType,
    this.status,
    this.statusDetail,
    this.onCopyImage,
    this.onSaveImage,
  });

  final RoomClient? room;
  final String imageId;
  final String? path;
  final String? imageUri;
  final String? fallbackMimeType;
  final String? status;
  final String? statusDetail;
  final Future<void> Function(_ThreadImageRecord image)? onCopyImage;
  final Future<void> Function(_ThreadImageRecord image)? onSaveImage;

  Future<_ThreadImageRecord?> _loadImage() async {
    final roomClient = room;
    final imagePath = path?.trim();
    if (roomClient != null && imagePath != null && imagePath.isNotEmpty) {
      final file = await roomClient.storage.download(imagePath);
      final mimeType = file.mimeType.trim().isNotEmpty ? file.mimeType.trim() : (fallbackMimeType ?? "image/png");
      return _ThreadImageRecord(data: file.data, mimeType: mimeType);
    }

    final uri = imageUri?.trim();
    if (uri != null && uri.isNotEmpty) {
      final record = await _loadGeneratedThreadImageRecordFromUri(room, imageUri: uri, fallbackMimeType: fallbackMimeType);
      if (record != null) {
        return record;
      }
    }
    if (imageId.trim().isEmpty) {
      return null;
    }
    if (roomClient == null) {
      return null;
    }
    return _loadGeneratedThreadImageRecord(roomClient, imageId: imageId, fallbackMimeType: fallbackMimeType);
  }

  bool _isGeneratingStatus(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }

    final normalized = value.toLowerCase();
    return normalized == "generating" ||
        normalized == "in_progress" ||
        normalized == "queued" ||
        normalized == "running" ||
        normalized == "pending";
  }

  bool _isFailedStatus(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    final normalized = value.toLowerCase();
    return normalized == "failed" || normalized == "cancelled";
  }

  @override
  Widget build(BuildContext context) {
    final detail = statusDetail?.trim();
    final normalizedStatus = status?.trim();
    final uri = imageUri?.trim();
    final parsedUri = uri == null ? null : Uri.tryParse(uri);

    if (imageId.trim().isEmpty && uri != null && parsedUri != null && (parsedUri.scheme == "http" || parsedUri.scheme == "https")) {
      return InteractiveViewer2(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Image.network(
              uri,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Text("Image unavailable", style: ShadTheme.of(context).textTheme.p.copyWith(color: Colors.white70)),
            ),
          ),
        ),
      );
    }

    return FutureBuilder<_ThreadImageRecord?>(
      future: _loadImage(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        final image = snapshot.data;
        if (image == null) {
          if (_isGeneratingStatus(normalizedStatus)) {
            return Center(
              child: Text(
                detail?.isNotEmpty == true ? detail! : "Generating image",
                style: ShadTheme.of(context).textTheme.p.copyWith(color: Colors.white70),
              ),
            );
          }

          final message = _isFailedStatus(normalizedStatus) ? (detail?.isNotEmpty == true ? detail! : "Image failed") : "Image unavailable";
          return Center(
            child: Text(message, style: ShadTheme.of(context).textTheme.p.copyWith(color: Colors.white70)),
          );
        }

        final imageWidget = _ImageMime.isSvg(image.mimeType)
            ? SvgPicture.memory(image.data, fit: BoxFit.contain)
            : Image.memory(image.data, fit: BoxFit.contain);

        final viewer = InteractiveViewer2(
          child: Center(
            child: Padding(padding: const EdgeInsets.all(24), child: imageWidget),
          ),
        );
        if (onCopyImage == null && onSaveImage == null) {
          return viewer;
        }

        return CoordinatedShadContextMenuRegion(
          items: [
            if (onSaveImage != null) ShadContextMenuItem(height: 40, onPressed: () => onSaveImage!(image), child: const Text("Save As...")),
            if (onCopyImage != null) ShadContextMenuItem(height: 40, onPressed: () => onCopyImage!(image), child: const Text("Copy")),
          ],
          child: viewer,
        );
      },
    );
  }
}

class _CyclingProgressIndicator extends StatefulWidget {
  const _CyclingProgressIndicator({this.strokeWidth = 2});

  final double strokeWidth;

  @override
  State<_CyclingProgressIndicator> createState() => _CyclingProgressIndicatorState();
}

class _CyclingProgressIndicatorState extends State<_CyclingProgressIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _colorAt(BuildContext context, double t) {
    final colorScheme = ShadTheme.of(context).colorScheme;
    final palette = [colorScheme.primary, colorScheme.foreground, colorScheme.mutedForeground, colorScheme.primary];

    final segmentCount = palette.length - 1;
    final scaled = t * segmentCount;
    final index = scaled.floor().clamp(0, segmentCount - 1);
    final localT = (scaled - index).clamp(0.0, 1.0);
    final eased = Curves.easeInOut.transform(localT);
    return Color.lerp(palette[index], palette[index + 1], eased) ?? colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CircularProgressIndicator(
        strokeWidth: widget.strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(_colorAt(context, _controller.value)),
      ),
    );
  }
}

String formatChatThreadStatusText(String text, {DateTime? startedAt, int? totalBytes, int? linesAdded, int? linesRemoved}) {
  if (linesAdded != null || linesRemoved != null) {
    final added = linesAdded != null ? "+${_formatGroupedStatusByteDigits(linesAdded)}" : null;
    final removed = linesRemoved != null ? "-${_formatGroupedStatusByteDigits(linesRemoved)}" : null;
    return [text, ?added, ?removed].join(" ");
  }
  if (totalBytes != null && totalBytes > 100) {
    return "$text ${_formatStatusByteCount(totalBytes)}";
  }
  if (startedAt == null) {
    return text;
  }

  final elapsed = DateTime.now().difference(startedAt);
  final seconds = _clampedElapsedSeconds(elapsed);
  if (seconds == 0) {
    return text;
  }
  return "$text ${_formatStatusSecondCount(seconds)}";
}

String _formatStatusByteCount(int value) {
  return "${_formatGroupedStatusByteDigits(value)} bytes";
}

int _clampedElapsedSeconds(Duration elapsed) {
  return elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
}

String _formatStatusSecondCount(int value) {
  return "$value ${_formatStatusSecondUnit(value)}";
}

String _formatStatusSecondUnit(int value) {
  return value == 1 ? "second" : "seconds";
}

String _formatGroupedStatusByteDigits(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 == 0) {
      buffer.write(",");
    }
    buffer.write(text[index]);
  }
  return buffer.toString();
}

LinearGradient _processingSweepGradient(BuildContext context, {required double t}) {
  final colorScheme = ShadTheme.of(context).colorScheme;
  final centerX = -1.4 + (t * 2.8);
  final highlight = colorScheme.background.withAlpha(210);

  return LinearGradient(
    begin: Alignment(centerX - 0.45, 0),
    end: Alignment(centerX + 0.45, 0),
    colors: [Colors.transparent, highlight, Colors.transparent],
    stops: const [0.0, 0.5, 1.0],
  );
}

Shader _processingSweepShader(BuildContext context, Rect rect, {required double t}) {
  return _processingSweepGradient(context, t: t).createShader(rect);
}

class _ProcessingSweepOverlay extends StatefulWidget {
  const _ProcessingSweepOverlay();

  @override
  State<_ProcessingSweepOverlay> createState() => _ProcessingSweepOverlayState();
}

class _ProcessingSweepOverlayState extends State<_ProcessingSweepOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(gradient: _processingSweepGradient(context, t: _controller.value)),
      ),
    );
  }
}

class ChatThreadProcessingSweepText extends StatelessWidget {
  const ChatThreadProcessingSweepText({
    super.key,
    required this.text,
    required this.style,
    this.animate = true,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final bool animate;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    if (!animate) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow, softWrap: softWrap, textAlign: textAlign);
    }

    return _ProcessingStatusText(
      text: text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      textAlign: textAlign,
    );
  }
}

class _ProcessingStatusText extends StatefulWidget {
  const _ProcessingStatusText({required this.text, required this.style, this.maxLines, this.overflow, this.softWrap, this.textAlign});

  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final TextAlign? textAlign;

  @override
  State<_ProcessingStatusText> createState() => _ProcessingStatusTextState();
}

class _ProcessingStatusTextState extends State<_ProcessingStatusText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final text = Text(
          widget.text,
          style: widget.style,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          softWrap: widget.softWrap,
          textAlign: widget.textAlign,
        );
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            text,
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) => _processingSweepShader(context, rect, t: _controller.value),
              child: Text(
                widget.text,
                style: widget.style.copyWith(color: Colors.white),
                maxLines: widget.maxLines,
                overflow: widget.overflow,
                softWrap: widget.softWrap,
                textAlign: widget.textAlign,
              ),
            ),
          ],
        );
      },
    );
  }
}

bool _isCancellingThreadStatusText(String? status) {
  if (status == null) {
    return false;
  }

  final normalized = status.trim().toLowerCase();
  return normalized == "cancelling" || normalized == "canceling";
}

class ChatThreadProcessingStatusRow extends StatefulWidget {
  const ChatThreadProcessingStatusRow({
    super.key,
    required this.text,
    this.startedAt,
    this.totalBytes,
    this.linesAdded,
    this.linesRemoved,
    this.onCancel,
    this.showCancelButton = false,
    this.cancelEnabled = true,
  });

  final String text;
  final DateTime? startedAt;
  final int? totalBytes;
  final int? linesAdded;
  final int? linesRemoved;
  final VoidCallback? onCancel;
  final bool showCancelButton;
  final bool cancelEnabled;

  @override
  State<ChatThreadProcessingStatusRow> createState() => _ChatThreadProcessingStatusRowState();
}

class _ChatThreadProcessingStatusRowState extends State<ChatThreadProcessingStatusRow> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ChatThreadProcessingStatusRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt ||
        oldWidget.totalBytes != widget.totalBytes ||
        oldWidget.linesAdded != widget.linesAdded ||
        oldWidget.linesRemoved != widget.linesRemoved) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    final shouldTick = widget.startedAt != null && !_shouldDisplayBytes && !_shouldDisplayLineCounts;
    if (!shouldTick) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }

    if (_ticker != null) {
      return;
    }

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  String _displayText() {
    return formatChatThreadStatusText(
      widget.text,
      startedAt: widget.startedAt,
      totalBytes: widget.totalBytes,
      linesAdded: widget.linesAdded,
      linesRemoved: widget.linesRemoved,
    );
  }

  bool get _shouldDisplayBytes => widget.totalBytes != null && widget.totalBytes! > 100;
  bool get _shouldDisplayLineCounts => widget.linesAdded != null || widget.linesRemoved != null;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final cancelButtonColor = widget.cancelEnabled ? theme.colorScheme.foreground : theme.colorScheme.muted;
    final cancelIconColor = widget.cancelEnabled ? theme.colorScheme.background : theme.colorScheme.mutedForeground;
    final displayText = _displayText();
    final statusTextStyle = threadTypographyTextStyle(context, TextStyle(fontSize: 13, color: theme.colorScheme.mutedForeground));
    final elapsedSeconds = widget.startedAt == null || _shouldDisplayBytes || _shouldDisplayLineCounts
        ? 0
        : _clampedElapsedSeconds(DateTime.now().difference(widget.startedAt!));
    final addedColor = Colors.green.shade500;
    final removedColor = Colors.red.shade500;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(width: 10),
        if (widget.showCancelButton)
          Opacity(
            opacity: widget.cancelEnabled ? 1 : 0.55,
            child: ShadGestureDetector(
              cursor: widget.cancelEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
              onTapDown: widget.cancelEnabled && widget.onCancel != null
                  ? (_) {
                      widget.onCancel!();
                    }
                  : null,
              child: Tooltip(
                message: widget.cancelEnabled ? "Stop" : "Cancelling",
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Positioned.fill(child: _CyclingProgressIndicator(strokeWidth: 2)),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: cancelButtonColor),
                        child: Icon(LucideIcons.x, color: cancelIconColor, size: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          const SizedBox(width: 13, height: 13, child: _CyclingProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Expanded(
          child: _shouldDisplayLineCounts
              ? Row(
                  children: [
                    Flexible(
                      child: Text(widget.text, style: statusTextStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    if (widget.linesAdded != null)
                      _AnimatedSignedStatusCounter(value: widget.linesAdded!, prefix: "+", style: statusTextStyle, color: addedColor),
                    if (widget.linesAdded != null && widget.linesRemoved != null) const SizedBox(width: 6),
                    if (widget.linesRemoved != null)
                      _AnimatedSignedStatusCounter(value: widget.linesRemoved!, prefix: "-", style: statusTextStyle, color: removedColor),
                  ],
                )
              : _shouldDisplayBytes
              ? Row(
                  children: [
                    Flexible(
                      child: Text(widget.text, style: statusTextStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    _StatusCounterSeparator(style: statusTextStyle),
                    _AnimatedStatusByteCounter(totalBytes: widget.totalBytes!, style: statusTextStyle),
                  ],
                )
              : elapsedSeconds > 0
              ? Row(
                  children: [
                    Flexible(
                      child: Text(widget.text, style: statusTextStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    _StatusCounterSeparator(style: statusTextStyle),
                    _AnimatedStatusSecondCounter(seconds: elapsedSeconds, style: statusTextStyle),
                  ],
                )
              : Text(displayText, style: statusTextStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _AnimatedStatusByteCounter extends StatefulWidget {
  const _AnimatedStatusByteCounter({required this.totalBytes, required this.style});

  final int totalBytes;
  final TextStyle style;

  @override
  State<_AnimatedStatusByteCounter> createState() => _AnimatedStatusByteCounterState();
}

class _AnimatedStatusSecondCounter extends StatefulWidget {
  const _AnimatedStatusSecondCounter({required this.seconds, required this.style});

  final int seconds;
  final TextStyle style;

  @override
  State<_AnimatedStatusSecondCounter> createState() => _AnimatedStatusSecondCounterState();
}

class _AnimatedSignedStatusCounter extends StatefulWidget {
  const _AnimatedSignedStatusCounter({required this.value, required this.prefix, required this.style, required this.color});

  final int value;
  final String prefix;
  final TextStyle style;
  final Color color;

  @override
  State<_AnimatedSignedStatusCounter> createState() => _AnimatedSignedStatusCounterState();
}

abstract class _AnimatedStatusValueCounterState<T extends StatefulWidget> extends State<T> with SingleTickerProviderStateMixin {
  static const Duration _rollDuration = Duration(milliseconds: 360);
  static const Duration _restDuration = Duration(milliseconds: 500);

  int get value;
  String prefixForValue(int value) => "";
  String suffixForValue(int value);
  Color? numberColor(BuildContext context) => null;
  int get initialDisplayValue => value;

  late int _displayValue;
  late int _targetValue;
  late double _transitionStartValue;
  late double _transitionEndValue;
  late DateTime _restStartedAt;
  var _transitioning = false;
  Timer? _restTimer;
  Timer? _transitionTimer;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final startValue = initialDisplayValue;
    _displayValue = startValue;
    _targetValue = value;
    _transitionStartValue = startValue.toDouble();
    _transitionEndValue = startValue.toDouble();
    _restStartedAt = DateTime.now().subtract(_restDuration);
    _controller = AnimationController(vsync: this, duration: _rollDuration, value: 1);
    if (_displayValue != _targetValue) {
      _scheduleTransition();
    }
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_targetValue == value) {
      return;
    }

    _targetValue = value;
    _scheduleTransition();
  }

  void _scheduleTransition() {
    if (_displayValue == _targetValue || _transitioning) {
      return;
    }

    final elapsedRest = DateTime.now().difference(_restStartedAt);
    if (elapsedRest < _restDuration) {
      _restTimer?.cancel();
      _restTimer = Timer(_restDuration - elapsedRest, _startTransition);
      return;
    }

    _startTransition();
  }

  void _startTransition() {
    _restTimer?.cancel();
    _restTimer = null;
    if (!mounted || _displayValue == _targetValue) {
      return;
    }

    final nextValue = _targetValue;
    setState(() {
      _transitionStartValue = _currentAnimatedValue;
      _transitionEndValue = nextValue.toDouble();
      _displayValue = nextValue;
      _transitioning = true;
    });
    _controller.forward(from: 0);
    _transitionTimer?.cancel();
    _transitionTimer = Timer(_rollDuration, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _transitioning = false;
        _transitionStartValue = _displayValue.toDouble();
        _transitionEndValue = _displayValue.toDouble();
        _restStartedAt = DateTime.now();
      });
      _scheduleTransition();
    });
  }

  double get _currentAnimatedValue {
    if (!_transitioning) {
      return _displayValue.toDouble();
    }
    final progress = Curves.easeOutCubic.transform(_controller.value);
    return _transitionStartValue + ((_transitionEndValue - _transitionStartValue) * progress);
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _transitionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget buildCounter(BuildContext context, TextStyle style) {
    final counterStyle = style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final numberStyle = counterStyle.copyWith(
      color: numberColor(context) ?? ShadTheme.of(context).colorScheme.foreground,
      fontWeight: FontWeight.w700,
    );
    final digitSize = _measureStatusCounterDigit(context, numberStyle);
    final wheelHeight = digitSize.height + 6;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = _transitioning ? Curves.easeOutCubic.transform(_controller.value) : 1.0;
        final digitCount = _transitioning
            ? math.max(_transitionStartValue.floor().toString().length, _transitionEndValue.floor().toString().length)
            : _displayValue.toString().length;
        return Stack(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(prefixForValue(_displayValue), style: numberStyle, maxLines: 1, overflow: TextOverflow.clip),
                for (var index = 0; index < digitCount; index++) ...[
                  if (index > 0 && (digitCount - index) % 3 == 0) Text(",", style: numberStyle, maxLines: 1, overflow: TextOverflow.clip),
                  _StatusCounterWheelDigit(
                    startValue: _transitioning ? _transitionStartValue : _displayValue.toDouble(),
                    endValue: _transitioning ? _transitionEndValue : _displayValue.toDouble(),
                    progress: progress,
                    digitIndex: index,
                    digitCount: digitCount,
                    style: numberStyle,
                    width: digitSize.width,
                    height: wheelHeight,
                  ),
                ],
                Text(suffixForValue(_displayValue), style: counterStyle, maxLines: 1, overflow: TextOverflow.clip),
              ],
            ),
            Positioned.fill(
              child: IgnorePointer(child: _StatusCounterWheelFade(color: ShadTheme.of(context).colorScheme.background)),
            ),
          ],
        );
      },
    );
  }
}

class _AnimatedStatusByteCounterState extends _AnimatedStatusValueCounterState<_AnimatedStatusByteCounter> {
  @override
  int get value => widget.totalBytes;

  @override
  int get initialDisplayValue => widget.totalBytes > 100 ? 100 : widget.totalBytes;

  @override
  String suffixForValue(int value) => " bytes";

  @override
  Widget build(BuildContext context) => buildCounter(context, widget.style);
}

class _AnimatedStatusSecondCounterState extends _AnimatedStatusValueCounterState<_AnimatedStatusSecondCounter> {
  @override
  int get value => widget.seconds;

  @override
  String suffixForValue(int value) => " ${_formatStatusSecondUnit(value)}";

  @override
  Widget build(BuildContext context) => buildCounter(context, widget.style);
}

class _AnimatedSignedStatusCounterState extends _AnimatedStatusValueCounterState<_AnimatedSignedStatusCounter> {
  @override
  int get value => widget.value;

  @override
  String prefixForValue(int value) => widget.prefix;

  @override
  String suffixForValue(int value) => "";

  @override
  Color? numberColor(BuildContext context) => widget.color;

  @override
  Widget build(BuildContext context) => buildCounter(context, widget.style);
}

class _StatusCounterSeparator extends StatelessWidget {
  const _StatusCounterSeparator({required this.style});

  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text(" • ", style: style, maxLines: 1, overflow: TextOverflow.clip);
  }
}

class StatusByteCounter extends StatelessWidget {
  const StatusByteCounter({super.key, required this.totalBytes, required this.style});

  final int totalBytes;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return _AnimatedStatusByteCounter(totalBytes: totalBytes, style: style);
  }
}

class StatusSignedCounter extends StatelessWidget {
  const StatusSignedCounter({super.key, required this.value, required this.prefix, required this.style, required this.color});

  final int value;
  final String prefix;
  final TextStyle style;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _AnimatedSignedStatusCounter(value: value, prefix: prefix, style: style, color: color);
  }
}

class _StatusCounterWheelDigit extends StatelessWidget {
  const _StatusCounterWheelDigit({
    required this.startValue,
    required this.endValue,
    required this.progress,
    required this.digitIndex,
    required this.digitCount,
    required this.style,
    required this.width,
    required this.height,
  });

  final double startValue;
  final double endValue;
  final double progress;
  final int digitIndex;
  final int digitCount;
  final TextStyle style;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final place = math.pow(10, digitCount - digitIndex - 1).toDouble();
    final startPlaceValue = (startValue / place).floor();
    final endPlaceValue = (endValue / place).floor();
    final startDigit = _positiveModulo(startPlaceValue, 10);
    final wheelDelta = endPlaceValue - startPlaceValue;
    final virtualDigit = startDigit + (wheelDelta * progress);
    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var digit = 0; digit < 10; digit++)
              Transform.translate(
                offset: Offset(0, _wrappedDigitOffset(digit: digit, virtualDigit: virtualDigit) * height),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Center(
                    child: Text("$digit", style: style, maxLines: 1, overflow: TextOverflow.clip),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

double _wrappedDigitOffset({required int digit, required double virtualDigit}) {
  final normalized = virtualDigit % 10;
  var offset = digit - normalized;
  if (offset > 5) {
    offset -= 10;
  } else if (offset <= -5) {
    offset += 10;
  }
  return offset;
}

int _positiveModulo(int value, int modulus) => ((value % modulus) + modulus) % modulus;

class _StatusCounterWheelFade extends StatelessWidget {
  const _StatusCounterWheelFade({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final transparent = color.withValues(alpha: 0);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, transparent, transparent, color],
          stops: const [0, 0.28, 0.72, 1],
        ),
      ),
    );
  }
}

Size _measureStatusCounterText(BuildContext context, TextStyle style, String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final size = painter.size;
  painter.dispose();
  return size;
}

Size _measureStatusCounterDigit(BuildContext context, TextStyle style) {
  var width = 0.0;
  var height = 0.0;
  for (var digit = 0; digit <= 9; digit++) {
    final size = _measureStatusCounterText(context, style, digit.toString());
    width = math.max(width, size.width);
    height = math.max(height, size.height);
  }

  return Size(width.ceilToDouble(), height.ceilToDouble());
}

class _PreviewSweepOverlay extends StatefulWidget {
  const _PreviewSweepOverlay();

  @override
  State<_PreviewSweepOverlay> createState() => _PreviewSweepOverlayState();
}

class _PreviewSweepOverlayState extends State<_PreviewSweepOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final centerX = -1.4 + (_controller.value * 2.8);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment(centerX - 0.45, 0),
              end: Alignment(centerX + 0.45, 0),
              colors: const <Color>[Color(0x22000000), Color(0x7A000000), Color(0x22000000)],
              stops: const <double>[0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

class ChatThreadAuthorHeader extends StatelessWidget {
  const ChatThreadAuthorHeader({super.key, required this.authorName, required this.createdAt, this.text});

  final String authorName;
  final DateTime createdAt;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final tt = theme.textTheme;
    final cs = theme.colorScheme;
    final isDesktopScreen =
        ThreadTypographyOverride.useDesktopAuthorHeaderAtNarrowWidthsOf(context) || MediaQuery.sizeOf(context).width >= 600;

    return Container(
      padding: _resolvedChatBubbleContentPadding(context),
      width: ((text)?.isEmpty ?? true) ? 250 : double.infinity,
      child: SelectionArea(
        child: Row(
          spacing: 8,
          children: [
            Expanded(
              child: Text(
                _displayParticipantName(context, authorName),
                style: isDesktopScreen
                    ? tt.small.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: cs.foreground)
                    : tt.small.copyWith(color: cs.foreground),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              timeAgo(createdAt),
              style: tt.small.copyWith(color: cs.mutedForeground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

Widget defaultMessageHeaderBuilder(BuildContext context, MeshElement message, {bool shouldShowAuthorNames = true}) {
  final name = message.getAttribute("author_name") ?? "";
  final createdAt = _messageCreatedAt(message);

  if (shouldShowAuthorNames) {
    return ChatThreadAuthorHeader(authorName: name.toString(), createdAt: createdAt, text: message.getAttribute("text") as String?);
  } else {
    return SizedBox(height: 0);
  }
}

DateTime _messageCreatedAt(MeshElement message) {
  final createdAt = message.getAttribute("created_at");
  if (createdAt is DateTime) {
    return createdAt;
  }
  if (createdAt is String) {
    return DateTime.tryParse(createdAt) ?? DateTime.now();
  }
  return DateTime.now();
}

class ChatThreadSnapshot {
  ChatThreadSnapshot({
    required this.messages,
    required this.online,
    required this.offline,
    required this.typing,
    required this.listening,
    required this.agentOnline,
    required this.threadStatus,
    required this.threadStatusStartedAt,
    required this.threadStatusMode,
    required this.threadStatusTotalBytes,
    required this.threadStatusLinesAdded,
    required this.threadStatusLinesRemoved,
    required this.supportsAgentMessages,
    required this.supportsMcp,
    required this.toolkits,
    required this.threadTurnId,
    required this.pendingMessages,
    required this.pendingItemId,
    required this.usage,
  });

  final bool agentOnline;
  final List<MeshElement> messages;
  final List<Participant> online;
  final List<String> offline;
  final List<String> typing;
  final List<String> listening;
  final String? threadStatus;
  final DateTime? threadStatusStartedAt;
  final String? threadStatusMode;
  final int? threadStatusTotalBytes;
  final int? threadStatusLinesAdded;
  final int? threadStatusLinesRemoved;
  final bool supportsAgentMessages;
  final bool supportsMcp;
  final Map<String, ToolkitCapabilities> toolkits;
  final String? threadTurnId;
  final List<PendingAgentMessage> pendingMessages;
  final String? pendingItemId;
  final AgentUsageSnapshot? usage;
}

class ChatThreadBuilder extends StatefulWidget {
  const ChatThreadBuilder({
    super.key,
    required this.path,
    required this.document,
    required this.room,
    required this.controller,
    required this.builder,
    this.agentName,
  });

  final String? agentName;
  final String path;
  final MeshDocument document;
  final RoomClient room;
  final ChatThreadController controller;
  final Widget Function(BuildContext, ChatThreadSnapshot state) builder;

  @override
  State createState() => _ChatThreadBuilder();
}

class _ChatThreadBuilder extends State<ChatThreadBuilder> {
  late StreamSubscription<RoomEvent> sub;

  Set<Participant> onlineParticipants = {};
  Set<String> offlineParticipants = {};
  Map<String, Timer> typing = {};
  Set<String> listening = {};
  List<MeshElement> messages = [];
  String? threadStatus;
  DateTime? threadStatusStartedAt;
  String? threadStatusMode;
  int? threadStatusTotalBytes;
  int? threadStatusLinesAdded;
  int? threadStatusLinesRemoved;
  bool supportsAgentMessages = false;
  Map<String, ToolkitCapabilities> toolkits = const {};
  String? threadTurnId;
  List<PendingAgentMessage> pendingMessages = const [];
  String? pendingItemId;
  AgentUsageSnapshot? usage;
  String? _capabilitiesRequestKey;
  String? _capabilitiesResponseKey;
  String? _openedPath;
  String? _openedAgentParticipantId;

  @override
  void initState() {
    super.initState();

    sub = widget.room.listen(_onRoomMessage);
    widget.room.messaging.addListener(_onMessagingChanged);
    widget.document.addListener(_onDocumentChanged);

    _getParticipants();
    _getMessages();
    _getThreadStatus();

    _checkAgent();
  }

  @override
  void didUpdateWidget(covariant ChatThreadBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.room != widget.room) {
      _closeThreadSubscription(room: oldWidget.room);
      sub.cancel();
      oldWidget.room.messaging.removeListener(_onMessagingChanged);
      sub = widget.room.listen(_onRoomMessage);
      widget.room.messaging.addListener(_onMessagingChanged);
    }

    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onDocumentChanged);
      widget.document.addListener(_onDocumentChanged);
    }

    if (oldWidget.room != widget.room || oldWidget.path != widget.path || oldWidget.agentName != widget.agentName) {
      if (oldWidget.room == widget.room) {
        _closeThreadSubscription(room: widget.room);
      }
      _clearCapabilities();
      usage = null;
    }

    _getParticipants();
    _getMessages();
    _getThreadStatus();
    _checkAgent();
  }

  bool agentOnline = false;

  void _clearCapabilities() {
    toolkits = const {};
    _capabilitiesRequestKey = null;
    _capabilitiesResponseKey = null;
  }

  Future<void> _requestCapabilities({required RemoteParticipant agent}) async {
    if (!_supportsAgentMessages(agent) && !_supportsMcp(agent)) {
      return;
    }

    final requestKey = "${agent.id}:${widget.path}";
    if (_capabilitiesRequestKey == requestKey || _capabilitiesResponseKey == requestKey) {
      return;
    }

    _capabilitiesRequestKey = requestKey;
    try {
      await widget.room.messaging.sendMessage(
        to: agent,
        type: agentRoomMessageType,
        message: CapabilitiesRequest(threadId: widget.path, messageId: const Uuid().v4()).toJson(),
      );
    } catch (_) {
      if (_capabilitiesRequestKey == requestKey) {
        _capabilitiesRequestKey = null;
      }
    }
  }

  bool _handleCapabilitiesMessage({required RoomMessageEvent event, required AgentMessage message}) {
    if (message is! CapabilitiesResponse) {
      return false;
    }

    if (message.threadId != widget.path) {
      return true;
    }

    final currentAgent = widget.room.messaging.remoteParticipants.firstWhereOrNull(
      (participant) => participant.id == event.message.fromParticipantId,
    );
    if (currentAgent == null) {
      return true;
    }

    toolkits = {for (final toolkit in message.toolkits) toolkit.name: toolkit};
    _capabilitiesRequestKey = null;
    _capabilitiesResponseKey = "${currentAgent.id}:${message.threadId}";
    if (mounted) {
      setState(() {});
    }

    return true;
  }

  bool _handleUsageMessage(AgentMessage message) {
    if (message is! AgentUsageUpdated) {
      return false;
    }
    final nextUsage = AgentUsageSnapshot.fromPayload(message.toJson());
    if (nextUsage == null) {
      return false;
    }
    if (nextUsage.threadPath != widget.path) {
      return true;
    }

    if (!shouldReplaceAgentUsageSnapshot(usage, nextUsage)) {
      return true;
    }
    usage = nextUsage;
    if (mounted) {
      setState(() {});
    }
    return true;
  }

  void _checkAgent() {
    final agent = widget.room.messaging.remoteParticipants.firstWhereOrNull(
      (participant) => participant.getAttribute("name") == widget.agentName,
    );
    final online = agent != null;
    if (online != agentOnline) {
      agentOnline = online;
      if (!online) {
        _clearCapabilities();
      }
      if (mounted) {
        setState(() {});
      }
    }

    if (agent != null) {
      _openThreadSubscription(agent: agent);
      unawaited(_requestCapabilities(agent: agent));
    } else {
      _closeThreadSubscription(room: widget.room);
    }
  }

  void _openThreadSubscription({required RemoteParticipant agent}) {
    if (_openedPath == widget.path && _openedAgentParticipantId == agent.id) {
      return;
    }
    _closeThreadSubscription(room: widget.room);
    _openedPath = widget.path;
    _openedAgentParticipantId = agent.id;

    if (_supportsAgentMessages(agent)) {
      _sendThreadSubscriptionMessageNowait(
        room: widget.room,
        agent: agent,
        message: OpenThread(threadId: widget.path),
      );
      return;
    }

    unawaited(() async {
      try {
        await widget.room.messaging.sendMessage(to: agent, type: "opened", message: {"path": widget.path});
      } catch (_) {}
    }());
  }

  void _closeThreadSubscription({required RoomClient room}) {
    final openedPath = _openedPath;
    final openedAgentParticipantId = _openedAgentParticipantId;
    _openedPath = null;
    _openedAgentParticipantId = null;
    if (openedPath == null || openedAgentParticipantId == null) {
      return;
    }
    final agent = room.messaging.remoteParticipants.firstWhereOrNull((participant) => participant.id == openedAgentParticipantId);
    if (agent == null || !_supportsAgentMessages(agent)) {
      return;
    }
    _sendThreadSubscriptionMessageNowait(
      room: room,
      agent: agent,
      message: CloseThread(threadId: openedPath),
    );
  }

  void _sendThreadSubscriptionMessageNowait({required RoomClient room, required RemoteParticipant agent, required AgentMessage message}) {
    unawaited(() async {
      try {
        await room.messaging.sendMessage(to: agent, type: agentRoomMessageType, message: message.toJson());
      } catch (_) {}
    }());
  }

  @override
  void dispose() {
    _closeThreadSubscription(room: widget.room);
    sub.cancel();
    widget.room.messaging.removeListener(_onMessagingChanged);
    widget.document.removeListener(_onDocumentChanged);
    super.dispose();
  }

  void _onDocumentChanged() {
    if (!mounted) {
      return;
    }

    _getParticipants();
    _getMessages();
    _getThreadStatus();
  }

  void _onMessagingChanged() {
    if (!mounted) {
      return;
    }

    _getParticipants();
    _getThreadStatus();
    _checkAgent();
  }

  void _onRoomMessage(RoomEvent event) {
    if (!mounted) {
      return;
    }

    if (event is RoomMessageEvent) {
      if (event.message.type == agentRoomMessageType) {
        final message = _agentMessageFromRoomPayload(event.message.message);
        if (message != null) {
          final statusChanged = trackAgentThreadStatusMessage(room: widget.room, message: message);
          if (_handleCapabilitiesMessage(event: event, message: message)) {
            if (statusChanged) {
              _getThreadStatus();
            }
            return;
          }
          if (_handleUsageMessage(message)) {
            if (statusChanged) {
              _getThreadStatus();
            }
            return;
          }
          widget.controller.handleAgentMessage(message);
          _getThreadStatus();
        }
      } else {
        _getThreadStatus();
      }

      if (event.message.type.startsWith("participant")) {
        _getParticipants();
        _checkAgent();
      }

      if (event.message.type == "typing" && event.message.message["path"] == widget.path) {
        // TODO: verify thread_id matches
        typing[event.message.fromParticipantId]?.cancel();
        typing[event.message.fromParticipantId] = Timer(Duration(seconds: 1), () {
          typing.remove(event.message.fromParticipantId);
          if (mounted) {
            setState(() {});
          }
        });
        if (mounted) {
          setState(() {});
        }
      } else if (event.message.type == "listening" && event.message.message["path"] == widget.path) {
        if (event.message.message["listening"] == true) {
          listening.add(event.message.fromParticipantId);
        } else {
          listening.remove(event.message.fromParticipantId);
        }

        widget.controller.listening = listening.isNotEmpty;
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  void _getParticipants() {
    final online = widget.controller.getOnlineParticipants(widget.document).toSet();
    if (!setEquals(online, onlineParticipants)) {
      onlineParticipants = online;
      if (!mounted) {
        return;
      }
      setState(() {});
    }

    final offline = widget.controller.getOfflineParticipants(widget.document).toSet();
    if (!setEquals(offline, offlineParticipants)) {
      offlineParticipants = offline;
      if (!mounted) {
        return;
      }
      setState(() {});
    }
  }

  void _getMessages() {
    final threadMessages = widget.document.root.getChildren().whereType<MeshElement>().where((x) => x.tagName == "messages").firstOrNull;
    messages = (threadMessages?.getChildren() ?? []).whereType<MeshElement>().toList();
    setState(() {});
  }

  void _getThreadStatus() {
    final nextState = resolveChatThreadStatus(
      room: widget.room,
      path: widget.path,
      agentName: widget.agentName,
      previous: ChatThreadStatusState(
        text: threadStatus,
        startedAt: threadStatusStartedAt,
        mode: threadStatusMode,
        turnId: threadTurnId,
        pendingMessages: pendingMessages,
        pendingItemId: pendingItemId,
        totalBytes: threadStatusTotalBytes,
        linesAdded: threadStatusLinesAdded,
        linesRemoved: threadStatusLinesRemoved,
        supportsAgentMessages: supportsAgentMessages,
      ),
    );

    final sameStartedAt = nextState.startedAt?.millisecondsSinceEpoch == threadStatusStartedAt?.millisecondsSinceEpoch;
    final samePendingMessages =
        nextState.pendingMessages.length == pendingMessages.length &&
        const DeepCollectionEquality().equals(
          nextState.pendingMessages
              .map(
                (x) => [
                  x.messageId,
                  x.messageType,
                  x.text,
                  x.attachments,
                  x.senderName,
                  x.matchByContentOnly,
                  x.awaitingAcceptance,
                  x.awaitingApplication,
                  x.awaitingOnline,
                ],
              )
              .toList(),
          pendingMessages
              .map(
                (x) => [
                  x.messageId,
                  x.messageType,
                  x.text,
                  x.attachments,
                  x.senderName,
                  x.matchByContentOnly,
                  x.awaitingAcceptance,
                  x.awaitingApplication,
                  x.awaitingOnline,
                ],
              )
              .toList(),
        );
    if (nextState.text == threadStatus &&
        nextState.mode == threadStatusMode &&
        nextState.totalBytes == threadStatusTotalBytes &&
        nextState.linesAdded == threadStatusLinesAdded &&
        nextState.linesRemoved == threadStatusLinesRemoved &&
        sameStartedAt &&
        nextState.turnId == threadTurnId &&
        nextState.pendingItemId == pendingItemId &&
        nextState.supportsAgentMessages == supportsAgentMessages &&
        samePendingMessages) {
      return;
    }

    if (!mounted) {
      threadStatus = nextState.text;
      threadStatusStartedAt = nextState.startedAt;
      threadStatusMode = nextState.mode;
      threadStatusTotalBytes = nextState.totalBytes;
      threadStatusLinesAdded = nextState.linesAdded;
      threadStatusLinesRemoved = nextState.linesRemoved;
      threadTurnId = nextState.turnId;
      supportsAgentMessages = nextState.supportsAgentMessages;
      pendingMessages = nextState.pendingMessages;
      pendingItemId = nextState.pendingItemId;
      return;
    }

    setState(() {
      threadStatus = nextState.text;
      threadStatusStartedAt = nextState.startedAt;
      threadStatusMode = nextState.mode;
      threadStatusTotalBytes = nextState.totalBytes;
      threadStatusLinesAdded = nextState.linesAdded;
      threadStatusLinesRemoved = nextState.linesRemoved;
      threadTurnId = nextState.turnId;
      supportsAgentMessages = nextState.supportsAgentMessages;
      pendingMessages = nextState.pendingMessages;
      pendingItemId = nextState.pendingItemId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final supportsMcp =
        toolkits.containsKey("mcp") ||
        widget.room.messaging.remoteParticipants.any(
          (participant) => participant.getAttribute("name") == widget.agentName && _supportsMcp(participant),
        );
    return widget.builder(
      context,
      ChatThreadSnapshot(
        messages: messages,
        agentOnline: agentOnline,
        online: onlineParticipants.toList(),
        offline: offlineParticipants.toList(),
        typing: typing.keys.toList(),
        listening: listening.toList(),
        threadStatus: threadStatus,
        threadStatusStartedAt: threadStatusStartedAt,
        threadStatusMode: threadStatusMode,
        threadStatusTotalBytes: threadStatusTotalBytes,
        threadStatusLinesAdded: threadStatusLinesAdded,
        threadStatusLinesRemoved: threadStatusLinesRemoved,
        supportsAgentMessages: supportsAgentMessages,
        supportsMcp: supportsMcp,
        toolkits: toolkits,
        threadTurnId: threadTurnId,
        pendingMessages: pendingMessages,
        pendingItemId: pendingItemId,
        usage: usage,
      ),
    );
  }
}

class ReasoningTrace extends StatefulWidget {
  const ReasoningTrace({super.key, required this.previous, required this.message, required this.next});

  final MeshElement? previous;
  final MeshElement message;
  final MeshElement? next;

  @override
  State<ReasoningTrace> createState() => _ReasoningTrace();
}

class _ReasoningTrace extends State<ReasoningTrace> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: 0, bottom: 0, right: 50, left: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(right: 16, left: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MarkdownViewer(
                    markdown: widget.message.getAttribute("summary") ?? "",
                    padding: const EdgeInsets.all(0),
                    threadTypography: true,
                    shrinkWrap: true,
                    selectable: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ShellLine extends StatefulWidget {
  const ShellLine({super.key, required this.previous, required this.message, required this.next});

  final MeshElement? previous;
  final MeshElement message;
  final MeshElement? next;

  @override
  State<ShellLine> createState() => _ShellLineState();
}

class _ShellLineState extends State<ShellLine> {
  String trim(String l) {
    if (l.length < 1024) {
      return l;
    }
    return "${l.substring(0, 1024)}...";
  }

  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final border = BorderSide(color: ShadTheme.of(context).cardTheme.border!.bottom!.color!);
    return Container(
      margin: EdgeInsets.only(top: 0, bottom: 0, right: 50, left: 5),
      decoration: BoxDecoration(
        color: ShadTheme.of(context).colorScheme.background,
        border: Border(
          left: border,
          right: border,
          top: widget.previous?.tagName != widget.message.tagName ? border : BorderSide.none,
          bottom: border,
        ),
        borderRadius: BorderRadius.only(
          topLeft: widget.previous?.tagName != widget.message.tagName ? Radius.circular(10) : Radius.zero,
          topRight: widget.previous?.tagName != widget.message.tagName ? Radius.circular(10) : Radius.zero,
          bottomRight: widget.next?.tagName == widget.message.tagName ? Radius.zero : Radius.circular(10),
          bottomLeft: widget.next?.tagName == widget.message.tagName ? Radius.zero : Radius.circular(10),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.previous?.tagName != widget.message.tagName)
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: border),
                color: ShadTheme.of(context).colorScheme.secondary,
              ),
              padding: EdgeInsets.only(left: 16, right: 16),
              child: Row(
                children: [
                  Icon(LucideIcons.terminal),
                  SizedBox(width: 10),
                  Expanded(child: Text("Terminal", style: ShadTheme.of(context).textTheme.p)),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.only(right: 16, left: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShadGestureDetector(
                  cursor: SystemMouseCursors.click,
                  onTap: () {
                    setState(() {
                      expanded = !expanded;
                    });
                  },
                  child: Padding(padding: EdgeInsets.all(3), child: Icon(expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight)),
                ),

                Expanded(
                  child: SelectableText.rich(
                    maxLines: expanded ? null : 1,
                    TextSpan(
                      children: [
                        TextSpan(text: widget.message.getAttribute("command"), style: threadTypographyCodeTextStyle(context)),
                        if (expanded) ...[
                          TextSpan(text: "\n"),
                          if (widget.message.getAttribute("result") != null) ...[
                            TextSpan(text: "\n"),
                            TextSpan(text: trim(widget.message.getAttribute("result")), style: threadTypographyCodeTextStyle(context)),
                          ],
                          if (widget.message.getAttribute("stdout") != null) ...[
                            TextSpan(text: "\n"),
                            TextSpan(text: trim(widget.message.getAttribute("stdout")), style: threadTypographyCodeTextStyle(context)),
                          ],
                          if (widget.message.getAttribute("stderr") != null) ...[
                            TextSpan(text: "\n"),
                            TextSpan(
                              text: trim(widget.message.getAttribute("stderr")),
                              style: threadTypographyCodeTextStyle(context, color: Colors.red),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EventLine extends StatefulWidget {
  const EventLine({
    super.key,
    required this.previous,
    required this.message,
    required this.next,
    required this.room,
    required this.path,
    required this.showCompletedToolCalls,
    this.agentName,
    this.openFile,
    this.pendingItemId,
    this.threadStatus,
    this.threadStatusStartedAt,
  });

  final MeshElement? previous;
  final MeshElement message;
  final MeshElement? next;
  final RoomClient room;
  final String path;
  final bool showCompletedToolCalls;
  final String? agentName;
  final FutureOr<void> Function(String path)? openFile;
  final String? pendingItemId;
  final String? threadStatus;
  final DateTime? threadStatusStartedAt;

  @override
  State<EventLine> createState() => _EventLineState();
}

class _EventLineState extends State<EventLine> {
  bool sendingApprovalDecision = false;

  Widget _wrapWithTooltip(BuildContext context, {required Widget child, required String? tooltipText}) {
    final normalizedTooltipText = tooltipText?.trim() ?? "";
    if (normalizedTooltipText.isEmpty) {
      return child;
    }

    return ShadTooltip(
      waitDuration: const Duration(milliseconds: 300),
      builder: (context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(normalizedTooltipText, style: ShadTheme.of(context).textTheme.small),
      ),
      child: child,
    );
  }

  String _humanize(String value) {
    if (value.trim().isEmpty) {
      return "";
    }

    final normalized = value.replaceAll(RegExp(r"[._-]+"), " ").trim();
    final parts = normalized.split(RegExp(r"\s+"));
    return parts.where((part) => part.isNotEmpty).map((part) => "${part[0].toUpperCase()}${part.substring(1)}").join(" ");
  }

  String _defaultHeadline({required String kind, required String state, required String eventName}) {
    if (kind == "plan") {
      return state == "completed" ? "Plan Ready" : "Planning";
    }
    if (kind == "diff") {
      return state == "completed" ? "Diff Ready" : "Preparing Diff";
    }
    if (kind == "exec") {
      return state == "completed" ? "Command Complete" : "Running Command";
    }
    if (kind == "message") {
      return state == "completed" ? "Response Ready" : "Composing Response";
    }
    if (kind == "turn") {
      return state == "completed" ? "Turn Complete" : "Thinking";
    }

    if (eventName.trim().isNotEmpty) {
      final tail = eventName.split(".").last;
      return _humanize(tail);
    }

    return "";
  }

  bool _useSummaryAsHeadline({required String summary, required String method, required String eventName}) {
    if (summary.trim().isEmpty) {
      return false;
    }

    final lower = summary.toLowerCase();
    if (lower == method.toLowerCase()) {
      return false;
    }
    if (lower == eventName.toLowerCase()) {
      return false;
    }
    if (method.trim().isNotEmpty && lower.startsWith(method.toLowerCase())) {
      return false;
    }
    return true;
  }

  List<String> _detailLines(String raw) {
    return _parseEventDetailLines(raw);
  }

  String _displayText({required String headline}) {
    return headline;
  }

  String? _eventPath() {
    final value = widget.message.getAttribute("path");
    if (value is! String) {
      return null;
    }

    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _commandPreviewText({required String kind}) {
    if (kind != "exec" && kind != "file") {
      return null;
    }

    final value = widget.message.getAttribute("preview");
    if (value is! String || value.isEmpty) {
      return null;
    }

    return value;
  }

  List<({String source, String text})> _eventLogs() {
    final logs = <({String source, String text})>[];

    for (final child in widget.message.getChildren().whereType<MeshElement>()) {
      if (child.tagName != "log") {
        continue;
      }

      final source = child.getAttribute("source");
      final text = child.getAttribute("text");
      if (source is! String || text is! String) {
        continue;
      }

      final normalizedSource = source.trim();
      if (normalizedSource.isEmpty) {
        continue;
      }

      logs.add((source: normalizedSource, text: text));
    }

    if (logs.length <= 10) {
      return logs;
    }

    return logs.sublist(logs.length - 10);
  }

  String? _diffPreviewPathForChange(dynamic change) {
    if (change is! Map) {
      return null;
    }

    final rawPath = change["path"];
    final path = rawPath is String ? rawPath.trim() : "";

    var movePath = "";
    final rawMovePath = change["move_path"] ?? change["movePath"];
    if (rawMovePath is String) {
      movePath = rawMovePath.trim();
    } else {
      final rawKind = change["kind"];
      if (rawKind is Map) {
        final nestedMovePath = rawKind["move_path"] ?? rawKind["movePath"];
        if (nestedMovePath is String) {
          movePath = nestedMovePath.trim();
        }
      }
    }

    if (path.isNotEmpty && movePath.isNotEmpty && path != movePath) {
      return "$path -> $movePath";
    }
    if (movePath.isNotEmpty) {
      return movePath;
    }
    if (path.isNotEmpty) {
      return path;
    }
    return null;
  }

  String _diffPreviewHeader({required String path, required int linesAdded, required int linesRemoved}) {
    if (linesAdded == 0 && linesRemoved == 0) {
      return path;
    }
    return "$path (+$linesAdded -$linesRemoved)";
  }

  List<Map<String, String>> _extractApplyPatchPreviewBlocks({required String encoded, required String headline, String? fallbackPath}) {
    final normalized = encoded.replaceAll("\r\n", "\n").trimRight();
    if (!normalized.contains("*** Begin Patch") &&
        !normalized.contains("*** Update File:") &&
        !normalized.contains("*** Add File:") &&
        !normalized.contains("*** Delete File:")) {
      return const [];
    }

    final previews = <Map<String, String>>[];
    var currentPath = "";
    var lines = <String>[];
    var linesAdded = 0;
    var linesRemoved = 0;

    void flush() {
      if (currentPath.isEmpty || lines.isEmpty) {
        lines = <String>[];
        linesAdded = 0;
        linesRemoved = 0;
        return;
      }
      previews.add({
        "path": _diffPreviewHeader(path: currentPath, linesAdded: linesAdded, linesRemoved: linesRemoved),
        "diff": lines.join("\n").trimRight(),
      });
      lines = <String>[];
      linesAdded = 0;
      linesRemoved = 0;
    }

    for (final rawLine in normalized.split("\n")) {
      final fileMatch = RegExp(r"^\*\*\* (?:Update|Add|Delete) File: (.+)$").firstMatch(rawLine);
      if (fileMatch != null) {
        flush();
        currentPath = fileMatch.group(1)?.trim() ?? "";
        continue;
      }

      if (currentPath.isEmpty) {
        continue;
      }
      if (rawLine.startsWith("*** ")) {
        continue;
      }

      lines.add(rawLine);
      if (rawLine.startsWith("+") && !rawLine.startsWith("+++")) {
        linesAdded++;
      } else if (rawLine.startsWith("-") && !rawLine.startsWith("---")) {
        linesRemoved++;
      }
    }
    flush();

    if (previews.isNotEmpty) {
      return previews;
    }

    final fallback = fallbackPath ?? headline;
    return [
      {"path": fallback, "diff": normalized},
    ];
  }

  List<Map<String, String>> _extractDiffPreviewBlocksFromEncoded({
    required String encoded,
    required String headline,
    String? fallbackPath,
  }) {
    if (encoded.trim().isEmpty) {
      return const [];
    }

    final applyPatchPreviews = _extractApplyPatchPreviewBlocks(encoded: encoded, headline: headline, fallbackPath: fallbackPath);
    if (applyPatchPreviews.isNotEmpty) {
      return applyPatchPreviews;
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        return const [];
      }

      final itemCandidates = <dynamic>[decoded["item"], (decoded["msg"] is Map) ? (decoded["msg"] as Map)["item"] : null, decoded];

      for (final candidate in itemCandidates) {
        if (candidate is! Map) {
          continue;
        }

        final changes = candidate["changes"];
        if (changes is! List) {
          continue;
        }

        final previews = <Map<String, String>>[];
        for (final change in changes) {
          if (change is! Map) {
            continue;
          }

          final diff = change["diff"];
          if (diff is! String) {
            continue;
          }

          final normalizedDiff = diff.replaceAll("\r\n", "\n").trimRight();
          if (normalizedDiff.isEmpty) {
            continue;
          }

          final path = _diffPreviewPathForChange(change) ?? fallbackPath ?? headline;
          previews.add({"path": path, "diff": normalizedDiff});
        }

        if (previews.isNotEmpty) {
          return previews;
        }
      }
    } catch (_) {}

    return const [];
  }

  List<Map<String, String>> _extractDiffPreviewBlocks({required String headline}) {
    final previewCandidates = <String>[];

    final preview = widget.message.getAttribute("preview");
    if (preview is String && preview.trim().isNotEmpty) {
      previewCandidates.add(preview);
    }

    final raw = widget.message.getAttribute("data");
    if (raw is String && raw.trim().isNotEmpty) {
      previewCandidates.add(raw);
    }

    final fallbackPath = _eventPath();
    for (final candidate in previewCandidates) {
      final previews = _extractDiffPreviewBlocksFromEncoded(encoded: candidate, headline: headline, fallbackPath: fallbackPath);
      if (previews.isNotEmpty) {
        return previews;
      }
    }

    return const [];
  }

  Widget _buildThreadPreviewBlock(
    BuildContext context, {
    required String header,
    required String code,
    required String languageOrFilename,
    String fallbackLanguageId = plaintextLanguageId,
    bool showProcessingOverlay = false,
    List<({String source, String text})> logs = const [],
  }) {
    final hasLogs = logs.isNotEmpty;
    final normalizedCode = code.replaceAll("\r\n", "\n").trimRight();
    if (normalizedCode.isEmpty && !hasLogs) {
      return SizedBox.shrink();
    }

    final theme = ShadTheme.of(context);
    final previewBackground = ThreadTypographyOverride.maybeCodeBlockSurfaceColorOf(context) ?? const Color(0xFF050505);
    final previewHeaderBackground = ThreadTypographyOverride.maybeCodeBlockHeaderSurfaceColorOf(context) ?? const Color(0xFF111111);
    final previewBorderColor = ThreadTypographyOverride.maybeCodeBlockBorderColorOf(context) ?? theme.colorScheme.border;
    final previewTextColor = ThreadTypographyOverride.maybeCodeBlockTextColorOf(context) ?? const Color(0xFFE5E7EB);
    final previewHeaderTextColor = ThreadTypographyOverride.maybeCodeBlockHeaderTextColorOf(context) ?? theme.colorScheme.mutedForeground;
    final previewHighlightTheme = chatBubbleCodeHighlightTheme(context);
    final usesMobileTypography = chatBubbleMarkdownUsesMobileTypography(context);
    final codeTextStyle = threadTypographyCodeTextStyle(
      context,
      fontSize:
          ThreadTypographyOverride.maybeCodeBlockFontSizeOf(context) ?? (usesMobileTypography ? chatBubbleMarkdownMobileBaseFontSize : 12),
      color: previewTextColor,
      height:
          ThreadTypographyOverride.maybeCodeBlockLineHeightOf(context) ??
          (usesMobileTypography ? chatBubbleMarkdownMobileCodeLineHeight : 1.3),
    );
    final headerTextStyle = threadTypographyCodeTextStyle(context, fontSize: usesMobileTypography ? 13 : 11, color: previewHeaderTextColor);
    final resolvedLanguageId = resolveLanguageIdForFilename(languageOrFilename) ?? fallbackLanguageId;
    final body = resolvedLanguageId == "diff"
        ? Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: _resolvedChatBubbleHorizontalPadding(context), vertical: 8),
            child: Builder(
              builder: (context) {
                final lines = normalizedCode.split("\n");
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final line in lines.indexed)
                      Padding(
                        padding: EdgeInsets.only(bottom: line.$1 < lines.length - 1 ? 2 : 0),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: diffLineBackgroundColor(context, line.$2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          child: SelectableText.rich(
                            highlightCodeSpanWithReHighlight(
                              context: context,
                              code: line.$2,
                              languageOrFilename: "diff",
                              textStyle: codeTextStyle,
                              theme: previewHighlightTheme,
                              fallbackLanguageId: "diff",
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: _resolvedChatBubbleHorizontalPadding(context), vertical: 8),
            child: SelectableText.rich(
              highlightCodeSpanWithReHighlight(
                context: context,
                code: normalizedCode,
                languageOrFilename: languageOrFilename,
                textStyle: codeTextStyle,
                theme: previewHighlightTheme,
                fallbackLanguageId: fallbackLanguageId,
              ),
            ),
          );
    final logsBody = hasLogs
        ? Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              _resolvedChatBubbleHorizontalPadding(context),
              0,
              _resolvedChatBubbleHorizontalPadding(context),
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in logs.indexed)
                        Padding(
                          padding: EdgeInsets.only(bottom: line.$1 < logs.length - 1 ? 2 : 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: line.$2.source == "stderr" ? const Color(0xFF2A0B0B) : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: SelectableText.rich(TextSpan(children: [ansiToTextSpan(line.$2.text, baseStyle: codeTextStyle)])),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          )
        : null;

    final previewContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: _resolvedChatBubbleHorizontalPadding(context), vertical: 6),
          decoration: BoxDecoration(
            color: previewHeaderBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectionArea(child: Text(header, style: headerTextStyle)),
              ),
              if (normalizedCode.isNotEmpty)
                ShadIconButton.ghost(
                  width: 24,
                  height: 24,
                  iconSize: 14,
                  icon: Icon(LucideIcons.copy, size: 14, color: previewHeaderTextColor),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: normalizedCode));
                  },
                ),
            ],
          ),
        ),
        if (normalizedCode.isNotEmpty) body,
        ?logsBody,
      ],
    );

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: previewBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: previewBorderColor),
      ),
      child: Stack(
        children: [
          previewContent,
          if (showProcessingOverlay) Positioned.fill(child: IgnorePointer(child: _PreviewSweepOverlay())),
        ],
      ),
    );
  }

  Widget _buildEventLogsBlock(BuildContext context, {required List<({String source, String text})> logs}) {
    if (logs.isEmpty) {
      return SizedBox.shrink();
    }
    return _buildThreadPreviewBlock(
      context,
      header: "logs",
      code: " ",
      languageOrFilename: "logs.txt",
      fallbackLanguageId: plaintextLanguageId,
      logs: logs,
    );
  }

  Future<void> _sendApprovalDecision({required String approvalId, required bool approve}) async {
    if (sendingApprovalDecision) {
      return;
    }

    final candidates = <RemoteParticipant>[];
    if (widget.agentName != null) {
      candidates.addAll(
        widget.room.messaging.remoteParticipants.where((participant) => participant.getAttribute("name") == widget.agentName),
      );
    }
    candidates.addAll(widget.room.messaging.remoteParticipants.where((participant) => participant.role == "agent"));

    final recipients = candidates.toSet().toList();
    if (recipients.isEmpty) {
      return;
    }

    final useAgentMessages = recipients.any(_supportsAgentMessages);
    String? turnId;
    if (useAgentMessages) {
      turnId = resolveChatThreadStatus(room: widget.room, path: widget.path, agentName: widget.agentName).turnId;

      if (turnId == null) {
        return;
      }
    }

    setState(() {
      sendingApprovalDecision = true;
    });

    try {
      await Future.wait([
        for (final participant in recipients)
          widget.room.messaging.sendMessage(
            to: participant,
            type: useAgentMessages ? agentRoomMessageType : (approve ? "approved" : "rejected"),
            message: useAgentMessages
                ? {
                    "type": approve ? agentToolApproveType : agentToolRejectType,
                    "thread_id": widget.path,
                    "turn_id": turnId,
                    "item_id": approvalId,
                  }
                : {"path": widget.path, "approval_id": approvalId},
          ),
      ]);
    } finally {
      if (mounted) {
        setState(() {
          sendingApprovalDecision = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const supportedKinds = {"exec", "tool", "web", "search", "diff", "image", "approval", "collab", "plan", "thread", "file"};

    final method = (widget.message.getAttribute("method") as String?) ?? "agent/event";
    final eventName =
        (widget.message.getAttribute("name") as String?) ??
        (widget.message.getAttribute("event_type") as String?) ??
        method.replaceAll("/", ".");
    final kind = ((widget.message.getAttribute("kind") as String?) ?? "").trim().toLowerCase();
    if (!supportedKinds.contains(kind)) {
      return SizedBox.shrink();
    }
    final state = ((widget.message.getAttribute("state") as String?) ?? "info").toLowerCase();
    final inProgress = state == "in_progress" || state == "running" || state == "queued";
    final itemType = ((widget.message.getAttribute("item_type") as String?) ?? "").trim().toLowerCase();
    final summary = ((widget.message.getAttribute("summary") as String?) ?? method).trim();
    final headlineAttr = ((widget.message.getAttribute("headline") as String?) ?? "").trim();
    final detailsAttr = ((widget.message.getAttribute("details") as String?) ?? "").trim();
    final detailLines = _detailLines(detailsAttr);
    if (_shouldHideToolOrShellCallEvent(widget.message, showCompletedToolCalls: widget.showCompletedToolCalls)) {
      return const SizedBox.shrink();
    }
    final approvalId =
        (((widget.message.getAttribute("item_id") as String?) ?? (widget.message.getAttribute("approval_id") as String?) ?? "")).trim();
    final useSummaryAsHeadline = _useSummaryAsHeadline(summary: summary, method: method, eventName: eventName);
    var headline = headlineAttr.isNotEmpty
        ? headlineAttr
        : (useSummaryAsHeadline ? summary : _defaultHeadline(kind: kind, state: state, eventName: eventName));
    if (headline.trim().isEmpty) {
      return SizedBox.shrink();
    }
    var renderedDetailLines = detailLines;
    if (kind == "exec") {
      renderedDetailLines = detailLines.toList();
    }
    final failureTooltipText = itemType == "tool_call" && (state == "failed" || state == "cancelled") && renderedDetailLines.isNotEmpty
        ? renderedDetailLines.join("\n")
        : null;
    if (failureTooltipText != null) {
      renderedDetailLines = const <String>[];
    }
    final eventPath = _eventPath();
    final commandPreview = _commandPreviewText(kind: kind);
    final eventLogs = _eventLogs();
    final diffPreviewBlocks = kind == "diff" ? _extractDiffPreviewBlocks(headline: headline) : const <Map<String, String>>[];
    final displayText = _displayText(headline: headline);
    final itemId = ((widget.message.getAttribute("item_id") as String?) ?? "").trim();
    final showPreviewOverlay = itemId.isNotEmpty && widget.pendingItemId != null && widget.pendingItemId == itemId;
    final canApprove = kind == "approval" && inProgress && approvalId.isNotEmpty;
    final canOpenPath = eventPath != null && widget.openFile != null && ((kind == "thread" && eventPath != widget.path) || kind == "file");
    final eventTextPadding = EdgeInsets.only(left: _resolvedChatBubbleHorizontalPadding(context));

    Color textColor;
    if (state == "failed") {
      textColor = ShadTheme.of(context).colorScheme.foreground;
    } else if (state == "cancelled") {
      textColor = ShadTheme.of(context).colorScheme.mutedForeground;
    } else if (state == "completed") {
      textColor = ShadTheme.of(context).colorScheme.foreground;
    } else if (inProgress) {
      textColor = ShadTheme.of(context).colorScheme.primary;
    } else {
      textColor = ShadTheme.of(context).colorScheme.foreground;
    }

    return Container(
      margin: EdgeInsets.only(top: 0, bottom: 0, left: 5),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _wrapWithTooltip(
                    context,
                    tooltipText: failureTooltipText,
                    child: canOpenPath
                        ? ShadGestureDetector(
                            cursor: SystemMouseCursors.click,
                            onTap: () {
                              unawaited(Future.sync(() => widget.openFile!(eventPath)));
                            },
                            child: Padding(
                              padding: eventTextPadding,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayText,
                                      style: threadTypographyTextStyle(
                                        context,
                                        TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: textColor,
                                          height: 1.3,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(LucideIcons.externalLink, size: 12, color: textColor),
                                ],
                              ),
                            ),
                          )
                        : Padding(
                            padding: eventTextPadding,
                            child: SelectionArea(
                              child: Text(
                                displayText,
                                style: threadTypographyTextStyle(
                                  context,
                                  TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor, height: 1.3),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
            if ((kind == "exec" || kind == "file") && commandPreview != null)
              _buildThreadPreviewBlock(
                context,
                header: "command",
                code: commandPreview,
                languageOrFilename: "command.sh",
                fallbackLanguageId: "sh",
                showProcessingOverlay: showPreviewOverlay,
                logs: eventLogs,
              ),
            if (diffPreviewBlocks.isNotEmpty)
              Column(
                children: [
                  for (final preview in diffPreviewBlocks)
                    _buildThreadPreviewBlock(
                      context,
                      header: preview["path"] ?? "diff",
                      code: preview["diff"] ?? "",
                      languageOrFilename: "diff",
                      fallbackLanguageId: "diff",
                      showProcessingOverlay: showPreviewOverlay,
                    ),
                ],
              ),
            if (eventLogs.isNotEmpty && !((kind == "exec" || kind == "file") && commandPreview != null))
              _buildEventLogsBlock(context, logs: eventLogs),
            if (renderedDetailLines.isNotEmpty && (kind != "diff" || diffPreviewBlocks.isEmpty))
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(top: 0),
                child: Padding(
                  padding: eventTextPadding,
                  child: SelectionArea(
                    child: Text(
                      renderedDetailLines.join("\n"),
                      style: threadTypographyTextStyle(context, TextStyle(color: textColor.withAlpha(220), height: 1.3)),
                    ),
                  ),
                ),
              ),
            if (canApprove)
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(top: 0),
                child: Padding(
                  padding: eventTextPadding,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ShadButton(
                        enabled: !sendingApprovalDecision,
                        onPressed: () {
                          _sendApprovalDecision(approvalId: approvalId, approve: true);
                        },
                        child: Text("Approve"),
                      ),
                      ShadButton.outline(
                        enabled: !sendingApprovalDecision,
                        onPressed: () {
                          _sendApprovalDecision(approvalId: approvalId, approve: false);
                        },
                        child: Text("Reject"),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatThreadPreview extends StatelessWidget {
  const ChatThreadPreview({super.key, required this.room, required this.path});

  final RoomClient room;
  final String path;

  @override
  Widget build(BuildContext context) {
    final ext = path.split(".").last.toLowerCase();

    if (imageExtensions.contains(ext)) {
      const previewEdge = 312.5;
      return FutureBuilder(
        future: room.storage.downloadUrl(path),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return SizedBox(
              width: previewEdge,
              height: previewEdge,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ImagePreview(key: ValueKey(path), url: Uri.parse(snapshot.data!), fit: BoxFit.cover),
              ),
            );
          }

          return SizedBox(
            width: previewEdge,
            height: previewEdge,
            child: ColoredBox(color: ShadTheme.of(context).colorScheme.background),
          );
        },
      );
    }

    final useThreadAttachmentStyle = ThreadTypographyOverride.useThreadAttachmentStyleOf(context);
    return FileDefaultPreviewCard(
      icon: LucideIcons.file,
      text: path.split("/").last,
      useThreadAttachmentStyle: useThreadAttachmentStyle,
      showActionIcon: useThreadAttachmentStyle,
    );
  }
}

typedef FileDropCallback = Future<void> Function(String name, Stream<Uint8List> dataStream, int? fileSize);
typedef FileDropOverlayBuilder = Widget Function(BuildContext context, bool dragging);
typedef TextPasteCallback = Future<void> Function(String text);

class FileDropArea extends StatefulWidget {
  final FileDropCallback onFileDrop;

  final Widget child;

  final bool multiple;

  final FileDropOverlayBuilder? overlayBuilder;

  final ValueChanged<bool>? onDraggingChanged;

  const FileDropArea({
    super.key,
    required this.onFileDrop,
    required this.child,
    this.multiple = true,
    this.overlayBuilder,
    this.onDraggingChanged,
  });

  @override
  FileDropAreaState createState() => FileDropAreaState();
}

const _preferredFormats = [
  Formats.mp4,
  Formats.mov,
  Formats.mkv,
  Formats.pdf,
  webPDFFormat,
  Formats.png,
  Formats.jpeg,
  Formats.heic,
  Formats.tiff,
  Formats.webp,
];

class FileDropAreaState extends State<FileDropArea> {
  bool _dragging = false;

  @override
  void dispose() {
    if (_dragging) {
      widget.onDraggingChanged?.call(false);
    }
    super.dispose();
  }

  Future<DataReaderFile> _getFile(DataReader reader, SimpleFileFormat? format) {
    final completer = Completer<DataReaderFile>();

    reader.getFile(format, completer.complete, onError: completer.completeError);

    return completer.future;
  }

  Future<T> _getValue<T extends Object>(DataReader reader, ValueFormat<T> format) {
    final completer = Completer<T>();

    reader.getValue(format, completer.complete, onError: completer.completeError);

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final overlay = widget.overlayBuilder?.call(context, _dragging);

    return DropRegion(
      formats: const [...Formats.standardFormats, Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDragOver,
      onDropLeave: _onDragLeave,
      onPerformDrop: _onDrop,
      child: Stack(
        children: [
          widget.child,
          if (overlay != null)
            Positioned.fill(child: IgnorePointer(child: overlay))
          else if (_dragging)
            Positioned.fill(child: Container(color: Colors.blue.withValues(alpha: 0.1))),
        ],
      ),
    );
  }

  void _setDragging(bool dragging) {
    if (!mounted || _dragging == dragging) {
      return;
    }

    setState(() => _dragging = dragging);
    widget.onDraggingChanged?.call(dragging);
  }

  DropOperation _onDragOver(DropOverEvent event) {
    _setDragging(true);

    return event.session.allowedOperations.contains(DropOperation.copy) ? DropOperation.copy : DropOperation.none;
  }

  void _onDragLeave(DropEvent event) {
    _setDragging(false);
  }

  Future<void> _onDrop(PerformDropEvent event) async {
    _setDragging(false);

    final readers = event.session.items.map((m) => m.dataReader).toList();
    var droppedFile = false;

    for (final reader in readers) {
      if (!widget.multiple && droppedFile) break;
      if (reader == null) continue;

      try {
        FolderDropPayload? folderPayload;
        if (reader.canProvide(Formats.fileUri)) {
          try {
            final namedUri = await _getValue(reader, Formats.fileUri);

            folderPayload = await resolveFolderDrop(namedUri);
          } catch (err, st) {
            debugPrint('Error reading dropped folder uri: $err\n$st');
          }
        }

        if (kIsWeb && folderPayload == null) {
          try {
            final rawItem = reader.rawReader;

            if (rawItem != null) {
              final result = rawItem.getDataForFormat('web:entry');
              final entryData = await result.$1;
              if (entryData != null) {
                folderPayload = await resolveFolderDropFromEntry(entryData);
              }
            }
          } catch (err, st) {
            debugPrint('Error reading dropped folder entry on web: $err\n$st');
          }
        }

        if (folderPayload != null) {
          for (final file in folderPayload.files) {
            if (!widget.multiple && droppedFile) break;
            final relativePath = file.relativePath.replaceAll('\\', '/');
            final uploadPath = relativePath.isEmpty ? folderPayload.folderName : '${folderPayload.folderName}/$relativePath';

            await widget.onFileDrop(uploadPath, file.dataStream, file.fileSize);
            droppedFile = true;
          }
          continue;
        }

        final name = (await reader.getSuggestedName())!;
        final fmt = _preferredFormats.firstWhereOrNull(reader.canProvide);
        final file = await _getFile(reader, fmt);

        await widget.onFileDrop(name, file.getStream(), file.fileSize);
        droppedFile = true;
      } catch (err, st) {
        debugPrint('Error dropping file: $err\n$st');
      }
    }
  }
}

class PhotoNamer {
  /// Example:
  /// IMG_20251211_173812.JPG
  /// IMG_20251211_173812_1.JPG
  /// IMG_20251211_173812_2.MOV
  static List<String> generateBatchNames(List<XFile> files) {
    if (files.isEmpty) return const [];

    final base = _base();
    final result = <String>[];

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final ext = _ext(file.name);

      final candidate = i == 0 ? '$base.$ext' : '${base}_$i.$ext';
      result.add(candidate);
    }

    return result;
  }

  static String _base() {
    final dt = DateTime.now();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return 'IMG_$y$m${d}_$hh$mm$ss';
  }

  static String _ext(String originalName) {
    final dotIndex = originalName.lastIndexOf('.');
    final rawExt = dotIndex == -1 ? '' : originalName.substring(dotIndex + 1).toUpperCase();

    if (rawExt.isEmpty) return 'JPG';

    return rawExt;
  }
}
