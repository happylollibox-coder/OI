// Idempotency for the PPC change log: one key per logical change on a day.
// Stable across retries because applied_at is preserved across offline re-flushes.

export interface ChangeLogKeyable {
  campaign_id: string;
  action: string;
  keyword_id?: string;
  targeting?: string;
  search_term?: string;
  new_bid?: number | null;
  new_budget?: number | null;
  applied_at: string; // ISO
}

/**
 * Derive a stable dedup key for a change-log entry.
 * - Object identity: keyword_id preferred over targeting over search_term.
 * - Day-level granularity for applied_at (time component ignored).
 * - new_bid and new_budget distinguish separate bid/budget actions on the same keyword.
 */
export function changeLogKey(e: ChangeLogKeyable): string {
  const obj = e.keyword_id || e.targeting || e.search_term || '';
  const day = (e.applied_at || '').slice(0, 10);
  return [e.campaign_id || '', e.action || '', obj, e.new_bid ?? '', e.new_budget ?? '', day].join('|');
}

/**
 * Dedup a list keeping the FIRST occurrence per key,
 * AND drop any entry whose key is already in `alreadySent`.
 */
export function dedupNewEntries<T extends ChangeLogKeyable>(entries: T[], alreadySent: Set<string>): T[] {
  const seen = new Set<string>();
  const out: T[] = [];
  for (const e of entries) {
    const k = changeLogKey(e);
    if (alreadySent.has(k) || seen.has(k)) continue;
    seen.add(k);
    out.push(e);
  }
  return out;
}
