-- =============================================
-- SP_REFRESH_RESEARCH_RECOMMENDATIONS
-- Weekly idempotent top-up of FACT_RESEARCH_RECOMMENDATIONS:
--   A. status maintenance: NEW -> ADVERTISED when a term now has 7-day clicks
--   B. Broad clusters (co-occurrence, fit>=90 seeds with market demand, >500 sales)
--   C. Phrase coverage_count
--   D. assemble candidate pool with sort_metric + dedup vs history & now-advertised
--   E. insert up to (5 - emitted_this_week) per family x type, top by sort_metric
-- Called by SP_ORCHESTRATE_DAILY_REFRESH after SP_REFRESH_RESEARCH_RANKED.
-- Broad co-occurrence is bounded (market-demand seeds + temp tables) to stay under
-- the per-statement CPU guard. SOP: architecture/RESEARCH_PAGE.md
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REFRESH_RESEARCH_RECOMMENDATIONS`()
BEGIN
  DECLARE wk DATE DEFAULT DATE_TRUNC(CURRENT_DATE(), WEEK(MONDAY));

  -- ── Step A: status maintenance — a rec is ADVERTISED once we run a keyword of
  -- its own match type on it (per-type 7-day keyword spend, from FACT_RESEARCH_RANKED).
  UPDATE `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS` t
  SET status = 'ADVERTISED'
  FROM `onyga-482313.OI.FACT_RESEARCH_RANKED` rr
  WHERE t.status = 'NEW'
    AND rr.parent_name = t.parent_name
    AND LOWER(rr.query_text) = LOWER(t.keyword)
    AND (
      (t.rec_type = 'EXACT'  AND COALESCE(rr.exact_kw_cost_7d, 0)  > 0) OR
      (t.rec_type = 'PHRASE' AND COALESCE(rr.phrase_kw_cost_7d, 0) > 0) OR
      (t.rec_type = 'BRAND'  AND COALESCE(rr.phrase_kw_cost_7d, 0) > 0) OR
      (t.rec_type = 'BROAD'  AND COALESCE(rr.broad_kw_cost_7d, 0)  > 0)
    );

  -- ── Step B: Broad clusters (fit>=90 seeds WITH market demand, bounded expansion)
  CREATE TEMP TABLE _broad_seeds AS
  SELECT c.parent_name, c.query_text
  FROM `onyga-482313.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES` c
  JOIN `onyga-482313.OI.FACT_RESEARCH_TERMS` rt
    ON LOWER(rt.query_text) = LOWER(c.query_text) AND COALESCE(rt.market_purchases, 0) > 0
  WHERE c.rec_type = 'BROAD';

  -- fit>=90 candidate terms per family (the only terms allowed into a cluster)
  CREATE TEMP TABLE _fit90 AS
  SELECT parent_name, LOWER(query_text) AS query_text
  FROM `onyga-482313.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES`
  WHERE rec_type = 'BROAD';

  CREATE TEMP TABLE _seed_asins AS
  SELECT s.parent_name, s.query_text AS seed, sq.ASIN
  FROM _broad_seeds s
  JOIN `onyga-482313.OI.FACT_SEARCH_QUERY` sq
    ON LOWER(sq.query_text) = LOWER(s.query_text)
   AND sq.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 104 WEEK)
  GROUP BY s.parent_name, seed, sq.ASIN;

  -- related queries sharing a seed ASIN, restricted to also-fit>=90 family terms
  CREATE TEMP TABLE _related AS
  SELECT sa.parent_name, sa.seed, LOWER(sq2.query_text) AS member
  FROM _seed_asins sa
  JOIN `onyga-482313.OI.FACT_SEARCH_QUERY` sq2
    ON sq2.ASIN = sa.ASIN
   AND sq2.week_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 104 WEEK)
   AND sq2.query_text != 'OTHER'
  JOIN _fit90 f ON f.parent_name = sa.parent_name AND f.query_text = LOWER(sq2.query_text)
  GROUP BY sa.parent_name, sa.seed, member;

  CREATE TEMP TABLE _broad_cluster AS
  WITH cluster_terms AS (
    SELECT parent_name, seed, member FROM _related
    UNION DISTINCT
    SELECT parent_name, seed, LOWER(seed) FROM _related
  )
  SELECT
    ct.parent_name, ct.seed,
    COUNT(DISTINCT ct.member) AS cluster_size,
    CAST(SUM(COALESCE(rt.market_purchases, 0)) AS INT64) AS cluster_sales
  FROM cluster_terms ct
  LEFT JOIN `onyga-482313.OI.FACT_RESEARCH_TERMS` rt
    ON LOWER(rt.query_text) = ct.member
  GROUP BY ct.parent_name, ct.seed;

  -- ── Step C: Phrase coverage_count, bounded to the top-30 phrase seeds per family
  -- (coverage is only a rank tie-breaker; computing it for all candidates is wasteful
  -- and the token-match join must stay small). Counts other family terms that contain
  -- ALL of the seed's significant tokens (de-correlated into joins — BigQuery rejects
  -- correlated array subqueries).
  CREATE TEMP TABLE _phrase_top AS
  SELECT parent_name, query_text
  FROM (
    SELECT parent_name, query_text,
      ROW_NUMBER() OVER (PARTITION BY parent_name ORDER BY rank DESC, query_text) AS rn
    FROM `onyga-482313.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES`
    WHERE rec_type = 'PHRASE'
  ) WHERE rn <= 30;

  CREATE TEMP TABLE _seed_tokens AS
  SELECT t.parent_name, t.query_text, w AS tok
  FROM _phrase_top t, UNNEST(SPLIT(LOWER(t.query_text), ' ')) w
  WHERE w NOT IN ('a','an','the','for','and','or','of','to','in','on','at','by','is','it','my','with')
    AND w != '';

  CREATE TEMP TABLE _phrase_cov AS
  WITH seed_ntok AS (
    SELECT parent_name, query_text, COUNT(*) AS ntok
    FROM _seed_tokens GROUP BY parent_name, query_text
  ),
  fam_terms AS (
    SELECT DISTINCT parent_name, LOWER(query_text) AS term
    FROM `onyga-482313.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES`
  ),
  matched AS (
    SELECT st.parent_name, st.query_text, ft.term, COUNT(DISTINCT st.tok) AS n_matched
    FROM _seed_tokens st
    JOIN fam_terms ft
      ON ft.parent_name = st.parent_name
     AND ft.term != LOWER(st.query_text)
     AND ft.term LIKE CONCAT('%', st.tok, '%')
    GROUP BY st.parent_name, st.query_text, ft.term
  )
  SELECT sn.parent_name, sn.query_text,
    COUNTIF(m.n_matched = sn.ntok) AS coverage_count
  FROM seed_ntok sn
  LEFT JOIN matched m
    ON m.parent_name = sn.parent_name AND m.query_text = sn.query_text
  GROUP BY sn.parent_name, sn.query_text;

  -- ── Step D: assemble candidate pool with sort_metric + dedup (anti-join, de-correlated)
  CREATE TEMP TABLE _hist AS
  SELECT DISTINCT parent_name, rec_type, LOWER(keyword) AS keyword
  FROM `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS`
  WHERE status IN ('NEW','ADVERTISED');

  CREATE TEMP TABLE _pool AS
  SELECT
    c.parent_name, c.rec_type, c.match_type, c.keyword, c.query_text,
    c.rank, c.overall_fit, c.market_volume,
    CASE WHEN c.rec_type = 'BROAD' THEN bc.cluster_sales ELSE NULL END AS market_sales,
    pc.coverage_count,
    CASE WHEN c.rec_type = 'BROAD' THEN bc.cluster_size ELSE NULL END AS cluster_size,
    CASE
      WHEN c.rec_type = 'BROAD'  THEN CAST(bc.cluster_sales AS FLOAT64)
      WHEN c.rec_type = 'PHRASE' THEN c.sort_metric + COALESCE(pc.coverage_count, 0) / 1000.0
      ELSE c.sort_metric
    END AS sort_metric
  FROM `onyga-482313.OI.V_RESEARCH_RECOMMENDATION_CANDIDATES` c
  LEFT JOIN _broad_cluster bc
    ON bc.parent_name = c.parent_name AND LOWER(bc.seed) = LOWER(c.query_text)
  LEFT JOIN _phrase_cov pc
    ON pc.parent_name = c.parent_name AND pc.query_text = c.query_text
  LEFT JOIN _hist h
    ON h.parent_name = c.parent_name AND h.rec_type = c.rec_type AND h.keyword = LOWER(c.keyword)
  -- "not advertised" (no matching-type keyword spend) is already enforced by the
  -- candidate view's per-type gate, so no search-term anti-join here.
  WHERE h.keyword IS NULL                                          -- never re-recommend
    AND (c.rec_type != 'BROAD' OR bc.cluster_sales > 500);         -- Broad cluster threshold

  -- ── Step E: per family x type, insert up to (5 - already NEW this week)
  CREATE TEMP TABLE _existing AS
  SELECT parent_name, rec_type, COUNT(*) AS n_existing
  FROM `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS`
  WHERE week_start = wk AND status = 'NEW'
  GROUP BY parent_name, rec_type;

  INSERT INTO `onyga-482313.OI.FACT_RESEARCH_RECOMMENDATIONS`
    (rec_id, week_start, parent_name, rec_type, match_type, keyword, query_text,
     rank, overall_fit, market_sales, market_volume, coverage_count, cluster_size, status, created_at)
  SELECT
    TO_HEX(MD5(CONCAT(parent_name, '|', rec_type, '|', keyword))) AS rec_id,
    wk, parent_name, rec_type, match_type, keyword, query_text,
    rank, overall_fit, market_sales, market_volume, coverage_count, cluster_size,
    'NEW', CURRENT_TIMESTAMP()
  FROM (
    SELECT p.*,
      ROW_NUMBER() OVER (PARTITION BY p.parent_name, p.rec_type ORDER BY p.sort_metric DESC, p.keyword) AS rn,
      COALESCE(e.n_existing, 0) AS n_existing
    FROM _pool p
    LEFT JOIN _existing e ON e.parent_name = p.parent_name AND e.rec_type = p.rec_type
  )
  WHERE rn <= (5 - n_existing);
END;
