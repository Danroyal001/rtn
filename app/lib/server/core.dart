// The backend's line to the RTN core. Every call is one of the core's RPC
// methods (core/crates/rtn-core/src/rpc.rs); the answer comes back as a typed
// Reply. Two ways to reach the core:
//
// - in-process (milestone 2): `librtn_ffi` loaded with dart:ffi, the network
//   kept in a directory with its journal. Set RTN_CORE_LIB (and RTN_DATA).
// - over HTTP: a running `rtn serve`, called at POST /v1/admin/rpc with the
//   operator's token, which never leaves the server. Set RTN_CORE_URL and
//   RTN_ADMIN_TOKEN.
//
// Server-only: pages never import this file, and the browser never sees the
// token or the core.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../services/money.dart';
import '../services/wire.dart';
import 'ffi.dart';

/// Carries one RPC request to the core and brings back its answer, both as
/// JSON text: `{"ok": ...}` or `{"error": {"code": ..., "message": ...}}`.
abstract interface class CoreLink {
  Future<String> call(String request);

  void close();
}

/// The core loaded in this process.
final class FfiCoreLink implements CoreLink {
  FfiCoreLink._(this._network);

  factory FfiCoreLink.open(String library, String dir) => FfiCoreLink._(RtnLibraryNetwork.open(library, dir));

  final RtnLibraryNetwork _network;

  @override
  Future<String> call(String request) async => _network.call(request);

  @override
  void close() => _network.close();
}

/// A core running as its own process (`rtn serve`).
final class HttpCoreLink implements CoreLink {
  HttpCoreLink(this.base, {required this.token});

  final Uri base;
  final String token;
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  @override
  Future<String> call(String request) async {
    final HttpClientRequest req = await _client.postUrl(base.resolve('/v1/admin/rpc'));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(request));
    final HttpClientResponse res = await req.close().timeout(const Duration(seconds: 10));
    final String body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 200) return '{"ok":$body}';
    if (body.startsWith('{')) return body;
    return jsonEncode(<String, Object?>{
      'error': <String, Object?>{'code': 'http_${res.statusCode}', 'message': 'the core refused the request'},
    });
  }

  @override
  void close() => _client.close(force: true);
}

int _systemClock() => DateTime.now().millisecondsSinceEpoch;

/// Typed calls to the core.
final class Core {
  Core(this.link, {int Function()? clock}) : _clock = clock ?? _systemClock;

  final CoreLink link;
  final int Function() _clock;
  final Random _random = Random.secure();
  Timer? _ticker;

  int get now => _clock();

  /// A random number for the core to derive a code or a voucher PIN from. The
  /// core reads no randomness of its own, so its journal replays exactly.
  int nonce() => _random.nextInt(1 << 32) * (1 << 20) + _random.nextInt(1 << 20);

  static Core? _shared;

  /// The core this server process talks to, configured from its environment.
  static Core get shared => _shared ??= _fromEnvironment(Platform.environment);

  static Core _fromEnvironment(Map<String, String> env) {
    final String? library = env['RTN_CORE_LIB'];
    if (library == null || library.isEmpty) {
      return Core(
        HttpCoreLink(Uri.parse(env['RTN_CORE_URL'] ?? 'http://127.0.0.1:8700'), token: env['RTN_ADMIN_TOKEN'] ?? ''),
      );
    }
    final Core core = Core(FfiCoreLink.open(library, env['RTN_DATA'] ?? '.rtn-data'));
    core.startUp(seed: int.tryParse(env['RTN_SEED'] ?? '') ?? 0, simulate: env['RTN_SIMULATE'] == '1');
    // In-process, nothing else drives the network's clock: the SMS centre's
    // retries and the simulator advance on this tick, as `rtn serve` does it.
    core._ticker = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(core.tick()));
    return core;
  }

  Future<void>? _starting;

  /// Seeds an empty network with [seed] demo lines and switches the simulator
  /// on when asked. Every call waits for this, so nobody reaches a network
  /// that is still being filled.
  void startUp({int seed = 0, bool simulate = false}) {
    _starting = () async {
      if (seed > 0) {
        final Object? page = jsonDecode(
          await link.call(
            jsonEncode(<String, Object?>{
              'method': 'subscriber_page', 'q': '', 'offset': 0, 'limit': 1, 'now': now, //
            }),
          ),
        );
        final Object? total = page is Map && page['ok'] is Map ? (page['ok'] as Map)['total'] : null;
        if (total == 0) {
          await link.call(jsonEncode(<String, Object?>{'method': 'seed', 'count': seed, 'seed': 1, 'now': now}));
        }
      }
      if (simulate) await link.call(jsonEncode(<String, Object?>{'method': 'set_simulator', 'running': true}));
    }();
  }

  void close() {
    _ticker?.cancel();
    link.close();
  }

  /// Runs one call and reads its answer with [read].
  Future<Reply<T>> ask<T>(Map<String, Object?> call, T Function(Object?) read) async {
    final String answer;
    try {
      await _starting;
      answer = await link.call(jsonEncode(call));
    } on Object {
      return Reply<T>.refused('core_unreachable', 'The RTN network is not reachable right now. Try again shortly.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(answer);
    } on FormatException {
      return Reply<T>.refused('core_garbled', 'The RTN network sent something unreadable.');
    }
    if (decoded is Map && decoded.containsKey('ok')) return Reply<T>.ok(read(decoded['ok']));
    final Object? error = decoded is Map ? decoded['error'] : null;
    if (error is Map) return Reply<T>.refused('${error['code']}', sentence('${error['message'] ?? ''}'));
    return Reply<T>.refused('core_garbled', 'The RTN network sent something unreadable.');
  }

  static Done _done(Object? _) => const Done();

  static List<T> _list<T>(Object? data, T Function(Object?) read) => <T>[
    for (final Object? item in data is List ? data : const <Object?>[]) read(item),
  ];

  static Inbox _inbox(Object? data) => Inbox(messages: _list(data, SmsMessage.fromJson));

  static CareChat _chat(Object? data) => CareChat(messages: _list(data, CareMessage.fromJson));

  // ----- reads ---------------------------------------------------------------------------

  Future<Reply<Line>> line(String msisdn) =>
      ask(<String, Object?>{'method': 'line', 'msisdn': msisdn, 'now': now}, Line.fromJson);

  Future<Reply<Subscriber>> subscriber(String msisdn) =>
      ask(<String, Object?>{'method': 'subscriber', 'msisdn': msisdn}, Subscriber.fromJson);

  Future<Reply<Catalog>> catalog() => ask(<String, Object?>{'method': 'catalog'}, Catalog.fromJson);

  Future<Reply<LedgerPage>> history(String msisdn, int limit) => ask(<String, Object?>{
    'method': 'history',
    'msisdn': msisdn,
    'limit': limit,
  }, (Object? data) => LedgerPage(entries: _list(data, LedgerEntry.fromJson)));

  Future<Reply<LedgerEntry>> ledgerEntry(int seq) =>
      ask(<String, Object?>{'method': 'ledger_entry', 'seq': seq}, LedgerEntry.fromJson);

  Future<Reply<LedgerPage>> ledger(int limit) => ask(<String, Object?>{
    'method': 'ledger',
    'limit': limit,
  }, (Object? data) => LedgerPage(entries: _list(data, LedgerEntry.fromJson)));

  Future<Reply<Inbox>> inbox(String msisdn) => ask(<String, Object?>{'method': 'inbox', 'msisdn': msisdn}, _inbox);

  Future<Reply<Inbox>> outbox(String msisdn) => ask(<String, Object?>{'method': 'outbox', 'msisdn': msisdn}, _inbox);

  Future<Reply<Inbox>> notifications(String msisdn) =>
      ask(<String, Object?>{'method': 'notifications', 'msisdn': msisdn}, _inbox);

  Future<Reply<Inbox>> smsLog(int limit) => ask(<String, Object?>{'method': 'sms_log', 'limit': limit}, _inbox);

  Future<Reply<SubscriberPage>> subscriberPage(String q, int offset, int limit) => ask(<String, Object?>{
    'method': 'subscriber_page',
    'q': q,
    'offset': offset,
    'limit': limit,
    'now': now,
  }, SubscriberPage.fromJson);

  Future<Reply<CareChat>> careThread(String msisdn) =>
      ask(<String, Object?>{'method': 'care_thread', 'msisdn': msisdn}, _chat);

  Future<Reply<CareDesk>> careThreads() => ask(<String, Object?>{
    'method': 'care_threads',
  }, (Object? data) => CareDesk(threads: _list(data, CareThread.fromJson)));

  Future<Reply<List<Voucher>>> vouchers(int limit) =>
      ask(<String, Object?>{'method': 'vouchers', 'limit': limit}, (Object? data) => _list(data, Voucher.fromJson));

  /// The live view, with the money totals and the simulator's state.
  Future<Reply<Traffic>> traffic() async {
    final Reply<Traffic> view = await ask(<String, Object?>{'method': 'traffic', 'now': now}, Traffic.fromJson);
    if (!view.ok) return view;
    final Reply<Totals> totals = await ask(<String, Object?>{'method': 'totals'}, Totals.fromJson);
    final Reply<bool> running = await ask(<String, Object?>{
      'method': 'simulator',
    }, (Object? d) => d is Map && d['running'] == true);
    final Traffic t = view.result;
    return Reply<Traffic>.ok(
      Traffic(
        at: t.at,
        totals: t.totals,
        seriesFrom: t.seriesFrom,
        series: t.series,
        subscribers: t.subscribers,
        activeSubscribers: t.activeSubscribers,
        attached: t.attached,
        activeCalls: t.activeCalls,
        queuedSms: t.queuedSms,
        ussdSessions: t.ussdSessions,
        money: totals.ok ? totals.result : const Totals(),
        simulating: running.ok && running.result,
      ),
    );
  }

  // ----- charging ------------------------------------------------------------------------

  /// Applies a charging operation under [requestId]; a retry with the same id
  /// is answered with the first outcome and charged once.
  Future<Reply<Outcome>> apply(String requestId, Map<String, Object?> op) =>
      ask(<String, Object?>{'method': 'apply', 'request_id': requestId, 'op': op, 'now': now}, Outcome.fromJson);

  // ----- the line ------------------------------------------------------------------------

  Future<Reply<Done>> verifyPin(String msisdn, String pin) =>
      ask(<String, Object?>{'method': 'verify_pin', 'msisdn': msisdn, 'pin': pin, 'now': now}, _done);

  Future<Reply<CodeSent>> requestOtp(String msisdn) => ask(
    <String, Object?>{'method': 'request_otp', 'msisdn': msisdn, 'nonce': nonce(), 'now': now},
    (Object? data) => CodeSent(msisdn: msisdn, expiresAt: data is Map ? (data['expires_at'] as num? ?? 0).toInt() : 0),
  );

  Future<Reply<Done>> verifyOtp(String msisdn, String code) =>
      ask(<String, Object?>{'method': 'verify_otp', 'msisdn': msisdn, 'code': code, 'now': now}, _done);

  Future<Reply<Done>> setName(String msisdn, String name) =>
      ask(<String, Object?>{'method': 'set_name', 'msisdn': msisdn, 'name': name}, _done);

  Future<Reply<Done>> changePin(String msisdn, String old, String fresh) =>
      ask(<String, Object?>{'method': 'change_pin', 'msisdn': msisdn, 'old': old, 'new': fresh, 'now': now}, _done);

  Future<Reply<Subscriber>> swapSim(String msisdn, String pin) =>
      ask(<String, Object?>{'method': 'swap_sim', 'msisdn': msisdn, 'pin': pin, 'now': now}, Subscriber.fromJson);

  Future<Reply<Done>> suspendLine(String msisdn, String pin) =>
      ask(<String, Object?>{'method': 'suspend_line', 'msisdn': msisdn, 'pin': pin, 'now': now}, _done);

  Future<Reply<Done>> setAttached(String msisdn, bool attached) =>
      ask(<String, Object?>{'method': 'set_attached', 'msisdn': msisdn, 'attached': attached, 'now': now}, _done);

  Future<Reply<Done>> setPlan(String msisdn, String planId) =>
      ask(<String, Object?>{'method': 'set_plan', 'msisdn': msisdn, 'plan_id': planId}, _done);

  Future<Reply<Done>> setStatus(String msisdn, String status) =>
      ask(<String, Object?>{'method': 'set_status', 'msisdn': msisdn, 'status': status}, _done);

  Future<Reply<Done>> setLoanLimit(String msisdn, int limit) =>
      ask(<String, Object?>{'method': 'set_loan_limit', 'msisdn': msisdn, 'limit': limit}, _done);

  Future<Reply<Done>> setPin(String msisdn, String pin) =>
      ask(<String, Object?>{'method': 'set_pin', 'msisdn': msisdn, 'pin': pin}, _done);

  Future<Reply<Subscriber>> addSubscriber(String msisdn, String name, String pin, String? planId) =>
      ask(<String, Object?>{
        'method': 'add_subscriber',
        'subscriber': <String, Object?>{'msisdn': msisdn, 'name': name, 'pin': pin, 'plan_id': planId},
        'now': now,
      }, Subscriber.fromJson);

  // ----- messages, care, USSD ------------------------------------------------------------

  Future<Reply<Done>> markRead(String msisdn, List<String> ids) =>
      ask(<String, Object?>{'method': 'mark_read', 'msisdn': msisdn, 'ids': ids}, _done);

  Future<Reply<Done>> deliverSms() => ask(<String, Object?>{'method': 'deliver_sms', 'now': now}, _done);

  Future<Reply<CareChat>> careSend(String msisdn, String text) =>
      ask(<String, Object?>{'method': 'care_send', 'msisdn': msisdn, 'text': text, 'now': now}, _chat);

  Future<Reply<CareChat>> careReply(String msisdn, String text) =>
      ask(<String, Object?>{'method': 'care_reply', 'msisdn': msisdn, 'text': text, 'now': now}, _chat);

  Future<Reply<UssdReply>> ussd(String sessionId, String msisdn, String input) => ask(<String, Object?>{
    'method': 'ussd',
    'session_id': sessionId,
    'msisdn': msisdn,
    'input': input,
    'now': now,
  }, UssdReply.fromJson);

  // ----- the operator --------------------------------------------------------------------

  Future<Reply<Done>> seed(int count) =>
      ask(<String, Object?>{'method': 'seed', 'count': count, 'seed': 1, 'now': now}, _done);

  Future<Reply<List<PrintedVoucher>>> issueVouchers(int count, int amount) => ask(<String, Object?>{
    'method': 'issue_vouchers',
    'count': count,
    'amount': amount,
    'nonce': nonce(),
    'now': now,
  }, (Object? data) => _list(data, PrintedVoucher.fromJson));

  Future<Reply<Done>> upsertPlan(Plan plan) =>
      ask(<String, Object?>{'method': 'upsert_plan', 'plan': plan.toJson()}, _done);

  Future<Reply<Done>> upsertBundle(Bundle bundle) =>
      ask(<String, Object?>{'method': 'upsert_bundle', 'bundle': bundle.toJson()}, _done);

  Future<Reply<Done>> setSimulator(bool running) =>
      ask(<String, Object?>{'method': 'set_simulator', 'running': running}, _done);

  /// One second of the network's background work.
  Future<Reply<Done>> tick() => ask(<String, Object?>{'method': 'tick', 'now': now}, _done);
}
