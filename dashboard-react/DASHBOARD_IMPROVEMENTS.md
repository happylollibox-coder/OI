# OI Dashboard — Improvement Brief

> **Date:** 2026-03-15
> **Compiled from:** PPC Specialist Audit · UX Audit · UI Visual Plan · Content Strategy Audit
> **Target:** React dashboard in `dashboard-react/`

---

## Don't Touch (A+ Features)

All four audits agree — polish only, no redesign:

- **KWDS Hero matching** — keyword → ASIN → Hero match YES/NO with action badges
- **LEARN auto-insights** — auto-generated strategy conclusions + scale candidates
- **STRAT portfolio view** — 7 strategies with live ROAS + "Questions to Answer" tracker
- **ADS + SQP cross-reference** — search term table with SQP market volume
- **HOME family profitability table** — NP/Unit + ROAS + Organic% in one row

---

## Already Completed (UI pass)

| Change | File |
|---|---|
| Added **Fira Sans** as primary UI font | `src/index.css` |
| Light mode contrast bump (`--color-muted` 6e→63, `--color-faint` ae→8e) | `src/index.css` |
| Card borders visible in light mode (`--color-border` opacity 0.06→0.14) | `src/index.css` |
| Sidebar light mode override (warm Apple-style `rgba(245,245,250,0.85)`) | `src/index.css` |
| `.section-divider` + `.card-lift` utilities added | `src/index.css` |
| Header KPI pills — colored accent dots, 12-13px fonts, more spacing | `src/components/Header.tsx` |
| Sidebar labels 9px→10px, rounded active highlight | `src/components/Sidebar.tsx` |
| Filter bar spacing gap-2→2.5, theme-aware button groups | `src/components/FilterBar.tsx` |
| Filter bar `bg-zinc-900/50`→`bg-inset` | `src/components/FilterBar.tsx` |
| PEAK dropdown `bg-zinc-900`→`bg-inset` | `src/pages/PeakPage.tsx` |
| Content area breathing room (px-7→8, py-4→5) | `src/App.tsx` |

---

## P0 — Critical

### 1. HOME Period Sync
**Files:** `src/pages/HomePage.tsx`, `src/hooks/useFilters.ts`
**Source:** PPC Audit Q2 · UX Audit #1

All cards, tables, and header MUST show the same time period. Current bug: header shows Mar 8–14 but metric cards show Mar 1–7 with `$0.00` Ads Spend → causes "are ads broken?" false alarm.

- When a data source has a lag (Ads=1d, Perf=3d, SQP=10d), show `—` with tooltip: "data arrives in X days"
- NEVER show `$0.00` when the reason is data lag

### 2. Skeleton Loading States
**Files:** `src/App.tsx`, new `src/components/Skeleton.tsx`
**Source:** UX Audit #2

Replace the full-page spinner (`Loading dashboard data...`) with skeleton screens that mirror actual layout: header pills, KPI cards, table rows, chart area.

- Use `animate-pulse` shimmer with `#1e1e23` base / `#2a2a30` highlight
- Sidebar and header should render immediately (they don't depend on data)

### 3. Filter Bar — Two-Tier Architecture
**File:** `src/components/FilterBar.tsx`
**Source:** UX Audit #3

- **Tier 1 (always visible):** Product Family · Time Period (Weeks/Month/Year) · Date Range
- **Tier 2 ("+More Filters" toggle):** Experiment · Keyword · Seasonality · Trend count
- Show active filter count badge on "+More Filters" button
- Active filters appear as removable chips below the bar

---

## P1 — High Priority

### 4. ACTION Reason Tags
**File:** `src/pages/ActionsPage.tsx`
**Source:** PPC Audit Q1 · UX Audit #4

Every urgent action card must include a reason chip explaining WHY. Current cards show the signal (WASTED_SPEND / UNPROFITABLE) but not the diagnostic.

Reasons: `wrong ASIN` · `low CTR (0.3%)` · `high CPC ($1.70)` · `no conversions` · `below threshold`

### 5. Sidebar Legibility + Labels
**File:** `src/components/Sidebar.tsx`
**Source:** UX Audit #5 · Content Audit

Labels update:

| Current | New |
|---|---|
| `ACTION` | **ACTIONS** |
| `STRAT` | **STRATEGY** |
| `SQP` | **SEARCH QUERY** |
| `KWDS` | **KEYWORDS** |

Styling:
- Labels `text-[10px]` → `text-[11px]`
- Tracking `tracking-widest` → `tracking-wider`
- Inactive color `text-faint` → `text-muted` (`#a1a1aa`)
- Add group headers in `text-[8px]` uppercase:
  - **Overview:** HOME, ACTIONS, PEAK, ADS, STRATEGY
  - **Data:** SEARCH QUERY, LEARN, KEYWORDS, LOG
  - **System:** HEALTH, ADMIN

### 6. Empty States — Remove Developer Hints
**Files:** All page files that use `<Empty>`
**Source:** Content Audit · UX Audit #9

Replace every instance of `Ensure Cube is running (VITE_CUBE_API_URL)` with user-facing guidance:

| Page | Current Hint | New Copy |
|---|---|---|
| Actions | `Ensure Cube is running` | "Actions appear when keyword data detects bid changes, negations, or opportunities." |
| Peak | `Ensure Cube is running` | "Peak planning activates when a holiday or event is within 6 weeks." |
| Keywords | `Ensure Cube is running` | "Keyword data syncs from your Amazon Ads campaigns." |
| Strategies | `No experiment template data` | "Create experiments in the data-entry app to see strategies here." |
| Log | `No changes` | "No changes recorded yet. Changes appear when bids, budgets, or statuses are modified." |
| ADS drainers | `No matching terms` | "No draining keywords found — try lowering the spend threshold." |

### 7. Page Titles & Subtitles — Standardize
**Files:** Individual page files
**Source:** Content Audit

| Page | Current Title | Current Subtitle | New Title | New Subtitle |
|---|---|---|---|---|
| HOME | *(none)* | — | **Overview** | "Weekly snapshot across all product families" |
| ACTION | "Detailed Actions" | "Every action justified by measures" | **Actions** | "Prioritized bid and keyword recommendations" |
| PEAK | "Next Peak" | "Peak season readiness" | *(keep)* | *(keep)* |
| ADS | "Ads Performance" | "{period} · Campaign & search term analysis" | *(keep)* | *(keep)* |
| STRAT | "Experiment Strategies" | "Learn from experiments..." | *(keep)* | *(keep)* |
| LEARN | "Learnings" | "What we're testing..." | *(keep)* | *(keep)* |
| KWDS | "Keyword–Product Map" | "Advertised vs. Purchased" | *(keep)* | "Which keywords trigger which products — and whether the right hero ASIN is served" |
| LOG | "Change Log" | "Recent changes" | *(keep)* | "Bid, budget, and status changes across experiments" |
| HEALTH | "System Health" | "Data pipeline status & integrity checks" | *(keep)* | *(keep)* |

### 8. Page Transition Animation
**File:** `src/App.tsx`
**Source:** UX Audit #6

- Add `key={page}` to content wrapper to trigger re-mount
- Add `animate-in` class (keyframe already exists in `index.css`)
- Result: smooth 0.25s fade-in on page switch

---

## P2 — Medium Priority

### 9. SQP Gap Annotation
**File:** `src/pages/FamilyPage.tsx`
**Source:** PPC Audit Q7 · UX Audit #7

On "You vs Amazon Total" chart, auto-annotate when share is dropping:
> "Amazon total grew 20% but your orders flat → you're losing share"

### 10. PEAK Budget Suggestion
**File:** `src/pages/PeakPage.tsx`
**Source:** PPC Audit Q8 · UX Audit #8

Add "Suggested weekly spend" row per phase. Formula: LY spend × TY sales growth rate. Label as "Suggested" not "Recommended" — it's directional.

### 11. PageSummaryBar Intelligence
**Files:** Each page file's `usePageSummary()` call
**Source:** UX Audit #10 · Content Audit

Replace static labels with contextual 1-liner insights:
- HOME: "Ads ROAS up 12% WoW across 4 families"
- PEAK: "Easter peak starts in 7 days — 3 products need ad boost"
- STRAT: "Hunter strategy outperforming at 2.45x ROAS"

### 12. Header Freshness Cleanup
**File:** `src/components/Header.tsx`
**Source:** UX Audit #11

- Replace verbose `SQP: Feb 22 – Feb 28 | Ads: thru Mar 14 | Perf: thru Mar 12`
- Show: green pulsing dot + `Data thru Mar 14` (latest date across all sources)
- Full freshness breakdown in hover tooltip only

### 13. ADS Page Copy Polish
**File:** `src/pages/AdsPerformancePage.tsx`
**Source:** Content Audit

- "What's Working" → lead with verb: "Scale these — high ROAS keywords with conversion headroom"
- "Money Drains" → make `negate` / `reduce bid` visually distinct badges
- "Money Drainers — 0 Orders" → rename: **"Zero-Order Keywords"**
- Hierarchy builder → add hint: "Drag to reorder. Add levels to slice data differently."

### 14. LEARN Page Copy Polish
**File:** `src/pages/LearnPage.tsx`
**Source:** Content Audit

- Scale candidates bullet: truncate to top 5 with "show more" toggle
- `HYPOTHESIS` pill → change to sentence case: **"Hypothesis"**

### 15. LOG Negative Keywords Section
**File:** `src/pages/LogPage.tsx`
**Source:** Content Audit

Add section intro: "Terms blocked from triggering your ads"

### 16. Card Hover Lift
**File:** `src/components/Card.tsx`
**Source:** UX Audit #13

Add `card-lift` class to base Card (class already in CSS). Effect: `translateY(-1px)` + `shadow-float` on hover.

### 17. Table Sort Affordance
**File:** `src/components/Tooltip.tsx` (SortTh)
**Source:** UX Audit #12

All sortable headers: `cursor: pointer`, underline on hover, arrow icon for sort direction.

---

## P3 — Low Priority

### 18. SEO Meta Tags
**File:** `index.html`
**Source:** Content Audit

```html
<title>Happy Lolli OI — Amazon PPC Analytics</title>
<meta name="description" content="Ori Intelligence: Amazon advertising performance, profit analytics, and campaign optimization for Happy Lolli." />
```

### 19. ROAS Color Thresholds
**Source:** UX Audit #14

- `≥ 2.0x` → green
- `1.0x – 1.99x` → yellow
- `< 1.0x` → red

### 20. Breadcrumbs
**Source:** UX Audit #15

Make first breadcrumb segment clickable (link back to section overview).

### 21. Design Tokens
**File:** `src/index.css` (inside `@theme {}`)
**Source:** UX Audit #16

```css
--text-subtitle: 16px;
--space-xs: 4px;
--space-sm: 8px;
--space-md: 16px;
--space-lg: 24px;
--space-xl: 32px;
--space-2xl: 48px;
--transition-fast: 150ms ease;
--transition-base: 200ms ease;
--transition-slow: 300ms ease;
```

### 22. Hardcoded Dark Styles Cleanup
**Files:** Multiple

- ~50 instances of `border-zinc-800/30` on table rows → use `border-border`
- ~10 instances of `bg-zinc-900/30` on sub-rows → use `bg-inset`
- Tooltip `bg-zinc-900` → `bg-card`
- ScoreGauge `bg-zinc-900/60` → `bg-card`

---

## General Rules (Always Follow)

- Use **Lucide icons**, never emojis as UI icons
- All clickable elements must have `cursor: pointer`
- Transitions: 150–300ms, never > 500ms
- Test both **dark and light mode** for every change
- Respect `prefers-reduced-motion` (already handled in `index.css`)
- Ads-sourced measures → **"Ads"** prefix; SQP-sourced → **"SQP"** prefix
- No developer hints in user-facing UI — always write for the PPC manager
