/// A typed subscriber line from the core: never a raw JSON map in app code.
class SubscriberLine {
  final String msisdn;
  final String imsi;
  final String status;
  final String planName;
  final int balanceUnits;
  final int loanUnits;
  final List<DataBundle> bundles;

  const SubscriberLine({
    required this.msisdn,
    required this.imsi,
    required this.status,
    required this.planName,
    required this.balanceUnits,
    required this.loanUnits,
    required this.bundles,
  });

  factory SubscriberLine.fromCore(Object? raw) {
    final Map<String, Object?> m = (raw is Map) ? Map<String, Object?>.from(raw) : <String, Object?>{};
    return SubscriberLine(
      msisdn: '${m['msisdn'] ?? ''}',
      imsi: '${m['imsi'] ?? ''}',
      status: '${m['status'] ?? 'unknown'}',
      planName: '${m['plan_name'] ?? m['plan'] ?? ''}',
      balanceUnits: (m['balance_units'] is int) ? m['balance_units'] as int : 0,
      loanUnits: (m['loan_units'] is int) ? m['loan_units'] as int : 0,
      bundles: <DataBundle>[],
    );
  }
}

class DataBundle {
  final String name;
  final int mb;
  final int priceUnits;
  const DataBundle({required this.name, required this.mb, required this.priceUnits});
}
