/**
 * Cube.js data hook - fetches from Cube via @cubejs-client/core SDK.
 * Use when VITE_CUBE_API_URL is set. Overlays Cube data on top of JSON fallback.
 *
 * Loading strategy: priority loaders (summary, trends, products) complete first
 * so the UI renders immediately. Background loaders (ads, sqp, etc.) fill in after.
 */
import { useState, useEffect } from 'react';
import type { DatasetName } from './data/datasetTypes';
import type {
  Ads7dRow,
  SqpWeeklyRow,
  ChangeLogRow,
  UpcomingEvent,
  PeakRow,
  ExperimentWeeklyRow,
  ProductRow,
  CampaignSearchTermRow,
  CampaignSearchTermWeeklyRow,
  SummaryRow,
  TrendRow,
  DailyTrendRow,
  DailyTrendByAsinRow,
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
  CoachCrossSellRow,
  CoachActionRow,
  CoachCampaignRow,
  CoachStrategyRow,
  PlanAdsTargetRow,
  ExperimentEvaluationRow,
  StrategicPrediction,
  BrandStrengthWeeklyRow,
  PhraseNegativeRow,
  ProductCreativeRow,
  HotSignalRow,
  StorageCostRow,
  SupplyChainRow,
  PeakRelevanceRow,
  SupplyPORow,
  SupplyPaymentRow,
  SupplyShipmentRow,
  AsinOosDaysRow,
} from '../types';

// In dev, always try Cube via proxy even if env not loaded
const CUBE_API = import.meta.env.VITE_CUBE_API_URL || (import.meta.env.DEV ? 'http://localhost:4000' : '');

type CubeLoadResult = { data: unknown[]; lastRefreshTime?: string; usedPreAggregations?: Record<string, unknown> };

export async function cubeLoad(query: object): Promise<unknown[]> {
  const r = await cubeLoadWithMeta(query);
  return r.data;
}

export async function cubeLoadWithMeta(query: object, maxRetries = 20): Promise<CubeLoadResult> {
  if (!CUBE_API) return { data: [] };
  const url = `${CUBE_API}/cubejs-api/v1/load?query=${encodeURIComponent(JSON.stringify(query))}`;
  try {
    let retries = 0;
    while (retries < maxRetries) {
      const token = localStorage.getItem('dashboard_token');
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const res = await fetch(`${CUBE_API}/cubejs-api/v1/load`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ query }),
      });
      
      if (!res.ok) {
        const text = await res.text();
        if (res.status === 401 || res.status === 403 || text.includes('Authentication required') || text.includes('Invalid token') || text.includes('Invalid dev token')) {
          console.warn(`[cubeLoad] Authentication failed (${res.status}). Clearing token.`);
          localStorage.removeItem('dashboard_token');
          window.location.href = '/';
          break;
        }
        throw new Error(`Cube HTTP ${res.status}: ${text}`);
      }
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
    asin: r['Product.asin'] ? String(r['Product.asin']) : null,
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
      dimensions: ['Ads.campaignId', 'Ads.campaignName', 'Ads.campaignType', 'Ads.date', 'Product.asin', 'Product.productShortName', 'Product.parentName'],
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
      dimensions: ['Ads.campaignId', 'Ads.campaignName', 'Ads.campaignType', 'Ads.date', 'Product.asin', 'Product.productShortName', 'Product.parentName'],
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
    dimensions: ['Sqp.reportingDate', 'Sqp.asin', 'Sqp.searchQuery', 'Sqp.showRatePct', 'Sqp.estimatedOrganicRank', 'Sqp.organicRankZone', 'Sqp.searchQueryScore', 'Product.productShortName', 'Product.productType', 'Product.parentName'],
    timeDimensions: [{ dimension: 'Sqp.reportingDate', dateRange: 'Last 104 weeks' }],
    limit: 80000,
  });
  return (rows as Record<string, unknown>[]).map(r => {
    const rd = r['Sqp.reportingDate'];
    const weekStart = rd ? addDays(fmtDate(rd), -6) : '';
    return {
      product_type: String(r['Product.productType'] ?? ''),
      family_name: String(r['Product.parentName'] ?? ''),
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
    timeDimensions: [{ dimension: 'Sqp.reportingDate', dateRange: 'Last 104 weeks' }],
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
    dimensions: ['Holidays.holidayDate', 'Holidays.holidayName', 'Holidays.category', 'Holidays.preSeasonStart', 'Holidays.boostStart', 'Holidays.peakStart'],
    limit: 50,
  });
  const today = new Date().toISOString().slice(0, 10);
  const futureHolidays = (rows as Record<string, unknown>[])
    .filter(r => fmtDate(r['Holidays.holidayDate']) > today && String(r['Holidays.category'] ?? '') === 'gift_season')
    .sort((a, b) => fmtDate(a['Holidays.holidayDate'] as string).localeCompare(fmtDate(b['Holidays.holidayDate'] as string)));
  // Return ALL future holidays — PeakPage picks the first "real peak" via peak_relevance
  return futureHolidays.map(next => {
    const holidayDate = fmtDate(next['Holidays.holidayDate']);
    const preSeasonStart = fmtDate(next['Holidays.preSeasonStart']);
    const boostStart = fmtDate(next['Holidays.boostStart']) || preSeasonStart;
    const peakStart = fmtDate(next['Holidays.peakStart']) || boostStart;
    const peakEnd = addDays(holidayDate, -1);
    // 3 phases: PRE_SEASON (pre_season_start → boost_start-1), BOOST (boost_start → peak_start-1), PEAK (peak_start → holiday_date-1)
    let currentStage = 'PRE_SEASON';
    if (today >= peakEnd) currentStage = 'POST_PEAK';
    else if (today >= peakStart) currentStage = 'PEAK';
    else if (today >= boostStart) currentStage = 'PRE_PEAK_BOOST';
    else if (today >= preSeasonStart) currentStage = 'PRE_SEASON';
    return {
      holiday_name: String(next['Holidays.holidayName'] ?? ''),
      holiday_date: holidayDate,
      peak_start: peakStart,
      peak_end: peakEnd,
      readiness_start: preSeasonStart,
      pre_peak_start: preSeasonStart,
      boost_start: boostStart,
      current_stage: currentStage,
      days_until_peak_start: daysBetween(today, peakStart),
    };
  });
}

/** All holidays (past + future) for YoY phase comparison */
async function loadAllHolidaysFromCube(): Promise<HolidayRow[]> {
  const rows = await cubeLoad({
    dimensions: ['Holidays.holidayDate', 'Holidays.holidayName', 'Holidays.category', 'Holidays.preSeasonStart', 'Holidays.boostStart', 'Holidays.peakStart', 'Holidays.rampUpDays'],
    limit: 200,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    holiday_name: String(r['Holidays.holidayName'] ?? ''),
    holiday_date: fmtDate(r['Holidays.holidayDate']),
    pre_season_start: fmtDate(r['Holidays.preSeasonStart']),
    boost_start: fmtDate(r['Holidays.boostStart']) || fmtDate(r['Holidays.preSeasonStart']),
    peak_start: fmtDate(r['Holidays.peakStart']) || fmtDate(r['Holidays.boostStart']) || fmtDate(r['Holidays.preSeasonStart']),
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

/** StrategyCampaignTemplate → strategy_campaign_templates (campaign-creation recipes) */
async function loadStrategyCampaignTemplatesFromCube(): Promise<import('../types').StrategyCampaignTemplateRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'StrategyCampaignTemplate.strategyId', 'StrategyCampaignTemplate.campaignSeq',
      'StrategyCampaignTemplate.adFormat', 'StrategyCampaignTemplate.matchType',
      'StrategyCampaignTemplate.biddingStrategy', 'StrategyCampaignTemplate.bidMin',
      'StrategyCampaignTemplate.bidMax', 'StrategyCampaignTemplate.dailyBudget',
      'StrategyCampaignTemplate.topOfSearchPct', 'StrategyCampaignTemplate.productPagePct',
      'StrategyCampaignTemplate.namingHint', 'StrategyCampaignTemplate.isRequired',
    ],
    limit: 200,
  });
  const n = (v: unknown): number | null => (v === null || v === undefined || v === '' ? null : Number(v));
  return (rows as Record<string, unknown>[]).map(r => ({
    strategy_id: String(r['StrategyCampaignTemplate.strategyId'] ?? ''),
    campaign_seq: Number(r['StrategyCampaignTemplate.campaignSeq'] ?? 0),
    ad_format: String(r['StrategyCampaignTemplate.adFormat'] ?? ''),
    match_type: String(r['StrategyCampaignTemplate.matchType'] ?? ''),
    bidding_strategy: String(r['StrategyCampaignTemplate.biddingStrategy'] ?? ''),
    bid_min: n(r['StrategyCampaignTemplate.bidMin']),
    bid_max: n(r['StrategyCampaignTemplate.bidMax']),
    daily_budget: n(r['StrategyCampaignTemplate.dailyBudget']),
    top_of_search_pct: n(r['StrategyCampaignTemplate.topOfSearchPct']),
    product_page_pct: n(r['StrategyCampaignTemplate.productPagePct']),
    naming_hint: String(r['StrategyCampaignTemplate.namingHint'] ?? ''),
    is_required: Boolean(r['StrategyCampaignTemplate.isRequired']),
  }));
}

/** Product + CostsHistory → products */
async function loadProductsFromCube(): Promise<ProductRow[]> {
  const [productRows, costRows] = await Promise.all([
    cubeLoad({ dimensions: ['Product.asin', 'Product.productShortName', 'Product.productType', 'Product.parentName', 'Product.parentAsin', 'Product.packageQuantity', 'Product.manufactureDay', 'Product.shipmentDays', 'Product.packageCubicFeet', 'Product.manufUpfrontPercentage', 'Product.shareCartonInFamily', 'Product.listingPriceAmount', 'Product.sku'], limit: 5000 }),
    cubeLoad({ 
      dimensions: ['CostsHistory.asin', 'CostsHistory.costOfGoods', 'CostsHistory.shippingCost', 'CostsHistory.fbaCost', 'CostsHistory.totalCostPerUnit', 'CostsHistory.pickPackFee', 'CostsHistory.referralFee'], 
      filters: [{ member: 'CostsHistory.endDate', operator: 'notSet' }],
      limit: 5000 
    }),
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
      family_name: String(r['Product.parentName'] ?? ''),
      parent_asin: r['Product.parentAsin'] ? String(r['Product.parentAsin']) : null,
      parent_name: String(r['Product.parentName'] ?? ''),
      cogs: costs?.cogs ?? 0,
      shipping_cost: costs?.shipping ?? 0,
      fba_cost: costs?.fba ?? 0,
      total_cost_per_unit: costs?.total ?? 0,
      pick_pack_fee: costs?.pickPack ?? 0,
      referral_fee: costs?.referral ?? 0,
      package_quantity: r['Product.packageQuantity'] != null ? Number(r['Product.packageQuantity']) : null,
      manufacture_day: r['Product.manufactureDay'] != null ? Number(r['Product.manufactureDay']) : null,
      shipment_days: r['Product.shipmentDays'] != null ? Number(r['Product.shipmentDays']) : null,
      package_cubic_feet: r['Product.packageCubicFeet'] != null ? Number(r['Product.packageCubicFeet']) : null,
      manuf_upfront_percentage: r['Product.manufUpfrontPercentage'] != null ? Number(r['Product.manufUpfrontPercentage']) : null,
      share_carton_in_family: r['Product.shareCartonInFamily'] != null ? (r['Product.shareCartonInFamily'] === true || r['Product.shareCartonInFamily'] === 'true') : null,
      listing_price: r['Product.listingPriceAmount'] != null ? Number(r['Product.listingPriceAmount']) : null,
      sku: String(r['Product.sku'] ?? ''),
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
    if ((src === 'ads' || src === 'FACT_AMAZON_ADS') && iso) out.ads_max_date = iso;
    if ((src === 'perf' || src === 'FACT_AMAZON_PERFORMANCE_DAILY') && iso) out.performance_max_date = iso;
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
      'Summary.periodStart', 'Summary.periodEnd', 'Summary.units7d', 'Summary.colorHex',
    ],
    limit: 20,
  });
  const arr = Array.isArray(rows) ? rows : [];
  if (import.meta.env.DEV) {
    console.log('[useCubeData] Summary from Cube:', arr.length, 'rows', arr.length ? arr : '(empty - check Cube/Summary schema)');
  }
  return (arr as Record<string, unknown>[]).map(r => ({
    product_type: String(r['Summary.productType'] ?? ''),
    color_hex: String(r['Summary.colorHex'] ?? '#666666'),
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
      'CoachHotSignals.currentBid', 'CoachHotSignals.recommendedBid',
      'CoachHotSignals.keywordId', 'CoachHotSignals.keywordText',
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
    current_bid: r['CoachHotSignals.currentBid'] != null ? Number(r['CoachHotSignals.currentBid']) : null,
    recommended_bid: r['CoachHotSignals.recommendedBid'] != null ? Number(r['CoachHotSignals.recommendedBid']) : null,
    keyword_id: r['CoachHotSignals.keywordId'] ? String(r['CoachHotSignals.keywordId']) : null,
    keyword_text: r['CoachHotSignals.keywordText'] ? String(r['CoachHotSignals.keywordText']) : null,
  })).sort((a, b) => b.priority_score - a.priority_score);
}

/** StorageCost → storage_costs (weekly FBA+AWD storage by product family) */
async function loadStorageCostsFromCube(): Promise<StorageCostRow[]> {
  const rows = await cubeLoad({
    measures: ['StorageCost.totalStorageCost'],
    dimensions: ['StorageCost.weekStartDate', 'StorageCost.productType', 'StorageCost.asin'],
    limit: 5000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    week_start_date: fmtDate(r['StorageCost.weekStartDate']),
    product_type: String(r['StorageCost.productType'] ?? ''),
    asin: r['StorageCost.asin'] ? String(r['StorageCost.asin']) : undefined,
    weekly_storage_cost: Number(r['StorageCost.totalStorageCost'] ?? 0),
  }));
}

/** SupplyChain → supply_chain (per-ASIN supply chain health) */
async function loadSupplyChainFromCube(): Promise<SupplyChainRow[]> {
  const coreDims = [
    'SupplyChain.asin', 'SupplyChain.productShortName', 'SupplyChain.productType',
    'SupplyChain.sellableQty', 'SupplyChain.fbaStockQty', 'SupplyChain.awdStockQty', 'SupplyChain.inTransitQty', 'SupplyChain.mfrStockQty', 'SupplyChain.totalAvailableQty',
    'SupplyChain.dailyVelocity', 'SupplyChain.daysOfCoverage', 'SupplyChain.fbaDaysOfCoverage', 'SupplyChain.awdDaysOfCoverage',
    'SupplyChain.nextShipmentDate', 'SupplyChain.daysToNextShipment', 'SupplyChain.nextShipmentQty',
    'SupplyChain.awdTargetMin', 'SupplyChain.awdTargetMax',
    'SupplyChain.awdApprovedMin', 'SupplyChain.awdApprovedMax', 'SupplyChain.awdDiffPct',
  ];

  // Always load core data first (guaranteed to work)
  const rawRows = await cubeLoad({ dimensions: coreDims, limit: 500 }) as Record<string, unknown>[];

  // Try loading forecast dimensions separately (cubeLoad returns [] on error, never throws)
  const forecastMap: Record<string, { last30: number; last30Planned: number; next30: number; next31_60: number; next61_90: number }> = {};
  const fRows = await cubeLoad({
    dimensions: [
      'SupplyChain.asin',
      'SupplyChain.last30dSold', 'SupplyChain.last30dPlanned',
      'SupplyChain.next30dPlanned', 'SupplyChain.next3160dPlanned', 'SupplyChain.next6190dPlanned',
    ],
    limit: 500,
  }) as Record<string, unknown>[];
  if (fRows.length > 0) {
    fRows.forEach(r => {
      const asin = String(r['SupplyChain.asin'] ?? '');
      if (asin) forecastMap[asin] = {
        last30: Number(r['SupplyChain.last30dSold'] ?? 0),
        last30Planned: Number(r['SupplyChain.last30dPlanned'] ?? 0),
        next30: Number(r['SupplyChain.next30dPlanned'] ?? 0),
        next31_60: Number(r['SupplyChain.next3160dPlanned'] ?? 0),
        next61_90: Number(r['SupplyChain.next6190dPlanned'] ?? 0),
      };
    });
  }

  return rawRows.map(r => {
    const asin = String(r['SupplyChain.asin'] ?? '');
    const fc = forecastMap[asin];
    return {
      asin,
      product_short_name: String(r['SupplyChain.productShortName'] ?? ''),
      product_type: String(r['SupplyChain.productType'] ?? ''),
      sellable_qty: Number(r['SupplyChain.sellableQty'] ?? 0),
      fba_stock_qty: Number(r['SupplyChain.fbaStockQty'] ?? 0),
      awd_stock_qty: Number(r['SupplyChain.awdStockQty'] ?? 0),
      in_transit_qty: Number(r['SupplyChain.inTransitQty'] ?? 0),
      mfr_stock_qty: Number(r['SupplyChain.mfrStockQty'] ?? 0),
      total_available_qty: Number(r['SupplyChain.totalAvailableQty'] ?? 0),
      daily_velocity: Number(r['SupplyChain.dailyVelocity'] ?? 0),
      days_of_coverage: r['SupplyChain.daysOfCoverage'] != null ? Number(r['SupplyChain.daysOfCoverage']) : null,
      fba_days_of_coverage: r['SupplyChain.fbaDaysOfCoverage'] != null ? Number(r['SupplyChain.fbaDaysOfCoverage']) : null,
      awd_days_of_coverage: r['SupplyChain.awdDaysOfCoverage'] != null ? Number(r['SupplyChain.awdDaysOfCoverage']) : null,
      next_shipment_date: r['SupplyChain.nextShipmentDate'] ? fmtDate(r['SupplyChain.nextShipmentDate']) : null,
      days_to_next_shipment: r['SupplyChain.daysToNextShipment'] != null ? Number(r['SupplyChain.daysToNextShipment']) : null,
      next_shipment_qty: r['SupplyChain.nextShipmentQty'] != null ? Number(r['SupplyChain.nextShipmentQty']) : null,
      awd_target_min: r['SupplyChain.awdTargetMin'] != null ? Number(r['SupplyChain.awdTargetMin']) : null,
      awd_target_max: r['SupplyChain.awdTargetMax'] != null ? Number(r['SupplyChain.awdTargetMax']) : null,
      awd_approved_min: r['SupplyChain.awdApprovedMin'] != null ? Number(r['SupplyChain.awdApprovedMin']) : null,
      awd_approved_max: r['SupplyChain.awdApprovedMax'] != null ? Number(r['SupplyChain.awdApprovedMax']) : null,
      awd_diff_pct: r['SupplyChain.awdDiffPct'] != null ? Number(r['SupplyChain.awdDiffPct']) : null,
      last_30d_sold: fc?.last30 ?? 0,
      last_30d_planned: fc?.last30Planned ?? 0,
      next_30d_planned: fc?.next30 ?? 0,
      next_31_60d_planned: fc?.next31_60 ?? 0,
      next_61_90d_planned: fc?.next61_90 ?? 0,
    };
  });
}

/** PurchaseOrdersDashboard → supply_pos */
async function loadSupplyPOsFromCube(): Promise<SupplyPORow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'PurchaseOrdersDashboard.purchaseOrderId', 'PurchaseOrdersDashboard.orderDate',
      'PurchaseOrdersDashboard.expectedReadyDate',
      'PurchaseOrdersDashboard.manufacturerName', 'PurchaseOrdersDashboard.productName',
      'PurchaseOrdersDashboard.productAsin', 'PurchaseOrdersDashboard.productId', 'PurchaseOrdersDashboard.quantity',
      'PurchaseOrdersDashboard.readyQuantity',
      'PurchaseOrdersDashboard.totalAmountDim', 'PurchaseOrdersDashboard.totalPaidDim',
      'PurchaseOrdersDashboard.unpaidManufacturer', 'PurchaseOrdersDashboard.totalShipmentCost',
      'PurchaseOrdersDashboard.paidShipmentCost', 'PurchaseOrdersDashboard.unpaidShipment',
      'PurchaseOrdersDashboard.totalUnpaidDim', 'PurchaseOrdersDashboard.totalQuantityShipped',
      'PurchaseOrdersDashboard.remainingToShip', 'PurchaseOrdersDashboard.estimatedShipmentCost',
      'PurchaseOrdersDashboard.paymentStatus', 'PurchaseOrdersDashboard.isOpen',
      'PurchaseOrdersDashboard.currency', 'PurchaseOrdersDashboard.notes',
    ],
    limit: 500,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    purchase_order_id: String(r['PurchaseOrdersDashboard.purchaseOrderId'] ?? ''),
    order_date: fmtDate(r['PurchaseOrdersDashboard.orderDate']),
    expected_ready_date: r['PurchaseOrdersDashboard.expectedReadyDate'] ? fmtDate(r['PurchaseOrdersDashboard.expectedReadyDate']) : null,
    manufacturer_name: String(r['PurchaseOrdersDashboard.manufacturerName'] ?? ''),
    product_name: String(r['PurchaseOrdersDashboard.productName'] ?? ''),
    product_asin: String(r['PurchaseOrdersDashboard.productAsin'] ?? ''),
    product_id: String(r['PurchaseOrdersDashboard.productId'] ?? ''),
    quantity: Number(r['PurchaseOrdersDashboard.quantity'] ?? 0),
    ready_quantity: Number(r['PurchaseOrdersDashboard.readyQuantity'] ?? 0),
    total_amount: Number(r['PurchaseOrdersDashboard.totalAmountDim'] ?? 0),
    total_paid: Number(r['PurchaseOrdersDashboard.totalPaidDim'] ?? 0),
    unpaid_manufacturer: Number(r['PurchaseOrdersDashboard.unpaidManufacturer'] ?? 0),
    total_shipment_cost: Number(r['PurchaseOrdersDashboard.totalShipmentCost'] ?? 0),
    paid_shipment_cost: Number(r['PurchaseOrdersDashboard.paidShipmentCost'] ?? 0),
    unpaid_shipment: Number(r['PurchaseOrdersDashboard.unpaidShipment'] ?? 0),
    total_unpaid: Number(r['PurchaseOrdersDashboard.totalUnpaidDim'] ?? 0),
    total_quantity_shipped: Number(r['PurchaseOrdersDashboard.totalQuantityShipped'] ?? 0),
    remaining_to_ship: Number(r['PurchaseOrdersDashboard.remainingToShip'] ?? 0),
    estimated_shipment_cost: r['PurchaseOrdersDashboard.estimatedShipmentCost'] != null ? Number(r['PurchaseOrdersDashboard.estimatedShipmentCost']) : null,
    payment_status: String(r['PurchaseOrdersDashboard.paymentStatus'] ?? ''),
    is_open: r['PurchaseOrdersDashboard.isOpen'] === true || r['PurchaseOrdersDashboard.isOpen'] === 'true',
    currency: String(r['PurchaseOrdersDashboard.currency'] ?? 'USD'),
    notes: r['PurchaseOrdersDashboard.notes'] ? String(r['PurchaseOrdersDashboard.notes']) : null,
  }));
}

/** VendorPaymentsDashboard → supply_payments (aggregated by date/vendor/payment_id) */
async function loadSupplyPaymentsFromCube(): Promise<SupplyPaymentRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'VendorPaymentsDashboard.paymentId',
      'VendorPaymentsDashboard.paymentDate', 'VendorPaymentsDashboard.paymentAmount',
      'VendorPaymentsDashboard.bankFee', 'VendorPaymentsDashboard.totalAmountDim',
      'VendorPaymentsDashboard.currency',
      'VendorPaymentsDashboard.paymentMethod', 'VendorPaymentsDashboard.vendorName',
      'VendorPaymentsDashboard.purchaseOrderIds', 'VendorPaymentsDashboard.shipmentIds',
      'VendorPaymentsDashboard.notes',
    ],
    limit: 1000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    payment_id: String(r['VendorPaymentsDashboard.paymentId'] ?? ''),
    payment_date: fmtDate(r['VendorPaymentsDashboard.paymentDate']),
    payment_amount: Number(r['VendorPaymentsDashboard.paymentAmount'] ?? 0),
    bank_fee: Number(r['VendorPaymentsDashboard.bankFee'] ?? 0),
    total_amount: Number(r['VendorPaymentsDashboard.totalAmountDim'] ?? 0),
    currency: String(r['VendorPaymentsDashboard.currency'] ?? 'USD'),
    payment_method: String(r['VendorPaymentsDashboard.paymentMethod'] ?? ''),
    vendor_name: String(r['VendorPaymentsDashboard.vendorName'] ?? ''),
    purchase_order_id: r['VendorPaymentsDashboard.purchaseOrderIds'] ? String(r['VendorPaymentsDashboard.purchaseOrderIds']) : null,
    shipment_id: r['VendorPaymentsDashboard.shipmentIds'] ? String(r['VendorPaymentsDashboard.shipmentIds']) : null,
    notes: r['VendorPaymentsDashboard.notes'] ? String(r['VendorPaymentsDashboard.notes']) : null,
  }));
}

/** ShipmentsDashboard → supply_shipments */
async function loadSupplyShipmentsFromCube(): Promise<SupplyShipmentRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'ShipmentsDashboard.shipmentId', 'ShipmentsDashboard.shipmentDate',
      'ShipmentsDashboard.estimatedArrivalDate', 'ShipmentsDashboard.trackingNumber',
      'ShipmentsDashboard.shipmentType', 'ShipmentsDashboard.totalQuantity',
      'ShipmentsDashboard.costShipped', 'ShipmentsDashboard.isPaid',
      'ShipmentsDashboard.paidDate', 'ShipmentsDashboard.shipmentStatus',
      'ShipmentsDashboard.notes', 'ShipmentsDashboard.lineCount',
      'ShipmentsDashboard.totalAllocatedCost', 'ShipmentsDashboard.totalQuantityShipped',
      'ShipmentsDashboard.productsList', 'ShipmentsDashboard.unpaidToShipment',
      'ShipmentsDashboard.isOpen',
    ],
    limit: 500,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    shipment_id: String(r['ShipmentsDashboard.shipmentId'] ?? ''),
    shipment_date: fmtDate(r['ShipmentsDashboard.shipmentDate']),
    estimated_arrival_date: r['ShipmentsDashboard.estimatedArrivalDate'] ? fmtDate(r['ShipmentsDashboard.estimatedArrivalDate']) : null,
    tracking_number: r['ShipmentsDashboard.trackingNumber'] ? String(r['ShipmentsDashboard.trackingNumber']) : null,
    shipment_type: String(r['ShipmentsDashboard.shipmentType'] ?? ''),
    total_quantity: Number(r['ShipmentsDashboard.totalQuantity'] ?? 0),
    cost_shipped: Number(r['ShipmentsDashboard.costShipped'] ?? 0),
    is_paid: r['ShipmentsDashboard.isPaid'] === true || r['ShipmentsDashboard.isPaid'] === 'true',
    paid_date: r['ShipmentsDashboard.paidDate'] ? fmtDate(r['ShipmentsDashboard.paidDate']) : null,
    shipment_status: String(r['ShipmentsDashboard.shipmentStatus'] ?? ''),
    notes: r['ShipmentsDashboard.notes'] ? String(r['ShipmentsDashboard.notes']) : null,
    line_count: Number(r['ShipmentsDashboard.lineCount'] ?? 0),
    total_allocated_cost: Number(r['ShipmentsDashboard.totalAllocatedCost'] ?? 0),
    total_quantity_shipped: Number(r['ShipmentsDashboard.totalQuantityShipped'] ?? 0),
    products_list: String(r['ShipmentsDashboard.productsList'] ?? ''),
    unpaid_to_shipment: Number(r['ShipmentsDashboard.unpaidToShipment'] ?? 0),
    is_open: r['ShipmentsDashboard.isOpen'] === true || r['ShipmentsDashboard.isOpen'] === 'true',
  }));
}

/** PeakRelevance → peak_relevance (per family per holiday) */
async function loadPeakRelevanceFromCube(): Promise<PeakRelevanceRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'PeakRelevance.holidayName', 'PeakRelevance.holidayDate',
      'PeakRelevance.family', 'PeakRelevance.isRelevantPeak',
      'PeakRelevance.confidence', 'PeakRelevance.coachRecommendation',
      'PeakRelevance.reason', 'PeakRelevance.ordersChangePct',
      'PeakRelevance.unitsChangePct', 'PeakRelevance.salesChangePct',
      'PeakRelevance.netRoasDelta', 'PeakRelevance.baselineAvgDailyOrders',
      'PeakRelevance.peakAvgDailyOrders', 'PeakRelevance.baselineNetRoas',
      'PeakRelevance.peakNetRoas',
    ],
    limit: 5000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    holiday_name: String(r['PeakRelevance.holidayName'] ?? ''),
    holiday_date: fmtDate(r['PeakRelevance.holidayDate']),
    family: String(r['PeakRelevance.family'] ?? ''),
    is_relevant_peak: r['PeakRelevance.isRelevantPeak'] === true || r['PeakRelevance.isRelevantPeak'] === 'true',
    confidence: String(r['PeakRelevance.confidence'] ?? ''),
    coach_recommendation: String(r['PeakRelevance.coachRecommendation'] ?? ''),
    reason: String(r['PeakRelevance.reason'] ?? ''),
    orders_change_pct: r['PeakRelevance.ordersChangePct'] != null ? Number(r['PeakRelevance.ordersChangePct']) : null,
    units_change_pct: r['PeakRelevance.unitsChangePct'] != null ? Number(r['PeakRelevance.unitsChangePct']) : null,
    sales_change_pct: r['PeakRelevance.salesChangePct'] != null ? Number(r['PeakRelevance.salesChangePct']) : null,
    net_roas_delta: r['PeakRelevance.netRoasDelta'] != null ? Number(r['PeakRelevance.netRoasDelta']) : null,
    baseline_avg_daily_orders: r['PeakRelevance.baselineAvgDailyOrders'] != null ? Number(r['PeakRelevance.baselineAvgDailyOrders']) : null,
    peak_avg_daily_orders: r['PeakRelevance.peakAvgDailyOrders'] != null ? Number(r['PeakRelevance.peakAvgDailyOrders']) : null,
    baseline_net_roas: r['PeakRelevance.baselineNetRoas'] != null ? Number(r['PeakRelevance.baselineNetRoas']) : null,
    peak_net_roas: r['PeakRelevance.peakNetRoas'] != null ? Number(r['PeakRelevance.peakNetRoas']) : null,
  }));
}

/** FamilyOccasionMap → family_occasions (seasonal detection per family) */
async function loadFamilyOccasionsFromCube(): Promise<import('../types').FamilyOccasionRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'FamilyOccasionMap.parentName', 'FamilyOccasionMap.occasion',
      'FamilyOccasionMap.liftRatio', 'FamilyOccasionMap.peakDailyOrders',
      'FamilyOccasionMap.offSeasonDailyOrders', 'FamilyOccasionMap.rankByLift',
      'FamilyOccasionMap.isPrimary', 'FamilyOccasionMap.isOverride',
    ],
    limit: 500,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    parent_name: String(r['FamilyOccasionMap.parentName'] ?? ''),
    occasion: String(r['FamilyOccasionMap.occasion'] ?? ''),
    lift_ratio: Number(r['FamilyOccasionMap.liftRatio'] ?? 0),
    peak_daily_orders: Number(r['FamilyOccasionMap.peakDailyOrders'] ?? 0),
    off_season_daily_orders: Number(r['FamilyOccasionMap.offSeasonDailyOrders'] ?? 0),
    rank_by_lift: Number(r['FamilyOccasionMap.rankByLift'] ?? 0),
    is_primary: r['FamilyOccasionMap.isPrimary'] === true || r['FamilyOccasionMap.isPrimary'] === 'true',
    is_override: r['FamilyOccasionMap.isOverride'] === true || r['FamilyOccasionMap.isOverride'] === 'true',
  }));
}

/** WeeklyTrends → weekly_trends (via UnifiedPerformance) */
async function loadWeeklyTrendsFromCube(): Promise<TrendRow[]> {
  const rows = await cubeLoad({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.adCost', 'UnifiedPerformance.cogs', 'UnifiedPerformance.netProfit', 'UnifiedPerformance.orders', 'UnifiedPerformance.units', 'UnifiedPerformance.clicks', 'UnifiedPerformance.sessions', 'UnifiedPerformance.impressions', 'UnifiedPerformance.netRoas', 'UnifiedPerformance.organicPct', 'UnifiedPerformance.tacos', 'UnifiedPerformance.npPerUnit'],
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
    impressions: Number(r['UnifiedPerformance.impressions'] ?? 0),
    net_roas: Number(r['UnifiedPerformance.netRoas'] ?? 0),
    organic_pct: Number(r['UnifiedPerformance.organicPct'] ?? 0),
    tacos: Number(r['UnifiedPerformance.tacos'] ?? 0),
    np_per_unit: Number(r['UnifiedPerformance.npPerUnit'] ?? 0),
  }));
}

/** MonthlyTrends → monthly_trends (via UnifiedPerformance) */
async function loadMonthlyTrendsFromCube(): Promise<TrendRow[]> {
  const rows = await cubeLoad({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.adCost', 'UnifiedPerformance.cogs', 'UnifiedPerformance.netProfit', 'UnifiedPerformance.orders', 'UnifiedPerformance.units', 'UnifiedPerformance.clicks', 'UnifiedPerformance.sessions', 'UnifiedPerformance.impressions', 'UnifiedPerformance.netRoas', 'UnifiedPerformance.organicPct', 'UnifiedPerformance.tacos', 'UnifiedPerformance.npPerUnit'],
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
    impressions: Number(r['UnifiedPerformance.impressions'] ?? 0),
    net_roas: Number(r['UnifiedPerformance.netRoas'] ?? 0),
    organic_pct: Number(r['UnifiedPerformance.organicPct'] ?? 0),
    tacos: Number(r['UnifiedPerformance.tacos'] ?? 0),
    np_per_unit: Number(r['UnifiedPerformance.npPerUnit'] ?? 0),
  }));
}

/** DailyTrends → daily_trends (via UnifiedPerformance, last 18 months by family × date) */
async function loadDailyTrendsFromCube(): Promise<DailyTrendRow[]> {
  const rows = await cubeLoad({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.adCost', 'UnifiedPerformance.cogs', 'UnifiedPerformance.orders', 'UnifiedPerformance.units', 'UnifiedPerformance.clicks', 'UnifiedPerformance.sessions', 'UnifiedPerformance.impressions'],
    dimensions: ['UnifiedPerformance.family', 'UnifiedPerformance.date'],
    timeDimensions: [{ dimension: 'UnifiedPerformance.date', dateRange: [(() => { const d = new Date(); d.setMonth(d.getMonth() - 18); return d.toISOString().slice(0, 10); })(), new Date().toISOString().slice(0, 10)] }],
    limit: 5000,
  });
  const result = (rows as Record<string, unknown>[]).map(r => ({
    product_type: String(r['UnifiedPerformance.family'] ?? ''),
    date: fmtDate(r['UnifiedPerformance.date']),
    sales: Number(r['UnifiedPerformance.sales'] ?? 0),
    orders: Number(r['UnifiedPerformance.orders'] ?? 0),
    units: Number(r['UnifiedPerformance.units'] ?? 0),
    ad_cost: Number(r['UnifiedPerformance.adCost'] ?? 0),
    cogs: Number(r['UnifiedPerformance.cogs'] ?? 0),
    net_profit: Number(r['UnifiedPerformance.sales'] ?? 0) - Number(r['UnifiedPerformance.adCost'] ?? 0) - Number(r['UnifiedPerformance.cogs'] ?? 0),
    clicks: Number(r['UnifiedPerformance.clicks'] ?? 0),
    sessions: Number(r['UnifiedPerformance.sessions'] ?? 0),
    impressions: Number(r['UnifiedPerformance.impressions'] ?? 0),
  })).filter(r => r.date);
  return result;
}

/** WeeklyTrendsByAsin → weekly_trends_by_asin (via UnifiedPerformance) */
async function loadWeeklyTrendsByAsinFromCube(): Promise<TrendRowByAsin[]> {
  const rows = await cubeLoad({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.adCost', 'UnifiedPerformance.cogs', 'UnifiedPerformance.netProfit', 'UnifiedPerformance.orders', 'UnifiedPerformance.units', 'UnifiedPerformance.clicks', 'UnifiedPerformance.sessions', 'UnifiedPerformance.impressions', 'UnifiedPerformance.netRoas', 'UnifiedPerformance.organicPct', 'UnifiedPerformance.tacos', 'UnifiedPerformance.npPerUnit'],
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
    impressions: Number(r['UnifiedPerformance.impressions'] ?? 0),
    net_roas: Number(r['UnifiedPerformance.netRoas'] ?? 0),
    organic_pct: Number(r['UnifiedPerformance.organicPct'] ?? 0),
    tacos: Number(r['UnifiedPerformance.tacos'] ?? 0),
    np_per_unit: Number(r['UnifiedPerformance.npPerUnit'] ?? 0),
  }));
}

/**
 * DailyTrendsByAsin → daily_trends_by_asin (via UnifiedPerformance, last 400 days by asin × date).
 * Powers the Home Brief: true per-product P&L + organic_units. 400d covers the 30-day window and
 * its prior-30-day baseline, plus last year's same season for the peak-anchored baseline.
 */
async function loadDailyTrendsByAsinFromCube(): Promise<DailyTrendByAsinRow[]> {
  const start = (() => { const d = new Date(); d.setDate(d.getDate() - 400); return d.toISOString().slice(0, 10); })();
  const rows = await cubeLoad({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.adCost', 'UnifiedPerformance.cogs', 'UnifiedPerformance.netProfit', 'UnifiedPerformance.orders', 'UnifiedPerformance.units', 'UnifiedPerformance.organicUnits', 'UnifiedPerformance.adOrders', 'UnifiedPerformance.clicks', 'UnifiedPerformance.sessions', 'UnifiedPerformance.impressions'],
    dimensions: ['UnifiedPerformance.family', 'UnifiedPerformance.asin', 'UnifiedPerformance.productShortName', 'UnifiedPerformance.date'],
    timeDimensions: [{ dimension: 'UnifiedPerformance.date', dateRange: [start, new Date().toISOString().slice(0, 10)] }],
    limit: 50000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    product_type: String(r['UnifiedPerformance.family'] ?? ''),
    asin: String(r['UnifiedPerformance.asin'] ?? ''),
    product_short_name: String(r['UnifiedPerformance.productShortName'] ?? ''),
    date: fmtDate(r['UnifiedPerformance.date']),
    sales: Number(r['UnifiedPerformance.sales'] ?? 0),
    ad_cost: Number(r['UnifiedPerformance.adCost'] ?? 0),
    cogs: Number(r['UnifiedPerformance.cogs'] ?? 0),
    net_profit: Number(r['UnifiedPerformance.netProfit'] ?? 0),
    orders: Number(r['UnifiedPerformance.orders'] ?? 0),
    units: Number(r['UnifiedPerformance.units'] ?? 0),
    organic_units: Number(r['UnifiedPerformance.organicUnits'] ?? 0),
    ad_orders: Number(r['UnifiedPerformance.adOrders'] ?? 0),
    clicks: Number(r['UnifiedPerformance.clicks'] ?? 0),
    sessions: Number(r['UnifiedPerformance.sessions'] ?? 0),
    impressions: Number(r['UnifiedPerformance.impressions'] ?? 0),
  })).filter(r => r.date);
}

/** MonthlyTrendsByAsin → monthly_trends_by_asin (via UnifiedPerformance) */
async function loadMonthlyTrendsByAsinFromCube(): Promise<TrendRowByAsin[]> {
  const rows = await cubeLoad({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.adCost', 'UnifiedPerformance.cogs', 'UnifiedPerformance.netProfit', 'UnifiedPerformance.orders', 'UnifiedPerformance.units', 'UnifiedPerformance.clicks', 'UnifiedPerformance.sessions', 'UnifiedPerformance.impressions', 'UnifiedPerformance.netRoas', 'UnifiedPerformance.organicPct', 'UnifiedPerformance.tacos', 'UnifiedPerformance.npPerUnit'],
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
    impressions: Number(r['UnifiedPerformance.impressions'] ?? 0),
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
    else if (pn.includes('Bunny')) product_type = 'Bunny';
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
      net_roas: r['ExperimentTermRecommendations.adsNetRoas'] != null ? Number(r['ExperimentTermRecommendations.adsNetRoas']) : null,
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
      if (pn.includes('Bunny')) return 'Bunny';
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
    net_roas_60d: r['ExperimentTermRecommendations.adsNetRoas'] != null ? Number(r['ExperimentTermRecommendations.adsNetRoas']) : null,
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

/** Ads → campaign_search_terms_weekly (term-level weekly buckets for sparklines). */
async function loadCampaignSearchTermsWeeklyFromCube(): Promise<CampaignSearchTermWeeklyRow[]> {
  // Group by the Sunday-aligned Ads.weekStart dimension (DATE_TRUNC WEEK(SUNDAY)) to match
  // the rest of the app's weeks (getWeekStart / weeks4w). Cube's granularity:'week' is
  // Monday-aligned and would never match the Sunday-based trend axes.
  const rows = await cubeLoad({
    measures: ['Ads.spend', 'Ads.grossProfit'],
    dimensions: ['Ads.campaignId', 'Ads.searchTerm', 'Ads.weekStart'],
    timeDimensions: [{ dimension: 'Ads.date', dateRange: 'Last 90 days' }],
    filters: [{ member: 'Ads.spend', operator: 'gt', values: ['0'] }],
    limit: 100000,
  });
  return (rows as Record<string, unknown>[]).map(r => {
    const wk = r['Ads.weekStart'] ?? r['Ads.date'];
    return {
      campaign_id: String(r['Ads.campaignId'] ?? ''),
      search_term: r['Ads.searchTerm'] ? String(r['Ads.searchTerm']) : '',
      week_start: wk ? fmtDate(wk) : '',
      spend: Number(r['Ads.spend'] ?? 0),
      gross_profit: r['Ads.grossProfit'] != null ? Number(r['Ads.grossProfit']) : 0,
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
      // Display: research rank + top-spend source targeting
      'AdsCoachDecision.researchRank', 'AdsCoachDecision.sourceKeyword',
      'AdsCoachDecision.sourceKeywordMatchType',
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
      research_rank: nul('AdsCoachDecision.researchRank'),
      source_keyword: r['AdsCoachDecision.sourceKeyword'] != null ? String(r['AdsCoachDecision.sourceKeyword']) : null,
      source_keyword_match_type: r['AdsCoachDecision.sourceKeywordMatchType'] != null ? String(r['AdsCoachDecision.sourceKeywordMatchType']) : null,
    };
  });
}

/** AdsCoachCrossSell → coach_cross_sell (self-brand co-purchase affinity gaps) */
async function loadCrossSellFromCube(): Promise<CoachCrossSellRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'AdsCoachCrossSell.targetAsin', 'AdsCoachCrossSell.advertiseAsin',
      'AdsCoachCrossSell.targetName', 'AdsCoachCrossSell.advertiseName',
      'AdsCoachCrossSell.targetParent', 'AdsCoachCrossSell.confidence',
    ],
    measures: ['AdsCoachCrossSell.crossOrders30d', 'AdsCoachCrossSell.crossSales30d'],
    order: { 'AdsCoachCrossSell.crossOrders30d': 'desc' },
    limit: 5000,
  });
  return (rows as Record<string, unknown>[]).map(r => {
    const sn = (k: string) => (r[k] != null ? String(r[k]) : null);
    return {
      target_asin: String(r['AdsCoachCrossSell.targetAsin'] ?? ''),
      advertise_asin: String(r['AdsCoachCrossSell.advertiseAsin'] ?? ''),
      target_name: sn('AdsCoachCrossSell.targetName'),
      advertise_name: sn('AdsCoachCrossSell.advertiseName'),
      target_parent: sn('AdsCoachCrossSell.targetParent'),
      cross_orders_30d: Number(r['AdsCoachCrossSell.crossOrders30d'] ?? 0),
      cross_sales_30d: Number(r['AdsCoachCrossSell.crossSales30d'] ?? 0),
      confidence: String(r['AdsCoachCrossSell.confidence'] ?? ''),
    };
  });
}

async function loadCoachActionsFromCube(): Promise<CoachActionRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'AdsCoachActions.campaignId', 'AdsCoachActions.campaignName', 'AdsCoachActions.campaignType',
      'AdsCoachActions.adGroupId',
      'AdsCoachActions.searchTerm', 'AdsCoachActions.asin',
      'AdsCoachActions.productShortName', 'AdsCoachActions.parentName',
      'AdsCoachActions.experimentName', 'AdsCoachActions.strategyId', 'AdsCoachActions.strategyName',
      'AdsCoachActions.adsSpend4w', 'AdsCoachActions.adsOrders4w', 'AdsCoachActions.adsClicks4w',
      'AdsCoachActions.adsImpressions4w', 'AdsCoachActions.adsClicks1w', 'AdsCoachActions.adsImpressions1w',
      'AdsCoachActions.adsSpend1w', 'AdsCoachActions.adsCpc1w',
      'AdsCoachActions.adsSales4w', 'AdsCoachActions.adsRoas4w', 'AdsCoachActions.adsCpc4w', 'AdsCoachActions.adsCvrPct4w',
      'AdsCoachActions.adsNetRoas4w', 'AdsCoachActions.adsNetProfit4w', 'AdsCoachActions.marginPerUnit',
      'AdsCoachActions.termSpend4w', 'AdsCoachActions.termOrders4w',
      'AdsCoachActions.termCampaignCount', 'AdsCoachActions.termSellingCampaigns',
      'AdsCoachActions.spendSharePct', 'AdsCoachActions.ordersSharePct',
      'AdsCoachActions.sqpOrders4w',
      'AdsCoachActions.targeting', 'AdsCoachActions.keywordId',
      'AdsCoachActions.targetNetRoas8w', 'AdsCoachActions.targetClicks8w',
      'AdsCoachActions.targetOrders8w', 'AdsCoachActions.targetSpend8w',
      'AdsCoachActions.currentBid', 'AdsCoachActions.recommendedBid', 'AdsCoachActions.bidChangePct',
      'AdsCoachActions.matchType',

      // Unified action fields
      'AdsCoachActions.actionId', 'AdsCoachActions.decisionBranchId', 'AdsCoachActions.actionType',
      'AdsCoachActions.action', 'AdsCoachActions.priorityScore',
      'AdsCoachActions.confidence', 'AdsCoachActions.reason',
      'AdsCoachActions.actionExplanation', 'AdsCoachActions.decisionTrace',

      'AdsCoachActions.heroAsin', 'AdsCoachActions.heroProductName', 'AdsCoachActions.isHeroMatch',
      'AdsCoachActions.heroNetRoas', 'AdsCoachActions.heroTotalOrders',
      'AdsCoachActions.coachMode', 'AdsCoachActions.activeOccasion', 'AdsCoachActions.currentPhase',
      'AdsCoachActions.ppDays', 'AdsCoachActions.ppTargetNetRoas', 'AdsCoachActions.ppTargetSpend', 'AdsCoachActions.ppTargetOrders',
      // Cooldown v2: placement & pre-peak comparison
      'AdsCoachActions.tosPct', 'AdsCoachActions.productPagePct', 'AdsCoachActions.b2bPct',
      'AdsCoachActions.prePeakBid', 'AdsCoachActions.prePeakTosPct', 'AdsCoachActions.prePeakPpPct',
      'AdsCoachActions.prePeakB2bPct', 'AdsCoachActions.prePeakAvgCpc', 'AdsCoachActions.lastDayCpc',
      'AdsCoachActions.currentBudget', 'AdsCoachActions.prePeakBudget', 'AdsCoachActions.recommendedBudget',
      'AdsCoachActions.ppCampaignNetRoas',
      // Strategic task
      'AdsCoachActions.strategicTask',
      'AdsCoachActions.adsSignal',
      // ROAS windows + SQP context
      'AdsCoachActions.adsNetRoas3d', 'AdsCoachActions.adsOrders3d',
      'AdsCoachActions.adsNetRoas1w', 'AdsCoachActions.adsOrders1w',
      'AdsCoachActions.lyNetRoas', 'AdsCoachActions.lyOrders',
      'AdsCoachActions.lySpend', 'AdsCoachActions.lyClicks', 'AdsCoachActions.lyCpc',
      'AdsCoachActions.q4PeakNetRoas', 'AdsCoachActions.q4PeakOrders', 'AdsCoachActions.q4PeakSpend',
      'AdsCoachActions.sqpAmazonSearchVolume8w', 'AdsCoachActions.sqpClicks8w',
      'AdsCoachActions.sqpSales8w', 'AdsCoachActions.sqpOrders8w',
      'AdsCoachActions.ltNetRoas', 'AdsCoachActions.ltOrders',
      'AdsCoachActions.ltFirstSeen', 'AdsCoachActions.ltLastSeen',
      // Launch track (new-campaign lifecycle)
      'AdsCoachActions.campaignAgeDays', 'AdsCoachActions.isNewCampaign',
      'AdsCoachActions.launchPhase', 'AdsCoachActions.launchDecision',
      'AdsCoachActions.launchBid', 'AdsCoachActions.launchBidSource',
      'AdsCoachActions.launchRecommendedBid', 'AdsCoachActions.launchClicks',
      'AdsCoachActions.clicksSinceLastBidChange', 'AdsCoachActions.launchDecisionTrace',
    ],
    order: { 'AdsCoachActions.priorityScore': 'desc' },
    limit: 2000,
  });
  return (rows as Record<string, unknown>[]).map((row) => {
    const r = row as Record<string, unknown>;
    const result: CoachActionRow = {
    campaign_id: String(r['AdsCoachActions.campaignId'] ?? ''),
    ad_group_id: String(r['AdsCoachActions.adGroupId'] ?? ''),
    campaign_name: String(r['AdsCoachActions.campaignName'] ?? ''),
    campaign_type: String(r['AdsCoachActions.campaignType'] ?? ''),
    search_term: String(r['AdsCoachActions.searchTerm'] ?? ''),
    asin: String(r['AdsCoachActions.asin'] ?? ''),
    product_short_name: String(r['AdsCoachActions.productShortName'] ?? ''),
    parent_name: String(r['AdsCoachActions.parentName'] ?? ''),
    experiment_name: r['AdsCoachActions.experimentName'] != null ? String(r['AdsCoachActions.experimentName']) : null,
    strategy_id: r['AdsCoachActions.strategyId'] != null ? String(r['AdsCoachActions.strategyId']) : null,
    strategy_name: r['AdsCoachActions.strategyName'] != null ? String(r['AdsCoachActions.strategyName']) : null,
    ads_spend_4w: Number(r['AdsCoachActions.adsSpend4w'] ?? 0),
    ads_orders_4w: Number(r['AdsCoachActions.adsOrders4w'] ?? 0),
    ads_clicks_4w: Number(r['AdsCoachActions.adsClicks4w'] ?? 0),
    ads_impressions_4w: Number(r['AdsCoachActions.adsImpressions4w'] ?? 0),
    ads_clicks_1w: Number(r['AdsCoachActions.adsClicks1w'] ?? 0),
    ads_impressions_1w: Number(r['AdsCoachActions.adsImpressions1w'] ?? 0),
    ads_spend_1w: Number(r['AdsCoachActions.adsSpend1w'] ?? 0),
    ads_cpc_1w: r['AdsCoachActions.adsCpc1w'] != null ? Number(r['AdsCoachActions.adsCpc1w']) : null,
    ads_sales_4w: Number(r['AdsCoachActions.adsSales4w'] ?? 0),
    ads_roas_4w: Number(r['AdsCoachActions.adsRoas4w'] ?? 0),
    ads_cpc_4w: r['AdsCoachActions.adsCpc4w'] != null ? Number(r['AdsCoachActions.adsCpc4w']) : null,
    ads_cvr_pct_4w: r['AdsCoachActions.adsCvrPct4w'] != null ? Number(r['AdsCoachActions.adsCvrPct4w']) : null,
    ads_net_roas_4w: r['AdsCoachActions.adsNetRoas4w'] != null ? Number(r['AdsCoachActions.adsNetRoas4w']) : null,
    ads_net_profit_4w: Number(r['AdsCoachActions.adsNetProfit4w'] ?? 0),
    margin_per_unit: Number(r['AdsCoachActions.marginPerUnit'] ?? 0),
    term_spend_4w: Number(r['AdsCoachActions.termSpend4w'] ?? 0),
    term_orders_4w: Number(r['AdsCoachActions.termOrders4w'] ?? 0),
    term_campaign_count: Number(r['AdsCoachActions.termCampaignCount'] ?? 0),
    term_selling_campaigns: Number(r['AdsCoachActions.termSellingCampaigns'] ?? 0),
    spend_share_pct: r['AdsCoachActions.spendSharePct'] != null ? Number(r['AdsCoachActions.spendSharePct']) : null,
    orders_share_pct: r['AdsCoachActions.ordersSharePct'] != null ? Number(r['AdsCoachActions.ordersSharePct']) : null,
    sqp_orders_4w: Number(r['AdsCoachActions.sqpOrders4w'] ?? 0),
    targeting: r['AdsCoachActions.targeting'] != null ? String(r['AdsCoachActions.targeting']) : null,
    keyword_id: r['AdsCoachActions.keywordId'] ? String(r['AdsCoachActions.keywordId']) : null,
    target_net_roas_8w: r['AdsCoachActions.targetNetRoas8w'] != null ? Number(r['AdsCoachActions.targetNetRoas8w']) : null,
    target_clicks_8w: r['AdsCoachActions.targetClicks8w'] != null ? Number(r['AdsCoachActions.targetClicks8w']) : null,
    target_orders_8w: r['AdsCoachActions.targetOrders8w'] != null ? Number(r['AdsCoachActions.targetOrders8w']) : null,
    target_spend_8w: r['AdsCoachActions.targetSpend8w'] != null ? Number(r['AdsCoachActions.targetSpend8w']) : null,
    current_bid: r['AdsCoachActions.currentBid'] != null ? Number(r['AdsCoachActions.currentBid']) : null,
    recommended_bid: r['AdsCoachActions.recommendedBid'] != null ? Number(r['AdsCoachActions.recommendedBid']) : null,
    bid_change_pct: r['AdsCoachActions.bidChangePct'] != null ? Number(r['AdsCoachActions.bidChangePct']) : null,
    match_type: r['AdsCoachActions.matchType'] ? String(r['AdsCoachActions.matchType']) : null,
    action_id: String(r['AdsCoachActions.actionId'] ?? ''),
    decision_branch_id: r['AdsCoachActions.decisionBranchId'] ? String(r['AdsCoachActions.decisionBranchId']) : null,
    action_type: String(r['AdsCoachActions.actionType'] ?? 'TERM'),
    action: String(r['AdsCoachActions.action'] ?? ''),
    priority_score: Number(r['AdsCoachActions.priorityScore'] ?? 0),
    confidence: String(r['AdsCoachActions.confidence'] ?? ''),
    reason: String(r['AdsCoachActions.reason'] ?? ''),
    action_explanation: r['AdsCoachActions.actionExplanation'] ? String(r['AdsCoachActions.actionExplanation']) : null,
    decision_trace: (() => { try { const raw = r['AdsCoachActions.decisionTrace']; return raw ? JSON.parse(String(raw)) : null; } catch (_e) { return null; } })(),
    hero_asin: r['AdsCoachActions.heroAsin'] ? String(r['AdsCoachActions.heroAsin']) : null,
    hero_product_name: r['AdsCoachActions.heroProductName'] ? String(r['AdsCoachActions.heroProductName']) : null,
    is_hero_match: Boolean(r['AdsCoachActions.isHeroMatch']),
    hero_net_roas: r['AdsCoachActions.heroNetRoas'] != null ? Number(r['AdsCoachActions.heroNetRoas']) : null,
    hero_total_orders: r['AdsCoachActions.heroTotalOrders'] != null ? Number(r['AdsCoachActions.heroTotalOrders']) : null,
    coach_mode: String(r['AdsCoachActions.coachMode'] ?? 'GUARDIAN'),
    active_occasion: String(r['AdsCoachActions.activeOccasion'] ?? 'NONE'),
    current_phase: String(r['AdsCoachActions.currentPhase'] ?? 'OFF_SEASON'),
    pp_days: r['AdsCoachActions.ppDays'] != null ? Number(r['AdsCoachActions.ppDays']) : null,
    pp_target_net_roas: r['AdsCoachActions.ppTargetNetRoas'] != null ? Number(r['AdsCoachActions.ppTargetNetRoas']) : null,
    pp_target_spend: r['AdsCoachActions.ppTargetSpend'] != null ? Number(r['AdsCoachActions.ppTargetSpend']) : null,
    pp_target_orders: r['AdsCoachActions.ppTargetOrders'] != null ? Number(r['AdsCoachActions.ppTargetOrders']) : null,
    tos_pct: r['AdsCoachActions.tosPct'] != null ? Number(r['AdsCoachActions.tosPct']) : null,
    product_page_pct: r['AdsCoachActions.productPagePct'] != null ? Number(r['AdsCoachActions.productPagePct']) : null,
    b2b_pct: r['AdsCoachActions.b2bPct'] != null ? Number(r['AdsCoachActions.b2bPct']) : null,
    pre_peak_bid: r['AdsCoachActions.prePeakBid'] != null ? Number(r['AdsCoachActions.prePeakBid']) : null,
    pre_peak_tos_pct: r['AdsCoachActions.prePeakTosPct'] != null ? Number(r['AdsCoachActions.prePeakTosPct']) : null,
    pre_peak_pp_pct: r['AdsCoachActions.prePeakPpPct'] != null ? Number(r['AdsCoachActions.prePeakPpPct']) : null,
    pre_peak_b2b_pct: r['AdsCoachActions.prePeakB2bPct'] != null ? Number(r['AdsCoachActions.prePeakB2bPct']) : null,
    pre_peak_avg_cpc: r['AdsCoachActions.prePeakAvgCpc'] != null ? Number(r['AdsCoachActions.prePeakAvgCpc']) : null,
    last_day_cpc: r['AdsCoachActions.lastDayCpc'] != null ? Number(r['AdsCoachActions.lastDayCpc']) : null,
    current_budget: r['AdsCoachActions.currentBudget'] != null ? Number(r['AdsCoachActions.currentBudget']) : null,
    pre_peak_budget: r['AdsCoachActions.prePeakBudget'] != null ? Number(r['AdsCoachActions.prePeakBudget']) : null,
    recommended_budget: r['AdsCoachActions.recommendedBudget'] != null ? Number(r['AdsCoachActions.recommendedBudget']) : null,
    pp_campaign_net_roas: r['AdsCoachActions.ppCampaignNetRoas'] != null ? Number(r['AdsCoachActions.ppCampaignNetRoas']) : null,
    strategic_task: r['AdsCoachActions.strategicTask'] != null ? String(r['AdsCoachActions.strategicTask']) : null,
    ads_signal: r['AdsCoachActions.adsSignal'] ? String(r['AdsCoachActions.adsSignal']) : null,
    ads_net_roas_3d: r['AdsCoachActions.adsNetRoas3d'] != null ? Number(r['AdsCoachActions.adsNetRoas3d']) : null,
    ads_orders_3d: r['AdsCoachActions.adsOrders3d'] != null ? Number(r['AdsCoachActions.adsOrders3d']) : null,
    ads_units_3d: null,
    ads_net_roas_1w: r['AdsCoachActions.adsNetRoas1w'] != null ? Number(r['AdsCoachActions.adsNetRoas1w']) : null,
    ads_orders_1w: r['AdsCoachActions.adsOrders1w'] != null ? Number(r['AdsCoachActions.adsOrders1w']) : null,
    ads_units_1w: null,
    ly_net_roas: r['AdsCoachActions.lyNetRoas'] != null ? Number(r['AdsCoachActions.lyNetRoas']) : null,
    ly_orders: r['AdsCoachActions.lyOrders'] != null ? Number(r['AdsCoachActions.lyOrders']) : null,
    ly_units: null,
    ly_spend: r['AdsCoachActions.lySpend'] != null ? Number(r['AdsCoachActions.lySpend']) : null,
    ly_clicks: r['AdsCoachActions.lyClicks'] != null ? Number(r['AdsCoachActions.lyClicks']) : null,
    ly_cpc: r['AdsCoachActions.lyCpc'] != null ? Number(r['AdsCoachActions.lyCpc']) : null,
    q4_peak_net_roas: r['AdsCoachActions.q4PeakNetRoas'] != null ? Number(r['AdsCoachActions.q4PeakNetRoas']) : null,
    q4_peak_orders: r['AdsCoachActions.q4PeakOrders'] != null ? Number(r['AdsCoachActions.q4PeakOrders']) : null,
    q4_peak_units: null,
    q4_peak_spend: r['AdsCoachActions.q4PeakSpend'] != null ? Number(r['AdsCoachActions.q4PeakSpend']) : null,
    sqp_amazon_search_volume_8w: r['AdsCoachActions.sqpAmazonSearchVolume8w'] != null ? Number(r['AdsCoachActions.sqpAmazonSearchVolume8w']) : null,
    sqp_clicks_8w: r['AdsCoachActions.sqpClicks8w'] != null ? Number(r['AdsCoachActions.sqpClicks8w']) : null,
    sqp_sales_8w: r['AdsCoachActions.sqpSales8w'] != null ? Number(r['AdsCoachActions.sqpSales8w']) : null,
    sqp_orders_8w: r['AdsCoachActions.sqpOrders8w'] != null ? Number(r['AdsCoachActions.sqpOrders8w']) : null,
    lt_net_roas: r['AdsCoachActions.ltNetRoas'] != null ? Number(r['AdsCoachActions.ltNetRoas']) : null,
    lt_orders: r['AdsCoachActions.ltOrders'] != null ? Number(r['AdsCoachActions.ltOrders']) : null,
    lt_units: null,
    lt_first_seen: r['AdsCoachActions.ltFirstSeen'] != null ? String(r['AdsCoachActions.ltFirstSeen']) : null,
    lt_last_seen: r['AdsCoachActions.ltLastSeen'] != null ? String(r['AdsCoachActions.ltLastSeen']) : null,
    // Launch track (new-campaign lifecycle)
    campaign_age_days: r['AdsCoachActions.campaignAgeDays'] != null ? Number(r['AdsCoachActions.campaignAgeDays']) : null,
    is_new_campaign: r['AdsCoachActions.isNewCampaign'] != null ? Boolean(r['AdsCoachActions.isNewCampaign']) : null,
    launch_phase: r['AdsCoachActions.launchPhase'] != null ? String(r['AdsCoachActions.launchPhase']) : null,
    launch_decision: r['AdsCoachActions.launchDecision'] != null ? String(r['AdsCoachActions.launchDecision']) : null,
    launch_bid: r['AdsCoachActions.launchBid'] != null ? Number(r['AdsCoachActions.launchBid']) : null,
    launch_bid_source: r['AdsCoachActions.launchBidSource'] != null ? String(r['AdsCoachActions.launchBidSource']) : null,
    launch_recommended_bid: r['AdsCoachActions.launchRecommendedBid'] != null ? Number(r['AdsCoachActions.launchRecommendedBid']) : null,
    launch_clicks: r['AdsCoachActions.launchClicks'] != null ? Number(r['AdsCoachActions.launchClicks']) : null,
    clicks_since_last_bid_change: r['AdsCoachActions.clicksSinceLastBidChange'] != null ? Number(r['AdsCoachActions.clicksSinceLastBidChange']) : null,
    launch_decision_trace: (() => { try { const raw = r['AdsCoachActions.launchDecisionTrace']; return raw ? JSON.parse(String(raw)) : null; } catch (_e) { return null; } })(),
    };
    return result;
  });
}

async function loadPlanAdsTargetsFromCube(): Promise<PlanAdsTargetRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'PlanAdsTargets.family', 'PlanAdsTargets.yr', 'PlanAdsTargets.mo', 'PlanAdsTargets.channel',
      'PlanAdsTargets.dailySpendTarget', 'PlanAdsTargets.cpcTarget', 'PlanAdsTargets.predictedCvr',
      'PlanAdsTargets.predictedRoas', 'PlanAdsTargets.predictedUnits', 'PlanAdsTargets.predictedNetProfit',
      'PlanAdsTargets.adsShare', 'PlanAdsTargets.seasonType', 'PlanAdsTargets.multiplierK',
    ],
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    family: String(r['PlanAdsTargets.family'] ?? ''),
    yr: Number(r['PlanAdsTargets.yr'] ?? 0),
    mo: Number(r['PlanAdsTargets.mo'] ?? 0),
    channel: String(r['PlanAdsTargets.channel'] ?? ''),
    daily_spend_target: Number(r['PlanAdsTargets.dailySpendTarget'] ?? 0),
    cpc_target: Number(r['PlanAdsTargets.cpcTarget'] ?? 0),
    predicted_cvr: Number(r['PlanAdsTargets.predictedCvr'] ?? 0),
    predicted_roas: Number(r['PlanAdsTargets.predictedRoas'] ?? 0),
    predicted_units: Number(r['PlanAdsTargets.predictedUnits'] ?? 0),
    predicted_net_profit: Number(r['PlanAdsTargets.predictedNetProfit'] ?? 0),
    ads_share: Number(r['PlanAdsTargets.adsShare'] ?? 0),
    season_type: String(r['PlanAdsTargets.seasonType'] ?? ''),
    multiplier_k: Number(r['PlanAdsTargets.multiplierK'] ?? 0),
  }));
}

/** AdsNegativeConflicts → negative_conflicts (terms a product negates but converts on) */
async function loadNegativeConflictsFromCube(): Promise<import('../types').NegativeConflictRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'AdsNegativeConflicts.campaignId', 'AdsNegativeConflicts.campaignName',
      'AdsNegativeConflicts.negatedTerm', 'AdsNegativeConflicts.asin',
      'AdsNegativeConflicts.negativeId', 'AdsNegativeConflicts.adGroupId',
      'AdsNegativeConflicts.matchType', 'AdsNegativeConflicts.level',
      'AdsNegativeConflicts.productShortName', 'AdsNegativeConflicts.parentName',
      'AdsNegativeConflicts.converterOrders', 'AdsNegativeConflicts.converterSales',
      'AdsNegativeConflicts.converterOrders90d', 'AdsNegativeConflicts.converterSales90d',
      'AdsNegativeConflicts.campaignNetRoasAllTime', 'AdsNegativeConflicts.campaignGrossRoasAllTime',
      'AdsNegativeConflicts.campaignSpendAllTime', 'AdsNegativeConflicts.campaignDistinctAsins',
      'AdsNegativeConflicts.campaignProductChanged',
      'AdsNegativeConflicts.conflictType',
    ],
  });
  const num = (v: unknown): number | null => (v === null || v === undefined ? null : Number(v));
  return (rows as Record<string, unknown>[]).map(r => ({
    campaign_id: String(r['AdsNegativeConflicts.campaignId'] ?? ''),
    campaign_name: String(r['AdsNegativeConflicts.campaignName'] ?? ''),
    negated_term: String(r['AdsNegativeConflicts.negatedTerm'] ?? ''),
    negative_id: String(r['AdsNegativeConflicts.negativeId'] ?? ''),
    ad_group_id: String(r['AdsNegativeConflicts.adGroupId'] ?? ''),
    match_type: String(r['AdsNegativeConflicts.matchType'] ?? ''),
    level: String(r['AdsNegativeConflicts.level'] ?? ''),
    asin: String(r['AdsNegativeConflicts.asin'] ?? ''),
    product_short_name: String(r['AdsNegativeConflicts.productShortName'] ?? ''),
    parent_name: String(r['AdsNegativeConflicts.parentName'] ?? ''),
    converter_orders: Number(r['AdsNegativeConflicts.converterOrders'] ?? 0),
    converter_sales: Number(r['AdsNegativeConflicts.converterSales'] ?? 0),
    converter_orders_90d: Number(r['AdsNegativeConflicts.converterOrders90d'] ?? 0),
    converter_sales_90d: Number(r['AdsNegativeConflicts.converterSales90d'] ?? 0),
    campaign_net_roas_all_time: num(r['AdsNegativeConflicts.campaignNetRoasAllTime']),
    campaign_gross_roas_all_time: num(r['AdsNegativeConflicts.campaignGrossRoasAllTime']),
    campaign_spend_all_time: num(r['AdsNegativeConflicts.campaignSpendAllTime']),
    campaign_distinct_asins: Number(r['AdsNegativeConflicts.campaignDistinctAsins'] ?? 0),
    campaign_product_changed: Boolean(r['AdsNegativeConflicts.campaignProductChanged']),
    conflict_type: String(r['AdsNegativeConflicts.conflictType'] ?? ''),
  }));
}

/** NegativeKeywords → negative_keywords (warehouse-owned registry, ENABLED only) */
async function loadNegativeKeywordsFromCube(): Promise<import('../types').NegativeKeyword[]> {
  const rows = await cubeLoad({
    dimensions: [
      'NegativeKeywords.id', 'NegativeKeywords.campaignName', 'NegativeKeywords.adGroupName',
      'NegativeKeywords.keywordText', 'NegativeKeywords.matchType', 'NegativeKeywords.level',
      'NegativeKeywords.source', 'NegativeKeywords.addedAt',
    ],
    order: { 'NegativeKeywords.addedAt': 'desc' },
    limit: 20000,
  });
  const str = (v: unknown): string | null => (v === null || v === undefined || v === '' ? null : String(v));
  return (rows as Record<string, unknown>[]).map(r => ({
    negative_id: String(r['NegativeKeywords.id'] ?? ''),
    campaign_name: String(r['NegativeKeywords.campaignName'] ?? ''),
    ad_group_name: str(r['NegativeKeywords.adGroupName']),
    keyword_text: String(r['NegativeKeywords.keywordText'] ?? ''),
    match_type: String(r['NegativeKeywords.matchType'] ?? ''),
    level: String(r['NegativeKeywords.level'] ?? ''),
    source: String(r['NegativeKeywords.source'] ?? ''),
    added_at: str(r['NegativeKeywords.addedAt']),
  }));
}

/** AsinOosDays → asin_oos_days (per-ASIN OOS day counts, feeds clear-case gate) */
async function loadAsinOosDaysFromCube(): Promise<AsinOosDaysRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'AsinOosDays.asin', 'AsinOosDays.oosDays28d', 'AsinOosDays.oosDays7d',
      'AsinOosDays.observedDays28d',
    ],
    limit: 5000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    asin: String(r['AsinOosDays.asin'] ?? ''),
    oos_days_28d: Number(r['AsinOosDays.oosDays28d'] ?? 0),
    oos_days_7d: Number(r['AsinOosDays.oosDays7d'] ?? 0),
    observed_days_28d: Number(r['AsinOosDays.observedDays28d'] ?? 0),
  }));
}

async function loadCoachStrategyFromCube(): Promise<CoachStrategyRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'AdsCoachStrategy.coachMode', 'AdsCoachStrategy.northStar',
      'AdsCoachStrategy.northStarMetric', 'AdsCoachStrategy.northStarTarget',
      'AdsCoachStrategy.taskId', 'AdsCoachStrategy.taskName',
      'AdsCoachStrategy.taskDescription', 'AdsCoachStrategy.capability',
      'AdsCoachStrategy.capabilityDirection', 'AdsCoachStrategy.displayOrder',
      'AdsCoachStrategy.mitigation', 'AdsCoachStrategy.emoji',
    ],
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    coach_mode: String(r['AdsCoachStrategy.coachMode'] ?? ''),
    north_star: String(r['AdsCoachStrategy.northStar'] ?? ''),
    north_star_metric: String(r['AdsCoachStrategy.northStarMetric'] ?? ''),
    north_star_target: r['AdsCoachStrategy.northStarTarget'] != null ? Number(r['AdsCoachStrategy.northStarTarget']) : null,
    task_id: String(r['AdsCoachStrategy.taskId'] ?? ''),
    task_name: String(r['AdsCoachStrategy.taskName'] ?? ''),
    task_description: String(r['AdsCoachStrategy.taskDescription'] ?? ''),
    capability: String(r['AdsCoachStrategy.capability'] ?? ''),
    capability_direction: r['AdsCoachStrategy.capabilityDirection'] != null ? String(r['AdsCoachStrategy.capabilityDirection']) : null,
    display_order: Number(r['AdsCoachStrategy.displayOrder'] ?? 0),
    mitigation: r['AdsCoachStrategy.mitigation'] != null ? String(r['AdsCoachStrategy.mitigation']) : null,
    emoji: String(r['AdsCoachStrategy.emoji'] ?? ''),
  }));
}

async function loadCampaignLaunchPerfFromCube(): Promise<import('../types').CampaignLaunchPerfRow[]> {
  try {
    const rows = await cubeLoad({
      dimensions: [
        'CampaignLaunchPerf.campaignId', 'CampaignLaunchPerf.campaignName',
        'CampaignLaunchPerf.campaignType', 'CampaignLaunchPerf.campaignState',
        'CampaignLaunchPerf.creationDate', 'CampaignLaunchPerf.strategyName',
        'CampaignLaunchPerf.windowStatus',
        'CampaignLaunchPerf.units', 'CampaignLaunchPerf.clicks',
        'CampaignLaunchPerf.orders', 'CampaignLaunchPerf.adSpend',
        'CampaignLaunchPerf.grossProfit', 'CampaignLaunchPerf.netProfit',
        'CampaignLaunchPerf.cpc', 'CampaignLaunchPerf.netRoas',
        'CampaignLaunchPerf.activeDays',
      ],
      limit: 500,
    });
    return (rows as Record<string, unknown>[]).map(r => ({
      campaign_id: String(r['CampaignLaunchPerf.campaignId'] ?? ''),
      campaign_name: String(r['CampaignLaunchPerf.campaignName'] ?? ''),
      campaign_type: String(r['CampaignLaunchPerf.campaignType'] ?? ''),
      campaign_state: String(r['CampaignLaunchPerf.campaignState'] ?? ''),
      creation_date: String(r['CampaignLaunchPerf.creationDate'] ?? '').split('T')[0],
      strategy_name: String(r['CampaignLaunchPerf.strategyName'] ?? 'No Strategy'),
      window_status: String(r['CampaignLaunchPerf.windowStatus'] ?? ''),
      units: Number(r['CampaignLaunchPerf.units'] ?? 0),
      clicks: Number(r['CampaignLaunchPerf.clicks'] ?? 0),
      orders: Number(r['CampaignLaunchPerf.orders'] ?? 0),
      ad_spend: Number(r['CampaignLaunchPerf.adSpend'] ?? 0),
      gross_profit: Number(r['CampaignLaunchPerf.grossProfit'] ?? 0),
      net_profit: Number(r['CampaignLaunchPerf.netProfit'] ?? 0),
      cpc: r['CampaignLaunchPerf.cpc'] != null ? Number(r['CampaignLaunchPerf.cpc']) : null,
      net_roas: r['CampaignLaunchPerf.netRoas'] != null ? Number(r['CampaignLaunchPerf.netRoas']) : null,
      active_days: Number(r['CampaignLaunchPerf.activeDays'] ?? 0),
    }));
  } catch (e) {
    console.warn('[CampaignLaunchPerf] Load failed:', e);
    return [];
  }
}
async function loadCampaignLaunchMonthlyFromCube(): Promise<import('../types').CampaignLaunchMonthlyRow[]> {
  try {
    const rows = await cubeLoad({
      dimensions: [
        'CampaignLaunchMonthly.campaignId', 'CampaignLaunchMonthly.campaignName',
        'CampaignLaunchMonthly.campaignType', 'CampaignLaunchMonthly.campaignState',
        'CampaignLaunchMonthly.creationDate', 'CampaignLaunchMonthly.strategyName',
        'CampaignLaunchMonthly.asin', 'CampaignLaunchMonthly.parentName',
        'CampaignLaunchMonthly.lastActiveDate', 'CampaignLaunchMonthly.endDateDisplay',
        'CampaignLaunchMonthly.monthsActive', 'CampaignLaunchMonthly.totalNetProfitDim',
        'CampaignLaunchMonthly.netProfitMonthlyAvg',
        'CampaignLaunchMonthly.m1Units', 'CampaignLaunchMonthly.m1Cpc',
        'CampaignLaunchMonthly.m1AdSpend', 'CampaignLaunchMonthly.m1NetRoas',
        'CampaignLaunchMonthly.m2Units', 'CampaignLaunchMonthly.m2Cpc',
        'CampaignLaunchMonthly.m2AdSpend', 'CampaignLaunchMonthly.m2NetRoas',
        'CampaignLaunchMonthly.m3Units', 'CampaignLaunchMonthly.m3Cpc',
        'CampaignLaunchMonthly.m3AdSpend', 'CampaignLaunchMonthly.m3NetRoas',
      ],
      limit: 500,
    });
    return (rows as Record<string, unknown>[]).map(r => ({
      campaign_id: String(r['CampaignLaunchMonthly.campaignId'] ?? ''),
      campaign_name: String(r['CampaignLaunchMonthly.campaignName'] ?? ''),
      campaign_type: String(r['CampaignLaunchMonthly.campaignType'] ?? ''),
      campaign_state: String(r['CampaignLaunchMonthly.campaignState'] ?? ''),
      creation_date: String(r['CampaignLaunchMonthly.creationDate'] ?? '').split('T')[0],
      strategy_name: String(r['CampaignLaunchMonthly.strategyName'] ?? 'No Strategy'),
      asin: r['CampaignLaunchMonthly.asin'] != null ? String(r['CampaignLaunchMonthly.asin']) : null,
      parent_name: r['CampaignLaunchMonthly.parentName'] != null ? String(r['CampaignLaunchMonthly.parentName']) : null,
      last_active_date: r['CampaignLaunchMonthly.lastActiveDate'] != null ? String(r['CampaignLaunchMonthly.lastActiveDate']).split('T')[0] : null,
      end_date_display: r['CampaignLaunchMonthly.endDateDisplay'] != null ? String(r['CampaignLaunchMonthly.endDateDisplay']).split('T')[0] : null,
      months_active: Number(r['CampaignLaunchMonthly.monthsActive'] ?? 1),
      total_net_profit: Number(r['CampaignLaunchMonthly.totalNetProfitDim'] ?? 0),
      net_profit_monthly_avg: Number(r['CampaignLaunchMonthly.netProfitMonthlyAvg'] ?? 0),
      m1_units: Number(r['CampaignLaunchMonthly.m1Units'] ?? 0),
      m1_cpc: r['CampaignLaunchMonthly.m1Cpc'] != null ? Number(r['CampaignLaunchMonthly.m1Cpc']) : null,
      m1_ad_spend: Number(r['CampaignLaunchMonthly.m1AdSpend'] ?? 0),
      m1_net_roas: r['CampaignLaunchMonthly.m1NetRoas'] != null ? Number(r['CampaignLaunchMonthly.m1NetRoas']) : null,
      m2_units: Number(r['CampaignLaunchMonthly.m2Units'] ?? 0),
      m2_cpc: r['CampaignLaunchMonthly.m2Cpc'] != null ? Number(r['CampaignLaunchMonthly.m2Cpc']) : null,
      m2_ad_spend: Number(r['CampaignLaunchMonthly.m2AdSpend'] ?? 0),
      m2_net_roas: r['CampaignLaunchMonthly.m2NetRoas'] != null ? Number(r['CampaignLaunchMonthly.m2NetRoas']) : null,
      m3_units: Number(r['CampaignLaunchMonthly.m3Units'] ?? 0),
      m3_cpc: r['CampaignLaunchMonthly.m3Cpc'] != null ? Number(r['CampaignLaunchMonthly.m3Cpc']) : null,
      m3_ad_spend: Number(r['CampaignLaunchMonthly.m3AdSpend'] ?? 0),
      m3_net_roas: r['CampaignLaunchMonthly.m3NetRoas'] != null ? Number(r['CampaignLaunchMonthly.m3NetRoas']) : null,
    }));
  } catch (e) {
    console.warn('[CampaignLaunchMonthly] Cube schema not available:', e);
    return [];
  }
}
async function loadCoachCampaignsFromCube(): Promise<CoachCampaignRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'AdsCoachCampaign.campaignId', 'AdsCoachCampaign.campaignName', 'AdsCoachCampaign.campaignType',
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
    campaign_type: r['AdsCoachCampaign.campaignType'] ? String(r['AdsCoachCampaign.campaignType']) : undefined,
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

async function loadAdsFocusTermsFromCube(): Promise<AdsFocusTermRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'AdsFocusTerms.weekStart',
      'AdsFocusTerms.focusBucket',
      'AdsFocusTerms.searchTerm',
    ],
    measures: [
      'AdsFocusTerms.spend',
      'AdsFocusTerms.orders',
      'AdsFocusTerms.sales',
      'AdsFocusTerms.netProfit',
      'AdsFocusTerms.termCount',
    ],
    limit: 10000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    week_start: String(r['AdsFocusTerms.weekStart'] ?? '').split('T')[0],
    focus_bucket: r['AdsFocusTerms.focusBucket'] as 'winner' | 'loser' | 'other_winners' | 'other_losers',
    search_term: String(r['AdsFocusTerms.searchTerm'] ?? ''),
    asin: null,
    product_short_name: null,
    spend: Number(r['AdsFocusTerms.spend'] ?? 0),
    orders: Number(r['AdsFocusTerms.orders'] ?? 0),
    sales: Number(r['AdsFocusTerms.sales'] ?? 0),
    net_profit: Number(r['AdsFocusTerms.netProfit'] ?? 0),
    term_count: Number(r['AdsFocusTerms.termCount'] ?? 0),
  }));
}

async function loadAdsFocusKeywordsFromCube(): Promise<import('../types').AdsFocusKeywordRow[]> {
  try {
    const rows = await cubeLoad({
      dimensions: [
        'AdsFocusKeywords.weekStart',
        'AdsFocusKeywords.focusBucket',
        'AdsFocusKeywords.keyword',
      ],
      measures: [
        'AdsFocusKeywords.spend',
        'AdsFocusKeywords.orders',
        'AdsFocusKeywords.sales',
        'AdsFocusKeywords.netProfit',
        'AdsFocusKeywords.keywordCount',
      ],
      limit: 10000,
    });
    return (rows as Record<string, unknown>[]).map(r => ({
      week_start: String(r['AdsFocusKeywords.weekStart'] ?? '').split('T')[0],
      focus_bucket: r['AdsFocusKeywords.focusBucket'] as 'winner' | 'loser' | 'other_winners' | 'other_losers',
      keyword: String(r['AdsFocusKeywords.keyword'] ?? ''),
      spend: Number(r['AdsFocusKeywords.spend'] ?? 0),
      orders: Number(r['AdsFocusKeywords.orders'] ?? 0),
      sales: Number(r['AdsFocusKeywords.sales'] ?? 0),
      net_profit: Number(r['AdsFocusKeywords.netProfit'] ?? 0),
      keyword_count: Number(r['AdsFocusKeywords.keywordCount'] ?? 0),
    }));
  } catch (e) {
    console.warn('[AdsFocusKeywords] Cube schema not available:', e);
    return [];
  }
}
async function loadPhraseNegativesFromCube(): Promise<PhraseNegativeRow[]> {
  const rows = await cubeLoad({
    dimensions: [
      'AdsCoachPhraseNegatives.phrase', 'AdsCoachPhraseNegatives.ngramSize',
      'AdsCoachPhraseNegatives.campaignId', 'AdsCoachPhraseNegatives.adGroupId', 'AdsCoachPhraseNegatives.campaignName',
      'AdsCoachPhraseNegatives.campaignType', 'AdsCoachPhraseNegatives.portfolioName', 'AdsCoachPhraseNegatives.strategyId',
      'AdsCoachPhraseNegatives.phraseTermCount', 'AdsCoachPhraseNegatives.phraseSpend8w',
      'AdsCoachPhraseNegatives.phraseOrders8w', 'AdsCoachPhraseNegatives.phraseClicks8w',
      'AdsCoachPhraseNegatives.phraseOrders1y', 'AdsCoachPhraseNegatives.phraseSpend1y',
      'AdsCoachPhraseNegatives.phraseSales1y', 'AdsCoachPhraseNegatives.phraseRoas1y',
      'AdsCoachPhraseNegatives.top3MonthsPct', 'AdsCoachPhraseNegatives.peakMonths',
      'AdsCoachPhraseNegatives.seasonalTheme', 'AdsCoachPhraseNegatives.action',
      'AdsCoachPhraseNegatives.priorityScore', 'AdsCoachPhraseNegatives.reason',
      'AdsCoachPhraseNegatives.sampleTerms',
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
    strategy_id: r['AdsCoachPhraseNegatives.strategyId'] ? String(r['AdsCoachPhraseNegatives.strategyId']) : null,
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
    sample_terms: (() => { try { return JSON.parse(String(r['AdsCoachPhraseNegatives.sampleTerms'] ?? '[]')); } catch { return []; } })(),
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
      'BrandStrengthWeekly.parentName',
      'BrandStrengthWeekly.phraseType',
      'BrandStrengthWeekly.requestedProduct',
      'BrandStrengthWeekly.tag',
      // Pre-computed ratios (dimensions, not measures — R4 compliance)
      'BrandStrengthWeekly.avgShowRate', 'BrandStrengthWeekly.avgImpressionShare',
      'BrandStrengthWeekly.avgOrganicRank',
      'BrandStrengthWeekly.adsCpc',
      'BrandStrengthWeekly.brandCvr', 'BrandStrengthWeekly.brandDominanceScore',
      'BrandStrengthWeekly.sqpMonthImpressions', 'BrandStrengthWeekly.sqpLyMonthImpressions',
    ],
    measures: [
      'BrandStrengthWeekly.sqpImpressions', 'BrandStrengthWeekly.sqpClicks',
      'BrandStrengthWeekly.sqpConversions', 'BrandStrengthWeekly.sqpCartAdds',
      'BrandStrengthWeekly.totalSearchVolume',
      'BrandStrengthWeekly.adsImpressions', 'BrandStrengthWeekly.adsClicks',
      'BrandStrengthWeekly.adsOrders', 'BrandStrengthWeekly.adsUnits',
      'BrandStrengthWeekly.adsSpend', 'BrandStrengthWeekly.adsSales',
    ],
    // Order desc + a generous limit so the NEWEST weeks always survive the row
    // cap (the table has >5k rows; an asc+5000 cap was dropping recent weeks,
    // leaving the Brand page stuck ~2 months stale). Page re-sorts asc for display.
    order: { 'BrandStrengthWeekly.weekStartDate': 'desc' },
    limit: 50000,
  });
  return (rows as Record<string, unknown>[]).map(r => ({
    week_start_date: String(r['BrandStrengthWeekly.weekStartDate'] ?? ''),
    brand_keyword: String(r['BrandStrengthWeekly.brandKeyword'] ?? 'other'),
    parent_name: String(r['BrandStrengthWeekly.parentName'] ?? 'Unknown'),
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
    sqp_month_impressions: parseCubeNum(r['BrandStrengthWeekly.sqpMonthImpressions']),
    sqp_ly_month_impressions: parseCubeNum(r['BrandStrengthWeekly.sqpLyMonthImpressions']),
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

// Maps each loadable dataset to its existing loader. Single source of truth
// for "how to load dataset X" — consumed by CubeDataProvider.
export const DATASET_LOADERS: Record<DatasetName, () => Promise<unknown>> = {
  summary: loadSummaryFromCube,
  weekly_trends: loadWeeklyTrendsFromCube,
  monthly_trends: loadMonthlyTrendsFromCube,
  weekly_trends_by_asin: loadWeeklyTrendsByAsinFromCube,
  monthly_trends_by_asin: loadMonthlyTrendsByAsinFromCube,
  daily_trends: loadDailyTrendsFromCube,
  daily_trends_by_asin: loadDailyTrendsByAsinFromCube,
  products: loadProductsFromCube,
  product_creatives: loadProductCreativesFromCube,
  experiments: loadExperimentsFromCube,
  ads_7d_summary: loadAdsSummaryFromCube,
  ads_7d: loadAdsFromCube,
  sqp_weekly: loadSqpFromCube,
  sqp_coverage_weeks: loadSqpCoverageWeeksFromCube,
  sqp_volume_4w: loadSqpVolume4wFromCube,
  change_log: loadChangeLogFromCube,
  upcoming: loadUpcomingFromCube,
  peak: loadPeakFromCube,
  hero_asins: loadHeroAsinsFromCube,
  keyword_product_map: loadKeywordProductMapFromCube,
  learnings: loadLearningsFromCube,
  budget_health: loadBudgetHealthFromCube,
  drivers: loadDriversFromCube,
  experiment_weekly: loadExperimentWeeklyFromCube,
  experiment_campaigns: loadExperimentCampaignsFromCube,
  campaign_search_terms: loadCampaignSearchTermsFromCube,
  campaign_search_terms_weekly: loadCampaignSearchTermsWeeklyFromCube,
  experiment_templates: loadExperimentTemplatesFromCube,
  holidays: loadAllHolidaysFromCube,
  coach_decisions: loadCoachDecisionsFromCube,
  actions: loadCoachActionsFromCube,
  coach_campaigns: loadCoachCampaignsFromCube,
  experiment_evaluations: loadExperimentEvaluationsFromCube,
  keyword_predictions: loadPredictionsFromCube,
  brand_strength_weekly: loadBrandStrengthFromCube,
  coach_phrase_negatives: loadPhraseNegativesFromCube,
  hot_signals: loadHotSignalsFromCube,
  storage_costs: loadStorageCostsFromCube,
  supply_chain: loadSupplyChainFromCube,
  supply_pos: loadSupplyPOsFromCube,
  supply_payments: loadSupplyPaymentsFromCube,
  supply_shipments: loadSupplyShipmentsFromCube,
  peak_relevance: loadPeakRelevanceFromCube,
  family_occasions: loadFamilyOccasionsFromCube,
  coach_strategy: loadCoachStrategyFromCube,
  ads_focus_terms: loadAdsFocusTermsFromCube,
  ads_focus_keywords: loadAdsFocusKeywordsFromCube,
  campaign_launch_perf: loadCampaignLaunchPerfFromCube,
  campaign_launch_monthly: loadCampaignLaunchMonthlyFromCube,
  plan_ads_targets: loadPlanAdsTargetsFromCube,
  asin_oos_days: loadAsinOosDaysFromCube,
  negative_conflicts: loadNegativeConflictsFromCube,
  negative_keywords: loadNegativeKeywordsFromCube,
  strategy_campaign_templates: loadStrategyCampaignTemplatesFromCube,
  coach_cross_sell: loadCrossSellFromCube,
  cubeMeta: loadCubeMeta,
  dataFreshness: loadDataFreshnessFromCube,
};

/* ═══════════════════════════════════════════════════════════════
 * Lazy-load keyword intelligence for inline panel
 * Only fetches when a complex keyword is expanded in the queue.
 * ═══════════════════════════════════════════════════════════════ */
export interface KeywordIntelligenceRow {
  searchTerm: string;
  totalSpend: number;
  totalOrders: number;
  totalClicks: number;
  productCount: number;
  campaignCount: number;
  heroAsin: string | null;
  heroProductName: string | null;
  heroNetRoas: number;
  heroCvrPct: number;
  heroStabilityPct: number;
  heroDataMonths: number;
  monthsWithData: number;
  heroSpend: number;
  heroSpendPct: number;
  complexityScore: number;
  isMultiCampaign: boolean;
  isHeroUnstable: boolean;
  isHeroUnproven: boolean;
  isFragmented: boolean;
  productBreakdown: { asin: string; product_name: string; spend: number; orders: number; clicks: number; cvr_pct: number; net_profit: number; is_hero: boolean; campaign_count: number }[];
  monthlyHeroes: { month: string; hero_asin: string; hero_product: string; orders: number; cvr_pct: number; spend: number }[];
  productBreakdown12m: { asin: string; product_name: string; spend: number; orders: number; clicks: number; cvr_pct: number; net_profit: number; is_hero: boolean; campaign_count: number }[];
  productBreakdownByMonth: { month: string; products: { asin: string; product_name: string; spend: number; orders: number; clicks: number; cvr_pct: number; net_profit: number; is_hero: boolean; campaign_count: number }[] }[];
}

// Cache to avoid re-fetching the same keyword
const intelligenceCache = new Map<string, KeywordIntelligenceRow>();

export function useKeywordIntelligence(searchTerm: string | null) {
  const [data, setData] = useState<KeywordIntelligenceRow | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!searchTerm) { setData(null); return; }

    // Check cache first
    const cached = intelligenceCache.get(searchTerm);
    if (cached) { setData(cached); return; }

    let cancelled = false;
    setLoading(true);

    (async () => {
      try {
        const rows = await cubeLoad({
          dimensions: [
            'KeywordIntelligence.searchTerm',
            'KeywordIntelligence.totalSpend', 'KeywordIntelligence.totalOrders', 'KeywordIntelligence.totalClicks',
            'KeywordIntelligence.productCount', 'KeywordIntelligence.campaignCount',
            'KeywordIntelligence.heroAsin', 'KeywordIntelligence.heroProductName',
            'KeywordIntelligence.heroNetRoas', 'KeywordIntelligence.heroCvrPct',
            'KeywordIntelligence.heroStabilityPct', 'KeywordIntelligence.heroDataMonths', 'KeywordIntelligence.monthsWithData',
            'KeywordIntelligence.heroSpend', 'KeywordIntelligence.heroSpendPct',
            'KeywordIntelligence.complexityScore',
            'KeywordIntelligence.isMultiCampaign', 'KeywordIntelligence.isHeroUnstable',
            'KeywordIntelligence.isHeroUnproven', 'KeywordIntelligence.isFragmented',
            'KeywordIntelligence.productBreakdown', 'KeywordIntelligence.monthlyHeroes',
            'KeywordIntelligence.productBreakdown12m', 'KeywordIntelligence.productBreakdownByMonth',
          ],
          filters: [{ member: 'KeywordIntelligence.searchTerm', operator: 'equals', values: [searchTerm] }],
          limit: 1,
        });

        if (cancelled) return;

        const r = (rows as Record<string, unknown>[])[0];
        if (!r) { setData(null); setLoading(false); return; }

        let productBreakdown: KeywordIntelligenceRow['productBreakdown'] = [];
        let monthlyHeroes: KeywordIntelligenceRow['monthlyHeroes'] = [];
        let productBreakdown12m: KeywordIntelligenceRow['productBreakdown12m'] = [];
        let productBreakdownByMonth: KeywordIntelligenceRow['productBreakdownByMonth'] = [];
        try { productBreakdown = JSON.parse(String(r['KeywordIntelligence.productBreakdown'] ?? '[]')); } catch { /* */ }
        try { monthlyHeroes = JSON.parse(String(r['KeywordIntelligence.monthlyHeroes'] ?? '[]')); } catch { /* */ }
        try { productBreakdown12m = JSON.parse(String(r['KeywordIntelligence.productBreakdown12m'] ?? '[]')); } catch { /* */ }
        try { productBreakdownByMonth = JSON.parse(String(r['KeywordIntelligence.productBreakdownByMonth'] ?? '[]')); } catch { /* */ }

        const row: KeywordIntelligenceRow = {
          searchTerm: String(r['KeywordIntelligence.searchTerm'] ?? ''),
          totalSpend: Number(r['KeywordIntelligence.totalSpend'] ?? 0),
          totalOrders: Number(r['KeywordIntelligence.totalOrders'] ?? 0),
          totalClicks: Number(r['KeywordIntelligence.totalClicks'] ?? 0),
          productCount: Number(r['KeywordIntelligence.productCount'] ?? 0),
          campaignCount: Number(r['KeywordIntelligence.campaignCount'] ?? 0),
          heroAsin: r['KeywordIntelligence.heroAsin'] ? String(r['KeywordIntelligence.heroAsin']) : null,
          heroProductName: r['KeywordIntelligence.heroProductName'] ? String(r['KeywordIntelligence.heroProductName']) : null,
          heroNetRoas: Number(r['KeywordIntelligence.heroNetRoas'] ?? 0),
          heroCvrPct: Number(r['KeywordIntelligence.heroCvrPct'] ?? 0),
          heroStabilityPct: Number(r['KeywordIntelligence.heroStabilityPct'] ?? 0),
          heroDataMonths: Number(r['KeywordIntelligence.heroDataMonths'] ?? 0),
          monthsWithData: Number(r['KeywordIntelligence.monthsWithData'] ?? 0),
          heroSpend: Number(r['KeywordIntelligence.heroSpend'] ?? 0),
          heroSpendPct: Number(r['KeywordIntelligence.heroSpendPct'] ?? 0),
          complexityScore: Number(r['KeywordIntelligence.complexityScore'] ?? 0),
          isMultiCampaign: Boolean(r['KeywordIntelligence.isMultiCampaign']),
          isHeroUnstable: Boolean(r['KeywordIntelligence.isHeroUnstable']),
          isHeroUnproven: Boolean(r['KeywordIntelligence.isHeroUnproven']),
          isFragmented: Boolean(r['KeywordIntelligence.isFragmented']),
          productBreakdown,
          monthlyHeroes,
          productBreakdown12m,
          productBreakdownByMonth,
        };

        intelligenceCache.set(searchTerm, row);
        if (!cancelled) { setData(row); setLoading(false); }
      } catch (e) {
        console.warn('[useKeywordIntelligence] failed:', e);
        if (!cancelled) { setData(null); setLoading(false); }
      }
    })();

    return () => { cancelled = true; };
  }, [searchTerm]);

  return { data, loading };
}
