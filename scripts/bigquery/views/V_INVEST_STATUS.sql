-- =============================================
-- V_INVEST_STATUS — the Invest book: sanctioned spend rate, trajectory, protection state.
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md §5.
--
-- STANDING RULE 0 GOVERNS THIS HEADER. Describe the MECHANISM, publish the QUERY, pin no
-- MEASUREMENT. A measured number written into prose looks verified and rots in silence, so none is
-- written here: every figure a reader might want is either a COLUMN of this view or the output of a
-- query printed below. DECLARED CONSTANTS — numbers a person chose, all of which live in the k CTE
-- — are legitimate and are named. Arithmetic that follows from a declared constant is legitimate
-- and is shown as arithmetic.
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════
-- WHAT THIS VIEW GUARANTEES, AND WHAT IT ONLY DISCLOSES. Read this before quoting the header.
-- ═════════════════════════════════════════════════════════════════════════════════════════════
-- A guarantee a verifier can break in one query is worse than no guarantee, so these are stated as
-- narrowly as the code actually supports them.
--
--   GUARANTEED. When a window's rate is published (rate_window_data_complete TRUE), every DATE in
--     that window arrived in the ACCOUNT's ads feed. Otherwise the rate is NULL and the reason names
--     the missing dates. The two windows are answered independently.
--   GUARANTEED. The rate is always the window's spend divided by the window's LENGTH, never by the
--     number of days that happened to carry rows. rate_window_days is the declared constant 28 on
--     every day of every month; nothing shortens or substitutes a window, ever.
--   GUARANTEED. A window may be called a FINDING against the sanction only if ZERO of its days
--     precede sanctioned_on. Per window, not per family.
--   GUARANTEED. protection_qualified is granted only on positive evidence and never on a NULL.
--
--   NOT GUARANTEED, AND NOT CLAIMED. That this FAMILY's rows for a delivered date arrived. On a
--     delivered date the ads fact cannot separate "was not advertising" from "rows have not landed".
--     At the NEWEST end of the window — where a feed lag actually shows — this is handled by
--     refusing CERTIFICATION on any trailing silent day, so it cannot become a false pass. At the
--     OLDEST end it is DISCLOSED ONLY: family_leading_silent_window_days and a sentence in
--     rate_window_basis. A re-labelled history still zero-fills the front of the window and this
--     view will divide those zeros as real. It says so rather than calling the class closed.
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════
-- THE QUESTION CHANGES WITH AGE (Ori 2026-08-19: "the question of launch products is are they
-- improving — not are they profitable — in the first 3 months").
-- ═════════════════════════════════════════════════════════════════════════════════════════════
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
-- looks like success and is not. Read the shares off the data rather than from any number here:
--   SELECT family, ROUND(100 * SAFE_DIVIDE(SUM(organic_units), NULLIF(SUM(units), 0)), 1) AS organic_pct
--   FROM `onyga-482313.OI.V_UNIFIED_DAILY`
--   WHERE date > DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 90 DAY)
--   GROUP BY family ORDER BY organic_pct DESC
--
-- A USEFUL CONSEQUENCE: trajectory is robust to a level bias. A constant COGS misallocation cancels
-- out of a month-over-month trend, which is why an implausible halo (spec §9.1) does not block the
-- ramp test — though it must be fixed before that family reaches PROOF.
--
-- ═════════════════════════════════════════════════════════════════════════════════════════════
-- THE SANCTION GATE: TWO WINDOWS, EITHER MAY BREACH (Ori's decision, fourth round).
-- ═════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY TWO. A trailing 28-day mean never lies about WHICH days it covers, and it LAGS A STEP UP: for
-- four weeks after a ramp the window still contains the quiet pre-ramp days, so the long arm alone
-- can certify a launch that is currently running far over its sanctioned rate. A 7-day mean sees the
-- step, and is noisy. Neither window is right alone, so:
--
--     spend_breached = (the 28-day rate is over the sanction)
--                   OR (the 7-day rate is over the sanction BY MORE THAN A DERIVED MARGIN)
--
-- WHY THE SHORT ARM NEEDS A MARGIN AND THE LONG ARM DOES NOT. A rate over n days is the mean of n
-- daily spends, so its standard error is sigma / sqrt(n). Over 28 days that error is small next to
-- any overspend worth acting on; over 7 days it is not, and a bare "7-day rate > sanction" test would
-- fire on an ordinary noisy week. So the short arm must clear the sanction by z standard errors of a
-- 7-day mean: margin = z * sigma / sqrt(7), z = k.breach_margin_sigmas.
--
-- z = 2, AND IT IS THE SAME z THE WINDOW LENGTH IS DERIVED AT. The 28-day floor below comes from
-- "the margin must be at least TWO standard errors wide". One measure, one z. Two standard errors of
-- a 7-day mean is a ~2.3% one-sided false-alarm rate on a normal approximation — a 7-day-only breach
-- roughly once in 44 quiet weeks.
--
-- WHICH sigma, AND WHY NOT THE OBVIOUS ONE. sigma must estimate DAY-TO-DAY NOISE. The plain standard
-- deviation of daily spend over a long window does not: on a ramping launch it is dominated by the
-- RAMP ITSELF, so the margin widens exactly when the gate needs to see a step up — the permissive
-- direction, which is the direction every defect on this measure has run in. This view therefore
-- uses the FIRST-DIFFERENCE estimator: sigma = STDDEV_SAMP(spend_t - spend_t-1) / sqrt(2), which is
-- exact for independent daily noise (the variance of a difference is 2 sigma^2) and nearly immune to
-- a level shift, because a step contributes ONE large difference instead of pulling every deviation
-- in the window. Where daily noise is positively autocorrelated it UNDERSTATES sigma, which narrows
-- the margin — the fail-closed direction, and the one to be wrong in. To compare the two estimators
-- on today's data rather than on a remembered figure, run the derivation query further down and set
-- it beside the daily_spend_sigma column this view publishes.
--
-- THE MARGIN IS PUBLISHED, NOT HIDDEN: breach_margin_sigmas (z), daily_spend_sigma,
-- short_window_standard_error, breach_margin_per_day and short_window_breach_threshold_per_day are
-- all columns. A reader can check the whole chain without opening this file.
--
-- WHAT THE TWO ARMS MEAN TO A READER, WHICH IS WHY spend_breach_arm EXISTS. A 28-day breach is a
-- STANDING overspend — it has been going on for weeks and the money is already gone. A 7-day-only
-- breach is a FRESH RAMP — it started recently, the 28-day mean has not caught it yet, and it is the
-- one that can still be stopped cheaply. Different facts, different actions, so the row says which.
--
-- HOW THE RULE IS TESTED. Walk it day by day on real V_UNIFIED_DAILY spend, zero-filled and NOT
-- rescaled: for every simulated today T, feed_end = T - 1, the 28-day window = [feed_end-28,
-- feed_end-1], the 7-day window = [feed_end-7, feed_end-1], sigma re-estimated from the 90
-- zero-filled days ending feed_end-1 — exactly what this view computes. GROUND TRUTH is the family's
-- actual mean daily spend over the 15 days CENTRED on T, and "truly overspending" is that rate above
-- the sanction. FALSE-COMPLIANT = the gate published not-breached while the truth was over; FALSE
-- BREACH = the reverse. The acceptance conditions this design is held to are structural, not
-- measured: the either-window rule must strictly dominate the 28-day-only rule on false-compliant
-- days, and must add NO false breach. There is a floor no window can beat and the honest thing is to
-- state it rather than tune around it — NO window of seven days can see a ramp before seven days of
-- it exist, so the first week of any ramp stays false-compliant on the short arm by construction.
-- The same walk shows the choice of z is not load-bearing across a wide range around 2, which is why
-- z is taken from the derivation above and not from the backtest; the backtest can only say that 2
-- does no harm.
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
-- standard errors wide, i.e. n >= (2 * sigma / (0.6 * S))^2. Run this to re-derive the floor — note
-- it uses the PLAIN standard deviation, which is the conservative (larger n) choice for a window
-- length, and it is also the query that prices the plain-vs-first-difference choice above:
--
--     WITH e AS (SELECT MAX(IF(ad_cost > 0 OR impressions > 0, date, NULL)) AS d
--                FROM `onyga-482313.OI.V_UNIFIED_DAILY`),
--          f AS (SELECT DISTINCT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'INVEST'),
--          g AS (SELECT f.family, day, COALESCE(SUM(u.ad_cost), 0) AS spend
--                FROM e, UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(e.d, INTERVAL 89 DAY), e.d)) AS day
--                CROSS JOIN f
--                LEFT JOIN `onyga-482313.OI.V_UNIFIED_DAILY` u
--                       ON u.family = f.family AND u.date = day
--                GROUP BY 1, 2)
--     SELECT family, ROUND(STDDEV_SAMP(spend), 2) AS plain_sigma FROM g GROUP BY 1
--
-- 28 sits above that floor and is the house 28-day window, so the ladder here is the one the rest of
-- OI reads. The floor is why the window may not be shortened; it is no longer a minimum anything is
-- tested against, because a trailing window can never fall below its own length.
--
-- THE DENOMINATOR IS ELAPSED DAYS, NOT DAYS THAT HAVE ROWS. The divisor is the window length, so a
-- genuine zero-spend day counts as a zero rather than dropping out and inflating the rate. THAT IS
-- ONLY HONEST IF A ZERO CAN BE TOLD FROM A HOLE, which is the next section.
--
-- WHY THE LOSS CEILING IS PUBLISHED BUT DOES NOT DECIDE ANYTHING: the SHAPE, which does not go
-- stale, is that a loss ceiling denominated in NET PROFIT is a loose bound by construction on a
-- product that nearly covers its costs, while the ceiling was backfilled from the sanctioned SPEND
-- rate monthised. The spend rate is what binds. The ceiling clause survives inside
-- protection_qualified ONLY as a catastrophe backstop and as a fail-closed test for missing data: it
-- can make protection harder to earn, never easier.
--
-- ---------------------------------------------------------------------------------------------
-- ONE DEFINITION OF "THE ADS FEED DELIVERED THIS DAY", AND IT IS A PROPERTY OF THE DATE.
--
--     the account's ads fact carries rows for the date  (SUM(Ads_cost) > 0 OR SUM(Ads_impressions) > 0)
--
-- computed ONCE, in acct_day, and read by everything that needs it: the account anchor, the window's
-- delivery count, the hole test and the sigma test. There is no second definition anywhere in this
-- file, and in particular there is no per-family one.
--
-- WHY THE OR IS THE RIGHT PREDICATE. The question is "did this date's advertising data ARRIVE", not
-- "did money move on it". A date of genuinely zero-cost delivery is a date the feed arrived on and
-- nobody spent, and it must be readable as exactly that.
--
-- WHY IT READS THE ADS FACT AND NOT V_UNIFIED_DAILY, EVEN THOUGH V_UNIFIED_DAILY IS WHAT THE
-- NUMERATOR SUMS. V_UNIFIED_DAILY keeps only rows whose advertised ASIN resolves through
-- COALESCE(most_advertised_asin_impressions, advertised_asins, ASIN_BY_CAMPAIGN_NAME) AND whose ASIN
-- joins V_PRODUCT_FAMILY_MAP AND whose date joins DIM_TIME. Every one of those is a FAMILY-LEVEL
-- filter, and the delivery signal exists precisely to be independent of family-level machinery. Read
-- from V_UNIFIED_DAILY, a remapping that unmaps a family would delete dates from the account-level
-- signal — the instrument would move with the very thing it is measuring, and would certify its own
-- hole as "the date never arrived". Read from FACT_AMAZON_ADS it cannot. Whether the two sets agree
-- TODAY is a measurement and not a guarantee; the query that takes it is printed at acct_day.
--
-- THE DIRECTION THIS CHOICE ERRS IN. Calling a date delivered when it was not turns a hole into a
-- zero, still divided by the full window length, and biases the rate DOWN — permissive, the
-- direction every defect this measure has had was in. So the anchor stays LEAST(newest delivered
-- date, yesterday-LA) and the window still ENDS one day before feed_end: the newest date the account
-- delivered is never inside the window it bounds.
--
-- THE CAP IS YESTERDAY (LA), FIXED, AND IT IS DELIBERATELY *NOT* FN_ADS_ANCHOR_CAP(). Its siblings
-- — V_KEYWORD_CONTEXT_LEDGER, V_KEYWORD_CONTEXT_GATE, V_SEASON_CONTEXT — all read
-- LEAST(MAX(date), FN_ADS_ANCHOR_CAP()), and this view did too. That function returns
-- CURRENT_DATE(LA) once the LA hour reaches 22 and CURRENT_DATE(LA) - 1 before it, so TWO READS AN
-- HOUR APART ACROSS 22:00 COULD NAME DIFFERENT 28-DAY SPANS and publish different verdicts on the
-- same calendar day. That is a UI-freshness trade-off and it is the wrong trade for a SANCTION GATE,
-- where the window a verdict is judged on must not move within a day.
-- IT ALSO CARRIES A MEASUREMENT COST, and V_ADS_SETTLE_CURVE prices it. Run
--   SELECT age_days, spend_pct_of_final_median FROM `onyga-482313.OI.V_ADS_SETTLE_CURVE`
--   WHERE channel = 'ALL' AND age_days <= 3
-- and read the age-1 row against the age-2 row. With the FIXED cap the newest day inside the window
-- is always at least age 2; under FN_ADS_ANCHOR_CAP an after-22:00 read could put an age-1 day at the
-- end of the window, and an under-loaded day divided as a whole day biases the rate DOWN — the
-- PERMISSIVE direction, which is the one this view is not allowed to be sloppy in. Both costs are
-- removed by the fixed cap.
--
-- THE NEWEST DELIVERED DAY IS STILL NOT IN THE WINDOW. Day-1 ads are partially loaded and restate for
-- about three days (fact_oi_fresh_ads_data_reading_rules), and a half-loaded day divided as a whole
-- day drags the rate DOWN. So the window ENDS one day before the feed's newest reachable day.
--
-- THE 200-DAY SCAN GUARD GUARDS ITSELF. The scan is anchored on CURRENT_DATE, not on feed_end, so a
-- badly stalled feed can push the window's days off the front of the scan. They would then be summed
-- as ZERO — silently, while the basis string still claimed 28 complete days, and in the permissive
-- direction. The window is therefore tested against the scan floor: if win_start falls outside it,
-- the rate is WITHHELD (NULL, never a partial sum), the basis says so in words, and
-- protection_qualified fails closed. The floor is set one day INSIDE the scan so that the two
-- expressions can only ever disagree in the safe direction.
--
-- ---------------------------------------------------------------------------------------------
-- DELIVERY IS A PROPERTY OF THE DATE. SPEND IS A PROPERTY OF THE FAMILY. THEY ARE NOT ONE QUESTION.
-- ---------------------------------------------------------------------------------------------
--
-- THE DEFECT THIS REPLACES, AND WHY IT KEPT COMING BACK. Earlier cuts inferred delivery from the
-- FAMILY'S OWN SPAN: a window day counted as a real zero if the family had a row on it, OR if the
-- account delivered the day AND the day lay outside that family's [first_ads_day, last_ads_day].
-- That instrument read the very rows it was being asked to report on, and it failed at all three
-- places a window can be damaged:
--
--   TRAILING — a lagging feed withholds a family's NEWEST rows first. last_ads_day moves back, the
--     withheld days fall OUTSIDE the span, and they are therefore summed as delivered real zeros,
--     still divided by 28. A DELIVERY LAG WAS READ AS A DECISION TO STOP ADVERTISING and the rate
--     read LOW. Permissive, like every defect this measure has had.
--   LEADING — any contiguous loss of OLDER rows (a remap that re-labels history, a partial backfill)
--     moves first_ads_day forward and zero-fills the front of the window the same way, with no flag.
--   MIDDLE — a genuine advertising STOP lies INSIDE the span, so every quiet day of it was called a
--     hole and the ENTIRE rate was withheld. A false withhold, on the one shape where an honest
--     number was there to be published. A stop is not a hole.
--
-- THE RULE NOW, AND IT IS TWO QUESTIONS ASKED SEPARATELY:
--
--   (1) HAS THIS DATE ARRIVED? An ACCOUNT-level property of the DATE, derived once in acct_day from
--       FACT_AMAZON_ADS over the whole window, for every family alike. It never consults a family.
--   (2) DID THIS FAMILY SPEND ON A DELIVERED DATE? If the date is delivered and this family has no
--       row on it, the family spent nothing that day. That is a GENUINE ZERO and it belongs in the
--       denominator, exactly as the argument above requires.
--
-- Everything else is a HOLE: a date the ACCOUNT's feed never delivered at all. A window with any hole
-- in it has its spend and its rate WITHHELD — NULL, never a short sum dressed as a full one — and
-- the withheld reason names the missing days BY DATE, not merely by count, so a reader knows which
-- loads to go and look for. protection_qualified fails closed. This is Ori's rule applied literally:
-- when you do not have full window data, do not show a calculated rate.
--
-- THE TWO WINDOWS ARE JUDGED ON THEIR OWN DAYS. A hole in the far end of the 28-day window withholds
-- the long rate and leaves the 7-day rate standing, because the short window's own days all arrived
-- and its rate is a true statement about them. That is the point of having two.
--
-- WHAT THIS RULE COSTS, STATED RATHER THAN HIDDEN, BECAUSE IT IS NOT FREE. On a DELIVERED date this
-- view cannot tell "this family was not advertising" from "this family's rows have not landed yet",
-- and it does not pretend to — no signal in the ads fact separates them. So it does two things
-- instead of guessing: it PUBLISHES the rate (a stop must publish an honest number) and it REFUSES
-- TO CERTIFY the window whenever the family is silent at the newest end of it. See the next section.
--
-- A FAMILY WITH NO ADS DATA AT ALL IS STILL CAUGHT, and by a rule of its own rather than as a side
-- effect of the span logic (O2). A declared INVEST family with no delivered ads row anywhere in the
-- 201-day scan — a launch sanctioned before it starts spending, a family-name mismatch, a mapping
-- that dropped it entirely — has family_ads_data_present FALSE, and BOTH windows are withheld on
-- that ground alone before any day is counted. Without it the LEFT JOIN sums an empty set to 0.0,
-- the row reads $0.00 a day, and $0.00 is under every sanction there is. "No data" is not "spent
-- nothing", here as everywhere else in this file.
--
-- ---------------------------------------------------------------------------------------------
-- TWO CURRENCY TESTS, EACH ANCHORED WHERE ITS OWN QUESTION LIVES (the Q3 off-by-one, closed).
-- ---------------------------------------------------------------------------------------------
--
-- (A) THE ACCOUNT'S FEED AGE, anchored to TODAY, against feed_stale_after_days. "How old is the
--     newest thing anyone knows?" NULL age is stale. This is the only staleness there is now, since
--     delivery is account-level: the per-family staleness test was an instrument for a job that no
--     longer exists.
--
-- (B) THIS FAMILY'S TRAILING SILENCE, anchored to win_end:
--
--         trailing_silent_days = GREATEST(0, win_end - family_ads_last_day)
--
--     win_end is where zero-filling can first begin, so win_end is where the test must start. The
--     OLD test asked (today - family_ads_last_day) > feed_stale_after_days. Since win_end = feed_end
--     - 1 and feed_age_days = today - feed_end,
--
--         today - last = trailing_silent_days + feed_age_days + 1
--
--     so the old flag fired only when trailing_silent_days > feed_stale_after_days - feed_age_days
--     - 1, i.e. at the ordinary feed age of 1, only when trailing_silent_days > 1. A family exactly
--     ONE day silent at the newest end of the window — family feed age 3 — was zero-filled and NOT
--     flagged: a GUARANTEED uncovered band, guaranteed because the two tests counted from different
--     days. Anchoring to win_end removes it with no constant left to tune. ANY trailing silent day
--     is one, and one is enough.
--
-- WHAT (B) DOES AND DOES NOT DO. It does NOT withhold the rate — a genuine stop must publish an
-- honest number, and on delivered dates the zeros are real. It blocks CERTIFICATION only:
-- rate_window_is_stale reads TRUE and protection_qualified fails closed. Refusing protection to a
-- family that spent nothing costs that family nothing. Granting it on rows that had not landed is
-- the failure this measure keeps having.
--
-- LEADING SILENCE IS PUBLISHED AND DOES NOT GATE, and the reason is not squeamishness. A launch that
-- began advertising inside the window has leading silence BY DEFINITION, so gating on it would
-- refuse protection to every real launch on the grounds of being new — not a fail-closed rule, an
-- arbitrary one. family_leading_silent_window_days rides on the row for the reader who suspects a
-- history was re-labelled; this view cannot decide that question and says so.
--
-- WHAT THE GATE DOES WHEN A WINDOW IS NOT CERTIFIABLE: protection_qualified FAILS CLOSED — no
-- protection. A rate whose window is COMPLETE is still PUBLISHED, because it is a true statement
-- about the days it covers, and rate_window_is_stale, rate_window_uncertifiable_reason,
-- family_trailing_silent_window_days, family_ads_last_day, ads_feed_last_day and rate_window_basis
-- all say plainly why it is not certified.
--
-- THE SIGMA IS WITHHELD ON A HOLE TOO, AND IN THE FAIL-CLOSED DIRECTION. The noise window is
-- zero-filled, so a hole in it manufactures a step down and a step up: two large first differences
-- that INFLATE sigma, widen the margin, and make the short arm harder to trip — permissive again. So
-- sigma is published only when every day of the noise window was delivered (and when enough days
-- were measured). An unpublished sigma leaves a ZERO margin, which makes the short arm fire on any
-- excess at all. noise_window_days_undelivered rides on the row so the reason is visible.
--
-- ---------------------------------------------------------------------------------------------
-- A SANCTION CANNOT BE JUDGED ON DAYS IT DID NOT COVER.
--
-- sanctioned_on — the day Ori signed the rate off — lives on DE_LAUNCH_INVESTMENT and is republished
-- by V_BOOK_ASSIGNMENT. Both current sanctions were signed after their launches began, so the
-- trailing window covers stretches of days on which no rate had been agreed. Judging a family
-- against a sanction that did not yet exist is not a defensible verdict, however unflattering the
-- spend.
--
-- SHRINKING THE WINDOW TO FIT THE SANCTION WAS REJECTED OUTRIGHT — rate_window_days must read 28 on
-- every day of every month, and a part-window rate carrying the same column name as a full one is
-- exactly the substitution round 2 was convened to delete.
--
-- WHAT IS WITHHELD IS THE CREDIT, NOT THE COMPARISON, AND THE ASYMMETRY IS THE WHOLE DESIGN.
-- The obvious implementation — withhold spend_breached itself until a full window sits inside the
-- sanction — WAS BUILT, DEPLOYED AND ROLLED BACK, because it is fail-OPEN in practice. NULL does not
-- travel as "not judged": V_TWO_BOOK_BRIEF aggregated the flag with
-- COUNTIF(COALESCE(spend_breached, FALSE)), so the moment both families went NULL the Invest total
-- read, verbatim, "All of them are inside their agreed rate and still qualify for launch protection"
-- — of families spending well over their sanctioned rates. A withheld verdict that is rendered
-- downstream as a pass is a certification, and Ori's rule for this gate is that it must never
-- certify a family any credible window says is overspending.
--
-- SO THE TWO QUESTIONS ARE SPLIT AND ANSWERED SEPARATELY:
--   · spend_breached / spend_breach_arm answer "IS THE MEASURED RATE ABOVE THE SANCTIONED RATE?"
--     That is ARITHMETIC over a window whose days are named on the row. It carries no claim about
--     when the rate was agreed, it is computed on every window whose data is complete, and it fails
--     closed: NULL only when there is nothing to measure at all.
--   · sanction_adherence_judged answers "CAN THIS BE READ AS ADHERENCE TO THE AGREEMENT?" It is TRUE
--     only when at least one window lies ENTIRELY on or after sanctioned_on — the 7-day window once
--     the sanction is 8 days old, the 28-day window once it is 29 — so a promise is never scored on
--     days it did not cover. Until then no adherence verdict is rendered at all.
--
-- FINDING ON THE SHORT WINDOW, COMPARISON ON THE LONG, AND THE RULE IS PER WINDOW (Ori 2026-08-20).
-- A window may carry a FINDING — a verdict that the agreement was broken, which forfeits launch
-- protection — only when ZERO of its days precede sanctioned_on. Otherwise its excess is a
-- COMPARISON: stated in full, convicting nobody.
--
-- WHY PER WINDOW AND NOT PER FAMILY. The two windows roll clean on different days: the 7-day window
-- clears a sanction three weeks before the 28-day one does. The previous cut applied the test to the
-- FAMILY — one flag, sanction_adherence_judged, gating the whole verdict — and that is wrong in both
-- directions at once. It is TOO STRICT before the long window clears: a 7-day window lying wholly
-- inside the sanction, over its rate, could not be called a breach because the 28-day window was not
-- yet judgeable, so the verdict went quiet exactly where Ori wanted one. And it is TOO LOOSE after:
-- once ANY window qualifies, the single flag let a sentence about the OTHER, part-pre-sanction window
-- be read as a finding too. Each arm now answers for its own days and no arm answers for the other's.
--
-- THE COLUMNS: sanction_covers_28d_window / sanction_covers_7d_window say whether each window lies
-- wholly inside the sanction; sanction_finding_28d / sanction_finding_7d are the per-arm findings;
-- sanction_breach_finding is their three-valued OR and sanction_breach_finding_arm names which fired.
-- spend_breached / spend_breached_28d / spend_breached_7d / spend_breach_arm are UNCHANGED and remain
-- the COMPARISON on both arms — the dual-window breach test is not touched by this rule.
-- Whether a given window is a finding or a comparison TODAY depends on the calendar and is therefore
-- a MEASUREMENT, not something to write down here. Read it:
--     SELECT family, sanctioned_on, rate_window_start, short_window_start,
--            rate_window_days_before_sanction, short_window_days_before_sanction,
--            sanction_covers_28d_window, sanction_covers_7d_window,
--            spend_breached_28d, spend_breached_7d,
--            sanction_finding_28d, sanction_finding_7d, sanction_breach_finding_arm
--     FROM `onyga-482313.OI.V_INVEST_STATUS` ORDER BY family
-- protection_qualified requires BOTH: a measured non-breach on every window AND a window the
-- sanction actually covered. Withholding therefore only ever makes protection HARDER to earn, which
-- is the direction a fail-closed gate is allowed to be wrong in.
--
-- WHAT THAT COSTS, STATED: a family whose pre-sanction spend was high cannot earn protection until
-- the 28-day window has cleared those days, even if it has complied perfectly since. That is the
-- price of never certifying on a window that says overspending, and it is paid in the safe currency.
-- rate_window_days_before_sanction, short_window_days_before_sanction and sanction_too_new_to_judge
-- ride on the row, rate_window_basis names the count and the sanction date in words, and
-- sanction_verdict says the whole thing in sentences meant to be read aloud.
--
-- ---------------------------------------------------------------------------------------------
-- ONE ROW PER FAMILY FROM V_BOOK_ASSIGNMENT, GUARDED STRUCTURALLY AND ASSERTED (O3 fix).
--
-- The fam aggregation is a CROSS JOIN of the book assignment against a date spine. N rows for one
-- family in V_BOOK_ASSIGNMENT would multiply that family's window spend by N — silently, on a
-- sanction gate, in whichever direction N points. V_BOOK_ASSIGNMENT is one row per family by design,
-- but "by design" is not a guard. So both:
--   · STRUCTURAL: b is deduplicated to one row per family by a deterministic total order over the
--     whole row (TO_JSON_STRING), never ANY_VALUE — see fact_oi_any_value_pairing_nondeterminism.
--     A duplicate can therefore never multiply a sum.
--   · ASSERTED: book_assignment_rows publishes the count that WAS there, and protection_qualified
--     requires it to be 1. A duplicate assignment cannot be silently resolved into a certification.
-- Check the dependency directly, which is cheaper than trusting either:
--     SELECT COUNTIF(n > 1) AS families_with_duplicate_rows FROM (
--       SELECT family, COUNT(*) AS n FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` GROUP BY family)
--
-- ---------------------------------------------------------------------------------------------
-- WHY THE SHORT WINDOW IS NOT CALLED A "SIGNAL". It was spend_per_day_7d_signal_only, with
-- signal_window_* columns and a basis string ending "direction only. Nothing is judged on this
-- window." Every one of those strings became false the moment the arm was wired, so every one of
-- them changed in the same commit: the columns are spend_per_day_7d and short_window_*, and the
-- basis says what the window now does. spend_rate_direction survives as a WORD (rising / steady /
-- falling), and it bands on THE DERIVED MARGIN — the 7-day rate must sit more than
-- breach_margin_per_day away from the 28-day rate before the word moves off "steady" — not on any
-- chosen percentage. (Strictly, the standard error of the difference between a 7-day mean and the
-- 28-day mean CONTAINING it is sigma * sqrt(1/7 - 1/28), slightly smaller than the sigma/sqrt(7)
-- used here, so the band is a little wide — the conservative direction for a word.)
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
-- THE BOOK ASSIGNMENT, DEDUPLICATED TO ONE ROW PER FAMILY (O3). The dedupe is a deterministic total
-- order over the entire row, so it cannot pair fields from different rows the way ANY_VALUE can, and
-- book_assignment_rows carries the count that was actually there into protection_qualified.
b AS (
  SELECT
    t.*,
    COUNT(*) OVER (PARTITION BY t.family) AS book_assignment_rows
  FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` t
  WHERE t.book = 'INVEST'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY t.family ORDER BY TO_JSON_STRING(t)) = 1
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
-- below reads a handful of rows instead of re-expanding an ASIN-grain view. has_ads_row IS THE ONE
-- DEFINITION OF "THE FEED DELIVERED THIS DAY" IN THIS FILE (O4) — the anchor, the staleness test and
-- the hole test all read it and none of them restates it.
-- THE 201 IS A LITERAL ON PURPOSE: written as an expression over CURRENT_DATE it prunes; read from
-- k it would not. k.scan_floor_days (200) is one day inside it, so the guard can only ever be
-- stricter than the scan, never looser. If you change one, change both, and keep the floor smaller.
u AS (
  SELECT family, date,
         SUM(ad_cost)     AS ad_cost,
         SUM(impressions) AS impressions,
         (SUM(ad_cost) > 0 OR SUM(impressions) > 0)                             AS has_ads_row
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 201 DAY)
  GROUP BY family, date
),
-- ═══ DELIVERY IS A PROPERTY OF THE DATE, NOT OF THE FAMILY ═══════════════════════════════════════
-- ONE ROW PER DATE THE ACCOUNT'S ADS FEED DELIVERED AT ALL. "Has this DATE arrived?" is an
-- account-level question and is answered here, once, for every family alike. "Did THIS FAMILY spend
-- on a delivered date?" is then a separate and unambiguous question, answered in the spine.
--
-- WHY THIS READS THE ADS FACT AND NOT u. u is V_UNIFIED_DAILY, which INNER JOINs
-- V_PRODUCT_FAMILY_MAP and DIM_TIME. Derived from u, the account-level delivery signal would be
-- filtered by exactly the family-level machinery it exists to be independent of: a date whose ads
-- rows all belong to unmapped ASINs, or a remapping that unmaps a family, deletes the date from the
-- signal — and the signal would then certify its own hole as "the date never arrived", or worse,
-- move with the very family whose absence it is being asked to judge. Reading FACT_AMAZON_ADS makes
-- delivery independent of the map, of the family and of DIM_TIME. Whether the two agree TODAY is a
-- measurement, not a guarantee, and this query is how to take it:
--   SELECT COUNTIF(f.day IS NULL) AS only_in_unified, COUNTIF(u.day IS NULL) AS only_in_fact
--   FROM (SELECT date AS day FROM `onyga-482313.OI.FACT_AMAZON_ADS`
--         WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 201 DAY)
--         GROUP BY date HAVING SUM(Ads_cost) > 0 OR SUM(Ads_impressions) > 0) f
--   FULL OUTER JOIN (SELECT date AS day FROM `onyga-482313.OI.V_UNIFIED_DAILY`
--         WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 201 DAY)
--         GROUP BY date HAVING SUM(ad_cost) > 0 OR SUM(impressions) > 0) u USING (day);
--
-- THE PREDICATE IS THE SAME ONE u USES (cost or impressions), and it is the fail-closed direction:
-- calling a date delivered when it was not turns a hole into a zero and biases the rate DOWN, so the
-- test errs towards calling a date UNDELIVERED. The cost of that choice is named and not hidden: an
-- account-wide day on which nothing at all ran is indistinguishable from a day that never loaded,
-- and this view calls it a hole and withholds rather than dividing by it.
acct_day AS (
  SELECT date AS day
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 201 DAY)
  GROUP BY date
  HAVING SUM(Ads_cost) > 0 OR SUM(Ads_impressions) > 0
),
-- EACH FAMILY'S OWN ADVERTISING SPAN INSIDE THE SCAN. Both ends NULL when no delivered ads row for
-- that family has ever reached this view — and a family with no span has no known zero days at all,
-- which is the O2 fix falling out of the O1 rule rather than being bolted on beside it.
span AS (
  SELECT family, MIN(date) AS first_ads_day, MAX(date) AS last_ads_day
  FROM u WHERE has_ads_row GROUP BY family
),
-- THE ACCOUNT'S NEWEST DELIVERED ADS DAY, capped at yesterday (LA). See the header: the cap is
-- deliberately NOT FN_ADS_ANCHOR_CAP(), so the window cannot move at 22:00 LA and the newest day
-- inside it is always at least age 2 and therefore essentially fully settled.
-- It reads acct_day for the same reason acct_day reads the fact: the newest day the ACCOUNT
-- delivered must not be able to move because one family lost its mapping. An empty acct_day still
-- returns one all-NULL row here, so the CROSS JOINs below cannot delete a family.
acct AS (
  SELECT LEAST(MAX(day),
               DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)) AS feed_end
  FROM acct_day
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
-- ONE DAY SPINE, family x every day from noise_start to win_end, carrying the three facts every
-- aggregate below needs: how much was spent, whether this family had a delivered row, and whether
-- the day can be READ AS A REAL ZERO. The long and short windows are both subsets of this spine, so
-- there is one definition of a window day and one definition of delivery.
-- delivered = the ACCOUNT'S feed delivered that date. Nothing else. It does not consult this
-- family's rows, its span, its first day or its last day, because a family's own rows are exactly
-- what is in question when the feed is lagging or a remapping has moved its history: an instrument
-- that reads the thing it is measuring cannot report on it.
--
-- WHAT THE OLD RULE DID AND WHY IT IS GONE. It read delivered as "this family's row arrived, OR the
-- account delivered the day AND the day lies outside this family's own [first_ads_day, last_ads_day]
-- span". That inferred delivery from the family's own span and was wrong at both ends and in the
-- middle: (a) TRAILING — a lagging feed withholds a family's NEWEST rows first, last_ads_day moves
-- back, and the withheld days fell OUTSIDE the span and so were summed as delivered real zeros, still
-- divided by the full window length, so the rate read LOW; (b) LEADING — any contiguous loss of OLDER
-- rows (a remap that re-labels history, a partial backfill) moves first_ads_day forward and the front
-- of the window zero-fills the same way, with no flag at all; (c) MIDDLE — a genuine advertising STOP
-- lies INSIDE the span, so every quiet day of it was called a hole and the whole rate was withheld,
-- which is a false withhold on the one case where an honest number was available.
-- The date-level rule answers all three the same way, and does it without a new dependency.
spine AS (
  SELECT
    b.family,
    w.win_start, w.sh_start, w.win_end,
    day,
    COALESCE(u.ad_cost, 0)                                                     AS spend,
    COALESCE(u.has_ads_row, FALSE)                                             AS family_row,
    (ad.day IS NOT NULL)                                                       AS delivered
  FROM b
  CROSS JOIN win w
  CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(w.noise_start, w.win_end)) AS day
  LEFT JOIN u        ON u.family = b.family AND u.date = day
  LEFT JOIN acct_day ad ON ad.day = day
),
-- PER-FAMILY WINDOW AGGREGATES, all off the one spine. Each window is counted on its own days.
fam AS (
  SELECT
    family,
    ROUND(SUM(IF(day BETWEEN win_start AND win_end, spend, 0)), 2)              AS rate_window_spend,
    ROUND(SUM(IF(day BETWEEN sh_start  AND win_end, spend, 0)), 2)              AS short_window_spend,
    -- DIAGNOSTIC: how many window days carried an ads row for this family at all. Kept because it
    -- separates "quiet" from "missing" to a reader; the GATE reads win_days_delivered, not this.
    COUNTIF(day BETWEEN win_start AND win_end AND family_row)                   AS win_days_with_ads,
    COUNTIF(day BETWEEN win_start AND win_end AND delivered)                    AS win_days_delivered,
    COUNTIF(day BETWEEN sh_start  AND win_end AND delivered)                    AS sh_days_delivered,
    -- WHICH DAYS ARE MISSING, BY NAME. Ori: a withheld window must say which days it is missing, not
    -- only how many. Dates, in order, so a reader can go and look for exactly those loads.
    STRING_AGG(IF(day BETWEEN win_start AND win_end AND NOT delivered,
                  FORMAT_DATE('%-d %B', day), NULL), ', ' ORDER BY day)         AS win_missing_days,
    STRING_AGG(IF(day BETWEEN sh_start  AND win_end AND NOT delivered,
                  FORMAT_DATE('%-d %B', day), NULL), ', ' ORDER BY day)         AS sh_missing_days,
    -- a hole anywhere in the noise window inflates sigma, so it withholds sigma
    COUNTIF(NOT delivered)                                                      AS noise_days_undelivered
  FROM spine
  GROUP BY family
),
-- DAY-TO-DAY NOISE, per family, from FIRST DIFFERENCES over the same zero-filled spine. The spine
-- matters: a day with no row is a $0 day, not an absent one, and dropping it would turn a quiet week
-- into a short window of busy days and understate the variation the margin is supposed to cover.
noise AS (
  SELECT
    family,
    STDDEV_SAMP(diff) / SQRT(2)                                                AS daily_spend_sigma,
    COUNT(diff) + 1                                                            AS noise_days_measured
  FROM (
    SELECT family,
           spend - LAG(spend) OVER (PARTITION BY family ORDER BY day)          AS diff
    FROM spine
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
-- THE RAW MATERIAL AND THE WITHHOLDING DECISION. Split from the publishing layer only because
-- BigQuery cannot reference a SELECT alias from the same SELECT.
-- ---------------------------------------------------------------------------------------------
core AS (
  SELECT
    b.family, b.launch_age_months, b.daily_investment, b.monthly_loss_ceiling,
    b.takeover_target_organic_units, b.stop_date, b.sanctioned_on, b.book_assignment_rows,
    w.feed_end, w.win_start, w.win_end, w.sh_start, w.win_days, w.sh_days,
    w.feed_age_days, w.feed_stale_after_days, w.breach_margin_sigmas,
    w.noise_window_days, w.noise_min_days, w.scan_floor,
    f.rate_window_spend                                                        AS raw_rate_window_spend,
    f.short_window_spend                                                       AS raw_short_window_spend,
    f.win_days_with_ads,
    COALESCE(f.win_days_delivered, 0)                                          AS win_days_delivered,
    COALESCE(f.sh_days_delivered,  0)                                          AS sh_days_delivered,
    f.win_missing_days,
    f.sh_missing_days,
    COALESCE(f.noise_days_undelivered, w.noise_window_days)                    AS noise_days_undelivered,
    n.daily_spend_sigma                                                        AS raw_daily_spend_sigma,
    n.noise_days_measured,
    -- HAS ANY ADS DATA FOR THIS FAMILY EVER REACHED THIS VIEW? FALSE is the O2 shape: no span, so no
    -- day can be read as a real zero and nothing is published as if it could.
    (sp.first_ads_day IS NOT NULL)                                             AS family_ads_data_present,
    LEAST(sp.last_ads_day, w.feed_end)                                         AS family_ads_last_day,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'),
              LEAST(sp.last_ads_day, w.feed_end), DAY)                         AS family_feed_age_days,
    sp.first_ads_day                                                           AS family_ads_first_day,
    -- ─── Q3: THE OFF-BY-ONE, CLOSED BY DERIVATION RATHER THAN BY A NEW CONSTANT ───────────────────
    -- TRAILING SILENCE: the number of window days at the NEWEST end on which this family has no ads
    -- row, counted from win_end — the day zero-filling can first begin — and not from today.
    --   trailing = GREATEST(0, win_end - family_ads_last_day)
    -- THE OLD TEST asked family_feed_age_days > feed_stale_after_days, i.e. (today - last) > 3. Since
    -- win_end = feed_end - 1 and feed_age_days = today - feed_end,
    --   today - last = (win_end - last) + feed_age_days + 1 = trailing + feed_age_days + 1
    -- so the old flag fired only when trailing > 2 - feed_age_days. At the ordinary feed age of 1 that
    -- is trailing > 1: a family exactly ONE day silent at the newest end of the window — family age 3 —
    -- was zero-filled and NOT flagged. That was the guaranteed uncovered band, and it was guaranteed
    -- because the two tests were anchored to different days. Anchoring the test to win_end removes the
    -- band with no constant left to tune: ANY trailing silent day is one, and one is enough.
    -- NULL-safe: a family with no ads day at all is silent for the whole window.
    LEAST(w.win_days,
          GREATEST(0, COALESCE(DATE_DIFF(w.win_end, LEAST(sp.last_ads_day, w.feed_end), DAY),
                               w.win_days)))                                   AS trailing_silent_days,
    -- LEADING SILENCE: the mirror count at the OLDEST end. It is PUBLISHED and it does NOT gate, and
    -- the reason is not squeamishness — it is that a launch which started advertising inside the
    -- window has leading silence BY DEFINITION, so gating on it would refuse protection to every real
    -- launch on the grounds of being new. It is the number a reader checks when a family's history
    -- looks like it moved. See the concerns in the header: on a delivered date this view cannot tell
    -- "was not advertising yet" from "its history was re-labelled", and it does not pretend to.
    LEAST(w.win_days,
          GREATEST(0, COALESCE(DATE_DIFF(sp.first_ads_day, w.win_start, DAY), w.win_days)))
                                                                               AS leading_silent_days,
    -- IS THE WINDOW INSIDE THE DAYS THIS VIEW ACTUALLY READ? NULL-safe: an undefined window is
    -- outside the scan, which is the fail-closed reading.
    COALESCE(w.win_start >= w.scan_floor, FALSE)                               AS win_inside_scan,
    -- ─── WHY A WINDOW'S SPEND IS WITHHELD, IF IT IS. ONE OWNER PER WINDOW, ONE REASON, IN WORDS. ───
    -- NULL means nothing is withheld. Anything else and the spend, the rate and everything derived
    -- from them are NULL — never a short sum dressed as a full one.
    CASE
      WHEN NOT COALESCE(w.win_start >= w.scan_floor, FALSE) THEN
        'the window reaches further back than this view scans, so its spend cannot be summed in full'
      WHEN sp.first_ads_day IS NULL THEN
        CONCAT('no advertising data for this family has ever reached this view, which is not the ',
               'same as this family having spent nothing')
      WHEN COALESCE(f.win_days_delivered, 0) < w.win_days THEN
        CONCAT(CAST(w.win_days - COALESCE(f.win_days_delivered, 0) AS STRING), ' of its ',
               CAST(w.win_days AS STRING),
               ' days never arrived in the account\'s advertising feed at all, so they are holes and ',
               'not zero-spend days, and no rate can be divided across them. The missing days are: ',
               IFNULL(f.win_missing_days, 'unknown'))
      ELSE NULL
    END                                                                        AS rate_withheld_reason,
    CASE
      WHEN NOT COALESCE(w.win_start >= w.scan_floor, FALSE) THEN
        'the window reaches further back than this view scans, so its spend cannot be summed in full'
      WHEN sp.first_ads_day IS NULL THEN
        CONCAT('no advertising data for this family has ever reached this view, which is not the ',
               'same as this family having spent nothing')
      WHEN COALESCE(f.sh_days_delivered, 0) < w.sh_days THEN
        CONCAT(CAST(w.sh_days - COALESCE(f.sh_days_delivered, 0) AS STRING), ' of its ',
               CAST(w.sh_days AS STRING),
               ' days never arrived in the account\'s advertising feed at all, so they are holes and ',
               'not zero-spend days, and no rate can be divided across them. The missing days are: ',
               IFNULL(f.sh_missing_days, 'unknown'))
      ELSE NULL
    END                                                                        AS short_withheld_reason,
    -- HOW MANY DAYS OF EACH WINDOW PRECEDE THE SANCTION. Zero means the arm may judge.
    IF(b.sanctioned_on IS NULL, NULL,
       GREATEST(0, LEAST(DATE_DIFF(b.sanctioned_on, w.win_start, DAY), w.win_days)))
                                                                               AS win_days_pre_sanction,
    IF(b.sanctioned_on IS NULL, NULL,
       GREATEST(0, LEAST(DATE_DIFF(b.sanctioned_on, w.sh_start, DAY), w.sh_days)))
                                                                               AS sh_days_pre_sanction
  FROM b
  CROSS JOIN win w
  LEFT JOIN fam   f  ON f.family  = b.family
  LEFT JOIN noise n  ON n.family  = b.family
  LEFT JOIN span  sp ON sp.family = b.family
),
-- ---------------------------------------------------------------------------------------------
-- WHAT IS ACTUALLY PUBLISHED. A window with a withheld reason publishes NULL for its spend and its
-- rate, and the reason travels with it.
-- ---------------------------------------------------------------------------------------------
pub AS (
  SELECT
    c.*,
    IF(c.rate_withheld_reason  IS NULL, c.raw_rate_window_spend,  NULL)        AS rate_window_spend,
    IF(c.short_withheld_reason IS NULL, c.raw_short_window_spend, NULL)        AS short_window_spend,
    -- THE RATES. Divided by the WINDOW LENGTH rather than by the number of days that happen to carry
    -- rows, so a delivered zero-spend day is a zero and not an absence.
    IF(c.rate_withheld_reason  IS NULL,
       ROUND(SAFE_DIVIDE(c.raw_rate_window_spend,  c.win_days), 2), NULL)      AS spend_per_day,
    IF(c.short_withheld_reason IS NULL,
       ROUND(SAFE_DIVIDE(c.raw_short_window_spend, c.sh_days),  2), NULL)      AS spend_per_day_7d,
    -- THE NOISE ESTIMATE AND THE MARGIN IT BUYS. A sigma measured on too few days, or on a noise
    -- window with a hole in it, is not published, and an unpublished sigma leaves a ZERO margin: the
    -- short arm then fires on any excess at all, which is the fail-closed direction.
    -- EACH STEP IS ROUNDED OFF THE STEP THAT IS PUBLISHED, not off the raw value, so a reader can
    -- reproduce the whole chain from the columns: sigma -> sigma/sqrt(7) -> z x that -> + sanction.
    IF(c.noise_days_measured >= c.noise_min_days AND c.noise_days_undelivered = 0,
       ROUND(c.raw_daily_spend_sigma, 2), NULL)                                AS daily_spend_sigma,
    IF(c.noise_days_measured >= c.noise_min_days AND c.noise_days_undelivered = 0,
       ROUND(ROUND(c.raw_daily_spend_sigma, 2) / SQRT(c.sh_days), 2), NULL)    AS short_window_se,
    COALESCE(IF(c.noise_days_measured >= c.noise_min_days AND c.noise_days_undelivered = 0,
                ROUND(c.breach_margin_sigmas
                      * ROUND(ROUND(c.raw_daily_spend_sigma, 2) / SQRT(c.sh_days), 2), 2), NULL), 0)
                                                                               AS breach_margin
  FROM core c
),
gate AS (
  SELECT
    p.*,
    -- ─── CAN THIS WINDOW BE CERTIFIED AS CURRENT? TWO TESTS, EACH ANCHORED WHERE IT BELONGS. ───
    -- (1) THE ACCOUNT'S FEED AGE against feed_stale_after_days. This is the currency test: it asks
    --     whether the window this view is reporting on is recent enough to act on. It is anchored to
    --     TODAY because that is the question — how old is the newest thing anyone knows.
    -- (2) THIS FAMILY'S TRAILING SILENCE, anchored to win_end. This is the zero-fill test: it asks
    --     whether the newest days of the window are days this family was quiet on, which on a
    --     delivered date is a genuine zero — but is ALSO precisely the signature of this family's own
    --     rows arriving late. The two are indistinguishable in the data, so this view publishes the
    --     rate honestly (a stop is not a hole, and Ori's rule withholds holes, not quiet) and refuses
    --     to CERTIFY it. Refusing protection to a family that spent nothing costs that family nothing;
    --     granting it on rows that had not landed is the failure this whole measure keeps having.
    -- family_is_stale keeps its name because downstream reads it, and it now means exactly what its
    -- consumers use it for: "read none of this as current".
    COALESCE(p.trailing_silent_days > 0, TRUE)                                 AS family_window_silent,
    COALESCE(p.feed_age_days        > p.feed_stale_after_days, TRUE)           AS account_is_stale,
    (COALESCE(p.feed_age_days > p.feed_stale_after_days, TRUE)
     OR COALESCE(p.trailing_silent_days > 0, TRUE))                            AS family_is_stale,
    p.daily_investment + p.breach_margin                                       AS short_breach_threshold,
    -- ─── THE TWO ARMS: IS THE MEASURED RATE ABOVE THE SANCTIONED RATE? ───
    -- Arithmetic over a named window whose days all arrived. NULL only when there is nothing to
    -- measure — never because of when the rate was agreed. See the header: the comparison is always
    -- published, the CREDIT for adherence is what waits for a window the sanction covered.
    IF(p.spend_per_day IS NULL OR p.daily_investment IS NULL, NULL,
       p.spend_per_day > p.daily_investment)                                   AS breached_28d,
    IF(p.spend_per_day_7d IS NULL OR p.daily_investment IS NULL, NULL,
       p.spend_per_day_7d > p.daily_investment + p.breach_margin)              AS breached_7d,
    -- ─── AND CAN EITHER WINDOW BE READ AS ADHERENCE TO THE AGREEMENT? ───
    -- Only a window lying ENTIRELY on or after sanctioned_on can. NULL-safe: no sanction date on
    -- record means no window qualifies.
    COALESCE(p.win_days_pre_sanction = 0, FALSE)                               AS adherence_judged_28d,
    COALESCE(p.sh_days_pre_sanction  = 0, FALSE)                               AS adherence_judged_7d
  FROM pub p
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
    -- ═══ FINDING ON THE SHORT WINDOW, COMPARISON ON THE LONG (Ori 2026-08-20) ═════════════════════
    -- THE RULE IS PER WINDOW, NOT PER FAMILY. A window may carry a FINDING — a verdict that the
    -- agreement was broken and the launch forfeits its protection — only when it lies WHOLLY inside
    -- the sanction, i.e. zero of its days precede sanctioned_on. A window with even one earlier day
    -- yields a COMPARISON: the excess is stated in full, and nobody is convicted on it.
    --
    -- WHY PER WINDOW AND NOT PER FAMILY. The two windows roll clean on different days: the 7-day
    -- window clears the sanction three weeks before the 28-day one does. Withholding the finding until
    -- the FAMILY has any judgeable window, as this view did before, is stricter than the rule and goes
    -- quiet in the wrong direction — it refuses to convict on a short window that IS wholly inside the
    -- sanction, on the grounds that the long one is not. It also does the reverse once one window
    -- qualifies: it lets a sentence about the OTHER, part-pre-sanction window read as a finding.
    -- Each arm now answers for its own days and no arm answers for the other's.
    --
    -- THREE-VALUED ON PURPOSE. NULL means the arm could not be measured, or the sanction does not
    -- wholly cover it — never "no breach". A consumer that tests only for TRUE reads these correctly;
    -- one that tests for FALSE gets NULL and must not treat it as a pass.
    IF(g.adherence_judged_28d, g.breached_28d, NULL)                           AS finding_28d,
    IF(g.adherence_judged_7d,  g.breached_7d,  NULL)                           AS finding_7d,
    (IF(g.adherence_judged_28d, g.breached_28d, NULL)
     OR IF(g.adherence_judged_7d, g.breached_7d, NULL))                        AS breach_finding,
    CASE
      WHEN COALESCE(IF(g.adherence_judged_28d, g.breached_28d, NULL), FALSE)
       AND COALESCE(IF(g.adherence_judged_7d,  g.breached_7d,  NULL), FALSE) THEN 'both windows'
      WHEN COALESCE(IF(g.adherence_judged_28d, g.breached_28d, NULL), FALSE)  THEN '28-day window'
      WHEN COALESCE(IF(g.adherence_judged_7d,  g.breached_7d,  NULL), FALSE)  THEN '7-day window only'
      ELSE NULL
    END                                                                        AS breach_finding_arm,
    -- the same three states as ready-made noun phrases, so no sentence below has to re-derive them
    CASE
      WHEN COALESCE(IF(g.adherence_judged_28d, g.breached_28d, NULL), FALSE)
       AND COALESCE(IF(g.adherence_judged_7d,  g.breached_7d,  NULL), FALSE) THEN 'both windows'
      WHEN COALESCE(IF(g.adherence_judged_28d, g.breached_28d, NULL), FALSE)  THEN 'the 28-day window'
      WHEN COALESCE(IF(g.adherence_judged_7d,  g.breached_7d,  NULL), FALSE)  THEN 'the 7-day window'
      ELSE NULL
    END                                                                        AS breach_finding_arm_phrase,
    CASE
      WHEN g.adherence_judged_28d AND g.adherence_judged_7d THEN 'both windows'
      WHEN g.adherence_judged_28d                           THEN 'the 28-day window'
      WHEN g.adherence_judged_7d                            THEN 'the 7-day window'
      ELSE NULL
    END                                                                        AS judged_arm_phrase,
    CASE
      WHEN NOT g.adherence_judged_28d AND NOT g.adherence_judged_7d THEN 'neither window'
      WHEN NOT g.adherence_judged_28d                               THEN 'the 28-day window'
      WHEN NOT g.adherence_judged_7d                                THEN 'the 7-day window'
      ELSE NULL
    END                                                                        AS unjudged_arm_phrase,
    -- the arms that are JUDGEABLE, MEASURED and NOT OVER — the only ones adherence may be read off.
    -- judged_arm_phrase alone is not enough: a window can be wholly inside the sanction and still have
    -- its rate withheld, and "wholly covered and not over its rate" would then be a claim about a
    -- number that was never published.
    CASE
      WHEN IF(g.adherence_judged_28d, g.breached_28d, NULL) = FALSE
       AND IF(g.adherence_judged_7d,  g.breached_7d,  NULL) = FALSE THEN 'both windows'
      WHEN IF(g.adherence_judged_28d, g.breached_28d, NULL) = FALSE THEN 'the 28-day window'
      WHEN IF(g.adherence_judged_7d,  g.breached_7d,  NULL) = FALSE THEN 'the 7-day window'
      ELSE NULL
    END                                                                        AS clear_arm_phrase,
    -- WHY THIS WINDOW IS NOT CERTIFIABLE, IN WORDS, NAMING THE ACTUAL CAUSE. The old sentence said
    -- "this family's advertising figures have not moved for N days" for every cause alike, which was
    -- wrong twice over: it blamed the family when the whole account feed had stopped, and it counted
    -- from today when the thing at stake begins at win_end. NULL when the window IS certifiable.
    CASE
      WHEN NOT (g.account_is_stale OR g.family_window_silent) THEN NULL
      WHEN g.account_is_stale AND g.family_window_silent THEN
        CONCAT('the account\'s advertising feed is ',
               IFNULL(CAST(g.feed_age_days AS STRING), 'an unknown number of'),
               ' days behind, and this family has no advertising row on the last ',
               IFNULL(CAST(g.trailing_silent_days AS STRING), 'unknown number of'),
               ' days of the window')
      WHEN g.account_is_stale THEN
        CONCAT('the account\'s advertising feed is ',
               IFNULL(CAST(g.feed_age_days AS STRING), 'an unknown number of'), ' days behind')
      ELSE
        CONCAT('this family has no advertising row on the last ',
               IFNULL(CAST(g.trailing_silent_days AS STRING), 'unknown number of'),
               ' days of the window. Those days were delivered by the account, so their zero is ',
               'published as a real zero and the rate above is honest — but a family that went quiet ',
               'at the newest end of the window and a family whose own rows have not landed yet look ',
               'identical here, so the window is reported and not certified')
    END                                                                        AS uncertifiable_phrase,
    -- "too new to judge" is a statement about a sanction that EXISTS and is young. A missing
    -- sanctioned_on is a different fault and says so in its own words rather than borrowing this one.
    (NOT (g.adherence_judged_28d OR g.adherence_judged_7d)
     AND g.sanctioned_on IS NOT NULL
     AND (g.spend_per_day IS NOT NULL OR g.spend_per_day_7d IS NOT NULL))      AS sanction_too_new,
    -- THE SHORT ARM'S BAR, IN WORDS, WRITTEN ONCE AND READ BY EVERY SENTENCE THAT QUOTES IT.
    -- The threshold is the sanctioned rate PLUS the noise margin, and the margin is 0 whenever sigma
    -- was not published (too few measured days, or a hole in the noise window). With a zero margin
    -- the bar IS the sanctioned rate, and calling it "what a noisy week could reach" would print the
    -- same dollar figure twice in one sentence under two different meanings. So the phrase is
    -- decided on the margin rather than written as a fixed form.
    CASE
      WHEN g.daily_investment IS NULL THEN NULL
      WHEN g.breach_margin > 0 THEN
        CONCAT(FORMAT('$%.2f', g.daily_investment + g.breach_margin), ' a day, the point a run of ',
               CAST(g.sh_days AS STRING), ' noisy days could reach on its own')
      ELSE
        CONCAT(FORMAT('$%.2f', g.daily_investment),
               ' a day — the agreed rate itself, because no noise allowance could be measured, ',
               'which makes this arm as strict as it can be rather than as forgiving')
    END                                                                        AS short_bar_phrase
  FROM gate g
)
SELECT
  g.family,
  g.launch_age_months,
  IF(g.launch_age_months <= 3, 'RAMP', 'PROOF')                                       AS phase,
  -- THE BINDING SANCTION, and the day it was agreed — nothing before that day is judged against it.
  g.daily_investment,
  g.sanctioned_on,
  -- HOW MANY ROWS V_BOOK_ASSIGNMENT ACTUALLY HAD FOR THIS FAMILY. One is the invariant; the spend
  -- above is deduplicated so a duplicate can never multiply it, and protection_qualified refuses a
  -- family whose assignment is ambiguous rather than silently picking one of the rows.
  g.book_assignment_rows,
  -- ─── THE LONG ARM: 28 complete trailing days. ───
  g.rate_window_spend,
  g.spend_per_day,
  ROUND(SAFE_DIVIDE(g.spend_per_day, NULLIF(g.daily_investment, 0)), 2)               AS spend_rate_ratio,
  -- IS THE MEASURED RATE ABOVE THE SANCTIONED RATE ON EITHER WINDOW? TRUE means over on at least one.
  -- FALSE means both windows were measured and neither was over. NULL means NOTHING COULD BE
  -- MEASURED — which is not a pass, and protection_qualified refuses to treat it as one.
  -- spend_breach_arm says WHICH window fired, because the reader's action differs: a 28-day breach is
  -- a standing overspend, a 7-day-only breach is a fresh ramp that can still be stopped cheaply.
  -- THIS IS THE COMPARISON, NOT THE ADHERENCE VERDICT — see sanction_adherence_judged below.
  g.spend_breached,
  g.breached_28d                                                                      AS spend_breached_28d,
  g.breached_7d                                                                       AS spend_breached_7d,
  g.spend_breach_arm,
  -- WHICH DAYS THE LONG ARM COVERS: as dates, as a count, and in a ready-made English form.
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
      ELSE IF(g.rate_withheld_reason IS NULL,
              ' — the window the agreed daily rate is judged on',
              ' — the window the agreed daily rate would be judged on')
    END,
    IFNULL(CONCAT('. No rate is published for this window: ', g.rate_withheld_reason), ''),
    IFNULL(CONCAT('. This window is not certifiable: ', g.uncertifiable_phrase), ''),
    -- LEADING SILENCE, SAID OUT LOUD. It does not gate — see the header — but a reader who is not
    -- told cannot check it, and an un-flagged zero-filled front is how the last round's hole hid.
    IF(COALESCE(g.leading_silent_days, 0) > 0,
       CONCAT('. This family has no advertising row on the first ',
              CAST(g.leading_silent_days AS STRING),
              ' days of the window either. On delivered dates that is a real zero and is divided as ',
              'one, and for a launch that began advertising inside the window it is simply the truth ',
              '— but it is also what a re-labelled history looks like, so check it before acting'), ''),
    '.')
  END                                                                                 AS rate_window_basis,
  -- The same window compressed to a clause that drops into the middle of a sentence.
  CASE WHEN g.win_end IS NULL THEN NULL ELSE
    CONCAT('over the ', CAST(g.win_days AS STRING), ' days to ', FORMAT_DATE('%-d %B %Y', g.win_end))
  END                                                                                 AS rate_window_phrase,
  g.win_days_pre_sanction                                                             AS rate_window_days_before_sanction,
  -- ─── HOW MUCH OF EACH WINDOW ACTUALLY ARRIVED (O1/O2). THE GATE READS THESE. ───
  -- days_delivered counts days that can be READ AS A REAL ZERO: the family's data arrived, or the
  -- account's feed delivered the day while the family was outside its own advertising span.
  -- days_with_ads_rows is the older DIAGNOSTIC and still nothing gates on it.
  g.win_days_with_ads                                                                 AS rate_window_days_with_ads_rows,
  g.win_days_delivered                                                                AS rate_window_days_delivered,
  (g.win_days - g.win_days_delivered)                                                 AS rate_window_days_missing,
  -- WHICH days are missing, by date. A count says how bad; the list says where to go and look.
  g.win_missing_days                                                                  AS rate_window_missing_days,
  (g.rate_withheld_reason IS NULL)                                                    AS rate_window_data_complete,
  g.rate_withheld_reason                                                              AS rate_window_withheld_reason,
  g.family_ads_data_present,
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
               IF(g.short_withheld_reason IS NULL,
                  ' a day over them is a breach in its own right',
                  ' a day over them would be a breach in its own right'))
    END,
    IFNULL(CONCAT('. No rate is published for this window: ', g.short_withheld_reason), ''),
    '.')
  END                                                                                 AS short_window_basis,
  g.sh_days_pre_sanction                                                              AS short_window_days_before_sanction,
  g.sh_days_delivered                                                                 AS short_window_days_delivered,
  (g.sh_days - g.sh_days_delivered)                                                   AS short_window_days_missing,
  g.sh_missing_days                                                                   AS short_window_missing_days,
  (g.short_withheld_reason IS NULL)                                                   AS short_window_data_complete,
  g.short_withheld_reason                                                             AS short_window_withheld_reason,
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
  g.noise_days_undelivered                                                            AS noise_window_days_undelivered,
  -- ─── HOW OLD THE ADS FEED IS, AND WHETHER THAT IS STILL CERTIFIABLE ───
  -- The account pair is a DIAGNOSTIC: a family can never be fresher than the account, so an
  -- account-wide test would change no row. Reading the two ages side by side is what tells a person
  -- whether the whole feed stopped or just this family. Neither of them sees a HOLE — that is what
  -- rate_window_days_delivered is for.
  g.feed_end                                                                          AS ads_feed_last_day,
  g.feed_age_days                                                                     AS ads_feed_age_days,
  g.account_is_stale                                                                  AS ads_feed_is_stale_account_wide,
  g.family_ads_last_day,
  g.family_feed_age_days                                                              AS family_ads_feed_age_days,
  g.feed_stale_after_days                                                             AS ads_feed_stale_after_days,
  -- ─── FAMILY SILENCE INSIDE THE WINDOW, ANCHORED TO win_end (Q3) ───────────────────────────────
  -- These count window days with no ads row for this family at the two ends. They are NOT holes:
  -- the account delivered those dates, so the zeros are real and the rate above is published from
  -- them. What trailing silence does is stop the window being CERTIFIED, because a family that went
  -- quiet and a family whose own newest rows have not landed are the same picture. Leading silence
  -- is published and does not gate: a launch that began advertising inside the window has it by
  -- definition, and refusing protection for being new is not a fail-closed rule, it is an arbitrary one.
  g.trailing_silent_days                                                              AS family_trailing_silent_window_days,
  g.leading_silent_days                                                               AS family_leading_silent_window_days,
  g.family_window_silent                                                              AS family_trailing_silence,
  -- THE GATE'S certifiability flag. It keeps its published name because consumers read it, and it
  -- means what they use it for: read none of this as current. It is TRUE when the ACCOUNT feed is
  -- stale, or when this family is silent at the newest end of its own window.
  g.family_is_stale                                                                   AS rate_window_is_stale,
  g.uncertifiable_phrase                                                              AS rate_window_uncertifiable_reason,
  g.sanction_too_new                                                                  AS sanction_too_new_to_judge,
  -- CAN ANY PUBLISHED WINDOW BE READ AS ADHERENCE TO THE AGREEMENT? TRUE only when at least one of
  -- them lies entirely on or after sanctioned_on. FALSE is not an accusation and not a pass: it says
  -- the promise is too young to have been kept or broken over a whole window yet.
  g.adherence_judged                                                                  AS sanction_adherence_judged,
  -- ─── AND PER WINDOW, WHICH IS THE RULE (Ori 2026-08-20) ───────────────────────────────────────
  -- "Finding on the short window, comparison on the long." A window carries a FINDING only when zero
  -- of its days precede sanctioned_on; otherwise its excess is a COMPARISON and convicts nobody.
  -- The two windows roll clean on different days, so the answer is PER WINDOW and not per family:
  -- the 7-day window clears the sanction three weeks before the 28-day one does, and holding its
  -- verdict back until the long window qualifies is stricter than the rule and goes quiet where a
  -- verdict was wanted. spend_breached* above stay the COMPARISON on both arms and are unchanged.
  -- NULL here means "not measurable, or not wholly covered" — never "no breach".
  g.adherence_judged_28d                                                              AS sanction_covers_28d_window,
  g.adherence_judged_7d                                                               AS sanction_covers_7d_window,
  g.finding_28d                                                                       AS sanction_finding_28d,
  g.finding_7d                                                                        AS sanction_finding_7d,
  g.breach_finding                                                                    AS sanction_breach_finding,
  g.breach_finding_arm                                                                AS sanction_breach_finding_arm,
  -- ─── THE SANCTION IN SENTENCES MEANT TO BE READ ALOUD ───
  -- Separate from `verdict`, which answers the other question this view exists for (is the launch
  -- improving). One sentence cannot carry both without one of them being read as the other.
  -- It states the COMPARISON first, because that is the money, and then says whether the comparison
  -- may be read as a broken promise — never the other way round.
  -- EVERY BRANCH BELOW IS GUARDED ON THE VALUES IT FORMATS. FORMAT('$%.2f', NULL) is NULL and one
  -- NULL blanks an entire CONCAT, so a branch that quotes a rate is only reachable when that rate is
  -- published: the withheld-window branches come FIRST and name what is missing instead of quoting it.
  CASE
    WHEN g.daily_investment IS NULL THEN
      CONCAT(g.family, ' has no agreed daily rate on record, so there is nothing to compare its spending with.')
    -- NEITHER WINDOW MEASURABLE. Says what is missing, and says it is not a pass.
    WHEN g.spend_per_day IS NULL AND g.spend_per_day_7d IS NULL THEN
      CONCAT(g.family, ' has no measurable spend rate right now. The ', CAST(g.win_days AS STRING),
             '-day window: ', g.rate_withheld_reason,
             IF(g.short_withheld_reason = g.rate_withheld_reason, '',
                CONCAT('. The ', CAST(g.sh_days AS STRING), '-day window: ', g.short_withheld_reason)),
             '. That is not a pass — nothing about its spending can be said, and it does not qualify ',
             'for launch protection either.')
    -- ONLY THE SHORT WINDOW IS COMPLETE. The long rate is named as withheld, never quoted.
    WHEN g.spend_per_day IS NULL THEN
      CONCAT(
        g.family, ' spent ', FORMAT('$%.2f', g.spend_per_day_7d), ' a day over the last ',
        CAST(g.sh_days AS STRING), ' days, against the ', FORMAT('$%.2f', g.daily_investment),
        ' a day agreed. ',
        IF(COALESCE(g.breached_7d, FALSE),
           CONCAT('That is clear of ', g.short_bar_phrase, ', so the short window is over on its own terms. '),
           CONCAT('That is under ', g.short_bar_phrase, ', so the short window is not over. ')),
        'The ', CAST(g.win_days AS STRING), '-day rate is withheld: ', g.rate_withheld_reason, '.',
        -- PER WINDOW, NOT PER FAMILY: only a window wholly inside the sanction may convict.
        CASE
          WHEN g.sanctioned_on IS NULL THEN
            ' There is no record of when that rate was agreed, so this is a comparison only — neither kept nor broken.'
          WHEN COALESCE(g.breach_finding, FALSE) THEN
            CONCAT(' That is a FINDING and not only a comparison: ', g.breach_finding_arm_phrase,
                   ' lies wholly inside the agreement, in force since ',
                   FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
                   ', so the agreement was broken over days it actually covered.')
          WHEN NOT (g.adherence_judged_28d OR g.adherence_judged_7d) THEN
            CONCAT(' The rate was only agreed on ', FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
                   ', and neither window lies wholly inside it yet, so this is a comparison of the ',
                   'rate against the agreement and not a finding that the agreement was broken.')
          WHEN g.clear_arm_phrase IS NOT NULL THEN
            CONCAT(' The agreement wholly covers ', g.clear_arm_phrase,
                   ', which is not over its rate; the other window is withheld, so the agreement ',
                   'cannot yet be called kept in full.')
          ELSE
            CONCAT(' The agreement wholly covers ', IFNULL(g.judged_arm_phrase, 'a window'),
                   ', but that window\'s rate is withheld, so nothing can be said about whether the ',
                   'agreement was kept — and that is not a pass.')
        END,
        ' It does not qualify for launch protection: protection is earned on windows that arrived in full.')
    -- ONLY THE LONG WINDOW IS COMPLETE. The short rate is named as withheld, never quoted.
    WHEN g.spend_per_day_7d IS NULL THEN
      CONCAT(
        g.family, ' spent ', FORMAT('$%.2f', g.spend_per_day), ' a day over the ',
        CAST(g.win_days AS STRING), ' days to ', FORMAT_DATE('%-d %B %Y', g.win_end),
        ', against the ', FORMAT('$%.2f', g.daily_investment), ' a day agreed. ',
        IF(COALESCE(g.breached_28d, FALSE),
           'That is over the agreed rate on the long window. ',
           'That is inside the agreed rate on the long window. '),
        'The ', CAST(g.sh_days AS STRING), '-day rate is withheld: ', g.short_withheld_reason, '.',
        -- PER WINDOW, NOT PER FAMILY: only a window wholly inside the sanction may convict.
        CASE
          WHEN g.sanctioned_on IS NULL THEN
            ' There is no record of when that rate was agreed, so this is a comparison only — neither kept nor broken.'
          WHEN COALESCE(g.breach_finding, FALSE) THEN
            CONCAT(' That is a FINDING and not only a comparison: ', g.breach_finding_arm_phrase,
                   ' lies wholly inside the agreement, in force since ',
                   FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
                   ', so the agreement was broken over days it actually covered.')
          WHEN NOT (g.adherence_judged_28d OR g.adherence_judged_7d) THEN
            CONCAT(' The rate was only agreed on ', FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
                   ', and neither window lies wholly inside it yet, so this is a comparison of the ',
                   'rate against the agreement and not a finding that the agreement was broken.')
          WHEN g.clear_arm_phrase IS NOT NULL THEN
            CONCAT(' The agreement wholly covers ', g.clear_arm_phrase,
                   ', which is not over its rate; the other window is withheld, so the agreement ',
                   'cannot yet be called kept in full.')
          ELSE
            CONCAT(' The agreement wholly covers ', IFNULL(g.judged_arm_phrase, 'a window'),
                   ', but that window\'s rate is withheld, so nothing can be said about whether the ',
                   'agreement was kept — and that is not a pass.')
        END,
        ' It does not qualify for launch protection: protection is earned on windows that arrived in full.')
    -- BOTH WINDOWS COMPLETE. Both rates are published, so both may be quoted.
    ELSE CONCAT(
      CASE
        WHEN g.spend_breach_arm = '7-day window only' THEN
          CONCAT(g.family, ' has STEPPED UP: ', FORMAT('$%.2f', g.spend_per_day_7d), ' a day over the last ',
                 CAST(g.sh_days AS STRING), ' days against the ', FORMAT('$%.2f', g.daily_investment),
                 ' a day agreed, clear of ', g.short_bar_phrase, '. The ',
                 CAST(g.win_days AS STRING), '-day rate is still ', FORMAT('$%.2f', g.spend_per_day),
                 ' and has not caught up — this is a fresh ramp, not a standing overspend, and the ',
                 'cheapest moment to stop it.')
        WHEN g.spend_breach_arm IS NOT NULL THEN
          CONCAT(g.family, ' is spending over its agreed rate on ',
                 IF(g.spend_breach_arm = 'both windows', 'both windows',
                    CONCAT('the ', g.spend_breach_arm)), ': ',
                 FORMAT('$%.2f', g.spend_per_day), ' a day over the ', CAST(g.win_days AS STRING),
                 ' days to ', FORMAT_DATE('%-d %B %Y', g.win_end), ' and ',
                 FORMAT('$%.2f', g.spend_per_day_7d),
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
                 FORMAT('$%.2f', g.spend_per_day_7d),
                 ' a day over the last ', CAST(g.sh_days AS STRING), ', against ',
                 FORMAT('$%.2f', g.daily_investment), ' a day agreed.')
      END,
      -- and now, separately, whether that comparison may be read as adherence to the agreement
      -- PER WINDOW, NOT PER FAMILY (Ori 2026-08-20): finding on the window the sanction wholly
      -- covers, comparison on the one it does not. Both windows' excesses are stated above either
      -- way; what changes here is only whether an excess may be called a broken promise.
      CASE
        WHEN g.sanctioned_on IS NULL THEN
          ' There is no record of when that rate was agreed, so this is a comparison only — neither kept nor broken.'
        WHEN COALESCE(g.breach_finding, FALSE) THEN
          CONCAT(' That is a FINDING and not only a comparison: ', g.breach_finding_arm_phrase,
                 ' lies wholly inside the agreement, in force since ',
                 FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
                 ', so the agreement was broken over days it actually covered.',
                 IF(g.unjudged_arm_phrase IS NULL OR g.unjudged_arm_phrase = 'neither window', '',
                    CONCAT(' Only ', g.unjudged_arm_phrase, ' still reaches back before that day, so its ',
                           'own figure above stays a comparison.')),
                 ' It does not qualify for launch protection.')
        WHEN NOT (g.adherence_judged_28d OR g.adherence_judged_7d) THEN
          CONCAT(' The rate was only agreed on ', FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
                 ', and neither window lies wholly inside it yet — ', CAST(g.win_days_pre_sanction AS STRING),
                 ' of the ', CAST(g.win_days AS STRING), ' long-window days and ',
                 CAST(g.sh_days_pre_sanction AS STRING), ' of the ', CAST(g.sh_days AS STRING),
                 ' short-window days fall before it. So both figures above are comparisons against the ',
                 'agreed rate, not findings that the agreement was broken. It does not qualify for ',
                 'launch protection either way: protection is earned on a window the sanction ',
                 'actually covered.')
        WHEN g.clear_arm_phrase IS NOT NULL THEN
          CONCAT(' The agreement has been in force since ', FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
                 ' and wholly covers ', g.clear_arm_phrase,
                 ', which is inside the rate, so on the days it covers this is adherence.',
                 IF(g.unjudged_arm_phrase IS NULL OR g.unjudged_arm_phrase = 'neither window', '',
                    CONCAT(' Only ', g.unjudged_arm_phrase, ' still reaches back before that day, so its ',
                           'own figure above stays a comparison.')))
        ELSE
          CONCAT(' The agreement has been in force since ', FORMAT_DATE('%-d %B %Y', g.sanctioned_on),
                 ', but no window it wholly covers could be measured, so nothing can be said about ',
                 'whether it was kept — and that is not a pass.')
      END,
      IFNULL(CONCAT(' It cannot be certified as current: ', g.uncertifiable_phrase, '.'), ''))
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
  -- It was called exemption_live and the name was the problem: "live" reads as "in force", which is
  -- the one thing it does not mean. This column says whether a launch has EARNED protection under
  -- the rules Ori set, never whether any machine is applying it.
  --
  -- This column is a STATEMENT, not yet a control. NOTHING READS IT TO STOP ANYTHING:
  -- V_LAUNCH_EXEMPTION still hardcodes TRUE AS exempt_active, so every launch keeps its protection
  -- whatever this says. Wiring this to the engine is Task 8b, and Task 8b is not built. Until it is,
  -- the only thing standing between an over-sanction launch and the money is a person reading it.
  --
  -- IT FAILS CLOSED, ON EIGHT COUNTS. Protection is granted only on POSITIVE evidence of adherence:
  -- inside the sanctioned window, a sanctioned rate on file, a MEASURED non-breach on BOTH windows,
  -- EVERY DAY OF BOTH WINDOWS DELIVERED BY THE ACCOUNT'S ADS FEED (a hole is not a zero), A WINDOW
  -- THE SANCTION ACTUALLY COVERED (a promise cannot be kept over days that preceded it), a ceiling on
  -- file with a measured loss under it, A CERTIFIABLE WINDOW (the account feed is fresh AND this
  -- family is not silent at the newest end of the window), and EXACTLY ONE BOOK ASSIGNMENT ROW. Any
  -- one of those missing and the answer is FALSE. Silence is not compliance; neither is a frozen
  -- feed, a feed with a hole in it, nor a sanction too new to have been tested.
  --
  -- WHAT THE FOURTH CLAUSE GUARANTEES, EXACTLY, AND WHAT IT DOES NOT. It guarantees that every DATE
  -- in both windows arrived in the ACCOUNT's ads feed. It does NOT guarantee that this family's own
  -- rows for those dates arrived, because on a delivered date nothing in the ads fact separates "this
  -- family was not advertising" from "this family's rows have not landed". That gap is covered where
  -- a lag actually shows — the NEWEST end of the window — by the seventh clause, which refuses
  -- certification on ANY trailing silent day. It is NOT covered at the OLDEST end: a contiguous loss
  -- of older rows on delivered dates still zero-fills the front of the window, and gating on that
  -- would refuse protection to every launch that began advertising inside the window.
  -- family_leading_silent_window_days publishes the count and rate_window_basis says it in words.
  -- Nothing here claims that hole is closed; the honest statement is that it is disclosed.
  -- ---------------------------------------------------------------------------------------------
  -- The outer COALESCE closes the last hole: a family with no stop date on file would otherwise
  -- leave the whole chain NULL, and NULL is not FALSE to a consumer that only tests for FALSE.
  COALESCE(
    CURRENT_DATE('America/Los_Angeles') <= g.stop_date
    AND g.stop_date            IS NOT NULL
    AND g.book_assignment_rows = 1
    AND g.daily_investment     IS NOT NULL AND g.spend_per_day    IS NOT NULL
    AND g.rate_withheld_reason IS NULL     AND g.short_withheld_reason IS NULL
    AND g.monthly_loss_ceiling IS NOT NULL AND mo.mtd_net_profit  IS NOT NULL
    -- NOT certifiable-as-current: the account feed is fresh AND this family is not silent at the
    -- newest end of its own window. Written through the one flag so there is one owner of the test.
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
