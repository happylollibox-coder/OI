# Auto-fill Shipment ETA from Shipment Type

**Date:** 2026-06-03
**Component:** `dashboard-react/src/components/Actions/CreateShipmentModal.tsx` (+ a small pure helper, likely `dashboard-react/src/utils.ts` or a local module)
**Status:** Design approved, pending implementation plan

## Problem

When creating/editing a shipment, the user picks a **shipment type** (transit mode: FAST_SEA / SLOW_SEA / AWD_SLOW_SEA / AWD_TRANSFER / AIR) but the **estimated arrival date** does not auto-fill — it must be typed manually. The user wants the ETA set automatically when the shipment type is decided: `ETA = ship_date + transit_days(type)`.

Today the only auto-calc lives in the backend (`app.py:1281-1298`) and is flawed: a **hardcoded** `days_map = {SLOW_SEA: 33, FAST_SEA: 27, AIR: 10}` that **omits AWD_SLOW_SEA (63) and AWD_TRANSFER (14)**, drifts from the authoritative source, and only fires if ETA is empty (so changing the type never updates it). `SP_GENERATE_SHIPMENT_PLAN` already computes `arrival_date = ship_date + transit_days` using `DE_LIST_OF_VALUES` — that is the source of truth.

## Decisions (from brainstorming)

- **Where:** the **React shipment UI** (`CreateShipmentModal`) — ETA recomputes live as the type/date are picked, before saving.
- **Lead-time source:** **`DE_LIST_OF_VALUES`** (`lov_set='SHIPMENT_TYPE'`, `attr1_value` = transit days) via the existing `GET /api/lov/SHIPMENT_TYPE` endpoint. No hardcoding; same source the SP uses; covers all types.
- **Overwrite behavior:** **recompute on every type/date change** (auto-fills, overwriting a prior value). The ETA field stays hand-editable between changes.
- **Scope:** **shipments only.** The PO `estimated_arrival_date` (the Bunny case) is out of scope — those POs are unpaid/unconfirmed with no shipment yet.

## Transit days (from `DE_LIST_OF_VALUES`, SHIPMENT_TYPE)

| value_id | days (`attr1_value`) |
|---|---|
| AIR | 10 |
| FAST_SEA | 27 |
| SLOW_SEA | 33 |
| AWD_TRANSFER | 14 |
| AWD_SLOW_SEA | 63 |

## Design

### 1. Load the lead-time map (live)
On modal mount, fetch `GET /api/lov/SHIPMENT_TYPE`. Build `transitDays: Record<string, number>` mapping each `value_id` → `Number(attr1_value)`. Cache in component state. If the fetch fails, `transitDays` is empty and auto-fill is a no-op (the field stays manual) — never block shipment creation on the LOV call.

### 2. Pure helper `etaFromType`
```ts
// ship date (ISO 'YYYY-MM-DD') + transitDays[type] → ISO date; null when the type/date is unusable
etaFromType(shipDateISO: string, type: string, transitDays: Record<string, number>): string | null
```
Returns `null` if `shipDateISO` is empty/invalid or `transitDays[type]` is missing — caller leaves the existing ETA untouched on `null` (don't clobber with garbage). Date math is UTC-noon-safe (avoid TZ off-by-one).

### 3. Recompute wiring
- **Top-level shipment:** a `useEffect` on `[shipmentType, shipmentDate, transitDays]` sets `setEstimatedArrival(etaFromType(...) ?? prev)`. On every type/date change ETA recomputes.
- **Per-split headers:** the modal also holds `headers[]`, each with its own `shipment_type` / `shipment_date` / `estimated_arrival_date`. When a split header's `shipment_type` or `shipment_date` changes (via `updateSplitHeader`), recompute that header's `estimated_arrival_date` with the same helper.
- **Editability:** the ETA input remains editable; a manual edit persists until the next type/date change re-auto-fills.

### 4. Backend
No backend change required for this request — the modal now always sends a computed `estimated_arrival_date`, so the `app.py` `days_map` branch (only fires when ETA is empty) never runs. **Recommended follow-up (out of scope):** replace that hardcoded `days_map` with a read from `DE_LIST_OF_VALUES` so non-UI API saves also cover AWD types — same drift the user hit.

## Testing

- **Unit (Vitest):** `etaFromType` — FAST_SEA(+27), AWD_SLOW_SEA(+63), AIR(+10); returns `null` for unknown type or empty date; no TZ off-by-one across a month/DST boundary.
- **Live:** open the shipment modal → pick a type → ETA fills (`ship_date + days`); switch type → ETA updates; verify a split header recomputes independently; confirm a manual ETA edit survives until the next type/date change.

## Scope

**Changes:** `CreateShipmentModal` fetches the LOV map, adds `etaFromType` + the recompute effects (top-level + per-split). One small pure helper + its test.

**Keeps unchanged:** the save endpoint, `SP_GENERATE_SHIPMENT_PLAN`, the shipment schema, the PO `estimated_arrival_date`, and the backend `days_map` (flagged as a follow-up).

**Out of scope:** writing the PO `estimated_arrival_date`; the Bunny PO-confirmation issue; per-product `shipment_days` (the transit days are per-type, from the LOV).

## Open questions / risks

- **Type value match:** the modal's `shipment_type` values must equal the LOV `value_id`s (FAST_SEA, SLOW_SEA, AWD_SLOW_SEA, AWD_TRANSFER, AIR). Confirm during implementation that the modal's type selector uses these exact ids; if it uses captions, key the map by caption instead.
- **Overwriting a deliberate manual ETA:** "recompute on every change" means changing the type wipes a hand-typed ETA. Accepted per the decision; the field is re-editable afterward.
