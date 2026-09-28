import 'validation_error.dart';

/// How the last send of a form ended (design doc 0008 §2).
enum SubmitOutcome {
  /// The server accepted the payload.
  accepted,

  /// The server answered with errors.
  rejected,

  /// The send ended without an answer: a network error, a timeout, or the
  /// user cancelled.
  abandoned,
}

/// The facts about the whole form, as one value (design doc 0008 §1).
///
/// A snapshot keeps the identical status until one of these facts changes,
/// and statuses compare by value, so a UI can select and compare what it
/// reads.
final class FormStatus {
  /// A status; the defaults describe a fresh form.
  const FormStatus({
    this.errorCount = 0,
    this.formError,
    this.submitCount = 0,
    this.submitting = false,
    this.lastSubmit,
    this.validating = false,
    this.dirty = false,
  });

  /// The active fields with an error, shown or not.
  final int errorCount;

  /// The server's answer for the whole form, such as "wrong e-mail or
  /// password"; it does not block the next submit.
  final ValidationError? formError;

  /// The submit attempts so far.
  final int submitCount;

  /// Whether a send is in progress.
  final bool submitting;

  /// How the last send ended; `null` before the first.
  final SubmitOutcome? lastSubmit;

  /// Whether an asynchronous validation is pending.
  final bool validating;

  /// Whether any field differs from its initial value.
  final bool dirty;

  /// Whether no active field has an error.
  bool get isValid => errorCount == 0;

  /// Whether a submit was attempted, which shows every field's error.
  bool get submitAttempted => submitCount > 0;

  @override
  bool operator ==(Object other) =>
      other is FormStatus &&
      other.errorCount == errorCount &&
      other.formError == formError &&
      other.submitCount == submitCount &&
      other.submitting == submitting &&
      other.lastSubmit == lastSubmit &&
      other.validating == validating &&
      other.dirty == dirty;

  @override
  int get hashCode => Object.hash(errorCount, formError, submitCount,
      submitting, lastSubmit, validating, dirty);

  @override
  String toString() => 'FormStatus(errors: $errorCount, '
      'submits: $submitCount, submitting: $submitting, '
      'lastSubmit: ${lastSubmit?.name}, dirty: $dirty)';
}
