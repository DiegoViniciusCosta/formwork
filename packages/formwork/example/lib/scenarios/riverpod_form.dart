import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

import '../shared/build_counts.dart';
import '../shared/scenario_page.dart';
import '../shared/signup.dart';

/// The catalog, as it would come from a repository.
final signupCatalogProvider =
    Provider((ref) => FormCatalog.fromJson(signupCatalogJson));

/// Sends a valid payload, and returns the server's errors, if any.
final signupSenderProvider = Provider<FormSender>(
  (ref) => fakeSignup, // your API call
);

/// The form's state is a Notifier of [FormSnapshot]: the engine computes
/// each next snapshot. No [FormController]. Disposed when the screen
/// leaves, so the form starts over each time it opens.
final signupProvider =
    NotifierProvider.autoDispose<SignupNotifier, FormSnapshot>(
        SignupNotifier.new);

class SignupNotifier extends Notifier<FormSnapshot> {
  static const engine = FormEngine();

  @override
  FormSnapshot build() => engine.registerAll(
        engine.initial(),
        ref.watch(signupCatalogProvider).fields,
      );

  void change(FieldPath path, Object? value) =>
      state = engine.change(state, path, value);

  Future<void> submit() async {
    final result = engine.submit(state);
    state = result.snapshot;
    final payload = result.payload;
    if (payload == null) return;
    state = engine.startSubmitting(state);
    try {
      final answer = await ref.read(signupSenderProvider)(payload);
      if (ref.mounted) state = engine.completeSubmit(state, answer);
    } catch (_) {
      // No answer: end the send, or the form stays submitting for good.
      if (ref.mounted) state = engine.abandonSubmit(state);
      rethrow;
    }
  }
}

/// Riverpod: each field watches its own state with `select` and feeds a
/// [SnapshotFieldView], so a change rebuilds only the fields whose state
/// it changed.
class RiverpodScenario extends ConsumerStatefulWidget {
  const RiverpodScenario({super.key});

  @override
  ConsumerState<RiverpodScenario> createState() => _RiverpodScenarioState();
}

class _RiverpodScenarioState extends ConsumerState<RiverpodScenario> {
  final counts = BuildCounts();
  late final registry = countingRegistry(materialFieldBuilders, counts);

  /// Where the fields register their focus: this screen owns it.
  final focus = FormFocus();

  @override
  Widget build(BuildContext context) {
    ref.listen(signupProvider, (before, after) {
      if (before == null) return;
      if (shouldFocusFirstError(before, after)) focus.requestFirstError(after);
      if (justAccepted(before, after)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Account created')));
      }
    });
    final fields = ref.watch(signupCatalogProvider).fields;
    return ScenarioPage(
      title: 'Riverpod',
      whatToTry: signupWhatToTry,
      header: Consumer(
        builder: (context, ref, _) {
          ref.watch(signupProvider);
          return TotalBuilds(counts);
        },
      ),
      form: Column(
        children: [
          // A flat form: groups and lists would need their item fields
          // too (`snapshot.visibleFields`).
          for (final def in fields)
            Consumer(
              builder: (context, ref, _) => SnapshotFieldView(
                def,
                state: ref.watch(signupProvider.select((s) => s.stateOf(def)!)),
                submitAttempted: ref.watch(
                    signupProvider.select((s) => s.status.submitAttempted)),
                onChanged: (value) =>
                    ref.read(signupProvider.notifier).change(def.path, value),
                registry: registry,
                localizer: signupLocalizer,
                focus: focus,
              ),
            ),
          Consumer(
            builder: (context, ref, _) => SendStatusLine(
                ref.watch(signupProvider.select((s) => s.status))),
          ),
        ],
      ),
      bottomBar: Consumer(
        builder: (context, ref, _) => SignupButton(
          submitting:
              ref.watch(signupProvider.select((s) => s.status.submitting)),
          onPressed: () => ref.read(signupProvider.notifier).submit(),
        ),
      ),
    );
  }
}
