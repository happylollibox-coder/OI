/**
 * CostsReportTab — self-loading costs table with inline COGS / shipping edit.
 * Replaces the Flask /costs-report HTML page inside the Supply page.
 */

import { useState, useEffect, useMemo, useCallback } from 'react';
import { Check, X, Search } from 'lucide-react';
import { dataEntry } from '../../utils/dataEntry';
import { fM } from '../../utils';

/* ─── Row shape from GET /api/costs-report ─── */
interface CostsRow {
  sku: string;
  asin: string;
  product_name: string;
  estimated_pick_pack_fee_per_unit: number | null;
  FBA_COST_estimated_referral_fee_per_unit: number | null;
  cost_of_goods: number | null;
  shipping_cost: number | null;
  TOTAL_COST_PER_UNIT: number | null;
  listing_price_amount: number | null;
}

function toRow(r: Record<string, unknown>): CostsRow {
  const num = (v: unknown) => (v == null ? null : Number(v));
  return {
    sku: String(r.sku ?? ''),
    asin: String(r.asin ?? ''),
    product_name: String(r.product_name ?? ''),
    estimated_pick_pack_fee_per_unit: num(r.estimated_pick_pack_fee_per_unit),
    FBA_COST_estimated_referral_fee_per_unit: num(r.FBA_COST_estimated_referral_fee_per_unit),
    cost_of_goods: num(r.cost_of_goods),
    shipping_cost: num(r.shipping_cost),
    TOTAL_COST_PER_UNIT: num(r.TOTAL_COST_PER_UNIT),
    listing_price_amount: num(r.listing_price_amount),
  };
}

/* ─── Inline editable number cell ─── */
interface InlineCostCellProps {
  asin: string;
  field: 'cogs' | 'shipping_cost';
  initialValue: number | null;
  onSaved: (asin: string, field: 'cogs' | 'shipping_cost', newTotal: number | null) => void;
}

function InlineCostCell({ asin, field, initialValue, onSaved }: InlineCostCellProps) {
  const [isEditing, setIsEditing] = useState(false);
  const [displayVal, setDisplayVal] = useState<number | null>(initialValue);
  const [inputVal, setInputVal] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /* Sync when parent row refreshes after a save */
  useEffect(() => {
    if (!isEditing) setDisplayVal(initialValue);
  }, [initialValue, isEditing]);

  const startEdit = useCallback(() => {
    setInputVal(displayVal != null ? String(displayVal) : '');
    setError(null);
    setIsEditing(true);
  }, [displayVal]);

  const cancel = useCallback(() => {
    setIsEditing(false);
    setError(null);
  }, []);

  const save = useCallback(async () => {
    const parsed = parseFloat(inputVal);
    if (Number.isNaN(parsed)) {
      setError('Enter a valid number');
      return;
    }
    const original = displayVal;
    if (parsed === original) { setIsEditing(false); return; }

    setSaving(true);
    setError(null);
    try {
      const body: { asin: string; shipping_cost?: number; cogs?: number } = { asin };
      if (field === 'cogs') body.cogs = parsed;
      else body.shipping_cost = parsed;

      await dataEntry.updateProductCosts(body);
      setDisplayVal(parsed);
      setIsEditing(false);
      onSaved(asin, field, null); // null → caller will refetch
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Save failed');
      setDisplayVal(original);
    } finally {
      setSaving(false);
    }
  }, [asin, field, inputVal, displayVal, onSaved]);

  if (isEditing) {
    return (
      <div className="flex flex-col items-end gap-0.5">
        <div className="flex items-center gap-1">
          <input
            type="number"
            step="0.01"
            value={inputVal}
            onChange={e => setInputVal(e.target.value)}
            className="w-20 bg-black/40 border border-border rounded px-1.5 py-0.5 text-xs text-right focus:outline-none focus:border-blue-500 font-mono"
            autoFocus
            onKeyDown={e => {
              if (e.key === 'Enter') void save();
              if (e.key === 'Escape') cancel();
            }}
            disabled={saving}
          />
          {saving ? (
            <div className="w-3 h-3 border-2 border-blue-500 border-t-transparent rounded-full animate-spin mx-1" />
          ) : (
            <>
              <button onClick={() => void save()} className="text-emerald-400 hover:text-emerald-300 p-0.5 bg-surface rounded" title="Save">
                <Check size={14} />
              </button>
              <button onClick={cancel} className="text-muted hover:text-red-400 p-0.5 bg-surface rounded" title="Cancel">
                <X size={14} />
              </button>
            </>
          )}
        </div>
        {error && <span className="text-[10px] text-red-400">{error}</span>}
      </div>
    );
  }

  return (
    <div
      className="group flex items-center justify-end min-w-[60px] min-h-[24px] rounded px-1 -mx-1 cursor-pointer hover:bg-white/5 transition-colors"
      onClick={startEdit}
      title="Click to edit"
    >
      <span className={displayVal != null ? 'text-blue-300 font-mono text-xs' : 'text-muted text-xs group-hover:text-subtle'}>
        {displayVal != null ? fM(displayVal) : '—'}
      </span>
    </div>
  );
}

/* ─── Column header ─── */
function Th({ children, right }: { children: React.ReactNode; right?: boolean }) {
  return (
    <th className={`px-4 py-2.5 text-xs font-semibold text-faint uppercase tracking-wider whitespace-nowrap ${right ? 'text-right' : 'text-left'}`}>
      {children}
    </th>
  );
}

/* ─── Main component ─── */
export function CostsReportTab() {
  const [rows, setRows] = useState<CostsRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');

  const loadRows = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const raw = await dataEntry.getCostsReport();
      setRows(raw.map(toRow));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load costs report');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void loadRows(); }, [loadRows]);

  /* After an inline edit succeeds, refetch to get server-recomputed TOTAL */
  const handleSaved = useCallback(() => {
    void loadRows();
  }, [loadRows]);

  const filtered = useMemo(() => {
    if (!search.trim()) return rows;
    const q = search.toLowerCase();
    return rows.filter(r =>
      r.sku.toLowerCase().includes(q) ||
      r.product_name.toLowerCase().includes(q) ||
      r.asin.toLowerCase().includes(q),
    );
  }, [rows, search]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20 text-muted text-sm gap-2">
        <div className="w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" />
        Loading costs report…
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex flex-col items-center justify-center py-20 gap-3">
        <p className="text-red-400 text-sm">{error}</p>
        <button
          onClick={() => void loadRows()}
          className="px-3 py-1.5 bg-surface border border-border rounded text-xs text-subtle hover:text-heading transition-colors"
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {/* Search */}
      <div className="flex items-center gap-2">
        <div className="relative flex-1 max-w-xs">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-faint pointer-events-none" />
          <input
            type="text"
            placeholder="Filter by SKU, product, ASIN…"
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full pl-7 pr-3 py-1.5 bg-surface border border-border rounded text-xs text-subtle placeholder-faint focus:outline-none focus:ring-1 focus:ring-blue-500/50"
          />
          {search && (
            <button
              onClick={() => setSearch('')}
              className="absolute right-2 top-1/2 -translate-y-1/2 text-faint hover:text-red-400 transition-colors"
            >
              <X size={12} />
            </button>
          )}
        </div>
        <span className="text-xs text-faint">{filtered.length} of {rows.length}</span>
      </div>

      {/* Table */}
      <div className="rounded-xl border border-border overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border bg-surface/50">
              <Th>SKU</Th>
              <Th>Product</Th>
              <Th>ASIN</Th>
              <Th right>Pick/Pack</Th>
              <Th right>Referral Fee</Th>
              <Th right>COGS ✎</Th>
              <Th right>Shipping ✎</Th>
              <Th right>Total Cost/Unit</Th>
              <Th right>Listing Price</Th>
              <Th right>Margin</Th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 && (
              <tr>
                <td colSpan={10} className="px-4 py-8 text-center text-muted text-sm">
                  No products match your filter
                </td>
              </tr>
            )}
            {filtered.map(r => {
              const margin =
                r.listing_price_amount != null && r.TOTAL_COST_PER_UNIT != null
                  ? r.listing_price_amount - r.TOTAL_COST_PER_UNIT
                  : null;
              const marginColor =
                margin == null
                  ? 'text-muted'
                  : margin >= 0
                    ? 'text-emerald-400'
                    : 'text-red-400';

              return (
                <tr key={r.asin} className="border-b border-border/50 hover:bg-white/[.02] transition-colors">
                  <td className="px-4 py-2.5 text-xs font-mono text-subtle whitespace-nowrap">{r.sku || '—'}</td>
                  <td className="px-4 py-2.5 text-xs text-subtle font-medium max-w-[220px] truncate" title={r.product_name}>
                    {r.product_name || '—'}
                  </td>
                  <td className="px-4 py-2.5 text-xs font-mono text-faint whitespace-nowrap">{r.asin || '—'}</td>
                  <td className="px-4 py-2.5 text-right text-xs font-mono text-subtle">
                    {r.estimated_pick_pack_fee_per_unit != null ? fM(r.estimated_pick_pack_fee_per_unit) : '—'}
                  </td>
                  <td className="px-4 py-2.5 text-right text-xs font-mono text-subtle">
                    {r.FBA_COST_estimated_referral_fee_per_unit != null ? fM(r.FBA_COST_estimated_referral_fee_per_unit) : '—'}
                  </td>
                  <td className="px-4 py-2.5 text-right">
                    <InlineCostCell
                      asin={r.asin}
                      field="cogs"
                      initialValue={r.cost_of_goods}
                      onSaved={handleSaved}
                    />
                  </td>
                  <td className="px-4 py-2.5 text-right">
                    <InlineCostCell
                      asin={r.asin}
                      field="shipping_cost"
                      initialValue={r.shipping_cost}
                      onSaved={handleSaved}
                    />
                  </td>
                  <td className="px-4 py-2.5 text-right text-xs font-mono font-semibold text-heading">
                    {r.TOTAL_COST_PER_UNIT != null ? fM(r.TOTAL_COST_PER_UNIT) : '—'}
                  </td>
                  <td className="px-4 py-2.5 text-right text-xs font-mono text-subtle">
                    {r.listing_price_amount != null ? fM(r.listing_price_amount) : '—'}
                  </td>
                  <td className={`px-4 py-2.5 text-right text-xs font-mono font-semibold ${marginColor}`}>
                    {margin != null ? fM(margin) : '—'}
                  </td>
                </tr>
              );
            })}
          </tbody>
          {filtered.length > 0 && (
            <tfoot>
              <tr className="border-t border-border bg-surface/30">
                <td colSpan={3} className="px-4 py-2.5 text-xs font-semibold text-faint uppercase">
                  {filtered.length} products
                </td>
                <td colSpan={7} />
              </tr>
            </tfoot>
          )}
        </table>
      </div>
    </div>
  );
}
