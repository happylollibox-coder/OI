export function PageHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div className="flex items-baseline gap-2.5 mb-5">
      <h1 className="text-[22px] font-extrabold tracking-tight">{title}</h1>
      {subtitle && <span className="text-xs text-subtle">{subtitle}</span>}
    </div>
  );
}
