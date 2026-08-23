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

**Two different completeness bars — use the right one for the job.**
`is_month_complete` is `coverage_pct >= 99.99`, a strict bar chosen to match
the tie-out verification the schema-divergence section describes (the exact
bar that makes an asymptotic month count as "done"). This SOP's operational
rule above is looser — `coverage_pct >= 99` — because 99.99 is stricter than
any real month needs to be trusted for basket analysis. Verified 2026-08-23,
of the 13 months with any item coverage at all (2024-08 through 2025-08):
`is_month_complete` is TRUE for only **3** (2024-08, 2024-11, 2025-06); the
operational `>= 99` bar admits **12** — every month in that range clears it
except 2025-08 at 98.93%, just under. Filtering `WHERE is_month_complete` —
the obvious thing to do with a column named that — silently discards nine
months that are perfectly usable for analysis. Use `is_month_complete` only
when you need the strict tie-out guarantee; use `coverage_pct >= 99` (the
rule above) for ordinary basket/cross-sell analysis.

## What the coverage gate does NOT guarantee

`V_ORDER_ITEM_COVERAGE.coverage_pct` answers exactly one question: *of the
order headers currently on file for this month, how many have their line
items arrived?* It does **not** answer *are the headers themselves complete
for this month?* — those are two different failure modes, and the gate is
blind to the second one.

**Two different horizons feed this pipeline.** `V_ORDER_ITEM_COVERAGE` reads
`V_SRC_ListOrder`/`V_SRC_ListOrderItems` — the live source — while
`items_through_date` (on every `V_ORDER_CROSS_SELL` row) is `MAX(purchase_date)`
from `FACT_CUSTOMER_ORDER_ITEM`, the loaded table; between a Daton sync and
the next `SP_LOAD_FACT_CUSTOMER_ORDER_ITEM` run, the gate can report a month
covered while those lines are not yet in the fact at all.

**Worked example: 2024-08 reads 100% and is still wrong.**

```
month,      fact_units, st_units, diff
2024-08-01, 434,        1043,     -609
2024-11-01, 3639,       3639,     0
2025-06-01, 799,        799,      0
```

`V_ORDER_ITEM_COVERAGE` reports August 2024 at 100% coverage — correctly, by
its own definition: every header present that month does have its items (A6,
the header-reconciliation check, confirms 0 mismatches). But the headers
themselves are incomplete. `V_SRC_ListOrder` — the order-HEADER feed, upstream
of everything in this pipeline — is sparse from 2024-08-01 through roughly
2024-08-20 (a handful of orders a day against 25-50 units/day of real Sales &
Traffic volume), then ties Sales & Traffic almost exactly from **2024-08-22**
onward (22=22, 23=20/20, 25=37/37, 31=44/44, day-by-day). This is the SP-API
Orders **two-year retention boundary**: as of today (2026-08-23) an order
placed before roughly 2024-08-22 falls outside that window and the API no
longer returns it by default — the handful that do appear earlier (back to
2024-08-03) are orders that surfaced only because something about them was
updated later, not a complete record of that period. Comparing 2024-08 fact
units (434) against Sales & Traffic (1043) makes the gap concrete: **-609
units**, entirely a header problem, not an item-sync problem — confirmed by
A6 passing clean on the same month.

**Reconciling an apparent contradiction:** this SOP says history floors at
~2024-08-22 elsewhere, while the earliest order in the fact is 2024-08-03.
Both are true at once and describe different things. ~2024-08-22 is where
**complete** history starts — the header feed ties Sales & Traffic from there
on. 2024-08-03 is merely the earliest **surviving** order from before that —
a scattered straggler the API still returns because it was touched again
after the retention window would otherwise have dropped it. Do not read
2024-08-03 as "data starts here"; read ~2024-08-22 as "data starts here."

**Practical rule:** for any analysis reaching into 2024-08, do not trust the
coverage gate alone — cross-check the month against
`SRC_ACC_SALES_TRAFFIC_DAILY` units the same way the worked example above
does. This class of gap (headers missing, not just items lagging) is
specific to the two-year retention boundary and is not expected elsewhere,
but the cross-check is cheap and worth running on **any** month whose numbers
look surprising, not only August 2024 — coverage_pct cannot tell you if it is
wrong about something upstream of itself.

**The tie-out method itself is sound.** The other two qualifying months
(`coverage_pct >= 99.99`) tie exactly: 2024-11 (3,639 = 3,639) and 2025-06
(799 = 799), both diff 0. 2024-08 is a real data boundary, not a broken
comparison — the method correctly flags it as an outlier rather than
silently averaging it away.

**Go / no-go, verified 2026-08-23** (the item feed's horizon moves as the
backfill progresses — re-run `V_ORDER_ITEM_COVERAGE` before trusting this
list on a later date; it is a snapshot, not a standing fact):

| Range | Status |
|---|---|
| 2024-09 through 2025-07 | Usable for basket/cross-sell analysis, every month at `coverage_pct` 99.7-100% — subject to the 2024-08-style residual gaps already documented, and always worth a spot cross-check |
| 2025-08 | **Not clean** — `coverage_pct` 98.93%, just under the 99% bar; do not draw conclusions from it without cross-checking against Sales & Traffic first |
| 2025-09 | **Not usable** — `coverage_pct` 4.27%, mid-backfill |
| 2025-10 through 2026-08 | **Not usable** — `coverage_pct` 0.0%, not yet reached by the item-feed backfill |

Item feed horizon (`MAX(purchase_date)` in `FACT_CUSTOMER_ORDER_ITEM`) as of
2026-08-23: **2025-08-28**. Anything past that date has no line items at all
yet, regardless of how many order headers exist for it.

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

**B7 can FAIL benignly on ordinary sync lag — this is the same class of
problem A1 has, just undocumented until now.** B7 compares `V_ORDER_BASKET`'s
`is_canceled`, which is *frozen* onto `FACT_CUSTOMER_ORDER_ITEM` at load time,
against `V_SRC_ListOrder.is_canceled`, which is *live*. If a customer cancels
an order in the window between a Daton sync and the next
`SP_LOAD_FACT_CUSTOMER_ORDER_ITEM` run, `V_SRC_ListOrder` already shows it
canceled while the frozen fact (and therefore `V_ORDER_BASKET`) still does
not — B7 reads that order as "canceled order leaked into the basket view" and
fails, even though nothing is actually broken. As with A1, **rerun the loader
before treating a B7 FAIL as a real defect** — it may just mean the last load
predates the latest cancellation.

**B5 only examines windows that HAVE rows.** It groups the cross-sell view by
`window_days` and checks `MAX(total_orders) > 0` for each group present — a
window that produces *zero rows* (see Windows, below) is invisible to it, not
failing. B5 validates whichever windows currently have rows in them, which
can be one, two, or three of the 90/365/9999 windows depending on where the
item-feed backfill sits relative to each window's cutoff on any given day —
today that is two of the three, not one. Do not read a green B5 as proof
*all three* windows are healthy; check which windows actually have rows
(see Windows, below) before drawing that conclusion.

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

**The rule, not a snapshot:** each window's cutoff is computed from *today*,
but the fact only has line items up to `items_through_date` (the item feed
backfills oldest-first and lags the header feed badly — see the coverage gate
above), and nothing past it. A window's effective data range is therefore
never "the last N days" — it is whatever overlap exists between
`[cutoff, today]` and `[order history start, items_through_date]`. Two
things can happen while the backfill is behind `today`:

- **`items_through_date` falls before the window's cutoff** (the cutoff asks
  for dates newer than anything loaded): the overlap is empty and the window
  returns **zero rows**. Safe — it reads as "no data" and gets treated with
  the suspicion it deserves.
- **`items_through_date` falls at or after the window's cutoff, but still
  before today** (the backfill's horizon lands inside the window's range):
  the overlap is real but is only `items_through_date − cutoff` days wide,
  not the full `window_days`. This is the dangerous case — the window
  returns actual rows, typically with `co_orders = 1` on each pair, that
  look like a genuine N-day answer and get trusted as one, when they in fact
  describe a thin, accidental sliver at the tail of the backfill.

A window is only a trustworthy picture of its stated length once
`items_through_date` has caught up to (or past) `today` for that window —
i.e. the backfill has fully closed the gap to the present.

**Before trusting any non-lifetime window, compare `items_through_date`
(carried on every row) against that window's cutoff** — computed as
`DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL window_days DAY)`. If
`items_through_date` is not at (or very near) today, the window's rows are
either empty or a partial-backfill sliver — never the full lookback period
its name implies. **Prefer `window_days = 9999` for any real analysis until
the backfill has caught up to the present** — it is the only window immune
to this failure mode, because its cutoff (1999-04-08, see below) sits behind
all order history rather than chasing a moving `today`.

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
prevent double-counting a *pair*: the downstream `COUNT(DISTINCT ...)` over
the composite `(selling_partner_id, amazon_order_id)` order key in the
`pairs` CTE is what actually guarantees each pair is counted once per order.
A reviewer proved the `DISTINCT` in `scoped` is redundant for pair-counting
by building the un-deduplicated variant and diffing — zero rows differed. It
is kept anyway because it is cheap and correct defense-in-depth against the
join fanning out before the aggregation that actually enforces correctness
runs.

## How to actually query this

Neither view exposes per-product **units** within a basket on its own.
`V_ORDER_BASKET.basket_label` is a `STRING_AGG(DISTINCT ...)` — it drops
quantities, so a basket with two of the same product looks identical to a
basket with one. `V_ORDER_CROSS_SELL` counts **orders** a pair appeared in
(`co_orders`), not units of either product. Both views deliberately
summarise; line-level quantity only lives in `FACT_CUSTOMER_ORDER_ITEM`.
Answering "which products were in this order and how many of each" means
joining back to it.

### (a) Basket composition for one family

Orders containing a given family, with every product in the basket and its
unit count:

```sql
SELECT b.purchase_date, b.amazon_order_id, b.basket_kind, b.units AS basket_units,
       STRING_AGG(FORMAT('%s x%d', f.product_short_name, f.quantity_ordered)
                  ORDER BY f.product_short_name) AS units_per_product
FROM `onyga-482313.OI.V_ORDER_BASKET` b
JOIN `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM` f USING (selling_partner_id, amazon_order_id)
WHERE NOT f.is_canceled AND f.quantity_ordered > 0
  AND b.amazon_order_id IN (
    SELECT amazon_order_id FROM `onyga-482313.OI.FACT_CUSTOMER_ORDER_ITEM`
    WHERE parent_name = 'Lollibox' AND NOT is_canceled AND quantity_ordered > 0)
GROUP BY 1,2,3,4 HAVING COUNT(*) > 1 ORDER BY b.purchase_date DESC LIMIT 20
```

Verified 2026-08-23 — runs and returns Lollibox baskets, most recent five:

| purchase_date | amazon_order_id | basket_kind | basket_units | units_per_product |
|---|---|---|---|---|
| 2025-08-27 | 111-3190523-9194648 | MULTI_PRODUCT | 2 | Purple Lollibox x1, White Lollibox x1 |
| 2025-08-27 | 111-6271888-6155443 | MULTI_PRODUCT | 2 | Blue Lollibox x1, Pink LolliME x1 |
| 2025-08-25 | 112-8160273-8805047 | MULTI_PRODUCT | 2 | Pink Lollibox x1, White Lollibox x1 |
| 2025-08-19 | 112-5912954-9044227 | MULTI_PRODUCT | 2 | Fresh in Beige x1, Pink Lollibox x1 |
| 2025-08-19 | 111-1172590-9264224 | MULTI_PRODUCT | 2 | Fresh in Pink x1, Purple Lollibox x1 |

Swap `parent_name = 'Lollibox'` for any other family to answer this question
for that family. This is the query to run for LolliBall once the backfill
reaches **2026-06-26** (LolliBall's first sale) — before that,
`V_ORDER_ITEM_COVERAGE` will show no items for that month and an empty
result means "not loaded yet," not "no one buys two LolliBalls."

### (b) Which products sell together, aggregated

A `V_ORDER_CROSS_SELL` query with the `co_orders` guard applied (drop
low-count pairs before trusting `lift`) and gated on `both_mapped` (per
`same_family` semantics, above — an unmapped side makes `same_family`
meaningless):

```sql
SELECT name_a, name_b, family_a, family_b, same_family, co_orders, lift
FROM `onyga-482313.OI.V_ORDER_CROSS_SELL`
WHERE window_days = 9999 AND co_orders >= 5 AND both_mapped
ORDER BY same_family DESC, lift DESC
```

Verified 2026-08-23 — real output, all 18 qualifying rows:

| name_a | name_b | family_a | family_b | same_family | co_orders | lift |
|---|---|---|---|---|---|---|
| Mint LolliME | Pink LolliME | LolliME | LolliME | true | 12 | 4.29 |
| Purple LolliME | Pink LolliME | LolliME | LolliME | true | 10 | 3.70 |
| Mint LolliME | Purple LolliME | LolliME | LolliME | true | 10 | 3.59 |
| Fresh in Beige | Fresh in Pink | Fresh | Fresh | true | 153 | 1.12 |
| Purple Lollibox | Blue Lollibox | Lollibox | Lollibox | true | 108 | 0.43 |
| Purple Lollibox | Pink Lollibox | Lollibox | Lollibox | true | 242 | 0.42 |
| Pink Lollibox | Blue Lollibox | Lollibox | Lollibox | true | 103 | 0.41 |
| White Lollibox | Pink Lollibox | Lollibox | Lollibox | true | 329 | 0.20 |
| White Lollibox | Blue Lollibox | Lollibox | Lollibox | true | 130 | 0.18 |
| Purple Lollibox | White Lollibox | Lollibox | Lollibox | true | 259 | 0.16 |
| Fresh in Beige | Blue Lollibox | Fresh | Lollibox | false | 7 | 0.09 |
| Pink Lollibox | Fresh in Beige | Lollibox | Fresh | false | 12 | 0.07 |
| Pink Lollibox | Fresh in Pink | Lollibox | Fresh | false | 27 | 0.06 |
| Purple Lollibox | Fresh in Beige | Lollibox | Fresh | false | 11 | 0.06 |
| Purple Lollibox | Fresh in Pink | Lollibox | Fresh | false | 20 | 0.05 |
| White Lollibox | Fresh in Beige | Lollibox | Fresh | false | 28 | 0.05 |
| White Lollibox | Fresh in Pink | Lollibox | Fresh | false | 50 | 0.04 |
| Fresh in Pink | Blue Lollibox | Fresh | Lollibox | false | 5 | 0.03 |

**Read this for what it actually says, not what might be assumed.** Every
cross-family pair here (`same_family = false`) sits well below 1.0 — the
highest is 0.09. It is *same*-family variant pairs that produce the highest
lift: LolliME color variants cluster from 3.59 to 4.29, meaning buyers pick
up two-plus LolliME colors together far more than chance would predict.
Lollibox variant pairs, by contrast, mostly sit below 1.0 (0.16-0.43) —
buyers who take one Lollibox color are *less* likely than chance to add a
second, i.e. colors substitute for each other rather than stacking. Fresh
in Beige / Fresh in Pink is the one same-family pair that lands just above
1.0 (1.12) at real volume (153 co-orders). Do not assume same-family pairs
are low-lift substitutes and cross-family pairs are the real cross-sell
signal — on this data, it is the reverse: cross-family affinity is
uniformly weak, and same-family affinity varies by family from strong
complement (LolliME) to substitute (Lollibox). Re-run this query rather than
trusting last measurement — these numbers move every time the item feed
backfills further.

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
