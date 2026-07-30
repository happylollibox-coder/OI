import { useState, useEffect, useCallback, useMemo } from 'react';
import { Check, X, Search, AlertTriangle, RefreshCw, Ban, Loader2 } from 'lucide-react';
import { Card } from './Card';
import { Badge } from './Badge';
import { apiFetch } from '../utils/apiFetch';
import { fmt, fM } from '../utils';

// Supervised keyword -> intent mapping.
// 2026-07-24: migrated from one-winning-theme to COMPOSED intents. A term's intent is built
// from its facets (budget · age · gender · holiday · occasion · product_type · gift) rather
// than chosen from a list, so facts that are all true at once no longer compete.
// The machine suggests, a human confirms or overrides, and the verdict is stored in
// DE_SEARCH_TERM_INTENT. Ordering is server-side by 365d clicks DESC so the biggest
// volume is always settled first — 201k terms exist and reviewing all of them is not
// the goal, covering the money is.
// SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md

type StatusFilter = 'ALL' | 'PENDING' | 'RECHECK' | 'VERIFIED' | 'CORRECTED' | 'REJECTED';

interface IntentTerm {
  search_term: string;
  resolved_intent_key: string | null;
  machine_suggestion: string | null;
  verified_intent_key: string | null;
  verification_status: string;
  is_human_verified: boolean;
  is_stale: boolean;
  verified_by: string | null;
  verified_at: string | null;
  facet_count: number | null;
  suggested_facets: string | null;
  term_kind: string | null;
  budget_tier: string | null;
  clicks_365d: number | null;
  orders_365d: number | null;
  cost_365d: number | null;
  cvr_pct: number | null;
}

// The vocabulary is the set of compositions that actually occur, ordered by volume —
// not a hand-kept theme list. 2,765 exist; the picker carries the 318 with >=100 clicks,
// which is 97.2% of traffic.
interface Theme { intent_key: string; label: string; intent_type: string; clicks: number }

interface MonthRow {
  month_of_year: number; cvr_hat: number | null; target_bid: number | null;
  max_bid: number | null; actual_cpc: number | null; net_roas_at_market: number | null;
  action: string; confidence: string;
}
interface ProductBlock {
  product: string; family: string; base_clicks: number | null; confidence: string;
  suggestion: string; months: MonthRow[];
}
const MONTHS = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
// Bands (2026-07-25): explicit per band, unknown = muted — never default to green.
function actionColor(a: string): string {
  if (a === 'RUN') return 'text-emerald-400';
  if (a === 'VELOCITY' || a === 'RUN_THIN') return 'text-amber-400';
  if (a === 'MARGINAL') return 'text-subtle';
  if (a === 'OFF') return 'text-subtle';
  if (a === 'PROBE') return 'text-purple-400';
  return 'text-subtle';
}

function statusVariant(s: string): string {
  if (s === 'RECHECK') return 'amber';
  if (s === 'VERIFIED') return 'green';
  if (s === 'CORRECTED') return 'blue';
  if (s === 'REJECTED') return 'red';
  return 'muted';
}

const FILTERS: StatusFilter[] = ['ALL', 'PENDING', 'RECHECK', 'VERIFIED', 'CORRECTED', 'REJECTED'];

export function IntentMapping() {
  const [rows, setRows] = useState<IntentTerm[]>([]);
  const [themes, setThemes] = useState<Theme[]>([]);
  const [counts, setCounts] = useState<Record<string, { terms: number; clicks: number }>>({});
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [status, setStatus] = useState<StatusFilter>('ALL');
  const [intentFilter, setIntentFilter] = useState('');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [busyTerm, setBusyTerm] = useState<string | null>(null);
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; msg: string } | null>(null);

  // Monthly popup: click a composed intent -> 12-month curve per product.
  const [popupIntent, setPopupIntent] = useState<string | null>(null);
  const [popupData, setPopupData] = useState<ProductBlock[] | null>(null);
  const [popupLoading, setPopupLoading] = useState(false);
  const [popupProductIdx, setPopupProductIdx] = useState(0);

  const openIntent = useCallback(async (intentKey: string) => {
    setPopupIntent(intentKey); setPopupData(null); setPopupLoading(true); setPopupProductIdx(0);
    try {
      const res = await apiFetch(`/api/admin/intent-monthly?intent_key=${encodeURIComponent(intentKey)}`);
      const d = await res.json();
      setPopupData(d.success ? (d.products || []) : []);
    } catch { setPopupData([]); }
    finally { setPopupLoading(false); }
  }, []);

  const showFeedback = (type: 'success' | 'error', msg: string) => {
    setFeedback({ type, msg });
    setTimeout(() => setFeedback(null), 4000);
  };

  const fetchAll = useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams({ limit: '200' });
      if (status !== 'ALL') params.set('status', status);
      if (query) params.set('q', query);
      if (intentFilter) params.set('intent', intentFilter);
      const res = await apiFetch(`/api/admin/intent-mapping?${params}`);
      const data = await res.json();
      if (data.success) {
        setRows(data.terms || []);
        setThemes(data.themes || []);
        setCounts(data.counts || {});
        setLoadError(false);
      } else {
        setLoadError(true);
      }
    } catch {
      setLoadError(true);
    } finally {
      setLoading(false);
    }
  }, [status, query, intentFilter]);

  useEffect(() => { fetchAll(); }, [fetchAll]);

  // Debounce the search box so typing doesn't fire a query per keystroke.
  useEffect(() => {
    const t = setTimeout(() => setQuery(search.trim()), 350);
    return () => clearTimeout(t);
  }, [search]);

  const submit = async (term: IntentTerm, verdict: 'VERIFIED' | 'CORRECTED' | 'REJECTED') => {
    const chosen = edits[term.search_term] ?? term.resolved_intent_key ?? term.machine_suggestion;
    if (verdict !== 'REJECTED' && !chosen) {
      showFeedback('error', 'Pick an intent first'); return;
    }
    setBusyTerm(term.search_term);
    try {
      const res = await apiFetch('/api/admin/intent-mapping/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ search_term: term.search_term, intent_key: chosen, status: verdict }),
      });
      const data = await res.json();
      if (data.success) {
        setRows(prev => prev.map(r => r.search_term === term.search_term
          ? { ...r, verification_status: verdict, is_human_verified: true, is_stale: false,
              verified_by: data.verified_by, verified_at: new Date().toISOString(),
              verified_intent_key: data.intent_key, resolved_intent_key: data.intent_key }
          : r));
        setEdits(prev => { const n = { ...prev }; delete n[term.search_term]; return n; });
        showFeedback('success', `${term.search_term} → ${data.intent_key ?? 'no intent'}`);
      } else {
        showFeedback('error', data.error || 'Failed to save');
      }
    } catch {
      showFeedback('error', 'Network error');
    } finally {
      setBusyTerm(null);
    }
  };

  const totalClicks = useMemo(
    () => Object.values(counts).reduce((s, c) => s + (c.clicks || 0), 0), [counts]);
  const verifiedClicks = useMemo(
    () => ['VERIFIED', 'CORRECTED', 'REJECTED'].reduce((s, k) => s + (counts[k]?.clicks || 0), 0),
    [counts]);

  if (loadError) {
    return (
      <Card className="p-6 text-center border-dashed border-red-500/30">
        <AlertTriangle size={20} className="mx-auto mb-2 text-red-400" />
        <div className="text-sm text-default">Couldn't load intent configuration.</div>
        <div className="text-xs text-subtle mt-1">Is the data-entry API running? (local: Flask on :5050)</div>
        <button onClick={fetchAll} className="mt-3 inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg border border-border bg-card hover:bg-white/[.04] transition-colors">
          <RefreshCw size={14} /> Retry
        </button>
      </Card>
    );
  }

  const block = popupData && popupData[popupProductIdx];

  return (
    <div className="space-y-4">
      {/* Monthly intent popup */}
      {popupIntent && (
        <div onClick={() => setPopupIntent(null)}
          style={{ minHeight: 400 }}
          className="fixed inset-0 z-50 flex items-start justify-center bg-black/50 p-6 overflow-y-auto">
          <div onClick={e => e.stopPropagation()}
            className="w-full max-w-3xl mt-12 rounded-xl border border-border bg-card shadow-xl">
            <div className="flex items-center justify-between px-5 py-3 border-b border-border">
              <div>
                <div className="text-sm font-semibold text-default">{popupIntent}</div>
                <div className="text-[11px] text-subtle">12-month model — CVR, target CPC, expected net ROAS</div>
              </div>
              <button onClick={() => setPopupIntent(null)} className="p-1 rounded hover:bg-white/[.06] text-subtle">
                <X size={16} />
              </button>
            </div>
            {popupLoading && <div className="p-8 text-center text-subtle"><Loader2 size={16} className="inline animate-spin mr-2" />Loading…</div>}
            {!popupLoading && (!popupData || popupData.length === 0) && (
              <div className="p-8 text-center text-subtle">No model coverage for this intent yet.</div>
            )}
            {!popupLoading && block && (
              <div className="p-5 space-y-4">
                {/* product selector — the curve is per product */}
                {popupData!.length > 1 && (
                  <div className="flex flex-wrap gap-1">
                    {popupData!.map((b, i) => (
                      <button key={b.product} onClick={() => setPopupProductIdx(i)}
                        className={`px-2.5 py-1 text-xs rounded-md border transition-colors ${
                          i === popupProductIdx ? 'bg-zinc-700 text-white border-border-strong'
                          : 'text-subtle border-border hover:text-default'}`}>
                        {b.product}
                      </button>
                    ))}
                  </div>
                )}
                <div className="flex items-baseline gap-2">
                  <span className="text-sm font-semibold text-default">{block.product}</span>
                  <span className="text-[11px] text-subtle">{block.family}</span>
                  <Badge variant={block.confidence === 'HIGH' ? 'green' : block.confidence === 'INSUFFICIENT' ? 'red' : 'amber'}>
                    {block.confidence}
                  </Badge>
                  <span className="text-[11px] text-subtle">{fmt(block.base_clicks || 0)} clicks</span>
                </div>

                {/* suggestion */}
                <div className="rounded-lg bg-accent/[.06] border border-accent/20 px-3 py-2 text-[13px] text-default">
                  <span className="font-semibold text-accent">Suggestion: </span>{block.suggestion}
                </div>

                {/* monthly table */}
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="text-subtle border-b border-border">
                        <th className="text-left font-semibold px-2 py-1.5">Month</th>
                        <th className="text-right font-semibold px-2 py-1.5">CVR</th>
                        <th className="text-right font-semibold px-2 py-1.5">Target CPC</th>
                        <th className="text-right font-semibold px-2 py-1.5">Breakeven</th>
                        <th className="text-right font-semibold px-2 py-1.5">Market CPC</th>
                        <th className="text-right font-semibold px-2 py-1.5">Net ROAS</th>
                        <th className="text-left font-semibold px-2 py-1.5">Action</th>
                      </tr>
                    </thead>
                    <tbody>
                      {block.months.map(m => (
                        <tr key={m.month_of_year} className="border-b border-border/40">
                          <td className="px-2 py-1.5 text-default">{MONTHS[m.month_of_year]}</td>
                          <td className="px-2 py-1.5 text-right tabular-nums">{m.cvr_hat != null ? `${(m.cvr_hat*100).toFixed(1)}%` : '--'}</td>
                          <td className="px-2 py-1.5 text-right tabular-nums text-default">{m.target_bid != null ? `$${m.target_bid.toFixed(2)}` : '--'}</td>
                          <td className="px-2 py-1.5 text-right tabular-nums text-subtle">{m.max_bid != null ? `$${m.max_bid.toFixed(2)}` : '--'}</td>
                          <td className="px-2 py-1.5 text-right tabular-nums text-subtle">{m.actual_cpc != null ? `$${m.actual_cpc.toFixed(2)}` : '–'}</td>
                          <td className="px-2 py-1.5 text-right tabular-nums">{m.net_roas_at_market != null ? `${m.net_roas_at_market.toFixed(2)}x` : '–'}</td>
                          <td className={`px-2 py-1.5 font-semibold ${actionColor(m.action)}`}>{m.action}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <div className="text-[11px] text-subtle">
                  Target CPC banks the 30% margin; breakeven is the ceiling. Net ROAS is expected gross
                  profit per ad dollar at the market CPC actually paid (— = no ads ran that month).
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {feedback && (
        <div className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-medium ${
          feedback.type === 'success'
            ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
            : 'bg-red-500/10 text-red-400 border border-red-500/20'
        }`}>
          {feedback.type === 'success' ? <Check size={16} /> : <X size={16} />}
          {feedback.msg}
        </div>
      )}

      {/* Coverage — by CLICKS, not term count. 201k terms exist and most are one-click
          noise; the number that matters is how much traffic has a settled verdict. */}
      <Card className="p-4">
        <div className="flex items-baseline justify-between mb-2">
          <div className="text-xs font-semibold text-subtle uppercase tracking-wide">
            Reviewed traffic
          </div>
          <div className="text-sm font-semibold text-default">
            {totalClicks > 0 ? ((verifiedClicks / totalClicks) * 100).toFixed(1) : '0.0'}% of clicks
          </div>
        </div>
        <div className="h-1.5 rounded-full bg-zinc-700/40 overflow-hidden">
          <div className="h-full bg-emerald-500/70 rounded-full"
               style={{ width: `${totalClicks > 0 ? (verifiedClicks / totalClicks) * 100 : 0}%` }} />
        </div>
        <div className="flex flex-wrap gap-3 mt-3 text-[11px] text-subtle">
          {FILTERS.filter(f => f !== 'ALL').map(f => (
            <span key={f}>
              <Badge variant={statusVariant(f)}>{f}</Badge>{' '}
              {fmt(counts[f]?.terms || 0)} terms · {fmt(counts[f]?.clicks || 0)} clicks
            </span>
          ))}
        </div>
      </Card>

      {/* Filters */}
      <div className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex gap-1 p-0.5 rounded-lg bg-zinc-800/40">
            {FILTERS.map(f => (
              <button key={f} onClick={() => setStatus(f)}
                className={`px-2.5 py-1 text-xs font-semibold rounded-md transition-colors ${
                  status === f ? 'bg-zinc-700 text-white' : 'text-subtle hover:text-default'}`}>
                {f}
              </button>
            ))}
          </div>
          <div className="relative flex-1 min-w-[200px]">
            <Search size={14} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-subtle" />
            <input value={search} onChange={e => setSearch(e.target.value)}
              placeholder="Filter search terms…"
              className="w-full pl-8 pr-3 py-1.5 text-xs rounded-lg bg-card border border-border text-default placeholder:text-subtle focus:outline-none focus:border-zinc-600" />
          </div>
          <button onClick={fetchAll}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg border border-border bg-card hover:bg-white/[.04] transition-colors">
            <RefreshCw size={13} /> Refresh
          </button>
        </div>
        {/* Intent filter — options come from the same volume-ordered vocabulary as the picker */}
        <div className="flex items-center gap-2">
          <span className="text-[11px] text-subtle uppercase tracking-wide">Intent</span>
          <select value={intentFilter} onChange={e => setIntentFilter(e.target.value)}
            className={`px-2 py-1.5 text-xs rounded-lg bg-card border text-default focus:outline-none min-w-[240px] ${
              intentFilter ? 'border-accent/60' : 'border-border'}`}>
            <option value="">All intents</option>
            {themes.map(t => (
              <option key={t.intent_key} value={t.intent_key}>
                {t.label} ({fmt(t.clicks)} clicks)
              </option>
            ))}
          </select>
          {intentFilter && (
            <button onClick={() => setIntentFilter('')}
              className="text-[11px] text-subtle hover:text-default underline decoration-dotted">clear</button>
          )}
        </div>
      </div>

      {/* Table — server orders by clicks DESC, highest volume first */}
      <Card className="overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="text-subtle border-b border-border">
                <th className="text-left font-semibold px-3 py-2">Search term</th>
                <th className="text-right font-semibold px-2 py-2">Clicks</th>
                <th className="text-right font-semibold px-2 py-2">Orders</th>
                <th className="text-right font-semibold px-2 py-2">CVR</th>
                <th className="text-right font-semibold px-2 py-2">Spend</th>
                <th className="text-left font-semibold px-2 py-2">Facets</th>
                <th className="text-left font-semibold px-2 py-2">Suggested</th>
                <th className="text-left font-semibold px-2 py-2">Intent</th>
                <th className="text-left font-semibold px-2 py-2">Status</th>
                <th className="text-right font-semibold px-3 py-2">Verify</th>
              </tr>
            </thead>
            <tbody>
              {loading && (
                <tr><td colSpan={10} className="text-center py-8 text-subtle">
                  <Loader2 size={16} className="inline animate-spin mr-2" />Loading…
                </td></tr>
              )}
              {!loading && rows.length === 0 && (
                <tr><td colSpan={10} className="text-center py-8 text-subtle">No terms match.</td></tr>
              )}
              {!loading && rows.map(r => {
                const chosen = edits[r.search_term] ?? r.resolved_intent_key ?? '';
                const changed = chosen !== (r.resolved_intent_key ?? '');
                const busy = busyTerm === r.search_term;
                return (
                  <tr key={r.search_term}
                      className={`border-b border-border/50 hover:bg-white/[.02] ${r.is_stale ? 'bg-amber-500/[.04]' : ''}`}>
                    <td className="px-3 py-2 text-default max-w-[280px] truncate" title={r.search_term}>
                      {r.search_term}
                    </td>
                    <td className="px-2 py-2 text-right tabular-nums text-default">{fmt(r.clicks_365d || 0)}</td>
                    <td className="px-2 py-2 text-right tabular-nums text-subtle">{fmt(r.orders_365d || 0)}</td>
                    <td className="px-2 py-2 text-right tabular-nums text-subtle">
                      {r.cvr_pct != null ? `${r.cvr_pct.toFixed(1)}%` : '--'}
                    </td>
                    <td className="px-2 py-2 text-right tabular-nums text-subtle">
                      {fM(r.cost_365d || 0)}
                    </td>
                    <td className="px-2 py-2 text-subtle max-w-[210px]">
                      {r.suggested_facets
                        ? <span className="text-[11px] leading-tight">{r.suggested_facets}</span>
                        : <span className="italic">{r.term_kind && r.term_kind !== 'KEYWORD' ? r.term_kind.toLowerCase() : 'none'}</span>}
                    </td>
                    <td className="px-2 py-2 text-subtle">
                      {r.machine_suggestion
                        ? <button onClick={() => openIntent(r.machine_suggestion!)}
                            className="text-left text-accent hover:underline decoration-dotted"
                            title="Show 12-month CVR / bid / net ROAS for this intent">
                            {r.machine_suggestion}
                          </button>
                        : <span className="italic">none</span>}
                      {r.budget_tier && (
                        <Badge variant={r.budget_tier === 'PREMIUM' ? 'green' : 'red'} className="ml-1">
                          {r.budget_tier === 'PREMIUM' ? '$$' : '$'}
                        </Badge>
                      )}
                    </td>
                    <td className="px-2 py-2">
                      <select value={chosen}
                        onChange={e => setEdits(p => ({ ...p, [r.search_term]: e.target.value }))}
                        className={`px-1.5 py-1 text-xs rounded-md bg-card border text-default focus:outline-none ${
                          changed ? 'border-blue-500/60' : 'border-border'}`}>
                        <option value="">— none —</option>
                        {themes.map(t => (
                          <option key={t.intent_key} value={t.intent_key}>{t.label}</option>
                        ))}
                      </select>
                    </td>
                    <td className="px-2 py-2">
                      <Badge variant={statusVariant(r.verification_status)}>{r.verification_status}</Badge>
                      {r.verified_by && (
                        <div className="text-[10px] text-subtle mt-0.5 truncate max-w-[110px]"
                             title={`${r.verified_by} · ${r.verified_at ?? ''}`}>
                          {r.verified_by}
                        </div>
                      )}
                    </td>
                    <td className="px-3 py-2 text-right whitespace-nowrap">
                      {busy ? <Loader2 size={14} className="inline animate-spin text-subtle" /> : (
                        <div className="inline-flex gap-1">
                          <button onClick={() => submit(r, changed ? 'CORRECTED' : 'VERIFIED')}
                            title={changed ? 'Save correction' : 'Confirm suggestion'}
                            className="p-1 rounded-md border border-border hover:bg-emerald-500/10 hover:border-emerald-500/40 text-emerald-400 transition-colors">
                            <Check size={13} />
                          </button>
                          <button onClick={() => submit(r, 'REJECTED')}
                            title="No valid intent for this term"
                            className="p-1 rounded-md border border-border hover:bg-red-500/10 hover:border-red-500/40 text-red-400 transition-colors">
                            <Ban size={13} />
                          </button>
                        </div>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Card>
      <div className="text-[11px] text-subtle px-1">
        Ordered by 365-day clicks, highest first. Showing up to 200 terms — narrow with the
        filter to reach further down the tail.
      </div>
    </div>
  );
}
