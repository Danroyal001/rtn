// Sending airtime and sharing data, both confirmed with the PIN.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/money.dart';
import '../services/remote.dart';
import '../services/wire.dart';

@DVFunctionalWidget()
Widget _transferScreen(BuildContext context) {
  final DVSignal<String> what = context.signal('Airtime');
  final DVSignal<String> to = context.signal('');
  final DVSignal<String> amount = context.signal('');
  final DVSignal<String> pin = context.signal('');
  final DVSignal<String> attempt = context.signal(newAttempt());
  final DVSignal<bool> busy = context.signal(false);
  final DVSignal<Reply<Outcome>?> result = context.signal<Reply<Outcome>?>(null);
  final ColorScheme colors = Theme.of(context).colorScheme;
  final bool airtime = what.value == 'Airtime';

  Future<void> send() async {
    busy.value = true;
    result.value = await ask(() => airtime
        ? transferAirtime(to: to.read(), amount: amount.read(), pin: pin.read(), attempt: attempt.read(), fromJson: Reply.of(Outcome.fromJson))
        : shareData(to: to.read(), megabytes: amount.read(), pin: pin.read(), attempt: attempt.read(), fromJson: Reply.of(Outcome.fromJson)));
    busy.value = false;
    attempt.value = newAttempt();
  }

  final Reply<Outcome>? done = result.value;
  final int? units = parseNaira(amount.value);
  return Screen(<Widget>[
    const PageTitle('Send', subtitle: 'Send airtime, or share data from your bundles, to another RTN line.'),
    Choices(const <String>['Airtime', 'Data'], selected: what.value, what: 'thing to send', onSelected: (String v) {
      what.value = v;
      amount.value = '';
      result.value = null;
    }),
    Panel(<Widget>[
      Field('Their RTN number', hint: '0999 000 0002', value: to.read(), onChanged: (String v) => to.value = v),
      Field(airtime ? 'Amount in naira' : 'Megabytes to share',
          hint: airtime ? '₦50 to ₦50,000' : '50 MB to 10 GB',
          value: amount.read(),
          onChanged: (String v) => amount.value = v),
      if (airtime && units != null && units > 0)
        DVText('They get ${naira(units)}. The fee is ₦10, so ${naira(units + 1000)} leaves your airtime.')
            .modifier(const DVModifier().color(colors.onSurfaceVariant)),
      if (!airtime)
        const DVText('Shared data comes from the bundles that expire first, and expires with them.')
            .modifier(const DVModifier().color(colors.onSurfaceVariant)),
      Field('Your PIN', hint: '4 to 6 digits', secret: true, value: pin.read(), onChanged: (String v) => pin.value = v, onSubmitted: send),
      ActionButton(airtime ? 'Send airtime' : 'Share data',
          tooltip: airtime ? 'Send this airtime now' : 'Share this data now', busy: busy.value, onPressed: send, icon: Icons.send),
    ]),
    if (done != null)
      done.ok
          ? Notice(
              airtime
                  ? 'Sent ${naira(done.result.detail.amount)} to ${localNumber(done.result.detail.to)}. Your airtime: ${naira(done.result.balance.airtime)}.'
                  : 'Shared ${dataSize(done.result.detail.bytes)} with ${localNumber(done.result.detail.to)}. Your data: ${dataSize(done.result.balance.dataBytes)}.',
              tone: 'good')
          : Notice(done.message),
    const DVText('Or dial *321*number*amount*PIN# to send airtime from any phone.')
        .modifier(const DVModifier().fontSize(13).color(colors.onSurfaceVariant)),
  ]);
}
