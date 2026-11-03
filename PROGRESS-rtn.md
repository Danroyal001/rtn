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
- Tab order and the 390 px layout: see the PR for what the 0.12.2 baseline comparison showed.
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
