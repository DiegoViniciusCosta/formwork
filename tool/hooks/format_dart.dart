// PostToolUse hook: formats the Dart file the agent just wrote, so format
// never shows up as a failure later. Never blocks.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final input = jsonDecode(await stdin.transform(utf8.decoder).join())
      as Map<String, dynamic>;
  final path = (input['tool_input'] as Map?)?['file_path'] as String?;
  if (path == null || !path.endsWith('.dart')) return;
  await Process.run('dart', ['format', path]);
}
