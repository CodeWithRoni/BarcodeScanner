import { useMemo, useState } from "react";
import { AlertTriangle, Check, ClipboardCopy, Copy, Download, History, Keyboard, ListChecks, PauseCircle, QrCode, ScanBarcode, Search, Trash2 } from "lucide-react";
import type { Delivery, ScanEntry } from "../lib/types";
import { clockTime, formatLabel, isTwoD, timeAgo } from "../lib/format";
import { CardHeader, cx } from "./ui";

type Filter = "all" | "1d" | "2d" | "failed";

const DELIVERY: Record<Delivery, { icon: typeof Check; label: string; cls: string }> = {
  typed: { icon: Keyboard, label: "Typed", cls: "text-emerald-600 dark:text-emerald-400" },
  copied: { icon: ClipboardCopy, label: "Copied", cls: "text-sky-600 dark:text-sky-400" },
  logged: { icon: ListChecks, label: "Logged", cls: "text-zinc-500" },
  paused: { icon: PauseCircle, label: "Paused", cls: "text-amber-600 dark:text-amber-400" },
  failed: { icon: AlertTriangle, label: "Failed", cls: "text-rose-600 dark:text-rose-400" },
};

export function ScanHistory({
  history,
  freshIds,
  onCopy,
  onExport,
  onClear,
}: {
  history: ScanEntry[];
  freshIds: Set<string>;
  onCopy: (code: string) => void;
  onExport: () => void;
  onClear: () => void;
}) {
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<Filter>("all");
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [confirmClear, setConfirmClear] = useState(false);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return history.filter((e) => {
      if (filter === "1d" && isTwoD(e.format)) return false;
      if (filter === "2d" && !isTwoD(e.format)) return false;
      if (filter === "failed" && e.delivery !== "failed") return false;
      if (!q) return true;
      return e.code.toLowerCase().includes(q) || e.deviceName.toLowerCase().includes(q) || formatLabel(e.format).toLowerCase().includes(q);
    });
  }, [history, query, filter]);

  const today = useMemo(() => {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    return history.filter((e) => e.receivedAt >= start.getTime()).length;
  }, [history]);

  const copy = (entry: ScanEntry) => {
    onCopy(entry.code);
    setCopiedId(entry.id);
    window.setTimeout(() => setCopiedId((id) => (id === entry.id ? null : id)), 1400);
  };

  const filters: Array<{ value: Filter; label: string }> = [
    { value: "all", label: "All" },
    { value: "1d", label: "Barcodes" },
    { value: "2d", label: "2D codes" },
    { value: "failed", label: "Failed" },
  ];

  return (
    <section className="card flex min-h-0 flex-1 flex-col">
      <CardHeader
        title="Live scan history"
        icon={<History className="size-3.5" />}
        action={
          <div className="flex items-center gap-1">
            <span className="mr-2 text-[11.5px] tabular-nums text-zinc-500">
              {today.toLocaleString()} today · {history.length.toLocaleString()} total
            </span>
            <button className="btn btn-outline h-7 px-2.5" onClick={onExport} disabled={history.length === 0}>
              <Download className="size-3.5" /> Export
            </button>
            <button
              className={cx("btn h-7 px-2.5", confirmClear ? "btn-danger" : "btn-ghost")}
              disabled={history.length === 0}
              onClick={() => {
                if (confirmClear) {
                  onClear();
                  setConfirmClear(false);
                } else {
                  setConfirmClear(true);
                  window.setTimeout(() => setConfirmClear(false), 3500);
                }
              }}
            >
              <Trash2 className="size-3.5" /> {confirmClear ? "Confirm" : "Clear"}
            </button>
          </div>
        }
      />
      <div className="flex items-center gap-2 px-5 pb-3">
        <div className="relative flex-1">
          <Search className="pointer-events-none absolute top-1/2 left-3 size-3.5 -translate-y-1/2 text-zinc-400" />
          <input className="input pl-8" placeholder="Search codes, formats or devices" value={query} onChange={(e) => setQuery(e.target.value)} spellCheck={false} />
        </div>
        <div className="flex rounded-lg bg-zinc-100 p-0.5 dark:bg-white/[0.05]">
          {filters.map((f) => (
            <button
              key={f.value}
              onClick={() => setFilter(f.value)}
              className={cx(
                "h-8 rounded-md px-2.5 text-[12px] font-medium transition",
                filter === f.value ? "bg-white text-zinc-900 shadow-sm dark:bg-white/10 dark:text-white" : "text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200",
              )}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto border-t border-zinc-200/70 dark:border-white/[0.06]">
        {filtered.length === 0 ? (
          <div className="flex h-full min-h-[220px] flex-col items-center justify-center gap-2 px-6 text-center">
            <div className="flex size-12 items-center justify-center rounded-2xl bg-zinc-100 text-zinc-400 dark:bg-white/[0.05]">
              <ScanBarcode className="size-6" />
            </div>
            <div className="text-[13.5px] font-semibold">{history.length === 0 ? "No scans yet" : "Nothing matches"}</div>
            <p className="max-w-[300px] text-[12.5px] text-zinc-500 dark:text-zinc-400">
              {history.length === 0 ? "Scanned codes appear here the moment your phone sends them." : "Try a different search or filter."}
            </p>
          </div>
        ) : (
          <ul className="divide-y divide-zinc-200/60 dark:divide-white/[0.05]">
            {filtered.map((entry) => {
              const d = DELIVERY[entry.delivery];
              const DIcon = d.icon;
              const two = isTwoD(entry.format);
              return (
                <li
                  key={entry.id}
                  className={cx("group flex items-center gap-3 px-5 py-2.5 transition-colors hover:bg-zinc-50 dark:hover:bg-white/[0.025]", freshIds.has(entry.id) && "animate-row-in")}
                >
                  <div className={cx("flex size-8 shrink-0 items-center justify-center rounded-lg", two ? "bg-violet-500/10 text-violet-600 dark:text-violet-400" : "bg-indigo-500/10 text-indigo-600 dark:text-indigo-400")}>
                    {two ? <QrCode className="size-4" /> : <ScanBarcode className="size-4" />}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-mono text-[13px] font-medium selectable" title={entry.code}>
                      {entry.code}
                    </div>
                    <div className="mt-0.5 flex items-center gap-2 text-[11.5px] text-zinc-500 dark:text-zinc-400">
                      <span className="rounded bg-zinc-100 px-1.5 py-px text-[10.5px] font-medium text-zinc-600 dark:bg-white/[0.06] dark:text-zinc-300">{formatLabel(entry.format)}</span>
                      <span className="truncate">{entry.deviceName}</span>
                      <span className={cx("inline-flex items-center gap-1", d.cls)} title={entry.error}>
                        <DIcon className="size-3" /> {d.label}
                      </span>
                    </div>
                  </div>
                  <div className="text-right text-[11.5px] tabular-nums text-zinc-400" title={new Date(entry.receivedAt).toLocaleString()}>
                    <div>{clockTime(entry.receivedAt)}</div>
                    <div className="text-[10.5px]">{timeAgo(entry.receivedAt)}</div>
                  </div>
                  <button className={cx("icon-btn size-7 transition", copiedId === entry.id ? "!text-emerald-500" : "opacity-0 group-hover:opacity-100 focus:opacity-100")} onClick={() => copy(entry)} title="Copy code">
                    {copiedId === entry.id ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </section>
  );
}
