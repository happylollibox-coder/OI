import React, { useState } from 'react';
import { Section } from './Section';
import { Th, SortTh, useSort } from './Tooltip';
import { MeasureSelector, useMeasureSelection, type MeasureDef } from './MeasureSelector';
import { RoasBadge } from './Badge';
import { ChevronRight, ChevronDown } from 'lucide-react';
import { fM, fP, fOrd, fClk, fCpc } from '../utils';
import type { SqpTermAgg } from '../utils/sqpTermTable';

const COLUMNS: MeasureDef[] = [
  { id: 'term', label: 'Keyword', group: 'Info' },
  { id: 'market_vol', label: 'Mkt Vol', tip: 'Market search-impression volume (AMAZON_IMPRESSIONS), summed across the weeks shown', group: 'SQP' },
  { id: 'impressions', label: 'Impr', group: 'SQP' },
  { id: 'impr_share', label: 'Impr Share%', tip: 'Your impressions ÷ market impressions', group: 'SQP' },
  { id: 'clicks', label: 'Clicks', group: 'SQP' },
  { id: 'ctr', label: 'CTR%', group: 'SQP' },
  { id: 'cart_adds', label: 'Cart Adds', group: 'SQP' },
  { id: 'orders', label: 'Orders', group: 'SQP' },
  { id: 'cvr', label: 'CVR%', group: 'SQP' },
  { id: 'organic_orders', label: 'Organic Ord', group: 'SQP' },
  { id: 'ad_spend', label: 'Ad Spend', group: 'Ads' },
  { id: 'ad_sales', label: 'Ad Sales', group: 'Ads' },
  { id: 'cpc', label: 'CPC', group: 'Ads' },
  { id: 'net_roas', label: 'Net ROAS', tip: 'Ad gross profit (sales − COGS) ÷ ad spend', group: 'Ads' },
  { id: 'est_rank', label: 'Est Rank', group: 'SQP' },
  { id: 'zone', label: 'Zone', group: 'SQP' },
];

const ZONE_LABELS: Record<string, string> = {
  upper_p1: 'P1 Top', mid_p1: 'P1 Mid', lower_p1: 'P1 Low', bottom_p1: 'P1 Bot', page_2_plus: 'P2+',
};

export function SqpTermsPanel({ terms, filterItems }: { terms: SqpTermAgg[]; filterItems?: string[] }) {
  const [cols, setCols] = useMeasureSelection('sqp_terms', COLUMNS);
  const sort = useSort('market_vol');
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const visible = COLUMNS.filter(c => cols.has(c.id));
  const toggle = (t: string) => setExpanded(p => { const n = new Set(p); n.has(t) ? n.delete(t) : n.add(t); return n; });
  const num = (n: number) => Math.round(n).toLocaleString();
  const pctCell = (v: number | null) => (v == null ? '--' : fP(v));

  return (
    <Section
      title="Search Terms"
      count={`${terms.length} terms`}
      filterItems={filterItems}
      headerRight={
        <MeasureSelector
          tableId="sqp_terms"
          measures={COLUMNS}
          selected={cols}
          onSelectedChange={setCols}
        />
      }
    >
      <div className="border border-border rounded-xl bg-card overflow-hidden">
        <table className="w-full border-collapse text-xs">
          <thead><tr>
            <Th> </Th>
            {visible.map(c => (
              <SortTh key={c.id} k={c.id} sort={sort.sort} toggle={sort.toggle} right={c.id !== 'term' && c.id !== 'zone'} tip={c.tip}>{c.label}</SortTh>
            ))}
          </tr></thead>
          <tbody>
            {sort.sorted(terms).map((t) => {
              const isExp = expanded.has(t.term);
              const cells: Record<string, React.ReactNode> = {
                term: <td key="term" className="px-3 py-2 font-semibold text-blue-400">{t.term}</td>,
                market_vol: <td key="market_vol" className="px-3 py-2 text-right font-mono text-[11px]">{num(t.market_vol)}</td>,
                impressions: <td key="impressions" className="px-3 py-2 text-right font-mono text-[11px]">{num(t.impressions)}</td>,
                impr_share: <td key="impr_share" className="px-3 py-2 text-right font-mono text-[11px]">{pctCell(t.impr_share)}</td>,
                clicks: <td key="clicks" className="px-3 py-2 text-right">{fClk(t.clicks)}</td>,
                ctr: <td key="ctr" className="px-3 py-2 text-right">{pctCell(t.ctr)}</td>,
                cart_adds: <td key="cart_adds" className="px-3 py-2 text-right font-mono text-[11px]">{num(t.cart_adds)}</td>,
                orders: <td key="orders" className="px-3 py-2 text-right">{fOrd(t.orders)}</td>,
                cvr: <td key="cvr" className="px-3 py-2 text-right">{pctCell(t.cvr)}</td>,
                organic_orders: <td key="organic_orders" className="px-3 py-2 text-right">{fOrd(t.organic_orders)}</td>,
                ad_spend: <td key="ad_spend" className="px-3 py-2 text-right font-mono text-[11px]">{fM(t.ad_spend)}</td>,
                ad_sales: <td key="ad_sales" className="px-3 py-2 text-right font-mono text-[11px]">{fM(t.ad_sales)}</td>,
                cpc: <td key="cpc" className="px-3 py-2 text-right font-mono text-[11px]">{t.cpc == null ? '--' : fCpc(t.cpc)}</td>,
                net_roas: <td key="net_roas" className="px-3 py-2"><RoasBadge value={t.net_roas} /></td>,
                est_rank: <td key="est_rank" className="px-3 py-2 text-right font-mono text-[11px]">{t.est_rank == null ? '--' : Math.round(t.est_rank)}</td>,
                zone: <td key="zone" className="px-3 py-2 text-[11px]">{t.zone ? (ZONE_LABELS[t.zone] || t.zone) : '--'}</td>,
              };
              return (
                <React.Fragment key={t.term}>
                  <tr onClick={() => toggle(t.term)} className="border-b border-border-faint hover:bg-white/[.02] cursor-pointer transition-colors">
                    <td className="px-3 py-2 w-6">{isExp ? <ChevronDown size={12} className="text-faint" /> : <ChevronRight size={12} className="text-faint" />}</td>
                    {visible.map(c => cells[c.id])}
                  </tr>
                  {isExp && (
                    <tr>
                      <td colSpan={visible.length + 1} className="p-0">
                        <div className="bg-inset px-4 py-3 border-b border-border-faint">
                          <div className="text-[10px] text-faint uppercase font-semibold mb-2 tracking-wider">Per-ASIN / week breakdown</div>
                          <table className="w-full text-[11px]">
                            <thead><tr className="text-subtle">
                              <th className="text-left py-1 px-2 font-semibold">Week</th>
                              <th className="text-left py-1 px-2 font-semibold">Product</th>
                              <th className="text-right py-1 px-2 font-semibold">Impr</th>
                              <th className="text-right py-1 px-2 font-semibold">Mkt Vol</th>
                              <th className="text-right py-1 px-2 font-semibold">Clicks</th>
                              <th className="text-right py-1 px-2 font-semibold">Orders</th>
                              <th className="text-right py-1 px-2 font-semibold">Ad Spend</th>
                              <th className="text-right py-1 px-2 font-semibold">Rank</th>
                            </tr></thead>
                            <tbody>
                              {t.rows.slice().sort((a, b) => b.reporting_date.localeCompare(a.reporting_date))
                                .map((e, ei) => (
                                <tr key={ei} className="border-t border-border-faint">
                                  <td className="py-1 px-2 font-mono text-[10px]">{e.reporting_date}</td>
                                  <td className="py-1 px-2">{e.product_short_name || e.asin}</td>
                                  <td className="py-1 px-2 text-right font-mono">{(e.impressions || 0).toLocaleString()}</td>
                                  <td className="py-1 px-2 text-right font-mono">{(e.amazon_impressions || 0).toLocaleString()}</td>
                                  <td className="py-1 px-2 text-right">{fClk(e.clicks)}</td>
                                  <td className="py-1 px-2 text-right">{fOrd(e.orders)}</td>
                                  <td className="py-1 px-2 text-right font-mono">{fM(e.ad_spend)}</td>
                                  <td className="py-1 px-2 text-right font-mono">{e.estimated_organic_rank == null ? '--' : Math.round(e.estimated_organic_rank)}</td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  )}
                </React.Fragment>
              );
            })}
          </tbody>
        </table>
      </div>
    </Section>
  );
}
