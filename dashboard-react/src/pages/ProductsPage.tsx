import { useState, useEffect, useMemo, Fragment } from 'react';
import { Rocket, Save, AlertCircle, CheckCircle, RefreshCw, Database, Calculator, DollarSign, Percent, TrendingUp, Target, Zap, ChevronDown, ChevronUp, Layers, X, Plus } from 'lucide-react';
import { useUnifiedData } from '../hooks/useUnifiedData';
import type { DashboardData } from '../types';
import { apiFetch } from '../utils/apiFetch';

// --- Margin Presets ---
const MARGIN_PRESETS = [
  { id: 'low', label: 'Low Revenue', pct: 15, description: 'Volume play — competitive pricing', color: 'amber' },
  { id: 'standard', label: 'Standard', pct: 25, description: 'Healthy sustainable margin', color: 'green' },
  { id: 'high', label: 'High Revenue', pct: 35, description: 'Premium brand positioning', color: 'purple' },
] as const;

// --- Default estimates for costs that may not have product-specific data ---
const DEFAULT_STORAGE_PER_UNIT = 0.20;       // $0.20/unit/month avg across catalog
const DEFAULT_AWD_TO_FBA_PER_UNIT = 0.30;    // AWD → FBA inbound transport estimate
const DEFAULT_REFUND_RATE_PCT = 3;            // ~3% of price lost to refunds/returns

function PriceCalculator({ data, selectedProduct }: { data: DashboardData; selectedProduct: string }) {
  const [showAdvanced, setShowAdvanced] = useState(false);
  
  // Core costs
  const [cogs, setCogs] = useState<string>('');
  const [shipping, setShipping] = useState<string>('');
  const [pickPack, setPickPack] = useState<string>('');
  const [referralPct, setReferralPct] = useState<string>('15');
  
  // Additional costs
  const [storageCost, setStorageCost] = useState<string>(String(DEFAULT_STORAGE_PER_UNIT));
  const [awdToFba, setAwdToFba] = useState<string>(String(DEFAULT_AWD_TO_FBA_PER_UNIT));
  const [refundPct, setRefundPct] = useState<string>(String(DEFAULT_REFUND_RATE_PCT));
  
  // Margin
  const [marginPreset, setMarginPreset] = useState<string>('standard');
  const [targetMarginPct, setTargetMarginPct] = useState<string>('25');

  // Bill of Materials — build COGS from component prices at volume tiers
  const [showBom, setShowBom] = useState(false);
  const [bomTiers, setBomTiers] = useState<string[]>(['500', '1000', '3000']);
  const [bomActiveTier, setBomActiveTier] = useState<number>(1); // index into bomTiers
  const [bomRows, setBomRows] = useState<{ id: string; name: string; prices: string[] }[]>([]);

  const [bomSaving, setBomSaving] = useState(false);
  const [bomSaved, setBomSaved] = useState(false);

  const addBomRow = () => setBomRows(r => [...r, { id: crypto.randomUUID(), name: '', prices: bomTiers.map(() => '') }]);
  const updateBomRow = (id: string, patch: Partial<{ name: string; prices: string[] }>) =>
    setBomRows(r => r.map(row => row.id === id ? { ...row, ...patch } : row));
  const removeBomRow = (id: string) => setBomRows(r => r.filter(row => row.id !== id));

  // Load the saved per-product BOM when a product is selected (server-backed, per ASIN)
  useEffect(() => {
    if (!selectedProduct) { setBomRows([]); return; }
    let cancelled = false;
    (async () => {
      try {
        const res = await apiFetch(`/api/products/bom?asin=${encodeURIComponent(selectedProduct)}`);
        if (!res.ok) return;
        const d = await res.json();
        if (cancelled) return;
        if (d.bom_json) {
          const parsed = JSON.parse(d.bom_json);
          if (Array.isArray(parsed.tiers) && parsed.tiers.length) setBomTiers(parsed.tiers.map(String));
          setBomActiveTier(typeof parsed.activeTier === 'number' ? parsed.activeTier : 1);
          setBomRows((parsed.components || []).map((c: { name?: string; prices?: number[] }) =>
            ({ id: crypto.randomUUID(), name: c.name || '', prices: (c.prices || []).map(String) })));
        } else {
          setBomRows([]); // no saved BOM for this product
        }
      } catch { /* ignore */ }
    })();
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedProduct]);

  const saveBom = async () => {
    if (!selectedProduct) return;
    setBomSaving(true);
    try {
      const bom_json = JSON.stringify({
        tiers: bomTiers.map(t => parseFloat(t) || 0),
        activeTier: bomActiveTier,
        components: bomRows.map(r => ({ name: r.name, prices: r.prices.map(p => parseFloat(p) || 0) })),
      });
      const res = await apiFetch('/api/products/bom', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ asin: selectedProduct, bom_json }),
      });
      if (res.ok) { setBomSaved(true); setTimeout(() => setBomSaved(false), 3000); }
    } catch { /* ignore */ }
    finally { setBomSaving(false); }
  };

  // Handle product selection to auto-fill defaults
  useEffect(() => {
    if (selectedProduct) {
      const prod = data.products?.find(p => p.asin === selectedProduct);
      if (prod) {
        setCogs(String(prod.cogs || 0));
        setShipping(String(prod.shipping_cost || 0));
        setPickPack(String(prod.pick_pack_fee || 0));
      }
    } else {
      setCogs('');
      setShipping('');
      setPickPack('');
    }
    // Only re-fill when the SELECTED product changes — not on every `data` refresh,
    // which would otherwise wipe a manually-entered or BOM-applied COGS.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedProduct]);
  
  // Handle margin preset selection
  const handlePresetClick = (presetId: string, pct: number) => {
    setMarginPreset(presetId);
    setTargetMarginPct(String(pct));
  };
  
  const handleMarginManualChange = (val: string) => {
    setTargetMarginPct(val);
    setMarginPreset('custom');
  };

  // Parsed values
  const pCogs = parseFloat(cogs) || 0;
  const pShip = parseFloat(shipping) || 0;
  const pPick = parseFloat(pickPack) || 0;
  const pRefPct = parseFloat(referralPct) || 0;
  const pStorage = parseFloat(storageCost) || 0;
  const pAwdFba = parseFloat(awdToFba) || 0;
  const pRefundPct = parseFloat(refundPct) || 0;
  const pMargin = parseFloat(targetMarginPct) || 0;

  // Total fixed cost (everything except referral and refund — those are % of price)
  const fixedCosts = pCogs + pShip + pPick + pStorage + pAwdFba;
  
  // Calculate recommended price:
  // Price = FixedCosts / (1 - ReferralPct/100 - RefundPct/100 - TargetMargin/100)
  const denominator = 1 - (pRefPct / 100) - (pRefundPct / 100) - (pMargin / 100);
  const recommendedPrice = denominator > 0 ? fixedCosts / denominator : 0;
  
  // Derived values at recommended price
  const referralFee = (recommendedPrice * pRefPct) / 100;
  const refundCost = (recommendedPrice * pRefundPct) / 100;
  const totalCosts = fixedCosts + referralFee + refundCost;
  const netProfit = recommendedPrice - totalCosts;
  const actualMargin = recommendedPrice > 0 ? (netProfit / recommendedPrice) * 100 : 0;
  const breakevenRoas = netProfit > 0 ? recommendedPrice / netProfit : 0;

  // Net margin at the product's CURRENT listing price (same cost model), for comparison
  const currentPrice = selectedProduct
    ? (data.products?.find(p => p.asin === selectedProduct)?.listing_price ?? null)
    : null;
  const curReferralFee = currentPrice ? (currentPrice * pRefPct) / 100 : 0;
  const curRefundCost = currentPrice ? (currentPrice * pRefundPct) / 100 : 0;
  const curNetProfit = currentPrice ? currentPrice - (fixedCosts + curReferralFee + curRefundCost) : 0;
  const curMargin = currentPrice && currentPrice > 0 ? (curNetProfit / currentPrice) * 100 : 0;

  // BOM totals: per-tier sum of component prices (per-unit), + order total at the active tier
  const bomTierTotals = bomTiers.map((_, ti) => bomRows.reduce((s, row) => s + (parseFloat(row.prices[ti]) || 0), 0));
  const bomPerUnit = bomTierTotals[bomActiveTier] || 0;
  const bomActiveQty = parseFloat(bomTiers[bomActiveTier]) || 0;
  const bomOrderTotal = bomPerUnit * bomActiveQty;

  // Cost breakdown for visual
  const costItems = [
    { label: 'COGS', value: pCogs, color: 'bg-blue-500' },
    { label: 'Shipping', value: pShip, color: 'bg-cyan-500' },
    { label: 'Pick & Pack', value: pPick, color: 'bg-indigo-500' },
    { label: 'Referral Fee', value: referralFee, color: 'bg-orange-500' },
    { label: 'Storage', value: pStorage, color: 'bg-teal-500' },
    { label: 'AWD→FBA', value: pAwdFba, color: 'bg-sky-500' },
    { label: 'Refunds', value: refundCost, color: 'bg-red-400' },
  ];

  return (
    <div className="bg-[var(--color-bg-elevated)] border border-[var(--color-border)] rounded-xl p-5 shadow-sm mb-8">
      <h3 className="font-semibold text-lg flex items-center gap-2 mb-5">
        <Calculator className="w-5 h-5 text-green-500" />
        Price Calculator
        <span className="text-xs font-normal text-[var(--color-text-muted)] ml-1">Costs + Margin → Recommended Price</span>
      </h3>
      
      <div className="flex flex-col lg:flex-row gap-6">
        {/* LEFT: Inputs */}
        <div className="flex-1 space-y-5">

          {/* Margin Presets */}
          <div>
            <label className="block text-xs font-medium text-[var(--color-text-secondary)] mb-2 uppercase tracking-wider">
              Target Net Margin
            </label>
            <div className="grid grid-cols-3 gap-2 mb-2">
              {MARGIN_PRESETS.map(p => (
                <button
                  key={p.id}
                  onClick={() => handlePresetClick(p.id, p.pct)}
                  className={`flex flex-col items-center gap-0.5 p-2.5 rounded-lg border text-xs transition-all ${
                    marginPreset === p.id
                      ? `border-${p.color}-500 bg-${p.color}-500/10 ring-1 ring-${p.color}-500/30`
                      : 'border-[var(--color-border)] bg-[var(--color-bg-primary)] hover:border-[var(--color-text-muted)]'
                  }`}
                >
                  <span className={`font-bold text-base ${marginPreset === p.id ? `text-${p.color}-500` : 'text-[var(--color-text)]'}`}>
                    {p.pct}%
                  </span>
                  <span className={`font-medium ${marginPreset === p.id ? `text-${p.color}-400` : 'text-[var(--color-text-secondary)]'}`}>
                    {p.label}
                  </span>
                </button>
              ))}
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs text-[var(--color-text-muted)]">Custom:</span>
              <div className="relative flex-1">
                <input type="number" step="1" min="0" max="80"
                  className={`w-full bg-[var(--color-bg-primary)] border text-sm rounded-lg pl-3 pr-7 py-1.5 focus:outline-none transition-colors ${
                    marginPreset === 'custom' ? 'border-emerald-500 ring-1 ring-emerald-500/30' : 'border-[var(--color-border)]'
                  }`}
                  value={targetMarginPct} onChange={e => handleMarginManualChange(e.target.value)} />
                <span className="absolute right-3 top-1.5 text-[var(--color-text-secondary)] text-sm">%</span>
              </div>
            </div>
          </div>

          {/* Core Costs */}
          <div>
            <label className="block text-xs font-medium text-[var(--color-text-secondary)] mb-2 uppercase tracking-wider">
              Core Product Costs
            </label>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              <CostInput label="COGS" value={cogs} onChange={setCogs} prefix="$" />
              <CostInput label="Shipping (MFR→US)" value={shipping} onChange={setShipping} prefix="$" />
              <CostInput label="Pick & Pack (FBA)" value={pickPack} onChange={setPickPack} prefix="$" />
              <CostInput label="Referral Fee" value={referralPct} onChange={setReferralPct} suffix="%" />
            </div>
          </div>

          {/* Bill of Materials (collapsible) — build COGS from component prices per volume tier */}
          <div>
            <button
              onClick={() => setShowBom(!showBom)}
              className="flex items-center gap-1 text-xs font-medium text-[var(--color-text-secondary)] uppercase tracking-wider hover:text-[var(--color-text)] transition-colors mb-2"
            >
              {showBom ? <ChevronUp className="w-3.5 h-3.5" /> : <ChevronDown className="w-3.5 h-3.5" />}
              <Layers className="w-3.5 h-3.5" />
              Bill of Materials
              <span className="text-[var(--color-text-muted)] normal-case ml-1">(build COGS from components)</span>
              {bomRows.length > 0 && <span className="text-green-500 normal-case ml-1 font-mono">· ${bomPerUnit.toFixed(2)}/unit @ {bomActiveQty}</span>}
            </button>
            {showBom && (
              <div className="animate-in slide-in-from-top-1 duration-200 border border-[var(--color-border)] rounded-lg p-3 bg-[var(--color-bg-primary)]">
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="text-[var(--color-text-muted)]">
                        <th className="text-left font-medium pb-1.5 pr-2">Component</th>
                        {bomTiers.map((qty, ti) => (
                          <th key={ti} className="pb-1.5 px-1 text-center">
                            <div className="text-[9px] uppercase tracking-wider mb-0.5">units</div>
                            <input type="number" min="0" value={qty}
                              onChange={e => setBomTiers(t => t.map((v, i) => i === ti ? e.target.value : v))}
                              className={`w-16 bg-[var(--color-bg-elevated)] border rounded px-1 py-1 text-center text-xs focus:outline-none ${bomActiveTier === ti ? 'border-green-500' : 'border-[var(--color-border)]'}`} />
                          </th>
                        ))}
                        <th className="w-6" />
                      </tr>
                    </thead>
                    <tbody>
                      {bomRows.map(row => (
                        <tr key={row.id}>
                          <td className="pr-2 py-0.5">
                            <input value={row.name} placeholder="e.g. Bunny Doll"
                              onChange={e => updateBomRow(row.id, { name: e.target.value })}
                              className="w-full min-w-[90px] bg-[var(--color-bg-elevated)] border border-[var(--color-border)] rounded px-2 py-1 text-xs focus:outline-none focus:border-green-500" />
                          </td>
                          {bomTiers.map((_, ti) => (
                            <td key={ti} className="px-1 py-0.5">
                              <div className="relative">
                                <span className="absolute left-1.5 top-1 text-[var(--color-text-muted)] text-[10px]">$</span>
                                <input type="number" step="0.01" value={row.prices[ti] ?? ''} placeholder="0"
                                  onChange={e => updateBomRow(row.id, { prices: row.prices.map((p, i) => i === ti ? e.target.value : p) })}
                                  className={`w-16 bg-[var(--color-bg-elevated)] border rounded pl-4 pr-1 py-1 text-center text-xs focus:outline-none ${bomActiveTier === ti ? 'border-green-500/50' : 'border-[var(--color-border)]'}`} />
                              </div>
                            </td>
                          ))}
                          <td className="py-0.5 text-center">
                            <button onClick={() => removeBomRow(row.id)} className="text-[var(--color-text-muted)] hover:text-red-500" title="Remove">
                              <X className="w-3.5 h-3.5" />
                            </button>
                          </td>
                        </tr>
                      ))}
                      {/* Totals row — click a tier's total to pick the active volume */}
                      <tr className="border-t border-[var(--color-border)]">
                        <td className="pt-1.5 pr-2 text-[var(--color-text-secondary)] font-semibold">Total /unit</td>
                        {bomTierTotals.map((tot, ti) => (
                          <td key={ti} className="pt-1.5 px-1 text-center">
                            <button onClick={() => setBomActiveTier(ti)} title="Use this volume"
                              className={`w-16 rounded px-1 py-0.5 font-mono font-semibold border ${bomActiveTier === ti ? 'border-green-500 bg-green-500/10 text-green-500' : 'border-transparent text-[var(--color-text-secondary)] hover:border-[var(--color-border)]'}`}>
                              ${tot.toFixed(2)}
                            </button>
                          </td>
                        ))}
                        <td />
                      </tr>
                    </tbody>
                  </table>
                </div>
                <div className="flex items-center justify-between mt-2 gap-2 flex-wrap">
                  <div className="flex items-center gap-3">
                    <button onClick={addBomRow} className="flex items-center gap-1 text-xs text-green-500 hover:text-green-400 font-medium">
                      <Plus className="w-3.5 h-3.5" /> Add component
                    </button>
                    {selectedProduct ? (
                      <button onClick={saveBom} disabled={bomSaving}
                        className={`flex items-center gap-1 text-xs px-2.5 py-1 rounded-lg font-medium transition-colors ${
                          bomSaved ? 'bg-green-500/15 text-green-400 border border-green-500/40'
                          : 'border border-[var(--color-border)] text-[var(--color-text-secondary)] hover:bg-[var(--color-bg-elevated)]'}`}>
                        <Save className="w-3.5 h-3.5" />
                        {bomSaving ? 'Saving…' : bomSaved ? 'Saved ✓' : 'Save BOM'}
                      </button>
                    ) : (
                      <span className="text-[10px] text-[var(--color-text-muted)]">Load a product to save its BOM</span>
                    )}
                  </div>
                  {bomRows.length > 0 && (
                    <div className="flex items-center gap-3 text-xs">
                      <span className="text-[var(--color-text-muted)]">
                        At <span className="text-[var(--color-text)] font-medium">{bomActiveQty}</span> units:{' '}
                        <span className="text-[var(--color-text)] font-mono font-semibold">${bomPerUnit.toFixed(2)}</span>/unit ·{' '}
                        <span className="text-[var(--color-text)] font-mono">${bomOrderTotal.toFixed(2)}</span> total
                      </span>
                      <button onClick={() => setCogs(String(Math.round(bomPerUnit * 1e4) / 1e4))}
                        className="bg-green-500 hover:bg-green-600 text-white px-2.5 py-1 rounded-lg text-xs font-medium whitespace-nowrap">
                        Use as COGS →
                      </button>
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>

          {/* Additional Costs (collapsible) */}
          <div>
            <button
              onClick={() => setShowAdvanced(!showAdvanced)}
              className="flex items-center gap-1 text-xs font-medium text-[var(--color-text-secondary)] uppercase tracking-wider hover:text-[var(--color-text)] transition-colors mb-2"
            >
              {showAdvanced ? <ChevronUp className="w-3.5 h-3.5" /> : <ChevronDown className="w-3.5 h-3.5" />}
              Additional Costs
              <span className="text-[var(--color-text-muted)] normal-case ml-1">(Storage, AWD→FBA, Refunds)</span>
            </button>
            {showAdvanced && (
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 animate-in slide-in-from-top-1 duration-200">
                <CostInput label="FBA Storage /unit" value={storageCost} onChange={setStorageCost} prefix="$" hint="Monthly avg" />
                <CostInput label="AWD → FBA Transport" value={awdToFba} onChange={setAwdToFba} prefix="$" hint="Per unit" />
                <CostInput label="Refund Loss" value={refundPct} onChange={setRefundPct} suffix="%" hint="% of price" />
              </div>
            )}
          </div>
        </div>

        {/* RIGHT: Output */}
        <div className="w-full lg:w-72 flex flex-col gap-3">
          {/* Main output: Recommended Price */}
          <div className="bg-gradient-to-br from-green-500/10 to-emerald-500/5 border border-green-500/20 rounded-xl p-5 text-center">
            <div className="text-xs text-green-400 uppercase tracking-widest font-semibold mb-1">Recommended Price</div>
            <div className="text-4xl font-extrabold text-green-500 tracking-tight">
              ${recommendedPrice > 0 ? recommendedPrice.toFixed(2) : '—'}
            </div>
            <div className="text-xs text-[var(--color-text-muted)] mt-1">
              at {actualMargin.toFixed(1)}% net margin
            </div>
          </div>

          {/* Current Price + net margin at that price (loaded product only) */}
          {currentPrice != null && currentPrice > 0 && (
            <div className="bg-[var(--color-bg-primary)] border border-[var(--color-border)] rounded-xl p-4 text-center">
              <div className="text-xs text-[var(--color-text-muted)] uppercase tracking-widest font-semibold mb-1">Current Price</div>
              <div className="text-2xl font-bold text-[var(--color-text)] tracking-tight">${currentPrice.toFixed(2)}</div>
              <div className={`text-xs mt-1 font-medium ${curMargin >= pMargin ? 'text-green-500' : curMargin >= 0 ? 'text-amber-500' : 'text-red-500'}`}>
                at {curMargin.toFixed(1)}% net margin · ${curNetProfit.toFixed(2)}/unit
              </div>
            </div>
          )}

          {/* Net Profit */}
          <div className="bg-[var(--color-bg-primary)] border border-[var(--color-border)] rounded-lg p-3 flex items-center justify-between px-4">
            <div className="text-xs text-[var(--color-text-secondary)] uppercase tracking-wider font-medium">
              Net Profit
            </div>
            <div className={`text-lg font-bold ${netProfit > 0 ? 'text-green-500' : 'text-red-500'}`}>
              ${netProfit > 0 ? netProfit.toFixed(2) : '0.00'}
            </div>
          </div>

          {/* Break-Even ROAS */}
          <div className="bg-[var(--color-bg-primary)] border border-[var(--color-border)] rounded-lg p-3 flex items-center justify-between px-4">
            <div className="text-xs text-[var(--color-text-secondary)] uppercase tracking-wider font-medium text-left leading-tight">
              Break-Even<br/>ROAS
            </div>
            <div className="text-lg font-bold text-[var(--color-text)]">
              {breakevenRoas > 0 ? breakevenRoas.toFixed(2) : '—'}
            </div>
          </div>

          {/* Cost Breakdown Bar */}
          {recommendedPrice > 0 && (
            <div className="bg-[var(--color-bg-primary)] border border-[var(--color-border)] rounded-lg p-3">
              <div className="text-xs text-[var(--color-text-secondary)] uppercase tracking-wider font-medium mb-2">Cost Breakdown</div>
              <div className="flex rounded-full overflow-hidden h-2.5 mb-2">
                {costItems.filter(c => c.value > 0).map(c => (
                  <div key={c.label} className={`${c.color} transition-all`} style={{ width: `${(c.value / recommendedPrice) * 100}%` }} title={`${c.label}: $${c.value.toFixed(2)}`} />
                ))}
                <div className="bg-green-500" style={{ width: `${(netProfit / recommendedPrice) * 100}%` }} title={`Profit: $${netProfit.toFixed(2)}`} />
              </div>
              <div className="grid grid-cols-2 gap-x-3 gap-y-0.5 text-[10px]">
                {costItems.filter(c => c.value > 0.005).map(c => (
                  <div key={c.label} className="flex items-center justify-between">
                    <div className="flex items-center gap-1">
                      <span className={`w-1.5 h-1.5 rounded-full ${c.color}`} />
                      <span className="text-[var(--color-text-muted)]">{c.label}</span>
                    </div>
                    <span className="text-[var(--color-text-secondary)] font-mono">${c.value.toFixed(2)}</span>
                  </div>
                ))}
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-1">
                    <span className="w-1.5 h-1.5 rounded-full bg-green-500" />
                    <span className="text-green-400 font-medium">Profit</span>
                  </div>
                  <span className="text-green-500 font-mono font-medium">${netProfit.toFixed(2)}</span>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/** Tiny reusable cost input field */
function CostInput({ label, value, onChange, prefix, suffix, hint }: {
  label: string; value: string; onChange: (v: string) => void; prefix?: string; suffix?: string; hint?: string;
}) {
  return (
    <div>
      <label className="block text-[10px] font-medium text-[var(--color-text-muted)] mb-0.5 uppercase tracking-wider">{label}</label>
      <div className="relative">
        {prefix && <span className="absolute left-2.5 top-[7px] text-[var(--color-text-secondary)] text-xs">{prefix}</span>}
        <input type="number" step="0.01"
          className={`w-full bg-[var(--color-bg-primary)] border border-[var(--color-border)] text-sm rounded-lg ${prefix ? 'pl-6' : 'pl-3'} ${suffix ? 'pr-6' : 'pr-3'} py-1.5 focus:outline-none focus:border-green-500 transition-colors`}
          value={value} onChange={e => onChange(e.target.value)} placeholder="0" />
        {suffix && <span className="absolute right-2.5 top-[7px] text-[var(--color-text-secondary)] text-xs">{suffix}</span>}
      </div>
      {hint && <span className="text-[9px] text-[var(--color-text-muted)]">{hint}</span>}
    </div>
  );
}

// Family-level bulk-editable fields. Each maps 1:1 to a manually-managed DIM_PRODUCT
// column that SP_MERGE_PRODUCT_DIM preserves. Cu.Ft is intentionally excluded — it is
// computed in the Cube from package L×W×H, not from a directly-editable column.
type BulkFieldKind = 'int' | 'percent' | 'bool';
const BULK_FIELDS: { key: string; label: string; kind: BulkFieldKind }[] = [
  { key: 'package_quantity', label: 'Pkg Qty', kind: 'int' },
  { key: 'manufacture_day', label: 'Mfr Days', kind: 'int' },
  { key: 'shipment_days', label: 'Ship Days', kind: 'int' },
  { key: 'manuf_upfront_percentage', label: 'Upfront %', kind: 'percent' },
  { key: 'share_carton_in_family', label: 'Shared', kind: 'bool' },
];

function ProductAttributesTable({ data }: { data: DashboardData }) {
  const [editingAsin, setEditingAsin] = useState<string | null>(null);
  const [editValues, setEditValues] = useState<{cogs: string, shipping: string}>({cogs: '', shipping: ''});
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<{text: string, type: 'success'|'error'} | null>(null);

  // --- Family bulk edit ---
  const [selectedFamilies, setSelectedFamilies] = useState<Set<string>>(new Set());
  const [bulkField, setBulkField] = useState<string>('package_quantity');
  const [bulkValue, setBulkValue] = useState<string>('');
  const [bulkSaving, setBulkSaving] = useState(false);

  const toggleFamily = (name: string) => {
    setSelectedFamilies(prev => {
      const next = new Set(prev);
      if (next.has(name)) next.delete(name); else next.add(name);
      return next;
    });
  };

  // Group products by parent (family_name from Cube, or parent_name, with product_type fallback)
  const parentGroups = useMemo(() => {
    if (!data.products) return [];
    const grouped: Record<string, { parent_asin: string; parent_name: string; products: any[] }> = {};
    data.products.forEach(p => {
      const key = p.parent_name || p.family_name || p.product_type || 'Uncategorized';
      if (!grouped[key]) {
        grouped[key] = {
          parent_asin: p.parent_asin || '',
          parent_name: key,
          products: [],
        };
      }
      grouped[key].products.push(p);
    });
    return Object.values(grouped).sort((a, b) => b.products.length - a.products.length);
  }, [data.products]);

  // ASINs across all checked families (empty ASINs dropped)
  const selectedAsins = useMemo(() => {
    return parentGroups
      .filter(g => selectedFamilies.has(g.parent_name))
      .flatMap(g => g.products.map((p: any) => p.asin))
      .filter(Boolean);
  }, [parentGroups, selectedFamilies]);

  const activeBulkField = BULK_FIELDS.find(f => f.key === bulkField)!;

  const handleBulkApply = async () => {
    if (selectedAsins.length === 0) {
      setMessage({ text: 'No products in the selected families', type: 'error' });
      return;
    }
    // Parse & validate the value per field kind
    let value: number | boolean;
    if (activeBulkField.kind === 'bool') {
      if (bulkValue !== 'true' && bulkValue !== 'false') {
        setMessage({ text: 'Pick Yes or No', type: 'error' });
        return;
      }
      value = bulkValue === 'true';
    } else {
      const n = activeBulkField.kind === 'percent' ? parseFloat(bulkValue) : parseInt(bulkValue, 10);
      if (isNaN(n)) {
        setMessage({ text: `Enter a valid ${activeBulkField.label} value`, type: 'error' });
        return;
      }
      // Upfront % is entered as a percent in the UI but stored as a fraction
      value = activeBulkField.kind === 'percent' ? n / 100 : n;
    }

    setBulkSaving(true);
    setMessage(null);
    try {
      const res = await apiFetch('/api/products/bulk-update-attributes', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ asins: selectedAsins, field: activeBulkField.key, value }),
      });
      const json = await res.json();
      if (json.success) {
        setMessage({
          text: `Updated ${activeBulkField.label} on ${selectedAsins.length} product${selectedAsins.length === 1 ? '' : 's'}. Refreshing data...`,
          type: 'success',
        });
        setSelectedFamilies(new Set());
        setTimeout(() => window.location.reload(), 1500);
      } else {
        setMessage({ text: json.error || 'Bulk update failed', type: 'error' });
      }
    } catch (e) {
      setMessage({ text: 'Network error during bulk update', type: 'error' });
    }
    setBulkSaving(false);
  };

  const handleEdit = (p: any) => {
    setEditingAsin(p.asin);
    setEditValues({
      cogs: String(p.cogs || 0),
      shipping: String(p.shipping_cost || 0)
    });
  };

  const handleSave = async (asin: string) => {
    setSaving(true);
    setMessage(null);
    try {
      const res = await apiFetch('/api/products/update-costs', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          asin,
          cogs: parseFloat(editValues.cogs),
          shipping_cost: parseFloat(editValues.shipping)
        })
      });
      const json = await res.json();
      if (json.success) {
        setMessage({ text: 'Updated successfully! Refreshing data...', type: 'success' });
        setEditingAsin(null);
        setTimeout(() => window.location.reload(), 1500);
      } else {
        setMessage({ text: json.error || 'Failed to update', type: 'error' });
      }
    } catch (e) {
      setMessage({ text: 'Network error updating costs', type: 'error' });
    }
    setSaving(false);
  };

  return (
    <div className="mb-6 bg-card/50 rounded-2xl border border-[var(--color-border)] p-4 shadow-sm backdrop-blur-md">
      <h2 className="text-xl font-semibold mb-4 text-[var(--color-text)] flex items-center">
        <Database className="mr-2 h-5 w-5 text-blue-500" />
        Product Costs Database
      </h2>
      
      {message && (
        <div className={`p-3 rounded-xl mb-4 text-sm font-medium ${message.type === 'success' ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
          {message.text}
        </div>
      )}

      <p className="text-xs text-[var(--color-text-muted)] mb-3">
        Tip: check one or more families below to bulk-set a shared attribute (e.g. Pkg Qty) across every product in them.
      </p>

      {selectedFamilies.size > 0 && (
        <div className="mb-4 flex flex-wrap items-end gap-3 rounded-xl border border-blue-500/30 bg-blue-500/5 p-3">
          <div className="flex items-center gap-2 text-sm font-medium text-[var(--color-text)]">
            <Layers className="h-4 w-4 text-blue-500" />
            {selectedFamilies.size} {selectedFamilies.size === 1 ? 'family' : 'families'}
            <span className="text-[var(--color-text-muted)] font-normal">
              ({selectedAsins.length} product{selectedAsins.length === 1 ? '' : 's'})
            </span>
          </div>

          <div className="flex flex-col gap-1">
            <label className="text-[10px] uppercase tracking-wider text-[var(--color-text-muted)]">Field</label>
            <select
              className="bg-[var(--color-bg-primary)] border border-[var(--color-border)] text-sm rounded-lg px-3 py-1.5 focus:outline-none focus:border-blue-500"
              value={bulkField}
              onChange={e => { setBulkField(e.target.value); setBulkValue(''); }}
            >
              {BULK_FIELDS.map(f => <option key={f.key} value={f.key}>{f.label}</option>)}
            </select>
          </div>

          <div className="flex flex-col gap-1">
            <label className="text-[10px] uppercase tracking-wider text-[var(--color-text-muted)]">New value</label>
            {activeBulkField.kind === 'bool' ? (
              <select
                className="bg-[var(--color-bg-primary)] border border-[var(--color-border)] text-sm rounded-lg px-3 py-1.5 focus:outline-none focus:border-blue-500"
                value={bulkValue}
                onChange={e => setBulkValue(e.target.value)}
              >
                <option value="">--</option>
                <option value="true">Yes</option>
                <option value="false">No</option>
              </select>
            ) : (
              <div className="relative">
                <input
                  type="number"
                  step={activeBulkField.kind === 'percent' ? '1' : '1'}
                  min="0"
                  className={`w-28 bg-[var(--color-bg-primary)] border border-[var(--color-border)] text-sm rounded-lg px-3 py-1.5 ${activeBulkField.kind === 'percent' ? 'pr-7' : ''} focus:outline-none focus:border-blue-500`}
                  value={bulkValue}
                  onChange={e => setBulkValue(e.target.value)}
                  placeholder={activeBulkField.label}
                />
                {activeBulkField.kind === 'percent' && (
                  <span className="absolute right-3 top-1.5 text-[var(--color-text-muted)] text-sm">%</span>
                )}
              </div>
            )}
          </div>

          <button
            onClick={handleBulkApply}
            disabled={bulkSaving || bulkValue === ''}
            className="flex items-center gap-1 px-3 py-1.5 text-sm bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:opacity-50"
          >
            {bulkSaving ? 'Applying...' : <><Save size={14} /> Apply to {selectedAsins.length}</>}
          </button>

          <button
            onClick={() => setSelectedFamilies(new Set())}
            className="flex items-center gap-1 px-2 py-1.5 text-sm text-[var(--color-text-muted)] hover:text-[var(--color-text)]"
          >
            <X size={14} /> Clear
          </button>
        </div>
      )}

      <div className="overflow-x-auto">
        <table className="w-full text-sm text-left">
          <thead className="text-xs uppercase bg-[var(--color-surface)]/50 text-[var(--color-text-muted)] border-b border-[var(--color-border)]">
            <tr>
              <th className="px-4 py-3 rounded-tl-lg">Product</th>
              <th className="px-4 py-3">ASIN</th>
              <th className="px-4 py-3 text-right">Listing $</th>
              <th className="px-4 py-3 text-right">COGS</th>
              <th className="px-4 py-3 text-right">Shipping</th>
              <th className="px-4 py-3 text-center" title="Manufacturing lead time">Mfr Days</th>
              <th className="px-4 py-3 text-center" title="Shipping transit time">Ship Days</th>
              <th className="px-4 py-3 text-center" title="Units per manufacturer shipping carton">Pkg Qty</th>
              <th className="px-4 py-3 text-center" title="Cubic feet per unit">Cu.Ft</th>
              <th className="px-4 py-3 text-center" title="Manufacturer upfront payment percentage">Upfront %</th>
              <th className="px-4 py-3 text-center" title="Can share cartons with other products in same family">Shared</th>
              <th className="px-4 py-3 text-right rounded-tr-lg">Action</th>
            </tr>
          </thead>
          <tbody>
            {parentGroups.map(group => (
              <Fragment key={group.parent_name}>
                {/* Parent Row */}
                <tr className="bg-[var(--color-surface)]/80 border-b border-[var(--color-border)]">
                  <td colSpan={12} className="px-4 py-2">
                    <div className="flex items-center gap-2">
                      <input
                        type="checkbox"
                        className="h-4 w-4 rounded border-[var(--color-border)] accent-blue-500 cursor-pointer"
                        checked={selectedFamilies.has(group.parent_name)}
                        onChange={() => toggleFamily(group.parent_name)}
                        title={`Select ${group.parent_name} for bulk edit`}
                      />
                      <span className="font-bold text-[var(--color-text)]">{group.parent_name}</span>
                      {group.parent_asin && (
                        <span className="text-xs font-mono text-[var(--color-text-muted)] bg-[var(--color-bg-primary)] px-2 py-0.5 rounded border border-[var(--color-border)]">
                          {group.parent_asin}
                        </span>
                      )}
                      <span className="text-xs text-[var(--color-text-muted)]">
                        {group.products.length} {group.products.length === 1 ? 'variation' : 'variations'}
                      </span>
                    </div>
                  </td>
                </tr>
                {/* Product Rows */}
                {group.products.map(p => (
                  <tr key={p.asin} className="border-b border-[var(--color-border)] hover:bg-[var(--color-surface)]/30 transition-colors">
                    <td className="px-4 py-3 font-medium text-[var(--color-text)] pl-8">
                      {p.product_short_name}
                    </td>
                    <td className="px-4 py-3 text-[var(--color-text-muted)] font-mono text-xs">
                      {p.asin}
                    </td>
                    
                    {/* Listing Price */}
                    <td className="px-4 py-3 text-right text-[var(--color-text)]">
                      {p.listing_price != null ? `$${Number(p.listing_price).toFixed(2)}` : <span className="text-[var(--color-text-muted)]">—</span>}
                    </td>
                    
                    {/* COGS */}
                    <td className="px-4 py-3 text-right text-[var(--color-text)]">
                      {editingAsin === p.asin ? (
                        <input
                          type="number"
                          step="0.01"
                          className="w-20 px-2 py-1 bg-[var(--color-bg-primary)] border border-[var(--color-border)] rounded text-sm text-[var(--color-text)] focus:ring-1 focus:ring-blue-500 focus:outline-none"
                          value={editValues.cogs}
                          onChange={e => setEditValues({...editValues, cogs: e.target.value})}
                        />
                      ) : (
                        `$${Number(p.cogs || 0).toFixed(2)}`
                      )}
                    </td>
                    
                    {/* Shipping */}
                    <td className="px-4 py-3 text-right text-[var(--color-text)]">
                      {editingAsin === p.asin ? (
                        <input
                          type="number"
                          step="0.01"
                          className="w-20 px-2 py-1 bg-[var(--color-bg-primary)] border border-[var(--color-border)] rounded text-sm text-[var(--color-text)] focus:ring-1 focus:ring-blue-500 focus:outline-none ml-auto"
                          value={editValues.shipping}
                          onChange={e => setEditValues({...editValues, shipping: e.target.value})}
                        />
                      ) : (
                        `$${Number(p.shipping_cost || 0).toFixed(2)}`
                      )}
                    </td>
                    
                    {/* Manufacture Days */}
                    <td className="px-4 py-3 text-center text-[var(--color-text)]">
                      {p.manufacture_day != null ? p.manufacture_day : <span className="text-[var(--color-text-muted)]">—</span>}
                    </td>
                    
                    {/* Shipment Days */}
                    <td className="px-4 py-3 text-center text-[var(--color-text)]">
                      {p.shipment_days != null ? p.shipment_days : <span className="text-[var(--color-text-muted)]">—</span>}
                    </td>
                    
                    {/* Package Quantity */}
                    <td className="px-4 py-3 text-center text-[var(--color-text)]">
                      {p.package_quantity != null ? p.package_quantity : <span className="text-[var(--color-text-muted)]">—</span>}
                    </td>
                    
                    {/* Package Cubic Feet */}
                    <td className="px-4 py-3 text-center text-[var(--color-text)] font-mono text-xs">
                      {p.package_cubic_feet != null ? p.package_cubic_feet.toFixed(3) : <span className="text-[var(--color-text-muted)]">—</span>}
                    </td>
                    
                    {/* Manuf Upfront % */}
                    <td className="px-4 py-3 text-center text-[var(--color-text)]">
                      {p.manuf_upfront_percentage != null ? (
                        <span className={`inline-flex px-1.5 py-0.5 rounded text-xs font-medium ${
                          p.manuf_upfront_percentage >= 0.4 ? 'bg-amber-500/10 text-amber-500' : 'bg-blue-500/10 text-blue-400'
                        }`}>
                          {Math.round(p.manuf_upfront_percentage * 100)}%
                        </span>
                      ) : <span className="text-[var(--color-text-muted)]">—</span>}
                    </td>
                    
                    {/* Share Carton */}
                    <td className="px-4 py-3 text-center">
                      {p.share_carton_in_family != null ? (
                        p.share_carton_in_family 
                          ? <span className="text-green-500 text-xs font-medium">✓</span> 
                          : <span className="text-red-400 text-xs font-medium">✗</span>
                      ) : <span className="text-[var(--color-text-muted)]">—</span>}
                    </td>
                    
                    {/* Action */}
                    <td className="px-4 py-3 text-right">
                      {editingAsin === p.asin ? (
                        <div className="flex justify-end gap-2">
                          <button 
                            onClick={() => setEditingAsin(null)}
                            className="px-2 py-1 text-xs text-[var(--color-text-muted)] hover:text-[var(--color-text)]"
                          >
                            Cancel
                          </button>
                          <button 
                            onClick={() => handleSave(p.asin)}
                            disabled={saving}
                            className="px-2 py-1 text-xs bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50 flex items-center"
                          >
                            {saving ? 'Saving...' : <><Save size={12} className="mr-1" /> Save</>}
                          </button>
                        </div>
                      ) : (
                        <button 
                          onClick={() => handleEdit(p)}
                          className="text-blue-500 hover:text-blue-600 text-sm font-medium"
                        >
                          Edit
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </Fragment>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export function ProductsPage({ data }: { data: DashboardData }) {
  const [models, setModels] = useState<Record<string, string>>({});
  const [availableModels, setAvailableModels] = useState<{product: string, daily_rate: number}[]>([]);
  const [newProductsByFamily, setNewProductsByFamily] = useState<Record<string, any[]>>({});
  
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [triggering, setTriggering] = useState(false);
  const [message, setMessage] = useState<{ text: string; type: 'success' | 'error' } | null>(null);

  const fetchAssignments = async () => {
    setLoading(true);
    try {
      const res = await apiFetch('/api/launch_models');
      if (res.ok) {
        const json = await res.json();
        if (json.success) {
          const map: Record<string, string> = {};
          json.models.forEach((m: any) => {
            map[m.family] = m.model_product;
          });
          setModels(map);
          
          const newProds: Record<string, any[]> = {};
          const available: {product: string, daily_rate: number}[] = [];
          
          json.products.forEach((p: any) => {
            if (p.is_new_product || p.is_draft) {
              if (!newProds[p.family]) newProds[p.family] = [];
              newProds[p.family].push(p);
            } else if (p.daily_rate > 0) {
              available.push({ product: p.product, daily_rate: p.daily_rate });
            }
          });
          
          setNewProductsByFamily(newProds);
          setAvailableModels(available.sort((a, b) => b.daily_rate - a.daily_rate));
        }
      }
    } catch (e) {
      console.error('Error fetching launch models', e);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchAssignments();
  }, []);

  const handleSave = async (family: string, model_product: string) => {
    setSaving(true);
    setMessage(null);
    try {
      const res = await apiFetch('/api/launch_models', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ family, model_product })
      });
      const json = await res.json();
      if (json.success) {
        setMessage({ text: `Saved ${family} model: ${model_product}`, type: 'success' });
        setModels(prev => ({ ...prev, [family]: model_product }));
      } else {
        setMessage({ text: json.error || 'Failed to save', type: 'error' });
      }
    } catch (e) {
      setMessage({ text: 'Network error saving model', type: 'error' });
    }
    setSaving(false);
  };

  const handleTriggerForecast = async () => {
    setTriggering(true);
    setMessage(null);
    try {
      const res = await apiFetch('/api/trigger_forecast', {
        method: 'POST',
      });
      const json = await res.json();
      if (json.success) {
        setMessage({ text: 'Forecast generated successfully in BigQuery.', type: 'success' });
      } else {
        setMessage({ text: json.error || 'Failed to generate forecast', type: 'error' });
      }
    } catch (e) {
      setMessage({ text: 'Network error triggering forecast', type: 'error' });
    }
    setTriggering(false);
  };

  return (
    <div className="space-y-6 max-w-5xl mx-auto">
      {/* 1. Main Title */}
      <div className="mb-6">
        <h1 className="text-3xl font-bold tracking-tight text-[var(--color-text)]">Products</h1>
        <p className="text-[var(--color-text-muted)] mt-1">Manage product catalog, edit attributes, and model pricing profitability.</p>
      </div>

      {/* 2. Calculator (top of page) */}
      <PriceCalculator data={data} />

      {/* 3. Product attributes table */}
      <ProductAttributesTable data={data} />

      {/* 4. Launch Models section */}
      <div className="bg-[var(--color-bg-elevated)] border border-[var(--color-border)] rounded-xl p-5 shadow-sm">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-bold flex items-center gap-2 text-[var(--color-text)]">
            <Rocket className="w-6 h-6 text-purple-500" />
            New Product Launch Models
          </h2>
          <div className="flex items-center gap-2">
            <button
              onClick={handleTriggerForecast}
              disabled={triggering}
              className="flex items-center gap-1 text-sm bg-purple-500 hover:bg-purple-600 text-white px-3 py-1.5 rounded-lg transition-colors disabled:opacity-50"
            >
              <Database className={`w-4 h-4 ${triggering ? 'animate-pulse' : ''}`} />
              {triggering ? 'Running...' : 'Run Forecast'}
            </button>
            <button
              onClick={fetchAssignments}
              disabled={loading}
              className="flex items-center gap-1 text-sm bg-[var(--color-bg-primary)] hover:bg-[var(--color-bg-hover)] border border-[var(--color-border)] px-3 py-1.5 rounded-lg transition-colors"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
              Refresh
            </button>
          </div>
        </div>

        <p className="text-[var(--color-text-secondary)] text-sm mb-4">
          Assign a reference model to a product family. The first 30 days of cold-start forecasting 
          will use the model's daily rate split evenly across all new products in the family, scaled by seasonality.
        </p>

      {message && (
        <div className={`p-3 rounded-md flex items-center gap-2 text-sm ${
          message.type === 'success' ? 'bg-green-500/10 text-green-500' : 'bg-red-500/10 text-red-500'
        }`}>
          {message.type === 'success' ? <CheckCircle className="w-4 h-4" /> : <AlertCircle className="w-4 h-4" />}
          {message.text}
        </div>
      )}

      <div className="grid gap-6">
        {Object.entries(newProductsByFamily).map(([family, products]) => {
          const currentModel = models[family] || '';
          
          return (
            <div key={family} className="bg-[var(--color-bg-elevated)] border border-[var(--color-border)] rounded-xl p-5">
              <div className="flex flex-col md:flex-row md:items-start justify-between gap-6">
                
                {/* Left: Family info and products */}
                <div className="flex-1">
                  <h3 className="font-semibold text-lg flex items-center gap-2 mb-3">
                    {family}
                    <span className="text-xs px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-400 font-medium border border-blue-500/20">
                      {products.length} New Products
                    </span>
                  </h3>
                  
                  <div className="flex flex-wrap gap-2">
                    {products.map((p, i) => (
                      <div key={p.product ?? i} className="text-sm bg-[var(--color-bg-primary)] border border-[var(--color-border)] px-3 py-1 rounded-md flex items-center gap-2">
                        {p.is_draft && <span className="w-2 h-2 rounded-full bg-yellow-500" title="Draft" />}
                        {p.product}
                      </div>
                    ))}
                  </div>
                </div>
                
                {/* Right: Model Selection */}
                <div className="w-full md:w-80 space-y-3 bg-[var(--color-bg-primary)] p-4 rounded-lg border border-[var(--color-border)]">
                  <label className="text-sm font-medium text-[var(--color-text-secondary)]">
                    Reference Model
                  </label>
                  
                  <select
                    className="w-full bg-[var(--color-bg-elevated)] border border-[var(--color-border)] text-sm rounded-lg px-3 py-2 focus:outline-none focus:border-purple-500 transition-colors"
                    value={currentModel}
                    onChange={(e) => handleSave(family, e.target.value)}
                    disabled={saving}
                  >
                    <option value="">-- No Model Assigned --</option>
                    {availableModels.map(m => (
                      <option key={m.product} value={m.product}>
                        {m.product} ({Math.round(m.daily_rate * 30)}/mo)
                      </option>
                    ))}
                  </select>
                  
                  {currentModel && (
                    <div className="text-xs text-[var(--color-text-secondary)] bg-purple-500/5 p-2 rounded border border-purple-500/10">
                      <span className="font-medium text-purple-400">Forecast Split:</span>
                      <br/>
                      The monthly rate will be divided by {products.length} to give each product an equal share of the {currentModel} volume.
                    </div>
                  )}
                </div>
              </div>
            </div>
          );
        })}
        
        {Object.keys(newProductsByFamily).length === 0 && (
          <div className="text-center py-12 text-[var(--color-text-secondary)] bg-[var(--color-bg-elevated)] rounded-xl border border-[var(--color-border)] border-dashed">
            <Rocket className="w-8 h-8 mx-auto mb-3 opacity-50" />
            <p>No new products or drafts found.</p>
          </div>
        )}
      </div>
      </div>
    </div>
  );
}
