# RTN finish — agent/rtn-finish (branch off m1-app)

Repo is PUBLIC/open source (MIT). Never commit secrets, /home paths, private tooling. Author: SigmaDev <61921483+Danroyal001@users.noreply.github.com>. No AI trailers.

## Current state (read from ~/rtn/progress + code inspection, 15 Oct)

- Branch `agent/rtn-finish` based on `m1-app` (66956ff). Source now present in ~/wt/rtn-finish.
- PR #1 (plan, m1-plan) and PR #2 (Rust core, m1-core) open. Core: 57 tests pass, clippy clean, smoke-tested `rtn serve`. FFI crate (`rtn-ffi`) exists but not wired into app backend yet.
- App (`m1-app`): `flutter analyze` clean, 15/15 tests pass. `demo.sh` written but NEVER run. Screens never built/opened in browser. No PR #3 for the app.
- Milestone 2 (PLAN.md) NOT started: no DV.Auth sessions, no `_guard.dart`, backend uses raw JSON (`Map<String, Object?>`) not typed functions, app reaches core via HTTP (`callCore`) not in-process FFI, no durable ledger file.
- Dartvel version: framework expects 0.12.1. App uses `main.dart` (not `DV.run()`), `MaterialApp.router` with `runApp()` (not framework render path convention fully), no `lib/index.dart` (only `pages/index.dart`), no `_guard.dart`, backend functions return raw JSON, components use `StatelessWidget` instead of `DVFunctionalWidget`/`DVClassWidget`, no signal-based refresh, many controls lack tooltips and `Semantics` labels.

## What the brief asks (binding quality bar from ~/AGENTS.md / brief)

1. App to ALL Dartvel conventions (0.12.1): `DV.run()` only, `index.dart` + `_guard.dart`, `DVFunctionalWidget`/`DVClassWidget`, `DVBox`/`DVText`, typed backend functions, NO JSON in app code, signals, tooltips + a11y, Dart-only tooling, latest Dartvel.
2. Build web-server + Android, run `./demo.sh` end to end, real-browser check of every page (own headless Chrome only; 360/1280 px, light/dark where themed, Ctrl+F, Tab), screenshots in `docs/screens/`. Open PR #3 for app.
3. Milestone 2 from PLAN.md: proper Dartvel sign-in sessions with guarded console pages, app calling core in-process via FFI (`rtn-ffi`), durable ledger. PR #4.

## Plan (test-first, evidence, never call partial done)

Step 1: Fix app conventions (typed backends, DV.run(), index.dart + _guard, DV widgets, signals, tooltips/a11y, no JSON). Run `flutter test`.
Step 2: Build core release (`~/heavy.sh cargo ...`), build Dartvel web-server (`~/heavy.sh dartvel build web-server`), run `./demo.sh`, verify health, console, sign-in.
Step 3: Real browser checks with own puppeteer-core Chrome (not shared 9333). Screenshots at 360 and 1280 px. Commit under `docs/screens/`.
Step 4: Android build (`~/heavy.sh dartvel build apk`).
Step 5: Milestone 2 (DV.Auth, _guard.dart wired, backend over FFI when library present, durable ledger). PR #4.
Step 6: Commit final, open PRs (#3 for app, #4 for M2), update `~/agent-context/STATUS.md`, write final report here.

Never merge PRs, never deploy, never message anyone.

---

## Log of steps

15 Oct 01:15 — Switched ~/wt/rtn-finish to `m1-app` source. Read full codebase. Confirmed previous agent made zero commits. Wrote accurate PROGRESS.
15 Oct 01:25 — `~/heavy.sh cargo test --workspace` passes (57 tests). `~/heavy.sh dartvel routes` generates barrel. `~/heavy.sh flutter test` now passes 15/15. Updated PROGRESS.

Next: Step 1 — inspect all backend functions, convert to typed objects; add `lib/index.dart`; add `_guard.dart`; replace `runApp()` with `DV.run()` convention; replace `StatelessWidget` components with `DVFunctionalWidget`/`DVClassWidget` where appropriate; add signals for refresh; add tooltips and `Semantics` labels everywhere.
Blockers: none yet. Must use `~/heavy.sh` for cargo and dartvel builds. Must remove `build/`, `target/` when finished.

- LEAD NOTE: PRs #1 (plan) and #2 (core) are MERGED into main. Rebase m1-app onto main before PR #3.
