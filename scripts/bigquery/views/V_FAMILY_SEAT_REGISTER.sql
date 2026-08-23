-- =============================================
-- V_FAMILY_SEAT_REGISTER — the object Ori reads every morning for the 80/20 doctrine.
-- First-production-night cleanup 2026-08-23 (v27.124): (1) sheet_row — every SEAT and LEAK row
-- publishes what a sheet does with it today (PENDING_BOOK / NEXT_LEAK_BOOK / NEXT_REPRICE_BOOK /
-- REBUILD_LEAK_BOOK / BY_HAND / NO_SHEET_ROW / NONE), so the brief derives its action from what is
-- EXECUTABLE and never from the doctrine status alone (a family can be OUT with nothing to pause,
-- and IN with a pending book waiting). (2) One leak book, one instruction: see leak_book_state —
-- when the pending leak book is stale the register says 'rebuild it' on every leak row and in the
-- family clause, never 'upload this one' beside 'build the next'. B32/B37.
-- Spec: docs/superpowers/specs/2026-08-22-family-seat-register-design.md §3–§6 and
-- architecture/FAMILY_SEAT_REGISTER.md (rulings R-a … R-k). Task 2 of the family seat register;
-- repair pass 2026-08-22 (defects D1–D14: R-f sign-aware stalled proposal, R-g per-family band,
-- R-h parked seats, R-i overdue settling, R-j not yet serving, R-k product targets, three-way
-- queue defense, whole-phrase brand match, two-digit dates, one raise clock, horizon-true counts).
-- Second repair pass 2026-08-22: R-k REFINED — gap rows are worded by their MEASURED cause, the
-- blanket phrase 'the ladder does not track product targets' is retired as false (the ladder
-- tracks SP product targets and this register seats them; the blind spot is rows arriving with
-- keyword_id −1, how SB video / PT product targets reach the warehouse); and the FAMILY 'what
-- closes the gap' sentence is HONEST — when the listed moves recover less than the gap it says
-- they do not close it and names what does (B29).
-- Third repair pass 2026-08-22: the closing promise counts only money a person recovers by doing
-- what the row lists TODAY; the repair dollars had been added to it, so a family could read
-- 'enough to close the gap' off a small executable total and a large re-judged-horizon projection.
-- R-l, 2026-08-22 (the settled gap-closure arithmetic). Only a PAUSE provably takes dollars off
-- the 20% side when the sheet lands: a leak paused, or a failed keyword killed with a pause row.
-- Parking a stalled probe LOWERS its price — the spend does not vanish — so it is its own line,
-- its dollars named as spend at risk of continuing, and it is OUT of the recovered-today total.
-- Re-pricing a repair recovers nothing today by construction: its own line too, named as a change
-- of price whose result arrives at the re-judged horizon. A holdout campaign gets no sheet row, so
-- its rows recover nothing either. The closing sentence then reads in one fixed order — the
-- executable recovery, the gap, a plain closes / does-not-close verdict, what the remaining
-- dollars depend on, and a pointer to that family's re-judged row. No projection may appear inside
-- the recovered-today number, and no sentence may claim a closure its own executable recovery does
-- not deliver. B29 re-derives that figure from the register's OWN per-row costs (never from the
-- sentence) with a stated tolerance; B30 keeps the two non-recovering lines named and excluded;
-- B31 asserts the order.
-- Fifth repair pass 2026-08-23 — R-l carried into the two PROJECTIONS and into the wording:
--   (1) the re-judged horizon no longer zeroes a stalled probe. It used to model parking as
--       taking the spend to $0, which is the very belief R-l retired, in the exact row the today
--       sentence sends the reader to. A stalled probe is now re-priced by the move on its OWN row
--       (R-f: raise to the seat price where the live bid is below it, otherwise park at the
--       engine's park price) and keeps spending at that price on the same linear bid→spend guess
--       the day-one horizon uses; it stays on the 20% side until a verdict arrives (B33).
--   (2) both projections now respect the holdout arm. A campaign in the holdout arm from its
--       eligible_from date gets no sheet row of any kind, so neither day one nor re-judged may
--       book a change for it: its cost on both is its cost today, a repair in one never moves to
--       the good side, and the family clause lists no move for it (B34).
--   (3) the FAMILY row names the book its pauses ride on instead of promising an upload 'today'.
--       Every dollar of the recovered-today figure rides the NEXT BOOK a generator builds — the
--       leak arm tools/build_seat_moves_bulksheet.py for a leak (SHIPPED 2026-08-23), the reprice
--       generator's pause row for a failed keyword — exactly as the LEAK row's own move already
--       says. The arithmetic is untouched; only the promise is (B32).
-- Sixth / seventh repair passes 2026-08-23 — the leak half, and then its wording:
--   (4) the leak arm SHIPPED (tools/build_seat_moves_bulksheet.py), so R-l's own recorded
--       overrule fired: a LEAK reaches $0 on day one and on re-judged EXACTLY where a
--       KEYWORD_PAUSE row for that campaign+keyword sits at PENDING_UPLOAD in
--       FACT_PPC_CHANGE_LOG — per ROW, measured against the log, never per category. A leak no
--       book carries costs what it costs today; a holdout-suppressed leak is never zeroed (B35).
--   (5) the WORDING follows the same measurement. A LEAK already on a pending book is told to
--       upload that batch (named on the row, and published in book_batch_id / book_action) and
--       explicitly NOT to build another — the previous unconditional 'pause it on the next leak
--       book' contradicted the $0 on its own row and would have produced a second batch of the
--       same pause rows. The FAMILY clause splits the same way and the closing sentence reads
--       'the pauses named above' rather than naming one book for all of them (B32).
--
-- WHAT IT SAYS. For every WORKING family (the HARVEST book in V_BOOK_ASSIGNMENT) it groups the
-- verdict ladder's keywords (FACT_KEYWORD_STATE, one snapshot) into plain-language categories,
-- puts each on one side of the doctrine line — the 80% side (winning, at its bar, waiting for a
-- verdict) or the 20% side (losing, probed, stalled, closed-but-spending, untracked) — and prices
-- every category in dollars per day on the basis window: the k.basis_days complete days ending at
-- the ads watermark − 1 (the ladder's own anchor). Launch families (INVEST book) are shown as a
-- labelled reference and never judged on profit. Brand-defense keywords are never judged on
-- profit either: they are a category of their own, outside both sides of the ratio, and the test
-- is three-fold — the ladder's own flag, the campaign-name rule the ladder's source uses
-- (V_BID_CPC_TRANSFER: 'BRAND DEFENSE' in the name), AND the keyword text against the house brand
-- phrases in DIM_BRAND_PHRASES (phrase_type BRAND) — because the ladder's flag misses brand-word
-- keywords in SB campaigns (the Bottle 'happy lolli truth or dare' family of trials). The test is
-- applied to OFF-LADDER keywords too (campaign name and targeting text from the ads rows), so an
-- untracked target in a defense campaign is DEFENSE, never a GAP judged on profit.
--
-- ROW TYPES (row_type), every one carrying a sentence a new reader can act on:
--   FAMILY     one per working family per HORIZON (today · day one · re-judged): the doctrine
--              read — spend basis, the two sides, good_share, doctrine_status (IN ≥ 80%, AT_LINE
--              within k.at_line_band of the line, OUT), allowance, what the seats / leaks / gaps
--              cost, open capacity, over_by. The 'today' row is the measurement; the other two are
--              PROJECTIONS and say so in horizon_assumption.
--   CATEGORY   one per (family, category, horizon) with its dollars per day and side — these sum
--              to the family's spend basis to the cent (asserted).
--   SEAT       one per seat occupant of a working family — numbered by DE_FAMILY_SEAT_LEDGER (the
--              only state the register keeps), with the occupant's kind, bid, cost per day, the
--              move on the pending book if any, the re-judge date, and for a STALLED probe the
--              raise it is parked at (old_bid → new_bid, the date, clicks since) in a sentence
--              worded by the size of the raise (ruling R-c); its proposal branches on the SIGN of
--              (seat price − live bid): raise to the seat price only if the live bid is below it,
--              otherwise park at the engine's published park price (ruling R-f). A settling seat
--              past its due date says it is overdue (ruling R-i). A parked keyword with spend and a
--              re-verdict appointment ahead is a seat, not a leak (ruling R-h).
--   OPEN_SEAT  one per working family: the lowest free seat number, the open capacity, and the
--              next probe candidate from the budget engine's queue the capacity can afford
--              (admission cost = seat price × the engine's daily click goal).
--   LEAK       one per closed-but-spending keyword (PARKED / DEAD with spend in the window).
--   GAP        one per keyword that SPENT on the basis window with no verdict row on the ladder
--              (a keyword with no ladder row and $0 on the basis window is not in the universe).
--              The row is worded by the MEASURED cause (ruling R-k, refined 2026-08-22):
--                keyword_id −1  how SB video / PT product-target rows reach the warehouse — no
--                               keyword id, so no DIM_KEYWORD row can exist and the ladder cannot
--                               see it; extending the pipeline to these rows is a ruling for Ori.
--                paused/archived  the current DIM_KEYWORD row is disabled on Amazon: the spend is
--                               trailing and the row leaves the universe when it stops.
--                enabled        the verdict arrives on the next state run (a newly mapped
--                               campaign, or a target the ladder has not yet swept).
--                anything else  'check why' — a real keyword id with no current DIM_KEYWORD row.
--              The ladder DOES track SP product targets (they live in DIM_KEYWORD and this
--              register seats them); the retired blanket phrase 'the verdict ladder does not
--              track product targets' was false on live rows and appears nowhere (B19).
--   NO_CLOCK   one per trial whose bid moved outside the change log (ruling R-d): 80% side, its
--              own sentence ("no date to judge it from") and move ("log the bid so the clock starts").
--   ABSORB     advisory only: an above-bar campaign in the family capped ≥ k.absorb_capped_days of
--              the last 7 that could take freed spend. Budgets are never moved by this register.
--   REFERENCE  one per launch family: the same categories priced, no doctrine read.
--   UNMAPPED   spend in the cracks (spec §2): one row per campaign that SPENT on the basis window
--              but that no family claims (no T_FAMILY_BAR row and no ladder row with a family), and
--              one total row. Outside every family read, published so nothing is silent; the move
--              is Admin's (map the campaign). Holdout is marked here too.
--
-- CATEGORIES (category ← ladder state, rulings in the SOP):
--   winning                                  WINNER, PACED_WINNER                              80
--   marginal — at its bar                    AT_BAR                                            80
--   waiting — too few clicks yet             TRIAL in no probe position WITH clicks on the window 80
--   waiting — no test clock                  TRIAL whose bid moved with NO applied log row     80  (R-d)
--   waiting — not yet serving                TRIAL in no probe position, $0 and 0 clicks — shown, no side  (R-j)
--   waiting — verdict settling               REVIVED_SETTLING, PENDING_SETTLE (seated, 80 side)  80
--   losing — in repair                       REPRICE                                           20 seat
--   losing — on probation at its floor       FLOOR_PROBATION                                   20 seat
--   losing — failed at its floor             LOSER                                             20 seat
--   probe — being bought at an entry bid     TRIAL engine-listed (T_LIFT_PROBES) or at floor w/ spend  20 seat (R-a)
--   probe — stalled                          TRIAL, standing applied raise past the engine's test  20 seat (R-b, R-c)
--   idle at the floor                        TRIAL at the floor, $0, 0 clicks — shown, no side  (R-e)
--   parked — awaiting re-verdict             PARKED with spend and next_check_date ≥ snapshot  20 seat (R-h)
--   closed but still spending                PARKED past its appointment with spend, DEAD with spend  20 leak
--   untracked — no verdict row               spend on the basis window, no FACT_KEYWORD_STATE row  20 gap
--   brand defense — never judged on profit   see above                                         outside
--   launch — contained                       LAUNCH_CONTAINED (reference families only)        outside
--   Anything else is 'other — <state>' on the 20% side: a family cannot pass by hiding spend.
--
-- HORIZONS (FAMILY / CATEGORY rows, column horizon):
--   today      measured on the basis window; nothing assumed.
--   day one    the PENDING_UPLOAD book lands: each keyword on it spends in proportion to
--              new_bid ÷ old_bid (a linear bid→spend guess, not a measurement); everything else
--              as today. A LEAK reaches $0 here ONLY where a PENDING_UPLOAD pause row for that
--              exact keyword exists (R-l, leak half, after the arm shipped on 2026-08-23:
--              tools/build_seat_moves_bulksheet.py). The credit is checked per row against the
--              change log; a leak no book carries costs here exactly what it costs today.
--   re-judged  repairs hold at their bar and move to the good side at their day-one cost;
--              probation keywords stay on the 20% side at their floor; failed keywords are killed
--              with a pause row the reprice generator builds today (→ $0); A LEAK reaches $0 only
--              where a pending pause row carries it, otherwise it keeps costing; STALLED PROBES ARE
--              RE-PRICED by the move on their own row (R-f's sign branch) and keep spending at that
--              price — parking lowers a price, it does not stop the spend; engine probes and parked
--              seats keep their day-one cost; settling verdicts hold; untracked unchanged.
--   holdout    on BOTH projections (R-l, holdout half): a keyword in a holdout campaign on or after
--              its eligible_from gets no sheet row of any kind, so its cost on either projection is
--              its cost today and a repair in one never moves to the good side.
--   The counts in a projection's sentence are the HORIZON's own (side_h), never today's (D5).
--
-- DECLARED CONSTANTS (the k CTE; Standing Rule 0 exempt — design choices, not measurements):
--   allowance_share 0.20 (the doctrine) · basis_days 7 · context_days 28 · probe_window_days 14
--   and verdict_clicks 20 (the engine's probing test, mirrored from V_KEYWORD_LIFT) ·
--   click_goal_day 4 (V_OOB_KEYWORD's seat model: slots = budget ÷ $4, one 4-click trial a day) ·
--   absorb_capped_days 4 · entry_raise_ratio 1.5 (a raise by half or more is an ENTRY, less is a
--   NUDGE — the wording rule of R-c) · bid_tol 0.005.
--   at_line_band is DERIVED, not declared: the relative noise of a 7-day spend read for the JUDGED
--   family ITSELF — stddev ÷ mean of its own daily spend over the context window, divided by
--   sqrt(basis_days) — one band per family, published on every FAMILY row with its derivation
--   (ruling R-g). The engine's park price (bid_park) is READ from T_OOB_SEAT_ECONOMICS (ruling R-f).
--
-- PLANNER DOCTRINE. Reads FACT_KEYWORD_STATE, T_FAMILY_BAR, FACT_AMAZON_ADS, DE_FAMILY_SEAT_LEDGER,
-- T_LIFT_PROBES, T_OOB_SEAT_ECONOMICS (V_OOB_KEYWORD is a planner-ceiling view that takes minutes;
-- its seat economics are materialised once per pass by SP_REFRESH_CUBE_TABLES), V_CAMPAIGN_CAP_STATE
-- (measured light: tens of MB, seconds), V_PPC_CHANGE_LOG_APPLIED, FACT_PPC_CHANGE_LOG (the
-- PENDING_UPLOAD book only), DIM_KEYWORD (bid versions), DIM_BRAND_PHRASES, DE_HOLDOUT_ASSIGNMENT,
-- V_BOOK_ASSIGNMENT. Never a ceiling view.
--
-- WHAT IT NEVER DOES. No engine reads it. No budget is moved. No bid is set. Every sheet it
-- prescribes is built by a generator and uploaded by Ori. Holdout campaigns are marked on EVERY
-- row that names a campaign (SEAT / LEAK / GAP / NO_CLOCK / ABSORB / OPEN_SEAT / UNMAPPED): from
-- their eligible_from date the move reads 'no sheet row', the absorption advisory is suppressed
-- and the probe queue skips them.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_SEAT_REGISTER` AS
WITH
k AS (
  SELECT 0.20 AS allowance_share, 7 AS basis_days, 28 AS context_days,
         14 AS probe_window_days, 20 AS verdict_clicks, 4 AS click_goal_day,
         4 AS absorb_capped_days, 1.5 AS entry_raise_ratio, 0.005 AS bid_tol),
run_day AS (SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
       FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- the basis window [basis_from, basis_to] and the context window [context_from, basis_to]
win AS (
  SELECT DATE_SUB(wm.d, INTERVAL k.basis_days DAY) AS basis_from,
         DATE_SUB(wm.d, INTERVAL 1 DAY) AS basis_to,
         DATE_SUB(wm.d, INTERVAL k.context_days DAY) AS context_from
  FROM wm CROSS JOIN k),
books AS (SELECT family, book FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT`),
-- campaign → family and the family bar (T_FAMILY_BAR is one row per enabled, mapped campaign)
fam AS (
  SELECT campaign_id, family, keyword_bar, bar_exempt
  FROM `onyga-482313.OI.T_FAMILY_BAR`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY family, keyword_bar) = 1),
-- D9 (2026-08-22): a house brand phrase is matched as a WHOLE phrase on word boundaries, never a
-- bare substring — 'lolli' as a substring would claim 'lolli pop' and 'lolli and pops'. Leading /
-- trailing separators are trimmed off the phrase; regex metacharacters are escaped.
brand AS (SELECT DISTINCT CONCAT(r'\b', REGEXP_REPLACE(TRIM(LOWER(phrase), ' |,'), r'([.*+?^${}()|\[\]\\])', r'\\\1'), r'\b') AS rx
          FROM `onyga-482313.OI.DIM_BRAND_PHRASES`
          WHERE phrase_type = 'BRAND' AND TRIM(LOWER(phrase), ' |,') != ''),
probes AS (SELECT DISTINCT CAST(keyword_id AS STRING) AS kid FROM `onyga-482313.OI.T_LIFT_PROBES`),
holdout AS (
  SELECT unit_id AS campaign_id, MIN(eligible_from) AS eligible_from
  FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
  WHERE unit_type = 'CAMPAIGN' AND arm = 'HOLDOUT'
  GROUP BY 1),
-- the keyword's latest APPLIED bid change — the raise a stalled probe is parked at (R-b)
lastchg AS (
  SELECT campaign_id, keyword_id, action, DATE(applied_at, 'America/Los_Angeles') AS chg_date,
         old_bid, new_bid, batch_id
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE action IN ('INCREASE_BID', 'REDUCE_BID') AND new_bid IS NOT NULL
    AND keyword_id IS NOT NULL AND keyword_id != ''
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY applied_at DESC, change_id DESC) = 1),
-- the pending book: logged at build time, not yet uploaded — the day-one horizon
pending AS (
  SELECT campaign_id, keyword_id, batch_id, action, old_bid, new_bid
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE upload_status = 'PENDING_UPLOAD'
    AND action IN ('INCREASE_BID', 'REDUCE_BID') AND new_bid IS NOT NULL AND old_bid > 0
    AND keyword_id IS NOT NULL AND keyword_id != ''
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY applied_at DESC, change_id DESC) = 1),
-- the pending PAUSE book: KEYWORD_PAUSE rows logged at build time and not yet uploaded. The leak
-- arm (tools/build_seat_moves_bulksheet.py) SHIPPED on 2026-08-23, so a leak's pause row now
-- exists — but only for the leaks a book actually carries. A leak with no row here is credited
-- nothing on either projection: the flip R-l pre-authorised is per ROW, measured, never blanket.
pending_pause AS (
  SELECT campaign_id, keyword_id, batch_id
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE upload_status = 'PENDING_UPLOAD' AND action = 'KEYWORD_PAUSE'
    AND keyword_id IS NOT NULL AND keyword_id != ''
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY applied_at DESC, change_id DESC) = 1),
-- how many distinct bids the keyword has ever carried (DIM_KEYWORD SCD2): > 1 means the bid moved
bidv AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         COUNT(DISTINCT ROUND(bid, 2)) AS bid_versions
  FROM `onyga-482313.OI.DIM_KEYWORD` GROUP BY 1, 2),
-- ENGINE PARITY FOR THE LEAK PAUSE (R-c, added 2026-08-23). The recovered-today figure may only
-- count a pause the leak book will actually WRITE. tools/build_seat_moves_bulksheet.py refuses a
-- leak on four measured grounds — holdout, no readable live state, already switched off in Amazon,
-- and a season BLOCK_CUT. Three of the four are read here; the fourth is NOT, and deliberately.
-- Without this the arithmetic promises dollars no sheet can move: a leak that is already paused in
-- Amazon still carries trailing spend on the basis window, and a pause row for it changes nothing.
--   the live switch: two independent feeds, and a row counts as SERVING only when the ones that
--   exist agree on ENABLED — a disagreement must never read as enabled (the generator's rule).
--   THE SEASON BLOCK_CUT IS NOT READ HERE, AND THE REASON IS MEASURED. V_KEYWORD_CONTEXT_GATE is a
--   ceiling-shaped view: joined into this register it is re-evaluated on every branch that reads a
--   keyword, and the same read that costs 24s without it costs 45-98s with it — the register is
--   the object Ori reads, and tripling it to carry a guard that fires on no row today is the wrong
--   trade (house rule 11's spirit). The guard is enforced OUTSIDE the hot path instead: acceptance
--   check B36 queries the gate ONCE against the executable LEAK set and FAILS if any leak the
--   register counts as recovered is one the generator would refuse on the season ledger. If that
--   check ever fires, the answer is a T_ materialisation of the gate, not an inline join.
kwfeed AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         UPPER(COALESCE(state, '')) AS st
  FROM `onyga-482313.OI.V_SRC_AmazonAds_keyword`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY date DESC) = 1),
-- the keyword's CURRENT DIM_KEYWORD state (R-k refined): the gap cause reads it — a paused or
-- archived row is trailing spend, an enabled row gets its verdict on the next state run
dimk AS (
  SELECT d.cid, d.kid, d.dim_state, kf.st AS feed_state
  FROM (
    SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
           UPPER(state) AS dim_state, keyword_text
    FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current
    QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY effective_from DESC, effective_to DESC) = 1) d
  LEFT JOIN kwfeed kf ON kf.cid = d.cid AND kf.kid = d.kid),
-- the ads scan starts at the context window or the OLDEST standing raise, whichever is earlier,
-- so clicks_since_raise is never truncated by an arbitrary window (Task 1 polish P2)
scan_from AS (
  SELECT LEAST(win.context_from, COALESCE((SELECT MIN(chg_date) FROM lastchg), win.context_from)) AS d
  FROM win),
ads AS (
  SELECT CAST(f.campaign_id AS STRING) AS cid, CAST(f.keyword_id AS STRING) AS kid,
         f.date, f.Ads_cost, f.Ads_clicks, f.GROSS_PROFIT, f.targeting, f.campaign_name
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f CROSS JOIN scan_from CROSS JOIN win
  WHERE f.date >= scan_from.d AND f.date <= win.basis_to
    AND f.keyword_id IS NOT NULL AND f.keyword_id != ''),
kw_ads AS (
  SELECT a.cid, a.kid,
         SUM(IF(a.date >= win.basis_from, a.Ads_cost, 0)) AS spend7,
         SUM(IF(a.date >= win.basis_from, a.Ads_clicks, 0)) AS clicks7,
         SUM(IF(a.date >= win.context_from, a.Ads_cost, 0)) AS spend28,
         SUM(IF(lc.chg_date IS NOT NULL AND a.date > lc.chg_date, a.Ads_clicks, 0)) AS clicks_since_raise,
         ARRAY_AGG(a.targeting ORDER BY a.date DESC, a.targeting LIMIT 1)[OFFSET(0)] AS targeting,
         ARRAY_AGG(a.campaign_name ORDER BY a.date DESC, a.campaign_name LIMIT 1)[OFFSET(0)] AS ads_campaign_name
  FROM ads a CROSS JOIN win
  LEFT JOIN lastchg lc ON lc.campaign_id = a.cid AND lc.keyword_id = a.kid
  GROUP BY 1, 2),
-- campaign read for the absorption advisory: 7-day GP-ROAS against the family bar
camp_ads AS (
  SELECT a.cid, SUM(a.Ads_cost) AS spend7, SUM(a.GROSS_PROFIT) AS gp7
  FROM ads a CROSS JOIN win WHERE a.date >= win.basis_from GROUP BY 1),
-- at_line_band (ruling R-g, 2026-08-22): the relative noise of a 7-day spend read for the JUDGED
-- family itself — stddev ÷ mean of ITS OWN daily spend over the context window ÷ sqrt(basis days),
-- one band per family, published with its derivation on every FAMILY row. Never another family's
-- noise (Bottle's noise must not decide whether LolliME is at the line).
fam_day AS (
  SELECT f.family, a.date, SUM(a.Ads_cost) AS sp
  FROM ads a JOIN fam f ON f.campaign_id = a.cid
  CROSS JOIN win
  WHERE a.date >= win.context_from
  GROUP BY 1, 2),
fam_noise AS (
  SELECT family, AVG(sp) AS mean_day, STDDEV_SAMP(sp) AS sd_day, COUNT(*) AS days_seen
  FROM fam_day GROUP BY 1),
band AS (
  SELECT n.family,
         ROUND(SAFE_DIVIDE(n.sd_day, NULLIF(n.mean_day, 0)) / SQRT(k.basis_days), 3) AS at_line_band,
         FORMAT('at_line_band for %s = (stddev ÷ mean of its OWN daily spend over the %d-day context window, on its %d days with spend) ÷ sqrt(%d basis days) = %.3f — a share within that many points under the 80%% line is indistinguishable from the line on a 7-day read of this family (ruling R-g: each family is judged against its own noise, never another family\'s)',
                n.family, k.context_days, n.days_seen, k.basis_days,
                ROUND(SAFE_DIVIDE(n.sd_day, NULLIF(n.mean_day, 0)) / SQRT(k.basis_days), 3)) AS at_line_band_derivation
  FROM fam_noise n CROSS JOIN k),
brand_hit AS (
  SELECT DISTINCT s.campaign_id, s.keyword_id
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
  JOIN brand b ON REGEXP_CONTAINS(LOWER(s.target_text), b.rx)),
-- the same brand-phrase test on the ads rows, for keywords the ladder does not carry
ads_brand_hit AS (
  SELECT DISTINCT a.cid, a.kid
  FROM kw_ads a JOIN brand b ON REGEXP_CONTAINS(LOWER(COALESCE(a.targeting, '')), b.rx)),
snap AS (
  SELECT s.campaign_id, s.keyword_id, s.family, s.campaign_name, s.target_text, s.match_type,
         s.channel, s.state, s.current_bid, s.bid_floor, COALESCE(s.at_floor, FALSE) AS at_floor,
         s.next_check_date, s.state_since,
         (COALESCE(s.is_brand_defense, FALSE)
          OR REGEXP_CONTAINS(UPPER(COALESCE(s.campaign_name, '')), r'BRAND DEFENSE')
          OR bh.keyword_id IS NOT NULL) AS is_defense
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s CROSS JOIN run_day
  LEFT JOIN brand_hit bh ON bh.campaign_id = s.campaign_id AND bh.keyword_id = s.keyword_id
  WHERE s.snapshot_date = run_day.d),
oob AS (
  SELECT campaign_id, keyword_id, target_text, campaign_name, slots, seat_rank, seat_cpc, role,
         is_defense AS oob_is_defense, bid_park
  FROM `onyga-482313.OI.T_OOB_SEAT_ECONOMICS`),
oob_camp AS (SELECT campaign_id, MAX(seat_cpc) AS seat_cpc, MAX(slots) AS slots FROM oob GROUP BY 1),
-- the engine's park price (R-f): V_OOB_KEYWORD publishes bid_park (one engine-wide value), read
-- through the T_ — never a literal. NULL if the T_ was built before the column existed: the row
-- then reads NULL rather than a guessed price.
park_bid AS (SELECT MAX(bid_park) AS bid_park FROM oob),
-- the three-way defense test on the engine's rows too (D6): the engine flag alone is one-way
oob_brand_hit AS (
  SELECT DISTINCT o.campaign_id, o.keyword_id
  FROM oob o JOIN brand b ON REGEXP_CONTAINS(LOWER(COALESCE(o.target_text, '')), b.rx)),
ledger AS (
  SELECT family, campaign_id, keyword_id, seat_no, opened_on
  FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` WHERE closed_on IS NULL),
-- ── the universe: every keyword in a family campaign that is on the ladder OR SPENT on the basis
--    window (an off-ladder keyword with $0 on the basis window is not a gap and is not counted)
u AS (
  SELECT COALESCE(s.campaign_id, a.cid) AS campaign_id,
         COALESCE(s.keyword_id, a.kid) AS keyword_id,
         COALESCE(s.family, f.family) AS family,
         COALESCE(s.campaign_name, a.ads_campaign_name) AS campaign_name,
         COALESCE(s.target_text, a.targeting) AS target_text,
         s.match_type, s.channel, s.state, s.current_bid, s.bid_floor, COALESCE(s.at_floor, FALSE) AS at_floor,
         s.next_check_date, s.state_since,
         -- brand defense three ways, on and OFF the ladder (house rule 12)
         (COALESCE(s.is_defense, FALSE)
          OR REGEXP_CONTAINS(UPPER(COALESCE(s.campaign_name, a.ads_campaign_name, '')), r'BRAND DEFENSE')
          OR ab.kid IS NOT NULL) AS is_defense,
         s.campaign_id IS NOT NULL AS on_ladder,
         COALESCE(a.spend7, 0) AS spend7, COALESCE(a.clicks7, 0) AS clicks7,
         COALESCE(a.spend28, 0) AS spend28, COALESCE(a.clicks_since_raise, 0) AS clicks_since_raise,
         f.keyword_bar,
         -- a product / category target (asin= / category= expression) — wording only. The ladder
         -- tracks SP product targets (they live in DIM_KEYWORD); the untrackable rows are those
         -- arriving with keyword_id −1 (SB video / PT), whatever the target type (R-k refined).
         REGEXP_CONTAINS(LOWER(COALESCE(s.target_text, a.targeting, '')), r'^\s*(asin|category)\s*=') AS is_product_target
  FROM snap s
  FULL OUTER JOIN kw_ads a ON a.cid = s.campaign_id AND a.kid = s.keyword_id
  LEFT JOIN ads_brand_hit ab ON ab.cid = a.cid AND ab.kid = a.kid
  LEFT JOIN fam f ON f.campaign_id = COALESCE(s.campaign_id, a.cid)
  WHERE COALESCE(s.family, f.family) IS NOT NULL
    AND (s.campaign_id IS NOT NULL OR COALESCE(a.spend7, 0) > 0)),
-- ── spend in the cracks: campaigns that spent on the basis window and that no family claims
camp_basis AS (
  SELECT CAST(f.campaign_id AS STRING) AS cid,
         ARRAY_AGG(f.campaign_name ORDER BY f.date DESC, f.campaign_name LIMIT 1)[OFFSET(0)] AS campaign_name,
         SUM(f.Ads_cost) AS spend7, SUM(f.Ads_clicks) AS clicks7
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f CROSS JOIN win
  WHERE f.date BETWEEN win.basis_from AND win.basis_to
  GROUP BY 1),
unmapped AS (
  SELECT cb.cid AS campaign_id, cb.campaign_name, cb.spend7, cb.clicks7,
         h.campaign_id IS NOT NULL AS holdout, h.eligible_from AS holdout_eligible_from
  FROM camp_basis cb
  LEFT JOIN fam f ON f.campaign_id = cb.cid
  LEFT JOIN (SELECT DISTINCT campaign_id FROM snap WHERE family IS NOT NULL) sf ON sf.campaign_id = cb.cid
  LEFT JOIN holdout h ON h.campaign_id = cb.cid
  WHERE f.campaign_id IS NULL AND sf.campaign_id IS NULL AND cb.spend7 > 0),
-- ── the positions (R-a … R-e) and the code
c AS (
  SELECT u.*, b.book,
         p.kid IS NOT NULL AS engine_probe,
         lc.action AS raise_action, lc.chg_date AS raised_on, lc.old_bid AS raise_old_bid, lc.new_bid AS raise_new_bid,
         pd.batch_id AS book_batch_id, pd.action AS book_action, pd.old_bid AS book_old_bid, pd.new_bid AS book_new_bid,
         pp.batch_id AS pause_batch_id, pp.batch_id IS NOT NULL AS pause_pending,
         COALESCE(bv.bid_versions, 1) AS bid_versions,
         -- R-b: the latest applied change is a raise that still stands (live bid at or above the
         -- logged new_bid — the $1.00 activation floor can lift it past the log — and above old_bid),
         -- aged against the SNAPSHOT date, past the engine's probe window, under the verdict's clicks
         (u.state = 'TRIAL' AND p.kid IS NULL AND NOT u.at_floor
          AND lc.action = 'INCREASE_BID'
          AND u.current_bid >= lc.new_bid - k.bid_tol AND u.current_bid > lc.old_bid + k.bid_tol
          AND lc.chg_date <= DATE_SUB(run_day.d, INTERVAL k.probe_window_days DAY)
          AND COALESCE(u.clicks_since_raise, 0) < k.verdict_clicks) AS stalled,
         -- R-d: the bid moved (more than one bid version in DIM_KEYWORD) with no applied log row,
         -- or moved away from the last logged bid since (a raise the activation floor lifted past
         -- its log still STANDS and is not 'outside the log')
         (COALESCE(bv.bid_versions, 1) > 1
          AND (lc.campaign_id IS NULL
               OR (ABS(u.current_bid - lc.new_bid) > k.bid_tol
                   AND NOT (lc.action = 'INCREASE_BID' AND u.current_bid > lc.new_bid)))) AS moved_outside_log,
         h.eligible_from AS holdout_eligible_from,
         h.campaign_id IS NOT NULL AS holdout,
         oc.seat_cpc AS seat_price, oc.slots AS campaign_slots,
         pb.bid_park,
         run_day.d AS snap_d,
         dk.dim_state,
         -- the live switch, read exactly as the leak book reads it: '' = unreadable in BOTH feeds,
         -- 'ENABLED' only when the ones that exist agree, otherwise the value that disagrees. A
         -- disagreement must never read as enabled — nothing is paused blind.
         CASE WHEN dk.feed_state IS NULL AND dk.dim_state IS NULL THEN ''
              WHEN COALESCE(dk.feed_state, dk.dim_state) = 'ENABLED'
                   AND COALESCE(dk.dim_state, dk.feed_state) = 'ENABLED' THEN 'ENABLED'
              ELSE COALESCE(NULLIF(dk.feed_state, 'ENABLED'), NULLIF(dk.dim_state, 'ENABLED'), 'ENABLED')
         END AS live_state,
         -- the MEASURED gap cause (R-k refined): why an off-ladder spender has no verdict row
         CASE WHEN u.on_ladder THEN CAST(NULL AS STRING)
              WHEN u.keyword_id = '-1' THEN 'NO_ID'
              WHEN dk.dim_state IN ('PAUSED', 'ARCHIVED') THEN 'DISABLED'
              WHEN dk.dim_state = 'ENABLED' THEN 'NEWLY_SEEN'
              ELSE 'UNKNOWN' END AS gap_cause
  FROM u CROSS JOIN k CROSS JOIN run_day CROSS JOIN park_bid pb
  LEFT JOIN books b ON b.family = u.family
  LEFT JOIN probes p ON p.kid = u.keyword_id
  LEFT JOIN lastchg lc ON lc.campaign_id = u.campaign_id AND lc.keyword_id = u.keyword_id
  LEFT JOIN pending pd ON pd.campaign_id = u.campaign_id AND pd.keyword_id = u.keyword_id
  LEFT JOIN pending_pause pp ON pp.campaign_id = u.campaign_id AND pp.keyword_id = u.keyword_id
  LEFT JOIN bidv bv ON bv.cid = u.campaign_id AND bv.kid = u.keyword_id
  LEFT JOIN holdout h ON h.campaign_id = u.campaign_id
  LEFT JOIN oob_camp oc ON oc.campaign_id = u.campaign_id
  LEFT JOIN dimk dk ON dk.cid = u.campaign_id AND dk.kid = u.keyword_id),
coded AS (
  SELECT c.*,
    CASE
      WHEN is_defense                                             THEN 'DEFENSE'
      WHEN NOT on_ladder                                          THEN 'GAP'
      WHEN state IN ('WINNER', 'PACED_WINNER')                    THEN 'WINNING'
      WHEN state = 'AT_BAR'                                       THEN 'MARGINAL'
      WHEN state = 'REPRICE'                                      THEN 'REPAIR'
      WHEN state = 'FLOOR_PROBATION'                              THEN 'PROBATION'
      WHEN state = 'LOSER'                                        THEN 'FAILED'
      WHEN state IN ('REVIVED_SETTLING', 'PENDING_SETTLE')        THEN 'SETTLING'
      WHEN state = 'TRIAL' AND (engine_probe OR (at_floor AND spend7 > 0)) THEN 'PROBE'
      WHEN state = 'TRIAL' AND stalled                            THEN 'STALLED_PROBE'
      WHEN state = 'TRIAL' AND at_floor AND spend7 = 0 AND clicks7 = 0 THEN 'IDLE_FLOOR'
      WHEN state = 'TRIAL' AND moved_outside_log                  THEN 'WAITING_NO_CLOCK'
      -- R-j: 'too few clicks yet' needs clicks; $0 and 0 clicks is not yet serving (no side, $0)
      WHEN state = 'TRIAL' AND spend7 = 0 AND clicks7 = 0         THEN 'WAITING_NOT_SERVING'
      WHEN state = 'TRIAL'                                        THEN 'WAITING'
      -- R-h: parked WITH spend and a re-verdict appointment still ahead = a seat being re-tested
      WHEN state = 'PARKED' AND spend7 > 0 AND next_check_date >= snap_d THEN 'PARKED_SEAT'
      WHEN state IN ('PARKED', 'DEAD') AND spend7 > 0             THEN 'LEAK'
      WHEN state IN ('PARKED', 'DEAD')                            THEN 'CLOSED_QUIET'
      WHEN state = 'LAUNCH_CONTAINED' AND book = 'INVEST'         THEN 'LAUNCH'
      ELSE 'OTHER'
    END AS code
  FROM c),
-- every code mapped to its category sentence, its side and its occupant kind — the one table
codes AS (
  SELECT 'WINNING'          AS code, 'winning'                                AS category, '80'      AS side, NULL          AS occupant_kind, 1  AS cat_order UNION ALL
  SELECT 'MARGINAL',                 'marginal — at its bar',                           '80',         NULL,                           2  UNION ALL
  SELECT 'WAITING',                  'waiting — too few clicks yet',                    '80',         NULL,                           3  UNION ALL
  SELECT 'WAITING_NO_CLOCK',         'waiting — no test clock',                         '80',         NULL,                           4  UNION ALL
  SELECT 'SETTLING',                 'waiting — verdict settling',                      '80',         'settling',                     5  UNION ALL
  SELECT 'REPAIR',                   'losing — in repair',                              '20',         'repair',                       6  UNION ALL
  SELECT 'PROBATION',                'losing — on probation at its floor',              '20',         'probation',                    7  UNION ALL
  SELECT 'FAILED',                   'losing — failed at its floor',                    '20',         'failed',                       8  UNION ALL
  SELECT 'PROBE',                    'probe — being bought at an entry bid',            '20',         'probe',                        9  UNION ALL
  SELECT 'STALLED_PROBE',            'probe — stalled',                                 '20',         'stalled probe',                10 UNION ALL
  SELECT 'PARKED_SEAT',              'parked — awaiting re-verdict',                    '20',         'parked — awaiting re-verdict', 11 UNION ALL
  SELECT 'LEAK',                     'closed but still spending',                       '20',         NULL,                           12 UNION ALL
  SELECT 'GAP',                      'untracked — no verdict row',                      '20',         NULL,                           13 UNION ALL
  SELECT 'OTHER',                    'other — not earning, not being tested',           '20',         NULL,                           14 UNION ALL
  SELECT 'IDLE_FLOOR',               'idle at the floor',                               'NONE',       NULL,                           15 UNION ALL
  SELECT 'WAITING_NOT_SERVING',      'waiting — not yet serving',                       'NONE',       NULL,                           16 UNION ALL
  SELECT 'CLOSED_QUIET',             'closed — not spending',                           'NONE',       NULL,                           17 UNION ALL
  SELECT 'DEFENSE',                  'brand defense — never judged on profit',          'DEFENSE',    NULL,                           18 UNION ALL
  SELECT 'LAUNCH',                   'launch — contained',                              'LAUNCH',     NULL,                           19),
-- ── per-keyword costs on the three horizons
kw AS (
  SELECT d.*, x.category, x.side, x.occupant_kind, x.cat_order,
         l.seat_no, l.opened_on AS seat_opened_on,
         d.spend7 / k.basis_days AS cost_today,
         -- R-l holdout half, applied to BOTH projections: a campaign in the holdout arm from its
         -- eligible_from date gets NO sheet row of any kind, so nothing a generator would have
         -- done to it lands and neither projection may book an improvement from it.
         (d.holdout AND d.snap_d >= d.holdout_eligible_from) AS no_sheet,
         -- the price a stalled probe would carry after the move ITS OWN row proposes (R-f):
         -- raised to the seat price where the live bid is below it, otherwise parked at the
         -- engine's park price. Parking LOWERS a price — it never takes the spend to $0 (R-l).
         CASE WHEN d.seat_price IS NOT NULL AND d.current_bid < d.seat_price - k.bid_tol THEN d.seat_price
              ELSE d.bid_park END AS stalled_proposed_bid,
         -- day one: the pending books land (linear bid→spend) — unless the row is in a holdout
         -- campaign, where no sheet lands and the row is exactly as it is today. A LEAK reaches $0
         -- here ONLY when a pause row for that exact keyword is on a PENDING_UPLOAD book: the leak
         -- arm shipped on 2026-08-23 (R-l's own overrule clause), so the sheet exists — but the
         -- credit is per row and measured against the change log, never a blanket assumption. A
         -- leak no book carries costs what it costs today; one a BID row touches is re-priced by
         -- the same linear guess as any other keyword.
         CASE WHEN d.holdout AND d.snap_d >= d.holdout_eligible_from THEN d.spend7 / k.basis_days
              WHEN d.code = 'LEAK' AND d.pause_pending THEN 0
              WHEN d.book_new_bid IS NOT NULL THEN d.spend7 / k.basis_days * SAFE_DIVIDE(d.book_new_bid, d.book_old_bid)
              ELSE d.spend7 / k.basis_days END AS cost_day1,
         x.side AS side_day1,
         -- re-judged: repairs hold at their bar (good side), probation at its floor, failed killed
         -- (a kill IS a pause → $0, and the SHIPPED generator builds that row for a LOSER today);
         -- A LEAK reaches $0 only where a pause row for it is on a PENDING_UPLOAD book (the leak
         -- arm, shipped 2026-08-23); a leak no book carries keeps costing; STALLED PROBES RE-PRICED:
         -- the move on their row is 'raise to the seat price' or 'park at the engine's park price',
         -- and both leave the keyword serving, so the spend continues at the proposed price (the
         -- same linear bid→spend guess the day-one horizon uses). Probes and settling hold,
         -- untracked unchanged; a holdout-suppressed row is unchanged on every count.
         CASE WHEN d.holdout AND d.snap_d >= d.holdout_eligible_from THEN d.spend7 / k.basis_days
              WHEN d.code = 'FAILED' THEN 0
              WHEN d.code = 'LEAK' THEN IF(d.pause_pending, 0, d.spend7 / k.basis_days)
              WHEN d.code = 'STALLED_PROBE' THEN d.spend7 / k.basis_days
                   * COALESCE(SAFE_DIVIDE(CASE WHEN d.seat_price IS NOT NULL AND d.current_bid < d.seat_price - k.bid_tol THEN d.seat_price
                                               ELSE d.bid_park END, NULLIF(d.current_bid, 0)), 1)
              WHEN d.code = 'PROBATION' THEN d.spend7 / k.basis_days
                   * COALESCE(SAFE_DIVIDE(LEAST(COALESCE(d.book_new_bid, d.current_bid), d.current_bid), NULLIF(d.current_bid, 0)), 1)
              WHEN d.book_new_bid IS NOT NULL THEN d.spend7 / k.basis_days * SAFE_DIVIDE(d.book_new_bid, d.book_old_bid)
              ELSE d.spend7 / k.basis_days END AS cost_rejudged,
         -- a repair in a holdout campaign is never re-priced, so it never earns the good side
         IF(d.code = 'REPAIR' AND NOT (d.holdout AND d.snap_d >= d.holdout_eligible_from), '80', x.side) AS side_rejudged,
         -- WHY A LEAK MAY GET NO PAUSE ROW, measured (R-l, engine parity with the leak book's
         -- classify_leak; added 2026-08-23). NULL = the leak book will WRITE its pause row;
         -- anything else is the rule that stops it, and the row's dollars must then stay OUT of
         -- the recovered-today total, because a pause that is never written recovers nothing.
         -- The order matches the generator's, and every input is carried by dimk so the guard
         -- costs the wide query no extra join (house rule 11's spirit; the season gate, which is
         -- NOT read here, is the one that could not be afforded — see the kwfeed block above).
         CASE WHEN d.code != 'LEAK'                                  THEN CAST(NULL AS STRING)
              WHEN d.holdout AND d.snap_d >= d.holdout_eligible_from THEN 'HOLDOUT'
              WHEN d.live_state = ''                                 THEN 'LIVE_STATE_UNKNOWN'
              WHEN d.live_state != 'ENABLED'                         THEN 'ALREADY_PAUSED'
              ELSE CAST(NULL AS STRING) END AS leak_block,
         -- the same refusals in the words the family sentence uses. HOLDOUT is worded by its own
         -- clause (n_bad_holdout) and is NULL here so it is never said twice.
         CASE WHEN d.code != 'LEAK'                                  THEN CAST(NULL AS STRING)
              WHEN d.holdout AND d.snap_d >= d.holdout_eligible_from THEN CAST(NULL AS STRING)
              WHEN d.live_state = '' THEN 'the switch could not be read in Amazon at all, and nothing is paused blind'
              WHEN d.live_state != 'ENABLED' THEN 'already switched off in Amazon (this is trailing spend; a pause row would change nothing)'
              ELSE CAST(NULL AS STRING) END AS leak_block_words
  FROM coded d CROSS JOIN k
  JOIN codes x ON x.code = d.code
  LEFT JOIN ledger l ON l.family = d.family AND l.campaign_id = d.campaign_id AND l.keyword_id = d.keyword_id),
-- ── ONE LEAK BOOK, ONE SEQUENCE (2026-08-23, first-production-night cleanup). The leak book
-- carries EVERY executable leak the day it is built; the next day's register can hold a new
-- leak no pending book carries beside sixteen a pending book does. Publishing 'upload that book'
-- on one row and 'pause it on the next leak book' on the next hands the reader two instructions
-- he cannot both obey — the next book, built, would carry the sixteen again. So the book's state
-- is read ONCE, register-wide: it is STALE when an executable leak is on no pending book while
-- another is on one, or when more than one pending book exists; then every executable leak row
-- and every family clause carry the same single instruction — rebuild the book with
-- `--replaces <the pending batch>`, which logs one book carrying every leak and labels the old
-- one as replaced by it (a row is never deleted) — and the word 'upload' appears on no leak row.
-- When it is not stale, an on-book leak says upload that one book and an off-book leak (only
-- possible when NO book is pending) says build the next. Published per row as sheet_row (B37).
leak_book_state AS (
  SELECT COUNTIF(pause_pending) > 0
           AND (COUNTIF(NOT pause_pending) > 0 OR COUNT(DISTINCT pause_batch_id) > 1) AS stale,
         COALESCE(STRING_AGG(DISTINCT pause_batch_id, ' ' ORDER BY pause_batch_id), '') AS books
  FROM kw WHERE book = 'HARVEST' AND code = 'LEAK' AND leak_block IS NULL),
-- ── family figures per horizon
hz AS (
  SELECT 'today' AS horizon, 1 AS hz_order UNION ALL
  SELECT 'day one', 2 UNION ALL
  SELECT 're-judged', 3),
kw_h AS (
  SELECT kw.*, hz.horizon, hz.hz_order,
         CASE hz.horizon WHEN 'today' THEN cost_today WHEN 'day one' THEN cost_day1 ELSE cost_rejudged END AS cost_h,
         CASE hz.horizon WHEN 're-judged' THEN side_rejudged ELSE side END AS side_h,
         CASE hz.horizon WHEN 're-judged' THEN IF(code = 'REPAIR' AND NOT no_sheet, 'MARGINAL', code) ELSE code END AS code_h,
         CASE hz.horizon WHEN 're-judged' THEN IF(code = 'REPAIR' AND NOT no_sheet, 'marginal — at its bar', category) ELSE category END AS category_h
  FROM kw CROSS JOIN hz),
fam_h AS (
  -- EVERY DOLLAR AGGREGATE IS ROUNDED HERE, AT SOURCE (2026-08-23, eighth pass). A distributed
  -- FLOAT64 SUM is not associative: the same read of this view returned one family's
  -- bad_side_per_day as a double just under a half-cent boundary on one run and just over it on
  -- the next, so the published COLUMN (rounded to four decimals) read the same both times while
  -- the SENTENCE, formatted from the raw double with %.2f, alternated one cent apart (Standing
  -- Rule 0: the family and the figure are not pinned here — re-run the determinism fingerprint
  -- at the foot of the acceptance suite to see it or not see it). The rows were
  -- otherwise byte-identical; a keyed FULL OUTER JOIN of two in-session reads found exactly one
  -- differing row, and the pre-change view body reproduced it, so it is not this pass's doing —
  -- it is the register failing its own determinism guarantee (spec §8) on a half-cent boundary.
  -- Rounding the aggregate ONCE, here, gives every consumer the same double: the column, the
  -- derived figures (judged, allowance, open capacity, over_by) and the sentence can no longer
  -- disagree with each other or with themselves between two reads. Four decimals, because that is
  -- what the published columns already carry, and a cent-level reconciliation (B01/B02/B15)
  -- cannot notice the difference.
  SELECT family, book, horizon, hz_order,
         ROUND(SUM(cost_today), 4) AS spend_basis_per_day,
         ROUND(SUM(spend28) / MAX(k.context_days), 4) AS spend_context_per_day,
         ROUND(SUM(cost_h), 4) AS spend_h_per_day,
         ROUND(SUM(IF(side_h = '80', cost_h, 0)), 4) AS good_side_per_day,
         ROUND(SUM(IF(side_h = '20', cost_h, 0)), 4) AS bad_side_per_day,
         ROUND(SUM(IF(side_h = 'DEFENSE', cost_h, 0)), 4) AS defense_per_day,
         ROUND(SUM(IF(side_h = 'LAUNCH', cost_h, 0)), 4) AS launch_per_day,
         ROUND(SUM(IF(side_h = '20' AND occupant_kind IS NOT NULL, cost_h, 0)), 4) AS seats_cost_per_day,
         ROUND(SUM(IF(code_h = 'LEAK', cost_h, 0)), 4) AS leak_per_day,
         ROUND(SUM(IF(code_h = 'GAP', cost_h, 0)), 4) AS gap_per_day,
         -- counts by the HORIZON's own side (D5): a projection never pairs today's counts with
         -- projected dollars — a repair that moved to the good side at re-judged is not a seat there
         COUNTIF(occupant_kind IS NOT NULL AND side_h = '20') AS seats_h,
         COUNTIF(occupant_kind = 'settling') AS seats_settling,
         COUNTIF(code_h = 'LEAK') AS n_leaks, COUNTIF(code_h = 'GAP') AS n_gaps,
         -- R-l leak half, after the arm shipped: how many of this family's leaks a PENDING_UPLOAD
         -- book actually pauses, and how many no sheet carries. The projection sentence names both.
         COUNTIF(code_h = 'LEAK' AND pause_pending
                 AND NOT (holdout AND snap_d >= holdout_eligible_from)) AS n_leaks_on_book,
         COUNTIF(code_h = 'LEAK' AND NOT (pause_pending
                 AND NOT (holdout AND snap_d >= holdout_eligible_from))) AS n_leaks_off_book,
         -- the gap-cause buckets (R-k refined): blind (no keyword id), trailing (disabled on
         -- Amazon), next-run (enabled, verdict coming), check (real id, no current DIM row)
         COUNTIF(code = 'GAP' AND gap_cause = 'NO_ID') AS n_gap_blind,
         ROUND(SUM(IF(code = 'GAP' AND gap_cause = 'NO_ID', cost_today, 0)), 4) AS gap_blind_today,
         COUNTIF(code = 'GAP' AND gap_cause = 'DISABLED') AS n_gap_trailing,
         ROUND(SUM(IF(code = 'GAP' AND gap_cause = 'DISABLED', cost_today, 0)), 4) AS gap_trailing_today,
         COUNTIF(code = 'GAP' AND gap_cause = 'NEWLY_SEEN') AS n_gap_next_run,
         COUNTIF(code = 'GAP' AND gap_cause = 'UNKNOWN') AS n_gap_check,
         ROUND(SUM(IF(code = 'GAP' AND gap_cause = 'UNKNOWN', cost_today, 0)), 4) AS gap_check_today,
         COUNTIF(code = 'REPAIR') AS n_repair, COUNTIF(code = 'STALLED_PROBE') AS n_stalled,
         COUNTIF(code = 'FAILED') AS n_failed, COUNTIF(code = 'PROBATION') AS n_probation,
         COUNTIF(code = 'PROBE') AS n_probe, COUNTIF(code = 'DEFENSE') AS n_defense,
         ROUND(SUM(IF(code = 'REPAIR', cost_day1, 0)), 4) AS repair_day1,
         ROUND(SUM(IF(code = 'STALLED_PROBE', cost_today, 0)), 4) AS stalled_today,
         ROUND(SUM(IF(code = 'FAILED', cost_today, 0)), 4) AS failed_today,
         -- R-l: the executable recovery is PAUSES ONLY — a leak paused, a failed keyword killed
         -- with a pause row — and a holdout campaign gets no sheet row, so it recovers nothing.
         -- EXECUTABLE means the leak book will actually WRITE the row (leak_block IS NULL): the
         -- holdout guard is only the first of four measured refusals, and counting a leak the
         -- generator will refuse promises dollars no sheet can move (added 2026-08-23; before it,
         -- this pair counted every non-holdout leak and the promise diverged from the book the
         -- moment a leak was switched off in Amazon, season-blocked, or unreadable).
         COUNTIF(code = 'LEAK' AND leak_block IS NULL) AS n_leaks_exec,
         ROUND(SUM(IF(code = 'LEAK' AND leak_block IS NULL, cost_today, 0)), 4) AS leak_exec_today,
         -- …and the leaks the book refuses, with the measured rule that refuses each, so the
         -- sentence can say what those dollars depend on instead of silently dropping them
         -- (house rule 10: unmeasured never reads as bad — these are MEASURED, and named).
         COUNTIF(code = 'LEAK' AND leak_block IS NOT NULL
                 AND leak_block != 'HOLDOUT') AS n_leaks_blocked,
         ROUND(SUM(IF(code = 'LEAK' AND leak_block IS NOT NULL AND leak_block != 'HOLDOUT',
                      cost_today, 0)), 4) AS leak_blocked_today,
         STRING_AGG(DISTINCT IF(code = 'LEAK', leak_block_words, NULL), '; '
                    ORDER BY IF(code = 'LEAK', leak_block_words, NULL)) AS leak_blocked_reasons,
         -- …and WHICH BOOK each of those pauses rides on, per row. A leak whose KEYWORD_PAUSE row
         -- already sits at PENDING_UPLOAD is on a sheet that EXISTS: the reader's move is to upload
         -- that batch (or label it SUPERSEDED_NEVER_UPLOADED), not to build another book. A leak no
         -- book carries rides the next one the generator builds. Same split as the projection
         -- counts above, but on the TODAY code and restricted to the executable set, because this
         -- pair words the recovered-today clause and must agree with n_leaks_exec to the row.
         COUNTIF(code = 'LEAK' AND pause_pending AND leak_block IS NULL) AS n_leaks_exec_on_book,
         COUNTIF(code = 'LEAK' AND NOT pause_pending AND leak_block IS NULL) AS n_leaks_exec_off_book,
         STRING_AGG(DISTINCT IF(code = 'LEAK' AND pause_pending AND leak_block IS NULL, pause_batch_id, NULL), ', '
                    ORDER BY IF(code = 'LEAK' AND pause_pending AND leak_block IS NULL, pause_batch_id, NULL)) AS leak_pause_books,
         COUNTIF(code = 'FAILED' AND NOT (holdout AND snap_d >= holdout_eligible_from)) AS n_failed_exec,
         ROUND(SUM(IF(code = 'FAILED' AND NOT (holdout AND snap_d >= holdout_eligible_from), cost_today, 0)), 4) AS failed_exec_today,
         -- and the same guard on the two lines that recover nothing: a stalled probe or a repair in
         -- a holdout campaign cannot even be re-priced, so it is never listed as a move
         COUNTIF(code = 'STALLED_PROBE' AND NOT no_sheet) AS n_stalled_exec,
         ROUND(SUM(IF(code = 'STALLED_PROBE' AND NOT no_sheet, cost_today, 0)), 4) AS stalled_exec_today,
         COUNTIF(code = 'REPAIR' AND NOT no_sheet) AS n_repair_exec,
         ROUND(SUM(IF(code = 'REPAIR' AND NOT no_sheet, cost_day1, 0)), 4) AS repair_exec_day1,
         -- every 20%-side row that gets no sheet row at all while the holdout arm runs
         COUNTIF(side_h = '20' AND no_sheet) AS n_bad_holdout,
         ROUND(SUM(IF(side_h = '20' AND no_sheet, cost_h, 0)), 4) AS bad_holdout_today,
         COUNT(*) AS n_keywords
  FROM kw_h CROSS JOIN k
  GROUP BY 1, 2, 3, 4),
fam_read AS (
  SELECT f.*, k.allowance_share, band.at_line_band, band.at_line_band_derivation,
         -- R-l: the recovered-today figure, and nothing else, may be called a recovery
         f.leak_exec_today + f.failed_exec_today AS recovered_today,
         good_side_per_day + bad_side_per_day AS judged_per_day,
         SAFE_DIVIDE(good_side_per_day, NULLIF(good_side_per_day + bad_side_per_day, 0)) AS good_share,
         k.allowance_share * (good_side_per_day + bad_side_per_day) AS allowance_per_day
  FROM fam_h f CROSS JOIN k LEFT JOIN band ON band.family = f.family),
fam_rows AS (
  SELECT f.*,
         allowance_per_day - bad_side_per_day AS open_capacity_per_day,
         GREATEST(0, bad_side_per_day - allowance_per_day) AS over_by_per_day,
         CASE WHEN book = 'INVEST' THEN 'REFERENCE'
              WHEN good_share IS NULL THEN 'NO_SPEND'
              WHEN good_share >= 0.80 THEN 'IN'
              WHEN good_share >= 0.80 - COALESCE(at_line_band, 0) THEN 'AT_LINE'
              ELSE 'OUT' END AS doctrine_status,
         CASE horizon
           WHEN 'today' THEN FORMAT('measured on the %d complete days %s to %s; nothing assumed',
                                    k.basis_days, CAST(win.basis_from AS STRING), CAST(win.basis_to AS STRING))
           WHEN 'day one' THEN 'projection: the pending books land — every keyword on a pending BID row spends in proportion to new bid ÷ old bid (a linear bid→spend guess, not a measurement); everything else as today. A closed-but-spending keyword reaches $0 here ONLY when a pause row for that exact keyword is on a pending book of its own — the leak arm (tools/build_seat_moves_bulksheet.py) shipped on 2026-08-23, so that sheet now exists, and the credit is checked row by row against the change log rather than assumed for the category. A leak no book carries costs here exactly what it costs today. A keyword in a holdout campaign on or after its eligible_from date gets no sheet row at all, so it is unchanged here — no book lands on it while the arm runs.'
           ELSE 'projection: the repairs hold at their bar and move to the good side at their day-one cost; probation keywords stay on the 20% side at their floor; failed keywords are killed with a pause row (→ $0) — the shipped reprice generator builds that row today; a leak reaches $0 only where a pause row for it sits on a pending book from the leak arm (tools/build_seat_moves_bulksheet.py, shipped 2026-08-23), checked row by row against the change log, and a leak no book carries keeps costing what it costs today; stalled probes are re-priced by the move on their own row — raised to the seat price where the live bid is below it, otherwise parked at the engine\'s park price — and keep spending at that price (the same linear bid→spend guess), because parking lowers a price and does not stop the spend, so they stay on the 20% side until a verdict arrives; engine probes keep their day-one cost; settling verdicts hold; untracked spend is unchanged until the ladder sees it. A keyword in a holdout campaign on or after its eligible_from date gets no sheet row at all, so it is unchanged here and a repair in one never moves to the good side.'
         END AS horizon_assumption
  FROM fam_read f CROSS JOIN k CROSS JOIN win),
-- ── the lowest free seat number per working family
free_no AS (
  SELECT b.family, MIN(n) AS lowest_free_seat
  FROM books b
  CROSS JOIN UNNEST(GENERATE_ARRAY(1, 1 + (SELECT COALESCE(MAX(seat_no), 0) FROM ledger))) AS n
  LEFT JOIN ledger l ON l.family = b.family AND l.seat_no = n
  WHERE b.book = 'HARVEST' AND l.seat_no IS NULL
  GROUP BY 1),
-- ── the probe queue: the engine's QUEUED keywords in the family, cheapest admission first by rank
-- (a holdout campaign leaves the queue from its eligible_from date; before then the candidate
--  carries the holdout marker)
queue AS (
  SELECT f.family, o.campaign_id, o.campaign_name, o.keyword_id, o.target_text,
         o.seat_rank - o.slots AS queue_pos, o.seat_cpc, o.seat_cpc * k.click_goal_day AS admission_cost_per_day,
         h.campaign_id IS NOT NULL AS holdout, h.eligible_from AS holdout_eligible_from,
         ROW_NUMBER() OVER (PARTITION BY f.family ORDER BY o.seat_rank, o.campaign_id, o.keyword_id) AS rk
  FROM oob o CROSS JOIN k CROSS JOIN run_day
  JOIN fam f ON f.campaign_id = o.campaign_id
  JOIN books b ON b.family = f.family AND b.book = 'HARVEST'
  LEFT JOIN holdout h ON h.campaign_id = o.campaign_id
  LEFT JOIN oob_brand_hit ob ON ob.campaign_id = o.campaign_id AND ob.keyword_id = o.keyword_id
  -- D6: defense three ways here too — the engine flag, the campaign name, a house brand phrase
  WHERE o.role = 'QUEUED' AND NOT COALESCE(o.oob_is_defense, FALSE)
    AND NOT REGEXP_CONTAINS(UPPER(COALESCE(o.campaign_name, '')), r'BRAND DEFENSE')
    AND ob.keyword_id IS NULL
    AND NOT (h.campaign_id IS NOT NULL AND run_day.d >= h.eligible_from)),
next_probe AS (
  SELECT q.family, q.campaign_id, q.campaign_name, q.keyword_id, q.target_text, q.queue_pos, q.seat_cpc, q.admission_cost_per_day,
         q.holdout, q.holdout_eligible_from
  FROM queue q
  JOIN fam_rows fr ON fr.family = q.family AND fr.horizon = 'today'
  WHERE q.admission_cost_per_day <= fr.open_capacity_per_day
  QUALIFY ROW_NUMBER() OVER (PARTITION BY q.family ORDER BY q.rk) = 1),
-- ── absorption advisory: above-bar campaigns capped ≥ k.absorb_capped_days of the last 7
absorb AS (
  SELECT f.family, cs.campaign_id, cs.campaign_name, cs.days_capped_7d, cs.spend_7d, cs.budget_7d,
         SAFE_DIVIDE(ca.gp7, NULLIF(ca.spend7, 0)) AS gp_roas_7d, f.keyword_bar,
         h.campaign_id IS NOT NULL AS holdout, h.eligible_from AS holdout_eligible_from
  FROM `onyga-482313.OI.V_CAMPAIGN_CAP_STATE` cs CROSS JOIN k
  JOIN fam f ON f.campaign_id = cs.campaign_id
  JOIN books b ON b.family = f.family AND b.book = 'HARVEST'
  LEFT JOIN camp_ads ca ON ca.cid = cs.campaign_id
  LEFT JOIN holdout h ON h.campaign_id = cs.campaign_id
  WHERE cs.days_capped_7d >= k.absorb_capped_days AND NOT cs.is_defense
    AND NOT COALESCE(f.bar_exempt, FALSE)
    AND SAFE_DIVIDE(ca.gp7, NULLIF(ca.spend7, 0)) >= f.keyword_bar),
-- ── one wide shape for every row (rendered from one typed column list; every branch identical in shape)
shape AS (
  -- FAMILY / REFERENCE rows
  SELECT
    IF(f.book = 'INVEST', 'REFERENCE', 'FAMILY') AS row_type,
    f.family AS family,
    f.book AS book,
    f.horizon AS horizon,
    CAST(NULL AS INT64) AS seat_no,
    CAST(NULL AS STRING) AS category,
    CAST(NULL AS STRING) AS side,
    CAST(NULL AS STRING) AS occupant_kind,
    CAST(NULL AS STRING) AS campaign_id,
    CAST(NULL AS STRING) AS campaign_name,
    CAST(NULL AS STRING) AS keyword_id,
    CAST(NULL AS STRING) AS target_text,
    CAST(NULL AS STRING) AS match_type,
    CAST(NULL AS STRING) AS state,
    CAST(NULL AS FLOAT64) AS current_bid,
    CAST(NULL AS FLOAT64) AS bid_floor,
    CAST(NULL AS FLOAT64) AS cost_per_day,
    CAST(NULL AS FLOAT64) AS cost_day_one,
    CAST(NULL AS FLOAT64) AS cost_rejudged,
    CAST(NULL AS STRING) AS book_batch_id,
    CAST(NULL AS STRING) AS book_action,
    CAST(NULL AS FLOAT64) AS book_old_bid,
    CAST(NULL AS FLOAT64) AS book_new_bid,
    CAST(NULL AS FLOAT64) AS raise_old_bid,
    CAST(NULL AS FLOAT64) AS raise_new_bid,
    CAST(NULL AS DATE) AS raised_on,
    CAST(NULL AS INT64) AS clicks_since_raise,
    CAST(NULL AS INT64) AS days_since_raise,
    CAST(NULL AS FLOAT64) AS seat_price,
    CAST(NULL AS DATE) AS due_on,
    CAST(NULL AS BOOL) AS holdout,
    CAST(NULL AS DATE) AS holdout_eligible_from,
    CAST(NULL AS STRING) AS holdout_note,
    ROUND(f.spend_basis_per_day, 4) AS spend_basis_per_day,
    ROUND(f.spend_context_per_day, 4) AS spend_context_per_day,
    ROUND(f.spend_h_per_day, 4) AS spend_horizon_per_day,
    ROUND(f.judged_per_day, 4) AS judged_per_day,
    ROUND(f.defense_per_day, 4) AS defense_per_day,
    ROUND(f.good_side_per_day, 4) AS good_side_per_day,
    ROUND(f.bad_side_per_day, 4) AS bad_side_per_day,
    ROUND(f.good_share, 4) AS good_share,
    f.doctrine_status AS doctrine_status,
    ROUND(f.allowance_per_day, 4) AS allowance_per_day,
    ROUND(f.seats_cost_per_day, 4) AS seats_cost_per_day,
    ROUND(f.leak_per_day, 4) AS leak_per_day,
    ROUND(f.gap_per_day, 4) AS gap_per_day,
    ROUND(f.open_capacity_per_day, 4) AS open_capacity_per_day,
    ROUND(f.over_by_per_day, 4) AS over_by_per_day,
    f.at_line_band AS at_line_band,
    f.at_line_band_derivation AS at_line_band_derivation,
    f.n_keywords AS n_keywords,
    f.horizon_assumption AS horizon_assumption,
    CAST(NULL AS STRING) AS move,
    CASE WHEN f.book = 'INVEST' THEN
           FORMAT('%s — launch family (reference only, never judged on profit): $%.2f/day on the %s horizon, of which $%.2f/day launch-contained, $%.2f/day winning, at its bar or waiting for a verdict, $%.2f/day losing, probed, leaking or untracked, $%.2f/day brand defense. The launch controller governs it; this register only shows it.',
                  UPPER(f.family), f.spend_h_per_day, f.horizon, f.launch_per_day, f.good_side_per_day, f.bad_side_per_day, f.defense_per_day)
         WHEN f.good_share IS NULL THEN
           FORMAT('%s — no judged spend on the basis window (%s horizon); nothing to read.', UPPER(f.family), f.horizon)
         ELSE
           FORMAT('%s — %d%% good · %s%s (%s horizon). Allowance $%.2f/day (%d%% of the $%.2f/day judged); the 20%% side holds $%.2f/day: %s, %s, %d untracked $%.2f/day; open capacity %s/day. %d settling verdicts are seated but count on the 80%% side. Brand defense $%.2f/day sits outside the ratio. At-the-line band %.1f points (this family\'s own 7-day noise; derivation on the row). %s',
                  UPPER(f.family), CAST(ROUND(100 * f.good_share) AS INT64),
                  CASE f.doctrine_status WHEN 'IN' THEN 'IN' WHEN 'AT_LINE' THEN 'AT THE LINE' ELSE 'OUT' END,
                  IF(f.doctrine_status = 'OUT', FORMAT(' by $%.2f/day', f.over_by_per_day),
                     IF(f.doctrine_status = 'AT_LINE', FORMAT(' (within %.1f points of 80%%, this family\'s own 7-day noise)', 100 * f.at_line_band), '')),
                  f.horizon, f.allowance_per_day, CAST(ROUND(100 * f.allowance_share) AS INT64), f.judged_per_day,
                  f.bad_side_per_day,
                  -- D5: on a projection the counts are the horizon's own and the verb is conditional
                  IF(f.horizon = 'today', FORMAT('%d seats costing $%.2f/day', f.seats_h, f.seats_cost_per_day),
                                          FORMAT('the %d seats would cost $%.2f/day', f.seats_h, f.seats_cost_per_day)),
                  -- R-l, leak half: a projection may still spend back only dollars a sheet
                  -- actually recovers. The leak arm shipped, so the clause names BOTH counts —
                  -- the leaks a pending book pauses, and the ones no book carries, which keep
                  -- costing on this horizon exactly as before.
                  IF(f.horizon = 'today', FORMAT('%d leaks $%.2f/day', f.n_leaks, f.leak_per_day),
                     CASE WHEN f.n_leaks = 0 THEN '0 leaks'
                          WHEN f.n_leaks_off_book = 0 THEN FORMAT('all %d leaks paused by a pending leak book', f.n_leaks_on_book)
                          WHEN f.n_leaks_on_book = 0 THEN FORMAT('%d leaks still costing $%.2f/day (no leak book carries them yet)', f.n_leaks_off_book, f.leak_per_day)
                          ELSE FORMAT('%d of %d leaks paused by a pending leak book, %d still costing $%.2f/day', f.n_leaks_on_book, f.n_leaks, f.n_leaks_off_book, f.leak_per_day) END),
                  f.n_gaps, f.gap_per_day,
                  IF(f.open_capacity_per_day < 0, FORMAT('−$%.2f', -f.open_capacity_per_day), FORMAT('$%.2f', f.open_capacity_per_day)),
                  f.seats_settling, f.defense_per_day, 100 * COALESCE(f.at_line_band, 0),
                  CASE WHEN f.horizon != 'today' THEN 'This row is a projection; the assumption it rests on is written on the row.'
                       WHEN f.doctrine_status = 'IN' THEN 'The family passes today; the open capacity is what a new probe may cost.'
                       ELSE CONCAT('What closes the gap: ',
                              -- the clause list is semicolon-separated; the last separator
                              -- becomes a full stop so the closing sentence starts a sentence
                              REGEXP_REPLACE(CONCAT(
                              -- R-l, the executable recovery: PAUSES ONLY. These are the only two
                              -- moves whose dollars provably leave the 20% side when the sheet
                              -- lands, and they are the only ones written in the (−$…/day) form.
                              -- and the leak clause names the book PER ROW, because the arm has
                              -- shipped: a leak whose pause row already sits at PENDING_UPLOAD is
                              -- on a sheet that EXISTS — the move is to upload that batch, not to
                              -- build another book — while a leak no book carries rides the next
                              -- one. Sending a reader to "the next leak book" for a keyword the
                              -- pending book already carries produces a SECOND batch of the same
                              -- pause rows, which is why the wording follows the same per-row
                              -- measurement the projections do (R-l(e)).
                              CASE WHEN f.n_leaks_exec = 0 THEN ''
                                   -- ONE BOOK: a stale pending book is never 'uploaded' beside a
                                   -- 'next book' — the single instruction is to rebuild it
                                   WHEN lbs.stale THEN
                                     FORMAT('pause the %d %s — rebuild the leak book: `tools/build_seat_moves_bulksheet.py --replaces %s` builds ONE book that carries every leak and labels %s never-uploaded, so do not upload %s (−$%.2f/day); ',
                                            f.n_leaks_exec, IF(f.n_leaks_exec = 1, 'leak', 'leaks'), lbs.books, lbs.books, lbs.books, f.leak_exec_today)
                                   WHEN f.n_leaks_exec_on_book > 0 THEN
                                     FORMAT('pause the %d %s — every one is already written on the pending leak book %s, so the move is to upload that book (or label it never-uploaded with `tools/build_seat_moves_bulksheet.py --supersede %s`), not to build another (−$%.2f/day); ',
                                            f.n_leaks_exec, IF(f.n_leaks_exec = 1, 'leak', 'leaks'), f.leak_pause_books, f.leak_pause_books, f.leak_exec_today)
                                   ELSE
                                     FORMAT('pause the %d %s on the next leak book (tools/build_seat_moves_bulksheet.py) (−$%.2f/day); ',
                                            f.n_leaks_exec, IF(f.n_leaks_exec = 1, 'leak', 'leaks'), f.leak_exec_today) END,
                              IF(f.n_failed_exec > 0, FORMAT('kill the %d failed keywords on the next book with a pause row (−$%.2f/day); ', f.n_failed_exec, f.failed_exec_today), ''),
                              -- R-l, engine parity: leaks the leak book REFUSES. Their dollars are
                              -- not in the recovered-today number above, and the reason each is
                              -- refused is measured, not assumed, so it is said in words here.
                              IF(f.n_leaks_blocked > 0, FORMAT('%s%d %s ($%.2f/day) get no pause row at all — %s — so their dollars are not part of the recovery above; ', IF(f.n_leaks_exec > 0, 'a further ', ''), f.n_leaks_blocked, IF(f.n_leaks_blocked = 1, 'leak', 'leaks'), f.leak_blocked_today, f.leak_blocked_reasons), ''),
                              IF(f.n_bad_holdout > 0, FORMAT('%d keywords on the 20%% side ($%.2f/day) sit in holdout campaigns and get no sheet row of any kind while the arm runs, so nothing listed here moves them; ', f.n_bad_holdout, f.bad_holdout_today), ''),
                              IF(f.n_leaks_exec + f.n_failed_exec = 0, 'there is nothing to pause on the next book; ', ''),
                              -- R-l, the lines that recover NOTHING today. Neither may wear the
                              -- (−$…/day) form: parking lowers a price and the spend continues,
                              -- and re-pricing a repair gives back nothing today by construction.
                              IF(f.n_stalled_exec > 0, FORMAT('re-price or park the %d stalled probes — parking lowers their price, it does not stop their spend, so their $%.2f/day stays at risk of continuing and is not recovered today; ', f.n_stalled_exec, f.stalled_exec_today), ''),
                              IF(f.n_repair_exec > 0, FORMAT('the %d repairs are being re-priced toward their bar — a change of price, not a recovery: it gives back nothing today, and $%.2f/day moves to the good side only when they are re-judged, and only if they hold at their bar; ', f.n_repair_exec, f.repair_exec_day1), ''),
                              -- the gap causes (R-k refined): each bucket worded by what was measured
                              IF(f.n_gap_next_run > 0,
                                 IF(f.n_gap_next_run = 1, 'the 1 enabled target with no verdict row gets one on the next state run; ',
                                    FORMAT('the %d enabled targets with no verdict row get one on the next state run; ', f.n_gap_next_run)), ''),
                              IF(f.n_gap_blind > 0,
                                 IF(f.n_gap_blind = 1, FORMAT('the 1 SB video product target ($%.2f/day) arrives with no keyword id, so the verdict ladder cannot see it — this spend stays untracked until the ladder learns to read these rows (a ruling for Ori, not a mapping fix); ', f.gap_blind_today),
                                    FORMAT('the %d SB video product targets ($%.2f/day) arrive with no keyword id, so the verdict ladder cannot see them — this spend stays untracked until the ladder learns to read these rows (a ruling for Ori, not a mapping fix); ', f.n_gap_blind, f.gap_blind_today)), ''),
                              IF(f.n_gap_trailing > 0,
                                 IF(f.n_gap_trailing = 1, FORMAT('the 1 paused target ($%.2f/day) is trailing spend and leaves the universe when it stops; ', f.gap_trailing_today),
                                    FORMAT('the %d paused targets ($%.2f/day) are trailing spend and leave the universe when it stops; ', f.n_gap_trailing, f.gap_trailing_today)), ''),
                              IF(f.n_gap_check > 0,
                                 IF(f.n_gap_check = 1, FORMAT('check why the ladder does not track the 1 remaining row ($%.2f/day); ', f.gap_check_today),
                                    FORMAT('check why the ladder does not track the %d remaining rows ($%.2f/day); ', f.n_gap_check, f.gap_check_today)), ''),
                              ''), r'; $', '. '),
                              -- R-l, the closing sentence, in one fixed order: the executable
                              -- recovery (pauses only), the gap, a plain closes / does-not-close
                              -- verdict, what the remaining dollars depend on, and a pointer to
                              -- this family's re-judged row. No projection is inside the number.
                              CASE WHEN NOT (f.over_by_per_day > 0) THEN ''
                                   WHEN f.recovered_today >= f.over_by_per_day - 0.005 THEN
                                     FORMAT('The pauses named above recover $%.2f/day against the $%.2f/day gap — that closes it. Everything else on this row changes a price rather than stopping spend; read this family\'s re-judged row to see where those dollars land.',
                                            f.recovered_today, f.over_by_per_day)
                                   ELSE
                                     FORMAT('The pauses named above recover $%.2f/day against the $%.2f/day gap — that does not close it. The remaining $%.2f/day depends on %s; read this family\'s re-judged row to see where those dollars land.',
                                            f.recovered_today, f.over_by_per_day, f.over_by_per_day - f.recovered_today,
                                            COALESCE(NULLIF(ARRAY_TO_STRING(ARRAY(SELECT x FROM UNNEST([
                                              IF(f.n_repair_exec > 0, FORMAT('the %d repairs holding at their bar when they are re-judged (a projection worth $%.2f/day, not money in hand)', f.n_repair_exec, f.repair_exec_day1), NULL),
                                              IF(f.n_stalled_exec > 0, FORMAT('the %d stalled probes ($%.2f/day) being re-priced or parked and then producing a verdict — parking lowers their price, so those dollars keep running at the parked price until a verdict arrives', f.n_stalled_exec, f.stalled_exec_today), NULL),
                                              IF(f.n_probation > 0, FORMAT('the %d probation keywords being judged at their floor', f.n_probation), NULL),
                                              IF(f.gap_per_day > 0, FORMAT('the $%.2f/day of untracked spend being tracked or stopped (a ruling for Ori, not a keyword move)', f.gap_per_day), NULL),
                                              IF(f.n_bad_holdout > 0, FORMAT('the $%.2f/day in holdout campaigns, which no sheet may touch until the arm ends', f.bad_holdout_today), NULL)
                                            ]) AS x WHERE x IS NOT NULL), ', and on '), ''),
                                              'growing the 80% side — there is no other lever on this row'))
                              END)
                  END)
         END AS sentence,
    CAST(NULL AS STRING) AS sheet_row,
    FORMAT('%s|%02d|%02d|', f.family, IF(f.book = 'INVEST', 9, 1), f.hz_order) AS sort_key
  FROM fam_rows f CROSS JOIN leak_book_state lbs
  UNION ALL
  -- CATEGORY rows (all families, all horizons) — they sum to the family's spend on that horizon
  SELECT
    'CATEGORY' AS row_type,
    family AS family,
    book AS book,
    horizon AS horizon,
    CAST(NULL AS INT64) AS seat_no,
    category_h AS category,
    side_h AS side,
    CAST(NULL AS STRING) AS occupant_kind,
    CAST(NULL AS STRING) AS campaign_id,
    CAST(NULL AS STRING) AS campaign_name,
    CAST(NULL AS STRING) AS keyword_id,
    CAST(NULL AS STRING) AS target_text,
    CAST(NULL AS STRING) AS match_type,
    CAST(NULL AS STRING) AS state,
    CAST(NULL AS FLOAT64) AS current_bid,
    CAST(NULL AS FLOAT64) AS bid_floor,
    ROUND(SUM(cost_h), 4) AS cost_per_day,
    CAST(NULL AS FLOAT64) AS cost_day_one,
    CAST(NULL AS FLOAT64) AS cost_rejudged,
    CAST(NULL AS STRING) AS book_batch_id,
    CAST(NULL AS STRING) AS book_action,
    CAST(NULL AS FLOAT64) AS book_old_bid,
    CAST(NULL AS FLOAT64) AS book_new_bid,
    CAST(NULL AS FLOAT64) AS raise_old_bid,
    CAST(NULL AS FLOAT64) AS raise_new_bid,
    CAST(NULL AS DATE) AS raised_on,
    CAST(NULL AS INT64) AS clicks_since_raise,
    CAST(NULL AS INT64) AS days_since_raise,
    CAST(NULL AS FLOAT64) AS seat_price,
    CAST(NULL AS DATE) AS due_on,
    CAST(NULL AS BOOL) AS holdout,
    CAST(NULL AS DATE) AS holdout_eligible_from,
    CAST(NULL AS STRING) AS holdout_note,
    CAST(NULL AS FLOAT64) AS spend_basis_per_day,
    CAST(NULL AS FLOAT64) AS spend_context_per_day,
    CAST(NULL AS FLOAT64) AS spend_horizon_per_day,
    CAST(NULL AS FLOAT64) AS judged_per_day,
    CAST(NULL AS FLOAT64) AS defense_per_day,
    CAST(NULL AS FLOAT64) AS good_side_per_day,
    CAST(NULL AS FLOAT64) AS bad_side_per_day,
    CAST(NULL AS FLOAT64) AS good_share,
    CAST(NULL AS STRING) AS doctrine_status,
    CAST(NULL AS FLOAT64) AS allowance_per_day,
    CAST(NULL AS FLOAT64) AS seats_cost_per_day,
    CAST(NULL AS FLOAT64) AS leak_per_day,
    CAST(NULL AS FLOAT64) AS gap_per_day,
    CAST(NULL AS FLOAT64) AS open_capacity_per_day,
    CAST(NULL AS FLOAT64) AS over_by_per_day,
    CAST(NULL AS FLOAT64) AS at_line_band,
    CAST(NULL AS STRING) AS at_line_band_derivation,
    COUNT(*) AS n_keywords,
    CAST(NULL AS STRING) AS horizon_assumption,
    CAST(NULL AS STRING) AS move,
    FORMAT('%s · %s: %d keywords, $%.2f/day on the %s horizon — %s', family, category_h,
                COUNT(*), SUM(cost_h), horizon,
                CASE side_h WHEN '80' THEN 'on the 80% side' WHEN '20' THEN 'on the 20% side'
                            WHEN 'DEFENSE' THEN 'outside the ratio (defense is never judged on profit)'
                            WHEN 'LAUNCH' THEN 'outside the doctrine (launch family)'
                            ELSE 'shown so nothing is silent; $0 by construction, no side' END) AS sentence,
    CAST(NULL AS STRING) AS sheet_row,
    FORMAT('%s|%02d|%02d|%02d', family, IF(book = 'INVEST', 9, 2), hz_order, MIN(cat_order)) AS sort_key
  FROM kw_h
  GROUP BY family, book, horizon, hz_order, category_h, side_h
  UNION ALL
  -- SEAT rows — one per occupant of a working family
  SELECT
    'SEAT' AS row_type,
    w.family AS family,
    w.book AS book,
    'today' AS horizon,
    w.seat_no AS seat_no,
    w.category AS category,
    w.side AS side,
    w.occupant_kind AS occupant_kind,
    w.campaign_id AS campaign_id,
    w.campaign_name AS campaign_name,
    w.keyword_id AS keyword_id,
    w.target_text AS target_text,
    w.match_type AS match_type,
    w.state AS state,
    w.current_bid AS current_bid,
    w.bid_floor AS bid_floor,
    ROUND(w.cost_today, 4) AS cost_per_day,
    ROUND(w.cost_day1, 4) AS cost_day_one,
    ROUND(w.cost_rejudged, 4) AS cost_rejudged,
    w.book_batch_id AS book_batch_id,
    w.book_action AS book_action,
    w.book_old_bid AS book_old_bid,
    w.book_new_bid AS book_new_bid,
    IF(w.code = 'STALLED_PROBE', w.raise_old_bid, NULL) AS raise_old_bid,
    IF(w.code = 'STALLED_PROBE', w.raise_new_bid, NULL) AS raise_new_bid,
    IF(w.code = 'STALLED_PROBE', w.raised_on, NULL) AS raised_on,
    IF(w.code = 'STALLED_PROBE', w.clicks_since_raise, NULL) AS clicks_since_raise,
    -- D8: ONE clock — the raise is aged against the snapshot date, the same clock the 14-day test uses
    IF(w.code = 'STALLED_PROBE', DATE_DIFF(run_day.d, w.raised_on, DAY), NULL) AS days_since_raise,
    w.seat_price AS seat_price,
    IF(w.code = 'STALLED_PROBE', NULL, w.next_check_date) AS due_on,
    w.holdout AS holdout,
    w.holdout_eligible_from AS holdout_eligible_from,
    CASE WHEN NOT w.holdout THEN NULL
              WHEN run_day.d >= w.holdout_eligible_from THEN FORMAT('HOLDOUT — do not touch: this campaign is in the holdout arm since %s and is excluded from every sheet', CAST(w.holdout_eligible_from AS STRING))
              ELSE FORMAT('HOLDOUT arm from %s — a sheet may touch it until then and must not after', CAST(w.holdout_eligible_from AS STRING)) END AS holdout_note,
    CAST(NULL AS FLOAT64) AS spend_basis_per_day,
    CAST(NULL AS FLOAT64) AS spend_context_per_day,
    CAST(NULL AS FLOAT64) AS spend_horizon_per_day,
    CAST(NULL AS FLOAT64) AS judged_per_day,
    CAST(NULL AS FLOAT64) AS defense_per_day,
    CAST(NULL AS FLOAT64) AS good_side_per_day,
    CAST(NULL AS FLOAT64) AS bad_side_per_day,
    CAST(NULL AS FLOAT64) AS good_share,
    CAST(NULL AS STRING) AS doctrine_status,
    CAST(NULL AS FLOAT64) AS allowance_per_day,
    CAST(NULL AS FLOAT64) AS seats_cost_per_day,
    CAST(NULL AS FLOAT64) AS leak_per_day,
    CAST(NULL AS FLOAT64) AS gap_per_day,
    CAST(NULL AS FLOAT64) AS open_capacity_per_day,
    CAST(NULL AS FLOAT64) AS over_by_per_day,
    CAST(NULL AS FLOAT64) AS at_line_band,
    CAST(NULL AS STRING) AS at_line_band_derivation,
    1 AS n_keywords,
    CAST(NULL AS STRING) AS horizon_assumption,
    CASE WHEN w.holdout AND run_day.d >= w.holdout_eligible_from THEN 'no sheet row — holdout campaign; the seat stays as it is while the arm runs'
         ELSE CASE w.code
           WHEN 'REPAIR' THEN IF(w.book_new_bid IS NOT NULL,
                                 FORMAT('on the pending book %s: $%.2f → $%.2f (%s); re-judge %s', w.book_batch_id, w.book_old_bid, w.book_new_bid, IF(w.book_action = 'INCREASE_BID', 'a raise', 'a cut'), CAST(w.next_check_date AS STRING)),
                                 FORMAT('no row on the pending book — the reprice generator (tools/build_reprice_bulksheet.py) prices it; re-judge %s', CAST(w.next_check_date AS STRING)))
           WHEN 'PROBATION' THEN IF(w.book_new_bid IS NOT NULL,
                                 FORMAT('on the pending book %s: $%.2f → $%.2f (%s) — hold at the floor, judge %s', w.book_batch_id, w.book_old_bid, w.book_new_bid, IF(w.book_action = 'INCREASE_BID', 'a raise', 'a cut'), CAST(w.next_check_date AS STRING)),
                                 FORMAT('hold at its floor $%.2f; judge %s', COALESCE(w.bid_floor, 0), CAST(w.next_check_date AS STRING)))
           WHEN 'FAILED' THEN 'kill it on the next book (pause row) — it lost at its floor after probation'
           WHEN 'PROBE' THEN 'no move — the engine is buying its verdict; the seat closes on the verdict'
           -- R-i: an overdue settling verdict is named as overdue, never published as a future event
           WHEN 'SETTLING' THEN IF(w.next_check_date < run_day.d,
                                 FORMAT('no move — was due to settle on %s, overdue by %d days; the ladder has not re-judged it (the cause is upstream and under diagnosis; the register never changes the ladder)', CAST(w.next_check_date AS STRING), DATE_DIFF(run_day.d, w.next_check_date, DAY)),
                                 FORMAT('no move — its verdict settles %s', CAST(w.next_check_date AS STRING)))
           -- R-h: parked with an appointment ahead — the ladder's revive cycle re-judges it
           WHEN 'PARKED_SEAT' THEN FORMAT('no move — re-judged on %s by the ladder\'s revive cycle; parked at bid $%.2f and still buying clicks until then', CAST(w.next_check_date AS STRING), w.current_bid)
           -- R-f: branch on the SIGN of (seat price − live bid); never a raise to a lower or equal price
           WHEN 'STALLED_PROBE' THEN CASE
                                 WHEN w.seat_price IS NULL THEN
                                   FORMAT('its campaign is outside the budget engine\'s seat model, so no seat price is published — price it by hand to get a verdict, or park it at the engine\'s park price $%.2f and let the ladder\'s revive cycle re-test it', w.bid_park)
                                 WHEN w.current_bid < w.seat_price - k.bid_tol THEN
                                   FORMAT('raise to the seat price $%.2f to get a verdict (live bid $%.2f), or park it at the engine\'s park price $%.2f', w.seat_price, w.current_bid, w.bid_park)
                                 ELSE
                                   FORMAT('park it — bid to the engine\'s park price $%.2f and let the ladder\'s revive cycle re-test it: its live bid $%.2f is already at or above the seat price $%.2f and still bought no verdict', w.bid_park, w.current_bid, w.seat_price)
                                 END
         END END AS move,
    CONCAT(
           FORMAT('seat %s — %s (%s) ', COALESCE(CAST(w.seat_no AS STRING), '?'), w.target_text, w.campaign_name),
           CASE w.code
             WHEN 'REPAIR' THEN FORMAT('is losing and being re-priced toward its bar: $%.2f/day at bid $%.2f', w.cost_today, w.current_bid)
             WHEN 'PROBATION' THEN FORMAT('is losing and held at its floor to be seen serving: $%.2f/day at bid $%.2f', w.cost_today, w.current_bid)
             WHEN 'FAILED' THEN FORMAT('lost at its floor: $%.2f/day at bid $%.2f', w.cost_today, w.current_bid)
             WHEN 'PROBE' THEN FORMAT('is a trial being bought at an entry bid: $%.2f/day at bid $%.2f%s', w.cost_today, w.current_bid,
                                      IF(w.engine_probe, ' (on the engine\'s probe list)', ' (at the park bid, with spend)'))
             WHEN 'SETTLING' THEN CONCAT(
               FORMAT('has a verdict pending until its clicks settle: $%.2f/day at bid $%.2f', w.cost_today, w.current_bid),
               IF(w.next_check_date < run_day.d,
                  FORMAT(' — was due to settle on %s — overdue by %d days; the ladder has not re-judged it', FORMAT_DATE('%b %d', w.next_check_date), DATE_DIFF(run_day.d, w.next_check_date, DAY)),
                  ''))
             WHEN 'PARKED_SEAT' THEN FORMAT('is parked by the ladder with a re-verdict appointment on %s and is still buying clicks: $%.2f/day at bid $%.2f — being re-tested, not leaking', FORMAT_DATE('%b %d', w.next_check_date), w.cost_today, w.current_bid)
             WHEN 'STALLED_PROBE' THEN
               CONCAT(
                 IF(SAFE_DIVIDE(w.raise_new_bid, NULLIF(w.raise_old_bid, 0)) >= k.entry_raise_ratio,
                    FORMAT('entered at $%.2f on %s', w.raise_new_bid, FORMAT_DATE('%b %d', w.raised_on)),
                    FORMAT('was nudged $%.2f→$%.2f on %s', w.raise_old_bid, w.raise_new_bid, FORMAT_DATE('%b %d', w.raised_on))),
                 IF(w.current_bid > w.raise_new_bid + k.bid_tol, FORMAT(', now sitting at $%.2f', w.current_bid), ''),
                 -- D8: both clocks on the row — the clicks are counted on complete ads days, the age is on the snapshot date
                 FORMAT(' — %d clicks on the %d complete ads days since (through %s, $%.2f/day); the raise is %d days old on the snapshot date (%s), past the engine\'s own test (%d clicks in %d days), so it is neither earning nor being tested',
                        w.clicks_since_raise, DATE_DIFF(win.basis_to, w.raised_on, DAY), FORMAT_DATE('%b %d', win.basis_to), w.cost_today,
                        DATE_DIFF(run_day.d, w.raised_on, DAY), FORMAT_DATE('%b %d', run_day.d), k.verdict_clicks, k.probe_window_days))
           END,
           IF(w.occupant_kind = 'settling', ' — seated, but counted on the 80% side (ruling)', ''),
           '. ',
           CASE w.code
             WHEN 'REPAIR' THEN IF(w.book_new_bid IS NOT NULL, FORMAT('On the book: $%.2f → $%.2f; re-judge %s.', w.book_old_bid, w.book_new_bid, CAST(w.next_check_date AS STRING)), FORMAT('Re-judge %s.', CAST(w.next_check_date AS STRING)))
             WHEN 'PROBATION' THEN FORMAT('Judge %s.', CAST(w.next_check_date AS STRING))
             WHEN 'FAILED' THEN 'Kill it on the next book.'
             WHEN 'PROBE' THEN 'No move; the seat closes on the verdict.'
             WHEN 'SETTLING' THEN IF(w.next_check_date < run_day.d, 'No move; the ladder owes it a re-judgement.', FORMAT('No move; settles %s.', CAST(w.next_check_date AS STRING)))
             WHEN 'PARKED_SEAT' THEN FORMAT('No move; re-judged on %s.', CAST(w.next_check_date AS STRING))
             WHEN 'STALLED_PROBE' THEN CASE
                                        WHEN w.seat_price IS NULL THEN FORMAT('No seat price is published for its campaign (outside the budget engine); price it by hand or park it at the engine\'s park price $%.2f.', w.bid_park)
                                        WHEN w.current_bid < w.seat_price - k.bid_tol THEN FORMAT('Raise to the seat price $%.2f to get a verdict, or park it at the engine\'s park price $%.2f.', w.seat_price, w.bid_park)
                                        ELSE FORMAT('Park it at the engine\'s park price $%.2f: it could not buy a verdict even at or above the seat price $%.2f.', w.bid_park, w.seat_price)
                                      END
           END,
           IF(w.seat_no IS NULL, ' (Not yet numbered: the seat ledger runs after the snapshot.)', ''),
           IF(w.holdout AND run_day.d >= w.holdout_eligible_from, ' HOLDOUT — do not touch; excluded from every sheet, whatever the move above would have been.', ''),
           IF(w.holdout AND run_day.d < w.holdout_eligible_from, FORMAT(' Its campaign joins the holdout arm on %s; no sheet touches it from then.', CAST(w.holdout_eligible_from AS STRING)), '')
         ) AS sentence,
    -- sheet_row: what a sheet does with this row today (2026-08-23). PENDING_BOOK = a pending
    -- book already carries it; NEXT_REPRICE_BOOK = the reprice generator writes it on its next
    -- build; BY_HAND = a stalled probe, priced or parked by hand (R-f); NO_SHEET_ROW = holdout;
    -- NONE = nothing to do today. The brief derives its action from these, never from the status.
    CASE WHEN w.holdout AND run_day.d >= w.holdout_eligible_from THEN 'NO_SHEET_ROW'
         WHEN w.code IN ('REPAIR', 'PROBATION') AND w.book_new_bid IS NOT NULL THEN 'PENDING_BOOK'
         WHEN w.code IN ('REPAIR', 'FAILED') THEN 'NEXT_REPRICE_BOOK'
         WHEN w.code = 'STALLED_PROBE' THEN 'BY_HAND'
         ELSE 'NONE' END AS sheet_row,
    FORMAT('%s|%02d|%05d|%s|%s', w.family, 3, COALESCE(w.seat_no, 99999), w.campaign_id, w.keyword_id) AS sort_key
  FROM kw w CROSS JOIN k CROSS JOIN win CROSS JOIN run_day
  WHERE w.book = 'HARVEST' AND w.occupant_kind IS NOT NULL
  UNION ALL
  -- OPEN_SEAT rows — the lowest free number and the next affordable probe
  SELECT
    'OPEN_SEAT' AS row_type,
    fr.family AS family,
    fr.book AS book,
    'today' AS horizon,
    fn.lowest_free_seat AS seat_no,
    'open seat' AS category,
    '20' AS side,
    CAST(NULL AS STRING) AS occupant_kind,
    np.campaign_id AS campaign_id,
    np.campaign_name AS campaign_name,
    np.keyword_id AS keyword_id,
    np.target_text AS target_text,
    CAST(NULL AS STRING) AS match_type,
    CAST(NULL AS STRING) AS state,
    CAST(NULL AS FLOAT64) AS current_bid,
    CAST(NULL AS FLOAT64) AS bid_floor,
    ROUND(np.admission_cost_per_day, 4) AS cost_per_day,
    CAST(NULL AS FLOAT64) AS cost_day_one,
    CAST(NULL AS FLOAT64) AS cost_rejudged,
    CAST(NULL AS STRING) AS book_batch_id,
    CAST(NULL AS STRING) AS book_action,
    CAST(NULL AS FLOAT64) AS book_old_bid,
    CAST(NULL AS FLOAT64) AS book_new_bid,
    CAST(NULL AS FLOAT64) AS raise_old_bid,
    CAST(NULL AS FLOAT64) AS raise_new_bid,
    CAST(NULL AS DATE) AS raised_on,
    CAST(NULL AS INT64) AS clicks_since_raise,
    CAST(NULL AS INT64) AS days_since_raise,
    np.seat_cpc AS seat_price,
    CAST(NULL AS DATE) AS due_on,
    IF(np.keyword_id IS NULL, NULL, np.holdout) AS holdout,
    np.holdout_eligible_from AS holdout_eligible_from,
    CASE WHEN np.keyword_id IS NULL OR NOT np.holdout THEN NULL
         ELSE FORMAT('HOLDOUT arm from %s — the candidate may be admitted until then; from that date its campaign leaves the queue', CAST(np.holdout_eligible_from AS STRING)) END AS holdout_note,
    CAST(NULL AS FLOAT64) AS spend_basis_per_day,
    CAST(NULL AS FLOAT64) AS spend_context_per_day,
    CAST(NULL AS FLOAT64) AS spend_horizon_per_day,
    CAST(NULL AS FLOAT64) AS judged_per_day,
    CAST(NULL AS FLOAT64) AS defense_per_day,
    CAST(NULL AS FLOAT64) AS good_side_per_day,
    CAST(NULL AS FLOAT64) AS bad_side_per_day,
    CAST(NULL AS FLOAT64) AS good_share,
    CAST(NULL AS STRING) AS doctrine_status,
    CAST(NULL AS FLOAT64) AS allowance_per_day,
    CAST(NULL AS FLOAT64) AS seats_cost_per_day,
    CAST(NULL AS FLOAT64) AS leak_per_day,
    CAST(NULL AS FLOAT64) AS gap_per_day,
    ROUND(fr.open_capacity_per_day, 4) AS open_capacity_per_day,
    ROUND(fr.over_by_per_day, 4) AS over_by_per_day,
    CAST(NULL AS FLOAT64) AS at_line_band,
    CAST(NULL AS STRING) AS at_line_band_derivation,
    CAST(NULL AS INT64) AS n_keywords,
    CAST(NULL AS STRING) AS horizon_assumption,
    CASE WHEN fr.open_capacity_per_day <= 0 THEN 'admit nothing until a seat closes or a leak is paused'
              WHEN np.keyword_id IS NULL THEN 'admit nothing — no queued candidate fits the capacity'
              ELSE FORMAT('proposal: admit %s in %s at the seat price $%.2f (about $%.2f/day) — the engine activates it when a seat frees; the register never bids', np.target_text, np.campaign_name, np.seat_cpc, np.admission_cost_per_day) END AS move,
    CASE WHEN fr.open_capacity_per_day <= 0 THEN
                FORMAT('seat %d is the next free number in %s, but there is no open capacity: the 20%% side is over its allowance by $%.2f/day. Nothing is admitted until a seat closes or a leak is paused.', fn.lowest_free_seat, UPPER(fr.family), fr.over_by_per_day)
              WHEN np.keyword_id IS NULL THEN
                FORMAT('seat %d (open) in %s — $%.2f/day of capacity, but no queued candidate in the budget engine fits it (or the family has no queued keyword).', fn.lowest_free_seat, UPPER(fr.family), fr.open_capacity_per_day)
              ELSE
                CONCAT(FORMAT('seat %d (open) in %s — $%.2f/day of capacity. Next affordable probe: %s in %s, queue #%d, at the seat price $%.2f/click × %d clicks a day ≈ $%.2f/day.', fn.lowest_free_seat, UPPER(fr.family), fr.open_capacity_per_day, np.target_text, np.campaign_name, np.queue_pos, np.seat_cpc, k.click_goal_day, np.admission_cost_per_day),
                       IF(np.holdout, FORMAT(' Its campaign joins the holdout arm on %s and leaves the queue then.', CAST(np.holdout_eligible_from AS STRING)), '')) END AS sentence,
    CAST(NULL AS STRING) AS sheet_row,
    FORMAT('%s|%02d|%05d||', fr.family, 4, fn.lowest_free_seat) AS sort_key
  FROM fam_rows fr CROSS JOIN k CROSS JOIN run_day
  JOIN free_no fn ON fn.family = fr.family
  LEFT JOIN next_probe np ON np.family = fr.family
  WHERE fr.horizon = 'today' AND fr.book = 'HARVEST'
  UNION ALL
  -- LEAK rows — closed but still spending
  SELECT
    'LEAK' AS row_type,
    w.family AS family,
    w.book AS book,
    'today' AS horizon,
    CAST(NULL AS INT64) AS seat_no,
    w.category AS category,
    w.side AS side,
    CAST(NULL AS STRING) AS occupant_kind,
    w.campaign_id AS campaign_id,
    w.campaign_name AS campaign_name,
    w.keyword_id AS keyword_id,
    w.target_text AS target_text,
    w.match_type AS match_type,
    w.state AS state,
    w.current_bid AS current_bid,
    w.bid_floor AS bid_floor,
    ROUND(w.cost_today, 4) AS cost_per_day,
    ROUND(w.cost_day1, 4) AS cost_day_one,
    ROUND(w.cost_rejudged, 4) AS cost_rejudged,
    -- the LEAK row's book is a PAUSE book, not a bid book: publish the batch whose pause row is
    -- what zeroes this row's two projections, so a reader who meets the $0 can find the sheet
    -- that earned it (a pending BID row publishes its batch the same way on a SEAT row).
    IF(w.pause_pending, w.pause_batch_id, w.book_batch_id) AS book_batch_id,
    IF(w.pause_pending, 'KEYWORD_PAUSE', w.book_action) AS book_action,
    w.book_old_bid AS book_old_bid,
    w.book_new_bid AS book_new_bid,
    CAST(NULL AS FLOAT64) AS raise_old_bid,
    CAST(NULL AS FLOAT64) AS raise_new_bid,
    CAST(NULL AS DATE) AS raised_on,
    CAST(NULL AS INT64) AS clicks_since_raise,
    CAST(NULL AS INT64) AS days_since_raise,
    CAST(NULL AS FLOAT64) AS seat_price,
    CAST(NULL AS DATE) AS due_on,
    w.holdout AS holdout,
    w.holdout_eligible_from AS holdout_eligible_from,
    CASE WHEN NOT w.holdout THEN NULL
              WHEN run_day.d >= w.holdout_eligible_from THEN FORMAT('HOLDOUT — do not touch: this campaign is in the holdout arm since %s and is excluded from every sheet', CAST(w.holdout_eligible_from AS STRING))
              ELSE FORMAT('HOLDOUT arm from %s — a sheet may touch it until then and must not after', CAST(w.holdout_eligible_from AS STRING)) END AS holdout_note,
    CAST(NULL AS FLOAT64) AS spend_basis_per_day,
    CAST(NULL AS FLOAT64) AS spend_context_per_day,
    CAST(NULL AS FLOAT64) AS spend_horizon_per_day,
    CAST(NULL AS FLOAT64) AS judged_per_day,
    CAST(NULL AS FLOAT64) AS defense_per_day,
    CAST(NULL AS FLOAT64) AS good_side_per_day,
    CAST(NULL AS FLOAT64) AS bad_side_per_day,
    CAST(NULL AS FLOAT64) AS good_share,
    CAST(NULL AS STRING) AS doctrine_status,
    CAST(NULL AS FLOAT64) AS allowance_per_day,
    CAST(NULL AS FLOAT64) AS seats_cost_per_day,
    CAST(NULL AS FLOAT64) AS leak_per_day,
    CAST(NULL AS FLOAT64) AS gap_per_day,
    CAST(NULL AS FLOAT64) AS open_capacity_per_day,
    CAST(NULL AS FLOAT64) AS over_by_per_day,
    CAST(NULL AS FLOAT64) AS at_line_band,
    CAST(NULL AS STRING) AS at_line_band_derivation,
    1 AS n_keywords,
    CAST(NULL AS STRING) AS horizon_assumption,
    -- the move is measured, not assumed: a leak whose KEYWORD_PAUSE row already sits at
    -- PENDING_UPLOAD is on a book that EXISTS — and it is the same fact that takes this row to $0
    -- on both projections, so telling the reader to build "the next leak book" would send him to
    -- create a second batch of the pause row he already has. The batch id is published beside it.
    CASE WHEN w.leak_block = 'HOLDOUT' THEN 'no sheet row — holdout campaign'
              -- the three measured refusals the leak book applies after holdout. Each is a reason
              -- there is NO row to write, so the move may not read 'pause it' (R-l, engine parity).
              WHEN w.leak_block = 'ALREADY_PAUSED' THEN FORMAT('no sheet row — it already reads %s in Amazon, so this is trailing spend from before the switch and a pause row would change nothing; it leaves the register on its own when the spend stops', LOWER(w.live_state))
              WHEN w.leak_block = 'LIVE_STATE_UNKNOWN' THEN 'no sheet row — the state of this switch could not be read in Amazon at all, and nothing is paused blind; check the keyword in Amazon by hand'
              -- ONE instruction per row (2026-08-23): a stale book is rebuilt, never uploaded
              -- beside a 'next book'; the negate is the same book's business, said in the sentence
              WHEN lbs.stale THEN FORMAT('rebuild the leak book: `tools/build_seat_moves_bulksheet.py --replaces %s` — one book carries every leak, this one included, and %s is labelled never-uploaded; do not upload %s', lbs.books, lbs.books, lbs.books)
              WHEN w.pause_pending THEN FORMAT('upload the pending leak book %s (or label it never-uploaded with `tools/build_seat_moves_bulksheet.py --supersede %s`); do not build another', w.pause_batch_id, w.pause_batch_id)
              ELSE 'pause it on the next leak book (tools/build_seat_moves_bulksheet.py)' END AS move,
    FORMAT('%s (%s) reads %s on the ladder yet spent $%.2f/day on the basis window at bid $%.2f. %s%s',
                w.target_text, w.campaign_name, IF(w.state = 'DEAD', 'dead', 'parked'), w.cost_today, COALESCE(w.current_bid, 0),
                CASE WHEN w.leak_block = 'HOLDOUT' THEN 'HOLDOUT — do not touch; no sheet row.'
                     WHEN w.leak_block = 'ALREADY_PAUSED' THEN FORMAT('It already reads %s in Amazon, so this is trailing spend from before the switch: no book will write a pause row for it and none is needed. It leaves the register on its own when the spend stops, and its dollars are not counted as recovered.', LOWER(w.live_state))
                     WHEN w.leak_block = 'LIVE_STATE_UNKNOWN' THEN 'The state of this switch could not be read in Amazon at all, so no book will write a pause row for it — nothing is paused blind. Check the keyword in Amazon by hand; its dollars are not counted as recovered.'
                     WHEN lbs.stale THEN FORMAT('Its pause row %s; the pending leak book is STALE (a leak exists that no pending book carries), so the one move is to rebuild the book with `tools/build_seat_moves_bulksheet.py --replaces %s` — one book then carries every leak and the old one is labelled never-uploaded. Do not upload %s. The same book judges any search term bleeding under it at the ad group (the acting grain).',
                                                IF(w.pause_pending, FORMAT('is on the pending leak book %s', w.pause_batch_id), 'is on no pending book'), lbs.books, lbs.books)
                     WHEN w.pause_pending THEN FORMAT('Its pause row is already on the pending leak book %s: upload that book, or label it never-uploaded with `tools/build_seat_moves_bulksheet.py --supersede %s` — that is why this row costs $0 on both projections. The same book judges any search term bleeding under it at the ad group (the acting grain).', w.pause_batch_id, w.pause_batch_id)
                     ELSE 'Pause it on the next leak book; the same book judges any search term bleeding under it at the ad group (the acting grain).' END,
                IF(w.holdout AND run_day.d < w.holdout_eligible_from, FORMAT(' Its campaign joins the holdout arm on %s.', CAST(w.holdout_eligible_from AS STRING)), '')) AS sentence,
    -- sheet_row (2026-08-23): the one instruction above, as a code the surfaces can count
    CASE WHEN w.leak_block IS NOT NULL THEN 'NO_SHEET_ROW'
         WHEN lbs.stale THEN 'REBUILD_LEAK_BOOK'
         WHEN w.pause_pending THEN 'PENDING_BOOK'
         ELSE 'NEXT_LEAK_BOOK' END AS sheet_row,
    FORMAT('%s|%02d|%010.2f|%s|%s', w.family, 5, 99999 - w.cost_today, w.campaign_id, w.keyword_id) AS sort_key
  FROM kw w CROSS JOIN run_day CROSS JOIN leak_book_state lbs
  WHERE w.book = 'HARVEST' AND w.code = 'LEAK'
  UNION ALL
  -- GAP rows — spending with no verdict row
  SELECT
    'GAP' AS row_type,
    w.family AS family,
    w.book AS book,
    'today' AS horizon,
    CAST(NULL AS INT64) AS seat_no,
    w.category AS category,
    w.side AS side,
    CAST(NULL AS STRING) AS occupant_kind,
    w.campaign_id AS campaign_id,
    w.campaign_name AS campaign_name,
    w.keyword_id AS keyword_id,
    w.target_text AS target_text,
    CAST(NULL AS STRING) AS match_type,
    CAST(NULL AS STRING) AS state,
    CAST(NULL AS FLOAT64) AS current_bid,
    CAST(NULL AS FLOAT64) AS bid_floor,
    ROUND(w.cost_today, 4) AS cost_per_day,
    ROUND(w.cost_day1, 4) AS cost_day_one,
    ROUND(w.cost_rejudged, 4) AS cost_rejudged,
    CAST(NULL AS STRING) AS book_batch_id,
    CAST(NULL AS STRING) AS book_action,
    CAST(NULL AS FLOAT64) AS book_old_bid,
    CAST(NULL AS FLOAT64) AS book_new_bid,
    CAST(NULL AS FLOAT64) AS raise_old_bid,
    CAST(NULL AS FLOAT64) AS raise_new_bid,
    CAST(NULL AS DATE) AS raised_on,
    CAST(NULL AS INT64) AS clicks_since_raise,
    CAST(NULL AS INT64) AS days_since_raise,
    CAST(NULL AS FLOAT64) AS seat_price,
    CAST(NULL AS DATE) AS due_on,
    w.holdout AS holdout,
    w.holdout_eligible_from AS holdout_eligible_from,
    CASE WHEN NOT w.holdout THEN NULL
              WHEN run_day.d >= w.holdout_eligible_from THEN FORMAT('HOLDOUT — do not touch: this campaign is in the holdout arm since %s and is excluded from every sheet', CAST(w.holdout_eligible_from AS STRING))
              ELSE FORMAT('HOLDOUT arm from %s — a sheet may touch it until then and must not after', CAST(w.holdout_eligible_from AS STRING)) END AS holdout_note,
    CAST(NULL AS FLOAT64) AS spend_basis_per_day,
    CAST(NULL AS FLOAT64) AS spend_context_per_day,
    CAST(NULL AS FLOAT64) AS spend_horizon_per_day,
    CAST(NULL AS FLOAT64) AS judged_per_day,
    CAST(NULL AS FLOAT64) AS defense_per_day,
    CAST(NULL AS FLOAT64) AS good_side_per_day,
    CAST(NULL AS FLOAT64) AS bad_side_per_day,
    CAST(NULL AS FLOAT64) AS good_share,
    CAST(NULL AS STRING) AS doctrine_status,
    CAST(NULL AS FLOAT64) AS allowance_per_day,
    CAST(NULL AS FLOAT64) AS seats_cost_per_day,
    CAST(NULL AS FLOAT64) AS leak_per_day,
    CAST(NULL AS FLOAT64) AS gap_per_day,
    CAST(NULL AS FLOAT64) AS open_capacity_per_day,
    CAST(NULL AS FLOAT64) AS over_by_per_day,
    CAST(NULL AS FLOAT64) AS at_line_band,
    CAST(NULL AS STRING) AS at_line_band_derivation,
    1 AS n_keywords,
    CAST(NULL AS STRING) AS horizon_assumption,
    -- R-k refined: the move is worded by the MEASURED cause, never a blanket claim
    CASE w.gap_cause
      WHEN 'NO_ID' THEN 'no sheet row — this row reaches the warehouse with no keyword id (keyword_id −1, how SB video / PT product targets arrive), so the verdict ladder cannot see it; the spend stays untracked until the ladder learns to read these rows (a ruling for Ori, not a mapping fix)'
      WHEN 'DISABLED' THEN FORMAT('no sheet row — this target is %s on Amazon (its current DIM_KEYWORD row): the spend is trailing and the row leaves the universe when it stops; no verdict is coming and none is needed', LOWER(COALESCE(w.dim_state, 'disabled')))
      WHEN 'NEWLY_SEEN' THEN 'no sheet row — the target is enabled with no verdict row yet: the verdict arrives on the next state run if the campaign is mapped; otherwise check why the ladder does not track it'
      ELSE 'no sheet row — check why the ladder does not track this target: it has a real keyword id but no current DIM_KEYWORD row'
    END AS move,
    CASE w.gap_cause
      WHEN 'NO_ID' THEN
        FORMAT('%s (%s) spent $%.2f/day on the basis window with no verdict row — %s from the SB video report, which carries no keyword id (keyword_id −1), so the verdict ladder cannot see it (the ladder does track SP product targets, which carry one); the spend stays untracked on the 20%% side until the ladder learns to read these rows (a ruling for Ori, not a mapping fix).%s',
               w.target_text, w.campaign_name, w.cost_today, IF(w.is_product_target, 'a product target', 'a row'),
               IF(w.holdout AND run_day.d >= w.holdout_eligible_from, ' HOLDOUT — do not touch.', ''))
      WHEN 'DISABLED' THEN
        FORMAT('%s (%s) is %s on Amazon (its current DIM_KEYWORD row) yet spent $%.2f/day on the basis window — trailing spend, not a live gap: it counts on the 20%% side while it lasts and leaves the universe when it stops. No verdict is coming and none is needed.%s',
               w.target_text, w.campaign_name, LOWER(COALESCE(w.dim_state, 'disabled')), w.cost_today,
               IF(w.holdout AND run_day.d >= w.holdout_eligible_from, ' HOLDOUT — do not touch.', ''))
      WHEN 'NEWLY_SEEN' THEN
        FORMAT('%s (%s) spent $%.2f/day on the basis window with no verdict row on the ladder — untracked spend counts on the 20%% side. The target is enabled: if the campaign was mapped to %s recently, the verdict arrives on the next state run; otherwise check why the ladder does not track it.%s',
               w.target_text, w.campaign_name, w.cost_today, w.family,
               IF(w.holdout AND run_day.d >= w.holdout_eligible_from, ' HOLDOUT — do not touch.', ''))
      ELSE
        FORMAT('%s (%s) spent $%.2f/day on the basis window with no verdict row, a real keyword id and no current DIM_KEYWORD row — check why the ladder does not track it; untracked on the 20%% side until then.%s',
               w.target_text, w.campaign_name, w.cost_today,
               IF(w.holdout AND run_day.d >= w.holdout_eligible_from, ' HOLDOUT — do not touch.', ''))
    END AS sentence,
    CAST(NULL AS STRING) AS sheet_row,
    FORMAT('%s|%02d|%010.2f|%s|%s', w.family, 6, 99999 - w.cost_today, w.campaign_id, w.keyword_id) AS sort_key
  FROM kw w CROSS JOIN run_day
  WHERE w.book = 'HARVEST' AND w.code = 'GAP'
  UNION ALL
  -- NO_CLOCK rows — a trial whose bid moved outside the change log (R-d): its own category, its own move
  SELECT
    'NO_CLOCK' AS row_type,
    w.family AS family,
    w.book AS book,
    'today' AS horizon,
    CAST(NULL AS INT64) AS seat_no,
    w.category AS category,
    w.side AS side,
    CAST(NULL AS STRING) AS occupant_kind,
    w.campaign_id AS campaign_id,
    w.campaign_name AS campaign_name,
    w.keyword_id AS keyword_id,
    w.target_text AS target_text,
    w.match_type AS match_type,
    w.state AS state,
    w.current_bid AS current_bid,
    w.bid_floor AS bid_floor,
    ROUND(w.cost_today, 4) AS cost_per_day,
    ROUND(w.cost_day1, 4) AS cost_day_one,
    ROUND(w.cost_rejudged, 4) AS cost_rejudged,
    w.book_batch_id AS book_batch_id,
    w.book_action AS book_action,
    w.book_old_bid AS book_old_bid,
    w.book_new_bid AS book_new_bid,
    CAST(NULL AS FLOAT64) AS raise_old_bid,
    CAST(NULL AS FLOAT64) AS raise_new_bid,
    CAST(NULL AS DATE) AS raised_on,
    CAST(NULL AS INT64) AS clicks_since_raise,
    CAST(NULL AS INT64) AS days_since_raise,
    CAST(NULL AS FLOAT64) AS seat_price,
    CAST(NULL AS DATE) AS due_on,
    w.holdout AS holdout,
    w.holdout_eligible_from AS holdout_eligible_from,
    CASE WHEN NOT w.holdout THEN NULL
              WHEN run_day.d >= w.holdout_eligible_from THEN FORMAT('HOLDOUT — do not touch: this campaign is in the holdout arm since %s and is excluded from every sheet', CAST(w.holdout_eligible_from AS STRING))
              ELSE FORMAT('HOLDOUT arm from %s — a sheet may touch it until then and must not after', CAST(w.holdout_eligible_from AS STRING)) END AS holdout_note,
    CAST(NULL AS FLOAT64) AS spend_basis_per_day,
    CAST(NULL AS FLOAT64) AS spend_context_per_day,
    CAST(NULL AS FLOAT64) AS spend_horizon_per_day,
    CAST(NULL AS FLOAT64) AS judged_per_day,
    CAST(NULL AS FLOAT64) AS defense_per_day,
    CAST(NULL AS FLOAT64) AS good_side_per_day,
    CAST(NULL AS FLOAT64) AS bad_side_per_day,
    CAST(NULL AS FLOAT64) AS good_share,
    CAST(NULL AS STRING) AS doctrine_status,
    CAST(NULL AS FLOAT64) AS allowance_per_day,
    CAST(NULL AS FLOAT64) AS seats_cost_per_day,
    CAST(NULL AS FLOAT64) AS leak_per_day,
    CAST(NULL AS FLOAT64) AS gap_per_day,
    CAST(NULL AS FLOAT64) AS open_capacity_per_day,
    CAST(NULL AS FLOAT64) AS over_by_per_day,
    CAST(NULL AS FLOAT64) AS at_line_band,
    CAST(NULL AS STRING) AS at_line_band_derivation,
    1 AS n_keywords,
    CAST(NULL AS STRING) AS horizon_assumption,
    IF(w.holdout AND run_day.d >= w.holdout_eligible_from, 'no sheet row — holdout campaign; the bid stays as it is',
            'log the bid (or restore it by sheet) so the clock can start') AS move,
    FORMAT('%s (%s) is a trial at bid $%.2f spending $%.2f/day, but this bid was set outside the change log, so there is no date to judge it from. %s%s',
                w.target_text, w.campaign_name, w.current_bid, w.cost_today,
                IF(w.holdout AND run_day.d >= w.holdout_eligible_from, 'HOLDOUT — do not touch; no sheet row.',
                   'Log the bid (or restore it by sheet) so the clock can start; it counts on the 80% side until then.'),
                IF(w.holdout AND run_day.d < w.holdout_eligible_from, FORMAT(' Its campaign joins the holdout arm on %s.', CAST(w.holdout_eligible_from AS STRING)), '')) AS sentence,
    CAST(NULL AS STRING) AS sheet_row,
    FORMAT('%s|%02d|%010.2f|%s|%s', w.family, 8, 99999 - w.cost_today, w.campaign_id, w.keyword_id) AS sort_key
  FROM kw w CROSS JOIN run_day
  WHERE w.book = 'HARVEST' AND w.code = 'WAITING_NO_CLOCK'
  UNION ALL
  -- ABSORB rows — advisory only
  SELECT
    'ABSORB' AS row_type,
    a.family AS family,
    'HARVEST' AS book,
    'today' AS horizon,
    CAST(NULL AS INT64) AS seat_no,
    'could absorb freed spend' AS category,
    CAST(NULL AS STRING) AS side,
    CAST(NULL AS STRING) AS occupant_kind,
    a.campaign_id AS campaign_id,
    a.campaign_name AS campaign_name,
    CAST(NULL AS STRING) AS keyword_id,
    CAST(NULL AS STRING) AS target_text,
    CAST(NULL AS STRING) AS match_type,
    CAST(NULL AS STRING) AS state,
    CAST(NULL AS FLOAT64) AS current_bid,
    CAST(NULL AS FLOAT64) AS bid_floor,
    CAST(NULL AS FLOAT64) AS cost_per_day,
    CAST(NULL AS FLOAT64) AS cost_day_one,
    CAST(NULL AS FLOAT64) AS cost_rejudged,
    CAST(NULL AS STRING) AS book_batch_id,
    CAST(NULL AS STRING) AS book_action,
    CAST(NULL AS FLOAT64) AS book_old_bid,
    CAST(NULL AS FLOAT64) AS book_new_bid,
    CAST(NULL AS FLOAT64) AS raise_old_bid,
    CAST(NULL AS FLOAT64) AS raise_new_bid,
    CAST(NULL AS DATE) AS raised_on,
    CAST(NULL AS INT64) AS clicks_since_raise,
    CAST(NULL AS INT64) AS days_since_raise,
    CAST(NULL AS FLOAT64) AS seat_price,
    CAST(NULL AS DATE) AS due_on,
    a.holdout AS holdout,
    a.holdout_eligible_from AS holdout_eligible_from,
    CASE WHEN NOT a.holdout THEN NULL
              WHEN run_day.d >= a.holdout_eligible_from THEN FORMAT('HOLDOUT — do not touch: this campaign is in the holdout arm since %s and is excluded from every sheet', CAST(a.holdout_eligible_from AS STRING))
              ELSE FORMAT('HOLDOUT arm from %s — a sheet may touch it until then and must not after', CAST(a.holdout_eligible_from AS STRING)) END AS holdout_note,
    CAST(NULL AS FLOAT64) AS spend_basis_per_day,
    CAST(NULL AS FLOAT64) AS spend_context_per_day,
    CAST(NULL AS FLOAT64) AS spend_horizon_per_day,
    CAST(NULL AS FLOAT64) AS judged_per_day,
    CAST(NULL AS FLOAT64) AS defense_per_day,
    CAST(NULL AS FLOAT64) AS good_side_per_day,
    CAST(NULL AS FLOAT64) AS bad_side_per_day,
    CAST(NULL AS FLOAT64) AS good_share,
    CAST(NULL AS STRING) AS doctrine_status,
    CAST(NULL AS FLOAT64) AS allowance_per_day,
    CAST(NULL AS FLOAT64) AS seats_cost_per_day,
    CAST(NULL AS FLOAT64) AS leak_per_day,
    CAST(NULL AS FLOAT64) AS gap_per_day,
    CAST(NULL AS FLOAT64) AS open_capacity_per_day,
    CAST(NULL AS FLOAT64) AS over_by_per_day,
    CAST(NULL AS FLOAT64) AS at_line_band,
    CAST(NULL AS STRING) AS at_line_band_derivation,
    CAST(NULL AS INT64) AS n_keywords,
    CAST(NULL AS STRING) AS horizon_assumption,
    IF(a.holdout AND run_day.d >= a.holdout_eligible_from,
       'advisory suppressed — holdout campaign; send no freed spend here while the arm runs',
       'advisory only — budgets are shown, never moved by the register') AS move,
    CONCAT(FORMAT('could absorb freed spend: %s — above its family bar (7-day GP-ROAS %.2fx vs bar %.2fx), capped %d of the last 7 days ($%.2f spent on a $%.2f budget). Advisory only; the register moves no budget.',
                a.campaign_name, a.gp_roas_7d, a.keyword_bar, a.days_capped_7d, a.spend_7d, a.budget_7d),
           CASE WHEN a.holdout AND run_day.d >= a.holdout_eligible_from THEN ' HOLDOUT — advisory suppressed: this campaign is in the holdout arm and takes no freed spend.'
                WHEN a.holdout THEN FORMAT(' Its campaign joins the holdout arm on %s; the advisory stops then.', CAST(a.holdout_eligible_from AS STRING))
                ELSE '' END) AS sentence,
    CAST(NULL AS STRING) AS sheet_row,
    FORMAT('%s|%02d|%s||', a.family, 7, a.campaign_id) AS sort_key
  FROM absorb a CROSS JOIN run_day
  UNION ALL
  -- UNMAPPED rows — spend in the cracks: one per campaign no family claims, plus one total row
  SELECT
    'UNMAPPED' AS row_type,
    'Unmapped' AS family,
    CAST(NULL AS STRING) AS book,
    'today' AS horizon,
    CAST(NULL AS INT64) AS seat_no,
    'unmapped — no family claims this spend' AS category,
    'UNMAPPED' AS side,
    CAST(NULL AS STRING) AS occupant_kind,
    x.campaign_id AS campaign_id,
    x.campaign_name AS campaign_name,
    CAST(NULL AS STRING) AS keyword_id,
    CAST(NULL AS STRING) AS target_text,
    CAST(NULL AS STRING) AS match_type,
    CAST(NULL AS STRING) AS state,
    CAST(NULL AS FLOAT64) AS current_bid,
    CAST(NULL AS FLOAT64) AS bid_floor,
    ROUND(x.spend7 / k.basis_days, 4) AS cost_per_day,
    ROUND(x.spend7 / k.basis_days, 4) AS cost_day_one,
    ROUND(x.spend7 / k.basis_days, 4) AS cost_rejudged,
    CAST(NULL AS STRING) AS book_batch_id,
    CAST(NULL AS STRING) AS book_action,
    CAST(NULL AS FLOAT64) AS book_old_bid,
    CAST(NULL AS FLOAT64) AS book_new_bid,
    CAST(NULL AS FLOAT64) AS raise_old_bid,
    CAST(NULL AS FLOAT64) AS raise_new_bid,
    CAST(NULL AS DATE) AS raised_on,
    CAST(NULL AS INT64) AS clicks_since_raise,
    CAST(NULL AS INT64) AS days_since_raise,
    CAST(NULL AS FLOAT64) AS seat_price,
    CAST(NULL AS DATE) AS due_on,
    IF(x.campaign_id IS NULL, NULL, x.holdout) AS holdout,
    x.holdout_eligible_from AS holdout_eligible_from,
    CASE WHEN x.campaign_id IS NULL OR NOT x.holdout THEN NULL
              WHEN run_day.d >= x.holdout_eligible_from THEN FORMAT('HOLDOUT — do not touch: this campaign is in the holdout arm since %s and is excluded from every sheet', CAST(x.holdout_eligible_from AS STRING))
              ELSE FORMAT('HOLDOUT arm from %s — a sheet may touch it until then and must not after', CAST(x.holdout_eligible_from AS STRING)) END AS holdout_note,
    ROUND(x.spend7 / k.basis_days, 4) AS spend_basis_per_day,
    CAST(NULL AS FLOAT64) AS spend_context_per_day,
    ROUND(x.spend7 / k.basis_days, 4) AS spend_horizon_per_day,
    CAST(NULL AS FLOAT64) AS judged_per_day,
    CAST(NULL AS FLOAT64) AS defense_per_day,
    CAST(NULL AS FLOAT64) AS good_side_per_day,
    CAST(NULL AS FLOAT64) AS bad_side_per_day,
    CAST(NULL AS FLOAT64) AS good_share,
    'UNMAPPED' AS doctrine_status,
    CAST(NULL AS FLOAT64) AS allowance_per_day,
    CAST(NULL AS FLOAT64) AS seats_cost_per_day,
    CAST(NULL AS FLOAT64) AS leak_per_day,
    CAST(NULL AS FLOAT64) AS gap_per_day,
    CAST(NULL AS FLOAT64) AS open_capacity_per_day,
    CAST(NULL AS FLOAT64) AS over_by_per_day,
    CAST(NULL AS FLOAT64) AS at_line_band,
    CAST(NULL AS STRING) AS at_line_band_derivation,
    x.n_campaigns AS n_keywords,
    CAST(NULL AS STRING) AS horizon_assumption,
    IF(x.campaign_id IS NULL,
       'map every campaign below to its family in Admin (Campaign Mapping); the next state run then judges it inside that family',
       'map this campaign to its family in Admin (Campaign Mapping) — the register cannot guess a family from a name; until then no family answers for this spend') AS move,
    IF(x.campaign_id IS NULL,
       FORMAT('UNMAPPED — $%.2f/day on the basis window in %d campaigns that no family claims (no family bar, no verdict row with a family). This money is outside every family read above, so no family can pass by leaving it here. Map each campaign to its family in Admin; the next state run judges it there.',
              x.spend7 / k.basis_days, x.n_campaigns),
       CONCAT(FORMAT('%s spent $%.2f/day on the basis window (%d clicks) and no family claims it — it is in no family read. Map it to its family in Admin; until then no family answers for this spend.',
                     x.campaign_name, x.spend7 / k.basis_days, x.clicks7),
              IF(x.holdout AND run_day.d >= x.holdout_eligible_from, ' HOLDOUT — do not touch; no sheet row.', ''),
              IF(x.holdout AND run_day.d < x.holdout_eligible_from, FORMAT(' Its campaign joins the holdout arm on %s.', CAST(x.holdout_eligible_from AS STRING)), ''))) AS sentence,
    CAST(NULL AS STRING) AS sheet_row,
    FORMAT('%s|%02d|%010.2f|%s|', 'Unmapped', IF(x.campaign_id IS NULL, 1, 2), IF(x.campaign_id IS NULL, 0, 99999 - x.spend7 / k.basis_days), COALESCE(x.campaign_id, '')) AS sort_key
  FROM (
    SELECT campaign_id, campaign_name, spend7, clicks7, holdout, holdout_eligible_from, CAST(NULL AS INT64) AS n_campaigns FROM unmapped
    UNION ALL
    SELECT NULL, NULL, SUM(spend7), SUM(clicks7), NULL, NULL, COUNT(*) FROM unmapped
  ) x CROSS JOIN k CROSS JOIN run_day
  WHERE x.campaign_id IS NOT NULL OR x.n_campaigns > 0
)
SELECT s.*, run_day.d AS as_of, win.basis_to AS ads_basis_to, win.basis_from AS ads_basis_from
FROM shape s CROSS JOIN run_day CROSS JOIN win;
