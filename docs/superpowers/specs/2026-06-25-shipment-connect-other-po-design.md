# Connect Other PO to Shipment — Design Spec

**Date:** 2026-06-25
**Status:** Approved design, pending implementation plan
**Goal:** When creating a manufacturer shipment on the Supply page, let the user connect one or more existing **Other POs** (service/misc POs — freight, customs, certification, sampling, photography), and **roll their amounts into the shipment's landed cost** so per-unit COGS reflects those service costs. Allow creating a new Other PO inline without leaving the shipment modal.

---

## 1. Decisions (locked with Ori)

| Decision | Choice |
|---|---|
| What "other PO" means | An **Other PO** (`DE_OTHER_PO`) — a service/misc PO, not another product PO. The allocation table already supports multiple product POs. |
| Cost behavior | **Roll into landed cost.** The connected Other POs' amounts are added to the shipment's allocable cost and spread across product lines by cubic feet, exactly like `cost_shipped`. |
| Cardinality | **Many Other POs per shipment.** |
| Source | **Link existing + create new inline.** Pick from existing Other POs; also create a new one inline (reusing `NewOtherPOModal`). |
| Storage | **New junction table `DE_SHIPMENT_OTHER_PO`** (Approach A). Mirrors `DE_SHIPMENT_LINES`; leaves `DE_OTHER_PO` untouched as an independent payable. |
| Amount source | **Live read** of `DE_OTHER_PO.total_amount` at allocation time (no snapshot column). Correcting an Other PO's amount and re-saving the shipment re-flows the landed cost. |
| Currency | **Face value, USD assumed.** No FX conversion (none exists in `app.py`). Show each Other PO's currency; warn on non-USD picks. Real FX is out of scope. |

---

## 2. Why fold into `allocated_cost` (the key lever)

Today, shipment allocable cost is:

```
total_cost = cost_shipped + amazon_commission
```

…spread across product lines **by cubic feet** into `DE_SHIPMENT_LINES.allocated_cost` (`data-entry-app/app.py:1517`). Every downstream landed-cost / per-unit-COGS number reads from `allocated_cost` (e.g. `app.py:565,581,597`).

By extending that one formula to:

```
total_cost = cost_shipped + amazon_commission + SUM(linked Other PO total_amount)
```

the connected service costs flow into per-unit landed cost **automatically** — no Cube schema, no `V_SUPPLY_*` view, and no frontend cost-math changes. This is why Approach A folds the amount into `total_cost` rather than tracking a parallel cost field.

---

## 3. Architecture

```
NewShipmentModal ──other_po_ids[]──> POST /api/shipments
  (also opens NewOtherPOModal nested for inline create → POST /api/other_po)

insert_shipment():
  total_cost = cost_shipped + amazon_commission + SUM(DE_OTHER_PO.total_amount for other_po_ids)
  → cubic-feet allocation into DE_SHIPMENT_LINES.allocated_cost (unchanged)
  → INSERT one DE_SHIPMENT_OTHER_PO row per other_po_id

Edit recalc (app.py:4199): same total_cost extension so editing cost_shipped
  does not drop the service portion.

Shipment detail GET (app.py:4018): returns connected_other_pos[] for display.
```

All `/api/*` routes are already protected by `protect_api`; the new endpoint(s) inherit auth by default (see `architecture/API_AUTH.md`). All frontend calls use `apiFetch`, never raw `fetch`.

---

## 4. Schema — `DE_SHIPMENT_OTHER_PO`

New junction table, DDL in `scripts/bigquery/tables/DE/DE_SHIPMENT_OTHER_PO.sql`, registered in `config.yaml`.

```sql
CREATE OR REPLACE TABLE `onyga-482313.OI.DE_SHIPMENT_OTHER_PO` (
  link_id      STRING NOT NULL,   -- UUID, e.g. SOP_abc123
  shipment_id  STRING NOT NULL,   -- FK → DE_MANUFACTURER_SHIPMENTS
  other_po_id  STRING NOT NULL,   -- FK → DE_OTHER_PO
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (link_id) NOT ENFORCED
);
```

No `rolled_amount`/`currency` snapshot columns — amount and currency are read live from `DE_OTHER_PO` so corrections propagate.

> **Note:** the live `DE_MANUFACTURER_SHIPMENTS` schema already carries `deliverer` and `amazon_commission` columns that the repo DDL omits (DDL is stale). Confirm the live junction creation against the live dataset; do not assume the repo DDL is authoritative.

---

## 5. Backend (Flask `data-entry-app/app.py`)

### 5.1 Create — `api_create_shipment` / `insert_shipment`
- Accept `other_po_ids: string[]` in the JSON body; pass through to `insert_shipment`.
- In `insert_shipment`, before cubic-feet allocation: query `SELECT other_po_id, total_amount, currency FROM DE_OTHER_PO WHERE other_po_id IN (...)`; add `SUM(total_amount)` to `total_cost`.
- After header + lines insert, insert one `DE_SHIPMENT_OTHER_PO` row per valid `other_po_id` (`generate_id('SOP')`).
- Product lines remain **required** (Other POs are supplementary cost, not a substitute for a physical line).
- Ignore unknown `other_po_id`s silently? **No** — return a 400 listing any ids not found in `DE_OTHER_PO`, to avoid silently dropping cost.

### 5.2 Edit recalc — `api_shipment_update` (`app.py:4199`)
- When recomputing `allocated_cost`, add `SUM(DE_OTHER_PO.total_amount)` for the shipment's linked Other POs (join via `DE_SHIPMENT_OTHER_PO`) into `total_cost`. Without this, any cost edit would silently strip the service portion.

### 5.3 Detail GET — `get_shipment_details` (`app.py:4018`)
- Add `connected_other_pos`: `[{ other_po_id, supplier_name, service_type, total_amount, currency }]` via join `DE_SHIPMENT_OTHER_PO → DE_OTHER_PO`. Serialized in `api_shipment_get`.

### 5.4 Delete
- `delete_shipment` must also delete `DE_SHIPMENT_OTHER_PO` rows for the shipment (cascade) — no orphan links.

---

## 6. Frontend (`dashboard-react/`)

### 6.1 `utils/dataEntry.ts`
- `CreateShipmentInput` gains `other_po_ids?: string[]`.
- `ShipmentDetail` gains `connected_other_pos?: { other_po_id; supplier_name; service_type; total_amount; currency }[]`.
- Reuse existing `listOtherPOs()` to populate the picker.

### 6.2 `components/supply/NewShipmentModal.tsx`
New **"Connected Other POs (services)"** section, below Notes / above PO-line allocation:
- Loads existing Other POs via `dataEntry.listOtherPOs()`.
- Searchable, **multi-select** list — each row: `supplier_name · service_type · total_amount currency`. Selected ids tracked in `useState<string[]>`.
- **"+ New Other PO"** button opens the existing `NewOtherPOModal` nested (stacked); on its `onSaved(otherPoId)`, refresh the list and auto-select the new id. Reuse — no inline re-implementation of the form.
- Running summary: **"+ $X added to landed cost"** = sum of selected `total_amount`. If any selected Other PO's `currency !== 'USD'`, show an amber warning chip ("mixed currencies — amounts rolled at face value").
- On submit, include `other_po_ids` in the `createShipment` payload.

### 6.3 `components/supply/ShipmentDetailDrawer.tsx`
- **Display only:** render `connected_other_pos` as a small read-only list (supplier · service · amount · currency). Add/remove-on-edit is **out of scope** for this iteration.

---

## 7. Out of scope (YAGNI)
- FX/currency conversion of Other PO amounts (face value only).
- Add/remove Other PO links from the detail drawer after creation (display only).
- Reverse view ("which shipments is this Other PO linked to") on the Other PO detail.

---

## 8. Testing
- **Unit (Vitest):** `NewShipmentModal` — selecting Other POs updates the "added to landed cost" summary; non-USD pick shows the warning; `other_po_ids` included in submit payload.
- **E2E (Playwright, `tests/e2e/supply-shipments.spec.ts`):** create a shipment with a connected Other PO; assert the link persists and the per-line `allocated_cost` increased by the Other PO's share.
- **Backend manual/integration:** create shipment with `other_po_ids`; verify `total_cost` includes the OPO sum, junction rows exist, edit-recalc preserves the service portion, delete cascades.

---

## 9. Implementation order
1. BigQuery: `DE_SHIPMENT_OTHER_PO` DDL + `config.yaml` registration (create live table).
2. Flask: create (insert + junction + validation), edit recalc, detail GET, delete cascade.
3. Frontend: `dataEntry.ts` types, `NewShipmentModal` section + nested create, `ShipmentDetailDrawer` display.
4. Tests: unit + E2E + backend verification.
