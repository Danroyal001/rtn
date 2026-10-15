// The frame around every screen: MyRTN's bar and navigation for subscribers,
// the console's for the operator, and nothing but the brand on sign-in.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/account.dart';
import '../styles/theme.dart';

typedef Destination = ({DVRouteTarget to, String label, IconData icon, String tooltip});

final List<Destination> subscriberNav = <Destination>[
  (to: DVRoutes.my, label: 'Home', icon: Icons.home_outlined, tooltip: 'Your balance and quick actions'),
  (to: DVRoutes.mydata, label: 'Data', icon: Icons.signal_cellular_alt, tooltip: 'Buy a data bundle'),
  (to: DVRoutes.myrecharge, label: 'Recharge', icon: Icons.bolt_outlined, tooltip: 'Recharge with a voucher or a card'),
  (to: DVRoutes.mytransfer, label: 'Send', icon: Icons.swap_horiz, tooltip: 'Send airtime or share data'),
  (to: DVRoutes.myhistory, label: 'History', icon: Icons.receipt_long_outlined, tooltip: 'Your transactions and receipts'),
  (to: DVRoutes.myaccount, label: 'Account', icon: Icons.person_outline, tooltip: 'Your line, SIM and PIN'),
];

final List<Destination> consoleNav = <Destination>[
  (to: DVRoutes.console, label: 'Live', icon: Icons.monitor_heart_outlined, tooltip: 'Live traffic across the network'),
  (to: DVRoutes.consolesubscribers, label: 'Subscribers', icon: Icons.groups_outlined, tooltip: 'Find and manage subscribers'),
  (to: DVRoutes.consolecatalog, label: 'Catalogue', icon: Icons.sell_outlined, tooltip: 'Rating plans and data bundles'),
  (to: DVRoutes.consolevouchers, label: 'Vouchers', icon: Icons.confirmation_number_outlined, tooltip: 'Print recharge vouchers'),
  (to: DVRoutes.consolecare, label: 'Care', icon: Icons.support_agent, tooltip: 'Answer subscribers'),
  (to: DVRoutes.consolesms, label: 'SMS', icon: Icons.sms_outlined, tooltip: 'The SMS centre'),
  (to: DVRoutes.consoleledger, label: 'Ledger', icon: Icons.account_balance_outlined, tooltip: 'Every balance change'),
];

bool isHere(String path, DVRouteTarget to) =>
    to.path == '/' || to.path == DVRoutes.console.path ? path == to.path : path == to.path || path.startsWith('${to.path}/');

/// The frame. [child] is the page.
@DVFunctionalWidget()
Widget _appFrame(BuildContext context, Widget child) {
  final String path = GoRouterState.of(context).uri.path;
  final bool console = path == DVRoutes.console.path || path.startsWith('${DVRoutes.console.path}/');
  // The public pages: the front page and the two ways to sign in.
  final bool signingIn =
      path == DVRoutes.index.path || path == DVRoutes.signin.path || path == DVRoutes.operator.path;
  final bool wide = MediaQuery.sizeOf(context).width >= 760;
  final ColorScheme colors = Theme.of(context).colorScheme;
  return Material(
    color: colors.surface,
    child: DVBox.list(<Widget>[
      TopBar(console: console, signingIn: signingIn, wide: wide, path: path),
      if (wide && !signingIn) NavStrip(console: console, path: path),
      Expanded(child: child),
      if (!wide && !signingIn) BottomNav(console: console, path: path),
    ], spacing: 0),
  );
}

/// The brand, and on the right what is always within reach.
@DVFunctionalWidget()
Widget _topBar(BuildContext context, {required bool console, required bool signingIn, required bool wide, required String path}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final Brightness showing = Theme.of(context).brightness;
  final ThemeChoice choice = context.global<ThemeChoice>();
  final DVSession? session = DV.Session.watch(context);
  final bool dark = showing == Brightness.dark;
  return DVBox.row(<Widget>[
    DVNavLink(
      to: console ? DVRoutes.console : (signingIn ? DVRoutes.index : DVRoutes.my),
      semanticLabel: console ? 'RTN console home' : 'MyRTN home',
      child: DVBox.row(<Widget>[
        DVBox.image(DVAsset.icon, alt: 'RTN logo', width: 32, height: 32),
        DVText(console ? 'RTN console' : 'MyRTN')
            .modifier(const DVModifier().fontSize(20).fontWeight(FontWeight.w800).letterSpacing(0.5)),
      ], spacing: 10, crossAlign: DVCrossAlign.center).modifier(
          const DVModifier().tooltip(console ? 'Back to the live view' : 'Back to your home screen')),
    ),
    // A Flexible child keeps this a row; a Spacer is not one, and in the
    // wrapping layout Dartvel uses for a row without one it cannot lay out.
    const Expanded(child: SizedBox.shrink()),
    if (!console && !signingIn && roleOf(session) == 'subscriber')
      DVNavLink(
        to: DVRoutes.mynotifications,
        semanticLabel: 'Notifications',
        child: DVBox(Icon(Icons.notifications_none, color: colors.onSurface),
            const DVModifier().padding(8).tooltip('Notifications from RTN')),
      ),
    DVBox(
      Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: colors.onSurface),
      const DVModifier()
          .padding(8)
          .rounded(999)
          .tooltip(dark ? 'Switch to light mode' : 'Switch to dark mode')
          .onTap(() => DV.global<ThemeChoice>(choice.next(showing))),
    ),
    if (!signingIn && session != null)
      DVBox(
        DVBox.row(<Widget>[
          Icon(Icons.logout, size: 18, color: colors.onSurface),
          if (wide) const DVText('Sign out'),
        ], spacing: 6, crossAlign: DVCrossAlign.center),
        const DVModifier()
            .paddingSymmetric(horizontal: 10, vertical: 8)
            .rounded(999)
            .tooltip('Sign out of ${console ? 'the console' : 'MyRTN'} on this device')
            .onTap(() async {
          await signOut();
          DV.Navigation.navigate(console ? DVRoutes.operator : DVRoutes.signin);
        }),
      ),
  ], spacing: 6, crossAlign: DVCrossAlign.center).modifier(const DVModifier()
      .paddingSymmetric(horizontal: 16, vertical: 10)
      .border(Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)))));
}

/// The tabs across the top on a wide screen.
@DVFunctionalWidget()
Widget _navStrip(BuildContext context, {required bool console, required String path}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  return DVBox.horizontalScrollable(<Widget>[
    for (final Destination d in console ? consoleNav : subscriberNav)
      DVNavLink(
        to: d.to,
        semanticLabel: isHere(path, d.to) ? '${d.label}, this page' : d.label,
        child: DVText(d.label).modifier(const DVModifier()
            .paddingSymmetric(horizontal: 14, vertical: 8)
            .rounded(999)
            .backgroundColor(isHere(path, d.to) ? colors.primaryContainer : Colors.transparent)
            .color(isHere(path, d.to) ? colors.onPrimaryContainer : colors.onSurface)
            .fontWeight(isHere(path, d.to) ? FontWeight.w800 : FontWeight.w600)
            .tooltip(d.tooltip)),
      ),
  ], spacing: 4, modifier: const DVModifier().paddingSymmetric(horizontal: 12, vertical: 6));
}

/// The tabs along the bottom on a phone.
@DVFunctionalWidget()
Widget _bottomNav(BuildContext context, {required bool console, required String path}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final List<Destination> nav = console ? consoleNav.take(5).toList() : subscriberNav.where((d) => d.label != 'Send').toList();
  return DVBox.row(<Widget>[
    for (final Destination d in nav)
      Expanded(
        child: DVNavLink(
          to: d.to,
          semanticLabel: isHere(path, d.to) ? '${d.label}, this page' : d.label,
          padding: EdgeInsets.zero,
          child: DVBox(
            DVBox.list(<Widget>[
              Icon(d.icon, color: isHere(path, d.to) ? colors.primary : colors.onSurfaceVariant),
              DVText(d.label).modifier(const DVModifier()
                  .fontSize(11)
                  .fontWeight(isHere(path, d.to) ? FontWeight.w800 : FontWeight.w600)
                  .color(isHere(path, d.to) ? colors.primary : colors.onSurfaceVariant)),
            ], spacing: 2, crossAlign: DVCrossAlign.center),
            const DVModifier().paddingSymmetric(vertical: 8).tooltip(d.tooltip),
          ),
        ),
      ),
  ], spacing: 0, modifier: const DVModifier()
      .backgroundColor(Theme.of(context).brightness == Brightness.dark ? RtnColors.night : Colors.white)
      .border(Border(top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)))));
}
