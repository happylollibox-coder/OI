# Supply Page — Phase 5 (Kill the Flask HTML UI) Plan

> **DESTRUCTIVE. Do not execute the deletions until the preconditions below are met AND Ori gives explicit go-ahead.** This plan documents the steps; it is intentionally not auto-run.

**Goal:** Remove the Flask data-entry app's HTML UI (page routes + Jinja templates), leaving Flask as an API-only backend for the dashboard. Phases 1–4 replaced the PO / Shipment / Payment / Costs screens in the React Supply page.

## ⚠️ Preconditions (MUST all hold before deleting anything)
1. **The dashboard Supply work is deployed to production.** All of it currently lives on the unmerged branch `feat/owned-negatives-coacher` (interleaved with a concurrent coacher session). Until that's merged to the deployed dashboard, the Flask HTML UI is the ONLY working data-entry UI — deleting it now would leave production with no data-entry tool.
2. **The deployed dashboard Supply page is verified in production** (create/edit/delete for POs, Shipments, Payments, Costs all work against prod).
3. **Cloud Run access logs show zero (or only your own test) traffic to the Flask HTML routes** over a representative window (e.g. 1–2 weeks): `/`, `/po/*`, `/orders/new`, `/other_po/*`, `/shipments*`, `/shipment/*`, `/payments*`, `/payment/*`, `/costs-report`. (Query via `gcloud logging` on the `data-entry-forms` service.)
4. **Ori's explicit confirmation** to proceed with deletion.

## What is safe to remove vs MUST stay
**Remove (HTML surface only):**
- Jinja templates in `data-entry-app/templates/` for the migrated screens: `index.html`, `po_details.html`, `other_po_details.html`, `order_form.html`, `other_po_form.html`, `shipment_form.html`, `shipment_details.html`, `shipments_list.html`, `payment_form.html`, `payment_details.html`, `payments_list.html`, `bulk_payment_form.html`, `bulk_po_payment_form.html`, `costs_report.html` (and `_product_select.html`, `base.html` once nothing renders).
- The HTML page routes that `render_template(...)` these: `index`, `po_details`, `update_po`, `new_other_po`, `other_po_details`, `delete_other_po`, `new_order`, `shipments_list`, `new_shipment`, `add_shipment_row`, `shipment_details`, `update_shipment`(HTML), `delete_shipment`(HTML), shipment line HTML routes, `payments_list`, `new_payment`, `bulk_new_payments`, `bulk_po_payments`, `payment_details`(HTML), `add_payment_line`(HTML), `delete_payment`(HTML), `delete_payment_line`(HTML), PO line HTML routes, `costs_report`.

**MUST stay (the API depends on them):**
- ALL the shared helper functions the JSON twins call: `insert_purchase_order`, `update_purchase_order`, `add_po_line`, `delete_po_line`, `update_po_line`, `delete_po`, `insert_other_po`, `delete_other_po_record`, `get_po_details`, `insert_shipment`, `get_shipment_details`, `update_shipment`, `delete_shipment_record`, `add_shipment_line`, `update_shipment_line_fields`, `delete_shipment_line_record`, `insert_payment`, `update_payment`, `get_payment_details`, `delete_payment_record`, `delete_payment_line_record`, `bulk_create_shipment_payments`, `bulk_create_po_payments`, `get_costs_history`, `get_open_pos_for_shipment`, `get_products`, `get_lovs`, `generate_payment_id`, `generate_other_po_id`, `generate_id`, `sync_shipment_paid_status`, `auto_close_received_shipments`, `clear_data_cache`, `@cache_result`.
- ALL `/api/*` routes (the dashboard's backend).
- Auth: the `protect_api` JWT gate, `/api/auth/dashboard-token`, the OAuth/session machinery, `ALLOWED_USERS`, `@login_required` (still used by the token-issuing flow), CORS allowlist.
- Other non-Supply API routes (plans, alerts, research, coach, ppc-change-log, shipment-plan, etc.) — untouched.

## Procedure (when greenlit)
1. **Branch**: do it as its own change on the canonical branch; small, reviewable commits.
2. **Delete templates** for the migrated screens.
3. **Delete the HTML page routes** that rendered them. After each removal run `python -m py_compile app.py`; grep for any remaining `render_template('<deleted>.html')` and any `url_for('<deleted_route>')` references (in surviving routes or templates) — fix/remove dangling references. The HTML routes were refactored in Phases 1–3 to call shared helpers, so the helpers stay; only the route wrappers + form parsing go.
4. **Verify the API still fully works**: re-run the Phase 1–4 live round-trips (PO/shipment/payment create→edit→delete, costs, bulk) against the running app — confirm no regression from the deletions.
5. **`requirements`/imports cleanup**: if removing templates makes any import unused, drop it (don't remove Flask/jinja — still needed for jsonify/routing).
6. **Redeploy** Flask (API-only) to Cloud Run; smoke `/api/*` from the deployed dashboard.
7. Optionally keep a tiny landing route at `/` that 302s to the dashboard, so the old bookmark isn't a hard 404.

## Why this isn't run now
The dashboard replacement is not yet merged/deployed to production, so the Flask HTML is still the live data-entry UI. Executing this plan before the cutover would remove the only working UI. Revisit once preconditions 1–4 hold.
