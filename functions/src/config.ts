/**
 * Central configuration constants for the migration functions. Keeping
 * these in one place avoids magic strings scattered across the codebase and
 * makes the intended region/collection names easy to audit.
 */

/**
 * The Firestore database for this project is provisioned in the `eur3`
 * multi-region. `europe-west1` is the closest single Cloud Functions region
 * to that multi-region, minimizing cross-region latency for Firestore
 * reads/writes performed by these functions.
 */
export const FUNCTIONS_REGION = 'europe-west1';

export const USERS_COLLECTION = 'users';
export const TEAM_MEMBERSHIPS_COLLECTION = 'teamMemberships';
export const MIGRATIONS_COLLECTION = 'migrations';
export const MIGRATION_CONFLICTS_COLLECTION = 'migrationConflicts';
export const MIGRATION_ERRORS_COLLECTION = 'migrationErrors';

/** Checkpoint document path for the multi-team membership migration. */
export const MULTI_TEAM_MIGRATION_DOC_ID = 'multiTeamV2';

/** Schema/migration version stamped on migrated membership documents. */
export const MIGRATION_VERSION = 2 as const;

/**
 * Default page size. Each user is processed in its own Firestore
 * transaction (two reads + writes), so pages are kept small to stay well
 * within the function's 540s timeout even on slow/contended data. The
 * migration is resumable, so smaller pages only mean more (cheap) calls.
 */
export const DEFAULT_PAGE_SIZE = 100;
export const MAX_PAGE_SIZE = 500;

/**
 * How long an `apply` lease is considered valid. A crashed/timed-out apply
 * call leaves its lease behind; once it is older than this, a subsequent
 * call may steal it and resume the run. Must comfortably exceed the
 * function's own `timeoutSeconds` so a still-running call is never treated
 * as dead.
 */
export const MIGRATION_LEASE_TTL_MS = 15 * 60 * 1000;
