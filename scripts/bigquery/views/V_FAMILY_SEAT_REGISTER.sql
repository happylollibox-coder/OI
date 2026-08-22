-- =============================================
-- V_FAMILY_SEAT_REGISTER — the object Ori reads every morning for the 80/20 doctrine.
-- Spec: docs/superpowers/specs/2026-08-22-family-seat-register-design.md §3–§6 and
-- architecture/FAMILY_SEAT_REGISTER.md (rulings R-a … R-e). Task 2 of the family seat register.
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
-- keywords in SB campaigns (the Bottle 'happy lolli truth or dare' family of trials).
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
--              worded by the size of the raise (ruling R-c).
--   OPEN_SEAT  one per working family: the lowest free seat number, the open capacity, and the
--              next probe candidate from the budget engine's queue the capacity can afford
--              (admission cost = seat price × the engine's daily click goal).
--   LEAK       one per closed-but-spending keyword (PARKED / DEAD with spend in the window).
--   GAP        one per spending keyword with no verdict row on the ladder.
--   NO_CLOCK   one per trial whose bid moved outside the change log (ruling R-d): 80% side, its
--              own sentence ("no date to judge it from") and move ("log the bid so the clock starts").
--   ABSORB     advisory only: an above-bar campaign in the family capped ≥ k.absorb_capped_days of
--              the last 7 that could take freed spend. Budgets are never moved by this register.
--   REFERENCE  one per launch family: the same categories priced, no doctrine read.
--
-- CATEGORIES (category ← ladder state, rulings in the SOP):
--   winning                                  WINNER, PACED_WINNER                              80
--   marginal — at its bar                    AT_BAR                                            80
--   waiting — too few clicks yet             TRIAL in no probe position, bid moved by the book  80
--   waiting — no test clock                  TRIAL whose bid moved with NO applied log row     80  (R-d)
--   waiting — verdict settling               REVIVED_SETTLING, PENDING_SETTLE (seated, 80 side)  80
--   losing — in repair                       REPRICE                                           20 seat
--   losing — on probation at its floor       FLOOR_PROBATION                                   20 seat
--   losing — failed at its floor             LOSER                                             20 seat
--   probe — being bought at an entry bid     TRIAL engine-listed (T_LIFT_PROBES) or at floor w/ spend  20 seat (R-a)
--   probe — stalled                          TRIAL, standing applied raise past the engine's test  20 seat (R-b, R-c)
--   idle at the floor                        TRIAL at the floor, $0, 0 clicks — shown, no side  (R-e)
--   closed but still spending                PARKED / DEAD with spend                          20 leak
--   untracked — no verdict row               spend with no FACT_KEYWORD_STATE row              20 gap
--   brand defense — never judged on profit   see above                                         outside
--   launch — contained                       LAUNCH_CONTAINED (reference families only)        outside
--   Anything else is 'other — <state>' on the 20% side: a family cannot pass by hiding spend.
--
-- HORIZONS (FAMILY / CATEGORY rows, column horizon):
--   today      measured on the basis window; nothing assumed.
--   day one    the PENDING_UPLOAD book lands: each keyword on it spends in proportion to
--              new_bid ÷ old_bid (a linear bid→spend guess, not a measurement); closed-but-spending
--              keywords are paused (→ $0); everything else as today.
--   re-judged  repairs hold at their bar and move to the good side at their day-one cost;
--              probation keywords stay on the 20% side at their floor; failed keywords are killed
--              (→ $0); stalled probes are parked (→ $0); engine probes keep their day-one cost;
--              settling verdicts hold; leaks paused; untracked unchanged.
--
-- DECLARED CONSTANTS (the k CTE; Standing Rule 0 exempt — design choices, not measurements):
--   allowance_share 0.20 (the doctrine) · basis_days 7 · context_days 28 · probe_window_days 14
--   and verdict_clicks 20 (the engine's probing test, mirrored from V_KEYWORD_LIFT) ·
--   click_goal_day 4 (V_OOB_KEYWORD's seat model: slots = budget ÷ $4, one 4-click trial a day) ·
--   absorb_capped_days 4 · entry_raise_ratio 1.5 (a raise by half or more is an ENTRY, less is a
--   NUDGE — the wording rule of R-c) · bid_tol 0.005.
--   at_line_band is DERIVED, not declared: the relative noise of a 7-day spend read for the
--   SMALLEST working family — stddev ÷ mean of its daily spend over the context window, divided
--   by sqrt(basis_days) — published on every FAMILY row with its derivation in words.
--
-- PLANNER DOCTRINE. Reads FACT_KEYWORD_STATE, T_FAMILY_BAR, FACT_AMAZON_ADS, DE_FAMILY_SEAT_LEDGER,
-- T_LIFT_PROBES, T_OOB_SEAT_ECONOMICS (V_OOB_KEYWORD is a planner-ceiling view that takes minutes;
-- its seat economics are materialised once per pass by SP_REFRESH_CUBE_TABLES), V_CAMPAIGN_CAP_STATE
-- (measured light: tens of MB, seconds), V_PPC_CHANGE_LOG_APPLIED, FACT_PPC_CHANGE_LOG (the
-- PENDING_UPLOAD book only), DIM_KEYWORD (bid versions), DIM_BRAND_PHRASES, DE_HOLDOUT_ASSIGNMENT,
-- V_BOOK_ASSIGNMENT. Never a ceiling view.
--
-- WHAT IT NEVER DOES. No engine reads it. No budget is moved. No bid is set. Every sheet it
-- prescribes is built by a generator and uploaded by Ori. Holdout campaigns are marked on every
-- SEAT / LEAK / GAP row and excluded from every sheet from their eligible_from date.
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
brand AS (SELECT DISTINCT LOWER(phrase) AS phrase
          FROM `onyga-482313.OI.DIM_BRAND_PHRASES` WHERE phrase_type = 'BRAND'),
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
-- how many distinct bids the keyword has ever carried (DIM_KEYWORD SCD2): > 1 means the bid moved
bidv AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         COUNT(DISTINCT ROUND(bid, 2)) AS bid_versions
  FROM `onyga-482313.OI.DIM_KEYWORD` GROUP BY 1, 2),
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
-- at_line_band: the relative noise of a 7-day spend read for the smallest working family
fam_day AS (
  SELECT f.family, a.date, SUM(a.Ads_cost) AS sp
  FROM ads a JOIN fam f ON f.campaign_id = a.cid
  JOIN books b ON b.family = f.family AND b.book = 'HARVEST'
  CROSS JOIN win
  WHERE a.date >= win.context_from
  GROUP BY 1, 2),
fam_noise AS (
  SELECT family, SUM(sp) AS sp_ctx, AVG(sp) AS mean_day, STDDEV_SAMP(sp) AS sd_day, COUNT(*) AS days_seen
  FROM fam_day GROUP BY 1),
band AS (
  SELECT n.family AS smallest_family,
         ROUND(SAFE_DIVIDE(n.sd_day, NULLIF(n.mean_day, 0)) / SQRT(k.basis_days), 3) AS at_line_band,
         FORMAT('at_line_band = (stddev ÷ mean of daily spend over the %d-day context window for the smallest working family, %s, on its %d days with spend) ÷ sqrt(%d basis days) = %.3f — a share within that many points under the 80%% line is indistinguishable from the line on a 7-day read',
                k.context_days, n.family, n.days_seen, k.basis_days,
                ROUND(SAFE_DIVIDE(n.sd_day, NULLIF(n.mean_day, 0)) / SQRT(k.basis_days), 3)) AS at_line_band_derivation
  FROM fam_noise n CROSS JOIN k
  ORDER BY n.sp_ctx, n.family LIMIT 1),
brand_hit AS (
  SELECT DISTINCT s.campaign_id, s.keyword_id
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
  JOIN brand b ON LOWER(s.target_text) LIKE CONCAT('%', b.phrase, '%')),
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
         is_defense AS oob_is_defense
  FROM `onyga-482313.OI.T_OOB_SEAT_ECONOMICS`),
oob_camp AS (SELECT campaign_id, MAX(seat_cpc) AS seat_cpc, MAX(slots) AS slots FROM oob GROUP BY 1),
ledger AS (
  SELECT family, campaign_id, keyword_id, seat_no, opened_on
  FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` WHERE closed_on IS NULL),
-- ── the universe: every keyword in a family campaign that is on the ladder OR spent in the window
u AS (
  SELECT COALESCE(s.campaign_id, a.cid) AS campaign_id,
         COALESCE(s.keyword_id, a.kid) AS keyword_id,
         COALESCE(s.family, f.family) AS family,
         COALESCE(s.campaign_name, a.ads_campaign_name) AS campaign_name,
         COALESCE(s.target_text, a.targeting) AS target_text,
         s.match_type, s.channel, s.state, s.current_bid, s.bid_floor, COALESCE(s.at_floor, FALSE) AS at_floor,
         s.next_check_date, s.state_since, COALESCE(s.is_defense, FALSE) AS is_defense,
         s.campaign_id IS NOT NULL AS on_ladder,
         COALESCE(a.spend7, 0) AS spend7, COALESCE(a.clicks7, 0) AS clicks7,
         COALESCE(a.spend28, 0) AS spend28, COALESCE(a.clicks_since_raise, 0) AS clicks_since_raise,
         f.keyword_bar
  FROM snap s
  FULL OUTER JOIN kw_ads a ON a.cid = s.campaign_id AND a.kid = s.keyword_id
  LEFT JOIN fam f ON f.campaign_id = COALESCE(s.campaign_id, a.cid)
  WHERE COALESCE(s.family, f.family) IS NOT NULL),
-- ── the positions (R-a … R-e) and the code
c AS (
  SELECT u.*, b.book,
         p.kid IS NOT NULL AS engine_probe,
         lc.action AS raise_action, lc.chg_date AS raised_on, lc.old_bid AS raise_old_bid, lc.new_bid AS raise_new_bid,
         pd.batch_id AS book_batch_id, pd.action AS book_action, pd.old_bid AS book_old_bid, pd.new_bid AS book_new_bid,
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
         oc.seat_cpc AS seat_price, oc.slots AS campaign_slots
  FROM u CROSS JOIN k CROSS JOIN run_day
  LEFT JOIN books b ON b.family = u.family
  LEFT JOIN probes p ON p.kid = u.keyword_id
  LEFT JOIN lastchg lc ON lc.campaign_id = u.campaign_id AND lc.keyword_id = u.keyword_id
  LEFT JOIN pending pd ON pd.campaign_id = u.campaign_id AND pd.keyword_id = u.keyword_id
  LEFT JOIN bidv bv ON bv.cid = u.campaign_id AND bv.kid = u.keyword_id
  LEFT JOIN holdout h ON h.campaign_id = u.campaign_id
  LEFT JOIN oob_camp oc ON oc.campaign_id = u.campaign_id),
coded AS (
  SELECT c.*,
    CASE
      WHEN NOT on_ladder                                          THEN 'GAP'
      WHEN is_defense                                             THEN 'DEFENSE'
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
      WHEN state = 'TRIAL'                                        THEN 'WAITING'
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
  SELECT 'LEAK',                     'closed but still spending',                       '20',         NULL,                           11 UNION ALL
  SELECT 'GAP',                      'untracked — no verdict row',                      '20',         NULL,                           12 UNION ALL
  SELECT 'OTHER',                    'other — not earning, not being tested',           '20',         NULL,                           13 UNION ALL
  SELECT 'IDLE_FLOOR',               'idle at the floor',                               'NONE',       NULL,                           14 UNION ALL
  SELECT 'CLOSED_QUIET',             'closed — not spending',                           'NONE',       NULL,                           15 UNION ALL
  SELECT 'DEFENSE',                  'brand defense — never judged on profit',          'DEFENSE',    NULL,                           16 UNION ALL
  SELECT 'LAUNCH',                   'launch — contained',                              'LAUNCH',     NULL,                           17),
-- ── per-keyword costs on the three horizons
kw AS (
  SELECT d.*, x.category, x.side, x.occupant_kind, x.cat_order,
         l.seat_no, l.opened_on AS seat_opened_on,
         d.spend7 / k.basis_days AS cost_today,
         -- day one: the pending book lands (linear bid→spend), leaks paused
         CASE WHEN d.code = 'LEAK' THEN 0
              WHEN d.book_new_bid IS NOT NULL THEN d.spend7 / k.basis_days * SAFE_DIVIDE(d.book_new_bid, d.book_old_bid)
              ELSE d.spend7 / k.basis_days END AS cost_day1,
         x.side AS side_day1,
         -- re-judged: repairs hold at their bar (good side), probation at its floor, failed killed,
         -- stalled parked, probes and settling hold, leaks paused, untracked unchanged
         CASE WHEN d.code IN ('LEAK', 'FAILED', 'STALLED_PROBE') THEN 0
              WHEN d.code = 'PROBATION' THEN d.spend7 / k.basis_days
                   * COALESCE(SAFE_DIVIDE(LEAST(COALESCE(d.book_new_bid, d.current_bid), d.current_bid), NULLIF(d.current_bid, 0)), 1)
              WHEN d.book_new_bid IS NOT NULL THEN d.spend7 / k.basis_days * SAFE_DIVIDE(d.book_new_bid, d.book_old_bid)
              ELSE d.spend7 / k.basis_days END AS cost_rejudged,
         IF(d.code = 'REPAIR', '80', x.side) AS side_rejudged
  FROM coded d CROSS JOIN k
  JOIN codes x ON x.code = d.code
  LEFT JOIN ledger l ON l.family = d.family AND l.campaign_id = d.campaign_id AND l.keyword_id = d.keyword_id),
-- ── family figures per horizon
hz AS (
  SELECT 'today' AS horizon, 1 AS hz_order UNION ALL
  SELECT 'day one', 2 UNION ALL
  SELECT 're-judged', 3),
kw_h AS (
  SELECT kw.*, hz.horizon, hz.hz_order,
         CASE hz.horizon WHEN 'today' THEN cost_today WHEN 'day one' THEN cost_day1 ELSE cost_rejudged END AS cost_h,
         CASE hz.horizon WHEN 're-judged' THEN side_rejudged ELSE side END AS side_h,
         CASE hz.horizon WHEN 're-judged' THEN IF(code = 'REPAIR', 'MARGINAL', code) ELSE code END AS code_h,
         CASE hz.horizon WHEN 're-judged' THEN IF(code = 'REPAIR', 'marginal — at its bar', category) ELSE category END AS category_h
  FROM kw CROSS JOIN hz),
fam_h AS (
  SELECT family, book, horizon, hz_order,
         SUM(cost_today) AS spend_basis_per_day,
         SUM(spend28) / MAX(k.context_days) AS spend_context_per_day,
         SUM(cost_h) AS spend_h_per_day,
         SUM(IF(side_h = '80', cost_h, 0)) AS good_side_per_day,
         SUM(IF(side_h = '20', cost_h, 0)) AS bad_side_per_day,
         SUM(IF(side_h = 'DEFENSE', cost_h, 0)) AS defense_per_day,
         SUM(IF(side_h = 'LAUNCH', cost_h, 0)) AS launch_per_day,
         SUM(IF(side_h = '20' AND occupant_kind IS NOT NULL, cost_h, 0)) AS seats_cost_per_day,
         SUM(IF(code_h = 'LEAK', cost_h, 0)) AS leak_per_day,
         SUM(IF(code_h = 'GAP', cost_h, 0)) AS gap_per_day,
         COUNTIF(occupant_kind IS NOT NULL AND side = '20') AS seats_20,
         COUNTIF(occupant_kind = 'settling') AS seats_settling,
         COUNTIF(code = 'LEAK') AS n_leaks, COUNTIF(code = 'GAP') AS n_gaps,
         COUNTIF(code = 'REPAIR') AS n_repair, COUNTIF(code = 'STALLED_PROBE') AS n_stalled,
         COUNTIF(code = 'FAILED') AS n_failed, COUNTIF(code = 'PROBATION') AS n_probation,
         COUNTIF(code = 'PROBE') AS n_probe, COUNTIF(code = 'DEFENSE') AS n_defense,
         SUM(IF(code = 'REPAIR', cost_day1, 0)) AS repair_day1,
         SUM(IF(code = 'STALLED_PROBE', cost_today, 0)) AS stalled_today,
         COUNT(*) AS n_keywords
  FROM kw_h CROSS JOIN k
  GROUP BY 1, 2, 3, 4),
fam_read AS (
  SELECT f.*, k.allowance_share, band.at_line_band, band.at_line_band_derivation,
         good_side_per_day + bad_side_per_day AS judged_per_day,
         SAFE_DIVIDE(good_side_per_day, NULLIF(good_side_per_day + bad_side_per_day, 0)) AS good_share,
         k.allowance_share * (good_side_per_day + bad_side_per_day) AS allowance_per_day
  FROM fam_h f CROSS JOIN k LEFT JOIN band ON TRUE),
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
           WHEN 'day one' THEN 'projection: the pending book lands — every keyword on it spends in proportion to new bid ÷ old bid (a linear bid→spend guess, not a measurement); closed-but-spending keywords are paused (→ $0); everything else as today'
           ELSE 'projection: the repairs hold at their bar and move to the good side at their day-one cost; probation keywords stay on the 20% side at their floor; failed keywords are killed (→ $0); stalled probes are parked (→ $0); engine probes keep their day-one cost; settling verdicts hold; leaks stay paused; untracked spend is unchanged until the ladder sees it'
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
queue AS (
  SELECT f.family, o.campaign_id, o.campaign_name, o.keyword_id, o.target_text,
         o.seat_rank - o.slots AS queue_pos, o.seat_cpc, o.seat_cpc * k.click_goal_day AS admission_cost_per_day,
         ROW_NUMBER() OVER (PARTITION BY f.family ORDER BY o.seat_rank, o.campaign_id, o.keyword_id) AS rk
  FROM oob o CROSS JOIN k
  JOIN fam f ON f.campaign_id = o.campaign_id
  JOIN books b ON b.family = f.family AND b.book = 'HARVEST'
  WHERE o.role = 'QUEUED' AND NOT COALESCE(o.oob_is_defense, FALSE)),
next_probe AS (
  SELECT q.family, q.campaign_id, q.campaign_name, q.keyword_id, q.target_text, q.queue_pos, q.seat_cpc, q.admission_cost_per_day
  FROM queue q
  JOIN fam_rows fr ON fr.family = q.family AND fr.horizon = 'today'
  WHERE q.admission_cost_per_day <= fr.open_capacity_per_day
  QUALIFY ROW_NUMBER() OVER (PARTITION BY q.family ORDER BY q.rk) = 1),
-- ── absorption advisory: above-bar campaigns capped ≥ k.absorb_capped_days of the last 7
absorb AS (
  SELECT f.family, cs.campaign_id, cs.campaign_name, cs.days_capped_7d, cs.spend_7d, cs.budget_7d,
         SAFE_DIVIDE(ca.gp7, NULLIF(ca.spend7, 0)) AS gp_roas_7d, f.keyword_bar
  FROM `onyga-482313.OI.V_CAMPAIGN_CAP_STATE` cs CROSS JOIN k
  JOIN fam f ON f.campaign_id = cs.campaign_id
  JOIN books b ON b.family = f.family AND b.book = 'HARVEST'
  LEFT JOIN camp_ads ca ON ca.cid = cs.campaign_id
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
           FORMAT('%s — launch family (reference only, never judged on profit): $%.2f/day on the %s horizon, of which $%.2f/day launch-contained, $%.2f/day winning or at its bar, $%.2f/day losing, probed, leaking or untracked, $%.2f/day brand defense. V_INVEST_STATUS owns its governance.',
                  UPPER(f.family), f.spend_h_per_day, f.horizon, f.launch_per_day, f.good_side_per_day, f.bad_side_per_day, f.defense_per_day)
         WHEN f.good_share IS NULL THEN
           FORMAT('%s — no judged spend on the basis window (%s horizon); nothing to read.', UPPER(f.family), f.horizon)
         ELSE
           FORMAT('%s — %d%% good · %s%s (%s horizon). Allowance $%.2f/day (%d%% of the $%.2f/day judged); the 20%% side holds $%.2f/day: %d seats costing $%.2f/day, %d leaks $%.2f/day, %d untracked $%.2f/day; open capacity %s/day. %d settling verdicts are seated but count on the 80%% side. Brand defense $%.2f/day sits outside the ratio. %s',
                  UPPER(f.family), CAST(ROUND(100 * f.good_share) AS INT64),
                  CASE f.doctrine_status WHEN 'IN' THEN 'IN' WHEN 'AT_LINE' THEN 'AT THE LINE' ELSE 'OUT' END,
                  IF(f.doctrine_status = 'OUT', FORMAT(' by $%.2f/day', f.over_by_per_day),
                     IF(f.doctrine_status = 'AT_LINE', FORMAT(' (within %.0f points of 80%%, the 7-day noise)', 100 * f.at_line_band), '')),
                  f.horizon, f.allowance_per_day, CAST(ROUND(100 * f.allowance_share) AS INT64), f.judged_per_day,
                  f.bad_side_per_day, f.seats_20, f.seats_cost_per_day, f.n_leaks, f.leak_per_day, f.n_gaps, f.gap_per_day,
                  IF(f.open_capacity_per_day < 0, FORMAT('−$%.2f', -f.open_capacity_per_day), FORMAT('$%.2f', f.open_capacity_per_day)),
                  f.seats_settling, f.defense_per_day,
                  CASE WHEN f.horizon != 'today' THEN 'This row is a projection — read horizon_assumption.'
                       WHEN f.doctrine_status = 'IN' THEN 'The family passes today; the open capacity is what a new probe may cost.'
                       ELSE CONCAT('What closes the gap: ',
                              IF(f.n_leaks > 0, FORMAT('pause the %d leaks (−$%.2f/day); ', f.n_leaks, f.leak_per_day), ''),
                              IF(f.n_repair > 0, FORMAT('let the %d repairs hold at their bar (−$%.2f/day moves to the good side at the re-judged horizon); ', f.n_repair, f.repair_day1), ''),
                              IF(f.n_stalled > 0, FORMAT('re-price or park the %d stalled probes (−$%.2f/day); ', f.n_stalled, f.stalled_today), ''),
                              IF(f.n_failed > 0, FORMAT('kill the %d failed keywords; ', f.n_failed), ''),
                              IF(f.n_gaps > 0, FORMAT('the %d untracked targets get a verdict on the next state run.', f.n_gaps), ''))
                  END)
         END AS sentence,
    FORMAT('%s|%02d|%02d|', f.family, IF(f.book = 'INVEST', 9, 1), f.hz_order) AS sort_key
  FROM fam_rows f
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
    IF(w.code = 'STALLED_PROBE', DATE_DIFF(win.basis_to, w.raised_on, DAY), NULL) AS days_since_raise,
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
    CASE w.code
           WHEN 'REPAIR' THEN IF(w.book_new_bid IS NOT NULL,
                                 FORMAT('on the pending book %s: $%.2f → $%.2f (%s); re-judge %s', w.book_batch_id, w.book_old_bid, w.book_new_bid, w.book_action, CAST(w.next_check_date AS STRING)),
                                 FORMAT('no row on the pending book — the reprice generator (tools/build_reprice_bulksheet.py) prices it; re-judge %s', CAST(w.next_check_date AS STRING)))
           WHEN 'PROBATION' THEN IF(w.book_new_bid IS NOT NULL,
                                 FORMAT('on the pending book %s: $%.2f → $%.2f (%s) — hold at the floor, judge %s', w.book_batch_id, w.book_old_bid, w.book_new_bid, w.book_action, CAST(w.next_check_date AS STRING)),
                                 FORMAT('hold at its floor $%.2f; judge %s', COALESCE(w.bid_floor, 0), CAST(w.next_check_date AS STRING)))
           WHEN 'FAILED' THEN 'kill it on the next book (pause row) — it lost at its floor after probation'
           WHEN 'PROBE' THEN 'no move — the engine is buying its verdict; the seat closes on the verdict'
           WHEN 'SETTLING' THEN FORMAT('no move — its verdict settles %s', CAST(w.next_check_date AS STRING))
           WHEN 'STALLED_PROBE' THEN IF(w.seat_price IS NOT NULL,
                                 FORMAT('raise to the seat price $%.2f to get a verdict, or park it at its floor $%.2f', w.seat_price, COALESCE(w.bid_floor, 0)),
                                 FORMAT('its campaign is outside the budget engine\'s seat model, so no seat price is published — price it by hand to get a verdict, or park it at its floor $%.2f', COALESCE(w.bid_floor, 0)))
         END AS move,
    CONCAT(
           FORMAT('seat %s — %s (%s) ', COALESCE(CAST(w.seat_no AS STRING), '?'), w.target_text, w.campaign_name),
           CASE w.code
             WHEN 'REPAIR' THEN FORMAT('is losing and being re-priced toward its bar: $%.2f/day at bid $%.2f', w.cost_today, w.current_bid)
             WHEN 'PROBATION' THEN FORMAT('is losing and held at its floor to be seen serving: $%.2f/day at bid $%.2f', w.cost_today, w.current_bid)
             WHEN 'FAILED' THEN FORMAT('lost at its floor: $%.2f/day at bid $%.2f', w.cost_today, w.current_bid)
             WHEN 'PROBE' THEN FORMAT('is a trial being bought at an entry bid: $%.2f/day at bid $%.2f%s', w.cost_today, w.current_bid,
                                      IF(w.engine_probe, ' (on the engine\'s probe list)', ' (at the park bid, with spend)'))
             WHEN 'SETTLING' THEN FORMAT('has a verdict pending until its clicks settle: $%.2f/day at bid $%.2f', w.cost_today, w.current_bid)
             WHEN 'STALLED_PROBE' THEN
               CONCAT(
                 IF(SAFE_DIVIDE(w.raise_new_bid, NULLIF(w.raise_old_bid, 0)) >= k.entry_raise_ratio,
                    FORMAT('entered at $%.2f on %s', w.raise_new_bid, FORMAT_DATE('%b %e', w.raised_on)),
                    FORMAT('was nudged $%.2f→$%.2f on %s', w.raise_old_bid, w.raise_new_bid, FORMAT_DATE('%b %e', w.raised_on))),
                 IF(w.current_bid > w.raise_new_bid + k.bid_tol, FORMAT(', now sitting at $%.2f', w.current_bid), ''),
                 FORMAT(' — %d clicks in the %d complete days since ($%.2f/day): the engine\'s own test (%d clicks in %d days) has expired without a verdict, so it is neither earning nor being tested',
                        w.clicks_since_raise, DATE_DIFF(win.basis_to, w.raised_on, DAY), w.cost_today, k.verdict_clicks, k.probe_window_days))
           END,
           IF(w.occupant_kind = 'settling', ' — seated, but counted on the 80% side (ruling)', ''),
           '. ',
           CASE w.code
             WHEN 'REPAIR' THEN IF(w.book_new_bid IS NOT NULL, FORMAT('On the book: $%.2f → $%.2f; re-judge %s.', w.book_old_bid, w.book_new_bid, CAST(w.next_check_date AS STRING)), FORMAT('Re-judge %s.', CAST(w.next_check_date AS STRING)))
             WHEN 'PROBATION' THEN FORMAT('Judge %s.', CAST(w.next_check_date AS STRING))
             WHEN 'FAILED' THEN 'Kill it on the next book.'
             WHEN 'PROBE' THEN 'No move; the seat closes on the verdict.'
             WHEN 'SETTLING' THEN FORMAT('No move; settles %s.', CAST(w.next_check_date AS STRING))
             WHEN 'STALLED_PROBE' THEN IF(w.seat_price IS NOT NULL,
                                        FORMAT('Raise to the seat price $%.2f to get a verdict, or park it at its floor $%.2f.', w.seat_price, COALESCE(w.bid_floor, 0)),
                                        FORMAT('No seat price is published for its campaign (outside the budget engine); price it by hand or park it at its floor $%.2f.', COALESCE(w.bid_floor, 0)))
           END,
           IF(w.seat_no IS NULL, ' (Not yet numbered: the seat ledger runs after the snapshot.)', ''),
           IF(w.holdout AND run_day.d >= w.holdout_eligible_from, ' HOLDOUT — do not touch; excluded from every sheet.', '')
         ) AS sentence,
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
                FORMAT('seat %d (open) in %s — $%.2f/day of capacity. Next affordable probe: %s in %s, queue #%d, at the seat price $%.2f/click × %d clicks a day ≈ $%.2f/day.', fn.lowest_free_seat, UPPER(fr.family), fr.open_capacity_per_day, np.target_text, np.campaign_name, np.queue_pos, np.seat_cpc, k.click_goal_day, np.admission_cost_per_day) END AS sentence,
    FORMAT('%s|%02d|%05d||', fr.family, 4, fn.lowest_free_seat) AS sort_key
  FROM fam_rows fr CROSS JOIN k
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
    IF(w.holdout AND run_day.d >= w.holdout_eligible_from, 'no sheet row — holdout campaign',
            'pause it on the next book (leak arm); if its spend comes from search terms under a parked keyword, the negate is judged at the ad group') AS move,
    FORMAT('%s (%s) reads %s on the ladder yet spent $%.2f/day on the basis window at bid $%.2f. %s%s',
                w.target_text, w.campaign_name, IF(w.state = 'DEAD', 'dead', 'parked'), w.cost_today, COALESCE(w.current_bid, 0),
                IF(w.holdout AND run_day.d >= w.holdout_eligible_from, 'HOLDOUT — do not touch; no sheet row.',
                   'Pause it on the next book; if the spend is a search term under a parked keyword, negate it at the ad group (the acting grain).'),
                IF(w.holdout AND run_day.d < w.holdout_eligible_from, FORMAT(' Its campaign joins the holdout arm on %s.', CAST(w.holdout_eligible_from AS STRING)), '')) AS sentence,
    FORMAT('%s|%02d|%010.2f|%s|%s', w.family, 5, 99999 - w.cost_today, w.campaign_id, w.keyword_id) AS sort_key
  FROM kw w CROSS JOIN run_day
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
    'no sheet row — the verdict arrives on the next state run if the campaign is mapped; otherwise check why the ladder does not track this target' AS move,
    FORMAT('%s (%s) spent $%.2f/day on the basis window with no verdict row on the ladder — untracked spend counts on the 20%% side. If the campaign was mapped to %s recently, the verdict arrives on the next state run; otherwise check why the ladder does not track this target.%s',
                w.target_text, w.campaign_name, w.cost_today, w.family,
                IF(w.holdout AND run_day.d >= w.holdout_eligible_from, ' HOLDOUT — do not touch.', '')) AS sentence,
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
    CAST(NULL AS INT64) AS n_keywords,
    CAST(NULL AS STRING) AS horizon_assumption,
    'advisory only — budgets are shown, never moved by the register' AS move,
    FORMAT('could absorb freed spend: %s — above its family bar (7-day GP-ROAS %.2fx vs bar %.2fx), capped %d of the last 7 days ($%.2f spent on a $%.2f budget). Advisory only; the register moves no budget.',
                a.campaign_name, a.gp_roas_7d, a.keyword_bar, a.days_capped_7d, a.spend_7d, a.budget_7d) AS sentence,
    FORMAT('%s|%02d|%s||', a.family, 7, a.campaign_id) AS sort_key
  FROM absorb a
)
SELECT s.*, run_day.d AS as_of, win.basis_to AS ads_basis_to, win.basis_from AS ads_basis_from
FROM shape s CROSS JOIN run_day CROSS JOIN win;
