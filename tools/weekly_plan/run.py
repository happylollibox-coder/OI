"""Build the rolling weekly plan: budget -> allocate -> purpose -> expected -> load. Coacher D."""
import io, subprocess, datetime as dt
import pandas as pd
from . import config as C
from .compute import assign_purpose, expected_value, SUCCESS_METRIC, allocate_budget
from .load import load_plan

def _q(sql):
    out = subprocess.run(["bq", f"--project_id={C.PROJECT}", "query", "--use_legacy_sql=false",
                          "--format=csv", "--max_rows=1000000", sql], capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(out.stderr)
    return pd.read_csv(io.StringIO(out.stdout)) if out.stdout.strip() else pd.DataFrame()

def _sunday(d):
    # Most recent Sunday — Sun–Sat week start, matching SQP/Amazon + Home ads (WEEK(SUNDAY)).
    return d - dt.timedelta(days=(d.weekday() + 1) % 7)

def run():
    today = dt.date.today()
    cur = _sunday(today)
    weeks = [cur + dt.timedelta(weeks=i) for i in range(C.HORIZON_WEEKS)]
    profile = _q("SELECT parent_name, season, match_type, intent_class, campaign_type, ad_format, "
                 "confidence, net_per_dollar, cpc_target, source FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`")
    # pd.read_csv coerces the literal 'NA' ad_format to NaN — restore it so the sentinel survives the
    # cellcap merge and lands as 'NA' (not NULL) in the plan, matching the engine's wk_plan join.
    profile["ad_format"] = profile["ad_format"].fillna("NA")
    gaps = _q("SELECT DISTINCT parent_name, season, match_type, intent_class FROM "
              "`onyga-482313.OI.V_STRATEGY_GAPS`")
    gapset = {(r.parent_name, r.season, r.match_type, r.intent_class) for r in gaps.itertuples()}
    # relevant peak windows per product (per-product peak) -> each week's season
    peakw = _q("SELECT r.family, h.boost_start, h.cooldown_start FROM `onyga-482313.OI.V_PEAK_RELEVANCE` r "
               "JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h ON h.holiday_name=r.holiday_name WHERE r.is_relevant_peak")
    def week_season(parent, wk):
        we = wk + dt.timedelta(days=6)
        for row in peakw.itertuples():
            if row.family != parent:
                continue
            bs, cs = pd.to_datetime(row.boost_start), pd.to_datetime(row.cooldown_start)
            if pd.isna(bs) or pd.isna(cs):
                continue
            if not (we < bs.date() or wk > cs.date()):
                return 'PEAK'
        return 'OFF'
    # per-product trailing net trend + bootstrap spend (8w)
    trend = _q(f"SELECT parent_name, ROUND(AVG(wk_net),2) net_trend, ROUND(AVG(wk_spend),2) boot_spend FROM ("
               f"  SELECT parent_name, week_start, SUM(net_profit) wk_net, SUM(spend) wk_spend "
               f"  FROM `onyga-482313.OI.V_WEEKLY_CELL_NET` "
               f"  WHERE week_start >= DATE_SUB(CURRENT_DATE(), INTERVAL {C.TREND_WEEKS} WEEK) "
               f"  GROUP BY 1,2) GROUP BY 1")
    # per-CELL trailing actual weekly spend (8w avg) — the capacity signal the allocator caps floors by.
    # Now per campaign_type × ad_format so each format slice is capped by its own real spend.
    cellcap = _q(f"SELECT parent_name, season, match_type, intent_class, campaign_type, ad_format, "
                 f"  ROUND(SUM(spend) / {C.BOOTSTRAP_WEEKS}, 2) AS recent_spend "
                 f"FROM `onyga-482313.OI.V_WEEKLY_CELL_NET` "
                 f"WHERE week_start >= DATE_SUB(CURRENT_DATE(), INTERVAL {C.BOOTSTRAP_WEEKS} WEEK) "
                 f"GROUP BY 1,2,3,4,5,6")
    cellcap["ad_format"] = cellcap["ad_format"].fillna("NA")   # same 'NA' → NaN read_csv fix
    budgets = _q("SELECT parent_name, weekly_budget FROM `onyga-482313.OI.DE_PRODUCT_BUDGET` "
                 "WHERE source IN ('MANUAL','BUSINESS_PLAN') QUALIFY ROW_NUMBER() OVER "
                 "(PARTITION BY parent_name ORDER BY week_start DESC)=1")
    bud = {r.parent_name: r.weekly_budget for r in budgets.itertuples()}
    boot = {r.parent_name: r.boot_spend for r in trend.itertuples()}
    nettr = {r.parent_name: r.net_trend for r in trend.itertuples()}
    # Plan cells are the FINE (campaign_type × ad_format) profile rows — each format slice gets its own
    # purpose, budget share, and target CPC. The coarse ALL/ALL rows are the engine's fallback, not plan
    # cells, so drop them here (every cell with data has fine rows, so nothing is lost).
    fine = profile[profile["campaign_type"] != "ALL"].copy()
    out_rows = []
    for wk in weeks:
        horizon = "CURRENT" if wk == cur else "FUTURE"
        for parent, pcells in fine.groupby("parent_name"):
            wk_season = week_season(parent, wk)
            cells = pcells[pcells["season"] == wk_season].copy()
            if cells.empty:
                continue
            cells["is_gap"] = [(r.parent_name, r.season, r.match_type, r.intent_class) in gapset
                               for r in cells.itertuples()]
            cells["is_brand"] = cells["intent_class"].eq("BRAND")
            cells["is_bleeder"] = cells["net_per_dollar"].fillna(0) < 0
            cells["probe_active"] = False
            cells["purpose"] = [assign_purpose(r._asdict()) for r in cells.itertuples()]
            # attach each cell's trailing actual weekly spend (capacity signal for the floor cap)
            cells = cells.merge(cellcap, on=["parent_name", "season", "match_type", "intent_class",
                                             "campaign_type", "ad_format"], how="left")
            peak = wk_season == "PEAK"
            wb = bud.get(parent) or boot.get(parent) or 0.0
            cells = allocate_budget(cells, weekly_budget=float(wb), peak=peak)
            for r in cells.itertuples():
                p = r.purpose
                out_rows.append(dict(
                    week_start=wk.isoformat(), horizon=horizon, parent_name=parent,
                    season=r.season, match_type=r.match_type, intent_class=r.intent_class,
                    campaign_type=r.campaign_type, ad_format=r.ad_format,
                    purpose=p, objective=f"{p} {parent} {r.match_type} {r.intent_class} {r.campaign_type}/{r.ad_format}",
                    success_metric=SUCCESS_METRIC[p],
                    expected_value=expected_value(p, r._asdict(), r.planned_spend),
                    target_cpc=(r.cpc_target if p == "SCALE" else None),
                    planned_spend=r.planned_spend, spend_mode=r.spend_mode,
                    expected_net_profit=nettr.get(parent), plan_net_profit=None,
                    coach_mode_hint=("BLITZ" if peak else "GUARDIAN"),
                    status="PROPOSED", actual_value=None, source="DERIVED"))
    df = pd.DataFrame(out_rows)
    _seed_bootstrap_budgets(cur, set(profile.parent_name) - set(bud), boot)
    load_plan(df, from_week=cur.isoformat())
    print(f"weekly plan rows={len(df)} weeks={[w.isoformat() for w in weeks]}")

def _seed_bootstrap_budgets(week, parents, boot):
    if not parents:
        return
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
