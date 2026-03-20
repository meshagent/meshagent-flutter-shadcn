import 'dart:async';

import 'package:collection/collection.dart';
import 'package:meshagent/meshagent.dart';

const String annotationFilePrompt = "meshagent.prompt.file.matches.regex";

class ChatFilePromptAction {
  const ChatFilePromptAction({
    required this.agentName,
    required this.promptName,
    required this.promptDescription,
    required this.promptTemplate,
  });

  final String agentName;
  final String promptName;
  final String? promptDescription;
  final String promptTemplate;

  String get menuLabel => promptName;

  String renderPrompt(String filePath) {
    return promptTemplate.replaceAll("{{file}}", filePath);
  }
}

List<ChatFilePromptAction> resolveChatFilePromptActions({required Iterable<ServiceSpec> services, required String filePath}) {
  final actions = <ChatFilePromptAction>[];

  for (final service in services) {
    for (final agent in service.agents) {
      final agentName = agent.name.trim();
      if (agentName.isEmpty) {
        continue;
      }

      final channels = agent.channels;
      if (channels == null) {
        continue;
      }

      for (final channel in channels.messaging) {
        final channelPattern = _stringAnnotation(channel.annotations, annotationFilePrompt);
        for (final prompt in channel.prompts) {
          final pattern =
              _stringAnnotation(prompt.annotations, annotationFilePrompt) ??
              channelPattern ??
              _dynamicStringAnnotation(agent.annotations, annotationFilePrompt) ??
              _stringAnnotation(service.metadata.annotations, annotationFilePrompt);
          if (pattern == null) {
            continue;
          }

          final regex = _tryParseRegExp(pattern);
          if (regex == null || !regex.hasMatch(filePath)) {
            continue;
          }

          final promptName = prompt.name.trim();
          actions.add(
            ChatFilePromptAction(
              agentName: agentName,
              promptName: promptName.isEmpty ? "New chat" : promptName,
              promptDescription: prompt.description?.trim(),
              promptTemplate: prompt.prompt,
            ),
          );
        }
      }
    }
  }

  actions.sort((left, right) {
    final labelCompare = left.menuLabel.toLowerCase().compareTo(right.menuLabel.toLowerCase());
    if (labelCompare != 0) {
      return labelCompare;
    }

    return left.agentName.toLowerCase().compareTo(right.agentName.toLowerCase());
  });
  return actions;
}

Future<String> startChatFilePromptThread({
  required RoomClient room,
  required ChatFilePromptAction action,
  required String filePath,
  String toolkit = "chat",
  String tool = "new_thread",
  Duration timeout = const Duration(seconds: 30),
}) {
  return startNewChatThread(
    room: room,
    agentName: action.agentName,
    prompt: action.renderPrompt(filePath),
    toolkit: toolkit,
    tool: tool,
    timeout: timeout,
  );
}

Future<String> startNewChatThread({
  required RoomClient room,
  required String agentName,
  required String prompt,
  List<String> attachmentPaths = const [],
  String toolkit = "chat",
  String tool = "new_thread",
  Duration timeout = const Duration(seconds: 30),
}) async {
  final normalizedAgentName = agentName.trim();
  if (normalizedAgentName.isEmpty) {
    throw RoomServerException("Agent name is required.");
  }

  final deadline = DateTime.now().add(timeout);
  final agent = await _waitForNamedAgentOnline(room: room, agentName: normalizedAgentName, deadline: deadline);
  await _waitForToolkitAvailable(room: room, participantId: agent.id, toolkitName: toolkit, deadline: deadline);

  final result = await room.agents.invokeTool(
    toolkit: toolkit,
    tool: tool,
    participantId: agent.id,
    input: ToolContentInput(
      JsonContent(
        json: {
          "message": {
            "text": prompt,
            "attachments": [
              for (final path in attachmentPaths) {"path": path},
            ],
            "tools": const [],
          },
        },
      ),
    ),
  );

  final content = switch (result) {
    ToolContentOutput(:final content) => content,
    ToolStreamOutput() => throw RoomServerException("$toolkit.$tool returned a stream; expected json content"),
  };

  if (content is! JsonContent) {
    throw RoomServerException("$toolkit.$tool returned ${content.runtimeType}; expected json content");
  }

  final responsePath = content.json["path"];
  if (responsePath is! String || responsePath.trim().isEmpty) {
    throw RoomServerException("$toolkit.$tool response missing path");
  }

  final threadPath = responsePath.trim();
  await _waitForThreadCreated(room: room, path: threadPath);
  return threadPath;
}

RegExp? _tryParseRegExp(String pattern) {
  try {
    return RegExp(pattern);
  } catch (_) {
    return null;
  }
}

String? _stringAnnotation(Map<String, String> annotations, String key) {
  final value = annotations[key];
  if (value == null) {
    return null;
  }

  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _dynamicStringAnnotation(Map<String, dynamic> annotations, String key) {
  final value = annotations[key];
  if (value is! String) {
    return null;
  }

  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

RemoteParticipant? _findNamedAgent(RoomClient room, String agentName) {
  return room.messaging.remoteParticipants.firstWhereOrNull((participant) {
    final name = participant.getAttribute("name");
    return name is String && name == agentName;
  });
}

Future<RemoteParticipant> _waitForNamedAgentOnline({
  required RoomClient room,
  required String agentName,
  required DateTime deadline,
}) async {
  while (true) {
    final participant = _findNamedAgent(room, agentName);
    if (participant != null) {
      return participant;
    }

    if (DateTime.now().isAfter(deadline)) {
      throw RoomServerException('Timed out waiting for agent "$agentName" to come online');
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

Future<void> _waitForToolkitAvailable({
  required RoomClient room,
  required String participantId,
  required String toolkitName,
  required DateTime deadline,
}) async {
  while (true) {
    try {
      final toolkits = await room.agents.listToolkits(participantId: participantId, timeout: 1000);
      if (toolkits.any((toolkit) => toolkit.name == toolkitName)) {
        return;
      }
    } catch (_) {}

    if (DateTime.now().isAfter(deadline)) {
      throw RoomServerException('Timed out waiting for toolkit "$toolkitName" to become available');
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

Future<void> _waitForThreadCreated({required RoomClient room, required String path}) async {
  for (var i = 0; i < 50; i++) {
    try {
      if (await room.storage.exists(path)) {
        return;
      }
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
