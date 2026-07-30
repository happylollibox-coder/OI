#!/usr/bin/env python3
"""Grid plan Phase 1.2 — propose registry rows for EXISTING campaigns.

For every currently-spending manual campaign (EXACT / PHRASE / BROAD / SB video / SB store),
derive (product, intent, rung) by clicks-weighted majority over the campaign's own search
terms through DE_SEARCH_TERM_INTENT, and product by clicks-weighted majority ASIN.

Writes PROPOSALS ONLY to .tmp/intent_campaign_absorb_proposals.csv for Ori's review — nothing
is inserted into DE_INTENT_CAMPAIGN by this script. Apply confirmed rows with --apply after
review (reads the CSV back, inserts rows with admitted_reason='ABSORBED', state='ACTIVE',
campaign_id already numeric so no reconciliation needed).

Purity gate: a campaign is proposed only when its top intent carries >= --min-purity (default
0.60) of its intent-classified clicks. Below that it is listed in the LOW_PURITY section for
information but not proposed — absorbing a mixed hunter as a single-intent cell would lie.
"""
import argparse, csv, json, subprocess, sys, pathlib

PROJECT = "onyga-482313.OI"
OUT = pathlib.Path("/Users/ori/Develop/OI/.tmp/intent_campaign_absorb_proposals.csv")

def bq(sql: str):
    r = subprocess.run(["bq", "query", "--use_legacy_sql=false", "--format=json",
                        "--max_rows=5000", sql], capture_output=True, text=True, cwd="/tmp")
    if r.returncode != 0:
        sys.exit(f"bq failed:\n{r.stderr[-2000:]}")
    return json.loads(r.stdout) if r.stdout.strip() else []  # DML returns empty stdout

RUNG_SQL = """
WITH spend AS (  -- currently-spending campaigns, last 60d, with format + match majority
  SELECT campaign_id, ANY_VALUE(campaign_name HAVING MAX date) campaign_name,
    ANY_VALUE(campaign_type) campaign_type,
    APPROX_TOP_COUNT(targeting_type, 1)[OFFSET(0)].value top_match,
    SUM(Ads_cost) cost_60d
  FROM `{p}.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY) AND campaign_id IS NOT NULL
  GROUP BY campaign_id
  HAVING cost_60d > 5
),
term_intents AS (
  SELECT a.campaign_id, d.suggested_intent_key ik, SUM(a.Ads_clicks) clk
  FROM `{p}.FACT_AMAZON_ADS` a
  JOIN `{p}.DE_SEARCH_TERM_INTENT` d USING (search_term)
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
    AND IFNULL(d.suggested_intent_key,'') NOT IN ('','asin_target','auto_target')
  GROUP BY 1,2
),
intent_pick AS (
  SELECT campaign_id,
    ARRAY_AGG(STRUCT(ik, clk) ORDER BY clk DESC LIMIT 1)[OFFSET(0)].ik top_intent,
    ARRAY_AGG(STRUCT(ik, clk) ORDER BY clk DESC LIMIT 1)[OFFSET(0)].clk top_clk,
    SUM(clk) all_clk
  FROM term_intents GROUP BY 1
),
prod_pick AS (
  SELECT a.campaign_id,
    APPROX_TOP_COUNT(p2.product_short_name, 1)[OFFSET(0)].value product_short_name
  FROM `{p}.FACT_AMAZON_ADS` a
  JOIN `{p}.DIM_PRODUCT` p2 ON p2.asin = a.ASIN_BY_CAMPAIGN_NAME
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
  GROUP BY 1
)
SELECT s.campaign_id, s.campaign_name, s.campaign_type, s.top_match,
  ROUND(s.cost_60d,2) cost_60d,
  pp.product_short_name,
  ip.top_intent, ip.top_clk, ip.all_clk,
  ROUND(SAFE_DIVIDE(ip.top_clk, ip.all_clk), 3) purity
FROM spend s
LEFT JOIN intent_pick ip USING (campaign_id)
LEFT JOIN prod_pick  pp USING (campaign_id)
ORDER BY s.cost_60d DESC
"""

def rung_for(row):
    ct, tm = (row.get("campaign_type") or ""), (row.get("top_match") or "").upper()
    name = (row.get("campaign_name") or "").upper()
    if ct == "SB":
        return "BROAD_VIDEO" if "VIDEO" in name else "BROAD_SPOTLIGHT"
    if "EXACT" in tm: return "EXACT"
    if "PHRASE" in tm: return "PHRASE"
    if "BROAD" in tm: return "BROAD_SP"
    return None  # AUTO / PT — not grid rungs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-purity", type=float, default=0.60)
    ap.add_argument("--apply", action="store_true",
                    help="insert CONFIRMED rows from the reviewed CSV (confirm column = y)")
    args = ap.parse_args()

    if args.apply:
        rows = [r for r in csv.DictReader(OUT.open()) if r.get("confirm", "").lower() == "y"]
        if not rows:
            sys.exit("no rows with confirm=y in the CSV")
        # Idempotency guard: BigQuery has no PK enforcement and a bq CLI retry can double-run
        # a DML INSERT (it did, 2026-07-25). Never insert an id already registered.
        existing = {r2["campaign_id"] for r2 in bq(
            f"SELECT campaign_id FROM `{PROJECT}.DE_INTENT_CAMPAIGN`")}
        skipped = [r2["campaign_id"] for r2 in rows if r2["campaign_id"] in existing]
        rows = [r2 for r2 in rows if r2["campaign_id"] not in existing]
        if skipped:
            print(f"skipped {len(skipped)} already-registered ids: {skipped[:5]}...")
        if not rows:
            sys.exit("all confirmed rows already registered - nothing to do")
        values = ",\n".join(
            "('{cid}', '{name}', '{prod}', '{ik}', '{rung}', 'A', 'ACTIVE', 'ABSORBED', "
            "CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 'absorb_existing.py')".format(
                cid=r["campaign_id"], name=r["campaign_name"].replace("'", "\\'"),
                prod=r["product_short_name"], ik=r["proposed_intent"], rung=r["proposed_rung"])
            for r in rows)
        bq(f"""INSERT INTO `{PROJECT}.DE_INTENT_CAMPAIGN`
               (campaign_id, campaign_name_at_creation, product_short_name, intent_key, rung,
                tier, state, admitted_reason, created_at, updated_at, updated_by)
               VALUES {values}""")
        print(f"inserted {len(rows)} registry rows")
        return

    data = bq(RUNG_SQL.format(p=PROJECT))
    proposals, low_purity, skipped = [], [], 0
    for r in data:
        rung = rung_for(r)
        purity = float(r["purity"]) if r.get("purity") not in (None, "") else 0.0
        if rung is None or not r.get("top_intent") or not r.get("product_short_name"):
            skipped += 1
            continue
        row = {
            "confirm": "", "campaign_id": r["campaign_id"], "campaign_name": r["campaign_name"],
            "product_short_name": r["product_short_name"], "proposed_intent": r["top_intent"],
            "proposed_rung": rung, "purity": purity, "cost_60d": r["cost_60d"],
            "intent_clicks": r.get("top_clk"), "all_intent_clicks": r.get("all_clk"),
        }
        (proposals if purity >= args.min_purity else low_purity).append(row)

    OUT.parent.mkdir(exist_ok=True)
    with OUT.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(proposals[0].keys()))
        w.writeheader(); w.writerows(proposals)
        f.write("\n# LOW PURITY (informational, not proposed)\n")
        w.writerows(low_purity)
    print(f"{OUT}: {len(proposals)} proposals (purity>={args.min_purity}), "
          f"{len(low_purity)} low-purity listed, {skipped} skipped (AUTO/PT/no data)")
    print("review, set confirm=y on rows to absorb, then re-run with --apply")

if __name__ == "__main__":
    main()
