"""Mutate Sales-Performance Max-2: budget -> $80/day, remove target ROAS.

Dry-run by default (prints current + planned). Pass --apply to execute.
Read path uses GoogleAdsService.search; writes use CampaignBudgetService /
CampaignService mutate. Reversible: re-run with old values to restore.
"""
import sys
from dotenv import load_dotenv

load_dotenv("/Users/ori/Develop/OI/.env")
sys.path.insert(0, "/Users/ori/Develop/OI/tools/mcp")
from google_ads.client import get_client, customer_id  # noqa

CAMPAIGN_NAME = "Sales-Performance Max-2"
NEW_BUDGET_DOLLARS = 80
APPLY = "--apply" in sys.argv

client = get_client()
cid = customer_id()
ga = client.get_service("GoogleAdsService")

row = next(iter(ga.search(customer_id=cid, query=f"""
    SELECT campaign.resource_name, campaign.name, campaign.status,
           campaign.bidding_strategy_type,
           campaign.maximize_conversion_value.target_roas,
           campaign_budget.resource_name, campaign_budget.amount_micros
    FROM campaign
    WHERE campaign.name = '{CAMPAIGN_NAME}'
""")), None)
if row is None:
    sys.exit(f"Campaign '{CAMPAIGN_NAME}' not found")

cur_budget = row.campaign_budget.amount_micros / 1e6
cur_troas = row.campaign.maximize_conversion_value.target_roas
print(f"Campaign      : {row.campaign.name} ({row.campaign.status.name})")
print(f"Bidding       : {row.campaign.bidding_strategy_type.name}")
print(f"Budget        : ${cur_budget:.2f}/day   ->  ${NEW_BUDGET_DOLLARS:.2f}/day")
print(f"Target ROAS   : {cur_troas:.4f}        ->  (removed / no target)")
print(f"Mode          : {'APPLY (live mutate)' if APPLY else 'DRY-RUN (no changes)'}")

if not APPLY:
    print("\nDry-run only. Re-run with --apply to execute.")
    sys.exit(0)

# 1) Budget -> $80/day
budget_svc = client.get_service("CampaignBudgetService")
b_op = client.get_type("CampaignBudgetOperation")
b = b_op.update
b.resource_name = row.campaign_budget.resource_name
b.amount_micros = int(NEW_BUDGET_DOLLARS * 1_000_000)
b_op.update_mask.paths.append("amount_micros")
budget_svc.mutate_campaign_budgets(customer_id=cid, operations=[b_op])
print("\n[ok] budget updated -> $80/day")

# 2) Remove target ROAS (keep Maximize Conversion Value)
camp_svc = client.get_service("CampaignService")
c_op = client.get_type("CampaignOperation")
c = c_op.update
c.resource_name = row.campaign.resource_name
c.maximize_conversion_value.target_roas = 0.0  # 0 == no target
c_op.update_mask.paths.append("maximize_conversion_value.target_roas")
camp_svc.mutate_campaigns(customer_id=cid, operations=[c_op])
print("[ok] target ROAS removed -> Maximize Conversion Value (no target)")

# verify
v = next(iter(ga.search(customer_id=cid, query=f"""
    SELECT campaign.maximize_conversion_value.target_roas,
           campaign_budget.amount_micros
    FROM campaign WHERE campaign.name = '{CAMPAIGN_NAME}'""")))
print(f"\nVERIFY -> budget ${v.campaign_budget.amount_micros/1e6:.2f}/day, "
      f"target_roas={v.campaign.maximize_conversion_value.target_roas}")
