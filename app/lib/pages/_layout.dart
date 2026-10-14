import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/session.dart';

/// Every page: the brand, the self-service links, and the console link.
class const Layout({super.key, required super.child}) extends DartvelLayout {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SubscriberSession me = context.global<SubscriberSession>();
    final String path = GoRouterState.of(context).uri.path;
    Widget link(DVRouteTarget to, String label) {
      final bool here = to.path == '/' ? path == '/' : path.startsWith(to.path);
      return DVNavLink(
        to: to,
        child: Container(
          padding: const .symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: here ? theme.colorScheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: here ? .w700 : .w500,
              color: here ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
            ),
          ),
        ),
      );
    }

    return Material(
      color: theme.colorScheme.surface,
      child: DVBox.list(<Widget>[
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          padding: const .symmetric(horizontal: 16, vertical: 10),
          child: DVBox.list(<Widget>[
            Row(spacing: 12, children: <Widget>[
              DVNavLink(
                to: DVRoutes.index,
                child: DVBox.row(<Widget>[
                  Image.asset('assets/icon.png', width: 32, height: 32, semanticLabel: 'RTN'),
                  Text('RTN', style: theme.textTheme.titleLarge?.copyWith(fontWeight: .w800, letterSpacing: 1)),
                ], spacing: 8),
              ),
              const Spacer(),
              if (me.signedIn)
                Flexible(
                  child: Text(
                    me.name,
                    overflow: .ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ]),
            SingleChildScrollView(
              scrollDirection: .horizontal,
              child: DVBox.row(<Widget>[
                link(DVRoutes.index, 'My line'),
                link(DVRoutes.bundles, 'Bundles'),
                link(DVRoutes.transfer, 'Transfer'),
                link(DVRoutes.borrow, 'Borrow'),
                link(DVRoutes.messages, 'Messages'),
                link(DVRoutes.history, 'History'),
                link(DVRoutes.ussd, 'USSD'),
                const SizedBox(width: 12),
                link(DVRoutes.console, 'Console'),
              ], spacing: 4, crossAlign: .center),
            ),
          ], spacing: 8),
        ),
        Expanded(child: child),
      ]),
    );
  }
}
