-- =============================================
-- Migration 2026-08-15 — FACT_INVENTORY_SNAPSHOT.LANDED_COGS_AMOUNT
-- =============================================
--
-- WHY
--   COGS_AMOUNT values stock at DIM_COSTS_HISTORY.TOTAL_COST_PER_UNIT, which is
--     cost_of_goods + shipping_cost + FBA_COST_estimated_fee_total
--   i.e. it includes Amazon pick&pack + referral fees. Those are incurred only
--   when a unit SELLS, so COGS_AMOUNT is the right cost for unit profitability
--   and the wrong one for valuing unsold stock — it overstates the asset by
--   ~2.1-2.25x (2025-12-31: $434,142 loaded vs $204,651 landed).
--
--   LANDED_COGS_AMOUNT adds the balance-sheet figure alongside it. ADDITIVE —
--   COGS_AMOUNT keeps its current meaning and every existing consumer is
--   untouched. Approved by Ori 2026-08-15.
--
-- SAFETY
--   ALTER TABLE ADD COLUMN + targeted UPDATE only. Never CREATE OR REPLACE this
--   table: the live schema already carries PAID_AMOUNT, which the repo DDL did
--   not have until this migration — replacing from DDL would have dropped it.
--   The UPDATE only writes the new column; no existing column is read-modified.
--
-- Spec: architecture/FINANCE_SNAPSHOT_EXPORT.md
-- =============================================

-- 1. Add the column (idempotent).
ALTER TABLE `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
  ADD COLUMN IF NOT EXISTS LANDED_COGS_AMOUNT FLOAT64
  OPTIONS (description =
    'Landed inventory value = quantity_balance * (cost_of_goods + shipping_cost). '
    'Manufacturing + freight only, EXCLUDING Amazon pick&pack and referral fees. '
    'Use this for asset / balance-sheet value; use COGS_AMOUNT for unit profitability.');

-- 2. Backfill every existing row from columns already present on the row.
--    NULL cost columns yield 0 — verified 2026-08-15 that every ASIN with no
--    DIM_COSTS_HISTORY row holds zero units, so this loses no value.
UPDATE `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
SET LANDED_COGS_AMOUNT =
      quantity_balance * (IFNULL(cost_of_goods, 0) + IFNULL(shipping_cost, 0))
WHERE TRUE;
