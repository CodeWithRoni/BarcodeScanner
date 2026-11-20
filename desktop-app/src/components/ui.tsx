import type { ReactNode } from "react";

export function cx(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(" ");
}

export function Switch({
  checked,
  onChange,
  label,
  disabled,
}: {
  checked: boolean;
  onChange: (value: boolean) => void;
  label: string;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={cx(
        "relative inline-flex h-[22px] w-[38px] shrink-0 items-center rounded-full transition-colors duration-200 outline-none focus-visible:ring-2 focus-visible:ring-accent-500/60 disabled:opacity-50",
        checked ? "bg-accent-500" : "bg-zinc-300 dark:bg-white/15",
      )}
    >
      <span
        className={cx(
          "inline-block size-[18px] rounded-full bg-white shadow-[0_1px_3px_rgba(0,0,0,0.25)] transition-transform duration-200 ease-[cubic-bezier(0.3,1.4,0.5,1)]",
          checked ? "translate-x-[18px]" : "translate-x-[2px]",
        )}
      />
    </button>
  );
}

export interface SegmentOption<T extends string> {
  value: T;
  label: string;
  icon?: ReactNode;
}

export function Segmented<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T;
  options: SegmentOption<T>[];
  onChange: (value: T) => void;
}) {
  const index = Math.max(
    0,
    options.findIndex((o) => o.value === value),
  );
  return (
    <div className="relative grid rounded-xl bg-zinc-100 p-1 dark:bg-white/[0.05]" style={{ gridTemplateColumns: `repeat(${options.length}, minmax(0, 1fr))` }}>
      <span
        aria-hidden
        className="absolute top-1 bottom-1 rounded-lg bg-white shadow-sm ring-1 ring-zinc-200/70 transition-transform duration-300 ease-[cubic-bezier(0.3,1.2,0.4,1)] dark:bg-white/10 dark:ring-white/10"
        style={{ width: `calc((100% - 0.5rem) / ${options.length})`, transform: `translateX(${index * 100}%)`, left: "0.25rem" }}
      />
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          onClick={() => onChange(o.value)}
          className={cx(
            "relative z-10 flex h-8 items-center justify-center gap-1.5 rounded-lg text-[12.5px] font-medium transition-colors outline-none focus-visible:ring-2 focus-visible:ring-accent-500/60",
            o.value === value ? "text-zinc-900 dark:text-white" : "text-zinc-500 hover:text-zinc-800 dark:text-zinc-400 dark:hover:text-zinc-200",
          )}
        >
          {o.icon}
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function CardHeader({ title, icon, action }: { title: string; icon?: ReactNode; action?: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 px-5 pt-4 pb-3">
      <div className="flex items-center gap-2">
        {icon && <span className="text-zinc-400 dark:text-zinc-500">{icon}</span>}
        <h2 className="card-title">{title}</h2>
      </div>
      {action}
    </div>
  );
}

export function Dot({ tone, pulse }: { tone: "green" | "amber" | "zinc" | "rose"; pulse?: boolean }) {
  const color = {
    green: "bg-emerald-500",
    amber: "bg-amber-500",
    zinc: "bg-zinc-400",
    rose: "bg-rose-500",
  }[tone];
  return (
    <span className="relative inline-flex size-2">
      {pulse && <span className={cx("absolute inline-flex size-full rounded-full animate-ping-slow", color)} />}
      <span className={cx("relative inline-flex size-2 rounded-full", color)} />
    </span>
  );
}
