/**
 * Temporary compatibility trigger: keeps `teamMemberships/*` (and the
 * `activeTeamId`/`schemaVersion` profile mirror) in sync when a *genuinely
 * old* client creates, updates, or deletes `users/{userId}` using the
 * legacy single-team schema.
 *
 * This is a backfill/bridge, not the app's primary consistency mechanism —
 * the future V2 client is expected to write `teamMemberships` and the
 * legacy mirror atomically itself (bumping `membershipWriteToken` as part
 * of that same transaction), at which point this trigger immediately
 * no-ops for that write. See {@link decideCompatSync} for the full
 * decision rules and functions/README.md for the operational rationale.
 *
 * The Firestore-transaction handler is factored out as the exported,
 * emulator-testable {@link handleLegacyUserCompatWrite}; the deployed
 * `legacyUserCompatSync` trigger is a thin adapter that unpacks the event
 * and calls it.
 *
 * Robustness properties (see the individual findings addressed in the
 * README):
 *  - Fires on create/update/delete (`onDocumentWritten`), so a legacy
 *    create with a `teamId` provisions the membership and a managed-player
 *    delete closes the open period + marks the membership inactive while
 *    preserving history.
 *  - Recomputes the target from the *fresh* current user state read inside
 *    the transaction, so an out-of-order/redelivered event cannot regress
 *    the membership or profile.
 *  - Never overwrites a membership document it did not produce, and never
 *    invents a join date — both are recorded as durable
 *    `migrationConflicts` instead.
 *  - A malformed `before` or *fresh current* user document is recorded as a
 *    durable `invalid_legacy_record` conflict (never left as a log line
 *    only) so the cutover gate can block on it.
 *  - Persists conflicts, and rethrows genuine infrastructure failures so
 *    Cloud Functions retries them (the write path is idempotent, so
 *    at-least-once redelivery is safe). `retry: true` enables that retry.
 */
import { Firestore, getFirestore, Timestamp } from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { randomUUID } from 'node:crypto';
import { decideCompatSync } from './compatDecision';
import {
  FUNCTIONS_REGION,
  MIGRATION_CONFLICTS_COLLECTION,
  TEAM_MEMBERSHIPS_COLLECTION,
  USERS_COLLECTION,
} from './config';
import { parseLegacyUser } from './mapping';
import { buildMembershipId, conflictDocId } from './migrationIds';
import { LegacyUserRecord, MigrationConflict } from './types';

/**
 * Machine-readable outcome of {@link handleLegacyUserCompatWrite}. Returned
 * so the (emulator) tests — and any future observability — can assert
 * exactly which branch handled a delivery.
 */
export type CompatOutcome =
  | 'empty' // Neither before nor after existed: nothing to do.
  | 'tokenNoop' // membershipWriteToken changed: a V2 client already synced.
  | 'malformedBefore' // Event `before` malformed: invalid_legacy_record conflict recorded.
  | 'malformedCurrent' // Fresh current doc malformed: invalid_legacy_record conflict recorded.
  | 'noop' // Computed target already matches stored state.
  | 'conflict' // Durable conflict recorded; foreign/incompatible data left untouched.
  | 'synced'; // Membership/profile written.

export interface CompatEventInput {
  userId: string;
  /** Raw `users/{userId}` body pre-write, or `null` if it did not exist. */
  rawBefore: Record<string, unknown> | null;
  /** Raw `users/{userId}` body post-write, or `null` if it was deleted. */
  rawAfter: Record<string, unknown> | null;
  /** `event.time` parsed to epoch millis (the authoritative event instant). */
  eventTimeMillis: number;
}

function invalidRecordConflict(userId: string, rawTeamId: unknown, detail: string): MigrationConflict {
  return {
    legacyUserId: userId,
    teamId: typeof rawTeamId === 'string' ? rawTeamId : null,
    reason: 'invalid_legacy_record',
    detail,
  };
}

/**
 * The whole trigger body as a plain, injectable function so it can be
 * exercised directly against the Firestore emulator (create/update/delete,
 * token no-op, deleted-user non-resurrection, malformed-record conflict and
 * duplicate delivery) without deploying the Cloud Function.
 *
 * Throws only on genuine infrastructure failures (so the caller/Cloud
 * Functions can retry the idempotent delivery); data problems (malformed
 * records, foreign memberships, missing join dates) are recorded as durable
 * conflicts and returned as a {@link CompatOutcome} instead.
 */
export async function handleLegacyUserCompatWrite(
  db: Firestore,
  input: CompatEventInput,
): Promise<CompatOutcome> {
  const { userId, rawBefore, rawAfter } = input;

  if (rawBefore === null && rawAfter === null) {
    return 'empty';
  }

  // Cheap V2-client detection first: if this exact write bumped the token, a
  // V2 client transaction already synchronized everything.
  const writeChangedToken =
    rawBefore !== null &&
    rawAfter !== null &&
    rawBefore.membershipWriteToken !== rawAfter.membershipWriteToken;
  if (writeChangedToken) {
    logger.debug('legacyUserCompatSync: membershipWriteToken changed; V2 client already synced', { userId });
    return 'tokenNoop';
  }

  // The event `before` is used only to detect what this write changed (team
  // switch, active flip). If it is malformed we cannot reason about it —
  // record a durable conflict (the id is known) and end. This is a data
  // problem, not a retryable infrastructure failure, so we do not rethrow.
  let before: LegacyUserRecord | null = null;
  if (rawBefore !== null) {
    const parsedBefore = parseLegacyUser(userId, rawBefore);
    if (!parsedBefore.ok) {
      const conflict = invalidRecordConflict(userId, rawBefore.teamId, `event "before" is malformed: ${parsedBefore.error}`);
      await db.collection(MIGRATION_CONFLICTS_COLLECTION).doc(conflictDocId(conflict)).set(
        {
          ...conflict,
          source: 'compatTrigger',
          recordedAt: Timestamp.now(),
          resolved: false,
        },
        { merge: true },
      );
      logger.warn('legacyUserCompatSync: event "before" is malformed; recorded conflict', {
        userId,
        error: parsedBefore.error,
      });
      return 'malformedBefore';
    }
    before = parsedBefore.user;
  }

  const eventTime = Timestamp.fromMillis(input.eventTimeMillis);
  const usersRef = db.collection(USERS_COLLECTION).doc(userId);
  const membershipsCollection = db.collection(TEAM_MEMBERSHIPS_COLLECTION);

  try {
    return await db.runTransaction(async (tx): Promise<CompatOutcome> => {
      // Read the *current* user state inside the transaction so a stale /
      // out-of-order redelivery computes writes from fresh data.
      const freshUserSnap = await tx.get(usersRef);
      let after: LegacyUserRecord | null = null;
      if (freshUserSnap.exists) {
        const rawCurrent = freshUserSnap.data() ?? {};
        const parsedAfter = parseLegacyUser(userId, rawCurrent);
        if (!parsedAfter.ok) {
          // Record a durable conflict rather than only logging; the id is
          // known so the cutover gate can block on it.
          const conflict = invalidRecordConflict(
            userId,
            rawCurrent.teamId,
            `current user document is malformed: ${parsedAfter.error}`,
          );
          tx.set(
            db.collection(MIGRATION_CONFLICTS_COLLECTION).doc(conflictDocId(conflict)),
            {
              ...conflict,
              source: 'compatTrigger',
              recordedAt: Timestamp.now(),
              resolved: false,
            },
            { merge: true },
          );
          logger.warn('legacyUserCompatSync: current user document is malformed; recorded conflict', {
            userId,
            error: parsedAfter.error,
          });
          return 'malformedCurrent';
        }
        after = parsedAfter.user;
      }

      const oldTeamId = before?.teamId ?? null;
      const newTeamId = after?.teamId ?? null;

      const oldMembershipSnap = oldTeamId
        ? await tx.get(membershipsCollection.doc(buildMembershipId(oldTeamId, userId)))
        : null;
      const newMembershipSnap = newTeamId
        ? newTeamId === oldTeamId
          ? oldMembershipSnap
          : await tx.get(membershipsCollection.doc(buildMembershipId(newTeamId, userId)))
        : null;

      const plan = decideCompatSync({
        userId,
        before,
        after,
        eventTime,
        writeChangedToken: false,
        existingOldMembership: oldMembershipSnap?.exists ? oldMembershipSnap.data() ?? null : null,
        existingNewMembership: newMembershipSnap?.exists ? newMembershipSnap.data() ?? null : null,
      });

      if (plan.kind === 'noop') {
        logger.debug('legacyUserCompatSync: no-op', { userId, reason: plan.reason });
        return 'noop';
      }

      if (plan.kind === 'conflict') {
        // Durably record the *blocking* conflict; never overwrite the
        // foreign document (not even to "revoke" it). This is not retryable,
        // so we do not rethrow.
        tx.set(
          db.collection(MIGRATION_CONFLICTS_COLLECTION).doc(conflictDocId(plan.conflict)),
          { ...plan.conflict, source: 'compatTrigger', recordedAt: Timestamp.now(), resolved: false },
          { merge: true },
        );
        logger.warn('legacyUserCompatSync: recorded conflict', { userId, reason: plan.reason });
        return 'conflict';
      }

      if (plan.closeOldMembership) {
        tx.set(
          membershipsCollection.doc(plan.closeOldMembership.membershipId),
          plan.closeOldMembership.membership,
        );
      }
      if (plan.upsertNewMembership) {
        tx.set(
          membershipsCollection.doc(plan.upsertNewMembership.membershipId),
          plan.upsertNewMembership.membership,
        );
      }

      // Only touch the user document if it still exists — never resurrect a
      // just-deleted user by writing a token/profile back onto it.
      if (freshUserSnap.exists) {
        // Bumping the token marks this exact write as "already synced" so the
        // update it causes (re-triggering this function) is recognized and
        // no-opped on the very first check, breaking the write loop.
        const userUpdate: Record<string, unknown> = { membershipWriteToken: randomUUID() };
        if (plan.profileUpdate) {
          userUpdate.activeTeamId = plan.profileUpdate.activeTeamId;
          userUpdate.schemaVersion = plan.profileUpdate.schemaVersion;
        }
        tx.set(usersRef, userUpdate, { merge: true });
      }

      logger.info('legacyUserCompatSync: synced old-client write', { userId, reason: plan.reason });
      return 'synced';
    });
  } catch (err) {
    // A conflict/malformed document is handled above without throwing;
    // reaching here means a genuine infrastructure failure (transaction
    // contention, Firestore unavailable, ...). Rethrow so Cloud Functions
    // retries the (idempotent) delivery instead of silently reporting
    // success.
    logger.error('legacyUserCompatSync: transaction failed; will be retried', {
      userId,
      error: err instanceof Error ? err.message : String(err),
    });
    throw err;
  }
}

export const legacyUserCompatSync = onDocumentWritten(
  { document: `${USERS_COLLECTION}/{userId}`, region: FUNCTIONS_REGION, retry: true },
  async (event) => {
    const beforeSnap = event.data?.before;
    const afterSnap = event.data?.after;
    const rawBefore = beforeSnap?.exists ? beforeSnap.data() ?? {} : null;
    const rawAfter = afterSnap?.exists ? afterSnap.data() ?? {} : null;

    await handleLegacyUserCompatWrite(getFirestore(), {
      userId: event.params.userId,
      rawBefore,
      rawAfter,
      eventTimeMillis: Date.parse(event.time),
    });
  },
);
