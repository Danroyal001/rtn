import 'package:flutter_test/flutter_test.dart';
import 'package:rtn_app/services/money.dart';

void main() {
  test('naira groups thousands and keeps kobo', () {
    expect(naira(0), '₦0.00');
    expect(naira(5), '₦0.05');
    expect(naira(123450), '₦1,234.50');
    expect(naira(100000000), '₦1,000,000.00');
    expect(naira(-2500), '−₦25.00');
  });

  test('typed naira becomes minor units, or null', () {
    expect(parseNaira('500'), 50000);
    expect(parseNaira('1,500.5'), 150050);
    expect(parseNaira('₦ 20'), 2000);
    expect(parseNaira('0.05'), 5);
    expect(parseNaira('1.234'), isNull);
    expect(parseNaira('abc'), isNull);
    expect(parseNaira(''), isNull);
  });

  test('data sizes read like a phone shows them', () {
    expect(dataSize(0), '0 MB');
    expect(dataSize(512 * 1024), '512 KB');
    expect(dataSize(100 * mb), '100 MB');
    expect(dataSize(1536 * mb), '1.5 GB');
    expect(dataSize(3 * 1024 * mb), '3 GB');
  });

  test('numbers are shown the local way and read in any common form', () {
    expect(localNumber('2349990000001'), '0999 000 0001');
    expect(localNumber('2349990000000'), 'RTN');
    expect(internationalNumber('0999 000 0001'), '2349990000001');
    expect(internationalNumber('+234 999 000 0001'), '2349990000001');
    expect(internationalNumber('234-999-000-0001'), '2349990000001');
    expect(internationalNumber('12'), isNull);
    expect(internationalNumber('0999abc'), isNull);
  });

  test('times and validity are short and readable', () {
    final DateTime at = DateTime(2026, 10, 14, 17, 5);
    expect(shortTime(at.millisecondsSinceEpoch), '14 Oct, 17:05');
    expect(validity(1), '1 day');
    expect(validity(30), '30 days');
    expect(megabytes('250'), 250 * mb);
    expect(megabytes('1.5'), isNull);
  });

  test('ledger kinds have words', () {
    expect(entryTitle('transfer_in'), 'Airtime received');
    expect(entryTitle('bundle_purchase'), 'Data bundle');
    expect(entryTitle('something_new'), 'Something new');
  });
}
