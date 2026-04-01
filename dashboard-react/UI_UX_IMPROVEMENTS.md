# OI Dashboard — UI/UX Visual Improvements Plan

> **Date:** 2026-03-15 (last updated)  
> **Source:** UI design audit + `/ui-ux-audit.md` workflow rules  

---

## ✅ Already Completed

| Change | File | Detail |
|--------|------|--------|
| Fira Sans as primary UI font | `src/index.css` | Fira Code stays for data/numbers |
| Light mode contrast bump | `src/index.css` | `--color-muted` 6e→63, `--color-faint` ae→8e |
| Card borders visible in light mode | `src/index.css` | `--color-border` opacity 0.06 → 0.14 |
| Sidebar light mode override | `src/index.css` | `rgba(245,245,250,0.85)` |
| `.section-divider` + `.card-lift` utilities | `src/index.css` | Ready to use |
| Animation tuning | `src/index.css` | `fadeIn` → 0.15s, translateY 4px |
| Header KPI pills improved | `src/components/Header.tsx` | Colored accent dots, 12-13px fonts |
| **Sidebar group headers** | `src/components/Sidebar.tsx` | 11px labels, `tracking-wider`, `text-muted`, Overview/Data/System groups, width 68→80px |
| **Filter bar two-tier** | `src/components/FilterBar.tsx` | Tier 1 core filters, Tier 2 "+More", violet badge, removable chips |
| **Skeleton loading** | `src/components/Skeleton.tsx` + `App.tsx` | Header+Sidebar render immediately, skeleton in main area |
| **Page transitions** | `src/App.tsx` | `key={page}` + `animate-in` on content wrapper |
| Filter bar dark blobs fixed | `src/components/FilterBar.tsx` | `bg-zinc-900/50` → `bg-inset` |
| PEAK dropdown fixed | `src/pages/PeakPage.tsx` | `bg-zinc-900` → `bg-inset` |
| PEAK empty state | `src/pages/PeakPage.tsx` | Contextual "within 6 weeks" hint |
| Content area breathing room | `src/App.tsx` | px-8, py-5, p-6, mt-3, left-[80px] |

---

## 🔧 Remaining — Visual/CSS Items

### 1. Header Freshness Cleanup (UX Audit Rule #11)
**File:** `src/components/Header.tsx`

- [ ] Replace verbose `SQP: Feb 22 – Feb 28 | Ads: thru Mar 14 | Perf: thru Mar 12`
- [ ] Show: green pulsing dot + `Data thru Mar 14` (latest date across all sources)
- [ ] Show full freshness breakdown in hover tooltip only

### 2. Card Hover Lift (UX Audit Rule #13)
**File:** `src/components/Card.tsx`

- [ ] Add `card-lift` class to the base `Card` component
- [ ] Effect: `translateY(-1px)` + `shadow-float` on hover

### 3. Design Tokens (UX Audit Rule #16)
**File:** `src/index.css` (inside `@theme {}`)

- [ ] Add spacing + transition tokens:
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

### 4. Remaining Hardcoded Dark Styles (Global)
**Files:** Multiple page files

- [ ] ~50 `border-zinc-800/30` on table rows → `border-border`
- [ ] ~10 `bg-zinc-900/30` on sub-rows → `bg-inset`
- [ ] `Tooltip.tsx` `bg-zinc-900` → `bg-card`
- [ ] `ScoreGauge.tsx` `bg-zinc-900/60` → `bg-card`
- [ ] `ChangesSummaryCell.tsx` tooltip → `bg-card`

---

## ⏩ Deferred — Needs Data Logic / Design Discussion

| # | Rule | Why Deferred |
|---|------|-------------|
| 1 | HOME Period Sync — show "—" for lagged data | Data-logic change |
| 4 | ACTION Reason Tags — "why" chips | Domain logic |
| 7 | SQP Gap Annotation — share drop annotations | Feature work |
| 8 | PEAK Budget Suggestion — suggested weekly spend | Feature work |
| 9 | Empty States — contextual guidance (partially done) | Content writing needed |
| 10 | PageSummaryBar Intelligence — contextual 1-liners | Data-logic feature |
| 12 | Table Sort Affordance — underline + arrow | Component refactor |
| 14 | ROAS Color Thresholds — green/yellow/red | Feature work |
| 15 | Breadcrumbs — clickable first segment | Feature work |

---

## 🚫 Don't Touch (A+ Features)
- KWDS Hero matching
- LEARN auto-insights
- STRAT portfolio view
- ADS + SQP cross-reference
- HOME family profitability table

---

## Conventions (Always Follow)
- **Sidebar width:** 80px → use `left-[80px]` on main content
- **Theme-aware:** Never use `bg-zinc-900`, `bg-zinc-800` for interactive elements → use `bg-inset`, `bg-card`, `border-border`
- **Lucide icons** only, never emojis as UI icons
- **`cursor: pointer`** on all clickable elements
- **Transitions:** 150-300ms, never > 500ms
- **Test both** dark and light mode for every change
- **Ads** prefix for ads measures, **SQP** prefix for SQP measures
