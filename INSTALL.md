# Installing & Running the YT Dashboard App

## A. Install the APK on an Android phone

1. On the phone, open the browser and go to
   `https://github.com/fgzakey/yt-dashboard-app/releases` → **Latest APK** → download `app-release.apk`.
   (Alternative: download on the PC and copy to the phone via USB/OneDrive, then open it with the Files app.)
2. Tap the downloaded file. Android will ask to allow installs from that app
   (Chrome or Files) → **Settings → Allow from this source** → back → **Install**.
3. If Google Play Protect warns about an unknown developer: tap
   **More details → Install anyway**. (Expected — the APK is self-built, not from Play.)
4. Open the app → Setup screen:
   - **Server URL**: your Space's direct URL, e.g. `https://<user>-<space>.hf.space`
   - **App password**: same as the web login (`APP_PASSWORD`)
   - Tap **Save & test connection**, then pick a model in Settings.

### Updating to a newer build — important

Each CI run signs with a freshly generated debug keystore, so a new APK has a
**different signature**: installing it over the old one fails with
"App not installed". **Uninstall the old app first**, then install the new APK
(you'll re-enter server URL/password — everything else lives in the shared DB).
If this gets annoying, add a persistent signing keystore as a GitHub secret later.

## B. Run in Android Studio with a Pixel Tablet emulator (Windows)

### 1. Install the tools

1. **Android Studio**: https://developer.android.com/studio → install with
   defaults (includes Android SDK + emulator).
2. **Flutter SDK**: https://docs.flutter.dev/get-started/install/windows →
   download the zip and extract to `C:\dev\flutter` (path must have **no spaces**).
3. Add `C:\dev\flutter\bin` to your PATH:
   Start → "Edit environment variables for your account" → Path → New → `C:\dev\flutter\bin`.
4. Open a **new** terminal and run:
   ```
   flutter doctor
   flutter doctor --android-licenses   (accept all with y)
   ```
5. In Android Studio: **File → Settings → Plugins** → install **Flutter**
   (installs Dart too) → restart.

### 2. Get the project

Clone to a plain local path — **not** inside OneDrive (sync interferes with builds):

```
cd C:\dev
git clone https://github.com/fgzakey/yt-dashboard-app.git
cd yt-dashboard-app
flutter create --platforms=android --org com.fidelkey --project-name yt_dashboard_app .
flutter pub get
```

The `flutter create` step generates the `android/` folder locally (the repo
doesn't ship it — CI generates its own). It's git-ignored, so it never gets committed.

### 3. Create the Pixel Tablet virtual device

1. Android Studio → **Open** → select `C:\dev\yt-dashboard-app`.
2. **Tools → Device Manager** → **+ / Create Virtual Device**.
3. Category **Tablet** → **Pixel Tablet** → Next.
4. Pick the latest stable system image (click the download icon next to it) → Next → Finish.
5. Press the ▶ button in Device Manager to boot the emulator.

### 4. Run the app

1. In the toolbar, select the **Pixel Tablet** in the device dropdown.
2. Press **Run ▶** (or in a terminal: `flutter run`).
3. The app starts on the emulator; enter the Server URL + password as on the phone.
   The emulator has normal internet access, so the HF Space works directly.

Hot reload: save a file and press `r` in the terminal (or the ⚡ button) to see
changes instantly.
