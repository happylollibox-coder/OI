import type { ProductInfo } from './types';

interface FamilyTabsProps {
  products: ProductInfo[];
  selected: string;
  onSelect: (name: string) => void;
}

export function FamilyTabs({ products, selected, onSelect }: FamilyTabsProps) {
  return (
    <div className="flex gap-2 mb-5 overflow-x-auto pb-1">
      {products.map(p => {
        const isActive = p.name === selected;
        const profitColor = p.ads_profit > 0 ? 'text-emerald-400' : p.ads_profit < 0 ? 'text-red-400' : 'text-muted';
        return (
          <button
            key={p.name}
            onClick={() => onSelect(p.name)}
            className={`flex flex-col items-start px-4 py-2.5 rounded-lg border transition-all cursor-pointer whitespace-nowrap ${
              isActive
                ? 'border-blue-500/40 bg-blue-500/10 shadow-sm shadow-blue-500/10'
                : 'border-border/30 bg-white/[0.02] hover:border-border/60 hover:bg-white/[0.04]'
            }`}
          >
            <span className={`text-sm font-bold ${isActive ? 'text-blue-400' : 'text-heading'}`}>{p.name}</span>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="text-[10px] text-muted">${p.price}</span>
              <span className="text-[10px] text-faint">·</span>
              <span className="text-[10px] text-muted">{p.product_count} SKUs</span>
              {p.ads_units > 0 && (
                <>
                  <span className="text-[10px] text-faint">·</span>
                  <span className="text-[10px] text-muted">{p.ads_units} sold</span>
                </>
              )}
              {p.ads_cps != null && (
                <>
                  <span className="text-[10px] text-faint">·</span>
                  <span className="text-[10px] text-muted">{p.ads_cps} CPS</span>
                </>
              )}
              {p.ads_profit !== 0 && (
                <>
                  <span className="text-[10px] text-faint">·</span>
                  <span className={`text-[10px] font-medium ${profitColor}`}>
                    {p.ads_profit > 0 ? '+' : ''}${Math.abs(p.ads_profit).toLocaleString(undefined, { maximumFractionDigits: 0 })}
                  </span>
                </>
              )}
            </div>
          </button>
        );
      })}
    </div>
  );
}
