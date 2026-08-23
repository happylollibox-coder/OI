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
--       WHEN THIS CHECK IS VALID (2026-08-23). It compares two objects on DIFFERENT clocks: the
--       register's occupant set is derived from the basis window, which moves when the ads
--       watermark advances, while DE_FAMILY_SEAT_LEDGER only moves when SP_MAINTAIN_FAMILY_SEATS
--       runs (orchestrator step 20.8b, right after the keyword-state snapshot). Run the suite
--       between a watermark advance and the next 20.8b and B04 reports the drift as violations:
--       occupants the ledger has not been offered yet come through with a NULL seat_no (and two
--       NULLs in one family also read as a duplicate (family, seat_no) pair), and occupants that
--       stopped spending leave an open ledger row with no SEAT row. That is the pipeline's
--       ordinary state mid-day, not a defect in the view — before treating a B04 failure as one,
--       check `LOG_PIPELINE_RUNS` for the last SP_MAINTAIN_FAMILY_SEATS against the current ads
--       watermark, and re-run after the next pass. The register never writes the ledger.
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
--   B19 Gap causes (R-k, refined 2026-08-22): every GAP row is worded by its MEASURED cause.
--       keyword_id −1 (how SB video / PT product-target rows reach the warehouse — no keyword id)
--       says the ladder cannot see it and promises no verdict; a paused / archived current
--       DIM_KEYWORD row says the spend is trailing and leaves the universe when it stops; an
--       enabled row keeps the 'next state run' sentence; a row with a real id but no current
--       DIM_KEYWORD row says 'check why'. The retired blanket phrase 'the verdict ladder does not
--       track product targets' appears NOWHERE in the register (it was false on live rows: the
--       ladder tracks SP product targets and this register seats them). The FAMILY 'what closes
--       the gap' sentence words each bucket the same way and promises 'next state run' only when
--       an enabled untracked row exists.
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
--   B29 Recovered today = pauses only (R-l). On every FAMILY 'today' row whose 20% side is over
--       its allowance (over_by > 0), the figure the closing sentence names as recovered today is
--       re-derived INDEPENDENTLY from the register's OWN per-row costs: the rows a person can
--       actually pause when the sheet lands — LEAK rows and failed SEAT rows, minus any row whose
--       campaign is holdout-suppressed, because a holdout row gets no sheet row at all. Nothing
--       else counts: parking a stalled probe LOWERS its price and its spend continues, and
--       re-pricing a repair recovers nothing today by construction. The sentence's figure, the
--       sum of its listed (−$…/day) moves, and the re-derivation must agree within $0.02 — the
--       tolerance a two-decimal rendering of one aggregate carries against a sum of per-row costs
--       each rounded on its own row (R-m: a one-cent difference between an aggregate and the sum
--       of independently rounded components is a display fact, not a defect). The gap the sentence
--       names must be the row's own over_by. Then the closure claim is judged on the re-derived
--       number and never on the sentence's own arithmetic: short of the gap it must say it does
--       not close it; at or above it, it must say it closes.
--   B30 The two lines that recover nothing today are named and excluded (R-l). The stalled-probe
--       clause may never wear the executable (−$…/day) form and must name its dollars as spend at
--       risk of continuing, not recovered today; the repair clause may never wear it either and
--       must name itself a change of price whose result arrives at the re-judged horizon; and
--       neither family's stalled or repair dollars may sit inside the recovered-today figure.
--       This is the check that a shared assumption between view and test once hid: B29's
--       re-derivation used to read the same sentence the view wrote, so a projection folded into
--       the recovery passed both. It now reads the rows, never the sentence.
--   B31 The closing sentence reads in the order R-l fixes: the executable recovery first, then the
--       gap, then a plain closes / does-not-close verdict, then what the remaining dollars depend
--       on, and finally a pointer to that family's re-judged row.
--   B32 Every published move names the book it rides on, and names it PER ROW (R-l, wording,
--       rewritten 2026-08-23 after the arm shipped). Every dollar of the recovered-today figure
--       comes from a LEAK row or a failed SEAT row. A failed keyword's pause row rides the next
--       book the shipped reprice generator builds. A LEAK is now one of two different things and
--       the sentence must say which, measured against the change log, exactly as the projections
--       are: if a KEYWORD_PAUSE row for it already sits at PENDING_UPLOAD its sheet EXISTS, and
--       the move is to upload THAT batch — named by id on the row and published in book_batch_id
--       / book_action — and explicitly not to build another; if no book carries it, it rides the
--       next leak book, named by its file. The old unconditional 'pause it on the next leak book'
--       was the defect this check now forbids: it contradicted the $0 the same row published on
--       both projections, and a reader who followed it would have built a second batch of pause
--       rows he already had. The FAMILY leak clause is worded by the same split (all-on-book,
--       none-on-book, mixed), the split is re-derived HERE from FACT_PPC_CHANGE_LOG, every batch
--       id a sentence names must be one the log actually holds for that family's leaks, and no
--       FAMILY sentence may say the pauses can be uploaded 'today'. The closing sentence points at
--       the clauses ('The pauses named above recover $…') rather than asserting one book for all.
--   B33 The re-judged horizon never makes a stalled probe's spend vanish (R-l, applied to the
--       projection). Parking LOWERS a price; the keyword keeps serving and keeps spending. So for
--       every working family whose 'probe — stalled' CATEGORY costs money today, the same category
--       must still cost money on the re-judged horizon, and no FAMILY row's horizon_assumption may
--       claim stalled probes are parked to $0. This is the row the today sentence points the
--       reader at, so the two must not contradict each other about the same dollars.
--   B34 The projections respect the holdout arm (R-l, holdout half). A row whose campaign is
--       holdout-suppressed on the snapshot date gets NO sheet row at all, so neither the day-one
--       nor the re-judged horizon may book any change for it: its cost on both projections equals
--       its cost today, a repair in one never moves to the good side, and the horizon assumptions
--       say so in words. Re-derived from the register's own SEAT / LEAK / GAP rows. On a snapshot
--       where no campaign is yet suppressed this check is vacuous by construction; the branch is
--       proven on TMP_ copies and the proof recorded in the SOP.
--   B35 A projection credits a leak's pause ONLY where the sheet that pauses it EXISTS, row by row
--       (R-l, leak half, after its own overrule clause fired). A leak is a PARKED-past-appointment
--       or DEAD keyword that still spends. Until 2026-08-23 no generator built its pause row, so
--       neither projection could take it to $0. The leak arm SHIPPED that day
--       (tools/build_seat_moves_bulksheet.py), and R-l's recorded overrule path — "ship the leak
--       arm — the sheet then exists and the branch is one line in the same two CASE expressions,
--       with B35's first three legs flipping with it" — is what this check now enforces, in the
--       ONLY form that stays honest: PER ROW, against the change log, never per category.
--       This check re-derives the pending pause book ITSELF from FACT_PPC_CHANGE_LOG
--       (upload_status = 'PENDING_UPLOAD', action = 'KEYWORD_PAUSE') and never reads the view's
--       own belief about it. Then: (1) a LEAK with a pending pause row must reach $0 on BOTH
--       projections; (2) a LEAK with no pending pause row and no book bid row must equal its
--       today cost on both, to the cent; (3) a holdout-suppressed LEAK is never zeroed, whatever
--       the change log says, because it gets no sheet row at all; (4) no horizon assumption may
--       claim a blanket pause of the category — the credit is per row and the assumption must
--       say so; (5) both projection assumptions still name the leak arm by its file, so a reader
--       can find the sheet the dollars ride on. The failed half is unchanged: its pause row comes
--       from the reprice generator and always has.
--
--   B36 The recovered-today figure counts ONLY the pauses the leak book will WRITE (R-l, engine
--       parity). The holdout guard was one of FOUR measured refusals in
--       tools/build_seat_moves_bulksheet.py's classify_leak; the other three — already switched
--       off in Amazon, no readable live state, season BLOCK_CUT — were not applied to the
--       arithmetic, so the register could promise dollars no sheet can move. This check
--       re-derives all four FROM THE SOURCES (both keyword feeds with the generator's rule that a
--       disagreement never reads as ENABLED, plus V_KEYWORD_CONTEXT_GATE) and asserts: a refused
--       leak publishes 'no sheet row' and says its dollars are not recovered; a leak the book WILL
--       write never publishes 'no sheet row'; NO season-blocked leak is counted as recoverable;
--       and the family clause names the refused ones instead of dropping them.
--       Leg (3) is load-bearing for a decision made on measurement: the season gate is read HERE
--       and not in the view because joined into the register it re-plans on every branch and takes
--       a full read from ~24s to 45-98s. That is safe only while leg (3) reads zero. If it fires,
--       materialise the gate into a T_ the register can afford — never widen the tolerance.
--       TDD record (2026-08-23): proven on TMP_ copies, never on live rows. TMP_KWFEED_PROOF is a
--       copy of the keyword feed with one live leak forced to 'paused'; against a register built
--       on it WITH this guard, B29/B32/B36 = 0/0/0, and against the same register with the guard
--       removed (the pre-change arithmetic) B29 = 1 and B36 = 2. All three TMP_ objects dropped.
--
-- WHAT THIS SUITE CANNOT SEE. The deploy command strips every `--` line, so the view's own header
-- block does not exist in the deployed definition: no check here, and no query against
-- INFORMATION_SCHEMA.VIEWS, can catch a stale sentence in the header of
-- scripts/bigquery/views/V_FAMILY_SEAT_REGISTER.sql, in architecture/FAMILY_SEAT_REGISTER.md, or
-- in the config.yaml entry. A retired belief has survived in those files twice while every check
-- here passed. The instrument for them is:
--
--     /usr/bin/python3 tools/check_retired_phrases.py
--
-- It replaces the `grep -nE '…'` that used to live in this comment, which failed twice and both
-- times structurally: it was LINE-based and the files are hard-wrapped (a retired phrase that
-- straddles a newline is invisible to it — 'the sheet that would pause it does not exist' IS in
-- the SOP and the documented grep does not return it; run as written it found 2 hits where a
-- whitespace-insensitive scan of the same files finds 4), and it read two files when three carry
-- the doctrine (config.yaml holds the same prose at book length and sat outside it, which is
-- where the next retired clause was found). The script collapses whitespace, scans every file
-- that publishes the doctrine, allows a hit ONLY inside quotation marks, and knows that a
-- straight " in config.yaml is a YAML delimiter and not a quotation.
-- WHENEVER A MODEL IS RETIRED, ITS PHRASES ARE ADDED TO THAT SCRIPT IN THE SAME COMMIT. A check
-- that only knows yesterday's wrong answer passes over today's.
-- =============================================================================================
CREATE TEMP TABLE reg AS SELECT * FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER`;

-- ── B36 / B29 / B32: WHICH LEAKS THE BOOK WILL ACTUALLY WRITE A PAUSE ROW FOR.
-- The recovered-today figure may only count a pause the generator writes, so this suite
-- re-derives the generator's four refusals from the SOURCES (never from the register), in the
-- generator's own order: holdout, unreadable live state, already switched off, season BLOCK_CUT.
-- The live switch is read from BOTH feeds with the generator's rule — a disagreement never reads
-- as ENABLED — and the season gate is read HERE rather than in the view, on purpose: joined into
-- the register V_KEYWORD_CONTEXT_GATE re-plans on every branch and triples the read (24s -> 45-98s
-- measured 2026-08-23), so the expensive guard lives in the check and B36 is what makes its
-- absence safe. A B36 failure means a real season-blocked leak exists and the gate must be
-- materialised into a T_ the register can afford.
-- It is its own TEMP TABLE for the same reason `reg` is: two of the checks read it, and left as a
-- CTE the season gate re-planned per reference and took the suite from about five minutes to over
-- forty. Read once, then joined.
CREATE TEMP TABLE leak_refusal AS
WITH leak_feed AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         UPPER(COALESCE(state, '')) AS st
  FROM `onyga-482313.OI.V_SRC_AmazonAds_keyword`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY date DESC) = 1),
leak_dim AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         UPPER(COALESCE(state, '')) AS st
  FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY effective_from DESC, effective_to DESC) = 1),
leak_season AS (
  SELECT keyword_text, ANY_VALUE(gate_reason) AS gate_reason
  FROM `onyga-482313.OI.V_KEYWORD_CONTEXT_GATE`
  WHERE gate_action = 'BLOCK_CUT' GROUP BY 1),
leak_pick AS (
  SELECT l.campaign_id, l.keyword_id,
         sn.gate_reason IS NOT NULL AS season_blocked,
         CASE WHEN COALESCE(l.holdout, FALSE) AND l.as_of >= l.holdout_eligible_from THEN 'HOLDOUT'
              WHEN kf.st IS NULL AND kd.st IS NULL THEN 'LIVE_STATE_UNKNOWN'
              WHEN NOT (COALESCE(kf.st, kd.st) = 'ENABLED' AND COALESCE(kd.st, kf.st) = 'ENABLED')
                THEN 'ALREADY_PAUSED'
              WHEN sn.gate_reason IS NOT NULL THEN 'SEASON_BLOCKED'
              ELSE CAST(NULL AS STRING) END AS refusal
  FROM reg l
  LEFT JOIN leak_feed kf ON kf.cid = CAST(l.campaign_id AS STRING) AND kf.kid = CAST(l.keyword_id AS STRING)
  LEFT JOIN leak_dim  kd ON kd.cid = CAST(l.campaign_id AS STRING) AND kd.kid = CAST(l.keyword_id AS STRING)
  LEFT JOIN leak_season sn ON sn.keyword_text = l.target_text
                          AND NOT REGEXP_CONTAINS(LOWER(COALESCE(l.target_text, '')), r'^\s*(asin|category)\s*=')
  WHERE l.row_type = 'LEAK' AND l.horizon = 'today')
SELECT * FROM leak_pick;

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
-- the current DIM_KEYWORD row per keyword (R-k refined: the gap cause reads its state)
dimk AS (SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid, UPPER(state) AS dim_state
         FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current
         QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY effective_from DESC, effective_to DESC) = 1),
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
         COUNTIF(is_defense) AS n_defense
  FROM pos GROUP BY 1),
-- the gap causes re-derived per family (R-k refined): no keyword id / disabled trailing /
-- enabled next-run / unknown. The gap filter lives inside COUNTIF, never in a WHERE: filtering
-- on the universe's EXISTS-derived is_defense in a WHERE trips BigQuery's non-equality
-- ANTISEMI-join limitation (the house anti-join rule).
rd_gap AS (
  SELECT p.family,
         COUNTIF(NOT p.is_defense AND NOT p.on_ladder AND p.keyword_id = '-1') AS n_blind,
         COUNTIF(NOT p.is_defense AND NOT p.on_ladder AND p.keyword_id != '-1' AND dk.dim_state IN ('PAUSED', 'ARCHIVED')) AS n_trailing,
         COUNTIF(NOT p.is_defense AND NOT p.on_ladder AND p.keyword_id != '-1' AND dk.dim_state = 'ENABLED') AS n_next,
         COUNTIF(NOT p.is_defense AND NOT p.on_ladder AND p.keyword_id != '-1'
                 AND (dk.dim_state IS NULL OR dk.dim_state NOT IN ('PAUSED', 'ARCHIVED', 'ENABLED'))) AS n_check
  FROM pos p
  LEFT JOIN dimk dk ON dk.cid = p.campaign_id AND dk.kid = p.keyword_id
  GROUP BY 1),
-- every GAP row with its re-derived cause (the row's wording must match it)
gapc AS (
  SELECT x.*, CASE WHEN x.keyword_id = '-1' THEN 'NO_ID'
                   WHEN dk.dim_state IN ('PAUSED', 'ARCHIVED') THEN 'DISABLED'
                   WHEN dk.dim_state = 'ENABLED' THEN 'NEWLY_SEEN'
                   ELSE 'UNKNOWN' END AS cause
  FROM (SELECT * FROM r WHERE row_type = 'GAP') x
  LEFT JOIN dimk dk ON dk.cid = x.campaign_id AND dk.kid = x.keyword_id),
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
-- R-l, the gap-closure arithmetic. The ONLY move that takes dollars off the 20% side when the
-- sheet lands is a PAUSE: a leak paused, or a failed keyword killed with a pause row. A holdout
-- campaign gets no sheet row, so its rows recover nothing either. Everything below is re-derived
-- from the register's OWN rows so no check ever reads the sentence it is judging.
-- R-l, re-derived: the pauses the sheets will actually WRITE. A LEAK the generator refuses on a
-- measured ground (already switched off, unreadable, season-blocked) recovers nothing and may not
-- sit inside the recovered-today figure; the holdout guard was only the first of the four.
pause_rows AS (
  SELECT r.family, r.cost_per_day
  FROM r LEFT JOIN leak_refusal lf
    ON lf.campaign_id = r.campaign_id AND lf.keyword_id = r.keyword_id AND r.row_type = 'LEAK'
  WHERE r.horizon = 'today'
    AND (r.row_type = 'LEAK' OR (r.row_type = 'SEAT' AND r.occupant_kind = 'failed'))
    AND NOT (COALESCE(r.holdout, FALSE) AND r.as_of >= r.holdout_eligible_from)
    AND (r.row_type != 'LEAK' OR lf.refusal IS NULL)),
exec_rd AS (SELECT family, SUM(cost_per_day) AS exec_today, COUNT(*) AS n_exec FROM pause_rows GROUP BY 1),
-- the two kinds whose dollars do NOT leave the bad side today, priced from their own seat rows
noexec_rd AS (
  SELECT family,
         SUM(IF(occupant_kind = 'stalled probe', cost_per_day, 0)) AS stalled_today,
         SUM(IF(occupant_kind = 'repair', cost_per_day, 0)) AS repair_today
  FROM r WHERE horizon = 'today' AND row_type = 'SEAT'
    -- a seat in a holdout campaign gets no sheet row, so it is not even re-priceable and the
    -- family clause lists no move for it; only the rows a sheet can reach earn a named line
    AND NOT (COALESCE(holdout, FALSE) AND as_of >= holdout_eligible_from)
  GROUP BY 1),
gapclose AS (
  SELECT f.family, f.sentence, f.over_by_per_day,
         COALESCE(e.exec_today, 0) AS exec_today, COALESCE(e.n_exec, 0) AS n_exec,
         COALESCE(nx.stalled_today, 0) AS stalled_today, COALESCE(nx.repair_today, 0) AS repair_today,
         CAST(REGEXP_EXTRACT(f.sentence, r'recover \$([0-9]+\.[0-9]+)/day against the \$[0-9]+\.[0-9]+/day gap') AS FLOAT64) AS said_recover,
         CAST(REGEXP_EXTRACT(f.sentence, r'recover \$[0-9]+\.[0-9]+/day against the \$([0-9]+\.[0-9]+)/day gap') AS FLOAT64) AS said_gap,
         COALESCE((SELECT SUM(CAST(v AS FLOAT64)) FROM UNNEST(REGEXP_EXTRACT_ALL(f.sentence, r'\(−\$([0-9]+\.[0-9]+)/day')) v), 0) AS listed
  FROM famrow f LEFT JOIN exec_rd e ON e.family = f.family LEFT JOIN noexec_rd nx ON nx.family = f.family
  WHERE f.row_type = 'FAMILY' AND f.horizon = 'today' AND f.over_by_per_day > 0),
-- B33: the stalled-probe CATEGORY priced on the two horizons the today sentence points at.
-- Parking lowers a price; the spend continues, so a family that pays for stalled probes today
-- must still pay for them on the re-judged horizon.
stalled_cat AS (
  SELECT family,
         SUM(IF(horizon = 'today', cost_per_day, 0)) AS today_cost,
         SUM(IF(horizon = 're-judged', cost_per_day, 0)) AS rejudged_cost,
         COUNTIF(horizon = 're-judged') AS n_rejudged_rows
  FROM r WHERE row_type = 'CATEGORY' AND category = 'probe — stalled' GROUP BY 1),
-- B35: the leak half of R-l, after the arm shipped. The pending PAUSE book is re-derived HERE
-- from the change log — the check never asks the view what it believes is pending.
pending_pause_chk AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id, CAST(keyword_id AS STRING) AS keyword_id,
         -- every batch that carries a pending pause for this keyword, in a total ordering: B32
         -- asserts the batch the register NAMES is one of them, so the id on a published sentence
         -- is re-derived from the log and never taken from the view's own belief
         STRING_AGG(DISTINCT batch_id, ',' ORDER BY batch_id) AS batch_ids
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE upload_status = 'PENDING_UPLOAD' AND action = 'KEYWORD_PAUSE'
    AND keyword_id IS NOT NULL AND keyword_id != ''
  GROUP BY 1, 2),
leak_rows AS (
  SELECT l.family, l.campaign_id, l.keyword_id, l.cost_per_day, l.cost_day_one, l.cost_rejudged,
         l.book_batch_id, l.book_action, l.move, l.sentence,
         COALESCE(l.holdout, FALSE) AND l.as_of >= l.holdout_eligible_from AS no_sheet,
         pp.keyword_id IS NOT NULL AS pause_pending,
         pp.batch_ids, lf.season_blocked, lf.refusal
  FROM r l
  LEFT JOIN pending_pause_chk pp
    ON pp.campaign_id = CAST(l.campaign_id AS STRING) AND pp.keyword_id = CAST(l.keyword_id AS STRING)
  LEFT JOIN leak_refusal lf ON lf.campaign_id = l.campaign_id AND lf.keyword_id = l.keyword_id
  WHERE l.row_type = 'LEAK'),
-- B32: how many of each family's EXECUTABLE leaks (holdout-suppressed rows removed — they get no
-- sheet row at all) the pending pause book already carries, re-derived from the change log. The
-- family's leak clause must be worded by this split, because a reader sent to "the next leak book"
-- for a keyword the pending book already carries builds a SECOND batch of the same pause rows.
leak_book_split AS (
  SELECT family,
         COUNTIF(refusal IS NULL) AS n_exec,
         COUNTIF(refusal IS NULL AND pause_pending) AS n_on_book,
         COUNTIF(refusal IS NULL AND NOT pause_pending) AS n_off_book,
         COUNTIF(refusal IS NOT NULL AND refusal != 'HOLDOUT') AS n_refused
  FROM leak_rows GROUP BY 1),
-- every batch id a FAMILY sentence NAMES, and every batch id the CHANGE LOG holds for that
-- family's leaks: B32 anti-joins one against the other, so a sentence can never invent a book
fam_named_books AS (
  SELECT f.family, bid AS named_batch
  FROM r f, UNNEST(REGEXP_EXTRACT_ALL(f.sentence, r'pending leak book ([A-Za-z0-9_]+)')) bid
  WHERE f.row_type = 'FAMILY' AND f.horizon = 'today'),
fam_log_books AS (
  SELECT DISTINCT lr.family, b AS log_batch
  FROM leak_rows lr, UNNEST(SPLIT(COALESCE(lr.batch_ids, ''), ',')) b
  WHERE b != ''),
leak_cat AS (
  SELECT family,
         SUM(IF(horizon = 'today', cost_per_day, 0)) AS today_cost,
         SUM(IF(horizon = 'day one', cost_per_day, 0)) AS day1_cost,
         SUM(IF(horizon = 're-judged', cost_per_day, 0)) AS rejudged_cost,
         COUNTIF(horizon = 'day one') AS n_day1_rows,
         COUNTIF(horizon = 're-judged') AS n_rejudged_rows
  FROM r WHERE row_type = 'CATEGORY' AND category = 'closed but still spending' GROUP BY 1),
-- B34: every row that names a campaign, on the three horizons, with its holdout state. A
-- holdout-suppressed row gets no sheet row, so nothing may move on either projection.
hold_rows AS (
  SELECT campaign_id, keyword_id, family, row_type, horizon, category, cost_per_day
  FROM r
  WHERE row_type IN ('SEAT', 'LEAK', 'GAP') AND campaign_id IS NOT NULL
    AND COALESCE(holdout, FALSE) AND as_of >= holdout_eligible_from),
hold_cat AS (
  SELECT h.family, c.horizon, SUM(c.cost_per_day) AS s
  FROM (SELECT DISTINCT family FROM hold_rows) h
  JOIN r c ON c.family = h.family AND c.row_type = 'CATEGORY'
  GROUP BY 1, 2),
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
            -- a holdout-suppressed seat carries the holdout move instead of the R-f proposal, by
            -- design (holdout wins over every other move); B09 owns that row's wording
            AND NOT (COALESCE(holdout, FALSE) AND as_of >= holdout_eligible_from)
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
  SELECT 'B11 three horizons per working family with as_of, horizon_assumption and basis dates; re-judged carries no repair category except where the repair sits in a holdout campaign and can never be re-priced',
         (SELECT COUNT(*) FROM working w LEFT JOIN
            (SELECT family, COUNT(DISTINCT horizon) AS nh FROM famrow
             WHERE row_type = 'FAMILY' AND as_of IS NOT NULL AND horizon_assumption IS NOT NULL AND ads_basis_to IS NOT NULL GROUP BY 1) h
            ON h.family = w.family WHERE COALESCE(h.nh, 0) != 3)
         -- a repair moves to 'marginal — at its bar' when re-judged BECAUSE a sheet re-priced it.
         -- A repair in a holdout campaign gets no sheet row at all, so it is still in repair —
         -- the one family shape where the category legitimately survives the horizon (R-l).
         + (SELECT COUNT(*) FROM cat c WHERE c.horizon = 're-judged' AND c.category = 'losing — in repair'
              AND c.family NOT IN (SELECT family FROM r WHERE row_type = 'SEAT' AND occupant_kind = 'repair'
                                     AND COALESCE(holdout, FALSE) AND as_of >= holdout_eligible_from))
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
  SELECT 'B19 gap causes (R-k refined): every GAP row worded by its measured cause (no keyword id / paused trailing / enabled next state run / check why); the retired blanket phrase appears nowhere; the FAMILY sentence words each bucket the same way',
         (SELECT COUNT(*) FROM gapc
          WHERE CASE cause
                  WHEN 'NO_ID' THEN NOT (sentence LIKE '%no keyword id%' AND sentence LIKE '%cannot see%' AND move LIKE '%no keyword id%' AND move LIKE '%cannot see%')
                                    OR sentence LIKE '%next state run%' OR move LIKE '%next state run%'
                  WHEN 'DISABLED' THEN NOT (sentence LIKE '%trailing%' AND move LIKE '%trailing%')
                                       OR sentence LIKE '%next state run%' OR move LIKE '%next state run%'
                  WHEN 'NEWLY_SEEN' THEN NOT (sentence LIKE '%next state run%' AND move LIKE '%next state run%')
                  ELSE NOT (sentence LIKE '%check why%' AND move LIKE '%check why%') END)
         + (SELECT COUNT(*) FROM r WHERE COALESCE(sentence, '') LIKE '%the verdict ladder does not track product targets%'
                                      OR COALESCE(move, '') LIKE '%the verdict ladder does not track product targets%')
         + (SELECT COUNT(*) FROM famrow f JOIN rd_gap g ON g.family = f.family
            WHERE f.row_type = 'FAMILY' AND f.horizon = 'today' AND f.doctrine_status != 'IN'
              AND ((g.n_blind > 0 AND NOT (f.sentence LIKE CONCAT('%', CAST(g.n_blind AS STRING), ' SB video product target%') AND f.sentence LIKE '%no keyword id%'))
                   OR (g.n_trailing > 0 AND NOT f.sentence LIKE CONCAT('%', CAST(g.n_trailing AS STRING), ' paused target%trailing%'))
                   OR (g.n_next > 0 AND NOT f.sentence LIKE CONCAT('%', CAST(g.n_next AS STRING), ' enabled target%next state run%'))
                   OR (g.n_next = 0 AND f.sentence LIKE '%next state run%')))
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
  UNION ALL
  SELECT 'B29 recovered today = pauses only (R-l): the sentence\'s recovered-today figure, the moves it lists and the register\'s own per-row pause costs agree within $0.02 (the tolerance of a two-decimal aggregate against a sum of independently rounded per-row costs), the gap it names is the row\'s own over_by, and the closure claim is judged on the re-derived number, never on the sentence',
         (SELECT COUNTIF(
                   -- (a) the sentence must state a recovery and a gap at all
                   said_recover IS NULL OR said_gap IS NULL
                   -- (b) the recovered-today figure IS the register's own pause rows
                   OR ABS(said_recover - exec_today) > 0.02
                   -- (c) the moves it lists in the executable (−$…/day) form add to the same figure
                   OR ABS(listed - exec_today) > 0.02
                   -- (d) the gap it names is the row's own
                   OR ABS(said_gap - over_by_per_day) > 0.02
                   -- (e) the verdict is judged on the re-derived number, never on the sentence
                   OR (exec_today < over_by_per_day - 0.005
                       AND (sentence NOT LIKE '%that does not close it%' OR sentence LIKE '%that closes it%'))
                   OR (exec_today >= over_by_per_day - 0.005
                       AND (sentence NOT LIKE '%that closes it%' OR sentence LIKE '%that does not close it%')))
          FROM gapclose)
  UNION ALL
  SELECT 'B30 the lines that recover nothing today are named and excluded (R-l): the stalled-probe clause never wears the executable (−$…/day) form and names its dollars as spend at risk of continuing; the repair clause never wears it and names itself a change of price whose result arrives at the re-judged horizon; neither sits inside the recovered-today figure',
         (SELECT COUNTIF(
                   -- neither clause may borrow the executable moves' (−$…/day) form
                   REGEXP_CONTAINS(sentence, r'stalled probes[^;]*\(−\$')
                   OR REGEXP_CONTAINS(sentence, r'repairs[^;]*\(−\$')
                   -- parking lowers a price; the spend continues, and the row must say so
                   OR (stalled_today > 0 AND (sentence NOT LIKE '%stays at risk of continuing%'
                                              OR sentence NOT LIKE '%not recovered today%'))
                   -- a repair is a change of price whose result arrives at the re-judged horizon
                   OR (repair_today > 0 AND (sentence NOT LIKE '%a change of price, not a recovery%'
                                             OR sentence NOT LIKE '%re-judged%'))
                   -- and neither may be folded into the recovered-today figure
                   OR (stalled_today > 0.05 AND ABS(said_recover - (exec_today + stalled_today)) <= 0.005)
                   OR (repair_today > 0.05 AND ABS(said_recover - (exec_today + repair_today)) <= 0.005))
          FROM gapclose)
  UNION ALL
  SELECT 'B31 the closing sentence reads in the order R-l fixes: the executable recovery, then the gap, then a plain closes / does-not-close verdict, then what the remaining dollars depend on, then the pointer to that family\'s re-judged row',
         (SELECT COUNTIF(
                   STRPOS(sentence, 'The pauses named above recover $') = 0
                   OR STRPOS(sentence, 're-judged row') = 0
                   OR STRPOS(sentence, 're-judged row') < STRPOS(sentence, 'The pauses named above recover $')
                   OR (exec_today < over_by_per_day - 0.005
                       AND (STRPOS(sentence, 'The remaining $') = 0
                            OR STRPOS(sentence, 'depends on') = 0
                            OR STRPOS(sentence, 'The remaining $') < STRPOS(sentence, 'that does not close it')
                            OR STRPOS(sentence, 're-judged row') < STRPOS(sentence, 'The remaining $'))))
          FROM gapclose)
  UNION ALL
  SELECT 'B32 every published move names the book it rides on, and names it PER ROW (R-l wording after the arm shipped): a leak the pending book already carries is told to upload that batch by id and not to build another, a leak no book carries rides the next leak book, the FAMILY clause is worded by the same split re-derived from the change log, and no sentence promises an upload today',
         (SELECT COUNTIF(
                   sentence LIKE '%you can upload today%'
                   OR sentence LIKE '%pauses you can upload%'
                   -- a failed-keyword clause must name the book it rides on
                   OR (REGEXP_CONTAINS(sentence, r'kill the [0-9]+ failed keywords')
                       AND NOT REGEXP_CONTAINS(sentence, r'kill the [0-9]+ failed keywords on the next book'))
                   -- and the closing sentence points at the clauses, each of which names its own
                   -- book, instead of asserting one book for all of them
                   OR (over_by_per_day > 0 AND STRPOS(sentence, 'The pauses named above recover $') = 0))
          FROM famrow WHERE row_type = 'FAMILY' AND horizon = 'today')
         -- the FAMILY leak clause is worded by the log-derived split, not by a fixed phrase
         + (SELECT COUNTIF(
                   -- every leak already on a book: name the batch, forbid 'the next leak book'
                   (s.n_off_book = 0 AND s.n_exec > 0
                    AND (NOT REGEXP_CONTAINS(f.sentence, r'pause the [0-9]+ leaks? — every one is already written on the pending leak book ')
                         OR REGEXP_CONTAINS(f.sentence, r'leaks? on the next leak book')))
                   -- no leak on a book: the next-book form, and no batch may be named
                   OR (s.n_on_book = 0 AND s.n_exec > 0
                       AND NOT REGEXP_CONTAINS(f.sentence, r'pause the [0-9]+ leaks? on the next leak book \(tools/build_seat_moves_bulksheet\.py\)'))
                   -- mixed: both counts and both destinations named
                   OR (s.n_on_book > 0 AND s.n_off_book > 0
                       AND (NOT REGEXP_CONTAINS(f.sentence, r'are already written on the pending leak book ')
                            OR NOT REGEXP_CONTAINS(f.sentence, r'ride the next leak book \(tools/build_seat_moves_bulksheet\.py\)')))
                   )
            FROM famrow f JOIN leak_book_split s ON s.family = f.family
            -- only families that publish the gap clause carry a leak clause at all: a family
            -- inside its allowance (doctrine IN) is told what its open capacity buys, not what to
            -- pause, and has no clause to word
            WHERE f.row_type = 'FAMILY' AND f.horizon = 'today'
              AND f.sentence LIKE '%What closes the gap%')
         -- and any batch id a FAMILY sentence names must be one the change log actually holds for
         -- one of that family's leaks (an anti-join, so nothing here reads the view's own belief)
         + (SELECT COUNT(*) FROM fam_named_books n
            LEFT JOIN fam_log_books l ON l.family = n.family AND l.log_batch = n.named_batch
            WHERE l.log_batch IS NULL)
         -- and the LEAK row's own move is the same measurement, row by row
         + (SELECT COUNTIF(
                   -- off-book: the next leak book, named by its file. Only a leak the generator
                   -- will WRITE gets a book at all — a refused one is worded by B36, not here.
                   (refusal IS NULL AND NOT pause_pending
                    AND move NOT LIKE '%pause it on the next leak book (tools/build_seat_moves_bulksheet.py)%')
                   -- on-book: upload THAT batch, never build another, and publish the id
                   OR (refusal IS NULL AND pause_pending
                       AND (move NOT LIKE CONCAT('%pending leak book ', COALESCE(book_batch_id, '~'), '%')
                            OR move LIKE '%next leak book%'
                            OR book_action != 'KEYWORD_PAUSE'
                            OR book_batch_id IS NULL
                            OR STRPOS(CONCAT(',', COALESCE(batch_ids, ''), ','),
                                      CONCAT(',', COALESCE(book_batch_id, '~'), ',')) = 0
                            OR sentence NOT LIKE CONCAT('%pending leak book ', COALESCE(book_batch_id, '~'), '%'))))
            FROM leak_rows)
  UNION ALL
  SELECT 'B33 the re-judged horizon never zeroes a stalled probe (R-l applied to the projection): parking lowers a price, so a family paying for stalled probes today still pays for them when re-judged, and no horizon assumption claims they are parked to $0',
         (SELECT COUNTIF(today_cost > 0.005 AND (n_rejudged_rows = 0 OR rejudged_cost <= 0.005)) FROM stalled_cat)
         + (SELECT COUNTIF(horizon_assumption LIKE '%stalled probes are parked (→ $0)%')
            FROM r WHERE row_type IN ('FAMILY', 'REFERENCE') AND horizon_assumption IS NOT NULL)
         + (SELECT COUNTIF(horizon = 're-judged'
                           AND horizon_assumption NOT LIKE '%stalled probes are re-priced by the move on their own row%')
            FROM r WHERE row_type = 'FAMILY')
  UNION ALL
  SELECT 'B34 the projections respect the holdout arm (R-l holdout half): a holdout-suppressed row gets no sheet row, so its day-one and re-judged cost equal its cost today, no repair in one moves to the good side, and both horizon assumptions say so',
         -- the register publishes SEAT / LEAK / GAP rows on the today horizon only, so the
         -- per-row proof is the family CATEGORY arithmetic: a family whose only 20%-side movers
         -- are holdout-suppressed cannot improve on either projection
         (SELECT COUNTIF(h.s IS NULL) FROM (SELECT DISTINCT family FROM hold_rows) x
          LEFT JOIN hold_cat h ON h.family = x.family AND h.horizon = 'today')
         + (SELECT COUNT(*) FROM r WHERE row_type = 'CATEGORY' AND horizon = 're-judged'
              AND category = 'losing — in repair'
              AND family NOT IN (SELECT family FROM hold_rows))
         + (SELECT COUNTIF(horizon = 'day one' AND horizon_assumption NOT LIKE '%holdout%')
            FROM r WHERE row_type = 'FAMILY')
         + (SELECT COUNTIF(horizon = 're-judged' AND horizon_assumption NOT LIKE '%holdout%')
            FROM r WHERE row_type = 'FAMILY')
  UNION ALL
  SELECT 'B35 a projection credits a leak pause only where the sheet exists, row by row (R-l leak half after the arm shipped): a leak on a PENDING_UPLOAD pause row reaches $0 on both projections, a leak on none equals today, a holdout leak is never zeroed, and both assumptions name the leak arm by its file',
         -- (1) a leak the pending pause book carries must reach $0 on BOTH projections
         (SELECT COUNTIF(pause_pending AND NOT no_sheet
                         AND (COALESCE(cost_day_one, 1) > 0.005 OR COALESCE(cost_rejudged, 1) > 0.005))
          FROM leak_rows)
         -- (2) a leak NO pause row and NO bid row carries must equal today on both, to the cent
         --     (0.005: the register publishes costs rounded to four decimals on each row)
         + (SELECT COUNTIF(NOT pause_pending AND book_batch_id IS NULL
                           AND (ABS(COALESCE(cost_day_one, 0) - cost_per_day) > 0.005
                                OR ABS(COALESCE(cost_rejudged, 0) - cost_per_day) > 0.005))
            FROM leak_rows)
         -- (3) a holdout-suppressed leak gets no sheet row at all: never zeroed, log or no log
         + (SELECT COUNTIF(no_sheet AND cost_per_day > 0.005
                           AND (COALESCE(cost_day_one, 0) <= 0.005 OR COALESCE(cost_rejudged, 0) <= 0.005))
            FROM leak_rows)
         -- (4) the 'closed but still spending' CATEGORY may only fall to $0 on a projection when
         --     EVERY leak in that family is on the pending pause book
         + (SELECT COUNTIF(lc.today_cost > 0.005 AND lc.day1_cost <= 0.005
                           AND (SELECT COUNTIF(NOT pause_pending OR no_sheet) FROM leak_rows lr WHERE lr.family = lc.family) > 0)
            FROM leak_cat lc)
         -- (5) no assumption may claim a blanket pause of the category
         + (SELECT COUNTIF(horizon_assumption LIKE '%the leaks are paused%'
                           OR horizon_assumption LIKE '%leaks stay paused%'
                           OR horizon_assumption LIKE '%closed-but-spending keywords are paused%')
            FROM r WHERE row_type IN ('FAMILY', 'REFERENCE') AND horizon_assumption IS NOT NULL)
         -- (6) both projections must still name the leak arm by its file
         + (SELECT COUNTIF(horizon IN ('day one', 're-judged')
                           AND horizon_assumption NOT LIKE '%build_seat_moves_bulksheet.py%')
            FROM r WHERE row_type = 'FAMILY')
         -- (6) and no projection sentence may read 'N leaks paused'
         -- (7) a projection sentence may say a leak is paused ONLY where a pending pause row
         --     carries it: 'all N leaks paused' is forbidden while any leak of that family is
         --     off-book or holdout-suppressed, and the mixed form must name both counts.
         + (SELECT COUNTIF(f.horizon != 'today'
                           AND REGEXP_CONTAINS(f.sentence, r'all [0-9]+ leaks paused')
                           AND (SELECT COUNTIF(NOT lr.pause_pending OR lr.no_sheet)
                                FROM leak_rows lr WHERE lr.family = f.family) > 0)
            FROM famrow f WHERE f.row_type = 'FAMILY')
  UNION ALL
  SELECT 'B36 the recovered-today figure counts only pauses the leak book will WRITE (R-l, engine parity): every leak the generator refuses is published as no-sheet-row and kept out of the recovery, and no season-blocked leak is counted as recoverable',
         -- (1) a leak the generator REFUSES must not read as a pause on its own row: its move
         --     must open 'no sheet row' and its sentence must say the dollars are not recovered.
         --     Refusals are re-derived from the sources (leak_refusal), never from the register.
         (SELECT COUNTIF(refusal IS NOT NULL
                         AND (move NOT LIKE 'no sheet row%'
                              OR (refusal != 'HOLDOUT' AND sentence NOT LIKE '%not counted as recovered%')))
          FROM leak_rows)
         -- (2) and the converse: a leak the generator WILL write must never read as no-sheet-row
         + (SELECT COUNTIF(refusal IS NULL AND move LIKE 'no sheet row%') FROM leak_rows)
         -- (3) THE GUARD THE VIEW CANNOT AFFORD TO CARRY. V_KEYWORD_CONTEXT_GATE re-plans on every
         --     branch of the register (24s -> 45-98s a read, measured 2026-08-23), so the season
         --     BLOCK_CUT is read here and NOT in the view. That is safe only while this leg reads
         --     zero: a leak the season ledger blocks gets no pause row from the generator, and the
         --     register would still be counting its dollars as recovered. If this ever fires, the
         --     fix is a T_ materialisation of the gate that the register can afford to join —
         --     never a quiet tolerance.
         + (SELECT COUNTIF(season_blocked AND move NOT LIKE 'no sheet row%') FROM leak_rows)
         -- (4) the family's leak clause must count only the leaks the book will write, and must
         --     name the refused ones separately rather than dropping them silently
         + (SELECT COUNTIF(bs.n_refused > 0
                           AND f.sentence NOT LIKE '%get no pause row at all%')
            FROM famrow f JOIN leak_book_split bs ON bs.family = f.family
            WHERE f.row_type = 'FAMILY' AND f.horizon = 'today' AND f.over_by_per_day > 0)
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks ORDER BY check_name;

-- Determinism (spec §8): run twice, uncached; the two fingerprints must be identical.
--   SELECT COUNT(*) AS n, TO_HEX(MD5(STRING_AGG(TO_JSON_STRING(t), '|' ORDER BY sort_key)))
--   FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER` t;
