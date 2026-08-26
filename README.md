# Mi Asistencia

Mobile-first Flutter Web application for managing sports-team sessions and
attendance. The interface is in Spanish; source code and internal data keys are
in English.

Coaches create teams (with collision-safe invite codes), schedule single or
recurring sessions, and track who showed up. Players join a team via an invite
code or QR link and mark themselves attending, injured, late, or absent — with
missing records resolving to "attending" by default. A roster dashboard gives
coaches live counts, notes, timestamps, and per-player overrides.

## Features

- Email/password registration and sign-in with Firebase Auth.
- Google sign-in and password reset by email.
- Team creation with collision-safe six-character invite codes.
- Team joining through an invite code or a QR-code invite link.
- Coach creation of single or recurring sessions.
- Player attendance updates for one or several sessions at once.
- Coach roster dashboard with live counts, notes, timestamps, and overrides.
- Presumed attendance: missing attendance records resolve to `attending`.

## Tech stack

- [Flutter](https://flutter.dev) Web (Dart SDK ^3.12)
- [Firebase](https://firebase.google.com) Auth, Firestore, Hosting, and
  Cloud Functions (Node.js 22, TypeScript)
- [Riverpod](https://riverpod.dev) for state management
- [go_router](https://pub.dev/packages/go_router) for navigation

## Prerequisites

- Flutter (Dart SDK ^3.12)
- A Firebase project with **Authentication**, **Firestore**, and **Hosting**
  enabled
- [FlutterFire CLI](https://firebase.flutter.dev/docs/cli) (optional, for
  `flutterfire configure`)
- [Firebase CLI](https://firebase.google.com/docs/cli) (`firebase-tools`)
- Node.js 22 (only if you use the Cloud Functions backend)

## Setup

```powershell
# 1. Clone and install Flutter dependencies
git clone https://github.com/GF3000/MiAsistencia.git
cd MiAsistencia
flutter pub get

# 2. Point the app at your Firebase project
#    Replace the values in lib/firebase_options.dart with your own project's
#    Web config (find them in Firebase Console > Project settings > Your apps).

# 3. Deploy Firestore rules, indexes, and hosting
firebase login
firebase deploy --only firestore:rules,firestore:indexes,hosting

# 4. Run locally in the browser
flutter run -d chrome
```

The Firebase web configuration lives in `lib/firebase_options.dart`. Firestore
rules and indexes are managed through `firestore.rules` and
`firestore.indexes.json`.

Before using Google sign-in, enable Google in **Firebase Console >
Authentication > Sign-in method** and verify that every deployment host is
listed under **Authentication > Settings > Authorized domains**.

## Cloud Functions (optional)

The `functions/` package contains a one-off backend for migrating the legacy
single-team data schema to the current multi-team `teamMemberships` schema,
plus a temporary compatibility trigger. It is not required to run the app; see
[`functions/README.md`](functions/README.md) for setup, deployment, and usage.

## Validation and deployment

```powershell
flutter analyze
flutter test
flutter build web
firebase deploy --only firestore:rules,firestore:indexes,hosting
```

## License

Released under the [MIT License](LICENSE).
