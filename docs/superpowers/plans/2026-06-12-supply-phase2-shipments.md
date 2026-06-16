# Supply Page — Phase 2 (Shipments) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development to execute task-by-task with two-stage review. Follow the **proven Phase 1 patterns** in the already-merged code (commits `85bd889`…`47e67be`): helper-extraction + JSON-twin for backend, drawer-from-modal + SupplyPage override-layer for frontend, `dataEntry` client over `apiFetch`, strict parity, no client-computed values.

**Goal:** Make the Supply page's Shipments tab the full editable replacement for the Flask shipment screens (list, detail, create with PO-line allocation, edit header/lines, delete), reading/writing via the Flask JSON API. Preserve all server-side auto-logic.

**Tech stack / conventions:** identical to Phase 1 (see `2026-06-12-supply-phase1-pos.md`). Node at `/Users/ori/.nvm/versions/node/v22.22.1/bin/`. Backend verify = `py_compile` + live curl (authorized). Frontend = Vitest + tsc + eslint, then browser smoke.

**References:** spec `2026-06-12-supply-page-migration-design.md`; audit `2026-06-12-data-entry-audit.md`; Phase 1 plan (pattern source).

---

## Audit summary (Shipments domain)

**Tables:** `DE_MANUFACTURER_SHIPMENTS` (header) + `DE_SHIPMENT_LINES` (one row per PO-line allocation: `shipment_id, purchase_order_id, product_id, quantity_shipped, allocated_cost, num_cartons, cubic_feet_per_carton, total_cubic_feet`).

**`SupplyShipmentRow` (types.ts):** `shipment_id, shipment_date, estimated_arrival_date, tracking_number, shipment_type, total_quantity, cost_shipped, is_paid, paid_date, shipment_status, notes, line_count, total_allocated_cost, total_quantity_shipped, products_list, unpaid_to_shipment, is_open`.

**Header fields (`shipment_form.html`):** `shipment_date` (req), `deliverer` (LOV `SUPPLIER`, req), `shipment_type` (LOV `SHIPMENT_TYPE`), `tracking_number`, `cost_shipped`, `amazon_commission` (default 0), `kg_price`, `shipment_status` (LOV `SHIPMENT_STATUS`), `notes`, `is_paid`/`paid_date`. Lines: pick open POs (`get_open_pos_for_shipment`), set `quantities[]` per (po_id, product_id), capped at the PO line's remaining qty.

**Server-side auto-logic (must stay in Flask):**
- `generate_id('SHP')` shipment id.
- **ETA auto-calc** from `shipment_type` when not provided: SLOW_SEA +33, FAST_SEA +27, AIR +10 days from `shipment_date`.
- `total_cost = cost_shipped + amazon_commission`; **cost allocated across lines by cubic feet** (product `package_cubic_feet` × cartons).
- `total_quantity` summed from lines.
- `sync_shipment_paid_status(ids)` + `auto_close_received_shipments()` on writes.
- `clear_data_cache()` after writes.

**Endpoints:**
| Path | Status |
|---|---|
| `POST /api/shipments` (create, `api_create_shipment`→`insert_shipment`) | **exists** |
| `POST /api/shipment/<id>/update` (`api_update_shipment`→`update_shipment`) | **exists** (login_required removed in `47e67be`) |
| `GET /api/shipment/<id>` (detail) | **gap — add** (wrap `get_shipment_details`, 3908) |
| `GET /api/shipments` (list) | **gap — add** (wrap `get_all_shipments`) — though table may stay on Cube (decide like Phase 1) |
| `GET /api/open-pos` (for the allocation picker) | **exists** (`/api/open-pos`, 6968) — verify shape |
| delete shipment (`delete_shipment`, 4280, HTML) | **gap — JSON twin** |
| line add/update/delete (`add_po_line`/line update 5911/delete 5970, HTML) | **gap — JSON twins** |
| bulk delete/update (3669/3710/3796, HTML) | defer unless needed |

**Frontend baseline:** Supply `ShipmentsTable` (read-only, Cube `data.supply_shipments`); `ShipmentEngine.tsx` already calls Flask shipment-plan endpoints (reference for patterns); `PODetailDrawer` already shows linked shipments read-only.

---

## File structure
- Backend: extend `data-entry-app/app.py` — helpers `get_shipment_details` (exists), extract `delete_shipment_record`, `add_shipment_line`/`update_shipment_line`/`delete_shipment_line` from the HTML routes; add JSON routes `GET /api/shipment/<id>`, `DELETE /api/shipment/<id>`, `POST/PUT/DELETE /api/shipment/<id>/lines[/<line_id>]`.
- Frontend: extend `src/utils/dataEntry.ts` with shipment methods; create `src/components/supply/NewShipmentModal.tsx` (with PO-line allocation picker), `src/components/supply/ShipmentDetailDrawer.tsx`; wire the Shipments tab in `SupplyPage.tsx` (override layer mirroring Phase 1's `poOverrides`/`deletedPOIds` → `shipmentOverrides`/`deletedShipmentIds`).

---

## Tasks

### Task 1 — Backend: `GET /api/shipment/<id>` detail JSON
Wrap `get_shipment_details(shipment_id)` (3908) into a JSON route mirroring Phase 1 Task 1 (`api_po_get`), serializing dates via the same `_ser` pattern. Returns `{shipment, lines, ...}`. No `@login_required`. py_compile + live curl on a real shipment id.

### Task 2 — Backend: shipment delete + line JSON twins
Extract the bodies of `delete_shipment` (4280), the shipment-line add (`add_po_line` for shipments, 5786), line update (5911), line delete (5970) into helpers returning `(errors[, id])`; rewire the HTML routes to call them (preserve flashes/redirects); add JSON twins: `DELETE /api/shipment/<id>`, `POST /api/shipment/<id>/lines`, `PUT /api/shipment/<id>/lines/<line_id>`, `DELETE /api/shipment/<id>/lines/<line_id>`. Use the same `'; '.join(...)` error serialization + `try/except`→500 pattern as Phase 1 Task 3. Verify `sync_shipment_paid_status` fires on line changes. py_compile + live round-trip on a throwaway shipment.

### Task 3 — Frontend: extend `dataEntry` client (Vitest TDD)
Add `getShipment(id)`, `createShipment(body)`, `updateShipment(id, body)`, `deleteShipment(id)`, `addShipmentLine(id, body)`, `updateShipmentLine(id, lineId, body)`, `deleteShipmentLine(id, lineId)`, `getOpenPOs()`. Mirror Phase 1 Task 5: tests first (URL/method/body/error-normalization/encoding), then implement over `json()`/`apiFetch`. `npx vitest run`.

### Task 4 — Frontend: `NewShipmentModal` with PO-line allocation
Mirror `NewPOModal`. Header fields per `shipment_form.html` (deliverer = LOV `SUPPLIER`, shipment_type = LOV `SHIPMENT_TYPE`, status = LOV `SHIPMENT_STATUS`, dates, costs, tracking, notes, is_paid). Allocation picker: load open POs via `getOpenPOs()`, let the user set `quantity` per (purchase_order_id, product_id) capped at remaining qty; send `lines: [{purchase_order_id, product_id, quantity, cartons}]` to `createShipment`. Do NOT compute ETA/allocated_cost client-side (server does). Inline error banner; keep form on error. tsc + eslint.

### Task 5 — Frontend: `ShipmentDetailDrawer` + wire Shipments tab
Mirror Phase 1 Task 9. Drawer loads via `getShipment(id)`; inline-edit header (status, dates, costs, tracking, notes) → `updateShipment`; line qty edit → `updateShipmentLine`; add line (open-PO picker) → `addShipmentLine`; delete line → `deleteShipmentLine`; delete shipment (in-component confirm) → `deleteShipment`; after each write refetch + `onChanged`. Wire SupplyPage Shipments tab: keep the table on Cube (`data.supply_shipments`), add a `shipmentOverrides`/`deletedShipmentIds` override layer + `mapShipmentDetailToRows`, a "New Shipment" toolbar button, and a per-row "View details" control opening the drawer. Reuse the exact override pattern from Phase 1 (clear override on delete; UTC-safe date parse; in-flight write guard).

### Task 6 — E2E + parity sign-off
Mirror Phase 1 Task 10: a Playwright `supply-shipments.spec.ts` (create→edit→delete round-trip, marker-scoped) — write-only, run live by Ori. Parity checklist: all header fields + LOVs, allocation capping, ETA auto-calc, cost allocation, paid-status sync, delete. Append results to the Phase 1 VERIFICATION doc or a Phase 2 sibling.

---

## Known design decisions (carry from Phase 1)
- Table/summary stay on **Cube**; detail/create/edit via **Flask**; override layer for instant reflection; Other reads analytics from Cube.
- All `/api/*` via `apiFetch` (JWT). New routes carry **no `@login_required`** (global gate covers them — see the `47e67be` lesson; double-check no shipment `/api/*` route keeps the legacy decorator).
- Send raw input only; server owns ids, ETA, allocation, totals, paid-status.

## Out of scope for Phase 2
Bulk shipment operations (unless Ori needs them), Payments (Phase 3), Costs report (Phase 4), Flask HTML removal (Phase 5).
