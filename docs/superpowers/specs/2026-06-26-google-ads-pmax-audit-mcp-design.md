# Google Ads PMax Audit + Update MCP — Design

**Date:** 2026-06-26
**Status:** Design approved, pending spec review
**Owner:** Ori (Happy Lolli LTD)

## Goal

Give Claude the ability to (1) **audit** that Happy Lolli's Google Ads Performance Max / Shopping
campaigns are configured well, and (2) — later — **update** campaign assets and configurations,
all through a custom MCP server that follows the existing `OI/tools/mcp/` pattern
(`oi_coach_server.py`, `gcs_server.py`, `deploy_server.py`).

The work is split into two phases. **Phase 1 is read-only** so it ships value the moment a
developer token clears and carries zero risk of changing the live account. **Phase 2 adds a gated
write layer** for updating assets and configs.

## Non-Goals

- Greenfield campaign creation from scratch (not what's wanted; can be added later).
- Managing other people's Google Ads accounts (single own-account use → **Basic access**, not Standard).
- Merchant Center product-feed health in Phase 1 (see Known Gap).
- Any autonomous mutation. Every write in Phase 2 is propose → confirm → apply (see Write-Safety Model).

## Background / Context

- Happy Lolli runs **Performance Max / Shopping** for the gift-box products (feed-driven).
- "Configured good" for PMax means asset-group coverage, ad strength, audience signals,
  listing-group structure, final-URL expansion, brand exclusions, and budget vs. target ROAS.
- "Assets" = image assets (landscape/square/portrait, logos, video) and text assets
  (headlines, long headlines, descriptions) linked into asset groups.
- This mirrors the existing Amazon coacher posture: **inspect → recommend → human uploads.**
  Relevant standing preferences: "coacher must only upload values it deliberately decided" and
  "Ori doesn't fully trust automation yet" → writes must be explicit and previewable.

## Architecture

A new Python stdio MCP server: `OI/tools/mcp/google_ads_server.py`, same shape as the other
`tools/mcp/` servers. Uses the official `google-ads` Python client. Credentials live in `OI/.env`
(never hardcoded), consistent with the global rule.

The code is organized into three modules with clean seams so Phase 2 slots in without reworking
Phase 1:

1. **`queries` (read)** — GAQL queries via `GoogleAdsService.search` / `search_stream`. Phase 1 only.
2. **`audit` (pure rules)** — pure functions: `config dict → findings list`. No I/O, fully unit-testable.
3. **`mutations` (write)** — Phase 2 only. `mutate`-based tools behind the propose/apply gate.

**Read-only is structural, not a flag:** Phase 1 contains no `mutate` call anywhere in the code
path, so it physically cannot alter the account.

### Authentication

- Developer token (from a Google Ads **Manager / MCC** account, **Basic** access tier).
- OAuth2 client ID + secret (created in GCP project `onyga-482313`).
- OAuth2 refresh token (generated once for the account).
- `login_customer_id` (the MCC) and `customer_id` (the Happy Lolli account).
- All stored in `OI/.env`:
  `GOOGLE_ADS_DEVELOPER_TOKEN`, `GOOGLE_ADS_CLIENT_ID`, `GOOGLE_ADS_CLIENT_SECRET`,
  `GOOGLE_ADS_REFRESH_TOKEN`, `GOOGLE_ADS_LOGIN_CUSTOMER_ID`, `GOOGLE_ADS_CUSTOMER_ID`.

## Phase 1 — Read-only Audit

### Tools exposed

| Tool | Returns |
|------|---------|
| `list_campaigns` | PMax/Shopping campaigns: status, budget, bid strategy, target ROAS |
| `get_asset_groups` | Asset groups per campaign + ad strength |
| `get_asset_group_assets` | Assets per group by field type (headline, long headline, description, marketing image, square image, logo, video) |
| `get_listing_groups` | Listing-group structure (all-products vs subdivided) |
| `audit_pmax` | Orchestrator: runs the above, applies the checklist, returns structured findings |

### Audit checklist (what "configured good" means)

Per asset group, against Google's PMax minimums / recommendations:

- **Text:** headlines ≥3 (rec 5), long headlines ≥1 (rec 5), descriptions ≥2 (rec 4), business name present.
- **Images:** ≥1 landscape (1.91:1) **and** ≥1 square (1:1); flag missing portrait (4:5); logo ≥1 square.
- **Video:** present, or note that Google auto-generates one if absent.
- **Ad strength:** below "Good" → flag.
- **Targeting/settings:** audience signal attached? final-URL expansion + brand exclusions set?
- **Campaign:** status sane, budget vs. target ROAS sanity check.

### Output

- Default: a **readable report in chat**.
- Flag to also dump raw findings JSON to `OI/exports/` for diffing config over time.
- Future option (not Phase 1): persist to a BigQuery `DE_`/`FACT_` table for config history,
  like other OI data.

### Known Gap (flagged, not silently skipped)

Product-**feed** health (disapprovals, missing GTINs) lives in **Merchant Center / Content API for
Shopping** — a separate API. Phase 1 audits the **Ads** side only and explicitly reports feed health
as "not checked — needs Content API." Addable in a later phase.

### Reporting limitation

Per-asset **performance** reporting (e.g. which headline performs best) is thinner in the Google Ads
API than the UI. The audit covers **coverage and configuration**, not per-asset performance ranking.

## Phase 2 — Gated Update Layer

Adds `mutate`-based tools so configs and assets can be changed from Claude.

### Write surface

- **Assets:** add / replace / remove headlines, long headlines, descriptions, images, logos, videos
  in an asset group (`AssetService` to upload new image/text assets, `AssetGroupAsset` to link/unlink).
- **Asset group:** status (enable/pause), name, final URLs, audience signals.
- **Listing groups:** subdivide products (by product type / item ID).
- **Campaign config:** budget, target ROAS, status, brand exclusions, final-URL expansion.

### Write-Safety Model (key requirement)

Mirrors the Amazon coacher's generate → review → upload flow. Every write is **two-step and never
autonomous**:

1. **`propose_*`** — runs the mutation in Google's **`validate_only` mode** (the API validates and
   returns errors **without applying**) and returns a **plain-English diff** of exactly what would change.
2. **`apply_*`** — executes the real mutation **only** when an explicit confirm is passed.

No tool ever mutates as a side effect of a read or an audit.

## Data Flow

```
Claude → audit_pmax(customer_id)
       → google_ads_server: queries (GAQL via google-ads client)
       → assemble config dict
       → audit rules (pure) → findings
       → JSON back to Claude → readable report (+ optional OI/exports/ JSON)

Phase 2:
Claude → propose_update_asset(...) → validate_only mutate → plain-English diff
       → (user confirms) → apply_update_asset(...) → real mutate
```

## Error Handling

- Missing/invalid `.env` var → error names the exact missing key.
- Dev-token not approved / wrong access tier → surface Google's error readably.
- `GoogleAdsException` → return the error codes/messages in readable form.
- Rate limits → surfaced, not swallowed.

## Testing (TDD)

- **Audit rules are pure** (`config dict → findings list`) → unit-tested against fixture JSON with no
  live API. This is the bulk of the test value and is written test-first.
- One live `list_campaigns` smoke test once credentials exist (read works on Basic access).
- Phase 2: `propose_*` tested with `validate_only` against fixtures / a test account before any
  `apply_*` touches the live account.

## Prerequisites — one-time manual setup (the real gate)

These are Ori-only steps; the MCP cannot proceed without them:

1. Confirm/create a Google Ads **Manager (MCC)** account → apply for a **developer token** (Basic access).
2. Create OAuth2 credentials in GCP (`onyga-482313`): client ID/secret → generate a refresh token.
3. Get the customer ID for the Happy Lolli account.
4. Put all values into `OI/.env`.

Detailed click-by-click steps for 1–3 to be provided when Ori is ready to start.

## Rollout

- **Phase 1:** build read-only audit MCP + audit rules + tests; wire into MCP config; validate against
  the live account once the token clears.
- **Phase 2:** add the gated update layer (propose/apply with `validate_only`).
- **Later (optional):** Merchant Center feed health (Content API); BigQuery config-history table.
