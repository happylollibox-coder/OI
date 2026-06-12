import React, { createContext, useContext, useState, useCallback } from 'react';
import type { PageId } from '../types';

// ─── View mode: admin sees everything, user sees only curated pages/columns ──
// No permissions/auth tie-in for now — it's a local toggle persisted per browser.
// Pages gate extra columns/diagnostics via `isAdmin` from useViewMode().

export type ViewMode = 'admin' | 'user';

const STORAGE_KEY = 'oi_view_mode';

// Pages considered "fully baked" — the only ones a regular user sees.
// Based on the PPC specialist audit grades + page maturity; edit freely.
export const USER_VISIBLE_PAGES: PageId[] = [
  'home', 'actions', 'do', 'ads', 'kwds', 'strategies', 'learn', 'sqp', 'supply', 'alerts',
];

export function isPageVisible(page: PageId, mode: ViewMode): boolean {
  if (mode === 'admin') return true;
  // 'family' and 'experiment' are drill-ins reached from visible pages
  if (page === 'family' || page === 'experiment') return true;
  return USER_VISIBLE_PAGES.includes(page);
}

interface ViewModeContextValue {
  mode: ViewMode;
  isAdmin: boolean;
  toggle: () => void;
}

const ViewModeContext = createContext<ViewModeContextValue | null>(null);

export function ViewModeProvider({ children }: { children: React.ReactNode }) {
  const [mode, setMode] = useState<ViewMode>(() => {
    try { return (localStorage.getItem(STORAGE_KEY) as ViewMode) || 'admin'; }
    catch { return 'admin'; }
  });

  const toggle = useCallback(() => {
    setMode(m => {
      const next: ViewMode = m === 'admin' ? 'user' : 'admin';
      try { localStorage.setItem(STORAGE_KEY, next); } catch { /* noop */ }
      return next;
    });
  }, []);

  return (
    <ViewModeContext.Provider value={{ mode, isAdmin: mode === 'admin', toggle }}>
      {children}
    </ViewModeContext.Provider>
  );
}

export function useViewMode() {
  const ctx = useContext(ViewModeContext);
  if (!ctx) throw new Error('useViewMode must be used within a ViewModeProvider');
  return ctx;
}
