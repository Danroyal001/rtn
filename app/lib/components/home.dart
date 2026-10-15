// The home screen: what is left on the line, what to do next.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/money.dart';
import '../services/remote.dart';
import '../services/wire.dart';
import '../styles/theme.dart';

@DVFunctionalWidget()
Widget _homeScreen(BuildContext context) {
  final DVSignal<Reply<Dashboard>?> dashboard = context.signal<Reply<Dashboard>?>(null);
  Future<Reply<Dashboard>> fetch() => home(fromJson: Reply.of(Dashboard.fromJson));
  loadInto(dashboard, fetch, every: const Duration(seconds: 5));
  final Reply<Dashboard>? reply = dashboard.value;
  if (reply == null) return const Screen(<Widget>[Loading(label: 'Loading your line')]);
  if (!reply.ok) {
    return Screen(<Widget>[const PageTitle('MyRTN'), Refusal(reply.message, onRetry: () => reload(dashboard, fetch))]);
  }
  final Dashboard d = reply.result;
  final Balance b = d.line.balance;
  final String first = d.line.subscriber.name.split(' ').first;
  return Screen(<Widget>[
    PageTitle(
      first.isEmpty ? 'Welcome' : 'Hello, $first',
      subtitle: '${localNumber(d.line.subscriber.msisdn)} · ${d.line.plan?.name ?? b.planId} plan',
    ),
    if (d.line.subscriber.barred) const Notice('This line is suspended. Chat to RTN care to have it restored.'),
    BalanceCard(balance: b),
    DataMeter(balance: b),
    const SectionTitle('Quick actions'),
    DVBox.masonry(
      <Widget>[
        const LinkTile(
          DVRoutes.mydata,
          'Buy data',
          icon: Icons.signal_cellular_alt,
          tooltip: 'Buy a data bundle',
          detail: 'For you or a gift',
        ),
        const LinkTile(
          DVRoutes.myrecharge,
          'Recharge',
          icon: Icons.bolt_outlined,
          tooltip: 'Recharge with a voucher or a card',
          detail: 'Voucher or card',
        ),
        const LinkTile(
          DVRoutes.mytransfer,
          'Send',
          icon: Icons.swap_horiz,
          tooltip: 'Send airtime or share data',
          detail: 'Airtime or data',
        ),
        LinkTile(
          DVRoutes.myborrow,
          'Borrow',
          icon: Icons.handshake_outlined,
          tooltip: 'Borrow airtime now, repay later',
          detail: 'Up to ${nairaShort(b.loanLimit)}',
        ),
        LinkTile(
          DVRoutes.myrewards,
          'Rewards',
          icon: Icons.card_giftcard,
          tooltip: 'Spend your loyalty points',
          detail: '${b.points} points',
        ),
        const LinkTile(
          DVRoutes.myussd,
          'Dial *123#',
          icon: Icons.dialpad,
          tooltip: 'Use RTN\'s USSD menus',
          detail: 'USSD dial pad',
        ),
        const LinkTile(
          DVRoutes.mysupport,
          'Support',
          icon: Icons.support_agent,
          tooltip: 'Chat to RTN care',
          detail: 'Chat to us',
        ),
        LinkTile(
          DVRoutes.mynotifications,
          'Alerts',
          icon: Icons.notifications_none,
          tooltip: 'Messages from RTN',
          detail: d.unread == 0 ? 'All read' : '${d.unread} unread',
        ),
      ],
      columns: 4,
      spacing: 8,
    ),
    if (d.offers.isNotEmpty) ...<Widget>[
      const SectionTitle('Offers for you'),
      DVBox.masonry(<Widget>[for (final Bundle offer in d.offers) OfferCard(bundle: offer)], columns: 2, spacing: 12),
    ],
    const SectionTitle('Recent activity'),
    Panel(<Widget>[
      if (d.recent.isEmpty) const Empty('Nothing yet.'),
      for (final LedgerEntry e in d.recent) EntryRow(entry: e),
      const TextLink(DVRoutes.myhistory, 'See all transactions', tooltip: 'Open your full history'),
    ], spacing: 4),
  ]);
}

/// Airtime, the loan and the points, in one card.
@DVFunctionalWidget()
Widget _balanceCard(BuildContext context, {required Balance balance}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  return DVBox.list(
    <Widget>[
      const DVText('Airtime').modifier(const DVModifier().color(Colors.white.withValues(alpha: 0.85))),
      DVText(naira(balance.airtime)).modifier(
        const DVModifier()
            .fontSize(36)
            .fontWeight(FontWeight.w800)
            .color(Colors.white)
            .tooltip('Airtime you can spend on calls, SMS and bundles'),
      ),
      DVBox.wrapLine(<Widget>[
        if (balance.reserved > 0)
          DVText('${naira(balance.reserved)} held for a call').modifier(const DVModifier().color(Colors.white)),
        DVText(balance.loan > 0 ? 'Loan to repay: ${naira(balance.loan)}' : 'No loan').modifier(
          const DVModifier()
              .color(Colors.white)
              .tooltip(
                balance.loan > 0
                    ? 'Repaid from your next recharge'
                    : 'You can borrow up to ${naira(balance.loanLimit)}',
              ),
        ),
        DVText('${balance.points} points')
            .modifier(const DVModifier().color(Colors.white).tooltip('Loyalty points: 1 for every ₦10 you spend')),
      ], spacing: 16),
    ],
    spacing: 4,
    modifier: const DVModifier()
        .padding(20)
        .rounded(20)
        .gradient(
          LinearGradient(
            colors: <Color>[RtnColors.teal, Color.lerp(RtnColors.teal, colors.secondary, 0.35)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
  );
}

/// How much data is left, as a meter, with each bundle under it.
@DVFunctionalWidget()
Widget _dataMeter(BuildContext context, {required Balance balance}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final int left = balance.dataBytes;
  final int biggest = balance.bundles.fold<int>(0, (int s, HeldBundle b) => s + b.bytesLeft);
  final double share = biggest == 0 ? 0 : left / biggest;
  return Panel(<Widget>[
    DVBox.row(
      <Widget>[
        SizedBox.square(
          dimension: 84,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              SizedBox.square(
                dimension: 84,
                child: CircularProgressIndicator(
                  value: left == 0 ? 0 : share.clamp(0.04, 1),
                  strokeWidth: 9,
                  backgroundColor: colors.surfaceContainerHighest,
                  semanticsLabel: 'Data left',
                  semanticsValue: dataSize(left),
                ),
              ),
              Icon(Icons.signal_cellular_alt, color: colors.primary),
            ],
          ),
        ),
        Expanded(
          child: DVBox.list(<Widget>[
            const DVText('Data').modifier(const DVModifier().color(colors.onSurfaceVariant)),
            DVText(dataSize(left)).modifier(const DVModifier().fontSize(28).fontWeight(FontWeight.w800)),
            DVText(
              left == 0
                  ? 'No bundle. Data is charged from airtime.'
                  : 'Left across ${balance.bundles.length} bundle${balance.bundles.length == 1 ? '' : 's'}',
            ).modifier(const DVModifier().color(colors.onSurfaceVariant).fontSize(13)),
          ], spacing: 2),
        ),
      ],
      spacing: 16,
      crossAlign: DVCrossAlign.center,
    ),
    for (final HeldBundle b in balance.bundles)
      DVBox.row(
        <Widget>[
          Expanded(child: DVText(b.name).modifier(const DVModifier().fontWeight(FontWeight.w600))),
          DVText(dataSize(b.bytesLeft)).modifier(const DVModifier().fontWeight(FontWeight.w700)),
          Tag('until ${shortTime(b.expiresAt)}', tooltip: 'This bundle expires on ${shortTime(b.expiresAt)}'),
        ],
        spacing: 8,
        crossAlign: DVCrossAlign.center,
      ),
  ]);
}

/// A bundle on offer, with a link to buy it.
@DVFunctionalWidget()
Widget _offerCard(BuildContext context, {required Bundle bundle}) => DVNavLink(
  to: DVRoutes.mydata,
  semanticLabel: '${bundle.name}, ${nairaShort(bundle.price)}, ${bundle.offer ?? ''}',
  child: DVBox(
    Panel(
      <Widget>[
        Tag(bundle.offer ?? 'Offer', warm: true),
        DVText(bundle.name).modifier(const DVModifier().fontSize(17).fontWeight(FontWeight.w800)),
        DVText('${nairaShort(bundle.price)} · ${validity(bundle.validityDays)}'),
      ],
      spacing: 6,
      accent: true,
    ),
    const DVModifier().tooltip('See ${bundle.name} on the Data page'),
  ),
);

/// One transaction in a list, linking to its receipt.
@DVFunctionalWidget()
Widget _entryRow(BuildContext context, {required LedgerEntry entry}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  final int money = entry.airtimeDelta;
  final String amount = money != 0
      ? '${money > 0 ? '+' : ''}${naira(money)}'
      : entry.dataDelta != 0
      ? '${entry.dataDelta > 0 ? '+' : '−'}${dataSize(entry.dataDelta.abs())}'
      : entry.pointsDelta != 0
      ? '${entry.pointsDelta} pts'
      : '';
  final Color ink = money > 0 || (money == 0 && entry.dataDelta > 0)
      ? (dark ? RtnColors.goodLight : RtnColors.good)
      : colors.onSurface;
  return DVNavLink(
    to: DVRoutes.myhistorySeq(seq: '${entry.seq}'),
    semanticLabel: '${entryTitle(entry.kind)}, $amount, ${shortTime(entry.at)}',
    child:
        DVBox.row(
          <Widget>[
            Expanded(
              child: DVBox.list(<Widget>[
                DVText(entryTitle(entry.kind)).modifier(const DVModifier().fontWeight(FontWeight.w700)),
                DVText('${entry.note} · ${shortTime(entry.at)}')
                    .modifier(const DVModifier().fontSize(12).color(colors.onSurfaceVariant)),
              ], spacing: 2),
            ),
            DVText(amount).modifier(const DVModifier().fontWeight(FontWeight.w800).color(ink)),
          ],
          spacing: 12,
          crossAlign: DVCrossAlign.center,
        ).modifier(
          const DVModifier()
              .paddingSymmetric(vertical: 8)
              .tooltip('Open the receipt for this ${entryTitle(entry.kind).toLowerCase()}'),
        ),
  );
}
