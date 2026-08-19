import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { apiFetch } from './apiFetch';

// Regression guard for the DO page's "Export Bulksheet" doing nothing (Ori 2026-08-12).
// A stale dashboard_token made apiFetch answer a 401 by navigating to the Flask re-auth
// bootstrap — mid-click, which unloaded the page while import('xlsx') was still resolving,
// so no file was ever produced. Enrichment calls now pass noReauthRedirect and must simply
// get the 401 back so the caller's own fallback runs.

const nav = vi.fn();

beforeEach(() => {
  localStorage.clear();
  sessionStorage.clear();
  nav.mockClear();
  localStorage.setItem('dashboard_token', 'stale.token.value');
  // window.location.assign is not implemented in jsdom — replace it with a spy
  Object.defineProperty(window, 'location', {
    configurable: true,
    value: { assign: nav, href: '' },
  });
  vi.stubGlobal('fetch', vi.fn(async () => new Response('{"error":"unauthorized"}', { status: 401 })));
});

afterEach(() => vi.unstubAllGlobals());

describe('apiFetch 401 handling', () => {
  it('does NOT navigate away when the caller opts out (enrichment inside a user gesture)', async () => {
    const res = await apiFetch('/api/live-campaigns', { noReauthRedirect: true });

    expect(res.status).toBe(401);          // caller sees the failure and can fall back
    expect(nav).not.toHaveBeenCalled();     // the page survives → the export can finish
    expect(localStorage.getItem('dashboard_token')).toBe('stale.token.value'); // token untouched
  });

  it('still self-heals (clears token + bounces) for ordinary calls', async () => {
    const res = await apiFetch('/api/plans');

    expect(res.status).toBe(401);
    if (import.meta.env.DEV) {
      // dev path: fail loudly, drop the dead token, no bounce
      expect(localStorage.getItem('dashboard_token')).toBeNull();
    } else {
      expect(nav).toHaveBeenCalledTimes(1);
      expect(localStorage.getItem('dashboard_token')).toBeNull();
    }
  });
});
