import 'package:meshagent/meshagent.dart';
import 'package:meshagent_flutter_shadcn/chat/file_prompt_actions.dart';
import 'package:test/test.dart';

void main() {
  group('resolveChatFilePromptActions', () {
    test('returns sorted matching prompt actions for file annotations', () {
      final services = [
        ServiceSpec(
          metadata: ServiceMetadata(name: 'Docs'),
          agents: [
            AgentSpec(
              name: 'Reviewer',
              channels: ChannelsSpec(
                chat: [
                  ChatChannel(
                    prompts: [
                      PromptTemplate(
                        name: 'Summarize',
                        description: 'Summarize the file',
                        prompt: 'Summarize {{file}}',
                        annotations: {annotationFilePrompt: r'\.md$'},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ServiceSpec(
          metadata: ServiceMetadata(name: 'Code'),
          agents: [
            AgentSpec(
              name: 'Refactor Bot',
              channels: ChannelsSpec(
                chat: [
                  ChatChannel(
                    prompts: [
                      PromptTemplate(
                        name: 'Refactor',
                        description: 'Refactor the selected file',
                        prompt: 'Refactor {{file}}',
                        annotations: {annotationFilePrompt: r'^src/.*\.dart$'},
                      ),
                      PromptTemplate(
                        name: 'Broken',
                        description: 'Should be ignored',
                        prompt: 'Ignore me',
                        annotations: {annotationFilePrompt: r'('},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ];

      final actions = resolveChatFilePromptActions(services: services, filePath: 'src/app.dart');

      expect(actions.map((action) => action.menuLabel).toList(), ['Refactor (Refactor Bot)']);
      expect(actions.single.renderPrompt('src/app.dart'), 'Refactor src/app.dart');
    });

    test('matches nested markdown paths and sorts alphabetically', () {
      final services = [
        ServiceSpec(
          metadata: ServiceMetadata(name: 'B'),
          agents: [
            AgentSpec(
              name: 'Beta',
              channels: ChannelsSpec(
                chat: [
                  ChatChannel(
                    prompts: [
                      PromptTemplate(
                        name: 'Summarize',
                        description: 'Summarize a markdown file',
                        prompt: 'Summarize {{file}}',
                        annotations: {annotationFilePrompt: r'\.md$'},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ServiceSpec(
          metadata: ServiceMetadata(name: 'A'),
          agents: [
            AgentSpec(
              name: 'Alpha',
              channels: ChannelsSpec(
                chat: [
                  ChatChannel(
                    prompts: [
                      PromptTemplate(
                        name: 'Explain',
                        description: 'Explain a docs file',
                        prompt: 'Explain {{file}}',
                        annotations: {annotationFilePrompt: r'^docs/'},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ];

      final actions = resolveChatFilePromptActions(services: services, filePath: 'docs/guide.md');

      expect(actions.map((action) => action.menuLabel).toList(), ['Explain (Alpha)', 'Summarize (Beta)']);
    });

    test('inherits file regex annotations from the service metadata', () {
      final services = [
        ServiceSpec(
          metadata: ServiceMetadata(name: 'Docs', annotations: {annotationFilePrompt: r'^docs/.*\.md$'}),
          agents: [
            AgentSpec(
              name: 'Reviewer',
              channels: ChannelsSpec(
                chat: [
                  ChatChannel(
                    prompts: [PromptTemplate(name: 'Review docs', description: 'Review a docs file', prompt: 'Review {{file}}')],
                  ),
                ],
              ),
            ),
          ],
        ),
      ];

      final actions = resolveChatFilePromptActions(services: services, filePath: 'docs/guide.md');

      expect(actions.map((action) => action.menuLabel).toList(), ['Review docs (Reviewer)']);
    });
  });
}
