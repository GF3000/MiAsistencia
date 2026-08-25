/**
 * Read-only migration status snapshot for autonomous orchestration. Returns
 * the checkpoint (progress/lease) plus aggregate `migrationConflicts`/
 * `migrationErrors` counts and a single `cutoverReady` boolean so a
 * deployment/cutover pipeline can *gate* on the migration being genuinely
 * finished with no unresolved blockers — without paging through every user.
 *
 * Entirely read-only: only `.get()` and aggregate `.count()` queries are
 * issued, never a write. It is therefore safe to poll at any time, exactly
 * like `dryRun`/`verify`.
 */
import { Firestore } from 'firebase-admin/firestore';
import { MIGRATION_CONFLICTS_COLLECTION, MIGRATION_ERRORS_COLLECTION } from './config';
import { MigrationCheckpointDoc, MigrationPageCounts, checkpointRef } from './migrationRunner';

export interface MigrationStatusCheckpoint {
  exists: boolean;
  status: 'in_progress' | 'done' | null;
  startedAtMillis: number | null;
  updatedAtMillis: number | null;
  lastCursor: string | null;
  totals: MigrationPageCounts | null;
  /** True when a lease is present and not yet expired (a run may be live). */
  leaseHeld: boolean;
  leaseOwner: string | null;
  leaseExpiresAtMillis: number | null;
}

export interface MigrationStatusResponse {
  mode: 'status';
  checkpoint: MigrationStatusCheckpoint;
  conflicts: { total: number; unresolved: number };
  errors: { total: number; unresolved: number };
  /**
   * `true` only when the migration checkpoint is `done` *and* there are zero
   * unresolved conflicts and zero unresolved errors. This is the hard gate:
   * membership-only firestore.rules must not be cut over while this is
   * `false`.
   */
  cutoverReady: boolean;
  generatedAtMillis: number;
}

async function countCollection(db: Firestore, name: string): Promise<{ total: number; unresolved: number }> {
  const collection = db.collection(name);
  const [totalSnap, unresolvedSnap] = await Promise.all([
    collection.count().get(),
    collection.where('resolved', '==', false).count().get(),
  ]);
  return { total: totalSnap.data().count, unresolved: unresolvedSnap.data().count };
}

export async function getMigrationStatus(db: Firestore): Promise<MigrationStatusResponse> {
  const now = Date.now();
  const snap = await checkpointRef(db).get();
  const checkpoint = snap.exists ? (snap.data() as MigrationCheckpointDoc) : null;

  const lease = checkpoint?.lease ?? null;
  const leaseHeld = !!lease && lease.expiresAt.toMillis() > now;

  const [conflicts, errors] = await Promise.all([
    countCollection(db, MIGRATION_CONFLICTS_COLLECTION),
    countCollection(db, MIGRATION_ERRORS_COLLECTION),
  ]);

  const done = checkpoint?.status === 'done';
  const cutoverReady = !!checkpoint && done && conflicts.unresolved === 0 && errors.unresolved === 0;

  return {
    mode: 'status',
    checkpoint: {
      exists: checkpoint !== null,
      status: checkpoint?.status ?? null,
      startedAtMillis: checkpoint?.startedAt?.toMillis() ?? null,
      updatedAtMillis: checkpoint?.updatedAt?.toMillis() ?? null,
      lastCursor: checkpoint?.lastCursor ?? null,
      totals: checkpoint?.totals ?? null,
      leaseHeld,
      leaseOwner: lease?.owner ?? null,
      leaseExpiresAtMillis: lease?.expiresAt?.toMillis() ?? null,
    },
    conflicts,
    errors,
    cutoverReady,
    generatedAtMillis: now,
  };
}
