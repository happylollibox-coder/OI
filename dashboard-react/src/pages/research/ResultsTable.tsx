import { Fragment, useState } from 'react';
import { ArrowUpDown, Check, Pencil } from 'lucide-react';
import { fmt, fM, fP, fShort } from '../../utils';
import type { ResearchRow, SortKey, SortDir, TermRanksMap } from './types';

interface ResultsTableProps {
  rows: ResearchRow[];            // current page of display rows
  totalCount: number;             // total display rows (across pages)
  currentPage: number;
  pageSize: number;
  onPageChange: (p: number) => void;
  sortKey: SortKey;
  sortDir: SortDir;
  onSort: (k: SortKey) => void;
  selectedProduct: string;
  productPrice: number;
  termRanks: TermRanksMap;
  onSaveSegments: (queryText: string, segs: Record<string, string | null>) => Promise<void>;
}

// ─── Tooltips: pure formatters over SQL explanation columns ──────
// Scoring itself lives in V_RESEARCH_RANKED (see architecture/RESEARCH_PAGE.md).

const segFitTooltip = (row: ResearchRow): string => {
  const fld = (label: string, val: string | null, score: number | null, pts: number) => {
    if (score == null) return `${label}: family not segmented (skipped)`;
    if (score === -1) return `${label}: "${val}" ✗ MISMATCH → cap 10`;
    if (score === 0) return `${label}: unknown → +0`;
    return `${label}: "${val}" ${score < pts ? '~ ADJACENT' : '✓ MATCH'} → +${score}`;
  };
  return [
    `SEG FIT for "${row.query_text}" — ${row.seg_fit ?? '—'}/100`,
    fld('Gender', row.gender, row.gender_score, 30),
    fld('Age', row.age_group, row.age_score, 30),
    fld('Occasion', row.occasion, row.occasion_score, 10),
    fld('Prod Type', row.product_type, row.pt_score, 30),
  ].join('\n');
};

const cpsFitTooltip = (row: ResearchRow): string => {
  const lines = [`CPS FIT for "${row.query_text}" — ${row.cps_fit ?? '—'}/100`];
  if (row.cps_source === 'ads_30d' || row.cps_source === 'ads_12m') {
    lines.push(`Source: real ads CVR (${row.cps_source === 'ads_30d' ? '30d' : '12m'}, ${row.ads_family_orders} orders)`);
  } else if (row.cps_source === 'curve') {
    lines.push(`Source: conversion curve (median price $${row.median_click_price?.toFixed(2) ?? '?'})`);
  } else {
    lines.push('No CVR data and no curve match');
  }
  if (row.effective_cps != null) lines.push(`CPS: ${row.effective_cps.toFixed(1)} clicks/sale`);
  lines.push('', 'Brackets: ≤5→100 | ≤8→85 | ≤12→70 | ≤20→55 | ≤35→35 | ≤50→20 | 50+→10');
  return lines.join('\n');
};

const occasionEmoji: Record<string, string> = {
  Birthday: '🎂', Christmas: '🎄', Easter: '🐰', Valentines: '💝',
  Graduation: '🎓', 'Back to School': '📚', Performance: '🎭',
  'Get Well': '💐', Encouragement: '💪', 'Mothers Day': '🌸',
  'Fathers Day': '👔', Wedding: '💒', Sleepover: '🛏️', Camp: '⛺', 'Sweet 16': '👑',
};

export function ResultsTable({
  rows, totalCount, currentPage, pageSize, onPageChange,
  sortKey, sortDir, onSort,
  selectedProduct, productPrice, termRanks, onSaveSegments,
}: ResultsTableProps) {
  const [editingTerm, setEditingTerm] = useState<string | null>(null);
  const [editSegments, setEditSegments] = useState<Record<string, string | null>>({});
  const [savingSegment, setSavingSegment] = useState(false);

  const totalPages = Math.ceil(totalCount / pageSize);

  // ─── Per-family comparison hover (from /api/research/term-ranks) ───
  const familyCompareTooltip = (row: ResearchRow): string => {
    const ranks = termRanks[row.query_text.toLowerCase()];
    if (!ranks || ranks.length === 0) return row.query_text;
    const lines = [`"${row.query_text}"`, '', 'Family        │ Rank│  Fit│ Seg │ CPS'];
    for (const fr of [...ranks].sort((a, b) => (b.rank ?? -1) - (a.rank ?? -1))) {
      const hero = fr.parent_name === selectedProduct ? ' ★' : '';
      lines.push(
        `${(fr.parent_name + hero).padEnd(14)}│${String(fr.rank ?? '—').padStart(4)} │${String(fr.overall_fit ?? '—').padStart(4)} │${String(fr.seg_fit ?? '—').padStart(4)} │${String(fr.cps_fit ?? '—').padStart(4)}`
      );
    }
    return lines.join('\n');
  };

  // ─── Price ratio bucket color ─────────────────────────
  const ratioColor = (medianPrice: number | null): string => {
    if (!medianPrice || medianPrice <= 0) return '';
    const ratio = productPrice / medianPrice;
    if (ratio < 0.8) return 'text-emerald-400';
    if (ratio < 1.2) return 'text-emerald-400 font-semibold';
    if (ratio < 1.8) return 'text-amber-400';
    if (ratio < 2.5) return 'text-orange-400';
    return 'text-red-400';
  };

  // ─── SortableHeader ───────────────────────────────────
  const SortHeader = ({ label, colKey, className = '', tooltip = '' }: { label: string; colKey: SortKey; className?: string; tooltip?: string }) => (
    <th
      className={`px-2 py-2 text-[9px] text-muted font-semibold uppercase tracking-wide cursor-pointer hover:text-subtle transition-colors whitespace-nowrap select-none ${className}`}
      onClick={() => onSort(colKey)}
      title={tooltip}
    >
      <span className="inline-flex items-center gap-0.5">
        {label}
        {sortKey === colKey && (
          <ArrowUpDown size={9} className={`${sortDir === 'desc' ? 'rotate-0' : 'rotate-180'} text-blue-400`} />
        )}
      </span>
    </th>
  );

  // ─── Split paged rows into sections (Brand / Off-Season / per Occasion) ───
  const brandRows = rows.filter(r => (r.brand_impressions || 0) > 0);
  const nonBrandRows = rows.filter(r => (r.brand_impressions || 0) === 0);
  const offSeasonRows = nonBrandRows.filter(r => !r.occasion);

  const occasionGroups: Record<string, ResearchRow[]> = {};
  nonBrandRows.filter(r => r.occasion).forEach(r => {
    const key = r.occasion!;
    if (!occasionGroups[key]) occasionGroups[key] = [];
    occasionGroups[key].push(r);
  });
  const occasionOrder = Object.entries(occasionGroups)
    .sort(([, a], [, b]) => b.reduce((s, r) => s + (r.market_impressions || 0), 0) - a.reduce((s, r) => s + (r.market_impressions || 0), 0))
    .map(([key]) => key);

  const sections: { label: string; rows: ResearchRow[] }[] = [];
  if (brandRows.length > 0) sections.push({ label: '🏷️ Brand Terms', rows: brandRows });
  if (offSeasonRows.length > 0) sections.push({ label: '📊 General / Off-Season', rows: offSeasonRows });
  occasionOrder.forEach(occ => {
    sections.push({ label: `${occasionEmoji[occ] || '📅'} ${occ}`, rows: occasionGroups[occ] });
  });

  const Pagination = ({ scrollTop = false }: { scrollTop?: boolean }) => (
    totalPages > 1 ? (
      <div className="flex items-center justify-between px-1">
        <span className="text-[10px] text-muted">
          Showing {((currentPage - 1) * pageSize) + 1}–{Math.min(currentPage * pageSize, totalCount)} of {totalCount}
        </span>
        <div className="flex items-center gap-1">
          <button
            onClick={() => { onPageChange(Math.max(1, currentPage - 1)); if (scrollTop) window.scrollTo({ top: 0, behavior: 'smooth' }); }}
            disabled={currentPage === 1}
            className="px-2 py-1 text-[10px] font-semibold rounded border border-border text-muted hover:text-heading disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          >← Prev</button>
          {Array.from({ length: totalPages }, (_, i) => i + 1).map(p => (
            <button
              key={p}
              onClick={() => { onPageChange(p); if (scrollTop) window.scrollTo({ top: 0, behavior: 'smooth' }); }}
              className={`px-2 py-1 text-[10px] font-semibold rounded border transition-colors ${
                p === currentPage
                  ? 'bg-blue-600 text-white border-blue-600'
                  : 'border-border text-muted hover:text-heading'
              }`}
            >{p}</button>
          ))}
          <button
            onClick={() => { onPageChange(Math.min(totalPages, currentPage + 1)); if (scrollTop) window.scrollTo({ top: 0, behavior: 'smooth' }); }}
            disabled={currentPage === totalPages}
            className="px-2 py-1 text-[10px] font-semibold rounded border border-border text-muted hover:text-heading disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          >Next →</button>
        </div>
      </div>
    ) : null
  );

  return (
    <div className="space-y-6">
      <Pagination />
      {sections.map(section => (
        <div key={section.label}>
          {/* Section header */}
          <div className="flex items-center gap-3 mb-2">
            <h4 className="text-xs font-bold text-heading">{section.label}</h4>
            <span className="text-[9px] text-muted tabular-nums">{section.rows.length} terms</span>
            <span className="text-[9px] text-muted tabular-nums">
              · {fShort(section.rows.reduce((s, r) => s + (r.market_impressions || 0), 0))} vol
            </span>
            <span className="text-[9px] text-muted tabular-nums">
              · {fmt(section.rows.reduce((s, r) => s + (r.market_purchases || 0), 0))} purch
            </span>
          </div>
          <div className="overflow-x-auto -mx-4">
            <table className="w-full text-[11px]">
              <thead>
                <tr className="border-b border-border/30">
                  <SortHeader label="Search Term" colKey="query_text" className="text-left pl-4 sticky left-0 bg-surface/95 backdrop-blur z-10" tooltip="Amazon search query from SQP data. Hover a row's term to compare ranks across all families." />
                  <SortHeader label="Rank" colKey="rank" className="text-center" tooltip="Overall rank = average of Fit and Purchase Rank (0-100)" />
                  <SortHeader label="Purch" colKey="purchase_rank" className="text-center" tooltip="Purchase rank based on weekly market purchases (bucket score 0-100). ≥1000→100 | ≥500→90 | ≥200→80 | ≥100→70 | ≥50→55 | ≥20→40 | ≥5→25 | <5→10" />
                  <SortHeader label="Fit" colKey="overall_fit" className="text-center" tooltip="If >3 ad sales → CPS FIT only. Otherwise → SEG FIT minus a price penalty (Pricier −10, Much pricier −20, Way above −30)" />
                  <SortHeader label="Seg Fit" colKey="match_rank" className="text-center" tooltip="Segment fit: how well this search term's segments (gender, age, occasion, type) align with your product family (0-100)" />
                  <SortHeader label="CPS Fit" colKey="cps_fit" className="text-center" tooltip="CPS fit: how efficiently this search term converts to sales (based on real CVR or conversion curve). Lower CPS = higher score." />
                  <SortHeader label="Brand" colKey="brand" className="text-center" tooltip="Detected brand in the search term (own brand or competitor)" />
                  <th className="px-2 py-2 text-[9px] text-muted font-semibold uppercase tracking-wide" title="Direct = contains your search words. Related = shares ASINs with direct matches">Match</th>
                  <SortHeader label="Relevance" colKey="overlap_pct" className="text-center" tooltip="% of seed ASINs that also appear for this query (higher = more relevant)" />
                  <SortHeader label="Type" colKey="product_type" className="text-center" tooltip="Product category from DE_PRODUCT_TYPE_KEYWORDS" />
                  <SortHeader label="Gender" colKey="gender" className="text-center" tooltip="Auto-detected target gender from search term" />
                  <SortHeader label="Age" colKey="age_group" className="text-center" tooltip="Auto-detected target age group from search term" />
                  <SortHeader label="Occasion" colKey="occasion" className="text-center" tooltip="Auto-detected occasion from search term (Birthday, Graduation, etc.)" />
                  <SortHeader label="Holiday" colKey="holiday" className="text-center" tooltip="Auto-detected holiday from search term. Off-season holidays → rank = 0" />
                  <th className="px-2 py-2 text-[9px] text-muted font-semibold uppercase tracking-wide text-center" title="Manually fix auto-detected segments for this search term">✏️</th>
                  <SortHeader label="Cost Tier" colKey="cost_tier" className="text-center" tooltip="Price tier based on median click price vs. your product price" />
                  <SortHeader label="Weeks" colKey="weeks_appeared" className="text-right" tooltip="Number of weeks this query appeared in SQP data (104-week window)" />
                  <SortHeader label="Week" colKey="last_week" className="text-right" tooltip="The most recent week of SQP data for this search term" />
                  <SortHeader label="Wk Vol." colKey="weekly_market_impressions" className="text-right" tooltip="Last week's market impressions (all sellers) for this search term" />
                  <SortHeader label="Wk Purch." colKey="weekly_market_purchases" className="text-right" tooltip="Last week's market purchases from this search term (all sellers)" />
                  <SortHeader label="Wk CVR%" colKey="weekly_market_cvr_pct" className="text-right" tooltip="Last week's market conversion rate: purchases / clicks (all sellers)" />
                  <SortHeader label="Wk MD Purch" colKey="median_click_price" className="text-right" tooltip="Last week's median purchase price — typical price of products bought for this query" />
                  <SortHeader label="Wk MD Click" colKey="clicks_median" className="text-right" tooltip="Last week's median click price — typical price of products clicked for this query" />
                  <SortHeader label="Fam. Impr." colKey="family_impressions" className="text-right" tooltip="This product family's impressions for this search term (SQP data)" />
                  <SortHeader label="Fam. Purch." colKey="family_purchases" className="text-right" tooltip="This product family's purchases from this search term (SQP data)" />
                  <SortHeader label="Brand Impr." colKey="brand_impressions" className="text-right" tooltip="Your brand's total impressions for this search term (all ASINs)" />
                  <SortHeader label="Brand Purch." colKey="brand_purchases" className="text-right" tooltip="Your brand's total purchases from this search term (all ASINs)" />
                  <SortHeader label="Brand Show%" colKey="show_rate_pct" className="text-right" tooltip="Your share of impressions: brand impressions / market impressions" />
                  <SortHeader label="CPC 12m" colKey="cpc_12m" className="text-right" tooltip="Your average cost-per-click for this term over the last 12 months (from Ads data)" />
                  <SortHeader label="CPC 30d" colKey="cpc_30d" className="text-right" tooltip="Your average cost-per-click for this term over the last 30 days (from Ads data)" />
                  <SortHeader label="CVR 12m" colKey="units_cvr_12m" className="text-right" tooltip="Ads unit conversion rate (units sold / clicks) over the last 12 months" />
                  <SortHeader label="CVR 30d" colKey="units_cvr_30d" className="text-right" tooltip="Ads unit conversion rate (units sold / clicks) over the last 30 days" />
                  <SortHeader label="ROAS 30d" colKey="roas_30d" className="text-right" tooltip="Return on ad spend (sales / spend) over the last 30 days" />
                  <th className="px-2 py-2 text-[9px] text-muted font-semibold uppercase tracking-wide text-right" title="Ads units sold. If 30d > 3 → 30d value, else 12m value">Ads Purch</th>
                  <th className="px-2 py-2 text-[9px] text-muted font-semibold uppercase tracking-wide text-right" title="Ads CPS = 1/CVR. If 30d units > 3 → 30d CVR, else 12m CVR">Ads CPS</th>
                  <SortHeader label="Est. CPS" colKey="est_clicks_per_sale" className="text-right" tooltip="Market-model clicks per sale: family conversion curve at the term's price bucket × the term's market intent (SQP, 0.5×–2×). Independent of your ads — compare against Ads CPS." />
                  <th className="px-2 py-2 text-[9px] text-muted font-semibold uppercase tracking-wide text-right" title="Estimated cost per sale = Est. CPS × CPC (30d or 12m)">Est. $/Sale</th>
                </tr>
              </thead>
              <tbody>
                {section.rows.map((row, i) => {
                  const isRealCps = row.cps_source === 'ads_30d' || row.cps_source === 'ads_12m';
                  const estCps = row.effective_cps ?? row.est_cps;
                  const cpc = row.cpc_30d ?? row.cpc_12m;
                  const estCostPerSale = estCps && cpc ? estCps * cpc : null;
                  const rowRatioColor = ratioColor(row.median_click_price);

                  return (
                    <Fragment key={row.query_text}>
                      <tr
                        className={`border-b border-border/10 hover:bg-white/[0.02] transition-colors ${
                          i % 2 === 0 ? 'bg-white/[0.01]' : ''
                        }`}
                      >
                        {/* Search Term — hover shows all-families comparison (SQL-computed) */}
                        <td className="px-2 py-2 pl-4 text-heading font-medium whitespace-nowrap sticky left-0 bg-inherit backdrop-blur z-10 max-w-[280px] truncate" title={familyCompareTooltip(row)}>
                          {row.query_text}
                        </td>

                        {/* Rank = avg(Fit, Purchase Rank) */}
                        <td className="px-2 py-2 text-center">
                          {(() => {
                            const r = row.rank_score;
                            if (r == null) return <span className="text-[8px] text-muted">—</span>;
                            const color = r >= 70 ? 'text-emerald-400 bg-emerald-500/15' :
                                          r >= 40 ? 'text-amber-400 bg-amber-500/15' :
                                          r > 0 ? 'text-red-400 bg-red-500/15' : 'text-muted bg-white/5';
                            const fitSrc = isRealCps && row.ads_family_orders > 3 ? 'Ads CPS' : 'Seg−price adj';
                            return (
                              <span className={`inline-block px-1.5 py-0.5 rounded text-[8px] font-bold tabular-nums ${color}`}
                                title={`Rank: ${r} = avg(Fit:${row.overall_fit ?? '—'} [${fitSrc}], Purch:${row.purchase_rank_score ?? '—'})${row.holiday && row.is_holiday_active === false ? '\nOff-season holiday → rank forced to 0' : ''}`}>{r}</span>
                            );
                          })()}
                        </td>

                        {/* Purchase Rank */}
                        <td className="px-2 py-2 text-center">
                          {(() => {
                            const pr = row.purchase_rank_score;
                            if (pr == null) return <span className="text-[8px] text-muted">—</span>;
                            const color = pr >= 70 ? 'text-emerald-400' :
                                          pr >= 40 ? 'text-amber-400' :
                                          pr > 0 ? 'text-red-400' : 'text-muted';
                            return <span className={`text-[8px] font-bold tabular-nums ${color}`}
                              title={`Purch Rank: ${pr}/100\nWk Purch: ${row.weekly_market_purchases ?? '—'}\n\nBuckets: ≥1000→100 | ≥500→90 | ≥200→80 | ≥100→70\n≥50→55 | ≥20→40 | ≥5→25 | <5→10`}>{pr}</span>;
                          })()}
                        </td>

                        {/* Overall Fit */}
                        <td className="px-2 py-2 text-center">
                          {(() => {
                            const overall = row.overall_fit;
                            if (overall == null) return <span className="text-[8px] text-muted">—</span>;
                            const color = overall >= 70 ? 'text-emerald-400 bg-emerald-500/15' :
                                          overall >= 40 ? 'text-amber-400 bg-amber-500/15' :
                                          overall > 0 ? 'text-red-400 bg-red-500/15' : 'text-muted bg-white/5';
                            const hasRealCps = isRealCps && row.ads_family_orders > 3;
                            const bucketPenalty: Record<string, number> = {
                              'C. Pricier': 10, 'D. Much pricier': 20, 'E. Way above': 30,
                            };
                            const penalty = row.price_bucket ? (bucketPenalty[row.price_bucket] ?? 0) : 0;
                            const tooltip = hasRealCps
                              ? `Fit: ${overall} = CPS FIT (Ads CPS: ${row.ads_cps ?? '—'}, ${row.ads_family_orders} sales)`
                              : `Fit: ${overall} = Seg ${row.seg_fit ?? '—'}${penalty > 0 ? ` − ${penalty} (${row.price_bucket})` : ` − 0 (${row.price_bucket ?? 'no price bucket'})`}`;
                            return (
                              <span className={`inline-block px-1.5 py-0.5 rounded text-[8px] font-bold tabular-nums ${color}`}
                                title={tooltip}>
                                {overall}
                              </span>
                            );
                          })()}
                        </td>

                        {/* Segment Fit — tooltip from SQL per-field scores */}
                        <td className="px-2 py-2 text-center">
                          {(() => {
                            const rank = row.seg_fit;
                            if (rank == null) return <span className="text-[8px] text-muted">—</span>;
                            const color = rank >= 70 ? 'text-emerald-400' :
                                          rank >= 40 ? 'text-amber-400' :
                                          rank > 0 ? 'text-red-400' : 'text-muted';
                            return <span className={`text-[8px] font-bold tabular-nums ${color}`} title={segFitTooltip(row)}>{rank}</span>;
                          })()}
                        </td>

                        {/* CPS Fit — tooltip from SQL cps_source/effective_cps */}
                        <td className="px-2 py-2 text-center">
                          {(() => {
                            const cf = row.cps_fit;
                            if (cf == null) return <span className="text-[8px] text-muted">—</span>;
                            const color = cf >= 70 ? 'text-emerald-400' :
                                          cf >= 40 ? 'text-amber-400' :
                                          cf > 10 ? 'text-orange-400' : 'text-red-400';
                            return <span className={`text-[8px] font-bold tabular-nums ${color}`} title={cpsFitTooltip(row)}>{cf}</span>;
                          })()}
                        </td>

                        {/* Brand */}
                        <td className="px-2 py-2 text-center">
                          {row.brand && (
                            <span className={`inline-block px-1 py-0.5 rounded text-[8px] font-bold ${
                              row.brand === 'Happy Lolli'
                                ? 'bg-cyan-500/15 text-cyan-400'
                                : 'bg-orange-500/15 text-orange-400'
                            }`} title={row.brand}>
                              {row.brand}
                            </span>
                          )}
                        </td>

                        {/* Match Type */}
                        <td className="px-2 py-2 text-center">
                          <span className={`inline-block px-1.5 py-0.5 rounded text-[8px] font-bold uppercase ${
                            row.match_type === 'direct'
                              ? 'bg-blue-500/15 text-blue-400'
                              : 'bg-purple-500/15 text-purple-400'
                          }`}>
                            {row.match_type}
                          </span>
                        </td>

                        {/* Relevance (overlap %) */}
                        <td className="px-2 py-2 text-center">
                          {row.match_type === 'direct' ? (
                            <span className="text-[8px] text-muted">—</span>
                          ) : (
                            <div className="flex items-center gap-1 justify-center" title={`${row.asin_overlap} of ${row.total_seed_asins} ASINs overlap`}>
                              <div className="w-12 h-1.5 bg-white/5 rounded-full overflow-hidden">
                                <div
                                  className={`h-full rounded-full transition-all ${
                                    (row.overlap_pct ?? 0) >= 50 ? 'bg-emerald-400' :
                                    (row.overlap_pct ?? 0) >= 25 ? 'bg-amber-400' : 'bg-red-400'
                                  }`}
                                  style={{ width: `${Math.min(row.overlap_pct ?? 0, 100)}%` }}
                                />
                              </div>
                              <span className={`text-[8px] font-medium tabular-nums ${
                                (row.overlap_pct ?? 0) >= 50 ? 'text-emerald-400' :
                                (row.overlap_pct ?? 0) >= 25 ? 'text-amber-400' : 'text-red-400'
                              }`}>
                                {row.overlap_pct ?? 0}%
                              </span>
                            </div>
                          )}
                        </td>

                        {/* Product Type */}
                        <td className="px-2 py-2 text-center">
                          {row.product_type ? (
                            <span className="px-1.5 py-0.5 rounded text-[8px] font-medium bg-violet-500/10 text-violet-400 whitespace-nowrap">{row.product_type}</span>
                          ) : <span className="text-[8px] text-muted">—</span>}
                        </td>

                        {/* Gender */}
                        <td className="px-2 py-2 text-center">
                          {row.gender ? (
                            <span className={`px-1.5 py-0.5 rounded text-[8px] font-medium whitespace-nowrap ${row.gender === 'Female' ? 'bg-pink-500/10 text-pink-400' : 'bg-blue-500/10 text-blue-400'}`}>
                              {row.gender === 'Female' ? '♀ F' : '♂ M'}
                            </span>
                          ) : <span className="text-[8px] text-muted">—</span>}
                        </td>

                        {/* Age Group */}
                        <td className="px-2 py-2 text-center">
                          {row.age_group ? (
                            <span className="px-1.5 py-0.5 rounded text-[8px] font-medium bg-cyan-500/10 text-cyan-400 whitespace-nowrap">{row.age_group}</span>
                          ) : <span className="text-[8px] text-muted">—</span>}
                        </td>

                        {/* Occasion */}
                        <td className="px-2 py-2 text-center">
                          {row.occasion ? (
                            <span className="px-1.5 py-0.5 rounded text-[8px] font-medium bg-amber-500/10 text-amber-400 whitespace-nowrap">{row.occasion}</span>
                          ) : <span className="text-[8px] text-muted">—</span>}
                        </td>

                        {/* Holiday — active flag computed in SQL */}
                        <td className="px-2 py-2 text-center">
                          {row.holiday ? (
                            <span className={`px-1.5 py-0.5 rounded text-[8px] font-medium whitespace-nowrap ${(row.is_holiday_active ?? false) ? 'bg-emerald-500/10 text-emerald-400' : 'bg-pink-500/10 text-pink-400'}`}>{row.holiday}</span>
                          ) : <span className="text-[8px] text-muted">—</span>}
                        </td>

                        {/* Edit Segments */}
                        <td className="px-2 py-2 text-center">
                          <button
                            onClick={() => {
                              if (editingTerm === row.query_text) {
                                setEditingTerm(null);
                              } else {
                                setEditingTerm(row.query_text);
                                setEditSegments({
                                  gender: row.gender,
                                  age_group: row.age_group,
                                  occasion: row.occasion,
                                  cost_tier: row.cost_tier,
                                  product_type: row.product_type,
                                  brand: row.brand,
                                });
                              }
                            }}
                            className="p-0.5 rounded hover:bg-white/10 text-muted hover:text-heading transition-colors"
                            title="Edit segments"
                          >
                            <Pencil size={10} />
                          </button>
                        </td>

                        {/* Cost Tier */}
                        <td className="px-2 py-2 text-center">
                          {row.cost_tier ? (
                            <span className="px-1.5 py-0.5 rounded text-[8px] font-medium bg-emerald-500/10 text-emerald-400 whitespace-nowrap">{row.cost_tier}</span>
                          ) : <span className="text-[8px] text-muted">—</span>}
                        </td>

                        {/* Weeks */}
                        <td className="px-2 py-2 text-right text-muted tabular-nums">{row.weeks_appeared}</td>

                        {/* Last Week Date */}
                        <td className="px-2 py-2 text-right text-muted tabular-nums text-[9px] whitespace-nowrap">
                          {row.last_week ? new Date(row.last_week + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: '2-digit' }) : '—'}
                        </td>

                        {/* Weekly Market Volume */}
                        <td className="px-2 py-2 text-right text-heading tabular-nums" title={`Total: ${fShort(row.market_impressions)} | Week: ${row.last_week || '—'}`}>{fShort(row.weekly_market_impressions)}</td>

                        {/* Weekly Market Purchases */}
                        <td className="px-2 py-2 text-right text-heading font-medium tabular-nums" title={`Total: ${fmt(row.market_purchases)}`}>{fmt(row.weekly_market_purchases)}</td>

                        {/* Weekly Market CVR */}
                        <td className="px-2 py-2 text-right text-muted tabular-nums" title={`Total: ${row.market_cvr_pct != null ? fP(row.market_cvr_pct) : '--'}`}>{row.weekly_market_cvr_pct != null ? fP(row.weekly_market_cvr_pct) : '--'}</td>

                        {/* Purchase Median Price */}
                        <td className="px-2 py-2 text-right text-muted tabular-nums">
                          {row.median_click_price != null ? fM(row.median_click_price) : '--'}
                        </td>

                        {/* Click Median Price */}
                        <td className="px-2 py-2 text-right text-muted tabular-nums">
                          {row.clicks_median != null ? fM(row.clicks_median) : '--'}
                        </td>

                        {/* Family Impressions */}
                        <td className="px-2 py-2 text-right text-muted tabular-nums" title={`Brand total: ${fShort(row.brand_impressions)}`}>{fShort(row.family_impressions)}</td>

                        {/* Family Purchases */}
                        <td className="px-2 py-2 text-right text-heading tabular-nums">{fmt(row.family_purchases)}</td>

                        {/* Brand Impressions */}
                        <td className="px-2 py-2 text-right text-muted tabular-nums">{fShort(row.brand_impressions)}</td>

                        {/* Brand Purchases */}
                        <td className="px-2 py-2 text-right text-heading tabular-nums">{fmt(row.brand_purchases)}</td>

                        {/* Brand Show Rate */}
                        <td className="px-2 py-2 text-right text-muted tabular-nums">
                          {(() => {
                            const sr = row.market_impressions > 0 ? (row.brand_impressions / row.market_impressions) * 100 : null;
                            if (sr == null) return '--';
                            return sr < 0.01 ? '<0.01%' : fP(sr);
                          })()}
                        </td>

                        {/* CPC 12m */}
                        <td className="px-2 py-2 text-right text-muted tabular-nums">
                          {row.ads_family_orders > 0 && row.cpc_12m != null ? fM(row.cpc_12m) : '--'}
                        </td>

                        {/* CPC 30d */}
                        <td className="px-2 py-2 text-right text-muted tabular-nums">
                          {row.ads_family_orders > 0 && row.cpc_30d != null ? fM(row.cpc_30d) : '--'}
                        </td>

                        {/* Units CVR 12m */}
                        <td className="px-2 py-2 text-right text-muted tabular-nums">
                          {row.ads_family_orders > 0 && row.units_cvr_12m != null ? fP(row.units_cvr_12m * 100) : '--'}
                        </td>

                        {/* Units CVR 30d */}
                        <td className="px-2 py-2 text-right text-muted tabular-nums">
                          {row.ads_family_orders > 0 && row.units_cvr_30d != null ? fP(row.units_cvr_30d * 100) : '--'}
                        </td>

                        {/* ROAS 30d */}
                        <td className="px-2 py-2 text-right tabular-nums">
                          {row.ads_family_orders > 0 && row.roas_30d != null ? fmt(row.roas_30d, 2) : '--'}
                        </td>

                        {/* Ads Purch: pre-computed from SQL */}
                        <td className="px-2 py-2 text-right tabular-nums">
                          {row.ads_purch != null
                            ? <span className={`text-[8px] ${(row.ads_units_30d ?? 0) > 3 ? 'text-body' : 'text-muted'}`}
                                title={`${(row.ads_units_30d ?? 0) > 3 ? '30d' : '12m'}: ${row.ads_purch} units`}>{row.ads_purch}</span>
                            : <span className="text-[8px] text-muted">--</span>
                          }
                        </td>

                        {/* Ads CPS: pre-computed from SQL */}
                        <td className="px-2 py-2 text-right tabular-nums">
                          {row.ads_cps != null
                            ? <span className="text-[8px] text-body"
                                title={`Ads CPS: ${row.ads_cps} clicks/sale (${(row.ads_units_30d ?? 0) > 3 ? '30d' : '12m'})`}>{row.ads_cps.toFixed(1)}</span>
                            : <span className="text-[8px] text-muted">--</span>
                          }
                        </td>

                        {/* Est. Clicks Per Sale — market model, independent of our ads */}
                        <td className={`px-2 py-2 text-right tabular-nums font-medium ${rowRatioColor}`}
                          title={row.est_cps == null
                            ? 'No estimate: no curve match for this price bucket'
                            : row.intent_factor != null
                              ? `Market model: curve ${row.est_cps_curve?.toFixed(1)} (${row.price_bucket}) × term intent ${row.intent_factor.toFixed(2)} = ${row.est_cps.toFixed(1)} clicks/sale${isRealCps ? `\nCompare: real Ads CPS ${row.ads_cps ?? '—'}` : ''}`
                              : `Market model: curve ${row.est_cps_curve?.toFixed(1) ?? row.est_cps.toFixed(1)} (${row.price_bucket ?? 'bucket'}), no market intent data${isRealCps ? `\nCompare: real Ads CPS ${row.ads_cps ?? '—'}` : ''}`}>
                          {row.est_cps != null ? fmt(row.est_cps, 1) : '--'}
                        </td>

                        {/* Est. Cost Per Sale */}
                        <td className="px-2 py-2 text-right tabular-nums">
                          {estCostPerSale != null ? fM(estCostPerSale) : '--'}
                        </td>

                      </tr>
                      {/* Inline segment editor */}
                      {editingTerm === row.query_text && (
                        <tr className="bg-white/[0.03] border-b border-border/10">
                          <td colSpan={99} className="px-4 py-2">
                            <div className="flex items-center gap-2 flex-wrap">
                              <span className="text-[9px] text-muted font-semibold uppercase">Fix segments:</span>
                              {(['gender', 'age_group', 'occasion', 'cost_tier', 'product_type', 'brand'] as const).map(field => {
                                const opts: Record<string, string[]> = {
                                  gender: ['Female', 'Male'],
                                  age_group: ['0-2 (Baby)', '2-4 (Toddler)', '5-9 (Kid)', '8-14', '10-12 (Tween)', '13-17 (Teen)', '18+ (Adult)'],
                                  occasion: ['Birthday', 'Christmas', 'Easter', 'Valentines', 'Graduation', 'Back to School', 'Performance', 'Get Well', 'Encouragement', 'Mothers Day', 'Fathers Day', 'Wedding', 'Sleepover', 'Camp', 'Sweet 16'],
                                  cost_tier: ['Budget (<$10)', 'Value ($10-$20)', 'Mid ($20-$35)', 'Premium ($35-$50)', 'Luxury ($50+)'],
                                  product_type: ['Social Game', 'Board Game', 'Bath & Spa', 'Beauty', 'Journal & Diary', 'Stationery', 'Books', 'Toys', 'Food & Treats', 'Clothing', 'Crafts & DIY', 'Accessories', 'Home & Room', 'Electronics', 'Party Supplies', 'Cards', 'Gift Sets', 'General'],
                                  brand: ['Happy Lolli', 'L.O.L Surprise', 'Disney', 'Barbie', 'Squishmallows', 'Sanrio', 'Pokemon', 'Taylor Swift', 'Minecraft', 'Roblox', 'Unicorn', 'Bluey', 'Gabbys Dollhouse', 'Paw Patrol', 'Harry Potter', 'LEGO', 'Hot Wheels', 'Bratz', 'Marvel', 'Star Wars', 'CoComelon', 'Peppa Pig'],
                                };
                                const label = field.replace('_', ' ');
                                return (
                                  <select
                                    key={field}
                                    value={editSegments[field] ?? ''}
                                    onChange={e => setEditSegments(prev => ({ ...prev, [field]: e.target.value || null }))}
                                    className="px-1.5 py-0.5 text-[9px] bg-white/[0.04] border border-border rounded text-heading"
                                  >
                                    <option value="">{label}</option>
                                    {opts[field].map(o => <option key={o} value={o}>{o}</option>)}
                                  </select>
                                );
                              })}
                              <button
                                disabled={savingSegment}
                                onClick={async () => {
                                  setSavingSegment(true);
                                  try {
                                    await onSaveSegments(row.query_text, editSegments);
                                    setEditingTerm(null);
                                  } catch (e) { console.error(e); }
                                  finally { setSavingSegment(false); }
                                }}
                                className="inline-flex items-center gap-1 px-2 py-0.5 text-[9px] font-bold bg-emerald-500/20 text-emerald-400 rounded hover:bg-emerald-500/30 transition-colors"
                              >
                                <Check size={9} /> Save
                              </button>
                              <button
                                onClick={() => setEditingTerm(null)}
                                className="px-2 py-0.5 text-[9px] text-muted hover:text-red-400 transition-colors"
                              >
                                Cancel
                              </button>
                            </div>
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  );
                })}
              </tbody>
              <tfoot>
                <tr className="border-t-2 border-border/40 bg-white/[0.03] font-semibold text-heading">
                  {/* Search Term → Week (18 cols): label */}
                  <td colSpan={18} className="px-2 py-2 pl-4 text-left text-[10px] uppercase tracking-wide text-muted sticky left-0 bg-surface/95 backdrop-blur z-10">
                    Total · {section.rows.length} terms
                  </td>
                  {/* Wk Vol. */}
                  <td className="px-2 py-2 text-right tabular-nums">{fShort(section.rows.reduce((s, r) => s + (r.weekly_market_impressions || 0), 0))}</td>
                  {/* Wk Purch. */}
                  <td className="px-2 py-2 text-right tabular-nums">{fmt(section.rows.reduce((s, r) => s + (r.weekly_market_purchases || 0), 0))}</td>
                  {/* Wk CVR% / Wk MD Purch / Wk MD Click — not summable */}
                  <td /><td /><td />
                  {/* Fam. Impr. */}
                  <td className="px-2 py-2 text-right tabular-nums">{fShort(section.rows.reduce((s, r) => s + (r.family_impressions || 0), 0))}</td>
                  {/* Fam. Purch. */}
                  <td className="px-2 py-2 text-right tabular-nums">{fmt(section.rows.reduce((s, r) => s + (r.family_purchases || 0), 0))}</td>
                  {/* Brand Impr. */}
                  <td className="px-2 py-2 text-right tabular-nums">{fShort(section.rows.reduce((s, r) => s + (r.brand_impressions || 0), 0))}</td>
                  {/* Brand Purch. */}
                  <td className="px-2 py-2 text-right tabular-nums">{fmt(section.rows.reduce((s, r) => s + (r.brand_purchases || 0), 0))}</td>
                  {/* Brand Show% → Est. $/Sale (10 cols): not summable */}
                  <td colSpan={10} />
                </tr>
              </tfoot>
            </table>
          </div>
        </div>
      ))}
      <Pagination scrollTop />
    </div>
  );
}
