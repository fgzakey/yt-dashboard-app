# YT Dashboard (Android app) — agent context (AGENTS.md)

Single source of truth for every coding harness — Antigravity and Cursor read it
natively; Claude Code imports it via `CLAUDE.md`. Edit THIS file, not the pointer.

## What this repo is

Android companion app for Phil's Library (videos) — same backend, same database.
A Flutter thin client of the Phil's Library backend (Hugging Face Docker Space →
same Neon Postgres DB as the web dashboard). No credentials ship in the app:
server URL + app password are entered in Settings at runtime (defaults in
`lib/app_state.dart`, HTTP layer in `lib/api.dart`, records in `lib/models.dart`,
screens in `lib/screens/`).

## Commands

- `flutter pub get` then `flutter run` (device/emulator) — debug.
- `flutter analyze` — must be clean, but a green analyze is NECESSARY NOT SUFFICIENT whenever a plugin's MAJOR version moves: only a real `flutter build apk` catches a broken Android plugin registrant.
- Release: push to `main` → `.github/workflows/build-apk.yml` builds the APK and attaches it to a GitHub release (tags like `v1.0.0-b29`).

## Cross-repo rules (all three Flutter apps)

- The three companions — `book-dashboard-app`, `phils-brain-app`, `yt-dashboard-app` — get dependency upgrades in ONE pass, but are NOT on identical constraints (see repo specifics below). Read `AGENTS.md` in each before bumping anything shared.
- `flutter pub upgrade --major-versions` WILL resolve to prereleases (it once picked file_picker 12.0.0-beta.7) — read its output, never trust it blindly.
- share_plus >= 12: use `SharePlus.instance.share(ShareParams(...))`; on iPad read `sharePositionOrigin` from the BuildContext BEFORE any await or `use_build_context_synchronously` fires.
- flutter_lints 6 adds `use_null_aware_elements`: `if (x != null) 'k': x` becomes `'k': ?x` (the `?` goes on the VALUE).
- Web-app parity: features are ported from the web dashboard (`phils-library` repo). When the web changes a shared feature, port it here in the same pass or the two drift. The web repo's AGENTS.md carries the full institutional knowledge.
- HUMAN AT THE STARTING GUN & SECURITY GOVERNANCE: All agents and harnesses operate under the 'Human at the Starting Gun' permissions model (docs/SECURITY-POLICY-HUMAN-AT-THE-STARTING-GUN.md) — design with full analysis, get explicit human authorization checkpoint, then implement autonomously under strict invariants (non-destructive git, zero-plaintext secret hygiene, database role boundaries).
- When giving PowerShell/terminal blocks to paste, end the block with a lone `#` line. Be concise and direct.

## Repo specifics

- **No checked-in `android/` directory.** CI runs `flutter create --platforms=android .` before building; locally you must run that once before `flutter build apk` works.
- share_plus ^13, flutter_lints ^6.
- The YT WEB dashboard is deprecated (folded into Phil's Library at `/videos`); this Flutter app is alive and still gets ported changes.
- **Video list search + sort (2026-08-11)** — the port of the web dashboard's `app/library-search.js`; keep `VideoSort` in `lib/app_state.dart` in step with the web's `LIBRARY_SORTS`. Four orders: Last modified (`savedAt`) / Last accessed (`openedAt`) / Date added (`addedAt`) / Last extracted (`extractedAt`), in an AppBar `PopupMenuButton` of `CheckedPopupMenuItem`s (plain items would leave the active order invisible, since `initialValue` only positions the menu). Last modified stays the DEFAULT — a sort control must not silently reshuffle the library on first launch. The three new `Video` fields are server-owned epoch ms and are deliberately absent from `toJson()`, like `savedAt`. Landmines this port hit, all worth keeping:
  - **`savedAt` is NOT "last accessed".** It is `updated_at`, bumped by any write. Opening a video calls `api.touchVideo` → `PATCH /api/db/videos?touch=<id>`, which writes the separate `last_opened_at` and nothing else. Never stamp it with `saveVideo` — the upsert would bump `updated_at` and reorder every default-sorted list in all four clients. It is fire-and-forget on tap (not awaited, errors swallowed), and prefers the server's returned timestamp over the device clock so rows stamped by the web dashboard sort on the same timeline.
  - **Dart has no NFD**, so the web's "decompose then strip combining marks" accent folding is unavailable. `AppState._foldMap` is an explicit á→a table instead. Accent folding is not cosmetic: the library is bilingual and nobody types "Filosofía" with the accent.
  - **`main.dart` holds the tab screens in a `const` list**, so switching tabs disposes `_VideosScreenState` while `AppState.videoQuery` survives in the provider. `initState` re-seeds `_searchCtrl` from it — without that the box returns empty over a still-filtered list, which is exactly the data-loss illusion the don't-persist-the-query rule exists to prevent. The query is per-session; the sort is persisted (`SharedPreferences` key `videoSort`).
  - **Don't hard-code the search bar's `PreferredSize` height.** `main.dart` applies a user-settable global `TextScaler` (`mdScale`, up to 3.0); a fixed 56 overflows. It scales via `MediaQuery.textScalerOf`.
  - The title shows `Videos (3 / 27)` while filtering and `(27)` otherwise, and the "No videos yet" empty state keys off the UNFILTERED list so it can't fight "No videos match" — same rules as the web panel headers.
