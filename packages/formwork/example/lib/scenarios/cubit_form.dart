import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

import '../shared/build_counts.dart';
import '../shared/scenario_page.dart';
import '../shared/signup.dart';

/// The form's state is a Cubit of [FormSnapshot]: the engine computes each
/// next snapshot, and the Cubit emits it. No [FormController].
class SignupCubit extends Cubit<FormSnapshot> {
  SignupCubit(this.fields, {required this.send})
      : super(engine.registerAll(engine.initial(), fields));

  static const engine = FormEngine();

  /// The fields of the form, in order.
  final List<FieldDef<Object?>> fields;

  /// Sends a valid payload, and returns the server's errors, if any.
  final FormSender send;

  void change(FieldPath path, Object? value) =>
      emit(engine.change(state, path, value));

  Future<void> submit() async {
    final result = engine.submit(state);
    emit(result.snapshot);
    final payload = result.payload;
    if (payload == null) return;
    emit(engine.startSubmitting(state));
    try {
      final answer = await send(payload);
      if (!isClosed) emit(engine.completeSubmit(state, answer));
    } catch (_) {
      // No answer: end the send, or the form stays submitting for good.
      if (!isClosed) emit(engine.abandonSubmit(state));
      rethrow;
    }
  }
}

/// Bloc: a `BlocSelector` per field feeds a [SnapshotFieldView], so a
/// change rebuilds only the fields whose state it changed.
class CubitScenario extends StatelessWidget {
  const CubitScenario({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => SignupCubit(
          FormCatalog.fromJson(signupCatalogJson).fields,
          send: fakeSignup, // your API call
        ),
        child: const _CubitSignupPage(),
      );
}

class _CubitSignupPage extends StatefulWidget {
  const _CubitSignupPage();

  @override
  State<_CubitSignupPage> createState() => _CubitSignupPageState();
}

class _CubitSignupPageState extends State<_CubitSignupPage> {
  final counts = BuildCounts();
  late final registry = countingRegistry(materialFieldBuilders, counts);

  /// Where the fields register their focus: this screen owns it.
  final focus = FormFocus();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SignupCubit>();
    return MultiBlocListener(
      listeners: [
        BlocListener<SignupCubit, FormSnapshot>(
          listenWhen: shouldFocusFirstError,
          listener: (context, s) => focus.requestFirstError(s),
        ),
        BlocListener<SignupCubit, FormSnapshot>(
          listenWhen: justAccepted,
          listener: (context, _) => ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Account created'))),
        ),
      ],
      child: ScenarioPage(
        title: 'Cubit (flutter_bloc)',
        whatToTry: signupWhatToTry,
        header: BlocBuilder<SignupCubit, FormSnapshot>(
          builder: (context, _) => TotalBuilds(counts),
        ),
        form: Column(
          children: [
            // A flat form: groups and lists would need their item fields
            // too (`snapshot.visibleFields`).
            for (final def in cubit.fields)
              BlocSelector<SignupCubit, FormSnapshot, (FieldState, bool)>(
                selector: (s) => (s.stateOf(def)!, s.status.submitAttempted),
                builder: (context, field) => SnapshotFieldView(
                  def,
                  state: field.$1,
                  submitAttempted: field.$2,
                  onChanged: (value) => cubit.change(def.path, value),
                  registry: registry,
                  localizer: signupLocalizer,
                  focus: focus,
                ),
              ),
            BlocSelector<SignupCubit, FormSnapshot, FormStatus>(
              selector: (s) => s.status,
              builder: (context, status) => SendStatusLine(status),
            ),
          ],
        ),
        bottomBar: BlocSelector<SignupCubit, FormSnapshot, bool>(
          selector: (s) => s.status.submitting,
          builder: (context, submitting) => SignupButton(
            submitting: submitting,
            onPressed: cubit.submit,
          ),
        ),
      ),
    );
  }
}
