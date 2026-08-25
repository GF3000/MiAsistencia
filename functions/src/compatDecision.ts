/**
 * Pure decision logic for the temporary old-client compatibility trigger
 * (`users/{userId}` onDocumentWritten). Given the event's `before` snapshot,
 * the *fresh* current user state read inside the transaction, and whatever
 * membership documents already exist, this decides whether anything needs
 * to be synced and computes the exact resulting documents — without touching
 * Firestore, which keeps it fully unit testable.
 *
 * Design invariants enforced here (see functions/README.md for the full
 * writeup):
 *  - If the triggering write changed `membershipWriteToken`, a V2 client
 *    transaction already kept everything consistent: no-op.
 *  - Never delete/shrink `membershipPeriods` or `attendanceDefaultHistory`;
 *    only append to them or close/open the trailing period.
 *  - Never let a shorter/older legacy `attendanceDefaultHistory` replace a
 *    longer one already present on the membership document.
 *  - Never invent a join date: creating a membership without a
 *    `teamJoinedAt`/`createdAt` to draw on is a durable conflict, not a
 *    guess.
 *  - Never stamp or overwrite a membership document that this migration did
 *    not produce (foreign/non-V2 data): that is a durable conflict too.
 *  - When a member leaves/deactivates/is deleted, close the trailing open
 *    period *and* set `active=false`, preserving all prior history.
 *  - Idempotent: computing from the fresh current state means a redelivered
 *    or out-of-order event converges to the same target and returns `noop`
 *    once the stored state already matches.
 */
import { Timestamp } from 'firebase-admin/firestore';
import { buildMembershipId } from './migrationIds';
import { MIGRATION_VERSION } from './config';
import { decideMembershipWrite, ExistingMembershipShape } from './idempotency';
import {
  AttendanceDefaultChange,
  AttendanceDefaultStatus,
  LegacyUserRecord,
  MembershipPeriod,
  MigrationConflict,
  ProfileUpdate,
  TeamMembershipRecord,
} from './types';

function millisOrNull(value: Timestamp | null): number | null {
  return value ? value.toMillis() : null;
}

function attendanceHistoryEqual(a: AttendanceDefaultChange[], b: AttendanceDefaultChange[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  return a.every((change, index) => {
    const other = b[index];
    return !!other && change.status === other.status && change.effectiveFrom.toMillis() === other.effectiveFrom.toMillis();
  });
}

function relevantFieldsEqual(before: LegacyUserRecord, after: LegacyUserRecord): boolean {
  return (
    before.teamId === after.teamId &&
    millisOrNull(before.teamJoinedAt) === millisOrNull(after.teamJoinedAt) &&
    before.role === after.role &&
    before.active === after.active &&
    before.managedByCoach === after.managedByCoach &&
    before.attendanceDefaultStatus === after.attendanceDefaultStatus &&
    attendanceHistoryEqual(before.attendanceDefaultHistory, after.attendanceDefaultHistory) &&
    before.fullName === after.fullName &&
    before.email === after.email
  );
}

/** Closes the trailing open period at `at`, or is a no-op if none is open. */
function closeOpenPeriod(periods: MembershipPeriod[], at: Timestamp): MembershipPeriod[] {
  const openIndex = periods.findIndex((period) => period.leftAt === null);
  if (openIndex === -1) {
    return periods;
  }
  const openPeriod = periods[openIndex];
  if (!openPeriod) {
    return periods;
  }
  const leftAt = at.toMillis() < openPeriod.joinedAt.toMillis() ? openPeriod.joinedAt : at;
  const next = periods.slice();
  next[openIndex] = { joinedAt: openPeriod.joinedAt, leftAt };
  return next;
}

/** Appends a new open period at `joinedAt`, or is a no-op if one is already open. */
function openNewPeriod(periods: MembershipPeriod[], joinedAt: Timestamp): MembershipPeriod[] {
  if (periods.some((period) => period.leftAt === null)) {
    return periods;
  }
  return [...periods, { joinedAt, leftAt: null }];
}

/**
 * Reconciles the trailing period against the merged membership's `active`
 * flag so a membership's open/closed state always matches `active`, no
 * matter how we arrived here (team switch into a previously-inactive
 * membership, an in-place active flip, or repairing a doc that drifted out
 * of sync). Returns the same array reference when nothing needs to change so
 * callers can use reference equality to detect "nothing actually changed".
 */
function reconcilePeriods(periods: MembershipPeriod[], active: boolean, at: Timestamp): MembershipPeriod[] {
  const hasOpenPeriod = periods.some((period) => period.leftAt === null);
  if (active && !hasOpenPeriod) {
    return openNewPeriod(periods, at);
  }
  if (!active && hasOpenPeriod) {
    return closeOpenPeriod(periods, at);
  }
  return periods;
}

/**
 * Merges legacy attendance defaults into an existing membership without
 * ever regressing a richer (longer) history already stored there.
 */
function mergeAttendanceDefaults(
  existing: Pick<TeamMembershipRecord, 'attendanceDefaultStatus' | 'attendanceDefaultHistory'>,
  legacy: Pick<LegacyUserRecord, 'attendanceDefaultStatus' | 'attendanceDefaultHistory'>,
): Pick<TeamMembershipRecord, 'attendanceDefaultStatus' | 'attendanceDefaultHistory'> {
  if (legacy.attendanceDefaultHistory.length < existing.attendanceDefaultHistory.length) {
    return existing;
  }
  if (
    legacy.attendanceDefaultStatus === existing.attendanceDefaultStatus &&
    attendanceHistoryEqual(legacy.attendanceDefaultHistory, existing.attendanceDefaultHistory)
  ) {
    // Content-identical: return the original references so callers can use
    // reference equality to detect "nothing actually changed".
    return existing;
  }
  return { attendanceDefaultStatus: legacy.attendanceDefaultStatus, attendanceDefaultHistory: legacy.attendanceDefaultHistory };
}

/** Builds the single initial period for a brand-new membership. */
function initialPeriods(active: boolean, joinedAt: Timestamp, eventTime: Timestamp): MembershipPeriod[] {
  if (active) {
    return [{ joinedAt, leftAt: null }];
  }
  // Inactive at creation: close immediately at the fixed event timestamp,
  // never inverting the range if the join date is somehow later.
  const leftAt = eventTime.toMillis() > joinedAt.toMillis() ? eventTime : joinedAt;
  return [{ joinedAt, leftAt }];
}

export interface MembershipUpsert {
  membershipId: string;
  membership: TeamMembershipRecord;
}

export type CompatPlan =
  | { kind: 'noop'; reason: string }
  | { kind: 'conflict'; reason: string; conflict: MigrationConflict }
  | {
      kind: 'sync';
      reason: string;
      closeOldMembership: MembershipUpsert | null;
      upsertNewMembership: MembershipUpsert | null;
      profileUpdate: ProfileUpdate | null;
    };

export interface CompatSyncInput {
  userId: string;
  /** Event `before` snapshot (pre-write). `null` for a document create. */
  before: LegacyUserRecord | null;
  /**
   * The *fresh* current user state, read inside the transaction. `null`
   * when the user document no longer exists (a delete). Computing the
   * target from this — rather than the event's immutable `after` snapshot —
   * is what prevents an out-of-order/stale redelivery from regressing the
   * membership or profile.
   */
  after: LegacyUserRecord | null;
  eventTime: Timestamp;
  /**
   * Whether the triggering write itself changed `membershipWriteToken`
   * (computed by the trigger from the event's before/after tokens). `true`
   * means a V2 client transaction already synchronized everything.
   */
  writeChangedToken: boolean;
  /** Raw stored `teamMemberships` doc for `before.teamId`, if any. */
  existingOldMembership: Record<string, unknown> | null;
  /** Raw stored `teamMemberships` doc for the current team, if any. */
  existingNewMembership: Record<string, unknown> | null;
}

type MembershipGuard =
  | { kind: 'absent' }
  | { kind: 'owned'; membership: TeamMembershipRecord }
  | { kind: 'conflict'; detail: string };

const VALID_ATTENDANCE_STATUSES: readonly AttendanceDefaultStatus[] = ['attending', 'absent'];

function isTimestamp(value: unknown): value is Timestamp {
  return value instanceof Timestamp;
}

function hasValidMembershipPeriods(value: unknown): value is MembershipPeriod[] {
  if (!Array.isArray(value)) {
    return false;
  }
  return value.every((period) => {
    if (typeof period !== 'object' || period === null) {
      return false;
    }
    const raw = period as Record<string, unknown>;
    if (!isTimestamp(raw.joinedAt)) {
      return false;
    }
    return raw.leftAt === null || raw.leftAt === undefined || isTimestamp(raw.leftAt);
  });
}

function hasValidAttendanceHistory(value: unknown): value is AttendanceDefaultChange[] {
  if (!Array.isArray(value)) {
    return false;
  }
  return value.every((change) => {
    if (typeof change !== 'object' || change === null) {
      return false;
    }
    const raw = change as Record<string, unknown>;
    return (
      typeof raw.status === 'string' &&
      VALID_ATTENDANCE_STATUSES.includes(raw.status as AttendanceDefaultStatus) &&
      isTimestamp(raw.effectiveFrom)
    );
  });
}

function hasOwnedMembershipShape(raw: Record<string, unknown>): raw is TeamMembershipRecord {
  return (
    typeof raw.teamId === 'string' &&
    typeof raw.memberId === 'string' &&
    typeof raw.active === 'boolean' &&
    typeof raw.managedByCoach === 'boolean' &&
    (raw.userId === null || typeof raw.userId === 'string') &&
    typeof raw.fullName === 'string' &&
    typeof raw.email === 'string' &&
    (raw.role === 'admin' || raw.role === 'player') &&
    (raw.attendanceDefaultStatus === 'attending' || raw.attendanceDefaultStatus === 'absent') &&
    hasValidMembershipPeriods(raw.membershipPeriods) &&
    hasValidAttendanceHistory(raw.attendanceDefaultHistory) &&
    isTimestamp(raw.createdAt) &&
    isTimestamp(raw.updatedAt) &&
    raw.migrationVersion === MIGRATION_VERSION
  );
}

/**
 * Applies the exact same ownership/shape/version guard the migration uses
 * before touching an existing membership document: absent (safe to create),
 * owned (a V2 doc this system produced, safe to update), or a conflict (any
 * foreign/non-V2/mismatched document, which must never be overwritten).
 */
function guardExistingMembership(
  raw: Record<string, unknown> | null,
  expected: { teamId: string; memberId: string },
): MembershipGuard {
  const decision = decideMembershipWrite(raw as ExistingMembershipShape | null, expected);
  if (decision.action === 'create') {
    return { kind: 'absent' };
  }
  if (decision.action === 'conflict') {
    return { kind: 'conflict', detail: decision.detail };
  }
  if (!raw || !hasOwnedMembershipShape(raw)) {
    return {
      kind: 'conflict',
      detail:
        `teamMemberships/${buildMembershipId(expected.teamId, expected.memberId)} has migration identity ` +
        'but an invalid owned-document shape; refusing to mutate it.',
    };
  }
  return { kind: 'owned', membership: raw };
}

function conflictPlan(userId: string, teamId: string, detail: string): CompatPlan {
  return {
    kind: 'conflict',
    reason: 'existing membership is not owned by this migration; refusing to overwrite.',
    conflict: {
      legacyUserId: userId,
      teamId,
      reason: 'membership_exists_incompatible',
      detail,
    },
  };
}

function missingJoinDateConflict(userId: string, teamId: string): CompatPlan {
  return {
    kind: 'conflict',
    reason: 'cannot create a membership without a join date.',
    conflict: {
      legacyUserId: userId,
      teamId,
      reason: 'missing_join_timestamp',
      detail:
        'Neither teamJoinedAt nor createdAt is set on the user; refusing to invent a join date for the membership.',
    },
  };
}

export function decideCompatSync(input: CompatSyncInput): CompatPlan {
  const { userId, before, after, eventTime } = input;

  if (input.writeChangedToken) {
    return {
      kind: 'noop',
      reason: 'membershipWriteToken changed: a V2 client transaction already synced this write.',
    };
  }

  // ---- Delete: the legacy user document was removed. -----------------
  if (after === null) {
    if (!before || !before.teamId) {
      return { kind: 'noop', reason: 'user deleted but had no team membership to close.' };
    }
    const guard = guardExistingMembership(input.existingOldMembership, {
      teamId: before.teamId,
      memberId: userId,
    });
    if (guard.kind === 'conflict') {
      return conflictPlan(userId, before.teamId, guard.detail);
    }
    if (guard.kind === 'absent') {
      return { kind: 'noop', reason: 'user deleted; no membership document to close.' };
    }
    const openIndex = guard.membership.membershipPeriods.findIndex((p) => p.leftAt === null);
    if (openIndex === -1 && guard.membership.active === false) {
      return { kind: 'noop', reason: 'user deleted; membership already closed and inactive.' };
    }
    const closedPeriods = closeOpenPeriod(guard.membership.membershipPeriods, eventTime);
    return {
      kind: 'sync',
      reason: 'legacy user deleted; closing membership and marking it inactive.',
      closeOldMembership: {
        membershipId: buildMembershipId(before.teamId, userId),
        membership: {
          ...guard.membership,
          membershipPeriods: closedPeriods,
          active: false,
          updatedAt: eventTime,
        },
      },
      upsertNewMembership: null,
      // The user document is gone; never resurrect it with a profile mirror.
      profileUpdate: null,
    };
  }

  // ---- Create / update: `after` is the fresh current state. ----------
  if (before && relevantFieldsEqual(before, after)) {
    return { kind: 'noop', reason: 'no membership-relevant fields changed (redelivery or unrelated write).' };
  }

  const teamChanged = before !== null && before.teamId !== after.teamId;

  // Close the membership on the team the user just left.
  let closeOldMembership: MembershipUpsert | null = null;
  if (teamChanged && before && before.teamId) {
    const guard = guardExistingMembership(input.existingOldMembership, {
      teamId: before.teamId,
      memberId: userId,
    });
    if (guard.kind === 'conflict') {
      return conflictPlan(userId, before.teamId, guard.detail);
    }
    if (guard.kind === 'owned') {
      const openIndex = guard.membership.membershipPeriods.findIndex((p) => p.leftAt === null);
      if (openIndex !== -1) {
        closeOldMembership = {
          membershipId: buildMembershipId(before.teamId, userId),
          membership: {
            ...guard.membership,
            membershipPeriods: closeOpenPeriod(guard.membership.membershipPeriods, eventTime),
            active: false,
            updatedAt: eventTime,
          },
        };
      }
    }
  }

  // Create/update the membership on the current team.
  let upsertNewMembership: MembershipUpsert | null = null;
  if (after.teamId) {
    const guard = guardExistingMembership(input.existingNewMembership, {
      teamId: after.teamId,
      memberId: userId,
    });
    if (guard.kind === 'conflict') {
      return conflictPlan(userId, after.teamId, guard.detail);
    }

    if (guard.kind === 'absent') {
      const joinedAt = after.teamJoinedAt ?? after.createdAt;
      if (joinedAt === null) {
        return missingJoinDateConflict(userId, after.teamId);
      }
      upsertNewMembership = {
        membershipId: buildMembershipId(after.teamId, userId),
        membership: {
          teamId: after.teamId,
          memberId: userId,
          userId: after.managedByCoach ? null : userId,
          fullName: after.fullName,
          email: after.email,
          role: after.role,
          active: after.active,
          managedByCoach: after.managedByCoach,
          membershipPeriods: initialPeriods(after.active, joinedAt, eventTime),
          attendanceDefaultStatus: after.attendanceDefaultStatus,
          attendanceDefaultHistory: after.attendanceDefaultHistory,
          createdAt: after.createdAt ?? joinedAt,
          updatedAt: eventTime,
          migrationVersion: MIGRATION_VERSION,
        },
      };
    } else {
      const existing = guard.membership;
      let periods = existing.membershipPeriods;
      if (teamChanged && after.active) {
        // Rejoining a team the member was previously in while active: append
        // a new open period. Prefer an explicit join date; otherwise the
        // observed event time is the truthful "rejoined now" instant.
        periods = openNewPeriod(periods, after.teamJoinedAt ?? after.createdAt ?? eventTime);
      }
      // Reconcile the merged state after applying the plan: an active member
      // must have an open period, an inactive one must not. This also fixes a
      // team switch into an existing *inactive* membership (no spurious open
      // period is created) and repairs any doc that drifted out of sync.
      periods = reconcilePeriods(periods, after.active, eventTime);
      const attendanceDefaults = mergeAttendanceDefaults(existing, after);
      const merged: TeamMembershipRecord = {
        ...existing,
        fullName: after.fullName,
        email: after.email,
        role: after.role,
        active: after.active,
        managedByCoach: after.managedByCoach,
        membershipPeriods: periods,
        attendanceDefaultStatus: attendanceDefaults.attendanceDefaultStatus,
        attendanceDefaultHistory: attendanceDefaults.attendanceDefaultHistory,
        updatedAt: eventTime,
        migrationVersion: MIGRATION_VERSION,
      };
      const unchanged =
        merged.fullName === existing.fullName &&
        merged.email === existing.email &&
        merged.role === existing.role &&
        merged.active === existing.active &&
        merged.managedByCoach === existing.managedByCoach &&
        merged.membershipPeriods === existing.membershipPeriods &&
        merged.attendanceDefaultStatus === existing.attendanceDefaultStatus &&
        merged.attendanceDefaultHistory === existing.attendanceDefaultHistory;
      if (!unchanged) {
        upsertNewMembership = { membershipId: buildMembershipId(after.teamId, userId), membership: merged };
      }
    }
  }

  const desiredProfile: ProfileUpdate = { activeTeamId: after.teamId, schemaVersion: MIGRATION_VERSION };
  const profileUpdate =
    after.activeTeamId === desiredProfile.activeTeamId && after.schemaVersion === desiredProfile.schemaVersion
      ? null
      : desiredProfile;

  if (!closeOldMembership && !upsertNewMembership && !profileUpdate) {
    return { kind: 'noop', reason: 'computed target state already matches stored state.' };
  }

  return {
    kind: 'sync',
    reason: teamChanged
      ? 'team membership changed via an old client.'
      : 'membership-relevant fields changed via an old client.',
    closeOldMembership,
    upsertNewMembership,
    profileUpdate,
  };
}
