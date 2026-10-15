# MyRTN

The self-service app for RTN lines, and the RTN operator console, in one
[Dartvel](https://dartvel.dev) 0.12.2 application. It runs as a web-server binary (the backend,
the web app and server-side rendering in one file) and builds for Android.

## What a subscriber can do

| Page | |
|---|---|
| `/signin` | Sign in with an RTN number and a six-digit code the network sends by SMS |
| `/my` | Airtime, a data meter with every bundle and its expiry, loan, points, offers, recent activity |
| `/my/data` | Buy daily to monthly bundles, for the line or as a gift to another number |
| `/my/recharge` | Recharge with a voucher PIN, or a card through MockPay, for any RTN number |
| `/my/transfer` | Send airtime or share bundle data, confirmed with the PIN |
| `/my/borrow` | Borrow airtime, repaid from the next recharge with a 10% fee |
| `/my/history` | Every transaction, filterable, with a receipt for each (`/my/history/<n>`) |
| `/my/rewards` | Spend loyalty points on bonus data |
| `/my/notifications` | What RTN has said: receipts, gifts, codes, alerts |
| `/my/support` | Chat to RTN care: an assistant at once, an agent when one answers |
| `/my/messages` | Send and read SMS, held at the SMS centre while the other phone is off |
| `/my/ussd` | A dial pad for `*123#`, `*312#`, `*303#`, `*321*…#`, `*555*PIN#` |
| `/my/account` | Name, plan, PIN, SIM swap, suspending a lost line, the simulated handset |

The operator signs in at `/operator` and gets `/console` (live traffic and money), subscribers
(search, add, bar, top up, plan, loan limit, PIN reset, ledger), the catalogue, vouchers, the care
desk, the SMS centre and the ledger.

## How it is put together

```
lib/
  main.dart            the smallest main Dartvel 0.12.2 can run (a TODO marks where DV.run() goes)
  pages/               one line per page; my/ and console/ each have a _guard.dart
  components/          every screen and piece of UI, as @DVFunctionalWidget functions
  backend/functions/   one typed backend function per action, each behind a @DVPolicy
  policies/access.dart SubscriberLine and OperatorConsole
  server/              server-only: the core link (FFI or HTTP), sessions, MockPay, the services
  services/            shared: the wire types and their one codec, money and number formatting,
                       loading data into signals, signing in on the device
web/                   the manifest, icons and a bootstrap that serves CanvasKit from the app
```

Backend functions take strings, ints and bools and answer `Reply<T>`: the value, or a refusal
with a code and a sentence a person can read. The line a function acts on always comes from the
Dartvel session, never from the request. See `AGENTS.md` for the conventions in full.

## Run it

From the repository root, `./demo.sh` builds the core and this app and runs both. By hand:

```sh
cd ../core && cargo build --release
cd ../app && dartvel build web-server
RTN_CORE_LIB=../core/target/release/librtn_ffi.so RTN_DATA=.rtn-data RTN_SEED=50 RTN_SIMULATE=1 \
RTN_CONSOLE_PASSWORD=choose-one RTN_DEMO=1 DARTVEL_PORT=8740 ./build/server
```

| Variable | |
|---|---|
| `RTN_CORE_LIB`, `RTN_DATA` | Load the core in-process and keep the network in this directory |
| `RTN_CORE_URL`, `RTN_ADMIN_TOKEN` | Otherwise, call a running `rtn serve` |
| `RTN_SEED`, `RTN_SIMULATE` | In-process only: demo lines for an empty network, and the traffic simulator |
| `RTN_CONSOLE_PASSWORD` | The console's password; with none, the console is closed |
| `RTN_DEMO=1` | Show sign-in codes on the page, for a demo where nobody holds the handsets |

The build opens each public page in a headless Chrome to write its HTML; set `DARTVEL_CHROME`
when Chrome is not in a standard place.

## Test

```sh
flutter test        # the services against the real core (build it first), and every screen
flutter analyze
```

The service tests load `../core/target/release/librtn_ffi.so` (or `RTN_CORE_LIB`). The widget
tests build every screen in light and dark at 360 and 1280 px with no backend, and the frame
inside a router.
