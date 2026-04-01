# 🎯 PPC Specialist Audit → UX Agent Brief

*What does a PPC manager need to answer, and does OI answer it well?*

**Data freshness context:** Ads = 1-day lag · Performance = 3-day lag · SQP = 10-day lag

---

## Daily Questions

### Q1: "Am I wasting money right now?"

**Most important answer:** A ranked list of keywords/search terms burning cash with zero return — sorted by wasted $ — with clear STOP/REDUCE labels.

| OI Support | Grade |
|---|:---:|
| ✅ ACTION page shows "Urgent 6 · Spend $119.82" with per-keyword actions | **A** |
| ✅ ADS page shows "Wasted: $382.50" in summary bar | |
| ⚠️ Missing: WHY it's wasting (low CTR? wrong ASIN? bad listing?) — the ACTION cards show the signal (WASTED_SPEND / UNPROFITABLE) but not the diagnostic | |

**UX recommendation:** Add a small "reason" tag per urgent action: `wrong ASIN` · `low CTR (0.3%)` · `high CPC ($1.70)` — so the manager knows the fix, not just the problem.

---

### Q2: "Is this week better or worse than last week?"

**Most important answer:** A single WoW comparison line: *"Profit ↑15%, Spend flat, ROAS ↑12%, Organic share ↑22%"* — in 1 second.

| OI Support | Grade |
|---|:---:|
| ✅ Header shows Net Profit $2,684 · Net ROAS 1.75x | **B+** |
| ✅ Metric cards show △% changes (e.g., +15.7%, +21.6%) | |
| ⚠️ **Period mismatch:** Header shows Mar 8-14, but metric cards show Mar 1-7 with $0 Ads Spend. This creates instant confusion — "are ads broken?" | |

**UX recommendation:** Sync all HOME sections to the same period. Show the latest **complete** week everywhere. If a data source has a lag, grey out that cell with a tooltip "data arrives in X days" rather than showing $0.

---

### Q3: "Which product families make money and which don't?"

**Most important answer:** A table ranked by **Net Profit per unit** showing: family → NP/Unit → ROAS → Organic% → trend direction.

| OI Support | Grade |
|---|:---:|
| ✅ HOME table: LolliME $12.22 NP/Unit, Lollibox $24.18, Fresh $20.63, Bottle $13.60 | **A** |
| ✅ Shows Sales, COGS, Ads Spend, NP, ROAS, TACoS, Units, Organic % all in one row | |
| ✅ "Efficient scaling" badges with dot indicators | |

**This is one of OI's strongest features.** No change needed.

---

## Weekly Questions

### Q4: "Which search terms should I scale, and which should I kill?"

**Most important answer:** Two lists side-by-side: **Winners** (high ROAS, orders, room to grow) vs **Losers** (spent $X, 0 orders) — with the market size for context.

| OI Support | Grade |
|---|:---:|
| ✅ ADS page: "Best Search Terms" table with Spend, Orders, Conv%, CPC, ROAS, **SQP Vol** | **A** |
| ✅ Spend threshold buttons ($3 / $5 / $10 / $20) to filter noise | |
| ✅ SQP cross-reference is unique — e.g., "teen girl gifts trendy stuff" = 210K SQP volume | |

**No change needed.** The ADS drill-down with SQP cross-reference is a unique competitive advantage.

---

### Q5: "Am I advertising the right product for each keyword?"

**Most important answer:** A YES/NO match table: keyword → which ASIN is showing → which ASIN *should* show (Hero) → action if mismatched.

| OI Support | Grade |
|---|:---:|
| ✅ KWDS page: Keyword → Product → Hero → Match? (YES/NO) → Action | **A+** |
| ✅ Color-coded YES (green) / NO (red) with PROMOTE / REDUCE BID / MONITOR labels | |
| ✅ SQP Mkt Vol shows if the keyword is worth fighting for | |

**This is OI's killer feature.** No Amazon tool does this. No change needed.

---

### Q6: "Which ad strategies are working and which should I pause?"

**Most important answer:** Strategy-level ROAS comparison + auto-generated insight on what to scale/pause.

| OI Support | Grade |
|---|:---:|
| ✅ STRAT: 7 strategies with live spend + ROAS (Hunter 2.45x, Brand Defense 0.55x) | **A+** |
| ✅ LEARN: Auto-generated insights — "Best performer: Fresh Collection – Brand Defense (avg 101.63x ROAS)" | |
| ✅ LEARN: "Scale candidates" list auto-identified, "ROAS declining for 3+ weeks — pause or restructure" | |
| ✅ "+ New Conclusion" button to build knowledge base | |

**Best-in-class feature.** The STRAT → LEARN loop replaces hours of manual analysis. No change needed.

---

### Q7: "How is my market share trending? What keywords am I missing?"

**Most important answer:** Our orders vs total Amazon orders per keyword, trending over time — plus a list of high-volume keywords we're NOT advertising on.

| OI Support | Grade |
|---|:---:|
| ✅ SQP page: "You vs Amazon Total" orders chart, Show Rate %, CTR, Conv% | **A-** |
| ✅ 22K keywords with SQP + Ads data cross-referenced | |
| ✅ ACTION page identifies NOT_TARGETED high-volume keywords with "NEW" action | |


**UX recommendation:** In the SQP "You vs Amazon Total" chart, add a "Gap" annotation: *"Amazon total grew 20% but your orders flat → you're losing share"* — make the insight explicit, not just visual. Currently requires visual interpretation.

---

### Q8: "Are we ready for the next peak season?"

**Most important answer:** LY vs TY comparison by phase (Pre-Peak → Boost → Peak) with a readiness checklist.

| OI Support | Grade |
|---|:---:|
| ✅ PEAK page: Easter phases with LY vs TY metrics, readiness checklist | **B+** |
| ⚠️ No budget allocation recommendation per phase | |

**UX recommendation:** Add a "Suggested weekly spend" row per phase based on LY spend × TY sales growth rate. Even a rough estimate helps planning.

---

## Summary for UX Agent

### What's A+ (don't touch)
- **KWDS Hero matching** — unique competitive advantage
- **LEARN auto-insights** — replaces hours of manual analysis
- **STRAT portfolio view** — strategy-level management
- **ADS search term table with SQP cross-reference** — no other tool does this

### What Needs Fixing

| # | Fix | Impact | Effort |
|:---:|---|---|---|
| 1 | **Sync HOME periods** — all cards/tables/header should show the same week. Show "—" with lag tooltip instead of $0 | Eliminates "are ads broken?" false alarm | Low |
| 2 | **Add "reason" tags on ACTION urgent items** — `wrong ASIN` · `low CTR` · `high CPC` | Tells manager the fix, not just the problem | Medium |
| 3 | **Explicit SQP gap annotation** — "you're losing share" callout on the chart | Makes the insight immediate instead of requiring interpretation | Low |
| 4 | **PEAK budget suggestion** — rough recommended spend per phase | Turns retrospective into planning tool | Medium |
