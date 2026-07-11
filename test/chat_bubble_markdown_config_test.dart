import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/chat_bubble_markdown_config.dart';
import 'package:meshagent_flutter_shadcn/thread_typography.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  test('external markdown links tolerate malformed percent encoding without throwing', () {
    expect(threadMarkdownExternalUri('https://example.com/file.png'), Uri.parse('https://example.com/file.png'));
    expect(
      threadMarkdownExternalUri('powerboards://preview?path=Screenshot% image.png'),
      Uri.parse('powerboards://preview?path=Screenshot%25%20image.png'),
    );
    expect(threadMarkdownExternalUri('https://[invalid'), isNull);
  });

  testWidgets('thread markdown link handler receives link taps', (tester) async {
    String? handledUrl;
    ValueChanged<String>? linkOnTap;

    await tester.pumpWidget(
      ShadApp(
        home: ThreadTypographyOverride(
          markdownLinkHandler: (context, url) {
            handledUrl = url;
            return true;
          },
          child: Builder(
            builder: (context) {
              linkOnTap = buildChatBubbleMarkdownConfig(context, threadTypography: true).a.onTap;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(linkOnTap, isNotNull);
    linkOnTap!('powerboards://files?path=content');
    expect(handledUrl, 'powerboards://files?path=content');
  });

  testWidgets('unhandled malformed markdown link does not replace the thread with an error widget', (tester) async {
    ValueChanged<String>? linkOnTap;

    await tester.pumpWidget(
      ShadApp(
        home: ThreadTypographyOverride(
          markdownLinkHandler: (context, url) => false,
          child: Builder(
            builder: (context) {
              linkOnTap = buildChatBubbleMarkdownConfig(context, threadTypography: true).a.onTap;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(linkOnTap, isNotNull);
    expect(() => linkOnTap!('https://[invalid'), returnsNormally);
    expect(tester.takeException(), isNull);
  });
}
