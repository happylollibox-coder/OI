import { useState, useEffect, useMemo, Fragment } from 'react';
import { Rocket, Save, AlertCircle, CheckCircle, RefreshCw, Database, Calculator, DollarSign, Percent, TrendingUp, Target, Zap, ChevronDown, ChevronUp } from 'lucide-react';
import { useUnifiedData } from '../hooks/useUnifiedData';
import type { DashboardData } from '../types';

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

function PriceCalculator({ data }: { data: DashboardData }) {
  const [selectedProduct, setSelectedProduct] = useState<string>('');
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
  }, [selectedProduct, data]);
  
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
          
          {/* Product Selector */}
          <div>
            <label className="block text-xs font-medium text-[var(--color-text-secondary)] mb-1 uppercase tracking-wider">
              Load Product Costs
            </label>
            <select
              className="w-full bg-[var(--color-bg-primary)] border border-[var(--color-border)] text-sm rounded-lg px-3 py-2 focus:outline-none focus:border-green-500 transition-colors"
              value={selectedProduct}
              onChange={(e) => setSelectedProduct(e.target.value)}
            >
              <option value="">-- Manual Entry --</option>
              {data.products?.map(p => (
                <option key={p.asin} value={p.asin}>{p.product_short_name} ({p.asin})</option>
              ))}
            </select>
          </div>

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

function ProductAttributesTable({ data }: { data: DashboardData }) {
  const [editingAsin, setEditingAsin] = useState<string | null>(null);
  const [editValues, setEditValues] = useState<{cogs: string, shipping: string}>({cogs: '', shipping: ''});
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<{text: string, type: 'success'|'error'} | null>(null);

  // Group products by family
  const families = useMemo(() => {
    if (!data.products) return {};
    const grouped: Record<string, any[]> = {};
    data.products.forEach(p => {
      const fam = p.parent_name || 'Uncategorized';
      if (!grouped[fam]) grouped[fam] = [];
      grouped[fam].push(p);
    });
    return grouped;
  }, [data.products]);

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
      const res = await fetch('/api/products/update-costs', {
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
    <div className="mb-6 bg-white/50 dark:bg-[#1C2128]/50 rounded-2xl border border-[var(--color-border)] p-4 shadow-sm backdrop-blur-md">
      <h2 className="text-xl font-semibold mb-4 text-[var(--color-text)] flex items-center">
        <Database className="mr-2 h-5 w-5 text-blue-500" />
        Product Costs Database
      </h2>
      
      {message && (
        <div className={`p-3 rounded-xl mb-4 text-sm font-medium ${message.type === 'success' ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
          {message.text}
        </div>
      )}

      <div className="overflow-x-auto">
        <table className="w-full text-sm text-left">
          <thead className="text-xs uppercase bg-[var(--color-surface)]/50 text-[var(--color-text-muted)] border-b border-[var(--color-border)]">
            <tr>
              <th className="px-4 py-3 rounded-tl-lg">Family / Product</th>
              <th className="px-4 py-3">ASIN</th>
              <th className="px-4 py-3">COGS</th>
              <th className="px-4 py-3 text-right">Shipping</th>
              <th className="px-4 py-3 text-right rounded-tr-lg">Action</th>
            </tr>
          </thead>
          <tbody>
            {Object.entries(families).map(([family, products]) => (
              <Fragment key={family}>
                {/* Family Row */}
                <tr className="bg-[var(--color-surface)]/80 border-b border-[var(--color-border)]">
                  <td colSpan={5} className="px-4 py-2 font-bold text-[var(--color-text)]">
                    {family}
                  </td>
                </tr>
                {/* Product Rows */}
                {products.map(p => (
                  <tr key={p.asin} className="border-b border-[var(--color-border)] hover:bg-[var(--color-surface)]/30 transition-colors">
                    <td className="px-4 py-3 font-medium text-[var(--color-text)] pl-8">
                      {p.product_short_name}
                    </td>
                    <td className="px-4 py-3 text-[var(--color-text-muted)]">
                      {p.asin}
                    </td>
                    
                    {/* COGS */}
                    <td className="px-4 py-3 text-[var(--color-text)]">
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
      const res = await fetch('/api/launch_models');
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
      const res = await fetch('/api/launch_models', {
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
      const res = await fetch('/api/trigger_forecast', {
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

      {/* 2. New table */}
      <ProductAttributesTable data={data} />

      {/* 3. Calculator */}
      <PriceCalculator data={data} />

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
                    {products.map(p => (
                      <div key={p.id} className="text-sm bg-[var(--color-bg-primary)] border border-[var(--color-border)] px-3 py-1 rounded-md flex items-center gap-2">
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
