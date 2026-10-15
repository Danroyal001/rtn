# RTN HTTP API

`rtn serve` listens on `127.0.0.1:8700` by default. Every body is JSON; every error is

```json
{ "error": { "code": "insufficient_funds", "message": "not enough airtime: ₦100.00 needed, ₦12.00 available" } }
```

Money is in minor units (100 = ₦1). Times are Unix milliseconds. Numbers are accepted as
`2349990000001`, `+2349990000001` or `09990000001` and always returned as `2349990000001`.

Operations that change a balance take an optional `request_id` (or an `Idempotency-Key` header).
Sending the same request id again returns the first result and charges nothing; using it for a
different operation answers `409 request_conflict`.

## Public

| Method | Path | Body | Answer |
|---|---|---|---|
| GET | `/health` | | `{status, version, subscribers}` |
| GET | `/v1/bundles` | | the bundle catalogue |
| GET | `/v1/plans` | | the rating plans |
| POST | `/v1/auth/login` | `{msisdn, pin}` | `{token, msisdn, name, expires_at}` (12 hours) |
| POST | `/v1/auth/otp` | `{msisdn}` | `{message_id, expires_at}`: a six-digit code goes out by SMS |
| POST | `/v1/auth/otp/verify` | `{msisdn, code}` | `{token, msisdn, name, expires_at}` |
| POST | `/v1/auth/logout` | | `{signed_out: true}` |

Three wrong PINs lock the PIN for five minutes (`429 pin_locked`). A sign-in code comes from
RTN's service number (`2349990000000`, shown as "RTN"), costs nothing, works once for five
minutes, is thrown away after five wrong tries (`401 code_expired`), and cannot be asked for again
within 30 seconds (`429 too_soon`).

## Self-service (`Authorization: Bearer <token>`)

| Method | Path | Body | Answer |
|---|---|---|---|
| GET | `/v1/me` | | `{subscriber, plan, balance}` |
| GET | `/v1/me/history?limit=50` | | ledger entries, newest first |
| POST | `/v1/me/bundles` | `{bundle_id, beneficiary?, request_id?}` | outcome; with `beneficiary` the bundle is a gift |
| POST | `/v1/me/transfer` | `{to, amount, pin, request_id?}` | outcome |
| POST | `/v1/me/share` | `{to, bytes, pin, request_id?}` | outcome: bundle data moved to another line (50 MB to 10 GB) |
| POST | `/v1/me/borrow` | `{amount, request_id?}` | outcome |
| POST | `/v1/me/recharge` | `{pin, request_id?}` | outcome: a voucher recharge |
| POST | `/v1/me/points` | `{reward_id, request_id?}` | outcome: loyalty points spent on bonus data |
| GET | `/v1/me/notifications` | | messages from RTN's service number |
| GET/POST | `/v1/me/care` | `{text}` | the conversation with RTN care |
| GET | `/v1/me/sms` | | `{inbox, outbox}` |
| POST | `/v1/me/sms` | `{to, text, request_id?}` | outcome |

An outcome is `{request_id, charged, balance, detail}`; `detail.type` says what happened
(`bundle`, `transfer`, `share`, `loan`, `voucher`, `reward`, `sms`, …). Balances carry `points`:
one for every ₦10 recharged or spent on bundles.

Five wrong voucher PINs lock a line out of recharging for 30 minutes (`429 voucher_locked`); a used
voucher answers `409 voucher_used`.

## USSD gateway

`POST /v1/ussd` with `{session_id, msisdn, input}` answers `{text, end, wire}`, where `wire` is
the `CON …`/`END …` form aggregators return to the handset. The first request of a session is a
dial string; later ones carry the subscriber's reply. A subscriber token may only speak for its
own number; the admin token may speak for any.

| Code | Service |
|---|---|
| `*123#` | Menu: balance, data bundles, transfer, borrow, my number, loyalty points |
| `*123*1#` | Balance |
| `*123*5#` | My number |
| `*312#` | Data bundles |
| `*303#` | Borrow airtime |
| `*321*<number>*<naira>*<pin>#` | Transfer airtime in one step |
| `*555*<voucher PIN>#` | Recharge from a voucher |

Sessions close after 180 seconds without input.

## Admin (`Authorization: Bearer $RTN_ADMIN_TOKEN`)

| Method | Path | Body | Answer |
|---|---|---|---|
| GET | `/v1/admin/subscribers?q=&status=&offset=&limit=` | | `{total, offset, items: [{subscriber, balance}]}` |
| POST | `/v1/admin/subscribers` | `{msisdn, name, pin, plan_id?, imsi?}` | subscriber |
| GET | `/v1/admin/subscribers/{msisdn}` | | `{subscriber, balance, history, inbox}` |
| PATCH | `/v1/admin/subscribers/{msisdn}` | any of `{status, plan_id, loan_limit, attached, pin}` | subscriber |
| POST | `/v1/admin/subscribers/{msisdn}/topup` | `{amount, via?, request_id?}` | outcome; `via` names the channel in the ledger |
| GET | `/v1/admin/catalog` | | `{plans, bundles, rewards, default_plan}` |
| PUT | `/v1/admin/plans/{id}` | `{name, voice_per_second, sms_per_segment, data_per_mb}` | plan |
| PUT | `/v1/admin/bundles/{id}` | `{name, data_bytes, price, validity_days, offer?}` | bundle |
| GET/POST | `/v1/admin/vouchers` | `{count, amount}` | the vouchers (never their PINs) / a printed batch with PINs |
| GET | `/v1/admin/care` | | every conversation, the waiting ones first |
| POST | `/v1/admin/care/{msisdn}` | `{text}` | an agent's answer; the assistant stops answering that line |
| GET | `/v1/admin/sms?limit=` | | the SMS centre's latest messages |
| POST | `/v1/admin/rpc` | any RPC call (below) | its answer: the trusted backend's single entry point |
| GET | `/v1/admin/ledger?limit=&msisdn=` | | ledger entries, newest first |
| GET | `/v1/admin/traffic` | | totals, the last 60 seconds, calls, queued SMS, money totals |
| GET | `/v1/admin/totals` | | `{topped_up, lent, repaid, revenue}` |
| POST | `/v1/admin/charge` | `{request_id, op}` | outcome: the charging interface for network elements |
| POST | `/v1/admin/sms/deliver` | | one store-and-forward pass |
| GET/PATCH | `/v1/admin/simulator` | `{running}` | |
| POST | `/v1/admin/simulator/tick` | `{seconds}` | what the simulator did |
| POST | `/v1/admin/seed` | `{count, seed}` | the subscribers added, with PINs |
| POST | `/v1/admin/snapshot` | | writes a snapshot and empties the journal (with `--data`) |

`op` for `/v1/admin/charge` is one of:

```json
{ "type": "top_up", "msisdn": "…", "amount": 10000, "via": "card •••• 4242" }
{ "type": "buy_bundle", "msisdn": "…", "bundle_id": "weekly-1gb", "beneficiary": null }
{ "type": "redeem_voucher", "msisdn": "…", "pin": "1234 5678 9012 3456" }
{ "type": "share_data", "from": "…", "to": "…", "bytes": 104857600 }
{ "type": "redeem_points", "msisdn": "…", "reward_id": "points-1gb" }
{ "type": "transfer", "from": "…", "to": "…", "amount": 10000 }
{ "type": "borrow", "msisdn": "…", "amount": 10000 }
{ "type": "data_usage", "msisdn": "…", "bytes": 1048576 }
{ "type": "voice_start", "msisdn": "…", "callee": "…" }
{ "type": "voice_end", "session_id": "net:<request id of the start>", "used_seconds": 37 }
{ "type": "sms_submit", "from": "…", "to": "…", "text": "…" }
```

## Durability

`rtn serve --data <dir>` keeps the network in a directory: every call that changes it is appended
to `journal.ndjson` and flushed before it is answered, and `snapshot.json` holds the network as of
a journal sequence number. Starting again loads the snapshot and replays the journal after it, so
the same network comes back, ledger included; a crash between writing a snapshot and emptying
the journal never applies a call twice. Reads are not journalled. Without `--data` the network
lives in memory.

## RPC

Everything the core does is one JSON call, `{"method": "...", ...}`, answered `{"ok": ...}` or
`{"error": {"code", "message"}}`: `rtn_core::rpc::Call` lists every method (`apply`, `line`,
`history`, `request_otp`, `verify_otp`, `issue_vouchers`, `care_send`, `ussd`, `tick`, ...). Calls
that depend on time carry `now` (Unix milliseconds), and the ones that need randomness (a sign-in
code, a voucher PIN) carry a `nonce` from the caller, so the core itself reads no clock and no random
source and a journal replays exactly. `POST /v1/admin/rpc` takes these calls over HTTP; the C ABI
takes them in-process.

## In-process (FFI)

`core/crates/rtn-ffi` builds `librtn_ffi` (`.so`, `.dylib`) with the C header in `include/rtn.h`:

```c
RtnNetwork *net = rtn_network_open("/var/lib/rtn");   // journalled; rtn_network_new() for memory only
char *answer = rtn_network_call(net, "{\"method\":\"catalog\"}");
rtn_string_free(answer);
rtn_network_compact(net);                             // snapshot + empty journal
rtn_network_free(net);
```

A handle may be called from several threads; calls run one at a time. The MyRTN backend binds
these with `dart:ffi` (`app/lib/server/ffi.dart`) when `RTN_CORE_LIB` is set.
