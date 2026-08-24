MiAsitencia - Team Attendance Management Web App

1. Executive Summary & Core Concept

SquadLog is a mobile-first web application designed for sports coaches and players to efficiently manage team attendance for training sessions and matches.

The application is built around the presumption of attendance principle: every rostered player is assumed to be attending every scheduled session unless they explicitly submit a status change.

2. Technical Stack & Deployment

Layer

Technology

Frontend Framework

Flutter Web (Mobile-First Responsive Design)

Authentication

Firebase Auth (Email & Password)

Database

Cloud Firestore

Hosting

Firebase Hosting

State Management

Flutter Riverpod / BLoC

3. Localization & Language Standard

To maintain clean code standards while serving native Spanish users:

User Interface & Copy: 100% Spanish (ES). All buttons, status text, form labels, tooltips, and validation alerts must be written in natural Spanish.

Codebase, Architecture & Documentation: 100% English (EN). All class names, file structures, variable names, database keys, Git commits, comments, and internal docs must be in English.

4. User Roles & Onboarding Workflow

4.1 User Roles

admin: Can create/delete sessions, create recurring series, edit any player's attendance record, view team code, and manage team roster. Multiple admins are supported per team.

player: Can view team schedule, update their own attendance status/note for single sessions, and batch-update attendance across multiple selected sessions.

4.2 Onboarding Logic Flow

Registration/Login: User registers via Email & Password.

Auth Gate Check:

If user.teamId == null $\rightarrow$ Route to Team Selection Screen (/onboarding).

If user.teamId != null $\rightarrow$ Route to main dashboard based on role (/admin or /player).

Team Selection Options:

Option A — Create Team (Crear equipo):

Admin enters Team Name.

App generates a unique 6-character uppercase alphanumeric code (e.g., K9X2P4), excluding ambiguous characters (0, O, 1, I, L).

App creates a new document in teams collection.

User profile is updated: teamId = newTeam.id, role = 'admin'.

Option B — Join Team (Unirse a un equipo):

Player enters 6-character team code.

App validates the code against teams.where('joinCode', '==', inputCode.toUpperCase()).

User profile is updated: teamId = matchedTeam.id, role = 'player'.

5. Domain Logic & Data Model

5.1 Firestore Data Schema

teams/{teamId}
  - name: string
  - joinCode: string (6-char uppercase, indexed)
  - createdBy: string (uid)
  - createdAt: timestamp

users/{userId}
  - email: string
  - fullName: string
  - role: string ("admin" | "player")
  - teamId: string | null
  - active: boolean
  - createdAt: timestamp

sessions/{sessionId}
  - teamId: string
  - title: string
  - startTime: timestamp
  - endTime: timestamp
  - recurrenceSeriesId: string | null
  - createdAt: timestamp

sessions/{sessionId}/attendance/{userId}
  - status: string ("attending" | "injured" | "court_only" | "gym_only" | "late" | "absent")
  - note: string | null
  - updatedBy: string (uid)
  - updatedAt: timestamp


5.2 Attendance Status Mapping

Database Value (status)

Spanish UI Label

Description

attending

Asiste

Default state (no record required in Firestore).

injured

Lesionado

Player is injured and cannot participate.

court_only

Solo pista

Player participates only in court drills.

gym_only

Solo físico

Player participates only in physical conditioning.

late

Llego tarde

Player will arrive late (can add exact arrival in note).

absent

No asisto

Player will not attend.

5.3 Presumption of Attendance Algorithm

To keep write operations minimal and avoid bulk document generation:

When rendering session attendance, read all active team users where teamId == currentTeamId.

Fetch existing documents in sessions/{sessionId}/attendance.

Perform a client-side join:

If a user has a subdocument in attendance, display their saved status, note, and updatedAt.

If no subdocument exists, resolve their status as attending with updatedAt = null.

6. Detailed Feature Requirements

6.1 Admin Features

Create Single/Recurring Sessions:

Single session: Title, date, start time, end time.

Recurring series: Repeat on specific day(s) of the week for $N$ weeks. The app creates $N$ session documents with a shared recurrenceSeriesId.

Attendance Dashboard:

View roster list for any selected session with real-time attendance counts (Attending, Late, Absent, etc.).

Timestamp inspection: See exactly when a player updated their status (updatedAt).

Admin Attendance Override:

Admin can change any player's status and note for any session. Sets updatedBy = adminUid.

6.2 Player Features

Schedule View:

Chronological list of upcoming team sessions with current personal status badge.

Single Session Status Update:

Tap session $\rightarrow$ Select status $\rightarrow$ Add optional note $\rightarrow$ Save.

Batch Attendance Update (Actualización en lote):

Player can multi-select sessions (e.g., all Wednesday sessions for the month).

Apply a single status and note (e.g., "Llego tarde", note: "Llego 15 mins tarde por trabajo") across all selected sessions in one atomic WriteBatch.

7. Security Rules (firestore.rules)

rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isAuthenticated() {
      return request.auth != null;
    }

    function getUserData() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data;
    }

    function isAdmin() {
      return isAuthenticated() && getUserData().role == 'admin';
    }

    function belongsToSameTeam(teamId) {
      return isAuthenticated() && getUserData().teamId == teamId;
    }

    // Teams Collection
    match /teams/{teamId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update, delete: if isAdmin() && resource.data.createdBy == request.auth.uid;
    }

    // Users Collection
    match /users/{userId} {
      allow read: if isAuthenticated();
      allow create, update: if isAuthenticated() && (request.auth.uid == userId || isAdmin());
    }

    // Sessions Collection
    match /sessions/{sessionId} {
      allow read: if isAuthenticated() && belongsToSameTeam(resource.data.teamId);
      allow create, update, delete: if isAdmin();

      // Attendance Subcollection
      match /attendance/{userId} {
        allow read: if isAuthenticated();
        allow write: if isAuthenticated() && (request.auth.uid == userId || isAdmin());
      }
    }
  }
}


8. Mobile Web UI Guidelines

Mobile Viewport Optimization: Form factors must be optimized for mobile web browsers (Safari on iOS, Chrome on Android).

Touch Targets: Minimum 48x48px touch targets for status selector chips and action buttons.

Fast Input: Quick status toggles with single-tap updates.

Code Input UI: The 6-digit join code input should use auto-uppercase formatting and letter spacing for legibility.