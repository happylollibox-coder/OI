"""OI Ads Coach MCP Server.

Exposes BigQuery V_ADS_COACH views as tools for querying
coach mode, actions, negate terms, phrase negatives, and cooldown status.
"""

import json
from typing import Optional

from google.cloud import bigquery
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("OI Coach")
client = bigquery.Client(project="onyga-482313")

PROJECT_DATASET = "onyga-482313.OI"


def _run_query(query: str, params: list | None = None) -> list[dict]:
    """Execute a BigQuery query and return rows as list of dicts."""
    job_config = bigquery.QueryJobConfig()
    if params:
        job_config.query_parameters = params
    results = client.query(query, job_config=job_config).result()
    return [dict(row) for row in results]


def _to_json(rows: list[dict]) -> str:
    """Serialize rows to JSON, handling date/decimal types."""
    if not rows:
        return json.dumps({"message": "No results found", "rows": []})
    return json.dumps({"count": len(rows), "rows": rows}, default=str)


@mcp.tool()
def get_coach_status() -> str:
    """Get current Ads Coach mode (BLITZ / COOLDOWN / GUARDIAN), active holidays, and cooldown day count."""
    query = f"""
        SELECT DISTINCT coach_mode, pp_day, holiday_name
        FROM `{PROJECT_DATASET}.V_ADS_COACH`
        WHERE coach_mode IS NOT NULL
        LIMIT 10
    """
    rows = _run_query(query)
    return _to_json(rows)


@mcp.tool()
def get_actions_summary(family: Optional[str] = None) -> str:
    """Get count of coach actions by type (NEGATE_TERM, KEEP, PROMOTE_TO_EXACT, etc.), optionally filtered by product family."""
    if family:
        query = f"""
            SELECT action, COUNT(*) AS count
            FROM `{PROJECT_DATASET}.V_ADS_COACH`
            WHERE product_family = @family
            GROUP BY action
            ORDER BY count DESC
        """
        params = [bigquery.ScalarQueryParameter("family", "STRING", family)]
    else:
        query = f"""
            SELECT action, COUNT(*) AS count
            FROM `{PROJECT_DATASET}.V_ADS_COACH`
            GROUP BY action
            ORDER BY count DESC
        """
        params = None
    rows = _run_query(query, params)
    return _to_json(rows)


@mcp.tool()
def get_negate_terms(
    family: Optional[str] = None,
    campaign: Optional[str] = None,
    limit: int = 50,
) -> str:
    """Get search terms recommended for negation, sorted by spend. Optionally filter by product family and/or campaign name."""
    conditions = ["action = 'NEGATE_TERM'"]
    params = []

    if family:
        conditions.append("product_family = @family")
        params.append(bigquery.ScalarQueryParameter("family", "STRING", family))
    if campaign:
        conditions.append("campaign_name = @campaign")
        params.append(bigquery.ScalarQueryParameter("campaign", "STRING", campaign))

    params.append(bigquery.ScalarQueryParameter("limit", "INT64", limit))
    where_clause = " AND ".join(conditions)

    query = f"""
        SELECT search_term, campaign_name, product_family,
               ads_spend, ads_orders, term_roas
        FROM `{PROJECT_DATASET}.V_ADS_COACH`
        WHERE {where_clause}
        ORDER BY ads_spend DESC
        LIMIT @limit
    """
    rows = _run_query(query, params)
    return _to_json(rows)


@mcp.tool()
def get_phrase_negatives(min_spend: float = 10.0) -> str:
    """Get n-gram phrase negatives with total spend above a threshold."""
    query = f"""
        SELECT *
        FROM `{PROJECT_DATASET}.V_ADS_COACH_PHRASE_NEGATIVES`
        WHERE total_spend >= @min_spend
        ORDER BY total_spend DESC
        LIMIT 50
    """
    params = [bigquery.ScalarQueryParameter("min_spend", "FLOAT64", min_spend)]
    rows = _run_query(query, params)
    return _to_json(rows)


@mcp.tool()
def get_cooldown_status() -> str:
    """Get detailed post-peak cooldown status per campaign, including bid change percentages."""
    query = f"""
        SELECT campaign_name, product_family, coach_mode,
               pp_day, pp_action, pp_bid_change_pct
        FROM `{PROJECT_DATASET}.V_ADS_COACH`
        WHERE coach_mode = 'COOLDOWN'
        LIMIT 50
    """
    rows = _run_query(query)
    return _to_json(rows)


if __name__ == "__main__":
    mcp.run()
