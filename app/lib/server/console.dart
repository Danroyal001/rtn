// What the operator console's backend functions do. Every function that calls
// these is behind the OperatorConsole policy: only a session the console
// sign-in issued may run them.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../services/money.dart';
import '../services/wire.dart';
import 'core.dart';

final class Console {
  Console(this.core, {required this.password});

  final Core core;

  /// The console password, or empty when the console is closed.
  final String password;

  static Console? _shared;

  static Console get shared =>
      _shared ??= Console(Core.shared, password: Platform.environment['RTN_CONSOLE_PASSWORD'] ?? '');

  /// Whether [given] is the console password. With no password configured,
  /// nothing is: the console is closed rather than open to everyone.
  bool passwordMatches(String given) {
    if (password.isEmpty) return false;
    final List<int> a = sha256.convert(utf8.encode(given)).bytes;
    final List<int> b = sha256.convert(utf8.encode(password)).bytes;
    int difference = 0;
    for (int i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  static Reply<T> _bad<T>(String code, String message) => Reply<T>.refused(code, message);

  // ----- the network ---------------------------------------------------------------------

  Future<Reply<Traffic>> traffic() => core.traffic();

  Future<Reply<Done>> setSimulator(bool running) => core.setSimulator(running);

  Future<Reply<LedgerPage>> ledger(int limit) => core.ledger(limit.clamp(1, 500));

  Future<Reply<Inbox>> smsLog(int limit) => core.smsLog(limit.clamp(1, 500));

  // ----- subscribers ---------------------------------------------------------------------

  Future<Reply<SubscriberPage>> subscribers(String search, int offset) =>
      core.subscriberPage(search.trim(), offset < 0 ? 0 : offset, 25);

  Future<Reply<SubscriberFile>> subscriber(String typed) async {
    final String? msisdn = internationalNumber(typed);
    if (msisdn == null) return _bad('invalid_msisdn', 'That is not a phone number.');
    final Reply<Line> line = await core.line(msisdn);
    if (!line.ok) return Reply<SubscriberFile>.refused(line.code, line.message);
    final Reply<LedgerPage> history = await core.history(msisdn, 30);
    final Reply<Inbox> inbox = await core.inbox(msisdn);
    final Reply<Catalog> catalog = await core.catalog();
    return Reply<SubscriberFile>.ok(
      SubscriberFile(
        line: line.result,
        history: history.ok ? history.result.entries : const <LedgerEntry>[],
        inbox: inbox.ok ? inbox.result.messages.reversed.take(20).toList() : const <SmsMessage>[],
        plans: catalog.ok ? catalog.result.plans : const <Plan>[],
      ),
    );
  }

  Future<Reply<Subscriber>> addSubscriber(String typed, String name, String pin, String planId) async {
    final String? msisdn = internationalNumber(typed);
    if (msisdn == null) return _bad('invalid_msisdn', 'That is not a phone number.');
    return core.addSubscriber(msisdn, name.trim(), pin.trim(), planId.trim().isEmpty ? null : planId.trim());
  }

  Future<Reply<Done>> setStatus(String msisdn, String status) {
    if (status != 'active' && status != 'barred') {
      return Future<Reply<Done>>.value(_bad('invalid_request', 'A line is active or barred.'));
    }
    return core.setStatus(msisdn, status);
  }

  Future<Reply<Outcome>> topUp(String msisdn, String amountTyped, String attempt) async {
    final int? amount = parseNaira(amountTyped);
    if (amount == null || amount == 0) return _bad('invalid_amount', 'Enter an amount in naira, like 500.');
    final String id = 'console:${attempt.trim().isEmpty ? DateTime.now().microsecondsSinceEpoch : attempt.trim()}';
    return core.apply(id, <String, Object?>{'type': 'top_up', 'msisdn': msisdn, 'amount': amount, 'via': 'RTN care'});
  }

  Future<Reply<Done>> setPlan(String msisdn, String planId) => core.setPlan(msisdn, planId);

  Future<Reply<Done>> setLoanLimit(String msisdn, String amountTyped) {
    final int? amount = parseNaira(amountTyped);
    if (amount == null) {
      return Future<Reply<Done>>.value(_bad('invalid_amount', 'Enter an amount in naira, like 500.'));
    }
    return core.setLoanLimit(msisdn, amount);
  }

  Future<Reply<Done>> resetPin(String msisdn, String pin) => core.setPin(msisdn, pin.trim());

  // ----- catalogue -----------------------------------------------------------------------

  Future<Reply<Catalog>> catalog() => core.catalog();

  Future<Reply<Done>> savePlan(String id, String name, String voiceKobo, String smsKobo, String dataKobo) {
    final int? voice = int.tryParse(voiceKobo.trim());
    final int? sms = int.tryParse(smsKobo.trim());
    final int? data = int.tryParse(dataKobo.trim());
    if (voice == null || sms == null || data == null) {
      return Future<Reply<Done>>.value(_bad('invalid_amount', 'Rates are whole kobo, like 20.'));
    }
    return core.upsertPlan(
      Plan(id: id.trim(), name: name.trim(), voicePerSecond: voice, smsPerSegment: sms, dataPerMb: data),
    );
  }

  Future<Reply<Done>> saveBundle(
    String id,
    String name,
    String megabytesTyped,
    String priceTyped,
    String days,
    String offer,
  ) {
    final int? bytes = megabytes(megabytesTyped);
    final int? price = parseNaira(priceTyped);
    final int? validity = int.tryParse(days.trim());
    if (bytes == null || price == null || validity == null) {
      return Future<Reply<Done>>.value(
        _bad('invalid_amount', 'A bundle needs whole megabytes, a price in naira and a validity in days.'),
      );
    }
    return core.upsertBundle(
      Bundle(
        id: id.trim(),
        name: name.trim(),
        dataBytes: bytes,
        price: price,
        validityDays: validity,
        offer: offer.trim().isEmpty ? null : offer.trim(),
      ),
    );
  }

  // ----- vouchers ------------------------------------------------------------------------

  Future<Reply<VoucherBook>> vouchers() async {
    final Reply<List<Voucher>> list = await core.vouchers(200);
    if (!list.ok) return Reply<VoucherBook>.refused(list.code, list.message);
    return Reply<VoucherBook>.ok(VoucherBook(vouchers: list.result));
  }

  Future<Reply<VoucherBook>> issueVouchers(String countTyped, String amountTyped) async {
    final int? count = int.tryParse(countTyped.trim());
    final int? amount = parseNaira(amountTyped);
    if (count == null || count < 1 || count > 100) return _bad('invalid_amount', 'Print 1 to 100 vouchers at a time.');
    if (amount == null) return _bad('invalid_amount', 'Enter each voucher\'s value in naira, like 500.');
    final Reply<List<PrintedVoucher>> printed = await core.issueVouchers(count, amount);
    if (!printed.ok) return Reply<VoucherBook>.refused(printed.code, printed.message);
    final Reply<List<Voucher>> list = await core.vouchers(200);
    return Reply<VoucherBook>.ok(
      VoucherBook(vouchers: list.ok ? list.result : const <Voucher>[], printed: printed.result),
    );
  }

  // ----- care ----------------------------------------------------------------------------

  Future<Reply<CareDesk>> careDesk() => core.careThreads();

  Future<Reply<CareChat>> careThread(String msisdn) async {
    final Reply<CareChat> chat = await core.careThread(msisdn);
    if (!chat.ok) return chat;
    return Reply<CareChat>.ok(CareChat(msisdn: msisdn, messages: chat.result.messages));
  }

  Future<Reply<CareChat>> careReply(String msisdn, String text) async {
    final Reply<CareChat> chat = await core.careReply(msisdn, text);
    if (!chat.ok) return chat;
    return Reply<CareChat>.ok(CareChat(msisdn: msisdn, messages: chat.result.messages));
  }
}
