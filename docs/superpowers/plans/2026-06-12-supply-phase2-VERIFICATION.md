# Supply Phase 2 (Shipments) — Verification & Parity Sign-off

**Branch:** `feat/owned-negatives-coacher` (Phase 2 commits `889014a` → `b29d98e`)
**Status:** Code-complete. Backend **live-verified** + drawer **browser-smoked** this session. Remaining: full manual parity walk + running the E2E.

## Already verified this session (2026-06-16)
- **Backend live round-trip** (real BigQuery, throwaway markers, cleaned up): create shipment → `GET /api/shipment/<id>` (auto-ETA AIR +10 = 2026-06-26 ✓) → `PUT` line `quantity_shipped=25` (header `total_quantity` recalc to 25 ✓) → delete line → delete shipment (gone ✓). Other-PO-style auto-logic (`generate_id('SHP')`, ETA, total_quantity recalc) confirmed.
- **Browser smoke** (Shipments tab): "New Shipment" button + per-row "View details" present; the `ShipmentDetailDrawer` loads real Flask data (SHP_247e2775be83: deliverer ANNA, AWD_SLOW_SEA, line Purple Box qty 560 / cost 1098, Financials, Delete Shipment), editable line inputs render, no console errors after the getOpenPOs fix.
- **Bug found + fixed (`cea21f9`):** `/api/open-pos` returns `{success, data:[...]}`; `getOpenPOs()` returned the wrapper so the drawer + NewShipmentModal crashed on `.find/.map`. Now unwraps `.data`. (Fix covers both components.)
- **Parity confirmed:** deliverer dropdown filters `SUPPLIER` LOV by `attr1_value == 'Deliverer'` (matches `shipment_form.html`).

## Remaining manual checks (you / a sandbox)
Dev servers up: Cube :4000, Flask :5050 (debug auto-reloads app.py), Vite :5173. To smoke the UI, mint a JWT with the data-entry-app `CUBEJS_API_SECRET` (use `data-entry-app/venv/bin/python`) and `localStorage.setItem('dashboard_token', …)`.

- [ ] **Create via New Shipment modal** end-to-end in the browser: header fields, allocation picker caps quantity at each PO line's `remaining_quantity`, submit → shipment appears in the table (override layer).
- [ ] **Edit** a line qty + allocated_cost in the drawer → persists (check BigQuery), header total_quantity recalcs.
- [ ] **Add line** from open-PO picker; **delete line**; **edit header** (status/dates/costs/tracking/notes/deliverer); **delete shipment** → row disappears and does NOT reappear (ghost-row guard).
- [ ] **Cost allocation by cubic feet** matches the old Flask app for a multi-line shipment (server-side; spot-check `allocated_cost` per line).
- [ ] **auto-close**: a paid shipment past ETA flips to RECEIVED (existing server logic; confirm unaffected).
- [ ] Run the E2E: confirm the 4 TODO selectors in `tests/e2e/supply-shipments.spec.ts` against the live DOM (first run `--headed`), then `npx playwright test tests/e2e/supply-shipments.spec.ts`. Mutates real data — sandbox or clean up the `E2E_*` row.

## Known Phase-2 deltas (acceptable; revisit if needed)
- New Shipment doesn't show in the table until override seeds it (same pattern as POs).
- `unpaid_to_shipment` in an overridden row is carried from the prior Cube row (the Flask detail lacks payment aggregates) — exact for edits that don't change payments; a brand-new shipment has none yet.
- Bulk shipment operations not migrated (out of scope).

## Branch note
All Phase 1 + Phase 2 work is on `feat/owned-negatives-coacher` (interleaved with the concurrent coacher session per Ori's decision). `feat/offseason-forecast` is behind and missing the `47e67be` ProductSelect fix — reconcile before relying on it.
