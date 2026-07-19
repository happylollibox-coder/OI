"""Swap Bunny asset group to gift/friendship copy + clean switch + enable.
Creates gift-framed text assets, relinks them, excludes the 5 message bunnies
from the old 'all' group, removes the dead old Bunny asset group, enables the
new Bunny campaign. Dry-run (validate) for the switch unless --apply.
"""
import sys, json
from dotenv import load_dotenv
load_dotenv("/Users/ori/Develop/OI/.env")
sys.path.insert(0, "/Users/ori/Develop/OI/tools/mcp")
from google_ads.client import get_client, customer_id

APPLY = "--apply" in sys.argv
NEWAG = 6726853602; OLDBUNNY = 6725482127; BUNNY_CAMP = 23991674132
prep = json.load(open("/tmp/bunny_prep.json"))
ALLROOT = prep["all_root"]

HEADLINES = [
    "Gift for Your Bestie", "The Birthday Bunny Gift", "Send a Hug From Anywhere",
    "A Gift That Says I Love You", "Proud of You Gift", "Best Friend Gift She'll Love",
    "Cute Gift for Your BFF", "Gift for Teen Best Friends", "Say It With a Bunny",
    "The Gift That Says It All", "Friendship in a Gift", "For Your Favorite Person",
    "A Little Bunny, Big Love", "Gift Her a Little Hug", "Best Friend Bunny Gift",
]
LONG_HEADLINES = [
    "The cute bunny gift that says exactly how you feel about your best friend.",
    "A little plush bunny with a big message - the perfect gift for your bestie.",
    "Birthday, bestie, or just because - a sweet gift that carries your message.",
    "Send a hug she can keep: a plush bunny gift for the people you love most.",
    "Proud, grateful, or missing them - say it with a cute Lolli Bunny gift.",
]
DESCRIPTIONS = [
    "A plush bunny gift that says it for you.",
    "The perfect little gift for your best friend, bestie, or birthday girl.",
    "Cute, huggable, and full of meaning - a gift she'll keep close.",
    "Say happy birthday, I love you, or proud of you with one sweet bunny.",
    "A meaningful little gift for the teen girls who matter most to you.",
]
for h in HEADLINES:  assert len(h) <= 30, (len(h), h)
for x in LONG_HEADLINES + DESCRIPTIONS: assert len(x) <= 90, (len(x), x)

client = get_client(); cid = customer_id()

# --- Phase 1: create text assets (idempotent; Google dedups identical text) ---
asvc = client.get_service("AssetService")
def make_assets(texts):
    ops = []
    for t in texts:
        op = client.get_type("AssetOperation"); op.create.text_asset.text = t; ops.append(op)
    res = asvc.mutate_assets(customer_id=cid, operations=ops)
    return [r.resource_name for r in res.results]
hl = make_assets(HEADLINES); lhl = make_assets(LONG_HEADLINES); ds = make_assets(DESCRIPTIONS)
print(f"assets ready: {len(hl)} HL, {len(lhl)} LHL, {len(ds)} DESC")

# --- Phase 2: the switch (validate unless --apply) ---
ops = []
def newop():
    op = client.get_type("MutateOperation"); ops.append(op); return op

# unlink old text
for ft in ("HEADLINE", "LONG_HEADLINE", "DESCRIPTION"):
    for aga in prep["old_text_aga"][ft]:
        newop().asset_group_asset_operation.remove = aga
# link new text
AGRN = f"customers/{cid}/assetGroups/{NEWAG}"
FT = client.enums.AssetFieldTypeEnum
for rns, ft in ((hl, FT.HEADLINE), (lhl, FT.LONG_HEADLINE), (ds, FT.DESCRIPTION)):
    for rn in rns:
        a = newop().asset_group_asset_operation.create
        a.asset_group = AGRN; a.asset = rn; a.field_type = ft
# exclude overlapping bunnies from 'all'
SRC = client.enums.ListingGroupFilterListingSourceEnum.SHOPPING
EXC = client.enums.ListingGroupFilterTypeEnum.UNIT_EXCLUDED
tid = -1
for item in prep["need_exclude"]:
    e = newop().asset_group_listing_group_filter_operation.create
    e.resource_name = f"customers/{cid}/assetGroupListingGroupFilters/{6601024538}~{tid}"
    e.asset_group = f"customers/{cid}/assetGroups/6601024538"
    e.type_ = EXC; e.listing_source = SRC; e.parent_listing_group_filter = ALLROOT
    e.case_value.product_item_id.value = item; tid -= 1
# remove dead old Bunny asset group
newop().asset_group_operation.remove = f"customers/{cid}/assetGroups/{OLDBUNNY}"
# enable the new Bunny campaign
mop = newop()
c = mop.campaign_operation.update
c.resource_name = f"customers/{cid}/campaigns/{BUNNY_CAMP}"
c.status = client.enums.CampaignStatusEnum.ENABLED
mop.campaign_operation.update_mask.paths.append("status")

svc = client.get_service("GoogleAdsService")
print(f"switch ops: {len(ops)} | swap 25 text, exclude {len(prep['need_exclude'])} from 'all', "
      f"remove old Bunny AG, ENABLE campaign | {'APPLY' if APPLY else 'DRY-RUN'}")
try:
    req = client.get_type("MutateGoogleAdsRequest")
    req.customer_id = cid; req.mutate_operations = ops
    req.validate_only = not APPLY; req.partial_failure = False
    svc.mutate(request=req)
    print("[ok]", "APPLIED — Bunny is live" if APPLY else "DRY-RUN PASSED")
except Exception as e:
    print("FAILED:\n", str(e)[:1200])
