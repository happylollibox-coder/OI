#!/usr/bin/env node
/**
 * Regression guard: refresh keys over restated fact tables must be content-sensitive.
 *
 * Amazon restates the last several days of ads data IN PLACE. SP_LOAD rewrites rows for
 * dates that already exist, so a watermark key like `SELECT MAX(date) FROM FACT_AMAZON_ADS`
 * returns the SAME value before and after the restatement — Cube keeps serving the
 * pre-restatement result and the dashboard under-reports spend.
 *
 * Observed 2026-07-23: FACT_AMAZON_ADS summed to 7,479.41 for 07-16→07-22 at 06:00Z and
 * 7,617.77 after the 07:06:45Z reload, MAX(date) = 2026-07-22 both times.
 *
 * Run: node test-refresh-keys.js
 */
const fs = require('fs');
const path = require('path');

// Tables Amazon restates in place. A refresh key over these must change when the
// row VALUES change, not only when a new date arrives.
//
// Each entry below was proved with BigQuery time travel: compare an aggregate at two
// FOR SYSTEM_TIME AS OF points and confirm it moves while MAX(<watermark>) is unchanged.
//   FACT_AMAZON_ADS ................ spend 7,479.41 -> 7,617.77, MAX(date) = 2026-07-22
//   ..._SEARCH_PERFORMANCE_WEEKLY .. ADS_Orders 435 -> 443, MAX(Reporting_Date) = 2026-07-18
//   FACT_EXPERIMENT_DAILY .......... ads_all_cost 533,718.38 -> 535,361.51 at a CONSTANT 7,384 rows
//   FACT_SEARCH_QUERY .............. distinct queries 412 -> 1,496, MAX(week_start_date) = 2026-07-12
//   T_UNIFIED_DAILY ................ ad_cost 715,174.30 -> 715,265.68, MAX(date) = 2026-07-21
//   targeting_keyword_report ....... cost 1,153.73 -> 1,152.75 at a CONSTANT 353 rows
//
// FACT_EXPERIMENT_DAILY and targeting_keyword_report both restated at an unchanged row count,
// which is why COUNT(*) in a composite key is not a sufficient guard either.
//
// View names are listed alongside their physical base table so that keying on the view — which
// has no last_modified_time of its own — is also rejected.
const RESTATED_TABLES = [
  'FACT_AMAZON_ADS',
  'FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY',
  'FACT_EXPERIMENT_DAILY',
  'FACT_SEARCH_QUERY',
  'V_SQP_QUERY_WEEKLY',        // view over FACT_SEARCH_QUERY
  'T_UNIFIED_DAILY',
  'V_KEYWORD_DAILY',           // view over fivetran-hl.amazon_ads.targeting_keyword_report
  'targeting_keyword_report',
  'keyword_history',
];

const WATERMARK_RE = /SELECT\s+MAX\s*\(/i;

// A key that reads __TABLES__ is restatement-safe by construction: last_modified_time flips on
// every rewrite. MAX() over __TABLES__ (to span several base tables) is therefore fine, so the
// metadata check has to come before the watermark check.
const METADATA_RE = /__TABLES__/;

const schemaDir = path.join(__dirname, 'schema');
const failures = [];

for (const file of fs.readdirSync(schemaDir).filter(f => f.endsWith('.js'))) {
  const src = fs.readFileSync(path.join(schemaDir, file), 'utf8');
  const m = src.match(/refreshKey:\s*\{([\s\S]*?)\}/);
  if (!m) continue;
  const key = m[1];

  if (METADATA_RE.test(key)) continue;

  for (const table of RESTATED_TABLES) {
    if (!key.includes(table)) continue;
    if (WATERMARK_RE.test(key)) {
      failures.push(
        `${file}: refreshKey over ${table} is a bare watermark — an in-place ` +
        `restatement leaves it unchanged and Cube serves stale totals.\n` +
        `    ${key.trim().replace(/\s+/g, ' ')}`
      );
    }
  }
}

if (failures.length) {
  console.error(`FAIL — ${failures.length} cube(s) with a restatement-blind refresh key:\n`);
  failures.forEach(f => console.error('  • ' + f + '\n'));
  process.exit(1);
}

console.log('PASS — no restatement-blind refresh keys.');
