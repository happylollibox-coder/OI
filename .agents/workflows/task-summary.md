---
description: After finishing every task, write a summary of what each change did
---

# Task Summary Workflow

After completing every task (bug fix, feature, cleanup), write a summary documenting what was done.

## What to include

For each change, write **one line** covering:
- **File** — what file was changed
- **What** — what the change does
- **Why** — root cause or motivation

## Format

Use a table or bullet list. Group by component:

```
### SQL
- `V_EXPERIMENT_TERM_RECOMMENDATIONS.sql` — Added (8w) time annotations to all reason strings. Root cause: reason said "3 organic purchases" but SQP Orders(4w) column showed 0 — different time windows.

### Cube
- `AdsCoachDecision.js` — Added 35+ new dimensions for Ads/SQP measures.

### React
- `ActionsPage.tsx` — Fixed duplicate campaign rows in expanded view. Root cause: campaignIndex wasn't aggregating by campaign_name.
```

## Where to write

Update the walkthrough artifact at:
`<artifactDir>/walkthrough.md`

## Rules

1. **Every task gets a summary** — no exceptions.
2. **Bug fixes must include**: Root cause → Fix → Verification.
3. **If you deployed SQL**, note the deploy status.
4. **If you took screenshots**, embed them.
5. **Be concise** — one line per file, not paragraphs.

## Example: This Session's Summary

### SQL (deployed ✅)
- `V_ADS_COACH_DECISION.sql` — Added 35+ new Ads/SQP columns (4w, LY Peak, Amazon market).
- `V_EXPERIMENT_TERM_RECOMMENDATIONS.sql` — Added (8w) time annotations to all reason text. Fixed stale `DIM_PRODUCT.cost_of_goods` reference.
- 5 more views + 1 proc — Cleaned up stale `p.cost_of_goods + p.shipping_cost` → `COALESCE(ch.TOTAL_COST_PER_UNIT, 0)`.

### Cube
- `AdsCoachDecision.js` — 35+ new dimensions matching SQL view.

### React
- `ActionsPage.tsx` — (1) Expanded column picker to 50+ columns. (2) Fixed duplicate campaign rows by aggregating campaignIndex. (3) Changed Do queue to store campaign names instead of experiment_id.
- `useCubeData.ts` — Expanded loader to fetch 55+ dimensions.
- `types.ts` — `CoachDecisionRow` expanded 23→68 fields.

### Workflows
- `/dashboard-testing` — Strict Cube→Vite→Data verification order.
- `/task-summary` — This workflow.
