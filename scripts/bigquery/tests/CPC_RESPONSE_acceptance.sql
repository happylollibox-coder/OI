-- =============================================================================================
-- V_CPC_RESPONSE / V_CPC_ELASTICITY acceptance — the price-to-clicks link. v27.76 (2026-08-25).
-- Forecast chain step 1. Every check returns a VIOLATION COUNT; every row must read PASS.
--
-- WHAT THIS SUITE IS REALLY GUARDING. Three defects were found and fixed while building this pair,
-- and each one was SILENT — the views returned confident, plausible numbers while wrong:
--   * a channel test of LIKE 'SP%' matched SPONSORED_BRANDS, folding the larger channel into the
--     smaller and erasing the SB/SP asymmetry the whole thing exists to publish (C05, C06);
--   * an inner join to the fact table dropped every keyword that had gone quiet, so a 65% coverage
--     gap read as "nothing to report" instead of "I cannot answer these" (C02, C10);
--   * per-keyword elasticities pinned half their values against the safety clamp, which meant the
--     clamp and not the data was setting the price response (C11).
-- C11 in particular PINS A DESIGN DECISION rather than a computation: rebuilding per-keyword fits
-- must break a test loudly, because the standard errors that killed the idea are still that wide.
-- =============================================================================================
WITH r AS (SELECT * FROM `onyga-482313.OI.V_CPC_RESPONSE`),
el AS (SELECT * FROM `onyga-482313.OI.V_CPC_ELASTICITY`),
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
tol AS (SELECT 0.005 AS rel, 0.002 AS abs_floor),

-- C01 THE PUBLISHED CONTRACT IS THE ARITHMETIC ACTUALLY PERFORMED. The header promises
--     clicks(cpc) = base * (cpc/base_cpc)^e; if the evaluated columns drift from that formula the
--     caller's own arithmetic silently disagrees with the view's.
c01 AS (
  SELECT COUNTIF(
    ABS(clicks_per_day_at_125x - baseline_clicks_per_day * POW(1.25, elasticity))
      > GREATEST((SELECT abs_floor FROM tol),
                 (SELECT rel FROM tol) * baseline_clicks_per_day * POW(1.25, elasticity))
    OR ABS(clicks_per_day_at_075x - baseline_clicks_per_day * POW(0.75, elasticity))
      > GREATEST((SELECT abs_floor FROM tol),
                 (SELECT rel FROM tol) * baseline_clicks_per_day * POW(0.75, elasticity))
  ) AS v FROM r WHERE elasticity IS NOT NULL),

-- C02 A GAP IS NULL, NEVER ZERO. A keyword with no settled clicks cannot be forecast; publishing 0
--     would let a caller price against a fabricated "we predict no clicks" instead of "unknown".
c02 AS (SELECT COUNTIF(elasticity_basis LIKE 'NO_BASELINE%'
                       AND (clicks_per_day_at_100x IS NOT NULL OR elasticity IS NOT NULL)) AS v FROM r),

-- C03 EVERY ANSWER DISCLOSES ITS BASIS. Ori 2026-08-25: the Catalog must say whether an estimate
--     came from data or from a borrowed flow. An undisclosed number is not an answer.
c03 AS (SELECT COUNTIF(elasticity_basis IS NULL OR elasticity_basis = ''
                       OR (elasticity IS NOT NULL AND elasticity_basis NOT LIKE 'DATA:%')) AS v FROM r),

-- C04 PAYING MORE NEVER BUYS FEWER CLICKS. A non-positive elasticity would invert the curve and
--     make the price search recommend bidding down to buy volume.
c04 AS (SELECT COUNTIF(elasticity <= 0
                       OR clicks_per_day_at_150x < clicks_per_day_at_100x
                       OR clicks_per_day_at_100x < clicks_per_day_at_075x) AS v FROM r
        WHERE elasticity IS NOT NULL),

-- C05 CHANNEL IS ONLY EVER SP OR SB, and BOTH must be present. This is the LIKE 'SP%' regression:
--     that bug left SB with a single observation while SP looked healthy, and nothing else caught it.
c05 AS (SELECT COUNTIF(channel NOT IN ('SP','SB')) + IF(COUNT(DISTINCT channel) = 2, 0, 1) AS v FROM r),

-- C06 THE ELASTICITY IS STABLE OUT OF SAMPLE. A fit that does not survive its own holdout is a
--     description of the past, not a forecast — and this chain exists to forecast.
c06 AS (SELECT COUNTIF(NOT is_usable
                       OR elasticity_holdout IS NULL
                       OR SAFE_DIVIDE(ABS(elasticity_holdout - elasticity_fit),
                                      NULLIF(ABS(elasticity_fit), 0)) > 0.75) AS v FROM el),

-- C07 THE BASELINE IS SETTLED, AND SB WAITS LONGER THAN SP. An unsettled baseline undercounts
--     clicks, which makes every candidate price look worse than it truly is.
c07 AS (SELECT COUNTIF(settled_through > (SELECT watermark FROM wm)) AS v FROM r),
c07b AS (SELECT IF((SELECT MAX(settled_through) FROM r WHERE channel = 'SB')
                   < (SELECT MAX(settled_through) FROM r WHERE channel = 'SP'), 0, 1) AS v),

-- C08 ONE ROW PER KEYWORD. A duplicated keyword would be double-counted by any caller that sums
--     predicted clicks across a campaign.
c08 AS (SELECT COUNTIF(n > 1) AS v FROM (
          SELECT campaign_id, targeting, COUNT(*) AS n FROM r GROUP BY 1,2)),

-- C09 A BASELINE CPC IS A REAL PRICE. Zero or negative would make the ratio in the contract
--     undefined and the curve meaningless.
c09 AS (SELECT COUNTIF(baseline_clicks > 0 AND (baseline_cpc IS NULL OR baseline_cpc <= 0)) AS v FROM r),

-- C10 THE COVERAGE GAP STAYS VISIBLE. If this ever reads zero, someone has restored the inner join
--     and the quiet keywords have gone back to being invisible rather than unanswered.
c10 AS (SELECT IF(COUNTIF(elasticity_basis LIKE 'NO_BASELINE%') > 0, 0, 1) AS v FROM r),

-- C11 ELASTICITY IS PER CHANNEL, NEVER PER KEYWORD. Pins the finding that keyword-level slopes
--     carry a standard error near 1.2 and cannot tell 0.3 from 2.5. Rebuilding them must fail here
--     first, and only pass again once the standard errors have actually come down.
c11 AS (SELECT COUNTIF(n > 1) AS v FROM (
          SELECT channel, COUNT(DISTINCT elasticity) AS n FROM r
          WHERE elasticity IS NOT NULL GROUP BY channel))

SELECT * FROM (
  SELECT 1  AS n, 'C01 the published contract is the arithmetic performed' AS check_name, v FROM c01 UNION ALL
  SELECT 2,  'C02 a gap is NULL, never zero',                         v FROM c02  UNION ALL
  SELECT 3,  'C03 every answer discloses its basis',                  v FROM c03  UNION ALL
  SELECT 4,  'C04 paying more never buys fewer clicks',               v FROM c04  UNION ALL
  SELECT 5,  'C05 channel is only SP or SB, and both are present',    v FROM c05  UNION ALL
  SELECT 6,  'C06 the elasticity is stable out of sample',            v FROM c06  UNION ALL
  SELECT 7,  'C07 the baseline is settled',                           v FROM c07  UNION ALL
  SELECT 8,  'C07b SB waits longer to settle than SP',                v FROM c07b UNION ALL
  SELECT 9,  'C08 one row per keyword',                               v FROM c08  UNION ALL
  SELECT 10, 'C09 a baseline CPC is a real price',                    v FROM c09  UNION ALL
  SELECT 11, 'C10 the coverage gap stays visible',                    v FROM c10  UNION ALL
  SELECT 12, 'C11 elasticity is per channel, never per keyword',      v FROM c11
)
ORDER BY n;
