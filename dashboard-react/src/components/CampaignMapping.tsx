import { useState, useEffect, useCallback, useMemo } from 'react';
import { Check, X, Search, Wand2, AlertTriangle, RefreshCw } from 'lucide-react';
import { Card } from './Card';
import { Badge } from './Badge';
import { apiFetch } from '../utils/apiFetch';
import { fM } from '../utils';
import {
  needsMapping,
  approveAllEligible,
  friendlyStrategy,
} from './campaignMapping.helpers';
import type { CampaignMappingRow, MappingCoverageCheck } from './campaignMapping.helpers';

type View = 'unmapped' | 'mapped';

// Source badge color. unmapped = needs attention (red), default = weak guess (amber),
// manual = admin-set (blue), auto = engine-set (green).
function sourceVariant(s: string): string {
  if (s === 'unmapped') return 'red';
  if (s === 'default') return 'amber';
  if (s === 'manual') return 'blue';
  if (s === 'auto') return 'green';
  return 'muted';
}

export function CampaignMapping() {
  const [rows, setRows] = useState<CampaignMappingRow[]>([]);
  const [families, setFamilies] = useState<string[]>([]);
  const [strategies, setStrategies] = useState<string[]>([]);
  const [coverage, setCoverage] = useState<MappingCoverageCheck[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [view, setView] = useState<View>('unmapped');
  const [search, setSearch] = useState('');
  const [edits, setEdits] = useState<Record<string, { family: string; strategy: string }>>({});
  const [busyId, setBusyId] = useState<string | null>(null);
  const [approvingAll, setApprovingAll] = useState(false);
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; msg: string } | null>(null);

  const showFeedback = (type: 'success' | 'error', msg: string) => {
    setFeedback({ type, msg });
    setTimeout(() => setFeedback(null), 3500);
  };

  const fetchAll = useCallback(async () => {
    setLoading(true);
    setLoadError(false);
    try {
      const [mapRes, covRes] = await Promise.all([
        apiFetch('/api/admin/campaign-mapping'),
        apiFetch('/api/admin/mapping-coverage'),
      ]);
      if (!mapRes.ok) { setLoadError(true); return; }
      const mapData = await mapRes.json();
      if (!mapData.success) { setLoadError(true); return; }
      setRows(mapData.campaigns || []);
      setFamilies(mapData.families || []);
      setStrategies(mapData.strategies || []);
      setEdits({});
      if (covRes.ok) {
        const covData = await covRes.json();
        if (covData.success) setCoverage(covData.checks || []);
      }
    } catch {
      setLoadError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchAll(); }, [fetchAll]);

  // Prefill, but only with values the backend will accept (the suggestion engine can
  // emit non-option values like "UNKNOWN"). Family from the suggestion (the GET payload
  // has no current_family field); strategy from current mapping, else the suggestion.
  const validFamily = (f: string | null) => (f && families.includes(f) ? f : '');
  const validStrategy = (s: string | null) => (s && strategies.includes(s) ? s : '');
  const editFor = (r: CampaignMappingRow) => edits[r.campaign_id] || {
    family: validFamily(r.suggested_family),
    strategy: validStrategy(r.current_strategy_id) || validStrategy(r.suggested_strategy),
  };
  const setEdit = (r: CampaignMappingRow, patch: Partial<{ family: string; strategy: string }>) => {
    setEdits(prev => ({ ...prev, [r.campaign_id]: { ...editFor(r), ...patch } }));
  };

  const assign = async (r: CampaignMappingRow) => {
    const { family, strategy } = editFor(r);
    if (!family || !strategy) return;
    setBusyId(r.campaign_id);
    try {
      const res = await apiFetch('/api/admin/campaign-mapping/assign', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ campaign_id: r.campaign_id, family, strategy }),
      });
      const data = await res.json();
      if (data.success) {
        showFeedback('success', `Mapped "${r.campaign_name}" → ${family} / ${friendlyStrategy(strategy)}`);
        await fetchAll();
      } else {
        showFeedback('error', data.error || 'Failed to assign');
      }
    } catch {
      showFeedback('error', 'Network error');
    } finally {
      setBusyId(null);
    }
  };

  const approveAll = async () => {
    const eligible = approveAllEligible(rows);
    if (eligible.length === 0) { showFeedback('error', 'No suggestions to apply'); return; }
    setApprovingAll(true);
    let applied = 0, failed = 0;
    for (const r of eligible) {
      try {
        const res = await apiFetch('/api/admin/campaign-mapping/assign', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            campaign_id: r.campaign_id,
            family: r.suggested_family as string,
            strategy: r.suggested_strategy as string,
          }),
        });
        const data = await res.json();
        if (data.success) applied++; else failed++;
      } catch {
        failed++;
      }
    }
    setApprovingAll(false);
    showFeedback(failed ? 'error' : 'success', `${applied} applied${failed ? `, ${failed} failed` : ''}`);
    await fetchAll();
  };

  const unmappedCount = useMemo(() => rows.filter(needsMapping).length, [rows]);
  const mappedCount = rows.length - unmappedCount;
  const eligibleCount = useMemo(() => approveAllEligible(rows).length, [rows]);
  const gaps = useMemo(() => coverage.filter(c => c.gap > 0), [coverage]);

  const visible = useMemo(() => {
    const q = search.trim().toLowerCase();
    return rows
      .filter(r => (view === 'unmapped' ? needsMapping(r) : !needsMapping(r)))
      .filter(r => !q || r.campaign_name.toLowerCase().includes(q));
  }, [rows, view, search]);

  if (loadError) {
    return (
      <Card className="p-6 text-center border-dashed border-red-500/30">
        <AlertTriangle size={20} className="mx-auto mb-2 text-red-400" />
        <div className="text-sm text-default">Couldn't load campaign mapping.</div>
        <div className="text-xs text-subtle mt-1">Is the data-entry API running? (local: Flask on :5050)</div>
        <button onClick={fetchAll} className="mt-3 inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg border border-border bg-card hover:bg-white/[.04] transition-colors">
          <RefreshCw size={14} /> Retry
        </button>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {/* Feedback toast */}
      {feedback && (
        <div className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-medium animate-in ${
          feedback.type === 'success' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 'bg-red-500/10 text-red-400 border border-red-500/20'
        }`}>
          {feedback.type === 'success' ? <Check size={16} /> : <X size={16} />}
          {feedback.msg}
        </div>
      )}

      {/* Coverage gap banner */}
      {!loading && (
        gaps.length === 0 ? (
          <div className="flex items-center gap-2 px-3 py-2 rounded-lg text-xs font-medium bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
            <Check size={14} /> All mapping checks clear.
          </div>
        ) : (
          <div className="flex flex-wrap gap-1.5">
            {gaps.map(c => (
              <span
                key={c.check_key}
                title={c.items.slice(0, 12).join(', ')}
                className={`inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-semibold border ${
                  c.critical ? 'bg-red-500/10 text-red-300 border-red-500/25' : 'bg-amber-500/10 text-amber-300 border-amber-500/25'
                }`}
              >
                <AlertTriangle size={12} />
                {c.label}: <span className="font-mono">{c.gap}</span>
                <span className="opacity-60 font-mono">({Math.round(c.pct)}% mapped)</span>
              </span>
            ))}
          </div>
        )
      )}

      {/* Toolbar */}
      <div className="flex flex-wrap items-center gap-2">
        {/* Not Mapped / Mapped toggle (default Not Mapped) */}
        <div className="flex rounded-lg border border-border/50 overflow-hidden">
          <button
            onClick={() => setView('unmapped')}
            className={`px-3 py-2 text-xs font-semibold transition-all ${view === 'unmapped' ? 'bg-blue-500/15 text-blue-400' : 'bg-card text-subtle hover:text-default'}`}
          >
            Not Mapped <span className="font-mono opacity-70">{unmappedCount}</span>
          </button>
          <button
            onClick={() => setView('mapped')}
            className={`px-3 py-2 text-xs font-semibold transition-all border-l border-border/50 ${view === 'mapped' ? 'bg-blue-500/15 text-blue-400' : 'bg-card text-subtle hover:text-default'}`}
          >
            Mapped <span className="font-mono opacity-70">{mappedCount}</span>
          </button>
        </div>

        {/* Approve all (Not Mapped view only) */}
        {view === 'unmapped' && (
          <button
            onClick={approveAll}
            disabled={approvingAll || eligibleCount === 0}
            className="flex items-center gap-1.5 px-3 py-2 text-xs font-semibold rounded-lg border border-purple-500/30 bg-purple-500/10 text-purple-300 hover:bg-purple-500/20 disabled:opacity-40 disabled:cursor-not-allowed transition-all"
          >
            <Wand2 size={14} className={approvingAll ? 'animate-pulse' : ''} />
            {approvingAll ? 'Applying…' : `Approve all suggestions (${eligibleCount})`}
          </button>
        )}

        {/* Search */}
        <div className="relative flex-1 min-w-[200px] max-w-[360px]">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-subtle" />
          <input
            type="text"
            placeholder="Search campaigns…"
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 text-sm rounded-lg bg-card border border-border/50 focus:border-blue-500/50 focus:outline-none transition-colors"
          />
          {search && (
            <button onClick={() => setSearch('')} className="absolute right-2 top-1/2 -translate-y-1/2 text-subtle hover:text-default">
              <X size={14} />
            </button>
          )}
        </div>

        <button
          onClick={fetchAll}
          disabled={loading}
          className="flex items-center gap-1.5 px-3 py-2 text-xs font-semibold rounded-lg border border-border/50 bg-card hover:bg-white/[.04] transition-colors disabled:opacity-50"
        >
          <RefreshCw size={14} className={loading ? 'animate-spin' : ''} /> Refresh
        </button>
      </div>

      {/* Rows */}
      {loading ? (
        <div className="py-12 text-center text-subtle text-sm animate-pulse">Loading campaigns…</div>
      ) : visible.length === 0 ? (
        <Card className="py-8 text-center text-subtle text-sm border-dashed">
          {search
            ? `No campaigns matching "${search}"`
            : view === 'unmapped' ? 'No unmapped campaigns — all spending campaigns are mapped.' : 'No mapped campaigns yet.'}
        </Card>
      ) : (
        <div className="space-y-2">
          {visible.map(r => {
            const ed = editFor(r);
            const canAssign = !!ed.family && !!ed.strategy && busyId !== r.campaign_id;
            return (
              <Card key={r.campaign_id} className="!p-3">
                <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
                  {/* Name + current */}
                  <div className="min-w-[220px] flex-1">
                    <div className="text-sm font-semibold text-default flex items-center gap-2">
                      {r.campaign_name}
                      <Badge variant={sourceVariant(r.source)}>{r.source}</Badge>
                    </div>
                    <div className="text-[11px] text-subtle font-mono mt-0.5">
                      {r.campaign_id} · 60d {fM(r.spend_60d)}
                    </div>
                    <div className="text-[11px] text-faint mt-0.5">
                      Current: {r.current_experiment_name || '—'}
                      {r.current_strategy_id ? ` · ${friendlyStrategy(r.current_strategy_id)}` : ''}
                    </div>
                  </div>

                  {/* Suggestion */}
                  <div className="text-[11px] text-subtle min-w-[150px]">
                    {r.suggested_family && r.suggested_strategy ? (
                      <>
                        <span className="text-faint">Suggested: </span>
                        {r.suggested_family} / {friendlyStrategy(r.suggested_strategy)}
                        {Number.isFinite(r.confidence) && (
                          <span className="font-mono opacity-60"> ({Math.round((r.confidence as number) * 100)}%)</span>
                        )}
                      </>
                    ) : (
                      <span className="text-faint">No suggestion</span>
                    )}
                  </div>

                  {/* Editors + Assign */}
                  <div className="flex items-center gap-2">
                    <select
                      value={ed.family}
                      onChange={e => setEdit(r, { family: e.target.value })}
                      className="px-2 py-1.5 text-xs rounded-lg bg-card border border-border/50 text-default min-w-[110px]"
                    >
                      <option value="">Family…</option>
                      {families.map(f => <option key={f} value={f}>{f}</option>)}
                    </select>
                    <select
                      value={ed.strategy}
                      onChange={e => setEdit(r, { strategy: e.target.value })}
                      className="px-2 py-1.5 text-xs rounded-lg bg-card border border-border/50 text-default min-w-[150px]"
                    >
                      <option value="">Strategy…</option>
                      {strategies.map(s => <option key={s} value={s}>{friendlyStrategy(s)}</option>)}
                    </select>
                    <button
                      onClick={() => assign(r)}
                      disabled={!canAssign}
                      className="px-3 py-1.5 text-xs font-semibold rounded-lg bg-emerald-500/15 text-emerald-400 border border-emerald-500/30 hover:bg-emerald-500/25 disabled:opacity-30 disabled:cursor-not-allowed transition-all"
                    >
                      {busyId === r.campaign_id ? '…' : 'Assign'}
                    </button>
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      )}

      {/* Footer */}
      {!loading && (
        <div className="text-[11px] text-faint pt-1">
          Showing {visible.length} {view === 'unmapped' ? 'unmapped' : 'mapped'} of {rows.length} spending campaigns.
        </div>
      )}
    </div>
  );
}
