-- =============================================
-- V_TERM_FAMILY_EVIDENCE — the family's settled evidence per search term (2026-08-16, Task 2.4).
-- Spec: architecture/SEASON_CONTEXT_LEDGER.md §7.12 (sibling evidence).
--
-- (Ori 2026-08-15: "you can check the general performance of the product keyword in other
-- campaign and decide if it worth to lift it again.") A parked keyword generates zero data and
-- cannot prove a trend changed — but the SAME TERM often runs in the family's OTHER campaigns,
-- and those clicks are our own conversions on our own listing: the strongest external evidence
-- that exists. This is PROMOTE_TO_EXACT's inference in the other direction — one rule, two
-- directions. Measured at design time: 10 of 104 CONFIRM_PARK rows had a sibling clearing the
-- revival bar (worst: "journal kit for girls" parked while its sibling held ~4,212 settled
-- clicks at 1.32x).
--
-- GRAIN: one row per (family, term, campaign) CONTRIBUTION — deliberately NOT pre-aggregated to
-- (family, term), so any consumer can exclude ITS OWN campaign and pick its best sibling; the
-- family rollup rides on every row as window columns. Reads ONLY the two snapshot tables —
-- planner-safe, ≤ 1 day stale, which is harmless for 90d settled records.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_TERM_FAMILY_EVIDENCE` AS
SELECT
  g.parent_name AS family,
  LOWER(TRIM(g.keyword_text)) AS term,
  CAST(g.campaign_id AS STRING) AS campaign_id,
  po.campaign_name,
  UPPER(COALESCE(g.match_type, '')) AS match_type,
  g.channel,
  g.settled_clk90, g.settled_ord90, g.settled_roas90, g.settled_cpc90,
  COALESCE(po.is_oob_owned, FALSE) AS is_capped,
  -- the family rollup, on every contribution row
  SUM(g.settled_clk90) OVER w AS family_clk90,
  SUM(g.settled_ord90) OVER w AS family_ord90,
  ROUND(SAFE_DIVIDE(SUM(g.settled_gp90) OVER w, NULLIF(SUM(g.settled_sp90) OVER w, 0)), 3) AS family_gp_roas90,
  COUNT(*) OVER w AS family_campaigns
FROM `onyga-482313.OI.FACT_KEYWORD_GUARD` g
LEFT JOIN `onyga-482313.OI.FACT_PANEL_OWNERSHIP` po
  ON CAST(po.campaign_id AS STRING) = CAST(g.campaign_id AS STRING)
WHERE g.parent_name IS NOT NULL AND g.keyword_text IS NOT NULL
WINDOW w AS (PARTITION BY g.parent_name, LOWER(TRIM(g.keyword_text)));
