# Supply Phase 3 (Payments) — Verification & Parity Sign-off

**Branch:** `feat/owned-negatives-coacher` (commits `81bf0ee`→`0272eac`). Code-complete; backend live-verified + payment drawer browser-smoked.

## Verified this session (2026-06-16)
- **Backend single-payment live round-trip** (real BigQuery): `POST /api/payments` → `GET /api/payment/<id>` → `POST .../update` → `DELETE` → 404. `generate_payment_id`, `sync_shipment_paid_status`, `auto_close_received_shipments` preserved (sync fires inside `insert_payment` + on delete).
- **Browser smoke** (Payments tab): "New Payment" + per-row "View details" present; `PaymentDetailDrawer` loads real Flask data (PAY_20260611_SYLVIA…: vendor SYLVIA, $13,975.06, Account Payoneer, linked PO, bank fee $126.92), editable header, Delete Payment. No console errors.
- **Bulk backend**: `POST /api/payments/bulk` (shipments) + `/api/payments/bulk-po` (POs) — shared payment_id, per-row amounts, bank_fee on first, sync preserved; live-tested JSON 400 on bad body.

## Remaining manual checks (you / sandbox)
Servers: Cube :4000, Flask :5050 (debug auto-reload), Vite :5173. Mint JWT via `data-entry-app/venv/bin/python` with `CUBEJS_API_SECRET`; `localStorage.setItem('dashboard_token',…)`.
- [ ] **Create via New Payment modal** end-to-end (vendor radio, method/currency LOV, optional PO/shipment link) → appears in table (override layer), correct `generate_payment_id` format.
- [ ] **Edit** drawer header (amount/method/vendor/notes) → persists (check BigQuery).
- [ ] **Delete** payment → row disappears, does not reappear; if linked to a shipment, that shipment's `is_paid` re-syncs.
- [ ] **Bulk Pay modal** (NOT browser-smoked yet): toggle Shipments/POs, check rows + amounts, submit → N payments created with one shared payment_id; confirm `sync_shipment_paid_status` flipped the paid shipments. (New bulk payments show after Cube refresh — no override-seeding for bulk.)
- [ ] Run E2E `tests/e2e/supply-payments.spec.ts` (4 TODO selectors to confirm `--headed`; needs a PAYMENT_METHOD LOV entry). Mutates real data.

## Known Phase-3 deltas (acceptable)
- Bulk payments don't override-seed the table (appear on next Cube refresh) — single payments do.
- Payment "lines" delete is keyed by shipment_id/po_id (a payment row's link), mirroring the Flask model — there's no separate line_id.
- Optional shipment link in New Payment is a plain text input (Flask used a hidden field); PO link uses a datalist autocomplete.

## Branch note
All Phases 1–3 on `feat/owned-negatives-coacher` (interleaved with the concurrent coacher session). `feat/offseason-forecast` is behind, missing `47e67be`. Reconcile before relying on it.
