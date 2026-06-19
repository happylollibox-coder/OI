// Sync accounting for the PPC change log ("Uploaded to Amazon" → FACT_PPC_CHANGE_LOG).
//
// "Uploaded" (the user applied the bulksheet in Amazon) and "logged to the
// scorecard" (the change reached BigQuery) are independent: a change can be
// marked uploaded while its /api/ppc-change-log POST fails. These two pure
// helpers separate "what to POST" from "how to record the result" so the queue
// hook can keep a reactive count of changes still waiting to be logged.

import { changeLogKey, dedupNewEntries, type ChangeLogKeyable } from './ppcLogDedup';

/**
 * What to POST on a flush: still-pending (previously-failed) entries plus any
 * new uploads, deduped and minus anything already confirmed sent. With no new
 * entries this is a plain retry of the pending set.
 */
export function planFlush<T extends ChangeLogKeyable>(
  pending: T[],
  newEntries: T[],
  sent: Set<string>,
): T[] {
  return dedupNewEntries([...pending, ...newEntries], sent);
}

/**
 * After a successful POST, the pending list to keep: everything still pending
 * minus the keys we just sent. Subtracting (rather than clearing) preserves any
 * change queued while the POST was in flight, so a concurrent upload is never
 * silently dropped.
 */
export function dropSent<T extends ChangeLogKeyable>(
  pending: T[],
  sentKeys: Set<string>,
): T[] {
  return pending.filter(e => !sentKeys.has(changeLogKey(e)));
}
