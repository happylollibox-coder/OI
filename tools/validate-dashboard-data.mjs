#!/usr/bin/env node
/**
 * Dashboard Data Validation Script
 * =================================
 * Compares Cube API responses (same data as React dashboard) against
 * BigQuery raw queries to catch aggregation bugs.
 *
 * Checks:
 *   1. TOTAL — overall Sales, COGS, Ads Spend, Orders
 *   2. FAMILY — per product family (Lollibox, LolliME, Bottle, Fresh)
 *   3. PRODUCT — per ASIN breakdown
 *   4. ADS BY PRODUCT — Ads Spend per product (campaign→ASIN mapping)
 *   5. SUM CONSISTENCY — Total = ∑ Families = ∑ Products
 *
 * Usage:
 *   node tools/validate-dashboard-data.mjs [--week 2026-02-21] [--cube http://localhost:4000]
 *
 * Requires:
 *   - Cube.js running locally (default: http://localhost:4000)
 *   - gcloud CLI authenticated (bq command) for BigQuery queries
 */

import { execSync } from 'child_process';

const CUBE_URL = process.argv.includes('--cube')
  ? process.argv[process.argv.indexOf('--cube') + 1]
  : 'http://localhost:4000';

const TARGET_WEEK = process.argv.includes('--week')
  ? process.argv[process.argv.indexOf('--week') + 1]
  : null;

const BQ_PROJECT = 'onyga-482313';
const BQ_DATASET = 'OI';
const TOLERANCE_PCT = 2; // 2% tolerance

// ─── Helpers ──────────────────────────────────────────────────────────────────

function fmt(n) { return typeof n === 'number' ? `$${n.toFixed(2)}` : String(n); }

function bqQuery(sql) {
  try {
    const cleanSql = sql.replace(/\n/g, ' ').replace(/\s+/g, ' ').trim();
    const result = execSync(
      `bq query --project_id=${BQ_PROJECT} --use_legacy_sql=false --format=json --max_rows=500 '${cleanSql.replace(/'/g, "'\\''")}'`,
      { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024, timeout: 30000 }
    );
    return JSON.parse(result.trim() || '[]');
  } catch (e) {
    console.error('  ⚠ BQ query failed:', e.stderr?.slice(0, 300) || e.message?.slice(0, 300));
    return [];
  }
}

async function cubeQuery(query) {
  try {
    const resp = await fetch(`${CUBE_URL}/cubejs-api/v1/load`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: '__no_auth__' },
      body: JSON.stringify({ query }),
    });
    if (!resp.ok) {
      const body = await resp.text();
      throw new Error(`HTTP ${resp.status}: ${body.slice(0, 200)}`);
    }
    const json = await resp.json();
    return json.results?.[0]?.data || json.data || [];
  } catch (e) {
    console.error('  ⚠ Cube query failed:', e.message?.slice(0, 300));
    return [];
  }
}

function compare(label, cubeVal, bqVal, metric) {
  const a = Number(cubeVal) || 0;
  const b = Number(bqVal) || 0;
  const diff = Math.abs(a - b);
  const maxVal = Math.max(Math.abs(a), Math.abs(b), 0.01);
  const pctDiff = (diff / maxVal) * 100;
  const pass = pctDiff <= TOLERANCE_PCT;
  const status = pass ? '✅' : pctDiff <= 10 ? '⚠️' : '❌';
  console.log(`  ${status} ${label.padEnd(30)} ${metric.padEnd(15)} Cube: ${fmt(a).padStart(12)} | BQ: ${fmt(b).padStart(12)} ${!pass ? `(${pctDiff.toFixed(1)}% diff)` : ''}`);
  return { label, metric, cube: a, bq: b, pctDiff, pass };
}

// ─── Detect Latest Week ───────────────────────────────────────────────────────

async function getLatestWeek() {
  if (TARGET_WEEK) return TARGET_WEEK;
  const rows = await cubeQuery({
    measures: ['UnifiedPerformance.sales'],
    dimensions: ['UnifiedPerformance.weekStart'],
    order: { 'UnifiedPerformance.weekStart': 'desc' },
    limit: 1,
  });
  const ws = rows[0]?.['UnifiedPerformance.weekStart'];
  return ws ? ws.slice(0, 10) : null;
}

// ─── Check 1: Total-Level Metrics ─────────────────────────────────────────────

async function checkTotals(week) {
  console.log(`\n${'━'.repeat(70)}`);
  console.log(`📊 CHECK 1: Total-Level Metrics (week: ${week})`);
  console.log('━'.repeat(70));

  const cubeTrends = await cubeQuery({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.adCost', 'UnifiedPerformance.cogs', 'UnifiedPerformance.orders'],
    timeDimensions: [{ dimension: 'UnifiedPerformance.weekStart', dateRange: [week, week] }],
  });
  const ct = cubeTrends[0] || {};

  const bqRows = bqQuery(`
    SELECT SUM(sales) AS sales, SUM(cogs) AS cogs, SUM(ad_cost) AS ad_cost, SUM(orders) AS orders
    FROM ${BQ_DATASET}.V_UNIFIED_DAILY WHERE week_start_date = '${week}'
  `);
  const bt = bqRows[0] || {};

  return [
    compare('Total', ct['UnifiedPerformance.sales'], bt.sales, 'Sales'),
    compare('Total', ct['UnifiedPerformance.cogs'], bt.cogs, 'COGS'),
    compare('Total', ct['UnifiedPerformance.adCost'], bt.ad_cost, 'Ads Spend'),
    compare('Total', ct['UnifiedPerformance.orders'], bt.orders, 'Orders'),
  ];
}

// ─── Check 2: Family-Level Metrics ────────────────────────────────────────────

async function checkFamilies(week) {
  console.log(`\n${'━'.repeat(70)}`);
  console.log(`📊 CHECK 2: Family-Level Metrics (week: ${week})`);
  console.log('━'.repeat(70));

  const cubeFam = await cubeQuery({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.adCost', 'UnifiedPerformance.cogs', 'UnifiedPerformance.orders'],
    dimensions: ['UnifiedPerformance.family'],
    timeDimensions: [{ dimension: 'UnifiedPerformance.weekStart', dateRange: [week, week] }],
  });

  const bqFam = bqQuery(`
    SELECT family, SUM(sales) AS sales, SUM(cogs) AS cogs, SUM(ad_cost) AS ad_cost, SUM(orders) AS orders
    FROM ${BQ_DATASET}.V_UNIFIED_DAILY WHERE week_start_date = '${week}'
    GROUP BY family ORDER BY family
  `);

  const bqMap = {};
  for (const r of bqFam) { bqMap[r.family] = r; }

  const results = [];
  for (const cr of cubeFam) {
    const fam = cr['UnifiedPerformance.family'];
    const br = bqMap[fam] || {};
    results.push(compare(`Family:${fam}`, cr['UnifiedPerformance.sales'], br.sales, 'Sales'));
    results.push(compare(`Family:${fam}`, cr['UnifiedPerformance.cogs'], br.cogs, 'COGS'));
    results.push(compare(`Family:${fam}`, cr['UnifiedPerformance.adCost'], br.ad_cost, 'Ads Spend'));
    results.push(compare(`Family:${fam}`, cr['UnifiedPerformance.orders'], br.orders, 'Orders'));
  }
  return results;
}

// ─── Check 3: Product-Level Metrics (ASIN breakdown) ──────────────────────────

async function checkProducts(week) {
  console.log(`\n${'━'.repeat(70)}`);
  console.log(`📊 CHECK 3: Product-Level Metrics (week: ${week})`);
  console.log('━'.repeat(70));

  const cubeProd = await cubeQuery({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.cogs', 'UnifiedPerformance.orders'],
    dimensions: ['UnifiedPerformance.asin', 'UnifiedPerformance.family'],
    timeDimensions: [{ dimension: 'UnifiedPerformance.weekStart', dateRange: [week, week] }],
  });

  const bqProd = bqQuery(`
    SELECT asin, family, SUM(sales) AS sales, SUM(cogs) AS cogs, SUM(orders) AS orders
    FROM ${BQ_DATASET}.V_UNIFIED_DAILY WHERE week_start_date = '${week}'
    GROUP BY asin, family ORDER BY sales DESC
  `);

  const bqMap = {};
  for (const r of bqProd) { bqMap[r.asin] = r; }

  const results = [];
  for (const cr of cubeProd) {
    const asin = cr['UnifiedPerformance.asin'];
    const br = bqMap[asin] || {};
    results.push(compare(`ASIN:${asin}`, cr['UnifiedPerformance.sales'], br.sales, 'Sales'));
    results.push(compare(`ASIN:${asin}`, cr['UnifiedPerformance.cogs'], br.cogs, 'COGS'));
    results.push(compare(`ASIN:${asin}`, cr['UnifiedPerformance.orders'], br.orders, 'Orders'));
  }
  return results;
}

// ─── Check 4: Ads by Campaign → Product mapping ──────────────────────────────

async function checkAdsByProduct(week) {
  console.log(`\n${'━'.repeat(70)}`);
  console.log(`📊 CHECK 4: Ads Spend by Product (week: ${week})`);
  console.log('━'.repeat(70));

  const cubeAds = await cubeQuery({
    measures: ['Ads.spend', 'Ads.sales', 'Ads.orders'],
    dimensions: ['Product.productShortName'],
    timeDimensions: [{ dimension: 'Ads.weekStart', dateRange: [week, week] }],
  });

  const bqAds = bqQuery(`
    SELECT p.product_short_name, SUM(a.cost) AS spend, SUM(a.sales) AS sales, SUM(a.orders) AS orders
    FROM ${BQ_DATASET}.FACT_AMAZON_ADS a
    JOIN ${BQ_DATASET}.DIM_PRODUCT p ON a.most_advertised_asin_impressions = p.asin
    WHERE a.date BETWEEN '${week}' AND DATE_ADD('${week}', INTERVAL 6 DAY)
    GROUP BY p.product_short_name ORDER BY spend DESC
  `);

  const bqMap = {};
  for (const r of bqAds) { bqMap[r.product_short_name] = r; }

  const results = [];
  for (const cr of cubeAds) {
    const name = cr['Product.productShortName'];
    if (!name) continue;
    const br = bqMap[name] || {};
    results.push(compare(`Product:${name}`, cr['Ads.spend'], br.spend, 'Ads Spend'));
    results.push(compare(`Product:${name}`, cr['Ads.sales'], br.sales, 'Ads Sales'));
    results.push(compare(`Product:${name}`, cr['Ads.orders'], br.orders, 'Ads Orders'));
  }
  return results;
}

// ─── Check 5: Sum Consistency ─────────────────────────────────────────────────

async function checkSumConsistency(week) {
  console.log(`\n${'━'.repeat(70)}`);
  console.log(`📊 CHECK 5: Internal Consistency — Total = ∑Families = ∑Products (week: ${week})`);
  console.log('━'.repeat(70));

  const cubeTotal = await cubeQuery({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.orders'],
    timeDimensions: [{ dimension: 'UnifiedPerformance.weekStart', dateRange: [week, week] }],
  });
  const ct = cubeTotal[0] || {};
  const totalSales = Number(ct['UnifiedPerformance.sales']) || 0;
  const totalOrders = Number(ct['UnifiedPerformance.orders']) || 0;

  const cubeFam = await cubeQuery({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.orders'],
    dimensions: ['UnifiedPerformance.family'],
    timeDimensions: [{ dimension: 'UnifiedPerformance.weekStart', dateRange: [week, week] }],
  });
  const famSales = cubeFam.reduce((s, r) => s + (Number(r['UnifiedPerformance.sales']) || 0), 0);
  const famOrders = cubeFam.reduce((s, r) => s + (Number(r['UnifiedPerformance.orders']) || 0), 0);

  const cubeProd = await cubeQuery({
    measures: ['UnifiedPerformance.sales', 'UnifiedPerformance.orders'],
    dimensions: ['UnifiedPerformance.asin'],
    timeDimensions: [{ dimension: 'UnifiedPerformance.weekStart', dateRange: [week, week] }],
  });
  const prodSales = cubeProd.reduce((s, r) => s + (Number(r['UnifiedPerformance.sales']) || 0), 0);
  const prodOrders = cubeProd.reduce((s, r) => s + (Number(r['UnifiedPerformance.orders']) || 0), 0);

  return [
    compare('Consistency', totalSales, famSales, 'Tot vs ∑Fam Sales'),
    compare('Consistency', totalSales, prodSales, 'Tot vs ∑Prod Sales'),
    compare('Consistency', totalOrders, famOrders, 'Tot vs ∑Fam Orders'),
    compare('Consistency', totalOrders, prodOrders, 'Tot vs ∑Prod Orders'),
  ];
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log('🔍 Dashboard Data Validation');
  console.log(`   Cube: ${CUBE_URL}`);
  console.log(`   BQ:   ${BQ_PROJECT}.${BQ_DATASET}`);

  const week = await getLatestWeek();
  if (!week) { console.error('❌ Could not determine latest week'); process.exit(1); }
  console.log(`   Week: ${week}\n`);

  const allResults = [];
  allResults.push(...await checkTotals(week));
  allResults.push(...await checkFamilies(week));
  allResults.push(...await checkProducts(week));
  allResults.push(...await checkAdsByProduct(week));
  allResults.push(...await checkSumConsistency(week));

  // Summary
  console.log(`\n${'═'.repeat(70)}`);
  const total = allResults.length;
  const passed = allResults.filter(r => r.pass).length;
  const failed = allResults.filter(r => !r.pass);
  console.log(`📋 SUMMARY: ${passed}/${total} checks passed`);
  if (failed.length) {
    console.log(`\n❌ FAILURES:`);
    for (const f of failed) {
      console.log(`   ${f.label} ${f.metric}: Cube=${fmt(f.cube)} vs BQ=${fmt(f.bq)} (${f.pctDiff.toFixed(1)}% diff)`);
    }
  } else {
    console.log('🎉 All checks passed!');
  }
  console.log('═'.repeat(70));
  process.exit(failed.length > 0 ? 1 : 0);
}

main().catch(e => { console.error('Fatal:', e); process.exit(1); });
