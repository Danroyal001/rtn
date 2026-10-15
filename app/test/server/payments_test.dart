import 'package:flutter_test/flutter_test.dart';
import 'package:rtn_app/server/payments.dart';

void main() {
  const CardDetails good = CardDetails(number: '4242 4242 4242 4242', expiry: '12/30', cvv: '123', name: 'Ada Okafor');
  final DateTime now = DateTime(2026, 10, 15);

  test('a good card is approved, once per key', () {
    final MockPay pay = MockPay();
    final Payment first = pay.charge(good, 50000, key: 'k1', now: now);
    expect(first.approved, isTrue);
    expect(first.last4, '4242');
    expect(first.reference, startsWith('mp_'));
    final Payment again = pay.charge(good, 50000, key: 'k1', now: now);
    expect(again.reference, first.reference);
    expect(pay.charges, 1);
  });

  test('the test cards decline the way their numbers say', () {
    final MockPay pay = MockPay();
    final Payment declined = pay.charge(
      good.copyWith(number: '4000 0000 0000 0002'),
      50000,
      key: 'k2',
      now: now,
    );
    expect(declined.approved, isFalse);
    expect(declined.reason, contains('declined'));
    final Payment broke = pay.charge(
      good.copyWith(number: '4000000000009995'),
      50000,
      key: 'k3',
      now: now,
    );
    expect(broke.reason, contains('funds'));
  });

  test('card details are checked before anything is charged', () {
    final MockPay pay = MockPay();
    expect(
      pay
          .charge(
            good.copyWith(number: '4242 4242 4242 4241'),
            50000,
            key: 'a',
            now: now,
          )
          .reason,
      contains('card number'),
    );
    expect(
      pay
          .charge(
            good.copyWith(expiry: '01/20'),
            50000,
            key: 'b',
            now: now,
          )
          .reason,
      contains('expired'),
    );
    expect(
      pay
          .charge(
            good.copyWith(expiry: '13/30'),
            50000,
            key: 'c',
            now: now,
          )
          .reason,
      contains('expiry'),
    );
    expect(
      pay
          .charge(
            good.copyWith(cvv: '12'),
            50000,
            key: 'd',
            now: now,
          )
          .reason,
      contains('security code'),
    );
    expect(pay.charge(good, 1000, key: 'e', now: now).reason, contains('₦50'));
    expect(pay.charge(good, 20000000, key: 'f', now: now).reason, contains('₦100,000'));
    expect(pay.charges, 0);
  });
}
