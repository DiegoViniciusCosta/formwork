// Timing of one change, against the targets of design doc 0002: change()
// under 50 µs at 10,000 fields. Outside CI, where timing is too noisy to
// gate on. Run from packages/formwork_core:
//
//   dart run tool/bench/change_bench.dart          (JIT)
//   dart compile exe tool/bench/change_bench.dart  (closer to release)
import 'package:formwork_core/formwork_core.dart' hide FormEngine, FormSnapshot;
import 'package:formwork_core/src/engine/engine.dart';

void main() {
  const engine = FormEngine();
  for (final size in [100, 1000, 10000]) {
    final defs = [
      for (var i = 0; i < size; i++)
        _Text('f$i',
            required: true, visibleWhen: i.isOdd ? eq('toggle', 'on') : null),
    ];
    var s = engine.registerAll(
      engine.initial(initialValues: {'toggle': 'on'}),
      defs,
    );
    final typed = FieldPath('f${size ~/ 2}');

    // Warm up, then measure typing into one field.
    for (var i = 0; i < 2000; i++) {
      s = engine.change(s, typed, 'v$i');
    }
    const runs = 20000;
    final watch = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      s = engine.change(s, typed, i.isEven ? '' : 'v$i');
    }
    final perChange = watch.elapsedMicroseconds / runs;
    print('$size fields: ${perChange.toStringAsFixed(2)} µs per change '
        '(typing, error toggling)');
  }
}

final class _Text extends FieldDef<String> {
  _Text(super.key, {super.required, super.visibleWhen});

  @override
  String get type => 'text';
}
