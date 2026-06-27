# Strategy Gaps: Detect → Borrow → Probe (Coacher C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect coacher cells with no trusted per-product plan, fill the fillable ones by borrowing a similar CONCLUSIVE cell (capped), and probe the rest (starved keywords) with a bounded per-match-type exploratory bid.

**Architecture:** Three components in dependency order. (A) `V_STRATEGY_GAPS` — a new view aggregating `V_ADS_COACH_DATA` to the `parent×season×match×intent` cell grain to flag non-steering cells. (B) `tools/strategy_profile/borrow.py` — a post-derivation step that fills gaps from a CONCLUSIVE donor (`source=BORROWED`, 80% haircut), plus a one-line `profile_steers` extension so borrowed cells steer. (C) a `target_action='PROBE'` branch in `V_ADS_COACH` driven by new probe signals, with `DE_PROBE_LOG` closing the 15-click/14-day loop.

**Tech Stack:** BigQuery Standard SQL (`bq` CLI, project `onyga-482313`); Python 3.12 in `.venv` at repo root (`pandas`, `pytest`); the coacher views `V_ADS_COACH_DATA` → `V_ADS_COACH`; the profile table `DE_PRODUCT_STRATEGY_PROFILE` (cols incl. `source`, `confidence`, `borrowed_from`, `cpc_target/min/max`, `tos_target_pct`, `intent_class`).

**Context every task needs:**
- Run Python from repo root as a module: `cd /Users/ori/Develop/OI && .venv/bin/python -m tools.strategy_profile.run` (and `.venv/bin/pytest tools/strategy_profile/tests -q`).
- Deploy a view: `bq query --use_legacy_sql=false < /Users/ori/Develop/OI/scripts/bigquery/views/<FILE>.sql` (pipe via **stdin** — a positional arg makes `bq` parse the leading `--` comment as a flag). A `CREATE OR REPLACE` prints no rows on success.
- `git` from this dir can lose cwd; use `git -C /Users/ori/Develop/OI ...`. Commit `--no-verify` (pre-existing TS lint debt is unrelated). End commit messages with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Heavy aggregate queries over `V_ADS_COACH` can hit "Resources exceeded" if they reference the view twice (e.g. a nested `(SELECT COUNT(*))`). Use a single scan with `COUNT(*)` + `COUNTIF(...)` instead.
- The coacher view feeds materialized `T_ADS_COACH_*` tables via `SP_REFRESH_ADS_COACH_ACTIONS`/`SP_REFRESH_CUBE_TABLES`; **validate against the views directly** (immediate) — do not run those SPs as part of these tasks.
- Profile cell grain = `parent_name × season(PEAK/OFF) × match_type(BROAD/EXACT/PHRASE/PRODUCT/AUTO/CATEGORY/OTHER) × intent_class(BRAND/PRODUCT/GENERIC)`. "Steers" = `source='MANUAL' OR confidence='CONCLUSIVE'` (to be extended to include `'BORROWED'` in Task B3).
- New constants live in `tools/strategy_profile/config.py`: add `BORROW_HAIRCUT = 0.80`, `PROBE_CPC_PCTILE = 50`, `PROBE_DECISION_CLICKS = 15`, `PROBE_DECISION_DAYS = 14`, `PROBE_DEMAND_FLOOR = 100` (SQP search-volume floor, tune later).

---

## Component A — Gap-detector

### Task A1: Expose `season` and `match_type` as output columns of `V_ADS_COACH_DATA`

**Files:** Modify `scripts/bigquery/views/V_ADS_COACH_DATA.sql`

`V_ADS_COACH_DATA` already computes a per-keyword season and match_type to join the profile (`psp`) on `parent×season×match×intent` (around the `profile_steers` line, ~1577), but does not output them. Expose them so the gaps view can aggregate by cell.

- [ ] **Step 1: Find the season + match_type expressions used in the `psp` join**

Run: `grep -n "psp" scripts/bigquery/views/V_ADS_COACH_DATA.sql`
Read the `LEFT JOIN ... psp ON ...` clause. Note the exact expressions/aliases it equates to `psp.season` and `psp.match_type` (e.g. a `family_season` column and a normalized match-type expression). These are the values to surface.

- [ ] **Step 2: Add two output columns next to `intent_class` (the main SELECT, ~line 1579)**

Add, immediately after the `... as intent_class,` output line:
```sql
    <season_expr>     as season,
    <match_type_expr> as match_type,
```
where `<season_expr>`/`<match_type_expr>` are the exact expressions identified in Step 1 (the same ones the `psp` join uses, so they can never drift from the profile grain). In the UNION's OPPORTUNITY branch (the `CAST(NULL AS ...)` block ~line 1862), add the matching:
```sql
    CAST(NULL AS STRING) as season,
    CAST(NULL AS STRING) as match_type,
```

- [ ] **Step 3: Deploy + verify the columns exist and match the profile grain**

Run: `bq query --use_legacy_sql=false < /Users/ori/Develop/OI/scripts/bigquery/views/V_ADS_COACH_DATA.sql`
Then:
```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT season, match_type, COUNT(*) n
FROM `onyga-482313.OI.V_ADS_COACH_DATA`
WHERE keyword_id IS NOT NULL
GROUP BY 1,2 ORDER BY n DESC LIMIT 12'
```
Expected: non-null `season ∈ {PEAK,OFF}` and `match_type ∈ {BROAD,EXACT,PHRASE,PRODUCT,AUTO,CATEGORY,OTHER}`; no unexpected values.

- [ ] **Step 4: Confirm row parity unchanged**

Run:
```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT COUNT(*) coach_data_rows FROM `onyga-482313.OI.V_ADS_COACH_DATA`'
```
Expected: equals the current count (e.g. 41474; adding output columns cannot change cardinality).

- [ ] **Step 5: Commit**

```bash
git -C /Users/ori/Develop/OI add scripts/bigquery/views/V_ADS_COACH_DATA.sql
git -C /Users/ori/Develop/OI commit --no-verify -m "feat(coacher): expose season+match_type on V_ADS_COACH_DATA (C gap-detector prep)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task A2: Create `V_STRATEGY_GAPS`

**Files:** Create `scripts/bigquery/views/V_STRATEGY_GAPS.sql`; Modify `config.yaml`

- [ ] **Step 1: Write the view**

Create `scripts/bigquery/views/V_STRATEGY_GAPS.sql`. It aggregates `V_ADS_COACH_DATA` (keyword grain) to the cell grain, left-joins the profile to read each cell's steer state, and computes the resolution. `no_traffic_rate`, `sqp_amazon_search_volume_8w`, `ads_spend_8w`, `target_impressions_8w` are already per-keyword on `V_ADS_COACH_DATA` (from A); `season`/`match_type` come from Task A1.

```sql
-- V_STRATEGY_GAPS — cells active in ads but not steering (missing profile or WEAK).
-- Drives borrow (Component B) and probe (Component C). Coacher sub-project C.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_STRATEGY_GAPS` AS
WITH cell AS (             -- aggregate live keyword rows to the profile cell grain
  SELECT
    parent_name, season, match_type, intent_class,
    COUNT(DISTINCT keyword_id)                                   AS keyword_count,
    COUNTIF(COALESCE(no_traffic_rate, 0) >= 0.8)                 AS starved_keyword_count,
    ROUND(SUM(COALESCE(ads_spend_8w, 0)), 2)                     AS spend_at_risk,
    ROUND(SUM(COALESCE(sqp_amazon_search_volume_8w, 0)), 0)      AS demand_signal
  FROM `onyga-482313.OI.V_ADS_COACH_DATA`
  WHERE keyword_id IS NOT NULL
    AND season IS NOT NULL AND match_type IS NOT NULL AND intent_class IS NOT NULL
  GROUP BY 1,2,3,4
),
prof AS (
  SELECT parent_name, season, match_type, intent_class, source, confidence
  FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`
),
gaps AS (
  SELECT
    c.parent_name, c.season, c.match_type, c.intent_class,
    CASE WHEN p.parent_name IS NULL THEN 'MISSING' ELSE 'WEAK' END AS gap_type,
    c.spend_at_risk, c.keyword_count, c.starved_keyword_count, c.demand_signal,
    -- a donor exists if any CONCLUSIVE cell shares the intent AND (same parent OR same match) —
    -- the reachable set of the borrow ladder (steps 1-4)
    EXISTS (SELECT 1 FROM prof d WHERE d.confidence='CONCLUSIVE'
              AND d.intent_class = c.intent_class
              AND (d.parent_name = c.parent_name OR d.match_type = c.match_type)) AS has_borrow_donor,
    (c.starved_keyword_count > 0 AND c.demand_signal >= 100) AS is_probeable_raw
  FROM cell c
  LEFT JOIN prof p USING (parent_name, season, match_type, intent_class)
  -- only surface cells that do NOT steer: missing, or present-but-WEAK-and-not-manual/borrowed
  WHERE p.parent_name IS NULL
     OR (COALESCE(p.source,'DERIVED') NOT IN ('MANUAL','BORROWED') AND p.confidence = 'WEAK')
)
SELECT *,
  CASE WHEN has_borrow_donor THEN 'BORROW'
       WHEN is_probeable_raw THEN 'PROBE'
       ELSE 'NONE' END AS suggested_resolution
FROM gaps
```

- [ ] **Step 2: Deploy**

Run: `bq query --use_legacy_sql=false < /Users/ori/Develop/OI/scripts/bigquery/views/V_STRATEGY_GAPS.sql`
Expected: succeeds, no rows.

- [ ] **Step 3: Validate — only non-steering cells, resolution sane**

```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT gap_type, suggested_resolution, COUNT(*) cells,
       ROUND(SUM(spend_at_risk),0) spend
FROM `onyga-482313.OI.V_STRATEGY_GAPS`
GROUP BY 1,2 ORDER BY 1,2'
```
Expected: rows only for `gap_type ∈ {MISSING, WEAK}` (never `STEERS`); `suggested_resolution ∈ {BORROW,PROBE,NONE}`; the WEAK count is ≤ 26 (today's WEAK total — some WEAK cells may have since gone inactive). Cross-check the WEAK cell list against the 26 known WEAK cells.

- [ ] **Step 4: Register in config.yaml + commit**

Add `V_STRATEGY_GAPS` to `config.yaml` under the views section (match the surrounding format). Then:
```bash
git -C /Users/ori/Develop/OI add scripts/bigquery/views/V_STRATEGY_GAPS.sql config.yaml
git -C /Users/ori/Develop/OI commit --no-verify -m "feat(coacher): V_STRATEGY_GAPS — detect non-steering cells (C)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Component B — Borrow-similar

### Task B1: `borrow.py` — donor ladder + cost-adjust + haircut (unit-tested, pure)

**Files:** Create `tools/strategy_profile/borrow.py`; Create `tools/strategy_profile/tests/test_borrow.py`; Modify `tools/strategy_profile/config.py`

- [ ] **Step 1: Add constants to `config.py`**

Append:
```python
BORROW_HAIRCUT = 0.80          # borrowed cpc capped at 80% of donor's cpc_target
PROBE_CPC_PCTILE = 50          # probe launch CPC = p50 of parent×match real CPC
PROBE_DECISION_CLICKS = 15     # probe graduates at this many clicks
PROBE_DECISION_DAYS = 14       # probe exhausts after this many days
PROBE_DEMAND_FLOOR = 100       # min SQP search volume to justify a probe
GLOBAL_BID_CAP = 2.00          # hard ceiling, mirrors th_bid_cap default
MATCH_DISTANCE = {("EXACT","PHRASE"):1, ("PHRASE","BROAD"):1, ("EXACT","BROAD"):2}
```

- [ ] **Step 2: Write the failing test**

Create `tools/strategy_profile/tests/test_borrow.py`:
```python
import pandas as pd
from tools.strategy_profile.borrow import fill_gaps
from tools.strategy_profile import config as C

def _profile(rows):
    cols = ["parent_name","season","match_type","intent_class","enabled",
            "cpc_target","cpc_min","cpc_max","launch_cpc","raise_pace_pct",
            "net_per_dollar","confidence","tos_target_pct","borrowed_from","source"]
    return pd.DataFrame([{**{c: None for c in cols}, **r} for r in rows])

def test_borrow_same_cell_other_season_with_haircut():
    # Fresh PEAK EXACT PRODUCT is CONCLUSIVE; Fresh OFF EXACT PRODUCT is WEAK -> borrow cross-season
    prof = _profile([
        dict(parent_name="Fresh", season="PEAK", match_type="EXACT", intent_class="PRODUCT",
             enabled=True, cpc_target=1.00, cpc_min=0.60, cpc_max=1.40, confidence="CONCLUSIVE", source="DERIVED"),
        dict(parent_name="Fresh", season="OFF", match_type="EXACT", intent_class="PRODUCT",
             enabled=True, cpc_target=0.50, cpc_min=0.30, cpc_max=0.70, confidence="WEAK", source="DERIVED"),
    ])
    cpc_by_pm = {("Fresh","EXACT"): 0.90}  # observed p50 CPC for this parent×match
    out = fill_gaps(prof, cpc_by_pm)
    off = out[(out.parent_name=="Fresh") & (out.season=="OFF") & (out.match_type=="EXACT") & (out.intent_class=="PRODUCT")].iloc[0]
    assert off["source"] == "BORROWED"
    assert off["borrowed_from"] == "Fresh|PEAK|EXACT|PRODUCT"
    assert round(off["cpc_target"], 2) == 0.80   # 80% of donor 1.00, same match -> no cost-adjust

def test_cross_match_cost_adjusts_to_target_cpc():
    # donor is EXACT (cpc_target 1.00), gap is PHRASE; borrowed cpc scales to PHRASE's own CPC level
    prof = _profile([
        dict(parent_name="Bottle", season="OFF", match_type="EXACT", intent_class="GENERIC",
             enabled=True, cpc_target=1.00, cpc_min=0.60, cpc_max=1.40, confidence="CONCLUSIVE", source="DERIVED"),
        dict(parent_name="Bottle", season="OFF", match_type="PHRASE", intent_class="GENERIC",
             enabled=True, cpc_target=None, cpc_min=None, cpc_max=None, confidence="WEAK", source="DERIVED"),
    ])
    cpc_by_pm = {("Bottle","EXACT"): 1.00, ("Bottle","PHRASE"): 0.50}
    out = fill_gaps(prof, cpc_by_pm)
    ph = out[(out.parent_name=="Bottle") & (out.match_type=="PHRASE")].iloc[0]
    assert ph["source"] == "BORROWED"
    # donor target 1.00 -> 80% haircut 0.80 -> cost-adjust by 0.50/1.00 -> 0.40
    assert round(ph["cpc_target"], 2) == 0.40

def test_manual_and_conclusive_untouched_no_donor_skipped():
    prof = _profile([
        dict(parent_name="X", season="OFF", match_type="EXACT", intent_class="BRAND",
             cpc_target=0.9, confidence="WEAK", source="MANUAL"),         # MANUAL: untouched
        dict(parent_name="X", season="OFF", match_type="BROAD", intent_class="GENERIC",
             cpc_target=0.4, confidence="WEAK", source="DERIVED"),         # no donor: skipped
    ])
    out = fill_gaps(prof, {})
    assert out[(out.source=="MANUAL")].iloc[0]["cpc_target"] == 0.9
    broad = out[(out.match_type=="BROAD")].iloc[0]
    assert broad["source"] == "DERIVED"           # unchanged, no donor
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd /Users/ori/Develop/OI && .venv/bin/pytest tools/strategy_profile/tests/test_borrow.py -q`
Expected: FAIL — `ModuleNotFoundError: tools.strategy_profile.borrow`.

- [ ] **Step 4: Implement `borrow.py`**

Create `tools/strategy_profile/borrow.py`:
```python
# tools/strategy_profile/borrow.py
"""Fill non-CONCLUSIVE profile cells by borrowing a similar CONCLUSIVE donor (capped, labeled)."""
from __future__ import annotations
import pandas as pd
from . import config as C

STEER_COLS = ["enabled","cpc_target","cpc_min","cpc_max","launch_cpc",
              "raise_pace_pct","net_per_dollar","tos_target_pct"]

def _key(r) -> str:
    return f"{r['parent_name']}|{r['season']}|{r['match_type']}|{r['intent_class']}"

def _match_distance(a: str, b: str) -> int:
    if a == b: return 0
    return C.MATCH_DISTANCE.get((a, b)) or C.MATCH_DISTANCE.get((b, a), 99)

def _rank_donor(gap, cand) -> tuple | None:
    """Lower tuple = better donor. None if cand is not a valid donor for gap."""
    if cand["confidence"] != "CONCLUSIVE": return None
    if cand["intent_class"] != gap["intent_class"]: return None
    same_parent = cand["parent_name"] == gap["parent_name"]
    same_match  = cand["match_type"]  == gap["match_type"]
    if same_parent and same_match:                       # ladder 1: other season, same cell
        return (1, 0)
    if same_parent:                                      # ladder 2: same parent, nearest match
        return (2, _match_distance(gap["match_type"], cand["match_type"]))
    if same_match:                                       # ladder 3: sibling parent, same match
        return (3, 0)
    return (4, 0)                                        # ladder 4: same intent aggregate

def fill_gaps(profile: pd.DataFrame, cpc_by_pm: dict) -> pd.DataFrame:
    """profile: the full DE_PRODUCT_STRATEGY_PROFILE-shaped frame (DERIVED+MANUAL).
    cpc_by_pm: {(parent, match_type): observed p50 cost_per_click} for cross-match cost-adjust.
    Returns the frame with BORROWED rows filled in for gap cells that have a donor."""
    df = profile.copy()
    donors = df[df["confidence"] == "CONCLUSIVE"].to_dict("records")
    out_rows = []
    for _, gap in df.iterrows():
        g = gap.to_dict()
        is_gap = (g.get("source") != "MANUAL") and (g.get("confidence") != "CONCLUSIVE")
        if not is_gap:
            out_rows.append(g); continue
        ranked = sorted(
            ((_rank_donor(g, d), d) for d in donors),
            key=lambda t: (t[0] is None, t[0] if t[0] else (99, 99)))
        best = next(((r, d) for r, d in ranked if r is not None), None)
        if best is None:
            out_rows.append(g); continue                 # no donor -> leave as-is (probe path)
        _, donor = best
        new = dict(g)
        for col in STEER_COLS:
            new[col] = donor.get(col)
        # cap: 80% haircut on cpc_target, clamp cpc_* to <= donor and <= global ceiling
        haircut = (donor["cpc_target"] or 0) * C.BORROW_HAIRCUT
        # cross-match cost-adjust: scale to the TARGET cell's own match-type CPC level
        donor_cpc = cpc_by_pm.get((donor["parent_name"], donor["match_type"]))
        gap_cpc   = cpc_by_pm.get((g["parent_name"], g["match_type"]))
        scale = (gap_cpc / donor_cpc) if (donor_cpc and gap_cpc and donor["match_type"] != g["match_type"]) else 1.0
        for col in ("cpc_target","cpc_min","cpc_max","launch_cpc"):
            v = new.get(col)
            if v is None: continue
            v = min(v, haircut if col == "cpc_target" else v) * scale
            new[col] = round(min(v, donor.get(col, v), C.GLOBAL_BID_CAP), 2)
        new["source"] = "BORROWED"
        new["borrowed_from"] = _key(donor)
        new["confidence"] = donor["confidence"]
        out_rows.append(new)
    return pd.DataFrame(out_rows)
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd /Users/ori/Develop/OI && .venv/bin/pytest tools/strategy_profile/tests/test_borrow.py -q`
Expected: 3 passed.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ori/Develop/OI add tools/strategy_profile/borrow.py tools/strategy_profile/tests/test_borrow.py tools/strategy_profile/config.py
git -C /Users/ori/Develop/OI commit --no-verify -m "feat(coacher): borrow.py — fill gap cells from similar CONCLUSIVE donor (C)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task B2: Wire borrow into the pipeline + load BORROWED rows

**Files:** Modify `tools/strategy_profile/run.py`, `tools/strategy_profile/load.py`

- [ ] **Step 1: Make `load_table` replace BORROWED rows too**

In `load.py`, change the signature and the DELETE so callers can refresh BORROWED alongside DERIVED (MANUAL still never touched):
```python
def load_table(df, table: str, updated_by="strategy_profile_tool", replace_sources=("DERIVED",)):
    """Replace only rows whose source is in replace_sources (MANUAL preserved)."""
    in_list = ",".join(f"'{s}'" for s in replace_sources)
    _bq(f"DELETE FROM `{C.PROJECT}.{C.DATASET}.{table}` WHERE source IN ({in_list})")
    # ... rest unchanged ...
```

- [ ] **Step 2: Build the `cpc_by_pm` map and call borrow in `run.py`**

In `run.py`, extend the existing derive import to also bring in `normalize_match_type`:
```python
from .derive import derive_profile, derive_main_keywords, normalize_match_type
```
Then, after `prof = derive_profile(base)` and before `load_table(prof, ...)`, add:
```python
    from .borrow import fill_gaps
    # observed median CPC per (parent, match_type) for cross-match cost-adjust.
    # base reliably carries "cpc" and "clicks" (see derive.py); avoid relying on a "cost" column.
    base["match_type"] = base["targeting_type"].map(normalize_match_type)
    cpc_by_pm = (base[base["clicks"] > 0]
                 .groupby(["parent_name", "match_type"])["cpc"].median().to_dict())
    prof = fill_gaps(prof, cpc_by_pm)
```
Change the profile load call to replace both sources:
```python
    load_table(prof, "DE_PRODUCT_STRATEGY_PROFILE", replace_sources=("DERIVED","BORROWED"))
```
(Leave the `main_keywords` load call as-is — default `("DERIVED",)`.)

- [ ] **Step 3: Run the pipeline against live data**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m tools.strategy_profile.run`
Expected: prints `profile rows=…` with no error; the count includes the new BORROWED rows.

- [ ] **Step 4: Validate BORROWED rows landed, MANUAL preserved, haircut held**

```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT source, confidence, COUNT(*) cells,
       COUNTIF(borrowed_from IS NOT NULL) with_donor,
       ROUND(MAX(cpc_target),2) max_cpc
FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`
GROUP BY 1,2 ORDER BY 1,2'
```
Expected: a `BORROWED` group appears with `with_donor = cells` and `max_cpc ≤ 2.0`; any MANUAL rows unchanged in count; total profile rows did not explode (each gap fills at most one row).

- [ ] **Step 5: Commit**

```bash
git -C /Users/ori/Develop/OI add tools/strategy_profile/run.py tools/strategy_profile/load.py
git -C /Users/ori/Develop/OI commit --no-verify -m "feat(coacher): wire borrow into strategy_profile run + load BORROWED (C)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task B3: Make BORROWED cells steer

**Files:** Modify `scripts/bigquery/views/V_ADS_COACH_DATA.sql`

- [ ] **Step 1: Extend `profile_steers`**

Change the line (~1577):
```sql
    (psp.source = 'MANUAL' OR psp.confidence = 'CONCLUSIVE') as profile_steers,
```
to:
```sql
    (psp.source IN ('MANUAL','BORROWED') OR psp.confidence = 'CONCLUSIVE') as profile_steers,
```

- [ ] **Step 2: Deploy + validate borrowed cells now steer, parity held**

Run: `bq query --use_legacy_sql=false < /Users/ori/Develop/OI/scripts/bigquery/views/V_ADS_COACH_DATA.sql`
```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT COUNT(*) rows_total,
       COUNTIF(profile_source="BORROWED" AND profile_steers) borrowed_steering,
       COUNTIF(profile_source="BORROWED" AND NOT profile_steers) borrowed_not_steering
FROM `onyga-482313.OI.V_ADS_COACH_DATA`'
```
Expected: `rows_total` unchanged; `borrowed_not_steering = 0` (every borrowed cell steers); `borrowed_steering > 0`.

- [ ] **Step 3: Confirm the engine has no new inversions**

```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT COUNT(*) rows_total,
       COUNTIF(target_action="INCREASE_BID" AND bid_change_pct<0) inc_neg,
       COUNTIF(target_action="REDUCE_BID" AND bid_change_pct>0) red_inv
FROM `onyga-482313.OI.V_ADS_COACH`'
```
Expected: `inc_neg=0`, `red_inv=0`; `rows_total` == `V_ADS_COACH_DATA` count.

- [ ] **Step 4: Commit**

```bash
git -C /Users/ori/Develop/OI add scripts/bigquery/views/V_ADS_COACH_DATA.sql
git -C /Users/ori/Develop/OI commit --no-verify -m "feat(coacher): BORROWED cells steer (profile_steers) (C)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Component C — Probe

### Task C1: `DE_PROBE_LOG` table

**Files:** Create `scripts/bigquery/tables/DE_PROBE_LOG.sql`; Modify `config.yaml`

- [ ] **Step 1: Write + run the DDL**

Create `scripts/bigquery/tables/DE_PROBE_LOG.sql`:
```sql
-- DE_PROBE_LOG — tracks each keyword probe's decision budget (15 clicks / 14 days). Coacher C.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PROBE_LOG` (
  keyword_id          STRING NOT NULL,
  parent_name         STRING,
  season              STRING,
  match_type          STRING,
  intent_class        STRING,
  probe_launch_cpc    FLOAT64,
  probe_started_at    DATE,
  clicks_accumulated  INT64,
  status              STRING,        -- ACTIVE | GRADUATED | EXHAUSTED
  decided_at          DATE,
  updated_at          TIMESTAMP
);
```
Run: `bq query --use_legacy_sql=false < /Users/ori/Develop/OI/scripts/bigquery/tables/DE_PROBE_LOG.sql`
Expected: succeeds.

- [ ] **Step 2: Register in config.yaml + commit**

Add `DE_PROBE_LOG` to `config.yaml` (tables section). Then:
```bash
git -C /Users/ori/Develop/OI add scripts/bigquery/tables/DE_PROBE_LOG.sql config.yaml
git -C /Users/ori/Develop/OI commit --no-verify -m "feat(coacher): DE_PROBE_LOG table (C probe close-the-loop)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task C2: Expose probe signals on `V_ADS_COACH_DATA`

**Files:** Modify `scripts/bigquery/views/V_ADS_COACH_DATA.sql`

- [ ] **Step 1: Add a `probe_targets` CTE and join it**

Add a CTE (near the other signal CTEs) that derives, per cell, whether it is a PROBE-resolution gap and the per-match-type launch CPC, plus the active probe status per keyword:
```sql
probe_cell AS (   -- cells the gap-detector says to PROBE + their per-match-type launch CPC
  SELECT g.parent_name, g.season, g.match_type, g.intent_class,
         pc.launch_cpc AS probe_launch_cpc
  FROM `onyga-482313.OI.V_STRATEGY_GAPS` g
  JOIN (   -- p50 real CPC per parent×match from the keyword report, capped at the ceiling
    SELECT parent_name, match_type,
           LEAST(APPROX_QUANTILES(cost_per_click, 100)[OFFSET(50)], 2.0) AS launch_cpc
    FROM `onyga-482313.OI.V_KEYWORD_DAILY`
    WHERE clicks > 0 GROUP BY 1,2
  ) pc USING (parent_name, match_type)
  WHERE g.suggested_resolution = 'PROBE'
),
probe_state AS (
  SELECT keyword_id, status AS probe_status
  FROM `onyga-482313.OI.DE_PROBE_LOG` WHERE status = 'ACTIVE'
)
```
In the main SELECT (ENABLED keyword branch), add outputs:
```sql
    (pcell.parent_name IS NOT NULL)               as is_probe_cell,
    pcell.probe_launch_cpc                         as probe_launch_cpc,
    ps.probe_status                                as probe_status,
```
joined via:
```sql
    LEFT JOIN probe_cell pcell
      ON pcell.parent_name=<parent_expr> AND pcell.season=<season_expr>
     AND pcell.match_type=<match_type_expr> AND pcell.intent_class=COALESCE(kic.intent_class,'GENERIC')
    LEFT JOIN probe_state ps ON ps.keyword_id=<keyword_id_expr>
```
(use the same parent/season/match/intent/keyword expressions the file already uses; `<keyword_id_expr>` is whatever feeds the `keyword_id` output). In the OPPORTUNITY UNION branch add `CAST(NULL AS BOOL) as is_probe_cell, CAST(NULL AS FLOAT64) as probe_launch_cpc, CAST(NULL AS STRING) as probe_status,`.

- [ ] **Step 2: Deploy + validate**

Run: `bq query --use_legacy_sql=false < /Users/ori/Develop/OI/scripts/bigquery/views/V_ADS_COACH_DATA.sql`
```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT COUNT(*) rows_total,
       COUNTIF(is_probe_cell) probe_cell_rows,
       COUNTIF(is_probe_cell AND COALESCE(no_traffic_rate,0)>=0.8) probe_starved_rows,
       ROUND(MAX(probe_launch_cpc),2) max_launch_cpc
FROM `onyga-482313.OI.V_ADS_COACH_DATA`'
```
Expected: `rows_total` unchanged; `max_launch_cpc ≤ 2.0`; `probe_starved_rows` = the keywords that will actually probe (may be small/zero today — acceptable).

- [ ] **Step 3: Commit**

```bash
git -C /Users/ori/Develop/OI add scripts/bigquery/views/V_ADS_COACH_DATA.sql
git -C /Users/ori/Develop/OI commit --no-verify -m "feat(coacher): expose probe signals (is_probe_cell, probe_launch_cpc) (C)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task C3: `target_action='PROBE'` branch in `V_ADS_COACH`

**Files:** Modify `scripts/bigquery/views/V_ADS_COACH.sql`

- [ ] **Step 1: Add the PROBE branch to `target_action`**

A probe fires only on a starved keyword (no usable performance signal) in a probe cell with an active/absent probe (not yet graduated/exhausted). Place it **before the launch/no-traffic and dead-zone fall-throughs but after the real REDUCE/STOP tiers** (a keyword with real bad data must still reduce/stop, not probe). Insert, just before the `-- Dead zone:` KEEP_TARGET branch:
```sql
    -- ═══ PROBE: starved keyword in a donor-less gap cell — bounded exploration ═══
    -- Only when there's no real performance to act on (no traffic) and the gap-detector
    -- marked the cell PROBE; capped per-match-type launch CPC; budget tracked in DE_PROBE_LOG.
    WHEN d.is_probe_cell
         AND COALESCE(d.no_traffic_rate, 0) >= 0.8
         AND COALESCE(d.target_orders_8w, 0) = 0
         AND COALESCE(d.probe_status, 'ACTIVE') = 'ACTIVE'
         AND COALESCE(d.current_bid, 0) < d.probe_launch_cpc
      THEN 'PROBE'
```

- [ ] **Step 2: Add the PROBE bid to `recommended_bid`**

In the `recommended_bid` CASE, before the mode-aware increase block, add:
```sql
    -- PROBE: bid to the per-match-type launch CPC (p50 real CPC for this parent×match)
    WHEN d.is_probe_cell AND COALESCE(d.no_traffic_rate,0) >= 0.8
         AND COALESCE(d.target_orders_8w,0) = 0
         AND COALESCE(d.probe_status,'ACTIVE') = 'ACTIVE'
         AND COALESCE(d.current_bid,0) < d.probe_launch_cpc
      THEN ROUND(LEAST(d.probe_launch_cpc, 2.0), 2)
```

- [ ] **Step 3: Add a probe decision-trace chip**

In `target_decision_trace`, near the `tos` chip, add (uses `d.match_type` exposed in Task A1; `value` is the static label `probe`):
```sql
      IF(d.is_probe_cell AND COALESCE(d.no_traffic_rate,0) >= 0.8,
        CONCAT(',{"id":"probe","label":"Probe","sql":"V_STRATEGY_GAPS","rule":"starved cell, no donor — exploring at $',
          CAST(ROUND(COALESCE(d.probe_launch_cpc,0),2) AS STRING),
          ' (p50 ', COALESCE(d.match_type,''), ' CPC)","pass":true,"value":"probe"}'),
        ''),
```

- [ ] **Step 4: Deploy + validate the probe fires correctly and safely**

Run: `bq query --use_legacy_sql=false < /Users/ori/Develop/OI/scripts/bigquery/views/V_ADS_COACH.sql`
```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT COUNT(*) rows_total,
       COUNTIF(target_action="PROBE") probes,
       COUNTIF(target_action="PROBE" AND recommended_bid>2.0) probe_over_cap,
       COUNTIF(target_action="PROBE" AND target_orders_8w>0) probe_on_real_data,
       COUNTIF(target_action="INCREASE_BID" AND bid_change_pct<0) inc_neg
FROM `onyga-482313.OI.V_ADS_COACH`'
```
Expected: `rows_total` == data count; `probe_over_cap=0`; `probe_on_real_data=0` (never probe a keyword with orders); `inc_neg=0`. `probes` may be small/0 today — acceptable (forward guardrail).

- [ ] **Step 5: Commit**

```bash
git -C /Users/ori/Develop/OI add scripts/bigquery/views/V_ADS_COACH.sql
git -C /Users/ori/Develop/OI commit --no-verify -m "feat(coacher): target_action=PROBE for starved gap cells (C)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task C4: `DE_PROBE_LOG` daily update (graduate / exhaust)

**Files:** Create `scripts/bigquery/procedures/SP_REFRESH_PROBE_LOG.sql`; Modify `config.yaml`

- [ ] **Step 1: Write the procedure**

Create `scripts/bigquery/procedures/SP_REFRESH_PROBE_LOG.sql`. It (1) inserts new ACTIVE rows for keywords now recommended PROBE that aren't logged, (2) updates accumulated clicks, (3) graduates at 15 clicks, (4) exhausts after 14 days.
```sql
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REFRESH_PROBE_LOG`()
BEGIN
  -- 1. start probes newly recommended this run
  INSERT INTO `onyga-482313.OI.DE_PROBE_LOG`
    (keyword_id, parent_name, season, match_type, intent_class, probe_launch_cpc,
     probe_started_at, clicks_accumulated, status, decided_at, updated_at)
  SELECT c.keyword_id, c.parent_name, c.season, c.match_type, c.intent_class,
         c.recommended_bid, CURRENT_DATE('America/Los_Angeles'), 0, 'ACTIVE', NULL, CURRENT_TIMESTAMP()
  FROM `onyga-482313.OI.V_ADS_COACH` c
  LEFT JOIN `onyga-482313.OI.DE_PROBE_LOG` l ON l.keyword_id = c.keyword_id AND l.status='ACTIVE'
  WHERE c.target_action='PROBE' AND c.keyword_id IS NOT NULL AND l.keyword_id IS NULL;

  -- 2. refresh accumulated clicks since probe start (from the keyword report)
  UPDATE `onyga-482313.OI.DE_PROBE_LOG` l
  SET clicks_accumulated = (
        SELECT COALESCE(SUM(kd.clicks),0) FROM `onyga-482313.OI.V_KEYWORD_DAILY` kd
        WHERE CAST(kd.keyword_id AS STRING) = l.keyword_id AND kd.date >= l.probe_started_at),
      updated_at = CURRENT_TIMESTAMP()
  WHERE l.status='ACTIVE';

  -- 3. graduate at the click budget, 4. exhaust at the day budget
  UPDATE `onyga-482313.OI.DE_PROBE_LOG` l
  SET status = CASE
        WHEN l.clicks_accumulated >= 15 THEN 'GRADUATED'
        WHEN DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), l.probe_started_at, DAY) >= 14 THEN 'EXHAUSTED'
        ELSE 'ACTIVE' END,
      decided_at = CASE
        WHEN l.clicks_accumulated >= 15
          OR DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), l.probe_started_at, DAY) >= 14
        THEN CURRENT_DATE('America/Los_Angeles') ELSE NULL END,
      updated_at = CURRENT_TIMESTAMP()
  WHERE l.status='ACTIVE';
END;
```
Run: `bq query --use_legacy_sql=false < /Users/ori/Develop/OI/scripts/bigquery/procedures/SP_REFRESH_PROBE_LOG.sql`
Expected: procedure created.

- [ ] **Step 2: Execute once + validate**

```bash
bq query --use_legacy_sql=false 'CALL `onyga-482313.OI.SP_REFRESH_PROBE_LOG`()'
bq query --use_legacy_sql=false --format=pretty '
SELECT status, COUNT(*) n, ROUND(MAX(probe_launch_cpc),2) max_cpc,
       MAX(clicks_accumulated) max_clicks
FROM `onyga-482313.OI.DE_PROBE_LOG` GROUP BY 1 ORDER BY 1'
```
Expected: runs clean; any rows are ACTIVE/GRADUATED/EXHAUSTED with `max_cpc ≤ 2.0`. (May be empty today if nothing probes — acceptable; the SP is idempotent.)

- [ ] **Step 3: Register in config.yaml + commit**

Add `SP_REFRESH_PROBE_LOG` to `config.yaml` (procedures). Note in the commit that scheduling it (daily, after the coach refresh) is a follow-up wiring step, not part of this task.
```bash
git -C /Users/ori/Develop/OI add scripts/bigquery/procedures/SP_REFRESH_PROBE_LOG.sql config.yaml
git -C /Users/ori/Develop/OI commit --no-verify -m "feat(coacher): SP_REFRESH_PROBE_LOG — close probe loop (15 clicks/14 days) (C)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task FINAL: Holistic validation + memory

**Files:** none (read-only) + memory files

- [ ] **Step 1: Full sweep**

```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT COUNT(*) rows_total,
       COUNTIF(target_action="REDUCE_BID" AND bid_change_pct>0) red_inv,
       COUNTIF(recommended_bid>th_bid_cap AND recommended_bid IS NOT NULL) over_ceiling,
       COUNTIF(target_action="PROBE" AND (recommended_bid>2.0 OR target_orders_8w>0)) bad_probes
FROM `onyga-482313.OI.V_ADS_COACH`'
```
Expected: `red_inv=0`, `over_ceiling=0`, `bad_probes=0`; `rows_total` == `V_ADS_COACH_DATA` count.

- [ ] **Step 2: End-to-end coherence check**

```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT
  (SELECT COUNT(*) FROM `onyga-482313.OI.V_STRATEGY_GAPS`) gaps,
  (SELECT COUNT(*) FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE` WHERE source="BORROWED") borrowed,
  (SELECT COUNTIF(target_action="PROBE") FROM `onyga-482313.OI.V_ADS_COACH`) probes'
```
Expected: numbers are internally consistent (borrowed cells ≤ gaps that had a donor; probes only where no donor).

- [ ] **Step 3: Update memory**

Create `/Users/ori/.claude/projects/-Users-ori-Develop/memory/project_coacher_gaps_borrow_probe.md` (type project) summarizing C: the three components, the auto-steer-with-caps + per-type-probe-CPC decisions, what's live, and the deferrals (dashboard surface, no-keyword cells, Bunny/LolliBall, probe scheduling). Add a one-line index entry to `MEMORY.md`.
