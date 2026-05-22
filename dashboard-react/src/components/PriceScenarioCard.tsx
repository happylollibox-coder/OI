import React, { useState, useEffect } from 'react';
import { fM, fShort, fP } from '../utils';
import { Calculator, ArrowRight, TrendingUp, TrendingDown, Target } from 'lucide-react';

interface Props {
  currentSales: number;
  currentOrders: number;
  currentCogs: number;
  currentAdCost: number;
  currentNetProfit: number;
}

export function PriceScenarioCard({ currentSales, currentOrders, currentCogs, currentAdCost, currentNetProfit }: Props) {
  const currentPrice = currentOrders > 0 ? currentSales / currentOrders : 0;
  
  const [newPriceStr, setNewPriceStr] = useState<string>('');
  const [prevPrice, setPrevPrice] = useState<number>(0);
  
  useEffect(() => {
    // If we receive a new valid price and it's different from the previous valid price, reset the input
    if (currentPrice > 0 && Math.abs(currentPrice - prevPrice) > 0.01) {
      setNewPriceStr(currentPrice.toFixed(2));
      setPrevPrice(currentPrice);
    }
  }, [currentPrice, prevPrice]);

  const newPrice = parseFloat(newPriceStr) || 0;
  
  const fixedUnitCost = currentOrders > 0 
    ? (currentCogs / currentOrders) - (0.15 * currentPrice) 
    : 0;

  const newUnitMargin = newPrice - fixedUnitCost - (0.15 * newPrice);
  
  const targetUnits = newUnitMargin > 0 
    ? Math.max(0, Math.ceil((currentNetProfit + currentAdCost) / newUnitMargin)) 
    : 0;
    
  const unitDiff = targetUnits - currentOrders;
  const unitDiffPct = currentOrders > 0 ? unitDiff / currentOrders : 0;

  const currentUnitMargin = currentOrders > 0 ? currentNetProfit / currentOrders : 0;
  
  // Calculate potential new profit if units stayed EXACTLY the same
  const projectedProfitSameUnits = (newUnitMargin * currentOrders) - currentAdCost;

  return (
    <div className="rounded-xl overflow-hidden relative group"
         style={{ 
           background: 'var(--color-card)', 
           border: '1px solid rgba(236,72,153,0.3)',
           boxShadow: 'var(--shadow-float)'
         }}>
         
      <div className="absolute inset-0 opacity-[0.03] pointer-events-none"
           style={{ background: 'linear-gradient(135deg, rgba(236,72,153,1) 0%, transparent 100%)' }} />

      <div className="p-3">
        <div className="flex items-center gap-2 mb-3">
          <div className="p-1.5 rounded-lg" style={{ background: 'rgba(236,72,153,0.1)', color: '#ec4899' }}>
            <Calculator size={14} />
          </div>
          <div>
            <div className="text-[12px] font-bold" style={{ color: 'var(--color-text)' }}>Price Change Scenario</div>
            <div className="text-[10px]" style={{ color: 'var(--color-faint)' }}>Break-even volume calculator</div>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-4 items-center">
          {/* Left: Input & Context */}
          <div className="space-y-3">
            <div>
              <label className="text-[10px] font-bold uppercase tracking-wider block mb-1" style={{ color: 'var(--color-faint)' }}>
                Target Price
              </label>
              <div className="relative">
                <span className="absolute left-3 top-1/2 -translate-y-1/2 text-[14px] font-semibold" style={{ color: 'var(--color-muted)' }}>$</span>
                <input
                  type="number"
                  value={newPriceStr}
                  onChange={e => setNewPriceStr(e.target.value)}
                  step="0.10"
                  min="0"
                  className="w-full bg-transparent border rounded-lg pl-6 pr-3 py-1.5 text-[14px] font-bold focus:outline-none focus:border-pink-500 transition-colors"
                  style={{ 
                    color: 'var(--color-text)',
                    borderColor: 'var(--color-border)',
                  }}
                />
              </div>
              <div className="flex justify-between text-[10px] mt-1" style={{ color: 'var(--color-faint)' }}>
                <span>Current: ${currentPrice.toFixed(2)}</span>
                <span style={{ color: newUnitMargin >= 0 ? 'var(--color-positive)' : 'var(--color-negative)' }}>Gross Profit/U: ${newUnitMargin.toFixed(2)}</span>
                <span style={{ color: (newUnitMargin - (currentOrders > 0 ? currentAdCost / currentOrders : 0)) >= 0 ? 'var(--color-positive)' : 'var(--color-negative)' }}>Margin/U: ${(newUnitMargin - (currentOrders > 0 ? currentAdCost / currentOrders : 0)).toFixed(2)}</span>
              </div>
            </div>
            
            <div className="flex justify-between items-center p-2 rounded-lg" style={{ background: 'var(--color-inset)' }}>
               <span className="text-[11px]" style={{ color: 'var(--color-faint)' }}>Proj. Profit (Flat Units)</span>
               <span className="text-[12px] font-bold" style={{ color: projectedProfitSameUnits >= currentNetProfit ? '#10b981' : '#ef4444' }}>
                 {fM(projectedProfitSameUnits)}
               </span>
            </div>
          </div>

          {/* Right: Target Outputs */}
          <div className="flex flex-col justify-center items-center p-3 rounded-lg border relative overflow-hidden" 
               style={{ 
                 background: 'var(--color-inset)',
                 borderColor: 'var(--color-border)'
               }}>
            
            <div className="text-[10px] font-bold uppercase tracking-wider mb-1" style={{ color: 'var(--color-faint)' }}>
              Required Units to Break-Even
            </div>
            
            <div className="flex items-end gap-2 mb-1">
              <span className="text-[24px] font-black leading-none tracking-tight" style={{ color: 'var(--color-text)' }}>
                {targetUnits.toLocaleString()}
              </span>
              <span className="text-[11px] font-semibold mb-1" style={{ color: 'var(--color-muted)' }}>units</span>
            </div>
            
            <div className="flex items-center gap-1 text-[11px] font-bold" style={{ color: unitDiff <= 0 ? '#10b981' : '#ef4444' }}>
              {unitDiff <= 0 ? <TrendingDown size={12} /> : <TrendingUp size={12} />}
              {unitDiff > 0 ? '+' : ''}{unitDiff.toLocaleString()} ({fP(unitDiffPct)})
            </div>
            
            <div className="text-[9px] text-center mt-2" style={{ color: 'var(--color-faint)' }}>
              To maintain {fM(currentNetProfit)} net profit with {fM(currentAdCost)} ad spend.
            </div>
            
          </div>
        </div>
      </div>
    </div>
  );
}
