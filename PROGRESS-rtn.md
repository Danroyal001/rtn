# RTN progress (handoff file)

Public repository (MIT). Commits as `Danroyal001 <danroyaleffiong@gmail.com>`, no AI trailers.
No secrets and no paths from anybody's machine in the repo.

## State on 2026-11-03

- **Milestones 1 and 2: merged** (PRs #1 plan, #2 core, #3 tweet link, #4 MyRTN on Dartvel 0.12.2).
  The old `m1-app` branch was superseded by #4 and is not merged on its own.
- **Branch `m1-finish`** (PR, base `main`): the app on **Dartvel 0.13.18** with the one-line
  `DV.run(args)` entry (`@DVBoot` registers the theme choice, `@DVAppRoot` wraps the generated
  router in `RtnApp`), the browser walkthrough and screenshots (`docs/screens/m1/`), and the
  milestone 3 spike below.
- **Milestone 3 spike** (`docs/M3-SPIKE.md`): Open5GS v2.8.0 + UERANSIM v3.3.0 attach, PDU session
  and ping through the UPF on PLMN 999/70 (`net/5gc/`); the charging and subscriber interfaces of
  Open5GS and free5GC v4.3.0, verified from running systems and source; `core/crates/rtn-5gc`, a
  provisioning bridge (SIM keys, RTN lines into Open5GS's subscriber DB, UE configs,
  `rtn 5g sync`, `rtn 5g ue-config`) with an end-to-end test against the Docker core.

## Open problems (found 2026-11-03, see the PR)

- **Signed-in pages are not server-rendered.** For `/my/*` and `/console/*` the web-server sends
  the splash shell only; the text exists once Flutter takes over. Dartvel deletes a guarded route's
  semantics capture and renders documents from captures (Dartvel CHANGELOG 0.12.x: "A guarded
  route's old semantics capture is deleted, never served"). A Dartvel framework gap, not an RTN
  bug; needs per-request rendering of guarded pages in Dartvel.
- **Signed-out `/console` goes to `/signin`**, not `/operator`: the server uses the one
  `dartvel.auth.pages.signIn` for every guarded route; the app's own console guard (to `/operator`)
  only runs in the browser. Also a Dartvel limitation (one sign-in page per app).
- **Tab does not reach a page's own controls.** In headless Chrome, Tab cycles between the top
  bar's home link, the theme switch and the Flutter view; on `/signin` it skips the number field.
  Identical on a 0.12.2 baseline build of `main` and on 0.13.18, so not an upgrade regression;
  `FocusKeeper` (the app's workaround for Dartvel's page shell taking focus) is not enough. Needs a
  Dartvel fix.
- Fixed here: Dartvel 0.13.2 keeps the page scrollbar on screen, and `Screen` padded its scroll
  view from outside, so the bar covered the right edge of every card at 390 px (a regression from
  the upgrade, seen against the 0.12.2 baseline). The margins are now inside the scroll view.
- Older layout nit, not fixed: "Quick actions" on the home screen shows one centred tile per row
  at phone width (same on 0.12.2).
- **Android:** `dart run dartvel_cli:dartvel build android --profile profile` builds
  `build/app/outputs/flutter-apk/app-profile.apk` (76.9 MB, debug-signed, minSdk 24, targetSdk 36).
  Not run: this VPS has no `/dev/kvm` for an emulator. A release APK needs a release key
  (`DARTVEL_ANDROID_KEYSTORE`…). `prodBackendHost` is `http://localhost:8740`, so a phone would
  need a reachable backend host set before the APK is useful.
- **No data charging yet** on the 5G core: Open5GS's 5G core has no charging interface; free5GC's
  SMF does (Nchf_ConvergedCharging) but no user plane worked with it here. Next: `rtn-chf` and a
  free5GC-compatible UPF (docs/PLAN.md, "After the spike").

## How to carry on

- Core: `cd core && cargo test --workspace && cargo clippy --workspace --all-targets -- -D warnings`
  (the `rtn-5gc` end-to-end test brings up `net/5gc` itself when Docker and the images are there).
- App: `export PATH=$HOME/snap/flutter/common/flutter/bin:$PATH; cd app && dart run dartvel_cli:dartvel routes && flutter test`
  (needs `RTN_CORE_LIB=core/target/release/librtn_ffi.so`), then `dart run dartvel_cli:dartvel build web-server`.
- Demo: `./demo.sh`. On the owner's VPS use `RTN_APP_PORT=18740 RTN_ADDR=127.0.0.1:18700`
  (8740 is dartvel.dev).
- 5G: `net/5gc/up.sh`, then with `rtn serve` running and `RTN_SIM_SECRET`/`RTN_SIM_OP` set:
  `rtn 5g sync`, `rtn 5g ue-config 2349990000001 > ue.yaml`, `net/5gc/ue.sh 0001 ue.yaml`,
  `docker exec rtn5g-ue-0001 ping -I uesimtun0 10.45.0.1`; `net/5gc/down.sh` when done.
- free5GC charging network: `net/5gc/free5gc/up.sh` / `down.sh` (control plane + Open5GS UPF; the
  PDU session fails at N4, see the spike).
- Browser checks: run your own headless Chrome via puppeteer-core, never the shared one on 9333.
  Flutter web drops keys typed in the first moments after a field gains focus; wait ~400 ms.
