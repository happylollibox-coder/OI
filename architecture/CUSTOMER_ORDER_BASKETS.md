# Customer Order Baskets

## What this is

Amazon customer-order data at line-item grain, and the basket signals built on
it. Before 2026-08-22 the warehouse had no customer-order grain at all — the
finest sales grain was `SRC_ACC_SALES_TRAFFIC_DAILY` (per ASIN per day), so
"which products are bought together" was unanswerable. Note `FACT_ORDERS` is
misnamed: it holds manufacturer purchase orders, not customer orders.

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

Before trusting `V_ORDER_CROSS_SELL` or `V_ORDER_BASKET` for a period, check:

```sql
SELECT purchase_month, header_orders, orders_with_items, coverage_pct, is_month_complete
FROM `onyga-482313.OI.V_ORDER_ITEM_COVERAGE`
ORDER BY purchase_month DESC
LIMIT 12
```

**Rule: do not draw a conclusion about a month whose `coverage_pct` is below 99.**
`V_ORDER_CROSS_SELL` also carries `items_through_date` on every row as a
second reminder of where the feed actually ends.

`coverage_pct` and `units_missing` must be read together: `orders_with_items`
only asks "does at least one item row exist for this order", not "have all
its lines arrived" — a partially-synced order still counts as covered, and
`units_missing` is what catches that at month level.

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

## Acceptance-suite semantics

Two suites, 17 checks total. Every row must read `PASS`.

- `scripts/bigquery/tests/FACT_CUSTOMER_ORDER_ITEM_acceptance.sql` — A1-A9
- `scripts/bigquery/tests/V_ORDER_CROSS_SELL_acceptance.sql` — B1-B8

**Both suites are only fully meaningful immediately after a load.** Run
`CALL SP_LOAD_FACT_CUSTOMER_ORDER_ITEM()` first if you want a trustworthy read.

**A1 is asymmetric — this is by design, not a bug.** It passes when the fact
is *behind* the source and fails only when the fact is *ahead*:

| Reading | Meaning | Verdict |
|---|---|---|
| fact < source | ordinary sync lag between a Daton sync and the next loader pass | PASS |
| fact = source | exact | PASS |
| fact > source | rows the no-DELETE-arm MERGE never cleaned up | FAIL |

The lag magnitude is printed in the check's `detail` column. **Rerun the
loader before treating a BEHIND reading as anything** — it may just mean the
last load predates the latest sync.

**A9 exists because A1 has a structural blind spot.** The loader `INNER JOIN`s
items to headers, and A1 compares the fact against that same joined source —
so a source item with no matching header vanishes from *both* sides of the A1
comparison at once and A1 cannot see it. A9 reads `V_SRC_ListOrderItems` and
`V_SRC_ListOrder` directly (a `LEFT JOIN ... WHERE header IS NULL`) to catch
exactly that case.

**B5 only examines windows that HAVE rows.** It groups the cross-sell view by
`window_days` and checks `MAX(total_orders) > 0` for each group present — a
window that produces *zero rows* (see Windows, below) is invisible to it, not
failing. With the 90- and 365-day windows currently empty, B5 validates
exactly one window (9999), not three. Do not read a green B5 as proof all
three windows are healthy.

## Known coverage gaps

These columns carry **no test coverage in either acceptance suite** — a
defect in any of them would ship unnoticed:

`pct_of_a_orders`, `pct_of_b_orders`, `same_family`, `both_mapped`,
`items_through_date`, `line_count`, `distinct_families`, `item_revenue`,
`all_asins_in_dim`.

This is stated plainly here rather than left implicit. If you build something
that leans on one of these columns, consider adding a check before trusting it
at scale.

## The schema divergence

`FACT_CUSTOMER_ORDER_ITEM.sql` declares `NOT NULL` on the three key columns
(`selling_partner_id`, `amazon_order_id`, `order_item_id`) in its `CREATE
TABLE`. **The live table does not have them.** BigQuery has no `ALTER` that
promotes an existing `NULLABLE` column to `REQUIRED`, and the table already
held rows when the `PRIMARY KEY (...) NOT ENFORCED` constraint was added, so
the key was applied live via a standalone `ALTER TABLE ... ADD PRIMARY KEY`
rather than a drop/rebuild. `CREATE TABLE IF NOT EXISTS` is a **silent
no-op** against a table that already exists, so re-running the DDL file will
never reconcile this gap.

Acceptance check A3 (no NULL keys or `purchase_date`) is what actually
polices the gap functionally, even though it is not enforced structurally.

Record: `scripts/bigquery/migrations/2026-08-23_fact_customer_order_item_pk.sql`.
**The statement in that file has already been applied** — it is a record of
an ad hoc change, not a script waiting to be run.

## Windows

`V_ORDER_CROSS_SELL` computes three lookback windows: 90, 365, and 9999 days,
all rolling from `CURRENT_DATE('America/Los_Angeles')`.

**As of 2026-08-23, the 90- and 365-day windows are EMPTY.** The item feed's
horizon (bounded by how far the backfill has reached) predates both window
start dates. Only the lifetime window (9999) currently returns rows.

`9999` is a **sentinel**, not a real day count. `DATE_SUB(CURRENT_DATE(...),
INTERVAL 9999 DAY)` computes a real cutoff date of **1999-04-08**. It behaves
as "lifetime" purely because that cutoff predates all order history (earliest
order: 2024-08-03) — an arithmetic coincidence, not an asserted invariant.
The two diverge around **2051**, at which point a real 9999-day-old order
could exist and the window would start excluding history. Not a near-term
concern, but worth knowing if this code is still running in 25 years.

## `same_family` semantics

`same_family` compares `COALESCE(parent_name, 'UNMAPPED:<asin>')` on both
sides of a pair, so it is **never NULL**.

It is **guaranteed FALSE whenever `both_mapped` is FALSE**:

- If *both* ASINs are unmapped, this holds structurally — `asin_a < asin_b`
  already forces two different ASINs, so their `UNMAPPED:<asin>` labels are
  always distinct.
- If *only one* side is unmapped, this holds because no real `parent_name` in
  `DIM_PRODUCT` happens to look like `'UNMAPPED:...'` — true today, but not
  enforced by any constraint.

**Practical consequence:** for any pair where `both_mapped` is FALSE,
`same_family` adds no information beyond `both_mapped` itself. **Use
`both_mapped` as the gate**, not `same_family`, when you want to know whether
a pair's family comparison is trustworthy.

## Label derivation differs between the two views

`V_ORDER_BASKET` and `V_ORDER_CROSS_SELL` can disagree — briefly — on the
label for the same ASIN:

| | `V_ORDER_BASKET` | `V_ORDER_CROSS_SELL` |
|---|---|---|
| `parent_name` / `product_short_name` source | frozen onto `FACT_CUSTOMER_ORDER_ITEM` at **load time** | derived **live** from `DIM_PRODUCT` at query time |

If `DIM_PRODUCT` changes between a fact load and a query against
`V_ORDER_CROSS_SELL`, the two views can show different labels for the same
ASIN until the next `SP_LOAD_FACT_CUSTOMER_ORDER_ITEM` run reconciles them.

## The unmapped ASINs, stated correctly

This has been gotten wrong twice during the build, so state it precisely:
`'UNMAPPED:<asin>'` covers **two distinct situations**, not one:

1. ASINs genuinely **absent** from `DIM_PRODUCT` (no row at all).
2. ASINs **present** in `DIM_PRODUCT` with `parent_name IS NULL`.

The two largest examples of the second kind:

| ASIN | Nickname | In `DIM_PRODUCT`? | `oi_is_active` | Last sale |
|---|---|---|---|---|
| `B0CHJY7XLQ` | "Popsicle" | Yes | FALSE | before July 2025 |
| `B0CHJZDD3F` | "BFF 1" | Yes | FALSE | before July 2025 |

Both are present in `DIM_PRODUCT`, both carry `oi_is_active = FALSE` (the
manually-managed business-truth flag), and neither has sold since July 2025.
Neither is a live product.

**Warning:** `is_active` alone (Amazon's own catalog flag) reads TRUE on both
— it means only that Fivetran has not marked the record deleted, nothing
about whether the business still sells it. Every other production view in
this warehouse treats "active" as `is_active AND oi_is_active`. Do not use
`is_active` alone as a liveness test anywhere near this pipeline.

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

**The `DISTINCT` in `V_ORDER_CROSS_SELL`'s `scoped` CTE** exists to bound
self-join cardinality — without it, an order with the same ASIN on two lines
would count twice going into the self-join. It does **not**, by itself,
prevent double-counting a *pair*: the downstream `COUNT(DISTINCT
amazon_order_id)` in the `pairs` CTE is what actually guarantees each pair is
counted once per order. A reviewer proved the `DISTINCT` in `scoped` is
redundant for pair-counting by building the un-deduplicated variant and
diffing — zero rows differed. It is kept anyway because it is cheap and
correct defense-in-depth against the join fanning out before the aggregation
that actually enforces correctness runs.

## Orchestrator position

`SP_LOAD_FACT_CUSTOMER_ORDER_ITEM` runs inside `SP_ORCHESTRATE_DAILY_REFRESH`
as **Refresh Task 1.1**, immediately after **Task 1** (`SP_MERGE_PRODUCT_DIM_SMART`).

**Why this position, and why it moved here:** the loader joins `DIM_PRODUCT`
for `parent_name`, `product_short_name`, and `is_mapped_product`. It was
originally placed at Task 0.5 (before the `DIM_PRODUCT` merge) and moved to
1.1 during the build. Running before the `DIM_PRODUCT` merge would mislabel
any ASIN newly added to the product dimension in that same orchestrator run —
the fact would freeze in a stale (or missing) label for that ASIN, and the
mistake would only self-heal on the *next day's* load, not the current one.
Running after Task 1 means the fact always sees the freshest `DIM_PRODUCT`
available in the run it belongs to.

To run the loader alone:

```sql
CALL `onyga-482313.OI.SP_LOAD_FACT_CUSTOMER_ORDER_ITEM`()
```

It is a full MERGE and is idempotent — running it twice changes nothing.

## Tests

- `scripts/bigquery/tests/FACT_CUSTOMER_ORDER_ITEM_acceptance.sql` (A1-A9)
- `scripts/bigquery/tests/V_ORDER_CROSS_SELL_acceptance.sql` (B1-B8, covers both `V_ORDER_CROSS_SELL` and `V_ORDER_BASKET`)

Every row must read `PASS`. See **Acceptance-suite semantics** above before
treating a `FAIL` (or a `PASS`) at face value — several checks have
non-obvious edge cases baked into their design.
