# Customer Order Baskets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the newly-synced Amazon customer-order feeds into a queryable item-grain fact and a measured same-basket cross-sell signal, so "which products are bought together" stops being an inference from ad attribution and becomes an observation.

**Architecture:** Two Daton source tables (`ListOrder`, `ListOrderItems`) are already exposed as the deployed interface views `V_SRC_ListOrder` and `V_SRC_ListOrderItems`. This plan adds one fact (`FACT_CUSTOMER_ORDER_ITEM`, loaded by a full MERGE that is restatement-safe), one gate view that reports how far the item backfill has actually reached, and two analytical views on top (`V_ORDER_BASKET`, `V_ORDER_CROSS_SELL`). Nothing in this plan modifies `FACT_AMAZON_PERFORMANCE_DAILY` or any existing fact — the order feed is added alongside as an independent source, never as a replacement.

**Tech Stack:** BigQuery Standard SQL (project `onyga-482313`, dataset `OI`, location `US`), `bq` CLI, git.

> **Commit hygiene:** the working tree contains unrelated in-flight work on
> `V_FAMILY_SEAT_REGISTER.sql` and `V_FAMILY_SEAT_REGISTER_acceptance.sql`.
> Never run `git add -A` or `git add .`. Stage only the exact paths each task
> names, and never modify, stash or revert those two files.

---

## Context the engineer needs before starting

Read this section fully. It contains facts that are not derivable from the code and that will cause silent wrong answers if missed.

**The two source views already exist and are deployed.** Do not recreate them. Their files are `scripts/bigquery/interface_views/V_SRC_ListOrder.sql` and `scripts/bigquery/interface_views/V_SRC_ListOrderItems.sql`. Read both file headers before writing anything — they document the traps below.

**Join key is composite.** Always join the two on `(selling_partner_id, amazon_order_id)`, both columns. Only one selling partner exists today (`AE97SA4TCRHH`) so it is currently a no-op, but `sellingPartnerId` is part of Daton's grain and a second seller account would make the dedup silently pick one row across partners.

**`purchase_date` is already America/Los_Angeles.** The raw Daton `PurchaseDate` is a naive UTC `DATETIME`; the interface view converts it. The LA date reconciles exactly with `SRC_ACC_SALES_TRAFFIC_DAILY.date`; the UTC date does not. Never re-derive the date from `purchase_timestamp_utc` without the LA conversion.

**Order money and item money are different things.** `V_SRC_ListOrder.order_total_amount` includes tax and shipping. `V_SRC_ListOrderItems.item_price_amount` is the extended product price for `quantity_ordered` units, before tax. They will not tie, and neither ties to `SRC_ACC_SALES_TRAFFIC_DAILY.SALES_AMOUNT`. Only **units** tie across all three.

**Cancellations exist at two levels.** `order_status = 'Canceled'` (one L — American spelling) marks the order; canceled orders carry zero units. Separately, individual line items can arrive with `quantity_ordered = 0` on an order whose header reads `Shipped`. Filtering only on `NOT is_canceled` is not enough — every consumer must also require `quantity_ordered > 0`.

**About 4% of sold units are ASINs missing from `DIM_PRODUCT`.** These are genuine retired Happy Lolli products (necklaces, older gift sets) that dropped out of the dimension. They must be kept in the fact, with `parent_name` NULL and `is_mapped_product = FALSE`, and the item feed's own `title` retained as a fallback label.

**The item backfill is incomplete while this plan is being written.** As of 2026-08-23 the order headers are complete through today, but the item feed had only reached mid-2025 and was advancing at roughly 800 rows/hour. `V_ORDER_CROSS_SELL` built on a partial item feed will return confidently wrong answers about recent products. Task 2 builds the gate that makes this visible, and Task 10 refuses to sign off until it passes.

**Never trust these two header fields:** `is_prime` reads 0.0% across all orders (not populated on this feed) and `fulfillment_channel` is `AFN` on every row (no variance). Do not build anything on either.

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/bigquery/views/V_ORDER_ITEM_COVERAGE.sql` | Create. Gate view: per month, how much of the header order set has items yet. |
| `scripts/bigquery/tables/FACT/FACT_CUSTOMER_ORDER_ITEM.sql` | Create. Item-grain fact DDL, partitioned by `purchase_date`. |
| `scripts/bigquery/procedures/SP_LOAD_FACT_CUSTOMER_ORDER_ITEM.sql` | Create. Full MERGE loader, restatement-safe. |
| `scripts/bigquery/views/V_ORDER_BASKET.sql` | Create. One row per order: basket shape and label. |
| `scripts/bigquery/views/V_ORDER_CROSS_SELL.sql` | Create. One row per unordered ASIN pair per window: co-orders, support, lift. |
| `scripts/bigquery/tests/FACT_CUSTOMER_ORDER_ITEM_acceptance.sql` | Create. Every row must read PASS. |
| `scripts/bigquery/tests/V_ORDER_CROSS_SELL_acceptance.sql` | Create. Every row must read PASS. |
| `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql` | Modify. Add one wrapped step calling the new loader. |
| `config.yaml` | Modify. Register all five new objects. |
| `architecture/CUSTOMER_ORDER_BASKETS.md` | Create. The SOP, including the coverage gate rule. |

---

### Task 1: Coverage gate view

Built first because every later task needs a way to answer "is the item feed far enough along to trust this?".

**Files:**
- Create: `scripts/bigquery/views/V_ORDER_ITEM_COVERAGE.sql`

- [ ] **Step 1: Write the failing check**

Run this to confirm the object does not yet exist:

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT COUNT(*) FROM `onyga-482313.OI.V_ORDER_ITEM_COVERAGE`'
```

Expected: FAIL with `Not found: Table onyga-482313:OI.V_ORDER_ITEM_COVERAGE`

- [ ] **Step 2: Write the view**

Create `scripts/bigquery/views/V_ORDER_ITEM_COVERAGE.sql`:

```sql
-- =============================================
-- OI Database Project - V_ORDER_ITEM_COVERAGE
-- =============================================
--
-- Purpose: The BACKFILL GATE for customer-order baskets. Reports, per calendar
--          month, how many order headers have their line items loaded yet.
--          Basket and cross-sell answers are only as good as this coverage —
--          a month at 40% coverage will produce confident, wrong pair counts.
--
-- Source: V_SRC_ListOrder (headers), V_SRC_ListOrderItems (lines)
-- Grain:  One row per purchase month
--
-- Canceled orders are excluded from the denominator: they carry zero units and
-- do not need line items, so counting them would understate real coverage.
--
-- READ THIS BEFORE TRUSTING V_ORDER_CROSS_SELL: a month whose coverage_pct is
-- below 99 is still filling. See architecture/CUSTOMER_ORDER_BASKETS.md.
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ORDER_ITEM_COVERAGE` AS

WITH headers AS (
  SELECT
    DATE_TRUNC(purchase_date, MONTH) AS purchase_month,
    selling_partner_id,
    amazon_order_id,
    units_total
  FROM `onyga-482313.OI.V_SRC_ListOrder`
  WHERE NOT is_canceled
),

items AS (
  SELECT
    selling_partner_id,
    amazon_order_id,
    COUNT(*)               AS item_lines,
    SUM(quantity_ordered)  AS item_units
  FROM `onyga-482313.OI.V_SRC_ListOrderItems`
  GROUP BY 1, 2
)

SELECT
  h.purchase_month,
  COUNT(*)                                                        AS header_orders,
  COUNTIF(i.amazon_order_id IS NOT NULL)                          AS orders_with_items,
  ROUND(100 * COUNTIF(i.amazon_order_id IS NOT NULL) / COUNT(*), 2) AS coverage_pct,
  SUM(h.units_total)                                              AS header_units,
  SUM(COALESCE(i.item_units, 0))                                  AS item_units,
  SUM(h.units_total) - SUM(COALESCE(i.item_units, 0))             AS units_missing,
  COUNTIF(i.amazon_order_id IS NOT NULL) = COUNT(*)               AS is_month_complete
FROM headers h
LEFT JOIN items i
  USING (selling_partner_id, amazon_order_id)
GROUP BY 1
ORDER BY 1;
```

- [ ] **Step 3: Deploy it**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=none < scripts/bigquery/views/V_ORDER_ITEM_COVERAGE.sql
```

Expected: `Created onyga-482313.OI.V_ORDER_ITEM_COVERAGE`

- [ ] **Step 4: Verify it returns sane rows**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT CAST(purchase_month AS STRING) m, header_orders, orders_with_items, coverage_pct, is_month_complete FROM `onyga-482313.OI.V_ORDER_ITEM_COVERAGE` ORDER BY purchase_month LIMIT 5'
```

Expected: one row per month starting 2024-08-01, `coverage_pct` at or near 100 for the earliest months (they backfilled first), `header_orders` in the hundreds to low thousands.

- [ ] **Step 5: Commit**

```bash
git add scripts/bigquery/views/V_ORDER_ITEM_COVERAGE.sql
git commit -m "feat: the backfill gate — a month's basket answers are only as good as its item coverage, so the coverage is a view you can read before you trust one"
```

---

### Task 2: The fact table

**Files:**
- Create: `scripts/bigquery/tables/FACT/FACT_CUSTOMER_ORDER_ITEM.sql`

- [ ] **Step 1: Confirm the table does not exist**

```bash
bq --project_id=onyga-482313 --location=US show --schema OI.FACT_CUSTOMER_ORDER_ITEM
```

Expected: FAIL with `Not found: Table onyga-482313:OI.FACT_CUSTOMER_ORDER_ITEM`

- [ ] **Step 2: Write the DDL**

Create `scripts/bigquery/tables/FACT/FACT_CUSTOMER_ORDER_ITEM.sql`:

```sql
-- =============================================
-- OI Database Project - FACT_CUSTOMER_ORDER_ITEM
-- =============================================
--
-- Purpose: Amazon customer-order LINE ITEMS — the only grain in the warehouse
--          that says which products travelled in the same order. Loaded by
--          SP_LOAD_FACT_CUSTOMER_ORDER_ITEM from V_SRC_ListOrderItems joined to
--          V_SRC_ListOrder for the date and status the item feed lacks.
--
-- Grain:  One row per (selling_partner_id, amazon_order_id, order_item_id)
--
-- Order-level attributes (purchase_date, order_status, ship_state, ...) are
-- DENORMALIZED onto every line so consumers never have to re-join the header.
-- order_units_total is the HEADER's own unit count, kept deliberately: comparing
-- it against SUM(quantity_ordered) for the order is how you detect line items
-- that have not synced yet.
--
-- Basket-level aggregates are NOT stored here. They are derived in
-- V_ORDER_BASKET, because an order's line count changes as items arrive and a
-- stored aggregate would go stale between loads.
--
-- is_mapped_product = FALSE marks ASINs absent from DIM_PRODUCT (~4% of units:
-- genuine retired Happy Lolli products). They are kept, and item_title carries
-- the label in place of the missing product_short_name.
--
-- Money: item_price_amount is the EXTENDED product price for quantity_ordered
-- units, before tax. It does not tie to the order total (which adds tax and
-- shipping) nor to SRC_ACC_SALES_TRAFFIC_DAILY.SALES_AMOUNT. Only units tie.
--
-- promotion_ids is a plain STRING despite the plural name, not an array —
-- do not UNNEST it.
--
-- shipping_price_amount and shipping_discount_amount from the source view are
-- deliberately omitted: basket composition does not need shipping detail.
--
-- DEPLOYED-SCHEMA DIVERGENCE (2026-08-23): the live table carries the
-- PRIMARY KEY below but NOT the NOT NULL constraints on the three key
-- columns. BigQuery has no ALTER that promotes an existing NULLABLE column
-- to REQUIRED, and the table already held 25,094 rows when this constraint
-- was added, so the key was applied live via ALTER TABLE ... ADD PRIMARY KEY
-- instead of a drop/rebuild. The NOT NULLs in this file take effect only on
-- a fresh CREATE. Beware: CREATE TABLE IF NOT EXISTS is a SILENT NO-OP
-- against the existing table, so re-running this file will NOT reconcile
-- the gap. Acceptance check A3 covers it by failing on any NULL key column;
-- the three key columns held zero NULLs across all rows when this was written.
--
-- Spec: architecture/CUSTOMER_ORDER_BASKETS.md
--
-- =============================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM` (
  -- Keys
  selling_partner_id         STRING NOT NULL,
  amazon_order_id            STRING NOT NULL,
  order_item_id              STRING NOT NULL,

  -- Order header, denormalized
  purchase_date              DATE,
  purchase_timestamp_utc     TIMESTAMP,
  order_status               STRING,
  is_canceled                BOOL,
  is_business_order          BOOL,
  ship_city                  STRING,
  ship_state                 STRING,
  order_units_total          INT64,

  -- Product
  asin                       STRING,
  seller_sku                 STRING,
  item_title                 STRING,
  parent_name                STRING,
  product_short_name         STRING,
  is_mapped_product          BOOL,

  -- Units
  quantity_ordered           INT64,
  quantity_shipped           INT64,

  -- Money (extended over quantity_ordered, pre-tax)
  item_price_amount          NUMERIC,
  item_tax_amount            NUMERIC,
  promotion_discount_amount  NUMERIC,
  unit_price_amount          NUMERIC,
  promotion_ids              STRING,
  is_gift                    BOOL,

  loaded_at                  TIMESTAMP,

  PRIMARY KEY (selling_partner_id, amazon_order_id, order_item_id) NOT ENFORCED
)
PARTITION BY purchase_date
CLUSTER BY asin, amazon_order_id
OPTIONS (
  description = "Amazon customer-order line items, one row per (selling_partner_id, amazon_order_id, order_item_id). THE basket-composition fact. Loaded by SP_LOAD_FACT_CUSTOMER_ORDER_ITEM. purchase_date is America/Los_Angeles and ties to SRC_ACC_SALES_TRAFFIC_DAILY.date on units. Consumers must filter NOT is_canceled AND quantity_ordered > 0 — canceled lines exist on Shipped orders. Spec: architecture/CUSTOMER_ORDER_BASKETS.md"
);
```

- [ ] **Step 3: Create the table**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=none < scripts/bigquery/tables/FACT/FACT_CUSTOMER_ORDER_ITEM.sql
```

Expected: the command completes with no error and prints nothing (DDL statements return no rows).

- [ ] **Step 4: Verify the schema and partitioning**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT table_name, ddl FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES` WHERE table_name = "FACT_CUSTOMER_ORDER_ITEM"'
```

Expected: one row whose DDL contains `PARTITION BY purchase_date` and `CLUSTER BY asin, amazon_order_id`.

- [ ] **Step 5: Commit**

```bash
git add scripts/bigquery/tables/FACT/FACT_CUSTOMER_ORDER_ITEM.sql
git commit -m "feat: the order-item fact — basket aggregates stay out of it on purpose, because a stored line count goes stale the moment the next item lands"
```

---

### Task 3: The loader

**Files:**
- Create: `scripts/bigquery/procedures/SP_LOAD_FACT_CUSTOMER_ORDER_ITEM.sql`

- [ ] **Step 1: Confirm the procedure does not exist**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT routine_name FROM `onyga-482313.OI.INFORMATION_SCHEMA.ROUTINES` WHERE routine_name = "SP_LOAD_FACT_CUSTOMER_ORDER_ITEM"'
```

Expected: zero rows.

- [ ] **Step 2: Write the procedure**

Create `scripts/bigquery/procedures/SP_LOAD_FACT_CUSTOMER_ORDER_ITEM.sql`:

```sql
-- =============================================
-- OI Database Project - SP_LOAD_FACT_CUSTOMER_ORDER_ITEM
-- =============================================
--
-- Purpose: Load FACT_CUSTOMER_ORDER_ITEM from the two order interface views.
-- Pattern: FULL MERGE on the composite key — no watermark.
--
-- Why a full MERGE and not an incremental window: the whole source is ~70k rows,
-- so a full pass is seconds, and orders RESTATE (an order shipped yesterday can
-- be canceled tomorrow, and Daton re-emits it). A date-windowed load would leave
-- stale is_canceled flags behind the window. Full MERGE is the cheap correct one.
--
-- The DIM_PRODUCT join is deduplicated with QUALIFY rather than ANY_VALUE:
-- picking parent_name and product_short_name with two separate ANY_VALUE calls
-- over one GROUP BY can pair a name from one row with a short name from another.
--
-- No DELETE arm: order items do not disappear from the source. If they ever do,
-- the acceptance test's row-count check (A1) is what surfaces it.
--
-- Spec: architecture/CUSTOMER_ORDER_BASKETS.md
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_FACT_CUSTOMER_ORDER_ITEM`()
OPTIONS (
  description = "Load FACT_CUSTOMER_ORDER_ITEM from V_SRC_ListOrderItems joined to V_SRC_ListOrder. Full MERGE on (selling_partner_id, amazon_order_id, order_item_id) — restatement-safe, no watermark."
)
BEGIN
  DECLARE v_loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  MERGE `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM` T
  USING (
    SELECT
      i.selling_partner_id,
      i.amazon_order_id,
      i.order_item_id,

      o.purchase_date,
      o.purchase_timestamp_utc,
      o.order_status,
      o.is_canceled,
      o.is_business_order,
      o.ship_city,
      o.ship_state,
      o.units_total AS order_units_total,

      i.asin,
      i.seller_sku,
      i.title AS item_title,
      d.parent_name,
      d.product_short_name,
      d.asin IS NOT NULL AS is_mapped_product,

      i.quantity_ordered,
      i.quantity_shipped,

      i.item_price_amount,
      i.item_tax_amount,
      i.promotion_discount_amount,
      i.unit_price_amount,
      i.promotion_ids,
      i.is_gift
    FROM `onyga-482313.OI.V_SRC_ListOrderItems` i
    JOIN `onyga-482313.OI.V_SRC_ListOrder` o
      USING (selling_partner_id, amazon_order_id)
    LEFT JOIN (
      SELECT asin, parent_name, product_short_name
      FROM `onyga-482313.OI.DIM_PRODUCT`
      QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY updated_at DESC, sku) = 1
    ) d
      ON d.asin = i.asin
  ) S
  ON  T.selling_partner_id = S.selling_partner_id
  AND T.amazon_order_id    = S.amazon_order_id
  AND T.order_item_id      = S.order_item_id

  WHEN MATCHED THEN UPDATE SET
    purchase_date             = S.purchase_date,
    purchase_timestamp_utc    = S.purchase_timestamp_utc,
    order_status              = S.order_status,
    is_canceled               = S.is_canceled,
    is_business_order         = S.is_business_order,
    ship_city                 = S.ship_city,
    ship_state                = S.ship_state,
    order_units_total         = S.order_units_total,
    asin                      = S.asin,
    seller_sku                = S.seller_sku,
    item_title                = S.item_title,
    parent_name               = S.parent_name,
    product_short_name        = S.product_short_name,
    is_mapped_product         = S.is_mapped_product,
    quantity_ordered          = S.quantity_ordered,
    quantity_shipped          = S.quantity_shipped,
    item_price_amount         = S.item_price_amount,
    item_tax_amount           = S.item_tax_amount,
    promotion_discount_amount = S.promotion_discount_amount,
    unit_price_amount         = S.unit_price_amount,
    promotion_ids             = S.promotion_ids,
    is_gift                   = S.is_gift,
    loaded_at                 = v_loaded_at

  WHEN NOT MATCHED THEN INSERT (
    selling_partner_id, amazon_order_id, order_item_id,
    purchase_date, purchase_timestamp_utc, order_status, is_canceled,
    is_business_order, ship_city, ship_state, order_units_total,
    asin, seller_sku, item_title, parent_name, product_short_name, is_mapped_product,
    quantity_ordered, quantity_shipped,
    item_price_amount, item_tax_amount, promotion_discount_amount,
    unit_price_amount, promotion_ids, is_gift,
    loaded_at
  ) VALUES (
    S.selling_partner_id, S.amazon_order_id, S.order_item_id,
    S.purchase_date, S.purchase_timestamp_utc, S.order_status, S.is_canceled,
    S.is_business_order, S.ship_city, S.ship_state, S.order_units_total,
    S.asin, S.seller_sku, S.item_title, S.parent_name, S.product_short_name, S.is_mapped_product,
    S.quantity_ordered, S.quantity_shipped,
    S.item_price_amount, S.item_tax_amount, S.promotion_discount_amount,
    S.unit_price_amount, S.promotion_ids, S.is_gift,
    v_loaded_at
  );
END;
```

- [ ] **Step 3: Deploy the procedure**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=none < scripts/bigquery/procedures/SP_LOAD_FACT_CUSTOMER_ORDER_ITEM.sql
```

Expected: completes with no error.

- [ ] **Step 4: Run it**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=none 'CALL `onyga-482313.OI.SP_LOAD_FACT_CUSTOMER_ORDER_ITEM`()'
```

Expected: completes with no error.

- [ ] **Step 5: Verify the load matches the source exactly**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`) AS fact_rows, (SELECT COUNT(*) FROM `onyga-482313.OI.V_SRC_ListOrderItems` i JOIN `onyga-482313.OI.V_SRC_ListOrder` o USING (selling_partner_id, amazon_order_id)) AS source_rows'
```

Expected: `fact_rows` equals `source_rows`. If `fact_rows` is larger, the `DIM_PRODUCT` join fanned out — check the QUALIFY clause.

- [ ] **Step 6: Run it a second time to prove idempotence**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=none 'CALL `onyga-482313.OI.SP_LOAD_FACT_CUSTOMER_ORDER_ITEM`()' && bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT COUNT(*) AS fact_rows FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`'
```

Expected: `fact_rows` unchanged from Step 5.

- [ ] **Step 7: Commit**

```bash
git add scripts/bigquery/procedures/SP_LOAD_FACT_CUSTOMER_ORDER_ITEM.sql
git commit -m "feat: the order-item loader — a full MERGE rather than a date window, because an order canceled tomorrow restates a row the window has already passed"
```

---

### Task 4: Acceptance test for the fact

**Files:**
- Create: `scripts/bigquery/tests/FACT_CUSTOMER_ORDER_ITEM_acceptance.sql`

- [ ] **Step 1: Write the test**

Create `scripts/bigquery/tests/FACT_CUSTOMER_ORDER_ITEM_acceptance.sql`:

```sql
-- =============================================================================================
-- FACT_CUSTOMER_ORDER_ITEM acceptance — every row must read PASS.
-- Run after SP_LOAD_FACT_CUSTOMER_ORDER_ITEM:
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache < FILE
-- Spec: architecture/CUSTOMER_ORDER_BASKETS.md
--
-- Checks:
--   A1 No fan-out: fact row count never exceeds the joined source row count. fact < src is
--      ordinary sync lag (the source is a continuously-syncing feed, the loader runs daily)
--      and PASSes with the lag stated; fact > src is a defect — rows the no-DELETE-arm MERGE
--      in SP_LOAD_FACT_CUSTOMER_ORDER_ITEM would never clean up.
--   A2 Key uniqueness: (selling_partner_id, amazon_order_id, order_item_id) appears once.
--   A3 No NULL keys and no NULL purchase_date.
--   A4 Referential integrity: every fact order exists in V_SRC_ListOrder.
--   A5 Dates are inside the feed's real window (2024-08-01 .. today LA).
--   A6 Header reconciliation: for every non-canceled order in the fact, the item units sum
--      to the header's own unit count. A mismatch means line items are missing for that
--      order, which is the failure mode that silently shrinks baskets.
--   A7 Mapping drift guard: unmapped ASINs stay under 10% of units. ~4% is expected
--      (retired products); a jump means DIM_PRODUCT lost live ASINs. Note: is_mapped_product
--      only tests that a DIM_PRODUCT row exists, not that it carries a family — rows with
--      is_mapped_product = TRUE and parent_name IS NULL pass A7 uncaught; that gap belongs to
--      DIM_PRODUCT's completeness, not this fact.
--   A8 Canceled orders carry no units, so they can never inflate a basket.
--   A9 No source item without an order header: the loader INNER JOINs items to headers, so an
--      item with no matching header is silently dropped and invisible to A1 (missing from both
--      sides of that comparison at once). Both sides here read the same live views in one
--      query, so this check carries no sync-lag artifact.
-- =============================================================================================
WITH
src AS (
  SELECT COUNT(*) AS n
  FROM `onyga-482313.OI.V_SRC_ListOrderItems` i
  JOIN `onyga-482313.OI.V_SRC_ListOrder` o USING (selling_partner_id, amazon_order_id)
),
fact AS (SELECT COUNT(*) AS n FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`),

a1 AS (
  SELECT 'A1 no fan-out (fact never exceeds source)' AS check_name,
         IF((SELECT n FROM fact) <= (SELECT n FROM src), 'PASS', 'FAIL') AS status,
         CASE
           WHEN (SELECT n FROM fact) > (SELECT n FROM src)
             THEN FORMAT('fact=%d source=%d — fact is AHEAD by %d: rows the no-DELETE MERGE never cleaned',
                         (SELECT n FROM fact), (SELECT n FROM src),
                         (SELECT n FROM fact) - (SELECT n FROM src))
           WHEN (SELECT n FROM fact) < (SELECT n FROM src)
             THEN FORMAT('fact=%d source=%d — fact is BEHIND by %d: ordinary sync lag, rerun the loader',
                         (SELECT n FROM fact), (SELECT n FROM src),
                         (SELECT n FROM src) - (SELECT n FROM fact))
           ELSE FORMAT('fact=%d source=%d — exact', (SELECT n FROM fact), (SELECT n FROM src))
         END AS detail
),

a2 AS (
  SELECT 'A2 key uniqueness' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d duplicated keys', COUNT(*)) AS detail
  FROM (
    SELECT selling_partner_id, amazon_order_id, order_item_id
    FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
    GROUP BY 1,2,3 HAVING COUNT(*) > 1
  )
),

a3 AS (
  SELECT 'A3 no null keys or dates' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d rows with a null key or date', COUNT(*)) AS detail
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
  WHERE selling_partner_id IS NULL OR amazon_order_id IS NULL
     OR order_item_id IS NULL OR purchase_date IS NULL
),

a4 AS (
  SELECT 'A4 referential integrity to headers' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d orphan fact rows', COUNT(*)) AS detail
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM` f
  LEFT JOIN `onyga-482313.OI.V_SRC_ListOrder` o
    USING (selling_partner_id, amazon_order_id)
  WHERE o.amazon_order_id IS NULL
),

a5 AS (
  SELECT 'A5 dates inside the feed window' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d rows outside 2024-08-01..today', COUNT(*)) AS detail
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
  WHERE purchase_date < DATE '2024-08-01'
     OR purchase_date > CURRENT_DATE('America/Los_Angeles')
),

a6 AS (
  SELECT 'A6 item units reconcile to header' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d orders whose items do not sum to the header count', COUNT(*)) AS detail
  FROM (
    SELECT selling_partner_id, amazon_order_id
    FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
    WHERE NOT is_canceled
    GROUP BY 1, 2
    HAVING SUM(quantity_ordered) != MAX(order_units_total)
  )
),

a7 AS (
  SELECT 'A7 unmapped-ASIN share under 10%' AS check_name,
         IF(pct < 10, 'PASS', 'FAIL') AS status,
         FORMAT('%.2f%% of units are unmapped', pct) AS detail
  FROM (
    SELECT 100 * SAFE_DIVIDE(
             SUM(IF(is_mapped_product, 0, quantity_ordered)),
             SUM(quantity_ordered)) AS pct
    FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
  )
),

a8 AS (
  SELECT 'A8 canceled orders carry no units' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d canceled rows with units', COUNT(*)) AS detail
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
  WHERE is_canceled AND quantity_ordered > 0
),

a9 AS (
  SELECT 'A9 no source item without an order header' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d source items the loader would silently drop', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_SRC_ListOrderItems` i
  LEFT JOIN `onyga-482313.OI.V_SRC_ListOrder` o
    USING (selling_partner_id, amazon_order_id)
  WHERE o.amazon_order_id IS NULL
)

SELECT * FROM a1
UNION ALL SELECT * FROM a2
UNION ALL SELECT * FROM a3
UNION ALL SELECT * FROM a4
UNION ALL SELECT * FROM a5
UNION ALL SELECT * FROM a6
UNION ALL SELECT * FROM a7
UNION ALL SELECT * FROM a8
UNION ALL SELECT * FROM a9
ORDER BY check_name;
```

- [ ] **Step 2: Run the test**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --nouse_cache --format=csv < scripts/bigquery/tests/FACT_CUSTOMER_ORDER_ITEM_acceptance.sql
```

Expected: 8 rows, every `status` reading `PASS`.

- [ ] **Step 3: If A6 fails, diagnose before proceeding**

A6 is the one that legitimately fails mid-backfill. Find the offending orders:

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT selling_partner_id, amazon_order_id, SUM(quantity_ordered) item_units, MAX(order_units_total) header_units FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM` WHERE NOT is_canceled GROUP BY 1, 2 HAVING item_units != header_units ORDER BY header_units - item_units DESC LIMIT 20'
```

If `item_units` is consistently lower, the item feed has partially loaded those orders — rerun `SP_LOAD_FACT_CUSTOMER_ORDER_ITEM` after the Daton sync advances, then re-run the test. Do not weaken the check.

- [ ] **Step 4: Commit**

```bash
git add scripts/bigquery/tests/FACT_CUSTOMER_ORDER_ITEM_acceptance.sql
git commit -m "feat: acceptance for the order-item fact — A6 compares item units against the header's own count, because a half-loaded order shrinks a basket without ever erroring"
```

---

### Task 5: The basket view

**Files:**
- Create: `scripts/bigquery/views/V_ORDER_BASKET.sql`

- [ ] **Step 1: Confirm the object does not exist**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT COUNT(*) FROM `onyga-482313.OI.V_ORDER_BASKET`'
```

Expected: FAIL with `Not found: Table onyga-482313:OI.V_ORDER_BASKET`

- [ ] **Step 2: Write the view**

Create `scripts/bigquery/views/V_ORDER_BASKET.sql`:

```sql
-- =============================================
-- OI Database Project - V_ORDER_BASKET
-- =============================================
--
-- Purpose: One row per customer order describing the SHAPE of the basket —
--          how many distinct products, how many units, and a readable label.
--          This is the human-facing surface; V_ORDER_CROSS_SELL is the
--          machine-facing pair table built from the same lines.
--
-- Source: FACT_CUSTOMER_ORDER_ITEM
-- Grain:  One row per (selling_partner_id, amazon_order_id)
--
-- Both exclusions matter and neither is optional:
--   NOT is_canceled       drops orders Amazon canceled outright
--   quantity_ordered > 0  drops canceled LINES on orders that still shipped
-- An order whose every line is canceled disappears entirely, which is correct —
-- it has no basket.
--
-- basket_kind separates the two different questions people ask:
--   SINGLE          one product, one unit
--   MULTI_UNIT_SAME one product, several units  (a "buy two" signal)
--   MULTI_PRODUCT   more than one product       (a cross-sell signal)
--
-- Unmapped ASINs (retired products absent from DIM_PRODUCT) keep their identity
-- as 'UNMAPPED:<asin>' rather than collapsing into one bucket, so two different
-- retired products never look like the same product bought twice.
--
-- Spec: architecture/CUSTOMER_ORDER_BASKETS.md
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ORDER_BASKET` AS

WITH lines AS (
  SELECT
    selling_partner_id,
    amazon_order_id,
    purchase_date,
    ship_state,
    is_business_order,
    asin,
    COALESCE(parent_name, CONCAT('UNMAPPED:', asin))        AS family_label,
    COALESCE(product_short_name, item_title, asin)          AS product_label,
    is_mapped_product,
    quantity_ordered,
    item_price_amount
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
  WHERE NOT is_canceled
    AND quantity_ordered > 0
)

SELECT
  selling_partner_id,
  amazon_order_id,
  purchase_date,
  ship_state,
  is_business_order,

  COUNT(*)                                  AS line_count,
  COUNT(DISTINCT asin)                      AS distinct_asins,
  COUNT(DISTINCT family_label)              AS distinct_families,
  SUM(quantity_ordered)                     AS units,
  ROUND(SUM(item_price_amount), 2)          AS item_revenue,
  LOGICAL_AND(is_mapped_product)            AS all_products_mapped,

  CASE
    WHEN COUNT(DISTINCT asin) > 1     THEN 'MULTI_PRODUCT'
    WHEN SUM(quantity_ordered) > 1    THEN 'MULTI_UNIT_SAME'
    ELSE                                   'SINGLE'
  END                                       AS basket_kind,

  STRING_AGG(DISTINCT product_label ORDER BY product_label) AS basket_label
FROM lines
GROUP BY 1, 2, 3, 4, 5;
```

- [ ] **Step 3: Deploy it**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=none < scripts/bigquery/views/V_ORDER_BASKET.sql
```

Expected: `Created onyga-482313.OI.V_ORDER_BASKET`

- [ ] **Step 4: Verify the basket mix looks plausible**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT basket_kind, COUNT(*) orders, ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),2) pct FROM `onyga-482313.OI.V_ORDER_BASKET` GROUP BY 1 ORDER BY 2 DESC'
```

Expected: three rows. `SINGLE` should dominate at roughly 90%+, with `MULTI_UNIT_SAME` and `MULTI_PRODUCT` each in the low single digits. The header-level distribution measured on 2026-08-23 was 92.5% one unit, 6.3% two units, 1.2% three or more — the basket mix should be in that neighbourhood, not wildly different.

- [ ] **Step 5: Eyeball actual multi-product baskets**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT CAST(purchase_date AS STRING) d, units, basket_label FROM `onyga-482313.OI.V_ORDER_BASKET` WHERE basket_kind = "MULTI_PRODUCT" ORDER BY purchase_date DESC LIMIT 10'
```

Expected: readable product-name pairs, not ASINs or NULLs. If you see raw ASINs, the `DIM_PRODUCT` labels are not landing — recheck the loader's join.

- [ ] **Step 6: Commit**

```bash
git add scripts/bigquery/views/V_ORDER_BASKET.sql
git commit -m "feat: the basket view — a canceled LINE on a shipped order is dropped too, because filtering only the canceled order still leaves phantom units in the basket"
```

---

### Task 6: The cross-sell pair view

**Files:**
- Create: `scripts/bigquery/views/V_ORDER_CROSS_SELL.sql`

- [ ] **Step 1: Confirm the object does not exist**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT COUNT(*) FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`'
```

Expected: FAIL with `Not found: Table onyga-482313:OI.V_ORDER_CROSS_SELL`

- [ ] **Step 2: Write the view**

Create `scripts/bigquery/views/V_ORDER_CROSS_SELL.sql`:

```sql
-- =============================================
-- OI Database Project - V_ORDER_CROSS_SELL
-- =============================================
--
-- Purpose: MEASURED same-basket co-purchase. One row per unordered ASIN pair
--          per lookback window, with how often the two appeared in one order
--          and how much more often than chance would predict.
--
-- Source: FACT_CUSTOMER_ORDER_ITEM
-- Grain:  One row per (window_days, asin_a, asin_b) where asin_a < asin_b
--
-- HOW THIS DIFFERS FROM V_ADS_COACH_CROSSSELL — they are not competitors and
-- neither replaces the other:
--   V_ADS_COACH_CROSSSELL reads V_SRC_AmazonAds_purchased_product: "someone
--     clicked an ad for A and later bought B" — ad-attributed, possibly across
--     separate orders, and blind to anything ads never touched.
--   V_ORDER_CROSS_SELL reads actual orders: "A and B were in the SAME basket" —
--     no attribution model, no ad dependency, but no click intent either.
--   Ads-attributed cross-sell answers "what should A's ads target?".
--   Basket cross-sell answers "what do buyers actually put together?".
--
-- WINDOWS: window_days 90 and 365 are rolling from today (LA); 9999 means
-- lifetime. Consumers pick one — never sum across windows, they overlap.
--
-- LIFT is co-occurrence divided by what independence would predict:
--   lift = P(A and B) / (P(A) * P(B))
-- lift = 1 means the pair co-occurs exactly as often as chance. Above 1 is a
-- real affinity. Read it WITH co_orders, never alone: a pair seen in 2 orders
-- can post a spectacular lift and mean nothing.
--
-- items_through_date is carried on every row on purpose. The item feed
-- backfills oldest-first, so a window that extends past items_through_date is
-- reporting on data that has not arrived. Check it before believing a number,
-- and check V_ORDER_ITEM_COVERAGE for the per-month picture.
--
-- Spec: architecture/CUSTOMER_ORDER_BASKETS.md
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ORDER_CROSS_SELL` AS

WITH windows AS (
  SELECT * FROM UNNEST([90, 365, 9999]) AS window_days
),

horizon AS (
  SELECT MAX(purchase_date) AS items_through_date
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
),

dim AS (
  SELECT asin, parent_name, product_short_name
  FROM `onyga-482313.OI.DIM_PRODUCT`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY updated_at DESC, sku) = 1
),

-- One row per (window, order, asin): an order containing the same ASIN on two
-- lines must count once, or every pair involving it doubles.
scoped AS (
  SELECT DISTINCT
    w.window_days,
    f.amazon_order_id,
    f.asin
  FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM` f
  CROSS JOIN windows w
  WHERE NOT f.is_canceled
    AND f.quantity_ordered > 0
    AND f.purchase_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL w.window_days DAY)
),

totals AS (
  SELECT window_days, COUNT(DISTINCT amazon_order_id) AS total_orders
  FROM scoped
  GROUP BY 1
),

asin_orders AS (
  SELECT window_days, asin, COUNT(DISTINCT amazon_order_id) AS orders_with_asin
  FROM scoped
  GROUP BY 1, 2
),

pairs AS (
  SELECT
    a.window_days,
    a.asin AS asin_a,
    b.asin AS asin_b,
    COUNT(DISTINCT a.amazon_order_id) AS co_orders
  FROM scoped a
  JOIN scoped b
    ON  a.window_days     = b.window_days
    AND a.amazon_order_id = b.amazon_order_id
    AND a.asin < b.asin
  GROUP BY 1, 2, 3
)

SELECT
  p.window_days,
  p.asin_a,
  p.asin_b,
  da.product_short_name              AS name_a,
  db.product_short_name              AS name_b,
  da.parent_name                     AS family_a,
  db.parent_name                     AS family_b,
  da.parent_name IS NOT NULL
    AND db.parent_name IS NOT NULL   AS both_mapped,
  da.parent_name = db.parent_name    AS same_family,

  p.co_orders,
  oa.orders_with_asin                AS orders_a,
  ob.orders_with_asin                AS orders_b,
  t.total_orders,

  ROUND(100 * p.co_orders / t.total_orders, 4)        AS support_pct,
  ROUND(100 * p.co_orders / oa.orders_with_asin, 2)   AS pct_of_a_orders,
  ROUND(100 * p.co_orders / ob.orders_with_asin, 2)   AS pct_of_b_orders,
  ROUND(
    SAFE_DIVIDE(
      p.co_orders * t.total_orders,
      oa.orders_with_asin * ob.orders_with_asin
    ), 2)                                             AS lift,

  h.items_through_date
FROM pairs p
JOIN totals t
  USING (window_days)
JOIN asin_orders oa
  ON oa.window_days = p.window_days AND oa.asin = p.asin_a
JOIN asin_orders ob
  ON ob.window_days = p.window_days AND ob.asin = p.asin_b
LEFT JOIN dim da ON da.asin = p.asin_a
LEFT JOIN dim db ON db.asin = p.asin_b
CROSS JOIN horizon h;
```

- [ ] **Step 3: Deploy it**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=none < scripts/bigquery/views/V_ORDER_CROSS_SELL.sql
```

Expected: `Created onyga-482313.OI.V_ORDER_CROSS_SELL`

- [ ] **Step 4: Read the top lifetime pairs**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT name_a, name_b, co_orders, lift, pct_of_a_orders, CAST(items_through_date AS STRING) through FROM `onyga-482313.OI.V_ORDER_CROSS_SELL` WHERE window_days = 9999 AND co_orders >= 5 ORDER BY co_orders DESC LIMIT 15'
```

Expected: real pairs with `co_orders` in the tens. Confirm `lift` is a positive finite number on every row and `through` matches the item feed's horizon.

- [ ] **Step 5: Sanity-check the lift arithmetic by hand**

Pick the top row from Step 4 and verify:

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT co_orders, orders_a, orders_b, total_orders, lift, ROUND((co_orders * total_orders) / (orders_a * orders_b), 2) AS lift_recomputed FROM `onyga-482313.OI.V_ORDER_CROSS_SELL` WHERE window_days = 9999 ORDER BY co_orders DESC LIMIT 1'
```

Expected: `lift` equals `lift_recomputed`.

- [ ] **Step 6: Commit**

```bash
git add scripts/bigquery/views/V_ORDER_CROSS_SELL.sql
git commit -m "feat: measured same-basket cross-sell — it sits beside the ad-attributed view rather than replacing it, because 'clicked A then bought B' and 'bought A and B together' are two different questions"
```

---

### Task 7: Acceptance test for the pair view

**Files:**
- Create: `scripts/bigquery/tests/V_ORDER_CROSS_SELL_acceptance.sql`

- [ ] **Step 1: Write the test**

Create `scripts/bigquery/tests/V_ORDER_CROSS_SELL_acceptance.sql`:

```sql
-- =============================================================================================
-- V_ORDER_CROSS_SELL + V_ORDER_BASKET acceptance — every row must read PASS.
-- Run after SP_LOAD_FACT_CUSTOMER_ORDER_ITEM:
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache < FILE
-- Spec: architecture/CUSTOMER_ORDER_BASKETS.md
--
-- Checks:
--   B1 Pairs are unordered and deduplicated: asin_a < asin_b on every row, so a pair
--      never appears twice mirrored.
--   B2 Co-occurrence cannot exceed either side's own order count.
--   B3 support_pct is a real percentage (0 < support <= 100).
--   B4 lift is finite and positive on every row.
--   B5 Every window present has a positive total_orders.
--   B6 Basket arithmetic: a MULTI_PRODUCT basket really does hold >1 distinct ASIN,
--      and a SINGLE basket really is one product and one unit.
--   B7 No canceled order reaches the basket view.
--   B8 Every pair's two ASINs both appear in the fact — no phantom ASINs.
-- =============================================================================================
WITH
b1 AS (
  SELECT 'B1 pairs unordered and deduped' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d rows with asin_a >= asin_b', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
  WHERE asin_a >= asin_b
),

b2 AS (
  SELECT 'B2 co_orders within both sides' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d rows where co_orders exceeds orders_a or orders_b', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
  WHERE co_orders > orders_a OR co_orders > orders_b
),

b3 AS (
  SELECT 'B3 support is a real percentage' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d rows with support outside (0,100]', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
  WHERE support_pct <= 0 OR support_pct > 100
),

b4 AS (
  SELECT 'B4 lift finite and positive' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d rows with a null or non-positive lift', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
  WHERE lift IS NULL OR lift <= 0 OR IS_INF(lift) OR IS_NAN(lift)
),

b5 AS (
  SELECT 'B5 every window has orders' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d windows with total_orders <= 0', COUNT(*)) AS detail
  FROM (
    SELECT window_days
    FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
    GROUP BY 1
    HAVING MAX(total_orders) <= 0
  )
),

b6 AS (
  SELECT 'B6 basket_kind matches its arithmetic' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d baskets whose kind contradicts their counts', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_ORDER_BASKET`
  WHERE (basket_kind = 'MULTI_PRODUCT'   AND distinct_asins <= 1)
     OR (basket_kind = 'MULTI_UNIT_SAME' AND (distinct_asins != 1 OR units <= 1))
     OR (basket_kind = 'SINGLE'          AND (distinct_asins != 1 OR units != 1))
),

b7 AS (
  SELECT 'B7 no canceled order in baskets' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d canceled orders leaked into V_ORDER_BASKET', COUNT(*)) AS detail
  FROM `onyga-482313.OI.V_ORDER_BASKET` b
  JOIN `onyga-482313.OI.V_SRC_ListOrder` o
    USING (selling_partner_id, amazon_order_id)
  WHERE o.is_canceled
),

b8 AS (
  SELECT 'B8 no phantom ASINs in pairs' AS check_name,
         IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
         FORMAT('%d pair-sides with an ASIN absent from the fact', COUNT(*)) AS detail
  FROM (
    SELECT asin_a AS a FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
    UNION ALL
    SELECT asin_b FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
  ) p
  LEFT JOIN (
    SELECT DISTINCT asin FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
  ) f
    ON f.asin = p.a
  WHERE f.asin IS NULL
)

SELECT * FROM b1
UNION ALL SELECT * FROM b2
UNION ALL SELECT * FROM b3
UNION ALL SELECT * FROM b4
UNION ALL SELECT * FROM b5
UNION ALL SELECT * FROM b6
UNION ALL SELECT * FROM b7
UNION ALL SELECT * FROM b8
ORDER BY check_name;
```

- [ ] **Step 2: Run the test**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --nouse_cache --format=csv < scripts/bigquery/tests/V_ORDER_CROSS_SELL_acceptance.sql
```

Expected: 8 rows, every `status` reading `PASS`.

- [ ] **Step 3: Commit**

```bash
git add scripts/bigquery/tests/V_ORDER_CROSS_SELL_acceptance.sql
git commit -m "feat: acceptance for baskets and pairs — B6 checks the label against its own arithmetic, so a basket can never be called MULTI_PRODUCT while holding one ASIN"
```

---

### Task 8: Wire the loader into the daily orchestrator

The loader must run after the source views have fresh Daton data and before anything reads the fact. `SP_ORCHESTRATE_DAILY_REFRESH` already runs the other Daton-sourced loads in its Task 0 block.

**Files:**
- Modify: `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql`

- [ ] **Step 1: Find the insertion point**

```bash
grep -n "Refresh Task 0.4\|SP_SRC_ACC_REPEAT_PURCHASE" scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql | head
```

Expected: a `Refresh Task 0.4` comment block calling `SP_SRC_ACC_REPEAT_PURCHASE`. The new step goes immediately after that block's closing `END;` — that is, after the last Daton source load and before the DIM merges begin.

- [ ] **Step 2: Insert the new wrapped step**

Insert this block after the `SP_SRC_ACC_REPEAT_PURCHASE` block's closing `END;`. It follows the file's existing wrapper pattern exactly — same logging table, same counters, same exception arm:

```sql
  -- ============================================
  -- Refresh Task 0.5: FACT_CUSTOMER_ORDER_ITEM (Daton → V_SRC → FACT)
  -- Customer-order line items: the basket-composition fact.
  -- ============================================
  SET procedure_name = 'SP_LOAD_FACT_CUSTOMER_ORDER_ITEM';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_LOAD_FACT_CUSTOMER_ORDER_ITEM`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;
```

- [ ] **Step 3: Redeploy the orchestrator**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=none < scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql
```

Expected: completes with no error.

- [ ] **Step 4: Confirm the step is registered in the deployed body**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT REGEXP_CONTAINS(ddl, "SP_LOAD_FACT_CUSTOMER_ORDER_ITEM") AS step_present FROM `onyga-482313.OI.INFORMATION_SCHEMA.ROUTINES` WHERE routine_name = "SP_ORCHESTRATE_DAILY_REFRESH"'
```

Expected: `true`.

- [ ] **Step 5: Commit**

```bash
git add scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql
git commit -m "feat: the order-item load joins the daily refresh after the Daton sources and before the DIM merges, so the fact is never built from yesterday's views"
```

---

### Task 9: Register objects and write the SOP

**Files:**
- Modify: `config.yaml`
- Create: `architecture/CUSTOMER_ORDER_BASKETS.md`

- [ ] **Step 1: Register all five objects in config.yaml**

Add these entries. Put the `FACT_` and `SP_` entries beside their existing siblings (search for `FACT_FORECAST_DEMAND` and `SP_SRC_ACC_SALES_TRAFFIC` respectively), and the three `V_` entries in the analytics-views block:

```yaml
  - name: "FACT_CUSTOMER_ORDER_ITEM"
    description: "Amazon customer-order LINE ITEMS — one row per (selling_partner_id, amazon_order_id, order_item_id). THE basket-composition fact: grouping by amazon_order_id is the only way in the warehouse to see which products were bought together. Loaded by SP_LOAD_FACT_CUSTOMER_ORDER_ITEM via full MERGE (restatement-safe: orders cancel after the fact). purchase_date is America/Los_Angeles and ties to SRC_ACC_SALES_TRAFFIC_DAILY.date on UNITS only — money does not tie, because item_price is pre-tax product price while the order total adds tax and shipping. Consumers MUST filter NOT is_canceled AND quantity_ordered > 0: canceled LINES exist on orders whose header reads Shipped. is_mapped_product=FALSE marks retired ASINs absent from DIM_PRODUCT (~4% of units, genuine old products) — they are kept, with item_title as the label. Partitioned by purchase_date, clustered by asin. Spec: architecture/CUSTOMER_ORDER_BASKETS.md"
    type: "fact"
    source_files: ["scripts/bigquery/tables/FACT/FACT_CUSTOMER_ORDER_ITEM.sql"]
    dependencies:
      - V_SRC_ListOrder
      - V_SRC_ListOrderItems
      - DIM_PRODUCT

  - name: "SP_LOAD_FACT_CUSTOMER_ORDER_ITEM"
    description: "Load FACT_CUSTOMER_ORDER_ITEM from V_SRC_ListOrderItems joined to V_SRC_ListOrder on (selling_partner_id, amazon_order_id). Full MERGE, no watermark — the source is ~70k rows and orders restate, so a windowed load would strand stale is_canceled flags. DIM_PRODUCT is deduped with QUALIFY, not ANY_VALUE, so parent_name and product_short_name always come from the same row. Runs in SP_ORCHESTRATE_DAILY_REFRESH task 0.5."
    source_files: ["scripts/bigquery/procedures/SP_LOAD_FACT_CUSTOMER_ORDER_ITEM.sql"]
    dependencies:
      - FACT_CUSTOMER_ORDER_ITEM

  - name: "V_ORDER_ITEM_COVERAGE"
    description: "THE BACKFILL GATE for baskets. Per purchase month: header orders, how many have their line items loaded, coverage_pct, and units_missing. The Daton item feed backfills oldest-first and lags the headers badly, so a recent month can sit at low coverage while looking populated. Read this before trusting V_ORDER_CROSS_SELL — a month under 99% is still filling. Canceled orders are excluded from the denominator (zero units, no items needed)."
    source_files: ["scripts/bigquery/views/V_ORDER_ITEM_COVERAGE.sql"]
    dependencies:
      - V_SRC_ListOrder
      - V_SRC_ListOrderItems

  - name: "V_ORDER_BASKET"
    description: "One row per customer order describing basket shape: line_count, distinct_asins, distinct_families, units, item_revenue, and basket_kind (SINGLE / MULTI_UNIT_SAME / MULTI_PRODUCT) plus a readable basket_label. Excludes canceled orders AND canceled lines (quantity_ordered > 0) — filtering only the order leaves phantom units. Unmapped retired ASINs keep separate identities as 'UNMAPPED:<asin>' so two different retired products never look like one product bought twice."
    source_files: ["scripts/bigquery/views/V_ORDER_BASKET.sql"]
    dependencies:
      - FACT_CUSTOMER_ORDER_ITEM

  - name: "V_ORDER_CROSS_SELL"
    description: "MEASURED same-basket co-purchase: one row per (window_days, asin_a, asin_b) with asin_a < asin_b, carrying co_orders, support_pct, pct_of_a_orders, pct_of_b_orders and lift = P(A and B)/(P(A)*P(B)). Windows are 90, 365 and 9999 (lifetime), rolling from CURRENT_DATE('America/Los_Angeles') — never sum across windows, they overlap. DISTINCT from V_ADS_COACH_CROSSSELL and does not replace it: that view reads ad-attributed purchased-product data ('clicked A's ad, later bought B', possibly separate orders); this one reads actual baskets ('A and B in the SAME order'). Ads-attributed answers what A's ads should target; basket answers what buyers put together. Read lift WITH co_orders — a pair seen twice can post a huge lift and mean nothing. items_through_date is on every row because the item feed backfills oldest-first."
    source_files: ["scripts/bigquery/views/V_ORDER_CROSS_SELL.sql"]
    dependencies:
      - FACT_CUSTOMER_ORDER_ITEM
      - DIM_PRODUCT
```

- [ ] **Step 2: Verify config.yaml still parses**

```bash
python3 -c "import yaml; d=yaml.safe_load(open('config.yaml')); print('config.yaml parses OK')"
```

Expected: `config.yaml parses OK`

- [ ] **Step 3: Write the SOP**

Create `architecture/CUSTOMER_ORDER_BASKETS.md`:

```markdown
# Customer Order Baskets

## What this is

Amazon customer-order data at line-item grain, and the basket signals built on it.
Before 2026-08-22 the warehouse had no customer-order grain at all — the finest
sales grain was `SRC_ACC_SALES_TRAFFIC_DAILY` (per ASIN per day), so "which
products are bought together" was unanswerable. Note `FACT_ORDERS` is misnamed:
it holds manufacturer purchase orders, not customer orders.

## The chain

```
Daton amazon_selling_partner_ListOrder      -> V_SRC_ListOrder      (headers)
Daton amazon_selling_partner_ListOrderItems -> V_SRC_ListOrderItems (lines)
        both -> SP_LOAD_FACT_CUSTOMER_ORDER_ITEM -> FACT_CUSTOMER_ORDER_ITEM
                                                      |-> V_ORDER_BASKET
                                                      |-> V_ORDER_CROSS_SELL
        gate: V_ORDER_ITEM_COVERAGE (reads the two V_SRC_ views directly)
```

## The coverage gate — read this before quoting any basket number

The Daton item feed backfills **oldest-first** and runs far slower than the
header feed. A month can show plenty of orders while most of their line items
have not arrived, and every basket statistic for that month will be quietly
wrong — baskets look smaller, pairs look rarer, lift looks like noise.

Before trusting `V_ORDER_CROSS_SELL` for a period, check:

```sql
SELECT purchase_month, header_orders, orders_with_items, coverage_pct, is_month_complete
FROM `onyga-482313.OI.V_ORDER_ITEM_COVERAGE`
ORDER BY purchase_month DESC
LIMIT 12
```

**Rule: do not draw a conclusion about a month whose `coverage_pct` is below 99.**
`V_ORDER_CROSS_SELL` also carries `items_through_date` on every row as a
second reminder of where the feed actually ends.

## Standing facts

- **Join key is composite:** `(selling_partner_id, amazon_order_id)`, always both.
  One partner exists today (`AE97SA4TCRHH`); the second column is there because
  `sellingPartnerId` is part of Daton's grain and a second seller account would
  make the dedup silently pick one row across partners.
- **`purchase_date` is America/Los_Angeles** and ties exactly to
  `SRC_ACC_SALES_TRAFFIC_DAILY.date` on units. The raw UTC date does not.
- **Only units tie across sources.** Item price is pre-tax product price; the
  order total adds tax and shipping; Sales & Traffic reports product sales.
- **Two levels of cancellation.** `order_status = 'Canceled'` (one L) at the
  header, and `quantity_ordered = 0` lines on orders that still shipped. Every
  consumer filters both.
- **~4% of units are ASINs missing from `DIM_PRODUCT`** — genuine retired
  products. Kept with `is_mapped_product = FALSE` and `item_title` as the label.
- **Do not use `is_prime` or `fulfillment_channel`.** The first reads 0.0%
  across all orders; the second is `AFN` on every row. Neither is populated
  meaningfully on this feed.
- **History floors at ~2024-08-22**, the SP-API Orders two-year window. That
  predates the 2024-09-05 start of ads data, so baskets cover the whole
  advertised era — but the floor rolls forward, so anything needed long-term
  must be retained here rather than re-fetched later.
- **No buyer identity.** `BuyerEmail` and `BuyerName` are NULL on every row, so
  customer-level repeat/LTV analysis is not possible from this feed — and there
  is no PII to govern.

## Cross-sell: two views, two questions

`V_ADS_COACH_CROSSSELL` and `V_ORDER_CROSS_SELL` are complements, not rivals.

| | `V_ADS_COACH_CROSSSELL` | `V_ORDER_CROSS_SELL` |
|---|---|---|
| Source | `V_SRC_AmazonAds_purchased_product` | `FACT_CUSTOMER_ORDER_ITEM` |
| Claim | clicked A's ad, later bought B | A and B in the same order |
| Same order required | no | yes |
| Needs ad exposure | yes | no |
| Answers | what should A's ads target | what buyers actually put together |

Read `lift` **with** `co_orders`. A pair appearing in two orders can post a
spectacular lift and mean nothing.

## Running it

The loader runs inside `SP_ORCHESTRATE_DAILY_REFRESH` (task 0.5). To run it
alone:

```sql
CALL `onyga-482313.OI.SP_LOAD_FACT_CUSTOMER_ORDER_ITEM`()
```

It is a full MERGE and is idempotent — running it twice changes nothing.

## Tests

- `scripts/bigquery/tests/FACT_CUSTOMER_ORDER_ITEM_acceptance.sql`
- `scripts/bigquery/tests/V_ORDER_CROSS_SELL_acceptance.sql`

Every row must read `PASS`. Check A6 (item units reconcile to the header count)
legitimately fails while the backfill is mid-flight — that is the check doing
its job, not a bug to work around.
```

- [ ] **Step 4: Commit**

```bash
git add config.yaml architecture/CUSTOMER_ORDER_BASKETS.md
git commit -m "docs: the basket SOP writes down the coverage gate, because the item feed backfills oldest-first and a half-filled month reads as a real one"
```

---

### Task 10: Full verification pass

Do not mark this plan complete until every step here passes.

- [ ] **Step 1: Run the loader fresh**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=none 'CALL `onyga-482313.OI.SP_LOAD_FACT_CUSTOMER_ORDER_ITEM`()'
```

Expected: completes with no error.

- [ ] **Step 2: Run both acceptance suites**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --nouse_cache --format=csv < scripts/bigquery/tests/FACT_CUSTOMER_ORDER_ITEM_acceptance.sql && bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --nouse_cache --format=csv < scripts/bigquery/tests/V_ORDER_CROSS_SELL_acceptance.sql
```

Expected: 16 rows total, every `status` reading `PASS`.

- [ ] **Step 3: Report the coverage picture honestly**

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT CAST(purchase_month AS STRING) m, header_orders, orders_with_items, coverage_pct FROM `onyga-482313.OI.V_ORDER_ITEM_COVERAGE` ORDER BY purchase_month DESC LIMIT 14'
```

Record which months are at 100% and which are still filling. **Any month below 99% must be named explicitly when reporting results.** Do not present cross-sell findings for an incomplete month without that caveat.

- [ ] **Step 4: Confirm units still tie to the existing sales source**

This is the cross-check that proves the new fact did not drift from the warehouse's established truth. Restrict it to fully-covered months:

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'WITH complete AS (SELECT purchase_month FROM `onyga-482313.OI.V_ORDER_ITEM_COVERAGE` WHERE coverage_pct >= 99.99), f AS (SELECT DATE_TRUNC(purchase_date, MONTH) m, SUM(quantity_ordered) units FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM` WHERE NOT is_canceled GROUP BY 1), st AS (SELECT DATE_TRUNC(date, MONTH) m, SUM(SALES_QUANTITY) units FROM `onyga-482313.OI.SRC_ACC_SALES_TRAFFIC_DAILY` GROUP BY 1) SELECT CAST(f.m AS STRING) month, f.units fact_units, st.units st_units, f.units - st.units diff FROM f JOIN st USING (m) JOIN complete c ON c.purchase_month = f.m ORDER BY f.m'
```

Expected: `diff` is 0 or within a handful of units on every complete month. A large gap means the fact is losing rows — investigate before proceeding, do not explain it away.

- [ ] **Step 5: Answer the original question, if coverage allows**

The question that started this: which LolliBall colours sell together, and how often does someone buy more than one?

```bash
bq --project_id=onyga-482313 --location=US query --use_legacy_sql=false --format=csv 'SELECT name_a, name_b, co_orders, lift, pct_of_a_orders FROM `onyga-482313.OI.V_ORDER_CROSS_SELL` WHERE window_days = 9999 AND family_a = "LolliBall" AND family_b = "LolliBall" ORDER BY co_orders DESC'
```

If this returns nothing, check `V_ORDER_ITEM_COVERAGE` for 2026-06 onward — LolliBall's first sale was 2026-06-26, and if the item feed has not reached that month the empty result means "not loaded yet", **not** "no one buys two LolliBalls". Say so explicitly rather than reporting a null finding.

- [ ] **Step 6: Final commit**

```bash
git add docs/superpowers/plans/2026-08-23-customer-order-baskets.md && git commit -m "test: verification pass — units reconcile to Sales & Traffic on every fully-covered month, and the coverage gate names the months that are not"
```

---

## Out of scope — separate plans

These came out of the same analysis but are independent subsystems. Each deserves its own plan and none of them blocks this one:

1. **`V_SALES_TODAY`** — serve the current partial day from the order feed while Sales & Traffic catches up. The order headers run a full day fresher. Note this can only ever supply units and order counts, never sessions.
2. **Cancellation rate into `V_ADS_SETTLE_CURVE`** — a measured cancellation signal lets the settle work separate "the sale went away" from "Amazon restated", which it currently cannot distinguish.
3. **Ship-state geography dimension** — `ship_state` is populated on 95% of orders but carries 366 distinct free-text values. Needs normalization to 50 states before it is usable.
4. **Feeding measured pairs into the cross-sell coacher** — once `V_ORDER_CROSS_SELL` has full coverage, decide deliberately how it combines with the ad-attributed view. That is a judgement about coacher behaviour, not a data-plumbing task, and should be brainstormed rather than planned straight into code.

**Explicitly not in scope:** modifying `FACT_AMAZON_PERFORMANCE_DAILY`. Its sales columns come from Sales & Traffic, which carries sessions in the same rows. Swapping the sales half to the order feed would fork the grain and break organic % and CVR downstream.
