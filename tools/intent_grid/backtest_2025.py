#!/usr/bin/env python3
"""2025 walk-forward backtest of the intent-grid system (cockpit + coacher).

COCKPIT (monthly, cell = product x intent): for each 2025 month M the model is refit on
data STRICTLY BEFORE M (no look-ahead): shrunk base CVR (k=200 to the intent prior),
season index (intent-pooled, k=500 shrink), value_per_click = cvr_hat x gp_per_order,
target_bid = 0.70 x value, bands vs prior-28d market CPC (RUN >=1.1 / VELOCITY 0.7-1.1 /
MARGINAL 0.5-0.7 / OFF <0.5). Advice is then scored against what REALLY happened in M:
  - agreement: OFF advice vs cell actually dark; RUN advice vs cell actually running
  - predictive hit: did realized net ROAS land in the advised band (cells >=30 clicks)
  - profit delta (conservative counterfactual):
      OFF/MARGINAL  -> counterfactual NP = 0, delta = -actual_NP
      RUN/VELOCITY  -> if actual CPC > band cap c: clicks scale linearly to c,
                       orders follow clicks, delta = NP' - NP. If actual <= cap: delta 0
                       (upside from raising bids is NOT credited - unverifiable).

COACH (weekly, term grain, executes the cockpit plan): 1000 scenarios of
(strategy x intent x product x keyword) = top-600 by 2025 clicks + 400 deterministic
pseudo-random (FARM_FINGERPRINT) from the >=20-click remainder. Weekly walk of 2025:
  NEGATE  trailing-4w clicks >= 15 AND orders = 0 (search-term doctrine, once)
  RAISE   trailing-1w ROAS >= 1.1 with orders (cap: cockpit max_cpc_run)
  PROBE   cumulative clicks < 4 after >= 2 active weeks (bid +5%)
  HOLD    otherwise (no loss-driven cuts - 2026-07-21 doctrine)
Each NEGATE is scored on the term's REAL forward tail: saved = fwd_cost - fwd_GP
(positive = right call), and "matched reality" if actual spend died within 4 weeks anyway.
RAISE scored by next-4w realized ROAS holding >= 1.1; PROBE by whether the term reached
4+ clicks in the next 8 weeks and converted.

Outputs in .tmp/: backtest_cell_month.json (cache), backtest_cockpit_advice.csv,
backtest_cockpit_scorecard.txt, backtest_coach_actions.csv, backtest_coach_scorecard.txt.
GP/order is the CURRENT product-level figure (margin structure assumed stable - stated
simplification; CVR/season/market are the walk-forward parts).
"""
import csv, json, pathlib, subprocess, sys
from collections import defaultdict

PROJECT = "onyga-482313.OI"
ROOT = pathlib.Path("/Users/ori/Develop/OI")
TMP = ROOT / ".tmp"
K_BASE, K_SEASON = 200, 500
ROAS_RUN, ROAS_VEL, ROAS_MARGINAL = 1.1, 0.7, 0.5
PROFIT_SHARE = 0.70
MIN_CLICKS_SCORE = 30


def bq(sql, tag):
    cache = TMP / f"backtest_cache_{tag}.json"
    if cache.exists():
        return json.loads(cache.read_text())
    r = subprocess.run(["bq", "query", "--use_legacy_sql=false", "--format=json",
                        "--max_rows=1000000", sql], capture_output=True, text=True, cwd="/tmp")
    if r.returncode != 0:
        sys.exit(f"bq failed [{tag}]:\n{r.stderr[-1500:]}\n{r.stdout[-1500:]}")
    data = json.loads(r.stdout) if r.stdout.strip() else []
    cache.write_text(json.dumps(data))
    return data


F = lambda v: float(v) if v not in (None, "") else 0.0
I = lambda v: int(v) if v not in (None, "") else 0


def main():
    TMP.mkdir(exist_ok=True)

    gp_rows = bq(f"""
    SELECT product_short_name, APPROX_QUANTILES(gp_per_order, 2)[OFFSET(1)] gp
    FROM `{PROJECT}.T_INTENT_BID_BASE` WHERE NOT gp_is_family_fallback
    GROUP BY 1""", "gp")
    GP = {r["product_short_name"]: F(r["gp"]) for r in gp_rows}

    cm = bq(f"""
    WITH prodmap AS (
      SELECT a.campaign_id, APPROX_TOP_COUNT(p.product_short_name,1)[OFFSET(0)].value prod
      FROM `{PROJECT}.FACT_AMAZON_ADS` a
      JOIN `{PROJECT}.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
      GROUP BY 1),
    base AS (
      SELECT pr.prod, i.intent_key, a.date,
             SUM(a.Ads_clicks) clicks, SUM(a.Ads_orders) orders, SUM(a.Ads_cost) cost
      FROM `{PROJECT}.FACT_AMAZON_ADS` a
      JOIN prodmap pr USING (campaign_id)
      JOIN `{PROJECT}.V_INTENT_RESOLVED` i USING (search_term)
      WHERE i.term_kind = "KEYWORD"
        AND i.intent_key NOT IN ("brand","asin_target","auto_target")
        AND a.date < "2026-01-01"
      GROUP BY 1,2,3),
    months AS (SELECT m FROM UNNEST(GENERATE_DATE_ARRAY("2025-01-01","2025-12-01",
                                                        INTERVAL 1 MONTH)) m),
    cellmonth AS (
      SELECT mo.m, b.prod, b.intent_key,
        SUM(IF(b.date < mo.m, b.clicks, 0)) hist_clicks,
        SUM(IF(b.date < mo.m, b.orders, 0)) hist_orders,
        SUM(IF(DATE_TRUNC(b.date, MONTH) = mo.m, b.clicks, 0)) real_clicks,
        SUM(IF(DATE_TRUNC(b.date, MONTH) = mo.m, b.orders, 0)) real_orders,
        SUM(IF(DATE_TRUNC(b.date, MONTH) = mo.m, b.cost, 0)) real_cost,
        SUM(IF(b.date >= DATE_SUB(mo.m, INTERVAL 28 DAY) AND b.date < mo.m, b.cost, 0)) p28_cost,
        SUM(IF(b.date >= DATE_SUB(mo.m, INTERVAL 28 DAY) AND b.date < mo.m, b.clicks, 0)) p28_clicks
      FROM months mo CROSS JOIN base b
      GROUP BY 1,2,3
      HAVING hist_clicks >= 100 OR real_clicks >= 10),
    intent_asof AS (
      SELECT mo.m, b.intent_key,
        SUM(IF(b.date < mo.m, b.clicks, 0)) i_clicks,
        SUM(IF(b.date < mo.m, b.orders, 0)) i_orders,
        SUM(IF(b.date < mo.m AND EXTRACT(MONTH FROM b.date) = EXTRACT(MONTH FROM mo.m),
               b.clicks, 0)) i_m_clicks,
        SUM(IF(b.date < mo.m AND EXTRACT(MONTH FROM b.date) = EXTRACT(MONTH FROM mo.m),
               b.orders, 0)) i_m_orders
      FROM months mo CROSS JOIN base b GROUP BY 1,2),
    glob AS (
      SELECT mo.m, SUM(IF(b.date < mo.m, b.clicks, 0)) g_clicks,
             SUM(IF(b.date < mo.m, b.orders, 0)) g_orders
      FROM months mo CROSS JOIN base b GROUP BY 1)
    SELECT cm.*, ia.i_clicks, ia.i_orders, ia.i_m_clicks, ia.i_m_orders,
           g.g_clicks, g.g_orders
    FROM cellmonth cm
    JOIN intent_asof ia ON ia.m = cm.m AND ia.intent_key = cm.intent_key
    JOIN glob g ON g.m = cm.m
    ORDER BY cm.prod, cm.intent_key, cm.m""", "cellmonth")

    advice_rows, agg = [], defaultdict(lambda: defaultdict(float))
    for r in cm:
        prod, intent, m = r["prod"], r["intent_key"], r["m"]
        gp = GP.get(prod)
        if not gp:
            continue
        g_cvr = F(r["g_orders"]) / max(1, I(r["g_clicks"]))
        i_cvr = (I(r["i_orders"]) + K_BASE * g_cvr) / (I(r["i_clicks"]) + K_BASE)
        base_cvr = (I(r["hist_orders"]) + K_BASE * i_cvr) / (I(r["hist_clicks"]) + K_BASE)
        if I(r["i_clicks"]) > 0:
            i_all = F(r["i_orders"]) / I(r["i_clicks"])
            w = I(r["i_m_clicks"]) / (I(r["i_m_clicks"]) + K_SEASON)
            i_m = (F(r["i_m_orders"]) / max(1, I(r["i_m_clicks"]))) if I(r["i_m_clicks"]) else i_all
            season = (w * i_m + (1 - w) * i_all) / i_all if i_all > 0 else 1.0
        else:
            season = 1.0
        season = min(max(season, 0.4), 2.5)
        cvr_hat = base_cvr * season
        value = cvr_hat * gp
        target_bid = round(PROFIT_SHARE * value, 2)
        max_run, max_vel = value / ROAS_RUN, value / ROAS_VEL
        market = F(r["p28_cost"]) / I(r["p28_clicks"]) if I(r["p28_clicks"]) >= 20 else None
        exp_roas = value / market if market else None
        if exp_roas is None:
            band = "RUN"
        elif exp_roas >= ROAS_RUN:
            band = "RUN"
        elif exp_roas >= ROAS_VEL:
            band = "VELOCITY"
        elif exp_roas >= ROAS_MARGINAL:
            band = "MARGINAL"
        else:
            band = "OFF"

        rc, ro, rcost = I(r["real_clicks"]), I(r["real_orders"]), F(r["real_cost"])
        real_np = ro * gp - rcost
        real_roas = (ro * gp) / rcost if rcost > 0 else None
        real_cpc = rcost / rc if rc else None

        if band in ("OFF", "MARGINAL"):
            delta = -real_np
        else:
            cap = max_run if band == "RUN" else max_vel
            if real_cpc and real_cpc > cap and rc:
                scale = cap / real_cpc
                delta = (ro * scale * gp - rc * scale * cap) - real_np
            else:
                delta = 0.0

        hit = None
        if rc >= MIN_CLICKS_SCORE and real_roas is not None:
            hit = {"RUN": real_roas >= ROAS_RUN,
                   "VELOCITY": ROAS_VEL <= real_roas < ROAS_RUN,
                   "MARGINAL": ROAS_MARGINAL <= real_roas < ROAS_VEL,
                   "OFF": real_roas < ROAS_MARGINAL}[band]
        agree = None
        if band == "OFF":
            agree = rcost < 5
        elif band == "RUN" and I(r["hist_clicks"]) >= 100:
            agree = rcost >= 5

        advice_rows.append({
            "month": m, "product": prod, "intent": intent, "band": band,
            "target_bid": target_bid, "max_cpc_run": round(max_run, 2),
            "cvr_hat": round(cvr_hat, 4), "season": round(season, 3),
            "market_cpc": round(market, 2) if market else "",
            "exp_roas": round(exp_roas, 2) if exp_roas else "",
            "real_clicks": rc, "real_orders": ro, "real_cost": round(rcost, 2),
            "real_roas": round(real_roas, 2) if real_roas is not None else "",
            "real_np": round(real_np, 2), "profit_delta": round(delta, 2),
            "band_hit": "" if hit is None else int(hit),
            "agrees_with_reality": "" if agree is None else int(agree)})
        a = agg[band]
        a["n"] += 1
        a["delta"] += delta
        if hit is not None:
            a["hit_n"] += 1
            a["hit_y"] += int(hit)
        if agree is not None:
            a["agr_n"] += 1
            a["agr_y"] += int(agree)

    with (TMP / "backtest_cockpit_advice.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(advice_rows[0].keys()))
        w.writeheader(); w.writerows(advice_rows)

    lines = ["COCKPIT SCORECARD (cell-month advice, walk-forward 2025)", ""]
    tot_delta = sum(a["delta"] for a in agg.values())
    for band in ("RUN", "VELOCITY", "MARGINAL", "OFF"):
        a = agg[band]
        hit = f"{a['hit_y']/a['hit_n']:.0%} of {int(a['hit_n'])}" if a["hit_n"] else "n/a"
        agr = f"{a['agr_y']/a['agr_n']:.0%} of {int(a['agr_n'])}" if a["agr_n"] else "n/a"
        lines.append(f"{band:9s} n={int(a['n']):5d}  band-hit={hit:14s} "
                     f"matches-reality={agr:14s} profit-delta=${a['delta']:+,.0f}")
    lines += ["", f"TOTAL profit delta vs what actually happened: ${tot_delta:+,.0f}",
              "(conservative: raising-bid upside never credited; OFF credit = avoided NP)"]
    (TMP / "backtest_cockpit_scorecard.txt").write_text("\n".join(lines))
    print("\n".join(lines))

    # ---------------- COACH ----------------
    tw = bq(f"""
    WITH prodmap AS (
      SELECT a.campaign_id, APPROX_TOP_COUNT(p.product_short_name,1)[OFFSET(0)].value prod
      FROM `{PROJECT}.FACT_AMAZON_ADS` a
      JOIN `{PROJECT}.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
      GROUP BY 1),
    term_year AS (
      SELECT pr.prod, i.intent_key, a.search_term term,
        APPROX_TOP_COUNT(CONCAT(IFNULL(a.campaign_type,"SP"), "/",
                                IFNULL(a.targeting_type,"?")), 1)[OFFSET(0)].value strategy,
        SUM(IF(a.date BETWEEN "2025-01-01" AND "2025-12-31", a.Ads_clicks, 0)) clicks25
      FROM `{PROJECT}.FACT_AMAZON_ADS` a
      JOIN prodmap pr USING (campaign_id)
      JOIN `{PROJECT}.V_INTENT_RESOLVED` i USING (search_term)
      WHERE i.term_kind = "KEYWORD"
        AND i.intent_key NOT IN ("brand","asin_target","auto_target")
      GROUP BY 1,2,3
      HAVING clicks25 >= 20),
    ranked AS (
      SELECT *, ROW_NUMBER() OVER (ORDER BY clicks25 DESC) rk,
             ROW_NUMBER() OVER (ORDER BY FARM_FINGERPRINT(CONCAT(prod, term))) rnd
      FROM term_year),
    sample AS (
      SELECT * FROM ranked WHERE rk <= 600
      UNION ALL
      SELECT * FROM (SELECT * FROM ranked WHERE rk > 600 ORDER BY rnd LIMIT 400)),
    weekly AS (
      SELECT pr.prod, a.search_term term, DATE_TRUNC(a.date, WEEK(SUNDAY)) wk,
             SUM(a.Ads_clicks) clicks, SUM(a.Ads_orders) orders, SUM(a.Ads_cost) cost
      FROM `{PROJECT}.FACT_AMAZON_ADS` a
      JOIN prodmap pr USING (campaign_id)
      WHERE a.date BETWEEN "2024-12-01" AND "2025-12-31"
      GROUP BY 1,2,3)
    SELECT s.prod, s.intent_key, s.term, s.strategy, s.clicks25, s.rk,
           w.wk, w.clicks, w.orders, w.cost
    FROM sample s JOIN weekly w ON w.prod = s.prod AND w.term = s.term
    ORDER BY s.prod, s.term, w.wk""", "coach_weekly")

    scen = defaultdict(list)
    for r in tw:
        scen[(r["prod"], r["intent_key"], r["term"], r["strategy"])].append(r)

    actions, tot = [], defaultdict(lambda: defaultdict(float))
    for (prod, intent, term, strat), weeks in scen.items():
        gp = GP.get(prod)
        if not gp:
            continue
        weeks.sort(key=lambda x: x["wk"])
        w25 = [w for w in weeks if w["wk"] >= "2025-01-01"]
        negated = False
        cum_clicks, active_weeks, probed = 0, 0, False
        for idx, w in enumerate(w25):
            trail = [x for x in weeks if x["wk"] < w["wk"] and x["wk"] >=
                     (lambda d: f"{d}")(_minus_weeks(w["wk"], 4))]
            t4c = sum(I(x["clicks"]) for x in trail)
            t4o = sum(I(x["orders"]) for x in trail)
            l1 = [x for x in weeks if x["wk"] < w["wk"] and x["wk"] >= _minus_weeks(w["wk"], 1)]
            l1c, l1o = sum(I(x["clicks"]) for x in l1), sum(I(x["orders"]) for x in l1)
            l1cost = sum(F(x["cost"]) for x in l1)
            cum_clicks += I(w["clicks"])
            if I(w["clicks"]) > 0:
                active_weeks += 1
            act, why = None, ""
            if not negated and t4c >= 15 and t4o == 0:
                act, why = "NEGATE", f"4w {t4c} clicks / 0 orders"
                negated = True
                fwd = [x for x in w25[idx:]]
                f_cost = sum(F(x["cost"]) for x in fwd)
                f_gp = sum(I(x["orders"]) for x in fwd) * gp
                f_orders = sum(I(x["orders"]) for x in fwd)
                died = all(F(x["cost"]) < 2 for x in w25[idx:idx + 4])
                actions.append(dict(product=prod, intent=intent, term=term, strategy=strat,
                    week=w["wk"], action=act, reason=why,
                    saved=round(f_cost - f_gp, 2), fwd_cost=round(f_cost, 2),
                    fwd_orders=f_orders, matched_reality=int(died)))
                t = tot["NEGATE"]
                t["n"] += 1
                t["saved"] += f_cost - f_gp
                t["right"] += int(f_cost - f_gp > 0)
                t["matched"] += int(died)
            elif l1o > 0 and l1cost > 0 and (l1o * gp) / l1cost >= ROAS_RUN:
                nxt = w25[idx:idx + 4]
                n_cost = sum(F(x["cost"]) for x in nxt)
                n_gp = sum(I(x["orders"]) for x in nxt) * gp
                ok = n_cost > 0 and n_gp / n_cost >= ROAS_RUN
                actions.append(dict(product=prod, intent=intent, term=term, strategy=strat,
                    week=w["wk"], action="RAISE", reason=f"1w ROAS {(l1o*gp)/l1cost:.2f}",
                    saved="", fwd_cost=round(n_cost, 2), fwd_orders=sum(I(x["orders"]) for x in nxt),
                    matched_reality=int(ok)))
                t = tot["RAISE"]
                t["n"] += 1
                t["right"] += int(ok)
            elif not probed and cum_clicks < 4 and active_weeks >= 2:
                probed = True
                fwd8 = w25[idx:idx + 8]
                got = sum(I(x["clicks"]) for x in fwd8) >= 4
                conv = sum(I(x["orders"]) for x in fwd8) > 0
                actions.append(dict(product=prod, intent=intent, term=term, strategy=strat,
                    week=w["wk"], action="PROBE", reason=f"only {cum_clicks} clicks",
                    saved="", fwd_cost="", fwd_orders="", matched_reality=int(got and conv)))
                t = tot["PROBE"]
                t["n"] += 1
                t["right"] += int(got)
                t["conv"] += int(conv)
        tot["HOLD"]["n"] += max(0, len(w25) - 1)

    with (TMP / "backtest_coach_actions.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(actions[0].keys()))
        w.writeheader(); w.writerows(actions)

    lines = ["COACH SCORECARD (weekly term-grain actions, 1000 scenarios, 2025)", "",
             f"scenarios: {len(scen)} | actions emitted: {len(actions)}"]
    n = tot["NEGATE"]
    if n["n"]:
        lines.append(f"NEGATE n={int(n['n'])}: right-call {n['right']/n['n']:.0%} "
                     f"(fwd tail would-be saved ${n['saved']:+,.0f}); "
                     f"reality already died within 4w in {n['matched']/n['n']:.0%}")
    rz = tot["RAISE"]
    if rz["n"]:
        lines.append(f"RAISE  n={int(rz['n'])}: next-4w ROAS held >=1.1 in {rz['right']/rz['n']:.0%}")
    pb = tot["PROBE"]
    if pb["n"]:
        lines.append(f"PROBE  n={int(pb['n'])}: reached 4+ clicks {pb['right']/pb['n']:.0%}, "
                     f"converted {pb['conv']/pb['n']:.0%}")
    lines.append(f"HOLD   week-slots (no action): {int(tot['HOLD']['n'])}")
    (TMP / "backtest_coach_scorecard.txt").write_text("\n".join(lines))
    print()
    print("\n".join(lines))


def _minus_weeks(iso_date: str, n: int) -> str:
    import datetime as dt
    d = dt.date.fromisoformat(iso_date) - dt.timedelta(weeks=n)
    return d.isoformat()


if __name__ == "__main__":
    main()
