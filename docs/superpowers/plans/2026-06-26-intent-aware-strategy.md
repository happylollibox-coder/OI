# Intent-Aware Strategy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the coacher's per-product strategy intent-aware — classify every keyword BRAND / PRODUCT / GENERIC, add `intent_class` to the strategy grain, and change suppression so it defends BRAND, protects PRODUCT (e.g. LolliME journal exact), and suppresses only GENERIC losers (e.g. Lollibox generic exact).

**Architecture:** A new `V_KEYWORD_INTENT_CLASS` view classifies keywords (reusing `DIM_BRAND_PHRASES` for brand + `FACT_RESEARCH_RANKED` fit + the anchor list, with a manual-override table). `DE_PRODUCT_STRATEGY_PROFILE` gains `intent_class` in its grain; the Python derivation merges the class and groups by it; the two coacher views join the class and apply intent-aware suppression. Band-clamp stays MANUAL-only (the B I1 de-risk holds).

**Tech Stack:** BigQuery Standard SQL (`bq` CLI), Python 3 (`OI/.venv`, pandas), pytest.

**Spec:** `docs/superpowers/specs/2026-06-26-intent-aware-strategy-design.md`

---

## File Structure

```
scripts/bigquery/tables/DE_KEYWORD_INTENT_OVERRIDE.sql      # new DDL (manual class overrides)
scripts/bigquery/views/V_KEYWORD_INTENT_CLASS.sql          # new: keyword -> BRAND/PRODUCT/GENERIC
tools/strategy_profile/config.py                            # MODIFY: add INTENT classes constant
tools/strategy_profile/derive.py                            # MODIFY: group by intent_class; brand=enabled
tools/strategy_profile/run.py                               # MODIFY: merge intent_class onto base
tools/strategy_profile/tests/test_derive.py                 # MODIFY: intent tests
scripts/bigquery/views/V_ADS_COACH_DATA.sql                 # MODIFY: join intent + 4-key profile join
scripts/bigquery/views/V_ADS_COACH.sql                     # MODIFY: intent-aware suppression
config.yaml                                                 # register new objects
```

Run Python from OI root: `.venv/bin/python -m tools.strategy_profile.run`. `bq --project_id=onyga-482313`. Commit `--no-verify`. Branch `feat/owned-negatives-coacher`.

---

### Task 1: DDL — override table + add intent columns + register

**Files:**
- Create: `scripts/bigquery/tables/DE_KEYWORD_INTENT_OVERRIDE.sql`
- Modify: `config.yaml`

- [ ] **Step 1: Write `DE_KEYWORD_INTENT_OVERRIDE.sql`**

```sql
-- DE_KEYWORD_INTENT_OVERRIDE — manual corrections to a keyword's intent class (BRAND/PRODUCT/GENERIC)
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_KEYWORD_INTENT_OVERRIDE` (
  parent_name   STRING NOT NULL,
  keyword_text  STRING NOT NULL,   -- store LOWER(text)
  intent_class  STRING NOT NULL,   -- BRAND / PRODUCT / GENERIC
  updated_at    TIMESTAMP,
  updated_by    STRING
)
OPTIONS (description = 'Manual override of keyword intent class; wins over V_KEYWORD_INTENT_CLASS derivation.');
```

- [ ] **Step 2: Create it + add intent columns to the two existing tables**

Run:
```bash
cd /Users/ori/Develop/OI
bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/tables/DE_KEYWORD_INTENT_OVERRIDE.sql && echo "override table OK"
bq --project_id=onyga-482313 query --use_legacy_sql=false '
ALTER TABLE `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE` ADD COLUMN IF NOT EXISTS intent_class STRING;
ALTER TABLE `onyga-482313.OI.DE_PRODUCT_MAIN_KEYWORDS`  ADD COLUMN IF NOT EXISTS is_brand BOOL;
ALTER TABLE `onyga-482313.OI.DE_PRODUCT_MAIN_KEYWORDS`  ADD COLUMN IF NOT EXISTS intent_class STRING;' && echo "columns added"
```
Expected: `override table OK`, `columns added`.

- [ ] **Step 3: Register in config.yaml**

Add under the appropriate sections of `config.yaml`:
```yaml
  - name: "DE_KEYWORD_INTENT_OVERRIDE"
    description: "Manual override of keyword intent class (BRAND/PRODUCT/GENERIC) for the coacher strategy"
  - name: "V_KEYWORD_INTENT_CLASS"
    description: "Classifies each ad keyword as BRAND/PRODUCT/GENERIC (brand dict + research fit + anchors + manual override)"
```

- [ ] **Step 4: Commit**

```bash
git add scripts/bigquery/tables/DE_KEYWORD_INTENT_OVERRIDE.sql config.yaml
git commit --no-verify -m "feat(coach): intent-override table + intent columns on strategy tables"
```

---

### Task 2: `V_KEYWORD_INTENT_CLASS` view

**Files:**
- Create: `scripts/bigquery/views/V_KEYWORD_INTENT_CLASS.sql`

- [ ] **Step 1: Write the view**

```sql
-- V_KEYWORD_INTENT_CLASS — classify each ad keyword per parent as BRAND / PRODUCT / GENERIC.
-- BRAND: contains a DIM_BRAND_PHRASES BRAND phrase.  PRODUCT: not brand AND (research fit >= 50 OR is an anchor).
-- GENERIC: everything else.  DE_KEYWORD_INTENT_OVERRIDE wins.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_INTENT_CLASS` AS
WITH camp_parent AS (
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
    WHERE a.date >= DATE('2025-09-23') GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
kw AS (
  SELECT DISTINCT cp.parent_name, LOWER(a.targeting) AS keyword_text
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camp_parent cp ON cp.campaign_id = a.campaign_id
  WHERE a.targeting IS NOT NULL AND a.targeting != ''
),
brand AS (
  SELECT k.parent_name, k.keyword_text, TRUE AS is_brand
  FROM kw k
  WHERE EXISTS (SELECT 1 FROM `onyga-482313.OI.DIM_BRAND_PHRASES` b
                WHERE b.phrase_type = 'BRAND' AND STRPOS(k.keyword_text, LOWER(b.phrase)) > 0)
),
fit AS (
  SELECT parent_name, LOWER(query_text) AS keyword_text, MAX(rank) AS fit_rank
  FROM `onyga-482313.OI.FACT_RESEARCH_RANKED` GROUP BY 1,2
),
anchor AS (
  SELECT DISTINCT parent_name, LOWER(keyword_text) AS keyword_text
  FROM `onyga-482313.OI.DE_PRODUCT_MAIN_KEYWORDS` WHERE is_anchor
)
SELECT kw.parent_name, kw.keyword_text,
  COALESCE(ov.intent_class,
    CASE WHEN b.is_brand THEN 'BRAND'
         WHEN an.keyword_text IS NOT NULL OR f.fit_rank >= 50 THEN 'PRODUCT'
         ELSE 'GENERIC' END) AS intent_class
FROM kw
LEFT JOIN brand  b  ON b.parent_name = kw.parent_name AND b.keyword_text = kw.keyword_text
LEFT JOIN fit    f  ON f.parent_name = kw.parent_name AND f.keyword_text = kw.keyword_text
LEFT JOIN anchor an ON an.parent_name = kw.parent_name AND an.keyword_text = kw.keyword_text
LEFT JOIN `onyga-482313.OI.DE_KEYWORD_INTENT_OVERRIDE` ov
  ON ov.parent_name = kw.parent_name AND LOWER(ov.keyword_text) = kw.keyword_text;
```

Output columns: `parent_name, keyword_text, intent_class` (one row per parent×keyword).

- [ ] **Step 2: Deploy + validate known terms**

Run:
```bash
cd /Users/ori/Develop/OI
bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/views/V_KEYWORD_INTENT_CLASS.sql && echo OK
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty '
SELECT parent_name, keyword_text, intent_class
FROM `onyga-482313.OI.V_KEYWORD_INTENT_CLASS`
WHERE (parent_name="LolliME" AND keyword_text IN ("journal for girls","girls diary","gift for 9 year old girl"))
   OR (parent_name="Lollibox" AND keyword_text="happy lolli gift box")
ORDER BY parent_name, keyword_text'
```
Expected: "journal for girls"→PRODUCT, "girls diary"→PRODUCT, "gift for 9 year old girl"→GENERIC, "happy lolli gift box"→BRAND. If a classification looks wrong, report it (it may indicate the fit threshold or brand dict needs tuning) before continuing.

- [ ] **Step 3: Commit**

```bash
git add scripts/bigquery/views/V_KEYWORD_INTENT_CLASS.sql
git commit --no-verify -m "feat(coach): V_KEYWORD_INTENT_CLASS — BRAND/PRODUCT/GENERIC classification"
```

---

### Task 3: Derivation — group by intent_class (TDD)

**Files:**
- Modify: `tools/strategy_profile/derive.py`
- Test: `tools/strategy_profile/tests/test_derive.py`

- [ ] **Step 1: Write the failing tests** (append to `test_derive.py`)

```python
def test_derive_profile_groups_by_intent_and_brand_is_enabled():
    import pandas as pd
    from tools.strategy_profile.derive import derive_profile
    rows = []
    # LolliME EXACT, two intents: PRODUCT profits, GENERIC loses; plus a BRAND losing cell
    for cpc, net in [(0.75, 30.0)]*6:
        rows.append(("LolliME","Christmas_PEAK","exact","PRODUCT",cpc,net,40,2,"journal for girls"))
    for cpc, net in [(0.80, -25.0)]*6:
        rows.append(("LolliME","Christmas_PEAK","exact","GENERIC",cpc,net,40,2,"gift for girls"))
    for cpc, net in [(0.50, -10.0)]*6:
        rows.append(("LolliME","Christmas_PEAK","exact","BRAND",cpc,net,40,2,"happy lolli journal"))
    df = pd.DataFrame(rows, columns=["parent_name","calendar_segment","targeting_type","intent_class",
                                     "cpc","net_profit","clicks","orders","targeting"])
    prof = derive_profile(df)
    prod = prof[(prof.intent_class=="PRODUCT")].iloc[0]
    gen  = prof[(prof.intent_class=="GENERIC")].iloc[0]
    brand= prof[(prof.intent_class=="BRAND")].iloc[0]
    assert set(["parent_name","season","match_type","intent_class","enabled"]).issubset(prof.columns)
    assert prod.enabled == True                 # product profits -> enabled
    assert gen.enabled == False                 # generic loses -> disabled
    assert brand.enabled == True                # BRAND always enabled (defense) despite negative net
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/strategy_profile/tests/test_derive.py::test_derive_profile_groups_by_intent_and_brand_is_enabled -v`
Expected: FAIL (`intent_class` not in groupby / KeyError).

- [ ] **Step 3: Update `derive_profile` in `derive.py`**

Change the grouping to include `intent_class` and force BRAND enabled. Replace the `derive_profile` body's group loop:
```python
def derive_profile(base: pd.DataFrame) -> pd.DataFrame:
    """base: keyword-day rows with parent_name, calendar_segment, targeting_type, intent_class, cpc, net_profit, clicks, orders."""
    d = base.copy()
    d["match_type"] = d["targeting_type"].map(normalize_match_type)
    d["season"] = d["calendar_segment"].map(season_of)
    if "intent_class" not in d.columns:
        d["intent_class"] = "GENERIC"
    rows = []
    for (parent, season, mt, intent), cell in d.groupby(["parent_name", "season", "match_type", "intent_class"]):
        cost = cell["cost"].sum() if "cost" in cell else (cell["cpc"] * cell["clicks"]).sum()
        net = cell["net_profit"].sum()
        npd = net / cost if cost else 0.0
        target, lo, hi = best_cpc_band(cell)
        conclusive = cell["clicks"].sum() >= C.MIN_CLICKS and cell["orders"].sum() >= C.MIN_ORDERS
        enabled = bool(npd > 0) or (intent == "BRAND")   # BRAND always defended
        rows.append(dict(
            parent_name=parent, season=season, match_type=mt, intent_class=intent,
            enabled=enabled, cpc_target=target, cpc_min=lo, cpc_max=hi,
            launch_cpc=lo, raise_pace_pct=C.RAISE_PACE_PCT,
            net_per_dollar=round(npd, 3),
            confidence="CONCLUSIVE" if conclusive else "WEAK",
            tos_target_pct=None, borrowed_from=None, source="DERIVED"))
    return pd.DataFrame(rows)
```

- [ ] **Step 4: Run to verify it passes + the full suite**

Run: `cd /Users/ori/Develop/OI && .venv/bin/python -m pytest tools/strategy_profile/tests -v`
Expected: all pass (the existing `derive_profile` test that builds a base without `intent_class` still works — it defaults to GENERIC; if that older test asserts a specific row, update it to filter `intent_class=="GENERIC"`).

- [ ] **Step 5: Commit**

```bash
git add tools/strategy_profile/derive.py tools/strategy_profile/tests/test_derive.py
git commit --no-verify -m "feat(coach): derive strategy profile per intent_class; BRAND always enabled (TDD)"
```

---

### Task 4: Wire classification into the run + re-derive + validate

**Files:**
- Modify: `tools/strategy_profile/run.py`
- Modify: `tools/strategy_profile/derive.py` (main-keyword tags)

- [ ] **Step 1: Tag main keywords with is_brand/intent_class in `derive_main_keywords`**

In `derive.py`, after building `g` in `derive_main_keywords`, merge the class (passed in) — change the signature to accept an optional class map and add the columns:
```python
def derive_main_keywords(base, intent=None, top_n=C.TOP_N_KEYWORDS):
    d = base.copy()
    d["match_type"] = d["targeting_type"].map(normalize_match_type)
    g = (d.groupby(["parent_name","match_type","targeting"], dropna=False)
           .agg(net_profit_90d=("net_profit","sum"),
                keyword_id=("keyword_id","first") if "keyword_id" in d else ("targeting","first"))
           .reset_index())
    g["rank"] = (g.groupby(["parent_name","match_type"])["net_profit_90d"]
                   .rank(ascending=False, method="first").astype(int))
    g = g[g["rank"] <= top_n].rename(columns={"targeting":"keyword_text"})
    g["is_anchor"] = True
    g["source"] = "DERIVED"
    if intent is not None:
        key = g["parent_name"] + "|" + g["keyword_text"].str.lower()
        g["intent_class"] = key.map(intent).fillna("GENERIC")
    else:
        g["intent_class"] = "GENERIC"
    g["is_brand"] = g["intent_class"].eq("BRAND")
    return g[["parent_name","keyword_text","keyword_id","match_type","rank","net_profit_90d",
              "is_anchor","is_brand","intent_class","source"]]
```

- [ ] **Step 2: Update `run.py` to merge intent_class onto the base**

```python
# tools/strategy_profile/run.py
"""Build base, classify intent, derive per-intent profile + main keywords, load to BQ."""
import io, subprocess
import pandas as pd
from tools.analysis.cpc_strategy_profit import config as AC
from tools.analysis.cpc_strategy_profit.build_base import build_base
from . import config as C
from .derive import derive_profile, derive_main_keywords
from .load import load_table

def _intent_map():
    out = subprocess.run(["bq", f"--project_id={C.PROJECT}", "query", "--use_legacy_sql=false",
                          "--format=csv", "--max_rows=1000000",
                          "SELECT parent_name, keyword_text, intent_class FROM `onyga-482313.OI.V_KEYWORD_INTENT_CLASS`"],
                         capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(out.stderr)
    cl = pd.read_csv(io.StringIO(out.stdout))
    return dict(zip(cl["parent_name"] + "|" + cl["keyword_text"].str.lower(), cl["intent_class"]))

def run():
    if not AC.BASE_CSV.exists():
        build_base()
    base = pd.read_csv(AC.BASE_CSV, parse_dates=["date"])
    intent = _intent_map()
    base["intent_class"] = (base["parent_name"] + "|" + base["targeting"].str.lower()).map(intent).fillna("GENERIC")
    prof = derive_profile(base)
    mk = derive_main_keywords(base, intent=intent)
    load_table(prof, "DE_PRODUCT_STRATEGY_PROFILE")
    load_table(mk, "DE_PRODUCT_MAIN_KEYWORDS")
    print(f"profile rows={len(prof)} (intents: {sorted(prof.intent_class.unique())})  main_keywords={len(mk)}")

if __name__ == "__main__":
    run()
```

- [ ] **Step 3: Re-derive + validate the per-intent profile**

Run:
```bash
cd /Users/ori/Develop/OI && .venv/bin/python -m tools.strategy_profile.run
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty '
SELECT parent_name, intent_class, enabled, ROUND(net_per_dollar,2) npd, confidence
FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`
WHERE match_type="EXACT" AND parent_name IN ("LolliME","Lollibox","Fresh")
ORDER BY parent_name, intent_class, season'
```
Expected: LolliME EXACT PRODUCT → `enabled=true` (npd>0); Lollibox/Fresh EXACT GENERIC → `enabled=false` (npd<0); any EXACT BRAND row → `enabled=true`. Report the table.

- [ ] **Step 4: Commit**

```bash
git add tools/strategy_profile/run.py tools/strategy_profile/derive.py
git commit --no-verify -m "feat(coach): classify intent in the run; re-derive per-intent profile + tag main keywords"
```

---

### Task 5: Steering part 1 — intent join in `V_ADS_COACH_DATA`

**Files:**
- Modify: `scripts/bigquery/views/V_ADS_COACH_DATA.sql`

- [ ] **Step 1: Locate the B-era profile join**

Run: `cd /Users/ori/Develop/OI && rg -n "DE_PRODUCT_STRATEGY_PROFILE|profile_season|profile_steers|profile_enabled" scripts/bigquery/views/V_ADS_COACH_DATA.sql`
Note the `psp` LEFT JOIN (added in sub-project B) and the `targeting`/`parent_name` aliases it uses.

- [ ] **Step 2: Join the intent class, and add intent to the profile join key**

Add a LEFT JOIN to `V_KEYWORD_INTENT_CLASS` keyed on the same parent + lower(targeting) the `psp` join uses, exposing `intent_class` (default GENERIC), and add `AND psp.intent_class = kic.intent_class` to the existing `psp` join:
```sql
  LEFT JOIN `onyga-482313.OI.V_KEYWORD_INTENT_CLASS` kic
    ON kic.parent_name = <parent_name_col> AND kic.keyword_text = LOWER(<targeting_col>)
```
and change the `psp` join's ON to also match intent:
```sql
   AND psp.intent_class = COALESCE(kic.intent_class, 'GENERIC')
```
Expose `COALESCE(kic.intent_class,'GENERIC') AS intent_class` and propagate it (plus the existing `profile_*` columns) through to the view output, same as the B columns. Replace `<parent_name_col>` / `<targeting_col>` with the real aliases from Step 1.

- [ ] **Step 3: Deploy + row parity**

Run:
```bash
cd /Users/ori/Develop/OI
bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/views/V_ADS_COACH_DATA.sql && echo OK
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=csv 'SELECT COUNT(*) FROM `onyga-482313.OI.V_ADS_COACH_DATA`'
```
Expected: `OK`; count unchanged vs before this task (capture it first). The intent join is one-class-per-keyword, and the profile join now matches on intent too — still many-to-one, so no fan-out. If the count grew, a keyword resolved >1 intent (V_KEYWORD_INTENT_CLASS must be unique per parent×keyword — verify) — fix before committing.

- [ ] **Step 4: Commit**

```bash
git add scripts/bigquery/views/V_ADS_COACH_DATA.sql
git commit --no-verify -m "feat(coach): join keyword intent_class + key profile by intent in V_ADS_COACH_DATA"
```

---

### Task 6: Steering part 2 — intent-aware suppression in `V_ADS_COACH`

**Files:**
- Modify: `scripts/bigquery/views/V_ADS_COACH.sql`

- [ ] **Step 1: Locate the B suppression guard**

Run: `cd /Users/ori/Develop/OI && rg -n "profile_enabled = FALSE|profile_steers|product_strategy|intent_class" scripts/bigquery/views/V_ADS_COACH.sql`
Find the `target_action` suppression branch added in sub-project B.

- [ ] **Step 2: Make suppression GENERIC-only; protect BRAND + PRODUCT**

Change the B suppression guard so it fires only for GENERIC intent. Replace the existing branch:
```sql
      WHEN d.intent_class = 'GENERIC'
           AND d.profile_enabled = FALSE AND d.profile_steers
           AND <the existing increase condition> THEN 'MONITOR_TARGET'
```
BRAND and PRODUCT rows therefore never hit the suppression branch (they keep their normal action, including INCREASE_BID). Update the decision-trace chip to include `d.intent_class`. Surface `d.intent_class` in the final SELECT.

- [ ] **Step 3: Deploy + validate intent-aware behavior**

Run:
```bash
cd /Users/ori/Develop/OI
bq --project_id=onyga-482313 query --use_legacy_sql=false < scripts/bigquery/views/V_ADS_COACH.sql && echo OK
bq --project_id=onyga-482313 query --use_legacy_sql=false 'CALL `onyga-482313.OI.SP_REFRESH_ADS_COACH_ACTIONS`()'
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty '
SELECT parent_name, intent_class,
  COUNTIF(UPPER(targeting_type)="EXACT" AND target_action="INCREASE_BID") AS exact_bid_ups
FROM `onyga-482313.OI.V_ADS_COACH`
WHERE parent_name IN ("LolliME","Lollibox","Fresh") AND strategy_id NOT IN ("BRAND_DEFENSE","PRODUCT_DEFENSE")
GROUP BY 1,2 ORDER BY 1,2'
```
Expected: for EXACT non-defense rows — `LolliME / PRODUCT` can have `exact_bid_ups > 0` (protected & scalable), `Lollibox / GENERIC` and `Fresh / GENERIC` show `0` (suppressed), and any BRAND rows are non-zero or untouched. Report the table.

- [ ] **Step 4: Validate parity + no regression**

Run:
```bash
bq --project_id=onyga-482313 query --use_legacy_sql=false --format=pretty '
SELECT
  COUNTIF(intent_class="GENERIC" AND profile_enabled=FALSE AND profile_steers AND target_action="INCREASE_BID"
          AND strategy_id NOT IN ("BRAND_DEFENSE","PRODUCT_DEFENSE")) AS generic_suppress_violations,
  COUNTIF(target_action="REDUCE_BID" AND current_bid IS NOT NULL AND recommended_bid > current_bid + 0.001) AS reduce_inversions
FROM `onyga-482313.OI.V_ADS_COACH`'
```
Expected: both `0`. (Row parity vs prior count also unchanged.)

- [ ] **Step 5: Commit**

```bash
git add scripts/bigquery/views/V_ADS_COACH.sql
git commit --no-verify -m "feat(coach): intent-aware suppression — GENERIC only; BRAND + PRODUCT protected"
```

---

## Review checkpoint (human)
After Task 6, stop and review with Ori:
- Spot-check `V_KEYWORD_INTENT_CLASS` per family (is PRODUCT/GENERIC sensible? any term to override via `DE_KEYWORD_INTENT_OVERRIDE`?).
- Confirm LolliME product-exact now keeps bid-ups and Lollibox generic-exact is suppressed.

## Notes / gotchas
- `V_KEYWORD_INTENT_CLASS` must be **unique per (parent_name, keyword_text)** — the `fit` and `anchor` CTEs are pre-aggregated/distinct and `brand` is a per-key EXISTS, so it is; verify with a `GROUP BY ... HAVING COUNT(*)>1` returning 0 rows if the row-parity check fails in Task 5.
- Suppression stays **GENERIC-only and CONCLUSIVE-only and non-defense**; band-clamp remains MANUAL-only (B's I1 de-risk).
- Re-run `SP_REFRESH_ADS_COACH_ACTIONS` after the view edits so `FACT_ADS_COACH_ACTIONS` reflects them; Cube `T_` tables refresh on their cycle.
- `.venv/bin/python` = OI root venv; `bq` authed for `onyga-482313`.
