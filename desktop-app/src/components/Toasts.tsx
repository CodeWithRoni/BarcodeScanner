import { AlertCircle, CheckCircle2, Info, ScanLine, X } from "lucide-react";
import type { Toast } from "../hooks/useBackend";
import { cx } from "./ui";

const ICONS = {
  scan: { icon: ScanLine, cls: "bg-accent-500 text-white" },
  success: { icon: CheckCircle2, cls: "bg-emerald-500 text-white" },
  error: { icon: AlertCircle, cls: "bg-rose-500 text-white" },
  info: { icon: Info, cls: "bg-zinc-700 text-white" },
};

export function Toasts({ toasts, onDismiss }: { toasts: Toast[]; onDismiss: (id: string) => void }) {
  return (
    <div className="pointer-events-none fixed right-5 bottom-5 z-50 flex w-[340px] flex-col gap-2">
      {toasts.map((t) => {
        const meta = ICONS[t.kind];
        const Icon = meta.icon;
        return (
          <div
            key={t.id}
            role="status"
            className="pointer-events-auto flex items-start gap-3 rounded-xl border border-zinc-200/80 bg-white/90 p-3 shadow-xl shadow-zinc-900/10 backdrop-blur-xl animate-toast-in dark:border-white/10 dark:bg-[#17181d]/90 dark:shadow-black/40"
          >
            <span className={cx("flex size-7 shrink-0 items-center justify-center rounded-lg", meta.cls)}>
              <Icon className="size-4" />
            </span>
            <div className="min-w-0 flex-1">
              <div className="text-[12.5px] font-semibold">{t.title}</div>
              {t.body && <div className={cx("mt-0.5 truncate text-[12px] text-zinc-500 dark:text-zinc-400", t.mono && "font-mono")}>{t.body}</div>}
            </div>
            <button className="icon-btn -mr-1 size-6" onClick={() => onDismiss(t.id)} aria-label="Dismiss">
              <X className="size-3.5" />
            </button>
          </div>
        );
      })}
    </div>
  );
}
