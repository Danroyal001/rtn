// Recharging: a scratch-card voucher, or a card through the payment provider.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/money.dart';
import '../services/remote.dart';
import '../services/wire.dart';

const List<String> rechargeAmounts = <String>['₦100', '₦200', '₦500', '₦1,000', '₦2,000', 'Other'];

@DVFunctionalWidget()
Widget _rechargeScreen(BuildContext context) {
  final DVSignal<String> method = context.signal('Voucher');
  final DVSignal<String> who = context.signal('Me');
  final DVSignal<String> number = context.signal('');
  final DVSignal<String> pin = context.signal('');
  final DVSignal<String> preset = context.signal('₦500');
  final DVSignal<String> other = context.signal('');
  final DVSignal<String> card = context.signal('');
  final DVSignal<String> expiry = context.signal('');
  final DVSignal<String> cvv = context.signal('');
  final DVSignal<String> attempt = context.signal(newAttempt());
  final DVSignal<bool> busy = context.signal(false);
  final DVSignal<Reply<Outcome>?> result = context.signal<Reply<Outcome>?>(null);
  final ColorScheme colors = Theme.of(context).colorScheme;

  String amount() => preset.read() == 'Other' ? other.read() : preset.read();
  String target() => who.read() == 'Me' ? '' : number.read();

  Future<void> submit() async {
    busy.value = true;
    result.value = await ask(() => method.read() == 'Voucher'
        ? rechargeVoucher(pin: pin.read(), forNumber: target(), attempt: attempt.read(), fromJson: Reply.of(Outcome.fromJson))
        : rechargeCard(
            forNumber: target(),
            amount: amount(),
            cardNumber: card.read(),
            expiry: expiry.read(),
            cvv: cvv.read(),
            attempt: attempt.read(),
            fromJson: Reply.of(Outcome.fromJson),
          ));
    busy.value = false;
    attempt.value = newAttempt();
  }

  final Reply<Outcome>? done = result.value;
  return Screen(<Widget>[
    const PageTitle('Recharge', subtitle: 'Top up airtime with a voucher PIN or a bank card.'),
    Choices(const <String>['Voucher', 'Card'], selected: method.value, what: 'way to pay', onSelected: (String v) {
      method.value = v;
      result.value = null;
    }),
    Panel(<Widget>[
      const SectionTitle('Recharge for'),
      Choices(const <String>['Me', 'Someone else'], selected: who.value, what: 'recipient', onSelected: (String v) => who.value = v),
      if (who.value != 'Me')
        Field('Their RTN number', hint: '0999 000 0002', value: number.read(), onChanged: (String v) => number.value = v),
    ]),
    if (method.value == 'Voucher')
      Panel(<Widget>[
        const SectionTitle('Voucher PIN', hint: 'The 16 digits under the scratch panel. Spaces are fine.'),
        Field('Voucher PIN', hint: '1234 5678 9012 3456', value: pin.read(), onChanged: (String v) => pin.value = v, onSubmitted: submit),
        ActionButton('Recharge', tooltip: 'Load this voucher onto the line', busy: busy.value, onPressed: submit, icon: Icons.bolt),
        const DVText('Or dial *555*PIN# from the line.').modifier(const DVModifier().fontSize(13).color(colors.onSurfaceVariant)),
      ])
    else
      Panel(<Widget>[
        const SectionTitle('Amount'),
        Choices(rechargeAmounts, selected: preset.value, what: 'amount', onSelected: (String v) => preset.value = v),
        if (preset.value == 'Other')
          Field('Amount in naira', hint: '₦50 to ₦100,000', value: other.read(), onChanged: (String v) => other.value = v),
        const SectionTitle('Card', hint: 'Paid through MockPay, RTN\'s test payment provider. No real money moves.'),
        Field('Card number', hint: '4242 4242 4242 4242', value: card.read(), onChanged: (String v) => card.value = v),
        DVBox.row(<Widget>[
          Expanded(child: Field('Expiry', hint: 'MM/YY', value: expiry.read(), onChanged: (String v) => expiry.value = v)),
          Expanded(child: Field('Security code', hint: '3 digits', secret: true, value: cvv.read(), onChanged: (String v) => cvv.value = v)),
        ], spacing: 12),
        ActionButton('Pay ${amount().isEmpty ? '' : amount()}',
            tooltip: 'Charge the card and recharge the line', busy: busy.value, onPressed: submit, icon: Icons.credit_card),
        const DVText('Test cards: 4242 4242 4242 4242 is approved; 4000 0000 0000 0002 is declined.')
            .modifier(const DVModifier().fontSize(13).color(colors.onSurfaceVariant)),
      ]),
    if (done != null)
      done.ok
          ? Notice(
              'Recharged ${naira(done.result.detail.amount)}${done.result.detail.repaid > 0 ? ', of which ${naira(done.result.detail.repaid)} repaid your loan' : ''}.'
              '${done.result.reference.isEmpty ? '' : ' Payment reference ${done.result.reference}.'}',
              tone: 'good')
          : Notice(done.message),
  ]);
}
