-- =============================================================================================
-- V_FAMILY_SEAT_REGISTER acceptance — every row must read PASS (spec §8 guarantees, rulings R-a…R-e).
-- Run after SP_MAINTAIN_FAMILY_SEATS on the latest FACT_KEYWORD_STATE snapshot:
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- The view is read ONCE into a temp table (a script, not a single query) so the fifteen checks
-- do not re-plan the register per correlated subquery.
-- TDD record: run BEFORE the view exists it cannot pass (the object is not found); after deploy
-- every check reads PASS. Determinism is asserted externally with the query at the bottom.
--
-- Checks (the register's own rows against an independent re-derivation where one exists):
--   B01 Reconciliation: CATEGORY rows on the 'today' horizon sum to the FAMILY / REFERENCE row's
--       spend_basis_per_day to the cent, for every family; and to spend_horizon_per_day on the
--       other two horizons.
--   B02 Sides: on 'today', SEAT rows on the 20% side + LEAK + GAP rows sum to bad_side_per_day to
--       the cent (settling seats are counted on the 80% side by ruling and are excluded).
--   B03 Every keyword exactly once: the CATEGORY keyword counts of a working family on 'today'
--       equal the family's universe re-derived here (ladder rows ∪ keywords with spend in the
--       basis window, in campaigns T_FAMILY_BAR maps to the family); and no keyword appears in
--       two of SEAT / LEAK / GAP / NO_CLOCK.
--   B04 Seats are numbered: every SEAT row carries a seat_no; (family, seat_no) is unique among
--       SEAT rows; the number is the open ledger row's; every open ledger row has a SEAT row.
--   B05 No launch family is judged: zero FAMILY rows for INVEST families; REFERENCE rows carry
--       doctrine_status 'REFERENCE' and never IN / AT_LINE / OUT.
--   B06 Brand defense never gets a move: no SEAT / LEAK / GAP row whose keyword is defense by the
--       ladder flag, by the campaign-name rule, or by the house brand phrases (DIM_BRAND_PHRASES).
--   B07 Total ordering: sort_key is unique over all rows (the determinism precondition).
--   B08 Plain words: every row has a non-empty sentence; every SEAT / LEAK / GAP / NO_CLOCK /
--       OPEN_SEAT row has a move; no category reads 'other' in a working family.
--   B09 Holdout: every SEAT / LEAK / GAP row in a HOLDOUT campaign carries holdout TRUE, its
--       eligible_from and a note; no row outside one carries the marker.
--   B10 Stalled probes (R-b / R-c): every 'probe — stalled' SEAT row publishes raise_old_bid,
--       raise_new_bid, raised_on, clicks_since_raise, days_since_raise and a sentence that says
--       'entered at' or 'was nudged'; its due_on is NULL (no clock); its move names the seat
--       price or says none is published.
--   B11 Horizons: exactly three FAMILY rows per working family (today, day one, re-judged), each
--       with as_of, horizon_assumption and ads_basis_to; the re-judged horizon has no
--       'losing — in repair' category.
--   B12 R-d / R-e re-derived: the count of 'waiting — no test clock' keywords and of 'idle at the
--       floor' keywords per working family equals an independent re-derivation; idle rows cost $0;
--       every no-clock keyword has its own NO_CLOCK row (sentence + move, ruling R-d).
--   B13 One OPEN_SEAT row per working family whose seat_no is the lowest number not held by an
--       open ledger row, and whose candidate (if any) costs no more than the open capacity.
--   B14 ABSORB rows are campaigns capped >= 4 of 7 days in V_CAMPAIGN_CAP_STATE, not defense.
--   B15 Every FAMILY row's figures reconcile: allowance = 0.20 × judged; judged = good + bad;
--       open_capacity = allowance − bad; good_share = good ÷ judged; spend_basis = judged +
--       defense (+ launch, + $0 categories) — all to the cent.
-- =============================================================================================
CREATE TEMP TABLE reg AS SELECT * FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER`;
WITH
k AS (SELECT 7 AS basis_days, 14 AS probe_window_days, 20 AS verdict_clicks, 0.005 AS bid_tol),
r AS (SELECT * FROM reg),
run_day AS (SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
working AS (SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'),
launch AS (SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'INVEST'),
fam AS (SELECT campaign_id, family FROM `onyga-482313.OI.T_FAMILY_BAR`
        QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY family) = 1),
brand AS (SELECT DISTINCT LOWER(phrase) AS phrase FROM `onyga-482313.OI.DIM_BRAND_PHRASES` WHERE phrase_type = 'BRAND'),
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
         SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL k.basis_days DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY), f.Ads_cost, 0)) AS spend7,
         SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL k.basis_days DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY), f.Ads_clicks, 0)) AS clicks7,
         SUM(IF(lc.chg_date IS NOT NULL AND f.date > lc.chg_date AND f.date < wm.d, f.Ads_clicks, 0)) AS clicks_since_raise
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f CROSS JOIN wm CROSS JOIN k
  LEFT JOIN lastchg lc ON lc.campaign_id = CAST(f.campaign_id AS STRING) AND lc.keyword_id = CAST(f.keyword_id AS STRING)
  WHERE f.date >= LEAST(DATE_SUB(wm.d, INTERVAL 28 DAY), COALESCE((SELECT MIN(chg_date) FROM lastchg), wm.d))
    AND f.keyword_id IS NOT NULL AND f.keyword_id != ''
  GROUP BY 1, 2),
brand_hit AS (
  SELECT DISTINCT s.campaign_id, s.keyword_id FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
  JOIN brand b ON LOWER(s.target_text) LIKE CONCAT('%', b.phrase, '%')),
snap AS (
  SELECT s.*, (COALESCE(s.is_brand_defense, FALSE) OR REGEXP_CONTAINS(UPPER(COALESCE(s.campaign_name, '')), r'BRAND DEFENSE') OR bh.keyword_id IS NOT NULL) AS is_defense
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s CROSS JOIN run_day
  LEFT JOIN brand_hit bh ON bh.campaign_id = s.campaign_id AND bh.keyword_id = s.keyword_id
  WHERE s.snapshot_date = run_day.d),
-- the universe the register must cover, re-derived
universe AS (
  SELECT COALESCE(s.campaign_id, sp.cid) AS campaign_id, COALESCE(s.keyword_id, sp.kid) AS keyword_id,
         COALESCE(s.family, f.family) AS family, s.state, COALESCE(s.is_defense, FALSE) AS is_defense,
         COALESCE(s.at_floor, FALSE) AS at_floor, s.current_bid, COALESCE(sp.spend7, 0) AS spend7, COALESCE(sp.clicks7, 0) AS clicks7,
         COALESCE(sp.clicks_since_raise, 0) AS clicks_since_raise
  FROM snap s FULL OUTER JOIN sp ON sp.cid = s.campaign_id AND sp.kid = s.keyword_id
  LEFT JOIN fam f ON f.campaign_id = COALESCE(s.campaign_id, sp.cid)
  WHERE COALESCE(s.family, f.family) IS NOT NULL),
wu AS (SELECT u.* FROM universe u JOIN working w ON w.family = u.family),
-- R-d / R-e re-derived
rd AS (
  SELECT u.family,
         COUNTIF(u.state = 'TRIAL' AND NOT u.is_defense AND p.kid IS NULL AND NOT (u.at_floor AND u.spend7 > 0)
                 -- stalled is NULL when there is no log row: COALESCE, or NOT NULL swallows the keyword
                 AND NOT COALESCE(p.kid IS NULL AND NOT u.at_floor AND lc.action = 'INCREASE_BID'
                          AND u.current_bid >= lc.new_bid - k.bid_tol AND u.current_bid > lc.old_bid + k.bid_tol
                          AND lc.chg_date <= DATE_SUB(run_day.d, INTERVAL k.probe_window_days DAY)
                          AND u.clicks_since_raise < k.verdict_clicks, FALSE)
                 AND NOT (u.at_floor AND u.spend7 = 0 AND u.clicks7 = 0)
                 AND COALESCE(bv.bid_versions, 1) > 1
                 AND (lc.campaign_id IS NULL OR (ABS(u.current_bid - lc.new_bid) > k.bid_tol AND NOT (lc.action = 'INCREASE_BID' AND u.current_bid > lc.new_bid)))) AS n_no_clock,
         COUNTIF(u.state = 'TRIAL' AND NOT u.is_defense AND p.kid IS NULL AND u.at_floor AND u.spend7 = 0 AND u.clicks7 = 0) AS n_idle
  FROM wu u CROSS JOIN k CROSS JOIN run_day
  LEFT JOIN probes p ON p.kid = u.keyword_id
  LEFT JOIN lastchg lc ON lc.campaign_id = u.campaign_id AND lc.keyword_id = u.keyword_id
  LEFT JOIN bidv bv ON bv.cid = u.campaign_id AND bv.kid = u.keyword_id
  GROUP BY 1),
ledger_open AS (SELECT family, campaign_id, keyword_id, seat_no FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` WHERE closed_on IS NULL),
famrow AS (SELECT * FROM r WHERE row_type IN ('FAMILY', 'REFERENCE')),
cat AS (SELECT * FROM r WHERE row_type = 'CATEGORY'),
kwrows AS (SELECT * FROM r WHERE row_type IN ('SEAT', 'LEAK', 'GAP', 'NO_CLOCK')),
-- aggregates used by several checks (plain joins; BigQuery refuses correlated subqueries over tables)
cat_sum AS (SELECT family, horizon, SUM(cost_per_day) AS s, SUM(n_keywords) AS nk FROM cat GROUP BY 1, 2),
cat_named AS (SELECT family, horizon, category, SUM(n_keywords) AS nk, SUM(cost_per_day) AS s FROM cat GROUP BY 1, 2, 3),
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
  SELECT 'B06 no brand-defense keyword holds a SEAT / LEAK / GAP row (ladder flag, campaign name, or house brand phrase)',
         (SELECT COUNT(*) FROM kwrows x JOIN universe u ON u.campaign_id = x.campaign_id AND u.keyword_id = x.keyword_id WHERE u.is_defense)
  UNION ALL
  SELECT 'B07 sort_key is unique over all rows (total ordering)',
         (SELECT COUNT(*) FROM (SELECT sort_key FROM r GROUP BY 1 HAVING COUNT(*) > 1))
         + (SELECT COUNT(*) FROM r WHERE sort_key IS NULL)
  UNION ALL
  SELECT 'B08 every row has a sentence; SEAT / LEAK / GAP / OPEN_SEAT rows have a move; no "other" category in a working family',
         (SELECT COUNT(*) FROM r WHERE sentence IS NULL OR LENGTH(sentence) < 20)
         + (SELECT COUNT(*) FROM r WHERE row_type IN ('SEAT', 'LEAK', 'GAP', 'NO_CLOCK', 'OPEN_SEAT') AND (move IS NULL OR move = ''))
         + (SELECT COUNT(*) FROM cat c JOIN working w ON w.family = c.family WHERE c.category LIKE 'other%')
  UNION ALL
  SELECT 'B09 holdout marked on every SEAT / LEAK / GAP row of a holdout campaign, and only there',
         (SELECT COUNT(*) FROM kwrows x LEFT JOIN holdout h ON h.campaign_id = x.campaign_id
          WHERE (h.campaign_id IS NOT NULL AND (NOT COALESCE(x.holdout, FALSE) OR x.holdout_eligible_from IS DISTINCT FROM h.eligible_from OR x.holdout_note IS NULL))
             OR (h.campaign_id IS NULL AND (COALESCE(x.holdout, FALSE) OR x.holdout_note IS NOT NULL)))
  UNION ALL
  SELECT 'B10 stalled-probe SEAT rows publish the raise (old, new, date, clicks, days), a size-aware sentence, no due date, and a seat-price proposal',
         (SELECT COUNT(*) FROM r WHERE row_type = 'SEAT' AND occupant_kind = 'stalled probe'
            AND (raise_old_bid IS NULL OR raise_new_bid IS NULL OR raised_on IS NULL OR clicks_since_raise IS NULL OR days_since_raise IS NULL
                 OR NOT (sentence LIKE '%entered at $%' OR sentence LIKE '%was nudged $%')
                 OR due_on IS NOT NULL
                 OR NOT (move LIKE 'raise to the seat price $%' OR move LIKE '%no seat price is published%')))
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
  SELECT 'B14 ABSORB rows are non-defense campaigns capped >= 4 of 7 days',
         (SELECT COUNT(*) FROM r a LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_CAP_STATE` cs ON cs.campaign_id = a.campaign_id
          WHERE a.row_type = 'ABSORB' AND (cs.campaign_id IS NULL OR cs.days_capped_7d < 4 OR cs.is_defense))
  UNION ALL
  SELECT 'B15 FAMILY figures reconcile (allowance, judged, capacity, share, basis), to the cent',
         (SELECT COUNT(*) FROM famrow f LEFT JOIN cat_sum c ON c.family = f.family AND c.horizon = f.horizon
          WHERE ABS(f.allowance_per_day - 0.20 * f.judged_per_day) > 0.01
             OR ABS(f.judged_per_day - (f.good_side_per_day + f.bad_side_per_day)) > 0.01
             OR ABS(f.open_capacity_per_day - (f.allowance_per_day - f.bad_side_per_day)) > 0.01
             OR (f.judged_per_day > 0 AND ABS(f.good_share - f.good_side_per_day / f.judged_per_day) > 0.001)
             OR c.s IS NULL OR ABS(f.spend_horizon_per_day - c.s) > 0.01)
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks ORDER BY check_name;

-- Determinism (spec §8): run twice, uncached; the two fingerprints must be identical.
--   SELECT COUNT(*) AS n, TO_HEX(MD5(STRING_AGG(TO_JSON_STRING(t), '|' ORDER BY sort_key)))
--   FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER` t;
