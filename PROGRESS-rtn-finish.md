# RTN: progress on `agent/rtn-finish`

Public repository (MIT). Commits are by SigmaDev with no AI trailers. No secrets, no paths from
anybody's machine.

## Where things stand

Done and checked:

- **Core** (`core/`): the self-care features MyRTN needs (one-time sign-in codes over the SMS
  centre, vouchers, recharge channels, bundle gifts, data sharing, loyalty points and rewards,
  notifications with read state, customer care threads, PIN change, SIM swap, self-suspension,
  `*555*PIN#`), the durable `Node` (journal + snapshot, exact replay), RPC over HTTP
  (`POST /v1/admin/rpc`) and over the C ABI (`rtn_network_open`, `rtn_network_compact`).
  `cargo test --workspace` (92 tests) and `cargo clippy --workspace --all-targets -- -D warnings`
  pass.
- **App** (`app/`): MyRTN rewritten on Dartvel 0.12.2: typed backend functions answering
  `Reply<T>`, `@DVPolicy` gates, Dartvel sessions issued after the SMS code, guards on `/my` and
  `/console`, every screen a `@DVFunctionalWidget` with signals, tooltips and names, the core
  in-process through `dart:ffi`. `flutter test` (86 tests) and `flutter analyze` pass;
  `dartvel build web-server` passes, including its page capture and accessibility audit.
- **End to end**: the web-server binary run with the core in-process and driven in headless
  Chromium, 30 steps, all passing: sign-in by SMS code, every subscriber action, Ctrl+F, Tab
  order, dark mode, 360 px, the console, a voucher printed in the console and redeemed by a
  subscriber, an agent's reply reaching the subscriber, and a subscriber kept out of the console.
  Screenshots in `docs/screens/`.
- **`demo.sh`**: run in all three modes. The default and `--http` serve MyRTN on :8740 from the
  same `.demo/network`, which survives a restart; `--core-only` serves the API on :8700; Ctrl+C
  (or TERM) stops every process it started. The walkthrough also passes against `--http`, except
  that sharing data can be refused there when the traffic simulator has already used the line's
  bundle, which is the network doing its job.

Fixed late, found by driving the real build:

- Switching between light and dark sent the reader back to `/`: the router was rebuilt with the
  theme. It is now made once in `main.dart` (a widget test holds this).
- Keyboard users could not Tab past the top bar. In 0.12.2 on the web, the page shell takes focus
  from a control as it gains it. `lib/services/focus.dart` (`FocusKeeper`) gives focus back, with
  a TODO to remove it when Dartvel is fixed. Tab now walks the bar, the nav and every control.
- Text from the core showed numbers as `2349990000005`; `wire.dart` now shows `0999 000 0005`.

Not done:

- **Android**: not built. The build machine could not download the Android SDK. The code has
  nothing web-only in it, and a device gets its session as a token rather than a cookie, but no
  APK has been built or run.
- **`main.dart` is not `DV.run()`**: Dartvel 0.12.2 has no `DV.run()`; `main.dart` is the
  smallest main it can run, with a TODO.
- **Backend middleware is not a `middleware:` field**: `@DVBackendFunction` has no such field in
  0.12.2, and `DVMiddlewares.auth` refuses everything unless the server is wired for it, which an
  application cannot do. Access is by `policy:` on the annotation instead.
- **Two calls name their fields**: the sign-in functions take the `Request` to set the session
  cookie, so 0.12.2 generates no typed call for them.

Worth knowing when testing in a browser:

- Flutter web drops keys typed in the first few milliseconds after a field gains focus. A person
  never types that fast; a test script must wait a moment after clicking a field.
- The server logs 404s for `/_dartvel/pages`: Dartvel Studio's endpoint, off in this app.

## How to carry on

- Core: `cd core && cargo test --workspace`
- App: `cd app && flutter test` (needs `core/target/release/librtn_ffi.so`), then
  `dartvel build web-server`
- Everything: `./demo.sh` (in-process core) or `./demo.sh --http` (core as `rtn serve`)
