import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';

/// Counts how many times each field's builder runs.
class BuildCounts {
  final counts = <String, int>{};

  int hit(String key) => counts[key] = (counts[key] ?? 0) + 1;

  int get total => counts.values.fold(0, (a, b) => a + b);
}

/// Wraps every builder of [inner] with a badge showing its build count.
FieldRegistry countingRegistry(
  Map<String, FieldBuilder> inner,
  BuildCounts counts,
) =>
    FieldRegistry()
      ..registerAll({
        for (final MapEntry(key: type, value: build) in inner.entries)
          type: (context, field) => Row(
                children: [
                  Expanded(child: build(context, field)),
                  const SizedBox(width: 8),
                  BuildBadge(counts.hit(field.def.path.toString())),
                ],
              ),
      });

/// How many times a field was built; tinted once it was built again.
class BuildBadge extends StatelessWidget {
  const BuildBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hot = count > 1;
    return Container(
      width: 36,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hot ? scheme.tertiaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$count', style: const TextStyle(fontSize: 12)),
    );
  }
}

/// The total of [counts], read after each frame.
class TotalBuilds extends StatefulWidget {
  const TotalBuilds(this.counts, {super.key});

  final BuildCounts counts;

  @override
  State<TotalBuilds> createState() => _TotalBuildsState();
}

class _TotalBuildsState extends State<TotalBuilds> {
  int total = 0;

  @override
  void didUpdateWidget(TotalBuilds oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshAfterFrame();
  }

  @override
  void initState() {
    super.initState();
    _refreshAfterFrame();
  }

  // Field builders run later in the same frame than this widget, so the
  // total is read once the frame is done.
  void _refreshAfterFrame() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && total != widget.counts.total) {
          setState(() => total = widget.counts.total);
        }
      });

  @override
  Widget build(BuildContext context) => Text(
        'Field builds so far: $total',
        style: Theme.of(context).textTheme.titleMedium,
      );
}
