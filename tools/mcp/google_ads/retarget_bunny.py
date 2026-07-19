"""Retarget the Bunny PMax campaign to 5 message bunnies + message-based themes.
Removes old listing children + plush-keychain themes; adds the 5 products and
message/relationship search themes. Dry-run default; --apply to execute.
"""
import sys, json
from dotenv import load_dotenv
load_dotenv("/Users/ori/Develop/OI/.env")
sys.path.insert(0, "/Users/ori/Develop/OI/tools/mcp")
from google_ads.client import get_client, customer_id

APPLY = "--apply" in sys.argv
AG = 6726853602
cur = json.load(open("/tmp/bunny_current.json"))
ROOT = cur["root"]

ITEMS = {  # the 5 chosen message bunnies
    "Bestie":  "shopify_zz_9237780136158_48324323475678",
    "Love":    "shopify_zz_9237780037854_48324323377374",
    "Birthday":"shopify_zz_9237779251422_48324268982494",
    "Hug":     "shopify_zz_9237779841246_48324321673438",
    "Proud":   "shopify_zz_9237782528222_48324335435998",
}
THEMES = [
    "gifts for best friend", "bff gifts", "gifts for bestie",
    "birthday gift for best friend", "birthday gifts for teen girls",
    "friendship gifts for girls", "long distance best friend gift",
    "thinking of you gift for her", "graduation gift for her",
    "congratulations gift for her", "encouragement gift for teen girl",
    "cute best friend gifts for teens",
]

client = get_client(); cid = customer_id()
ops = []
def newop():
    op = client.get_type("MutateOperation"); ops.append(op); return op

# remove old listing children (units + catch-all); keep root subdivision
for ch in cur["children"]:
    newop().asset_group_listing_group_filter_operation.remove = ch
# add the 5 products + a new everything-else catch-all under existing root
SRC = client.enums.ListingGroupFilterListingSourceEnum.SHOPPING
INC = client.enums.ListingGroupFilterTypeEnum.UNIT_INCLUDED
EXC = client.enums.ListingGroupFilterTypeEnum.UNIT_EXCLUDED
def lg(tid): return f"customers/{cid}/assetGroupListingGroupFilters/{AG}~{tid}"
tid = -1
for name, item in ITEMS.items():
    u = newop().asset_group_listing_group_filter_operation.create
    u.resource_name = lg(tid); u.asset_group = f"customers/{cid}/assetGroups/{AG}"
    u.type_ = INC; u.listing_source = SRC; u.parent_listing_group_filter = ROOT
    u.case_value.product_item_id.value = item; tid -= 1
o = newop().asset_group_listing_group_filter_operation.create
o.resource_name = lg(tid); o.asset_group = f"customers/{cid}/assetGroups/{AG}"
o.type_ = EXC; o.listing_source = SRC; o.parent_listing_group_filter = ROOT
o.case_value.product_item_id._pb.SetInParent()

# swap search themes
for sig in cur["themes"]:
    newop().asset_group_signal_operation.remove = sig
for t in THEMES:
    s = newop().asset_group_signal_operation.create
    s.asset_group = f"customers/{cid}/assetGroups/{AG}"; s.search_theme.text = t

svc = client.get_service("GoogleAdsService")
print(f"Bunny retarget: -{len(cur['children'])} old products, +{len(ITEMS)} ({', '.join(ITEMS)})")
print(f"                -{len(cur['themes'])} plush themes, +{len(THEMES)} message themes")
print(f"Total ops: {len(ops)} | {'APPLY' if APPLY else 'DRY-RUN'}")
try:
    req = client.get_type("MutateGoogleAdsRequest")
    req.customer_id = cid; req.mutate_operations = ops
    req.validate_only = not APPLY; req.partial_failure = False
    svc.mutate(request=req)
    print("[ok]", "APPLIED" if APPLY else "DRY-RUN PASSED")
except Exception as e:
    print("FAILED:\n", str(e)[:1000])
