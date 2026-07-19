"""Generalized PMax builder from a config json (see /tmp/<fam>_cfg.json).
Config keys: name, agname, budget, merchant_id, final_urls, brand,
asset_group_assets, items, audience, search_themes.
Usage: build_family_pmax.py <config.json> [--apply]
Creates campaign PAUSED, geo=US PRESENCE. Dry-run default.
"""
import sys, json
from dotenv import load_dotenv
load_dotenv("/Users/ori/Develop/OI/.env")
sys.path.insert(0, "/Users/ori/Develop/OI/tools/mcp")
from google_ads.client import get_client, customer_id

APPLY = "--apply" in sys.argv
cfgpath = [a for a in sys.argv[1:] if not a.startswith("--")][0]
d = json.load(open(cfgpath))
client = get_client(); cid = customer_id()
def rn(kind, tid): return f"customers/{cid}/{kind}/{tid}"
BUD, CAMP, AG = -1, -2, -3
ops = []
def newop():
    op = client.get_type("MutateOperation"); ops.append(op); return op

b = newop().campaign_budget_operation.create
b.resource_name = rn("campaignBudgets", BUD)
b.name = f"{d['name']} budget"
b.amount_micros = int(d["budget"]) * 1_000_000
b.delivery_method = client.enums.BudgetDeliveryMethodEnum.STANDARD
b.explicitly_shared = False

c = newop().campaign_operation.create
c.resource_name = rn("campaigns", CAMP)
c.name = d["name"]
c.advertising_channel_type = client.enums.AdvertisingChannelTypeEnum.PERFORMANCE_MAX
c.status = client.enums.CampaignStatusEnum.PAUSED
c.campaign_budget = rn("campaignBudgets", BUD)
client.copy_from(c.maximize_conversions, client.get_type("MaximizeConversions"))
c.shopping_setting.merchant_id = d["merchant_id"]
c.contains_eu_political_advertising = (
    client.enums.EuPoliticalAdvertisingStatusEnum.DOES_NOT_CONTAIN_EU_POLITICAL_ADVERTISING)
c.geo_target_type_setting.positive_geo_target_type = client.enums.PositiveGeoTargetTypeEnum.PRESENCE

loc = newop().campaign_criterion_operation.create
loc.campaign = rn("campaigns", CAMP); loc.location.geo_target_constant = "geoTargetConstants/2840"
lang = newop().campaign_criterion_operation.create
lang.campaign = rn("campaigns", CAMP); lang.language.language_constant = "languageConstants/1000"

for ft, rns in d["brand"].items():
    for a in rns:
        ca = newop().campaign_asset_operation.create
        ca.campaign = rn("campaigns", CAMP); ca.asset = a
        ca.field_type = client.enums.AssetFieldTypeEnum[ft]

ag = newop().asset_group_operation.create
ag.resource_name = rn("assetGroups", AG); ag.name = d["agname"]
ag.campaign = rn("campaigns", CAMP); ag.final_urls.extend(d["final_urls"])
ag.status = client.enums.AssetGroupStatusEnum.ENABLED

n = 0
for ft, rns in d["asset_group_assets"].items():
    for a in rns:
        aga = newop().asset_group_asset_operation.create
        aga.asset_group = rn("assetGroups", AG); aga.asset = a
        aga.field_type = client.enums.AssetFieldTypeEnum[ft]; n += 1

SUB=client.enums.ListingGroupFilterTypeEnum.SUBDIVISION
INC=client.enums.ListingGroupFilterTypeEnum.UNIT_INCLUDED
EXC=client.enums.ListingGroupFilterTypeEnum.UNIT_EXCLUDED
SRC=client.enums.ListingGroupFilterListingSourceEnum.SHOPPING
def lg(tid): return f"customers/{cid}/assetGroupListingGroupFilters/{AG}~{tid}"
root=newop().asset_group_listing_group_filter_operation.create
root.resource_name=lg(-4); root.asset_group=rn("assetGroups",AG); root.type_=SUB; root.listing_source=SRC
tid=-5
for item in d["items"]:
    u=newop().asset_group_listing_group_filter_operation.create
    u.resource_name=lg(tid); u.asset_group=rn("assetGroups",AG); u.type_=INC; u.listing_source=SRC
    u.parent_listing_group_filter=lg(-4); u.case_value.product_item_id.value=item; tid-=1
o=newop().asset_group_listing_group_filter_operation.create
o.resource_name=lg(tid); o.asset_group=rn("assetGroups",AG); o.type_=EXC; o.listing_source=SRC
o.parent_listing_group_filter=lg(-4); o.case_value.product_item_id._pb.SetInParent()

for t in d["search_themes"]:
    s=newop().asset_group_signal_operation.create
    s.asset_group=rn("assetGroups",AG); s.search_theme.text=t
if d.get("audience"):
    a=newop().asset_group_signal_operation.create
    a.asset_group=rn("assetGroups",AG); a.audience.audience=d["audience"]

svc=client.get_service("GoogleAdsService")
print(f"{d['name']} | PMax PAUSED | ${d['budget']}/day | US PRESENCE | {len(d['items'])} products | {n} assets | {len(d['search_themes'])} themes + {'aud' if d.get('audience') else 'no-aud'} | ops={len(ops)} | {'APPLY' if APPLY else 'DRY-RUN'}")
try:
    req=client.get_type("MutateGoogleAdsRequest")
    req.customer_id=cid; req.mutate_operations=ops; req.validate_only=not APPLY; req.partial_failure=False
    resp=svc.mutate(request=req)
    if APPLY:
        for r in resp.mutate_operation_responses:
            for f in ("campaign_result","asset_group_result","campaign_budget_result"):
                v=getattr(r,f)
                if v.resource_name: print("  created:",v.resource_name)
        print("[ok] created (PAUSED).")
    else:
        print("[ok] DRY-RUN PASSED.")
except Exception as e:
    print("FAILED:\n", str(e)[:1000])
