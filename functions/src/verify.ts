/**
 * Read-only verification for the multi-team membership migration: compares
 * what {@link mapLegacyUserDocToMembership} says the state *should* be
 * against what is actually stored in `teamMemberships`/`users`, and reports
 * mismatches without writing anything.
 */
import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { TEAM_MEMBERSHIPS_COLLECTION, USERS_COLLECTION } from './config';
import { mapLegacyUserDocToMembership } from './mapping';
import { MigrationConflict, ProfileUpdate, TeamMembershipRecord } from './types';
import { checkpointRef, clampPageSize, fetchUserPage, MigrationCheckpointDoc } from './migrationRunner';

export interface FieldMismatch {
  field: string;
  expected: unknown;
  actual: unknown;
}

function timestampMillisOrNull(value: unknown): number | null {
  return value instanceof Timestamp ? value.toMillis() : null;
}

interface ComparablePeriod {
  joinedAt: number;
  leftAt: number | null;
}

interface ComparableHistoryEntry {
  status: string;
  effectiveFrom: number;
}

const VALID_ATTENDANCE_STATUSES = new Set(['attending', 'absent']);

function parseComparablePeriods(value: unknown): ComparablePeriod[] | null {
  if (!Array.isArray(value)) {
    return null;
  }
  const parsed: ComparablePeriod[] = [];
  for (const raw of value) {
    const period = raw as Record<string, unknown> | null | undefined;
    if (!period) {
      return null;
    }
    const joinedAt = timestampMillisOrNull(period.joinedAt);
    const leftAtRaw = period.leftAt;
    const leftAt =
      leftAtRaw === null || leftAtRaw === undefined
        ? null
        : timestampMillisOrNull(leftAtRaw);
    if (joinedAt === null) {
      return null;
    }
    if (leftAtRaw !== null && leftAtRaw !== undefined && leftAt === null) {
      return null;
    }
    parsed.push({ joinedAt, leftAt });
  }
  return parsed;
}

function periodsEqual(expected: TeamMembershipRecord['membershipPeriods'], actual: ComparablePeriod[]): boolean {
  if (actual.length !== expected.length) {
    return false;
  }
  for (let i = 0; i < expected.length; i++) {
    const expectedPeriod = expected[i];
    const actualPeriod = actual[i];
    if (!expectedPeriod || !actualPeriod || expectedPeriod.joinedAt.toMillis() !== actualPeriod.joinedAt) {
      return false;
    }
    const expectedLeft = expectedPeriod.leftAt ? expectedPeriod.leftAt.toMillis() : null;
    if (expectedLeft !== actualPeriod.leftAt) {
      return false;
    }
  }
  return true;
}

function periodsSemanticallyCompatible(
  expected: TeamMembershipRecord['membershipPeriods'],
  actual: ComparablePeriod[],
  expectedActive: boolean,
): boolean {
  if (actual.length === 0) {
    return false;
  }
  if (periodsEqual(expected, actual)) {
    return true;
  }
  const hasOpenPeriod = actual.some((period) => period.leftAt === null);
  if (expectedActive && !hasOpenPeriod) {
    return false;
  }
  if (!expectedActive && hasOpenPeriod) {
    return false;
  }
  const expectedCurrent = expected[expected.length - 1];
  if (!expectedCurrent) {
    return false;
  }
  const matchingCurrent = actual.find((period) => period.joinedAt === expectedCurrent.joinedAt.toMillis());
  if (!matchingCurrent) {
    return false;
  }
  if (expectedCurrent.leftAt === null) {
    return matchingCurrent.leftAt === null;
  }
  return matchingCurrent.leftAt !== null && matchingCurrent.leftAt >= expectedCurrent.leftAt.toMillis();
}

function parseComparableHistory(value: unknown): ComparableHistoryEntry[] | null {
  if (!Array.isArray(value)) {
    return null;
  }
  const parsed: ComparableHistoryEntry[] = [];
  for (const raw of value) {
    const item = raw as Record<string, unknown> | null | undefined;
    if (
      !item ||
      typeof item.status !== 'string' ||
      !VALID_ATTENDANCE_STATUSES.has(item.status)
    ) {
      return null;
    }
    const effectiveFrom = timestampMillisOrNull(item.effectiveFrom);
    if (effectiveFrom === null) {
      return null;
    }
    parsed.push({ status: item.status, effectiveFrom });
  }
  return parsed;
}

function historyCompatible(
  expected: TeamMembershipRecord['attendanceDefaultHistory'],
  actual: ComparableHistoryEntry[],
): boolean {
  if (actual.length < expected.length) {
    return false;
  }
  for (let i = 0; i < expected.length; i++) {
    const expectedChange = expected[i];
    const actualChange = actual[i];
    if (
      !expectedChange ||
      !actualChange ||
      actualChange.status !== expectedChange.status ||
      actualChange.effectiveFrom !== expectedChange.effectiveFrom.toMillis()
    ) {
      return false;
    }
  }
  return true;
}

/**
 * Compares the mapped/expected membership document against whatever is
 * actually stored (or `null` if it does not exist). Pure and
 * emulator/network-free: the caller is responsible for fetching `actual`.
 */
export function compareMembership(
  expected: TeamMembershipRecord,
  actual: Record<string, unknown> | null,
): FieldMismatch[] {
  if (actual === null) {
    return [{ field: 'exists', expected: true, actual: false }];
  }
  const mismatches: FieldMismatch[] = [];
  const simpleFields: (keyof TeamMembershipRecord)[] = [
    'teamId',
    'memberId',
    'userId',
    'fullName',
    'email',
    'role',
    'active',
    'managedByCoach',
    'attendanceDefaultStatus',
    'migrationVersion',
  ];
  for (const field of simpleFields) {
    if (actual[field] !== expected[field]) {
      mismatches.push({ field, expected: expected[field], actual: actual[field] });
    }
  }
  const parsedPeriods = parseComparablePeriods(actual.membershipPeriods);
  if (
    parsedPeriods === null ||
    !periodsSemanticallyCompatible(expected.membershipPeriods, parsedPeriods, expected.active)
  ) {
    mismatches.push({
      field: 'membershipPeriods',
      expected: expected.membershipPeriods,
      actual: actual.membershipPeriods,
    });
  }
  const parsedHistory = parseComparableHistory(actual.attendanceDefaultHistory);
  if (
    parsedHistory === null ||
    !historyCompatible(expected.attendanceDefaultHistory, parsedHistory)
  ) {
    mismatches.push({
      field: 'attendanceDefaultHistory',
      expected: expected.attendanceDefaultHistory,
      actual: actual.attendanceDefaultHistory,
    });
  }
  return mismatches;
}

/** Compares the mirrored profile fields (`activeTeamId`/`schemaVersion`). */
export function compareProfile(
  expected: ProfileUpdate,
  actual: { activeTeamId: unknown; schemaVersion: unknown },
): FieldMismatch[] {
  const mismatches: FieldMismatch[] = [];
  if (actual.activeTeamId !== expected.activeTeamId) {
    mismatches.push({ field: 'activeTeamId', expected: expected.activeTeamId, actual: actual.activeTeamId });
  }
  if (actual.schemaVersion !== expected.schemaVersion) {
    mismatches.push({ field: 'schemaVersion', expected: expected.schemaVersion, actual: actual.schemaVersion });
  }
  return mismatches;
}

export interface VerifyPageRequest {
  pageSize?: number;
  cursor?: string | null;
  migrationStartedAtMillis?: number;
}

export interface VerifyMismatch {
  legacyUserId: string;
  teamId: string | null;
  membershipId: string | null;
  fields: FieldMismatch[];
}

export interface VerifyPageCounts {
  processed: number;
  matched: number;
  skippedNoTeam: number;
  conflicts: number;
  mismatches: number;
  errors: number;
}

export interface VerifyPageResponse {
  mode: 'verify';
  pageSize: number;
  startCursor: string | null;
  nextCursor: string | null;
  done: boolean;
  counts: VerifyPageCounts;
  conflicts: MigrationConflict[];
  mismatches: VerifyMismatch[];
  errors: { legacyUserId: string; message: string }[];
  migrationStartedAtMillis: number;
  durationMs: number;
}

/**
 * Verifies one page of legacy users against the current
 * `teamMemberships`/`users` state. Entirely read-only: only `.get()` calls
 * are issued, never `.set()`/`.update()`/`runTransaction()`.
 */
export async function runVerifyPage(db: Firestore, request: VerifyPageRequest): Promise<VerifyPageResponse> {
  const start = Date.now();
  const pageSize = clampPageSize(request.pageSize);
  const cursor = request.cursor ?? null;

  const checkpointSnap = await checkpointRef(db).get();
  const checkpoint = checkpointSnap.exists ? (checkpointSnap.data() as MigrationCheckpointDoc) : null;
  const migrationStartedAt =
    checkpoint?.startedAt instanceof Timestamp
      ? checkpoint.startedAt
      : request.migrationStartedAtMillis !== undefined
        ? Timestamp.fromMillis(request.migrationStartedAtMillis)
        : Timestamp.now();

  const { docs, nextCursor, done } = await fetchUserPage(db, pageSize, cursor);

  const counts: VerifyPageCounts = {
    processed: 0,
    matched: 0,
    skippedNoTeam: 0,
    conflicts: 0,
    mismatches: 0,
    errors: 0,
  };
  const conflicts: MigrationConflict[] = [];
  const mismatches: VerifyMismatch[] = [];
  const errors: { legacyUserId: string; message: string }[] = [];

  for (const doc of docs) {
    counts.processed++;
    try {
      const mapped = mapLegacyUserDocToMembership(doc.id, doc.data(), { migrationStartedAt });
      if (mapped.kind === 'skippedNoTeam') {
        counts.skippedNoTeam++;
        continue;
      }
      if (mapped.kind === 'conflict') {
        counts.conflicts++;
        conflicts.push(mapped.conflict);
        continue;
      }

      const membershipSnap = await db.collection(TEAM_MEMBERSHIPS_COLLECTION).doc(mapped.membershipId).get();
      const fieldMismatches = compareMembership(
        mapped.membership,
        membershipSnap.exists ? (membershipSnap.data() as Record<string, unknown>) : null,
      );

      const userSnap = await db.collection(USERS_COLLECTION).doc(doc.id).get();
      const userData = userSnap.data() ?? {};
      fieldMismatches.push(
        ...compareProfile(mapped.profileUpdate, {
          activeTeamId: userData.activeTeamId ?? null,
          schemaVersion: userData.schemaVersion ?? null,
        }),
      );

      if (fieldMismatches.length === 0) {
        counts.matched++;
      } else {
        counts.mismatches++;
        mismatches.push({
          legacyUserId: doc.id,
          teamId: mapped.membership.teamId,
          membershipId: mapped.membershipId,
          fields: fieldMismatches,
        });
      }
    } catch (err) {
      counts.errors++;
      errors.push({ legacyUserId: doc.id, message: err instanceof Error ? err.message : String(err) });
    }
  }

  return {
    mode: 'verify',
    pageSize,
    startCursor: cursor,
    nextCursor,
    done,
    counts,
    conflicts,
    mismatches,
    errors,
    migrationStartedAtMillis: migrationStartedAt.toMillis(),
    durationMs: Date.now() - start,
  };
}
