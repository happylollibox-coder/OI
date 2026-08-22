-- =============================================================================================
-- V_FAMILY_SEAT_REGISTER acceptance — every row must read PASS (spec §8 guarantees, rulings R-a…R-k).
-- Run after SP_MAINTAIN_FAMILY_SEATS on the latest FACT_KEYWORD_STATE snapshot:
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- The view is read ONCE into a temp table (a script, not a single query) so the checks do not
-- re-plan the register per correlated subquery.
-- TDD record: run BEFORE the view exists it cannot pass (the object is not found); after deploy
-- every check reads PASS. Determinism is asserted externally with the query at the bottom.
-- The declared constants the checks read live in the k CTE below and mirror the view's own k CTE
-- (Standing Rule 0: a check reads k, never a literal of its own).
--
-- Checks (the register's own rows against an independent re-derivation where one exists):
--   B01 Reconciliation: CATEGORY rows on the 'today' horizon sum to the FAMILY / REFERENCE row's
--       spend_basis_per_day to the cent, for every family; and to spend_horizon_per_day on the
--       other two horizons.
--   B02 Sides: on 'today', SEAT rows on the 20% side + LEAK + GAP rows sum to bad_side_per_day to
--       the cent (settling seats are counted on the 80% side by ruling and are excluded).
--   B03 Every keyword exactly once: the CATEGORY keyword counts of a working family on 'today'
--       equal the family's universe re-derived here (ladder rows ∪ keywords with spend > 0 on the
--       BASIS window — never the wider scan window — in campaigns T_FAMILY_BAR maps to the
--       family); and no keyword appears in two of SEAT / LEAK / GAP / NO_CLOCK.
--   B04 Seats are numbered: every SEAT row carries a seat_no; (family, seat_no) is unique among
--       SEAT rows; the number is the open ledger row's; every open ledger row has a SEAT row.
--   B05 No launch family is judged: zero FAMILY rows for INVEST families; REFERENCE rows carry
--       doctrine_status 'REFERENCE' and never IN / AT_LINE / OUT.
--   B06 Brand defense never gets a move: no SEAT / LEAK / GAP / NO_CLOCK row whose keyword is
--       defense by the ladder flag, by the campaign-name rule, or by a house brand phrase
--       (DIM_BRAND_PHRASES, phrase_type BRAND) matched as a WHOLE PHRASE on word boundaries —
--       never a bare substring (ruling D9: 'lolli' as a substring would claim 'lolli pop') —
--       tested on the ROW's own campaign_name and target_text, and on the ladder flag.
--   B07 Total ordering: sort_key is unique over all rows (the determinism precondition).
--   B08 Plain words: every row has a non-empty sentence; every SEAT / LEAK / GAP / NO_CLOCK /
--       OPEN_SEAT row has a move; no category reads 'other' in a working family.
--   B09 Holdout: every row that names a campaign (SEAT / LEAK / GAP / NO_CLOCK / ABSORB / UNMAPPED,
--       and OPEN_SEAT with a candidate) in a HOLDOUT campaign carries holdout TRUE, its
--       eligible_from and a note; no row outside one carries the marker; from eligible_from the
--       move of such a row reads 'no sheet row' / 'advisory suppressed' and no OPEN_SEAT candidate
--       sits in one.
--   B10 Stalled probes (R-b / R-c / R-f): every 'probe — stalled' SEAT row publishes raise_old_bid,
--       raise_new_bid, raised_on, clicks_since_raise, days_since_raise and a sentence that says
--       'entered at' or 'was nudged'; its due_on is NULL (no clock); its move branches on the SIGN
--       of (seat price − live bid): a live bid BELOW the seat price proposes 'raise to the seat
--       price $X'; a live bid AT OR ABOVE it proposes 'park it' at the engine's park price (it could
--       not buy a verdict even at the seat price); a campaign with no published seat price says so
--       and proposes the park price. A 'raise to' is never printed to a price at or below the live bid.
--   B11 Horizons: exactly three FAMILY rows per working family (today, day one, re-judged), each
--       with as_of, horizon_assumption and ads_basis_to; the re-judged horizon has no
--       'losing — in repair' category.
--   B12 R-d / R-e re-derived: the count of 'waiting — no test clock' keywords and of 'idle at the
--       floor' keywords per working family equals an independent re-derivation; idle rows cost $0;
--       every no-clock keyword has its own NO_CLOCK row (sentence + move, ruling R-d).
--   B13 One OPEN_SEAT row per working family whose seat_no is the lowest number not held by an
--       open ledger row, and whose candidate (if any) costs no more than the open capacity.
--   B14 ABSORB rows are campaigns capped on at least k.absorb_capped_days of the last 7 in
--       V_CAMPAIGN_CAP_STATE, not defense.
--   B15 Every FAMILY row's figures reconcile: allowance = k.allowance_share × judged; judged =
--       good + bad; open_capacity = allowance − bad; good_share = good ÷ judged; spend_basis =
--       judged + defense (+ launch, + $0 categories) — all to the cent.
--   B16 Spend in the cracks: the UNMAPPED campaign rows equal an independent re-derivation (every
--       campaign with spend > 0 on the basis window that has no T_FAMILY_BAR row and no ladder row
--       with a family), cost per day to the cent; the total row equals their sum and count.
--   B17 No phantom gap: every GAP row costs more than $0 on the basis window (the definition of
--       a gap is spend with no verdict row).
--   B18 Overdue settling (R-i): a settling SEAT row whose due_on is before as_of says 'was due to
--       settle on <date> — overdue by N days; the ladder has not re-judged it' in its sentence and
--       its move, with N = as_of − due_on; a settling row not yet due never says 'overdue'.
--   B19 Product targets (R-k): a GAP row whose target is a product target (asin= / category=)
--       says 'the verdict ladder does not track product targets' in its sentence and its move and
--       never promises a verdict 'on the next state run'; a keyword GAP row keeps the 'next state
--       run' sentence; the FAMILY 'what closes the gap' sentence says the same — it promises a
--       verdict only for the keyword gaps and names the product-target gaps as untracked until the
--       ladder tracks them.
--   B20 REFERENCE wording (D4): the launch-family sentence names the good side as 'winning, at its
--       bar or waiting for a verdict' (the side includes waiting).
--   B21 Projection counts (D5): on every FAMILY row the '<N> seats', '<N> leaks' and '<N> untracked'
--       in the sentence equal the keyword counts of that HORIZON's own CATEGORY rows (seat
--       categories on the 20% side; closed but still spending; untracked) — never today's counts
--       beside projected dollars.
--   B22 Probe queue defense (D6): no OPEN_SEAT candidate is defense by any of the three tests
--       (T_OOB_SEAT_ECONOMICS.is_defense, 'BRAND DEFENSE' in the campaign name, a whole-phrase
--       house brand match on the target text).
--   B23 Dates (D7): no sentence or move carries a space-padded day ('Aug  4'); every month-day in a
--       sentence is two-digit.
--   B24 One clock (D8): on every stalled SEAT row days_since_raise = as_of − raised_on (the same
--       clock the 14-day test ages against), and the sentence states both the age on the snapshot
--       date and the complete ads days the clicks were counted on.
--   B25 at_line_band per family (R-g): every working family's FAMILY row carries a band equal to an
--       independent re-derivation of ITS OWN daily-spend noise (stddev ÷ mean over the context
--       window ÷ √basis_days) and a derivation that names the family.
--   B26 Parked seats (R-h): the 'parked — awaiting re-verdict' SEAT rows per working family equal
--       the re-derivation (PARKED, not defense, spend on the basis window, next_check_date on or
--       after as_of), each on the 20% side with due_on = the appointment and the move 'no move —
--       re-judged on <date>'; LEAK rows equal the re-derivation (PARKED past its appointment with
--       spend, or DEAD with spend).
--   B27 Not yet serving (R-j): the 'waiting — not yet serving' keywords per working family equal
--       the re-derivation (TRIAL in no probe position, not idle at the floor, not no-clock, $0 and
--       0 clicks on the basis window), cost $0 on no side; every 'waiting — too few clicks yet'
--       keyword has clicks > 0 on the basis window (the category counts equal the re-derivation).
--   B28 Whole-phrase defense (D9): the 'brand defense' CATEGORY count per working family equals
--       the whole-phrase three-way re-derivation over the universe.
-- =============================================================================================
CREATE TEMP TABLE reg AS SELECT * FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER`;
WITH
k AS (SELECT 7 AS basis_days, 28 AS context_days, 14 AS probe_window_days, 20 AS verdict_clicks,
             0.005 AS bid_tol, 0.20 AS allowance_share, 4 AS absorb_capped_days),
r AS (SELECT * FROM reg),
run_day AS (SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
working AS (SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'),
launch AS (SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'INVEST'),
fam AS (SELECT campaign_id, family FROM `onyga-482313.OI.T_FAMILY_BAR`
        QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY family) = 1),
-- house brand phrases as whole-phrase, word-boundary regexes (D9): never a bare substring
brand AS (SELECT DISTINCT CONCAT(r'\b', REGEXP_REPLACE(TRIM(LOWER(phrase), ' |,'), r'([.*+?^${}()|\[\]\\])', r'\\\1'), r'\b') AS rx
          FROM `onyga-482313.OI.DIM_BRAND_PHRASES` WHERE phrase_type = 'BRAND' AND TRIM(LOWER(phrase), ' |,') != ''),
probes AS (SELECT DISTINCT CAST(keyword_id AS STRING) AS kid FROM `onyga-482313.OI.T_LIFT_PROBES`),
holdout AS (SELECT unit_id AS campaign_id, MIN(eligible_from) AS eligible_from
            FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` WHERE unit_type = 'CAMPAIGN' AND arm = 'HOLDOUT' GROUP BY 1),
lastchg AS (
  SELECT campaign_id, keyword_id, action, DATE(applied_at, 'America/Los_Angeles') AS chg_date, old_bid, new_bid
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE action IN ('INCREASE_BID', 'REDUCE_BID') AND new_bid IS NOT NULL AND keyword_id IS NOT NULL AND keyword_id != ''
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY applied_at DESC, change_id DESC) = 1),
bidv AS (SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid, COUNT(DISTINCT ROUND(bid, 2)) AS bid_versions
         FROM `onyga-482313.OI.DIM_KEYWORD` GROUP BY 1, 2),
sp AS (
  SELECT CAST(f.campaign_id AS STRING) AS cid, CAST(f.keyword_id AS STRING) AS kid,
         ARRAY_AGG(f.campaign_name ORDER BY f.date DESC, f.campaign_name LIMIT 1)[OFFSET(0)] AS ads_campaign_name,
         ARRAY_AGG(f.targeting ORDER BY f.date DESC, f.targeting LIMIT 1)[OFFSET(0)] AS targeting,
         SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL k.basis_days DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY), f.Ads_cost, 0)) AS spend7,
         SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL k.basis_days DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY), f.Ads_clicks, 0)) AS clicks7,
         SUM(IF(lc.chg_date IS NOT NULL AND f.date > lc.chg_date AND f.date < wm.d, f.Ads_clicks, 0)) AS clicks_since_raise
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f CROSS JOIN wm CROSS JOIN k
  LEFT JOIN lastchg lc ON lc.campaign_id = CAST(f.campaign_id AS STRING) AND lc.keyword_id = CAST(f.keyword_id AS STRING)
  WHERE f.date >= LEAST(DATE_SUB(wm.d, INTERVAL k.context_days DAY), COALESCE((SELECT MIN(chg_date) FROM lastchg), wm.d))
    AND f.keyword_id IS NOT NULL AND f.keyword_id != ''
  GROUP BY 1, 2),
-- the family's own daily-spend noise on the context window (R-g), re-derived
fam_day AS (
  SELECT fm.family, f.date, SUM(f.Ads_cost) AS sp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f CROSS JOIN wm CROSS JOIN k
  JOIN fam fm ON fm.campaign_id = CAST(f.campaign_id AS STRING)
  WHERE f.date BETWEEN DATE_SUB(wm.d, INTERVAL k.context_days DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY)
    AND f.keyword_id IS NOT NULL AND f.keyword_id != ''
  GROUP BY 1, 2),
fam_band AS (
  SELECT family, ROUND(SAFE_DIVIDE(STDDEV_SAMP(sp), NULLIF(AVG(sp), 0)) / SQRT(MAX(k.basis_days)), 3) AS band
  FROM fam_day CROSS JOIN k GROUP BY 1),
brand_hit AS (
  SELECT DISTINCT s.campaign_id, s.keyword_id FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
  JOIN brand b ON REGEXP_CONTAINS(LOWER(s.target_text), b.rx)),
snap AS (
  SELECT s.*, (COALESCE(s.is_brand_defense, FALSE) OR REGEXP_CONTAINS(UPPER(COALESCE(s.campaign_name, '')), r'BRAND DEFENSE') OR bh.keyword_id IS NOT NULL) AS is_defense
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s CROSS JOIN run_day
  LEFT JOIN brand_hit bh ON bh.campaign_id = s.campaign_id AND bh.keyword_id = s.keyword_id
  WHERE s.snapshot_date = run_day.d),
-- the universe the register must cover, re-derived
universe AS (
  SELECT COALESCE(s.campaign_id, sp.cid) AS campaign_id, COALESCE(s.keyword_id, sp.kid) AS keyword_id,
         COALESCE(s.family, f.family) AS family, s.state, s.next_check_date,
         (COALESCE(s.is_defense, FALSE)
          OR REGEXP_CONTAINS(UPPER(COALESCE(s.campaign_name, sp.ads_campaign_name, '')), r'BRAND DEFENSE')
          OR EXISTS (SELECT 1 FROM brand b WHERE REGEXP_CONTAINS(LOWER(COALESCE(s.target_text, sp.targeting, '')), b.rx))) AS is_defense,
         COALESCE(s.at_floor, FALSE) AS at_floor, s.current_bid, COALESCE(sp.spend7, 0) AS spend7, COALESCE(sp.clicks7, 0) AS clicks7,
         COALESCE(sp.clicks_since_raise, 0) AS clicks_since_raise,
         s.campaign_id IS NOT NULL AS on_ladder,
         REGEXP_CONTAINS(LOWER(COALESCE(s.target_text, sp.targeting, '')), r'^\s*(asin|category)\s*=') AS is_product_target
  FROM snap s FULL OUTER JOIN sp ON sp.cid = s.campaign_id AND sp.kid = s.keyword_id
  LEFT JOIN fam f ON f.campaign_id = COALESCE(s.campaign_id, sp.cid)
  -- an off-ladder keyword belongs to the universe only with spend on the BASIS window
  WHERE COALESCE(s.family, f.family) IS NOT NULL AND (s.campaign_id IS NOT NULL OR COALESCE(sp.spend7, 0) > 0)),
-- spend in the cracks, re-derived at campaign grain on the basis window (no keyword filter)
unmapped_rd AS (
  SELECT CAST(f.campaign_id AS STRING) AS campaign_id, SUM(f.Ads_cost) / MAX(k.basis_days) AS cost_per_day
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f CROSS JOIN wm CROSS JOIN k
  WHERE f.date BETWEEN DATE_SUB(wm.d, INTERVAL k.basis_days DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY)
  GROUP BY 1
  HAVING SUM(f.Ads_cost) > 0
     AND campaign_id NOT IN (SELECT campaign_id FROM fam)
     AND campaign_id NOT IN (SELECT DISTINCT campaign_id FROM snap WHERE family IS NOT NULL)),
wu AS (SELECT u.* FROM universe u JOIN working w ON w.family = u.family),
-- the TRIAL positions re-derived once (R-a … R-e, R-j), per keyword
pos AS (
  SELECT u.*,
         p.kid IS NOT NULL AS engine_probe,
         COALESCE(p.kid IS NULL AND NOT u.at_floor AND lc.action = 'INCREASE_BID'
                  AND u.current_bid >= lc.new_bid - k.bid_tol AND u.current_bid > lc.old_bid + k.bid_tol
                  AND lc.chg_date <= DATE_SUB(run_day.d, INTERVAL k.probe_window_days DAY)
                  AND u.clicks_since_raise < k.verdict_clicks, FALSE) AS stalled,
         (COALESCE(bv.bid_versions, 1) > 1
          AND (lc.campaign_id IS NULL OR (ABS(u.current_bid - lc.new_bid) > k.bid_tol AND NOT (lc.action = 'INCREASE_BID' AND u.current_bid > lc.new_bid)))) AS no_clock
  FROM wu u CROSS JOIN k CROSS JOIN run_day
  LEFT JOIN probes p ON p.kid = u.keyword_id
  LEFT JOIN lastchg lc ON lc.campaign_id = u.campaign_id AND lc.keyword_id = u.keyword_id
  LEFT JOIN bidv bv ON bv.cid = u.campaign_id AND bv.kid = u.keyword_id),
rd AS (
  SELECT family,
         COUNTIF(state = 'TRIAL' AND NOT is_defense AND NOT engine_probe AND NOT (at_floor AND spend7 > 0) AND NOT stalled
                 AND NOT (at_floor AND spend7 = 0 AND clicks7 = 0) AND no_clock) AS n_no_clock,
         COUNTIF(state = 'TRIAL' AND NOT is_defense AND NOT engine_probe AND at_floor AND spend7 = 0 AND clicks7 = 0) AS n_idle,
         COUNTIF(state = 'TRIAL' AND NOT is_defense AND NOT engine_probe AND NOT (at_floor AND spend7 > 0) AND NOT stalled
                 AND NOT (at_floor AND spend7 = 0 AND clicks7 = 0) AND NOT no_clock AND spend7 = 0 AND clicks7 = 0) AS n_not_serving,
         COUNTIF(state = 'TRIAL' AND NOT is_defense AND NOT engine_probe AND NOT (at_floor AND spend7 > 0) AND NOT stalled
                 AND NOT (at_floor AND spend7 = 0 AND clicks7 = 0) AND NOT no_clock AND NOT (spend7 = 0 AND clicks7 = 0)) AS n_waiting,
         COUNTIF(state = 'PARKED' AND NOT is_defense AND spend7 > 0 AND next_check_date >= (SELECT d FROM run_day)) AS n_parked_seat,
         COUNTIF(NOT is_defense AND spend7 > 0 AND (state = 'DEAD' OR (state = 'PARKED' AND NOT (next_check_date >= (SELECT d FROM run_day))))) AS n_leak,
         COUNTIF(is_defense) AS n_defense,
         COUNTIF(NOT is_defense AND NOT on_ladder AND is_product_target) AS n_gap_pt,
         COUNTIF(NOT is_defense AND NOT on_ladder AND NOT is_product_target) AS n_gap_kw
  FROM pos GROUP BY 1),
ledger_open AS (SELECT family, campaign_id, keyword_id, seat_no FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` WHERE closed_on IS NULL),
famrow AS (SELECT * FROM r WHERE row_type IN ('FAMILY', 'REFERENCE')),
cat AS (SELECT * FROM r WHERE row_type = 'CATEGORY'),
kwrows AS (SELECT * FROM r WHERE row_type IN ('SEAT', 'LEAK', 'GAP', 'NO_CLOCK')),
-- every row that names a campaign (the holdout marker's domain)
camprows AS (SELECT * FROM r WHERE campaign_id IS NOT NULL AND row_type IN ('SEAT', 'LEAK', 'GAP', 'NO_CLOCK', 'ABSORB', 'UNMAPPED', 'OPEN_SEAT')),
-- aggregates used by several checks (plain joins; BigQuery refuses correlated subqueries over tables)
cat_sum AS (SELECT family, horizon, SUM(cost_per_day) AS s, SUM(n_keywords) AS nk FROM cat GROUP BY 1, 2),
cat_named AS (SELECT family, horizon, category, SUM(n_keywords) AS nk, SUM(cost_per_day) AS s FROM cat GROUP BY 1, 2, 3),
-- the seat categories (an occupant on the 20% side) per horizon, from the CATEGORY rows themselves
seat_cats AS (SELECT 'losing — in repair' AS category UNION ALL SELECT 'losing — on probation at its floor' UNION ALL
              SELECT 'losing — failed at its floor' UNION ALL SELECT 'probe — being bought at an entry bid' UNION ALL
              SELECT 'probe — stalled' UNION ALL SELECT 'parked — awaiting re-verdict'),
hz_counts AS (
  SELECT c.family, c.horizon,
         SUM(IF(c.side = '20' AND sc.category IS NOT NULL, c.n_keywords, 0)) AS n_seats,
         SUM(IF(c.category = 'closed but still spending', c.n_keywords, 0)) AS n_leaks,
         SUM(IF(c.category = 'untracked — no verdict row', c.n_keywords, 0)) AS n_gaps
  FROM cat c LEFT JOIN seat_cats sc ON sc.category = c.category
  GROUP BY 1, 2),
bad20 AS (SELECT family, SUM(cost_per_day) AS s FROM kwrows WHERE side = '20' GROUP BY 1),
wu_cnt AS (SELECT family, COUNT(*) AS n FROM wu GROUP BY 1),
lowest AS (
  SELECT w.family, MIN(n) AS lowest_free_seat
  FROM working w CROSS JOIN UNNEST(GENERATE_ARRAY(1, 1 + (SELECT COALESCE(MAX(seat_no), 0) FROM ledger_open))) AS n
  LEFT JOIN ledger_open l ON l.family = w.family AND l.seat_no = n
  WHERE l.seat_no IS NULL GROUP BY 1),
checks AS (
  SELECT 'B01 CATEGORY rows sum to the family spend on every horizon, to the cent' AS check_name,
         (SELECT COUNT(*) FROM famrow f LEFT JOIN cat_sum c ON c.family = f.family AND c.horizon = f.horizon
          WHERE c.s IS NULL OR ABS(c.s - f.spend_horizon_per_day) > 0.01
             OR (f.horizon = 'today' AND ABS(f.spend_horizon_per_day - f.spend_basis_per_day) > 0.0001)) AS violations
  UNION ALL
  SELECT 'B02 SEAT(20% side) + LEAK + GAP costs equal bad_side_per_day today, to the cent',
         (SELECT COUNT(*) FROM famrow f JOIN working w ON w.family = f.family LEFT JOIN bad20 b ON b.family = f.family
          WHERE f.horizon = 'today' AND ABS(COALESCE(b.s, 0) - f.bad_side_per_day) > 0.01)
  UNION ALL
  SELECT 'B03 every keyword of a working family counted exactly once (CATEGORY counts = re-derived universe; no keyword in two of SEAT/LEAK/GAP)',
         (SELECT COUNT(*) FROM working w LEFT JOIN cat_sum c ON c.family = w.family AND c.horizon = 'today' LEFT JOIN wu_cnt u ON u.family = w.family
          WHERE COALESCE(c.nk, 0) IS DISTINCT FROM COALESCE(u.n, 0))
         + (SELECT COUNT(*) FROM (SELECT campaign_id, keyword_id FROM kwrows GROUP BY 1, 2 HAVING COUNT(*) > 1))
  UNION ALL
  SELECT 'B04 every SEAT row numbered by its open ledger row, numbers unique per family, every open ledger row has a SEAT row',
         (SELECT COUNT(*) FROM r WHERE row_type = 'SEAT' AND seat_no IS NULL)
         + (SELECT COUNT(*) FROM (SELECT family, seat_no FROM r WHERE row_type = 'SEAT' GROUP BY 1, 2 HAVING COUNT(*) > 1))
         + (SELECT COUNT(*) FROM r s LEFT JOIN ledger_open l ON l.family = s.family AND l.campaign_id = s.campaign_id AND l.keyword_id = s.keyword_id
            WHERE s.row_type = 'SEAT' AND (l.seat_no IS NULL OR l.seat_no != s.seat_no))
         + (SELECT COUNT(*) FROM ledger_open l LEFT JOIN r s ON s.row_type = 'SEAT' AND s.family = l.family AND s.campaign_id = l.campaign_id AND s.keyword_id = l.keyword_id
            WHERE s.keyword_id IS NULL)
  UNION ALL
  SELECT 'B05 no launch family in a FAMILY row; REFERENCE rows are never judged',
         (SELECT COUNT(*) FROM r JOIN launch l ON l.family = r.family WHERE r.row_type = 'FAMILY')
         + (SELECT COUNT(*) FROM r WHERE row_type = 'REFERENCE' AND doctrine_status != 'REFERENCE')
         + (SELECT COUNT(*) FROM r JOIN launch l ON l.family = r.family WHERE r.row_type IN ('SEAT', 'LEAK', 'GAP', 'OPEN_SEAT', 'ABSORB'))
  UNION ALL
  SELECT 'B06 no brand-defense keyword holds a SEAT / LEAK / GAP / NO_CLOCK row (ladder flag, campaign name, or a WHOLE-PHRASE house brand match — tested on the row itself)',
         (SELECT COUNT(*) FROM kwrows x LEFT JOIN snap s ON s.campaign_id = x.campaign_id AND s.keyword_id = x.keyword_id
          WHERE COALESCE(s.is_brand_defense, FALSE)
             OR REGEXP_CONTAINS(UPPER(COALESCE(x.campaign_name, '')), r'BRAND DEFENSE')
             OR EXISTS (SELECT 1 FROM brand b WHERE REGEXP_CONTAINS(LOWER(COALESCE(x.target_text, '')), b.rx)))
  UNION ALL
  SELECT 'B07 sort_key is unique over all rows (total ordering)',
         (SELECT COUNT(*) FROM (SELECT sort_key FROM r GROUP BY 1 HAVING COUNT(*) > 1))
         + (SELECT COUNT(*) FROM r WHERE sort_key IS NULL)
  UNION ALL
  SELECT 'B08 every row has a sentence; SEAT / LEAK / GAP / NO_CLOCK / OPEN_SEAT rows have a move; no "other" category in a working family',
         (SELECT COUNT(*) FROM r WHERE sentence IS NULL OR LENGTH(sentence) < 20)
         + (SELECT COUNT(*) FROM r WHERE row_type IN ('SEAT', 'LEAK', 'GAP', 'NO_CLOCK', 'OPEN_SEAT') AND (move IS NULL OR move = ''))
         + (SELECT COUNT(*) FROM cat c JOIN working w ON w.family = c.family WHERE c.category LIKE 'other%')
  UNION ALL
  SELECT 'B09 holdout marked on every row that names a holdout campaign (SEAT / LEAK / GAP / NO_CLOCK / ABSORB / UNMAPPED / OPEN_SEAT candidate), only there; from eligible_from the move is suppressed and no candidate sits in one',
         (SELECT COUNT(*) FROM camprows x LEFT JOIN holdout h ON h.campaign_id = x.campaign_id
          WHERE (h.campaign_id IS NOT NULL AND (NOT COALESCE(x.holdout, FALSE) OR x.holdout_eligible_from IS DISTINCT FROM h.eligible_from OR x.holdout_note IS NULL))
             OR (h.campaign_id IS NULL AND (COALESCE(x.holdout, FALSE) OR x.holdout_note IS NOT NULL)))
         + (SELECT COUNT(*) FROM r x WHERE x.holdout IS NULL AND x.campaign_id IS NULL AND (x.holdout_note IS NOT NULL OR x.holdout_eligible_from IS NOT NULL))
         + (SELECT COUNT(*) FROM camprows x JOIN holdout h ON h.campaign_id = x.campaign_id CROSS JOIN run_day
            WHERE run_day.d >= h.eligible_from
              AND (x.row_type = 'OPEN_SEAT'
                   OR NOT (x.move LIKE 'no sheet row%' OR x.move LIKE 'advisory suppressed%' OR x.row_type = 'UNMAPPED')
                   OR x.sentence NOT LIKE '%HOLDOUT%'))
  UNION ALL
  SELECT 'B10 stalled-probe SEAT rows publish the raise (old, new, date, clicks, days), a size-aware sentence, no due date, and a proposal that branches on the sign: raise only to a price ABOVE the live bid, otherwise park at the engine park price (R-f)',
         (SELECT COUNT(*) FROM r CROSS JOIN k WHERE row_type = 'SEAT' AND occupant_kind = 'stalled probe'
            AND (raise_old_bid IS NULL OR raise_new_bid IS NULL OR raised_on IS NULL OR clicks_since_raise IS NULL OR days_since_raise IS NULL
                 OR NOT (sentence LIKE '%entered at $%' OR sentence LIKE '%was nudged $%')
                 OR due_on IS NOT NULL
                 OR NOT CASE
                      WHEN seat_price IS NULL THEN move LIKE '%no seat price is published%' AND move LIKE '%park price $%'
                      WHEN current_bid < seat_price - k.bid_tol THEN move LIKE 'raise to the seat price $%'
                      ELSE move LIKE 'park it%' AND move LIKE '%park price $%' END
                 OR (move LIKE 'raise to the seat price $%' AND seat_price <= current_bid + k.bid_tol)))
         + (SELECT COUNT(*) FROM r WHERE row_type = 'SEAT' AND occupant_kind != 'stalled probe' AND raise_new_bid IS NOT NULL)
  UNION ALL
  SELECT 'B11 three horizons per working family with as_of, horizon_assumption and basis dates; re-judged has no repair category',
         (SELECT COUNT(*) FROM working w LEFT JOIN
            (SELECT family, COUNT(DISTINCT horizon) AS nh FROM famrow
             WHERE row_type = 'FAMILY' AND as_of IS NOT NULL AND horizon_assumption IS NOT NULL AND ads_basis_to IS NOT NULL GROUP BY 1) h
            ON h.family = w.family WHERE COALESCE(h.nh, 0) != 3)
         + (SELECT COUNT(*) FROM cat WHERE horizon = 're-judged' AND category = 'losing — in repair')
  UNION ALL
  SELECT 'B12 R-d / R-e: "waiting — no test clock" and "idle at the floor" counts match the re-derivation; idle costs $0',
         (SELECT COUNT(*) FROM rd
          LEFT JOIN cat_named nc ON nc.family = rd.family AND nc.horizon = 'today' AND nc.category = 'waiting — no test clock'
          LEFT JOIN cat_named ic ON ic.family = rd.family AND ic.horizon = 'today' AND ic.category = 'idle at the floor'
          WHERE rd.n_no_clock IS DISTINCT FROM COALESCE(nc.nk, 0) OR rd.n_idle IS DISTINCT FROM COALESCE(ic.nk, 0))
         + (SELECT COUNT(*) FROM cat WHERE category = 'idle at the floor' AND cost_per_day != 0)
         + (SELECT COUNT(*) FROM rd LEFT JOIN (SELECT family, COUNT(*) AS n FROM r WHERE row_type = 'NO_CLOCK' GROUP BY 1) x ON x.family = rd.family
            WHERE rd.n_no_clock IS DISTINCT FROM COALESCE(x.n, 0))
  UNION ALL
  SELECT 'B13 one OPEN_SEAT row per working family at the lowest free number; its candidate fits the capacity',
         (SELECT COUNT(*) FROM working w LEFT JOIN (SELECT family, COUNT(*) AS n FROM r WHERE row_type = 'OPEN_SEAT' GROUP BY 1) o ON o.family = w.family
          WHERE COALESCE(o.n, 0) != 1)
         + (SELECT COUNT(*) FROM r o JOIN lowest lo ON lo.family = o.family WHERE o.row_type = 'OPEN_SEAT' AND o.seat_no != lo.lowest_free_seat)
         + (SELECT COUNT(*) FROM r WHERE row_type = 'OPEN_SEAT' AND keyword_id IS NOT NULL AND cost_per_day > open_capacity_per_day + 0.0001)
  UNION ALL
  SELECT 'B14 ABSORB rows are non-defense campaigns capped on at least k.absorb_capped_days of the last 7',
         (SELECT COUNT(*) FROM r a CROSS JOIN k LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_CAP_STATE` cs ON cs.campaign_id = a.campaign_id
          WHERE a.row_type = 'ABSORB' AND (cs.campaign_id IS NULL OR cs.days_capped_7d < k.absorb_capped_days OR cs.is_defense))
  UNION ALL
  SELECT 'B15 FAMILY figures reconcile (allowance = k.allowance_share × judged, judged, capacity, share, basis), to the cent',
         (SELECT COUNT(*) FROM famrow f CROSS JOIN k LEFT JOIN cat_sum c ON c.family = f.family AND c.horizon = f.horizon
          WHERE ABS(f.allowance_per_day - k.allowance_share * f.judged_per_day) > 0.01
             OR ABS(f.judged_per_day - (f.good_side_per_day + f.bad_side_per_day)) > 0.01
             OR ABS(f.open_capacity_per_day - (f.allowance_per_day - f.bad_side_per_day)) > 0.01
             OR (f.judged_per_day > 0 AND ABS(f.good_share - f.good_side_per_day / f.judged_per_day) > 0.001)
             OR c.s IS NULL OR ABS(f.spend_horizon_per_day - c.s) > 0.01)
  UNION ALL
  SELECT 'B16 UNMAPPED rows equal the re-derived spend in the cracks (campaign set, cost to the cent); the total row equals their sum and count',
         (SELECT COUNT(*) FROM unmapped_rd u FULL OUTER JOIN (SELECT * FROM r WHERE row_type = 'UNMAPPED' AND campaign_id IS NOT NULL) x ON x.campaign_id = u.campaign_id
          WHERE u.campaign_id IS NULL OR x.campaign_id IS NULL OR ABS(u.cost_per_day - x.cost_per_day) > 0.01)
         + (SELECT COUNT(*) FROM (SELECT COUNT(*) AS n, SUM(cost_per_day) AS s FROM r WHERE row_type = 'UNMAPPED' AND campaign_id IS NOT NULL) d
            CROSS JOIN (SELECT COUNT(*) AS nt, MAX(n_keywords) AS nk, MAX(cost_per_day) AS st FROM r WHERE row_type = 'UNMAPPED' AND campaign_id IS NULL) t
            WHERE (d.n > 0 AND (t.nt != 1 OR t.nk != d.n OR ABS(t.st - d.s) > 0.01)) OR (d.n = 0 AND t.nt != 0))
  UNION ALL
  SELECT 'B17 no phantom gap: every GAP row spent more than $0 on the basis window',
         (SELECT COUNT(*) FROM r WHERE row_type = 'GAP' AND NOT (cost_per_day > 0))
  UNION ALL
  SELECT 'B18 overdue settling (R-i): a settling seat past its due date says so (due date, days overdue, not re-judged) in sentence and move; one not yet due never says overdue',
         (SELECT COUNT(*) FROM r WHERE row_type = 'SEAT' AND occupant_kind = 'settling'
            AND ((due_on < as_of AND NOT (sentence LIKE CONCAT('%was due to settle on ', FORMAT_DATE('%b %d', due_on), ' — overdue by ', CAST(DATE_DIFF(as_of, due_on, DAY) AS STRING), ' day%')
                                          AND sentence LIKE '%the ladder has not re-judged it%'
                                          AND move LIKE '%was due to settle on%' AND move LIKE '%overdue by%'))
                 OR (due_on >= as_of AND (sentence LIKE '%overdue%' OR move LIKE '%overdue%'))
                 OR due_on IS NULL))
  UNION ALL
  SELECT 'B19 product targets (R-k): a product-target GAP says the ladder does not track product targets and promises no verdict; a keyword GAP keeps the next-state-run sentence; the FAMILY sentence says the same',
         (SELECT COUNT(*) FROM r WHERE row_type = 'GAP'
            AND IF(REGEXP_CONTAINS(LOWER(COALESCE(target_text, '')), r'^\s*(asin|category)\s*='),
                   NOT (sentence LIKE '%the verdict ladder does not track product targets%' AND move LIKE '%the verdict ladder does not track product targets%')
                     OR sentence LIKE '%next state run%' OR move LIKE '%next state run%',
                   NOT (sentence LIKE '%next state run%' AND move LIKE '%next state run%')))
         + (SELECT COUNT(*) FROM famrow f JOIN rd ON rd.family = f.family
            WHERE f.row_type = 'FAMILY' AND f.horizon = 'today' AND f.doctrine_status != 'IN'
              AND ((rd.n_gap_pt > 0 AND NOT (f.sentence LIKE CONCAT('%', CAST(rd.n_gap_pt AS STRING), ' untracked product target%') AND f.sentence LIKE '%the verdict ladder does not track product targets%'))
                   OR (rd.n_gap_kw > 0 AND NOT f.sentence LIKE CONCAT('%', CAST(rd.n_gap_kw AS STRING), ' untracked keyword%next state run%'))
                   OR (rd.n_gap_kw = 0 AND f.sentence LIKE '%next state run%')))
  UNION ALL
  SELECT 'B20 REFERENCE wording (D4): the launch-family sentence names the good side as winning, at its bar or waiting for a verdict',
         (SELECT COUNT(*) FROM r WHERE row_type = 'REFERENCE' AND sentence NOT LIKE '%winning, at its bar or waiting for a verdict%')
  UNION ALL
  SELECT 'B21 projection counts (D5): the seat / leak / untracked counts in every FAMILY sentence equal that horizon’s own CATEGORY keyword counts',
         (SELECT COUNT(*) FROM famrow f LEFT JOIN hz_counts h ON h.family = f.family AND h.horizon = f.horizon
          WHERE f.row_type = 'FAMILY' AND f.good_share IS NOT NULL
            AND (SAFE_CAST(REGEXP_EXTRACT(f.sentence, r'(\d+) seats') AS INT64) IS DISTINCT FROM COALESCE(h.n_seats, 0)
                 OR SAFE_CAST(REGEXP_EXTRACT(f.sentence, r'(\d+) leaks') AS INT64) IS DISTINCT FROM COALESCE(h.n_leaks, 0)
                 OR SAFE_CAST(REGEXP_EXTRACT(f.sentence, r'(\d+) untracked') AS INT64) IS DISTINCT FROM COALESCE(h.n_gaps, 0)))
  UNION ALL
  SELECT 'B22 probe queue defense (D6): no OPEN_SEAT candidate is defense by the engine flag, the campaign name, or a whole-phrase house brand match',
         (SELECT COUNT(*) FROM r x LEFT JOIN `onyga-482313.OI.T_OOB_SEAT_ECONOMICS` o ON o.campaign_id = x.campaign_id AND o.keyword_id = x.keyword_id
          WHERE x.row_type = 'OPEN_SEAT' AND x.keyword_id IS NOT NULL
            AND (COALESCE(o.is_defense, FALSE)
                 OR REGEXP_CONTAINS(UPPER(COALESCE(x.campaign_name, '')), r'BRAND DEFENSE')
                 OR EXISTS (SELECT 1 FROM brand b WHERE REGEXP_CONTAINS(LOWER(COALESCE(x.target_text, '')), b.rx))))
  UNION ALL
  SELECT 'B23 dates (D7): no sentence or move carries a space-padded day; every month-day reads two digits',
         (SELECT COUNT(*) FROM r WHERE REGEXP_CONTAINS(COALESCE(sentence, ''), r'[A-Z][a-z]{2}  \d') OR REGEXP_CONTAINS(COALESCE(move, ''), r'[A-Z][a-z]{2}  \d')
             OR REGEXP_CONTAINS(COALESCE(sentence, ''), r'[A-Z][a-z]{2} \d(\D|$)') OR REGEXP_CONTAINS(COALESCE(move, ''), r'[A-Z][a-z]{2} \d(\D|$)'))
  UNION ALL
  SELECT 'B24 one clock (D8): on every stalled seat days_since_raise = as_of − raised_on and the sentence states the age on the snapshot date and the complete ads days counted',
         (SELECT COUNT(*) FROM r WHERE row_type = 'SEAT' AND occupant_kind = 'stalled probe'
            AND (days_since_raise IS DISTINCT FROM DATE_DIFF(as_of, raised_on, DAY)
                 OR sentence NOT LIKE CONCAT('%', CAST(DATE_DIFF(ads_basis_to, raised_on, DAY) AS STRING), ' complete ads days%')
                 OR sentence NOT LIKE CONCAT('%', CAST(DATE_DIFF(as_of, raised_on, DAY) AS STRING), ' days old on the snapshot date%')))
  UNION ALL
  SELECT 'B25 at_line_band per family (R-g): every working family’s FAMILY row carries ITS OWN re-derived daily-spend noise and a derivation naming the family',
         (SELECT COUNT(*) FROM famrow f JOIN working w ON w.family = f.family LEFT JOIN fam_band b ON b.family = f.family
          WHERE f.row_type = 'FAMILY'
            AND (f.at_line_band IS NULL OR b.band IS NULL OR ABS(f.at_line_band - b.band) > 0.0011
                 OR f.at_line_band_derivation NOT LIKE CONCAT('%', f.family, '%')))
  UNION ALL
  SELECT 'B26 parked seats (R-h): parked-awaiting-re-verdict SEAT rows and LEAK rows equal the re-derivation; each parked seat is on the 20% side, due on its appointment, with the no-move sentence',
         (SELECT COUNT(*) FROM rd
          LEFT JOIN (SELECT family, COUNT(*) AS n FROM r WHERE row_type = 'SEAT' AND occupant_kind = 'parked — awaiting re-verdict' GROUP BY 1) p ON p.family = rd.family
          LEFT JOIN (SELECT family, COUNT(*) AS n FROM r WHERE row_type = 'LEAK' GROUP BY 1) l ON l.family = rd.family
          WHERE rd.n_parked_seat IS DISTINCT FROM COALESCE(p.n, 0) OR rd.n_leak IS DISTINCT FROM COALESCE(l.n, 0))
         + (SELECT COUNT(*) FROM r x JOIN snap s ON s.campaign_id = x.campaign_id AND s.keyword_id = x.keyword_id
            WHERE x.row_type = 'SEAT' AND x.occupant_kind = 'parked — awaiting re-verdict'
              AND (x.side != '20' OR x.category != 'parked — awaiting re-verdict' OR x.due_on IS DISTINCT FROM s.next_check_date
                   OR x.due_on < x.as_of OR NOT (x.cost_per_day > 0)
                   OR NOT (x.move LIKE CONCAT('no move — re-judged on ', CAST(x.due_on AS STRING), '%') OR x.move LIKE 'no sheet row%')))
  UNION ALL
  SELECT 'B27 not yet serving (R-j): the waiting — not yet serving count equals the re-derivation at $0 on no side, and every waiting — too few clicks yet keyword has clicks on the basis window',
         (SELECT COUNT(*) FROM rd
          LEFT JOIN cat_named ns ON ns.family = rd.family AND ns.horizon = 'today' AND ns.category = 'waiting — not yet serving'
          LEFT JOIN cat_named wt ON wt.family = rd.family AND wt.horizon = 'today' AND wt.category = 'waiting — too few clicks yet'
          WHERE rd.n_not_serving IS DISTINCT FROM COALESCE(ns.nk, 0) OR rd.n_waiting IS DISTINCT FROM COALESCE(wt.nk, 0))
         + (SELECT COUNT(*) FROM cat WHERE category = 'waiting — not yet serving' AND (cost_per_day != 0 OR side != 'NONE'))
  UNION ALL
  SELECT 'B28 whole-phrase defense (D9): the brand-defense CATEGORY count per working family equals the whole-phrase three-way re-derivation',
         (SELECT COUNT(*) FROM rd LEFT JOIN cat_named d ON d.family = rd.family AND d.horizon = 'today' AND d.category = 'brand defense — never judged on profit'
          WHERE rd.n_defense IS DISTINCT FROM COALESCE(d.nk, 0))
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks ORDER BY check_name;

-- Determinism (spec §8): run twice, uncached; the two fingerprints must be identical.
--   SELECT COUNT(*) AS n, TO_HEX(MD5(STRING_AGG(TO_JSON_STRING(t), '|' ORDER BY sort_key)))
--   FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER` t;
