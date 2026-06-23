import { useState, useMemo } from 'react';
import type { DashboardData, FamilyName, ExperimentCampaignRow, CampaignSearchTermRow, HolidayRow, PeakRelevanceRow, PeakKeywordRecRow } from '../types';
import { useFilters } from '../hooks/useFilters';
import { formatSectionFilters } from '../utils/filterUtils';
import { FilterInfoIcon } from '../components/FilterInfoIcon';
import { experimentMatchesFamily } from '../utils';
import { Badge } from '../components/Badge';
import { PageHeader } from '../components/PageHeader';
import { Card } from '../components/Card';
import { Empty } from '../components/Empty';
import { Th, MEASURE_TIPS } from '../components/Tooltip';
import { ChevronRight, ChevronDown, Calendar, TrendingUp, Zap, AlertTriangle } from 'lucide-react';
import { fM, fP, fOrd, fR, fClk, famFromType, formatDateRange } from '../utils';
import { usePageSummary } from '../components/PageSummaryBar';
import { MeasureSelector, useMeasureSelection, type MeasureDef } from '../components/MeasureSelector';
import { useProductFamily } from '../hooks/useProductFamily';

const STAGES = ['PRE_SEASON', 'PRE_PEAK_BOOST', 'PEAK'] as const;
const STAGE_LABELS: Record<string, string> = { PRE_SEASON: 'Pre Season', PRE_PEAK_BOOST: 'Boost', PEAK: 'Peak', POST_PEAK: 'Post Peak' };
const STAGE_COLORS: Record<string, string> = {
  PRE_SEASON: 'from-blue-700 to-blue-500',
  PRE_PEAK_BOOST: 'from-amber-700 to-amber-500',
  PEAK: 'from-red-700 to-red-500',
};

const FAMILY_NAMES: FamilyName[] = ['Lollibox', 'LolliME', 'Bottle', 'Fresh'];

type CheckItem = { label: string; dataKey: string };

const CHECKLISTS: Record<string, CheckItem[]> = {
  PRE_SEASON: [
    { label: 'Verify ≥ 10 peak keywords are mapped with market volume data (expand to review)', dataKey: 'peak_keywords' },
    { label: 'Create an experiment per product family — confirm status is ACTIVE (expand to review)', dataKey: 'experiments_status' },
    { label: 'Define bid strategy, daily budget & match types per campaign (Campaign Manager)', dataKey: 'campaign_config' },
    { label: 'Add ≥ 5 negative keywords per campaign to block wasted spend (expand to review)', dataKey: 'negative_keywords' },
    { label: 'Create SP + SB campaigns in Amazon Ads console for each experiment', dataKey: 'campaigns_created' },
    { label: 'Confirm FBA stock covers ≥ 6 weeks of projected peak orders (Seller Central → Inventory Planning)', dataKey: 'inventory' },
    { label: 'Verify all peak campaigns show status ENABLED in Amazon Ads (expand to review)', dataKey: 'campaigns_live' },
    { label: 'Review LY top Ads keywords by orders — add missing high-converters to campaigns (expand)', dataKey: 'ly_ads_best_keywords' },
    { label: 'Review LY top SQP organic keywords — verify paid coverage for top 10 (expand to review)', dataKey: 'ly_sqp_best_keywords' },
    { label: 'Confirm 0 keywords target a non-hero ASIN — fix any mismatches (expand to see list)', dataKey: 'hero_asin_check' },
    { label: 'Audit hero ASIN listings: peak keywords in title, A+ content live, ≥ 6 images (Seller Central)', dataKey: 'listings_ready' },
  ],
  PRE_PEAK_BOOST: [
    { label: 'Confirm ROAS trend is STABLE or IMPROVING for all experiments — 0 declining (expand to review)', dataKey: 'ads_healthy' },
    { label: 'Increase bids +10–20% per boost schedule (Campaign Manager → Bid Adjustments)', dataKey: 'bid_schedule' },
    { label: 'Raise daily budget +30–50% — confirm budget utilization stays < 90% (Campaign Manager)', dataKey: 'budget_increase' },
    { label: 'Verify Top-of-Search impression share ≥ 30% for hero ASINs (Campaign Manager → Placements)', dataKey: 'tos_check' },
    { label: 'Launch SB Video campaigns for each product family (Campaign Manager → Create Campaign)', dataKey: 'sb_video' },
    { label: 'Set up daily check: budget exhaustion, CPC spikes > $1.50, ROAS < 1.0 (this page + Ads page)', dataKey: 'monitoring' },
  ],
  PEAK: [
    { label: 'Compare actual 7d sales vs projected 4wk target — on track ≥ 80% pace (expand to review)', dataKey: 'sales_tracking' },
    { label: 'Verify budget utilization < 90% for all experiments — increase if capped (expand to review)', dataKey: 'budget_check' },
    { label: 'Confirm top 10 keywords by spend have conv rate > 5% — pause low-performers (expand)', dataKey: 'top_keywords_conv' },
    { label: 'Check all high-spend keywords have CPC < $1.50 — reduce bids if spiking (expand to review)', dataKey: 'cpc_check' },
    { label: 'Verify FBA stock covers remaining peak weeks — reorder if < 4 weeks supply (Seller Central)', dataKey: 'inventory_check' },
  ],
};

type PeakTrendMeasure = 'orders' | 'sales' | 'adCost' | 'netProfit';
const PEAK_TREND_MEASURES: { id: PeakTrendMeasure; label: string; color: string }[] = [
  { id: 'orders', label: 'Orders', color: '#3b82f6' },
  { id: 'sales', label: 'Sales', color: '#22c55e' },
  { id: 'adCost', label: 'Ads Spend', color: '#fb923c' },
  { id: 'netProfit', label: 'Net Profit', color: '#a78bfa' },
];

function KwRecRow({ r }: { r: PeakKeywordRecRow }) {
  const meta: Record<string, { label: string; cls: string }> = {
    INCREASE: { label: '↑ Increase', cls: 'text-emerald-400' },
    INCREASE_CAUTIOUS: { label: '↑ Cap', cls: 'text-amber-400' },
    ADD: { label: '+ Add', cls: 'text-blue-400' },
    DEFENSE: { label: '🛡 Defense', cls: 'text-purple-400' },
    WATCH: { label: 'Watch', cls: 'text-faint' },
  };
  const m = meta[r.recommendation] || meta.WATCH;
  return (
    <div className="flex items-center gap-2 text-[11px] py-1 border-b border-border-faint/40" title={r.reason}>
      <span className={`font-semibold whitespace-nowrap w-[58px] shrink-0 ${m.cls}`}>{m.label}</span>
      <span className="text-blue-300 font-medium truncate flex-1 min-w-0">{r.search_term}</span>
      {r.is_trending && <span className="text-[8px] text-amber-400 font-semibold whitespace-nowrap shrink-0" title="Market demand rising now">↗ trending</span>}
      <span className="font-mono text-faint text-[9px] whitespace-nowrap hidden lg:inline">{r.parent_name}</span>
      <span className="font-mono text-muted text-[10px] whitespace-nowrap w-16 text-right shrink-0">{r.amazon_sales.toLocaleString()} sales</span>
      <span className={`font-mono text-[10px] whitespace-nowrap w-9 text-right shrink-0 ${r.ly_net_roas != null && r.ly_net_roas >= 1 ? 'text-emerald-400' : 'text-muted'}`}>{r.ly_net_roas != null ? `${r.ly_net_roas.toFixed(1)}x` : '—'}</span>
    </div>
  );
}

function KwBucket({ title, sub, color, rows, limit }: { title: string; sub: string; color: string; rows: PeakKeywordRecRow[]; limit: number }) {
  return (
    <div>
      <div className={`text-[10px] uppercase tracking-wider font-semibold mb-1 ${color}`}>
        {title} <span className="text-faint normal-case font-normal">({rows.length}) · {sub}</span>
      </div>
      {rows.slice(0, limit).map(r => <KwRecRow key={r.parent_name + r.search_term} r={r} />)}
      {rows.length === 0 && <div className="text-[11px] text-faint py-1">None</div>}
    </div>
  );
}

export function PeakPage({ data }: { data: DashboardData }) {
  const { filters } = useFilters();
  const { getFamily } = useProductFamily();
  const allFuturePeaks = data.peak || [];
  const peakRelevance = data.peak_relevance || [];

  // ── Smart "Next Real Peak" selection ──
  // Find the first future holiday that is a REAL peak for at least one family.
  // If family filter is set, it must be a real peak specifically for THAT family.
  // Falls back to first future holiday if no relevance data is available yet.
  const pk = useMemo(() => {
    if (allFuturePeaks.length === 0) return null;
    if (peakRelevance.length === 0) return allFuturePeaks[0]; // no relevance data → fallback to next
    for (const candidate of allFuturePeaks) {
      const relRows = peakRelevance.filter(r => r.holiday_name === candidate.holiday_name);
      if (relRows.length === 0) return candidate; // no relevance data for this holiday → show it
      if (filters.family) {
        // Family filter active: check if THIS family peaks for this holiday
        const famRow = relRows.find(r => r.family === filters.family);
        if (famRow?.is_relevant_peak) return candidate;
      } else {
        // No filter: check if ANY family peaks
        if (relRows.some(r => r.is_relevant_peak)) return candidate;
      }
    }
    // No real peak found — fall back to the first future holiday
    return allFuturePeaks[0];
  }, [allFuturePeaks, peakRelevance, filters.family]);

  const [openStages, setOpenStages] = useState<Set<number>>(new Set([STAGES.findIndex(s => s === pk?.current_stage)]));
  const [expandedItems, setExpandedItems] = useState<Set<string>>(new Set());
  const [expandedExps, setExpandedExps] = useState<Set<string>>(new Set());
  const [expandedCampaigns, setExpandedCampaigns] = useState<Set<string>>(new Set());
  const [showYoy, setShowYoy] = useState(true);
  const [selectedHoliday, setSelectedHoliday] = useState<string | null>(null);
  const [selectedMeasures, setSelectedMeasures] = useMeasureSelection('peak_comparison', COMPARISON_MEASURES);
  const [peakTrendMeasure, setPeakTrendMeasure] = useState<PeakTrendMeasure>('orders');
  const [peakTrendGranularity, setPeakTrendGranularity] = useState<'weekly' | 'daily'>('daily');
  const [dtpRange, setDtpRange] = useState<{ before: number; after: number }>({ before: 7, after: 3 }); // days around peak to show: default 7 before → 3 after
  const [showDailyPeak, setShowDailyPeak] = useState(true);
  const [showLyTopTerms, setShowLyTopTerms] = useState(true);
  const [showKwPlan, setShowKwPlan] = useState(true);
  const [showProdActions, setShowProdActions] = useState(true);
  const [showStuck, setShowStuck] = useState(true);

  const allCheckData = useMemo(() => buildCheckData(data, pk, getFamily), [data, pk, getFamily]);

  const toggleExp = (eid: string) => setExpandedExps(p => { const n = new Set(p); n.has(eid) ? n.delete(eid) : n.add(eid); return n; });
  const toggleCampaign = (cid: string) => setExpandedCampaigns(p => { const n = new Set(p); n.has(cid) ? n.delete(cid) : n.add(cid); return n; });

  type CampaignDetail = ExperimentCampaignRow & {
    terms: CampaignSearchTermRow[];
  };
  type ExpDetail = {
    campaigns: CampaignDetail[];
    exp: (typeof data.experiments)[0] | null;
  };

  const expDetails = useMemo(() => {
    const allCamps = data.experiment_campaigns || [];
    const cst = data.campaign_search_terms || [];
    const exps = data.experiments || [];

    // Build search term index by campaign_id
    const termsByCamp: Record<string, CampaignSearchTermRow[]> = {};
    cst.forEach(t => {
      if (!termsByCamp[t.campaign_id]) termsByCamp[t.campaign_id] = [];
      termsByCamp[t.campaign_id].push(t);
    });

    // Build campaign with terms
    const buildCamp = (c: ExperimentCampaignRow): CampaignDetail => ({
      ...c,
      terms: (termsByCamp[c.campaign_id] || []).sort((a, b) => b.spend - a.spend),
    });

    // Step 1: group campaigns that have a DIM_EXPERIMENT_CAMPAIGN mapping
    const mappedByExp: Record<string, CampaignDetail[]> = {};
    const mappedCampIds = new Set<string>();
    allCamps.filter(c => c.experiment_id).forEach(c => {
      const eid = c.experiment_id!;
      if (!mappedByExp[eid]) mappedByExp[eid] = [];
      mappedByExp[eid].push(buildCamp(c));
      mappedCampIds.add(c.campaign_id);
    });

    // Step 2: collect unmapped campaigns
    const unmapped = allCamps.filter(c => !c.experiment_id && !mappedCampIds.has(c.campaign_id));

    // Step 3: heuristic matching — extract tokens from campaign name and experiment name
    const tokenize = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim().split(/\s+/).filter(t => t.length > 1);

    const FAMILY_PREFIXES: Record<string, string[]> = {
      Lollibox: ['box'],
      LolliME: ['me'],
      Bottle: ['bottle'],
      Fresh: ['fresh'],
    };

    const campFamilyPrefix = (name: string): string | null => {
      const lower = name.toLowerCase();
      if (lower.startsWith('box') || lower.includes('box-') || lower.includes('box ')) return 'box';
      if (lower.startsWith('me-') || lower.startsWith('me ') || lower.includes(' me-')) return 'me';
      if (lower.startsWith('bottle') || lower.includes('bottle-')) return 'bottle';
      if (lower.startsWith('fresh') || lower.includes('fresh-')) return 'fresh';
      if (lower.startsWith('brand')) return 'brand';
      return null;
    };

    const expFamilyPrefix = (name: string): string | null => {
      const lower = name.toLowerCase();
      for (const [, prefixes] of Object.entries(FAMILY_PREFIXES)) {
        for (const p of prefixes) {
          if (lower.includes(p)) return p;
        }
      }
      return null;
    };

    const matchScore = (expName: string, campName: string): number => {
      const expTokens = tokenize(expName);
      const campTokens = tokenize(campName);
      const NOISE = new Set(['sp', 'sb', 'auto', 'broad', 'exact', 'phrase', 'pt', 'video', 'store', 'the', 'for', 'and', 'of', 'with', 'new']);
      const meaningful = (t: string) => !NOISE.has(t) && t.length > 2;
      let score = 0;
      const expFamily = expFamilyPrefix(expName);
      const campFamily = campFamilyPrefix(campName);
      if (expFamily && campFamily && expFamily === campFamily) score += 2;
      else if (expFamily && campFamily && expFamily !== campFamily) return -1;
      for (const et of expTokens.filter(meaningful)) {
        for (const ct of campTokens.filter(meaningful)) {
          if (et === ct) score += 3;
          else if (et.includes(ct) || ct.includes(et)) score += 1;
        }
      }
      return score;
    };

    // Try to assign each unmapped campaign to the best-scoring experiment
    const heuristicByExp: Record<string, CampaignDetail[]> = {};
    unmapped.forEach(camp => {
      let bestEid = '';
      let bestScore = 2; // minimum threshold
      exps.forEach(e => {
        const nameToCheck = (e.experiment_name || '') + ' ' + e.experiment_id;
        const s = matchScore(nameToCheck, camp.campaign_name);
        if (s > bestScore) { bestScore = s; bestEid = e.experiment_id; }
      });
      if (bestEid) {
        if (!heuristicByExp[bestEid]) heuristicByExp[bestEid] = [];
        heuristicByExp[bestEid].push(buildCamp(camp));
      }
    });

    // Step 4: assemble final map
    const map: Record<string, ExpDetail> = {};
    exps.forEach(e => {
      const eid = e.experiment_id;
      const directCamps = mappedByExp[eid] || [];
      const heuristicCamps = heuristicByExp[eid] || [];
      const allExpCamps = [...directCamps, ...heuristicCamps].sort((a, b) => b.spend - a.spend);
      map[eid] = { campaigns: allExpCamps, exp: e };
    });

    return map;
  }, [data.experiment_campaigns, data.campaign_search_terms, data.experiments]);

  const filteredExpDetails = useMemo(() => {
    const map = expDetails;
    if (!filters.family && !filters.experiment) return map;
    return Object.fromEntries(
      Object.entries(map).filter(([eid, d]) => {
        if (filters.experiment && eid !== filters.experiment) return false;
        if (filters.family && (!d.exp || !experimentMatchesFamily(d.exp.experiment_name || d.exp.experiment_id, filters.family))) return false;
        return true;
      })
    );
  }, [expDetails, filters.family, filters.experiment]);

  const filteredCheckData = useMemo(() => {
    const cd = allCheckData;
    const out = { ...cd };
    const filterExpRows = (key: string) => {
      const item = cd[key];
      if (!item?.expIds) return;
      const keep = item.expIds
        .map((eid, i) => ({ eid, i }))
        .filter(({ eid }) => {
          if (filters.experiment && eid !== filters.experiment) return false;
          const d = expDetails[eid];
          if (filters.family && (!d?.exp || !experimentMatchesFamily(d.exp.experiment_name || d.exp.experiment_id, filters.family))) return false;
          return true;
        });
      out[key] = {
        ...item,
        rows: keep.map(({ i }) => item.rows[i]),
        expIds: keep.map(({ eid }) => eid),
      };
    };
    filterExpRows('experiments_status');
    filterExpRows('campaigns_live');
    return out;
  }, [allCheckData, expDetails, filters.family, filters.experiment]);

  const holidayNames = useMemo(() => {
    const holidays = data.holidays || [];
    const names = [...new Set(holidays.filter(h => h.category === 'gift_season' || h.category === 'prime_event').map(h => h.holiday_name))].sort();
    return names;
  }, [data.holidays]);

  const activeHolidayName = selectedHoliday || pk?.holiday_name || '';

  // Peak Relevance: coach recommendation per family for the active holiday
  // Respects the family filter — if set, only shows that family
  const relevanceForHoliday = useMemo(() => {
    const rows = data.peak_relevance || [];
    if (!activeHolidayName) return [];
    // Match by holiday name — pick the latest year's data for each family
    const matching = rows.filter(r => r.holiday_name === activeHolidayName);
    // Group by family, pick most recent holiday_date per family
    const byFamily: Record<string, PeakRelevanceRow> = {};
    matching.forEach(r => {
      if (filters.family && r.family !== filters.family) return; // respect family filter
      if (!byFamily[r.family] || r.holiday_date > byFamily[r.family].holiday_date) {
        byFamily[r.family] = r;
      }
    });
    return Object.values(byFamily).sort((a, b) => a.family.localeCompare(b.family));
  }, [data.peak_relevance, activeHolidayName, filters.family]);

  // Check if any family sees this as a real peak
  const anyRelevantPeak = relevanceForHoliday.some(r => r.is_relevant_peak);

  // Peak Impact Ranking: families sorted by order change % (highest impact first)
  // Used in the "Peak Impact by Family" section
  const peakImpactRanking = useMemo(() => {
    return [...relevanceForHoliday]
      .filter(r => r.orders_change_pct != null)
      .sort((a, b) => (b.orders_change_pct ?? 0) - (a.orders_change_pct ?? 0));
  }, [relevanceForHoliday]);

  // Relevance lookup by holiday name (for dropdown badge)
  const holidayRelevanceSummary = useMemo(() => {
    const rows = data.peak_relevance || [];
    const map: Record<string, { relevant: number; total: number }> = {};
    rows.forEach(r => {
      if (!map[r.holiday_name]) map[r.holiday_name] = { relevant: 0, total: 0 };
      map[r.holiday_name].total++;
      if (r.is_relevant_peak) map[r.holiday_name].relevant++;
    });
    return map;
  }, [data.peak_relevance]);

  const phaseComparison = useMemo(() => {
    const holidays = data.holidays || [];
    const wt = data.weekly_trends || [];
    if (!activeHolidayName || !wt.length) return null;

    const matching = holidays.filter(h => h.holiday_name === activeHolidayName && h.pre_season_start).sort((a, b) => a.holiday_date.localeCompare(b.holiday_date));
    if (matching.length < 2) return null;

    // TY = the holiday matching the current peak (or the next upcoming one)
    const today = new Date().toISOString().slice(0, 10);
    const pkDate = pk?.holiday_date || '';
    const tyHoliday = matching.find(h => h.holiday_date === pkDate)
      || matching.find(h => h.holiday_date >= today)
      || matching[matching.length - 1];
    // LY = the one immediately before TY
    const tyIdx = matching.indexOf(tyHoliday);
    const lyHoliday = tyIdx > 0 ? matching[tyIdx - 1] : matching.find(h => h.holiday_date < tyHoliday.holiday_date) || matching[0];
    if (tyHoliday === lyHoliday) return null;
    const tyPhases = phaseBoundaries(tyHoliday);
    const lyPhases = phaseBoundaries(lyHoliday);

    type FamAgg = { sales: number; adCost: number; cogs: number; netProfit: number; orders: number; clicks: number };
    const emptyFam = (): FamAgg => ({ sales: 0, adCost: 0, cogs: 0, netProfit: 0, orders: 0, clicks: 0 });

    const aggregate = (rows: typeof wt) => {
      const byFam: Record<string, FamAgg> = {};
      FAMILY_NAMES.forEach(f => { byFam[f] = emptyFam(); });
      byFam['Total'] = emptyFam();
      rows.forEach(r => {
        const fam = famFromType(r.product_type);
        if (fam && byFam[fam as string]) {
          const b = byFam[fam as string];
          b.sales += r.sales || 0; b.adCost += r.ad_cost || 0; b.cogs += r.cogs || 0;
          b.netProfit += r.net_profit || 0; b.orders += r.orders || 0; b.clicks += r.clicks || 0;
        }
        const t = byFam['Total'];
        t.sales += r.sales || 0; t.adCost += r.ad_cost || 0; t.cogs += r.cogs || 0;
        t.netProfit += r.net_profit || 0; t.orders += r.orders || 0; t.clicks += r.clicks || 0;
      });
      return byFam;
    };

    const inRange = (ws: string, range: { start: string; end: string }) => ws >= range.start && ws <= range.end;

    const result: Record<PhaseKey | 'full', { ty: Record<string, FamAgg>; ly: Record<string, FamAgg>; tyRange: string; lyRange: string }> = {} as any;
    for (const phase of [...PHASE_KEYS, 'full' as const]) {
      const tyR = tyPhases[phase];
      const lyR = lyPhases[phase];
      result[phase] = {
        ty: aggregate(wt.filter(r => inRange(r.week_start || '', tyR))),
        ly: aggregate(wt.filter(r => inRange(r.week_start || '', lyR))),
        tyRange: `${tyR.start} – ${tyR.end}`,
        lyRange: `${lyR.start} – ${lyR.end}`,
      };
    }

    return {
      phases: result,
      tyHoliday: `${tyHoliday.holiday_name} (${tyHoliday.holiday_date})`,
      lyHoliday: `${lyHoliday.holiday_name} (${lyHoliday.holiday_date})`,
    };
  }, [data.holidays, data.weekly_trends, activeHolidayName]);

  // Legacy aggregate yoyData for backward compatibility
  const yoyData = useMemo(() => {
    if (phaseComparison) {
      const full = phaseComparison.phases.full;
      return { ly: full.ly, ty: full.ty, lyRange: full.lyRange, tyRange: full.tyRange, lyWeeks: 0, tyWeeks: 0 };
    }
    if (!pk) return null;
    const wt = data.weekly_trends || [];
    const readinessStart = pk.pre_peak_start || pk.peak_start;
    const thisYearEnd = pk.peak_end;
    if (!readinessStart || !thisYearEnd) return null;
    const lyStart = shiftYear(readinessStart, -1);
    const lyEnd = shiftYear(thisYearEnd, -1);
    const aggregate = (rows: typeof wt) => {
      const byFam: Record<string, { sales: number; adCost: number; cogs: number; netProfit: number; orders: number; weeks: number }> = {};
      FAMILY_NAMES.forEach(f => { byFam[f] = { sales: 0, adCost: 0, cogs: 0, netProfit: 0, orders: 0, weeks: 0 }; });
      rows.forEach(r => {
        const fam = famFromType(r.product_type);
        if (fam && byFam[fam as string]) {
          const b = byFam[fam as string];
          b.sales += r.sales || 0; b.adCost += r.ad_cost || 0; b.cogs += r.cogs || 0;
          b.netProfit += r.net_profit || 0; b.orders += r.orders || 0; b.weeks += 1;
        }
      });
      return byFam;
    };
    const lyRows = wt.filter(r => (r.week_start || '') >= lyStart && (r.week_start || '') <= lyEnd);
    const tyRows = wt.filter(r => (r.week_start || '') >= readinessStart && (r.week_start || '') <= thisYearEnd);
    return { ly: aggregate(lyRows), ty: aggregate(tyRows), lyRange: `${lyStart} – ${lyEnd}`, tyRange: `${readinessStart} – ${thisYearEnd}`, lyWeeks: lyRows.length, tyWeeks: tyRows.length };
  }, [data.weekly_trends, pk, phaseComparison]);

  const peakTrendData = useMemo(() => {
    const holidays = data.holidays || [];
    const wt = data.weekly_trends || [];
    if (!activeHolidayName || !wt.length) return null;

    const matching = holidays.filter(h => h.holiday_name === activeHolidayName && h.pre_season_start).sort((a, b) => a.holiday_date.localeCompare(b.holiday_date));
    if (matching.length < 2) return null;

    const today = new Date().toISOString().slice(0, 10);
    const pkDate = pk?.holiday_date || '';
    const tyHoliday = matching.find(h => h.holiday_date === pkDate) || matching.find(h => h.holiday_date >= today) || matching[matching.length - 1];
    const tyIdx2 = matching.indexOf(tyHoliday);
    const lyHoliday = tyIdx2 > 0 ? matching[tyIdx2 - 1] : matching.find(h => h.holiday_date < tyHoliday.holiday_date) || matching[0];
    if (tyHoliday === lyHoliday) return null;

    const tyPhases = phaseBoundaries(tyHoliday);
    const lyPhases = phaseBoundaries(lyHoliday);
    // Floor the start at peak − 35d so single-phase events (e.g. Prime Day, whose
    // pre_season_start = the peak day) still span several weeks; without this the weekly
    // window collapses to ~0 weeks and the whole trend card is hidden.
    const tyFloorW = addDaysLocal(tyHoliday.holiday_date, -35);
    const lyFloorW = addDaysLocal(lyHoliday.holiday_date, -35);
    const tyStart = tyPhases.pre_season.start < tyFloorW ? tyPhases.pre_season.start : tyFloorW;
    const tyEnd = tyHoliday.holiday_date; // stop at peak day (0 days from peak)
    const lyStart = lyPhases.pre_season.start < lyFloorW ? lyPhases.pre_season.start : lyFloorW;
    const lyEnd = lyHoliday.holiday_date;

    // Get unique sorted weeks for TY and LY — cap at holiday date
    const tyWeeks = [...new Set(wt.filter(r => (r.week_start || '') >= tyStart && (r.week_start || '') <= tyEnd).map(r => r.week_start || ''))].sort();
    const lyWeeks = [...new Set(wt.filter(r => (r.week_start || '') >= lyStart && (r.week_start || '') <= lyEnd).map(r => r.week_start || ''))].sort();
    const maxLen = Math.max(tyWeeks.length, lyWeeks.length);
    if (maxLen === 0) return null;

    const aggWeek = (rows: typeof wt, week: string) => {
      let sales = 0, adCost = 0, orders = 0, cogs = 0, netProfit = 0;
      rows.filter(r => r.week_start === week).forEach(r => {
        if (!filters.family || famFromType(r.product_type) === filters.family) {
          sales += r.sales || 0; adCost += r.ad_cost || 0; orders += r.orders || 0;
          cogs += r.cogs || 0; netProfit += r.net_profit || 0;
        }
      });
      return { sales, adCost, orders, netProfit };
    };

    const daysToPeakLabel = (weekStr: string, holidayDate: string) => {
      const wMs = new Date(weekStr + 'T00:00:00').getTime();
      const hMs = new Date(holidayDate + 'T00:00:00').getTime();
      const diffDays = Math.round((wMs - hMs) / 86400000);
      const diffWeeks = Math.round(diffDays / 7);
      if (Math.abs(diffDays) <= 3) return 'Peak';
      return diffWeeks > 0 ? `+${diffWeeks}w` : `${diffWeeks}w`;
    };
    const tyData = tyWeeks.map(w => ({ ...aggWeek(wt, w), label: daysToPeakLabel(w, tyHoliday.holiday_date) }));
    const lyData = lyWeeks.map(w => ({ ...aggWeek(wt, w), label: daysToPeakLabel(w, lyHoliday.holiday_date) }));

    // Calculate phase boundaries as week indices
    const weekIdx = (weeks: string[], dateStr: string) => {
      for (let i = 0; i < weeks.length; i++) { if (weeks[i] >= dateStr) return i; }
      return weeks.length;
    };
    const tyBoostIdx = weekIdx(tyWeeks, tyPhases.boost.start);
    const tyPeakIdx = weekIdx(tyWeeks, tyPhases.peak.start);

    return { tyData, lyData, maxLen, tyWeeks, lyWeeks, tyBoostIdx, tyPeakIdx, tyRange: `${tyStart} – ${tyEnd}`, lyRange: `${lyStart} – ${lyEnd}` };
  }, [data.holidays, data.weekly_trends, activeHolidayName, filters.family]);

  // ── Per-day peak performance from daily_trends (past 7 days only) ──
  const dailyPeakData = useMemo(() => {
    const dt = data.daily_trends || [];
    if (!dt.length) return null;

    const today = new Date().toISOString().slice(0, 10);
    const d7ago = new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10);

    const byDate: Record<string, { date: string; sales: number; spend: number; orders: number; clicks: number; sessions: number; cogs: number; netProfit: number }> = {};
    dt.forEach(r => {
      const d = r.date;
      if (!d || d < d7ago || d > today) return;
      if (filters.family && famFromType(r.product_type) !== filters.family) return;
      if (!byDate[d]) byDate[d] = { date: d, sales: 0, spend: 0, orders: 0, clicks: 0, sessions: 0, cogs: 0, netProfit: 0 };
      byDate[d].sales += r.sales || 0;
      byDate[d].spend += r.ad_cost || 0;
      byDate[d].orders += r.orders || 0;
      byDate[d].clicks += r.clicks || 0;
      byDate[d].sessions += r.sessions || 0;
      byDate[d].cogs += r.cogs || 0;
      byDate[d].netProfit += r.net_profit || 0;
    });

    const sorted = Object.values(byDate).sort((a, b) => a.date.localeCompare(b.date));
    if (sorted.length === 0) return null;

    const totalSales = sorted.reduce((s, d) => s + d.sales, 0);
    const totalSpend = sorted.reduce((s, d) => s + d.spend, 0);
    const totalOrders = sorted.reduce((s, d) => s + d.orders, 0);
    return { days: sorted, totalSales, totalSpend, totalOrders, today };
  }, [data.daily_trends, filters.family]);

  // ── True daily-grain data for "Daily" peak trend chart (TY vs LY) ──
  // Both TY and LY use daily_trends (now 18 months of data), one bar per day, aligned by days-to-peak
  const dailyPeakTrendData = useMemo(() => {
    const holidays = data.holidays || [];
    const dt = data.daily_trends || [];
    if (!activeHolidayName || !dt.length) return null;

    const matching = holidays.filter(h => h.holiday_name === activeHolidayName && h.pre_season_start).sort((a, b) => a.holiday_date.localeCompare(b.holiday_date));
    if (matching.length < 2) return null;

    const today = new Date().toISOString().slice(0, 10);
    const pkDate = pk?.holiday_date || '';
    const tyHoliday = matching.find(h => h.holiday_date === pkDate) || matching.find(h => h.holiday_date >= today) || matching[matching.length - 1];
    const tyIdx2 = matching.indexOf(tyHoliday);
    const lyHoliday = tyIdx2 > 0 ? matching[tyIdx2 - 1] : matching.find(h => h.holiday_date < tyHoliday.holiday_date) || matching[0];
    if (tyHoliday === lyHoliday) return null;

    const tyPhases = phaseBoundaries(tyHoliday);
    const lyPhases = phaseBoundaries(lyHoliday);

    const daysToPeak = (dateStr: string, holidayDate: string) =>
      Math.round((new Date(dateStr + 'T00:00:00').getTime() - new Date(holidayDate + 'T00:00:00').getTime()) / 86400000);
    const daysToPeakLabel = (diff: number) => {
      if (diff === 0) return 'Peak';
      return diff > 0 ? `+${diff}d` : `${diff}d`;
    };

    // Helper: build daily bars from daily_trends for a date range
    const buildDailyBars = (startDate: string, endDate: string, holidayDate: string) => {
      const dates = [...new Set(
        dt.filter(r => r.date >= startDate && r.date <= endDate).map(r => r.date)
      )].sort();
      const bars: { sales: number; adCost: number; orders: number; netProfit: number; label: string; dtp: number }[] = [];
      for (const dateStr of dates) {
        let sales = 0, adCost = 0, orders = 0, netProfit = 0;
        dt.filter(r => r.date === dateStr).forEach(r => {
          if (!filters.family || famFromType(r.product_type) === filters.family) {
            sales += r.sales || 0; adCost += r.ad_cost || 0; orders += r.orders || 0;
            netProfit += r.net_profit || 0;
          }
        });
        const dtp = daysToPeak(dateStr, holidayDate);
        bars.push({ sales, adCost, orders, netProfit, label: daysToPeakLabel(dtp), dtp });
      }
      return bars;
    };

    // Floor the start at peak − 30d so single-phase events (e.g. Prime Day, whose
    // pre_season_start = the peak day itself) still have pre-peak data for the window
    // filter. Long-ramp holidays keep their earlier pre_season_start via the min.
    const tyFloor = addDaysLocal(tyHoliday.holiday_date, -30);
    const lyFloor = addDaysLocal(lyHoliday.holiday_date, -30);
    const tyStart = tyPhases.pre_season.start < tyFloor ? tyPhases.pre_season.start : tyFloor;
    const tyEnd = today; // include today even if past peak
    const lyStart = lyPhases.pre_season.start < lyFloor ? lyPhases.pre_season.start : lyFloor;
    const lyEnd = addDaysLocal(lyHoliday.holiday_date, 14); // include 2 weeks post-peak for LY

    const tyData = buildDailyBars(tyStart, tyEnd, tyHoliday.holiday_date);
    const lyData = buildDailyBars(lyStart, lyEnd, lyHoliday.holiday_date);

    const tyHolidayDate = tyHoliday.holiday_date;
    const lyHolidayDate = lyHoliday.holiday_date;

    if (tyData.length === 0 && lyData.length === 0) return null;

    // Align both series on a shared days-to-peak axis
    const allDtp = [...new Set([...tyData.map(d => d.dtp), ...lyData.map(d => d.dtp)])].sort((a, b) => a - b);
    const maxLen = allDtp.length;

    // Phase boundary indices
    const tyBoostDtp = daysToPeak(tyPhases.boost.start, tyHoliday.holiday_date);
    const tyPeakDtp = daysToPeak(tyPhases.peak.start, tyHoliday.holiday_date);
    const tyBoostIdx = allDtp.findIndex(d => d >= tyBoostDtp);
    const tyPeakIdx = allDtp.findIndex(d => d >= tyPeakDtp);

    const tyRange = `${tyStart} – ${tyEnd}`;
    const lyRange = `${lyStart} – ${lyEnd}`;

    return { tyData, lyData, maxLen, allDtp, tyBoostIdx: tyBoostIdx >= 0 ? tyBoostIdx : maxLen, tyPeakIdx: tyPeakIdx >= 0 ? tyPeakIdx : maxLen, tyRange, lyRange, isAlignedByDtp: true as const, tyHolidayDate, lyHolidayDate };
  }, [data.holidays, data.daily_trends, activeHolidayName, filters.family]);

  // ── LY top search terms with % contribution ──
  const lyTopTerms = useMemo(() => {
    const holidays = data.holidays || [];
    if (!activeHolidayName) return null;
    // Look up LAST YEAR's actual occasion row — Prime Day moves year to year
    // (2025: Jul 8-11, 2026: Jun 23-26), so a naive -1yr shift lands on the wrong dates.
    const matching = holidays.filter(h => h.holiday_name === activeHolidayName && h.pre_season_start)
      .sort((a, b) => a.holiday_date.localeCompare(b.holiday_date));
    if (matching.length < 2) return null;
    const today = new Date().toISOString().slice(0, 10);
    const pkDate = pk?.holiday_date || '';
    const tyHoliday = matching.find(h => h.holiday_date === pkDate) || matching.find(h => h.holiday_date >= today) || matching[matching.length - 1];
    const tyIdx = matching.indexOf(tyHoliday);
    const lyHoliday = tyIdx > 0 ? matching[tyIdx - 1] : matching.find(h => h.holiday_date < tyHoliday.holiday_date) || matching[0];
    if (tyHoliday === lyHoliday) return null;
    // LY peak window = last year's ACTUAL peak_start → holiday_date
    const lyPeakStart = phaseBoundaries(lyHoliday).peak.start;
    const lyPeakEnd = lyHoliday.holiday_date;

    // 2-week baseline window immediately before the peak (for daily-avg purchase delta)
    const baseStart = addDaysLocal(lyPeakStart, -14);
    const baseEnd = addDaysLocal(lyPeakStart, -1);

    // SQP is weekly grain — include any week that OVERLAPS the target window
    const sqp = data.sqp_weekly || [];
    const overlaps = (wk: string, s: string, e: string) => wk <= e && addDaysLocal(wk, 6) >= s;
    const peakRows = sqp.filter(s => overlaps(s.week_start, lyPeakStart, lyPeakEnd));
    const baseRows = sqp.filter(s => overlaps(s.week_start, baseStart, baseEnd));
    if (peakRows.length === 0) return null;

    // Days in each window (weekly grain → distinct weeks × 7) for daily-average math
    const peakDays = (new Set(peakRows.map(r => r.week_start)).size || 1) * 7;
    const baseDays = (new Set(baseRows.map(r => r.week_start)).size || 1) * 7;

    type Agg = { term: string; orders: number; impressions: number; clicks: number; amzVolume: number; amzSales: number; families: Set<string>; baseOrders: number };
    const termAgg: Record<string, Agg> = {};
    const ensure = (term: string) => (termAgg[term] ||= { term, orders: 0, impressions: 0, clicks: 0, amzVolume: 0, amzSales: 0, families: new Set(), baseOrders: 0 });
    peakRows.forEach(s => {
      const a = ensure(s.search_term);
      a.orders += s.orders || 0;
      a.impressions += s.impressions || 0;
      a.clicks += s.clicks || 0;
      a.amzVolume += s.amazon_impressions || 0;   // total Amazon search volume for the term
      a.amzSales += s.amazon_orders || 0;          // total Amazon purchases (market-wide) for the term
      const fam = famFromType(s.product_type);
      if (fam) a.families.add(String(fam));
    });
    baseRows.forEach(s => { ensure(s.search_term).baseOrders += s.orders || 0; });

    const sorted = Object.values(termAgg).sort((a, b) => b.orders - a.orders);
    const totalOrders = sorted.reduce((s, t) => s + t.orders, 0);
    const top20 = sorted.slice(0, 20);
    const top20Orders = top20.reduce((s, t) => s + t.orders, 0);
    const top20Pct = totalOrders > 0 ? (top20Orders / totalOrders) * 100 : 0;

    return {
      terms: top20.map(t => {
        const peakDaily = t.orders / peakDays;
        const baseDaily = t.baseOrders / baseDays;
        return {
          term: t.term,
          orders: t.orders,
          impressions: t.impressions,
          clicks: t.clicks,
          amzVolume: t.amzVolume,
          amzSales: t.amzSales,
          pctOfTotal: totalOrders > 0 ? (t.orders / totalOrders) * 100 : 0,
          families: [...t.families].join(', '),
          peakDaily,
          baseDaily,
          dailyDelta: peakDaily - baseDaily,                                   // abs change in purchases/day
          dailyDeltaPct: baseDaily > 0 ? ((peakDaily - baseDaily) / baseDaily) * 100 : null, // null = no baseline (new at peak)
        };
      }),
      totalOrders,
      top20Pct,
      dateRange: `${lyPeakStart} – ${lyPeakEnd}`,
      baselineRange: `${baseStart} – ${baseEnd}`,
    };
  }, [data.sqp_weekly, data.holidays, activeHolidayName, pk]);

  // Sort state for the LY top-terms table
  const [lyTermSort, setLyTermSort] = useState<{ key: 'orders' | 'pctOfTotal' | 'dailyDelta' | 'amzVolume' | 'amzSales' | 'impressions' | 'clicks'; dir: 'asc' | 'desc' }>({ key: 'orders', dir: 'desc' });
  const lyTermsSorted = useMemo(() => {
    if (!lyTopTerms) return [];
    const { key, dir } = lyTermSort;
    const m = dir === 'asc' ? 1 : -1;
    return [...lyTopTerms.terms].sort((a, b) => (((a[key] ?? -Infinity) as number) - ((b[key] ?? -Infinity) as number)) * m);
  }, [lyTopTerms, lyTermSort]);
  const lyTermArrow = (k: typeof lyTermSort.key) => (lyTermSort.key === k ? (lyTermSort.dir === 'desc' ? ' ↓' : ' ↑') : '');
  const lyTermSortBy = (k: typeof lyTermSort.key) => setLyTermSort(s => ({ key: k, dir: s.key === k && s.dir === 'desc' ? 'asc' : 'desc' }));

  // ── Peak Keyword Plan: Research-style buckets, from V_PEAK_KEYWORD_RECS ──
  const peakKwRecs = useMemo(() => {
    const all = (data.peak_keyword_recs || []).filter(r =>
      r.holiday_name === activeHolidayName && (!filters.family || r.parent_name === filters.family));
    if (!all.length) return null;
    const byPriority = (a: PeakKeywordRecRow, b: PeakKeywordRecRow) => b.priority_score - a.priority_score;
    // INCREASE = existing terms to boost; trending first
    const increase = all.filter(r => r.match_bucket === 'INCREASE')
      .sort((a, b) => (Number(b.is_trending) - Number(a.is_trending)) || byPriority(a, b));
    // New-term buckets mirror Research: only fit-qualified (ADD = rank>75)
    const addOf = (b: string) => all.filter(r => r.match_bucket === b && r.recommendation === 'ADD').sort(byPriority);
    return {
      increase,
      exact: addOf('EXACT'),
      phrase: addOf('PHRASE'),
      broad: addOf('BROAD'),
      brand: all.filter(r => r.match_bucket === 'BRAND').sort(byPriority),
      trendingCount: increase.filter(r => r.is_trending).length,
      addCount: all.filter(r => r.recommendation === 'ADD').length,
    };
  }, [data.peak_keyword_recs, activeHolidayName, filters.family]);

  // ── Per-product peak actions: roll the recs up to one action line per product ──
  const peakProductActions = useMemo(() => {
    const all = (data.peak_keyword_recs || []).filter(r =>
      r.holiday_name === activeHolidayName && (!filters.family || r.parent_name === filters.family));
    if (!all.length) return null;
    const byFam: Record<string, { family: string; boost: number; trending: number; add: number; cautious: number; defense: number }> = {};
    all.forEach(r => {
      const f = (byFam[r.parent_name] ||= { family: r.parent_name, boost: 0, trending: 0, add: 0, cautious: 0, defense: 0 });
      if (r.recommendation === 'INCREASE') { f.boost++; if (r.is_trending) f.trending++; }
      else if (r.recommendation === 'INCREASE_CAUTIOUS') f.cautious++;
      else if (r.recommendation === 'ADD') f.add++;
      else if (r.recommendation === 'DEFENSE') f.defense++;
    });
    return Object.values(byFam)
      .map(f => ({ ...f, action: (f.add >= 3 && f.add >= f.boost) ? 'NEW_CAMPAIGN' : f.boost > 0 ? 'SCALE' : f.add > 0 ? 'ADD_KW' : 'MONITOR' }))
      .sort((a, b) => (b.boost + b.add) - (a.boost + a.add));
  }, [data.peak_keyword_recs, activeHolidayName, filters.family]);

  // ── Stuck campaigns to refresh before the peak ──
  const peakStuck = useMemo(() => {
    const rows = (data.peak_stuck_campaigns || []).filter(c => !filters.family || c.parent_name === filters.family);
    if (!rows.length) return null;
    const order: Record<string, number> = { BUDGET_CAPPED: 0, PAUSED: 1, DORMANT: 2, SHARE_DROPPED: 3 };
    return [...rows].sort((a, b) => (order[a.stuck_flag] ?? 9) - (order[b.stuck_flag] ?? 9) || a.parent_name.localeCompare(b.parent_name));
  }, [data.peak_stuck_campaigns, filters.family]);

  // Export the full peak keyword plan (active holiday) as a CSV the team can action.
  const exportPeakRecsCsv = () => {
    const rows = (data.peak_keyword_recs || [])
      .filter(r => r.holiday_name === activeHolidayName && (!filters.family || r.parent_name === filters.family))
      .sort((a, b) => a.parent_name.localeCompare(b.parent_name) || b.priority_score - a.priority_score);
    if (!rows.length) return;
    const hdr = ['Family', 'Search Term', 'Bucket', 'Recommendation', 'Trending', 'Amazon Volume', 'Amazon Sales', 'Net ROAS', 'Research Rank', 'Priority', 'Reason'];
    const esc = (v: unknown) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const csv = [
      hdr.join(','),
      ...rows.map(r => [r.parent_name, r.search_term, r.match_bucket, r.recommendation, r.is_trending ? 'yes' : '',
        r.amazon_volume, r.amazon_sales, r.ly_net_roas ?? '', r.research_rank ?? '', r.priority_score, r.reason].map(esc).join(',')),
    ].join('\n');
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `peak-keyword-plan-${activeHolidayName.replace(/\s+/g, '-')}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  usePageSummary({ title: 'Peak', items: [{ label: 'Peak Planning', value: pk ? 'Active' : 'Inactive' }] });

  if (!pk) return <Empty icon="⛰️" message="No upcoming peak" hint="Peak planning activates when a holiday or event is within 6 weeks." />;

  const ci = STAGES.indexOf(pk.current_stage as typeof STAGES[number]);
  const dates = [pk.pre_peak_start, pk.boost_start, pk.peak_start, pk.holiday_date]
    .map(d => d ? new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : '--');

  const toggleStage = (i: number) => setOpenStages(p => { const n = new Set(p); n.has(i) ? n.delete(i) : n.add(i); return n; });
  const toggleItem = (key: string) => setExpandedItems(p => { const n = new Set(p); n.has(key) ? n.delete(key) : n.add(key); return n; });

  const peakFilterItems = formatSectionFilters(filters);
  return (
    <div className="animate-in">
      <div className="flex items-center gap-2 mb-5">
        <PageHeader title="Next Peak" subtitle="Peak season readiness" />
        {peakFilterItems.length > 0 && <FilterInfoIcon items={peakFilterItems} />}
      </div>

      <Card className={`!border-l-[3px] mb-6 ${ci >= 2 ? '!border-l-red-500' : ci >= 1 ? '!border-l-amber-500' : '!border-l-blue-500'}`}>
        <div className="flex justify-between items-start mb-2.5">
          <div>
            <div className="text-xl font-extrabold tracking-tight">NEXT PEAK: {pk.holiday_name || '--'}</div>
            <div className="text-xs text-subtle mt-1">
              Holiday: {pk.holiday_date || '--'} · Peak Start: {pk.peak_start || '--'} · Peak End: {pk.peak_end || '--'}
            </div>
          </div>
          <div className="text-right">
            <Badge variant={ci === 0 ? 'blue' : ci === 1 ? 'amber' : 'red'} className="!text-xs">
              {STAGE_LABELS[pk.current_stage] || pk.current_stage || '--'}
            </Badge>
            {pk.days_until_peak_start != null && (
              <div className="font-mono text-[11px] text-subtle mt-1">
                {pk.days_until_peak_start > 0 ? `${pk.days_until_peak_start} days to peak` : 'Peak active'}
              </div>
            )}
          </div>
        </div>
        <div className="flex h-9 rounded-xl overflow-hidden mb-3.5 text-[10px] font-semibold">
          {STAGES.map((s, i) => (
            <div key={s} className={`flex items-center justify-center text-white/85 px-2 min-w-[44px] bg-gradient-to-br ${STAGE_COLORS[s]} ${i === ci ? 'outline outline-2 outline-white -outline-offset-2 z-[1]' : ''}`} style={{ flex: 1 }}>
              {STAGE_LABELS[s]}
            </div>
          ))}
        </div>
        <div className="flex text-[10px] text-faint font-mono">
          {dates.map((d, i) => <span key={i} className="flex-1 text-center">{d}</span>)}
        </div>
      </Card>

      {/* Peak Impact by Family + Coach Recommendation */}
      {peakImpactRanking.length > 0 && (
        <Card className="mb-6">
          <div className="flex items-center gap-2 mb-4">
            <Zap size={14} className="text-amber-400" />
            <span className="text-sm font-bold">Peak Impact by Family — {activeHolidayName}</span>
            {!anyRelevantPeak && (
              <Badge variant="red" className="!text-[9px] ml-2">Not a Peak for Your Products</Badge>
            )}
            {anyRelevantPeak && (
              <Badge variant="green" className="!text-[9px] ml-2">{relevanceForHoliday.filter(r => r.is_relevant_peak).length} of {relevanceForHoliday.length} families peak</Badge>
            )}
          </div>

          {/* Impact Bars — visual ranking */}
          <div className="space-y-2 mb-5">
            {peakImpactRanking.map(r => {
              const pct = r.orders_change_pct ?? 0;
              const maxPct = Math.max(...peakImpactRanking.map(x => Math.abs(x.orders_change_pct ?? 0)), 1);
              const barW = Math.min(Math.abs(pct) / maxPct * 100, 100);
              const isPositive = pct > 0;
              const recLabel: Record<string, string> = {
                AGGRESSIVE_BOOST: '🚀 Aggressive Boost',
                MODERATE_BOOST: '📈 Moderate Boost',
                CAUTIOUS_BOOST: '⚠️ Cautious Boost',
                HOLD: '⏸ Hold',
                REDUCE: '📉 Reduce',
              };
              const barColor = isPositive
                ? r.coach_recommendation === 'AGGRESSIVE_BOOST' ? 'bg-emerald-500/80' : 'bg-blue-500/70'
                : 'bg-red-500/60';
              return (
                <div key={r.family} className="flex items-center gap-3">
                  <div className="w-20 text-xs font-semibold text-right truncate">{r.family}</div>
                  <div className="flex-1 flex items-center gap-2 min-w-0">
                    <div className="flex-1 h-6 bg-zinc-800/60 rounded-md overflow-hidden relative">
                      <div
                        className={`h-full rounded-md ${barColor} transition-all duration-500`}
                        style={{ width: `${barW}%` }}
                      />
                      <div className="absolute inset-0 flex items-center px-2">
                        <span className={`text-[11px] font-bold font-mono ${barW > 30 ? 'text-white' : 'text-subtle'}`}>
                          {pct > 0 ? '+' : ''}{pct.toFixed(0)}% orders
                        </span>
                      </div>
                    </div>
                    <div className="w-40 text-[10px] font-semibold whitespace-nowrap">
                      <span className={`${isPositive ? 'text-emerald-400' : pct < -10 ? 'text-red-400' : 'text-zinc-400'}`}>
                        {recLabel[r.coach_recommendation] || r.coach_recommendation}
                      </span>
                      {r.confidence !== 'HIGH' && <span className="text-faint ml-1">({r.confidence})</span>}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>

          {/* Detailed Table */}
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-xs">
              <thead>
                <tr>
                  <Th>Family</Th>
                  <Th right>Baseline Ord/Day</Th>
                  <Th right>Peak Ord/Day</Th>
                  <Th right>Orders Δ</Th>
                  <Th right>Baseline ROAS</Th>
                  <Th right>Peak ROAS</Th>
                  <Th right>ROAS Δ</Th>
                  <Th>Coach Signal</Th>
                </tr>
              </thead>
              <tbody>
                {relevanceForHoliday.map(r => {
                  const recColor: Record<string, string> = {
                    AGGRESSIVE_BOOST: 'text-emerald-400',
                    MODERATE_BOOST: 'text-blue-400',
                    CAUTIOUS_BOOST: 'text-amber-400',
                    HOLD: 'text-zinc-400',
                    REDUCE: 'text-red-400',
                  };
                  const recIcon: Record<string, string> = {
                    AGGRESSIVE_BOOST: '🚀',
                    MODERATE_BOOST: '📈',
                    CAUTIOUS_BOOST: '⚠️',
                    HOLD: '⏸',
                    REDUCE: '📉',
                  };
                  const ordDelta = r.orders_change_pct;
                  return (
                    <tr key={r.family} className={`border-b border-border-faint hover:bg-white/[.02] ${!r.is_relevant_peak ? 'opacity-50' : ''}`}>
                      <td className="px-3 py-1.5 font-semibold">{r.family}</td>
                      <td className="px-3 py-1.5 text-right font-mono">{r.baseline_avg_daily_orders?.toFixed(1) ?? '—'}</td>
                      <td className="px-3 py-1.5 text-right font-mono">{r.peak_avg_daily_orders?.toFixed(1) ?? '—'}</td>
                      <td className={`px-3 py-1.5 text-right font-mono font-semibold ${(ordDelta ?? 0) > 0 ? 'text-emerald-400' : (ordDelta ?? 0) < -10 ? 'text-red-400' : 'text-zinc-400'}`}>
                        {ordDelta != null ? `${ordDelta > 0 ? '+' : ''}${ordDelta.toFixed(1)}%` : '—'}
                      </td>
                      <td className="px-3 py-1.5 text-right font-mono">{r.baseline_net_roas != null ? fR(r.baseline_net_roas) : '—'}</td>
                      <td className="px-3 py-1.5 text-right font-mono">{r.peak_net_roas != null ? fR(r.peak_net_roas) : '—'}</td>
                      <td className={`px-3 py-1.5 text-right font-mono font-semibold ${(r.net_roas_delta ?? 0) > 0 ? 'text-emerald-400' : (r.net_roas_delta ?? 0) < -0.1 ? 'text-red-400' : 'text-zinc-400'}`}>
                        {r.net_roas_delta != null ? `${r.net_roas_delta > 0 ? '+' : ''}${r.net_roas_delta.toFixed(2)}` : '—'}
                      </td>
                      <td className="px-3 py-1.5">
                        <span className={`font-semibold ${recColor[r.coach_recommendation] || 'text-zinc-400'}`}>
                          {recIcon[r.coach_recommendation] || ''} {r.coach_recommendation.replace(/_/g, ' ')}
                        </span>
                        {r.confidence !== 'HIGH' && (
                          <span className="text-[9px] text-faint ml-1">({r.confidence})</span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <div className="mt-2 text-[10px] text-faint italic">
            Based on last year's peak vs 4-week baseline. Only families with ≥12 months of data.
          </div>
        </Card>
      )}

      {/* Peak Trend Chart: TY vs LY — dynamic measure */}
      {((peakTrendGranularity === 'weekly' && peakTrendData && peakTrendData.maxLen > 0) || (peakTrendGranularity === 'daily' && dailyPeakTrendData && dailyPeakTrendData.maxLen > 0)) && (
        <Card className="mb-6">
          <div className="flex items-center justify-between mb-3">
            <div className="text-sm font-bold">Peak {PEAK_TREND_MEASURES.find(m => m.id === peakTrendMeasure)?.label || 'Orders'} Trend — TY vs LY</div>
            <div className="flex items-center gap-4 text-[10px] text-faint font-mono">
              <span className="flex items-center gap-1"><span className="w-3 h-2 rounded-sm inline-block" style={{ background: PEAK_TREND_MEASURES.find(m => m.id === peakTrendMeasure)?.color || '#3b82f6' }} /> TY {(peakTrendGranularity === 'daily' ? dailyPeakTrendData : peakTrendData)?.tyRange}{peakTrendGranularity === 'daily' && dailyPeakTrendData?.tyHolidayDate ? ` (peak: ${dailyPeakTrendData.tyHolidayDate})` : ''}</span>
              <span className="flex items-center gap-1"><span className="w-3 h-0.5 bg-amber-400 inline-block" style={{ borderTop: '2px dashed' }} /> LY {(peakTrendGranularity === 'daily' ? dailyPeakTrendData : peakTrendData)?.lyRange}{peakTrendGranularity === 'daily' && dailyPeakTrendData?.lyHolidayDate ? ` (peak: ${dailyPeakTrendData.lyHolidayDate})` : ''}</span>
            </div>
          </div>
          {/* Granularity toggle + Measure selector */}
          <div className="flex items-center gap-3 mb-3">
            <div className="flex rounded-lg border border-zinc-700 overflow-hidden">
              {(['weekly', 'daily'] as const).map(g => (
                <button key={g} onClick={() => setPeakTrendGranularity(g)}
                  className={`px-3 py-1 text-[10px] font-semibold transition-all ${peakTrendGranularity === g ? 'bg-zinc-700 text-white' : 'text-zinc-500 hover:text-zinc-300'}`}
                >{g === 'weekly' ? 'Weekly' : 'Daily'}</button>
              ))}
            </div>
            <div className="flex gap-1.5">
              {PEAK_TREND_MEASURES.map(m => (
                <button
                  key={m.id}
                  onClick={() => setPeakTrendMeasure(m.id)}
                  className="px-2.5 py-1 rounded-lg text-[10px] font-semibold border transition-all"
                  style={{
                    borderColor: peakTrendMeasure === m.id ? m.color : 'rgba(63,63,70,.45)',
                    background: peakTrendMeasure === m.id ? m.color + '20' : 'transparent',
                    color: peakTrendMeasure === m.id ? m.color : '#71717a',
                  }}
                >{m.label}</button>
              ))}
            </div>
            {/* Days-to-peak range selector */}
            <div className="flex rounded-lg border border-zinc-700 overflow-hidden ml-2">
              {([{ label: '-7/+3d', before: 7, after: 3 }, { label: '±7d', before: 7, after: 7 }, { label: '±14d', before: 14, after: 14 }, { label: '±30d', before: 30, after: 30 }, { label: 'All', before: 999, after: 999 }] as const).map(r => {
                const isActive = dtpRange.before === r.before && dtpRange.after === r.after;
                return (
                  <button key={r.label} onClick={() => setDtpRange({ before: r.before, after: r.after })}
                    className={`px-2.5 py-1 text-[10px] font-semibold transition-all ${isActive ? 'bg-zinc-700 text-white' : 'text-zinc-500 hover:text-zinc-300'}`}
                  >{r.label}</button>
                );
              })}
            </div>
          </div>
          {(() => {
            const activeTrendData = peakTrendGranularity === 'daily' ? dailyPeakTrendData : peakTrendData;
            if (!activeTrendData) return null;
            const mKey = peakTrendMeasure;
            const mColor = PEAK_TREND_MEASURES.find(m => m.id === mKey)?.color || '#3b82f6';

            // Apply dtpRange filter to daily data
            const isDailyDtp = peakTrendGranularity === 'daily' && 'allDtp' in activeTrendData;
            const tyDataRaw = activeTrendData.tyData;
            const lyDataRaw = activeTrendData.lyData;
            const filteredTy = isDailyDtp && dtpRange.before < 999
              ? tyDataRaw.filter((d: any) => d.dtp >= -dtpRange.before && d.dtp <= dtpRange.after)
              : tyDataRaw;
            const filteredLy = isDailyDtp && dtpRange.before < 999
              ? lyDataRaw.filter((d: any) => d.dtp >= -dtpRange.before && d.dtp <= dtpRange.after)
              : lyDataRaw;
            const tyData = filteredTy;
            const lyData = filteredLy;

            const getVal = (d: typeof tyData[0]) => d[mKey] || 0;
            const fmtVal = (v: number) => mKey === 'orders' ? fOrd(v) : fM(v);
            const fmtShort = (v: number) => {
              if (mKey === 'orders') return String(Math.round(v));
              if (Math.abs(v) >= 1000) return `$${(v / 1000).toFixed(1)}k`;
              return `$${Math.round(v)}`;
            };
            const W = 800, H = 260, PAD_L = 55, PAD_R = 10, PAD_T = 28, PAD_B = 30;
            const chartW = W - PAD_L - PAD_R;
            const chartH = H - PAD_T - PAD_B;
            const allVals = [...tyData.map(getVal), ...lyData.map(getVal)];
            const maxVal = Math.max(...allVals, 1) * 1.12; // 12% headroom for labels
            const yForVal = (v: number) => PAD_T + chartH - (v / maxVal) * chartH;

            // Rebuild shared axis after filtering
            const allDtp = isDailyDtp
              ? [...new Set([...tyData.map((d: any) => d.dtp), ...lyData.map((d: any) => d.dtp)])].sort((a: number, b: number) => a - b) as number[]
              : null;
            const axisLen = allDtp ? allDtp.length : (tyData.length || lyData.length);
            const barW = Math.max(6, Math.min(30, (chartW / axisLen) - 4));
            const xForAxisIdx = (i: number) => PAD_L + (i + 0.5) * (chartW / axisLen);

            // Recompute phase boundary indices for potentially filtered axis
            const origAllDtp = isDailyDtp ? (activeTrendData as any).allDtp as number[] : null;
            const origBoostDtp = origAllDtp ? origAllDtp[activeTrendData.tyBoostIdx] : undefined;
            const tyBoostIdx = isDailyDtp && allDtp && origBoostDtp !== undefined
              ? allDtp.findIndex(d => d >= origBoostDtp)
              : activeTrendData.tyBoostIdx;
            const tyPeakIdx = isDailyDtp && allDtp
              ? allDtp.findIndex(d => d >= 0)
              : activeTrendData.tyPeakIdx;

            // Map TY/LY points to x positions
            const tyPoints = isDailyDtp
              ? tyData.map(d => ({ ...d, x: xForAxisIdx(allDtp!.indexOf((d as any).dtp)) }))
              : tyData.map((d, i) => ({ ...d, x: xForAxisIdx(i) }));
            const lyPoints = isDailyDtp
              ? lyData.map(d => {
                  // Find nearest dtp position on shared axis
                  const dtp = (d as any).dtp as number;
                  let bestIdx = 0; let bestDist = Infinity;
                  allDtp!.forEach((v, i) => { const dist = Math.abs(v - dtp); if (dist < bestDist) { bestDist = dist; bestIdx = i; } });
                  return { ...d, x: xForAxisIdx(bestIdx) };
                })
              : lyData.map((d, i) => ({ ...d, x: xForAxisIdx(i) }));



            // Grid lines
            const gridLines = [0, 0.25, 0.5, 0.75, 1].map(f => ({
              y: PAD_T + chartH * (1 - f),
              label: fmtVal(maxVal * 0.89 * f), // scale back from headroom
            }));

            // X-axis labels from shared axis
            const xLabels = isDailyDtp && allDtp
              ? allDtp.map((dtp, i) => ({ x: xForAxisIdx(i), label: dtp === 0 ? 'Peak' : dtp > 0 ? `+${dtp}d` : `${dtp}d` }))
              : tyData.map((d, i) => ({ x: xForAxisIdx(i), label: d.label }));
            const labelStep = Math.max(1, Math.ceil(xLabels.length / 12));

            return (
              <svg viewBox={`0 0 ${W} ${H}`} className="w-full" style={{ maxHeight: 300 }}>
                {/* Grid */}
                {gridLines.map((g, i) => (
                  <g key={i}>
                    <line x1={PAD_L} x2={W - PAD_R} y1={g.y} y2={g.y} stroke="rgba(255,255,255,0.06)" strokeWidth={1} />
                    <text x={PAD_L - 4} y={g.y + 3} textAnchor="end" fill="rgba(255,255,255,0.3)" fontSize={8} fontFamily="monospace">{g.label}</text>
                  </g>
                ))}

                {/* Phase boundary markers */}
                {tyBoostIdx > 0 && tyBoostIdx < axisLen && (
                  <line x1={xForAxisIdx(tyBoostIdx) - barW / 2 - 2} x2={xForAxisIdx(tyBoostIdx) - barW / 2 - 2} y1={PAD_T} y2={PAD_T + chartH} stroke="rgba(251,191,36,0.4)" strokeWidth={1} strokeDasharray="3,3" />
                )}
                {tyPeakIdx > 0 && tyPeakIdx < axisLen && (
                  <>
                    <line x1={xForAxisIdx(tyPeakIdx) - barW / 2 - 2} x2={xForAxisIdx(tyPeakIdx) - barW / 2 - 2} y1={PAD_T} y2={PAD_T + chartH} stroke="rgba(239,68,68,0.4)" strokeWidth={1} strokeDasharray="3,3" />
                    <text x={xForAxisIdx(tyPeakIdx) - barW / 2 + 2} y={PAD_T + 8} fill="rgba(239,68,68,0.5)" fontSize={7} fontFamily="monospace">Peak</text>
                  </>
                )}

                {/* TY bars + value labels (offset left when LY present) */}
                {tyPoints.map((d, i) => {
                  const v = getVal(d);
                  const barY = yForVal(v);
                  const halfBar = barW / 2;
                  const xOff = lyPoints.length > 0 ? d.x - halfBar / 2 - 0.5 : d.x;
                  return (
                    <g key={`ty-${i}`}>
                      <rect
                        x={xOff - halfBar / 2}
                        y={barY}
                        width={lyPoints.length > 0 ? halfBar : barW}
                        height={Math.max(0, PAD_T + chartH - barY)}
                        rx={2}
                        fill={mColor}
                        opacity={0.7}
                      />
                      {/* TY value label above bar (only show if not too dense) */}
                      {axisLen <= 30 && (
                        <text
                          x={xOff}
                          y={Math.max(barY - 4, PAD_T - 2)}
                          textAnchor="middle"
                          fill={mColor}
                          fontSize={7}
                          fontFamily="monospace"
                          fontWeight="bold"
                        >{fmtShort(v)}</text>
                      )}
                    </g>
                  );
                })}

                {/* LY bars (yellow, offset right) + value labels */}
                {lyPoints.map((d, i) => {
                  const v = getVal(d);
                  const barY = yForVal(v);
                  const halfBar = barW / 2;
                  const xOff = d.x + halfBar / 2 + 0.5;
                  return (
                    <g key={`ly-${i}`}>
                      <rect
                        x={xOff - halfBar / 2}
                        y={barY}
                        width={halfBar}
                        height={Math.max(0, PAD_T + chartH - barY)}
                        rx={2}
                        fill="rgba(251,191,36,0.8)"
                        opacity={0.6}
                      />
                      {/* LY value label above bar (only show if not too dense) */}
                      {axisLen <= 30 && (
                        <text
                          x={xOff}
                          y={Math.max(barY - 4, PAD_T - 2)}
                          textAnchor="middle"
                          fill="rgba(251,191,36,0.7)"
                          fontSize={6}
                          fontFamily="monospace"
                        >{fmtShort(v)}</text>
                      )}
                    </g>
                  );
                })}

                {/* X-axis labels */}
                {xLabels.map((xl, i) => (
                  (axisLen <= 16 || i % labelStep === 0) && (
                    <text key={`xl-${i}`} x={xl.x} y={H - 6} textAnchor="middle" fill="rgba(255,255,255,0.35)" fontSize={peakTrendGranularity === 'daily' ? 5.5 : 7} fontFamily="monospace">{xl.label}</text>
                  )
                ))}
              </svg>
            );
          })()}
          {/* Notice when LY has no data for selected measure */}
          {(() => {
            const atd = peakTrendGranularity === 'daily' ? dailyPeakTrendData : peakTrendData;
            return atd && atd.lyData.length > 0 && atd.lyData.every((d: any) => (d[peakTrendMeasure] || 0) === 0) ? (
              <div className="text-[10px] text-amber-400/60 mt-1.5 font-mono">⚠ LY {PEAK_TREND_MEASURES.find(m => m.id === peakTrendMeasure)?.label} data not available for {atd.lyRange}</div>
            ) : null;
          })()}
          {peakTrendGranularity === 'daily' && (
            <div className="text-[9px] text-zinc-600 mt-1 font-mono">
              Each bar = one day · Day 0 = peak holiday · TY peak: {dailyPeakTrendData?.tyHolidayDate || '—'} · LY peak: {dailyPeakTrendData?.lyHolidayDate || '—'}
              {dtpRange.before < 999 && (dtpRange.before === dtpRange.after
                ? ` · Showing ±${dtpRange.before}d around peak`
                : ` · Showing ${dtpRange.before}d before → ${dtpRange.after}d after peak`)}
            </div>
          )}
        </Card>
      )}

      {/* ─── Per-Day Peak Performance (last 7 days) ─── */}
      {dailyPeakData && dailyPeakData.days.length > 0 && (
        <Card className="mb-6">
          <button onClick={() => setShowDailyPeak(p => !p)} className="flex items-center gap-2 w-full text-left mb-2">
            <Calendar size={16} className="text-red-400" />
            <span className="text-sm font-bold">Daily Performance</span>
            <Badge variant="red">LIVE</Badge>
            <span className="text-[10px] text-faint font-mono ml-1">Last {dailyPeakData.days.length} days · {fM(dailyPeakData.totalSales)} sales · {fOrd(dailyPeakData.totalOrders)} orders</span>
            <ChevronRight size={12} className={`text-faint ml-auto transition-transform ${showDailyPeak ? 'rotate-90' : ''}`} />
          </button>
          {showDailyPeak && (
            <div className="animate-in">
              {/* SVG bar chart */}
              <div className="mb-3">
                {(() => {
                  const days = dailyPeakData.days;
                  const today = dailyPeakData.today;
                  const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
                  const maxSales = Math.max(...days.map(d => d.sales), 1) * 1.15;
                  const W = 700, H = 180, PAD_L = 50, PAD_R = 10, PAD_T = 24, PAD_B = 34;
                  const chartW = W - PAD_L - PAD_R;
                  const chartH = H - PAD_T - PAD_B;
                  const barW = Math.max(16, Math.min(50, (chartW / days.length) - 8));
                  const xForIdx = (i: number) => PAD_L + (i + 0.5) * (chartW / days.length);
                  const yForVal = (v: number) => PAD_T + chartH - (v / maxSales) * chartH;
                  const gridLines = [0, 0.25, 0.5, 0.75, 1].map(f => ({ y: PAD_T + chartH * (1 - f), label: fM(maxSales * 0.87 * f) }));
                  const fmtShort = (v: number) => Math.abs(v) >= 1000 ? `$${(v / 1000).toFixed(1)}k` : `$${Math.round(v)}`;
                  return (
                    <svg viewBox={`0 0 ${W} ${H}`} className="w-full" style={{ maxHeight: 200 }}>
                      {/* Grid */}
                      {gridLines.map((g, i) => (
                        <g key={i}>
                          <line x1={PAD_L} x2={W - PAD_R} y1={g.y} y2={g.y} stroke="rgba(255,255,255,0.06)" strokeWidth={1} />
                          <text x={PAD_L - 4} y={g.y + 3} textAnchor="end" fill="rgba(255,255,255,0.25)" fontSize={7} fontFamily="monospace">{g.label}</text>
                        </g>
                      ))}
                      {/* Bars */}
                      {days.map((d, i) => {
                        const v = d.sales;
                        const barY = yForVal(v);
                        const isToday = d.date === today;
                        const dayOfWeek = DAY_NAMES[new Date(d.date + 'T00:00:00').getDay()];
                        const dayLabel = new Date(d.date + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
                        const roas = d.spend > 0 ? d.sales / d.spend : 0;
                        return (
                          <g key={d.date}>
                            <rect
                              x={xForIdx(i) - barW / 2} y={barY} width={barW}
                              height={Math.max(0, PAD_T + chartH - barY)} rx={3}
                              fill={isToday ? 'url(#todayGrad)' : 'url(#barGrad)'}
                              opacity={0.85}
                            />
                            {isToday && <rect x={xForIdx(i) - barW / 2 - 1} y={barY - 1} width={barW + 2} height={Math.max(0, PAD_T + chartH - barY + 2)} rx={3} fill="none" stroke="rgba(34,211,238,0.5)" strokeWidth={1.5} />}
                            <text x={xForIdx(i)} y={Math.max(barY - 5, PAD_T - 2)} textAnchor="middle" fill={isToday ? '#22d3ee' : '#10b981'} fontSize={8} fontFamily="monospace" fontWeight="bold">{fmtShort(v)}</text>
                            <text x={xForIdx(i)} y={H - 18} textAnchor="middle" fill={isToday ? '#22d3ee' : 'rgba(255,255,255,0.4)'} fontSize={8} fontFamily="monospace" fontWeight={isToday ? 'bold' : 'normal'}>{dayOfWeek}</text>
                            <text x={xForIdx(i)} y={H - 8} textAnchor="middle" fill={isToday ? 'rgba(34,211,238,0.7)' : 'rgba(255,255,255,0.2)'} fontSize={7} fontFamily="monospace">{d.date.slice(5)}</text>
                            <title>{`${dayLabel} (${dayOfWeek})\nSales: ${fM(d.sales)}\nSpend: ${fM(d.spend)}\nOrders: ${fOrd(d.orders)}\nROAS: ${fR(roas)}\nNet Profit: ${fM(d.netProfit)}`}</title>
                          </g>
                        );
                      })}
                      {/* Gradient defs */}
                      <defs>
                        <linearGradient id="barGrad" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" stopColor="#f87171" />
                          <stop offset="100%" stopColor="#b91c1c" />
                        </linearGradient>
                        <linearGradient id="todayGrad" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" stopColor="#22d3ee" />
                          <stop offset="100%" stopColor="#0891b2" />
                        </linearGradient>
                      </defs>
                    </svg>
                  );
                })()}
              </div>
              {/* Daily data table */}
              <div className="overflow-x-auto">
                <table className="w-full border-collapse text-[11px]">
                  <thead>
                    <tr className="text-faint uppercase tracking-wider text-[9px] border-b border-border-faint">
                      <th className="text-left px-2 py-1.5">Date</th>
                      <th className="text-left px-2 py-1.5">Day</th>
                      <th className="text-right px-2 py-1.5">Sales</th>
                      <th className="text-right px-2 py-1.5">Orders</th>
                      <th className="text-right px-2 py-1.5">Ads Spend</th>
                      <th className="text-right px-2 py-1.5">Net Profit</th>
                      <th className="text-right px-2 py-1.5">ROAS</th>
                      <th className="text-right px-2 py-1.5">Clicks</th>
                      <th className="text-right px-2 py-1.5">Conv %</th>
                    </tr>
                  </thead>
                  <tbody>
                    {dailyPeakData.days.map(d => {
                      const roas = d.spend > 0 ? d.sales / d.spend : 0;
                      const cvr = d.clicks > 0 ? (d.orders / d.clicks) * 100 : 0;
                      const dayName = new Date(d.date + 'T00:00:00').toLocaleDateString('en-US', { weekday: 'short' });
                      const isToday = d.date === dailyPeakData.today;
                      return (
                        <tr key={d.date} className={`border-b border-border-faint/50 ${isToday ? 'bg-cyan-500/10 ring-1 ring-inset ring-cyan-500/20' : 'hover:bg-white/[.02]'}`}>
                          <td className={`px-2 py-1 font-mono ${isToday ? 'text-cyan-400 font-bold' : 'text-foreground'}`}>{d.date.slice(5)}</td>
                          <td className="px-2 py-1 text-muted text-[10px]">{dayName}</td>
                          <td className="px-2 py-1 text-right font-mono font-semibold text-emerald-400">{fM(d.sales)}</td>
                          <td className="px-2 py-1 text-right font-mono">{fOrd(d.orders)}</td>
                          <td className="px-2 py-1 text-right font-mono text-amber-400">{fM(d.spend)}</td>
                          <td className={`px-2 py-1 text-right font-mono font-semibold ${d.netProfit >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>{fM(d.netProfit)}</td>
                          <td className={`px-2 py-1 text-right font-mono font-semibold ${roas >= 2 ? 'text-emerald-400' : roas >= 1 ? 'text-amber-400' : 'text-rose-400'}`}>{fR(roas)}</td>
                          <td className="px-2 py-1 text-right font-mono text-muted">{fClk(d.clicks)}</td>
                          <td className="px-2 py-1 text-right font-mono text-muted">{fP(cvr)}</td>
                        </tr>
                      );
                    })}
                    {/* Total row */}
                    <tr className="border-t-2 border-zinc-600 font-bold">
                      <td className="px-2 py-1.5 font-semibold" colSpan={2}>TOTAL</td>
                      <td className="px-2 py-1.5 text-right font-mono text-emerald-400">{fM(dailyPeakData.totalSales)}</td>
                      <td className="px-2 py-1.5 text-right font-mono">{fOrd(dailyPeakData.totalOrders)}</td>
                      <td className="px-2 py-1.5 text-right font-mono text-amber-400">{fM(dailyPeakData.totalSpend)}</td>
                      <td className={`px-2 py-1.5 text-right font-mono font-semibold ${(dailyPeakData.totalSales - dailyPeakData.totalSpend) >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                        {fM(dailyPeakData.days.reduce((s, d) => s + d.netProfit, 0))}
                      </td>
                      <td className={`px-2 py-1.5 text-right font-mono font-semibold ${dailyPeakData.totalSpend > 0 ? (dailyPeakData.totalSales / dailyPeakData.totalSpend >= 2 ? 'text-emerald-400' : 'text-amber-400') : ''}`}>
                        {dailyPeakData.totalSpend > 0 ? fR(dailyPeakData.totalSales / dailyPeakData.totalSpend) : '—'}
                      </td>
                      <td className="px-2 py-1.5 text-right font-mono text-muted">{fClk(dailyPeakData.days.reduce((s, d) => s + d.clicks, 0))}</td>
                      <td></td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </Card>
      )}

      {/* ─── LY Top Search Terms with % Contribution ─── */}
      {lyTopTerms && lyTopTerms.terms.length > 0 && (
        <Card className="mb-6">
          <button onClick={() => setShowLyTopTerms(p => !p)} className="flex items-center gap-2 w-full text-left mb-2">
            <TrendingUp size={16} className="text-amber-400" />
            <span className="text-sm font-bold">LY Peak Top Search Terms</span>
            <span className="text-[10px] text-faint font-mono ml-1">
              {lyTopTerms.dateRange} · Top {lyTopTerms.terms.length} drove {lyTopTerms.top20Pct.toFixed(0)}% of {fOrd(lyTopTerms.totalOrders)} total SQP orders
            </span>
            <ChevronRight size={12} className={`text-faint ml-auto transition-transform ${showLyTopTerms ? 'rotate-90' : ''}`} />
          </button>
          {showLyTopTerms && (
            <div className="animate-in">
              {/* Contribution bar */}
              <div className="flex items-center gap-2 mb-3">
                <div className="flex-1 h-4 rounded-full bg-zinc-800 overflow-hidden">
                  <div
                    className="h-full bg-gradient-to-r from-amber-500 to-amber-400 rounded-full transition-all"
                    style={{ width: `${Math.min(100, lyTopTerms.top20Pct)}%` }}
                  />
                </div>
                <span className="text-xs font-bold text-amber-400 font-mono">{lyTopTerms.top20Pct.toFixed(0)}%</span>
                <span className="text-[10px] text-faint">of total orders</span>
              </div>
              {/* Top terms table */}
              <div className="overflow-x-auto">
                <table className="w-full border-collapse text-[11px]">
                  <thead>
                    <tr className="text-faint uppercase tracking-wider text-[9px] border-b border-border-faint">
                      <th className="text-left px-2 py-1.5 w-6">#</th>
                      <th className="text-left px-2 py-1.5">Search Term</th>
                      <th className="text-left px-2 py-1.5">Families</th>
                      <th className="text-right px-2 py-1.5 cursor-pointer select-none hover:text-foreground" onClick={() => lyTermSortBy('orders')}>SQP Orders{lyTermArrow('orders')}</th>
                      <th className="text-right px-2 py-1.5 cursor-pointer select-none hover:text-foreground" onClick={() => lyTermSortBy('pctOfTotal')}>% of Total{lyTermArrow('pctOfTotal')}</th>
                      <th className="text-right px-2 py-1.5 cursor-pointer select-none hover:text-foreground" onClick={() => lyTermSortBy('dailyDelta')} title="Change in avg purchases/day: peak window vs the 2 weeks before">Δ Purch/day{lyTermArrow('dailyDelta')}</th>
                      <th className="text-right px-2 py-1.5 cursor-pointer select-none hover:text-foreground" onClick={() => lyTermSortBy('amzVolume')} title="Total Amazon search volume for this term (market-wide)">Amazon Volume{lyTermArrow('amzVolume')}</th>
                      <th className="text-right px-2 py-1.5 cursor-pointer select-none hover:text-foreground" onClick={() => lyTermSortBy('amzSales')} title="Total Amazon purchases for this term (market-wide)">Amazon Sales{lyTermArrow('amzSales')}</th>
                      <th className="text-right px-2 py-1.5 cursor-pointer select-none hover:text-foreground" onClick={() => lyTermSortBy('clicks')}>Clicks{lyTermArrow('clicks')}</th>
                      <th className="text-right px-2 py-1.5">Conv %</th>
                    </tr>
                  </thead>
                  <tbody>
                    {lyTermsSorted.map((t, i) => {
                      const cvr = t.clicks > 0 ? (t.orders / t.clicks) * 100 : 0;
                      return (
                        <tr key={t.term} className="border-b border-border-faint/50 hover:bg-white/[.02]">
                          <td className="px-2 py-1 text-faint font-mono">{i + 1}</td>
                          <td className="px-2 py-1 text-blue-300 font-medium">{t.term}</td>
                          <td className="px-2 py-1 text-muted text-[10px]">{t.families || '—'}</td>
                          <td className="px-2 py-1 text-right font-mono font-semibold text-foreground">{fOrd(t.orders)}</td>
                          <td className="px-2 py-1 text-right">
                            <div className="flex items-center justify-end gap-1">
                              <div className="w-12 h-1.5 rounded-full bg-zinc-800 overflow-hidden">
                                <div className="h-full bg-amber-400 rounded-full" style={{ width: `${Math.min(100, t.pctOfTotal * 3)}%` }} />
                              </div>
                              <span className="font-mono text-amber-400 text-[10px] w-10 text-right">{t.pctOfTotal.toFixed(1)}%</span>
                            </div>
                          </td>
                          <td className={`px-2 py-1 text-right font-mono ${t.dailyDelta > 0 ? 'text-emerald-400' : t.dailyDelta < 0 ? 'text-rose-400' : 'text-muted'}`}>
                            {t.dailyDelta >= 0 ? '+' : ''}{t.dailyDelta.toFixed(1)}/d
                            {t.dailyDeltaPct != null && <span className="text-faint text-[9px] ml-1">({t.dailyDeltaPct >= 0 ? '+' : ''}{t.dailyDeltaPct.toFixed(0)}%)</span>}
                            {t.dailyDeltaPct == null && t.dailyDelta > 0 && <span className="text-faint text-[9px] ml-1">(new)</span>}
                          </td>
                          <td className="px-2 py-1 text-right font-mono text-muted">{t.amzVolume.toLocaleString()}</td>
                          <td className="px-2 py-1 text-right font-mono text-muted">{t.amzSales.toLocaleString()}</td>
                          <td className="px-2 py-1 text-right font-mono text-muted">{t.clicks.toLocaleString()}</td>
                          <td className={`px-2 py-1 text-right font-mono ${cvr > 5 ? 'text-emerald-400' : 'text-muted'}`}>{fP(cvr)}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </Card>
      )}

      {/* ─── Per-Product Peak Actions (rollup of the keyword recs) ─── */}
      {peakProductActions && (
        <Card className="mb-6">
          <button onClick={() => setShowProdActions(p => !p)} className="flex items-center gap-2 w-full text-left mb-2">
            <Zap size={16} className="text-amber-400" />
            <span className="text-sm font-bold">Per-Product Peak Actions — {activeHolidayName}</span>
            <span className="text-[10px] text-faint font-mono ml-1">{peakProductActions.length} products</span>
            <ChevronRight size={12} className={`text-faint ml-auto transition-transform ${showProdActions ? 'rotate-90' : ''}`} />
          </button>
          {showProdActions && (
            <div className="animate-in space-y-1.5">
              {peakProductActions.map(p => {
                const meta = ({
                  NEW_CAMPAIGN: { label: '🆕 New campaign', cls: 'bg-blue-500/15 text-blue-400' },
                  SCALE: { label: '↑ Scale existing', cls: 'bg-emerald-500/15 text-emerald-400' },
                  ADD_KW: { label: '+ Add keywords', cls: 'bg-blue-500/15 text-blue-400' },
                  MONITOR: { label: 'Monitor', cls: 'bg-white/[0.04] text-faint' },
                } as Record<string, { label: string; cls: string }>)[p.action];
                return (
                  <div key={p.family} className="flex items-center gap-3 text-[12px] py-1.5 border-b border-border-faint/40">
                    <span className="font-bold text-heading w-24 shrink-0 truncate">{p.family}</span>
                    <span className={`px-2 py-0.5 rounded-md text-[10px] font-semibold whitespace-nowrap ${meta.cls}`}>{meta.label}</span>
                    <div className="flex items-center gap-3 font-mono text-[11px] ml-auto">
                      {p.boost > 0 && <span className="text-emerald-400">↑ {p.boost} boost{p.trending > 0 ? ` (${p.trending} ↗)` : ''}</span>}
                      {p.add > 0 && <span className="text-blue-400">🆕 {p.add} add</span>}
                      {p.cautious > 0 && <span className="text-amber-400">↓ {p.cautious} trim</span>}
                      {p.defense > 0 && <span className="text-purple-400">🛡 {p.defense} defense</span>}
                    </div>
                  </div>
                );
              })}
              <div className="text-[9px] text-zinc-600 mt-1 font-mono">New campaign = ≥3 new keywords to add · Scale = raise bids on existing winners · trim = advertised but unprofitable at peak</div>
            </div>
          )}
        </Card>
      )}

      {/* ─── Peak Keyword Plan (from V_PEAK_KEYWORD_RECS) ─── */}
      {peakKwRecs && (
        <Card className="mb-6">
          <div className="flex items-center gap-2 mb-2">
            <button onClick={() => setShowKwPlan(p => !p)} className="flex items-center gap-2 flex-1 min-w-0 text-left">
              <Zap size={16} className="text-blue-400 shrink-0" />
              <span className="text-sm font-bold whitespace-nowrap">Peak Keyword Plan — {activeHolidayName}</span>
              <span className="text-[10px] text-faint font-mono ml-1 truncate">
                {peakKwRecs.increase.length} to boost{peakKwRecs.trendingCount ? ` (${peakKwRecs.trendingCount} ↗ trending)` : ''} · {peakKwRecs.addCount} to add
              </span>
            </button>
            <button onClick={exportPeakRecsCsv} title="Download the full plan as CSV" className="text-[10px] font-semibold px-2 py-1 rounded-md border border-border/40 text-muted hover:text-foreground hover:border-border whitespace-nowrap shrink-0">⬇ CSV</button>
            <button onClick={() => setShowKwPlan(p => !p)} className="shrink-0" aria-label="Toggle"><ChevronRight size={12} className={`text-faint transition-transform ${showKwPlan ? 'rotate-90' : ''}`} /></button>
          </div>
          {showKwPlan && (
            <>
              <div className="animate-in grid md:grid-cols-2 gap-x-6 gap-y-3">
                <KwBucket title="↑ Boost existing" sub="advertised — raise bids" color="text-emerald-400" rows={peakKwRecs.increase} limit={12} />
                <KwBucket title="🎯 Add — Exact" sub="new · rank≥75" color="text-blue-400" rows={peakKwRecs.exact} limit={8} />
                <KwBucket title="🔤 Add — Phrase" sub="new · ≥3 words" color="text-blue-400" rows={peakKwRecs.phrase} limit={8} />
                <KwBucket title="📡 Add — Broad" sub="new · high volume" color="text-blue-400" rows={peakKwRecs.broad} limit={6} />
                {peakKwRecs.brand.length > 0 && <KwBucket title="🛡 Brand defense" sub="own-brand" color="text-purple-400" rows={peakKwRecs.brand} limit={6} />}
              </div>
              <div className="text-[9px] text-zinc-600 mt-2 font-mono">From last year's {activeHolidayName} peak demand × profitability + current trend (↗) · new terms gated on research fit (rank&gt;75) · hover a row for the reason</div>
            </>
          )}
        </Card>
      )}

      {/* ─── Stuck campaigns to refresh before the peak ─── */}
      {peakStuck && peakStuck.length > 0 && (
        <Card className="mb-6">
          <button onClick={() => setShowStuck(p => !p)} className="flex items-center gap-2 w-full text-left mb-2">
            <AlertTriangle size={16} className="text-amber-400" />
            <span className="text-sm font-bold">Stuck Campaigns — refresh before peak</span>
            <span className="text-[10px] text-faint font-mono ml-1">{peakStuck.length} need attention</span>
            <ChevronRight size={12} className={`text-faint ml-auto transition-transform ${showStuck ? 'rotate-90' : ''}`} />
          </button>
          {showStuck && (
            <div className="animate-in space-y-1">
              {peakStuck.slice(0, 20).map(c => {
                const fm = ({
                  BUDGET_CAPPED: { label: 'CAPPED', cls: 'bg-red-500/15 text-red-400' },
                  PAUSED: { label: 'PAUSED', cls: 'bg-amber-500/15 text-amber-400' },
                  DORMANT: { label: 'DORMANT', cls: 'bg-amber-500/15 text-amber-400' },
                  SHARE_DROPPED: { label: 'SHARE ↓', cls: 'bg-blue-500/15 text-blue-400' },
                } as Record<string, { label: string; cls: string }>)[c.stuck_flag] || { label: c.stuck_flag, cls: 'bg-white/[0.04] text-faint' };
                return (
                  <div key={c.campaign_name} className="flex items-center gap-2 text-[11px] py-1 border-b border-border-faint/40">
                    <span className={`px-1.5 py-0.5 rounded text-[9px] font-bold shrink-0 ${fm.cls}`}>{fm.label}</span>
                    <span className="font-mono text-faint text-[9px] w-16 shrink-0 truncate">{c.parent_name}</span>
                    <span className="text-blue-300 truncate flex-1 min-w-0" title={c.campaign_name}>{c.campaign_name}</span>
                    <span className="text-muted text-[10px] truncate max-w-[45%] hidden md:inline" title={c.reason}>{c.reason}</span>
                  </div>
                );
              })}
              <div className="text-[9px] text-zinc-600 mt-1 font-mono">From V_ADS_COACH campaign health · raise capped budgets · reactivate paused · refresh dormant before the peak</div>
            </div>
          )}
        </Card>
      )}

      {/* Holiday Selector */}
      {holidayNames.length > 0 && (
        <div className="flex items-center gap-3 mb-4">
          <span className="text-[10px] text-faint uppercase tracking-wider font-semibold">Compare holiday:</span>
          <select
            value={activeHolidayName}
            onChange={e => setSelectedHoliday(e.target.value || null)}
            className="px-2.5 py-1 text-xs font-semibold rounded-lg bg-inset border border-border text-subtle hover:border-border-strong focus:outline-none focus:border-blue-500 appearance-none cursor-pointer"
          >
            {pk?.holiday_name && <option value={pk.holiday_name}>{pk.holiday_name} (next peak){holidayRelevanceSummary[pk.holiday_name] ? ` — ${holidayRelevanceSummary[pk.holiday_name].relevant}/${holidayRelevanceSummary[pk.holiday_name].total} families` : ''}</option>}
            {holidayNames.filter(n => n !== pk?.holiday_name).map(n => {
              const rel = holidayRelevanceSummary[n];
              const suffix = rel ? ` — ${rel.relevant}/${rel.total} families peak` : '';
              return <option key={n} value={n}>{n}{suffix}</option>;
            })}
          </select>
          {relevanceForHoliday.length > 0 && (
            <Badge variant={anyRelevantPeak ? 'green' : 'red'} className="!text-[9px]">
              {anyRelevantPeak
                ? `${relevanceForHoliday.filter(r => r.is_relevant_peak).length}/${relevanceForHoliday.length} families peak`
                : 'No peak signal'}
            </Badge>
          )}
        </div>
      )}

      {/* Phase-by-Phase Comparison (actual holiday dates) */}
      {phaseComparison && (
        <Card className="mb-6">
          <div className="flex items-center justify-between mb-3 pr-1">
            <button onClick={() => setShowYoy(p => !p)} className="flex items-center gap-1.5 text-sm font-bold text-left">
              <ChevronRight size={14} className={`text-faint transition-transform duration-200 ${showYoy ? 'rotate-90' : ''}`} />
              Phase Comparison: {phaseComparison.tyHoliday} vs {phaseComparison.lyHoliday}
            </button>
            <MeasureSelector
              tableId="peak_comparison"
              measures={COMPARISON_MEASURES}
              selected={selectedMeasures}
              onSelectedChange={setSelectedMeasures}
            />
          </div>
          {showYoy && (
            <div className="animate-in space-y-5">
              {COMPARISON_PHASE_KEYS.map(phase => {
                const pd = phaseComparison.phases[phase];
                const fams = filters.family ? [filters.family, 'Total' as FamilyName] : [...FAMILY_NAMES, 'Total' as FamilyName];
                const hasAnyData = fams.some(f => (pd.ty[f]?.sales || 0) > 0 || (pd.ly[f]?.sales || 0) > 0);
                if (!hasAnyData) return null;
                return (
                  <div key={phase}>
                    <div className="flex items-center gap-2 mb-2">
                      <span className={`text-xs font-bold px-2 py-0.5 rounded bg-gradient-to-br ${STAGE_COLORS[phase === 'pre_season' ? 'PRE_SEASON' : phase === 'boost' ? 'PRE_PEAK_BOOST' : phase.toUpperCase()] || 'from-zinc-700 to-zinc-600'} text-white/90`}>
                        {PHASE_LABELS_MAP[phase]}
                      </span>
                      <span className="text-[10px] text-faint font-mono">TY: {pd.tyRange} · LY: {pd.lyRange}</span>
                    </div>
                    <div className="overflow-x-auto">
                      <table className="w-full border-collapse text-xs">
                        <thead>
                          <tr>
                            <Th>Family</Th>
                            {selectedMeasures.has('sales_ly') && <Th right tip={MEASURE_TIPS.sales}>LY Sales</Th>}
                            {selectedMeasures.has('sales_ty') && <Th right tip={MEASURE_TIPS.sales}>TY Sales</Th>}
                            {selectedMeasures.has('sales_delta') && <Th right>Delta</Th>}
                            {selectedMeasures.has('roas_ly') && <Th right tip={MEASURE_TIPS.net_roas}>LY ROAS</Th>}
                            {selectedMeasures.has('roas_ty') && <Th right tip={MEASURE_TIPS.net_roas}>TY ROAS</Th>}
                            {selectedMeasures.has('orders_ly') && <Th right tip={MEASURE_TIPS.orders}>LY Orders</Th>}
                            {selectedMeasures.has('orders_ty') && <Th right tip={MEASURE_TIPS.orders}>TY Orders</Th>}
                            {selectedMeasures.has('spend_ly') && <Th right tip={MEASURE_TIPS.ad_cost}>LY Ads Cost</Th>}
                            {selectedMeasures.has('spend_ty') && <Th right tip={MEASURE_TIPS.ad_cost}>TY Ads Cost</Th>}
                            {selectedMeasures.has('cvr_ly') && <Th right tip={MEASURE_TIPS.conv_rate}>LY Ads Conv %</Th>}
                            {selectedMeasures.has('cvr_ty') && <Th right tip={MEASURE_TIPS.conv_rate}>TY Ads Conv %</Th>}
                          </tr>
                        </thead>
                        <tbody>
                          {fams.map(fam => {
                            const ly = pd.ly[fam]; const ty = pd.ty[fam];
                            if (!ly && !ty) return null;
                            const lySales = ly?.sales || 0; const tySales = ty?.sales || 0;
                            const lyRoas = ly?.adCost ? ly.netProfit / ly.adCost : 0;
                            const tyRoas = ty?.adCost ? ty.netProfit / ty.adCost : 0;
                            const lyCvr = ly?.clicks ? (ly.orders / ly.clicks) * 100 : 0;
                            const tyCvr = ty?.clicks ? (ty.orders / ty.clicks) * 100 : 0;
                            const delta = lySales ? ((tySales - lySales) / lySales) * 100 : 0;
                            if (!lySales && !tySales) return null;
                            const isTotal = fam === ('Total' as any);
                            return (
                              <tr key={fam} className={`border-b border-border-faint hover:bg-white/[.02] ${isTotal ? 'border-t-2 border-t-zinc-600 font-bold' : ''}`}>
                                <td className="px-3 py-1.5 font-semibold">{fam}</td>
                                {selectedMeasures.has('sales_ly') && <td className="px-3 py-1.5 text-right font-mono">{fM(lySales)}</td>}
                                {selectedMeasures.has('sales_ty') && <td className="px-3 py-1.5 text-right font-mono">{fM(tySales)}</td>}
                                {selectedMeasures.has('sales_delta') && (
                                  <td className={`px-3 py-1.5 text-right font-mono font-semibold ${delta > 0 ? 'text-emerald-400' : delta < 0 ? 'text-red-400' : ''}`}>
                                    {delta > 0 ? '+' : ''}{delta.toFixed(1)}%
                                  </td>
                                )}
                                {selectedMeasures.has('roas_ly') && <td className="px-3 py-1.5 text-right font-mono">{fR(lyRoas)}</td>}
                                {selectedMeasures.has('roas_ty') && <td className="px-3 py-1.5 text-right font-mono">{fR(tyRoas)}</td>}
                                {selectedMeasures.has('orders_ly') && <td className="px-3 py-1.5 text-right font-mono">{fOrd(ly?.orders || 0)}</td>}
                                {selectedMeasures.has('orders_ty') && <td className="px-3 py-1.5 text-right font-mono">{fOrd(ty?.orders || 0)}</td>}
                                {selectedMeasures.has('spend_ly') && <td className="px-3 py-1.5 text-right font-mono">{fM(ly?.adCost || 0)}</td>}
                                {selectedMeasures.has('spend_ty') && <td className="px-3 py-1.5 text-right font-mono">{fM(ty?.adCost || 0)}</td>}
                                {selectedMeasures.has('cvr_ly') && <td className="px-3 py-1.5 text-right font-mono">{fP(lyCvr)}</td>}
                                {selectedMeasures.has('cvr_ty') && <td className="px-3 py-1.5 text-right font-mono">{fP(tyCvr)}</td>}
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </Card>
      )}

      {/* Overall Year-over-Year (fallback when no holiday dates) */}
      {!phaseComparison && yoyData && (
        <Card className="mb-6">
          <button onClick={() => setShowYoy(p => !p)} className="flex items-center gap-1.5 text-sm font-bold w-full text-left mb-3">
            <ChevronRight size={14} className={`text-faint transition-transform duration-200 ${showYoy ? 'rotate-90' : ''}`} />
            Year-over-Year Comparison
            <span className="text-[10px] text-faint font-mono font-normal ml-1">(Pre Season → Peak End, calendar shift)</span>
          </button>
          {showYoy && (
            <div className="animate-in">
              <div className="flex gap-4 text-[10px] text-faint font-mono mb-3">
                <span>Last Year: {yoyData.lyRange}</span>
                <span>This Year: {yoyData.tyRange}</span>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full border-collapse text-xs">
                  <thead>
                    <tr>
                      <Th>Family</Th>
                      <Th right tip={MEASURE_TIPS.sales}>LY Sales</Th>
                      <Th right tip={MEASURE_TIPS.sales}>TY Sales</Th>
                      <Th right>Delta</Th>
                      <Th right tip={MEASURE_TIPS.net_roas}>LY ROAS</Th>
                      <Th right tip={MEASURE_TIPS.net_roas}>TY ROAS</Th>
                      <Th right tip={MEASURE_TIPS.orders}>LY Orders</Th>
                      <Th right tip={MEASURE_TIPS.orders}>TY Orders</Th>
                    </tr>
                  </thead>
                  <tbody>
                    {(filters.family ? [filters.family] : FAMILY_NAMES).map(fam => {
                      const ly = yoyData.ly[fam]; const ty = yoyData.ty[fam];
                      if (!ly || !ty) return null;
                      const lyRoas = ly.adCost ? ly.netProfit / ly.adCost : 0;
                      const tyRoas = ty.adCost ? ty.netProfit / ty.adCost : 0;
                      const salesDelta = ly.sales ? ((ty.sales - ly.sales) / ly.sales) * 100 : 0;
                      if (!ly.sales && !ty.sales) return null;
                      return (
                        <tr key={fam} className="border-b border-border-faint hover:bg-white/[.02]">
                          <td className="px-3 py-2 font-semibold">{fam}</td>
                          <td className="px-3 py-2 text-right font-mono">{fM(ly.sales)}</td>
                          <td className="px-3 py-2 text-right font-mono">{fM(ty.sales)}</td>
                          <td className={`px-3 py-2 text-right font-mono font-semibold ${salesDelta > 0 ? 'text-emerald-400' : salesDelta < 0 ? 'text-red-400' : ''}`}>
                            {salesDelta > 0 ? '+' : ''}{salesDelta.toFixed(1)}%
                          </td>
                          <td className="px-3 py-2 text-right font-mono">{fR(lyRoas)}</td>
                          <td className="px-3 py-2 text-right font-mono">{fR(tyRoas)}</td>
                          <td className="px-3 py-2 text-right font-mono">{fOrd(ly.orders)}</td>
                          <td className="px-3 py-2 text-right font-mono">{fOrd(ty.orders)}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </Card>
      )}

      {STAGES.map((st, idx) => {
        const isActive = idx === ci;
        const isPast = idx < ci;
        const isOpen = openStages.has(idx);
        const items = CHECKLISTS[st] || [];

        return (
          <div key={st} className={`mb-4 ${!isActive && !isPast ? 'opacity-50' : ''}`}>
            <button onClick={() => toggleStage(idx)} className="flex items-center gap-1.5 text-sm font-bold w-full text-left mb-2">
              <ChevronRight size={14} className={`text-faint transition-transform duration-200 ${isOpen ? 'rotate-90' : ''}`} />
              {STAGE_LABELS[st]}
              <Badge variant={isPast ? 'green' : isActive ? 'blue' : 'muted'}>{isPast ? 'Done' : isActive ? 'Current' : 'Upcoming'}</Badge>
            </button>
            {isOpen && (
              <div className="space-y-1.5 animate-in">
                {items.map((item, i) => {
                  const cd = filteredCheckData[item.dataKey];
                  const hasData = cd && cd.rows.length > 0;
                  const isExpanded = expandedItems.has(`${st}-${i}`);
                  const statusIcon = isPast ? '✅' : (hasData && cd.status === 'ok' ? '✅' : hasData && cd.status === 'warn' ? '⚠️' : '⬜');
                  const borderColor = isPast ? 'border-l-emerald-500' : (hasData && cd.status === 'ok' ? 'border-l-emerald-500' : hasData && cd.status === 'warn' ? 'border-l-amber-500' : 'border-l-zinc-600');

                  return (
                    <div key={i}>
                      <button
                        onClick={() => hasData ? toggleItem(`${st}-${i}`) : undefined}
                        className={`flex gap-3 p-3 border border-border rounded-xl bg-card transition-colors hover:border-border-strong w-full text-left border-l-[3px] ${borderColor} ${hasData ? 'cursor-pointer' : 'cursor-default'}`}
                      >
                        <span className="text-base flex-shrink-0 mt-px">{statusIcon}</span>
                        <div className="flex-1">
                          <div className="text-xs font-semibold flex items-center gap-2">
                            {item.label}
                            {hasData && <span className="text-[10px] text-faint font-mono">({cd.rows.length} items)</span>}
                          </div>
                          {cd?.summary && <div className="text-[10px] text-subtle mt-0.5">{cd.summary}</div>}
                        </div>
                        {hasData && (isExpanded ? <ChevronDown size={14} className="text-faint mt-0.5" /> : <ChevronRight size={14} className="text-faint mt-0.5" />)}
                      </button>
                      {isExpanded && hasData && (
                        <div className="mt-1 mb-2 border border-border rounded-lg bg-inset overflow-x-auto animate-in">
                          <table className="w-full border-collapse text-xs">
                            <thead>
                              <tr>
                                {cd.columns.map(c => (
                                  <th key={c} className="bg-inset text-subtle text-left px-3 py-2 font-semibold text-[10px] uppercase tracking-wider border-b border-border whitespace-nowrap">{c}</th>
                                ))}
                              </tr>
                            </thead>
                            <tbody>
                              {cd.rows.flatMap((row, ri) => {
                                const isExpRow = (item.dataKey === 'experiments_status' || item.dataKey === 'campaigns_live');
                                const eid = isExpRow ? cd.expIds?.[ri] : undefined;
                                const expIsOpen = eid ? expandedExps.has(eid) : false;
                                const details = eid ? filteredExpDetails[eid] : undefined;
                                const hasCampaigns = details && details.campaigns.length > 0;
                                const rows: React.ReactNode[] = [
                                  <tr key={ri} onClick={eid ? (e) => { e.stopPropagation(); toggleExp(eid); } : undefined}
                                    className={`border-b border-border-faint last:border-b-0 hover:bg-white/[.02] ${eid ? 'cursor-pointer' : ''}`}>
                                    {row.map((cell, ci2) => (
                                      <td key={ci2} className="px-3 py-1.5 whitespace-nowrap">
                                        {ci2 === 0 && eid ? (
                                          <span className="flex items-center gap-1">
                                            {expIsOpen ? <ChevronDown size={10} className="text-faint flex-shrink-0" /> : <ChevronRight size={10} className="text-faint flex-shrink-0" />}
                                            {cell}
                                          </span>
                                        ) : cell}
                                      </td>
                                    ))}
                                  </tr>
                                ];
                                if (expIsOpen && hasCampaigns) {
                                  rows.push(
                                    <tr key={`${ri}-detail`}>
                                      <td colSpan={cd.columns.length} className="p-0">
                                        <div className="bg-inset px-4 py-2 animate-in">
                                          <div className="text-[10px] text-faint font-semibold mb-1.5 uppercase tracking-wider">
                                            Campaigns ({details!.campaigns.length})
                                            {details!.exp?.start_date && (
                                              <span className="ml-2 font-normal normal-case">
                                                Started {details!.exp.start_date} · {calcDaysRunning(details!.exp.start_date)} days
                                              </span>
                                            )}
                                          </div>
                                          <div className="space-y-2">
                                            {details!.campaigns.map(camp => {
                                              const campKey = `${eid}__${camp.campaign_id}`;
                                              const campOpen = expandedCampaigns.has(campKey);
                                              return (
                                                <div key={camp.campaign_id} className="border border-zinc-700/40 rounded-lg overflow-hidden">
                                                  <button
                                                    onClick={(e) => { e.stopPropagation(); toggleCampaign(campKey); }}
                                                    className="flex items-center gap-2 w-full text-left px-3 py-2 hover:bg-white/[.03] transition-colors"
                                                  >
                                                    {campOpen ? <ChevronDown size={11} className="text-faint flex-shrink-0" /> : <ChevronRight size={11} className="text-faint flex-shrink-0" />}
                                                    <span className="text-xs font-semibold text-blue-400 truncate">{camp.campaign_name}</span>
                                                    <span className="text-[10px] text-faint font-mono ml-auto flex gap-3 flex-shrink-0">
                                                      <span>{camp.campaign_type}</span>
                                                      <span>Ads Spend: {fM(camp.spend)}</span>
                                                      <span>Ads Orders: {fOrd(camp.orders)}</span>
                                                      <span>Ads Clicks: {fClk(camp.clicks)}</span>
                                                      {camp.top_of_search_pct != null && <span>TOS: {camp.top_of_search_pct}%</span>}
                                                      <span>{camp.terms.length} terms</span>
                                                    </span>
                                                  </button>
                                                  {campOpen && (
                                                    <div className="border-t border-zinc-700/30 animate-in">
                                                      {camp.terms.length > 0 ? (
                                                        <table className="w-full border-collapse text-[11px]">
                                                          <thead><tr>
                                                            <Th>Keyword</Th>
                                                            <Th right tip={MEASURE_TIPS.spend}>Ads Spend</Th>
                                                            <Th right tip={MEASURE_TIPS.orders}>Ads Orders</Th>
                                                            <Th right tip={MEASURE_TIPS.clicks}>Ads Clicks</Th>
                                                            <Th right tip={MEASURE_TIPS.conv_rate}>Ads Conv%</Th>
                                                            <Th right>Ads CPC</Th>
                                                          </tr></thead>
                                                          <tbody>
                                                            {camp.terms.slice(0, 30).map((t, ti) => (
                                                              <tr key={ti} className="border-b border-border-faint last:border-b-0 hover:bg-white/[.02]">
                                                                <td className="px-3 py-1 text-blue-300 font-medium">{t.search_term}</td>
                                                                <td className="px-3 py-1 text-right font-mono">{fM(t.spend)}</td>
                                                                <td className="px-3 py-1 text-right font-mono">{fOrd(t.orders)}</td>
                                                                <td className="px-3 py-1 text-right font-mono">{fClk(t.clicks)}</td>
                                                                <td className="px-3 py-1 text-right font-mono">{fP(t.conv_rate)}</td>
                                                                <td className="px-3 py-1 text-right font-mono">${(t.cpc || 0).toFixed(2)}</td>
                                                              </tr>
                                                            ))}
                                                          </tbody>
                                                        </table>
                                                      ) : (
                                                        <div className="px-3 py-2 text-[11px] text-faint italic">No search term data for this campaign</div>
                                                      )}
                                                    </div>
                                                  )}
                                                </div>
                                              );
                                            })}
                                          </div>
                                        </div>
                                      </td>
                                    </tr>
                                  );
                                } else if (expIsOpen && eid) {
                                  rows.push(
                                    <tr key={`${ri}-empty`}>
                                      <td colSpan={cd.columns.length} className="px-4 py-3 text-[11px] text-faint italic bg-inset">
                                        No campaign or search term data available for this experiment
                                      </td>
                                    </tr>
                                  );
                                }
                                return rows;
                              })}
                            </tbody>
                          </table>
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function shiftYear(dateStr: string, years: number): string {
  const d = new Date(dateStr + 'T00:00:00');
  d.setFullYear(d.getFullYear() + years);
  return d.toISOString().slice(0, 10);
}

function addDaysLocal(dateStr: string, n: number): string {
  const d = new Date(dateStr + 'T00:00:00');
  d.setDate(d.getDate() + n);
  return d.toISOString().slice(0, 10);
}

function phaseBoundaries(h: HolidayRow) {
  const boostStart = h.boost_start || h.pre_season_start;
  const peakStart = h.peak_start || boostStart;
  const peakEnd = addDaysLocal(h.holiday_date, -1);
  return {
    pre_season: { start: h.pre_season_start, end: addDaysLocal(boostStart, -1) },
    boost: { start: boostStart, end: addDaysLocal(peakStart, -1) },
    peak: { start: peakStart, end: peakEnd },
    full: { start: h.pre_season_start, end: peakEnd },
  };
}

type PhaseKey = 'pre_season' | 'boost' | 'peak';
const PHASE_KEYS: PhaseKey[] = ['pre_season', 'boost', 'peak'];
/** Phases shown in the holiday comparison tables */
const COMPARISON_PHASE_KEYS: PhaseKey[] = ['pre_season', 'boost', 'peak'];
const PHASE_LABELS_MAP: Record<PhaseKey, string> = { pre_season: 'Pre Season', boost: 'Boost', peak: 'Peak' };

const COMPARISON_MEASURES: MeasureDef[] = [
  { id: 'sales_ly', label: 'LY Sales', tip: MEASURE_TIPS.sales, group: 'PnL', defaultVisible: true },
  { id: 'sales_ty', label: 'TY Sales', tip: MEASURE_TIPS.sales, group: 'PnL', defaultVisible: true },
  { id: 'sales_delta', label: 'Sales Delta', tip: 'Percentage change in sales vs LY', group: 'PnL', defaultVisible: true },
  { id: 'roas_ly', label: 'LY ROAS', tip: MEASURE_TIPS.net_roas, group: 'PnL', defaultVisible: true },
  { id: 'roas_ty', label: 'TY ROAS', tip: MEASURE_TIPS.net_roas, group: 'PnL', defaultVisible: true },
  { id: 'orders_ly', label: 'LY Orders', tip: MEASURE_TIPS.orders, group: 'PnL', defaultVisible: true },
  { id: 'orders_ty', label: 'TY Orders', tip: MEASURE_TIPS.orders, group: 'PnL', defaultVisible: true },
  { id: 'spend_ly', label: 'LY Ads Cost', tip: MEASURE_TIPS.ad_cost, group: 'Ads', defaultVisible: false },
  { id: 'spend_ty', label: 'TY Ads Cost', tip: MEASURE_TIPS.ad_cost, group: 'Ads', defaultVisible: false },
  { id: 'cvr_ly', label: 'LY Ads Conv %', tip: MEASURE_TIPS.conv_rate, group: 'Ads', defaultVisible: false },
  { id: 'cvr_ty', label: 'TY Ads Conv %', tip: MEASURE_TIPS.conv_rate, group: 'Ads', defaultVisible: false },
];

function calcDaysRunning(startDate: string): number {
  const start = new Date(startDate + 'T00:00:00');
  const now = new Date();
  return Math.max(0, Math.floor((now.getTime() - start.getTime()) / 86400000));
}

type CheckResult = { status: 'ok' | 'warn' | 'info'; summary: string; columns: string[]; rows: string[][]; expIds?: string[] };

function buildCheckData(data: DashboardData, pk: DashboardData['peak'][0] | null, getFamily: (name: string | null | undefined) => string | null): Record<string, CheckResult> {
  const out: Record<string, CheckResult> = {};
  const kw = data.keyword_product_map || [];
  const drv = data.drivers || [];
  const exps = data.experiments || [];
  const neg = data.negative_keywords || [];
  const bh = data.budget_health || [];
  const sqp = data.sqp_weekly || [];

  const peakName = (pk?.holiday_name || '').toLowerCase();

  // Cannibalization: multiple products targeting same search term, grouped by family
  const termMap: Record<string, Set<string>> = {};
  kw.forEach(k => {
    if (!termMap[k.search_term]) termMap[k.search_term] = new Set();
    termMap[k.search_term].add(k.product_short_name);
  });
  const cannibal = Object.entries(termMap).filter(([, v]) => v.size > 1).map(([term, prods]) => ({ term, prods: [...prods] }));
  if (cannibal.length > 0) {
    out.cannibalization = {
      status: 'warn',
      summary: `${cannibal.length} keywords targeted by multiple products`,
      columns: ['Keyword', 'Products', '# Products', 'Family'],
      rows: cannibal.slice(0, 20).map(c => {
        const fam = c.prods.map(p => getFamily(p)).filter(Boolean).join(', ');
        return [c.term, c.prods.join(', '), String(c.prods.length), fam || '--'];
      }),
    };
  } else {
    out.cannibalization = { status: 'ok', summary: 'No cannibalization detected', columns: [], rows: [] };
  }

  // Experiments status
  const activeExps = exps.filter(e => e.status === 'ACTIVE' || e.status === 'RUNNING');
  const pausedExps = exps.filter(e => e.status === 'PAUSED');
  const expsSlice = exps.slice(0, 20);
  out.experiments_status = {
    status: activeExps.length > 0 ? 'ok' : 'warn',
    summary: `${activeExps.length} active, ${pausedExps.length} paused experiments`,
    columns: ['Experiment', 'Status', 'Days', 'Spend', 'ROAS', 'Organic Verdict', 'Family'],
    expIds: expsSlice.map(e => e.experiment_id),
    rows: expsSlice.map(e => {
      const n = (e.experiment_name || '').toLowerCase();
      const fam = n.includes('lollibox') || n.includes('box') ? 'Lollibox' : n.includes('lollime') || n.includes('mint') ? 'LolliME' : n.includes('bottle') || n.includes('truth') ? 'Bottle' : n.includes('fresh') ? 'Fresh' : '--';
      const days = e.start_date ? String(calcDaysRunning(e.start_date)) : String(e.days_running || '--');
      return [
        e.experiment_name || e.experiment_id, e.status || '--', days,
        fM(e.ads_total_spend), e.ads_avg_roas != null ? fR(e.ads_avg_roas) : '--', e.organic_verdict || '--', fam,
      ];
    }),
  };

  // Campaigns LIVE - filter to peak-specific experiments
  const peakExps = peakName
    ? activeExps.filter(e => {
        const n = (e.experiment_name || e.experiment_id || '').toLowerCase();
        return n.includes(peakName) || (peakName.includes('easter') && n.includes('easter')) ||
               (peakName.includes('valentine') && n.includes('valentine')) ||
               (peakName.includes('christmas') && n.includes('christmas')) ||
               (peakName.includes('halloween') && n.includes('halloween')) ||
               (peakName.includes('mother') && n.includes('mother'));
      })
    : activeExps;
  const allActiveForPeak = peakExps.length > 0 ? peakExps : activeExps;
  out.campaigns_live = {
    status: allActiveForPeak.length > 0 ? 'ok' : 'warn',
    summary: peakExps.length > 0
      ? `${peakExps.length} peak-specific experiments active (${peakName})`
      : allActiveForPeak.length > 0
        ? `${allActiveForPeak.length} active experiments (none peak-specific for "${pk?.holiday_name || '--'}")`
        : 'No active experiments',
    columns: ['Experiment', 'Status', 'Start Date', 'Days Running', 'Family'],
    expIds: allActiveForPeak.map(e => e.experiment_id),
    rows: allActiveForPeak.map(e => {
      const n = (e.experiment_name || '').toLowerCase();
      const fam = n.includes('lollibox') || n.includes('box') ? 'Lollibox' : n.includes('lollime') || n.includes('mint') ? 'LolliME' : n.includes('bottle') || n.includes('truth') ? 'Bottle' : n.includes('fresh') ? 'Fresh' : '--';
      const days = e.start_date ? String(calcDaysRunning(e.start_date)) : String(e.days_running || '--');
      return [e.experiment_name || e.experiment_id, e.status || '', e.start_date || '--', days, fam];
    }),
  };

  // Last year peak Ads best keywords (from drivers/keyword_product_map)
  const lyPeakAdsKw = [...drv]
    .filter(d => (d.orders || 0) > 0)
    .sort((a, b) => (b.orders || 0) - (a.orders || 0))
    .slice(0, 20);
  out.ly_ads_best_keywords = {
    status: lyPeakAdsKw.length > 0 ? 'ok' : 'info',
    summary: `Top ${lyPeakAdsKw.length} keywords by Ads orders (use as peak targets)`,
    columns: ['Keyword', 'Product', 'Family', 'Orders', 'Spend', 'Conv %', 'ROAS'],
    rows: lyPeakAdsKw.map(d => {
      const fam = famFromType(d.product_type) || getFamily(d.product_short_name) || '--';
      return [d.search_term, d.product_short_name, String(fam), fOrd(d.orders), fM(d.spend), fP(d.conv_rate), fR(d.net_roas)];
    }),
  };

  // Last year peak SQP best keywords
  let lySqpPeakStart = '';
  let lySqpPeakEnd = '';
  if (pk?.peak_start && pk?.peak_end) {
    lySqpPeakStart = shiftYear(pk.pre_peak_start || pk.peak_start, -1);
    lySqpPeakEnd = shiftYear(pk.peak_end, -1);
  }
  const lySqpKw = sqp
    .filter(s => s.week_start >= lySqpPeakStart && s.week_start <= lySqpPeakEnd)
    .reduce((acc, s) => {
      if (!acc[s.search_term]) acc[s.search_term] = { term: s.search_term, orders: 0, impressions: 0, clicks: 0, families: new Set<string>() };
      acc[s.search_term].orders += s.orders || 0;
      acc[s.search_term].impressions += s.impressions || 0;
      acc[s.search_term].clicks += s.clicks || 0;
      const fam = famFromType(s.product_type);
      if (fam) acc[s.search_term].families.add(String(fam));
      return acc;
    }, {} as Record<string, { term: string; orders: number; impressions: number; clicks: number; families: Set<string> }>);
  const lySqpSorted = Object.values(lySqpKw).sort((a, b) => b.orders - a.orders).slice(0, 20);
  out.ly_sqp_best_keywords = {
    status: lySqpSorted.length > 0 ? 'ok' : 'info',
    summary: lySqpSorted.length > 0
      ? `Top ${lySqpSorted.length} SQP keywords from last year peak period (${lySqpPeakStart} – ${lySqpPeakEnd})`
      : `No SQP data for last year peak period (${lySqpPeakStart || '--'} – ${lySqpPeakEnd || '--'})`,
    columns: ['Keyword', 'Families', 'Orders (SQP)', 'Impressions', 'Clicks'],
    rows: lySqpSorted.map(s => [s.term, [...s.families].join(', ') || '--', fOrd(s.orders), String(s.impressions.toLocaleString()), String(s.clicks.toLocaleString())]),
  };

  // Hero ASIN check
  const heroMismatch = kw.filter(k => k.is_hero_match === false);
  out.hero_asin_check = {
    status: heroMismatch.length > 0 ? 'warn' : 'ok',
    summary: heroMismatch.length > 0 ? `${heroMismatch.length} keywords NOT on hero ASIN` : 'All keywords on correct hero ASINs',
    columns: ['Keyword', 'Advertised Product', 'Family', 'Hero ASIN', 'ROAS', 'Action'],
    rows: heroMismatch.slice(0, 15).map(k => {
      const fam = getFamily(k.product_short_name) || '--';
      return [k.search_term, k.product_short_name, String(fam), k.hero_asin || '--', fR(k.net_roas_60d), k.action];
    }),
  };

  // Conv rate check
  const lowConv = drv.filter(d => d.conv_rate != null && d.conv_rate < 1.5 && (d.spend || 0) > 10);
  out.conv_rate_check = {
    status: lowConv.length > 3 ? 'warn' : 'ok',
    summary: lowConv.length > 0 ? `${lowConv.length} keywords with conv rate < 1.5%` : 'Conv rates healthy',
    columns: ['Keyword', 'Product', 'Family', 'Conv %', 'Spend', 'Orders', 'ROAS'],
    rows: lowConv.sort((a, b) => (a.conv_rate || 0) - (b.conv_rate || 0)).slice(0, 15).map(d => {
      const fam = famFromType(d.product_type) || getFamily(d.product_short_name) || '--';
      return [d.search_term, d.product_short_name, String(fam), fP(d.conv_rate), fM(d.spend), fOrd(d.orders), fR(d.net_roas)];
    }),
  };

  // Negative keywords (warehouse-owned registry — ENABLED only)
  out.negatives_check = {
    status: neg.length > 0 ? 'ok' : 'info',
    summary: `${neg.length} negative keywords set`,
    columns: ['Keyword', 'Match', 'Campaign', 'Source'],
    rows: neg.slice(0, 20).map(n => [
      n.keyword_text || '--',
      (n.match_type || '').replace('NEGATIVE_', '').toLowerCase() || '--',
      n.campaign_name || '--',
      n.source || '--',
    ]),
  };
  out.negative_keywords = out.negatives_check;

  // Peak keywords (top market volume keywords)
  const topKw = [...kw].sort((a, b) => (b.market_volume || 0) - (a.market_volume || 0));
  const uniqueTerms = [...new Map(topKw.map(k => [k.search_term, k])).values()];
  out.peak_keywords = {
    status: uniqueTerms.length > 0 ? 'ok' : 'warn',
    summary: `${uniqueTerms.length} unique keywords tracked`,
    columns: ['Keyword', 'Product', 'Family', 'Market Vol', 'Impression Share', 'Spend', 'ROAS'],
    rows: uniqueTerms.slice(0, 20).map(k => {
      const fam = getFamily(k.product_short_name) || '--';
      return [k.search_term, k.product_short_name, String(fam), k.market_volume ? String(Math.round(k.market_volume)) + ' ord/wk' : '--', k.impression_share ? fP(k.impression_share * 100) : '--', fM(k.spend_60d), fR(k.net_roas_60d)];
    }),
  };

  // Budget check + budget suggestion
  const bhWithData = bh.filter(b => b.budget_utilization_pct != null);
  const highUtil = bhWithData.filter(b => (b.budget_utilization_pct || 0) > 90);

  // Calculate daily spend from experiments
  const totalDailySpend = exps.reduce((s, e) => {
    const days = e.start_date ? Math.max(1, calcDaysRunning(e.start_date)) : (e.days_running || 1);
    return s + (e.ads_total_spend || 0) / days;
  }, 0);
  const suggestedPeakDaily = totalDailySpend * 1.5;

  out.budget_check = {
    status: highUtil.length > 0 ? 'warn' : 'ok',
    summary: highUtil.length > 0
      ? `${highUtil.length} experiments near budget cap · Current: ${fM(totalDailySpend)}/day → Suggested peak: ${fM(suggestedPeakDaily)}/day (+50%)`
      : `Budget levels healthy · Current: ${fM(totalDailySpend)}/day → Suggested peak: ${fM(suggestedPeakDaily)}/day (+50%)`,
    columns: ['Experiment', 'Budget Util %', 'Daily Spend', 'Suggested Peak'],
    rows: bhWithData.slice(0, 15).map(b => {
      const exp = exps.find(e => e.experiment_id === b.experiment_id);
      const days = exp?.start_date ? Math.max(1, calcDaysRunning(exp.start_date)) : (exp?.days_running || 1);
      const daily = (exp?.ads_total_spend || 0) / days;
      return [b.experiment_id || '--', b.budget_utilization_pct != null ? fP(b.budget_utilization_pct) : '--', fM(daily), fM(daily * 1.5)];
    }),
  };

  // Budget increase suggestion (for PRE_PEAK_BOOST phase)
  const expBudgets = exps.filter(e => e.ads_total_spend).map(e => {
    const days = e.start_date ? Math.max(1, calcDaysRunning(e.start_date)) : (e.days_running || 1);
    const daily = (e.ads_total_spend || 0) / days;
    return { name: e.experiment_name || e.experiment_id, daily, suggested: daily * 1.5 };
  });
  out.budget_increase = {
    status: totalDailySpend > 0 ? 'info' : 'warn',
    summary: totalDailySpend > 0
      ? `Current: ${fM(totalDailySpend)}/day across ${expBudgets.length} experiments → Suggested +50%: ${fM(suggestedPeakDaily)}/day`
      : 'No spend data to base suggestion on',
    columns: ['Experiment', 'Current $/day', 'Suggested Peak $/day', 'Delta'],
    rows: expBudgets.sort((a, b) => b.daily - a.daily).slice(0, 15).map(e => [
      e.name, fM(e.daily), fM(e.suggested), `+${fM(e.suggested - e.daily)}`,
    ]),
  };

  // CPC check from drivers
  const highCpc = drv.filter(d => (d.cpc || 0) > 1.5);
  out.cpc_check = {
    status: highCpc.length > 5 ? 'warn' : 'ok',
    summary: highCpc.length > 0 ? `${highCpc.length} keywords with CPC > $1.50` : 'CPC levels normal',
    columns: ['Keyword', 'Product', 'Family', 'CPC', 'Spend', 'Conv %', 'ROAS'],
    rows: highCpc.sort((a, b) => (b.cpc || 0) - (a.cpc || 0)).slice(0, 15).map(d => {
      const fam = famFromType(d.product_type) || getFamily(d.product_short_name) || '--';
      return [d.search_term, d.product_short_name, String(fam), '$' + (d.cpc || 0).toFixed(2), fM(d.spend), fP(d.conv_rate), fR(d.net_roas)];
    }),
  };

  // Top keywords converting
  const topConv = drv.filter(d => (d.orders || 0) > 0).sort((a, b) => (b.orders || 0) - (a.orders || 0));
  out.top_keywords_conv = {
    status: topConv.length > 0 ? 'ok' : 'warn',
    summary: `${topConv.length} keywords with orders`,
    columns: ['Keyword', 'Product', 'Family', 'Orders', 'Spend', 'Conv %', 'ROAS'],
    rows: topConv.slice(0, 15).map(d => {
      const fam = famFromType(d.product_type) || getFamily(d.product_short_name) || '--';
      return [d.search_term, d.product_short_name, String(fam), fOrd(d.orders), fM(d.spend), fP(d.conv_rate), fR(d.net_roas)];
    }),
  };

  // Peak sales estimate from summary, broken down by family
  const summary = data.summary || [];
  const totalSales7d = summary.reduce((s, r) => s + (r.sales_7d || 0), 0);
  const totalOrders7d = summary.reduce((s, r) => s + (r.orders_7d || 0), 0);
  const run7dRange = summary[0]?.period_start && summary[0]?.period_end ? formatDateRange(summary[0].period_start, summary[0].period_end) : '';
  out.peak_sales_estimate = {
    status: 'info',
    summary: `Current weekly run rate: ${fM(totalSales7d)} / ${fOrd(totalOrders7d)}${run7dRange ? ` (${run7dRange})` : ''}`,
    columns: ['Family', 'Sales 7d', 'Orders 7d', 'Ads ROAS', 'Projected 4wk'],
    rows: summary.map(r => {
      const fam = famFromType(r.product_type) || r.product_type;
      return [String(fam), fM(r.sales_7d), fOrd(r.orders_7d), fR(r.net_roas), fM((r.sales_7d || 0) * 4)];
    }),
  };

  // Ads healthy check from budget health
  const unhealthy = bh.filter(b => (b as unknown as Record<string, unknown>).ads_roas_trend === 'DECLINING');
  out.ads_healthy = {
    status: unhealthy.length > 0 ? 'warn' : 'ok',
    summary: unhealthy.length > 0 ? `${unhealthy.length} experiments with declining ROAS` : 'All ads stable',
    columns: ['Experiment', 'Strategy', 'ROAS Trend', 'Data Status'],
    rows: bh.filter(b => (b as unknown as Record<string, unknown>).ads_roas_trend && (b as unknown as Record<string, unknown>).ads_roas_trend !== 'INSUFFICIENT_DATA').slice(0, 15).map(b => [
      (b as unknown as Record<string, unknown>).experiment_name as string || b.experiment_id,
      (b as unknown as Record<string, unknown>).strategy_id as string || '--',
      (b as unknown as Record<string, unknown>).ads_roas_trend as string || '--',
      (b as unknown as Record<string, unknown>).data_status as string || '--',
    ]),
  };

  // Sales tracking
  out.sales_tracking = out.peak_sales_estimate;

  return out;
}
