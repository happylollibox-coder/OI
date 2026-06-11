import { TrendingUp } from 'lucide-react';
import { fmt } from '../../utils';
import type { ConversionCurveRow, ProductInfo } from './types';

interface ConversionCurveCardProps {
  curve: ConversionCurveRow[];
  products: ProductInfo[];
  selectedProduct: string;
}

export function ConversionCurveCard({ curve, products, selectedProduct }: ConversionCurveCardProps) {
  const familyProducts = products.filter(p => p.name === selectedProduct);
  if (familyProducts.length === 0 || curve.length === 0) return null;
  const fp = familyProducts[0];

  const bucketDefs = [
    { key: 'B. Sweet spot', label: '🎯 Sweet Spot', color: 'text-emerald-400' },
    { key: 'C. Pricier', label: '⬆️ Pricier', color: 'text-amber-400' },
    { key: 'D. Much pricier', label: '⬆️⬆️ Much Pricier', color: 'text-orange-400' },
    { key: 'E. Way above', label: '🔴 Way Above', color: 'text-red-400' },
  ];

  const hasOwn = curve.some(c => c.parent_name === selectedProduct);
  const src = hasOwn ? selectedProduct : '_ALL';

  const getPriceRange = (bucketKey: string) => {
    const row = curve.find(c => c.parent_name === src && c.price_bucket === bucketKey && c.holiday_name === '_ALL');
    if (!row || !fp.price) return '';
    const lo = Math.round(fp.price * row.price_ratio_low);
    const hi = row.price_ratio_high >= 99 ? '∞' : `$${Math.round(fp.price * row.price_ratio_high)}`;
    return `$${lo}–${hi}`;
  };

  const getCps = (bucket: string, season: string) => {
    const row = curve.find(c => c.parent_name === src && c.price_bucket === bucket && c.holiday_name === season);
    return row?.clicks_per_sale ?? null;
  };
  const allSweet = getCps('B. Sweet spot', '_ALL');
  const xmasSweet = getCps('B. Sweet spot', 'Christmas');
  const xmasBoost = allSweet && xmasSweet ? Math.round((1 - xmasSweet / allSweet) * 100) : null;

  return (
    <div className="mb-6">
      <h3 className="text-xs font-bold text-heading mb-3 flex items-center gap-2">
        <TrendingUp size={14} className="text-blue-400" />
        Conversion Curves — Est. Clicks Per Sale
      </h3>
      <div className="overflow-x-auto -mx-1">
        <table className="w-full text-[11px]">
          <thead>
            <tr className="border-b border-border/30">
              <th className="px-3 py-2 text-[9px] text-muted font-semibold uppercase tracking-wide text-left">Product</th>
              <th className="px-3 py-2 text-[9px] text-muted font-semibold uppercase tracking-wide text-center">Curve Source</th>
              {bucketDefs.map(bd => (
                <th key={bd.key} className={`px-3 py-2 text-[9px] ${bd.color} font-semibold uppercase tracking-wide text-right`}>
                  <div>{bd.label}</div>
                  <div className="text-[8px] font-normal opacity-60">{getPriceRange(bd.key)}</div>
                </th>
              ))}
              <th className="px-3 py-2 text-[9px] text-blue-400 font-semibold uppercase tracking-wide text-right">🎄 Xmas Boost</th>
            </tr>
          </thead>
          <tbody>
            <tr className="border-b border-border/10 hover:bg-white/[0.02]">
              <td className="px-3 py-2 text-heading font-medium">{fp.name} <span className="text-muted font-normal text-[10px]">${fp.price}</span></td>
              <td className="px-3 py-2 text-center">
                <span className={`inline-block px-1.5 py-0.5 rounded text-[8px] font-bold ${hasOwn ? 'bg-emerald-500/15 text-emerald-400' : 'bg-blue-500/15 text-blue-400'}`}>
                  {hasOwn ? 'OWN CURVE' : 'GLOBAL'}
                </span>
              </td>
              <td className="px-3 py-2 text-right text-emerald-400 font-semibold tabular-nums">{allSweet != null ? fmt(allSweet, 1) : '--'}</td>
              <td className="px-3 py-2 text-right text-amber-400 tabular-nums">{getCps('C. Pricier', '_ALL') != null ? fmt(getCps('C. Pricier', '_ALL')!, 1) : '--'}</td>
              <td className="px-3 py-2 text-right text-orange-400 tabular-nums">{getCps('D. Much pricier', '_ALL') != null ? fmt(getCps('D. Much pricier', '_ALL')!, 1) : '--'}</td>
              <td className="px-3 py-2 text-right text-red-400 tabular-nums">{getCps('E. Way above', '_ALL') != null ? fmt(getCps('E. Way above', '_ALL')!, 1) : '--'}</td>
              <td className="px-3 py-2 text-right tabular-nums">
                {xmasBoost != null ? (
                  <span className={xmasBoost > 0 ? 'text-emerald-400' : 'text-red-400'}>
                    {xmasBoost > 0 ? '↓' : '↑'}{Math.abs(xmasBoost)}% clicks
                  </span>
                ) : '--'}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p className="text-[9px] text-muted mt-2">
        Price ranges show the median click price range for each tier based on {selectedProduct}'s ${fp.price} price.
        {' '}<span className={`font-medium ${hasOwn ? 'text-emerald-400' : 'text-blue-400'}`}>{hasOwn ? 'OWN CURVE' : 'GLOBAL'}</span> — {hasOwn ? 'based on this family\'s ad history' : 'using all-product average (new product)'}.
      </p>
    </div>
  );
}
