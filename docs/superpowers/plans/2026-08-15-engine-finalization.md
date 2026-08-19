# Engine Finalization — Self-Improving Keyword Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every keyword has one explicit lifecycle state, one owner, and one next appointment; the engine remembers what it proposed, grades itself against outcomes AND against Ori's manual changes, tunes its own thresholds through `DE_COACH_THRESHOLDS`, and can never ship two contradictory instructions for the same key.

**Architecture:** All decision logic in BigQuery views/SPs (feedback_all_logic_in_backend). Three new load-bearing objects — a daily engine-proposal snapshot (`FACT_ENGINE_PROPOSALS`, the engine's memory of its own opinions), a keyword state machine (`V_KEYWORD_STATE`, the "roadmap of each keyword"), and a standing pre-upload contradiction gate (`SP_ENGINE_PREFLIGHT` → `T_ENGINE_PREFLIGHT`). The learning loop closes through the suggestion channel that already exists in `DE_COACH_THRESHOLDS` (`suggested_value`/`suggested_at`/`suggestion_reason`): the tuner writes proposals, Ori promotes them, the SQL reads only `threshold_value`.

**Tech Stack:** BigQuery SQL (views + SPs), `bq` CLI deploys, Python tools in `tools/` for bulksheet generation, Cube.js passthrough schemas, React panels (render-only).

---

## Ground rules for every task (read once, apply always)

1. **SOP first.** Each task that changes engine behavior updates its SOP in `architecture/` before the SQL. The SOP section to touch is named per task.
2. **Deploy pattern.** `bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' <file>)"`. Back up first: `cp FILE.sql FILE.sql.bak.v27.NN.$(date +%H%M)`.
3. **Verification is part of the task, not a follow-up.** Every deploy gets: (a) the assertion query written BEFORE the change, run on the live view to show the defect; (b) the same query after deploy showing the fix; (c) pull-twice determinism (`bq query` the output twice, diff byte-identical) on any view whose SELECT list changed; (d) a decision-flip count ("N rows changed action, biggest movers are …") reported to Ori.
4. **Settle discipline.** Any new judgment reads settled windows (SP D+7, SB D+14) or explicitly declares itself a fresh-day signal. Fresh SP day-1 is 88–90% complete; SB ~17.5% understated. Never grade a change before its scorecard read-gate.
5. **GP currency.** `FACT_AMAZON_ADS.GROSS_PROFIT`, the stored column. Never recompute (v27.62 rule). SB arm derives margin from the dominant mapped ASIN — deterministically, never a bare `ANY_VALUE` pair.
6. **Registration.** Every new BigQuery object goes into `config.yaml` the same commit.
7. **Repo state warning.** The working tree carries ~171 dirty files from parallel sessions and `deployment/deploy_all.sh` ships the working tree. Commit ONLY the files each task names. Dashboard commits need `--no-verify`.
8. **BigQuery planner limits.** These engine views are heavy. A query joining two of them can throw "too many subqueries". The rule: materialize each engine's slice into a temp/`T_` table inside an SP, then join the small tables. Never join two engine views directly.
9. **Excluded from this plan** (separate plans, do not scope-creep into them): the September BASE/GROWTH restructure, Q4 supply decisions (Lollibox White, Bottle price), Phase 5 kill-Flask-HTML, the intent CVR curve build (its Phase-0 coverage gate appears here only as a gate).

---

## The investment doctrine (Ori 2026-08-15 — the test every rule must pass)

"The decision should be like a stock, you are Warren Buffett. Should I invest in this stock
(keyword). It should be about believing. **The product is the stock.**"

Operationally: the PRODUCT is the business — belief, margin, CVR, market position live there. A
keyword is a PRICE at which the product's demand can be bought; its worth-per-click is
margin × CVR, estimated hierarchically (term when the data exists → intent → product as the
floor), so thin keyword data never overturns product-level conviction. Every bid decision is a
VALUATION decision (price vs worth, with a margin of safety), never a momentum decision — the
account's own record enforces this (holding paid, churn lost, momentum raises reversed at 54%).
The analogy breaks in exactly one place and the break is doctrine too: a position here has a
DAILY CARRYING COST, so believing means holding the SEAT and negotiating the PRICE — park when
price sits persistently above value, exit only on thesis break (tested loser), never on a dip.
**The review test for every rule in this plan: is it valuing, or is it chasing the tape?**

## The target keyword lifecycle (the spec every task serves)

Every (campaign, keyword) is in exactly ONE state, has exactly ONE owner, and always has a NEXT APPOINTMENT (a date on which something will re-judge it). This is the end-to-end roadmap of each keyword:

```
                 ┌──────────────────────────────────────────────────────────┐
                 │ ENTRY — added by research (orphan winner term, rank>75), │
                 │ intent grid, seasonal calendar, or launch build.         │
                 │ Bid = calibrated entry (1.5× target CPC, capped by seat  │
                 │ CPC; NEVER the $1.00 flat floor — Task 2.2 kills it).    │
                 └──────────────┬───────────────────────────────────────────┘
                                ▼
   ┌────────── TRIAL (probing) — gathers clicks at seat pace (80/20).       │
   │           Judged only on settled evidence, window = V_PEAK_WINDOW_RULE │
   │           (7d, or 3d in a proven peak). Next appointment: settle_due.  │
   │    ┌───────────┴────────────┐
   │    ▼                        ▼
   │  WINNER (roas90 ≥ 1.0 or converting)      LOSER (settled, below bar)
   │  · never pulled down (v27.63)             · bleed via SEARCH-TERM
   │  · paced 5%/day only when >4 clk/day        NEGATES first, bid second
   │    on a capped budget                     · DARK_BRAKE scaled by ITS
   │  · sweet-spot raise toward $2 cap           OWN record (Task 1.3)
   │  · budget raise is the lever              · tested loser (≥15 clk90,
   │    (never the brake)                        0 ord) → DEAD, seat freed
   │    │                                          │
   │    │                                          ▼
   │    │                                    PARK (bid → park floor)
   │    │                                    · logged w/ campaign_id+kw_id
   │    │                                    · season ledger remembers the
   │    │                                      occurrence (BLOCK_CUT etc.)
   │    │                                          │ next appointment:
   │    │                                          ▼ settle_due (D+7/D+14)
   │    │                                    REVERDICT (V_PARK_REVERDICT)
   │    │                                    · REVIVE ≥1.0× @ ≥10 settled clk
   │    │                                      at calibrated bid (never $1)
   │    │                                    · CONFIRM_PARK → re-check via
   │    │                                      14d revival sweep + next
   │    │                                      season window
   │    └──────────────┬───────────────────────────┘
   │                   ▼
   │        SEASONAL_MEMORY — every occurrence writes the ledger; next
   │        year's window pre-arms ENTRY_BLOCK / early revive.
   └─── ownership overlay at every state: LOW_STOCK > LAUNCH > OOB > LIFT
        (one engine may act; all others emit an explicit DEFER, and the
        DEFER target must actually RENDER the decision — Task 1.2).
```

The plan's phases build, in order: trust in the current numbers (0), coherence so states can't contradict (1), the state machine itself (2), the learning loop (3), context awareness (4), and a deploy protocol so "deployed unverified" cannot recur (5).

---

## Phase 0 — Verify before building (nothing below is safe until this passes)

### Task 0.1: Adversarially verify the v27.62 GP fix across all 8 views

> **✅ DONE 2026-08-15** — 9 views verified by 9 adversarial agents (record: `progress.md`
> §2026-08-15). All samples exact, all deployed defs clean, flip shape as predicted (halo winners
> restored — VIDEO- BALL "gift for girls" 0.60×→1.34×; mild GP inflation corrected elsewhere).
> One PRE-EXISTING defect found underneath and fixed same day (v27.64): V_RUN_TARGET
> `ANY_VALUE(target_text)` nondeterminism on the '-1' collapsed rows → `MIN()`, redeployed,
> re-verified byte-identical (1,302 rows ×2). Counts toward Task 1.9; the open ANY_VALUE sites
> remain V_KEYWORD_LIFT's SB arm + V_SB_LAUNCH_TARGET. **Task 0.2 also DONE** — record CLEAN,
> 68 rows, BOX-SBS present; ~8 rows are engine-suggested-hand-applied (Task 3.1 must classify
> AGREED) and one stale old_budget on same-day double edits. **Phase 0 exit: GREEN.**

The GP fix is deployed but its verification agents died on a rate limit. v27.48 shipped in exactly this state and came back with 5 defects. Do not build on top of unverified plumbing.

**Files:**
- No source changes. Verification queries only.
- Log results: `progress.md` (append a dated section).

- [ ] **Step 1: Confirm zero live tier-cost joins in the DEPLOYED definitions (not the files)**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --max_rows=20 --format=csv "
SELECT table_name,
       REGEXP_CONTAINS(view_definition, r'(?i)JOIN[^;]{0,120}T_PRICE_COST_TIER') AS live_join
FROM \`onyga-482313.OI\`.INFORMATION_SCHEMA.VIEWS
WHERE table_name IN ('V_KEYWORD_LIFT','V_LAUNCH_PHASE1','V_OOB_KEYWORD','V_PARK_REVERDICT',
                     'V_OOB_BUDGET_PHASE','V_KEYWORD_GUARD','V_CHANGE_SCORECARD','V_RUN_TARGET','V_LOW_STOCK_ADS')"
```
Expected: `live_join = false` on all 9 rows.

- [ ] **Step 2: Hand-recompute GP-ROAS for a stratified sample of 20 campaign-days**

For each of the 8 views, pick 2–3 rows spanning families and channels; for each, pull the stored GP and recompute the view's ratio:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --max_rows=10 --format=csv "
SELECT campaign_name, date, ROUND(SUM(GROSS_PROFIT),2) gp, ROUND(SUM(Ads_cost),2) spend,
       ROUND(SAFE_DIVIDE(SUM(GROSS_PROFIT), SUM(Ads_cost)),2) gp_roas
FROM \`onyga-482313.OI.FACT_AMAZON_ADS\`
WHERE campaign_name='VIDEO- BALL' AND date='2026-08-12' GROUP BY 1,2"
```
Expected anchor: VIDEO- BALL / 2026-08-12 = GP $229.16, GP-ROAS 3.69×, and every view that surfaces that campaign-day agrees. Repeat per view against its own output columns (each view's GP-ROAS column must equal the FACT ratio for the same window).

- [ ] **Step 3: Pull-twice determinism on the 8 views**

Pull each view's full output twice with `--nouse_cache`, `sort`, `diff`. Expected: byte-identical. Any diff = an `ANY_VALUE`-class bug; STOP and report before continuing.

- [ ] **Step 4: Decision-flip report**

For each view, count rows whose action differs from the `.bak.v27.62.*` era. Cheapest honest method: the `.bak` files still contain the old formula — deploy each bak to a scratch name (`V_TMP_GPCHECK_<name>`) one at a time, diff `(key, action, suggested value)` against live, drop the scratch view, record: flips per view, direction (cuts→holds expected to dominate), 10 biggest movers by spend. Report to Ori. Expected shape: flips overwhelmingly cuts-becoming-holds/protects (the corrupt GP read winners as losers).

- [ ] **Step 5: Record verdict in progress.md; if ANY check fails, revert that view from its bak and stop the plan**

### Task 0.2: Verify the manual-change record and freeze it as the learning baseline

Ori's instruction: "check this check and if ok learn from my manual changes." The manual rows exist (Aug 2–11: 66 MANUAL rows — 38 INCREASE_BID on Aug 4, 3 budget changes Aug 9–11, etc., zero missing campaign_ids). Before anything learns from them, prove the record is complete and correctly attributed.

**Files:**
- Verification queries; append findings to `progress.md`.

- [ ] **Step 1: Completeness — every manual change Ori remembers making is logged**

Cross-check the log against Amazon's own change history for the same window (Ori's console screenshots / bulk operations history). Known specific items to confirm present: the BOX-SBS budget + bid changes, the portfolio reassignment session (portfolio changes are NOT bid/budget rows — confirm they were either logged with their own action or documented as out of log scope).

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --max_rows=100 --format=csv "
SELECT DATE(applied_at) d, action, campaign_id, keyword_id, old_bid, new_bid, old_budget, new_budget
FROM \`onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED\`
WHERE source='MANUAL' AND applied_at >= '2026-08-01' ORDER BY applied_at"
```

- [ ] **Step 2: Attribution — no engine change mislabeled MANUAL and vice versa**

Spot-check 10 rows: each MANUAL row's value must NOT equal the engine's contemporaneous suggestion for that key on that day (if it does, it was probably an engine-suggested change applied by hand — label it `MANUAL_APPLIED_COACH` in the notes, not a divergence). This distinction feeds Task 3.2 directly.

- [ ] **Step 3: Scorecard coverage — every manual row will get a verdict**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --max_rows=10 --format=csv "
SELECT COUNT(*) manual_rows, COUNTIF(sc.change_key IS NOT NULL) graded_or_pending
FROM \`onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED\` m
LEFT JOIN (SELECT DISTINCT change_key FROM \`onyga-482313.OI.V_CHANGE_SCORECARD\`) sc
  ON sc.change_key = CONCAT(m.campaign_id,'|',COALESCE(m.keyword_id,''),'|',CAST(m.applied_at AS STRING))
WHERE m.source='MANUAL' AND m.applied_at >= '2026-08-01'"
```
(Adjust the key expression to the scorecard's actual key columns — read `V_CHANGE_SCORECARD.sql` §"HOW EACH ACTION TYPE IS SCORED" first.) Expected: rows too young appear in neither (correct — the lag is the view); rows old enough all appear.

---

## Phase 1 — Coherence: one key, one owner, one instruction

### Task 1.1: `SP_ENGINE_PREFLIGHT` + `T_ENGINE_PREFLIGHT` + `V_ENGINE_PREFLIGHT` — the standing contradiction gate

> **✅ BUILT 2026-08-15** — with one design improvement over the spec below: the SP judges
> `FACT_ENGINE_PROPOSALS` (already materialized daily by Task 20.6) instead of re-scanning the
> ceiling views, so it reads only two small tables and runs in seconds. Deployed, first run:
> **149 instructions → 97 GO / 44 EXCLUDE / 8 REVIEW** — 29.5% contradiction, the iteration-6
> magnitude, now gated daily (orchestrator Task 20.7). Verdicts stamped back onto the proposal
> history (Task 3.0's remaining column work — done). Assertion passed: zero keys with two live
> instructions. Exclusion map: LOW_STOCK silences LAUNCH ×31 / OOB ×4 / LIFT ×2; REVERDICT
> silences LIFT ×3; OOB silences LIFT ×2. The 8 REVIEWs are all settled-winner cuts (1.2×–3.85×)
> flagged for human eyes. Registered in config.yaml; SOP at architecture/ENGINE_PREFLIGHT.md.
> Step 6 ALSO DONE: EnginePreflight cube (passthrough) + the DoPage.exportBulksheet gate —
> fetches the latest verdicts at export time (fresh, like live-campaigns), refuses EXCLUDE rows
> with reasons listed, per-item confirm on REVIEW, fails OPEN with a visible "exported WITHOUT
> the gate" flag if the cube is unreachable. Levers: bid actions (incl. revival INCREASE_BID) →
> BID; the exporter's own budget predicate → BUDGET; negates/creates pass unjudged (SOP known
> gap). Typecheck zero DoPage lines (6 pre-existing DoPage type errors fixed behavior-preserving
> along the way); vite build passes. Cube restart required before the gate is live in the
> browser. **TASK 1.1 CLOSED.**

The iteration-6 audit was a one-off that cut contradiction from 29.9% to ~4%. Make it a permanent, mechanical gate that runs before every upload and feeds a Weekly Run banner.

**Files:**
- Create: `scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql`
- Create: `scripts/bigquery/views/V_ENGINE_PREFLIGHT.sql`
- Create: `architecture/ENGINE_PREFLIGHT.md`
- Modify: `config.yaml` (register SP, T_, V_)
- Modify: the bulksheet generator tool in `tools/` (find it: `grep -rl "bulksheet" tools/ | head`) — it must refuse EXCLUDE rows.

- [ ] **Step 1: Write the SOP** — `architecture/ENGINE_PREFLIGHT.md` with the check list below, the owner-precedence order, and the rule "the generator refuses EXCLUDE rows; REVIEW rows require a click; GO rows flow."

- [ ] **Step 2: Write the assertion query first (it should FIND contradictions today)**

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --max_rows=50 --format=csv "
SELECT campaign_id, keyword_id, COUNT(DISTINCT engine) engines
FROM \`onyga-482313.OI.T_ENGINE_PREFLIGHT\`
GROUP BY 1,2 HAVING COUNT(*) > 1 ORDER BY engines DESC"
```
Expected BEFORE the SP exists: table not found (the failing test). AFTER Step 3: rows listing any key that two engines instruct — each must carry verdict EXCLUDE on all but the owner.

- [ ] **Step 3: Write the SP.** One temp table per engine slice (planner rule), then union + judge:

```sql
-- SP_ENGINE_PREFLIGHT — materializes every live instruction from every engine, one row per
-- (engine, campaign_id, keyword_id), then stamps a verdict. Scheduled with the weekly run and
-- callable on demand before any upload. THE GENERATOR MUST NOT SHIP WHAT THIS EXCLUDES.
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_ENGINE_PREFLIGHT`()
BEGIN
  CREATE TEMP TABLE i_lift AS
  SELECT 'LIFT' AS engine, CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         action, suggested_bid AS sug_bid, CAST(NULL AS FLOAT64) sug_budget, current_bid
  FROM `onyga-482313.OI.V_KEYWORD_LIFT`
  WHERE action NOT IN ('HOLD','DEFER_OOB','PROBE_WAIT') AND suggested_bid IS NOT NULL;

  CREATE TEMP TABLE i_oob AS
  SELECT 'OOB', CAST(campaign_id AS STRING), CAST(keyword_id AS STRING),
         bid_action, suggested_bid, CAST(NULL AS FLOAT64), current_bid
  FROM `onyga-482313.OI.V_OOB_KEYWORD`
  WHERE bid_action NOT IN ('HOLD') AND suggested_bid IS NOT NULL;

  CREATE TEMP TABLE i_lowstock AS
  SELECT 'LOW_STOCK', CAST(campaign_id AS STRING), CAST(keyword_id AS STRING),
         action, suggested_bid, suggested_budget, CAST(NULL AS FLOAT64)
  FROM `onyga-482313.OI.V_LOW_STOCK_ADS`
  WHERE row_kind IN ('TARGET','CAMPAIGN') AND COALESCE(is_proposal, FALSE);

  CREATE TEMP TABLE i_launch AS
  SELECT 'LAUNCH', CAST(campaign_id AS STRING), CAST(keyword_id AS STRING),
         ladder_action, proposed_bid, CAST(NULL AS FLOAT64), current_bid
  FROM `onyga-482313.OI.V_LAUNCH_BID_LADDER` WHERE is_proposal;

  CREATE TEMP TABLE i_reverdict AS
  SELECT 'REVERDICT', CAST(campaign_id AS STRING), CAST(keyword_id AS STRING),
         'REVIVE', revive_bid, CAST(NULL AS FLOAT64), current_bid
  FROM `onyga-482313.OI.V_PARK_REVERDICT` WHERE reverdict = 'REVIVE';

  -- settled record for the direction-vs-record test (small: key + two numbers)
  CREATE TEMP TABLE rec AS
  SELECT CAST(campaign_id AS STRING) cid, CAST(keyword_id AS STRING) kid,
         settled_roas90, settled_clk90
  FROM `onyga-482313.OI.V_KEYWORD_GUARD`;

  CREATE OR REPLACE TABLE `onyga-482313.OI.T_ENGINE_PREFLIGHT` AS
  WITH all_i AS (
    SELECT * FROM i_lift UNION ALL SELECT * FROM i_oob UNION ALL
    SELECT * FROM i_lowstock UNION ALL SELECT * FROM i_launch UNION ALL SELECT * FROM i_reverdict
  ),
  ranked AS (
    SELECT *,
      -- OWNERSHIP PRECEDENCE (Ori 2026-08-13): LOW_STOCK > LAUNCH > OOB > REVERDICT > LIFT
      ROW_NUMBER() OVER (PARTITION BY cid, kid ORDER BY
        CASE engine WHEN 'LOW_STOCK' THEN 1 WHEN 'LAUNCH' THEN 2 WHEN 'OOB' THEN 3
                    WHEN 'REVERDICT' THEN 4 ELSE 5 END) AS own_rank,
      COUNT(*) OVER (PARTITION BY cid, kid) AS n_instr
    FROM all_i
  )
  SELECT r.*, CURRENT_TIMESTAMP() AS preflight_at,
    CASE
      WHEN r.n_instr > 1 AND r.own_rank > 1 THEN 'EXCLUDE'          -- a non-owner instructing
      WHEN r.sug_bid IS NOT NULL AND rc.settled_roas90 >= 1.2 AND rc.settled_clk90 >= 10
           AND r.sug_bid < r.current_bid THEN 'REVIEW'              -- cutting a settled winner
      WHEN r.sug_bid IS NOT NULL AND r.sug_bid > 2.00 THEN 'REVIEW' -- above the house bid cap
      WHEN r.sug_bid IS NOT NULL AND ABS(r.sug_bid - r.current_bid) < 0.005 THEN 'EXCLUDE' -- no-op
      ELSE 'GO' END AS verdict,
    CASE
      WHEN r.n_instr > 1 AND r.own_rank > 1
        THEN CONCAT('owned by a higher engine — ', r.n_instr - 1, ' other instruction(s) on this key')
      WHEN rc.settled_roas90 >= 1.2 AND rc.settled_clk90 >= 10 AND r.sug_bid < r.current_bid
        THEN CONCAT('cut on a settled winner (', CAST(rc.settled_roas90 AS STRING), 'x/90d) — human eyes')
      ELSE NULL END AS verdict_reason
  FROM ranked r
  LEFT JOIN rec rc ON rc.cid = r.cid AND rc.kid = r.kid;
END;
```

- [ ] **Step 4: `V_ENGINE_PREFLIGHT`** — thin view over the T_ adding campaign/keyword names via `V_DIM_CAMPAIGN_CURRENT` + `DIM_KEYWORD` for the panel. No logic.

- [ ] **Step 5: Deploy SP + view, CALL the SP, run the Step-2 assertion.** Record today's contradiction count in `progress.md`. Expected: the multi-engine keys that exist today (e.g. any keyword in both OOB and LIFT's actionable sets) each show one GO and N−1 EXCLUDEs.

- [ ] **Step 6: Wire the generator** — the bulksheet tool refuses rows whose (cid, kid) is EXCLUDE in `T_ENGINE_PREFLIGHT` and prints what it refused and why. Run it in dry-run; expected output lists refused rows.

- [ ] **Step 7: Register in `config.yaml`, commit**

```bash
git add scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql scripts/bigquery/views/V_ENGINE_PREFLIGHT.sql architecture/ENGINE_PREFLIGHT.md config.yaml
git commit -m "feat(engine): standing preflight contradiction gate (SP+T_+V_), generator refuses EXCLUDE"
```

### Task 1.2: Close the AUTO deferral hole (decisions computed, rendered nowhere)

> **✅ DONE 2026-08-16, browser-verified live.** The Auto sections now fetch OobKeyword rows for
> DEFER_OOB campaigns and render the OOB engine's decisions in place of the ownership
> placeholders — headers read "6 OOB-owned" (Auto low budget) + "1 OOB-owned" (Auto) = the 7
> deferring campaigns, matching BigQuery exactly. Verified rendered rows on BALL-SP/AUTO (Mint):
> substitutes 23c 0.00× → dark brake $0.41→$0.39; loose-match 13c 0.00× → $0.34→$0.32 (the
> exact "22 clicks and no trimming" class Ori flagged, now visible and queueable); close-match →
> ACTIVATE $0.99 "anchored to the record … never the flat $1"; complements proven 11.81× → hold.
> Window honesty kept (1d under "last day", wider windows dashed with prev-2d in the tooltip);
> one-list apply-all includes the OOB bids; non-clobber + MANUAL-sweep exclusion for
> other-panel claims. Typecheck zero lines, vite build clean.

LIFT emits `DEFER_OOB` for 8 AUTO campaigns; the OOB panel drops AUTO campaigns (`!r.isAutoCampaign`); the Auto section never reads `OobKeyword`. ~$46/day of near-zero-return spend (measured 0.13× over 3d) carries live DARK_BRAKE decisions nobody can see or apply.

**Files:**
- Modify: `dashboard-react/src/pages/KeywordLiftPhase.tsx` (the AUTO tier fetches `OobKeyword` rows for campaigns whose LIFT action is `DEFER_OOB` and renders them in the existing table shape, actions queueable)
- Test: manual — panel renders the deferred rows with their OOB bid actions.

- [ ] **Step 1:** In the AUTO tier only, collect `campaignId`s where every keyword row is `DEFER_OOB`; fetch `OobKeyword` for those ids (same dimension list OobBudgetPhase uses).
- [ ] **Step 2:** Render each such campaign's OOB keyword rows in the same table, action column showing the OOB `bid_action` (lowercased), `→ $` from `suggestedBid`, why from `bidReason`, queueable via the existing `queueKwBid`-shaped helper. Do NOT re-derive anything.
- [ ] **Step 3:** Verify in the browser: BALL-SP/AUTO (Purple) shows close-match $0.48 → $0.45 dark brake (or current values). Typecheck the file: zero errors.
- [ ] **Step 4:** Commit (`--no-verify`).

### Task 1.3: DARK_BRAKE scales with the keyword's own record everywhere

> **✅ DONE 2026-08-16 (v27.65).** Investigation refined the diagnosis: the record-scaling already
> existed in all three arms (v27.46 A4) — the real defect was the dark multiplier collapsing every
> band to the 5% minimum when pct_dark reads low (a 7-day-hysteresis-owned campaign at 0% dark
> today). Fix = the plan's ZERO-SALE EVIDENCE FLOOR as a third term in every brake LEAST (one
> shared fragment, 3 bid arms + 3 reason mirrors): clk1 ≥ 10 AND roas_1d = 0 AND roas90 < 1.0 ⇒
> step ≥ 15%. Proven seats exempt (paced, never punished). Deployed + verified: anchor row BALL
> Mint loose-match 13c 0.00× / r90 0.33 now steps 14.7% with the reason naming 15%; exactly 4
> rows deepened account-wide, 234 byte-stable; pull-twice PASS. SOP §DARK_BRAKE updated.

The share-based brake arm brakes a 22-click 0.00× keyword 7% (12 days to floor) because the step is keyed to CAMPAIGN darkness. The full-ladder arm already scales by the keyword's 90d record (`proven 5% min · 0.6–1.0× max(5%,15%×dark) · else max(5%,30%×dark)`). Unify: every brake step uses the record-scaled formula.

**Files:**
- Modify: `scripts/bigquery/views/V_OOB_KEYWORD.sql` (the DARK_BRAKE suggested_bid arm keyed on `clk_share1` — find with `grep -n "clk_share1" V_OOB_KEYWORD.sql`)
- Modify: `architecture/OOB_BUDGET_PHASE.md` §bid ladder.

- [ ] **Step 1: Assertion before** — the 22-click keyword's suggested step:

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --max_rows=5 --format=csv "
SELECT target_text, current_bid, suggested_bid, ROUND(100*(1 - suggested_bid/current_bid),1) step_pct, roas90
FROM \`onyga-482313.OI.V_OOB_KEYWORD\`
WHERE campaign_name='BALL-SP/AUTO (Purple)' AND bid_action='DARK_BRAKE'"
```
Expected before: step ≈ 7% despite roas90 ≈ 0.54. Expected after: step = `max(5%, 15% × dark)` for the 0.6–1.0 band / `max(5%, 30% × dark)` below 0.6 — for 23% dark and roas90 0.54 that is ~7%… **so ALSO floor the step at 15% when `roas_1d = 0` on ≥ 10 clicks yesterday** (a 22-click zero-sale day is evidence, not noise). Encode exactly:

```sql
-- step multiplier, shared by BOTH brake arms (v27.64): the keyword's own record picks the band,
-- and a zero-sale double-digit day floors the step at 15% — volume that size waits for nobody.
LEAST(
  IF(COALESCE(roas90,0) >= 1.0, 0.95,
     IF(roas90 >= 0.6, 1 - GREATEST(0.05, 0.15 * pct_dark/100),
                       1 - GREATEST(0.05, 0.30 * pct_dark/100))),
  IF(COALESCE(clk1,0) >= 10 AND COALESCE(roas_1d,0) = 0, 0.85, 1.0)
)
```
- [ ] **Step 2:** Apply to both brake arms (share-based and ladder), same expression, one comment block explaining the bands and citing this task.
- [ ] **Step 3:** Deploy, re-run assertion (expect ~15% on the 22-click row), pull-twice, decision-flip count, commit.

### Task 1.4: Fix the negate surface grain (iteration-6 "WRONG-GRAIN" finding)

The negate view aggregates at the wrong grain, so a term can be proposed for negation in an ad group where it never ran. Correct grain: (campaign_id, ad_group_id, term).

**Files:**
- Modify: the negate surface view (find it: `grep -rln "NEGATE" scripts/bigquery/views/ | head`; iteration-6 notes name it — read `progress.md` §iteration-6)
- Modify: its SOP section.

- [ ] **Step 1: Assertion** — count proposed negations whose (campaign, ad_group, term) has zero clicks in FACT for that ad group. Expected before: > 0. After: 0.
- [ ] **Step 2:** Re-key the aggregation to (campaign_id, ad_group_id, LOWER(term)); the negate row emits every ad_group_id the term actually ran in (the OobBudgetPhase queueNeg pattern already fans out per ad group).
- [ ] **Step 3:** Deploy, assert, pull-twice, commit.

### Task 1.5: Park direction guard — a park can never raise a bid

> **✅ DONE 2026-08-16 (v27.65, same version tag as Task 1.3 — one day's guard batch).** The 3
> Aug-13 violations had rolled off with the data (assertion: 0 today) but the class is
> structural — any breakeven/park pricing arm resolves upward whenever the current bid sits below
> its computed destination. Guard added at the TOP of the final output ladder (below DEFER_OOB),
> in all THREE parallel CASEs (action → HOLD, suggested_bid → NULL, reason → "direction violation
> held — <action> priced $X ABOVE the current $Y: a condemnation may never raise the bid"), same
> predicate, the file's no-drift rule. Deployed: 0 rows changed today (latent, as expected),
> assertion 0, pull-twice PASS (613 rows).

3 rows record a raise as a park. Add the direction guard at the output layer (v27.29 no-op pattern): any PARK/CUT_TO_BREAKEVEN whose suggested value > current bid resolves to HOLD with reason "park resolves upward — direction violation, held".

**Files:**
- Modify: `scripts/bigquery/views/V_KEYWORD_LIFT.sql` (output-layer guard block)

- [ ] **Step 1: Assertion before** (expect 3):
```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --max_rows=10 --format=csv "
SELECT campaign_name, target_text, current_bid, suggested_bid FROM \`onyga-482313.OI.V_KEYWORD_LIFT\`
WHERE action IN ('PARK','CUT_TO_BREAKEVEN') AND suggested_bid > current_bid + 0.005"
```
- [ ] **Step 2:** Add the guard in the final `SELECT ... REPLACE` wrapper, deploy, expect 0, pull-twice, commit.

### Task 1.6: Change-log completeness — `campaign_id` on the 126 legacy rows ⚠️ REQUIRES ORI'S EXPLICIT GO

> **✅ DONE 2026-08-16 — Ori's named go: "run the campaign_id backfill on FACT_PPC_CHANGE_LOG".**
> Root cause found first: all 126 were campaign-CREATION rows (116 competitor targets Jul 23–24,
> 7 SB, 3 cross-sell Jun 18) — the campaigns had no Amazon id yet when logged, so the writer
> stored name + empty id. Backfill by exact campaign name: **123 updated, 23 campaigns, all 123
> ids verified against V_DIM_CAMPAIGN_CURRENT.** The 3 leftovers carry NO name either (orphan
> cross-sell rows, keyless and inert — cannot join anything, cannot pollute grades; left as-is,
> documented). Effect: the July competitor build — past its read gate since ~Aug 7 — becomes
> gradeable on the scorecard's next read.

The writer once dropped campaign_id on 126 rows; new rows are clean (verified Aug 15: 0 missing since Aug 1). Backfilling FACT_PPC_CHANGE_LOG is a production-data UPDATE — Ori must name it before an agent may run it. Prepare the statement, show the dry-run counts, wait.

- [ ] **Step 1:** Build the mapping (keyword_id → campaign_id via DIM_KEYWORD) as a SELECT; show row count = 126 and 0 ambiguous.
- [ ] **Step 2:** Print the parameterized UPDATE for Ori. DO NOT RUN without his named approval in chat.

### Task 1.7: Kill the "BUDGET OK" lie on the 16 non-exempt campaigns

> **✅ DONE 2026-08-16 (v27.66).** The contradiction had DOUBLED since the finding: 26 campaigns
> exporting $501.31/day of cuts + $100.25/day of raises behind BUDGET_OK (was 16/$260 on Aug 13).
> Fixed at the source layer (V_COACH_CAMPAIGN_BUDGET): a BUDGET_OK label whose published number
> moves ≥ $0.01 (is_change's own threshold, so label and export can never flip apart) is overridden
> to BUDGET_DECREASE_PENDING / BUDGET_INCREASE_PENDING, with a `budget_action_note` sentence
> explaining the cooldown mask. Names chosen so V_WEEKLY_RUN_CAMPAIGN's existing LIKE
> '%DECREASE%'/'%INCREASE%' strategy classifier catches them with zero downstream changes. Both T_
> snapshots rebuilt. Assertion after: BUDGET_OK exports 0 (28 honest OKs remain); the moves now
> read 22 DECREASE_PENDING + 4 INCREASE_PENDING. No React change needed — no surface rendered the
> raw label as a badge (the "green badge" was the label reaching the apply set unrenamed).
> OPEN POLICY QUESTION for Ori, now visible instead of hidden: should the 3-day cooldown null the
> NUMBER too (nothing exports during cooldown), or keep exporting with the honest label as now?

16 campaigns export ~$260/day of budget cuts behind a green "BUDGET OK" badge. The badge logic contradicts the export.

**Files:**
- The badge is view-authored (find: `grep -rn "BUDGET OK" scripts/bigquery/views/ dashboard-react/src/`); fix the view string to state the pending cut and its size; the panel renders it as amber, not green.

- [ ] **Step 1:** Assertion: list the 16 (campaign, badge, pending cut $). Expected: badge text names the cut after the fix.
- [ ] **Step 2:** Deploy view + panel color keying off the view's severity field (no React logic), commit.

### Task 1.8: Remove the `manual_hold` flag (doctrine: fix the model, not manual carve-outs) — **RESEQUENCED**

> **⚠ PREMISE CORRECTED 2026-08-16, task DEFERRED behind Task 3.1.** Measured live: MANUAL_HOLD
> is NOT inert — it FIRES on 2 LIFT rows today (6 carry the flag; OOB: 0 firing / 2 flagged),
> actively protecting Ori's recent hand changes for their 7-day window (v27.48.2/v27.53 ITEM 8f).
> Removing it before `V_MANUAL_DIVERGENCE` exists would set the engines re-suggesting against
> Ori's hand with NOTHING learning from the disagreement — the exact opposite of the doctrine's
> intent. Order of operations: Task 3.1 ships the replacement (every manual change classified
> AGREED/OVERRODE and graded), runs alongside the hold for ≥ 2 weeks of verdicts, THEN this task
> removes the hold. Execute as Phase 3's closing step, not Phase 1's.

`manual_hold` is built and inert in LIFT/OOB. Under Ori's doctrine (engine 100% auto; a manual change means the MODEL needs fixing) it must go, replaced by the Phase 3 divergence loop.

**Files:**
- Modify: `scripts/bigquery/views/V_KEYWORD_LIFT.sql`, `V_OOB_KEYWORD.sql` (drop the column and its plumbing), `cube/schema/*.js` passthroughs, panels that read it.

- [ ] **Step 1:** `grep -rn "manual_hold\|manualHold"` across `scripts/ cube/ dashboard-react/src/` — enumerate every reader.
- [ ] **Step 2:** Remove column + readers in one pass; the panels lose nothing (the flag never fired). Deploy, typecheck, pull-twice, commit with a comment in each view header: "v27.6N: manual_hold removed — manual changes are LEARNED FROM (V_MANUAL_DIVERGENCE), not deferred to."

### Task 1.9: Fix the latent `ANY_VALUE` pairs (V_KEYWORD_LIFT SB arm, V_SB_LAUNCH_TARGET)

> **✅ DONE 2026-08-16 (v27.67).** Both sites replaced with the v27.46 dominant-ASIN pattern
> copied verbatim from V_OOB_KEYWORD's `prod` CTE (dominant mapped ASIN by all-history ad spend
> supplies BOTH cost and price — coherently paired, deterministic). Deployed defs verified via
> INFORMATION_SCHEMA; pull-THRICE byte-identical on both (LIFT SB arm 235 rows incl. roas
> columns; V_SB_LAUNCH_TARGET full 114 rows). Both were latent today (pulls agreed before the
> fix) — fixed on principle: latent ≠ absent, and the class already flipped a tier boundary once
> (0.89 vs 1.18) when it bit OOB. V_RUN_TARGET's instance was fixed earlier as v27.64 (Phase 0).
> **Every known ANY_VALUE pairing site in the engine is now closed.**

Same class as the v27.46 OOB fix: two `ANY_VALUE`s from one GROUP BY divided → nondeterministic ROAS. Both sites are known and latent.

- [ ] **Step 1:** Pull-twice each view; capture any diff (may be zero today — latent ≠ absent).
- [ ] **Step 2:** Replace with the deterministic dominant-ASIN pattern from `V_OOB_KEYWORD.sql` v27.46 (copy the CTE, cite it).
- [ ] **Step 3:** Deploy, pull-twice ×3 clean, commit.

### Task 1.10: `V_LOW_STOCK_ADS` emits `ad_group_id`; finish the low-stock apply-all

> **✅ DONE 2026-08-15.** View v27.63 deployed — `ad_group_id` through all four UNION branches
> (0 target proposals missing it; pull-twice byte-identical, 143 rows). Cube passthrough +
> LowStockPhase queue wiring + apply-all shipped and BROWSER-VERIFIED live: "apply all 45"
> (= 39 bid cuts + 6 paired budget cuts, matching BigQuery exactly); full pairing round-trip
> exercised — budget click queues the budget AND its sized-from bid cuts, unqueueing a paired
> target pulls the budget row with it, queue returned to exactly empty. The pairing claim was
> verified in the SQL first (camp_agg: suggested_budget = GREATEST(budget − SUM(dollars_freed),
> floor)). Stale "advisory only" footers on Revivals + Launch exemption corrected same day.
> **All three of Ori's requested panels (revivals, low stock, launch exemption) now queue.**

Blocked finding from 2026-08-15: the TARGET arm has `ad_group_id` upstream (`kw.cfg.ad_group_id`, ~line 986) but drops it before the output UNION — so its bid cuts can't become valid bulksheet rows.

**Files:**
- Modify: `scripts/bigquery/views/V_LOW_STOCK_ADS.sql` — carry `ad_group_id` into the TARGET branch of the output UNION; `CAST(NULL AS STRING) AS ad_group_id` in the FAMILY/ASIN/CAMPAIGN branches (same pattern as `bid_clamped_to_floor` in v27.60).
- Modify: `cube/schema/LowStockAds.js` — passthrough `adGroupId`.
- Modify: `dashboard-react/src/pages/LowStockPhase.tsx` — queue wiring + apply-all, EXACTLY the Revivals/LaunchExemption v27.63 pattern: one memoised `applicable` list feeds both count and click; TARGET+is_proposal → REDUCE_BID at `suggestedBid`; CAMPAIGN+suggestedBudget → BUDGET_CHANGE; FAMILY/ASIN never queueable; a keyword already claimed by another panel renders "other panel", never clobbered.
- **PAIRING RULE (critical):** the CAMPAIGN row's suggested budget is *summed from its target cuts*. Apply-all queues both together. Queueing a campaign budget row individually also queues its paired targets, or blocks with the reason visible. Never let the budget cut land without the bid cuts it was sized from.

- [ ] **Step 1:** Assertion: `SELECT COUNTIF(ad_group_id IS NULL) FROM V_LOW_STOCK_ADS WHERE row_kind='TARGET' AND is_proposal` — before: column doesn't exist (fails); after: 0.
- [ ] **Step 2:** View change, deploy, assert, pull-twice.
- [ ] **Step 3:** Cube passthrough + panel wiring + apply-all; typecheck clean; `npx vite build` passes.
- [ ] **Step 4:** Restart Cube note for Ori; commit (`--no-verify` for dashboard files).

---

## Phase 2 — The keyword state machine (the literal roadmap of each keyword)

### Task 2.1: `V_KEYWORD_STATE` — one row per keyword: state, owner, next appointment, and the 360° signal panel

> **✅ CORE DONE 2026-08-16** — `SP_SNAPSHOT_KEYWORD_STATE` → `FACT_KEYWORD_STATE` →
> `V_KEYWORD_STATE`, orchestrator Task 20.8, registered, SOP at architecture/KEYWORD_STATE.md.
> Pure assembly of the other snapshots' verdicts. First run: **877 keywords — 529 PARKED /
> 117 TRIAL / 92 WINNER / 46 DEAD / 45 LOSER_BLEED / 30 REVIVED_SETTLING / 11 PENDING_SETTLE /
> 7 PACED_WINNER; BOTH INVARIANTS PASS (0 duplicate states, 0 missing appointments).** Notable:
> some PARKED/TRIAL appointments are in the PAST (oldest 2025-11-16) — overdue re-checks now
> visible for the first time; a V_ENGINE_HEALTH "overdue appointments" check should read this.
> **REMAINING in this task:** the 360° signal panel (windows × scopes, settle-labeled — second
> half); SEASONAL_HOLD state (blocked on a season-gate snapshot); full event-sourced state_since.

This is the backbone the user asked for ("the roadmap of each keyword"). Everything above becomes legible through it, and its two invariants are the engine's standing self-check.

**360° SIGNAL PANEL (Ori 2026-08-15: "for each keyword the engine needs to be familiar of last
day, 3 days, 7 days, 14 days, 90 days, last year peaks — for the campaign and for the family").**
The state row ALSO carries the full signal panel: windows {1d, 3d, 7d, 14d, 90d, LY-peak} × scopes
{keyword, campaign, family}, each window as (clicks, spend, gp, gp_roas, cpc) + a `settled` flag
(1d/3d are PACING signals; 7d/14d/90d judge only when settled; LY-peak aligns by LEDGER OCCURRENCE,
never calendar date — reuse the season ledger, do not re-derive). Family scope generalizes the
Task 2.4 sibling-evidence insight: family evidence at the keyword row, systematically.
THE TWO-LANE RULE, stated as doctrine: **actions read few signals; audits read all of them.** A
rule's evidence window is part of the rule. The panel exists for humans and for the Task 3.2
grader — a signal enters an ACTION path only after the grader proves decisions split on it
(promotion pipeline). Measured precedent for both lanes: every speculatively-added live signal
lost (1-day raise, LY CPC rule, flat placement β); every major defect was found by an audit
reading signals the deciding rule ignored (FIT_CPC winner-starving via roas90, the 10
sibling-contradicted parks via family evidence, the GP bug via Amazon-vs-panel).
BUILD SHAPE: computed ONCE in this view and snapshotted daily (guard-snapshot pattern,
`SP_SNAPSHOT_KEYWORD_STATE` → `FACT_KEYWORD_STATE`, ~1k rows) — engines and audits read the
snapshot. Never let nine views each grow eighteen window columns locally; per-view window math is
exactly how the ANY_VALUE and wrong-grain bugs crept in.

**Files:**
- Create: `scripts/bigquery/views/V_KEYWORD_STATE.sql` (built as SP + `T_KEYWORD_STATE` if the planner objects — expect it to; follow the Task 1.1 materialize-then-join pattern)
- Create: `architecture/KEYWORD_STATE.md`
- Modify: `config.yaml`

**Column spec (complete — this IS the interface):**

| column | type | source |
|---|---|---|
| campaign_id, keyword_id, ad_group_id | STRING | DIM_KEYWORD config |
| target_text, match_type, channel, is_pt | STRING/BOOL | DIM_KEYWORD / campaign |
| family | STRING | V_CAMPAIGN_FAMILY_MAP |
| state | STRING | derived — exactly one of: `TRIAL`, `WINNER`, `PACED_WINNER`, `LOSER_BLEED`, `PARKED`, `PENDING_SETTLE`, `REVIVED_SETTLING`, `SEASONAL_HOLD`, `DEAD` |
| state_since | DATE | the change-log / ledger event that entered the state |
| owner_engine | STRING | `LOW_STOCK` \| `LAUNCH` \| `OOB` \| `REVERDICT` \| `LIFT` — the Task 1.1 precedence, computed from the same membership sources (V_LOW_STOCK_ADS critical families, V_LAUNCH_EXEMPTION exempt_active, V_CAMPAIGN_CAP_STATE.is_oob_owned, reverdict population, else LIFT) |
| current_bid | FLOAT64 | DIM_KEYWORD |
| settled_clk90, settled_roas90 | INT64/FLOAT64 | V_KEYWORD_GUARD |
| next_check_date | DATE | state-dependent: TRIAL→settle_due; PARKED→reverdict settle_due; REVIVED_SETTLING→its settle_due; SEASONAL_HOLD→season window open date; WINNER/PACED_WINNER→scorecard read date of the last change, else NULL+7d rolling |
| next_check_what | STRING | plain-English: what will be judged on that date |
| season_context | STRING | ledger label if any occurrence memory exists |
| state_reason | STRING | one sentence, view-authored |

**State derivation (precedence, first match wins):**
```sql
CASE
  WHEN tested_loser THEN 'DEAD'                                   -- ≥15 settled clk90, 0 orders
  WHEN is_parked AND reverdict = 'PENDING_SETTLE' THEN 'PENDING_SETTLE'
  WHEN is_parked THEN 'PARKED'
  WHEN revive_settling THEN 'REVIVED_SETTLING'
  WHEN season_entry_block THEN 'SEASONAL_HOLD'
  WHEN settled_roas90 >= 1.0 AND settled_clk90 >= 10
    THEN IF(paced_yesterday, 'PACED_WINNER', 'WINNER')            -- paced = brake fired on >4 clk
  WHEN settled_clk90 >= 10 AND settled_roas90 < 0.6 THEN 'LOSER_BLEED'
  ELSE 'TRIAL' END
```
Every input above is an EXISTING column in V_KEYWORD_GUARD / V_PARK_REVERDICT / the season ledger — the state view computes NOTHING new; it only assembles.

- [ ] **Step 1:** SOP with the diagram from this plan's header + the two invariants (below).
- [ ] **Step 2:** Assertion queries first (both must FAIL with "not found", then pass after deploy):

```sql
-- INVARIANT 1: every live keyword has exactly one state
SELECT campaign_id, keyword_id, COUNT(*) FROM `onyga-482313.OI.V_KEYWORD_STATE` GROUP BY 1,2 HAVING COUNT(*)>1;
-- expected: 0 rows
-- INVARIANT 2: no keyword without a next appointment (DEAD exempt)
SELECT COUNTIF(next_check_date IS NULL AND state != 'DEAD') FROM `onyga-482313.OI.V_KEYWORD_STATE`;
-- expected: 0
```
- [ ] **Step 3:** Build, deploy, run invariants, pull-twice, register, commit.
- [ ] **Step 4:** Surface: a compact state-distribution strip on Weekly Run (counts per state, owner split) — passthrough cube + render-only panel. This is diagnostic, not another action surface.

### Task 2.2: Kill the $1.00 activation floor at every remaining site

> **✅ DONE 2026-08-16 (v27.69).** 35 sites: LIFT's raise-destination expression (32 copies —
> `GREATEST(…, 1.00)` → floor $0.31, so NUDGE/VOLUME destinations follow the anchor instead of
> being dragged to $1), LIFT's flat `THEN 1.00` probe entry (2 arms — now 1.5× target CPC / winner
> CPC, floor $0.31 cap $2.00, raise-only: an anchored entry at/below current emits NULL), and
> OOB's ACTIVATE seat entry (anchored, floored $0.31, capped by the SEAT CPC — an entry the
> capped budget cannot fund just re-darkens the day — then $2.00, platform floor last).
> DOCTRINE SUCCESSION recorded in both files: the floor was Ori 2026-08-02 "i wont move if not";
> the Aug-9 post-mortem re-judged it ("real defect = $1.00 activation floor"). Anchorless rows
> keep $1.00 deliberately (no clearing price to read; wake-step prices down after).
> Verified: before 4 live $1.00-with-anchor suggestions → after **0**; flips LIFT 8 / OOB 5, all
> the intended shape (entries re-priced both directions: $0.58/$0.83 where anchors are cheap,
> $1.13/$1.27 where anchors justify more); pull-twice PASS both.

Known defect ("$1.00 entry floor is a defect"). ACTIVATE paths must price entry from evidence: `min(GREATEST(1.5 × target_cpc, 0.31), seat_cpc, 2.00)`; a keyword with a prior settled record enters at `min(pre-park bid, 1.1 × settled CPC)` (the reverdict calibration, already built — reuse, don't fork).

- [ ] **Step 1:** Enumerate: `grep -rn "1.00\|'\$1" scripts/bigquery/views/V_OOB_KEYWORD.sql V_KEYWORD_LIFT.sql | grep -i "activ\|entry\|seat"` — list every site.
- [ ] **Step 2:** Assertion: count of ACTIVATE/PROBE_START suggestions equal to exactly 1.00 with a target_cpc present. Before: >0. After: 0.
- [ ] **Step 3:** Replace each site with the calibrated expression, one shared comment. Deploy, assert, flip-count, commit.

### Task 2.3: Budget ladder's own evidence window obeys `V_PEAK_WINDOW_RULE`

> **✅ DONE 2026-08-16 (v27.70).** The ladder's in_peak + window length now read
> V_PEAK_WINDOW_RULE (local season CTE retired); every leg reads named evidence columns defined
> ONCE (`ev_s/ev_p`, `evc_s/evc_p` + labels) — off-peak keeps the deliberate v27.9 shape, in peak
> every leg follows w_days (3 ⇒ 3d+4-14d, 7 ⇒ 7d+8-28d). Reasons print the labels they judge.
> Assertion: every row in_peak=true / w_days=3 = the rule exactly (BTS, NOT_PROVEN → 3). Flips:
> 6 of 30, ALL evidence-widening — 5 HOLD→RAISE_WEAK (noisy anchor day was blocking raises the
> 3-day window supports; VIDEO- BALL "last 3d 1.32× → raise ×1.25") + 1 CUT→HOLD. Pull-twice
> PASS. `w_days` published. roas_1d/prev2 columns untouched (display + OOB keyword gate inputs).
> **PHASE 2 now complete** except 2.1's signal-panel second half.

The keyword engines switched to the proven 3d-in-peak rule; the budget ladder still judges a hardcoded last-day + prev-2d. Same rule, same burden of proof: 3d unless last year's same peak proved 7d better.

**Files:** `scripts/bigquery/views/V_OOB_BUDGET_PHASE.sql` + SOP.

- [ ] **Step 1:** Read `V_PEAK_WINDOW_RULE`'s consumption pattern in `V_KEYWORD_LIFT.sql` (w_days) and mirror it: the ladder's STRONG/CUT windows become (w_days, prev-w_days) instead of (1d, prev-2d) **during a peak only** — the off-peak dual-window shape stays (it was deliberately chosen in v27.9).
- [ ] **Step 2:** Assertion: in-peak, the ladder's window label equals the rule's w_days. Deploy, flip-count, commit.

### Task 2.4: Sibling-evidence reverdict — the loser→winner road (Ori 2026-08-15)

> **✅ DONE 2026-08-16 (v27.68).** V_TERM_FAMILY_EVIDENCE deployed (contribution grain — improved
> over the spec's aggregate grain so consumers can exclude their own campaign; anchor verified:
> "journal kit for girls" 4,157 sibling clicks at 1.347×). Both arms live in V_PARK_REVERDICT,
> evaluated only where own-record said CONFIRM_PARK; DEAD doubled bar; sibling-CPC-priced revive
> bid; all three outputs share the predicate. First run, all 6 rows HAND-VERIFIED: 1
> SIBLING_REVIVE ("diy journal kit for girls 8-14" EXACT — own 496c @ 0.97×, family broad proves
> 2.47×, revive $0.81) + 5 REDUNDANT — including the SAME term's broad instance correctly staying
> parked (exact sibling serves it): the serve-better rule cuts both directions on one keyword.
> Downstream patched: REDUNDANT = CONFIRM_PARK in both engines' confirm_park flags + LIFT's 8c
> shield (IN-lists); SIBLING_REVIVE ≠ REVIVE everywhere (no engine auto-activation, hand-queue
> only via the panel, excluded from apply-all — the read-this-first class). Snapshot re-run; panel
> + cube filters extended; SOP §7.12 written; registered. NOTE: revive count dropped 25→5 because
> Ori APPLIED the revivals batch — 30 keywords now REVIVED_SETTLING per the state machine.

A parked keyword generates zero data, so it cannot prove a trend changed on its own. Ori's rule:
judge it by the SAME TERM's performance in the family's OTHER campaigns — our own conversions on our
own listing, at click grain, from data we already own. Measured at design time: 10 of 104
CONFIRM_PARK rows had a sibling clearing the revival bar (worst case: "journal kit for girls"
parked while its sibling held 4,212 settled clicks at 1.32×). This is PROMOTE_TO_EXACT's inference
in the other direction — one rule, two directions. SQP market share (Task 4.4) is the FALLBACK eye
only, for terms with zero own traffic anywhere in the family.

**Files:**
- Create: `scripts/bigquery/views/V_TERM_FAMILY_EVIDENCE.sql`
- Modify: `scripts/bigquery/views/V_PARK_REVERDICT.sql` (new verdict arms)
- Modify: `architecture/SEASON_CONTEXT_LEDGER.md` §7 (the reverdict doctrine section)
- Modify: `config.yaml`

**Logic (complete):**

`V_TERM_FAMILY_EVIDENCE` — one row per (parent_name, LOWER(keyword_text)): settled clicks/orders/
GP-ROAS/CPC summed across ALL the family's campaigns from `V_KEYWORD_GUARD`, plus the best single
sibling (campaign_id, match_type, settled record, is it capped per V_CAMPAIGN_CAP_STATE). Pure
assembly — no new judgment inputs.

`V_PARK_REVERDICT` gains two arms, evaluated ONLY where the existing arms said CONFIRM_PARK (the
own-record verdicts stay untouched and rank first):

```sql
-- sibling slice EXCLUDES the row's own campaign — its own clicks are the evidence that parked it
WHEN sib.settled_roas90 >= 1.0 AND sib.settled_clk90 >= 10        -- the ONE revival bar, reused
 AND (   (own.match_type = 'EXACT' AND sib.match_type != 'EXACT') -- exact serves what broad finds, cheaper
      OR sib.is_capped                                            -- sibling proves it but can't fund it
     )
  THEN 'SIBLING_REVIVE'   -- revive_bid = LEAST(pre_park_bid, ROUND(1.1 * sib.settled_cpc90, 2)),
                          -- floored at k.revive_floor — a real anchor, never the probe entry
WHEN sib.settled_roas90 >= 1.0 AND sib.settled_clk90 >= 10
  THEN 'REDUNDANT'        -- the family already owns this term there; reviving would double-bid.
                          -- reason names the sibling: 'served by <campaign> at <roas>x — stay parked'
```

Guards carried over unchanged: one revive per season occurrence (`re_parked_this_occ`),
`manual_parked_recent` defers, settle discipline on the SIBLING's record (it is settled by
construction — V_KEYWORD_GUARD is the settled snapshot). DEAD (tested loser) rows are eligible for
SIBLING_REVIVE at a doubled click bar (≥ 20 sibling settled clicks) — the one-way door gets a
keyhole, opened only by own-family conversions.

- [ ] **Step 1: SOP** — add §"Sibling evidence" to the reverdict doctrine: the two arms, the
  redundancy rule, the double-bid rationale (cite the intent-grid legacy double-bid issue).
- [ ] **Step 2: Assertion before** (run against live views; this is the failing test):

```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --max_rows=5 --format=csv "
SELECT COUNTIF(reverdict='SIBLING_REVIVE') sib_revive, COUNTIF(reverdict='REDUNDANT') redundant
FROM \`onyga-482313.OI.V_PARK_REVERDICT\`"
```
Expected before: `Unrecognized name` (the arms don't exist). After: sib_revive + redundant ≈ 10
(today's measured overlap; both numbers > 0).
- [ ] **Step 3:** Build `V_TERM_FAMILY_EVIDENCE`, deploy, pull-twice. Spot-check: ("LolliME",
  "journal kit for girls") shows ~4,212 sibling clicks at ~1.32×.
- [ ] **Step 4:** Add the arms to `V_PARK_REVERDICT` (join the evidence view; planner rule — if it
  objects, materialize the evidence slice first). Deploy, run Step-2 assertion, pull-twice.
- [ ] **Step 5:** Hand-verify every SIBLING_REVIVE row (expect ≤ 10): the sibling is real, the
  match-type/capped test holds, the revive bid ≈ 1.1× sibling CPC. Verify every REDUNDANT reason
  names a live sibling.
- [ ] **Step 6:** The Revivals panel needs no new wiring — SIBLING_REVIVE rows flow through the
  reverdict='REVIVE'-family filter once added to the panel's filter list (one-line change +
  cube passthrough if the verdict string is new to it). Apply-all includes SIBLING_REVIVE only
  when the Step-5 hand-check passed once; REDUNDANT renders in the Park-confirmed section with
  its reason.
- [ ] **Step 7:** Register, commit.

---

## Phase 3 — The learning loop (the engine improves itself)

### Task 3.0: `FACT_ENGINE_PROPOSALS` — the engine remembers what it said

> **✅ v27.72, 2026-08-17 (Ori: "close the negate gap"):** the NEGATE lever is IN — INSERTs 8+9
> (V_OOB_SEARCH_TERM is_negate → OOB/LIFT; V_WEEKLY_RUN_NEGATIVE → COACH, live view because the
> T_ copy builds in Task 21 after this snapshot), grain='NEGATE', one row per (campaign, term),
> term keyed through preflight/health/divergence/DoPage gate; peak-converting negates REVIEW
> (first catch: "journal for girls", 47 peak orders). Manual negates now classify AGREED /
> ENGINE_SILENT in V_MANUAL_DIVERGENCE. 54 judged on day one (36 COACH / 14 OOB / 4 LIFT).
> The one unsnapshotted lever left: ADD_KEYWORD (research "+broad" offers).
>
> **FOLLOW-UPS from the 2026-08-16 review (named, still not built):** (1) add the coach's VALUE
> surfaces (V_COACH_CAMPAIGN_BUDGET WHERE is_change; V_COACH_APPLY bid rows) as engine='COACH'
> INSERTs — coach NEGATES are covered by v27.72, but hand-applied coach bid/budget suggestions
> still misread as ENGINE_SILENT in V_MANUAL_DIVERGENCE;
> (2) feed PHASE's peak evidence legs (ev_s) to V_OOB_KEYWORD's raise-gate arm so both engines
> judge one number (the reason was reworded honestly meanwhile); (3) OOB WAKE_STEP short still
> generic — author when wake columns join the OOB published set.

> **✅ BUILT EARLY, 2026-08-15** (Ori: "i can ask you daily what was planned, what actually
> happened and what are your action items"). Shipped DECOUPLED from Task 1.1: the table +
> `SP_SNAPSHOT_ENGINE_PROPOSALS` (7 single-view INSERTs, orchestrator Task 20.6) + `V_DAILY_BRIEF`
> (PLANNED / HAPPENED / VERDICT_NEW / ACTION_ITEM) are live; first snapshot = 212 proposals.
> Spec: `architecture/DAILY_BRIEF.md`. REMAINING in this task when 1.1 lands: add the preflight
> `verdict`/`verdict_reason` columns to the snapshot (the SP currently records instructions
> without contradiction verdicts), and fold NEGATE proposals in (known gap, stated in the SOP).

Nothing can learn without memory of its own opinions. Append, daily, every instruction every engine emitted — applied or not.

**Files:**
- Create: `scripts/bigquery/tables/FACT_ENGINE_PROPOSALS.sql` (DDL: `snapshot_date DATE, engine STRING, campaign_id STRING, keyword_id STRING, action STRING, suggested_bid FLOAT64, suggested_budget FLOAT64, current_bid FLOAT64, verdict STRING, verdict_reason STRING` — partitioned by snapshot_date)
- Modify: `SP_ENGINE_PREFLIGHT` (Task 1.1) — after building `T_ENGINE_PREFLIGHT`, append with an EXPLICIT column map (the T_ uses working names `cid`/`kid`/`sug_bid`; never `SELECT *` into a FACT):

```sql
DELETE FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
WHERE snapshot_date = CURRENT_DATE('America/Los_Angeles');
INSERT INTO `onyga-482313.OI.FACT_ENGINE_PROPOSALS`
  (snapshot_date, engine, campaign_id, keyword_id, action,
   suggested_bid, suggested_budget, current_bid, verdict, verdict_reason)
SELECT CURRENT_DATE('America/Los_Angeles'), engine, cid, kid, action,
       sug_bid, sug_budget, current_bid, verdict, verdict_reason
FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`;
```
- Schedule: the SP joins the existing daily orchestration (find the scheduler: `grep -rn "SP_ENGINE\|scheduled" config.yaml architecture/ | head`).

- [ ] **Step 1:** DDL + SP insert + dedupe. Deploy. CALL twice same day; assert row count unchanged after second call.
- [ ] **Step 2:** Register, commit.

### Task 3.1: `V_MANUAL_DIVERGENCE` — learn from Ori's manual changes

> **✅ DONE 2026-08-16** (with 3.2 and 3.3 — Phase 3 shipped as one batch; see each task's note).
> First census the day the first manual read-gates crossed: 89 changes, 24 graded —
> 5 CONFIRMED / 2 NEUTRAL / **9 REVERSED** / 8 INSUFFICIENT. All PRE_SNAPSHOT era; real
> AGREED/OVERRODE/ENGINE_SILENT classification begins with changes applied 2026-08-15+.
> The 1.8 clock STARTS NOW: MANUAL_HOLD comes out after this ledger runs ≥ 2 weeks (~Aug 30).

Doctrine: "if i change something manually you should ask why and if it is the right decision. if so we need to fix the model." Mechanize it.

**Files:**
- Create: `scripts/bigquery/views/V_MANUAL_DIVERGENCE.sql`
- Create: `architecture/MANUAL_DIVERGENCE.md`

**Logic (complete):** every `source='MANUAL'` row in the change log, joined to `FACT_ENGINE_PROPOSALS` on (campaign_id, keyword_id, snapshot_date = change date):
- `divergence_kind`: `AGREED` (manual value ≈ engine's proposal ±5% — Ori applied the coach by hand), `OVERRODE` (engine proposed differently), `ENGINE_SILENT` (no proposal that day — the engine missed something Ori saw).
- Join `V_CHANGE_SCORECARD` on the change key for the settled verdict.
- Output verdict per settled row: `MANUAL_BETTER` (Ori's change CONFIRMED where engine proposed the opposite direction), `ENGINE_BETTER` (Ori's change REVERSED and the engine had proposed holding/opposite), `TIE/PENDING`.
- The panel question, view-authored per OVERRODE row: "you did X where the engine said Y — settled verdict Z. Which rule should change?"

Until `FACT_ENGINE_PROPOSALS` has history, backfill what's answerable: the Aug 2–11 manual rows joined to scorecard only (no engine-side comparison), flagged `era='PRE_SNAPSHOT'`.

- [ ] **Step 1:** SOP; then assertion query counting Aug 2–11 MANUAL rows classified (expect 66 rows, all `PRE_SNAPSHOT` until snapshots accrue).
- [ ] **Step 2:** Build, deploy, register, commit.
- [ ] **Step 3:** Surface on Weekly Run as a small "Your calls vs the engine" panel (render-only). Every OVERRODE row where MANUAL_BETTER must end as either a threshold change (Task 3.2) or a documented disagreement — that's the SOP's closing rule.

### Task 3.2: `V_THRESHOLD_TUNER` — scorecard verdicts propose threshold changes AND discover missing signals

> **✅ CORE DONE 2026-08-16.** View + SP_WRITE_THRESHOLD_SUGGESTIONS deployed (SP hand-run at the
> weekly review, never scheduled; currently a deliberate no-op — live DE keys are coach-grain, so
> every ladder-grain proposal reads ADVISORY_ONLY, stated per row). First run: 6 proposals with
> published era_splits + the seeded park-calibration suggestion. **Headline finding: BID_UP
> reverses at 42–57% across EVERY step size (n=24–37 per cell) — the step was never the variable;
> the missing signal is.** That question is queued for the signal-discovery half, which is
> PENDING DATA by design (panel history from Aug 16, grades from ~Aug 29): first counterfactual —
> does family context separate good raises from bad.

`DE_COACH_THRESHOLDS` already has `suggested_value / suggested_at / suggestion_reason` per (family, threshold). The tuner fills them; Ori promotes to `threshold_value`; SQL reads only `threshold_value`. ADVISORY ONLY — no auto-apply in this plan.

**SIGNAL DISCOVERY (Ori 2026-08-15: "when checking engine performance that will bring more signals
to check if the decision should be decided differently").** The tuner's second half is the
COUNTERFACTUAL AUDIT: for every graded change, attach the Task 2.1 signal panel AS OF the change
date (from `FACT_KEYWORD_STATE` history; reconstruct from FACT for pre-snapshot eras), then split
verdicts by each signal the deciding rule did NOT read. Output rows read like: "raises where
family trailing-7d GP-ROAS < 0.8 reversed at 78% vs 54% overall — propose a family gate on
raises." Promotion bar, non-negotiable: (a) ≥ 20 graded changes per cell, (b) the split must hold
in TWO separate eras (guards against one bad fortnight becoming doctrine), (c) the proposal names
the exact rule + gate it would add — vague "consider X" rows are forbidden. First question to
feed it once proposal history settles (~Aug 29): did campaign/family context separate the good
raises from the bad — the raise side is the engine's measured weak spot (54% reversed, −1.16×
average) and the likeliest place a 360° signal pays first.

**Files:**
- Create: `scripts/bigquery/views/V_THRESHOLD_TUNER.sql`
- Create: `scripts/bigquery/procedures/SP_WRITE_THRESHOLD_SUGGESTIONS.sql` (writes the top proposals into `DE_COACH_THRESHOLDS.suggested_*`; UPDATE of a DE_ table = data-entry surface, allowed, but log each write)
- Create: `architecture/THRESHOLD_TUNER.md`

**Logic (complete):** aggregate `V_CHANGE_SCORECARD` over settled verdicts, minimum 20 graded changes per cell:
```sql
SELECT action, step_bucket, tier, COUNT(*) n,
       COUNTIF(verdict='CONFIRMED')/COUNT(*) confirm_rate,
       COUNTIF(verdict='REVERSED')/COUNT(*)  reversed_rate
FROM graded GROUP BY 1,2,3 HAVING n >= 20
```
Proposal rules (each maps to a named threshold row):
- `reversed_rate > 0.40` on a step bucket → propose the next-gentler step for that band.
- `confirm_rate > 0.70` on raises in a band → propose widening the raise gate one notch.
- Park calibration: the measured OFF-only shape (+$2,020) becomes the first written suggestion.
Reason string cites the numbers: "38 REVERSED of 61 cuts at −15% in band 0.6–1.0 over 8 weeks".

- [ ] **Step 1:** SOP; assertion = tuner emits ≥1 proposal on current history (the park calibration at minimum).
- [ ] **Step 2:** Build view + SP, deploy, run once, verify `suggested_*` populated and `threshold_value` UNTOUCHED. Register, commit.
- [ ] **Step 3:** Admin panel shows suggestion vs current with an accept affordance that copies suggested→value via the existing Flask data-entry path (`/api` conventions; NOT `@login_required` on `/api` routes).

### Task 3.3: `V_ENGINE_HEALTH` — the weekly self-check, one row per check

> **✅ DONE 2026-08-16.** Nine checks live, first board immediately diagnostic: **RED
> contradiction_rate 31.8%** (57/179 — the gate works; the finding is that the engines
> STRUCTURALLY generate a third of their instructions on each other's keys, mostly LAUNCH
> proposing on LOW_STOCK-owned families — the refinement is to stop generating the overlap, not
> just silencing it), **AMBER overdue_appointments 78** (oldest 2025-11-16 — judgments due that
> nothing re-ran, visible for the first time), **AMBER scorecard_reversed_share 41.1%** (trailing
> 42d), six GREEN incl. both state invariants, single-voice, snapshot freshness. Joins the Weekly
> Run summary strip when Phase 6 builds it.

The engine "always checks himself": a standing scoreboard, green/amber/red, rendered at the top of Weekly Run.

**Checks (complete list, each a UNION arm with `check_name, status, measured, threshold, detail`):**
1. contradiction_rate — EXCLUDE share in T_ENGINE_PREFLIGHT (amber > 5%, red > 15%)
2. ownership_overlaps — keys with >1 GO instruction (red > 0)
3. state_invariants — Task 2.1's two invariants (red on any violation)
4. noop_rate — share of instructions that are no-ops (amber > 10%: the ladder is thrashing)
5. scorecard_mix — REVERSED share trailing 4 settled weeks (amber > 35%)
6. manual_divergence — OVERRODE count last 7d with no resolution (amber > 0 after 14d)
7. settle_veto_hits — changes blocked by settle guards last 7d (informational)
8. snapshot_freshness — FACT_ENGINE_PROPOSALS max(snapshot_date) (red if > 2d old)
9. determinism_spot — pull-twice hash of V_OOB_KEYWORD's (key, action, bid) done in the SP (red on mismatch)

- [ ] **Step 1:** SOP + build + deploy + register; assertion: 9 rows, each with a non-null status.
- [ ] **Step 2:** Weekly Run header strip (render-only). Commit.

---

## Phase 4 — Context awareness (seasonality · launch · peaks · competitors)

### Task 4.1: SB-specific fresh windows

SB day-1 sales are ~17.5% understated (SP 3–6%). Every short-window judgment on SB rows either (a) excludes the freshest day, or (b) carries an SB haircut factor read from one place. Choose (a) — simpler, no invented constant: SB short windows shift back one day (`[T-2, T-1]` where SP uses `[T-1]`).

- [ ] **Step 1:** Enumerate SB short-window sites: `grep -n "is_sb\|channel='SB'\|sb_" scripts/bigquery/views/V_OOB_KEYWORD.sql V_OOB_BUDGET_PHASE.sql V_LOW_STOCK_ADS.sql | grep -i "1d\|last_day"`.
- [ ] **Step 2:** Assertion: an SB row's "last day" label and window dates. Apply the shift, deploy, flip-count (expect small), commit.

### Task 4.2: Seasonal-term routing — the 90d gate becomes engine-enforced

The rule exists as feedback ("holiday terms in seasonal campaign; 90d gate"). Enforce: ADD_KEYWORD proposals whose term matches a season ledger occurrence route to the family's seasonal campaign; outside the 90d pre-window they are `SEASONAL_HOLD` (state machine Task 2.1 already carries the state).

- [ ] **Step 1:** Find the ADD_KEYWORD emitter (research playbook: `is_research` → "+broad" adds): `grep -rn "ADD_KEYWORD" scripts/bigquery/views/`.
- [ ] **Step 2:** Join the ledger; assert: 0 seasonal-matched adds routed to non-seasonal campaigns; adds outside the window emit `SEASONAL_HOLD` with the window-open date as next appointment. Deploy, commit.

### Task 4.3: Launch negatives — close the gap

New campaigns ship with NO negatives; the backfill xlsx was built and never uploaded.

- [ ] **Step 1:** Regenerate the backfill from current data (the old file is stale); present to Ori for upload (uploads are his).
- [ ] **Step 2:** Fix the template: the campaign-creation path includes the standard negative set (brand terms per feedback_brand_term_negation, known account-level losers) so the gap can't recur. Find: `grep -rn "negative" tools/ scripts/bigquery/ | grep -i "template\|launch"`.

### Task 4.4: Competitor awareness — minimal, evidence-based (no new data sources)

Three concrete pieces, all from data already owned:
1. **`DE_COMPETITOR_BRANDS`** (the standing TODO): seed from DIM_PRODUCT competitor ASINs' brands + the research page's brand segmentation; register; the research views read it instead of their local heuristic.
2. **Term-level market share signal:** SQP `market_purchases90d` vs our purchases → `market_share_90d` exposed on the conquest/PT surfaces (OobSearchTerm already carries the inputs). No bid rule yet — publish the number beside PT bids so divergence is visible. (A bid rule needs the intent-coverage gate first.)
3. **Brand-term negation audit:** assert every non-defense campaign negates the brand terms (`feedback_brand_term_negation`); emit missing pairs as NEGATE proposals through the normal surface.

- [ ] **Step 1:** DDL + seed + register DE_COMPETITOR_BRANDS; commit.
- [ ] **Step 2:** market_share_90d passthrough (view + cube + panel column). Commit.
- [ ] **Step 3:** Audit query → assert count of uncovered (campaign, brand-term) pairs; wire the proposals; deploy; commit.

### Task 4.5: Intent-coverage gate (guard, not build)

The intent CVR curve stays unbuilt until occasion-tag coverage ≥ 60% of ads clicks (now ~27%). Add the coverage number to `V_ENGINE_HEALTH` (informational row) so the gate is visible instead of remembered.

- [ ] **Step 1:** Add check #10 to Task 3.3's view. Deploy, commit.

---

## Phase 5 — Deploys that verify themselves

### Task 5.1: `tools/deploy_view.py` — the only sanctioned way to deploy an engine view

"Deployed unverified" (v27.48, v27.62) becomes structurally impossible: one deterministic tool that does backup → deploy → verify → report, and refuses to leave a view in an unverified state.

**Files:**
- Create: `tools/deploy_view.py`
- Create: `architecture/DEPLOY_PROTOCOL.md`
- Modify: `config.yaml` (per-view verification config: key columns, anchor assertions)

**Behavior (complete):**
1. `cp FILE.sql FILE.sql.bak.<version>.<HHMM>`
2. deploy via `bq query` (strip `--` comments)
3. pull-twice determinism on (key, action, suggested value) — hash compare
4. run the view's registered anchor assertions from `config.yaml` (e.g. V_OOB_KEYWORD: "VIDEO- BALL surprise balls, roas90 ≥ 1.0 → bid_action=HOLD when clk1 ≤ 4")
5. decision-flip report vs the bak (deploy bak to `V_TMP_DEPLOYCHECK`, diff, drop)
6. print PASS/FAIL; on FAIL, auto-revert from the bak and say so loudly
7. append the whole run to `progress.md`

- [ ] **Step 1:** Write the tool (argparse: `--view V_OOB_KEYWORD [--skip-flip-report]`); config schema in `config.yaml` under each view's entry: `verify: {keys: [...], anchors: [{name, sql, expect}]}`.
- [ ] **Step 2:** Test on a no-op redeploy of `V_OOB_KEYWORD` (deploy the identical file): expect PASS, 0 flips.
- [ ] **Step 3:** Seed anchors for the 5 heavy engine views (one anchor each minimum — the known truths from this plan's Phase 0/1 assertions).
- [ ] **Step 4:** SOP: every future engine deploy uses the tool. Commit.

---

## Phase 6 — Weekly Run 5-second / 5-minute UX (companion document)

> Added 2026-08-16 at Ori's direction. Full plan: `docs/superpowers/plans/2026-08-16-weekly-run-5s-5min.md`.
> **Goal:** accept any action in 5 seconds; understand every change AND every unchanged keyword in
> 5 minutes. **Why it belongs to this plan:** it is the consumption layer of Phase 1/3's data
> machinery — the summary strip and unified Today's-decisions feed read `T_ENGINE_PREFLIGHT` +
> `FACT_ENGINE_PROPOSALS` (small tables, seconds) while the 17 criteria sections become lazy
> drill-downs. Its Task 1 (snapshot learns `ad_group_id`) amends this plan's Task 3.0 objects; its
> UNCHANGED taxonomy upgrades to `V_KEYWORD_STATE` when Task 2.1 lands; `V_ENGINE_HEALTH`
> (Task 3.3) joins its summary strip when built. Runs parallel to Phase 2 — nothing blocks.

## Dependency order & what needs Ori

```
0.1 → 0.2 → 1.1 → {1.2, 1.3, 1.4, 1.5, 1.7, 1.9, 1.10} → 2.1 → {2.2, 2.3, 2.4}
                 1.1 → 3.0 → 3.1 → 3.2 → 3.3 → 4.5
independent after 1.1: 4.1, 4.2, 4.3, 4.4, 5.1 (5.1 early is BETTER — later tasks deploy through it)
1.6 and 1.8: any time; 1.6 blocked on Ori's named go.
```

**Decisions Ori must make (the plan proceeds around them until answered):**
1. **Task 1.6** — say the words to run the 126-row campaign_id backfill UPDATE, or drop it.
2. **Task 3.2** — confirm the tuner stays advisory-only (this plan assumes yes; auto-apply with a confidence gate is a later plan).
3. **Task 4.4** — confirm competitor scope stays minimal (no price/BSR scraping, no new data sources) for this plan.
4. **Ownership precedence** — Task 1.1 encodes LOW_STOCK > LAUNCH > OOB > REVERDICT > LIFT. Confirm REVERDICT above LIFT (a revival beats a portfolio nudge) — the plan assumes yes.

**What I added beyond the request (the "anything else"):**
- Phase 0 verify-first — the GP fix underneath everything is deployed but unverified; building on it without Step 0 repeats the v27.48 mistake.
- `FACT_ENGINE_PROPOSALS` (Task 3.0) — self-improvement requires the engine to remember what it *proposed*, not only what was *applied*; without it, "learn from manual changes" can only ever grade Ori, never the engine.
- Threshold consolidation happens through the EXISTING `DE_COACH_THRESHOLDS` suggestion channel rather than a new table — less machinery, same loop.
- Task 5.1 deploy protocol — "the engine checks itself" must include checking its own deployments; twice now a version shipped unverified.
- The state machine's two invariants (one state, one next appointment) as standing health checks — "strive for perfection" needs a definition of broken.

### Task 4.6: Low-stock REDIRECT arm — re-aim the family, brake only when there's nowhere to aim

> Ori 2026-08-17: "if one variation is out of stock we should change the target of the out of
> stock target to the best high demand variation we have in stock. we should cut budget if we
> have only low demand variation or the entire family is out of stock." Plus the return half:
> "when it is back in inventory recheck if we want to change it back or leave it" — a REMEMBERED
> re-decision with evidence, never an automatic revert.

**Why (measured, Bunny 2026-08-17):** family ads sell the LISTING, not the advertised ASIN —
77.6% of Bunny ad units land on a sibling of the advertised doorway; Bestie (binding, 20d cover)
has ZERO own-ad sales; Proud ties it at 1.43/day with 252d cover. Braking the family sacrifices
in-stock sibling sales to save ~0.25/day of drain ("buys 0.8 days"). Re-aiming keeps the sales
and removes the doorway.

**The rule ladder (family graded on the binding variation, as today):**
1. REDIRECT — binding variation heading dry AND best in-stock sibling (FBA cover ≥ 60d) has
   7d-rate ≥ 50% of the binding rate → per (ad group advertising the dry ASIN, from
   V_SRC_AmazonAds_advertised_product, ad_id included): PAUSE the dry ASIN's product ad +
   CREATE the hero's. Bids and budgets UNTOUCHED. Waste-parks (non-converting) still allowed.
2. BRAKE — only low-demand siblings in stock (best < 50% of binding rate) → today's bid/budget
   model.
3. FULL BRAKE — whole family dry → today's model, strongest arm.

**The return recheck:** DE_AD_REDIRECTS ledger (one row per redirect: family, out_asin,
hero_asin, campaign, ad_group, out_ad_id, redirected_at, status ACTIVE/RESTORED/KEPT), written
at bulksheet export (DE_NEGATIVE_KEYWORDS precedent). V_AD_REDIRECT_RECHECK: ACTIVE redirects
whose out_asin is back (cover ≥ 45d) AND ≥ 14d of hero-doorway data → RECHECK row with the
evidence (hero doorway units/CVR since redirect vs the out ASIN's pre-redirect doorway) and a
suggestion — RESTORE (re-enable out ad + pause hero ad, both by ad_id) or KEEP. Ori decides.

**Spine:** REDIRECT/RECHECK rows ride FACT_ENGINE_PROPOSALS (grain='REDIRECT', aux_id carries
hero asin|sku, keyword_id slot carries the ad_id to pause) → preflight (lever REDIRECT, key =
ad_group|dry_asin) → feed. DoPage: PAUSE_PRODUCT_AD export branch (Product Ad Update by ad_id)
+ ledger POST. SB video creatives cannot be swapped — they stay on the brake arms.

### Task 4.7: Complete-days window convention — every window ends on the last complete day

> Ori 2026-08-17 (after catching dashboard 35c vs console 56c on "the same 3 days"):
> last day = Aug 16 · 3d = Aug 13–15 · 7d = Aug 9–15 · 28d = Jul 19–Aug 15 — "this is the correct."

**Rule:** wm = newest loaded ads day. `last_day` = wm alone (the filling day, labeled fresh —
day-1 data is 88–90% complete). EVERY multi-day window ends at wm−1: 3d = [wm−3, wm−1],
7d = [wm−7, wm−1], 28d = [wm−28, wm−1], 90d = [wm−90, wm−1]. Settled windows unchanged (already
end D+7/D+14 back). Result: every dashboard window matches an Amazon-console range of complete
days exactly — this class of verification confusion dies.

**Sites (scoped 2026-08-17):** V_OOB_KEYWORD (~13 INTERVAL sites), V_KEYWORD_LIFT (~6),
V_OOB_SEARCH_TERM, V_OOB_BUDGET_PHASE — plus the differently-spelled idioms in V_LOW_STOCK_ADS
(3d halve decision window!), V_KEYWORD_DAILY / coach windows, V_TERM_FAMILY_EVIDENCE. Note the
decision arms that consume 1d/3d (zero-sale brake clk1/roas1; dark-brake 3d; low-stock 3d
halve): inputs get one day older and one day more complete — the safer direction, but re-verify
each arm's before/after flip report. UI: window column headers/tooltips print the actual date
span ("3d = Aug 13–15"). Deploy battery: backups, pull-twice, flip reports per view.

### Task 4.8: The last-day veto — the fresh day can only say "wait", never drive

> Ori 2026-08-17, verbatim: the "last day" in all scenarios can
> 1. "stop raise if last days had more than 10 clicks with poor performance (wait to see if it
>    is performance is raised the day after)"
> 2. "stop bid reduction if last days had more than 10 clicks with very good performance (wait
>    to see if it is performance is reduced the day after)"

**The design (completes Task 4.7):** complete-day windows DECIDE moves; the standalone filling
day (last day) is a symmetric one-day VETO at real volume — it never initiates anything:
- RAISE arm + clk1 > 10 AND poor yday → HOLD, reason "yday: Nc at X.XXx ⇒ wait a day"
- REDUCE/park arm + clk1 > 10 AND very good yday → HOLD, same grammar, opposite sign
- "Wait to see the day after" needs NO state: the engines re-run daily; if the signal persists
  into the complete windows the move fires tomorrow on settled ground.
**Default bars (Engine SQL + DE_COACH_THRESHOLDS per doctrine; Ori can tune):**
poor = gp-roas1 < 0.5 (or 0 sales); very good = gp-roas1 >= 1.2 (the proven-winner bar).
**Sites:** the raise + reduce arms of V_KEYWORD_LIFT and V_OOB_KEYWORD (build AFTER Task 4.7
lands — same files); coach INCREASE/REDUCE arms follow. The veto must appear in the no-drift
action/value/reason ladders identically, and the HOLD publishes as its own short so the panel
says WHY the move waited. Interlock: the existing wave veto stays untouched (1-day-signal
verdict memory: never tighten it) — this veto HOLDS moves, it never creates raises.

> **✅ Task 4.7 DONE, v27.74 (2026-08-17).** 62 sites across 5 views (LIFT 10, OOB_KEYWORD 14,
> OOB_SEARCH_TERM 21, OOB_BUDGET_PHASE 12, LOW_STOCK 5), all deployed, flip reports per view.
> Verifier: BoxPink 3d raw 56 = view 56; two OOB reconciliations exact; pull-twice identical on
> both heavy engines; zero MISSED sites. Live effects: 7 negate offers died (were riding
> partial-day clicks); VIDEO-BALL 3d GP-ROAS 0.72→1.09 (filling day out — halves spared); OOB
> actions ACTIVATE 8→7 / DARK_BRAKE 33→35 / TRIM 5→4. Panels catch up at the next T_ rebuild.
> OPEN NOTES for Ori: (a) prev2 already ended at wm-1 — should it re-anchor to the 2 days before
> the last COMPLETE day? (b) probe-episode evidence still includes the filling day (20-click
> probe verdicts can read partial data); (c) the new 7d shares day wm-7 with the settled 8-28
> leg (one-day overlap, settle window untouched by scope); (d) OOB_SEARCH_TERM big-word age gate
> is 89 complete days under the new framing (pre-existing, INTERVAL 90 if strict).

> **✅ Task 4.8 DONE, v27.75 (2026-08-17).** Last-day veto live in BOTH bid engines as a thin
> outer wrapper (lastday CTE 10 / 0.5 / 1.2; two booleans computed once; pub.* EXCEPT REPLACE over
> action/suggested_bid/reason/reason_short). Verified: zero escapes both directions both views;
> 7 vetoed rows today (LIFT 3 raises, OOB 4 cuts) each satisfying its predicate with bid NULLed;
> zero-sale floor intact (15 OOB cuts at 0.00x — structurally cannot meet the 1.2x cut bar); no
> schema leak (101 cols unchanged); pull-twice MD5 identical on both; budget arms untouched;
> grammar clean. Note: OOB's raise arm and LIFT's cut arm had no live candidates today —
> data-dead, not code-dead (both probed directly).
>
> **WATCH ITEM (measured 2026-08-17, Ori's call — the one thing that could turn a "wait" into a
> permanent block):** the two arms do NOT carry equal evidence. A filling day reading >= 1.2x is
> RELIABLE — attribution is still accruing, so true ROAS can only rise; the cut veto is sound and
> its 4 firings today were textbook. A filling day reading 0.00x is AMBIGUOUS — "no sales" and
> "sales not attributed yet" are indistinguishable (SP settles ~D+7, SB ~D+14). Measured: of
> keywords at >10 filling-day clicks, 46% read exactly 0.00x (SB 50%, SP 42% — NOT an SB-specific
> effect, contra the build agent's concern), 17% read >= 1.2x, 20% poor-but-nonzero. All 3 raise
> vetoes today were 0.00x rows. RISK: if a keyword takes >10 clicks EVERY day and its filling day
> always reads 0.00x, its raise is vetoed every day = permanent block, which is NOT Ori's rule
> ("wait to see if performance is raised the day after" = wait ONE day, then decide).
> DETECTION: watch the daily brief for the same keyword+raise vetoed on consecutive days.
> IF IT APPEARS, the faithful fix is a REPEAT-GUARD (a raise may be vetoed at most once; the next
> day it proceeds) — needs the veto recorded in the daily snapshot, since vetoed rows become HOLD
> and HOLDs are not snapshotted. Do NOT pre-build: measure first.

### Task 4.9: The expected-orders gate — the raise veto must know a bad day from a quiet one

> Ori 2026-08-17, after the worked example: "build the expected-orders gate."

**The flaw it fixes (measured, not theorised):** at age 1 we see ~85% of a day's spend but only
~69% of its sales (V_ADS_SETTLE_CURVE), and 46% of at-volume keywords read exactly 0.00x on the
filling day. BOX-SP/AUTO (Pink) "substitutes" converts once per ~42 clicks and has zero-order days
6 times in 13; on the filling day it took 45 clicks (≈1 expected order), got 0 — and its raise was
vetoed. That is an ordinary Tuesday for a 2.7x keyword, not poor performance. Because it is busy
daily, its raise would be blocked ~63% of days forever — the opposite of "wait a day".

**The rule.** Split the raise arm by whether the poor reading is INFORMATIVE:
- `roas_1d > 0 AND < 0.5` — sales landed and were poor: real evidence, veto as before, no gate.
- `roas_1d = 0 or NULL` — ambiguous: veto ONLY IF `expected_orders_1d >= 3.0`, where
  `expected_orders_1d = clicks_1d * (orders_window / clicks_window)` on the keyword's OWN complete-day
  rate. Poisson: P(0 | λ=3) ≈ 5% — "a 1-in-20 event, not a Tuesday".
- No rate computable / never converted → expected 0 → NO veto. The veto may only block when it HAS
  evidence; whether a never-converting keyword deserves a raise belongs to the complete-day ladders
  and the zero-sale floor, never to the veto.
**The cut arm is untouched by design** — missing sales can only make a day look worse, so a fresh
day already at >= 1.2x is conservative proof. The asymmetry in the code mirrors a real asymmetry
in the evidence.
**Rate window:** longest complete-day pair available (prefer 90d; never includes the filling day).
OOB publishes clk90/ord90 additively for it; LIFT uses its published clicks_w/orders_w or a longer
leg if one exists.

> **✅ Task 4.9 DONE, v27.76 (2026-08-17).** Gate live in both engines. LIFT: all 3 raise vetoes
> RELEASED, each justified — "substitutes" 49c, 90d 18 ord/720 clk, expected 1.225 (Ori's worked
> example, raise republished AUTO_RAISE $0.64→$0.74); "gifts for tween girls" exp 0.568; "gift for
> teen girl" exp 0.338. OOB: 3 cut vetoes byte-identical (cut arm has no gate by construction).
> Verified: no wrong releases, no wrong blocks, zero-sale floor intact (16 rows, MD5 matched),
> additive-only schema (clk90/ord90/expected_orders_1d in OOB; clicks_90d/orders_90d in LIFT),
> pull-twice identical both views. Rate = 90d complete-day pair (never the filling day).
>
> **FINDING FOR ORI — the zero-reading branch is dormant at this account's volume.** Of 31 LIFT
> rows reading 0.00x at >10 clicks, ZERO reach 3.0 expected orders; account-wide max today is 2.10.
> At 1–2.5% order rates a keyword needs ~120–300 clicks IN ONE DAY to clear the bar. So in practice
> the raise veto now fires only on the informative branch (sales landed, 0 < roas_1d < 0.5). That is
> the correct answer to "is one quiet day evidence?" — at this per-keyword volume it never is — but
> it means the zero-day protection Ori asked for is mathematically unavailable, not merely unused.
> Lever: `veto_min_expected_orders` in the lastday CTE (3.0 → P(0)≈5%; 2.0 → 13.5%; 1.5 → 22%).
> Sub-notes: negative roas_1d counts as INFORMATIVE (money moved) — confirm if that should be gated
> instead; 136 LIFT rows have no 90d history and are structurally exempt; roas_1d is ROUND(_,2) so a
> sub-0.005 ROAS routes to the gated branch.

### Task 4.10 (URGENT, opened 2026-08-17 20:13): V_PANEL_OWNERSHIP no longer plans
**Symptom:** `SELECT COUNT(*) FROM V_PANEL_OWNERSHIP` fails deterministically with "Not enough
resources for query planning — too many subqueries or query is too complex" (dry-run reproduces).
**Timeline (causation is ours):** FACT_PANEL_OWNERSHIP last written 10:50 IDT (07:50 UTC
orchestrator, OK) — BEFORE any of today's edits. All edits landed 10:58 → 19:19 (v27.73 redirect
mode + v27.74 windows on V_LOW_STOCK_ADS; v27.75/76 on the bid engines). First run afterwards,
16:24, FAILED. V_PANEL_OWNERSHIP INLINES V_LOW_STOCK_ADS (line 163), which grew twice today.
**Consequence if unfixed:** tomorrow's 07:50 UTC ownership snapshot fails → FACT_PANEL_OWNERSHIP
goes stale → the single-home rule, DEFER_* routing and panel membership all read yesterday's
ownership. The preflight still blocks contradictory uploads, so this is a legibility/routing
break, not an upload-safety break.
**Fix (house pattern, fact_oi_cube_table_planner_blowup):** stop inlining the ceiling view —
materialize T_LOW_STOCK_ADS inside SP_SNAPSHOT_PANEL_OWNERSHIP before the ownership build and
point V_PANEL_OWNERSHIP at the T_. Ordering constraint: the ownership snapshot (20.5g) runs BEFORE
the cube T_ builds (Task 21), so it must build its own copy, not reuse Task 21's.

> **✅ Task 4.10 DONE, v27.77 (2026-08-17).** V_PANEL_OWNERSHIP plans and runs again. ONE source
> needed materializing: T_LOW_STOCK_CAMPAIGN, a pure pass-through slice of V_LOW_STOCK_ADS's
> CAMPAIGN rows, built by SP_SNAPSHOT_PANEL_OWNERSHIP immediately before the ownership table. No
> semantics moved — the roll-up, both claim arms and the ladder stay in the view. VERIFIED: view
> plans + runs (93 rows); SP idempotent (two runs, MD5 8da1a289974c07de16a936bca003c3a7 both
> times); slice provably identical to the live view's own campaign rows; ZERO owner flips across
> all 93 campaigns (owner / owner_rank / claim_scope / claim_rank / defer_* / low_stock_state all
> unchanged vs the 10:50 backup); 95→93 is two campaigns PAUSED during the day, both LAUNCH-owned,
> neither a low-stock claim; every consumer dry-runs clean (orchestrator, cube, engines, reverdict).
> Rollback copy FACT_PANEL_OWNERSHIP_bak_v2777 left in the dataset — DROP once tomorrow's 07:50 UTC
> run is green.
> **config.yaml repaired (my defect):** tonight's Task 4.6 registrations were appended to the file
> tail, landing inside the `monitoring:` mapping and breaking the YAML parse for every tool that
> loads it. Relocated: DE_AD_REDIRECTS + T_LOW_STOCK_CAMPAIGN → `tables:`, V_LOW_STOCK_REDIRECT +
> V_AD_REDIRECT_RECHECK → `views:`. Parses clean: views 203, tables 127, procedures 92,
> cloud_functions 1 (unchanged, verified against the pre-fix backup).

### Task 4.11 (OPEN, found by the 4.10 verifier): redirect mode blinded ownership's arm B
**The coupling I missed in v27.73.** V_PANEL_OWNERSHIP's LOW_STOCK claim has two arms: A structural
(family risk_state='CRITICAL') and B instructed (a campaign-row suggested budget OR ≥1 proposal
target). Arm B exists specifically for BUNNY-SP/AUTO (Brave): a family grading WATCH, not CRITICAL,
that low stock is nevertheless cutting while Portfolio proposes a raise. v27.73's redirect gate
sets is_proposal=FALSE on bid-cut rows in redirect-mode families, so ls_proposal_targets collapsed:
10 of 14 low-stock campaigns now read 0, and 5 (BALL-SP/AUTO White, BUNNY - COMPETITORS,
BUNNY-SP/AUTO Birthday, BUNNY-VIDEO/BROAD Hunter, VIDEO- COMP/BALL) carry neither a suggested
budget nor a proposal target. They keep the claim ONLY because arm A fires today.
**The live risk:** a family in redirect mode that grades WATCH instead of CRITICAL gets NO claim —
arm A silent, arm B blind — so the engines are free to raise bids into a stock problem. That is
precisely the contradiction ownership exists to prevent.
**Fix options (Ori's call):** (a) count redirect rows as instructions — publish a redirect-target
count from V_LOW_STOCK_ADS and add it to arm B; or (b) add `redirect_mode` itself as a third claim
arm (cleanest: a family being re-aimed IS low stock acting). Recommend (b) plus (a)'s counter for
legibility. NOT built — needs a decision, and it touches the ownership ladder.

> **✅ Task 4.11 DONE, v27.78 (2026-08-17).** Redirect mode is now a low-stock claim basis.
> V_LOW_STOCK_ADS CAMPAIGN rows publish the real redirect_mode (the rmode join already existed —
> no new join/CTE, and the slice was re-dry-run after deploy: still plans); V_PANEL_OWNERSHIP's
> ls CTE carries ls_redirect_mode, arm B ORs it, and it is published + now wired as a cube
> dimension (lsRedirectMode) so a panel can show which signal the claim rests on.
> COUNTERFACTUAL (the real proof — arm A masks this today): with arm A held silent, the OLD arm B
> keeps 9 of 14 claims; the NEW one keeps all 14. The 5 recovered are exactly the exposed set —
> BALL-SP/AUTO (White), BUNNY - COMPETITORS, BUNNY-SP/AUTO (Birthday), BUNNY-VIDEO/BROAD (Hunter),
> VIDEO- COMP/BALL — each carrying redirect_mode=TRUE with NULL suggested value and 0 proposal
> targets, i.e. no money signal at all. Live: ZERO owner changes (correct — both families grade
> CRITICAL today), 93 rows, SP idempotent, all consumers clean, config.yaml parses.
>
> **CORRECTION TO THE 4.11 PREMISE (verifier, worth keeping):** the gap this closes is THROTTLE,
> not WATCH. redirect_mode requires binding risk_state IN ('THROTTLE','CRITICAL') and the family
> grade inherits the binding grade whenever it is not OK — so a re-aiming family can never grade
> WATCH. Arm A fires only on CRITICAL; the newly-covered state is THROTTLE + redirect + both money
> signals silent. The arm is real, the original prose was wrong. Docs in the view/SP/config still
> say WATCH and should be corrected on the next touch.
>
> **OPEN, LATENT (named, not built):** (1) ls_redirect_mode is NOT family-propagated while arm A's
> risk_state IS (fam_prop window) — on a THROTTLE day, a campaign of a re-aiming family with no
> low-stock row (never delivered an impression) would still fall to rank 4 unowned; 0 instances
> today. (2) claim_reason is at 79 of 80 chars on the longest live redirect claim and the clause is
> appended with no truncation guard — a 3-digit cover, a >=$100 budget or a longer family name
> breaches it by construction. (3) config.yaml's FACT_PANEL_OWNERSHIP entry is stale (v27.62, 108
> rows, no ls_redirect_mode) and V_LOW_STOCK_ADS's entry never got its v27.73/v27.74 blocks.

### Task 4.12 ✅ DONE, v27.80 (2026-08-17) — per-product campaigns brake, only shared doorways re-aim

> Ori: "BALL-SP/AUTO (Mint) is auto per product. auto we have for each product - so no need to
> change only reduce ads by reducing the bid."

**The hole v27.73 opened.** The redirect gate suppressed brakes for EVERY campaign of a
redirect-mode family. Three cases, only the third wrong: shared doorway → suppress + redirect
(correct); dedicated to an IN-STOCK sibling → suppress, no redirect (correct — braking Pink saves
no Mint units and loses Pink sales); **dedicated to the DRY variation → suppressed with no usable
redirect**, i.e. BALL-SP/AUTO (Mint) neither braked nor re-aimed. Swapping Mint→Pink inside Mint's
own auto campaign proposes building a duplicate of BALL-SP/AUTO (Pink), which already exists.
**Built:** V_CAMPAIGN_PRODUCT_SCOPE (campaign → n_own_asins / sole_asin, 30 complete days,
own = parent_name IS NOT NULL) materialized as T_CAMPAIGN_PRODUCT_SCOPE and joined as a PHYSICAL
TABLE (never inlined — the ceiling view has no headroom), built at orchestrator Task 20.5d3 ahead
of every consumer. V_LOW_STOCK_ADS gains serves_only_binding; suppression now requires
redirect_mode AND NOT waste-park AND NOT serves_only_binding. V_LOW_STOCK_REDIRECT excludes
n_own_asins = 1 (UNKNOWN scope keeps the offer — never lose one to a missing row).
**Measured:** redirect 5 → 4 rows (Mint dropped, proven against the .bak body which still returns
it); Mint's two AUTOMATIC halves regain proposals ($0.41→$0.20 and $0.34→$0.20, $6.02/day);
in-stock siblings and all four shared doorways byte-identical; 141 view rows unchanged, the ONLY
delta account-wide is LolliBall TARGET proposals 3→5. Scope independently recounted: 74 campaigns,
0 mismatches, matches Ori's own figures (Mint 1, Pink 1, BUNNY-SP/BROAD 3, BALLS- BROAD 5,
BUNNY- BROAD 9, BUNNY - COMPETITORS 11). Planner: slice + ownership + 12 downstream consumers all
validate; SP_SNAPSHOT_PANEL_OWNERSHIP ran end-to-end, so tomorrow's 07:50 pass is safe.

### Task 4.13 — WITHDRAWN (2026-08-17): the "SB blind spot" is not a hole
Ori asked "cant you see the products assign to the ad in VIDEO- BALL?" — the check overturned my
framing twice over.
**(a) The data genuinely is not there for SB video.** V_SRC_AmazonAds_sb_ad_report DOES carry an
`advertised_asin` column, but Amazon populates it with the literal string 'Unknown' for video
creatives (74,103 impressions / $961 over 30d on VIDEO- BALL, one row, asin='Unknown'), and
creative_type / landing_page_type / ad_id / headline are all empty; AD_Advertised_ID is just
'campaign|ad_group'. FACT's 'Unknown' is faithfully inherited, not a mapping bug.
**(b) But the brake I called a $51.35/day hole should NOT fire.** The purchased-product report
answers the decision-relevant question — what the ad actually SELLS. Over 60 days the dry
variation's share is: VIDEO- BALL 18.0% (24 of 133 units), VIDEO- COMP/BALL 14.3% (4 of 28),
BUNNY-VIDEO/BROAD (Hunter) 10.5% (4 of 38). These are FAMILY-level ads: 82-90% of what they sell
is an IN-STOCK sibling. Braking them sacrifices the majority to slow a minority — precisely the
mistake redirect mode exists to prevent. VIDEO- BALL contributes ~0.4 Mint units/day against
Mint's ~8.7/day total, i.e. ~4% of the drain.
**Verdict: the current suppression is CORRECT for all three.** They cannot be re-aimed (video
creatives have no bulksheet swap path) and they should not be braked. No engine change needed.
**What IS worth doing (small, legibility only):** the suppression is currently a side effect of
family-level redirect mode with no stated reason, so the panel shows silence. Publish the WHY —
"family-level ad; 82% of its sales are in-stock siblings, braking costs more than it saves" — so
the reader sees a decision rather than an absence. Not urgent, no money at stake.

**Also open, smaller:** (1) V_LOW_STOCK_REDIRECT recomputes "dedicated" inline instead of reading
T_CAMPAIGN_PRODUCT_SCOPE — two hand-synced definitions of one predicate (they agree today, and the
inline filter is row-level `impressions > 0` vs the table's `HAVING SUM(...) > 0`). (2) Pre-existing
float flicker: risk_reason interpolates a spend/day figure that alternates $1.66/$1.67 across pulls
on one Bunny campaign — narrative only, every decision column byte-identical; wants a ROUND.
(3) binding_asin is NULL on CAMPAIGN rows, so a panel cannot reproduce serves_only_binding from
published columns — it must trust the boolean.
