# tools/strategy_profile/run.py
"""Build base, classify intent, derive per-intent profile + main keywords, load to BQ."""
import io, subprocess
import pandas as pd
from tools.analysis.cpc_strategy_profit import config as AC
from tools.analysis.cpc_strategy_profit.build_base import build_base
from . import config as C
from .derive import derive_profile, derive_main_keywords, normalize_match_type
from .borrow import fill_gaps
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
    # Borrow (Coacher C): fill non-CONCLUSIVE cells from a similar CONCLUSIVE donor.
    # base reliably carries "cpc" and "clicks" (see derive.py); avoid relying on a "cost" column.
    base["match_type"] = base["targeting_type"].map(normalize_match_type)
    cpc_by_pm = (base[base["clicks"] > 0]
                 .groupby(["parent_name", "match_type"])["cpc"].median().to_dict())
    prof = fill_gaps(prof, cpc_by_pm)
    mk = derive_main_keywords(base, intent=intent)
    load_table(prof, "DE_PRODUCT_STRATEGY_PROFILE", replace_sources=("DERIVED", "BORROWED"))
    load_table(mk, "DE_PRODUCT_MAIN_KEYWORDS")
    n_borrowed = int((prof["source"] == "BORROWED").sum())
    print(f"profile rows={len(prof)} (borrowed={n_borrowed}; intents: {sorted(prof.intent_class.unique())})  main_keywords={len(mk)}")

if __name__ == "__main__":
    run()
