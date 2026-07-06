# YT Dashboard — Android App

Flutter companion app for the YT Dashboard. It is a thin client of the same
backend (your Hugging Face Space), so it reads and writes the **same Neon
Postgres database** as the web version — videos, chats, prompts, and results
stay in sync across both.

## v1 features (core parity)

- **Videos** — fetch transcripts by URL, browse the shared library, delete.
- **Chat** — ask questions about any video (same system prompt as the web); history syncs.
- **Prompts** — built-in + custom standardized prompts, create/edit/delete, run against any video.
- **Results** — searchable saved-results library with Markdown rendering.
- **Settings** — server URL, app password, OpenRouter model picker, temperature.

Slides & Visuals and Visual Scribe are planned for v2.

## How it works

No database credentials or API keys live in the app. It calls the dashboard's
existing API routes (`/api/transcript`, `/api/chat`, `/api/db/*`, `/api/models`)
and authenticates with the same `APP_PASSWORD` as the web login (sent as the
`yt_auth` cookie). One new route was added to the dashboard for the app:
`/api/prompts/defaults` (exposes the built-in prompts) — deploy the dashboard
once after adding it.

## Building the APK (GitHub Actions — no local toolchain needed)

1. Create a new **GitHub repo** (e.g. `yt-dashboard-app`) and push this folder:

   ```
   cd yt-dashboard-app
   git init -b main
   git add -A
   git commit -m "Android app v1: videos, chat, prompts, results"
   git remote add origin https://github.com/<you>/yt-dashboard-app.git
   git push -u origin main
   ```

2. The **Build Android APK** workflow runs automatically. When it finishes:
   - Download the APK from the run's **Artifacts**, or
   - Grab it from the repo's **Releases → Latest APK**.

3. On your phone, open the APK and allow "install from unknown sources".

The repo intentionally contains only `pubspec.yaml` + `lib/` — the workflow
runs `flutter create --platforms=android .` in CI to generate the Gradle
boilerplate, so there's nothing platform-specific to maintain in git.

## First-run setup in the app

1. Open the app → it shows the Setup screen.
2. Server URL: your Space's **direct** URL, e.g. `https://<user>-<space>.hf.space`
   (not the huggingface.co page).
3. App password: the same `APP_PASSWORD` as the web login.
4. Tap **Save & test connection**, then pick a model in Settings.

## Local development (optional)

With the Flutter SDK installed:

```
flutter create --platforms=android --org com.fidelkey --project-name yt_dashboard_app .
flutter pub get
flutter run
```
