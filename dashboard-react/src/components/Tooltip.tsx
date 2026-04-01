import { useState, useRef, useEffect, useCallback, useMemo } from 'react';
import { createPortal } from 'react-dom';

export function Tip({ text, children, multiline }: { text: string; children: React.ReactNode; multiline?: boolean }) {
  const [show, setShow] = useState(false);
  const [coords, setCoords] = useState({ x: 0, y: 0, above: true });
  const ref = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    if (show && ref.current) {
      const r = ref.current.getBoundingClientRect();
      setCoords({ x: r.left + r.width / 2, y: r.top < 60 ? r.bottom : r.top, above: r.top >= 60 });
    }
  }, [show]);

  return (
    <span ref={ref} className="relative inline-flex items-center gap-0.5 cursor-help"
      onMouseEnter={() => setShow(true)} onMouseLeave={() => setShow(false)}>
      {children}
      {show && createPortal(
        <span
          className={`fixed z-[9999] px-2.5 py-1.5 rounded-lg bg-card border border-border-strong text-[10px] text-muted leading-snug shadow-xl min-w-[160px] max-w-[280px] font-normal normal-case tracking-normal pointer-events-none ${multiline ? 'whitespace-pre-line' : 'whitespace-normal'}`}
          style={{
            left: coords.x,
            top: coords.above ? coords.y : coords.y + 6,
            transform: coords.above ? 'translate(-50%, -100%) translateY(-6px)' : 'translate(-50%, 0)',
          }}
        >
          {text}
        </span>,
        document.body
      )}
    </span>
  );
}

export function Th({ children, tip, right }: { children: React.ReactNode; tip?: string; right?: boolean }) {
  return (
    <th className={`bg-inset text-subtle ${right ? 'text-right' : 'text-left'} px-3 py-2.5 font-semibold text-[10px] uppercase tracking-wider border-b border-border whitespace-nowrap`}>
      {tip ? <Tip text={tip}>{children} <span className="text-faint text-[9px]">ⓘ</span></Tip> : children}
    </th>
  );
}

/* ─── Sortable table infrastructure ─── */

export type SortDir = 'asc' | 'desc' | null;
export interface SortState { key: string; dir: SortDir }

export function useSort(defaultKey?: string, defaultDir: SortDir = 'desc') {
  const [sort, setSort] = useState<SortState>({ key: defaultKey || '', dir: defaultKey ? defaultDir : null });

  const toggle = useCallback((key: string) => {
    setSort(prev => {
      if (prev.key !== key) return { key, dir: 'desc' };
      if (prev.dir === 'desc') return { key, dir: 'asc' };
      return { key: '', dir: null };
    });
  }, []);

  const sorted = useCallback(<T,>(rows: T[], accessor?: (row: T, key: string) => unknown): T[] => {
    if (!sort.key || !sort.dir) return rows;
    const get = accessor || ((r: T, k: string) => (r as Record<string, unknown>)[k]);
    return [...rows].sort((a, b) => {
      const va = get(a, sort.key);
      const vb = get(b, sort.key);
      if (va == null && vb == null) return 0;
      if (va == null) return 1;
      if (vb == null) return -1;
      const na = typeof va === 'number' ? va : typeof va === 'string' ? parseFloat(va) : NaN;
      const nb = typeof vb === 'number' ? vb : typeof vb === 'string' ? parseFloat(vb) : NaN;
      let cmp: number;
      if (!isNaN(na) && !isNaN(nb)) cmp = na - nb;
      else cmp = String(va).localeCompare(String(vb));
      return sort.dir === 'asc' ? cmp : -cmp;
    });
  }, [sort]);

  return useMemo(() => ({ sort, toggle, sorted }), [sort, toggle, sorted]);
}

const ARROW_UP = '↑';
const ARROW_DN = '↓';

export function SortTh({ k, sort, toggle, children, tip, right }: {
  k: string; sort: SortState; toggle: (k: string) => void;
  children: React.ReactNode; tip?: string; right?: boolean;
}) {
  const active = sort.key === k && sort.dir;
  const arrow = active ? (sort.dir === 'asc' ? ARROW_UP : ARROW_DN) : '';
  const inner = (
    <span className="inline-flex items-center gap-0.5">
      <button type="button" onClick={() => toggle(k)}
        className={`hover:text-white transition-colors select-none ${active ? 'text-blue-400' : ''}`}>
        {children}
        {arrow && <span className="text-[9px] ml-0.5 font-mono">{arrow}</span>}
      </button>
      {tip && <Tip text={tip}><span className="text-faint text-[9px] cursor-help">ⓘ</span></Tip>}
    </span>
  );
  return (
    <th className={`bg-inset text-subtle ${right ? 'text-right' : 'text-left'} px-3 py-2.5 font-semibold text-[10px] uppercase tracking-wider border-b border-border whitespace-nowrap cursor-pointer`}>
      {inner}
    </th>
  );
}

export const MEASURE_TIPS: Record<string, string> = {
  sales: 'Total revenue from all orders (Business)',
  ad_cost: 'Total advertising spend across all campaigns (Ads)',
  cogs: 'Cost of Goods Sold = units × (product cost + shipping + FBA fees) (Business)',
  net_profit: 'Sales − Ads Spend − COGS. True profit after all costs (Business)',
  net_roas: '(Sales − COGS) ÷ Ads Spend. Gross profit per unit of ad spend (Business)',
  ads_roas: 'Ads Sales ÷ Ads Spend (Ads)',
  gross_roas: 'Ads Sales ÷ Ads Spend (Ads)',
  ads_sales: 'Ad-attributed sales revenue (Ads)',
  orders: 'Total units ordered (ads + organic) (Business)',
  clicks: 'Ad clicks from Sponsored Products / Brands / Display (Ads)',
  sessions: 'Product page visits from all traffic sources (Business)',
  organic_pct: 'Organic orders ÷ Total orders × 100. Higher = less ads dependency (Business)',
  spend: 'Total ad spend (Ads)',
  ads_spend: 'Total ad spend (Ads)',
  ads_orders: 'Orders attributed to ads (Ads)',
  conv_rate: 'Ads Orders ÷ Ads Clicks × 100 (Ads)',
  cpc: 'Ads Spend ÷ Ads Clicks (Ads)',
  impressions: 'Ad impressions shown in search results (Ads)',
  impression_share: 'Your ad impressions ÷ Total market impressions (Ads)',
  market_volume: 'Estimated weekly orders for this keyword across all sellers (SQP)',
  margin_per_unit: 'Revenue per unit − COGS per unit. Profit per item sold (Business)',
  budget_util: 'Daily spend ÷ Daily budget. >90% means budget is capping performance (Ads)',
  organic_lift: 'Change in organic orders during experiment vs baseline period (SQP, Ads)',
  days_running: 'Calendar days since experiment start date (Ads)',
  show_rate: 'Your product appearance rate in search results for this keyword (SQP)',
  search_query_score: 'Composite relevance score from Amazon (SQP)',
  estimated_organic_rank: 'Page position from Show Rate %. P1 Top = top of page 1 (show rate >35%). Based on impression share vs Amazon total search volume (SQP)',
  sales_change: 'Percentage change in sales vs the previous period (prev week, prev month, or prev year depending on view)',
  sqp_ctr: 'Click-Through Rate: your clicks ÷ your impressions. Measures how desirable your product looks when shown in search results (SQP)',
  sqp_conv_rate: 'Conversion Rate: your orders ÷ your clicks. Measures how well your product converts after someone clicks (SQP)',
};
