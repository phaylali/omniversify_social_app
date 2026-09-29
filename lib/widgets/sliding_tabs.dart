import 'package:flutter/material.dart';

/// Plain bold labels with a gold underline that glides between them.
///
/// The tab treatment the scrolls screen introduced, in a form any screen can
/// drop in: labels sit on a hairline divider, and a single underline slides
/// under the active one over 300ms (easeOutCubic) instead of popping.
class SlidingTabs extends StatelessWidget {
  const SlidingTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onSelect,
  });

  final List<String> labels;

  /// Which label is active.
  final int index;

  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / labels.length;
            return Stack(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        child: InkWell(
                          key: ValueKey('tab-${labels[i]}'),
                          onTap: () {
                            if (i != index) onSelect(i);
                          },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                            child: Column(
                              children: [
                                Text(
                                  labels[i],
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                    color: i == index
                                        ? gold
                                        : cs.onSurface.withAlpha(140),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Reserves the underline's height, so the
                                // sliding indicator never changes the layout.
                                const SizedBox(height: 2.5),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  left: index * width,
                  width: width,
                  bottom: 0,
                  height: 2.5,
                  child: DecoratedBox(
                    key: const ValueKey('sliding-tabs-underline'),
                    decoration: BoxDecoration(
                      color: gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        Divider(height: 1, color: gold.withAlpha(60)),
      ],
    );
  }
}
