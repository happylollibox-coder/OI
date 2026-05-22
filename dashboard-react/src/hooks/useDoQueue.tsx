import React, { createContext, useContext, useState, useCallback, useEffect, useMemo } from 'react';

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
  spend: number;
  orders: number;
  cpc: number;
  conv_rate: number;
  seasonal_theme?: string;
  // Budget actions
  current_budget?: number | null;
  recommended_budget?: number | null;
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
  hasItem: (search_term: string, action: string, campaign: string) => boolean;
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

const DoQueueContext = createContext<DoQueueContextValue | null>(null);

function loadQueue(): DoQueueItem[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
}

function saveQueue(items: DoQueueItem[]) {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(items)); } catch {}
}

function loadDone(): DoQueueItem[] {
  try {
    const raw = localStorage.getItem(DONE_STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
}

function saveDone(items: DoQueueItem[]) {
  try { localStorage.setItem(DONE_STORAGE_KEY, JSON.stringify(items)); } catch {}
}

function loadUploaded(): DoQueueItem[] {
  try {
    const raw = localStorage.getItem(UPLOADED_STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
}

function saveUploaded(items: DoQueueItem[]) {
  try { localStorage.setItem(UPLOADED_STORAGE_KEY, JSON.stringify(items)); } catch {}
}

export function DoQueueProvider({ children }: { children: React.ReactNode }) {
  const [items, setItems] = useState<DoQueueItem[]>(loadQueue);
  const [doneItems, setDoneItems] = useState<DoQueueItem[]>(loadDone);
  const [uploadedItems, setUploadedItems] = useState<DoQueueItem[]>(loadUploaded);

  useEffect(() => { saveQueue(items); }, [items]);
  useEffect(() => { saveDone(doneItems); }, [doneItems]);
  useEffect(() => { saveUploaded(uploadedItems); }, [uploadedItems]);

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

  const hasItem = useCallback((search_term: string, action: string, campaign: string) => {
    return items.some(p => p.search_term === search_term && p.action === action && p.campaign === campaign);
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
      }, 0);
      return [];
    });
  }, []);

  const undoUploaded = useCallback((id: string) => {
    setUploadedItems(prev => {
      const item = prev.find(p => p.id === id);
      if (!item) return prev;
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
