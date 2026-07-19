-- V_FAMILY_BUDGET_ALLOCATION — total daily budget → per-family daily budget.
-- floor + winners-take-the-rest: every family keeps family_floor_daily; the remaining pot splits by
-- V_FAMILY_NET_PROFIT_7D.weight (daily-avg net profit over 7 full days). If no family has positive
-- weight, the pot splits equally (no divide-by-zero → all-floor collapse). A DE_PRODUCT_BUDGET row
-- with source='MANUAL_DAILY' (a DAILY number written by the Step-1 UI) overrides a family's split —
-- distinct from legacy WEEKLY 'MANUAL' rows the weekly-plan tool uses, so the two never clash.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_BUDGET_ALLOCATION` AS
WITH cfg AS (
  SELECT
    MAX(IF(config_key='total_daily_budget', config_value, NULL)) AS total,
    MAX(IF(config_key='family_floor_daily', config_value, NULL)) AS floor
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
w AS (SELECT parent_name, weight FROM `onyga-482313.OI.V_FAMILY_NET_PROFIT_7D`),
agg AS (
  SELECT COUNT(*) n_fam, SUM(weight) tot_w,
    (SELECT total FROM cfg) total, (SELECT floor FROM cfg) floor
  FROM w
),
alloc AS (
  SELECT w.parent_name, a.floor,
    a.floor + (a.total - a.floor * a.n_fam) *
      CASE WHEN a.tot_w > 0 THEN SAFE_DIVIDE(w.weight, a.tot_w) ELSE 1.0 / a.n_fam END
      AS waterfall_daily
  FROM w CROSS JOIN agg a
),
manual AS (
  SELECT parent_name, weekly_budget AS manual_daily
  FROM `onyga-482313.OI.DE_PRODUCT_BUDGET`
  WHERE source = 'MANUAL_DAILY'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY parent_name ORDER BY week_start DESC) = 1
)
SELECT
  al.parent_name,
  ROUND(al.floor, 2) AS floor,
  ROUND(COALESCE(m.manual_daily, al.waterfall_daily), 2) AS allocated_daily,
  IF(m.manual_daily IS NOT NULL, 'MANUAL_DAILY', 'WATERFALL') AS source
FROM alloc al LEFT JOIN manual m ON m.parent_name = al.parent_name;
