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
