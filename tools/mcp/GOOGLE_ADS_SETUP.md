# Google Ads Audit MCP — Setup

Read-only **Phase 1**. Audits Performance Max / Shopping campaigns against a config
checklist (asset coverage, ad strength, audience signal, budget/target ROAS, brand
exclusions). **No mutate calls — this server cannot change the account.**

## Prerequisites (one-time, manual — the real gate)

1. Google Ads **Manager (MCC)** account → apply for a **developer token**. **Basic access**
   is enough for one own-account; you do NOT need Standard access for Phase 1.
2. In GCP project `onyga-482313`: create an OAuth2 **Desktop** client → client ID + secret.
3. Generate a **refresh token** for the account (Google's `generate_user_credentials` flow
   from the google-ads-python examples).
4. Find the **customer ID** of the Happy Lolli Google Ads account.

## Env vars (add to `OI/.env`)

```
GOOGLE_ADS_DEVELOPER_TOKEN=...
GOOGLE_ADS_CLIENT_ID=...
GOOGLE_ADS_CLIENT_SECRET=...
GOOGLE_ADS_REFRESH_TOKEN=...
GOOGLE_ADS_LOGIN_CUSTOMER_ID=...   # the MCC, dashes optional
GOOGLE_ADS_CUSTOMER_ID=...         # the Happy Lolli account, dashes optional
```

A missing var produces a clear `ValueError` naming the exact key.

## Run / register

Launch the server:

```
.venv/bin/python tools/mcp/google_ads_server.py
```

Register it in your Claude MCP config as a stdio server (top-level `mcpServers` in
`~/.claude.json`, alongside `canva` / `shopify-dev`):

```json
"oi-google-ads": {
  "type": "stdio",
  "command": "/Users/ori/Develop/OI/.venv/bin/python",
  "args": ["/Users/ori/Develop/OI/tools/mcp/google_ads_server.py"]
}
```

Restart Claude Code; confirm the `oi-google-ads` tools appear.

## Tools

- `list_campaigns` — PMax/Shopping campaigns: status, budget, target ROAS
- `get_asset_groups` — asset groups + ad strength
- `get_asset_group_assets` — asset counts by field type per group
- `get_listing_groups` — **Phase 1 stub** (listing-group detail lands in a later iteration)
- `audit_pmax(dump_json=False)` — the headline audit; `dump_json=True` also writes raw
  findings to `OI/exports/pmax_audit_<customer_id>.json`

## Verify once credentials exist

```
.venv/bin/python -c "from tools.mcp.google_ads_server import list_campaigns; print(list_campaigns())"
.venv/bin/python -c "from tools.mcp.google_ads_server import audit_pmax; print(audit_pmax(True))"
```

## Known gaps (Phase 1)

- **Product-feed health** (disapprovals, GTINs) lives in **Merchant Center / Content API for
  Shopping** — a separate API, not covered here. `audit_pmax` reports `feed_health` as
  "not checked".
- **Listing-group structure** and **audience-signal / brand-exclusion** detail are stubbed or
  defaulted in the fetcher; they land in a later iteration.
- The live `fetch_account_snapshot` path is unverified until real credentials exist; the pure
  audit rules and GAQL builders are unit-tested.

## Phase 2 (future, separate plan)

Gated update layer — propose/apply (validate_only → confirm) for updating assets and configs.
See `docs/superpowers/specs/2026-06-26-google-ads-pmax-audit-mcp-design.md`.
