CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_BUILD_CUSTOMER_PURCHASE_FLOWS`()
OPTIONS (description = "Grows the customer purchase flow tree on the CUSTOMER's dimensions (THREE_LAYERS.md §2.0.3/§2.0.4/§2.0.5). A member is a (subject x season) CELL, not a keyword — the same keyword converts at 4.55% in November and 3.44% in August, so time is a property of the observation and not of the subject. TIME AND FAMILY ARE FORCED levels, exempt from the improvement threshold: a tree that pools across seasons or products is answering a different question from the one it was asked (§2.0.4). INTENT and ADS TYPE are then earned greedily. PLACEMENT IS NEVER A LEVEL — a keyword does not belong to a placement, it is served across a mix — so it is carried as a modifier instead (§2.0.5). THE SPLIT IS SCORED ON NET PROFIT PER CLICK, not on CVR: the first version scored CVR alone and therefore split on the dimension that separates conversion while pooling across the one that separates economics, and net profit is clicks x CVR x GP-per-order - cost, so the pooled link multiplied straight into the answer. Writes T_CUSTOMER_PURCHASE_FLOW and T_SUBJECT_FLOW_NODE. Decides nothing.")
BEGIN
  DECLARE pass INT64 DEFAULT 0;
  DECLARE split_count INT64 DEFAULT 1;
  DECLARE max_depth        INT64   DEFAULT 15;
  DECLARE min_node_members INT64   DEFAULT 3;
  DECLARE min_node_clicks  INT64   DEFAULT 200;
  DECLARE min_improvement  FLOAT64 DEFAULT 0.05;

  -- A MEMBER IS A (SUBJECT x SEASON) CELL. Time is a property of the observation, so it cannot be a
  -- column on the subject — it has to be in the grain, or the same keyword's December and August
  -- behaviour are averaged into one number that describes neither.
  CREATE OR REPLACE TEMP TABLE mem AS
  WITH wm AS (SELECT MAX(date) w FROM `onyga-482313.OI.FACT_AMAZON_ADS`)
  SELECT
    s.campaign_id, s.keyword_id, s.target_text, s.family, s.intent, s.ads_type,
    s.top_of_search_share,
    CASE WHEN EXTRACT(MONTH FROM a.date) IN (11,12) THEN 'HOLIDAY'
         WHEN EXTRACT(MONTH FROM a.date) IN (8,9)   THEN 'BACK_TO_SCHOOL'
         WHEN EXTRACT(MONTH FROM a.date) IN (1,2)   THEN 'POST_HOLIDAY'
         ELSE                                            'OFF_SEASON' END AS season,
    SUM(a.Ads_clicks) AS clicks, SUM(a.Ads_orders) AS orders,
    SUM(a.Ads_cost) AS cost, SUM(a.GROSS_PROFIT) AS gp,
    COUNT(DISTINCT a.date) AS days_with_clicks,
    SAFE_DIVIDE(SUM(a.Ads_orders), NULLIF(SUM(a.Ads_clicks),0)) AS cvr,
    -- THE QUANTITY THE TREE IS ACTUALLY FOR. Splitting to minimise the scatter of NET PROFIT PER
    -- CLICK optimises the target directly, instead of optimising one link and hoping.
    SAFE_DIVIDE(SUM(a.GROSS_PROFIT) - SUM(a.Ads_cost), NULLIF(SUM(a.Ads_clicks),0)) AS npc
  FROM `onyga-482313.OI.T_SUBJECT_FLOW` s
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON CAST(a.campaign_id AS STRING) = s.campaign_id
   AND LOWER(TRIM(a.targeting)) = s.target_text
  CROSS JOIN wm
  WHERE a.date BETWEEN DATE_SUB(wm.w, INTERVAL 364 DAY) AND wm.w
  GROUP BY 1,2,3,4,5,6,7,8
  HAVING SUM(a.Ads_clicks) >= 20;

  -- FORCED LEVELS FIRST (§2.0.4): season, then family. Not scored, not optional.
  CREATE OR REPLACE TEMP TABLE assign AS
  SELECT campaign_id, keyword_id, season,
         CONCAT('ROOT/season=', season, '/family=', family) AS node_id,
         2 AS depth, '<season><family>' AS used_dims
  FROM mem;

  CREATE OR REPLACE TEMP TABLE nodes AS
  SELECT DISTINCT node_id, 'ROOT' AS parent_id, 2 AS depth,
         'family' AS split_dim, CAST(NULL AS STRING) AS split_value, TRUE AS is_leaf
  FROM assign
  UNION ALL SELECT 'ROOT', CAST(NULL AS STRING), 0, CAST(NULL AS STRING), CAST(NULL AS STRING), FALSE;

  WHILE split_count > 0 AND pass < max_depth DO
    SET pass = pass + 1;

    CREATE OR REPLACE TEMP TABLE cand AS
    WITH long AS (
      SELECT a.node_id, a.used_dims, m.clicks, m.npc, d.dim, d.val
      FROM assign a JOIN mem m USING (campaign_id, keyword_id, season),
      UNNEST([STRUCT('intent' AS dim, m.intent AS val), ('ads_type', m.ads_type)]) d
      WHERE d.val IS NOT NULL
        AND STRPOS(IFNULL(a.used_dims,''), CONCAT('<', d.dim, '>')) = 0
    ),
    node_now AS (
      SELECT a.node_id, SUM(m.clicks) clicks, COUNT(*) members,
             SAFE_DIVIDE(STDDEV(m.npc), NULLIF(ABS(AVG(m.npc)),0)) disp
      FROM assign a JOIN mem m USING (campaign_id, keyword_id, season) GROUP BY 1),
    child AS (
      SELECT node_id, dim, val, SUM(clicks) clicks, COUNT(*) members,
             SAFE_DIVIDE(STDDEV(npc), NULLIF(ABS(AVG(npc)),0)) disp
      FROM long GROUP BY 1,2,3),
    scored AS (
      SELECT node_id, dim, COUNT(*) children,
             MIN(members) smallest_child_members, MIN(clicks) smallest_child_clicks,
             SAFE_DIVIDE(SUM(clicks*disp), NULLIF(SUM(clicks),0)) child_disp
      FROM child WHERE disp IS NOT NULL GROUP BY 1,2)
    SELECT s.*, n.disp node_disp, n.clicks node_clicks, n.members node_members,
           n.disp - s.child_disp AS improvement
    FROM scored s JOIN node_now n USING (node_id);

    CREATE OR REPLACE TEMP TABLE winner AS
    SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY node_id ORDER BY improvement DESC) rn
                   FROM cand
                   WHERE children >= 2 AND improvement >= min_improvement
                     AND smallest_child_members >= min_node_members
                     AND smallest_child_clicks >= min_node_clicks
                     AND node_members >= min_node_members * 2) WHERE rn = 1;
    SET split_count = (SELECT COUNT(*) FROM winner);

    IF split_count > 0 THEN
      CREATE OR REPLACE TEMP TABLE assign_next AS
      SELECT a.campaign_id, a.keyword_id, a.season,
             IF(w.node_id IS NULL, a.node_id,
                CONCAT(a.node_id, '/', w.dim, '=',
                       CASE w.dim WHEN 'intent' THEN m.intent WHEN 'ads_type' THEN m.ads_type END)) AS node_id,
             IF(w.node_id IS NULL, a.depth, a.depth + 1) AS depth,
             IF(w.node_id IS NULL, a.used_dims, CONCAT(a.used_dims, '<', w.dim, '>')) AS used_dims
      FROM assign a JOIN mem m USING (campaign_id, keyword_id, season)
      LEFT JOIN winner w ON w.node_id = a.node_id;
      CREATE OR REPLACE TEMP TABLE assign AS SELECT * FROM assign_next;

      INSERT INTO nodes
      SELECT DISTINCT a.node_id, w.node_id, a.depth, w.dim,
             REGEXP_EXTRACT(a.node_id, r'=([^/]*)$'), TRUE
      FROM assign a JOIN winner w ON STARTS_WITH(a.node_id, CONCAT(w.node_id, '/', w.dim, '='))
      WHERE NOT EXISTS (SELECT 1 FROM nodes n WHERE n.node_id = a.node_id);
      UPDATE nodes SET is_leaf = FALSE WHERE node_id IN (SELECT node_id FROM winner);
    END IF;
  END WHILE;

  CREATE OR REPLACE TABLE `onyga-482313.OI.T_SUBJECT_FLOW_NODE`
  OPTIONS (description = "Which grown flow node each (subject x season) cell sits in (§2.0.3/§2.0.4). A member is a cell rather than a keyword because time is a property of the observation. Rebuilt by SP_BUILD_CUSTOMER_PURCHASE_FLOWS.")
  AS SELECT a.campaign_id, a.keyword_id, a.season, m.target_text, m.family,
            a.node_id, a.depth, a.used_dims, CURRENT_TIMESTAMP() AS built_at
     FROM assign a JOIN mem m USING (campaign_id, keyword_id, season);

  CREATE OR REPLACE TABLE `onyga-482313.OI.T_CUSTOMER_PURCHASE_FLOW`
  OPTIONS (description = "The grown customer purchase flow tree on the customer's dimensions (§2.0.3/§2.0.4/§2.0.5). Time and family are FORCED levels; intent and ads type are earned greedily; placement is carried as a modifier (top_of_search_share) and never as a level. Split scored on NET PROFIT PER CLICK, the quantity the tree exists to predict, rather than on CVR alone. Every node's profile rolls up its descendants so a shallower node is a real fallback. Profile split BY LINK because the purpose is to see WHICH link is wrong.")
  AS
  SELECT n.node_id, n.parent_id, n.depth, n.split_dim, n.split_value, n.is_leaf,
         COUNT(*) AS members,
         SUM(m.clicks) clicks, SUM(m.orders) orders, ROUND(SUM(m.cost),2) cost,
         ROUND(SAFE_DIVIDE(SUM(m.cost),   NULLIF(SUM(m.clicks),0)),4) flow_cpc,
         ROUND(SAFE_DIVIDE(SUM(m.orders), NULLIF(SUM(m.clicks),0)),5) flow_cvr,
         ROUND(SAFE_DIVIDE(SUM(m.gp),     NULLIF(SUM(m.orders),0)),4) flow_gp_per_order,
         ROUND(SAFE_DIVIDE(SUM(m.gp)-SUM(m.cost), NULLIF(SUM(m.clicks),0)),5) flow_net_profit_per_click,
         ROUND(AVG(m.top_of_search_share),4) flow_top_of_search_share,
         ROUND(SAFE_DIVIDE(STDDEV(m.npc), NULLIF(ABS(AVG(m.npc)),0)),3) npc_dispersion,
         CURRENT_TIMESTAMP() built_at
  FROM nodes n
  JOIN `onyga-482313.OI.T_SUBJECT_FLOW_NODE` t
    ON t.node_id = n.node_id OR STARTS_WITH(t.node_id, CONCAT(n.node_id, '/'))
  JOIN mem m ON m.campaign_id=t.campaign_id AND m.keyword_id=t.keyword_id AND m.season=t.season
  GROUP BY 1,2,3,4,5,6;
END;
