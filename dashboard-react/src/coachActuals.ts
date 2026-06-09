// ─── Ads-Coacher in-component logic, extracted pure + TDD'd ──────────────────
// Mirrors the planTypes.ts standard. These were inline memos in ActionsPage.tsx;
// extracted so Phase 2B can extend the ROAS window (7d ad-only / 4w / peak) and
// inject live thresholds without touching the component.

export interface FamilyActual { dailyCost: number; cpc: number; roas: number }

// Minimal structural shapes (avoid importing the heavy DashboardData types here).
export interface DailyTrendLike { date: string; product_type: string; ad_cost?: number; clicks?: number }
export interface ActLike { product_short_name?: string | null; spend?: number; net_roas?: number }
export interface ModeRowLike { product_short_name?: string | null; coach_mode?: string | null }

// Per-family last-week actuals vs the (daily) plan guidelines:
//   • dailyCost + cpc = last 7 distinct trend dates from daily_trends (ad-only), non-overlapping.
//   • roas = last 4w ad-only, spend-weighted over the family's coach term rows (acts) — the only
//     ad-only ROAS currently available (a daily_trends ROAS would be blended/halo).
// Keyed by getFamily(product_short_name) so it matches the family panel's bucket keys exactly.
export function familyActuals(
  acts: ActLike[],
  dailyTrends: DailyTrendLike[],
  getFamily: (name?: string | null) => string | null,
): Map<string, FamilyActual> {
  const dates = [...new Set(dailyTrends.map(r => r.date))].sort();
  // TODO(phase-2b): nDays is a single global window shared across families; a family with sparse
  // coverage in the window gets divided by 7 not its own active-day count. Faithful to the original
  // memo — revisit when adding the multi-window (7d/4w/peak) ROAS.
  const recentDates = new Set(dates.slice(-7)); // last week
  const nDays = recentDates.size || 1;

  const sp = new Map<string, { cost: number; clicks: number }>();
  for (const r of dailyTrends) {
    if (!recentDates.has(r.date)) continue;
    const e = sp.get(r.product_type) ?? { cost: 0, clicks: 0 };
    e.cost += r.ad_cost || 0;
    e.clicks += r.clicks || 0;
    sp.set(r.product_type, e);
  }

  const ro = new Map<string, { spend: number; roasW: number }>();
  for (const a of acts) {
    const fam = getFamily(a.product_short_name);
    if (!fam) continue;
    const s = a.spend || 0;
    const e = ro.get(fam) ?? { spend: 0, roasW: 0 };
    e.spend += s;
    e.roasW += (a.net_roas || 0) * s;
    ro.set(fam, e);
  }

  const out = new Map<string, FamilyActual>();
  for (const fam of new Set([...sp.keys(), ...ro.keys()])) {
    const s = sp.get(fam);
    const r = ro.get(fam);
    out.set(fam, {
      dailyCost: s ? s.cost / nDays : 0,
      cpc: s && s.clicks > 0 ? s.cost / s.clicks : 0,
      roas: r && r.spend > 0 ? r.roasW / r.spend : 0,
    });
  }
  return out;
}

// Most frequent coach_mode across rows; first-seen wins on a tie; GUARDIAN when there are none.
export function dominantMode(rows: { coach_mode?: string | null }[]): string {
  const counts: Record<string, number> = {};
  for (const r of rows) if (r.coach_mode) counts[r.coach_mode] = (counts[r.coach_mode] || 0) + 1;
  return Object.entries(counts).sort((a, b) => b[1] - a[1])[0]?.[0] || 'GUARDIAN';
}

// Per-family dominant coach mode, keyed by getFamily(product_short_name) so it lines up with the
// family panel's bucket keys. Replaces the previous global-mode-for-every-family behaviour.
export function familyModes(
  rows: ModeRowLike[],
  getFamily: (name?: string | null) => string | null,
): Map<string, string> {
  const byFam = new Map<string, { coach_mode?: string | null }[]>();
  for (const r of rows) {
    const fam = getFamily(r.product_short_name);
    if (!fam || !r.coach_mode) continue;
    const arr = byFam.get(fam);
    if (arr) arr.push(r); else byFam.set(fam, [r]);
  }
  const out = new Map<string, string>();
  for (const [family, frows] of byFam) out.set(family, dominantMode(frows));
  return out;
}
