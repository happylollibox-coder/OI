"""Create a dedicated PMax campaign for LolliME, focused on journal intent.

Reuses the existing LolliME asset-group assets (account-level -> just relink),
scopes to the 3 LolliME products, seeds journal search themes. Campaign is
created PAUSED. Dry-run (validate_only) by default; pass --apply to create.
"""
import sys, json
from dotenv import load_dotenv
load_dotenv("/Users/ori/Develop/OI/.env")
sys.path.insert(0, "/Users/ori/Develop/OI/tools/mcp")
from google_ads.client import get_client, customer_id

BUDGET_DOLLARS = 20
CAMP_NAME = "PMax - LolliME Journal"
APPLY = "--apply" in sys.argv

SEARCH_THEMES = [
    "creative journal kit for girls",
    "journal gift for girls",
    "gift journal for teen girls",
    "diary journal for tween girls",
    "journaling kit for girls",
    "personalized journal for girls",
    "guided journal for girls",
]

d = json.load(open("/tmp/lollime_assets.json"))
client = get_client(); cid = customer_id()
def rn(kind, tid): return f"customers/{cid}/{kind}/{tid}"

# temp ids
BUD, CAMP, AG = -1, -2, -3
ops = []
def newop():
    op = client.get_type("MutateOperation"); ops.append(op); return op

# 1) budget
b = newop().campaign_budget_operation.create
b.resource_name = rn("campaignBudgets", BUD)
b.name = "PMax LolliME Journal budget"
b.amount_micros = BUDGET_DOLLARS * 1_000_000
b.delivery_method = client.enums.BudgetDeliveryMethodEnum.STANDARD
b.explicitly_shared = False

# 2) campaign (PAUSED, PMax, Maximize Conversions to start)
c = newop().campaign_operation.create
c.resource_name = rn("campaigns", CAMP)
c.name = CAMP_NAME
c.advertising_channel_type = client.enums.AdvertisingChannelTypeEnum.PERFORMANCE_MAX
c.status = client.enums.CampaignStatusEnum.PAUSED
c.campaign_budget = rn("campaignBudgets", BUD)
client.copy_from(c.maximize_conversions, client.get_type("MaximizeConversions"))
c.shopping_setting.merchant_id = d["merchant_id"]
c.contains_eu_political_advertising = (
    client.enums.EuPoliticalAdvertisingStatusEnum.DOES_NOT_CONTAIN_EU_POLITICAL_ADVERTISING)

# 3) geo + language
loc = newop().campaign_criterion_operation.create
loc.campaign = rn("campaigns", CAMP)
loc.location.geo_target_constant = "geoTargetConstants/2840"      # United States
lang = newop().campaign_criterion_operation.create
lang.campaign = rn("campaigns", CAMP)
lang.language.language_constant = "languageConstants/1000"        # English

# 4) brand assets at campaign level (business name + logos, reuse)
for ft, rns in d["brand"].items():
    for asset_rn in rns:
        ca = newop().campaign_asset_operation.create
        ca.campaign = rn("campaigns", CAMP)
        ca.asset = asset_rn
        ca.field_type = client.enums.AssetFieldTypeEnum[ft]

# 5) asset group
ag = newop().asset_group_operation.create
ag.resource_name = rn("assetGroups", AG)
ag.name = "LolliME Journal"
ag.campaign = rn("campaigns", CAMP)
ag.final_urls.extend(d["final_urls"])
ag.status = client.enums.AssetGroupStatusEnum.ENABLED

# 6) relink all existing LolliME assets
n_assets = 0
for ft, rns in d["asset_group_assets"].items():
    for asset_rn in rns:
        aga = newop().asset_group_asset_operation.create
        aga.asset_group = rn("assetGroups", AG)
        aga.asset = asset_rn
        aga.field_type = client.enums.AssetFieldTypeEnum[ft]
        n_assets += 1

# 7) listing filter: only the 3 LolliME products
SUB = client.enums.ListingGroupFilterTypeEnum.SUBDIVISION
INC = client.enums.ListingGroupFilterTypeEnum.UNIT_INCLUDED
EXC = client.enums.ListingGroupFilterTypeEnum.UNIT_EXCLUDED
SRC = client.enums.ListingGroupFilterListingSourceEnum.SHOPPING
def lg_rn(tid): return f"customers/{cid}/assetGroupListingGroupFilters/{AG}~{tid}"
root = newop().asset_group_listing_group_filter_operation.create
root.resource_name = lg_rn(-4)
root.asset_group = rn("assetGroups", AG)
root.type_ = SUB
root.listing_source = SRC
tid = -5
for item in d["items"]:
    u = newop().asset_group_listing_group_filter_operation.create
    u.resource_name = lg_rn(tid); u.asset_group = rn("assetGroups", AG)
    u.type_ = INC
    u.listing_source = SRC
    u.parent_listing_group_filter = lg_rn(-4)
    u.case_value.product_item_id.value = item
    tid -= 1
# everything-else catch-all (excluded)
other = newop().asset_group_listing_group_filter_operation.create
other.resource_name = lg_rn(tid); other.asset_group = rn("assetGroups", AG)
other.type_ = EXC
other.listing_source = SRC
other.parent_listing_group_filter = lg_rn(-4)
other.case_value.product_item_id._pb.SetInParent()

# 8) journal search themes
for theme in SEARCH_THEMES:
    s = newop().asset_group_signal_operation.create
    s.asset_group = rn("assetGroups", AG)
    s.search_theme.text = theme

svc = client.get_service("GoogleAdsService")
print(f"Campaign : {CAMP_NAME}  (PMax, PAUSED)")
print(f"Budget   : ${BUDGET_DOLLARS}/day  | bidding: Maximize Conversions | US / English")
print(f"Products : {len(d['items'])} LolliME items")
print(f"Assets   : {n_assets} relinked (HL/desc/img/video) + brand name/logos")
print(f"Themes   : {len(SEARCH_THEMES)} journal search themes")
print(f"Total ops: {len(ops)}  | mode: {'APPLY' if APPLY else 'DRY-RUN (validate_only)'}\n")
try:
    req = client.get_type("MutateGoogleAdsRequest")
    req.customer_id = cid
    req.mutate_operations = ops
    req.validate_only = not APPLY
    req.partial_failure = False
    resp = svc.mutate(request=req)
    if APPLY:
        for r in resp.mutate_operation_responses:
            for f in ("campaign_result","asset_group_result","campaign_budget_result"):
                v = getattr(r, f)
                if v.resource_name: print("  created:", v.resource_name)
        print("\n[ok] LolliME PMax created (PAUSED). Review in UI, then enable.")
    else:
        print("[ok] DRY-RUN PASSED — validates clean. Re-run with --apply to create.")
except Exception as e:
    msg = str(e)
    print("VALIDATION FAILED:\n", msg[:1500])
