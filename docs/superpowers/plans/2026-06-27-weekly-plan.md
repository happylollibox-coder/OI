# Rolling Weekly Plan (Coacher D) — Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the backend of a per-product rolling weekly plan: a budget-first, purpose-tagged, cell-grain plan that measures actuals per purpose, learns what works, and improves each iteration.

**Architecture:** Two editable tables (`DE_PRODUCT_BUDGET`, `DE_WEEKLY_PLAN`), one helper view (`V_WEEKLY_CELL_NET`), a Python generator (`tools/weekly_plan/`) that allocates budget → assigns purposes → sets expected values → writes the plan, and three read views (`V_WEEKLY_PLAN_REVIEW`, `V_PLAN_LEARNINGS`, `V_WEEKLY_PLAN_ACTIONS`). **Backend only** — no frontend ([[feedback_all_logic_in_backend]]); the dashboard surface is v1.1.

**Tech Stack:** BigQuery Standard SQL (`bq` CLI, project `onyga-482313`); Python 3.12 `.venv` at repo root (`pandas`, `pytest`); reuses `DE_PRODUCT_STRATEGY_PROFILE` (B), `V_STRATEGY_GAPS`/`DE_PROBE_LOG` (C), `V_PEAK_RELEVANCE`, `DIM_US_HOLIDAYS`, `FACT_AMAZON_ADS`, `V_KEYWORD_INTENT_CLASS`, `DE_COACH_THRESHOLDS`, `V_ADS_COACH`.

**Context every task needs:**
- Run Python from repo root as a module: `cd /Users/ori/Develop/OI && .venv/bin/python -m tools.weekly_plan.run` (tests: `.venv/bin/pytest tools/weekly_plan/tests -q`).
- Deploy a view/table: `bq query --use_legacy_sql=false < /Users/ori/Develop/OI/scripts/bigquery/<path>.sql` (pipe via **stdin** — a positional arg makes `bq` parse the leading `--` comment as a flag).
- `git` from this dir can lose cwd; use `git -C /Users/ori/Develop/OI ...`. Commit `--no-verify`. End messages with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Cell grain** everywhere = `parent_name × season(PEAK/OFF) × match_type(BROAD/EXACT/PHRASE/PRODUCT/AUTO/CATEGORY/OTHER) × intent_class(BRAND/PRODUCT/GENERIC)`. `season` of a week = PEAK if the week overlaps any `DIM_US_HOLIDAYS` boost..cooldown window for which the product is a *relevant* peak (`V_PEAK_RELEVANCE.is_relevant_peak`), else OFF.
- **camp_parent mapping** (used for per-cell net): `FACT_AMAZON_ADS.campaign_id` → dominant-by-spend `DIM_PRODUCT.parent_name` via `ASIN_BY_CAMPAIGN_NAME` (same pattern as `V_KEYWORD_INTENT_CLASS`). Match type from `targeting_type` (BROAD/EXACT/PHRASE/AUTOMATIC→AUTO/ASIN→PRODUCT/ASIN EXPANDED→PRODUCT/CATEGORY). Intent from `V_KEYWORD_INTENT_CLASS` on `parent_name + LOWER(targeting)`.
- **Net profit = ads-attributed** = `GROSS_PROFIT − Ads_cost` (the coacher's net), per [[fact_oi_net_roas_no_halo]].
- Week boundary = Monday, `America/Los_Angeles`. Reviews run on **completed** weeks only.
- Constants live in `tools/weekly_plan/config.py`: `HORIZON_WEEKS=4`, `TREND_WEEKS=8`, `EXPLORE_CAP_FRAC=0.10` (CAP cells get ≤10% of budget), `ON_PLAN_TOL=0.90`, `PEAK_BUDGET_MULT=2.5`, `BOOTSTRAP_WEEKS=8`, `PROBE_CLICKS=15`.

---

### Task 1: `DE_PRODUCT_BUDGET` table

**Files:** Create `scripts/bigquery/tables/DE_PRODUCT_BUDGET.sql`; Modify `config.yaml`

- [ ] **Step 1: Write + run the DDL**
```sql
-- DE_PRODUCT_BUDGET — per-product weekly spend ceiling (risk envelope). Coacher D.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PRODUCT_BUDGET` (
  parent_name    STRING NOT NULL,
  week_start     DATE NOT NULL,
  weekly_budget  FLOAT64,
  source         STRING,          -- MANUAL | BUSINESS_PLAN | BOOTSTRAP
  updated_at     TIMESTAMP,
  updated_by     STRING
);
```
Run: `bq query --use_legacy_sql=false < /Users/ori/Develop/OI/scripts/bigquery/tables/DE_PRODUCT_BUDGET.sql`
Expected: succeeds.

- [ ] **Step 2: Register in config.yaml (tables, type data_entry) + commit**
```bash
git -C /Users/ori/Develop/OI add scripts/bigquery/tables/DE_PRODUCT_BUDGET.sql config.yaml
git -C /Users/ori/Develop/OI commit --no-verify -m "feat(coacher): DE_PRODUCT_BUDGET table (D budget anchor)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `DE_WEEKLY_PLAN` table

**Files:** Create `scripts/bigquery/tables/DE_WEEKLY_PLAN.sql`; Modify `config.yaml`

- [ ] **Step 1: Write + run the DDL**
```sql
-- DE_WEEKLY_PLAN — per-cell weekly plan (history-retained). Coacher D.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_WEEKLY_PLAN` (
  week_start       DATE NOT NULL,
  horizon          STRING,         -- CURRENT | FUTURE
  parent_name      STRING NOT NULL,
  season           STRING,         -- PEAK | OFF
  match_type       STRING,
  intent_class     STRING,
  purpose          STRING,         -- SCALE | MAP | PROBE | DEFEND | CUT | HOLD
  objective        STRING,
  success_metric   STRING,         -- NET_PROFIT | CLICKS | TOS_SHARE | SPEND_DOWN | HOLD
  expected_value   FLOAT64,
  target_cpc       FLOAT64,        -- SCALE only (from profile cpc_target)
  planned_spend    FLOAT64,
  spend_mode       STRING,         -- SCALE | CAP
  expected_net_profit FLOAT64,     -- product-level trend projection (repeated on each cell)
  plan_net_profit  FLOAT64,        -- business-plan target (best-effort; may be NULL)
  coach_mode_hint  STRING,         -- GUARDIAN | BLITZ | COOLDOWN
  status           STRING,         -- PROPOSED | ON_PLAN | OFF_PLAN | MET | MISSED
  actual_value     FLOAT64,        -- written back by the review (Task 6)
  source           STRING,         -- DERIVED | MANUAL
  updated_at       TIMESTAMP,
  updated_by       STRING
);
```
Run it (stdin). Expected: succeeds.

- [ ] **Step 2: Register in config.yaml + commit** (message: `feat(coacher): DE_WEEKLY_PLAN table (D plan, cell grain, history-retained)`).

---

### Task 3: `V_WEEKLY_CELL_NET` helper view (weekly net per cell)

**Files:** Create `scripts/bigquery/views/V_WEEKLY_CELL_NET.sql`; Modify `config.yaml`

The shared base for the trend (generator), the review actuals, and learnings. One row per `parent × season × match_type × intent_class × week_start` with net/spend/clicks/orders.

- [ ] **Step 1: Write the view**
```sql
-- V_WEEKLY_CELL_NET — weekly ads net profit/spend/clicks per strategy cell. Coacher D.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_CELL_NET` AS
WITH camp_parent AS (
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
    WHERE a.date >= DATE('2025-09-23') GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
peak_weeks AS (   -- weeks that are a RELEVANT peak for a family (per-product peak, #4)
  SELECT r.family, h.boost_start, h.cooldown_start
  FROM `onyga-482313.OI.V_PEAK_RELEVANCE` r
  JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h ON h.holiday_name = r.holiday_name
  WHERE r.is_relevant_peak
),
base AS (
  SELECT
    cp.parent_name,
    DATE_TRUNC(a.date, WEEK(MONDAY)) AS week_start,
    CASE UPPER(a.targeting_type)
      WHEN 'BROAD' THEN 'BROAD' WHEN 'EXACT' THEN 'EXACT' WHEN 'PHRASE' THEN 'PHRASE'
      WHEN 'AUTOMATIC' THEN 'AUTO' WHEN 'ASIN' THEN 'PRODUCT' WHEN 'ASIN EXPANDED' THEN 'PRODUCT'
      WHEN 'CATEGORY' THEN 'CATEGORY' ELSE UPPER(a.targeting_type) END AS match_type,
    COALESCE(ic.intent_class, 'GENERIC') AS intent_class,
    a.GROSS_PROFIT, a.Ads_cost, a.date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camp_parent cp ON cp.campaign_id = a.campaign_id
  LEFT JOIN `onyga-482313.OI.V_KEYWORD_INTENT_CLASS` ic
    ON ic.parent_name = cp.parent_name AND ic.keyword_text = LOWER(a.targeting)
  WHERE a.date >= DATE('2025-09-23')
)
SELECT
  b.parent_name, b.week_start, b.match_type, b.intent_class,
  IF(EXISTS (SELECT 1 FROM peak_weeks pw
             WHERE pw.family = b.parent_name AND b.date BETWEEN pw.boost_start AND pw.cooldown_start),
     'PEAK', 'OFF') AS season,
  ROUND(SUM(b.GROSS_PROFIT - b.Ads_cost), 2) AS net_profit,
  ROUND(SUM(b.Ads_cost), 2) AS spend,
  SUM(CASE WHEN b.GROSS_PROFIT IS NOT NULL THEN 1 ELSE 0 END) AS rows_n
FROM base b
GROUP BY b.parent_name, b.week_start, b.match_type, b.intent_class, season
```
(Clicks/orders can be added later; net+spend cover the SCALE/CUT metrics. `season` here matches the per-product peak rule.)

- [ ] **Step 2: Deploy + validate**
```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT season, COUNT(*) cells, ROUND(SUM(net_profit),0) net, ROUND(SUM(spend),0) spend
FROM `onyga-482313.OI.V_WEEKLY_CELL_NET` GROUP BY 1 ORDER BY 1'
```
Expected: rows for OFF (and PEAK where a relevant peak week exists); net/spend are finite; per-cell weekly grain (spot-check one parent×week sums to that parent's weekly ads net).

- [ ] **Step 3: Register in config.yaml + commit** (`feat(coacher): V_WEEKLY_CELL_NET — weekly net per strategy cell (D)`).

---

### Task 4: `tools/weekly_plan` pure logic (allocate / assign purpose / expected value) — unit-tested

**Files:** Create `tools/weekly_plan/__init__.py`, `tools/weekly_plan/config.py`, `tools/weekly_plan/compute.py`, `tools/weekly_plan/tests/__init__.py`, `tools/weekly_plan/tests/test_compute.py`

- [ ] **Step 1: Write `config.py`**
```python
"""Constants for the weekly plan generator (Coacher D)."""
PROJECT = "onyga-482313"
DATASET = "OI"
HORIZON_WEEKS = 4          # current + 3 future
TREND_WEEKS = 8            # trailing weeks for the net-profit trend
BOOTSTRAP_WEEKS = 8        # trailing weeks for the budget bootstrap
EXPLORE_CAP_FRAC = 0.10    # CAP (unproven) cells share at most this fraction of budget
ON_PLAN_TOL = 0.90         # actual >= TOL * expected => ON_PLAN
PEAK_BUDGET_MULT = 2.5     # in-window peak cells weighted up by this
PROBE_CLICKS = 15          # MAP/PROBE success target
```

- [ ] **Step 2: Write the failing test** `tools/weekly_plan/tests/test_compute.py`
```python
import pandas as pd
from tools.weekly_plan.compute import assign_purpose, expected_value, allocate_budget
from tools.weekly_plan import config as C

def _cell(**kw):
    base = dict(parent_name="Fresh", season="OFF", match_type="EXACT", intent_class="PRODUCT",
                confidence="CONCLUSIVE", net_per_dollar=0.5, cpc_target=0.9, source="DERIVED",
                is_gap=False, is_brand=False, probe_active=False, net_trend=100.0, is_bleeder=False)
    base.update(kw); return base

def test_assign_purpose_scale_map_defend_cut():
    assert assign_purpose(_cell(confidence="CONCLUSIVE", net_per_dollar=0.5)) == "SCALE"
    assert assign_purpose(_cell(confidence="WEAK", is_gap=True, net_per_dollar=0.0)) == "MAP"
    assert assign_purpose(_cell(is_brand=True)) == "DEFEND"
    assert assign_purpose(_cell(is_bleeder=True, net_per_dollar=-0.3, confidence="WEAK")) == "CUT"

def test_expected_value_by_purpose():
    assert expected_value("MAP", _cell(), planned_spend=20) == C.PROBE_CLICKS
    # SCALE expected NP = net_per_dollar * planned_spend
    assert round(expected_value("SCALE", _cell(net_per_dollar=0.5), planned_spend=200), 1) == 100.0

def test_allocate_budget_scale_uncapped_cap_limited():
    cells = pd.DataFrame([
        _cell(parent_name="Fresh", match_type="EXACT", purpose="SCALE", net_per_dollar=0.6),
        _cell(parent_name="Fresh", match_type="BROAD", purpose="MAP", net_per_dollar=0.0, confidence="WEAK", is_gap=True),
    ])
    cells["purpose"] = [assign_purpose(r) for _, r in cells.iterrows()]
    out = allocate_budget(cells, weekly_budget=1000.0, peak=False)
    scale = out[out.purpose == "SCALE"].iloc[0]
    cap = out[out.purpose == "MAP"].iloc[0]
    assert scale["spend_mode"] == "SCALE"
    assert cap["spend_mode"] == "CAP"
    # CAP cells together <= EXPLORE_CAP_FRAC * budget
    assert out[out.spend_mode == "CAP"]["planned_spend"].sum() <= C.EXPLORE_CAP_FRAC * 1000 + 1e-6
    # SCALE gets the rest (the floor)
    assert scale["planned_spend"] > cap["planned_spend"]
```

- [ ] **Step 3: Run it — expect ModuleNotFoundError**
Run: `cd /Users/ori/Develop/OI && .venv/bin/pytest tools/weekly_plan/tests/test_compute.py -q` → FAIL (no module).

- [ ] **Step 4: Implement `compute.py`**
```python
"""Pure planning logic for the weekly plan (Coacher D). No I/O."""
from __future__ import annotations
import pandas as pd
from . import config as C

def assign_purpose(cell) -> str:
    """cell: dict-like with confidence, net_per_dollar, is_gap, is_brand, probe_active, is_bleeder."""
    if cell.get("is_brand"):
        return "DEFEND"
    if cell.get("is_bleeder") or (cell.get("net_per_dollar", 0) < 0 and cell.get("confidence") != "CONCLUSIVE"):
        return "CUT"
    if cell.get("probe_active"):
        return "PROBE"
    if cell.get("confidence") == "CONCLUSIVE" and cell.get("net_per_dollar", 0) > 0:
        return "SCALE"
    if cell.get("is_gap"):
        return "MAP"
    return "HOLD"

SUCCESS_METRIC = {"SCALE": "NET_PROFIT", "MAP": "CLICKS", "PROBE": "CLICKS",
                  "DEFEND": "TOS_SHARE", "CUT": "SPEND_DOWN", "HOLD": "HOLD"}

def expected_value(purpose: str, cell, planned_spend: float):
    if purpose in ("MAP", "PROBE"):
        return float(C.PROBE_CLICKS)
    if purpose == "SCALE":
        return round((cell.get("net_per_dollar") or 0) * (planned_spend or 0), 2)
    return None  # DEFEND/CUT/HOLD measured but no single expected scalar in v1

def allocate_budget(cells: pd.DataFrame, weekly_budget: float, peak: bool) -> pd.DataFrame:
    """Split weekly_budget across a product's cells. CAP (unproven) cells share <= EXPLORE_CAP_FRAC;
    SCALE cells take the remainder as a floor (they may run beyond it while profitable)."""
    df = cells.copy()
    if "purpose" not in df:
        df["purpose"] = [assign_purpose(r) for _, r in df.iterrows()]
    df["spend_mode"] = df["purpose"].map(lambda p: "SCALE" if p in ("SCALE", "DEFEND") else "CAP")
    cap_pool = C.EXPLORE_CAP_FRAC * weekly_budget
    cap_mask = df["spend_mode"] == "CAP"
    n_cap = int(cap_mask.sum())
    df.loc[cap_mask, "planned_spend"] = round(cap_pool / n_cap, 2) if n_cap else 0.0
    # SCALE/DEFEND share the remainder, weighted by net_per_dollar (peak cells boosted)
    scale_mask = ~cap_mask
    remainder = max(weekly_budget - cap_pool, 0.0)
    w = (df.loc[scale_mask, "net_per_dollar"].clip(lower=0.01)
         * (C.PEAK_BUDGET_MULT if peak else 1.0))
    wsum = w.sum()
    df.loc[scale_mask, "planned_spend"] = (
        (w / wsum * remainder).round(2) if wsum > 0 else 0.0)
    return df
```

- [ ] **Step 5: Run the test — expect pass**
Run: `.venv/bin/pytest tools/weekly_plan/tests/test_compute.py -q` → PASS.

- [ ] **Step 6: Commit** (`feat(coacher): weekly_plan compute — purpose assignment + budget allocation (D)`).

---

### Task 5: `tools/weekly_plan/run.py` — pull inputs, build plan, load

**Files:** Create `tools/weekly_plan/load.py`, `tools/weekly_plan/run.py`

- [ ] **Step 1: Write `load.py`** (mirror `tools/strategy_profile/load.py`, but only replace DERIVED rows for the CURRENT+FUTURE weeks — never past weeks, never MANUAL):
```python
"""Load DERIVED weekly-plan rows for the current+future window, preserving MANUAL + past weeks."""
import datetime as dt, json, subprocess, tempfile
from . import config as C

def _bq(sql):
    out = subprocess.run(["bq", f"--project_id={C.PROJECT}", "query", "--use_legacy_sql=false"],
                         input=sql, capture_output=True, text=True)
    if out.returncode: raise SystemExit(out.stderr)

def load_plan(df, from_week: str):
    """Replace DERIVED rows with week_start >= from_week; MANUAL + past weeks untouched."""
    _bq(f"DELETE FROM `{C.PROJECT}.{C.DATASET}.DE_WEEKLY_PLAN` "
        f"WHERE source='DERIVED' AND week_start >= DATE('{from_week}')")
    now = dt.datetime.utcnow().isoformat()
    rows = df.where(df.notna(), None).to_dict("records")
    for r in rows:
        for k, v in r.items():
            if isinstance(v, float) and v != v: r[k] = None
        r["updated_at"] = now; r["updated_by"] = "weekly_plan_tool"
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        for r in rows: f.write(json.dumps(r, default=str) + "\n")
        path = f.name
    out = subprocess.run(["bq", f"--project_id={C.PROJECT}", "load",
        "--source_format=NEWLINE_DELIMITED_JSON", f"{C.DATASET}.DE_WEEKLY_PLAN", path],
        capture_output=True, text=True)
    if out.returncode: raise SystemExit(out.stderr)
    print(f"loaded {len(rows)} DERIVED plan rows from {from_week}")
```

- [ ] **Step 2: Write `run.py`** — pull profile + gaps + probe + per-product budget (bootstrap if missing) + product net trend; for each of HORIZON_WEEKS weeks build the active cells, allocate, assign purpose/metric/expected, write.
```python
"""Build the rolling weekly plan: budget -> allocate -> purpose -> expected -> load. Coacher D."""
import io, subprocess, datetime as dt
import pandas as pd
from . import config as C
from .compute import assign_purpose, expected_value, SUCCESS_METRIC, allocate_budget
from .load import load_plan

def _q(sql):
    out = subprocess.run(["bq", f"--project_id={C.PROJECT}", "query", "--use_legacy_sql=false",
                          "--format=csv", "--max_rows=1000000", sql], capture_output=True, text=True)
    if out.returncode: raise SystemExit(out.stderr)
    return pd.read_csv(io.StringIO(out.stdout)) if out.stdout.strip() else pd.DataFrame()

def _monday(d): return d - dt.timedelta(days=d.weekday())

def run():
    today = dt.date.today()
    cur = _monday(today)
    weeks = [cur + dt.timedelta(weeks=i) for i in range(C.HORIZON_WEEKS)]
    profile = _q("SELECT parent_name, season, match_type, intent_class, confidence, "
                 "net_per_dollar, cpc_target, source FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`")
    gaps = _q("SELECT DISTINCT parent_name, season, match_type, intent_class FROM "
              "`onyga-482313.OI.V_STRATEGY_GAPS`")
    gapset = {(r.parent_name, r.season, r.match_type, r.intent_class) for r in gaps.itertuples()}
    # relevant peak windows per product (per-product peak, #4) → each week's season
    peakw = _q("SELECT r.family, h.boost_start, h.cooldown_start FROM `onyga-482313.OI.V_PEAK_RELEVANCE` r "
               "JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h ON h.holiday_name=r.holiday_name WHERE r.is_relevant_peak")
    def week_season(parent, wk):
        we = wk + dt.timedelta(days=6)
        for row in peakw.itertuples():
            if row.family == parent and not (we < pd.to_datetime(row.boost_start).date()
                                             or wk > pd.to_datetime(row.cooldown_start).date()):
                return 'PEAK'
        return 'OFF'
    # per-product trailing net trend + bootstrap spend (8w), and any existing budgets
    trend = _q(f"SELECT parent_name, ROUND(AVG(wk_net),2) net_trend, ROUND(AVG(wk_spend),2) boot_spend FROM ("
               f"  SELECT parent_name, week_start, SUM(net_profit) wk_net, SUM(spend) wk_spend "
               f"  FROM `onyga-482313.OI.V_WEEKLY_CELL_NET` "
               f"  WHERE week_start >= DATE_SUB(CURRENT_DATE(), INTERVAL {C.TREND_WEEKS} WEEK) "
               f"  GROUP BY 1,2) GROUP BY 1")
    budgets = _q("SELECT parent_name, weekly_budget FROM `onyga-482313.OI.DE_PRODUCT_BUDGET` "
                 "WHERE source IN ('MANUAL','BUSINESS_PLAN') QUALIFY ROW_NUMBER() OVER "
                 "(PARTITION BY parent_name ORDER BY week_start DESC)=1")
    bud = {r.parent_name: r.weekly_budget for r in budgets.itertuples()}
    boot = {r.parent_name: r.boot_spend for r in trend.itertuples()}
    nettr = {r.parent_name: r.net_trend for r in trend.itertuples()}
    out_rows = []
    for wk in weeks:
        horizon = "CURRENT" if wk == cur else "FUTURE"
        for parent, pcells in profile.groupby("parent_name"):
            # active cells = the product's cells for THIS week's season only (per-product peak)
            wk_season = week_season(parent, wk)
            cells = pcells[pcells["season"] == wk_season].copy()
            if cells.empty:
                continue
            cells["is_gap"] = [ (r.parent_name, r.season, r.match_type, r.intent_class) in gapset
                                for r in cells.itertuples() ]
            cells["is_brand"] = cells["intent_class"].eq("BRAND")
            cells["is_bleeder"] = cells["net_per_dollar"].fillna(0) < 0
            cells["probe_active"] = False
            cells["purpose"] = [assign_purpose(r._asdict()) for r in cells.itertuples()]
            peak = wk_season == "PEAK"
            wb = bud.get(parent) or boot.get(parent) or 0.0
            cells = allocate_budget(cells, weekly_budget=float(wb), peak=peak)
            for r in cells.itertuples():
                p = r.purpose
                out_rows.append(dict(
                    week_start=wk.isoformat(), horizon=horizon, parent_name=parent,
                    season=r.season, match_type=r.match_type, intent_class=r.intent_class,
                    purpose=p, objective=f"{p} {parent} {r.match_type} {r.intent_class}",
                    success_metric=SUCCESS_METRIC[p],
                    expected_value=expected_value(p, r._asdict(), r.planned_spend),
                    target_cpc=(r.cpc_target if p == "SCALE" else None),
                    planned_spend=r.planned_spend, spend_mode=r.spend_mode,
                    expected_net_profit=nettr.get(parent), plan_net_profit=None,
                    coach_mode_hint=("BLITZ" if peak else "GUARDIAN"),
                    status="PROPOSED", actual_value=None, source="DERIVED"))
    df = pd.DataFrame(out_rows)
    # bootstrap any missing budgets into DE_PRODUCT_BUDGET for visibility
    _seed_bootstrap_budgets(cur, set(profile.parent_name) - set(bud), boot)
    load_plan(df, from_week=cur.isoformat())
    print(f"weekly plan rows={len(df)} weeks={[w.isoformat() for w in weeks]}")

def _seed_bootstrap_budgets(week, parents, boot):
    if not parents: return
    vals = ",".join(
        f"('{p}', DATE('{week.isoformat()}'), {float(boot.get(p) or 0)}, 'BOOTSTRAP', CURRENT_TIMESTAMP(), 'weekly_plan_tool')"
        for p in parents)
    subprocess.run(["bq", f"--project_id={C.PROJECT}", "query", "--use_legacy_sql=false",
        f"DELETE FROM `{C.PROJECT}.{C.DATASET}.DE_PRODUCT_BUDGET` WHERE source='BOOTSTRAP' "
        f"AND week_start=DATE('{week.isoformat()}'); "
        f"INSERT INTO `{C.PROJECT}.{C.DATASET}.DE_PRODUCT_BUDGET` "
        f"(parent_name, week_start, weekly_budget, source, updated_at, updated_by) VALUES {vals}"],
        capture_output=True, text=True)

if __name__ == "__main__":
    run()
```

- [ ] **Step 3: Run it live**
Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m tools.weekly_plan.run`
Expected: prints `weekly plan rows=… weeks=[…4 mondays…]` with no error.

- [ ] **Step 4: Validate the plan landed**
```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT horizon, purpose, spend_mode, COUNT(*) n, ROUND(SUM(planned_spend),0) spend
FROM `onyga-482313.OI.DE_WEEKLY_PLAN` GROUP BY 1,2,3 ORDER BY 1,2'
```
Expected: 4 weeks (1 CURRENT + 3 FUTURE) × parents × cells; every row has a `purpose` + `success_metric`; SCALE rows have `spend_mode=SCALE`, MAP/PROBE/CUT `CAP`; per product, sum of CAP `planned_spend` ≤ 10% of its budget. And `DE_PRODUCT_BUDGET` has BOOTSTRAP rows for products without a manual budget.

- [ ] **Step 5: Commit** (`feat(coacher): weekly_plan run.py — build+load rolling plan with bootstrap budget (D)`).

---

### Task 6: `V_WEEKLY_PLAN_REVIEW` (measure last week per purpose)

**Files:** Create `scripts/bigquery/views/V_WEEKLY_PLAN_REVIEW.sql`; Modify `config.yaml`

- [ ] **Step 1: Write the view** — last completed week's plan rows joined to actuals; status per purpose's metric.
```sql
-- V_WEEKLY_PLAN_REVIEW — actual vs expected per plan item for the last completed week. Coacher D.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_PLAN_REVIEW` AS
WITH tol AS (
  SELECT COALESCE(MAX(IF(threshold_key='WEEKLY_PLAN_ON_PLAN_TOL', threshold_value, NULL)), 0.90) AS on_plan_tol
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
),
last_wk AS (SELECT DATE_TRUNC(DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY), WEEK(MONDAY)) AS wk),
plan AS (
  SELECT * FROM `onyga-482313.OI.DE_WEEKLY_PLAN`
  WHERE week_start = (SELECT wk FROM last_wk)
),
actual AS (
  SELECT parent_name, season, match_type, intent_class, net_profit AS actual_net, spend AS actual_spend
  FROM `onyga-482313.OI.V_WEEKLY_CELL_NET`
  WHERE week_start = (SELECT wk FROM last_wk)
)
SELECT
  p.week_start, p.parent_name, p.season, p.match_type, p.intent_class, p.purpose, p.success_metric,
  p.expected_value, p.expected_net_profit, p.plan_net_profit, p.spend_mode, p.planned_spend,
  a.actual_net, a.actual_spend,
  CASE p.success_metric
    WHEN 'NET_PROFIT' THEN
      IF(COALESCE(a.actual_net,0) >= (SELECT on_plan_tol FROM tol) * COALESCE(p.expected_value,0), 'ON_PLAN', 'OFF_PLAN')
    WHEN 'SPEND_DOWN' THEN IF(COALESCE(a.actual_spend,1e9) <= COALESCE(p.planned_spend,0), 'ON_PLAN', 'OFF_PLAN')
    ELSE 'PENDING' END AS status,   -- CLICKS/TOS_SHARE/HOLD resolved in V_PLAN_LEARNINGS / probe log
  -- budget adherence: only CAP cells can OVERSPEND
  IF(p.spend_mode='CAP' AND COALESCE(a.actual_spend,0) > COALESCE(p.planned_spend,0), TRUE, FALSE) AS overspend,
  IF(p.success_metric='NET_PROFIT' AND p.plan_net_profit IS NOT NULL
     AND COALESCE(a.actual_net,0) < p.plan_net_profit, 'BELOW_TARGET', NULL) AS vs_business_plan
FROM plan p
LEFT JOIN actual a USING (parent_name, season, match_type, intent_class)
```

- [ ] **Step 2: Deploy + validate**
```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT purpose, status, COUNT(*) n, COUNTIF(overspend) overspends
FROM `onyga-482313.OI.V_WEEKLY_PLAN_REVIEW` GROUP BY 1,2 ORDER BY 1,2'
```
Expected: rows only when a plan exists for last week (may be empty on the very first run — acceptable; rerun after a week exists, or backfill a test week). SCALE rows resolve ON_PLAN/OFF_PLAN by net; `overspend` only ever TRUE for `spend_mode=CAP`.

- [ ] **Step 3: Write `SP_REVIEW_WEEKLY_PLAN` (write status back so learnings accumulate)**

Create `scripts/bigquery/procedures/SP_REVIEW_WEEKLY_PLAN.sql`. The review view computes status; this persists it onto `DE_WEEKLY_PLAN` for the last completed week so `V_PLAN_LEARNINGS` can aggregate it. Idempotent. (All logic stays in SQL.)
```sql
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REVIEW_WEEKLY_PLAN`()
BEGIN
  UPDATE `onyga-482313.OI.DE_WEEKLY_PLAN` p
  SET status = r.status,
      actual_value = CASE p.success_metric WHEN 'NET_PROFIT' THEN r.actual_net
                                            WHEN 'SPEND_DOWN' THEN r.actual_spend ELSE p.actual_value END,
      updated_at = CURRENT_TIMESTAMP()
  FROM `onyga-482313.OI.V_WEEKLY_PLAN_REVIEW` r
  WHERE p.week_start = r.week_start AND p.parent_name = r.parent_name
    AND p.season = r.season AND p.match_type = r.match_type AND p.intent_class = r.intent_class
    AND r.status IN ('ON_PLAN','OFF_PLAN');
END;
```
Run it (stdin), then `CALL`:
```bash
bq query --use_legacy_sql=false < /Users/ori/Develop/OI/scripts/bigquery/procedures/SP_REVIEW_WEEKLY_PLAN.sql
bq query --use_legacy_sql=false 'CALL `onyga-482313.OI.SP_REVIEW_WEEKLY_PLAN`()'
```
Expected: created + runs clean (0 rows updated today — no completed plan week yet; that's fine). Register in config.yaml. This SP + `run.py` are the weekly cadence: review last week → write back → generate current+future.

- [ ] **Step 4: Register in config.yaml + commit** (`feat(coacher): V_WEEKLY_PLAN_REVIEW + SP_REVIEW_WEEKLY_PLAN — measure + write back (D)`).

---

### Task 7: `V_PLAN_LEARNINGS` (track record per cell × purpose)

**Files:** Create `scripts/bigquery/views/V_PLAN_LEARNINGS.sql`; Modify `config.yaml`

- [ ] **Step 1: Write the view** — aggregate completed plan weeks (status written back) per cell×purpose into a verdict.
```sql
-- V_PLAN_LEARNINGS — what works per cell x purpose across completed weeks. Coacher D.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PLAN_LEARNINGS` AS
SELECT
  parent_name, season, match_type, intent_class, purpose,
  COUNT(*) AS attempts,
  COUNTIF(status IN ('ON_PLAN','MET')) AS wins,
  ROUND(SAFE_DIVIDE(COUNTIF(status IN ('ON_PLAN','MET')), COUNT(*)), 2) AS win_rate,
  ROUND(AVG(actual_value), 2) AS avg_actual,
  CASE
    WHEN COUNT(*) < 3 THEN 'INCONCLUSIVE'
    WHEN SAFE_DIVIDE(COUNTIF(status IN ('ON_PLAN','MET')), COUNT(*)) >= 0.6 THEN 'WORKS'
    ELSE 'DOESNT' END AS verdict
FROM `onyga-482313.OI.DE_WEEKLY_PLAN`
WHERE horizon = 'CURRENT' AND status IN ('ON_PLAN','OFF_PLAN','MET','MISSED')
GROUP BY 1,2,3,4,5
```

- [ ] **Step 2: Deploy + validate**
```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT verdict, COUNT(*) n FROM `onyga-482313.OI.V_PLAN_LEARNINGS` GROUP BY 1'
```
Expected: deploys; likely empty / all `INCONCLUSIVE` today (no completed reviewed weeks yet) — correct cold-start behavior. **v1 limitation:** the generator does **not** yet consume `V_PLAN_LEARNINGS` to re-assign purposes/recalibrate (it derives from profile + gaps only); that feedback edge is inert until weeks accumulate and is wired in **v1.1**. The data path (review → write-back → learnings) is built so the corpus starts accumulating now.

- [ ] **Step 3: Register + commit** (`feat(coacher): V_PLAN_LEARNINGS — cell x purpose track record (D)`).

---

### Task 8: `V_WEEKLY_PLAN_ACTIONS` (current-week coach actions + expected result)

**Files:** Create `scripts/bigquery/views/V_WEEKLY_PLAN_ACTIONS.sql`; Modify `config.yaml`

- [ ] **Step 1: Write the view** — current-week `V_ADS_COACH` actionable rows joined to their cell's plan item, with a purpose-derived `expected_result`.
```sql
-- V_WEEKLY_PLAN_ACTIONS — current-week coach actions grouped under each cell's plan item. Coacher D.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_PLAN_ACTIONS` AS
WITH cur AS (SELECT DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), WEEK(MONDAY)) AS wk),
plan AS (
  SELECT parent_name, season, match_type, intent_class, purpose, success_metric, expected_value, target_cpc
  FROM `onyga-482313.OI.DE_WEEKLY_PLAN`
  WHERE horizon='CURRENT' AND week_start=(SELECT wk FROM cur)
)
SELECT
  c.parent_name, c.season, c.match_type, c.intent_class,
  pl.purpose, c.keyword_id, c.target_action, c.current_bid, c.recommended_bid, c.bid_change_pct,
  pl.target_cpc,
  CASE pl.purpose
    WHEN 'SCALE'  THEN 'grow at target CPC — more volume at held ROAS'
    WHEN 'MAP'    THEN 'reach 15 clicks to decide'
    WHEN 'PROBE'  THEN 'reach 15 clicks to decide'
    WHEN 'DEFEND' THEN 'hold top-of-search position'
    WHEN 'CUT'    THEN 'cut wasted spend'
    WHEN 'HOLD'   THEN 'maintain — no churn'
    ELSE 'monitor' END AS expected_result
FROM `onyga-482313.OI.V_ADS_COACH` c
JOIN plan pl USING (parent_name, season, match_type, intent_class)
WHERE c.target_action IS NOT NULL AND c.target_action NOT IN ('MONITOR_TARGET','KEEP_TARGET')
```

- [ ] **Step 2: Deploy + validate**
```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT purpose, target_action, COUNT(*) n
FROM `onyga-482313.OI.V_WEEKLY_PLAN_ACTIONS` GROUP BY 1,2 ORDER BY 1,2 LIMIT 20'
```
Expected: current-week coach actions appear under their cell's purpose, each with a non-null `expected_result`. (If empty, confirm the current week's plan rows exist and `V_ADS_COACH` exposes season/match_type — both built in C.)

- [ ] **Step 3: Register + commit** (`feat(coacher): V_WEEKLY_PLAN_ACTIONS — actions + expected results under the plan (D)`).

---

### Task FINAL: Holistic validation + memory

- [ ] **Step 1: End-to-end coherence**
```bash
bq query --use_legacy_sql=false --format=pretty '
SELECT
  (SELECT COUNT(*) FROM `onyga-482313.OI.DE_WEEKLY_PLAN`) plan_rows,
  (SELECT COUNT(DISTINCT week_start) FROM `onyga-482313.OI.DE_WEEKLY_PLAN`) weeks,
  (SELECT COUNT(*) FROM `onyga-482313.OI.DE_PRODUCT_BUDGET`) budgets,
  (SELECT COUNTIF(spend_mode="CAP") FROM `onyga-482313.OI.DE_WEEKLY_PLAN`) cap_cells,
  (SELECT COUNTIF(spend_mode="SCALE") FROM `onyga-482313.OI.DE_WEEKLY_PLAN`) scale_cells'
```
Expected: `weeks=4`; budgets ≥ 1 per advertised product; cap+scale cells cover the plan; no NULL `purpose`.

- [ ] **Step 2: Re-run idempotency** — run `python -m tools.weekly_plan.run` twice; `DE_WEEKLY_PLAN` row count for current+future weeks is stable (DELETE+INSERT), past weeks untouched, any MANUAL row preserved.

- [ ] **Step 3: Update memory** — create `/Users/ori/.claude/projects/-Users-ori-Develop/memory/project_coacher_weekly_plan.md` (type project): the budget-first purpose-driven learning loop, the 2 tables + 4 views + generator, backend-only v1 (surface=v1.1), the per-product-peak + SCALE-uncapped/CAP rules, and deferrals (E adjust/escalate, F execution, business-plan net reconciliation is a stub). Add a one-line `MEMORY.md` index entry.
