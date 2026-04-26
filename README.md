# Alert_Sys_App (AlertSys)

Flutter-based industrial alert management app with **role-based access** (Admin / Supervisor), **Firebase authentication + database**, and **push notifications** (FCM). Supervisors can claim/resolve alerts, request collaboration/assistance, and optionally get **AI resolution suggestions**.

## Features

- **Authentication & roles**: Firebase Auth + role routing (`admin` / `supervisor`)
- **Alerts workflow**: receive → claim → in progress → resolved / suspended
- **Collaboration**: request/offer assistance between supervisors
- **Notifications**:
  - Firebase Cloud Messaging (FCM) token stored under `users/{uid}`
  - In-app navigation to alert details on notification tap
- **AI Assist (optional)**: resolution suggestions via a remote proxy endpoint (Gemini)
- **Shorebird**: configured for code-push updates (`shorebird.yaml`)

## Tech stack

- **Flutter** (Dart SDK `>=3.0.0 <4.0.0`)
- **Firebase**: `firebase_core`, `firebase_auth`, `firebase_database`, `cloud_firestore`, `firebase_messaging`
- **State management**: `provider`
- **Web hosting (optional)**: Firebase Hosting (`build/web`)

## Project structure (high level)

- `lib/main.dart`: app entrypoint, Firebase init, role-based routing
- `lib/screens/`: UI screens (login, dashboards, alert details, admin views)
- `lib/services/`: Firebase/FCM/AI services
- `lib/providers/`: app state (alerts, theme)
- `functions/`: Firebase Functions workspace (present, currently minimal)

## Prerequisites

- **Flutter SDK** installed and on PATH
- **Android Studio** (for Android emulator + SDK) and/or a physical Android device
- **Firebase project** (this repo includes FlutterFire options already)
- Optional for web deploy: **Firebase CLI**

## Firebase setup

This project already contains FlutterFire configuration in `lib/firebase_options.dart`.

- **Android**: `android/app/google-services.json` is present.
- **iOS**: `ios/Runner/GoogleService-Info.plist` is **not** in this repo (you’ll need to add it if you want to run on iOS).

If you need to regenerate Firebase config for your own Firebase project, use FlutterFire CLI:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

## Install dependencies

From the project root:

```bash
flutter pub get
```

## Run the app

### Run on Android

Start an emulator (or connect a device), then:

```bash
flutter run
```

### Run on Windows (desktop)

Enable Windows desktop (one-time on your machine) and run:

```bash
flutter config --enable-windows-desktop
flutter run -d windows
```

### Run on Web

```bash
flutter run -d chrome
```

## Build outputs

- **Android APK (debug/release)**:

```bash
flutter build apk
```

- **Web build (for Firebase Hosting)**:

```bash
flutter build web
```

## Deploy (optional)

### Firebase Hosting (web)

The `firebase.json` is configured to serve `build/web`.

```bash
firebase login
firebase init hosting   # only if you haven't linked a project yet
flutter build web
firebase deploy --only hosting
```

## Configuration notes

- **AI Assist endpoint**: implemented in `lib/services/ai_service.dart` and currently points to a hosted proxy URL. If you change or self-host it, update `_workerUrl`.
- **Remote config**: `lib/services/config_service.dart` fetches config from a remote URL (used for things like OneSignal ID).
- **FCM tokens**: stored in Realtime Database under `users/{uid}` (see `lib/services/fcm_service.dart`).

## Common troubleshooting

- **Stuck on login / role not found**: the app expects a user record at `users/{uid}` with a valid `role` (`admin` or `supervisor`). Missing/invalid role will force sign-out.
- **FCM not receiving messages on Android**:
  - Ensure `google-services.json` matches the Firebase project you are using
  - Verify the device has a token saved under `users/{uid}/fcmToken`
- **iOS build fails**: add `ios/Runner/GoogleService-Info.plist` (not included here) and re-run `flutter pub get`.