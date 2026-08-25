import { Timestamp } from 'firebase-admin/firestore';
import { CompatSyncInput, decideCompatSync } from '../src/compatDecision';
import { LegacyUserRecord, TeamMembershipRecord } from '../src/types';

const t = (iso: string) => Timestamp.fromDate(new Date(iso));

function legacyUser(overrides: Partial<LegacyUserRecord> = {}): LegacyUserRecord {
  return {
    id: 'user-1',
    email: 'player@example.com',
    fullName: 'Marina García',
    role: 'player',
    teamId: 'team-1',
    teamJoinedAt: t('2026-01-10T00:00:00Z'),
    active: true,
    managedByCoach: false,
    attendanceDefaultStatus: 'attending',
    attendanceDefaultHistory: [],
    createdAt: t('2026-01-01T00:00:00Z'),
    activeTeamId: null,
    schemaVersion: null,
    membershipWriteToken: null,
    ...overrides,
  };
}

function membership(overrides: Partial<TeamMembershipRecord> = {}): TeamMembershipRecord {
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

const eventTime = t('2026-06-01T00:00:00Z');

function decide(overrides: Partial<CompatSyncInput>) {
  return decideCompatSync({
    userId: 'user-1',
    before: legacyUser(),
    after: legacyUser(),
    eventTime,
    writeChangedToken: false,
    existingOldMembership: null,
    existingNewMembership: null,
    ...overrides,
  });
}

describe('decideCompatSync: guard rails', () => {
  it('no-ops when the triggering write changed membershipWriteToken (a V2 client already synced it)', () => {
    const plan = decide({
      before: legacyUser({ fullName: 'Old Name' }),
      after: legacyUser({ fullName: 'New Name' }),
      writeChangedToken: true,
    });
    expect(plan.kind).toBe('noop');
  });

  it('no-ops when nothing membership-relevant changed (redelivery of the same event)', () => {
    const plan = decide({ existingNewMembership: membership() });
    expect(plan.kind).toBe('noop');
  });

  it('no-ops when the computed target state already matches stored state (at-least-once duplicate delivery)', () => {
    const plan = decide({
      before: legacyUser({ fullName: 'Old Name' }),
      after: legacyUser({ fullName: 'Marina García', activeTeamId: 'team-1', schemaVersion: 2 }),
      existingNewMembership: membership({ fullName: 'Marina García' }),
    });
    expect(plan.kind).toBe('noop');
  });
});

describe('decideCompatSync: create paths', () => {
  it('creates a membership on a legacy document create (before is null) that already has a teamId', () => {
    const plan = decide({
      before: null,
      after: legacyUser({ teamId: 'team-1', teamJoinedAt: t('2026-06-01T00:00:00Z'), activeTeamId: null, schemaVersion: null }),
      existingNewMembership: null,
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membershipId).toBe('team-1__user-1');
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual([
        { joinedAt: t('2026-06-01T00:00:00Z'), leftAt: null },
      ]);
      expect(plan.profileUpdate).toEqual({ activeTeamId: 'team-1', schemaVersion: 2 });
      expect(plan.closeOldMembership).toBeNull();
    }
  });

  it('creates an inactive member with a period closed at the fixed event time (derived from active state)', () => {
    const plan = decide({
      before: null,
      after: legacyUser({ teamId: 'team-1', teamJoinedAt: t('2026-01-10T00:00:00Z'), active: false }),
      existingNewMembership: null,
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membership.active).toBe(false);
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual([
        { joinedAt: t('2026-01-10T00:00:00Z'), leftAt: eventTime },
      ]);
    }
  });

  it('creates a brand-new membership with a single open period on a first-time join via an old client', () => {
    const plan = decide({
      before: legacyUser({ teamId: null, teamJoinedAt: null, activeTeamId: null, schemaVersion: null }),
      after: legacyUser({ teamId: 'team-1', teamJoinedAt: t('2026-06-01T00:00:00Z') }),
      existingNewMembership: null,
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual([
        { joinedAt: t('2026-06-01T00:00:00Z'), leftAt: null },
      ]);
      expect(plan.closeOldMembership).toBeNull();
    }
  });

  it('records a missing_join_timestamp conflict instead of inventing a join date', () => {
    const plan = decide({
      before: null,
      after: legacyUser({ teamId: 'team-1', teamJoinedAt: null, createdAt: null }),
      existingNewMembership: null,
    });
    expect(plan.kind).toBe('conflict');
    if (plan.kind === 'conflict') {
      expect(plan.conflict.reason).toBe('missing_join_timestamp');
      expect(plan.conflict.teamId).toBe('team-1');
    }
  });
});

describe('decideCompatSync: leaving a team', () => {
  it('closes the old membership open period, marks it inactive, and clears activeTeamId', () => {
    const plan = decide({
      before: legacyUser({ teamId: 'team-1' }),
      after: legacyUser({ teamId: null, teamJoinedAt: null, activeTeamId: 'team-1', schemaVersion: 2 }),
      existingOldMembership: membership(),
      existingNewMembership: null,
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.closeOldMembership?.membership.membershipPeriods).toEqual([
        { joinedAt: t('2026-01-10T00:00:00Z'), leftAt: eventTime },
      ]);
      expect(plan.closeOldMembership?.membership.active).toBe(false);
      expect(plan.upsertNewMembership).toBeNull();
      expect(plan.profileUpdate).toEqual({ activeTeamId: null, schemaVersion: 2 });
    }
  });

  it('never rewrites an already-closed old membership (no churn, history preserved)', () => {
    const closedMembership = membership({
      membershipPeriods: [{ joinedAt: t('2026-01-10T00:00:00Z'), leftAt: t('2026-05-01T00:00:00Z') }],
      active: false,
    });
    const plan = decide({
      before: legacyUser({ teamId: 'team-1', fullName: 'Old' }),
      // activeTeamId still stale so the plan is still a sync (profile mirror),
      // proving the *membership* is left untouched even though a sync occurs.
      after: legacyUser({ teamId: null, teamJoinedAt: null, fullName: 'Old', activeTeamId: 'team-1', schemaVersion: 2 }),
      existingOldMembership: closedMembership,
      existingNewMembership: null,
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.closeOldMembership).toBeNull();
      expect(plan.profileUpdate).toEqual({ activeTeamId: null, schemaVersion: 2 });
    }
  });
});

describe('decideCompatSync: switching teams', () => {
  it('closes the old membership and opens/creates the new one in the same plan', () => {
    const plan = decide({
      before: legacyUser({ teamId: 'team-1' }),
      after: legacyUser({ teamId: 'team-2', teamJoinedAt: t('2026-06-01T00:00:00Z') }),
      existingOldMembership: membership({ teamId: 'team-1' }),
      existingNewMembership: null,
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.closeOldMembership?.membershipId).toBe('team-1__user-1');
      expect(plan.closeOldMembership?.membership.membershipPeriods[0]?.leftAt).toEqual(eventTime);
      expect(plan.closeOldMembership?.membership.active).toBe(false);
      expect(plan.upsertNewMembership?.membershipId).toBe('team-2__user-1');
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual([
        { joinedAt: t('2026-06-01T00:00:00Z'), leftAt: null },
      ]);
    }
  });

  it('rejoining a team the member previously left appends a new period instead of overwriting history', () => {
    const priorPeriods = [{ joinedAt: t('2025-01-01T00:00:00Z'), leftAt: t('2025-06-01T00:00:00Z') }];
    const plan = decide({
      before: legacyUser({ teamId: 'team-9' }),
      after: legacyUser({ teamId: 'team-1', teamJoinedAt: t('2026-06-01T00:00:00Z') }),
      existingOldMembership: membership({ teamId: 'team-9', membershipPeriods: priorPeriods }),
      existingNewMembership: membership({ teamId: 'team-1', membershipPeriods: priorPeriods }),
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual([
        ...priorPeriods,
        { joinedAt: t('2026-06-01T00:00:00Z'), leftAt: null },
      ]);
    }
  });

  it('switching to an existing inactive membership while inactive does NOT open a spurious period', () => {
    const priorPeriods = [{ joinedAt: t('2025-01-01T00:00:00Z'), leftAt: t('2025-06-01T00:00:00Z') }];
    const plan = decide({
      before: legacyUser({ teamId: 'team-9' }),
      after: legacyUser({
        teamId: 'team-1',
        teamJoinedAt: t('2026-06-01T00:00:00Z'),
        active: false,
        fullName: 'New Name',
      }),
      existingOldMembership: membership({ teamId: 'team-9', membershipPeriods: priorPeriods }),
      existingNewMembership: membership({
        teamId: 'team-1',
        active: false,
        fullName: 'Old Name',
        membershipPeriods: priorPeriods,
      }),
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      // The membership stays closed & inactive: no open period is created for
      // an inactive team switch (the fullName change forces the upsert so we
      // can observe the reconciled periods).
      expect(plan.upsertNewMembership?.membership.fullName).toBe('New Name');
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual(priorPeriods);
      expect(plan.upsertNewMembership?.membership.active).toBe(false);
    }
  });

  it('switching to an existing inactive membership while active opens a fresh period', () => {
    const priorPeriods = [{ joinedAt: t('2025-01-01T00:00:00Z'), leftAt: t('2025-06-01T00:00:00Z') }];
    const plan = decide({
      before: legacyUser({ teamId: 'team-9' }),
      after: legacyUser({ teamId: 'team-1', teamJoinedAt: t('2026-06-01T00:00:00Z'), active: true }),
      existingOldMembership: membership({ teamId: 'team-9', membershipPeriods: priorPeriods }),
      existingNewMembership: membership({
        teamId: 'team-1',
        active: false,
        membershipPeriods: priorPeriods,
      }),
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual([
        ...priorPeriods,
        { joinedAt: t('2026-06-01T00:00:00Z'), leftAt: null },
      ]);
      expect(plan.upsertNewMembership?.membership.active).toBe(true);
    }
  });
});

describe('decideCompatSync: in-place field and active changes on the same team', () => {
  it('mirrors a role change without touching membershipPeriods', () => {
    const existing = membership();
    const plan = decide({
      before: legacyUser({ role: 'player' }),
      after: legacyUser({ role: 'admin' }),
      existingNewMembership: existing,
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membership.role).toBe('admin');
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual(existing.membershipPeriods);
    }
  });

  it('closes the open period and sets active=false when a member becomes inactive', () => {
    const plan = decide({
      before: legacyUser({ active: true }),
      after: legacyUser({ active: false }),
      existingNewMembership: membership(),
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual([
        { joinedAt: t('2026-01-10T00:00:00Z'), leftAt: eventTime },
      ]);
      expect(plan.upsertNewMembership?.membership.active).toBe(false);
    }
  });

  it('opens a new period at the event time when a member is reactivated', () => {
    const closed = membership({
      membershipPeriods: [{ joinedAt: t('2026-01-10T00:00:00Z'), leftAt: t('2026-05-01T00:00:00Z') }],
      active: false,
    });
    const plan = decide({
      before: legacyUser({ active: false }),
      after: legacyUser({ active: true }),
      existingNewMembership: closed,
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual([
        ...closed.membershipPeriods,
        { joinedAt: eventTime, leftAt: null },
      ]);
    }
  });

  it('repairs a drifted doc: active member with no open period gets one opened at the event time', () => {
    // A field-only change (no active flip in the event) but the stored
    // membership is out of sync: active=true yet the trailing period is
    // closed. Reconciliation must open a fresh period so state matches.
    const drifted = membership({
      active: true,
      membershipPeriods: [{ joinedAt: t('2026-01-10T00:00:00Z'), leftAt: t('2026-05-01T00:00:00Z') }],
    });
    const plan = decide({
      before: legacyUser({ active: true, fullName: 'Old Name' }),
      after: legacyUser({ active: true, fullName: 'New Name' }),
      existingNewMembership: drifted,
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual([
        ...drifted.membershipPeriods,
        { joinedAt: eventTime, leftAt: null },
      ]);
    }
  });

  it('repairs a drifted doc: inactive member with a stray open period gets it closed at the event time', () => {
    const drifted = membership({
      active: false,
      membershipPeriods: [{ joinedAt: t('2026-01-10T00:00:00Z'), leftAt: null }],
    });
    const plan = decide({
      before: legacyUser({ active: false, fullName: 'Old Name' }),
      after: legacyUser({ active: false, fullName: 'New Name' }),
      existingNewMembership: drifted,
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual([
        { joinedAt: t('2026-01-10T00:00:00Z'), leftAt: eventTime },
      ]);
      expect(plan.upsertNewMembership?.membership.active).toBe(false);
    }
  });

  it('never overwrites a richer (longer) V2 attendance history with a shorter legacy one', () => {
    const richHistory = [
      { status: 'absent' as const, effectiveFrom: t('2026-02-01T00:00:00Z') },
      { status: 'attending' as const, effectiveFrom: t('2026-03-01T00:00:00Z') },
    ];
    const plan = decide({
      before: legacyUser({ fullName: 'Old Name' }),
      after: legacyUser({
        fullName: 'New Name',
        attendanceDefaultStatus: 'absent',
        attendanceDefaultHistory: [{ status: 'absent', effectiveFrom: t('2026-02-01T00:00:00Z') }],
      }),
      existingNewMembership: membership({ attendanceDefaultStatus: 'attending', attendanceDefaultHistory: richHistory }),
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membership.attendanceDefaultHistory).toEqual(richHistory);
      expect(plan.upsertNewMembership?.membership.attendanceDefaultStatus).toBe('attending');
      expect(plan.upsertNewMembership?.membership.fullName).toBe('New Name');
    }
  });

  it('adopts the legacy attendance history when it is at least as long as the stored one', () => {
    const richerLegacyHistory = [
      { status: 'absent' as const, effectiveFrom: t('2026-02-01T00:00:00Z') },
      { status: 'attending' as const, effectiveFrom: t('2026-04-01T00:00:00Z') },
    ];
    const plan = decide({
      before: legacyUser(),
      after: legacyUser({ attendanceDefaultStatus: 'attending', attendanceDefaultHistory: richerLegacyHistory }),
      existingNewMembership: membership({
        attendanceDefaultStatus: 'attending',
        attendanceDefaultHistory: [{ status: 'absent', effectiveFrom: t('2026-02-01T00:00:00Z') }],
      }),
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membership.attendanceDefaultHistory).toEqual(richerLegacyHistory);
    }
  });

  it('creates the membership on the fly if it never existed even though teamId did not change', () => {
    const plan = decide({
      before: legacyUser({ fullName: 'Old Name' }),
      after: legacyUser({ fullName: 'New Name' }),
      existingNewMembership: null,
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.upsertNewMembership?.membership.fullName).toBe('New Name');
      expect(plan.upsertNewMembership?.membership.membershipPeriods).toEqual([
        { joinedAt: t('2026-01-10T00:00:00Z'), leftAt: null },
      ]);
    }
  });
});

describe('decideCompatSync: delete paths', () => {
  it('closes a managed-player membership open period and marks it inactive, preserving history', () => {
    const existing = membership({
      managedByCoach: true,
      userId: null,
      membershipPeriods: [
        { joinedAt: t('2025-01-01T00:00:00Z'), leftAt: t('2025-03-01T00:00:00Z') },
        { joinedAt: t('2026-02-01T00:00:00Z'), leftAt: null },
      ],
    });
    const plan = decide({
      before: legacyUser({ teamId: 'team-1', managedByCoach: true }),
      after: null,
      existingOldMembership: existing,
    });
    expect(plan.kind).toBe('sync');
    if (plan.kind === 'sync') {
      expect(plan.closeOldMembership?.membershipId).toBe('team-1__user-1');
      expect(plan.closeOldMembership?.membership.active).toBe(false);
      expect(plan.closeOldMembership?.membership.membershipPeriods).toEqual([
        { joinedAt: t('2025-01-01T00:00:00Z'), leftAt: t('2025-03-01T00:00:00Z') },
        { joinedAt: t('2026-02-01T00:00:00Z'), leftAt: eventTime },
      ]);
      expect(plan.upsertNewMembership).toBeNull();
      // The user document is gone; never resurrect it with a profile mirror.
      expect(plan.profileUpdate).toBeNull();
    }
  });

  it('no-ops on delete when the user had no team', () => {
    const plan = decide({ before: legacyUser({ teamId: null }), after: null, existingOldMembership: null });
    expect(plan.kind).toBe('noop');
  });

  it('no-ops on delete when the membership is already closed and inactive', () => {
    const plan = decide({
      before: legacyUser({ teamId: 'team-1' }),
      after: null,
      existingOldMembership: membership({
        membershipPeriods: [{ joinedAt: t('2026-01-10T00:00:00Z'), leftAt: t('2026-05-01T00:00:00Z') }],
        active: false,
      }),
    });
    expect(plan.kind).toBe('noop');
  });

  it('no-ops on delete when no membership document exists', () => {
    const plan = decide({ before: legacyUser({ teamId: 'team-1' }), after: null, existingOldMembership: null });
    expect(plan.kind).toBe('noop');
  });
});

describe('decideCompatSync: foreign membership conflicts', () => {
  it('refuses to overwrite a foreign (non-V2) membership on an update and records a conflict', () => {
    const foreign: Record<string, unknown> = { teamId: 'team-1', memberId: 'user-1', handWrittenByAdmin: true };
    const plan = decide({
      before: legacyUser({ fullName: 'Old Name' }),
      after: legacyUser({ fullName: 'New Name' }),
      existingNewMembership: foreign,
    });
    expect(plan.kind).toBe('conflict');
    if (plan.kind === 'conflict') {
      expect(plan.conflict.reason).toBe('membership_exists_incompatible');
      expect(plan.conflict.teamId).toBe('team-1');
    }
  });

  it('refuses to close a foreign membership on delete', () => {
    const foreign: Record<string, unknown> = { teamId: 'team-1', memberId: 'user-1', handWrittenByAdmin: true };
    const plan = decide({ before: legacyUser({ teamId: 'team-1' }), after: null, existingOldMembership: foreign });
    expect(plan.kind).toBe('conflict');
  });

  it('refuses to create over a foreign membership when switching teams (no partial writes)', () => {
    const foreign: Record<string, unknown> = { teamId: 'team-2', memberId: 'user-1', handWrittenByAdmin: true };
    const plan = decide({
      before: legacyUser({ teamId: 'team-1' }),
      after: legacyUser({ teamId: 'team-2', teamJoinedAt: t('2026-06-01T00:00:00Z') }),
      existingOldMembership: membership({ teamId: 'team-1' }),
      existingNewMembership: foreign,
    });
    expect(plan.kind).toBe('conflict');
    if (plan.kind === 'conflict') {
      expect(plan.conflict.teamId).toBe('team-2');
    }
  });
});

describe('decideCompatSync: stale / out-of-order events', () => {
  it('computes from the fresh current state so a stale event cannot regress a closed period', () => {
    // The event's `before` claims the member was active, but the *fresh*
    // current state (passed as `after`) already shows them inactive with the
    // membership closed. The stale event must not reopen the closed period.
    const plan = decide({
      before: legacyUser({ active: true }),
      after: legacyUser({ active: false, activeTeamId: 'team-1', schemaVersion: 2 }),
      existingNewMembership: membership({
        membershipPeriods: [{ joinedAt: t('2026-01-10T00:00:00Z'), leftAt: t('2026-05-01T00:00:00Z') }],
        active: false,
      }),
    });
    expect(plan.kind).toBe('noop');
  });

  it('reconciles to the fresh team even when a stale join event is redelivered', () => {
    // A stale "joined team-1" event is redelivered, but the fresh current
    // state shows the user has since left every team. Computing from fresh
    // state yields a no-op instead of resurrecting the membership.
    const plan = decide({
      before: legacyUser({ teamId: null, teamJoinedAt: null }),
      after: legacyUser({ teamId: null, teamJoinedAt: null, activeTeamId: null, schemaVersion: 2 }),
      existingNewMembership: null,
    });
    expect(plan.kind).toBe('noop');
  });
});
