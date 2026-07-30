#!/usr/bin/env python3
"""Absorb AUTO and COMPETITOR-PT campaigns into DE_INTENT_CAMPAIGN (SOP extension 2026-07-25).

AUTO  = campaigns whose clicks are majority auto clauses (close-match/loose-match/
        substitutes/complements) -> rung='AUTO', intent_key='discovery' (per-product
        discovery unit; never an intent cell).
PT    = campaigns with majority spend on competitor-ASIN product targeting
        (targeting LIKE 'asin="..."', excluding OWN ASINs) -> rung='PT_ASIN',
        intent_key='competitor' (cells live at target grain inside; registry row is
        the campaign, key = numeric campaign_id).

Same supervised flow as absorb_existing.py: writes PROPOSALS ONLY to
.tmp/intent_auto_pt_absorb_proposals.csv for Ori's review (spend/CVR columns included);
--apply inserts confirm=y rows with an existence guard (state='ACTIVE',
admitted_reason='ABSORBED'). Own-ASIN defense PT campaigns are excluded by construction.
"""
import argparse, csv, json, subprocess, sys, pathlib

PROJECT = "onyga-482313.OI"
OUT = pathlib.Path("/Users/ori/Develop/OI/.tmp/intent_auto_pt_absorb_proposals.csv")


def bq(sql):
    r = subprocess.run(["bq", "query", "--use_legacy_sql=false", "--format=json",
                        "--max_rows=5000", sql], capture_output=True, text=True, cwd="/tmp")
    if r.returncode != 0:
        sys.exit(f"bq failed:\n{r.stderr[-2000:]}\n{r.stdout[-1000:]}")
    try:
        return json.loads(r.stdout) if r.stdout.strip() else []
    except json.JSONDecodeError:
        return []


SQL = f"""
WITH own AS (SELECT asin FROM `{PROJECT}.DIM_PRODUCT` WHERE parent_name IS NOT NULL),
prodmap AS (
  SELECT a.campaign_id, APPROX_TOP_COUNT(p.product_short_name,1)[OFFSET(0)].value prod
  FROM `{PROJECT}.FACT_AMAZON_ADS` a
  JOIN `{PROJECT}.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
  GROUP BY 1),
agg AS (
  SELECT CAST(a.campaign_id AS STRING) campaign_id,
    ANY_VALUE(a.campaign_name HAVING MAX a.date) campaign_name,
    ANY_VALUE(pr.prod) prod,
    SUM(a.Ads_cost) cost_12m, SUM(a.Ads_clicks) clicks_12m, SUM(a.Ads_orders) orders_12m,
    SUM(IF(LOWER(a.targeting) IN ("close-match","loose-match","substitutes","complements"),
           a.Ads_clicks, 0)) auto_clicks,
    SUM(IF(STARTS_WITH(LOWER(a.targeting), "asin=")
           AND UPPER(REGEXP_EXTRACT(a.targeting, r'(?i)asin="([A-Z0-9]+)"'))
               NOT IN (SELECT asin FROM own),
           a.Ads_cost, 0)) comp_pt_cost
  FROM `{PROJECT}.FACT_AMAZON_ADS` a
  JOIN prodmap pr ON pr.campaign_id = a.campaign_id
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
  GROUP BY 1
  HAVING cost_12m > 5)
SELECT *,
  SAFE_DIVIDE(auto_clicks, clicks_12m) auto_share,
  SAFE_DIVIDE(comp_pt_cost, cost_12m) comp_share,
  ROUND(SAFE_DIVIDE(orders_12m, clicks_12m), 4) cvr
FROM agg
WHERE SAFE_DIVIDE(auto_clicks, clicks_12m) > 0.5
   OR SAFE_DIVIDE(comp_pt_cost, cost_12m) > 0.5
ORDER BY cost_12m DESC"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    if args.apply:
        rows = [r for r in csv.DictReader(OUT.open()) if r.get("confirm", "").lower() == "y"]
        if not rows:
            sys.exit("no rows with confirm=y")
        existing = {r["campaign_id"] for r in
                    bq(f"SELECT campaign_id FROM `{PROJECT}.DE_INTENT_CAMPAIGN`")}
        rows = [r for r in rows if r["campaign_id"] not in existing]
        if not rows:
            sys.exit("all confirmed rows already registered")
        values = ",\n".join(
            '("{cid}", "{name}", "{prod}", "{ik}", "{rung}", \'A\', \'ACTIVE\', \'ABSORBED\', '
            "CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 'absorb_auto_pt.py')".format(
                cid=r["campaign_id"], name=r["campaign_name"].replace('"', ''),
                prod=r["product_short_name"], ik=r["proposed_intent"], rung=r["proposed_rung"])
            for r in rows)
        bq(f"""INSERT INTO `{PROJECT}.DE_INTENT_CAMPAIGN`
               (campaign_id, campaign_name_at_creation, product_short_name, intent_key, rung,
                tier, state, admitted_reason, created_at, updated_at, updated_by)
               VALUES {values}""")
        print(f"inserted {len(rows)} registry rows")
        return

    data = bq(SQL)
    props = []
    for r in data:
        is_auto = float(r["auto_share"] or 0) > 0.5
        props.append({
            "confirm": "", "campaign_id": r["campaign_id"], "campaign_name": r["campaign_name"],
            "product_short_name": r["prod"],
            "proposed_intent": "discovery" if is_auto else "competitor",
            "proposed_rung": "AUTO" if is_auto else "PT_ASIN",
            "cost_12m": round(float(r["cost_12m"]), 2), "clicks_12m": r["clicks_12m"],
            "orders_12m": r["orders_12m"], "cvr": r["cvr"],
            "auto_share": round(float(r["auto_share"] or 0), 2),
            "comp_share": round(float(r["comp_share"] or 0), 2)})
    OUT.parent.mkdir(exist_ok=True)
    with OUT.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(props[0].keys()))
        w.writeheader(); w.writerows(props)
    n_auto = sum(1 for p in props if p["proposed_rung"] == "AUTO")
    print(f"{OUT}: {len(props)} proposals ({n_auto} AUTO, {len(props)-n_auto} PT_ASIN)")
    print("review, set confirm=y, re-run with --apply")


if __name__ == "__main__":
    main()
