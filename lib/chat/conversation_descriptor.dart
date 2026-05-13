import 'package:collection/collection.dart';
import 'package:meshagent/meshagent.dart';
import 'package:path/path.dart' as p;

const String defaultUntitledThreadName = 'New Chat';

final RegExp _uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false);

enum ChatAgentConversationKind { chat, voiceOnly, meeting }

enum ChatThreadDisplayMode { singleThread, multiThreadComposer }

class ChatAgentConversationDescriptor {
  const ChatAgentConversationDescriptor._({
    required this.kind,
    this.chatThreadDisplayMode = ChatThreadDisplayMode.singleThread,
    this.threadDir,
    this.threadListPath,
    this.threadPath,
  });

  const ChatAgentConversationDescriptor.chat({
    ChatThreadDisplayMode chatThreadDisplayMode = ChatThreadDisplayMode.singleThread,
    String? threadDir,
    String? threadListPath,
    String? threadPath,
  }) : this._(
         kind: ChatAgentConversationKind.chat,
         chatThreadDisplayMode: chatThreadDisplayMode,
         threadDir: threadDir,
         threadListPath: threadListPath,
         threadPath: threadPath,
       );

  const ChatAgentConversationDescriptor.voiceOnly() : this._(kind: ChatAgentConversationKind.voiceOnly);

  const ChatAgentConversationDescriptor.meeting() : this._(kind: ChatAgentConversationKind.meeting);

  final ChatAgentConversationKind kind;
  final ChatThreadDisplayMode chatThreadDisplayMode;
  final String? threadDir;
  final String? threadListPath;
  final String? threadPath;

  bool get isChat => kind == ChatAgentConversationKind.chat;
  bool get isVoiceOnly => kind == ChatAgentConversationKind.voiceOnly;
  bool get isMeeting => kind == ChatAgentConversationKind.meeting;
  bool get isMultiThreadChat => isChat && chatThreadDisplayMode == ChatThreadDisplayMode.multiThreadComposer;
}

String? participantDisplayName(RemoteParticipant participant) {
  final rawName = participant.getAttribute("name");
  if (rawName is! String) {
    return null;
  }

  final name = rawName.trim();
  if (name.isEmpty) {
    return null;
  }

  return name;
}

bool participantSupportsVoice(RemoteParticipant participant) {
  final value = participant.getAttribute("supports_voice");
  return value is bool && value;
}

bool? participantSupportsChatOverride(RemoteParticipant participant) {
  final value = participant.getAttribute("supports_chat");
  return value is bool ? value : null;
}

bool participantSupportsChat(RemoteParticipant participant) {
  final value = participantSupportsChatOverride(participant);
  if (value is bool) {
    return value;
  }

  return true;
}

String? normalizedAnnotationString(Object? value) {
  if (value is! String) {
    return null;
  }

  final normalized = value.trim();
  if (normalized.isEmpty) {
    return null;
  }

  return normalized;
}

ChatThreadDisplayMode chatThreadDisplayModeFromAnnotation(Object? value) {
  final normalized = normalizedAnnotationString(value);
  if (normalized == "default-new") {
    return ChatThreadDisplayMode.multiThreadComposer;
  }

  return ChatThreadDisplayMode.singleThread;
}

String? normalizedThreadDir(String? threadDir) {
  if (threadDir == null) {
    return null;
  }

  final trimmed = threadDir.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  return trimmed.endsWith("/") ? trimmed.substring(0, trimmed.length - 1) : trimmed;
}

String? _threadListPathFromThreadDir(String? threadDir) {
  final normalized = normalizedThreadDir(threadDir);
  if (normalized == null) {
    return null;
  }

  if (normalized.startsWith('dataset://')) {
    return "$normalized/index";
  }

  return "$normalized/index.threadl";
}

String? participantThreadDir(RemoteParticipant participant) {
  final value = participant.getAttribute("meshagent.chatbot.thread-dir");
  if (value is! String) {
    return null;
  }

  return normalizedThreadDir(value);
}

String? participantThreadListPath(RemoteParticipant participant) {
  final threadListPath = normalizedAnnotationString(participant.getAttribute("meshagent.chatbot.thread-list"));
  if (threadListPath != null) {
    return threadListPath;
  }

  return _threadListPathFromThreadDir(participantThreadDir(participant));
}

String? participantThreadPath(RemoteParticipant participant) {
  return normalizedAnnotationString(participant.getAttribute("meshagent.chatbot.thread-path"));
}

ChatAgentConversationDescriptor? participantConversationDescriptor(RemoteParticipant participant) {
  final supportsVoice = participantSupportsVoice(participant);
  final supportsChatOverride = participantSupportsChatOverride(participant);
  final threadDir = participantThreadDir(participant);
  final threadListPath = participantThreadListPath(participant);
  final threadPath = participantThreadPath(participant);
  final hasThreadAnnotations =
      normalizedAnnotationString(participant.getAttribute("meshagent.chatbot.threading")) != null ||
      threadDir != null ||
      threadListPath != null ||
      threadPath != null;

  if (supportsChatOverride == false) {
    return supportsVoice ? const ChatAgentConversationDescriptor.voiceOnly() : null;
  }

  if (supportsVoice && supportsChatOverride != true && !hasThreadAnnotations) {
    return const ChatAgentConversationDescriptor.voiceOnly();
  }

  if (hasThreadAnnotations || participantSupportsChat(participant)) {
    return ChatAgentConversationDescriptor.chat(
      chatThreadDisplayMode: chatThreadDisplayModeFromAnnotation(participant.getAttribute("meshagent.chatbot.threading")),
      threadDir: threadDir,
      threadListPath: threadListPath,
      threadPath: threadPath,
    );
  }

  if (supportsVoice) {
    return const ChatAgentConversationDescriptor.voiceOnly();
  }

  return null;
}

String? serviceThreadDir(ServiceSpec service) {
  return normalizedThreadDir(service.agents.firstOrNull?.annotations["meshagent.chatbot.thread-dir"]);
}

String? serviceThreadListPath(ServiceSpec service, {Iterable<RemoteParticipant> remoteParticipants = const []}) {
  final annotationPath = normalizedAnnotationString(service.agents.firstOrNull?.annotations["meshagent.chatbot.thread-list"]);
  if (annotationPath != null) {
    return annotationPath;
  }

  final threadDir = serviceThreadDir(service);
  final threadListPath = _threadListPathFromThreadDir(threadDir);
  if (threadListPath != null) {
    return threadListPath;
  }

  final agentName = service.agents.firstOrNull?.name;
  if (agentName == null || agentName.trim().isEmpty) {
    return null;
  }

  for (final participant in remoteParticipants) {
    if (participant.getAttribute("name") == agentName) {
      return participantThreadListPath(participant);
    }
  }

  return null;
}

String? serviceThreadPath(ServiceSpec service, {Iterable<RemoteParticipant> remoteParticipants = const []}) {
  final annotationPath = normalizedAnnotationString(service.agents.firstOrNull?.annotations["meshagent.chatbot.thread-path"]);
  if (annotationPath != null) {
    return annotationPath;
  }

  final agentName = service.agents.firstOrNull?.name;
  if (agentName == null || agentName.trim().isEmpty) {
    return null;
  }

  for (final participant in remoteParticipants) {
    if (participant.getAttribute("name") == agentName) {
      return participantThreadPath(participant);
    }
  }

  return null;
}

ChatAgentConversationDescriptor? serviceConversationDescriptor(
  ServiceSpec service, {
  Iterable<RemoteParticipant> remoteParticipants = const [],
}) {
  final type = service.agents.firstOrNull?.annotations["meshagent.agent.type"];
  if (type == "VoiceBot") {
    return const ChatAgentConversationDescriptor.voiceOnly();
  }

  if (type == "MeetingTranscriber") {
    return const ChatAgentConversationDescriptor.meeting();
  }

  if (type != "ChatBot") {
    return null;
  }

  return ChatAgentConversationDescriptor.chat(
    chatThreadDisplayMode: chatThreadDisplayModeFromAnnotation(service.agents.firstOrNull?.annotations["meshagent.chatbot.threading"]),
    threadDir: serviceThreadDir(service),
    threadListPath: serviceThreadListPath(service, remoteParticipants: remoteParticipants),
    threadPath: serviceThreadPath(service, remoteParticipants: remoteParticipants),
  );
}

ChatAgentConversationDescriptor? conversationDescriptorForParticipant(
  Participant participant, {
  required Iterable<ServiceSpec> services,
  required Iterable<RemoteParticipant> remoteParticipants,
}) {
  if (participant is! RemoteParticipant) {
    return null;
  }

  final participantName = participantDisplayName(participant);
  if (participantName != null) {
    final matchingService = services.firstWhereOrNull((service) => service.agents.firstOrNull?.name == participantName);
    final serviceDescriptor = matchingService == null
        ? null
        : serviceConversationDescriptor(matchingService, remoteParticipants: remoteParticipants);
    if (serviceDescriptor != null) {
      return serviceDescriptor;
    }
  }

  return participantConversationDescriptor(participant);
}

String? _defaultThreadDocumentDir(String? agentName) {
  if (agentName == null) {
    return null;
  }

  final trimmed = agentName.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  return ".threads/$trimmed";
}

String? resolvedThreadListPath(String? threadListPath, {String? threadDir, String? agentName}) {
  if (threadListPath != null) {
    final trimmed = threadListPath.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }

  final normalizedDir = normalizedThreadDir(threadDir);
  if (normalizedDir == null) {
    final defaultThreadDir = _defaultThreadDocumentDir(agentName);
    if (defaultThreadDir == null) {
      return null;
    }
    return "$defaultThreadDir/index.threadl";
  }

  return "$normalizedDir/index.threadl";
}

String chatDocumentPath(String? agentName, {String? threadDir, String fallbackPath = ".threads/main.thread"}) {
  final normalizedDir = normalizedThreadDir(threadDir);
  if (normalizedDir != null) {
    if (normalizedDir.startsWith('dataset://') || normalizedDir.startsWith('tmp://')) {
      return "$normalizedDir/main";
    }
    return "$normalizedDir/main.thread";
  }

  final defaultThreadDir = _defaultThreadDocumentDir(agentName);
  if (defaultThreadDir != null) {
    return "$defaultThreadDir/main.thread";
  }

  return fallbackPath;
}

String defaultThreadDisplayNameFromPath(String path) {
  final basename = p.posix.basename(path);
  final rawName = basename.endsWith('.thread') ? basename.substring(0, basename.length - '.thread'.length) : basename;
  final trimmed = rawName.trim();
  if (trimmed.isEmpty) {
    return defaultUntitledThreadName;
  }

  if (_uuidPattern.hasMatch(trimmed)) {
    return defaultUntitledThreadName;
  }

  final normalized = trimmed.replaceAll(RegExp(r'[_-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return defaultUntitledThreadName;
  }

  return normalized
      .split(' ')
      .where((segment) => segment.isNotEmpty)
      .map((segment) => segment.length == 1 ? segment.toUpperCase() : '${segment[0].toUpperCase()}${segment.substring(1)}')
      .join(' ');
}
