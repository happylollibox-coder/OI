import { test, expect } from '@playwright/test';
import { routeDataFixtures } from './fixtures';

test.beforeEach(async ({ page }) => {
  await routeDataFixtures(page);
});

test('HomePage loads and shows KPI metrics', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByText('Weekly Summary')).toBeVisible({ timeout: 10000 });
  await expect(page.getByTestId('kpi-sales')).toBeVisible();
  await expect(page.getByTestId('kpi-sales')).toContainText(/[\d,]+/);
  await expect(page.getByTestId('kpi-profit')).toBeVisible();
});

test('Filters work: Parent filter updates UI', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByText('Weekly Summary')).toBeVisible({ timeout: 10000 });

  // Open Parent dropdown and select Lollibox
  await page.getByRole('button', { name: /Parent/i }).first().click();
  await page.getByRole('button', { name: 'Lollibox' }).click();

  // Assert filter is applied: Clear button appears
  await expect(page.getByRole('button', { name: /Clear \d+/ })).toBeVisible();

  // Assert Parent shows Lollibox
  await expect(page.getByRole('button', { name: /Parent/i }).first()).toContainText('Lollibox');

  // Clear filters and verify we're back to All
  await page.getByRole('button', { name: /Clear \d+/ }).click();
  await expect(page.getByRole('button', { name: /Clear \d+/ })).not.toBeVisible();
});
