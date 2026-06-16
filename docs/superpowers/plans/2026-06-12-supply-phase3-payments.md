# Supply Page — Phase 3 (Payments) Implementation Plan

> REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Reuse the proven Phase 1/2 patterns (commits for POs `85bd889…` and shipments `889014a…`): helper-extraction + JSON-twin (backend), drawer-from-modal + SupplyPage override layer (frontend), `dataEntry` over `apiFetch`, strict parity, raw input only. Commit on the current shared branch (`feat/owned-negatives-coacher` as of writing — verify at start; no new branch). Live verification of writes is authorized.

**Goal:** Make the Supply page's Payments tab the editable replacement for the Flask payment screens (list, detail, create single, edit/delete, add/delete line) + the two bulk-entry flows, via Flask JSON. Preserve `generate_payment_id`, `sync_shipment_paid_status`, `auto_close_received_shipments`.

## Audit summary (Payments)
- **Table:** `DE_VENDOR_PAYMENTS`. **No existing `/api/payment*` JSON routes** — all HTML today (unlike shipments).
- **`SupplyPaymentRow`:** `payment_id, payment_date, payment_amount, bank_fee, total_amount, currency, payment_method, vendor_name, purchase_order_id, shipment_id, notes`.
- **Helpers:** `insert_payment(data)→(errors,payment_id)` (1609), `get_payment_details` (4336), `update_payment` (4362), `generate_payment_id` (398, meaningful `PAY_YYYYMMDD_VENDOR_PRODUCT[_MMM_YYYY][_NNN]`), `add_payment_line` (4476). Vendor can be multi (joined). Links to PO and/or shipment (both optional — standalone adjustment allowed; amount ≠ 0 required; vendor required).
- **Auto-logic on insert/edit:** `generate_payment_id` (when vendor+date and no id); after a payment write the HTML routes call `sync_shipment_paid_status(...)` + `auto_close_received_shipments()` — REPLICATE exactly (read the `new_payment`/`update_payment`/`delete` routes to see which ids they sync).
- **Form fields (`payment_form.html`):** `payment_date` (req), `payment_amount` (req, ≠0), `bank_fee` (default 0), `currency` (LOV CURRENCY), `payment_method` (LOV PAYMENT_METHOD, req), `vendor_name` (radio SYLVIA/ANNA/JENNA, req), `purchase_order_id` (optional link), `shipment_id` (optional hidden link), `notes`.
- **Bulk flows (HTML):** `/payments/bulk-new` (`bulk_new_payments` 2799) and `/payments/bulk-po-new` (`bulk_po_payments` 2921) — multi-record entry (pay several shipments / several POs at once). Read both to learn their payload + per-row logic.
- **Frontend baseline:** Supply `PaymentsTable` (read-only, Cube `data.supply_payments`); `PODetailDrawer`/`ShipmentDetailDrawer` already show linked payments read-only.

## Tasks
### P3-1 — Backend: `GET /api/payment/<id>` detail JSON
Wrap `get_payment_details` (read it for shape) into a JSON route mirroring `api_shipment_get`/`api_po_get` (`_ser` date handling, 404 if None, no `@login_required`). py_compile + live curl.

### P3-2 — Backend: payment JSON twins (single)
Extract helpers from the HTML routes and add JSON twins, reusing the Phase 1/2 error pattern (`'; '.join(...)`, try/except→500, `clear_data_cache()`):
- `POST /api/payments` → `insert_payment` (body: payment_date, payment_amount, bank_fee, currency, payment_method, vendor_name, purchase_order_id?, shipment_id?, notes) → `{success, payment_id}`. MUST fire the SAME `sync_shipment_paid_status`/`auto_close` the HTML `new_payment` route does.
- `POST /api/payment/<id>/update` → `update_payment`.
- `DELETE /api/payment/<id>` → extract delete helper (+ its sync_shipment_paid_status for the affected shipment).
- `POST /api/payment/<id>/lines` (add) + `DELETE /api/payment/<id>/lines/<line_id>` if payments have lines (check `add_payment_line`/`delete_payment_line`; some payments are line-based across multiple POs). Mirror exactly.
Rewire the HTML routes to call the helpers (preserve flashes/redirects). py_compile + live round-trip (create→GET→update→delete, verify `sync_shipment_paid_status` flips the linked shipment's is_paid as expected).

### P3-3 — Frontend: `dataEntry` payment methods (Vitest TDD)
Add `getPayment(id)`, `createPayment(body)`, `updatePayment(id, body)`, `deletePayment(id)`, (+ line methods if applicable), and bulk methods (P3-6). Append tests mirroring the PO/shipment cases. `npx vitest run`.

### P3-4 — Frontend: `NewPaymentModal`
Mirror `NewShipmentModal`. Fields per `payment_form.html`: vendor (radio/segmented SYLVIA/ANNA/JENNA, req), payment_date (req), payment_amount (req, ≠0), bank_fee, currency (LOV), payment_method (LOV, req), optional PO link (searchable — reuse `/api/orders` or a PO picker) and/or shipment link, notes. Send raw input only (server makes the id). Inline error banner; keep form on error.

### P3-5 — Frontend: `PaymentDetailDrawer` + wire Payments tab
Mirror `ShipmentDetailDrawer` + the Phase 1/2 override layer: `paymentOverrides`/`deletedPaymentIds`/`effectivePayments`/`mapPaymentDetailToRows`, "New Payment" toolbar button, per-row "View details" → drawer. Editable header (amount, bank_fee, method, currency, vendor, notes, links) → `updatePayment`; delete payment (in-component confirm) → `deletePayment`; after writes refetch + `onChanged`; `busyRef` guard; UTC-safe dates. Keep table on Cube.

### P3-6 — Bulk payment flows
Read `bulk_new_payments` (2799) and `bulk_po_payments` (2921). Add JSON twins `POST /api/payments/bulk` and `POST /api/payments/bulk-po` wrapping their extracted logic (each creates multiple payments + fires sync). Frontend: a `BulkPaymentModal` (mirrors the bulk forms — a grid of rows). If the bulk UI is large, it MAY be split to its own follow-up — note in report. Live-verify a 2-row bulk create then clean up.

### P3-7 — E2E + parity sign-off
Playwright `supply-payments.spec.ts` (write-only, run by Ori): create→edit→delete round-trip, marker-scoped. Parity checklist: all fields + LOVs + vendor radio, generate_payment_id format, sync_shipment_paid_status effect, bulk flows. Append to a Phase 3 verification doc.

## Out of scope
Costs report (Phase 4), Flask HTML removal (Phase 5).
