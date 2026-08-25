import { Timestamp } from 'firebase-admin/firestore';
import { mapLegacyUserDocToMembership, mapLegacyUserToMembership, parseLegacyUser } from '../src/mapping';
import { LegacyUserRecord } from '../src/types';

function baseUser(overrides: Partial<LegacyUserRecord> = {}): LegacyUserRecord {
  return {
    id: 'user-1',
    email: 'player@example.com',
    fullName: 'Marina García',
    role: 'player',
    teamId: 'team-1',
    teamJoinedAt: Timestamp.fromDate(new Date('2026-01-10T00:00:00Z')),
    active: true,
    managedByCoach: false,
    attendanceDefaultStatus: 'attending',
    attendanceDefaultHistory: [],
    createdAt: Timestamp.fromDate(new Date('2026-01-01T00:00:00Z')),
    activeTeamId: null,
    schemaVersion: null,
    membershipWriteToken: null,
    ...overrides,
  };
}

const migrationStartedAt = Timestamp.fromDate(new Date('2026-06-01T00:00:00Z'));

describe('parseLegacyUser', () => {
  it('parses a well-formed legacy document', () => {
    const result = parseLegacyUser('user-1', {
      email: 'a@b.com',
      fullName: 'Jane Doe',
      role: 'player',
      teamId: 'team-1',
      active: true,
    });
    expect(result.ok).toBe(true);
  });

  it('rejects a missing/invalid email', () => {
    const result = parseLegacyUser('user-1', { fullName: 'Jane', role: 'player', active: true });
    expect(result).toEqual({ ok: false, error: expect.stringContaining('email') });
  });

  it('rejects an empty fullName', () => {
    const result = parseLegacyUser('user-1', { email: '', fullName: '', role: 'player', active: true });
    expect(result.ok).toBe(false);
  });

  it('rejects an invalid role', () => {
    const result = parseLegacyUser('user-1', {
      email: 'a@b.com',
      fullName: 'Jane',
      role: 'superadmin',
      active: true,
    });
    expect(result).toEqual({ ok: false, error: expect.stringContaining('role') });
  });

  it('rejects a non-boolean active flag', () => {
    const result = parseLegacyUser('user-1', {
      email: 'a@b.com',
      fullName: 'Jane',
      role: 'player',
      active: 'yes',
    });
    expect(result.ok).toBe(false);
  });

  it('rejects a teamJoinedAt that is not a Timestamp', () => {
    const result = parseLegacyUser('user-1', {
      email: 'a@b.com',
      fullName: 'Jane',
      role: 'player',
      active: true,
      teamJoinedAt: '2026-01-01',
    });
    expect(result.ok).toBe(false);
  });

  it('rejects a malformed attendanceDefaultHistory entry', () => {
    const result = parseLegacyUser('user-1', {
      email: 'a@b.com',
      fullName: 'Jane',
      role: 'player',
      active: true,
      attendanceDefaultHistory: [{ status: 'attending' }], // missing effectiveFrom
    });
    expect(result.ok).toBe(false);
  });

  it('defaults optional fields when absent', () => {
    const result = parseLegacyUser('user-1', {
      email: 'a@b.com',
      fullName: 'Jane',
      role: 'player',
      active: true,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.user.managedByCoach).toBe(false);
      expect(result.user.attendanceDefaultStatus).toBe('attending');
      expect(result.user.attendanceDefaultHistory).toEqual([]);
      expect(result.user.teamId).toBeNull();
      expect(result.user.createdAt).toBeNull();
    }
  });
});

describe('mapLegacyUserToMembership', () => {
  it('skips users without a team', () => {
    const result = mapLegacyUserToMembership(baseUser({ teamId: null }), { migrationStartedAt });
    expect(result).toEqual({ kind: 'skippedNoTeam' });
  });

  it('records a conflict and skips when both teamJoinedAt and createdAt are missing', () => {
    const result = mapLegacyUserToMembership(
      baseUser({ teamJoinedAt: null, createdAt: null }),
      { migrationStartedAt },
    );
    expect(result.kind).toBe('conflict');
    if (result.kind === 'conflict') {
      expect(result.conflict.reason).toBe('missing_join_timestamp');
      expect(result.conflict.legacyUserId).toBe('user-1');
    }
  });

  it('falls back to createdAt when teamJoinedAt is missing', () => {
    const createdAt = Timestamp.fromDate(new Date('2026-02-01T00:00:00Z'));
    const result = mapLegacyUserToMembership(
      baseUser({ teamJoinedAt: null, createdAt }),
      { migrationStartedAt },
    );
    expect(result.kind).toBe('mapped');
    if (result.kind === 'mapped') {
      expect(result.membership.membershipPeriods[0]?.joinedAt).toEqual(createdAt);
    }
  });

  it('maps an active account user with an open period and userId = memberId', () => {
    const result = mapLegacyUserToMembership(baseUser(), { migrationStartedAt });
    expect(result.kind).toBe('mapped');
    if (result.kind === 'mapped') {
      expect(result.membershipId).toBe('team-1__user-1');
      expect(result.membership.userId).toBe('user-1');
      expect(result.membership.memberId).toBe('user-1');
      expect(result.membership.membershipPeriods).toEqual([
        { joinedAt: baseUser().teamJoinedAt, leftAt: null },
      ]);
      expect(result.membership.migrationVersion).toBe(2);
      expect(result.profileUpdate).toEqual({ activeTeamId: 'team-1', schemaVersion: 2 });
    }
  });

  it('maps a coach-managed player with userId = null, preserving the legacy memberId', () => {
    const result = mapLegacyUserToMembership(
      baseUser({ id: 'managed-doc-id', managedByCoach: true, email: '' }),
      { migrationStartedAt },
    );
    expect(result.kind).toBe('mapped');
    if (result.kind === 'mapped') {
      expect(result.membership.memberId).toBe('managed-doc-id');
      expect(result.membership.userId).toBeNull();
      expect(result.membershipId).toBe('team-1__managed-doc-id');
    }
  });

  it('closes an inactive member period at the fixed migrationStartedAt instant', () => {
    const result = mapLegacyUserToMembership(baseUser({ active: false }), { migrationStartedAt });
    expect(result.kind).toBe('mapped');
    if (result.kind === 'mapped') {
      expect(result.membership.membershipPeriods).toEqual([
        { joinedAt: baseUser().teamJoinedAt, leftAt: migrationStartedAt },
      ]);
      expect(result.membership.active).toBe(false);
    }
  });

  it('never inverts a period: an inactive member whose join date is after migrationStartedAt closes immediately at joinedAt', () => {
    const lateJoin = Timestamp.fromDate(new Date('2027-01-01T00:00:00Z'));
    const result = mapLegacyUserToMembership(
      baseUser({ active: false, teamJoinedAt: lateJoin }),
      { migrationStartedAt },
    );
    expect(result.kind).toBe('mapped');
    if (result.kind === 'mapped') {
      const period = result.membership.membershipPeriods[0];
      expect(period?.joinedAt).toEqual(lateJoin);
      expect(period?.leftAt).toEqual(lateJoin);
    }
  });

  it('reuses migrationStartedAt for updatedAt so a whole run is reproducible', () => {
    const result = mapLegacyUserToMembership(baseUser(), { migrationStartedAt });
    expect(result.kind).toBe('mapped');
    if (result.kind === 'mapped') {
      expect(result.membership.updatedAt).toEqual(migrationStartedAt);
    }
  });
});

describe('mapLegacyUserDocToMembership', () => {
  it('turns a malformed raw document into an invalid_legacy_record conflict instead of throwing', () => {
    const result = mapLegacyUserDocToMembership('user-1', { role: 'not-a-role' }, { migrationStartedAt });
    expect(result.kind).toBe('conflict');
    if (result.kind === 'conflict') {
      expect(result.conflict.reason).toBe('invalid_legacy_record');
    }
  });

  it('maps a well-formed raw document the same way as the typed API', () => {
    const raw = {
      email: 'a@b.com',
      fullName: 'Jane',
      role: 'player',
      teamId: 'team-9',
      teamJoinedAt: Timestamp.fromDate(new Date('2026-03-01T00:00:00Z')),
      active: true,
    };
    const result = mapLegacyUserDocToMembership('user-9', raw, { migrationStartedAt });
    expect(result.kind).toBe('mapped');
    if (result.kind === 'mapped') {
      expect(result.membershipId).toBe('team-9__user-9');
    }
  });
});
