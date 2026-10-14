// The operator's console: sign-in, live traffic, subscribers, rating plans.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/rtn.dart';
import '../services/session.dart';
import 'loaded.dart';
import 'traffic_chart.dart';
import 'ui.dart';

/// Calls the backend as the signed-in operator; an expired session signs out.
Future<RtnResult> asConsole(Future<Map<String, Object?>> Function(String session) call) async {
  final ConsoleSession console = DV.global<ConsoleSession>();
  final RtnResult result = await rtnCall(() => call(console.session));
  if (result.code == 'console_signed_out') DV.global<ConsoleSession>(const ConsoleSession());
  return result;
}

/// The console's own links, under the page heading.
class const ConsoleTabs({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final String path = GoRouterState.of(context).uri.path;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    Widget tab(DVRouteTarget to, String label, bool here) => DVNavLink(
          to: to,
          child: Container(
            padding: const .symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(width: 3, color: here ? scheme.secondary : Colors.transparent)),
            ),
            child: Text(label, style: TextStyle(fontWeight: here ? .w700 : .w500)),
          ),
        );
    return Wrap(spacing: 4, children: <Widget>[
      tab(DVRoutes.console, 'Live traffic', path == DVRoutes.console.path),
      tab(DVRoutes.consolesubscribers, 'Subscribers', path.startsWith(DVRoutes.consolesubscribers.path)),
      tab(DVRoutes.consolecatalog, 'Plans and bundles', path.startsWith(DVRoutes.consolecatalog.path)),
    ]);
  }
}

/// Shows [builder] to a signed-in operator and the console sign-in to anyone else.
class const ConsoleSignedIn({super.key, required final Widget Function(BuildContext context) builder})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      context.global<ConsoleSession>().signedIn ? builder(context) : const _ConsoleSignIn();
}

class const _ConsoleSignIn() extends StatefulWidget {
  @override
  State<_ConsoleSignIn> createState() => _ConsoleSignInState();
}

class _ConsoleSignInState extends State<_ConsoleSignIn> {
  final TextEditingController _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final RtnResult result = await rtnCall(() => consoleSignIn(password: _password.text));
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _error = result.message);
      return;
    }
    DV.global<ConsoleSession>(ConsoleSession(session: '${result.map['session']}'));
  }

  @override
  Widget build(BuildContext context) => Panel(
        child: DVBox.list(<Widget>[
          const SectionTitle('Operator sign-in'),
          const Text('The console is for the people who run the network.'),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: 'Console password'),
            obscureText: true,
            onSubmitted: (_) => _signIn(),
          ),
          if (_error != null) Notice(_error!),
          Align(alignment: .centerLeft, child: BusyButton(label: 'Sign in', onPressed: _signIn)),
          Text('demo.sh prints the password when it starts.', style: Theme.of(context).textTheme.bodySmall),
        ], spacing: 14),
      );
}

class const TrafficBoard({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Loaded(
        load: () => asConsole((String session) => consoleTraffic(session: session)),
        refreshEvery: const Duration(seconds: 2),
        loadingLabel: 'Loading live traffic',
        builder: (BuildContext context, RtnResult result, Future<void> Function() reload) {
          final Map<String, Object?> t = result.map;
          final Map<String, Object?> totals = asMap(t['totals']);
          final Map<String, Object?> money = asMap(t['totals_money']);
          final List<Map<String, Object?>> series = asList(t['series']);
          int lastMinute(String key) => series.fold(0, (int sum, Map<String, Object?> s) => sum + asInt(s[key]));
          final bool running = t['simulator_running'] == true;
          return DVBox.list(<Widget>[
            Panel(
              child: Row(spacing: 16, children: <Widget>[
                Expanded(
                  child: Text(running
                      ? 'The traffic simulator is on: every active line is browsing, calling and texting.'
                      : 'The traffic simulator is off. Only real requests move these numbers.'),
                ),
                BusyButton(
                  label: running ? 'Stop simulator' : 'Start simulator',
                  tonal: running,
                  onPressed: () async {
                    await asConsole((String session) => consoleSimulator(session: session, running: !running));
                    await reload();
                  },
                ),
              ]),
            ),
            const SectionTitle('Right now'),
            TileGrid(children: <Widget>[
              StatTile(label: 'Subscribers', value: '${t['subscribers']}', note: '${t['active_subscribers']} active'),
              StatTile(label: 'Phones attached', value: '${t['attached']}'),
              StatTile(label: 'Calls in progress', value: '${t['active_calls']}'),
              StatTile(label: 'SMS waiting', value: '${t['queued_sms']}', note: 'held for phones that are off'),
            ]),
            const SectionTitle('The last minute'),
            TileGrid(children: <Widget>[
              StatTile(label: 'Data', value: dataSize(lastMinute('data_bytes'))),
              StatTile(label: 'Voice', value: '${lastMinute('voice_seconds')} s'),
              StatTile(label: 'SMS', value: '${lastMinute('sms')}'),
              StatTile(label: 'Revenue', value: naira(lastMinute('revenue')), accent: true),
            ]),
            Panel(child: TrafficChart(series: series, seriesFrom: asInt(t['series_from']))),
            const SectionTitle('Since the core started'),
            TileGrid(children: <Widget>[
              StatTile(label: 'Charging requests', value: '${totals['charges']}', note: '${totals['failures']} refused'),
              StatTile(label: 'USSD requests', value: '${totals['ussd']}'),
              StatTile(label: 'Revenue', value: naira(money['revenue']), accent: true),
              StatTile(label: 'Topped up', value: naira(money['topped_up'])),
              StatTile(label: 'Lent', value: naira(money['lent']), note: '${naira(money['repaid'])} repaid'),
            ]),
          ], spacing: 16);
        },
      );
}

class const SubscriberDirectory({super.key}) extends StatefulWidget {
  @override
  State<SubscriberDirectory> createState() => _SubscriberDirectoryState();
}

class _SubscriberDirectoryState extends State<SubscriberDirectory> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  int _offset = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DVBox.list(<Widget>[
        TextField(
          controller: _search,
          decoration: InputDecoration(
            labelText: 'Search by number, IMSI or name',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.arrow_forward),
              onPressed: () => setState(() {
                _query = _search.text.trim();
                _offset = 0;
              }),
            ),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (String text) => setState(() {
            _query = text.trim();
            _offset = 0;
          }),
        ),
        Loaded(
          key: ValueKey<String>('$_query@$_offset'),
          load: () => asConsole((String session) =>
              consoleSubscribers(session: session, search: _query, offset: _offset)),
          loadingLabel: 'Loading subscribers',
          builder: (BuildContext context, RtnResult result, Future<void> Function() reload) {
            final List<Map<String, Object?>> items = asList(result.map['items']);
            final int total = asInt(result.map['total']);
            return DVBox.list(<Widget>[
              Text(total == 0
                  ? 'No subscribers match.'
                  : 'Showing ${_offset + 1} to ${_offset + items.length} of $total.'),
              Panel(
                padding: const .symmetric(vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: .horizontal,
                  child: DataTable(
                    columns: const <DataColumn>[
                      DataColumn(label: Text('Number')),
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Plan')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Airtime'), numeric: true),
                      DataColumn(label: Text('Data'), numeric: true),
                    ],
                    rows: <DataRow>[
                      for (final Map<String, Object?> item in items)
                        _row(asMap(item['subscriber']), asMap(item['balance'])),
                    ],
                  ),
                ),
              ),
              DVBox.row(<Widget>[
                if (_offset > 0)
                  BusyButton(
                    label: 'Previous page',
                    tonal: true,
                    onPressed: () async => setState(() => _offset = (_offset - 25).clamp(0, total)),
                  ),
                if (_offset + items.length < total)
                  BusyButton(
                    label: 'Next page',
                    tonal: true,
                    onPressed: () async => setState(() => _offset += 25),
                  ),
              ], spacing: 12, crossAlign: .center),
            ], spacing: 12);
          },
        ),
        const NewSubscriberForm(),
      ], spacing: 16);

  DataRow _row(Map<String, Object?> s, Map<String, Object?> b) => DataRow(cells: <DataCell>[
        DataCell(DVNavLink(
          to: DVRoutes.consolesubscribersMsisdn(msisdn: '${s['msisdn']}'),
          child: Text(phone(s['msisdn']), style: const TextStyle(fontWeight: .w600, decoration: .underline)),
        )),
        DataCell(Text('${s['name']}')),
        DataCell(Text('${s['plan_id']}')),
        DataCell(Text(s['status'] == 'barred' ? 'Barred' : (s['attached'] == true ? 'Active' : 'Active, phone off'))),
        DataCell(Text(naira(b['airtime']))),
        DataCell(Text(dataSize(b['data_bytes']))),
      ]);
}

class const NewSubscriberForm({super.key}) extends StatefulWidget {
  @override
  State<NewSubscriberForm> createState() => _NewSubscriberFormState();
}

class _NewSubscriberFormState extends State<NewSubscriberForm> {
  final TextEditingController _number = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  String _plan = '';
  String? _message;
  bool _error = false;

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final RtnResult result = await asConsole((String session) => consoleAddSubscriber(
          session: session,
          msisdn: _number.text,
          name: _name.text,
          pin: _pin.text,
          planId: _plan,
        ));
    if (!mounted) return;
    setState(() {
      _error = !result.ok;
      _message = result.ok
          ? 'Added ${result.map['name']} on ${phone(result.map['msisdn'])}, SIM ${result.map['imsi']}.'
          : result.message;
      if (result.ok) {
        _number.clear();
        _name.clear();
        _pin.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Panel(
        child: DVBox.list(<Widget>[
          const SectionTitle('Add a subscriber'),
          TextField(controller: _number, decoration: const InputDecoration(labelText: 'Number'), keyboardType: TextInputType.phone),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
          TextField(
            controller: _pin,
            decoration: const InputDecoration(labelText: 'Starting PIN (4 to 6 digits)'),
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _add(),
          ),
          DropdownButtonFormField<String>(
            initialValue: _plan,
            decoration: const InputDecoration(labelText: 'Plan'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(value: '', child: Text('Default plan')),
              DropdownMenuItem<String>(value: 'pulse', child: Text('Pulse')),
              DropdownMenuItem<String>(value: 'steady', child: Text('Steady')),
            ],
            onChanged: (String? value) => setState(() => _plan = value ?? ''),
          ),
          if (_message != null) Notice(_message!, error: _error),
          Align(alignment: .centerLeft, child: BusyButton(label: 'Add subscriber', onPressed: _add)),
        ], spacing: 12),
      );
}

class const SubscriberDetail({super.key, required final String msisdn}) extends StatefulWidget {
  @override
  State<SubscriberDetail> createState() => _SubscriberDetailState();
}

class _SubscriberDetailState extends State<SubscriberDetail> {
  final TextEditingController _topUp = TextEditingController();
  String? _message;
  bool _error = false;

  @override
  void dispose() {
    _topUp.dispose();
    super.dispose();
  }

  Future<void> _act(Future<RtnResult> Function() action, String done, Future<void> Function() reload) async {
    final RtnResult result = await action();
    if (!mounted) return;
    setState(() {
      _error = !result.ok;
      _message = result.ok ? done : result.message;
    });
    await reload();
  }

  @override
  Widget build(BuildContext context) => Loaded(
        load: () => asConsole((String session) => consoleSubscriber(session: session, msisdn: widget.msisdn)),
        refreshEvery: const Duration(seconds: 5),
        loadingLabel: 'Loading the subscriber',
        builder: (BuildContext context, RtnResult result, Future<void> Function() reload) {
          final Map<String, Object?> s = asMap(result.map['subscriber']);
          final Map<String, Object?> b = asMap(result.map['balance']);
          final List<Map<String, Object?>> history = asList(result.map['history']);
          final bool barred = s['status'] == 'barred';
          return DVBox.list(<Widget>[
            PageHeading('${s['name']}', subtitle: '${phone(s['msisdn'])} · SIM ${s['imsi']}'),
            if (_message != null) Notice(_message!, error: _error),
            TileGrid(children: <Widget>[
              StatTile(label: 'Airtime', value: naira(b['airtime'])),
              StatTile(label: 'Data', value: dataSize(b['data_bytes'])),
              StatTile(label: 'Loan', value: naira(b['loan']), accent: asInt(b['loan']) > 0),
              StatTile(label: 'Status', value: barred ? 'Barred' : 'Active', note: s['attached'] == true ? 'Phone attached' : 'Phone off'),
            ]),
            Panel(
              child: DVBox.list(<Widget>[
                const SectionTitle('Manage this line'),
                Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: .center, children: <Widget>[
                  BusyButton(
                    label: barred ? 'Lift the bar' : 'Bar this line',
                    tonal: !barred,
                    onPressed: () => _act(
                      () => asConsole((String session) => consoleUpdateSubscriber(
                          session: session, msisdn: widget.msisdn, status: barred ? 'active' : 'barred', planId: '')),
                      barred ? 'The line is active again.' : 'The line is barred.',
                      reload,
                    ),
                  ),
                  for (final String plan in <String>['pulse', 'steady'])
                    if (plan != s['plan_id'])
                      BusyButton(
                        label: 'Move to $plan',
                        tonal: true,
                        onPressed: () => _act(
                          () => asConsole((String session) => consoleUpdateSubscriber(
                              session: session, msisdn: widget.msisdn, status: '', planId: plan)),
                          'Moved to $plan.',
                          reload,
                        ),
                      ),
                ]),
                Row(spacing: 12, children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _topUp,
                      decoration: const InputDecoration(labelText: 'Top up, in naira', prefixText: '₦ '),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  BusyButton(
                    label: 'Top up',
                    onPressed: () => _act(
                      () => asConsole((String session) => consoleTopUp(
                          session: session, msisdn: widget.msisdn, naira: _topUp.text, requestId: newRequestId('console'))),
                      'Topped up.',
                      reload,
                    ),
                  ),
                ]),
              ], spacing: 14),
            ),
            Panel(
              padding: const .symmetric(vertical: 12),
              child: DVBox.list(<Widget>[
                const Padding(padding: .symmetric(horizontal: 16), child: SectionTitle('Recent ledger')),
                if (history.isEmpty) const Padding(padding: .symmetric(horizontal: 16), child: Text('Nothing yet.')),
                for (final Map<String, Object?> e in history.take(25))
                  ListTile(
                    dense: true,
                    title: Text('${entryKind(e['kind'])}: ${e['note']}'),
                    subtitle: Text('${when(e['at'])} · ${e['request_id']}'),
                    trailing: Text(naira(e['airtime_after'])),
                  ),
              ]),
            ),
          ], spacing: 16);
        },
      );
}

class const CatalogEditor({super.key}) extends StatefulWidget {
  @override
  State<CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<CatalogEditor> {
  String? _message;
  bool _error = false;

  void _report(RtnResult result, String done) => setState(() {
        _error = !result.ok;
        _message = result.ok ? done : result.message;
      });

  @override
  Widget build(BuildContext context) => Loaded(
        load: () => asConsole((String session) => consoleCatalog(session: session)),
        loadingLabel: 'Loading plans and bundles',
        builder: (BuildContext context, RtnResult result, Future<void> Function() reload) {
          final List<Map<String, Object?>> plans = asList(asMap(result.map['plans']).values.toList());
          final List<Map<String, Object?>> bundles = asList(result.map['bundles']);
          return DVBox.list(<Widget>[
            if (_message != null) Notice(_message!, error: _error),
            const SectionTitle('Rating plans'),
            const Text('Rates apply from the next charge. A call in progress keeps the rate it started with.'),
            for (final Map<String, Object?> p in plans)
              _PlanForm(plan: p, onSaved: (RtnResult r) async {
                _report(r, 'Saved ${p['name']}.');
                await reload();
              }),
            _PlanForm(plan: const <String, Object?>{}, onSaved: (RtnResult r) async {
              _report(r, 'Plan added.');
              await reload();
            }),
            const SectionTitle('Data bundles'),
            for (final Map<String, Object?> b in bundles)
              _BundleForm(bundle: b, onSaved: (RtnResult r) async {
                _report(r, 'Saved ${b['name']}.');
                await reload();
              }),
            _BundleForm(bundle: const <String, Object?>{}, onSaved: (RtnResult r) async {
              _report(r, 'Bundle added.');
              await reload();
            }),
          ], spacing: 14);
        },
      );
}

String _nairaField(Object? units) => units == null ? '' : (asInt(units) / 100).toStringAsFixed(2);

class const _PlanForm({required final Map<String, Object?> plan, required final Future<void> Function(RtnResult) onSaved})
    extends StatefulWidget {
  @override
  State<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends State<_PlanForm> {
  late final TextEditingController _id = TextEditingController(text: '${widget.plan['id'] ?? ''}');
  late final TextEditingController _name = TextEditingController(text: '${widget.plan['name'] ?? ''}');
  late final TextEditingController _voice =
      TextEditingController(text: '${widget.plan['voice_per_second'] ?? ''}');
  late final TextEditingController _sms = TextEditingController(text: _nairaField(widget.plan['sms_per_segment']));
  late final TextEditingController _data = TextEditingController(text: _nairaField(widget.plan['data_per_mb']));

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_id, _name, _voice, _sms, _data]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isNew = widget.plan.isEmpty;
    Widget field(TextEditingController c, String label, {bool enabled = true}) => SizedBox(
          width: 180,
          child: TextField(controller: c, enabled: enabled, decoration: InputDecoration(labelText: label)),
        );
    return Panel(
      child: DVBox.list(<Widget>[
        Text(isNew ? 'New plan' : '${widget.plan['name']}', style: Theme.of(context).textTheme.titleMedium),
        Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
          field(_id, 'Id', enabled: isNew),
          field(_name, 'Name'),
          field(_voice, 'Voice, kobo a second'),
          field(_sms, 'SMS, naira a part'),
          field(_data, 'Data, naira per MB'),
        ]),
        Align(
          alignment: .centerLeft,
          child: BusyButton(
            label: isNew ? 'Add plan' : 'Save ${widget.plan['name']}',
            onPressed: () async => widget.onSaved(await asConsole((String session) => consoleSavePlan(
                  session: session,
                  id: _id.text,
                  name: _name.text,
                  voiceKoboPerSecond: _voice.text,
                  smsNaira: _sms.text,
                  dataNairaPerMb: _data.text,
                ))),
          ),
        ),
      ], spacing: 12),
    );
  }
}

class const _BundleForm({required final Map<String, Object?> bundle, required final Future<void> Function(RtnResult) onSaved})
    extends StatefulWidget {
  @override
  State<_BundleForm> createState() => _BundleFormState();
}

class _BundleFormState extends State<_BundleForm> {
  late final TextEditingController _id = TextEditingController(text: '${widget.bundle['id'] ?? ''}');
  late final TextEditingController _name = TextEditingController(text: '${widget.bundle['name'] ?? ''}');
  late final TextEditingController _mb = TextEditingController(
      text: widget.bundle['data_bytes'] == null ? '' : '${asInt(widget.bundle['data_bytes']) ~/ 1048576}');
  late final TextEditingController _price = TextEditingController(text: _nairaField(widget.bundle['price']));
  late final TextEditingController _days = TextEditingController(text: '${widget.bundle['validity_days'] ?? ''}');

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_id, _name, _mb, _price, _days]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isNew = widget.bundle.isEmpty;
    Widget field(TextEditingController c, String label, {bool enabled = true}) => SizedBox(
          width: 180,
          child: TextField(controller: c, enabled: enabled, decoration: InputDecoration(labelText: label)),
        );
    return Panel(
      child: DVBox.list(<Widget>[
        Text(isNew ? 'New bundle' : '${widget.bundle['name']}', style: Theme.of(context).textTheme.titleMedium),
        Wrap(spacing: 12, runSpacing: 12, children: <Widget>[
          field(_id, 'Id', enabled: isNew),
          field(_name, 'Name'),
          field(_mb, 'Data, MB'),
          field(_price, 'Price, naira'),
          field(_days, 'Valid for, days'),
        ]),
        Align(
          alignment: .centerLeft,
          child: BusyButton(
            label: isNew ? 'Add bundle' : 'Save ${widget.bundle['name']}',
            onPressed: () async => widget.onSaved(await asConsole((String session) => consoleSaveBundle(
                  session: session,
                  id: _id.text,
                  name: _name.text,
                  dataMb: int.tryParse(_mb.text.trim()) ?? 0,
                  priceNaira: _price.text,
                  validityDays: int.tryParse(_days.text.trim()) ?? 0,
                ))),
          ),
        ),
      ], spacing: 12),
    );
  }
}
