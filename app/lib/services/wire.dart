// The types MyRTN's backend functions take and return, shared by the server
// and the app. Pages and components only ever see these classes.
//
// Dartvel 0.12.2 sends a backend function's result with jsonEncode, which
// calls toJson, and the generated client asks for a `fromJson` to read it
// back. This file is the one place that conversion is written. It uses the
// RTN core's own field names, so the same decoder reads the core's answers on
// the server and the backend's answers in the app.
//
// Pure Dart: imported by backend functions and by pages, so no Flutter and no
// dart:io here.

/// Reads one JSON object without trusting its shape.
final class _In {
  _In(Object? data) : _m = data is Map ? data : const <Object?, Object?>{};

  final Map<Object?, Object?> _m;

  String str(String key) => switch (_m[key]) {
        final String s => s,
        null => '',
        final Object other => '$other',
      };

  String? maybe(String key) => _m[key] == null ? null : str(key);

  int integer(String key) => switch (_m[key]) {
        final int i => i,
        final num n => n.toInt(),
        final String s => int.tryParse(s) ?? 0,
        _ => 0,
      };

  bool flag(String key) => _m[key] == true;

  List<T> list<T>(String key, T Function(Object?) read) => <T>[
        for (final Object? item in _m[key] is List ? _m[key]! as List : const <Object?>[]) read(item),
      ];

  /// A JSON object whose values are all of one type, as a list of them.
  List<T> values<T>(String key, T Function(Object?) read) => <T>[
        for (final Object? item in _m[key] is Map ? (_m[key]! as Map).values : const <Object?>[]) read(item),
      ];

  T? optional<T>(String key, T Function(Object?) read) => _m[key] == null ? null : read(_m[key]);

  T one<T>(String key, T Function(Object?) read) => read(_m[key]);
}

List<Object?> _all(Iterable<Object?> items) =>
    <Object?>[for (final Object? item in items) item is _Wire ? item.toJson() : item];

abstract interface class _Wire {
  Map<String, Object?> toJson();
}

// ----- the answer every backend function gives ---------------------------------------

/// A value, or the reason there is none, in words a person can read.
///
/// Backend functions answer with this rather than throwing: Dartvel turns an
/// exception into a bare 500, and a refusal ("not enough airtime") is an
/// answer, not a failure.
final class Reply<T> implements _Wire {
  const Reply.ok(T this.value)
      : code = '',
        message = '';

  const Reply.refused(this.code, this.message) : value = null;

  final T? value;
  final String code;
  final String message;

  bool get ok => code.isEmpty;

  /// The value of an ok reply. Check [ok] first.
  T get result => value as T;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'value': value is _Wire ? (value! as _Wire).toJson() : value,
        'code': code,
        'message': message,
      };

  /// Reads a reply. Anything that is not one (the generated client hands over
  /// the body of a 401 or a 500 as it is) is a refusal, never an empty value.
  static Reply<T> decode<T>(Object? data, T Function(Object?) read) {
    if (data is! Map || !data.containsKey('code')) {
      final String text = data is String ? data : '';
      if (text.contains('Unauthorized')) {
        return Reply<T>.refused('signed_out', 'You are signed out. Sign in again to carry on.');
      }
      if (text.contains('Not authorized')) {
        return Reply<T>.refused('forbidden', 'This account cannot do that.');
      }
      return Reply<T>.refused('unexpected', 'Something went wrong on our side. Try again.');
    }
    final _In m = _In(data);
    final String code = m.str('code');
    return code.isEmpty ? Reply<T>.ok(m.one('value', read)) : Reply<T>.refused(code, m.str('message'));
  }

  /// The `fromJson` a generated client function asks for:
  /// `myLine(fromJson: Reply.of(Line.fromJson))`.
  static Reply<T> Function(Object?) of<T>(T Function(Object?) read) =>
      (Object? data) => decode<T>(data, read);

  /// The reply when the backend could not be reached at all.
  static Reply<T> offline<T>() =>
      Reply<T>.refused('offline', 'Could not reach RTN. Check your connection and try again.');
}

/// An action that has nothing to return but that it worked.
class const Done({final String message = ''}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'message': message};

  static Done fromJson(Object? data) => Done(message: _In(data).str('message'));
}

// ----- the catalogue ---------------------------------------------------------------------

class const Plan({
  required final String id,
  required final String name,
  final int voicePerSecond = 0,
  final int smsPerSegment = 0,
  final int dataPerMb = 0,
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'voice_per_second': voicePerSecond,
        'sms_per_segment': smsPerSegment,
        'data_per_mb': dataPerMb,
      };

  static Plan fromJson(Object? data) {
    final _In m = _In(data);
    return Plan(
      id: m.str('id'),
      name: m.str('name'),
      voicePerSecond: m.integer('voice_per_second'),
      smsPerSegment: m.integer('sms_per_segment'),
      dataPerMb: m.integer('data_per_mb'),
    );
  }
}

class const Bundle({
  required final String id,
  required final String name,
  final int dataBytes = 0,
  final int price = 0,
  final int validityDays = 1,
  final String? offer,
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'data_bytes': dataBytes,
        'price': price,
        'validity_days': validityDays,
        if (offer != null) 'offer': offer,
      };

  static Bundle fromJson(Object? data) {
    final _In m = _In(data);
    return Bundle(
      id: m.str('id'),
      name: m.str('name'),
      dataBytes: m.integer('data_bytes'),
      price: m.integer('price'),
      validityDays: m.integer('validity_days'),
      offer: m.maybe('offer'),
    );
  }
}

class const Reward({
  required final String id,
  required final String name,
  final int points = 0,
  final int dataBytes = 0,
  final int validityDays = 1,
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'points': points,
        'data_bytes': dataBytes,
        'validity_days': validityDays,
      };

  static Reward fromJson(Object? data) {
    final _In m = _In(data);
    return Reward(
      id: m.str('id'),
      name: m.str('name'),
      points: m.integer('points'),
      dataBytes: m.integer('data_bytes'),
      validityDays: m.integer('validity_days'),
    );
  }
}

class const Catalog({
  final List<Plan> plans = const <Plan>[],
  final List<Bundle> bundles = const <Bundle>[],
  final List<Reward> rewards = const <Reward>[],
  final String defaultPlan = '',
}) implements _Wire {
  Plan? plan(String id) => plans.where((Plan p) => p.id == id).firstOrNull;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'plans': <String, Object?>{for (final Plan p in plans) p.id: p.toJson()},
        'bundles': _all(bundles),
        'rewards': _all(rewards),
        'default_plan': defaultPlan,
      };

  static Catalog fromJson(Object? data) {
    final _In m = _In(data);
    return Catalog(
      plans: m.values('plans', Plan.fromJson),
      bundles: m.list('bundles', Bundle.fromJson),
      rewards: m.list('rewards', Reward.fromJson),
      defaultPlan: m.str('default_plan'),
    );
  }
}

// ----- a line ----------------------------------------------------------------------------

class const HeldBundle({
  required final String bundleId,
  required final String name,
  final int bytesLeft = 0,
  final int expiresAt = 0,
}) implements _Wire {
  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'bundle_id': bundleId, 'name': name, 'bytes_left': bytesLeft, 'expires_at': expiresAt};

  static HeldBundle fromJson(Object? data) {
    final _In m = _In(data);
    return HeldBundle(
      bundleId: m.str('bundle_id'),
      name: m.str('name'),
      bytesLeft: m.integer('bytes_left'),
      expiresAt: m.integer('expires_at'),
    );
  }
}

class const Balance({
  required final String msisdn,
  final String planId = '',
  final String status = 'active',
  final int airtime = 0,
  final int reserved = 0,
  final int available = 0,
  final int dataBytes = 0,
  final List<HeldBundle> bundles = const <HeldBundle>[],
  final int loan = 0,
  final int loanLimit = 0,
  final int points = 0,
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'msisdn': msisdn,
        'plan_id': planId,
        'status': status,
        'airtime': airtime,
        'reserved': reserved,
        'available': available,
        'data_bytes': dataBytes,
        'bundles': _all(bundles),
        'loan': loan,
        'loan_limit': loanLimit,
        'points': points,
      };

  static Balance fromJson(Object? data) {
    final _In m = _In(data);
    return Balance(
      msisdn: m.str('msisdn'),
      planId: m.str('plan_id'),
      status: m.str('status'),
      airtime: m.integer('airtime'),
      reserved: m.integer('reserved'),
      available: m.integer('available'),
      dataBytes: m.integer('data_bytes'),
      bundles: m.list('bundles', HeldBundle.fromJson),
      loan: m.integer('loan'),
      loanLimit: m.integer('loan_limit'),
      points: m.integer('points'),
    );
  }
}

class const Subscriber({
  required final String msisdn,
  final String imsi = '',
  final String name = '',
  final String planId = '',
  final String status = 'active',
  final bool attached = true,
  final int loanLimit = 0,
  final int createdAt = 0,
}) implements _Wire {
  bool get barred => status == 'barred';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'msisdn': msisdn,
        'imsi': imsi,
        'name': name,
        'plan_id': planId,
        'status': status,
        'attached': attached,
        'loan_limit': loanLimit,
        'created_at': createdAt,
      };

  static Subscriber fromJson(Object? data) {
    final _In m = _In(data);
    return Subscriber(
      msisdn: m.str('msisdn'),
      imsi: m.str('imsi'),
      name: m.str('name'),
      planId: m.str('plan_id'),
      status: m.str('status'),
      attached: m.flag('attached'),
      loanLimit: m.integer('loan_limit'),
      createdAt: m.integer('created_at'),
    );
  }
}

/// A line, its plan and its balances.
class const Line({required final Subscriber subscriber, final Plan? plan, required final Balance balance})
    implements _Wire {
  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'subscriber': subscriber.toJson(), 'plan': plan?.toJson(), 'balance': balance.toJson()};

  static Line fromJson(Object? data) {
    final _In m = _In(data);
    return Line(
      subscriber: m.one('subscriber', Subscriber.fromJson),
      plan: m.optional('plan', Plan.fromJson),
      balance: m.one('balance', Balance.fromJson),
    );
  }
}

/// One balance change, as the core's ledger keeps it.
class const LedgerEntry({
  required final int seq,
  final int at = 0,
  final String requestId = '',
  final String msisdn = '',
  final String kind = '',
  final int airtimeDelta = 0,
  final int dataDelta = 0,
  final int loanDelta = 0,
  final int airtimeAfter = 0,
  final int dataAfter = 0,
  final int loanAfter = 0,
  final int pointsDelta = 0,
  final int pointsAfter = 0,
  final String note = '',
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'seq': seq,
        'at': at,
        'request_id': requestId,
        'msisdn': msisdn,
        'kind': kind,
        'airtime_delta': airtimeDelta,
        'data_delta': dataDelta,
        'loan_delta': loanDelta,
        'airtime_after': airtimeAfter,
        'data_after': dataAfter,
        'loan_after': loanAfter,
        'points_delta': pointsDelta,
        'points_after': pointsAfter,
        'note': note,
      };

  static LedgerEntry fromJson(Object? data) {
    final _In m = _In(data);
    return LedgerEntry(
      seq: m.integer('seq'),
      at: m.integer('at'),
      requestId: m.str('request_id'),
      msisdn: m.str('msisdn'),
      kind: m.str('kind'),
      airtimeDelta: m.integer('airtime_delta'),
      dataDelta: m.integer('data_delta'),
      loanDelta: m.integer('loan_delta'),
      airtimeAfter: m.integer('airtime_after'),
      dataAfter: m.integer('data_after'),
      loanAfter: m.integer('loan_after'),
      pointsDelta: m.integer('points_delta'),
      pointsAfter: m.integer('points_after'),
      note: m.str('note'),
    );
  }
}

class const LedgerPage({final List<LedgerEntry> entries = const <LedgerEntry>[]}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'entries': _all(entries)};

  static LedgerPage fromJson(Object? data) => LedgerPage(entries: _In(data).list('entries', LedgerEntry.fromJson));
}

/// What an operation did besides change a balance. Which fields mean anything
/// depends on [type].
class const OutcomeDetail({
  final String type = '',
  final int repaid = 0,
  final String bundleId = '',
  final int expiresAt = 0,
  final String? beneficiary,
  final String to = '',
  final int amount = 0,
  final int fee = 0,
  final int borrowed = 0,
  final int owed = 0,
  final String serial = '',
  final int bytes = 0,
  final String rewardId = '',
  final int dataBytes = 0,
  final int points = 0,
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'repaid': repaid,
        'bundle_id': bundleId,
        'expires_at': expiresAt,
        'beneficiary': beneficiary,
        'to': to,
        'amount': amount,
        'fee': fee,
        'borrowed': borrowed,
        'owed': owed,
        'serial': serial,
        'bytes': bytes,
        'reward_id': rewardId,
        'data_bytes': dataBytes,
        'points': points,
      };

  static OutcomeDetail fromJson(Object? data) {
    final _In m = _In(data);
    return OutcomeDetail(
      type: m.str('type'),
      repaid: m.integer('repaid'),
      bundleId: m.str('bundle_id'),
      expiresAt: m.integer('expires_at'),
      beneficiary: m.maybe('beneficiary'),
      to: m.str('to'),
      amount: m.integer('amount'),
      fee: m.integer('fee'),
      borrowed: m.integer('borrowed'),
      owed: m.integer('owed'),
      serial: m.str('serial'),
      bytes: m.integer('bytes'),
      rewardId: m.str('reward_id'),
      dataBytes: m.integer('data_bytes'),
      points: m.integer('points'),
    );
  }
}

/// The result of a charging operation. [reference] is the payment provider's,
/// for a card recharge.
class const Outcome({
  final String requestId = '',
  final int charged = 0,
  required final Balance balance,
  final OutcomeDetail detail = const OutcomeDetail(),
  final String reference = '',
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'request_id': requestId,
        'charged': charged,
        'balance': balance.toJson(),
        'detail': detail.toJson(),
        'reference': reference,
      };

  static Outcome fromJson(Object? data) {
    final _In m = _In(data);
    return Outcome(
      requestId: m.str('request_id'),
      charged: m.integer('charged'),
      balance: m.one('balance', Balance.fromJson),
      detail: m.one('detail', OutcomeDetail.fromJson),
      reference: m.str('reference'),
    );
  }
}

// ----- messages, care and USSD ----------------------------------------------------------

class const SmsMessage({
  required final String id,
  final String from = '',
  final String to = '',
  final String text = '',
  final int segments = 1,
  final int submittedAt = 0,
  final String state = 'queued',
  final bool read = false,
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'from': from,
        'to': to,
        'text': text,
        'segments': segments,
        'submitted_at': submittedAt,
        'state': state,
        'read': read,
      };

  static SmsMessage fromJson(Object? data) {
    final _In m = _In(data);
    return SmsMessage(
      id: m.str('id'),
      from: m.str('from'),
      to: m.str('to'),
      text: m.str('text'),
      segments: m.integer('segments'),
      submittedAt: m.integer('submitted_at'),
      state: m.str('state'),
      read: m.flag('read'),
    );
  }
}

class const Inbox({final List<SmsMessage> messages = const <SmsMessage>[]}) implements _Wire {
  int get unread => messages.where((SmsMessage m) => !m.read).length;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'messages': _all(messages)};

  static Inbox fromJson(Object? data) => Inbox(messages: _In(data).list('messages', SmsMessage.fromJson));
}

/// A subscriber's SMS: what arrived and what they sent, newest first.
class const Messages({
  final List<SmsMessage> inbox = const <SmsMessage>[],
  final List<SmsMessage> sent = const <SmsMessage>[],
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'inbox': _all(inbox), 'sent': _all(sent)};

  static Messages fromJson(Object? data) {
    final _In m = _In(data);
    return Messages(inbox: m.list('inbox', SmsMessage.fromJson), sent: m.list('sent', SmsMessage.fromJson));
  }
}

class const CareMessage({final int at = 0, final String author = 'subscriber', final String text = ''})
    implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'at': at, 'author': author, 'text': text};

  static CareMessage fromJson(Object? data) {
    final _In m = _In(data);
    return CareMessage(at: m.integer('at'), author: m.str('author'), text: m.str('text'));
  }
}

class const CareChat({final String msisdn = '', final List<CareMessage> messages = const <CareMessage>[]})
    implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'msisdn': msisdn, 'messages': _all(messages)};

  static CareChat fromJson(Object? data) {
    final _In m = _In(data);
    return CareChat(msisdn: m.str('msisdn'), messages: m.list('messages', CareMessage.fromJson));
  }
}

class const CareThread({
  required final String msisdn,
  final String name = '',
  final int messages = 0,
  final int lastAt = 0,
  final String lastText = '',
  final bool waiting = false,
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'msisdn': msisdn,
        'name': name,
        'messages': messages,
        'last_at': lastAt,
        'last_text': lastText,
        'waiting': waiting,
      };

  static CareThread fromJson(Object? data) {
    final _In m = _In(data);
    return CareThread(
      msisdn: m.str('msisdn'),
      name: m.str('name'),
      messages: m.integer('messages'),
      lastAt: m.integer('last_at'),
      lastText: m.str('last_text'),
      waiting: m.flag('waiting'),
    );
  }
}

class const CareDesk({final List<CareThread> threads = const <CareThread>[]}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'threads': _all(threads)};

  static CareDesk fromJson(Object? data) => CareDesk(threads: _In(data).list('threads', CareThread.fromJson));
}

class const UssdReply({final String text = '', final bool end = true}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'text': text, 'end': end};

  static UssdReply fromJson(Object? data) {
    final _In m = _In(data);
    return UssdReply(text: m.str('text'), end: m.flag('end'));
  }
}

// ----- sign-in ---------------------------------------------------------------------------

/// A sign-in code is on its way. [demoCode] is only set on a demo server, where
/// nobody has the handset the code went to.
class const CodeSent({required final String msisdn, final int expiresAt = 0, final String demoCode = ''})
    implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'msisdn': msisdn, 'expires_at': expiresAt, 'demo_code': demoCode};

  static CodeSent fromJson(Object? data) {
    final _In m = _In(data);
    return CodeSent(msisdn: m.str('msisdn'), expiresAt: m.integer('expires_at'), demoCode: m.str('demo_code'));
  }
}

/// Who a new session belongs to. The session itself travels as a cookie (or,
/// on a device, as [token]).
class const SignedIn({required final String userId, final String name = '', final String role = '', final String token = ''})
    implements _Wire {
  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'user_id': userId, 'name': name, 'role': role, if (token.isNotEmpty) 'token': token};

  static SignedIn fromJson(Object? data) {
    final _In m = _In(data);
    return SignedIn(userId: m.str('user_id'), name: m.str('name'), role: m.str('role'), token: m.str('token'));
  }
}

// ----- the home screen -------------------------------------------------------------------

class const Dashboard({
  required final Line line,
  final int unread = 0,
  final List<LedgerEntry> recent = const <LedgerEntry>[],
  final List<Bundle> offers = const <Bundle>[],
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'line': line.toJson(),
        'unread': unread,
        'recent': _all(recent),
        'offers': _all(offers),
      };

  static Dashboard fromJson(Object? data) {
    final _In m = _In(data);
    return Dashboard(
      line: m.one('line', Line.fromJson),
      unread: m.integer('unread'),
      recent: m.list('recent', LedgerEntry.fromJson),
      offers: m.list('offers', Bundle.fromJson),
    );
  }
}

/// What the rewards page shows: the points and what they buy.
class const Loyalty({final int points = 0, final List<Reward> rewards = const <Reward>[]}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'points': points, 'rewards': _all(rewards)};

  static Loyalty fromJson(Object? data) {
    final _In m = _In(data);
    return Loyalty(points: m.integer('points'), rewards: m.list('rewards', Reward.fromJson));
  }
}

// ----- the console -----------------------------------------------------------------------

class const TrafficCounters({
  final int dataBytes = 0,
  final int voiceSeconds = 0,
  final int sms = 0,
  final int ussd = 0,
  final int charges = 0,
  final int revenue = 0,
  final int failures = 0,
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'data_bytes': dataBytes,
        'voice_seconds': voiceSeconds,
        'sms': sms,
        'ussd': ussd,
        'charges': charges,
        'revenue': revenue,
        'failures': failures,
      };

  static TrafficCounters fromJson(Object? data) {
    final _In m = _In(data);
    return TrafficCounters(
      dataBytes: m.integer('data_bytes'),
      voiceSeconds: m.integer('voice_seconds'),
      sms: m.integer('sms'),
      ussd: m.integer('ussd'),
      charges: m.integer('charges'),
      revenue: m.integer('revenue'),
      failures: m.integer('failures'),
    );
  }
}

class const Totals({final int toppedUp = 0, final int lent = 0, final int repaid = 0, final int revenue = 0})
    implements _Wire {
  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'topped_up': toppedUp, 'lent': lent, 'repaid': repaid, 'revenue': revenue};

  static Totals fromJson(Object? data) {
    final _In m = _In(data);
    return Totals(
      toppedUp: m.integer('topped_up'),
      lent: m.integer('lent'),
      repaid: m.integer('repaid'),
      revenue: m.integer('revenue'),
    );
  }
}

/// The live view: totals since start, the last minute second by second, and
/// what is happening now.
class const Traffic({
  final int at = 0,
  final TrafficCounters totals = const TrafficCounters(),
  final int seriesFrom = 0,
  final List<TrafficCounters> series = const <TrafficCounters>[],
  final int subscribers = 0,
  final int activeSubscribers = 0,
  final int attached = 0,
  final int activeCalls = 0,
  final int queuedSms = 0,
  final int ussdSessions = 0,
  final Totals money = const Totals(),
  final bool simulating = false,
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'at': at,
        'totals': totals.toJson(),
        'series_from': seriesFrom,
        'series': _all(series),
        'subscribers': subscribers,
        'active_subscribers': activeSubscribers,
        'attached': attached,
        'active_calls': activeCalls,
        'queued_sms': queuedSms,
        'ussd_sessions': ussdSessions,
        'money': money.toJson(),
        'simulating': simulating,
      };

  static Traffic fromJson(Object? data) {
    final _In m = _In(data);
    return Traffic(
      at: m.integer('at'),
      totals: m.one('totals', TrafficCounters.fromJson),
      seriesFrom: m.integer('series_from'),
      series: m.list('series', TrafficCounters.fromJson),
      subscribers: m.integer('subscribers'),
      activeSubscribers: m.integer('active_subscribers'),
      attached: m.integer('attached'),
      activeCalls: m.integer('active_calls'),
      queuedSms: m.integer('queued_sms'),
      ussdSessions: m.integer('ussd_sessions'),
      money: m.one('money', Totals.fromJson),
      simulating: m.flag('simulating'),
    );
  }
}

class const SubscriberRow({required final Subscriber subscriber, required final Balance balance}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'subscriber': subscriber.toJson(), 'balance': balance.toJson()};

  static SubscriberRow fromJson(Object? data) {
    final _In m = _In(data);
    return SubscriberRow(
      subscriber: m.one('subscriber', Subscriber.fromJson),
      balance: m.one('balance', Balance.fromJson),
    );
  }
}

class const SubscriberPage({final int total = 0, final int offset = 0, final List<SubscriberRow> items = const <SubscriberRow>[]})
    implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'total': total, 'offset': offset, 'items': _all(items)};

  static SubscriberPage fromJson(Object? data) {
    final _In m = _In(data);
    return SubscriberPage(
      total: m.integer('total'),
      offset: m.integer('offset'),
      items: m.list('items', SubscriberRow.fromJson),
    );
  }
}

/// One subscriber as the operator sees them.
class const SubscriberFile({
  required final Line line,
  final List<LedgerEntry> history = const <LedgerEntry>[],
  final List<SmsMessage> inbox = const <SmsMessage>[],
  final List<Plan> plans = const <Plan>[],
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'line': line.toJson(),
        'history': _all(history),
        'inbox': _all(inbox),
        'plans': _all(plans),
      };

  static SubscriberFile fromJson(Object? data) {
    final _In m = _In(data);
    return SubscriberFile(
      line: m.one('line', Line.fromJson),
      history: m.list('history', LedgerEntry.fromJson),
      inbox: m.list('inbox', SmsMessage.fromJson),
      plans: m.list('plans', Plan.fromJson),
    );
  }
}

class const Voucher({
  required final String serial,
  final int amount = 0,
  final int createdAt = 0,
  final String? usedBy,
  final int? usedAt,
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'serial': serial,
        'amount': amount,
        'created_at': createdAt,
        'used_by': usedBy,
        'used_at': usedAt,
      };

  static Voucher fromJson(Object? data) {
    final _In m = _In(data);
    return Voucher(
      serial: m.str('serial'),
      amount: m.integer('amount'),
      createdAt: m.integer('created_at'),
      usedBy: m.maybe('used_by'),
      usedAt: m.optional('used_at', (Object? v) => v is num ? v.toInt() : 0),
    );
  }
}

/// A printed voucher: the only time its PIN is shown.
class const PrintedVoucher({required final String serial, required final String pin, final int amount = 0})
    implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'serial': serial, 'pin': pin, 'amount': amount};

  static PrintedVoucher fromJson(Object? data) {
    final _In m = _In(data);
    return PrintedVoucher(serial: m.str('serial'), pin: m.str('pin'), amount: m.integer('amount'));
  }
}

class const VoucherBook({
  final List<Voucher> vouchers = const <Voucher>[],
  final List<PrintedVoucher> printed = const <PrintedVoucher>[],
}) implements _Wire {
  @override
  Map<String, Object?> toJson() => <String, Object?>{'vouchers': _all(vouchers), 'printed': _all(printed)};

  static VoucherBook fromJson(Object? data) {
    final _In m = _In(data);
    return VoucherBook(
      vouchers: m.list('vouchers', Voucher.fromJson),
      printed: m.list('printed', PrintedVoucher.fromJson),
    );
  }
}
