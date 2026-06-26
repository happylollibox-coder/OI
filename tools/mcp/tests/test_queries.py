from tools.mcp.google_ads.queries import (
    campaigns_query,
    asset_groups_query,
    asset_group_assets_query,
)


def test_campaigns_query_targets_pmax_and_shopping():
    q = campaigns_query()
    assert "FROM campaign" in q
    assert "campaign.advertising_channel_type" in q
    assert "PERFORMANCE_MAX" in q
    assert "SHOPPING" in q


def test_asset_groups_query_selects_ad_strength():
    q = asset_groups_query()
    assert "FROM asset_group" in q
    assert "asset_group.ad_strength" in q


def test_asset_group_assets_query_filters_by_group():
    q = asset_group_assets_query("987654")
    assert "FROM asset_group_asset" in q
    assert "asset_group.id = 987654" in q
    assert "asset_group_asset.field_type" in q
