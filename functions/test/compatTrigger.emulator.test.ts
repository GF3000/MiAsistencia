/**
 * Emulator-backed integration coverage for the compatibility trigger's
 * actual transaction handler ({@link handleLegacyUserCompatWrite}) — the
 * exact function the deployed `legacyUserCompatSync` trigger invokes. It
 * exercises create/update/delete, the membershipWriteToken no-op,
 * deleted-user non-resurrection, the malformed-record conflict path, and
 * duplicate delivery against real Firestore transactions.
 *
 * Requires the Firestore emulator (see functions/README.md). When
 * FIRESTORE_EMULATOR_HOST is not set the whole suite is skipped, so a plain
 * `npm install && npm test` still passes.
 *
 * Uses its own project id so it never shares emulator data with the other
 * emulator suites (Jest runs test files in parallel workers).
 */
import { initializeApp } from 'firebase-admin/app';
import { Firestore, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { handleLegacyUserCompatWrite } from '../src/compatTrigger';
import { conflictDocId } from '../src/migrationIds';

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const describeIfEmulator = emulatorHost ? describe : describe.skip;

const t = (iso: string) => Timestamp.fromDate(new Date(iso));

function legacyUserDoc(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    email: 'player@example.com',
    fullName: 'Marina García',
    role: 'player',
    teamId: 'team-1',
    teamJoinedAt: t('2026-01-10T00:00:00Z'),
    active: true,
    managedByCoach: false,
    ...overrides,
  };
}

describeIfEmulator('legacyUserCompatSync handler (Firestore emulator)', () => {
  let db: Firestore;

  beforeAll(() => {
    initializeApp({ projectId: 'demo-compat-trigger' });
    db = getFirestore();
  });

  async function deleteCollection(name: string) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
  }

  beforeEach(async () => {
    await Promise.all([
      deleteCollection('users'),
      deleteCollection('teamMemberships'),
      deleteCollection('migrationConflicts'),
    ]);
  });

  afterAll(async () => {
    await Promise.all([
      deleteCollection('users'),
      deleteCollection('teamMemberships'),
      deleteCollection('migrationConflicts'),
    ]);
    await db.terminate();
  }, 30000);

  /** Seeds a user doc and runs the create delivery, mirroring a legacy create. */
  async function seedThroughCreate(userId: string, doc: Record<string, unknown>): Promise<void> {
    await db.collection('users').doc(userId).set(doc);
    const outcome = await handleLegacyUserCompatWrite(db, {
      userId,
      rawBefore: null,
      rawAfter: doc,
      eventTimeMillis: Date.parse('2026-06-01T00:00:00Z'),
    });
    expect(outcome).toBe('synced');
  }

  it('provisions the membership, mirrors the profile, and bumps the token on a legacy create', async () => {
    const doc = legacyUserDoc();
    await db.collection('users').doc('u-create').set(doc);

    const outcome = await handleLegacyUserCompatWrite(db, {
      userId: 'u-create',
      rawBefore: null,
      rawAfter: doc,
      eventTimeMillis: Date.parse('2026-06-01T00:00:00Z'),
    });

    expect(outcome).toBe('synced');
    const membership = await db.collection('teamMemberships').doc('team-1__u-create').get();
    expect(membership.exists).toBe(true);
    expect(membership.data()?.memberId).toBe('u-create');
    expect(membership.data()?.userId).toBe('u-create');
    expect(membership.data()?.membershipPeriods).toEqual([
      { joinedAt: t('2026-01-10T00:00:00Z'), leftAt: null },
    ]);

    const userDoc = await db.collection('users').doc('u-create').get();
    expect(userDoc.data()?.activeTeamId).toBe('team-1');
    expect(userDoc.data()?.schemaVersion).toBe(2);
    expect(typeof userDoc.data()?.membershipWriteToken).toBe('string');
  });

  it('closes the trailing period on an active -> inactive update', async () => {
    await seedThroughCreate('u-update', legacyUserDoc());

    const inactive = legacyUserDoc({ active: false });
    await db.collection('users').doc('u-update').set(inactive, { merge: true });

    const outcome = await handleLegacyUserCompatWrite(db, {
      userId: 'u-update',
      rawBefore: legacyUserDoc({ active: true }),
      rawAfter: inactive,
      eventTimeMillis: Date.parse('2026-07-01T00:00:00Z'),
    });

    expect(outcome).toBe('synced');
    const membership = await db.collection('teamMemberships').doc('team-1__u-update').get();
    expect(membership.data()?.active).toBe(false);
    expect(membership.data()?.membershipPeriods).toEqual([
      { joinedAt: t('2026-01-10T00:00:00Z'), leftAt: t('2026-07-01T00:00:00Z') },
    ]);
  });

  it('closes the membership on delete and never resurrects the deleted user doc', async () => {
    await seedThroughCreate('u-delete', legacyUserDoc({ managedByCoach: true, email: '' }));

    await db.collection('users').doc('u-delete').delete();

    const outcome = await handleLegacyUserCompatWrite(db, {
      userId: 'u-delete',
      rawBefore: legacyUserDoc({ managedByCoach: true, email: '' }),
      rawAfter: null,
      eventTimeMillis: Date.parse('2026-08-01T00:00:00Z'),
    });

    expect(outcome).toBe('synced');
    const membership = await db.collection('teamMemberships').doc('team-1__u-delete').get();
    expect(membership.data()?.active).toBe(false);
    expect(membership.data()?.membershipPeriods).toEqual([
      { joinedAt: t('2026-01-10T00:00:00Z'), leftAt: t('2026-08-01T00:00:00Z') },
    ]);

    // The user document must stay deleted: never resurrected by a mirror write.
    const userDoc = await db.collection('users').doc('u-delete').get();
    expect(userDoc.exists).toBe(false);
  });

  it('no-ops immediately when the write only bumped membershipWriteToken (V2 client already synced)', async () => {
    const outcome = await handleLegacyUserCompatWrite(db, {
      userId: 'u-token',
      rawBefore: legacyUserDoc({ membershipWriteToken: 'token-a' }),
      rawAfter: legacyUserDoc({ membershipWriteToken: 'token-b' }),
      eventTimeMillis: Date.parse('2026-06-01T00:00:00Z'),
    });

    expect(outcome).toBe('tokenNoop');
    // The trigger short-circuited before reading/writing anything.
    const membership = await db.collection('teamMemberships').doc('team-1__u-token').get();
    expect(membership.exists).toBe(false);
  });

  it('records an invalid_legacy_record conflict when the fresh current document is malformed', async () => {
    const malformed = legacyUserDoc({ role: 'not-a-real-role' });
    await db.collection('users').doc('u-bad-current').set(malformed);

    const outcome = await handleLegacyUserCompatWrite(db, {
      userId: 'u-bad-current',
      rawBefore: null,
      rawAfter: malformed,
      eventTimeMillis: Date.parse('2026-06-01T00:00:00Z'),
    });

    expect(outcome).toBe('malformedCurrent');
    const conflict = await db
      .collection('migrationConflicts')
      .doc(conflictDocId({ legacyUserId: 'u-bad-current', teamId: 'team-1', reason: 'invalid_legacy_record' }))
      .get();
    expect(conflict.exists).toBe(true);
    expect(conflict.data()?.reason).toBe('invalid_legacy_record');
    expect(conflict.data()?.resolved).toBe(false);
    expect(conflict.data()?.source).toBe('compatTrigger');
  });

  it('records an invalid_legacy_record conflict when the event before-snapshot is malformed', async () => {
    const outcome = await handleLegacyUserCompatWrite(db, {
      userId: 'u-bad-before',
      rawBefore: legacyUserDoc({ role: 'not-a-real-role' }),
      rawAfter: legacyUserDoc(),
      eventTimeMillis: Date.parse('2026-06-01T00:00:00Z'),
    });

    expect(outcome).toBe('malformedBefore');
    const conflict = await db
      .collection('migrationConflicts')
      .doc(conflictDocId({ legacyUserId: 'u-bad-before', teamId: 'team-1', reason: 'invalid_legacy_record' }))
      .get();
    expect(conflict.exists).toBe(true);
    expect(conflict.data()?.reason).toBe('invalid_legacy_record');
  });

  it('is idempotent under duplicate delivery: the second identical event is a no-op with no churn', async () => {
    const doc = legacyUserDoc();
    await seedThroughCreate('u-dup', doc);
    const first = await db.collection('teamMemberships').doc('team-1__u-dup').get();
    const firstUpdatedAt = first.data()?.updatedAt as Timestamp;

    // Redeliver the exact same create event; fresh-state recompute yields noop.
    const outcome = await handleLegacyUserCompatWrite(db, {
      userId: 'u-dup',
      rawBefore: null,
      rawAfter: doc,
      eventTimeMillis: Date.parse('2026-06-01T00:00:00Z'),
    });

    expect(outcome).toBe('noop');
    const second = await db.collection('teamMemberships').doc('team-1__u-dup').get();
    expect((second.data()?.updatedAt as Timestamp).toMillis()).toBe(firstUpdatedAt.toMillis());
  });
});
