import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';

/// Layout shared by every scenario: what to try, the form, and an optional
/// live view of the snapshot.
class ScenarioPage extends StatelessWidget {
  const ScenarioPage({
    super.key,
    required this.title,
    required this.whatToTry,
    required this.form,
    this.snapshot,
    this.header,
    this.bottomBar,
    this.actions,
  });

  final String title;

  /// Short checklist shown above the form.
  final List<String> whatToTry;

  final Widget form;

  /// When given, a collapsible panel shows the snapshot as it changes.
  final ValueListenable<FormSnapshot>? snapshot;

  /// Extra content between the checklist and the form.
  final Widget? header;

  final Widget? bottomBar;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final snapshot = this.snapshot;
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _WhatToTry(whatToTry),
          if (header case final header?) ...[
            const SizedBox(height: 16),
            header,
          ],
          const SizedBox(height: 16),
          form,
          if (snapshot != null) SnapshotInspector(snapshot),
        ],
      ),
      bottomNavigationBar: bottomBar == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: bottomBar,
              ),
            ),
    );
  }
}

class _WhatToTry extends StatelessWidget {
  const _WhatToTry(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      color: scheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What to try', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final step in steps)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $step'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Collapsible, live view of a [FormSnapshot]: values, errors (all of them,
/// not only the displayed ones), touched keys and flags.
class SnapshotInspector extends StatelessWidget {
  const SnapshotInspector(this.snapshot, {super.key});

  final ValueListenable<FormSnapshot> snapshot;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        title: const Text('Snapshot inspector'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<FormSnapshot>(
            valueListenable: snapshot,
            builder: (context, s, _) => SelectableText(
              [
                'isValid: ${s.isValid}',
                'submitAttempted: ${s.submitAttempted}',
                'visible: ${s.visibleFields.map((f) => f.key).join(', ')}',
                'touched: ${s.touched.join(', ')}',
                'errors: ${s.errors}',
                'values: ${s.values}',
              ].join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      );
}

/// Shows the submitted payload in a dialog.
Future<void> showPayload(BuildContext context, Map<String, Object?> payload) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submitted payload'),
        content: SelectableText(
          payload.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );

/// Save button that is enabled until the first failed attempt, then stays
/// disabled while the form is invalid. The first tap is what reveals every
/// error, so the user always learns why the button is disabled.
class SubmitButton extends StatelessWidget {
  const SubmitButton({
    super.key,
    required this.controller,
    required this.onValid,
    this.label = 'Submit',
  });

  final DynamicFormController controller;
  final void Function(Map<String, Object?> payload) onValid;
  final String label;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<FormSnapshot>(
        valueListenable: controller,
        builder: (context, s, _) => FilledButton(
          onPressed: s.submitAttempted && !s.isValid
              ? null
              : () {
                  if (controller.submit() case final payload?) onValid(payload);
                },
          child: Text(label),
        ),
      );
}
