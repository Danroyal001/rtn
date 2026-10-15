// MockPay: a card payment provider that behaves like a real one and moves no
// money. It checks a card the way a gateway does (Luhn, expiry, security
// code, limits), declines the published test numbers the way they say, and
// answers a retried request with the first answer.
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../services/money.dart';

/// Smallest and largest card recharge.
const int cardMinimum = 5000;
const int cardMaximum = 10000000;

class const CardDetails({
  required final String number,
  required final String expiry,
  required final String cvv,
  final String name = '',
}) {
  String get digits => number.replaceAll(RegExp(r'[\s-]'), '');

  CardDetails copyWith({String? number, String? expiry, String? cvv}) =>
      CardDetails(number: number ?? this.number, expiry: expiry ?? this.expiry, cvv: cvv ?? this.cvv, name: name);
}

class const Payment({
  required final bool approved,
  final String reference = '',
  final String last4 = '',
  final String reason = '',
}) {
  /// How the ledger names where the money came from.
  String get channel => 'card •••• $last4';
}

/// Card numbers that decline, and why.
const Map<String, String> _declines = <String, String>{
  '4000000000000002': 'The card was declined by the bank.',
  '4000000000009995': 'The card has insufficient funds.',
  '4000000000000069': 'The card has expired.',
};

bool _luhn(String digits) {
  int sum = 0;
  bool double = false;
  for (int i = digits.length - 1; i >= 0; i--) {
    int d = digits.codeUnitAt(i) - 48;
    if (double) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    double = !double;
  }
  return sum % 10 == 0;
}

final class MockPay {
  final Map<String, Payment> _byKey = <String, Payment>{};

  /// Charges that were approved, for tests.
  int charges = 0;

  /// Charges [amount] minor units to [card]. [key] identifies the attempt: the
  /// same key is answered with the same payment and never charged twice.
  Payment charge(CardDetails card, int amount, {required String key, required DateTime now}) {
    final Payment? seen = _byKey[key];
    if (seen != null) return seen;
    final String? problem = _problem(card, amount, now);
    if (problem != null) return Payment(approved: false, reason: problem);
    final String digits = card.digits;
    final String last4 = digits.substring(digits.length - 4);
    final String reference = 'mp_${sha256.convert(utf8.encode('mockpay:$key')).toString().substring(0, 20)}';
    final String? decline = _declines[digits];
    final Payment payment = decline == null
        ? Payment(approved: true, reference: reference, last4: last4)
        : Payment(approved: false, reference: reference, last4: last4, reason: decline);
    _byKey[key] = payment;
    if (payment.approved) charges++;
    return payment;
  }

  String? _problem(CardDetails card, int amount, DateTime now) {
    final String digits = card.digits;
    if (!RegExp(r'^\d{13,19}$').hasMatch(digits) || !_luhn(digits)) return 'Check the card number.';
    final RegExpMatch? expiry = RegExp(r'^\s*(\d{2})\s*/\s*(\d{2})\s*$').firstMatch(card.expiry);
    if (expiry == null) return 'Write the expiry as MM/YY.';
    final int month = int.parse(expiry.group(1)!);
    final int year = 2000 + int.parse(expiry.group(2)!);
    if (month < 1 || month > 12) return 'Write the expiry as MM/YY.';
    if (DateTime(year, month + 1).isBefore(now) || DateTime(year, month + 1) == now) return 'The card has expired.';
    if (!RegExp(r'^\d{3,4}$').hasMatch(card.cvv.trim())) return 'The security code is the 3 digits on the back.';
    if (amount < cardMinimum) return 'The smallest card recharge is ${nairaShort(cardMinimum)}.';
    if (amount > cardMaximum) return 'The largest card recharge is ${nairaShort(cardMaximum)}.';
    return null;
  }
}
