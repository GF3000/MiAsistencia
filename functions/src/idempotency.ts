/**
 * Pure decision helpers that make the migration idempotent and resumable.
 * Given "what's already in Firestore" and "what the mapping wants to
 * write", they decide the safe action without performing any I/O.
 */
import { buildMembershipId } from './migrationIds';
import { MIGRATION_VERSION } from './config';
import { ProfileUpdate } from './types';

export type MembershipWriteDecision =
  | { action: 'create' }
  | { action: 'alreadyMigrated' }
  | { action: 'conflict'; detail: string };

export interface ExistingMembershipShape {
  teamId?: unknown;
  memberId?: unknown;
  migrationVersion?: unknown;
}

/**
 * Decides what to do about writing a `teamMemberships/{teamId}__{memberId}`
 * document given whatever (possibly unrelated) document already occupies
 * that id.
 *
 * - No document there yet: safe to `create`.
 * - A document that this same migration already produced (same
 *   `migrationVersion`, `teamId`, `memberId`): `alreadyMigrated`, skip the
 *   write — running the migration twice must not double-write or churn
 *   `updatedAt`.
 * - Anything else (hand-written data, a different schema/version, or a
 *   document whose teamId/memberId disagree with the id itself): `conflict`
 *   — never overwritten by the migration, must be reviewed manually.
 */
export function decideMembershipWrite(
  existing: ExistingMembershipShape | null,
  expected: { teamId: string; memberId: string },
): MembershipWriteDecision {
  if (existing === null) {
    return { action: 'create' };
  }
  if (
    existing.migrationVersion === MIGRATION_VERSION &&
    existing.teamId === expected.teamId &&
    existing.memberId === expected.memberId
  ) {
    return { action: 'alreadyMigrated' };
  }
  return {
    action: 'conflict',
    detail:
      `teamMemberships/${buildMembershipId(expected.teamId, expected.memberId)} ` +
      'already exists and was not produced by this migration version; refusing to overwrite it.',
  };
}

/**
 * Decides whether the `users/{userId}` profile mirror
 * (`activeTeamId`/`schemaVersion`) still needs to be written. Merging
 * identical values would still cause a Firestore write (bumping
 * `updatedAt`/triggering listeners), so callers should skip the write
 * entirely when this returns `noop`.
 */
export function decideProfileWrite(
  existing: { activeTeamId: unknown; schemaVersion: unknown },
  expected: ProfileUpdate,
): 'write' | 'noop' {
  if (
    existing.activeTeamId === expected.activeTeamId &&
    existing.schemaVersion === expected.schemaVersion
  ) {
    return 'noop';
  }
  return 'write';
}
