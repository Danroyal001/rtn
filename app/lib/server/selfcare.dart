// What MyRTN's backend functions do for a signed-in subscriber. Each backend
// function is one line that names the signed-in number and calls one of these;
// keeping the work here makes it testable against a real core without a
// server in the way.
//
// Every number the subscriber did not choose comes from their session, never
// from the request: a page cannot act on somebody else's line.
import 'dart:io';

import '../services/money.dart';
import '../services/wire.dart';
import 'core.dart';
import 'payments.dart';

final class SelfCare {
  SelfCare(this.core, {required this.pay, this.demo = false});

  final Core core;
  final MockPay pay;

  /// On a demo server the sign-in code is shown on the page, since nobody
  /// holds the handset it was sent to.
  final bool demo;

  static SelfCare? _shared;

  /// The service for this server process.
  static SelfCare get shared =>
      _shared ??= SelfCare(Core.shared, pay: MockPay(), demo: Platform.environment['RTN_DEMO'] == '1');

  /// The id a charge is recorded under: the page's own id for this attempt,
  /// scoped to the line, so a retry is recognised and two lines never clash.
  static String requestId(String msisdn, String given) {
    final String trimmed = given.trim();
    final String id = trimmed.isEmpty || trimmed.length > 64
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : trimmed;
    return 'app:$msisdn:$id';
  }

  static Reply<T> _bad<T>(String code, String message) => Reply<T>.refused(code, message);

  static Reply<T>? _number<T>(String typed, void Function(String) use) {
    final String? number = internationalNumber(typed);
    if (number == null) return _bad('invalid_msisdn', 'That is not a phone number.');
    use(number);
    return null;
  }

  /// The beneficiary of an action: [typed] when given, else the line itself.
  static String? _target(String msisdn, String typed) => typed.trim().isEmpty ? msisdn : internationalNumber(typed);

  // ----- signing in ----------------------------------------------------------------------

  Future<Reply<CodeSent>> sendCode(String typed) async {
    final String? msisdn = internationalNumber(typed);
    if (msisdn == null) return _bad('invalid_msisdn', 'That is not a phone number.');
    final Reply<CodeSent> sent = await core.requestOtp(msisdn);
    if (!sent.ok || !demo) return sent;
    // The code went out by SMS. On a demo, read it back from the SMS centre.
    await core.deliverSms();
    final Reply<Inbox> log = await core.smsLog(50);
    final String code = log.ok
        ? log.result.messages
                  .where((SmsMessage m) => m.to == msisdn && m.from == serviceNumber && m.text.contains('sign-in code'))
                  .map((SmsMessage m) => m.text.substring(0, 6))
                  .firstOrNull ??
              ''
        : '';
    return Reply<CodeSent>.ok(CodeSent(msisdn: msisdn, expiresAt: sent.result.expiresAt, demoCode: code));
  }

  Future<Reply<SignedIn>> verifyCode(String typed, String code) async {
    final String? msisdn = internationalNumber(typed);
    if (msisdn == null) return _bad('invalid_msisdn', 'That is not a phone number.');
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) return _bad('wrong_code', 'The code is the 6 digits we sent you.');
    final Reply<Done> checked = await core.verifyOtp(msisdn, code.trim());
    if (!checked.ok) return Reply<SignedIn>.refused(checked.code, checked.message);
    final Reply<Subscriber> who = await core.subscriber(msisdn);
    return Reply<SignedIn>.ok(SignedIn(userId: msisdn, name: who.ok ? who.result.name : '', role: 'subscriber'));
  }

  /// "50 subscribers", or why the network cannot be read.
  Future<Reply<Done>> status() async {
    final Reply<SubscriberPage> page = await core.subscriberPage('', 0, 1);
    if (!page.ok) return Reply<Done>.refused(page.code, page.message);
    return Reply<Done>.ok(Done(message: '${page.result.total} subscribers'));
  }

  // ----- reading the line ----------------------------------------------------------------

  Future<Reply<Line>> line(String msisdn) => core.line(msisdn);

  Future<Reply<Dashboard>> dashboard(String msisdn) async {
    final Reply<Line> line = await core.line(msisdn);
    if (!line.ok) return Reply<Dashboard>.refused(line.code, line.message);
    final Reply<Inbox> notes = await core.notifications(msisdn);
    final Reply<LedgerPage> recent = await core.history(msisdn, 4);
    final Reply<Catalog> catalog = await core.catalog();
    return Reply<Dashboard>.ok(
      Dashboard(
        line: line.result,
        unread: notes.ok ? notes.result.unread : 0,
        recent: recent.ok ? recent.result.entries : const <LedgerEntry>[],
        offers: catalog.ok ? catalog.result.bundles.where((Bundle b) => b.offer != null).toList() : const <Bundle>[],
      ),
    );
  }

  Future<Reply<Catalog>> catalog() => core.catalog();

  Future<Reply<LedgerPage>> history(String msisdn, int limit) => core.history(msisdn, limit.clamp(1, 200));

  /// One ledger entry, if it is on this line.
  Future<Reply<LedgerEntry>> receipt(String msisdn, int seq) async {
    final Reply<LedgerEntry> entry = await core.ledgerEntry(seq);
    if (!entry.ok) return _bad('not_found', 'There is no such transaction.');
    if (entry.result.msisdn != msisdn) return _bad('not_yours', 'That transaction is not on your line.');
    return entry;
  }

  Future<Reply<Loyalty>> loyalty(String msisdn) async {
    final Reply<Line> line = await core.line(msisdn);
    if (!line.ok) return Reply<Loyalty>.refused(line.code, line.message);
    final Reply<Catalog> catalog = await core.catalog();
    return Reply<Loyalty>.ok(
      Loyalty(points: line.result.balance.points, rewards: catalog.ok ? catalog.result.rewards : const <Reward>[]),
    );
  }

  Future<Reply<Inbox>> notifications(String msisdn) async {
    final Reply<Inbox> notes = await core.notifications(msisdn);
    if (!notes.ok) return notes;
    return Reply<Inbox>.ok(Inbox(messages: notes.result.messages.reversed.toList()));
  }

  Future<Reply<Done>> markRead(String msisdn, List<String> ids) => core.markRead(msisdn, ids.take(500).toList());

  Future<Reply<Messages>> messages(String msisdn) async {
    final Reply<Inbox> inbox = await core.inbox(msisdn);
    final Reply<Inbox> outbox = await core.outbox(msisdn);
    if (!inbox.ok) return Reply<Messages>.refused(inbox.code, inbox.message);
    return Reply<Messages>.ok(
      Messages(
        inbox: inbox.result.messages
            .where((SmsMessage m) => m.from != serviceNumber)
            .toList()
            .reversed
            .take(50)
            .toList(),
        sent: outbox.ok ? outbox.result.messages.reversed.take(50).toList() : const <SmsMessage>[],
      ),
    );
  }

  // ----- buying and moving money ---------------------------------------------------------

  Future<Reply<Outcome>> buyBundle(String msisdn, String bundleId, String forNumber, String attempt) async {
    final String? target = _target(msisdn, forNumber);
    if (target == null) return _bad('invalid_msisdn', 'That is not a phone number.');
    return core.apply(requestId(msisdn, attempt), <String, Object?>{
      'type': 'buy_bundle',
      'msisdn': msisdn,
      'bundle_id': bundleId,
      'beneficiary': target == msisdn ? null : target,
    });
  }

  Future<Reply<Outcome>> rechargeVoucher(String msisdn, String pin, String forNumber, String attempt) async {
    final String? target = _target(msisdn, forNumber);
    if (target == null) return _bad('invalid_msisdn', 'That is not a phone number.');
    return core.apply(requestId(msisdn, attempt), <String, Object?>{
      'type': 'redeem_voucher',
      'msisdn': target,
      'pin': pin,
    });
  }

  Future<Reply<Outcome>> rechargeCard(
    String msisdn,
    String forNumber,
    String amountTyped,
    CardDetails card,
    String attempt,
  ) async {
    final String? target = _target(msisdn, forNumber);
    if (target == null) return _bad('invalid_msisdn', 'That is not a phone number.');
    final int? amount = parseNaira(amountTyped);
    if (amount == null || amount == 0) return _bad('invalid_amount', 'Enter an amount in naira, like 500.');
    final Reply<Subscriber> exists = await core.subscriber(target);
    if (!exists.ok) return Reply<Outcome>.refused(exists.code, exists.message);
    final String id = requestId(msisdn, attempt);
    final Payment payment = pay.charge(card, amount, key: id, now: DateTime.now());
    if (!payment.approved) {
      return _bad(payment.reference.isEmpty ? 'card_invalid' : 'card_declined', payment.reason);
    }
    final Reply<Outcome> topped = await core.apply(id, <String, Object?>{
      'type': 'top_up',
      'msisdn': target,
      'amount': amount,
      'via': payment.channel,
    });
    if (!topped.ok) return topped;
    final Outcome o = topped.result;
    return Reply<Outcome>.ok(
      Outcome(
        requestId: o.requestId,
        charged: amount,
        balance: o.balance,
        detail: OutcomeDetail(type: 'card', amount: amount, repaid: o.detail.repaid, to: target),
        reference: payment.reference,
      ),
    );
  }

  Future<Reply<Outcome>> transfer(String msisdn, String to, String amountTyped, String pin, String attempt) async {
    String? number;
    final Reply<Outcome>? bad = _number(to, (String n) => number = n);
    if (bad != null) return bad;
    final int? amount = parseNaira(amountTyped);
    if (amount == null || amount == 0) return _bad('invalid_amount', 'Enter an amount in naira, like 500.');
    final Reply<Done> pinOk = await core.verifyPin(msisdn, pin);
    if (!pinOk.ok) return Reply<Outcome>.refused(pinOk.code, pinOk.message);
    return core.apply(requestId(msisdn, attempt), <String, Object?>{
      'type': 'transfer',
      'from': msisdn,
      'to': number,
      'amount': amount,
    });
  }

  Future<Reply<Outcome>> shareData(String msisdn, String to, String megabytesTyped, String pin, String attempt) async {
    String? number;
    final Reply<Outcome>? bad = _number(to, (String n) => number = n);
    if (bad != null) return bad;
    final int? bytes = megabytes(megabytesTyped);
    if (bytes == null) return _bad('invalid_amount', 'Enter whole megabytes, like 500.');
    final Reply<Done> pinOk = await core.verifyPin(msisdn, pin);
    if (!pinOk.ok) return Reply<Outcome>.refused(pinOk.code, pinOk.message);
    return core.apply(requestId(msisdn, attempt), <String, Object?>{
      'type': 'share_data',
      'from': msisdn,
      'to': number,
      'bytes': bytes,
    });
  }

  Future<Reply<Outcome>> borrow(String msisdn, String amountTyped, String attempt) async {
    final int? amount = parseNaira(amountTyped);
    if (amount == null || amount == 0) return _bad('invalid_amount', 'Choose how much to borrow.');
    return core.apply(requestId(msisdn, attempt), <String, Object?>{
      'type': 'borrow',
      'msisdn': msisdn,
      'amount': amount,
    });
  }

  Future<Reply<Outcome>> redeem(String msisdn, String rewardId, String attempt) => core.apply(
    requestId(msisdn, attempt),
    <String, Object?>{'type': 'redeem_points', 'msisdn': msisdn, 'reward_id': rewardId},
  );

  Future<Reply<Outcome>> sendSms(String msisdn, String to, String text, String attempt) async {
    String? number;
    final Reply<Outcome>? bad = _number(to, (String n) => number = n);
    if (bad != null) return bad;
    return core.apply(requestId(msisdn, attempt), <String, Object?>{
      'type': 'sms_submit',
      'from': msisdn,
      'to': number,
      'text': text,
    });
  }

  // ----- care and USSD -------------------------------------------------------------------

  Future<Reply<CareChat>> care(String msisdn) => core.careThread(msisdn);

  Future<Reply<CareChat>> careSend(String msisdn, String text) => core.careSend(msisdn, text);

  Future<Reply<UssdReply>> ussd(String msisdn, String session, String input) {
    final String id = session.trim().isEmpty ? 'web' : session.trim();
    return core.ussd('app:$msisdn:$id', msisdn, input);
  }

  // ----- the line itself -----------------------------------------------------------------

  Future<Reply<Done>> rename(String msisdn, String name) => core.setName(msisdn, name);

  Future<Reply<Done>> changePin(String msisdn, String old, String fresh) => core.changePin(msisdn, old, fresh);

  Future<Reply<Line>> swapSim(String msisdn, String pin) async {
    final Reply<Subscriber> swapped = await core.swapSim(msisdn, pin);
    if (!swapped.ok) return Reply<Line>.refused(swapped.code, swapped.message);
    return core.line(msisdn);
  }

  Future<Reply<Done>> suspend(String msisdn, String pin) => core.suspendLine(msisdn, pin);

  Future<Reply<Done>> setPlan(String msisdn, String planId) => core.setPlan(msisdn, planId);

  /// Switches the simulated handset on or off. Off, the SMS centre holds
  /// messages until it is back.
  Future<Reply<Done>> setHandset(String msisdn, bool on) => core.setAttached(msisdn, on);
}
