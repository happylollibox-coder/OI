import { useEffect, useState } from 'react';
import { apiFetch } from '../utils/apiFetch';
import { useDoQueue } from '../hooks/useDoQueue';
import { fShort, fR } from '../utils';

interface Tile {
  defined: number;
  missing: number;
  redundant: number;
  informational: number;
  suppressed: number;
}
interface Cell {
  grain: 'ASIN' | 'FAMILY' | 'STORE' | 'CAMPAIGN';
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
  // Campaigns that are ENABLED in Amazon but haven't served in 30d. They have no in-window
  // impressions so they'd otherwise vanish, making a configured cell look 'missing'.
  n_dark?: number;
  dark_campaigns?: string | null;
  is_archived?: boolean;   // UNMAPPED cells only — historical spend, never a to-do
  state?: string | null;
  suppressed: boolean;
  status: 'ok' | 'missing' | 'redundant' | 'none' | 'suppressed' | 'unmapped' | 'dark';
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
  net_profit: number | null;
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
  // NULLABLE: both come from SAFE_DIVIDE over cost, so a month with no spend returns NULL —
  // which is now common, since brand-new campaigns appear with zero metrics (Ori 2026-07-24).
  // Typed non-null before, so `net_roas.toFixed()` compiled fine and crashed at runtime.
  net_profit: number | null;
  net_roas: number | null;
}
/** One keyword within a (campaign × month) — the third evidence level under a MonthRow. */
export interface MonthKw {
  keyword_text: string;
  match_type: string;
  impressions: number;
  clicks: number;
  spend: number;
  cpc: number | null;
  units: number;
  net_profit: number;
  net_roas: number | null;
  target_cpc: number | null;   // CPC that hits the INTENT floor at THIS month's cvr
}
/** Threaded bundle for the per-month keyword drill: cache (campaign_id → month → keywords),
 *  a per-campaign loading probe, the expanded `${campaign_id}|${month}` set, + handlers. */
interface MonthKwCtx {
  data: Record<string, Record<string, MonthKw[]>>;
  loading: (campaignId: string) => boolean;
  expanded: Set<string>;
  toggle: (key: string) => void;
  ensure: (campaignId: string) => void;
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
  strategy_family_stats?: Record<string, StrategyStat>;  // '<strategy>|<family>'
  family_stats?: Record<string, FamilyStat>;
  window?: string;        // echoed back by /api/daily-workflow (today|yesterday|7d|30d|90d|12mo|peak)
  window_start?: string;  // resolved YYYY-MM-DD (inclusive)
  window_end?: string;    // resolved YYYY-MM-DD (inclusive)
}

const STORE_KEY = '__STORE__';

// Time-window choices for the whole cockpit — mirrors the /api/daily-workflow WINDOWS map.
// Every measure on the page (coverage counts, status, metrics) is computed over the chosen window.
type CovWindow = 'today' | 'yesterday' | '7d' | '30d' | '90d' | '12mo' | 'peak';
const COV_WINDOWS: { key: CovWindow; label: string; short: string; hint: string }[] = [
  { key: 'today',     label: 'Today',     short: 'today', hint: 'ads so far today' },
  { key: 'yesterday', label: 'Yesterday', short: 'yest',  hint: 'the full prior day' },
  { key: '7d',        label: '7 days',    short: '7d',    hint: 'trailing 7 days (default)' },
  { key: '30d',       label: '30 days',   short: '30d',   hint: 'trailing 30 days' },
  { key: '90d',       label: '90 days',   short: '90d',   hint: 'trailing 90 days' },
  { key: '12mo',      label: '12 months', short: '12mo',  hint: 'trailing 12 months' },
  { key: 'peak',      label: 'Peak',      short: 'peak',  hint: 'gift-season days only, over the last 12 months' },
];
const winShort = (w: CovWindow): string => COV_WINDOWS.find(x => x.key === w)?.short ?? String(w);
const COV_WIN_KEY = 'coverage_window';
const recallWin = (): CovWindow => {
  try {
    const v = localStorage.getItem(COV_WIN_KEY) as CovWindow | null;
    return v && COV_WINDOWS.some(w => w.key === v) ? v : '7d';
  } catch { return '7d'; }
};

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
  ads_net_roas: number | null;   // intent-level aggregate (NOT per-keyword)
  net_roas: number | null;       // REAL per-keyword net ROAS (units_7d × family_gp / cost)
  target_cpc: number | null;     // CPC that lands this keyword on the INTENT net-ROAS floor
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
  intents?: Record<string, { suggested: boolean; wtd_net_roas: number | null; spend: number; label: string }>;
}

/** One month in a keyword's 12-month drill (raw shape from /api/keyword-months). */
export interface KwMonthRow {
  month: string;
  clicks: number;
  spend: number;
  units: number;
  impressions: number;
}

/** Threaded bundle for per-keyword month drill: cache (keyed by family → keyword_key),
 *  a per-family loading probe, the expanded keyword_key set, and toggle/ensure handlers. */
interface KwMonthsCtx {
  data: Record<string, Record<string, KwMonthRow[]>> | null;
  loading: (family: string) => boolean;
  expanded: Set<string>;
  toggle: (key: string) => void;
  ensure: (family: string) => void;
}

const STRAT_LABEL: Record<string, string> = {
  AUTO: 'Auto',
  BROAD_SP: 'Broad SP',
  BROAD_VIDEO: 'Broad Video',
  BROAD_SPOTLIGHT: 'Broad Spotlight',
  PHRASE: 'Phrase',
  EXACT: 'Exact',
  COMPETITOR: 'Competitor',
  BRAND_DEFENSE: 'Brand Defense',
  PRODUCT_DEFENSE: 'Product Defense',
  UNMAPPED: 'Unmapped',
};

/** Pull the campaign_id out of an UNMAPPED cell_key ('UNMAPPED|<campaign_id>'). */
// eslint-disable-next-line react-refresh/only-export-components
export function parseCampaignId(cellKey: string): string {
  return cellKey.split('|')[1] ?? '';
}

/** One campaign in the mapping modal (from GET /api/admin/campaign-mapping). */
interface MappingCampaign {
  campaign_id: string;
  campaign_name: string;
  spend_60d: number;
  current_experiment_id: string | null;
  current_experiment_name: string | null;
  current_strategy_id: string | null;
  suggested_family: string | null;
  suggested_strategy: string | null;
  suggested_experiment_id: string | null;
  confidence: number | null;
  source: string | null;
}
interface MappingData {
  campaigns: MappingCampaign[];
  families: string[];
  strategies: string[];
}

/** Current-strategy indicator for a campaign row: amber "unmapped" when null,
 *  else a faint pill with the human label (STRAT_LABEL; unknown ids shown raw). */
export function CurrentStrategyPill({ id }: { id: string | null }) {
  if (id == null) {
    return <span className="shrink-0 rounded px-1.5 py-px text-[10px] font-semibold bg-amber-500/15 text-amber-400">unmapped</span>;
  }
  return (
    <span className="shrink-0 rounded px-1.5 py-px text-[10px] font-semibold bg-white/[0.05] text-faint">
      {STRAT_LABEL[id] ?? id}
    </span>
  );
}

/** One campaign row in the mapping modal: name + 60d spend + current-strategy pill,
 *  then family/strategy selects + Save. Local select state defaults from the
 *  current mapping (strategy) and the backend suggestion (family/strategy fallback). */
function MappingRow({ c, families, strategies, pending, onSave }: {
  c: MappingCampaign;
  families: string[];
  strategies: string[];
  pending: boolean;
  onSave: (family: string, strategy: string) => void;
}) {
  const initFamily = c.suggested_family && families.includes(c.suggested_family) ? c.suggested_family : '';
  const initStrategy =
    c.current_strategy_id && strategies.includes(c.current_strategy_id)
      ? c.current_strategy_id
      : c.suggested_strategy && strategies.includes(c.suggested_strategy)
        ? c.suggested_strategy
        : '';
  const [family, setFamily] = useState(initFamily);
  const [strategy, setStrategy] = useState(initStrategy);
  // Snapshot the initial defaults once (lazy initializer, evaluated on mount only)
  // so "changed?" is measured against mount-time values, not the live edits.
  // A row left at its defaults keeps Save disabled.
  const [initial] = useState(() => ({ family: initFamily, strategy: initStrategy }));
  const changed = family !== initial.family || strategy !== initial.strategy;
  const canSave = changed && !!family && !!strategy && !pending;
  const selCls = 'text-[10px] bg-surface border border-border-faint rounded px-1.5 py-1 text-muted';
  return (
    <div className="flex items-center gap-2 border-b border-border-faint py-1.5 last:border-0">
      <span className="min-w-0 flex-1 truncate text-[11px] text-heading" title={c.campaign_name}>{c.campaign_name}</span>
      <span className="shrink-0 text-[10px] tabular-nums text-faint">${c.spend_60d.toFixed(0)}</span>
      <CurrentStrategyPill id={c.current_strategy_id} />
      <select value={family} onChange={e => setFamily(e.target.value)} className={selCls} title="Family">
        <option value="">family…</option>
        {families.map(f => <option key={f} value={f}>{f}</option>)}
      </select>
      <select value={strategy} onChange={e => setStrategy(e.target.value)} className={selCls} title="Strategy">
        <option value="">strategy…</option>
        {strategies.map(s => <option key={s} value={s}>{STRAT_LABEL[s] ?? s}</option>)}
      </select>
      <button
        onClick={() => onSave(family, strategy)}
        disabled={!canSave}
        className="shrink-0 rounded border border-border-faint px-2 py-1 text-[10px] text-muted hover:text-heading disabled:opacity-40"
        title="Assign this campaign to a strategy"
      >
        {pending ? '…' : 'Save'}
      </button>
    </div>
  );
}

function StatusPill({ c }: { c: Cell }) {
  const map: Record<Cell['status'], { tone: string; label: string }> = {
    ok: { tone: 'text-emerald-400', label: '✓ defined' },
    missing: { tone: 'text-red-400', label: '✗ to do' },
    redundant: { tone: 'text-amber-400', label: `⚠ ${c.n_enabled} campaigns` },
    none: { tone: 'text-faint', label: '– not running' },
    suppressed: { tone: 'text-subtle', label: '⊘ not expected' },
    unmapped: { tone: 'text-amber-400', label: c.is_archived ? '⊙ archived' : '⊙ unmapped' },
    // Configured but not delivering — deliberately NOT 'to do': the campaign exists, so the fix
    // is budget/bid/eligibility (or archive it), never building a duplicate.
    dark: { tone: 'text-amber-400', label: '◐ not delivering' },
  };
  const { tone, label } = map[c.status];
  return (
    <span className={`${tone} font-semibold text-[10px]`}>
      {label}
      {/* Live cell that ALSO has dark campaigns hanging off it — surfaced so they don't stay invisible. */}
      {c.status !== 'dark' && (c.n_dark ?? 0) > 0 && (
        <span className="ml-1 text-amber-400/80 font-normal"
          title={`Enabled but not delivering (no impressions in 30d): ${c.dark_campaigns ?? ''}`}>
          · ◐ {c.n_dark} dark
        </span>
      )}
    </span>
  );
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

/** Colour a net-ROAS number to AGREE with its ProfitChip. Both key on profit_state, which the
 *  backend computes against the STRATEGY's own floor (BRAND_DEFENSE = 3.0, DE_COACH_THRESHOLDS),
 *  not a flat 1.0 — so a 2.31x brand-defense cell no longer prints green beside a red "loss". */
function roasTone(state: string): string {
  return state === 'profitable' ? 'text-emerald-400'
    : state === 'unprofitable' ? 'text-red-400'
    : 'text-muted';
}

/** Compact windowed P&L roll-up: "{win}: {profitable}/{total} profit · +$X · −$Y".
 *  Emerald net-profit and red net-loss are each omitted when 0; empty spend → "no spend ({win})".
 *  `win` is the active time-window's short label (7d/30d/90d/12mo/peak/today/yest). */
export function ProfitRollup({ s, win = '7d' }: { s: StrategyStat; win?: string }) {
  if (!s.total) return <div className="mt-0.5 text-[9px] text-faint">no spend ({win})</div>;
  const gain = Math.round(s.net_profit_profitable);
  const loss = Math.round(Math.abs(s.net_profit_unprofitable));
  return (
    <div className="mt-0.5 text-[9px] tabular-nums text-muted">
      <span className="text-faint">{win}: </span>
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
        {c.net_roas != null && <span className={roasTone(c.profit_state)}>{fR(c.net_roas)}</span>}
        {' · '}{fShort(c.clicks)} clk · {fShort(c.impressions)} imp · {c.units}u
        {c.cpc != null && ` · $${c.cpc.toFixed(2)} cpc`}
      </span>
      <ProfitChip state={c.profit_state} />
    </span>
  );
}

/** Strategy roll-up tile — defined / to-do / redundant across a strategy's coverage cells.
 *  Border tone: red if anything to do, else amber if redundant, else emerald. */
export function StrategyTile({ name, t, stat, open, onOpen, win }: { name: string; t: Tile; stat?: StrategyStat; open: boolean; onOpen: () => void; win?: string }) {
  const isUnmapped = name === 'UNMAPPED';
  const tone = isUnmapped
    ? (t.informational > 0
        ? 'border-amber-500/40 bg-amber-500/10 hover:bg-amber-500/20'
        : 'border-emerald-500/50 bg-emerald-500/10 hover:bg-emerald-500/20')
    : t.missing > 0
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
        {isUnmapped ? (
          t.informational > 0
            ? <span className="text-amber-400">{t.informational} unmapped</span>
            : <span className="text-faint">none unmapped</span>
        ) : (
          <>
            <span className="text-emerald-400">✓ {t.defined} defined</span>
            {t.missing > 0 && <><span className="text-faint"> · </span><span className="text-red-400">✗ {t.missing} to do</span></>}
            {t.redundant > 0 && <><span className="text-faint"> · </span><span className="text-amber-400">⚠ {t.redundant} redundant</span></>}
            {t.informational > 0 && <><span className="text-faint"> · </span><span className="text-faint">{t.informational} idle</span></>}
          </>
        )}
      </div>
      <ProfitRollup s={stat ?? ZERO_STAT} win={win} />
    </button>
  );
}

/** Small top-right header button that opens the campaign-mapping modal.
 *  Amber toned with a count badge when unmapped>0, else neutral. */
function ConfigureButton({ count, onClick }: { count: number; onClick: () => void }) {
  const active = count > 0;
  const tone = active
    ? 'border-amber-500/40 bg-amber-500/10 hover:bg-amber-500/20 text-amber-400'
    : 'border-border-faint bg-surface hover:bg-white/[0.04] text-muted';
  return (
    <button
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-xs transition ${tone}`}
      title="Configure campaign → strategy mapping"
    >
      <span className="leading-none">⚙</span>
      <span className="font-semibold">Configure</span>
      {active
        ? <span className="rounded-full bg-amber-500/20 px-1.5 py-px text-[9px] font-bold tabular-nums text-amber-400">{count}</span>
        : <span className="text-[9px] text-faint tabular-nums">0</span>}
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

/** One keyword within a month drill: match chip + text, then right-aligned metrics
 *  mirroring the month line (spend · clicks · cpc · units · roas · ±profit). */
export function MonthKeywordRow({ k }: { k: MonthKw }) {
  const roas = k.net_roas ?? 0;
  const roasTone = roas >= 1 ? 'text-emerald-400' : 'text-red-400';
  const profTone = k.net_profit >= 0 ? 'text-emerald-400' : 'text-red-400';
  const prof = k.net_profit >= 0
    ? `+$${Math.round(k.net_profit)}`
    : `−$${Math.round(Math.abs(k.net_profit))}`;
  return (
    <div className="flex items-center gap-1 py-px text-[9px] tabular-nums text-faint">
      <MatchChip mt={k.match_type} />
      <span className="truncate max-w-[150px] text-muted" title={k.keyword_text}>{k.keyword_text}</span>
      <span className="ml-auto whitespace-nowrap">${k.spend.toFixed(0)} · {k.clicks} clk · ${(k.cpc ?? (k.clicks > 0 ? k.spend / k.clicks : 0)).toFixed(2)} cpc · {k.units}u ·</span>
      <span className={roasTone}>{roas.toFixed(2)}x</span>
      <span>·</span>
      <span className={profTone}>{prof}</span>
      <span>·</span>
      <span className="text-muted" title="conversion rate = units ÷ clicks">{k.clicks > 0 ? (100 * k.units / k.clicks).toFixed(1) : '0.0'}% cvr</span>
      {k.target_cpc != null && (
        <>
          <span>·</span>
          <span
            className={k.cpc != null && k.cpc > k.target_cpc ? 'text-amber-400' : 'text-emerald-400'}
            title={k.cpc != null && k.cpc > k.target_cpc
              ? `Lower bid to ~$${k.target_cpc.toFixed(2)} to reach 1.1x net ROAS at this month's cvr`
              : `Room to bid up to ~$${k.target_cpc.toFixed(2)} at this month's cvr`}
          >tgt ${k.target_cpc.toFixed(2)}</span>
        </>
      )}
    </div>
  );
}

/** One month in a campaign's 12-month drill: "{YYYY-MM} · ${spend} · {clicks} clk · ${cpc} cpc · {units}u · {roas}x · ±$profit".
 *  When `campaignId` + `kwCtx` are supplied the row becomes expandable → the keywords that drove that month. */
export function MonthRow({ m, campaignId, kwCtx }: { m: MonthRow; campaignId?: string; kwCtx?: MonthKwCtx }) {
  // A month with no spend has no ROAS and no profit — render '—' rather than a fake 0.00x.
  const roasTone = m.net_roas == null ? 'text-faint' : m.net_roas >= 1 ? 'text-emerald-400' : 'text-red-400';
  const profTone = m.net_profit == null ? 'text-faint' : m.net_profit >= 0 ? 'text-emerald-400' : 'text-red-400';
  const prof = m.net_profit == null
    ? '—'
    : m.net_profit >= 0
      ? `+$${Math.round(m.net_profit)}`
      : `−$${Math.round(Math.abs(m.net_profit))}`;
  const canExpand = !!campaignId && !!kwCtx;
  const mkey = `${campaignId}|${m.month}`;
  const isOpen = kwCtx?.expanded.has(mkey) ?? false;
  const kws = campaignId && kwCtx ? kwCtx.data[campaignId]?.[m.month] : undefined;
  const sorted = kws ? [...kws].sort((a, b) => b.spend - a.spend) : undefined;
  const isLoading = campaignId && kwCtx ? kwCtx.loading(campaignId) : false;
  const line = (
    <div className="flex items-center gap-1 py-px text-[9px] tabular-nums text-faint">
      {canExpand && <span className="w-2 shrink-0 text-faint">{isOpen ? '▾' : '▸'}</span>}
      <span className="w-[42px] shrink-0 text-muted">{m.month.slice(0, 7)}</span>
      <span className="whitespace-nowrap">· ${(m.spend ?? 0).toFixed(0)} · {m.clicks ?? 0} clk · ${(m.clicks > 0 ? (m.spend ?? 0) / m.clicks : 0).toFixed(2)} cpc · {m.units ?? 0}u ·</span>
      <span className={roasTone}>{m.net_roas == null ? '—' : `${m.net_roas.toFixed(2)}x`}</span>
      <span>·</span>
      <span className={profTone}>{prof}</span>
      <span>·</span>
      <span className="text-muted" title="conversion rate = units ÷ clicks">{m.clicks > 0 ? (100 * m.units / m.clicks).toFixed(1) : '0.0'}% cvr</span>
    </div>
  );
  if (!canExpand) return line;
  return (
    <div>
      <button
        onClick={() => { kwCtx!.ensure(campaignId!); kwCtx!.toggle(mkey); }}
        className="block w-full text-left hover:bg-white/[0.02]"
      >
        {line}
      </button>
      {isOpen && (
        <div className="pl-4">
          {sorted && sorted.length > 0 ? (
            sorted.map((k, i) => <MonthKeywordRow key={`${k.match_type}-${k.keyword_text}-${i}`} k={k} />)
          ) : isLoading ? (
            <div className="text-faint text-[9px]">loading…</div>
          ) : (
            <div className="text-faint text-[9px]">no keyword data</div>
          )}
        </div>
      )}
    </div>
  );
}

interface ConfiguredTarget { targeting: string; match_type: string; state: string; bid: number | null; }

/** What a campaign is CONFIGURED to target, for campaigns with no performance yet.
 *  Every other drill is performance-derived, so a campaign created today drilled to "no monthly
 *  data" and you could not confirm what it targets (Ori 2026-07-24). Reads the Amazon config
 *  mirror via /api/campaign-targets — keywords AND product targets, with live bid + state. */
function ConfiguredTargets({ campaignId }: { campaignId: string }) {
  const [rows, setRows] = useState<ConfiguredTarget[] | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await apiFetch(`/api/campaign-targets?campaign_id=${encodeURIComponent(campaignId)}`);
        const j = await res.json() as { targets?: ConfiguredTarget[] };
        if (!cancelled) setRows(j.targets || []);
      } catch { if (!cancelled) setFailed(true); }
    })();
    return () => { cancelled = true; };
  }, [campaignId]);

  if (failed) return <div className="text-faint text-[9px]">no monthly data</div>;
  if (rows === null) return <div className="text-faint text-[9px]">loading targets…</div>;
  if (rows.length === 0) return <div className="text-faint text-[9px]">no monthly data · no targets configured</div>;
  return (
    <div>
      <div className="py-0.5 text-[9px] text-faint">
        Not delivering yet — showing the {rows.length} target{rows.length === 1 ? '' : 's'} it is configured to run:
      </div>
      {rows.map((t, i) => (
        <div key={`${t.targeting}-${i}`} className="flex items-center gap-1.5 py-px text-[9px] tabular-nums text-faint">
          <MatchChip mt={t.match_type} />
          {/* strip Amazon's asin="…" wrapper for display, same as the Do queue */}
          <span className="truncate text-[10px] text-muted" title={t.targeting}>
            {t.targeting.replace(/^(asin|asin-expanded|category)="?|"?$/gi, '')}
          </span>
          <span className="ml-auto whitespace-nowrap">
            {t.state !== 'ENABLED' && <span className="text-amber-400">{t.state.toLowerCase()} · </span>}
            {t.bid != null ? `bid $${t.bid.toFixed(2)}` : 'no bid'}
          </span>
        </div>
      ))}
    </div>
  );
}

/** One campaign in a cell's evidence list: expander chevron · state badge · name · right-aligned
 *  metrics. Expands to reveal a lazy-loaded 12-month P&L drill (most-recent month first). */
export function CampaignEvidenceRow({
  c, months, monthsLoading = false, isOpen = false, onToggle, monthKwCtx,
}: {
  c: DetailCampaign;
  months?: MonthRow[];
  monthsLoading?: boolean;
  isOpen?: boolean;
  onToggle?: () => void;
  monthKwCtx?: MonthKwCtx;
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
              <span className={roasTone(c.profit_state)}>{fR(c.net_roas)}</span>
            )}
            {c.net_roas != null && ' · '}{fShort(c.clicks)} clk · {c.units}u · ${c.ad_spend.toFixed(0)} s
            {c.cpc != null && ` · $${c.cpc.toFixed(2)} cpc`}
            {c.net_profit != null && c.ad_spend > 0 && (
              <>
                {' · '}
                <span className={c.net_profit > 0 ? 'text-emerald-400' : 'text-red-400'}>
                  {c.net_profit > 0 ? '+' : '−'}${Math.abs(c.net_profit).toFixed(0)} np
                </span>
              </>
            )}
          </span>
          <ProfitChip state={c.profit_state} />
        </span>
      </button>
      {isOpen && (
        <div className="pl-4 pb-1">
          {monthsLoading && !recentFirst ? (
            <div className="text-faint text-[9px]">loading…</div>
          ) : recentFirst && recentFirst.length > 0 ? (
            recentFirst.map((m, i) => <MonthRow key={`${m.month}-${i}`} m={m} campaignId={c.campaign_id} kwCtx={monthKwCtx} />)
          ) : (
            /* No performance yet (a campaign created today) → show what it is CONFIGURED to
               target, so the drill still answers "what is in this campaign?". */
            <ConfiguredTargets campaignId={c.campaign_id} />
          )}
        </div>
      )}
    </div>
  );
}

/** One month in a keyword's 12-month drill: "{YYYY-MM} · ${spend} · {clicks} clk · ${cpc} cpc · {units}u". */
export function KwMonthRow({ m }: { m: KwMonthRow }) {
  return (
    <div className="flex items-center gap-1 py-px text-[9px] tabular-nums text-faint">
      <span className="w-[42px] shrink-0 text-muted">{m.month.slice(0, 7)}</span>
      <span className="whitespace-nowrap">· ${m.spend.toFixed(0)} · {m.clicks} clk · ${(m.clicks > 0 ? m.spend / m.clicks : 0).toFixed(2)} cpc · {m.units}u</span>
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

/** One keyword in a family's coverage list: expander chevron + match chip + text, right-aligned
 *  status-appropriate metrics. Expands to a lazy-loaded 12-month drill (most-recent month first).
 *  When no `months` ctx is supplied it renders inert (chevron shown, click is a no-op). */
export function KeywordRow({ k, family, months }: { k: KeywordRowData; family?: string | null; months?: KwMonthsCtx }) {
  const showPerf = k.status === 'running' || k.status === 'orphan' || k.status === 'paused';
  const kwKey = `${k.match_type}|${k.keyword_text}`;
  const fam = family ?? undefined;
  const isOpen = months?.expanded.has(kwKey) ?? false;
  const monthRows = fam && months?.data ? months.data[fam]?.[kwKey] : undefined;
  const isLoading = fam && months ? months.loading(fam) : false;
  const recentFirst = monthRows ? [...monthRows].sort((a, b) => b.month.localeCompare(a.month)) : undefined;
  return (
    <div className="border-b border-border-faint last:border-0">
      <button
        onClick={() => { if (fam) months?.ensure(fam); months?.toggle(kwKey); }}
        className="flex w-full items-center gap-1.5 py-0.5 text-left hover:bg-white/[0.02]"
      >
        <span className="w-2 shrink-0 text-[9px] text-faint">{isOpen ? '▾' : '▸'}</span>
        <MatchChip mt={k.match_type} />
        <span className="truncate text-[11px] text-muted" title={k.keyword_text}>{k.keyword_text}</span>
        <span className="ml-auto inline-flex shrink-0 items-center gap-1 text-[10px] tabular-nums text-faint">
          {k.status === 'running' && (
            <span>
              ${k.cost.toFixed(0)} spend · {k.clicks} clk
              {k.research_rank != null && ` · rank ${k.research_rank}`}
              {k.cpc != null && ` · $${k.cpc.toFixed(2)} cpc`}
              {k.net_roas != null && (
                <>
                  {' · '}
                  <span className={k.net_roas >= 1 ? 'text-emerald-400' : 'text-red-400'}>{k.net_roas.toFixed(2)}x</span>
                </>
              )}
              {k.target_cpc != null && (
                <>
                  {' · '}
                  <span
                    className={k.cpc != null && k.cpc > k.target_cpc ? 'text-amber-400' : 'text-emerald-400'}
                    title={k.cpc != null && k.cpc > k.target_cpc
                      ? `Lower bid to ~$${k.target_cpc.toFixed(2)} to reach 1.1x net ROAS`
                      : `Room to bid up to ~$${k.target_cpc.toFixed(2)} at 1.1x net ROAS`}
                  >tgt ${k.target_cpc.toFixed(2)}</span>
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
      </button>
      {isOpen && (
        <div className="pl-4 pb-1">
          {recentFirst && recentFirst.length > 0 ? (
            recentFirst.map((m, i) => <KwMonthRow key={`${m.month}-${i}`} m={m} />)
          ) : isLoading ? (
            <div className="text-faint text-[9px]">loading…</div>
          ) : (
            <div className="text-faint text-[9px]">no monthly data</div>
          )}
        </div>
      )}
    </div>
  );
}

interface CompTarget {
  target: string; target_type: string; clicks: number; cost: number;
  cpc: number | null; units: number; net_roas: number | null; target_cpc: number | null; is_winner: boolean;
}
interface CompCandidate {
  candidate_asin: string; found_in: string; clicks: number; cost: number;
  cpc: number | null; units: number; net_roas: number | null; target_cpc: number | null;
}
interface CompFamily { targets: CompTarget[]; candidates: CompCandidate[]; }

/** One ASIN row — shared by current targets and promotion candidates. */
function CompRow({ asin, sub, clicks, cost, cpc, units, netRoas, targetCpc }: {
  asin: string; sub?: string; clicks: number; cost: number;
  cpc: number | null; units: number; netRoas: number | null; targetCpc: number | null;
}) {
  const roas = netRoas ?? 0;
  return (
    <div className="flex items-center gap-1.5 border-b border-border-faint py-0.5 last:border-0 text-[10px] tabular-nums text-faint">
      <span className="shrink-0 rounded bg-white/[0.05] px-1 py-px text-[9px] font-semibold text-muted">ASIN</span>
      <span className="truncate text-[11px] text-muted" title={asin}>{asin}</span>
      {sub && <span className="shrink-0 text-[9px] text-faint">via {sub}</span>}
      <span className="ml-auto whitespace-nowrap">
        ${Math.round(cost)} · {clicks} clk · ${(cpc ?? 0).toFixed(2)} cpc · {units}u ·{' '}
        <span className={roas >= 1 ? 'text-emerald-400' : 'text-red-400'}>{roas.toFixed(2)}x</span>
      </span>
      {targetCpc != null && (
        <span
          className={cpc != null && cpc > targetCpc ? 'text-amber-400' : 'text-emerald-400'}
          title={cpc != null && cpc > targetCpc
            ? `Lower bid to ~$${targetCpc.toFixed(2)} to reach the profit floor`
            : `Room to bid up to ~$${targetCpc.toFixed(2)}`}
        >tgt ${targetCpc.toFixed(2)}</span>
      )}
    </div>
  );
}

/** Competitor cells target PRODUCTS, so they get ASIN evidence instead of the keyword panel:
 *  what you target now, plus ASINs Auto discovered profitably that you don't target yet. */
export function CompetitorPanel({ family, data, loading }: {
  family: string | null; data: Record<string, CompFamily> | null; loading: boolean;
}) {
  const f = family ? data?.[family] : undefined;
  if (loading && !data) return <div className="mt-2 text-[10px] text-faint">loading competitor targets…</div>;
  if (!f || (f.targets.length === 0 && f.candidates.length === 0)) {
    return <div className="mt-2 text-[10px] text-faint">No competitor ASIN targets in this window.</div>;
  }
  const winners = f.targets.filter(t => t.is_winner).length;
  return (
    <div className="mt-2 rounded border border-border-faint bg-surface/40 p-2">
      <div className="mb-1.5 flex items-center gap-2">
        <span className="text-[11px] font-semibold text-heading">Competitor ASINs</span>
        <span className="text-[10px] tabular-nums">
          <span className="text-muted">{f.targets.length} targeted</span>
          <span className="text-faint"> · </span>
          <span className={winners > 0 ? 'text-emerald-400' : 'text-red-400'}>{winners} profitable</span>
          {f.candidates.length > 0 && (
            <><span className="text-faint"> · </span>
              <span className="text-amber-400">{f.candidates.length} to promote</span></>
          )}
        </span>
      </div>
      {f.targets.length > 0 && (
        <>
          <div className="mb-0.5 mt-1 text-[10px] font-semibold text-faint">🎯 Targeted now</div>
          {f.targets.map((t, i) => (
            <CompRow key={`${t.target}-${i}`} asin={t.target} clicks={t.clicks} cost={t.cost}
              cpc={t.cpc} units={t.units} netRoas={t.net_roas} targetCpc={t.target_cpc} />
          ))}
        </>
      )}
      {f.candidates.length > 0 && (
        <>
          <div className="mb-0.5 mt-2 text-[10px] font-semibold text-amber-400">
            ✨ Discovered by Auto — worth promoting
          </div>
          {f.candidates.map((c, i) => (
            <CompRow key={`${c.candidate_asin}-${i}`} asin={c.candidate_asin} sub={c.found_in}
              clicks={c.clicks} cost={c.cost} cpc={c.cpc} units={c.units}
              netRoas={c.net_roas} targetCpc={c.target_cpc} />
          ))}
          <div className="mt-1 text-[9px] italic text-faint">
            Proven on {'>'}=10 clicks only — a promotion shortlist, not certainty. Start nearer the
            current CPC than the target.
          </div>
        </>
      )}
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
 * Competitor CAMPAIGN PLAN — the write side of the ASIN evidence above.
 * Pure presentation: every number, name, band and bid is decided by
 * FN_COMPETITOR_CAMPAIGN_PLAN and nested by /api/competitor-campaign-plan.
 * This renders variation → tier → campaign → ASINs and queues bulksheet rows.
 * ───────────────────────────────────────────────────────────────────────────── */

interface PlanAsin {
  candidate_asin: string; found_in: string; clicks: number; cost: number;
  cpc: number | null; units: number; net_roas: number | null; target_cpc: number | null;
  asin_rank: number;
}
interface PlanCampaign {
  campaign_key: string; campaign_name: string; sb_campaign_name: string; ad_group_name: string;
  group_code: string; chunk_index: number; n_asins: number;
  suggested_bid: number; suggested_bid_sb: number; suggested_bid_raw: number; bid_capped: boolean;
  group_med_target_cpc: number; group_avg_target_cpc: number; group_max_target_cpc: number;
  daily_budget: number | null; product_page_pct: number | null; daily_budget_sb: number | null;
  group_clicks: number; group_window_cost: number; group_units: number;
  proj_spend: number; proj_margin: number; proj_net_roas: number | null;
  asins: PlanAsin[];
}
interface PlanTier { tier_code: string; tier_label: string; tier_sort: number; campaigns: PlanCampaign[]; }
interface PlanVariation { variation: string; variation_label: string; winner_asin: string; tiers: PlanTier[]; }
interface PlanFamily { variations: PlanVariation[]; }

/** One planned campaign: collapsed summary row, expands to its ASIN list. */
function PlanCampaignRow({ camp, variation, winnerAsin, family }: {
  camp: PlanCampaign; variation: string; winnerAsin: string; family: string;
}) {
  const [open, setOpen] = useState(false);
  const { addItem, hasItem } = useDoQueue();
  // Queued when every ASIN of the group is already in the queue for this campaign.
  const queued = camp.asins.every(a => hasItem('', 'ADD_COMPETITOR_TARGET', camp.campaign_name, `asin="${a.candidate_asin}"`));
  // The SB VIDEO variant is a SEPARATE campaign (sb_campaign_name), queued independently — a family
  // can run the SP conquest, the video conquest, or both. Deduped on the SB name + action.
  const queuedSb = camp.asins.every(a => hasItem('', 'ADD_COMPETITOR_TARGET_SB', camp.sb_campaign_name, `asin="${a.candidate_asin}"`));

  // channel = 'SP' → product-target campaign; 'SB' → video campaign on the same targets.
  const queueChannel = (channel: 'SP' | 'SB') => {
    const isSB = channel === 'SB';
    for (const a of camp.asins) {
      addItem({
        search_term: '',
        action: isSB ? 'ADD_COMPETITOR_TARGET_SB' : 'ADD_COMPETITOR_TARGET',
        // The campaign does not exist yet, so its NAME is its handle all the way through the
        // bulksheet (Amazon resolves Create rows by the name placed in Campaign ID) — the same
        // trick the cross-sell / EXACT-boost create paths use.
        campaign: isSB ? camp.sb_campaign_name : camp.campaign_name,
        campaign_id: '',
        ad_group_id: '',
        ad_group_name: camp.ad_group_name,
        targeting: `asin="${a.candidate_asin}"`,
        keyword_id: '',
        match_type: 'PRODUCT_TARGETING',
        campaign_type: isSB ? 'SB' : 'SP',
        product: variation,
        asin: winnerAsin,          // the variation we advertise ON the competitor's page
        target_spend_8w: 0, target_orders_8w: 0, target_net_roas_8w: a.net_roas ?? 0,
        current_bid: null,
        recommended_bid: isSB ? camp.suggested_bid_sb : camp.suggested_bid,
        spend: a.cost, orders: a.units, cpc: a.cpc ?? 0,
        conv_rate: a.clicks > 0 ? a.units / a.clicks : 0,
        source: 'COACH',
      });
    }
  };

  return (
    <div className="border-b border-border-faint last:border-0">
      <div className="flex items-center gap-1.5 py-0.5">
        <button onClick={() => setOpen(o => !o)} className="flex flex-1 min-w-0 items-center gap-1.5 text-left">
          <span className="w-2 shrink-0 text-[9px] text-faint">{open ? '▾' : '▸'}</span>
          <span className="shrink-0 rounded bg-white/[0.05] px-1 py-px text-[9px] font-semibold text-muted">
            {camp.group_code}
          </span>
          <span className="truncate text-[11px] text-muted" title={camp.campaign_name}>{camp.campaign_name}</span>
          <span className="ml-auto shrink-0 whitespace-nowrap text-[10px] tabular-nums text-faint">
            {camp.n_asins} ASIN{camp.n_asins === 1 ? '' : 's'} · bid{' '}
            <span className={camp.bid_capped ? 'text-amber-400' : 'text-heading'}
              title={camp.bid_capped
                ? `Group break-even is $${camp.suggested_bid_raw.toFixed(2)}; capped by the COMPETITOR template's bid ceiling`
                : `Lowest break-even CPC in the group — every ASIN here still clears the profit floor at this bid`}>
              ${camp.suggested_bid.toFixed(2)}{camp.bid_capped && ' ▲'}
            </span>
            {' · '}~${Math.round(camp.proj_spend)} spend → ${Math.round(camp.proj_margin)} margin{' · '}
            <span className={(camp.proj_net_roas ?? 0) >= 1 ? 'text-emerald-400' : 'text-red-400'}>
              {(camp.proj_net_roas ?? 0).toFixed(2)}x
            </span>
          </span>
        </button>
        <button
          onClick={() => queueChannel('SP')}
          disabled={queued}
          title={queued ? 'SP conquest already in the Do queue' : `Queue the SP product-targeting campaign (${camp.n_asins} target(s)) for the next bulksheet`}
          className="shrink-0 rounded px-1 py-px text-[9px] font-semibold text-faint hover:text-muted disabled:opacity-40"
        >
          {queued ? '✓ queued' : '+ queue'}
        </button>
        <button
          onClick={() => queueChannel('SB')}
          disabled={queuedSb}
          title={queuedSb ? 'SB video conquest already in the Do queue' : `Queue the SB VIDEO campaign (${camp.sb_campaign_name}) on the same competitor pages — runs the ${variation} video`}
          className="shrink-0 rounded px-1 py-px text-[9px] font-semibold text-violet-400/70 hover:text-violet-300 disabled:opacity-40"
        >
          {queuedSb ? '✓ video' : '🎬 video'}
        </button>
      </div>
      {open && (
        <div className="pl-4 pb-1">
          <div className="py-0.5 text-[9px] text-faint">
            Ad group “{camp.ad_group_name}” · ${camp.daily_budget ?? '—'}/day
            {(camp.product_page_pct ?? 0) > 0 && ` · +${camp.product_page_pct}% product page`}
            {' · '}break-even CPC in group: min ${camp.suggested_bid_raw.toFixed(2)} ·
            med ${camp.group_med_target_cpc.toFixed(2)} · max ${camp.group_max_target_cpc.toFixed(2)}
            {' — bidding at the MIN keeps every ASIN above the profit floor.'}
          </div>
          {camp.asins.map(a => (
            <CompRow key={a.candidate_asin} asin={a.candidate_asin} sub={a.found_in}
              clicks={a.clicks} cost={a.cost} cpc={a.cpc} units={a.units}
              netRoas={a.net_roas} targetCpc={a.target_cpc} />
          ))}
        </div>
      )}
    </div>
  );
}

/** Variation → tier → campaign tree for one family. */
export function CompetitorPlanPanel({ family, data, loading }: {
  family: string | null; data: Record<string, PlanFamily> | null; loading: boolean;
}) {
  const f = family ? data?.[family] : undefined;
  if (loading && !data) return <div className="mt-2 text-[10px] text-faint">building campaign plan…</div>;
  if (!f || f.variations.length === 0) {
    return (
      <div className="mt-2 text-[10px] text-faint">
        No competitor campaigns to build in this window — nothing cleared the promotion bar.
      </div>
    );
  }
  const nCampaigns = f.variations.reduce((s, v) => s + v.tiers.reduce((t, x) => t + x.campaigns.length, 0), 0);
  const nAsins = f.variations.reduce((s, v) => s + v.tiers.reduce((t, x) => t + x.campaigns.reduce((c, y) => c + y.n_asins, 0), 0), 0);
  return (
    <div className="mt-2 rounded border border-border-faint bg-surface/40 p-2">
      <div className="mb-1.5 flex items-center gap-2">
        <span className="text-[11px] font-semibold text-heading">🏗 Campaigns to build</span>
        <span className="text-[10px] tabular-nums text-muted">
          {nCampaigns} campaign{nCampaigns === 1 ? '' : 's'} · {nAsins} ASINs
        </span>
      </div>
      {f.variations.map(v => (
        <div key={v.variation} className="mb-1.5 last:mb-0">
          <div className="text-[10px] font-semibold text-muted">
            {v.variation_label}
            <span className="ml-1 font-normal text-faint">
              — the variation that actually sold on these pages ({v.winner_asin})
            </span>
          </div>
          {v.tiers.map(t => (
            <div key={t.tier_code} className="pl-2">
              <div className="mt-0.5 text-[9px] font-semibold uppercase tracking-wide text-faint">{t.tier_label}</div>
              <div className="pl-1">
                {t.campaigns.map(c => (
                  <PlanCampaignRow key={c.campaign_key} camp={c} variation={v.variation}
                    winnerAsin={v.winner_asin} family={family!} />
                ))}
              </div>
            </div>
          ))}
        </div>
      ))}
      <div className="mt-1 text-[9px] italic text-faint">
        One campaign per winner variation × bid tier, max 10 ASINs — a campaign shares one bid, so
        every ASIN in it must want roughly the same one. Queue a campaign, then export the bulksheet
        from the Do page and upload it to Amazon manually.
      </div>
    </div>
  );
}

// Strategies whose campaigns target keywords → month rows can drill into keyword breakdowns.
// AUTO / PRODUCT_DEFENSE are ASIN/auto-targeted (no keywords), so their months stay flat.
const KEYWORD_STRATEGIES = new Set(['BROAD_SP', 'BROAD_VIDEO', 'BROAD_SPOTLIGHT', 'PHRASE', 'EXACT', 'BRAND_DEFENSE']);
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
function KeywordPanel({ family, data, loading, mode = 'intent', months }: { family: string | null; data: Record<string, FamilyKeywords> | null; loading: boolean; mode?: 'intent' | 'brand'; months?: KwMonthsCtx }) {
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
                <KeywordRow key={`${k.match_type}-${k.keyword_text}-${i}`} k={k} family={family} months={months} />
              ))}
            </div>
          );
        })}
      </div>
    );
  }

  const intentGroups = groupByIntent(filtered);
  const intentsMap = fam.intents ?? {};
  // Partition by the family's suggestion map: a group is "suggested" only when its
  // intent has an entry with suggested===true; everything else (false, or no entry —
  // e.g. the Other/unclassified bucket) falls to the not-suggested section.
  const suggestedGroups = intentGroups.filter(g => intentsMap[g.key]?.suggested === true);
  const notSuggestedGroups = intentGroups.filter(g => intentsMap[g.key]?.suggested !== true);

  const renderGroup = (g: IntentGroup) => {
    const isOpen = openIntents.has(g.key);
    const roas = intentsMap[g.key]?.wtd_net_roas;
    return (
      <div key={g.key} className="mt-1">
        <button onClick={() => toggle(g.key)} className="flex w-full items-center gap-1.5 py-0.5 text-left hover:bg-white/[0.02]">
          <span className="w-2 shrink-0 text-[9px] text-faint">{isOpen ? '▾' : '▸'}</span>
          <span className="truncate text-[11px] font-semibold text-heading">{g.label}</span>
          <span className="ml-auto shrink-0 text-[9px] tabular-nums">
            {roas != null && <span className={`mr-1.5 ${roas >= 1.1 ? 'text-emerald-400' : 'text-red-400'}`}>{roas.toFixed(2)}x</span>}
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
                  <KeywordRow key={`${k.match_type}-${k.keyword_text}-${i}`} k={k} family={family} months={months} />
                ))}
              </div>
            ))}
          </div>
        )}
      </div>
    );
  };

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
      {suggestedGroups.length > 0 && (
        <div className="mb-1">
          <div className="mb-0.5 mt-1 text-[10px] font-semibold text-emerald-400">✅ Suggested intents</div>
          {suggestedGroups.map(renderGroup)}
        </div>
      )}
      {notSuggestedGroups.length > 0 && (
        <div>
          <div className="mb-0.5 mt-1 text-[10px] font-semibold text-faint">⊘ Not-suggested intents</div>
          {notSuggestedGroups.map(renderGroup)}
        </div>
      )}
    </div>
  );
}

const STATUS_ORDER: Record<Cell['status'], number> = {
  missing: 0,
  dark: 1,          // configured but not delivering — as urgent as missing, listed just after
  redundant: 2,
  ok: 3,
  none: 4,
  suppressed: 5,
  unmapped: 6,
};

function cellLabel(c: Cell, byStrategy = false): string {
  // byStrategy: the family-only view already scopes to one product, so a FAMILY/STORE row titled
  // with the family name just repeats it. Title it with the strategy and drop the extra hierarchy
  // level — the row then opens straight to campaigns (Ori 2026-07-23). ASIN-grain (Auto) keeps the
  // product name, because there a family genuinely has several cells worth telling apart.
  if (byStrategy) {
    const st = STRAT_LABEL[c.strategy] ?? c.strategy;
    if (c.grain === 'FAMILY' || c.grain === 'STORE') return st;
    // Auto is ASIN-grain, so a family has one cell per variation. Prefix each with the strategy
    // instead of nesting them under a header — otherwise Auto is the only strategy with a second
    // level, and the header-less rows that follow it look like they belong to it (Ori 2026-07-23).
    return `${st} · ${c.product_short_name || c.parent_name || c.asin || '—'}`;
  }
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

/** Same shape as groupByFamily, but grouped by STRATEGY — used when a family is selected with
 *  no strategy tile open, so "pick a product" shows everything that product runs, across strategies. */
export function groupByStrategy(cells: Cell[]): FamilyGroup[] {
  const byStrategy = new Map<string, Cell[]>();
  for (const c of cells) {
    const arr = byStrategy.get(c.strategy);
    if (arr) arr.push(c);
    else byStrategy.set(c.strategy, [c]);
  }
  const groups: FamilyGroup[] = [];
  for (const [strategy, groupCells] of byStrategy) {
    const sorted = [...groupCells].sort((a, b) => STATUS_ORDER[a.status] - STATUS_ORDER[b.status]);
    groups.push({
      family: STRAT_LABEL[strategy] ?? strategy,
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

/** One family button in the left panel: name + defined/planned + windowed profit roll-up. */
function FamilyButton({ entry, selected, onSelect, win }: { entry: FamilyEntry; selected: boolean; onSelect: () => void; win?: string }) {
  const { defined, planned } = entry.stat;
  const dpTone = defined >= planned ? 'text-emerald-400' : 'text-red-400';
  return (
    <button
      onClick={onSelect}
      className={`w-full rounded-lg border px-3 py-2 text-left transition border-border-faint bg-surface hover:bg-white/[0.04] ${selected ? 'ring-2 ring-blue-400/60' : ''}`}
    >
      <div className="text-xs font-bold text-heading">{entry.label}</div>
      <div className={`mt-0.5 text-[10px] font-semibold tabular-nums ${dpTone}`}>{defined}/{planned} defined</div>
      <ProfitRollup s={entry.stat} win={win} />
    </button>
  );
}

/** Daily-workflow coverage cockpit (rung 1): six strategy tiles rolling up
 *  defined / to-do / redundant, each expandable to its coverage cells.
 *  All status/roll-up logic lives in /api/daily-workflow (BigQuery); this only renders. */
// Segmented time-window control — same visual language as HomeBrief's DateToggle.
function CovWindowToggle({ win, onPick }: { win: CovWindow; onPick: (w: CovWindow) => void }) {
  return (
    <div className="inline-flex flex-wrap gap-0.5 bg-white/[.04] border border-border rounded-lg p-0.5">
      {COV_WINDOWS.map(w => {
        const active = win === w.key;
        return (
          <button key={w.key} title={w.hint} onClick={() => onPick(w.key)}
            className={`text-[11px] font-mono px-2 py-1 rounded-md transition-all
              ${active ? 'bg-blue-500/90 text-white' : 'text-muted hover:text-text'}`}>
            {w.label}
          </button>
        );
      })}
    </div>
  );
}

export function CoveragePage() {
  const [data, setData] = useState<WorkflowData | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [win, setWin] = useState<CovWindow>(recallWin); // time window governing every measure on the page
  const wfUrl = `/api/daily-workflow?window=${win}`;
  const pickWin = (w: CovWindow) => { setWin(w); try { localStorage.setItem(COV_WIN_KEY, w); } catch { /* ignore */ } };
  const [open, setOpen] = useState<string | null>(null); // strategy name
  const [selectedFamily, setSelectedFamily] = useState<string | null>(null); // null = ALL; else parent_name or STORE_KEY
  const [openCell, setOpenCell] = useState<string | null>(null); // expanded cell_key
  const [kwData, setKwData] = useState<Record<string, FamilyKeywords> | null>(null);
  const [kwLoading, setKwLoading] = useState(false);
  const [pendingCell, setPendingCell] = useState<string | null>(null); // cell_key of in-flight suppress toggle
  const [configOpen, setConfigOpen] = useState(false); // campaign-mapping modal open
  const [mapData, setMapData] = useState<MappingData | null>(null); // lazily-fetched mapping list
  const [mapLoading, setMapLoading] = useState(false);
  const [mapPending, setMapPending] = useState<Set<string>>(new Set()); // campaign_ids of in-flight assigns
  const [onlyUnmapped, setOnlyUnmapped] = useState(true); // modal filter toggle (default: only unmapped)
  const [compData, setCompData] = useState<Record<string, CompFamily> | null>(null);
  const [compLoading, setCompLoading] = useState(false);
  const [planData, setPlanData] = useState<Record<string, PlanFamily> | null>(null);
  const [planLoading, setPlanLoading] = useState(false);
  const [wfRefreshing, setWfRefreshing] = useState(false); // window switch in flight — numbers on screen are stale
  const [monthsData, setMonthsData] = useState<Record<string, MonthRow[]> | null>(null);
  const [monthsLoading, setMonthsLoading] = useState(false);
  const [openCampaigns, setOpenCampaigns] = useState<Set<string>>(new Set()); // expanded campaign_ids
  const [kwMonthsData, setKwMonthsData] = useState<Record<string, Record<string, KwMonthRow[]>> | null>(null); // family → keyword_key → months
  const [kwMonthsLoading, setKwMonthsLoading] = useState<Set<string>>(new Set()); // families with an in-flight fetch
  const [openKw, setOpenKw] = useState<Set<string>>(new Set()); // expanded keyword_keys
  const [monthKwData, setMonthKwData] = useState<Record<string, Record<string, MonthKw[]>>>({}); // campaign_id → month → keywords
  const [monthKwLoading, setMonthKwLoading] = useState<Set<string>>(new Set()); // campaign_ids with an in-flight fetch
  const [openMonths, setOpenMonths] = useState<Set<string>>(new Set()); // expanded `${campaign_id}|${month}`

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
      const wf = await apiFetch(wfUrl);
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

  /** Lazily fetch the full campaign-mapping list once (called when Configure opens). */
  function ensureMapping() {
    if (mapData !== null || mapLoading) return;
    setMapLoading(true);
    apiFetch('/api/admin/campaign-mapping')
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(json => setMapData({
        campaigns: json.campaigns ?? [],
        families: json.families ?? [],
        strategies: json.strategies ?? [],
      }))
      .catch(() => setMapData({ campaigns: [], families: [], strategies: [] }))
      .finally(() => setMapLoading(false));
  }

  /** Assign (or re-assign) a campaign to a family+strategy, then refetch the mapping
   *  list (modal rows) and the workflow (badge). Per-row pending tracked by campaign_id. */
  async function saveMapping(campaign_id: string, family: string, strategy: string) {
    if (!campaign_id || !family || !strategy || mapPending.has(campaign_id)) return;
    setMapPending(prev => new Set(prev).add(campaign_id));
    try {
      const res = await apiFetch('/api/admin/campaign-mapping/assign', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ campaign_id, family, strategy }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      if (!json.success) throw new Error(json.error || 'server rejected mapping');
      const m = await apiFetch('/api/admin/campaign-mapping');
      if (m.ok) {
        const mj = await m.json();
        if (mj.success) setMapData({ campaigns: mj.campaigns ?? [], families: mj.families ?? [], strategies: mj.strategies ?? [] });
      }
      const wf = await apiFetch(wfUrl);
      if (wf.ok) {
        const fresh = await wf.json();
        if (!fresh.error) setData(fresh);
      }
    } catch (e) {
      console.warn('campaign mapping assign failed', e);
    } finally {
      setMapPending(prev => { const next = new Set(prev); next.delete(campaign_id); return next; });
    }
  }

  /** Fetch the keyword panel for a window, replacing whatever is cached. Keyword measures
   *  (clicks/cost/cpc/net_roas/target_cpc/profit_state) are window-scoped server-side via
   *  FN_COVERAGE_KEYWORD, so the panel must answer to the same toggle as the tiles. */
  function fetchKeywords(w: CovWindow) {
    setKwLoading(true);
    apiFetch(`/api/coverage-keywords?window=${w}`)
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(json => setKwData(json.families ?? {}))
      .catch(() => setKwData({}))
      .finally(() => setKwLoading(false));
  }

  /** Competitor ASIN targets + Auto-discovered candidates; window-scoped like the keyword panel. */
  function fetchCompetitor(w: CovWindow) {
    setCompLoading(true);
    apiFetch(`/api/competitor-targets?window=${w}`)
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(json => setCompData(json.families ?? {}))
      .catch(() => setCompData({}))
      .finally(() => setCompLoading(false));
  }
  /** Competitor campaigns to BUILD — same window as the evidence it is derived from. */
  function fetchCompetitorPlan(w: CovWindow) {
    setPlanLoading(true);
    apiFetch(`/api/competitor-campaign-plan?window=${w}`)
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(json => setPlanData(json.families ?? {}))
      .catch(() => setPlanData({}))
      .finally(() => setPlanLoading(false));
  }
  function ensureCompetitor() {
    if (planData === null && !planLoading) fetchCompetitorPlan(win);
    if (compData !== null || compLoading) return;
    fetchCompetitor(win);
  }

  function ensureKeywords() {
    if (kwData !== null || kwLoading) return;
    fetchKeywords(win);
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

  /** Lazy-load a family's per-keyword 12-month drill once; cache keyed by family. */
  function ensureKwMonths(family: string) {
    if (!family) return;
    if (kwMonthsData?.[family] || kwMonthsLoading.has(family)) return;
    setKwMonthsLoading(prev => new Set(prev).add(family));
    apiFetch(`/api/keyword-months?family=${encodeURIComponent(family)}`)
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(json => setKwMonthsData(prev => ({ ...(prev ?? {}), [family]: json.months ?? {} })))
      .catch(() => setKwMonthsData(prev => ({ ...(prev ?? {}), [family]: {} })))
      .finally(() => setKwMonthsLoading(prev => { const next = new Set(prev); next.delete(family); return next; }));
  }

  function toggleKw(key: string) {
    setOpenKw(prev => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  /** Lazy-load a campaign's per-month keyword breakdown once; cache keyed by campaign_id. */
  function ensureMonthKw(campaignId: string) {
    if (!campaignId) return;
    if (monthKwData[campaignId] || monthKwLoading.has(campaignId)) return;
    setMonthKwLoading(prev => new Set(prev).add(campaignId));
    apiFetch(`/api/campaign-keyword-months?campaign_id=${encodeURIComponent(campaignId)}`)
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(json => setMonthKwData(prev => ({ ...prev, [campaignId]: json.months ?? {} })))
      .catch(() => setMonthKwData(prev => ({ ...prev, [campaignId]: {} })))
      .finally(() => setMonthKwLoading(prev => { const next = new Set(prev); next.delete(campaignId); return next; }));
  }

  function toggleMonth(key: string) {
    setOpenMonths(prev => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  useEffect(() => {
    // Re-fetch whenever the window changes. Keep the old data on screen until the new
    // payload lands (no flip to the "Scanning…" splash) so switching windows feels instant.
    let cancelled = false;
    setWfRefreshing(true);
    apiFetch(wfUrl)
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(d => { if (!cancelled) (d.error ? setErr(d.error) : setData(d)); })
      .catch(e => { if (!cancelled) setErr(String(e)); })
      .finally(() => { if (!cancelled) setWfRefreshing(false); });
    return () => { cancelled = true; };
  }, [wfUrl]);

  useEffect(() => {
    // Keyword measures are window-scoped too, so the panel has to follow the toggle.
    // It's lazy-loaded, so only refetch when it's already on screen — otherwise
    // ensureKeywords() will fetch it with the current window on first expand.
    if (compData !== null) fetchCompetitor(win);
    if (planData !== null) fetchCompetitorPlan(win);
    if (kwData === null) return;
    fetchKeywords(win);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [win]);

  if (err) return <div className="p-6 text-sm text-red-400">Coverage scan failed: {err}</div>;
  if (!data) return <div className="p-6 text-sm text-muted">Scanning ad coverage…</div>;

  const familyMatch = (c: Cell): boolean => {
    if (selectedFamily === null) return true; // ALL
    if (selectedFamily === STORE_KEY) return c.parent_name === null;
    return c.parent_name === selectedFamily;
  };
  // ARCHIVED campaigns are history, not work — they'd otherwise flood the UNMAPPED drill in wide
  // windows (42 of 44 at 12mo). Keep them out of the actionable list; their spend still counts in
  // the P&L rollups, and the count is shown below so nothing is silently hidden.
  // Picking a product/family with NO strategy open shows EVERYTHING that family runs, across all
  // strategies (Ori 2026-07-23) — previously this rendered nothing until you also clicked a tile.
  const familyOnly = !open && selectedFamily !== null;
  const openScope = open
    ? data.cells.filter(c => c.strategy === open && familyMatch(c))
    : familyOnly ? data.cells.filter(familyMatch) : [];
  const archivedCount = openScope.filter(c => c.is_archived).length;
  const archivedSpend = openScope.filter(c => c.is_archived).reduce((n, c) => n + (c.cost || 0), 0);
  const openGroups = familyOnly
    ? groupByStrategy(openScope.filter(c => !c.is_archived))
    : groupByFamily(openScope.filter(c => !c.is_archived));
  const openCellCount = openGroups.reduce((n, g) => n + g.cells.length, 0);
  // Tiles must respect the family filter: picking Bottle should show Bottle's coverage counts and
  // Bottle's P&L on every strategy tile, not the all-families totals (Ori 2026-07-23).
  const tilesScoped: Record<string, Tile> = selectedFamily === null
    ? data.tiles
    : Object.fromEntries(data.strategies.map(st => {
        const cs = data.cells.filter(c => c.strategy === st && familyMatch(c) && !c.is_archived);
        return [st, {
          defined:       cs.filter(c => c.status === 'ok').length,
          missing:       cs.filter(c => c.status === 'missing').length,
          redundant:     cs.filter(c => c.status === 'redundant').length,
          informational: cs.filter(c => c.status === 'none').length,
          suppressed:    cs.filter(c => c.status === 'suppressed').length,
        } as Tile];
      }));
  /** Per-strategy P&L for the current family scope (falls back to all-families when ALL). */
  const statFor = (st: string): StrategyStat | undefined =>
    selectedFamily === null
      ? data.strategy_stats?.[st]
      : data.strategy_family_stats?.[`${st}|${selectedFamily}`];
  const familyEntries = buildFamilyEntries(data.family_stats);
  const kwMonthsCtx: KwMonthsCtx = {
    data: kwMonthsData,
    loading: (f: string) => kwMonthsLoading.has(f),
    expanded: openKw,
    toggle: toggleKw,
    ensure: ensureKwMonths,
  };
  const monthKwCtx: MonthKwCtx = {
    data: monthKwData,
    loading: (id: string) => monthKwLoading.has(id),
    expanded: openMonths,
    toggle: toggleMonth,
    ensure: ensureMonthKw,
  };

  return (
    <div className="p-4">
      <div className="flex items-center justify-between gap-3 mb-2">
        <div className="flex items-center gap-3">
          <h1 className="text-lg font-bold text-heading">🗂️ Daily Workflow — Coverage</h1>
          <span className="text-[11px] text-muted">green = everything defined · click a strategy to see the mapping</span>
        </div>
        <ConfigureButton
          count={data.tiles['UNMAPPED']?.informational ?? 0}
          onClick={() => { setConfigOpen(true); ensureMapping(); }}
        />
      </div>

      {/* Time window — governs every measure below (coverage counts, status, metrics). Default 7 days. */}
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 mb-4">
        <span className="text-[11px] font-semibold text-muted">Time window</span>
        <CovWindowToggle win={win} onPick={pickWin} />
        <span className="text-[11px] text-faint">
          {wfRefreshing && (
            <span className="mr-2 rounded bg-amber-500/15 px-1.5 py-px text-[10px] font-semibold text-amber-400">
              updating… showing previous window
            </span>
          )}
          {data.window_start && data.window_end
            ? (data.window_start === data.window_end
                ? data.window_start
                : `${data.window_start} → ${data.window_end}`)
            : ''}
          {win === 'peak' && <span className="text-faint"> · gift-season days only</span>}
          <span className="text-faint"> · all metrics below reflect this window</span>
        </span>
      </div>

      <div className="flex flex-col md:flex-row gap-3">
        <div className="flex w-full shrink-0 flex-col gap-2 md:w-[170px] md:min-w-[170px]">
          {familyEntries.map(entry => (
            <FamilyButton
              key={entry.key}
              entry={entry}
              selected={entry.key === 'ALL' ? selectedFamily === null : selectedFamily === entry.key}
              onSelect={() => setSelectedFamily(entry.key === 'ALL' ? null : entry.key)}
              win={winShort(win)}
            />
          ))}
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap gap-2 mb-2">
            {data.strategies.filter(s => s !== 'UNMAPPED').map(s => (
              <StrategyTile
                key={s}
                name={s}
                t={tilesScoped[s] ?? { defined: 0, missing: 0, redundant: 0, informational: 0, suppressed: 0 }}
                stat={statFor(s)}
                open={open === s}
                onOpen={() => setOpen(o => (o === s ? null : s))}
                win={winShort(win)}
              />
            ))}
          </div>

      {/* Stale-window guard: the toggle label flips instantly but the numbers come from the payload,
          which takes seconds to refetch. Dimming them (plus the "updating…" chip above) makes it
          obvious the figures below still belong to the PREVIOUS window — otherwise switching to
          Yesterday and seeing 7-day numbers reads as a broken filter (Ori 2026-07-23). */}
      {(open || familyOnly) && (
        <div className={`mt-3 border border-border/40 rounded-lg bg-white/[0.01] max-w-[860px] transition-opacity ${wfRefreshing ? 'opacity-40' : ''}`}>
          <div className="flex items-center justify-between px-4 py-2.5 border-b border-border/20 bg-white/[0.02]">
            <div className="text-sm font-semibold">
              {open
                ? (STRAT_LABEL[open] ?? open)
                : (selectedFamily === STORE_KEY ? 'Store' : selectedFamily)}
              <span className="text-faint text-xs ml-2 font-normal">
                {open ? 'mapping — done vs to do' : 'all strategies — done vs to do'}
              </span>
            </div>
            <button
              onClick={() => { if (open) setOpen(null); else setSelectedFamily(null); }}
              className="text-faint hover:text-text text-lg leading-none px-1" title="Collapse">×</button>
          </div>

          <div className="p-4 text-xs">
            {/* Never silently truncate: say what was held back and why. */}
            {archivedCount > 0 && (
              <div className="mb-2 rounded border border-border-faint bg-white/[0.02] px-2 py-1 text-[10px] text-faint">
                ⊙ {archivedCount} archived campaign{archivedCount === 1 ? '' : 's'} ran in this window
                {archivedSpend > 0 && <> (${Math.round(archivedSpend).toLocaleString()} spend)</>} — hidden
                from the to-do list because they're closed in Amazon. Their spend still counts in the P&amp;L above.
              </div>
            )}
            {openCellCount === 0 ? (
              <div className="text-faint text-[10px]">
                {archivedCount > 0
                  ? `Nothing actionable for ${open ? 'this strategy' : 'this product'} in this window — only archived campaigns.`
                  : `No coverage cells for ${open ? 'this strategy' : 'this product'}.`}
              </div>
            ) : (
              openGroups.map(group => (
                <div key={group.family} className="mb-2 last:mb-0">
                  {/* In the family view a single family-grain cell IS the strategy row, so the
                      group header would just repeat it. Auto (many ASIN cells) still gets one. */}
                  {!familyOnly && (
                    <div className="flex items-center gap-1.5 px-0.5 pb-0.5 pt-1">
                      <span className="text-muted uppercase text-[10px] font-semibold tracking-wide">{group.family}</span>
                      {group.missingCount > 0 && (
                        <span className="text-red-400 text-[10px] font-semibold">{group.missingCount} to do</span>
                      )}
                    </div>
                  )}
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
                              if (KEYWORD_STRATEGIES.has(c.strategy)) ensureKeywords();
                              if (c.strategy === 'COMPETITOR') ensureCompetitor();
                            }}
                            className="flex flex-1 min-w-0 items-center gap-2 text-left"
                          >
                            <span className="text-faint text-[9px] w-2 shrink-0">{isOpen ? '▾' : '▸'}</span>
                            <span className="text-heading truncate max-w-[200px]" title={c.asin ?? undefined}>{cellLabel(c, familyOnly)}</span>
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
                            {/* The `reason` line was removed as redundant (Ori 2026-07-23): the row's
                                own status pill already says "⚠ 2 campaigns" / "✗ to do", and the
                                campaigns it described are listed directly below. It also leaked the
                                raw enum (BROAD_SPOTLIGHT). `reason` still comes back on the payload
                                for anything that wants to explain a cell elsewhere. */}
                            {campaigns && campaigns.length > 0 ? (
                              campaigns.map((cmp, j) => (
                                <CampaignEvidenceRow
                                  key={`${cmp.campaign_name}-${j}`}
                                  c={cmp}
                                  months={monthsData?.[cmp.campaign_id]}
                                  monthsLoading={monthsLoading}
                                  isOpen={openCampaigns.has(cmp.campaign_id)}
                                  onToggle={() => { toggleCampaign(cmp.campaign_id); ensureMonths(); }}
                                  monthKwCtx={KEYWORD_STRATEGIES.has(c.strategy) ? monthKwCtx : undefined}
                                />
                              ))
                            ) : (
                              <div className="text-faint text-[10px]">no campaigns</div>
                            )}
                            {(c.strategy !== 'BRAND_DEFENSE' && KEYWORD_STRATEGIES.has(c.strategy)) && (
                              <KeywordPanel family={c.parent_name} data={kwData} loading={kwLoading} mode="intent" months={kwMonthsCtx} />
                            )}
                            {c.strategy === 'COMPETITOR' && (
                              <>
                                <CompetitorPanel family={c.parent_name} data={compData} loading={compLoading} />
                                <CompetitorPlanPanel family={c.parent_name} data={planData} loading={planLoading} />
                              </>
                            )}
                            {c.strategy === 'BRAND_DEFENSE' && (
                              <KeywordPanel family={c.parent_name} data={kwData} loading={kwLoading} mode="brand" months={kwMonthsCtx} />
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

      {configOpen && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
          onClick={() => setConfigOpen(false)}
        >
          <div
            className="bg-card border border-border rounded-lg max-w-[820px] w-[92%] max-h-[85vh] overflow-auto"
            onClick={e => e.stopPropagation()}
          >
            <div className="sticky top-0 flex items-start justify-between border-b border-border bg-card px-4 py-3">
              <div>
                <div className="text-sm font-bold text-heading">Campaign Mapping</div>
                <div className="text-[11px] text-muted">assign campaigns to strategies</div>
              </div>
              <div className="flex items-center gap-3">
                <label className="flex items-center gap-1 text-[11px] text-muted">
                  <input type="checkbox" checked={onlyUnmapped} onChange={e => setOnlyUnmapped(e.target.checked)} />
                  show only unmapped
                </label>
                <button
                  onClick={() => setConfigOpen(false)}
                  className="px-1 text-lg leading-none text-faint hover:text-heading"
                  title="Close"
                >
                  ✕
                </button>
              </div>
            </div>
            <div className="p-3">
              {mapLoading && !mapData ? (
                <div className="py-4 text-center text-[11px] text-faint">loading…</div>
              ) : (() => {
                const rows = (mapData?.campaigns ?? []).filter(c => (onlyUnmapped ? c.current_strategy_id == null : true));
                if (rows.length === 0) {
                  return <div className="py-4 text-center text-[11px] text-faint">no campaigns</div>;
                }
                return rows.map(c => (
                  <MappingRow
                    key={c.campaign_id}
                    c={c}
                    families={mapData?.families ?? []}
                    strategies={mapData?.strategies ?? []}
                    pending={mapPending.has(c.campaign_id)}
                    onSave={(family, strategy) => saveMapping(c.campaign_id, family, strategy)}
                  />
                ));
              })()}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
