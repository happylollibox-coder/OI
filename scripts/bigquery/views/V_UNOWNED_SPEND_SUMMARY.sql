-- =============================================
-- V_UNOWNED_SPEND_SUMMARY — the account-level number to watch daily (2026-08-25).
-- Doctrine: architecture/THREE_LAYERS.md §1.4, §10.1. SOP: architecture/UNOWNED_SPEND.md.
--
-- WHAT THIS IS. The companion to V_UNOWNED_SPEND: how much of the account is spending where no
-- layer can see it, what it returns, and its share of the account — one row per reason class plus a
-- grand total under reason_class = '__ALL__'. The point of it is that the number stops being
-- something a research pass rediscovers and becomes something a person watches.
--
-- READ '__ALL__' FIRST, THEN THE CLASSES. The classes partition the total exactly (first-match
-- precedence in V_UNOWNED_SPEND), so they sum to it. The acceptance suite asserts that.
--
-- READ THE TWO WINDOWS TOGETHER. spend_per_day_28d is the headline and is the same shape as the
-- baseline figure it descends from. spend_per_day_7d is the live half. They diverge a lot and the
-- divergence is the most informative thing here: spend on a PAUSED campaign is a tail that decays
-- to nothing on its own, while spend under the sentinel is money leaving today. A total quoted
-- without both windows is a number that will be argued about.
--
-- SHARE OF THE ACCOUNT IS THE PART THAT TRAVELS. §10.5: a finding's share of the account matters
-- more than its absolute size, because the account itself moves. Both windows carry their share.
--
-- IT ISSUES NO VERDICT. gp_roas is printed; no bar is applied to the population, because the
-- population does not own one — a class spans families, and some of its rows have no family at all.
-- unjudgeable_subjects / unjudgeable_spend_per_day_28d count exactly how much of the money cannot be
-- scored at all, which is a fact about the hole rather than about the subjects.
--
-- REPORTING ONLY. Reads. Writes nothing. Read by no engine, no book, no generator, not in the
-- orchestrator. Asking changes nothing (§1.4).
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_UNOWNED_SPEND_SUMMARY`
OPTIONS (
  description = "THE DAILY NUMBER FOR MONEY NO LAYER CAN SEE (2026-08-25). Companion to V_UNOWNED_SPEND: how much of the account spends with no row in FACT_KEYWORD_STATE, what it returns, and its share of the account. One row per reason_class — SENTINEL | CAMPAIGN_OUTSIDE_UNIVERSE | SUBJECT_OUTSIDE_UNIVERSE | DROPPED_DOWNSTREAM — plus a grand total under reason_class = '__ALL__'. The classes partition the total exactly and sum to it (asserted in scripts/bigquery/tests/V_UNOWNED_SPEND_acceptance.sql), and the total reconciles against FACT_AMAZON_ADS: unowned + owned = the account's spend over the same window. READ THE TWO WINDOWS TOGETHER — spend_per_day_28d is the headline, spend_per_day_7d is the live half, and they diverge a lot: spend on a paused campaign is a tail that decays on its own, spend under the sentinel is money leaving today. Both carry their share of the account, which is the figure that survives the account changing size. NO VERDICT IS ISSUED: gp_roas is printed and no bar is applied to a population that does not own one; unjudgeable_subjects and unjudgeable_spend_per_day_28d say how much of it cannot be scored at all. Every row carries one plain-language sentence. REPORTING ONLY — writes nothing, read by no engine or book, not in the orchestrator. SOP: architecture/UNOWNED_SPEND.md."
)
AS
WITH
u AS (SELECT * FROM `onyga-482313.OI.V_UNOWNED_SPEND`),
w AS (SELECT MAX(as_of) AS as_of, MAX(window_days) AS window_days, MAX(recent_days) AS recent_days
      FROM u),
-- The account, over exactly the same two windows and from the same fact table. This is what makes
-- the reconciliation an identity rather than a comparison of two nearly-equal numbers.
acct AS (
  SELECT
    SUM(a.Ads_cost) / w.window_days                                                   AS a_spend_28,
    SUM(a.GROSS_PROFIT) / w.window_days                                               AS a_gp_28,
    SUM(IF(a.date > DATE_SUB(w.as_of, INTERVAL w.recent_days DAY), a.Ads_cost, 0)) / w.recent_days
                                                                                      AS a_spend_7,
    SUM(IF(a.date > DATE_SUB(w.as_of, INTERVAL w.recent_days DAY), a.GROSS_PROFIT, 0)) / w.recent_days
                                                                                      AS a_gp_7
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  CROSS JOIN w
  WHERE a.date BETWEEN DATE_SUB(w.as_of, INTERVAL w.window_days - 1 DAY) AND w.as_of
  GROUP BY w.window_days, w.recent_days
),
grouped AS (
  SELECT reason_class, u.* EXCEPT (reason_class) FROM u
  UNION ALL
  SELECT '__ALL__' AS reason_class, u.* EXCEPT (reason_class) FROM u
),
agg AS (
  SELECT
    g.reason_class,
    COUNT(*)                                                          AS subjects,
    COUNT(DISTINCT CONCAT(g.campaign_id, '|', g.keyword_id))          AS subject_pairs,
    COUNT(DISTINCT g.campaign_id)                                     AS campaigns,
    SUM(g.spend_per_day_28d)                                          AS spend_28,
    SUM(g.gp_per_day_28d)                                             AS gp_28,
    SUM(g.spend_per_day_7d)                                           AS spend_7,
    SUM(g.gp_per_day_7d)                                              AS gp_7,
    SUM(g.clicks_28d)                                                 AS clicks_28,
    SUM(g.orders_28d)                                                 AS orders_28,
    COUNTIF(g.spending_in_last_7d)                                    AS subjects_spending_in_last_7d,
    COUNTIF(g.judgeability <> 'HAS_BAR')                              AS unjudgeable_subjects,
    SUM(IF(g.judgeability <> 'HAS_BAR', g.spend_per_day_28d, 0))      AS unjudgeable_spend_28,
    COUNTIF(g.judgeability = 'NO_BAR_NO_FAMILY')                      AS subjects_with_no_family,
    SUM(IF(g.judgeability = 'NO_BAR_NO_FAMILY', g.spend_per_day_28d, 0)) AS no_family_spend_28,
    MAX(g.days_in_current_run)                                        AS longest_run_days,
    STRING_AGG(DISTINCT g.reason ORDER BY g.reason)                   AS reasons_present
  FROM grouped g
  GROUP BY g.reason_class
)
SELECT
  w.as_of,
  w.window_days,
  w.recent_days,
  agg.reason_class,
  agg.reasons_present,
  agg.subjects,
  agg.subject_pairs,
  agg.campaigns,
  agg.subjects_spending_in_last_7d,
  ROUND(agg.spend_28, 2)                                              AS spend_per_day_28d,
  ROUND(agg.gp_28, 2)                                                 AS gp_per_day_28d,
  ROUND(SAFE_DIVIDE(agg.gp_28, agg.spend_28), 4)                      AS gp_roas_28d,
  ROUND(agg.spend_7, 2)                                               AS spend_per_day_7d,
  ROUND(agg.gp_7, 2)                                                  AS gp_per_day_7d,
  ROUND(SAFE_DIVIDE(agg.gp_7, agg.spend_7), 4)                        AS gp_roas_7d,
  agg.clicks_28,                                                      -- clicks over the 28-day window
  agg.orders_28,                                                      -- orders over the 28-day window
  ROUND(100 * SAFE_DIVIDE(agg.spend_28, acct.a_spend_28), 3)          AS share_of_account_pct_28d,
  ROUND(100 * SAFE_DIVIDE(agg.spend_7,  acct.a_spend_7),  3)          AS share_of_account_pct_7d,
  ROUND(acct.a_spend_28, 2)                                           AS account_spend_per_day_28d,
  ROUND(acct.a_gp_28, 2)                                              AS account_gp_per_day_28d,
  ROUND(SAFE_DIVIDE(acct.a_gp_28, acct.a_spend_28), 4)                AS account_gp_roas_28d,
  ROUND(acct.a_spend_7, 2)                                            AS account_spend_per_day_7d,
  ROUND(SAFE_DIVIDE(acct.a_gp_7, acct.a_spend_7), 4)                  AS account_gp_roas_7d,
  agg.unjudgeable_subjects,
  ROUND(agg.unjudgeable_spend_28, 2)                                  AS unjudgeable_spend_per_day_28d,
  agg.subjects_with_no_family,
  ROUND(agg.no_family_spend_28, 2)                                    AS no_family_spend_per_day_28d,
  agg.longest_run_days,
  CONCAT(
    IF(agg.reason_class = '__ALL__',
       'Across the whole account, ',
       CONCAT('In the ', agg.reason_class, ' class, ')),
    CAST(agg.subjects AS STRING), ' spending subject(s) in ', CAST(agg.campaigns AS STRING),
    ' campaign(s) have no row in the Catalog\'s keyword state. They cost $',
    FORMAT('%.2f', agg.spend_28), '/day over the last ', CAST(w.window_days AS STRING),
    ' complete days — ', FORMAT('%.2f', 100 * SAFE_DIVIDE(agg.spend_28, acct.a_spend_28)),
    '% of the account\'s $', FORMAT('%.2f', acct.a_spend_28), '/day — and returned ',
    FORMAT('%.3f', SAFE_DIVIDE(agg.gp_28, agg.spend_28)),
    ' gross-profit dollars per ad dollar against the account\'s ',
    FORMAT('%.3f', SAFE_DIVIDE(acct.a_gp_28, acct.a_spend_28)), '. ',
    'In the last ', CAST(w.recent_days AS STRING), ' days the live figure is $',
    FORMAT('%.2f', agg.spend_7), '/day (',
    FORMAT('%.2f', 100 * SAFE_DIVIDE(agg.spend_7, acct.a_spend_7)), '% of the account), across ',
    CAST(agg.subjects_spending_in_last_7d AS STRING), ' subject(s) still spending — read that ',
    'beside the headline, because spend on a paused campaign is a tail and spend under the ',
    'sentinel is money leaving today. ',
    IF(agg.unjudgeable_subjects = 0,
       'Every subject here has a family bar it could be judged against, if a layer could see it.',
       CONCAT(CAST(agg.unjudgeable_subjects AS STRING), ' of them, carrying $',
              FORMAT('%.2f', agg.unjudgeable_spend_28),
              '/day, cannot be judged at all — no family bar, an exempt family, or too few clicks ',
              'to read — so no verdict is available for that money at any price. ')),
    ' Nothing here is a verdict: this is a census of subjects the Catalog has never met.'
  )                                                                   AS sentence,
  CURRENT_DATE('America/Los_Angeles')                                 AS computed_on
FROM agg
CROSS JOIN w
CROSS JOIN acct
ORDER BY IF(agg.reason_class = '__ALL__', 0, 1), spend_per_day_28d DESC, agg.reason_class;
