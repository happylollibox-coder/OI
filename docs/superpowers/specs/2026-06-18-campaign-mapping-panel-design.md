# Campaign Mapping Panel — Design Spec

**Date:** 2026-06-18
**Status:** Approved (design), pending implementation plan
**Branch:** feat/owned-negatives-coacher
**Author:** Ori + Claude

## 1. Problem

The dashboard Admin page lost its **Campaign → Strategy / Family mapping** panel. The
backend for it is fully built and live in `data-entry-app/app.py`:

- `GET  /api/admin/campaign-mapping` — list spending campaigns + current mapping + suggestion
- `POST /api/admin/campaign-mapping/assign` — approve a `{campaign_id, family, strategy}`
- `GET  /api/admin/mapping-coverage` — gap checks (are conversions/mappings done?)

…but **no React frontend exists** for it anywhere (not in git history, stashes, the old
`dashboard/` app, or Flask templates). This spec restores the frontend panel.

Why it matters: an unmapped/default-mapped spending campaign is silently dropped from
strategy evaluation, family rollups, and profit math. Mapping it is a recurring admin task.

## 2. Goal

Restore a self-contained **Campaign Mapping** panel on the Admin page that lets an admin:
- see which spending campaigns still need a family+strategy mapping (default view),
- review/correct already-mapped campaigns,
- assign a mapping per campaign, or accept all suggestions in one click,
- see at-a-glance coverage gaps.

## 3. Non-goals (YAGNI)

- No new backend endpoints — consume the three that already exist.
- No new nav page or routing — it lives as a `<Section>` on the existing Admin page.
- No editing of the suggestion engine (`V_CAMPAIGN_MAPPING_STATUS` / `SP_AUTO_ASSIGN_CAMPAIGNS`).
- No multi-select/bulk-checkbox UI beyond the single "Approve all suggestions" action.

## 4. Backend contract (existing — for reference)

### GET `/api/admin/campaign-mapping`
```json
{
  "success": true,
  "campaigns": [{
    "campaign_id": "string",
    "campaign_name": "string",
    "spend_60d": 1234.56,
    "current_experiment_id": "string | null",
    "current_experiment_name": "string | null",
    "current_strategy_id": "string | null",
    "suggested_family": "string | null",
    "suggested_strategy": "string | null",
    "suggested_experiment_id": "string | null",
    "confidence": 0.0,
    "source": "unmapped | default | manual | auto | ..."
  }],
  "families": ["Bottle","Bunny","Fresh","LolliBall","LolliME","Lollibox"],
  "strategies": ["BRAND_DEFENSE","CATEGORY_CONQUEST","COMPETITOR_CONQUEST","EXACT_BOOST","HUNTER","LOW_COST_DISCOVERY","PRODUCT_DEFENSE"]
}
```
Rows are pre-sorted: `(source IN ('unmapped','default')) DESC, spend_60d DESC`.

### POST `/api/admin/campaign-mapping/assign`
Body `{ "campaign_id", "family", "strategy" }`. Validates family ∈ families and
strategy ∈ strategies server-side. Creates the experiment if needed, then upserts
`DIM_EXPERIMENT_CAMPAIGN`. Returns `{ "success": true }`, or `{ "success": false, "error": "..." }`
with HTTP 400 (missing/invalid field) / 404 (campaign not found) / 500.

### GET `/api/admin/mapping-coverage`
```json
{ "success": true, "checks": [{
  "check_key": "string", "label": "string", "scope": "string",
  "total": 0, "mapped": 0, "gap": 0, "pct": 0.0, "critical": true,
  "items": ["...offending entities..."]
}]}
```

## 5. Component design

**New file:** `dashboard-react/src/components/CampaignMapping.tsx` — a sibling of
`NegativePhrases.tsx`, following the same conventions (`apiFetch`, `Card`, `Badge`,
`Section` wrapper supplied by the parent, success/error feedback toast).

**Placement:** `dashboard-react/src/pages/AdminPage.tsx`, a new
`<Section title="Campaign Mapping" count="Campaign → Strategy / Family">` rendered
**above** the existing Negative Phrases section.

### Layout (top → bottom)
1. **Coverage gap banner** — derived from `mapping-coverage`. One chip per check with
   `gap > 0` (`critical` chips red, others amber), showing `label` + gap count + `pct`
   mapped. When every gap is 0, collapses to a single green "All mapped" line.
2. **Toolbar**
   - Segmented toggle **`Not Mapped` | `Mapped`**, **default `Not Mapped`**.
     - *Not Mapped* = `source ∈ {unmapped, default}`.
     - *Mapped* = everything else.
   - **`Approve all suggestions`** button — visible/active **only in the Not Mapped view**.
   - Name **search** box (filters within the active view by `campaign_name`).
3. **Campaign rows** (filtered + searched). Each row shows:
   - `campaign_name` (+ small `campaign_id`)
   - `spend_60d` (money, `font-mono`, via `fM()`)
   - current mapping: `current_experiment_name` / friendly(`current_strategy_id`), or "—"
   - **source** badge, color-coded (unmapped/default = attention; manual/auto = neutral/green)
   - **suggestion**: friendly(`suggested_strategy`) + `suggested_family` + confidence %, when present
   - editable **Family** dropdown (from `families`) + **Strategy** dropdown (from `strategies`,
     rendered with a friendly label map), pre-filled from current mapping, else the suggestion
   - **Assign** button — disabled when family/strategy are incomplete or unchanged from current
4. **Feedback toast** — success/error, auto-dismiss (same pattern as NegativePhrases).

### Strategy label map (frontend, mirrors app.py `_STRATEGY_LABEL`)
```
EXACT_BOOST → Exact Boost, HUNTER → Broad Hunter, LOW_COST_DISCOVERY → Auto Discovery,
BRAND_DEFENSE → Brand Defense, PRODUCT_DEFENSE → Product Defense,
COMPETITOR_CONQUEST → Competitor Conquest, CATEGORY_CONQUEST → Category Conquest
```
Unknown strategy IDs fall back to the raw ID.

## 6. Behaviors

- **Assign (per row):** POST `{campaign_id, family, strategy}`. On success → toast
  "Mapped <campaign> → <Family> / <Strategy>", then refetch list + coverage (so the row's
  source badge flips to manual and gap counts drop). On error → toast the backend message.
- **Approve all suggestions:** acts only on the **Not Mapped** set, and only on rows that
  have BOTH `suggested_family` and `suggested_strategy` (incomplete suggestions skipped).
  Sequential POSTs; afterward toast "N applied, M failed" and refetch list + coverage.
  It can never overwrite an existing manual/auto mapping because those rows are not in scope.
- **Refetch:** any successful mutation refetches both `campaign-mapping` and `mapping-coverage`.

## 7. Data types (add to `types.ts` or local to the component)

```ts
interface CampaignMappingRow {
  campaign_id: string; campaign_name: string; spend_60d: number;
  current_experiment_id: string | null; current_experiment_name: string | null;
  current_strategy_id: string | null;
  suggested_family: string | null; suggested_strategy: string | null;
  suggested_experiment_id: string | null;
  confidence: number | null; source: string;
}
interface MappingCoverageCheck {
  check_key: string; label: string; scope: string;
  total: number; mapped: number; gap: number; pct: number;
  critical: boolean; items: string[];
}
```

## 8. Error handling

Unlike the current silently-empty admin panels, the fetch failure path is **visible**:
when `GET /api/admin/campaign-mapping` is not OK (e.g. backend down — the exact thing that
made Admin look broken), render an explicit "Couldn't load campaign mapping — is the API
running?" card instead of an empty table. Assign/approve errors surface the backend's
`error` string in the toast.

## 9. Testing

Vitest unit test (`CampaignMapping.test.ts` or co-located) for the **pure helpers**, factored
out of the component so they're testable without rendering:
- `needsMapping(row)` → `source ∈ {unmapped, default}`
- `approveAllEligible(rows)` → not-mapped rows that have both suggested_family and suggested_strategy
- `friendlyStrategy(id)` → label map with raw-ID fallback

Manual verification: restart local Flask (`env -u CUBEJS_API_SECRET PORT=5050 venv/bin/python app.py`),
load Admin in the preview, confirm the panel lists campaigns, the toggle defaults to Not Mapped,
the gap banner renders, a single Assign flips the source badge, and Approve-all reports a count.

## 10. Open questions

None — design approved 2026-06-18.
