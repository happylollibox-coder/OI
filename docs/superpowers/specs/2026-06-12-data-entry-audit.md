# Data-Entry App Audit — Reference for Supply Migration

**Date:** 2026-06-12
**Purpose:** Concrete inventory of the Flask data-entry app (`data-entry-app/`) backing the Supply-page migration (see `2026-06-12-supply-page-migration-design.md`). This is the "endpoint/auto-logic audit" deliverable from Phase 0. Per-domain field-level audits are completed when each phase's plan is written; the PO domain (Phase 1) is fully audited here.

---

## Tables (`data-entry-app/config.py`)

| Constant | BigQuery table | Notes |
|---|---|---|
| `ORDERS_TABLE` | `OI.DE_PURCHASE_ORDERS` | **Line-per-row**: a multi-product PO is multiple rows sharing `purchase_order_id` |
| `OTHER_PO_TABLE` | `OI.DE_OTHER_PO` | Non-product POs (services); single row, `other_po_id` PK |
| `SHIPMENTS_TABLE` | `OI.DE_MANUFACTURER_SHIPMENTS` | Shipment header |
| `SHIPMENT_LINES_TABLE` | `OI.DE_SHIPMENT_LINES` | Shipment line items, linked to PO via `purchase_order_id` |
| `PAYMENTS_TABLE` | `OI.DE_VENDOR_PAYMENTS` | Vendor payments; links to PO/shipment |
| `PRODUCTS_TABLE` | `OI.DIM_PRODUCT` | Product master (`product_id` INT64, `asin`, `sku`, `display_name`, `product_name`, `is_active`) |
| `COSTS_HISTORY_TABLE` | `OI.DIM_COSTS_HISTORY` | Cost history (costs report) |
| Other DE tables | `DE_ALERTS`, `DE_PRODUCT_PHRASE_NEGATIVES`, `DE_PLAN_STRATEGY`, `DE_PLAN_ADS_TARGETS`, `DE_SHIPMENT_PLAN`, `DE_SCHEDULED_SHIPMENTS` | Out of Supply scope — already consumed by other dashboard pages |

## Server-side auto-logic (stays in Flask — never reimplemented in React)

| Helper (`app.py`) | Triggered by | Behavior |
|---|---|---|
| `insert_purchase_order(data, product_lines)` (line 998) | PO create | Validates header + lines; resolves product info from `DIM_PRODUCT` (`product_name = sku or display_name or product_name`); computes `unit_price = total_amount / quantity`; generates PO ID `PO_YYYYMMDD_MFR[_PRODUCT]_QTY` with `_N` dedup suffix; inserts one row per line |
| `generate_other_po_id(date, vendor, service)` (line 361) | Other-PO create | Deterministic `PO_YYYYMMDD_VENDOR_SERVICE` with `_NNN` collision suffix |
| `generate_payment_id(...)` (line 392) | Payment create | Meaningful `PAY_YYYYMMDD_VENDOR_PRODUCT[_MMM_YYYY][_NNN]` |
| `generate_id(prefix)` (line 357) | misc | `prefix_<uuid12>` |
| `auto_close_received_shipments()` (line 194) | after payment insert | Flips shipments to `RECEIVED` when ETA passed and paid |
| `sync_shipment_paid_status(ids)` (line 215) | payment/shipment writes | Recomputes `is_paid`/`paid_date` from payment totals vs shipment cost (0.01 tolerance) |
| `get_products()` (line 494, `@cache_result` 600s) | product selects | Cached product hierarchy (parents) |
| `get_po_details(po_id)` (line 762) | PO detail read | Returns `(po, payments, shipments, product_lines)`; `po` includes computed `total_paid`, `total_shipment_cost`, `amount_remaining`, `remaining_quantity_to_ship`, `remaining_shipments_estimated`, `is_paid_in_full` |
| `clear_data_cache()` | after every write | Cache invalidation |

**Rule:** React forms send raw user input only — never client-generated IDs, statuses, unit prices, or computed totals.

## LOVs (`DE_LOV` via `get_lovs()` line 332)
Columns: `lov_set, value_id, value_caption, is_default, attr1_name, attr1_value, attr2_name, attr2_value`. Sets include `CURRENCY`, `SHIPMENT_TYPE`, `SUPPLIER`, payment method, service type. `GET /api/lov/<set>` exists; **gap:** one-shot `GET /api/lov`.

---

## PO domain endpoints (Phase 1)

| Method/Path | Type | Status | Backing logic |
|---|---|---|---|
| `GET /api/orders` | JSON | exists (3022) | PO + Other-PO list, 100 rows |
| `POST /api/po` | JSON | exists (3040) | `insert_purchase_order`; looks up `product_id` by `asin` if needed |
| `POST /api/po/<id>/update-eta` | JSON | exists (3093) | UPDATE `estimated_arrival_date` |
| `GET /api/po/<id>/lines` | JSON | exists (3340) | `get_po_details` → `product_lines` only |
| `POST /api/po/update_line` | JSON | exists (3351) | ready-qty update |
| `GET /po/<id>` | HTML | exists (2140) | `get_po_details` full tuple — **needs JSON twin** |
| `POST /po/<id>/update` | HTML | exists (2160) | `update_purchase_order` header — **needs JSON twin** |
| `POST /orders/new` | HTML | exists (2304) | `insert_purchase_order` (covered by `POST /api/po`) |
| `POST /po/add_line` | HTML | exists (3133) | add line, inherits header — **needs JSON twin** |
| `POST /po/delete_line` | HTML | exists (3225) | delete line (refuses last line) — **needs JSON twin** |
| `POST /po/update_line` | HTML | exists (3269) | update `quantity`/`total_amount`/`ready_quantity` by field — **needs JSON twin (any field)** |
| `POST /po/<id>/delete` | HTML | exists (3350 area) | delete whole PO — **needs JSON twin** |
| `POST /po/bulk-delete` | HTML | exists (3380) | bulk delete — **needs JSON twin** |
| `GET/POST /other_po/new`, `GET /other_po/<id>`, `POST /other_po/<id>/delete` | HTML | exists (2177/2244/2281) | Other-PO CRUD — **needs JSON twins** |

**Gap-fill rule:** extract each HTML route body into a shared helper, leave the HTML route calling it (unchanged), add a JSON route calling the same helper. Auto-logic helpers fire identically in both.

### `DE_PURCHASE_ORDERS` columns (from insert/update code)
`purchase_order_id` STRING, `order_date` DATE, `manufacturer_name` STRING, `product_id` INT64, `product_asin` STRING, `product_name` STRING, `quantity` INT64, `ready_quantity` INT64, `unit_price` FLOAT64, `total_amount` FLOAT64, `currency` STRING, `payment_status` STRING (`PENDING`/`PAID`), `notes` STRING, `adjustments` FLOAT64, `estimated_arrival_date` DATE, `expected_ready_date` DATE.

### `DE_OTHER_PO` columns
`other_po_id`, `order_date`, `service_type`, `supplier_name`, `product_asins` (comma-joined), `total_amount`, `currency`, `payment_status` (default `PENDING`), `notes`, `created_at`.

### PO new-form fields (`order_form.html`)
- Header: `order_date` (required), `manufacturer_name` (required, defaults "SYLVIA"), `currency` (LOV `CURRENCY`, honors `is_default`), `payment_status` (PENDING/PAID), `notes`.
- Lines (repeatable): product (via `_product_select.html`, parent hierarchy), `quantity` (min 1), `amount`. Live PO Total + Total Qty display.

---

## Frontend baseline (`dashboard-react`)

- `SupplyPage.tsx` (1440 lines): tabs `pos | payments | shipments | snapshot`. Reads `data.supply_pos`, `data.supply_other_pos`, `data.supply_payments`, `data.supply_shipments` from `useUnifiedData` (**Cube**, not Flask). Stock snapshot reads Cube `InventorySnapshot` directly.
- `PODetailsModal.tsx` (376 lines): **read-only** detail modal driven by already-loaded Cube rows. Starting point for the editable detail drawer.
- Types already defined in `types.ts`: `SupplyPORow` (998), `SupplyOtherPORow` (1058), `SupplyPaymentRow`, `SupplyShipmentRow`.
- API client: `utils/apiFetch.ts` (from `ff91564`) attaches the dashboard JWT; all `/api/*` calls go through the proxy. **All new Supply code uses `apiFetch`.**
- `ShipmentEngine.tsx` already calls Flask JSON endpoints (`/api/scheduled-shipments`, etc.) — reference pattern for write-then-read.

## Testing reality
- **No Flask pytest harness** (`requirements.txt` has no pytest; only a one-off `test_query.py`). Backend verification = integration: call the new JSON endpoint, confirm BigQuery rows, compare to the Flask HTML route's output.
- **Vitest** for TS unit tests (e.g. `StepAdsPath.test.ts`), run via `npm test`. **Playwright** (Firefox) E2E in `tests/e2e/`.
- Per-phase verification (spec §9): create → edit → delete round-trip on a test record via the React UI, BigQuery row checks, cleanup.
