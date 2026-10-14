// RTN's building blocks: page frame, headings, panels, stat tiles, notices.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

/// A page's scrolling column, centred and no wider than reads well.
class const PageFrame({super.key, required final List<Widget> children}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const .symmetric(horizontal: 16, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: DVBox.list(children, spacing: 20),
          ),
        ),
      );
}

/// The page's title, as a heading for assistive technology, and a line under it.
class const PageHeading(final String title, {super.key, final String? subtitle}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return DVBox.list(<Widget>[
      Semantics(
        header: true,
        child: Text(title, style: text.headlineMedium?.copyWith(fontWeight: .w700)),
      ),
      if (subtitle != null)
        Text(subtitle!, style: text.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ], crossAlign: .start, spacing: 6);
  }
}

/// A section title inside a page.
class const SectionTitle(final String title, {super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: .w600)),
      );
}

/// A bordered card with padding.
class const Panel({super.key, required final Widget child, final EdgeInsetsGeometry padding = const .all(20)})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: padding, child: child));
}

/// One figure with its label, as on a dashboard.
class const StatTile({
  super.key,
  required final String label,
  required final String value,
  final String? note,
  final bool accent = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color colour = accent ? theme.colorScheme.secondary : theme.colorScheme.primary;
    return Panel(
      padding: const .all(16),
      child: DVBox.list(<Widget>[
        Text(label, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .w700, color: colour)),
        if (note != null) Text(note!, style: theme.textTheme.bodySmall),
      ], crossAlign: .start, spacing: 4),
    );
  }
}

/// Tiles in as many columns as fit.
class const TileGrid({super.key, required final List<Widget> children, final double minTileWidth = 200})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int columns = (constraints.maxWidth / minTileWidth).floor().clamp(1, 4);
          final double width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[for (final Widget child in children) SizedBox(width: width, child: child)],
          );
        },
      );
}

/// A message about what just happened: an error, or a success.
class const Notice(final String message, {super.key, final bool error = true}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const .all(12),
        decoration: BoxDecoration(
          color: error ? scheme.errorContainer : scheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          message,
          style: TextStyle(color: error ? scheme.onErrorContainer : scheme.onPrimaryContainer),
        ),
      ),
    );
  }
}

/// A label and its value on one line, the value right-aligned.
class const FactRow(final String label, final String value, {super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const .symmetric(vertical: 4),
        child: Row(children: <Widget>[
          Expanded(child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Text(value, style: const TextStyle(fontWeight: .w600)),
        ]),
      );
}

/// A button that shows it is working while [onPressed] runs.
class const BusyButton({
  super.key,
  required final String label,
  required final Future<void> Function()? onPressed,
  final bool tonal = false,
}) extends StatefulWidget {
  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget label = _busy
        ? Semantics(
            label: '${widget.label}, working',
            child: const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        : Text(widget.label);
    final VoidCallback? pressed = widget.onPressed == null || _busy ? null : _run;
    return Tooltip(
      message: widget.label,
      child: widget.tonal
          ? FilledButton.tonal(onPressed: pressed, child: label)
          : FilledButton(onPressed: pressed, child: label),
    );
  }
}
