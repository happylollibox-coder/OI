-- =============================================
-- SP_SYNC_NEGATIVES — keep the owned negative registries current from our uploads
-- =============================================
--
-- The warehouse is the single authority on negatives (Fivetran's negative sync is
-- frozen). This procedure folds every negative we push through the DO page —
-- recorded in FACT_PPC_CHANGE_LOG — into:
--   • DE_NEGATIVE_KEYWORDS  (keyword negatives: NEGATE_* / STOP_TERM)
--   • DE_NEGATIVE_TARGETS   (product-target negatives: NEGATE_* on asin=… targets)
-- and flips removed negatives (REMOVE_NEGATIVE) to state='REMOVED'.
--
-- Idempotent: MERGE on the natural key, so it can run after every upload (or scheduled).
-- Called automatically by the Flask change-log insert endpoint (api_ppc_change_log_insert).
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SYNC_NEGATIVES`()
BEGIN
  DECLARE now_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  -- ── A. Keyword negatives we uploaded → upsert ENABLED into DE_NEGATIVE_KEYWORDS ──
  MERGE `onyga-482313.OI.DE_NEGATIVE_KEYWORDS` T
  USING (
    SELECT
      campaign_id,
      ANY_VALUE(campaign_name) AS campaign_name,
      NULLIF(ad_group_id, '')  AS ad_group_id,
      kw_text, match_type, lvl,
      ANY_VALUE(src) AS source,
      MAX(change_id) AS change_id,
      MIN(applied_at) AS added_at
    FROM (
      SELECT
        campaign_id, campaign_name, ad_group_id, applied_at, change_id, source AS src,
        COALESCE(NULLIF(TRIM(search_term), ''), targeting) AS kw_text,
        IF(action LIKE '%PHRASE%', 'NEGATIVE_PHRASE', 'NEGATIVE_EXACT') AS match_type,
        IF(COALESCE(NULLIF(TRIM(ad_group_id), ''), '') = '', 'CAMPAIGN', 'AD_GROUP') AS lvl
      FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
      WHERE (action LIKE 'NEGATE%' OR action = 'STOP_TERM')
        AND COALESCE(match_type, '') != 'PRODUCT_TARGETING'
        AND LOWER(COALESCE(targeting, '')) NOT LIKE 'asin=%'
        AND COALESCE(NULLIF(TRIM(search_term), ''), targeting) IS NOT NULL
    )
    GROUP BY campaign_id, ad_group_id, kw_text, match_type, lvl
  ) S
  ON  T.campaign_id = S.campaign_id
  AND COALESCE(T.ad_group_id, '') = COALESCE(S.ad_group_id, '')
  AND LOWER(T.keyword_text) = LOWER(S.kw_text)
  AND T.match_type = S.match_type
  WHEN MATCHED AND T.state = 'REMOVED' THEN
    UPDATE SET state = 'ENABLED', removed_at = NULL, change_id = S.change_id, updated_at = now_ts
  WHEN NOT MATCHED THEN
    INSERT (negative_id, campaign_id, campaign_name, ad_group_id, keyword_text, match_type, level, state, source, added_at, change_id, updated_at)
    VALUES (CONCAT('neg_', SUBSTR(TO_HEX(MD5(CONCAT(S.campaign_id, '|', COALESCE(S.ad_group_id, ''), '|', LOWER(S.kw_text), '|', S.match_type))), 1, 12)),
            S.campaign_id, S.campaign_name, S.ad_group_id, S.kw_text, S.match_type, S.lvl, 'ENABLED', COALESCE(S.source, 'COACH'), S.added_at, S.change_id, now_ts);

  -- ── B. Product-target negatives we uploaded → upsert into DE_NEGATIVE_TARGETS ──
  MERGE `onyga-482313.OI.DE_NEGATIVE_TARGETS` T
  USING (
    SELECT
      campaign_id,
      ANY_VALUE(campaign_name) AS campaign_name,
      NULLIF(ad_group_id, '')  AS ad_group_id,
      expr, lvl,
      ANY_VALUE(src) AS source,
      MAX(change_id) AS change_id,
      MIN(applied_at) AS added_at
    FROM (
      SELECT campaign_id, campaign_name, ad_group_id, applied_at, change_id, source AS src,
        COALESCE(targeting, search_term) AS expr,
        IF(COALESCE(NULLIF(TRIM(ad_group_id), ''), '') = '', 'CAMPAIGN', 'AD_GROUP') AS lvl
      FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
      WHERE action LIKE 'NEGATE%'
        AND (COALESCE(match_type, '') = 'PRODUCT_TARGETING' OR LOWER(COALESCE(targeting, '')) LIKE 'asin=%')
        AND COALESCE(targeting, search_term) IS NOT NULL
    )
    GROUP BY campaign_id, ad_group_id, expr, lvl
  ) S
  ON  T.campaign_id = S.campaign_id
  AND COALESCE(T.ad_group_id, '') = COALESCE(S.ad_group_id, '')
  AND LOWER(T.targeting_expression) = LOWER(S.expr)
  WHEN MATCHED AND T.state = 'REMOVED' THEN
    UPDATE SET state = 'ENABLED', removed_at = NULL, change_id = S.change_id, updated_at = now_ts
  WHEN NOT MATCHED THEN
    INSERT (negative_id, campaign_id, campaign_name, ad_group_id, targeting_expression, level, state, source, added_at, change_id, updated_at)
    VALUES (CONCAT('negt_', SUBSTR(TO_HEX(MD5(CONCAT(S.campaign_id, '|', COALESCE(S.ad_group_id, ''), '|', LOWER(S.expr)))), 1, 12)),
            S.campaign_id, S.campaign_name, S.ad_group_id, S.expr, S.lvl, 'ENABLED', COALESCE(S.source, 'COACH'), S.added_at, S.change_id, now_ts);

  -- ── C. Removals we uploaded (REMOVE_NEGATIVE) → flip ENABLED keyword negatives to REMOVED ──
  UPDATE `onyga-482313.OI.DE_NEGATIVE_KEYWORDS` T
  SET state = 'REMOVED', removed_at = now_ts, updated_at = now_ts
  WHERE T.state = 'ENABLED' AND EXISTS (
    SELECT 1 FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` c
    WHERE c.action IN ('REMOVE_NEGATIVE', 'REMOVE_CONFLICTING_NEGATIVE')
      AND c.campaign_id = T.campaign_id
      AND LOWER(COALESCE(NULLIF(TRIM(c.search_term), ''), c.targeting)) = LOWER(T.keyword_text)
  );
END;
