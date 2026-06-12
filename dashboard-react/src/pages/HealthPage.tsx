import { useMemo } from 'react';
import type { DashboardData } from '../types';
import { Card } from '../components/Card';
import { Badge } from '../components/Badge';
import { PageHeader } from '../components/PageHeader';
import { usePageSummary } from '../components/PageSummaryBar';
import { CheckCircle, XCircle, AlertTriangle, Clock, Database, Activity, RefreshCw, Info, Layers, Zap } from 'lucide-react';

function formatDateRange(start?: string, end?: string) {
  if (!start || !end) return null;
  return `${start} — ${end}`;
}

/**
 * DATA_CHECKS: Each entry maps a logical data source to the actual field in DashboardData.
 * The Health page now reads directly from the loaded data arrays instead of
 * looking at _meta.files (which was a legacy JSON-file system that no longer exists).
 *
 * - dataKey: the property name in DashboardData
 * - cubeSource: which Cube schema/loader supplies this data
 * - minRows: minimum rows expected for a "healthy" status
 * - critical: if true, missing data shows as MISSING (red); else EMPTY (amber) or N/A
 * - loaderName: matches the name used in resolveLoader() for error tracking
 */
const DATA_CHECKS: {
  label: string;
  dataKey: keyof DashboardData;
  cubeSource: string;
  minRows: number;
  critical: boolean;
  loaderName: string;
}[] = [
  // Priority loaders (loaded first, blocking)
  { label: 'Summary (per-family KPIs)',     dataKey: 'summary',               cubeSource: 'UnifiedPerformance', minRows: 1, critical: true,  loaderName: 'summary' },
  { label: 'Products (catalog + costs)',    dataKey: 'products',              cubeSource: 'Product',            minRows: 1, critical: true,  loaderName: 'products' },
  { label: 'Weekly trends',                 dataKey: 'weekly_trends',         cubeSource: 'UnifiedPerformance', minRows: 4, critical: true,  loaderName: 'weeklyTrends' },
  { label: 'Monthly trends',                dataKey: 'monthly_trends',        cubeSource: 'UnifiedPerformance', minRows: 4, critical: true,  loaderName: 'monthlyTrends' },
  { label: 'Weekly trends (ASIN)',          dataKey: 'weekly_trends_by_asin', cubeSource: 'UnifiedPerformance', minRows: 4, critical: true,  loaderName: 'weeklyTrendsByAsin' },
  { label: 'Monthly trends (ASIN)',         dataKey: 'monthly_trends_by_asin',cubeSource: 'UnifiedPerformance', minRows: 4, critical: true,  loaderName: 'monthlyTrendsByAsin' },
  { label: 'Product Creatives',             dataKey: 'product_creatives',     cubeSource: 'DimProductCreatives',minRows: 0, critical: false, loaderName: 'productCreatives' },
  { label: 'Experiments',                   dataKey: 'experiments',           cubeSource: 'Experiment',         minRows: 0, critical: false, loaderName: 'experiments' },
  { label: 'Ads summary (7d)',              dataKey: 'ads_7d_summary',        cubeSource: 'Ads',                minRows: 0, critical: false, loaderName: 'adsSummary' },

  // Light background loaders
  { label: 'Change log',                    dataKey: 'change_log',            cubeSource: 'ChangeLog',          minRows: 0, critical: false, loaderName: 'changeLog' },
  { label: 'Upcoming events',               dataKey: 'upcoming',              cubeSource: 'DimTime',            minRows: 0, critical: false, loaderName: 'upcoming' },
  { label: 'Peak data',                     dataKey: 'peak',                  cubeSource: 'DimTime',            minRows: 0, critical: false, loaderName: 'peak' },
  { label: 'Hero ASINs',                    dataKey: 'hero_asins',            cubeSource: 'V_PARENT_HERO_ASIN', minRows: 1, critical: false, loaderName: 'heroAsins' },
  { label: 'Keyword-product map',           dataKey: 'keyword_product_map',   cubeSource: 'ExperimentTermRecommendations',  minRows: 1, critical: true,  loaderName: 'keywordProductMap' },
  { label: 'Learnings',                     dataKey: 'learnings',             cubeSource: 'AdsLearning',        minRows: 0, critical: false, loaderName: 'learnings' },
  { label: 'Budget health',                 dataKey: 'budget_health',         cubeSource: 'V_EXPERIMENT_BUDGET_HEALTH', minRows: 0, critical: false, loaderName: 'budgetHealth' },
  { label: 'Drivers',                       dataKey: 'drivers',               cubeSource: 'V_WEEKLY_DRIVERS',   minRows: 1, critical: true,  loaderName: 'drivers' },
  { label: 'Experiment weekly',             dataKey: 'experiment_weekly',     cubeSource: 'ExperimentDaily',    minRows: 0, critical: false, loaderName: 'experimentWeekly' },
  { label: 'Experiment campaigns',          dataKey: 'experiment_campaigns',  cubeSource: 'ExperimentCampaign', minRows: 0, critical: false, loaderName: 'experimentCampaigns' },
  { label: 'Campaign search terms',         dataKey: 'campaign_search_terms', cubeSource: 'CampaignSearchTerms', minRows: 0, critical: false, loaderName: 'campaignSearchTerms' },
  { label: 'Experiment templates',          dataKey: 'experiment_templates',  cubeSource: 'ExperimentTemplate', minRows: 0, critical: false, loaderName: 'experimentTemplates' },
  { label: 'Experiment evaluations',        dataKey: 'experiment_evaluations',cubeSource: 'ExperimentEvaluation', minRows: 0, critical: false, loaderName: 'experimentEvaluations' },
  { label: 'Keyword predictions',           dataKey: 'keyword_predictions',   cubeSource: 'KeywordStrategyPrediction', minRows: 0, critical: false, loaderName: 'keywordPredictions' },
  { label: 'Holidays',                      dataKey: 'holidays',              cubeSource: 'DimTime',            minRows: 0, critical: false, loaderName: 'holidays' },
  { label: 'Coach decisions',               dataKey: 'coach_decisions',       cubeSource: 'AdsCoachDecision',   minRows: 0, critical: false, loaderName: 'coachDecisions' },
  { label: 'Actions (recommendations)',     dataKey: 'actions',               cubeSource: 'AdsCoachActions',    minRows: 1, critical: true,  loaderName: 'coachTerms' },
  { label: 'Coach campaigns',               dataKey: 'coach_campaigns',       cubeSource: 'AdsCoachCampaigns',  minRows: 0, critical: false, loaderName: 'coachCampaigns' },
  { label: 'Coach strategy',                dataKey: 'coach_strategy',        cubeSource: 'AdsCoachStrategy',   minRows: 0, critical: false, loaderName: 'coachStrategy' },
  { label: 'Brand strength',                dataKey: 'brand_strength_weekly', cubeSource: 'BrandStrength',      minRows: 0, critical: false, loaderName: 'brandStrength' },
  { label: 'Phrase negatives',              dataKey: 'coach_phrase_negatives',cubeSource: 'PhraseMatcher',      minRows: 0, critical: false, loaderName: 'phraseNegatives' },
  { label: 'Hot signals',                   dataKey: 'hot_signals',           cubeSource: 'HotSignal',          minRows: 0, critical: false, loaderName: 'hotSignals' },
  { label: 'Daily trends',                  dataKey: 'daily_trends',          cubeSource: 'UnifiedPerformance', minRows: 0, critical: false, loaderName: 'dailyTrends' },
  { label: 'Storage costs',                 dataKey: 'storage_costs',         cubeSource: 'StorageCost',        minRows: 0, critical: false, loaderName: 'storageCosts' },
  { label: 'Supply chain',                  dataKey: 'supply_chain',          cubeSource: 'SupplyChain',        minRows: 0, critical: false, loaderName: 'supplyChain' },
  { label: 'Supply POs',                    dataKey: 'supply_pos',            cubeSource: 'PurchaseOrdersDashboard', minRows: 0, critical: false, loaderName: 'supplyPOs' },
  { label: 'Supply Payments',               dataKey: 'supply_payments',       cubeSource: 'VendorPaymentsDashboard', minRows: 0, critical: false, loaderName: 'supplyPayments' },
  { label: 'Supply Shipments',              dataKey: 'supply_shipments',      cubeSource: 'ShipmentsDashboard', minRows: 0, critical: false, loaderName: 'supplyShipments' },
  { label: 'Peak relevance',                dataKey: 'peak_relevance',        cubeSource: 'PeakRelevance',      minRows: 0, critical: false, loaderName: 'peakRelevance' },
  { label: 'Family occasions',              dataKey: 'family_occasions',      cubeSource: 'FamilyOccasionMap',  minRows: 0, critical: false, loaderName: 'familyOccasions' },

  // Heavy background loaders
  { label: 'Ads campaign detail',           dataKey: 'ads_7d',                cubeSource: 'Ads',                minRows: 1, critical: true,  loaderName: 'ads' },
  { label: 'SQP weekly',                    dataKey: 'sqp_weekly',            cubeSource: 'Sqp',                minRows: 1, critical: true,  loaderName: 'sqp' },
];

export function HealthPage({ data }: { data: DashboardData }) {
  const meta = data._meta || {};
  const refreshed = meta.refreshed_at ? new Date(meta.refreshed_at) : null;
  const dr = meta.date_ranges?.summary_7d;
  const rangeStr = formatDateRange(dr?.start, dr?.end);
  const failedQueries = meta.failed_queries || [];

  const staleness = useMemo(() => {
    if (!refreshed) return null;
    const hours = (Date.now() - refreshed.getTime()) / 3600000;
    return hours;
  }, [refreshed]);

  const checks = useMemo(() => {
    return DATA_CHECKS.map(c => {
      const rawVal = data[c.dataKey];
      const rows = Array.isArray(rawVal) ? rawVal.length : (rawVal && typeof rawVal === 'object' ? Object.keys(rawVal).length : 0);
      const hasError = failedQueries.includes(c.loaderName);
      const belowMin = rows < c.minRows;
      const ok = !hasError && !belowMin;
      return { ...c, rows, hasError, belowMin, ok };
    });
  }, [data, failedQueries]);

  const loaded = checks.filter(c => c.ok);
  const failed = checks.filter(c => !c.ok && c.critical);
  const warnings = checks.filter(c => !c.ok && !c.critical);

  const costCoverage = useMemo(() => {
    const prods = data.products || [];
    const total = prods.length;
    const withCost = prods.filter(p => p.total_cost_per_unit && p.total_cost_per_unit > 0).length;
    return { total, withCost, pct: total ? Math.round((withCost / total) * 100) : 0 };
  }, [data.products]);

  const summaryChecks = useMemo(() => {
    const s = data.summary || [];
    const issues: { family: string; issue: string; severity: 'warn' | 'error' }[] = [];
    s.forEach(r => {
      if (!r.cogs_7d || r.cogs_7d === 0) issues.push({ family: r.product_type, issue: 'Missing COGS — Net Profit and Net ROAS will be inaccurate', severity: 'error' });
      if (r.sessions_7d === 0 && r.orders_7d > 0) issues.push({ family: r.product_type, issue: 'Orders without sessions — Business Report data may be lagging', severity: 'warn' });
      if (r.ad_cost_7d > r.sales_7d) issues.push({ family: r.product_type, issue: 'Ads spend exceeds sales — check campaigns', severity: 'warn' });
    });
    return issues;
  }, [data.summary]);

  // Data freshness from meta
  const adsFreshness = meta.data_freshness?.ads_max_date;
  const perfFreshness = meta.data_freshness?.performance_max_date;

  usePageSummary({
    title: 'Health',
    items: [
      { label: 'Loaded', value: `${loaded.length}`, color: 'green' },
      { label: 'Failed', value: `${failed.length}`, color: failed.length > 0 ? 'red' : undefined },
      { label: 'Warnings', value: `${warnings.length}`, color: warnings.length > 0 ? 'amber' : undefined },
      { label: 'Queries', value: `${meta.queries_run ?? '—'}` },
    ],
  });

  return (
    <div className="animate-in">
      <PageHeader title="System Health" subtitle="Pipeline status, data integrity & freshness monitoring" />

      {/* Overall Status Banner */}
      <div className={`border rounded-xl p-5 mb-5 ${failed.length === 0 ? 'border-emerald-500/25 bg-emerald-500/[.04]' : 'border-red-500/25 bg-red-500/[.04]'}`}>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            {failed.length === 0 ? (
              <div className="w-10 h-10 rounded-xl bg-emerald-500/15 flex items-center justify-center">
                <CheckCircle size={20} className="text-emerald-400" />
              </div>
            ) : (
              <div className="w-10 h-10 rounded-xl bg-red-500/15 flex items-center justify-center">
                <XCircle size={20} className="text-red-400" />
              </div>
            )}
            <div>
              <div className="text-lg font-bold">{failed.length === 0 ? 'All Systems Healthy' : `${failed.length} Critical Issue${failed.length !== 1 ? 's' : ''}`}</div>
              <div className="text-xs text-subtle flex items-center gap-3 mt-0.5">
                <span className="flex items-center gap-1"><CheckCircle size={10} className="text-emerald-400" />{loaded.length} loaded</span>
                {failed.length > 0 && <span className="flex items-center gap-1"><XCircle size={10} className="text-red-400" />{failed.length} failed</span>}
                {warnings.length > 0 && <span className="flex items-center gap-1"><AlertTriangle size={10} className="text-amber-400" />{warnings.length} warnings</span>}
                <span className="flex items-center gap-1"><Database size={10} className="text-blue-400" />{meta.queries_run ?? 0} queries</span>
              </div>
            </div>
          </div>
          <div className="text-right">
            {refreshed && (
              <div className="flex items-center gap-1.5 font-mono text-xs">
                <Clock size={12} className="text-faint" />
                {refreshed.toLocaleDateString()} {refreshed.toLocaleTimeString()}
              </div>
            )}
            {staleness != null && (
              <div className={`text-[11px] mt-0.5 ${staleness > 24 ? 'text-red-400 font-semibold' : staleness > 6 ? 'text-amber-400' : 'text-subtle'}`}>
                {staleness < 1 ? 'Just now' : staleness < 24 ? `${Math.round(staleness)}h ago` : `${Math.round(staleness / 24)}d ago — stale!`}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* KPI Strip */}
      <div className="grid grid-cols-5 gap-3 mb-5">
        <Card className="!p-4">
          <div className="text-[10px] text-subtle uppercase tracking-wider font-semibold mb-1 flex items-center gap-1"><Activity size={10} />Data Period</div>
          <div className="text-lg font-bold font-mono">{rangeStr || '--'}</div>
          <div className="text-[11px] text-subtle">7-day reporting window</div>
        </Card>
        <Card className="!p-4">
          <div className="text-[10px] text-subtle uppercase tracking-wider font-semibold mb-1 flex items-center gap-1"><Database size={10} />COGS Coverage</div>
          <div className={`text-lg font-bold font-mono ${costCoverage.pct === 100 ? 'text-emerald-400' : costCoverage.pct >= 80 ? 'text-amber-400' : 'text-red-400'}`}>
            {costCoverage.withCost}/{costCoverage.total} ({costCoverage.pct}%)
          </div>
          <div className="text-[11px] text-subtle">Products with cost data</div>
        </Card>
        <Card className="!p-4">
          <div className="text-[10px] text-subtle uppercase tracking-wider font-semibold mb-1 flex items-center gap-1"><RefreshCw size={10} />Pipeline Queries</div>
          <div className="text-lg font-bold font-mono">{meta.queries_run ?? 0}</div>
          <div className={`text-[11px] ${(meta.queries_failed ?? 0) > 0 ? 'text-red-400' : 'text-subtle'}`}>{meta.queries_failed ?? 0} failed</div>
        </Card>
        <Card className="!p-4">
          <div className="text-[10px] text-subtle uppercase tracking-wider font-semibold mb-1 flex items-center gap-1"><Zap size={10} />Ads Data</div>
          <div className="text-lg font-bold font-mono">{adsFreshness || '--'}</div>
          <div className="text-[11px] text-subtle">Latest ads date</div>
        </Card>
        <Card className="!p-4">
          <div className="text-[10px] text-subtle uppercase tracking-wider font-semibold mb-1 flex items-center gap-1"><Layers size={10} />Families</div>
          <div className="text-lg font-bold font-mono">{(data.summary || []).length}</div>
          <div className="text-[11px] text-subtle">Active in summary data</div>
        </Card>
      </div>

      {/* Data Integrity Warnings */}
      {summaryChecks.length > 0 && (
        <div className="mb-5">
          <div className="text-sm font-bold mb-3 flex items-center gap-2"><AlertTriangle size={14} className="text-amber-400" />Data Integrity Warnings</div>
          <div className="space-y-1.5">
            {summaryChecks.map((c, i) => (
              <div key={i} className={`flex items-center gap-2.5 px-4 py-2.5 rounded-xl border ${c.severity === 'error' ? 'border-red-500/20 bg-red-500/[.04]' : 'border-amber-500/20 bg-amber-500/[.04]'}`}>
                {c.severity === 'error' ? <XCircle size={14} className="text-red-400" /> : <AlertTriangle size={14} className="text-amber-400" />}
                <Badge variant={c.severity === 'error' ? 'red' : 'amber'}>{c.family}</Badge>
                <span className="text-[11px] text-muted">{c.issue}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Pipeline Status Table */}
      <div className="mb-5">
        <div className="text-sm font-bold mb-3 flex items-center gap-2"><Database size={14} className="text-blue-400" />Pipeline Status — Data Sources</div>
        <div className="border border-border rounded-xl bg-card overflow-hidden">
          <table className="w-full border-collapse text-xs">
            <thead>
              <tr>
                {['Data Source', 'Status', 'Rows', 'Min', 'Type', 'Cube Source'].map(h => (
                  <th key={h} className={`bg-inset text-subtle text-left px-3 py-2.5 font-semibold text-[10px] uppercase tracking-wider border-b border-border ${h === 'Rows' || h === 'Min' ? 'text-right' : ''}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {checks.map((c, i) => (
                <tr key={i} className={`border-b border-border-faint last:border-b-0 transition-colors ${!c.ok ? (c.critical ? 'bg-red-500/[.03]' : 'bg-amber-500/[.03]') : 'hover:bg-white/[.02]'}`}>
                  <td className="px-3 py-2">
                    <div className="font-semibold flex items-center gap-1.5">
                      {c.ok ? (
                        <CheckCircle size={12} className="text-emerald-400 shrink-0" />
                      ) : c.hasError ? (
                        <XCircle size={12} className="text-red-400 shrink-0" />
                      ) : (
                        <AlertTriangle size={12} className={`${c.critical ? 'text-red-400' : 'text-amber-400'} shrink-0`} />
                      )}
                      {c.label}
                    </div>
                    {c.hasError && <div className="text-[10px] text-red-400 mt-0.5 font-mono">Query failed — check Cube API logs</div>}
                  </td>
                  <td className="px-3 py-2">
                    {c.hasError ? (
                      <Badge variant="red">FAILED</Badge>
                    ) : c.ok ? (
                      <Badge variant="green">LOADED</Badge>
                    ) : c.belowMin && c.critical ? (
                      <Badge variant="red">MISSING</Badge>
                    ) : c.belowMin && c.minRows > 0 ? (
                      <Badge variant="amber">EMPTY</Badge>
                    ) : c.rows === 0 && !c.critical ? (
                      <Badge variant="muted">N/A</Badge>
                    ) : (
                      <Badge variant="green">LOADED</Badge>
                    )}
                  </td>
                  <td className="px-3 py-2 text-right font-mono font-medium">{c.rows > 0 ? c.rows.toLocaleString() : '—'}</td>
                  <td className="px-3 py-2 text-right font-mono text-faint">{c.minRows > 0 ? `≥${c.minRows}` : '--'}</td>
                  <td className="px-3 py-2">
                    <Badge variant={c.critical ? 'red' : 'muted'}>{c.critical ? 'Critical' : 'Optional'}</Badge>
                  </td>
                  <td className="px-3 py-2 text-[11px] text-subtle font-mono">{c.cubeSource}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Explanation */}
      <div className="mb-5">
        <div className="text-sm font-bold mb-3 flex items-center gap-2"><Info size={14} className="text-cyan-400" />How This Page Works</div>
        <Card className="!p-4">
          <div className="text-[11px] text-muted space-y-2">
            <p>
              This page monitors the <strong className="text-[var(--color-text)]">live state of data loaded from Cube.js API</strong>.
              Each row represents a data source that the dashboard queries on startup.
            </p>
            <div className="grid grid-cols-2 gap-4 mt-3">
              <div>
                <div className="font-semibold text-[var(--color-text)] mb-1">Status Badges</div>
                <div className="space-y-1">
                  <div className="flex items-center gap-2"><Badge variant="green">LOADED</Badge> <span>Data successfully fetched from Cube API</span></div>
                  <div className="flex items-center gap-2"><Badge variant="red">MISSING</Badge> <span>Critical data not available — page may show $0</span></div>
                  <div className="flex items-center gap-2"><Badge variant="red">FAILED</Badge> <span>Cube query threw an error (timeout, OOM, etc.)</span></div>
                  <div className="flex items-center gap-2"><Badge variant="amber">EMPTY</Badge> <span>Query ran but returned 0 rows</span></div>
                  <div className="flex items-center gap-2"><Badge variant="muted">N/A</Badge> <span>Optional data — no rows expected</span></div>
                </div>
              </div>
              <div>
                <div className="font-semibold text-[var(--color-text)] mb-1">Data Flow</div>
                <div className="space-y-1 font-mono text-[10px]">
                  <div className="flex items-center gap-2">
                    <span className="text-blue-400">BigQuery</span>
                    <span className="text-faint">→</span>
                    <span className="text-purple-400">Cube.js API</span>
                    <span className="text-faint">→</span>
                    <span className="text-emerald-400">Dashboard</span>
                  </div>
                  <div className="mt-2 text-muted text-[11px] font-sans">
                    All data flows through Cube.js which queries BigQuery.
                    Pre-aggregations are currently disabled — queries go directly to BigQuery.
                  </div>
                </div>
              </div>
            </div>
          </div>
        </Card>
      </div>

      {/* Calculation Reference */}
      <div className="mb-5">
        <div className="text-sm font-bold mb-3 flex items-center gap-2"><Info size={14} className="text-purple-400" />Calculation Reference</div>
        <Card className="!p-4">
          <div className="grid grid-cols-2 gap-x-8 gap-y-2 text-[11px]">
            {[
              ['Net Profit', 'Sales − Ads Spend − COGS'],
              ['COGS', 'Units Sold × Total Cost Per Unit (from DIM_COSTS_HISTORY)'],
              ['Total Cost Per Unit', 'Cost of Goods + Shipping + FBA Fees'],
              ['Net ROAS', '(Sales − COGS) ÷ Ads Spend'],
              ['Organic %', 'Organic Orders ÷ Total Orders × 100'],
              ['Organic Orders', 'Total Orders (Business Report) − Ad Orders (FACT_AMAZON_ADS)'],
              ['Conv Rate (CVR)', 'Total Orders ÷ Sessions × 100'],
            ].map(([l, v]) => (
              <div key={l} className="flex gap-2 py-1 border-b border-border-faint">
                <span className="font-semibold text-muted min-w-[120px]">{l}</span>
                <span className="text-subtle font-mono text-[10px]">{v}</span>
              </div>
            ))}
          </div>
        </Card>
      </div>

      {/* Data Sources */}
      <div className="mb-5">
        <div className="text-sm font-bold mb-3 flex items-center gap-2"><Database size={14} className="text-cyan-400" />BigQuery Sources</div>
        <Card className="!p-4">
          <div className="space-y-2 text-[11px]">
            {[
              { src: 'V_SRC_sales_and_traffic_business_sku_report_daily', desc: 'Total sales, orders, sessions (Amazon Business Report)', lag: '~2 day lag' },
              { src: 'FACT_AMAZON_ADS', desc: 'Ad spend, clicks, ad orders, impressions', lag: 'Same day' },
              { src: 'DIM_COSTS_HISTORY', desc: 'COGS, shipping, FBA fees per ASIN', lag: 'Manual updates' },
              { src: 'DIM_PRODUCT', desc: 'Product catalog, family mapping, pricing', lag: 'Manual updates' },
              { src: 'FACT_EXPERIMENT_DAILY', desc: 'Experiment-level performance data', lag: 'Same day' },
              { src: 'DIM_US_HOLIDAYS', desc: 'Holiday calendar, peak dates', lag: 'Static' },
              { src: 'V_ADS_COACH_DECISION', desc: 'Coach recommendations, SQP enrichment', lag: 'Computed' },
              { src: 'V_BRAND_STRENGTH_WEEKLY', desc: 'Brand keyword health + dominance', lag: 'Computed' },
              { src: 'FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY', desc: 'SQP data (search terms, show rate, rank)', lag: '~1 week lag' },
            ].map(s => (
              <div key={s.src} className="flex items-center gap-3 py-1.5 border-b border-border-faint last:border-b-0">
                <code className="text-blue-400 font-mono text-[10px] min-w-[300px]">{s.src}</code>
                <span className="text-muted flex-1">{s.desc}</span>
                <Badge variant="muted">{s.lag}</Badge>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </div>
  );
}
