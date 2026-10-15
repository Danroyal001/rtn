// Borrowing airtime, repaid from the next recharge.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/money.dart';
import '../services/remote.dart';
import '../services/wire.dart';

const List<int> loanOffers = <int>[10000, 20000, 50000];

@DVFunctionalWidget()
Widget _borrowScreen(BuildContext context) {
  final DVSignal<Reply<Line>?> line = context.signal<Reply<Line>?>(null);
  final DVSignal<String> choice = context.signal('');
  final DVSignal<String> attempt = context.signal(newAttempt());
  final DVSignal<bool> busy = context.signal(false);
  final DVSignal<Reply<Outcome>?> result = context.signal<Reply<Outcome>?>(null);
  Future<Reply<Line>> fetch() => myLine(fromJson: Reply.of(Line.fromJson));
  loadInto(line, fetch);

  final Reply<Line>? reply = line.value;
  if (reply == null) return const Screen(<Widget>[PageTitle('Borrow airtime'), Loading()]);
  if (!reply.ok) {
    return Screen(<Widget>[
      const PageTitle('Borrow airtime'),
      Refusal(reply.message, onRetry: () => reload(line, fetch)),
    ]);
  }
  final Balance b = reply.result.balance;
  final List<String> offers = <String>[
    for (final int amount in loanOffers)
      if (amount <= b.loanLimit) nairaShort(amount),
  ];

  Future<void> borrow() async {
    if (choice.read().isEmpty) return;
    busy.value = true;
    result.value = await ask(
      () => borrowAirtime(amount: choice.read(), attempt: attempt.read(), fromJson: Reply.of(Outcome.fromJson)),
    );
    busy.value = false;
    attempt.value = newAttempt();
    await reload(line, fetch);
  }

  final Reply<Outcome>? done = result.value;
  final int? units = parseNaira(choice.value);
  return Screen(<Widget>[
    const PageTitle('Borrow airtime', subtitle: 'Airtime now, repaid from your next recharge with a 10% service fee.'),
    Panel(<Widget>[
      DVBox.wrapLine(<Widget>[
        Stat('You owe', naira(b.loan), tooltip: 'Taken from your next recharge'),
        Stat('You can borrow up to', naira(b.loanLimit), tooltip: 'Your loan limit'),
      ], spacing: 32),
    ]),
    if (b.loan > 0)
      Notice('Repay the ${naira(b.loan)} you owe before borrowing again. Any recharge repays it.', tone: 'info')
    else if (offers.isEmpty)
      const Notice('This line cannot borrow airtime yet.', tone: 'info')
    else
      Panel(<Widget>[
        const SectionTitle('How much?'),
        Choices(offers, selected: choice.value, what: 'amount', onSelected: (String v) => choice.value = v),
        if (units != null) DVText('You get ${naira(units)} now and repay ${naira(units + units ~/ 10)}.'),
        ActionButton(
          'Borrow ${choice.value}',
          tooltip: 'Borrow this airtime now',
          busy: busy.value,
          onPressed: choice.value.isEmpty ? null : borrow,
          icon: Icons.handshake_outlined,
        ),
      ]),
    if (done != null)
      done.ok
          ? Notice(
              'You borrowed ${naira(done.result.detail.borrowed)}. You will repay ${naira(done.result.detail.owed)}.',
              tone: 'good',
            )
          : Notice(done.message),
    const Empty('Or dial *303# from the line.'),
  ]);
}
