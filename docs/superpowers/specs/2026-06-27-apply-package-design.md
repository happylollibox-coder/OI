# Execution / Apply Package (Coacher sub-project F)

- **Date:** 2026-06-27
- **Owner:** Ori
- **Status:** v1 BUILT (autonomous, prepare-only). Spec for the record.
- **Parent vision:** the per-product coacher. **F** is "perform the plan" — turning the coacher's decisions into something applied to Amazon Ads.
- **Decisions (from Ori):** **Prepare-only** (no API writes / no auto-spend); execution is **manual bulksheet upload** (no Amazon Ads write API configured). So F prepares a clean, deduped, ready-to-upload set; Ori reviews + uploads.
- **Builds on:** `V_ADS_COACH` (decisions), D's plan budgets. Backend only ([[feedback_all_logic_in_backend]]) — today the bulksheet logic lives in the frontend (`DoPage.tsx` `exportBulksheet`), which this moves toward the backend.

---

## 1. Problem

`V_ADS_COACH` is at **search-term × keyword grain** — a single keyword fans out ~104× (live: 9,230 bid-action rows across only **89** keywords). A bulksheet built naively from it is almost entirely duplicate `Update` rows, and Amazon **rejects the whole upload for "Duplicate Id"** (the known bug). The apply logic also lives in `DoPage.tsx`, violating the all-logic-in-backend rule. F fixes both: a backend view emitting **one deduped apply row per entity**.

## 2. Component 1 — `V_COACH_APPLY` (v1: keyword bids)

A backend view emitting one row per entity to change, deduped:
- **`KEYWORD_BID`** — one row per `keyword_id`, picking the highest-priority row's `target_action` + `recommended_bid` (keyword-grain logic is repeated across search-term slices; `ARRAY_AGG(... ORDER BY priority_score DESC, ABS(bid_change_pct) DESC LIMIT 1)` makes the pick deterministic and contradiction-free). Columns: `entity_type, entity_id, campaign_id, parent_name, operation('Update'), current_bid, new_bid, bid_change_pct, source_action, priority_score`.
- Live: 9,230 → **89** rows, 0 duplicates, 0 over-ceiling.

The frontend `DoPage` formats these rows into the Amazon Bulksheet v2.0 XLSX (presentation only). 

## 3. Scope

**In (v1):** `V_COACH_APPLY` (deduped keyword-bid apply rows); `config.yaml`.
**Deferred (v1.1):** budget-apply rows (campaign daily budget ≈ D's `planned_spend / 7`, needs a cell→campaign rollup); negative-keyword apply rows; rewiring `DoPage.exportBulksheet` to read `V_COACH_APPLY` (so the frontend stops owning the dedup/selection logic); PROBE/Create rows.
**Out:** any Amazon Ads **API mutation** / auto-push (no write creds; Ori uploads manually) — that's a future, separately-authorized effort.

## 4. Risks & limits

- **Prepare-only** — F never spends; the human applies. No rollback needed.
- **Dedup pick** is by `priority_score` then `|bid_change_pct|`; assumes keyword-grain decisions are consistent across slices (they are, post the earlier TARGET-grain dedup fixes) — the pick is a safety net, not a tie-break of genuine conflicts.
- v1 covers **keyword bids only**; budgets/negatives/Creates are v1.1.
- Observational; the bulksheet still requires the materialized refresh + a human upload.

## 5. Testing

- `V_COACH_APPLY`: one row per `entity_id` (0 duplicates); `new_bid ≤ 2.0` (ceiling); `source_action ∈ {INCREASE_BID, REDUCE_BID, PROBE}`; row count = distinct keyword_ids with a bid action.
