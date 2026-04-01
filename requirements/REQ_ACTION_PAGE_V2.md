# REQ: ACTION Page V2

**Status:** 🟡 IN PROGRESS — PPC section complete, pending UX + Developer sections
**Date:** 2026-03-15
**Agents:** PPC Specialist → UX Agent → Developer

---

## 📋 Protocol

Each agent adds their section in order. The developer implements only after all sections are complete.

| Agent | Role | Status |
|---|---|:---:|
| **PPC Specialist** | Business requirements — WHAT and WHY | ✅ Done |
| **UX Agent** | Design decisions — HOW it looks and behaves | ⬜ Pending |
| **Developer** | Technical implementation — HOW it's built | ⬜ Pending |

---

## 1. PPC Specialist — Business Requirements

### REQ-1: Ads Spend Pie Chart (Budget Health Visualization)

**Business need:** I need to see in 1 second "what % of my ad spend is wasted vs profitable."

**Buckets:**

| Bucket | Rule | Color intent |
|---|---|---|
| **NOT CONVERTING** | Spend ≥ $3, Orders = 0 | Red — waste |
| **LOSING** | Orders > 0 but Net ROAS < 1x | Orange — unprofitable |
| **WINNING** | Net ROAS 1x – 3x | Green — profitable |
| **BEST** | Net ROAS > 3x | Blue/gold — star performers |

**Behavior:**
- Pie chart shows % of total spend per bucket
- Center of pie: total spend amount
- Clicking a slice filters the action table below to show only those terms
- Show both the $ amount and % per slice

**Data source:** Same data as the current action/ads search term views — just aggregated into buckets.

---

### REQ-2: Campaign-Level Action Instructions

**Business need:** When I click STOP/REDUCE BID/PROMOTE on a search term, I need to know exactly what to do **per campaign** — because Amazon works at the campaign level, not at the keyword level globally.

**Rules by campaign match type:**

| Action | Exact/Phrase Campaign | Auto/Broad Campaign |
|---|---|---|
| **STOP** | Pause/remove the keyword | Add as **negative exact** keyword |
| **REDUCE BID** | Lower keyword bid to suggested $ | N/A (bid is at campaign level) |
| **PROMOTE** | Increase keyword bid / create new exact campaign | Extract to dedicated exact campaign |
| **NEW** | Create new exact keyword in existing/new campaign | Already running via auto/broad |

**Behavior:**
- Clicking an action button (e.g., STOP) on a search term opens a panel/modal
- Panel shows every campaign that contains this search term
- For each campaign: shows campaign name, match type, current spend on this term, and the specific instruction
- Bottom of panel: **"Copy as Bulk Sheet"** button — generates CSV/text in Amazon bulk upload format
- Bottom of panel: **"Mark as Done ✓"** button — records the action in the change log

**Campaign lookup:** The system already has `FACT_AMAZON_ADS` with `campaign_id` per search term, and `DIM_EXPERIMENT_CAMPAIGN` links campaigns to experiments. We need to resolve which campaign(s) contain this search term and determine their match type.

**Example output:**

```
📋 STOP "10 year old girl gifts" — $22.52 spent, 0 orders

Campaign                                  Match Type    Action
─────────────────────────────────────────────────────────────────
Lollibox-SP/BROAD (Hunter)                BROAD         → Add NEGATIVE EXACT
Lollibox-SP/AUTO (Discovery)              AUTO          → Add NEGATIVE EXACT  
White Lollibox-SP/EXACT (Boost)           EXACT         → PAUSE keyword

[Copy Bulk Sheet]  [Mark Done ✓]
```

---

### REQ-3: Action priority & grouping

**Business need:** Actions should be grouped by urgency, with spend amounts visible.

**Priority order:**
1. 🔴 **STOP** — Wasted spend, kill it now
2. 🟠 **REDUCE BID** — Unprofitable, trim it
3. 🟢 **PROMOTE** — Working well, invest more
4. 🔵 **NEW** — Untapped opportunity, start testing

**Each group header shows:** count of items + total spend in that group

---

## 2. UX Agent — Design & Interaction

> ⬜ **PENDING** — UX Agent to fill this section with:
> - Layout: where pie chart goes relative to the action table
> - Pie chart interaction design (hover states, click-to-filter, animation)
> - Action modal/panel design (slide-out panel vs modal vs inline expand)
> - Bulk sheet copy format and confirmation UX
> - "Mark as Done" state management (optimistic UI? toast confirmation?)
> - Mobile/responsive considerations
> - Color palette for buckets (aligned with dashboard theme)
> - Empty states (what if no actions in a bucket?)

---

## 3. Developer — Technical Implementation

> ⬜ **PENDING** — Developer to fill this section with:
> - Data layer changes (new views/cubes needed?)
> - Campaign match type resolution logic
> - Bulk sheet CSV format specification
> - Change log integration for "Mark as Done"
> - State management approach
> - Component architecture
> - Performance considerations (pie chart re-render on filter change)

---

## Reference Documents

- [PPC Specialist Audit](../ppc_specialist_audit.md) — full dashboard audit
- [Strategy Tracking Framework](../strategy_tracking_framework.md) — per-strategy KPI framework
