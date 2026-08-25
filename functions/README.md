# MiAsistencia Cloud Functions — Phase 2: multi-team data migration

This package contains the Cloud Functions (v2, Node.js 22, TypeScript)
backend for migrating the legacy single-team `users/{userId}` schema into
the new top-level `teamMemberships/{teamId}__{memberId}` schema, plus a
temporary compatibility trigger that keeps both schemas in sync while old
Flutter clients are still in the field.

It intentionally does **not** touch `firestore.rules` or the Flutter app —
those are handled separately. This backend can be deployed and exercised
against production data safely: `dryRun` and `verify` never write anything,
and `apply` is idempotent/resumable and never overwrites data it doesn't
recognize.

## What gets migrated

For every `users/{userId}` document that has a `teamId`:

- A `teamMemberships/{teamId}__{userId}` document is created with
  `teamId`, `memberId` (= the legacy user doc id, preserved exactly, so
  `sessions/*/attendance/{memberId}` keeps working), a nullable `userId`
  (`null` for coach-managed players, the legacy id otherwise), `fullName`,
  `email`, `role`, `active`, `managedByCoach`, `membershipPeriods`,
  `attendanceDefaultStatus`/`attendanceDefaultHistory`, `createdAt`,
  `updatedAt`, and `migrationVersion: 2`.
- `users/{userId}` gains `activeTeamId` (= the legacy `teamId`) and
  `schemaVersion: 2`. **No other legacy field is touched or removed.**

Users without a `teamId` are skipped (nothing to migrate yet — they'll be
picked up automatically once they join a team, either via the future V2
client or via the compatibility trigger below).

### Join/leave date semantics (read this before running `apply`)

- `membershipPeriods[0].joinedAt` is `teamJoinedAt` if present, otherwise
  `createdAt`. **If neither is set, the user is never migrated** — it is
  recorded as a `missing_join_timestamp` conflict instead. We never invent
  a `1970-01-01` (or any other) join date.
- Active users (`active == true`) get a single **open** period
  (`leftAt: null`).
- Inactive users (`active == false`) have no legacy "left at" timestamp to
  draw on, so instead of guessing one per user, **every inactive member
  migrated by the same run is closed at one fixed instant**: the run's
  `migrations/multiTeamV2.startedAt` timestamp (recorded once, the first
  time `apply` runs or resumes). This keeps a run byte-for-byte
  reproducible. If a member's `joinedAt` is somehow after that instant, the
  period is closed immediately at `joinedAt` instead of producing an
  inverted `[joinedAt, leftAt)` range.

## Prerequisites

```powershell
cd functions
npm install
```

Node 22 is the deployed runtime (`engines.node` in `package.json`); your
local Node version can be newer for `npm install`/build/test.

## 1. Set the migration secret

The HTTP endpoint is deployed as publicly invokable (`invoker: "public"`,
reachable from the internet) but is useless without this secret — every
request is rejected with `401` unless it presents it via a constant-time
comparison. See **Security model** below for the implications of
`invoker: "public"`.

```powershell
firebase functions:secrets:set MIGRATION_TOKEN
# Paste a long random value when prompted. Generate one (PowerShell only,
# no external tools) with:
#   -join (1..48 | ForEach-Object { [char](Get-Random -InputObject ((48..57)+(65..90)+(97..122))) })
```

That generator draws 48 characters, **with replacement**, from the 62
alphanumerics (`0-9A-Za-z`) — ~285 bits of entropy. (The previous
`Get-Random -Count 40` recipe was broken: `Get-Random -Count` samples
*without replacement* from the 36-character pool `0-9a-z`, so it can never
return more than 36 characters, every character appears at most once, and
the output is just a random permutation of a known multiset — far less
entropy than the intended 40-character random string.)

Never commit the secret value anywhere (not in `.env`, not in this repo).
Firebase stores it in Secret Manager and injects it into the function at
runtime via `defineSecret`.

## 2. Build, lint, test

```powershell
cd functions
npm run lint
npm run build
npm test
```

`npm test` runs the **unit** tests only. The emulator-backed integration
suites (`test/*.emulator.test.ts`) are **skipped** unless
`FIRESTORE_EMULATOR_HOST` is set — this is deliberate so a plain
`npm install && npm test` passes without the emulator, but it also means a
bare `npm test` gives you *no* integration coverage. To actually run them:

```powershell
# Terminal 1 — start the Firestore emulator (needs a JDK on PATH):
cd ..            # repo root, where firebase.json lives
firebase emulators:start --only firestore --project demo-migration-test

# Terminal 2 — point the tests at it and run the whole suite:
cd functions
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
npm test
```

When the variable is set you will see `migration.emulator.test.ts`,
`migrationResume.emulator.test.ts` and `compatTrigger.emulator.test.ts` run
(not skipped) in the Jest output — that is your confirmation the integration
tests really executed. They use the Admin SDK directly against the emulator
(no `firestore.rules` involved, since the Admin SDK bypasses rules) and
cover pagination/resume, failed-user retry, the poison-page `noProgress`
guard, one-shot reset (incl. stale-conflict clearing), the checkpoint lease
(incl. `finalizePage` owner-equality), the read-only `status`/cutover gate,
and the compatibility trigger's create/update/delete/token-no-op/
non-resurrection/malformed-conflict/duplicate-delivery paths.

## 3. Deploy

```powershell
firebase deploy --only functions
```

This deploys both `multiTeamMigration` (HTTPS, `timeoutSeconds: 540`,
`memory: 512MiB`) and `legacyUserCompatSync` (Firestore
`onDocumentWritten` trigger with `retry: true`), both in `europe-west1`
(the single-region function location closest to the project's `eur3`
Firestore multi-region).

## 4. Running the migration

All requests are `POST` to the deployed function URL (find it in the
deploy output or via `firebase functions:list`), with the token in an
`Authorization: Bearer <token>` header (or `X-Migration-Token`), and a JSON
body. The response is machine-readable JSON with `counts`, `nextCursor`,
and `done`, designed for a scripted loop.

```powershell
$token = "<your MIGRATION_TOKEN value>"
$url   = "https://europe-west1-<project-id>.cloudfunctions.net/multiTeamMigration"
$headers = @{ Authorization = "Bearer $token" }
```

### Dry run (no writes at all)

Safe to run anytime, against production, as many times as you like.

```powershell
$cursor = $null
do {
  $body = @{ mode = "dryRun"; pageSize = 100; cursor = $cursor } | ConvertTo-Json
  $resp = Invoke-RestMethod -Method Post -Uri $url -Body $body -ContentType "application/json" -Headers $headers
  $resp.counts | Format-List
  if ($resp.noProgress) {
    throw "Dry run stalled on a no-progress page (cursor '$($resp.nextCursor)'). Investigate the failing user(s) before retrying."
  }
  $cursor = $resp.nextCursor
} while (-not $resp.done)
```

`dryRun` never calls a Firestore write/transaction — only `.get()` reads —
so it cannot corrupt data even if run concurrently with itself or `apply`.

### Apply (writes; paginate until `done: true`)

`apply` is checkpointed in `migrations/multiTeamV2` and resumable: if you
don't pass `cursor` in the body, it automatically continues from wherever
the last `apply` call left off. **Do not pass `reset` in this loop** (see
below). Once a run is `done`, explicit `cursor` overrides are rejected with
HTTP `400` — use one-shot `reset` for a fresh run. Run it until `done` is
`true`:

```powershell
do {
  $body = @{ mode = "apply"; pageSize = 100 } | ConvertTo-Json
  try {
    $resp = Invoke-RestMethod -Method Post -Uri $url -Body $body -ContentType "application/json" -Headers $headers
  } catch {
    # 409 = another apply run holds the lease; wait and retry the same page.
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 409) {
      Start-Sleep -Seconds 15
      continue
    }
    throw
  }
  "{0} processed, {1} migrated, {2} alreadyMigrated, {3} conflicts, {4} vanished, {5} errors" -f `
    $resp.counts.processed, $resp.counts.migrated, $resp.counts.alreadyMigrated, `
    $resp.counts.conflicts, $resp.counts.vanished, $resp.counts.errors
  # Poison-page guard: if the page could not advance because its first user
  # keeps throwing a transient error, STOP with a clear error instead of
  # retrying the same page forever. The failing user is in
  # migrationErrors/{teamId__userId} (or _record__userId); repair and re-run.
  if ($resp.noProgress) {
    throw "Migration stalled on a no-progress page (cursor '$($resp.nextCursor)'). See migrationErrors for the failing user(s); fix and re-run."
  }
} while (-not $resp.done)
```

- **Resumable / crash-safe.** Safe to stop and re-run at any time (crash,
  timeout, closed laptop) — it resumes from the stored `lastCursor` and
  never resets the run's `startedAt`.
- **Never advances past a transient failure.** If a per-user transaction
  throws (contention, Firestore unavailable), that user is recorded in
  `migrationErrors/{teamId__userId}` (or `_record__userId`), the stored cursor stops just before it, and
  `done` stays `false` so your loop keeps going and retries it. One bad
  document never fails the whole page.
- **Never spins on a poison page.** If the *first* unprocessed user on a
  page keeps throwing, the cursor cannot advance at all. The response then
  carries `noProgress: true` so the loop above stops with a clear error
  rather than retrying the identical page forever. The failing user stays in
  `migrationErrors/{teamId__userId}` (or `_record__userId`) for repair/retry.
- **Idempotent.** Already-migrated documents (`migrationVersion == 2` with
  a matching `teamId`/`memberId`) are detected and left untouched
  (`alreadyMigrated`, not re-written).
- **Never overwrites foreign data.** A document that already occupies a
  target `teamMemberships/*` id but was **not** produced by this migration
  is never overwritten — it is recorded in `migrationConflicts/{teamId__userId}`
  and counted in `counts.conflicts`.
- **Serialized.** Two `apply` calls cannot run at once: the second gets an
  HTTP `409` (a lease on the checkpoint prevents interleaved writes from
  regressing the cursor/totals). The loop above handles it by waiting.
- **Self-healing conflicts.** When a user that previously produced a
  conflict/error later migrates cleanly, its stale
  `migrationConflicts`/`migrationErrors` document is deleted.

### Resetting an `apply` run (one-shot)

Reset is a **one-shot administrative action**, *not* part of the apply
loop. A `reset: true` call discards the checkpoint (fresh `startedAt`,
`lastCursor` back to `null`, counters zeroed) and returns **immediately
with `done: true` and `reset: true`, without processing a page**:

```powershell
# Run this ONCE, on its own, before starting a fresh apply loop:
$body = @{ mode = "apply"; reset = $true } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri $url -Body $body -ContentType "application/json" -Headers $headers
# -> { ..., "reset": true, "done": true, "counts": { all zero } }

# Then run the ordinary apply loop above (WITHOUT reset).
```

Because reset returns `done: true` and processes nothing, it is impossible
to accidentally "loop resetting page 1": a `while (-not done)` loop that
mistakenly keeps sending `reset` simply stops after the first call instead
of endlessly re-zeroing the checkpoint. Reset does **not** delete any
`teamMemberships` documents already written — those remain protected by the
idempotency check on the next pass. Reset **does** clear the
`migrationConflicts` and `migrationErrors` bookkeeping collections, so a
fresh run starts from a clean slate. This is what eliminates *stale
conflicts/errors for vanished users*: a user that produced a conflict and
was then deleted can never be revisited by the ordinary apply loop (it is no
longer in `users`), so its bookkeeping doc — and therefore the cutover gate
— would otherwise stay blocked forever. Resetting before the final
apply→verify→status cycle guarantees the gate reflects only current reality.
Reset is refused with `409` if another `apply` run currently holds the
lease.

### Verify (read-only; run after `apply` reaches `done: true`)

Compares every legacy user against the membership/profile state that the
same mapping logic says it *should* have, without writing anything:

```powershell
$cursor = $null
do {
  $body = @{ mode = "verify"; pageSize = 100; cursor = $cursor } | ConvertTo-Json
  $resp = Invoke-RestMethod -Method Post -Uri $url -Body $body -ContentType "application/json" -Headers $headers
  if ($resp.mismatches.Count -gt 0) { $resp.mismatches | ConvertTo-Json -Depth 6 }
  $cursor = $resp.nextCursor
} while (-not $resp.done)
```

`counts.matched` + `counts.mismatches` + `counts.skippedNoTeam` +
`counts.conflicts` + `counts.errors` should equal `counts.processed` for
every page. A non-zero `counts.mismatches` after a fresh `apply` run
usually means either incompatible concurrent writes to
`teamMemberships`/`users` between `apply` and `verify`, or data that no
longer satisfies the migration invariants. `verify` allows richer
membership period/default-history state when it is semantically compatible
(for example, legit trigger-appended history), but still flags shape or
state mismatches that can break cutover assumptions.

### Status (read-only; the cutover gate)

`mode: "status"` returns a machine-readable snapshot for autonomous
orchestration to gate deployment/cutover on. It is **read-only** (only
`.get()` and aggregate `.count()` queries — no writes), so it is safe to
poll at any time, exactly like `dryRun`/`verify`. It ignores every body
field except `mode`:

```powershell
$body = @{ mode = "status" } | ConvertTo-Json
$resp = Invoke-RestMethod -Method Post -Uri $url -Body $body -ContentType "application/json" -Headers $headers
$resp | ConvertTo-Json -Depth 6
# {
#   "mode": "status",
#   "checkpoint": { "exists": true, "status": "done", "lastCursor": null,
#                   "totals": { ... }, "leaseHeld": false, ... },
#   "conflicts": { "total": 0, "unresolved": 0 },
#   "errors":    { "total": 0, "unresolved": 0 },
#   "cutoverReady": true
# }
```

`cutoverReady` is `true` **only** when the checkpoint `status` is `done`
**and** there are zero *unresolved* conflicts and zero *unresolved* errors.
This is the hard gate for the upcoming rules phase (see **Authorization
authority & the hard cutover gate** below): do not cut `firestore.rules`
over to the membership schema while `cutoverReady` is `false`.

Because a conflict/error for a *vanished* user is never auto-resolved by the
apply loop (that user is gone from `users`), the canonical cutover procedure
is: **one-shot `reset`** (which also clears stale conflicts/errors) →
**`apply`** until `done` → **`verify`** → **`status`** until
`cutoverReady: true`.

### curl equivalents

```bash
URL="https://europe-west1-<project-id>.cloudfunctions.net/multiTeamMigration"
TOKEN="<your MIGRATION_TOKEN value>"

# dry run
curl -X POST "$URL" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"mode":"dryRun","pageSize":100}'

# one-shot reset
curl -X POST "$URL" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"mode":"apply","reset":true}'

# apply one page (repeat until "done":true; retry on HTTP 409)
curl -sS -w '\n%{http_code}\n' -X POST "$URL" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"mode":"apply","pageSize":100}'
```

No `gcloud` is required for any of the above — a bearer token over HTTPS is
the entire auth story.

```bash
# status (cutover gate) — read-only
curl -X POST "$URL" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"mode":"status"}'
```

## 5. The old-client compatibility trigger

`legacyUserCompatSync` (`onDocumentWritten` on `users/{userId}`) is a
**temporary** bridge, not the app's permanent consistency mechanism. It
fires on **create, update, and delete**:

- **Create** with a `teamId` provisions the membership document.
- **Update** mirrors team switches, join/leave/reactivate/deactivate, and
  profile fields.
- **Delete** closes the trailing open `membershipPeriod` and marks the
  membership `active: false` (important for coach-managed players whose
  whole account is a `users/*` doc), **preserving all prior history**.

Once the future V2 Flutter client writes `teamMemberships` and the legacy
mirror atomically itself, it will also bump a `membershipWriteToken` field
on the user document as part of that same transaction — the trigger detects
that token change and no-ops immediately, doing nothing. The **migration**
does the same: when `apply` writes the `activeTeamId`/`schemaVersion` profile
mirror it bumps `membershipWriteToken` in the *same* transaction, so the
user-doc write it causes makes this trigger no-op cheaply on its first check
instead of recomputing a membership the migration just wrote.

For writes from a genuinely old client, the trigger:

- **Recomputes from fresh state.** It re-reads the *current* user document
  inside its transaction and computes the target from that, not from the
  event's immutable `after` snapshot, so an out-of-order or redelivered
  event cannot regress the membership or profile.
- **Reconciles active vs. open period.** After computing the plan it
  guarantees the merged membership's open/closed state matches `active`: an
  active member always has an open period (opened at the event time if one
  is missing), an inactive one never does (the trailing period is closed).
  This also makes a team switch into an existing *inactive* membership safe
  (no spurious open period) and repairs a doc that drifted out of sync.
- **Never deletes/shrinks** `membershipPeriods` or
  `attendanceDefaultHistory` — it only appends a period or fills `leftAt`
  on the trailing one — and never lets a shorter/older legacy history
  overwrite a longer one already stored.
- **Never invents a join date** — a create/switch without a
  `teamJoinedAt`/`createdAt` is recorded as a `missing_join_timestamp`
  conflict in `migrationConflicts/{teamId__userId}` instead of guessing.
- **Records malformed documents as durable conflicts** — if the event
  `before` snapshot *or* the fresh current user document fails validation,
  the trigger records an `invalid_legacy_record` conflict in
  `migrationConflicts/{_record__userId}` and ends,
  rather than only logging. That conflict then blocks the cutover gate until
  the record is repaired.
- **Never overwrites foreign data** — it applies the same
  ownership/version guard as the migration and records a *blocking*
  `membership_exists_incompatible` conflict rather than stamping a
  non-V2/foreign membership document. It never rewrites a foreign document,
  not even to "revoke" it.
- **Cannot loop** — it only writes when the computed target differs from
  current stored state, and its own user-doc write bumps
  `membershipWriteToken`, which makes the resulting re-trigger no-op on its
  very first check.
- **Does not swallow failures.** A conflict/malformed document is recorded
  and the delivery ends cleanly, but a genuine infrastructure failure
  (transaction contention, Firestore unavailable) is rethrown so Cloud
  Functions retries the (idempotent) delivery — `retry: true` enables that.

The Firestore-transaction body is factored out as the exported
`handleLegacyUserCompatWrite`, which the deployed trigger calls and the
emulator suite (`test/compatTrigger.emulator.test.ts`) exercises directly:
create/update/delete, the token no-op, deleted-user non-resurrection, the
malformed-record conflict, and duplicate delivery.

See `src/compatDecision.ts` for the full (pure, unit-tested) decision logic
and `src/compatTrigger.ts` for the Firestore-transaction wiring.

## Concurrency & the checkpoint lease

`apply` acquires a short-lived lease (`migrations/multiTeamV2.lease`,
TTL 15 min > the 540s function timeout) before touching a page and releases
it when the page finishes. A second concurrent `apply` that finds a live
lease it does not own is rejected with HTTP `409` (`error:
"migration_busy"`). A crashed run's lease simply expires and the next call
takes over — without resetting `startedAt`. This is what guarantees two
`apply` calls can never interleave and regress the checkpoint cursor or
totals.

## Conflicts & errors collections

- `migrationConflicts/{scope__userId}` — durable record of non-retryable problems
  (`missing_join_timestamp`, `membership_exists_incompatible`,
  `invalid_legacy_record`). `scope` is `teamId` for team-scoped conflicts and
  `_record` for malformed-legacy-record conflicts. Written by both the migration and the
  compatibility trigger; auto-deleted when the user later maps cleanly.
- `migrationErrors/{scope__userId}` — durable record of transient per-user
  processing failures encountered by `apply`; scope is `teamId` when known,
  `_record` otherwise. Auto-deleted when the user is successfully processed
  on a later page/retry.

## Authorization authority & the hard cutover gate

This is the single most important operational constraint for the upcoming
`firestore.rules` phase. Read it before writing any rule that references
`teamMemberships`.

- **Legacy `users.teamId` / `users.role` remain the *sole* authorization
  authority during this single-team bridge.** Every access decision — who
  may read/write a team's sessions, attendance, roster, and who is an admin
  — is still made from the legacy user profile. `teamMemberships` is
  *migration-derived, bridge-owned data*, not an identity/authorization
  source.
- **`teamMemberships` must not grant session/team/admin access yet.** In the
  rules phase it will be made readable/writable under *constrained* rules so
  the V2 client can operate on V2 data, but a membership document must **not**
  by itself confer any session/team/admin capability. Deriving "this user is
  on this team / is an admin" from `teamMemberships` stays disabled until
  after cutover.
- **The bridge never treats `teamMemberships` as an authorization source.**
  The compatibility trigger and migration read the legacy `users/*` document
  as the source of truth and *write* `teamMemberships`; they never consult a
  membership document to decide what a user is allowed to do. Foreign/non-V2
  membership documents are recorded as *blocking* conflicts and left
  **untouched** — the bridge never overwrites a foreign document, not even to
  "revoke" it.
- **Hard cutover gate — membership-only rules are FORBIDDEN while
  `migrationConflicts` or `migrationErrors` exist.** Do not deploy any
  `firestore.rules` that derives authorization from `teamMemberships` while
  `status.cutoverReady` is `false` (i.e. the checkpoint is not `done`, or any
  *unresolved* conflict/error remains). Cutting over with unresolved
  conflicts/errors would silently drop or misgrant access for exactly the
  users whose membership state is known-bad. The gate is machine-checkable:
  poll `mode: "status"` and require `cutoverReady: true`.

Canonical safe cutover sequence:

1. `reset` (one-shot — also clears stale conflicts/errors, including for
   vanished users).
2. `apply` until `done: true` (stop on `noProgress: true` and repair the
   offending `migrationErrors/{scope__userId}`).
3. `verify` until zero mismatches.
4. `status` until `cutoverReady: true`.
5. *Only then* deploy the membership-aware `firestore.rules`.

## Security model (`invoker: "public"`)

`multiTeamMigration` is deployed with `invoker: "public"`, meaning **anyone
on the internet can reach the URL**. This is a deliberate trade-off so the
endpoint can be driven by a plain `curl`/PowerShell loop with no `gcloud`
/ IAM / OAuth dependency. Understand the limitations:

- The **only** thing protecting your data is the `MIGRATION_TOKEN` bearer
  secret, compared in constant time. A `POST` without it gets `401` and
  touches nothing; a non-`POST` gets `405` before the token is even read.
- There is **no network-level restriction** and no per-caller rate
  limiting here — the endpoint is exposed to internet-wide probing/DoS.
- The token travels in an HTTP header, so its confidentiality depends on
  HTTPS (Cloud Functions enforces TLS) and on you **not** leaking it via
  shell history, CI logs, or screenshots.

Mitigations you should apply:

- Use a long, random token (see §1) and **rotate it** after the migration.
- **Delete the function** once the migration is complete
  (`firebase functions:delete multiTeamMigration`) so the surface is gone.
- If you need stronger protection than a shared secret, deploy with
  `invoker: "private"` instead and call it with an OAuth identity token —
  but that reintroduces a `gcloud`/service-account dependency, which we
  intentionally avoid here.

## Safety constraints (do not relax these without re-reviewing)

- `dryRun`, `verify`, and `status` must never call `.set()`/`.update()`/
  `.delete()`/`runTransaction()` on any collection (`status` uses only
  `.get()` and aggregate `.count()`).
- `apply` must never overwrite a `teamMemberships/*` document it didn't
  create — always check `migrationVersion`/`teamId`/`memberId` first and
  record a conflict instead.
- `finalizePage` must write the checkpoint only when the caller *still owns*
  the lease (exact owner match). A stale worker whose lease was released,
  stolen, or expired-and-taken-over — or a checkpoint with no lease — must
  never write status/cursor/totals.
- `apply` must surface `noProgress: true` when the cursor cannot advance
  because the first unprocessed user keeps failing, so the driving loop stops
  instead of retrying a poison page forever.
- The compatibility trigger must never delete/shrink `membershipPeriods`
  or `attendanceDefaultHistory`, never invent a join date, never overwrite a
  foreign/non-V2 membership, and must record malformed records and foreign
  memberships as durable *blocking* conflicts.
- `teamMemberships` is never an authorization source during the bridge;
  legacy `users.teamId`/`users.role` is. Membership-only rules are forbidden
  until `status.cutoverReady` is `true` (see **Authorization authority & the
  hard cutover gate**).
- Multi-team support is **not** enabled in this phase — `activeTeamId`
  simply mirrors the single legacy `teamId` for now.
- The HTTP endpoint only accepts `POST`; anything else gets `405` before
  the token is even checked.
- Never commit the `MIGRATION_TOKEN` value. It lives only in Secret
  Manager (`firebase functions:secrets:set`).

## Project layout

```
functions/
  src/
    config.ts           Region/collection name constants, lease TTL, page size
    types.ts             Shared TypeScript types (legacy user, membership, ...)
    migrationIds.ts       Deterministic teamMemberships doc id helpers
    mapping.ts            Pure legacy user -> membership mapping + validation
    idempotency.ts         Pure "should I write this?" ownership/shape guards
    migrationRunner.ts      Paginated apply/dryRun + checkpoint/lease/retry logic
    verify.ts               Read-only verification (pure compare + orchestration)
    status.ts               Read-only checkpoint + conflict/error-count cutover gate
    compatDecision.ts        Pure old-client trigger decision logic
    compatTrigger.ts          onDocumentWritten(users/{userId}) wiring + testable handler
    auth.ts                   Constant-time token comparison
    httpMigration.ts           The protected HTTPS v2 endpoint (dryRun/apply/verify/status)
    index.ts                    Deployable exports
  test/                          Jest unit + *.emulator.test.ts integration tests
```
