/**
 * Pure mapping and validation helpers for the legacy `users/{userId}` ->
 * `teamMemberships/{teamId}__{memberId}` migration.
 *
 * Nothing in this module touches Firestore/Admin SDK network calls: it only
 * operates on plain data (using the value-only `Timestamp` class), which
 * keeps it trivially unit-testable and reusable from both the HTTP
 * migration runner and the compatibility trigger.
 */
import { Timestamp } from 'firebase-admin/firestore';
import { buildMembershipId } from './migrationIds';
import {
  AttendanceDefaultChange,
  AttendanceDefaultStatus,
  LegacyUserRecord,
  MappingResult,
  MembershipPeriod,
  TeamMembershipRecord,
  UserRole,
} from './types';

export interface ParseSuccess {
  ok: true;
  user: LegacyUserRecord;
}

export interface ParseFailure {
  ok: false;
  error: string;
}

export type ParseResult = ParseSuccess | ParseFailure;

export type MembershipParseResult =
  | { ok: true; membership: TeamMembershipRecord }
  | { ok: false; error: string };

const VALID_ROLES: readonly UserRole[] = ['admin', 'player'];
const VALID_ATTENDANCE_STATUSES: readonly AttendanceDefaultStatus[] = [
  'attending',
  'absent',
];

function isTimestamp(value: unknown): value is Timestamp {
  return value instanceof Timestamp;
}

/**
 * Parses and validates a raw Firestore `users/{userId}` document body into a
 * strongly typed {@link LegacyUserRecord}, or reports why it is malformed.
 *
 * This is intentionally defensive: legacy documents were written over time
 * by evolving client versions and are not guaranteed to match the current
 * shape exactly.
 */
export function parseLegacyUser(id: string, data: Record<string, unknown>): ParseResult {
  if (typeof data.email !== 'string') {
    return { ok: false, error: 'email must be a string.' };
  }
  if (typeof data.fullName !== 'string' || data.fullName.length === 0) {
    return { ok: false, error: 'fullName must be a non-empty string.' };
  }
  if (typeof data.role !== 'string' || !VALID_ROLES.includes(data.role as UserRole)) {
    return { ok: false, error: `role must be one of ${VALID_ROLES.join(', ')}.` };
  }
  if (data.teamId !== null && data.teamId !== undefined && typeof data.teamId !== 'string') {
    return { ok: false, error: 'teamId must be a string or null.' };
  }
  if (data.teamJoinedAt !== null && data.teamJoinedAt !== undefined && !isTimestamp(data.teamJoinedAt)) {
    return { ok: false, error: 'teamJoinedAt must be a Firestore Timestamp or null.' };
  }
  if (typeof data.active !== 'boolean') {
    return { ok: false, error: 'active must be a boolean.' };
  }
  if (data.managedByCoach !== undefined && typeof data.managedByCoach !== 'boolean') {
    return { ok: false, error: 'managedByCoach must be a boolean.' };
  }
  if (
    data.attendanceDefaultStatus !== undefined &&
    (typeof data.attendanceDefaultStatus !== 'string' ||
      !VALID_ATTENDANCE_STATUSES.includes(data.attendanceDefaultStatus as AttendanceDefaultStatus))
  ) {
    return {
      ok: false,
      error: `attendanceDefaultStatus must be one of ${VALID_ATTENDANCE_STATUSES.join(', ')}.`,
    };
  }
  if (data.attendanceDefaultHistory !== undefined && !Array.isArray(data.attendanceDefaultHistory)) {
    return { ok: false, error: 'attendanceDefaultHistory must be an array.' };
  }
  const history: AttendanceDefaultChange[] = [];
  for (const raw of (data.attendanceDefaultHistory as unknown[] | undefined) ?? []) {
    if (
      typeof raw !== 'object' ||
      raw === null ||
      !VALID_ATTENDANCE_STATUSES.includes((raw as Record<string, unknown>).status as AttendanceDefaultStatus) ||
      !isTimestamp((raw as Record<string, unknown>).effectiveFrom)
    ) {
      return { ok: false, error: 'attendanceDefaultHistory entries must have a valid status and effectiveFrom.' };
    }
    history.push({
      status: (raw as Record<string, unknown>).status as AttendanceDefaultStatus,
      effectiveFrom: (raw as Record<string, unknown>).effectiveFrom as Timestamp,
    });
  }
  if (data.createdAt !== null && data.createdAt !== undefined && !isTimestamp(data.createdAt)) {
    return { ok: false, error: 'createdAt must be a Firestore Timestamp or null.' };
  }
  if (data.activeTeamId !== null && data.activeTeamId !== undefined && typeof data.activeTeamId !== 'string') {
    return { ok: false, error: 'activeTeamId must be a string or null.' };
  }
  if (data.schemaVersion !== null && data.schemaVersion !== undefined && typeof data.schemaVersion !== 'number') {
    return { ok: false, error: 'schemaVersion must be a number or null.' };
  }
  if (
    data.membershipWriteToken !== null &&
    data.membershipWriteToken !== undefined &&
    typeof data.membershipWriteToken !== 'string'
  ) {
    return { ok: false, error: 'membershipWriteToken must be a string or null.' };
  }

  return {
    ok: true,
    user: {
      id,
      email: data.email,
      fullName: data.fullName,
      role: data.role as UserRole,
      teamId: (data.teamId as string | undefined) ?? null,
      teamJoinedAt: (data.teamJoinedAt as Timestamp | undefined) ?? null,
      active: data.active,
      managedByCoach: (data.managedByCoach as boolean | undefined) ?? false,
      attendanceDefaultStatus: (data.attendanceDefaultStatus as AttendanceDefaultStatus | undefined) ?? 'attending',
      attendanceDefaultHistory: history,
      createdAt: (data.createdAt as Timestamp | undefined) ?? null,
      activeTeamId: (data.activeTeamId as string | undefined) ?? null,
      schemaVersion: (data.schemaVersion as number | undefined) ?? null,
      membershipWriteToken: (data.membershipWriteToken as string | undefined) ?? null,
    },
  };
}

export interface MappingOptions {
  /**
   * A single fixed instant recorded once when a migration run starts
   * (`migrations/multiTeamV2.startedAt`). Reused for every user processed by
   * that run so that inactive-member period closures are deterministic and
   * reproducible across pages/retries, instead of using "now" per user.
   */
  migrationStartedAt: Timestamp;
}

/**
 * Maps a validated legacy user into its target `teamMemberships` document,
 * or explains why it cannot be migrated (yet).
 *
 * Period semantics for members who are no longer active
 * (`active === false`): the legacy schema has no "left the team at" instant,
 * so we deliberately do not invent one per user. Instead every inactive
 * member migrated by the same run is closed at the same fixed
 * `migrationStartedAt` instant — i.e. "as of this migration, this person is
 * recorded as having left". This keeps the whole run reproducible (running
 * it again, or resuming it, yields byte-identical output) and avoids
 * fabricating a plausible-looking but false leave date.
 */
export function mapLegacyUserToMembership(
  user: LegacyUserRecord,
  options: MappingOptions,
): MappingResult {
  if (user.teamId === null || user.teamId.length === 0) {
    return { kind: 'skippedNoTeam' };
  }

  const joinedAt = user.teamJoinedAt ?? user.createdAt;
  if (joinedAt === null) {
    return {
      kind: 'conflict',
      conflict: {
        legacyUserId: user.id,
        teamId: user.teamId,
        reason: 'missing_join_timestamp',
        detail:
          'Neither teamJoinedAt nor createdAt is set; refusing to invent a join date.',
      },
    };
  }

  const membershipId = buildMembershipId(user.teamId, user.id);
  const periods: MembershipPeriod[] = user.active
    ? [{ joinedAt, leftAt: null }]
    : [
        {
          joinedAt,
          // Never invert a period: if the fixed migration instant is not
          // after the join date (e.g. a just-created, already-inactive
          // record), close it immediately instead of producing leftAt <
          // joinedAt.
          leftAt:
            options.migrationStartedAt.toMillis() > joinedAt.toMillis()
              ? options.migrationStartedAt
              : joinedAt,
        },
      ];

  const membership = {
    teamId: user.teamId,
    memberId: user.id,
    userId: user.managedByCoach ? null : user.id,
    fullName: user.fullName,
    email: user.email,
    role: user.role,
    active: user.active,
    managedByCoach: user.managedByCoach,
    membershipPeriods: periods,
    attendanceDefaultStatus: user.attendanceDefaultStatus,
    attendanceDefaultHistory: user.attendanceDefaultHistory,
    createdAt: user.createdAt ?? joinedAt,
    updatedAt: options.migrationStartedAt,
    migrationVersion: 2 as const,
  };

  return {
    kind: 'mapped',
    membershipId,
    membership,
    profileUpdate: { activeTeamId: user.teamId, schemaVersion: 2 as const },
  };
}

/** Convenience wrapper combining parsing and mapping for the migration runner. */
export function mapLegacyUserDocToMembership(
  id: string,
  data: Record<string, unknown>,
  options: MappingOptions,
): MappingResult {
  const parsed = parseLegacyUser(id, data);
  if (!parsed.ok) {
    return {
      kind: 'conflict',
      conflict: {
        legacyUserId: id,
        teamId: typeof data.teamId === 'string' ? data.teamId : null,
        reason: 'invalid_legacy_record',
        detail: parsed.error,
      },
    };
  }
  return mapLegacyUserToMembership(parsed.user, options);
}
