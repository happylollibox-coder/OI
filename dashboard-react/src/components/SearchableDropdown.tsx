import { useState, useRef, useEffect } from 'react';
import { ChevronDown, X } from 'lucide-react';

interface SearchableDropdownProps {
  value: string;
  onChange: (value: string) => void;
  options: string[];
  placeholder: string;
  activeClass?: string;
  includeOther?: boolean;
}

export function SearchableDropdown({
  value,
  onChange,
  options,
  placeholder,
  activeClass = 'border-blue-500/40 text-blue-400',
  includeOther = true,
}: SearchableDropdownProps) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');
  const ref = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  useEffect(() => {
    if (open && inputRef.current) inputRef.current.focus();
  }, [open]);

  const filtered = options.filter(o => o.toLowerCase().includes(search.toLowerCase()));
  const displayLabel = value === '__OTHER__' ? 'Other' : value || placeholder;

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => { setOpen(!open); setSearch(''); }}
        className={`flex items-center gap-1 px-2 py-1 text-[10px] bg-white/[0.04] border rounded-md transition-all whitespace-nowrap ${
          value ? activeClass : 'border-border text-muted'
        }`}
      >
        <span className="max-w-[100px] truncate">{displayLabel}</span>
        {value ? (
          <X
            size={10}
            className="opacity-60 hover:opacity-100 shrink-0"
            onClick={e => { e.stopPropagation(); onChange(''); setOpen(false); }}
          />
        ) : (
          <ChevronDown size={10} className="opacity-40 shrink-0" />
        )}
      </button>

      {open && (
        <div className="absolute top-full left-0 mt-1 z-50 w-48 bg-[#1a1a2e] border border-border/50 rounded-lg shadow-xl overflow-hidden">
          <div className="p-1.5 border-b border-border/30">
            <input
              ref={inputRef}
              type="text"
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder={`Search ${placeholder.toLowerCase()}...`}
              className="w-full px-2 py-1 text-[10px] bg-white/[0.06] border border-border/30 rounded text-heading placeholder:text-muted/50 focus:outline-none focus:border-blue-500/40"
            />
          </div>
          <div className="max-h-48 overflow-y-auto">
            <button
              onClick={() => { onChange(''); setOpen(false); }}
              className={`w-full text-left px-3 py-1.5 text-[10px] hover:bg-white/[0.06] transition-colors ${
                !value ? 'text-blue-400 font-semibold' : 'text-muted'
              }`}
            >
              All ({placeholder})
            </button>
            {filtered.map(opt => (
              <button
                key={opt}
                onClick={() => { onChange(opt); setOpen(false); }}
                className={`w-full text-left px-3 py-1.5 text-[10px] hover:bg-white/[0.06] transition-colors ${
                  value === opt ? 'text-blue-400 font-semibold' : 'text-heading'
                }`}
              >
                {opt}
              </button>
            ))}
            {includeOther && (
              <button
                onClick={() => { onChange('__OTHER__'); setOpen(false); }}
                className={`w-full text-left px-3 py-1.5 text-[10px] hover:bg-white/[0.06] transition-colors italic ${
                  value === '__OTHER__' ? 'text-blue-400 font-semibold' : 'text-muted'
                }`}
              >
                Other (unclassified)
              </button>
            )}
            {filtered.length === 0 && (
              <div className="px-3 py-2 text-[9px] text-muted italic">No matches</div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
