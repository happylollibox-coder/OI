-- SP_GENERATE_ALERTS: Core alert engine for shipment planning v2
-- Runs daily (or on-demand). Generates alerts based on DOC projections.
--
-- Consumes V_PLAN_FORECAST as single source of truth for:
--   effectiveGrowth, daily_rate, gap, DOC, inventory
--
-- Alert Types:
--   CREATE_PO        – Gap from Plan >= min_manuf_quantity
--   CREATE_SHIPMENT  – Goods at manufacturer AND fba_doc_effective < 45
--
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_GENERATE_ALERTS`()
BEGIN
  DECLARE FBA_MIN_DAYS INT64 DEFAULT 30;
  DECLARE FBA_MAX_DAYS INT64 DEFAULT 45;
  DECLARE EMERGENCY_DOC INT64 DEFAULT 15;

  -- ═══════════════════════════════════════════════
  -- 1. Read V_PLAN_FORECAST (single source of truth)
  -- ═══════════════════════════════════════════════
  CREATE TEMP TABLE tmp_data AS
  SELECT v.*,
         p.manufacturer,
         COALESCE(ch.cost_of_goods, 0.0) AS unit_cost,
         COALESCE(anp.approved_no_po_qty, 0) AS approved_no_po_qty
  FROM `onyga-482313.OI.V_PLAN_FORECAST` v
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON v.asin = p.asin
  LEFT JOIN (
    SELECT asin, cost_of_goods
    FROM (
      SELECT asin, cost_of_goods, ROW_NUMBER() OVER(PARTITION BY asin ORDER BY start_date DESC) as rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
    )
    WHERE rn = 1
  ) ch ON v.asin = ch.asin
  LEFT JOIN (
    SELECT asin, SUM(ship_qty) AS approved_no_po_qty
    FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS`
    WHERE status = 'APPROVED' AND needs_new_po = TRUE
    GROUP BY asin
  ) anp ON v.asin = anp.asin
  WHERE v.daily_rate > 0;

  -- ═══════════════════════════════════════════════
  -- 2. Build candidate alerts
  -- ═══════════════════════════════════════════════
  CREATE TEMP TABLE tmp_candidates AS

  -- ALERT: Create PO (gap >= min_manuf_quantity)
  SELECT GENERATE_UUID() id, 'CREATE_PO' atype, d.asin, d.product pn,
    CASE WHEN d.fba_doc_walk < EMERGENCY_DOC THEN 'CRITICAL'
         WHEN d.fba_doc_walk < FBA_MIN_DAYS THEN 'WARNING'
         ELSE 'INFO' END sev,
    CONCAT('Create PO: ', d.product, ' (', CAST(CAST(d.gap_from_plan AS INT64) AS STRING), ' gap)') ttl,
    CONCAT('Plan: ', CAST(d.yearly_plan AS STRING),
           '. Current Stock: ', CAST(d.available_stock AS STRING),
           ' (FBA: ', CAST(d.fba_stock AS STRING),
           ', AWD: ', CAST(d.awd_stock AS STRING),
           ', Transit: ', CAST(d.in_transit AS STRING), ')',
           '. Total Stock: ', CAST(d.total_stock AS STRING),
           '. Sold: ', CAST(d.ytd_sold AS STRING),
           CASE WHEN d.approved_no_po_qty > 0
             THEN CONCAT('. Approved w/o PO: ', CAST(d.approved_no_po_qty AS STRING))
             ELSE '' END) dsc,
    CAST(CEIL(GREATEST(d.gap_from_plan, d.min_manuf_quantity) / GREATEST(d.package_quantity, 1))
         * GREATEST(d.package_quantity, 1) AS INT64) sq,
    CAST(0 AS INT64) sfba, CAST(0 AS INT64) sawd,
    CAST(d.fba_doc_walk AS FLOAT64) fdoc, CAST(d.sellable_doc_walk AS FLOAT64) sdoc, CAST(NULL AS DATE) bd,
    'MODAL_CREATE_PO' AS action_type,
    JSON_OBJECT(
      'asin', d.asin,
      'product_name', d.product,
      'manufacturer', d.manufacturer,
      'unit_cost', d.unit_cost,
      'recommended_qty', CAST(CEIL(GREATEST(d.gap_from_plan, d.min_manuf_quantity) / GREATEST(d.package_quantity, 1)) * GREATEST(d.package_quantity, 1) AS INT64),
      'gap_from_plan', CAST(d.gap_from_plan AS INT64),
      'fba_stock', d.fba_stock,
      'awd_stock', d.awd_stock,
      'in_transit', d.in_transit,
      'at_manufacturer', d.at_manufacturer,
      'current_stock', d.available_stock,
      'total_stock', d.total_stock,
      'approved_no_po_qty', d.approved_no_po_qty
    ) AS action_payload
  FROM tmp_data d
  WHERE d.gap_from_plan > 0
    AND d.gap_from_plan >= COALESCE(d.min_manuf_quantity, 0)

  UNION ALL

  -- ALERT: Create Shipment (goods at Mfr, effective FBA DOC < Max)
  SELECT GENERATE_UUID(), 'CREATE_SHIPMENT', d.asin, d.product,
    CASE WHEN d.fba_doc_effective < EMERGENCY_DOC THEN 'CRITICAL' ELSE 'WARNING' END,
    CONCAT('Ship: ', d.product, ' (', CAST(d.ready_to_ship AS STRING), ' ready)'),
    CONCAT('FBA: ', CAST(d.fba_stock AS STRING), ' (DOC ', CAST(ROUND(d.fba_doc) AS STRING), 'd)',
           CASE WHEN d.in_transit > 0 THEN CONCAT('. In Transit: ', CAST(d.in_transit AS STRING)) ELSE '' END,
           '. AWD: ', CAST(d.awd_stock AS STRING),
           '. Mfr Ready: ', CAST(d.ready_to_ship AS STRING),
           '. In Prod: ', CAST(d.in_production AS STRING)),
    CAST(LEAST(d.ready_to_ship,
      CEIL(CASE WHEN d.is_awd_product THEN
          GREATEST(FBA_MAX_DAYS * d.daily_rate - d.fba_stock - d.in_transit, 0)
            + GREATEST(d.effective_lead_days * d.daily_rate - d.awd_stock, 0)
        ELSE
          GREATEST(FBA_MAX_DAYS * d.daily_rate - d.fba_stock - d.in_transit, 0)
            + d.shipment_days * d.daily_rate
      END / GREATEST(d.package_quantity, 1)) * GREATEST(d.package_quantity, 1)) AS INT64) sq,
    CAST(CEIL(GREATEST(FBA_MAX_DAYS * d.daily_rate - d.fba_stock - d.in_transit, 0)
         / GREATEST(d.package_quantity, 1)) * GREATEST(d.package_quantity, 1) AS INT64) sfba,
    CASE WHEN d.is_awd_product THEN
      CAST(CEIL(GREATEST(d.effective_lead_days * d.daily_rate - d.awd_stock, 0)
           / GREATEST(d.package_quantity, 1)) * GREATEST(d.package_quantity, 1) AS INT64) ELSE 0 END sawd,
    d.fba_doc fdoc, d.system_doc sdoc, CAST(NULL AS DATE) bd,
    'MODAL_CREATE_SHIPMENT' AS action_type,
    JSON_OBJECT(
      'asin', d.asin,
      'recommended_qty', CAST(LEAST(d.ready_to_ship,
        CEIL(CASE WHEN d.is_awd_product THEN
            GREATEST(FBA_MAX_DAYS * d.daily_rate - d.fba_stock - d.in_transit, 0)
              + GREATEST(d.effective_lead_days * d.daily_rate - d.awd_stock, 0)
          ELSE
            GREATEST(FBA_MAX_DAYS * d.daily_rate - d.fba_stock - d.in_transit, 0)
              + d.shipment_days * d.daily_rate
        END / GREATEST(d.package_quantity, 1)) * GREATEST(d.package_quantity, 1)) AS INT64),
      'recommended_fba_qty', CAST(CEIL(GREATEST(FBA_MAX_DAYS * d.daily_rate - d.fba_stock - d.in_transit, 0) / GREATEST(d.package_quantity, 1)) * GREATEST(d.package_quantity, 1) AS INT64),
      'recommended_awd_qty', CASE WHEN d.is_awd_product THEN CAST(CEIL(GREATEST(d.effective_lead_days * d.daily_rate - d.awd_stock, 0) / GREATEST(d.package_quantity, 1)) * GREATEST(d.package_quantity, 1) AS INT64) ELSE 0 END,
      'at_manufacturer', CAST(d.ready_to_ship AS INT64)
    ) AS action_payload
  FROM tmp_data d
  WHERE d.ready_to_ship > 0 AND d.fba_doc_effective < FBA_MAX_DAYS

  UNION ALL

  -- ALERT: AWD Target Deviation (Diff > 10%)
  SELECT GENERATE_UUID(), 'UPDATE_AWD_TARGET', s.asin, s.product_short_name,
    CASE 
      WHEN s.awd_diff_pct > 30 THEN 'CRITICAL'
      WHEN s.awd_diff_pct > 20 THEN 'HIGH'
      ELSE 'WARNING'
    END sev,
    CONCAT('Update AWD: ', s.product_short_name) ttl,
    CONCAT(
      'Min: ', 
      CASE 
        WHEN COALESCE(s.awd_approved_min, -1) != s.awd_target_min 
        THEN CONCAT(COALESCE(CAST(s.awd_approved_min AS STRING), 'None'), ' → ', CAST(s.awd_target_min AS STRING))
        ELSE CAST(s.awd_target_min AS STRING)
      END,
      ', Max: ',
      CASE 
        WHEN COALESCE(s.awd_approved_max, -1) != s.awd_target_max 
        THEN CONCAT(COALESCE(CAST(s.awd_approved_max AS STRING), 'None'), ' → ', CAST(s.awd_target_max AS STRING))
        ELSE CAST(s.awd_target_max AS STRING)
      END,
      ' (Diff: ', CAST(ROUND(s.awd_diff_pct) AS STRING), '%)'
    ) dsc,
    CAST(s.awd_target_max AS INT64) sq,
    CAST(0 AS INT64) sfba, CAST(0 AS INT64) sawd,
    CAST(NULL AS FLOAT64) fdoc, CAST(NULL AS FLOAT64) sdoc, CAST(NULL AS DATE) bd,
    'MODAL_AWD_TARGET' AS action_type,
    JSON_OBJECT(
      'asin', s.asin,
      'recommended_awd_target_min', CAST(s.awd_target_min AS INT64),
      'recommended_awd_target_max', CAST(s.awd_target_max AS INT64),
      'current_approved_min', CAST(s.awd_approved_min AS INT64),
      'current_approved_max', CAST(s.awd_approved_max AS INT64)
    ) AS action_payload
  FROM `onyga-482313.OI.V_SUPPLY_CHAIN_SUMMARY` s
  WHERE s.awd_diff_pct > 10

  UNION ALL

  -- ALERT: Plan Drift (Deviation > 15% between remaining_plan and unconstrained_remaining_forecast)
  SELECT GENERATE_UUID(), 'PLAN_DRIFT', d.asin, d.product,
    CASE 
      WHEN ABS(d.unconstrained_remaining_forecast - GREATEST(0, d.yearly_plan - d.ytd_sold)) / NULLIF(GREATEST(0, d.yearly_plan - d.ytd_sold), 0) > 0.30 THEN 'CRITICAL'
      ELSE 'WARNING'
    END sev,
    CONCAT('Plan Drift: ', d.product) ttl,
    CONCAT('Remaining Plan: ', CAST(GREATEST(0, d.yearly_plan - d.ytd_sold) AS STRING),
           '. Unconstrained Forecast: ', CAST(d.unconstrained_remaining_forecast AS STRING),
           '. Diff: ', CAST(ROUND(ABS(d.unconstrained_remaining_forecast - GREATEST(0, d.yearly_plan - d.ytd_sold)) * 100.0 / NULLIF(GREATEST(0, d.yearly_plan - d.ytd_sold), 0)) AS STRING), '%') dsc,
    CAST(0 AS INT64) sq,
    CAST(0 AS INT64) sfba, CAST(0 AS INT64) sawd,
    CAST(NULL AS FLOAT64) fdoc, CAST(NULL AS FLOAT64) sdoc, CAST(NULL AS DATE) bd,
    'MODAL_UPDATE_PLAN' AS action_type,
    JSON_OBJECT(
      'asin', d.asin,
      'yearly_plan', CAST(d.yearly_plan AS INT64),
      'ytd_sold', CAST(d.ytd_sold AS INT64),
      'remaining_plan', CAST(GREATEST(0, d.yearly_plan - d.ytd_sold) AS INT64),
      'unconstrained_forecast', CAST(d.unconstrained_remaining_forecast AS INT64),
      'recommended_plan', CAST(d.ytd_sold + d.unconstrained_remaining_forecast AS INT64)
    ) AS action_payload
  FROM tmp_data d
  WHERE d.yearly_plan > 0 
    AND GREATEST(0, d.yearly_plan - d.ytd_sold) > 0
    AND ABS(d.unconstrained_remaining_forecast - GREATEST(0, d.yearly_plan - d.ytd_sold)) / GREATEST(0, d.yearly_plan - d.ytd_sold) > 0.15;

  -- ═══════════════════════════════════════════════
  -- 3. Upsert into DE_ALERTS (Self-Healing)
  -- ═══════════════════════════════════════════════
  MERGE `onyga-482313.OI.DE_ALERTS` t
  USING tmp_candidates s
  ON t.alert_type = s.atype AND t.product_asin = s.asin AND t.status IN ('OPEN', 'SNOOZED')
  WHEN MATCHED THEN
    UPDATE SET
      t.severity = s.sev,
      t.title = s.ttl,
      t.description = s.dsc,
      t.suggested_qty = s.sq,
      t.suggested_split_fba = s.sfba,
      t.suggested_split_awd = s.sawd,
      t.fba_doc = s.fdoc,
      t.system_doc = s.sdoc,
      t.breach_date = s.bd,
      t.action_type = s.action_type,
      t.action_payload = s.action_payload,
      t.updated_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN
    INSERT (id, alert_type, product_asin, product_name, severity, title, description,
            suggested_qty, suggested_split_fba, suggested_split_awd, fba_doc, system_doc, breach_date,
            status, created_at, action_type, action_payload, updated_at)
    VALUES (s.id, s.atype, s.asin, s.pn, s.sev, s.ttl, s.dsc,
            s.sq, s.sfba, s.sawd, s.fdoc, s.sdoc, s.bd,
            'OPEN', CURRENT_TIMESTAMP(), s.action_type, s.action_payload, CURRENT_TIMESTAMP());

  -- ═══════════════════════════════════════════════
  -- 4. Auto-Resolve stale alerts
  -- ═══════════════════════════════════════════════
  UPDATE `onyga-482313.OI.DE_ALERTS` t
  SET 
    status = 'AUTO_RESOLVED', 
    updated_at = CURRENT_TIMESTAMP(), 
    notes = CONCAT('Auto-resolved on ', CAST(CURRENT_DATE() AS STRING), ': condition no longer met')
  WHERE status = 'OPEN'
    AND alert_type IN ('CREATE_PO', 'CREATE_SHIPMENT', 'UPDATE_AWD_TARGET', 'PLAN_DRIFT')
    AND NOT EXISTS (
      SELECT 1 FROM tmp_candidates s 
      WHERE s.atype = t.alert_type AND s.asin = t.product_asin
    );

  -- ═══════════════════════════════════════════════
  -- 5. Cleanup
  -- ═══════════════════════════════════════════════
  DROP TABLE IF EXISTS tmp_data;
  DROP TABLE IF EXISTS tmp_candidates;
END;
