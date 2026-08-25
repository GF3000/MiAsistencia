/**
 * Shared type definitions for the multi-team membership migration (Phase 2).
 *
 * These types intentionally mirror the Dart domain model in
 * `lib/src/models/app_user.dart` and `lib/src/models/team_membership.dart` so
 * the backend and the future Flutter client agree on wire shapes.
 */
import { Timestamp } from 'firebase-admin/firestore';

export type UserRole = 'admin' | 'player';

export type AttendanceDefaultStatus = 'attending' | 'absent';

/** One entry of `attendanceDefaultHistory` on a legacy user or membership. */
export interface AttendanceDefaultChange {
  status: AttendanceDefaultStatus;
  effectiveFrom: Timestamp;
}

/** Shape of a legacy `users/{userId}` document, as read from Firestore. */
export interface LegacyUserRecord {
  id: string;
  email: string;
  fullName: string;
  role: UserRole;
  teamId: string | null;
  teamJoinedAt: Timestamp | null;
  active: boolean;
  managedByCoach: boolean;
  attendanceDefaultStatus: AttendanceDefaultStatus;
  attendanceDefaultHistory: AttendanceDefaultChange[];
  createdAt: Timestamp | null;
  activeTeamId: string | null;
  schemaVersion: number | null;
  /**
   * Set by a V2-client atomic transaction on every write that already keeps
   * `teamMemberships/*` and this legacy mirror in sync. Used by the
   * compatibility trigger to detect and ignore its own/no-op deliveries.
   */
  membershipWriteToken: string | null;
}

/** `[joinedAt, leftAt)` span of continuous membership in a team. */
export interface MembershipPeriod {
  joinedAt: Timestamp;
  leftAt: Timestamp | null;
}

/**
 * Shape of a `teamMemberships/{teamId}__{memberId}` document.
 *
 * Declared as a `type` (not an `interface`) on purpose: a closed object
 * type is assignable to `Record<string, unknown>`, which lets the pure
 * compatibility/idempotency guards accept a validated membership record and
 * a raw Firestore document body through the same parameter.
 */
export type TeamMembershipRecord = {
  teamId: string;
  memberId: string;
  userId: string | null;
  fullName: string;
  email: string;
  role: UserRole;
  active: boolean;
  managedByCoach: boolean;
  membershipPeriods: MembershipPeriod[];
  attendanceDefaultStatus: AttendanceDefaultStatus;
  attendanceDefaultHistory: AttendanceDefaultChange[];
  createdAt: Timestamp;
  updatedAt: Timestamp;
  migrationVersion: 2;
};

/**
 * Partial update applied to `users/{userId}` alongside the migration/trigger.
 * `activeTeamId` may be null: the compatibility trigger sets it back to
 * null when an old client removes the user's team entirely.
 */
export interface ProfileUpdate {
  activeTeamId: string | null;
  schemaVersion: 2;
}

export type MigrationConflictReason =
  | 'missing_join_timestamp'
  | 'membership_exists_incompatible'
  | 'invalid_legacy_record';

export interface MigrationConflict {
  legacyUserId: string;
  teamId: string | null;
  reason: MigrationConflictReason;
  detail: string;
}

export type MappingResult =
  | { kind: 'skippedNoTeam' }
  | { kind: 'conflict'; conflict: MigrationConflict }
  | {
      kind: 'mapped';
      membershipId: string;
      membership: TeamMembershipRecord;
      profileUpdate: ProfileUpdate;
    };
