// Keeps keyboard focus where Tab put it, on the web.
//
// TODO(dartvel): remove when Dartvel's page shell stops taking focus from
// controls on the web. In 0.12.2, focusing a control in a browser briefly
// hands focus to a scope (the root, or the view's) while the engine moves the
// DOM focus, and the shell's keyboard-scroll node (DVKeyboardScroll) reads that as focus lost
// and takes it. The control loses focus at once and the next Tab starts again
// from the top of the page, so a keyboard user can never get past the first
// text field or past the bar at the top.
//
// This puts focus back on the control when that is what happened: a control
// had focus, focus passed to a scope, and the next thing to take it is
// a node that is not part of traversal. A click on an empty part of the page
// goes from the control to the shell's selection area instead, never through
// a scope, and is left alone.
import 'dart:async';

import 'package:flutter/widgets.dart';

abstract final class FocusKeeper {
  static bool _installed = false;
  static FocusNode? _last;
  static bool _passedRoot = false;
  static DateTime _restoredAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Starts keeping focus. Safe to call on every build.
  static void install() {
    if (_installed) return;
    _installed = true;
    FocusManager.instance.addListener(_changed);
  }

  static void _changed() {
    final FocusNode? focused = FocusManager.instance.primaryFocus;
    // A scope with primary focus (the root, or a view's) means no control has it.
    if (focused == null || focused is FocusScopeNode) {
      _passedRoot = _last != null;
      return;
    }
    if (focused.skipTraversal) {
      final FocusNode? last = _last;
      final DateTime now = DateTime.now();
      // Once per half second at most, so a control the engine keeps
      // releasing can never be fought over in a loop.
      if (_passedRoot &&
          last != null &&
          last.context != null &&
          last.canRequestFocus &&
          now.difference(_restoredAt) > const Duration(milliseconds: 500)) {
        _restoredAt = now;
        scheduleMicrotask(last.requestFocus);
      }
      _passedRoot = false;
      return;
    }
    _passedRoot = false;
    _last = focused;
  }
}
