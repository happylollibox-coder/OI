-- =============================================
-- V_DAILY_BRIEF — one query answers Ori's three daily questions (2026-08-15).
-- Spec: architecture/DAILY_BRIEF.md.
--
-- (Ori 2026-08-15): "i can ask you daily what was planned, what actually happened and what are
-- your action items. the purpose is to make it better. meaning if after a change it became worse
-- this is not good."
--
-- FIVE SECTIONS, one uniform row shape, so the whole brief is SELECT * ORDER BY section:
--   PLANNED      — the latest FACT_ENGINE_PROPOSALS snapshot, GATE-FILTERED: what the engine wants
--                  done today, one price per keyword.
--   SKIPPED      — the instructions the gate refused, with the gate's own sentence and the value
--                  they wanted. Recorded, never deleted; just not on the list you upload from.
--   HAPPENED     — changes APPLIED in the last 48h, split status=planned (the engine proposed it
--                  on the day it was applied) / unplanned (manual, or the engine never said it —
--                  the manual-divergence doctrine's raw material).
--   VERDICT_NEW  — scorecard verdicts that became READABLE in the last 3 days. THE LAG IS THE
--                  INSTRUMENT: a change is judged at T+14 (SB T+21), never earlier — an early read
--                  systematically under-reads your own change and manufactures churn
--                  (V_CHANGE_SCORECARD header). So "what actually happened" arrives on a delay,
--                  by design, and this section is where it lands the morning it is finally honest.
--   SEATS        — the 80/20 doctrine read, one plain line per WORKING family, from the family
--                  seat register. Not an instruction: a standing position. It says how much of the
--                  family's judged spend is winning, at its bar or waiting for a verdict, what the
--                  20% side costs against its allowance, and what that side is made of (numbered
--                  seats, leaks still spending, untracked keywords). It never proposes a move of
--                  its own — the moves are on the register's own rows, and the line says so.
--   ACTION_ITEM  — verdicts that DEMAND a hand: REVERSED (restore the pre-change value, NEVER
--                  lower — remedy_value is the number) still unrestored, from the last 14 days of
--                  newly-readable grades. "if after a change it became worse this is not good" —
--                  this section is that sentence, mechanized.
--
-- PLANNER NOTE: V_CHANGE_SCORECARD is a ceiling view; FACT_ENGINE_PROPOSALS and the change log
-- are cheap. The scorecard subtree appears in two UNION arms — kept lean (no further joins on
-- those arms). If this view ever hits the planner, snapshot the scorecard the same way the guard
-- is snapshotted and point the two arms at the table.
--
-- ############################################################################
-- # v27.102 — ONE KEYWORD, ONE PRICE. THE BRIEF READS THE GATE'S VERDICT NOW. #
-- ############################################################################
-- (2026-08-21, found while preparing a hand-built upload.) This view read the very table
-- SP_ENGINE_PREFLIGHT stamps its verdict onto — and never read the verdict column. So every
-- collision loser the gate had already refused was printed in PLANNED beside the instruction that
-- beat it, at ITS OWN price, with nothing on the row to say it had lost. On a keyword three
-- engines instructed, the morning list offered three different bids for the same target and no
-- way to tell which one the account should get. The bulksheet is built BY HAND from this list, so
-- the bid that reached Amazon was decided by which line the eye landed on first.
--
-- The gate itself was never broken: it resolves every contention to a single surviving
-- instruction, and the surviving set on the day this was found carried exactly one price per
-- (campaign, key, lever). It resolved them onto the table and no reader downstream ever asked.
--
-- THREE PLACES QUOTED A PRICE; ALL THREE NOW QUOTE THE SURVIVOR:
--   1. PLANNED lists exportable instructions only (verdict GO or REVIEW, or none at all — an
--      unjudged row fails OPEN and is still a plan). REVIEW rows keep their place on the list and
--      say in the first clause that they need eyes before they are sent.
--   2. HAPPENED's "the engine proposed N" quote. It joined on (day, campaign, keyword) with no
--      verdict test, so a hand change on a contended keyword printed once PER PROPOSING ENGINE,
--      each line quoting a different number. It now reads the `survivor` CTE — one instruction
--      per key per day — so an applied change is one row quoting one price.
--   3. ACTION_ITEM's CONFLICT clause, which demotes a scorecard restore to REVIEW because "a live
--      engine outranks the remedy". A refused instruction is not a live engine, and it was both
--      demoting restores it had no standing to demote and duplicating the action item once per
--      proposing engine. Same CTE, same rule.
--
-- NOTHING IS DELETED. The refused instructions move to their own SKIPPED section carrying the
-- gate's plain sentence and the value they wanted, so the morning read still shows every opinion
-- the engine had — it just stops offering them as prices to copy. This is the same doctrine
-- SP_ENGINE_PREFLIGHT states for the holdout arm: block the export, never the judgement.
--
-- FAIL OPEN. Every test is COALESCE(verdict, 'GO') != 'EXCLUDE'. A partition written before
-- verdicts existed, or one the gate has not stamped yet, reads as a plan — the brief must not go
-- blank because a procedure did not run.
--
-- SECTION_RANK RENUMBERED, order unchanged: PLANNED 1, SKIPPED 2, HAPPENED 3, VERDICT_NEW 4,
-- ACTION_ITEM 5. The ritual is ORDER BY section_rank, so the sections still arrive in the order
-- they always did with the new one in the place it belongs.
--
-- ####################################################################
-- # v27.123 — SEATS: the 80/20 doctrine read joins the morning brief. #
-- ####################################################################
-- (2026-08-23, family seat register Task 4. Spec: architecture/FAMILY_SEAT_REGISTER.md.)
-- SECTION_RANK 6, APPENDED — the five existing sections keep their numbers and their order, so
-- the ritual query and every reader of it are byte-identical above the new section.
--
-- SEATS is not a sixth list of instructions. The other five sections answer "what was planned,
-- what happened, what needs a hand"; this one answers the standing question underneath them —
-- is each working family still spending 80% of its money on keywords that are winning, at their
-- bar, or waiting for a verdict? It is a POSITION, not a proposal, and the line says so in its
-- last clause: the moves live on the register's own rows, where the gap-closure arithmetic
-- (ruling R-l) is stated once and asserted once. This section deliberately re-states no
-- projection, promises no recovery and names no book — a second place doing R-l's arithmetic is a
-- second place for it to drift.
--
-- IT READS THE MATERIALISED REGISTER, NOT THE LIVE VIEW. T_FAMILY_SEAT_REGISTER is built by
-- SP_REFRESH_CUBE_TABLES step 0c, and the SeatRegister cube and V_RUN_SUMMARY's SEATS section read
-- the same table. Three surfaces, one image: they cannot quote different numbers at the same
-- reader on the same morning. The cost of that choice is stated on the line itself — every SEATS
-- row prints the ads window it was measured on and the keyword snapshot it came from, so a reader
-- who built a book since the last pass can see that this line has not seen it yet.
--
-- v27.125 (2026-08-23, repair pass): (1) the 'rebuild the leak book' action NAMES THE BATCH —
-- `--replaces <batch>` — because the generator's --replaces takes one or more batch ids and
-- refuses a build that does not name the pending book, so the earlier template ('--replaces)'
-- with nothing after it) was an instruction a new user could not execute as written; the batch
-- ids are read register-wide off the LEAK rows that carry them (one leak book at a time, R-n).
-- (2) A repair the register now marks ENGINE_PRICES or TOO_THIN_TO_PRICE (B38) is NOT a row for
-- the next book: it is named in the detail as 'not on any sheet', never counted toward an action.
-- THE ACTION IS DERIVED FROM WHAT IS EXECUTABLE (v27.124, 2026-08-23), never from the doctrine
-- status alone: the register publishes sheet_row on every SEAT and LEAK row, and this section
-- counts those — a stale leak book to rebuild, a pending book to upload, rows for the next book,
-- stalled probes by hand — in that priority. Only when nothing is executable does the status
-- speak, and an OUT family then reads 'nothing executable today', because its gap may depend on
-- a ruling (untracked spend) or a re-judgement, not on a move. Asserted by C11.
--
-- THE LABEL CASE LEARNS EVERY STATUS THE REGISTER CAN EMIT — IN, AT_LINE, OUT, NO_SPEND,
-- REFERENCE and the bare UNMAPPED literal the unmapped block selects (the file checker reads
-- bare literals as well as CASE arms since 2026-08-23) — and its fall-through says so in words
-- instead of returning NULL. Nothing here may
-- render blank: every FORMAT argument is COALESCEd, because CONCAT with one NULL argument returns
-- NULL and would publish an empty line rather than a wrong one, which is worse. The acceptance
-- suite (scripts/bigquery/tests/SEAT_SURFACE_acceptance.sql, C04) asserts no row is blank and no
-- row wears the fall-through wording; the file checker
-- scripts/bigquery/tests/check_seat_surface_labels.py asserts the CASE still names every status
-- the register's own doctrine_status CASE can produce, so adding one there fails the build here.
--
-- The standing assertion for this defect is V_ENGINE_HEALTH's plan_price_ambiguity check, with a
-- pre-deploy twin in scripts/bigquery/check_one_price_per_key.py.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_DAILY_BRIEF` AS
WITH latest AS (
  SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
),

-- v27.102: today's judged instructions, read ONCE and split two ways below. `exportable` is the
-- whole rule of this view in one expression — an instruction is a plan unless the gate refused
-- it, and an unstamped instruction is a plan (COALESCE, so a missing verdict fails open).
today AS (
  SELECT p.*, (COALESCE(p.verdict, 'GO') != 'EXCLUDE') AS exportable
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS` p, latest
  WHERE p.snapshot_date = latest.d
    -- v27.98: PLANNED is "what the engine wants DONE today". A row the last-day veto held is the
    -- engine saying wait, and it is now RECORDED in the proposal table (verdict EXCLUDE, with the
    -- veto's own sentence) rather than erased — but it belongs in the audit trail, not on the
    -- morning list, exactly as the table's own header argues about hold rows. This keeps the
    -- brief byte-identical to what it printed before held rows existed.
    AND p.hold_source IS NULL
),

-- v27.102: THE SURVIVING INSTRUCTION, one per (day, campaign, keyword). Used wherever the brief
-- QUOTES a price back at the reader — the HAPPENED comparison and the ACTION_ITEM conflict flag.
-- Both used to join the raw proposal table, so a contended keyword duplicated the row once per
-- proposing engine and each copy quoted a different number.
-- The pick order is deliberate and total: instructions that CARRY a value first (a negate has no
-- value, and "the engine proposed" followed by nothing is not a sentence), then the ownership
-- ladder SP_ENGINE_PREFLIGHT ranks by, then the engine name so a re-run is byte-identical.
survivor AS (
  SELECT snapshot_date, campaign_id, COALESCE(keyword_id, '') AS kid,
         CASE grain WHEN 'BUDGET' THEN 'BUDGET' WHEN 'NEGATE' THEN 'NEGATE' ELSE 'BID' END AS lever,
         engine, action, suggested_bid, suggested_budget
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE hold_source IS NULL
    AND COALESCE(verdict, 'GO') != 'EXCLUDE'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY snapshot_date, campaign_id, COALESCE(keyword_id, '')
    ORDER BY IF(COALESCE(suggested_bid, suggested_budget) IS NULL, 1, 0),
             CASE engine WHEN 'LOW_STOCK' THEN 1 WHEN 'LAUNCH' THEN 2 WHEN 'OOB' THEN 3
                         WHEN 'REVERDICT' THEN 4 WHEN 'LIFT' THEN 5 WHEN 'COACH' THEN 6 ELSE 9 END,
             engine) = 1
),
-- today's slice of the same CTE. A separate name because BigQuery refuses a scalar subquery
-- inside a JOIN predicate ("Unsupported subquery with table in join predicate") — the date
-- restriction has to happen before the join, not inside it.
survivor_today AS (
  SELECT s.* FROM survivor s, latest WHERE s.snapshot_date = latest.d
),

planned AS (
  SELECT
    'PLANNED' AS section, 1 AS section_rank,
    p.engine AS source, p.campaign_name, p.target_text AS item, p.action,
    COALESCE(p.current_bid, p.current_budget) AS from_value,
    COALESCE(p.suggested_bid, p.suggested_budget) AS to_value,
    p.grain AS status,
    -- a REVIEW row is exportable but not unattended: the gate's condition leads the sentence, so
    -- it cannot be copied off this list without the caution being read first
    IF(p.verdict = 'REVIEW',
       CONCAT('check before sending — ', COALESCE(p.verdict_reason, 'flagged by the gate'),
              ' · ', p.reason),
       p.reason) AS detail,
    p.campaign_id, p.keyword_id
  FROM today p
  WHERE p.exportable
),

-- v27.102: refused, recorded, and off the price list. The gate's own sentence first (why it lost),
-- then the value it wanted, so the record of the opinion survives in full.
skipped AS (
  SELECT
    'SKIPPED' AS section, 2 AS section_rank,
    p.engine AS source, p.campaign_name, p.target_text AS item, p.action,
    COALESCE(p.current_bid, p.current_budget) AS from_value,
    COALESCE(p.suggested_bid, p.suggested_budget) AS to_value,
    COALESCE(p.verdict, 'EXCLUDE') AS status,
    CONCAT(COALESCE(p.verdict_reason, 'refused by the gate'),
           ' · what it wanted: ', p.reason) AS detail,
    p.campaign_id, p.keyword_id
  FROM today p
  WHERE NOT p.exportable
),

happened AS (
  -- the change log carries no campaign NAME — join the dim (cheap, current row only)
  SELECT
    'HAPPENED' AS section, 3 AS section_rank,
    a.source, dc.campaign_name, a.targeting AS item, a.action,
    COALESCE(a.old_bid, a.old_budget) AS from_value,
    COALESCE(a.new_bid, a.new_budget) AS to_value,
    -- planned = the engine proposed THIS key on the day it was applied
    IF(p.campaign_id IS NOT NULL, 'planned', 'unplanned') AS status,
    CONCAT('applied ', CAST(DATE(a.applied_at, 'America/Los_Angeles') AS STRING),
           IF(p.campaign_id IS NOT NULL,
              CONCAT(' — engine (', p.engine, ') proposed ',
                     CAST(COALESCE(p.suggested_bid, p.suggested_budget) AS STRING)),
              ' — no engine proposal that day')) AS detail,
    CAST(a.campaign_id AS STRING) AS campaign_id, CAST(a.keyword_id AS STRING) AS keyword_id
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED` a
  -- v27.102: the SURVIVING instruction, not every instruction. This join used to reach the raw
  -- proposal table, so one applied change on a contended keyword became one brief row per
  -- proposing engine — each quoting a different proposed price at a reader holding one bulksheet.
  -- The v27.98 hold_source rule and the gate's verdict both live in the CTE now.
  LEFT JOIN survivor p
    ON p.snapshot_date = DATE(a.applied_at, 'America/Los_Angeles')
   AND p.campaign_id = CAST(a.campaign_id AS STRING)
   AND p.kid = COALESCE(CAST(a.keyword_id AS STRING), '')
   -- v27.102: AND ON THE SAME LEVER, derived from the change's own values. Campaign-grain changes
   -- key on kid = '' and so does every NEGATE proposal in the campaign (a negate has no keyword
   -- id), so a search-term block was marking hand PAUSES as "planned" and then printing a blank
   -- sentence, because the CONCAT quoting the proposed price returns NULL on a value-less row.
   -- A change carrying no value at all — a pause — matches nothing, which is the honest answer:
   -- PAUSE is not one of the levers the engine proposes on.
   AND p.lever = CASE WHEN a.new_budget IS NOT NULL OR a.old_budget IS NOT NULL THEN 'BUDGET'
                      WHEN a.new_bid IS NOT NULL OR a.old_bid IS NOT NULL THEN 'BID'
                      ELSE 'NONE' END
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc
    ON CAST(dc.campaign_id AS STRING) = CAST(a.campaign_id AS STRING)
  WHERE a.applied_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 48 HOUR)
),

verdict_new AS (
  SELECT
    'VERDICT_NEW' AS section, 4 AS section_rank,
    CONCAT(s.source, ' ', s.coach_mode) AS source, s.campaign_name,
    COALESCE(s.targeting, s.search_term) AS item, s.action,
    SAFE_CAST(s.old_value AS FLOAT64) AS from_value,
    SAFE_CAST(s.new_value AS FLOAT64) AS to_value,
    s.verdict AS status,
    CONCAT(s.verdict_reason, ' · window GP-ROAS ',
           CAST(ROUND(COALESCE(s.win_gp_roas, 0), 2) AS STRING),
           IF(s.prior_available, CONCAT(' vs own prior ', CAST(ROUND(s.prior_gp_roas, 2) AS STRING)), ' (no prior)')) AS detail,
    CAST(s.campaign_id AS STRING) AS campaign_id, CAST(s.keyword_id AS STRING) AS keyword_id
  FROM `onyga-482313.OI.V_CHANGE_SCORECARD` s
  WHERE s.read_gate_date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 3 DAY)
                             AND CURRENT_DATE('America/Los_Angeles')
),

action_items AS (
  -- REVERSED = it became worse AND fell below its own record. Remedy is ALWAYS "restore the
  -- pre-change value" (remedy_value), never a further cut — the scorecard never punishes twice.
  --
  -- v2 (2026-08-15, same day it was born — the FIRST upload attempt caught this): a remedy is only
  -- a RESTORE while the graded change is still the STANDING value. The v1 filter used
  -- n_later_changes = 0, which counts later changes INSIDE THE GRADING WINDOW only — 25 of the
  -- first 27 "restores" had been re-decided since (BALL Mint loose-match: graded 0.69->0.55 on
  -- Jul 22, then FIVE more changes through Aug 9, live at $0.34 — "restore to $0.69" would stomp
  -- the newer ladder mid-settle, whose own verdict is not readable until Aug 23). Three guards:
  --   1. next_change_date IS NULL — no later change at ALL, not just in-window;
  --   2. LIVE PARITY — the config's current value must equal the graded new_value (+-0.011);
  --      an unlogged drift means the world moved without the log, which is its own finding;
  --   3. CONFLICT FLAG — if TODAY's proposal snapshot has an engine instructing this key AND the
  --      gate let that instruction stand, the row demotes to REVIEW naming the conflict
  --      (single-home: a live engine outranks a scorecard remedy; low stock outranks everything).
  --      v27.102: "and the gate let it stand" is new — a refused instruction is not a live engine.
  SELECT
    'ACTION_ITEM' AS section, 5 AS section_rank,
    'SCORECARD' AS source, s.campaign_name,
    COALESCE(s.targeting, s.search_term) AS item, s.action,
    SAFE_CAST(s.new_value AS FLOAT64) AS from_value,   -- where it sits now (verified live below)
    SAFE_CAST(s.remedy_value AS FLOAT64) AS to_value,  -- restore to this
    IF(pr.campaign_id IS NOT NULL, 'REVIEW', 'RESTORE') AS status,
    CONCAT('REVERSED on settled evidence — restore ', s.value_kind, ' to ',
           CAST(s.remedy_value AS STRING), ' (was changed ',
           CAST(s.change_date AS STRING), '; ', s.verdict_reason, ')',
           IF(pr.campaign_id IS NOT NULL,
              CONCAT(' · CONFLICT: ', pr.engine, ' proposes ', pr.action, ' ',
                     CAST(COALESCE(pr.suggested_bid, pr.suggested_budget) AS STRING),
                     ' today — the live engine outranks the remedy, decide by hand'),
              '')) AS detail,
    CAST(s.campaign_id AS STRING) AS campaign_id, CAST(s.keyword_id AS STRING) AS keyword_id
  FROM `onyga-482313.OI.V_CHANGE_SCORECARD` s
  LEFT JOIN (SELECT CAST(keyword_id AS STRING) kid, bid
             FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current) live_kw
    ON live_kw.kid = CAST(s.keyword_id AS STRING)
  LEFT JOIN (SELECT CAST(campaign_id AS STRING) cid, daily_budget
             FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`) live_c
    ON s.keyword_id IS NULL AND live_c.cid = CAST(s.campaign_id AS STRING)
  -- v27.102: only a SURVIVING instruction is "a live engine". A refused one has no standing to
  -- demote a restore to REVIEW, and this join used to duplicate the action item once per
  -- proposing engine, each copy naming a different conflicting price.
  LEFT JOIN survivor_today pr
    ON pr.campaign_id = CAST(s.campaign_id AS STRING)
   AND pr.kid = COALESCE(CAST(s.keyword_id AS STRING), '')
   -- v27.102: AND ON THE SAME LEVER. A budget restore keys on kid = '' — and so does every
   -- NEGATE proposal in the campaign, because a negate has no keyword id. So a search-term block
   -- was demoting campaign-budget restores to REVIEW as though it were a competing budget
   -- instruction, and printing a blank explanation while it did it (a negate carries no value, so
   -- the CONCAT that quotes the conflicting price returned NULL and took the whole sentence with
   -- it). One BOTTLE budget restore was sitting on the morning action list in exactly that state.
   AND pr.lever = s.value_kind
  WHERE s.verdict = 'REVERSED'
    AND s.remedy_value IS NOT NULL
    AND s.next_change_date IS NULL
    AND ABS(COALESCE(live_kw.bid, live_c.daily_budget) - SAFE_CAST(s.new_value AS FLOAT64)) <= 0.011
    AND ABS(SAFE_CAST(s.remedy_value AS FLOAT64) - SAFE_CAST(s.new_value AS FLOAT64)) > 0.011  -- no-op remedies out
    AND s.read_gate_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
),

-- v27.123 SEATS. The register's image, read once: a small table scan, not a plan (the register
-- itself is the expensive object, and step 0c has already paid for it).
seat_reg AS (
  SELECT * FROM `onyga-482313.OI.T_FAMILY_SEAT_REGISTER`
),
-- What the 20% side is MADE of, counted from the register's own per-row rows rather than re-read
-- off its family sentence. Settling seats are numbered on the ledger but counted on the 80% side
-- by Ori's ruling, so the seat count here is the 20% side's — the same set the family row prices.
seat_counts AS (
  SELECT family,
         COUNTIF(row_type = 'SEAT' AND side = '20') AS n_seats,
         COUNTIF(row_type = 'LEAK')                 AS n_leaks,
         COUNTIF(row_type = 'GAP')                  AS n_gaps,
         -- WHAT IS EXECUTABLE TODAY (v27.124, 2026-08-23): counted from the register's own
         -- per-row sheet_row, never inferred from the doctrine status. A family can be OUT with
         -- nothing to pause (Bottle: its gap is untracked spend and stalled probes) and IN with a
         -- pending book waiting (Fresh, LolliME: leaks already written on a pending leak book) —
         -- the action column used to say 'close the gap' to the first and 'no action' to the
         -- second, each the opposite of what the register's rows said.
         COUNTIF(sheet_row = 'REBUILD_LEAK_BOOK')                        AS n_rebuild,
         COUNTIF(sheet_row = 'PENDING_BOOK')                             AS n_pending,
         STRING_AGG(DISTINCT IF(sheet_row = 'PENDING_BOOK', book_batch_id, NULL), ', '
                    ORDER BY IF(sheet_row = 'PENDING_BOOK', book_batch_id, NULL)) AS pending_books,
         COUNTIF(sheet_row IN ('NEXT_LEAK_BOOK', 'NEXT_REPRICE_BOOK'))  AS n_next,
         COUNTIF(sheet_row = 'BY_HAND')                                  AS n_hand,
         -- B38 (v27.125): rows NO sheet will carry — the engine's own instruction prices one, a
         -- record too thin to read prices none. Named, never counted as executable.
         COUNTIF(sheet_row = 'ENGINE_PRICES')                            AS n_engine,
         COUNTIF(sheet_row = 'TOO_THIN_TO_PRICE')                        AS n_thin
  FROM seat_reg GROUP BY 1
),
-- The stale pending leak book(s), read ONCE register-wide (R-n: one leak book at a time, so the
-- state is account-wide, not per family): the batch ids the REBUILD_LEAK_BOOK leak rows carry.
-- The generator's --replaces needs them by name and refuses a build that does not name them.
stale_books AS (
  SELECT STRING_AGG(DISTINCT book_batch_id, ' ' ORDER BY book_batch_id) AS books
  FROM seat_reg
  WHERE row_type = 'LEAK' AND sheet_row = 'REBUILD_LEAK_BOOK' AND book_batch_id IS NOT NULL
),
-- One row per WORKING family. A launch family is published by the register as a REFERENCE row, not
-- a FAMILY row, so this filter is what keeps the house rule — a launch family is never judged on
-- profit — rather than a list of names anyone could forget to update.
seat_family AS (
  SELECT f.*, COALESCE(c.n_seats, 0) AS n_seats,
              COALESCE(c.n_leaks, 0) AS n_leaks,
              COALESCE(c.n_gaps,  0) AS n_gaps,
              COALESCE(c.n_rebuild, 0) AS n_rebuild,
              COALESCE(c.n_pending, 0) AS n_pending,
              c.pending_books,
              COALESCE(c.n_next, 0) AS n_next,
              COALESCE(c.n_hand, 0) AS n_hand,
              COALESCE(c.n_engine, 0) AS n_engine,
              COALESCE(c.n_thin, 0) AS n_thin,
              sb.books AS stale_books
  FROM seat_reg f LEFT JOIN seat_counts c ON c.family = f.family
  CROSS JOIN stale_books sb
  WHERE f.row_type = 'FAMILY' AND f.horizon = 'today'
),
seats AS (
  SELECT
    'SEATS' AS section, 6 AS section_rank,
    'SEAT REGISTER' AS source,
    s.family AS campaign_name,
    FORMAT('%d seat%s · %d leak%s · %d untracked',
           s.n_seats, IF(s.n_seats = 1, '', 's'),
           s.n_leaks, IF(s.n_leaks = 1, '', 's'),
           s.n_gaps) AS item,
    -- THE ACTION IS WHAT IS EXECUTABLE, in one fixed priority: a stale leak book is rebuilt
    -- before anything else is uploaded; a pending book is uploaded (or labelled) before the next
    -- one is built; a by-hand move (a stalled probe) is named when no sheet carries anything;
    -- and only when nothing is executable does the doctrine status speak — and then it says
    -- 'nothing executable', never 'close the gap' (the gap may depend on rulings, not moves).
    CASE WHEN s.n_rebuild > 0 THEN
           -- the batch is NAMED (v27.125): --replaces takes the pending batch id(s), and the
           -- generator refuses a build that does not name them. If no leak row carries a batch
           -- (every row of the pending book left the leak population), the generator still names
           -- the pending batch when it refuses — say so rather than print an empty argument.
           FORMAT('rebuild the leak book: `tools/build_seat_moves_bulksheet.py --replaces %s` — %d leak%s wait on it; do not upload %s',
                  COALESCE(s.stale_books, '<the pending batch id the generator names when it refuses a build without it>'),
                  s.n_rebuild, IF(s.n_rebuild = 1, '', 's'),
                  COALESCE(s.stale_books, 'the old book'))
         WHEN s.n_pending > 0 THEN
           FORMAT('upload the pending book%s %s — %d row%s wait on %s (or label %s never-uploaded)',
                  IF(STRPOS(COALESCE(s.pending_books, ''), ',') > 0, 's', ''), COALESCE(s.pending_books, '?'),
                  s.n_pending, IF(s.n_pending = 1, '', 's'),
                  IF(STRPOS(COALESCE(s.pending_books, ''), ',') > 0, 'them', 'it'),
                  IF(STRPOS(COALESCE(s.pending_books, ''), ',') > 0, 'them', 'it'))
         WHEN s.n_next > 0 THEN
           FORMAT('build the next book — %d row%s wait on it', s.n_next, IF(s.n_next = 1, '', 's'))
         WHEN s.n_hand > 0 THEN
           FORMAT('by hand — %d stalled probe%s to re-price or park', s.n_hand, IF(s.n_hand = 1, '', 's'))
         ELSE CASE s.doctrine_status
           WHEN 'IN'        THEN 'passes — nothing executable today'
           WHEN 'AT_LINE'   THEN 'at the line — nothing executable today'
           WHEN 'OUT'       THEN 'nothing executable today — the gap depends on rulings and re-judging; read the register'
           WHEN 'NO_SPEND'  THEN 'no judged spend — nothing to read'
           WHEN 'REFERENCE' THEN 'reference only — never judged on profit'
           WHEN 'UNMAPPED'  THEN 'unmapped spend — map the campaign to its family in Admin'
           ELSE 'a doctrine status this brief has not learned — read the register'
         END
    END AS action,
    -- from → to is the honest pair here: what the 20% side COSTS today, against what it is
    -- ALLOWED to cost. No bid and no budget is proposed by this section.
    s.bad_side_per_day  AS from_value,
    s.allowance_per_day AS to_value,
    s.doctrine_status   AS status,
    CONCAT(
      UPPER(s.family), ' ',
      CASE s.doctrine_status
        WHEN 'IN' THEN FORMAT('passes the 80/20 line: %.0f%% of its judged spend is winning, at its bar, or waiting for a verdict.',
                              100 * COALESCE(s.good_share, 0))
        WHEN 'AT_LINE' THEN FORMAT('sits at the 80/20 line: %.0f%% good, which is inside this family\'s own 7-day spend noise of %.1f points.',
                              100 * COALESCE(s.good_share, 0), 100 * COALESCE(s.at_line_band, 0))
        WHEN 'OUT' THEN FORMAT('is below the 80/20 line: %.0f%% of its judged spend is winning, at its bar, or waiting for a verdict.',
                              100 * COALESCE(s.good_share, 0))
        WHEN 'NO_SPEND' THEN 'spent nothing the doctrine judges on this window, so there is no ratio to read.'
        WHEN 'REFERENCE' THEN 'is a launch family and is never judged on profit.'
        WHEN 'UNMAPPED' THEN 'is spend no family claims; map the campaign to its family in Admin.'
        ELSE 'carries a doctrine status this brief has not learned; read the register.'
      END,
      FORMAT(' The 20%% side costs $%.2f/day against an allowance of $%.2f/day',
             COALESCE(s.bad_side_per_day, 0), COALESCE(s.allowance_per_day, 0)),
      IF(s.doctrine_status = 'OUT',
         FORMAT(' — over by $%.2f/day.', COALESCE(s.over_by_per_day, 0)),
         FORMAT(' — $%.2f/day of capacity is open, which is what a new probe may cost.',
                COALESCE(s.open_capacity_per_day, 0))),
      FORMAT(' That side is %d numbered seat%s ($%.2f/day), %d leak%s still spending ($%.2f/day) and %d untracked keyword%s ($%.2f/day).',
             s.n_seats, IF(s.n_seats = 1, '', 's'), COALESCE(s.seats_cost_per_day, 0),
             s.n_leaks, IF(s.n_leaks = 1, '', 's'), COALESCE(s.leak_per_day, 0),
             s.n_gaps,  IF(s.n_gaps  = 1, '', 's'), COALESCE(s.gap_per_day, 0)),
      -- what is executable today, counted from the register's own rows (the action above is the
      -- first of these in priority; the rest are named here so nothing waits unseen)
      FORMAT(' Executable today: %d row%s on a pending book%s, %d row%s for the next book, %d stalled probe%s by hand%s.',
             s.n_pending + s.n_rebuild, IF(s.n_pending + s.n_rebuild = 1, '', 's'),
             IF(s.n_rebuild > 0, ' that is STALE and must be rebuilt', IF(s.pending_books IS NULL, '', CONCAT(' (', s.pending_books, ')'))),
             s.n_next, IF(s.n_next = 1, '', 's'),
             s.n_hand, IF(s.n_hand = 1, '', 's'),
             IF(s.n_pending + s.n_rebuild + s.n_next + s.n_hand = 0, ' — nothing executable today', '')),
      -- B38 (v27.125): the rows no sheet will carry, named so nothing waits unseen — and never
      -- counted above, because a book row the generator refuses is not executable
      IF(s.n_engine + s.n_thin > 0,
         CONCAT(' Not on any sheet: ',
                IF(s.n_engine > 0, FORMAT('%d repair%s priced by the engine\'s own GO instruction', s.n_engine, IF(s.n_engine = 1, '', 's')), ''),
                IF(s.n_engine > 0 AND s.n_thin > 0, '; ', ''),
                IF(s.n_thin > 0, FORMAT('%d repair%s too thin for any book to price (the ladder re-judges %s)', s.n_thin, IF(s.n_thin = 1, '', 's'), IF(s.n_thin = 1, 'it', 'them')), ''),
                '.'),
         ''),
      -- the two dates that let a reader tell whether this line has seen what he did yesterday
      FORMAT(' Measured on the %d complete ads days to %s, from the keyword snapshot of %s.',
             DATE_DIFF(s.ads_basis_to, s.ads_basis_from, DAY) + 1,
             FORMAT_DATE('%b %d', s.ads_basis_to), FORMAT_DATE('%b %d', s.as_of)),
      ' Seat by seat — and, where the family is short, what closes the gap and what the rest depends on — is on this family\'s rows in V_FAMILY_SEAT_REGISTER; this line proposes no move of its own.'
    ) AS detail,
    -- names no campaign and no keyword, which is why the holdout rule has nothing to mark here:
    -- a family is not a campaign, and no sheet is built from this section.
    CAST(NULL AS STRING) AS campaign_id, CAST(NULL AS STRING) AS keyword_id
  FROM seat_family s
)

SELECT * FROM planned
UNION ALL SELECT * FROM skipped
UNION ALL SELECT * FROM happened
UNION ALL SELECT * FROM verdict_new
UNION ALL SELECT * FROM action_items
UNION ALL SELECT * FROM seats;
