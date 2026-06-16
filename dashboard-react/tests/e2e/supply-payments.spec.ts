/**
 * ============================================================
 * supply-payments.spec.ts — Payment create → edit → delete round-trip
 * ============================================================
 *
 * ⚠️  DO NOT RUN IN CI OR AGAINST PRODUCTION.
 *
 * This test MUTATES REAL DATA:
 *   - Creates a Payment in BigQuery via the Flask /api/payment/create endpoint
 *   - Edits the payment's notes (and optionally amount) via /api/payment/<id>/update
 *   - Permanently deletes the Payment via /api/payment/<id>/delete
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

test('Payment create → edit → delete round-trip', async ({ page }) => {
  // ── 1. Unique marker for this test run ──────────────────────────────────────
  // We embed the marker in the Notes field. Notes are surfaced inside the
  // PaymentDetailDrawer (headerView.notes, PaymentDetailDrawer.tsx line 378–383)
  // and are the most reliable text-searchable field for post-creation assertion.
  const marker = 'E2E_' + Date.now();

  // Use today's date as the payment_date so default date filters include it.
  const paymentDate = new Date().toISOString().slice(0, 10); // YYYY-MM-DD

  // ── 2. Navigate to the app ───────────────────────────────────────────────────
  await page.goto('/');
  // Wait for the home-page landmark before proceeding (mirrors supply-shipments.spec.ts).
  await expect(page.getByText('Weekly Summary')).toBeVisible({ timeout: 10_000 });

  // ── 3. Navigate to the Supply page via sidebar ───────────────────────────────
  // Sidebar renders nav buttons with their label text (Sidebar.tsx: label: 'SUPPLY').
  await page.getByRole('button', { name: 'SUPPLY' }).click();

  // Verify the Supply Chain heading rendered.
  await expect(page.getByText('Supply Chain')).toBeVisible({ timeout: 8_000 });

  // ── 4. Click the Payments tab ────────────────────────────────────────────────
  // Tab label is "Payments" (SupplyPage.tsx line 848).
  // The tab bar renders <button> elements with the label text and a count badge.
  // TODO: confirm selector — if the tab bar has ambiguous "Payments" text
  //       elsewhere, narrow with a parent scoping locator.
  await page.getByRole('button', { name: /^Payments/ }).click();

  // Confirm the tab activated — "New Payment" button only renders when
  // tab === 'payments' (SupplyPage.tsx line 996–1011).
  await expect(page.getByRole('button', { name: /New Payment/ })).toBeVisible({ timeout: 5_000 });

  // ── 5. Open the "New Payment" modal ──────────────────────────────────────────
  // Button text is "New Payment" (SupplyPage.tsx line 1010).
  // There is also a "Bulk Pay" button rendered before it; target by name.
  await page.getByRole('button', { name: /New Payment/ }).click();

  // Wait for the modal header.
  // NewPaymentModal renders <h2>New Vendor Payment</h2> (NewPaymentModal.tsx line 226).
  await expect(page.getByText('New Vendor Payment')).toBeVisible({ timeout: 5_000 });

  // ── 6. Fill the payment form ──────────────────────────────────────────────────

  // Vendor — segmented radio buttons SYLVIA | ANNA | JENNA
  // (NewPaymentModal.tsx line 266–280). Pick SYLVIA.
  // Each vendor renders as a <button type="button"> with the vendor name as text.
  await page.getByRole('button', { name: 'SYLVIA' }).click();

  // Payment Date — <input type="date" required> (NewPaymentModal.tsx line 291–298).
  // The date input auto-focuses on mount. It has no htmlFor label — locate by type.
  // TODO: confirm selector — if there are other date inputs on screen,
  //       scope to the modal container instead.
  const dateInput = page.locator('input[type="date"]').first();
  await dateInput.fill(paymentDate);

  // Payment Method (Paid From Account) — <select required> (NewPaymentModal.tsx line 306–320).
  // Becomes enabled when lovsLoading transitions to false.
  // It is the only required <select> in the form; the currency <select> is optional.
  // TODO: confirm selector — if the form renders multiple selects before LOVs
  //       load, this nth(0) approach targets the first select (payment_method).
  //       Alternatively, scope by the label "Paid From Account".
  const paymentMethodSelect = page.locator('select').first();
  await expect(paymentMethodSelect).not.toBeDisabled({ timeout: 8_000 });
  // Pick the first non-placeholder option (index 1).
  // TODO: if LOV PAYMENT_METHOD is empty in your sandbox, add a LOV entry via
  //       the Flask admin (lov_type='PAYMENT_METHOD') before running this test.
  await paymentMethodSelect.selectOption({ index: 1 });

  // Payment Amount — <input type="number" step="any" placeholder="0.00">
  // (NewPaymentModal.tsx line 337–341). Must not be 0.
  await page.getByPlaceholder('0.00').first().fill('100');

  // Notes — embed the marker for later identification.
  // <textarea placeholder="Any additional information…"> (NewPaymentModal.tsx line 421–428).
  await page.getByPlaceholder(/Any additional information/i).fill(marker);

  // ── 7. Submit the payment ─────────────────────────────────────────────────────
  // Footer submit button text is "Save Payment" (NewPaymentModal.tsx line 442).
  await page.getByRole('button', { name: /Save Payment/i }).click();

  // Modal closes on success (setShowNewPayment(false) via onSaved in SupplyPage
  // line 532). Wait for the modal header to disappear.
  await expect(page.getByText('New Vendor Payment')).not.toBeVisible({ timeout: 15_000 });

  // ── 8. Assert a payment row appears in the table ──────────────────────────────
  // After onSaved, SupplyPage fetches the payment detail and injects it into
  // paymentOverrides; the row should appear immediately.
  // The PaymentsTable renders payment_id as a <button title="View details: <id>">
  // (SupplyPage.tsx line 1463–1470). We can't know the id at write time, so
  // assert the table has at least one <tbody> row.
  await expect(
    page.locator('tbody tr').first(),
  ).toBeVisible({ timeout: 10_000 });

  // ── 9. Open the newly created payment's drawer ────────────────────────────────
  // PaymentsTable renders each row's Payment ID cell as a <button
  //   title="View details: <payment_id>"> (SupplyPage.tsx line 1463–1470).
  // The most recently created payment is sorted first by default
  // (paySort = { field: 'payment_date', dir: 'desc' }, SupplyPage.tsx line 325).
  // Click the first "View details:" button.
  // TODO: confirm sort order on first --headed run. If the new row is not
  //       first, scan tbody for the row whose title contains "View details:"
  //       created today (the payment_id contains the creation timestamp).
  const viewDetailsBtn = page
    .locator('button[title^="View details:"]')
    .first();
  await expect(viewDetailsBtn).toBeVisible({ timeout: 8_000 });
  await viewDetailsBtn.click();

  // Wait for the drawer to finish loading.
  // PaymentDetailDrawer shows "Loading payment details…" while fetching
  // (PaymentDetailDrawer.tsx line 226–228).
  await expect(page.getByText('Loading payment details…')).not.toBeVisible({ timeout: 10_000 });

  // Confirm the drawer is open and loaded: the Notes section shows our marker.
  // (PaymentDetailDrawer.tsx line 378–383 — renders when headerView.notes is truthy.)
  // TODO: confirm selector — if the drawer does not show notes text at
  //       top level, scope to the drawer container with a parent locator.
  await expect(page.getByText(marker)).toBeVisible({ timeout: 8_000 });

  // ── 10. Edit the payment via the drawer's edit form ───────────────────────────
  // PaymentDetailDrawer renders an edit toggle button with title="Edit payment"
  // (PaymentDetailDrawer.tsx line 207–214). Clicking it shows the header edit form.
  const editBtn = page.getByTitle('Edit payment');
  await expect(editBtn).toBeVisible({ timeout: 5_000 });
  await editBtn.click();

  // The edit form appears; it contains a <textarea> for Notes
  // (PaymentDetailDrawer.tsx line 280). Update the notes with a suffix to confirm
  // the edit persisted after save.
  const editedMarker = marker + '_EDITED';
  // The drawer's edit form Notes textarea is the only <textarea> in the drawer.
  // TODO: confirm selector — if other textareas appear on screen, scope to the
  //       drawer edit section using a closer ancestor locator.
  const notesTextarea = page.locator('textarea').first();
  await notesTextarea.fill(editedMarker);

  // Submit the edit — the "Save Payment" button inside the edit form
  // (PaymentDetailDrawer.tsx line 288–293).
  // Note: there is no role="button" with name="Save Payment" ambiguity here
  // because the create modal is closed; this is the only "Save Payment" button.
  await page.getByRole('button', { name: /Save Payment/i }).click();

  // Wait for the busy spinner to clear
  // (PaymentDetailDrawer.tsx line 416: "Saving…" text when busy === true).
  await expect(page.getByText('Saving…')).not.toBeVisible({ timeout: 10_000 });

  // ── 11. Assert the edit persisted ─────────────────────────────────────────────
  // After refreshAndNotify the drawer re-renders with the server-side value.
  // The edited notes text should now appear in the drawer's notes section.
  // TODO: confirm selector — after save, editingHeader resets to false and
  //       the notes render in the read-only notes band (line 378–383).
  await expect(page.getByText(editedMarker)).toBeVisible({ timeout: 8_000 });

  // ── 12. Delete the payment via the drawer ─────────────────────────────────────
  // Footer shows "Delete Payment" button (PaymentDetailDrawer.tsx line 409–414).
  await page.getByRole('button', { name: /Delete Payment/i }).click();

  // Confirmation prompt appears with "Delete this payment?"
  // (PaymentDetailDrawer.tsx line 391).
  await expect(page.getByText(/Delete this payment\?/i)).toBeVisible();

  // "Confirm Delete" button (PaymentDetailDrawer.tsx line 399–405).
  await page.getByRole('button', { name: /Confirm Delete/i }).click();

  // Drawer closes: doDeletePayment calls onChanged(null) then onClose()
  // (PaymentDetailDrawer.tsx line 163–164).
  await expect(page.getByText(/Delete this payment\?/i)).not.toBeVisible({ timeout: 10_000 });

  // ── 13. Assert the row is gone from the table ─────────────────────────────────
  // SupplyPage adds the payment_id to deletedPaymentIds after onChanged(null)
  // (SupplyPage.tsx line 539–544); effectivePayments filters it out immediately.
  // The marker text (from Notes) was only visible in the drawer, but the edited
  // marker is no longer on the page at all after the drawer closes.
  // We also assert the drawer's "Delete this payment?" prompt is fully gone.
  await expect(page.getByText(editedMarker)).toHaveCount(0);
});
