-- SP_REFRESH_PROBE_LOG — close the probe loop (15 clicks / 14 days). Coacher C.
-- Run daily AFTER the coach refresh. Idempotent.
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REFRESH_PROBE_LOG`()
BEGIN
  -- 1. start probes newly recommended this run (dedup to one row per keyword_id)
  INSERT INTO `onyga-482313.OI.DE_PROBE_LOG`
    (keyword_id, parent_name, season, match_type, intent_class, probe_launch_cpc,
     probe_started_at, clicks_accumulated, status, decided_at, updated_at)
  SELECT c.keyword_id,
         ANY_VALUE(c.parent_name), ANY_VALUE(c.season), ANY_VALUE(c.match_type),
         ANY_VALUE(c.intent_class), ANY_VALUE(c.recommended_bid),
         CURRENT_DATE('America/Los_Angeles'), 0, 'ACTIVE', NULL, CURRENT_TIMESTAMP()
  FROM `onyga-482313.OI.V_ADS_COACH` c
  WHERE c.target_action = 'PROBE' AND c.keyword_id IS NOT NULL
    AND c.keyword_id NOT IN (
      SELECT keyword_id FROM `onyga-482313.OI.DE_PROBE_LOG`
      WHERE status = 'ACTIVE' AND keyword_id IS NOT NULL)
  GROUP BY c.keyword_id;

  -- 2. refresh accumulated clicks since probe start (from the keyword report)
  UPDATE `onyga-482313.OI.DE_PROBE_LOG` l
  SET clicks_accumulated = (
        SELECT COALESCE(SUM(kd.clicks), 0) FROM `onyga-482313.OI.V_KEYWORD_DAILY` kd
        WHERE CAST(kd.keyword_id AS STRING) = l.keyword_id AND kd.date >= l.probe_started_at),
      updated_at = CURRENT_TIMESTAMP()
  WHERE l.status = 'ACTIVE';

  -- 3. graduate at the click budget (15), 4. exhaust at the day budget (14)
  UPDATE `onyga-482313.OI.DE_PROBE_LOG` l
  SET status = CASE
        WHEN l.clicks_accumulated >= 15 THEN 'GRADUATED'
        WHEN DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), l.probe_started_at, DAY) >= 14 THEN 'EXHAUSTED'
        ELSE 'ACTIVE' END,
      decided_at = CASE
        WHEN l.clicks_accumulated >= 15
          OR DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), l.probe_started_at, DAY) >= 14
        THEN CURRENT_DATE('America/Los_Angeles') ELSE NULL END,
      updated_at = CURRENT_TIMESTAMP()
  WHERE l.status = 'ACTIVE';
END;
