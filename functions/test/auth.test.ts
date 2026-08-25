import { extractBearerToken, tokensMatch } from '../src/auth';

describe('tokensMatch', () => {
  it('matches identical tokens', () => {
    expect(tokensMatch('super-secret', 'super-secret')).toBe(true);
  });

  it('rejects a wrong token of the same length', () => {
    expect(tokensMatch('super-secreX', 'super-secret')).toBe(false);
  });

  it('rejects a token of a different length without throwing', () => {
    expect(() => tokensMatch('short', 'a-much-longer-secret-value')).not.toThrow();
    expect(tokensMatch('short', 'a-much-longer-secret-value')).toBe(false);
  });

  it('rejects a missing token', () => {
    expect(tokensMatch(null, 'super-secret')).toBe(false);
    expect(tokensMatch(undefined, 'super-secret')).toBe(false);
    expect(tokensMatch('', 'super-secret')).toBe(false);
  });

  it('rejects when the expected secret is empty (never "matches everything")', () => {
    expect(tokensMatch('anything', '')).toBe(false);
    expect(tokensMatch('', '')).toBe(false);
  });
});

describe('extractBearerToken', () => {
  it('extracts the token from a well-formed header', () => {
    expect(extractBearerToken('Bearer abc123')).toBe('abc123');
  });

  it('is case-insensitive on the "Bearer" scheme', () => {
    expect(extractBearerToken('bearer abc123')).toBe('abc123');
  });

  it('returns null for a missing header', () => {
    expect(extractBearerToken(undefined)).toBeNull();
    expect(extractBearerToken(null)).toBeNull();
  });

  it('returns null for a header without the Bearer scheme', () => {
    expect(extractBearerToken('Basic abc123')).toBeNull();
  });
});
