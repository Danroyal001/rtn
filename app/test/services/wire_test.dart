import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtn_app/services/wire.dart';

/// What the backend sends is what the app reads back.
T roundTrip<T>(Object value, T Function(Object?) read) => read(jsonDecode(jsonEncode(value)));

void main() {
  const Balance balance = Balance(
    msisdn: '2349990000001',
    airtime: 123450,
    available: 123450,
    dataBytes: 1048576,
    bundles: <HeldBundle>[HeldBundle(bundleId: 'daily-100mb', name: 'Daily 100MB', bytesLeft: 1048576, expiresAt: 9)],
    points: 12,
  );

  test('a dashboard survives the trip from backend to page', () {
    const Dashboard home = Dashboard(
      line: Line(
        subscriber: Subscriber(msisdn: '2349990000001', name: 'Ada'),
        plan: Plan(id: 'pulse', name: 'Pulse'),
        balance: balance,
      ),
      unread: 2,
      recent: <LedgerEntry>[LedgerEntry(seq: 7, kind: 'top_up', airtimeDelta: 5000, note: 'Top-up')],
      offers: <Bundle>[Bundle(id: 'monthly-10gb', name: 'Monthly 10GB', offer: 'Best value')],
    );
    final Reply<Dashboard> back = roundTrip(const Reply<Dashboard>.ok(home), Reply.of(Dashboard.fromJson));
    expect(back.ok, isTrue);
    expect(back.result.line.subscriber.name, 'Ada');
    expect(back.result.line.plan?.name, 'Pulse');
    expect(back.result.line.balance.bundles.single.name, 'Daily 100MB');
    expect(back.result.line.balance.points, 12);
    expect(back.result.recent.single.seq, 7);
    expect(back.result.offers.single.offer, 'Best value');
    expect(back.result.unread, 2);
  });

  test('a refusal keeps its code and words', () {
    final Reply<Outcome> back = roundTrip(
      const Reply<Outcome>.refused('insufficient_funds', 'Not enough airtime.'),
      Reply.of(Outcome.fromJson),
    );
    expect(back.ok, isFalse);
    expect(back.code, 'insufficient_funds');
    expect(back.message, 'Not enough airtime.');
  });

  test('what is not a reply is a refusal, never an empty success', () {
    expect(Reply.decode('Unauthorized', Line.fromJson).code, 'signed_out');
    expect(Reply.decode('Not authorized (OperatorConsole.view)', Line.fromJson).code, 'forbidden');
    expect(Reply.decode('Internal Server Error', Line.fromJson).code, 'unexpected');
    expect(Reply.decode(null, Line.fromJson).ok, isFalse);
  });

  test("the core's own answers decode with the same types", () {
    final Catalog catalog = Catalog.fromJson(
      jsonDecode(
        '{"plans":{"pulse":{"id":"pulse","name":"Pulse","voice_per_second":20,"sms_per_segment":400,"data_per_mb":500}},'
        '"bundles":[{"id":"daily-100mb","name":"Daily 100MB","data_bytes":104857600,"price":10000,"validity_days":1}],'
        '"default_plan":"pulse","rewards":[{"id":"points-1gb","name":"Bonus 1GB","points":350,"data_bytes":1073741824,"validity_days":7}]}',
      ),
    );
    expect(catalog.plan('pulse')?.voicePerSecond, 20);
    expect(catalog.bundles.single.offer, isNull);
    expect(catalog.rewards.single.points, 350);
    final Voucher used = Voucher.fromJson(
      jsonDecode('{"serial":"RTN0000000001","amount":50000,"created_at":1,"used_by":"2349990000001","used_at":5}'),
    );
    expect(used.usedBy, '2349990000001');
    expect(used.usedAt, 5);
  });

  test('words from the network arrive with local numbers, its numbers stay whole', () {
    final HeldBundle gift = HeldBundle.fromJson(<String, Object?>{
      'bundle_id': 'shared',
      'name': 'Data from 2349990000005',
      'bytes_left': 1,
      'expires_at': 2,
    });
    expect(gift.name, 'Data from 0999 000 0005');
    final SmsMessage sms = SmsMessage.fromJson(<String, Object?>{
      'from': '2349990000005',
      'text': 'Call 2349990000005',
    });
    expect(sms.from, '2349990000005');
    expect(sms.text, 'Call 0999 000 0005');
  });
}
