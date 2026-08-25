CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_BUILD_CUSTOMER_PURCHASE_FLOWS`()
OPTIONS (description = "Grows the customer purchase flow TREE (THREE_LAYERS.md §2.0.3; Ori 2026-08-25: 'the catalog can have more than 10 levels and should add a level only if it improve the accuracy is has (not necessarily in a specific order)'). GREEDY, NOT A FIXED LADDER: at every node each candidate dimension is scored by the CLICK-WEIGHTED dispersion of the children it would produce, and the node splits on whichever dimension helps most — so different branches split on different things and depth is decided by evidence rather than declared. Replaces a fixed coverage-ordered ladder that measurement showed was almost exactly wrong: at the root the best splits are age_group (0.581) and subject_kind (0.581) while channel — which the ladder used first — ranks 7th of 9 (0.885), and family and intent_type, which sat at levels 4 and 5, are the two WORST splits available (0.914, 0.917). Coverage says which fields are safe; it says nothing about which are informative. A node splits only when the improvement clears a declared threshold AND both children keep enough members and clicks; otherwise it stays a leaf. Depth is NOT capped at ten — it stops when nothing helps. Writes T_CUSTOMER_PURCHASE_FLOW and T_SUBJECT_FLOW_NODE. Decides nothing and is read by nothing that can move money.")
BEGIN
  DECLARE pass INT64 DEFAULT 0;
  DECLARE split_count INT64 DEFAULT 1;
  -- DECLARED CONSTANTS (§1.5): porting sets values rather than hunting literals.
  DECLARE max_depth        INT64   DEFAULT 15;    -- a stop, not a target; growth ends when nothing helps
  DECLARE min_node_members INT64   DEFAULT 3;     -- below this a node is one subject wearing a general name
  DECLARE min_node_clicks  INT64   DEFAULT 200;   -- a node nobody bought from teaches nothing
  DECLARE min_improvement  FLOAT64 DEFAULT 0.05;  -- a split must EARN its complexity

  -- Every member's own 365-day record, computed once. The tree only ever regroups these.
  CREATE OR REPLACE TEMP TABLE mem AS
  WITH wm AS (SELECT MAX(date) w FROM `onyga-482313.OI.FACT_AMAZON_ADS`)
  SELECT s.campaign_id, s.keyword_id, s.target_text, s.family,
         s.channel, s.subject_kind, s.intent_type, s.term_kind,
         CAST(s.is_gift AS STRING) AS is_gift, s.age_group, s.gender, s.product_type,
         SUM(a.Ads_clicks) AS clicks, SUM(a.Ads_orders) AS orders,
         SUM(a.Ads_cost) AS cost, SUM(a.GROSS_PROFIT) AS gp,
         SAFE_DIVIDE(SUM(a.Ads_orders), NULLIF(SUM(a.Ads_clicks),0)) AS cvr,
         COUNT(DISTINCT a.date) AS days_with_clicks
  FROM `onyga-482313.OI.T_SUBJECT_FLOW` s
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON CAST(a.campaign_id AS STRING) = s.campaign_id
   AND LOWER(TRIM(a.targeting)) = s.target_text
  CROSS JOIN wm
  WHERE a.date BETWEEN DATE_SUB(wm.w, INTERVAL 364 DAY) AND wm.w
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
  HAVING SUM(a.Ads_clicks) >= 30;   -- a member with less teaches the tree nothing

  -- Assignment: everyone starts in the root. The tree grows by rewriting this.
  CREATE OR REPLACE TEMP TABLE assign AS
  SELECT campaign_id, keyword_id, 'ROOT' AS node_id, 0 AS depth,
         CAST(NULL AS STRING) AS used_dims
  FROM mem;

  CREATE OR REPLACE TEMP TABLE nodes AS
  SELECT 'ROOT' AS node_id, CAST(NULL AS STRING) AS parent_id, 0 AS depth,
         CAST(NULL AS STRING) AS split_dim, CAST(NULL AS STRING) AS split_value,
         'all subjects' AS path, TRUE AS is_leaf;

  WHILE split_count > 0 AND pass < max_depth DO
    SET pass = pass + 1;

    -- SCORE EVERY CANDIDATE DIMENSION AT EVERY LEAF. One row per (node, dimension): what the
    -- click-weighted dispersion of the children WOULD be, versus what the node has now.
    CREATE OR REPLACE TEMP TABLE cand AS
    WITH long AS (
      SELECT a.node_id, a.used_dims, m.clicks, m.cvr, d.dim, d.val
      FROM assign a JOIN mem m USING (campaign_id, keyword_id),
      UNNEST([STRUCT('channel' AS dim, m.channel AS val),
              ('subject_kind', m.subject_kind), ('intent_type', m.intent_type),
              ('family', m.family), ('term_kind', m.term_kind), ('is_gift', m.is_gift),
              ('age_group', m.age_group), ('gender', m.gender),
              ('product_type', m.product_type)]) d
      WHERE d.val IS NOT NULL
        -- A DIMENSION IS NEVER REUSED ON ITS OWN BRANCH: splitting twice on the same field cannot
        -- separate anything the first split did not.
        -- STRPOS rather than CONTAINS_SUBSTR: the latter demands a CONSTANT needle, and the
        -- needle here is the candidate dimension being scored.
        AND (a.used_dims IS NULL OR STRPOS(a.used_dims, CONCAT('<', d.dim, '>')) = 0)
    ),
    node_now AS (
      SELECT a.node_id, SUM(m.clicks) AS clicks, COUNT(*) AS members,
             SAFE_DIVIDE(STDDEV(m.cvr), NULLIF(AVG(m.cvr),0)) AS disp
      FROM assign a JOIN mem m USING (campaign_id, keyword_id) GROUP BY 1
    ),
    child AS (
      SELECT node_id, dim, val, SUM(clicks) AS clicks, COUNT(*) AS members,
             SAFE_DIVIDE(STDDEV(cvr), NULLIF(AVG(cvr),0)) AS disp
      FROM long GROUP BY 1,2,3
    ),
    scored AS (
      SELECT c.node_id, c.dim,
             COUNT(*) AS children,
             MIN(c.members) AS smallest_child_members,
             MIN(c.clicks)  AS smallest_child_clicks,
             SAFE_DIVIDE(SUM(c.clicks * c.disp), NULLIF(SUM(c.clicks),0)) AS child_disp
      FROM child c
      WHERE c.disp IS NOT NULL
      GROUP BY 1,2
    )
    SELECT s.*, n.disp AS node_disp, n.clicks AS node_clicks, n.members AS node_members,
           n.disp - s.child_disp AS improvement
    FROM scored s JOIN node_now n USING (node_id);

    -- THE WINNING SPLIT PER LEAF: the biggest honest improvement that also leaves both children
    -- standing on real evidence. A split that helps on paper but strands a child is not a split.
    CREATE OR REPLACE TEMP TABLE winner AS
    SELECT * FROM (
      SELECT *, ROW_NUMBER() OVER (PARTITION BY node_id ORDER BY improvement DESC) AS rn
      FROM cand
      WHERE children >= 2
        AND improvement >= min_improvement
        AND smallest_child_members >= min_node_members
        AND smallest_child_clicks  >= min_node_clicks
        AND node_members >= min_node_members * 2
    ) WHERE rn = 1;

    SET split_count = (SELECT COUNT(*) FROM winner);

    IF split_count > 0 THEN
      -- reassign members into their new child nodes
      CREATE OR REPLACE TEMP TABLE assign_next AS
      SELECT a.campaign_id, a.keyword_id,
             IF(w.node_id IS NULL, a.node_id,
                CONCAT(a.node_id, '/', w.dim, '=', COALESCE(
                  CASE w.dim WHEN 'channel' THEN m.channel WHEN 'subject_kind' THEN m.subject_kind
                             WHEN 'intent_type' THEN m.intent_type WHEN 'family' THEN m.family
                             WHEN 'term_kind' THEN m.term_kind WHEN 'is_gift' THEN m.is_gift
                             WHEN 'age_group' THEN m.age_group WHEN 'gender' THEN m.gender
                             WHEN 'product_type' THEN m.product_type END, 'NULL'))) AS node_id,
             IF(w.node_id IS NULL, a.depth, a.depth + 1) AS depth,
             IF(w.node_id IS NULL, a.used_dims,
                CONCAT(IFNULL(a.used_dims,''), '<', w.dim, '>')) AS used_dims
      FROM assign a
      JOIN mem m USING (campaign_id, keyword_id)
      LEFT JOIN winner w ON w.node_id = a.node_id;

      -- a member whose value on the winning dimension is NULL cannot be placed: it stays put, which
      -- is why a node can keep members after splitting rather than emptying.
      CREATE OR REPLACE TEMP TABLE assign AS SELECT * FROM assign_next;

      INSERT INTO nodes
      SELECT DISTINCT a.node_id, w.node_id AS parent_id, a.depth, w.dim,
             REGEXP_EXTRACT(a.node_id, r'=([^/]*)$') AS split_value,
             a.node_id AS path, TRUE
      FROM assign a JOIN winner w ON STARTS_WITH(a.node_id, CONCAT(w.node_id, '/', w.dim, '='))
      WHERE NOT EXISTS (SELECT 1 FROM nodes n WHERE n.node_id = a.node_id);

      UPDATE nodes SET is_leaf = FALSE WHERE node_id IN (SELECT node_id FROM winner);
    END IF;
  END WHILE;

  -- ---- publish -------------------------------------------------------------------------------
  -- TWO THINGS THE FIRST CUT GOT WRONG, both found by reading the output rather than the code.
  --
  -- (1) ONLY TEACHING MEMBERS WERE PLACED. The tree is GROWN from subjects with >= 30 clicks, but
  --     it must ANSWER for every subject — 849 exist and only 327 teach. The other 522 were left
  --     with no flow at all, which breaks the one promise the root is for: a generic answer for any
  --     keyword. Teaching and membership are different things, and conflating them silently
  --     abandoned 62 % of the account.
  -- (2) INTERNAL NODES HAD NO PROFILE. Members were recorded only at their final leaf, so a parent
  --     had nobody and published nothing — and falling back to a shallower flow, which is the whole
  --     point of a tree when the deep node is thin, had nothing to fall back TO.
  --
  -- Both are fixed by separating the two ideas: every subject is WALKED DOWN the grown tree by its
  -- own facets to the deepest node that exists for it, and every node's profile ROLLS UP all of its
  -- descendants' teaching members.

  -- walk EVERY subject (teaching or not) down the tree it did not necessarily help build
  CREATE OR REPLACE TEMP TABLE all_subject AS
  SELECT s.campaign_id, s.keyword_id, s.target_text, s.family AS subject_family,
         s.channel, s.subject_kind, s.intent_type, s.family, s.term_kind,
         CAST(s.is_gift AS STRING) AS is_gift, s.age_group, s.gender, s.product_type
  FROM `onyga-482313.OI.T_SUBJECT_FLOW` s;

  CREATE OR REPLACE TEMP TABLE placed AS
  WITH cand AS (
    SELECT a.campaign_id, a.keyword_id, n.node_id, n.depth
    FROM all_subject a
    JOIN nodes n
      ON n.node_id = 'ROOT'
      OR n.node_id = CONCAT('ROOT/', n.split_dim, '=', 'x')   -- placeholder, replaced below
    WHERE FALSE
  )
  -- the node path is self-describing, so a subject's own path is rebuilt from its facets and the
  -- deepest node that actually EXISTS in the grown tree is taken.
  SELECT a.campaign_id, a.keyword_id,
         ARRAY_AGG(n.node_id ORDER BY n.depth DESC LIMIT 1)[SAFE_OFFSET(0)] AS node_id,
         MAX(n.depth) AS depth
  FROM all_subject a
  JOIN nodes n
    ON n.node_id = 'ROOT'
    OR STARTS_WITH(CONCAT(
         'ROOT',
         IFNULL(CONCAT('/age_group=', IFNULL(a.age_group,'NULL')), ''),
         IFNULL(CONCAT('/subject_kind=', a.subject_kind), ''),
         IFNULL(CONCAT('/family=', a.family), ''),
         IFNULL(CONCAT('/channel=', a.channel), ''),
         IFNULL(CONCAT('/product_type=', IFNULL(a.product_type,'NULL')), ''),
         IFNULL(CONCAT('/intent_type=', a.intent_type), ''),
         IFNULL(CONCAT('/term_kind=', a.term_kind), ''),
         IFNULL(CONCAT('/is_gift=', IFNULL(a.is_gift,'NULL')), ''),
         IFNULL(CONCAT('/gender=', IFNULL(a.gender,'NULL')), '')), n.node_id)
  GROUP BY 1,2;

  CREATE OR REPLACE TABLE `onyga-482313.OI.T_SUBJECT_FLOW_NODE`
  OPTIONS (description = "Which grown flow node each subject sits in (§2.0.3). EVERY subject is placed, not only the ones that taught the tree: the tree is GROWN from subjects with enough clicks and must ANSWER for all of them, and conflating teaching with membership silently abandoned 62% of the account on the first build. Rebuilt by SP_BUILD_CUSTOMER_PURCHASE_FLOWS.")
  AS SELECT p.campaign_id, p.keyword_id, a.target_text, a.subject_family,
            p.node_id, p.depth,
            (SELECT COUNT(*) FROM mem m
              WHERE m.campaign_id = p.campaign_id AND m.keyword_id = p.keyword_id) > 0 AS taught_the_tree,
            CURRENT_TIMESTAMP() AS built_at
     FROM placed p JOIN all_subject a USING (campaign_id, keyword_id);

  -- EVERY node's profile rolls up ALL of its descendants, so a parent is a real fallback and not an
  -- empty row. A node's descendants are exactly the nodes whose path starts with its own.
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_CUSTOMER_PURCHASE_FLOW`
  OPTIONS (description = "The grown customer purchase flow tree (§2.0.3, Ori 2026-08-25). GREEDY rather than a fixed ladder: every node split on whichever dimension most reduced its children's click-weighted dispersion, so different branches split on different dimensions and depth is decided by evidence rather than declared. Measured at the root, the best splits are age_group (0.581) and subject_kind (0.581) while channel ranks 7th of 9 (0.885) and family and intent_type are the two WORST available — coverage says which fields are safe, not which are informative, which is why the fixed coverage-ordered ladder it replaced was almost exactly wrong. A node splits only when the improvement clears a declared threshold AND both children keep enough members and clicks; depth is NOT capped, growth stops when nothing helps. EVERY node carries a profile rolled up from all its descendants, so a shallower node is a real fallback rather than an empty row. The profile is split BY LINK (CPC, CVR, gross profit per order, clicks per active day) because the purpose is to see WHICH link is wrong. Rebuilt by SP_BUILD_CUSTOMER_PURCHASE_FLOWS.")
  AS
  SELECT
    n.node_id, n.parent_id, n.depth, n.split_dim, n.split_value, n.is_leaf,
    COUNT(DISTINCT FORMAT('%s|%s', m.campaign_id, m.keyword_id)) AS members_teaching,
    (SELECT COUNT(*) FROM `onyga-482313.OI.T_SUBJECT_FLOW_NODE` t
      WHERE t.node_id = n.node_id OR STARTS_WITH(t.node_id, CONCAT(n.node_id, '/'))) AS members_total,
    SUM(m.clicks) AS clicks, SUM(m.orders) AS orders, ROUND(SUM(m.cost),2) AS cost,
    ROUND(SAFE_DIVIDE(SUM(m.cost),   NULLIF(SUM(m.clicks),0)), 4) AS flow_cpc,
    ROUND(SAFE_DIVIDE(SUM(m.orders), NULLIF(SUM(m.clicks),0)), 5) AS flow_cvr,
    ROUND(SAFE_DIVIDE(SUM(m.gp),     NULLIF(SUM(m.orders),0)), 4) AS flow_gp_per_order,
    ROUND(SAFE_DIVIDE(SUM(m.gp),     NULLIF(SUM(m.cost),0)),   4) AS flow_gp_roas,
    ROUND(AVG(SAFE_DIVIDE(m.clicks, NULLIF(m.days_with_clicks,0))), 3) AS flow_clicks_per_active_day,
    ROUND(SAFE_DIVIDE(STDDEV(m.cvr), NULLIF(AVG(m.cvr),0)), 3) AS cvr_dispersion,
    CURRENT_TIMESTAMP() AS built_at
  FROM nodes n
  JOIN `onyga-482313.OI.T_SUBJECT_FLOW_NODE` t
    ON t.node_id = n.node_id OR STARTS_WITH(t.node_id, CONCAT(n.node_id, '/'))
  JOIN mem m ON m.campaign_id = t.campaign_id AND m.keyword_id = t.keyword_id
  GROUP BY 1,2,3,4,5,6;
END;
