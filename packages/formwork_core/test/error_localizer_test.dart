import 'package:formwork_core/formwork_core.dart';
import 'package:test/test.dart';

void main() {
  test('the English localizer reads the params of built-in codes', () {
    expect(
      englishErrorLocalizer(
          ValidationError('minLength', params: {'min': 3}), TextFieldDef('a')),
      'Must be at least 3 characters',
    );
    expect(
        englishErrorLocalizer(ValidationError('nope'), null), 'Invalid value');
  });

  test("a field's own message wins over the localizer", () {
    final field = TextFieldDef('a', messages: {'required': 'Tell us'});
    expect(localizeError(ValidationError('required'), field), 'Tell us');
    expect(localizeError(ValidationError('email'), field),
        'Invalid email address');
  });

  test('a custom localizer handles what the field does not override', () {
    String pt(ValidationError e, FieldDef<Object?>? f) => 'erro: ${e.code}';
    expect(localizeError(ValidationError('email'), TextFieldDef('a'), pt),
        'erro: email');
  });
}
