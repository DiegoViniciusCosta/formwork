import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';

/// The sign-up form the state management scenarios share, as a server
/// would send it.
const signupCatalogJson = <String, dynamic>{
  'fields': [
    {
      'key': 'email',
      'type': 'email',
      'label': 'Email',
      'required': true,
      'validators': [
        {'type': 'email'},
      ],
    },
    {
      'key': 'password',
      'type': 'password',
      'label': 'Password',
      'required': true,
      'validators': [
        {'type': 'minLength', 'value': 8},
      ],
    },
    {
      'key': 'confirm',
      'type': 'password',
      'label': 'Confirm password',
      'required': true,
      'validators': [
        {'type': 'matches', 'field': 'password'},
      ],
    },
    {
      'key': 'accountType',
      'type': 'dropdown',
      'label': 'Account type',
      'required': true,
      'options': [
        {'value': 'personal', 'label': 'Personal'},
        {'value': 'company', 'label': 'Company'},
      ],
    },
    {
      'key': 'companyName',
      'type': 'text',
      'label': 'Company name',
      'required': true,
      'visibleWhen': {
        'eq': ['accountType', 'company'],
      },
    },
    {
      'key': 'news',
      'type': 'checkbox',
      'label': 'Send me product news',
    },
  ],
};

/// What to try, the same in every state management scenario.
const signupWhatToTry = [
  'The badge counts builds of each field. Type in Email: only its badge '
      'grows.',
  'Pick Company: Company name appears, and no other field rebuilds.',
  'Submit with taken@example.com: after a second the server rejects it '
      'on the e-mail field, and the focus jumps there.',
];

/// A fake sign-up API: rejects one e-mail, accepts anything else.
Future<ServerErrors?> fakeSignup(Map<String, Object?> payload) async {
  await Future<void>.delayed(const Duration(seconds: 1));
  return switch (payload) {
    {'email': 'taken@example.com'} =>
      ServerErrors(fields: {FieldPath('email'): ValidationError('taken')}),
    _ => null,
  };
}

/// Text for the server's error codes; English for the rest.
String signupLocalizer(ValidationError error, FieldDef<Object?>? field) =>
    switch (error.code) {
      'taken' => 'Already used by another account',
      _ => englishErrorLocalizer(error, field),
    };

/// Whether the change from [before] to [after] should move the focus to
/// the first error: a submit attempt that failed, or a rejected send.
bool shouldFocusFirstError(FormSnapshot before, FormSnapshot after) =>
    !after.status.isValid &&
    (after.status.submitCount > before.status.submitCount ||
        (after.status.lastSubmit == SubmitOutcome.rejected &&
            before.status.lastSubmit != SubmitOutcome.rejected));

/// Whether the server accepted the send between [before] and [after].
bool justAccepted(FormSnapshot before, FormSnapshot after) =>
    after.status.lastSubmit == SubmitOutcome.accepted &&
    before.status.lastSubmit != SubmitOutcome.accepted;

/// One line about the last send.
class SendStatusLine extends StatelessWidget {
  const SendStatusLine(this.status, {super.key});

  final FormStatus status;

  @override
  Widget build(BuildContext context) {
    final text = status.submitting
        ? 'Sending…'
        : switch (status.lastSubmit) {
            SubmitOutcome.accepted => 'Account created',
            SubmitOutcome.rejected => 'The server rejected the form',
            SubmitOutcome.abandoned => 'No answer from the server',
            null => '',
          };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text),
    );
  }
}

/// The call to action, disabled while a send is in flight.
class SignupButton extends StatelessWidget {
  const SignupButton({
    super.key,
    required this.submitting,
    required this.onPressed,
  });

  final bool submitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: submitting ? null : onPressed,
        child: Text(submitting ? 'Sending…' : 'Create account'),
      );
}
