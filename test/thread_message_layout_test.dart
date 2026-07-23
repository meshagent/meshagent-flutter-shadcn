import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:meshagent_flutter_shadcn/chat/chat.dart';
import 'package:meshagent_flutter_shadcn/chat_bubble_markdown_config.dart';
import 'package:meshagent_flutter_shadcn/markdown_viewer.dart';
import 'package:meshagent_flutter_shadcn/thread_typography.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> disposeThreadWidget(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('shared message layout keeps legacy defaults without an override', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Center(
          child: SizedBox(
            width: 600,
            child: ChatThreadMessageView(
              mine: true,
              isAgentMessage: false,
              text: 'hello',
              authorName: 'person',
              createdAt: DateTime.utc(2026),
              shouldShowHeader: false,
              showBubbleActions: false,
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(MarkdownViewer)).width, greaterThan(500));
    final bubbleBounds = tester.getRect(find.byType(ChatBubble));
    final markdownBounds = tester.getRect(find.byType(MarkdownViewer));
    expect(markdownBounds.top - bubbleBounds.top, closeTo(3, 0.01));
    expect(bubbleBounds.bottom - markdownBounds.bottom, closeTo(3, 0.01));
    await disposeThreadWidget(tester);
  });

  testWidgets('legacy remote human header reserves an action rail only when actions are enabled', (tester) async {
    Future<double> pumpHeader({required bool showBubbleActions}) async {
      await tester.pumpWidget(
        ShadApp(
          home: Center(
            child: SizedBox(
              width: 600,
              child: ChatThreadMessageView(
                mine: false,
                isAgentMessage: false,
                text: 'hello',
                authorName: 'person',
                createdAt: DateTime.utc(2026),
                showBubbleActions: showBubbleActions,
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(ChatThreadAuthorHeader)).width;
    }

    expect(await pumpHeader(showBubbleActions: false), closeTo(600 - (2 * ChatThreadMessageView.chatBubbleHorizontalInset), 0.01));
    expect(
      await pumpHeader(showBubbleActions: true),
      closeTo(600 - (2 * ChatThreadMessageView.chatBubbleHorizontalInset) - ChatThreadMessageView.chatBubbleActionRailWidth, 0.01),
    );
    await disposeThreadWidget(tester);
  });

  testWidgets('opt-in shared message layout shrink-wraps human bubbles', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Center(
          child: SizedBox(
            width: 600,
            child: ThreadTypographyOverride(
              shrinkWrapHumanBubbles: true,
              humanBubbleMaxWidthFraction: 0.75,
              child: ChatThreadMessageView(
                mine: true,
                isAgentMessage: false,
                text: 'preview',
                authorName: 'person',
                createdAt: DateTime.utc(2026),
                shouldShowHeader: false,
                showBubbleActions: false,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(MarkdownViewer)).width, lessThan(200));
    expect(tester.getSize(find.byType(MarkdownViewer)).height, lessThan(40));
    await disposeThreadWidget(tester);
  });

  testWidgets('opt-in human bubble padding balances text vertically', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Center(
          child: SizedBox(
            width: 600,
            child: ThreadTypographyOverride(
              bubbleContentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shrinkWrapHumanBubbles: true,
              child: ChatThreadMessageView(
                mine: true,
                isAgentMessage: false,
                text: 'hello',
                authorName: 'person',
                createdAt: DateTime.utc(2026),
                shouldShowHeader: false,
                showBubbleActions: false,
              ),
            ),
          ),
        ),
      ),
    );

    final bubbleBounds = tester.getRect(find.byType(ChatBubble));
    final textBounds = tester.getRect(find.byType(MarkdownViewer));
    expect(textBounds.top - bubbleBounds.top, closeTo(6, 0.01));
    expect(bubbleBounds.bottom - textBounds.bottom, closeTo(6, 0.01));
    final markdownConfig = buildChatBubbleMarkdownConfig(tester.element(find.byType(MarkdownViewer)), threadTypography: true);
    expect(markdownConfig.p.textStyle.leadingDistribution, TextLeadingDistribution.even);
    await disposeThreadWidget(tester);
  });

  testWidgets('opt-in human header spacing is identical for text and attachments', (tester) async {
    const attachmentKey = ValueKey<String>('human-attachment');
    await tester.pumpWidget(
      ShadApp(
        home: Center(
          child: SizedBox(
            width: 600,
            child: ThreadTypographyOverride(
              humanMessageHeaderContentSpacing: 8,
              attachmentHorizontalInset: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChatThreadMessageView(
                    mine: false,
                    isAgentMessage: false,
                    text: 'hello',
                    authorName: 'person',
                    createdAt: DateTime.utc(2026),
                    showBubbleActions: false,
                  ),
                  ChatThreadMessageView(
                    mine: false,
                    isAgentMessage: false,
                    text: '',
                    authorName: 'person',
                    createdAt: DateTime.utc(2026),
                    showBubbleActions: false,
                    attachmentWidgets: const <Widget>[SizedBox(key: attachmentKey, width: 100, height: 40)],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final headers = find.byType(ChatThreadAuthorHeader);
    final textHeaderBottom = tester.getBottomLeft(headers.at(0)).dy;
    final attachmentHeaderBottom = tester.getBottomLeft(headers.at(1)).dy;
    expect(tester.getTopLeft(find.byType(ChatBubble)).dy - textHeaderBottom, closeTo(8, 0.01));
    expect(tester.getTopLeft(find.byKey(attachmentKey)).dy - attachmentHeaderBottom, closeTo(8, 0.01));
    await disposeThreadWidget(tester);
  });

  testWidgets('opt-in compact author headers stay together and follow message alignment', (tester) async {
    const mineAttachmentKey = ValueKey<String>('mine-attachment');
    await tester.pumpWidget(
      ShadApp(
        home: Center(
          child: SizedBox(
            width: 600,
            child: ThreadTypographyOverride(
              authorHeaderContentPadding: EdgeInsets.zero,
              messageHorizontalInset: 0,
              attachmentHorizontalInset: 0,
              compactAuthorHeaders: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChatThreadMessageView(
                    mine: false,
                    isAgentMessage: false,
                    text: 'from someone else',
                    authorName: 'other-person',
                    createdAt: DateTime.utc(2026),
                    showBubbleActions: false,
                  ),
                  ChatThreadMessageView(
                    mine: true,
                    isAgentMessage: false,
                    text: '',
                    authorName: 'me',
                    createdAt: DateTime.utc(2026),
                    showBubbleActions: false,
                    attachmentWidgets: const <Widget>[SizedBox(key: mineAttachmentKey, width: 100, height: 40)],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final headers = find.byType(ChatThreadAuthorHeader);
    final otherHeader = headers.at(0);
    final mineHeader = headers.at(1);
    final otherTexts = find.descendant(of: otherHeader, matching: find.byType(Text));
    final mineTexts = find.descendant(of: mineHeader, matching: find.byType(Text));

    expect(tester.getTopLeft(otherHeader).dx, closeTo(100, 0.01));
    expect(tester.getTopLeft(otherTexts.at(1)).dx - tester.getTopRight(otherTexts.at(0)).dx, closeTo(8, 0.01));
    expect(tester.getTopRight(mineHeader).dx, closeTo(700, 0.01));
    expect(tester.getTopLeft(mineTexts.at(1)).dx - tester.getTopRight(mineTexts.at(0)).dx, closeTo(8, 0.01));
    expect(tester.getTopRight(find.byKey(mineAttachmentKey)).dx, closeTo(tester.getTopRight(mineHeader).dx, 0.01));
    await disposeThreadWidget(tester);
  });

  testWidgets('opt-in shared message layout aligns agent text, headers, and attachments', (tester) async {
    const attachmentKey = ValueKey<String>('attachment');
    await tester.pumpWidget(
      ShadApp(
        home: Center(
          child: SizedBox(
            width: 600,
            child: ThreadTypographyOverride(
              agentBubbleContentPadding: EdgeInsets.zero,
              authorHeaderContentPadding: EdgeInsets.zero,
              messageHorizontalInset: 0,
              attachmentHorizontalInset: 0,
              child: ChatThreadMessageView(
                mine: false,
                isAgentMessage: true,
                text: 'response',
                authorName: 'builder',
                createdAt: DateTime.utc(2026),
                showBubbleActions: false,
                attachmentWidgets: const <Widget>[SizedBox(key: attachmentKey, width: 100, height: 40)],
              ),
            ),
          ),
        ),
      ),
    );

    final authorLeft = tester.getTopLeft(find.text('builder')).dx;
    final messageLeft = tester.getTopLeft(find.text('response')).dx;
    final attachmentLeft = tester.getTopLeft(find.byKey(attachmentKey)).dx;
    expect(messageLeft, closeTo(authorLeft, 0.01));
    expect(attachmentLeft, closeTo(authorLeft, 0.01));
    await disposeThreadWidget(tester);
  });

  testWidgets('opt-in empty-message author header width can match an attachment column', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Center(
          child: SizedBox(
            width: 600,
            child: ThreadTypographyOverride(
              emptyMessageAuthorHeaderWidth: 312.5,
              child: ChatThreadMessageView(
                mine: true,
                isAgentMessage: false,
                text: '',
                authorName: 'person',
                createdAt: DateTime.utc(2026),
                showBubbleActions: false,
                attachmentWidgets: const <Widget>[SizedBox(width: 312.5, height: 40)],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(ChatThreadAuthorHeader)).width, 312.5);
    await disposeThreadWidget(tester);
  });

  testWidgets('opt-in message actions align to human and agent message bottoms', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Center(
          child: SizedBox(
            width: 600,
            child: ThreadTypographyOverride(
              messageHorizontalInset: 0,
              shrinkWrapHumanBubbles: true,
              bottomAlignMessageActions: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChatThreadMessageView(
                    mine: true,
                    isAgentMessage: false,
                    text: 'hello',
                    authorName: 'person',
                    createdAt: DateTime.utc(2026),
                    shouldShowHeader: false,
                  ),
                  ChatThreadMessageView(
                    mine: false,
                    isAgentMessage: true,
                    text: 'agent response',
                    authorName: 'agent',
                    createdAt: DateTime.utc(2026),
                    shouldShowHeader: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final bubbles = find.byType(ChatBubble);
    final actionButtons = find.widgetWithIcon(ShadButton, LucideIcons.ellipsis);
    expect(actionButtons, findsNWidgets(2));

    final humanBubbleBottom = tester.getBottomRight(bubbles.at(0)).dy;
    final humanActionBottom = tester.getBottomRight(actionButtons.at(0)).dy;
    expect(humanActionBottom, closeTo(humanBubbleBottom, 0.01));

    final agentBubbleBounds = tester.getRect(bubbles.at(1));
    final agentActionBounds = tester.getRect(actionButtons.at(1));
    expect(agentActionBounds.bottom, closeTo(agentBubbleBounds.bottom, 0.01));
    expect(agentBubbleBounds.right - agentActionBounds.right, closeTo(8, 0.01));
    await disposeThreadWidget(tester);
  });
}
