import React, { useMemo, useState } from 'react';
import HeroTimeline from './HeroTimeline';
import type { ActionRow, CoachDecisionRow } from '../../types';
import type { DoQueueItem } from '../../hooks/useDoQueue';

/* ─── Types ─── */
interface ProductBreakdown {
  asin: string;
  product_name: string;
  spend: number;
  orders: number;
  clicks: number;
  cvr_pct: number;
  net_profit: number;
  is_hero: boolean;
  campaign_count: number;
}

interface MonthlyHero {
  month: string;
  hero_asin: string;
  hero_product: string;
  orders: number;
  cvr_pct: number;
  spend: number;
}

export interface KeywordIntelligenceData {
  searchTerm: string;
  totalSpend: number;
  totalOrders: number;
  totalClicks: number;
  productCount: number;
  campaignCount: number;
  heroAsin: string | null;
  heroProductName: string | null;
  heroNetRoas: number;
  heroCvrPct: number;
  heroStabilityPct: number;
  heroDataMonths: number;
  monthsWithData: number;
  heroSpend: number;
  heroSpendPct: number;
  complexityScore: number;
  isMultiCampaign: boolean;
  isHeroUnstable: boolean;
  isHeroUnproven: boolean;
  isFragmented: boolean;
  productBreakdown: ProductBreakdown[];
  monthlyHeroes: MonthlyHero[];
  productBreakdown12m: ProductBreakdown[];
  productBreakdownByMonth: { month: string; products: ProductBreakdown[] }[];
}

interface KeywordIntelligencePanelProps {
  data: KeywordIntelligenceData;
  loading?: boolean;
  /** All coach actions for this search term (across campaigns) */
  termActions: ActionRow[];
  /** Coach decision row for this search term */
  coachDecision: CoachDecisionRow | null;
  /** Add an item to the Do queue */
  onAddToDoQueue: (item: Omit<DoQueueItem, 'id' | 'addedAt'>) => void;
  /** Check if an item is already in the Do queue */
  isInDoQueue: (search_term: string, action: string, campaign: string) => boolean;
}

type TabId = 'data' | 'findings' | 'strategy' | 'actions';

/* ─── Helpers ─── */
const fmt$ = (v: number) => v >= 1000 ? `$${(v / 1000).toFixed(1)}K` : `$${v.toFixed(0)}`;
const fmtPct = (v: number) => `${v.toFixed(0)}%`;

/* ─── Campaign template detection ─── */
const TEMPLATE_PATTERNS: { pattern: RegExp; template: string; emoji: string; color: string }[] = [
  { pattern: /boost|exact.*boost/i, template: 'Boost', emoji: '🚀', color: '#a855f7' },
  { pattern: /hunter/i, template: 'Hunter', emoji: '🎯', color: '#3b82f6' },
  { pattern: /discovery|auto/i, template: 'Discovery', emoji: '🔍', color: '#22c55e' },
  { pattern: /video|sbv/i, template: 'Video', emoji: '🎬', color: '#ec4899' },
  { pattern: /store|sb[\\s/]/i, template: 'Store/SB', emoji: '🏪', color: '#f59e0b' },
  { pattern: /guardian|defend/i, template: 'Guardian', emoji: '🛡️', color: '#6366f1' },
];

function detectTemplate(campaignName: string): { template: string; emoji: string; color: string } {
  for (const tp of TEMPLATE_PATTERNS) {
    if (tp.pattern.test(campaignName)) return tp;
  }
  return { template: 'Other', emoji: '📦', color: '#64748b' };
}

/* ─── Actionable actions (show ⊕ button) ─── */
const NON_ACTIONABLE = new Set(['MONITOR', 'MONITOR_TARGET', 'KEEP', 'KEEP_TARGET', 'BUDGET_OK', 'MAINTAIN']);

/* ─── Styling constants ─── */
const TAB_STYLES = {
  container: {
    display: 'flex' as const,
    gap: 2,
    marginBottom: 14,
    borderBottom: '1px solid rgba(148,163,184,0.1)',
    paddingBottom: 0,
  },
  tab: (active: boolean) => ({
    padding: '6px 14px',
    fontSize: 12,
    fontWeight: active ? 700 : 500,
    color: active ? '#e2e8f0' : '#64748b',
    background: active ? 'rgba(99,102,241,0.12)' : 'transparent',
    border: 'none',
    borderBottom: active ? '2px solid #6366f1' : '2px solid transparent',
    borderRadius: '6px 6px 0 0',
    cursor: 'pointer' as const,
    transition: 'all 0.15s',
    display: 'flex' as const,
    alignItems: 'center' as const,
    gap: 5,
  }),
  badge: (color: string) => ({
    fontSize: 10,
    fontWeight: 700,
    padding: '1px 5px',
    borderRadius: 8,
    background: `${color}22`,
    color: color,
  }),
};

const CARD_STYLE = {
  padding: '10px 14px',
  borderRadius: 8,
  background: 'rgba(30,41,59,0.4)',
  border: '1px solid rgba(148,163,184,0.08)',
  marginBottom: 8,
  fontSize: 12,
};

/* ─── Badges ─── */
function AlertBadge({ label, color }: { label: string; color: string }) {
  return (
    <span style={{
      display: 'inline-flex',
      alignItems: 'center',
      gap: 4,
      padding: '2px 8px',
      borderRadius: 10,
      fontSize: 11,
      fontWeight: 600,
      background: `${color}18`,
      color: color,
      border: `1px solid ${color}30`,
    }}>
      {label}
    </span>
  );
}

/* ─── Spend Allocation Bar ─── */
function SpendBar({ products, totalSpend }: { products: ProductBreakdown[]; totalSpend: number }) {
  const sorted = useMemo(() => [...products].sort((a, b) => b.spend - a.spend), [products]);
  const PRODUCT_COLORS = ['#6366f1', '#f59e0b', '#10b981', '#ef4444', '#8b5cf6', '#ec4899', '#14b8a6', '#f97316'];

  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
        <span style={{ fontWeight: 600, fontSize: 13, color: '#94a3b8' }}>Spend Allocation</span>
      </div>

      {/* Bar */}
      <div style={{
        display: 'flex',
        height: 20,
        borderRadius: 6,
        overflow: 'hidden',
        background: 'rgba(30,41,59,0.5)',
      }}>
        {sorted.map((p, i) => {
          const pct = totalSpend > 0 ? (p.spend / totalSpend) * 100 : 0;
          if (pct < 1) return null;
          return (
            <div
              key={p.asin}
              title={`${p.product_name}: ${fmt$(p.spend)} (${pct.toFixed(0)}%)`}
              style={{
                width: `${pct}%`,
                background: `${PRODUCT_COLORS[i % PRODUCT_COLORS.length]}${p.is_hero ? 'cc' : '66'}`,
                borderRight: '1px solid rgba(15,23,42,0.5)',
                transition: 'all 0.2s',
                cursor: 'default',
              }}
            />
          );
        })}
      </div>

      {/* Labels */}
      <div style={{
        display: 'flex',
        flexWrap: 'wrap',
        gap: '4px 12px',
        marginTop: 4,
        fontSize: 11,
        color: '#94a3b8',
      }}>
        {sorted.filter(p => p.spend > 0).slice(0, 6).map((p, i) => (
          <span key={p.asin} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{
              width: 6, height: 6, borderRadius: 2,
              background: PRODUCT_COLORS[i % PRODUCT_COLORS.length],
              display: 'inline-block',
            }} />
            {p.product_name}
            <span style={{ color: '#64748b' }}>{fmt$(p.spend)}</span>
            {p.is_hero && <span style={{ color: '#f59e0b' }}>⭐</span>}
          </span>
        ))}
      </div>
    </div>
  );
}

/* ─── Product Performance Table ─── */
function ProductTable({ products }: { products: ProductBreakdown[] }) {
  const sorted = useMemo(() => [...products].sort((a, b) => b.spend - a.spend), [products]);

  return (
    <div style={{ marginBottom: 12, overflowX: 'auto' }}>
      <div style={{ fontWeight: 600, fontSize: 13, color: '#94a3b8', marginBottom: 6 }}>Product Performance</div>
      <table style={{
        width: '100%',
        borderCollapse: 'collapse',
        fontSize: 12,
      }}>
        <thead>
          <tr style={{ borderBottom: '1px solid rgba(148,163,184,0.15)' }}>
            <th style={{ textAlign: 'left', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Product</th>
            <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Spend</th>
            <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Ord</th>
            <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>CVR</th>
            <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Net P&L</th>
            <th style={{ textAlign: 'center', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Hero</th>
          </tr>
        </thead>
        <tbody>
          {sorted.filter(p => p.spend > 0).map(p => (
            <tr
              key={p.asin}
              style={{
                borderBottom: '1px solid rgba(148,163,184,0.08)',
                background: p.is_hero ? 'rgba(245,158,11,0.06)' : 'transparent',
              }}
            >
              <td style={{ padding: '5px 8px', color: '#e2e8f0', fontWeight: p.is_hero ? 600 : 400 }}>
                {p.product_name}
                {p.campaign_count > 1 && (
                  <span style={{ color: '#64748b', fontSize: 10, marginLeft: 4 }}>
                    ({p.campaign_count} campaigns)
                  </span>
                )}
              </td>
              <td style={{ textAlign: 'right', padding: '5px 8px', color: '#e2e8f0' }}>{fmt$(p.spend)}</td>
              <td style={{ textAlign: 'right', padding: '5px 8px', color: p.orders > 0 ? '#e2e8f0' : '#ef4444' }}>{p.orders}</td>
              <td style={{ textAlign: 'right', padding: '5px 8px', color: p.cvr_pct > 5 ? '#10b981' : p.cvr_pct > 0 ? '#e2e8f0' : '#ef4444' }}>
                {p.cvr_pct > 0 ? `${p.cvr_pct}%` : '—'}
              </td>
              <td style={{
                textAlign: 'right', padding: '5px 8px',
                color: p.net_profit > 0 ? '#10b981' : '#ef4444',
                fontWeight: 600,
              }}>
                {p.net_profit > 0 ? '+' : ''}{fmt$(p.net_profit)}
              </td>
              <td style={{ textAlign: 'center', padding: '5px 8px' }}>
                {p.is_hero ? '⭐' : p.orders === 0 ? '💀' : ''}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}


/* ═══════════════════════════════════════════════════════════════
   TAB 1: DATA — existing timeline + spend bar + product table
   ═══════════════════════════════════════════════════════════════ */
function DataTab({ data }: { data: KeywordIntelligenceData }) {
  const [timeframe, setTimeframe] = useState<string>('4w');

  const activeBreakdown = useMemo(() => {
    if (timeframe === '4w') return data.productBreakdown || [];
    if (timeframe === '12m') return data.productBreakdown12m || [];
    const monthData = (data.productBreakdownByMonth || []).find(m => m.month === timeframe);
    return monthData ? monthData.products : [];
  }, [timeframe, data]);

  const totalActiveSpend = useMemo(() => activeBreakdown.reduce((sum, p) => sum + p.spend, 0), [activeBreakdown]);
  const totalActiveOrders = useMemo(() => activeBreakdown.reduce((sum, p) => sum + p.orders, 0), [activeBreakdown]);

  return (
    <>
      {/* Timeframe + stats */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
        <select
          value={timeframe}
          onChange={e => setTimeframe(e.target.value)}
          style={{
            background: 'rgba(30, 41, 59, 0.8)',
            color: '#e2e8f0',
            border: '1px solid rgba(148,163,184,0.2)',
            borderRadius: 4,
            padding: '3px 8px',
            fontSize: 12,
            cursor: 'pointer',
            outline: 'none',
          }}
        >
          <option value="4w">Last 4 Weeks</option>
          <option value="12m">Last 12 Months</option>
          {(data.productBreakdownByMonth || []).map(m => (
            <option key={m.month} value={m.month}>{m.month}</option>
          ))}
        </select>
        <div style={{ display: 'flex', gap: 12, fontSize: 11, color: '#94a3b8' }}>
          <span>{fmt$(totalActiveSpend)} spend</span>
          <span>{totalActiveOrders} orders</span>
        </div>
      </div>

      {/* Hero Timeline */}
      {data.monthlyHeroes.length > 0 && (
        <HeroTimeline
          monthlyHeroes={data.monthlyHeroes}
          currentHeroAsin={data.heroAsin}
          heroStabilityPct={data.heroStabilityPct}
        />
      )}

      {/* Spend Allocation */}
      {activeBreakdown.length > 1 && (
        <SpendBar products={activeBreakdown} totalSpend={totalActiveSpend} />
      )}

      {/* Product Table */}
      {activeBreakdown.length > 0 && (
        <ProductTable products={activeBreakdown} />
      )}
    </>
  );
}


/* ═══════════════════════════════════════════════════════════════
   TAB 2: FINDINGS — auto-generated insights
   ═══════════════════════════════════════════════════════════════ */
interface Finding {
  icon: string;
  title: string;
  description: string;
  severity: 'info' | 'warning' | 'success' | 'danger';
}

function FindingsTab({ data, termActions }: { data: KeywordIntelligenceData; termActions: ActionRow[] }) {
  const findings = useMemo((): Finding[] => {
    const out: Finding[] = [];

    // 1. Hero dominance analysis
    if (data.monthlyHeroes.length > 0) {
      const heroCounts: Record<string, number> = {};
      for (const mh of data.monthlyHeroes) {
        heroCounts[mh.hero_product] = (heroCounts[mh.hero_product] || 0) + 1;
      }
      const sorted = Object.entries(heroCounts).sort((a, b) => b[1] - a[1]);
      const topHero = sorted[0];
      if (topHero && topHero[1] >= data.monthlyHeroes.length * 0.6) {
        out.push({
          icon: '👑',
          title: 'Dominant Hero',
          description: `${topHero[0]} is the hero in ${topHero[1]} of ${data.monthlyHeroes.length} months — consistent performer.`,
          severity: 'success',
        });
      } else if (sorted.length > 1) {
        out.push({
          icon: '🔄',
          title: 'Hero Rotation',
          description: `Hero changes between ${sorted.map(s => `${s[0]} (${s[1]}mo)`).join(', ')} — no clear dominant product.`,
          severity: 'warning',
        });
      }
    }

    // 2. Seasonality detection
    if (data.productBreakdownByMonth && data.productBreakdownByMonth.length >= 6) {
      const monthlyOrders = data.productBreakdownByMonth.map(m => ({
        month: m.month,
        totalOrders: m.products.reduce((s, p) => s + p.orders, 0),
        totalSpend: m.products.reduce((s, p) => s + p.spend, 0),
      }));
      const avgOrders = monthlyOrders.reduce((s, m) => s + m.totalOrders, 0) / monthlyOrders.length;
      const peakMonths = monthlyOrders.filter(m => m.totalOrders > avgOrders * 1.5);
      const slowMonths = monthlyOrders.filter(m => m.totalOrders < avgOrders * 0.5 && m.totalOrders > 0);

      if (peakMonths.length > 0) {
        out.push({
          icon: '📈',
          title: 'Peak Months Detected',
          description: `${peakMonths.map(m => m.month).join(', ')} show ${(peakMonths[0].totalOrders / (avgOrders || 1)).toFixed(1)}x higher orders than average — seasonal opportunity.`,
          severity: 'info',
        });
      }
      if (slowMonths.length > 0) {
        out.push({
          icon: '📉',
          title: 'Off-Season Weakness',
          description: `${slowMonths.map(m => m.month).join(', ')} show significantly lower conversion — consider reducing bids or pausing during off-season.`,
          severity: 'warning',
        });
      }
    }

    // 3. Hero instability
    if (data.isHeroUnstable) {
      out.push({
        icon: '⚠️',
        title: 'Unstable Hero',
        description: `Hero changes frequently (${fmtPct(data.heroStabilityPct)} stable) — avoid aggressive consolidation. Multiple products compete for top slot.`,
        severity: 'danger',
      });
    }

    // 4. Spend fragmentation
    if (data.isFragmented) {
      out.push({
        icon: '💸',
        title: 'Spend Fragmented',
        description: `Only ${fmtPct(data.heroSpendPct)} of spend goes to hero product — budget is spread across ${data.productCount} products. Consider consolidating.`,
        severity: 'warning',
      });
    }

    // 5. Hero unproven
    if (data.isHeroUnproven) {
      out.push({
        icon: '⏳',
        title: 'Hero Needs More Data',
        description: `${data.heroProductName} has only ${data.heroDataMonths} months of data — needs 4+ months to confirm as reliable hero.`,
        severity: 'warning',
      });
    }

    // 6. Campaign template gaps
    const campNames = termActions.map(a => a.campaign_name?.toUpperCase() || '');
    const templates = new Set(campNames.map(cn => detectTemplate(cn).template));
    if (!templates.has('Boost')) {
      out.push({
        icon: '🚀',
        title: 'No Boost Campaign',
        description: 'No Exact/Boost campaign targets this keyword — if it\'s a proven winner, consider promoting to exact match.',
        severity: 'info',
      });
    }
    if (!templates.has('Video')) {
      out.push({
        icon: '🎬',
        title: 'No Video Coverage',
        description: 'No video (SBV) campaign targets this keyword — video ads can improve visibility and CTR.',
        severity: 'info',
      });
    }

    // 7. Zero-order products
    const zeroOrderProducts = (data.productBreakdown || []).filter(p => p.orders === 0 && p.spend > 5);
    if (zeroOrderProducts.length > 0) {
      out.push({
        icon: '💀',
        title: 'Non-Converting Products',
        description: `${zeroOrderProducts.map(p => p.product_name).join(', ')} have spend but zero orders — wasting ${fmt$(zeroOrderProducts.reduce((s, p) => s + p.spend, 0))}.`,
        severity: 'danger',
      });
    }

    return out;
  }, [data, termActions]);

  const severityColors = {
    info: '#3b82f6',
    warning: '#f59e0b',
    success: '#22c55e',
    danger: '#ef4444',
  };

  if (findings.length === 0) {
    return <div style={{ color: '#64748b', fontSize: 12, padding: 8 }}>No significant findings for this keyword.</div>;
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      {findings.map((f, i) => (
        <div key={i} style={{
          ...CARD_STYLE,
          borderLeft: `3px solid ${severityColors[f.severity]}`,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 3 }}>
            <span style={{ fontSize: 14 }}>{f.icon}</span>
            <span style={{ fontWeight: 700, color: severityColors[f.severity], fontSize: 12 }}>{f.title}</span>
          </div>
          <div style={{ color: '#94a3b8', fontSize: 11, lineHeight: 1.5 }}>
            {f.description}
          </div>
        </div>
      ))}
    </div>
  );
}


/* ═══════════════════════════════════════════════════════════════
   TAB 3: STRATEGY & DECISIONS
   ═══════════════════════════════════════════════════════════════ */
function StrategyTab({ data, termActions, coachDecision }: {
  data: KeywordIntelligenceData; termActions: ActionRow[]; coachDecision: CoachDecisionRow | null;
}) {
  // Group actions by campaign template
  const campaignOwnership = useMemo(() => {
    const groups: Record<string, { template: string; emoji: string; color: string; campaigns: { name: string; action: string; spend: number; orders: number; roas: number | null }[] }> = {};
    for (const a of termActions) {
      const tp = detectTemplate(a.campaign_name || '');
      if (!groups[tp.template]) {
        groups[tp.template] = { ...tp, campaigns: [] };
      }
      // Deduplicate by campaign_name
      if (!groups[tp.template].campaigns.some(c => c.name === a.campaign_name)) {
        groups[tp.template].campaigns.push({
          name: a.campaign_name || 'Unknown',
          action: a.action || '',
          spend: a.ads_spend_4w || 0,
          orders: a.ads_orders_4w || 0,
          roas: a.ads_net_roas_4w,
        });
      }
    }
    return Object.values(groups).sort((a, b) =>
      b.campaigns.reduce((s, c) => s + c.spend, 0) - a.campaigns.reduce((s, c) => s + c.spend, 0)
    );
  }, [termActions]);

  const coachMode = termActions[0]?.coach_mode || coachDecision?.signal || 'GUARDIAN';

  const modeInfo: Record<string, { emoji: string; label: string; color: string; description: string }> = {
    GUARDIAN: { emoji: '🛡️', label: 'Guardian', color: '#6366f1', description: 'Finding the right profitable bid — optimizing for net ROAS.' },
    BLITZ: { emoji: '⚡', label: 'Blitz', color: '#f59e0b', description: 'Raised bids to capture peak demand — maximize orders during opportunity window.' },
    COOLDOWN: { emoji: '❄️', label: 'Cooldown', color: '#3b82f6', description: 'Post-peak wind-down — gradually reducing bids to pre-peak levels.' },
  };
  const mode = modeInfo[coachMode] || modeInfo.GUARDIAN;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      {/* Coach Mode */}
      <div style={{
        ...CARD_STYLE,
        borderLeft: `3px solid ${mode.color}`,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
          <span style={{ fontSize: 14 }}>{mode.emoji}</span>
          <span style={{ fontWeight: 700, color: mode.color, fontSize: 13 }}>Coach Mode: {mode.label}</span>
        </div>
        <div style={{ color: '#94a3b8', fontSize: 11 }}>{mode.description}</div>
      </div>

      {/* Campaign Ownership */}
      <div style={{ fontWeight: 600, fontSize: 13, color: '#94a3b8', marginBottom: 2 }}>Campaign Ownership</div>
      {campaignOwnership.length === 0 ? (
        <div style={{ color: '#64748b', fontSize: 12 }}>No campaign data available for this term.</div>
      ) : (
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 11 }}>
          <thead>
            <tr style={{ borderBottom: '1px solid rgba(148,163,184,0.15)' }}>
              <th style={{ textAlign: 'left', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Template</th>
              <th style={{ textAlign: 'left', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Campaign</th>
              <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Spend</th>
              <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Orders</th>
              <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Net ROAS</th>
              <th style={{ textAlign: 'center', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {campaignOwnership.flatMap(g =>
              g.campaigns.map((c, i) => (
                <tr key={`${g.template}-${i}`} style={{
                  borderBottom: '1px solid rgba(148,163,184,0.06)',
                }}>
                  {i === 0 ? (
                    <td rowSpan={g.campaigns.length} style={{
                      padding: '5px 8px', verticalAlign: 'top',
                      borderRight: `2px solid ${g.color}20`,
                    }}>
                      <span style={{ fontSize: 12 }}>{g.emoji}</span>{' '}
                      <span style={{ color: g.color, fontWeight: 600 }}>{g.template}</span>
                    </td>
                  ) : null}
                  <td style={{ padding: '4px 8px', color: '#cbd5e1', maxWidth: 220, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={c.name}>
                    {c.name}
                  </td>
                  <td style={{ textAlign: 'right', padding: '4px 8px', color: '#e2e8f0', fontFamily: 'monospace' }}>{fmt$(c.spend)}</td>
                  <td style={{ textAlign: 'right', padding: '4px 8px', color: c.orders > 0 ? '#e2e8f0' : '#ef4444', fontFamily: 'monospace' }}>{c.orders}</td>
                  <td style={{ textAlign: 'right', padding: '4px 8px', color: (c.roas || 0) > 1 ? '#10b981' : '#ef4444', fontFamily: 'monospace' }}>
                    {c.roas != null ? `${c.roas.toFixed(1)}x` : '—'}
                  </td>
                  <td style={{ textAlign: 'center', padding: '4px 8px' }}>
                    <span style={{
                      fontSize: 10, fontWeight: 600, padding: '1px 6px', borderRadius: 6,
                      background: c.action.includes('NEGATE') || c.action.includes('STOP') ? '#ef444422' :
                                  c.action.includes('INCREASE') || c.action.includes('PROMOTE') ? '#22c55e22' : '#64748b18',
                      color: c.action.includes('NEGATE') || c.action.includes('STOP') ? '#ef4444' :
                             c.action.includes('INCREASE') || c.action.includes('PROMOTE') ? '#22c55e' : '#94a3b8',
                    }}>
                      {c.action}
                    </span>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      )}

      {/* Strategic guidance */}
      <div style={{ ...CARD_STYLE, marginTop: 4 }}>
        <div style={{ fontWeight: 600, color: '#94a3b8', marginBottom: 4, fontSize: 12 }}>💡 Recommendations</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: 11, color: '#cbd5e1' }}>
          {data.productCount > 2 && (
            <div>• <strong>Consolidate:</strong> {data.productCount} products compete — decide which product should own this keyword.</div>
          )}
          {data.campaignCount > 3 && (
            <div>• <strong>Simplify:</strong> {data.campaignCount} campaigns running this term — consider consolidating to 1-2 campaigns.</div>
          )}
          {coachMode === 'GUARDIAN' && (
            <div>• <strong>Guardian goal:</strong> Find the right bid baseline to keep this term profitable while maintaining visibility.</div>
          )}
          {coachMode === 'BLITZ' && (
            <div>• <strong>Blitz goal:</strong> Raise bids to capture peak demand — take profit during seasonal windows.</div>
          )}
          {data.heroProductName && data.heroSpendPct < 50 && (
            <div>• <strong>Hero underfunded:</strong> {data.heroProductName} only gets {fmtPct(data.heroSpendPct)} of spend — negate or reduce non-hero campaigns to consolidate.</div>
          )}
        </div>
      </div>
    </div>
  );
}


/* ═══════════════════════════════════════════════════════════════
   TAB 4: ACTIONS — per-campaign with ⊕ add to Do queue
   ═══════════════════════════════════════════════════════════════ */
function ActionsTab({ termActions, onAddToDoQueue, isInDoQueue }: {
  termActions: ActionRow[];
  onAddToDoQueue: (item: Omit<DoQueueItem, 'id' | 'addedAt'>) => void;
  isInDoQueue: (search_term: string, action: string, campaign: string) => boolean;
}) {
  const actionable = useMemo(() => termActions.filter(a => !NON_ACTIONABLE.has(a.action)), [termActions]);
  const monitorable = useMemo(() => termActions.filter(a => NON_ACTIONABLE.has(a.action)), [termActions]);

  const handleAdd = (a: ActionRow) => {
    onAddToDoQueue({
      search_term: a.search_term || '',
      action: a.action || '',
      campaign: a.campaign_name || '',
      campaign_id: a.campaign_id || '',
      ad_group_id: '',
      targeting: a.targeting || '',
      keyword_id: a.keyword_id || '',
      match_type: a.match_type || '',
      target_spend_8w: a.target_spend_8w || 0,
      target_orders_8w: a.target_orders_8w || 0,
      target_net_roas_8w: a.target_net_roas_8w || 0,
      current_bid: a.current_bid || null,
      recommended_bid: a.recommended_bid || null,
      campaign_type: a.campaign_type || '',
      product: a.asin || '',
      spend: a.ads_spend_4w || 0,
      orders: a.ads_orders_4w || 0,
      cpc: a.ads_cpc_4w || 0,
      conv_rate: a.ads_cvr_pct_4w || 0,
    });
  };

  const renderActionRow = (a: ActionRow, showAddButton: boolean) => {
    const tp = detectTemplate(a.campaign_name || '');
    const inQueue = isInDoQueue(a.search_term || '', a.action || '', a.campaign_name || '');
    const isNegate = a.action?.includes('NEGATE') || a.action?.includes('STOP');
    const isIncrease = a.action?.includes('INCREASE') || a.action?.includes('PROMOTE');

    return (
      <tr key={`${a.campaign_id}-${a.action}-${a.targeting || a.search_term}`}
        style={{ borderBottom: '1px solid rgba(148,163,184,0.06)' }}>
        <td style={{ padding: '5px 8px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span style={{ fontSize: 11 }}>{tp.emoji}</span>
            <span style={{ color: '#cbd5e1', fontSize: 11, maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', display: 'inline-block' }} title={a.campaign_name || ''}>
              {a.campaign_name || 'Unknown'}
            </span>
          </div>
          <div style={{ fontSize: 10, color: '#64748b', marginTop: 1 }}>{tp.template} · {a.strategy_name || a.strategy_id || ''}</div>
        </td>
        <td style={{ textAlign: 'center', padding: '5px 8px' }}>
          <span style={{
            fontSize: 10, fontWeight: 700, padding: '2px 7px', borderRadius: 6,
            background: isNegate ? '#ef444422' : isIncrease ? '#22c55e22' : '#64748b18',
            color: isNegate ? '#ef4444' : isIncrease ? '#22c55e' : '#94a3b8',
          }}>
            {a.action}
          </span>
        </td>
        <td style={{ textAlign: 'right', padding: '5px 8px', fontSize: 11, fontFamily: 'monospace' }}>
          {a.current_bid != null && a.recommended_bid != null ? (
            <span>
              <span style={{ color: '#64748b' }}>${a.current_bid.toFixed(2)}</span>
              <span style={{ color: '#94a3b8' }}>→</span>
              <span style={{ color: isIncrease ? '#22c55e' : isNegate ? '#ef4444' : '#e2e8f0', fontWeight: 600 }}>${a.recommended_bid.toFixed(2)}</span>
            </span>
          ) : '—'}
        </td>
        <td style={{ textAlign: 'right', padding: '5px 8px', fontFamily: 'monospace', fontSize: 11, color: '#e2e8f0' }}>{fmt$(a.ads_spend_4w || 0)}</td>
        <td style={{ textAlign: 'right', padding: '5px 8px', fontFamily: 'monospace', fontSize: 11, color: (a.ads_orders_4w || 0) > 0 ? '#e2e8f0' : '#ef4444' }}>{a.ads_orders_4w || 0}</td>
        <td style={{ textAlign: 'center', padding: '5px 4px' }}>
          {showAddButton ? (
            inQueue ? (
              <span style={{
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                width: 22, height: 22, borderRadius: 6,
                background: '#22c55e18', color: '#22c55e', fontSize: 13,
              }}>✓</span>
            ) : (
              <button
                onClick={() => handleAdd(a)}
                style={{
                  display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                  width: 22, height: 22, borderRadius: 6,
                  background: 'rgba(99,102,241,0.15)', color: '#818cf8',
                  border: '1px solid rgba(99,102,241,0.3)',
                  cursor: 'pointer', fontSize: 14, fontWeight: 700,
                  transition: 'all 0.15s',
                }}
                title="Add to Do queue"
                onMouseEnter={e => {
                  (e.target as HTMLElement).style.background = 'rgba(99,102,241,0.3)';
                  (e.target as HTMLElement).style.color = '#a5b4fc';
                }}
                onMouseLeave={e => {
                  (e.target as HTMLElement).style.background = 'rgba(99,102,241,0.15)';
                  (e.target as HTMLElement).style.color = '#818cf8';
                }}
              >
                +
              </button>
            )
          ) : null}
        </td>
      </tr>
    );
  };

  return (
    <div>
      {actionable.length > 0 && (
        <>
          <div style={{ fontWeight: 600, fontSize: 12, color: '#94a3b8', marginBottom: 6 }}>
            Actionable ({actionable.length})
          </div>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 11, marginBottom: 14 }}>
            <thead>
              <tr style={{ borderBottom: '1px solid rgba(148,163,184,0.15)' }}>
                <th style={{ textAlign: 'left', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Campaign</th>
                <th style={{ textAlign: 'center', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Action</th>
                <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Bid</th>
                <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Spend</th>
                <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Ord</th>
                <th style={{ textAlign: 'center', padding: '4px 4px', color: '#64748b', fontWeight: 500, width: 30 }}>Do</th>
              </tr>
            </thead>
            <tbody>
              {actionable.map(a => renderActionRow(a, true))}
            </tbody>
          </table>
        </>
      )}

      {monitorable.length > 0 && (
        <>
          <div style={{ fontWeight: 600, fontSize: 12, color: '#64748b', marginBottom: 6 }}>
            Monitoring ({monitorable.length})
          </div>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 11 }}>
            <thead>
              <tr style={{ borderBottom: '1px solid rgba(148,163,184,0.1)' }}>
                <th style={{ textAlign: 'left', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Campaign</th>
                <th style={{ textAlign: 'center', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Action</th>
                <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Bid</th>
                <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Spend</th>
                <th style={{ textAlign: 'right', padding: '4px 8px', color: '#64748b', fontWeight: 500 }}>Ord</th>
                <th style={{ textAlign: 'center', padding: '4px 4px', color: '#64748b', fontWeight: 500, width: 30 }}></th>
              </tr>
            </thead>
            <tbody>
              {monitorable.map(a => renderActionRow(a, false))}
            </tbody>
          </table>
        </>
      )}

      {termActions.length === 0 && (
        <div style={{ color: '#64748b', fontSize: 12, padding: 8 }}>No coach actions found for this keyword.</div>
      )}
    </div>
  );
}


/* ═══════════════════════════════════════════════════════════════
   MAIN PANEL — 4-tab container
   ═══════════════════════════════════════════════════════════════ */
export default function KeywordIntelligencePanel({
  data, loading, termActions, coachDecision, onAddToDoQueue, isInDoQueue,
}: KeywordIntelligencePanelProps) {
  const [activeTab, setActiveTab] = useState<TabId>('data');

  if (loading) {
    return (
      <div style={{
        padding: '20px 24px',
        background: 'rgba(15, 23, 42, 0.6)',
        borderRadius: 10,
        border: '1px solid rgba(148,163,184,0.1)',
        color: '#94a3b8',
        fontSize: 13,
      }}>
        Loading keyword intelligence...
      </div>
    );
  }

  const actionableCount = termActions.filter(a => !NON_ACTIONABLE.has(a.action)).length;

  const TABS: { id: TabId; label: string; emoji: string; badge?: number; badgeColor?: string }[] = [
    { id: 'data', label: 'Data', emoji: '📊' },
    { id: 'findings', label: 'Findings', emoji: '💡' },
    { id: 'strategy', label: 'Strategy', emoji: '🎯' },
    { id: 'actions', label: 'Actions', emoji: '⚡', badge: actionableCount || undefined, badgeColor: '#6366f1' },
  ];

  return (
    <div style={{
      padding: '16px 20px',
      background: 'linear-gradient(135deg, rgba(15,23,42,0.8) 0%, rgba(30,41,59,0.6) 100%)',
      borderRadius: 10,
      border: '1px solid rgba(99,102,241,0.15)',
      margin: '8px 0 12px 32px',
      boxShadow: '0 4px 12px rgba(0,0,0,0.15)',
    }}>
      {/* Header */}
      <div style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'flex-start',
        marginBottom: 10,
        flexWrap: 'wrap',
        gap: 8,
      }}>
        <div>
          <span style={{ fontSize: 14, fontWeight: 700, color: '#e2e8f0' }}>
            🔍 Keyword Intelligence
          </span>
          <span style={{ fontSize: 12, color: '#94a3b8', marginLeft: 8 }}>
            {data.campaignCount} campaigns · {data.productCount} products
          </span>
        </div>

        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {data.isHeroUnstable && <AlertBadge label="Hero Unstable" color="#ef4444" />}
          {data.isHeroUnproven && <AlertBadge label={`Hero ${data.heroDataMonths}mo data`} color="#f59e0b" />}
          {data.isFragmented && <AlertBadge label={`${data.heroSpendPct}% hero spend`} color="#8b5cf6" />}
          {data.isMultiCampaign && <AlertBadge label={`${data.campaignCount} campaigns`} color="#6366f1" />}
        </div>
      </div>

      {/* Current Hero Callout */}
      {data.heroProductName && (
        <div style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          padding: '6px 12px',
          borderRadius: 8,
          background: 'rgba(245,158,11,0.08)',
          border: '1px solid rgba(245,158,11,0.15)',
          marginBottom: 10,
          fontSize: 12,
        }}>
          <div>
            <span style={{ color: '#f59e0b', fontWeight: 600 }}>⭐ Current Hero: </span>
            <span style={{ color: '#e2e8f0', fontWeight: 600 }}>{data.heroProductName}</span>
          </div>
          <div style={{ display: 'flex', gap: 12, color: '#94a3b8' }}>
            <span>CVR {fmtPct(data.heroCvrPct)}</span>
            <span>ROAS {data.heroNetRoas.toFixed(1)}x</span>
            <span>Spend share {fmtPct(data.heroSpendPct)}</span>
            <span>Stability {fmtPct(data.heroStabilityPct)}</span>
          </div>
        </div>
      )}

      {/* Tab Bar */}
      <div style={TAB_STYLES.container}>
        {TABS.map(tab => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            style={TAB_STYLES.tab(activeTab === tab.id)}
          >
            <span>{tab.emoji}</span>
            <span>{tab.label}</span>
            {tab.badge != null && tab.badge > 0 && (
              <span style={TAB_STYLES.badge(tab.badgeColor || '#6366f1')}>{tab.badge}</span>
            )}
          </button>
        ))}
      </div>

      {/* Tab Content */}
      {activeTab === 'data' && <DataTab data={data} />}
      {activeTab === 'findings' && <FindingsTab data={data} termActions={termActions} />}
      {activeTab === 'strategy' && <StrategyTab data={data} termActions={termActions} coachDecision={coachDecision} />}
      {activeTab === 'actions' && <ActionsTab termActions={termActions} onAddToDoQueue={onAddToDoQueue} isInDoQueue={isInDoQueue} />}
    </div>
  );
}
