import 'package:flutter/material.dart';

import '../services/rtn.dart';

/// Data carried per second over the last minute: one series, one hue, bars
/// on a shared baseline. Each bar names its second and value on hover, focus
/// or long press, and the whole chart has a one-line summary for screen readers.
class const TrafficChart({super.key, required final List<Map<String, Object?>> series, required final int seriesFrom})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<int> bytes = <int>[for (final Map<String, Object?> s in series) asInt(s['data_bytes'])];
    final int peak = bytes.fold(0, (int a, int b) => a > b ? a : b);
    final int total = bytes.fold(0, (int a, int b) => a + b);
    String second(int index) {
      final DateTime at = DateTime.fromMillisecondsSinceEpoch((seriesFrom + index) * 1000).toLocal();
      return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}:${at.second.toString().padLeft(2, '0')}';
    }

    return Column(
      crossAxisAlignment: .start,
      spacing: 8,
      children: <Widget>[
        Text('Data per second, last 60 seconds', style: theme.textTheme.titleMedium),
        Text(
          'Total ${dataSize(total)}, busiest second ${dataSize(peak)}.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        SizedBox(
          height: 140,
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double slot = constraints.maxWidth / (bytes.isEmpty ? 1 : bytes.length);
                return Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
                  ),
                  child: Row(
                    crossAxisAlignment: .end,
                    children: <Widget>[
                      for (int i = 0; i < bytes.length; i++)
                        Tooltip(
                          message: '${second(i)}: ${dataSize(bytes[i])}',
                          child: SizedBox(
                            width: slot,
                            height: constraints.maxHeight,
                            child: Align(
                              alignment: .bottomCenter,
                              child: Container(
                                width: (slot - 2).clamp(1, 24),
                                height: peak == 0 ? 0 : (constraints.maxHeight - 4) * bytes[i] / peak,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        DefaultTextStyle(
          style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
          child: Row(children: <Widget>[
            Text(bytes.isEmpty ? '' : second(0)),
            const Spacer(),
            Text(bytes.isEmpty ? '' : second(bytes.length - 1)),
          ]),
        ),
      ],
    );
  }
}
