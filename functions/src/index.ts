/**
 * Cloud Functions entry point. Initializes the Admin SDK once and re-exports
 * the deployable functions for Phase 2 of the multi-team migration.
 */
import { initializeApp, getApps } from 'firebase-admin/app';

if (getApps().length === 0) {
  initializeApp();
}

export { multiTeamMigration } from './httpMigration';
export { legacyUserCompatSync } from './compatTrigger';
