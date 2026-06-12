import { useState, useEffect, useMemo } from 'react';
import { Package, X, Plus, Minus, Loader2, ChevronDown, ChevronRight } from 'lucide-react';
import { fmt } from '../../utils';
import { useUnifiedData } from '../../hooks/useUnifiedData';
import { apiFetch } from '../../utils/apiFetch';

export interface DraftPOLine {
  product: string;
  qty: number;
  asin: string;
  cogs: number;
  amtString?: string;
}

export function CreatePOModal({
  draftLines: initialDraftLines,
  onClose,
  onSuccess,
}: {
  draftLines: DraftPOLine[];
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [draftLines, setDraftLines] = useState<DraftPOLine[]>(initialDraftLines);
  const { data: { products = [] } = {} } = useUnifiedData();

  const productsByFamily = useMemo(() => {
    const grouped: Record<string, typeof products> = {};
    for (const p of products) {
      const fam = p.family_name || 'Other';
      if (!grouped[fam]) grouped[fam] = [];
      grouped[fam].push(p);
    }
    return grouped;
  }, [products]);

  const [isAddMenuOpen, setIsAddMenuOpen] = useState(false);
  const [expandedFamilies, setExpandedFamilies] = useState<Record<string, boolean>>({});

  // Form states
  const [orderDate, setOrderDate] = useState(new Date().toISOString().split('T')[0]);
  const [manufacturer, setManufacturer] = useState('Standard Supplier');
  const [currency, setCurrency] = useState('USD');
  const [paymentStatus, setPaymentStatus] = useState('PENDING');
  const [notes, setNotes] = useState('');
  
  // Calculate total amount based on the current drafted lines
  const totalAmount = draftLines.reduce((sum, line) => sum + (line.qty * line.cogs), 0);

  const [manufacturerOptions, setManufacturerOptions] = useState<string[]>([]);

  useEffect(() => {
    apiFetch('/api/lov/SUPPLIER')
      .then(res => res.json())
      .then(data => {
        if (Array.isArray(data)) {
          const mfrs = data.filter((v: any) => v.attr1_value === 'Manufacturer').map((v: any) => v.value_id);
          setManufacturerOptions(mfrs);
          if (mfrs.length > 0 && manufacturer === 'Standard Supplier') {
            setManufacturer(mfrs[0]);
          }
        }
      })
      .catch(console.error);
  }, []);

  const handleUpdateLine = (idx: number, updates: Partial<DraftPOLine>) => {
    const updated = [...draftLines];
    updated[idx] = { ...updated[idx], ...updates };
    setDraftLines(updated);
  };

  const handleAddLine = (p: any) => {
    setDraftLines([
      ...draftLines,
      { product: p.product_short_name, qty: 1000, cogs: p.cogs || 1.00, asin: p.asin }
    ]);
    setIsAddMenuOpen(false);
  };

  const handleRemoveLine = (idx: number) => {
    const updated = draftLines.filter((_, i) => i !== idx);
    if (updated.length === 0) {
      onClose(); // Auto close if all lines are removed
      return;
    }
    setDraftLines(updated);
  };

  const handleSubmit = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await apiFetch('/api/po', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          order_date: orderDate,
          manufacturer_name: manufacturer,
          currency: currency,
          payment_status: paymentStatus,
          notes: notes,
          product_lines: draftLines.map(line => ({
            asin: line.asin || 'UNKNOWN',
            quantity: line.qty,
            total_amount: line.qty * line.cogs,
          })),
        }),
      });
      const data = await res.json();
      if (!res.ok || !data.success) throw new Error(data.error || 'Failed to create PO');

      onSuccess();
    } catch (e: any) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="bg-card border border-border w-full max-w-5xl rounded-xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-border/50 bg-surface">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-purple-500/10 text-purple-400">
              <Package size={18} />
            </div>
            <div>
              <h2 className="text-sm font-semibold text-text">
                Create Purchase Order
              </h2>
              <p className="text-[11px] text-muted truncate max-w-[250px]">
                {draftLines.length} product line{draftLines.length > 1 ? 's' : ''} drafted
              </p>
            </div>
          </div>
          <button onClick={onClose} className="p-1.5 text-muted hover:text-text hover:bg-inset rounded-md transition-colors">
            <X size={16} />
          </button>
        </div>

        {/* Body */}
        <div className="px-5 py-6 space-y-5 overflow-y-auto overflow-x-hidden">
          {error && (
            <div className="p-3 text-[11px] text-red-400 bg-red-500/10 border border-red-500/20 rounded-md">
              {error}
            </div>
          )}

          {/* Drafted Lines Summary */}
          <div className="space-y-2">
            <div className="flex justify-between items-center mb-2">
              <h3 className="text-[11px] font-bold text-muted uppercase tracking-wider">Order Items</h3>
              <div className="relative">
                <button 
                  onClick={() => setIsAddMenuOpen(!isAddMenuOpen)}
                  className="flex items-center gap-1 text-[10px] font-bold px-2 py-1 bg-purple-500/15 text-purple-500 dark:text-purple-400 hover:bg-purple-500/25 rounded-md transition-colors"
                >
                  <Plus size={12} />
                  ADD LINE
                </button>
                {isAddMenuOpen && (
                  <div className="absolute z-20 mt-1 w-64 bg-card border border-border/50 rounded-lg shadow-xl overflow-hidden right-0 max-h-64 overflow-y-auto">
                    {Object.entries(productsByFamily).map(([family, prods]) => (
                      <div key={family} className="border-b border-border/50 last:border-0">
                        <button 
                          onClick={() => setExpandedFamilies(prev => ({...prev, [family]: !prev[family]}))}
                          className="w-full flex items-center justify-between px-3 py-2 text-left bg-inset hover:bg-card-hover text-[11px] font-bold text-text"
                        >
                          {family}
                          {expandedFamilies[family] ? <ChevronDown size={12} /> : <ChevronRight size={12} />}
                        </button>
                        {expandedFamilies[family] && (
                          <div className="py-1">
                            {prods.map(p => (
                              <button
                                key={p.asin}
                                onClick={() => handleAddLine(p)}
                                className="w-full text-left px-3 py-1.5 hover:bg-card-hover transition-colors flex items-center justify-between"
                              >
                                <span className="text-[11px] font-medium text-text truncate pr-2">{p.product_short_name}</span>
                                <span className="text-[9px] text-subtle font-mono">{p.asin}</span>
                              </button>
                            ))}
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
            
            <div className="rounded-md border border-border/50 p-2 space-y-1 max-h-64 overflow-y-auto">
              {draftLines.map((line, idx) => (
                <div key={idx} className="flex items-start gap-3 py-1.5 px-2 hover:bg-white/5 rounded-md transition-colors group min-w-0">
                  <div className="flex-1 min-w-0 flex items-center justify-between bg-inset border border-border/50 rounded px-3 py-2">
                    <span className="font-semibold text-text text-[12px] pr-4">{line.product}</span>
                    <span className="text-[10px] text-subtle font-mono tracking-wider bg-inset px-1.5 py-0.5 rounded flex-shrink-0">{line.asin}</span>
                  </div>
                  
                  <div className="flex items-center gap-2 bg-inset border border-border/50 rounded flex-shrink-0 px-2 py-2 mt-0.5">
                    <span className="text-[10px] text-muted font-medium">QTY</span>
                    <input 
                      type="number" 
                      min="1"
                      value={line.qty} 
                      onChange={e => handleUpdateLine(idx, { qty: parseInt(e.target.value) || 0 })}
                      className="w-16 bg-transparent text-[12px] text-text font-semibold outline-none text-right"
                    />
                  </div>
                  
                  <div className="flex items-center gap-2 bg-inset border border-border/50 rounded flex-shrink-0 px-2 py-2 mt-0.5">
                    <span className="text-[10px] text-muted font-medium">COST</span>
                    <span className="text-[12px] text-muted">$</span>
                    <input 
                      type="number" 
                      min="0"
                      step="0.01"
                      value={line.cogs} 
                      onChange={e => handleUpdateLine(idx, { cogs: parseFloat(e.target.value) || 0 })}
                      className="w-20 bg-transparent text-[12px] text-text font-semibold outline-none text-right -ml-1"
                    />
                  </div>
                  
                  <div className="flex items-center gap-2 bg-inset border border-border/50 rounded flex-shrink-0 px-2 py-2 mt-0.5">
                    <span className="text-[10px] text-muted font-medium">AMT</span>
                    <span className="text-[12px] text-muted">$</span>
                    <input 
                      type="text" 
                      value={line.amtString ?? Number((line.qty * line.cogs).toFixed(2))} 
                      onChange={e => {
                        const val = e.target.value;
                        if (/^\d*\.?\d*$/.test(val)) {
                          const parsed = parseFloat(val);
                          handleUpdateLine(idx, {
                            amtString: val,
                            ...(!isNaN(parsed) && line.qty > 0 ? { cogs: parsed / line.qty } : {})
                          });
                        }
                      }}
                      onBlur={() => handleUpdateLine(idx, { amtString: undefined })}
                      className="w-24 bg-transparent text-[12px] text-text font-semibold outline-none text-right -ml-1"
                    />
                  </div>
                  
                  <button 
                    onClick={() => handleRemoveLine(idx)}
                    className="text-muted hover:text-red-400 p-1.5 rounded-md opacity-50 hover:opacity-100 transition-all flex-shrink-0 bg-inset border border-border/50 mt-1"
                    title="Remove line"
                  >
                    <Minus size={12} />
                  </button>
                </div>
              ))}
            </div>
            
            <div className="mt-2 p-3 rounded-md bg-purple-500/10 border border-purple-500/20 flex justify-between items-center">
              <span className="text-[11px] font-bold text-purple-400/80 uppercase tracking-wider">Total Estimate</span>
              <span className="text-purple-400 text-sm font-bold">${totalAmount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <label className="text-[11px] font-semibold text-muted uppercase tracking-wider">Manufacturer</label>
              <select 
                value={manufacturer} 
                onChange={e => setManufacturer(e.target.value)}
                className="w-full bg-inset border border-border rounded-md px-3 py-2 text-sm text-text outline-none focus:border-purple-500/50 focus:ring-1 focus:ring-purple-500/50"
              >
                {manufacturerOptions.length === 0 ? (
                  <option value="Standard Supplier">Standard Supplier</option>
                ) : (
                  manufacturerOptions.map(opt => (
                    <option key={opt} value={opt}>{opt}</option>
                  ))
                )}
              </select>
            </div>
            <div className="space-y-1.5">
              <label className="text-[11px] font-semibold text-muted uppercase tracking-wider">Order Date</label>
              <input 
                type="date" 
                value={orderDate} 
                onChange={e => setOrderDate(e.target.value)}
                className="w-full bg-inset border border-border rounded-md px-3 py-2 text-sm text-text outline-none focus:border-purple-500/50 focus:ring-1 focus:ring-purple-500/50"
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <label className="text-[11px] font-semibold text-muted uppercase tracking-wider">Payment Status</label>
              <select 
                value={paymentStatus} 
                onChange={e => setPaymentStatus(e.target.value)}
                className="w-full bg-inset border border-border rounded-md px-3 py-2 text-sm text-text outline-none focus:border-purple-500/50 focus:ring-1 focus:ring-purple-500/50"
              >
                <option value="PENDING">Pending</option>
                <option value="DEPOSIT_PAID">Deposit Paid</option>
                <option value="FULLY_PAID">Fully Paid</option>
              </select>
            </div>
            <div className="space-y-1.5">
              <label className="text-[11px] font-semibold text-muted uppercase tracking-wider">Currency</label>
              <select 
                value={currency} 
                onChange={e => setCurrency(e.target.value)}
                className="w-full bg-inset border border-border rounded-md px-3 py-2 text-sm text-text outline-none focus:border-purple-500/50 focus:ring-1 focus:ring-purple-500/50"
              >
                <option value="USD">USD</option>
                <option value="CNY">CNY</option>
                <option value="EUR">EUR</option>
              </select>
            </div>
          </div>

          <div className="space-y-1.5">
            <label className="text-[11px] font-semibold text-muted uppercase tracking-wider">Notes</label>
            <textarea 
              value={notes} 
              onChange={e => setNotes(e.target.value)}
              placeholder="Optional order notes..."
              className="w-full bg-inset border border-border rounded-md px-3 py-2 text-sm text-text outline-none focus:border-purple-500/50 focus:ring-1 focus:ring-purple-500/50 min-h-[80px]"
            />
          </div>
        </div>

        {/* Footer */}
        <div className="px-5 py-4 border-t border-border/50 bg-surface flex justify-end gap-3">
          <button 
            onClick={onClose}
            disabled={loading}
            className="px-4 py-2 text-sm font-medium text-muted hover:text-text transition-colors disabled:opacity-50"
          >
            Cancel
          </button>
          <button 
            onClick={handleSubmit}
            disabled={loading}
            className="inline-flex items-center gap-2 px-6 py-2 bg-purple-500 hover:bg-purple-600 text-white text-sm font-medium rounded-md shadow-lg shadow-purple-500/20 transition-all disabled:opacity-50"
          >
            {loading && <Loader2 size={16} className="animate-spin" />}
            Create Purchase Order
          </button>
        </div>
      </div>
    </div>
  );
}
