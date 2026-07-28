import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_shadcn/code_language_resolver.dart';

void main() {
  test('resolveLanguageIdForFilename maps svg like the source viewer', () {
    expect(resolveLanguageIdForFilename('/tmp/pie_chart.svg'), 'xml');
    expect(resolveLanguageIdForFilename('/tmp/pie_chart.svgz'), 'xml');
  });

  test('resolveLanguageIdForFilename preserves extensions in filenames containing spaces', () {
    expect(resolveLanguageIdForFilename('/tmp/Project status dashboard/Status Dashboard.html'), 'xml');
    expect(resolveLanguageIdForFilename('/tmp/Project status dashboard/Status Dashboard.js'), 'javascript');
  });

  test('resolveLanguageIdForFilename never treats whitespace as filename syntax', () {
    expect(resolveLanguageIdForFilename('dart extra'), isNull);
  });
}
