// A number validator on a text field does not compile (design doc 0006 §1).
import 'package:formwork_core/formwork_core.dart';

final name = TextFieldDef('name', validators: [min(1000)]);
