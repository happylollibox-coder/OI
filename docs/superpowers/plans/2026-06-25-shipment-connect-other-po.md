# Connect Other PO to Shipment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the New Shipment modal connect one or more existing Other POs (service/misc POs) to a shipment and roll their amounts into the shipment's cubic-feet landed-cost allocation; allow creating a new Other PO inline.

**Architecture:** A new junction table `DE_SHIPMENT_OTHER_PO` links shipment↔other_po. The Flask `insert_shipment` adds `SUM(linked Other PO total_amount)` into the existing `total_cost` that drives per-line `allocated_cost` (so all downstream landed-cost numbers update for free). The edit-recalc, detail GET, and delete paths are updated to keep the link consistent. The React modal gets a multi-select Other PO section backed by a pure summary util, plus a nested reuse of `NewOtherPOModal` for inline creation.

**Tech Stack:** BigQuery (DDL + DML), Flask 3 (`data-entry-app/app.py`, `config.py`), React 19 + TypeScript + Tailwind 4 (`dashboard-react/`), Vitest, Playwright.

**Spec:** `docs/superpowers/specs/2026-06-25-shipment-connect-other-po-design.md`

**Conventions for this plan:**
- All BigQuery DML against the live dataset (`onyga-482313.OI`) — there is no Python unit-test harness for `app.py`; backend tasks use explicit `bq`/`python` verification commands.
- All frontend network calls use `apiFetch` (never raw `fetch`).
- Dashboard TS commits use `--no-verify` (pre-existing lint/tsc debt in unrelated files; see project memory).
- Branch: `feat/owned-negatives-coacher` (current). Commit after each task.

---

## File Structure

| File | Create/Modify | Responsibility |
|---|---|---|
| `scripts/bigquery/tables/DE/DE_SHIPMENT_OTHER_PO.sql` | Create | Junction table DDL |
| `config.yaml` | Modify | Register the new BQ object |
| `data-entry-app/config.py` | Modify | `SHIPMENT_OTHER_PO_TABLE` / `BASE_SHIPMENT_OTHER_PO` constants |
| `data-entry-app/app.py` | Modify | create (insert + junction + validation), edit-recalc, detail GET, delete cascade |
| `dashboard-react/src/utils/otherPoSummary.ts` | Create | Pure summary helper (sum + currency detection) |
| `dashboard-react/src/utils/otherPoSummary.test.ts` | Create | Unit tests for the helper |
| `dashboard-react/src/utils/dataEntry.ts` | Modify | `other_po_ids` input + `connected_other_pos` detail types |
| `dashboard-react/src/components/supply/NewShipmentModal.tsx` | Modify | Connected Other POs section + nested create + submit payload |
| `dashboard-react/src/components/supply/ShipmentDetailDrawer.tsx` | Modify | Read-only connected Other POs display |
| `dashboard-react/tests/e2e/supply-shipments.spec.ts` | Modify | E2E coverage for connecting an Other PO |

---

## Task 1: Create the junction table `DE_SHIPMENT_OTHER_PO`

**Files:**
- Create: `scripts/bigquery/tables/DE/DE_SHIPMENT_OTHER_PO.sql`
- Modify: `config.yaml` (tables section, after the `DE_OTHER_PO` entry at line ~800)
- Modify: `data-entry-app/config.py`

- [ ] **Step 1: Write the DDL file**

Create `scripts/bigquery/tables/DE/DE_SHIPMENT_OTHER_PO.sql`:

```sql
-- =============================================
-- OI Database Project - DE_SHIPMENT_OTHER_PO Table
-- =============================================
-- Junction table linking shipments to Other POs (service/misc POs).
-- A shipment can connect multiple Other POs; their total_amount is rolled
-- into the shipment's landed-cost allocation.
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.DE_SHIPMENT_OTHER_PO` (
  link_id      STRING NOT NULL,   -- UUID, e.g. SOP_abc123
  shipment_id  STRING NOT NULL,   -- FK → DE_MANUFACTURER_SHIPMENTS
  other_po_id  STRING NOT NULL,   -- FK → DE_OTHER_PO
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),

  PRIMARY KEY (link_id) NOT ENFORCED
);
```

- [ ] **Step 2: Create the table in the live dataset**

Run:
```bash
cd /Users/ori/Develop/OI
bq query --use_legacy_sql=false --project_id=onyga-482313 < scripts/bigquery/tables/DE/DE_SHIPMENT_OTHER_PO.sql
```
Expected: `Created onyga-482313.OI.DE_SHIPMENT_OTHER_PO` (or success with no errors).

- [ ] **Step 3: Verify the table exists with the right schema**

Run:
```bash
bq show --schema --format=prettyjson onyga-482313:OI.DE_SHIPMENT_OTHER_PO
```
Expected: JSON listing `link_id`, `shipment_id`, `other_po_id`, `created_at`.

- [ ] **Step 4: Register in `config.yaml`**

In `config.yaml`, immediately after the `DE_OTHER_PO` table entry (ends at line ~800), add:

```yaml
  - name: "DE_SHIPMENT_OTHER_PO"
    description: "Junction linking shipments to Other POs (service costs rolled into landed cost)"
    type: "data_entry"
    source_files: ["scripts/bigquery/tables/DE/DE_SHIPMENT_OTHER_PO.sql"]
```

- [ ] **Step 5: Add config constants in `data-entry-app/config.py`**

After line 9 (`SHIPMENT_LINES_TABLE = ...`), add:
```python
SHIPMENT_OTHER_PO_TABLE = f'{PROJECT_ID}.{DATASET_ID}.DE_SHIPMENT_OTHER_PO'
```
After line 19 (`BASE_SHIPMENT_LINES = 'DE_SHIPMENT_LINES'`), add:
```python
BASE_SHIPMENT_OTHER_PO = 'DE_SHIPMENT_OTHER_PO'
```

- [ ] **Step 6: Import the constant in `app.py`**

In `data-entry-app/app.py` line 332, add `SHIPMENT_OTHER_PO_TABLE` to the `from config import ...` list:
```python
from config import PROJECT_ID, DATASET_ID, ORDERS_TABLE, OTHER_PO_TABLE, SHIPMENTS_TABLE, SHIPMENT_LINES_TABLE, SHIPMENT_OTHER_PO_TABLE, PAYMENTS_TABLE, PRODUCTS_TABLE, COSTS_HISTORY_TABLE, ALERTS_TABLE, PHRASE_NEGATIVES_TABLE
```

- [ ] **Step 7: Verify the import loads**

Run:
```bash
cd /Users/ori/Develop/OI/data-entry-app && /usr/bin/python3 -c "import config; print(config.SHIPMENT_OTHER_PO_TABLE, config.BASE_SHIPMENT_OTHER_PO)"
```
Expected: `onyga-482313.OI.DE_SHIPMENT_OTHER_PO DE_SHIPMENT_OTHER_PO`

- [ ] **Step 8: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tables/DE/DE_SHIPMENT_OTHER_PO.sql config.yaml data-entry-app/config.py data-entry-app/app.py
git commit -m "feat(bq): DE_SHIPMENT_OTHER_PO junction (shipment <-> other PO)"
```

---

## Task 2: Flask — roll connected Other POs into landed cost on create

**Files:**
- Modify: `data-entry-app/app.py` — `insert_shipment` (def at line 1394), `api_create_shipment` (line 2536)

- [ ] **Step 1: Extend `insert_shipment` signature**

Change the def at `data-entry-app/app.py:1394` from:
```python
def insert_shipment(data, lines):
```
to:
```python
def insert_shipment(data, lines, other_po_ids=None):
```

- [ ] **Step 2: Add the Other PO sum into `total_cost`**

In `insert_shipment`, find (line ~1410-1411):
```python
    # total_cost = shipment cost + amazon commission (used for allocation)
    total_cost = (cost_shipped or 0) + amazon_commission
```
Replace with:
```python
    # --- Roll connected Other PO amounts into the allocable cost ---
    other_po_ids = [str(pid) for pid in (other_po_ids or []) if pid]
    other_po_total = 0.0
    if other_po_ids:
        opo_ph = ', '.join([f'@opo_{i}' for i in range(len(other_po_ids))])
        opo_q = f"SELECT COALESCE(SUM(total_amount), 0) AS s FROM `{OTHER_PO_TABLE}` WHERE other_po_id IN ({opo_ph})"
        opo_params = [bigquery.ScalarQueryParameter(f'opo_{i}', 'STRING', pid) for i, pid in enumerate(other_po_ids)]
        opo_rows = list(client.query(opo_q, job_config=bigquery.QueryJobConfig(query_parameters=opo_params)).result())
        other_po_total = float(opo_rows[0].s) if opo_rows else 0.0

    # total_cost = shipment cost + amazon commission + connected Other POs (used for allocation)
    total_cost = (cost_shipped or 0) + amazon_commission + other_po_total
```

- [ ] **Step 3: Insert junction rows after the lines insert**

In `insert_shipment`, find the lines-insert error check (line ~1576-1577):
```python
    lines_job.result()
    if lines_job.errors:
        return lines_job.errors, shipment_id
```
Immediately after it, insert:
```python
    # --- Insert connected Other PO junction rows ---
    if other_po_ids:
        link_rows = [{
            'link_id': generate_id('SOP'),
            'shipment_id': shipment_id,
            'other_po_id': pid,
        } for pid in other_po_ids]
        sop_table_ref = client.get_table(SHIPMENT_OTHER_PO_TABLE)
        sop_job_config = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            autodetect=False,
            schema=sop_table_ref.schema,
        )
        sop_job = client.load_table_from_json(link_rows, sop_table_ref, job_config=sop_job_config)
        sop_job.result()
        if sop_job.errors:
            return sop_job.errors, shipment_id
```

- [ ] **Step 4: Validate + pass `other_po_ids` in `api_create_shipment`**

In `api_create_shipment` (line 2536), find (line ~2582-2585):
```python
        if not lines:
            return jsonify({'success': False, 'error': 'At least one shipment line is required (must provide PO ID and product)'}), 400

        errors, shipment_id = insert_shipment(header_data, lines)
```
Replace with:
```python
        if not lines:
            return jsonify({'success': False, 'error': 'At least one shipment line is required (must provide PO ID and product)'}), 400

        # Validate connected Other POs (rolled into landed cost) — reject unknown ids
        other_po_ids = [str(x) for x in (data.get('other_po_ids') or []) if x]
        if other_po_ids:
            chk_ph = ', '.join([f'@id_{i}' for i in range(len(other_po_ids))])
            chk_q = f"SELECT other_po_id FROM `{OTHER_PO_TABLE}` WHERE other_po_id IN ({chk_ph})"
            chk_params = [bigquery.ScalarQueryParameter(f'id_{i}', 'STRING', pid) for i, pid in enumerate(other_po_ids)]
            found = {r.other_po_id for r in client.query(chk_q, job_config=bigquery.QueryJobConfig(query_parameters=chk_params)).result()}
            missing = [pid for pid in other_po_ids if pid not in found]
            if missing:
                return jsonify({'success': False, 'error': f"Unknown Other PO id(s): {', '.join(missing)}"}), 400

        errors, shipment_id = insert_shipment(header_data, lines, other_po_ids=other_po_ids)
```

- [ ] **Step 5: Syntax-check the module**

Run:
```bash
cd /Users/ori/Develop/OI/data-entry-app && /usr/bin/python3 -c "import ast; ast.parse(open('app.py').read()); print('OK')"
```
Expected: `OK`

- [ ] **Step 6: Integration verify (live Flask) — create a shipment with one Other PO**

Start Flask locally per project memory (`fact_oi_admin_page_needs_flask_5050`):
```bash
cd /Users/ori/Develop/OI/data-entry-app && env -u CUBEJS_API_SECRET PORT=5050 ../venv/bin/python app.py &
```
Then pick a real open PO line + product_id and a real `other_po_id`:
```bash
# Grab one open PO line and one Other PO id for the payload
curl -s localhost:5050/api/open-pos | /usr/bin/python3 -m json.tool | head -40
curl -s localhost:5050/api/other_po | /usr/bin/python3 -m json.tool | head -20
```
POST a shipment (substitute the real `purchase_order_id`, `product_id`, `other_po_id`, and a known `quantity`):
```bash
curl -s -X POST localhost:5050/api/shipments -H 'Content-Type: application/json' \
  -d '{"shipment_date":"2026-06-25","deliverer":"","shipment_type":"AIR","cost_shipped":100,"lines":[{"purchase_order_id":"<PO_ID>","product_id":<PID>,"quantity":10}],"other_po_ids":["<OPO_ID>"]}'
```
Expected: `{"success": true, "shipment_id": "SHP_..."}`.

- [ ] **Step 7: Verify the junction row + cost rolled in**

```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 \
'SELECT * FROM `onyga-482313.OI.DE_SHIPMENT_OTHER_PO` WHERE shipment_id = "<SHP_ID>"'
bq query --use_legacy_sql=false --project_id=onyga-482313 \
'SELECT SUM(allocated_cost) AS allocated FROM `onyga-482313.OI.DE_SHIPMENT_LINES` WHERE shipment_id = "<SHP_ID>"'
```
Expected: one junction row; `allocated` ≈ `cost_shipped (100) + Other PO total_amount` (not just 100). Note the `<SHP_ID>` for Task 4 verification, then it can be deleted after Task 5.

- [ ] **Step 8: Verify the unknown-id guard**

```bash
curl -s -X POST localhost:5050/api/shipments -H 'Content-Type: application/json' \
  -d '{"shipment_date":"2026-06-25","deliverer":"","shipment_type":"AIR","cost_shipped":1,"lines":[{"purchase_order_id":"<PO_ID>","product_id":<PID>,"quantity":1}],"other_po_ids":["OPO_does_not_exist"]}'
```
Expected: HTTP 400, `{"success": false, "error": "Unknown Other PO id(s): OPO_does_not_exist"}`.

- [ ] **Step 9: Commit**

```bash
cd /Users/ori/Develop/OI
git add data-entry-app/app.py
git commit -m "feat(api): roll connected Other POs into shipment landed cost on create"
```

---

## Task 3: Flask — preserve Other PO cost in edit-recalc

**Files:**
- Modify: `data-entry-app/app.py` — shipment update recalc block (line ~4199-4207)

- [ ] **Step 1: Add the Other PO sum into the recalc `total_cost`**

In `api_shipment_update`, find (line ~4207):
```python
        total_cost = new_cost_shipped + new_amazon_commission
```
Replace with:
```python
        total_cost = new_cost_shipped + new_amazon_commission
        # Keep connected Other PO amounts in the allocation so editing cost does not drop them
        opo_sum_q = f"""
            SELECT COALESCE(SUM(o.total_amount), 0) AS s
            FROM `{SHIPMENT_OTHER_PO_TABLE}` j
            JOIN `{OTHER_PO_TABLE}` o ON j.other_po_id = o.other_po_id
            WHERE j.shipment_id = @shipment_id
        """
        opo_sum_jc = bigquery.QueryJobConfig(query_parameters=[bigquery.ScalarQueryParameter("shipment_id", "STRING", shipment_id)])
        opo_sum_rows = list(client.query(opo_sum_q, job_config=opo_sum_jc).result())
        total_cost += float(opo_sum_rows[0].s) if opo_sum_rows else 0.0
```

- [ ] **Step 2: Syntax-check the module**

Run:
```bash
cd /Users/ori/Develop/OI/data-entry-app && /usr/bin/python3 -c "import ast; ast.parse(open('app.py').read()); print('OK')"
```
Expected: `OK`

- [ ] **Step 3: Integration verify — edit cost keeps the service portion**

Using the `<SHP_ID>` from Task 2 (which has a connected Other PO), edit `cost_shipped` to 200:
```bash
curl -s -X POST "localhost:5050/api/shipment/<SHP_ID>/update" -H 'Content-Type: application/json' \
  -d '{"cost_shipped":200}'
bq query --use_legacy_sql=false --project_id=onyga-482313 \
'SELECT SUM(allocated_cost) AS allocated FROM `onyga-482313.OI.DE_SHIPMENT_LINES` WHERE shipment_id = "<SHP_ID>"'
```
Expected: `allocated` ≈ `200 + Other PO total_amount` — NOT 200. (Confirms the service portion survived the recalc.)

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add data-entry-app/app.py
git commit -m "feat(api): keep connected Other PO cost in shipment edit recalc"
```

---

## Task 4: Flask — return connected Other POs in shipment detail

**Files:**
- Modify: `data-entry-app/app.py` — `get_shipment_details` (def line 4018, before `return shipment` at line ~4054)

- [ ] **Step 1: Add `connected_other_pos` to the detail dict**

In `get_shipment_details`, find (line ~4052-4054):
```python
        shipment['lines'] = lines

    return shipment
```
Replace with:
```python
        shipment['lines'] = lines

    # Connected Other POs (services rolled into landed cost) — read-only for the drawer
    opo_q = f"""
    SELECT j.other_po_id, o.supplier_name, o.service_type, o.total_amount, o.currency
    FROM `{SHIPMENT_OTHER_PO_TABLE}` j
    LEFT JOIN `{OTHER_PO_TABLE}` o ON j.other_po_id = o.other_po_id
    WHERE j.shipment_id = @shipment_id
    """
    opo_rows = client.query(opo_q, job_config=job_config).result()
    shipment['connected_other_pos'] = [dict(r) for r in opo_rows]

    return shipment
```

> Note: `job_config` here is the one declared at the top of `get_shipment_details` (binds `@shipment_id`). The selected columns contain no DATE/TIMESTAMP fields, so the existing `_ser` serializer in `api_shipment_get` passes them through safely.

- [ ] **Step 2: Syntax-check the module**

Run:
```bash
cd /Users/ori/Develop/OI/data-entry-app && /usr/bin/python3 -c "import ast; ast.parse(open('app.py').read()); print('OK')"
```
Expected: `OK`

- [ ] **Step 3: Integration verify — detail returns the connection**

```bash
curl -s "localhost:5050/api/shipment/<SHP_ID>" | /usr/bin/python3 -m json.tool | grep -A12 connected_other_pos
```
Expected: a `connected_other_pos` array with one object (`other_po_id`, `supplier_name`, `service_type`, `total_amount`, `currency`).

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add data-entry-app/app.py
git commit -m "feat(api): return connected_other_pos in shipment detail"
```

---

## Task 5: Flask — cascade-delete junction rows with the shipment

**Files:**
- Modify: `data-entry-app/app.py` — `delete_shipment_record` (def line 6360)

- [ ] **Step 1: Delete junction rows before the header**

In `delete_shipment_record`, find the lines-delete block:
```python
        client.query(query_lines, job_config=job_config).result()

        # Delete header
```
Replace with:
```python
        client.query(query_lines, job_config=job_config).result()

        # Delete connected Other PO links
        query_links = f"""
        DELETE FROM `{SHIPMENT_OTHER_PO_TABLE}`
        WHERE shipment_id = @shipment_id
        """
        client.query(query_links, job_config=job_config).result()

        # Delete header
```

- [ ] **Step 2: Syntax-check the module**

Run:
```bash
cd /Users/ori/Develop/OI/data-entry-app && /usr/bin/python3 -c "import ast; ast.parse(open('app.py').read()); print('OK')"
```
Expected: `OK`

- [ ] **Step 3: Integration verify — delete cascades**

Delete the test shipment from Task 2 and confirm no orphan links:
```bash
curl -s -X DELETE "localhost:5050/api/shipment/<SHP_ID>"
bq query --use_legacy_sql=false --project_id=onyga-482313 \
'SELECT COUNT(*) AS orphans FROM `onyga-482313.OI.DE_SHIPMENT_OTHER_PO` WHERE shipment_id = "<SHP_ID>"'
```
Expected: delete returns `{"success": true}`; `orphans` = 0. (If delete reports a streaming-buffer error, wait 5-10 min and retry — known limitation.)

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add data-entry-app/app.py
git commit -m "feat(api): cascade-delete DE_SHIPMENT_OTHER_PO with shipment"
```

---

## Task 6: Frontend — pure `otherPoSummary` helper (TDD)

**Files:**
- Create: `dashboard-react/src/utils/otherPoSummary.ts`
- Test: `dashboard-react/src/utils/otherPoSummary.test.ts`

- [ ] **Step 1: Write the failing test**

Create `dashboard-react/src/utils/otherPoSummary.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { summarizeConnectedOtherPos, type OtherPoLite } from './otherPoSummary';

const ALL: OtherPoLite[] = [
  { other_po_id: 'OPO_A', supplier_name: 'Freightco', service_type: 'Freight', total_amount: 100, currency: 'USD' },
  { other_po_id: 'OPO_B', supplier_name: 'CertLab', service_type: 'Certification', total_amount: 50.5, currency: 'USD' },
  { other_po_id: 'OPO_C', supplier_name: 'EuroShip', service_type: 'Customs', total_amount: 30, currency: 'EUR' },
];

describe('summarizeConnectedOtherPos', () => {
  it('returns zeros for an empty selection', () => {
    const s = summarizeConnectedOtherPos(ALL, []);
    expect(s).toEqual({ total: 0, count: 0, currencies: [], hasNonUsd: false });
  });

  it('sums selected USD amounts without flagging non-USD', () => {
    const s = summarizeConnectedOtherPos(ALL, ['OPO_A', 'OPO_B']);
    expect(s.total).toBeCloseTo(150.5);
    expect(s.count).toBe(2);
    expect(s.currencies).toEqual(['USD']);
    expect(s.hasNonUsd).toBe(false);
  });

  it('flags non-USD and lists distinct currencies', () => {
    const s = summarizeConnectedOtherPos(ALL, ['OPO_A', 'OPO_C']);
    expect(s.total).toBeCloseTo(130);
    expect(s.count).toBe(2);
    expect(s.currencies.sort()).toEqual(['EUR', 'USD']);
    expect(s.hasNonUsd).toBe(true);
  });

  it('ignores ids not present in the list and missing/zero amounts', () => {
    const withNull: OtherPoLite[] = [
      ...ALL,
      { other_po_id: 'OPO_D', supplier_name: null, service_type: null, total_amount: null, currency: null },
    ];
    const s = summarizeConnectedOtherPos(withNull, ['OPO_A', 'OPO_MISSING', 'OPO_D']);
    expect(s.total).toBeCloseTo(100);
    expect(s.count).toBe(2); // OPO_A + OPO_D matched; OPO_MISSING ignored
    expect(s.currencies).toEqual(['USD']); // OPO_D null currency defaults to USD
    expect(s.hasNonUsd).toBe(false);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /Users/ori/Develop/OI/dashboard-react && npx vitest run src/utils/otherPoSummary.test.ts
```
Expected: FAIL — cannot resolve `./otherPoSummary`.

- [ ] **Step 3: Write the implementation**

Create `dashboard-react/src/utils/otherPoSummary.ts`:
```ts
/**
 * Pure helpers for the "Connected Other POs" section of the New Shipment modal.
 * Summarizes the selected Other POs whose amounts roll into the shipment's
 * landed cost. Currency handling is face-value (no FX); non-USD picks are flagged.
 */
export interface OtherPoLite {
  other_po_id: string;
  supplier_name?: string | null;
  service_type?: string | null;
  total_amount?: number | null;
  currency?: string | null;
}

export interface ConnectedOtherPoSummary {
  /** Sum of selected total_amount (face value). */
  total: number;
  /** Number of selected Other POs that matched the list. */
  count: number;
  /** Distinct currencies among the selection (defaults missing to 'USD'). */
  currencies: string[];
  /** True if any selected currency is not USD. */
  hasNonUsd: boolean;
}

export function summarizeConnectedOtherPos(
  all: OtherPoLite[],
  selectedIds: string[],
): ConnectedOtherPoSummary {
  const selected = new Set(selectedIds);
  const picked = all.filter((o) => selected.has(o.other_po_id));
  let total = 0;
  const currencies = new Set<string>();
  for (const o of picked) {
    total += Number(o.total_amount) || 0;
    currencies.add((o.currency || 'USD').toUpperCase());
  }
  const currencyList = [...currencies];
  return {
    total,
    count: picked.length,
    currencies: currencyList,
    hasNonUsd: currencyList.some((c) => c !== 'USD'),
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd /Users/ori/Develop/OI/dashboard-react && npx vitest run src/utils/otherPoSummary.test.ts
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/utils/otherPoSummary.ts dashboard-react/src/utils/otherPoSummary.test.ts
git commit -m "feat(dash): otherPoSummary util (sum + currency detection) + tests"
```

---

## Task 7: Frontend — extend dataEntry types

**Files:**
- Modify: `dashboard-react/src/utils/dataEntry.ts`

- [ ] **Step 1: Add `other_po_ids` to `CreateShipmentInput`**

In `dataEntry.ts`, in `CreateShipmentInput` (line 45-58), add a field just above `lines: ShipmentLineInput[];`:
```ts
  other_po_ids?: string[];
  lines: ShipmentLineInput[];
```

- [ ] **Step 2: Add a `ConnectedOtherPo` type and field on `ShipmentDetail`**

In `dataEntry.ts`, immediately above `export interface ShipmentDetail {` (line 77), add:
```ts
export interface ConnectedOtherPo {
  other_po_id: string;
  supplier_name: string | null;
  service_type: string | null;
  total_amount: number | null;
  currency: string | null;
}
```
Then inside `ShipmentDetail`, add a field just above `[k: string]: unknown;`:
```ts
  connected_other_pos?: ConnectedOtherPo[];
  [k: string]: unknown;
```

- [ ] **Step 3: Type-check passes for this file**

Run:
```bash
cd /Users/ori/Develop/OI/dashboard-react && npx tsc --noEmit -p tsconfig.json 2>&1 | grep "dataEntry.ts" || echo "no new dataEntry.ts errors"
```
Expected: `no new dataEntry.ts errors`.

- [ ] **Step 4: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/utils/dataEntry.ts
git commit -m "feat(dash): dataEntry types for connected Other POs"
```

---

## Task 8: Frontend — Connected Other POs section in NewShipmentModal

**Files:**
- Modify: `dashboard-react/src/components/supply/NewShipmentModal.tsx`

- [ ] **Step 1: Add imports**

At the top of `NewShipmentModal.tsx`, update the lucide import (line 15) to add icons and add two new imports:
```tsx
import { X, Truck, Search, Plus, Tag, AlertTriangle } from 'lucide-react';
import {
  dataEntry,
  type CreateShipmentInput,
  type LovItem,
} from '../../utils/dataEntry';
import { NewOtherPOModal } from './NewOtherPOModal';
import { summarizeConnectedOtherPos, type OtherPoLite } from '../../utils/otherPoSummary';
```

- [ ] **Step 2: Add state for the Other PO section**

In the component, after the PO allocation state block (after line 86 `const [search, setSearch] = useState('');`), add:
```tsx
  // ── Connected Other POs (services rolled into landed cost) ──
  const [otherPos, setOtherPos] = useState<OtherPoLite[]>([]);
  const [otherPosLoading, setOtherPosLoading] = useState(true);
  const [selectedOtherPoIds, setSelectedOtherPoIds] = useState<string[]>([]);
  const [otherPoSearch, setOtherPoSearch] = useState('');
  const [showNewOtherPo, setShowNewOtherPo] = useState(false);
```

- [ ] **Step 3: Add a loader + a refresh helper for Other POs**

After the "Load open PO lines" effect (after line 160, the closing of that `useEffect`), add:
```tsx
  // ── Load existing Other POs ──
  const loadOtherPos = useCallback(() => {
    setOtherPosLoading(true);
    dataEntry
      .listOtherPOs()
      .then((raw) => {
        setOtherPos(raw as unknown as OtherPoLite[]);
      })
      .catch(() => {
        // Leave empty — user can still create one
      })
      .finally(() => setOtherPosLoading(false));
  }, []);

  useEffect(() => {
    loadOtherPos();
  }, [loadOtherPos]);
```

- [ ] **Step 4: Add derived summary + toggle helper**

After `const totalAllocated = ...` (line 176), add:
```tsx
  // ── Derived: connected Other PO summary ──
  const otherPoSummary = summarizeConnectedOtherPos(otherPos, selectedOtherPoIds);

  const filteredOtherPos = otherPoSearch.trim()
    ? otherPos.filter((o) => {
        const q = otherPoSearch.toLowerCase();
        return (
          (o.supplier_name ?? '').toLowerCase().includes(q) ||
          (o.service_type ?? '').toLowerCase().includes(q) ||
          o.other_po_id.toLowerCase().includes(q)
        );
      })
    : otherPos;

  const toggleOtherPo = useCallback((id: string) => {
    setSelectedOtherPoIds((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id],
    );
  }, []);
```

- [ ] **Step 5: Include `other_po_ids` in the submit payload**

In `handleSubmit`, in the `CreateShipmentInput` object (line ~249-267), add the field just above `lines: activeLines.map(...)`:
```tsx
        other_po_ids: selectedOtherPoIds.length ? selectedOtherPoIds : undefined,
        lines: activeLines.map((r) => ({
```
Then add `selectedOtherPoIds` to the `handleSubmit` `useCallback` dependency array (the array starting at line ~278), inserting it after `allRows,`:
```tsx
      allRows,
      selectedOtherPoIds,
```

- [ ] **Step 6: Render the Connected Other POs section**

In the JSX, find the PO-line allocation comment (line ~540):
```tsx
          {/* ── PO-line Allocation Picker ── */}
```
Immediately BEFORE it, insert this block:
```tsx
          {/* ── Connected Other POs (services → landed cost) ── */}
          <div>
            <div className="flex items-center justify-between mb-2 gap-3">
              <span className={labelCls}>Connected Other POs (services)</span>
              <button
                type="button"
                onClick={() => setShowNewOtherPo(true)}
                className="flex items-center gap-1 px-2.5 py-1 rounded-lg border border-border text-[11px] font-medium text-muted hover:text-heading hover:bg-white/5 transition-colors"
              >
                <Plus size={12} /> New Other PO
              </button>
            </div>

            {/* Search */}
            <div className="relative mb-2">
              <Search
                size={12}
                className="absolute left-3 top-1/2 -translate-y-1/2 text-faint pointer-events-none"
              />
              <input
                type="text"
                value={otherPoSearch}
                onChange={(e) => setOtherPoSearch(e.target.value)}
                placeholder="Search by supplier, service, or Other PO ID…"
                className="w-full rounded-lg border border-border bg-surface pl-8 pr-3 py-2 text-xs text-heading focus:outline-none focus:ring-1 focus:ring-purple-500/50"
              />
            </div>

            {/* List */}
            <div
              className="rounded-lg border border-border overflow-hidden"
              style={{ maxHeight: 220, overflowY: 'auto', scrollbarWidth: 'thin', scrollbarColor: 'var(--color-border) transparent' }}
            >
              {otherPosLoading ? (
                <div className="flex items-center justify-center py-6 text-xs text-muted">
                  Loading Other POs…
                </div>
              ) : filteredOtherPos.length === 0 ? (
                <div className="flex items-center justify-center py-6 text-xs text-muted">
                  {otherPoSearch ? 'No Other POs match your search.' : 'No Other POs yet — create one above.'}
                </div>
              ) : (
                <ul className="divide-y divide-border">
                  {filteredOtherPos.map((o) => {
                    const checked = selectedOtherPoIds.includes(o.other_po_id);
                    return (
                      <li key={o.other_po_id}>
                        <label
                          className={`flex items-center gap-3 px-3 py-2 cursor-pointer transition-colors ${
                            checked ? 'bg-purple-500/5' : 'hover:bg-white/3'
                          }`}
                        >
                          <input
                            type="checkbox"
                            checked={checked}
                            onChange={() => toggleOtherPo(o.other_po_id)}
                            className="w-3.5 h-3.5 rounded accent-purple-500 shrink-0"
                          />
                          <Tag size={12} className="text-purple-400 shrink-0" />
                          <span className="flex-1 min-w-0">
                            <span className="block text-xs text-heading font-medium truncate">
                              {o.supplier_name ?? '—'}
                              <span className="ml-1.5 text-[10px] text-muted font-normal">
                                {o.service_type ?? ''}
                              </span>
                            </span>
                            <span className="block text-[10px] text-faint font-mono truncate">
                              {o.other_po_id}
                            </span>
                          </span>
                          <span className="text-xs font-mono text-heading shrink-0">
                            {(Number(o.total_amount) || 0).toLocaleString(undefined, {
                              minimumFractionDigits: 2,
                              maximumFractionDigits: 2,
                            })}{' '}
                            <span className="text-[10px] text-faint">{o.currency ?? 'USD'}</span>
                          </span>
                        </label>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>

            {/* Summary */}
            {otherPoSummary.count > 0 && (
              <div className="mt-2 flex items-center justify-between gap-3">
                {otherPoSummary.hasNonUsd && (
                  <span className="flex items-center gap-1 text-[10px] text-warning">
                    <AlertTriangle size={11} />
                    Mixed currencies — amounts rolled at face value
                  </span>
                )}
                <span className="ml-auto text-[11px] font-mono text-purple-400 font-semibold">
                  +{otherPoSummary.total.toLocaleString(undefined, {
                    minimumFractionDigits: 2,
                    maximumFractionDigits: 2,
                  })}{' '}
                  added to landed cost
                </span>
              </div>
            )}
          </div>

```

- [ ] **Step 7: Render the nested NewOtherPOModal**

In the JSX, find the outermost closing of the modal — the last lines of the component (the `</div>` that closes the backdrop, right before the final `);`). Immediately before that final closing `</div>`, add:
```tsx
        {showNewOtherPo && (
          <NewOtherPOModal
            onClose={() => setShowNewOtherPo(false)}
            onSaved={(otherPoId) => {
              setShowNewOtherPo(false);
              setSelectedOtherPoIds((prev) =>
                prev.includes(otherPoId) ? prev : [...prev, otherPoId],
              );
              loadOtherPos();
            }}
          />
        )}
```

> The nested modal renders its own `fixed inset-0 z-50` backdrop and stops click propagation, so it stacks above the shipment modal. Selecting the newly created id before the list refresh ensures it stays checked once `loadOtherPos` returns.

- [ ] **Step 8: Type-check + lint the file**

Run:
```bash
cd /Users/ori/Develop/OI/dashboard-react && npx tsc --noEmit -p tsconfig.json 2>&1 | grep "NewShipmentModal.tsx" || echo "no new NewShipmentModal.tsx errors"
```
Expected: `no new NewShipmentModal.tsx errors`.

- [ ] **Step 9: Visual smoke check in dev**

Start the dev servers (Vite + Flask :5050) and open the Supply → Shipments → New Shipment modal. Confirm:
- A "Connected Other POs (services)" section appears above the PO-line allocation.
- The list shows existing Other POs with supplier · service · amount · currency.
- Checking items shows the "+ $X added to landed cost" summary; checking a non-USD one shows the amber warning.
- "+ New Other PO" opens the Other PO form stacked on top; saving it returns and auto-checks the new row.

(Use the preview workflow / browser to verify and capture a screenshot.)

- [ ] **Step 10: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/components/supply/NewShipmentModal.tsx
git commit -m "feat(dash): connect Other POs in New Shipment modal (+ inline create)" --no-verify
```

---

## Task 9: Frontend — show connected Other POs in ShipmentDetailDrawer

**Files:**
- Modify: `dashboard-react/src/components/supply/ShipmentDetailDrawer.tsx`

- [ ] **Step 1: Render a read-only connected section between Lines and Financials**

In `ShipmentDetailDrawer.tsx`, find the end of the Lines section and start of Financials (lines ~598-600):
```tsx
            </div>
          )}

          {/* ── Financials ── */}
```
Insert this block between the Lines section's closing `)}` (line 598) and the `{/* ── Financials ── */}` comment (line 600):
```tsx

          {/* ── Connected Other POs (read-only) ── */}
          {!loading && !loadError && (detail?.connected_other_pos?.length ?? 0) > 0 && (
            <div>
              <div className="text-[10px] text-faint uppercase tracking-wider font-semibold mb-1.5 flex items-center gap-1.5">
                <Tag size={11} /> Connected Other POs ({detail?.connected_other_pos?.length})
              </div>
              <div className="rounded-lg border border-border overflow-hidden divide-y divide-border">
                {(detail?.connected_other_pos ?? []).map((o) => (
                  <div key={o.other_po_id} className="flex items-center gap-3 px-3 py-2">
                    <Tag size={12} className="text-purple-400 shrink-0" />
                    <div className="flex-1 min-w-0">
                      <div className="text-xs text-heading font-medium truncate">
                        {o.supplier_name ?? '—'}
                        <span className="ml-1.5 text-[10px] text-muted font-normal">{o.service_type ?? ''}</span>
                      </div>
                      <div className="text-[10px] text-faint font-mono truncate">{o.other_po_id}</div>
                    </div>
                    <div className="text-xs font-mono text-heading shrink-0">
                      {fmtFull$(Number(o.total_amount) || 0)}
                      <span className="ml-1 text-[10px] text-faint">{o.currency ?? 'USD'}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

```

> `Tag` must be imported from `lucide-react` and `fmtFull$` is already defined/used in this file (see the Financials section). If `Tag` is not yet in the lucide import line, add it.

- [ ] **Step 2: Ensure `Tag` is imported**

Run:
```bash
cd /Users/ori/Develop/OI/dashboard-react && grep -n "from 'lucide-react'" src/components/supply/ShipmentDetailDrawer.tsx
```
If `Tag` is not in that import list, add it. Then verify `fmtFull$` exists:
```bash
grep -n "fmtFull\$" src/components/supply/ShipmentDetailDrawer.tsx | head -1
```
Expected: at least one match (the helper is already used in Financials).

- [ ] **Step 3: Type-check the file**

Run:
```bash
cd /Users/ori/Develop/OI/dashboard-react && npx tsc --noEmit -p tsconfig.json 2>&1 | grep "ShipmentDetailDrawer.tsx" || echo "no new ShipmentDetailDrawer.tsx errors"
```
Expected: `no new ShipmentDetailDrawer.tsx errors`.

- [ ] **Step 4: Visual smoke check**

Open a shipment that has a connected Other PO (e.g. one created via the modal in Task 8) in the drawer. Confirm a "Connected Other POs (N)" read-only block renders between Lines and Financials with supplier · service · amount · currency.

- [ ] **Step 5: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/src/components/supply/ShipmentDetailDrawer.tsx
git commit -m "feat(dash): show connected Other POs in shipment detail drawer" --no-verify
```

---

## Task 10: E2E — connect an Other PO when creating a shipment

**Files:**
- Modify: `dashboard-react/tests/e2e/supply-shipments.spec.ts`

> This spec mutates real data and is gated behind `SUPPLY_E2E=1` + live Flask/Cube/Vite. It is run manually, not in CI.

- [ ] **Step 1: Add a focused test that connects an Other PO**

In `supply-shipments.spec.ts`, after the existing `test('Shipment create → edit → delete round-trip', ...)` block, add a new test:
```ts
test('New Shipment modal can connect an Other PO and roll it into landed cost', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByText('Weekly Summary')).toBeVisible({ timeout: 10_000 });
  await page.getByRole('button', { name: 'SUPPLY' }).click();
  await expect(page.getByText('Supply Chain')).toBeVisible({ timeout: 8_000 });
  await page.getByRole('button', { name: /^Shipments/ }).click();
  await page.getByRole('button', { name: /New Shipment/ }).click();

  // The Connected Other POs section renders.
  await expect(page.getByText('Connected Other POs (services)')).toBeVisible({ timeout: 8_000 });

  // Select the first Other PO checkbox in that section, if any exist.
  const firstOtherPo = page.locator('input[type="checkbox"][class*="accent-purple-500"]').first();
  if (await firstOtherPo.count()) {
    await firstOtherPo.check();
    // The landed-cost summary appears.
    await expect(page.getByText(/added to landed cost/)).toBeVisible();
  }
});
```

- [ ] **Step 2: Run the new test against the live stack (manual)**

With Vite (:5173), Flask (:5050), and Cube (:4000) running:
```bash
cd /Users/ori/Develop/OI/dashboard-react && SUPPLY_E2E=1 npx playwright test tests/e2e/supply-shipments.spec.ts -g "connect an Other PO"
```
Expected: PASS (or skipped only if `CI` is set without `SUPPLY_E2E`).

- [ ] **Step 3: Commit**

```bash
cd /Users/ori/Develop/OI
git add dashboard-react/tests/e2e/supply-shipments.spec.ts
git commit -m "test(e2e): connect Other PO in New Shipment modal"
```

---

## Final verification

- [ ] **Run the full unit suite** — `cd dashboard-react && npx vitest run` → existing tests + the 4 new `otherPoSummary` tests pass.
- [ ] **End-to-end manual round-trip** — create a shipment with 1 product line ($100 cost) + 1 Other PO ($X): confirm `SUM(allocated_cost) ≈ 100 + X`; open the drawer and confirm the Connected Other POs block; edit `cost_shipped`→ confirm the service portion survives; delete → confirm no orphan junction rows.
- [ ] **Update project memory** — append/update the supply-page migration memory with this feature (new `DE_SHIPMENT_OTHER_PO` table; shipment landed cost now includes connected Other POs; deploy state of cube/Flask/dashboard).
- [ ] **Deploy note** — Flask change requires redeploy of `data-entry-forms` via `data-entry-app/cloudbuild.yaml`; dashboard requires a build+deploy. Hold deploy until Ori confirms (per project deploy conventions).
