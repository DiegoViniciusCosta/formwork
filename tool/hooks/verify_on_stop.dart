// Stop hook: before the agent declares a task done, runs the fast
// verification if Dart code or a pubspec changed. On failure, exit code 2
// feeds the tail of the report back to the agent and keeps it working.
//
// Loop guard: if the agent is already continuing because of this hook
// (stop_hook_active), it is allowed to stop. One retry locally; CI remains
// the final gate. Without the guard, an unfixable failure loops forever.
import 'dart:convert';
import 'dart:io';

const _maxLines = 80;

Future<void> main() async {
  final input = jsonDecode(await stdin.transform(utf8.decoder).join())
      as Map<String, dynamic>;
  if (input['stop_hook_active'] == true) return;

  final root = Platform.environment['CLAUDE_PROJECT_DIR'] ?? '.';
  final status = await Process.run(
    'git',
    ['status', '--porcelain'],
    workingDirectory: root,
  );
  final touchedCode = (status.stdout as String)
      .split('\n')
      .any((l) => l.trim().endsWith('.dart') || l.contains('pubspec.yaml'));
  if (!touchedCode) return;

  final verify = await Process.run(
    'bash',
    ['tool/verify.sh', '--fast'],
    workingDirectory: root,
  );
  if (verify.exitCode == 0) return;

  final lines = '${verify.stdout}\n${verify.stderr}'.trim().split('\n');
  final tail = lines.length > _maxLines
      ? lines.sublist(lines.length - _maxLines)
      : lines;
  stderr
    ..writeln('tool/verify.sh --fast failed. Fix these before finishing:')
    ..writeln(tail.join('\n'));
  exit(2);
}
