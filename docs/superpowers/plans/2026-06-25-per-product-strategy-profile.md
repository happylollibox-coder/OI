# Per-Product Strategy Profile — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the coacher a per-product (parent × season × match-type) strategy profile it steers bids toward — target CPC + profitable band, match-type enable/suppress, launch CPC, anchored on derived main keywords — seeded from the CPC analysis, editable, preserved across refreshes.

**Architecture:** Two editable BigQuery `DE_` tables, a Python derivation tool (`tools/strategy_profile/`, reusing the analysis's `build_base`) that loads them via a MANUAL-preserving MERGE, and a steering join added to `V_ADS_COACH_DATA` / `V_ADS_COACH` that clamps recommended bids into the product's band and hard-suppresses CONCLUSIVE-negative match types.

**Tech Stack:** BigQuery Standard SQL (`bq` CLI), Python 3 (`OI/.venv`, pandas), pytest.

**Spec:** `docs/superpowers/specs/2026-06-25-per-product-strategy-profile-design.md`

---

## File Structure

```
scripts/bigquery/tables/DE_PRODUCT_MAIN_KEYWORDS.sql        # DDL
scripts/bigquery/tables/DE_PRODUCT_STRATEGY_PROFILE.sql     # DDL
tools/strategy_profile/__init__.py
tools/strategy_profile/config.py          # constants, paths, project/dataset
tools/strategy_profile/derive.py          # PURE: normalize_match_type, season_of, best_cpc_band, derive_profile, derive_main_keywords
tools/strategy_profile/load.py            # MERGE rows into the DE_ tables, preserving source='MANUAL'
tools/strategy_profile/run.py             # build base -> derive -> load
tools/strategy_profile/tests/test_derive.py
scripts/bigquery/views/V_ADS_COACH_DATA.sql   # MODIFY: season + profile join
scripts/bigquery/views/V_ADS_COACH.sql        # MODIFY: clamp-to-band + suppress
config.yaml                                    # register the 2 tables
```

Conventions: run Python from OI root as `.venv/bin/python -m tools.strategy_profile.<mod>`. `bq --project_id=onyga-482313`. Commit with `--no-verify` (pre-existing lint debt). Branch `feat/owned-negatives-coacher`.

---

### Task 1: DDL for the two tables + register in config.yaml

**Files:**
- Create: `scripts/bigquery/tables/DE_PRODUCT_MAIN_KEYWORDS.sql`
- Create: `scripts/bigquery/tables/DE_PRODUCT_STRATEGY_PROFILE.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write `DE_PRODUCT_MAIN_KEYWORDS.sql`**

```sql
-- DE_PRODUCT_MAIN_KEYWORDS — per-product anchor keywords (derived top terms; editable)
-- Append/update only — NEVER CREATE OR REPLACE (preserves source='MANUAL' rows).
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PRODUCT_MAIN_KEYWORDS` (
  parent_name    STRING NOT NULL,
  keyword_text   STRING NOT NULL,
  keyword_id     STRING,
  match_type     STRING NOT NULL,          -- BROAD/EXACT/PHRASE/AUTO/PRODUCT
  rank           INT64,                     -- 1 = top anchor within (parent, match_type)
  net_profit_90d FLOAT64,
  is_anchor      BOOL DEFAULT TRUE,
  source         STRING NOT NULL,           -- DERIVED / MANUAL
  updated_at     TIMESTAMP,
  updated_by     STRING
)
OPTIONS (description = 'Per-product anchor keywords for the coacher strategy profile. Derived by tools/strategy_profile; MANUAL rows preserved. See docs/superpowers/specs/2026-06-25-per-product-strategy-profile-design.md');
```

- [ ] **Step 2: Write `DE_PRODUCT_STRATEGY_PROFILE.sql`**

```sql
-- DE_PRODUCT_STRATEGY_PROFILE — per parent × season × match-type bid strategy (derived; editable)
-- Append/update only — NEVER CREATE OR REPLACE (preserves source='MANUAL' rows).
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE` (
  parent_name     STRING NOT NULL,
  season          STRING NOT NULL,          -- PEAK / OFF
  match_type      STRING NOT NULL,          -- BROAD/EXACT/PHRASE/AUTO/PRODUCT
  enabled         BOOL NOT NULL,            -- FALSE => suppress bid-up (when confidence=CONCLUSIVE)
  cpc_target      FLOAT64,
  cpc_min         FLOAT64,
  cpc_max         FLOAT64,
  launch_cpc      FLOAT64,
  raise_pace_pct  FLOAT64,
  net_per_dollar  FLOAT64,                  -- evidence: SUM(net)/SUM(cost)
  confidence      STRING,                   -- CONCLUSIVE / WEAK
  tos_target_pct  FLOAT64,                  -- nullable until foundation A
  borrowed_from   STRING,                   -- nullable until sub-project C
  source          STRING NOT NULL,          -- DERIVED / MANUAL / BORROWED
  updated_at      TIMESTAMP,
  updated_by      STRING
)
OPTIONS (description = 'Per-product (parent x season x match-type) bid strategy the coacher steers toward. Derived by tools/strategy_profile; MANUAL rows preserved.');
```

- [ ] **Step 3: Create both tables in BigQuery**

Run:
```bash
cd /Users/ori/Develop/OI
for f in DE_PRODUCT_MAIN_KEYWORDS DE_PRODUCT_STRATEGY_PROFILE; do
  bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/tables/$f.sql && echo "created $f"
done
```
Expected: `created DE_PRODUCT_MAIN_KEYWORDS` and `created DE_PRODUCT_STRATEGY_PROFILE`.

- [ ] **Step 4: Verify schemas**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv 'SELECT table_name, COUNT(*) cols FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS` WHERE table_name IN ("DE_PRODUCT_MAIN_KEYWORDS","DE_PRODUCT_STRATEGY_PROFILE") GROUP BY 1'
```
Expected: `DE_PRODUCT_MAIN_KEYWORDS,10` and `DE_PRODUCT_STRATEGY_PROFILE,16`.

- [ ] **Step 5: Register in config.yaml**

Add two entries under the tables/DE section of `config.yaml` (match the existing `DE_COACH_THRESHOLDS` entry's format):
```yaml
  - name: "DE_PRODUCT_MAIN_KEYWORDS"
    description: "Per-product anchor keywords for the coacher strategy profile (derived + editable)"
  - name: "DE_PRODUCT_STRATEGY_PROFILE"
    description: "Per parent x season x match-type bid strategy the coacher steers toward (derived + editable)"
```

- [ ] **Step 6: Commit**

```bash
git add scripts/bigquery/tables/DE_PRODUCT_MAIN_KEYWORDS.sql scripts/bigquery/tables/DE_PRODUCT_STRATEGY_PROFILE.sql config.yaml
git commit --no-verify -m "feat(coach): DDL for per-product strategy profile tables"
```

---

### Task 2: Derivation logic (pure Python, TDD)

**Files:**
- Create: `tools/strategy_profile/__init__.py` (empty), `tools/strategy_profile/tests/__init__.py` (empty)
- Create: `tools/strategy_profile/config.py`
- Create: `tools/strategy_profile/derive.py`
- Test: `tools/strategy_profile/tests/test_derive.py`

- [ ] **Step 1: Create package + `config.py`**

```bash
mkdir -p tools/strategy_profile/tests
touch tools/strategy_profile/__init__.py tools/strategy_profile/tests/__init__.py
```

```python
# tools/strategy_profile/config.py
"""Constants for the per-product strategy profile derivation."""
PROJECT = "onyga-482313"
DATASET = "OI"
CPC_BIN = 0.10            # $ width for the CPC-band search
TOP_N_KEYWORDS = 10       # main keywords per (parent, match_type)
RAISE_PACE_PCT = 15.0     # default raise pace toward target
MIN_CLICKS = 200          # CONCLUSIVE gate
MIN_ORDERS = 10           # CONCLUSIVE gate
MATCH_MAP = {"broad": "BROAD", "exact": "EXACT", "phrase": "PHRASE",
             "asin": "PRODUCT", "asin expanded": "PRODUCT",
             "automatic": "AUTO", "category": "CATEGORY"}
```

- [ ] **Step 2: Write the failing tests**

```python
# tools/strategy_profile/tests/test_derive.py
import pandas as pd
from tools.strategy_profile.derive import (
    normalize_match_type, season_of, best_cpc_band, derive_profile, derive_main_keywords)

def test_normalize_match_type():
    assert normalize_match_type("broad") == "BROAD"
    assert normalize_match_type("EXACT") == "EXACT"
    assert normalize_match_type("asin") == "PRODUCT"
    assert normalize_match_type("weird") == "OTHER"

def test_season_of():
    assert season_of("Christmas_PEAK") == "PEAK"
    assert season_of("Easter_BOOST") == "PEAK"
    assert season_of("EVERYDAY_2026-01") == "OFF"
    assert season_of("Christmas_COOLDOWN") == "OFF"

def test_best_cpc_band_picks_most_profitable_contiguous_band():
    # net is highest in $0.50-0.60; positive contiguous 0.40-0.70; negative at 0.90
    df = pd.DataFrame({
        "cpc":        [0.45, 0.55, 0.65, 0.95],
        "net_profit": [10.0, 40.0, 15.0, -20.0],
        "clicks":     [10,   20,   10,   10],
    })
    target, lo, hi = best_cpc_band(df)
    assert 0.50 <= target <= 0.60          # midpoint of best band
    assert lo == 0.40 and hi == 0.70       # contiguous positive band edges

def test_best_cpc_band_all_negative_returns_none():
    df = pd.DataFrame({"cpc":[0.9,1.1], "net_profit":[-5.0,-9.0], "clicks":[5,5]})
    assert best_cpc_band(df) == (None, None, None)

def _base():
    # Fresh EXACT loses; Fresh BROAD profits; both off-season
    rows = []
    for cpc, net in [(0.55, 50.0)]*6:           # BROAD profitable, enough clicks/orders
        rows.append(("Fresh","EVERYDAY_2026-01","broad",cpc,net,40,2,"bath term"))
    for cpc, net in [(0.80, -30.0)]*6:          # EXACT loses
        rows.append(("Fresh","EVERYDAY_2026-01","exact",cpc,net,40,2,"exact bath"))
    return pd.DataFrame(rows, columns=["parent_name","calendar_segment","targeting_type",
                                       "cpc","net_profit","clicks","orders","targeting"])

def test_derive_profile_enables_profitable_suppresses_losing():
    prof = derive_profile(_base())
    broad = prof[(prof.match_type=="BROAD")].iloc[0]
    exact = prof[(prof.match_type=="EXACT")].iloc[0]
    assert broad.enabled == True and broad.net_per_dollar > 0
    assert exact.enabled == False and exact.net_per_dollar < 0
    assert broad.season == "OFF" and broad.parent_name == "Fresh"
    assert broad.source == "DERIVED"

def test_derive_main_keywords_ranks_top_n():
    df = pd.DataFrame({
        "parent_name":["Fresh"]*3, "targeting_type":["broad"]*3,
        "targeting":["a","b","c"], "keyword_id":["1","2","3"],
        "net_profit":[5.0, 50.0, 20.0], "clicks":[10,10,10],
    })
    mk = derive_main_keywords(df, top_n=2)
    assert list(mk.sort_values("rank")["keyword_text"]) == ["b","c"]   # top 2 by net
    assert (mk["is_anchor"] == True).all() and (mk["source"]=="DERIVED").all()
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/strategy_profile/tests/test_derive.py -v`
Expected: FAIL (`ModuleNotFoundError: tools.strategy_profile.derive`).

- [ ] **Step 4: Write `derive.py`**

```python
# tools/strategy_profile/derive.py
"""Pure derivation of the per-product strategy profile + main keywords from the keyword-day base."""
from __future__ import annotations
import math
import pandas as pd
from . import config as C

def normalize_match_type(targeting_type: str) -> str:
    return C.MATCH_MAP.get(str(targeting_type).lower(), "OTHER")

def season_of(calendar_segment: str) -> str:
    s = str(calendar_segment)
    return "PEAK" if (s.endswith("_BOOST") or s.endswith("_PEAK")) else "OFF"

def best_cpc_band(cell: pd.DataFrame, cpc_bin: float = C.CPC_BIN):
    """Return (target, lo, hi) for the most profitable contiguous run of CPC bins, or (None,None,None)."""
    if cell.empty:
        return (None, None, None)
    b = cell.assign(band=(cell["cpc"] / cpc_bin).apply(math.floor).astype(int))
    net = b.groupby("band")["net_profit"].sum().sort_index()
    pos = net[net > 0]
    if pos.empty:
        return (None, None, None)
    best = int(net.idxmax())
    if net.get(best, 0) <= 0:
        return (None, None, None)
    lo = best
    while (lo - 1) in net.index and net[lo - 1] > 0:
        lo -= 1
    hi = best
    while (hi + 1) in net.index and net[hi + 1] > 0:
        hi += 1
    target = round((best + 0.5) * cpc_bin, 2)
    return (target, round(lo * cpc_bin, 2), round((hi + 1) * cpc_bin, 2))

def derive_profile(base: pd.DataFrame) -> pd.DataFrame:
    """base: keyword-day rows with parent_name, calendar_segment, targeting_type, cpc, net_profit, clicks, orders."""
    d = base.copy()
    d["match_type"] = d["targeting_type"].map(normalize_match_type)
    d["season"] = d["calendar_segment"].map(season_of)
    rows = []
    for (parent, season, mt), cell in d.groupby(["parent_name", "season", "match_type"]):
        cost = cell["cost"].sum() if "cost" in cell else (cell["cpc"] * cell["clicks"]).sum()
        net = cell["net_profit"].sum()
        npd = net / cost if cost else 0.0
        target, lo, hi = best_cpc_band(cell)
        conclusive = cell["clicks"].sum() >= C.MIN_CLICKS and cell["orders"].sum() >= C.MIN_ORDERS
        rows.append(dict(
            parent_name=parent, season=season, match_type=mt,
            enabled=bool(npd > 0), cpc_target=target, cpc_min=lo, cpc_max=hi,
            launch_cpc=lo, raise_pace_pct=C.RAISE_PACE_PCT,
            net_per_dollar=round(npd, 3),
            confidence="CONCLUSIVE" if conclusive else "WEAK",
            tos_target_pct=None, borrowed_from=None, source="DERIVED"))
    return pd.DataFrame(rows)

def derive_main_keywords(base: pd.DataFrame, top_n: int = C.TOP_N_KEYWORDS) -> pd.DataFrame:
    d = base.copy()
    d["match_type"] = d["targeting_type"].map(normalize_match_type)
    g = (d.groupby(["parent_name", "match_type", "targeting"], dropna=False)
           .agg(net_profit_90d=("net_profit", "sum"),
                keyword_id=("keyword_id", "first") if "keyword_id" in d else ("targeting", "first"))
           .reset_index())
    g["rank"] = (g.groupby(["parent_name", "match_type"])["net_profit_90d"]
                   .rank(ascending=False, method="first").astype(int))
    g = g[g["rank"] <= top_n].copy()
    g = g.rename(columns={"targeting": "keyword_text"})
    g["is_anchor"] = True
    g["source"] = "DERIVED"
    return g[["parent_name", "keyword_text", "keyword_id", "match_type",
              "rank", "net_profit_90d", "is_anchor", "source"]]
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/strategy_profile/tests/test_derive.py -v`
Expected: 6 passed.

- [ ] **Step 6: Commit**

```bash
git add tools/strategy_profile/__init__.py tools/strategy_profile/config.py tools/strategy_profile/derive.py tools/strategy_profile/tests/
git commit --no-verify -m "feat(coach): strategy-profile derivation logic (TDD)"
```

---

### Task 3: Loader with MANUAL-preservation

**Files:**
- Create: `tools/strategy_profile/load.py`
- Test: add to `tools/strategy_profile/tests/test_derive.py`

- [ ] **Step 1: Write the failing test (row-prep is pure and testable)**

Append to `tools/strategy_profile/tests/test_derive.py`:
```python
from tools.strategy_profile.load import to_json_rows

def test_to_json_rows_stamps_audit_fields():
    import pandas as pd
    df = pd.DataFrame([{"parent_name":"Fresh","season":"OFF","match_type":"BROAD",
                        "enabled":True,"cpc_target":0.55,"cpc_min":0.4,"cpc_max":0.7,
                        "launch_cpc":0.4,"raise_pace_pct":15.0,"net_per_dollar":0.8,
                        "confidence":"CONCLUSIVE","tos_target_pct":None,"borrowed_from":None,
                        "source":"DERIVED"}])
    rows = to_json_rows(df, updated_by="strategy_profile_tool")
    assert rows[0]["updated_by"] == "strategy_profile_tool"
    assert "updated_at" in rows[0] and rows[0]["enabled"] is True
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/strategy_profile/tests/test_derive.py::test_to_json_rows_stamps_audit_fields -v`
Expected: FAIL (`cannot import name 'to_json_rows'`).

- [ ] **Step 3: Write `load.py`**

```python
# tools/strategy_profile/load.py
"""Load derived profile/main-keyword rows into BQ, preserving source='MANUAL' rows.

Strategy: DELETE the DERIVED rows for the keys we're refreshing, then INSERT the new
DERIVED rows. MANUAL rows are never touched.
"""
import datetime as dt, json, subprocess, tempfile
from . import config as C

def to_json_rows(df, updated_by: str):
    now = dt.datetime.utcnow().isoformat()
    rows = df.where(df.notna(), None).to_dict("records")
    for r in rows:
        r["updated_at"] = now
        r["updated_by"] = updated_by
    return rows

def _bq(sql: str):
    out = subprocess.run(["bq", f"--project_id={C.PROJECT}", "query", "--use_legacy_sql=false"],
                         input=sql, capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(out.stderr)

def load_table(df, table: str, updated_by="strategy_profile_tool"):
    """Replace only the DERIVED rows of `table` with df's rows (MANUAL rows preserved)."""
    _bq(f"DELETE FROM `{C.PROJECT}.{C.DATASET}.{table}` WHERE source='DERIVED'")
    rows = to_json_rows(df, updated_by)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
        path = f.name
    out = subprocess.run(
        ["bq", f"--project_id={C.PROJECT}", "load", "--source_format=NEWLINE_DELIMITED_JSON",
         f"{C.DATASET}.{table}", path], capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(out.stderr)
    print(f"loaded {len(rows)} DERIVED rows into {table}")
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/strategy_profile/tests/test_derive.py -v`
Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/strategy_profile/load.py tools/strategy_profile/tests/test_derive.py
git commit --no-verify -m "feat(coach): strategy-profile BQ loader (preserves MANUAL rows)"
```

---

### Task 4: Orchestrate + run on real data + validate seed sanity

**Files:**
- Create: `tools/strategy_profile/run.py`

- [ ] **Step 1: Write `run.py`**

```python
# tools/strategy_profile/run.py
"""Build the keyword-day base (reuse the analysis), derive the profile + main keywords, load to BQ."""
import pandas as pd
from tools.analysis.cpc_strategy_profit import config as AC
from tools.analysis.cpc_strategy_profit.build_base import build_base
from .derive import derive_profile, derive_main_keywords
from .load import load_table

def run():
    if not AC.BASE_CSV.exists():
        build_base()
    base = pd.read_csv(AC.BASE_CSV, parse_dates=["date"])
    prof = derive_profile(base)
    mk = derive_main_keywords(base)
    load_table(prof, "DE_PRODUCT_STRATEGY_PROFILE")
    load_table(mk, "DE_PRODUCT_MAIN_KEYWORDS")
    print(f"profile rows={len(prof)}  main_keywords={len(mk)}")

if __name__ == "__main__":
    run()
```

- [ ] **Step 2: Run it against real data**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m tools.strategy_profile.run`
Expected: `loaded N DERIVED rows...` twice, then `profile rows=NN  main_keywords=NN`, no traceback.

- [ ] **Step 3: Validate seed sanity (must match the spec §7 findings)**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty '
SELECT parent_name, match_type,
  COUNTIF(enabled) enabled_cells, COUNTIF(NOT enabled) disabled_cells,
  ROUND(AVG(net_per_dollar),2) avg_npd
FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`
WHERE match_type="EXACT" GROUP BY 1,2 ORDER BY 1'
```
Expected: EXACT is **disabled** (enabled=FALSE, negative avg_npd) for **Fresh** and **Lollibox**, and **enabled** for **LolliME**. If not, stop and report — the derivation diverges from the analysis.

- [ ] **Step 4: Validate MANUAL preservation**

Run:
```bash
cd /Users/ori/Develop/OI
bq --project_id=onyga-482313 query --use_legacy_sql=false "INSERT INTO \`onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE\` (parent_name,season,match_type,enabled,cpc_target,source,updated_at,updated_by) VALUES ('Bottle','PEAK','BROAD',true,0.99,'MANUAL',CURRENT_TIMESTAMP(),'test')"
.venv/bin/python -m tools.strategy_profile.run
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv "SELECT COUNT(*) FROM \`onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE\` WHERE source='MANUAL' AND cpc_target=0.99"
```
Expected: the final count is `1` — the MANUAL row survived the refresh. (Then delete it: `bq query "DELETE FROM ... WHERE source='MANUAL' AND updated_by='test'"`.)

- [ ] **Step 5: Commit**

```bash
git add tools/strategy_profile/run.py
git commit --no-verify -m "feat(coach): strategy-profile orchestrator; seeded + validated against analysis"
```

---

### Task 5: Steering part 1 — season + profile join in `V_ADS_COACH_DATA`

**Files:**
- Modify: `scripts/bigquery/views/V_ADS_COACH_DATA.sql`

- [ ] **Step 1: Locate the anchors**

Run: `cd /Users/ori/Develop/OI && rg -n "DIM_STRATEGY_TEMPLATE|strategy_id|coach_mode|parent_name|targeting_type|recommended_bid_min" scripts/bigquery/views/V_ADS_COACH_DATA.sql | head -40`
Note the CTE where `DIM_STRATEGY_TEMPLATE` is LEFT JOINed (≈ line 78) and the final SELECT's column list. Confirm `parent_name`, `targeting_type`, and a coach-mode source are available there.

- [ ] **Step 2: Add the profile join + season in the appropriate CTE**

In the CTE that joins `DIM_STRATEGY_TEMPLATE` (the one exposing `recommended_bid_min/max`), add a season expression and LEFT JOIN the profile. Insert alongside the existing strategy-template join:

```sql
  -- season for the per-product strategy profile (BLITZ/peak => PEAK; else OFF)
  ,CASE WHEN COALESCE(fcm.coach_mode,'GUARDIAN') = 'BLITZ' THEN 'PEAK' ELSE 'OFF' END AS profile_season
  ,UPPER(psp.match_type) IS NOT NULL AS has_product_profile
  ,psp.enabled        AS profile_enabled
  ,psp.cpc_target     AS profile_cpc_target
  ,psp.cpc_min        AS profile_cpc_min
  ,psp.cpc_max        AS profile_cpc_max
  ,psp.confidence     AS profile_confidence
```
and the join (place next to the `DIM_STRATEGY_TEMPLATE` LEFT JOIN, mapping the row's match type via the same normalization as the tool — uppercased `targeting_type` collapsed to BROAD/EXACT/PHRASE/AUTO/PRODUCT):
```sql
  LEFT JOIN `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE` psp
    ON psp.parent_name = <parent_name_col>
   AND psp.season = (CASE WHEN COALESCE(fcm.coach_mode,'GUARDIAN')='BLITZ' THEN 'PEAK' ELSE 'OFF' END)
   AND psp.match_type = CASE UPPER(<targeting_type_col>)
        WHEN 'BROAD' THEN 'BROAD' WHEN 'EXACT' THEN 'EXACT' WHEN 'PHRASE' THEN 'PHRASE'
        WHEN 'AUTOMATIC' THEN 'AUTO' WHEN 'ASIN' THEN 'PRODUCT' WHEN 'ASIN EXPANDED' THEN 'PRODUCT'
        WHEN 'CATEGORY' THEN 'CATEGORY' ELSE UPPER(<targeting_type_col>) END
```
Replace `<parent_name_col>` / `<targeting_type_col>` / `fcm.coach_mode` with the actual aliases found in Step 1. Propagate the new `profile_*` columns out through every downstream CTE/SELECT to the view's final output.

- [ ] **Step 3: Deploy the view**

Run: `cd /Users/ori/Develop/OI && bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/views/V_ADS_COACH_DATA.sql && echo OK`
Expected: `OK` (no SQL error).

- [ ] **Step 4: Validate row-count parity (no fan-out from the join)**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv 'SELECT COUNT(*) FROM `onyga-482313.OI.V_ADS_COACH_DATA`'
```
Compare to the row count captured before the change (capture it first with the same query on the deployed pre-change view, or `git stash` compare). Expected: **identical** — the profile join is many-to-one (one profile row per parent×season×match_type) and must not multiply rows. If it grew, the join key isn't unique-per-row — stop and fix.

- [ ] **Step 5: Commit**

```bash
git add scripts/bigquery/views/V_ADS_COACH_DATA.sql
git commit --no-verify -m "feat(coach): join per-product strategy profile + season into V_ADS_COACH_DATA"
```

---

### Task 6: Steering part 2 — clamp-to-band + suppress in `V_ADS_COACH`

**Files:**
- Modify: `scripts/bigquery/views/V_ADS_COACH.sql`

- [ ] **Step 1: Locate the anchors**

Run: `cd /Users/ori/Develop/OI && rg -n "strategy_bid_min|strategy_bid_max|recommended_bid|target_action|INCREASE_BID|profile_" scripts/bigquery/views/V_ADS_COACH.sql | head -40`
Note: where `strategy_bid_min`/`strategy_bid_max` are set (≈ lines 162/209), where `recommended_bid` is computed (≈ 259-260), and where `target_action` resolves `INCREASE_BID`.

- [ ] **Step 2: Override the bid band with the product band**

Change the `strategy_bid_min` / `strategy_bid_max` definitions to prefer the product profile:
```sql
    COALESCE(d.profile_cpc_min, stmpl.recommended_bid_min, 0.10) as strategy_bid_min,
    COALESCE(d.profile_cpc_max, stmpl.recommended_bid_max)      as strategy_bid_max,
```
The existing `recommended_bid` already clamps with `LEAST(..., bid_cap)`; extend it to also respect the band:
```sql
    LEAST(GREATEST(<existing_recommended_bid_expr>, strategy_bid_min), strategy_bid_max, th_bid_cap) as recommended_bid
```
(Use the existing inner bid expression in place of `<existing_recommended_bid_expr>`; do not duplicate the cap logic — fold the GREATEST/LEAST around what's already there.)

- [ ] **Step 3: Suppress bid-up on CONCLUSIVE-negative cells**

In the `target_action` CASE, add — **before** any branch that can emit `INCREASE_BID` — a guard that blocks bid-up when the product profile disables this match type with confidence:
```sql
      WHEN d.profile_enabled = FALSE AND d.profile_confidence = 'CONCLUSIVE'
           AND <the_increase_condition> THEN 'MONITOR_TARGET'
```
Keep `REDUCE_BID` / `STOP_TARGET` branches intact (money-bleeders in a suppressed cell should still be cut). Add a decision-trace chip in the existing trace JSON build: `STRUCT('product_strategy' AS id, 'suppressed by product strategy' AS label, d.profile_confidence AS rule)` (match the existing chip struct shape in the file).

Also surface the profile fields in `V_ADS_COACH`'s final SELECT so they're queryable for validation and display: add `d.profile_cpc_min`, `d.profile_cpc_max`, `d.profile_cpc_target`, `d.profile_enabled`, `d.profile_confidence` to the output column list.

- [ ] **Step 4: Deploy the view**

Run: `cd /Users/ori/Develop/OI && bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/views/V_ADS_COACH.sql && echo OK`
Expected: `OK`.

- [ ] **Step 5: Validate steering behavior**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty '
SELECT
  COUNTIF(profile_cpc_max IS NOT NULL AND recommended_bid > profile_cpc_max + 0.001) AS over_band,
  COUNTIF(profile_cpc_min IS NOT NULL AND recommended_bid < profile_cpc_min - 0.001) AS under_band,
  COUNTIF(profile_enabled = FALSE AND profile_confidence="CONCLUSIVE" AND target_action="INCREASE_BID") AS suppressed_violations
FROM `onyga-482313.OI.V_ADS_COACH`'
```
Expected: `over_band=0`, `under_band=0`, `suppressed_violations=0`. Any non-zero means the clamp/suppress isn't applied — stop and fix.

- [ ] **Step 6: Refresh actions + spot-check Fresh/Lollibox exact**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false 'CALL `onyga-482313.OI.SP_REFRESH_ADS_COACH_ACTIONS`()'
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty '
SELECT parent_name, targeting_type, COUNTIF(target_action="INCREASE_BID") increases
FROM `onyga-482313.OI.V_ADS_COACH`
WHERE parent_name IN ("Fresh","Lollibox") AND UPPER(targeting_type)="EXACT" GROUP BY 1,2'
```
Expected: `increases = 0` for Fresh/Lollibox exact (bid-up suppressed). Verify a LolliME exact row can still get `INCREASE_BID`.

- [ ] **Step 7: Commit**

```bash
git add scripts/bigquery/views/V_ADS_COACH.sql
git commit --no-verify -m "feat(coach): steer bids to product band + suppress CONCLUSIVE-negative match types"
```

---

### Task 7: Data-entry editability (minimal CRUD)

**Files:**
- Modify: `data-entry-app/app.py`

- [ ] **Step 1: Locate an existing DE_ table CRUD endpoint to copy the pattern**

Run: `cd /Users/ori/Develop/OI && rg -n "DE_COACH_THRESHOLDS|@app.route.*coach.thresh|def .*threshold" data-entry-app/app.py | head`
Use the closest existing DE_ editing endpoint as the template (same auth decorator, BQ client usage, and `clear_data_cache()` call after writes).

- [ ] **Step 2: Add GET + upsert endpoints for the profile**

Add two routes mirroring that pattern (auth-guarded, parameterized UPDATE/MERGE via `QueryJobConfig`). On any write, set `source='MANUAL'`, stamp `updated_at`/`updated_by` (the logged-in user), and call `clear_data_cache()`:
```python
@app.route("/api/product-strategy", methods=["GET"])
@login_required
def get_product_strategy():
    rows = bq_query("SELECT * FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE` ORDER BY parent_name, season, match_type")
    return jsonify(rows)

@app.route("/api/product-strategy", methods=["POST"])
@login_required
def upsert_product_strategy():
    p = request.get_json()
    sql = """MERGE `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE` t
      USING (SELECT @parent parent_name, @season season, @mt match_type) s
      ON t.parent_name=s.parent_name AND t.season=s.season AND t.match_type=s.match_type
      WHEN MATCHED THEN UPDATE SET enabled=@enabled, cpc_target=@cpc_target, cpc_min=@cpc_min,
        cpc_max=@cpc_max, source='MANUAL', updated_at=CURRENT_TIMESTAMP(), updated_by=@user
      WHEN NOT MATCHED THEN INSERT (parent_name,season,match_type,enabled,cpc_target,cpc_min,cpc_max,source,updated_at,updated_by)
        VALUES (@parent,@season,@mt,@enabled,@cpc_target,@cpc_min,@cpc_max,'MANUAL',CURRENT_TIMESTAMP(),@user)"""
    run_parameterized(sql, p)   # use the app's existing parameterized-query helper
    clear_data_cache()
    return jsonify({"ok": True})
```
Match the actual helper names in `app.py` (`bq_query`, parameterized-update helper, `clear_data_cache`); the names above are placeholders for whatever the file already uses.

- [ ] **Step 3: Smoke-test the endpoint locally**

Run (Flask on :5050 per the project note — clear any stale prod token):
```bash
cd /Users/ori/Develop/OI/data-entry-app && env -u CUBEJS_API_SECRET PORT=5050 ../.venv/bin/python app.py &
sleep 4 && curl -s localhost:5050/api/product-strategy | head -c 300; echo
```
Expected: a JSON array of profile rows (or an auth redirect if the local dev token isn't set — then verify the route is registered via the startup logs instead).

- [ ] **Step 4: Commit**

```bash
git add data-entry-app/app.py
git commit --no-verify -m "feat(coach): data-entry CRUD for per-product strategy profile (MANUAL edits)"
```

---

## Review checkpoint (human)

After Task 6, before Task 7, stop and review with Ori:
- Does the seeded profile (`SELECT * FROM DE_PRODUCT_STRATEGY_PROFILE ORDER BY parent_name, season, match_type`) match his intent per product? This is the moment to hand-edit (MANUAL) any cell that looks wrong before the steering drives real bids.
- Confirm the suppression on Fresh/Lollibox exact is desired before relying on it.

---

## Notes / gotchas
- **Don't `CREATE OR REPLACE` the DE_ tables** — `CREATE TABLE IF NOT EXISTS` only; the loader's DELETE-DERIVED + INSERT preserves MANUAL rows.
- **The two views are large and delicate** (`V_ADS_COACH_DATA` ~1600 lines). Make minimal, additive edits at the anchors found in Step 1; propagate new columns through every intermediate CTE. After each view edit, the deploy step is the syntax gate and the row-parity query is the correctness gate.
- **Cube freshness:** `V_ADS_COACH` feeds materialized `T_`/`FACT_ADS_COACH_ACTIONS` via `SP_REFRESH_ADS_COACH_ACTIONS` — call it (Task 6 Step 6) before checking dashboard-facing results.
- **`tos_target_pct` stays NULL** until foundation A (sub-project A) lands; the steering must treat NULL band/target as "no override" (the `COALESCE` handles this).
- `.venv/bin/python` = OI root venv (3.12); `bq` authed for `onyga-482313`.
