# narrate_my (Collab)

A Flutter application. This guide covers everything needed to get the project running from a completely clean machine, plus fixes for the setup issues this project is known to hit after cloning.

## 1. Prerequisites

| Tool | Why you need it | Notes |
|---|---|---|
| **Flutter SDK** | Builds and runs the app | Must be **Dart 3.11.5 or newer** (check `pubspec.yaml` → `environment: sdk:`). This project uses newer Dart syntax ("dot shorthands"), so an old cached Flutter install will fail to compile it. |
| **Android Studio** | Provides the Android SDK, an emulator, and Gradle tooling | Required even if you plan to code in VS Code — it's the easiest way to install/manage the Android SDK. |
| **A JDK (17 or newer, 21 recommended)** | Required by Gradle 9.x / AGP 8.11.x used in this project | Android Studio bundles its own JDK (JBR), which is usually sufficient — you don't need to install one separately unless `flutter doctor` says otherwise. |
| **Xcode** (Mac only, optional) | Only needed if you want to run on iOS/an iOS simulator | Not required for Android. |
| **Git** | To clone the repo | — |

## 2. Install Flutter

1. Download Flutter from [flutter.dev/get-started/install](https://flutter.dev/get-started/install) for your OS.
2. Extract/install it, then add the `flutter/bin` folder to your system `PATH`.
3. Verify:
   ```
   flutter --version
   ```
   Confirm the reported Dart version is **3.11.5+**. If it's older:
   ```
   flutter upgrade
   ```

## 3. Install Android Studio + Android SDK + Emulator

1. Download and install [Android Studio](https://developer.android.com/studio).
2. On first launch, go through the **Setup Wizard** — let it install the Android SDK, SDK Platform-Tools, and a default emulator image.
3. Open **SDK Manager** (More Actions → SDK Manager, or Tools → SDK Manager if a project is open) → **SDK Tools** tab → check **"Android SDK Command-line Tools (latest)"** → Apply.
   - This step is easy to miss and causes: `Android sdkmanager not found. ... cmdline-tools component is missing.`
4. Open **Device Manager** and create at least one Android Virtual Device (AVD), e.g. Pixel 8 / API 34+.

## 4. Accept Android licenses

```
flutter doctor --android-licenses
```
Type `y` to accept each license prompt. If this fails with a `cmdline-tools missing` error, go back to step 3.4 above first.

## 5. Clone and set up the project

```
git clone <repo-url>
cd Collab
flutter pub get
```

### ⚠️ Known issue: `android/local.properties`

This repo has previously shipped with a **stale, developer-specific** `android/local.properties` file (it's supposed to be git-ignored). If you see Gradle errors referencing a path like `C:\Users\<someone-else>\...`, delete the file:

```
del android\local.properties      # Windows
rm android/local.properties       # macOS/Linux
```

Flutter/Android Studio regenerates it automatically with your machine's correct `sdk.dir` and `flutter.sdk` paths the next time you sync/run — you never need to write it by hand.

## 6. Verify your setup

```
flutter doctor -v
```
Every line (Flutter, Android toolchain, Android Studio, Connected device) should show a green checkmark before continuing. Fix anything marked `[!]` or `[✗]` — the command tells you exactly what's missing.

## 7. Run the app

1. Start your emulator:
   ```
   flutter emulators --launch <emulator_id>
   ```
   (or launch it from Android Studio's Device Manager)
2. Confirm it's visible:
   ```
   flutter devices
   ```
3. Run:
   ```
   flutter run
   ```

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Gradle sync fails referencing another user's file path | Stale `android/local.properties` | Delete the file (see step 5) and re-sync |
| `Android sdkmanager not found` / `cmdline-tools component is missing` | Command-line tools not installed | Android Studio → SDK Manager → SDK Tools → install "Android SDK Command-line Tools (latest)" |
| `Android license status unknown` | Licenses not accepted | `flutter doctor --android-licenses` |
| Build errors around `.fromSeed(...)` / `.center` syntax in `main.dart` | Flutter/Dart SDK too old | `flutter upgrade` (needs Dart 3.11.5+) |
| Gradle/JDK version errors | Wrong JDK selected in Android Studio | Android Studio → Settings → Build Tools → Gradle → set Gradle JDK to 17+ (21 recommended), or use the bundled JBR |
| No devices found | No emulator running / not created | Create + launch an AVD via Android Studio's Device Manager |

## Project structure

```
lib/
  main.dart          # App entry point
  Model/              # Entities, repositories, business logic
  ViewModel/           # View models
  View/                # Screens/widgets
```
