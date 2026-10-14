# RTN progress (paused 2026-10-14: queued while the owner runs 2 agents)

## Done
- Repo https://github.com/Danroyal001/rtn (public). Stacked PRs: #1 plan (`m1-plan`), #2 Rust core (`m1-core`).
- Rust core (`core/`): rtn-core (registry, charging + idempotent ledger, USSD, SMSC, simulator, traffic),
  rtn-api (axum), rtn-cli (`rtn`), rtn-ffi (C ABI + include/rtn.h). 57 tests incl. proptest
  invariants pass; clippy -D warnings clean; benches in core/README.md; smoke-tested `rtn serve`.
- Dartvel app (`app/`, branch `m1-app`, WIP, no PR yet): backend functions proxying to the core
  (lib/backend), pages for My line, Bundles, Transfer, Borrow, Messages, History, USSD dial pad,
  Console (live traffic, subscribers + detail, plans/bundles). `flutter analyze` clean,
  `flutter test` 15/15 pass. `demo.sh`, README written.

## Not done yet (next steps, in order)
1. `cd app && ~/heavy.sh dartvel build web-server`; run `./demo.sh`; check every page in an own
   puppeteer-core Chrome (not the shared 9333 one): SSR HTML, Ctrl+F, Tab, screen reader labels,
   phone width; screenshots.
2. `~/heavy.sh dartvel build apk` (Android SDK at ~/android-sdk).
3. Open PR #3 from `m1-app` (base `m1-core`) with evidence; add a STATUS.md entry.
4. Milestone 2+: see docs/PLAN.md (DV.Auth sessions + _guard.dart, backend over rtn-ffi, durable ledger).

## Resume
- `cd ~/rtn && git checkout m1-app`
- Core: `cd core && ~/heavy.sh cargo test --workspace` (cargo is ~/.cargo/bin/cargo)
- App: `export PATH=$HOME/snap/flutter/common/flutter/bin:$PATH; cd app && dartvel routes && flutter test`
- Commits: SigmaDev <61921483+Danroyal001@users.noreply.github.com>, no AI trailers.
