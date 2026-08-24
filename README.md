# Mi Asistencia

Mobile-first Flutter Web application for managing sports-team sessions and
attendance. The interface is in Spanish; source code and internal data keys are
in English.

## Features

- Email/password registration and sign-in with Firebase Auth.
- Google sign-in and password reset by email.
- Team creation with collision-safe six-character invite codes.
- Team joining through an invite code.
- Coach creation of single or recurring sessions.
- Player attendance updates for one or several sessions.
- Coach roster dashboard with live counts, notes, timestamps, and overrides.
- Presumed attendance: missing attendance records resolve to `attending`.

## Local development

```powershell
flutter pub get
flutter run -d chrome
```

The Firebase web configuration is stored in `lib/firebase_options.dart`.
Firestore rules and indexes are managed through `firestore.rules` and
`firestore.indexes.json`.

Before using Google sign-in, enable Google in **Firebase Console >
Authentication > Sign-in method** and verify that every deployment host is
listed under **Authentication > Settings > Authorized domains**.

## Validation and deployment

```powershell
flutter analyze
flutter test
flutter build web
firebase deploy --only firestore:rules,firestore:indexes,hosting
```
