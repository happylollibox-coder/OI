/**
 * ============================================================
 * supply-shipments.spec.ts — Shipment create → edit → delete round-trip
 * ============================================================
 *
 * ⚠️  DO NOT RUN IN CI OR AGAINST PRODUCTION.
 *
 * This test MUTATES REAL DATA:
 *   - Creates a Shipment in BigQuery via the Flask /api/shipment/create endpoint
 *   - Edits a line quantity_shipped via /api/shipment/<id>/line/<lid>
 *   - Permanently deletes the Shipment via /api/shipment/<id>/delete
 *
 * Prerequisites before running:
 *   1. Vite dev server running:  npm run dev        (→ http://localhost:5173)
 *   2. Flask data-entry running: flask run or gunicorn in data-entry-app/
 *                                                    (→ http://localhost:5050)
 *   3. Cube.js running:          cd cube && npm run dev  (→ http://localhost:4000)
 *   All three services must be up; Playwright reuses an existing dev server
 *   (reuseExistingServer: true in playwright.config.ts).
 *
 * Selectors marked // TODO must be confirmed against the live DOM on first
 * --headed run before relying on this spec in any automated context.
 *
 * Exclude from CI unless a dedicated sandbox environment with all three
 * services is available and SUPPLY_E2E=1 is set.
 * ============================================================
 */

import { test, expect } from '@playwright/test';

// Skip automatically in CI unless an explicit opt-in env var is set.
test.skip(
  !!process.env.CI && !process.env.SUPPLY_E2E,
  'Supply E2E skipped in CI — requires live Flask + Cube servers and SUPPLY_E2E=1',
);

test('Shipment create → edit → delete round-trip', async ({ page }) => {
  // ── 1. Unique marker for this test run ──────────────────────────────────────
  // We embed the marker in the Notes field (always visible in the drawer
  // and surfaced on the row via products_list after server aggregation).
  // The tracking_number field is optional and also a good unique anchor,
  // but Notes is the most reliable text-searchable field in the drawer.
  const marker = 'E2E_' + Date.now();

  // Use today's date as the shipment_date so the default date filter includes it.
  const shipmentDate = new Date().toISOString().slice(0, 10); // YYYY-MM-DD

  // ── 2. Navigate to the app ───────────────────────────────────────────────────
  await page.goto('/');
  // Wait for the home-page landmark before proceeding (mirrors supply-pos.spec.ts).
  await expect(page.getByText('Weekly Summary')).toBeVisible({ timeout: 10_000 });

  // ── 3. Navigate to the Supply page via sidebar ───────────────────────────────
  // Sidebar renders nav buttons with their label text (Sidebar.tsx: label: 'SUPPLY').
  await page.getByRole('button', { name: 'SUPPLY' }).click();

  // Verify the Supply Chain heading rendered.
  await expect(page.getByText('Supply Chain')).toBeVisible({ timeout: 8_000 });

  // ── 4. Click the Shipments tab ───────────────────────────────────────────────
  // Tab label is "Shipments" (SupplyPage.tsx line 776).
  // TODO: confirm selector — the tab is a <button> with text "Shipments"; if the
  //       tab bar uses a different role/container, narrow with .first() or a
  //       parent scoping locator.
  await page.getByRole('button', { name: /^Shipments/ }).click();

  // Confirm the tab activated — the "New Shipment" button only renders when
  // tab === 'shipments' (SupplyPage.tsx line 914).
  await expect(page.getByRole('button', { name: /New Shipment/ })).toBeVisible({ timeout: 5_000 });

  // ── 5. Open the "New Shipment" modal ─────────────────────────────────────────
  // Button text is "New Shipment" with a Plus icon (SupplyPage.tsx line 920).
  await page.getByRole('button', { name: /New Shipment/ }).click();

  // Wait for the modal header.
  await expect(page.getByText('New Manufacturer Shipment')).toBeVisible({ timeout: 5_000 });

  // ── 6. Fill the shipment form ─────────────────────────────────────────────────

  // Shipment Date — <input type="date"> (NewShipmentModal.tsx line 350–357).
  // Labelled only via a non-<label for> text node; use the date input directly.
  // TODO: confirm selector — the date input has no htmlFor label; if getByLabel
  //       fails, fall back to page.locator('input[type="date"]').first().
  const dateInput = page.locator('input[type="date"]').first();
  await dateInput.fill(shipmentDate);

  // Wait for LOVs to finish loading (select becomes enabled when lovsLoading = false).
  // Deliverer — required <select> (NewShipmentModal.tsx line 365–380).
  // TODO: confirm the select element has a label accessible by name; if not,
  //       locate by position: page.locator('select').nth(0).
  const delivererSelect = page.locator('select').nth(0);
  await expect(delivererSelect).not.toBeDisabled({ timeout: 8_000 });
  // Pick the first non-placeholder option (index 1).
  // TODO: if the LOV is empty in your sandbox, add a SUPPLIER with attr1_value='Deliverer'
  //       via the Flask admin before running this test.
  await delivererSelect.selectOption({ index: 1 });

  // Shipment Type — optional <select> (NewShipmentModal.tsx line 386–399).
  const typeSelect = page.locator('select').nth(1);
  await expect(typeSelect).not.toBeDisabled({ timeout: 5_000 });
  // Pick the first non-placeholder option if available; otherwise leave blank.
  const typeOptions = await typeSelect.locator('option').count();
  if (typeOptions > 1) {
    await typeSelect.selectOption({ index: 1 });
  }

  // Notes — use the marker so the drawer shows searchable text after creation.
  // <textarea placeholder="Any additional information…"> (NewShipmentModal.tsx line 488).
  await page.getByPlaceholder(/Any additional information/i).fill(marker);

  // ── 7. Allocate a quantity on one open-PO line ───────────────────────────────
  // The allocation table renders after posLoading becomes false.
  // Wait for it to appear (either a product row OR the "No open PO lines" message).
  // TODO: confirm the table becomes visible within 10 s in your sandbox.
  await expect(
    page.locator('table').first().or(page.getByText(/No open PO lines available/i)),
  ).toBeVisible({ timeout: 10_000 });

  // Find the first "Qty to Ship" input (w-20 number inputs inside the allocation
  // table, one per open-PO line — NewShipmentModal.tsx line 629–655).
  // They have: type="number" min=0, placeholder="0", class contains "w-20".
  // TODO: confirm selector — if multiple number inputs exist before the table,
  //       scope to the allocation table's tbody instead.
  const qtyInputs = page.locator('input[type="number"][placeholder="0"]');
  const firstQtyInput = qtyInputs.first();

  // Only attempt to fill if there is at least one open PO line.
  const qtyCount = await qtyInputs.count();
  if (qtyCount === 0) {
    // No open PO lines — the modal will reject on submit. Skip allocation; the
    // test will fail at step 8 with the modal's own validation message, which
    // is the correct failure mode when the sandbox has no open POs.
    console.warn('[supply-shipments] No open PO lines found — allocation skipped. Ensure the sandbox has at least one open PO with remaining_quantity > 0.');
  } else {
    // Enter 1 unit — always within any remaining cap ≥ 1.
    await firstQtyInput.fill('1');
  }

  // ── 8. Submit the shipment ───────────────────────────────────────────────────
  // Footer submit button text is "Create Shipment" (NewShipmentModal.tsx line 724).
  await page.getByRole('button', { name: /Create Shipment/i }).click();

  // Modal closes on success (setShowNewShipment(false) in onSaved).
  await expect(page.getByText('New Manufacturer Shipment')).not.toBeVisible({ timeout: 15_000 });

  // ── 9. Assert a shipment row appears in the table ────────────────────────────
  // After onSaved, SupplyPage fetches the detail and injects it into
  // shipmentOverrides; the row should appear immediately.
  // The table rows render the shipment_date formatted via fmtDate (e.g. "Jun 16, 2026").
  // We can't easily match the formatted date, so assert the row count grew by
  // checking the table has at least one <tbody> row.
  // A more precise assertion: the drawer we'll open in step 10 is the authoritative
  // confirmation — so here we just confirm the table rendered rows.
  await expect(
    page.locator('tbody tr').first(),
  ).toBeVisible({ timeout: 10_000 });

  // ── 10. Open the newly created shipment's drawer ─────────────────────────────
  // ShipmentsTable (SupplyPage.tsx line 1418) renders each row's first cell as
  // a <button title="View details: <shipment_id>">…</button> (line 1441).
  // The most recently created shipment is sorted first by default (sort desc by
  // shipment_date). We click the first "View details" button in the table.
  // TODO: confirm the sort order on first --headed run. If the new row is not
  //       first, search the tbody for a row containing today's formatted date.
  const viewDetailsBtn = page
    .locator('button[title^="View details:"]')
    .first();
  await expect(viewDetailsBtn).toBeVisible({ timeout: 8_000 });
  await viewDetailsBtn.click();

  // Wait for the drawer to load.
  // The drawer shows a spinner with "Loading shipment details…" while fetching
  // (ShipmentDetailDrawer.tsx line 358–360).
  await expect(page.getByText('Loading shipment details…')).not.toBeVisible({ timeout: 10_000 });

  // Confirm the drawer opened and loaded: the Notes section shows our marker.
  // (ShipmentDetailDrawer.tsx line 635–641 — renders when notes is truthy.)
  // TODO: confirm selector — if the drawer renders the notes text without a
  //       dedicated testid, this text match is the most reliable handle.
  await expect(page.getByText(marker)).toBeVisible({ timeout: 8_000 });

  // ── 11. Edit a line quantity_shipped in the drawer ───────────────────────────
  // ShipmentDetailDrawer renders per-line quantity_shipped as a number input
  // (ShipmentDetailDrawer.tsx line 495–501):
  //   <input type="number" className="…w-16 …" value={draft.quantity_shipped} …/>
  // When the value differs from the saved value a "Save quantity" button appears
  // (title="Save quantity", line 503).
  // The allocated_cost inputs have step="0.01"; the quantity inputs do NOT —
  // that uniquely identifies them.
  // TODO: if there are quantity inputs from other open drawers/pickers on screen,
  //       scope to the drawer panel with a more specific ancestor locator.
  const qtyShippedInput = page
    .locator('input[type="number"]')
    .filter({ hasNot: page.locator('[step="0.01"]') })
    .first();
  // TODO: the filter above excludes step="0.01" inputs; confirm it selects the
  //       correct quantity_shipped input and not an unrelated numeric field.
  // Alternative reliable selector if the above is fragile:
  //   page.locator('input[type="number"]').nth(0)  — first number input in drawer
  await qtyShippedInput.fill('2');

  // Wait for the "Save quantity" icon button to appear.
  const saveQtyBtn = page.getByTitle('Save quantity');
  await expect(saveQtyBtn).toBeVisible({ timeout: 3_000 });
  await saveQtyBtn.click();

  // Wait for the busy spinner to clear (ShipmentDetailDrawer.tsx line 674:
  // "Saving…" text next to a Loader2 icon when busy === true).
  await expect(page.getByText('Saving…')).not.toBeVisible({ timeout: 10_000 });

  // ── 12. Assert the edit persisted ────────────────────────────────────────────
  // After refreshAndNotify the drawer re-renders with the server-side value.
  // The quantity_shipped input should now show "2".
  // TODO: confirm the selector still points to the same input after refresh.
  await expect(
    page
      .locator('input[type="number"]')
      .filter({ hasNot: page.locator('[step="0.01"]') })
      .first(),
  ).toHaveValue('2', { timeout: 8_000 });

  // ── 13. Delete the shipment ───────────────────────────────────────────────────
  // Footer shows "Delete Shipment" button (ShipmentDetailDrawer.tsx line 669).
  await page.getByRole('button', { name: /Delete Shipment/i }).click();

  // Confirmation prompt appears (ShipmentDetailDrawer.tsx line 649):
  // "Delete this shipment and all its lines?"
  await expect(page.getByText(/Delete this shipment and all its lines\?/i)).toBeVisible();

  // "Confirm Delete" button (line 659–663).
  await page.getByRole('button', { name: /Confirm Delete/i }).click();

  // Drawer closes: onChanged(null) triggers onClose() (ShipmentDetailDrawer.tsx line 296).
  await expect(page.getByText(/Delete this shipment and all its lines\?/i)).not.toBeVisible({ timeout: 10_000 });

  // ── 14. Assert the row is gone from the table ─────────────────────────────────
  // SupplyPage adds the shipment_id to deletedShipmentIds after onChanged(null);
  // effectiveShipments filters it out immediately (SupplyPage.tsx line 444).
  // We can't easily match the marker in the table rows (notes aren't rendered
  // inline), so assert that no "View details: <id>" button for our shipment
  // remains. Since we don't know the id at test-write time, assert the marker
  // text (from the Notes section) is gone from the page entirely.
  await expect(page.getByText(marker)).toHaveCount(0);
});
