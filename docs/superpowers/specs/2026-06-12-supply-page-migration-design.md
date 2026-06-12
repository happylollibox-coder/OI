# Supply Page Migration — Design Spec

**Date:** 2026-06-12
**Status:** Approved design, pending implementation plan
**Goal:** Move all data-entry functionality from the Flask app's HTML UI into the React dashboard's Supply page. The Flask app survives as a headless JSON API; its HTML UI is killed once the React UI is verified bug-free in real use.

---

## 1. Decisions (locked with Ori)

| Decision | Choice |
|---|---|
| Kill scope | Flask **UI only**. Flask stays alive as the write-API backend for BigQuery `DE_*` tables. |
| UI destination | **Everything under the Supply page** — POs, Shipments, Payments, Stock Snapshot, Costs Report as tabs. |
| Parity | **Strict parity first.** Same fields, validations, flows as the Flask forms. UX improvements only after parity is proven. |
| API security | **In scope, done first.** Bearer-token auth on `/api/*`, CORS narrowed to dashboard origins. |
| Rollout | **Incremental, tab by tab.** Both UIs coexist; each phase verified against the live Flask app before the next. |
| Read path | **Flask API for entry screens** (fresh BigQuery reads, write-then-read consistent); **Cube for analytics** (Stock Snapshot and existing summary tabs unchanged). |

---

## 2. Architecture

```
React Supply page ──reads/writes──> Flask /api/* ──> BigQuery DE_* tables
       │
       └── analytics reads (Stock Snapshot, summaries) ──> Cube.js
```

- **Shared API client:** `dashboard-react/src/utils/apiFetch.ts` (exists since `ff91564`) — attaches `Authorization: Bearer <dashboard_token>`; requests go through the `/api/*` proxy. All existing consumers already converted. May be extended with error normalization for the Supply forms.
- **Post-write refresh:** after any write, refetch the affected list from Flask. Flask already calls `clear_data_cache()` on writes, so reads are immediately consistent.
- **No optimistic UI.** Always confirm from the server response — parity with Flask's post-redirect-refresh behavior.

## 3. Phase 0 — API hardening + client plumbing

**Status: DONE** — implemented in commit `ff91564` (2026-06-12), see `architecture/API_AUTH.md`.

- `protect_api` `before_request` hook on all `/api/*` routes: requires the dashboard JWT (HS256, `CUBEJS_API_SECRET` — same token Cube verifies) or an allowed session cookie; OPTIONS exempt. New `/api` routes are protected by default.
- CORS narrowed from `*` to the `ALLOWED_ORIGINS` allowlist (Cloud Run dashboard origins + localhost:5173).
- Shared client: `dashboard-react/src/utils/apiFetch.ts` injects `Authorization` from `dashboard_token`; all 67 `fetch('/api/…')` call sites converted. **All new Supply-page code must use `apiFetch`, never raw `fetch`.**
- Calls go through the dev/nginx proxy at `/api/*` (Vite dev → local Flask :5050; Docker nginx → us-central1 Cloud Run), not a direct `VITE_DATA_ENTRY_URL` fetch.
- Browser-session routes (`/login`, `/auth/*`, HTML pages) untouched so the Flask UI keeps working during migration.

## 4. Flask API gap-fill (additive only)

JSON endpoints missing today (reads happen server-side in HTML routes):

- `GET /api/shipments` (list), `GET /api/shipment/<id>` (details + lines)
- `GET /api/payments` (list), `GET /api/payment/<id>` (details + lines)
- `GET /api/po/<id>` (full details; only `/api/po/<id>/lines` exists today)
- `GET /api/costs-report`
- `GET /api/lov` — all LOV sets in one call, mirroring `get_lovs()` (per-set `GET /api/lov/<set>` already exists)
- JSON write equivalents where only HTML-form routes exist (payment create/edit, some shipment/PO line ops — exact list produced by the Phase 0 endpoint audit)

**Rule:** each new endpoint wraps the **exact same query/insert code** the HTML route uses today — extracted into shared functions, not rewritten. The working logic is the benchmark; it is never re-implemented.

## 5. LOVs and automatic logic (parity-critical)

### 5.1 List of Values (`DE_LOV`)
- All dropdowns (supplier, shipment type, service type, currency, payment method, …) are fed from `DE_LOV` including `is_default` preselection and `attr1/attr2` metadata.
- React forms load all sets via the new `GET /api/lov`, honor `is_default` (preselect), and apply attr metadata exactly as the Jinja templates do.

### 5.2 Server-side auto-logic — stays in Flask, never reimplemented in React

| Auto-logic | What it does |
|---|---|
| `generate_payment_id()` | Meaningful `PAY_YYYYMMDD_VENDOR_PRODUCT_MMM` IDs with dedup counters |
| `generate_other_po_id()` | Deterministic `PO_date_vendor_service` IDs with collision suffix |
| `generate_id()` | UUID-based IDs for all other records |
| `auto_close_received_shipments()` | Flips shipments to RECEIVED when ETA passed and paid |
| `sync_shipment_paid_status()` | Recomputes `is_paid`/`paid_date` from payment totals vs shipment cost |
| PO `total_amount` recalcs | Totals updated on line add/edit/delete |
| `get_products()` | Cached product hierarchy (parents) for product selects |
| `clear_data_cache()` | Cache invalidation after every write |

React forms send **raw user input only** — never client-generated IDs, statuses, or computed totals. Every new JSON endpoint must trigger the same helpers as its HTML-route twin (~18 call sites audited). Each phase's parity checklist has a line item per auto-behavior.

### 5.3 Client-side form logic ported 1:1
Jinja/JS conveniences ported faithfully to React (display-only; server still computes on save):
- Shared product-select with parent hierarchy (`_product_select.html`)
- Live line-total / grand-total display
- Field cascades (e.g. vendor → currency default)
- Bulk-payment row builders (both bulk flows)

## 6. Supply page structure (strict parity)

Tab bar extends to: **POs · Shipments · Payments · Stock Snapshot · Costs Report**

- Existing read-only tables become editable: row click opens a detail drawer/modal (replacing Flask detail pages) with the same fields, inline line-item add/edit/delete, linked records, and delete actions.
- "New PO" (incl. Other PO), "New Shipment", "New Payment", "Bulk Payments" buttons open modal forms — same fields, validations, defaults as Flask forms.
- Reuse existing components (Table, SearchableDropdown, PODetailsModal as starting point) and dashboard styling.

## 7. Phases

| Phase | Scope |
|---|---|
| 0 | ✅ DONE (`ff91564`) — API auth + CORS, shared API client, consumers repointed. Remaining: endpoint/auto-logic audit |
| 1 | POs — list + details drawer + new-PO/other-PO forms + line editing + delete/bulk-delete |
| 2 | Shipments — list + details + new form + line ops + bulk update |
| 3 | Payments — list + details + new form + both bulk-entry flows |
| 4 | Costs report + leftovers surfaced by the Phase 0 audit |
| 5 | Kill checklist — confirm zero traffic to Flask HTML routes (Cloud Run logs), strip templates/HTML routes, Flask becomes API-only |

Each phase ends with side-by-side verification: same action in both UIs, confirm identical BigQuery rows (including auto-generated IDs, statuses, and totals).

## 8. Error handling

- Every write surfaces Flask's error response verbatim in a toast; failed writes never clear form state.
- API client distinguishes auth failures (re-acquire token, retry once) from validation/server errors (surface to user).

## 9. Testing & verification

- Per phase: browser-level verification (preview tools / Playwright MCP) of create → edit → delete round-trips on test records, with BigQuery checks, then cleanup of test rows.
- Parity checklist per phase covers: all form fields, all validations, all LOV dropdowns + defaults, and every server-side auto-behavior in §5.2.

## 10. Out of scope

- UX redesign (post-parity).
- Migrating the Flask API itself to another backend.
- Non-supply API consumers (Coach, Research, Plans endpoints) — they keep working unchanged behind the same hardened auth.
