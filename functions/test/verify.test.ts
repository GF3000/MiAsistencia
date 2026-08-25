import { Timestamp } from 'firebase-admin/firestore';
import { compareMembership, compareProfile } from '../src/verify';
import { TeamMembershipRecord } from '../src/types';

const t = (iso: string) => Timestamp.fromDate(new Date(iso));

function expectedMembership(overrides: Partial<TeamMembershipRecord> = {}): TeamMembershipRecord {
  return {
    teamId: 'team-1',
    memberId: 'user-1',
    userId: 'user-1',
    fullName: 'Marina García',
    email: 'player@example.com',
    role: 'player',
    active: true,
    managedByCoach: false,
    membershipPeriods: [{ joinedAt: t('2026-01-10T00:00:00Z'), leftAt: null }],
    attendanceDefaultStatus: 'attending',
    attendanceDefaultHistory: [],
    createdAt: t('2026-01-01T00:00:00Z'),
    updatedAt: t('2026-01-10T00:00:00Z'),
    migrationVersion: 2,
    ...overrides,
  };
}

describe('compareMembership', () => {
  it('reports a single "exists" mismatch when the document is missing', () => {
    const mismatches = compareMembership(expectedMembership(), null);
    expect(mismatches).toEqual([{ field: 'exists', expected: true, actual: false }]);
  });

  it('reports no mismatches for an identical document', () => {
    const expected = expectedMembership();
    const actual: Record<string, unknown> = {
      teamId: expected.teamId,
      memberId: expected.memberId,
      userId: expected.userId,
      fullName: expected.fullName,
      email: expected.email,
      role: expected.role,
      active: expected.active,
      managedByCoach: expected.managedByCoach,
      membershipPeriods: expected.membershipPeriods.map((p) => ({ joinedAt: p.joinedAt, leftAt: p.leftAt })),
      attendanceDefaultStatus: expected.attendanceDefaultStatus,
      attendanceDefaultHistory: expected.attendanceDefaultHistory,
      migrationVersion: expected.migrationVersion,
    };
    expect(compareMembership(expected, actual)).toEqual([]);
  });

  it('flags a scalar field mismatch', () => {
    const expected = expectedMembership();
    const actual = { ...expected, fullName: 'Wrong Name' };
    const mismatches = compareMembership(expected, actual);
    expect(mismatches).toEqual([{ field: 'fullName', expected: 'Marina García', actual: 'Wrong Name' }]);
  });

  it('flags a membershipPeriods mismatch on length', () => {
    const expected = expectedMembership();
    const actual = { ...expected, membershipPeriods: [] };
    const mismatches = compareMembership(expected, actual);
    expect(mismatches.some((m) => m.field === 'membershipPeriods')).toBe(true);
  });

  it('flags a membershipPeriods mismatch on leftAt', () => {
    const expected = expectedMembership();
    const actual = {
      ...expected,
      membershipPeriods: [{ joinedAt: t('2026-01-10T00:00:00Z'), leftAt: t('2026-02-01T00:00:00Z') }],
    };
    const mismatches = compareMembership(expected, actual);
    expect(mismatches.some((m) => m.field === 'membershipPeriods')).toBe(true);
  });

  it('flags an attendanceDefaultHistory mismatch', () => {
    const expected = expectedMembership({
      attendanceDefaultHistory: [{ status: 'absent', effectiveFrom: t('2026-02-01T00:00:00Z') }],
    });
    const actual = { ...expected, attendanceDefaultHistory: [] };
    const mismatches = compareMembership(expected, actual);
    expect(mismatches.some((m) => m.field === 'attendanceDefaultHistory')).toBe(true);
  });
});

describe('compareProfile', () => {
  it('reports no mismatches when both fields match', () => {
    expect(
      compareProfile({ activeTeamId: 'team-1', schemaVersion: 2 }, { activeTeamId: 'team-1', schemaVersion: 2 }),
    ).toEqual([]);
  });

  it('flags a mismatched activeTeamId', () => {
    const mismatches = compareProfile(
      { activeTeamId: 'team-1', schemaVersion: 2 },
      { activeTeamId: null, schemaVersion: 2 },
    );
    expect(mismatches).toEqual([{ field: 'activeTeamId', expected: 'team-1', actual: null }]);
  });

  it('flags a mismatched schemaVersion', () => {
    const mismatches = compareProfile(
      { activeTeamId: 'team-1', schemaVersion: 2 },
      { activeTeamId: 'team-1', schemaVersion: 1 },
    );
    expect(mismatches).toEqual([{ field: 'schemaVersion', expected: 2, actual: 1 }]);
  });
});
