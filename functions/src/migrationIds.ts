/**
 * Deterministic ID helpers for the multi-team migration.
 *
 * The membership document id must be a pure function of (teamId, memberId)
 * so that re-running the migration (or the compatibility trigger) always
 * targets the same document — this is what makes the migration idempotent.
 *
 * The same reasoning applies to the bookkeeping collections
 * (`migrationConflicts` / `migrationErrors`): their ids must preserve the
 * *context* a record refers to, not just the user. A user can produce a
 * blocking conflict on team A (e.g. a foreign membership document at
 * `teamA__user`) and then be moved to team B; if both records collapsed
 * onto `migrationConflicts/{userId}`, a clean migration of team B would
 * delete team A's conflict while the foreign document is still sitting
 * there — silently opening the cutover gate. See
 * {@link buildScopedRecordId} / {@link conflictDocId}.
 */
import { MigrationConflictReason } from './types';

const SEPARATOR = '__';

/**
 * Scope segment used for bookkeeping records that are about the legacy
 * *user record itself* rather than about one team (e.g.
 * `invalid_legacy_record`: the document does not parse, so its team cannot
 * be trusted — and once the record is repaired the conflict is genuinely
 * resolved regardless of which team the user ends up on).
 *
 * It cannot collide with a real team scope in practice: team ids are
 * Firestore auto-ids (`[A-Za-z0-9]{20}`) and therefore never start with an
 * underscore.
 */
export const RECORD_SCOPE = '_record';

/** Whether a bookkeeping record is about one team or about the user record. */
export type RecordScope = 'team' | 'record';

/** Builds the deterministic `teamMemberships` document id. */
export function buildMembershipId(teamId: string, memberId: string): string {
  if (!teamId) {
    throw new Error('buildMembershipId requires a non-empty teamId.');
  }
  if (!memberId) {
    throw new Error('buildMembershipId requires a non-empty memberId.');
  }
  return `${teamId}${SEPARATOR}${memberId}`;
}

/** Splits a membership document id back into its (teamId, memberId) parts. */
export function parseMembershipId(
  membershipId: string,
): { teamId: string; memberId: string } | null {
  const index = membershipId.indexOf(SEPARATOR);
  if (index <= 0 || index === membershipId.length - SEPARATOR.length) {
    return null;
  }
  return {
    teamId: membershipId.slice(0, index),
    memberId: membershipId.slice(index + SEPARATOR.length),
  };
}

/**
 * Builds the deterministic `migrationConflicts`/`migrationErrors` document
 * id for one (user, context) pair:
 *
 * - team context (`teamId` given): `{teamId}__{legacyUserId}` — the same id
 *   as the membership document the record is about, so a record can never
 *   be confused with (or overwritten by) one for another team.
 * - record context (`teamId === null`): `_record__{legacyUserId}` — the
 *   record is about the legacy user document itself.
 */
export function buildScopedRecordId(legacyUserId: string, teamId: string | null): string {
  if (!legacyUserId) {
    throw new Error('buildScopedRecordId requires a non-empty legacyUserId.');
  }
  const scope = teamId && teamId.length > 0 ? teamId : RECORD_SCOPE;
  return `${scope}${SEPARATOR}${legacyUserId}`;
}

/**
 * The scope a conflict belongs to. `invalid_legacy_record` is *always*
 * record-scoped — even when the malformed document happens to carry a
 * readable `teamId` — because the problem (and its repair) is the legacy
 * record itself, not a specific team. Every other reason describes a
 * problem with one team's membership document and is team-scoped.
 */
export function conflictScope(reason: MigrationConflictReason, teamId: string | null): RecordScope {
  return reason !== 'invalid_legacy_record' && !!teamId && teamId.length > 0 ? 'team' : 'record';
}

/** Deterministic `migrationConflicts` document id for a conflict. */
export function conflictDocId(conflict: {
  legacyUserId: string;
  teamId: string | null;
  reason: MigrationConflictReason;
}): string {
  const scope = conflictScope(conflict.reason, conflict.teamId);
  return buildScopedRecordId(conflict.legacyUserId, scope === 'team' ? conflict.teamId : null);
}

/**
 * Deterministic `migrationErrors` document id. A transient processing
 * failure is recorded against the team context the user had when it
 * happened (or the record scope when the document carries no usable
 * `teamId`), so an error raised while the user was on team A is never
 * silently cleared by a later clean pass over team B.
 */
export function errorDocId(legacyUserId: string, teamId: string | null): string {
  return buildScopedRecordId(legacyUserId, teamId);
}
