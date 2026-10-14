// What every page needs to talk about money, data and time, and to read the
// one answer shape every backend function gives.

/// The result of a backend function: data, or a refusal with a reason a
/// person can read.
class const RtnResult({
  final bool ok = false,
  final Object? data,
  final String code = '',
  final String message = '',
}) {
  factory RtnResult.from(Map<String, Object?> answer) => answer['ok'] == true
      ? RtnResult(ok: true, data: answer['data'])
      : RtnResult(
          code: '${answer['code'] ?? 'refused'}',
          message: '${answer['message'] ?? 'That did not work.'}',
        );

  Map<String, Object?> get map =>
      data is Map ? Map<String, Object?>.from(data! as Map) : const <String, Object?>{};

  List<Map<String, Object?>> get list => data is List
      ? <Map<String, Object?>>[
          for (final Object? item in data! as List)
            if (item is Map) Map<String, Object?>.from(item),
        ]
      : const <Map<String, Object?>>[];
}

/// Runs a backend call and turns a transport failure into a refusal.
Future<RtnResult> rtnCall(Future<Map<String, Object?>> Function() call) async {
  try {
    return RtnResult.from(await call());
  } catch (_) {
    return const RtnResult(
      code: 'offline',
      message: 'Could not reach RTN. Check your connection and try again.',
    );
  }
}

/// Reads a nested JSON value as a map.
Map<String, Object?> asMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const <String, Object?>{};

/// Reads a nested JSON value as a list of maps.
List<Map<String, Object?>> asList(Object? value) => value is List
    ? <Map<String, Object?>>[
        for (final Object? item in value)
          if (item is Map) Map<String, Object?>.from(item),
      ]
    : const <Map<String, Object?>>[];

int asInt(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

/// "₦1,234.50" for 123450 minor units.
String naira(Object? units) {
  final int value = asInt(units);
  final String whole = (value ~/ 100).toString();
  final StringBuffer grouped = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '₦$grouped.${(value % 100).toString().padLeft(2, '0')}';
}

/// "1.5 GB", "100 MB", "512 KB".
String dataSize(Object? bytes) {
  final int value = asInt(bytes);
  const int mb = 1048576;
  if (value >= 1024 * mb) {
    final double gb = value / (1024 * mb);
    return '${gb.toStringAsFixed(gb == gb.roundToDouble() ? 0 : 1)} GB';
  }
  if (value >= mb) return '${(value / mb).toStringAsFixed(value % mb == 0 ? 0 : 1)} MB';
  return '${(value / 1024).ceil()} KB';
}

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "14 Oct, 17:45" in the reader's local time.
String when(Object? millis) {
  final DateTime at = DateTime.fromMillisecondsSinceEpoch(asInt(millis)).toLocal();
  final String hour = at.hour.toString().padLeft(2, '0');
  final String minute = at.minute.toString().padLeft(2, '0');
  return '${at.day} ${_months[at.month - 1]}, $hour:$minute';
}

/// A number as people read it in Nigeria: "0999 000 0001" for 2349990000001.
String phone(Object? msisdn) {
  final String digits = '$msisdn';
  if (digits.startsWith('234') && digits.length == 13) {
    final String local = '0${digits.substring(3)}';
    return '${local.substring(0, 4)} ${local.substring(4, 7)} ${local.substring(7)}';
  }
  return digits;
}

/// A fresh id for one attempt at an operation, so a retry is recognised.
String newRequestId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

/// Human words for a ledger entry's kind.
String entryKind(Object? kind) => switch ('$kind') {
      'top_up' => 'Top-up',
      'loan_repayment' => 'Loan repaid',
      'loan' => 'Borrowed',
      'bundle_purchase' => 'Bundle',
      'bundle_expired' => 'Bundle expired',
      'transfer_out' => 'Sent',
      'transfer_in' => 'Received',
      'voice' => 'Call',
      'sms' => 'SMS',
      'data' => 'Data',
      final String other => other,
    };
