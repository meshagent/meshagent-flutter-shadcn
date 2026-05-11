import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/code_language_resolver.dart';

void main() {
  test('resolveLanguageIdForFilename maps svg like the source viewer', () {
    expect(resolveLanguageIdForFilename('/tmp/pie_chart.svg'), 'xml');
    expect(resolveLanguageIdForFilename('/tmp/pie_chart.svgz'), 'xml');
  });
}
