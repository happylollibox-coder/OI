export function Empty({ icon = '📊', message = 'No data available', hint, action }: {
  icon?: string;
  message?: string;
  hint?: string;
  action?: { label: string; onClick: () => void };
}) {
  return (
    <div className="text-center py-14 px-6 text-faint rounded-xl border border-border-faint bg-card/50 backdrop-blur-sm animate-in">
      <div className="text-4xl mb-3 opacity-40">{icon}</div>
      <div className="text-sm font-medium mb-1.5 text-subtle">{message}</div>
      {hint && (
        <div className="text-[11px] text-faint max-w-xs mx-auto leading-relaxed">
          {hint}
        </div>
      )}
      {action && (
        <button
          onClick={action.onClick}
          className="mt-4 px-4 py-1.5 rounded-lg bg-blue-500/10 border border-blue-500/20 text-blue-400 text-[11px] font-semibold hover:bg-blue-500/20 transition-all duration-200"
        >
          {action.label}
        </button>
      )}
    </div>
  );
}
