# Supply: Multiple POs on One Payment (Full / Partial)

**Date:** 2026-07-05
**Status:** Approved design — ready for implementation plan
**Scope:** Frontend-only enhancement to the Supply page. No BigQuery / Cube / Flask changes.

## Problem

On the Supply page, a user needs to record a single real bank payment that covers
several purchase orders at once, where each PO may be paid **in full** or **partially**.

## Key finding: the backend already supports this

A "payment" in `DE_VENDOR_PAYMENTS` is not one row — it is **all rows sharing the same
`payment_id`**. Each row carries its own `purchase_order_id` and its own `payment_amount`.

The full plumbing for "one payment across many POs, each with its own amount" already exists
and is shipped:

- **Flask** `bulk_create_po_payments(data)` (`data-entry-app/app.py:3000`) generates **one**
  `payment_id`, writes **one row per PO** (`payment_amount` per PO → partials work), and
  applies `bank_fee` to the **first row only** (no double-count).
- **JSON route** `POST /api/payments/bulk-po` (`app.py:3287`) wraps it.
- **Client** `dataEntry.bulkCreatePoPayments({ po_ids, amounts, payment_date,
  payment_method, vendor_name, currency, bank_fee, notes })`
  (`dashboard-react/src/utils/dataEntry.ts:217`).
- **View** `V_SUPPLY_ORDERS_DASHBOARD` computes `total_paid = SUM(payment_amount)` per
  `purchase_order_id`, so partial allocations roll up to each PO correctly with **zero SQL
  changes**.
- **UI** `BulkPaymentModal.tsx` (PO mode), opened by the **"Bulk Pay"** button
  (`SupplyPage.tsx:1013`), already: lists open POs with checkbox + an **Unpaid** column
  (`unpaid_manufacturer` = remaining balance) + a per-PO editable **Amount** input, and
  submits through `bulkCreatePoPayments`.

**Conclusion:** multiple POs (including partial) on one payment is already recorded correctly
today. The only gap versus the desired workflow is the **amount-entry UX**.

## The gap

Today each PO amount is typed by hand. The desired behavior is a single payment-level
**Full / Partial** choice:

- **Full** → each selected PO is paid its full remaining balance.
- **Partial** → user enters one total; system splits it **equally** across the selected POs;
  each split is then manually adjustable.

## Design (enhance `BulkPaymentModal`, PO mode only)

### 1. Full / Partial toggle
Add a payment-level segmented control (**Full** | **Partial**), visible in PO mode only.

- **Full (default):**
  - On toggling a PO checkbox on, its Amount auto-fills to `unpaid_manufacturer`.
  - Amount inputs are read-only / dimmed (value is derived from the balance).
  - Payment total = sum of checked POs' remaining balances.
- **Partial:**
  - Reveal a single **"Total payment"** numeric input.
  - When the total is entered **or** the checked set changes, split the total **equally**
    across all checked POs and write each share into that PO's Amount field.
  - Every Amount field stays **freely editable**. Editing one field does **not**
    auto-rebalance the others (predictable, no surprise recalculation).

### 2. Validation (warn, don't hard-block, except the zero rule)
- Running total shown: *"Allocated $X of $Y"* (Y = Total payment in Partial mode; sum of
  balances in Full mode).
- **Block submit** if any checked PO has amount ≤ 0.
- **Warn only** if, in Partial mode, the sum of per-PO amounts ≠ the entered total.
- **Warn only** if a PO's amount exceeds its remaining balance (overpay / prepayment is
  allowed).

### 3. Submit (unchanged)
Checked ids + amounts → `dataEntry.bulkCreatePoPayments(...)`. `bank_fee` remains a single
payment-level field (already applied to the first row by Flask).

### 4. Discoverability
Rename the **"Bulk Pay"** button to **"Pay Multiple POs"** for clarity. Keep it as a separate
button next to **New Payment** (do not merge into the New Payment modal).

## Out of scope (YAGNI)
- Any BigQuery / Cube / Flask change.
- Shipment-mode behavior changes (leave as-is).
- Proportional / weighted auto-rebalance when editing a split.
- Adding PO lines to an already-recorded payment (existing-payment flow).
- Per-PO Full/Partial toggles (decided: one toggle for the whole payment).

## Affected files
- `dashboard-react/src/components/supply/BulkPaymentModal.tsx` — add toggle, total input,
  equal-split logic, Full-mode prefill/read-only, running-total + warnings.
- `dashboard-react/src/pages/SupplyPage.tsx` — rename the "Bulk Pay" button label.

## Acceptance criteria
1. In PO mode, a **Full / Partial** toggle is present; Full is the default.
2. **Full:** checking POs auto-fills each amount to its remaining balance; amounts are not
   hand-editable; submit records one payment with each PO paid its balance.
3. **Partial:** entering a Total splits it equally across checked POs; each split is editable;
   changing the checked set re-splits the current Total.
4. A running "Allocated $X of $Y" indicator is visible.
5. Submit is blocked when any checked PO amount ≤ 0; sum-mismatch and overpay produce
   warnings only.
6. On submit, exactly one `payment_id` is created with one row per checked PO and the correct
   per-PO amount (verified in `DE_VENDOR_PAYMENTS` / Payments tab).
7. Bank fee is recorded once for the payment.
