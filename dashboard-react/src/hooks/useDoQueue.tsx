import React, { createContext, useContext, useState, useCallback, useEffect, useMemo } from 'react';
import { apiFetch } from '../utils/apiFetch';
import { changeLogKey, dedupNewEntries } from '../ppcLogDedup';

export interface DoQueueItem {
  id: string;
  search_term: string;
  action: string;
  campaign: string;
  campaign_id: string;
  ad_group_id: string;
  // Tier 1 (bid changes): the actual keyword + its ID + match type
  targeting: string;       // The keyword text (e.g., "truth or dare") — differs from search_term for broad/phrase
  keyword_id: string;      // Amazon keyword ID — required for Update operations
  match_type: string;      // BROAD, PHRASE, EXACT — from data, not guessed
  // Target-level aggregate metrics (from coach view — across ALL search terms for this keyword)
  target_spend_8w: number;
  target_orders_8w: number;
  target_net_roas_8w: number;
  // Coach recommended bid (graduated from ROAS tiers)
  current_bid: number | null;
  recommended_bid: number | null;
  campaign_type: string; // 'SPONSORED_PRODUCTS' | 'SPONSORED_BRANDS' | 'SPONSORED_BRANDS_VIDEO' | ''
  product: string;
  asin?: string; // ASIN for the promoted product — used for Creative ASINs / SKU resolution in bulksheet
  spend: number;
  orders: number;
  cpc: number;
  conv_rate: number;
  seasonal_theme?: string;
  // Budget actions
  current_budget?: number | null;
  recommended_budget?: number | null;
  // Close-the-loop snapshot (FACT_PPC_CHANGE_LOG)
  coach_mode?: string;     // GUARDIAN / COOLDOWN / BLITZ at decision time
  source?: 'COACH' | 'MANUAL';
  // Weekly impact target from the decision card — persisted to FACT_PPC_CHANGE_LOG and
  // graded as target_status by V_PPC_ACTION_OUTCOMES a week after upload.
  expected_impact_weekly?: number;   // $/wk target from the decision card (save or earn)
  expected_impact_kind?: 'save' | 'earn';
  addedAt: number;
  doneAt?: number; // timestamp when marked done
  uploadedAt?: number; // timestamp when marked as uploaded to Amazon
}

interface DoQueueContextValue {
  items: DoQueueItem[];
  doneItems: DoQueueItem[];
  uploadedItems: DoQueueItem[];
  addItem: (item: Omit<DoQueueItem, 'id' | 'addedAt'>) => void;
  removeItem: (id: string) => void;
  clearCampaign: (campaign: string) => void;
  clearAll: () => void;
  hasItem: (search_term: string, action: string, campaign: string, targeting?: string) => boolean;
  markDone: (id: string) => void;
  undoDone: (id: string) => void;
  clearDone: () => void;
  markAllUploaded: () => void;
  undoUploaded: (id: string) => void;
  clearUploaded: () => void;
  isUploaded: (search_term: string, campaign_id: string) => boolean;
  isDone: (search_term: string, campaign_id: string) => boolean;
  cleanupUploaded: (currentActions: { search_term: string; campaign_id: string }[]) => void;
}

const STORAGE_KEY = 'oi_do_queue';
const DONE_STORAGE_KEY = 'oi_do_done';
const UPLOADED_STORAGE_KEY = 'oi_do_uploaded';
const PENDING_LOG_KEY = 'oi_ppc_log_pending';
const SENT_LOG_KEY = 'oi_ppc_log_sent';

const DoQueueContext = createContext<DoQueueContextValue | null>(null);

function loadQueue(): DoQueueItem[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
}

function saveQueue(items: DoQueueItem[]) {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(items)); } catch { /* localStorage unavailable — ignore */ }
}

function loadDone(): DoQueueItem[] {
  try {
    const raw = localStorage.getItem(DONE_STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
}

function saveDone(items: DoQueueItem[]) {
  try { localStorage.setItem(DONE_STORAGE_KEY, JSON.stringify(items)); } catch { /* localStorage unavailable — ignore */ }
}

/* ─── Close the loop: persist applied changes to FACT_PPC_CHANGE_LOG ───
 * POST /api/ppc-change-log on "Uploaded to Amazon". localStorage stays the
 * source for the UI; failed posts wait in PENDING_LOG_KEY and are re-flushed
 * on next app load or next upload. SOP: architecture/PPC_CLOSE_THE_LOOP.md */

interface PpcChangeLogEntry {
  applied_at: string; // preserved across offline retries
  action: string;
  search_term: string;
  targeting: string;
  keyword_id: string;
  match_type: string;
  campaign_id: string;
  campaign_name: string;
  campaign_type: string;
  ad_group_id: string;
  product: string;
  old_bid: number | null;
  new_bid: number | null;
  old_budget: number | null;
  new_budget: number | null;
  target_spend_8w: number;
  target_orders_8w: number;
  target_net_roas_8w: number;
  coach_mode: string;
  source: 'COACH' | 'MANUAL';
  expected_impact_weekly: number | null;
  expected_impact_kind: string | null;
}

function toChangeLogEntries(items: DoQueueItem[]): PpcChangeLogEntry[] {
  const now = new Date().toISOString();
  return items.map(i => ({
    applied_at: now,
    action: i.action,
    search_term: i.search_term || '',
    targeting: i.targeting || '',
    keyword_id: i.keyword_id || '',
    match_type: i.match_type || '',
    campaign_id: i.campaign_id || '',
    campaign_name: i.campaign || '',
    campaign_type: i.campaign_type || '',
    ad_group_id: i.ad_group_id || '',
    product: i.product || '',
    old_bid: i.current_bid ?? null,
    new_bid: i.recommended_bid ?? null,
    old_budget: i.current_budget ?? null,
    new_budget: i.recommended_budget ?? null,
    target_spend_8w: i.target_spend_8w || 0,
    target_orders_8w: i.target_orders_8w || 0,
    target_net_roas_8w: i.target_net_roas_8w || 0,
    coach_mode: i.coach_mode || '',
    source: i.source || 'COACH',
    expected_impact_weekly: i.expected_impact_weekly ?? null,
    expected_impact_kind: i.expected_impact_kind ?? null,
  }));
}

function loadPendingLog(): PpcChangeLogEntry[] {
  try {
    const raw = localStorage.getItem(PENDING_LOG_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
}

function savePendingLog(entries: PpcChangeLogEntry[]) {
  try {
    if (entries.length) localStorage.setItem(PENDING_LOG_KEY, JSON.stringify(entries));
    else localStorage.removeItem(PENDING_LOG_KEY);
  } catch { /* localStorage unavailable — ignore */ }
}

async function postChangeLog(entries: PpcChangeLogEntry[]): Promise<boolean> {
  if (!entries.length) return true;
  try {
    const res = await apiFetch('/api/ppc-change-log', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(entries),
    });
    return res.ok;
  } catch { return false; }
}

function loadSentKeys(): Set<string> {
  try { return new Set(JSON.parse(localStorage.getItem(SENT_LOG_KEY) || '[]')); } catch { return new Set(); }
}

function addSentKeys(keys: string[]) {
  try {
    const cur = [...loadSentKeys(), ...keys];
    localStorage.setItem(SENT_LOG_KEY, JSON.stringify(cur.slice(-500)));
  } catch { /* localStorage unavailable — ignore */ }
}

/** Queue entries (incl. any prior failures), dedup against already-sent keys, then try to flush. */
function logAppliedChanges(items: DoQueueItem[]) {
  const sent = loadSentKeys();
  const fresh = dedupNewEntries([...loadPendingLog(), ...toChangeLogEntries(items)], sent);
  if (!fresh.length) { savePendingLog([]); return; }
  savePendingLog(fresh); // offline fallback first — clear only on success
  postChangeLog(fresh).then(ok => {
    if (ok) { addSentKeys(fresh.map(changeLogKey)); savePendingLog([]); }
    else console.warn('[DoQueue] PPC change log POST failed — kept in oi_ppc_log_pending for retry');
  });
}

function loadUploaded(): DoQueueItem[] {
  try {
    const raw = localStorage.getItem(UPLOADED_STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
}

function saveUploaded(items: DoQueueItem[]) {
  try { localStorage.setItem(UPLOADED_STORAGE_KEY, JSON.stringify(items)); } catch { /* localStorage unavailable — ignore */ }
}

export function DoQueueProvider({ children }: { children: React.ReactNode }) {
  const [items, setItems] = useState<DoQueueItem[]>(loadQueue);
  const [doneItems, setDoneItems] = useState<DoQueueItem[]>(loadDone);
  const [uploadedItems, setUploadedItems] = useState<DoQueueItem[]>(loadUploaded);

  useEffect(() => { saveQueue(items); }, [items]);
  useEffect(() => { saveDone(doneItems); }, [doneItems]);
  useEffect(() => { saveUploaded(uploadedItems); }, [uploadedItems]);

  // Flush change-log entries that failed to reach BigQuery in a previous session.
  // Dedup against already-sent keys first so a stale pending queue can't re-POST a
  // change we already logged (the server MERGE is idempotent regardless, but this
  // avoids the needless round-trip and keeps oi_ppc_log_sent authoritative).
  useEffect(() => {
    const pending = dedupNewEntries(loadPendingLog(), loadSentKeys());
    if (!pending.length) { savePendingLog([]); return; }
    postChangeLog(pending).then(ok => {
      if (ok) { addSentKeys(pending.map(changeLogKey)); savePendingLog([]); }
    });
  }, []);

  const addItem = useCallback((item: Omit<DoQueueItem, 'id' | 'addedAt'>) => {
    setItems(prev => {
      const exists = prev.some(
        p => p.search_term === item.search_term && p.action === item.action && p.campaign === item.campaign && p.targeting === item.targeting
      );
      if (exists) return prev;
      const newItem: DoQueueItem = {
        ...item,
        id: `${item.campaign}|${item.action}|${item.targeting || item.search_term}|${Date.now()}`,
        addedAt: Date.now(),
      };
      return [...prev, newItem];
    });
  }, []);

  const removeItem = useCallback((id: string) => {
    setItems(prev => prev.filter(p => p.id !== id));
  }, []);

  const clearCampaign = useCallback((campaign: string) => {
    setItems(prev => prev.filter(p => p.campaign !== campaign));
  }, []);

  const clearAll = useCallback(() => setItems([]), []);

  const hasItem = useCallback((search_term: string, action: string, campaign: string, targeting?: string) => {
    // targeting disambiguates target-level rows (empty search_term, keyword in targeting):
    // without it, queueing ONE keyword marks every sibling keyword in the same
    // campaign+action as queued. Optional to keep legacy 3-arg call sites working.
    return items.some(p => p.search_term === search_term && p.action === action && p.campaign === campaign
      && (targeting === undefined || p.targeting === targeting));
  }, [items]);

  const markDone = useCallback((id: string) => {
    setItems(prev => {
      const item = prev.find(p => p.id === id);
      if (!item) return prev;
      setDoneItems(done => [...done, { ...item, doneAt: Date.now() }]);
      return prev.filter(p => p.id !== id);
    });
  }, []);

  const undoDone = useCallback((id: string) => {
    setDoneItems(prev => {
      const item = prev.find(p => p.id === id);
      if (!item) return prev;
      // eslint-disable-next-line @typescript-eslint/no-unused-vars -- strip doneAt before re-queueing
      const { doneAt, ...rest } = item;
      setItems(q => [...q, rest]);
      return prev.filter(p => p.id !== id);
    });
  }, []);

  const clearDone = useCallback(() => setDoneItems([]), []);

  /* ─── Uploaded to Amazon ─── */
  const markAllUploaded = useCallback(() => {
    const now = Date.now();
    // Read items snapshot first, then update both states separately
    // (avoids React StrictMode double-invocation bug when nesting setters)
    setItems(prev => {
      if (prev.length === 0) return prev;
      // Schedule uploaded update outside the setItems updater
      setTimeout(() => {
        setUploadedItems(up => {
          const existingKeys = new Set(up.map(u => `${u.search_term}|${u.campaign_id}|${u.action}`));
          const newItems = prev
            .filter(item => !existingKeys.has(`${item.search_term}|${item.campaign_id}|${item.action}`))
            .map(item => ({ ...item, uploadedAt: now }));
          return [...up, ...newItems];
        });
        // Close the loop: persist this batch to FACT_PPC_CHANGE_LOG
        logAppliedChanges(prev);
      }, 0);
      return [];
    });
  }, []);

  const undoUploaded = useCallback((id: string) => {
    setUploadedItems(prev => {
      const item = prev.find(p => p.id === id);
      if (!item) return prev;
      // eslint-disable-next-line @typescript-eslint/no-unused-vars -- strip uploaded/done timestamps before re-queueing
      const { uploadedAt, doneAt, ...rest } = item;
      setItems(q => [...q, rest]);
      return prev.filter(p => p.id !== id);
    });
  }, []);

  const clearUploaded = useCallback(() => setUploadedItems([]), []);

  const isUploaded = useCallback((search_term: string, campaign_id: string) => {
    return uploadedItems.some(
      p => p.search_term === search_term && p.campaign_id === campaign_id
    );
  }, [uploadedItems]);

  const isDone = useCallback((search_term: string, campaign_id: string) => {
    return doneItems.some(
      p => p.search_term === search_term && p.campaign_id === campaign_id
    );
  }, [doneItems]);

  const cleanupUploaded = useCallback((currentActions: { search_term: string; campaign_id: string }[]) => {
    if (!uploadedItems.length || !currentActions.length) return;
    const actionSet = new Set(
      currentActions.map(a => `${(a.search_term || '').toLowerCase()}|${a.campaign_id || ''}`)
    );
    setUploadedItems(prev => {
      const remaining = prev.filter(item => {
        const key = `${(item.search_term || '').toLowerCase()}|${item.campaign_id || ''}`;
        return actionSet.has(key); // keep only items that still appear in actions
      });
      if (remaining.length === prev.length) return prev; // no change
      return remaining;
    });
  }, [uploadedItems]);

  // Memoize context value to prevent unnecessary re-renders
  const value = useMemo(() => ({
    items, doneItems, uploadedItems,
    addItem, removeItem, clearCampaign, clearAll, hasItem,
    markDone, undoDone, clearDone,
    markAllUploaded, undoUploaded, clearUploaded, isUploaded, isDone, cleanupUploaded,
  }), [items, doneItems, uploadedItems, addItem, removeItem, clearCampaign, clearAll, hasItem, markDone, undoDone, clearDone, markAllUploaded, undoUploaded, clearUploaded, isUploaded, isDone, cleanupUploaded]);

  return (
    <DoQueueContext.Provider value={value}>
      {children}
    </DoQueueContext.Provider>
  );
}

export function useDoQueue() {
  const ctx = useContext(DoQueueContext);
  if (!ctx) throw new Error('useDoQueue must be inside DoQueueProvider');
  return ctx;
}
