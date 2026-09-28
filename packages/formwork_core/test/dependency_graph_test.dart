import 'package:formwork_core/formwork_core.dart';
import 'package:formwork_core/src/engine/dependency_graph.dart';
import 'package:test/test.dart';

FieldPath p(String path) => FieldPath(path);

Set<FieldPath> paths(Iterable<String> texts) => {for (final t in texts) p(t)};

void main() {
  group('DependencyGraph', () {
    test('indexes each path to the fields whose rules read it', () {
      final graph = const DependencyGraph.empty()
          .add(p('spouseName'), conditionReads: paths(['maritalStatus']))
          .add(p('spouseAge'), conditionReads: paths(['maritalStatus']))
          .add(p('confirm'), validatorReads: paths(['password']));

      expect(
        graph.conditionDependents(p('maritalStatus')).toSet(),
        paths(['spouseName', 'spouseAge']),
      );
      expect(
          graph.validatorDependents(p('password')).toSet(), paths(['confirm']));
      expect(graph.conditionDependents(p('password')), isEmpty);
      expect(graph.conditionReadsOf(p('spouseName')), paths(['maritalStatus']));
    });

    test('adding a field again replaces its edges', () {
      final graph = const DependencyGraph.empty()
          .add(p('b'), conditionReads: paths(['a']))
          .add(p('b'), conditionReads: paths(['c']));

      expect(graph.conditionDependents(p('a')), isEmpty);
      expect(graph.conditionDependents(p('c')).toSet(), paths(['b']));
    });

    test('removing a field removes its edges, and keeps edges to it', () {
      final graph = const DependencyGraph.empty()
          .add(p('b'), conditionReads: paths(['a']))
          .add(p('c'), conditionReads: paths(['b']))
          .remove(p('b'));

      expect(graph.conditionDependents(p('a')), isEmpty);
      expect(graph.conditionReadsOf(p('b')), isEmpty);
      // c still reads b: unregistering b makes c inactive, not unlinked.
      expect(graph.conditionDependents(p('b')).toSet(), paths(['c']));
    });

    test('a change never alters the previous graph', () {
      final before = const DependencyGraph.empty()
          .add(p('b'), conditionReads: paths(['a']));
      before.add(p('c'), conditionReads: paths(['a'])).remove(p('b'));
      expect(before.conditionDependents(p('a')).toSet(), paths(['b']));
    });

    test('an unchanged add or remove returns the identical graph', () {
      final graph = const DependencyGraph.empty()
          .add(p('b'), conditionReads: paths(['a']));
      expect(
        identical(graph.add(p('b'), conditionReads: paths(['a'])), graph),
        isTrue,
      );
      expect(identical(graph.remove(p('x')), graph), isTrue);
    });
  });

  group('cycles', () {
    test('a condition reading its own field is a cycle', () {
      expect(
        () => const DependencyGraph.empty()
            .add(p('a'), conditionReads: paths(['a'])),
        throwsA(isA<CycleError>()
            .having((e) => e.paths, 'paths', [p('a'), p('a')])),
      );
    });

    test('closing a chain of conditions throws, naming the paths', () {
      final graph = const DependencyGraph.empty()
          .add(p('b'), conditionReads: paths(['a']))
          .add(p('c'), conditionReads: paths(['b']));

      expect(
        () => graph.add(p('a'), conditionReads: paths(['c'])),
        throwsA(isA<CycleError>().having((e) => e.paths, 'paths', [
          p('a'),
          p('c'),
          p('b'),
          p('a')
        ]).having((e) => e.toString(), 'message', contains('a → c → b → a'))),
      );
    });

    test('a cycle through a replaced definition is found', () {
      final graph = const DependencyGraph.empty()
          .add(p('b'), conditionReads: paths(['x']))
          .add(p('a'), conditionReads: paths(['b']));
      expect(
        () => graph.add(p('b'), conditionReads: paths(['a'])),
        throwsA(isA<CycleError>()),
      );
    });

    test('a diamond is not a cycle', () {
      final graph = const DependencyGraph.empty()
          .add(p('b'), conditionReads: paths(['a']))
          .add(p('c'), conditionReads: paths(['a']))
          .add(p('d'), conditionReads: paths(['b', 'c']));
      expect(graph.conditionDependents(p('b')).toSet(), paths(['d']));
    });

    test('a diamond registered bottom-up walks and finds no cycle', () {
      final graph = const DependencyGraph.empty()
          .add(p('d'), conditionReads: paths(['b', 'c']))
          .add(p('b'), conditionReads: paths(['a']))
          .add(p('c'), conditionReads: paths(['a']))
          .add(p('a'), conditionReads: paths(['x']));
      expect(graph.conditionReadsOf(p('a')), paths(['x']));
      expect(graph.conditionDependents(p('a')).toSet(), paths(['b', 'c']));
    });

    test('validators that read each other are not a cycle', () {
      final graph = const DependencyGraph.empty()
          .add(p('password'), validatorReads: paths(['confirm']))
          .add(p('confirm'), validatorReads: paths(['password']));
      expect(
          graph.validatorDependents(p('confirm')).toSet(), paths(['password']));
    });

    test('a failed add leaves the graph usable', () {
      final graph = const DependencyGraph.empty()
          .add(p('b'), conditionReads: paths(['a']));
      expect(() => graph.add(p('a'), conditionReads: paths(['b'])),
          throwsA(isA<CycleError>()));
      expect(graph.conditionReadsOf(p('a')), isEmpty);
      expect(graph.add(p('c'), conditionReads: paths(['b'])),
          isA<DependencyGraph>());
    });
  });

  test('a cycle through a very long chain is found without a stack overflow',
      () {
    var graph = const DependencyGraph.empty();
    for (var i = 1; i < 50000; i++) {
      graph = graph.add(p('f$i'), conditionReads: paths(['f${i - 1}']));
    }
    expect(
      () => graph.add(p('f0'), conditionReads: paths(['f49999'])),
      throwsA(isA<CycleError>()
          .having((e) => e.paths.length, 'length', 50001)
          .having((e) => e.paths.first, 'first', p('f0'))
          .having((e) => e.paths.last, 'last', p('f0'))),
    );
  });

  test('dependents of one path scale to many fields', () {
    var graph = const DependencyGraph.empty();
    for (var i = 0; i < 10000; i++) {
      graph = graph.add(p('f$i'), conditionReads: paths(['toggle']));
    }
    expect(graph.conditionDependents(p('toggle')).length, 10000);
  });
}
