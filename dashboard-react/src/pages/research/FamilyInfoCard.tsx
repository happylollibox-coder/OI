import { useState } from 'react';
import type { FamilyInfo, SegmentReason, SegmentReasoning } from './types';
import { apiFetch } from '../../utils/apiFetch';

interface FamilyInfoCardProps {
  familyInfo: FamilyInfo;
  selectedProduct: string;
  segmentReasoning: SegmentReasoning | null;
  onRefreshFamily: () => Promise<void>;
}

const segDefs = [
  { key: 'gender', label: 'Gender', color: 'pink', dbKey: 'seg_gender' },
  { key: 'age_group', label: 'Age', color: 'cyan', dbKey: 'seg_age_group' },
  { key: 'occasion', label: 'Occasion', color: 'amber', dbKey: 'seg_occasion' },
  { key: 'product_type', label: 'Product Type', color: 'violet', dbKey: 'seg_product_type' },
] as const;

const colorMap: Record<string, string> = {
  pink: 'bg-pink-500/10 text-pink-400',
  cyan: 'bg-cyan-500/10 text-cyan-400',
  amber: 'bg-amber-500/10 text-amber-400',
  violet: 'bg-violet-500/10 text-violet-400',
};
const colorBorder: Record<string, string> = {
  pink: 'border-pink-500/30',
  cyan: 'border-cyan-500/30',
  amber: 'border-amber-500/30',
  violet: 'border-violet-500/30',
};

export function FamilyInfoCard({ familyInfo, selectedProduct, segmentReasoning, onRefreshFamily }: FamilyInfoCardProps) {
  const [showPerProduct, setShowPerProduct] = useState(false);
  const segs = familyInfo.summary.segments || {};

  const postSegments = async (body: Record<string, string | null>) => {
    await apiFetch('/api/research/product-segments', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ parent_name: selectedProduct, ...body }),
    });
    await onRefreshFamily();
  };

  const removeSegValue = (dbKey: string, currentCsv: string, valueToRemove: string) => {
    const newValues = currentCsv.split(',').map(v => v.trim()).filter(v => v !== valueToRemove);
    return postSegments({ [dbKey]: newValues.join(',') || null });
  };

  const addSegValue = (dbKey: string, currentCsv: string | null, newValue: string) => {
    const existing = currentCsv ? currentCsv.split(',').map(v => v.trim()) : [];
    if (existing.includes(newValue) || !newValue.trim()) return Promise.resolve();
    existing.push(newValue.trim());
    return postSegments({ [dbKey]: existing.join(',') });
  };

  return (
    <div className="mb-4 border border-border/30 rounded-lg overflow-hidden bg-white/[0.01]">
      {/* Parent summary row */}
      <div className="flex items-center gap-3 px-4 py-2.5 bg-white/[0.02] border-b border-border/20">
        <div className="flex-1">
          <span className="text-sm font-bold text-heading">{familyInfo.summary.parent_name}</span>
          <span className="ml-2 text-[10px] text-muted">
            {familyInfo.summary.product_count} products · Amazon: {familyInfo.summary.product_types.join(', ')}
          </span>
        </div>
        <div className="flex items-center gap-2 text-[10px] tabular-nums">
          <span className="text-heading font-semibold text-xs">
            {familyInfo.summary.min_price === familyInfo.summary.max_price
              ? `$${familyInfo.summary.avg_price}`
              : `$${familyInfo.summary.min_price}–$${familyInfo.summary.max_price}`}
          </span>
          {familyInfo.summary.avg_total_cost != null && (
            <span className="text-red-400/80 font-medium"
              title={`COGS: $${familyInfo.summary.avg_cogs ?? '?'} · Referral: $${familyInfo.summary.avg_referral_fee ?? '?'} · FBA: $${familyInfo.summary.avg_fba_fee ?? '?'} · Shipping: $${familyInfo.summary.avg_shipping_cost ?? '?'}`}
            >
              − ${familyInfo.summary.avg_total_cost} costs
            </span>
          )}
          {familyInfo.summary.gross_profit_per_unit != null && (
            <span className="text-emerald-400 font-semibold" title="Gross Profit per Unit (Revenue before Ads)">
              = ${familyInfo.summary.gross_profit_per_unit} GP
            </span>
          )}
        </div>
      </div>

      {/* Editable Segments */}
      <div className="px-4 py-3 space-y-2 border-b border-border/10">
        {segDefs.map(sd => {
          const val = segs[sd.key as keyof typeof segs] as string | null;
          const items = val ? val.split(',').map(v => v.trim()) : [];
          const reasoning: SegmentReason[] = (segmentReasoning || {})[sd.key] || [];
          return (
            <div key={sd.key} className="flex items-center gap-2 text-[10px]">
              <span className="text-muted font-medium w-[80px] shrink-0">{sd.label}:</span>
              <div className="flex flex-wrap items-center gap-1">
                {items.map(v => {
                  const reasonItem = reasoning.find(r => r.value === v);
                  return (
                    <span
                      key={v}
                      className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[8px] font-medium ${colorMap[sd.color]} group`}
                      title={reasonItem ? `${reasonItem.pct}% of purchases (${reasonItem.orders} orders) · ${reasonItem.clicks_per_sale ?? '?'} clicks/sale` : 'Manually set'}
                    >
                      {v}
                      {reasonItem && <span className="text-[7px] opacity-60">{reasonItem.pct}%</span>}
                      <button
                        onClick={() => removeSegValue(sd.dbKey, val || '', v)}
                        className="opacity-0 group-hover:opacity-100 transition-opacity hover:text-red-400 ml-0.5"
                      >×</button>
                    </span>
                  );
                })}
                {/* Add button */}
                <input
                  type="text"
                  placeholder="+"
                  className={`w-[60px] px-1 py-0.5 text-[8px] bg-transparent border ${colorBorder[sd.color]} rounded text-muted placeholder:text-center focus:w-[120px] focus:placeholder:text-left transition-all outline-none`}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      const input = e.currentTarget;
                      addSegValue(sd.dbKey, val, input.value);
                      input.value = '';
                    }
                  }}
                  onBlur={(e) => {
                    if (e.target.value.trim()) {
                      addSegValue(sd.dbKey, val, e.target.value);
                      e.target.value = '';
                    }
                  }}
                />
              </div>
              {/* Reasoning: show uncaptured values from ad data */}
              {reasoning.filter(r => !items.includes(r.value)).length > 0 && (
                <div className="flex items-center gap-1 ml-2">
                  <span className="text-[7px] text-muted">also in ads:</span>
                  {reasoning
                    .filter(r => !items.includes(r.value))
                    .map(r => (
                      <button
                        key={r.value}
                        onClick={() => addSegValue(sd.dbKey, val, r.value)}
                        className={`px-1 py-0 rounded text-[7px] opacity-40 hover:opacity-100 border border-dashed ${colorBorder[sd.color]} transition-opacity`}
                        title={`${r.pct}% of purchases (${r.orders} orders) · ${r.clicks_per_sale ?? '?'} clicks/sale — click to add`}
                      >
                        +{r.value} ({r.pct}%)
                      </button>
                    ))}
                </div>
              )}
            </div>
          );
        })}
        <div className="flex items-center gap-2 pt-1">
          <button
            onClick={async () => {
              try {
                await apiFetch('/api/research/derive-segments', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ parent_name: selectedProduct, force: true }),
                });
                await onRefreshFamily();
              } catch (e) { console.error(e); }
            }}
            className="px-2 py-0.5 text-[8px] text-blue-400 hover:bg-blue-500/10 rounded border border-blue-500/20 transition-colors"
            title="Re-derive segments from ad purchase data"
          >
            🤖 Auto-derive
          </button>
          <span className="text-[7px] text-muted">Hover badges to see purchase % · Type in + field to add manually</span>
        </div>
      </div>

      {/* Per-product segments (collapsible) */}
      <div className="border-t border-border/10">
        <button
          onClick={() => setShowPerProduct(!showPerProduct)}
          className="w-full flex items-center gap-2 px-4 py-2 text-[9px] text-muted hover:text-subtle transition-colors cursor-pointer"
        >
          <span className={`transition-transform ${showPerProduct ? 'rotate-90' : ''}`}>▶</span>
          Per Product ({familyInfo.products.length})
        </button>
        {showPerProduct && (
          <div className="px-4 pb-2">
            <table className="w-full text-[10px]">
              <thead>
                <tr className="border-b border-border/20">
                  <th className="py-1 text-left text-[8px] text-muted font-semibold uppercase tracking-wide">Product</th>
                  <th className="py-1 text-right text-[8px] text-muted font-semibold uppercase tracking-wide w-14">Price</th>
                  {segDefs.map(sd => (
                    <th key={sd.key} className="py-1 text-left text-[8px] text-muted font-semibold uppercase tracking-wide pl-3">{sd.label}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {familyInfo.products.map(p => {
                  const pSegs = p.segments || {};
                  const parentSegs = segs;

                  const addProductSeg = (dbKey: string, currentCsv: string | null, newValue: string) => {
                    const existing = currentCsv ? currentCsv.split(',').map(v => v.trim()) : [];
                    if (existing.includes(newValue) || !newValue.trim()) return Promise.resolve();
                    existing.push(newValue.trim());
                    return postSegments({ asin: p.asin, [dbKey]: existing.join(',') });
                  };

                  const removeProductSeg = (dbKey: string, currentCsv: string, valueToRemove: string) => {
                    const newValues = currentCsv.split(',').map(v => v.trim()).filter(v => v !== valueToRemove);
                    return postSegments({ asin: p.asin, [dbKey]: newValues.join(',') || null });
                  };

                  return (
                    <tr key={p.asin} className="border-b border-border/5 hover:bg-white/[0.02]">
                      <td className="py-1.5 text-heading font-medium truncate max-w-[160px]" title={`${p.asin} · ${p.product_type}`}>
                        {p.product_short_name}
                      </td>
                      <td className="py-1.5 text-right text-muted tabular-nums">{p.current_price ? `$${p.current_price}` : '—'}</td>
                      {segDefs.map(sd => {
                        const pVal = pSegs[sd.key as keyof typeof pSegs] as string | null;
                        const parentVal = parentSegs[sd.key as keyof typeof parentSegs] as string | null;
                        const pItems = pVal ? pVal.split(',').map(v => v.trim()) : [];
                        const parentItems = parentVal ? parentVal.split(',').map(v => v.trim()) : [];
                        // Show only values unique to this product (not in parent) OR show all if they differ
                        const isDifferent = pVal !== parentVal;
                        const displayItems = isDifferent ? pItems : [];

                        // Per-ASIN reasoning suggestions
                        const byAsin = segmentReasoning?.by_asin || {};
                        const asinReasoning: SegmentReason[] = byAsin[p.asin]?.[sd.key] || [];
                        const uncaptured = asinReasoning.filter(r => !pItems.includes(r.value));

                        return (
                          <td key={sd.key} className="py-1.5 pl-3">
                            <div className="flex flex-wrap items-center gap-0.5">
                              {!isDifferent && pItems.length > 0 && (
                                <span className="text-[7px] text-muted italic">= parent</span>
                              )}
                              {displayItems.map(v => {
                                const isExtra = !parentItems.includes(v);
                                const reasonItem = asinReasoning.find(r => r.value === v);
                                return (
                                  <span
                                    key={v}
                                    className={`inline-flex items-center gap-0.5 px-1 py-0 rounded text-[7px] font-medium ${colorMap[sd.color]} group ${isExtra ? 'ring-1 ring-white/10' : ''}`}
                                    title={reasonItem
                                      ? `${reasonItem.pct}% of this product's orders (${reasonItem.orders}) · ${reasonItem.clicks_per_sale ?? '?'} clicks/sale`
                                      : isExtra ? 'Product-specific (manually set)' : 'Same as parent'}
                                  >
                                    {v}
                                    {reasonItem && <span className="text-[6px] opacity-50">{reasonItem.pct}%</span>}
                                    <button
                                      onClick={() => removeProductSeg(sd.dbKey, pVal || '', v)}
                                      className="opacity-0 group-hover:opacity-100 transition-opacity hover:text-red-400"
                                    >×</button>
                                  </span>
                                );
                              })}
                              {/* Per-ASIN suggestions */}
                              {uncaptured.length > 0 && (
                                <>
                                  {uncaptured.map(r => (
                                    <button
                                      key={r.value}
                                      onClick={() => addProductSeg(sd.dbKey, pVal, r.value)}
                                      className={`px-0.5 py-0 rounded text-[6px] opacity-30 hover:opacity-100 border border-dashed ${colorBorder[sd.color]} transition-opacity`}
                                      title={`${r.pct}% of this product's orders (${r.orders}) · ${r.clicks_per_sale ?? '?'} clicks/sale — click to add`}
                                    >
                                      +{r.value} {r.pct}%
                                    </button>
                                  ))}
                                </>
                              )}
                              <input
                                type="text"
                                placeholder="+"
                                className={`w-[40px] px-0.5 py-0 text-[7px] bg-transparent border ${colorBorder[sd.color]} rounded text-muted placeholder:text-center focus:w-[80px] transition-all outline-none`}
                                onKeyDown={(e) => {
                                  if (e.key === 'Enter') {
                                    addProductSeg(sd.dbKey, pVal, e.currentTarget.value);
                                    e.currentTarget.value = '';
                                  }
                                }}
                                onBlur={(e) => {
                                  if (e.target.value.trim()) {
                                    addProductSeg(sd.dbKey, pVal, e.target.value);
                                    e.target.value = '';
                                  }
                                }}
                              />
                            </div>
                          </td>
                        );
                      })}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
