// The backend's services against the real RTN core, loaded in-process through
// the C ABI (milestone 2). Build it first: `cargo build --release` in core/.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtn_app/server/console.dart';
import 'package:rtn_app/server/core.dart';
import 'package:rtn_app/server/payments.dart';
import 'package:rtn_app/server/selfcare.dart';
import 'package:rtn_app/services/money.dart';
import 'package:rtn_app/services/wire.dart';

const String ada = '2349990000001';
const String bola = '2349990000002';

String get library =>
    Platform.environment['RTN_CORE_LIB'] ?? '${Directory.current.path}/../core/target/release/librtn_ffi.so';

void main() {
  late Directory dir;
  late Core core;
  late SelfCare care;
  late Console console;
  int clock = 1800000000000;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rtn-app-test');
    core = Core(FfiCoreLink.open(library, dir.path), clock: () => clock);
    care = SelfCare(core, pay: MockPay(), demo: true);
    console = Console(core, password: 'operator-pass');
    expect((await core.seed(5)).ok, isTrue);
  });

  tearDown(() {
    core.close();
    dir.deleteSync(recursive: true);
  });

  test('sign in with a code the SMS centre delivered', () async {
    final Reply<CodeSent> sent = await care.sendCode('0999 000 0001');
    expect(sent.ok, isTrue, reason: sent.message);
    expect(sent.result.msisdn, ada);
    expect(sent.result.demoCode, hasLength(6));
    final Reply<SignedIn> wrong = await care.verifyCode(ada, sent.result.demoCode == '000000' ? '111111' : '000000');
    expect(wrong.code, 'wrong_code');
    final Reply<SignedIn> who = await care.verifyCode(ada, sent.result.demoCode);
    expect(who.ok, isTrue);
    expect(who.result.role, 'subscriber');
    final Reply<CodeSent> unknown = await care.sendCode('0999 999 9999');
    expect(unknown.code, 'unknown_subscriber');
    final Reply<CodeSent> garbage = await care.sendCode('hello');
    expect(garbage.code, 'invalid_msisdn');
  });

  test('the status says how many lines the network has', () async {
    final Reply<Done> status = await care.status();
    expect(status.result.message, '5 subscribers');
  });

  test('the home screen has the line, offers and recent activity', () async {
    final Reply<Dashboard> home = await care.dashboard(ada);
    expect(home.ok, isTrue, reason: home.message);
    expect(home.result.line.subscriber.msisdn, ada);
    expect(home.result.line.balance.airtime, greaterThan(0));
    expect(home.result.offers, isNotEmpty);
    expect(home.result.recent, isNotEmpty);
  });

  test('buying data for yourself and as a gift, with a retry charged once', () async {
    final Reply<Outcome> mine = await care.buyBundle(ada, 'daily-100mb', '', 'r1');
    expect(mine.ok, isTrue, reason: mine.message);
    final Reply<Outcome> retry = await care.buyBundle(ada, 'daily-100mb', '', 'r1');
    expect(retry.result.balance.airtime, mine.result.balance.airtime);
    final Reply<Outcome> gift = await care.buyBundle(ada, 'weekly-1gb', '0999 000 0002', 'r2');
    expect(gift.ok, isTrue, reason: gift.message);
    expect(gift.result.detail.beneficiary, bola);
    final Reply<Outcome> nope = await care.buyBundle(ada, 'no-such-bundle', '', 'r3');
    expect(nope.code, 'unknown_bundle');
    expect(nope.message, endsWith('.'));
  });

  test('recharge with a voucher and with a card', () async {
    final Reply<VoucherBook> printed = await console.issueVouchers('2', '200');
    expect(printed.ok, isTrue, reason: printed.message);
    final String pin = printed.result.printed.first.pin;
    final Reply<Outcome> voucher = await care.rechargeVoucher(ada, pin, '', 'v1');
    expect(voucher.ok, isTrue, reason: voucher.message);
    expect(voucher.result.detail.amount, 20000);
    final Reply<Outcome> used = await care.rechargeVoucher(bola, pin, '', 'v2');
    expect(used.code, 'voucher_used');

    const CardDetails card = CardDetails(number: '4242424242424242', expiry: '12/30', cvv: '123');
    final Reply<Outcome> paid = await care.rechargeCard(ada, '', '1,000', card, 'c1');
    expect(paid.ok, isTrue, reason: paid.message);
    expect(paid.result.reference, startsWith('mp_'));
    final Reply<LedgerPage> history = await care.history(ada, 5);
    expect(history.result.entries.first.note, contains('card •••• 4242'));
    final Reply<Outcome> declined = await care.rechargeCard(
      ada,
      '',
      '1,000',
      card.copyWith(number: '4000000000000002'),
      'c2',
    );
    expect(declined.code, 'card_declined');
    final Reply<Outcome> badAmount = await care.rechargeCard(ada, '', 'lots', card, 'c3');
    expect(badAmount.code, 'invalid_amount');
  });

  test('transfers and data sharing need the PIN', () async {
    final Reply<Outcome> wrongPin = await care.transfer(ada, '0999 000 0002', '100', '9999', 't1');
    expect(wrongPin.code, 'wrong_pin');
    final Reply<Outcome> sent = await care.transfer(ada, '0999 000 0002', '100', '1234', 't2');
    expect(sent.ok, isTrue, reason: sent.message);
    expect(sent.result.detail.fee, 1000);
    await care.buyBundle(ada, 'weekly-1gb', '', 'b1');
    final Reply<Outcome> shared = await care.shareData(ada, '0999 000 0002', '100', '1234', 's1');
    expect(shared.ok, isTrue, reason: shared.message);
    expect(shared.result.detail.bytes, 100 * mb);
    // Switching the handset on delivers what the SMS centre holds for it.
    await care.setHandset(bola, true);
    final Reply<Inbox> notes = await care.notifications(bola);
    expect(notes.result.messages.where((SmsMessage m) => m.text.contains('received')), isNotEmpty);
    expect(notes.result.unread, greaterThan(0));
    await care.markRead(bola, notes.result.messages.map((SmsMessage m) => m.id).toList());
    expect((await care.notifications(bola)).result.unread, 0);
  });

  test('a receipt is only readable by its owner', () async {
    final Reply<LedgerPage> history = await care.history(ada, 10);
    final LedgerEntry first = history.result.entries.last;
    expect((await care.receipt(ada, first.seq)).ok, isTrue);
    expect((await care.receipt(bola, first.seq)).code, 'not_yours');
  });

  test('borrow, points, support and USSD', () async {
    final Reply<Outcome> loan = await care.borrow(ada, '100', 'l1');
    expect(loan.ok, isTrue, reason: loan.message);
    expect(loan.result.detail.owed, 11000);
    final Reply<Loyalty> loyalty = await care.loyalty(ada);
    expect(loyalty.result.rewards, isNotEmpty);
    final Reply<CareChat> chat = await care.careSend(ada, 'what is my balance?');
    expect(chat.result.messages.last.author, 'assistant');
    final Reply<UssdReply> menu = await care.ussd(ada, 'u1', '*123#');
    expect(menu.result.end, isFalse);
    expect(menu.result.text, contains('Balance'));
  });

  test('line management', () async {
    expect((await care.rename(ada, 'Ada Lovelace')).ok, isTrue);
    expect((await care.changePin(ada, '1234', '4321')).ok, isTrue);
    expect((await care.changePin(ada, '1234', '5555')).code, 'wrong_pin');
    final Reply<Line> swapped = await care.swapSim(ada, '4321');
    expect(swapped.ok, isTrue, reason: swapped.message);
    expect((await care.setHandset(ada, false)).ok, isTrue);
    expect((await care.line(ada)).result.subscriber.attached, isFalse);
    expect((await care.suspend(ada, '4321')).ok, isTrue);
    expect((await care.line(ada)).result.subscriber.barred, isTrue);
  });

  test('the console signs in with its password and runs the network', () async {
    expect(console.passwordMatches('operator-pass'), isTrue);
    expect(console.passwordMatches('nope'), isFalse);
    expect(Console(core, password: '').passwordMatches(''), isFalse, reason: 'no password, no console');
    final Reply<SubscriberPage> page = await console.subscribers('', 0);
    expect(page.result.total, 5);
    final Reply<Subscriber> added = await console.addSubscriber('0999 123 4567', 'New Person', '4321', '');
    expect(added.ok, isTrue, reason: added.message);
    expect((await console.topUp('2349991234567', '50', 'ct1')).ok, isTrue);
    expect((await console.setStatus('2349991234567', 'barred')).ok, isTrue);
    final Reply<SubscriberFile> file = await console.subscriber('2349991234567');
    expect(file.result.line.balance.airtime, 5000);
    expect(file.result.line.subscriber.barred, isTrue);
    expect((await console.setSimulator(true)).ok, isTrue);
    clock += 5000;
    await core.tick();
    final Reply<Traffic> traffic = await console.traffic();
    expect(traffic.result.simulating, isTrue);
    expect(traffic.result.series, hasLength(60));
  });

  test('the network survives the backend restarting', () async {
    await care.buyBundle(ada, 'weekly-1gb', '', 'kept');
    core.close();
    core = Core(FfiCoreLink.open(library, dir.path), clock: () => clock);
    care = SelfCare(core, pay: MockPay());
    final Reply<LedgerPage> history = await care.history(ada, 3);
    expect(history.result.entries.any((LedgerEntry e) => e.requestId.endsWith(':kept')), isTrue);
  });

  test('a call made while the network is being seeded waits for it', () async {
    final Directory fresh = Directory.systemTemp.createTempSync('rtn-app-start');
    final Core starting = Core(FfiCoreLink.open(library, fresh.path), clock: () => clock);
    starting.startUp(seed: 7);
    // No await between starting up and asking: the first visitor after a restart.
    final Reply<Line> line = await SelfCare(starting, pay: MockPay()).line('2349990000007');
    expect(line.ok, isTrue, reason: line.message);
    starting.close();
    fresh.deleteSync(recursive: true);
  });

  test('a core that cannot be reached is a refusal, not a crash', () async {
    final Core gone = Core(HttpCoreLink(Uri.parse('http://127.0.0.1:1'), token: 'x'));
    final Reply<Line> line = await SelfCare(gone, pay: MockPay()).line(ada);
    expect(line.code, 'core_unreachable');
  });
}
