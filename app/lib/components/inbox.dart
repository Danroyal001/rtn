// Rewards, notifications, support chat and SMS.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../services/money.dart';
import '../services/remote.dart';
import '../services/wire.dart';

@DVFunctionalWidget()
Widget _rewardsScreen(BuildContext context) {
  final DVSignal<Reply<Loyalty>?> points = context.signal<Reply<Loyalty>?>(null);
  final DVSignal<String> busyId = context.signal('');
  final DVSignal<Reply<Outcome>?> result = context.signal<Reply<Outcome>?>(null);
  Future<Reply<Loyalty>> fetch() => loyalty(fromJson: Reply.of(Loyalty.fromJson));
  loadInto(points, fetch);
  final Reply<Loyalty>? reply = points.value;
  if (reply == null) return const Screen(<Widget>[PageTitle('Rewards'), Loading(label: 'Loading your points')]);
  if (!reply.ok) {
    return Screen(<Widget>[const PageTitle('Rewards'), Refusal(reply.message, onRetry: () => reload(points, fetch))]);
  }
  final Loyalty l = reply.result;
  final ColorScheme colors = Theme.of(context).colorScheme;

  Future<void> redeem(Reward r) async {
    busyId.value = r.id;
    result.value = await ask(
      () => redeemPoints(rewardId: r.id, attempt: newAttempt(), fromJson: Reply.of(Outcome.fromJson)),
    );
    busyId.value = '';
    await reload(points, fetch);
  }

  final Reply<Outcome>? done = result.value;
  return Screen(<Widget>[
    const PageTitle('Rewards', subtitle: 'One point for every ₦10 you recharge or spend on bundles.'),
    Panel(<Widget>[
      Stat('Your points', '${l.points}', tooltip: 'Points you can spend now', ink: colors.primary),
    ], accent: true),
    if (done != null)
      done.ok
          ? Notice('Enjoy your ${dataSize(done.result.detail.dataBytes)} of bonus data.', tone: 'good')
          : Notice(done.message),
    const SectionTitle('Spend your points'),
    for (final Reward r in l.rewards)
      Panel(<Widget>[
        DVBox.row(
          <Widget>[
            Expanded(
              child: DVBox.list(<Widget>[
                DVText(r.name).modifier(const DVModifier().fontSize(17).fontWeight(FontWeight.w800)),
                DVText('${dataSize(r.dataBytes)}, valid ${validity(r.validityDays)}')
                    .modifier(const DVModifier().color(colors.onSurfaceVariant)),
              ], spacing: 2),
            ),
            Tag('${r.points} pts', tooltip: '${r.name} costs ${r.points} points'),
          ],
          spacing: 12,
          crossAlign: DVCrossAlign.center,
        ),
        ActionButton(
          l.points >= r.points ? 'Redeem' : 'Need ${r.points - l.points} more points',
          tooltip: l.points >= r.points ? 'Spend ${r.points} points on ${r.name}' : 'You do not have enough points yet',
          busy: busyId.value == r.id,
          onPressed: l.points >= r.points ? () => redeem(r) : null,
        ),
      ], spacing: 8),
  ]);
}

@DVFunctionalWidget()
Widget _notificationsScreen(BuildContext context) {
  final DVSignal<Reply<Inbox>?> inbox = context.signal<Reply<Inbox>?>(null);
  Future<Reply<Inbox>> fetch() => notifications(fromJson: Reply.of(Inbox.fromJson));
  loadInto(inbox, fetch, every: const Duration(seconds: 5));
  final Reply<Inbox>? reply = inbox.value;
  if (reply == null) return const Screen(<Widget>[PageTitle('Notifications'), Loading()]);
  if (!reply.ok) {
    return Screen(<Widget>[
      const PageTitle('Notifications'),
      Refusal(reply.message, onRetry: () => reload(inbox, fetch)),
    ]);
  }
  final List<SmsMessage> messages = reply.result.messages;
  final ColorScheme colors = Theme.of(context).colorScheme;

  Future<void> markAll() async {
    await ask(
      () => markRead(
        ids: messages.where((SmsMessage m) => !m.read).map((SmsMessage m) => m.id).join(','),
        fromJson: Reply.of(Done.fromJson),
      ),
    );
    await reload(inbox, fetch);
  }

  return Screen(<Widget>[
    const PageTitle('Notifications', subtitle: 'What RTN has told you: receipts, gifts, codes and alerts.'),
    if (reply.result.unread > 0)
      ActionButton(
        'Mark all ${reply.result.unread} as read',
        tooltip: 'Mark every notification as read',
        primary: false,
        onPressed: markAll,
      ),
    Panel(<Widget>[
      if (messages.isEmpty) const Empty('No notifications yet.'),
      for (final SmsMessage m in messages)
        DVBox.row(
          <Widget>[
            Icon(
              m.read ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
              color: m.read ? colors.onSurfaceVariant : colors.primary,
              semanticLabel: m.read ? 'Read' : 'Unread',
            ),
            Expanded(
              child: DVBox.list(<Widget>[
                DVText(m.text).modifier(const DVModifier().fontWeight(m.read ? FontWeight.w500 : FontWeight.w700)),
                DVText(shortTime(m.submittedAt))
                    .modifier(const DVModifier().fontSize(12).color(colors.onSurfaceVariant)),
              ], spacing: 2),
            ),
          ],
          spacing: 12,
          crossAlign: DVCrossAlign.start,
        ).modifier(const DVModifier().paddingSymmetric(vertical: 8)),
    ], spacing: 2),
  ]);
}

@DVFunctionalWidget()
Widget _supportScreen(BuildContext context) {
  final DVSignal<Reply<CareChat>?> chat = context.signal<Reply<CareChat>?>(null);
  final DVSignal<String> draft = context.signal('');
  final DVSignal<bool> busy = context.signal(false);
  Future<Reply<CareChat>> fetch() => careChat(fromJson: Reply.of(CareChat.fromJson));
  loadInto(chat, fetch, every: const Duration(seconds: 4));
  final Reply<CareChat>? reply = chat.value;

  Future<void> send() async {
    if (draft.read().trim().isEmpty) return;
    busy.value = true;
    final Reply<CareChat> answer = await ask(() => careSend(text: draft.read(), fromJson: Reply.of(CareChat.fromJson)));
    busy.value = false;
    chat.value = answer;
    if (answer.ok) draft.value = '';
  }

  return Screen(<Widget>[
    const PageTitle('Support', subtitle: 'Chat to RTN care. Our assistant answers at once; ask for an agent any time.'),
    if (reply == null)
      const Loading(label: 'Loading the conversation')
    else if (!reply.ok)
      Refusal(reply.message, onRetry: () => reload(chat, fetch))
    else
      Panel(<Widget>[
        if (reply.result.messages.isEmpty)
          const Empty('Ask about your balance, data, borrowing, recharges, your PIN or a lost SIM.'),
        for (final CareMessage m in reply.result.messages) ChatBubble(message: m),
      ]),
    Panel(<Widget>[
      // Keyed by the conversation's length, so a sent message clears the field.
      KeyedSubtree(
        key: ValueKey<int>(reply?.value?.messages.length ?? 0),
        child: Field(
          'Your message',
          hint: 'Type here',
          value: draft.read(),
          onChanged: (String v) => draft.value = v,
          onSubmitted: send,
        ),
      ),
      ActionButton(
        'Send',
        tooltip: 'Send this message to RTN care',
        busy: busy.value,
        onPressed: send,
        icon: Icons.send,
      ),
    ]),
  ]);
}

@DVFunctionalWidget()
Widget _chatBubble(BuildContext context, {required CareMessage message, bool operator = false}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  // Whose side of the conversation this message is on depends on who reads it.
  final bool mine = operator ? message.author == 'agent' : message.author == 'subscriber';
  final String who = switch (message.author) {
    'assistant' => 'RTN assistant',
    'agent' => operator ? 'You (agent)' : 'RTN care agent',
    _ => operator ? 'Subscriber' : 'You',
  };
  return Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: DVBox.list(
        <Widget>[
          DVText(who).modifier(
            const DVModifier().fontSize(12).fontWeight(FontWeight.w700).color(mine ? colors.onPrimary : colors.primary),
          ),
          DVText(message.text).modifier(const DVModifier().color(mine ? colors.onPrimary : colors.onSurface)),
          DVText(shortTime(message.at)).modifier(
            const DVModifier()
                .fontSize(11)
                .color((mine ? colors.onPrimary : colors.onSurfaceVariant).withValues(alpha: 0.8)),
          ),
        ],
        spacing: 4,
        modifier: const DVModifier()
            .padding(12)
            .rounded(16)
            .backgroundColor(mine ? colors.primary : colors.surfaceContainerHighest)
            .semanticLabel('$who said: ${message.text}'),
      ),
    ),
  );
}

@DVFunctionalWidget()
Widget _messagesScreen(BuildContext context) {
  final DVSignal<Reply<Messages>?> sms = context.signal<Reply<Messages>?>(null);
  final DVSignal<String> to = context.signal('');
  final DVSignal<String> text = context.signal('');
  final DVSignal<bool> busy = context.signal(false);
  final DVSignal<Reply<Outcome>?> result = context.signal<Reply<Outcome>?>(null);
  Future<Reply<Messages>> fetch() => messages(fromJson: Reply.of(Messages.fromJson));
  loadInto(sms, fetch, every: const Duration(seconds: 5));
  final Reply<Messages>? reply = sms.value;
  final ColorScheme colors = Theme.of(context).colorScheme;
  final int length = text.value.length;
  final int parts = length <= 160 ? 1 : (length / 153).ceil();

  Future<void> send() async {
    busy.value = true;
    result.value = await ask(
      () => sendSms(to: to.read(), text: text.read(), attempt: newAttempt(), fromJson: Reply.of(Outcome.fromJson)),
    );
    busy.value = false;
    await reload(sms, fetch);
  }

  Widget list(String title, List<SmsMessage> items, bool sent) => Panel(<Widget>[
    SectionTitle(title),
    if (items.isEmpty) const Empty('None yet.'),
    for (final SmsMessage m in items)
      DVBox.list(
        <Widget>[
          DVText(sent ? 'To ${localNumber(m.to)}' : 'From ${localNumber(m.from)}')
              .modifier(const DVModifier().fontWeight(FontWeight.w700)),
          DVText(m.text),
          DVText('${shortTime(m.submittedAt)}${sent ? ' · ${m.state}' : ''}').modifier(
            const DVModifier()
                .fontSize(12)
                .color(colors.onSurfaceVariant)
                .tooltip(
                  sent && m.state == 'queued' ? 'Held at the SMS centre until their phone is on' : 'When it was sent',
                ),
          ),
        ],
        spacing: 2,
        modifier: const DVModifier().paddingSymmetric(vertical: 6),
      ),
  ], spacing: 4);

  return Screen(<Widget>[
    const PageTitle(
      'Messages',
      subtitle: 'SMS on your line. A message waits at the SMS centre while the other phone is off.',
    ),
    Panel(<Widget>[
      Field('To', hint: '0999 000 0002', value: to.read(), onChanged: (String v) => to.value = v),
      Field('Message', multiline: true, value: text.read(), onChanged: (String v) => text.value = v),
      DVText('$length characters, $parts part${parts == 1 ? '' : 's'}')
          .modifier(const DVModifier().fontSize(12).color(colors.onSurfaceVariant)),
      ActionButton(
        'Send SMS',
        tooltip: 'Send this SMS; each part is charged',
        busy: busy.value,
        onPressed: send,
        icon: Icons.sms_outlined,
      ),
      if (result.value case final Reply<Outcome> done)
        done.ok ? const Notice('Sent to the SMS centre.', tone: 'good') : Notice(done.message),
    ]),
    if (reply == null)
      const Loading()
    else if (!reply.ok)
      Refusal(reply.message, onRetry: () => reload(sms, fetch))
    else ...<Widget>[list('Received', reply.result.inbox, false), list('Sent', reply.result.sent, true)],
  ]);
}
