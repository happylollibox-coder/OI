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

# Borrow / probe (Coacher C)
BORROW_HAIRCUT = 0.80          # borrowed cpc capped at 80% of donor's cpc_target
PROBE_CPC_PCTILE = 50          # probe launch CPC = p50 of parent×match real CPC
PROBE_DECISION_CLICKS = 15     # probe graduates at this many clicks
PROBE_DECISION_DAYS = 14       # probe exhausts after this many days
PROBE_DEMAND_FLOOR = 100       # min SQP search volume to justify a probe
GLOBAL_BID_CAP = 2.00          # hard ceiling, mirrors th_bid_cap default
MATCH_DISTANCE = {("EXACT", "PHRASE"): 1, ("PHRASE", "BROAD"): 1, ("EXACT", "BROAD"): 2}
