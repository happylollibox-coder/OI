import { useEffect, useState } from 'react';
import { apiFetch } from '../utils/apiFetch';
import { fShort, fR } from '../utils';

interface Tile {
  defined: number;
  missing: number;
  redundant: number;
  informational: number;
  suppressed: number;
}
interface Cell {
  grain: 'ASIN' | 'FAMILY' | 'STORE';
  parent_name: string | null;
  asin: string | null;
  product_short_name: string | null;
  strategy: string;
  expected: boolean;
  n_enabled: number;
  n_any: number;
  impressions: number;
  clicks: number;
  units: number;
  net_roas: number | null;
  campaigns: string | null;
  suppressed: boolean;
  status: 'ok' | 'missing' | 'redundant' | 'none' | 'suppressed';
  reason: string;
  cell_key: string;
}
interface DetailCampaign {
  campaign_name: string;
  state: string | null;
  is_enabled: boolean;
  impressions: number;
  clicks: number;
  units: number;
  ad_spend: number;
  net_roas: number | null;
  last_seen: string;
}
interface WorkflowData {
  strategies: string[];
  tiles: Record<string, Tile>;
  cells: Cell[];
  detail: Record<string, DetailCampaign[]>;
}

interface KeywordRowData {
  parent_name: string;
  match_type: string;
  keyword_text: string;
  is_running: boolean;
  is_enabled: boolean;
  is_recommended: boolean;
  clicks: number;
  cost: number;
  net_profit: number;
  research_rank: number | null;
  overall_fit: number | null;
  is_relevant: boolean | null;
  ads_net_roas: number | null;
  rec_type: string | null;
  last_seen: string | null;
  status: string;
}
interface FamilyKeywords {
  counts: { running: number; missing: number; orphan: number; paused: number };
  missing_shown: number;
  missing_total: number;
  keywords: KeywordRowData[];
}

const STRAT_LABEL: Record<string, string> = {
  AUTO: 'Auto',
  INTENT: 'Intent',
  EXACT_BOOST: 'Exact Boost',
  COMPETITOR: 'Competitor',
  BRAND_DEFENSE: 'Brand Defense',
  PRODUCT_DEFENSE: 'Product Defense',
};

function StatusPill({ c }: { c: Cell }) {
  const map: Record<Cell['status'], { tone: string; label: string }> = {
    ok: { tone: 'text-emerald-400', label: '✓ defined' },
    missing: { tone: 'text-red-400', label: '✗ to do' },
    redundant: { tone: 'text-amber-400', label: `⚠ ${c.n_enabled} campaigns` },
    none: { tone: 'text-faint', label: '– not running' },
    suppressed: { tone: 'text-subtle', label: '⊘ not expected' },
  };
  const { tone, label } = map[c.status];
  return <span className={`${tone} font-semibold text-[10px]`}>{label}</span>;
}

function Metrics({ c }: { c: Cell }) {
  if (!c.clicks) return <span className="text-faint text-[9px]">no data</span>;
  return (
    <span className="text-[9px] tabular-nums text-muted">
      {c.net_roas != null && <span className={c.net_roas >= 1 ? 'text-emerald-400' : 'text-red-400'}>{fR(c.net_roas)}</span>}
      {' · '}{fShort(c.clicks)} clk · {fShort(c.impressions)} imp · {c.units}u
    </span>
  );
}

/** Strategy roll-up tile — defined / to-do / redundant across a strategy's coverage cells.
 *  Border tone: red if anything to do, else amber if redundant, else emerald. */
export function StrategyTile({ name, t, open, onOpen }: { name: string; t: Tile; open: boolean; onOpen: () => void }) {
  const tone = t.missing > 0
    ? 'border-red-500/40 bg-red-500/10 hover:bg-red-500/20'
    : t.redundant > 0
      ? 'border-amber-500/40 bg-amber-500/10 hover:bg-amber-500/20'
      : 'border-emerald-500/50 bg-emerald-500/10 hover:bg-emerald-500/20';
  return (
    <button
      onClick={onOpen}
      className={`rounded-lg border px-4 py-3 text-left min-w-[150px] transition ${tone} ${open ? 'ring-2 ring-blue-400/60' : ''}`}
    >
      <div className="text-xs font-bold text-heading">{STRAT_LABEL[name] ?? name}</div>
      <div className="mt-1 text-[10px] font-semibold">
        <span className="text-emerald-400">✓ {t.defined} defined</span>
        {t.missing > 0 && <><span className="text-faint"> · </span><span className="text-red-400">✗ {t.missing} to do</span></>}
        {t.redundant > 0 && <><span className="text-faint"> · </span><span className="text-amber-400">⚠ {t.redundant} redundant</span></>}
        {t.informational > 0 && <><span className="text-faint"> · </span><span className="text-faint">{t.informational} idle</span></>}
      </div>
    </button>
  );
}

/** State badge for a campaign in the evidence list. */
function StateBadge({ state }: { state: string | null }) {
  const map: Record<string, { cls: string; label: string }> = {
    ENABLED: { cls: 'bg-emerald-500/15 text-emerald-400', label: 'ENABLED' },
    PAUSED: { cls: 'bg-white/[0.06] text-subtle', label: 'PAUSED' },
    ARCHIVED: { cls: 'bg-white/[0.03] text-faint', label: 'ARCHIVED' },
  };
  const m = state ? map[state] : undefined;
  const cls = m?.cls ?? 'bg-white/[0.03] text-faint';
  const label = m?.label ?? (state ?? '—');
  return <span className={`shrink-0 rounded px-1 py-px text-[9px] font-semibold ${cls}`}>{label}</span>;
}

/** One campaign in a cell's evidence list: state badge · name · right-aligned metrics. */
export function CampaignEvidenceRow({ c }: { c: DetailCampaign }) {
  return (
    <div className="flex items-center gap-1.5 py-0.5">
      <StateBadge state={c.state} />
      <span className="truncate text-[10px] text-muted" title={c.campaign_name}>{c.campaign_name}</span>
      <span className="ml-auto shrink-0 text-[9px] tabular-nums text-faint">
        {c.net_roas != null && (
          <span className={c.net_roas >= 1 ? 'text-emerald-400' : 'text-red-400'}>{fR(c.net_roas)}</span>
        )}
        {c.net_roas != null && ' · '}{fShort(c.clicks)} clk · {c.units}u · ${c.ad_spend.toFixed(0)}
      </span>
    </div>
  );
}

/** Tiny match-type chip (EXACT/PHRASE/BROAD) with a faint tint. */
function MatchChip({ mt }: { mt: string }) {
  const tint: Record<string, string> = {
    EXACT: 'bg-emerald-500/10 text-emerald-400',
    PHRASE: 'bg-blue-500/10 text-blue-400',
    BROAD: 'bg-amber-500/10 text-amber-400',
  };
  const cls = tint[mt] ?? 'bg-white/[0.05] text-faint';
  return <span className={`shrink-0 rounded px-1 py-px text-[9px] font-semibold ${cls}`}>{mt}</span>;
}

/** One keyword in a family's coverage list: match chip + text, right-aligned status-appropriate metrics. */
export function KeywordRow({ k }: { k: KeywordRowData }) {
  return (
    <div className="flex items-center gap-1.5 border-b border-border-faint py-0.5 last:border-0">
      <MatchChip mt={k.match_type} />
      <span className="truncate text-[11px] text-muted" title={k.keyword_text}>{k.keyword_text}</span>
      <span className="ml-auto shrink-0 text-[10px] tabular-nums text-faint">
        {k.status === 'running' && (
          <>
            ${k.cost.toFixed(0)} spend · {k.clicks} clk
            {k.research_rank != null && ` · rank ${k.research_rank}`}
            {k.ads_net_roas != null && (
              <>
                {' · '}
                <span className={k.ads_net_roas >= 1 ? 'text-emerald-400' : 'text-red-400'}>{k.ads_net_roas.toFixed(2)}x</span>
              </>
            )}
          </>
        )}
        {k.status === 'orphan' && (
          <span className="inline-flex items-center gap-1">
            <span>${k.cost.toFixed(0)} spend · {k.clicks} clk</span>
            <span className={`rounded px-1 py-px text-[9px] font-semibold ${k.is_relevant === false ? 'bg-red-500/15 text-red-400' : 'bg-amber-500/15 text-amber-400'}`}>
              {k.is_relevant === false ? 'not relevant' : 'no research rank'}
            </span>
          </span>
        )}
        {k.status === 'missing' && (
          <span className="inline-flex items-center gap-1">
            <span>rank {k.research_rank ?? '—'}</span>
            {k.rec_type === 'BRAND' && <span className="rounded bg-blue-500/15 px-1 py-px text-[9px] font-semibold text-blue-400">BRAND</span>}
          </span>
        )}
        {k.status === 'paused' && <span className="text-faint">${k.cost.toFixed(0)} spend</span>}
      </span>
    </div>
  );
}

/** Keyword-level coverage for an INTENT family cell — status-grouped, honest metrics only. */
function KeywordPanel({ family, data, loading }: { family: string | null; data: Record<string, FamilyKeywords> | null; loading: boolean }) {
  if (loading && !data) return <div className="mt-2 text-faint text-[10px]">loading keywords…</div>;
  const fam = data?.[family ?? ''];
  if (!fam) return <div className="mt-2 text-faint text-[10px]">no keyword data</div>;

  const { counts, keywords } = fam;
  const groups: { key: string; header: string; rows: KeywordRowData[]; cap?: number }[] = [
    { key: 'orphan', header: '⚠ Review (off-strategy waste)', rows: keywords.filter(k => k.status === 'orphan') },
    { key: 'missing', header: '✗ Missing (top opportunities)', rows: keywords.filter(k => k.status === 'missing') },
    { key: 'running', header: '✓ Running', rows: keywords.filter(k => k.status === 'running'), cap: 15 },
    { key: 'paused', header: '⏸ Paused', rows: keywords.filter(k => k.status === 'paused') },
  ];

  return (
    <div className="mt-2 rounded border border-border-faint bg-surface/40 p-2">
      <div className="mb-1.5 flex items-center gap-2">
        <span className="text-[11px] font-semibold text-heading">Keywords</span>
        <span className="text-[10px] tabular-nums">
          {counts.running > 0 && <span className="text-emerald-400">✓ {counts.running} running</span>}
          {counts.missing > 0 && <>{counts.running > 0 && <span className="text-faint"> · </span>}<span className="text-red-400">✗ {counts.missing} missing</span></>}
          {counts.orphan > 0 && <>{(counts.running > 0 || counts.missing > 0) && <span className="text-faint"> · </span>}<span className="text-amber-400">⚠ {counts.orphan} review</span></>}
          {counts.paused > 0 && <>{(counts.running > 0 || counts.missing > 0 || counts.orphan > 0) && <span className="text-faint"> · </span>}<span className="text-faint">⏸ {counts.paused} paused</span></>}
        </span>
      </div>
      {groups.map(g => {
        if (g.rows.length === 0) return null;
        const shown = g.cap && g.rows.length > g.cap ? g.rows.slice(0, g.cap) : g.rows;
        const extra = g.cap && g.rows.length > g.cap ? g.rows.length - g.cap : 0;
        return (
          <div key={g.key} className="mt-1.5">
            <div className="mb-0.5 text-[9px] font-semibold uppercase tracking-wide text-faint">{g.header}</div>
            {shown.map((k, i) => (
              <KeywordRow key={`${k.match_type}-${k.keyword_text}-${i}`} k={k} />
            ))}
            {extra > 0 && <div className="py-0.5 text-[10px] text-muted">+{extra} more</div>}
          </div>
        );
      })}
    </div>
  );
}

const STATUS_ORDER: Record<Cell['status'], number> = {
  missing: 0,
  redundant: 1,
  ok: 2,
  none: 3,
  suppressed: 4,
};

function cellLabel(c: Cell): string {
  if (c.grain === 'STORE') return 'Store';
  if (c.grain === 'FAMILY') return c.parent_name || c.asin || '—';
  return c.product_short_name || c.parent_name || c.asin || '—';
}

export interface FamilyGroup {
  family: string;
  cells: Cell[];
  missingCount: number;
}

/** Group a strategy's coverage cells by parent_name (null → "Store").
 *  Groups ordered by # of 'missing' cells DESC, then family name; cells within
 *  a group keep the status sort (missing → redundant → ok → none → suppressed). */
// eslint-disable-next-line react-refresh/only-export-components
export function groupByFamily(cells: Cell[]): FamilyGroup[] {
  const byFamily = new Map<string, Cell[]>();
  for (const c of cells) {
    const family = c.parent_name ?? 'Store';
    const arr = byFamily.get(family);
    if (arr) arr.push(c);
    else byFamily.set(family, [c]);
  }
  const groups: FamilyGroup[] = [];
  for (const [family, groupCells] of byFamily) {
    const sorted = [...groupCells].sort((a, b) => STATUS_ORDER[a.status] - STATUS_ORDER[b.status]);
    groups.push({
      family,
      cells: sorted,
      missingCount: sorted.filter(c => c.status === 'missing').length,
    });
  }
  groups.sort((a, b) => b.missingCount - a.missingCount || a.family.localeCompare(b.family));
  return groups;
}

/** Daily-workflow coverage cockpit (rung 1): six strategy tiles rolling up
 *  defined / to-do / redundant, each expandable to its coverage cells.
 *  All status/roll-up logic lives in /api/daily-workflow (BigQuery); this only renders. */
export function CoveragePage() {
  const [data, setData] = useState<WorkflowData | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [open, setOpen] = useState<string | null>(null); // strategy name
  const [openCell, setOpenCell] = useState<string | null>(null); // expanded cell_key
  const [kwData, setKwData] = useState<Record<string, FamilyKeywords> | null>(null);
  const [kwLoading, setKwLoading] = useState(false);
  const [pendingCell, setPendingCell] = useState<string | null>(null); // cell_key of in-flight suppress toggle

  async function toggleSuppress(c: Cell, active: boolean) {
    if (pendingCell) return;
    setPendingCell(c.cell_key);
    try {
      const res = await apiFetch('/api/coverage-expectation', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          parent_name: c.parent_name,
          asin: c.asin,
          strategy: c.strategy,
          active,
          reason: active ? 'marked not needed in cockpit' : 'restored expectation in cockpit',
        }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      if (!json.ok) throw new Error('server rejected expectation write');
      const wf = await apiFetch('/api/daily-workflow');
      if (!wf.ok) throw new Error(`HTTP ${wf.status}`);
      const fresh = await wf.json();
      if (fresh.error) throw new Error(fresh.error);
      setData(fresh);
    } catch (e) {
      console.warn('coverage expectation toggle failed', e);
    } finally {
      setPendingCell(null);
    }
  }

  function ensureKeywords() {
    if (kwData !== null || kwLoading) return;
    setKwLoading(true);
    apiFetch('/api/coverage-keywords')
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(json => setKwData(json.families ?? {}))
      .catch(() => setKwData({}))
      .finally(() => setKwLoading(false));
  }

  useEffect(() => {
    apiFetch('/api/daily-workflow')
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(d => (d.error ? setErr(d.error) : setData(d)))
      .catch(e => setErr(String(e)));
  }, []);

  if (err) return <div className="p-6 text-sm text-red-400">Coverage scan failed: {err}</div>;
  if (!data) return <div className="p-6 text-sm text-muted">Scanning ad coverage…</div>;

  const openGroups = open ? groupByFamily(data.cells.filter(c => c.strategy === open)) : [];
  const openCellCount = openGroups.reduce((n, g) => n + g.cells.length, 0);

  return (
    <div className="p-4">
      <div className="flex items-center gap-3 mb-4">
        <h1 className="text-lg font-bold text-heading">🗂️ Daily Workflow — Coverage</h1>
        <span className="text-[11px] text-muted">green = everything defined · click a strategy to see the mapping</span>
      </div>

      <div className="flex flex-wrap gap-2 mb-2">
        {data.strategies.map(s => (
          <StrategyTile
            key={s}
            name={s}
            t={data.tiles[s] ?? { defined: 0, missing: 0, redundant: 0, informational: 0, suppressed: 0 }}
            open={open === s}
            onOpen={() => setOpen(o => (o === s ? null : s))}
          />
        ))}
      </div>

      {open && (
        <div className="mt-3 border border-border/40 rounded-lg bg-white/[0.01] max-w-[860px]">
          <div className="flex items-center justify-between px-4 py-2.5 border-b border-border/20 bg-white/[0.02]">
            <div className="text-sm font-semibold">
              {STRAT_LABEL[open] ?? open}
              <span className="text-faint text-xs ml-2 font-normal">mapping — done vs to do</span>
            </div>
            <button onClick={() => setOpen(null)} className="text-faint hover:text-text text-lg leading-none px-1" title="Collapse">×</button>
          </div>

          <div className="p-4 text-xs">
            {openCellCount === 0 ? (
              <div className="text-faint text-[10px]">No coverage cells for this strategy.</div>
            ) : (
              openGroups.map(group => (
                <div key={group.family} className="mb-2 last:mb-0">
                  <div className="flex items-center gap-1.5 px-0.5 pb-0.5 pt-1">
                    <span className="text-muted uppercase text-[10px] font-semibold tracking-wide">{group.family}</span>
                    {group.missingCount > 0 && (
                      <span className="text-red-400 text-[10px] font-semibold">{group.missingCount} to do</span>
                    )}
                  </div>
                  {group.cells.map((c, i) => {
                    const isOpen = openCell === c.cell_key;
                    const campaigns = data.detail?.[c.cell_key];
                    const isPending = pendingCell === c.cell_key;
                    return (
                      <div key={c.cell_key || `${c.grain}-${c.asin ?? c.parent_name ?? i}`} className="border-b border-border-faint last:border-0">
                        <div className="flex w-full items-center gap-2 py-1 hover:bg-white/[0.02]">
                          <button
                            onClick={() => {
                              setOpenCell(k => (k === c.cell_key ? null : c.cell_key));
                              if (c.strategy === 'INTENT') ensureKeywords();
                            }}
                            className="flex flex-1 min-w-0 items-center gap-2 text-left"
                          >
                            <span className="text-faint text-[9px] w-2 shrink-0">{isOpen ? '▾' : '▸'}</span>
                            <span className="text-heading truncate max-w-[200px]" title={c.asin ?? undefined}>{cellLabel(c)}</span>
                            <span className="ml-auto"><Metrics c={c} /></span>
                            <span className="w-[100px] text-right"><StatusPill c={c} /></span>
                          </button>
                          {c.status === 'missing' && (
                            <button
                              onClick={() => toggleSuppress(c, true)}
                              disabled={isPending}
                              className="shrink-0 text-faint hover:text-muted text-[10px] disabled:opacity-40"
                              title="Mark this cell as not needing a campaign"
                            >
                              {isPending ? '…' : '⊘ not needed'}
                            </button>
                          )}
                          {c.status === 'suppressed' && (
                            <button
                              onClick={() => toggleSuppress(c, false)}
                              disabled={isPending}
                              className="shrink-0 text-faint hover:text-muted text-[10px] disabled:opacity-40"
                              title="Restore this cell as expected coverage"
                            >
                              {isPending ? '…' : '↩ expect'}
                            </button>
                          )}
                        </div>
                        {isOpen && (
                          <div className="pl-4 pb-2 pt-0.5">
                            {c.reason && (
                              <div className="text-muted italic text-[11px] mb-1.5">💡 {c.reason}</div>
                            )}
                            {campaigns && campaigns.length > 0 ? (
                              campaigns.map((cmp, j) => (
                                <CampaignEvidenceRow key={`${cmp.campaign_name}-${j}`} c={cmp} />
                              ))
                            ) : (
                              <div className="text-faint text-[10px]">no campaigns</div>
                            )}
                            {c.strategy === 'INTENT' && (
                              <KeywordPanel family={c.parent_name} data={kwData} loading={kwLoading} />
                            )}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}
