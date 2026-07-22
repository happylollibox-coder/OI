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
  cost: number;
  cpc: number | null;
  profit_state: string;
}
interface DetailCampaign {
  campaign_id: string;
  campaign_name: string;
  state: string | null;
  is_enabled: boolean;
  impressions: number;
  clicks: number;
  units: number;
  ad_spend: number;
  net_roas: number | null;
  last_seen: string;
  cpc: number | null;
  profit_state: string;
}
interface MonthRow {
  month: string;
  impressions: number;
  clicks: number;
  spend: number;
  units: number;
  net_profit: number;
  net_roas: number;
}
interface StrategyStat {
  total: number;
  profitable: number;
  net_profit_profitable: number;
  net_profit_unprofitable: number;
}
interface FamilyStat extends StrategyStat {
  defined: number;
  planned: number;
}
const ZERO_STAT: StrategyStat = { total: 0, profitable: 0, net_profit_profitable: 0, net_profit_unprofitable: 0 };
interface WorkflowData {
  strategies: string[];
  tiles: Record<string, Tile>;
  cells: Cell[];
  detail: Record<string, DetailCampaign[]>;
  strategy_stats?: Record<string, StrategyStat>;
  family_stats?: Record<string, FamilyStat>;
}

const STORE_KEY = '__STORE__';

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
  cpc: number | null;
  profit_state: string;
  intent_key: string | null;
  intent_label: string | null;
  is_brand: boolean;
  brand_name: string | null;
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

/** At-a-glance profit verdict pill from profit_state. */
export function ProfitChip({ state }: { state: string }) {
  const map: Record<string, { cls: string; label: string }> = {
    profitable: { cls: 'bg-emerald-500/15 text-emerald-400', label: 'profit' },
    unprofitable: { cls: 'bg-red-500/15 text-red-400', label: 'loss' },
    unknown: { cls: 'bg-white/[0.05] text-faint', label: '?' },
  };
  const m = map[state] ?? map.unknown;
  return <span className={`shrink-0 rounded px-1 py-px text-[9px] font-semibold ${m.cls}`}>{m.label}</span>;
}

/** Compact last-7-day P&L roll-up: "{profitable}/{total} profit · +$X · −$Y".
 *  Emerald net-profit and red net-loss are each omitted when 0; empty spend → "no spend (7d)". */
export function ProfitRollup({ s }: { s: StrategyStat }) {
  if (!s.total) return <div className="mt-0.5 text-[9px] text-faint">no spend (7d)</div>;
  const gain = Math.round(s.net_profit_profitable);
  const loss = Math.round(Math.abs(s.net_profit_unprofitable));
  return (
    <div className="mt-0.5 text-[9px] tabular-nums text-muted">
      <span className="text-faint">7d: </span>
      <span>{s.profitable}/{s.total} profit</span>
      {gain !== 0 && <span className="text-emerald-400"> · +${gain}</span>}
      {loss !== 0 && <span className="text-red-400"> · −${loss}</span>}
    </div>
  );
}

function Metrics({ c }: { c: Cell }) {
  if (!c.clicks) return <span className="text-faint text-[9px]">no data</span>;
  return (
    <span className="inline-flex items-center gap-1 text-[9px] tabular-nums text-muted">
      <span>
        {c.net_roas != null && <span className={c.net_roas >= 1 ? 'text-emerald-400' : 'text-red-400'}>{fR(c.net_roas)}</span>}
        {' · '}{fShort(c.clicks)} clk · {fShort(c.impressions)} imp · {c.units}u
        {c.cpc != null && ` · $${c.cpc.toFixed(2)} cpc`}
      </span>
      <ProfitChip state={c.profit_state} />
    </span>
  );
}

/** Strategy roll-up tile — defined / to-do / redundant across a strategy's coverage cells.
 *  Border tone: red if anything to do, else amber if redundant, else emerald. */
export function StrategyTile({ name, t, stat, open, onOpen }: { name: string; t: Tile; stat?: StrategyStat; open: boolean; onOpen: () => void }) {
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
      <ProfitRollup s={stat ?? ZERO_STAT} />
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

/** One month in a campaign's 12-month drill: "{YYYY-MM} · ${spend} · {clicks} clk · {units}u · {roas}x · ±$profit". */
export function MonthRow({ m }: { m: MonthRow }) {
  const roasTone = m.net_roas >= 1 ? 'text-emerald-400' : 'text-red-400';
  const profTone = m.net_profit >= 0 ? 'text-emerald-400' : 'text-red-400';
  const prof = m.net_profit >= 0
    ? `+$${Math.round(m.net_profit)}`
    : `−$${Math.round(Math.abs(m.net_profit))}`;
  return (
    <div className="flex items-center gap-1 py-px text-[9px] tabular-nums text-faint">
      <span className="w-[42px] shrink-0 text-muted">{m.month.slice(0, 7)}</span>
      <span>· ${m.spend.toFixed(0)} · {m.clicks} clk · {m.units}u ·</span>
      <span className={roasTone}>{m.net_roas.toFixed(2)}x</span>
      <span>·</span>
      <span className={profTone}>{prof}</span>
    </div>
  );
}

/** One campaign in a cell's evidence list: expander chevron · state badge · name · right-aligned
 *  metrics. Expands to reveal a lazy-loaded 12-month P&L drill (most-recent month first). */
export function CampaignEvidenceRow({
  c, months, monthsLoading = false, isOpen = false, onToggle,
}: {
  c: DetailCampaign;
  months?: MonthRow[];
  monthsLoading?: boolean;
  isOpen?: boolean;
  onToggle?: () => void;
}) {
  const recentFirst = months ? [...months].reverse() : undefined;
  return (
    <div>
      <button
        onClick={onToggle}
        className="flex w-full items-center gap-1.5 py-0.5 text-left hover:bg-white/[0.02]"
      >
        <span className="w-2 shrink-0 text-[9px] text-faint">{isOpen ? '▾' : '▸'}</span>
        <StateBadge state={c.state} />
        <span className="truncate text-[10px] text-muted" title={c.campaign_name}>{c.campaign_name}</span>
        <span className="ml-auto inline-flex shrink-0 items-center gap-1 text-[9px] tabular-nums text-faint">
          <span>
            {c.net_roas != null && (
              <span className={c.net_roas >= 1 ? 'text-emerald-400' : 'text-red-400'}>{fR(c.net_roas)}</span>
            )}
            {c.net_roas != null && ' · '}{fShort(c.clicks)} clk · {c.units}u · ${c.ad_spend.toFixed(0)}
            {c.cpc != null && ` · $${c.cpc.toFixed(2)} cpc`}
          </span>
          <ProfitChip state={c.profit_state} />
        </span>
      </button>
      {isOpen && (
        <div className="pl-4 pb-1">
          {monthsLoading && !recentFirst ? (
            <div className="text-faint text-[9px]">loading…</div>
          ) : recentFirst && recentFirst.length > 0 ? (
            recentFirst.map((m, i) => <MonthRow key={`${m.month}-${i}`} m={m} />)
          ) : (
            <div className="text-faint text-[9px]">no monthly data</div>
          )}
        </div>
      )}
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
  const showPerf = k.status === 'running' || k.status === 'orphan' || k.status === 'paused';
  return (
    <div className="flex items-center gap-1.5 border-b border-border-faint py-0.5 last:border-0">
      <MatchChip mt={k.match_type} />
      <span className="truncate text-[11px] text-muted" title={k.keyword_text}>{k.keyword_text}</span>
      <span className="ml-auto inline-flex shrink-0 items-center gap-1 text-[10px] tabular-nums text-faint">
        {k.status === 'running' && (
          <span>
            ${k.cost.toFixed(0)} spend · {k.clicks} clk
            {k.research_rank != null && ` · rank ${k.research_rank}`}
            {k.cpc != null && ` · $${k.cpc.toFixed(2)} cpc`}
            {k.ads_net_roas != null && (
              <>
                {' · '}
                <span className={k.ads_net_roas >= 1 ? 'text-emerald-400' : 'text-red-400'}>{k.ads_net_roas.toFixed(2)}x</span>
              </>
            )}
          </span>
        )}
        {k.status === 'orphan' && (
          <span className="inline-flex items-center gap-1">
            <span>${k.cost.toFixed(0)} spend · {k.clicks} clk{k.cpc != null && ` · $${k.cpc.toFixed(2)} cpc`}</span>
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
        {k.status === 'paused' && <span className="text-faint">${k.cost.toFixed(0)} spend{k.cpc != null && ` · $${k.cpc.toFixed(2)} cpc`}</span>}
        {showPerf && <ProfitChip state={k.profit_state} />}
      </span>
    </div>
  );
}

const KW_STATUS_SORT: Record<string, number> = { orphan: 0, missing: 1, running: 2, paused: 3 };
const MATCH_ORDER: Record<string, number> = { EXACT: 0, PHRASE: 1, BROAD: 2 };
const OTHER_INTENT = '__other__';

interface IntentGroup {
  key: string;
  label: string;
  rows: KeywordRowData[];
  counts: { running: number; missing: number; orphan: number; paused: number };
  activity: number;
  isOther: boolean;
}

/** Bucket a family's keywords by intent_key (null → "Other / unclassified"),
 *  sorted by activity (running+missing+orphan) DESC then label; Other always last. */
function groupByIntent(keywords: KeywordRowData[]): IntentGroup[] {
  const byIntent = new Map<string, KeywordRowData[]>();
  for (const k of keywords) {
    const key = k.intent_key ?? OTHER_INTENT;
    const arr = byIntent.get(key);
    if (arr) arr.push(k);
    else byIntent.set(key, [k]);
  }
  const groups: IntentGroup[] = [];
  for (const [key, rows] of byIntent) {
    const isOther = key === OTHER_INTENT;
    const label = isOther ? 'Other / unclassified' : (rows[0].intent_label ?? rows[0].intent_key ?? 'Other / unclassified');
    const counts = { running: 0, missing: 0, orphan: 0, paused: 0 };
    for (const r of rows) {
      if (r.status === 'running') counts.running++;
      else if (r.status === 'missing') counts.missing++;
      else if (r.status === 'orphan') counts.orphan++;
      else if (r.status === 'paused') counts.paused++;
    }
    groups.push({ key, label, rows, counts, activity: counts.running + counts.missing + counts.orphan, isOther });
  }
  groups.sort((a, b) => {
    if (a.isOther !== b.isOther) return a.isOther ? 1 : -1;
    return b.activity - a.activity || a.label.localeCompare(b.label);
  });
  return groups;
}

/** Within an intent, sub-group by match_type (EXACT → PHRASE → BROAD);
 *  rows within a match ordered orphan → missing → running → paused. */
function matchGroupsOf(rows: KeywordRowData[]): { mt: string; rows: KeywordRowData[] }[] {
  const byMatch = new Map<string, KeywordRowData[]>();
  for (const k of rows) {
    const arr = byMatch.get(k.match_type);
    if (arr) arr.push(k);
    else byMatch.set(k.match_type, [k]);
  }
  return [...byMatch.entries()]
    .map(([mt, rs]) => ({
      mt,
      rows: [...rs].sort((a, b) => (KW_STATUS_SORT[a.status] ?? 9) - (KW_STATUS_SORT[b.status] ?? 9)),
    }))
    .sort((a, b) => (MATCH_ORDER[a.mt] ?? 9) - (MATCH_ORDER[b.mt] ?? 9) || a.mt.localeCompare(b.mt));
}

/** Status sections for the brand-mode keyword panel, in display order. */
const BRAND_STATUS_SECTIONS: { status: string; label: string }[] = [
  { status: 'orphan', label: 'Review' },
  { status: 'missing', label: 'Missing' },
  { status: 'running', label: 'Running' },
  { status: 'paused', label: 'Paused' },
];

/** Keyword-level coverage for a family cell.
 *  mode='intent' (default): exclude own-brand terms, group by intent → match type.
 *  mode='brand': keep only own-brand terms, group by status (Review → Missing → Running → Paused),
 *  no intent/match nesting. The summary count line is always computed from the filtered set. */
function KeywordPanel({ family, data, loading, mode = 'intent' }: { family: string | null; data: Record<string, FamilyKeywords> | null; loading: boolean; mode?: 'intent' | 'brand' }) {
  const [openIntents, setOpenIntents] = useState<Set<string>>(new Set());
  if (loading && !data) return <div className="mt-2 text-faint text-[10px]">loading keywords…</div>;
  const fam = data?.[family ?? ''];
  if (!fam) return <div className="mt-2 text-faint text-[10px]">no keyword data</div>;

  const filtered = fam.keywords.filter(k => (mode === 'brand' ? k.is_brand : !k.is_brand));
  const counts = { running: 0, missing: 0, orphan: 0, paused: 0 };
  for (const k of filtered) {
    if (k.status === 'running') counts.running++;
    else if (k.status === 'missing') counts.missing++;
    else if (k.status === 'orphan') counts.orphan++;
    else if (k.status === 'paused') counts.paused++;
  }

  function toggle(key: string) {
    setOpenIntents(prev => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  if (mode === 'brand') {
    if (filtered.length === 0) {
      return <div className="mt-2 text-faint text-[10px]">no brand keywords</div>;
    }
    return (
      <div className="mt-2 rounded border border-border-faint bg-surface/40 p-2">
        <div className="mb-1.5 flex items-center gap-2">
          <span className="text-[11px] font-semibold text-heading">Brand keywords</span>
          <span className="text-[10px] tabular-nums">
            {counts.running > 0 && <span className="text-emerald-400">✓ {counts.running} running</span>}
            {counts.missing > 0 && <>{counts.running > 0 && <span className="text-faint"> · </span>}<span className="text-red-400">✗ {counts.missing} missing</span></>}
            {counts.orphan > 0 && <>{(counts.running > 0 || counts.missing > 0) && <span className="text-faint"> · </span>}<span className="text-amber-400">⚠ {counts.orphan} review</span></>}
            {counts.paused > 0 && <>{(counts.running > 0 || counts.missing > 0 || counts.orphan > 0) && <span className="text-faint"> · </span>}<span className="text-faint">⏸ {counts.paused} paused</span></>}
          </span>
        </div>
        {BRAND_STATUS_SECTIONS.map(sec => {
          const rows = filtered.filter(k => k.status === sec.status);
          if (rows.length === 0) return null;
          return (
            <div key={sec.status} className="mt-1">
              <div className="mb-0.5 text-[9px] font-semibold uppercase tracking-wide text-faint">{sec.label}</div>
              {rows.map((k, i) => (
                <KeywordRow key={`${k.match_type}-${k.keyword_text}-${i}`} k={k} />
              ))}
            </div>
          );
        })}
      </div>
    );
  }

  const intentGroups = groupByIntent(filtered);

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
      {intentGroups.map(g => {
        const isOpen = openIntents.has(g.key);
        return (
          <div key={g.key} className="mt-1">
            <button onClick={() => toggle(g.key)} className="flex w-full items-center gap-1.5 py-0.5 text-left hover:bg-white/[0.02]">
              <span className="w-2 shrink-0 text-[9px] text-faint">{isOpen ? '▾' : '▸'}</span>
              <span className="truncate text-[11px] font-semibold text-heading">{g.label}</span>
              <span className="ml-auto shrink-0 text-[9px] tabular-nums">
                {g.counts.running > 0 && <span className="text-emerald-400">✓{g.counts.running} </span>}
                {g.counts.missing > 0 && <span className="text-red-400">✗{g.counts.missing} </span>}
                {g.counts.orphan > 0 && <span className="text-amber-400">⚠{g.counts.orphan} </span>}
                {g.counts.paused > 0 && <span className="text-faint">⏸{g.counts.paused}</span>}
              </span>
            </button>
            {isOpen && (
              <div className="pl-4">
                {matchGroupsOf(g.rows).map(mg => (
                  <div key={mg.mt} className="mt-1">
                    <div className="mb-0.5 text-[9px] font-semibold uppercase tracking-wide text-faint">{mg.mt}</div>
                    {mg.rows.map((k, i) => (
                      <KeywordRow key={`${k.match_type}-${k.keyword_text}-${i}`} k={k} />
                    ))}
                  </div>
                ))}
              </div>
            )}
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

interface FamilyEntry {
  key: string; // family key: real parent_name, or STORE_KEY, or 'ALL'
  label: string;
  stat: FamilyStat;
}

/** Build the ordered family-button list: ALL (summed) first, real families alpha,
 *  then the Store bucket (__STORE__) last. Missing per-family fields default to zero. */
// eslint-disable-next-line react-refresh/only-export-components
export function buildFamilyEntries(familyStats: Record<string, FamilyStat> | undefined): FamilyEntry[] {
  const stats = familyStats ?? {};
  const all: FamilyStat = { total: 0, profitable: 0, net_profit_profitable: 0, net_profit_unprofitable: 0, defined: 0, planned: 0 };
  const real: FamilyEntry[] = [];
  let store: FamilyEntry | null = null;
  for (const [k, s] of Object.entries(stats)) {
    const stat: FamilyStat = {
      total: s.total ?? 0,
      profitable: s.profitable ?? 0,
      net_profit_profitable: s.net_profit_profitable ?? 0,
      net_profit_unprofitable: s.net_profit_unprofitable ?? 0,
      defined: s.defined ?? 0,
      planned: s.planned ?? 0,
    };
    all.total += stat.total;
    all.profitable += stat.profitable;
    all.net_profit_profitable += stat.net_profit_profitable;
    all.net_profit_unprofitable += stat.net_profit_unprofitable;
    all.defined += stat.defined;
    all.planned += stat.planned;
    if (k === STORE_KEY) store = { key: STORE_KEY, label: 'Store', stat };
    else real.push({ key: k, label: k, stat });
  }
  real.sort((a, b) => a.label.localeCompare(b.label));
  const entries: FamilyEntry[] = [{ key: 'ALL', label: 'All', stat: all }, ...real];
  if (store) entries.push(store);
  return entries;
}

/** One family button in the left panel: name + defined/planned + 7d profit roll-up. */
function FamilyButton({ entry, selected, onSelect }: { entry: FamilyEntry; selected: boolean; onSelect: () => void }) {
  const { defined, planned } = entry.stat;
  const dpTone = defined >= planned ? 'text-emerald-400' : 'text-red-400';
  return (
    <button
      onClick={onSelect}
      className={`w-full rounded-lg border px-3 py-2 text-left transition border-border-faint bg-surface hover:bg-white/[0.04] ${selected ? 'ring-2 ring-blue-400/60' : ''}`}
    >
      <div className="text-xs font-bold text-heading">{entry.label}</div>
      <div className={`mt-0.5 text-[10px] font-semibold tabular-nums ${dpTone}`}>{defined}/{planned} defined</div>
      <ProfitRollup s={entry.stat} />
    </button>
  );
}

/** Daily-workflow coverage cockpit (rung 1): six strategy tiles rolling up
 *  defined / to-do / redundant, each expandable to its coverage cells.
 *  All status/roll-up logic lives in /api/daily-workflow (BigQuery); this only renders. */
export function CoveragePage() {
  const [data, setData] = useState<WorkflowData | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [open, setOpen] = useState<string | null>(null); // strategy name
  const [selectedFamily, setSelectedFamily] = useState<string | null>(null); // null = ALL; else parent_name or STORE_KEY
  const [openCell, setOpenCell] = useState<string | null>(null); // expanded cell_key
  const [kwData, setKwData] = useState<Record<string, FamilyKeywords> | null>(null);
  const [kwLoading, setKwLoading] = useState(false);
  const [pendingCell, setPendingCell] = useState<string | null>(null); // cell_key of in-flight suppress toggle
  const [monthsData, setMonthsData] = useState<Record<string, MonthRow[]> | null>(null);
  const [monthsLoading, setMonthsLoading] = useState(false);
  const [openCampaigns, setOpenCampaigns] = useState<Set<string>>(new Set()); // expanded campaign_ids

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

  function ensureMonths() {
    if (monthsData !== null || monthsLoading) return;
    setMonthsLoading(true);
    apiFetch('/api/campaign-months')
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(json => setMonthsData(json.months ?? {}))
      .catch(() => setMonthsData({}))
      .finally(() => setMonthsLoading(false));
  }

  function toggleCampaign(id: string) {
    setOpenCampaigns(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  useEffect(() => {
    apiFetch('/api/daily-workflow')
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(d => (d.error ? setErr(d.error) : setData(d)))
      .catch(e => setErr(String(e)));
  }, []);

  if (err) return <div className="p-6 text-sm text-red-400">Coverage scan failed: {err}</div>;
  if (!data) return <div className="p-6 text-sm text-muted">Scanning ad coverage…</div>;

  const familyMatch = (c: Cell): boolean => {
    if (selectedFamily === null) return true; // ALL
    if (selectedFamily === STORE_KEY) return c.parent_name === null;
    return c.parent_name === selectedFamily;
  };
  const openGroups = open ? groupByFamily(data.cells.filter(c => c.strategy === open && familyMatch(c))) : [];
  const openCellCount = openGroups.reduce((n, g) => n + g.cells.length, 0);
  const familyEntries = buildFamilyEntries(data.family_stats);

  return (
    <div className="p-4">
      <div className="flex items-center gap-3 mb-4">
        <h1 className="text-lg font-bold text-heading">🗂️ Daily Workflow — Coverage</h1>
        <span className="text-[11px] text-muted">green = everything defined · click a strategy to see the mapping</span>
      </div>

      <div className="flex flex-col md:flex-row gap-3">
        <div className="flex w-full shrink-0 flex-col gap-2 md:w-[170px] md:min-w-[170px]">
          {familyEntries.map(entry => (
            <FamilyButton
              key={entry.key}
              entry={entry}
              selected={entry.key === 'ALL' ? selectedFamily === null : selectedFamily === entry.key}
              onSelect={() => setSelectedFamily(entry.key === 'ALL' ? null : entry.key)}
            />
          ))}
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap gap-2 mb-2">
            {data.strategies.map(s => (
              <StrategyTile
                key={s}
                name={s}
                t={data.tiles[s] ?? { defined: 0, missing: 0, redundant: 0, informational: 0, suppressed: 0 }}
                stat={data.strategy_stats?.[s]}
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
                              if (c.strategy === 'INTENT' || c.strategy === 'EXACT_BOOST' || c.strategy === 'BRAND_DEFENSE') ensureKeywords();
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
                                <CampaignEvidenceRow
                                  key={`${cmp.campaign_name}-${j}`}
                                  c={cmp}
                                  months={monthsData?.[cmp.campaign_id]}
                                  monthsLoading={monthsLoading}
                                  isOpen={openCampaigns.has(cmp.campaign_id)}
                                  onToggle={() => { toggleCampaign(cmp.campaign_id); ensureMonths(); }}
                                />
                              ))
                            ) : (
                              <div className="text-faint text-[10px]">no campaigns</div>
                            )}
                            {(c.strategy === 'INTENT' || c.strategy === 'EXACT_BOOST') && (
                              <KeywordPanel family={c.parent_name} data={kwData} loading={kwLoading} mode="intent" />
                            )}
                            {c.strategy === 'BRAND_DEFENSE' && (
                              <KeywordPanel family={c.parent_name} data={kwData} loading={kwLoading} mode="brand" />
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
      </div>
    </div>
  );
}
