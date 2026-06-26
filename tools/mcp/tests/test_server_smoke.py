import importlib


def test_server_module_imports_and_registers_tools():
    mod = importlib.import_module("tools.mcp.google_ads_server")
    assert mod.mcp is not None
    for name in [
        "list_campaigns",
        "get_asset_groups",
        "get_asset_group_assets",
        "get_listing_groups",
        "audit_pmax",
    ]:
        assert callable(getattr(mod, name))
