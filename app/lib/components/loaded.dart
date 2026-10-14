import 'dart:async';

import 'package:flutter/material.dart';

import '../services/rtn.dart';
import 'ui.dart';

/// Loads something from the backend and builds with it, with a loading state,
/// a readable refusal with a way to try again, and an optional refresh.
class const Loaded({
  super.key,
  required final Future<RtnResult> Function() load,
  required final Widget Function(BuildContext context, RtnResult result, Future<void> Function() reload) builder,
  final Duration? refreshEvery,
  final String loadingLabel = 'Loading',
}) extends StatefulWidget {
  @override
  State<Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<Loaded> {
  RtnResult? _result;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.refreshEvery != null) {
      _timer = Timer.periodic(widget.refreshEvery!, (_) => _reload());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_loading) return;
    _loading = true;
    final RtnResult result = await widget.load();
    _loading = false;
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final RtnResult? result = _result;
    if (result == null) {
      return Padding(
        padding: const .all(24),
        child: Center(
          child: Semantics(
            label: widget.loadingLabel,
            child: const CircularProgressIndicator(),
          ),
        ),
      );
    }
    if (!result.ok) {
      return Column(
        crossAxisAlignment: .start,
        spacing: 12,
        children: <Widget>[
          Notice(result.message),
          BusyButton(label: 'Try again', onPressed: _reload, tonal: true),
        ],
      );
    }
    return widget.builder(context, result, _reload);
  }
}
