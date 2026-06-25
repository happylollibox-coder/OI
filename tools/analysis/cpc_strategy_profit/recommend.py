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
    # NA (not False) where the coacher has no recent moves for this parent — absence != disagreement
    agree = rec["rec_direction"] == rec["coacher_bias"]
    rec["agrees_with_coacher"] = agree.where(rec["coacher_bias"].notna(), other=pd.NA)
    return rec
