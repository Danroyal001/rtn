// A phone's dial pad for RTN's USSD services. Every key is a button with a
// name, and the keyboard works too.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/remote.dart';
import '../services/wire.dart';
import '../styles/theme.dart';

const List<String> dialKeys = <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
const List<String> ussdCodes = <String>['*123#', '*123*1#', '*312#', '*303#', '*321*number*amount*PIN#', '*555*PIN#'];

@DVFunctionalWidget()
Widget _ussdScreen(BuildContext context) {
  final DVSignal<String> typed = context.signal('');
  final DVSignal<String> session = context.signal('');
  final DVSignal<UssdReply?> screen = context.signal<UssdReply?>(null);
  final DVSignal<String> problem = context.signal('');
  final DVSignal<bool> busy = context.signal(false);
  final ColorScheme colors = Theme.of(context).colorScheme;

  Future<void> send() async {
    final String input = typed.read().trim();
    if (input.isEmpty) return;
    String id = session.read();
    if (id.isEmpty) {
      id = newAttempt();
      session.value = id;
    }
    busy.value = true;
    final Reply<UssdReply> reply = await ask(
      () => dialUssd(session: id, input: input, fromJson: Reply.of(UssdReply.fromJson)),
    );
    busy.value = false;
    typed.value = '';
    if (!reply.ok) {
      problem.value = reply.message;
      session.value = '';
      return;
    }
    problem.value = '';
    screen.value = reply.result;
    if (reply.result.end) session.value = '';
  }

  void hangUp() {
    session.value = '';
    screen.value = null;
    typed.value = '';
  }

  final UssdReply? shown = screen.value;
  final bool waiting = session.value.isNotEmpty;
  return Screen(<Widget>[
    const PageTitle('USSD', subtitle: 'RTN\'s menus as your phone shows them. Dial *123# to start.'),
    DVBox.list(
      <Widget>[
        DVText(shown == null ? 'Ready' : (shown.end ? 'Session ended' : 'Reply to continue'))
            .modifier(const DVModifier().fontSize(12).color(RtnColors.tealLight)),
        DVText(shown?.text ?? 'Dial a code, like *123#.')
            .modifier(const DVModifier().color(Colors.white).fontFamily('monospace').fontSize(15).lineHeight(1.4)),
      ],
      spacing: 6,
      modifier: const DVModifier().padding(16).rounded(16).backgroundColor(RtnColors.night).minHeight(150),
    ),
    if (problem.value.isNotEmpty) Notice(problem.value),
    Field(
      waiting ? 'Your reply' : 'Number or code to dial',
      hint: waiting ? 'Type the option' : '*123#',
      value: typed.read(),
      onChanged: (String v) => typed.value = v,
      onSubmitted: send,
    ),
    DVText(typed.value.isEmpty ? ' ' : typed.value)
        .modifier(const DVModifier().fontSize(28).fontWeight(FontWeight.w700).align(Alignment.center)),
    DVBox.masonry(
      <Widget>[
        for (final String key in dialKeys)
          DVText(key).modifier(
            const DVModifier()
                .fontSize(24)
                .fontWeight(FontWeight.w700)
                .align(Alignment.center)
                .paddingSymmetric(vertical: 14)
                .rounded(999)
                .backgroundColor(colors.surfaceContainerHighest)
                .tooltip('Press $key')
                .onTap(() => typed.value = '${typed.read()}$key'),
          ),
      ],
      columns: 3,
      spacing: 10,
      responsive: false,
    ),
    DVBox.row(<Widget>[
      Expanded(
        child: ActionButton(
          waiting ? 'Send' : 'Call',
          tooltip: waiting ? 'send this reply' : 'dial this code',
          busy: busy.value,
          onPressed: send,
        ),
      ),
      Expanded(
        child: ActionButton(
          'Delete',
          tooltip: 'delete the last digit',
          primary: false,
          onPressed: () => typed.value = typed.read().isEmpty ? '' : typed.read().substring(0, typed.read().length - 1),
        ),
      ),
      Expanded(
        child: ActionButton('End', tooltip: 'end the session', danger: true, onPressed: hangUp),
      ),
    ], spacing: 8),
    const SectionTitle('Codes'),
    DVBox.wrapLine(<Widget>[
      for (final String code in ussdCodes)
        Tag(
          code,
          tooltip: switch (code) {
            '*123#' => 'The main menu',
            '*123*1#' => 'Your balance',
            '*312#' => 'Data bundles',
            '*303#' => 'Borrow airtime',
            '*555*PIN#' => 'Recharge from a voucher PIN',
            _ => 'Send airtime in one step',
          },
        ),
    ], spacing: 8),
  ], maxWidth: 420);
}
