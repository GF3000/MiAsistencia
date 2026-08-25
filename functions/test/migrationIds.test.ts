import {
  buildMembershipId,
  buildScopedRecordId,
  conflictDocId,
  errorDocId,
  parseMembershipId,
} from '../src/migrationIds';

describe('buildMembershipId', () => {
  it('joins teamId and memberId deterministically', () => {
    expect(buildMembershipId('team-1', 'user-1')).toBe('team-1__user-1');
  });

  it('is a pure function of its inputs (repeat calls agree)', () => {
    const a = buildMembershipId('team-9', 'member-42');
    const b = buildMembershipId('team-9', 'member-42');
    expect(a).toBe(b);
  });

  it('throws on an empty teamId', () => {
    expect(() => buildMembershipId('', 'user-1')).toThrow();
  });

  it('throws on an empty memberId', () => {
    expect(() => buildMembershipId('team-1', '')).toThrow();
  });
});

describe('parseMembershipId', () => {
  it('splits a valid id back into its parts', () => {
    expect(parseMembershipId('team-1__user-1')).toEqual({ teamId: 'team-1', memberId: 'user-1' });
  });

  it('returns null for an id without the separator', () => {
    expect(parseMembershipId('team-1-user-1')).toBeNull();
  });

  it('returns null when the teamId part is empty', () => {
    expect(parseMembershipId('__user-1')).toBeNull();
  });

  it('returns null when the memberId part is empty', () => {
    expect(parseMembershipId('team-1__')).toBeNull();
  });

  it('round-trips through buildMembershipId', () => {
    const id = buildMembershipId('team-abc', 'member-xyz');
    expect(parseMembershipId(id)).toEqual({ teamId: 'team-abc', memberId: 'member-xyz' });
  });
});

describe('buildScopedRecordId', () => {
  it('uses team scope when teamId is present', () => {
    expect(buildScopedRecordId('user-1', 'team-1')).toBe('team-1__user-1');
  });

  it('uses record scope when teamId is null', () => {
    expect(buildScopedRecordId('user-1', null)).toBe('_record__user-1');
  });
});

describe('conflictDocId', () => {
  it('keeps invalid_legacy_record conflicts record-scoped', () => {
    expect(
      conflictDocId({
        legacyUserId: 'user-1',
        teamId: 'team-1',
        reason: 'invalid_legacy_record',
      }),
    ).toBe('_record__user-1');
  });

  it('uses team scope for team-specific conflicts', () => {
    expect(
      conflictDocId({
        legacyUserId: 'user-1',
        teamId: 'team-1',
        reason: 'membership_exists_incompatible',
      }),
    ).toBe('team-1__user-1');
  });
});

describe('errorDocId', () => {
  it('uses team scope when available', () => {
    expect(errorDocId('user-1', 'team-1')).toBe('team-1__user-1');
  });

  it('falls back to record scope when team is unavailable', () => {
    expect(errorDocId('user-1', null)).toBe('_record__user-1');
  });
});
