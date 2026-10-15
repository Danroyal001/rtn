// The line itself: name, plan, PIN, SIM, and the phone it is in.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/money.dart';
import '../services/remote.dart';
import '../services/wire.dart';

@DVFunctionalWidget()
Widget _accountScreen(BuildContext context) {
  final DVSignal<Reply<Line>?> line = context.signal<Reply<Line>?>(null);
  final DVSignal<Reply<Catalog>?> catalog = context.signal<Reply<Catalog>?>(null);
  final DVSignal<String> note = context.signal('');
  final DVSignal<String> problem = context.signal('');
  Future<Reply<Line>> fetch() => myLine(fromJson: Reply.of(Line.fromJson));
  loadInto(line, fetch);
  loadInto(catalog, () => bundleCatalog(fromJson: Reply.of(Catalog.fromJson)));
  final Reply<Line>? reply = line.value;
  if (reply == null) return const Screen(<Widget>[PageTitle('Account'), Loading(label: 'Loading your line')]);
  if (!reply.ok) return Screen(<Widget>[const PageTitle('Account'), Refusal(reply.message, onRetry: () => reload(line, fetch))]);
  final Line l = reply.result;
  final List<Plan> plans = catalog.value?.value?.plans ?? const <Plan>[];

  Future<void> report(Future<Reply<Object?>> Function() action, String success) async {
    note.value = '';
    problem.value = '';
    final Reply<Object?> r = await ask(action);
    if (r.ok) {
      note.value = success;
    } else {
      problem.value = r.message;
    }
    await reload(line, fetch);
  }

  return Screen(<Widget>[
    PageTitle(l.subscriber.name, subtitle: localNumber(l.subscriber.msisdn)),
    if (note.value.isNotEmpty) Notice(note.value, tone: 'good'),
    if (problem.value.isNotEmpty) Notice(problem.value),
    if (l.subscriber.barred) const Notice('This line is suspended. Chat to RTN care to have it restored.'),
    Panel(<Widget>[
      const SectionTitle('Your line'),
      DVBox.wrap(<Widget>[
        Stat('Number', localNumber(l.subscriber.msisdn), tooltip: 'Your phone number'),
        Stat('SIM (IMSI)', l.subscriber.imsi, tooltip: 'The identity of the SIM this number is on'),
        Stat('Plan', l.plan?.name ?? l.subscriber.planId, tooltip: 'How calls, SMS and data are charged'),
        Stat('On RTN since', shortDate(l.subscriber.createdAt), tooltip: 'When this line was opened'),
      ], spacing: 28),
      NameForm(name: l.subscriber.name, onSave: (String name) => report(() => renameLine(name: name, fromJson: Reply.of(Done.fromJson)), 'Name saved.')),
    ]),
    if (plans.isNotEmpty)
      Panel(<Widget>[
        const SectionTitle('Tariff plan', hint: 'Rates per second of call, per SMS part and per MB of data outside a bundle.'),
        for (final Plan p in plans)
          DVBox.row(<Widget>[
            Expanded(
              child: DVBox.list(<Widget>[
                DVText(p.name).modifier(const DVModifier().fontWeight(FontWeight.w800)),
                DVText('Calls ${naira(p.voicePerSecond)}/s · SMS ${naira(p.smsPerSegment)} · Data ${naira(p.dataPerMb)}/MB'),
              ], spacing: 2),
            ),
            if (p.id == l.subscriber.planId)
              const Tag('Your plan')
            else
              ActionButton('Switch', tooltip: 'Move your line to the ${p.name} plan', primary: false,
                  onPressed: () => report(() => changePlan(planId: p.id, fromJson: Reply.of(Done.fromJson)), 'You are now on ${p.name}.')),
          ], spacing: 12, crossAlign: DVCrossAlign.center),
      ]),
    Panel(<Widget>[
      const SectionTitle('Your phone', hint: 'Simulated: switch the handset off to see the SMS centre hold messages for it.'),
      DVBox.row(<Widget>[
        Expanded(child: DVText(l.subscriber.attached ? 'The phone is on the network.' : 'The phone is off. Messages are waiting for it.')),
        Semantics(
          label: 'Phone on the network',
          child: Switch(
            value: l.subscriber.attached,
            onChanged: (bool on) =>
                report(() => setHandset(on: on, fromJson: Reply.of(Done.fromJson)), on ? 'Phone on.' : 'Phone off.'),
          ),
        ),
      ], spacing: 12, crossAlign: DVCrossAlign.center).modifier(
          const DVModifier().tooltip(l.subscriber.attached ? 'Switch the phone off' : 'Switch the phone on')),
    ]),
    PinForm(
      onSave: (String current, String fresh) =>
          report(() => changePin(current: current, fresh: fresh, fromJson: Reply.of(Done.fromJson)), 'PIN changed.'),
    ),
    PinAction(
      title: 'Replace your SIM',
      hint: 'Moves your number, balance and history to a new SIM. The old one stops working.',
      button: 'Swap SIM',
      tooltip: 'Move this number to a new SIM',
      onConfirm: (String pin) => report(() => swapSim(pin: pin, fromJson: Reply.of(Line.fromJson)), 'Your number is on a new SIM.'),
    ),
    PinAction(
      title: 'Lost or stolen phone',
      hint: 'Suspends the line at once so nobody can use your airtime. RTN care lifts it when you have a new SIM.',
      button: 'Suspend line',
      tooltip: 'Stop all use of this line now',
      danger: true,
      onConfirm: (String pin) => report(() => suspendLine(pin: pin, fromJson: Reply.of(Done.fromJson)), 'Your line is suspended.'),
    ),
    const Panel(<Widget>[
      SectionTitle('More'),
      DVBox.grid(<Widget>[
        LinkTile(DVRoutes.mymessages, 'Messages', icon: Icons.sms_outlined, tooltip: 'Send and read SMS'),
        LinkTile(DVRoutes.mynotifications, 'Notifications', icon: Icons.notifications_none, tooltip: 'Messages from RTN'),
        LinkTile(DVRoutes.myrewards, 'Rewards', icon: Icons.card_giftcard, tooltip: 'Spend your loyalty points'),
        LinkTile(DVRoutes.myborrow, 'Borrow', icon: Icons.handshake_outlined, tooltip: 'Borrow airtime'),
        LinkTile(DVRoutes.mysupport, 'Support', icon: Icons.support_agent, tooltip: 'Chat to RTN care'),
        LinkTile(DVRoutes.myussd, 'USSD', icon: Icons.dialpad, tooltip: 'Dial RTN\'s USSD codes'),
      ], columns: 3, spacing: 8),
    ]),
  ]);
}

@DVFunctionalWidget()
Widget _nameForm(BuildContext context, {required String name, required void Function(String) onSave}) {
  final DVSignal<String> draft = context.signal(name);
  return DVBox.row(<Widget>[
    Expanded(child: Field('Name on the line', value: draft.read(), onChanged: (String v) => draft.value = v)),
    ActionButton('Save', tooltip: 'Save the name on your line', primary: false, onPressed: () => onSave(draft.read())),
  ], spacing: 12, crossAlign: DVCrossAlign.center);
}

@DVFunctionalWidget()
Widget _pinForm(BuildContext context, {required void Function(String current, String fresh) onSave}) {
  final DVSignal<String> current = context.signal('');
  final DVSignal<String> fresh = context.signal('');
  final DVSignal<String> again = context.signal('');
  final bool matches = fresh.value.isNotEmpty && fresh.value == again.value;
  return Panel(<Widget>[
    const SectionTitle('Change your PIN', hint: 'Your PIN confirms transfers, data sharing and SIM changes. 4 to 6 digits.'),
    Field('Current PIN', secret: true, value: current.read(), onChanged: (String v) => current.value = v),
    Field('New PIN', secret: true, value: fresh.read(), onChanged: (String v) => fresh.value = v),
    Field('New PIN again', secret: true, value: again.read(), onChanged: (String v) => again.value = v,
        helper: again.value.isNotEmpty && !matches ? 'The two new PINs differ.' : ''),
    ActionButton('Change PIN', tooltip: matches ? 'Save the new PIN' : 'Type the new PIN twice first',
        onPressed: matches ? () => onSave(current.read(), fresh.read()) : null),
  ]);
}

@DVFunctionalWidget()
Widget _pinAction(
  BuildContext context, {
  required String title,
  required String hint,
  required String button,
  required String tooltip,
  required void Function(String pin) onConfirm,
  bool danger = false,
}) {
  final DVSignal<bool> open = context.signal(false);
  final DVSignal<String> pin = context.signal('');
  return Panel(<Widget>[
    SectionTitle(title, hint: hint),
    if (!open.value)
      ActionButton(button, tooltip: tooltip, primary: false, danger: danger, onPressed: () => open.value = true)
    else ...<Widget>[
      Field('Your PIN to confirm', secret: true, value: pin.read(), onChanged: (String v) => pin.value = v),
      DVBox.wrap(<Widget>[
        ActionButton('Confirm: $button', tooltip: tooltip, danger: danger, onPressed: () {
          open.value = false;
          onConfirm(pin.read());
        }),
        ActionButton('Cancel', tooltip: 'Leave things as they are', primary: false, onPressed: () => open.value = false),
      ], spacing: 8),
    ],
  ]);
}
