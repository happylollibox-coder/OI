/**
 * ============================================================
 * supply-pos.spec.ts — PO create → edit → delete round-trip
 * ============================================================
 *
 * ⚠️  DO NOT RUN IN CI OR AGAINST PRODUCTION.
 *
 * This test MUTATES REAL DATA:
 *   - Creates a Purchase Order in BigQuery via the Flask /api/po/create endpoint
 *   - Edits a product-line amount via /api/po/update_line
 *   - Permanently deletes the PO via /api/po/delete
 *
 * Prerequisites before running:
 *   1. Vite dev server running:  npm run dev        (→ http://localhost:5173)
 *   2. Flask data-entry running: (e.g. flask run or gunicorn in data-entry-app/)
 *   3. Cube.js running:          cd cube && npm run dev  (→ http://localhost:4000)
 *   All three services must be up; Playwright reuses an existing dev server
 *   (reuseExistingServer: true in playwright.config.ts).
 *
 * Exclude from CI unless a dedicated sandbox environment with all three
 * services is available and SUPPLY_E2E=1 is set.
 *
 * Selectors marked // TODO must be confirmed against the live DOM on first run.
 * ============================================================
 */

import { test, expect } from '@playwright/test';

// Skip automatically in CI unless an explicit opt-in env var is set.
test.skip(
  !!process.env.CI && !process.env.SUPPLY_E2E,
  'Supply E2E skipped in CI — requires live Flask + Cube servers and SUPPLY_E2E=1',
);

test('PO create → edit → delete round-trip', async ({ page }) => {
  // ── 1. Unique marker for this test run ──────────────────────────────────────
  const marker = 'E2E_' + Date.now();
  // Use a fixed future date so "Open only" filter keeps the PO visible.
  const orderDate = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10); // YYYY-MM-DD, ~30 days from now

  // ── 2. Navigate to the app ───────────────────────────────────────────────────
  await page.goto('/');
  // Wait for home-page landmark before proceeding (mirrors all-pages.spec.ts).
  await expect(page.getByText('Weekly Summary')).toBeVisible({ timeout: 10_000 });

  // ── 3. Navigate to the Supply page via sidebar ───────────────────────────────
  // Sidebar renders nav buttons with their label text (Sidebar.tsx: label: 'SUPPLY').
  await page.getByRole('button', { name: 'SUPPLY' }).click();

  // Verify the Supply Chain heading rendered.
  await expect(page.getByText('Supply Chain')).toBeVisible({ timeout: 8_000 });

  // ── 4. Make sure the Purchase Orders tab is active ───────────────────────────
  // Tab label is "Purchase Orders" (SupplyPage.tsx line 689).
  // It may already be active (default tab is 'pos'), but click to be sure.
  await page.getByRole('button', { name: /Purchase Orders/ }).click();

  // ── 5. Disable "Open only" filter so the new PO is visible even before edit ──
  // The checkbox label text is "Open only" (SupplyPage.tsx line 773).
  const openOnlyLabel = page.getByText('Open only');
  // Uncheck if currently checked (the filter defaults to true).
  const openOnlyCheckbox = openOnlyLabel.locator('..').locator('input[type="checkbox"]');
  // TODO: confirm selector against live DOM — label wraps the checkbox so the
  //       nearest ancestor approach should work, but inspect if it doesn't.
  if (await openOnlyCheckbox.isChecked()) {
    await openOnlyCheckbox.uncheck();
  }

  // ── 6. Open the "New PO" modal ───────────────────────────────────────────────
  // Button text is "New PO" with a Plus icon (SupplyPage.tsx line 836).
  await page.getByRole('button', { name: /New PO/ }).first().click();

  // Wait for the modal header to appear.
  await expect(page.getByText('New Purchase Order')).toBeVisible({ timeout: 5_000 });

  // ── 7. Fill the PO form ──────────────────────────────────────────────────────

  // Order Date — <input type="date" required> (NewPOModal.tsx line 213).
  // The date input auto-focuses on mount; fill it by label.
  await page.getByLabel(/Order Date/i).fill(orderDate);

  // Manufacturer Name — pre-filled with "SYLVIA"; replace with marker.
  // Label text is "Manufacturer" (NewPOModal.tsx line 226).
  const manufacturerInput = page.getByLabel(/Manufacturer/i);
  await manufacturerInput.fill(marker);

  // Product line — ProductSelect is a SearchableDropdown (custom component,
  // not a native <select>).  The toggle button shows the placeholder
  // "Select product" when no value is selected (ProductSelect.tsx line 90).
  // Click to open the dropdown, then search and pick the first product.
  const productTrigger = page.getByRole('button', { name: /Select product/i });
  // TODO: confirm selector — if there are multiple "Select product" buttons
  //       (e.g. another line already open) use .first().
  await productTrigger.first().click();

  // The search input placeholder is "Search select product..." (SearchableDropdown.tsx line 69).
  const productSearchInput = page.getByPlaceholder(/search select product/i);
  // TODO: confirm placeholder text against live DOM — it renders as
  //       `Search ${placeholder.toLowerCase()}...` where placeholder = "Select product".
  await productSearchInput.fill('Lollibox'); // search by known parent group

  // Pick the first result in the dropdown list.
  // Options are rendered as <button> elements with the product label text.
  const firstProductOption = page
    .locator('[class*="max-h-48"] button')
    .filter({ hasText: /Lollibox/i })
    .first();
  // TODO: confirm the dropdown list container selector — it uses Tailwind class
  //       "max-h-48 overflow-y-auto" (SearchableDropdown.tsx line 73).
  await firstProductOption.click();

  // Quantity — numeric input, label "Qty" (NewPOModal.tsx line 327).
  // The first line's qty is already 1; set a distinct value to ease assertion.
  await page.getByLabel(/^Qty/i).first().fill('10');

  // Amount — numeric input, label "Amount" (NewPOModal.tsx line 342).
  await page.getByLabel(/^Amount/i).first().fill('500');

  // ── 8. Submit the PO ─────────────────────────────────────────────────────────
  // Footer submit button text is "Save Purchase Order" (NewPOModal.tsx line 409).
  await page.getByRole('button', { name: /Save Purchase Order/i }).click();

  // Modal closes on success; wait for it to disappear.
  await expect(page.getByText('New Purchase Order')).not.toBeVisible({ timeout: 15_000 });

  // ── 9. Assert the new row appears in the PO table ────────────────────────────
  // The table renders manufacturer_name in a <td> (SupplyPage.tsx line 1097).
  // After save, SupplyPage fetches the PO and injects it into poOverrides;
  // it should appear immediately without a page reload.
  await expect(page.getByText(marker).first()).toBeVisible({ timeout: 10_000 });

  // ── 10. Open the PO's detail drawer ──────────────────────────────────────────
  // Each PO row has a button showing the PO ID with an Eye icon (SupplyPage.tsx
  // line 1086–1093).  Find the row that contains our marker text, then click
  // the Eye button within it (the PO ID button in that same row).
  // Strategy: find the <tr> that contains the marker, then click the first
  // link-style button inside it.
  const markerRow = page.locator('tr').filter({ hasText: marker });
  // The PO ID button is the first <button> in the row that opens the drawer.
  await markerRow.getByRole('button').first().click();
  // TODO: if the first button in the row turns out to be something else (sort
  //       header, copy button), narrow by title="View details:".

  // Wait for the drawer to load the PO detail.
  await expect(page.getByText('Loading PO details…')).not.toBeVisible({ timeout: 10_000 });
  // The drawer header shows the PO ID; confirm the drawer is open by checking
  // for the marker in the drawer's subtitle area (manufacturer_name).
  await expect(page.getByText(marker).first()).toBeVisible({ timeout: 8_000 });

  // ── 11. Edit a line amount in the drawer ─────────────────────────────────────
  // The drawer renders each line's total_amount as <input type="number" step="0.01">
  // (PODetailDrawer.tsx line 422).  It is the only step="0.01" input rendered
  // for a single-line PO, so we can target it directly.
  // When the value differs from the saved value a Save icon button appears.
  const amountInput = page.locator('input[type="number"][step="0.01"]').first();
  // TODO: confirm selector — if the drawer adds more step="0.01" inputs (e.g.
  //       the "add line" amount field), use nth(0) for the existing line amount.
  await amountInput.fill('600');

  // A Save icon button appears when the draft differs from saved value.
  // The button's title is "Save amount" (PODetailDrawer.tsx line 432).
  const saveAmountBtn = page.getByTitle('Save amount');
  await saveAmountBtn.click();

  // Wait for the busy spinner to clear (drawer re-fetches after each write).
  // The drawer shows a "Saving…" text while busy.
  await expect(page.getByText('Saving…')).not.toBeVisible({ timeout: 10_000 });

  // ── 12. Assert the edit persisted ────────────────────────────────────────────
  // After refreshAndNotify the drawer re-renders with the server-side value.
  // The amount input (step="0.01") should now show "600".
  await expect(
    page.locator('input[type="number"][step="0.01"]').first(),
  ).toHaveValue('600', { timeout: 8_000 });

  // ── 13. Delete the PO ────────────────────────────────────────────────────────
  // Footer shows "Delete PO" button (PODetailDrawer.tsx line 654).
  await page.getByRole('button', { name: /Delete PO/i }).click();

  // Confirmation prompt appears with "Confirm Delete" button (line 648).
  await expect(page.getByText(/Delete this PO and all its lines\?/)).toBeVisible();
  await page.getByRole('button', { name: /Confirm Delete/i }).click();

  // Drawer closes (onClose is called after successful delete, line 241).
  await expect(page.getByText(/Delete this PO and all its lines\?/)).not.toBeVisible({ timeout: 10_000 });

  // ── 14. Assert the row is gone from the table ─────────────────────────────────
  // SupplyPage adds the PO id to deletedPOIds after onChanged(null); the row
  // is filtered out immediately.
  await expect(page.getByText(marker)).toHaveCount(0);
});
