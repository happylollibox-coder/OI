import { Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_DIR = path.join(__dirname, '../fixtures');
const FILES = [
  'summary', 'actions', 'upcoming', 'peak', 'products', 'hero_asins',
  'keyword_product_map', 'weekly_trends', 'monthly_trends', 'weekly_trends_by_asin', 'monthly_trends_by_asin', 'learnings',
  'experiments', 'budget_health', 'drivers', 'change_log', 'negative_keywords',
  'experiment_weekly', 'sqp_weekly', 'sqp_volume_4w', 'experiment_campaigns', 'campaign_search_terms',
  'ads_7d', 'experiment_templates',
  '_meta',
] as const;

/** Intercept /data/*.json and serve fixture data. Call in beforeEach or test. */
export async function routeDataFixtures(page: Page) {
  await page.route('**/data/*.json', async (route) => {
    const url = route.request().url();
    const match = url.match(/\/data\/([^/]+)\.json$/);
    const file = match?.[1];
    if (!file || !FILES.includes(file as typeof FILES[number])) {
      return route.continue();
    }
    const fixturePath = path.join(FIXTURE_DIR, `${file}.json`);
    let body: unknown;
    if (fs.existsSync(fixturePath)) {
      body = JSON.parse(fs.readFileSync(fixturePath, 'utf-8'));
    } else {
      body = file === '_meta' ? {} : [];
    }
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
  });
}
