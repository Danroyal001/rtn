// Buying data: for this line, or as a gift to another.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/money.dart';
import '../services/remote.dart';
import '../services/wire.dart';

const List<String> bundlePeriods = <String>['All', 'Daily', 'Weekly', 'Monthly'];

bool inBundlePeriod(Bundle b, String period) => switch (period) {
      'Daily' => b.validityDays <= 1,
      'Weekly' => b.validityDays > 1 && b.validityDays <= 7,
      'Monthly' => b.validityDays > 7,
      _ => true,
    };

@DVFunctionalWidget()
Widget _dataScreen(BuildContext context) {
  final DVSignal<Reply<Catalog>?> catalog = context.signal<Reply<Catalog>?>(null);
  final DVSignal<String> period = context.signal('All');
  final DVSignal<String> who = context.signal('Me');
  final DVSignal<String> number = context.signal('');
  final DVSignal<Bundle?> chosen = context.signal<Bundle?>(null);
  final DVSignal<String> attempt = context.signal(newAttempt());
  final DVSignal<bool> busy = context.signal(false);
  final DVSignal<Reply<Outcome>?> result = context.signal<Reply<Outcome>?>(null);
  Future<Reply<Catalog>> fetch() => bundleCatalog(fromJson: Reply.of(Catalog.fromJson));
  loadInto(catalog, fetch);

  final Reply<Catalog>? reply = catalog.value;
  if (reply == null) return const Screen(<Widget>[PageTitle('Buy data'), Loading(label: 'Loading bundles')]);
  if (!reply.ok) {
    return Screen(<Widget>[const PageTitle('Buy data'), Refusal(reply.message, onRetry: () => reload(catalog, fetch))]);
  }

  Future<void> buy() async {
    final Bundle? bundle = chosen.read();
    if (bundle == null) return;
    busy.value = true;
    result.value = await ask(() => buyBundle(
          bundleId: bundle.id,
          forNumber: who.read() == 'Me' ? '' : number.read(),
          attempt: attempt.read(),
          fromJson: Reply.of(Outcome.fromJson),
        ));
    busy.value = false;
    if (result.read()?.ok ?? false) {
      chosen.value = null;
      attempt.value = newAttempt();
    }
  }

  final Bundle? picked = chosen.value;
  final Reply<Outcome>? done = result.value;
  final String recipient = who.value == 'Me' ? 'your line' : (number.value.trim().isEmpty ? 'another number' : number.value.trim());
  return Screen(<Widget>[
    const PageTitle('Buy data', subtitle: 'Paid from your airtime. Bundles are used before pay-as-you-go data.'),
    Panel(<Widget>[
      const SectionTitle('Who is it for?'),
      Choices(const <String>['Me', 'Someone else'], selected: who.value, what: 'recipient', onSelected: (String v) {
        who.value = v;
        result.value = null;
      }),
      if (who.value != 'Me')
        Field('Their RTN number', hint: '0999 000 0002', value: number.read(), onChanged: (String v) => number.value = v),
    ]),
    Choices(bundlePeriods, selected: period.value, what: 'period', onSelected: (String v) => period.value = v),
    if (done != null) done.ok
        ? Notice('Done. ${dataSize(done.result.balance.dataBytes)} of data on your line now, '
            '${naira(done.result.balance.airtime)} airtime left.', tone: 'good')
        : Notice(done.message),
    if (picked != null)
      Panel(<Widget>[
        const SectionTitle('Confirm'),
        DVText('Buy ${picked.name} for ${recipient == 'your line' ? recipient : localNumber(internationalNumber(recipient) ?? recipient)}: '
            '${nairaShort(picked.price)}, valid ${validity(picked.validityDays)}.'),
        DVBox.wrap(<Widget>[
          ActionButton('Buy now', tooltip: 'Pay ${nairaShort(picked.price)} from airtime', busy: busy.value, onPressed: buy),
          ActionButton('Cancel', tooltip: 'Do not buy this bundle', primary: false, onPressed: () => chosen.value = null),
        ], spacing: 8),
      ], accent: true),
    DVBox.grid(<Widget>[
      for (final Bundle b in reply.result.bundles.where((Bundle b) => inBundlePeriod(b, period.value)))
        BundleCard(bundle: b, onChoose: () {
          chosen.value = b;
          result.value = null;
        }),
    ], columns: 2, spacing: 12),
  ]);
}

@DVFunctionalWidget()
Widget _bundleCard(BuildContext context, {required Bundle bundle, required VoidCallback onChoose}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  return Panel(<Widget>[
    DVBox.row(<Widget>[
      Expanded(child: DVText(bundle.name).modifier(const DVModifier().fontSize(17).fontWeight(FontWeight.w800))),
      if (bundle.offer != null) Tag(bundle.offer!, warm: true, tooltip: 'On offer: ${bundle.offer}'),
    ], spacing: 8, crossAlign: DVCrossAlign.center),
    DVText(dataSize(bundle.dataBytes)).modifier(const DVModifier().fontSize(24).fontWeight(FontWeight.w800).color(colors.primary)),
    DVText('${nairaShort(bundle.price)} · valid ${validity(bundle.validityDays)}')
        .modifier(const DVModifier().color(colors.onSurfaceVariant)),
    ActionButton('Buy', tooltip: 'Buy ${bundle.name} for ${nairaShort(bundle.price)}', onPressed: onChoose, icon: Icons.shopping_bag_outlined),
  ], spacing: 8);
}
