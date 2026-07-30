#!/usr/bin/env python3
"""Grid plan Phase 1.3 — Tier-A build bulksheet.

Builds the MISSING rungs (BROAD_SP, EXACT) for every Tier-A product x intent pair
(>= --min-clicks intent-attributed ad clicks in 12m, KEYWORD terms, brand excluded),
skipping rungs already covered in DE_INTENT_CAMPAIGN.

Per cell:
  EXACT  top-10 terms by SQP volume (fallback ads clicks), research rank > 75 gate,
         one owner per (intent, term) across the products being built (best value-per-click
         posterior wins; losers get negativeExact in their new Exact).
  BROAD  3-5 diverse phrasings (token-Jaccard <= 0.6); a seed may not STEM-match any
         exact-owned term of the SAME PRODUCT (any cell, new or absorbed) — those terms
         ship as negativeExact in every Broad of the product (graduation mechanism;
         stem matching because Amazon negatives hit close variants/plurals).

Bids = T_INTENT_BID_BASE target_bid for --bid-month (clamped 0.15..2.00 — GUARDIAN ceiling).
State: OFF and MARGINAL bands ship PAUSED (spec: OFF-unless-PROBE); cells OFF all 12 months
or missing a bid-model row are skipped; ENABLED cells whose month-7 band is OFF start Aug 1.
Portfolio ID = per-product majority portfolio from V_DIM_CAMPAIGN_CURRENT.
Family junk list ships campaign-level negativePhrase (validated 2026-07-24 format) with:
facet protection (a cell never negates its own intent words), converter override (>=3
orders/12m beats a colliding negative — brand tokens excepted), and the Amazon word caps
(phrases over 4 words become campaign-level negativeExact; over 10 words dropped).

Registry rows are inserted PENDING_UPLOAD (campaign_id = name placeholder) with an existence
guard — re-runs never double-insert. Audit written to .tmp/tier_a_build_audit.csv.
"""
import argparse, csv, json, re, subprocess, sys, pathlib

PROJECT = "onyga-482313.OI"
ROOT = pathlib.Path("/Users/ori/Develop/OI")
XLSX = ROOT / "exports/2026-07-25_tier_a_build_bulksheet.xlsx"
AUDIT = ROOT / ".tmp/tier_a_build_audit.csv"

PRODUCT_STYLE = {  # product_short_name -> (name prefix, variant token)
    "White Lollibox": ("BOX", "White"),
    "Purple LolliME": ("ME", "Purple"),
    "Fresh in Pink": ("FRESH", "Fresh"),
    "Truth Or Dare": ("BOTTLE", "Truth"),
    "Mint LolliME": ("MINT", "Mint"),
    "Blue Lollibox": ("BOX", "Blue"),
    "Pink Lollibox": ("BOX", "Pink"),
}
BID_FLOOR, BID_CEILING = 0.15, 2.00
# Brand negatives are doctrine (negate everywhere except defense) — no converter override.
BRAND_TOKENS = {"lolli", "lollibox", "lollime", "lolliball", "lollibunny", "lollipop", "happy"}
DAILY_BUDGET = "10.00"
START_DATE = "2026-07-26"

SP_H = ['Product','Entity','Operation','Campaign ID','Ad Group ID','Portfolio ID','Ad ID','Keyword ID',
 'Product Targeting ID','Campaign Name','Ad Group Name','Campaign Name (Informational only)',
 'Ad Group Name (Informational only)','Portfolio Name (Informational only)','Start Date','End Date',
 'Targeting Type','State','Campaign State (Informational only)','Ad Group State (Informational only)',
 'Daily Budget','SKU','ASIN (Informational only)','Eligibility Status (Informational only)',
 'Reason for Ineligibility (Informational only)','Ad Group Default Bid',
 'Ad Group Default Bid (Informational only)','Bid','Keyword Text','Native Language Keyword',
 'Native Language Locale','Match Type','Bidding Strategy','Placement','Percentage',
 'Product Targeting Expression','Resolved Product Targeting Expression (Informational only)']


def bq(sql: str):
    r = subprocess.run(["bq", "query", "--use_legacy_sql=false", "--format=json",
                        "--max_rows=100000", sql], capture_output=True, text=True, cwd="/tmp")
    if r.returncode != 0:
        sys.exit(f"bq failed (rc={r.returncode}):\nSTDERR: {r.stderr[-2000:]}\nSTDOUT: {r.stdout[-2000:]}\nSQL: {sql[:300]}")
    try:
        return json.loads(r.stdout) if r.stdout.strip() else []
    except json.JSONDecodeError:
        return []  # DML jobs print status text, not JSON


def stem(tok: str) -> str:
    if len(tok) > 3 and tok.endswith("es"):
        return tok[:-2]
    if len(tok) > 2 and tok.endswith("s"):
        return tok[:-1]
    return tok


def toklist(text: str):
    return [stem(t) for t in re.findall(r"[a-z0-9']+", text.lower())]


def tokens(term: str):
    return set(toklist(term))


def has_phrase(keyword: str, phrase: str) -> bool:
    """Stem-aware token containment: Amazon negatives match close variants (plurals)."""
    kw, ph = toklist(keyword), toklist(phrase)
    return bool(ph) and any(kw[i:i + len(ph)] == ph for i in range(len(kw) - len(ph) + 1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-clicks", type=int, default=5000)
    ap.add_argument("--bid-month", type=int, default=8)
    ap.add_argument("--dry-run", action="store_true", help="skip the registry insert")
    args = ap.parse_args()

    pairs = bq(f"""
    WITH prod AS (
      SELECT a.campaign_id, APPROX_TOP_COUNT(p.product_short_name,1)[OFFSET(0)].value prod
      FROM `{PROJECT}.FACT_AMAZON_ADS` a
      JOIN `{PROJECT}.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
      WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY) GROUP BY 1)
    SELECT pr.prod product_short_name, i.intent_key, SUM(a.Ads_clicks) clicks_12m
    FROM `{PROJECT}.FACT_AMAZON_ADS` a
    JOIN prod pr ON pr.campaign_id = a.campaign_id
    JOIN `{PROJECT}.V_INTENT_RESOLVED` i USING (search_term)
    WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
      AND i.intent_key NOT IN ("brand","asin_target","auto_target") AND i.term_kind = "KEYWORD"
    GROUP BY 1,2 HAVING clicks_12m >= {args.min_clicks}
    ORDER BY clicks_12m DESC""")

    coverage = {}
    for r in bq(f"SELECT product_short_name, intent_key, rung FROM `{PROJECT}.DE_INTENT_CAMPAIGN`"):
        coverage.setdefault((r["product_short_name"], r["intent_key"]), set()).add(r["rung"])

    prods = sorted({p["product_short_name"] for p in pairs})
    intents = sorted({p["intent_key"] for p in pairs})
    in_p = ",".join(f'"{x}"' for x in prods)
    in_i = ",".join(f'"{x}"' for x in intents)

    bands = {}  # (prod, intent) -> {month: row}
    for r in bq(f"""
    SELECT product_short_name, intent_key, month_of_year, target_bid, action, value_per_click,
           gp_per_order, base_cvr
    FROM `{PROJECT}.T_INTENT_BID_BASE`
    WHERE product_short_name IN ({in_p}) AND intent_key IN ({in_i})"""):
        bands.setdefault((r["product_short_name"], r["intent_key"]), {})[int(r["month_of_year"])] = r

    meta = {r["product_short_name"]: r for r in bq(f"""
    SELECT product_short_name, ANY_VALUE(sku) sku, ANY_VALUE(parent_name) parent_name
    FROM `{PROJECT}.DIM_PRODUCT` WHERE product_short_name IN ({in_p}) GROUP BY 1""")}

    cands = bq(f"""
    WITH prod AS (
      SELECT a.campaign_id, APPROX_TOP_COUNT(p.product_short_name,1)[OFFSET(0)].value prod
      FROM `{PROJECT}.FACT_AMAZON_ADS` a
      JOIN `{PROJECT}.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
      WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY) GROUP BY 1),
    ads AS (
      SELECT pr.prod, i.intent_key, a.search_term term,
             SUM(a.Ads_clicks) clicks, SUM(a.Ads_orders) orders
      FROM `{PROJECT}.FACT_AMAZON_ADS` a
      JOIN prod pr ON pr.campaign_id = a.campaign_id
      JOIN `{PROJECT}.V_INTENT_RESOLVED` i USING (search_term)
      WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
        AND pr.prod IN ({in_p}) AND i.intent_key IN ({in_i}) AND i.term_kind = "KEYWORD"
      GROUP BY 1,2,3),
    sqp AS (
      SELECT product_short_name prod, search_term term, SUM(impressions) sqp_impr
      FROM `{PROJECT}.V_SQP_ADS_BY_TERM`
      WHERE week_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
        AND product_short_name IN ({in_p})
      GROUP BY 1,2),
    research AS (
      SELECT parent_name, query_text term, MAX(rank) rank
      FROM `{PROJECT}.V_RESEARCH_RANKED` GROUP BY 1,2)
    SELECT a.prod, a.intent_key, a.term, a.clicks, a.orders,
           IFNULL(s.sqp_impr, 0) sqp_impr, r.rank
    FROM ads a
    LEFT JOIN sqp s ON s.prod = a.prod AND s.term = a.term
    LEFT JOIN `{PROJECT}.DIM_PRODUCT` dp ON dp.product_short_name = a.prod
    LEFT JOIN research r ON r.parent_name = dp.parent_name AND r.term = a.term""")

    existing_exact = {}  # (prod, intent) -> set of keyword texts in absorbed EXACT campaigns
    reg = bq(f"""SELECT campaign_id, product_short_name, intent_key FROM
                 `{PROJECT}.DE_INTENT_CAMPAIGN` WHERE rung = "EXACT" AND state = "ACTIVE" """)
    if reg:
        ids = ",".join(f'"{r["campaign_id"]}"' for r in reg)
        kw = bq(f"""
        SELECT CAST(campaign_id AS STRING) campaign_id, targeting, SUM(Ads_clicks) clk
        FROM `{PROJECT}.FACT_AMAZON_ADS`
        WHERE CAST(campaign_id AS STRING) IN ({ids})
          AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
          AND LOWER(IFNULL(targeting_type,"")) LIKE "%exact%" AND targeting IS NOT NULL
        GROUP BY 1,2""")
        by_camp = {}
        for k in kw:
            by_camp.setdefault(k["campaign_id"], set()).add(k["targeting"].lower())
        for r in reg:
            cell = (r["product_short_name"], r["intent_key"])
            existing_exact.setdefault(cell, set()).update(by_camp.get(r["campaign_id"], set()))

    port = {r["prod"]: r["portfolio_id"] for r in bq(f"""
    WITH prodmap AS (
      SELECT a.campaign_id, APPROX_TOP_COUNT(p.product_short_name,1)[OFFSET(0)].value prod
      FROM `{PROJECT}.FACT_AMAZON_ADS` a
      JOIN `{PROJECT}.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
      WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY) GROUP BY 1)
    SELECT pr.prod,
      APPROX_TOP_COUNT(CAST(c.portfolio_id AS STRING),1)[OFFSET(0)].value portfolio_id
    FROM `{PROJECT}.V_DIM_CAMPAIGN_CURRENT` c
    JOIN prodmap pr ON pr.campaign_id = CAST(c.campaign_id AS STRING)
    WHERE c.campaign_type = "SP" AND c.portfolio_id IS NOT NULL
    GROUP BY 1""", ) if r.get("portfolio_id")}

    negatives = {}  # parent_name -> [phrase]
    for r in bq(f"""SELECT effective_parent_name, phrase FROM `{PROJECT}.V_PRODUCT_PHRASE_NEGATIVES`
                    WHERE LOWER(match_type) LIKE "%phrase%" """):
        negatives.setdefault(r["effective_parent_name"], []).append(r["phrase"])

    live_names = {r["name"].lower() for r in bq(f"""
    SELECT DISTINCT ANY_VALUE(campaign_name HAVING MAX date) name
    FROM `{PROJECT}.FACT_AMAZON_ADS` WHERE campaign_id IS NOT NULL GROUP BY campaign_id""")}
    live_names |= {r["campaign_name_at_creation"].lower() for r in
                   bq(f"SELECT campaign_name_at_creation FROM `{PROJECT}.DE_INTENT_CAMPAIGN`")
                   if r.get("campaign_name_at_creation")}

    # ---- assemble cells --------------------------------------------------------------
    by_cell = {}
    for c in cands:
        by_cell.setdefault((c["prod"], c["intent_key"]), []).append(c)

    def protected_tokens(intent: str):
        """Facet tokens a cell may not negate: its own intent words.
        implied_low-* cells are DEFINED by stuff/things wording."""
        base = intent.replace("implied_low", "stuff things thing")
        return {stem(t) for t in re.findall(r"[a-z0-9]+", base.replace("-", " ").replace("_", " ").lower())}

    def post_value(c, prod, intent):
        b = bands.get((prod, intent), {}).get(args.bid_month, {})
        prior = float(b.get("base_cvr") or 0.02)
        gp = float(b.get("gp_per_order") or 10.0)
        k = 200
        return (int(c["orders"]) + k * prior) / (int(c["clicks"]) + k) * gp

    audit, skipped_cells, campaigns = [], [], []
    exact_sel = {}   # (prod,intent) -> [term rows]
    broad_sel = {}
    cell_pool = {}   # (prod,intent) -> negative-filtered candidate pool
    for p in pairs:
        prod, intent = p["product_short_name"], p["intent_key"]
        have = coverage.get((prod, intent), set())
        need = [r for r in ("BROAD_SP", "EXACT") if r not in have]
        if not need:
            continue
        cell_bands = bands.get((prod, intent), {})
        if not cell_bands or args.bid_month not in cell_bands:
            skipped_cells.append((prod, intent, "no bid-model row"))
            continue
        if all(m.get("action") == "OFF" for m in cell_bands.values()):
            skipped_cells.append((prod, intent, "OFF all 12 months"))
            continue
        if prod not in PRODUCT_STYLE or prod not in meta:
            skipped_cells.append((prod, intent, "unknown product style/sku"))
            continue
        pool = sorted(by_cell.get((prod, intent), []),
                      key=lambda c: (-int(c["sqp_impr"]), -int(c["clicks"])))
        # Family negatives veto candidates (Ori's deliberate list wins) — unless the
        # phrase is the cell's own defining facet, which a cell may never negate.
        protected = protected_tokens(intent)
        fam = sorted(set(negatives.get(meta[prod]["parent_name"], [])))
        kept, killed, overrode = [], [], []
        for c in pool:
            if not all(" " <= ch <= "~" for ch in c["term"]):
                continue  # non-ASCII artifacts (U+FFFC etc.) — Amazon rejects
            hit = next((ph for ph in fam
                        if not tokens(ph) <= protected and has_phrase(c["term"], ph)), None)
            if hit and int(c["orders"]) >= 3 and not (tokens(hit) & BRAND_TOKENS):
                # Ori's BTS precedent: a proven converter overrides the family negative
                # (the colliding phrase is dropped from this campaign only, at emit time).
                overrode.append(f"{c['term']} ({c['orders']} ord, neg: {hit})")
                kept.append(c)
            elif hit:
                killed.append(f"{c['term']} [neg: {hit}]")
            else:
                kept.append(c)
        if overrode:
            audit.append({"cell": f"{prod}|{intent}", "rung": "*",
                          "event": "CONVERTER_OVERRIDES_NEGATIVE",
                          "detail": "; ".join(overrode[:8]) + (" ..." if len(overrode) > 8 else "")})
        if killed:
            audit.append({"cell": f"{prod}|{intent}", "rung": "*",
                          "event": "CANDIDATE_VETOED_BY_NEGATIVE",
                          "detail": "; ".join(killed[:8]) + (" ..." if len(killed) > 8 else "")})
        cell_pool[(prod, intent)] = kept
        if "EXACT" in need:
            gated = [c for c in kept if c.get("rank") not in (None, "") and float(c["rank"]) > 75]
            exact_sel[(prod, intent)] = gated[:10]
        campaigns.append({"prod": prod, "intent": intent, "need": need})

    # ---- self-competition: one owner per (intent, term) across built Exacts ----------
    owner = {}
    for (prod, intent), terms in exact_sel.items():
        for c in terms:
            key = (intent, c["term"].lower())
            val = post_value(c, prod, intent)
            if key not in owner or val > owner[key][1]:
                owner[key] = (prod, val)
    loser_negatives = {}  # (prod,intent) -> [term]
    for (prod, intent), terms in list(exact_sel.items()):
        keep, lose = [], []
        for c in terms:
            (keep if owner[(intent, c["term"].lower())][0] == prod else lose).append(c)
        exact_sel[(prod, intent)] = keep
        if lose:
            loser_negatives[(prod, intent)] = [c["term"] for c in lose]

    # ---- Broad seeds AFTER exact ownership: ANY exact-owned term of the SAME PRODUCT
    # (new or absorbed, any intent cell) may not seed a Broad — sibling cells must not
    # argue with each other; exact terms live in exactly one Exact campaign.
    product_exact = {}
    for (pr2, _i2), terms in exact_sel.items():
        product_exact.setdefault(pr2, set()).update(k["term"].lower() for k in terms)
    for (pr2, _i2), terms in existing_exact.items():
        product_exact.setdefault(pr2, set()).update(terms)
    # Ban by STEM form: Amazon close-variant matching means the plural of an exact-owned
    # term would be blocked by its own graduation negativeExact.
    stemkey = lambda t: " ".join(toklist(t))
    product_exact_stems = {pr4: {stemkey(t) for t in ts} for pr4, ts in product_exact.items()}
    for c in campaigns:
        if "BROAD_SP" not in c["need"]:
            continue
        prod, intent = c["prod"], c["intent"]
        banned = product_exact_stems.get(prod, set())
        picked = []
        for cand in cell_pool.get((prod, intent), []):
            if len(picked) >= 5:
                break
            if stemkey(cand["term"]) in banned:
                continue
            tk = tokens(cand["term"])
            if any(len(tk & tokens(x["term"])) / max(1, len(tk | tokens(x["term"]))) > 0.6
                   for x in picked):
                continue
            picked.append(cand)
        broad_sel[(prod, intent)] = picked

    # ---- emit rows -------------------------------------------------------------------
    def sp(entity, cname, **kw):
        row = {h: "" for h in SP_H}
        row.update({"Product": "Sponsored Products", "Entity": entity, "Operation": "Create",
                    "Campaign ID": cname, "Campaign Name": cname})
        row.update(kw)
        return row

    rows, registry_rows, name_seen = [], [], set()
    converted_long, dropped_long = set(), set()
    for c in campaigns:
        prod, intent = c["prod"], c["intent"]
        prefix, var = PRODUCT_STYLE[prod]
        sku = meta[prod]["sku"]
        parent = meta[prod]["parent_name"]
        b = bands.get((prod, intent), {}).get(args.bid_month, {})
        band = b.get("action") or "RUN"
        bid = min(max(float(b.get("target_bid") or 0.40), BID_FLOOR), BID_CEILING)
        state = "PAUSED" if band in ("OFF", "MARGINAL") else "ENABLED"
        # TIME_BASED cells are date-triggered (DIM_US_HOLIDAYS), not band-triggered: they
        # ship PAUSED and the month plan issues the resume at boost_start. Jul-Aug christmas
        # terms: 1,377 clicks / 6 orders — off-season holiday traffic converts near zero.
        HOLIDAY_TOKENS = ("christmas", "easter", "valentine", "halloween", "school",
                          "mothers-day", "black-friday")
        if any(tok in intent for tok in HOLIDAY_TOKENS):
            state = "PAUSED"
        jul = (bands.get((prod, intent), {}).get(7, {}) or {}).get("action")
        start = "2026-08-01" if (state == "ENABLED" and jul == "OFF") else START_DATE
        for rung in c["need"]:
            label = "BROAD" if rung == "BROAD_SP" else "EXACT"
            kws = (broad_sel if rung == "BROAD_SP" else exact_sel).get((prod, intent), [])
            if not kws:
                audit.append({"cell": f"{prod}|{intent}", "rung": rung, "event": "SKIPPED_NO_KEYWORDS",
                              "detail": "no candidates survived gates"})
                continue
            cname = f"{prefix}-SP/{label} ({intent}, {var})"
            n = 1
            while cname.lower() in live_names or cname.lower() in name_seen:
                n += 1
                cname = f"{prefix}-SP/{label} ({intent}, {var} {n})"
            name_seen.add(cname.lower())
            ag = f"{intent} {var}"
            bidstr = f"{bid:.2f}"
            rows.append(sp("Campaign", cname, **{"Start Date": start, "Targeting Type": "MANUAL",
                        "Portfolio ID": port.get(prod, ""),
                        "State": state, "Daily Budget": DAILY_BUDGET,
                        "Bidding Strategy": "Dynamic bids - down only"}))
            rows.append(sp("Ad Group", cname, **{"Ad Group ID": ag, "Ad Group Name": ag,
                        "State": "ENABLED", "Ad Group Default Bid": bidstr}))
            rows.append(sp("Product Ad", cname, **{"Ad Group ID": ag, "Ad Group Name": ag,
                        "State": "ENABLED", "SKU": sku}))
            for k in kws:
                rows.append(sp("Keyword", cname, **{"Ad Group ID": ag, "Ad Group Name": ag,
                            "State": "ENABLED", "Bid": bidstr, "Keyword Text": k["term"],
                            "Match Type": label}))
            neg_exact = set()
            if rung == "BROAD_SP":  # graduation mechanism: exact terms out of broad
                neg_exact |= product_exact.get(prod, set())
            else:
                neg_exact |= {t.lower() for t in loser_negatives.get((prod, intent), [])}
            own_kw = {k["term"].lower() for k in kws}
            for t in sorted(neg_exact - own_kw):
                rows.append(sp("Negative Keyword", cname, **{"Ad Group ID": ag, "Ad Group Name": ag,
                            "State": "ENABLED", "Keyword Text": t, "Match Type": "negativeExact"}))
            protected = protected_tokens(intent)
            dropped_protected, dropped_conflict = [], []
            for ph in sorted(set(negatives.get(parent, []))):
                if tokens(ph) <= protected:  # never negate the cell's own facet words
                    dropped_protected.append(ph)
                    continue
                if any(has_phrase(k["term"], ph) for k in kws):  # converter override
                    dropped_conflict.append(ph)
                    continue
                wc = len(ph.split())
                if wc > 4:  # Amazon caps negativePhrase at 4 words (negativeExact at 10)
                    if wc <= 10:
                        rows.append(sp("Campaign Negative Keyword", cname, **{"State": "ENABLED",
                                    "Keyword Text": ph, "Match Type": "negativeExact"}))
                        converted_long.add(ph)
                    else:
                        dropped_long.add(ph)
                    continue
                rows.append(sp("Campaign Negative Keyword", cname, **{"State": "ENABLED",
                            "Keyword Text": ph, "Match Type": "negativePhrase"}))
            if dropped_protected:
                audit.append({"cell": f"{prod}|{intent}", "rung": rung,
                              "event": "NEG_PHRASE_PROTECTED",
                              "detail": "; ".join(dropped_protected)})
            if dropped_conflict:
                audit.append({"cell": f"{prod}|{intent}", "rung": rung,
                              "event": "NEG_PHRASE_DROPPED_FOR_CONVERTER",
                              "detail": "; ".join(dropped_conflict)})
            audit.append({"cell": f"{prod}|{intent}", "rung": rung, "event": "BUILT",
                          "detail": f"{cname} | band={band} bid={bidstr} state={state} "
                                    f"kw={len(kws)} negExact={len(neg_exact - own_kw)}"})
            registry_rows.append((cname, prod, intent, rung))

    if not rows:
        sys.exit("nothing to build (all Tier-A rungs already covered in the registry) — "
                 "workbook NOT overwritten")
    from openpyxl import Workbook
    wb = Workbook(); wb.remove(wb.active)
    ws = wb.create_sheet("Sponsored Products Campaigns")
    ws.append(SP_H)
    for r in rows:
        ws.append([r[h] for h in SP_H])
    ws.freeze_panes = "A2"
    XLSX.parent.mkdir(exist_ok=True)
    wb.save(XLSX)

    for pr3, it3, why in skipped_cells:
        audit.append({"cell": f"{pr3}|{it3}", "rung": "*", "event": "CELL_SKIPPED", "detail": why})
    if converted_long:
        audit.append({"cell": "*", "rung": "*", "event": "NEG_PHRASE_TO_EXACT_4WORD_CAP",
                      "detail": "; ".join(sorted(converted_long))})
    if dropped_long:
        audit.append({"cell": "*", "rung": "*", "event": "NEG_DROPPED_OVER_10_WORDS",
                      "detail": "; ".join(sorted(dropped_long))})
    AUDIT.parent.mkdir(exist_ok=True)
    with AUDIT.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["cell", "rung", "event", "detail"])
        w.writeheader(); w.writerows(audit)

    if not args.dry_run and registry_rows:
        existing = {r["campaign_id"] for r in
                    bq(f"SELECT campaign_id FROM `{PROJECT}.DE_INTENT_CAMPAIGN`")}
        todo = [r for r in registry_rows if r[0] not in existing]
        if todo:
            values = ",\n".join(
                f"(\"{n}\", \"{n}\", \"{p}\", \"{i}\", \"{ru}\", 'A', 'PENDING_UPLOAD', "
                f"'TIER_A_BUILD', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 'build_tier_a.py')"
                for n, p, i, ru in todo)
            bq(f"""INSERT INTO `{PROJECT}.DE_INTENT_CAMPAIGN`
                   (campaign_id, campaign_name_at_creation, product_short_name, intent_key, rung,
                    tier, state, admitted_reason, created_at, updated_at, updated_by)
                   VALUES {values}""")
        print(f"registry: {len(todo)} inserted PENDING_UPLOAD, {len(registry_rows)-len(todo)} already present")

    n_camp = sum(1 for r in rows if r["Entity"] == "Campaign")
    print(f"{XLSX.name}: {n_camp} campaigns, {len(rows)} rows")
    for prod_i, intent_i, why in skipped_cells:
        print(f"  skipped cell: {prod_i} | {intent_i} — {why}")
    print(f"audit: {AUDIT}")


if __name__ == "__main__":
    main()
