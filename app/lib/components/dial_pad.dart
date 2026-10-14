// A handset's dial pad that talks to the RTN USSD gateway: dial a code, read
// the menu, answer it, until the network ends the session.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/rtn.dart';
import '../services/session.dart';
import 'self_service.dart';
import 'ui.dart';

const List<(String, String)> _keys = <(String, String)>[
  ('1', ''), ('2', 'ABC'), ('3', 'DEF'),
  ('4', 'GHI'), ('5', 'JKL'), ('6', 'MNO'),
  ('7', 'PQRS'), ('8', 'TUV'), ('9', 'WXYZ'),
  ('*', ''), ('0', '+'), ('#', ''),
];

const List<(String, String)> quickCodes = <(String, String)>[
  ('*123#', 'Menu'),
  ('*123*1#', 'Balance'),
  ('*312#', 'Data bundles'),
  ('*303#', 'Borrow'),
  ('*123*5#', 'My number'),
];

class const DialPad({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      SignedIn(builder: (BuildContext context, SubscriberSession me) => _Handset(me: me));
}

class const _Handset({required final SubscriberSession me}) extends StatefulWidget {
  @override
  State<_Handset> createState() => _HandsetState();
}

class _HandsetState extends State<_Handset> {
  final FocusNode _padFocus = FocusNode(debugLabel: 'dial pad');
  final TextEditingController _answer = TextEditingController();
  String _typed = '';
  String? _session;
  String? _reply;
  bool _ended = false;
  bool _busy = false;

  @override
  void dispose() {
    _padFocus.dispose();
    _answer.dispose();
    super.dispose();
  }

  void _press(String key) {
    if (_reply != null || _busy) return;
    setState(() => _typed = (_typed + key).length > 40 ? _typed : _typed + key);
  }

  void _delete() {
    if (_reply != null || _typed.isEmpty) return;
    setState(() => _typed = _typed.substring(0, _typed.length - 1));
  }

  Future<void> _send(String input) async {
    if (_busy || input.isEmpty) return;
    setState(() => _busy = true);
    final String session = _session ??= newRequestId('handset');
    final RtnResult result = await asMe((String token) =>
        dialUssd(token: token, msisdn: widget.me.msisdn, sessionId: session, input: input));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _answer.clear();
      if (result.ok) {
        _reply = '${result.map['text']}';
        _ended = result.map['end'] == true;
      } else {
        _reply = result.message;
        _ended = true;
      }
      if (_ended) _session = null;
    });
  }

  void _dismiss() {
    setState(() {
      _reply = null;
      _ended = false;
      _session = null;
      _typed = '';
    });
    _padFocus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _reply != null) return KeyEventResult.ignored;
    final String? character = event.character;
    if (character != null && RegExp(r'^[0-9*#]$').hasMatch(character)) {
      _press(character);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _delete();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _send(_typed);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Widget screen = Container(
      height: 230,
      padding: const .all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: _reply == null
          ? Center(
              child: Semantics(
                label: _typed.isEmpty ? 'Nothing dialled yet' : 'Dialled $_typed',
                liveRegion: true,
                child: Text(
                  _typed.isEmpty ? 'Dial a code' : _typed,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                    color: _typed.isEmpty ? scheme.onSurfaceVariant : scheme.onSurface,
                  ),
                ),
              ),
            )
          : DVBox.list(<Widget>[
              Expanded(
                child: SingleChildScrollView(
                  child: Semantics(liveRegion: true, child: Text(_reply!, style: theme.textTheme.bodyLarge)),
                ),
              ),
              if (!_ended)
                TextField(
                  controller: _answer,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Reply', isDense: true),
                  keyboardType: TextInputType.text,
                  onSubmitted: _send,
                ),
              DVBox.row(<Widget>[
                if (!_ended)
                  BusyButton(label: 'Send', onPressed: () => _send(_answer.text))
                else
                  BusyButton(label: 'OK', onPressed: () async => _dismiss()),
                if (!_ended) BusyButton(label: 'Cancel', tonal: true, onPressed: () async => _dismiss()),
              ], spacing: 8, crossAlign: .center),
            ], spacing: 10),
    );

    final Widget keypad = GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: <Widget>[
        for (final (String digit, String letters) in _keys)
          Tooltip(
            message: digit,
            child: OutlinedButton(
              onPressed: _reply == null ? () => _press(digit) : null,
              style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: .zero),
              child: Column(mainAxisSize: .min, children: <Widget>[
                Text(digit, style: theme.textTheme.titleLarge),
                if (letters.isNotEmpty)
                  ExcludeSemantics(child: Text(letters, style: theme.textTheme.labelSmall)),
              ]),
            ),
          ),
      ],
    );

    final Widget controls = DVBox.row(<Widget>[
      IconButton.filledTonal(
        tooltip: 'Delete the last digit',
        onPressed: _reply == null && _typed.isNotEmpty ? _delete : null,
        icon: const Icon(Icons.backspace_outlined),
      ),
      IconButton.filled(
        tooltip: 'Dial',
        iconSize: 32,
        onPressed: _reply == null && _typed.isNotEmpty && !_busy ? () => _send(_typed) : null,
        style: IconButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary),
        icon: const Icon(Icons.call),
      ),
      IconButton.filledTonal(
        tooltip: 'Clear',
        onPressed: _reply == null && _typed.isNotEmpty ? () => setState(() => _typed = '') : null,
        icon: const Icon(Icons.clear),
      ),
    ], align: .spaceEvenly, crossAlign: .center);

    return Wrap(
      spacing: 24,
      runSpacing: 24,
      children: <Widget>[
        Focus(
          focusNode: _padFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Panel(
              child: DVBox.list(<Widget>[
                Text('Calling as ${phone(widget.me.msisdn)}', style: theme.textTheme.labelLarge),
                screen,
                keypad,
                controls,
              ], spacing: 14),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Panel(
            child: DVBox.list(<Widget>[
              const SectionTitle('Codes'),
              for (final (String code, String what) in quickCodes)
                ListTile(
                  contentPadding: .zero,
                  title: Text(code, style: const TextStyle(fontWeight: .w700)),
                  subtitle: Text(what),
                  onTap: _reply == null ? () => setState(() => _typed = code) : null,
                ),
              const ListTile(
                contentPadding: .zero,
                title: Text('*321*number*amount*PIN#', style: TextStyle(fontWeight: .w700)),
                subtitle: Text('Send airtime in one step'),
              ),
              const Text('Type on your keyboard too: digits, * and #, Backspace, and Enter to dial.'),
            ], spacing: 4),
          ),
        ),
      ],
    );
  }
}
