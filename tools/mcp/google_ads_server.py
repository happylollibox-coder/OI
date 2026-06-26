"""Google Ads PMax Audit MCP Server (Phase 1, read-only).

Exposes read-only tools to inspect and audit Performance Max / Shopping campaigns.
No mutate calls — this server cannot change the account.
"""

import json
from pathlib import Path

from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP

from tools.mcp.google_ads import audit_rules, queries
from tools.mcp.google_ads.client import customer_id, get_client

load_dotenv(Path(__file__).resolve().parents[2] / ".env")

mcp = FastMCP("OI Google Ads (read-only)")

EXPORTS_DIR = Path(__file__).resolve().parents[2] / "exports"


def _snapshot() -> dict:
    client = get_client()
    return queries.fetch_account_snapshot(client, customer_id())


@mcp.tool()
def list_campaigns() -> str:
    """List PMax/Shopping campaigns with status, budget, and target ROAS."""
    snap = _snapshot()
    rows = [
        {k: c[k] for k in ("name", "status", "budget_micros", "target_roas")}
        for c in snap["campaigns"]
    ]
    return json.dumps({"count": len(rows), "campaigns": rows}, default=str)


@mcp.tool()
def get_asset_groups() -> str:
    """List asset groups per campaign with ad strength."""
    snap = _snapshot()
    rows = []
    for c in snap["campaigns"]:
        for ag in c["asset_groups"]:
            rows.append({"campaign": c["name"], "asset_group": ag["name"],
                         "ad_strength": ag.get("ad_strength")})
    return json.dumps({"count": len(rows), "asset_groups": rows}, default=str)


@mcp.tool()
def get_asset_group_assets() -> str:
    """List asset counts by field type for every asset group."""
    snap = _snapshot()
    rows = []
    for c in snap["campaigns"]:
        for ag in c["asset_groups"]:
            counts = {ft: len(v) for ft, v in ag.get("assets", {}).items()}
            rows.append({"campaign": c["name"], "asset_group": ag["name"], "asset_counts": counts})
    return json.dumps({"count": len(rows), "rows": rows}, default=str)


@mcp.tool()
def get_listing_groups() -> str:
    """Report listing-group structure per asset group (all-products vs subdivided).

    Phase 1 returns a placeholder note; listing-group detail lands in a later iteration.
    """
    return json.dumps({"note": "Listing-group detail not yet implemented in Phase 1."})


@mcp.tool()
def audit_pmax(dump_json: bool = False) -> str:
    """Audit all PMax/Shopping campaigns against the config checklist.

    Returns a summary + findings (severity error/warning/ok). Set dump_json=True to
    also write the raw findings to OI/exports/.
    """
    snap = _snapshot()
    result = audit_rules.audit_account(snap)
    result["feed_health"] = "not checked — needs Merchant Center Content API (out of Phase 1 scope)"
    if dump_json:
        EXPORTS_DIR.mkdir(exist_ok=True)
        out = EXPORTS_DIR / f"pmax_audit_{snap['customer_id']}.json"
        out.write_text(json.dumps(result, indent=2, default=str))
        result["written_to"] = str(out)
    return json.dumps(result, default=str)


if __name__ == "__main__":
    mcp.run()
