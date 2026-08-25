/**
 * Emulator-backed integration coverage for the migration runner + verify
 * flow, exercising real Firestore transactions/queries end to end.
 *
 * Requires the Firestore emulator: run
 *   firebase emulators:start --only firestore --project demo-migration-test
 * and set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 before `npm test`. When
 * that variable is not set, this whole suite is skipped so `npm test`
 * still passes in environments without the emulator (e.g. a plain `npm
 * install && npm test`), while remaining runnable on demand.
 *
 * No firestore.rules are involved: the Admin SDK always bypasses security
 * rules, so this only exercises the functions' own read/write logic.
 */
import { initializeApp } from 'firebase-admin/app';
import { Firestore, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { conflictDocId } from '../src/migrationIds';
import { runMigrationPage } from '../src/migrationRunner';
import { runVerifyPage } from '../src/verify';

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const describeIfEmulator = emulatorHost ? describe : describe.skip;

describeIfEmulator('migration runner (Firestore emulator)', () => {
  let db: Firestore;

  beforeAll(() => {
    initializeApp({ projectId: 'demo-migration-test' });
    db = getFirestore();
  });

  afterAll(async () => {
    await deleteCollection('users');
    await deleteCollection('teamMemberships');
    await deleteCollection('migrations');
    await deleteCollection('migrationConflicts');
    await deleteCollection('migrationErrors');
    await db.terminate();
  }, 30000);

  async function deleteCollection(name: string) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
  }

  beforeAll(async () => {
    const t = (iso: string) => Timestamp.fromDate(new Date(iso));
    await db
      .collection('users')
      .doc('active-account')
      .set({
        email: 'a@example.com',
        fullName: 'Active Account',
        role: 'player',
        teamId: 'team-1',
        teamJoinedAt: t('2026-01-10T00:00:00Z'),
        active: true,
        managedByCoach: false,
      });
    await db
      .collection('users')
      .doc('inactive-account')
      .set({
        email: 'b@example.com',
        fullName: 'Inactive Account',
        role: 'player',
        teamId: 'team-1',
        teamJoinedAt: t('2026-01-05T00:00:00Z'),
        active: false,
        managedByCoach: false,
      });
    await db
      .collection('users')
      .doc('managed-player')
      .set({
        email: '',
        fullName: 'Managed Player',
        role: 'player',
        teamId: 'team-1',
        teamJoinedAt: t('2026-02-01T00:00:00Z'),
        active: true,
        managedByCoach: true,
      });
    await db.collection('users').doc('no-team-yet').set({
      email: 'c@example.com',
      fullName: 'No Team Yet',
      role: 'player',
      teamId: null,
      active: true,
      managedByCoach: false,
    });
    await db.collection('users').doc('malformed-no-join-date').set({
      email: 'd@example.com',
      fullName: 'Malformed User',
      role: 'player',
      teamId: 'team-1',
      active: true,
      managedByCoach: false,
      // No teamJoinedAt and no createdAt: this must become a conflict.
    });
  });

  it('dryRun makes no writes and reports the expected preview counts', async () => {
    const result = await runMigrationPage(db, { mode: 'dryRun', pageSize: 200 });
    expect(result.done).toBe(true);
    expect(result.counts.processed).toBe(5);
    expect(result.counts.migrated).toBe(3);
    expect(result.counts.skippedNoTeam).toBe(1);
    expect(result.counts.conflicts).toBe(1);

    // Confirm dryRun truly wrote nothing.
    const membershipsSnap = await db.collection('teamMemberships').get();
    expect(membershipsSnap.empty).toBe(true);
    const checkpointSnap = await db.collection('migrations').doc('multiTeamV2').get();
    expect(checkpointSnap.exists).toBe(false);
  });

  it('apply migrates the expected users, mirrors the profile, and records a conflict', async () => {
    const result = await runMigrationPage(db, { mode: 'apply', pageSize: 200 });
    expect(result.done).toBe(true);
    expect(result.counts.migrated).toBe(3);
    expect(result.counts.conflicts).toBe(1);

    const activeMembership = await db.collection('teamMemberships').doc('team-1__active-account').get();
    expect(activeMembership.exists).toBe(true);
    expect(activeMembership.data()?.membershipPeriods).toEqual([
      { joinedAt: Timestamp.fromDate(new Date('2026-01-10T00:00:00Z')), leftAt: null },
    ]);

    const inactiveMembership = await db.collection('teamMemberships').doc('team-1__inactive-account').get();
    expect(inactiveMembership.data()?.membershipPeriods[0].leftAt).toBeTruthy();

    const managedMembership = await db.collection('teamMemberships').doc('team-1__managed-player').get();
    expect(managedMembership.data()?.userId).toBeNull();
    expect(managedMembership.data()?.memberId).toBe('managed-player');

    const activeUserDoc = await db.collection('users').doc('active-account').get();
    expect(activeUserDoc.data()?.activeTeamId).toBe('team-1');
    expect(activeUserDoc.data()?.schemaVersion).toBe(2);

    const conflictDoc = await db
      .collection('migrationConflicts')
      .doc(
        conflictDocId({
          legacyUserId: 'malformed-no-join-date',
          teamId: 'team-1',
          reason: 'missing_join_timestamp',
        }),
      )
      .get();
    expect(conflictDoc.exists).toBe(true);
    expect(conflictDoc.data()?.reason).toBe('missing_join_timestamp');

    const checkpoint = await db.collection('migrations').doc('multiTeamV2').get();
    expect(checkpoint.data()?.status).toBe('done');
  });

  it('resuming apply after it is already done reprocesses nothing (cursor is past the end)', async () => {
    const result = await runMigrationPage(db, { mode: 'apply', pageSize: 200 });
    expect(result.done).toBe(true);
    expect(result.counts.processed).toBe(0);
  });

  it('re-scanning from the top (same startedAt) is idempotent: already-migrated documents are not rewritten', async () => {
    const before = await db.collection('teamMemberships').doc('team-1__active-account').get();
    // Rewind only the cursor (not startedAt/status) to force a full re-scan
    // with the same fixed migration instant, simulating an operator-driven
    // re-run without discarding the run's identity.
    await db.collection('migrations').doc('multiTeamV2').update({ lastCursor: null, status: 'in_progress' });

    const result = await runMigrationPage(db, { mode: 'apply', pageSize: 200 });
    expect(result.counts.alreadyMigrated).toBe(3);
    expect(result.counts.migrated).toBe(0);
    expect(result.counts.conflicts).toBe(1);

    const after = await db.collection('teamMemberships').doc('team-1__active-account').get();
    expect(after.data()?.updatedAt).toEqual(before.data()?.updatedAt);
  });

  it('verify reports matches for migrated users and a conflict for the malformed one, with no writes', async () => {
    const result = await runVerifyPage(db, { pageSize: 200 });
    expect(result.done).toBe(true);
    expect(result.counts.matched).toBe(3);
    expect(result.counts.skippedNoTeam).toBe(1);
    expect(result.counts.conflicts).toBe(1);
    expect(result.counts.mismatches).toBe(0);
  });

  it('apply refuses to overwrite a pre-existing incompatible teamMemberships document', async () => {
    await db.collection('users').doc('conflicting-user').set({
      email: 'e@example.com',
      fullName: 'Conflicting User',
      role: 'player',
      teamId: 'team-2',
      teamJoinedAt: Timestamp.now(),
      active: true,
      managedByCoach: false,
    });
    await db.collection('teamMemberships').doc('team-2__conflicting-user').set({
      teamId: 'team-2',
      memberId: 'conflicting-user',
      handWrittenByAdmin: true,
      // No migrationVersion: this is not something migration produced.
    });

    // Reset is a one-shot action that does not process a page; run apply
    // afterwards (paginating until done) to exercise the conflict path.
    const resetAck = await runMigrationPage(db, { mode: 'apply', pageSize: 200, reset: true });
    expect(resetAck.reset).toBe(true);
    expect(resetAck.done).toBe(true);

    let result = await runMigrationPage(db, { mode: 'apply', pageSize: 200 });
    while (!result.done) {
      result = await runMigrationPage(db, { mode: 'apply', pageSize: 200 });
    }
    const conflictDoc = await db
      .collection('migrationConflicts')
      .doc(
        conflictDocId({
          legacyUserId: 'conflicting-user',
          teamId: 'team-2',
          reason: 'membership_exists_incompatible',
        }),
      )
      .get();
    expect(conflictDoc.exists).toBe(true);
    expect(conflictDoc.data()?.reason).toBe('membership_exists_incompatible');

    const untouched = await db.collection('teamMemberships').doc('team-2__conflicting-user').get();
    expect(untouched.data()?.handWrittenByAdmin).toBe(true);
    expect(untouched.data()?.migrationVersion).toBeUndefined();
  });
});
