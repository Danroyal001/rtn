// The self-service screens' parts: sign-in, balances, bundles, transfer,
// borrow, history and messages. Each page composes these.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/rtn.dart';
import '../services/session.dart';
import 'loaded.dart';
import 'ui.dart';

/// Calls the backend as the signed-in subscriber; a token the core no longer
/// knows signs them out here too.
Future<RtnResult> asMe(Future<Map<String, Object?>> Function(String token) call) async {
  final SubscriberSession me = DV.global<SubscriberSession>();
  final RtnResult result = await rtnCall(() => call(me.token));
  if (result.code == 'unauthorized') DV.global<SubscriberSession>(const SubscriberSession());
  return result;
}

/// Shows [builder] to a signed-in subscriber, and the sign-in form to anyone else.
class const SignedIn({super.key, required final Widget Function(BuildContext context, SubscriberSession me) builder})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final SubscriberSession me = context.global<SubscriberSession>();
    return me.signedIn ? builder(context, me) : const SubscriberSignIn();
  }
}

class const SubscriberSignIn({super.key}) extends StatefulWidget {
  @override
  State<SubscriberSignIn> createState() => _SubscriberSignInState();
}

class _SubscriberSignInState extends State<SubscriberSignIn> {
  final TextEditingController _number = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final RtnResult result = await rtnCall(() => subscriberSignIn(msisdn: _number.text, pin: _pin.text));
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _error = result.message);
      return;
    }
    final Map<String, Object?> data = result.map;
    DV.global<SubscriberSession>(SubscriberSession(
      token: '${data['token']}',
      msisdn: '${data['msisdn']}',
      name: '${data['name']}',
    ));
  }

  @override
  Widget build(BuildContext context) => Panel(
        child: AutofillGroup(
          child: DVBox.list(<Widget>[
            const SectionTitle('Sign in to your line'),
            const Text('Use your RTN number and the PIN you use for transfers.'),
            TextField(
              controller: _number,
              decoration: const InputDecoration(labelText: 'Phone number', hintText: '0999 000 0001'),
              keyboardType: TextInputType.phone,
              autofillHints: const <String>[AutofillHints.telephoneNumber],
              textInputAction: TextInputAction.next,
            ),
            TextField(
              controller: _pin,
              decoration: const InputDecoration(labelText: 'PIN'),
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              onSubmitted: (_) => _signIn(),
            ),
            if (_error != null) Notice(_error!),
            Align(alignment: .centerLeft, child: BusyButton(label: 'Sign in', onPressed: _signIn)),
            Text(
              'Trying the demo? Lines 0999 000 0001 to 0999 000 0005 use PIN 1234.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ], spacing: 14),
        ),
      );
}

/// Balances, bundles and the plan for the signed-in line.
class const LineOverview({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SignedIn(
        builder: (BuildContext context, SubscriberSession me) => Loaded(
          load: () => asMe((String token) => mySummary(token: token)),
          refreshEvery: const Duration(seconds: 10),
          loadingLabel: 'Loading your balances',
          builder: (BuildContext context, RtnResult result, Future<void> Function() reload) {
            final Map<String, Object?> balance = asMap(result.map['balance']);
            final Map<String, Object?> plan = asMap(result.map['plan']);
            final List<Map<String, Object?>> bundles = asList(balance['bundles']);
            final int loan = asInt(balance['loan']);
            return DVBox.list(<Widget>[
              TileGrid(children: <Widget>[
                StatTile(
                  label: 'Airtime',
                  value: naira(balance['airtime']),
                  note: asInt(balance['reserved']) > 0 ? '${naira(balance['reserved'])} held for a call' : null,
                ),
                StatTile(label: 'Data', value: dataSize(balance['data_bytes'])),
                StatTile(
                  label: loan > 0 ? 'Loan to repay' : 'You can borrow',
                  value: naira(loan > 0 ? loan : balance['loan_limit']),
                  accent: loan > 0,
                ),
              ]),
              Panel(
                child: DVBox.list(<Widget>[
                  const SectionTitle('Your line'),
                  FactRow('Number', phone(me.msisdn)),
                  FactRow('Plan', '${plan['name'] ?? balance['plan_id']}'),
                  FactRow('Calls', '${naira(plan['voice_per_second'])} a second'),
                  FactRow('SMS', '${naira(plan['sms_per_segment'])} a message'),
                  FactRow('Data outside a bundle', '${naira(plan['data_per_mb'])} per MB'),
                ], spacing: 4),
              ),
              Panel(
                child: DVBox.list(<Widget>[
                  const SectionTitle('Active bundles'),
                  if (bundles.isEmpty)
                    const Text('No active bundles. Data is charged per MB from your airtime.')
                  else
                    for (final Map<String, Object?> b in bundles)
                      FactRow('${b['name']}, until ${when(b['expires_at'])}', '${dataSize(b['bytes_left'])} left'),
                  const DVNavLink(to: DVRoutes.bundles, child: Text('Buy a bundle')),
                ], spacing: 8),
              ),
              Align(
                alignment: .centerLeft,
                child: BusyButton(
                  label: 'Sign out',
                  tonal: true,
                  onPressed: () async {
                    await rtnCall(() => subscriberSignOut(token: me.token));
                    DV.global<SubscriberSession>(const SubscriberSession());
                  },
                ),
              ),
            ], spacing: 16);
          },
        ),
      );
}

/// The bundle catalogue. Anyone can read it; buying needs a signed-in line.
class const BundleShelf({super.key}) extends StatefulWidget {
  @override
  State<BundleShelf> createState() => _BundleShelfState();
}

class _BundleShelfState extends State<BundleShelf> {
  String? _message;
  bool _error = false;

  Future<void> _buy(Map<String, Object?> bundle) async {
    final RtnResult result = await asMe(
      (String token) => buyBundle(token: token, bundleId: '${bundle['id']}', requestId: newRequestId('bundle')),
    );
    if (!mounted) return;
    setState(() {
      _error = !result.ok;
      _message = result.ok
          ? 'You bought ${bundle['name']}. Airtime left: ${naira(asMap(result.map['balance'])['airtime'])}.'
          : result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final SubscriberSession me = context.global<SubscriberSession>();
    return Loaded(
      load: () => rtnCall(bundleCatalog),
      loadingLabel: 'Loading bundles',
      builder: (BuildContext context, RtnResult result, Future<void> Function() reload) => DVBox.list(<Widget>[
        if (_message != null) Notice(_message!, error: _error),
        TileGrid(minTileWidth: 220, children: <Widget>[
          for (final Map<String, Object?> b in result.list)
            Panel(
              child: DVBox.list(<Widget>[
                Text('${b['name']}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: .w700)),
                Text(dataSize(b['data_bytes']), style: Theme.of(context).textTheme.headlineSmall),
                Text('${naira(b['price'])}, valid ${b['validity_days']} day${b['validity_days'] == 1 ? '' : 's'}'),
                if (me.signedIn)
                  BusyButton(label: 'Buy ${b['name']}', onPressed: () => _buy(b))
                else
                  const DVNavLink(to: DVRoutes.index, child: Text('Sign in to buy')),
              ], crossAlign: .start, spacing: 8),
            ),
        ]),
      ], spacing: 16),
    );
  }
}

class const TransferForm({super.key}) extends StatefulWidget {
  @override
  State<TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<TransferForm> {
  final TextEditingController _to = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  String _requestId = newRequestId('transfer');
  String? _message;
  bool _error = false;

  @override
  void dispose() {
    _to.dispose();
    _amount.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final RtnResult result = await asMe((String token) => sendAirtime(
          token: token,
          to: _to.text,
          naira: _amount.text,
          pin: _pin.text,
          requestId: _requestId,
        ));
    if (!mounted) return;
    setState(() {
      _error = !result.ok;
      if (result.ok) {
        final Map<String, Object?> detail = asMap(result.map['detail']);
        _message = 'Sent ${naira(detail['amount'])} to ${phone(detail['to'])}. '
            'Fee ${naira(detail['fee'])}. Airtime left: ${naira(asMap(result.map['balance'])['airtime'])}.';
        _requestId = newRequestId('transfer');
        _amount.clear();
      } else {
        _message = result.message;
      }
      _pin.clear();
    });
  }

  @override
  Widget build(BuildContext context) => SignedIn(
        builder: (BuildContext context, SubscriberSession me) => Panel(
          child: DVBox.list(<Widget>[
            TextField(
              controller: _to,
              decoration: const InputDecoration(labelText: "Recipient's number", hintText: '0999 000 0002'),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _requestId = newRequestId('transfer'),
            ),
            TextField(
              controller: _amount,
              decoration: const InputDecoration(labelText: 'Amount in naira', prefixText: '₦ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              onChanged: (_) => _requestId = newRequestId('transfer'),
            ),
            TextField(
              controller: _pin,
              decoration: const InputDecoration(labelText: 'Your PIN'),
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              onSubmitted: (_) => _send(),
            ),
            const Text('A transfer costs a flat ₦10.00. You can send ₦50 to ₦50,000 at a time.'),
            if (_message != null) Notice(_message!, error: _error),
            Align(alignment: .centerLeft, child: BusyButton(label: 'Send airtime', onPressed: _send)),
          ], spacing: 14),
        ),
      );
}

class const BorrowPanel({super.key}) extends StatefulWidget {
  @override
  State<BorrowPanel> createState() => _BorrowPanelState();
}

class _BorrowPanelState extends State<BorrowPanel> {
  String? _message;
  bool _error = false;

  Future<void> _borrow(int amount, Future<void> Function() reload) async {
    final RtnResult result = await asMe(
      (String token) => borrowAirtime(token: token, amount: amount, requestId: newRequestId('borrow')),
    );
    if (!mounted) return;
    setState(() {
      _error = !result.ok;
      _message = result.ok
          ? 'You borrowed ${naira(amount)}. ${naira(asMap(result.map['detail'])['owed'])} comes out of your next top-up.'
          : result.message;
    });
    await reload();
  }

  @override
  Widget build(BuildContext context) => SignedIn(
        builder: (BuildContext context, SubscriberSession me) => Loaded(
          load: () => asMe((String token) => mySummary(token: token)),
          builder: (BuildContext context, RtnResult result, Future<void> Function() reload) {
            final Map<String, Object?> balance = asMap(result.map['balance']);
            final int loan = asInt(balance['loan']);
            final int limit = asInt(balance['loan_limit']);
            final List<int> offers = <int>[10000, 20000, 50000].where((int a) => a <= limit).toList();
            return Panel(
              child: DVBox.list(<Widget>[
                if (_message != null) Notice(_message!, error: _error),
                if (loan > 0)
                  Text('You owe ${naira(loan)}. It is repaid from your next top-up, and you can borrow again after that.')
                else ...<Widget>[
                  Text('You can borrow up to ${naira(limit)}. A 10% service fee is added, and it all comes out of your next top-up.'),
                  Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
                    for (final int amount in offers)
                      BusyButton(label: 'Borrow ${naira(amount)}', onPressed: () => _borrow(amount, reload)),
                  ]),
                ],
              ], spacing: 14),
            );
          },
        ),
      );
}

class const HistoryList({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SignedIn(
        builder: (BuildContext context, SubscriberSession me) => Loaded(
          load: () => asMe((String token) => myHistory(token: token)),
          loadingLabel: 'Loading your history',
          builder: (BuildContext context, RtnResult result, Future<void> Function() reload) {
            final List<Map<String, Object?>> entries = result.list;
            if (entries.isEmpty) return const Panel(child: Text('Nothing yet.'));
            return Panel(
              padding: const .symmetric(vertical: 8),
              child: Column(children: <Widget>[
                for (final Map<String, Object?> e in entries)
                  ListTile(
                    title: Text('${entryKind(e['kind'])}: ${e['note']}'),
                    subtitle: Text('${when(e['at'])} · airtime after ${naira(e['airtime_after'])}'),
                    trailing: Text(
                      _change(e),
                      style: TextStyle(
                        fontWeight: .w700,
                        color: asInt(e['airtime_delta']) < 0
                            ? Theme.of(context).colorScheme.secondary
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ]),
            );
          },
        ),
      );

  static String _change(Map<String, Object?> e) {
    final int airtime = asInt(e['airtime_delta']);
    final int data = asInt(e['data_delta']);
    if (airtime != 0) return '${airtime < 0 ? '−' : '+'}${naira(airtime.abs())}';
    if (data != 0) return '${data < 0 ? '−' : '+'}${dataSize(data.abs())}';
    return '';
  }
}

class const MessagesPanel({super.key}) extends StatefulWidget {
  @override
  State<MessagesPanel> createState() => _MessagesPanelState();
}

class _MessagesPanelState extends State<MessagesPanel> {
  final TextEditingController _to = TextEditingController();
  final TextEditingController _text = TextEditingController();
  String? _message;
  bool _error = false;

  @override
  void dispose() {
    _to.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(Future<void> Function() reload) async {
    final RtnResult result = await asMe((String token) =>
        sendMessage(token: token, to: _to.text, text: _text.text, requestId: newRequestId('sms')));
    if (!mounted) return;
    setState(() {
      _error = !result.ok;
      if (result.ok) {
        final Map<String, Object?> detail = asMap(result.map['detail']);
        _message = 'Sent in ${detail['segments']} part(s) for ${naira(result.map['charged'])}.';
        _text.clear();
      } else {
        _message = result.message;
      }
    });
    await reload();
  }

  @override
  Widget build(BuildContext context) => SignedIn(
        builder: (BuildContext context, SubscriberSession me) => Loaded(
          load: () => asMe((String token) => myMessages(token: token)),
          refreshEvery: const Duration(seconds: 5),
          loadingLabel: 'Loading your messages',
          builder: (BuildContext context, RtnResult result, Future<void> Function() reload) {
            Widget list(String title, List<Map<String, Object?>> messages, bool incoming) => Panel(
                  padding: const .symmetric(vertical: 12),
                  child: DVBox.list(<Widget>[
                    Padding(padding: const .symmetric(horizontal: 16), child: SectionTitle(title)),
                    if (messages.isEmpty)
                      const Padding(padding: .symmetric(horizontal: 16), child: Text('None yet.')),
                    for (final Map<String, Object?> m in messages)
                      ListTile(
                        title: Text('${m['text']}'),
                        subtitle: Text(
                          '${incoming ? 'From ${phone(m['from'])}' : 'To ${phone(m['to'])}'} · ${when(m['submitted_at'])}'
                          '${incoming ? '' : ' · ${_state(m['state'])}'}',
                        ),
                      ),
                  ], spacing: 4),
                );
            return DVBox.list(<Widget>[
              Panel(
                child: DVBox.list(<Widget>[
                  const SectionTitle('New message'),
                  TextField(
                    controller: _to,
                    decoration: const InputDecoration(labelText: 'To', hintText: '0999 000 0002'),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                  ),
                  TextField(
                    controller: _text,
                    decoration: const InputDecoration(labelText: 'Message'),
                    maxLines: 3,
                    maxLength: 459,
                  ),
                  if (_message != null) Notice(_message!, error: _error),
                  Align(alignment: .centerLeft, child: BusyButton(label: 'Send SMS', onPressed: () => _send(reload))),
                ], spacing: 12),
              ),
              list('Inbox', asList(result.map['inbox']), true),
              list('Sent', asList(result.map['outbox']), false),
            ], spacing: 16);
          },
        ),
      );

  static String _state(Object? state) => switch ('$state') {
        'delivered' => 'delivered',
        'expired' => 'not delivered',
        _ => 'waiting for the phone',
      };
}
