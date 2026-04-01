import { useState, useMemo } from 'react';
import type { DashboardData, FamilyName, ExperimentCampaignRow, CampaignSearchTermRow, HolidayRow } from '../types';
import { useFilters } from '../hooks/useFilters';
import { formatSectionFilters } from '../utils/filterUtils';
import { FilterInfoIcon } from '../components/FilterInfoIcon';
import { experimentMatchesFamily } from '../utils';
import { Badge } from '../components/Badge';
import { PageHeader } from '../components/PageHeader';
import { Card } from '../components/Card';
import { Empty } from '../components/Empty';
import { Th, MEASURE_TIPS } from '../components/Tooltip';
import { ChevronRight, ChevronDown, Calendar, TrendingUp } from 'lucide-react';
import { fM, fP, fOrd, fR, fClk, famFromType, famFromProduct } from '../utils';
import { usePageSummary } from '../components/PageSummaryBar';
import { MeasureSelector, useMeasureSelection, type MeasureDef } from '../components/MeasureSelector';

const STAGES = ['READINESS', 'PRE_PEAK', 'PRE_PEAK_BOOST', 'PEAK'] as const;
const STAGE_LABELS: Record<string, string> = { READINESS: 'Readiness', PRE_PEAK: 'Pre Peak', PRE_PEAK_BOOST: 'Boost', PEAK: 'Peak' };
const STAGE_COLORS: Record<string, string> = {
  READINESS: 'from-zinc-700 to-zinc-600',
  PRE_PEAK: 'from-blue-700 to-blue-500',
  PRE_PEAK_BOOST: 'from-amber-700 to-amber-500',
  PEAK: 'from-red-700 to-red-500',
};

const FAMILY_NAMES: FamilyName[] = ['Lollibox', 'LolliME', 'Bottle', 'Fresh'];

type CheckItem = { label: string; dataKey: string };

const CHECKLISTS: Record<string, CheckItem[]> = {
  READINESS: [
    { label: 'Verify ≥ 10 peak keywords are mapped with market volume data (expand to review)', dataKey: 'peak_keywords' },
    { label: 'Create an experiment per product family — confirm status is ACTIVE (expand to review)', dataKey: 'experiments_status' },
    { label: 'Define bid strategy, daily budget & match types per campaign (Campaign Manager)', dataKey: 'campaign_config' },
    { label: 'Add ≥ 5 negative keywords per campaign to block wasted spend (expand to review)', dataKey: 'negative_keywords' },
    { label: 'Create SP + SB campaigns in Amazon Ads console for each experiment', dataKey: 'campaigns_created' },
    { label: 'Confirm FBA stock covers ≥ 6 weeks of projected peak orders (Seller Central → Inventory Planning)', dataKey: 'inventory' },
    { label: 'Configure bid multiplier schedule: TOS placement boost ≥ 50% (Campaign Manager → Placements)', dataKey: 'bid_scaling' },
    { label: 'Set peak sales target per family from current 7d run rate × uplift factor (expand to review)', dataKey: 'peak_sales_estimate' },
  ],
  PRE_PEAK: [
    { label: 'Verify all peak campaigns show status ENABLED in Amazon Ads (expand to review)', dataKey: 'campaigns_live' },
    { label: 'Review LY top Ads keywords by orders — add missing high-converters to campaigns (expand)', dataKey: 'ly_ads_best_keywords' },
    { label: 'Review LY top SQP organic keywords — verify paid coverage for top 10 (expand to review)', dataKey: 'ly_sqp_best_keywords' },
    { label: 'Confirm 0 keywords target a non-hero ASIN — fix any mismatches (expand to see list)', dataKey: 'hero_asin_check' },
    { label: 'Flag keywords with conv rate < 1.5% and spend > $10 — pause or optimize (expand to review)', dataKey: 'conv_rate_check' },
    { label: 'Confirm 0 keywords targeted by multiple products in same family (expand to review)', dataKey: 'cannibalization' },
    { label: 'Verify negative keywords are active on all peak campaigns (expand to review count)', dataKey: 'negatives_check' },
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

export function PeakPage({ data }: { data: DashboardData }) {
  const { filters } = useFilters();
  const pa = data.peak || [];
  const pk = pa[0] || null;
  const [openStages, setOpenStages] = useState<Set<number>>(new Set([STAGES.findIndex(s => s === pk?.current_stage)]));
  const [expandedItems, setExpandedItems] = useState<Set<string>>(new Set());
  const [expandedExps, setExpandedExps] = useState<Set<string>>(new Set());
  const [expandedCampaigns, setExpandedCampaigns] = useState<Set<string>>(new Set());
  const [showYoy, setShowYoy] = useState(true);
  const [selectedHoliday, setSelectedHoliday] = useState<string | null>(null);
  const [selectedMeasures, setSelectedMeasures] = useMeasureSelection('peak_comparison', COMPARISON_MEASURES);
  const [peakTrendMeasure, setPeakTrendMeasure] = useState<PeakTrendMeasure>('orders');
  const [showDailyPeak, setShowDailyPeak] = useState(true);
  const [showLyTopTerms, setShowLyTopTerms] = useState(true);

  const checkData = useMemo(() => buildCheckData(data, pk), [data, pk]);

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
    const cd = checkData;
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
  }, [checkData, expDetails, filters.family, filters.experiment]);

  const holidayNames = useMemo(() => {
    const holidays = data.holidays || [];
    const names = [...new Set(holidays.filter(h => h.category === 'gift_season').map(h => h.holiday_name))].sort();
    return names;
  }, [data.holidays]);

  const activeHolidayName = selectedHoliday || pk?.holiday_name || '';

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
    const readinessStart = pk.readiness_start || pk.peak_start;
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
    const tyStart = tyPhases.pre_peak.start;
    const tyEnd = tyHoliday.holiday_date; // stop at peak day (0 days from peak)
    const lyStart = lyPhases.pre_peak.start;
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
      const diff = Math.round((wMs - hMs) / 86400000);
      if (Math.abs(diff) <= 3) return 'Peak';
      return diff > 0 ? `+${diff}d` : `${diff}d`;
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

  // ── Per-day peak data from ads_7d ──
  const dailyPeakData = useMemo(() => {
    if (!pk || pk.current_stage !== 'PEAK') return null;
    const ads = data.ads_7d || [];
    const peakStart = pk.peak_start;
    const peakEnd = pk.peak_end;
    if (!peakStart || !peakEnd) return null;

    // Group ads_7d by date (day), aggregate per day
    const byDay: Record<string, { date: string; sales: number; spend: number; orders: number; clicks: number; impressions: number }> = {};
    ads.forEach(r => {
      const dateStr = r.date || r.week_start;
      if (!dateStr || dateStr < peakStart || dateStr > peakEnd) return;
      if (filters.family && r.product_short_name) {
        const fam = famFromProduct(r.product_short_name);
        if (fam && fam !== filters.family) return;
      }
      if (!byDay[dateStr]) byDay[dateStr] = { date: dateStr, sales: 0, spend: 0, orders: 0, clicks: 0, impressions: 0 };
      byDay[dateStr].sales += r.sales || 0;
      byDay[dateStr].spend += r.spend || 0;
      byDay[dateStr].orders += r.orders || 0;
      byDay[dateStr].clicks += r.clicks || 0;
      byDay[dateStr].impressions += r.impressions || 0;
    });

    const sorted = Object.values(byDay).sort((a, b) => a.date.localeCompare(b.date));
    if (sorted.length === 0) return null;

    const totalSales = sorted.reduce((s, d) => s + d.sales, 0);
    const totalSpend = sorted.reduce((s, d) => s + d.spend, 0);
    const totalOrders = sorted.reduce((s, d) => s + d.orders, 0);
    return { days: sorted, totalSales, totalSpend, totalOrders };
  }, [data.ads_7d, pk, filters.family]);

  // ── LY top search terms with % contribution ──
  const lyTopTerms = useMemo(() => {
    if (!pk?.peak_start || !pk?.peak_end) return null;
    // Get LY date range
    const lyPeakStart = shiftYear(pk.peak_start, -1);
    const lyPeakEnd = shiftYear(pk.peak_end, -1);

    // Aggregate from SQP data
    const sqp = data.sqp_weekly || [];
    const lyRows = sqp.filter(s => s.week_start >= lyPeakStart && s.week_start <= lyPeakEnd);
    if (lyRows.length === 0) return null;

    const termAgg: Record<string, { term: string; orders: number; impressions: number; clicks: number; families: Set<string> }> = {};
    lyRows.forEach(s => {
      if (!termAgg[s.search_term]) termAgg[s.search_term] = { term: s.search_term, orders: 0, impressions: 0, clicks: 0, families: new Set() };
      termAgg[s.search_term].orders += s.orders || 0;
      termAgg[s.search_term].impressions += s.impressions || 0;
      termAgg[s.search_term].clicks += s.clicks || 0;
      const fam = famFromType(s.product_type);
      if (fam) termAgg[s.search_term].families.add(String(fam));
    });

    const sorted = Object.values(termAgg).sort((a, b) => b.orders - a.orders);
    const totalOrders = sorted.reduce((s, t) => s + t.orders, 0);
    const top20 = sorted.slice(0, 20);
    const top20Orders = top20.reduce((s, t) => s + t.orders, 0);
    const top20Pct = totalOrders > 0 ? (top20Orders / totalOrders) * 100 : 0;

    return {
      terms: top20.map(t => ({
        ...t,
        pctOfTotal: totalOrders > 0 ? (t.orders / totalOrders) * 100 : 0,
        families: [...t.families].join(', '),
      })),
      totalOrders,
      top20Pct,
      dateRange: `${lyPeakStart} – ${lyPeakEnd}`,
    };
  }, [data.sqp_weekly, pk]);

  if (!pk) return <Empty icon="⛰️" message="No upcoming peak" hint="Peak planning activates when a holiday or event is within 6 weeks." />;

  const ci = STAGES.indexOf(pk.current_stage as typeof STAGES[number]);
  const dates = [pk.readiness_start, pk.pre_peak_start, pk.boost_start, pk.peak_start, pk.peak_end]
    .map(d => d ? new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : '--');

  const toggleStage = (i: number) => setOpenStages(p => { const n = new Set(p); n.has(i) ? n.delete(i) : n.add(i); return n; });
  const toggleItem = (key: string) => setExpandedItems(p => { const n = new Set(p); n.has(key) ? n.delete(key) : n.add(key); return n; });

  const peakFilterItems = formatSectionFilters(filters);

  usePageSummary({ title: 'Peak', items: [{ label: 'Peak Planning', value: 'Active' }] });
  return (
    <div className="animate-in">
      <div className="flex items-center gap-2 mb-5">
        <PageHeader title="Next Peak" subtitle="Peak season readiness" />
        {peakFilterItems.length > 0 && <FilterInfoIcon items={peakFilterItems} />}
      </div>

      <Card className={`!border-l-[3px] mb-6 ${ci >= 3 ? '!border-l-red-500' : ci >= 2 ? '!border-l-amber-500' : ci >= 1 ? '!border-l-blue-500' : '!border-l-zinc-500'}`}>
        <div className="flex justify-between items-start mb-2.5">
          <div>
            <div className="text-xl font-extrabold tracking-tight">NEXT PEAK: {pk.holiday_name || '--'}</div>
            <div className="text-xs text-subtle mt-1">
              Holiday: {pk.holiday_date || '--'} · Peak Start: {pk.peak_start || '--'} · Peak End: {pk.peak_end || '--'}
            </div>
          </div>
          <div className="text-right">
            <Badge variant={ci === 0 ? 'muted' : ci === 1 ? 'blue' : ci === 2 ? 'amber' : 'red'} className="!text-xs">
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
            <div key={s} className={`flex items-center justify-center text-white/85 px-2 min-w-[44px] bg-gradient-to-br ${STAGE_COLORS[s]} ${i === ci ? 'outline outline-2 outline-white -outline-offset-2 z-[1]' : ''}`} style={{ flex: i === 3 ? 2 : 1 }}>
              {STAGE_LABELS[s]}
            </div>
          ))}
        </div>
        <div className="flex text-[10px] text-faint font-mono">
          {dates.map((d, i) => <span key={i} className="flex-1 text-center">{d}</span>)}
        </div>
      </Card>

      {/* Peak Trend Chart: TY vs LY — dynamic measure */}
      {peakTrendData && peakTrendData.maxLen > 0 && (
        <Card className="mb-6">
          <div className="flex items-center justify-between mb-3">
            <div className="text-sm font-bold">Peak {PEAK_TREND_MEASURES.find(m => m.id === peakTrendMeasure)?.label || 'Orders'} Trend — TY vs LY</div>
            <div className="flex items-center gap-4 text-[10px] text-faint font-mono">
              <span className="flex items-center gap-1"><span className="w-3 h-2 rounded-sm inline-block" style={{ background: PEAK_TREND_MEASURES.find(m => m.id === peakTrendMeasure)?.color || '#3b82f6' }} /> TY {peakTrendData.tyRange}</span>
              <span className="flex items-center gap-1"><span className="w-3 h-0.5 bg-amber-400 inline-block" style={{ borderTop: '2px dashed' }} /> LY {peakTrendData.lyRange}</span>
            </div>
          </div>
          {/* Measure selector buttons */}
          <div className="flex gap-1.5 mb-3">
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
          {(() => {
            const { tyData, lyData, maxLen, tyBoostIdx, tyPeakIdx } = peakTrendData;
            const mKey = peakTrendMeasure;
            const mColor = PEAK_TREND_MEASURES.find(m => m.id === mKey)?.color || '#3b82f6';
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
            const barW = Math.max(6, Math.min(30, (chartW / maxLen) - 4));
            const xForIdx = (i: number) => PAD_L + (i + 0.5) * (chartW / maxLen);
            const yForVal = (v: number) => PAD_T + chartH - (v / maxVal) * chartH;

            // LY line path
            const lyPoints = lyData.map((d, i) => `${xForIdx(i)},${yForVal(getVal(d))}`);
            const lyPath = lyPoints.length > 0 ? 'M' + lyPoints.join(' L') : '';

            // Grid lines
            const gridLines = [0, 0.25, 0.5, 0.75, 1].map(f => ({
              y: PAD_T + chartH * (1 - f),
              label: fmtVal(maxVal * 0.89 * f), // scale back from headroom
            }));

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
                {tyBoostIdx > 0 && tyBoostIdx < maxLen && (
                  <line x1={xForIdx(tyBoostIdx) - barW / 2 - 2} x2={xForIdx(tyBoostIdx) - barW / 2 - 2} y1={PAD_T} y2={PAD_T + chartH} stroke="rgba(251,191,36,0.4)" strokeWidth={1} strokeDasharray="3,3" />
                )}
                {tyPeakIdx > 0 && tyPeakIdx < maxLen && (
                  <>
                    <line x1={xForIdx(tyPeakIdx) - barW / 2 - 2} x2={xForIdx(tyPeakIdx) - barW / 2 - 2} y1={PAD_T} y2={PAD_T + chartH} stroke="rgba(239,68,68,0.4)" strokeWidth={1} strokeDasharray="3,3" />
                    <text x={xForIdx(tyPeakIdx) - barW / 2 + 2} y={PAD_T + 8} fill="rgba(239,68,68,0.5)" fontSize={7} fontFamily="monospace">Peak</text>
                  </>
                )}

                {/* TY bars + value labels */}
                {tyData.map((d, i) => {
                  const v = getVal(d);
                  const barY = yForVal(v);
                  return (
                    <g key={`ty-${i}`}>
                      <rect
                        x={xForIdx(i) - barW / 2}
                        y={barY}
                        width={barW}
                        height={Math.max(0, PAD_T + chartH - barY)}
                        rx={2}
                        fill={mColor}
                        opacity={0.7}
                      />
                      {/* TY value label above bar */}
                      <text
                        x={xForIdx(i)}
                        y={Math.max(barY - 4, PAD_T - 2)}
                        textAnchor="middle"
                        fill={mColor}
                        fontSize={7}
                        fontFamily="monospace"
                        fontWeight="bold"
                      >{fmtShort(v)}</text>
                    </g>
                  );
                })}

                {/* LY line */}
                {lyPath && (
                  <path d={lyPath} fill="none" stroke="rgba(251,191,36,0.8)" strokeWidth={2} strokeDasharray="6,3" />
                )}
                {/* LY dots + value labels */}
                {lyData.map((d, i) => {
                  const v = getVal(d);
                  const cy = yForVal(v);
                  return (
                    <g key={`ly-${i}`}>
                      <circle cx={xForIdx(i)} cy={cy} r={3} fill="rgba(251,191,36,0.9)" stroke="rgba(0,0,0,0.3)" strokeWidth={0.5} />
                      {/* LY value label below dot */}
                      <text
                        x={xForIdx(i)}
                        y={Math.min(cy + 12, PAD_T + chartH + 2)}
                        textAnchor="middle"
                        fill="rgba(251,191,36,0.7)"
                        fontSize={6}
                        fontFamily="monospace"
                      >{fmtShort(v)}</text>
                    </g>
                  );
                })}

                {/* X-axis labels */}
                {tyData.map((d, i) => (
                  (maxLen <= 12 || i % Math.ceil(maxLen / 10) === 0) && (
                    <text key={`xl-${i}`} x={xForIdx(i)} y={H - 6} textAnchor="middle" fill="rgba(255,255,255,0.35)" fontSize={7} fontFamily="monospace">{d.label}</text>
                  )
                ))}
              </svg>
            );
          })()}
          {/* Notice when LY has no data for selected measure */}
          {peakTrendData.lyData.length > 0 && peakTrendData.lyData.every(d => (d[peakTrendMeasure] || 0) === 0) && (
            <div className="text-[10px] text-amber-400/60 mt-1.5 font-mono">⚠ LY {PEAK_TREND_MEASURES.find(m => m.id === peakTrendMeasure)?.label} data not available for {peakTrendData.lyRange}</div>
          )}
        </Card>
      )}

      {/* ─── Per-Day Peak Performance ─── */}
      {dailyPeakData && dailyPeakData.days.length > 0 && (
        <Card className="mb-6">
          <button onClick={() => setShowDailyPeak(p => !p)} className="flex items-center gap-2 w-full text-left mb-2">
            <Calendar size={16} className="text-red-400" />
            <span className="text-sm font-bold">Daily Peak Performance</span>
            <Badge variant="red">LIVE</Badge>
            <span className="text-[10px] text-faint font-mono ml-1">{dailyPeakData.days.length} days · {fM(dailyPeakData.totalSales)} sales · {fOrd(dailyPeakData.totalOrders)} orders</span>
            <ChevronRight size={12} className={`text-faint ml-auto transition-transform ${showDailyPeak ? 'rotate-90' : ''}`} />
          </button>
          {showDailyPeak && (
            <div className="animate-in">
              {/* Mini daily bar chart */}
              <div className="mb-3">
                {(() => {
                  const days = dailyPeakData.days;
                  const maxSales = Math.max(...days.map(d => d.sales), 1);
                  return (
                    <div className="flex items-end gap-1 h-28">
                      {days.map(d => {
                        const h = (d.sales / maxSales) * 100;
                        const dayLabel = new Date(d.date + 'T00:00:00').toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
                        const roas = d.spend > 0 ? d.sales / d.spend : 0;
                        return (
                          <div key={d.date} className="flex-1 flex flex-col items-center gap-0.5 group relative">
                            <div className="text-[8px] font-mono text-emerald-400 font-bold opacity-0 group-hover:opacity-100 transition-opacity">
                              {fM(d.sales)}
                            </div>
                            <div
                              className="w-full rounded-t-sm bg-gradient-to-t from-red-600 to-red-400 transition-all group-hover:from-red-500 group-hover:to-red-300"
                              style={{ height: `${h}%`, minHeight: 2 }}
                              title={`${dayLabel}\nSales: ${fM(d.sales)}\nSpend: ${fM(d.spend)}\nOrders: ${fOrd(d.orders)}\nROAS: ${fR(roas)}`}
                            />
                            <div className="text-[7px] text-faint font-mono leading-none">
                              {d.date.slice(5)}
                            </div>
                          </div>
                        );
                      })}
                    </div>
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
                      return (
                        <tr key={d.date} className="border-b border-border-faint/50 hover:bg-white/[.02]">
                          <td className="px-2 py-1 font-mono text-foreground">{d.date}</td>
                          <td className="px-2 py-1 text-muted">{dayName}</td>
                          <td className="px-2 py-1 text-right font-mono font-semibold text-emerald-400">{fM(d.sales)}</td>
                          <td className="px-2 py-1 text-right font-mono">{fOrd(d.orders)}</td>
                          <td className="px-2 py-1 text-right font-mono text-amber-400">{fM(d.spend)}</td>
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
                      <th className="text-right px-2 py-1.5">SQP Orders</th>
                      <th className="text-right px-2 py-1.5">% of Total</th>
                      <th className="text-right px-2 py-1.5">Impressions</th>
                      <th className="text-right px-2 py-1.5">Clicks</th>
                      <th className="text-right px-2 py-1.5">Conv %</th>
                    </tr>
                  </thead>
                  <tbody>
                    {lyTopTerms.terms.map((t, i) => {
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
                          <td className="px-2 py-1 text-right font-mono text-muted">{t.impressions.toLocaleString()}</td>
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

      {/* Holiday Selector */}
      {holidayNames.length > 0 && (
        <div className="flex items-center gap-3 mb-4">
          <span className="text-[10px] text-faint uppercase tracking-wider font-semibold">Compare holiday:</span>
          <select
            value={activeHolidayName}
            onChange={e => setSelectedHoliday(e.target.value || null)}
            className="px-2.5 py-1 text-xs font-semibold rounded-lg bg-inset border border-border text-subtle hover:border-border-strong focus:outline-none focus:border-blue-500 appearance-none cursor-pointer"
          >
            {pk?.holiday_name && <option value={pk.holiday_name}>{pk.holiday_name} (next peak)</option>}
            {holidayNames.filter(n => n !== pk?.holiday_name).map(n => <option key={n} value={n}>{n}</option>)}
          </select>
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
                      <span className={`text-xs font-bold px-2 py-0.5 rounded bg-gradient-to-br ${STAGE_COLORS[phase === 'pre_peak' ? 'PRE_PEAK' : phase === 'boost' ? 'PRE_PEAK_BOOST' : phase.toUpperCase()] || 'from-zinc-700 to-zinc-600'} text-white/90`}>
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
            <span className="text-[10px] text-faint font-mono font-normal ml-1">(Readiness → Peak End, calendar shift)</span>
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
  const peakStart = h.pre_season_start;
  const peakEnd = addDaysLocal(h.holiday_date, -2);
  return {
    readiness: { start: addDaysLocal(h.pre_season_start, -120), end: addDaysLocal(h.pre_season_start, -29) },
    pre_peak: { start: addDaysLocal(h.pre_season_start, -28), end: addDaysLocal(h.pre_season_start, -15) },
    boost: { start: addDaysLocal(h.pre_season_start, -14), end: addDaysLocal(h.pre_season_start, -1) },
    peak: { start: peakStart, end: peakEnd },
    full: { start: addDaysLocal(h.pre_season_start, -120), end: peakEnd },
  };
}

type PhaseKey = 'readiness' | 'pre_peak' | 'boost' | 'peak';
const PHASE_KEYS: PhaseKey[] = ['readiness', 'pre_peak', 'boost', 'peak'];
/** Phases shown in the holiday comparison tables (Readiness removed per user request) */
const COMPARISON_PHASE_KEYS: PhaseKey[] = ['pre_peak', 'boost', 'peak'];
const PHASE_LABELS_MAP: Record<PhaseKey, string> = { readiness: 'Readiness', pre_peak: 'Pre Peak', boost: 'Boost', peak: 'Peak' };

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

function buildCheckData(data: DashboardData, pk: DashboardData['peak'][0] | null): Record<string, CheckResult> {
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
        const fam = c.prods.map(p => famFromProduct(p)).filter(Boolean).join(', ');
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
      const fam = famFromType(d.product_type) || famFromProduct(d.product_short_name) || '--';
      return [d.search_term, d.product_short_name, String(fam), fOrd(d.orders), fM(d.spend), fP(d.conv_rate), fR(d.net_roas)];
    }),
  };

  // Last year peak SQP best keywords
  let lySqpPeakStart = '';
  let lySqpPeakEnd = '';
  if (pk?.peak_start && pk?.peak_end) {
    lySqpPeakStart = shiftYear(pk.readiness_start || pk.peak_start, -1);
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
      const fam = famFromProduct(k.product_short_name) || '--';
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
      const fam = famFromType(d.product_type) || famFromProduct(d.product_short_name) || '--';
      return [d.search_term, d.product_short_name, String(fam), fP(d.conv_rate), fM(d.spend), fOrd(d.orders), fR(d.net_roas)];
    }),
  };

  // Negative keywords
  out.negatives_check = {
    status: neg.length > 0 ? 'ok' : 'info',
    summary: `${neg.length} negative keywords set`,
    columns: ['Campaign', 'Negative Keyword', 'Spend 30d'],
    rows: neg.slice(0, 20).map(n => [n.campaign_name || '--', n.negative_keyword || '--', fM(n.spend_30d)]),
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
      const fam = famFromProduct(k.product_short_name) || '--';
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
      const fam = famFromType(d.product_type) || famFromProduct(d.product_short_name) || '--';
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
      const fam = famFromType(d.product_type) || famFromProduct(d.product_short_name) || '--';
      return [d.search_term, d.product_short_name, String(fam), fOrd(d.orders), fM(d.spend), fP(d.conv_rate), fR(d.net_roas)];
    }),
  };

  // Peak sales estimate from summary, broken down by family
  const summary = data.summary || [];
  const totalSales7d = summary.reduce((s, r) => s + (r.sales_7d || 0), 0);
  const totalOrders7d = summary.reduce((s, r) => s + (r.orders_7d || 0), 0);
  out.peak_sales_estimate = {
    status: 'info',
    summary: `Current weekly run rate: ${fM(totalSales7d)} / ${fOrd(totalOrders7d)}`,
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
