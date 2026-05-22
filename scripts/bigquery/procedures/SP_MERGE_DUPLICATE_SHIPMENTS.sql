-- SP_MERGE_DUPLICATE_SHIPMENTS: Post-processing step after SP_GENERATE_SHIPMENT_PLAN
-- If a SUGGESTED row shares the same product + ship_wednesday + shipment_type
-- as an APPROVED/SCHEDULED row, absorb its qty into the approved row and delete the duplicate.
-- Called by SP_ORCHESTRATE_DAILY_REFRESH after SP_GENERATE_SHIPMENT_PLAN.

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_MERGE_DUPLICATE_SHIPMENTS`()
BEGIN
  CREATE TEMP TABLE tmp_approved_keys AS
  SELECT product, ship_wednesday, shipment_type
  FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS`
  WHERE status IN ('APPROVED', 'SCHEDULED')
  GROUP BY product, ship_wednesday, shipment_type;

  CREATE TEMP TABLE tmp_merge_overlaps AS
  SELECT s.product, s.ship_wednesday, s.shipment_type,
    SUM(s.ship_qty) AS extra_qty, SUM(s.ship_cartons) AS extra_cartons
  FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` s
  JOIN tmp_approved_keys ak
    ON ak.product = s.product AND ak.ship_wednesday = s.ship_wednesday
    AND ak.shipment_type = s.shipment_type
  WHERE s.status = 'SUGGESTED'
  GROUP BY s.product, s.ship_wednesday, s.shipment_type;

  -- Absorb suggested qty into the approved row
  UPDATE `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` approved
  SET approved.ship_qty = approved.ship_qty + m.extra_qty,
      approved.ship_cartons = approved.ship_cartons + m.extra_cartons
  FROM tmp_merge_overlaps m
  WHERE approved.product = m.product
    AND approved.ship_wednesday = m.ship_wednesday
    AND approved.shipment_type = m.shipment_type
    AND approved.status IN ('APPROVED', 'SCHEDULED');

  -- Remove the merged SUGGESTED duplicates
  DELETE FROM `onyga-482313.OI.DE_SCHEDULED_SHIPMENTS` s
  WHERE s.status = 'SUGGESTED'
    AND CONCAT(s.product, '|', CAST(s.ship_wednesday AS STRING), '|', CAST(s.shipment_type AS STRING))
      IN (SELECT CONCAT(m.product, '|', CAST(m.ship_wednesday AS STRING), '|', CAST(m.shipment_type AS STRING)) FROM tmp_merge_overlaps m);

  DROP TABLE IF EXISTS tmp_approved_keys;
  DROP TABLE IF EXISTS tmp_merge_overlaps;
END;
