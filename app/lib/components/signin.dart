// Signing in: a number, then the code the SMS centre sent to it.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/account.dart';
import '../services/money.dart';
import '../services/remote.dart';
import '../services/wire.dart';

@DVFunctionalWidget()
Widget _signInScreen(BuildContext context) {
  final DVSignal<String> number = context.signal('');
  final DVSignal<String> code = context.signal('');
  final DVSignal<CodeSent?> sent = context.signal<CodeSent?>(null);
  final DVSignal<bool> busy = context.signal(false);
  final DVSignal<String> problem = context.signal('');
  final ColorScheme colors = Theme.of(context).colorScheme;

  Future<void> sendCode() async {
    problem.value = '';
    if (internationalNumber(number.read()) == null) {
      problem.value = 'Enter your RTN number, like 0999 000 0001.';
      return;
    }
    busy.value = true;
    final Reply<CodeSent> reply =
        await ask(() => sendSignInCode(msisdn: number.read(), fromJson: Reply.of(CodeSent.fromJson)));
    busy.value = false;
    if (reply.ok) {
      sent.value = reply.result;
    } else {
      problem.value = reply.message;
    }
  }

  Future<void> verify() async {
    final CodeSent? waiting = sent.read();
    if (waiting == null) return;
    problem.value = '';
    busy.value = true;
    final Reply<SignedIn> who = await signInWithCode(waiting.msisdn, code.read().trim());
    busy.value = false;
    if (who.ok) {
      DV.Navigation.navigate(DVRoutes.my);
    } else {
      problem.value = who.message;
    }
  }

  final CodeSent? waiting = sent.value;
  return Screen(<Widget>[
    const SizedBox(height: 12),
    Center(child: DVBox.image(DVAsset.icon, alt: 'RTN logo', width: 72, height: 72)),
    const PageTitle('Sign in to MyRTN', subtitle: 'Your balance, data, recharges and more, for your RTN line.'),
    Panel(<Widget>[
      if (waiting == null) ...<Widget>[
        Field(
          'Your RTN number',
          hint: '0999 000 0001',
          helper: 'We will send a 6-digit code to this number by SMS.',
          value: number.read(),
          onChanged: (String v) => number.value = v,
          onSubmitted: sendCode,
        ),
        ActionButton('Send me a code',
            tooltip: 'Send a sign-in code by SMS to this number', busy: busy.value, onPressed: sendCode),
      ] else ...<Widget>[
        DVText('We sent a code to ${localNumber(waiting.msisdn)}. It works for 5 minutes.')
            .modifier(const DVModifier().color(colors.onSurfaceVariant)),
        if (waiting.demoCode.isNotEmpty)
          Notice('Demo network: the SMS says your code is ${waiting.demoCode}.', tone: 'info'),
        Field(
          'Sign-in code',
          hint: '6 digits',
          value: code.read(),
          onChanged: (String v) => code.value = v,
          onSubmitted: verify,
        ),
        ActionButton('Sign in', tooltip: 'Check the code and sign in', busy: busy.value, onPressed: verify),
        DVBox.wrap(<Widget>[
          ActionButton('Use another number',
              tooltip: 'Go back and type a different number', primary: false, onPressed: () {
            sent.value = null;
            code.value = '';
            problem.value = '';
          }),
          ActionButton('Send a new code',
              tooltip: 'Send another code to the same number', primary: false, onPressed: sendCode),
        ], spacing: 8),
      ],
      if (problem.value.isNotEmpty) Notice(problem.value),
    ]),
    const DVText('Signing in uses your number only: no password. RTN will never ask you for your code.')
        .modifier(const DVModifier().fontSize(13).color(colors.onSurfaceVariant)),
  ], maxWidth: 460);
}
