/**
 * Emulator-backed integration coverage for the migration runner's
 * *operational* guarantees: pagination/resume, per-user failure isolation
 * with retry, one-shot reset, checkpoint-lease concurrency protection, and
 * stale-conflict resolution.
 *
 * Requires the Firestore emulator (see functions/README.md for the exact
 * command). When FIRESTORE_EMULATOR_HOST is not set the whole suite is
 * skipped, so a plain `npm install && npm test` still passes.
 *
 * Uses its own project id so it never shares emulator data with
 * migration.emulator.test.ts (Jest runs test files in parallel workers).
 */
import { initializeApp } from 'firebase-admin/app';
import { Firestore, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { buildScopedRecordId } from '../src/migrationIds';
import {
  MigrationBusyError,
  MigrationCheckpointDoc,
  MigrationInvalidApplyCursorError,
  MigrationPageCounts,
  checkpointRef,
  finalizePage,
  runMigrationPage,
} from '../src/migrationRunner';
import { getMigrationStatus } from '../src/status';

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const describeIfEmulator = emulatorHost ? describe : describe.skip;

const USER_IDS = ['u1', 'u2', 'u3', 'u4', 'u5'];

describeIfEmulator('migration runner operational guarantees (Firestore emulator)', () => {
  let db: Firestore;

  beforeAll(() => {
    initializeApp({ projectId: 'demo-migration-resume' });
    db = getFirestore();
  });

  async function deleteCollection(name: string) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
  }

  async function clearDerivedState() {
    await Promise.all([
      deleteCollection('teamMemberships'),
      deleteCollection('migrations'),
      deleteCollection('migrationConflicts'),
      deleteCollection('migrationErrors'),
    ]);
  }

  beforeAll(async () => {
    const joinedAt = Timestamp.fromDate(new Date('2026-01-10T00:00:00Z'));
    await Promise.all(
      USER_IDS.map((id) =>
        db.collection('users').doc(id).set({
          email: `${id}@example.com`,
          fullName: `User ${id}`,
          role: 'player',
          teamId: 'team-1',
          teamJoinedAt: joinedAt,
          active: true,
          managedByCoach: false,
        }),
      ),
    );
  });

  beforeEach(async () => {
    await clearDerivedState();
  });

  afterAll(async () => {
    await deleteCollection('users');
    await clearDerivedState();
    await db.terminate();
  }, 30000);

  it('paginates and resumes across pages with pageSize=2 until done', async () => {
    let pages = 0;
    let result = await runMigrationPage(db, { mode: 'apply', pageSize: 2 });
    pages++;
    expect(result.done).toBe(false);
    expect(result.counts.processed).toBe(2);
    while (!result.done) {
      result = await runMigrationPage(db, { mode: 'apply', pageSize: 2 });
      pages++;
    }
    expect(pages).toBeGreaterThanOrEqual(3);

    const checkpoint = (await checkpointRef(db).get()).data() as MigrationCheckpointDoc;
    expect(checkpoint.status).toBe('done');
    expect(checkpoint.totals.processed).toBe(5);
    expect(checkpoint.totals.migrated).toBe(5);

    const memberships = await db.collection('teamMemberships').get();
    expect(memberships.size).toBe(5);
  });

  it('does not advance the cursor past a transient per-user failure and retries it later', async () => {
    const restore = injectFirstUserReadFailure(db, 'u3');
    let firstPage;
    try {
      firstPage = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    } finally {
      restore();
    }

    expect(firstPage.counts.errors).toBe(1);
    expect(firstPage.done).toBe(false);

    const checkpointAfterFailure = (await checkpointRef(db).get()).data() as MigrationCheckpointDoc;
    // Frontier stopped at the last good doc before u3 (u2), so u3 is retried.
    expect(checkpointAfterFailure.lastCursor).toBe('u2');
    const startedAt = checkpointAfterFailure.startedAt.toMillis();

    const errorDoc = await db.collection('migrationErrors').doc(buildScopedRecordId('u3', 'team-1')).get();
    expect(errorDoc.exists).toBe(true);

    const u3Before = await db.collection('teamMemberships').doc('team-1__u3').get();
    expect(u3Before.exists).toBe(false);

    // Resume (no reset): the failed user is retried and the run completes.
    let result = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    while (!result.done) {
      result = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    }

    const u3After = await db.collection('teamMemberships').doc('team-1__u3').get();
    expect(u3After.exists).toBe(true);

    const errorResolved = await db.collection('migrationErrors').doc(buildScopedRecordId('u3', 'team-1')).get();
    expect(errorResolved.exists).toBe(false);

    const finalCheckpoint = (await checkpointRef(db).get()).data() as MigrationCheckpointDoc;
    expect(finalCheckpoint.status).toBe('done');
    // startedAt must be preserved across ordinary retries (never reset).
    expect(finalCheckpoint.startedAt.toMillis()).toBe(startedAt);
  });

  it('resolves a stale conflict document once the user migrates cleanly on a later run', async () => {
    await db.collection('migrationConflicts').doc(buildScopedRecordId('u1', 'team-1')).set({
      legacyUserId: 'u1',
      teamId: 'team-1',
      reason: 'membership_exists_incompatible',
      detail: 'stale conflict from an earlier run',
      resolved: false,
    });

    let result = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    while (!result.done) {
      result = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    }

    const conflictDoc = await db.collection('migrationConflicts').doc(buildScopedRecordId('u1', 'team-1')).get();
    expect(conflictDoc.exists).toBe(false);
  });

  it('reset is a one-shot action: it does not process a page and cannot loop resetting page 1', async () => {
    let result = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    while (!result.done) {
      result = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    }
    const firstStartedAt = ((await checkpointRef(db).get()).data() as MigrationCheckpointDoc).startedAt.toMillis();

    // A short delay so the reset's fresh startedAt is strictly newer.
    await new Promise((r) => setTimeout(r, 5));

    const resetAck = await runMigrationPage(db, { mode: 'apply', pageSize: 10, reset: true });
    expect(resetAck.reset).toBe(true);
    expect(resetAck.done).toBe(true);
    expect(resetAck.counts.processed).toBe(0);

    const afterReset = (await checkpointRef(db).get()).data() as MigrationCheckpointDoc;
    expect(afterReset.lastCursor).toBeNull();
    expect(afterReset.totals.processed).toBe(0);
    expect(afterReset.status).toBe('in_progress');
    expect(afterReset.startedAt.toMillis()).toBeGreaterThan(firstStartedAt);
  });

  it('rejects a concurrent apply with a MigrationBusyError while another run holds the lease', async () => {
    const now = Date.now();
    const totals = {
      processed: 0,
      migrated: 0,
      alreadyMigrated: 0,
      skippedNoTeam: 0,
      conflicts: 0,
      vanished: 0,
      errors: 0,
    };
    await checkpointRef(db).set({
      status: 'in_progress',
      startedAt: Timestamp.fromMillis(now),
      lastCursor: null,
      updatedAt: Timestamp.fromMillis(now),
      totals,
      lease: {
        owner: 'another-run',
        acquiredAt: Timestamp.fromMillis(now),
        expiresAt: Timestamp.fromMillis(now + 10 * 60 * 1000),
      },
    });

    await expect(runMigrationPage(db, { mode: 'apply', pageSize: 2 })).rejects.toBeInstanceOf(MigrationBusyError);

    // The foreign lease is untouched, and no users were processed.
    const memberships = await db.collection('teamMemberships').get();
    expect(memberships.empty).toBe(true);
  });

  it('rejects explicit apply cursor once migration is done', async () => {
    let result = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    while (!result.done) {
      result = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    }

    await expect(
      runMigrationPage(db, { mode: 'apply', pageSize: 10, cursor: 'u1' }),
    ).rejects.toBeInstanceOf(MigrationInvalidApplyCursorError);
  });

  it('finalizePage refuses to write when the caller no longer owns the lease', async () => {
    const now = Date.now();
    const foreignTotals: MigrationPageCounts = {
      processed: 2,
      migrated: 2,
      alreadyMigrated: 0,
      skippedNoTeam: 0,
      conflicts: 0,
      vanished: 0,
      errors: 0,
    };
    await checkpointRef(db).set({
      status: 'in_progress',
      startedAt: Timestamp.fromMillis(now),
      lastCursor: 'u2',
      updatedAt: Timestamp.fromMillis(now),
      totals: foreignTotals,
      lease: {
        owner: 'other-owner',
        acquiredAt: Timestamp.fromMillis(now),
        expiresAt: Timestamp.fromMillis(now + 10 * 60 * 1000),
      },
    });

    // A stale worker (different owner) must never write checkpoint/totals/status.
    await finalizePage(
      db,
      'stale-owner',
      { processed: 99, migrated: 99, alreadyMigrated: 0, skippedNoTeam: 0, conflicts: 0, vanished: 0, errors: 0 },
      'u5',
      true,
    );

    const after = (await checkpointRef(db).get()).data() as MigrationCheckpointDoc;
    expect(after.status).toBe('in_progress'); // not flipped to done
    expect(after.lastCursor).toBe('u2'); // not advanced
    expect(after.totals.processed).toBe(2); // not merged with the stale 99
    expect(after.lease?.owner).toBe('other-owner'); // foreign lease untouched
  });

  it('finalizePage refuses to write when there is no lease to own (expired/released)', async () => {
    const now = Date.now();
    await checkpointRef(db).set({
      status: 'in_progress',
      startedAt: Timestamp.fromMillis(now),
      lastCursor: 'u1',
      updatedAt: Timestamp.fromMillis(now),
      totals: {
        processed: 1,
        migrated: 1,
        alreadyMigrated: 0,
        skippedNoTeam: 0,
        conflicts: 0,
        vanished: 0,
        errors: 0,
      },
      lease: null,
    });

    await finalizePage(
      db,
      'stale-owner',
      { processed: 5, migrated: 5, alreadyMigrated: 0, skippedNoTeam: 0, conflicts: 0, vanished: 0, errors: 0 },
      'u5',
      true,
    );

    const after = (await checkpointRef(db).get()).data() as MigrationCheckpointDoc;
    expect(after.status).toBe('in_progress');
    expect(after.lastCursor).toBe('u1');
    expect(after.totals.processed).toBe(1);
  });

  it('flags noProgress on a poison page whose first user cannot advance', async () => {
    // u1 always fails: the frontier can never move past the incoming cursor,
    // so the page makes no forward progress and would loop forever.
    const restore = injectPersistentUserReadFailure(db, 'u1');
    let page;
    try {
      page = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    } finally {
      restore();
    }

    expect(page.counts.errors).toBe(1);
    expect(page.done).toBe(false);
    expect(page.noProgress).toBe(true);
    expect(page.nextCursor).toBeNull(); // cursor did not advance from the start

    // The per-user error is still recorded for repair/retry.
    const errorDoc = await db.collection('migrationErrors').doc(buildScopedRecordId('u1', 'team-1')).get();
    expect(errorDoc.exists).toBe(true);

    // After the fault clears, a resume advances normally (no longer a poison page).
    let result = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    while (!result.done) {
      result = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    }
    expect(result.noProgress).toBe(false);
    const resolved = await db.collection('migrationErrors').doc(buildScopedRecordId('u1', 'team-1')).get();
    expect(resolved.exists).toBe(false);
  });

  it('reset clears stale conflicts/errors, including for users that have vanished', async () => {
    await db.collection('migrationConflicts').doc('vanished-user').set({
      legacyUserId: 'vanished-user',
      teamId: 'team-x',
      reason: 'invalid_legacy_record',
      detail: 'stale conflict for a user that no longer exists',
      resolved: false,
    });
    await db.collection('migrationErrors').doc('vanished-user').set({
      legacyUserId: 'vanished-user',
      message: 'stale error for a user that no longer exists',
      resolved: false,
    });

    const resetAck = await runMigrationPage(db, { mode: 'apply', pageSize: 10, reset: true });
    expect(resetAck.reset).toBe(true);
    expect(resetAck.done).toBe(true);

    expect((await db.collection('migrationConflicts').doc('vanished-user').get()).exists).toBe(false);
    expect((await db.collection('migrationErrors').doc('vanished-user').get()).exists).toBe(false);
  });

  it('status reports cutoverReady only when done with zero unresolved conflicts/errors', async () => {
    let result = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    while (!result.done) {
      result = await runMigrationPage(db, { mode: 'apply', pageSize: 10 });
    }

    let status = await getMigrationStatus(db);
    expect(status.mode).toBe('status');
    expect(status.checkpoint.exists).toBe(true);
    expect(status.checkpoint.status).toBe('done');
    expect(status.conflicts.unresolved).toBe(0);
    expect(status.errors.unresolved).toBe(0);
    expect(status.cutoverReady).toBe(true);

    // A single unresolved conflict must block the cutover gate.
    await db.collection('migrationConflicts').doc('blocker').set({
      legacyUserId: 'blocker',
      teamId: null,
      reason: 'invalid_legacy_record',
      detail: 'unresolved',
      resolved: false,
    });
    status = await getMigrationStatus(db);
    expect(status.conflicts.total).toBe(1);
    expect(status.conflicts.unresolved).toBe(1);
    expect(status.cutoverReady).toBe(false);
  });
});

/**
 * Patches `db.runTransaction` so the first `tx.get` targeting `users/{id}`
 * rejects with a simulated transient failure, then behaves normally.
 * Returns a restore function. Only that one document read is affected;
 * checkpoint/lease transactions (which read `migrations/*`) are untouched.
 */
function injectFirstUserReadFailure(db: Firestore, userId: string): () => void {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const anyDb = db as any;
  const realRunTransaction = anyDb.runTransaction.bind(anyDb);
  const targetPath = `users/${userId}`;
  let fired = false;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  anyDb.runTransaction = (updateFn: any, options: any) =>
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    realRunTransaction(async (tx: any) => {
      const realGet = tx.get.bind(tx);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      tx.get = (ref: any) => {
        if (!fired && ref && ref.path === targetPath) {
          fired = true;
          return Promise.reject(new Error(`injected transient failure for ${targetPath}`));
        }
        return realGet(ref);
      };
      return updateFn(tx);
    }, options);
  return () => {
    anyDb.runTransaction = realRunTransaction;
  };
}

/**
 * Like {@link injectFirstUserReadFailure} but keeps failing *every* read of
 * `users/{userId}` until restored, so a page that starts on that user can
 * never make forward progress (poison page). Checkpoint/lease transactions
 * (which read `migrations/*`) are untouched.
 */
function injectPersistentUserReadFailure(db: Firestore, userId: string): () => void {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const anyDb = db as any;
  const realRunTransaction = anyDb.runTransaction.bind(anyDb);
  const targetPath = `users/${userId}`;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  anyDb.runTransaction = (updateFn: any, options: any) =>
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    realRunTransaction(async (tx: any) => {
      const realGet = tx.get.bind(tx);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      tx.get = (ref: any) => {
        if (ref && ref.path === targetPath) {
          return Promise.reject(new Error(`injected persistent failure for ${targetPath}`));
        }
        return realGet(ref);
      };
      return updateFn(tx);
    }, options);
  return () => {
    anyDb.runTransaction = realRunTransaction;
  };
}
