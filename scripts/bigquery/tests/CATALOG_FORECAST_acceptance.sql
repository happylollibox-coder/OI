-- =============================================================================================
-- V_CATALOG_FORECAST acceptance — the chain and the price it picks. v27.77 (2026-08-25).
-- Forecast chain step 2. Every check returns a VIOLATION COUNT; every row must read PASS.
--
-- THE TWO CHECKS THAT MATTER MOST ARE F01 AND F02, and they are not style checks.
-- F01 pins the chain to HOUSE PRICING: contribution per click is gp_per_click/keyword_bar - cpc,
--     which is zero exactly at the house's own affordable_cpc. If the chain stops reproducing that
--     number it has quietly started pricing keywords by a different rule than the rest of the
--     account, which is how two layers end up spending against different definitions of money.
-- F02 pins the GRID to the CLOSED FORM. Gross profit per click does not depend on price, so the
--     optimum is provably ceiling * e/(1+e). A grid that drifts from it is broken in a way that
--     still returns a plausible-looking price -- the most dangerous failure this view can have.
-- F12 exists because the seasonal legs were wired in after the fact: if a future edit reverts the
--     clicks leg to one season-blind baseline, every seasonal answer silently becomes the same
--     answer, and nothing else here would notice.
-- =============================================================================================
WITH f AS (SELECT * FROM `onyga-482313.OI.V_CATALOG_FORECAST`),
tol AS (SELECT 0.005 AS rel, 0.002 AS abs_floor),

-- F01 THE CEILING IS THE HOUSE'S affordable_cpc, on rows that use purely the subject's own rates.
--     (Rows blended with a flow SHOULD differ -- the flow supplies a different rate on purpose.)
f01 AS (SELECT COUNTIF(ABS(ceiling_cpc - house_affordable_cpc) > 0.005) AS v
        FROM f WHERE rate_basis = 'DATA: own settled rates' AND house_affordable_cpc IS NOT NULL),

-- F02 THE GRID AGREES WITH THE CLOSED FORM wherever the optimum lies inside the searched range.
--     Tolerance is one grid step, because that is the resolution the grid can express.
f02 AS (SELECT COUNTIF(ABS(best_cpc - best_cpc_closed_form) > 0.011) AS v
        FROM f WHERE best_cpc_closed_form BETWEEN grid_lo AND grid_hi),

-- F03 BASIS IS NEVER BLANK, and an UNKNOWN never carries a number. A forecast that does not say
--     where it came from is worse than no forecast, because the Brain cannot weigh it.
f03 AS (SELECT COUNTIF(rate_basis IS NULL OR rate_basis = '' OR clicks_basis IS NULL
                       OR (rate_basis LIKE 'UNKNOWN%' AND best_cpc IS NOT NULL)) AS v FROM f),

-- F04 HALO IS NEVER ABSENT AND NEVER DEFAULTED. Without keyword_bar every contribution is NULL and
--     the "best" point would be chosen by ordering a column that is NULL everywhere.
f04 AS (SELECT COUNTIF(halo_factor IS NULL OR keyword_bar IS NULL
                       OR halo_factor <= 0 OR keyword_bar <= 0) AS v FROM f),

-- F05 ONE ROW PER SUBJECT PER SEASON. Flow membership is (subject x season) and fans out 2.09x if
--     the season is not pinned -- that fan-out would multiply the account's forecast money.
f05 AS (SELECT COUNTIF(n > 1) AS v FROM (
          SELECT campaign_id, keyword_id, season, COUNT(*) AS n FROM f GROUP BY 1,2,3)),

-- F06 THE CONTRIBUTION IS THE ARITHMETIC IT CLAIMS: clicks * (gp_per_click/bar - cpc), at HALF
--     halo credit. Full credit would sanction bids the house bar rejects by up to 27%.
f06 AS (SELECT COUNTIF(
          ABS(contribution_per_day
              - clicks_per_day * (SAFE_DIVIDE(gp_per_click_modelled, keyword_bar) - best_cpc))
          > GREATEST((SELECT abs_floor FROM tol),
                     (SELECT rel FROM tol) * ABS(contribution_per_day))) AS v FROM f),

-- F07 THE GRID NEVER PRICES BEYOND THE EVIDENCE. The response curve is a power law; extrapolating
--     it past the highest price a keyword was ever paid invents clicks that were never observed.
f07 AS (SELECT COUNTIF(best_cpc > grid_hi + 0.0001 OR best_cpc < grid_lo - 0.0001) AS v FROM f),

-- F08 THE CLICKS LEG AND THE MONEY LEG SHARE A SEASON. Otherwise a December answer carries
--     December conversion on August traffic, and the row describes two different months.
f08 AS (SELECT COUNTIF(clicks_basis LIKE 'DATA:%' AND STRPOS(clicks_basis, season) = 0) AS v
        FROM f),

-- F09 ads_net_roas IS gross profit over cost, with no halo in it. The halo belongs to net_roas.
f09 AS (SELECT COUNTIF(ABS(ads_net_roas - SAFE_DIVIDE(gp_per_click_modelled, best_cpc))
                       > GREATEST(0.002, 0.005 * ads_net_roas)) AS v FROM f),

-- F10 NET ROAS CARRIES THE HALO EXACTLY ONCE. Layering halo onto a bar-adjusted number is the
--     classic double-count, and it inflates every answer.
f10 AS (SELECT COUNTIF(ABS(net_roas - ads_net_roas * halo_factor)
                       > GREATEST(0.002, 0.005 * net_roas)) AS v FROM f),

-- F11 A RECOMMENDATION RESTS ON A POSITIVE RATE. A zero or negative CVR or GP-per-order cannot
--     produce a price worth paying, and must not reach the output as one.
f11 AS (SELECT COUNTIF(cvr_used <= 0 OR gp_per_order_used <= 0 OR gp_per_click_modelled <= 0) AS v
        FROM f),

-- F12 THE SEASONS ACTUALLY DIFFER. If a future edit reverts the clicks leg to one season-blind
--     baseline, every seasonal answer collapses to the same answer and nothing else here notices.
f12 AS (SELECT IF(COUNT(DISTINCT ROUND(cpd, 2)) > 1, 0, 1) AS v
        FROM (SELECT season, SUM(contribution_per_day) AS cpd FROM f GROUP BY season)),

-- F13 THE VIEW DECIDES NOTHING. It must publish no bid, budget or pause column.
f13 AS (SELECT COUNTIF(LOWER(column_name) IN ('new_bid','bid','budget','action','apply','pause')) AS v
        FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
        WHERE table_name = 'V_CATALOG_FORECAST')

SELECT * FROM (
  SELECT 1  AS n, 'F01 the ceiling reproduces house affordable_cpc' AS check_name, v FROM f01 UNION ALL
  SELECT 2,  'F02 the grid agrees with the closed form',        v FROM f02 UNION ALL
  SELECT 3,  'F03 basis is never blank; UNKNOWN carries no number', v FROM f03 UNION ALL
  SELECT 4,  'F04 halo is never absent and never defaulted',    v FROM f04 UNION ALL
  SELECT 5,  'F05 one row per subject per season',              v FROM f05 UNION ALL
  SELECT 6,  'F06 contribution is the arithmetic it claims',    v FROM f06 UNION ALL
  SELECT 7,  'F07 the grid never prices beyond the evidence',   v FROM f07 UNION ALL
  SELECT 8,  'F08 the clicks leg and money leg share a season', v FROM f08 UNION ALL
  SELECT 9,  'F09 ads_net_roas has no halo in it',              v FROM f09 UNION ALL
  SELECT 10, 'F10 net_roas carries the halo exactly once',      v FROM f10 UNION ALL
  SELECT 11, 'F11 a recommendation rests on a positive rate',   v FROM f11 UNION ALL
  SELECT 12, 'F12 the seasons actually differ',                 v FROM f12 UNION ALL
  SELECT 13, 'F13 the view decides nothing',                    v FROM f13
)
ORDER BY n;
