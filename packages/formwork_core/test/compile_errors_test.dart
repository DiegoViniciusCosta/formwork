import 'dart:io';

import 'package:test/test.dart';

/// Runs `dart analyze` on a fixture and returns the diagnostic codes.
Future<List<String>> _diagnostics(String fixture) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['analyze', '--format=machine', 'test/compile_errors/$fixture'],
  );
  // Machine format: SEVERITY|TYPE|CODE|file|line|column|length|message
  return [
    for (final line in '${result.stderr}${result.stdout}'.split('\n'))
      if (line.startsWith('ERROR|')) line.split('|')[2],
  ];
}

void main() {
  test('a number validator on a text field does not compile', () async {
    expect(
      await _diagnostics('min_on_text_field.dart'),
      contains('LIST_ELEMENT_TYPE_NOT_ASSIGNABLE'),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a string condition on an enum field does not compile', () async {
    expect(
      await _diagnostics('string_on_enum_field.dart'),
      contains('ARGUMENT_TYPE_NOT_ASSIGNABLE'),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
