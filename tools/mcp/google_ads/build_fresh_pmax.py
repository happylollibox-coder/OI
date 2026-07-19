"""Create a dedicated PMax campaign for Fresh, focused on self-care/spa intent.
Same recipe as build_lollime_pmax.py. Reuses existing Fresh assets, scopes to
the 3 Fresh products, seeds self-care search themes + Fresh audience signal.
Campaign created PAUSED. Dry-run (validate_only) default; --apply to create.
"""
import sys, json
from dotenv import load_dotenv
load_dotenv("/Users/ori/Develop/OI/.env")
sys.path.insert(0, "/Users/ori/Develop/OI/tools/mcp")
from google_ads.client import get_client, customer_id

BUDGET_DOLLARS = 15
CAMP_NAME = "PMax - Fresh Self-Care"
APPLY = "--apply" in sys.argv
SEARCH_THEMES = [
    "self care gift for teen girls", "spa gift set for girls", "spa kit for teen girls",
    "skincare gift set for teen girls", "self care kit for girls", "pampering gift for teen girls",
    "spa day set for girls", "bath and body gift set for teen girls", "self care gift for college girls",
    "teen girl spa gift", "spa gift for 13 year old girl", "spa gift for 14 year old girl",
    "self care gift for tween girls", "relaxation gift for teen girls", "spa set for girls",
]

d = json.load(open("/tmp/fresh_assets.json"))
client = get_client(); cid = customer_id()
def rn(kind, tid): return f"customers/{cid}/{kind}/{tid}"
BUD, CAMP, AG = -1, -2, -3
ops = []
def newop():
    op = client.get_type("MutateOperation"); ops.append(op); return op

b = newop().campaign_budget_operation.create
b.resource_name = rn("campaignBudgets", BUD)
b.name = "PMax Fresh Self-Care budget"
b.amount_micros = BUDGET_DOLLARS * 1_000_000
b.delivery_method = client.enums.BudgetDeliveryMethodEnum.STANDARD
b.explicitly_shared = False

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

loc = newop().campaign_criterion_operation.create
loc.campaign = rn("campaigns", CAMP); loc.location.geo_target_constant = "geoTargetConstants/2840"
lang = newop().campaign_criterion_operation.create
lang.campaign = rn("campaigns", CAMP); lang.language.language_constant = "languageConstants/1000"

for ft, rns in d["brand"].items():
    for asset_rn in rns:
        ca = newop().campaign_asset_operation.create
        ca.campaign = rn("campaigns", CAMP); ca.asset = asset_rn
        ca.field_type = client.enums.AssetFieldTypeEnum[ft]

ag = newop().asset_group_operation.create
ag.resource_name = rn("assetGroups", AG); ag.name = "Fresh Self-Care"
ag.campaign = rn("campaigns", CAMP); ag.final_urls.extend(d["final_urls"])
ag.status = client.enums.AssetGroupStatusEnum.ENABLED

n_assets = 0
for ft, rns in d["asset_group_assets"].items():
    for asset_rn in rns:
        aga = newop().asset_group_asset_operation.create
        aga.asset_group = rn("assetGroups", AG); aga.asset = asset_rn
        aga.field_type = client.enums.AssetFieldTypeEnum[ft]; n_assets += 1

SUB = client.enums.ListingGroupFilterTypeEnum.SUBDIVISION
INC = client.enums.ListingGroupFilterTypeEnum.UNIT_INCLUDED
EXC = client.enums.ListingGroupFilterTypeEnum.UNIT_EXCLUDED
SRC = client.enums.ListingGroupFilterListingSourceEnum.SHOPPING
def lg_rn(tid): return f"customers/{cid}/assetGroupListingGroupFilters/{AG}~{tid}"
root = newop().asset_group_listing_group_filter_operation.create
root.resource_name = lg_rn(-4); root.asset_group = rn("assetGroups", AG)
root.type_ = SUB; root.listing_source = SRC
tid = -5
for item in d["items"]:
    u = newop().asset_group_listing_group_filter_operation.create
    u.resource_name = lg_rn(tid); u.asset_group = rn("assetGroups", AG)
    u.type_ = INC; u.listing_source = SRC; u.parent_listing_group_filter = lg_rn(-4)
    u.case_value.product_item_id.value = item; tid -= 1
other = newop().asset_group_listing_group_filter_operation.create
other.resource_name = lg_rn(tid); other.asset_group = rn("assetGroups", AG)
other.type_ = EXC; other.listing_source = SRC; other.parent_listing_group_filter = lg_rn(-4)
other.case_value.product_item_id._pb.SetInParent()

for theme in SEARCH_THEMES:
    s = newop().asset_group_signal_operation.create
    s.asset_group = rn("assetGroups", AG); s.search_theme.text = theme
# audience signal (reuse Fresh's existing audience)
if d.get("audience"):
    a = newop().asset_group_signal_operation.create
    a.asset_group = rn("assetGroups", AG); a.audience.audience = d["audience"]

svc = client.get_service("GoogleAdsService")
print(f"Campaign : {CAMP_NAME}  (PMax, PAUSED)")
print(f"Budget   : ${BUDGET_DOLLARS}/day | Maximize Conversions | US/English")
print(f"Products : {len(d['items'])} Fresh items | Assets: {n_assets} relinked + brand")
print(f"Signals  : {len(SEARCH_THEMES)} self-care themes + {'1 audience' if d.get('audience') else 'no audience'}")
print(f"Total ops: {len(ops)} | mode: {'APPLY' if APPLY else 'DRY-RUN'}\n")
try:
    req = client.get_type("MutateGoogleAdsRequest")
    req.customer_id = cid; req.mutate_operations = ops
    req.validate_only = not APPLY; req.partial_failure = False
    resp = svc.mutate(request=req)
    if APPLY:
        for r in resp.mutate_operation_responses:
            for f in ("campaign_result","asset_group_result","campaign_budget_result"):
                v = getattr(r, f)
                if v.resource_name: print("  created:", v.resource_name)
        print("\n[ok] Fresh PMax created (PAUSED).")
    else:
        print("[ok] DRY-RUN PASSED. Re-run with --apply.")
except Exception as e:
    print("VALIDATION FAILED:\n", str(e)[:1200])
