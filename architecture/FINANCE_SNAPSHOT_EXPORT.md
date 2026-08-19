# SOP — Finance Snapshot Export (BigQuery → budget folder)

**Tool:** `tools/export_finance_snapshot.py` · **Make target:** `make export-finance`
**Consumer:** Claude Cowork's family financial dashboard in `/Users/ori/budget/`
**Created:** 2026-08-15 · **Extended:** 2026-08-15 (v2 — history + vendor debt)

## Purpose

Give the household financial report a current inventory valuation (an asset the
dashboard otherwise can't see), a monthly ads sales/spend series, and the
vendor debt position, without Cowork needing BigQuery access.

## Contract

Writes to `/Users/ori/budget/data/` (override with `--out-dir`):

| File | Grain | Source |
|---|---|---|
| `inventory_snapshot.csv` | latest `Date` × `source_type` | `FACT_INVENTORY_SNAPSHOT` |
| `inventory_by_product.csv` | latest `Date` × `parent_name` × `product_short_name` | `FACT_INVENTORY_SNAPSHOT` ⋈ `DIM_PRODUCT` |
| `ads_sales_monthly.csv` | calendar month | `FACT_AMAZON_ADS` |
| `inventory_history.csv` | month (valued snapshots only) | `FACT_INVENTORY_SNAPSHOT` |
| `purchase_orders.csv` | PO header | `DE_PURCHASE_ORDERS` ⋈ `DE_VENDOR_PAYMENTS` |
| `freight_shipments.csv` | shipment | `DE_MANUFACTURER_SHIPMENTS` ⋈ `DE_VENDOR_PAYMENTS` |
| `vendor_payments.csv` | payment allocation | `DE_VENDOR_PAYMENTS` |
| `other_purchase_orders.csv` | other-PO | `DE_OTHER_PO` ⋈ `DE_VENDOR_PAYMENTS` |
| `product_costs.csv` | ASIN (current cost row) | `DIM_COSTS_HISTORY` ⋈ `DIM_PRODUCT` |
| `export_meta.json` | — | freshness, coverage, caveats, row counts |

Writes are **atomic** (temp file + `os.replace`) so a mid-export read can never
see a truncated CSV.

## Rules

- **The export tool is read-only.** SELECT only; it creates and writes nothing.
  (The one BigQuery change in this SOP — `LANDED_COGS_AMOUNT`, 2026-08-15 — was
  a separate approved migration, registered in `config.yaml`.)
- **No new grain invented.** The export ships raw sums; every derived metric
  (Net Profit, Net ROAS, TACoS) stays in Cube. See `DB_FIELD_LINEAGE.md`.
- Inventory is a **full re-snapshot per `Date`**, so "current" = `MAX(Date)`.
  There is no as-of/incremental logic to get wrong.

## ⚠️ `COGS_AMOUNT` is not a landed cost — use `landed_cogs_value`

Investigated 2026-08-15 after Ori spotted White Lollibox at $31.08/unit against a
true cost of $12.75 + $3.28 = $16.03.

**Root cause.** `SP_LOAD_FACT_INVENTORY_SNAPSHOT` values stock at
`DIM_COSTS_HISTORY.TOTAL_COST_PER_UNIT`, and that column is

```
TOTAL_COST_PER_UNIT = cost_of_goods + shipping_cost + FBA_COST_estimated_fee_total
31.8524             = 12.7599       + 3.2825        + 15.81
                                        (15.81 = 7.65 pick&pack + 8.16 referral)
```

It is a **fully-loaded unit-economics cost** — correct for the profit on a unit
that *sells*, wrong for valuing a unit that *hasn't sold*. Amazon's pick&pack and
referral fees are incurred at the moment of sale; capitalising them into on-hand
stock inflates the asset. Both COGS paths in the loader are affected: the owned
path (`quantity × TOTAL_COST_PER_UNIT`) and the manufacturer path
(`FACT_PURCHASE_ORDER.cogs_remaining_at_manufacturer`), which is built on the
same loaded cost.

**Not** a double-count, **not** a join fan-out, **not** a per-unit/total mixup —
the three original suspects. Quantities are correct and `cost_of_goods` /
`shipping_cost` on the FACT are correct; only the *cost concept* is wrong.

This also explains the "52–62% of sell price" pattern that looked like systematic
inflation: the referral fee is 15% of sell price *by definition*, so a loaded
cost necessarily tracks price.

**Overstatement** (total COGS_AMOUNT ÷ landed): 2.08× at 2024-12-31, 2.12× at
2025-12-31, 2.25× at 2026-08-15.

| Date | `total_cogs` (FACT) | `total_landed_cogs` (true) |
|---|---|---|
| 2024-12-31 | $314,012 | **$150,952** |
| 2025-12-31 | $434,142 | **$204,651** |
| 2026-08-15 | $1,265,418 | **$562,686** |

**Fix — additive column, approved by Ori 2026-08-15.**
`FACT_INVENTORY_SNAPSHOT.LANDED_COGS_AMOUNT` was added alongside `COGS_AMOUNT`,
which keeps its current meaning so every existing consumer is untouched.

| Layer | Change |
|---|---|
| Table | `ALTER TABLE ADD COLUMN` + backfill — `scripts/bigquery/migrations/2026-08-15_landed_cogs_amount.sql` (35,004 rows, 0 NULL, 0 mismatches) |
| Loader | `SP_LOAD_FACT_INVENTORY_SNAPSHOT` populates it on every run |
| Cube | measure `InventorySnapshot.totalLandedCogs` ("Landed COGS Value"); `totalCogs` retitled "COGS Value (incl. Amazon fees)" |
| Export | reads the column instead of recomputing, so the definition lives only in the loader |

**Never `CREATE OR REPLACE` this table.** The live schema carried `PAID_AMOUNT`
which the repo DDL did not — replacing from DDL would have silently dropped it.
The DDL is now in sync, but the ALTER-only rule stands (same doctrine as
`DIM_US_HOLIDAYS`).

The 8 ASINs with no `DIM_COSTS_HISTORY` row (48 of 222 snapshot rows) all hold
**zero units**, so the landed total is complete, not understated.

⚠️ **Production Cube not deployed.** The measure is live on the local dev Cube
(verified end-to-end). Shipping it to Cloud Run needs
`./deployment/deploy_all.sh cube`, which uploads the **working tree** — stash
unrelated WIP first.

## Reading the numbers

- `landed_cogs_value` = what the stock actually cost us (manufacturing +
  freight) — **this is the assets figure.**
- `cogs_value` = the FACT's `COGS_AMOUNT`, fee-loaded. Kept for continuity and
  reconciliation only. `amazon_fees_in_cogs_value` is the difference.
- `sell_value` = retail value at list price — a ceiling, not an expected
  realization. Never add it to assets alongside the cost figures.
- `paid_amount` is non-zero only for `MFR Ready` (supplier deposits already
  paid); the rest is unpaid at snapshot time.
- `source_type` spans the whole pipeline — `MFR Ready`, `In Production`,
  `In Transit`, `In Transit AWD`, `AWD`, `FBA`. Only `FBA` (and `AWD`) is
  sellable now; the rest is capital in flight. Don't treat the total as
  available stock.
- `ads_sales_monthly.csv`: the last row carries `is_partial=true`. Ads data
  lags 1–2 days and restates for up to ~2 weeks (see
  `fact_oi_ads_restatement_settle`), so the current month is always understated.
  `days_with_data` tells you how much of the month is actually covered.
- These are **ad-attributed** sales, not total Amazon sales. Organic revenue is
  not in this file.

## Inventory history — most dates are not valued

`FACT_INVENTORY_SNAPSHOT` looks daily but is not. Most dates carry **14 FBA-only
rows with NULL `COGS_AMOUNT` / `SELL_AMOUNT`** — placeholders, not valuations. A
real snapshot is 222 rows across all six `source_type` values.

Valued dates as of 2026-08-15: **2024-12-31, 2025-12-31, and daily from
2026-04-01 on**. `2026-03` has no rows at all; `2026-02` stops at the 3rd.

`inventory_history.csv` therefore emits **only months with a valued snapshot**
(7 rows), and lists the skipped months in
`export_meta.inventory_months_without_valued_snapshot`. Emitting blank value
columns for the placeholder months would invite the reader to sum them as zero.

Year-over-year at year-end works — both 2024-12-31 and 2025-12-31 are valued:
landed inventory **$150,952 → $204,651 (+35.6%)**. A month-by-month 2025 series
does not exist.

## Vendor debt — where the money actually lives

Two vendors, two completely different billing paths:

| Vendor | Role | Billed in | Paid in |
|---|---|---|---|
| SYLVIA | manufacturer | `DE_PURCHASE_ORDERS` | `DE_VENDOR_PAYMENTS` (`purchase_order_id`) |
| ANNA | freight forwarder | `DE_MANUFACTURER_SHIPMENTS.cost_shipped` | `DE_VENDOR_PAYMENTS` (`shipment_id`) |

**ANNA has no purchase orders at all.** Any "open debt" built from
`DE_PURCHASE_ORDERS` alone reports the freight forwarder as owing nothing.

Traps, all verified 2026-08-15:

- `DE_PURCHASE_ORDERS` is **one row per PO line** (69 rows / 46 POs). Joining
  payments at row grain fans the paid amount across lines — aggregate to header
  grain first. There is no `po_number` / `supplier` / `status` column; the real
  names are `purchase_order_id` / `manufacturer_name` / `payment_status`.
- `payment_status` is `PENDING` on **every** PO row and `deposit` is `0` on every
  row. Neither field is maintained — the payment ledger is the only truth.
- `DE_VENDOR_PAYMENTS` is **one row per allocation**, not per payment. See
  [`fact_oi_vendor_payments_allocation_grain`]. 323 rows, all USD, no orphans.
- `is_paid` on shipments and the payment ledger **disagree**: the flag leaves
  $51,189 of freight unpaid, the ledger $53,404. Both ship; pick deliberately.
- 5 allocations totalling $5,877 are labelled vendor `ANNA` but applied to
  SYLVIA manufacturing POs, and 2 ANNA payments totalling $16,982 are
  `UNLINKED` — they reduce no balance anywhere. Summing `open_balance` across
  files overstates debt by that amount.

Position at 2026-08-15: SYLVIA billed $833,396 / paid $639,348 / **open
$194,049**; ANNA billed $163,599 / paid $110,196 / **open $53,404**; other-POs
open $125. Ledger cash out $770,661 reconciles to the four files exactly.

## Schema note (2026-08-15)

`FACT_AMAZON_ADS` measure columns are `Ads_sales`, `Ads_cost`, `Ads_orders`,
`Ads_clicks`, `Ads_impressions` — there are no bare `sales` / `ad_spend` /
`orders` columns. The table summary in `CLAUDE.md` and in the `oi-data-analyst`
skill reference is stale on this point; verified against
`INFORMATION_SCHEMA.COLUMNS`.

## Scheduling

Manual today. A daily launchd job is a reasonable next step but has **not** been
installed — it needs Ori's go-ahead.
