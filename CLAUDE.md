# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

Mi Asistencia is a mobile-first **Flutter Web** app for sports-team session
and attendance management, backed by **Firebase** (Auth, Firestore, Hosting,
Cloud Functions). Coaches create teams and sessions; players join with an
invite code / QR link and set their attendance. Core rule: **presumption of
attendance** — a player with no attendance record for a session counts as
`attending`.

## Language conventions

- **All user-facing text is Spanish** (labels, buttons, errors, snackbars,
  tooltips). Keep accents and natural phrasing.
- **Code, identifiers, comments, commit messages and Firestore keys/values
  are English** (e.g. `absent_unannounced`, `teamMemberships`).
- Commits use Conventional Commits: `feat: …`, `fix: …`, `refactor: …`.

## Layout

```
lib/
  main.dart, firebase_options.dart
  src/
    app.dart            MaterialApp.router + theme
    providers.dart      Riverpod providers (repositories, streams, derived state)
    router/             go_router config (app_router.dart) + auth/team gate (gate_state.dart)
    models/             Plain Dart models + Firestore mapping (attendance, team_session, team_membership, player_tag, ...)
    repositories/       All Firestore/Auth access (auth, team, session, attendance, player_tag)
    screens/            One file per route
    widgets/            Reusable UI (attendance editor, calendar, charts, tables, ...)
    theme/, utils/      Theme; CSV export, web file download (conditional import), search, invites
test/                   Flutter unit + widget tests (flat, *_test.dart)
functions/              Cloud Functions v2 (TypeScript, Node 22) — see functions/README.md
firestore.rules         Security rules (large; authorization lives here)
firestore.indexes.json  Composite indexes
first_prompt.md         ORIGINAL product spec (historical; names "SquadLog", BLoC, email-only auth — outdated, do not treat as current)
```

UI code never talks to Firestore directly: screens/widgets → providers →
repositories.

## Data model (Firestore)

- `users/{uid}` — profile, `activeTeamId`.
- `teams/{teamId}` — team; subcollections `attendanceIndex/{memberId}`,
  `playerTags`, `playerTagAssignments`.
- `teamMemberships/{teamId}__{memberId}` — role (coach/player), active,
  membership periods, `managedByCoach`, default attendance. **Authoritative
  source for authorization** (rules and app).
- `teamInvites/{teamId}` — the team's current six-character invite code.
- `sessions/{sessionId}` (with `teamId`, optional `kind`: `training` |
  `match`; missing = training) and `sessions/{id}/attendance/{memberId}`.
- `sessionSeries/{id}` — recurring sessions.

Attendance statuses (`AttendanceStatus` in `lib/src/models/attendance.dart`,
stored as `firestoreValue`): `attending`, `injured`, `court_only`, `gym_only`,
`late`, `absent`, `late_unannounced`, `absent_unannounced`,
`absent_late_notice`, `no_convocado`. `notApplicable` is UI-only and throws if
stored. **If you add or rename a status, also update
`ATTENDANCE_STATUS_VALUES` in `functions/src/attendanceIndex.ts`** and the
rules (`hasValidAttendanceShape`), and deploy functions + rules before the
client that writes it.

Matches vs trainings: a match reuses the same statuses with match labels
(`AttendanceStatus.labelIn(kind, …)`). Every player is **presumed called up
and available** (`attending` = "Disponible" for the player, "Convocado" for
the coach); the player may mark `absent` ("No disponible") or `injured`; the
coach marks `no_convocado` (locks the player) or `absent_unannounced`.
Training-only statuses on a session later turned into a match collapse via
`inKind`. Matches never count towards the attendance % or training columns.

### Attendance index (app depends on Cloud Functions)

`teams/{teamId}/attendanceIndex/{memberId}` holds a `{ sessionId: status }`
map per player so history/stats/CSV read one doc per player instead of one
listener per session. It is written **only by Cloud Functions** (client
read-only):

- `attendanceIndexSync` — mirrors writes to `sessions/*/attendance/*`.
- `attendanceIndexSessionCleanup` — removes a deleted session's entries.
- `attendanceIndexRebuild` — token-protected HTTPS backfill (`dryRun`/`apply`).

So the functions are **not optional** for a working app: without them player
history and stats go stale.

## Commands

Flutter (repo root):

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
flutter build web
```

Cloud Functions:

```powershell
npm --prefix functions run lint
npm --prefix functions run build
npm --prefix functions test     # unit only; emulator suites need FIRESTORE_EMULATOR_HOST
```

Run `flutter analyze` and `flutter test` before declaring Dart changes done;
run lint + build + test in `functions/` for TypeScript changes. The local Node
may be newer than the `engines: 22` pin; that's fine for lint/build/test.

## Firebase / deployment

- Firebase project: `mi-asistencia-c8854` (`.firebaserc` default).
- Hosting: primary site **`miasistencia-bmcoras`** (serves `build/web`); the
  legacy site `mi-asistencia-c8854` only 301-redirects to it.
- Firestore `eur3`; functions in `europe-west1`.
- Deploys touch production. **Do not deploy, run the migration/rebuild
  endpoints, or change secrets (`MIGRATION_TOKEN`) without explicit user
  approval.**

```powershell
flutter build web
firebase deploy --only firestore:rules,firestore:indexes,hosting
firebase deploy --only functions   # may need --force for functions with retry policies
```

## Gotchas

- Session/calendar day math must be DST-safe (see commit 5c47082): build dates
  with `DateTime(y, m, d + n)`, never by adding `Duration(days: n)`.
- Security rules allow at most 20 document accesses (`get`/`exists`) per
  request — a client batch counts as one request. Rules that look up a
  document per written doc break on large batches; keep per-doc lookups out of
  rules on bulk paths and split batches per session (see commit 7d8a47f).
- Coach-managed players have a `memberId` but no `userId`; don't assume every
  member has an auth account.
- `lib/src/utils/file_download.dart` uses conditional imports
  (`_web` / `_stub`) so tests run on the VM.
