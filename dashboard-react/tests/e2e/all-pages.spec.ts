import { test, expect } from '@playwright/test';
import { routeDataFixtures } from './fixtures';

test.beforeEach(async ({ page }) => {
  await routeDataFixtures(page);
});

/** Navigate via sidebar and assert page content. Each page shows either main content or empty state. */
const PAGE_TESTS: { navLabel: string; expectedText: string | RegExp }[] = [
  { navLabel: 'HOME', expectedText: 'Weekly Summary' },
  { navLabel: 'ACTION', expectedText: /Detailed Actions|No pending actions/ },
  { navLabel: 'PEAK', expectedText: /Next Peak|No upcoming peak/ },
  { navLabel: 'ADS', expectedText: /Campaigns|What's Working|No matching terms/ },
  { navLabel: 'STRAT', expectedText: /Experiment Strategies|No experiment template data/ },
  { navLabel: 'SQP', expectedText: /All Families|SQP across all product families/ },
  { navLabel: 'LEARN', expectedText: /Learnings|No weekly experiment data/ },
  { navLabel: 'KWDS', expectedText: /Keyword–Product Map|No keyword data/ },
  { navLabel: 'LOG', expectedText: /Change Log|No changes/ },
  { navLabel: 'HEALTH', expectedText: 'System Health' },
  { navLabel: 'ADMIN', expectedText: /Operations|DB Tests/ },
];

for (const { navLabel, expectedText } of PAGE_TESTS) {
  test(`${navLabel} page loads and shows expected content`, async ({ page }) => {
    await page.goto('/');
    await expect(page.getByText('Weekly Summary')).toBeVisible({ timeout: 10000 });

    await page.getByRole('button', { name: navLabel }).click();

    await expect(page.getByText(expectedText).first()).toBeVisible({ timeout: 5000 });
  });

  test(`${navLabel} page visual regression`, async ({ page }) => {
    await page.goto('/');
    await expect(page.getByText('Weekly Summary')).toBeVisible({ timeout: 10000 });

    await page.getByRole('button', { name: navLabel }).click();
    await expect(page.getByText(expectedText).first()).toBeVisible({ timeout: 5000 });

    // Scroll main to bottom so any lazy content loads
    await page.locator('main').evaluate((el) => {
      el.scrollTop = el.scrollHeight;
    });
    await page.waitForTimeout(300);

    // Expand layout so fullPage captures all content (main has overflow-y-auto, document is viewport-sized)
    await page.evaluate(() => {
      const main = document.querySelector('main') as HTMLElement;
      if (!main) return;
      const sh = main.scrollHeight;
      const headerH = 56;
      document.body.style.height = `${headerH + sh}px`;
      document.body.style.overflow = 'visible';
      main.style.position = 'absolute';
      main.style.top = `${headerH}px`;
      main.style.left = '68px';
      main.style.right = '0';
      main.style.bottom = 'auto';
      main.style.height = `${sh}px`;
      main.style.overflow = 'visible';
    });

    await expect(page).toHaveScreenshot(`${navLabel.toLowerCase()}-page.png`, { fullPage: true });
  });
}
