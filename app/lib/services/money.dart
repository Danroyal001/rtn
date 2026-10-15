// How MyRTN writes and reads money, data, numbers and times. Pure Dart:
// the backend validates with the same rules the pages display with.

/// One megabyte, as bundles count it.
const int mb = 1048576;

/// RTN's own number, which its messages come from.
const String serviceNumber = '2349990000000';

/// "₦1,234.50" for 123450 minor units.
String naira(int units) {
  final String sign = units < 0 ? '−' : '';
  final int value = units.abs();
  final String whole = (value ~/ 100).toString();
  final StringBuffer grouped = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '$sign₦$grouped.${(value % 100).toString().padLeft(2, '0')}';
}

/// "₦500" when there are no kobo, else [naira].
String nairaShort(int units) => units % 100 == 0 ? naira(units).replaceFirst('.00', '') : naira(units);

/// Naira as a person types it ("1,500", "250.50", "₦20") in minor units, or
/// null when it is not an amount.
int? parseNaira(String text) {
  final String cleaned = text.replaceAll(',', '').replaceAll('₦', '').replaceAll(' ', '').trim();
  final RegExpMatch? match = RegExp(r'^(\d{1,9})(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) return null;
  final int whole = int.parse(match.group(1)!);
  final String fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction);
}

/// Whole megabytes typed by a person, in bytes, or null.
int? megabytes(String text) {
  final int? value = int.tryParse(text.replaceAll(',', '').trim());
  return value == null || value <= 0 ? null : value * mb;
}

/// "1.5 GB", "100 MB", "512 KB".
String dataSize(int bytes) {
  if (bytes <= 0) return '0 MB';
  if (bytes >= 1024 * mb) {
    final double gb = bytes / (1024 * mb);
    final String text = gb.toStringAsFixed(1);
    return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text} GB';
  }
  if (bytes >= mb) return '${bytes ~/ mb} MB';
  return '${(bytes / 1024).ceil()} KB';
}

/// A number as people read it in Nigeria: "0999 000 0001". RTN's own number
/// reads "RTN".
String localNumber(String msisdn) {
  if (msisdn == serviceNumber) return 'RTN';
  if (msisdn.startsWith('234') && msisdn.length == 13) {
    final String local = '0${msisdn.substring(3)}';
    return '${local.substring(0, 4)} ${local.substring(4, 7)} ${local.substring(7)}';
  }
  return msisdn;
}

/// Text the network wrote, with every RTN number in it as people read it:
/// "Data from 2349990000005" becomes "Data from 0999 000 0005".
String readable(String text) =>
    text.replaceAllMapped(RegExp(r'(?<!\d)234\d{10}(?!\d)'), (Match m) => localNumber(m[0]!));

/// A number typed any common way, in the international form the network uses
/// (2349990000001), or null when it is not a number. The same rules as the
/// core's.
String? internationalNumber(String typed) {
  final StringBuffer digits = StringBuffer();
  final String trimmed = typed.trim();
  for (int i = 0; i < trimmed.length; i++) {
    final String c = trimmed[i];
    if (RegExp(r'\d').hasMatch(c)) {
      digits.write(c);
    } else if (c == '+' && i == 0) {
      continue;
    } else if (c == ' ' || c == '-') {
      continue;
    } else {
      return null;
    }
  }
  String number = digits.toString();
  if (number.length == 11 && number.startsWith('0')) number = '234${number.substring(1)}';
  if (number.length < 10 || number.length > 15 || number.startsWith('0')) return null;
  return number;
}

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

/// "14 Oct, 17:05" in the reader's local time.
String shortTime(int millis) {
  final DateTime at = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  final String hour = at.hour.toString().padLeft(2, '0');
  final String minute = at.minute.toString().padLeft(2, '0');
  return '${at.day} ${_months[at.month - 1]}, $hour:$minute';
}

/// "14 Oct 2026".
String shortDate(int millis) {
  final DateTime at = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  return '${at.day} ${_months[at.month - 1]} ${at.year}';
}

/// "1 day", "30 days".
String validity(int days) => days == 1 ? '1 day' : '$days days';

/// Words for a ledger entry's kind.
String entryTitle(String kind) => switch (kind) {
  'top_up' => 'Recharge',
  'loan_repayment' => 'Loan repaid',
  'loan' => 'Airtime borrowed',
  'bundle_purchase' => 'Data bundle',
  'bundle_received' => 'Data gift received',
  'bundle_expired' => 'Bundle expired',
  'transfer_out' => 'Airtime sent',
  'transfer_in' => 'Airtime received',
  'data_share_out' => 'Data shared',
  'data_share_in' => 'Data received',
  'reward_redeemed' => 'Reward',
  'voice' => 'Call',
  'sms' => 'SMS',
  'data' => 'Data use',
  _ => kind.isEmpty ? 'Entry' : '${kind[0].toUpperCase()}${kind.substring(1).replaceAll('_', ' ')}',
};

/// A core message ("not enough airtime: ...") as a sentence: capitalised and
/// ending with a full stop.
String sentence(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) return trimmed;
  final String first = '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  return first.endsWith('.') || first.endsWith('?') || first.endsWith('!') ? first : '$first.';
}
