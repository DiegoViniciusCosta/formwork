// A condition on an enum field takes the enum, not a string (design doc
// 0006 §1).
import 'package:formwork_core/formwork_core.dart';

enum MaritalStatus { single, married }

final status = ChoiceFieldDef<MaritalStatus>('status',
    options: [for (final s in MaritalStatus.values) Option(s, s.name)]);

final condition = status.equals('married');
