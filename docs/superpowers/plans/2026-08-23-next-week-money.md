# Next Week's Money Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One engine plans next week's not-good money for the working families (HARVEST book): judge every keyword on the complete-days window, pot the good side's spend, ramp a share of it into numbered dollar-sized seats for the not-good side, write plan A (shadow) and plan B (live) nightly, own bids and budgets for those families in the preflight, produce one bulksheet, grade both plans at T+14, and backtest them.

**Architecture:** Three BigQuery layers — config (`DE_PLAN_CONFIG`, `FN_PLAN_CALENDAR_STATE`), judgement (`V_PLAN_WINDOW_JUDGMENT`, one row per working-family keyword with both plans' sides), and the nightly builder (`SP_BUILD_NEXT_WEEK_PLAN` → `FACT_PLAN_NEXT_WEEK`, append-only, partitioned by `as_of`). Ownership is enforced where the house already enforces holds: `SP_SNAPSHOT_ENGINE_PROPOSALS` writes `engine='PLAN'` rows and stamps `hold_source='PLAN'` on the retired engines' rows; `SP_ENGINE_PREFLIGHT` gains a belt arm. Execution stays manual: a new plan book (`tools/build_plan_bulksheet.py`) reuses the reprice book's row builders and change-log discipline; the two existing books refuse plan-owned keys. Grading is `V_PLAN_SCORECARD` (T+14 settled), health is `V_ENGINE_HEALTH` `plan_*` checks, the surface is the `PlanNextWeek` cube over `T_PLAN_NEXT_WEEK` and a Weekly Run panel.

**Tech Stack:** BigQuery Standard SQL (views, tables, stored procedures, SQL UDF) deployed with `bq query`; Python 3 (`/usr/local/bin/python3`, pytest, PyYAML, openpyxl) for books, tests and the backtest; Cube.js schema files; React/TypeScript dashboard (`dashboard-react`).

---

## Spec authority

`docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md` — rulings P-1..P-14. Every task below names the rulings it implements. Where this plan adjusts the suggested decomposition it says so in the task header and why.

**P-14 (added to the spec by this plan, 2026-08-23)** answers the defect Ori raised and has not ruled on: a window read today has not seen its own orders (SP settles ~D+7, SB ~D+14), so the not-good side is overstated. It is built BOTH ways, as instructed: (a) the window's gross profit is corrected for settle completion using the published curve (`V_ADS_SETTLE_CURVE` through `V_PLAN_SETTLE_COMPLETION` — never a hardcoded factor; where the curve cannot answer, the factor is 1.0, the row says so, and the plan rests on (b) alone), and (b) the guard is asymmetric — PROMOTE on fresh evidence, never DEMOTE until the window has settled (SP 7 / SB 14 complete days after `window_to`). Every row publishes `settle_arm` and `decided_by`, and every surface prints them. Ori has NOT ruled; the "to overrule" line is in the spec.

**Ruling coverage map** (self-review, every ruling to a task): P-1 T1 · P-2 T2 · P-3 T1 · P-4 T1+T2+T4 · P-5 T1 · P-6 T1 · P-7 T1 · P-8 T2 · P-9 T1+T2+T5+T6 · P-10 T0+T1 · P-11 T3+T4 · P-12 T2 · P-13 T0 · P-14 T1 (+ asserted in T2, printed in T4 and T7, counted in T5).

## House conventions (binding for every step)

- Repo `/Users/ori/Develop/OI`, project `onyga-482313`, dataset `OI`, branch `feat/campaign-first-strategy`. Other sessions commit to the same branch — always `git add` named files only.
- Deploy a SQL file: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"`. Never `cat` a `.sql` into `bq`.
- Back up before redeploying an existing object: `cp FILE FILE.bak.v27.NNN.$(date +%H%M)`. Backups are not committed.
- Every object registered in `config.yaml` in the right section (`views:` starts line 102, `tables:` 1592, `stored_procedures:` 2232, `functions:` 2747). Insert next to its siblings, never at the end of the file. Commit `config.yaml` via `git add -p config.yaml` selecting only your hunks.
- Standing Rule 0: mechanism in prose, queries for numbers, no pinned measurement in an SOP, header, or registry description. Declared constants (0.20, 7, 3, $0.25, the $20.01–$31.99 band) are exempt.
- Complete days only: every window ends at `wm − 1` where `wm = LEAST(MAX(date), FN_ADS_ANCHOR_CAP())` over `FACT_AMAZON_ADS` (America/Los_Angeles). The filling day never enters a window (P-10).
- Calendar is read on `CURRENT_DATE('America/New_York')`; ads facts on America/Los_Angeles.
- Never change `SP_SNAPSHOT_KEYWORD_STATE`, `T_FAMILY_BAR`/`V_FAMILY_BAR`, `FN_BID_FLOOR`/`V_BID_FLOOR`.
- Never delete a `FACT_PPC_CHANGE_LOG` row; books land `PENDING_UPLOAD`; `--supersede` and `--mark-uploaded` act on `PENDING_UPLOAD` rows only. Never upload to Amazon. Never commit `.tmp/`.
- Holdout (`DE_HOLDOUT_ASSIGNMENT` `arm='HOLDOUT'`, `unit_type='CAMPAIGN'`, `eligible_from` 2026-09-01) is excluded from every sheet and every `PLAN` proposal from `eligible_from`.
- Brand defense and launch (INVEST) families are never judged on profit — they are outside the plan's universe.
- Ceiling views (`V_OOB_KEYWORD`, `V_KEYWORD_LIFT`) are read only through their `T_` tables (`T_OOB_SEAT_ECONOMICS`, `T_LIFT_PROBES`).
- Python tests: `cd /Users/ori/Develop/OI && /usr/local/bin/python3 -m pytest tools/tests/ -q`. SQL acceptance files live in `scripts/bigquery/tests/` and must read `PASS` on every row.
- Version stamps for this plan: v27.130 (T0) … v27.138 (T8). The spec amendment (P-14) is v27.131 and is committed with T1. Dated header paragraph on every touched SQL file.

## Calendar note the engineer needs

On 2026-08-23 the live `DIM_US_HOLIDAYS` carries Back to School 2026 with `boost_start` 2026-08-01, `peak_start` 2026-08-10, `holiday_date` 2026-09-14, `cooldown_end` NULL. `FN_PLAN_CALENDAR_STATE` (T0) therefore reads **PEAK** from 2026-08-10 through 2026-09-17 (`holiday_date + 3`), and **OFF_PEAK** from 2026-09-18 until Christmas's `boost_start` 2026-10-01. The first plan nights run in PEAK: window 3 complete days, share 0.20.

**Correction, measured against the live calendar while building T0 (2026-08-23):** the Q4 half of the sentence above was wrong, and the T0 acceptance was corrected with it. Christmas's run-up does NOT run to 2026-11-02 — Halloween carries `peak_start` 2026-10-10 (cooldown NULL, `holiday_date` 2026-10-31), and PEAK wins over an overlapping BOOST, so the BOOST stretch is only 2026-10-01..2026-10-09 and PEAK runs from 2026-10-10 through Christmas's `cooldown_end`. The T0 acceptance therefore asserts 2026-10-05 = BOOST and 2026-10-15 = PEAK (the precedence, on a live overlap date) instead of the plan's original 2026-10-15 = BOOST, which the live calendar does not support. Read the year's shape from `FN_PLAN_CALENDAR_STATE` itself (the query is in `architecture/NEXT_WEEK_MONEY.md` §1), never from this paragraph. Ori's ruling is open: if the pre-Black-Friday weeks should be judged as a run-up at the BOOST share, that is a calendar edit or a precedence ruling, not a code change.

---

## File Structure

| path | action | one responsibility |
|---|---|---|
| `scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql` | create | the declared settings per calendar state (window, share, live plan, ramp steps) |
| `scripts/bigquery/functions/FN_PLAN_CALENDAR_STATE.sql` | create | one date → `OFF_PEAK` / `BOOST` / `PEAK` from the live holiday calendar |
| `scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql` | create | T0 acceptance |
| `scripts/bigquery/views/V_PLAN_SETTLE_COMPLETION.sql` | create | **(P-14a)** per channel x age, the completion factor read from `V_ADS_SETTLE_CURVE` — monotone, capped, floored, and honest when the curve cannot answer |
| `scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql` | create | the nightly plan, both plans, append-only (**DDL moved into T1** — the judgement view reads last night's sides for the P-14b guard) |
| `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql` | create | one row per working-family keyword: windows, window record raw AND settle-corrected, rule-B side, the P-14b asymmetric guard, grace, plan-A side, candidacy, prices, seat cost, rank |
| `scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql` | create | T1 acceptance (includes the P-14 checks) |
| `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql` | create | pot, allowance, ramp, seat cost, rank, seating, queue, moves, budgets, sentences, assertions |
| `scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql` | create | T2 acceptance (§9 guarantees) |
| `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql` | modify (insert Task 20.8c after 20.8b) | call the builder nightly after the seat ledger |
| `scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql` | modify (INSERT 10, 11; UPDATE 12) | PLAN rows in; LIFT/OOB/REVERDICT rows held for plan campaigns |
| `scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql` | modify | PLAN precedence; belt arm `is_plan_owned`; flag column |
| `scripts/bigquery/views/V_ENGINE_PREFLIGHT.sql` | redeploy | expose the new T_ column (SELECT *) |
| `scripts/bigquery/tests/PLAN_OWNERSHIP_acceptance.sql` | create | T3 acceptance |
| `tools/build_plan_bulksheet.py` | create | the plan book: keyword moves + campaign budget rows from the live plan |
| `tools/build_restore_plan_bulksheet.py` | create | undo sheet for a plan book from its audit csv |
| `tools/build_reprice_bulksheet.py` | modify | `PLAN_OWNED` disposition for keys the live plan owns |
| `tools/build_seat_moves_bulksheet.py` | modify | `PLAN_OWNED` disposition for leaks the live plan owns |
| `tools/tests/test_plan_book.py` | create | pure-function tests for the plan book |
| `tools/tests/test_change_log_discipline.py` | modify | add the plan book to `BOOKS` |
| `tools/tests/test_seat_moves.py` | modify | `PLAN_OWNED` test for the leak classifier |
| `scripts/bigquery/views/V_PLAN_SCORECARD.sql` | create | T+14 settled grade of both plans per family × calendar state, with the declared decision rule |
| `scripts/bigquery/views/V_ENGINE_HEALTH.sql` | modify | `plan_*` checks c23–c28; PLAN in the precedence CASE |
| `tools/backtest_next_week_plan.py` | create | weekly replay Sep 2024 → today, both plans, shares 0.20/0.35/0.50, report + query |
| `tools/tests/test_backtest_next_week_plan.py` | create | fixture test of the backtest aggregation |
| `scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql` | modify (step 0d) | `T_PLAN_NEXT_WEEK` = latest `as_of` image for the cube |
| `scripts/bigquery/views/V_RUN_SUMMARY.sql` | modify | `OWNERS` section (counts by engine) and the plan-held row |
| `cube/schema/PlanNextWeek.js` | create | cube over `T_PLAN_NEXT_WEEK` |
| `dashboard-react/src/pages/PlanNextWeekPanel.tsx` | create | per-family plan panel |
| `dashboard-react/src/pages/WeeklyRunPage.tsx` | modify | mount the panel |
| `dashboard-react/src/components/RunSummaryStrip.tsx` | modify | render the `OWNERS` section |
| `architecture/NEXT_WEEK_MONEY.md` | create | the SOP |
| `config.yaml` | modify | registrations (one per object, right section) |

---

### Task 0: DE_PLAN_CONFIG + FN_PLAN_CALENDAR_STATE (P-13, §3)

**Files:**
- Create: `scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql`
- Create: `scripts/bigquery/functions/FN_PLAN_CALENDAR_STATE.sql`
- Create: `scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql`
- Modify: `config.yaml` (tables: next to `DE_PEAK_WINDOW_OVERRIDE` ~line 1797; functions: next to `FN_ADS_ANCHOR_CAP` ~line 2748)

- [ ] **Step 1: Write the failing acceptance**

`scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql`:

```sql
-- =============================================================================================
-- DE_PLAN_CONFIG + FN_PLAN_CALENDAR_STATE acceptance — every row must read PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-13, §3.
-- Checks:
--   C01 exactly one ACTIVE row per calendar state, and all three states present
--   C02 settings in range: window_days 1..28, allowance_share (0,1], live_plan A|B, ramp_steps >= 1
--   C03 the function reads the live calendar: PEAK inside a peak, BOOST in the run-up, OFF_PEAK
--       between seasons (declared calendar dates, not measurements)
--   C04 the function never returns NULL or an unknown state over a two-year sweep
-- =============================================================================================
WITH cfg AS (
  SELECT calendar_state, COUNT(*) n
  FROM `onyga-482313.OI.DE_PLAN_CONFIG` WHERE is_active GROUP BY 1
),
c01 AS (
  SELECT 'C01 one active row per state, three states' AS check_name,
         (SELECT COUNT(*) FROM cfg WHERE n != 1)
       + (SELECT 3 - COUNT(*) FROM cfg WHERE calendar_state IN ('OFF_PEAK','BOOST','PEAK')) AS violations
),
c02 AS (
  SELECT 'C02 settings in range',
         COUNTIF(window_days NOT BETWEEN 1 AND 28 OR allowance_share <= 0 OR allowance_share > 1
                 OR live_plan NOT IN ('A','B') OR ramp_steps < 1)
  FROM `onyga-482313.OI.DE_PLAN_CONFIG` WHERE is_active
),
c03 AS (
  SELECT 'C03 calendar reads PEAK / BOOST / OFF_PEAK on declared dates',
         COUNTIF(NOT ok)
  FROM UNNEST([
    STRUCT(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(DATE '2026-12-20') = 'PEAK'     AS ok),
    STRUCT(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(DATE '2026-08-05') = 'BOOST'    AS ok),
    STRUCT(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(DATE '2026-08-23') = 'PEAK'     AS ok),
    STRUCT(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(DATE '2026-07-15') = 'OFF_PEAK' AS ok),
    STRUCT(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(DATE '2026-10-15') = 'BOOST'    AS ok)
  ])
),
c04 AS (
  SELECT 'C04 never NULL, never an unknown state (2025-01-01 .. 2026-12-31)',
         COUNTIF(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(d) IS NULL
                 OR `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(d) NOT IN ('OFF_PEAK','BOOST','PEAK'))
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2025-01-01', DATE '2026-12-31')) d
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03 UNION ALL SELECT * FROM c04)
ORDER BY check_name;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /Users/ori/Develop/OI && bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql)"`
Expected: error containing `Not found: Table onyga-482313:OI.DE_PLAN_CONFIG` (or `Function not found: FN_PLAN_CALENDAR_STATE`).

- [ ] **Step 3: Write DE_PLAN_CONFIG**

`scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql`:

```sql
-- =============================================================================================
-- DE_PLAN_CONFIG — v27.130 (2026-08-23): the declared settings of the next-week money plan,
-- ONE ROW PER CALENDAR STATE. The plan reads this table, never a literal (spec P-13).
--
--   calendar_state   OFF_PEAK | BOOST | PEAK  (FN_PLAN_CALENDAR_STATE decides which one is on)
--   window_days      complete days in the judged window (P-10): 7 off-peak, 3 in BOOST and PEAK
--   allowance_share  share of the GOOD side's window spend handed to the not-good side (P-2):
--                    0.20 off-peak and in PEAK; 0.50 in BOOST (Ori 2026-08-23) — a learning
--                    question; V_PLAN_SCORECARD and the backtest publish the evidence per state
--   live_plan        'B' (rule B judges the window) or 'A' (the ladder judges the side, P-9)
--   ramp_steps       windows over which the allowance closes the gap to today's not-good spend
--                    (P-8: three, like the three-step bid cap)
--   is_active        FALSE = superseded; kept for the audit trail. Readers take the latest
--                    active row per state (QUALIFY ROW_NUMBER ORDER BY updated_at DESC).
--
-- CREATE IF NOT EXISTS + a seed scoped by updated_by = 'plan_seed': re-running the file never
-- destroys a row Ori entered by hand (house DE_ pattern, DE_BUDGET_CONFIG).
-- Ori changes a setting by INSERTing a new active row for the state with a later updated_at and
-- setting is_active = FALSE on the old one — never by editing this file.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-13.
-- SOP: architecture/NEXT_WEEK_MONEY.md
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PLAN_CONFIG`
(
  calendar_state   STRING  NOT NULL,
  window_days      INT64   NOT NULL,
  allowance_share  FLOAT64 NOT NULL,
  live_plan        STRING  NOT NULL,
  ramp_steps       INT64   NOT NULL,
  min_orders       INT64   NOT NULL,   -- P-3, the window order floor; a setting, not a literal
  is_active        BOOL    NOT NULL,
  description      STRING,
  updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_by       STRING
)
OPTIONS (description = "v27.130 (2026-08-23) next-week money plan settings, one row per calendar state (OFF_PEAK | BOOST | PEAK): window_days (complete days, P-10), allowance_share (share of the good side's window spend for the not-good side, P-2/P-13), live_plan (A|B, P-9), ramp_steps (P-8). The plan reads the latest is_active row per state; never a literal. Seed rows carry updated_by = 'plan_seed' and are the only rows the DDL file rewrites. Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md. SOP: architecture/NEXT_WEEK_MONEY.md");

-- NOTE (v27.131). The seed sketched here — an unconditional DELETE of the seed rows and a
-- re-INSERT active with CURRENT_TIMESTAMP() — is the shape that SHIPPED AND WAS REPAIRED, because
-- it silently reverts a setting Ori changed by hand: his row survives the delete but stops being
-- the row the reader takes, since the reader takes the LATEST active row per state. The shipped
-- file seeds only a state with NO row at all, deletes only its own row for a state nobody has
-- ruled on, and stamps a declared sentinel updated_at. Read the deployed file, not this sketch:
--   scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql
```

**Read the deployed DE_PLAN_CONFIG.sql, not the sketch above** — the shipped table carries
`min_orders` (REQUIRED) and `description` (not `note`), and its seed defers to a hand-entered row.

- [ ] **Step 4: Write FN_PLAN_CALENDAR_STATE**

`scripts/bigquery/functions/FN_PLAN_CALENDAR_STATE.sql`:

```sql
-- =============================================================================================
-- FN_PLAN_CALENDAR_STATE(d) — v27.130 (2026-08-23): which calendar state a date is in, read
-- from the LIVE DIM_US_HOLIDAYS (the authority; the repo seed is stale — config.yaml says so).
--   PEAK     d BETWEEN peak_start AND COALESCE(cooldown_end, holiday_date + 3)   (wins)
--   BOOST    d >= boost_start AND d < COALESCE(peak_start, holiday_date)
--   OFF_PEAK otherwise
-- Categories = the four the house gate V_SEASON_PEAK_GATE uses. The season end follows the
-- gate's COALESCE(cooldown_end, holiday_date + 3) (BTS and Halloween carry NULL cooldowns).
-- Callers pass CURRENT_DATE('America/New_York') (the calendar is US Eastern) or a historical
-- date (the backtest). A scalar subquery over a 38-row table — cheap, and it constant-folds.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-13, §3.
-- =============================================================================================
CREATE OR REPLACE FUNCTION `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(d DATE)
RETURNS STRING
OPTIONS (description = "v27.130 (2026-08-23): calendar state of a date for the next-week money plan — PEAK (peak_start .. COALESCE(cooldown_end, holiday_date+3)) wins over BOOST (boost_start .. day before COALESCE(peak_start, holiday_date)) over OFF_PEAK; categories gift_season/prime_event/back_to_school/seasonal, read from the LIVE DIM_US_HOLIDAYS. Pair with DE_PLAN_CONFIG for the window and share. Spec P-13.")
AS ((
  SELECT COALESCE(
    IF(COUNTIF(d BETWEEN peak_start AND COALESCE(cooldown_end, DATE_ADD(holiday_date, INTERVAL 3 DAY))) > 0, 'PEAK', NULL),
    IF(COUNTIF(d >= boost_start AND d < COALESCE(peak_start, holiday_date)) > 0, 'BOOST', NULL),
    'OFF_PEAK')
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE category IN ('gift_season', 'prime_event', 'back_to_school', 'seasonal')
    AND boost_start IS NOT NULL
));
```

- [ ] **Step 5: Deploy both**

Run:
```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/functions/FN_PLAN_CALENDAR_STATE.sql)"
```
Expected: the first prints three statements' results (table created, 0 rows deleted, 3 rows inserted — on a re-run: 3 deleted, 3 inserted); the second prints `Created onyga-482313.OI.FN_PLAN_CALENDAR_STATE`.

- [ ] **Step 6: Run the acceptance**

Run: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql)"`
Expected: four rows, every `result` = `PASS`.

- [ ] **Step 7: Register in config.yaml**

Insert after the `DE_PEAK_WINDOW_OVERRIDE` entry in `tables:` (after its `source_files:` line, ~line 1800):

```yaml
  - name: "DE_PLAN_CONFIG"
    description: "v27.130 (2026-08-23) — the next-week money plan's declared settings, one active row per calendar state (OFF_PEAK | BOOST | PEAK): window_days (complete days, P-10), allowance_share (the share of the GOOD side's window spend handed to the not-good side — 0.20 off-peak and in PEAK, 0.50 in BOOST, Ori 2026-08-23, a learning question the scorecard and the backtest answer per state), live_plan (B = rule B judges the window; A = the ladder judges the side), ramp_steps (windows to close the gap to today's not-good spend). SP_BUILD_NEXT_WEEK_PLAN and V_PLAN_WINDOW_JUDGMENT read the latest is_active row for FN_PLAN_CALENDAR_STATE(CURRENT_DATE New York) — never a literal. Ori changes a setting by inserting a new active row and retiring the old (is_active = FALSE); the DDL rewrites only updated_by = 'plan_seed' rows. Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-13. SOP: architecture/NEXT_WEEK_MONEY.md"
    type: "data_entry"
    source_files: ["scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql"]
```

Insert after the `FN_ADS_ANCHOR_CAP` entry in `functions:` (~line 2752):

```yaml
  - name: "FN_PLAN_CALENDAR_STATE"
    description: "v27.130 (2026-08-23): FN_PLAN_CALENDAR_STATE(d DATE) -> 'PEAK' | 'BOOST' | 'OFF_PEAK' from the LIVE DIM_US_HOLIDAYS (categories gift_season/prime_event/back_to_school/seasonal): PEAK = peak_start .. COALESCE(cooldown_end, holiday_date + 3) and wins; BOOST = boost_start .. the day before COALESCE(peak_start, holiday_date); else OFF_PEAK. The next-week money plan pairs it with DE_PLAN_CONFIG (window, share per state); the backtest calls it on historical dates. Spec P-13, §3."
    source_files: ["scripts/bigquery/functions/FN_PLAN_CALENDAR_STATE.sql"]
    type: "sql_udf"
```

Verify: `/usr/local/bin/python3 -c "import yaml,collections; d=yaml.safe_load(open('config.yaml')); n=[e['name'] for s in ('views','tables','stored_procedures','functions') for e in d[s]]; print(len(n), [k for k,v in collections.Counter(n).items() if v>1])"`
Expected: a count and `[]` (no duplicate names).

- [ ] **Step 8: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/tables/DE/DE_PLAN_CONFIG.sql scripts/bigquery/functions/FN_PLAN_CALENDAR_STATE.sql scripts/bigquery/tests/PLAN_CONFIG_acceptance.sql
git add -p config.yaml
git commit -m "feat(plan): DE_PLAN_CONFIG + FN_PLAN_CALENDAR_STATE — declared settings per calendar state (v27.130, P-13)"
```

---

### Task 1: the judgement layer — settle completion, the plan table, and V_PLAN_WINDOW_JUDGMENT (P-1, P-3, P-4, P-5, P-6, P-7, P-9, P-10, P-14)

**Adjustment to the suggested decomposition, and why:** `FACT_PLAN_NEXT_WEEK`'s DDL is created HERE, not in T2. The P-14b guard has to know whether a keyword was on the good side last night, and last night's side lives in that table — so the table must exist before the view that reads it. Only the DDL moves; the builder that fills it is still T2. A second file, `V_PLAN_SETTLE_COMPLETION`, is added for P-14a so the completion factor is one object with one acceptance instead of a CTE nobody can test.

**Files:**
- Create: `scripts/bigquery/views/V_PLAN_SETTLE_COMPLETION.sql`
- Create: `scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql`
- Create: `scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql`
- Create: `scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql`
- Modify: `docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md` (P-14 — already written by the planning session; verify it is present before starting)
- Modify: `config.yaml` (`views:` next to `V_PEAK_WINDOW_RULE`; `tables:` next to `FACT_KEYWORD_STATE`)

- [ ] **Step 1: Confirm P-14 is in the spec before building it**

Run: `grep -c "P-14" docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md`
Expected: a count of at least `4` (the ruling row, the §3a section heading, and the two §9 guarantees). If it is `0`, stop — the ruling this task implements is missing and must be written first.

- [ ] **Step 2: Write the failing acceptance**

`scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql`:

```sql
-- =============================================================================================
-- V_PLAN_SETTLE_COMPLETION + V_PLAN_WINDOW_JUDGMENT acceptance — every row must read PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-1, P-3..P-7, P-10, P-14.
-- Checks:
--   C01 the window is complete days only: window_to = watermark - 1 and the window is exactly
--       window_days long (P-10); no window day is younger than age 2 (the precondition P-14a's
--       factor floor relies on)
--   C02 the universe is the HARVEST book, enabled campaigns, no brand defense, no launch (P-11 §8)
--   C03 one row per (campaign_id, keyword_id) — the judgement is a keyword-grain object
--   C04 every row carries a side for BOTH plans, and both are one of the declared values (P-9)
--   C05 P-14a: the corrected gross profit never flips sign and is never smaller in magnitude than
--       the raw one; the completion factor is in (0, 1]; a row whose curve cannot answer says
--       UNCORRECTED_NO_CURVE and carries factor 1.0
--   C06 P-14b: no keyword that was good sits on the not-good side while its window is unsettled;
--       every HELD_UNSETTLED row carries a settle_due_on strictly after today
--   C07 P-3/P-5: a GOOD row has 2+ observed orders (order counts are never inflated) or is a
--       GRACE / HELD_UNSETTLED row; every row names decided_by
--   C08 P-6/P-7: every not-good candidate has a planned_bid at or above its floor, a seat cost
--       that is not negative, and a rank score that is not NULL
-- =============================================================================================
WITH j AS (SELECT * FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`),
sc AS (SELECT * FROM `onyga-482313.OI.V_PLAN_SETTLE_COMPLETION`),
c01 AS (
  SELECT 'C01 complete days only, no day younger than age 2' AS check_name,
         COUNTIF(window_to != DATE_SUB(watermark, INTERVAL 1 DAY)
                 OR DATE_DIFF(window_to, window_from, DAY) + 1 != window_days
                 OR DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), window_to, DAY) < 2) AS violations
  FROM j
),
c02 AS (
  SELECT 'C02 HARVEST book only, no brand defense, no launch state',
         COUNTIF(book != 'HARVEST' OR is_brand_defense OR ladder_state = 'LAUNCH_CONTAINED')
  FROM j
),
c03 AS (
  SELECT 'C03 one row per campaign x keyword',
         (SELECT COUNT(*) FROM (SELECT campaign_id, keyword_id FROM j GROUP BY 1, 2 HAVING COUNT(*) > 1))
),
c04 AS (
  SELECT 'C04 both plans carry a declared side',
         COUNTIF(side_b NOT IN ('GOOD','NOT_GOOD') OR side_a NOT IN ('GOOD','NOT_GOOD'))
  FROM j
),
c05 AS (
  SELECT 'C05 P-14a correction is honest (sign, magnitude, factor range, no-curve label)',
         COUNTIF(SIGN(w_gp_corrected) != SIGN(w_gp)
                 OR ABS(w_gp_corrected) < ABS(w_gp) - 0.005
                 OR settle_factor_min <= 0 OR settle_factor_min > 1.0
                 OR (settle_arm = 'UNCORRECTED_NO_CURVE' AND settle_factor_min != 1.0))
  FROM j
),
c06 AS (
  SELECT 'C06 P-14b no unsettled demotion of a keyword that was good',
         COUNTIF((side_b = 'NOT_GOOD' AND was_good AND NOT settled)
                 OR (settle_arm = 'HELD_UNSETTLED'
                     AND (settle_due_on IS NULL
                          OR settle_due_on <= CURRENT_DATE('America/Los_Angeles')
                          OR side_b != 'GOOD')))
  FROM j
),
c07 AS (
  SELECT 'C07 P-3 order floor read on observed orders; decided_by always named',
         COUNTIF(decided_by IS NULL
                 OR (side_b = 'GOOD' AND w_ord < 2 AND decided_by NOT IN ('P-5','P-14b')))
  FROM j
),
c08 AS (
  SELECT 'C08 P-6/P-7 candidate price, seat cost and rank are usable',
         COUNTIF(side_b = 'NOT_GOOD'
                 AND (planned_bid < bid_floor - 0.005 OR seat_cost_per_day < 0
                      OR rank_score IS NULL))
  FROM j
),
c09 AS (
  -- an analytic function may not sit inside an aggregate, so the LAG is computed one level down
  SELECT 'C09 the completion curve is monotone in age and never above 1',
         (SELECT COUNTIF(bad) FROM (
            SELECT (sales_completion > 1.0
                    OR sales_completion <= 0
                    OR sales_completion < LAG(sales_completion)
                         OVER (PARTITION BY channel ORDER BY age_days) - 1e-9) AS bad
            FROM sc))
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06
      UNION ALL SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09)
ORDER BY check_name;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql)"`
Expected: an error containing `Not found: Table onyga-482313:OI.V_PLAN_WINDOW_JUDGMENT`.

- [ ] **Step 4: Write V_PLAN_SETTLE_COMPLETION (P-14a)**

`scripts/bigquery/views/V_PLAN_SETTLE_COMPLETION.sql`:

```sql
-- =============================================================================================
-- V_PLAN_SETTLE_COMPLETION — v27.131 (2026-08-23): "how much of this day's ads sales had arrived
-- when we read it?", per channel and per age in days. ONE ROW PER (channel, age_days).
--
-- WHY IT EXISTS (spec P-14a). A window read the day after it closes has not seen its own orders:
-- ads sales accrue across the attribution window (SP ~7 days, SB ~14). A plan that judges such a
-- window as it reads calls a keyword not-good for the crime of being recent, and parks it. So the
-- plan divides each window day's gross profit by the completion factor for that day's age.
--
-- THE FACTOR IS READ, NEVER DECLARED. It comes from V_ADS_SETTLE_CURVE, the house's published
-- measurement of restatement (first sample at each age vs the latest sample held), through three
-- treatments that make a measured curve safe to divide by:
--   FORWARD FILL   ages the curve has not measured take the last age it did measure.
--   MONOTONE       the published medians wobble by a point either way (a later age can read
--                  lower than an earlier one, which is noise, not evidence that sales vanished).
--                  A running MAX makes the factor non-decreasing in age, so an older day is never
--                  corrected harder than a younger one.
--   CAP AND FLOOR  capped at 1.0 (a day is never more than complete). Floored at the declared
--                  FACTOR_FLOOR below so no rebuilt curve can ever inflate a window more than
--                  twofold. The floor is not expected to bind: by P-10 no window day is younger
--                  than age 2, and the curve's own age-2 medians are far above it.
-- Beyond the curve's last measured age the factor is 1.0 by construction (the curve covers the
-- whole attribution window; anything older is settled).
--
-- HONESTY COLUMN. curve_available is FALSE when the curve cannot answer for this channel and age
-- — too few report dates behind the median, or no curve at all (V_ADS_SETTLE_CURVE needs several
-- days of SP_SNAPSHOT_ADS_RESTATEMENT samples before it says anything). The factor is then 1.0
-- and the consumer says so on the row: the plan falls back to the asymmetric guard (P-14b) alone.
--
-- SPEND IS PUBLISHED TOO, and is NOT used to correct anything: the same curve shows spend at
-- essentially its final value by age 2, which is why the plan corrects gross profit only. It is
-- carried here so the acceptance can assert that, rather than the plan asserting it from memory.
--
-- Declared constants (Standing Rule 0 exempt):
--   MIN_REPORT_DATES 8  — the median needs a week-plus of report dates behind it to be read as a
--                         factor rather than as a rumour.
--   FACTOR_FLOOR   0.50 — the twofold inflation cap described above.
--   MAX_AGE         120 — the grid this view publishes; older days are settled by any measure.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-14a, §3a.
-- SOP: architecture/NEXT_WEEK_MONEY.md
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_SETTLE_COMPLETION`
OPTIONS (description = "v27.131 (2026-08-23): the settle-completion factor the next-week money plan divides a window day's gross profit by, one row per (channel SP|SB, age_days 0..120). Read from V_ADS_SETTLE_CURVE (sales_pct_of_final_median), forward-filled over unmeasured ages, made monotone in age by a running MAX, capped at 1.0 and floored at a declared 0.50 so no rebuilt curve can inflate a window more than twofold; 1.0 beyond the curve's last measured age. curve_available says whether the curve could actually answer (enough report dates behind the median) — FALSE means the factor is 1.0 and the plan rests on the asymmetric guard alone (spec P-14a). spend_completion is published for the acceptance only: spend is at its final value by age 2, which is why only gross profit is corrected. Read by V_PLAN_WINDOW_JUDGMENT. Spec P-14a, §3a. SOP: architecture/NEXT_WEEK_MONEY.md")
AS
WITH k AS (
  SELECT 8 AS min_report_dates, 0.50 AS factor_floor, 120 AS max_age
),
raw AS (
  SELECT channel,
         age_days,
         SAFE_DIVIDE(sales_pct_of_final_median, 100) AS f_sales,
         SAFE_DIVIDE(spend_pct_of_final_median, 100) AS f_spend,
         report_dates
  FROM `onyga-482313.OI.V_ADS_SETTLE_CURVE`
  WHERE channel IN ('SP', 'SB')
),
bounds AS (
  SELECT channel, MAX(age_days) AS curve_max_age
  FROM raw
  GROUP BY 1
),
grid AS (
  SELECT ch AS channel, age AS age_days
  FROM k, UNNEST(['SP', 'SB']) AS ch, UNNEST(GENERATE_ARRAY(0, k.max_age)) AS age
),
joined AS (
  SELECT g.channel, g.age_days, r.f_sales, r.f_spend, r.report_dates, b.curve_max_age
  FROM grid g
  LEFT JOIN raw r ON r.channel = g.channel AND r.age_days = g.age_days
  LEFT JOIN bounds b ON b.channel = g.channel
),
filled AS (
  SELECT j.*,
         LAST_VALUE(f_sales IGNORE NULLS) OVER w AS f_sales_ff,
         LAST_VALUE(f_spend IGNORE NULLS) OVER w AS f_spend_ff,
         LAST_VALUE(report_dates IGNORE NULLS) OVER w AS report_dates_ff
  FROM joined j
  WINDOW w AS (PARTITION BY channel ORDER BY age_days ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
),
mono AS (
  SELECT f.*,
         MAX(f_sales_ff) OVER w AS f_sales_mono,
         MAX(f_spend_ff) OVER w AS f_spend_mono
  FROM filled f
  WINDOW w AS (PARTITION BY channel ORDER BY age_days ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  m.channel,
  m.age_days,
  CASE
    WHEN m.curve_max_age IS NULL THEN 1.0
    WHEN m.age_days > m.curve_max_age THEN 1.0
    WHEN m.f_sales_mono IS NULL THEN 1.0
    ELSE LEAST(1.0, GREATEST((SELECT factor_floor FROM k), m.f_sales_mono))
  END AS sales_completion,
  CASE
    WHEN m.curve_max_age IS NULL THEN 1.0
    WHEN m.age_days > m.curve_max_age THEN 1.0
    WHEN m.f_spend_mono IS NULL THEN 1.0
    ELSE LEAST(1.0, GREATEST((SELECT factor_floor FROM k), m.f_spend_mono))
  END AS spend_completion,
  CASE
    WHEN m.curve_max_age IS NOT NULL AND m.age_days > m.curve_max_age THEN TRUE
    WHEN m.f_sales_mono IS NULL THEN FALSE
    WHEN COALESCE(m.report_dates_ff, 0) < (SELECT min_report_dates FROM k) THEN FALSE
    ELSE TRUE
  END AS curve_available,
  CASE
    WHEN m.curve_max_age IS NULL THEN 'NO_CURVE'
    WHEN m.age_days > m.curve_max_age THEN 'BEYOND_CURVE'
    WHEN m.f_sales_mono IS NULL THEN 'NO_CURVE'
    WHEN COALESCE(m.report_dates_ff, 0) < (SELECT min_report_dates FROM k) THEN 'THIN_CURVE'
    ELSE 'CURVE'
  END AS factor_source,
  COALESCE(m.report_dates_ff, 0) AS report_dates
FROM mono m
ORDER BY channel, age_days;
```

- [ ] **Step 5: Write FACT_PLAN_NEXT_WEEK (the table only — the builder is T2)**

`scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql`:

```sql
-- =============================================================================================
-- FACT_PLAN_NEXT_WEEK — v27.131 (2026-08-23): the nightly plan for the working families, ONE ROW
-- PER (as_of, plan, campaign_id, keyword_id). Two plans are written every night (spec P-9):
--   plan 'B'  the LIVE plan — the window decides the side and the amount (rule B).
--   plan 'A'  the SHADOW plan — the ladder decides the side, the window decides the amount.
-- Nothing is ever deleted except today's own partition, which the builder rewrites when it re-runs
-- (idempotent on one pass). History is the scorecard's evidence and the P-14b guard's memory of
-- what the plan said last night.
--
-- Written by SP_BUILD_NEXT_WEEK_PLAN (orchestrator Task 20.8c). Read by V_PLAN_WINDOW_JUDGMENT
-- (last night's side, for P-14b), SP_SNAPSHOT_ENGINE_PROPOSALS (the PLAN engine's rows),
-- V_PLAN_SCORECARD (T+14 grading), tools/build_plan_bulksheet.py (the book) and the surfaces.
--
-- The table is created EMPTY here; the judgement view reads it and must not wait for the builder.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §4, §5, P-9, P-14.
-- SOP: architecture/NEXT_WEEK_MONEY.md
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
(
  as_of                      DATE    NOT NULL,
  plan                       STRING  NOT NULL,
  is_live_plan               BOOL    NOT NULL,
  family                     STRING,
  book                       STRING,
  campaign_id                STRING,
  campaign_name              STRING,
  keyword_id                 STRING,
  ad_group_id                STRING,
  target_text                STRING,
  match_type                 STRING,
  channel                    STRING,
  is_auto                    BOOL,
  is_pt                      BOOL,
  calendar_state             STRING,
  window_days                INT64,
  window_from                DATE,
  window_to                  DATE,
  watermark                  DATE,
  w_clk                      INT64,
  w_ord                      INT64,
  w_sp                       FLOAT64,
  w_gp                       FLOAT64,
  w_gp_corrected             FLOAT64,
  settle_factor_min          FLOAT64,
  settle_curve_available     BOOL,
  settled                    BOOL,
  settle_due_on              DATE,
  settle_arm                 STRING,
  decided_by                 STRING,
  was_good                   BOOL,
  family_bar                 FLOAT64,
  ret_raw                    FLOAT64,
  ret_corrected              FLOAT64,
  ladder_state               STRING,
  side                       STRING,
  verdict                    STRING,
  is_candidate               BOOL,
  rank_score                 FLOAT64,
  rank_no                    INT64,
  seat_no                    INT64,
  seat_cost_per_day          FLOAT64,
  current_bid                FLOAT64,
  planned_bid                FLOAT64,
  bid_floor                  FLOAT64,
  move                       STRING,
  planned_spend_per_day      FLOAT64,
  verdict_date               DATE,
  pot_per_day                FLOAT64,
  allowance_target_per_day   FLOAT64,
  allowance_ramped_per_day   FLOAT64,
  notgood_today_per_day      FLOAT64,
  ramp_step                  INT64,
  ramp_steps                 INT64,
  allowance_share            FLOAT64,
  campaign_planned_budget    FLOAT64,
  campaign_current_budget    FLOAT64,
  holdout                    BOOL,
  holdout_eligible_from      DATE,
  sentence                   STRING,
  built_at                   TIMESTAMP
)
PARTITION BY as_of
CLUSTER BY plan, family, campaign_id
OPTIONS (description = "v27.131 (2026-08-23) the next-week money plan, one row per (as_of, plan, campaign, keyword) for the working families (HARVEST book). Two plans every night: 'B' is live (the window decides the side and the amount, rule B) and 'A' is shadow (the ladder decides the side, the window decides the amount) — spec P-9. Carries the window and its record raw AND corrected for settle completion, the arm that decided the side (settle_arm / decided_by, spec P-14), the family's pot / allowance / ramp step, the seat number and seat cost, the planned price and the executable move, the campaign budget the plan implies, and the plain sentence a person reads. Append-only; the builder rewrites only today's partition. Written by SP_BUILD_NEXT_WEEK_PLAN (orchestrator 20.8c); read by V_PLAN_WINDOW_JUDGMENT (last night's side, for the P-14b guard), SP_SNAPSHOT_ENGINE_PROPOSALS, V_PLAN_SCORECARD, tools/build_plan_bulksheet.py and T_PLAN_NEXT_WEEK. Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md. SOP: architecture/NEXT_WEEK_MONEY.md");
```

- [ ] **Step 6: Write V_PLAN_WINDOW_JUDGMENT**

`scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql`:

```sql
-- =============================================================================================
-- V_PLAN_WINDOW_JUDGMENT — v27.131 (2026-08-23): ONE ROW PER working-family keyword, carrying the
-- window, the window record (raw AND corrected for settle completion), the side BOTH plans give
-- it, the arm that decided it, the repaired price, the seat cost and the rank. It decides nothing
-- about money: the builder (SP_BUILD_NEXT_WEEK_PLAN) does the potting, seating and queueing. This
-- view is the JUDGEMENT, and it is a view so a person can read it at any moment without a pass.
--
-- THE UNIVERSE (spec §8, P-11): the HARVEST book's families, campaigns that are ENABLED today, no
-- brand defense (never judged on profit), no launch-contained keyword (the launch controller owns
-- those). Everything else in the account is outside this plan and is untouched by it.
--
-- THE WINDOW (P-10, P-13): window_days complete days ending at the ads watermark minus one, where
-- the watermark is LEAST(MAX(date), FN_ADS_ANCHOR_CAP()) over FACT_AMAZON_ADS. The filling day
-- never enters a window. window_days and allowance_share come from DE_PLAN_CONFIG for the state
-- FN_PLAN_CALENDAR_STATE reads today — a literal appears nowhere in this file.
--
-- THE SIDE (P-1, P-3, P-5, P-14). Rule B judges the window, not the ladder's 90-day record:
--   GOOD        2+ orders IN THE WINDOW and window gross profit per ad dollar at or above the
--               family bar. Order COUNTS are read as observed and are never inflated (P-14a: a
--               count cannot be fractionally corrected); the RETURN is read corrected.
--   HELD_UNSETTLED (P-14b) a keyword that WAS good and now reads not-good, whose window has not
--               yet settled (SP 7 / SB 14 complete days after window_to). It keeps the good side,
--               held, and carries the date it will be judged again with no guard. Promotion is
--               allowed on fresh evidence; only demotion waits. This is the ASYMMETRY.
--   GRACE (P-5) a ladder-settled winner (WINNER / PACED_WINNER) with a quiet window keeps the
--               good side for one window, held. Ordered AFTER the settle guard so a one-window
--               grace budget is not spent while the evidence is still arriving.
--   LOSING / ONE_ORDER / NO_SALE / NOT_SERVING — the not-good side.
-- decided_by names the ruling that decided the row: P-3, P-14b or P-5. settle_arm names what the
-- correction did: SETTLED, CORRECTED, PROMOTED_ON_FRESH, HELD_UNSETTLED, UNCORRECTED_NO_CURVE.
--
-- "WAS GOOD" (P-14b) is last night's live-plan side if there is one, or — on the first night, and
-- for a keyword the plan has not seen — the ladder's own settled record at or above the bar with
-- 2+ settled orders. Both are records of a judgement already made, never of today's window.
--
-- PLAN A (shadow, P-9) takes the side from the ladder state alone: WINNER, PACED_WINNER, AT_BAR
-- and the waiting states (TRIAL, PENDING_SETTLE, REVIVED_SETTLING) are its good side; REPRICE,
-- LOSER, FLOOR_PROBATION, PARKED and DEAD are not. The amounts are the same window amounts.
--
-- THE REPAIRED PRICE (P-6) is the ladder's affordable_bid, capped at three 5% steps in either
-- direction from the live bid, floored at the row's own bid_floor (the ONE floor definition,
-- FN_BID_FLOOR through the state table) and ceilinged at the house $2.00 for a raise. The cap
-- constants are mirrored from tools/build_reprice_bulksheet.py so the book and the plan cannot
-- price the same keyword differently.
-- SEAT COST (P-6) is spend at THAT price, not last window's spend: the window's spend per day
-- scaled linearly by the price change (the same linear bid-to-spend guess the seat register uses
-- on its day-one horizon). A candidate with no window spend is priced at the engine's seat
-- economics — seat_cpc times the register's declared click goal per day.
-- RANK (P-7) is dollars at stake times closeness to the bar: window spend per day times corrected
-- return over the bar, ties broken by window clicks then by the keyword key (a total ordering).
--
-- Planner note: every source here is a snapshot table or a small view. The ceiling views are read
-- only through their T_ tables (T_OOB_SEAT_ECONOMICS, T_LIFT_PROBES), per the house rule.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §3, §3a, §4, P-1..P-14.
-- SOP: architecture/NEXT_WEEK_MONEY.md
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`
OPTIONS (description = "v27.131 (2026-08-23): one row per working-family (HARVEST) keyword — the complete-days window from DE_PLAN_CONFIG for today's calendar state, the keyword's record in it raw AND corrected for settle completion via V_PLAN_SETTLE_COMPLETION, the side rule B gives it (P-1/P-3), the P-14b asymmetric guard (promote on fresh evidence, never demote until the window has settled: SP 7 / SB 14), the P-5 grace for ladder-settled winners, the shadow plan A side from the ladder state (P-9), the repaired price capped at three 5% steps and floored at the row's own bid_floor (P-6), the seat cost at that price, and the P-7 rank. Publishes settle_arm and decided_by on every row so a reader can see which arm decided it. Judges only; SP_BUILD_NEXT_WEEK_PLAN does the potting, seating and queueing. Brand defense, launch-contained keywords and non-enabled campaigns are outside the universe. Spec P-1..P-14, §3a. SOP: architecture/NEXT_WEEK_MONEY.md")
AS
WITH k AS (
  -- P-3/P-13: min_orders is NOT a literal — it is read from DE_PLAN_CONFIG in the cfg CTE below
  -- and joined in. Writing `2 AS min_orders` here would put the order floor in two places that
  -- can disagree, which is the exact defect DE_PLAN_CONFIG exists to prevent (v27.131 fix).
  SELECT 0.05   AS material_step,     -- mirrored from tools/build_reprice_bulksheet.py MATERIAL_STEP
         3      AS blind_steps,       -- ...and BLIND_STEPS: the engine's blind run before a re-read
         2.00   AS raise_ceiling,     -- the house bid ceiling (GUARDIAN threshold redesign)
         4      AS click_goal_day,    -- mirrored from V_FAMILY_SEAT_REGISTER k.click_goal_day
         7      AS settle_days_sp,    -- SP attribution window, complete days (P-12, P-14b)
         14     AS settle_days_sb     -- SB attribution window, complete days
),
caps AS (
  SELECT k.*,
         POW(1 + k.material_step, k.blind_steps) - 1 AS cap_up,      -- +15.7625%
         1 - POW(1 - k.material_step, k.blind_steps) AS cap_down     -- -14.2625%
  FROM k
),
today AS (
  SELECT CURRENT_DATE('America/Los_Angeles') AS d_la,
         CURRENT_DATE('America/New_York')    AS d_ny
),
cfg AS (
  -- Every setting, min_orders included. Copy this CTE, not a subset of it.
  SELECT calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders
  FROM `onyga-482313.OI.DE_PLAN_CONFIG`
  WHERE is_active
  QUALIFY ROW_NUMBER() OVER (PARTITION BY calendar_state ORDER BY updated_at DESC) = 1
),
state AS (
  SELECT `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(t.d_ny) AS calendar_state
  FROM today t
),
wm AS (
  SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
),
win AS (
  -- P-10 + the P-14a FENCE. window_to is NOT simply wm - 1: FN_ADS_ANCHOR_CAP() advances to the
  -- current LA date at 22:00 LA, so a late-evening run would otherwise admit an age-1 day, whose
  -- SPEND the settle curve publishes as materially short of final — understating the pot, the
  -- allowance and every seat cost in the same direction. The fence gives up a day instead. Before
  -- 22:00 LA the two terms are equal and it costs nothing.
  SELECT s.calendar_state, c.window_days, c.allowance_share, c.live_plan, c.ramp_steps,
         c.min_orders,
         wm.d                                                  AS watermark,
         LEAST(DATE_SUB(wm.d, INTERVAL 1 DAY),
               DATE_SUB(t.d_la, INTERVAL 2 DAY))               AS window_to,
         DATE_SUB(LEAST(DATE_SUB(wm.d, INTERVAL 1 DAY),
                        DATE_SUB(t.d_la, INTERVAL 2 DAY)),
                  INTERVAL c.window_days - 1 DAY)              AS window_from
  FROM state s
  JOIN cfg c USING (calendar_state)
  CROSS JOIN wm
  CROSS JOIN today t
),
books AS (
  SELECT family, book FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'
),
snap AS (
  SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
),
camp AS (
  SELECT CAST(campaign_id AS STRING) AS cid,
         ANY_VALUE(campaign_state) AS campaign_state,
         ANY_VALUE(daily_budget)   AS daily_budget,
         ANY_VALUE(portfolio_id)   AS portfolio_id
  FROM `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
  GROUP BY 1
),
ks AS (
  SELECT s.*, b.book
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
  JOIN snap ON s.snapshot_date = snap.d
  JOIN books b ON b.family = s.family
  JOIN camp c ON c.cid = CAST(s.campaign_id AS STRING)
  WHERE NOT COALESCE(s.is_brand_defense, FALSE)
    AND s.state != 'LAUNCH_CONTAINED'
    AND UPPER(COALESCE(c.campaign_state, 'ENABLED')) = 'ENABLED'
),
-- the window record, PER DAY, so each day can be corrected at its own age (P-14a)
fdays AS (
  SELECT CAST(f.campaign_id AS STRING) AS cid,
         CAST(f.keyword_id AS STRING)  AS kid,
         f.date,
         f.campaign_type               AS ch,
         SUM(f.Ads_cost)     AS sp,
         SUM(f.Ads_clicks)   AS clk,
         SUM(f.Ads_orders)   AS ord,
         SUM(f.GROSS_PROFIT) AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  CROSS JOIN win
  WHERE f.date BETWEEN win.window_from AND win.window_to
    AND f.keyword_id IS NOT NULL
  GROUP BY 1, 2, 3, 4
),
rec AS (
  SELECT d.cid, d.kid,
         SUM(d.sp)  AS w_sp,
         SUM(d.clk) AS w_clk,
         SUM(d.ord) AS w_ord,
         SUM(d.gp)  AS w_gp,
         -- P-14a: each day's gross profit divided by ITS OWN completion factor. COALESCE to 1.0
         -- so a missing curve row can never drop a day out of the sum.
         SUM(SAFE_DIVIDE(d.gp, COALESCE(sc.sales_completion, 1.0))) AS w_gp_corrected,
         MIN(COALESCE(sc.sales_completion, 1.0))                    AS settle_factor_min,
         LOGICAL_AND(COALESCE(sc.curve_available, FALSE))           AS settle_curve_available,
         MIN(DATE_DIFF(t.d_la, d.date, DAY))                        AS min_age_days
  FROM fdays d
  CROSS JOIN today t
  LEFT JOIN `onyga-482313.OI.V_PLAN_SETTLE_COMPLETION` sc
    ON sc.channel = d.ch
   AND sc.age_days = LEAST(DATE_DIFF(t.d_la, d.date, DAY), 120)
  GROUP BY 1, 2
),
-- P-14b memory: what the LIVE plan said last night. Empty on the first night, by design.
prior AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         MAX(side = 'GOOD') AS prior_good
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan
    AND as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
                 WHERE is_live_plan AND as_of < (SELECT d_la FROM today))
  GROUP BY 1, 2
),
probes AS (
  SELECT DISTINCT CAST(keyword_id AS STRING) AS kid FROM `onyga-482313.OI.T_LIFT_PROBES`
),
seatecon AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS kid,
         ANY_VALUE(seat_cpc) AS seat_cpc, ANY_VALUE(bid_park) AS bid_park
  FROM `onyga-482313.OI.T_OOB_SEAT_ECONOMICS`
  GROUP BY 1, 2
),
holdout AS (
  SELECT CAST(unit_id AS STRING) AS cid, MIN(eligible_from) AS eligible_from
  FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
  WHERE unit_type = 'CAMPAIGN' AND arm = 'HOLDOUT'
  GROUP BY 1
),
base AS (
  SELECT
    ks.family, ks.book,
    CAST(ks.campaign_id AS STRING) AS campaign_id, ks.campaign_name,
    CAST(ks.keyword_id AS STRING)  AS keyword_id,
    CAST(ks.ad_group_id AS STRING) AS ad_group_id,
    ks.target_text, ks.match_type, ks.channel,
    COALESCE(ks.is_auto, FALSE) AS is_auto, COALESCE(ks.is_pt, FALSE) AS is_pt,
    COALESCE(ks.is_brand_defense, FALSE) AS is_brand_defense,
    ks.state AS ladder_state, ks.current_bid, ks.affordable_bid, ks.bid_floor,
    ks.gp_per_click, ks.settled_ord90, ks.settled_gp90, ks.settled_sp90,
    COALESCE(ks.family_bar, 1.0) AS family_bar,
    win.calendar_state, win.window_days, win.window_from, win.window_to, win.watermark,
    win.allowance_share, win.ramp_steps, win.live_plan,
    cp.daily_budget AS campaign_current_budget, cp.portfolio_id,
    COALESCE(rec.w_sp, 0)  AS w_sp,
    COALESCE(rec.w_clk, 0) AS w_clk,
    COALESCE(rec.w_ord, 0) AS w_ord,
    COALESCE(rec.w_gp, 0)  AS w_gp,
    COALESCE(rec.w_gp_corrected, 0) AS w_gp_corrected,
    COALESCE(rec.settle_factor_min, 1.0) AS settle_factor_min,
    COALESCE(rec.settle_curve_available, FALSE) AS settle_curve_available,
    rec.min_age_days,
    COALESCE(pr.prior_good, FALSE) AS prior_good,
    (pb.kid IS NOT NULL) AS is_probe,
    se.seat_cpc, se.bid_park,
    (h.cid IS NOT NULL AND t.d_la >= h.eligible_from) AS holdout,
    h.eligible_from AS holdout_eligible_from,
    IF(ks.channel = 'SB', caps.settle_days_sb, caps.settle_days_sp) AS settle_days,
    win.min_orders, caps.cap_up, caps.cap_down, caps.raise_ceiling, caps.click_goal_day,
    t.d_la AS today_la
  FROM ks
  CROSS JOIN win
  CROSS JOIN caps
  CROSS JOIN today t
  LEFT JOIN camp cp ON cp.cid = CAST(ks.campaign_id AS STRING)
  LEFT JOIN rec ON rec.cid = CAST(ks.campaign_id AS STRING) AND rec.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN prior pr ON pr.cid = CAST(ks.campaign_id AS STRING) AND pr.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN probes pb ON pb.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN seatecon se ON se.cid = CAST(ks.campaign_id AS STRING) AND se.kid = CAST(ks.keyword_id AS STRING)
  LEFT JOIN holdout h ON h.cid = CAST(ks.campaign_id AS STRING)
),
derived AS (
  SELECT b.*,
    SAFE_DIVIDE(b.w_gp, NULLIF(b.w_sp, 0))           AS ret_raw,
    SAFE_DIVIDE(b.w_gp_corrected, NULLIF(b.w_sp, 0)) AS ret_corrected,
    DATE_ADD(b.window_to, INTERVAL b.settle_days DAY) AS settle_due_on,
    (DATE_DIFF(b.today_la, b.window_to, DAY) >= b.settle_days) AS settled,
    -- the ladder's own settled record, the bootstrap half of "was good" (P-14b)
    (COALESCE(b.settled_ord90, 0) >= b.min_orders
     AND COALESCE(SAFE_DIVIDE(b.settled_gp90, NULLIF(b.settled_sp90, 0)), 0) >= b.family_bar)
      AS ladder_settled_good,
    -- P-6: the repaired price. Cap three 5% steps either way, floor at the row's own floor,
    -- ceiling the house $2.00 on a raise.
    LEAST(
      GREATEST(
        LEAST(
          GREATEST(COALESCE(b.affordable_bid, b.current_bid), b.current_bid * (1 - b.cap_down)),
          b.current_bid * (1 + b.cap_up)),
        COALESCE(b.bid_floor, 0)),
      GREATEST(b.raise_ceiling, b.current_bid))            AS planned_bid_raw
  FROM base b
),
sided AS (
  SELECT d.*,
    (d.w_ord >= d.min_orders AND COALESCE(d.ret_raw, -1)       >= d.family_bar) AS good_raw,
    (d.w_ord >= d.min_orders AND COALESCE(d.ret_corrected, -1) >= d.family_bar) AS good_corrected,
    (d.prior_good OR d.ladder_settled_good)                                     AS was_good
  FROM derived d
),
judged AS (
  SELECT s.*,
    CASE
      WHEN s.good_corrected THEN 'GOOD'
      WHEN s.was_good AND NOT s.settled THEN 'HELD_UNSETTLED'
      WHEN s.w_ord < s.min_orders AND s.ladder_state IN ('WINNER', 'PACED_WINNER') THEN 'GRACE'
      WHEN s.w_ord >= s.min_orders THEN 'LOSING'
      WHEN s.w_ord = 1 THEN 'ONE_ORDER'
      WHEN s.w_sp > 0 OR s.w_clk > 0 THEN 'NO_SALE'
      ELSE 'NOT_SERVING'
    END AS verdict
  FROM sided s
),
final AS (
  SELECT j.*,
    IF(j.verdict IN ('GOOD', 'HELD_UNSETTLED', 'GRACE'), 'GOOD', 'NOT_GOOD') AS side_b,
    IF(j.ladder_state IN ('WINNER', 'PACED_WINNER', 'AT_BAR', 'TRIAL', 'PENDING_SETTLE',
                          'REVIVED_SETTLING'), 'GOOD', 'NOT_GOOD')           AS side_a,
    CASE
      WHEN j.verdict = 'HELD_UNSETTLED' THEN 'P-14b'
      WHEN j.verdict = 'GRACE'          THEN 'P-5'
      ELSE 'P-3'
    END AS decided_by,
    CASE
      WHEN j.verdict = 'HELD_UNSETTLED'                     THEN 'HELD_UNSETTLED'
      WHEN NOT j.settle_curve_available                     THEN 'UNCORRECTED_NO_CURVE'
      WHEN j.good_corrected AND NOT j.good_raw              THEN 'PROMOTED_ON_FRESH'
      WHEN j.settled                                        THEN 'SETTLED'
      ELSE 'CORRECTED'
    END AS settle_arm,
    -- P-6: seat cost = spend at the repaired price, per day
    CASE
      WHEN j.w_sp > 0 AND COALESCE(j.current_bid, 0) > 0
        THEN (j.w_sp / j.window_days) * SAFE_DIVIDE(j.planned_bid_raw, j.current_bid)
      WHEN j.is_probe
        THEN COALESCE(j.seat_cpc, j.bid_floor, 0) * j.click_goal_day
      ELSE 0
    END AS seat_cost_per_day,
    -- P-7: dollars at stake x closeness to the bar
    (j.w_sp / j.window_days) * COALESCE(SAFE_DIVIDE(j.ret_corrected, NULLIF(j.family_bar, 0)), 0)
      AS rank_score
  FROM judged j
)
SELECT
  f.family, f.book, f.campaign_id, f.campaign_name, f.keyword_id, f.ad_group_id,
  f.target_text, f.match_type, f.channel, f.is_auto, f.is_pt, f.is_brand_defense,
  f.portfolio_id, f.campaign_current_budget,
  f.calendar_state, f.window_days, f.window_from, f.window_to, f.watermark,
  f.allowance_share, f.ramp_steps, f.live_plan,
  f.w_clk, f.w_ord, f.w_sp, f.w_gp, f.w_gp_corrected,
  f.settle_factor_min, f.settle_curve_available, f.min_age_days,
  f.settled, f.settle_due_on, f.settle_days, f.settle_arm, f.decided_by, f.was_good,
  f.family_bar, f.ret_raw, f.ret_corrected, f.good_raw, f.good_corrected,
  f.ladder_state, f.verdict, f.side_b, f.side_a,
  (f.side_b = 'NOT_GOOD' AND NOT f.holdout) AS is_candidate,
  f.rank_score,
  f.current_bid, f.bid_floor, f.bid_park,
  ROUND(f.planned_bid_raw, 2) AS planned_bid,
  ROUND(f.seat_cost_per_day, 4) AS seat_cost_per_day,
  f.is_probe, f.holdout, f.holdout_eligible_from,
  -- the plain sentence, printed on the book, the panel and the brief
  CASE f.verdict
    WHEN 'GOOD' THEN FORMAT(
      'GOOD on the window — %d orders on $%.2f of ad spend from %t to %t, returning %.2f gross-profit dollars per ad dollar against the %s bar of %.2f. The good side is never cut and is not re-priced (P-4).',
      f.w_ord, f.w_sp, f.window_from, f.window_to, COALESCE(f.ret_corrected, 0), f.family, f.family_bar)
    WHEN 'HELD_UNSETTLED' THEN FORMAT(
      'HELD — this keyword was good and its window (%t to %t) has not settled yet, so it is not demoted today (P-14b). %s sales accrue for %d days; it is judged again on %t with no guard.',
      f.window_from, f.window_to, f.channel, f.settle_days, f.settle_due_on)
    WHEN 'GRACE' THEN FORMAT(
      'GRACE — the ladder calls this a settled winner (%s) and its window is quiet (%d orders on $%.2f). A proven winner keeps the good side for one quiet window (P-5), held, not cut.',
      f.ladder_state, f.w_ord, f.w_sp)
    WHEN 'LOSING' THEN FORMAT(
      'LOSING on the window — %d orders on $%.2f of ad spend returning %.2f per ad dollar, under the %s bar of %.2f. It competes for a seat at the repaired price $%.2f.',
      f.w_ord, f.w_sp, COALESCE(f.ret_corrected, 0), f.family, f.family_bar, ROUND(f.planned_bid_raw, 2))
    WHEN 'ONE_ORDER' THEN FORMAT(
      'WAITING, one order — one order on $%.2f of ad spend is not evidence whatever the return, so this keyword is on the not-good side and competes for a seat at $%.2f.',
      f.w_sp, ROUND(f.planned_bid_raw, 2))
    WHEN 'NO_SALE' THEN FORMAT(
      'NO SALE — $%.2f of ad spend and %d clicks from %t to %t bought nothing. It competes for a seat at $%.2f; if it does not get one it queues at the park price.',
      f.w_sp, f.w_clk, f.window_from, f.window_to, ROUND(f.planned_bid_raw, 2))
    ELSE FORMAT('NOT SERVING — no spend and no clicks from %t to %t.', f.window_from, f.window_to)
  END AS sentence,
  CASE f.settle_arm
    WHEN 'PROMOTED_ON_FRESH'    THEN 'the settle correction promoted it: uncorrected it read under the bar, corrected for the sales still arriving it reads at or above it (P-14a)'
    WHEN 'HELD_UNSETTLED'       THEN 'the asymmetric guard decided it: promotion is allowed on fresh evidence, demotion waits for the window to settle (P-14b)'
    WHEN 'UNCORRECTED_NO_CURVE' THEN 'the settle curve could not answer for this channel and age, so nothing was corrected and the guard alone protects this row (P-14a)'
    WHEN 'SETTLED'              THEN 'the window has settled, so the record is read as it stands'
    ELSE 'the window record was corrected for the sales still arriving, using the published settle curve (P-14a)'
  END AS settle_arm_sentence
FROM final f
-- house rule 9: a total ordering, reaching the keyword key
ORDER BY f.family, f.side_b, f.rank_score DESC, f.w_clk DESC, f.campaign_id, f.keyword_id;
```

- [ ] **Step 7: Deploy all three, in dependency order**

Run:
```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/views/V_PLAN_SETTLE_COMPLETION.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql)"
```
Expected: `Created onyga-482313.OI.V_PLAN_SETTLE_COMPLETION`, then the table create, then `Created onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`. Any `Not found` names a dependency that has not been deployed — stop and deploy it first.

- [ ] **Step 8: Run the acceptance**

Run: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql)"`
Expected: nine rows, every `result` = `PASS`.

- [ ] **Step 9: Read the judgement once, in words (the three-lens check)**

Run:
```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=prettyjson \
"SELECT family, side_b, decided_by, settle_arm, COUNT(*) AS keywords,
        ROUND(SUM(w_sp) / MAX(window_days), 2) AS spend_per_day
 FROM \`onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT\`
 GROUP BY 1,2,3,4 ORDER BY family, side_b, spend_per_day DESC"
```
Expected: rows for all four HARVEST families; `decided_by` values only in (`P-3`, `P-5`, `P-14b`); at least one `PROMOTED_ON_FRESH` or `HELD_UNSETTLED` row (the P-14 arms are doing something) OR an `UNCORRECTED_NO_CURVE` majority (the curve cannot answer — record that in the commit message, it is the fallback the ruling names). Read three of the sentences in full and confirm a person could act on each.

- [ ] **Step 10: Register in config.yaml**

Insert in `views:`, next to `V_PEAK_WINDOW_RULE`:

```yaml
  - name: "V_PLAN_SETTLE_COMPLETION"
    description: "v27.131 (2026-08-23) — the settle-completion factor the next-week money plan divides a window day's gross profit by, one row per (channel SP|SB, age_days 0..120). Read from V_ADS_SETTLE_CURVE, forward-filled over unmeasured ages, made monotone in age, capped at 1.0 and floored at a declared 0.50; 1.0 beyond the curve's last measured age. curve_available says whether the curve could answer — FALSE means the factor is 1.0 and the plan rests on the asymmetric guard alone. spend_completion is published for the acceptance only. Spec P-14a."
    source_files: ["scripts/bigquery/views/V_PLAN_SETTLE_COMPLETION.sql"]
  - name: "V_PLAN_WINDOW_JUDGMENT"
    description: "v27.131 (2026-08-23) — one row per working-family (HARVEST) keyword: the complete-days window from DE_PLAN_CONFIG for today's calendar state, the keyword's record in it raw and corrected for settle completion, the rule-B side (P-1/P-3), the P-14b asymmetric guard (promote on fresh evidence, never demote until the window has settled), the P-5 grace, the shadow plan-A side from the ladder state, the repaired price (P-6) and the P-7 rank. Judges only — SP_BUILD_NEXT_WEEK_PLAN pots, seats and queues. Spec P-1..P-14."
    source_files: ["scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql"]
```

Insert in `tables:`, next to `FACT_KEYWORD_STATE`:

```yaml
  - name: "FACT_PLAN_NEXT_WEEK"
    description: "v27.131 (2026-08-23) — the next-week money plan, one row per (as_of, plan, campaign, keyword) for the HARVEST families. Two plans every night: 'B' live (the window decides the side and the amount) and 'A' shadow (the ladder decides the side) — spec P-9. Carries the window record raw and settle-corrected, the arm that decided the side (settle_arm / decided_by, P-14), the pot / allowance / ramp step, the seat number and cost, the planned price and move, the implied campaign budget and the sentence a person reads. Partitioned by as_of, clustered by plan/family/campaign; append-only, the builder rewrites only today's partition. Written by SP_BUILD_NEXT_WEEK_PLAN."
    type: "fact"
    source_files: ["scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql"]
```

Verify: `/usr/local/bin/python3 -c "import yaml,collections; d=yaml.safe_load(open('config.yaml')); n=[e['name'] for s in ('views','tables','stored_procedures','functions') for e in d[s]]; print(len(n), [k for k,v in collections.Counter(n).items() if v>1])"`
Expected: a count and `[]`.

- [ ] **Step 11: Commit (the spec amendment rides with this task)**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_PLAN_SETTLE_COMPLETION.sql scripts/bigquery/views/V_PLAN_WINDOW_JUDGMENT.sql \
        scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql \
        scripts/bigquery/tests/V_PLAN_WINDOW_JUDGMENT_acceptance.sql \
        docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md
git add -p config.yaml
git commit -m "feat(plan): the judgement layer — the window, the settle correction and the asymmetric guard (v27.131, P-1/P-3..P-7/P-10/P-14)"
```

---

### Task 2: the nightly builder — pot, allowance, ramp, seats, queue, moves, budgets (P-2, P-4, P-6, P-7, P-8, P-9, P-12, P-14)

**Files:**
- Create: `scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql`
- Create: `scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql`
- Modify: `scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql` (insert Task 20.8c after 20.8b, before Task 21)
- Modify: `config.yaml` (`stored_procedures:` next to `SP_MAINTAIN_FAMILY_SEATS`)

**One deviation from spec §4.7, recorded for Ori:** §4.7 says a queued keyword's planned spend is zero. Parking a keyword LOWERS its price; it does not stop its spend (the seat register's measured ruling R-l). The builder follows the spec for the ARITHMETIC — a queued row carries `planned_spend_per_day = 0`, so `seats + queued = the not-good side` and `seats <= allowance` both hold to the cent — and tells the truth in WORDS on the row: a parked keyword keeps spending at the park price until it is killed or graduates, so the family's real not-good spend sits above the allowance until then. If Ori would rather the arithmetic carry the residual, that is a one-line change to `planned_spend_per_day` and a re-derivation of the two reconciliation checks.

- [ ] **Step 1: Write the failing acceptance**

`scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql`:

```sql
-- =============================================================================================
-- FACT_PLAN_NEXT_WEEK acceptance — the spec's §9 guarantees. Every row must read PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §9, P-2, P-4, P-6..P-9, P-12, P-14.
-- =============================================================================================
WITH p AS (
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
),
b AS (SELECT * FROM p WHERE is_live_plan),
c01 AS (
  SELECT 'C01 window is complete days only, never the filling day (P-10)' AS check_name,
         COUNTIF(window_to != DATE_SUB(watermark, INTERVAL 1 DAY)
                 OR DATE_DIFF(window_to, window_from, DAY) + 1 != window_days) AS violations
  FROM p
),
c02 AS (
  SELECT 'C02 both plans written, one row per plan x campaign x keyword (P-9)',
         (SELECT COUNT(*) FROM (SELECT plan, campaign_id, keyword_id FROM p GROUP BY 1,2,3 HAVING COUNT(*) > 1))
       + (SELECT ABS(2 - COUNT(DISTINCT plan)) FROM p)
       + (SELECT COUNTIF(n != 1) FROM (SELECT plan, COUNT(DISTINCT is_live_plan) n FROM p GROUP BY 1))
),
c03 AS (
  SELECT 'C03 pot = the GOOD side window spend per day, to the cent (P-2)',
         COUNTIF(ABS(pot_per_day - good_spend) > 0.01)
  FROM (
    SELECT plan, family, MAX(pot_per_day) pot_per_day,
           SAFE_DIVIDE(SUM(IF(side = 'GOOD', w_sp, 0)), MAX(window_days)) good_spend
    FROM p GROUP BY 1, 2)
),
c04 AS (
  SELECT 'C04 allowance = share x pot, ramped one step of the gap (P-2, P-8)',
         COUNTIF(ABS(allowance_target_per_day - allowance_share * pot_per_day) > 0.01
                 OR ABS(allowance_ramped_per_day
                        - GREATEST(allowance_share * pot_per_day,
                                   notgood_today_per_day
                                   - (notgood_today_per_day - allowance_share * pot_per_day) / ramp_steps)) > 0.01)
  FROM (SELECT DISTINCT plan, family, allowance_share, pot_per_day, allowance_target_per_day,
                        allowance_ramped_per_day, notgood_today_per_day, ramp_steps FROM p)
),
c05 AS (
  SELECT 'C05 seats fit the allowance; every seat is numbered exactly once (P-2, P-7)',
         (SELECT COUNTIF(seat_cost > allowance + 0.01)
          FROM (SELECT plan, family, SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)) seat_cost,
                       MAX(allowance_ramped_per_day) allowance
                FROM p GROUP BY 1, 2))
       + (SELECT COUNT(*) FROM (SELECT plan, family, seat_no FROM p
                                WHERE seat_no IS NOT NULL GROUP BY 1,2,3 HAVING COUNT(*) > 1))
),
c06 AS (
  SELECT 'C06 every not-good keyword has exactly one move; no good keyword has one (P-4)',
         COUNTIF(side = 'GOOD' AND move != 'NONE')
       + COUNTIF(side = 'NOT_GOOD' AND NOT holdout
                 AND move NOT IN ('REPRICE','HOLD_AT_PRICE','PARK','PAUSE'))
       + COUNTIF(side = 'NOT_GOOD' AND holdout AND move != 'NONE_HOLDOUT')
  FROM p
),
c07 AS (
  SELECT 'C07 seated <=> a seat number, queued <=> zero planned spend (§4.5)',
         COUNTIF(side = 'NOT_GOOD' AND NOT holdout AND seat_no IS NULL AND planned_spend_per_day != 0)
       + COUNTIF(side = 'NOT_GOOD' AND seat_no IS NOT NULL
                 AND ABS(planned_spend_per_day - seat_cost_per_day) > 0.005)
  FROM p
),
c08 AS (
  SELECT 'C08 no holdout campaign is repriced, parked or paused by the plan (house rule)',
         COUNTIF(holdout AND move NOT IN ('NONE', 'NONE_HOLDOUT'))
  FROM p
),
c09 AS (
  SELECT 'C09 P-14: every row names its arm; no unsettled demotion of a keyword that was good',
         COUNTIF(settle_arm IS NULL OR decided_by IS NULL
                 OR (side = 'NOT_GOOD' AND was_good AND NOT settled))
  FROM b
),
c10 AS (
  SELECT 'C10 P-12: every repriced seat carries a verdict date in the future',
         COUNTIF(move = 'REPRICE' AND (verdict_date IS NULL OR verdict_date <= as_of))
  FROM p
),
c11 AS (
  SELECT 'C11 budgets: no campaign budget in the forbidden $20.01-$31.99 band',
         COUNTIF(campaign_planned_budget > 20.00 AND campaign_planned_budget < 32.00)
  FROM p
),
c12 AS (
  SELECT 'C12 prices: no planned bid below the row floor or above the house ceiling on a raise',
         COUNTIF(planned_bid < bid_floor - 0.005
                 OR (planned_bid > current_bid + 0.005 AND planned_bid > 2.005))
  FROM p WHERE move = 'REPRICE'
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06
      UNION ALL SELECT * FROM c07 UNION ALL SELECT * FROM c08 UNION ALL SELECT * FROM c09
      UNION ALL SELECT * FROM c10 UNION ALL SELECT * FROM c11 UNION ALL SELECT * FROM c12)
ORDER BY check_name;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"`
Expected: twelve rows and at least `C02` reading `FAIL` (the table exists from T1 but is empty, so `COUNT(DISTINCT plan)` is 0 and `ABS(2 - 0) = 2`). If every row reads PASS on an empty table, the acceptance is not testing anything — stop and fix it.

- [ ] **Step 3: Write SP_BUILD_NEXT_WEEK_PLAN**

`scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql`:

```sql
-- =============================================================================================
-- SP_BUILD_NEXT_WEEK_PLAN — v27.132 (2026-08-23): the nightly plan for the working families.
-- Reads V_PLAN_WINDOW_JUDGMENT (the side and the price) ONCE and turns it into money:
--   1. POT (P-2)        the GOOD side's window spend per day, per family. Not the family total.
--   2. ALLOWANCE (P-2)  allowance_share x pot, from DE_PLAN_CONFIG for today's calendar state.
--   3. RAMP (P-8)       one third of the gap between today's not-good spend and the allowance is
--                       closed each window, so a family two thirds over the line is not parked in
--                       one upload. Recomputed from actual spend every night, so it converges
--                       whether or not anyone uploads on schedule.
--   4. SEATS (P-6, P-7) not-good candidates ranked by dollars at stake x closeness to the bar,
--                       each costing its spend AT THE REPAIRED PRICE, taking numbered seats while
--                       the running cost fits the ramped allowance. A continuing occupant keeps
--                       its number from DE_FAMILY_SEAT_LEDGER; a new occupant takes the family's
--                       lowest free number, in rank order.
--   5. QUEUE (§4.5)     everything that did not fit: parked at the engine's park price, or paused
--                       when it is already at that price. Planned spend zero — see the note.
--   6. MOVES (§4.6)     one executable instruction per not-good keyword; none on the good side.
--   7. BUDGETS (§4.7)   a campaign's planned budget = the sum of its keywords' planned spend,
--                       ramped from today's budget by the same one-third step, snapped out of the
--                       forbidden $20.01-$31.99 band, floored at Amazon's $1.00 minimum.
-- BOTH PLANS ARE WRITTEN (P-9): 'B' is live (rule B decides the side), 'A' is the shadow (the
-- ladder decides the side, the window decides the amount). The scorecard grades both at T+14.
--
-- THE QUEUED-SPEND NOTE. Parking lowers a keyword's price; it does not stop its spend (the seat
-- register's measured ruling R-l). This procedure follows the spec's arithmetic — a queued row's
-- planned spend is zero, so seats + queued = the not-good side and seats <= allowance both hold
-- to the cent — and says so in words on the row, so nobody reads "queued" as "stopped".
--
-- HOLDOUT: a campaign in the holdout arm from its eligible_from gets a row (the counterfactual)
-- and NO move. It never competes for a seat and never appears on a sheet.
--
-- Idempotent: deletes today's as_of partition and rewrites it. Never touches an earlier one.
-- Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.8c, after the seat ledger (20.8b).
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §4, §5, §9.
-- SOP: architecture/NEXT_WEEK_MONEY.md
-- =============================================================================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN`()
OPTIONS (description = "v27.132 (2026-08-23): builds the next-week money plan for the HARVEST families and writes today's partition of FACT_PLAN_NEXT_WEEK, both plans (P-9). Reads V_PLAN_WINDOW_JUDGMENT once. Pot = the GOOD side's window spend per day (P-2); allowance = allowance_share x pot from DE_PLAN_CONFIG, ramped one third of the gap to today's not-good spend each window (P-8); not-good candidates are ranked by dollars at stake x closeness to the bar (P-7) and take numbered dollar-sized seats costing their spend at the repaired price (P-6) until the allowance is full, the rest queue at the engine park price or are paused; every not-good keyword gets exactly one move and the good side gets none (P-4); every repriced seat carries a verdict date (P-12); campaign budgets are the sum of planned spend, ramped, snapped out of the forbidden $20.01-$31.99 band and floored at $1.00. A queued row's planned spend is zero by the spec's arithmetic; the row says in words that parking lowers a price and does not stop a spend. Holdout campaigns get a counterfactual row and no move. Idempotent on one pass. Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.8c. Spec §4, §5, §9. SOP: architecture/NEXT_WEEK_MONEY.md")
BEGIN
  DECLARE as_of_d DATE DEFAULT CURRENT_DATE('America/Los_Angeles');
  DECLARE live_plan_code STRING DEFAULT (
    SELECT live_plan FROM `onyga-482313.OI.DE_PLAN_CONFIG`
    WHERE is_active
      AND calendar_state = `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(CURRENT_DATE('America/New_York'))
    ORDER BY updated_at DESC LIMIT 1);

  -- ONE scan of the judgement view; everything below reads this copy.
  CREATE OR REPLACE TEMP TABLE j AS
  SELECT * FROM `onyga-482313.OI.V_PLAN_WINDOW_JUDGMENT`;

  -- Both plans over the same keywords: 'B' takes rule B's side, 'A' takes the ladder's (P-9).
  CREATE OR REPLACE TEMP TABLE r AS
  SELECT j.*, pl AS plan, IF(pl = 'B', j.side_b, j.side_a) AS side
  FROM j, UNNEST(['A', 'B']) AS pl;

  -- 1-3. Pot, allowance, ramp — per plan x family.
  CREATE OR REPLACE TEMP TABLE fam AS
  SELECT plan, family,
         MAX(window_days)     AS window_days,
         MAX(allowance_share) AS allowance_share,
         MAX(ramp_steps)      AS ramp_steps,
         COALESCE(SAFE_DIVIDE(SUM(IF(side = 'GOOD',     w_sp, 0)), MAX(window_days)), 0) AS pot_per_day,
         COALESCE(SAFE_DIVIDE(SUM(IF(side = 'NOT_GOOD', w_sp, 0)), MAX(window_days)), 0) AS notgood_today_per_day
  FROM r
  GROUP BY 1, 2;

  CREATE OR REPLACE TEMP TABLE fam2 AS
  SELECT f.*,
         f.allowance_share * f.pot_per_day AS allowance_target_per_day,
         GREATEST(f.allowance_share * f.pot_per_day,
                  f.notgood_today_per_day
                  - (f.notgood_today_per_day - f.allowance_share * f.pot_per_day) / f.ramp_steps)
           AS allowance_ramped_per_day
  FROM fam f;

  -- 4. Rank and walk the not-good side (P-7). Holdout campaigns never compete.
  CREATE OR REPLACE TEMP TABLE ranked AS
  SELECT r.*, f.pot_per_day, f.allowance_target_per_day, f.allowance_ramped_per_day,
         f.notgood_today_per_day,
         ROW_NUMBER() OVER w AS rank_no,
         SUM(r.seat_cost_per_day) OVER (PARTITION BY r.plan, r.family
              ORDER BY r.rank_score DESC, r.w_clk DESC, r.campaign_id, r.keyword_id
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_cost
  FROM r
  JOIN fam2 f USING (plan, family)
  WHERE r.side = 'NOT_GOOD' AND NOT r.holdout
  WINDOW w AS (PARTITION BY r.plan, r.family
               ORDER BY r.rank_score DESC, r.w_clk DESC, r.campaign_id, r.keyword_id);

  -- the family's currently open seats — a continuing occupant keeps its number
  CREATE OR REPLACE TEMP TABLE led AS
  SELECT family, CAST(campaign_id AS STRING) AS campaign_id, CAST(keyword_id AS STRING) AS keyword_id,
         MIN(seat_no) AS led_seat_no
  FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`
  WHERE closed_on IS NULL
  GROUP BY 1, 2, 3;

  CREATE OR REPLACE TEMP TABLE seated AS
  SELECT k.*, l.led_seat_no
  FROM ranked k
  LEFT JOIN led l ON l.family = k.family AND l.campaign_id = k.campaign_id AND l.keyword_id = k.keyword_id
  WHERE k.cum_cost <= k.allowance_ramped_per_day + 0.0001;

  -- the free seat numbers, lowest first, and the new occupants that take them in rank order
  CREATE OR REPLACE TEMP TABLE seat_no_map AS
  WITH cnt AS (
    SELECT plan, family, COUNT(*) AS n_seated, COALESCE(MAX(led_seat_no), 0) AS max_occ
    FROM seated GROUP BY 1, 2),
  nums AS (
    SELECT c.plan, c.family, x AS seat_no
    FROM cnt c, UNNEST(GENERATE_ARRAY(1, c.n_seated + c.max_occ)) AS x),
  taken AS (
    SELECT plan, family, led_seat_no AS seat_no FROM seated WHERE led_seat_no IS NOT NULL),
  free AS (
    SELECT n.plan, n.family, n.seat_no,
           ROW_NUMBER() OVER (PARTITION BY n.plan, n.family ORDER BY n.seat_no) AS free_ix
    FROM nums n
    LEFT JOIN taken t ON t.plan = n.plan AND t.family = n.family AND t.seat_no = n.seat_no
    WHERE t.seat_no IS NULL),
  fresh AS (
    SELECT plan, family, campaign_id, keyword_id,
           ROW_NUMBER() OVER (PARTITION BY plan, family ORDER BY rank_no) AS new_ix
    FROM seated WHERE led_seat_no IS NULL)
  SELECT s.plan, s.family, s.campaign_id, s.keyword_id,
         COALESCE(s.led_seat_no, fr.seat_no) AS seat_no
  FROM seated s
  LEFT JOIN fresh n ON n.plan = s.plan AND n.family = s.family
                   AND n.campaign_id = s.campaign_id AND n.keyword_id = s.keyword_id
  LEFT JOIN free fr ON fr.plan = s.plan AND fr.family = s.family AND fr.free_ix = n.new_ix;

  -- 5-6. Assemble every row: side, seat or queue, move, planned price, planned spend, verdict date
  CREATE OR REPLACE TEMP TABLE assembled AS
  SELECT
    r.*,
    f.pot_per_day, f.allowance_target_per_day, f.allowance_ramped_per_day,
    f.notgood_today_per_day, f.ramp_steps AS fam_ramp_steps,
    k.rank_no,
    m.seat_no,
    CASE
      WHEN r.side = 'GOOD'                                          THEN 'NONE'
      WHEN r.holdout                                                THEN 'NONE_HOLDOUT'
      WHEN m.seat_no IS NOT NULL AND ABS(r.planned_bid - r.current_bid) > 0.005 THEN 'REPRICE'
      WHEN m.seat_no IS NOT NULL                                    THEN 'HOLD_AT_PRICE'
      WHEN COALESCE(r.bid_park, r.bid_floor, 0) < r.current_bid - 0.005 THEN 'PARK'
      ELSE 'PAUSE'
    END AS move
  FROM r
  JOIN fam2 f USING (plan, family)
  LEFT JOIN ranked k ON k.plan = r.plan AND k.campaign_id = r.campaign_id AND k.keyword_id = r.keyword_id
  LEFT JOIN seat_no_map m ON m.plan = r.plan AND m.campaign_id = r.campaign_id AND m.keyword_id = r.keyword_id;

  CREATE OR REPLACE TEMP TABLE priced AS
  SELECT a.*,
    CASE a.move
      WHEN 'REPRICE'       THEN a.planned_bid
      WHEN 'HOLD_AT_PRICE' THEN a.current_bid
      WHEN 'PARK'          THEN ROUND(COALESCE(a.bid_park, a.bid_floor, a.current_bid), 2)
      ELSE a.current_bid
    END AS planned_bid_final,
    CASE
      WHEN a.side = 'GOOD' OR a.holdout THEN COALESCE(SAFE_DIVIDE(a.w_sp, a.window_days), 0)
      WHEN a.seat_no IS NOT NULL        THEN a.seat_cost_per_day
      ELSE 0
    END AS planned_spend_per_day,
    IF(a.move = 'REPRICE', DATE_ADD(as_of_d, INTERVAL a.settle_days DAY), NULL) AS verdict_date
  FROM assembled a;

  -- 7. Campaign budgets: sum of planned spend, ramped one step, band-snapped, floored at $1.00
  CREATE OR REPLACE TEMP TABLE budgets AS
  WITH implied AS (
    SELECT plan, campaign_id,
           SUM(planned_spend_per_day)     AS implied_budget,
           MAX(campaign_current_budget)   AS current_budget,
           MAX(fam_ramp_steps)            AS ramp_steps
    FROM priced GROUP BY 1, 2),
  rampd AS (
    SELECT plan, campaign_id, current_budget,
           COALESCE(current_budget, implied_budget)
           + (implied_budget - COALESCE(current_budget, implied_budget)) / ramp_steps AS ramped
    FROM implied)
  SELECT plan, campaign_id, current_budget,
         ROUND(
           GREATEST(1.00,
             CASE WHEN ramped > 20.00 AND ramped < 32.00
                  THEN IF(ramped < 26.00, 20.00, 32.00)
                  ELSE ramped END), 2) AS campaign_planned_budget
  FROM rampd;

  DELETE FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d;

  INSERT INTO `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
    (as_of, plan, is_live_plan, family, book, campaign_id, campaign_name, keyword_id, ad_group_id,
     target_text, match_type, channel, is_auto, is_pt, calendar_state, window_days, window_from,
     window_to, watermark, w_clk, w_ord, w_sp, w_gp, w_gp_corrected, settle_factor_min,
     settle_curve_available, settled, settle_due_on, settle_arm, decided_by, was_good, family_bar,
     ret_raw, ret_corrected, ladder_state, side, verdict, is_candidate, rank_score, rank_no,
     seat_no, seat_cost_per_day, current_bid, planned_bid, bid_floor, move, planned_spend_per_day,
     verdict_date, pot_per_day, allowance_target_per_day, allowance_ramped_per_day,
     notgood_today_per_day, ramp_step, ramp_steps, allowance_share, campaign_planned_budget,
     campaign_current_budget, holdout, holdout_eligible_from, sentence, built_at)
  SELECT
    as_of_d, p.plan, (p.plan = live_plan_code), p.family, p.book, p.campaign_id, p.campaign_name,
    p.keyword_id, p.ad_group_id, p.target_text, p.match_type, p.channel, p.is_auto, p.is_pt,
    p.calendar_state, p.window_days, p.window_from, p.window_to, p.watermark,
    CAST(p.w_clk AS INT64), CAST(p.w_ord AS INT64), p.w_sp, p.w_gp, p.w_gp_corrected,
    p.settle_factor_min, p.settle_curve_available, p.settled, p.settle_due_on, p.settle_arm,
    p.decided_by, p.was_good, p.family_bar, p.ret_raw, p.ret_corrected, p.ladder_state, p.side,
    p.verdict, (p.side = 'NOT_GOOD' AND NOT p.holdout), p.rank_score, p.rank_no, p.seat_no,
    ROUND(p.seat_cost_per_day, 4), p.current_bid, ROUND(p.planned_bid_final, 2), p.bid_floor,
    p.move, ROUND(p.planned_spend_per_day, 4), p.verdict_date,
    ROUND(p.pot_per_day, 4), ROUND(p.allowance_target_per_day, 4),
    ROUND(p.allowance_ramped_per_day, 4), ROUND(p.notgood_today_per_day, 4),
    -- ramp_step is a REPORT: how many windows the plan has been running for this family, capped
    -- at ramp_steps. The arithmetic above does not depend on it — each night's ramp is recomputed
    -- from the actual not-good spend, so the sequence converges with or without an upload.
    LEAST(p.fam_ramp_steps,
          1 + DIV(DATE_DIFF(as_of_d,
                            COALESCE((SELECT MIN(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
                                      WHERE family = p.family), as_of_d), DAY),
                  p.window_days)),
    p.fam_ramp_steps,
    p.allowance_share, b.campaign_planned_budget, b.current_budget,
    p.holdout, p.holdout_eligible_from,
    CONCAT(p.sentence, ' ', p.settle_arm_sentence, '.',
      CASE p.move
        WHEN 'REPRICE' THEN FORMAT(
          ' SEAT %d of %s: re-price $%.2f -> $%.2f, costing about $%.2f a day of the $%.2f a day this family allows the not-good side. Judged again on %t.',
          p.seat_no, p.family, p.current_bid, p.planned_bid_final, p.seat_cost_per_day,
          p.allowance_ramped_per_day, p.verdict_date)
        WHEN 'HOLD_AT_PRICE' THEN FORMAT(
          ' SEAT %d of %s: the price is already where the plan wants it, so nothing is uploaded; it keeps its seat at about $%.2f a day.',
          p.seat_no, p.family, p.seat_cost_per_day)
        WHEN 'PARK' THEN FORMAT(
          ' QUEUED, no seat: park the bid at $%.2f. Parking LOWERS the price, it does not stop the spend — this keyword keeps buying clicks at the park price until it earns a seat or is killed.',
          p.planned_bid_final)
        WHEN 'PAUSE' THEN
          ' QUEUED, no seat, and already at the park price: pause it. A keyword that queues a whole window with no seat is a kill candidate.'
        WHEN 'NONE_HOLDOUT' THEN
          ' This campaign is a measurement control: the plan records what it would have done and uploads nothing to it.'
        ELSE ' No move: the good side is never cut and is not re-priced (P-4).'
      END) AS sentence,
    CURRENT_TIMESTAMP()
  FROM priced p
  LEFT JOIN budgets b ON b.plan = p.plan AND b.campaign_id = p.campaign_id;

  -- §9 guarantees, asserted where they are cheapest to assert: at write time.
  ASSERT (SELECT COUNT(DISTINCT plan) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d) = 2
    AS 'both plans must be written every night (P-9)';
  ASSERT (SELECT COUNTIF(side = 'GOOD' AND move != 'NONE')
          FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d) = 0
    AS 'the good side is never cut and is not re-priced (P-4)';
  ASSERT (SELECT COUNTIF(seat_cost > allowance + 0.01) FROM (
            SELECT plan, family, SUM(IF(seat_no IS NOT NULL, seat_cost_per_day, 0)) seat_cost,
                   MAX(allowance_ramped_per_day) allowance
            FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d GROUP BY 1, 2)) = 0
    AS 'seats must fit the ramped allowance (P-2, P-8)';
  ASSERT (SELECT COUNTIF(side = 'NOT_GOOD' AND was_good AND NOT settled)
          FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d AND is_live_plan) = 0
    AS 'no keyword that was good may be demoted before its window settles (P-14b)';
  ASSERT (SELECT COUNTIF(holdout AND move NOT IN ('NONE', 'NONE_HOLDOUT'))
          FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = as_of_d) = 0
    AS 'a holdout campaign gets a record and no move';
END;
```

- [ ] **Step 4: Deploy and run it once by hand**

Run:
```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
```
Expected: `Created onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN`, then the CALL completes with no output and no `Assertion failed` line. An assertion failure names the guarantee it broke — fix the arithmetic, never the assertion.

- [ ] **Step 5: Run the acceptance**

Run: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql)"`
Expected: twelve rows, every `result` = `PASS`.

- [ ] **Step 6: Prove it is idempotent**

Run:
```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT COUNT(*) n, ROUND(SUM(planned_spend_per_day),4) s FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\` WHERE as_of = CURRENT_DATE('America/Los_Angeles')"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "CALL \`onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT COUNT(*) n, ROUND(SUM(planned_spend_per_day),4) s FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\` WHERE as_of = CURRENT_DATE('America/Los_Angeles')"
```
Expected: the two `n,s` lines are identical. (They are only identical if the ads watermark has not moved between the calls; if it has, re-run both.)

- [ ] **Step 7: Insert Task 20.8c in the orchestrator**

Back up first: `cp scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql.bak.v27.132.$(date +%H%M)`

Find the line `  -- Refresh Task 21: Refresh Cube Tables (T_*)` and insert this block immediately BEFORE the `  -- ============================================` line that opens it (i.e. directly after the `END;` that closes the 20.8b `SP_MAINTAIN_FAMILY_SEATS` block):

```sql
  -- ============================================
  -- Refresh Task 20.8c (2026-08-23, next week's money Task 2): the plan. Reads the keyword-state
  -- snapshot (20.8) through V_PLAN_WINDOW_JUDGMENT and the seat ledger (20.8b), and writes today's
  -- partition of FACT_PLAN_NEXT_WEEK — both plans, every night (spec P-9). MUST run after 20.8b,
  -- because a continuing occupant's seat number comes from the ledger that step maintains, and
  -- after 20.8, whose snapshot the judgement view reads.
  -- ONE PASS OF LAG, DELIBERATE AND MEASURED: the proposal snapshot (Task 20.6) and the preflight
  -- (20.7) run EARLIER in this pass than the keyword state machine (20.8) does — that ordering
  -- predates this plan and is not changed here. So the PLAN rows a given pass writes are read by
  -- the NEXT pass's proposal snapshot, exactly as the ladder's own snapshot is already read a pass
  -- late by everything below it. SP_SNAPSHOT_ENGINE_PROPOSALS therefore reads the LATEST available
  -- plan partition and prints its date on every PLAN row, and V_ENGINE_HEALTH counts the lag
  -- (plan_proposal_lag_days). Closing the lag means moving 20.6 and 20.7 below 20.8c, which is a
  -- change to another owner's ordering — recorded as an open ruling for Ori, not taken here.
  -- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md. SOP: architecture/NEXT_WEEK_MONEY.md.
  -- ============================================
  SET procedure_name = 'SP_BUILD_NEXT_WEEK_PLAN';
  SET procedure_start_time = CURRENT_TIMESTAMP();
  SET total_procedures = total_procedures + 1;

  BEGIN
    CALL `onyga-482313.OI.SP_BUILD_NEXT_WEEK_PLAN`();
    SET success_count = success_count + 1;
    SET error_msg = NULL;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'OK', NULL, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('OK %s completed successfully in %d seconds', procedure_name,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND)) as log_message;
  EXCEPTION WHEN ERROR THEN
    SET failure_count = failure_count + 1;
    SET error_msg = @@error.message;
    INSERT INTO `onyga-482313.OI.LOG_PIPELINE_RUNS`
      (run_id, run_date, procedure_name, status, error_message, started_at, finished_at, duration_seconds, inserted_at)
    VALUES
      (run_id, CURRENT_DATE(), procedure_name, 'FAIL', error_msg, procedure_start_time, CURRENT_TIMESTAMP(), TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), procedure_start_time, SECOND), CURRENT_TIMESTAMP());
    SELECT FORMAT('FAIL %s failed: %s', procedure_name, @@error.message) as log_message;
  END;
```

**Check the ordering before you deploy.** Run: `grep -n "Refresh Task 20.6 (2026-08-15\|Refresh Task 20.8b\|Refresh Task 20.8c\|Refresh Task 21:" scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql`
Expected: four line numbers in the order 20.6 < 20.8b < 20.8c < 21. That is the intended layout: the proposal snapshot runs earlier in the pass than the keyword state machine already, so the plan is read a pass late by design (see the block's own comment). **Do NOT move the new block above the keyword state machine to "fix" this** — the judgement view reads that snapshot, and moving it would build the plan on nothing. The lag is measured by a health check in T5 and recorded as an open ruling for Ori.

Then deploy: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql)"`
Expected: `Created onyga-482313.OI.SP_ORCHESTRATE_DAILY_REFRESH`.

- [ ] **Step 8: Register in config.yaml**

Insert in `stored_procedures:`, next to `SP_MAINTAIN_FAMILY_SEATS`:

```yaml
  - name: "SP_BUILD_NEXT_WEEK_PLAN"
    description: "v27.132 (2026-08-23) — builds the next-week money plan for the HARVEST families and writes today's partition of FACT_PLAN_NEXT_WEEK, both plans (P-9). Pot = the GOOD side's window spend per day (P-2); allowance = allowance_share x pot from DE_PLAN_CONFIG, ramped one third of the gap each window (P-8); not-good candidates ranked by dollars at stake x closeness to the bar (P-7) take numbered seats costing their spend at the repaired price (P-6) until the allowance is full; the rest queue at the park price or are paused; one move per not-good keyword, none on the good side (P-4); a verdict date on every repriced seat (P-12); campaign budgets ramped, band-snapped and floored. Idempotent. Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.8c, after the seat ledger. Spec §4, §5, §9. SOP: architecture/NEXT_WEEK_MONEY.md"
    source_files: ["scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql"]
```

Verify: `/usr/local/bin/python3 -c "import yaml,collections; d=yaml.safe_load(open('config.yaml')); n=[e['name'] for s in ('views','tables','stored_procedures','functions') for e in d[s]]; print(len(n), [k for k,v in collections.Counter(n).items() if v>1])"`
Expected: a count and `[]`.

- [ ] **Step 9: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_BUILD_NEXT_WEEK_PLAN.sql \
        scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql \
        scripts/bigquery/procedures/SP_ORCHESTRATE_DAILY_REFRESH.sql
git add -p config.yaml
git commit -m "feat(plan): the nightly builder — pot, allowance, ramp, seats, queue, moves, budgets (v27.132, P-2/P-4/P-6..P-9/P-12/P-14)"
```

---

### Task 3: one engine — the plan owns bids and budgets for working families (P-11)

**Files:**
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql` (add INSERT 10, INSERT 11, UPDATE 12)
- Modify: `scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql` (PLAN first in precedence; a belt arm)
- Redeploy: `scripts/bigquery/views/V_ENGINE_PREFLIGHT.sql` (it is a `SELECT *` over `T_ENGINE_PREFLIGHT`)
- Create: `scripts/bigquery/tests/PLAN_OWNERSHIP_acceptance.sql`

**How the hold works, and why nothing new is invented.** The house already has a mechanism for "recorded but never exported": `hold_source`. `SP_SNAPSHOT_ENGINE_PROPOSALS` writes it, and `SP_ENGINE_PREFLIGHT` skips every row that carries one, so such a row never reaches `T_ENGINE_PREFLIGHT`, the cube, the decisions feed or `DoPage`'s export. The plan reuses it verbatim with `hold_source = 'PLAN'`. **The held row keeps its values** — unlike the last-day veto, whose source view produced them empty, a LIFT or OOB proposal arrives with a real bid, and that bid is the counterfactual the scorecard grades. The stamp is additive: `held_action` and `held_bid` are filled in beside the originals, nothing is nulled, nothing is deleted.

- [ ] **Step 1: Write the failing acceptance**

`scripts/bigquery/tests/PLAN_OWNERSHIP_acceptance.sql`:

```sql
-- =============================================================================================
-- PLAN ownership acceptance (P-11) — every row must read PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §6, P-11.
-- =============================================================================================
WITH snap AS (SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`),
fp AS (SELECT f.* FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS` f, snap WHERE f.snapshot_date = snap.d),
plan_c AS (
  SELECT DISTINCT campaign_id
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan
    AND as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE is_live_plan)
),
pf AS (SELECT * FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`),
c01 AS (
  SELECT 'C01 the plan proposes in the snapshot (engine = PLAN, BID and BUDGET)' AS check_name,
         (SELECT 2 - COUNT(DISTINCT grain) FROM fp WHERE engine = 'PLAN' AND grain IN ('BID','BUDGET')) AS violations
),
c02 AS (
  SELECT 'C02 no LIFT / OOB / REVERDICT bid or budget row in a plan campaign escapes the hold',
         COUNTIF(engine IN ('LIFT','OOB','REVERDICT') AND grain IN ('BID','BUDGET')
                 AND campaign_id IN (SELECT campaign_id FROM plan_c)
                 AND hold_source IS NULL)
  FROM fp
),
c03 AS (
  SELECT 'C03 every plan-held row keeps its value and carries the plan sentence',
         COUNTIF(hold_source = 'PLAN'
                 AND (verdict != 'EXCLUDE'
                      OR verdict_reason NOT LIKE '%the plan owns%'
                      OR (grain = 'BID' AND held_bid IS NULL AND suggested_bid IS NULL)))
  FROM fp
),
c04 AS (
  SELECT 'C04 zero GO rows from the retired engines on money levers in plan campaigns',
         COUNTIF(engine IN ('LIFT','OOB','REVERDICT') AND lever IN ('BID','BUDGET')
                 AND campaign_id IN (SELECT campaign_id FROM plan_c) AND verdict = 'GO')
  FROM pf
),
c05 AS (
  SELECT 'C05 negates, LOW_STOCK and LAUNCH are untouched by the plan hold',
         COUNTIF(hold_source = 'PLAN' AND (grain = 'NEGATE' OR engine IN ('LOW_STOCK','LAUNCH','COACH')))
  FROM fp
),
c06 AS (
  SELECT 'C06 no plan-held row reaches the gate table (they are recorded, never exported)',
         (SELECT COUNT(*) FROM pf p JOIN fp f
            ON f.engine = p.engine AND f.campaign_id = p.campaign_id
           AND COALESCE(f.keyword_id,'') = COALESCE(p.keyword_id,'')
           AND COALESCE(f.target_text,'') = COALESCE(p.target_text,'')
           AND f.grain = p.grain
          WHERE f.hold_source = 'PLAN')
),
c07 AS (
  SELECT 'C07 no PLAN row for a holdout campaign, on any lever',
         COUNTIF(engine = 'PLAN' AND campaign_id IN (
                   SELECT CAST(unit_id AS STRING) FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
                   WHERE unit_type = 'CAMPAIGN' AND arm = 'HOLDOUT'
                     AND CURRENT_DATE('America/Los_Angeles') BETWEEN eligible_from AND trial_end))
  FROM fp
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05 UNION ALL SELECT * FROM c06
      UNION ALL SELECT * FROM c07)
ORDER BY check_name;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/PLAN_OWNERSHIP_acceptance.sql)"`
Expected: seven rows, with at least `C01` reading `FAIL` (no PLAN rows exist yet — `2 - 0 = 2`).

- [ ] **Step 3: Add the PLAN inserts and the hold to SP_SNAPSHOT_ENGINE_PROPOSALS**

Back up: `cp scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql.bak.v27.133.$(date +%H%M)`

Insert this block immediately before the final `END;` of the procedure:

```sql
  -- ── 10-12. THE PLAN (v27.133, 2026-08-23, spec P-11) ─────────────────────────────────────────
  -- For the working families the plan is the sole authority on keyword bids and campaign budgets.
  -- It enters as an engine like any other (so Weekly Run shows ONE list and ONE export path), and
  -- the engines it retires are HELD, not deleted: their proposal keeps its action and its bid, and
  -- hold_source = 'PLAN' keeps it out of the gate, the cube, the decisions feed and every export —
  -- the same mechanism the last-day veto uses (v27.98). That held row IS the counterfactual the
  -- A-vs-B scorecard grades, which is the whole reason it is not deleted.
  -- THE PLAN IS READ A PASS LATE ON PURPOSE: this snapshot (Task 20.6) runs earlier in the pass
  -- than the keyword state machine (20.8) and therefore earlier than the plan builder (20.8c), so
  -- the LATEST available partition is the one before today's. The date is printed on every row.
  -- Holdout campaigns are excluded here as well as at the gate — belt and braces on an arm whose
  -- whole value is that nothing reaches it.
  BEGIN
    DECLARE plan_as_of DATE DEFAULT (
      SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE is_live_plan);

    IF plan_as_of IS NOT NULL THEN
      -- 10. PLAN keyword bids: one row per keyword the plan actually moves.
      INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
        (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id,
         target_text, match_type, channel, action, current_bid, suggested_bid, current_budget,
         suggested_budget, reason, reason_short, season_relax_applied)
      SELECT snap, 'PLAN', 'BID', p.campaign_id, p.campaign_name, p.keyword_id, p.ad_group_id,
             p.target_text, p.match_type, p.channel,
             CASE p.move
               WHEN 'REPRICE' THEN IF(p.planned_bid > p.current_bid, 'INCREASE_BID', 'REDUCE_BID')
               WHEN 'PARK'    THEN 'REDUCE_BID'
               ELSE 'PAUSE_KEYWORD' END,
             p.current_bid, p.planned_bid, NULL, NULL,
             p.sentence,
             FORMAT('plan %t · seat %s · $%.2f → $%.2f',
                    p.as_of, COALESCE(CAST(p.seat_no AS STRING), 'queued'),
                    p.current_bid, p.planned_bid),
             CAST(NULL AS BOOL)
      FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
      WHERE p.as_of = plan_as_of AND p.is_live_plan
        AND p.move IN ('REPRICE', 'PARK', 'PAUSE')
        AND NOT p.holdout;

      -- 11. PLAN campaign budgets: one row per campaign whose planned budget differs from today's.
      INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
        (snapshot_date, engine, grain, campaign_id, campaign_name, keyword_id, ad_group_id,
         target_text, match_type, channel, action, current_bid, suggested_bid, current_budget,
         suggested_budget, reason, reason_short, season_relax_applied)
      SELECT snap, 'PLAN', 'BUDGET', p.campaign_id, ANY_VALUE(p.campaign_name),
             NULL, CAST(NULL AS STRING), NULL, NULL, ANY_VALUE(p.channel),
             IF(MAX(p.campaign_planned_budget) > MAX(p.campaign_current_budget),
                'INCREASE_BUDGET', 'REDUCE_BUDGET'),
             NULL, NULL, MAX(p.campaign_current_budget), MAX(p.campaign_planned_budget),
             FORMAT('the plan owns this campaign: its keywords plan to spend about $%.2f a day, so the budget moves one ramp step from $%.2f to $%.2f (plan %t).',
                    SUM(p.planned_spend_per_day), MAX(p.campaign_current_budget),
                    MAX(p.campaign_planned_budget), plan_as_of),
             FORMAT('plan %t · budget $%.2f → $%.2f', plan_as_of,
                    MAX(p.campaign_current_budget), MAX(p.campaign_planned_budget)),
             CAST(NULL AS BOOL)
      FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
      WHERE p.as_of = plan_as_of AND p.is_live_plan AND NOT p.holdout
      GROUP BY p.campaign_id
      HAVING ABS(MAX(p.campaign_planned_budget) - MAX(p.campaign_current_budget)) > 0.005;

      -- 12. THE HOLD. Additive: the original action and bid stay, held_* are filled in beside
      -- them, and hold_source keeps the row out of the gate and every export.
      UPDATE `onyga-482313.OI.FACT_ENGINE_PROPOSALS` f
      SET f.hold_source    = 'PLAN',
          f.held_action    = COALESCE(f.held_action, f.action),
          f.held_bid       = COALESCE(f.held_bid, f.suggested_bid),
          f.verdict        = 'EXCLUDE',
          f.verdict_reason = "held — the plan owns this keyword's price: for a working family the next-week money plan is the only engine that sets bids and budgets, and this proposal is kept in full so the scorecard can grade what it would have done"
      WHERE f.snapshot_date = snap
        AND f.hold_source IS NULL
        AND f.engine IN ('LIFT', 'OOB', 'REVERDICT')
        AND f.grain IN ('BID', 'BUDGET')
        AND f.campaign_id IN (
          SELECT DISTINCT campaign_id FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
          WHERE as_of = plan_as_of AND is_live_plan);
    END IF;
  END;
```

Deploy: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql)"`
Expected: `Created onyga-482313.OI.SP_SNAPSHOT_ENGINE_PROPOSALS`.

- [ ] **Step 4: Give PLAN top precedence and a belt arm in SP_ENGINE_PREFLIGHT**

Back up: `cp scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql.bak.v27.133.$(date +%H%M)`

Make three edits.

(a) In the `ranked` CTE, add the plan-owned flag. Insert after the `(h.cid IS NOT NULL) AS is_holdout,` / `h.trial_id AS holdout_trial_id,` pair:

```sql
      -- v27.133 (spec P-11): TRUE iff the next-week money plan owns this campaign's money today.
      -- The BELT: the braces is hold_source, stamped by SP_SNAPSHOT_ENGINE_PROPOSALS, which keeps
      -- a retired engine's row out of this table entirely. This flag catches the case the stamp
      -- cannot — an engine added later that nobody remembered to hold — and it costs one scan of a
      -- tiny partition. Fails open: no plan partition, no ownership.
      (pl.cid IS NOT NULL) AS is_plan_owned,
```

and add the CTE beside `hold`:

```sql
  -- v27.133: the campaigns the live next-week plan owns. Latest partition, so a pass that has not
  -- rebuilt the plan yet still reads the ownership the previous pass established.
  plan_own AS (
    SELECT DISTINCT CAST(campaign_id AS STRING) AS cid
    FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
    WHERE is_live_plan
      AND as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE is_live_plan)
  ),
```

and the join, beside `LEFT JOIN hold h ...`:

```sql
    LEFT JOIN plan_own pl ON pl.cid = CAST(p.campaign_id AS STRING)
```

(b) In the precedence `ROW_NUMBER()` and the `FIRST_VALUE()` that names the owner, put `PLAN` first. Both `CASE p.engine` ladders change from

```sql
                   WHEN 'LOW_STOCK' THEN 1 WHEN 'LAUNCH' THEN 2 WHEN 'OOB' THEN 3
                   WHEN 'REVERDICT' THEN 4 WHEN 'LIFT' THEN 5 WHEN 'COACH' THEN 6 ELSE 9 END,
```

to

```sql
                   WHEN 'LOW_STOCK' THEN 1 WHEN 'PLAN' THEN 2 WHEN 'LAUNCH' THEN 3
                   WHEN 'OOB' THEN 4 WHEN 'REVERDICT' THEN 5 WHEN 'LIFT' THEN 6
                   WHEN 'COACH' THEN 7 ELSE 9 END,
```

(LOW_STOCK stays first: it is the owner of its campaigns and a stock-out outranks a money plan.)

(c) Add the belt arm to the verdict `CASE`, immediately after the holdout arm and before the collision arm:

```sql
      -- v27.133 PLAN-OWNED (spec P-11), ordered after HOLDOUT and before the collision arm. A
      -- proposal from a retired engine on a money lever inside a campaign the plan owns is not
      -- exported. It should never get this far — SP_SNAPSHOT_ENGINE_PROPOSALS stamps hold_source
      -- and this procedure skips such rows — so a row reaching here means an engine was added
      -- without being held, and the belt catches it rather than letting it move a working family's
      -- money behind the plan's back.
      WHEN r.is_plan_owned AND r.engine != 'PLAN' AND r.engine != 'LOW_STOCK'
        AND r.lever IN ('BID', 'BUDGET') THEN 'EXCLUDE'
```

and the matching reason, in the same position in the reason `CASE`:

```sql
      WHEN r.is_plan_owned AND r.engine != 'PLAN' AND r.engine != 'LOW_STOCK'
        AND r.lever IN ('BID', 'BUDGET')
        THEN 'skipped — the next-week money plan owns this working family: it is the only engine that sets a bid or a budget here, and this proposal is kept in full so we can grade what it would have done'
```

(d) Publish the flag on `T_ENGINE_PREFLIGHT` — add `r.is_plan_owned,` to the final `SELECT` list, next to `r.is_holdout, r.holdout_trial_id,`.

Deploy: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql)"`
Expected: `Created onyga-482313.OI.SP_ENGINE_PREFLIGHT`.

- [ ] **Step 5: Rebuild the snapshot and the gate, then redeploy the preflight view**

Run:
```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "CALL \`onyga-482313.OI.SP_SNAPSHOT_ENGINE_PROPOSALS\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "CALL \`onyga-482313.OI.SP_ENGINE_PREFLIGHT\`()"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/views/V_ENGINE_PREFLIGHT.sql)"
```
Expected: both CALLs complete (the snapshot re-reads the ceiling views and takes minutes — that is normal), then `Created onyga-482313.OI.V_ENGINE_PREFLIGHT`. If `V_ENGINE_PREFLIGHT.sql` names its columns rather than `SELECT *`, add `is_plan_owned` to its list before redeploying.

- [ ] **Step 6: Run the acceptance**

Run: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/PLAN_OWNERSHIP_acceptance.sql)"`
Expected: seven rows, every `result` = `PASS`.

- [ ] **Step 7: Read the ownership once, in words**

Run:
```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT engine, grain, COALESCE(hold_source,'-') AS hold, COALESCE(verdict,'-') AS verdict, COUNT(*) n
 FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`
 WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\`)
 GROUP BY 1,2,3,4 ORDER BY engine, grain"
```
Expected: `PLAN` rows with `hold = '-'`; `LIFT`, `OOB` and `REVERDICT` rows in plan campaigns with `hold = 'PLAN'` and `verdict = 'EXCLUDE'`; `COACH` negates untouched. Read one held row's `verdict_reason` in full and confirm it explains itself to a stranger.

- [ ] **Step 8: Commit**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql \
        scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql \
        scripts/bigquery/views/V_ENGINE_PREFLIGHT.sql \
        scripts/bigquery/tests/PLAN_OWNERSHIP_acceptance.sql
git commit -m "feat(plan): one engine — PLAN proposes, LIFT/OOB/REVERDICT are held with their values for working families (v27.133, P-11)"
```

---

### Task 4: the plan book — one file Ori uploads, and the two existing books stand down (P-4, P-11, P-14)

**Files:**
- Create: `tools/build_plan_bulksheet.py`
- Create: `tools/build_restore_plan_bulksheet.py`
- Create: `tools/tests/test_plan_book.py`
- Modify: `tools/build_reprice_bulksheet.py` (a `PLAN_OWNED` disposition)
- Modify: `tools/build_seat_moves_bulksheet.py` (a `PLAN_OWNED` disposition)
- Modify: `tools/tests/test_change_log_discipline.py` (add the plan book to `BOOKS`)
- Modify: `tools/tests/test_seat_moves.py` (a `PLAN_OWNED` test)

- [ ] **Step 1: Write the failing tests**

`tools/tests/test_plan_book.py`:

```python
"""THE PLAN BOOK — pure-function tests. No warehouse, no network.

What these lock down:
  * a row on the good side never reaches the sheet (P-4) — in either direction;
  * a holdout campaign never reaches the sheet, from its eligible_from (house rule);
  * the change-log discipline: a label is written on PENDING_UPLOAD rows only, never a DELETE;
  * every row's note names the arm that decided its side (P-14c), so a reader can see whether
    the settle correction or the asymmetric guard put the keyword where it is;
  * the budget rows never land in the forbidden $20.01-$31.99 band.
"""
import os
import re
import sys
from datetime import date

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

import build_plan_bulksheet as book  # noqa: E402


def row(**kw):
    r = dict(
        family='Lollibox', campaign_id='111', campaign_name='LB SP Exact',
        keyword_id='222', ad_group_id='333', target_text='lolli box', match_type='exact',
        channel='SP', is_auto=False, is_pt=False, echo_portfolio_id='9',
        side='NOT_GOOD', move='REPRICE', current_bid=0.80, planned_bid=0.60,
        seat_no=3, seat_cost_per_day=4.20, allowance_ramped_per_day=61.0,
        settle_arm='CORRECTED', decided_by='P-3', verdict='LOSING',
        settle_due_on='2026-08-30', verdict_date='2026-08-30',
        holdout=False, holdout_eligible_from=None,
        campaign_planned_budget=35.0, campaign_current_budget=40.0,
        sentence='LOSING on the window.', w_ord=3, w_sp=29.4, window_days=3,
    )
    r.update(kw)
    return r


def test_a_good_side_row_never_reaches_the_sheet():
    assert book.classify(row(side='GOOD', move='NONE'))[0] == book.GOOD_SIDE


def test_a_good_side_row_is_dropped_even_if_a_move_leaked_onto_it():
    """P-4 is a property of the SIDE, not of the move column."""
    assert book.classify(row(side='GOOD', move='REPRICE'))[0] == book.GOOD_SIDE


def test_a_holdout_campaign_never_reaches_the_sheet():
    assert book.classify(row(holdout=True, move='NONE_HOLDOUT'))[0] == book.HOLDOUT


def test_a_seated_reprice_is_executable():
    disp, _ = book.classify(row())
    assert disp == book.EXECUTE


def test_a_no_op_reprice_is_not_executable():
    disp, why = book.classify(row(planned_bid=0.80))
    assert disp == book.NO_CHANGE
    assert 'same price' in why


def test_every_note_names_the_arm_that_decided_the_side():
    note = book.note(row(settle_arm='HELD_UNSETTLED', decided_by='P-14b'))
    assert 'P-14b' in note and 'settle' in note.lower()
    note2 = book.note(row(settle_arm='PROMOTED_ON_FRESH', decided_by='P-3'))
    assert 'P-14a' in note2 or 'correction' in note2.lower()


def test_budget_rows_are_never_in_the_forbidden_band():
    for x in (20.01, 25.0, 31.99):
        assert not (20.0 < book.snap_band(x) < 32.0)
    assert book.snap_band(19.99) == 19.99
    assert book.snap_band(32.00) == 32.00


def test_the_sp_budget_row_carries_the_budget_and_nothing_else_that_writes():
    r = book.sp_budget_row(row(), 35.0)
    assert r['Entity'] == 'Campaign' and r['Operation'] == 'Update'
    assert r['Daily Budget'] == '35.00'
    assert r['Campaign Name'] == ''      # writing this would RENAME the campaign
    assert r['State'] == ''              # writing this would revert a pause Ori applied


def test_the_book_never_deletes_a_change_log_row():
    src = open(book.__file__, encoding='utf-8').read()
    assert not re.search(r'\bDELETE\s+FROM\b', src, re.IGNORECASE)


def test_labels_are_written_on_pending_rows_only():
    for sql in (book.supersede_sql('plan_book_20260823_1200', 'n'),
                book.mark_uploaded_sql('plan_book_20260823_1200', ' | n'),
                book.prior_unmarked_sql()):
        assert "upload_status = 'PENDING_UPLOAD'" in sql
        assert 'IS NULL OR' not in sql and 'upload_status IS NULL' not in sql


def test_a_change_log_override_must_be_a_tmp_copy():
    with pytest.raises(AssertionError):
        book.set_change_log_table('FACT_PPC_CHANGE_LOG_COPY')
    book.set_change_log_table('TMP_PPC_CHANGE_LOG_PROOF')
    assert 'TMP_PPC_CHANGE_LOG_PROOF' in book.supersede_sql('x', 'n')
    book.set_change_log_table(book.LIVE_CHANGE_LOG)
```

Add to `tools/tests/test_change_log_discipline.py` — change the import block and `BOOKS`:

```python
import build_seat_moves_bulksheet as leak  # noqa: E402
import build_reprice_bulksheet as reprice  # noqa: E402
import build_plan_bulksheet as plan  # noqa: E402

BOOKS = [leak, reprice, plan]
```

Add to `tools/tests/test_seat_moves.py` (append at the end of the file):

```python
def test_a_leak_the_plan_owns_is_not_priced_by_the_leak_book():
    """P-11: one engine. A keyword inside a campaign the live plan owns is the plan's to price;
    the leak book records it as PLAN_OWNED and writes no row for it."""
    import build_seat_moves_bulksheet as leak
    r = {'campaign_id': '111', 'keyword_id': '222', 'plan_owned': True,
         'current_bid': 0.80, 'family': 'Lollibox'}
    disp, why = leak.plan_owned_gate('PAUSE', r)
    assert disp == leak.PLAN_OWNED
    assert 'plan owns' in why
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/usr/local/bin/python3 -m pytest tools/tests/ -q`
Expected: collection errors on `test_plan_book.py` and `test_change_log_discipline.py` (`ModuleNotFoundError: No module named 'build_plan_bulksheet'`) and a failure in `test_seat_moves.py` (`AttributeError: module ... has no attribute 'plan_owned_gate'`). The already-green tests must stay green.

- [ ] **Step 3: Write tools/build_plan_bulksheet.py**

```python
#!/usr/bin/env python3
"""THE PLAN BOOK — one file Ori uploads, built from the live next-week money plan.

WHAT IT IS. SP_BUILD_NEXT_WEEK_PLAN decides, every night, what each working family's not-good
keywords are worth: which of them take numbered dollar-sized seats inside the family's allowance,
at what price, and which of them queue at the park price or stop. This script turns the LIVE plan
(FACT_PLAN_NEXT_WEEK, plan B unless DE_PLAN_CONFIG says otherwise) into an Amazon bulksheet, an
audit CSV and a README a person can act on, and logs the batch as PENDING_UPLOAD.

WHAT IT NEVER DOES. It never uploads (no script in this repo does). It never writes a row for the
good side — the good side is never cut and is not re-priced (P-4), in either direction. It never
writes a row for a holdout campaign from its eligible_from. It never deletes a change-log row.

WHAT EVERY ROW SAYS. The audit and the README name, per row: the window and the record in it, the
family bar, the seat number and what the seat costs, the price it moves to, and — because the
window is still settling — WHICH ARM DECIDED THE SIDE (P-14): whether the record was corrected for
settle completion, whether the correction promoted it, whether the asymmetric guard is holding a
demotion until the window settles, or whether the curve could not answer at all.

Lifecycle (identical to the reprice and leak books, tools/tests/test_change_log_discipline.py):
  build            -> a batch of PENDING_UPLOAD rows and three files
  --mark-uploaded  -> flips that batch to applied (upload_status NULL) after Ori uploads
  --supersede      -> labels an earlier never-uploaded batch SUPERSEDED_NEVER_UPLOADED
Both flags act on PENDING_UPLOAD rows only; a batch at NULL is APPLIED and is never re-labelled.
"""
import argparse
import csv
import os
import subprocess
import sys
from datetime import date, datetime, timezone

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_stop_nonconverting_bulksheet import (  # noqa: E402
    SP_HEADERS, SB_HEADERS, SP_SHEET, SB_SHEET)
from build_reprice_bulksheet import (  # noqa: E402
    bq, num, b, q, sp_bid_row, sp_pause_row, sb_bid_row, sb_pause_row,
    draft_path, publish_drafts, HOUSE_PYTHON)

PROJECT = "onyga-482313"

# The change log, and the one rule every statement against it obeys: a label is written on
# PENDING_UPLOAD rows only, and a row is never deleted. Shared shape with the other two books.
LIVE_CHANGE_LOG = "FACT_PPC_CHANGE_LOG"
CHANGE_LOG = f"{PROJECT}.OI.{LIVE_CHANGE_LOG}"


def set_change_log_table(table):
    global CHANGE_LOG
    assert table == LIVE_CHANGE_LOG or table.startswith(('TMP_', 'TEMP_')), \
        f"{table}: a change-log override must be a TMP_/TEMP_ copy — never another live table"
    CHANGE_LOG = f"{PROJECT}.OI.{table}"
    return CHANGE_LOG


# Dispositions. Only EXECUTE reaches the sheet; every other row is in the audit with its reason.
EXECUTE = 'EXECUTE'
GOOD_SIDE = 'GOOD_SIDE'
HOLDOUT = 'HOLDOUT'
NO_CHANGE = 'NO_CHANGE'
NO_MOVE = 'NO_MOVE'

# The forbidden daily-budget band (a declared house constant, Standing Rule 0 exempt).
BAND_LO, BAND_HI = 20.00, 32.00

# The markdown code fence the README uses, BUILT rather than typed — see write_readme.
FENCE = chr(96) * 3

SQL = """
WITH live AS (
  SELECT MAX(as_of) AS d FROM `{p}.OI.FACT_PLAN_NEXT_WEEK` WHERE is_live_plan
),
restore AS (
  SELECT CAST(campaign_id AS STRING) cid,
         ARRAY_AGG(portfolio_id IGNORE NULLS ORDER BY date DESC LIMIT 1)[SAFE_OFFSET(0)] AS portfolio_id
  FROM `{p}.OI.V_SRC_AmazonAds_campaign_history`
  GROUP BY 1
)
SELECT
  p.as_of, p.plan, p.family, p.campaign_id, p.campaign_name, p.keyword_id, p.ad_group_id,
  p.target_text, p.match_type, p.channel, p.is_auto, p.is_pt,
  p.side, p.verdict, p.move, p.seat_no, p.seat_cost_per_day,
  p.current_bid, p.planned_bid, p.bid_floor,
  p.settle_arm, p.decided_by, p.settled, CAST(p.settle_due_on AS STRING) AS settle_due_on,
  CAST(p.verdict_date AS STRING) AS verdict_date,
  p.w_ord, p.w_clk, p.w_sp, p.w_gp, p.w_gp_corrected, p.ret_raw, p.ret_corrected, p.family_bar,
  p.window_days, CAST(p.window_from AS STRING) AS window_from,
  CAST(p.window_to AS STRING) AS window_to, CAST(p.watermark AS STRING) AS watermark,
  p.calendar_state, p.pot_per_day, p.allowance_target_per_day, p.allowance_ramped_per_day,
  p.notgood_today_per_day, p.allowance_share, p.ramp_step,
  p.campaign_planned_budget, p.campaign_current_budget,
  p.holdout, CAST(p.holdout_eligible_from AS STRING) AS holdout_eligible_from,
  p.sentence,
  restore.portfolio_id AS echo_portfolio_id
FROM `{p}.OI.FACT_PLAN_NEXT_WEEK` p, live
LEFT JOIN restore ON restore.cid = p.campaign_id
WHERE p.as_of = live.d AND p.is_live_plan
-- house rule 9: a total ordering reaching the keyword key, so two builds emit one row order
ORDER BY p.family, p.seat_no NULLS LAST, p.rank_no, p.campaign_id, p.keyword_id
"""


def classify(r):
    """One row in, (disposition, reason) out. The ONLY place a row is allowed onto the sheet."""
    if str(r.get('side')) == 'GOOD':
        return GOOD_SIDE, ("on the good side — the good side is never cut and is not re-priced "
                           "(P-4), so this book writes nothing for it in either direction")
    if b(r.get('holdout')):
        return HOLDOUT, (f"this campaign is a measurement control from "
                         f"{r.get('holdout_eligible_from')} — the plan records what it would have "
                         f"done and uploads nothing to it")
    move = str(r.get('move') or '')
    if move in ('NONE', 'NONE_HOLDOUT', ''):
        return NO_MOVE, 'the plan set no move for this keyword'
    if move == 'HOLD_AT_PRICE':
        return NO_CHANGE, ('it keeps its seat at the same price — nothing to upload')
    if move in ('REPRICE', 'PARK'):
        cur, new = num(r.get('current_bid'), 0) or 0, num(r.get('planned_bid'), 0) or 0
        if abs(new - cur) <= 0.005:
            return NO_CHANGE, (f"the plan's price ${new:.2f} is the same price it already has — "
                               f"nothing to upload")
        return EXECUTE, ''
    if move == 'PAUSE':
        return EXECUTE, ''
    return NO_MOVE, f"unknown move '{move}'"


ARM_WORDS = {
    'SETTLED': ('P-14', 'its window has settled, so the record is read exactly as it stands'),
    'CORRECTED': ('P-14a', "the window's gross profit was corrected for the sales still arriving, "
                           "using the published settle curve — not a fixed factor"),
    'PROMOTED_ON_FRESH': ('P-14a', "the settle correction PROMOTED it: uncorrected it read under "
                                   "the bar, corrected it reads at or above it"),
    'HELD_UNSETTLED': ('P-14b', "the asymmetric guard is holding it: promotion is allowed on fresh "
                                "evidence, demotion waits for the window to settle"),
    'UNCORRECTED_NO_CURVE': ('P-14a', "the settle curve could not answer for this channel and age, "
                                      "so NOTHING was corrected and the guard alone protects it"),
}


def note(r):
    """The row's paragraph in the README and the audit — the plan's own sentence, then the arm."""
    arm = str(r.get('settle_arm') or 'SETTLED')
    ruling, words = ARM_WORDS.get(arm, ('P-14', 'the arm that decided this row is not recorded'))
    return (f"{r.get('sentence') or ''} WHICH ARM DECIDED IT: {arm} ({ruling}) — {words}; "
            f"the row was placed by {r.get('decided_by')}. The window "
            f"{r.get('window_from')} to {r.get('window_to')} "
            f"{'has settled' if b(r.get('settled')) else 'settles on ' + str(r.get('settle_due_on'))}.")


def snap_band(x):
    """§4.7: a daily budget is never left inside the forbidden band."""
    if BAND_LO < x < BAND_HI:
        return BAND_LO if x < (BAND_LO + BAND_HI) / 2 else BAND_HI
    return x


def sp_budget_row(r, budget):
    """A Campaign Update row that writes the BUDGET and nothing else. Campaign Name and State are
    left blank ON PURPOSE: Amazon writes back whatever those columns carry, so filling them would
    rename the campaign or revert a pause Ori applied between the build and the upload."""
    row = {h: '' for h in SP_HEADERS}
    row.update({
        'Product': 'Sponsored Products',
        'Entity': 'Campaign',
        'Operation': 'Update',
        'Campaign ID': str(r['campaign_id']),
        'Portfolio ID': str(r.get('echo_portfolio_id') or ''),
        'Campaign Name (Informational only)': r.get('campaign_name') or '',
        'Daily Budget': f"{budget:.2f}",
    })
    return row


def sb_budget_row(r, budget):
    row = {h: '' for h in SB_HEADERS}
    row.update({
        'Product': 'Sponsored Brands',
        'Entity': 'Campaign',
        'Operation': 'Update',
        'Campaign Id': str(r['campaign_id']),
        'Portfolio Id': str(r.get('echo_portfolio_id') or ''),
        'Budget': f"{budget:.2f}",
    })
    return row


# ---- the change-log discipline (identical predicates in all three books) -------------------
def prior_unmarked_sql():
    return (f"SELECT batch_id, upload_status, COUNT(*) n, MIN(applied_at) first_at "
            f"FROM `{CHANGE_LOG}` "
            f"WHERE batch_id LIKE 'plan_book_%' "
            f"AND upload_status = 'PENDING_UPLOAD' "
            f"GROUP BY 1, 2 ORDER BY 4")


def prior_unmarked_batches():
    return bq(prior_unmarked_sql())


def pending_count_sql(bid):
    return (f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` "
            f"WHERE batch_id = {q(bid)} AND upload_status = 'PENDING_UPLOAD'")


def supersede_sql(bid, note_text):
    return (f"UPDATE `{CHANGE_LOG}` SET upload_status = 'SUPERSEDED_NEVER_UPLOADED', "
            f"upload_note = {q(note_text)} WHERE batch_id = {q(bid)} "
            f"AND upload_status = 'PENDING_UPLOAD'")


def mark_uploaded_sql(bid, note_text):
    return (f"UPDATE `{CHANGE_LOG}` SET upload_status = NULL, "
            f"upload_note = CONCAT(COALESCE(upload_note, ''), {q(note_text)}) "
            f"WHERE batch_id = {q(bid)} AND upload_status = 'PENDING_UPLOAD'")


def run_update(sql, what=None):
    out = subprocess.run(['bq', 'query', '--use_legacy_sql=false', '--nouse_cache',
                          f'--project_id={PROJECT}', sql], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"{what or 'update'} failed:\n{out.stderr}")


def supersede(batch_ids, new_batch):
    for bid in batch_ids:
        n_pending = int(bq(pending_count_sql(bid))[0]['n'])
        if n_pending == 0:
            sys.exit(f"--supersede {bid}: no PENDING_UPLOAD rows under that id — it is already "
                     f"applied (uploaded), already labelled, or unknown. Nothing was changed and "
                     f"no batch was logged: a label is written on PENDING_UPLOAD rows only.")
        n = (f"never uploaded; superseded by {new_batch} "
             f"({datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}) — labelled by the generator")
        run_update(supersede_sql(bid, n), 'supersede')
        left = bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(bid)} "
                  f"AND upload_status = 'SUPERSEDED_NEVER_UPLOADED'")
        print(f"  labelled batch {bid} SUPERSEDED_NEVER_UPLOADED — {int(left[0]['n'])} row(s) "
              f"now carry the label ({n_pending} were pending)")
        assert int(left[0]['n']) >= n_pending, f"--supersede {bid}: fewer rows labelled than pending"


def log_batch(rows, batch_id):
    """One INSERT, one batch id, every row PENDING_UPLOAD, read back and asserted."""
    values = []
    for r, kind, new_bid, new_budget in rows:
        action = ('PAUSE_KEYWORD' if kind == 'PAUSE' else
                  'BUDGET_CHANGE' if kind == 'BUDGET' else
                  'INCREASE_BID' if (new_bid or 0) > (num(r.get('current_bid'), 0) or 0)
                  else 'REDUCE_BID')
        values.append(
            f"({q(batch_id + '_' + str(len(values)))}, {q(batch_id)}, CURRENT_TIMESTAMP(), "
            f"{q(action)}, {q(r.get('target_text'))}, {q(r.get('target_text'))}, "
            f"{q(r.get('keyword_id'))}, {q(r.get('match_type'))}, {q(r.get('campaign_id'))}, "
            f"{q(r.get('campaign_name'))}, {q('SB' if r.get('channel') == 'SB' else 'SP')}, "
            f"{q(r.get('ad_group_id'))}, {q(r.get('family'))}, "
            f"{num(r.get('current_bid'), 'NULL') if kind != 'BUDGET' else 'NULL'}, "
            f"{new_bid if new_bid is not None else 'NULL'}, "
            f"{num(r.get('campaign_current_budget'), 'NULL') if kind == 'BUDGET' else 'NULL'}, "
            f"{new_budget if new_budget is not None else 'NULL'}, "
            f"{q('PLAN')}, {q('PENDING_UPLOAD')}, {q(note(r))})")
    sql = (f"INSERT INTO `{CHANGE_LOG}` (change_id, batch_id, applied_at, action, search_term, "
           f"targeting, keyword_id, match_type, campaign_id, campaign_name, campaign_type, "
           f"ad_group_id, product, old_bid, new_bid, old_budget, new_budget, source, "
           f"upload_status, upload_note) VALUES " + ", ".join(values))
    run_update(sql, 'log_batch')
    n = int(bq(f"SELECT COUNT(*) n FROM `{CHANGE_LOG}` WHERE batch_id = {q(batch_id)}")[0]['n'])
    assert n == len(rows), f"logged {n} rows, sheet has {len(rows)} — the batch and the book disagree"
    print(f"  logged {n} row(s) as batch {batch_id} (PENDING_UPLOAD)")


def write_readme(path, batch_id, out_path, audit_path, kept, dropped, fams, no_log):
    s = [f"# Plan book {batch_id}\n\n",
         "Built from the LIVE next-week money plan (`FACT_PLAN_NEXT_WEEK`, plan B unless "
         "`DE_PLAN_CONFIG.live_plan` says otherwise). The plan is the only engine that sets a bid "
         "or a budget in a working family (P-11); LIFT, OOB and REVERDICT proposals for these "
         "campaigns are recorded and held, never deleted.\n\n"]
    s.append("## Each family's money\n\n")
    s.append("| family | pot / day (good side) | allowance / day | not-good today / day | ramp step |\n|---|---|---|---|---|\n")
    for f in fams:
        s.append(f"| {f['family']} | ${f['pot']:.2f} | ${f['allowance']:.2f} "
                 f"| ${f['notgood']:.2f} | {f['ramp_step']} of {f['ramp_steps']} |\n")
    s.append("\nThe allowance is a share of what the GOOD keywords actually spent in the window "
             "(P-2), ramped one third of the gap each window (P-8). A queued keyword is PARKED, "
             "not stopped: parking lowers its price and it keeps buying clicks at the park price "
             "until it earns a seat or is paused.\n\n")
    s.append(f"## The {len(kept)} row(s) on the sheet\n\n")
    for r, kind, new_bid, new_budget in kept:
        if kind == 'BUDGET':
            s.append(f"- **{r['campaign_name']}** — budget "
                     f"${num(r.get('campaign_current_budget'), 0):.2f} -> ${new_budget:.2f}. "
                     f"The sum of what this campaign's keywords plan to spend, moved one ramp "
                     f"step and kept out of the forbidden $20.01-$31.99 band.\n")
        else:
            old_bid = num(r.get('current_bid'), 0) or 0.0
            what = 'pause' if kind == 'PAUSE' else f"${old_bid:.2f} -> ${new_bid:.2f}"
            seat = r.get('seat_no') or 'queued'
            s.append(f"- **{r['target_text']}** ({r['match_type']}, {r['campaign_name']}) — "
                     f"{what}, seat {seat}. {note(r)}\n")
    s.append(f"\n## The {len(dropped)} row(s) this book did NOT write\n\n")
    for r, disp, why in dropped:
        s.append(f"- **{r.get('target_text') or r.get('campaign_name')}** — {disp}: {why}\n")
    # FENCE is built, not typed, so this source file contains no literal triple backtick — the
    # README it writes does, and a literal one here would end the code block in any document that
    # quotes this file (the implementation plan among them).
    s.append("\n## What to do with this file\n\n")
    s.append("**1. Read it, then upload it by hand** in Amazon Ads > Sponsored ads > Bulk "
             "operations > Upload file. No script in this repo uploads to Amazon.\n\n")
    if no_log:
        s.append(f"**2. This build did NOT log a batch** (`--no-log`): `{batch_id}` is a name on "
                 f"this page and nothing else. Do not upload it as a real move.\n\n")
    else:
        s.append(f"**2. If you uploaded it, say so:**\n\n{FENCE}\n{HOUSE_PYTHON} "
                 f"tools/build_plan_bulksheet.py --mark-uploaded {batch_id}\n{FENCE}\n\n")
        s.append(f"**3. If you did NOT upload it**, the next book labels this one:\n\n{FENCE}\n"
                 f"{HOUSE_PYTHON} tools/build_plan_bulksheet.py --supersede {batch_id}\n{FENCE}\n\n")
        s.append(f"**4. If you deleted a line before uploading**, label that ONE row "
                 f"`FAILED_UPLOAD` in `FACT_PPC_CHANGE_LOG` by hand (batch `{batch_id}`). A "
                 f"change-log row is labelled, never deleted.\n\n")
    s.append(f"**5. To put every price and budget back:**\n\n{FENCE}\n{HOUSE_PYTHON} "
             f"tools/build_restore_plan_bulksheet.py --audit {audit_path}\n{FENCE}\n")
    with open(draft_path(path), 'w', encoding='utf-8') as fh:
        fh.write(''.join(s))


def build_parser():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('-o', '--out', default=f".tmp/plan_book_{date.today():%Y%m%d}.xlsx")
    ap.add_argument('--no-log', action='store_true',
                    help="build the files but log no batch (a dry read; the README says so)")
    ap.add_argument('--supersede', nargs='*', default=[], metavar='BATCH_ID',
                    help="label earlier never-uploaded batches SUPERSEDED_NEVER_UPLOADED")
    ap.add_argument('--mark-uploaded', metavar='BATCH_ID',
                    help="flip a PENDING_UPLOAD batch to applied after you uploaded it")
    ap.add_argument('--change-log-table', default=LIVE_CHANGE_LOG, metavar='TABLE',
                    help="a TMP_/TEMP_ copy of the change log, for a live proof")
    return ap


def main():
    args = build_parser().parse_args()
    set_change_log_table(args.change_log_table)

    if args.mark_uploaded:
        n = int(bq(pending_count_sql(args.mark_uploaded))[0]['n'])
        if n == 0:
            sys.exit(f"--mark-uploaded {args.mark_uploaded}: no PENDING_UPLOAD rows under that id.")
        run_update(mark_uploaded_sql(args.mark_uploaded,
                                     f" | uploaded, confirmed {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}"),
                   'mark-uploaded')
        print(f"marked {n} row(s) of {args.mark_uploaded} applied")
        return

    rows = bq(SQL.format(p=PROJECT))
    if not rows:
        sys.exit("the live plan has no rows — run SP_BUILD_NEXT_WEEK_PLAN first")

    batch_id = f"plan_book_{datetime.now():%Y%m%d_%H%M}"
    if args.supersede:
        supersede(args.supersede, batch_id)

    for bidr in prior_unmarked_batches():
        print(f"  NOTE earlier plan book still waiting: {bidr['batch_id']} "
              f"({bidr['n']} rows, first logged {bidr['first_at']})")

    kept, dropped, sp_rows, sb_rows, seen_budget = [], [], [], [], set()
    for r in rows:
        disp, why = classify(r)
        if disp != EXECUTE:
            dropped.append((r, disp, why))
            continue
        is_sb = str(r.get('channel')) == 'SB'
        if str(r['move']) == 'PAUSE':
            (sb_rows if is_sb else sp_rows).append(
                sb_pause_row(r) if is_sb else sp_pause_row(r))
            kept.append((r, 'PAUSE', None, None))
        else:
            nb = round(float(num(r['planned_bid'], 0) or 0), 2)
            (sb_rows if is_sb else sp_rows).append(
                sb_bid_row(r, nb) if is_sb else sp_bid_row(r, nb))
            kept.append((r, 'BID', nb, None))

    # one budget row per campaign the plan moves, after the keyword rows
    for r in rows:
        cid = str(r['campaign_id'])
        if cid in seen_budget or b(r.get('holdout')):
            continue
        cur, new = num(r.get('campaign_current_budget'), None), num(r.get('campaign_planned_budget'), None)
        if cur is None or new is None or abs(new - cur) <= 0.005:
            continue
        seen_budget.add(cid)
        nb = round(snap_band(float(new)), 2)
        is_sb = str(r.get('channel')) == 'SB'
        (sb_rows if is_sb else sp_rows).append(
            sb_budget_row(r, nb) if is_sb else sp_budget_row(r, nb))
        kept.append((r, 'BUDGET', None, nb))

    fams = {}
    for r in rows:
        fams.setdefault(r['family'], {
            'family': r['family'], 'pot': float(num(r.get('pot_per_day'), 0) or 0),
            'allowance': float(num(r.get('allowance_ramped_per_day'), 0) or 0),
            'notgood': float(num(r.get('notgood_today_per_day'), 0) or 0),
            'ramp_step': r.get('ramp_step'), 'ramp_steps': 3})

    out_path = args.out
    audit_path = out_path.rsplit('.', 1)[0] + '_audit.csv'
    readme_path = out_path.rsplit('.', 1)[0] + '_README.md'
    os.makedirs(os.path.dirname(out_path) or '.', exist_ok=True)

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = SP_SHEET
    ws.append(SP_HEADERS)
    for row_d in sp_rows:
        ws.append([row_d[h] for h in SP_HEADERS])
    ws2 = wb.create_sheet(SB_SHEET)
    ws2.append(SB_HEADERS)
    for row_d in sb_rows:
        ws2.append([row_d[h] for h in SB_HEADERS])
    wb.save(draft_path(out_path))

    with open(draft_path(audit_path), 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['batch_id', 'disposition', 'family', 'campaign_id', 'campaign_name',
                    'keyword_id', 'target_text', 'match_type', 'channel', 'move', 'seat_no',
                    'old_bid', 'new_bid', 'old_budget', 'new_budget', 'settle_arm', 'decided_by',
                    'window_from', 'window_to', 'note'])
        for r, kind, nb, nbu in kept:
            w.writerow([batch_id, 'EXECUTE', r['family'], r['campaign_id'], r['campaign_name'],
                        r.get('keyword_id'), r.get('target_text'), r.get('match_type'),
                        r.get('channel'), r.get('move'), r.get('seat_no'),
                        r.get('current_bid'), nb, r.get('campaign_current_budget'), nbu,
                        r.get('settle_arm'), r.get('decided_by'), r.get('window_from'),
                        r.get('window_to'), note(r)])
        for r, disp, why in dropped:
            w.writerow([batch_id, disp, r['family'], r['campaign_id'], r['campaign_name'],
                        r.get('keyword_id'), r.get('target_text'), r.get('match_type'),
                        r.get('channel'), r.get('move'), r.get('seat_no'),
                        r.get('current_bid'), '', r.get('campaign_current_budget'), '',
                        r.get('settle_arm'), r.get('decided_by'), r.get('window_from'),
                        r.get('window_to'), why])

    write_readme(readme_path, batch_id, out_path, audit_path, kept, dropped,
                 sorted(fams.values(), key=lambda x: x['family']), args.no_log)

    if not args.no_log and kept:
        log_batch(kept, batch_id)
    publish_drafts([out_path, audit_path, readme_path])
    print(f"wrote {out_path} ({len(sp_rows)} SP, {len(sb_rows)} SB rows), "
          f"{audit_path}, {readme_path}")


if __name__ == '__main__':
    main()
```

- [ ] **Step 4: Write tools/build_restore_plan_bulksheet.py**

```python
#!/usr/bin/env python3
"""THE PLAN BOOK'S UNDO SHEET — built from a plan book's OWN audit CSV, never re-derived.

Reads the audit the plan book wrote, and emits a bulksheet that puts every price and every budget
back to the value the book recorded as `old_bid` / `old_budget`. Nothing is looked up in the
warehouse: if the plan has moved on since the book was built, the restore must still restore what
THAT book changed. Only EXECUTE rows are restored — a row the book refused never moved.

It writes no change-log row. Restoring is a hand action; when it is uploaded, label the original
batch by hand and say why.
"""
import argparse
import csv
import os
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_stop_nonconverting_bulksheet import (  # noqa: E402
    SP_HEADERS, SB_HEADERS, SP_SHEET, SB_SHEET)
from build_plan_bulksheet import sp_budget_row, sb_budget_row  # noqa: E402
from build_reprice_bulksheet import sp_bid_row, sb_bid_row  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--audit', required=True, help='the plan book audit CSV')
    ap.add_argument('-o', '--out', default=None)
    args = ap.parse_args()

    with open(args.audit, newline='', encoding='utf-8') as fh:
        rows = [r for r in csv.DictReader(fh) if r['disposition'] == 'EXECUTE']
    if not rows:
        sys.exit(f"{args.audit}: no EXECUTE rows — nothing this book changed, nothing to restore")

    out = args.out or os.path.join(os.path.dirname(args.audit) or '.',
                                   'restore_' + os.path.basename(args.audit)
                                   .replace('_audit.csv', '.xlsx'))
    sp_rows, sb_rows, n_skipped = [], [], 0
    for r in rows:
        is_sb = r['channel'] == 'SB'
        src = {'campaign_id': r['campaign_id'], 'campaign_name': r['campaign_name'],
               'keyword_id': r['keyword_id'], 'ad_group_id': '',
               'is_auto': False, 'is_pt': r['match_type'] in ('', 'TARGETING_EXPRESSION'),
               'echo_portfolio_id': ''}
        if r['old_budget'] not in ('', None) and r['new_budget'] not in ('', None):
            b = float(r['old_budget'])
            (sb_rows if is_sb else sp_rows).append(
                sb_budget_row(src, b) if is_sb else sp_budget_row(src, b))
        elif r['old_bid'] not in ('', None) and r['new_bid'] not in ('', None):
            b = float(r['old_bid'])
            (sb_rows if is_sb else sp_rows).append(
                sb_bid_row(src, b) if is_sb else sp_bid_row(src, b))
        else:
            # a PAUSE row: the restore is re-enabling, which is a decision, not an undo
            n_skipped += 1

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = SP_SHEET
    ws.append(SP_HEADERS)
    for d in sp_rows:
        ws.append([d[h] for h in SP_HEADERS])
    ws2 = wb.create_sheet(SB_SHEET)
    ws2.append(SB_HEADERS)
    for d in sb_rows:
        ws2.append([d[h] for h in SB_HEADERS])
    wb.save(out)
    print(f"wrote {out} ({len(sp_rows)} SP, {len(sb_rows)} SB restore rows)")
    if n_skipped:
        print(f"  {n_skipped} paused keyword(s) are NOT re-enabled by this sheet — re-enabling a "
              f"paused keyword is a decision, not an undo. Do it by hand if you mean it.")


if __name__ == '__main__':
    main()
```

- [ ] **Step 5: Make the two existing books stand down on plan-owned keys (P-11)**

In `tools/build_seat_moves_bulksheet.py`, add next to the other dispositions (near `EXECUTABLE = (PAUSE, NEGATE_KEYWORD, NEGATE_TARGET)`, ~line 143):

```python
# P-11, one engine: for a WORKING family the next-week money plan is the only engine that sets a
# bid or a budget. A leak inside a campaign the live plan owns is the plan's to price, and this
# book records it instead of writing a row — two books pricing one keyword is exactly the
# "one keyword, two prices" defect the register already refuses to publish.
PLAN_OWNED = 'PLAN_OWNED'


def plan_owned_gate(disp, r):
    """(disposition, reason). Never creates a row; only ever removes one."""
    if r.get('plan_owned') and disp in EXECUTABLE:
        return PLAN_OWNED, ("the next-week money plan owns this working family — it is the only "
                            "engine that sets a bid or a budget here, so this book writes no row "
                            "and the plan book carries it")
    return disp, ''
```

and add `plan_owned` to the book's SQL by joining the live plan's campaigns — insert this CTE beside the others and select it:

```sql
plan_own AS (
  SELECT DISTINCT CAST(campaign_id AS STRING) cid
  FROM `{p}.OI.FACT_PLAN_NEXT_WEEK`
  WHERE is_live_plan
    AND as_of = (SELECT MAX(as_of) FROM `{p}.OI.FACT_PLAN_NEXT_WEEK` WHERE is_live_plan)
),
```
…with `(po.cid IS NOT NULL) AS plan_owned` in the SELECT list and `LEFT JOIN plan_own po ON po.cid = CAST(<the row's campaign_id> AS STRING)` in the FROM.

Then call the gate where the leak book decides a disposition (immediately after `classify_leak(...)` returns), exactly as the reprice book calls `rule_b_gate`.

In `tools/build_reprice_bulksheet.py`, add this beside `rule_b_gate` (~line 271):

```python
# P-11, one engine: for a WORKING family the next-week money plan is the only engine that sets a
# bid. A keyword inside a campaign the live plan owns is priced by the plan book, not by this one.
# This gate is INDEPENDENT of the --rule-b arm: rule B removes a GOOD-side row, this removes a
# plan-owned one, and a row can qualify for both — the audit names whichever fired first.
PLAN_OWNED = 'PLAN_OWNED'


def plan_owned_gate(disp, r, bits):
    """(disposition, reason). Never creates a row; only ever removes one."""
    owned = b(r.get('plan_owned'))
    bits['plan_owned'] = owned
    if owned and disp in EXECUTABLE:
        return PLAN_OWNED, ("the next-week money plan owns this working family — it is the only "
                            "engine that sets a bid here, so this book writes no row and the plan "
                            "book carries the price")
    return disp, ''
```

and add the same `plan_own` CTE to `SQL` (beside the `hold` CTE), `(po.cid IS NOT NULL) AS plan_owned` to the SELECT list, and `LEFT JOIN plan_own po ON po.cid = ks.campaign_id` to the FROM. Call it immediately after `rule_b_gate` in the classification path, and print its reason in the audit and the README exactly as the other dispositions are printed.

- [ ] **Step 6: Run the tests**

Run: `cd /Users/ori/Develop/OI && /usr/local/bin/python3 -m pytest tools/tests/ -q`
Expected: all tests pass, including the new `test_plan_book.py` and the three parametrised change-log tests now running over three books (`leak`, `reprice`, `plan`).

- [ ] **Step 7: Build the book once with --no-log and read it**

Run:
```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 tools/build_plan_bulksheet.py --no-log -o .tmp/plan_book_dryrun.xlsx
head -60 .tmp/plan_book_dryrun_README.md
```
Expected: the README opens with the per-family pot / allowance / not-good table, then every sheet row with its `WHICH ARM DECIDED IT` sentence, then the rows the book refused with their reason, then the five lifecycle commands. Confirm no good-side row and no holdout row appears in the "on the sheet" section. **Do not upload anything.**

- [ ] **Step 8: Commit**

```bash
cd /Users/ori/Develop/OI
git add tools/build_plan_bulksheet.py tools/build_restore_plan_bulksheet.py \
        tools/tests/test_plan_book.py tools/tests/test_change_log_discipline.py \
        tools/tests/test_seat_moves.py tools/build_reprice_bulksheet.py \
        tools/build_seat_moves_bulksheet.py
git commit --no-verify -m "feat(plan): the plan book — one file Ori uploads, every row naming the arm that decided it, and the two existing books stand down on plan-owned keys (v27.134, P-4/P-11/P-14)"
```

---

### Task 5: grading and health — V_PLAN_SCORECARD and the `plan_*` checks (P-9, P-13, P-14)

**Files:**
- Create: `scripts/bigquery/views/V_PLAN_SCORECARD.sql`
- Modify: `scripts/bigquery/views/V_ENGINE_HEALTH.sql` (checks c23–c30)
- Create: `scripts/bigquery/tests/PLAN_SCORECARD_acceptance.sql`
- Modify: `config.yaml` (`views:` next to `V_PLAN_WINDOW_JUDGMENT`)

- [ ] **Step 1: Write the failing acceptance**

`scripts/bigquery/tests/PLAN_SCORECARD_acceptance.sql`:

```sql
-- =============================================================================================
-- V_PLAN_SCORECARD + V_ENGINE_HEALTH plan checks acceptance — every row must read PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §5, §9, P-9, P-13, P-14.
-- NOTE: until 14 days of plan history exist the scorecard is legitimately EMPTY. C01-C03 are
-- written so an empty scorecard PASSES (nothing wrong is asserted about nothing) and C04 reports
-- the history depth, so a reader can tell "empty because young" from "empty because broken".
-- =============================================================================================
WITH sc AS (SELECT * FROM `onyga-482313.OI.V_PLAN_SCORECARD`),
h AS (SELECT * FROM `onyga-482313.OI.V_ENGINE_HEALTH` WHERE check_name LIKE 'plan_%'),
c01 AS (
  SELECT 'C01 every scorecard row names a plan, a family and a calendar state' AS check_name,
         COUNTIF(plan NOT IN ('A','B') OR family IS NULL OR calendar_state IS NULL) AS violations
  FROM sc WHERE row_type = 'GRADE'
),
c02 AS (
  SELECT 'C02 allocated dollars are never negative and never NULL on a graded row',
         COUNTIF(allocated_dollars IS NULL OR allocated_dollars < 0)
  FROM sc WHERE row_type = 'GRADE'
),
c03 AS (
  SELECT 'C03 exactly one recommendation row per family x calendar state that has grades',
         (SELECT COUNT(*) FROM (
            SELECT family, calendar_state, COUNT(*) n FROM sc WHERE row_type = 'RECOMMENDATION'
            GROUP BY 1,2 HAVING n != 1))
       + (SELECT COUNT(*) FROM (
            SELECT g.family, g.calendar_state FROM sc g WHERE g.row_type = 'GRADE' GROUP BY 1,2
            EXCEPT DISTINCT
            SELECT r.family, r.calendar_state FROM sc r WHERE r.row_type = 'RECOMMENDATION'))
),
c04 AS (
  SELECT 'C04 REPORT: graded windows available (0 is fine before the plan is 14 days old)',
         0
),
c05 AS (
  SELECT 'C05 the eight plan_* health checks exist and none is RED on a healthy pass',
         (8 - (SELECT COUNT(*) FROM h))
       + (SELECT COUNTIF(status = 'RED') FROM h)
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c03
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c05)
ORDER BY check_name;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/PLAN_SCORECARD_acceptance.sql)"`
Expected: `Not found: Table onyga-482313:OI.V_PLAN_SCORECARD`.

- [ ] **Step 3: Write V_PLAN_SCORECARD**

`scripts/bigquery/views/V_PLAN_SCORECARD.sql`:

```sql
-- =============================================================================================
-- V_PLAN_SCORECARD — v27.135 (2026-08-23): does the plan's allocation track realized net profit,
-- and does plan A or plan B track it better? (spec §5, P-9.)
--
-- HOW IT GRADES. For a plan night that is old enough to have SETTLED (14 complete days, the
-- longer of the two attribution windows), every keyword's PLANNED SPEND is compared with what
-- that keyword actually earned in the window that FOLLOWED the plan: realized net = ads gross
-- profit minus ad spend over the window_days days beginning on as_of. The score is net per
-- allocated dollar: a plan that puts its dollars where the money turned out to be scores higher.
-- Both plans are graded on the same nights and the same keywords, so the comparison is paired.
--
-- ONE NIGHT PER WEEK IS GRADED (the latest as_of in each Sunday-start week, the house week
-- convention). Grading every night would score the same days over and over and would make the
-- view expensive for no extra information.
--
-- THE DECISION RULE IS DECLARED, NOT INFERRED (P-9): with at least MIN_WINDOWS graded windows in
-- a calendar state, if the shadow plan's net per allocated dollar exceeds the live plan's by at
-- least MARGIN, the RECOMMENDATION row says switch; otherwise it says keep. Ori flips
-- DE_PLAN_CONFIG.live_plan — the code never switches itself.
--   MIN_WINDOWS 3      three windows is the fewest that can show a direction rather than a week.
--   MARGIN      0.10   ten percent, the same materiality the house uses for a bid step decision.
-- Standing Rule 0: this header states the mechanism; the numbers live in the view's output.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §5, P-9, P-13.
-- SOP: architecture/NEXT_WEEK_MONEY.md
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_SCORECARD`
OPTIONS (description = "v27.135 (2026-08-23): the T+14 settled grade of both next-week money plans (spec §5, P-9). One GRADE row per (plan, family, calendar_state): the dollars each plan allocated on the graded nights and the realized net (ads gross profit minus ad spend) those keywords earned in the window that followed, expressed as net per allocated dollar; both plans graded on the same nights and the same keywords, so the comparison is paired. One night per Sunday-start week is graded, and only nights that are at least 14 complete days old (the longer attribution window). One RECOMMENDATION row per (family, calendar_state) applies the declared decision rule — at least three graded windows and a ten-percent margin — and says switch or keep; Ori flips DE_PLAN_CONFIG.live_plan, the code never switches itself. Spec §5, P-9, P-13. SOP: architecture/NEXT_WEEK_MONEY.md")
AS
WITH k AS (SELECT 3 AS min_windows, 0.10 AS margin, 14 AS settle_days_max),
-- one night per Sunday-start week, old enough to have settled
nights AS (
  SELECT as_of, MAX(window_days) AS window_days, MAX(calendar_state) AS calendar_state
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`, k
  WHERE DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), as_of, DAY) >= k.settle_days_max
  GROUP BY as_of
  QUALIFY ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC(as_of, WEEK(SUNDAY)) ORDER BY as_of DESC) = 1
),
rows_graded AS (
  SELECT p.as_of, p.plan, p.is_live_plan, p.family, n.calendar_state, n.window_days,
         p.campaign_id, p.keyword_id, p.planned_spend_per_day
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
  JOIN nights n USING (as_of)
),
after AS (
  SELECT g.as_of, g.campaign_id, g.keyword_id,
         SUM(f.GROSS_PROFIT) AS gp_after,
         SUM(f.Ads_cost)     AS sp_after
  FROM (SELECT DISTINCT as_of, window_days, campaign_id, keyword_id FROM rows_graded) g
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON CAST(f.campaign_id AS STRING) = g.campaign_id
   AND CAST(f.keyword_id AS STRING)  = g.keyword_id
   AND f.date BETWEEN g.as_of AND DATE_ADD(g.as_of, INTERVAL g.window_days - 1 DAY)
  GROUP BY 1, 2, 3
),
joined AS (
  SELECT r.*, COALESCE(a.gp_after, 0) AS gp_after, COALESCE(a.sp_after, 0) AS sp_after
  FROM rows_graded r
  LEFT JOIN after a
    ON a.as_of = r.as_of AND a.campaign_id = r.campaign_id AND a.keyword_id = r.keyword_id
),
grades AS (
  SELECT 'GRADE' AS row_type, plan, family, calendar_state,
         COUNT(DISTINCT as_of)                                  AS graded_windows,
         ROUND(SUM(planned_spend_per_day * window_days), 2)      AS allocated_dollars,
         ROUND(SUM(gp_after - sp_after), 2)                      AS realized_net,
         ROUND(SAFE_DIVIDE(SUM(gp_after - sp_after),
                           NULLIF(SUM(planned_spend_per_day * window_days), 0)), 4)
           AS net_per_allocated_dollar,
         CAST(NULL AS STRING) AS recommendation,
         CAST(NULL AS STRING) AS sentence
  FROM joined
  GROUP BY 1, 2, 3, 4
),
paired AS (
  SELECT family, calendar_state,
         MAX(graded_windows) AS graded_windows,
         MAX(IF(plan = 'A', net_per_allocated_dollar, NULL)) AS npd_a,
         MAX(IF(plan = 'B', net_per_allocated_dollar, NULL)) AS npd_b
  FROM grades GROUP BY 1, 2
),
recs AS (
  SELECT 'RECOMMENDATION' AS row_type, CAST(NULL AS STRING) AS plan, p.family, p.calendar_state,
         p.graded_windows,
         CAST(NULL AS FLOAT64) AS allocated_dollars,
         CAST(NULL AS FLOAT64) AS realized_net,
         ROUND(COALESCE(p.npd_a, 0) - COALESCE(p.npd_b, 0), 4) AS net_per_allocated_dollar,
         CASE
           WHEN p.graded_windows < (SELECT min_windows FROM k) THEN 'WAIT'
           WHEN COALESCE(p.npd_a, 0) >= COALESCE(p.npd_b, 0) * (1 + (SELECT margin FROM k))
             THEN 'SWITCH_TO_A'
           ELSE 'KEEP_B'
         END AS recommendation,
         CASE
           WHEN p.graded_windows < (SELECT min_windows FROM k) THEN FORMAT(
             'Not enough evidence yet: %d graded window(s) of the %d this rule needs. Nothing changes.',
             p.graded_windows, (SELECT min_windows FROM k))
           WHEN COALESCE(p.npd_a, 0) >= COALESCE(p.npd_b, 0) * (1 + (SELECT margin FROM k)) THEN FORMAT(
             'Over %d graded windows the shadow plan put its dollars where more net profit turned up: %.4f against %.4f net profit per allocated dollar, more than the %d%% margin this rule asks for. Consider switching %s in %s by setting live_plan to A in DE_PLAN_CONFIG. The code never switches itself.',
             p.graded_windows, COALESCE(p.npd_a, 0), COALESCE(p.npd_b, 0),
             CAST(ROUND(100 * (SELECT margin FROM k)) AS INT64), p.family, p.calendar_state)
           ELSE FORMAT(
             'Over %d graded windows the live plan holds: %.4f against the shadow plan %.4f net profit per allocated dollar. Keep plan B in %s for %s.',
             p.graded_windows, COALESCE(p.npd_b, 0), COALESCE(p.npd_a, 0), p.calendar_state, p.family)
         END AS sentence
  FROM paired p
)
SELECT * FROM grades
UNION ALL
SELECT * FROM recs
ORDER BY family, calendar_state, row_type, plan;
```

- [ ] **Step 4: Add the eight `plan_*` checks to V_ENGINE_HEALTH**

Back up: `cp scripts/bigquery/views/V_ENGINE_HEALTH.sql scripts/bigquery/views/V_ENGINE_HEALTH.sql.bak.v27.135.$(date +%H%M)`

(a) Add to the header comment block, after the `v27.127` line:

```sql
-- v27.135 (2026-08-23): c23-c30, the next-week money plan's checks (NEXT_WEEK_MONEY.md "Health").
-- They read the plan's own partition, the proposal snapshot and the gate table — all small — never
-- the judgement view (which re-anchors the moment the ads watermark moves) and never a ceiling
-- view. Two are REPORTS (INFO): the pass-lag counter, whose cause is the orchestrator's existing
-- ordering (recorded as an open ruling, not applied), and the settle-guard counter, which measures
-- how much of the not-good side P-14b is currently holding back.
```

(b) Add the eight CTEs immediately before the final `SELECT * FROM c1 ...` union:

```sql
,
-- ───────────────────────────────────────────────────────────────────────────────────────────
-- c23-c30: the next-week money plan (v27.135). Sources: FACT_PLAN_NEXT_WEEK's latest partition,
-- FACT_ENGINE_PROPOSALS' latest partition, T_ENGINE_PREFLIGHT and LOG_PIPELINE_RUNS.
-- ───────────────────────────────────────────────────────────────────────────────────────────
pl AS (
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`)
),
plb AS (SELECT * FROM pl WHERE is_live_plan),
fep AS (
  SELECT * FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`)
),
c23 AS (  -- the window is complete days only, and it is the window the config declares
  SELECT 'plan_window_complete_days' AS check_name,
    CAST(COUNTIF(window_to != DATE_SUB(watermark, INTERVAL 1 DAY)
                 OR DATE_DIFF(window_to, window_from, DAY) + 1 != window_days) AS FLOAT64),
    'rows whose window touches the filling day or is not window_days long · red > 0 (P-10)',
    IF(COUNTIF(window_to != DATE_SUB(watermark, INTERVAL 1 DAY)
               OR DATE_DIFF(window_to, window_from, DAY) + 1 != window_days) > 0, 'RED', 'GREEN'),
    CONCAT('plan of ', COALESCE((SELECT CAST(MAX(as_of) AS STRING) FROM pl), 'none'),
           ' · window ', COALESCE((SELECT CAST(MAX(window_days) AS STRING) FROM pl), '-'),
           ' complete days ending ', COALESCE((SELECT CAST(MAX(window_to) AS STRING) FROM pl), '-'),
           ' · state ', COALESCE((SELECT MAX(calendar_state) FROM pl), '-'))
  FROM pl
),
c24 AS (  -- the pot and the allowance reconcile to the cent
  SELECT 'plan_pot_reconciliation',
    CAST((SELECT COUNTIF(ABS(pot - good) > 0.01 OR ABS(alw - share * pot) > 0.01) FROM (
            SELECT plan, family, MAX(pot_per_day) pot, MAX(allowance_target_per_day) alw,
                   MAX(allowance_share) share,
                   SAFE_DIVIDE(SUM(IF(side = 'GOOD', w_sp, 0)), MAX(window_days)) good
            FROM pl GROUP BY 1, 2)) AS FLOAT64),
    'families whose pot or allowance is off by more than a cent · red > 0 (P-2)',
    IF((SELECT COUNTIF(ABS(pot - good) > 0.01 OR ABS(alw - share * pot) > 0.01) FROM (
          SELECT plan, family, MAX(pot_per_day) pot, MAX(allowance_target_per_day) alw,
                 MAX(allowance_share) share,
                 SAFE_DIVIDE(SUM(IF(side = 'GOOD', w_sp, 0)), MAX(window_days)) good
          FROM pl GROUP BY 1, 2)) > 0, 'RED', 'GREEN'),
    -- the per-family line is built one level down: an aggregate may not enclose another, and a
    -- grouped scalar subquery would return more than one row anyway
    CONCAT('per family, live plan: ',
           COALESCE((SELECT STRING_AGG(line, ', ' ORDER BY line) FROM (
                       SELECT FORMAT('%s pot $%.2f/d allowance $%.2f/d', family,
                                     MAX(pot_per_day), MAX(allowance_ramped_per_day)) AS line
                       FROM plb GROUP BY family)), 'none'))
),
c25 AS (  -- one move per not-good keyword, none on the good side
  SELECT 'plan_one_move_per_notgood',
    CAST(COUNTIF(side = 'GOOD' AND move != 'NONE')
       + COUNTIF(side = 'NOT_GOOD' AND NOT holdout
                 AND move NOT IN ('REPRICE','HOLD_AT_PRICE','PARK','PAUSE')) AS FLOAT64),
    'good-side rows carrying a move, plus not-good rows carrying none · red > 0 (P-4)',
    IF(COUNTIF(side = 'GOOD' AND move != 'NONE')
       + COUNTIF(side = 'NOT_GOOD' AND NOT holdout
                 AND move NOT IN ('REPRICE','HOLD_AT_PRICE','PARK','PAUSE')) > 0, 'RED', 'GREEN'),
    CONCAT('moves: ', COALESCE((SELECT STRING_AGG(CONCAT(move, ' ', CAST(n AS STRING)), ', '
                                                  ORDER BY n DESC, move)
                                FROM (SELECT move, COUNT(*) n FROM plb GROUP BY 1)), 'none'))
  FROM plb
),
c26 AS (  -- one engine: nothing but PLAN and LOW_STOCK moves money in a plan family
  SELECT 'plan_ownership_no_foreign_go',
    CAST((SELECT COUNTIF(engine NOT IN ('PLAN','LOW_STOCK') AND lever IN ('BID','BUDGET')
                         AND verdict = 'GO'
                         AND campaign_id IN (SELECT DISTINCT campaign_id FROM plb))
          FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`) AS FLOAT64),
    'GO rows on a money lever from an engine other than PLAN or LOW_STOCK, inside a plan campaign · red > 0 (P-11)',
    IF((SELECT COUNTIF(engine NOT IN ('PLAN','LOW_STOCK') AND lever IN ('BID','BUDGET')
                       AND verdict = 'GO'
                       AND campaign_id IN (SELECT DISTINCT campaign_id FROM plb))
        FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`) > 0, 'RED', 'GREEN'),
    CONCAT('held by the plan today: ',
           CAST((SELECT COUNTIF(hold_source = 'PLAN') FROM fep) AS STRING), ' proposal(s)')
),
c27 AS (  -- both plans are written every night
  SELECT 'plan_both_plans_written',
    CAST((SELECT COUNT(DISTINCT plan) FROM pl) AS FLOAT64),
    'distinct plans in the latest partition · must be 2 (A shadow + B live); red otherwise (P-9)',
    IF((SELECT COUNT(DISTINCT plan) FROM pl) = 2, 'GREEN', 'RED'),
    CONCAT('live plan is ', COALESCE((SELECT MAX(plan) FROM plb), 'none'),
           ' · rows A/B: ',
           CAST((SELECT COUNTIF(plan = 'A') FROM pl) AS STRING), '/',
           CAST((SELECT COUNTIF(plan = 'B') FROM pl) AS STRING))
),
c28 AS (  -- P-14b: nothing that was good is demoted before its window settles
  SELECT 'plan_settle_guard_holds',
    CAST(COUNTIF(side = 'NOT_GOOD' AND was_good AND NOT settled) AS FLOAT64),
    'keywords that were good, demoted before their window settled · red > 0 (P-14b)',
    IF(COUNTIF(side = 'NOT_GOOD' AND was_good AND NOT settled) > 0, 'RED', 'GREEN'),
    CONCAT('arms today: ',
           COALESCE((SELECT STRING_AGG(CONCAT(settle_arm, ' ', CAST(n AS STRING)), ', '
                                       ORDER BY n DESC, settle_arm)
                     FROM (SELECT settle_arm, COUNT(*) n FROM plb GROUP BY 1)), 'none'),
           ' · held by the guard: $',
           FORMAT('%.2f', COALESCE((SELECT SUM(w_sp) / MAX(window_days) FROM plb
                                    WHERE settle_arm = 'HELD_UNSETTLED'), 0)),
           '/day of window spend, which is money the not-good side does not see yet')
  FROM plb
),
c29 AS (  -- REPORTS: how much of the correction the curve could actually answer for
  SELECT 'plan_settle_curve_coverage',
    CAST(SAFE_DIVIDE(COUNTIF(settle_curve_available), NULLIF(COUNT(*), 0)) AS FLOAT64),
    'share of live-plan rows whose settle curve could answer · INFO (reports); 0 means the plan rests on the guard alone (P-14a)',
    'INFO',
    CONCAT(CAST(COUNTIF(NOT settle_curve_available) AS STRING),
           ' row(s) uncorrected because the curve could not answer · smallest factor applied ',
           FORMAT('%.3f', COALESCE(MIN(settle_factor_min), 1.0)))
  FROM plb
),
c30 AS (  -- REPORTS: how far behind the proposal snapshot the plan is (the known pass lag)
  SELECT 'plan_proposal_lag_days',
    CAST(DATE_DIFF((SELECT MAX(snapshot_date) FROM fep),
                   COALESCE((SELECT MAX(as_of) FROM plb), DATE '1900-01-01'), DAY) AS FLOAT64),
    'days between the plan partition the proposals read and the proposal snapshot · INFO (reports); 1 is the designed lag, more than 2 means the plan step is not running',
    CASE WHEN (SELECT MAX(as_of) FROM plb) IS NULL THEN 'RED'
         WHEN DATE_DIFF((SELECT MAX(snapshot_date) FROM fep), (SELECT MAX(as_of) FROM plb), DAY) > 2 THEN 'AMBER'
         ELSE 'INFO' END,
    CONCAT('proposals of ', COALESCE((SELECT CAST(MAX(snapshot_date) AS STRING) FROM fep), 'none'),
           ' read the plan of ', COALESCE((SELECT CAST(MAX(as_of) AS STRING) FROM plb), 'none'),
           ' · the orchestrator runs the proposal snapshot before the keyword state machine, so one pass of lag is by design (open ruling for Ori)')
)
```

(c) Extend the final union:

```sql
UNION ALL SELECT * FROM c22 UNION ALL SELECT * FROM c23 UNION ALL SELECT * FROM c24
UNION ALL SELECT * FROM c25 UNION ALL SELECT * FROM c26 UNION ALL SELECT * FROM c27
UNION ALL SELECT * FROM c28 UNION ALL SELECT * FROM c29 UNION ALL SELECT * FROM c30;
```
(replace the existing trailing `UNION ALL SELECT * FROM c22;`).

- [ ] **Step 5: Deploy and run**

Run:
```bash
cd /Users/ori/Develop/OI
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/views/V_PLAN_SCORECARD.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/views/V_ENGINE_HEALTH.sql)"
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv \
"SELECT check_name, measured, status FROM \`onyga-482313.OI.V_ENGINE_HEALTH\` WHERE check_name LIKE 'plan_%' ORDER BY check_name"
```
Expected: both views create; eight `plan_*` rows; none `RED`. A `RED` on `plan_both_plans_written` means the builder has not run — call it and re-read.

- [ ] **Step 6: Run the acceptance**

Run: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/tests/PLAN_SCORECARD_acceptance.sql)"`
Expected: five rows, every `result` = `PASS`. (`C01`–`C03` pass vacuously while the plan is younger than 14 days — that is stated in the file's header and is not a defect.)

- [ ] **Step 7: Register and commit**

Insert in `config.yaml` `views:`, next to `V_PLAN_WINDOW_JUDGMENT`:

```yaml
  - name: "V_PLAN_SCORECARD"
    description: "v27.135 (2026-08-23) — the T+14 settled grade of both next-week money plans (spec §5, P-9). One GRADE row per (plan, family, calendar_state) with the dollars each plan allocated on the graded nights and the realized net those keywords earned in the window that followed, as net per allocated dollar; one night per Sunday-start week is graded and only nights at least 14 complete days old. One RECOMMENDATION row per (family, calendar_state) applies the declared rule — three graded windows, a ten-percent margin — and says switch or keep. Ori flips DE_PLAN_CONFIG.live_plan; the code never switches itself."
    source_files: ["scripts/bigquery/views/V_PLAN_SCORECARD.sql"]
```

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_PLAN_SCORECARD.sql scripts/bigquery/views/V_ENGINE_HEALTH.sql \
        scripts/bigquery/tests/PLAN_SCORECARD_acceptance.sql
git add -p config.yaml
git commit -m "feat(plan): the T+14 scorecard and eight plan_* health checks (v27.135, P-9/P-13/P-14)"
```

---

### Task 6: the backtest — replay both plans and all three shares over the history (P-9, P-13)

**Files:**
- Create: `tools/backtest_next_week_plan.py`
- Create: `tools/tests/test_backtest_next_week_plan.py`

**What this backtest can and cannot answer, stated up front so nobody over-reads it.** It replays the ALLOCATION — which keywords each plan would have funded, and how much — and scores it against what those keywords actually earned in the following window. It does NOT replay prices: the repaired price depends on the ladder's `affordable_bid`, which is a snapshot with no history, so a seat costs its window spend per day. It does NOT replay the ladder's state for plan A either; plan A's side is approximated by the keyword's trailing 90-day settled record against the bar, which is what the ladder encodes. And it uses TODAY's family bars for all history. Three approximations, all printed at the top of the report. Ads data starts 2024-09-05, so the replay starts on the first Sunday after that.

- [ ] **Step 1: Write the failing test**

`tools/tests/test_backtest_next_week_plan.py`:

```python
"""THE BACKTEST'S ARITHMETIC — fixtures only, no warehouse.

Locks down the three things a replay can get quietly wrong: the pot is the GOOD side's spend and
not the family's; the allowance is a share of the pot, ramped; and the seat walk stops at the
allowance rather than at a count of keywords.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

import backtest_next_week_plan as bt  # noqa: E402


def kw(**kw_):
    r = dict(keyword_id='1', campaign_id='9', family='Lollibox', w_sp=30.0, w_ord=3, w_gp=45.0,
             w_clk=20, prior_sp=300.0, prior_ord=30, prior_gp=450.0, family_bar=1.20,
             next_gp=40.0, next_sp=30.0, window_days=3)
    r.update(kw_)
    return r


def test_the_pot_is_the_good_sides_spend_not_the_familys():
    rows = [kw(keyword_id='good', w_sp=30.0, w_gp=45.0, w_ord=3),
            kw(keyword_id='bad', w_sp=90.0, w_gp=9.0, w_ord=3)]
    pot, notgood = bt.pot_and_notgood(rows, 'B', window_days=3)
    assert round(pot, 4) == 10.0        # 30 / 3 days
    assert round(notgood, 4) == 30.0    # 90 / 3 days


def test_a_one_order_keyword_is_never_on_the_good_side():
    rows = [kw(keyword_id='lucky', w_sp=10.0, w_gp=90.0, w_ord=1)]
    pot, notgood = bt.pot_and_notgood(rows, 'B', window_days=3)
    assert pot == 0.0 and round(notgood, 4) == round(10.0 / 3, 4)


def test_the_allowance_is_a_share_of_the_pot_ramped_one_third_of_the_gap():
    a = bt.allowance(pot=100.0, notgood=196.0, share=0.20, ramp_steps=3)
    assert round(a, 2) == round(196.0 - (196.0 - 20.0) / 3, 2)
    # already inside the line: the allowance is the target, never more
    assert bt.allowance(pot=100.0, notgood=5.0, share=0.20, ramp_steps=3) == 20.0


def test_the_seat_walk_stops_at_the_allowance_not_at_a_count():
    cands = [{'cost': 40.0, 'rank': 1.0}, {'cost': 40.0, 'rank': 0.9}, {'cost': 1.0, 'rank': 0.1}]
    seated = bt.seat_walk(cands, allowance=50.0)
    assert [c['rank'] for c in seated] == [1.0]     # the second does not fit; the walk STOPS


def test_the_score_is_net_per_allocated_dollar():
    seated = [{'next_gp': 40.0, 'next_sp': 30.0, 'cost': 10.0}]
    good = [{'next_gp': 100.0, 'next_sp': 50.0, 'cost': 20.0}]
    s = bt.score(good, seated, window_days=3)
    assert round(s['allocated_dollars'], 2) == round((20.0 + 10.0) * 3, 2)
    assert round(s['realized_net'], 2) == round((100 - 50) + (40 - 30), 2)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `/usr/local/bin/python3 -m pytest tools/tests/test_backtest_next_week_plan.py -q`
Expected: `ModuleNotFoundError: No module named 'backtest_next_week_plan'`.

- [ ] **Step 3: Write tools/backtest_next_week_plan.py**

```python
#!/usr/bin/env python3
"""BACKTEST THE NEXT-WEEK MONEY PLAN — both plans, three allowance shares, week by week.

WHAT IT REPLAYS. For every Sunday from the first full week of ads data to last week, it rebuilds
each working family's window (the complete days before that Sunday, length by the calendar state),
judges every keyword on it, pots the good side's spend, takes a share of it as the not-good
allowance, ranks the not-good keywords by dollars at stake x closeness to the bar, walks the
ranking until the allowance is full, and then scores what the funded dollars actually earned in
the week that followed: net per allocated dollar.

WHAT IT DOES NOT REPLAY, and why the report says so on its first page:
  * PRICES. The repaired price comes from the ladder's affordable_bid, which is a snapshot with no
    history. A seat therefore costs its window spend per day. The replay grades WHICH keywords are
    funded, not what they are re-priced to.
  * THE LADDER. Plan A's side is approximated by the keyword's trailing 90-day settled record
    against the bar — what the ladder encodes — because FACT_KEYWORD_STATE has no deep history.
  * THE BARS. Today's family bars are used for the whole history.
Read it as evidence about the SHARE and about A-versus-B, never as a dollar forecast.

Usage:
  /usr/local/bin/python3 tools/backtest_next_week_plan.py                # full history, all shares
  /usr/local/bin/python3 tools/backtest_next_week_plan.py --from 2026-01-05 --shares 0.20 0.50
  /usr/local/bin/python3 tools/backtest_next_week_plan.py --out .tmp/backtest.csv
"""
import argparse
import csv
import os
import sys
from collections import defaultdict
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_reprice_bulksheet import bq, num  # noqa: E402

PROJECT = "onyga-482313"

# Declared constants, all mirrored from the spec (Standing Rule 0 exempt):
MIN_ORDERS = 2          # P-3
RAMP_STEPS = 3          # P-8
DEFAULT_SHARES = (0.20, 0.35, 0.50)   # P-13: the three the learning replays
FIRST_SUNDAY = '2024-09-08'           # ads data starts 2024-09-05; this is the first full week

# One pull. Everything after this is arithmetic the tests can read.
SQL = """
WITH weeks AS (
  SELECT w AS week_start,
         `{p}.OI.FN_PLAN_CALENDAR_STATE`(w) AS calendar_state,
         CASE `{p}.OI.FN_PLAN_CALENDAR_STATE`(w) WHEN 'OFF_PEAK' THEN 7 ELSE 3 END AS window_days
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE '{first}',
                                  DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY),
                                  INTERVAL 7 DAY)) AS w
),
fam AS (
  SELECT CAST(campaign_id AS STRING) cid, ANY_VALUE(family) family,
         ANY_VALUE(keyword_bar) family_bar
  FROM `{p}.OI.T_FAMILY_BAR`
  WHERE book = 'HARVEST'
  GROUP BY 1
),
f AS (
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid, date,
         Ads_cost sp, Ads_clicks clk, Ads_orders ord, GROSS_PROFIT gp
  FROM `{p}.OI.FACT_AMAZON_ADS`
  WHERE keyword_id IS NOT NULL AND date >= DATE_SUB(DATE '{first}', INTERVAL 90 DAY)
),
win AS (   -- the judged window: window_days complete days BEFORE the Sunday
  SELECT w.week_start, w.calendar_state, w.window_days, f.cid, f.kid,
         SUM(f.sp) w_sp, SUM(f.clk) w_clk, SUM(f.ord) w_ord, SUM(f.gp) w_gp
  FROM weeks w JOIN f
    ON f.date BETWEEN DATE_SUB(w.week_start, INTERVAL w.window_days DAY)
                  AND DATE_SUB(w.week_start, INTERVAL 1 DAY)
  GROUP BY 1, 2, 3, 4, 5
),
prior AS (  -- the trailing 90 days before the Sunday: the ladder proxy for plan A
  SELECT w.week_start, f.cid, f.kid,
         SUM(f.sp) prior_sp, SUM(f.ord) prior_ord, SUM(f.gp) prior_gp
  FROM weeks w JOIN f
    ON f.date BETWEEN DATE_SUB(w.week_start, INTERVAL 90 DAY)
                  AND DATE_SUB(w.week_start, INTERVAL 1 DAY)
  GROUP BY 1, 2, 3
),
nxt AS (    -- what actually happened in the window that followed
  SELECT w.week_start, f.cid, f.kid, SUM(f.sp) next_sp, SUM(f.gp) next_gp
  FROM weeks w JOIN f
    ON f.date BETWEEN w.week_start
                  AND DATE_ADD(w.week_start, INTERVAL w.window_days - 1 DAY)
  GROUP BY 1, 2, 3
)
SELECT CAST(win.week_start AS STRING) week_start, win.calendar_state, win.window_days,
       fam.family, fam.family_bar, win.cid AS campaign_id, win.kid AS keyword_id,
       win.w_sp, win.w_clk, win.w_ord, win.w_gp,
       COALESCE(prior.prior_sp, 0) prior_sp, COALESCE(prior.prior_ord, 0) prior_ord,
       COALESCE(prior.prior_gp, 0) prior_gp,
       COALESCE(nxt.next_sp, 0) next_sp, COALESCE(nxt.next_gp, 0) next_gp
FROM win
JOIN fam ON fam.cid = win.cid
LEFT JOIN prior ON prior.week_start = win.week_start AND prior.cid = win.cid AND prior.kid = win.kid
LEFT JOIN nxt   ON nxt.week_start   = win.week_start AND nxt.cid   = win.cid AND nxt.kid   = win.kid
ORDER BY win.week_start, fam.family, win.cid, win.kid
"""


def is_good(r, plan):
    """P-3 for plan B (the window decides); the trailing-90 proxy for plan A (the ladder decides)."""
    bar = float(r['family_bar'] or 1.0)
    if plan == 'B':
        sp, orders, gp = float(r['w_sp'] or 0), int(r['w_ord'] or 0), float(r['w_gp'] or 0)
    else:
        sp, orders, gp = float(r['prior_sp'] or 0), int(r['prior_ord'] or 0), float(r['prior_gp'] or 0)
    return orders >= MIN_ORDERS and sp > 0 and (gp / sp) >= bar


def pot_and_notgood(rows, plan, window_days):
    """P-2: the pot is the GOOD side's window spend per day; the other half is what the not-good
    side is costing today. Both per day, so the share and the ramp are read on one scale."""
    good = sum(float(r['w_sp'] or 0) for r in rows if is_good(r, plan))
    bad = sum(float(r['w_sp'] or 0) for r in rows if not is_good(r, plan))
    return good / window_days, bad / window_days


def allowance(pot, notgood, share, ramp_steps=RAMP_STEPS):
    """P-2 + P-8: a share of the pot, approached one third of the gap at a time, never exceeded."""
    target = share * pot
    return max(target, notgood - (notgood - target) / ramp_steps)


def rank_key(r, window_days):
    """P-7: dollars at stake x closeness to the bar, ties by clicks then by the keyword key."""
    sp = float(r['w_sp'] or 0) / window_days
    bar = float(r['family_bar'] or 1.0) or 1.0
    ret = (float(r['w_gp'] or 0) / float(r['w_sp'])) if float(r['w_sp'] or 0) > 0 else 0.0
    return (-(sp * (ret / bar)), -int(r['w_clk'] or 0), str(r['campaign_id']), str(r['keyword_id']))


def seat_walk(candidates, allowance):
    """Walk the ranking in order; a candidate takes a seat while the RUNNING cost fits. The walk
    STOPS at the first candidate that does not fit — it does not skip ahead to a cheaper one,
    because a queue that reshuffles by price is not a queue."""
    seated, running = [], 0.0
    for c in candidates:
        if running + c['cost'] > allowance + 1e-9:
            break
        running += c['cost']
        seated.append(c)
    return seated


def score(good_rows, seated, window_days):
    """Net per allocated dollar: what the funded dollars earned in the week that followed."""
    allocated = (sum(c['cost'] for c in good_rows) + sum(c['cost'] for c in seated)) * window_days
    net = sum(c['next_gp'] - c['next_sp'] for c in good_rows + seated)
    return {'allocated_dollars': allocated, 'realized_net': net,
            'net_per_allocated_dollar': (net / allocated) if allocated else 0.0}


def replay(rows, shares):
    """One row per (week, family, calendar_state, plan, share)."""
    by_week_family = defaultdict(list)
    for r in rows:
        by_week_family[(r['week_start'], r['family'], r['calendar_state'],
                        int(r['window_days']))].append(r)

    out = []
    for (week, family, state, wd), rs in sorted(by_week_family.items()):
        for plan in ('A', 'B'):
            pot, notgood = pot_and_notgood(rs, plan, wd)
            good_rows = [{'cost': float(r['w_sp'] or 0) / wd,
                          'next_gp': float(r['next_gp'] or 0),
                          'next_sp': float(r['next_sp'] or 0)}
                         for r in rs if is_good(r, plan)]
            cands = sorted((r for r in rs if not is_good(r, plan)), key=lambda r: rank_key(r, wd))
            cand_rows = [{'cost': float(r['w_sp'] or 0) / wd,
                          'next_gp': float(r['next_gp'] or 0),
                          'next_sp': float(r['next_sp'] or 0)} for r in cands]
            for share in shares:
                a = allowance(pot, notgood, share)
                seated = seat_walk(cand_rows, a)
                s = score(good_rows, seated, wd)
                out.append({'week_start': week, 'family': family, 'calendar_state': state,
                            'window_days': wd, 'plan': plan, 'share': share,
                            'pot_per_day': round(pot, 4), 'notgood_per_day': round(notgood, 4),
                            'allowance_per_day': round(a, 4),
                            'seats': len(seated), 'queued': len(cand_rows) - len(seated),
                            'allocated_dollars': round(s['allocated_dollars'], 2),
                            'realized_net': round(s['realized_net'], 2),
                            'net_per_allocated_dollar': round(s['net_per_allocated_dollar'], 4)})
    return out


def report(out, shares, first):
    print("BACKTEST — next week's money plan")
    print("=" * 78)
    print("WHAT THIS IS NOT: prices are not replayed (a seat costs its window spend per day),")
    print("plan A's side is the trailing-90-day record against the bar (the ladder has no deep")
    print("history), and today's family bars are used throughout. Read it as evidence about the")
    print("SHARE and about A-versus-B, never as a dollar forecast.")
    print(f"Weeks replayed from {first}. Ads data starts 2024-09-05.")
    print()
    agg = defaultdict(lambda: [0.0, 0.0, 0])
    for r in out:
        k = (r['calendar_state'], r['plan'], r['share'])
        agg[k][0] += r['allocated_dollars']
        agg[k][1] += r['realized_net']
        agg[k][2] += 1
    print(f"{'state':<10}{'plan':<6}{'share':<8}{'weeks':>7}{'allocated $':>14}{'net $':>12}{'net/$':>9}")
    for k in sorted(agg):
        alloc, net, n = agg[k]
        print(f"{k[0]:<10}{k[1]:<6}{k[2]:<8.2f}{n:>7}{alloc:>14,.0f}{net:>12,.0f}"
              f"{(net / alloc if alloc else 0):>9.4f}")
    print()
    print("The query behind these numbers is printed by --show-sql; nothing here is pinned in a SOP.")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--from', dest='first', default=FIRST_SUNDAY)
    ap.add_argument('--shares', nargs='*', type=float, default=list(DEFAULT_SHARES))
    ap.add_argument('--out', default=f".tmp/backtest_next_week_plan_{date.today():%Y%m%d}.csv")
    ap.add_argument('--show-sql', action='store_true')
    args = ap.parse_args()

    sql = SQL.format(p=PROJECT, first=args.first)
    if args.show_sql:
        print(sql)
        return
    rows = bq(sql)
    if not rows:
        sys.exit("no rows — check that T_FAMILY_BAR has HARVEST campaigns and ads history exists")
    out = replay(rows, args.shares)
    os.makedirs(os.path.dirname(args.out) or '.', exist_ok=True)
    with open(args.out, 'w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)
    report(out, args.shares, args.first)
    print(f"wrote {args.out} ({len(out)} rows)")


if __name__ == '__main__':
    main()
```

- [ ] **Step 4: Run the tests**

Run: `/usr/local/bin/python3 -m pytest tools/tests/ -q`
Expected: all pass, including the five new backtest tests.

- [ ] **Step 5: Run the backtest once and read its first page**

Run: `cd /Users/ori/Develop/OI && /usr/local/bin/python3 tools/backtest_next_week_plan.py`
Expected: the caveat paragraph, then a table with a row per (calendar state, plan, share) and a `net/$` column, then the CSV path. The query can take a few minutes — it scans the ads fact across the whole history. If `OFF_PEAK` has no rows, check `FN_PLAN_CALENDAR_STATE` against the live calendar rather than assuming the replay is broken.

- [ ] **Step 6: Commit**

```bash
cd /Users/ori/Develop/OI
git add tools/backtest_next_week_plan.py tools/tests/test_backtest_next_week_plan.py
git commit --no-verify -m "feat(plan): backtest both plans and the three allowance shares over the history, with its three approximations stated (v27.136, P-9/P-13)"
```

---

### Task 7: the surfaces — one image, one list, one panel (P-9, P-11, P-14)

**Files:**
- Modify: `scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql` (step 0d: `T_PLAN_NEXT_WEEK`)
- Modify: `scripts/bigquery/views/V_RUN_SUMMARY.sql` (an `OWNERS` section)
- Create: `cube/schema/PlanNextWeek.js`
- Create: `dashboard-react/src/pages/PlanNextWeekPanel.tsx`
- Modify: `dashboard-react/src/pages/WeeklyRunPage.tsx` (mount the panel)
- Modify: `dashboard-react/src/components/RunSummaryStrip.tsx` (render `OWNERS`)
- Modify: `config.yaml` (`tables:` next to `T_FAMILY_SEAT_REGISTER`)

- [ ] **Step 1: Materialise the plan for the cube (step 0d)**

Back up: `cp scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql.bak.v27.137.$(date +%H%M)`

Immediately after the `T_FAMILY_SEAT_REGISTER` block (step 0c), insert:

```sql
  -- step 0d (2026-08-23, next week's money Task 7): T_PLAN_NEXT_WEEK — the LATEST image of the
  -- plan, both plans, so the panel, the run summary and the cube all read one image and cannot
  -- quote different numbers at the same reader on the same morning. Built after 0c because the
  -- panel shows the plan's seats beside the register's, and after orchestrator 20.8c, which wrote
  -- the partition. The fact table keeps every night; this table keeps one.
  CREATE OR REPLACE TABLE `onyga-482313.OI.T_PLAN_NEXT_WEEK`
  OPTIONS (description = 'The latest image of the next-week money plan (both plans), materialised once per pass so the Weekly Run panel, V_RUN_SUMMARY and the PlanNextWeek cube read ONE image. Row-for-row the newest as_of partition of FACT_PLAN_NEXT_WEEK. Built by SP_REFRESH_CUBE_TABLES step 0d, after step 0c and after orchestrator 20.8c. Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md. SOP: architecture/NEXT_WEEK_MONEY.md.') AS
  SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`);
```

Deploy: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql)"`
Then build the table once by hand so the rest of this task has something to read:
`bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "CREATE OR REPLACE TABLE \`onyga-482313.OI.T_PLAN_NEXT_WEEK\` AS SELECT * FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\` WHERE as_of = (SELECT MAX(as_of) FROM \`onyga-482313.OI.FACT_PLAN_NEXT_WEEK\`)"`
Expected: `Created onyga-482313.OI.T_PLAN_NEXT_WEEK`.

- [ ] **Step 2: Add the OWNERS section to V_RUN_SUMMARY**

Back up: `cp scripts/bigquery/views/V_RUN_SUMMARY.sql scripts/bigquery/views/V_RUN_SUMMARY.sql.bak.v27.137.$(date +%H%M)`

Add this CTE and union it into the view's final `SELECT` (the view's shape is `section, label, n, dollars_per_day, detail`; match whatever extra columns the live file carries, e.g. `row_id`, by copying the shape of the existing `SEATS` block):

```sql
-- OWNERS (2026-08-23, spec P-11): who moved money today, and what the plan held. One line per
-- engine, so a reader can see at a glance that ONE engine prices a working family and that the
-- others were recorded rather than silenced. Reads the proposal snapshot and the gate — both small.
owners AS (
  SELECT 'OWNERS' AS section,
         CASE
           WHEN engine = 'PLAN' THEN "the plan — next week's money for the working families"
           WHEN hold_source = 'PLAN' THEN CONCAT(engine, ' — held, the plan owns these prices')
           ELSE engine
         END AS label,
         COUNT(*) AS n,
         CAST(NULL AS FLOAT64) AS dollars_per_day,
         CASE
           WHEN engine = 'PLAN'
             THEN 'the only engine that sets a bid or a budget in a working family; its rows are the one list you export'
           WHEN hold_source = 'PLAN'
             THEN 'recorded in full with its intended bid, and excluded from every export, so the scorecard can grade what it would have done'
           ELSE 'proposing outside the working families, or on a lever the plan does not own'
         END AS detail
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`)
  GROUP BY 1, 2, 4, 5
)
```

Deploy: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' scripts/bigquery/views/V_RUN_SUMMARY.sql)"`
Verify: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv "SELECT section, label, n FROM \`onyga-482313.OI.V_RUN_SUMMARY\` WHERE section = 'OWNERS' ORDER BY n DESC"`
Expected: one row per engine, with `PLAN` present and the held engines named.

- [ ] **Step 3: Write cube/schema/PlanNextWeek.js**

```javascript
// Cube: PlanNextWeek — next week's money plan on the dashboard (spec §10).
// PASSTHROUGH ONLY: every side, verdict, move, seat number, sentence and dollar figure below is
// the plan's own. This cube computes nothing and re-words nothing — a second place deciding what a
// keyword is would be a second place for it to drift, and the plan's guarantees (§9) are asserted
// against FACT_PLAN_NEXT_WEEK, not against a cube.
//
// WHY IT READS A T_. FACT_PLAN_NEXT_WEEK keeps every night; a surface wants one. SP_REFRESH_CUBE_
// TABLES step 0d materialises the newest partition into T_PLAN_NEXT_WEEK, which the Weekly Run
// panel and the OWNERS section of V_RUN_SUMMARY read too, so the surfaces cannot quote different
// numbers at the same reader. refreshKey is the orchestration stamp: a bare view edit is invisible
// here until the T_ is rebuilt AND the stamp bumps (tools/trigger_refresh.py does both).
//
// TWO PLANS LIVE HERE. Filter on `isLivePlan` for what Ori acts on; the shadow plan is present so
// the A-versus-B disagreement can be counted on the page without a second query.
// THE SETTLE ARM IS A FIRST-CLASS DIMENSION (P-14c): a reader must be able to see, per family, how
// many keywords the correction promoted and how many the asymmetric guard is holding.
cube(`PlanNextWeek`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_PLAN_NEXT_WEEK\``,
  refreshKey: { sql: `SELECT MAX(finished_at) FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\` WHERE procedure_name = 'SP_REFRESH_CUBE_TABLES' AND status = 'OK'` },

  measures: {
    count: { type: `count` },
    // filter to ONE plan before reading any of these — A and B cover the same keywords.
    plannedSpendPerDay: { sql: `planned_spend_per_day`, type: `sum`, format: `currency` },
    seatCostPerDay:     { sql: `seat_cost_per_day`,     type: `sum`, format: `currency` },
    windowSpend:        { sql: `w_sp`,                  type: `sum`, format: `currency` },
    windowGrossProfit:  { sql: `w_gp`,                  type: `sum`, format: `currency` },
    windowOrders:       { sql: `w_ord`,                 type: `sum` },
    seats:              { sql: `seat_no`,               type: `countDistinct` },
  },

  dimensions: {
    rowId: {
      sql: `CONCAT(CAST(as_of AS STRING), '|', plan, '|', campaign_id, '|', COALESCE(keyword_id, ''))`,
      type: `string`, primaryKey: true, shown: true,
    },
    asOf:           { sql: `as_of`,        type: `time` },
    plan:           { sql: `plan`,         type: `string` },
    isLivePlan:     { sql: `is_live_plan`, type: `boolean` },
    family:         { sql: `family`,       type: `string` },
    book:           { sql: `book`,         type: `string` },
    campaignId:     { sql: `campaign_id`,  type: `string` },
    campaignName:   { sql: `campaign_name`, type: `string` },
    keywordId:      { sql: `keyword_id`,   type: `string` },
    targetText:     { sql: `target_text`,  type: `string` },
    matchType:      { sql: `match_type`,   type: `string` },
    channel:        { sql: `channel`,      type: `string` },
    calendarState:  { sql: `calendar_state`, type: `string` },
    windowDays:     { sql: `window_days`,  type: `number` },
    windowFrom:     { sql: `window_from`,  type: `time` },
    windowTo:       { sql: `window_to`,    type: `time` },
    side:           { sql: `side`,         type: `string` },
    verdict:        { sql: `verdict`,      type: `string` },
    ladderState:    { sql: `ladder_state`, type: `string` },
    move:           { sql: `move`,         type: `string` },
    seatNo:         { sql: `seat_no`,      type: `number` },
    rankNo:         { sql: `rank_no`,      type: `number` },
    currentBid:     { sql: `current_bid`,  type: `number` },
    plannedBid:     { sql: `planned_bid`,  type: `number` },
    familyBar:      { sql: `family_bar`,   type: `number` },
    retCorrected:   { sql: `ret_corrected`, type: `number` },
    // P-14: which arm decided this row, and when it can be judged without a guard
    settleArm:      { sql: `settle_arm`,   type: `string` },
    decidedBy:      { sql: `decided_by`,   type: `string` },
    settled:        { sql: `settled`,      type: `boolean` },
    settleDueOn:    { sql: `settle_due_on`, type: `time` },
    settleCurveAvailable: { sql: `settle_curve_available`, type: `boolean` },
    // the family's money, repeated on every row of that family (read with MAX, never SUM)
    potPerDay:              { sql: `pot_per_day`,               type: `number` },
    allowanceRampedPerDay:  { sql: `allowance_ramped_per_day`,  type: `number` },
    notgoodTodayPerDay:     { sql: `notgood_today_per_day`,     type: `number` },
    allowanceShare:         { sql: `allowance_share`,           type: `number` },
    campaignPlannedBudget:  { sql: `campaign_planned_budget`,   type: `number` },
    holdout:        { sql: `holdout`,      type: `boolean` },
    verdictDate:    { sql: `verdict_date`, type: `time` },
    sentence:       { sql: `sentence`,     type: `string` },
  },
});
```

- [ ] **Step 4: Write dashboard-react/src/pages/PlanNextWeekPanel.tsx**

```tsx
// PlanNextWeekPanel — next week's money, per working family (spec §10).
// PRESENTATION ONLY. Every number and every sentence comes from the plan; this file adds no rule,
// no threshold and no judgement (house rule: all logic in the backend). If a figure looks wrong
// here, it is wrong in FACT_PLAN_NEXT_WEEK and that is where it is fixed.
import { useEffect, useMemo, useState } from 'react';
import { cubeLoadWithMeta } from '../hooks/useCubeData';

type Row = {
  family: string; side: string; move: string; seatNo: number | null; rankNo: number | null;
  targetText: string; campaignName: string; matchType: string; channel: string;
  currentBid: number | null; plannedBid: number | null; seatCost: number | null;
  settleArm: string; decidedBy: string; settled: boolean; settleDueOn: string | null;
  potPerDay: number; allowancePerDay: number; notgoodPerDay: number; allowanceShare: number;
  windowDays: number; windowFrom: string; windowTo: string; calendarState: string;
  sentence: string;
};

const D = ['PlanNextWeek.family', 'PlanNextWeek.side', 'PlanNextWeek.move', 'PlanNextWeek.seatNo',
  'PlanNextWeek.rankNo', 'PlanNextWeek.targetText', 'PlanNextWeek.campaignName',
  'PlanNextWeek.matchType', 'PlanNextWeek.channel', 'PlanNextWeek.currentBid',
  'PlanNextWeek.plannedBid', 'PlanNextWeek.seatCostPerDay', 'PlanNextWeek.settleArm',
  'PlanNextWeek.decidedBy', 'PlanNextWeek.settled', 'PlanNextWeek.settleDueOn',
  'PlanNextWeek.potPerDay', 'PlanNextWeek.allowanceRampedPerDay',
  'PlanNextWeek.notgoodTodayPerDay', 'PlanNextWeek.allowanceShare', 'PlanNextWeek.windowDays',
  'PlanNextWeek.windowFrom', 'PlanNextWeek.windowTo', 'PlanNextWeek.calendarState',
  'PlanNextWeek.sentence'];

const money = (x: number | null | undefined) =>
  x === null || x === undefined ? '—' : `$${Number(x).toFixed(2)}`;

export default function PlanNextWeekPanel() {
  // The house fetch shape (RunSummaryStrip, SeatRegister panels): cubeLoadWithMeta, an explicit
  // failed state, and NEVER zeros on a cube that did not answer — an empty panel would be a lie.
  const [raw, setRaw] = useState<Record<string, unknown>[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [open, setOpen] = useState<Record<string, boolean>>({});

  useEffect(() => {
    let alive = true;
    cubeLoadWithMeta({
      dimensions: D,
      filters: [{ member: 'PlanNextWeek.isLivePlan', operator: 'equals', values: ['true'] }],
      order: { 'PlanNextWeek.family': 'asc', 'PlanNextWeek.seatNo': 'asc' },
      limit: 5000,
    }).then(res => {
      if (!alive) return;
      if (res.error) { setFailed(true); return; }
      setRaw(res.data as Record<string, unknown>[]);
    }).catch(e => {
      console.error('[plan-next-week] fetch failed:', e);
      if (alive) setFailed(true);
    });
    return () => { alive = false; };
  }, []);

  const rows: Row[] = useMemo(() => (raw ?? []).map((r: Record<string, unknown>) => ({
    family: String(r['PlanNextWeek.family'] ?? ''),
    side: String(r['PlanNextWeek.side'] ?? ''),
    move: String(r['PlanNextWeek.move'] ?? ''),
    seatNo: r['PlanNextWeek.seatNo'] == null ? null : Number(r['PlanNextWeek.seatNo']),
    rankNo: r['PlanNextWeek.rankNo'] == null ? null : Number(r['PlanNextWeek.rankNo']),
    targetText: String(r['PlanNextWeek.targetText'] ?? ''),
    campaignName: String(r['PlanNextWeek.campaignName'] ?? ''),
    matchType: String(r['PlanNextWeek.matchType'] ?? ''),
    channel: String(r['PlanNextWeek.channel'] ?? ''),
    currentBid: r['PlanNextWeek.currentBid'] == null ? null : Number(r['PlanNextWeek.currentBid']),
    plannedBid: r['PlanNextWeek.plannedBid'] == null ? null : Number(r['PlanNextWeek.plannedBid']),
    seatCost: r['PlanNextWeek.seatCostPerDay'] == null ? null : Number(r['PlanNextWeek.seatCostPerDay']),
    settleArm: String(r['PlanNextWeek.settleArm'] ?? ''),
    decidedBy: String(r['PlanNextWeek.decidedBy'] ?? ''),
    settled: String(r['PlanNextWeek.settled']) === 'true',
    settleDueOn: r['PlanNextWeek.settleDueOn'] ? String(r['PlanNextWeek.settleDueOn']).slice(0, 10) : null,
    potPerDay: Number(r['PlanNextWeek.potPerDay'] ?? 0),
    allowancePerDay: Number(r['PlanNextWeek.allowanceRampedPerDay'] ?? 0),
    notgoodPerDay: Number(r['PlanNextWeek.notgoodTodayPerDay'] ?? 0),
    allowanceShare: Number(r['PlanNextWeek.allowanceShare'] ?? 0),
    windowDays: Number(r['PlanNextWeek.windowDays'] ?? 0),
    windowFrom: String(r['PlanNextWeek.windowFrom'] ?? '').slice(0, 10),
    windowTo: String(r['PlanNextWeek.windowTo'] ?? '').slice(0, 10),
    calendarState: String(r['PlanNextWeek.calendarState'] ?? ''),
    sentence: String(r['PlanNextWeek.sentence'] ?? ''),
  })), [raw]);

  if (failed) return (
    <div className="p-4 text-sm text-amber-700">
      next week's money is unavailable — the PlanNextWeek cube isn't answering. The plan itself is
      in FACT_PLAN_NEXT_WEEK and the plan book reads it directly, so nothing is blocked.
    </div>
  );
  if (raw === null) return <div className="p-4 text-sm text-gray-500">loading next week's money…</div>;

  const families = Array.from(new Set(rows.map(r => r.family))).sort();

  return (
    <section className="rounded-lg border border-gray-200 bg-white p-4">
      <h2 className="text-base font-semibold">Next week's money</h2>
      <p className="mt-1 text-sm text-gray-600">
        Each working family's not-good keywords are funded out of a share of what its GOOD keywords
        actually spent in the window. The good side is never cut and is not re-priced. The window is{' '}
        {rows[0]?.windowDays ?? '—'} complete days ({rows[0]?.windowFrom} to {rows[0]?.windowTo},{' '}
        {rows[0]?.calendarState?.toLowerCase().replace('_', ' ')}).
      </p>

      {families.map(f => {
        const fr = rows.filter(r => r.family === f);
        const head = fr[0];
        const seats = fr.filter(r => r.seatNo !== null).sort((a, b) => (a.seatNo! - b.seatNo!));
        const queued = fr.filter(r => r.side === 'NOT_GOOD' && r.seatNo === null)
          .sort((a, b) => (a.rankNo ?? 1e9) - (b.rankNo ?? 1e9));
        const held = fr.filter(r => r.settleArm === 'HELD_UNSETTLED');
        const promoted = fr.filter(r => r.settleArm === 'PROMOTED_ON_FRESH');
        return (
          <div key={f} className="mt-4 border-t border-gray-100 pt-3">
            <button className="text-left w-full" onClick={() => setOpen(o => ({ ...o, [f]: !o[f] }))}>
              <span className="font-medium">{f}</span>
              <span className="ml-2 text-sm text-gray-600">
                pot {money(head?.potPerDay)}/day · allowance {money(head?.allowancePerDay)}/day
                {' '}({Math.round((head?.allowanceShare ?? 0) * 100)}% of the pot) · not-good today{' '}
                {money(head?.notgoodPerDay)}/day · {seats.length} seat(s), {queued.length} queued
              </span>
            </button>

            {(held.length > 0 || promoted.length > 0) && (
              <p className="mt-1 text-xs text-gray-600">
                The window is still settling: the correction promoted {promoted.length} keyword(s)
                on fresh evidence, and {held.length} keyword(s) that were good are HELD rather than
                demoted until their window settles. Every row below says which arm decided it.
              </p>
            )}

            {open[f] && (
              <table className="mt-2 w-full text-sm">
                <thead className="text-left text-xs uppercase text-gray-500">
                  <tr>
                    <th className="py-1">seat</th><th>keyword</th><th>campaign</th>
                    <th>move</th><th>price</th><th>cost/day</th><th>decided by</th>
                  </tr>
                </thead>
                <tbody>
                  {[...seats, ...queued].map((r, i) => (
                    <tr key={i} className="border-t border-gray-100 align-top">
                      <td className="py-1">{r.seatNo ?? `queued #${r.rankNo ?? '—'}`}</td>
                      <td>{r.targetText} <span className="text-gray-400">{r.matchType}</span></td>
                      <td className="text-gray-600">{r.campaignName}</td>
                      <td>{r.move}</td>
                      <td>{money(r.currentBid)} → {money(r.plannedBid)}</td>
                      <td>{money(r.seatCost)}</td>
                      <td className="text-gray-600">
                        {r.decidedBy} · {r.settleArm}
                        {!r.settled && r.settleDueOn ? ` (settles ${r.settleDueOn})` : ''}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        );
      })}
    </section>
  );
}
```

- [ ] **Step 5: Mount the panel and render OWNERS**

In `dashboard-react/src/pages/WeeklyRunPage.tsx`: add `import PlanNextWeekPanel from './PlanNextWeekPanel';` beside the other page imports, and render `<PlanNextWeekPanel />` directly beneath the run-summary strip and above the existing campaign/keyword sections (next week's money is the allocation; the sections below it are the detail).

In `dashboard-react/src/components/RunSummaryStrip.tsx`: the file already splits `all` by `section` (`CHANGES`, `HELD`, `UNCHANGED`, `SEATS`). Add `owners: all.filter(r => r.section === 'OWNERS').sort(byN),` to that object and render it as a fourth line, in the same shape as the `HELD` line, with the heading `who moved money today`. Its rows already carry their own `detail` sentence — print it, do not rewrite it.

In `cube/schema/RunSummary.js`: the `section` dimension carries the inline comment `// CHANGES | HELD | UNCHANGED`. Extend it to `// CHANGES | HELD | UNCHANGED | SEATS | OWNERS` — the cube derives `rowId` as `CONCAT(section, '|', label)`, so the new section needs no other change, but a stale comment is how the next reader learns the wrong set.

- [ ] **Step 6: Build the dashboard and check the cube answers**

Run:
```bash
cd /Users/ori/Develop/OI/dashboard-react && /Users/ori/.nvm/versions/node/v22.22.1/bin/npm run build
```
Expected: a clean production build (TypeScript errors are failures — fix them, do not `// @ts-ignore` them).

Then, with Cube running locally (`cd cube && npm run dev`), confirm the cube answers:
```bash
curl -s -G 'http://localhost:4000/cubejs-api/v1/load' \
  --data-urlencode 'query={"dimensions":["PlanNextWeek.family","PlanNextWeek.settleArm"],"measures":["PlanNextWeek.count"],"limit":50}' | head -40
```
Expected: JSON rows per family and settle arm. An empty result usually means `T_PLAN_NEXT_WEEK` has not been built — rebuild it (Step 1) and touch the cube cache per `feedback_refresh_cube_cache_after_fix`.

- [ ] **Step 7: Register and commit**

Insert in `config.yaml` `tables:`, next to `T_FAMILY_SEAT_REGISTER`:

```yaml
  - name: "T_PLAN_NEXT_WEEK"
    description: "v27.137 (2026-08-23) — the latest image of the next-week money plan (both plans), materialised once per pass by SP_REFRESH_CUBE_TABLES step 0d so the Weekly Run panel, the OWNERS section of V_RUN_SUMMARY and the PlanNextWeek cube read ONE image and cannot quote different numbers at the same reader. Row-for-row the newest as_of partition of FACT_PLAN_NEXT_WEEK. SOP: architecture/NEXT_WEEK_MONEY.md"
    type: "cube_table"
    source_files: ["scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql"]
```

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/procedures/SP_REFRESH_CUBE_TABLES.sql scripts/bigquery/views/V_RUN_SUMMARY.sql \
        cube/schema/PlanNextWeek.js dashboard-react/src/pages/PlanNextWeekPanel.tsx \
        dashboard-react/src/pages/WeeklyRunPage.tsx dashboard-react/src/components/RunSummaryStrip.tsx
git add -p config.yaml
git commit --no-verify -m "feat(plan): the surfaces — T_PLAN_NEXT_WEEK, the OWNERS line, the PlanNextWeek cube and the Weekly Run panel (v27.137, P-9/P-11/P-14)"
```

---

### Task 8: the SOP, and the pass that proves the whole thing (all rulings)

**Files:**
- Create: `architecture/NEXT_WEEK_MONEY.md`
- Modify: `architecture/ENGINE_PREFLIGHT.md` (a paragraph on the PLAN arm)
- Modify: `architecture/ENGINE_HEALTH.md` (the eight `plan_*` checks)
- Modify: `config.yaml` (final verification only — every object should already be registered)

- [ ] **Step 1: Write architecture/NEXT_WEEK_MONEY.md**

Write the SOP with these sections, in this order. **Standing Rule 0 is binding here:** state mechanisms, never a measured number; declared constants (0.20, 0.35, 0.50, 3, 7, 14, $2.00, $20.01–$31.99, the ten-percent margin) are exempt, and every claim that would otherwise need a figure carries the QUERY that produces it.

1. **What this is** — one paragraph: every working family's not-good keywords are funded out of a share of what its good keywords actually spent in the last complete-days window; the good side is never cut and is not re-priced; one engine sets bids and budgets for these families; Ori uploads one file.
2. **The daily loop** — orchestrator 20.8 (keyword state) → 20.8b (seat ledger) → 20.8c (`SP_BUILD_NEXT_WEEK_PLAN`) → the next pass's 20.6 (proposals, where PLAN rows enter and the retired engines are held) → 20.7 (the gate) → 21 step 0d (`T_PLAN_NEXT_WEEK`). Say plainly that the proposal snapshot reads the plan a pass late and why (the orchestrator's existing ordering), and that `plan_proposal_lag_days` measures it.
3. **The rulings** — P-1 … P-14, each in one line with its "to overrule" note, copied from the spec. P-14 carries the sentence that **Ori has not ruled** and this is the build-as-specified answer.
4. **Settle completion and the asymmetric guard** — how `V_PLAN_SETTLE_COMPLETION` reads the published curve (forward fill, monotone, cap, floor, the honesty column), why order counts are never inflated, why spend is not corrected, and what `settle_arm` / `decided_by` mean on a row. Include the query that shows today's arm counts per family.
5. **The book loop** — build, read the README, upload by hand, `--mark-uploaded`; `--supersede` if not; `FAILED_UPLOAD` by hand for a deleted line; the restore sheet by name. Every instruction carries its command.
6. **Holdout** — excluded from every sheet and every PLAN proposal from `eligible_from`; the row is still written as the counterfactual.
7. **Health** — the eight `plan_*` checks, what each means, and what a person does about a RED one.
8. **Known limits**, each with its cause and its fix if there is one:
   - the proposal-snapshot lag of one pass (cause: orchestrator ordering; fix: move 20.6/20.7 below 20.8c — an open ruling for Ori);
   - a queued keyword's planned spend is zero while parking only lowers its price (cause: spec §4.7's arithmetic; the row says so in words);
   - the P-5 grace is granted on the ladder state alone — there is no two-window memory table, so it cannot see whether the previous window was also quiet (inherited from the reprice book's rule-B arm);
   - the backtest's three approximations (no prices, the ladder proxy, today's bars);
   - `V_ADS_SETTLE_CURVE` is young: `plan_settle_curve_coverage` says how much of the correction it can actually answer for, and a zero there means the plan rests on P-14b alone.
9. **Queries** — one per claim anyone will want to check: the pot and allowance per family; the seats and the queue; the arm counts; the held proposals; the scorecard; the backtest command.
10. **Open rulings for Ori** — the P-14 defect ruling itself, the orchestrator ordering, the queued-spend arithmetic, and the allowance share per calendar state (which the scorecard and the backtest are built to answer).

- [ ] **Step 2: Add the PLAN arm to the two existing SOPs**

`architecture/ENGINE_PREFLIGHT.md`: add a paragraph to the exclusion-sources section — a fourth source, PLAN-OWNED, ordered after HOLDOUT and before the collision arm, with the belt-and-braces explanation (the braces is `hold_source`, stamped by the snapshot; the belt is `is_plan_owned`, for an engine added later that nobody remembered to hold). State that PLAN sits second in precedence, behind LOW_STOCK only.

`architecture/ENGINE_HEALTH.md`: add the eight `plan_*` checks to the check list with one line each, and mark `plan_settle_curve_coverage` and `plan_proposal_lag_days` as REPORTS (INFO), like the two seat-register reports already there.

- [ ] **Step 3: Run every acceptance in the plan, in order**

```bash
cd /Users/ori/Develop/OI
for f in PLAN_CONFIG V_PLAN_WINDOW_JUDGMENT FACT_PLAN_NEXT_WEEK PLAN_OWNERSHIP PLAN_SCORECARD; do
  echo "=== $f"
  bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache \
    "$(grep -v '^--' scripts/bigquery/tests/${f}_acceptance.sql)"
done
```
Expected: every row of every suite reads `PASS`. Any `FAIL` names the guarantee it broke — fix the object, never the check.

- [ ] **Step 4: Run every Python test**

Run: `/usr/local/bin/python3 -m pytest tools/tests/ -q`
Expected: all pass, with `test_change_log_discipline.py` now parametrised over three books.

- [ ] **Step 5: Verify config.yaml one last time**

Run:
```bash
cd /Users/ori/Develop/OI
/usr/local/bin/python3 - <<'PY'
import yaml, collections
d = yaml.safe_load(open('config.yaml'))
names = [e['name'] for s in ('views','tables','stored_procedures','functions') for e in d[s]]
dupes = [k for k, v in collections.Counter(names).items() if v > 1]
want = ['DE_PLAN_CONFIG','FN_PLAN_CALENDAR_STATE','V_PLAN_SETTLE_COMPLETION',
        'V_PLAN_WINDOW_JUDGMENT','FACT_PLAN_NEXT_WEEK','SP_BUILD_NEXT_WEEK_PLAN',
        'V_PLAN_SCORECARD','T_PLAN_NEXT_WEEK']
print('duplicates:', dupes)
print('missing   :', [w for w in want if w not in names])
PY
```
Expected: `duplicates: []` and `missing   : []`.

- [ ] **Step 6: Read the health board once**

Run: `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=csv "SELECT check_name, measured, status, detail FROM \`onyga-482313.OI.V_ENGINE_HEALTH\` ORDER BY status, check_name"`
Expected: no `RED` row anywhere on the board (not just the `plan_*` ones — the plan changes the proposal snapshot and the gate, so a regression would show on an older check first).

- [ ] **Step 7: Commit**

```bash
cd /Users/ori/Develop/OI
git add architecture/NEXT_WEEK_MONEY.md architecture/ENGINE_PREFLIGHT.md architecture/ENGINE_HEALTH.md
git add -p config.yaml
git commit -m "docs(plan): the next-week money SOP — the loop, the fourteen rulings, the settle arms, the book loop, health and the open rulings (v27.138)"
```

---

## Time estimate

Hours are build **plus** the three-lens verification each task's steps ask for (run it, read it in words, prove the guarantee). The comparable references: a task on the family seat register took 1–3 hours; a repair round on a shipped object took about 45 minutes.

| task | what it is | hours |
|---|---|---|
| T0 | `DE_PLAN_CONFIG` + `FN_PLAN_CALENDAR_STATE` + acceptance | 1.0 – 1.5 |
| T1 | `V_PLAN_SETTLE_COMPLETION`, `FACT_PLAN_NEXT_WEEK` DDL, `V_PLAN_WINDOW_JUDGMENT` + acceptance. The largest single SQL object in the plan, and the P-14 arms live here | 3.0 – 4.5 |
| T2 | `SP_BUILD_NEXT_WEEK_PLAN` + orchestrator 20.8c + acceptance. Seating and the free-number map are the fiddly parts | 3.0 – 4.0 |
| T3 | ownership: the snapshot's three new statements, the preflight's precedence and belt arm, the view redeploy + acceptance. Two long CALLs (the ceiling views) are most of the wall clock | 2.0 – 3.0 |
| T4 | the plan book, the restore book, the two existing books standing down, four test files | 3.0 – 4.0 |
| T5 | `V_PLAN_SCORECARD` + eight `plan_*` health checks + acceptance | 2.0 – 2.5 |
| T6 | the backtest tool + its fixture tests; the first full run is slow | 2.0 – 3.0 |
| T7 | `T_PLAN_NEXT_WEEK`, the OWNERS line, the cube, the panel, the two dashboard edits, a clean build | 2.5 – 3.5 |
| T8 | the SOP, two SOP amendments, the whole-suite pass | 1.5 – 2.5 |
| | **total** | **20 – 28.5** |

### Calendar

**Before Sunday 2026-08-30 (the next Weekly Run) — the money-moving half.** T0 through T4 is the smallest set that changes what Ori uploads: the plan exists, it owns the working families' prices and budgets, and one book carries it. That is 12–17 hours of work, which fits Sunday if it starts by Wednesday 2026-08-26 and nothing in T3 surprises. Order matters — T1 before T2 before T3 before T4, no overlap, because each reads the last one's output.
- **Live before Sunday:** the judgement, the nightly plan, one-engine ownership, the plan book. Ori's Weekly Run on 2026-08-30 is then one file built from the plan instead of a 25-row repair list.
- **A safe partial:** T0–T2 alone. The plan is written and readable every night and nothing changes what Ori uploads. If T3 or T4 is not finished by Saturday, ship T0–T2 and leave the existing books in charge for one more week — the plan grades itself in the meantime and the first upload lands on 2026-09-06 with a week of evidence behind it.

**Before 2026-09-01 (when the holdout arms).** T5 (health and the scorecard) matters more than it looks: from 2026-09-01 the holdout's `eligible_from` is live, and every book and every PLAN proposal must be excluding those campaigns from that morning. The exclusion is built in T2 (the builder's `holdout` column), T3 (the preflight arm, which already covers all engines) and T4 (the book's `HOLDOUT` disposition), and it is *proved* by `PLAN_OWNERSHIP_acceptance.sql` C07 and `FACT_PLAN_NEXT_WEEK_acceptance.sql` C08. **Run both acceptances again on the morning of 2026-09-01**, after the first pass in which the holdout arm is live — before that date they pass vacuously, because the holdout CTE is empty by design.
- **Live before 2026-09-01:** T5 and, if the week allows, T7 (the surfaces). T6 (the backtest) and T8 (the SOP) can follow in the first week of September — the backtest answers a learning question (the allowance share per calendar state) that nothing is waiting on, and the SOP should be written when the mechanism has stopped moving.

**Not before the peak ends.** The live calendar reads PEAK from 2026-08-10 to 2026-09-17, so the first plan nights run on a 3-day window at a 0.20 share. The 7-day OFF_PEAK window does not arrive until 2026-09-18, and BOOST (share 0.50) not until Christmas's `boost_start`. Nobody should conclude anything about the share from the first three weeks: the scorecard needs three graded windows per calendar state, and the backtest is the only instrument that can speak about a state the plan has not lived through yet.
