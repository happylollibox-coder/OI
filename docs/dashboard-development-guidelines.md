# Dashboard Development Guidelines (OI)

Comprehensive UI/UX, development, and testing guidelines for the OI dashboard (`dashboard-react/`).

---

## 1. UI/UX Guidelines

### Theme & Colors

| Token | Value | Usage |
|-------|-------|-------|
| `--color-surface` | `#111114` | Main background |
| `--color-card` | `#16161a` | Cards, panels |
| `--color-border` | `rgba(63,63,70,.45)` | Default borders |
| `--color-muted` | `#a1a1aa` | Secondary text |
| `--color-subtle` | `#71717a` | Labels, hints |
| `--color-faint` | `#52525b` | Tertiary text |

**Tailwind:** `bg-surface`, `bg-card`, `border-border`, `text-subtle`, `text-faint`, `text-muted`

### Semantic Colors (State)

| State | Color | Usage |
|-------|-------|-------|
| Positive / good | `emerald-400`, `#34d399` | Profitable, up, success |
| Negative / bad | `red-400`, `#f87171` | Loss, down, urgent |
| Warning / caution | `amber-400` | N/A, peak, fix |
| Neutral / info | `blue-400` | Info, experiments |
| Muted / inactive | `zinc-500` | No data, disabled |

### Typography

- Base font size: 13px. Font: Inter (body), JetBrains Mono (numbers).
- Headings: `text-[22px]`–`text-3xl`, `font-bold` / `font-extrabold`
- Values: `font-mono text-2xl`–`text-3xl font-bold`
- Labels: `text-[10px]`–`text-[11px] font-semibold uppercase tracking-widest`
- Notes: `text-[11px] text-subtle`
- Meta: `text-[10px] text-faint font-mono`

### Cards & Containers

- Radius: `rounded-xl` or `rounded-2xl`
- Padding: `p-4`–`p-5`
- Border: `border border-border`
- Hover: `hover:border-border-strong`, `hover:shadow-[...]`
- Accent: `border-l-4` with semantic color (`border-l-emerald-500`, `border-l-red-500`)

### Tables & Rows

- Row hover: `hover:bg-white/[.02]`
- Row borders: `border-b border-zinc-800/30`
- Clickable rows: `cursor-pointer transition-colors`
- Selected row: `bg-blue-500/10 border-l-2 border-l-blue-500`

### Charts (Recharts)

- Grid: `strokeDasharray: '3 3'`, `stroke: 'rgba(63,63,70,.3)'`
- Axis ticks: `fill: '#71717a'`, `fontSize: 8–10`
- Tooltip: `background: '#16161a'`, `borderRadius: 8`, `fontSize: 10`
- Use `CHART_GRID`, `CHART_AXIS_TICK_*`, `CHART_TOOLTIP_STYLE` from `chartTheme.ts`

### Interactions

- Transitions: `transition-all`, `transition-colors`, `duration-200`
- Buttons: `rounded-lg`, `border`, `hover:border-*`, `cursor-pointer`
- Empty state: `<Empty icon="…" message="…" hint="…" />`

---

## 2. Development Best Practices

### Before Writing Code

- **Read existing patterns**: Check similar pages/components before adding new ones.
- **Check types**: Ensure `DashboardData` and related types in `types.ts` support the data you need.
- **Plan data flow**: Data comes from `useData()` → passed down. No ad-hoc fetches for the same data.

### While Writing Code

- **Use shared components**: Prefer `Card`, `KpiCard`, `Badge`, `Section`, `Empty`, `Tip`, `SortTh`, `DataTable` over custom equivalents.
- **Use design tokens**: `bg-card`, `text-subtle`, `border-border` — not raw hex values for surfaces/borders.
- **Use hooks**: `useFilters()`, `useSort`, `useData()` — don't duplicate filter/sort logic.
- **Extract reusable logic**: If logic is used in 2+ places, move to a hook or util.
- **Keep components focused**: One responsibility per component. Split large pages into subcomponents.

### Code Quality

- **TypeScript**: No `any`. Extend types in `types.ts` when adding new data fields.
- **Null safety**: Handle `null`/`undefined` — use optional chaining, nullish coalescing, early returns.
- **Avoid unused variables**: Remove or use. Run linter before committing.
- **Consistent naming**: `camelCase` for variables/functions, `PascalCase` for components, `UPPER_SNAKE` for constants.

### File Organization

- **New page**: `src/pages/<Name>Page.tsx`
- **New component**: `src/components/<Name>.tsx`
- **New hook**: `src/hooks/use<Name>.ts`
- **New util**: `src/utils.ts` or a dedicated file if large
- **Constants**: `src/constants.ts` or `src/types.ts` for shared enums/meta

### Imports

- Use path aliases if configured (`@/` or `../`).
- Group: React → external libs → internal components → hooks/utils → types.
- Prefer named exports for components.

### Performance

- **useMemo**: For derived data from props/state (e.g. filtered lists, aggregated values).
- **useCallback**: For callbacks passed to memoized children or used in deps.
- **Avoid unnecessary re-renders**: Don't create objects/arrays inline in JSX if they're passed as props.

---

## 3. Testing Best Practices

### Before Submitting Changes

1. **Lint**: Run `npm run lint` (or equivalent). Fix all errors.
2. **TypeScript**: Run `tsc -b` or `npm run build`. Zero type errors.
3. **Build**: Run `npm run build`. Build must succeed.

### Manual Verification

- **Empty states**: Test with no data (empty JSON, filters that return nothing). Ensure `<Empty>` or graceful fallback.
- **Edge cases**: Zero values, negative numbers, very long strings, missing optional fields.
- **Filters**: Change family, period, specific period. Verify data updates correctly.
- **Navigation**: Click through all affected pages. No broken links or missing props.

### Regression Checks

- **Existing pages**: Ensure changes don't break unrelated pages (e.g. HomePage, FamilyPage, ActionsPage).
- **Shared components**: If you changed `Card`, `Badge`, `Section`, etc., spot-check all usages.

### Data Integrity

- **JSON shape**: If you added/modified data files, ensure they match `DashboardData` and consumers.
- **Formatting**: Use `fM`, `fP`, `fR`, `fOrd`, `fClk` from `utils.ts` for consistent number formatting.

### What to Report

- **Pre-existing issues**: If tests/lint fail before your changes, note that. Don't claim them as introduced by you.
- **New failures**: If your changes cause failures, fix them before considering the task done.

---

## 4. Checklist Before PR / Merge

- [ ] `npm run build` passes
- [ ] Linter passes (no errors)
- [ ] Types extended in `types.ts` if new data/fields
- [ ] Page registered in `App.tsx` and `Sidebar.tsx` if new page
- [ ] Empty/loading states handled
- [ ] Design tokens used (no ad-hoc colors for surfaces/borders)
- [ ] No unused imports or variables
- [ ] Manual smoke test on affected pages
