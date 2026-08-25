/**
 * Protected HTTPS v2 endpoint that drives the multi-team migration:
 * `mode: "dryRun" | "apply" | "verify"`, paginated via `cursor`/`nextCursor`
 * so an external orchestrator (PowerShell/curl) can page through all users.
 *
 * Protection model: the function is deployed as publicly invokable
 * (`invoker: "public"`) — i.e. reachable from the internet — but every
 * request must present the `MIGRATION_TOKEN` secret via an `Authorization:
 * Bearer <token>` (or `X-Migration-Token`) header, checked with a
 * constant-time comparison. Without the secret the endpoint is useless: it
 * responds `401` and touches no data. See functions/README.md for how to
 * set/rotate the secret and invoke the endpoint safely.
 */
import { getFirestore } from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';
import { defineSecret } from 'firebase-functions/params';
import { onRequest } from 'firebase-functions/v2/https';
import { extractBearerToken, tokensMatch } from './auth';
import { FUNCTIONS_REGION } from './config';
import {
  MigrationBusyError,
  MigrationInvalidApplyCursorError,
  MigrationMode,
  runMigrationPage,
} from './migrationRunner';
import { getMigrationStatus } from './status';
import { runVerifyPage } from './verify';

/** Firebase Secret Manager-backed secret; set once via `firebase functions:secrets:set MIGRATION_TOKEN`. */
export const migrationToken = defineSecret('MIGRATION_TOKEN');

function asOptionalNumber(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

function asOptionalNullableString(value: unknown): string | null | undefined {
  if (value === null) {
    return null;
  }
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

/**
 * `multiTeamMigration` HTTP endpoint.
 *
 * Request body (JSON):
 * ```jsonc
 * {
 *   "mode": "dryRun" | "apply" | "verify" | "status",
 *   "pageSize": 200,          // optional, default 200, max 500
 *   "cursor": "abc123",       // optional; omit to start from the beginning
 *                              // ("apply" resumes automatically instead)
 *   "reset": false,           // "apply" only: discard the stored checkpoint
 *   "migrationStartedAtMillis": 1750000000000 // optional pin for dryRun/verify preview timing
 * }
 * ```
 * `status` ignores all body fields except `mode` and returns a read-only
 * checkpoint + conflict/error-count snapshot with a `cutoverReady` gate.
 * Response body: see {@link MigrationPageResponse} / {@link VerifyPageResponse} /
 * {@link MigrationStatusResponse}.
 */
export const multiTeamMigration = onRequest(
  {
    region: FUNCTIONS_REGION,
    secrets: [migrationToken],
    invoker: 'public',
    cors: false,
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'method_not_allowed', message: 'This endpoint only accepts POST.' });
      return;
    }

    const providedToken =
      extractBearerToken(req.get('authorization')) ?? (req.get('x-migration-token') || null);
    if (!tokensMatch(providedToken, migrationToken.value())) {
      logger.warn('multiTeamMigration: rejected request (missing/invalid token)', {
        hasHeader: providedToken !== null,
      });
      res.status(401).json({ error: 'unauthorized', message: 'Missing or invalid migration token.' });
      return;
    }

    const body = (typeof req.body === 'object' && req.body !== null ? req.body : {}) as Record<string, unknown>;
    const mode = body.mode;
    if (mode !== 'dryRun' && mode !== 'apply' && mode !== 'verify' && mode !== 'status') {
      res.status(400).json({
        error: 'invalid_mode',
        message: 'body.mode must be one of "dryRun", "apply", "verify", "status".',
      });
      return;
    }

    const db = getFirestore();
    const pageSize = asOptionalNumber(body.pageSize);
    const cursor = asOptionalNullableString(body.cursor) ?? null;
    const migrationStartedAtMillis = asOptionalNumber(body.migrationStartedAtMillis);

    try {
      if (mode === 'status') {
        const result = await getMigrationStatus(db);
        res.status(200).json(result);
        return;
      }
      if (mode === 'verify') {
        const result = await runVerifyPage(db, { pageSize, cursor, migrationStartedAtMillis });
        res.status(200).json(result);
        return;
      }
      const migrationMode: MigrationMode = mode;
      const result = await runMigrationPage(db, {
        mode: migrationMode,
        pageSize,
        cursor,
        reset: body.reset === true,
        migrationStartedAtMillis,
      });
      res.status(200).json(result);
    } catch (err) {
      if (err instanceof MigrationInvalidApplyCursorError) {
        res.status(400).json({
          error: 'invalid_cursor',
          message: err.message,
        });
        return;
      }
      if (err instanceof MigrationBusyError) {
        logger.warn('multiTeamMigration: rejected concurrent apply (lease held)', {
          leaseOwner: err.leaseOwner,
          expiresAtMillis: err.expiresAtMillis,
        });
        res.status(409).json({
          error: 'migration_busy',
          message:
            'Another migration apply run is already in progress. Wait for it to finish (or for its lease to expire) and retry.',
          leaseExpiresAtMillis: err.expiresAtMillis,
        });
        return;
      }
      logger.error('multiTeamMigration: unhandled error while processing page', err);
      res.status(500).json({
        error: 'internal_error',
        message: err instanceof Error ? err.message : String(err),
      });
    }
  },
);
