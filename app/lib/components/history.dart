// Every transaction on the line, and a receipt for each.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/money.dart';
import '../services/remote.dart';
import '../services/wire.dart';

const List<String> historyFilters = <String>['All', 'Money in', 'Money out', 'Data', 'Calls & SMS'];

bool matchesHistoryFilter(LedgerEntry e, String filter) => switch (filter) {
  'Money in' => e.airtimeDelta > 0,
  'Money out' => e.airtimeDelta < 0,
  'Data' => e.dataDelta != 0 || e.kind == 'data',
  'Calls & SMS' => e.kind == 'voice' || e.kind == 'sms',
  _ => true,
};

@DVFunctionalWidget()
Widget _historyScreen(BuildContext context) {
  final DVSignal<Reply<LedgerPage>?> page = context.signal<Reply<LedgerPage>?>(null);
  final DVSignal<String> filter = context.signal('All');
  Future<Reply<LedgerPage>> fetch() => history(limit: 100, fromJson: Reply.of(LedgerPage.fromJson));
  loadInto(page, fetch, every: const Duration(seconds: 10));
  final Reply<LedgerPage>? reply = page.value;
  if (reply == null) return const Screen(<Widget>[PageTitle('History'), Loading(label: 'Loading transactions')]);
  if (!reply.ok) {
    return Screen(<Widget>[const PageTitle('History'), Refusal(reply.message, onRetry: () => reload(page, fetch))]);
  }
  final List<LedgerEntry> shown = reply.result.entries
      .where((LedgerEntry e) => matchesHistoryFilter(e, filter.value))
      .toList();
  return Screen(<Widget>[
    const PageTitle('History', subtitle: 'Your last 100 transactions. Open one for its receipt.'),
    Choices(historyFilters, selected: filter.value, what: 'filter', onSelected: (String v) => filter.value = v),
    Panel(<Widget>[
      if (shown.isEmpty) const Empty('Nothing here yet.'),
      for (final LedgerEntry e in shown) EntryRow(entry: e),
    ], spacing: 2),
  ]);
}

@DVFunctionalWidget()
Widget _receiptScreen(BuildContext context, String seq) {
  final DVSignal<Reply<LedgerEntry>?> entry = context.signal<Reply<LedgerEntry>?>(null);
  final int number = int.tryParse(seq) ?? 0;
  Future<Reply<LedgerEntry>> fetch() => receipt(seq: number, fromJson: Reply.of(LedgerEntry.fromJson));
  loadInto(entry, fetch);
  final Reply<LedgerEntry>? reply = entry.value;
  if (reply == null) return const Screen(<Widget>[PageTitle('Receipt'), Loading(label: 'Loading the receipt')]);
  if (!reply.ok) {
    return Screen(<Widget>[
      const PageTitle('Receipt'),
      Notice(reply.message),
      const TextLink(DVRoutes.myhistory, 'Back to history', tooltip: 'Back to all transactions'),
    ]);
  }
  final LedgerEntry e = reply.result;
  final ColorScheme colors = Theme.of(context).colorScheme;
  Widget row(String label, String value) => DVBox.row(
    <Widget>[
      Expanded(child: DVText(label).modifier(const DVModifier().color(colors.onSurfaceVariant))),
      Flexible(child: DVText(value).modifier(const DVModifier().fontWeight(FontWeight.w700))),
    ],
    spacing: 12,
    crossAlign: DVCrossAlign.start,
  );
  return Screen(<Widget>[
    PageTitle(entryTitle(e.kind), subtitle: e.note),
    Panel(<Widget>[
      if (e.airtimeDelta != 0) row('Airtime', '${e.airtimeDelta > 0 ? '+' : ''}${naira(e.airtimeDelta)}'),
      if (e.dataDelta != 0) row('Data', '${e.dataDelta > 0 ? '+' : '−'}${dataSize(e.dataDelta.abs())}'),
      if (e.loanDelta != 0) row('Loan', '${e.loanDelta > 0 ? '+' : ''}${naira(e.loanDelta)}'),
      if (e.pointsDelta != 0) row('Points', '${e.pointsDelta > 0 ? '+' : ''}${e.pointsDelta}'),
      row('When', shortTime(e.at)),
      row('Line', localNumber(e.msisdn)),
      row('Airtime after', naira(e.airtimeAfter)),
      row('Data after', dataSize(e.dataAfter)),
      if (e.loanAfter > 0) row('Owed after', naira(e.loanAfter)),
      row('Transaction', '#${e.seq}'),
      row('Reference', e.requestId),
    ], spacing: 10),
    DVBox.wrapLine(<Widget>[
      ActionButton(
        'Copy reference',
        tooltip: 'Copy the reference to quote to RTN care',
        primary: false,
        icon: Icons.copy,
        onPressed: () => DV.Clipboard.copy('RTN #${e.seq} ${e.requestId}'),
      ),
      const TextLink(DVRoutes.myhistory, 'Back to history', tooltip: 'Back to all transactions'),
    ], spacing: 12),
  ]);
}
