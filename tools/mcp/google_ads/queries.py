"""GAQL query builders (pure strings) and the read-only snapshot fetcher.

Read-only: only GoogleAdsService.search is used. No mutate calls anywhere.
"""


def campaigns_query() -> str:
    return (
        "SELECT campaign.id, campaign.name, campaign.status, "
        "campaign.advertising_channel_type, campaign_budget.amount_micros, "
        "campaign.maximize_conversion_value.target_roas, "
        "campaign.url_expansion_opt_out "
        "FROM campaign "
        "WHERE campaign.advertising_channel_type IN ('PERFORMANCE_MAX', 'SHOPPING') "
        "AND campaign.status != 'REMOVED'"
    )


def asset_groups_query() -> str:
    return (
        "SELECT asset_group.id, asset_group.name, asset_group.status, "
        "asset_group.ad_strength, asset_group.campaign "
        "FROM asset_group "
        "WHERE asset_group.status != 'REMOVED'"
    )


def asset_group_assets_query(asset_group_id: str) -> str:
    return (
        "SELECT asset_group_asset.field_type, asset_group_asset.asset, "
        "asset.id "
        "FROM asset_group_asset "
        f"WHERE asset_group.id = {int(asset_group_id)} "
        "AND asset_group_asset.status != 'REMOVED'"
    )


def fetch_account_snapshot(client, customer_id: str) -> dict:
    """Run the read queries and normalize into the audit snapshot dict.

    Uses GoogleAdsService.search (read-only). Field-type enum names from
    asset_group_asset.field_type populate the per-group 'assets' buckets.
    """
    svc = client.get_service("GoogleAdsService")

    campaigns: dict[str, dict] = {}
    for row in svc.search(customer_id=customer_id, query=campaigns_query()):
        target_roas = None
        mcv = row.campaign.maximize_conversion_value
        if mcv and mcv.target_roas:
            target_roas = mcv.target_roas
        campaigns[str(row.campaign.id)] = {
            "name": row.campaign.name,
            "status": row.campaign.status.name,
            "budget_micros": row.campaign_budget.amount_micros,
            "target_roas": target_roas,
            "final_url_expansion_opt_out": bool(row.campaign.url_expansion_opt_out),
            "brand_exclusions_count": 0,  # populated by a brand-list query in a later iteration
            "asset_groups": [],
            "_ag_index": {},
        }

    for row in svc.search(customer_id=customer_id, query=asset_groups_query()):
        camp_id = row.asset_group.campaign.split("/")[-1]
        camp = campaigns.get(camp_id)
        if not camp:
            continue
        ag = {
            "id": str(row.asset_group.id),
            "name": row.asset_group.name,
            "ad_strength": row.asset_group.ad_strength.name,
            "has_audience_signal": False,  # set by signal query in a later iteration
            "assets": {},
        }
        camp["asset_groups"].append(ag)
        camp["_ag_index"][ag["id"]] = ag

    for camp in campaigns.values():
        for ag in camp["asset_groups"]:
            for row in svc.search(
                customer_id=customer_id, query=asset_group_assets_query(ag["id"])
            ):
                field = row.asset_group_asset.field_type.name
                ag["assets"].setdefault(field, []).append(str(row.asset.id))
        camp.pop("_ag_index", None)

    return {
        "customer_id": customer_id,
        "campaigns": list(campaigns.values()),
    }
