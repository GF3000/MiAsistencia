/**
 * Constant-time token comparison utilities for the migration HTTP endpoint.
 * Kept separate from the endpoint itself so the comparison logic (the part
 * that actually matters for security) can be unit tested directly.
 */
import { timingSafeEqual } from 'node:crypto';

/**
 * Compares a caller-supplied token against the expected secret in
 * constant time with respect to the *content* of `provided`, so a network
 * attacker cannot use response latency to learn the secret byte-by-byte.
 *
 * Length differences are unavoidable to detect in non-constant time (you
 * cannot `timingSafeEqual` buffers of different lengths), so on a length
 * mismatch we still perform a same-length dummy comparison before
 * returning `false`, keeping the *shape* of the code path identical.
 */
export function tokensMatch(provided: string | null | undefined, expected: string): boolean {
  if (!expected) {
    return false;
  }
  if (!provided) {
    return false;
  }
  const providedBuf = Buffer.from(provided, 'utf8');
  const expectedBuf = Buffer.from(expected, 'utf8');
  if (providedBuf.length !== expectedBuf.length) {
    timingSafeEqual(expectedBuf, expectedBuf);
    return false;
  }
  return timingSafeEqual(providedBuf, expectedBuf);
}

/** Extracts a bearer token from an `Authorization: Bearer <token>` header. */
export function extractBearerToken(header: string | undefined | null): string | null {
  if (!header) {
    return null;
  }
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match ? (match[1] ?? null) : null;
}
