-- =============================================
-- FN_EXTRACT_BUDGET
-- =============================================
-- The sixth query facet: what the SHOPPER said about their budget.
-- Companion to FN_EXTRACT_SEGMENTS (gender / age_group / occasion / holiday).
--
-- NOT the same as FACT_RESEARCH_RANKED.price_bucket, which is OUR price relative to the
-- market (A. Cheaper … E. Way above). This is the customer's own stated constraint, read
-- from the words they typed. A shopper searching "gifts under 10 dollars" and one searching
-- "gifts for girls" want different products at different prices and convert very differently.
--
-- Measured 2026-07-24 over the trailing 365 days, price-qualified vs everything else:
--   price intent     3,789 terms   8,438 clicks   1.47% CVR   $0.302 GP/click   0.90 GP-ROAS
--   everything else 197,350 terms 825,147 clicks   3.99% CVR   $0.696 GP/click   1.33 GP-ROAS
-- The only bucket in the account that loses money on gross profit.
--
-- Returns budget_tier plus the parsed ceiling where the shopper named a number, so the bid
-- model can distinguish "under $10" from "under $50" rather than lumping both into "cheap".
--
--   DEAL_SEEKER  deals / cheap / bargain / discount / on sale — no number given
--   UNDER_N      an explicit ceiling ("under 10 dollars", "$15 gifts", "10 dollar gift")
--   IMPLIED_LOW  "stuff" / "things" — budget never stated, but the behaviour is identical
--   PREMIUM      luxury / high end / splurge / best quality — the opposite signal
--   NULL         no budget language at all (the overwhelming majority)
--
-- IMPLIED_LOW (Ori, 2026-07-24: "stuff usually implies low budget"). Confirmed and then some —
-- it is the largest low-budget bucket by an order of magnitude and the worst-performing traffic
-- in the account:
--   stuff/things   11,384 terms  37,218 clicks  1.40% CVR  $0.293 GP/click  0.65 GP-ROAS
--   UNDER_N         2,777         3,464         1.41%      $0.326           0.89
--   DEAL_SEEKER       612         4,445         1.78%      $0.341           1.06
--   no budget     185,766       787,237         4.11%      $0.714           1.35
-- Converts identically to shoppers who literally type "under $10", at 10x their combined
-- volume, and returns less per dollar than either. ~$16,800 spent to make ~$10,900.
-- Ranked BELOW the stated signals so "cheap stuff for girls" reads DEAL_SEEKER, not IMPLIED_LOW:
-- an explicit statement of budget outranks an inferred one.
--
-- price_ceiling is only populated for UNDER_N. It is a plain number of dollars.
--
-- Edit ONLY here — like FN_EXTRACT_SEGMENTS, this is the single source of truth and is
-- consumed by V_ADS_SEARCH_TERM_FACETS.
-- SOP: docs/superpowers/specs/2026-07-24-intent-coverage-phase0-design.md
-- =============================================

CREATE OR REPLACE FUNCTION `onyga-482313`.OI.FN_EXTRACT_BUDGET(query_text STRING)
RETURNS STRUCT<budget_tier STRING, price_ceiling FLOAT64>
AS (STRUCT(
  CASE
    -- An explicit number wins over a vague word: "cheap gifts under $20" is UNDER_N.
    WHEN REGEXP_CONTAINS(LOWER(query_text),
      r'under \$?\d+|below \$?\d+|less than \$?\d+|\$\d+ (and )?(under|or less)|\$\d+|\b\d+ dollars?\b')
      THEN 'UNDER_N'
    WHEN REGEXP_CONTAINS(LOWER(query_text),
      r'\bdeals?\b|\bcheap(er|est)?\b|\bbudget\b|\bon sale\b|\bsale\b|\baffordable\b|\binexpensive\b|\bbargain\b|\bdiscount|\blow cost\b|\bunder budget\b')
      THEN 'DEAL_SEEKER'
    WHEN REGEXP_CONTAINS(LOWER(query_text),
      r'\bluxur|\bpremium\b|\bhigh.end\b|\bsplurge\b|\bexpensive\b|\bdesigner\b|\bbest quality\b')
      THEN 'PREMIUM'
    -- Inferred, not stated. Last among the low-budget arms so any explicit signal wins.
    WHEN REGEXP_CONTAINS(LOWER(query_text), r'\b(stuff|things)\b')
      THEN 'IMPLIED_LOW'
    ELSE NULL
  END,
  -- The named ceiling, when there is one. Three single-group patterns tried in order of how
  -- unambiguous they are (REGEXP_EXTRACT permits only one capturing group, hence the COALESCE).
  -- Order matters: "gifts under 10 dollars for 12 year old girls" must read 10, not 12, so the
  -- explicit "under N" phrasing is tried first and the age digits that follow can never win.
  -- Gated on the tier so a bare number in a non-price query ("12 year old") yields NULL.
  IF(
    CASE
      WHEN REGEXP_CONTAINS(LOWER(query_text),
        r'under \$?\d+|below \$?\d+|less than \$?\d+|\$\d+ (and )?(under|or less)|\$\d+|\b\d+ dollars?\b')
        THEN TRUE ELSE FALSE
    END,
    SAFE_CAST(COALESCE(
      REGEXP_EXTRACT(LOWER(query_text), r'(?:under|below|less than)\s*\$?(\d+)'),
      REGEXP_EXTRACT(LOWER(query_text), r'\$(\d+)'),
      REGEXP_EXTRACT(LOWER(query_text), r'\b(\d+)\s*dollars?\b')
    ) AS FLOAT64),
    NULL)
));
