# Supply Phase 1 (POs) — Live Verification & Parity Sign-off

**Branch:** `feat/supply-phase1-pos` (13 commits, off `30b5864`)
**Status:** Code-complete. All static checks pass (tsc clean, Vitest 190/190, eslint clean on new files). **No live verification run yet** — per decision, subagents never touched production BigQuery. This checklist is for you (Ori) to run before merge.

## Before you start
1. **Restore your parked WIP** when ready: `git stash pop` (stash `supply-phase1-wip-parking` holds the 32 unrelated files I parked at the start — campaign mapping, coacher, negatives, etc.). It is NOT on this branch's commits.
2. A concurrent process modified `scripts/bigquery/views/V_ADS_NEGATIVE_CONFLICTS.sql` mid-session — it's still uncommitted in your tree, untouched by me.
3. Stand up dev servers: Cube (`cd cube && npm run dev` → :4000), Flask (`cd data-entry-app && python app.py` → :5050), Vite (`cd dashboard-react && npm run dev` → :5173).

## A. Backend endpoints (curl against local Flask :5050)
Get a token: `TOKEN=$(curl -s localhost:5050/api/auth/dashboard-token | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")`

- [ ] `GET /api/po/<id>` returns `{po, product_lines, payments, shipments}` with ISO dates and numeric aggregates.
- [ ] `GET /api/lov` returns all sets; `CURRENCY` has exactly one `is_default`; `SERVICE_TYPE` and `SUPPLIER` present.
- [ ] On a **throwaway** PO: `POST /api/po/<id>/header`, `POST /api/po/<id>/lines` (add), `PUT /api/po/<id>/lines/<pid>` (each field: quantity/total_amount/ready_quantity), `DELETE /api/po/<id>/lines/<pid>`, `DELETE /api/po/<id>` — each returns `{success:true}` and the BigQuery rows change as expected. Error responses are plain strings (not `"['...']"`).
- [ ] Other-PO: `GET /api/other_po`, `GET /api/other_po/<id>`, `POST /api/other_po` (confirm `generate_other_po_id` format `PO_YYYYMMDD_VENDOR_SERVICE`), `DELETE /api/other_po/<id>`.
- [ ] **HTML routes still work** (regression): open the live Flask UI, add/edit/delete a PO line and an Other PO via the old forms — same flashes/redirects as before the refactor.

## B. Auto-logic parity (the part you emphasized)
- [ ] New PO id format matches the old app (`PO_YYYYMMDD_MFR[_PRODUCT]_QTY` + dedup suffix).
- [ ] `unit_price` is computed server-side (= amount/qty); never sent by the dashboard.
- [ ] Multi-line PO totals match the old app.
- [ ] `payment_status` default PENDING; currency default = LOV `is_default`.
- [ ] LOV dropdowns (CURRENCY, SERVICE_TYPE, SUPPLIER) populate from `DE_LOV` and preselect defaults where the old form did.
- [ ] Other-PO `payment_status='PENDING'`, `created_at` set, `product_asins` comma-joined.

## C. Dashboard UI (Supply page, PO tab)
- [ ] Table, summary cards, ProductBreakdown still show the rich Cube columns (no regression).
- [ ] "New PO" modal: all `order_form.html` fields present; create → PO appears in the table immediately (override layer).
- [ ] "New Other PO" modal: SERVICE_TYPE/SUPPLIER are dropdowns; CURRENCY preselects default.
- [ ] Open a PO → drawer loads fresh from Flask; edit line qty/amount/ready, save → persists (verify in BigQuery) and drawer + table reflect it.
- [ ] Add line / delete line (delete hidden when one line left); header edit; delete PO (in-component confirm) → row disappears and does NOT reappear (the C1 ghost-row fix).
- [ ] Payments / Shipments / Stock Snapshot tabs unchanged.

## D. Run the E2E
- [ ] Confirm the 4 TODO selectors in `dashboard-react/tests/e2e/supply-pos.spec.ts` against the live DOM (first run `--headed`), then: `cd dashboard-react && npx playwright test tests/e2e/supply-pos.spec.ts`. **This mutates real data** — point it at a sandbox if you have one, or clean up the `E2E_*` marker rows after.

## Known Phase-1 deltas (decided acceptable; revisit if they bother you)
- **Other-PO `product_asins`**: dashboard uses a freeform ASIN tag input vs the old grouped product multi-select (data-compatible; field is optional).
- **Other-PO `total_amount`**: not marked `required` (old form was); 0 allowed.
- **New Other PO** doesn't appear in the table until the next Cube refresh (Other POs render from Cube `supply_other_pos`, not overlaid).
- **`InlineReadyCell`** (ready-qty edit directly in the PO table row) still posts to `/api/po/update_line` directly and doesn't flow through the override layer — functional, but its edit won't optimistically refresh other columns.
- **Duplicate product lines**: line edit/delete is keyed by `product_id` (mirrors the backend's line API). A PO with two lines of the same product can't be edited independently — same constraint as the old app.

## Next phases
Phase 2 (Shipments), 3 (Payments + bulk), 4 (Costs report), 5 (kill Flask HTML) — each gets its own plan when you're ready, following the same helper-extraction + JSON-twin + drawer pattern proven here.
