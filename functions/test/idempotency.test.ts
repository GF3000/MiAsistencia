import { decideMembershipWrite, decideProfileWrite } from '../src/idempotency';

describe('decideMembershipWrite', () => {
  const expected = { teamId: 'team-1', memberId: 'user-1' };

  it('creates when no document exists yet', () => {
    expect(decideMembershipWrite(null, expected)).toEqual({ action: 'create' });
  });

  it('is idempotent: a document already produced by migration v2 is left untouched', () => {
    const existing = { teamId: 'team-1', memberId: 'user-1', migrationVersion: 2 };
    expect(decideMembershipWrite(existing, expected)).toEqual({ action: 'alreadyMigrated' });
  });

  it('flags a conflict for a document without a migrationVersion (hand-written/foreign data)', () => {
    const existing = { teamId: 'team-1', memberId: 'user-1' };
    const decision = decideMembershipWrite(existing, expected);
    expect(decision.action).toBe('conflict');
  });

  it('flags a conflict when migrationVersion matches but teamId/memberId disagree', () => {
    const existing = { teamId: 'team-2', memberId: 'user-1', migrationVersion: 2 };
    const decision = decideMembershipWrite(existing, expected);
    expect(decision.action).toBe('conflict');
  });

  it('flags a conflict for a different (e.g. future) migrationVersion', () => {
    const existing = { teamId: 'team-1', memberId: 'user-1', migrationVersion: 3 };
    const decision = decideMembershipWrite(existing, expected);
    expect(decision.action).toBe('conflict');
  });

  it('running the decision twice on the same existing doc yields the same result (idempotent)', () => {
    const existing = { teamId: 'team-1', memberId: 'user-1', migrationVersion: 2 };
    const first = decideMembershipWrite(existing, expected);
    const second = decideMembershipWrite(existing, expected);
    expect(first).toEqual(second);
  });
});

describe('decideProfileWrite', () => {
  it('writes when the profile mirror is missing', () => {
    const decision = decideProfileWrite(
      { activeTeamId: null, schemaVersion: null },
      { activeTeamId: 'team-1', schemaVersion: 2 },
    );
    expect(decision).toBe('write');
  });

  it('is a no-op once the profile mirror already matches (idempotent resume)', () => {
    const decision = decideProfileWrite(
      { activeTeamId: 'team-1', schemaVersion: 2 },
      { activeTeamId: 'team-1', schemaVersion: 2 },
    );
    expect(decision).toBe('noop');
  });

  it('writes when only schemaVersion is stale', () => {
    const decision = decideProfileWrite(
      { activeTeamId: 'team-1', schemaVersion: 1 },
      { activeTeamId: 'team-1', schemaVersion: 2 },
    );
    expect(decision).toBe('write');
  });
});
