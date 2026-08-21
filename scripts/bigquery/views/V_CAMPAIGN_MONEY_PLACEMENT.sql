-- =============================================================================================
-- V_CAMPAIGN_MONEY_PLACEMENT — the top-down answer: is the advertising money in the right place?
--
-- WHAT ORI ASKED (2026-08-21): "per campaign check if the budget is ok — top down. How much of the
-- budget is on profitable or marginal campaigns and their spend, and how much is on not profitable
-- campaigns and their spend."
--
-- SO EVERY LINE CARRIES TWO DOLLAR FIGURES, NEVER ONE. Committed budget and delivered spend are
-- different questions in this account and they diverge in both directions at once — campaigns
-- overdeliver against the budget in force on a given day while, in aggregate, most committed budget
-- is never consumed. "How much budget sits on losers" and "how much money went to losers" therefore
-- have different answers, and Ori asked for both. Read them side by side on every row.
--
-- ---------------------------------------------------------------------------------------------
-- THE GOVERNING RULE: A CAMPAIGN IS JUDGED AGAINST ITS FAMILY'S MEASURED BAR, NEVER AGAINST 1.0.
--
-- Organic sales are measurable at FAMILY grain and are NOT attributable to a campaign. So the
-- campaign keeps being measured on ads-attributed gross profit per ad dollar — the only honest
-- measure at this grain — and what changes is the BAR it is held to: the halo-adjusted breakeven
-- that V_FAMILY_BAR computes per family and SP_SNAPSHOT_FAMILY_BAR lands, already exploded to
-- campaign grain, in T_FAMILY_BAR. A family whose ads-attributed return sits below 1.0 while its
-- total return sits at or above 1.0 is paying its way through organic sales it earned; judged flat,
-- every one of its campaigns reads as a loser and cutting them takes the family down with them.
-- Whether that is happening today is a MEASUREMENT, not a claim for this header. Take it:
--   SELECT family, ads_net_roas, total_net_roas, keyword_bar, bar_exempt
--   FROM `onyga-482313.OI.T_FAMILY_BAR` GROUP BY 1,2,3,4,5 ORDER BY ads_net_roas;
-- And the cost of getting it wrong, measured on the deployed view against a flat test:
--   SELECT COUNTIF(gp_roas_window < 1.0) AS losers_flat,
--          ROUND(100*SUM(IF(gp_roas_window < 1.0, spend_window, 0))/SUM(spend_window),1) AS pct_flat,
--          COUNTIF(bucket_code = 'UNPROFITABLE') AS losers_barred,
--          ROUND(100*SUM(IF(bucket_code='UNPROFITABLE', spend_window,0))/SUM(spend_window),1) AS pct_barred
--   FROM `onyga-482313.OI.V_CAMPAIGN_MONEY_PLACEMENT` WHERE row_kind = 'CAMPAIGN' AND spend_window > 0;
--
-- READ THE TABLE, NEVER THE VIEW. V_FAMILY_BAR inlines V_FAMILY_PNL and sits at the planner
-- ceiling. T_FAMILY_BAR is its nightly snapshot and is the only safe read from here.
--
-- THIS IS T_FAMILY_BAR'S FIRST CONSUMER. Until this view shipped, nothing in the warehouse read
-- that table, and SP_SNAPSHOT_FAMILY_BAR's header, its OPTIONS description and the matching
-- config.yaml clauses all said so. Those statements were corrected in the same commit as this file.
-- Note what this view does NOT establish: the halo is still not priced into any bid. This is a
-- reporting read of the bar, not the engine wiring it into a decision.
--
-- ---------------------------------------------------------------------------------------------
-- THREE POPULATIONS THAT MUST NOT BE SWEPT INTO A PROFIT VERDICT.
--
-- 1. LAUNCHES ARE NOT JUDGED ON PROFIT. Families in the INVEST book are judged on adherence to the
--    sanction and on organic trajectory in months 0-3, never on profitability (Ori 2026-08-19).
--    Their campaigns get their own bucket, described by the sanction, and this view goes further
--    than naming them: on a LAUNCH row every profitability field — the bar, the return, the band,
--    the shortfall, the gross profit itself and the verdict — is NULL. Gross profit is suppressed
--    because gross profit divided by spend IS the verdict, one division away, and a suppression a
--    reader can undo is not a suppression. That is asserted, not merely intended.
--
-- 2. UNMAPPED SPEND MUST APPEAR, NOT VANISH. A share of account spend resolves to no family — the
--    'Unknown' advertised-ASIN key, largely Sponsored Brands — so it has no bar and cannot be
--    judged. It gets a published line with its dollars. The founding complaint behind this whole
--    design was a total that lied by omission; a total that silently drops unjudgeable spend
--    repeats it. The line also says the condition is FIXABLE rather than permanent: the campaign
--    names carry the family in plain text and DE_CAMPAIGN_FAMILY already exists to override, so
--    mapping these campaigns brings the money under a bar. Whether the bucket is growing is a
--    measurement — compare its spend over a short and a long window to see.
--
-- 3. TOO LITTLE VOLUME IS A WITHHOLDING, NOT A LOSS. A campaign with a handful of clicks cannot be
--    classified, and letting "unmeasured" fall through into "losing" is the exact failure this
--    design exists to end. Those campaigns get their own bucket and carry no verdict.
--
-- AND TWO MORE THE RECONCILIATION FORCED INTO EXISTENCE. Neither is a judgement; both are here
-- because the alternative is money disappearing off the bottom of the page.
--
-- 4. STILL BUDGETED HERE, ALREADY ENDED AT AMAZON. Some campaigns carry state ENABLED in the
--    change-log while their serving status reads ENDED. They hold real committed budget that can
--    never be delivered. The convention elsewhere in the repo is to filter them out
--    (serving_status IN ('CAMPAIGN_STATUS_ENABLED','CAMPAIGN_OUT_OF_BUDGET'), as
--    V_CAMPAIGN_CAP_STATE and V_LAUNCH_POPULATION do) and that is right for an engine, which must
--    not act on them. It is wrong for a top-down budget answer, which would then drop their budget
--    without saying so and quietly inflate the parked-budget line. They are separated into their
--    own bucket instead: excluded from every judgement, still counted in the budget total.
--
-- 5. SPENT IN THE WINDOW, NO LONGER RUNNING. The universe of BUDGET and the universe of SPEND are
--    not the same set. Campaigns paused or archived during the window spent real money and hold no
--    budget today. A view restricted to live campaigns silently drops that spend — the same
--    omission failure as the unmapped bucket, and larger. They get a line: zero budget, their real
--    spend. This is what makes the account spend total equal every dollar the account spent.
--
-- ---------------------------------------------------------------------------------------------
-- THE BAND AROUND THE BAR IS ONE DECLARED CONSTANT, AND IT IS THE MEASURE'S OWN MOVEMENT.
--
-- A campaign either clears its bar, misses it, or sits close enough that the evidence does not say.
-- The width of "close enough" is not a taste. Gross profit per order varies far less than the
-- COUNT of orders, so the sampling error in a campaign's return is dominated by Poisson noise in
-- orders: one standard error is the return divided by the square root of orders. That is a model,
-- so it was CHECKED against this account rather than assumed. Split the window into two halves and
-- compare each campaign's return across them; two independent halves should disagree by about
-- sqrt(2)/sqrt(orders) in relative terms. Run it and see the curve fall:
--   WITH wm AS (SELECT DATE_SUB(MAX(date), INTERVAL 1 DAY) e FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
--        win AS (SELECT DATE_SUB(e, INTERVAL 89 DAY) s, e FROM wm),
--        a AS (SELECT CAST(f.campaign_id AS STRING) cid,
--                     IF(f.date <= DATE_SUB(w.e, INTERVAL 45 DAY),'H1','H2') half,
--                     SUM(f.Ads_cost) spend, SUM(f.Ads_clicks) clicks, SUM(f.Ads_orders) orders,
--                     SUM(f.GROSS_PROFIT) gp
--              FROM `onyga-482313.OI.FACT_AMAZON_ADS` f, win w
--              WHERE f.date BETWEEN w.s AND w.e GROUP BY 1,2),
--        p AS (SELECT cid, MAX(IF(half='H1',clicks,NULL)) c1, MAX(IF(half='H2',clicks,NULL)) c2,
--                     MAX(IF(half='H1',orders,NULL)) o1, MAX(IF(half='H2',orders,NULL)) o2,
--                     SAFE_DIVIDE(MAX(IF(half='H1',gp,NULL)),MAX(IF(half='H1',spend,NULL))) r1,
--                     SAFE_DIVIDE(MAX(IF(half='H2',gp,NULL)),MAX(IF(half='H2',spend,NULL))) r2
--              FROM a GROUP BY cid)
--   SELECT CASE WHEN LEAST(c1,c2)<50 THEN 'a. <50' WHEN LEAST(c1,c2)<100 THEN 'b. 50-99'
--               WHEN LEAST(c1,c2)<200 THEN 'c. 100-199' WHEN LEAST(c1,c2)<400 THEN 'd. 200-399'
--               WHEN LEAST(c1,c2)<800 THEN 'e. 400-799' ELSE 'f. 800+' END bucket,
--          COUNT(*) n,
--          ROUND(AVG(ABS(r1-r2)/NULLIF((r1+r2)/2,0)),3) measured_gap,
--          ROUND(AVG(SQRT(2)/SQRT(NULLIF(LEAST(o1,o2),0))),3) poisson_prediction
--   FROM p WHERE r1 IS NOT NULL AND r2 IS NOT NULL AND c1>0 AND c2>0 GROUP BY 1 ORDER BY 1;
--
-- WHAT THAT CURVE LICENSES, AND WHAT IT DOES NOT. The measured gap and the prediction track each
-- other closely at the thin end and at the fat end, which is what licenses the model; the middle
-- buckets hold only a handful of campaigns each and their agreement should not be leaned on. Do NOT
-- quote the middle of this curve as evidence.
--
-- SO band_sigmas = 1.0 — ONE standard error, which makes the band exactly as wide as the movement
-- the measure was just shown to have. Not 0.5: a half-width band convicts campaigns of losing on a
-- gap smaller than the movement the same data exhibits between adjacent windows, which is convicting
-- on noise. Not 2.0: two standard errors is the width for a formal test at conventional confidence,
-- and it swallows most of the money into "cannot tell", which answers Ori's question with a shrug.
-- One standard error is the honest reading of "the difference is bigger than the way this number
-- ordinarily moves". Its cost is visible rather than argued — this query prices every choice:
--   SELECT z, COUNTIF(v='CLEARS') clears, COUNTIF(v='MISSES') misses, COUNTIF(v='CLOSE') too_close,
--          ROUND(SUM(IF(v='MISSES', spend_window, 0)),0) spend_condemned
--   FROM (SELECT z, spend_window,
--                CASE WHEN gp_roas_window - z*band_half_width/1.0 >= keyword_bar THEN 'CLEARS'
--                     WHEN gp_roas_window + z*band_half_width/1.0 <  keyword_bar THEN 'MISSES'
--                     ELSE 'CLOSE' END v
--         FROM `onyga-482313.OI.V_CAMPAIGN_MONEY_PLACEMENT`, UNNEST([0.5,1.0,1.5,2.0]) z
--         WHERE row_kind='CAMPAIGN' AND keyword_bar IS NOT NULL AND bucket_code <> 'TOO_SMALL')
--   GROUP BY z ORDER BY z;
--
-- THE BAND IS PER CAMPAIGN, WHICH IS WHY IT NEEDS NO TUNING. A flat percentage band would be too
-- wide for a campaign with thousands of orders and too narrow for one with twelve. This band
-- narrows on its own as a campaign accumulates volume, so the verdict sharpens with the evidence
-- and nobody has to revisit a number.
--
-- ---------------------------------------------------------------------------------------------
-- THE VOLUME FLOOR IS DERIVED, NOT CHOSEN, AND THE WINDOW IS PART OF IT.
--
-- volume_floor_clicks = 226 over the 90-day window. It is the click count at which a campaign is
-- expected to produce nine orders at the account's own measured conversion rate, and nine expected
-- orders puts the relative sampling error on its return at about a third — the point past which a
-- verdict stops being a reading and starts being a coin. The account's conversion rate is a
-- measurement, so take it rather than trusting this line:
--   WITH wm AS (SELECT DATE_SUB(MAX(date), INTERVAL 1 DAY) e FROM `onyga-482313.OI.FACT_AMAZON_ADS`)
--   SELECT SUM(Ads_orders) orders, SUM(Ads_clicks) clicks,
--          SAFE_DIVIDE(SUM(Ads_orders), SUM(Ads_clicks)) cvr,
--          9 / SAFE_DIVIDE(SUM(Ads_orders), SUM(Ads_clicks)) AS clicks_for_nine_orders
--   FROM `onyga-482313.OI.FACT_AMAZON_ADS`, wm
--   WHERE date BETWEEN DATE_SUB(wm.e, INTERVAL 89 DAY) AND wm.e;
--
-- AFFORDABILITY IS THE TEST THAT ACTUALLY PICKS THE NUMBER, because a floor that withholds a
-- verdict on a large share of the money is not a floor, it is a refusal to answer. Price the whole
-- ladder before changing it:
--   WITH wm AS (SELECT DATE_SUB(MAX(date), INTERVAL 1 DAY) e FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
--        c AS (SELECT clicks_window, spend_window, budget_per_day
--              FROM `onyga-482313.OI.V_CAMPAIGN_MONEY_PLACEMENT`
--              WHERE row_kind='CAMPAIGN' AND bucket_code NOT IN ('STOPPED','NOT_SERVING'))
--   SELECT fl, COUNTIF(clicks_window < fl) withheld,
--          ROUND(100*SUM(IF(clicks_window<fl,spend_window,0))/SUM(spend_window),2) pct_spend,
--          ROUND(100*SUM(IF(clicks_window<fl,budget_per_day,0))/SUM(budget_per_day),2) pct_budget
--   FROM c CROSS JOIN UNNEST([50,101,151,226,300,402,629,1000]) fl GROUP BY fl ORDER BY fl;
-- The shape it returns is a knee: the spend withheld rises slowly up to the floor and steeply past
-- it, while looser floors buy back almost no money and leave verdicts at fifty per cent error.
--
-- THE SAME FLOOR ON A SHORTER WINDOW IS NOT THE SAME FLOOR. Applied to 28 days it withholds several
-- times the spend, because the clicks simply are not there yet. If you shorten window_days you must
-- re-derive the floor, and you will not like what it costs. Publish both together, always — they
-- ride on every row of this view as volume_floor_clicks and window_days for exactly that reason.
--
-- ---------------------------------------------------------------------------------------------
-- WINDOW. 90 complete days ending at the ads watermark minus one day. Day-1 ads data is only about
-- 88-90% loaded, so the last day is dropped. The length matches the settled window the family bars
-- are themselves measured on, which matters: a campaign verdict computed on a short window and
-- tested against a bar measured on a long one is comparing two different things. The two windows
-- are not identical — the bars end at the ORDERS watermark and this one ends behind the ADS feed —
-- so they can differ by a day or two at the edge, which is a real and accepted approximation.
--
-- BUDGET IS READ AS OF TODAY, AND THAT IS WHY IT IS NEVER APPLIED BACKWARDS. A campaign's daily
-- budget moves roughly weekly in this account, so today's budget is a point-in-time reading and
-- multiplying it across ninety days of history would be wrong by a large and unknowable amount.
-- The two figures on every row are therefore honest about what they are: budget_per_day is what is
-- committed TODAY, spend_window is what was actually delivered over the window, and spend_per_day
-- is that spend averaged over the window so the reader can hold the two beside each other. There is
-- deliberately no utilisation percentage in any sentence, because a ratio of today's budget to
-- history's spend is the kind of number that gets quoted as if it meant something.
--
-- THE SENTENCES ARE THE DELIVERABLE. Plain English, read aloud before shipping: no rule names, no
-- formulas, no metric codes, no engine internals. If you add a branch, read it out.
--
-- SUPERSEDES V_COVERAGE_CAMPAIGN_PROFIT7D, which answers the same question wrongly in four ways at
-- once: a flat 1.0 bar, a seven-day window, no volume floor and no launch exemption.
--
-- WHAT THIS VIEW IS ACCURATE TO. FACT_AMAZON_ADS is the consolidated house source and the only one
-- covering both channels and carrying gross profit, which is what makes this measure identical to
-- the one the bars were calibrated against. It does not reconcile to the per-channel Amazon reports
-- to the cent — it runs about a percent apart from them. So a bucket total here is good to roughly
-- a percent, and no threshold should ever be set tight enough for that to matter. Separately, where
-- a product's cost of goods is tier-imputed rather than real, the gross profit inside the fact
-- inherits that artifact and so does the campaign's return; the fix for such a row is the cost of
-- goods, never the bar and never the verdict.
--
-- ACCEPTANCE ASSERTIONS RUN AGAINST THE DEPLOYED VIEW: scripts/bigquery/tests/V_CAMPAIGN_MONEY_PLACEMENT_acceptance.sql
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_MONEY_PLACEMENT` AS
WITH
-- ---------------------------------------------------------------------------------------------
-- THE DECLARED CONSTANTS. Every number this view's judgement rests on is named here, once. Each
-- one is true because it was derived and someone chose it; the derivations are in the header, with
-- the query that re-takes each measurement. Changing one of these changes the answer; nothing else
-- in this file does.
-- ---------------------------------------------------------------------------------------------
k AS (
  SELECT
    90    AS window_days,          -- complete days of ads history the verdict is measured on. Matches
                                   -- the settled window the family bars are measured on.
    1     AS watermark_lag_days,   -- days dropped off the end of the ads feed. Day-1 is ~88-90% loaded.
    226   AS volume_floor_clicks,  -- below this many clicks in the window, no verdict. Derived: the
                                   -- clicks that produce nine expected orders at the account's own
                                   -- conversion rate, which is a third relative error on the return.
    9     AS floor_expected_orders,-- the orders the floor is derived to expect. Published so the
                                   -- floor and its reason can never drift apart.
    1.0   AS band_sigmas           -- half-width of "too close to call", in standard errors of the
                                   -- campaign's own return. One, because one standard error is the
                                   -- movement the measure was measured to have between windows.
),
-- the window, anchored on the ads feed rather than on a calendar
wm AS (
  SELECT DATE_SUB(MAX(f.date), INTERVAL k.watermark_lag_days DAY) AS window_end
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f, k
  GROUP BY k.watermark_lag_days
),
win AS (
  SELECT DATE_SUB(wm.window_end, INTERVAL (k.window_days - 1) DAY) AS window_start, wm.window_end
  FROM wm, k
),
-- ---------------------------------------------------------------------------------------------
-- THE THREE INPUTS.
-- ---------------------------------------------------------------------------------------------
-- 1. what was actually delivered, per campaign, over the window
fact_window AS (
  SELECT
    CAST(f.campaign_id AS STRING) AS campaign_id,
    MAX(f.campaign_name)          AS fact_campaign_name,   -- deterministic: MAX is a total function
    MAX(f.campaign_type)          AS fact_campaign_type,
    -- MONEY IS CARRIED AS EXACT DECIMAL, NOT AS FLOAT, AND THAT IS A CORRECTNESS REQUIREMENT
    -- RATHER THAN A STYLE. A FLOAT64 sum is not associative: BigQuery adds the shards in whatever
    -- order they finish, so two uncached runs of the same query differ in the last bits. That is
    -- invisible until a derived figure lands on a rounding boundary — a spend of 736.65 divided by
    -- 90 days is 8.185, and a sentence built from a float reads 8.18 on one run and 8.19 on the
    -- next. Both were observed here before this cast existed. NUMERIC addition is exact and
    -- order-independent, so every dollar quantity in this view is NUMERIC from the source
    -- aggregate through to the published column, and the sentences are stable by construction.
    ROUND(SUM(CAST(f.Ads_cost AS NUMERIC)), 2)     AS spend_window,
    SUM(f.Ads_clicks)             AS clicks_window,
    SUM(f.Ads_orders)             AS orders_window,
    ROUND(SUM(CAST(f.GROSS_PROFIT AS NUMERIC)), 2) AS gross_profit_window
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f, win w
  WHERE f.date BETWEEN w.window_start AND w.window_end
  GROUP BY 1
),
-- 2. what is committed today. Every campaign the change log calls ENABLED, INCLUDING the ones whose
--    serving status says Amazon has already ended them — those are separated by bucket below, not
--    dropped here, because dropping them drops their budget out of the account total.
dim_current AS (
  SELECT
    CAST(c.campaign_id AS STRING) AS campaign_id,
    c.campaign_name,
    c.campaign_type,
    c.serving_status,
    CAST(c.daily_budget AS NUMERIC) AS budget_per_day
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` c
  WHERE c.campaign_state = 'ENABLED'
  -- one row per campaign, picked by a TOTAL ordering over the whole row so no two fields can ever
  -- be paired from different rows
  QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(c.campaign_id AS STRING)
                             ORDER BY TO_JSON_STRING(c)) = 1
),
-- 3. the bar, already at campaign grain, from the nightly snapshot. Same total-ordering dedupe.
bar AS (
  SELECT
    b.campaign_id,
    b.family,
    b.book,
    b.keyword_bar,
    b.bar_exempt
  FROM `onyga-482313.OI.T_FAMILY_BAR` b
  QUALIFY ROW_NUMBER() OVER (PARTITION BY b.campaign_id ORDER BY TO_JSON_STRING(b)) = 1
),
-- ---------------------------------------------------------------------------------------------
-- THE UNIVERSE. A FULL OUTER JOIN, on purpose: the set that holds budget and the set that spent
-- money are not the same set, and either side alone loses real dollars off the bottom of the page.
-- ---------------------------------------------------------------------------------------------
universe AS (
  SELECT
    COALESCE(d.campaign_id, f.campaign_id)                     AS campaign_id,
    COALESCE(d.campaign_name, f.fact_campaign_name)            AS campaign_name,
    COALESCE(d.campaign_type, f.fact_campaign_type)            AS campaign_type,
    d.serving_status,
    COALESCE(d.budget_per_day, NUMERIC '0')                    AS budget_per_day,
    COALESCE(f.spend_window, NUMERIC '0')                      AS spend_window,
    COALESCE(f.clicks_window, 0)                               AS clicks_window,
    COALESCE(f.orders_window, 0)                               AS orders_window,
    -- gross profit is deliberately NOT coalesced to zero: a campaign with no rows earned no
    -- measurement, not zero profit, and letting unmeasured read as worst-case is the failure this
    -- whole design exists to end. It stays NULL and the volume floor catches the campaign.
    f.gross_profit_window,
    d.campaign_id IS NOT NULL                                  AS holds_budget_today,
    COALESCE(d.serving_status IN ('CAMPAIGN_STATUS_ENABLED','CAMPAIGN_OUT_OF_BUDGET'), FALSE) AS can_serve
  FROM dim_current d
  FULL OUTER JOIN fact_window f USING (campaign_id)
),
-- ---------------------------------------------------------------------------------------------
-- THE VERDICT. Return against the campaign's OWN family bar, with a band one standard error wide.
-- ---------------------------------------------------------------------------------------------
scored AS (
  SELECT
    u.*,
    b.family,
    b.book,
    b.keyword_bar,
    b.bar_exempt,
    SAFE_DIVIDE(u.gross_profit_window, u.spend_window) AS gp_roas_window,
    -- one standard error of the campaign's own return: the return divided by the square root of its
    -- order count. GREATEST(orders, 1) keeps the arithmetic defined at zero orders; at zero orders
    -- the return is zero anyway, so the band collapses and the campaign reads as short of its bar,
    -- which is the right answer when the clicks were there and the orders were not.
    k.band_sigmas * SAFE_DIVIDE(SAFE_DIVIDE(u.gross_profit_window, u.spend_window),
                                SQRT(GREATEST(u.orders_window, 1))) AS band_half_width
  FROM universe u
  LEFT JOIN bar b USING (campaign_id)
  CROSS JOIN k
),
bucketed AS (
  SELECT
    s.*,
    CASE
      -- the two accounting lines first: neither is a judgement, both exist so money cannot vanish
      WHEN NOT s.holds_budget_today             THEN 'STOPPED'
      WHEN NOT s.can_serve                      THEN 'NOT_SERVING'
      -- no family means no bar, so there is nothing to judge against
      WHEN s.keyword_bar IS NULL                THEN 'UNJUDGEABLE'
      -- launches are judged on their sanction and never on profit, so they take precedence over
      -- every profitability branch below, including the volume floor: "too little traffic to judge
      -- its profit" is still a sentence about profit.
      WHEN s.bar_exempt                         THEN 'LAUNCH'
      WHEN s.clicks_window < k.volume_floor_clicks THEN 'TOO_SMALL'
      WHEN s.gp_roas_window - s.band_half_width >= s.keyword_bar THEN 'PROFITABLE'
      WHEN s.gp_roas_window + s.band_half_width <  s.keyword_bar THEN 'UNPROFITABLE'
      ELSE 'MARGINAL'
    END AS bucket_code
  FROM scored s CROSS JOIN k
),
-- suppression happens ONCE, here, so no downstream expression can reintroduce a suppressed field
campaign_base AS (
  SELECT
    c.campaign_id, c.campaign_name, c.campaign_type, c.family, c.book, c.bucket_code,
    c.budget_per_day, c.spend_window, c.clicks_window, c.orders_window,
    c.serving_status, c.can_serve, c.holds_budget_today,
    IF(c.bucket_code = 'LAUNCH', NULL, c.gross_profit_window) AS gross_profit_window,
    IF(c.bucket_code = 'LAUNCH', NULL, c.gp_roas_window)      AS gp_roas_window,
    IF(c.bucket_code = 'LAUNCH', NULL, c.keyword_bar)         AS keyword_bar,
    IF(c.bucket_code = 'LAUNCH', NULL, c.band_half_width)     AS band_half_width,
    IF(c.bucket_code IN ('PROFITABLE','MARGINAL','UNPROFITABLE'),
       ROUND(c.spend_window * CAST(c.keyword_bar AS NUMERIC) - c.gross_profit_window, 2),
       NULL) AS shortfall_window,
    CASE c.bucket_code
      WHEN 'PROFITABLE'   THEN 'Earning more than its family needs'
      WHEN 'MARGINAL'     THEN 'Too close to call'
      WHEN 'UNPROFITABLE' THEN 'Earning less than its family needs'
      ELSE NULL
    END AS profit_verdict
  FROM bucketed c
),
totals AS (
  SELECT
    SUM(budget_per_day) AS acct_budget_per_day,
    SUM(spend_window)   AS acct_spend_window,
    COUNT(*)            AS acct_campaigns
  FROM campaign_base
),
bucket_agg AS (
  SELECT
    bucket_code,
    COUNT(*)                                     AS n_campaigns,
    SUM(budget_per_day)                          AS budget_per_day,
    SUM(spend_window)                            AS spend_window,
    SUM(clicks_window)                           AS clicks_window,
    SUM(orders_window)                           AS orders_window,
    IF(bucket_code = 'LAUNCH', NULL, SUM(gross_profit_window)) AS gross_profit_window,
    IF(bucket_code = 'LAUNCH', NULL,
       SAFE_DIVIDE(SUM(gross_profit_window), SUM(spend_window)))               AS gp_roas_window,
    IF(bucket_code IN ('PROFITABLE','MARGINAL','UNPROFITABLE'),
       SUM(shortfall_window), NULL)              AS shortfall_window,
    COUNTIF(campaign_type = 'SB')                AS n_sponsored_brands,
    -- the biggest single shortfall in the bucket, picked by a TOTAL ordering (dollars, then name,
    -- then id) so the sentence names the same campaign on every run
    ARRAY_AGG(campaign_name ORDER BY shortfall_window DESC, campaign_name, campaign_id LIMIT 1)[SAFE_OFFSET(0)]
                                                 AS worst_campaign_name
  FROM campaign_base
  GROUP BY bucket_code
),
-- ---------------------------------------------------------------------------------------------
-- THE SPINE. Every bucket gets a row whether or not a campaign is in it today, so a bucket
-- emptying out reads as "no campaigns" rather than as a line that quietly disappeared.
-- ---------------------------------------------------------------------------------------------
spine AS (
  SELECT * FROM UNNEST([
    STRUCT('PROFITABLE'   AS bucket_code, 1 AS sort_key, 'Earning more than its family needs' AS bucket),
    STRUCT('MARGINAL',     2, 'Too close to call'),
    STRUCT('UNPROFITABLE', 3, 'Earning less than its family needs'),
    STRUCT('LAUNCH',       4, 'A launch the account decided to pay for'),
    STRUCT('TOO_SMALL',    5, 'Too little traffic to judge'),
    STRUCT('UNJUDGEABLE',  6, 'No family attached, so nothing to judge it against'),
    STRUCT('NOT_SERVING',  7, 'Still budgeted here, already ended at Amazon'),
    STRUCT('STOPPED',      8, 'Spent during the window, no longer running')
  ])
)
-- ---------------------------------------------------------------------------------------------
-- ROW 1: THE ACCOUNT. Published so a reader can see that nothing was dropped.
-- ---------------------------------------------------------------------------------------------
SELECT
  'ACCOUNT'                                   AS row_kind,
  0                                           AS sort_key,
  'ACCOUNT'                                   AS bucket_code,
  'Everything, so the lines below can be checked against it' AS bucket,
  CAST(NULL AS STRING)                        AS campaign_id,
  CAST(NULL AS STRING)                        AS campaign_name,
  CAST(NULL AS STRING)                        AS campaign_type,
  CAST(NULL AS STRING)                        AS family,
  CAST(NULL AS STRING)                        AS book,
  t.acct_campaigns                            AS n_campaigns,
  t.acct_budget_per_day                       AS budget_per_day,
  NUMERIC '100'                               AS pct_of_account_budget,
  t.acct_spend_window                         AS spend_window,
  ROUND(t.acct_spend_window / k.window_days, 2) AS spend_per_day,
  NUMERIC '100'                               AS pct_of_account_spend,
  CAST(NULL AS INT64)                         AS clicks_window,
  CAST(NULL AS INT64)                         AS orders_window,
  CAST(NULL AS NUMERIC)                       AS gross_profit_window,
  CAST(NULL AS NUMERIC)                       AS gp_roas_window,
  CAST(NULL AS FLOAT64)                       AS keyword_bar,
  CAST(NULL AS FLOAT64)                       AS band_half_width,
  CAST(NULL AS NUMERIC)                       AS shortfall_window,
  CAST(NULL AS STRING)                        AS profit_verdict,
  FORMAT(
    'Over the ninety days ending %s the account spent %s on advertising. Today it holds %s a day of committed budget. Every line below adds back to those two numbers, so nothing has been left out.',
    FORMAT_DATE('%-d %B', w.window_end),
    FORMAT('$%\'.0f', t.acct_spend_window),
    FORMAT('$%\'.0f', t.acct_budget_per_day)
  )                                           AS sentence,
  w.window_start, w.window_end, k.window_days,
  CURRENT_DATE('America/Los_Angeles')         AS budget_as_of,
  k.volume_floor_clicks, k.band_sigmas
FROM totals t, win w, k

UNION ALL
-- ---------------------------------------------------------------------------------------------
-- ROWS 2..9: THE BUCKETS. THESE ARE THE ANSWER.
-- ---------------------------------------------------------------------------------------------
SELECT
  'BUCKET'                                    AS row_kind,
  sp.sort_key,
  sp.bucket_code,
  sp.bucket,
  CAST(NULL AS STRING)                        AS campaign_id,
  CAST(NULL AS STRING)                        AS campaign_name,
  CAST(NULL AS STRING)                        AS campaign_type,
  CAST(NULL AS STRING)                        AS family,
  CAST(NULL AS STRING)                        AS book,
  COALESCE(g.n_campaigns, 0)                  AS n_campaigns,
  COALESCE(g.budget_per_day, NUMERIC '0')     AS budget_per_day,
  ROUND(100 * SAFE_DIVIDE(COALESCE(g.budget_per_day, 0), t.acct_budget_per_day), 1) AS pct_of_account_budget,
  COALESCE(g.spend_window, NUMERIC '0')       AS spend_window,
  ROUND(COALESCE(g.spend_window, NUMERIC '0') / k.window_days, 2) AS spend_per_day,
  ROUND(100 * SAFE_DIVIDE(COALESCE(g.spend_window, 0), t.acct_spend_window), 1) AS pct_of_account_spend,
  g.clicks_window, g.orders_window,
  g.gross_profit_window,
  ROUND(g.gp_roas_window, 4)                  AS gp_roas_window,
  CAST(NULL AS FLOAT64)                       AS keyword_bar,
  CAST(NULL AS FLOAT64)                       AS band_half_width,
  g.shortfall_window,
  CAST(NULL AS STRING)                        AS profit_verdict,
  -- ═══ THE SENTENCES. READ EVERY ONE ALOUD BEFORE YOU DEPLOY A CHANGE TO IT. ═══════════════════
  CASE
    WHEN COALESCE(g.n_campaigns, 0) = 0 THEN
      FORMAT('No campaigns are in this group over the ninety days ending %s.', FORMAT_DATE('%-d %B', w.window_end))

    WHEN sp.bucket_code = 'PROFITABLE' THEN
      FORMAT('%d campaigns are earning more than their family needs. They hold %s a day of budget and spent %s over the ninety days ending %s, which is %s a day — %s of the budget and %s of the money. This is the part of the account that is working, and it is the first place to put more money.',
        g.n_campaigns, FORMAT('$%\'.0f', g.budget_per_day), FORMAT('$%\'.0f', g.spend_window),
        FORMAT_DATE('%-d %B', w.window_end), FORMAT('$%\'.0f', g.spend_window / k.window_days),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.budget_per_day, t.acct_budget_per_day)),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.spend_window, t.acct_spend_window)))

    WHEN sp.bucket_code = 'MARGINAL' THEN
      FORMAT('%d campaigns are too close to call. What they earn sits inside the ordinary movement of the measure, so the evidence does not yet say whether they are above or below what their family needs. They hold %s a day of budget and spent %s, which is %s a day — %s of the budget and %s of the money. Leave them where they are and let them gather more traffic.',
        g.n_campaigns, FORMAT('$%\'.0f', g.budget_per_day), FORMAT('$%\'.0f', g.spend_window),
        FORMAT('$%\'.0f', g.spend_window / k.window_days),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.budget_per_day, t.acct_budget_per_day)),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.spend_window, t.acct_spend_window)))

    WHEN sp.bucket_code = 'UNPROFITABLE' THEN
      FORMAT('%d campaigns are earning less than their family needs, by more than the measure moves on its own. They hold %s a day of budget and spent %s, which is %s a day — %s of the budget and %s of the money. Across the window they came up %s short of what their families needed, and the largest single piece of that is %s. Lowering their bids or narrowing what they buy recovers that money; switching them off also gives up the sales that came with it.',
        g.n_campaigns, FORMAT('$%\'.0f', g.budget_per_day), FORMAT('$%\'.0f', g.spend_window),
        FORMAT('$%\'.0f', g.spend_window / k.window_days),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.budget_per_day, t.acct_budget_per_day)),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.spend_window, t.acct_spend_window)),
        FORMAT('$%\'.0f', g.shortfall_window), g.worst_campaign_name)

    WHEN sp.bucket_code = 'LAUNCH' THEN
      FORMAT('%d campaigns belong to families the account has deliberately decided to invest in. They hold %s a day of budget and spent %s, which is %s a day — %s of the budget and %s of the money. They are judged on whether they are spending at the rate that was agreed and on whether organic sales are climbing, never on what they earn, so no profit figure is shown for them anywhere on these rows.',
        g.n_campaigns, FORMAT('$%\'.0f', g.budget_per_day), FORMAT('$%\'.0f', g.spend_window),
        FORMAT('$%\'.0f', g.spend_window / k.window_days),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.budget_per_day, t.acct_budget_per_day)),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.spend_window, t.acct_spend_window)))

    WHEN sp.bucket_code = 'TOO_SMALL' THEN
      FORMAT('%d campaigns have not had enough traffic to judge. Below %d clicks in ninety days, what a campaign earns swings by more than a third from one stretch of days to the next, so any verdict on them would be noise. They hold %s a day of budget — %s of the total — and spent only %s, which is %s of the money. Most of that budget is sitting unused rather than being lost, and the way to settle these campaigns is to give a few of them enough traffic to read.',
        g.n_campaigns, k.volume_floor_clicks, FORMAT('$%\'.0f', g.budget_per_day),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.budget_per_day, t.acct_budget_per_day)),
        FORMAT('$%\'.0f', g.spend_window),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.spend_window, t.acct_spend_window)))

    WHEN sp.bucket_code = 'UNJUDGEABLE' THEN
      FORMAT('%d campaigns are not attached to any family, so there is nothing to judge them against. They hold %s a day of budget and spent %s — %s of the budget and %s of the money. %s, whose sales come back to us without a product attached. This is fixable rather than permanent: naming a family for each one on the campaign mapping screen brings the money under a bar.',
        g.n_campaigns, FORMAT('$%\'.0f', g.budget_per_day), FORMAT('$%\'.0f', g.spend_window),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.budget_per_day, t.acct_budget_per_day)),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.spend_window, t.acct_spend_window)),
        -- the channel count is COMPUTED, never asserted: if the mix changes the sentence changes
        IF(g.n_sponsored_brands = g.n_campaigns,
           'Every one of them is a Sponsored Brands campaign',
           FORMAT('%d of them are Sponsored Brands campaigns', g.n_sponsored_brands)))

    WHEN sp.bucket_code = 'NOT_SERVING' THEN
      FORMAT('%d campaigns still carry budget here and Amazon has already ended them. They hold %s a day — %s of the budget — and %s, because they cannot run. That budget is not being wasted, it is simply not real, and clearing it makes the budget figure mean what it says.',
        g.n_campaigns, FORMAT('$%\'.0f', g.budget_per_day),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.budget_per_day, t.acct_budget_per_day)),
        IF(g.spend_window > 0, FORMAT('spent %s over the window', FORMAT('$%\'.0f', g.spend_window)),
                               'spent nothing over the window'))

    WHEN sp.bucket_code = 'STOPPED' THEN
      FORMAT('%d campaigns spent money inside the window and are no longer running. They hold no budget today and spent %s — %s of the money. They are here so the total covers every dollar the account spent, not only the dollars still under management.',
        g.n_campaigns, FORMAT('$%\'.0f', g.spend_window),
        FORMAT('%.0f%%', 100 * SAFE_DIVIDE(g.spend_window, t.acct_spend_window)))
  END                                         AS sentence,
  w.window_start, w.window_end, k.window_days,
  CURRENT_DATE('America/Los_Angeles')         AS budget_as_of,
  k.volume_floor_clicks, k.band_sigmas
FROM spine sp
LEFT JOIN bucket_agg g USING (bucket_code)
CROSS JOIN totals t
CROSS JOIN win w
CROSS JOIN k

UNION ALL
-- ---------------------------------------------------------------------------------------------
-- ROWS 10..n: THE CAMPAIGNS, so any bucket can be opened.
-- ---------------------------------------------------------------------------------------------
SELECT
  'CAMPAIGN'                                  AS row_kind,
  sp.sort_key,
  c.bucket_code,
  sp.bucket,
  c.campaign_id, c.campaign_name, c.campaign_type, c.family, c.book,
  1                                           AS n_campaigns,
  c.budget_per_day,
  ROUND(100 * SAFE_DIVIDE(c.budget_per_day, t.acct_budget_per_day), 2) AS pct_of_account_budget,
  c.spend_window,
  ROUND(c.spend_window / k.window_days, 2)    AS spend_per_day,
  ROUND(100 * SAFE_DIVIDE(c.spend_window, t.acct_spend_window), 2) AS pct_of_account_spend,
  c.clicks_window, c.orders_window,
  c.gross_profit_window,
  ROUND(c.gp_roas_window, 4)                  AS gp_roas_window,
  ROUND(c.keyword_bar, 4)                     AS keyword_bar,
  ROUND(c.band_half_width, 4)                 AS band_half_width,
  c.shortfall_window,
  c.profit_verdict,
  CASE c.bucket_code
    WHEN 'PROFITABLE' THEN
      FORMAT('%s brings back %s of gross profit for every dollar it spends, clear of the %s its family needs. It holds %s a day of budget and spent %s over the window, %s a day.',
        c.campaign_name, FORMAT('$%.2f', c.gp_roas_window), FORMAT('$%.2f', c.keyword_bar),
        FORMAT('$%\'.2f', c.budget_per_day), FORMAT('$%\'.0f', c.spend_window),
        FORMAT('$%\'.2f', c.spend_window / k.window_days))

    WHEN 'MARGINAL' THEN
      FORMAT('%s brings back %s of gross profit for every dollar it spends against the %s its family needs, close enough that the difference is inside the ordinary movement of the measure. It holds %s a day of budget and spent %s over the window, %s a day.',
        c.campaign_name, FORMAT('$%.2f', c.gp_roas_window), FORMAT('$%.2f', c.keyword_bar),
        FORMAT('$%\'.2f', c.budget_per_day), FORMAT('$%\'.0f', c.spend_window),
        FORMAT('$%\'.2f', c.spend_window / k.window_days))

    WHEN 'UNPROFITABLE' THEN
      FORMAT('%s brings back %s of gross profit for every dollar it spends, short of the %s its family needs. Over the window it came up %s short. It holds %s a day of budget and spent %s, %s a day.',
        c.campaign_name, FORMAT('$%.2f', c.gp_roas_window), FORMAT('$%.2f', c.keyword_bar),
        FORMAT('$%\'.0f', c.shortfall_window), FORMAT('$%\'.2f', c.budget_per_day),
        FORMAT('$%\'.0f', c.spend_window), FORMAT('$%\'.2f', c.spend_window / k.window_days))

    WHEN 'LAUNCH' THEN
      FORMAT('%s belongs to %s, a family the account has decided to invest in. It holds %s a day of budget and spent %s over the window, %s a day. It is judged on whether it is spending at the rate that was agreed and on whether organic sales are climbing, not on what it earns.',
        c.campaign_name, c.family, FORMAT('$%\'.2f', c.budget_per_day),
        FORMAT('$%\'.0f', c.spend_window), FORMAT('$%\'.2f', c.spend_window / k.window_days))

    WHEN 'TOO_SMALL' THEN
      FORMAT('%s has had %d clicks in ninety days, short of the %d it would take to read what it earns. It holds %s a day of budget and spent %s, %s a day.',
        c.campaign_name, c.clicks_window, k.volume_floor_clicks,
        FORMAT('$%\'.2f', c.budget_per_day), FORMAT('$%\'.0f', c.spend_window),
        FORMAT('$%\'.2f', c.spend_window / k.window_days))

    WHEN 'UNJUDGEABLE' THEN
      FORMAT('%s is not attached to any family, so there is nothing to judge it against. It holds %s a day of budget and spent %s over the window. Naming its family on the campaign mapping screen brings it under a bar.',
        c.campaign_name, FORMAT('$%\'.2f', c.budget_per_day), FORMAT('$%\'.0f', c.spend_window))

    WHEN 'NOT_SERVING' THEN
      FORMAT('%s still carries %s a day of budget here, and Amazon has already ended it, so that money cannot be spent.',
        c.campaign_name, FORMAT('$%\'.2f', c.budget_per_day))

    WHEN 'STOPPED' THEN
      FORMAT('%s spent %s inside the window and is no longer running, so it holds no budget today.',
        c.campaign_name, FORMAT('$%\'.0f', c.spend_window))
  END                                         AS sentence,
  w.window_start, w.window_end, k.window_days,
  CURRENT_DATE('America/Los_Angeles')         AS budget_as_of,
  k.volume_floor_clicks, k.band_sigmas
FROM campaign_base c
JOIN spine sp USING (bucket_code)
CROSS JOIN totals t
CROSS JOIN win w
CROSS JOIN k;
