export function PageSelect<T extends string>({ label, value, onChange, options }: {
  label: string;
  value: T;
  onChange: (v: T) => void;
  options: { value: T; label: string }[];
}) {
  return (
    <>
      <label className="text-[10px] text-subtle uppercase tracking-wider font-semibold ml-2 first:ml-0">{label}</label>
      <select
        value={value}
        onChange={e => onChange(e.target.value as T)}
        className="bg-[#09090b] border border-border text-white px-2.5 py-1.5 rounded-lg text-[11px] focus:outline-none focus:border-blue-500"
      >
        {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
    </>
  );
}
