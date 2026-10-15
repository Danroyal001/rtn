// The operator console: the network live, subscribers, the catalogue,
// vouchers, care and the SMS centre.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/account.dart';
import '../services/money.dart';
import '../services/remote.dart';
import '../services/wire.dart';
import '../styles/theme.dart';

@DVFunctionalWidget()
Widget _consoleSignInScreen(BuildContext context) {
  final DVSignal<String> password = context.signal('');
  final DVSignal<bool> busy = context.signal(false);
  final DVSignal<String> problem = context.signal('');

  Future<void> signIn() async {
    busy.value = true;
    final Reply<SignedIn> who = await signInToConsole(password.read());
    busy.value = false;
    if (who.ok) {
      DV.Navigation.navigate(DVRoutes.console);
    } else {
      problem.value = who.message;
    }
  }

  return Screen(<Widget>[
    const SizedBox(height: 12),
    const PageTitle('RTN console', subtitle: 'For the operator of this RTN network.'),
    Panel(<Widget>[
      Field(
        'Console password',
        secret: true,
        value: password.read(),
        onChanged: (String v) => password.value = v,
        onSubmitted: signIn,
      ),
      ActionButton('Sign in', tooltip: 'Sign in to the operator console', busy: busy.value, onPressed: signIn),
      if (problem.value.isNotEmpty) Notice(problem.value),
    ]),
    const Empty('The password is set on the server as RTN_CONSOLE_PASSWORD; demo.sh prints it.'),
  ], maxWidth: 420);
}

// ----- live --------------------------------------------------------------------------------

@DVFunctionalWidget()
Widget _liveScreen(BuildContext context) {
  final DVSignal<Reply<Traffic>?> traffic = context.signal<Reply<Traffic>?>(null);
  Future<Reply<Traffic>> fetch() => consoleTraffic(fromJson: Reply.of(Traffic.fromJson));
  loadInto(traffic, fetch, every: const Duration(seconds: 2));
  final Reply<Traffic>? reply = traffic.value;
  if (reply == null) {
    return const Screen(<Widget>[PageTitle('Live network'), Loading(label: 'Loading live traffic')], maxWidth: 1100);
  }
  if (!reply.ok) {
    return Screen(<Widget>[
      const PageTitle('Live network'),
      Refusal(reply.message, onRetry: () => reload(traffic, fetch)),
    ], maxWidth: 1100);
  }
  final Traffic t = reply.result;
  final TrafficCounters lastMinute = t.series.fold(
    const TrafficCounters(),
    (TrafficCounters a, TrafficCounters b) => TrafficCounters(
      dataBytes: a.dataBytes + b.dataBytes,
      voiceSeconds: a.voiceSeconds + b.voiceSeconds,
      sms: a.sms + b.sms,
      ussd: a.ussd + b.ussd,
      charges: a.charges + b.charges,
      revenue: a.revenue + b.revenue,
      failures: a.failures + b.failures,
    ),
  );
  final int balances = t.money.toppedUp + t.money.lent - t.money.revenue - t.money.repaid;

  Future<void> toggle() async {
    await ask(() => consoleSimulator(running: !t.simulating, fromJson: Reply.of(Done.fromJson)));
    await reload(traffic, fetch);
  }

  return Screen(<Widget>[
    const PageTitle('Live network', subtitle: 'Refreshed every two seconds.'),
    DVBox.wrapLine(<Widget>[
      Tag(
        t.simulating ? 'Simulator on' : 'Simulator off',
        warm: !t.simulating,
        tooltip: t.simulating
            ? 'Simulated subscribers are using the network'
            : 'Only real requests are reaching the network',
      ),
      ActionButton(
        t.simulating ? 'Stop the simulator' : 'Start the simulator',
        tooltip: t.simulating ? 'Stop the simulated traffic' : 'Start simulated calls, SMS and data across all lines',
        primary: !t.simulating,
        onPressed: toggle,
      ),
    ], spacing: 12),
    Panel(<Widget>[
      const SectionTitle('Right now'),
      DVBox.wrapLine(<Widget>[
        Stat(
          'Subscribers',
          '${t.subscribers}',
          tooltip: '${t.activeSubscribers} active, ${t.subscribers - t.activeSubscribers} barred',
        ),
        Stat('Phones on', '${t.attached}', tooltip: 'Handsets attached to the network'),
        Stat('Calls', '${t.activeCalls}', tooltip: 'Calls in progress'),
        Stat('SMS waiting', '${t.queuedSms}', tooltip: 'Messages held for phones that are off'),
        Stat('USSD sessions', '${t.ussdSessions}', tooltip: 'Open USSD menus'),
      ], spacing: 28),
    ]),
    Panel(<Widget>[
      const SectionTitle('The last minute'),
      DVBox.wrapLine(<Widget>[
        Stat('Charges', '${lastMinute.charges}', tooltip: 'Charging operations applied'),
        Stat(
          'Refused',
          '${lastMinute.failures}',
          tooltip: 'Operations the network refused, such as not enough airtime',
        ),
        Stat('Data', dataSize(lastMinute.dataBytes), tooltip: 'Data used'),
        Stat('Voice', '${lastMinute.voiceSeconds}s', tooltip: 'Seconds of calls billed'),
        Stat('SMS', '${lastMinute.sms}', tooltip: 'Messages sent'),
        Stat('Revenue', naira(lastMinute.revenue), tooltip: 'Earned from usage, bundles and fees'),
      ], spacing: 28),
      TrafficChart(series: t.series),
    ]),
    Panel(<Widget>[
      const SectionTitle(
        'Money since the network started',
        hint: 'Balances + revenue + repaid always equals topped up + lent.',
      ),
      DVBox.wrapLine(<Widget>[
        Stat('Topped up', naira(t.money.toppedUp), tooltip: 'Recharges of every kind'),
        Stat('Lent', naira(t.money.lent), tooltip: 'Airtime loans'),
        Stat('Repaid', naira(t.money.repaid), tooltip: 'Loans repaid, service fee included'),
        Stat(
          'Revenue',
          naira(t.money.revenue),
          ink: Theme.of(context).colorScheme.primary,
          tooltip: 'Usage, bundles and transfer fees',
        ),
        Stat('In balances', naira(balances), tooltip: 'Airtime subscribers hold'),
      ], spacing: 28),
    ]),
  ], maxWidth: 1100);
}

/// Charges per second over the last minute, as bars.
@DVFunctionalWidget()
Widget _trafficChart(BuildContext context, {required List<TrafficCounters> series}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final int peak = series.fold<int>(1, (int m, TrafficCounters c) => c.charges > m ? c.charges : m);
  return DVBox.list(
    <Widget>[
      DVText('Charges per second, last 60 seconds (peak $peak)')
          .modifier(const DVModifier().fontSize(12).color(colors.onSurfaceVariant)),
      SizedBox(
        height: 120,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (final (int i, TrafficCounters c) in series.indexed)
              Expanded(
                child: DVBox(
                  const SizedBox.shrink(),
                  const DVModifier()
                      .height(4 + 116 * c.charges / peak)
                      .marginOnly(right: 2)
                      .rounded(2)
                      .backgroundColor(c.failures > 0 && c.failures * 4 > c.charges ? RtnColors.rust : colors.primary)
                      .tooltip('${60 - i}s ago: ${c.charges} charges, ${c.failures} refused, ${naira(c.revenue)}'),
                ),
              ),
          ],
        ),
      ),
    ],
    spacing: 6,
    modifier: const DVModifier().semanticLabel('Bar chart of charges per second over the last minute'),
  );
}

// ----- subscribers -------------------------------------------------------------------------

@DVFunctionalWidget()
Widget _subscribersScreen(BuildContext context) {
  final DVSignal<Reply<SubscriberPage>?> page = context.signal<Reply<SubscriberPage>?>(null);
  final DVSignal<String> search = context.signal('');
  final DVSignal<int> offset = context.signal(0);
  Future<Reply<SubscriberPage>> fetch() =>
      consoleSubscribers(search: search.read(), offset: offset.read(), fromJson: Reply.of(SubscriberPage.fromJson));
  loadInto(page, fetch);
  final Reply<SubscriberPage>? reply = page.value;
  final ColorScheme colors = Theme.of(context).colorScheme;

  Future<void> go(int to) async {
    offset.value = to < 0 ? 0 : to;
    await reload(page, fetch);
  }

  return Screen(<Widget>[
    const PageTitle('Subscribers', subtitle: 'Search by number, name or IMSI.'),
    DVBox.row(
      <Widget>[
        Expanded(
          child: Field(
            'Search',
            hint: '0999 000 0001, Ada, 99970…',
            value: search.read(),
            onChanged: (String v) => search.value = v,
            onSubmitted: () => go(0),
          ),
        ),
        ActionButton('Search', tooltip: 'Find matching subscribers', onPressed: () => go(0), icon: Icons.search),
      ],
      spacing: 12,
      crossAlign: DVCrossAlign.center,
    ),
    if (reply == null)
      const Loading()
    else if (!reply.ok)
      Refusal(reply.message, onRetry: () => reload(page, fetch))
    else ...<Widget>[
      Panel(<Widget>[
        DVText('${reply.result.total} subscriber${reply.result.total == 1 ? '' : 's'}')
            .modifier(const DVModifier().color(colors.onSurfaceVariant)),
        for (final SubscriberRow row in reply.result.items)
          DVNavLink(
            to: DVRoutes.consolesubscribersMsisdn(msisdn: row.subscriber.msisdn),
            semanticLabel: '${row.subscriber.name}, ${localNumber(row.subscriber.msisdn)}',
            child: DVBox.row(
              <Widget>[
                Expanded(
                  child: DVBox.list(<Widget>[
                    DVText(row.subscriber.name).modifier(const DVModifier().fontWeight(FontWeight.w700)),
                    DVText(
                      '${localNumber(row.subscriber.msisdn)} · ${row.subscriber.planId}${row.subscriber.attached ? '' : ' · phone off'}',
                    ).modifier(const DVModifier().fontSize(12).color(colors.onSurfaceVariant)),
                  ], spacing: 2),
                ),
                if (row.subscriber.barred) const Tag('Barred', warm: true, tooltip: 'This line cannot be charged'),
                DVText(naira(row.balance.airtime)).modifier(const DVModifier().fontWeight(FontWeight.w700)),
                DVText(dataSize(row.balance.dataBytes)).modifier(const DVModifier().color(colors.onSurfaceVariant)),
              ],
              spacing: 12,
              crossAlign: DVCrossAlign.center,
            ).modifier(const DVModifier().paddingSymmetric(vertical: 8).tooltip('Open ${row.subscriber.name}\'s file')),
          ),
      ], spacing: 2),
      DVBox.wrapLine(<Widget>[
        ActionButton(
          'Previous',
          tooltip: 'The previous 25',
          primary: false,
          onPressed: offset.value == 0 ? null : () => go(offset.read() - 25),
        ),
        ActionButton(
          'Next',
          tooltip: 'The next 25',
          primary: false,
          onPressed: offset.value + 25 >= reply.result.total ? null : () => go(offset.read() + 25),
        ),
      ], spacing: 8),
    ],
    AddSubscriberForm(onAdded: () => go(0)),
  ], maxWidth: 1000);
}

@DVFunctionalWidget()
Widget _addSubscriberForm(BuildContext context, {required VoidCallback onAdded}) {
  final DVSignal<String> number = context.signal('');
  final DVSignal<String> name = context.signal('');
  final DVSignal<String> pin = context.signal('');
  final DVSignal<Reply<Subscriber>?> result = context.signal<Reply<Subscriber>?>(null);

  Future<void> add() async {
    result.value = await ask(
      () => consoleAddSubscriber(
        msisdn: number.read(),
        name: name.read(),
        pin: pin.read(),
        planId: '',
        fromJson: Reply.of(Subscriber.fromJson),
      ),
    );
    if (result.read()?.ok ?? false) onAdded();
  }

  final Reply<Subscriber>? done = result.value;
  return Panel(<Widget>[
    const SectionTitle('Add a subscriber', hint: 'Numbers in RTN\'s range, 0999…. A new SIM is issued.'),
    Field('Number', hint: '0999 123 4567', value: number.read(), onChanged: (String v) => number.value = v),
    Field('Name', value: name.read(), onChanged: (String v) => name.value = v),
    Field('PIN', hint: '4 to 6 digits', secret: true, value: pin.read(), onChanged: (String v) => pin.value = v),
    ActionButton('Add subscriber', tooltip: 'Create this line', onPressed: add, icon: Icons.person_add_alt),
    if (done != null)
      done.ok ? Notice('Added ${done.result.name} on SIM ${done.result.imsi}.', tone: 'good') : Notice(done.message),
  ]);
}

@DVFunctionalWidget()
Widget _subscriberFileScreen(BuildContext context, String msisdn) {
  final DVSignal<Reply<SubscriberFile>?> file = context.signal<Reply<SubscriberFile>?>(null);
  final DVSignal<String> amount = context.signal('');
  final DVSignal<String> limit = context.signal('');
  final DVSignal<String> pin = context.signal('');
  final DVSignal<String> note = context.signal('');
  final DVSignal<String> problem = context.signal('');
  Future<Reply<SubscriberFile>> fetch() =>
      consoleSubscriber(msisdn: msisdn, fromJson: Reply.of(SubscriberFile.fromJson));
  loadInto(file, fetch, every: const Duration(seconds: 5));
  final Reply<SubscriberFile>? reply = file.value;
  if (reply == null) return const Screen(<Widget>[PageTitle('Subscriber'), Loading()]);
  if (!reply.ok) {
    return Screen(<Widget>[const PageTitle('Subscriber'), Refusal(reply.message, onRetry: () => reload(file, fetch))]);
  }
  final SubscriberFile f = reply.result;
  final Subscriber s = f.line.subscriber;
  final Balance b = f.line.balance;

  Future<void> act(Future<Reply<Object?>> Function() action, String success) async {
    note.value = '';
    problem.value = '';
    final Reply<Object?> r = await ask(action);
    if (r.ok) {
      note.value = success;
    } else {
      problem.value = r.message;
    }
    await reload(file, fetch);
  }

  return Screen(<Widget>[
    PageTitle(s.name, subtitle: '${localNumber(s.msisdn)} · SIM ${s.imsi}'),
    const TextLink(DVRoutes.consolesubscribers, 'All subscribers', tooltip: 'Back to the subscriber list'),
    if (note.value.isNotEmpty) Notice(note.value, tone: 'good'),
    if (problem.value.isNotEmpty) Notice(problem.value),
    Panel(<Widget>[
      DVBox.wrapLine(<Widget>[
        Stat(
          'Status',
          s.barred ? 'Barred' : 'Active',
          ink: s.barred ? RtnColors.rust : null,
          tooltip: 'Whether the line can be charged',
        ),
        Stat('Phone', s.attached ? 'On' : 'Off', tooltip: 'Whether the handset is attached'),
        Stat('Airtime', naira(b.airtime), tooltip: '${naira(b.reserved)} held for calls'),
        Stat('Data', dataSize(b.dataBytes), tooltip: '${b.bundles.length} bundles'),
        Stat('Loan', naira(b.loan), tooltip: 'Limit ${naira(b.loanLimit)}'),
        Stat('Points', '${b.points}', tooltip: 'Loyalty points'),
      ], spacing: 28),
      DVBox.wrapLine(<Widget>[
        ActionButton(
          s.barred ? 'Lift the bar' : 'Bar the line',
          tooltip: s.barred ? 'Let this line be charged again' : 'Stop all charging on this line',
          danger: !s.barred,
          onPressed: () => act(
            () => consoleSetStatus(
              msisdn: s.msisdn,
              status: s.barred ? 'active' : 'barred',
              fromJson: Reply.of(Done.fromJson),
            ),
            s.barred ? 'The line is active.' : 'The line is barred.',
          ),
        ),
      ], spacing: 8),
    ]),
    Panel(<Widget>[
      const SectionTitle('Top up'),
      DVBox.row(
        <Widget>[
          Expanded(
            child: Field(
              'Amount in naira',
              hint: '500',
              value: amount.read(),
              onChanged: (String v) => amount.value = v,
            ),
          ),
          ActionButton(
            'Top up',
            tooltip: 'Credit this line',
            onPressed: () => act(
              () => consoleTopUp(
                msisdn: s.msisdn,
                amount: amount.read(),
                attempt: newAttempt(),
                fromJson: Reply.of(Outcome.fromJson),
              ),
              'Topped up.',
            ),
          ),
        ],
        spacing: 12,
        crossAlign: DVCrossAlign.center,
      ),
      const SectionTitle('Plan'),
      Choices(
        <String>[for (final Plan p in f.plans) p.id],
        selected: s.planId,
        what: 'plan',
        onSelected: (String id) =>
            act(() => consoleSetPlan(msisdn: s.msisdn, planId: id, fromJson: Reply.of(Done.fromJson)), 'Plan changed.'),
      ),
      const SectionTitle('Loan limit'),
      DVBox.row(
        <Widget>[
          Expanded(
            child: Field(
              'Limit in naira',
              hint: naira(b.loanLimit),
              value: limit.read(),
              onChanged: (String v) => limit.value = v,
            ),
          ),
          ActionButton(
            'Set',
            tooltip: 'Set how much this line may borrow',
            primary: false,
            onPressed: () => act(
              () => consoleSetLoanLimit(msisdn: s.msisdn, amount: limit.read(), fromJson: Reply.of(Done.fromJson)),
              'Loan limit set.',
            ),
          ),
        ],
        spacing: 12,
        crossAlign: DVCrossAlign.center,
      ),
      const SectionTitle('Reset the PIN', hint: 'Only after checking it is them.'),
      DVBox.row(
        <Widget>[
          Expanded(
            child: Field('New PIN', secret: true, value: pin.read(), onChanged: (String v) => pin.value = v),
          ),
          ActionButton(
            'Reset',
            tooltip: 'Give this line a new PIN',
            primary: false,
            onPressed: () => act(
              () => consoleResetPin(msisdn: s.msisdn, pin: pin.read(), fromJson: Reply.of(Done.fromJson)),
              'PIN reset.',
            ),
          ),
        ],
        spacing: 12,
        crossAlign: DVCrossAlign.center,
      ),
    ]),
    Panel(<Widget>[
      const SectionTitle('Ledger'),
      if (f.history.isEmpty) const Empty('No entries.'),
      for (final LedgerEntry e in f.history) LedgerRow(entry: e),
    ], spacing: 2),
    Panel(<Widget>[
      const SectionTitle('Delivered SMS'),
      if (f.inbox.isEmpty) const Empty('None.'),
      for (final SmsMessage m in f.inbox) DVText('${localNumber(m.from)}: ${m.text}'),
    ], spacing: 4),
  ], maxWidth: 1000);
}

/// One ledger entry, as the operator reads it.
@DVFunctionalWidget()
Widget _ledgerRow(BuildContext context, {required LedgerEntry entry, bool showLine = false}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final List<String> parts = <String>[
    if (entry.airtimeDelta != 0) '${entry.airtimeDelta > 0 ? '+' : ''}${naira(entry.airtimeDelta)}',
    if (entry.dataDelta != 0) '${entry.dataDelta > 0 ? '+' : '−'}${dataSize(entry.dataDelta.abs())}',
    if (entry.loanDelta != 0) 'loan ${entry.loanDelta > 0 ? '+' : ''}${naira(entry.loanDelta)}',
  ];
  return DVBox.row(
    <Widget>[
      DVText(
        '#${entry.seq}',
      ).modifier(const DVModifier().fontSize(12).color(colors.onSurfaceVariant).tooltip('Ledger entry ${entry.seq}')),
      Expanded(
        child: DVBox.list(<Widget>[
          DVText('${entryTitle(entry.kind)}${showLine ? ' · ${localNumber(entry.msisdn)}' : ''}')
              .modifier(const DVModifier().fontWeight(FontWeight.w700)),
          DVText('${entry.note} · ${shortTime(entry.at)}')
              .modifier(const DVModifier().fontSize(12).color(colors.onSurfaceVariant)),
        ], spacing: 2),
      ),
      DVText(parts.join('  ')).modifier(const DVModifier().fontWeight(FontWeight.w700)),
    ],
    spacing: 12,
    crossAlign: DVCrossAlign.center,
  ).modifier(
    const DVModifier()
        .paddingSymmetric(vertical: 6)
        .tooltip('Request ${entry.requestId}; airtime after ${naira(entry.airtimeAfter)}'),
  );
}

// ----- catalogue ---------------------------------------------------------------------------

@DVFunctionalWidget()
Widget _catalogScreen(BuildContext context) {
  final DVSignal<Reply<Catalog>?> catalog = context.signal<Reply<Catalog>?>(null);
  Future<Reply<Catalog>> fetch() => consoleCatalog(fromJson: Reply.of(Catalog.fromJson));
  loadInto(catalog, fetch);
  final Reply<Catalog>? reply = catalog.value;
  if (reply == null) return const Screen(<Widget>[PageTitle('Catalogue'), Loading()]);
  if (!reply.ok) {
    return Screen(<Widget>[
      const PageTitle('Catalogue'),
      Refusal(reply.message, onRetry: () => reload(catalog, fetch)),
    ]);
  }
  final Catalog c = reply.result;
  return Screen(<Widget>[
    const PageTitle(
      'Catalogue',
      subtitle: 'A change applies to the next charge. Bundles already bought keep what they were sold with.',
    ),
    const SectionTitle(
      'Rating plans',
      hint: 'Rates in kobo: per second of call, per SMS part, per MB outside a bundle.',
    ),
    for (final Plan p in c.plans) PlanEditor(plan: p, onSaved: () => reload(catalog, fetch)),
    PlanEditor(
      plan: const Plan(id: '', name: ''),
      onSaved: () => reload(catalog, fetch),
    ),
    const SectionTitle('Data bundles'),
    for (final Bundle b in c.bundles) BundleEditor(bundle: b, onSaved: () => reload(catalog, fetch)),
    BundleEditor(
      bundle: const Bundle(id: '', name: ''),
      onSaved: () => reload(catalog, fetch),
    ),
  ], maxWidth: 1000);
}

@DVFunctionalWidget()
Widget _planEditor(BuildContext context, {required Plan plan, required VoidCallback onSaved}) {
  final bool fresh = plan.id.isEmpty;
  final DVSignal<String> id = context.signal(plan.id);
  final DVSignal<String> name = context.signal(plan.name);
  final DVSignal<String> voice = context.signal(fresh ? '' : '${plan.voicePerSecond}');
  final DVSignal<String> sms = context.signal(fresh ? '' : '${plan.smsPerSegment}');
  final DVSignal<String> data = context.signal(fresh ? '' : '${plan.dataPerMb}');
  final DVSignal<Reply<Done>?> result = context.signal<Reply<Done>?>(null);

  Future<void> save() async {
    result.value = await ask(
      () => consoleSavePlan(
        id: id.read(),
        name: name.read(),
        voicePerSecond: voice.read(),
        smsPerSegment: sms.read(),
        dataPerMb: data.read(),
        fromJson: Reply.of(Done.fromJson),
      ),
    );
    if (result.read()?.ok ?? false) onSaved();
  }

  return Panel(<Widget>[
    DVText(fresh ? 'New plan' : plan.name).modifier(const DVModifier().fontWeight(FontWeight.w800)),
    DVBox.wrapLine(<Widget>[
      if (fresh)
        SizedBox(
          width: 160,
          child: Field('Id', hint: 'night-owl', value: id.read(), onChanged: (String v) => id.value = v),
        ),
      SizedBox(
        width: 180,
        child: Field('Name', value: name.read(), onChanged: (String v) => name.value = v),
      ),
      SizedBox(
        width: 120,
        child: Field('Voice /s', value: voice.read(), onChanged: (String v) => voice.value = v),
      ),
      SizedBox(
        width: 120,
        child: Field('SMS /part', value: sms.read(), onChanged: (String v) => sms.value = v),
      ),
      SizedBox(
        width: 120,
        child: Field('Data /MB', value: data.read(), onChanged: (String v) => data.value = v),
      ),
    ], spacing: 12),
    ActionButton(
      fresh ? 'Add plan' : 'Save ${plan.name}',
      tooltip: fresh ? 'Add this rating plan' : 'Save the new rates',
      primary: fresh,
      onPressed: save,
    ),
    if (result.value case final Reply<Done> r) r.ok ? const Notice('Saved.', tone: 'good') : Notice(r.message),
  ], spacing: 8);
}

@DVFunctionalWidget()
Widget _bundleEditor(BuildContext context, {required Bundle bundle, required VoidCallback onSaved}) {
  final bool fresh = bundle.id.isEmpty;
  final DVSignal<String> id = context.signal(bundle.id);
  final DVSignal<String> name = context.signal(bundle.name);
  final DVSignal<String> size = context.signal(fresh ? '' : '${bundle.dataBytes ~/ mb}');
  final DVSignal<String> price = context.signal(fresh ? '' : '${bundle.price ~/ 100}');
  final DVSignal<String> days = context.signal(fresh ? '' : '${bundle.validityDays}');
  final DVSignal<String> offer = context.signal(bundle.offer ?? '');
  final DVSignal<Reply<Done>?> result = context.signal<Reply<Done>?>(null);

  Future<void> save() async {
    result.value = await ask(
      () => consoleSaveBundle(
        id: id.read(),
        name: name.read(),
        megabytes: size.read(),
        price: price.read(),
        validityDays: days.read(),
        offer: offer.read(),
        fromJson: Reply.of(Done.fromJson),
      ),
    );
    if (result.read()?.ok ?? false) onSaved();
  }

  return Panel(<Widget>[
    DVText(fresh ? 'New bundle' : bundle.name).modifier(const DVModifier().fontWeight(FontWeight.w800)),
    DVBox.wrapLine(<Widget>[
      if (fresh)
        SizedBox(
          width: 160,
          child: Field('Id', hint: 'night-2gb', value: id.read(), onChanged: (String v) => id.value = v),
        ),
      SizedBox(
        width: 180,
        child: Field('Name', value: name.read(), onChanged: (String v) => name.value = v),
      ),
      SizedBox(
        width: 110,
        child: Field('MB', value: size.read(), onChanged: (String v) => size.value = v),
      ),
      SizedBox(
        width: 110,
        child: Field('Price ₦', value: price.read(), onChanged: (String v) => price.value = v),
      ),
      SizedBox(
        width: 90,
        child: Field('Days', value: days.read(), onChanged: (String v) => days.value = v),
      ),
      SizedBox(
        width: 180,
        child: Field('Offer line', hint: 'Best value', value: offer.read(), onChanged: (String v) => offer.value = v),
      ),
    ], spacing: 12),
    ActionButton(
      fresh ? 'Add bundle' : 'Save ${bundle.name}',
      tooltip: fresh ? 'Add this bundle to the catalogue' : 'Save this bundle',
      primary: fresh,
      onPressed: save,
    ),
    if (result.value case final Reply<Done> r) r.ok ? const Notice('Saved.', tone: 'good') : Notice(r.message),
  ], spacing: 8);
}

// ----- vouchers ----------------------------------------------------------------------------

@DVFunctionalWidget()
Widget _vouchersScreen(BuildContext context) {
  final DVSignal<Reply<VoucherBook>?> book = context.signal<Reply<VoucherBook>?>(null);
  final DVSignal<String> count = context.signal('5');
  final DVSignal<String> amount = context.signal('500');
  final DVSignal<bool> busy = context.signal(false);
  Future<Reply<VoucherBook>> fetch() => consoleVouchers(fromJson: Reply.of(VoucherBook.fromJson));
  loadInto(book, fetch);
  final Reply<VoucherBook>? reply = book.value;
  final ColorScheme colors = Theme.of(context).colorScheme;

  Future<void> printBatch() async {
    busy.value = true;
    book.value = await ask(
      () => consoleIssueVouchers(count: count.read(), amount: amount.read(), fromJson: Reply.of(VoucherBook.fromJson)),
    );
    busy.value = false;
  }

  return Screen(<Widget>[
    const PageTitle('Vouchers', subtitle: 'Scratch-card recharge vouchers. A PIN is shown once, when it is printed.'),
    Panel(<Widget>[
      const SectionTitle('Print a batch'),
      DVBox.wrapLine(<Widget>[
        SizedBox(
          width: 140,
          child: Field('How many', value: count.read(), onChanged: (String v) => count.value = v),
        ),
        SizedBox(
          width: 160,
          child: Field('Value in naira', value: amount.read(), onChanged: (String v) => amount.value = v),
        ),
      ], spacing: 12),
      ActionButton(
        'Print vouchers',
        tooltip: 'Issue a batch of new vouchers',
        busy: busy.value,
        onPressed: printBatch,
        icon: Icons.print_outlined,
      ),
    ]),
    if (reply == null)
      const Loading()
    else if (!reply.ok)
      Refusal(reply.message, onRetry: () => reload(book, fetch))
    else ...<Widget>[
      if (reply.result.printed.isNotEmpty)
        Panel(<Widget>[
          const SectionTitle(
            'Just printed',
            hint: 'Hand these out now: the PINs are not kept and will not be shown again.',
          ),
          for (final PrintedVoucher v in reply.result.printed)
            DVBox.row(
              <Widget>[
                DVText(v.serial).modifier(const DVModifier().color(colors.onSurfaceVariant)),
                Expanded(
                  child: DVText(<String>[for (int i = 0; i < v.pin.length; i += 4) v.pin.substring(i, i + 4)].join(' '))
                      .modifier(const DVModifier().fontFamily('monospace').fontWeight(FontWeight.w700).fontSize(16)),
                ),
                DVText(naira(v.amount)),
              ],
              spacing: 12,
              crossAlign: DVCrossAlign.center,
            ),
        ], accent: true),
      Panel(<Widget>[
        const SectionTitle('All vouchers'),
        if (reply.result.vouchers.isEmpty) const Empty('None printed yet.'),
        for (final Voucher v in reply.result.vouchers)
          DVBox.row(
            <Widget>[
              Expanded(child: DVText(v.serial)),
              DVText(naira(v.amount)),
              Tag(
                v.usedBy == null ? 'Unused' : 'Used by ${localNumber(v.usedBy!)}',
                warm: v.usedBy != null,
                tooltip: v.usedBy == null
                    ? 'Printed ${shortTime(v.createdAt)}'
                    : 'Redeemed ${shortTime(v.usedAt ?? 0)}',
              ),
            ],
            spacing: 12,
            crossAlign: DVCrossAlign.center,
          ),
      ], spacing: 6),
    ],
  ], maxWidth: 900);
}

// ----- care --------------------------------------------------------------------------------

@DVFunctionalWidget()
Widget _careDeskScreen(BuildContext context) {
  final DVSignal<Reply<CareDesk>?> desk = context.signal<Reply<CareDesk>?>(null);
  final DVSignal<String> open = context.signal('');
  Future<Reply<CareDesk>> fetch() => consoleCareDesk(fromJson: Reply.of(CareDesk.fromJson));
  loadInto(desk, fetch, every: const Duration(seconds: 4));
  final Reply<CareDesk>? reply = desk.value;
  final ColorScheme colors = Theme.of(context).colorScheme;
  return Screen(<Widget>[
    const PageTitle(
      'Care',
      subtitle: 'Conversations waiting for an answer come first. Replying takes over from the assistant.',
    ),
    if (reply == null)
      const Loading()
    else if (!reply.ok)
      Refusal(reply.message, onRetry: () => reload(desk, fetch))
    else
      Panel(<Widget>[
        if (reply.result.threads.isEmpty) const Empty('Nobody has written yet.'),
        for (final CareThread t in reply.result.threads)
          DVBox.row(
            <Widget>[
              Expanded(
                child: DVBox.list(<Widget>[
                  DVText('${t.name} · ${localNumber(t.msisdn)}')
                      .modifier(const DVModifier().fontWeight(FontWeight.w700)),
                  DVText(t.lastText).modifier(const DVModifier().maxLines(1).color(colors.onSurfaceVariant)),
                ], spacing: 2),
              ),
              if (t.waiting) const Tag('Waiting', warm: true, tooltip: 'The subscriber wrote last'),
            ],
            spacing: 12,
            crossAlign: DVCrossAlign.center,
          ).modifier(
            const DVModifier()
                .paddingSymmetric(vertical: 8, horizontal: 8)
                .rounded(12)
                .backgroundColor(open.value == t.msisdn ? colors.primaryContainer : Colors.transparent)
                .tooltip('Open the conversation with ${t.name}')
                .onTap(() => open.value = t.msisdn),
          ),
      ], spacing: 2),
    // Keyed by the number, so opening another conversation starts afresh.
    if (open.value.isNotEmpty) CareThreadView(msisdn: open.value, key: ValueKey<String>(open.value)),
  ], maxWidth: 900);
}

@DVFunctionalWidget()
Widget _careThreadView(BuildContext context, {required String msisdn}) {
  final DVSignal<Reply<CareChat>?> chat = context.signal<Reply<CareChat>?>(null);
  final DVSignal<String> draft = context.signal('');
  Future<Reply<CareChat>> fetch() => consoleCareThread(msisdn: msisdn, fromJson: Reply.of(CareChat.fromJson));
  loadInto(chat, fetch, every: const Duration(seconds: 4));
  final Reply<CareChat>? reply = chat.value;

  Future<void> send() async {
    if (draft.read().trim().isEmpty) return;
    chat.value = await ask(
      () => consoleCareReply(msisdn: msisdn, text: draft.read(), fromJson: Reply.of(CareChat.fromJson)),
    );
    draft.value = '';
  }

  return Panel(<Widget>[
    SectionTitle('Conversation with ${localNumber(msisdn)}'),
    if (reply == null)
      const Loading()
    else if (!reply.ok)
      Notice(reply.message)
    else
      for (final CareMessage m in reply.result.messages) ChatBubble(message: m, operator: true),
    KeyedSubtree(
      key: ValueKey<int>(reply?.value?.messages.length ?? 0),
      child: Field('Your answer', value: draft.read(), onChanged: (String v) => draft.value = v, onSubmitted: send),
    ),
    ActionButton('Send answer', tooltip: 'Answer as an RTN care agent', onPressed: send, icon: Icons.send),
  ]);
}

// ----- the SMS centre and the ledger ------------------------------------------------------

@DVFunctionalWidget()
Widget _smsLogScreen(BuildContext context) {
  final DVSignal<Reply<Inbox>?> log = context.signal<Reply<Inbox>?>(null);
  Future<Reply<Inbox>> fetch() => consoleSms(limit: 100, fromJson: Reply.of(Inbox.fromJson));
  loadInto(log, fetch, every: const Duration(seconds: 3));
  final Reply<Inbox>? reply = log.value;
  final ColorScheme colors = Theme.of(context).colorScheme;
  return Screen(<Widget>[
    const PageTitle('SMS centre', subtitle: 'The latest 100 messages. Queued ones wait for the phone to come back on.'),
    if (reply == null)
      const Loading()
    else if (!reply.ok)
      Refusal(reply.message, onRetry: () => reload(log, fetch))
    else
      Panel(<Widget>[
        for (final SmsMessage m in reply.result.messages)
          DVBox.row(
            <Widget>[
              Expanded(
                child: DVBox.list(<Widget>[
                  DVText('${localNumber(m.from)} → ${localNumber(m.to)}')
                      .modifier(const DVModifier().fontWeight(FontWeight.w700)),
                  DVText(m.from == serviceNumber && m.text.contains('sign-in code') ? 'Sign-in code (hidden)' : m.text)
                      .modifier(const DVModifier().color(colors.onSurfaceVariant)),
                ], spacing: 2),
              ),
              Tag(
                m.state,
                warm: m.state != 'delivered',
                tooltip: '${m.segments} part${m.segments == 1 ? '' : 's'}, sent ${shortTime(m.submittedAt)}',
              ),
            ],
            spacing: 12,
            crossAlign: DVCrossAlign.center,
          ).modifier(const DVModifier().paddingSymmetric(vertical: 6)),
      ], spacing: 2),
  ], maxWidth: 1000);
}

@DVFunctionalWidget()
Widget _ledgerScreen(BuildContext context) {
  final DVSignal<Reply<LedgerPage>?> ledger = context.signal<Reply<LedgerPage>?>(null);
  Future<Reply<LedgerPage>> fetch() => consoleLedger(limit: 100, fromJson: Reply.of(LedgerPage.fromJson));
  loadInto(ledger, fetch, every: const Duration(seconds: 3));
  final Reply<LedgerPage>? reply = ledger.value;
  return Screen(<Widget>[
    const PageTitle('Ledger', subtitle: 'The latest 100 balance changes. Every balance is the sum of its entries.'),
    if (reply == null)
      const Loading()
    else if (!reply.ok)
      Refusal(reply.message, onRetry: () => reload(ledger, fetch))
    else
      Panel(<Widget>[
        for (final LedgerEntry e in reply.result.entries) LedgerRow(entry: e, showLine: true),
      ], spacing: 2),
  ], maxWidth: 1000);
}
