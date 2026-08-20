-- =============================================
-- V_INVEST_STATUS — the Invest book: sanctioned spend rate, trajectory, protection state (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §5.
--
-- THE QUESTION CHANGES WITH AGE (Ori 2026-08-19: "the question of launch products is are they
-- improving — not are they profitable — in the first 3 months").
--
--   RAMP  (months 0-3): judged on TRAJECTORY ONLY. Nothing is required to be positive; everything is
--                       required to be IMPROVING — organic units rising, total net ROAS rising, loss
--                       shrinking. The decision rule is "no improvement across two consecutive
--                       months", NEVER "still unprofitable". A profitable-at-month-2 test would kill
--                       every launch that was working.
--   PROOF (months 3+):  level starts to matter — closing on the declared take-over target by the
--                       end date, with the ceiling and clock enforcing themselves.
--
-- WHY ABSOLUTE ORGANIC UNITS, NOT SHARE: share is a trap — it rises when ads units collapse, which
-- looks like success and is not. Bunny and LolliBall already sit at ~31% organic, comparable to
-- Lollibox's 29.7%, so by share alone they would read "finished" while still losing money.
--
-- A USEFUL CONSEQUENCE: trajectory is robust to a level bias. A constant COGS misallocation cancels
-- out of a month-over-month trend, which is why LolliBall's implausible 0.87 halo (spec §9.1) does
-- not block the ramp test — though it must be fixed before LolliBall reaches PROOF.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_INVEST_STATUS` AS
WITH
-- ---------------------------------------------------------------------------------------------
-- THE DECLARED TUNABLES. Every number the window design rests on is named here, once, so no reader
-- has to find it inside an expression. Changing one of these changes the measure; nothing else does.
-- ---------------------------------------------------------------------------------------------
k AS (
  SELECT
    28  AS rate_window_days,        -- the BINDING window: 28 COMPLETE days, always full (see below)
    7   AS signal_window_days,      -- the DIRECTION signal: 7 complete days. THE GATE NEVER READS IT.
    3   AS feed_stale_after_days,   -- the ads feed may be this many days behind today before the
                                    -- window stops being certifiable. Same threshold V_DATA_FRESHNESS
                                    -- already calls STALE (days_stale > 3), so the two agree.
    0.20 AS direction_band          -- how far the 7-day rate must sit from the 28-day rate before the
                                    -- direction word stops saying "steady". Nothing gates on it, but a
                                    -- word still has to earn itself: the standard error of a 7-day mean
                                    -- is sigma/sqrt(7), which on the sigmas measured below (as of
                                    -- 2026-08-20) is $10.93 of a $59.29 Bunny rate and $19.48 of a
                                    -- $102.01 LolliBall rate — 18% and 19%. Inside 20% the two windows
                                    -- are not distinguishable, so "rising" or "falling" would be a
                                    -- claim about noise. Re-derive the sigmas before quoting them.
),
b AS (
  SELECT * FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'INVEST'
),
-- the three most recent COMPLETE calendar months, per family, from the measurement spine
m AS (
  SELECT family, period_label, period_start, net_profit, total_net_roas, organic_units
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE REGEXP_CONTAINS(period_label, r'^\d{4}-\d{2}$')
    AND period_end < DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), MONTH)
),
ranked AS (
  SELECT m.*, ROW_NUMBER() OVER (PARTITION BY family ORDER BY period_start DESC) AS rn
  FROM m JOIN b USING (family)
),
trend AS (
  SELECT family,
    MAX(IF(rn=1, organic_units, NULL))  AS org_m0, MAX(IF(rn=2, organic_units, NULL))  AS org_m1, MAX(IF(rn=3, organic_units, NULL))  AS org_m2,
    MAX(IF(rn=1, total_net_roas, NULL)) AS tnr_m0, MAX(IF(rn=2, total_net_roas, NULL)) AS tnr_m1, MAX(IF(rn=3, total_net_roas, NULL)) AS tnr_m2,
    MAX(IF(rn=1, net_profit, NULL))     AS np_m0,  MAX(IF(rn=2, net_profit, NULL))     AS np_m1,  MAX(IF(rn=3, net_profit, NULL))     AS np_m2
  FROM ranked WHERE rn <= 3 GROUP BY family
),
-- ---------------------------------------------------------------------------------------------
-- TWO MEASURES, TWO WINDOWS, ONE OWNER EACH.
--
--   MONEY (the loss ceiling) -> CALENDAR MONTH TO DATE, read from V_FAMILY_PNL, never recomputed
--             here. A loss CEILING is a monthly allowance — "$913 in a month" — so a calendar month
--             is the window it is denominated in, and the running month is the right partial. Its
--             money is bounded at the ORDERS watermark, complete by construction (the sessions gate
--             drops mid-sync partial days), so sales, COGS and ad spend inside it end on the same
--             complete day. One concept, one number, one place. Published with its own window
--             columns AND its own basis string (loss_ceiling_window_basis) so it can never be read
--             as the rate window.
--
--   RATE (the sanction)      -> A TRAILING WINDOW OF 28 COMPLETE DAYS, computed here.
--
-- WHY A TRAILING WINDOW AND NOT MONTH TO DATE (defect fix 2026-08-20, third round; Ori's decision).
-- The sanction is denominated as a RATE — "$30 a day", "$55 a day" — not as a monthly budget. A
-- month-to-date rate was the wrong shape from the beginning, and every defect found on this measure
-- came out of that one mistake: on the 1st the month holds one day, so the window had to be special-
-- cased, and the special case is where the damage lives. The round-2 cut required 11 loaded days and,
-- below that, SUBSTITUTED THE LAST COMPLETE CALENDAR MONTH's rate into the same columns —
-- spend_per_day, spend_rate_ratio, spend_breached, protection_qualified. For the first twelve days of
-- every month the sanction gate therefore reported LAST month's behaviour, and where last month was
-- compliant a family overspending today read compliant. Measured on real V_UNIFIED_DAILY spend
-- (2026-08-20): on 3-12 July 2026 that rule published LolliBall at $5.82 a day — June's rate — while
-- July actually ran $91.11 a day against a $55 sanction. Withholding is not substituting.
--
-- A TRAILING WINDOW IS ALWAYS FULL. No month boundary, no minimum, no fallback, no caveat, no
-- is_fallback boolean: on every day of every month it holds exactly 28 complete days. There is
-- nothing left for a substitution rule to do, so there is none.
--
-- WHY THE WINDOW CANNOT BE SHORT — the round-2 derivation, which was sound work and is kept because
-- it is the REASON 28 is safe rather than merely conventional. A rate over n days is the mean of n
-- daily spends, so its standard error is sigma / sqrt(n). For the gate to SEE a family running 1.6x
-- its sanctioned rate, the margin it has to clear (0.6 x the sanctioned rate) must be at least two
-- standard errors wide, which puts a false pass near 1 in 40. That is n >= (2 x sigma / (0.6 x S))^2.
-- MEASURED 2026-08-20, and every figure below is AS OF THAT DATE — re-run the query before quoting:
--
--     WITH e AS (SELECT MAX(IF(ad_cost > 0, date, NULL)) AS d
--                FROM `onyga-482313.OI.V_UNIFIED_DAILY`),
--          f AS (SELECT DISTINCT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'INVEST'),
--          g AS (SELECT f.family, day, COALESCE(SUM(u.ad_cost), 0) AS spend
--                FROM e, UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(e.d, INTERVAL 89 DAY), e.d)) AS day
--                CROSS JOIN f
--                LEFT JOIN `onyga-482313.OI.V_UNIFIED_DAILY` u
--                       ON u.family = f.family AND u.date = day
--                GROUP BY 1, 2)
--     SELECT family, ROUND(STDDEV_SAMP(spend), 2) AS sigma FROM g GROUP BY 1
--
-- (It anchors on the feed rather than on a literal date, so it re-runs correctly on any day. Run
-- 2026-08-20 over the 90 days to 19 August 2026, it returned exactly the two sigmas below.)
--
--     Bunny      sigma $28.91, S $30 -> margin $18 -> n >= (57.82 / 18)^2  = 10.32 -> 11 days
--     LolliBall  sigma $51.55, S $55 -> margin $33 -> n >= (103.10 / 33)^2 =  9.76 -> 10 days
--
-- 28 sits far above that 11-day floor, and it is the house 28-day window, so the ladder here is the
-- same one the rest of OI reads. The floor is why the window may not be shortened; it is no longer a
-- minimum anything is tested against, because a trailing window can never fall below its own length.
--
-- WHAT A TRAILING WINDOW COSTS, STATED RATHER THAN HIDDEN. It lags a step UP. On a launch that
-- ramps from near zero, the 28-day window still contains the quiet pre-ramp days for four weeks, so
-- the rate reads lower than the family is spending TODAY. Walked over every day from 1 May to 20
-- August 2026 on real daily spend (as of 2026-08-20, both INVEST families, 224 family-days): on 9
-- of them the trailing window read compliant where the old month-to-date window read breached —
-- Bunny 13-15 June and LolliBall 13-18 July, both inside their launch ramps. That is the honest
-- trade Ori chose against a rule that reported the WRONG MONTH for twelve days out of every month
-- and could not be repaired without another special case. The 7-day direction signal below exists
-- precisely so a ramp is visible while the binding window is still catching up; it is published, it
-- is named, and the gate does not read it.
--
-- HOW THAT WALK IS RE-RUN, because a number in a comment is worth what its method is worth: take
-- every simulated today, set feed_end = today - lag for lag in 1, 2 and 3 (the observed lag is 1),
-- build BOTH windows off it — trailing [feed_end - 28, feed_end - 1] against the old
-- month-to-date-with-an-11-day-fallback — and read each against real daily spend from
-- V_UNIFIED_DAILY, zero-filled so a day with no rows counts as $0. Over 672 family-days the trailing
-- window returned exactly ONE window length, 28, at every lag and on every day of the month; the old
-- one returned 11 to 31 and spent 240 of those 672 family-days describing a DIFFERENT MONTH than the
-- day it was published on.
--
-- THE DENOMINATOR IS ELAPSED DAYS, NOT DAYS THAT HAVE ROWS. The divisor is the window length, so a
-- genuine zero-spend day counts as a zero rather than dropping out and inflating the rate.
--
-- WHY THE LOSS CEILING IS PUBLISHED BUT DOES NOT DECIDE ANYTHING: the SHAPE, which does not go
-- stale, is that both families run well over their sanctioned SPEND while their month-to-date LOSS
-- sits at a small fraction of a ceiling denominated in net profit — a loss ceiling on a product that
-- nearly covers its costs never fires. The spend rate is what binds. The ceiling clause survives
-- inside protection_qualified ONLY as a catastrophe backstop and as a fail-closed test for missing
-- data: it can make protection harder to earn, never easier.
--
-- ---------------------------------------------------------------------------------------------
-- THE WINDOW IS BOUNDED ON THE SOURCE THAT IS ACTUALLY SUMMED.
--
-- The numerator sums ad_cost from V_UNIFIED_DAILY, so the newest day of the window is taken from
-- V_UNIFIED_DAILY too. Earlier cuts read FACT_AMAZON_ADS instead. They agree today, but they are not
-- the same set: V_UNIFIED_DAILY keeps only rows whose advertised ASIN resolves through
-- COALESCE(most_advertised_asin_impressions, advertised_asins, ASIN_BY_CAMPAIGN_NAME) AND whose ASIN
-- joins V_PRODUCT_FAMILY_MAP AND whose date joins DIM_TIME. A day can land in FACT and reach nothing
-- here. The window would then end on a day the numerator cannot see while the denominator still
-- counted it — diluting the rate DOWN, the same direction as every defect found on this measure.
--
-- AND IT IS CAPPED THE WAY ITS SIBLINGS ARE. V_KEYWORD_CONTEXT_LEDGER:27, V_KEYWORD_CONTEXT_GATE:78
-- and V_SEASON_CONTEXT:37 all read LEAST(MAX(date), FN_ADS_ANCHOR_CAP()). A future-dated row would
-- otherwise push the window END past the days that exist, spending the window's 28 days on days with
-- no spend in them — the same dilution again.
--
-- THE NEWEST LOADED DAY IS NOT IN THE WINDOW. Day-1 ads are 88-90% loaded and restate for about
-- three days (fact_oi_fresh_ads_data_reading_rules), and a half-loaded day divided as a whole day
-- drags the rate DOWN. So the window ENDS one day before the feed's newest reachable day.
--
-- ---------------------------------------------------------------------------------------------
-- THE STALENESS BOUND: A FROZEN FEED MUST NOT KEEP CERTIFYING A SANCTION.
--
-- The window is anchored entirely on the ads feed. If Fivetran stalls, the anchor freezes, the
-- window slides nowhere, and without a bound this view would publish a rate and a verdict off a
-- frozen four-week window for as long as the stall lasts — while a launch spent whatever it liked in
-- the days nobody can see. The bound is the ADS FEED'S AGE against today: ads_feed_age_days =
-- CURRENT_DATE(LA) - the newest reachable ads day. Normal operation is 1. Stale is more than
-- feed_stale_after_days = 3, the same threshold V_DATA_FRESHNESS uses for every other source, so OI
-- has one definition of a stale feed rather than two.
--
-- WHAT THE GATE DOES WHEN THE FEED IS STALE: protection_qualified FAILS CLOSED — no protection. A
-- sanction gate that cannot see current spend must not certify it, and NULL-safety runs the same
-- way: an unknown staleness is treated as stale. The RATE ITSELF IS STILL PUBLISHED, because it is a
-- true statement about the days it covers; rate_window_is_stale, ads_feed_last_day and
-- ads_feed_age_days say plainly how old those days are, and rate_window_basis says it in words.
-- ---------------------------------------------------------------------------------------------
u AS (
  -- ONE bounded pass over the source the numerator sums. The 200-day bound is a scan guard, not a
  -- measurement choice: it is seven times the 28-day window, so it cannot clip it. A feed frozen for
  -- longer than 200 days returns no rows at all — every window column NULL, every rate NULL, and
  -- protection_qualified FALSE, which is the fail-closed direction.
  SELECT family, date, ad_cost
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 200 DAY)
),
u_win AS (
  -- The window edges as ROW-LEVEL constants, so the whole thing is one pass: an unpartitioned
  -- analytic MAX over the same scan, rather than a second expansion of V_UNIFIED_DAILY to find the
  -- newest day. feed_end = the newest day whose ad spend actually reaches this view, capped.
  -- The window lengths come from k, not from literals repeated here: a declared tunable that some
  -- other line quietly re-states is how two numbers that must be equal stop being equal.
  SELECT
    x.family, x.date, x.ad_cost, x.feed_end,
    DATE_SUB(x.feed_end, INTERVAL 1 DAY)                                 AS win_end,
    DATE_SUB(x.feed_end, INTERVAL k.rate_window_days   DAY)              AS win_start,
    DATE_SUB(x.feed_end, INTERVAL k.signal_window_days DAY)              AS sig_start
  FROM (
    SELECT family, date, ad_cost,
           LEAST(MAX(IF(ad_cost > 0, date, NULL)) OVER (),
                 `onyga-482313.OI.FN_ADS_ANCHOR_CAP`())                  AS feed_end
    FROM u
  ) x
  CROSS JOIN k
),
spend AS (
  SELECT
    family,
    MAX(feed_end)                                                        AS feed_end,
    MAX(win_start)                                                       AS win_start,
    MAX(win_end)                                                         AS win_end,
    MAX(sig_start)                                                       AS sig_start,
    ROUND(SUM(IF(date BETWEEN win_start AND win_end, ad_cost, 0)), 2)    AS rate_window_spend,
    ROUND(SUM(IF(date BETWEEN sig_start AND win_end, ad_cost, 0)), 2)    AS signal_window_spend
  FROM u_win
  GROUP BY family
),
-- The window as ONE row, so every INVEST family publishes the same span even when it has no spend at
-- all. Derived from `spend` (already grouped, a handful of rows) rather than from V_UNIFIED_DAILY
-- again, so the heavy source is expanded once. With no rows at all this still returns a single
-- all-NULL row, which is what keeps the CROSS JOIN below from deleting families.
rate_win AS (
  SELECT
    MAX(feed_end)                                                        AS feed_end,
    MAX(win_start)                                                       AS win_start,
    MAX(win_end)                                                         AS win_end,
    MAX(sig_start)                                                       AS sig_start,
    DATE_DIFF(MAX(win_end), MAX(win_start), DAY) + 1                     AS win_days,
    DATE_DIFF(MAX(win_end), MAX(sig_start), DAY) + 1                     AS sig_days,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(feed_end), DAY)   AS feed_age_days
  FROM spend
),
w AS (
  SELECT
    r.*,
    k.feed_stale_after_days,
    k.direction_band,
    (r.feed_age_days > k.feed_stale_after_days)                          AS is_stale,
    -- THE SPAN IN WORDS, for the column a person reads. Real dates every day of the year, so it can
    -- never drift out of agreement with the numbers beside it, and it says out loud that this is the
    -- window the sanction is judged on.
    CONCAT(
      FORMAT_DATE('%-d %B', r.win_start), ' to ', FORMAT_DATE('%-d %B %Y', r.win_end), ', ',
      CAST(r.win_days AS STRING), ' complete days — the window the agreed daily rate is judged on',
      IF(r.feed_age_days > k.feed_stale_after_days,
         CONCAT('. The advertising figures have not moved for ', CAST(r.feed_age_days AS STRING),
                ' days, so this window is out of date and nothing can be certified against it.'),
         '.'))                                                           AS win_basis,
    -- The same window compressed to a clause that drops into the middle of a sentence: "spending
    -- $59.29 a day over the 28 days to 18 August 2026".
    CONCAT('over the ', CAST(r.win_days AS STRING), ' days to ',
           FORMAT_DATE('%-d %B %Y', r.win_end))                          AS win_phrase,
    -- AND THE SIGNAL WINDOW, NAMED SO IT CANNOT BE MISTAKEN FOR THE BINDING ONE.
    CONCAT(
      FORMAT_DATE('%-d %B', r.sig_start), ' to ', FORMAT_DATE('%-d %B %Y', r.win_end), ', ',
      CAST(r.sig_days AS STRING), ' complete days — direction only. Nothing is judged on this window.')
                                                                         AS sig_basis
  FROM rate_win r CROSS JOIN k
),
-- THE MONEY, READ NOT RECOMPUTED. One row per family for the running month, bounded at the orders
-- watermark by the view that owns it.
money AS (
  SELECT family, net_profit AS mtd_net_profit, period_start AS mtd_money_start, period_end AS mtd_money_end
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE period_label = 'MTD'
)
SELECT
  b.family,
  b.launch_age_months,
  IF(b.launch_age_months <= 3, 'RAMP', 'PROOF')                                       AS phase,
  -- THE BINDING SANCTION.
  -- NULL, NEVER ZERO, WHEN THE SPEND IS UNKNOWN. COALESCE(rate, 0) made "we have no data for this
  -- family" read as "it spent nothing", which is the single most flattering reading available and
  -- the one that hands out launch protection for free.
  b.daily_investment,
  -- ─── THE RATE THAT BINDS: 28 complete trailing days. THIS is what the sanction gate reads. ───
  sp.rate_window_spend,
  sp.spend_per_day,
  ROUND(SAFE_DIVIDE(sp.spend_per_day, NULLIF(b.daily_investment, 0)), 2)               AS spend_rate_ratio,
  -- TRUE means measured over. FALSE means measured under. NULL means NOT MEASURED — which is not a
  -- pass, and protection_qualified below refuses to treat it as one.
  (sp.spend_per_day > b.daily_investment)                                              AS spend_breached,
  -- WHICH DAYS THE BINDING RATE COVERS: as dates, as a count, and in two ready-made English forms.
  w.win_start                                                                          AS rate_window_start,
  w.win_end                                                                            AS rate_window_end,
  w.win_days                                                                           AS rate_window_days,
  w.win_basis                                                                          AS rate_window_basis,
  w.win_phrase                                                                         AS rate_window_phrase,
  -- ─── THE DIRECTION SIGNAL: 7 complete days, ending on the same day. IT DOES NOT BIND. ───
  -- Ori approved the ladder shape separately: the long window decides, the short one says which way
  -- the rate is moving — a launch stepping up shows here weeks before the 28-day mean catches it.
  -- Nothing in protection_qualified, spend_breached or spend_rate_ratio reads any of these columns,
  -- and the name of every one of them says so.
  sp.spend_per_day_7d_signal_only,
  ROUND(SAFE_DIVIDE(sp.spend_per_day_7d_signal_only, NULLIF(sp.spend_per_day, 0)), 2)  AS spend_rate_direction_ratio,
  CASE
    WHEN sp.spend_per_day_7d_signal_only IS NULL OR sp.spend_per_day IS NULL OR sp.spend_per_day = 0 THEN NULL
    WHEN sp.spend_per_day_7d_signal_only > sp.spend_per_day * (1 + w.direction_band)   THEN 'rising'
    WHEN sp.spend_per_day_7d_signal_only < sp.spend_per_day * (1 - w.direction_band)   THEN 'falling'
    ELSE 'steady'
  END                                                                                  AS spend_rate_direction,
  w.sig_start                                                                          AS signal_window_start,
  w.win_end                                                                            AS signal_window_end,
  w.sig_days                                                                           AS signal_window_days,
  w.sig_basis                                                                          AS signal_window_basis,
  -- ─── HOW OLD THE ADS FEED IS, AND WHETHER THAT IS STILL CERTIFIABLE ───
  w.feed_end                                                                           AS ads_feed_last_day,
  w.feed_age_days                                                                      AS ads_feed_age_days,
  w.feed_stale_after_days                                                              AS ads_feed_stale_after_days,
  COALESCE(w.is_stale, TRUE)                                                           AS rate_window_is_stale,
  -- ─── THE LOSS CEILING: A DIFFERENT WINDOW, A DIFFERENT JOB, AND IT DOES NOT BIND ───
  -- Calendar month to date, cut at the ORDERS watermark by V_FAMILY_PNL. Nothing here recomputes it.
  -- The basis string exists so that a reader holding both windows on one row can never take this for
  -- the rate window: one is a monthly allowance, the other is a trailing rate.
  b.monthly_loss_ceiling,
  mo.mtd_net_profit,
  mo.mtd_money_start,
  mo.mtd_money_end,
  IF(mo.mtd_money_start IS NULL OR mo.mtd_money_end IS NULL, NULL,
     CONCAT(FORMAT_DATE('%-d %B', mo.mtd_money_start), ' to ',
            FORMAT_DATE('%-d %B %Y', mo.mtd_money_end),
            ', the part of this calendar month that is measured — a monthly allowance, not the ',
            'spend-rate window, and not what the sanction is judged on'))               AS loss_ceiling_window_basis,
  ROUND(100 * SAFE_DIVIDE(-mo.mtd_net_profit, NULLIF(b.monthly_loss_ceiling, 0)), 1)   AS ceiling_used_pct,
  (-mo.mtd_net_profit >= b.monthly_loss_ceiling)                                       AS ceiling_breached,
  b.stop_date,
  DATE_DIFF(b.stop_date, CURRENT_DATE('America/Los_Angeles'), DAY)                     AS days_left,
  -- ---------------------------------------------------------------------------------------------
  -- WHETHER THE LAUNCH QUALIFIES FOR PROTECTION, AND WHAT THAT IS NOT.
  -- It was called exemption_live until 2026-08-20 and the name was the problem: "live" reads as "in
  -- force", which is the one thing it does not mean. This column says whether a launch has EARNED
  -- protection under the rules Ori set, never whether any machine is applying it.
  --
  -- This column is a STATEMENT, not yet a control. NOTHING READS IT TO STOP ANYTHING:
  -- V_LAUNCH_EXEMPTION still hardcodes TRUE AS exempt_active, so every launch keeps its protection
  -- whatever this says. Wiring this to the engine is Task 8b, and Task 8b is not built. Until it is,
  -- the only thing standing between an over-sanction launch and the money is a person reading it.
  --
  -- IT FAILS CLOSED, ON FIVE COUNTS. Protection is granted only on POSITIVE evidence of adherence:
  -- inside the sanctioned window, a sanctioned rate on file, a measured spend at or under it, a
  -- ceiling on file with a measured loss under it, and A WINDOW THAT IS STILL CURRENT. Any one of
  -- those missing and the answer is FALSE. Silence is not compliance, and neither is a frozen feed.
  -- ---------------------------------------------------------------------------------------------
  -- The outer COALESCE closes the last hole: a family with no stop date on file would otherwise
  -- leave the whole chain NULL, and NULL is not FALSE to a consumer that only tests for FALSE.
  COALESCE(
    CURRENT_DATE('America/Los_Angeles') <= b.stop_date
    AND b.stop_date            IS NOT NULL
    AND b.daily_investment     IS NOT NULL AND sp.spend_per_day  IS NOT NULL
    AND b.monthly_loss_ceiling IS NOT NULL AND mo.mtd_net_profit IS NOT NULL
    AND NOT COALESCE(w.is_stale, TRUE)
    AND sp.spend_per_day      <= b.daily_investment
    AND -mo.mtd_net_profit     < b.monthly_loss_ceiling, FALSE)                        AS protection_qualified,
  t.org_m2, t.org_m1, t.org_m0,
  t.tnr_m2, t.tnr_m1, t.tnr_m0,
  t.np_m2,  t.np_m1,  t.np_m0,
  -- the three RAMP trends; NULL-safe so a young family with two months of data still reports
  (t.org_m0 > t.org_m1)                                                               AS organic_units_rising,
  (t.tnr_m0 > t.tnr_m1)                                                               AS net_roas_rising,
  (t.np_m0  > t.np_m1)                                                                AS loss_shrinking,
  b.takeover_target_organic_units,
  CASE
    WHEN b.launch_age_months <= 3 THEN
      CASE
        WHEN t.org_m1 IS NULL THEN 'too early to judge — needs two complete months'
        WHEN t.org_m0 > t.org_m1 AND t.np_m0 > t.np_m1
          THEN CONCAT('improving — organic units ', CAST(t.org_m1 AS STRING), ' to ', CAST(t.org_m0 AS STRING), ', loss shrinking')
        WHEN t.org_m2 IS NOT NULL AND t.org_m0 <= t.org_m1 AND t.org_m1 <= t.org_m2
          THEN 'no improvement two months running — the investment is not working'
        ELSE CONCAT('mixed — organic units ', CAST(t.org_m1 AS STRING), ' to ', CAST(t.org_m0 AS STRING), ', watch next month')
      END
    ELSE
      CASE
        WHEN b.takeover_target_organic_units IS NULL
          THEN CONCAT('take-over target not set — ', CAST(t.org_m0 AS STRING),
                      ' organic units last complete month, but nothing to judge it against')
        WHEN t.org_m0 >= b.takeover_target_organic_units
          THEN CONCAT('took over — ', CAST(t.org_m0 AS STRING), ' organic units against a target of ', CAST(b.takeover_target_organic_units AS STRING))
        ELSE CONCAT('short of target — ', CAST(t.org_m0 AS STRING), ' of ', CAST(b.takeover_target_organic_units AS STRING), ' organic units, ',
                    CAST(DATE_DIFF(b.stop_date, CURRENT_DATE('America/Los_Angeles'), DAY) AS STRING), ' days left')
      END
  END                                                                                 AS verdict
FROM b
CROSS JOIN w
LEFT JOIN trend t  ON t.family  = b.family
LEFT JOIN (
  -- The rates, divided by the WINDOW LENGTH rather than by the number of days that happen to carry
  -- rows, so a zero-spend day is a zero and not an absence.
  SELECT
    s.family,
    s.rate_window_spend,
    ROUND(SAFE_DIVIDE(s.rate_window_spend,
                      DATE_DIFF(s.win_end, s.win_start, DAY) + 1), 2)                 AS spend_per_day,
    ROUND(SAFE_DIVIDE(s.signal_window_spend,
                      DATE_DIFF(s.win_end, s.sig_start, DAY) + 1), 2)                 AS spend_per_day_7d_signal_only
  FROM spend s
) sp ON sp.family = b.family
LEFT JOIN money mo ON mo.family = b.family;
