// The public front page: what MyRTN is, and the way in.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../styles/theme.dart';

@DVFunctionalWidget()
Widget _welcomeScreen(BuildContext context) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final DVSession? session = DV.Session.watch(context);
  final bool signedIn = '${session?.claims['role'] ?? ''}' == 'subscriber';
  return Screen(<Widget>[
    DVBox.list(<Widget>[
      DVBox.image(DVAsset.icon, alt: 'RTN logo', width: 88, height: 88),
      const DVText('Your RTN line, in one place.')
          .modifier(const DVModifier().fontSize(34).fontWeight(FontWeight.w800).semanticHeading(1)),
      const DVText('Check your airtime and data, buy bundles, recharge, send airtime, borrow, '
              'collect rewards and chat to RTN care. Sign in with your number; we text you a code.')
          .modifier(const DVModifier().fontSize(17).color(colors.onSurfaceVariant)),
      DVBox.wrap(<Widget>[
        DVNavLink(
          to: signedIn ? DVRoutes.my : DVRoutes.signin,
          semanticLabel: signedIn ? 'Open MyRTN' : 'Sign in to MyRTN',
          child: DVText(signedIn ? 'Open MyRTN' : 'Sign in').modifier(const DVModifier()
              .paddingSymmetric(horizontal: 22, vertical: 13)
              .rounded(12)
              .backgroundColor(colors.primary)
              .color(colors.onPrimary)
              .fontWeight(FontWeight.w800)
              .tooltip(signedIn ? 'Go to your home screen' : 'Sign in with your RTN number')),
        ),
        const TextLink(DVRoutes.operator, 'Operator console', tooltip: 'Sign in to the RTN operator console'),
      ], spacing: 16),
    ], spacing: 14, modifier: const DVModifier().paddingOnly(top: 24, bottom: 8)),
    const DVBox.grid(<Widget>[
      Feature(icon: Icons.data_usage, title: 'Balance and data meter', text: 'Airtime, every bundle and when it expires, live.'),
      Feature(icon: Icons.signal_cellular_alt, title: 'Data bundles', text: 'Daily to monthly, for you or as a gift.'),
      Feature(icon: Icons.bolt_outlined, title: 'Recharge', text: 'A voucher PIN or a card, for any RTN number.'),
      Feature(icon: Icons.swap_horiz, title: 'Send airtime and data', text: 'To any RTN line, confirmed with your PIN.'),
      Feature(icon: Icons.handshake_outlined, title: 'Borrow', text: 'Airtime now, repaid from your next recharge.'),
      Feature(icon: Icons.card_giftcard, title: 'Rewards', text: 'A point for every ₦10, spent on bonus data.'),
      Feature(icon: Icons.receipt_long_outlined, title: 'History and receipts', text: 'Every transaction, with a receipt for each.'),
      Feature(icon: Icons.support_agent, title: 'Support', text: 'An assistant at once, an agent when you ask.'),
    ], columns: 4, spacing: 12),
    const Panel(<Widget>[
      SectionTitle('No data? Dial a code', hint: 'From any RTN line, on any phone.'),
      DVBox.wrap(<Widget>[
        Tag('*123#', tooltip: 'The main menu'),
        Tag('*123*1#', tooltip: 'Your balance'),
        Tag('*312#', tooltip: 'Data bundles'),
        Tag('*303#', tooltip: 'Borrow airtime'),
        Tag('*555*PIN#', tooltip: 'Recharge from a voucher'),
      ], spacing: 8),
    ]),
    const DVText('RTN is an independent, open-source demo network. It is not affiliated with any mobile operator, '
            'and its numbers (0999…) are in a range set aside for testing.')
        .modifier(const DVModifier().fontSize(12).color(colors.onSurfaceVariant)),
  ], maxWidth: 1000);
}

@DVFunctionalWidget()
Widget _feature(BuildContext context, {required IconData icon, required String title, required String text}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  return Panel(<Widget>[
    Icon(icon, color: RtnColors.rust, size: 28),
    DVText(title).modifier(const DVModifier().fontWeight(FontWeight.w800).semanticHeading(2)),
    DVText(text).modifier(const DVModifier().color(colors.onSurfaceVariant)),
  ], spacing: 6);
}
