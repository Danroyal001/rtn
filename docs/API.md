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
| POST | `/v1/auth/logout` | | `{signed_out: true}` |

Three wrong PINs lock the PIN for five minutes (`429 pin_locked`).

## Self-service (`Authorization: Bearer <token>`)

| Method | Path | Body | Answer |
|---|---|---|---|
| GET | `/v1/me` | | `{subscriber, plan, balance}` |
| GET | `/v1/me/history?limit=50` | | ledger entries, newest first |
| POST | `/v1/me/bundles` | `{bundle_id, request_id?}` | outcome |
| POST | `/v1/me/transfer` | `{to, amount, pin, request_id?}` | outcome |
| POST | `/v1/me/borrow` | `{amount, request_id?}` | outcome |
| GET | `/v1/me/sms` | | `{inbox, outbox}` |
| POST | `/v1/me/sms` | `{to, text, request_id?}` | outcome |

An outcome is `{request_id, charged, balance, detail}`; `detail.type` says what happened
(`bundle`, `transfer`, `loan`, `sms`, …).

## USSD gateway

`POST /v1/ussd` with `{session_id, msisdn, input}` answers `{text, end, wire}`, where `wire` is
the `CON …`/`END …` form aggregators return to the handset. The first request of a session is a
dial string; later ones carry the subscriber's reply. A subscriber token may only speak for its
own number; the admin token may speak for any.

| Code | Service |
|---|---|
| `*123#` | Menu: balance, data bundles, transfer, borrow, my number |
| `*123*1#` | Balance |
| `*123*5#` | My number |
| `*312#` | Data bundles |
| `*303#` | Borrow airtime |
| `*321*<number>*<naira>*<pin>#` | Transfer airtime in one step |

Sessions close after 180 seconds without input.

## Admin (`Authorization: Bearer $RTN_ADMIN_TOKEN`)

| Method | Path | Body | Answer |
|---|---|---|---|
| GET | `/v1/admin/subscribers?q=&status=&offset=&limit=` | | `{total, offset, items: [{subscriber, balance}]}` |
| POST | `/v1/admin/subscribers` | `{msisdn, name, pin, plan_id?, imsi?}` | subscriber |
| GET | `/v1/admin/subscribers/{msisdn}` | | `{subscriber, balance, history, inbox}` |
| PATCH | `/v1/admin/subscribers/{msisdn}` | any of `{status, plan_id, loan_limit, attached, pin}` | subscriber |
| POST | `/v1/admin/subscribers/{msisdn}/topup` | `{amount, request_id?}` | outcome |
| GET | `/v1/admin/catalog` | | `{plans, bundles, default_plan}` |
| PUT | `/v1/admin/plans/{id}` | `{name, voice_per_second, sms_per_segment, data_per_mb}` | plan |
| PUT | `/v1/admin/bundles/{id}` | `{name, data_bytes, price, validity_days}` | bundle |
| GET | `/v1/admin/ledger?limit=&msisdn=` | | ledger entries, newest first |
| GET | `/v1/admin/traffic` | | totals, the last 60 seconds, calls, queued SMS, money totals |
| GET | `/v1/admin/totals` | | `{topped_up, lent, repaid, revenue}` |
| POST | `/v1/admin/charge` | `{request_id, op}` | outcome: the charging interface for network elements |
| POST | `/v1/admin/sms/deliver` | | one store-and-forward pass |
| GET/PATCH | `/v1/admin/simulator` | `{running}` | |
| POST | `/v1/admin/simulator/tick` | `{seconds}` | what the simulator did |
| POST | `/v1/admin/seed` | `{count, seed}` | the subscribers added, with PINs |
| POST | `/v1/admin/snapshot` | | saves to the `--state` file |

`op` for `/v1/admin/charge` is one of:

```json
{ "type": "top_up", "msisdn": "…", "amount": 10000 }
{ "type": "buy_bundle", "msisdn": "…", "bundle_id": "weekly-1gb" }
{ "type": "transfer", "from": "…", "to": "…", "amount": 10000 }
{ "type": "borrow", "msisdn": "…", "amount": 10000 }
{ "type": "data_usage", "msisdn": "…", "bytes": 1048576 }
{ "type": "voice_start", "msisdn": "…", "callee": "…" }
{ "type": "voice_end", "session_id": "net:<request id of the start>", "used_seconds": 37 }
{ "type": "sms_submit", "from": "…", "to": "…", "text": "…" }
```

## In-process (FFI)

`core/crates/rtn-ffi` builds `librtn_ffi.so` with the C header in `include/rtn.h`. It takes the
same operations as JSON calls (`{"method": "apply", "request_id": …, "op": …, "now": …}`); see
`rtn_core::rpc::Call` for every method.
