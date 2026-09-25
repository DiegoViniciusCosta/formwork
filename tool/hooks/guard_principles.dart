// PreToolUse hook: rejects an edit that would break principle 1 *before*
// it lands, with a message the agent can act on. Exit code 2 sends stderr
// back to the agent and blocks the tool call.
import 'dart:convert';
import 'dart:io';

final _flutterImport = RegExp(
  r'''import\s+['"](package:flutter(_test)?/|dart:ui)''',
);
final _visualImport = RegExp(
  r'''import\s+['"]package:flutter/(material|cupertino)\.dart''',
);
final _catalogImport = RegExp(
  r'''(import|export)\s+['"](\.\./catalog/|\.\./\.\./formwork_core\.dart|package:formwork_core/)''',
);

Future<void> main() async {
  final input =
      jsonDecode(await stdin.transform(utf8.decoder).join())
          as Map<String, dynamic>;
  final tool = (input['tool_input'] as Map?)?.cast<String, dynamic>() ?? {};
  final path = (tool['file_path'] as String? ?? '').replaceAll(r'\', '/');

  // Covers Write (content), Edit (new_string) and MultiEdit (edits[]).
  final text = [
    tool['content'],
    tool['new_string'],
    for (final e in (tool['edits'] as List? ?? const []))
      (e as Map)['new_string'],
  ].whereType<String>().join('\n');

  String? violation;
  if (path.contains('packages/formwork_core/') &&
      _flutterImport.hasMatch(text)) {
    violation =
        'Blocked: formwork_core must stay pure Dart (PRINCIPLES.md, '
        'principle 1), so a Dart backend can use it. Put Flutter code in '
        'packages/formwork/lib/src/flutter and keep the core '
        'framework-free.';
  } else if (path.contains('packages/formwork_core/lib/src/engine/') &&
      _catalogImport.hasMatch(text)) {
    violation =
        'Blocked: the engine must not import the catalog '
        '(design doc 0007). JSON is one front door to the engine; put the '
        'code that needs both in lib/src/catalog.';
  } else if (path.contains('packages/formwork/lib/') &&
      _visualImport.hasMatch(text)) {
    violation =
        'Blocked: formwork must not import material or cupertino '
        '(PRINCIPLES.md, principle 1). Use package:flutter/widgets.dart, and '
        'put visual builders in a satellite package such as formwork_material.';
  }

  if (violation != null) {
    stderr.writeln(violation);
    exit(2);
  }
}
