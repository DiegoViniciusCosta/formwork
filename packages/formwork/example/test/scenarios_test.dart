import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadCheckbox, ShadInputDecorator, ShadTheme;
import 'package:formwork_example/main.dart';
import 'package:formwork_example/scenarios/all_field_types.dart';
import 'package:formwork_example/scenarios/conditional_fields.dart';
import 'package:formwork_example/scenarios/cubit_form.dart';
import 'package:formwork_example/scenarios/custom_field_types.dart';
import 'package:formwork_example/scenarios/custom_validators.dart';
import 'package:formwork_example/scenarios/external_state.dart';
import 'package:formwork_example/scenarios/groups_and_lists.dart';
import 'package:formwork_example/scenarios/profile_completion.dart';
import 'package:formwork_example/scenarios/rebuild_inspector.dart';
import 'package:formwork_example/shared/build_counts.dart';
import 'package:formwork_example/scenarios/riverpod_form.dart';
import 'package:formwork_example/scenarios/shadcn_form.dart';

Future<void> _open(WidgetTester t, Widget scenario) async {
  t.view.physicalSize = const Size(1080, 20000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    child: ShadTheme(
      data: shadcnTheme(),
      child: MaterialApp(home: scenario),
    ),
  ));
}

Finder _field(String label) => find.widgetWithText(TextField, label);

Finder _submit(String label) => find.widgetWithText(FilledButton, label);

bool _enabled(WidgetTester t, Finder button) =>
    t.widget<FilledButton>(button).onPressed != null;

Future<void> _pick(WidgetTester t, String label, String option) async {
  await t.tap(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(DropdownButtonFormField<Object?>),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text(option).last);
  await t.pumpAndSettle();
}

/// The total the build counter shows.
int _totalBuilds(WidgetTester t) => int.parse(
      RegExp(r'Field builds so far: (\d+)')
          .firstMatch(t
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data ?? '')
              .firstWhere((d) => d.startsWith('Field builds so far')))!
          .group(1)!,
    );

/// The build count the badge next to the field [label] shows.
int _badge(WidgetTester t, String label) => t
    .widget<BuildBadge>(find.descendant(
      of: find.ancestor(of: _field(label), matching: find.byType(Row)).first,
      matching: find.byType(BuildBadge),
    ))
    .count;

void main() {
  testWidgets('every scenario opens from the gallery', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: ShadTheme(
        data: shadcnTheme(),
        child: const MaterialApp(home: ScenarioGallery()),
      ),
    ));

    final titles = t
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data!)
        .toList();
    expect(titles, hasLength(12));

    for (final title in titles) {
      await t.tap(find.text(title));
      await t.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(t.takeException(), isNull, reason: title);
      await t.pageBack();
      await t.pumpAndSettle();
    }
  });

  group('groups and lists', () {
    testWidgets('adding past maxItems shows the error; removing all asks one',
        (t) async {
      await _open(t, const GroupsAndListsScenario());
      expect(_field('Dependent name'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await t.tap(find.text('Add dependent'));
        await t.pump();
      }
      expect(_field('Dependent name'), findsNWidgets(4));
      await t.tap(_submit('Submit'));
      await t.pump();
      expect(find.text('Allows at most 3 items'), findsOneWidget);

      for (var i = 4; i > 0; i--) {
        await t.tap(find.byTooltip('Remove dependent $i'));
        await t.pump();
      }
      expect(_field('Dependent name'), findsNothing);
      expect(find.text('Needs at least 1 item'), findsOneWidget);
    });
  });

  group('profile completion', () {
    testWidgets('renewal: answering "no" hides the vehicle chain and saves',
        (t) async {
      await _open(t, const ProfileCompletionScenario());
      await t.tap(find.text('Renewal'));
      await t.pumpAndSettle();
      expect(find.text('Do you have a vehicle?'), findsOneWidget);
      expect(_field('License plate'), findsNothing);

      await _pick(t, 'Do you have a vehicle?', 'No');
      await t.tap(find.widgetWithText(FilledButton, 'Save'));
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();

      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('a form error from the server shows under the form', (t) async {
      await _open(t, const ProfileCompletionScenario());
      await t.tap(find.text('Complete'));
      await t.pumpAndSettle();
      await t.tap(find.text('Highlight missing'));
      await t.pumpAndSettle();
      await t.enterText(_field('Tax ID'), '00000000000');
      await t.tap(find.widgetWithText(FilledButton, 'Save'));
      await t.pump();
      expect(find.widgetWithText(FilledButton, 'Sending…'), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(find.text('This account is locked: call support'), findsOneWidget);
    });

    testWidgets('renewal: answering "yes" shows the known type prefilled',
        (t) async {
      await _open(t, const ProfileCompletionScenario());
      await t.tap(find.text('Renewal'));
      await t.pumpAndSettle();

      await _pick(t, 'Do you have a vehicle?', 'Yes');

      expect(find.text('Car'), findsOneWidget);
      expect(_field('License plate'), findsOneWidget);
    });

    testWidgets('highlight mode shows the whole form, prefilled', (t) async {
      await _open(t, const ProfileCompletionScenario());
      await t.tap(find.text('Highlight missing'));
      await t.pumpAndSettle();

      expect(_field('Full name'), findsOneWidget);
      expect(find.text('Maria Silva'), findsOneWidget);
      expect(_field('Monthly income'), findsOneWidget);
    });
  });

  group('all field types', () {
    testWidgets('first submit reveals errors and disables the button',
        (t) async {
      await _open(t, const AllFieldTypesScenario());
      final submit = _submit('Create account');
      expect(find.text('This field is required'), findsNothing);
      expect(_enabled(t, submit), isTrue);

      await t.tap(submit);
      await t.pump();

      expect(find.text('This field is required'), findsWidgets);
      expect(_enabled(t, submit), isFalse);
    });

    testWidgets('shows only the first failing validator', (t) async {
      await _open(t, const AllFieldTypesScenario());
      await t.enterText(_field('Username'), 'AB');
      await t.pump();

      expect(find.text('Must be at least 3 characters'), findsOneWidget);
      expect(find.text('Only lowercase letters and digits'), findsNothing);
    });

    testWidgets('an optional field is valid when empty only', (t) async {
      await _open(t, const AllFieldTypesScenario());
      await t.enterText(_field('Website (optional)'), 'www.x.com');
      await t.pump();
      expect(find.text('Must start with http:// or https://'), findsOneWidget);

      await t.enterText(_field('Website (optional)'), '');
      await t.pump();
      expect(find.text('Must start with http:// or https://'), findsNothing);
    });
  });

  group('conditional fields', () {
    testWidgets('one controller swaps several dependents', (t) async {
      await _open(t, const ConditionalFieldsScenario());
      expect(_field('Phone'), findsNothing);

      await _pick(t, 'Preferred contact', 'Phone');
      expect(_field('Phone'), findsOneWidget);
      expect(find.text('Best time to call'), findsOneWidget);

      await _pick(t, 'Preferred contact', 'Email');
      expect(_field('Phone'), findsNothing);
      expect(_field('Contact email'), findsOneWidget);
    });

    testWidgets(
      'hiding a field also hides the fields that depend on it',
      (t) async {
        await _open(t, const ConditionalFieldsScenario());
        await t.tap(find.text('I have a vehicle'));
        await t.pumpAndSettle();
        await _pick(t, 'Vehicle type', 'Car');
        expect(_field('License plate'), findsOneWidget);

        await t.tap(find.text('I have a vehicle'));
        await t.pumpAndSettle();

        expect(_field('License plate'), findsNothing);
      },
    );
  });

  group('custom validators', () {
    testWidgets('validates CPF check digits', (t) async {
      await _open(t, const CustomValidatorsScenario());
      await t.enterText(_field('CPF'), '529.982.247-26');
      await t.pump();
      expect(find.text('Invalid CPF'), findsOneWidget);

      await t.enterText(_field('CPF'), '529.982.247-25');
      await t.pump();
      expect(find.text('Invalid CPF'), findsNothing);
    });

    testWidgets('rejects impossible dates and minors', (t) async {
      await _open(t, const CustomValidatorsScenario());
      await t.enterText(_field('Birth date'), '31/02/2000');
      await t.pump();
      expect(find.text('Use dd/mm/yyyy'), findsOneWidget);

      final now = DateTime.now();
      final minor = '01/01/${now.year - 17}';
      await t.enterText(_field('Birth date'), minor);
      await t.pump();
      expect(find.text('You must be at least 18'), findsOneWidget);
    });

    testWidgets('reports the validator the app does not know', (t) async {
      await _open(t, const CustomValidatorsScenario());
      expect(find.text('Skipped: iban iban'), findsOneWidget);
    });
  });

  group('custom field types', () {
    testWidgets('app builders drive values and validation', (t) async {
      await _open(t, const CustomFieldTypesScenario());
      expect(
        find.text('Skipped: signature (signature)'),
        findsOneWidget,
      );

      await t.tap(find.byIcon(Icons.star_border).at(1)); // 2 stars
      await t.pump();
      expect(find.text('Tell us what went wrong below'), findsOneWidget);

      await t.tap(find.byIcon(Icons.star_border).last); // 5 stars
      await t.pump();
      expect(find.text('Tell us what went wrong below'), findsNothing);
      expect(find.byIcon(Icons.star), findsNWidgets(5));
    });
  });

  group('rebuild inspector', () {
    testWidgets('typing in one field rebuilds only that field', (t) async {
      await _open(t, const RebuildInspectorScenario());
      await t.pumpAndSettle();
      expect(find.text('Field builds so far: 49'), findsOneWidget);

      await t.enterText(_field('Field 1'), 'abc');
      await t.pumpAndSettle();

      expect(find.text('Field builds so far: 50'), findsOneWidget);
    });
  });

  group('external state', () {
    testWidgets('undo restores the previous snapshot', (t) async {
      await _open(t, const ExternalStateScenario());
      await t.tap(find.text('Notify the team'));
      await t.pump();
      expect(find.text('History: 2 snapshot(s)'), findsOneWidget);

      await t.tap(find.byTooltip('Undo'));
      await t.pump();

      expect(find.text('History: 1 snapshot(s)'), findsOneWidget);
      final checkbox =
          t.widget<CheckboxListTile>(find.byType(CheckboxListTile));
      expect(checkbox.value, isFalse);
    });

    String titleText(WidgetTester t) =>
        t.widget<TextField>(_field('Title')).controller!.text;

    testWidgets('text fields follow values set from outside', (t) async {
      await _open(t, const ExternalStateScenario());
      await t.tap(find.byTooltip('Fill sample'));
      await t.pump();
      expect(titleText(t), 'Fix login crash');

      await t.tap(find.byTooltip('Reset'));
      await t.pump();
      expect(titleText(t), '');
    });

    testWidgets('undo steps a text field back', (t) async {
      await _open(t, const ExternalStateScenario());
      await t.enterText(_field('Title'), 'Fix');
      await t.pump();
      await t.enterText(_field('Title'), 'Fix login');
      await t.pump();

      await t.tap(find.byTooltip('Undo'));
      await t.pump();

      expect(titleText(t), 'Fix');
    });
  });

  for (final (name, scenario) in [
    ('cubit', const CubitScenario()),
    ('riverpod', const RiverpodScenario()),
  ]) {
    group(name, () {
      testWidgets('typing in one field rebuilds only that field', (t) async {
        await _open(t, scenario);
        await t.pumpAndSettle();
        final before = _totalBuilds(t);

        await t.enterText(_field('Email'), 'a');
        await t.pumpAndSettle();

        expect(_totalBuilds(t), before + 1);
        expect(_badge(t, 'Email'), 2);
      });

      testWidgets('picking Company shows Company name, and rebuilds no other',
          (t) async {
        await _open(t, scenario);
        await t.pumpAndSettle();
        final before = _totalBuilds(t);
        expect(_field('Company name'), findsNothing);

        await _pick(t, 'Account type', 'Company');

        expect(_field('Company name'), findsOneWidget);
        // Account type changed, Company name appeared: nothing else.
        expect(_totalBuilds(t), before + 2);
      });

      testWidgets('a field error from the server shows on its field, focused',
          (t) async {
        await _open(t, scenario);
        await t.enterText(_field('Email'), 'taken@example.com');
        await t.enterText(_field('Password'), 'secret123');
        await t.enterText(_field('Confirm password'), 'secret123');
        await _pick(t, 'Account type', 'Personal');
        final email = t.widget<EditableText>(find.descendant(
          of: _field('Email'),
          matching: find.byType(EditableText),
        ));
        expect(email.focusNode.hasFocus, isFalse);

        await t.tap(_submit('Create account'));
        await t.pump();
        expect(find.text('Sending…'), findsWidgets);

        await t.pump(const Duration(seconds: 1));
        await t.pumpAndSettle();
        expect(find.text('Already used by another account'), findsOneWidget);
        expect(find.text('The server rejected the form'), findsOneWidget);
        expect(email.focusNode.hasFocus, isTrue);
      });

      testWidgets('an accepted send says so', (t) async {
        await _open(t, scenario);
        await t.enterText(_field('Email'), 'ada@example.com');
        await t.enterText(_field('Password'), 'secret123');
        await t.enterText(_field('Confirm password'), 'secret123');
        await _pick(t, 'Account type', 'Personal');

        await t.tap(_submit('Create account'));
        await t.pump(const Duration(seconds: 1));
        await t.pumpAndSettle();
        expect(find.text('Account created'), findsWidgets);
      });
    });
  }

  group('your design system (shadcn_ui)', () {
    Finder input(String label) => find.descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byType(ShadInputDecorator),
          ),
          matching: find.byType(EditableText),
        );

    Future<void> select(WidgetTester t, String option) async {
      await t.tap(find.text('Select…'));
      await t.pumpAndSettle();
      await t.tap(find.text(option).last);
      await t.pumpAndSettle();
    }

    testWidgets('submitting empty shows the errors in shadcn style', (t) async {
      await _open(t, const ShadcnScenario());
      await t.tap(find.text('Create account'));
      await t.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.text('This field is required'),
          matching: find.byType(ShadInputDecorator),
        ),
        findsNWidgets(4),
      );
    });

    testWidgets('picking Company in the select shows Company name', (t) async {
      await _open(t, const ShadcnScenario());
      expect(find.text('Company name'), findsNothing);
      await select(t, 'Company');
      expect(find.text('Company name'), findsOneWidget);
    });

    testWidgets('every component follows values set from outside', (t) async {
      await _open(t, const ShadcnScenario());
      await t.tap(find.byTooltip('Fill sample'));
      await t.pumpAndSettle();
      expect(find.text('Company'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget);
      expect(t.widget<ShadCheckbox>(find.byType(ShadCheckbox)).value, isTrue);

      await t.tap(find.byTooltip('Clear'));
      await t.pumpAndSettle();
      expect(find.text('Select…'), findsOneWidget);
      expect(find.text('Company name'), findsNothing);
      expect(find.text('ada@example.com'), findsNothing);
      expect(t.widget<ShadCheckbox>(find.byType(ShadCheckbox)).value, isFalse);
    });

    testWidgets('a field error from the server shows on its field, focused',
        (t) async {
      await _open(t, const ShadcnScenario());
      await t.enterText(input('Email'), 'taken@example.com');
      await t.enterText(input('Password'), 'secret123');
      await t.enterText(input('Confirm password'), 'secret123');
      await select(t, 'Personal');
      await t.tap(find.text('Send me product news'));
      await t.pump();
      expect(t.widget<ShadCheckbox>(find.byType(ShadCheckbox)).value, isTrue);
      final email = t.widget<EditableText>(input('Email'));
      expect(email.focusNode.hasFocus, isFalse);

      await t.tap(find.text('Create account'));
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();

      expect(find.text('Already used by another account'), findsOneWidget);
      expect(email.focusNode.hasFocus, isTrue);
    });
  });
}
