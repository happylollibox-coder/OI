-- =============================================
-- V_INVEST_STATUS — the Invest book: sanctioned spend rate, trajectory, protection state.
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §5.
--
-- STANDING RULE 0 APPLIES TO THIS HEADER. A measured number written into prose is a liability.
-- Where a figure appears below it carries its as-of date and the window it was measured on, and the
-- QUERY that produced it is written beside it. Re-run before quoting. Nothing here gates on a pinned
-- number; every threshold this view applies is derived at query time from the data it is judging.
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
-- looks like success and is not. Both INVEST families already sit INSIDE the band the established
-- families occupy — above at least one of them — so by share alone they would read "finished" while
-- still losing money. Read it off the data rather than from a number written here:
--   SELECT family, ROUND(100 * SAFE_DIVIDE(SUM(organic_units), NULLIF(SUM(units), 0)), 1) AS organic_pct
--   FROM `onyga-482313.OI.V_UNIFIED_DAILY`
--   WHERE date > DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 90 DAY)
--   GROUP BY family ORDER BY organic_pct DESC
--
-- A USEFUL CONSEQUENCE: trajectory is robust to a level bias. A constant COGS misallocation cancels
-- out of a month-over-month trend, which is why LolliBall's implausible halo (spec §9.1) does not
-- block the ramp test — though it must be fixed before LolliBall reaches PROOF.
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════
-- THE SANCTION GATE: TWO WINDOWS, EITHER MAY BREACH (2026-08-20, FOURTH ROUND — ORI'S DECISION).
-- ═════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHAT WENT WRONG. Round 2 judged the rate month-to-date and lied for the first twelve days of every
-- month. Round 3 replaced it with a trailing 28 complete days, which never lies about WHICH days it
-- covers — and then lags a step UP, because for four weeks the window still contains the quiet
-- pre-ramp days. That lag is a LIVE FALSE PASS, not a theoretical one. Re-derived on real
-- V_UNIFIED_DAILY spend, zero-filled, 2026-08-20:
--
--     window 2026-06-19..2026-07-16  ->  LolliBall $54.32 a day, 0.99x its $55 sanction, NOT breached
--     the 7 days INSIDE that window  ->            $106.93 a day
--     July 2026 as a whole            ->            $91.11 a day
--
-- The month's loss also sat far under the ceiling, so a gate reading only the 28-day window would
-- have certified a launch running near twice its sanctioned rate. Neither window is right alone.
--
-- ORI'S RULE: BREACH ON EITHER WINDOW. A sanction gate must never certify a family that any credible
-- window says is overspending — fail closed, as everywhere else in this view.
--
--     spend_breached = (the 28-day rate is over the sanction)
--                   OR (the 7-day rate is over the sanction BY MORE THAN A DERIVED MARGIN)
--
-- WHY THE 7-DAY ARM NEEDS A MARGIN AND THE 28-DAY ARM DOES NOT. A rate over n days is the mean of n
-- daily spends, so its standard error is sigma / sqrt(n). Over 28 days that error is small next to
-- any overspend worth acting on; over 7 days it is not, and a bare "7-day rate > sanction" test
-- would fire on an ordinary noisy week. So the short arm must clear the sanction by z standard
-- errors of a 7-day mean: margin = z * sigma / sqrt(7), z = k.breach_margin_sigmas.
--
-- z = 2, AND IT IS THE SAME z THIS FILE ALREADY DERIVES THE WINDOW LENGTH AT. The 28-day floor below
-- is derived from "the margin must be at least TWO standard errors wide, which puts a false pass
-- near 1 in 40". One measure, one z. Two standard errors of a 7-day mean is a ~2.3% one-sided false-
-- alarm rate on a normal approximation — a 7-day-only breach roughly once in 44 quiet weeks.
--
-- WHICH sigma, AND WHY NOT THE OBVIOUS ONE. sigma must estimate DAY-TO-DAY NOISE. The plain standard
-- deviation of daily spend over a long window does not: on a ramping launch it is dominated by the
-- RAMP ITSELF, so the margin widens exactly when the gate needs to be able to see a step up — the
-- permissive direction, which is the direction every defect on this measure has run in. This view
-- therefore uses the FIRST-DIFFERENCE estimator: sigma = STDDEV_SAMP(spend_t - spend_t-1) / sqrt(2),
-- which is exact for independent daily noise (Var of a difference is 2 sigma^2) and nearly immune to
-- a level shift, because a step contributes ONE large difference out of ninety instead of pulling
-- every deviation in the window. Where daily noise is positively autocorrelated it UNDERSTATES
-- sigma, which narrows the margin — the fail-closed direction, and the one to be wrong in.
--
-- HOW MUCH THAT CHOICE MATTERS, MEASURED (as of 2026-08-20, 90 zero-filled days to 2026-08-18 —
-- RE-RUN, DO NOT QUOTE): the plain standard deviation came out about 2.5x the first-difference sigma
-- on Bunny and about 3.8x on LolliBall, the family that ramped. The damage is not the size of the
-- number, it is WHEN it arrives: the plain sigma stays inflated for a full noise window AFTER a ramp,
-- so on the plain estimator LolliBall's 7-day breach threshold today would sit near $94 a day
-- against the ~$65 this view publishes — the family would have to run at nearly 1.7x its sanctioned
-- rate before the short arm could speak, and it would be a ramp that already ENDED that bought it
-- that room. On the walk below the plain estimator scores 8 false-compliant family-days against 6.
--
-- THE MARGIN IS PUBLISHED, NOT HIDDEN: breach_margin_sigmas (z), daily_spend_sigma,
-- short_window_standard_error, breach_margin_per_day and short_window_breach_threshold_per_day are
-- all columns. A reader can check the arithmetic without opening this file.
--
-- WHAT THE TWO ARMS MEAN TO A READER, WHICH IS WHY spend_breach_arm EXISTS. A 28-day breach is a
-- STANDING overspend — it has been going on for weeks and the money is already gone. A 7-day-only
-- breach is a FRESH RAMP — it started recently, the 28-day mean has not caught it yet, and it is the
-- one that can still be stopped cheaply. Different facts, different actions, so the row says which.
--
-- HOW THE RULE WAS TESTED, AND THE RESULT. Walked day by day on real V_UNIFIED_DAILY spend,
-- zero-filled, NOT rescaled: for every simulated today T, feed_end = T - 1 (the observed lag), the
-- 28-day window = [feed_end-28, feed_end-1], the 7-day window = [feed_end-7, feed_end-1], and sigma
-- re-estimated from the 90 zero-filled days ending feed_end-1 — exactly what this view computes.
-- GROUND TRUTH is the family's actual mean daily spend over the 15 days CENTRED on T (the rate an
-- omniscient reader would have named on the day), and "truly overspending" is that rate above the
-- sanction. FALSE-COMPLIANT = the gate published not-breached while the truth was over.
-- Run 2026-08-20 over 20 June to 12 August 2026, both families, 108 family-days, 95 of them truly
-- over: OLD RULE (28-day only) 16 false-compliant; NEW RULE (either window) 6. FALSE BREACHES: 0
-- under both. On the unambiguous subset (truth above 1.2x or below 0.8x the sanction, 104 of the
-- 108): 14 -> 4, still no false breach. The ten days recovered are LolliBall 9-18 July 2026 as
-- simulated todays, i.e. feed_end 8-17 July, the ten feed-days the short arm catches alone — the
-- exact ramp the defect was demonstrated on, including 18 July, where the old rule published 0.99x
-- against a true $103.36 a day. The six that remain false-compliant are 3-8 July, the first week of
-- that ramp, when the 7-day window did not yet contain seven ramped days: NO window of seven days
-- can see a ramp before seven days of it exist, and the honest thing is to say so rather than to
-- shorten the window until it "catches" the case it was tuned on.
-- The same walk shows the choice of z is not load-bearing on this data: z from 1.5 to 3.0 gives 6-7
-- false-compliant and ZERO false breaches, so z = 2 is taken from the derivation above rather than
-- from the backtest. The backtest can only say that 2 does no harm.
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════
-- THE WINDOWS THEMSELVES
-- ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   MONEY (the loss ceiling) -> CALENDAR MONTH TO DATE, read from V_FAMILY_PNL, never recomputed
--             here. A loss CEILING is a monthly allowance, so a calendar month is the window it is
--             denominated in, and the running month is the right partial. Its money is bounded at
--             the ORDERS watermark, complete by construction. One concept, one number, one place.
--             Published with its own window columns AND its own basis string
--             (loss_ceiling_window_basis) so it can never be read as the rate window.
--
--   RATE (the sanction)      -> TWO TRAILING WINDOWS OF COMPLETE DAYS, 28 and 7, computed here.
--
-- A TRAILING WINDOW IS ALWAYS FULL. No month boundary, no minimum, no fallback, no caveat, no
-- is_fallback boolean: on every day of every month the long window holds exactly 28 complete days
-- and the short one exactly 7. There is nothing left for a substitution rule to do, so there is none.
--
-- WHY THE LONG WINDOW MAY NOT BE SHORTENED — the round-2 derivation, kept because it is the REASON
-- 28 is safe rather than merely conventional. For the gate to SEE a family running 1.6x its
-- sanctioned rate, the margin it has to clear (0.6 x the sanctioned rate) must be at least two
-- standard errors wide, i.e. n >= (2 * sigma / (0.6 * S))^2. Run this to re-derive it — note it uses
-- the PLAIN standard deviation, which is the conservative (larger n) choice for a window length:
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
-- Run 2026-08-20 over the 90 days to 2026-08-19 it put the floor near 10-11 days for both families.
-- 28 sits far above that floor and is the house 28-day window, so the ladder here is the one the
-- rest of OI reads. The floor is why the window may not be shortened; it is no longer a minimum
-- anything is tested against, because a trailing window can never fall below its own length.
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
-- THE CAP IS YESTERDAY (LA), FIXED, AND IT IS DELIBERATELY *NOT* FN_ADS_ANCHOR_CAP() (K4b/K4c fix,
-- 2026-08-20). Its siblings — V_KEYWORD_CONTEXT_LEDGER:27, V_KEYWORD_CONTEXT_GATE:78,
-- V_SEASON_CONTEXT:37 — all read LEAST(MAX(date), FN_ADS_ANCHOR_CAP()), and this view did too. That
-- function returns CURRENT_DATE(LA) once the LA hour reaches 22 and CURRENT_DATE(LA) - 1 before it,
-- so TWO READS AN HOUR APART ACROSS 22:00 COULD NAME DIFFERENT 28-DAY SPANS and publish different
-- verdicts on the same calendar day. That is a UI-freshness trade-off (it lets a reader ahead of LA
-- see the current LA date late in the evening) and it is the wrong trade for a SANCTION GATE, where
-- the window a verdict is judged on must not move within a day.
-- IT ALSO CARRIES A REAL MEASUREMENT COST, and V_ADS_SETTLE_CURVE prices it. Ads SPEND settles fast:
-- run `SELECT age_days, spend_pct_of_final_median FROM `onyga-482313.OI.V_ADS_SETTLE_CURVE`
-- WHERE channel = 'ALL' AND age_days <= 3` — as of 2026-08-20 it returned 5.2% at age 0, 88.3% at
-- age 1, 99.9% at age 2 and 100.1% at age 3 (re-run; do not quote). With the fixed cap, the newest
-- day inside the window is always at least age 2, i.e. about 99.9% loaded, so the under-load bias on
-- the rate is on the order of 0.1% of ONE day — about 0.004% of the 28-day rate and 0.014% of the
-- 7-day rate, thousands of times smaller than the breach margin and not worth a correction. Under
-- FN_ADS_ANCHOR_CAP, an after-22:00 read on a same-day-loaded feed would have put an age-1 day
-- (~88% loaded) at the end of the window: about 0.4% low on the 28-day rate and 1.7% low on the
-- 7-day one — small, but biased in the PERMISSIVE direction, which is the direction this view is
-- not allowed to be sloppy in. Both costs are removed by the fixed cap.
--
-- THE NEWEST LOADED DAY IS STILL NOT IN THE WINDOW. Day-1 ads are 88-90% loaded and restate for
-- about three days (fact_oi_fresh_ads_data_reading_rules), and a half-loaded day divided as a whole
-- day drags the rate DOWN. So the window ENDS one day before the feed's newest reachable day.
--
-- THE 200-DAY SCAN GUARD NOW GUARDS ITSELF (K4a fix, 2026-08-20). The scan is anchored on
-- CURRENT_DATE, not on feed_end, so a badly stalled feed can push the window's days off the front of
-- the scan. They would then be summed as ZERO — silently, while the basis string still claimed 28
-- complete days, and in the permissive direction. The window is therefore tested against the scan
-- floor: if win_start falls outside it, the rate is WITHHELD (NULL, never a partial sum), the basis
-- says so in words, and protection_qualified fails closed. The floor is set one day INSIDE the scan
-- so that the two expressions can only ever disagree in the safe direction.
--
-- ---------------------------------------------------------------------------------------------
-- THE STALENESS BOUND, PER FAMILY (K2 fix, 2026-08-20 — this was the critical one).
--
-- The window is anchored entirely on the ads feed. If Fivetran stalls, the anchor freezes, the
-- window slides nowhere, and without a bound this view would publish a rate and a verdict off a
-- frozen four-week window while a launch spent whatever it liked in the days nobody can see.
--
-- UNTIL THIS ROUND THAT BOUND WAS ACCOUNT-WIDE AND COULD NOT SEE A PER-FAMILY FEED STOP. feed_end
-- was an UNPARTITIONED analytic MAX over every family. If ONE family's spend stopped reaching this
-- view while the rest of the account kept loading, the age stayed 1, the window stayed "fresh", and
-- that family's spend was divided by 28 days of which several carried no data — reading LOW, the
-- compliance direction, with the gate certifying it.
--
-- STALENESS IS NOW MEASURED PER FAMILY: family_ads_last_day is the newest day on which THAT family
-- has an ads row reaching this view (ad_cost > 0 OR impressions > 0 — impressions are included so a
-- day of genuinely zero-cost delivery still counts as the feed arriving), and rate_window_is_stale
-- is that family's own age against feed_stale_after_days. NULL age is treated as stale.
--
-- THE ACCOUNT-WIDE FIGURES ARE STILL PUBLISHED, AND THEY ARE NOT A SECOND GATE, BECAUSE THEY CANNOT
-- BE ONE. A family's last day can never be newer than the account's, so account-stale ALWAYS implies
-- family-stale: adding the account test to the gate would change no row, ever. It earns its place as
-- a DIAGNOSTIC instead — reading ads_feed_age_days beside family_ads_feed_age_days is what separates
-- "the whole feed stopped" from "this one family stopped", and those need different phone calls.
--
-- WHAT IT COSTS, STATED RATHER THAN HIDDEN: a family that has genuinely stopped advertising for more
-- than feed_stale_after_days is indistinguishable, from inside this view, from a family whose feed
-- broke — V_UNIFIED_DAILY COALESCEs both ad_cost and impressions to 0. It will read stale and lose
-- protection. That is Ori's rule applied literally ("unknown staleness = stale"), and it is the safe
-- error: a launch that has stopped spending is not executing its sanctioned investment either.
--
-- WHAT THE GATE DOES WHEN THE FEED IS STALE: protection_qualified FAILS CLOSED — no protection. A
-- sanction gate that cannot see current spend must not certify it. THE RATE ITSELF IS STILL
-- PUBLISHED, because it is a true statement about the days it covers; rate_window_is_stale,
-- family_ads_last_day, ads_feed_last_day and the two age columns say plainly how old those days are,
-- and rate_window_basis says it in words.
--
-- rate_window_days_with_ads_rows counts how many of the window's 28 days carried an ads row for that
-- family at all. It is a DIAGNOSTIC and nothing gates on it: a day of genuine zero spend is a real
-- zero and must stay in the denominator. It is published so a reader can see a hole rather than
-- infer one from a suspiciously low rate.
--
-- ---------------------------------------------------------------------------------------------
-- A SANCTION CANNOT BE JUDGED ON DAYS IT DID NOT COVER (K3 fix, 2026-08-20).
--
-- sanctioned_on — the day Ori signed the rate off — lives on DE_LAUNCH_INVESTMENT and is republished
-- by V_BOOK_ASSIGNMENT, and until this round this view never read it. Both current sanctions were
-- signed months after their launches began, so the trailing window covered long stretches of days on
-- which no rate had been agreed, while rate_window_basis called itself "the window the agreed daily
-- rate is judged on". Judging a family against a sanction that did not yet exist is not a defensible
-- verdict, however unflattering the spend.
--
-- SHRINKING THE WINDOW TO FIT THE SANCTION WAS REJECTED OUTRIGHT — rate_window_days must read 28 on
-- every day of every month, and a part-window rate carrying the same column name as a full one is
-- exactly the substitution round 2 was convened to delete.
--
-- WHAT IS WITHHELD IS THE CREDIT, NOT THE COMPARISON, AND THE ASYMMETRY IS THE WHOLE DESIGN.
-- The obvious implementation — withhold spend_breached itself until a full window sits inside the
-- sanction — WAS BUILT, DEPLOYED AND ROLLED BACK ON 2026-08-20, because it is fail-OPEN in practice.
-- NULL does not travel as "not judged": V_TWO_BOOK_BRIEF aggregates the flag with
-- COUNTIF(COALESCE(spend_breached, FALSE)), so the moment both families went NULL the Invest total
-- read, verbatim, "All of them are inside their agreed rate and still qualify for launch
-- protection" — of two families spending about 1.9x their sanctioned rates. A withheld verdict that
-- is rendered downstream as a pass is a certification, and Ori's rule for this gate is that it must
-- never certify a family any credible window says is overspending.
--
-- SO THE TWO QUESTIONS ARE SPLIT AND ANSWERED SEPARATELY:
--   · spend_breached / spend_breach_arm answer "IS THE MEASURED RATE ABOVE THE SANCTIONED RATE?"
--     That is ARITHMETIC over a window whose days are named on the row. It carries no claim about
--     when the rate was agreed, it is computed on every window that has data, and it fails closed:
--     NULL only when there is nothing to measure at all.
--   · sanction_adherence_judged answers "CAN THIS BE READ AS ADHERENCE TO THE AGREEMENT?" It is TRUE
--     only when at least one window lies ENTIRELY on or after sanctioned_on — the 7-day window once
--     the sanction is 8 days old, the 28-day window once it is 29 — so a promise is never scored on
--     days it did not cover. Until then no adherence verdict is rendered at all.
-- protection_qualified requires BOTH: a measured non-breach on every window AND a window the
-- sanction actually covered. Withholding therefore only ever makes protection HARDER to earn, which
-- is the direction a fail-closed gate is allowed to be wrong in.
--
-- WHAT THAT COSTS, STATED: a family whose pre-sanction spend was high cannot earn protection until
-- the 28-day window has cleared those days, even if it has complied perfectly since. That is the
-- price of never certifying on a window that says overspending, and it is paid in the safe currency.
-- rate_window_days_before_sanction, short_window_days_before_sanction and sanction_too_new_to_judge
-- ride on the row, rate_window_basis names the count and the sanction date in words, and
-- sanction_verdict says the whole thing in one sentence meant to be read aloud.
--
-- ---------------------------------------------------------------------------------------------
-- WHY THE SHORT WINDOW IS NO LONGER CALLED A "SIGNAL". It was spend_per_day_7d_signal_only, with
-- signal_window_* columns and a basis string ending "direction only. Nothing is judged on this
-- window." Every one of those strings became false the moment the arm was wired, so every one of
-- them changed in the same commit: the columns are spend_per_day_7d and short_window_*, and the
-- basis says what the window now does. spend_rate_direction survives as a WORD (rising / steady /
-- falling), and it too now uses the derived margin instead of a chosen percentage band: the 7-day
-- rate has to sit more than breach_margin_per_day away from the 28-day rate before the word moves
-- off "steady". (Strictly, the standard error of the difference between a 7-day mean and the 28-day
-- mean CONTAINING it is sigma * sqrt(1/7 - 1/28), slightly smaller than the sigma/sqrt(7) used here,
-- so the band is a little wide — the conservative direction for a word.)
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_INVEST_STATUS` AS
WITH
-- ---------------------------------------------------------------------------------------------
-- THE DECLARED TUNABLES. Every number the window design rests on is named here, once, so no reader
-- has to find it inside an expression. Changing one of these changes the measure; nothing else does.
-- ---------------------------------------------------------------------------------------------
k AS (
  SELECT
    28  AS rate_window_days,        -- the LONG binding window: 28 COMPLETE days, always full
    7   AS short_window_days,       -- the SHORT binding window: 7 COMPLETE days. IT ALSO BREACHES.
    90  AS noise_window_days,       -- days of daily spend the day-to-day sigma is estimated from
    10  AS noise_min_days,          -- fewer measured days than this and sigma is not published, which
                                    -- leaves the short arm with a ZERO margin — the fail-closed way
    2.0 AS breach_margin_sigmas,    -- z. The short arm must clear the sanction by z standard errors
                                    -- of a 7-day mean. Same z the 28-day floor is derived at.
    3   AS feed_stale_after_days,   -- a family's ads feed may be this many days behind today before
                                    -- its window stops being certifiable. Same threshold
                                    -- V_DATA_FRESHNESS calls STALE (days_stale > 3), so the two agree.
    200 AS scan_floor_days          -- the guard the window must sit inside. The scan below reaches
                                    -- 201 days back, so this floor is one day INSIDE it and the two
                                    -- can only ever disagree in the safe direction.
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
-- ONE bounded pass over the source the numerator sums, collapsed to family x date so everything
-- below reads a handful of rows instead of re-expanding an ASIN-grain view.
-- THE 201 IS A LITERAL ON PURPOSE: written as an expression over CURRENT_DATE it prunes; read from
-- k it would not. k.scan_floor_days (200) is one day inside it, so the guard can only ever be
-- stricter than the scan, never looser. If you change one, change both, and keep the floor smaller.
u AS (
  SELECT family, date,
         SUM(ad_cost)    AS ad_cost,
         SUM(impressions) AS impressions
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 201 DAY)
  GROUP BY family, date
),
-- THE ACCOUNT'S NEWEST REACHABLE ADS DAY, capped at yesterday (LA). See the header: the cap is
-- deliberately NOT FN_ADS_ANCHOR_CAP(), so the window cannot move at 22:00 LA and the newest day
-- inside it is always at least age 2 and therefore essentially fully settled.
acct AS (
  SELECT LEAST(MAX(IF(ad_cost > 0, date, NULL)),
               DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)) AS feed_end
  FROM u
),
-- THE WINDOW EDGES, ONE ROW, derived once from the tunables so no line quietly re-states a length.
-- With no rows at all this still returns a single all-NULL row, which is what keeps the CROSS JOIN
-- below from deleting families.
win AS (
  SELECT
    a.feed_end,
    DATE_SUB(a.feed_end, INTERVAL 1 DAY)                                  AS win_end,
    DATE_SUB(a.feed_end, INTERVAL k.rate_window_days  DAY)                AS win_start,
    DATE_SUB(a.feed_end, INTERVAL k.short_window_days DAY)                AS sh_start,
    -- the noise window, clamped to the scan floor so days the scan never read cannot enter it as
    -- false zeros and manufacture a step change that inflates sigma
    GREATEST(DATE_SUB(a.feed_end, INTERVAL k.noise_window_days DAY),
             DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL k.scan_floor_days DAY))
                                                                          AS noise_start,
    DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL k.scan_floor_days DAY)
                                                                          AS scan_floor,
    k.rate_window_days                                                    AS win_days,
    k.short_window_days                                                   AS sh_days,
    k.noise_window_days,
    k.noise_min_days,
    k.breach_margin_sigmas,
    k.feed_stale_after_days,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), a.feed_end, DAY)       AS feed_age_days
  FROM acct a CROSS JOIN k
),
-- PER-FAMILY SPEND OVER BOTH WINDOWS, plus the two things staleness needs: that family's own newest
-- ads day, and how many days of the long window carried an ads row for it at all.
fam AS (
  SELECT
    b.family,
    ROUND(SUM(IF(u.date BETWEEN w.win_start AND w.win_end, u.ad_cost, 0)), 2)  AS rate_window_spend,
    ROUND(SUM(IF(u.date BETWEEN w.sh_start  AND w.win_end, u.ad_cost, 0)), 2)  AS short_window_spend,
    COUNTIF(u.date BETWEEN w.win_start AND w.win_end
            AND (u.ad_cost > 0 OR u.impressions > 0))                          AS win_days_with_ads,
    LEAST(MAX(IF(u.ad_cost > 0 OR u.impressions > 0, u.date, NULL)), MAX(w.feed_end))
                                                                               AS family_ads_last_day
  FROM b
  CROSS JOIN win w
  LEFT JOIN u ON u.family = b.family
  GROUP BY b.family
),
-- DAY-TO-DAY NOISE, per family, from FIRST DIFFERENCES over a zero-filled spine. The spine matters:
-- a day with no row is a $0 day, not an absent one, and dropping it would turn a quiet week into a
-- short window of busy days and understate the variation the margin is supposed to cover.
noise AS (
  SELECT
    family,
    STDDEV_SAMP(diff) / SQRT(2)                                                AS daily_spend_sigma,
    COUNT(diff) + 1                                                            AS noise_days_measured
  FROM (
    SELECT
      g.family,
      g.spend - LAG(g.spend) OVER (PARTITION BY g.family ORDER BY g.day)       AS diff
    FROM (
      SELECT b.family, day, COALESCE(SUM(u.ad_cost), 0) AS spend
      FROM b
      CROSS JOIN win w
      CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(w.noise_start, w.win_end)) AS day
      LEFT JOIN u ON u.family = b.family AND u.date = day
      GROUP BY b.family, day
    ) g
  )
  GROUP BY family
),
-- THE MONEY, READ NOT RECOMPUTED. One row per family for the running month, bounded at the orders
-- watermark by the view that owns it.
money AS (
  SELECT family, net_profit AS mtd_net_profit, period_start AS mtd_money_start, period_end AS mtd_money_end
  FROM `onyga-482313.OI.V_FAMILY_PNL`
  WHERE period_label = 'MTD'
),
-- ---------------------------------------------------------------------------------------------
-- EVERYTHING THE GATE NEEDS, ASSEMBLED ONCE. Split from the final SELECT only because BigQuery
-- cannot reference a SELECT alias from the same SELECT, and every one of these is read more than
-- once below.
-- ---------------------------------------------------------------------------------------------
core AS (
  SELECT
    b.family, b.launch_age_months, b.daily_investment, b.monthly_loss_ceiling,
    b.takeover_target_organic_units, b.stop_date, b.sanctioned_on,
    w.feed_end, w.win_start, w.win_end, w.sh_start, w.win_days, w.sh_days,
    w.feed_age_days, w.feed_stale_after_days, w.breach_margin_sigmas,
    w.noise_window_days, w.noise_min_days, w.scan_floor,
    f.win_days_with_ads,
    f.family_ads_last_day,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), f.family_ads_last_day, DAY) AS family_feed_age_days,
    -- IS THE WINDOW INSIDE THE DAYS THIS VIEW ACTUALLY READ? If not, the spend below is a partial
    -- sum dressed as a full one, so it is withheld rather than published.
    (w.win_start >= w.scan_floor)                                              AS win_inside_scan,
    IF(w.win_start >= w.scan_floor, f.rate_window_spend,  NULL)                AS rate_window_spend,
    IF(w.win_start >= w.scan_floor, f.short_window_spend, NULL)                AS short_window_spend,
    -- THE RATES. Divided by the WINDOW LENGTH rather than by the number of days that happen to carry
    -- rows, so a zero-spend day is a zero and not an absence.
    IF(w.win_start >= w.scan_floor,
       ROUND(SAFE_DIVIDE(f.rate_window_spend,  w.win_days), 2), NULL)          AS spend_per_day,
    IF(w.win_start >= w.scan_floor,
       ROUND(SAFE_DIVIDE(f.short_window_spend, w.sh_days),  2), NULL)          AS spend_per_day_7d,
    -- THE NOISE ESTIMATE AND THE MARGIN IT BUYS. A sigma measured on too few days is not published,
    -- and an unpublished sigma leaves a ZERO margin: the short arm then fires on any excess at all,
    -- which is the fail-closed direction.
    -- EACH STEP IS ROUNDED OFF THE STEP THAT IS PUBLISHED, not off the raw value, so a reader can
    -- reproduce the whole chain from the columns: sigma -> sigma/sqrt(7) -> z x that -> + sanction.
    -- Rounding each step off the raw number instead left the published margin a cent away from
    -- z x the published standard error, which is exactly the kind of number that makes a reader
    -- distrust the ones beside it.
    IF(n.noise_days_measured >= w.noise_min_days, ROUND(n.daily_spend_sigma, 2), NULL)
                                                                               AS daily_spend_sigma,
    n.noise_days_measured,
    IF(n.noise_days_measured >= w.noise_min_days,
       ROUND(ROUND(n.daily_spend_sigma, 2) / SQRT(w.sh_days), 2), NULL)        AS short_window_se,
    COALESCE(IF(n.noise_days_measured >= w.noise_min_days,
                ROUND(w.breach_margin_sigmas
                      * ROUND(ROUND(n.daily_spend_sigma, 2) / SQRT(w.sh_days), 2), 2), NULL), 0)
                                                                               AS breach_margin,
    -- HOW MANY DAYS OF EACH WINDOW PRECEDE THE SANCTION. Zero means the arm may judge.
    IF(b.sanctioned_on IS NULL, NULL,
       GREATEST(0, LEAST(DATE_DIFF(b.sanctioned_on, w.win_start, DAY), w.win_days)))
                                                                               AS win_days_pre_sanction,
    IF(b.sanctioned_on IS NULL, NULL,
       GREATEST(0, LEAST(DATE_DIFF(b.sanctioned_on, w.sh_start, DAY), w.sh_days)))
                                                                               AS sh_days_pre_sanction
  FROM b
  CROSS JOIN win w
  LEFT JOIN fam   f ON f.family = b.family
  LEFT JOIN noise n ON n.family = b.family
),
gate AS (
  SELECT
    c.*,
    -- staleness, PER FAMILY, NULL-safe: an unknown age is a stale one
    COALESCE(c.family_feed_age_days > c.feed_stale_after_days, TRUE)           AS family_is_stale,
    COALESCE(c.feed_age_days        > c.feed_stale_after_days, TRUE)           AS account_is_stale,
    c.daily_investment + c.breach_margin                                       AS short_breach_threshold,
    -- ─── THE TWO ARMS: IS THE MEASURED RATE ABOVE THE SANCTIONED RATE? ───
    -- Arithmetic over a named window. NULL only when there is nothing to measure — never because of
    -- when the rate was agreed. See the header: the comparison is always published, the CREDIT for
    -- adherence is what waits for a window the sanction covered.
    IF(c.spend_per_day IS NULL OR c.daily_investment IS NULL, NULL,
       c.spend_per_day > c.daily_investment)                                   AS breached_28d,
    IF(c.spend_per_day_7d IS NULL OR c.daily_investment IS NULL, NULL,
       c.spend_per_day_7d > c.daily_investment + c.breach_margin)              AS breached_7d,
    -- ─── AND CAN EITHER WINDOW BE READ AS ADHERENCE TO THE AGREEMENT? ───
    -- Only a window lying ENTIRELY on or after sanctioned_on can. NULL-safe: no sanction date on
    -- record means no window qualifies.
    COALESCE(c.win_days_pre_sanction = 0, FALSE)                               AS adherence_judged_28d,
    COALESCE(c.sh_days_pre_sanction  = 0, FALSE)                               AS adherence_judged_7d
  FROM core c
),
g2 AS (
  SELECT
    g.*,
    -- SQL's three-valued OR is exactly the rule: TRUE if either arm fires, FALSE only when both arms
    -- were measured and neither fired, NULL only when neither could be measured.
    (g.breached_28d OR g.breached_7d)                                          AS spend_breached,
    CASE
      WHEN COALESCE(g.breached_28d, FALSE) AND COALESCE(g.breached_7d, FALSE) THEN 'both windows'
      WHEN COALESCE(g.breached_28d, FALSE)                                    THEN '28-day window'
      WHEN COALESCE(g.breached_7d,  FALSE)                                    THEN '7-day window only'
      ELSE NULL
    END                                                                        AS spend_breach_arm,
    (g.adherence_judged_28d OR g.adherence_judged_7d)                          AS adherence_judged,
    -- "too new to judge" is a statement about a sanction that EXISTS and is young. A missing
    -- sanctioned_on is a different fault and says so in its own words rather than borrowing this one.
    (NOT (g.adherence_judged_28d OR g.adherence_judged_7d)
     AND g.sanctioned_on IS NOT NULL
     AND g.spend_per_day IS NOT NULL)                                          AS sanction_too_new
  FROM gate g
)
SELECT
  g.family,
  g.launch_age_months,
  IF(g.launch_age_months <= 3, 'RAMP', 'PROOF')                                       AS phase,
  -- THE BINDING SANCTION, and the day it was agreed — nothing before that day is judged against it.
  -- NULL, NEVER ZERO, WHEN THE SPEND IS UNKNOWN. COALESCE(rate, 0) made "we have no data for this
  -- family" read as "it spent nothing", which is the single most flattering reading available and
  -- the one that hands out launch protection for free.
  g.daily_investment,
  g.sanctioned_on,
  -- ─── THE LONG ARM: 28 complete trailing days. ───
  g.rate_window_spend,
  g.spend_per_day,
  ROUND(SAFE_DIVIDE(g.spend_per_day, NULLIF(g.daily_investment, 0)), 2)               AS spend_rate_ratio,
  -- IS THE MEASURED RATE ABOVE THE SANCTIONED RATE ON EITHER WINDOW? TRUE means over on at least one.
  -- FALSE means both windows were measured and neither was over. NULL means NOTHING COULD BE
  -- MEASURED — which is not a pass, and protection_qualified refuses to treat it as one.
  -- spend_breach_arm says WHICH window fired, because the reader's action differs: a 28-day breach is
  -- a standing overspend, a 7-day-only breach is a fresh ramp that can still be stopped cheaply.
  -- THIS IS THE COMPARISON, NOT THE ADHERENCE VERDICT — see sanction_adherence_judged below, and the
  -- header section on why the two are deliberately separate.
  g.spend_breached,
  g.breached_28d                                                                      AS spend_breached_28d,
  g.breached_7d                                                                       AS spend_breached_7d,
  g.spend_breach_arm,
  -- WHICH DAYS THE LONG ARM COVERS: as dates, as a count, and in two ready-made English forms.
  g.win_start                                                                         AS rate_window_start,
  g.win_end                                                                           AS rate_window_end,
  g.win_days                                                                          AS rate_window_days,
  -- THE SPAN IN WORDS, for the column a person reads. Real dates every day of the year, so it can
  -- never drift out of agreement with the numbers beside it, and it says out loud whether this window
  -- is judging anything — and if not, why not.
  CASE WHEN g.win_start IS NULL OR g.win_end IS NULL THEN NULL ELSE CONCAT(
    FORMAT_DATE('%-d %B', g.win_start), ' to ', FORMAT_DATE('%-d %B %Y', g.win_end), ', ',
    CAST(g.win_days AS STRING), ' complete days',
    CASE
      WHEN g.sanctioned_on IS NULL THEN
        ' — but there is no record of when the daily rate was agreed, so nothing is judged on it'
      WHEN g.win_days_pre_sanction > 0 THEN
        CONCAT(' — of which ', CAST(g.win_days_pre_sanction AS STRING),
               IF(g.win_days_pre_sanction = 1, ' falls', ' fall'),
               ' before the daily rate was agreed on ', FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
               ', so the rate below is a comparison against that rate and not a finding that it was broken')
      ELSE ' — the window the agreed daily rate is judged on'
    END,
    IF(NOT g.win_inside_scan,
       '. These days are older than this view reads, so the spend over them is withheld rather than summed short', ''),
    IF(g.family_is_stale,
       CONCAT('. This family\'s advertising figures have not moved for ',
              IFNULL(CAST(g.family_feed_age_days AS STRING), 'an unknown number of'),
              ' days, so nothing can be certified against this window'), ''),
    '.')
  END                                                                                 AS rate_window_basis,
  -- The same window compressed to a clause that drops into the middle of a sentence: "spending
  -- $59.29 a day over the 28 days to 18 August 2026".
  CASE WHEN g.win_end IS NULL THEN NULL ELSE
    CONCAT('over the ', CAST(g.win_days AS STRING), ' days to ', FORMAT_DATE('%-d %B %Y', g.win_end))
  END                                                                                 AS rate_window_phrase,
  g.win_days_pre_sanction                                                             AS rate_window_days_before_sanction,
  -- DIAGNOSTIC ONLY, nothing gates on it: how many of the window's days carried an ads row for this
  -- family. A genuine zero-spend day is a real zero and stays in the denominator either way.
  g.win_days_with_ads                                                                 AS rate_window_days_with_ads_rows,
  -- ─── THE SHORT ARM: 7 complete days, ending on the same day. IT BINDS TOO. ───
  -- A launch stepping up shows here weeks before the 28-day mean catches it, which is the whole
  -- reason it is wired: the long window lags a ramp, and a lagging window certified an overspender.
  g.short_window_spend,
  g.spend_per_day_7d,
  g.short_breach_threshold                                                            AS short_window_breach_threshold_per_day,
  ROUND(SAFE_DIVIDE(g.spend_per_day_7d, NULLIF(g.spend_per_day, 0)), 2)               AS spend_rate_direction_ratio,
  -- The direction WORD, banded by the same derived margin the short arm breaches on, so a word can
  -- no longer claim a move the noise could have produced.
  CASE
    WHEN g.spend_per_day_7d IS NULL OR g.spend_per_day IS NULL             THEN NULL
    WHEN g.spend_per_day_7d > g.spend_per_day + g.breach_margin            THEN 'rising'
    WHEN g.spend_per_day_7d < g.spend_per_day - g.breach_margin            THEN 'falling'
    ELSE 'steady'
  END                                                                                 AS spend_rate_direction,
  g.sh_start                                                                          AS short_window_start,
  g.win_end                                                                           AS short_window_end,
  g.sh_days                                                                           AS short_window_days,
  CASE WHEN g.sh_start IS NULL OR g.win_end IS NULL THEN NULL ELSE CONCAT(
    FORMAT_DATE('%-d %B', g.sh_start), ' to ', FORMAT_DATE('%-d %B %Y', g.win_end), ', ',
    CAST(g.sh_days AS STRING), ' complete days',
    CASE
      WHEN g.sanctioned_on IS NULL THEN
        ' — but there is no record of when the daily rate was agreed, so nothing is judged on it'
      WHEN g.sh_days_pre_sanction > 0 THEN
        CONCAT(' — of which ', CAST(g.sh_days_pre_sanction AS STRING),
               IF(g.sh_days_pre_sanction = 1, ' falls', ' fall'),
               ' before the daily rate was agreed on ', FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
               ', so spending over ', FORMAT('$%.2f', g.short_breach_threshold),
               ' a day here is a comparison against that rate and not yet a finding that it was broken')
      ELSE
        CONCAT(' — a fresh step up shows here first, and spending more than ',
               FORMAT('$%.2f', g.short_breach_threshold),
               ' a day over them is a breach in its own right')
    END, '.')
  END                                                                                 AS short_window_basis,
  g.sh_days_pre_sanction                                                              AS short_window_days_before_sanction,
  -- ─── HOW THE SHORT ARM'S THRESHOLD WAS DERIVED, PUBLISHED SO IT CAN BE CHECKED ───
  -- threshold = the sanctioned rate + z standard errors of a 7-day mean, where the standard error is
  -- sigma / sqrt(7) and sigma is the day-to-day noise estimated from first differences over
  -- noise_window_days zero-filled days. A NULL sigma leaves a zero margin, which is fail-closed.
  g.breach_margin_sigmas,
  g.breach_margin                                                                     AS breach_margin_per_day,
  g.daily_spend_sigma,
  g.short_window_se                                                                   AS short_window_standard_error,
  g.noise_window_days,
  g.noise_days_measured                                                               AS noise_window_days_measured,
  -- ─── HOW OLD THE ADS FEED IS, AND WHETHER THAT IS STILL CERTIFIABLE ───
  -- The account pair is a DIAGNOSTIC: a family can never be fresher than the account, so an
  -- account-wide test would change no row. Reading the two ages side by side is what tells a person
  -- whether the whole feed stopped or just this family.
  g.feed_end                                                                          AS ads_feed_last_day,
  g.feed_age_days                                                                     AS ads_feed_age_days,
  g.account_is_stale                                                                  AS ads_feed_is_stale_account_wide,
  g.family_ads_last_day,
  g.family_feed_age_days                                                              AS family_ads_feed_age_days,
  g.feed_stale_after_days                                                             AS ads_feed_stale_after_days,
  -- THE GATE'S staleness flag, and it is now this family's own.
  g.family_is_stale                                                                   AS rate_window_is_stale,
  g.sanction_too_new                                                                  AS sanction_too_new_to_judge,
  -- CAN ANY PUBLISHED WINDOW BE READ AS ADHERENCE TO THE AGREEMENT? TRUE only when at least one of
  -- them lies entirely on or after sanctioned_on. FALSE is not an accusation and not a pass: it says
  -- the promise is too young to have been kept or broken over a whole window yet.
  g.adherence_judged                                                                  AS sanction_adherence_judged,
  -- ─── THE SANCTION IN ONE SENTENCE, MEANT TO BE READ ALOUD ───
  -- Separate from `verdict`, which answers the other question this view exists for (is the launch
  -- improving). One sentence cannot carry both without one of them being read as the other.
  -- It states the COMPARISON first, because that is the money, and then says whether the comparison
  -- may be read as a broken promise — never the other way round.
  CASE
    WHEN g.daily_investment IS NULL THEN
      CONCAT(g.family, ' has no agreed daily rate on record, so there is nothing to compare its spending with.')
    WHEN g.spend_per_day IS NULL THEN
      CONCAT(g.family, ' has no measurable spend rate right now, so nothing can be said about its ',
             'spending. That is not a pass: it does not qualify for launch protection either.')
    ELSE CONCAT(
      CASE
        WHEN g.spend_breach_arm = '7-day window only' THEN
          CONCAT(g.family, ' has STEPPED UP: ', FORMAT('$%.2f', g.spend_per_day_7d), ' a day over the last ',
                 CAST(g.sh_days AS STRING), ' days against the ', FORMAT('$%.2f', g.daily_investment),
                 ' a day agreed, clear of the ', FORMAT('$%.2f', g.short_breach_threshold),
                 ' a day a run of ', CAST(g.sh_days AS STRING), ' noisy days could reach on its own. The ',
                 CAST(g.win_days AS STRING), '-day rate is still ', FORMAT('$%.2f', g.spend_per_day),
                 ' and has not caught up — this is a fresh ramp, not a standing overspend, and the ',
                 'cheapest moment to stop it.')
        WHEN g.spend_breach_arm IS NOT NULL THEN
          CONCAT(g.family, ' is spending over its agreed rate on ', g.spend_breach_arm, ': ',
                 FORMAT('$%.2f', g.spend_per_day), ' a day over the ', CAST(g.win_days AS STRING),
                 ' days to ', FORMAT_DATE('%-d %B %Y', g.win_end), ' and ',
                 IFNULL(FORMAT('$%.2f', g.spend_per_day_7d), 'an unmeasured amount'),
                 ' a day over the last ', CAST(g.sh_days AS STRING),
                 ', against the ', FORMAT('$%.2f', g.daily_investment), ' a day agreed. ',
                 IF(g.spend_breach_arm = 'both windows',
                    'Both windows are over, so this is a standing overspend and not a fresh step up.',
                    CONCAT('Only the ', CAST(g.win_days AS STRING),
                           '-day window is over — the last ', CAST(g.sh_days AS STRING),
                           ' days sit under the point where a noisy week could reach on its own, ',
                           'so the overspend is older than it is current.')))
        ELSE
          CONCAT(g.family, ' is spending inside its agreed rate on both windows: ',
                 FORMAT('$%.2f', g.spend_per_day), ' a day over the ', CAST(g.win_days AS STRING),
                 ' days to ', FORMAT_DATE('%-d %B %Y', g.win_end), ' and ',
                 IFNULL(FORMAT('$%.2f', g.spend_per_day_7d), 'an unmeasured amount'),
                 ' a day over the last ', CAST(g.sh_days AS STRING), ', against ',
                 FORMAT('$%.2f', g.daily_investment), ' a day agreed.')
      END,
      -- and now, separately, whether that comparison may be read as adherence to the agreement
      CASE
        WHEN g.sanctioned_on IS NULL THEN
          ' There is no record of when that rate was agreed, so this is a comparison only — neither kept nor broken.'
        WHEN NOT g.adherence_judged THEN
          CONCAT(' The rate was only agreed on ', FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
                 ', and no complete window lies inside it yet — ', CAST(g.win_days_pre_sanction AS STRING),
                 ' of the ', CAST(g.win_days AS STRING), ' long-window days and ',
                 CAST(g.sh_days_pre_sanction AS STRING), ' of the ', CAST(g.sh_days AS STRING),
                 ' short-window days fall before it. So this is a comparison, not a finding that the ',
                 'agreement was broken. It does not qualify for launch protection either way: ',
                 'protection is earned on a window the sanction actually covered.')
        WHEN g.spend_breached THEN
          CONCAT(' The rate has been in force since ', FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
                 ', so this is a breach of the agreement.')
        ELSE
          CONCAT(' The rate has been in force since ', FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
                 ', so this is adherence to the agreement.')
      END,
      IF(g.family_is_stale,
         CONCAT(' Read none of it as current: this family\'s advertising figures have not moved for ',
                IFNULL(CAST(g.family_feed_age_days AS STRING), 'an unknown number of'), ' days.'), ''))
  END                                                                                 AS sanction_verdict,
  -- ─── THE LOSS CEILING: A DIFFERENT WINDOW, A DIFFERENT JOB, AND IT DOES NOT BIND ───
  -- Calendar month to date, cut at the ORDERS watermark by V_FAMILY_PNL. Nothing here recomputes it.
  -- The basis string exists so that a reader holding both windows on one row can never take this for
  -- the rate window: one is a monthly allowance, the other is a trailing rate.
  g.monthly_loss_ceiling,
  mo.mtd_net_profit,
  mo.mtd_money_start,
  mo.mtd_money_end,
  IF(mo.mtd_money_start IS NULL OR mo.mtd_money_end IS NULL, NULL,
     CONCAT(FORMAT_DATE('%-d %B', mo.mtd_money_start), ' to ',
            FORMAT_DATE('%-d %B %Y', mo.mtd_money_end),
            ', the part of this calendar month that is measured — a monthly allowance, not the ',
            'spend-rate window, and not what the sanction is judged on'))              AS loss_ceiling_window_basis,
  ROUND(100 * SAFE_DIVIDE(-mo.mtd_net_profit, NULLIF(g.monthly_loss_ceiling, 0)), 1)  AS ceiling_used_pct,
  (-mo.mtd_net_profit >= g.monthly_loss_ceiling)                                      AS ceiling_breached,
  g.stop_date,
  DATE_DIFF(g.stop_date, CURRENT_DATE('America/Los_Angeles'), DAY)                    AS days_left,
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
  -- IT FAILS CLOSED, ON SIX COUNTS. Protection is granted only on POSITIVE evidence of adherence:
  -- inside the sanctioned window, a sanctioned rate on file, a MEASURED non-breach on BOTH windows,
  -- A WINDOW THE SANCTION ACTUALLY COVERED (sanction_adherence_judged — a promise cannot be kept over
  -- days that preceded it), a ceiling on file with a measured loss under it, and A WINDOW THAT IS
  -- STILL CURRENT FOR THIS FAMILY. Any one of those missing and the answer is FALSE. Silence is not
  -- compliance; neither is a frozen feed, and neither is a sanction too new to have been tested.
  -- ---------------------------------------------------------------------------------------------
  -- The outer COALESCE closes the last hole: a family with no stop date on file would otherwise
  -- leave the whole chain NULL, and NULL is not FALSE to a consumer that only tests for FALSE.
  COALESCE(
    CURRENT_DATE('America/Los_Angeles') <= g.stop_date
    AND g.stop_date            IS NOT NULL
    AND g.daily_investment     IS NOT NULL AND g.spend_per_day    IS NOT NULL
    AND g.monthly_loss_ceiling IS NOT NULL AND mo.mtd_net_profit  IS NOT NULL
    AND NOT g.family_is_stale
    AND g.spend_breached       IS NOT NULL AND NOT g.spend_breached
    AND g.adherence_judged
    AND -mo.mtd_net_profit      < g.monthly_loss_ceiling, FALSE)                       AS protection_qualified,
  t.org_m2, t.org_m1, t.org_m0,
  t.tnr_m2, t.tnr_m1, t.tnr_m0,
  t.np_m2,  t.np_m1,  t.np_m0,
  -- the three RAMP trends; NULL-safe so a young family with two months of data still reports
  (t.org_m0 > t.org_m1)                                                               AS organic_units_rising,
  (t.tnr_m0 > t.tnr_m1)                                                               AS net_roas_rising,
  (t.np_m0  > t.np_m1)                                                                AS loss_shrinking,
  g.takeover_target_organic_units,
  CASE
    WHEN g.launch_age_months <= 3 THEN
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
        WHEN g.takeover_target_organic_units IS NULL
          THEN CONCAT('take-over target not set — ', CAST(t.org_m0 AS STRING),
                      ' organic units last complete month, but nothing to judge it against')
        WHEN t.org_m0 >= g.takeover_target_organic_units
          THEN CONCAT('took over — ', CAST(t.org_m0 AS STRING), ' organic units against a target of ', CAST(g.takeover_target_organic_units AS STRING))
        ELSE CONCAT('short of target — ', CAST(t.org_m0 AS STRING), ' of ', CAST(g.takeover_target_organic_units AS STRING), ' organic units, ',
                    CAST(DATE_DIFF(g.stop_date, CURRENT_DATE('America/Los_Angeles'), DAY) AS STRING), ' days left')
      END
  END                                                                                 AS verdict
FROM g2 g
LEFT JOIN trend t  ON t.family = g.family
LEFT JOIN money mo ON mo.family = g.family;
