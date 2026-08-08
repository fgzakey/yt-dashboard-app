# YT Dashboard (Android app) — agent context (AGENTS.md)

Single source of truth for every coding harness — Codex and Hermes read it
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
- When giving PowerShell/terminal blocks to paste, end the block with a lone `#` line. Be concise and direct.

## Repo specifics

- **No checked-in `android/` directory.** CI runs `flutter create --platforms=android .` before building; locally you must run that once before `flutter build apk` works.
- share_plus ^13, flutter_lints ^6.
- The YT WEB dashboard is deprecated (folded into Phil's Library at `/videos`); this Flutter app is alive and still gets ported changes.
