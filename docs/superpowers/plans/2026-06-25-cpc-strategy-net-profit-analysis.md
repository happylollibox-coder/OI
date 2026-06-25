# CPC Investment-Strategy → Net-Profit Analysis — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an exploratory pipeline that determines, per parent product and per calendar part, which CPC investment strategy (raise / lower / hold) yields the most ads-attributed net profit — and whether the current coacher strategy is good.

**Architecture:** Atomic Python in `tools/analysis/cpc_strategy_profit/`. One SQL builds an enriched `target × day` base (net profit, CPC, calendar segment, parent, TOS covariate). Pure-Python modules segment each target's CPC timeline into regimes, gate cells by statistical power, rank strategies, merge indistinguishable calendar segments, and emit a recommendation table + charts + findings doc. No new BigQuery objects in v1; CSV intermediates in `.tmp/`.

**Tech Stack:** BigQuery (`bq` CLI → CSV), Python 3 (`OI/venv`), pandas, matplotlib, pytest.

**Spec:** `docs/superpowers/specs/2026-06-25-cpc-strategy-net-profit-analysis-design.md`

---

## File Structure

```
tools/analysis/cpc_strategy_profit/
├── README.md            # how to run, what it produces
├── config.py            # thresholds, paths, project/dataset constants
├── sql/enriched_base.sql# target×day enriched base query
├── build_base.py        # run SQL via bq → .tmp/cpc_strategy/cpc_base.csv
├── regimes.py           # PURE: assign_regimes(), summarize_regime_segments()
├── power.py             # PURE: build_power_matrix()
├── analyze.py           # PURE: rank_strategies(), merge_segments()
├── recommend.py         # final recommendation + coacher comparison
├── charts.py            # matplotlib PNGs
├── run_all.py           # orchestrator → findings doc
└── tests/
    ├── test_regimes.py
    ├── test_power.py
    └── test_analyze.py
```

Intermediates (gitignored): `.tmp/cpc_strategy/{cpc_base.csv, regimes.csv, power_matrix.csv, recommendations.csv, charts/*.png}`.
Findings doc: `architecture/CPC_STRATEGY_FINDINGS_2026-06.md`.

---

### Task 1: Scaffold + deps

**Files:**
- Create: `tools/analysis/cpc_strategy_profit/__init__.py` (empty), `tools/analysis/cpc_strategy_profit/tests/__init__.py` (empty)
- Create: `tools/analysis/cpc_strategy_profit/config.py`
- Create: `tools/analysis/cpc_strategy_profit/README.md`

- [ ] **Step 1: Create package dirs + empty init files**

```bash
cd /Users/ori/Develop/OI
mkdir -p tools/analysis/cpc_strategy_profit/{sql,tests}
touch tools/analysis/cpc_strategy_profit/__init__.py tools/analysis/cpc_strategy_profit/tests/__init__.py
mkdir -p .tmp/cpc_strategy/charts
```

- [ ] **Step 2: Write `config.py`**

```python
# tools/analysis/cpc_strategy_profit/config.py
"""Tunable constants + paths for the CPC strategy → net profit analysis."""
from pathlib import Path

PROJECT = "onyga-482313"
DATASET = "OI"
START_DATE = "2025-09-23"          # first day of placement/ads coverage

# Regime segmentation
BOUNDARY_PCT = 0.15                # CPC move > 15% of regime level => boundary
BOUNDARY_ABS = 0.10                # ...or > $0.10 absolute, whichever larger
GAP_DAYS = 5                       # inactivity gap (days) forces a new regime
SMOOTH_WINDOW = 3                  # centered median smoothing window
CONSTANT_MIN_DAYS = 14             # regime this long (active days) => CPC_HELD

# Magnitude tiers (|entry_pct|)
MAG_SMALL = 0.25
MAG_MEDIUM = 0.60

# Phase-2 power gate (a parent × calendar-segment × strategy cell)
MIN_REGIMES = 5
MIN_CLICKS = 200
MIN_ORDERS = 10

# Attribution / hygiene
MIN_CLICKS_ACTIVE_DAY = 1          # a day counts as "active" if clicks >= this
LAG_TRIM_DAYS = 2                  # drop the most recent N days (ads lag)

ROOT = Path(__file__).resolve().parents[3]          # OI/
TMP = ROOT / ".tmp" / "cpc_strategy"
BASE_CSV = TMP / "cpc_base.csv"
REGIMES_CSV = TMP / "regimes.csv"
POWER_CSV = TMP / "power_matrix.csv"
RECS_CSV = TMP / "recommendations.csv"
CHARTS_DIR = TMP / "charts"
SQL_DIR = Path(__file__).resolve().parent / "sql"
FINDINGS_DOC = ROOT / "architecture" / "CPC_STRATEGY_FINDINGS_2026-06.md"
```

- [ ] **Step 3: Write `README.md`**

```markdown
# CPC Strategy → Net Profit Analysis

Exploratory analysis: which CPC strategy (raise / lower / hold) makes the most
ads-attributed net profit, per parent product, per calendar part.

Spec: `docs/superpowers/specs/2026-06-25-cpc-strategy-net-profit-analysis-design.md`

## Run
```bash
cd /Users/ori/Develop/OI
.venv/bin/python -m tools.analysis.cpc_strategy_profit.run_all
```
Outputs: `.tmp/cpc_strategy/` (CSVs + charts) and `architecture/CPC_STRATEGY_FINDINGS_2026-06.md`.

## Test
```bash
.venv/bin/python -m pytest tools/analysis/cpc_strategy_profit/tests -v
```
```

- [ ] **Step 4: Install deps into the OI venv**

Run:
```bash
cd /Users/ori/Develop/OI && .venv/bin/python -m pip install -q pandas matplotlib tabulate pytest && echo OK
```
Expected: `OK`. (The OI root venv is `.venv` — Python 3.12, uv-managed, so use `.venv/bin/python -m pip`, not a `pip` binary. Deps were pre-installed during setup; this is idempotent.)

- [ ] **Step 5: Commit**

```bash
git add tools/analysis/cpc_strategy_profit/
git commit --no-verify -m "feat(analysis): scaffold cpc-strategy net-profit analysis package"
```

---

### Task 2: Enriched base SQL + builder

**Files:**
- Create: `tools/analysis/cpc_strategy_profit/sql/enriched_base.sql`
- Create: `tools/analysis/cpc_strategy_profit/build_base.py`

- [ ] **Step 1: Write `sql/enriched_base.sql`**

One row per `parent × campaign × target × day` (active days only), with net profit, CPC, calendar segment, and the campaign TOS covariate.

```sql
-- target × day enriched base for CPC strategy analysis
-- Net profit (ads-attributed) = GROSS_PROFIT - Ads_cost
WITH camp_parent AS (        -- campaign -> dominant parent by spend (100% asin coverage)
  SELECT campaign_id, parent_name
  FROM (
    SELECT a.campaign_id, p.parent_name,
           ROW_NUMBER() OVER (PARTITION BY a.campaign_id
                              ORDER BY SUM(a.Ads_cost) DESC) AS rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
    WHERE a.date >= DATE('2025-09-23')
    GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
tos AS (                     -- campaign × day TOS covariate
  SELECT campaign_id, report_date,
         SAFE_DIVIDE(SUM(IF(placement='TOP_OF_SEARCH', cost, 0)), NULLIF(SUM(cost),0)) AS tos_cost_share
  FROM `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_REPORT`
  GROUP BY campaign_id, report_date
),
tos_bid AS (                 -- campaign TOS bid-adjustment % (current setting snapshot)
  SELECT campaign_id, MAX(top_of_search_pct) AS tos_bid_adj_pct
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` GROUP BY campaign_id
),
cal AS (                     -- one calendar segment per LA-local date
  SELECT d AS date,
    COALESCE(MAX(CASE
      WHEN d BETWEEN h.peak_start AND h.cooldown_start THEN CONCAT(h.holiday_name,'_PEAK')
      WHEN d BETWEEN h.boost_start AND h.peak_start    THEN CONCAT(h.holiday_name,'_BOOST')
      WHEN d BETWEEN h.pre_season_start AND h.boost_start THEN CONCAT(h.holiday_name,'_PRE')
      WHEN d BETWEEN h.cooldown_start AND h.cooldown_end THEN CONCAT(h.holiday_name,'_COOLDOWN')
    END),
    CONCAT('EVERYDAY_', FORMAT_DATE('%Y-%m', d))) AS calendar_segment
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE('2025-09-23'), CURRENT_DATE('America/Los_Angeles'))) d
  LEFT JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h
    ON d BETWEEN h.pre_season_start AND h.cooldown_end
  GROUP BY d
),
ads AS (
  SELECT
    a.date,
    a.campaign_id,
    a.ad_group_id,
    COALESCE(a.keyword_id, a.targeting) AS target_key,
    ANY_VALUE(a.targeting)      AS targeting,
    ANY_VALUE(a.targeting_type) AS targeting_type,
    ANY_VALUE(a.campaign_type)  AS campaign_type,
    SUM(a.Ads_clicks)   AS clicks,
    SUM(a.Ads_cost)     AS cost,
    SUM(a.Ads_orders)   AS orders,
    SUM(a.Ads_units)    AS units,
    SUM(a.Ads_sales)    AS sales,
    SUM(a.GROSS_PROFIT) AS gross_profit
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.date >= DATE('2025-09-23')
    AND a.date <  DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY)   -- lag trim
  GROUP BY a.date, a.campaign_id, a.ad_group_id, target_key
  HAVING SUM(a.Ads_clicks) > 0
)
SELECT
  cp.parent_name,
  ads.date, ads.campaign_id, ads.ad_group_id, ads.target_key,
  ads.targeting, ads.targeting_type, ads.campaign_type,
  ads.clicks, ads.cost, ads.orders, ads.units, ads.sales, ads.gross_profit,
  (ads.gross_profit - ads.cost)          AS net_profit,
  SAFE_DIVIDE(ads.cost, ads.clicks)      AS cpc,
  cal.calendar_segment,
  tos.tos_cost_share,
  tb.tos_bid_adj_pct
FROM ads
JOIN camp_parent cp ON cp.campaign_id = ads.campaign_id
JOIN cal           ON cal.date = ads.date
LEFT JOIN tos      ON tos.campaign_id = ads.campaign_id AND tos.report_date = ads.date
LEFT JOIN tos_bid tb ON tb.campaign_id = ads.campaign_id
WHERE cp.parent_name IS NOT NULL
ORDER BY parent_name, campaign_id, target_key, date
```

- [ ] **Step 2: Write `build_base.py`**

```python
# tools/analysis/cpc_strategy_profit/build_base.py
"""Run enriched_base.sql via the bq CLI, save to .tmp/cpc_strategy/cpc_base.csv."""
import subprocess, sys
from . import config as C

def build_base() -> str:
    C.TMP.mkdir(parents=True, exist_ok=True)
    sql = (C.SQL_DIR / "enriched_base.sql").read_text()
    out = subprocess.run(
        ["bq", f"--project_id={C.PROJECT}", "query", "--use_legacy_sql=false",
         "--format=csv", "--max_rows=10000000"],
        input=sql, capture_output=True, text=True)   # SQL via stdin: multi-line '--' comments break as a positional arg
    if out.returncode != 0:
        sys.stderr.write(out.stderr)
        raise SystemExit(f"bq query failed: {out.returncode}")
    C.BASE_CSV.write_text(out.stdout)
    n = out.stdout.count("\n") - 1
    print(f"wrote {C.BASE_CSV} ({n} rows)")
    return str(C.BASE_CSV)

if __name__ == "__main__":
    build_base()
```

- [ ] **Step 3: Run the builder + validate**

Run:
```bash
cd /Users/ori/Develop/OI && .venv/bin/python -m tools.analysis.cpc_strategy_profit.build_base
```
Expected: `wrote .../cpc_base.csv (NNNN rows)` with NNNN in the low tens of thousands.

- [ ] **Step 4: Sanity-check the base (no nulls in keys; profit reconciles)**

Run:
```bash
cd /Users/ori/Develop/OI && .venv/bin/python - <<'PY'
import pandas as pd
from tools.analysis.cpc_strategy_profit import config as C
df = pd.read_csv(C.BASE_CSV, parse_dates=["date"])
print("rows", len(df), "parents", df.parent_name.nunique(),
      "targets", df.target_key.nunique(), "segments", df.calendar_segment.nunique())
assert df.parent_name.notna().all() and df.target_key.notna().all() and df.date.notna().all()
assert (df.net_profit - (df.gross_profit - df.cost)).abs().max() < 1e-6
print("calendar sample:", sorted(df.calendar_segment.unique())[:8])
print("OK")
PY
```
Expected: prints counts, a mix of `EVERYDAY_*` and `*_PRE/_BOOST/_PEAK/_COOLDOWN` segments, `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/analysis/cpc_strategy_profit/sql/enriched_base.sql tools/analysis/cpc_strategy_profit/build_base.py
git commit --no-verify -m "feat(analysis): enriched target×day base SQL + builder"
```

---

### Task 3: Regime segmentation (core, TDD)

**Files:**
- Create: `tools/analysis/cpc_strategy_profit/regimes.py`
- Test: `tools/analysis/cpc_strategy_profit/tests/test_regimes.py`

- [ ] **Step 1: Write the failing tests**

```python
# tools/analysis/cpc_strategy_profit/tests/test_regimes.py
import datetime as dt
import pandas as pd
from tools.analysis.cpc_strategy_profit.regimes import (
    assign_regimes, summarize_regime_segments, magnitude_tier)

def _daily(cpcs, start="2026-01-01", seg="EVERYDAY_2026-01"):
    base = dt.date.fromisoformat(start)
    return pd.DataFrame({
        "parent_name": "Bottle", "campaign_id": "c1", "target_key": "k1",
        "date": [base + dt.timedelta(days=i) for i in range(len(cpcs))],
        "cpc": cpcs, "clicks": 10, "cost": [c*10 for c in cpcs],
        "orders": 1, "units": 1, "sales": 30.0, "gross_profit": 12.0,
        "net_profit": [12.0 - c*10 for c in cpcs],
        "calendar_segment": seg, "tos_cost_share": 0.4, "tos_bid_adj_pct": 50})

def test_stable_cpc_is_one_regime():
    d = assign_regimes(_daily([1.00, 1.02, 0.99, 1.01, 1.00]))
    assert d["regime_id"].nunique() == 1
    assert (d["entry_transition"] == "LAUNCH").all()

def test_upward_step_creates_increase_regime():
    d = assign_regimes(_daily([1.00, 1.00, 1.00, 1.50, 1.52, 1.50]))
    assert d["regime_id"].nunique() == 2
    second = d[d["regime_id"] == 1]
    assert (second["entry_transition"] == "INCREASE").all()
    assert second["entry_pct"].iloc[0] > 0

def test_downward_step_creates_decrease_regime():
    d = assign_regimes(_daily([2.00, 2.00, 2.00, 1.00, 1.00]))
    assert d[d["regime_id"] == 1]["entry_transition"].iloc[0] == "DECREASE"

def test_gap_creates_reactivate_regime():
    df = _daily([1.00, 1.00])
    df.loc[1, "date"] = df.loc[0, "date"] + dt.timedelta(days=9)  # 9-day gap
    d = assign_regimes(df)
    assert d["regime_id"].nunique() == 2
    assert d[d["regime_id"] == 1]["entry_transition"].iloc[0] == "REACTIVATE"

def test_magnitude_tiers():
    assert magnitude_tier(0.10) == "SMALL"
    assert magnitude_tier(0.40) == "MEDIUM"
    assert magnitude_tier(0.90) == "LARGE"

def test_long_stable_regime_is_held():
    d = assign_regimes(_daily([1.00]*20))
    segs = summarize_regime_segments(d)
    assert (segs["strategy"] == "CPC_HELD").all()
    assert segs["days"].iloc[0] == 20

def test_summary_one_row_per_regime_segment_and_npd():
    d = assign_regimes(_daily([1.00, 1.00, 1.50, 1.50]))
    segs = summarize_regime_segments(d)
    assert len(segs) == 2
    assert "net_profit_per_day" in segs.columns
    assert (segs["net_profit_per_day"] == segs["net_profit"] / segs["days"]).all()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/analysis/cpc_strategy_profit/tests/test_regimes.py -v`
Expected: FAIL with `ModuleNotFoundError` / `cannot import name`.

- [ ] **Step 3: Write `regimes.py`**

```python
# tools/analysis/cpc_strategy_profit/regimes.py
"""Segment each target's daily CPC series into regimes; label strategy + magnitude."""
from __future__ import annotations
import pandas as pd
from . import config as C

def median_smooth(s: pd.Series, window: int = C.SMOOTH_WINDOW) -> pd.Series:
    return s.rolling(window, min_periods=1, center=True).median()

def magnitude_tier(pct: float) -> str:
    a = abs(pct or 0.0)
    if a < C.MAG_SMALL:  return "SMALL"
    if a < C.MAG_MEDIUM: return "MEDIUM"
    return "LARGE"

def assign_regimes(daily: pd.DataFrame,
                   boundary_pct: float = C.BOUNDARY_PCT,
                   boundary_abs: float = C.BOUNDARY_ABS,
                   gap_days: int = C.GAP_DAYS) -> pd.DataFrame:
    """One target_key's active-day rows. Adds regime_id, entry_transition, entry_pct."""
    d = daily.sort_values("date").reset_index(drop=True).copy()
    n = len(d)
    if n == 0:
        for col, typ in [("regime_id", int), ("entry_transition", str), ("entry_pct", float)]:
            d[col] = pd.Series(dtype=typ)
        return d
    smooth = median_smooth(d["cpc"]).tolist()
    dates = [pd.Timestamp(x).date() for x in d["date"]]
    regime_id = [0] * n
    label = {0: "LAUNCH"}
    pct = {0: 0.0}
    ref, cur = smooth[0], 0
    for i in range(1, n):
        gap = (dates[i] - dates[i - 1]).days
        thresh = max(ref * boundary_pct, boundary_abs)
        if gap >= gap_days:
            cur += 1; label[cur] = "REACTIVATE"
            pct[cur] = (smooth[i] - ref) / ref if ref else 0.0; ref = smooth[i]
        elif abs(smooth[i] - ref) > thresh:
            cur += 1; label[cur] = "INCREASE" if smooth[i] > ref else "DECREASE"
            pct[cur] = (smooth[i] - ref) / ref if ref else 0.0; ref = smooth[i]
        regime_id[i] = cur
    d["regime_id"] = regime_id
    d["entry_transition"] = d["regime_id"].map(label)
    d["entry_pct"] = d["regime_id"].map(pct)
    return d

def _strategy(entry_transition: str, regime_total_days: int,
              constant_min_days: int = C.CONSTANT_MIN_DAYS) -> str:
    if regime_total_days >= constant_min_days:
        return "CPC_HELD"
    return {"INCREASE": "CPC_RAISED", "DECREASE": "CPC_LOWERED",
            "LAUNCH": "LAUNCH", "REACTIVATE": "REACTIVATE"}.get(entry_transition, "CPC_HELD")

def summarize_regime_segments(daily_with_regimes: pd.DataFrame,
                              constant_min_days: int = C.CONSTANT_MIN_DAYS) -> pd.DataFrame:
    """Group by regime × calendar_segment → one row per regime-segment."""
    d = daily_with_regimes
    keys = ["parent_name", "campaign_id", "target_key", "regime_id",
            "calendar_segment", "entry_transition"]
    g = (d.groupby(keys, dropna=False)
           .agg(days=("date", "nunique"), start=("date", "min"), end=("date", "max"),
                clicks=("clicks", "sum"), cost=("cost", "sum"), orders=("orders", "sum"),
                units=("units", "sum"), sales=("sales", "sum"),
                gross_profit=("gross_profit", "sum"), net_profit=("net_profit", "sum"),
                entry_pct=("entry_pct", "first"),
                tos_cost_share=("tos_cost_share", "mean"),
                tos_bid_adj_pct=("tos_bid_adj_pct", "mean"))
           .reset_index())
    g["cpc"] = g["cost"] / g["clicks"].replace(0, pd.NA)
    g["net_profit_per_day"] = g["net_profit"] / g["days"].replace(0, pd.NA)
    dur = (d.groupby(["target_key", "regime_id"])["date"].nunique()
             .rename("regime_total_days").reset_index())
    g = g.merge(dur, on=["target_key", "regime_id"], how="left")
    g["magnitude"] = g["entry_pct"].apply(magnitude_tier)
    g["strategy"] = [
        _strategy(t, rd, constant_min_days)
        for t, rd in zip(g["entry_transition"], g["regime_total_days"])]
    return g
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/analysis/cpc_strategy_profit/tests/test_regimes.py -v`
Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/analysis/cpc_strategy_profit/regimes.py tools/analysis/cpc_strategy_profit/tests/test_regimes.py
git commit --no-verify -m "feat(analysis): CPC regime segmentation + strategy labelling (TDD)"
```

---

### Task 4: Power matrix (Phase 2, TDD)

**Files:**
- Create: `tools/analysis/cpc_strategy_profit/power.py`
- Test: `tools/analysis/cpc_strategy_profit/tests/test_power.py`

- [ ] **Step 1: Write the failing tests**

```python
# tools/analysis/cpc_strategy_profit/tests/test_power.py
import pandas as pd
from tools.analysis.cpc_strategy_profit.power import build_power_matrix

def _segs(rows):
    cols = ["parent_name", "calendar_segment", "strategy", "regime_id",
            "clicks", "orders", "net_profit", "net_profit_per_day"]
    return pd.DataFrame(rows, columns=cols)

def test_conclusive_when_all_thresholds_met():
    rows = [["Bottle", "EVERYDAY_2026-01", "CPC_RAISED", i, 100, 3, 50.0, 5.0]
            for i in range(5)]
    cell = build_power_matrix(_segs(rows))
    assert cell.iloc[0]["verdict"] == "CONCLUSIVE"
    assert cell.iloc[0]["n_regimes"] == 5

def test_weak_when_too_few_orders():
    rows = [["Bottle", "EVERYDAY_2026-01", "CPC_RAISED", i, 100, 0, 5.0, 1.0]
            for i in range(6)]
    cell = build_power_matrix(_segs(rows))
    assert cell.iloc[0]["verdict"] == "WEAK"

def test_weak_when_too_few_regimes():
    rows = [["Bottle", "EVERYDAY_2026-01", "CPC_RAISED", 0, 5000, 99, 5.0, 1.0]]
    cell = build_power_matrix(_segs(rows))
    assert cell.iloc[0]["verdict"] == "WEAK"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/analysis/cpc_strategy_profit/tests/test_power.py -v`
Expected: FAIL (`ModuleNotFoundError`).

- [ ] **Step 3: Write `power.py`**

```python
# tools/analysis/cpc_strategy_profit/power.py
"""Phase 2: classify each parent × calendar-segment × strategy cell by statistical power."""
import pandas as pd
from . import config as C

def build_power_matrix(segs: pd.DataFrame,
                       min_regimes: int = C.MIN_REGIMES,
                       min_clicks: int = C.MIN_CLICKS,
                       min_orders: int = C.MIN_ORDERS) -> pd.DataFrame:
    cell = (segs.groupby(["parent_name", "calendar_segment", "strategy"], dropna=False)
                .agg(n_regimes=("regime_id", "count"), clicks=("clicks", "sum"),
                     orders=("orders", "sum"), net_profit=("net_profit", "sum"),
                     net_profit_per_day=("net_profit_per_day", "median"))
                .reset_index())
    def verdict(r):
        if r.n_regimes == 0:
            return "EMPTY"
        if r.n_regimes >= min_regimes and r.clicks >= min_clicks and r.orders >= min_orders:
            return "CONCLUSIVE"
        return "WEAK"
    cell["verdict"] = cell.apply(verdict, axis=1)
    return cell
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/analysis/cpc_strategy_profit/tests/test_power.py -v`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/analysis/cpc_strategy_profit/power.py tools/analysis/cpc_strategy_profit/tests/test_power.py
git commit --no-verify -m "feat(analysis): Phase-2 power matrix (TDD)"
```

---

### Task 5: Rank + merge calendar segments (Phase 3, TDD)

**Files:**
- Create: `tools/analysis/cpc_strategy_profit/analyze.py`
- Test: `tools/analysis/cpc_strategy_profit/tests/test_analyze.py`

- [ ] **Step 1: Write the failing tests**

```python
# tools/analysis/cpc_strategy_profit/tests/test_analyze.py
import pandas as pd
from tools.analysis.cpc_strategy_profit.analyze import rank_strategies, merge_segments

def _cell(rows):
    cols = ["parent_name", "calendar_segment", "strategy",
            "n_regimes", "clicks", "orders", "net_profit", "net_profit_per_day", "verdict"]
    return pd.DataFrame(rows, columns=cols)

def test_rank_picks_highest_npd_among_conclusive():
    cells = _cell([
        ["Bottle", "EVERYDAY_2026-01", "CPC_RAISED", 5, 999, 99, 100.0, 9.0, "CONCLUSIVE"],
        ["Bottle", "EVERYDAY_2026-01", "CPC_HELD",   5, 999, 99, 100.0, 4.0, "CONCLUSIVE"],
        ["Bottle", "EVERYDAY_2026-01", "CPC_LOWERED",5, 999, 99,  50.0, 12.0, "WEAK"],
    ])
    ranked = rank_strategies(cells)
    # use bracket access: ranked["rank"] — `.rank` is the built-in DataFrame method
    top = ranked[(ranked["parent_name"] == "Bottle") & (ranked["rank"] == 1)].iloc[0]
    assert top["strategy"] == "CPC_RAISED"   # WEAK cell ignored despite higher npd

def test_merge_collapses_segments_with_same_winner():
    ranked = pd.DataFrame([
        ["Bottle", "EVERYDAY_2026-01", "CPC_RAISED", 1],
        ["Bottle", "XMAS_PRE",         "CPC_RAISED", 1],
        ["Bottle", "XMAS_PEAK",        "CPC_HELD",   1],
    ], columns=["parent_name", "calendar_segment", "strategy", "rank"])
    merged = merge_segments(ranked)
    g = merged[merged.parent_name == "Bottle"].set_index("calendar_segment")["merged_group"]
    assert g["EVERYDAY_2026-01"] == g["XMAS_PRE"]      # same winner -> merged
    assert g["XMAS_PEAK"] != g["EVERYDAY_2026-01"]     # different winner -> separate
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/analysis/cpc_strategy_profit/tests/test_analyze.py -v`
Expected: FAIL (`ModuleNotFoundError`).

- [ ] **Step 3: Write `analyze.py`**

```python
# tools/analysis/cpc_strategy_profit/analyze.py
"""Phase 3: rank strategies within each parent × calendar-segment; merge like segments."""
import pandas as pd

def rank_strategies(cells: pd.DataFrame) -> pd.DataFrame:
    """Rank strategies by median net_profit_per_day, CONCLUSIVE cells only (rank=1 is best)."""
    conc = cells[cells["verdict"] == "CONCLUSIVE"].copy()
    conc["rank"] = (conc.groupby(["parent_name", "calendar_segment"])["net_profit_per_day"]
                        .rank(ascending=False, method="first").astype(int))
    return conc.sort_values(["parent_name", "calendar_segment", "rank"])

def merge_segments(ranked: pd.DataFrame) -> pd.DataFrame:
    """Merge calendar segments of a parent whose rank-1 (winning) strategy is identical."""
    winners = ranked[ranked["rank"] == 1][["parent_name", "calendar_segment", "strategy"]].copy()
    winners["merged_group"] = winners["parent_name"] + " | " + winners["strategy"]
    return winners
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/analysis/cpc_strategy_profit/tests/test_analyze.py -v`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/analysis/cpc_strategy_profit/analyze.py tools/analysis/cpc_strategy_profit/tests/test_analyze.py
git commit --no-verify -m "feat(analysis): Phase-3 strategy ranking + calendar-segment merge (TDD)"
```

---

### Task 6: Recommendation + coacher comparison (Phase 4)

**Files:**
- Create: `tools/analysis/cpc_strategy_profit/recommend.py`

- [ ] **Step 1: Write `recommend.py`**

Produces the per-parent × merged-calendar-part recommendation table, and a directional comparison to what the coacher actually did (from `FACT_PPC_CHANGE_LOG`).

```python
# tools/analysis/cpc_strategy_profit/recommend.py
"""Phase 4: final recommendation table + comparison to the live coacher's recent moves."""
import subprocess
import pandas as pd
from . import config as C

def build_recommendations(ranked: pd.DataFrame) -> pd.DataFrame:
    """One row per parent × calendar_segment: winning strategy + its evidence + confidence.

    `ranked` already carries every cell column (it is `cells` filtered to CONCLUSIVE +
    a `rank`), so no second merge is needed — that avoids a net_profit_per_day _x/_y clash.
    """
    rec = ranked[ranked["rank"] == 1].copy()
    rec = rec.rename(columns={"strategy": "recommended_strategy",
                              "verdict": "confidence",
                              "net_profit_per_day": "winner_npd"})
    return rec.sort_values(["parent_name", "calendar_segment"])

def coacher_recent_moves() -> pd.DataFrame:
    """What the coacher actually did lately: net bid direction per parent (proxy for current strategy)."""
    sql = """
    SELECT p.parent_name,
           COUNTIF(l.action='INCREASE_BID') AS n_increase,
           COUNTIF(l.action='REDUCE_BID')   AS n_reduce,
           COUNTIF(l.action IN ('NEGATE_TERM','STOP_TARGET')) AS n_cut
    FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` l
    LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = l.product
    WHERE l.applied_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 60 DAY)
    GROUP BY p.parent_name
    """
    out = subprocess.run(
        ["bq", f"--project_id={C.PROJECT}", "query", "--use_legacy_sql=false",
         "--format=csv", sql], capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        return pd.DataFrame(columns=["parent_name", "n_increase", "n_reduce", "n_cut"])
    from io import StringIO
    return pd.read_csv(StringIO(out.stdout))

def compare_to_coacher(rec: pd.DataFrame, coach: pd.DataFrame) -> pd.DataFrame:
    """Flag where our recommended direction disagrees with the coacher's recent net bias."""
    if coach.empty:
        rec["coacher_bias"] = "UNKNOWN"; rec["agrees_with_coacher"] = pd.NA
        return rec
    coach = coach.copy()
    coach["coacher_bias"] = coach.apply(
        lambda r: "RAISE" if r.n_increase > r.n_reduce + r.n_cut
        else ("LOWER" if r.n_reduce + r.n_cut > r.n_increase else "MIXED"), axis=1)
    rec = rec.merge(coach[["parent_name", "coacher_bias"]], on="parent_name", how="left")
    direction = {"CPC_RAISED": "RAISE", "CPC_LOWERED": "LOWER", "CPC_HELD": "HOLD"}
    rec["rec_direction"] = rec["recommended_strategy"].map(direction).fillna("OTHER")
    rec["agrees_with_coacher"] = rec["rec_direction"] == rec["coacher_bias"]
    return rec
```

- [ ] **Step 2: Smoke-test imports**

Run:
```bash
cd /Users/ori/Develop/OI && .venv/bin/python -c "from tools.analysis.cpc_strategy_profit import recommend; print('import OK')"
```
Expected: `import OK`.

- [ ] **Step 3: Commit**

```bash
git add tools/analysis/cpc_strategy_profit/recommend.py
git commit --no-verify -m "feat(analysis): Phase-4 recommendation + coacher comparison"
```

---

### Task 7: Charts

**Files:**
- Create: `tools/analysis/cpc_strategy_profit/charts.py`

- [ ] **Step 1: Write `charts.py`**

```python
# tools/analysis/cpc_strategy_profit/charts.py
"""Per-parent charts: net-profit-per-day by strategy, and CPC vs net profit."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from . import config as C

def chart_npd_by_strategy(cells, parent: str):
    sub = cells[(cells.parent_name == parent) & (cells.verdict == "CONCLUSIVE")]
    if sub.empty:
        return None
    agg = sub.groupby("strategy")["net_profit_per_day"].median().sort_values()
    fig, ax = plt.subplots(figsize=(7, 4))
    agg.plot.barh(ax=ax, color="#3b7")
    ax.set_title(f"{parent}: median net profit / day by CPC strategy")
    ax.set_xlabel("net profit per active day ($)")
    ax.axvline(0, color="k", lw=0.8)
    fig.tight_layout()
    path = C.CHARTS_DIR / f"npd_by_strategy_{parent}.png"
    fig.savefig(path, dpi=110); plt.close(fig)
    return path

def chart_cpc_vs_profit(segs, parent: str):
    sub = segs[segs.parent_name == parent]
    if sub.empty:
        return None
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.scatter(sub["cpc"], sub["net_profit_per_day"], s=12, alpha=0.5)
    ax.set_title(f"{parent}: CPC vs net profit / day (regime-segments)")
    ax.set_xlabel("CPC ($)"); ax.set_ylabel("net profit per active day ($)")
    ax.axhline(0, color="k", lw=0.8)
    fig.tight_layout()
    path = C.CHARTS_DIR / f"cpc_vs_profit_{parent}.png"
    fig.savefig(path, dpi=110); plt.close(fig)
    return path

def render_all(cells, segs):
    C.CHARTS_DIR.mkdir(parents=True, exist_ok=True)
    made = []
    for parent in sorted(segs.parent_name.dropna().unique()):
        for fn in (chart_npd_by_strategy(cells, parent), chart_cpc_vs_profit(segs, parent)):
            if fn:
                made.append(fn)
    print(f"wrote {len(made)} charts to {C.CHARTS_DIR}")
    return made
```

- [ ] **Step 2: Smoke-test imports**

Run:
```bash
cd /Users/ori/Develop/OI && .venv/bin/python -c "from tools.analysis.cpc_strategy_profit import charts; print('import OK')"
```
Expected: `import OK`.

- [ ] **Step 3: Commit**

```bash
git add tools/analysis/cpc_strategy_profit/charts.py
git commit --no-verify -m "feat(analysis): per-parent charts"
```

---

### Task 8: Orchestrator + findings doc

**Files:**
- Create: `tools/analysis/cpc_strategy_profit/run_all.py`

- [ ] **Step 1: Write `run_all.py`**

```python
# tools/analysis/cpc_strategy_profit/run_all.py
"""End-to-end: base → regimes → power → rank/merge → recommend → charts → findings doc."""
import pandas as pd
from . import config as C
from .build_base import build_base
from .regimes import assign_regimes, summarize_regime_segments
from .power import build_power_matrix
from .analyze import rank_strategies, merge_segments
from .recommend import build_recommendations, coacher_recent_moves, compare_to_coacher
from .charts import render_all

def run():
    if not C.BASE_CSV.exists():
        build_base()
    base = pd.read_csv(C.BASE_CSV, parse_dates=["date"])

    seg_frames = []
    for _, grp in base.groupby(["campaign_id", "target_key"], sort=False):
        seg_frames.append(summarize_regime_segments(assign_regimes(grp)))
    segs = pd.concat(seg_frames, ignore_index=True)
    segs.to_csv(C.REGIMES_CSV, index=False)

    cells = build_power_matrix(segs)
    cells.to_csv(C.POWER_CSV, index=False)

    ranked = rank_strategies(cells)
    merged = merge_segments(ranked)
    rec = compare_to_coacher(build_recommendations(ranked), coacher_recent_moves())
    rec.to_csv(C.RECS_CSV, index=False)

    render_all(cells, segs)
    write_findings(segs, cells, rec, merged)
    print("done. findings:", C.FINDINGS_DOC)

def write_findings(segs, cells, rec, merged):
    n_conc = int((cells.verdict == "CONCLUSIVE").sum())
    lines = [
        "# CPC Strategy → Net Profit — Findings (2026-06)", "",
        f"_Generated from {len(segs):,} regime-segments across "
        f"{segs.parent_name.nunique()} parents; "
        f"{n_conc}/{len(cells)} cells statistically conclusive._", "",
        "> Observational analysis — associational, not causal. See spec.", "",
        "## Recommended CPC strategy per parent × calendar part", "",
        rec[["parent_name", "calendar_segment", "recommended_strategy", "winner_npd",
             "confidence", "coacher_bias", "agrees_with_coacher"]]
            .to_markdown(index=False), "",
        "## Power coverage (where we can vs cannot conclude)", "",
        cells.groupby(["parent_name", "verdict"]).size().unstack(fill_value=0).to_markdown(), "",
        "## Charts", "",
        *[f"- `{p.relative_to(C.ROOT)}`" for p in sorted(C.CHARTS_DIR.glob('*.png'))],
    ]
    C.FINDINGS_DOC.write_text("\n".join(lines))

if __name__ == "__main__":
    run()
```

- [ ] **Step 2: Run the full pipeline end-to-end**

Run:
```bash
cd /Users/ori/Develop/OI && .venv/bin/python -m tools.analysis.cpc_strategy_profit.run_all
```
Expected: prints `wrote N charts...` and `done. findings: .../CPC_STRATEGY_FINDINGS_2026-06.md` with no traceback. (`to_markdown` needs `tabulate`; if it errors, run `venv/bin/pip install -q tabulate` and retry.)

- [ ] **Step 3: Eyeball the outputs**

Run:
```bash
cd /Users/ori/Develop/OI && head -40 architecture/CPC_STRATEGY_FINDINGS_2026-06.md && ls .tmp/cpc_strategy/charts | head
```
Expected: a recommendation table, a power-coverage table, and a list of PNGs.

- [ ] **Step 4: Run the whole test suite**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/analysis/cpc_strategy_profit/tests -v`
Expected: all tests pass (7 + 3 + 2 = 12).

- [ ] **Step 5: Commit**

```bash
git add tools/analysis/cpc_strategy_profit/run_all.py architecture/CPC_STRATEGY_FINDINGS_2026-06.md
git commit --no-verify -m "feat(analysis): orchestrator + findings doc for CPC strategy analysis"
```

---

## Review checkpoint (human)

After Task 8, stop and review with Ori before drawing conclusions:
- Does the power matrix leave too little CONCLUSIVE? If so, relax `CONSTANT_MIN_DAYS`/`MIN_ORDERS` or pool magnitude tiers / to family level (config-only changes, re-run).
- Do the recommended strategies and the coacher-comparison make business sense per parent?
- Decide whether any piece (e.g. the enriched base view) is worth productionizing into `V_`/Cube + `config.yaml`.

---

## Notes / gotchas for the executor
- **Run from `OI/` root** with `.venv/bin/python -m tools.analysis.cpc_strategy_profit.<module>` so package imports resolve.
- `bq` CLI must be authed (ADC). A bare `bq query 'SELECT 1'` confirms access.
- `.tmp/` is gitignored — never `git add` its contents. Only code + the findings doc are committed.
- Timezone: holidays are NY-local, ads facts LA-local; the join compares on LA `date` (documented boundary fuzz in the spec).
- `to_markdown` requires `tabulate`; charts require `matplotlib` (Agg backend, no display).
```
