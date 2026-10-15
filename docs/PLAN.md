# RTN plan

RTN is a small but working mobile-network operator stack: the parts that hold a subscriber's
money and messages are written in Rust, and everything a person looks at is written in Dartvel.
This file is the plan for milestone 1 and the list of what comes after. It is kept current: when a
decision changes, it changes here.

## Identity

- Name: **RTN**. In the product it stands for nothing in particular; the README has the joke.
- Colours: deep teal (`#0F766E`) with a rust accent (`#C2410C`) on an off-white or near-black
  page. No yellow, no other operator's name, logo, tagline or USSD branding.
- Currency: minor units (`u64`, kobo-like), shown as `₦` with two decimals. Phone numbers are
  Nigerian-shaped (`234…`) because the joke is Nigerian, but the number ranges are RTN's own
  test range (`2349990000000`–`2349999999999`), which no real operator uses.

## Milestone 1

### Rust core (`core/`, one cargo workspace)

| Crate | What it is |
|---|---|
| `rtn-core` | The library. No I/O, no async, no clock it does not get handed. |
| `rtn-api` | One HTTP/JSON API (axum) over one `rtn_core::Network`. |
| `rtn-cli` | The `rtn` binary: `serve`, `seed`, `simulate`, and client commands against a running API. |
| `rtn-ffi` | A C ABI over the same library (JSON in, JSON out) for in-process callers. |

`rtn-core` modules:

1. **Registry** (HLR/HSS-like): subscribers keyed by MSISDN with an IMSI index; plan, status
   (active, barred), PIN hash, loan limit. MSISDN and IMSI are validated types, not strings.
2. **Rating plans and bundles**: per-second voice rate, per-SMS-segment price, pay-as-you-go
   data rate per MB, and a bundle catalogue (data MB, price, validity days).
3. **Online charging engine** (OCS-like):
   - balances: airtime, data bundles (with expiry), outstanding loan;
   - operations: top-up, buy bundle, airtime transfer (with fee), borrow (loan repaid from the next
     top-up with a service fee), data usage (bundle first, then airtime), voice as a credit-control
     session (reserve a quota on start, commit exact per-second usage on end, release the rest);
   - every operation carries a request id: replaying one returns the first result and never
     charges twice;
   - an append-only ledger: every balance change is a ledger entry with the balance after it.
   - invariants (property-tested): no balance goes negative; replaying any request changes
     nothing; transfers conserve money (sender loses amount + fee, receiver gains amount, the
     operator gains the fee); each account's balance equals the sum of its ledger deltas.
4. **USSD gateway**: a session state machine. `*123#` opens the menu (balance, bundles,
   transfer, borrow, my number); shortcuts `*123*1#` (balance), `*312#` (bundles),
   `*321*<number>*<amount>*<pin>#` (transfer) and `*303#` (borrow). Responses are `CON` (expects
   input) or `END` (session closed), the convention USSD aggregators use. Sessions time out.
5. **SMS centre**: store-and-forward. Submit charges the sender per segment (GSM-7 160/153,
   UCS-2 70/67), queues for the recipient, delivers when the recipient is attached, retries with
   back-off while they are not, expires after the validity period, and sends the sender a
   delivery report either way.
6. **Data-usage metering simulator**: a seeded generator of traffic (data sessions, calls, SMS)
   across subscribers, applied through the charging engine; per-second traffic counters for
   the live view.

Persistence for milestone 1: in memory, with a JSON snapshot on demand (`POST /v1/admin/snapshot`)
and on shutdown when `--state <file>` is given; loaded at start when the file exists.

Quality bar: unit tests per module, `proptest` properties for the charging invariants and the
USSD/SMS state machines, `criterion` benchmarks for charging, USSD and SMS throughput, `clippy
-D warnings`.

### HTTP API (`rtn-api`)

- `GET /health`
- Self-service, subscriber token from `POST /v1/auth/login {msisdn, pin}`:
  `GET /v1/me`, `GET /v1/me/history`, `POST /v1/me/bundles`, `POST /v1/me/transfer`,
  `POST /v1/me/borrow`, `GET /v1/me/sms`, `POST /v1/me/sms`.
- `GET /v1/bundles` (public catalogue).
- `POST /v1/ussd {session_id, msisdn, input}` (the gateway, as an aggregator would call it).
- Admin, `Authorization: Bearer $RTN_ADMIN_TOKEN`: subscribers (list, create, read, update
  status/plan, top up), plans (list, create/update), bundles (create/update), ledger, traffic,
  network charging events (data, voice start/end, SMS submit), simulator tick, snapshot.

Errors are JSON `{error: {code, message}}` with stable codes (`insufficient_funds`,
`unknown_subscriber`, …).

### Dartvel app (`app/`, Dartvel 0.12.2)

One Dartvel application with two areas, built for web, web-server and Android:

- **Self-service**: sign in with number and PIN; balance (airtime, data, loan); buy bundles;
  transfer airtime; history; a USSD dial pad that talks to the gateway.
- **Admin console** (`/admin/...`): subscribers (list, search, create, bar/unbar, top up),
  rating plans and bundles, and live traffic (counters refreshed every two seconds).

Every screen is a page with its own URL, rendered by Dartvel's one render path (server-rendered
on web-server, prerendered on web), so text is selectable, findable with Ctrl+F, reachable with
Tab and read by screen readers. Every control has a tooltip and an accessible label.

The app reaches the core through **Dartvel backend functions** (`lib/backend/functions`) that
call the Rust HTTP API (`RTN_CORE_URL`), so the browser never holds the admin token and the
app's typed client is the only thing the pages call. The FFI crate is there for an in-process
binding; wiring the backend to it is milestone 2.

Milestone 1 sessions are the core's own tokens kept by the app; moving to `DV.Auth` sessions and
`_guard.dart` (so the server refuses an admin page to a signed-out visitor) is milestone 2.

### Demo

`./demo.sh` builds the core, starts the API, seeds 50 subscribers (PIN `1234` on the first five,
printed), runs the traffic simulator, and serves the Dartvel web-server build pointed at it.
`./demo.sh --core-only` skips the Flutter build.

### Order of work (test first)

1. Workspace skeleton, types, failing tests for each module's contract.
2. Registry → plans → charging (+ properties) → USSD → SMSC → metering.
3. API with integration tests (`tower::ServiceExt::oneshot`), then the CLI.
4. Benchmarks; FFI crate with a round-trip test.
5. Dartvel app: backend functions with tests, then pages; web-server build checked in a real
   browser; screenshots.
6. `demo.sh`; README.

## MyRTN (between milestones 1 and 2)

The self-service app grew into MyRTN, a full operator self-care app: sign-in with a number and
a one-time code the core sends by SMS; home with balance, data meter, offers and recent
activity; data bundles for yourself or as a gift; recharge with a voucher PIN or a card through
MockPay, a test payment provider in the backend; airtime transfer and data sharing with the PIN;
borrowing; history with a receipt per transaction; loyalty points spent on bonus data;
notifications from RTN's service number; support chat (an assistant until an agent answers from
the console); SMS; a USSD dial pad; and account management (name, plan, PIN, SIM swap, suspending
a lost line, switching the simulated handset off and on). The core gained what these need,
test-first: one-time codes, vouchers, recharge channels, gifts, data sharing, points, rewards,
notifications with read state, care threads, PIN change, SIM swap and self-suspension. The console
gained vouchers, a care desk and the SMS centre.

## Milestone 2: done

- **Sessions**: Dartvel sessions. Dartvel 0.12.2 has no phone sign-in, so the backend checks the
  one-time code and asks Dartvel's session store for a session with a `role` claim
  (`subscriber` or `operator`); a cookie in a browser, the token in the body on a device.
  `@DVPolicy` classes (`SubscriberLine`, `OperatorConsole`) gate every backend function; the
  line a function acts on is always the session's own. `_guard.dart` in `pages/my` and
  `pages/console` sends the wrong kind of visitor to the right sign-in page, and the web-server
  sends a signed-out request for a guarded page to `/signin` before rendering anything.
- **In-process core**: with `RTN_CORE_LIB` set, the backend loads `librtn_ffi` with `dart:ffi`
  and holds the network itself, ticking it every second; without it, it calls `rtn serve` at
  `POST /v1/admin/rpc`. Both speak the same RPC.
- **Durable ledger**: `rtn_core::node::Node`, an append-only journal of every call that changes
  the network, flushed before the call is answered, with snapshot compaction. `rtn serve --data`
  and `rtn_network_open` both use it. Replay is exact because the core reads no clock and no
  random source: callers pass `now` and a `nonce`.

## After milestone 2
- **M3, protocols**: a Diameter Gy (credit control) front for the charging engine, SMPP 3.4 bind
  for the SMSC, and a USSD aggregator-style HTTP callback adapter.
- **M4, network side**: a simulated radio/packet core (attach/detach, cells, roaming partner),
  number portability lookup, CDR export.
- **M5, scale**: sharded charging engine, ledger replication, load test at 10k TPS.
