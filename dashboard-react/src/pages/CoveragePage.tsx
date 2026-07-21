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
}
interface WorkflowData {
  strategies: string[];
  tiles: Record<string, Tile>;
  cells: Cell[];
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

/** Daily-workflow coverage cockpit (rung 1): six strategy tiles rolling up
 *  defined / to-do / redundant, each expandable to its coverage cells.
 *  All status/roll-up logic lives in /api/daily-workflow (BigQuery); this only renders. */
export function CoveragePage() {
  const [data, setData] = useState<WorkflowData | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [open, setOpen] = useState<string | null>(null); // strategy name

  useEffect(() => {
    apiFetch('/api/daily-workflow')
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(d => (d.error ? setErr(d.error) : setData(d)))
      .catch(e => setErr(String(e)));
  }, []);

  if (err) return <div className="p-6 text-sm text-red-400">Coverage scan failed: {err}</div>;
  if (!data) return <div className="p-6 text-sm text-muted">Scanning ad coverage…</div>;

  const openCells = open
    ? data.cells
        .filter(c => c.strategy === open)
        .sort((a, b) => STATUS_ORDER[a.status] - STATUS_ORDER[b.status])
    : [];

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
            {openCells.length === 0 ? (
              <div className="text-faint text-[10px]">No coverage cells for this strategy.</div>
            ) : (
              openCells.map((c, i) => (
                <div key={`${c.grain}-${c.asin ?? c.parent_name ?? i}`} className="flex items-center gap-2 py-1 border-b border-border-faint last:border-0">
                  <span className="text-heading truncate max-w-[200px]" title={c.asin ?? undefined}>{cellLabel(c)}</span>
                  <span className="ml-auto"><Metrics c={c} /></span>
                  <span className="w-[100px] text-right"><StatusPill c={c} /></span>
                </div>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}
