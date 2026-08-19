#!/usr/bin/env python3
"""Export a read-only financial snapshot from BigQuery to the budget folder.

Writes to --out-dir (default /Users/ori/budget/data):
    inventory_snapshot.csv     latest inventory snapshot, by source_type
    inventory_by_product.csv   same snapshot, by product family / short name
    ads_sales_monthly.csv      monthly ads sales / spend / orders
    inventory_history.csv      end-of-month inventory value, owned vs factory
    purchase_orders.csv        manufacturer POs (header grain) + paid + open balance
    freight_shipments.csv      freight shipments + paid + open balance
    vendor_payments.csv        payment allocation ledger, by date
    other_purchase_orders.csv  non-manufacturing POs (sampling, certs, photos)
    export_meta.json           freshness, coverage and row counts

Read-only: SELECT statements only, no BigQuery objects created or modified.
Files are written atomically (temp file + rename) so a reader never sees a
half-written CSV.

Usage:
    python tools/export_finance_snapshot.py [--out-dir DIR] [--quiet]
"""

import argparse
import csv
import datetime as dt
import json
import os
import sys
import tempfile

from google.cloud import bigquery

PROJECT = "onyga-482313"
DATASET = "OI"
US_MARKETPLACE = "ATVPDKIKX0DER"
DEFAULT_OUT_DIR = "/Users/ori/budget/data"

# ── Queries ───────────────────────────────────────────────────────────────
# All three read the FACT tables directly. FACT_INVENTORY_SNAPSHOT is a full
# re-snapshot per Date, so "latest snapshot" == MAX(Date).

# COGS_AMOUNT is NOT a landed inventory cost. It is built from
# DIM_COSTS_HISTORY.TOTAL_COST_PER_UNIT, which equals
#   cost_of_goods + shipping_cost + Amazon pick&pack + Amazon referral fee.
# Those Amazon fees are only incurred when a unit SELLS, so capitalising them
# into on-hand stock overstates the asset by ~2.25x (see the SOP).
# LANDED_COGS_AMOUNT (added to the FACT 2026-08-15, migration
# 2026-08-15_landed_cogs_amount.sql) is the balance-sheet figure. The export
# reads the column rather than recomputing it, so the definition lives in one
# place — the loader.
LANDED = "LANDED_COGS_AMOUNT"
LANDED_S = "s.LANDED_COGS_AMOUNT"

Q_INVENTORY_SNAPSHOT = f"""
SELECT Date,
       source_type,
       SUM(quantity_balance) AS units,
       SUM({LANDED})         AS landed_cogs_value,
       SUM(COGS_AMOUNT)      AS cogs_value,
       SUM(COGS_AMOUNT) - SUM({LANDED}) AS amazon_fees_in_cogs_value,
       SUM(SELL_AMOUNT)      AS sell_value,
       SUM(PAID_AMOUNT)      AS paid_amount
FROM `{PROJECT}.{DATASET}.FACT_INVENTORY_SNAPSHOT`
WHERE Date = (SELECT MAX(Date) FROM `{PROJECT}.{DATASET}.FACT_INVENTORY_SNAPSHOT`)
GROUP BY Date, source_type
ORDER BY source_type
"""

Q_INVENTORY_BY_PRODUCT = f"""
SELECT agg.Date,
       p.parent_name AS product_family,
       p.product_short_name,
       SUM(agg.quantity_balance) AS units,
       SUM(agg.LANDED_COGS_AMOUNT) AS landed_cogs_value,
       SUM(agg.COGS_AMOUNT)      AS cogs_value,
       SUM(agg.SELL_AMOUNT)      AS sell_value
FROM `{PROJECT}.{DATASET}.FACT_INVENTORY_SNAPSHOT` agg
LEFT JOIN `{PROJECT}.{DATASET}.DIM_PRODUCT` p
  ON p.asin = agg.ASIN AND p.marketplace = '{US_MARKETPLACE}'
WHERE agg.Date = (SELECT MAX(Date) FROM `{PROJECT}.{DATASET}.FACT_INVENTORY_SNAPSHOT`)
GROUP BY 1, 2, 3
ORDER BY landed_cogs_value DESC
"""

# NOTE: FACT_AMAZON_ADS columns are Ads_sales / Ads_cost / Ads_orders — there
# are no bare `sales` / `ad_spend` / `orders` columns (CLAUDE.md's schema note
# is stale). Verified against INFORMATION_SCHEMA.COLUMNS 2026-08-15.
# is_partial marks the current (still accruing) month: ads data lags 1-2 days
# and spend/sales restate for up to ~2 weeks, so the last row is never final.
Q_ADS_SALES_MONTHLY = f"""
WITH monthly AS (
  SELECT FORMAT_DATE('%Y-%m', date) AS month,
         SUM(Ads_sales)  AS ads_sales,
         SUM(Ads_cost)   AS ad_spend,
         SUM(Ads_orders) AS orders,
         COUNT(DISTINCT date) AS days_with_data
  FROM `{PROJECT}.{DATASET}.FACT_AMAZON_ADS`
  GROUP BY 1
)
SELECT month, ads_sales, ad_spend, orders, days_with_data,
       month = (SELECT MAX(month) FROM monthly) AS is_partial
FROM monthly
ORDER BY month
"""

Q_ADS_MAX_DATE = f"""
SELECT MAX(date) AS max_date FROM `{PROJECT}.{DATASET}.FACT_AMAZON_ADS`
"""

# End-of-month inventory value.
#
# Most dates in FACT_INVENTORY_SNAPSHOT are NOT valued snapshots: they carry 14
# FBA-only rows with NULL COGS_AMOUNT / SELL_AMOUNT. Only a handful of dates
# hold a real 222-row, six-source-type valued snapshot (2024-12-31, 2025-12-31,
# and daily from 2026-04 on). Taking MAX(Date) per month therefore lands on a
# placeholder for most months and produces empty value columns, which a
# consumer can easily read as "inventory was zero".
#
# So this restricts month-ends to VALUED snapshots and skips the months that
# have none. The skipped months are reported in export_meta.json rather than
# emitted as blank rows — explicit absence beats ambiguous emptiness.
#
# The owned/factory CASE arms cover all six source_type values that have ever
# appeared (verified 2026-08-15), so owned + factory == total.
Q_INVENTORY_HISTORY = f"""
WITH valued_dates AS (
  SELECT Date
  FROM `{PROJECT}.{DATASET}.FACT_INVENTORY_SNAPSHOT`
  GROUP BY Date
  HAVING COUNTIF(COGS_AMOUNT IS NOT NULL) > 0
),
month_ends AS (
  SELECT FORMAT_DATE('%Y-%m', Date) AS month,
         MAX(Date) AS snap_date,
         COUNT(*)  AS valued_days_in_month
  FROM valued_dates
  GROUP BY 1
)
SELECT m.month,
       m.snap_date,
       m.valued_days_in_month,
       m.snap_date = LAST_DAY(m.snap_date) AS is_month_end,
       SUM(CASE WHEN s.source_type IN ('FBA','AWD','In Transit','In Transit AWD')
                THEN {LANDED_S} ELSE 0 END) AS owned_landed_cogs,
       SUM(CASE WHEN s.source_type IN ('MFR Ready','In Production')
                THEN {LANDED_S} ELSE 0 END) AS factory_landed_cogs,
       SUM({LANDED_S})         AS total_landed_cogs,
       SUM(CASE WHEN s.source_type IN ('FBA','AWD','In Transit','In Transit AWD')
                THEN s.COGS_AMOUNT ELSE 0 END) AS owned_cogs,
       SUM(CASE WHEN s.source_type IN ('MFR Ready','In Production')
                THEN s.COGS_AMOUNT ELSE 0 END) AS factory_cogs,
       SUM(CASE WHEN s.source_type IN ('MFR Ready','In Production')
                THEN s.PAID_AMOUNT ELSE 0 END) AS factory_paid,
       SUM(s.COGS_AMOUNT)      AS total_cogs,
       SUM(s.SELL_AMOUNT)      AS total_sell,
       SUM(s.quantity_balance) AS total_units
FROM `{PROJECT}.{DATASET}.FACT_INVENTORY_SNAPSHOT` s
JOIN month_ends m ON s.Date = m.snap_date
GROUP BY 1, 2, 3, 4
ORDER BY 1
"""

# Months present in the snapshot table but with no valued snapshot at all —
# reported in export_meta.json so the gaps in inventory_history.csv are stated,
# not merely absent.
Q_INVENTORY_UNVALUED_MONTHS = f"""
SELECT FORMAT_DATE('%Y-%m', Date) AS month
FROM `{PROJECT}.{DATASET}.FACT_INVENTORY_SNAPSHOT`
GROUP BY 1
HAVING COUNTIF(COGS_AMOUNT IS NOT NULL) = 0
ORDER BY 1
"""

# DE_PURCHASE_ORDERS is one row per PO *line* (69 rows / 46 POs), so payments
# must be joined at header grain or the paid amount fans out across the lines.
# Real columns are purchase_order_id / manufacturer_name — there is no
# po_number / supplier / status column. payment_status is 'PENDING' on every
# row and `deposit` is always 0, so neither can be used to derive what is
# owed; the payment ledger is the only source of truth for money paid.
Q_PURCHASE_ORDERS = f"""
WITH po_header AS (
  SELECT purchase_order_id,
         MIN(order_date)              AS order_date,
         MIN(manufacturer_name)       AS supplier,
         MIN(currency)                AS currency,
         MIN(payment_status)          AS payment_status,
         MAX(remaining_payment_date)  AS remaining_payment_date,
         MAX(estimated_arrival_date)  AS estimated_arrival_date,
         COUNT(*)                     AS line_count,
         SUM(quantity)                AS quantity,
         SUM(total_amount)            AS total_amount,
         SUM(IFNULL(adjustments, 0))  AS adjustments
  FROM `{PROJECT}.{DATASET}.DE_PURCHASE_ORDERS`
  GROUP BY 1
),
allocated AS (
  SELECT purchase_order_id,
         SUM(payment_amount)        AS paid_amount,
         SUM(IFNULL(bank_fee, 0))   AS bank_fees,
         MAX(payment_date)          AS last_payment_date
  FROM `{PROJECT}.{DATASET}.DE_VENDOR_PAYMENTS`
  WHERE purchase_order_id IS NOT NULL
  GROUP BY 1
)
SELECT h.purchase_order_id,
       h.order_date,
       h.supplier,
       h.currency,
       h.payment_status,
       h.line_count,
       h.quantity,
       h.total_amount,
       h.adjustments,
       h.total_amount + h.adjustments AS billed_amount,
       IFNULL(a.paid_amount, 0)       AS paid_amount,
       IFNULL(a.bank_fees, 0)         AS bank_fees,
       h.total_amount + h.adjustments - IFNULL(a.paid_amount, 0) AS open_balance,
       a.last_payment_date,
       h.remaining_payment_date,
       h.estimated_arrival_date
FROM po_header h
LEFT JOIN allocated a USING (purchase_order_id)
ORDER BY h.order_date, h.purchase_order_id
"""

# Freight (ANNA) is billed here, not in DE_PURCHASE_ORDERS — the freight
# forwarder has no PO rows at all. Two independent "paid" signals exist and
# they disagree: the is_paid flag and the actual payment allocations. Both
# ship so the discrepancy is visible rather than silently resolved.
Q_FREIGHT_SHIPMENTS = f"""
WITH allocated AS (
  SELECT shipment_id,
         SUM(payment_amount) AS paid_amount,
         MAX(payment_date)   AS last_payment_date
  FROM `{PROJECT}.{DATASET}.DE_VENDOR_PAYMENTS`
  WHERE shipment_id IS NOT NULL
  GROUP BY 1
)
SELECT s.shipment_id,
       s.shipment_date,
       s.estimated_arrival_date,
       s.deliverer,
       s.shipment_type,
       s.shipment_status,
       s.total_quantity,
       s.cost_shipped,
       IFNULL(s.amazon_commission, 0) AS amazon_commission,
       s.cost_shipped + IFNULL(s.amazon_commission, 0) AS billed_amount,
       s.is_paid,
       s.paid_date,
       IFNULL(a.paid_amount, 0) AS paid_amount,
       s.cost_shipped + IFNULL(s.amazon_commission, 0)
         - IFNULL(a.paid_amount, 0) AS open_balance,
       a.last_payment_date
FROM `{PROJECT}.{DATASET}.DE_MANUFACTURER_SHIPMENTS` s
LEFT JOIN allocated a USING (shipment_id)
ORDER BY s.shipment_date, s.shipment_id
"""

# One row per ALLOCATION, not per payment — a single wire split across POs or
# shipments appears as several rows. Sum payment_amount for cash out; never
# treat a row as a whole payment. link_type shows what the money was applied
# to; UNLINKED rows reduce no balance anywhere.
Q_VENDOR_PAYMENTS = f"""
SELECT payment_id,
       payment_date,
       vendor_name,
       payment_amount,
       IFNULL(bank_fee, 0) AS bank_fee,
       currency,
       payment_method,
       purchase_order_id,
       shipment_id,
       CASE WHEN purchase_order_id IS NOT NULL AND shipment_id IS NOT NULL THEN 'BOTH'
            WHEN purchase_order_id IS NOT NULL THEN 'PO'
            WHEN shipment_id IS NOT NULL THEN 'SHIPMENT'
            ELSE 'UNLINKED' END AS link_type
FROM `{PROJECT}.{DATASET}.DE_VENDOR_PAYMENTS`
ORDER BY payment_date, payment_id, purchase_order_id, shipment_id
"""

# Per-unit costs straight from the source cost table, so inventory value can be
# recomputed independently of the FACT. Columns are split so the two different
# cost concepts are visible side by side:
#   landed_cost_per_unit      = cost_of_goods + shipping_cost  -> value stock
#   total_cost_per_unit_loaded = landed + Amazon fees          -> unit profit
# DIM_COSTS_HISTORY is versioned by start_date; this takes the current row per
# ASIN, matching what SP_LOAD_FACT_INVENTORY_SNAPSHOT joins (rn = 1). Single
# marketplace, no (asin, start_date) collisions — verified 2026-08-15.
Q_PRODUCT_COSTS = f"""
WITH latest AS (
  SELECT asin, sku, product_name, start_date, end_date,
         cost_of_goods, shipping_cost,
         estimated_pick_pack_fee_per_unit,
         FBA_COST_estimated_referral_fee_per_unit,
         FBA_COST_estimated_fee_total,
         TOTAL_COST_PER_UNIT,
         ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) AS rn
  FROM `{PROJECT}.{DATASET}.DIM_COSTS_HISTORY`
)
SELECT l.asin,
       p.parent_name AS product_family,
       p.product_short_name,
       l.sku,
       l.start_date AS cost_effective_from,
       l.cost_of_goods,
       l.shipping_cost,
       l.cost_of_goods + l.shipping_cost AS landed_cost_per_unit,
       l.estimated_pick_pack_fee_per_unit        AS amazon_pick_pack_fee,
       l.FBA_COST_estimated_referral_fee_per_unit AS amazon_referral_fee,
       l.FBA_COST_estimated_fee_total            AS amazon_fees_total,
       l.TOTAL_COST_PER_UNIT AS total_cost_per_unit_loaded,
       p.listing_price_amount AS list_price
FROM latest l
LEFT JOIN `{PROJECT}.{DATASET}.DIM_PRODUCT` p
  ON p.asin = l.asin AND p.marketplace = '{US_MARKETPLACE}'
WHERE l.rn = 1
ORDER BY p.parent_name, p.product_short_name, l.asin
"""

# Non-manufacturing spend (sampling, certifications, photography, other).
# Allocations reference these by the same purchase_order_id column.
Q_OTHER_PURCHASE_ORDERS = f"""
WITH allocated AS (
  SELECT purchase_order_id AS other_po_id,
         SUM(payment_amount) AS paid_amount
  FROM `{PROJECT}.{DATASET}.DE_VENDOR_PAYMENTS`
  WHERE purchase_order_id IS NOT NULL
  GROUP BY 1
)
SELECT o.other_po_id,
       o.order_date,
       o.service_type,
       o.supplier_name,
       o.total_amount,
       o.currency,
       o.payment_status,
       IFNULL(a.paid_amount, 0) AS paid_amount,
       o.total_amount - IFNULL(a.paid_amount, 0) AS open_balance
FROM `{PROJECT}.{DATASET}.DE_OTHER_PO` o
LEFT JOIN allocated a USING (other_po_id)
ORDER BY o.order_date, o.other_po_id
"""


# ── Helpers ───────────────────────────────────────────────────────────────
def to_csv_value(v):
    if v is None:
        return ""
    if isinstance(v, (dt.date, dt.datetime)):
        return v.isoformat()
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return f"{v:.4f}".rstrip("0").rstrip(".")
    return str(v)


def write_atomic(path, write_fn):
    """Write via a temp file in the same dir, then rename over the target."""
    directory = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".tmp_", suffix=".part")
    try:
        with os.fdopen(fd, "w", newline="", encoding="utf-8") as fh:
            write_fn(fh)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def write_csv(path, columns, rows):
    def _write(fh):
        writer = csv.writer(fh)
        writer.writerow(columns)
        for row in rows:
            writer.writerow([to_csv_value(row[c]) for c in columns])

    write_atomic(path, _write)
    return len(rows)


def write_json(path, payload):
    write_atomic(path, lambda fh: json.dump(payload, fh, indent=2, ensure_ascii=False))


# ── Main ──────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out-dir", default=DEFAULT_OUT_DIR,
                        help=f"output directory (default: {DEFAULT_OUT_DIR})")
    parser.add_argument("--quiet", action="store_true", help="suppress progress output")
    args = parser.parse_args()

    out_dir = os.path.abspath(os.path.expanduser(args.out_dir))
    os.makedirs(out_dir, exist_ok=True)

    def log(msg):
        if not args.quiet:
            print(msg)

    client = bigquery.Client(project=PROJECT)

    # (filename, sql, column whose min/max describes the file's coverage)
    exports = [
        ("inventory_snapshot.csv", Q_INVENTORY_SNAPSHOT, "Date"),
        ("inventory_by_product.csv", Q_INVENTORY_BY_PRODUCT, "Date"),
        ("ads_sales_monthly.csv", Q_ADS_SALES_MONTHLY, "month"),
        ("inventory_history.csv", Q_INVENTORY_HISTORY, "snap_date"),
        ("purchase_orders.csv", Q_PURCHASE_ORDERS, "order_date"),
        ("freight_shipments.csv", Q_FREIGHT_SHIPMENTS, "shipment_date"),
        ("vendor_payments.csv", Q_VENDOR_PAYMENTS, "payment_date"),
        ("other_purchase_orders.csv", Q_OTHER_PURCHASE_ORDERS, "order_date"),
        ("product_costs.csv", Q_PRODUCT_COSTS, "cost_effective_from"),
    ]

    files = []
    snapshot_date = None
    bytes_billed = 0

    for filename, sql, coverage_col in exports:
        job = client.query(sql)
        rows = list(job.result())
        columns = [f.name for f in job.result().schema]
        bytes_billed += job.total_bytes_billed or 0

        path = os.path.join(out_dir, filename)
        n = write_csv(path, columns, rows)

        entry = {"name": filename, "rows": n}
        values = [row[coverage_col] for row in rows if row[coverage_col] is not None]
        if values:
            entry["covers"] = {"from": to_csv_value(min(values)),
                               "to": to_csv_value(max(values)),
                               "column": coverage_col}
        files.append(entry)
        log(f"  {filename:<26} {n:>5} rows")

        if snapshot_date is None and "Date" in columns and rows:
            snapshot_date = rows[0]["Date"].isoformat()

    ads_max = list(client.query(Q_ADS_MAX_DATE).result())[0]["max_date"]
    unvalued_months = [r["month"] for r in client.query(Q_INVENTORY_UNVALUED_MONTHS).result()]

    meta = {
        "exported_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "inventory_snapshot_date": snapshot_date,
        "ads_max_date": ads_max.isoformat() if ads_max else None,
        "source": f"{PROJECT}.{DATASET}",
        "notes": (
            "Read-only export. Inventory values are at the latest FACT_INVENTORY_SNAPSHOT "
            "Date; cogs_value is landed cost, sell_value is retail value at list price. "
            "The last row of ads_sales_monthly.csv has is_partial=true: ads data lags 1-2 "
            "days and restates for up to ~2 weeks, so treat it as incomplete."
        ),
        "inventory_months_without_valued_snapshot": unvalued_months,
        "caveats": [
            "USE landed_cogs_value FOR ASSETS, NOT cogs_value. cogs_value comes from the "
            "FACT's COGS_AMOUNT, which is built on DIM_COSTS_HISTORY.TOTAL_COST_PER_UNIT "
            "= cost_of_goods + shipping_cost + Amazon pick&pack + Amazon referral fee. "
            "Those fees are incurred only when a unit sells, so cogs_value overstates "
            "on-hand inventory by roughly 2.25x. landed_cogs_value = quantity x "
            "(cost_of_goods + shipping_cost) is the balance-sheet figure. Same split in "
            "inventory_history.csv: total_landed_cogs vs total_cogs.",
            "product_costs.csv carries both concepts per unit so inventory value can be "
            "recomputed independently: landed_cost_per_unit for stock value, "
            "total_cost_per_unit_loaded for per-unit profit on a sold unit.",
            "inventory_history.csv covers only months that HAVE a valued snapshot. The "
            "months in inventory_months_without_valued_snapshot hold FBA-only placeholder "
            "rows with no COGS/SELL values and are absent from the file — do not read "
            "their absence as zero inventory. 2026-03 has no rows at all.",
            "Rows with is_month_end=false are the last valued snapshot in that month, not "
            "a true month-end value (e.g. the current, still-running month).",
            "purchase_orders.csv is PO-header grain (lines aggregated). Manufacturer "
            "(SYLVIA) only — the freight forwarder has no POs, its billing is in "
            "freight_shipments.csv.",
            "payment_status on POs is 'PENDING' on every row and deposit is always 0. "
            "Neither is maintained — use paid_amount / open_balance instead.",
            "freight_shipments.csv carries two disagreeing paid signals: the is_paid flag "
            "and paid_amount from the ledger. Freight shipments only start 2025-03; "
            "earlier freight is not in this table.",
            "vendor_payments.csv is one row per ALLOCATION, not per payment. A wire split "
            "across POs or shipments appears as several rows.",
            "UNLINKED payment rows reduce no balance in any other file, so summing "
            "open_balance across files overstates debt by that amount.",
        ],
        "files": files,
    }
    write_json(os.path.join(out_dir, "export_meta.json"), meta)
    log("  export_meta.json           written")
    log(f"\nExported to {out_dir}")
    log(f"Inventory snapshot: {snapshot_date} | ads through: {ads_max} "
        f"| {bytes_billed / 1e6:.1f} MB billed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001 - top-level CLI guard
        print(f"export_finance_snapshot: FAILED — {exc}", file=sys.stderr)
        sys.exit(1)
