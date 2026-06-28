/**
 * ProductSelect — searchable product picker with parent grouping.
 *
 * Grouping strategy: SearchableDropdown accepts only `string[]` options and a
 * `string` value — it has no native group/section support.  We simulate
 * grouping by prefixing every option label with "[ParentName] " so the parent
 * context is visible in both the list and the filter search.  A separate
 * Map<label, product_id> resolves the selected label back to a numeric id.
 */
import { useEffect, useMemo, useState } from 'react';
import { SearchableDropdown } from '../SearchableDropdown';
import { dataEntry, type Product } from '../../utils/dataEntry';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Build the display label that will appear in the dropdown option. */
function productLabel(p: Product): string {
  const base = p.product_short_name ?? p.sku ?? p.product_name ?? p.display_name ?? `Product ${p.product_id}`;
  const group = p.parent_name ?? 'Other';
  // Prefix with group so search on parent name works too.
  return `[${group}] ${base}`;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

interface ProductSelectProps {
  // product_id is a >2^53 int — kept as a string so the JS number type can't round it.
  value: string | null;
  onChange: (id: string) => void;
  required?: boolean;
}

export function ProductSelect({ value, onChange, required = false }: ProductSelectProps) {
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  // Fetch on mount
  useEffect(() => {
    let cancelled = false;
    dataEntry
      .listProducts()
      .then((data) => {
        if (!cancelled) {
          setProducts(data);
          setLoading(false);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setError(true);
          setLoading(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // Build options list and a reverse map label → product_id.
  // Products are already sorted by parent_name then product_short_name from the
  // API (ORDER BY COALESCE(parent_name,'zzz'), product_short_name, product_name).
  const { options, labelToId } = useMemo(() => {
    const opts: string[] = [];
    const map = new Map<string, string>();
    for (const p of products) {
      const label = productLabel(p);
      opts.push(label);
      map.set(label, p.product_id);
    }
    return { options: opts, labelToId: map };
  }, [products]);

  // Derive the currently-selected label from value prop.
  const selectedLabel = useMemo(() => {
    if (value === null) return '';
    const found = products.find((p) => p.product_id === value);
    return found ? productLabel(found) : '';
  }, [value, products]);

  function handleChange(label: string) {
    if (!label) return; // cleared
    const id = labelToId.get(label);
    if (id !== undefined) onChange(id);
  }

  const placeholder = loading ? 'Loading products…' : error ? 'Error loading products' : 'Select product';

  return (
    <div className={required && !value ? 'ring-1 ring-[var(--color-negative)]/40 rounded-md' : ''}>
      <SearchableDropdown
        value={selectedLabel}
        onChange={handleChange}
        options={options}
        placeholder={placeholder}
        includeOther={false}
      />
    </div>
  );
}
