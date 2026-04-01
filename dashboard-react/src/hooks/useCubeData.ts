/**
 * Cube.js data hook - fetches from Cube via @cubejs-client/core SDK.
 * Use when VITE_CUBE_API_URL is set. Overlays Cube data on top of JSON fallback.
 *
 * Loading strategy: priority loaders (summary, trends, products) complete first
 * so the UI renders immediately. Background loaders (ads, sqp, etc.) fill in after.
 */
import { useState, useEffect } from 'react';
import type {
  DashboardData,
  Ads7dRow,
  SqpWeeklyRow,
  ChangeLogRow,
  UpcomingEvent,
  PeakRow,
  ExperimentWeeklyRow,
  ProductRow,
  CampaignSearchTermRow,
  SummaryRow,
  ActionRow,
  TrendRow,
  TrendRowByAsin,
  LearningRow,
  ExperimentRow,
  BudgetHealthRow,
  DriverRow,
  HeroAsin,
  KeywordMapRow,
  ExperimentCampaignRow,
  ExperimentTemplateRow,
  HolidayRow,
  CoachDecisionRow,
  CoachTermRow,
  CoachCampaignRow,
  ExperimentEvaluationRow,
  StrategicPrediction,
  BrandStrengthWeeklyRow,
  PhraseNegativeRow,
  ProductCreativeRow,
  HotSignalRow,
} from '../types';

// In dev, always try Cube via proxy even if env not loaded
const CUBE_API = import.meta.env.VITE_CUBE_API_URL || (import.meta.env.DEV ? 'http://localhost:4000' : '');

type CubeLoadResult = { data: unknown[]; lastRefreshTime?: string; usedPreAggregations?: Record<string, unknown> };

async function cubeLoad(query: object): Promise<unknown[]> {
  const r = await cubeLoadWithMeta(query);
  return r.data;
}

async function cubeLoadWithMeta(query: object, maxRetries = 20): Promise<CubeLoadResult> {
  if (!CUBE_API) return { data: [] };
  try {
    let retries = 0;
    while (retries < maxRetries) {
      const res = await fetch(`${CUBE_API}/cubejs-api/v1/load`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query }),
      });
      if (!res.ok) throw new Error(`Cube HTTP ${res.status}`);
      const json = await res.json();

      if (json.error === 'Continue wait') {
        retries++;
        if (import.meta.env.DEV) console.log(`[cubeLoad] Continue wait... (${retries}/${maxRetries})`);
        await new Promise(r => setTimeout(r, 2000));
        continue;
      }
      if (json.error) {
         console.error('[cubeLoad] API returned error:', json.error);
         break;
      }

      return {
        data: json.data ?? [],
        lastRefreshTime: json.lastRefreshTime,
        usedPreAggregations: json.usedPreAggregations,
      };
    }
    return { data: [] };
  } catch (e) {
    if (import.meta.env.DEV) console.warn('[cubeLoad] fetch failed:', e);
    return { data: [] };
  }
}

function fmtDate(v: unknown): string {
  if (!v) return '';
  return String(v).slice(0, 10);
}

function mapAdsRow(r: Record<string, unknown>): Ads7dRow {
  const dateVal = r['Ads.date'] ?? r['Ads.date.week'] ?? r['Ads.date.day'];
  const dateStr = dateVal ? fmtDate(dateVal) : '';
  // Prefer Ads.weekStart (Sunday-aligned) over deriving from date
  const weekStartRaw = r['Ads.weekStart'] ? fmtDate(r['Ads.weekStart']) : '';
  const weekStart = weekStartRaw || (dateStr ? getWeekStart(dateStr) : '');
  const spend = Number(r['Ads.spend'] ?? 0);
  const orders = Number(r['Ads.orders'] ?? 0);
  const clicks = Number(r['Ads.clicks'] ?? 0);
  const impressions = Number(r['Ads.impressions'] ?? 0);
  const sales = Number(r['Ads.sales'] ?? 0);
  const cogs = Number(r['Ads.cogs'] ?? 0);
  const grossProfit = r['Ads.grossProfit'] != null ? Number(r['Ads.grossProfit']) : null;
  const cpc = clicks ? spend / clicks : 0;
  const convRate = clicks ? (orders * 100) / clicks : 0;
  const roas = spend ? (sales - cogs) / spend : 0;
  return {
    row_type: r['Ads.searchTerm'] ? 'search_term' : 'campaign',
    date: dateStr || undefined,
    week_start: weekStart,
    campaign_id: String(r['Ads.campaignId'] ?? ''),
    campaign_name: String(r['Ads.campaignName'] ?? ''),
    campaign_type: r['Ads.campaignType'] != null ? String(r['Ads.campaignType']) : null,
    portfolio_name: null,
    product_short_name: r['Product.productShortName'] != null ? String(r['Product.productShortName']) : '',
    parent_name: r['Product.parentName'] != null ? String(r['Product.parentName']) : null,
    search_term: r['Ads.searchTerm'] ? String(r['Ads.searchTerm']) : null,
    spend,
    orders,
    clicks,
    impressions,
    sales,
    cogs,
    gross_profit: grossProfit,
    cpc,
    conv_rate: convRate,
    roas,
    search_terms_count: null,
  };
}

/**
 * Ads Summary → ads_7d_summary (campaign-level only, no searchTerm/Product).
 * Matches the existing adsByWeekCampaign pre-aggregation → sub-second response.
 * Used by HOME page for KPI, family table, and trend charts.
 */
async function loadAdsSummaryFromCube(): Promise<Ads7dRow[]> {
  const rows = await cubeLoad({
    measures: ['Ads.spend', 'Ads.orders', 'Ads.clicks', 'Ads.impressions', 'Ads.sales', 'Ads.cogs', 'Ads.grossProfit'],
    dimensions: ['Ads.campaignId', 'Ads.campaignName', 'Ads.campaignType', 'Product.productShortName', 'Ads.weekStart'],
    timeDimensions: [{ dimension: 'Ads.date', dateRange: 'Last 730 days' }],
    order: { 'Ads.weekStart': 'desc' },
    filters: [
      { member: 'Ads.spend', operator: 'gt', values: ['0'] }
    ],
    limit: 50000,
  });
  return (rows as Record<string, unknown>[]).map(r => mapAdsRow(r));
}

/**
 * Ads → ads_7d (3 years, campaign-week granularity).
 * Aggregated at campaign × week level (~2-3k rows) instead of campaign × search_term × day
 * (millions of rows). Search-term detail is loaded separately via campaign_search_terms.
 */
async function loadAdsFromCube(): Promise<Ads7dRow[]> {
  // Try 6-month window first (covers most analytics needs)
  try {
    const rows = await cubeLoad({
      measures: ['Ads.spend', 'Ads.orders', 'Ads.clicks', 'Ads.impressions', 'Ads.sales', 'Ads.cogs', 'Ads.grossProfit'],
      dimensions: ['Ads.campaignId', 'Ads.campaignName', 'Ads.campaignType', 'Ads.weekStart', 'Product.productShortName', 'Product.parentName'],
      timeDimensions: [{ dimension: 'Ads.date', dateRange: 'Last 180 days' }],
      order: { 'Ads.spend': 'desc' },
      filters: [
        { member: 'Ads.spend', operator: 'gt', values: ['0'] }
      ],
      limit: 50000,
    });
    return (rows as Record<string, unknown>[]).map(r => mapAdsRow(r));
  } catch (err) {
    console.warn('[useCubeData] Ads 180d query failed, retrying with 60 days:', err);
    // Fallback: 60-day window with lower limit
    const rows = await cubeLoad({
      measures: ['Ads.spend', 'Ads.orders', 'Ads.clicks', 'Ads.impressions', 'Ads.sales', 'Ads.cogs', 'Ads.grossProfit'],
      dimensions: ['Ads.campaignId', 'Ads.campaignName', 'Ads.campaignType', 'Ads.weekStart', 'Product.productShortName', 'Product.parentName'],
      timeDimensions: [{ dimension: 'Ads.date', dateRange: 'Last 60 days' }],
      order: { 'Ads.spend': 'desc' },
      filters: [
        { member: 'Ads.spend', operator: 'gt', values: ['0'] }
      ],
      limit: 20000,
    });
    return (rows as Record<string, unknown>[]).map(r => mapAdsRow(r));
  }
}

/** Sqp → sqp_weekly */
async function loadSqpFromCube(): Promise<SqpWeeklyRow[]> {
  const rows = await cubeLoad({
    measures: [
      'Sqp.impressions', 'Sqp.clicks', 'Sqp.orders', 'Sqp.cartAdds',
      'Sqp.amazonImpressions', 'Sqp.amazonClicks', 'Sqp.amazonOrders',
      'Sqp.adsImpressions', 'Sqp.adsClicks', 'Sqp.adsOrders',
    ],
    dimensions: ['Sqp.reportingDate', 'Sqp.asin', 'Sqp.searchQuery', 'Sqp.showRatePct', 'Sqp.estimatedOrganicRank', 'Sqp.organicRankZone', 'Sqp.searchQueryScore', 'Product.productShortName', 'Product.productType'],
    timeDimensions: [{ dimension: 'Sqp.reportingDate', dateRange: 'Last 56 weeks' }],
    limit: 50000,
  });
  return (rows as Record<string, unknown>[]).map(r => {
    const rd = r['Sqp.reportingDate'];
    const weekStart = rd ? addDays(fmtDate(rd), -6) : '';
    return {
      product_type: String(r['Product.productType'] ?? ''),
      asin: String(r['Sqp.asin'] ?? ''),
      product_short_name: String(r['Product.productShortName'] ?? ''),
      week_start: weekStart,
      search_term: String(r['Sqp.searchQuery'] ?? ''),
      impressions: Number(r['Sqp.impressions'] ?? 0),
      clicks: Number(r['Sqp.clicks'] ?? 0),
      cart_adds: Number(r['Sqp.cartAdds'] ?? 0),
      orders: Number(r['Sqp.orders'] ?? 0),
      amazon_impressions: Number(r['Sqp.amazonImpressions'] ?? 0),
      amazon_clicks: Number(r['Sqp.amazonClicks'] ?? 0),
      amazon_orders: Number(r['Sqp.amazonOrders'] ?? 0),
      ads_impressions: Number(r['Sqp.adsImpressions'] ?? 0),
      ads_clicks: Number(r['Sqp.adsClicks'] ?? 0),
      ads_orders: Number(r['Sqp.adsOrders'] ?? 0),
      show_rate_pct: Number(r['Sqp.showRatePct'] ?? 0),
      estimated_organic_rank: Number(r['Sqp.estimatedOrganicRank'] ?? 0),
      organic_rank_zone: String(r['Sqp.organicRankZone'] ?? ''),
      search_query_score: Number(r['Sqp.searchQueryScore'] ?? 0),
    };
  });
}

/** Sqp → sqp_coverage_weeks (lightweight query for hasSqp indicator) */
async function loadSqpCoverageWeeksFromCube(): Promise<{ week_start: string }[]> {
  const rows = await cubeLoad({
    dimensions: ['Sqp.reportingDate'],
    timeDimensions: [{ dimension: 'Sqp.reportingDate', dateRange: 'Last 56 weeks' }],
    limit: 500, // max 100 weeks typically
  });
  return (rows as Record<string, unknown>[]).map(r => {
    const rd = r['Sqp.reportingDate'];
    return { week_start: rd ? addDays(fmtDate(rd), -6) : '' };
  });
}

/** ChangeLog → change_log */
async function loadChangeLogFromCube(): Promise<ChangeLogRow[]> {
  const rows = await cubeLoad({
    dimensions: ['ChangeLog.experimentId', 'ChangeLog.changeDate', 'ChangeLog.changeType', 'ChangeLog.fieldChanged', 'ChangeLog.oldValue', 'ChangeLog.newValue', 'ChangeLog.reason', 'ChangeLog.createdAt'],
    limit: 200,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    change_date: fmtDate(r['ChangeLog.changeDate'] ?? r['ChangeLog.createdAt']),
    created_at: fmtDate(r['ChangeLog.createdAt']),
    experiment_id: String(r['ChangeLog.experimentId'] ?? ''),
    change_type: String(r['ChangeLog.changeType'] ?? ''),
    field_changed: String(r['ChangeLog.fieldChanged'] ?? ''),
    old_value: String(r['ChangeLog.oldValue'] ?? ''),
    new_value: String(r['ChangeLog.newValue'] ?? ''),
    reason: String(r['ChangeLog.reason'] ?? ''),
  }));
}

/** Holidays → upcoming (with computed status) */
async function loadUpcomingFromCube(): Promise<UpcomingEvent[]> {
  const rows = await cubeLoad({
    dimensions: ['Holidays.holidayDate', 'Holidays.holidayName', 'Holidays.category', 'Holidays.preSeasonStart'],
    limit: 50,
  });
  const today = new Date().toISOString().slice(0, 10);
  return (rows as Record<string, unknown>[])
    .filter(r => {
      const hd = fmtDate(r['Holidays.holidayDate']);
      return hd >= today && hd <= addDays(today, 120);
    })
    .map(r => {
      const holidayDate = fmtDate(r['Holidays.holidayDate']);
      const preSeasonStart = fmtDate(r['Holidays.preSeasonStart']);
      const status = dateBetween(today, preSeasonStart, holidayDate);
      return {
        holiday_name: String(r['Holidays.holidayName'] ?? ''),
        holiday_date: holidayDate,
        status,
        days_until_holiday: daysBetween(today, holidayDate),
        category: String(r['Holidays.category'] ?? ''),
        pre_season_start: preSeasonStart,
        days_until_pre_season: daysBetween(today, preSeasonStart),
      };
    });
}

/** Holidays → peak (next gift_season) */
async function loadPeakFromCube(): Promise<PeakRow[]> {
  const rows = await cubeLoad({
    dimensions: ['Holidays.holidayDate', 'Holidays.holidayName', 'Holidays.category', 'Holidays.preSeasonStart'],
    limit: 50,
  });
  const today = new Date().toISOString().slice(0, 10);
  const next = (rows as Record<string, unknown>[])
    .filter(r => fmtDate(r['Holidays.holidayDate']) > today && String(r['Holidays.category'] ?? '') === 'gift_season')
    .sort((a, b) => fmtDate(a['Holidays.holidayDate'] as string).localeCompare(fmtDate(b['Holidays.holidayDate'] as string)))[0];
  if (!next) return [];
  const holidayDate = fmtDate(next['Holidays.holidayDate']);
  const preSeasonStart = fmtDate(next['Holidays.preSeasonStart']);
  const peakStart = preSeasonStart;
  const peakEnd = addDays(holidayDate, -2);
  const readinessStart = addDays(preSeasonStart, -120);
  const prePeakStart = addDays(preSeasonStart, -28);
  const boostStart = addDays(preSeasonStart, -14);
  let currentStage = 'READINESS';
  if (today >= peakEnd) currentStage = 'POST_PEAK';
  else if (today >= preSeasonStart) currentStage = 'PEAK';
  else if (today >= boostStart) currentStage = 'PRE_PEAK_BOOST';
  else if (today >= prePeakStart) currentStage = 'PRE_PEAK';
  return [{
    holiday_name: String(next['Holidays.holidayName'] ?? ''),
    holiday_date: holidayDate,
    peak_start: peakStart,
    peak_end: peakEnd,
    readiness_start: readinessStart,
    pre_peak_start: prePeakStart,
    boost_start: boostStart,
    current_stage: currentStage,
    days_until_peak_start: daysBetween(today, peakStart),
  }];
}

/** All holidays (past + future) for YoY phase comparison */
async function loadAllHolidaysFromCube(): Promise<HolidayRow[]> {
  const rows = await cubeLoad({
    dimensions: ['Holidays.holidayDate', 'Holidays.holidayName', 'Holidays.category', 'Holidays.preSeasonStart', 'Holidays.rampUpDays'],
    limit: 200,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    holiday_name: String(r['Holidays.holidayName'] ?? ''),
    holiday_date: fmtDate(r['Holidays.holidayDate']),
    pre_season_start: fmtDate(r['Holidays.preSeasonStart']),
    category: String(r['Holidays.category'] ?? ''),
    ramp_up_days: r['Holidays.rampUpDays'] != null ? Number(r['Holidays.rampUpDays']) : undefined,
  })).filter(r => r.holiday_date && r.holiday_name);
}

/** ExperimentDaily + Experiment → experiment_weekly */
async function loadExperimentWeeklyFromCube(): Promise<ExperimentWeeklyRow[]> {
  const rows = await cubeLoad({
    measures: [
      'ExperimentDaily.performanceTotalOrders', 'ExperimentDaily.performanceOrganicUnits',
      'ExperimentDaily.adsAllOrders', 'ExperimentDaily.adsAllCost', 'ExperimentDaily.performanceTotalSales',
      'ExperimentDaily.performanceSessions',
    ],
    dimensions: ['ExperimentDaily.experimentId', 'ExperimentDaily.snapshotDate', 'Experiment.experimentName', 'Experiment.strategyId'],
    timeDimensions: [{ dimension: 'ExperimentDaily.snapshotDate', dateRange: 'Last 12 weeks' }],
    limit: 5000,
  });
  const byWeek = new Map<string, { sales: number; ads_spend: number; total_orders: number; ads_orders: number; organic_units: number; sessions: number; experiment_name: string; strategy_id: string }>();
  for (const r of rows as Record<string, unknown>[]) {
    const sd = r['ExperimentDaily.snapshotDate'];
    const weekStart = sd ? getWeekStart(fmtDate(sd)) : '';
    const key = `${r['ExperimentDaily.experimentId']}|${weekStart}`;
    let cur = byWeek.get(key);
    if (!cur) {
      cur = { sales: 0, ads_spend: 0, total_orders: 0, ads_orders: 0, organic_units: 0, sessions: 0, experiment_name: String(r['Experiment.experimentName'] ?? ''), strategy_id: String(r['Experiment.strategyId'] ?? '') };
      byWeek.set(key, cur);
    }
    cur.sales += Number(r['ExperimentDaily.performanceTotalSales'] ?? 0);
    cur.ads_spend += Number(r['ExperimentDaily.adsAllCost'] ?? 0);
    cur.total_orders += Number(r['ExperimentDaily.performanceTotalOrders'] ?? 0);
    cur.ads_orders += Number(r['ExperimentDaily.adsAllOrders'] ?? 0);
    cur.organic_units += Number(r['ExperimentDaily.performanceOrganicUnits'] ?? 0);
    cur.sessions += Number(r['ExperimentDaily.performanceSessions'] ?? 0);
  }
  return Array.from(byWeek.entries())
    .filter(([, m]) => m.total_orders > 0 || m.ads_spend > 0)
    .map(([key, m]) => {
      const [experimentId, weekStart] = key.split('|');
      const convRate = m.sessions ? (m.ads_orders * 100) / m.sessions : 0;
      const netRoas = m.ads_spend ? (m.sales - m.ads_spend) / m.ads_spend : 0;
      const organicPct = m.total_orders ? (m.organic_units * 100) / m.total_orders : 0;
      return {
        experiment_id: experimentId,
        experiment_name: m.experiment_name,
        strategy_id: m.strategy_id,
        week_start: weekStart,
        sales: m.sales,
        ads_spend: m.ads_spend,
        total_orders: m.total_orders,
        ads_orders: m.ads_orders,
        organic_units: m.organic_units,
        sessions: m.sessions,
        conv_rate: convRate,
        net_roas: netRoas,
        organic_pct: organicPct,
      };
    });
}

/** DimProductCreatives → product_creatives */
async function loadProductCreativesFromCube(): Promise<ProductCreativeRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'DimProductCreatives.productFamily',
      'DimProductCreatives.brandEntityId',
      'DimProductCreatives.brandName',
      'DimProductCreatives.videoAssetId',
    ],
    limit: 50,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    product_family: String(r['DimProductCreatives.productFamily'] ?? ''),
    brand_entity_id: String(r['DimProductCreatives.brandEntityId'] ?? ''),
    brand_name: String(r['DimProductCreatives.brandName'] ?? ''),
    video_asset_id: String(r['DimProductCreatives.videoAssetId'] ?? ''),
  }));
}

/** Product + CostsHistory → products */
async function loadProductsFromCube(): Promise<ProductRow[]> {
  const [productRows, costRows] = await Promise.all([
    cubeLoad({ dimensions: ['Product.asin', 'Product.productShortName', 'Product.productType'], limit: 5000 }),
    cubeLoad({ dimensions: ['CostsHistory.asin', 'CostsHistory.costOfGoods', 'CostsHistory.shippingCost', 'CostsHistory.fbaCost', 'CostsHistory.totalCostPerUnit', 'CostsHistory.pickPackFee', 'CostsHistory.referralFee'], limit: 5000 }),
  ]);
  const costByAsin = new Map<string, { cogs: number; shipping: number; fba: number; total: number; pickPack: number; referral: number }>();
  for (const r of costRows as Record<string, unknown>[]) {
    const asin = String(r['CostsHistory.asin'] ?? '');
    costByAsin.set(asin, {
      cogs: Number(r['CostsHistory.costOfGoods'] ?? 0),
      shipping: Number(r['CostsHistory.shippingCost'] ?? 0),
      fba: Number(r['CostsHistory.fbaCost'] ?? 0),
      total: Number(r['CostsHistory.totalCostPerUnit'] ?? 0),
      pickPack: Number(r['CostsHistory.pickPackFee'] ?? 0),
      referral: Number(r['CostsHistory.referralFee'] ?? 0),
    });
  }
  return (productRows as Record<string, unknown>[]).map(r => {
    const asin = String(r['Product.asin'] ?? '');
    const costs = costByAsin.get(asin);
    return {
      asin,
      product_short_name: String(r['Product.productShortName'] ?? ''),
      product_type: String(r['Product.productType'] ?? ''),
      cogs: costs?.cogs ?? 0,
      shipping_cost: costs?.shipping ?? 0,
      fba_cost: costs?.fba ?? 0,
      total_cost_per_unit: costs?.total ?? 0,
      pick_pack_fee: costs?.pickPack ?? 0,
      referral_fee: costs?.referral ?? 0,
    };
  });
}

/** DataFreshness → data_freshness (ads_max_date, performance_max_date) */
async function loadDataFreshnessFromCube(): Promise<{ ads_max_date?: string; performance_max_date?: string }> {
  const rows = await cubeLoad({
    dimensions: ['DataFreshness.source', 'DataFreshness.maxDate'],
    limit: 10,
  });
  const out: { ads_max_date?: string; performance_max_date?: string } = {};
  for (const r of rows as Record<string, unknown>[]) {
    const src = String(r['DataFreshness.source'] ?? '');
    const md = r['DataFreshness.maxDate'];
    const iso = md ? String(md).slice(0, 10) : '';
    if (src === 'ads' && iso) out.ads_max_date = iso;
    if (src === 'perf' && iso) out.performance_max_date = iso;
  }
  return out;
}

/** Fetch Cube response metadata (lastRefreshTime, usedPreAggregations) for refresh label */
async function loadCubeMeta(): Promise<{ refreshed_at?: string; cube_source: 'preagg' | 'live' }> {
  const q = { measures: ['UnifiedPerformance.count'], limit: 1 };
  const { lastRefreshTime, usedPreAggregations } = await cubeLoadWithMeta(q);
  const hasPreAgg = usedPreAggregations && Object.keys(usedPreAggregations).length > 0;
  return {
    refreshed_at: hasPreAgg && lastRefreshTime ? lastRefreshTime : undefined,
    cube_source: hasPreAgg ? 'preagg' : 'live',
  };
}

/** Summary → summary */
async function loadSummaryFromCube(): Promise<SummaryRow[]> {
  const { data: rows } = await cubeLoadWithMeta({
    dimensions: [
      'Summary.productType', 'Summary.sales7d', 'Summary.adCost7d', 'Summary.cogs7d', 'Summary.netProfit7d',
      'Summary.orders7d', 'Summary.organicUnits7d', 'Summary.adOrders7d', 'Summary.clicks7d', 'Summary.sessions7d',
      'Summary.netRoas', 'Summary.organicPct', 'Summary.salesPrev7d', 'Summary.adCostPrev7d', 'Summary.cogsPrev7d',
      'Summary.netProfitPrev7d', 'Summary.ordersPrev7d', 'Summary.organicUnitsPrev7d',
      'Summary.netRoasPrev', 'Summary.organicPctPrev', 'Summary.salesChangePct', 'Summary.costChangePct',
      'Summary.periodStart', 'Summary.periodEnd', 'Summary.units7d',
    ],
    limit: 20,
  });
  const arr = Array.isArray(rows) ? rows : [];
  if (import.meta.env.DEV) {
    console.log('[useCubeData] Summary from Cube:', arr.length, 'rows', arr.length ? arr : '(empty - check Cube/Summary schema)');
  }
  return (arr as Record<string, unknown>[]).map(r => ({
    product_type: String(r['Summary.productType'] ?? ''),
    sales_7d: Number(r['Summary.sales7d'] ?? 0),
    ad_cost_7d: Number(r['Summary.adCost7d'] ?? 0),
    cogs_7d: Number(r['Summary.cogs7d'] ?? 0),
    net_profit_7d: Number(r['Summary.netProfit7d'] ?? 0),
    orders_7d: Number(r['Summary.orders7d'] ?? 0),
    organic_units_7d: Number(r['Summary.organicUnits7d'] ?? 0),
    ad_orders_7d: Number(r['Summary.adOrders7d'] ?? 0),
    clicks_7d: Number(r['Summary.clicks7d'] ?? 0),
    sessions_7d: Number(r['Summary.sessions7d'] ?? 0),
    organic_pct: Number(r['Summary.organicPct'] ?? 0),
    net_roas: Number(r['Summary.netRoas'] ?? 0),
    sales_prev_7d: Number(r['Summary.salesPrev7d'] ?? 0),
    ad_cost_prev_7d: Number(r['Summary.adCostPrev7d'] ?? 0),
    cogs_prev_7d: Number(r['Summary.cogsPrev7d'] ?? 0),
    net_profit_prev_7d: Number(r['Summary.netProfitPrev7d'] ?? 0),
    orders_prev_7d: Number(r['Summary.ordersPrev7d'] ?? 0),
    organic_units_prev_7d: Number(r['Summary.organicUnitsPrev7d'] ?? 0),
    units_7d: Number(r['Summary.units7d'] ?? 0),
    net_roas_prev: Number(r['Summary.netRoasPrev'] ?? 0),
    organic_pct_prev: Number(r['Summary.organicPctPrev'] ?? 0),
    sales_change_pct: Number(r['Summary.salesChangePct'] ?? 0),
    cost_change_pct: Number(r['Summary.costChangePct'] ?? 0),
    period_start: String(r['Summary.periodStart'] ?? ''),
    period_end: String(r['Summary.periodEnd'] ?? ''),
  }));
}

/** ExperimentTermRecommendations → actions (includes KEEP; excludes MONITOR for performance) */
async function loadActionsFromCube(): Promise<ActionRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'ExperimentTermRecommendations.action', 'ExperimentTermRecommendations.adsSignal', 'ExperimentTermRecommendations.reason',
      'ExperimentTermRecommendations.searchTerm', 'ExperimentTermRecommendations.experimentId',
      'ExperimentTermRecommendations.productShortName', 'ExperimentTermRecommendations.heroAsin', 'ExperimentTermRecommendations.isHeroMatch',
      'ExperimentTermRecommendations.adsSpend', 'ExperimentTermRecommendations.adsOrders', 'ExperimentTermRecommendations.adsClicks', 'ExperimentTermRecommendations.adsClicksRecent',
      'ExperimentTermRecommendations.cpc', 'ExperimentTermRecommendations.adsCvrPct', 'ExperimentTermRecommendations.marginPerUnit',
      'ExperimentTermRecommendations.marketWeeklyOrders', 'ExperimentTermRecommendations.yourOrdersSharePct',
      'ExperimentTermRecommendations.priorityScore', 'ExperimentTermRecommendations.strategyId', 'ExperimentTermRecommendations.adsNetRoas',
      'ExperimentTermRecommendations.weightedTotalNetRoas',
      'ExperimentTermRecommendations.campaignId', 'ExperimentTermRecommendations.campaignName',
      'ExperimentTermRecommendations.campaignType',
      'ExperimentTermRecommendations.adGroupId', 'ExperimentTermRecommendations.portfolioName',
      'ExperimentTermRecommendations.heroAction', 'ExperimentTermRecommendations.heroActionExplanation',
      'ExperimentTermRecommendations.negateAs', 'ExperimentTermRecommendations.actionExplanation',
      'ExperimentTermRecommendations.heroProductName', 'ExperimentTermRecommendations.heroNetRoas',
      'ExperimentTermRecommendations.heroTotalOrders', 'ExperimentTermRecommendations.heroAdsCtrPct',
      'ExperimentTermRecommendations.sqpSearchVolume',
      'ExperimentTermRecommendations.sqpOrganicRank', 'ExperimentTermRecommendations.isTopOfPageOrganic',
      'ExperimentTermRecommendations.decisionTrace',
    ],
    limit: 10000,
  });

  return (rows as Record<string, unknown>[]).map(r => ({
    search_term: String(r['ExperimentTermRecommendations.searchTerm'] ?? ''),
    product_short_name: String(r['ExperimentTermRecommendations.productShortName'] ?? ''),
    asin: String(r['ExperimentTermRecommendations.asin'] ?? ''),
    experiment_id: String(r['ExperimentTermRecommendations.experimentId'] ?? ''),
    strategy_id: String(r['ExperimentTermRecommendations.strategyId'] ?? ''),
    campaign_id: String(r['ExperimentTermRecommendations.campaignId'] ?? ''),
    ad_group_id: String(r['ExperimentTermRecommendations.adGroupId'] ?? ''),
    campaign_name: String(r['ExperimentTermRecommendations.campaignName'] ?? ''),
    campaign_type: String(r['ExperimentTermRecommendations.campaignType'] ?? 'SP'),
    portfolio_name: String(r['ExperimentTermRecommendations.portfolioName'] ?? 'Unassigned'),
    hero_asin: String(r['ExperimentTermRecommendations.heroAsin'] ?? ''),
    is_hero_match: Boolean(r['ExperimentTermRecommendations.isHeroMatch']),
    action: String(r['ExperimentTermRecommendations.action'] ?? ''),
    reason: String(r['ExperimentTermRecommendations.reason'] ?? ''),
    priority_score: Number(r['ExperimentTermRecommendations.priorityScore'] ?? 0),
    ads_signal: String(r['ExperimentTermRecommendations.adsSignal'] ?? ''),
    spend: Number(r['ExperimentTermRecommendations.adsSpend'] ?? 0),
    orders: Number(r['ExperimentTermRecommendations.adsOrders'] ?? 0),
    clicks: Number(r['ExperimentTermRecommendations.adsClicks'] ?? 0),
    ads_clicks_recent: Number(r['ExperimentTermRecommendations.adsClicksRecent'] ?? 0),
    cpc: Number(r['ExperimentTermRecommendations.cpc'] ?? 0),
    conv_rate: Number(r['ExperimentTermRecommendations.adsCvrPct'] ?? 0),
    net_roas: Number(r['ExperimentTermRecommendations.adsNetRoas'] ?? 0),
    margin_per_unit: Number(r['ExperimentTermRecommendations.marginPerUnit'] ?? 0),
    market_volume: Number(r['ExperimentTermRecommendations.marketWeeklyOrders'] ?? 0),
    impression_share: Number(r['ExperimentTermRecommendations.yourOrdersSharePct'] ?? 0),
    // dual-grain: not available from ExperimentTermRecommendations
    targeting: null,
    keyword_id: null,
    target_action: null,
    effective_roas: null,
    weighted_total_net_roas: r['ExperimentTermRecommendations.weightedTotalNetRoas'] != null ? Number(r['ExperimentTermRecommendations.weightedTotalNetRoas']) : null,
    target_net_roas_8w: null,
    target_clicks_8w: null,
    target_orders_8w: null,
    target_spend_8w: null,
    current_bid: null,
    recommended_bid: null,
    match_type: null,
    // Hero & explanation columns
    hero_product_name: r['ExperimentTermRecommendations.heroProductName'] ? String(r['ExperimentTermRecommendations.heroProductName']) : null,
    hero_action: r['ExperimentTermRecommendations.heroAction'] ? String(r['ExperimentTermRecommendations.heroAction']) : null,
    hero_action_explanation: r['ExperimentTermRecommendations.heroActionExplanation'] ? String(r['ExperimentTermRecommendations.heroActionExplanation']) : null,
    hero_net_roas: r['ExperimentTermRecommendations.heroNetRoas'] != null ? Number(r['ExperimentTermRecommendations.heroNetRoas']) : null,
    hero_total_orders: r['ExperimentTermRecommendations.heroTotalOrders'] != null ? Number(r['ExperimentTermRecommendations.heroTotalOrders']) : null,
    hero_ads_ctr_pct: r['ExperimentTermRecommendations.heroAdsCtrPct'] != null ? Number(r['ExperimentTermRecommendations.heroAdsCtrPct']) : null,
    negate_as: r['ExperimentTermRecommendations.negateAs'] ? String(r['ExperimentTermRecommendations.negateAs']) : null,
    action_explanation: r['ExperimentTermRecommendations.actionExplanation'] ? String(r['ExperimentTermRecommendations.actionExplanation']) : null,
    weighted_total_net_roas_dim: r['ExperimentTermRecommendations.weightedTotalNetRoas'] != null ? Number(r['ExperimentTermRecommendations.weightedTotalNetRoas']) : null,
    sqp_search_volume: Number(r['ExperimentTermRecommendations.sqpSearchVolume'] ?? 0),
    sqp_organic_rank: r['ExperimentTermRecommendations.sqpOrganicRank'] != null ? Number(r['ExperimentTermRecommendations.sqpOrganicRank']) : null,
    is_top_of_page_organic: Boolean(r['ExperimentTermRecommendations.isTopOfPageOrganic']),
    decision_trace: (() => { try { const raw = r['ExperimentTermRecommendations.decisionTrace']; return raw ? JSON.parse(String(raw)) : null; } catch { return null; } })(),
  })).sort((a, b) => b.priority_score - a.priority_score);
}

/** CoachHotSignals → 3-day rapid-reaction ads alerts */
async function loadHotSignalsFromCube(): Promise<HotSignalRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'CoachHotSignals.hotSignal', 'CoachHotSignals.hotSignalReason',
      'CoachHotSignals.searchTerm', 'CoachHotSignals.asin',
      'CoachHotSignals.productShortName', 'CoachHotSignals.parentName',
      'CoachHotSignals.experimentId', 'CoachHotSignals.experimentName',
      'CoachHotSignals.strategyId', 'CoachHotSignals.strategyName',
      'CoachHotSignals.campaignId', 'CoachHotSignals.campaignName',
      'CoachHotSignals.campaignType', 'CoachHotSignals.adGroupId',
      'CoachHotSignals.spend3d', 'CoachHotSignals.orders3d',
      'CoachHotSignals.clicks3d', 'CoachHotSignals.impressions3d',
      'CoachHotSignals.cpc3d', 'CoachHotSignals.cvr3d',
      'CoachHotSignals.adsRoas3d', 'CoachHotSignals.netProfit3d',
      'CoachHotSignals.marginPerUnit',
      'CoachHotSignals.coach8wAction', 'CoachHotSignals.coach8wRoas',
      'CoachHotSignals.coach8wSignal',
      'CoachHotSignals.priorityScore', 'CoachHotSignals.daysWithData',
      'CoachHotSignals.sqpSearchVolume4w', 'CoachHotSignals.sqpOrganicRank',
    ],
    limit: 500,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    hot_signal: String(r['CoachHotSignals.hotSignal'] ?? '') as HotSignalRow['hot_signal'],
    hot_signal_reason: String(r['CoachHotSignals.hotSignalReason'] ?? ''),
    search_term: String(r['CoachHotSignals.searchTerm'] ?? ''),
    asin: String(r['CoachHotSignals.asin'] ?? ''),
    product_short_name: String(r['CoachHotSignals.productShortName'] ?? ''),
    parent_name: String(r['CoachHotSignals.parentName'] ?? ''),
    experiment_id: String(r['CoachHotSignals.experimentId'] ?? ''),
    experiment_name: String(r['CoachHotSignals.experimentName'] ?? ''),
    strategy_id: String(r['CoachHotSignals.strategyId'] ?? ''),
    strategy_name: String(r['CoachHotSignals.strategyName'] ?? ''),
    campaign_id: String(r['CoachHotSignals.campaignId'] ?? ''),
    campaign_name: String(r['CoachHotSignals.campaignName'] ?? ''),
    campaign_type: String(r['CoachHotSignals.campaignType'] ?? 'SP'),
    ad_group_id: String(r['CoachHotSignals.adGroupId'] ?? ''),
    spend_3d: Number(r['CoachHotSignals.spend3d'] ?? 0),
    orders_3d: Number(r['CoachHotSignals.orders3d'] ?? 0),
    clicks_3d: Number(r['CoachHotSignals.clicks3d'] ?? 0),
    impressions_3d: Number(r['CoachHotSignals.impressions3d'] ?? 0),
    cpc_3d: r['CoachHotSignals.cpc3d'] != null ? Number(r['CoachHotSignals.cpc3d']) : null,
    cvr_3d: r['CoachHotSignals.cvr3d'] != null ? Number(r['CoachHotSignals.cvr3d']) : null,
    ads_roas_3d: r['CoachHotSignals.adsRoas3d'] != null ? Number(r['CoachHotSignals.adsRoas3d']) : null,
    net_profit_3d: r['CoachHotSignals.netProfit3d'] != null ? Number(r['CoachHotSignals.netProfit3d']) : null,
    margin_per_unit: Number(r['CoachHotSignals.marginPerUnit'] ?? 0),
    coach_8w_action: r['CoachHotSignals.coach8wAction'] ? String(r['CoachHotSignals.coach8wAction']) : null,
    coach_8w_roas: r['CoachHotSignals.coach8wRoas'] != null ? Number(r['CoachHotSignals.coach8wRoas']) : null,
    coach_8w_signal: r['CoachHotSignals.coach8wSignal'] ? String(r['CoachHotSignals.coach8wSignal']) : null,
    priority_score: Number(r['CoachHotSignals.priorityScore'] ?? 0),
    sqp_search_volume_4w: Number(r['CoachHotSignals.sqpSearchVolume4w'] ?? 0),
    sqp_organic_rank: r['CoachHotSignals.sqpOrganicRank'] != null ? Number(r['CoachHotSignals.sqpOrganicRank']) : null,
    days_with_data: Number(r['CoachHotSignals.daysWithData'] ?? 0),
  })).sort((a, b) => b.priority_score - a.priority_score);
}

/** WeeklyTrends → weekly_trends (via UnifiedPerformance) */
async function loadWeeklyTrendsFromCube(): Promise<TrendRow[]> {
  const rows = await cubeLoad({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.adCost', 'UnifiedPerformance.cogs', 'UnifiedPerformance.netProfit', 'UnifiedPerformance.orders', 'UnifiedPerformance.units', 'UnifiedPerformance.clicks', 'UnifiedPerformance.sessions', 'UnifiedPerformance.netRoas', 'UnifiedPerformance.organicPct', 'UnifiedPerformance.tacos', 'UnifiedPerformance.npPerUnit'],
    dimensions: ['UnifiedPerformance.family', 'UnifiedPerformance.weekStart'],
    limit: 5000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    product_type: String(r['UnifiedPerformance.family'] ?? ''),
    week_start: fmtDate(r['UnifiedPerformance.weekStart']),
    sales: Number(r['UnifiedPerformance.sales'] ?? 0),
    ad_cost: Number(r['UnifiedPerformance.adCost'] ?? 0),
    cogs: Number(r['UnifiedPerformance.cogs'] ?? 0),
    net_profit: Number(r['UnifiedPerformance.netProfit'] ?? 0),
    orders: Number(r['UnifiedPerformance.orders'] ?? 0),
    units: Number(r['UnifiedPerformance.units'] ?? 0),
    clicks: Number(r['UnifiedPerformance.clicks'] ?? 0),
    sessions: Number(r['UnifiedPerformance.sessions'] ?? 0),
    net_roas: Number(r['UnifiedPerformance.netRoas'] ?? 0),
    organic_pct: Number(r['UnifiedPerformance.organicPct'] ?? 0),
    tacos: Number(r['UnifiedPerformance.tacos'] ?? 0),
    np_per_unit: Number(r['UnifiedPerformance.npPerUnit'] ?? 0),
  }));
}

/** MonthlyTrends → monthly_trends (via UnifiedPerformance) */
async function loadMonthlyTrendsFromCube(): Promise<TrendRow[]> {
  const rows = await cubeLoad({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.adCost', 'UnifiedPerformance.cogs', 'UnifiedPerformance.netProfit', 'UnifiedPerformance.orders', 'UnifiedPerformance.units', 'UnifiedPerformance.clicks', 'UnifiedPerformance.sessions', 'UnifiedPerformance.netRoas', 'UnifiedPerformance.organicPct', 'UnifiedPerformance.tacos', 'UnifiedPerformance.npPerUnit'],
    dimensions: ['UnifiedPerformance.family', 'UnifiedPerformance.monthStart'],
    limit: 5000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    product_type: String(r['UnifiedPerformance.family'] ?? ''),
    month_start: fmtDate(r['UnifiedPerformance.monthStart']),
    sales: Number(r['UnifiedPerformance.sales'] ?? 0),
    ad_cost: Number(r['UnifiedPerformance.adCost'] ?? 0),
    cogs: Number(r['UnifiedPerformance.cogs'] ?? 0),
    net_profit: Number(r['UnifiedPerformance.netProfit'] ?? 0),
    orders: Number(r['UnifiedPerformance.orders'] ?? 0),
    units: Number(r['UnifiedPerformance.units'] ?? 0),
    clicks: Number(r['UnifiedPerformance.clicks'] ?? 0),
    sessions: Number(r['UnifiedPerformance.sessions'] ?? 0),
    net_roas: Number(r['UnifiedPerformance.netRoas'] ?? 0),
    organic_pct: Number(r['UnifiedPerformance.organicPct'] ?? 0),
    tacos: Number(r['UnifiedPerformance.tacos'] ?? 0),
    np_per_unit: Number(r['UnifiedPerformance.npPerUnit'] ?? 0),
  }));
}

/** WeeklyTrendsByAsin → weekly_trends_by_asin (via UnifiedPerformance) */
async function loadWeeklyTrendsByAsinFromCube(): Promise<TrendRowByAsin[]> {
  const rows = await cubeLoad({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.adCost', 'UnifiedPerformance.cogs', 'UnifiedPerformance.netProfit', 'UnifiedPerformance.orders', 'UnifiedPerformance.units', 'UnifiedPerformance.clicks', 'UnifiedPerformance.sessions', 'UnifiedPerformance.netRoas', 'UnifiedPerformance.organicPct', 'UnifiedPerformance.tacos', 'UnifiedPerformance.npPerUnit'],
    dimensions: ['UnifiedPerformance.family', 'UnifiedPerformance.asin', 'UnifiedPerformance.productShortName', 'UnifiedPerformance.weekStart'],
    limit: 5000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    product_type: String(r['UnifiedPerformance.family'] ?? ''),
    asin: String(r['UnifiedPerformance.asin'] ?? ''),
    product_short_name: String(r['UnifiedPerformance.productShortName'] ?? ''),
    week_start: fmtDate(r['UnifiedPerformance.weekStart']),
    sales: Number(r['UnifiedPerformance.sales'] ?? 0),
    ad_cost: Number(r['UnifiedPerformance.adCost'] ?? 0),
    cogs: Number(r['UnifiedPerformance.cogs'] ?? 0),
    net_profit: Number(r['UnifiedPerformance.netProfit'] ?? 0),
    orders: Number(r['UnifiedPerformance.orders'] ?? 0),
    units: Number(r['UnifiedPerformance.units'] ?? 0),
    clicks: Number(r['UnifiedPerformance.clicks'] ?? 0),
    sessions: Number(r['UnifiedPerformance.sessions'] ?? 0),
    net_roas: Number(r['UnifiedPerformance.netRoas'] ?? 0),
    organic_pct: Number(r['UnifiedPerformance.organicPct'] ?? 0),
    tacos: Number(r['UnifiedPerformance.tacos'] ?? 0),
    np_per_unit: Number(r['UnifiedPerformance.npPerUnit'] ?? 0),
  }));
}

/** MonthlyTrendsByAsin → monthly_trends_by_asin (via UnifiedPerformance) */
async function loadMonthlyTrendsByAsinFromCube(): Promise<TrendRowByAsin[]> {
  const rows = await cubeLoad({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.adCost', 'UnifiedPerformance.cogs', 'UnifiedPerformance.netProfit', 'UnifiedPerformance.orders', 'UnifiedPerformance.units', 'UnifiedPerformance.clicks', 'UnifiedPerformance.sessions', 'UnifiedPerformance.netRoas', 'UnifiedPerformance.organicPct', 'UnifiedPerformance.tacos', 'UnifiedPerformance.npPerUnit'],
    dimensions: ['UnifiedPerformance.family', 'UnifiedPerformance.asin', 'UnifiedPerformance.productShortName', 'UnifiedPerformance.monthStart'],
    limit: 5000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    product_type: String(r['UnifiedPerformance.family'] ?? ''),
    asin: String(r['UnifiedPerformance.asin'] ?? ''),
    product_short_name: String(r['UnifiedPerformance.productShortName'] ?? ''),
    month_start: fmtDate(r['UnifiedPerformance.monthStart']),
    sales: Number(r['UnifiedPerformance.sales'] ?? 0),
    ad_cost: Number(r['UnifiedPerformance.adCost'] ?? 0),
    cogs: Number(r['UnifiedPerformance.cogs'] ?? 0),
    net_profit: Number(r['UnifiedPerformance.netProfit'] ?? 0),
    orders: Number(r['UnifiedPerformance.orders'] ?? 0),
    units: Number(r['UnifiedPerformance.units'] ?? 0),
    clicks: Number(r['UnifiedPerformance.clicks'] ?? 0),
    sessions: Number(r['UnifiedPerformance.sessions'] ?? 0),
    net_roas: Number(r['UnifiedPerformance.netRoas'] ?? 0),
    organic_pct: Number(r['UnifiedPerformance.organicPct'] ?? 0),
    tacos: Number(r['UnifiedPerformance.tacos'] ?? 0),
    np_per_unit: Number(r['UnifiedPerformance.npPerUnit'] ?? 0),
  }));
}

/** ExperimentLearnings → learnings */
async function loadLearningsFromCube(): Promise<LearningRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'ExperimentLearnings.rowKey', 'ExperimentLearnings.learningDimension', 'ExperimentLearnings.dimensionValue',
      'ExperimentLearnings.avgOrganicLiftPct', 'ExperimentLearnings.avgTotalLiftPct', 'ExperimentLearnings.avgRoas',
      'ExperimentLearnings.avgAdSpend', 'ExperimentLearnings.avgDaysRunning', 'ExperimentLearnings.successfulCount', 'ExperimentLearnings.unsuccessfulCount',
    ],
    measures: ['ExperimentLearnings.experimentCount'],
    limit: 200,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    learning_dimension: String(r['ExperimentLearnings.learningDimension'] ?? ''),
    dimension_value: String(r['ExperimentLearnings.dimensionValue'] ?? ''),
    experiment_count: Number(r['ExperimentLearnings.experimentCount'] ?? 0),
    avg_organic_lift_pct: r['ExperimentLearnings.avgOrganicLiftPct'] != null ? Number(r['ExperimentLearnings.avgOrganicLiftPct']) : undefined,
    avg_total_lift_pct: r['ExperimentLearnings.avgTotalLiftPct'] != null ? Number(r['ExperimentLearnings.avgTotalLiftPct']) : undefined,
    avg_roas: r['ExperimentLearnings.avgRoas'] != null ? Number(r['ExperimentLearnings.avgRoas']) : undefined,
    avg_ad_spend: r['ExperimentLearnings.avgAdSpend'] != null ? Number(r['ExperimentLearnings.avgAdSpend']) : undefined,
    avg_days_running: r['ExperimentLearnings.avgDaysRunning'] != null ? Number(r['ExperimentLearnings.avgDaysRunning']) : undefined,
    successful_count: r['ExperimentLearnings.successfulCount'] != null ? Number(r['ExperimentLearnings.successfulCount']) : undefined,
    unsuccessful_count: r['ExperimentLearnings.unsuccessfulCount'] != null ? Number(r['ExperimentLearnings.unsuccessfulCount']) : undefined,
  } as LearningRow));
}

/** Experiment → experiments */
async function loadExperimentsFromCube(): Promise<ExperimentRow[]> {
  const rows = await cubeLoad({
    dimensions: ['Experiment.experimentId', 'Experiment.experimentName', 'Experiment.strategyId', 'Experiment.status', 'Experiment.startDate', 'Experiment.endDate'],
    limit: 100,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    experiment_id: String(r['Experiment.experimentId'] ?? ''),
    experiment_name: String(r['Experiment.experimentName'] ?? ''),
    strategy_id: String(r['Experiment.strategyId'] ?? ''),
    status: String(r['Experiment.status'] ?? ''),
    start_date: fmtDate(r['Experiment.startDate']),
    end_date: fmtDate(r['Experiment.endDate']),
  } as ExperimentRow));
}

/** ExperimentBudgetHealth → budget_health */
async function loadBudgetHealthFromCube(): Promise<BudgetHealthRow[]> {
  const rows = await cubeLoad({
    dimensions: ['ExperimentBudgetHealth.experimentId', 'ExperimentBudgetHealth.budgetUtilizationPct', 'ExperimentBudgetHealth.adsRoasTrend', 'ExperimentBudgetHealth.dataStatus'],
    limit: 100,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    experiment_id: String(r['ExperimentBudgetHealth.experimentId'] ?? ''),
    budget_utilization_pct: Number(r['ExperimentBudgetHealth.budgetUtilizationPct'] ?? 0),
    action_signal: r['ExperimentBudgetHealth.adsRoasTrend'] ? String(r['ExperimentBudgetHealth.adsRoasTrend']) : undefined,
  }));
}

/** ExperimentTermRecommendations → drivers */
async function loadDriversFromCube(): Promise<DriverRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'ExperimentTermRecommendations.searchTerm', 'ExperimentTermRecommendations.productShortName', 'ExperimentTermRecommendations.experimentId',
      'ExperimentTermRecommendations.action', 'ExperimentTermRecommendations.adsSpend', 'ExperimentTermRecommendations.adsOrders',
      'ExperimentTermRecommendations.adsClicks', 'ExperimentTermRecommendations.cpc', 'ExperimentTermRecommendations.adsCvrPct',
      'ExperimentTermRecommendations.marginPerUnit', 'ExperimentTermRecommendations.yourOrdersSharePct', 'ExperimentTermRecommendations.adsNetRoas',
    ],
    limit: 2000,
  });
  return (rows as Record<string, unknown>[]).map(r => {
    const pn = String(r['ExperimentTermRecommendations.productShortName'] ?? '');
    let product_type = pn;
    if (pn.includes('Lollibox')) product_type = 'Lollibox';
    else if (pn.includes('LolliME')) product_type = 'LolliME';
    else if (pn.includes('Fresh')) product_type = 'Fresh';
    else if (pn.includes('Truth') || pn.includes('Bottle')) product_type = 'Bottle';
    return {
      search_term: String(r['ExperimentTermRecommendations.searchTerm'] ?? ''),
      product_short_name: pn,
      product_type,
      experiment_id: r['ExperimentTermRecommendations.experimentId'] ? String(r['ExperimentTermRecommendations.experimentId']) : undefined,
      spend: Number(r['ExperimentTermRecommendations.adsSpend'] ?? 0),
      orders: Number(r['ExperimentTermRecommendations.adsOrders'] ?? 0),
      clicks: Number(r['ExperimentTermRecommendations.adsClicks'] ?? 0),
      cpc: Number(r['ExperimentTermRecommendations.cpc'] ?? 0),
      conv_rate: Number(r['ExperimentTermRecommendations.adsCvrPct'] ?? 0),
      net_roas: Number(r['ExperimentTermRecommendations.adsNetRoas'] ?? 0),
      margin_per_unit: Number(r['ExperimentTermRecommendations.marginPerUnit'] ?? 0),
      impression_share: Number(r['ExperimentTermRecommendations.yourOrdersSharePct'] ?? 0),
      action: String(r['ExperimentTermRecommendations.action'] ?? ''),
    };
  });
}

/** ParentHeroAsin → hero_asins */
async function loadHeroAsinsFromCube(): Promise<HeroAsin[]> {
  const rows = await cubeLoad({
    dimensions: ['ParentHeroAsin.asin', 'ParentHeroAsin.searchTerm', 'ParentHeroAsin.parentName', 'ParentHeroAsin.productShortName', 'ParentHeroAsin.heroRank', 'ParentHeroAsin.heroScore', 'ParentHeroAsin.sqpCvrPct', 'ParentHeroAsin.sqpCtrPct', 'ParentHeroAsin.sqpImpressions', 'ParentHeroAsin.sqpClicks', 'ParentHeroAsin.sqpConversions', 'ParentHeroAsin.adsSpend', 'ParentHeroAsin.adsOrders', 'ParentHeroAsin.adsClicks', 'ParentHeroAsin.adsNetRoas', 'ParentHeroAsin.marginPerUnit', 'ParentHeroAsin.reason'],
    limit: 500,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    asin: String(r['ParentHeroAsin.asin'] ?? ''),
    search_term: r['ParentHeroAsin.searchTerm'] ? String(r['ParentHeroAsin.searchTerm']) : undefined,
    parent_name: r['ParentHeroAsin.parentName'] ? String(r['ParentHeroAsin.parentName']) : undefined,
    product_short_name: String(r['ParentHeroAsin.productShortName'] ?? ''),
    product_type: (() => {
      const pn = String(r['ParentHeroAsin.productShortName'] ?? '');
      if (pn.includes('Lollibox')) return 'Lollibox';
      if (pn.includes('LolliME')) return 'LolliME';
      if (pn.includes('Fresh')) return 'Fresh';
      if (pn.includes('Truth') || pn.includes('Bottle')) return 'Bottle';
      return pn;
    })(),
    hero_rank: r['ParentHeroAsin.heroRank'] != null ? Number(r['ParentHeroAsin.heroRank']) : undefined,
    sqp_cvr_pct: r['ParentHeroAsin.sqpCvrPct'] != null ? Number(r['ParentHeroAsin.sqpCvrPct']) : undefined,
    sqp_ctr_pct: r['ParentHeroAsin.sqpCtrPct'] != null ? Number(r['ParentHeroAsin.sqpCtrPct']) : undefined,
    sqp_impressions: r['ParentHeroAsin.sqpImpressions'] != null ? Number(r['ParentHeroAsin.sqpImpressions']) : undefined,
    sqp_clicks: r['ParentHeroAsin.sqpClicks'] != null ? Number(r['ParentHeroAsin.sqpClicks']) : undefined,
    sqp_conversions: r['ParentHeroAsin.sqpConversions'] != null ? Number(r['ParentHeroAsin.sqpConversions']) : undefined,
    ads_spend: r['ParentHeroAsin.adsSpend'] != null ? Number(r['ParentHeroAsin.adsSpend']) : undefined,
    ads_orders: r['ParentHeroAsin.adsOrders'] != null ? Number(r['ParentHeroAsin.adsOrders']) : undefined,
    ads_clicks: r['ParentHeroAsin.adsClicks'] != null ? Number(r['ParentHeroAsin.adsClicks']) : undefined,
    ads_net_roas: r['ParentHeroAsin.adsNetRoas'] != null ? Number(r['ParentHeroAsin.adsNetRoas']) : undefined,
    margin_per_unit: r['ParentHeroAsin.marginPerUnit'] != null ? Number(r['ParentHeroAsin.marginPerUnit']) : undefined,
    reason: r['ParentHeroAsin.reason'] ? String(r['ParentHeroAsin.reason']) : undefined,
  }));
}

/** ExperimentTermRecommendations → keyword_product_map */
async function loadKeywordProductMapFromCube(): Promise<KeywordMapRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'ExperimentTermRecommendations.searchTerm', 'ExperimentTermRecommendations.experimentId', 'ExperimentTermRecommendations.productShortName',
      'ExperimentTermRecommendations.heroAsin', 'ExperimentTermRecommendations.isHeroMatch', 'ExperimentTermRecommendations.action', 'ExperimentTermRecommendations.reason',
      'ExperimentTermRecommendations.adsSpend', 'ExperimentTermRecommendations.adsOrders', 'ExperimentTermRecommendations.adsClicks', 'ExperimentTermRecommendations.adsImpressions',
      'ExperimentTermRecommendations.cpc', 'ExperimentTermRecommendations.adsCvrPct', 'ExperimentTermRecommendations.adsNetRoas',
      'ExperimentTermRecommendations.marketWeeklyOrders', 'ExperimentTermRecommendations.yourOrdersSharePct',
    ],
    limit: 2000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    search_term: String(r['ExperimentTermRecommendations.searchTerm'] ?? ''),
    experiment_id: r['ExperimentTermRecommendations.experimentId'] ? String(r['ExperimentTermRecommendations.experimentId']) : undefined,
    product_short_name: String(r['ExperimentTermRecommendations.productShortName'] ?? ''),
    hero_asin: String(r['ExperimentTermRecommendations.heroAsin'] ?? ''),
    is_hero_match: Boolean(r['ExperimentTermRecommendations.isHeroMatch']),
    action: String(r['ExperimentTermRecommendations.action'] ?? ''),
    reason: r['ExperimentTermRecommendations.reason'] ? String(r['ExperimentTermRecommendations.reason']) : undefined,
    spend_60d: Number(r['ExperimentTermRecommendations.adsSpend'] ?? 0),
    orders_60d: Number(r['ExperimentTermRecommendations.adsOrders'] ?? 0),
    clicks_60d: Number(r['ExperimentTermRecommendations.adsClicks'] ?? 0),
    impressions_60d: Number(r['ExperimentTermRecommendations.adsImpressions'] ?? 0),
    cpc_60d: Number(r['ExperimentTermRecommendations.cpc'] ?? 0),
    conv_rate_60d: Number(r['ExperimentTermRecommendations.adsCvrPct'] ?? 0),
    net_roas_60d: Number(r['ExperimentTermRecommendations.adsNetRoas'] ?? 0),
    market_volume: Number(r['ExperimentTermRecommendations.marketWeeklyOrders'] ?? 0),
    impression_share: Number(r['ExperimentTermRecommendations.yourOrdersSharePct'] ?? 0),
  }));
}

/** Sqp → sqp_volume_4w: SUM(AMAZON_IMPRESSIONS) per search term over last 4 weeks */
async function loadSqpVolume4wFromCube(): Promise<Record<string, number>> {
  const rows = await cubeLoad({
    measures: ['Sqp.amazonImpressions'],
    dimensions: ['Sqp.searchQuery'],
    timeDimensions: [{ dimension: 'Sqp.reportingDate', dateRange: 'Last 4 weeks' }],
    limit: 5000,
  });
  const out: Record<string, number> = {};
  for (const r of rows as Record<string, unknown>[]) {
    const term = String(r['Sqp.searchQuery'] ?? '').toLowerCase();
    if (term) out[term] = (out[term] ?? 0) + Number(r['Sqp.amazonImpressions'] ?? 0);
  }
  return out;
}

/** ExperimentCampaign + Ads → experiment_campaigns */
async function loadExperimentCampaignsFromCube(): Promise<ExperimentCampaignRow[]> {
  const rows = await cubeLoad({
    dimensions: ['ExperimentCampaign.experimentId', 'ExperimentCampaign.campaignId', 'ExperimentCampaign.campaignName', 'ExperimentCampaign.topOfSearchPct', 'ExperimentCampaign.productPagePct', 'ExperimentCampaign.restOfSearchPct'],
    limit: 200,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    experiment_id: r['ExperimentCampaign.experimentId'] ? String(r['ExperimentCampaign.experimentId']) : null,
    campaign_id: String(r['ExperimentCampaign.campaignId'] ?? ''),
    campaign_name: String(r['ExperimentCampaign.campaignName'] ?? ''),
    campaign_type: '',
    top_of_search_pct: r['ExperimentCampaign.topOfSearchPct'] != null ? Number(r['ExperimentCampaign.topOfSearchPct']) : null,
    product_page_pct: r['ExperimentCampaign.productPagePct'] != null ? Number(r['ExperimentCampaign.productPagePct']) : null,
    rest_of_search_pct: r['ExperimentCampaign.restOfSearchPct'] != null ? Number(r['ExperimentCampaign.restOfSearchPct']) : null,
    notes: null,
    spend: 0,
    orders: 0,
    clicks: 0,
    impressions: 0,
    first_date: null,
    last_date: null,
  }));
}

/** ExperimentTemplates → experiment_templates (Strategies page) */
async function loadExperimentTemplatesFromCube(): Promise<ExperimentTemplateRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'ExperimentTemplates.experimentId', 'ExperimentTemplates.experimentName', 'ExperimentTemplates.strategyId',
      'ExperimentTemplates.description', 'ExperimentTemplates.status', 'ExperimentTemplates.startDate', 'ExperimentTemplates.endDate',
      'ExperimentTemplates.baselineDays', 'ExperimentTemplates.outcomeScore', 'ExperimentTemplates.outcomeTags', 'ExperimentTemplates.outcomeNotes',
      'ExperimentTemplates.lifecycleStage', 'ExperimentTemplates.graduationConfidence', 'ExperimentTemplates.seasonContext',
      'ExperimentTemplates.daysRunning', 'ExperimentTemplates.totalSpend', 'ExperimentTemplates.totalOrders', 'ExperimentTemplates.totalClicks',
      'ExperimentTemplates.totalImpressions', 'ExperimentTemplates.totalSales', 'ExperimentTemplates.netRoas',
      'ExperimentTemplates.convRate', 'ExperimentTemplates.cpc', 'ExperimentTemplates.uniqueSearchTerms',
    ],
    limit: 100,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    strategy_id: String(r['ExperimentTemplates.strategyId'] ?? ''),
    experiment_id: String(r['ExperimentTemplates.experimentId'] ?? ''),
    experiment_name: String(r['ExperimentTemplates.experimentName'] ?? ''),
    description: r['ExperimentTemplates.description'] ? String(r['ExperimentTemplates.description']) : null,
    status: String(r['ExperimentTemplates.status'] ?? ''),
    start_date: r['ExperimentTemplates.startDate'] ? String(r['ExperimentTemplates.startDate']) : null,
    end_date: r['ExperimentTemplates.endDate'] ? String(r['ExperimentTemplates.endDate']) : null,
    baseline_days: r['ExperimentTemplates.baselineDays'] != null ? Number(r['ExperimentTemplates.baselineDays']) : null,
    outcome_score: r['ExperimentTemplates.outcomeScore'] != null ? Number(r['ExperimentTemplates.outcomeScore']) : null,
    outcome_tags: r['ExperimentTemplates.outcomeTags'] ? String(r['ExperimentTemplates.outcomeTags']) : null,
    outcome_notes: r['ExperimentTemplates.outcomeNotes'] ? String(r['ExperimentTemplates.outcomeNotes']) : null,
    lifecycle_stage: r['ExperimentTemplates.lifecycleStage'] ? String(r['ExperimentTemplates.lifecycleStage']) : null,
    graduation_confidence: r['ExperimentTemplates.graduationConfidence'] ? String(r['ExperimentTemplates.graduationConfidence']) : null,
    season_context: r['ExperimentTemplates.seasonContext'] ? String(r['ExperimentTemplates.seasonContext']) : null,
    days_running: Number(r['ExperimentTemplates.daysRunning'] ?? 0),
    total_spend: r['ExperimentTemplates.totalSpend'] != null ? Number(r['ExperimentTemplates.totalSpend']) : null,
    total_orders: r['ExperimentTemplates.totalOrders'] != null ? Number(r['ExperimentTemplates.totalOrders']) : null,
    total_clicks: r['ExperimentTemplates.totalClicks'] != null ? Number(r['ExperimentTemplates.totalClicks']) : null,
    total_impressions: r['ExperimentTemplates.totalImpressions'] != null ? Number(r['ExperimentTemplates.totalImpressions']) : null,
    total_sales: r['ExperimentTemplates.totalSales'] != null ? Number(r['ExperimentTemplates.totalSales']) : null,
    net_roas: r['ExperimentTemplates.netRoas'] != null ? Number(r['ExperimentTemplates.netRoas']) : null,
    conv_rate: r['ExperimentTemplates.convRate'] != null ? Number(r['ExperimentTemplates.convRate']) : null,
    cpc: r['ExperimentTemplates.cpc'] != null ? Number(r['ExperimentTemplates.cpc']) : null,
    unique_search_terms: r['ExperimentTemplates.uniqueSearchTerms'] != null ? Number(r['ExperimentTemplates.uniqueSearchTerms']) : null,
  }));
}

/** Ads → campaign_search_terms */
async function loadCampaignSearchTermsFromCube(): Promise<CampaignSearchTermRow[]> {
  const rows = await cubeLoad({
    measures: ['Ads.spend', 'Ads.orders', 'Ads.clicks', 'Ads.impressions'],
    dimensions: ['Ads.campaignId', 'Ads.searchTerm'],
    timeDimensions: [{ dimension: 'Ads.date', dateRange: 'Last 90 days' }],
    limit: 100000,
  });
  const byKey = new Map<string, { spend: number; orders: number; clicks: number; impressions: number }>();
  for (const r of rows as Record<string, unknown>[]) {
    const key = `${r['Ads.campaignId']}|${r['Ads.searchTerm'] ?? ''}`;
    const cur = byKey.get(key) ?? { spend: 0, orders: 0, clicks: 0, impressions: 0 };
    cur.spend += Number(r['Ads.spend'] ?? 0);
    cur.orders += Number(r['Ads.orders'] ?? 0);
    cur.clicks += Number(r['Ads.clicks'] ?? 0);
    cur.impressions += Number(r['Ads.impressions'] ?? 0);
    byKey.set(key, cur);
  }
  return Array.from(byKey.entries())
    .filter(([, m]) => m.spend > 0)
    .map(([key, m]) => {
      const [campaignId, searchTerm] = key.split('|');
      return {
        campaign_id: campaignId,
        search_term: searchTerm || '',
        spend: m.spend,
        orders: m.orders,
        clicks: m.clicks,
        impressions: m.impressions,
        conv_rate: m.clicks ? (m.orders * 100) / m.clicks : 0,
        cpc: m.clicks ? m.spend / m.clicks : 0,
      };
    });
}

async function loadCoachDecisionsFromCube(): Promise<CoachDecisionRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'AdsCoachDecision.searchTerm', 'AdsCoachDecision.bestAsin',
      'AdsCoachDecision.productShortName', 'AdsCoachDecision.parentName',
      'AdsCoachDecision.marginPerUnit', 'AdsCoachDecision.campaignCount4w',
      'AdsCoachDecision.sellingCampaigns4w',
      // Ads 4w
      'AdsCoachDecision.adsSpend4w', 'AdsCoachDecision.adsOrders4w',
      'AdsCoachDecision.adsUnits4w', 'AdsCoachDecision.adsClicks4w',
      'AdsCoachDecision.adsImpressions4w', 'AdsCoachDecision.adsSales4w',
      'AdsCoachDecision.adsCpc4w', 'AdsCoachDecision.adsCvrPct4w',
      'AdsCoachDecision.adsCostPerOrder4w',
      'AdsCoachDecision.adsNetRoas4w', 'AdsCoachDecision.adsNetProfit4w',
      // Ads Lifetime
      'AdsCoachDecision.adsSpendLifetime', 'AdsCoachDecision.adsOrdersLifetime',
      'AdsCoachDecision.adsNetRoasLifetime',
      // Ads LY Peak
      'AdsCoachDecision.adsSpendLyPeak', 'AdsCoachDecision.adsOrdersLyPeak',
      'AdsCoachDecision.adsUnitsLyPeak', 'AdsCoachDecision.adsClicksLyPeak',
      'AdsCoachDecision.adsImpressionsLyPeak', 'AdsCoachDecision.adsSalesLyPeak',
      'AdsCoachDecision.adsCpcLyPeak', 'AdsCoachDecision.adsCvrPctLyPeak',
      'AdsCoachDecision.adsNetRoasLyPeak',
      // SQP 4w Your ASIN
      'AdsCoachDecision.sqpImpressions4w', 'AdsCoachDecision.sqpClicks4w',
      'AdsCoachDecision.sqpCartAdds4w', 'AdsCoachDecision.sqpOrders4w',
      'AdsCoachDecision.sqpSales4w', 'AdsCoachDecision.sqpOrganicUnits4w',
      'AdsCoachDecision.sqpShowRate4w', 'AdsCoachDecision.sqpImpressionShare4w',
      'AdsCoachDecision.sqpOrganicRank4w',
      // SQP 4w Amazon market
      'AdsCoachDecision.sqpAmazonImpressions4w', 'AdsCoachDecision.sqpAmazonClicks4w',
      'AdsCoachDecision.sqpAmazonCartAdds4w', 'AdsCoachDecision.sqpAmazonOrders4w',
      'AdsCoachDecision.sqpAmazonSearchVolume4w',
      // SQP LY Peak Your ASIN
      'AdsCoachDecision.sqpImpressionsLyPeak', 'AdsCoachDecision.sqpClicksLyPeak',
      'AdsCoachDecision.sqpCartAddsLyPeak', 'AdsCoachDecision.sqpOrdersLyPeak',
      'AdsCoachDecision.sqpSalesLyPeak', 'AdsCoachDecision.sqpShowRateLyPeak',
      'AdsCoachDecision.sqpImpressionShareLyPeak', 'AdsCoachDecision.sqpOrganicRankLyPeak',
      // SQP LY Peak Amazon market
      'AdsCoachDecision.sqpAmazonImpressionsLyPeak', 'AdsCoachDecision.sqpAmazonClicksLyPeak',
      'AdsCoachDecision.sqpAmazonCartAddsLyPeak', 'AdsCoachDecision.sqpAmazonOrdersLyPeak',
      'AdsCoachDecision.sqpAmazonSearchVolumeLyPeak',
      // Decision
      'AdsCoachDecision.signal', 'AdsCoachDecision.decision',
      'AdsCoachDecision.priorityScore', 'AdsCoachDecision.confidence',
      'AdsCoachDecision.reason',
      // 7d activity
      'AdsCoachDecision.adsImpressions7d', 'AdsCoachDecision.adsSpend7d',
      'AdsCoachDecision.adsActiveLast7d',
    ],
    limit: 50000,
  });
  const n = (k: string) => Number(r[k] ?? 0);
  const s = (k: string) => String(r[k] ?? '');
  const nul = (k: string) => r[k] != null ? Number(r[k]) : null;
  let r: Record<string, unknown>;
  return (rows as Record<string, unknown>[]).map(row => {
    r = row;
    return {
      search_term: s('AdsCoachDecision.searchTerm'),
      best_asin: s('AdsCoachDecision.bestAsin'),
      product_short_name: s('AdsCoachDecision.productShortName'),
      parent_name: s('AdsCoachDecision.parentName'),
      margin_per_unit: n('AdsCoachDecision.marginPerUnit'),
      campaign_count_4w: n('AdsCoachDecision.campaignCount4w'),
      selling_campaigns_4w: n('AdsCoachDecision.sellingCampaigns4w'),
      // Ads 4w
      ads_spend_4w: n('AdsCoachDecision.adsSpend4w'),
      ads_orders_4w: n('AdsCoachDecision.adsOrders4w'),
      ads_units_4w: n('AdsCoachDecision.adsUnits4w'),
      ads_clicks_4w: n('AdsCoachDecision.adsClicks4w'),
      ads_impressions_4w: n('AdsCoachDecision.adsImpressions4w'),
      ads_sales_4w: n('AdsCoachDecision.adsSales4w'),
      ads_cpc_4w: nul('AdsCoachDecision.adsCpc4w'),
      ads_cvr_pct_4w: nul('AdsCoachDecision.adsCvrPct4w'),
      ads_cost_per_order_4w: nul('AdsCoachDecision.adsCostPerOrder4w'),
      ads_net_roas_4w: n('AdsCoachDecision.adsNetRoas4w'),
      ads_net_profit_4w: n('AdsCoachDecision.adsNetProfit4w'),
      // Ads Lifetime
      ads_spend_lifetime: n('AdsCoachDecision.adsSpendLifetime'),
      ads_orders_lifetime: n('AdsCoachDecision.adsOrdersLifetime'),
      ads_net_roas_lifetime: n('AdsCoachDecision.adsNetRoasLifetime'),
      // 7d activity
      ads_impressions_7d: n('AdsCoachDecision.adsImpressions7d'),
      ads_spend_7d: n('AdsCoachDecision.adsSpend7d'),
      ads_active_last_7d: Boolean(r['AdsCoachDecision.adsActiveLast7d']),
      // Ads LY Peak
      ads_spend_ly_peak: n('AdsCoachDecision.adsSpendLyPeak'),
      ads_orders_ly_peak: n('AdsCoachDecision.adsOrdersLyPeak'),
      ads_units_ly_peak: n('AdsCoachDecision.adsUnitsLyPeak'),
      ads_clicks_ly_peak: n('AdsCoachDecision.adsClicksLyPeak'),
      ads_impressions_ly_peak: n('AdsCoachDecision.adsImpressionsLyPeak'),
      ads_sales_ly_peak: n('AdsCoachDecision.adsSalesLyPeak'),
      ads_cpc_ly_peak: nul('AdsCoachDecision.adsCpcLyPeak'),
      ads_cvr_pct_ly_peak: nul('AdsCoachDecision.adsCvrPctLyPeak'),
      ads_net_roas_ly_peak: nul('AdsCoachDecision.adsNetRoasLyPeak'),
      // SQP 4w Your ASIN
      sqp_impressions_4w: n('AdsCoachDecision.sqpImpressions4w'),
      sqp_clicks_4w: n('AdsCoachDecision.sqpClicks4w'),
      sqp_cart_adds_4w: n('AdsCoachDecision.sqpCartAdds4w'),
      sqp_orders_4w: n('AdsCoachDecision.sqpOrders4w'),
      sqp_sales_4w: n('AdsCoachDecision.sqpSales4w'),
      sqp_organic_units_4w: n('AdsCoachDecision.sqpOrganicUnits4w'),
      sqp_show_rate_4w: n('AdsCoachDecision.sqpShowRate4w'),
      sqp_impression_share_4w: n('AdsCoachDecision.sqpImpressionShare4w'),
      sqp_organic_rank_4w: n('AdsCoachDecision.sqpOrganicRank4w'),
      // SQP 4w Amazon
      sqp_amazon_impressions_4w: n('AdsCoachDecision.sqpAmazonImpressions4w'),
      sqp_amazon_clicks_4w: n('AdsCoachDecision.sqpAmazonClicks4w'),
      sqp_amazon_cart_adds_4w: n('AdsCoachDecision.sqpAmazonCartAdds4w'),
      sqp_amazon_orders_4w: n('AdsCoachDecision.sqpAmazonOrders4w'),
      sqp_amazon_search_volume_4w: n('AdsCoachDecision.sqpAmazonSearchVolume4w'),
      // SQP LY Peak Your ASIN
      sqp_impressions_ly_peak: n('AdsCoachDecision.sqpImpressionsLyPeak'),
      sqp_clicks_ly_peak: n('AdsCoachDecision.sqpClicksLyPeak'),
      sqp_cart_adds_ly_peak: n('AdsCoachDecision.sqpCartAddsLyPeak'),
      sqp_orders_ly_peak: n('AdsCoachDecision.sqpOrdersLyPeak'),
      sqp_sales_ly_peak: n('AdsCoachDecision.sqpSalesLyPeak'),
      sqp_show_rate_ly_peak: n('AdsCoachDecision.sqpShowRateLyPeak'),
      sqp_impression_share_ly_peak: n('AdsCoachDecision.sqpImpressionShareLyPeak'),
      sqp_organic_rank_ly_peak: n('AdsCoachDecision.sqpOrganicRankLyPeak'),
      // SQP LY Peak Amazon
      sqp_amazon_impressions_ly_peak: n('AdsCoachDecision.sqpAmazonImpressionsLyPeak'),
      sqp_amazon_clicks_ly_peak: n('AdsCoachDecision.sqpAmazonClicksLyPeak'),
      sqp_amazon_cart_adds_ly_peak: n('AdsCoachDecision.sqpAmazonCartAddsLyPeak'),
      sqp_amazon_orders_ly_peak: n('AdsCoachDecision.sqpAmazonOrdersLyPeak'),
      sqp_amazon_search_volume_ly_peak: n('AdsCoachDecision.sqpAmazonSearchVolumeLyPeak'),
      // Decision
      signal: s('AdsCoachDecision.signal'),
      decision: s('AdsCoachDecision.decision'),
      priority_score: n('AdsCoachDecision.priorityScore'),
      confidence: s('AdsCoachDecision.confidence'),
      reason: s('AdsCoachDecision.reason'),
    };
  });
}

async function loadCoachTermsFromCube(): Promise<CoachTermRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'AdsCoachTerm.campaignId', 'AdsCoachTerm.campaignName', 'AdsCoachTerm.campaignType',
      'AdsCoachTerm.searchTerm', 'AdsCoachTerm.asin',
      'AdsCoachTerm.productShortName', 'AdsCoachTerm.parentName',
      'AdsCoachTerm.experimentName', 'AdsCoachTerm.strategyId', 'AdsCoachTerm.strategyName',
      'AdsCoachTerm.adsSpend4w', 'AdsCoachTerm.adsOrders4w', 'AdsCoachTerm.adsClicks4w',
      'AdsCoachTerm.adsSales4w', 'AdsCoachTerm.adsCpc4w', 'AdsCoachTerm.adsCvrPct4w',
      'AdsCoachTerm.adsNetRoas4w', 'AdsCoachTerm.adsNetProfit4w', 'AdsCoachTerm.marginPerUnit',
      'AdsCoachTerm.termSpend4w', 'AdsCoachTerm.termOrders4w',
      'AdsCoachTerm.termCampaignCount', 'AdsCoachTerm.termSellingCampaigns',
      'AdsCoachTerm.spendSharePct', 'AdsCoachTerm.ordersSharePct',
      'AdsCoachTerm.sqpOrders4w',
      'AdsCoachTerm.targeting', 'AdsCoachTerm.keywordId',
      'AdsCoachTerm.targetAction', 'AdsCoachTerm.effectiveRoas',
      'AdsCoachTerm.adsWeightedNetRoas',
      'AdsCoachTerm.targetNetRoas8w', 'AdsCoachTerm.targetClicks8w',
      'AdsCoachTerm.targetOrders8w', 'AdsCoachTerm.targetSpend8w',
      'AdsCoachTerm.targetDecisionTrace', 'AdsCoachTerm.recommendationObject',
      'AdsCoachTerm.currentBid', 'AdsCoachTerm.recommendedBid', 'AdsCoachTerm.bidChangePct',
      'AdsCoachTerm.matchType',
      'AdsCoachTerm.action', 'AdsCoachTerm.priorityScore',
      'AdsCoachTerm.confidence', 'AdsCoachTerm.reason',
      'AdsCoachTerm.heroAsin', 'AdsCoachTerm.heroProductName', 'AdsCoachTerm.isHeroMatch',
      'AdsCoachTerm.heroAction', 'AdsCoachTerm.heroActionExplanation',
      'AdsCoachTerm.heroNetRoas', 'AdsCoachTerm.heroTotalOrders',
    ],
    limit: 50000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    campaign_id: String(r['AdsCoachTerm.campaignId'] ?? ''),
    campaign_name: String(r['AdsCoachTerm.campaignName'] ?? ''),
    campaign_type: String(r['AdsCoachTerm.campaignType'] ?? ''),
    search_term: String(r['AdsCoachTerm.searchTerm'] ?? ''),
    asin: String(r['AdsCoachTerm.asin'] ?? ''),
    product_short_name: String(r['AdsCoachTerm.productShortName'] ?? ''),
    parent_name: String(r['AdsCoachTerm.parentName'] ?? ''),
    experiment_name: r['AdsCoachTerm.experimentName'] as string | null,
    strategy_id: r['AdsCoachTerm.strategyId'] as string | null,
    strategy_name: r['AdsCoachTerm.strategyName'] as string | null,
    ads_spend_4w: Number(r['AdsCoachTerm.adsSpend4w'] ?? 0),
    ads_orders_4w: Number(r['AdsCoachTerm.adsOrders4w'] ?? 0),
    ads_clicks_4w: Number(r['AdsCoachTerm.adsClicks4w'] ?? 0),
    ads_sales_4w: Number(r['AdsCoachTerm.adsSales4w'] ?? 0),
    ads_cpc_4w: r['AdsCoachTerm.adsCpc4w'] != null ? Number(r['AdsCoachTerm.adsCpc4w']) : null,
    ads_cvr_pct_4w: r['AdsCoachTerm.adsCvrPct4w'] != null ? Number(r['AdsCoachTerm.adsCvrPct4w']) : null,
    ads_net_roas_4w: Number(r['AdsCoachTerm.adsNetRoas4w'] ?? 0),
    ads_net_profit_4w: Number(r['AdsCoachTerm.adsNetProfit4w'] ?? 0),
    margin_per_unit: Number(r['AdsCoachTerm.marginPerUnit'] ?? 0),
    term_spend_4w: Number(r['AdsCoachTerm.termSpend4w'] ?? 0),
    term_orders_4w: Number(r['AdsCoachTerm.termOrders4w'] ?? 0),
    term_campaign_count: Number(r['AdsCoachTerm.termCampaignCount'] ?? 0),
    term_selling_campaigns: Number(r['AdsCoachTerm.termSellingCampaigns'] ?? 0),
    spend_share_pct: r['AdsCoachTerm.spendSharePct'] != null ? Number(r['AdsCoachTerm.spendSharePct']) : null,
    orders_share_pct: r['AdsCoachTerm.ordersSharePct'] != null ? Number(r['AdsCoachTerm.ordersSharePct']) : null,
    sqp_orders_4w: Number(r['AdsCoachTerm.sqpOrders4w'] ?? 0),
    targeting: r['AdsCoachTerm.targeting'] as string | null,
    keyword_id: r['AdsCoachTerm.keywordId'] ? String(r['AdsCoachTerm.keywordId']) : null,
    target_action: r['AdsCoachTerm.targetAction'] as string | null,
    effective_roas: r['AdsCoachTerm.effectiveRoas'] != null ? Number(r['AdsCoachTerm.effectiveRoas']) : null,
    weighted_total_net_roas: r['AdsCoachTerm.adsWeightedNetRoas'] != null ? Number(r['AdsCoachTerm.adsWeightedNetRoas']) : null,
    target_net_roas_8w: r['AdsCoachTerm.targetNetRoas8w'] != null ? Number(r['AdsCoachTerm.targetNetRoas8w']) : null,
    target_clicks_8w: r['AdsCoachTerm.targetClicks8w'] != null ? Number(r['AdsCoachTerm.targetClicks8w']) : null,
    target_orders_8w: r['AdsCoachTerm.targetOrders8w'] != null ? Number(r['AdsCoachTerm.targetOrders8w']) : null,
    target_spend_8w: r['AdsCoachTerm.targetSpend8w'] != null ? Number(r['AdsCoachTerm.targetSpend8w']) : null,
    target_decision_trace: (() => { try { const raw = r['AdsCoachTerm.targetDecisionTrace']; return raw ? JSON.parse(String(raw)) : null; } catch { return null; } })(),
    recommendation_object: (String(r['AdsCoachTerm.recommendationObject'] ?? 'TERM') as 'TARGET' | 'TERM'),
    current_bid: r['AdsCoachTerm.currentBid'] != null ? Number(r['AdsCoachTerm.currentBid']) : null,
    recommended_bid: r['AdsCoachTerm.recommendedBid'] != null ? Number(r['AdsCoachTerm.recommendedBid']) : null,
    bid_change_pct: r['AdsCoachTerm.bidChangePct'] != null ? Number(r['AdsCoachTerm.bidChangePct']) : null,
    match_type: r['AdsCoachTerm.matchType'] ? String(r['AdsCoachTerm.matchType']) : null,
    action: String(r['AdsCoachTerm.action'] ?? ''),
    priority_score: Number(r['AdsCoachTerm.priorityScore'] ?? 0),
    confidence: String(r['AdsCoachTerm.confidence'] ?? ''),
    reason: String(r['AdsCoachTerm.reason'] ?? ''),
    hero_asin: r['AdsCoachTerm.heroAsin'] ? String(r['AdsCoachTerm.heroAsin']) : null,
    hero_product_name: r['AdsCoachTerm.heroProductName'] ? String(r['AdsCoachTerm.heroProductName']) : null,
    is_hero_match: Boolean(r['AdsCoachTerm.isHeroMatch']),
    hero_action: r['AdsCoachTerm.heroAction'] ? String(r['AdsCoachTerm.heroAction']) : null,
    hero_action_explanation: r['AdsCoachTerm.heroActionExplanation'] ? String(r['AdsCoachTerm.heroActionExplanation']) : null,
    hero_net_roas: r['AdsCoachTerm.heroNetRoas'] != null ? Number(r['AdsCoachTerm.heroNetRoas']) : null,
    hero_total_orders: r['AdsCoachTerm.heroTotalOrders'] != null ? Number(r['AdsCoachTerm.heroTotalOrders']) : null,
  }));
}

async function loadCoachCampaignsFromCube(): Promise<CoachCampaignRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'AdsCoachCampaign.campaignId', 'AdsCoachCampaign.campaignName',
      'AdsCoachCampaign.experimentName', 'AdsCoachCampaign.strategyId', 'AdsCoachCampaign.strategyName',
      'AdsCoachCampaign.totalTerms', 'AdsCoachCampaign.totalSpend4w', 'AdsCoachCampaign.totalOrders4w',
      'AdsCoachCampaign.totalNetProfit4w', 'AdsCoachCampaign.campaignNetRoas4w', 'AdsCoachCampaign.campaignAvgCpc4w',
      'AdsCoachCampaign.termsNegate', 'AdsCoachCampaign.termsReduce', 'AdsCoachCampaign.termsKeep',
      'AdsCoachCampaign.termsScale', 'AdsCoachCampaign.termsMonitor',
      'AdsCoachCampaign.spendOnNegateTerms', 'AdsCoachCampaign.campaignAction',
      'AdsCoachCampaign.estWeeklySavings', 'AdsCoachCampaign.topNegateTerms',
      'AdsCoachCampaign.topScaleTerms', 'AdsCoachCampaign.actionSummary',
      'AdsCoachCampaign.totalPriorityScore',
      'AdsCoachCampaign.termsHeroMismatch', 'AdsCoachCampaign.spendOnWrongHero',
      'AdsCoachCampaign.placementAction',
    ],
    limit: 1000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    campaign_id: String(r['AdsCoachCampaign.campaignId'] ?? ''),
    campaign_name: String(r['AdsCoachCampaign.campaignName'] ?? ''),
    experiment_name: r['AdsCoachCampaign.experimentName'] as string | null,
    strategy_id: r['AdsCoachCampaign.strategyId'] as string | null,
    strategy_name: r['AdsCoachCampaign.strategyName'] as string | null,
    total_terms: Number(r['AdsCoachCampaign.totalTerms'] ?? 0),
    total_spend_4w: Number(r['AdsCoachCampaign.totalSpend4w'] ?? 0),
    total_orders_4w: Number(r['AdsCoachCampaign.totalOrders4w'] ?? 0),
    total_net_profit_4w: Number(r['AdsCoachCampaign.totalNetProfit4w'] ?? 0),
    campaign_net_roas_4w: r['AdsCoachCampaign.campaignNetRoas4w'] != null ? Number(r['AdsCoachCampaign.campaignNetRoas4w']) : null,
    campaign_avg_cpc_4w: r['AdsCoachCampaign.campaignAvgCpc4w'] != null ? Number(r['AdsCoachCampaign.campaignAvgCpc4w']) : null,
    terms_negate: Number(r['AdsCoachCampaign.termsNegate'] ?? 0),
    terms_reduce: Number(r['AdsCoachCampaign.termsReduce'] ?? 0),
    terms_keep: Number(r['AdsCoachCampaign.termsKeep'] ?? 0),
    terms_scale: Number(r['AdsCoachCampaign.termsScale'] ?? 0),
    terms_monitor: Number(r['AdsCoachCampaign.termsMonitor'] ?? 0),
    spend_on_negate_terms: Number(r['AdsCoachCampaign.spendOnNegateTerms'] ?? 0),
    campaign_action: String(r['AdsCoachCampaign.campaignAction'] ?? ''),
    est_weekly_savings: Number(r['AdsCoachCampaign.estWeeklySavings'] ?? 0),
    top_negate_terms: String(r['AdsCoachCampaign.topNegateTerms'] ?? ''),
    top_scale_terms: String(r['AdsCoachCampaign.topScaleTerms'] ?? ''),
    action_summary: String(r['AdsCoachCampaign.actionSummary'] ?? ''),
    total_priority_score: Number(r['AdsCoachCampaign.totalPriorityScore'] ?? 0),
    terms_hero_mismatch: Number(r['AdsCoachCampaign.termsHeroMismatch'] ?? 0),
    spend_on_wrong_hero: Number(r['AdsCoachCampaign.spendOnWrongHero'] ?? 0),
    placement_action: String(r['AdsCoachCampaign.placementAction'] ?? 'MAINTAIN'),
  }));
}

async function loadPhraseNegativesFromCube(): Promise<PhraseNegativeRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'AdsCoachPhraseNegatives.phrase', 'AdsCoachPhraseNegatives.ngramSize',
      'AdsCoachPhraseNegatives.campaignId', 'AdsCoachPhraseNegatives.adGroupId', 'AdsCoachPhraseNegatives.campaignName',
      'AdsCoachPhraseNegatives.campaignType', 'AdsCoachPhraseNegatives.portfolioName',
      'AdsCoachPhraseNegatives.phraseTermCount', 'AdsCoachPhraseNegatives.phraseSpend8w',
      'AdsCoachPhraseNegatives.phraseOrders8w', 'AdsCoachPhraseNegatives.phraseClicks8w',
      'AdsCoachPhraseNegatives.phraseOrders1y', 'AdsCoachPhraseNegatives.phraseSpend1y',
      'AdsCoachPhraseNegatives.phraseSales1y', 'AdsCoachPhraseNegatives.phraseRoas1y',
      'AdsCoachPhraseNegatives.top3MonthsPct', 'AdsCoachPhraseNegatives.peakMonths',
      'AdsCoachPhraseNegatives.seasonalTheme', 'AdsCoachPhraseNegatives.action',
      'AdsCoachPhraseNegatives.priorityScore', 'AdsCoachPhraseNegatives.reason',
    ],
    limit: 500,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    phrase: String(r['AdsCoachPhraseNegatives.phrase'] ?? ''),
    ngram_size: Number(r['AdsCoachPhraseNegatives.ngramSize'] ?? 2),
    campaign_id: String(r['AdsCoachPhraseNegatives.campaignId'] ?? ''),
    ad_group_id: String(r['AdsCoachPhraseNegatives.adGroupId'] ?? ''),
    campaign_name: String(r['AdsCoachPhraseNegatives.campaignName'] ?? ''),
    campaign_type: String(r['AdsCoachPhraseNegatives.campaignType'] ?? ''),
    portfolio_name: String(r['AdsCoachPhraseNegatives.portfolioName'] ?? ''),
    phrase_term_count: Number(r['AdsCoachPhraseNegatives.phraseTermCount'] ?? 0),
    phrase_spend_8w: Number(r['AdsCoachPhraseNegatives.phraseSpend8w'] ?? 0),
    phrase_orders_8w: Number(r['AdsCoachPhraseNegatives.phraseOrders8w'] ?? 0),
    phrase_clicks_8w: Number(r['AdsCoachPhraseNegatives.phraseClicks8w'] ?? 0),
    phrase_orders_1y: Number(r['AdsCoachPhraseNegatives.phraseOrders1y'] ?? 0),
    phrase_spend_1y: Number(r['AdsCoachPhraseNegatives.phraseSpend1y'] ?? 0),
    phrase_sales_1y: Number(r['AdsCoachPhraseNegatives.phraseSales1y'] ?? 0),
    phrase_roas_1y: Number(r['AdsCoachPhraseNegatives.phraseRoas1y'] ?? 0),
    top3_months_pct: Number(r['AdsCoachPhraseNegatives.top3MonthsPct'] ?? 0),
    peak_months: String(r['AdsCoachPhraseNegatives.peakMonths'] ?? ''),
    seasonal_theme: String(r['AdsCoachPhraseNegatives.seasonalTheme'] ?? 'General Peak'),
    action: String(r['AdsCoachPhraseNegatives.action'] ?? ''),
    priority_score: Number(r['AdsCoachPhraseNegatives.priorityScore'] ?? 0),
    reason: String(r['AdsCoachPhraseNegatives.reason'] ?? ''),
  }));
}

async function loadExperimentEvaluationsFromCube(): Promise<ExperimentEvaluationRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'ExperimentEvaluation.experimentId', 'ExperimentEvaluation.experimentName',
      'ExperimentEvaluation.strategyId', 'ExperimentEvaluation.strategyName',
      'ExperimentEvaluation.status', 'ExperimentEvaluation.experimentDescription',
      'ExperimentEvaluation.strategyGoal',
      'ExperimentEvaluation.totalSpend', 'ExperimentEvaluation.totalOrders',
      'ExperimentEvaluation.totalSales', 'ExperimentEvaluation.daysWithData',
      'ExperimentEvaluation.uniqueTerms', 'ExperimentEvaluation.convertingTerms',
      'ExperimentEvaluation.avgCpc', 'ExperimentEvaluation.cvrPct', 'ExperimentEvaluation.grossRoas',
      'ExperimentEvaluation.wastedSpend', 'ExperimentEvaluation.wastedPct',
      'ExperimentEvaluation.termsGraduatedToExact',
      'ExperimentEvaluation.topConvertingTerms', 'ExperimentEvaluation.topWastedTerms',
      'ExperimentEvaluation.check1Cpc', 'ExperimentEvaluation.check2Roas',
      'ExperimentEvaluation.check3Data', 'ExperimentEvaluation.check4Discovery',
      'ExperimentEvaluation.check5Graduated', 'ExperimentEvaluation.check6Waste',
      'ExperimentEvaluation.check7Cvr',
      'ExperimentEvaluation.verdict', 'ExperimentEvaluation.verdictReason',
    ],
    limit: 200,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    experiment_id: String(r['ExperimentEvaluation.experimentId'] ?? ''),
    experiment_name: String(r['ExperimentEvaluation.experimentName'] ?? ''),
    strategy_id: String(r['ExperimentEvaluation.strategyId'] ?? ''),
    strategy_name: String(r['ExperimentEvaluation.strategyName'] ?? ''),
    status: String(r['ExperimentEvaluation.status'] ?? ''),
    experiment_description: r['ExperimentEvaluation.experimentDescription'] as string | null,
    strategy_goal: r['ExperimentEvaluation.strategyGoal'] as string | null,
    total_spend: Number(r['ExperimentEvaluation.totalSpend'] ?? 0),
    total_orders: Number(r['ExperimentEvaluation.totalOrders'] ?? 0),
    total_sales: Number(r['ExperimentEvaluation.totalSales'] ?? 0),
    days_with_data: Number(r['ExperimentEvaluation.daysWithData'] ?? 0),
    unique_terms: Number(r['ExperimentEvaluation.uniqueTerms'] ?? 0),
    converting_terms: Number(r['ExperimentEvaluation.convertingTerms'] ?? 0),
    avg_cpc: r['ExperimentEvaluation.avgCpc'] != null ? Number(r['ExperimentEvaluation.avgCpc']) : null,
    cvr_pct: r['ExperimentEvaluation.cvrPct'] != null ? Number(r['ExperimentEvaluation.cvrPct']) : null,
    gross_roas: r['ExperimentEvaluation.grossRoas'] != null ? Number(r['ExperimentEvaluation.grossRoas']) : null,
    wasted_spend: Number(r['ExperimentEvaluation.wastedSpend'] ?? 0),
    wasted_pct: r['ExperimentEvaluation.wastedPct'] != null ? Number(r['ExperimentEvaluation.wastedPct']) : null,
    terms_graduated_to_exact: Number(r['ExperimentEvaluation.termsGraduatedToExact'] ?? 0),
    top_converting_terms: r['ExperimentEvaluation.topConvertingTerms'] as string | null,
    top_wasted_terms: r['ExperimentEvaluation.topWastedTerms'] as string | null,
    check_1_cpc: String(r['ExperimentEvaluation.check1Cpc'] ?? ''),
    check_2_roas: String(r['ExperimentEvaluation.check2Roas'] ?? ''),
    check_3_data: String(r['ExperimentEvaluation.check3Data'] ?? ''),
    check_4_discovery: String(r['ExperimentEvaluation.check4Discovery'] ?? ''),
    check_5_graduated: String(r['ExperimentEvaluation.check5Graduated'] ?? ''),
    check_6_waste: String(r['ExperimentEvaluation.check6Waste'] ?? ''),
    check_7_cvr: String(r['ExperimentEvaluation.check7Cvr'] ?? ''),
    verdict: String(r['ExperimentEvaluation.verdict'] ?? ''),
    verdict_reason: String(r['ExperimentEvaluation.verdictReason'] ?? ''),
  }));
}

/** KeywordStrategyPrediction → keyword_predictions */
async function loadPredictionsFromCube(): Promise<StrategicPrediction[]> {
  const rows = await cubeLoad({
    dimensions: [
      'KeywordStrategyPrediction.searchTerm', 'KeywordStrategyPrediction.asin',
      'KeywordStrategyPrediction.productShortName',
      'KeywordStrategyPrediction.strategicSignal', 'KeywordStrategyPrediction.predictedNetRoas',
      'KeywordStrategyPrediction.predictionConfidence', 'KeywordStrategyPrediction.lifetimeNetRoas',
      'KeywordStrategyPrediction.seasonalityMultiplier',
      'KeywordStrategyPrediction.hasSeasonalData', 'KeywordStrategyPrediction.bestSeasonMonth',
      'KeywordStrategyPrediction.bestSeasonMonthCvr', 'KeywordStrategyPrediction.heroProductName',
      'KeywordStrategyPrediction.peakMultiplier',
      'KeywordStrategyPrediction.peakDescription', 'KeywordStrategyPrediction.cpcInflationRatio',
      'KeywordStrategyPrediction.predictedCpc', 'KeywordStrategyPrediction.tosCvrBoost',
      'KeywordStrategyPrediction.organicHaloMultiplier', 'KeywordStrategyPrediction.organicWeeklyVelocity',
      'KeywordStrategyPrediction.baseCvr', 'KeywordStrategyPrediction.baseCpc',
      'KeywordStrategyPrediction.totalClicks', 'KeywordStrategyPrediction.totalOrders',
      'KeywordStrategyPrediction.totalSpend', 'KeywordStrategyPrediction.daysWithData',
    ],
    filters: [
      { member: 'KeywordStrategyPrediction.totalClicks', operator: 'gte', values: ['10'] },
    ],
    limit: 5000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    search_term: String(r['KeywordStrategyPrediction.searchTerm'] ?? ''),
    asin: String(r['KeywordStrategyPrediction.asin'] ?? ''),
    product_short_name: String(r['KeywordStrategyPrediction.productShortName'] ?? ''),
    strategic_signal: String(r['KeywordStrategyPrediction.strategicSignal'] ?? ''),
    predicted_net_roas: Number(r['KeywordStrategyPrediction.predictedNetRoas'] ?? 0),
    prediction_confidence: Number(r['KeywordStrategyPrediction.predictionConfidence'] ?? 0),
    lifetime_net_roas: Number(r['KeywordStrategyPrediction.lifetimeNetRoas'] ?? 0),
    seasonality_multiplier: Number(r['KeywordStrategyPrediction.seasonalityMultiplier'] ?? 1),
    has_seasonal_data: String(r['KeywordStrategyPrediction.hasSeasonalData'] ?? 'false') === 'true',
    best_season_month: r['KeywordStrategyPrediction.bestSeasonMonth'] != null ? Number(r['KeywordStrategyPrediction.bestSeasonMonth']) : null,
    best_season_month_cvr: r['KeywordStrategyPrediction.bestSeasonMonthCvr'] != null ? Number(r['KeywordStrategyPrediction.bestSeasonMonthCvr']) : null,
    hero_product_name: r['KeywordStrategyPrediction.heroProductName'] ? String(r['KeywordStrategyPrediction.heroProductName']) : null,
    peak_multiplier: Number(r['KeywordStrategyPrediction.peakMultiplier'] ?? 1),
    peak_description: String(r['KeywordStrategyPrediction.peakDescription'] ?? ''),
    cpc_inflation_ratio: Number(r['KeywordStrategyPrediction.cpcInflationRatio'] ?? 1),
    predicted_cpc: Number(r['KeywordStrategyPrediction.predictedCpc'] ?? 0),
    tos_cvr_boost: Number(r['KeywordStrategyPrediction.tosCvrBoost'] ?? 1),
    organic_halo_multiplier: Number(r['KeywordStrategyPrediction.organicHaloMultiplier'] ?? 1),
    organic_weekly_velocity: Number(r['KeywordStrategyPrediction.organicWeeklyVelocity'] ?? 0),
    base_cvr: Number(r['KeywordStrategyPrediction.baseCvr'] ?? 0),
    base_cpc: Number(r['KeywordStrategyPrediction.baseCpc'] ?? 0),
    total_clicks: Number(r['KeywordStrategyPrediction.totalClicks'] ?? 0),
    total_orders: Number(r['KeywordStrategyPrediction.totalOrders'] ?? 0),
    total_spend: Number(r['KeywordStrategyPrediction.totalSpend'] ?? 0),
    days_with_data: Number(r['KeywordStrategyPrediction.daysWithData'] ?? 0),
  }));
}

/** BrandStrengthWeekly → brand_strength_weekly */
async function loadBrandStrengthFromCube(): Promise<BrandStrengthWeeklyRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'BrandStrengthWeekly.weekStartDate', 
      'BrandStrengthWeekly.brandKeyword',
      'BrandStrengthWeekly.phraseType',
      'BrandStrengthWeekly.requestedProduct',
      'BrandStrengthWeekly.tag'
    ],
    measures: [
      'BrandStrengthWeekly.sqpImpressions', 'BrandStrengthWeekly.sqpClicks',
      'BrandStrengthWeekly.sqpConversions', 'BrandStrengthWeekly.sqpCartAdds',
      'BrandStrengthWeekly.avgShowRate', 'BrandStrengthWeekly.avgImpressionShare',
      'BrandStrengthWeekly.avgOrganicRank', 'BrandStrengthWeekly.totalSearchVolume',
      'BrandStrengthWeekly.adsImpressions', 'BrandStrengthWeekly.adsClicks',
      'BrandStrengthWeekly.adsOrders', 'BrandStrengthWeekly.adsUnits',
      'BrandStrengthWeekly.adsSpend', 'BrandStrengthWeekly.adsSales',
      'BrandStrengthWeekly.adsCpc',
      'BrandStrengthWeekly.brandCvr', 'BrandStrengthWeekly.brandDominanceScore',
    ],
    order: { 'BrandStrengthWeekly.weekStartDate': 'asc' },
    limit: 5000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    week_start_date: String(r['BrandStrengthWeekly.weekStartDate'] ?? ''),
    brand_keyword: String(r['BrandStrengthWeekly.brandKeyword'] ?? 'other'),
    phrase_type: r['BrandStrengthWeekly.phraseType'] ? String(r['BrandStrengthWeekly.phraseType']) : null,
    requested_product: r['BrandStrengthWeekly.requestedProduct'] ? String(r['BrandStrengthWeekly.requestedProduct']) : null,
    tag: r['BrandStrengthWeekly.tag'] ? String(r['BrandStrengthWeekly.tag']) : null,
    sqp_impressions: Number(r['BrandStrengthWeekly.sqpImpressions'] ?? 0),
    sqp_clicks: Number(r['BrandStrengthWeekly.sqpClicks'] ?? 0),
    sqp_conversions: Number(r['BrandStrengthWeekly.sqpConversions'] ?? 0),
    sqp_cart_adds: Number(r['BrandStrengthWeekly.sqpCartAdds'] ?? 0),
    avg_show_rate: parseCubeNum(r['BrandStrengthWeekly.avgShowRate']),
    avg_impression_share: parseCubeNum(r['BrandStrengthWeekly.avgImpressionShare']),
    avg_organic_rank: parseCubeNum(r['BrandStrengthWeekly.avgOrganicRank']),
    total_search_volume: Number(r['BrandStrengthWeekly.totalSearchVolume'] ?? 0),
    brand_asin_count: 0,
    ads_impressions: Number(r['BrandStrengthWeekly.adsImpressions'] ?? 0),
    ads_clicks: Number(r['BrandStrengthWeekly.adsClicks'] ?? 0),
    ads_orders: Number(r['BrandStrengthWeekly.adsOrders'] ?? 0),
    ads_units: Number(r['BrandStrengthWeekly.adsUnits'] ?? 0),
    ads_spend: Number(r['BrandStrengthWeekly.adsSpend'] ?? 0),
    ads_sales: Number(r['BrandStrengthWeekly.adsSales'] ?? 0),
    ads_cpc: parseCubeNum(r['BrandStrengthWeekly.adsCpc']),
    brand_cvr: parseCubeNum(r['BrandStrengthWeekly.brandCvr']),
    brand_dominance_score: parseCubeNum(r['BrandStrengthWeekly.brandDominanceScore']),
  }));
}

function parseCubeNum(v: unknown): number | null {
  if (v == null || v === '' || v === 'NaN') return null;
  const n = Number(v);
  return isNaN(n) ? null : n;
}

function addDays(iso: string, n: number): string {
  const d = new Date(iso);
  d.setDate(d.getDate() + n);
  return d.toISOString().slice(0, 10);
}

function daysBetween(a: string, b: string): number {
  return Math.round((new Date(b).getTime() - new Date(a).getTime()) / 86400000);
}

function dateBetween(today: string, preStart: string, holiday: string): string {
  if (today >= preStart && today <= holiday) return 'ACTIVE';
  if (today < preStart) return 'UPCOMING';
  return 'PASSED';
}

function getWeekStart(iso: string): string {
  // Use noon UTC to avoid timezone day-boundary shifts
  const raw = iso.length === 10 ? iso + 'T12:00:00Z' : iso;
  const d = new Date(raw);
  const day = d.getUTCDay(); // 0=Sun, 1=Mon, ... 6=Sat
  d.setUTCDate(d.getUTCDate() - day); // go back to Sunday
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}

/**
 * useCubeData - fetches dashboard data from Cube when VITE_CUBE_API_URL is set.
 * Returns partial data (Cube-backed fields); use with useUnifiedData for full data.
 */
export function useCubeData(): { data: Partial<DashboardData>; loading: boolean; fromCube: boolean } {
  const [data, setData] = useState<Partial<DashboardData>>({});
  const [loading, setLoading] = useState(true);
  const [retryCount, setRetryCount] = useState(0);
  const fromCube = !!CUBE_API;

  useEffect(() => {
    if (!CUBE_API) {
      if (import.meta.env.DEV) console.warn('[useCubeData] VITE_CUBE_API_URL not set — add to .env');
      setLoading(false);
      return;
    }
    let cancelled = false;
    const failedQueries: string[] = [];

    function resolveLoader(r: PromiseSettledResult<unknown>, name: string): unknown {
      if (r.status === 'rejected') {
        console.error(`[useCubeData] ${name} failed:`, r.reason);
        failedQueries.push(name);
        if (name === 'sqpVolume4w') return {} as Record<string, number>;
        if (name === 'cubeMeta') return { cube_source: 'live' as const };
        if (name === 'dataFreshness') return {};
        return [];
      }
      const v = (r as PromiseFulfilledResult<unknown>).value;
      if (v != null) return v;
      if (name === 'sqpVolume4w') return {} as Record<string, number>;
      if (name === 'cubeMeta') return { cube_source: 'live' as const };
      if (name === 'dataFreshness') return {};
      return [];
    }

    (async () => {
      try {
        // --- Priority loaders: UI renders after these complete ---
        const priorityLoaders: [string, () => Promise<unknown>][] = [
          ['cubeMeta', loadCubeMeta],
          ['dataFreshness', loadDataFreshnessFromCube],
          ['summary', loadSummaryFromCube],
          ['weeklyTrends', loadWeeklyTrendsFromCube],
          ['monthlyTrends', loadMonthlyTrendsFromCube],
          ['weeklyTrendsByAsin', loadWeeklyTrendsByAsinFromCube],
          ['monthlyTrendsByAsin', loadMonthlyTrendsByAsinFromCube],
          ['products', loadProductsFromCube],
          ['productCreatives', loadProductCreativesFromCube],
          ['experiments', loadExperimentsFromCube],
          ['adsSummary', loadAdsSummaryFromCube],
        ];

        const pResults = await Promise.allSettled(priorityLoaders.map(([, fn]) => fn()));
        if (cancelled) return;

        const cubeMeta = resolveLoader(pResults[0], 'cubeMeta') as { refreshed_at?: string; cube_source: 'preagg' | 'live' };
        const dataFreshness = resolveLoader(pResults[1], 'dataFreshness') as { ads_max_date?: string; performance_max_date?: string };
        const summary = resolveLoader(pResults[2], 'summary') as SummaryRow[];
        const weeklyTrends = resolveLoader(pResults[3], 'weeklyTrends') as TrendRow[];
        const monthlyTrends = resolveLoader(pResults[4], 'monthlyTrends') as TrendRow[];
        const weeklyTrendsByAsin = resolveLoader(pResults[5], 'weeklyTrendsByAsin') as TrendRowByAsin[];
        const monthlyTrendsByAsin = resolveLoader(pResults[6], 'monthlyTrendsByAsin') as TrendRowByAsin[];
        const products = resolveLoader(pResults[7], 'products') as ProductRow[];
        const productCreatives = resolveLoader(pResults[8], 'productCreatives') as ProductCreativeRow[];
        const experiments = resolveLoader(pResults[9], 'experiments') as ExperimentRow[];
        const adsSummary = resolveLoader(pResults[10], 'adsSummary') as Ads7dRow[];

        if (import.meta.env.DEV) {
          console.log('[useCubeData] Priority done — summary:', summary.length, 'weeklyTrends:', weeklyTrends.length, 'adsSummary:', adsSummary.length);
        }

        // Auto-retry if priority data is empty (Cube may have been restarting)
        if (!summary.length && !weeklyTrends.length && retryCount < 3) {
          console.warn(`[useCubeData] Priority data empty, retrying in 3s (attempt ${retryCount + 1}/3)`);
          setTimeout(() => { if (!cancelled) setRetryCount(c => c + 1); }, 3000);
          return;
        }

        const buildMeta = (s: SummaryRow[], df: typeof dataFreshness, cm: typeof cubeMeta) => ({
          refreshed_at: cm.refreshed_at,
          cube_source: cm.cube_source,
          data_freshness: df,
          ...(s?.[0] ? { date_ranges: { summary_7d: { start: s[0].period_start || '', end: s[0].period_end || '' } } } : {}),
        });

        const priorityData: Partial<DashboardData> = {
          summary,
          weekly_trends: weeklyTrends,
          monthly_trends: monthlyTrends,
          weekly_trends_by_asin: weeklyTrendsByAsin,
          monthly_trends_by_asin: monthlyTrendsByAsin,
          products,
          product_creatives: productCreatives,
          experiments,
          ads_7d_summary: adsSummary,
          negative_keywords: [],
          _meta: buildMeta(summary, dataFreshness, cubeMeta),
        };

        setData(priorityData);
        setLoading(false);

        // --- Background loaders: split to avoid browser connection pooling timeouts ---
        const lightLoaders: [string, () => Promise<unknown>][] = [
          ['changeLog', loadChangeLogFromCube],
          ['upcoming', loadUpcomingFromCube],
          ['peak', loadPeakFromCube],
          ['heroAsins', loadHeroAsinsFromCube],
          ['keywordProductMap', loadKeywordProductMapFromCube],
          ['learnings', loadLearningsFromCube],
          ['budgetHealth', loadBudgetHealthFromCube],
          ['drivers', loadDriversFromCube],
          ['experimentWeekly', loadExperimentWeeklyFromCube],
          ['sqpVolume4w', loadSqpVolume4wFromCube],
          ['experimentCampaigns', loadExperimentCampaignsFromCube],
          ['campaignSearchTerms', loadCampaignSearchTermsFromCube],
          ['experimentTemplates', loadExperimentTemplatesFromCube],
          ['holidays', loadAllHolidaysFromCube],
          ['coachDecisions', loadCoachDecisionsFromCube],
          ['coachTerms', loadCoachTermsFromCube],
          ['coachCampaigns', loadCoachCampaignsFromCube],
          ['experimentEvaluations', loadExperimentEvaluationsFromCube],
          ['keywordPredictions', loadPredictionsFromCube],
          ['brandStrength', loadBrandStrengthFromCube],
          ['phraseNegatives', loadPhraseNegativesFromCube],
          ['sqpCoverageWeeks', loadSqpCoverageWeeksFromCube],
          ['hotSignals', loadHotSignalsFromCube],
        ];

        const heavyLoaders: [string, () => Promise<unknown>][] = [
          ['actions', loadActionsFromCube],
          ['ads', loadAdsFromCube],
          ['sqp', loadSqpFromCube],
        ];

        // Run light loaders first so they don't get stuck behind heavy ones
        const bgResultsLight = await Promise.allSettled(lightLoaders.map(([, fn]) => fn()));
        if (cancelled) return;

        // Run heavy loaders SEQUENTIALLY to avoid overwhelming Cube API memory
        const bgResultsHeavy: PromiseSettledResult<unknown>[] = [];
        for (const [, fn] of heavyLoaders) {
          if (cancelled) return;
          const result = await Promise.allSettled([fn()]);
          bgResultsHeavy.push(result[0]);
        }
        if (cancelled) return;

        const changeLog = resolveLoader(bgResultsLight[0], 'changeLog') as ChangeLogRow[];
        const upcoming = resolveLoader(bgResultsLight[1], 'upcoming') as UpcomingEvent[];
        const peak = resolveLoader(bgResultsLight[2], 'peak') as PeakRow[];
        const heroAsins = resolveLoader(bgResultsLight[3], 'heroAsins') as HeroAsin[];
        const keywordProductMap = resolveLoader(bgResultsLight[4], 'keywordProductMap') as KeywordMapRow[];
        const learnings = resolveLoader(bgResultsLight[5], 'learnings') as LearningRow[];
        const budgetHealth = resolveLoader(bgResultsLight[6], 'budgetHealth') as BudgetHealthRow[];
        const drivers = resolveLoader(bgResultsLight[7], 'drivers') as DriverRow[];
        const experimentWeekly = resolveLoader(bgResultsLight[8], 'experimentWeekly') as ExperimentWeeklyRow[];
        const sqpVolume4w = resolveLoader(bgResultsLight[9], 'sqpVolume4w') as Record<string, number>;
        const experimentCampaigns = resolveLoader(bgResultsLight[10], 'experimentCampaigns') as ExperimentCampaignRow[];
        const campaignSearchTerms = resolveLoader(bgResultsLight[11], 'campaignSearchTerms') as CampaignSearchTermRow[];
        const experimentTemplates = resolveLoader(bgResultsLight[12], 'experimentTemplates') as ExperimentTemplateRow[];
        const holidays = resolveLoader(bgResultsLight[13], 'holidays') as HolidayRow[];
        const coachDecisions = resolveLoader(bgResultsLight[14], 'coachDecisions') as CoachDecisionRow[];
        const coachTerms = resolveLoader(bgResultsLight[15], 'coachTerms') as CoachTermRow[];
        const coachCampaigns = resolveLoader(bgResultsLight[16], 'coachCampaigns') as CoachCampaignRow[];
        const experimentEvaluations = resolveLoader(bgResultsLight[17], 'experimentEvaluations') as ExperimentEvaluationRow[];
        const keywordPredictions = resolveLoader(bgResultsLight[18], 'keywordPredictions') as StrategicPrediction[];
        const brandStrength = resolveLoader(bgResultsLight[19], 'brandStrength') as BrandStrengthWeeklyRow[];
        const phraseNegatives = resolveLoader(bgResultsLight[20], 'phraseNegatives') as PhraseNegativeRow[];
        const sqpCoverageWeeks = resolveLoader(bgResultsLight[21], 'sqpCoverageWeeks') as { week_start: string }[];
        const hotSignals = resolveLoader(bgResultsLight[22], 'hotSignals') as HotSignalRow[];

        const actions = resolveLoader(bgResultsHeavy[0], 'actions') as ActionRow[];
        const ads = resolveLoader(bgResultsHeavy[1], 'ads') as Ads7dRow[];
        const sqp = resolveLoader(bgResultsHeavy[2], 'sqp') as SqpWeeklyRow[];

        if (import.meta.env.DEV) {
          console.log('[useCubeData] Background done — ads:', ads.length, 'sqp:', sqp.length, 'decisions:', coachDecisions.length, 'actions:', coachTerms.length);
        }

        setData(prev => ({
          ...prev,
          actions,
          ads_7d: ads,
          sqp_weekly: sqp,
          sqp_coverage_weeks: sqpCoverageWeeks,
          change_log: changeLog,
          upcoming,
          peak,
          hero_asins: heroAsins,
          keyword_product_map: keywordProductMap,
          learnings,
          budget_health: budgetHealth,
          drivers,
          experiment_weekly: experimentWeekly,
          sqp_volume_4w: sqpVolume4w,
          experiment_campaigns: experimentCampaigns,
          campaign_search_terms: campaignSearchTerms,
          experiment_templates: experimentTemplates,
          holidays,
          coach_decisions: coachDecisions,
          coach_terms: coachTerms,
          coach_campaigns: coachCampaigns,
          experiment_evaluations: experimentEvaluations,
          keyword_predictions: keywordPredictions,
          brand_strength_weekly: brandStrength,
          coach_phrase_negatives: phraseNegatives,
          hot_signals: hotSignals,
          _meta: {
            ...prev._meta,
            queries_run: (prev._meta?.queries_run ?? 0) + lightLoaders.length + heavyLoaders.length,
            queries_failed: failedQueries.length,
            failed_queries: failedQueries,
          },
        }));
      } catch (e) {
        console.error('[useCubeData] load failed:', e);
        if (!cancelled) {
          setLoading(false);
          if (retryCount < 3) {
            console.warn(`[useCubeData] Load failed, retrying in 3s (attempt ${retryCount + 1}/3)`);
            setTimeout(() => { if (!cancelled) setRetryCount(c => c + 1); }, 3000);
          }
        }
      }
    })();
    return () => { cancelled = true; };
  }, [retryCount]); // eslint-disable-line react-hooks/exhaustive-deps

  return { data, loading, fromCube };
}
