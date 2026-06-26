"""GAQL query builders (pure strings) and the read-only snapshot fetcher.

Read-only: only GoogleAdsService.search is used. No mutate calls anywhere.
"""


def campaigns_query() -> str:
    return (
        "SELECT campaign.id, campaign.name, campaign.status, "
        "campaign.advertising_channel_type, campaign_budget.amount_micros, "
        "campaign.maximize_conversion_value.target_roas "
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


def campaign_brand_assets_query() -> str:
    """Campaign-level brand assets (business name, logos). In PMax these are set
    once per campaign and apply to every asset group, so the asset-group audit
    must count them or it false-flags them as missing."""
    return (
        "SELECT campaign.id, campaign_asset.field_type, campaign_asset.asset "
        "FROM campaign_asset "
        "WHERE campaign_asset.field_type IN "
        "('BUSINESS_NAME', 'LOGO', 'LANDSCAPE_LOGO', 'BUSINESS_LOGO') "
        "AND campaign_asset.status != 'REMOVED'"
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
            # Final-URL-expansion state is not selectable via GAQL (no such field
            # in the current API), so we leave it unknown and the audit skips it.
            "final_url_expansion_opt_out": None,
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

    # Campaign-level brand assets (business name + logos) apply to every asset
    # group in the campaign. Collect them per campaign so we can merge them in.
    camp_brand: dict[str, list[tuple[str, str]]] = {}
    for row in svc.search(
        customer_id=customer_id, query=campaign_brand_assets_query()
    ):
        camp_brand.setdefault(str(row.campaign.id), []).append(
            (row.campaign_asset.field_type.name, str(row.campaign_asset.asset))
        )

    for camp_id, camp in campaigns.items():
        brand = camp_brand.get(camp_id, [])
        for ag in camp["asset_groups"]:
            for row in svc.search(
                customer_id=customer_id, query=asset_group_assets_query(ag["id"])
            ):
                field = row.asset_group_asset.field_type.name
                ag["assets"].setdefault(field, []).append(str(row.asset.id))
            # Merge campaign-wide brand assets (business name, logos) into the
            # asset group's coverage so they aren't false-flagged as missing.
            for field, asset_id in brand:
                ag["assets"].setdefault(field, []).append(asset_id)
        camp.pop("_ag_index", None)

    return {
        "customer_id": customer_id,
        "campaigns": list(campaigns.values()),
    }
