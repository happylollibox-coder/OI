# Weekly Run 5-Second / 5-Minute Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ori accepts any single action in 5 seconds (the reason legible at a glance, one click to queue) and understands the ENTIRE run — every change AND every unchanged keyword — in 5 minutes, on a page that is interactive in seconds instead of minutes.

**Architecture:** The heavy lifting is already done by the data layer built this week — `FACT_ENGINE_PROPOSALS` (every instruction, daily) + `T_ENGINE_PREFLIGHT` (verdicts) are SMALL tables, so the new "front page" (summary strip + unified Today's-decisions feed) reads them in ~2 seconds while the 17 existing criteria sections become lazy drill-downs that fetch only when expanded. The 5-second accept comes from a fixed reason GRAMMAR authored in the views (never truncated in React) plus the one-click queue idiom the panels already share. The 5-minute read comes from one feed + one unchanged-inventory strip instead of 17 tables.

**Tech Stack:** BigQuery views (reason contract + summary), Cube.js passthroughs, React 19 + TS strict + Tailwind 4 (render-only), the existing DO-queue/preflight machinery.

---

## The two contracts (what "done" means)

**5-SECOND ACCEPT.** Every actionable row, anywhere on the page, has the same anatomy in the same
order, so the eye learns ONE scan pattern:

```
[item]  [now → proposed]  [why_short: TRIGGER — EVIDENCE ⇒ MOVE]  [⬚ queue toggle]
  e.g.  substitutes  $0.41 → $0.39   23c 0.00× yesterday, 90d 0.33 — brake 15%   ⬚
```
- `why_short` is ONE clause, ≤ ~12 words, AUTHORED IN THE VIEW (the v27.62 low-stock rule:
  written short in SQL, never truncated in React). The full paragraph is the cell's tooltip.
- Guards that PASSED are silent (quiet = safe). Only REVIEW/flags render, as one amber chip
  with the reason. "Nothing flagged" is communicated by absence, not by ✓-noise.
- One click queues. The row shows ✓ when queued. Apply-all counts derive from the same
  memoised list they queue (the session's one-list discipline).

**5-MINUTE WHOLE-RUN READ.** From a cold page open, within 5 minutes Ori can narrate: how many
changes, in which direction, worth how much, what was held and why, and what the rest of the
account is doing (unchanged, and why unchanged). Structure:

```
┌─ RUN SUMMARY STRIP (renders < 3s — small-table query) ─────────────────────┐
│ 97 changes proposed · 38 bid cuts · 8 bid raises · 26 budgets −$102/d ·    │
│ 25 revivals  ·  44 excluded (ownership) · 8 REVIEW (winner cuts)           │
│ ($/day shown for budget moves only — bid-level $ needs spend estimates the │
│  snapshot does not carry; adding fake precision would break trust)         │
│ UNCHANGED: 412 keywords — 118 winners holding · 74 settling · 61 parked ·  │
│ 106 confirmed-park · 25 trial · 28 seasonal-hold                           │
└────────────────────────────────────────────────────────────────────────────┘
┌─ TODAY'S DECISIONS (one unified feed, grouped by engine, < 3s) ────────────┐
│ ▾ LOW_STOCK (46 · −$102/d)  [queue all GO]                                 │
│    …rows in the 5-second anatomy…                                          │
│ ▾ OOB (47) · LAUNCH (35) · LIFT (43) · REVERDICT (25)                      │
│ ▸ 44 excluded by ownership — collapsed, expandable, never queueable        │
└────────────────────────────────────────────────────────────────────────────┘
▸ the 17 existing criteria sections — unchanged UI, but LAZY: fetch on expand
```

The feed is the read; the sections become the microscope. Nothing is removed.

---

## Ground rules

1. All decision logic and ALL strings stay in BigQuery (`feedback_all_logic_in_backend`;
   short-forms authored in views — the LowStockPhase v27.62 precedent).
2. The feed's authority is `T_ENGINE_PREFLIGHT` — verdicts are the SP's; React renders them.
   EXCLUDE rows are never queueable anywhere. REVIEW queues only via per-item confirm (the
   DoPage gate then re-checks at export — two doors, same rule).
3. Non-clobber: a key queued by another surface renders "· other panel" (the RevivalsPhase
   `ourItem`/`claimedElsewhere` idiom, reused verbatim).
4. Deploy pattern, backups, pull-twice, `config.yaml` registration — as everywhere this week.
5. No commits, no dashboard deploys (`deploy_all.sh` ships the working tree; ~171 dirty files).
6. Ori's two numbers are ACCEPTANCE TESTS, not vibes — Task 8 measures both.

---

> **PROGRESS 2026-08-16:** Task 0 ✅ (architecture/WEEKLY_RUN_UX.md). Task 1 ✅ (ad_group_id +
> reason_short columns through snapshot + preflight + cube; 147/149 BID rows keyed — the 2
> keyless are the known LAUNCH auto-clause gap, rendered unqueueable). Task 2 ✅ (V_RUN_SUMMARY,
> ~4s, UNCHANGED upgraded to FACT_KEYWORD_STATE which superseded the plan's interim guard CASE;
> live: 113 changes / 57 held / 772 unchanged in 7 classes). Task 7 backend ✅ (V_RUN_UNCHANGED +
> RunUnchanged cube; strip drill rides the Task-5 agent). Tasks 4+5+7-drill and Task 6 running
> as parallel agents. Task 3 (why_short authoring in OOB/LIFT) DEFERRED next — the feed falls
> back to full reasons, per the plan's own dependency note. Task 8 after the agents land.
>
> **BUILD COMPLETE 2026-08-16 (evening):** Tasks 4+5+6+7 ✅, all browser-verified live (full
> record: progress.md §Phase 6). Page-open queries 65→12; strip + feed render the whole run with
> numbers matching T_ENGINE_PREFLIGHT exactly; queue/unqueue/queue-all/non-clobber/EXCLUDE/drills
> all exercised in the running app. One backend bug found by the build and fixed same hour
> (LOW_STOCK current_budget NULL → 7 cuts mislabeled as raises; truth: 17 cuts −$113.28/d).
> OPEN: Task 3 (why_short in the two big engines) · Task 8 protocol half (Ori's first Monday:
> 5 rows ≤ 25s, 5-minute narration) · prod cube deploy rides the next dashboard ship.

## Task 0: The UX contract SOP

**Files:**
- Create: `architecture/WEEKLY_RUN_UX.md`

- [ ] **Step 1:** Write the SOP containing: the two contracts verbatim (5s anatomy, 5min
  structure), the reason-grammar spec (`TRIGGER — EVIDENCE ⇒ MOVE`, ≤12 words, authored in SQL),
  the quiet-guards rule, the lazy-section rule (a section fetches ONLY on first expand), and the
  feed-vs-sections division of labor (feed = read+approve; sections = diagnose). State the
  dependency: the "unchanged" strip upgrades to `V_KEYWORD_STATE` when engine-finalization Task
  2.1 lands; v1 derives states from the snapshot tables (mapping table in Task 2 below).

## Task 1: The snapshot learns `ad_group_id` (feed rows must be uploadable)

The feed queues DO-items directly, and a bid item without `ad_group_id` produces a bulksheet row
Amazon rejects (the Revivals lesson). Verified 2026-08-16: `FACT_ENGINE_PROPOSALS` lacks the
column; every source view now carries it.

**Files:**
- Modify: `scripts/bigquery/tables/FACT_ENGINE_PROPOSALS.sql` (DDL comment + column)
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql` (all 7 INSERTs)
- Modify: `scripts/bigquery/procedures/SP_ENGINE_PREFLIGHT.sql` (carry through to T_)
- Modify: `config.yaml` (both descriptions)

- [ ] **Step 1: Failing assertion**
```bash
bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --max_rows=3 --format=csv \
"SELECT COUNTIF(ad_group_id IS NULL) FROM \`onyga-482313.OI.T_ENGINE_PREFLIGHT\` WHERE lever='BID'"
```
Expected: `Unrecognized name: ad_group_id`.
- [ ] **Step 2:** `ALTER TABLE \`onyga-482313.OI.FACT_ENGINE_PROPOSALS\` ADD COLUMN IF NOT EXISTS ad_group_id STRING;`
  and mirror in the DDL file.
- [ ] **Step 3:** In `SP_SNAPSHOT_ENGINE_PROPOSALS`, add `ad_group_id` to the column list and each
  SELECT: LIFT `CAST(ad_group_id AS STRING)`; OOB `CAST(ad_group_id AS STRING)`; LOW_STOCK
  `CAST(ad_group_id AS STRING)` (TARGET arm; NULL rides the CAMPAIGN arm naturally); LAUNCH
  `CAST(ad_group_id AS STRING)`; REVERDICT `CAST(ad_group_id AS STRING)`; the two BUDGET arms
  insert `CAST(NULL AS STRING)`.
- [ ] **Step 4:** In `SP_ENGINE_PREFLIGHT`, add `ad_group_id` to the `p` CTE select list and the
  final T_ SELECT (`r.ad_group_id`).
- [ ] **Step 5:** Deploy both SPs; `CALL SP_SNAPSHOT_ENGINE_PROPOSALS(); CALL SP_ENGINE_PREFLIGHT();`
  re-run Step 1: expected 0 (all BID rows carry the ad group; verified 0-missing in every source
  this week).
- [ ] **Step 6:** Update the EnginePreflight cube with the passthrough
  (`adGroupId: { sql: 'ad_group_id', type: 'string' }`) — file `cube/schema/EnginePreflight.js`.

## Task 2: `V_RUN_SUMMARY` — the front page as one small-table query

**Files:**
- Create: `scripts/bigquery/views/V_RUN_SUMMARY.sql`
- Create: `cube/schema/RunSummary.js`
- Modify: `config.yaml`

One row per summary cell: `section ('CHANGES'|'HELD'|'UNCHANGED'), label, n, dollars_per_day,
detail`. Reads ONLY small tables (T_ENGINE_PREFLIGHT, FACT_KEYWORD_GUARD, FACT_PARK_REVERDICT,
FACT_PANEL_OWNERSHIP) — target < 3s.

- [ ] **Step 1: The view (complete):**
```sql
CREATE OR REPLACE VIEW `onyga-482313.OI.V_RUN_SUMMARY` AS
WITH pf AS (SELECT * FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`),
changes AS (
  SELECT 'CHANGES' AS section,
    CASE WHEN lever='BUDGET' AND suggested_budget < current_budget THEN 'budget cuts'
         WHEN lever='BUDGET' THEN 'budget raises'
         WHEN grain='REVIVE' THEN 'revivals'
         WHEN suggested_bid < current_bid THEN 'bid cuts'
         ELSE 'bid raises' END AS label,
    COUNT(*) AS n,
    ROUND(SUM(CASE WHEN lever='BUDGET' THEN suggested_budget - current_budget ELSE 0 END), 2) AS dollars_per_day,
    CAST(NULL AS STRING) AS detail
  FROM pf WHERE verdict = 'GO' GROUP BY 2
),
held AS (
  SELECT 'HELD', CONCAT(LOWER(verdict), ' — ', IFNULL(SPLIT(verdict_reason, ' — ')[SAFE_OFFSET(0)], 'other')),
         COUNT(*), CAST(NULL AS FLOAT64), ANY_VALUE(verdict_reason)
  FROM pf WHERE verdict != 'GO' GROUP BY 2
),
-- v1 UNCHANGED taxonomy from the snapshot tables (upgrades to V_KEYWORD_STATE at Task 2.1 of the
-- engine plan). A keyword with NO instruction today is "unchanged"; its class comes from guard +
-- reverdict. Anti-join by equality only (fact_oi_bigquery_antisemi_join_needs_equality).
instructed AS (SELECT DISTINCT campaign_id, COALESCE(keyword_id,'') kid FROM pf),
unchanged AS (
  SELECT 'UNCHANGED',
    CASE WHEN rv.reverdict = 'CONFIRM_PARK' THEN 'confirmed park'
         WHEN rv.reverdict = 'PENDING_SETTLE' THEN 'park settling'
         WHEN g.settled_roas90 >= 1.0 AND g.settled_clk90 >= 10 THEN 'winners holding'
         WHEN NOT COALESCE(g.settle_ok, TRUE) THEN 'clicks settling'
         WHEN COALESCE(g.settled_clk90, 0) < 10 THEN 'trial — thin record'
         ELSE 'holding on record' END,
    COUNT(*), CAST(NULL AS FLOAT64), CAST(NULL AS STRING)
  FROM `onyga-482313.OI.FACT_KEYWORD_GUARD` g
  LEFT JOIN (SELECT CAST(campaign_id AS STRING) c, CAST(keyword_id AS STRING) k, reverdict
             FROM `onyga-482313.OI.FACT_PARK_REVERDICT`) rv
    ON rv.c = CAST(g.campaign_id AS STRING) AND rv.k = CAST(g.keyword_id AS STRING)
  LEFT JOIN instructed i
    ON i.campaign_id = CAST(g.campaign_id AS STRING) AND i.kid = CAST(g.keyword_id AS STRING)
  WHERE i.campaign_id IS NULL
  GROUP BY 2
)
SELECT * FROM changes UNION ALL SELECT * FROM held UNION ALL SELECT * FROM unchanged;
```
- [ ] **Step 2:** Deploy; assert: `SELECT section, COUNT(*) FROM V_RUN_SUMMARY GROUP BY 1` returns
  all three sections with n > 0; the CHANGES total equals T_ENGINE_PREFLIGHT's GO count; time the
  query (< 3s expected — small tables only).
- [ ] **Step 3:** `cube/schema/RunSummary.js` passthrough (section, label, n, dollarsPerDay,
  detail; refreshKey 15 min), registered in config.yaml.

## Task 3: `why_short` in the two engines that lack it

Low stock (`action_reason_short`), launch (band strings), and reverdict (short reasons) already
comply. `V_OOB_KEYWORD.bid_reason` and `V_KEYWORD_LIFT.reason` are paragraphs.

**Files:**
- Modify: `scripts/bigquery/views/V_OOB_KEYWORD.sql` (add `bid_reason_short`)
- Modify: `scripts/bigquery/views/V_KEYWORD_LIFT.sql` (add `reason_short`)
- Modify: `scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_PROPOSALS.sql` (snapshot the short form
  into a new `reason_short` column — ALTER FACT_ENGINE_PROPOSALS + carry through preflight, same
  motion as Task 1)
- Modify: `cube/schema/OobKeyword.js`, `cube/schema/KeywordLift.js`, `cube/schema/EnginePreflight.js`

- [ ] **Step 1:** In each view's OUTPUT layer add the short column in the grammar
  `TRIGGER — EVIDENCE ⇒ MOVE`, built from the SAME predicates as the action ladder (no-drift
  rule). Complete example for the OOB dark-brake arm — every arm gets its own clause:
```sql
    WHEN <the DARK_BRAKE predicate, verbatim from the action CASE>
      THEN CONCAT(CAST(b.clk1 AS STRING), 'c ', FORMAT('%.2f', COALESCE(b.roas1,0)), 'x yesterday, 90d ',
                  FORMAT('%.2f', COALESCE(b.roas90,0)), ' — brake ',
                  CAST(CAST(ROUND(100*(1 - <the shared step expression>)) AS INT64) AS STRING), '%')
```
  Rows whose full reason is already ≤ ~60 chars may reuse it verbatim. NULL is forbidden on
  actionable rows — assert it.
- [ ] **Step 2:** Deploy both views; assert
  `COUNTIF(bid_action NOT IN ('HOLD') AND suggested_bid IS NOT NULL AND (bid_reason_short IS NULL OR LENGTH(bid_reason_short) > 80)) = 0`
  (and the LIFT equivalent); pull-twice both.
- [ ] **Step 3:** ALTER + snapshot + preflight carry-through + cube passthroughs; CALL both SPs;
  assert T_ENGINE_PREFLIGHT has `reason_short` non-null on > 90% of GO rows.

## Task 4: `TodayDecisions.tsx` — the unified feed

**Files:**
- Create: `dashboard-react/src/pages/TodayDecisions.tsx`
- Modify: `dashboard-react/src/pages/WeeklyRunPage.tsx` (mount it directly under the summary strip)

- [ ] **Step 1:** Component fetches `EnginePreflight` (dimensions: rowId, engine, ownerEngine,
  lever, grain, verdict, verdictReason, campaignId, campaignName, keywordId, adGroupId,
  targetText, matchType, channel, action, currentBid, suggestedBid, currentBudget,
  suggestedBudget, reason, reasonShort, snapshotDate) — non-fatal on error (section renders
  "preflight unavailable", never blanks the page).
- [ ] **Step 2:** Render, grouped by engine (LOW_STOCK, LAUNCH, OOB, REVERDICT, LIFT — the
  ownership order), each group header showing `n` (+ `Σ$/day` on BUDGET rows only — never invent
  bid-level dollar impact) + a `queue all GO` button:
  - GO rows: the 5-second anatomy. `why` cell shows `reasonShort` (fallback: `reason` when short
    is NULL — pre-Task-3 tolerance), full `reason` as title tooltip.
  - REVIEW rows: amber chip with `verdictReason`; queue only via `window.confirm` (the DoPage
    text pattern).
  - EXCLUDE rows: one collapsed line per group — "N excluded — <ownerEngine> owns these keys" —
    expandable, rows rendered faint, NO queue affordance anywhere on them.
- [ ] **Step 3:** Queue wiring: the RevivalsPhase idiom verbatim (`ourItem`/`claimedElsewhere`
  keyed on keyword_id for BID/REVIVE levers, campaign_id for BUDGET; item shape from
  OobBudgetPhase:231/211 with `campaign_type` from `channel`; direction INCREASE/REDUCE by
  comparing suggested to current — the one permitted glue). One memoised `applicable` list per
  group feeds count AND click; unapply symmetric; never sweep other panels' items.
- [ ] **Step 4:** Typecheck (`grep TodayDecisions` → zero lines) + `npx vite build`.
- [ ] **Step 5:** Browser-verify with the running dev servers: group counts match
  `SELECT engine, COUNT(*) FROM T_ENGINE_PREFLIGHT WHERE verdict='GO' GROUP BY 1`; queue one row,
  confirm it lands in the DO queue with ad_group_id; unqueue; REVIEW confirm fires; EXCLUDE rows
  unclickable.

## Task 5: The summary strip

**Files:**
- Create: `dashboard-react/src/components/RunSummaryStrip.tsx`
- Modify: `dashboard-react/src/pages/WeeklyRunPage.tsx` (mount at top, above TodayDecisions)

- [ ] **Step 1:** Fetch `RunSummary`; render three lines (CHANGES with per-label n + $, HELD
  amber with per-class n, UNCHANGED as `n label · n label · …` in muted text). Numbers `font-mono`,
  labels sans (house convention). Non-fatal fetch. No arithmetic beyond Σ of the rows it renders.
- [ ] **Step 2:** Clicking a CHANGES label scrolls to that engine group in TodayDecisions;
  clicking an UNCHANGED label expands a compact drill list (Task 7). Typecheck + build.

## Task 6: Lazy sections — the page becomes interactive in seconds

Verified 2026-08-16: every phase component fetches in `useEffect` on MOUNT, so page-open fires
~17 ceiling-view queries at once (measured cold loads 40–120s each; the "why is it not loading"
incident). The feed replaces the first read, so sections may fetch on first EXPAND.

**Files:**
- Modify: `dashboard-react/src/pages/KeywordLiftPhase.tsx`, `OobBudgetPhase.tsx`,
  `RevivalsPhase.tsx`, `LaunchExemptionPhase.tsx`, `LowStockPhase.tsx`, `NewCampaignCards.tsx`,
  `BrandDefensePhase.tsx` (+ any other Weekly Run phase found by
  `grep -l "cubeLoad" dashboard-react/src/pages/*Phase*.tsx`)

- [ ] **Step 1:** In each: gate the fetch effect on the section's `open` state with a
  fetched-once ref —
```tsx
  const fetchedRef = useRef(false);
  useEffect(() => {
    if (!open || fetchedRef.current) return;
    fetchedRef.current = true;
    /* existing fetch body, unchanged */
  }, [open]);
```
  The collapsed header keeps its count-free goal text plus `· expand to load`. A section Ori
  leaves collapsed costs zero queries.
- [ ] **Step 2:** Exception, deliberate: the settled-scorecard section ("How did last week's
  changes do?") stays eager — it is part of the 5-minute read.
- [ ] **Step 3:** Typecheck all touched files (zero new lines each), vite build, then browser:
  page-open network shows ONLY RunSummary + EnginePreflight + scorecard queries; expanding Low
  stock fires its queries on that click and renders as before.

## Task 7: The "unchanged, and why" drill

**Files:**
- Create: `scripts/bigquery/views/V_RUN_UNCHANGED.sql` (row-grain sibling of V_RUN_SUMMARY's
  UNCHANGED arm: campaign_name, target_text, class, settled_clk90, settled_roas90, one
  view-authored `why_short` per class — e.g. `winner 1.41× over 502 settled clicks — holding`)
- Create: `cube/schema/RunUnchanged.js`
- Modify: `dashboard-react/src/components/RunSummaryStrip.tsx` (clicking an UNCHANGED class opens
  a compact 3-column list: item · record · why_short; lazy-fetched on first open, filtered by class)
- Modify: `config.yaml`

- [ ] **Step 1:** View = the Task-2 `unchanged` CTE re-emitted at row grain with the class CASE
  shared verbatim (copy, with a no-drift comment pointing at V_RUN_SUMMARY). Deploy; assert its
  per-class counts equal V_RUN_SUMMARY's UNCHANGED n's exactly (same-query-different-grain test).
- [ ] **Step 2:** Cube + strip drill; typecheck + build + browser check one class.

## Task 8: The acceptance tests — measure Ori's two numbers

- [ ] **Step 1 (5 minutes, mechanical half):** From a hard reload of Weekly Run: summary strip +
  TodayDecisions rendered with data in ≤ 15s (browser-measured via the network panel); every GO
  row queueable; total rows in the feed ≈ preflight GO+REVIEW count. Record numbers in
  `progress.md`.
- [ ] **Step 2 (5 seconds, protocol half):** With Ori, first Monday run after ship: he picks 5
  arbitrary GO rows; for each, reads why_short, decides, clicks. Target ≤ 25s for the 5. Then the
  5-minute narration test: scroll summary + feed only, narrate the run. Failures become concrete
  follow-ups filed against the reason grammar (which clause was illegible?), never against his
  reading speed.
- [ ] **Step 3:** Append results to `progress.md` and mark this plan done or file the follow-ups.

---

## Dependency order

```
0 → 1 → 2 → {4, 5} → 6 → 8        3 (why_short) can run parallel after 1; 4 tolerates its absence
                     7 after 2      (reasonShort falls back to reason until Task 3 lands)
```

**Interlocks with the engine-finalization plan:** the UNCHANGED taxonomy (Tasks 2/7) upgrades to
`V_KEYWORD_STATE` + next-appointment dates when that plan's Task 2.1 lands — the class CASE is
deliberately isolated in two marked places. `V_ENGINE_HEALTH` (its Task 3.3) will join the summary
strip as a fourth line when built. Nothing here blocks on it.

**Explicitly out of scope (YAGNI until the acceptance test says otherwise):** a card-walker review
mode, keyboard shortcuts, per-row sparklines, diff-vs-yesterday on the feed (the daily brief
already answers it at the day grain), and any change to the 17 sections' internals beyond lazy
fetching.
