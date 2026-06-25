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
