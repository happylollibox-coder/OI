import { useState, useEffect, useMemo } from 'react';
import { Package, X, Plus, Minus, Loader2, ChevronDown, ChevronRight, AlertCircle } from 'lucide-react';
import { fmt } from '../../utils';
import { useUnifiedData } from '../../hooks/useUnifiedData';

export interface DraftShipmentLine {
  product: string;
  asin: string;
  qty: number;
  cartons?: number;
  po_id?: string;
  po_error?: string;
}

export function CreateShipmentModal({
  draftLines: initialDraftLines,
  onClose,
  onSuccess,
  defaultDate,
  defaultType
}: {
  draftLines: DraftShipmentLine[];
  onClose: () => void;
  onSuccess: () => void;
  defaultDate?: string;
  defaultType?: string;
}) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [draftLines, setDraftLines] = useState<DraftShipmentLine[]>(initialDraftLines);
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
  const [shipmentDate, setShipmentDate] = useState(defaultDate || new Date().toISOString().split('T')[0]);
  const [estimatedArrival, setEstimatedArrival] = useState('');
  const [shipmentType, setShipmentType] = useState(defaultType || 'FAST_SEA');
  const [shipmentStatus, setShipmentStatus] = useState('PENDING');
  const [deliverer, setDeliverer] = useState('');
  const [trackingNumber, setTrackingNumber] = useState('');
  const [notes, setNotes] = useState('');
  
  const [costShipped, setCostShipped] = useState<string>('');
  const [kgPrice, setKgPrice] = useState<string>('');

  useEffect(() => {
    if (defaultType) {
      setShipmentType(defaultType);
      setSplitHeaders(prev => {
        const newHeaders = [...prev];
        newHeaders[0] = { ...newHeaders[0], shipment_type: defaultType };
        return newHeaders;
      });
    }
  }, [defaultType]);

  const [delivererOptions, setDelivererOptions] = useState<any[]>([]);
  const [typeOptions, setTypeOptions] = useState<any[]>([]);
  const [statusOptions, setStatusOptions] = useState<any[]>([]);
  
  // Split Shipment states
  const [numSplits, setNumSplits] = useState(1);
  const [splitHeaders, setSplitHeaders] = useState<any[]>([{
    shipment_date: defaultDate || new Date().toISOString().split('T')[0],
    estimated_arrival_date: '',
    shipment_type: defaultType || 'FAST_SEA',
    shipment_status: 'PENDING',
    deliverer: '',
    tracking_number: '',
    notes: '',
    cost_shipped: '',
    kg_price: ''
  }]);
  const [splitCartons, setSplitCartons] = useState<number[][]>(initialDraftLines.map(l => [l.cartons || 0]));
  
  const [openPos, setOpenPos] = useState<any[]>([]);
  const [posLoading, setPosLoading] = useState(true);

  // Fetch LOVs
  useEffect(() => {
    fetch('/api/lov/SUPPLIER')
      .then(res => res.json())
      .then(data => {
        if (Array.isArray(data)) {
          const mfrs = data.filter((v: any) => v.attr1_value === 'Deliverer');
          setDelivererOptions(mfrs);
          if (mfrs.length > 0) setDeliverer(mfrs.find((m: any) => m.is_default)?.value_id || mfrs[0].value_id);
        }
      })
      .catch(console.error);

    fetch('/api/lov/SHIPMENT_TYPE')
      .then(res => res.json())
      .then(data => {
        if (Array.isArray(data)) {
          setTypeOptions(data);
          if (!defaultType) setShipmentType(data.find((m: any) => m.is_default)?.value_id || data[0].value_id);
        }
      })
      .catch(console.error);

    fetch('/api/lov/SHIPMENT_STATUS')
      .then(res => res.json())
      .then(data => {
        if (Array.isArray(data)) {
          setStatusOptions(data);
          setShipmentStatus(data.find((m: any) => m.is_default)?.value_id || data[0].value_id);
        }
      })
      .catch(console.error);
  }, [defaultType]);

  // Sync splitHeaders with default headers if they change in single mode
  useEffect(() => {
    if (numSplits === 1) {
      setSplitHeaders([{
        shipment_date: shipmentDate,
        estimated_arrival_date: estimatedArrival,
        shipment_type: shipmentType,
        shipment_status: shipmentStatus,
        deliverer: deliverer,
        tracking_number: trackingNumber,
        notes: notes,
        cost_shipped: costShipped,
        kg_price: kgPrice
      }]);
    }
  }, [shipmentDate, estimatedArrival, shipmentType, shipmentStatus, deliverer, trackingNumber, notes, costShipped, kgPrice, numSplits]);

  // Fetch Open POs and match them to drafted lines
  useEffect(() => {
    setPosLoading(true);
    fetch('/api/open-pos')
      .then(res => res.json())
      .then(data => {
        if (data.success && data.data) {
          const pos = data.data;
          setOpenPos(pos);
          
          // Match lines
          setDraftLines(prev => {
            const newLines = prev.map(line => {
              const cleanAsin = line.asin?.trim();
              const matches = pos.filter((po: any) => po.product_asin?.trim() === cleanAsin);
              if (matches.length === 0) {
                return { ...line, po_error: 'No open PO exists' };
              }
              const selectedPo = matches.length === 1 ? matches[0] : matches[matches.length - 1];
              const ctns = selectedPo.package_quantity ? Math.floor(line.qty / selectedPo.package_quantity) : line.cartons;
              return { ...line, po_id: selectedPo.purchase_order_id, cartons: ctns, po_error: undefined };
            });
            // Also update splitCartons array size to match new lines cartons
            if (numSplits === 1) {
              setSplitCartons(newLines.map(l => [l.cartons || 0]));
            } else {
              setSplitCartons(prev => {
                const updated = [...prev];
                for (let i = 0; i < newLines.length; i++) {
                  if (!updated[i]) {
                    const arr = new Array(numSplits).fill(0);
                    arr[0] = newLines[i].cartons || 0;
                    updated[i] = arr;
                  }
                }
                return updated;
              });
            }
            return newLines;
          });
        }
      })
      .catch(err => {
        console.error(err);
      })
      .finally(() => {
        setPosLoading(false);
      });
  }, []);

  const handleUpdateLine = (idx: number, updates: Partial<DraftShipmentLine>) => {
    const updated = [...draftLines];
    updated[idx] = { ...updated[idx], ...updates };
    setDraftLines(updated);
    
    if ('cartons' in updates && numSplits === 1) {
      const newSplitCartons = [...splitCartons];
      if (newSplitCartons[idx]) {
        newSplitCartons[idx][0] = updates.cartons || 0;
      } else {
        newSplitCartons[idx] = [updates.cartons || 0];
      }
      setSplitCartons(newSplitCartons);
    }
  };

  const handleAddLine = (p: any) => {
    // Attempt to auto-match PO for new line
    const cleanAsin = p.asin?.trim();
    const matches = openPos.filter((po: any) => po.product_asin?.trim() === cleanAsin);
    let po_id = undefined;
    let po_error = undefined;
    let ctns = 0;
    const qty = 1000;
    if (matches.length === 0) po_error = 'No open PO exists';
    else {
      const selectedPo = matches.length === 1 ? matches[0] : matches[matches.length - 1];
      po_id = selectedPo.purchase_order_id;
      ctns = selectedPo.package_quantity ? Math.floor(qty / selectedPo.package_quantity) : 0;
    }

    setDraftLines([
      ...draftLines,
      { product: p.product_short_name, asin: p.asin, qty, cartons: ctns, po_id: po_id, po_error: po_error }
    ]);
    const arr = new Array(numSplits).fill(0);
    arr[0] = ctns;
    setSplitCartons([...splitCartons, arr]);
    setIsAddMenuOpen(false);
  };

  const handleRemoveLine = (idx: number) => {
    const updated = draftLines.filter((_, i) => i !== idx);
    const updatedCartons = splitCartons.filter((_, i) => i !== idx);
    if (updated.length === 0) {
      onClose();
      return;
    }
    setDraftLines(updated);
    setSplitCartons(updatedCartons);
  };
  
  const handleAddSplit = () => {
    setNumSplits(prev => prev + 1);
    setSplitHeaders(prev => [
      ...prev,
      {
        shipment_date: shipmentDate,
        estimated_arrival_date: estimatedArrival,
        shipment_type: shipmentType,
        shipment_status: shipmentStatus,
        deliverer: deliverer,
        tracking_number: '',
        notes: '',
        cost_shipped: '',
        kg_price: ''
      }
    ]);
    setSplitCartons(prev => prev.map(row => [...row, 0]));
  };
  
  const handleRemoveSplit = (idx: number) => {
    if (numSplits <= 1) return;
    setNumSplits(prev => prev - 1);
    setSplitHeaders(prev => prev.filter((_, i) => i !== idx));
    setSplitCartons(prev => prev.map(row => {
      const newRow = [...row];
      // When removing a split, add its cartons to the first split to maintain totals
      const removedCartons = newRow.splice(idx, 1)[0] || 0;
      newRow[0] += removedCartons;
      return newRow;
    }));
  };

  const updateSplitHeader = (idx: number, field: string, value: any) => {
    setSplitHeaders(prev => {
      const updated = [...prev];
      updated[idx] = { ...updated[idx], [field]: value };
      return updated;
    });
  };

  const updateSplitCartons = (lineIdx: number, splitIdx: number, value: number) => {
    setSplitCartons(prev => {
      const updated = [...prev];
      updated[lineIdx] = [...updated[lineIdx]];
      updated[lineIdx][splitIdx] = value;
      return updated;
    });
  };

  // Validate carton allocations
  const cartonValidation = useMemo(() => {
    if (numSplits === 1) return { isValid: true, errors: [] };
    const errors: string[] = [];
    let isValid = true;
    for (let i = 0; i < draftLines.length; i++) {
      const totalAllocated = (splitCartons[i] || []).reduce((sum, v) => sum + (v || 0), 0);
      const expected = draftLines[i].cartons || 0;
      if (totalAllocated !== expected) {
        errors.push(`Line ${i + 1} (${draftLines[i].product}) has ${totalAllocated} allocated cartons, but total is ${expected}.`);
        isValid = false;
      }
    }
    return { isValid, errors };
  }, [numSplits, draftLines, splitCartons]);

  const handleSubmit = async () => {
    // Validate POs
    const missingPos = draftLines.filter(l => !l.po_id);
    if (missingPos.length > 0) {
      setError(`Cannot submit: ${missingPos.length} line(s) missing a Purchase Order.`);
      return;
    }
    
    if (!cartonValidation.isValid) {
      setError(`Carton allocation error: \n` + cartonValidation.errors.join('\n'));
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const promises = [];
      
      for (let s = 0; s < numSplits; s++) {
        const header = numSplits > 1 ? splitHeaders[s] : {
          shipment_date: shipmentDate,
          estimated_arrival_date: estimatedArrival,
          shipment_type: shipmentType,
          shipment_status: shipmentStatus,
          deliverer,
          tracking_number: trackingNumber,
          notes,
          cost_shipped: costShipped,
          kg_price: kgPrice
        };
        
        // Build lines for this split
        const linesForSplit = [];
        for (let l = 0; l < draftLines.length; l++) {
          const line = draftLines[l];
          const allocatedCartons = numSplits > 1 ? splitCartons[l][s] : (line.cartons || 0);
          
          if (allocatedCartons > 0) {
            // Calculate qty based on carton ratio
            const qtyPerCarton = line.cartons ? line.qty / line.cartons : 0;
            const allocatedQty = Math.round(allocatedCartons * qtyPerCarton);
            
            linesForSplit.push({
              purchase_order_id: line.po_id,
              asin: line.asin,
              quantity: allocatedQty || line.qty, // Fallback if no cartons
              cartons: allocatedCartons
            });
          }
        }
        
        // If this split has no items, skip it
        if (linesForSplit.length === 0) continue;

        const payload = {
          shipment_date: header.shipment_date,
          estimated_arrival_date: header.estimated_arrival_date || null,
          shipment_type: header.shipment_type,
          shipment_status: header.shipment_status,
          deliverer: deliverer, // Deliverer is the same for all splits
          tracking_number: header.tracking_number,
          notes: header.notes,
          cost_shipped: header.cost_shipped ? parseFloat(header.cost_shipped) : null,
          kg_price: header.kg_price ? parseFloat(header.kg_price) : null,
          is_paid: false,
          lines: linesForSplit
        };

        promises.push(fetch('/api/shipments', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        }).then(res => res.json()));
      }

      if (promises.length === 0) {
        setError("No items allocated to any shipment splits.");
        setLoading(false);
        return;
      }

      const results = await Promise.all(promises);
      const failures = results.filter(r => !r.success);
      
      if (failures.length > 0) {
        setError(failures.map(f => f.error).join(' | ') || 'Failed to create one or more shipments');
      } else {
        onSuccess();
      }
    } catch (err: any) {
      setError(err.message || 'An error occurred');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="bg-[#1C1C1F] border border-border w-full max-w-5xl rounded-xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-border/50 bg-white/[0.02]">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-blue-500/10 text-blue-400">
              <Package size={18} />
            </div>
            <div>
              <h2 className="text-sm font-semibold text-white">
                Create Shipment
              </h2>
              <p className="text-[11px] text-gray-400 truncate max-w-[250px]">
                {draftLines.length} product line{draftLines.length > 1 ? 's' : ''} drafted
              </p>
            </div>
          </div>
          <button onClick={onClose} className="p-1.5 text-gray-400 hover:text-white hover:bg-white/5 rounded-md transition-colors">
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
              <h3 className="text-[11px] font-bold text-gray-400 uppercase tracking-wider">Shipment Items</h3>
              
              <div className="flex items-center gap-4">
                {posLoading && (
                  <div className="flex items-center gap-2 text-[10px] text-gray-400">
                    <Loader2 size={12} className="animate-spin" /> Auto-matching POs...
                  </div>
                )}
                
                <div className="flex items-center gap-2">
                  <button 
                    onClick={handleAddSplit}
                    className="flex items-center gap-1 text-[10px] font-bold px-2 py-1 bg-purple-500/10 text-purple-400 hover:bg-purple-500/20 border border-purple-500/30 rounded-md transition-colors"
                  >
                    <Plus size={12} />
                    SPLIT SHIPMENT
                  </button>
                  <div className="relative">
                    <button 
                      onClick={() => setIsAddMenuOpen(!isAddMenuOpen)}
                      className="flex items-center gap-1 text-[10px] font-bold px-2 py-1 bg-blue-500/10 text-blue-400 hover:bg-blue-500/20 rounded-md transition-colors"
                    >
                      <Plus size={12} />
                      ADD LINE
                    </button>
                    {isAddMenuOpen && (
                    <div className="absolute z-20 mt-1 w-64 bg-[#2C2C30] border border-border/50 rounded-lg shadow-xl overflow-hidden right-0 max-h-64 overflow-y-auto">
                      {Object.entries(productsByFamily).map(([family, prods]) => (
                        <div key={family} className="border-b border-border/50 last:border-0">
                          <button 
                            onClick={() => setExpandedFamilies(prev => ({...prev, [family]: !prev[family]}))}
                            className="w-full flex items-center justify-between px-3 py-2 text-left bg-black/20 hover:bg-black/40 text-[11px] font-bold text-gray-300"
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
                                  className="w-full text-left px-3 py-1.5 hover:bg-white/5 transition-colors flex items-center justify-between"
                                >
                                  <span className="text-[11px] font-medium text-gray-200 truncate pr-2">{p.product_short_name}</span>
                                  <span className="text-[9px] text-gray-500 font-mono">{p.asin}</span>
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
              </div>
            </div>
            
            <div className="rounded-md border border-border/50 p-2 space-y-1 max-h-64 overflow-y-auto">
              {draftLines.map((line, idx) => {
                const totalAllocated = (splitCartons[idx] || []).reduce((sum, v) => sum + (v || 0), 0);
                const allocationError = numSplits > 1 && totalAllocated !== (line.cartons || 0);

                return (
                  <div key={idx} className={`flex flex-col gap-2 py-2 px-2 hover:bg-white/5 rounded-md transition-colors group min-w-0 border-b border-border/30 last:border-0 ${allocationError ? 'bg-red-500/5' : ''}`}>
                    <div className="flex items-start gap-2">
                      {/* Left Column: Product Info & PO Select */}
                      <div className="flex flex-col gap-1 w-48 flex-shrink-0">
                        <span className="font-semibold text-white text-[12px] truncate">{line.product}</span>
                        <span className="text-[9px] text-gray-500 font-mono tracking-wider">{line.asin}</span>
                      </div>
                      
                      <div className="flex-1 min-w-0 mt-0.5">
                        {line.po_error ? (
                          <div className="flex items-center gap-1.5 text-[10px] font-medium text-red-400 bg-red-400/10 px-2 py-1.5 rounded border border-red-400/20">
                            <AlertCircle size={10} />
                            {line.po_error}
                          </div>
                        ) : (
                          <select
                            className="w-full bg-black/20 border border-border/50 rounded px-2 py-1.5 text-[11px] font-semibold text-white outline-none focus:border-blue-500/50 truncate"
                            value={line.po_id || ''}
                            onChange={(e) => {
                              const newPoId = e.target.value;
                              const selectedPo = openPos.find(p => p.purchase_order_id === newPoId);
                              const ctns = selectedPo?.package_quantity ? Math.floor(line.qty / selectedPo.package_quantity) : line.cartons;
                              handleUpdateLine(idx, { po_id: newPoId, cartons: ctns });
                            }}
                          >
                            <option value="">-- Select PO --</option>
                            {openPos.filter(p => p.product_asin?.trim() === line.asin?.trim()).map(po => (
                              <option key={po.purchase_order_id} value={po.purchase_order_id}>
                                {po.purchase_order_id} ({po.manufacturer_name}) - Rem: {fmt(po.remaining_quantity)}
                              </option>
                            ))}
                          </select>
                        )}
                      </div>

                      {/* Right Column: Qty, Ctns, Actions */}
                      <div className="flex items-center gap-2 flex-shrink-0 mt-0.5">
                        <div className="flex flex-col items-end gap-1 px-2">
                          <span className="text-[11px] text-white font-bold">{fmt(line.qty)} <span className="text-[9px] text-gray-400 font-medium">QTY</span></span>
                          <div className="flex items-center gap-1">
                            <input
                              type="number"
                              min="0"
                              value={line.cartons || 0}
                              onChange={(e) => {
                                const newCtns = parseInt(e.target.value) || 0;
                                const po = openPos.find(p => p.purchase_order_id === line.po_id);
                                const newQty = po?.package_quantity ? newCtns * po.package_quantity : line.qty;
                                handleUpdateLine(idx, { cartons: newCtns, qty: newQty });
                              }}
                              className="w-14 bg-black/20 border border-border/50 rounded px-1 py-0.5 text-[11px] font-bold text-white text-right outline-none focus:border-blue-500/50"
                            />
                            <span className="text-[9px] text-gray-400 font-medium">CTNS</span>
                          </div>
                        </div>
                        {numSplits === 1 && (
                          <button 
                            onClick={() => handleRemoveLine(idx)}
                            className="text-gray-400 hover:text-red-400 p-1.5 rounded opacity-50 hover:opacity-100 transition-all bg-black/20 border border-border/50 self-start"
                            title="Remove line"
                          >
                            <Minus size={12} />
                          </button>
                        )}
                      </div>
                    </div>

                    {/* Split Allocation Row */}
                    {numSplits > 1 && (
                      <div className="flex flex-col gap-2 pl-2 border-l-2 border-purple-500/30 ml-2 py-1">
                        <div className="flex items-center justify-between text-[10px] text-gray-400">
                          <span className="font-bold uppercase tracking-wider text-purple-400">Carton Allocation</span>
                          {allocationError && (
                            <span className="text-red-400 font-bold flex items-center gap-1">
                              <AlertCircle size={10} />
                              Allocated: {totalAllocated} / {line.cartons}
                            </span>
                          )}
                        </div>
                        <div className="flex items-center gap-2 flex-wrap">
                          {Array.from({ length: numSplits }).map((_, sIdx) => (
                            <div key={sIdx} className="flex items-center gap-1.5 bg-black/20 border border-border/50 rounded px-2 py-1">
                              <span className="text-[9px] text-gray-400 font-medium">Split {sIdx + 1}</span>
                              <input 
                                type="number" 
                                min="0"
                                value={splitCartons[idx]?.[sIdx] ?? ''} 
                                onChange={e => updateSplitCartons(idx, sIdx, parseInt(e.target.value) || 0)}
                                className={`w-12 bg-transparent text-[11px] font-semibold outline-none text-right ${allocationError ? 'text-red-300' : 'text-purple-300'}`}
                              />
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          {/* Header Form */}
          {numSplits === 1 ? (
            <>
              <div className="grid grid-cols-3 gap-4">
                <div className="space-y-1.5">
                  <label className="text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Shipment Date</label>
                  <input 
                    type="date" 
                    value={shipmentDate} 
                    onChange={e => setShipmentDate(e.target.value)}
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-white outline-none focus:border-blue-500/50 focus:ring-1 focus:ring-blue-500/50"
                  />
                </div>
                <div className="space-y-1.5">
                  <label className="text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Estimated Arrival</label>
                  <input 
                    type="date" 
                    value={estimatedArrival} 
                    onChange={e => setEstimatedArrival(e.target.value)}
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-white outline-none focus:border-blue-500/50 focus:ring-1 focus:ring-blue-500/50"
                  />
                </div>
                <div className="space-y-1.5">
                  <label className="text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Shipment Type</label>
                  <select 
                    value={shipmentType} 
                    onChange={e => setShipmentType(e.target.value)}
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-white outline-none focus:border-blue-500/50 focus:ring-1 focus:ring-blue-500/50"
                  >
                    {typeOptions.map(o => (
                      <option key={o.value_id} value={o.value_id}>{o.value_caption}</option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div className="space-y-1.5">
                  <label className="text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Status</label>
                  <select 
                    value={shipmentStatus} 
                    onChange={e => setShipmentStatus(e.target.value)}
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-white outline-none focus:border-blue-500/50 focus:ring-1 focus:ring-blue-500/50"
                  >
                    {statusOptions.map(o => (
                      <option key={o.value_id} value={o.value_id}>{o.value_caption}</option>
                    ))}
                  </select>
                </div>
                <div className="space-y-1.5">
                  <label className="text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Deliverer</label>
                  <select 
                    value={deliverer} 
                    onChange={e => setDeliverer(e.target.value)}
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-white outline-none focus:border-blue-500/50 focus:ring-1 focus:ring-blue-500/50"
                  >
                    <option value="">-- Select --</option>
                    {delivererOptions.map(o => (
                      <option key={o.value_id} value={o.value_id}>{o.value_caption}</option>
                    ))}
                  </select>
                </div>
                <div className="space-y-1.5">
                  <label className="text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Tracking Number</label>
                  <input 
                    type="text" 
                    value={trackingNumber} 
                    onChange={e => setTrackingNumber(e.target.value)}
                    placeholder="Optional tracking info"
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-white outline-none focus:border-blue-500/50 focus:ring-1 focus:ring-blue-500/50"
                  />
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div className="space-y-1.5">
                  <label className="text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Cost Shipped</label>
                  <input 
                    type="number" 
                    step="0.01"
                    value={costShipped} 
                    onChange={e => setCostShipped(e.target.value)}
                    placeholder="0.00"
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-white outline-none focus:border-blue-500/50 focus:ring-1 focus:ring-blue-500/50"
                  />
                </div>
                <div className="space-y-1.5">
                  <label className="text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Kg Price</label>
                  <input 
                    type="number" 
                    step="0.01"
                    value={kgPrice} 
                    onChange={e => setKgPrice(e.target.value)}
                    placeholder="0.00"
                    className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-white outline-none focus:border-blue-500/50 focus:ring-1 focus:ring-blue-500/50"
                  />
                </div>
              </div>

              <div className="space-y-1.5">
                <label className="text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Notes</label>
                <textarea 
                  value={notes} 
                  onChange={e => setNotes(e.target.value)}
                  placeholder="Optional shipment notes..."
                  className="w-full bg-black/20 border border-border rounded-md px-3 py-2 text-sm text-white outline-none focus:border-blue-500/50 focus:ring-1 focus:ring-blue-500/50 min-h-[60px]"
                />
              </div>
            </>
          ) : (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-[11px] font-bold text-purple-400 uppercase tracking-wider">Split Headers</h3>
                <span className="text-[10px] text-gray-400 bg-white/5 px-2 py-1 rounded">
                  Edit individual split details below
                </span>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {Array.from({ length: numSplits }).map((_, sIdx) => {
                  const header = splitHeaders[sIdx];
                  if (!header) return null;
                  return (
                    <div key={sIdx} className="bg-white/[0.02] border border-purple-500/20 rounded-xl p-4 relative">
                      <div className="flex items-center justify-between mb-3">
                        <h4 className="text-[12px] font-bold text-purple-300">Split {sIdx + 1}</h4>
                        <button 
                          onClick={() => handleRemoveSplit(sIdx)}
                          className="text-gray-500 hover:text-red-400"
                        >
                          <X size={14} />
                        </button>
                      </div>
                      
                      <div className="space-y-3">
                        <div className="grid grid-cols-2 gap-2">
                          <div className="space-y-1">
                            <label className="text-[9px] font-semibold text-gray-400 uppercase">Ship Date</label>
                            <input 
                              type="date" 
                              value={header.shipment_date} 
                              onChange={e => updateSplitHeader(sIdx, 'shipment_date', e.target.value)}
                              className="w-full bg-black/20 border border-border rounded px-2 py-1.5 text-[10px] text-white outline-none focus:border-purple-500/50"
                            />
                          </div>
                          <div className="space-y-1">
                            <label className="text-[9px] font-semibold text-gray-400 uppercase">ETA</label>
                            <input 
                              type="date" 
                              value={header.estimated_arrival_date} 
                              onChange={e => updateSplitHeader(sIdx, 'estimated_arrival_date', e.target.value)}
                              className="w-full bg-black/20 border border-border rounded px-2 py-1.5 text-[10px] text-white outline-none focus:border-purple-500/50"
                            />
                          </div>
                        </div>

                        <div className="space-y-1">
                          <label className="text-[9px] font-semibold text-gray-400 uppercase">Shipment Type</label>
                          <select 
                            value={header.shipment_type} 
                            onChange={e => updateSplitHeader(sIdx, 'shipment_type', e.target.value)}
                            className="w-full bg-black/20 border border-border rounded px-2 py-1.5 text-[10px] text-white outline-none focus:border-purple-500/50"
                          >
                            {typeOptions.map(o => (
                              <option key={o.value_id} value={o.value_id}>{o.value_caption}</option>
                            ))}
                          </select>
                        </div>

                        <div className="space-y-1">
                          <label className="text-[9px] font-semibold text-gray-400 uppercase">Tracking Number</label>
                          <input 
                            type="text" 
                            value={header.tracking_number} 
                            onChange={e => updateSplitHeader(sIdx, 'tracking_number', e.target.value)}
                            placeholder="Optional tracking"
                            className="w-full bg-black/20 border border-border rounded px-2 py-1.5 text-[10px] text-white outline-none focus:border-purple-500/50"
                          />
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-5 py-4 border-t border-border/50 bg-white/[0.02] flex justify-between items-center">
          <div className="flex items-center gap-4">
             <div className="flex flex-col">
               <span className="text-[10px] font-bold text-gray-400 uppercase tracking-wider">Total Quantity</span>
               <span className="text-white text-lg font-bold">{fmt(draftLines.reduce((s, l) => s + l.qty, 0))} <span className="text-sm text-gray-500">units</span></span>
             </div>
             {draftLines.some(l => !!l.po_error) && (
               <div className="flex items-center gap-1.5 text-xs font-medium text-red-400 bg-red-400/10 px-3 py-1.5 rounded-md border border-red-400/20">
                 <AlertCircle size={14} />
                 Missing POs
               </div>
             )}
          </div>
          <div className="flex gap-3">
            <button 
              onClick={onClose}
              disabled={loading}
              className="px-4 py-2 text-sm font-medium text-gray-400 hover:text-white transition-colors disabled:opacity-50"
            >
              Cancel
            </button>
            <button 
              onClick={handleSubmit}
              disabled={loading || draftLines.some(l => !!l.po_error) || !cartonValidation.isValid}
              className="inline-flex items-center gap-2 px-6 py-2 bg-blue-600 hover:bg-blue-500 text-white text-sm font-medium rounded-md shadow-lg shadow-blue-500/20 transition-all disabled:opacity-50"
            >
              {loading && <Loader2 size={16} className="animate-spin" />}
              {numSplits > 1 ? `Create ${numSplits} Shipments` : 'Create Shipment'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
