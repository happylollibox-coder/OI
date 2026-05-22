import React, { useMemo } from 'react';

/* ─── Types ─── */
interface MonthlyHero {
  month: string;
  hero_asin: string;
  hero_product: string;
  orders: number;
  cvr_pct: number;
  spend: number;
}

interface HeroTimelineProps {
  monthlyHeroes: MonthlyHero[];
  currentHeroAsin: string | null;
  heroStabilityPct: number;
}

/* ─── Color palette for products ─── */
const PRODUCT_COLORS: Record<string, string> = {};
const COLOR_PALETTE = [
  '#6366f1', // indigo
  '#f59e0b', // amber
  '#10b981', // emerald
  '#ef4444', // red
  '#8b5cf6', // violet
  '#ec4899', // pink
  '#14b8a6', // teal
  '#f97316', // orange
  '#06b6d4', // cyan
  '#84cc16', // lime
];

function getProductColor(asin: string): string {
  if (!PRODUCT_COLORS[asin]) {
    const idx = Object.keys(PRODUCT_COLORS).length % COLOR_PALETTE.length;
    PRODUCT_COLORS[asin] = COLOR_PALETTE[idx];
  }
  return PRODUCT_COLORS[asin];
}

/* ─── Short month labels ─── */
function shortMonth(ym: string): string {
  const [, m] = ym.split('-');
  const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return months[parseInt(m, 10)] || m;
}

/* ─── Component ─── */
export default function HeroTimeline({ monthlyHeroes, currentHeroAsin, heroStabilityPct }: HeroTimelineProps) {
  // Deduplicate unique products for the legend
  const uniqueProducts = useMemo(() => {
    const seen = new Map<string, string>();
    for (const mh of monthlyHeroes) {
      if (!seen.has(mh.hero_asin)) seen.set(mh.hero_asin, mh.hero_product);
    }
    return Array.from(seen.entries());
  }, [monthlyHeroes]);

  if (!monthlyHeroes.length) return null;

  return (
    <div style={{ marginBottom: 16 }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
        <span style={{ fontWeight: 600, fontSize: 13, color: '#94a3b8' }}>Hero Timeline</span>
        <span style={{
          fontSize: 11,
          padding: '2px 8px',
          borderRadius: 10,
          background: heroStabilityPct >= 70 ? 'rgba(16,185,129,0.15)' :
                      heroStabilityPct >= 40 ? 'rgba(245,158,11,0.15)' : 'rgba(239,68,68,0.15)',
          color: heroStabilityPct >= 70 ? '#10b981' :
                 heroStabilityPct >= 40 ? '#f59e0b' : '#ef4444',
          fontWeight: 600,
        }}>
          {heroStabilityPct}% stable
        </span>
      </div>

      {/* Timeline strip */}
      <div style={{
        display: 'flex',
        gap: 2,
        borderRadius: 8,
        overflow: 'hidden',
        background: 'rgba(30,41,59,0.5)',
        padding: 2,
      }}>
        {monthlyHeroes.map((mh) => {
          const color = getProductColor(mh.hero_asin);
          const isCurrent = mh.hero_asin === currentHeroAsin;
          // First two chars of product name
          const initial = mh.hero_product
            .replace(/^(White|Pink|Purple|Blue|Mint|Fresh)\s+/i, '')
            .substring(0, 3);

          return (
            <div
              key={mh.month}
              title={`${mh.month}: ${mh.hero_product}\n${mh.orders} orders, ${mh.cvr_pct}% CVR, $${mh.spend} spend`}
              style={{
                flex: 1,
                minWidth: 0,
                textAlign: 'center',
                padding: '6px 2px 4px',
                background: `${color}${isCurrent ? '40' : '25'}`,
                borderBottom: `3px solid ${color}`,
                borderTop: isCurrent ? `2px solid ${color}` : '2px solid transparent',
                cursor: 'default',
                transition: 'all 0.15s',
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLElement).style.background = `${color}60`;
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLElement).style.background = `${color}${isCurrent ? '40' : '25'}`;
              }}
            >
              <div style={{
                fontSize: 10,
                color: '#94a3b8',
                marginBottom: 2,
                whiteSpace: 'nowrap',
                overflow: 'hidden',
              }}>
                {shortMonth(mh.month)}
              </div>
              <div style={{
                fontSize: 11,
                fontWeight: 700,
                color: color,
                whiteSpace: 'nowrap',
                overflow: 'hidden',
              }}>
                {initial}
              </div>
              <div style={{
                fontSize: 9,
                color: '#64748b',
                marginTop: 1,
              }}>
                {mh.orders > 0 ? `${mh.orders}` : '—'}
              </div>
            </div>
          );
        })}
      </div>

      {/* Legend */}
      <div style={{
        display: 'flex',
        flexWrap: 'wrap',
        gap: '6px 16px',
        marginTop: 6,
        fontSize: 11,
        color: '#94a3b8',
      }}>
        {uniqueProducts.map(([asin, name]) => (
          <span key={asin} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{
              width: 8, height: 8, borderRadius: 2,
              background: getProductColor(asin),
              display: 'inline-block',
            }} />
            {name}
            {asin === currentHeroAsin && <span style={{ color: '#f59e0b', fontWeight: 600 }}> ⭐</span>}
          </span>
        ))}
      </div>
    </div>
  );
}
