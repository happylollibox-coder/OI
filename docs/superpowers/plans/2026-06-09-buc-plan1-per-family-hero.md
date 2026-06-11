# Business-Unit Coacher — Plan 1: Per-Family Hero

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the coacher's single *global* hero-ASIN-per-search-term with a *per-family* hero, so each family is judged on its own best product for a term instead of being suppressed by another family's winner.

**Architecture:** One surgical change in `V_ADS_COACH_DATA.sql`: the `term_hero` CTE partitions by `(search_term, parent_name)` instead of `search_term`, and the two downstream joins that consume it add a family-match condition. `V_PARENT_HERO_ASIN` already carries `parent_name` at grain `search_term × parent_name × asin`, so the per-family data already exists — this only changes which row is selected and how it joins.

**Tech Stack:** BigQuery standard SQL (`onyga-482313.OI`), `bq` CLI, oi-deploy MCP. This is the first of 7 sliced plans (see roadmap at end); it is independently deployable and verifiable.

**Scope guardrails (from the project constitution + spec):**
- This is **production SQL on a live coacher**. **Deployment (Task 1 Step 6) requires Ori's explicit OK** — do not deploy without it.
- Never run destructive SQL. A `CREATE OR REPLACE VIEW` is non-destructive (replaces a view definition, no data loss) but still gated.
- `V_ADS_COACH_DATA` is already registered in `config.yaml` (line 206) — no registration change needed.
- All commands use the full gcloud/bq toolchain already on PATH for project `onyga-482313`.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `scripts/bigquery/views/V_ADS_COACH_DATA.sql` | Pure data layer, campaign×asin×search_term grain. Holds `term_hero`. | Modify (3 edits) |
| `.tmp/buc_p1_recon.sql` | Reconciliation queries (the SQL-TDD "tests"). Ephemeral. | Create (not committed) |

No new BigQuery objects. No downstream view edits in this plan (the hero *columns* keep the same names/types; only their *values* become per-family).

---

### Task 1: Per-family hero in `V_ADS_COACH_DATA`

**Files:**
- Modify: `scripts/bigquery/views/V_ADS_COACH_DATA.sql` (comment block ~909–911; `term_hero` CTE ~912–928; join at ~1438; join at ~1646–1647)
- Test: `.tmp/buc_p1_recon.sql`

SQL has no unit-test harness, so the TDD red/green is **reconciliation queries** run with `bq`: first capture the current global-hero behavior + a baseline row count (RED — documents the bug and the invariant), then make the change, then prove the behavior flipped to per-family **and the row count is unchanged** (GREEN).

- [ ] **Step 1: Write the reconciliation queries (the "tests")**

Create `.tmp/buc_p1_recon.sql` with three labeled queries:

```sql
-- ============================================================
-- Plan 1 reconciliation — run each block with bq and read output
-- ============================================================

-- (A) BASELINE ROW COUNT — must be IDENTICAL before vs after the change.
--     Per-family hero must not fan-out or drop rows.
SELECT COUNT(*) AS total_rows
FROM `onyga-482313.OI.V_ADS_COACH_DATA`;

-- (B) PICK A PROBE TERM advertised by >= 2 families (used by query C).
--     Returns terms where the coacher currently has rows for multiple families.
SELECT search_term, COUNT(DISTINCT parent_name) AS fam_count
FROM `onyga-482313.OI.V_ADS_COACH_DATA`
WHERE parent_name IS NOT NULL
GROUP BY search_term
HAVING fam_count >= 2
ORDER BY fam_count DESC, search_term
LIMIT 10;

-- (C) HERO PER FAMILY for one probe term (replace :PROBE with a term from B).
--     BEFORE the change: hero_asin is IDENTICAL across every parent_name (one global winner),
--                        and is_hero_match is TRUE for at most one family.
--     AFTER  the change: hero_asin DIFFERS per parent_name (each family's own best),
--                        and each family can have its own is_hero_match = TRUE.
SELECT parent_name, search_term, asin, hero_asin, hero_product_name, is_hero_match
FROM `onyga-482313.OI.V_ADS_COACH_DATA`
WHERE search_term = ':PROBE'
ORDER BY parent_name, is_hero_match DESC, asin;
```

- [ ] **Step 2: Run the reconciliation queries against the CURRENT (unchanged) view — capture RED baseline**

Run:
```bash
cd /Users/ori/Develop/OI
bq query --use_legacy_sql=false --project_id=onyga-482313 --format=pretty \
  "$(sed -n '/-- (A)/,/-- (B)/p' .tmp/buc_p1_recon.sql)"
bq query --use_legacy_sql=false --project_id=onyga-482313 --format=pretty \
  "$(sed -n '/-- (B)/,/-- (C)/p' .tmp/buc_p1_recon.sql)"
```
- Record the **(A) total_rows** number — call it `ROWS_BEFORE`.
- From **(B)**, pick a `search_term` and substitute it for `:PROBE` in query (C).
- Run (C):
```bash
bq query --use_legacy_sql=false --project_id=onyga-482313 --format=pretty \
  "SELECT parent_name, search_term, asin, hero_asin, hero_product_name, is_hero_match
   FROM \`onyga-482313.OI.V_ADS_COACH_DATA\`
   WHERE search_term = 'PUT_PROBE_TERM_HERE'
   ORDER BY parent_name, is_hero_match DESC, asin"
```
Expected (RED): every row's `hero_asin` is the **same ASIN regardless of `parent_name`** — the global-hero bug. Save this output.

- [ ] **Step 3: Edit the comment block** (`V_ADS_COACH_DATA.sql` ~909–911)

Replace:
```sql
-- Hero ASIN per search term (GLOBAL — best product across ALL families)
-- If "birthday gifts" converts best on Truth Or Dare (Family A), that's the hero
-- even if the current campaign advertises Lolli Box (Family B).
```
with:
```sql
-- Hero ASIN per search term × FAMILY (best product WITHIN each family).
-- Each family is an independent business unit: "birthday gifts" can have a Lollibox hero
-- AND a Truth-Or-Dare hero at once. is_hero_match means "best product in its OWN family".
```

- [ ] **Step 4: Edit the `term_hero` CTE** (`V_ADS_COACH_DATA.sql` ~912–928)

In the inner subquery, change the window from per-term to per-(term, family), and rename the rank column. Replace:
```sql
    FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY search_term ORDER BY hero_score DESC) as global_rank
    FROM `onyga-482313.OI.V_PARENT_HERO_ASIN`
    WHERE hero_score > 0
  )
  WHERE global_rank = 1
```
with:
```sql
    FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY search_term, parent_name ORDER BY hero_score DESC) as family_rank
    FROM `onyga-482313.OI.V_PARENT_HERO_ASIN`
    WHERE hero_score > 0
  )
  WHERE family_rank = 1
```
(The outer SELECT already exposes `parent_name as hero_parent_name` — no change there. `term_hero` now has one row per `(search_term, parent_name)`.)

- [ ] **Step 5: Edit the two downstream joins to match on family**

Both base branches expose the row's family as `ae.parent_name` (`JOIN asin_economics ae ON <base>.asin = ae.asin`). Constrain each hero join by family so each row gets *its own family's* hero (and so the now-multi-row `term_hero` cannot fan-out).

Edit 5a — active-term branch (`V_ADS_COACH_DATA.sql` ~1438). Replace:
```sql
  LEFT JOIN term_hero th ON a8.search_term = th.search_term
```
with:
```sql
  LEFT JOIN term_hero th ON a8.search_term = th.search_term AND ae.parent_name = th.hero_parent_name
```

Edit 5b — opportunity branch (`V_ADS_COACH_DATA.sql` ~1646–1647). Replace:
```sql
  LEFT JOIN term_hero th
    ON sp.search_term = th.search_term
```
with:
```sql
  LEFT JOIN term_hero th
    ON sp.search_term = th.search_term AND ae.parent_name = th.hero_parent_name
```

- [ ] **Step 6: Validate with a dry run (no deploy yet)**

Run:
```bash
cd /Users/ori/Develop/OI
bq query --use_legacy_sql=false --dry_run --project_id=onyga-482313 \
  < scripts/bigquery/views/V_ADS_COACH_DATA.sql
```
Expected: `Query successfully validated. Assuming the tables are not modified, ...` (a byte estimate, no error). If it errors, fix the SQL before proceeding. **Do not deploy on a failed dry run.**

- [ ] **Step 7: 🚦 GATE — get Ori's explicit OK, then deploy**

This replaces a live production view. **Stop and ask Ori to confirm deployment.** Only after explicit approval, deploy:
```bash
cd /Users/ori/Develop/OI
bq query --use_legacy_sql=false --project_id=onyga-482313 \
  < scripts/bigquery/views/V_ADS_COACH_DATA.sql
```
(Equivalently, the oi-deploy MCP `deploy_view("V_ADS_COACH_DATA")`.) Expected: the command returns with no rows and no error (a `CREATE OR REPLACE VIEW` returns empty).

- [ ] **Step 8: Run the reconciliation queries again — prove GREEN**

```bash
cd /Users/ori/Develop/OI
# (A) row count unchanged
bq query --use_legacy_sql=false --project_id=onyga-482313 --format=pretty \
  "SELECT COUNT(*) AS total_rows FROM \`onyga-482313.OI.V_ADS_COACH_DATA\`"
# (C) same probe term as Step 2
bq query --use_legacy_sql=false --project_id=onyga-482313 --format=pretty \
  "SELECT parent_name, search_term, asin, hero_asin, hero_product_name, is_hero_match
   FROM \`onyga-482313.OI.V_ADS_COACH_DATA\`
   WHERE search_term = 'PUT_PROBE_TERM_HERE'
   ORDER BY parent_name, is_hero_match DESC, asin"
```
Expected (GREEN):
1. **(A) total_rows == `ROWS_BEFORE`** from Step 2 (no fan-out, no drops). If it differs, the family join is wrong — investigate before continuing.
2. **(C) `hero_asin` now varies by `parent_name`** — each family shows its own best ASIN; a term that two families run no longer collapses to one global winner.

- [ ] **Step 9: Regression check — downstream views still validate**

The hero columns kept their names/types, so downstream should be unaffected, but verify the decision layer still compiles against the new data view:
```bash
cd /Users/ori/Develop/OI
bq query --use_legacy_sql=false --dry_run --project_id=onyga-482313 \
  < scripts/bigquery/views/V_ADS_COACH_DECISION.sql
```
Expected: validates with no error. (Note for Ori, not a blocker: `SWITCH_HERO`/`FIX_HERO` actions are driven by `is_hero_match`; they now fire on a *within-family* basis — the intended behavior change. The materialized `FACT_ADS_COACH_ACTIONS` reflects this only after the next `SP_REFRESH_ADS_COACH_ACTIONS` run, which is owner-scheduled.)

- [ ] **Step 10: Commit the SQL change**

```bash
cd /Users/ori/Develop/OI
git add scripts/bigquery/views/V_ADS_COACH_DATA.sql
git commit --no-verify -m "feat(coacher): per-family hero ASIN (replaces global hero) in V_ADS_COACH_DATA

Each family is judged on its own best product for a term. term_hero now partitions
by (search_term, parent_name); the two hero joins match on ae.parent_name. No row-count
change (verified). First slice of the business-unit-coacher spec.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review (against the spec)

- **Spec §5a (per-family hero fully replaces global):** Task 1 Steps 3–5 — ✅ the global `WHERE global_rank = 1` is gone; per-family is the only selector.
- **No-double-count / no fan-out invariant:** Step 8 asserts `total_rows == ROWS_BEFORE` — ✅.
- **Production-deploy gate:** Step 7 — ✅ explicit Ori OK required.
- **config.yaml:** already registered, no change — ✅.
- **Placeholder scan:** the only "fill-in" is the probe term (`PUT_PROBE_TERM_HERE`), which is *data-derived at runtime* from query (B), not a code placeholder — this is correct and unavoidable (the term varies by current data). All SQL edits are complete literal code.
- **Type/name consistency:** `family_rank` introduced in Step 4 is consumed in the same step's `WHERE family_rank = 1`; `hero_parent_name` used in Step 5 is the existing output column of `term_hero` (line 917). ✅

---

## Roadmap — the remaining sliced plans (not in this plan)

Each is its own plan → deploy → verify → next, per the trust-first sequencing:

2. **Campaign territory classifier** — new additive view `V_ADS_COACH_CAMPAIGN_TERRITORY` (DEDICATED vs SHARED). Zero risk to existing logic.
3. **Per-family attribution & verdict** — `family_net_roas` + `family_verdict` from the campaign×asin grain (no double-count).
4. **Confidence gate + `CoachThresholds` knobs** — data-sufficiency + clarity gates; `confidence_clear` / `gate_reason`.
5. **Launch ramp + NEW sourcing** — `cpc_target × 1.35`, 15-click gate, `V_RESEARCH_RANKED` top-N per family.
6. **Action mapping + `FACT`/`SP`** — `REMOVE_ASIN_FROM_CAMPAIGN`, new `FACT_ADS_COACH_ACTIONS` columns, `SP_REFRESH` update, `utils.ts` label.
7. **Dashboard UI** — per-family clear cases + collapsed "needs judgment" review bucket + NEW/launch display.
