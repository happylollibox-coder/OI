#!/usr/bin/env node
/**
 * Acceptance check: what Cube SERVES for Ads.spend must equal raw FACT_AMAZON_ADS.
 *
 * Deliberately does NOT pass renewQuery — the point is to catch a stale cached result,
 * which is exactly what a forced re-run would hide. See test-refresh-keys.js for the
 * restatement/refresh-key background.
 *
 * Run: node test-ads-reconcile.js [startDate endDate]
 * Needs: cube dev server on :4000, CUBEJS_API_SECRET in cube/.env, authenticated `bq`.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const jwt = require('jsonwebtoken');

const CUBE_URL = process.env.CUBE_URL || 'http://localhost:4000';
const TABLE = 'onyga-482313.OI.FACT_AMAZON_ADS';

function readEnv() {
  const file = path.join(__dirname, '.env');
  if (!fs.existsSync(file)) return {};
  return Object.fromEntries(
    fs.readFileSync(file, 'utf8')
      .split('\n')
      .filter(l => l.includes('=') && !l.trim().startsWith('#'))
      .map(l => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()])
  );
}

function bq(sql) {
  const out = execFileSync('bq', ['query', '--use_legacy_sql=false', '--format=csv', sql], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  });
  return out.trim().split('\n').slice(1); // drop header
}

function addDays(iso, n) {
  const d = new Date(iso + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

async function main() {
  let [start, end] = process.argv.slice(2);
  if (!start || !end) {
    // Default: the 7 days ending at the latest date present in the fact table.
    end = bq(`SELECT CAST(MAX(date) AS STRING) FROM \`${TABLE}\``)[0];
    start = addDays(end, -6);
  }

  const secret = process.env.CUBEJS_API_SECRET || readEnv().CUBEJS_API_SECRET;
  if (!secret) throw new Error('CUBEJS_API_SECRET not found (env or cube/.env)');
  const token = jwt.sign({ email: 'test@local' }, secret, { expiresIn: '10m' });

  const res = await fetch(`${CUBE_URL}/cubejs-api/v1/load`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      query: {
        measures: ['Ads.spend'],
        dimensions: ['Ads.campaignId'],
        timeDimensions: [{ dimension: 'Ads.date', dateRange: [start, end] }],
        limit: 5000,
      },
    }),
  });
  const json = await res.json();
  if (json.error) throw new Error(`Cube error: ${JSON.stringify(json.error)}`);

  const cubeSpend = json.data.reduce((s, r) => s + Number(r['Ads.spend'] || 0), 0);
  const cubeCampaigns = json.data.length;

  const [rawRow] = bq(
    `SELECT ROUND(SUM(Ads_cost), 2), COUNT(DISTINCT campaign_id) FROM \`${TABLE}\`` +
    ` WHERE date BETWEEN '${start}' AND '${end}'`
  );
  const [rawSpend, rawCampaigns] = rawRow.split(',').map(Number);

  const delta = cubeSpend - rawSpend;
  console.log(`range        ${start} → ${end}`);
  console.log(`cube         $${cubeSpend.toFixed(2)}  (${cubeCampaigns} campaigns)`);
  console.log(`raw fact     $${rawSpend.toFixed(2)}  (${rawCampaigns} campaigns)`);
  console.log(`delta        $${delta.toFixed(2)}  (${(rawSpend ? (delta / rawSpend) * 100 : 0).toFixed(3)}%)`);
  console.log(`served at    ${json.lastRefreshTime}`);

  if (Math.abs(delta) > 0.01) {
    console.error('\nFAIL — Cube does not reconcile with FACT_AMAZON_ADS.');
    process.exit(1);
  }
  console.log('\nPASS — Cube reconciles with FACT_AMAZON_ADS.');
}

main().catch(e => { console.error('ERROR:', e.message); process.exit(2); });
