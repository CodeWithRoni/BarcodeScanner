import { EyeOff, Monitor, Moon, ScanLine, Sun } from "lucide-react";
import type { ThemePreference } from "../hooks/useTheme";
import type { Snapshot } from "../lib/types";
import { cx, Dot } from "./ui";

export function Header({
  snapshot,
  theme,
  onCycleTheme,
  onHide,
}: {
  snapshot: Snapshot | null;
  theme: ThemePreference;
  onCycleTheme: () => void;
  onHide: () => void;
}) {
  const status = snapshot?.status ?? "waiting";
  const count = snapshot?.devices.length ?? 0;
  const pill =
    status === "connected"
      ? {
          tone: "green" as const,
          text: count > 1 ? `${count} phones connected` : `Connected to ${snapshot?.devices[0]?.deviceName ?? "phone"}`,
          cls: "border-emerald-500/25 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300",
        }
      : status === "paused"
        ? { tone: "amber" as const, text: "Scanning paused", cls: "border-amber-500/25 bg-amber-500/10 text-amber-700 dark:text-amber-300" }
        : {
            tone: "zinc" as const,
            text: "Waiting for a phone",
            cls: "border-zinc-200 bg-white/70 text-zinc-600 dark:border-white/10 dark:bg-white/[0.04] dark:text-zinc-300",
          };

  const ThemeIcon = theme === "dark" ? Moon : theme === "light" ? Sun : Monitor;

  return (
    <header className="flex h-14 shrink-0 items-center justify-between border-b border-zinc-200/70 px-5 dark:border-white/[0.06]">
      <div className="flex items-center gap-2.5">
        <div className="flex size-8 items-center justify-center rounded-[10px] bg-gradient-to-br from-indigo-500 to-violet-500 text-white shadow-md shadow-indigo-500/30">
          <ScanLine className="size-[18px]" strokeWidth={2.2} />
        </div>
        <div className="leading-tight">
          <div className="text-[14px] font-semibold tracking-tight">BarcodeSync</div>
          <div className="text-[11px] text-zinc-500 dark:text-zinc-400">{snapshot?.server.desktopName ?? "Desktop"}</div>
        </div>
      </div>

      <div className={cx("flex items-center gap-2 rounded-full border px-3 py-1 text-[12px] font-medium transition-colors", pill.cls)}>
        <Dot tone={pill.tone} pulse={status !== "paused"} />
        <span className="max-w-[280px] truncate">{pill.text}</span>
      </div>

      <div className="flex items-center gap-1">
        <button className="icon-btn" onClick={onCycleTheme} title={`Theme: ${theme}`} aria-label="Change theme">
          <ThemeIcon className="size-4" />
        </button>
        <button className="icon-btn" onClick={onHide} title="Hide to tray" aria-label="Hide to tray">
          <EyeOff className="size-4" />
        </button>
      </div>
    </header>
  );
}
