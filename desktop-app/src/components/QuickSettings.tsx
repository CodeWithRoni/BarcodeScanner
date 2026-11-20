import type { ReactNode } from "react";
import { ClipboardCopy, CornerDownLeft, Keyboard, ListChecks, Pause, Play, Power, SlidersHorizontal, Volume2, Minimize2 } from "lucide-react";
import type { OutputMode, Settings, SettingsPatch } from "../lib/types";
import { CardHeader, Segmented, Switch, cx } from "./ui";

const MODE_HINT: Record<OutputMode, string> = {
  keyboard: "Types each code into whichever app has focus.",
  clipboard: "Copies each code so you can paste it anywhere.",
  log: "Only records scans in the history below.",
};

function Row({
  icon,
  title,
  hint,
  children,
  disabled,
}: {
  icon: ReactNode;
  title: string;
  hint?: string;
  children: ReactNode;
  disabled?: boolean;
}) {
  return (
    <div className={cx("flex items-center gap-3 py-2.5 transition-opacity", disabled && "opacity-50")}>
      <div className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-zinc-100 text-zinc-600 dark:bg-white/[0.05] dark:text-zinc-300">{icon}</div>
      <div className="min-w-0 flex-1">
        <div className="text-[13px] font-medium">{title}</div>
        {hint && <div className="truncate text-[11.5px] text-zinc-500 dark:text-zinc-400">{hint}</div>}
      </div>
      {children}
    </div>
  );
}

export function QuickSettings({ settings, onChange }: { settings: Settings; onChange: (patch: SettingsPatch) => void }) {
  return (
    <section className="card">
      <CardHeader
        title="Quick actions"
        icon={<SlidersHorizontal className="size-3.5" />}
        action={
          <button
            className={cx("btn h-7 px-2.5", settings.paused ? "btn-primary" : "btn-outline")}
            onClick={() => onChange({ paused: !settings.paused })}
          >
            {settings.paused ? <Play className="size-3.5" /> : <Pause className="size-3.5" />}
            {settings.paused ? "Resume" : "Pause"}
          </button>
        }
      />
      <div className="px-5 pb-2">
        <div className="mb-1.5 text-[11px] font-medium text-zinc-500 dark:text-zinc-400">Output mode</div>
        <Segmented<OutputMode>
          value={settings.outputMode}
          onChange={(outputMode) => onChange({ outputMode })}
          options={[
            { value: "keyboard", label: "Type", icon: <Keyboard className="size-3.5" /> },
            { value: "clipboard", label: "Clipboard", icon: <ClipboardCopy className="size-3.5" /> },
            { value: "log", label: "Log only", icon: <ListChecks className="size-3.5" /> },
          ]}
        />
        <p className="mt-2 text-[11.5px] text-zinc-500 dark:text-zinc-400">{MODE_HINT[settings.outputMode]}</p>
      </div>
      <div className="divide-y divide-zinc-200/70 px-5 pb-3 dark:divide-white/[0.06]">
        <Row icon={<CornerDownLeft className="size-4" />} title="Auto-Enter" hint="Press Enter after typing" disabled={settings.outputMode !== "keyboard"}>
          <Switch label="Auto-Enter" checked={settings.autoEnter} disabled={settings.outputMode !== "keyboard"} onChange={(autoEnter) => onChange({ autoEnter })} />
        </Row>
        <Row icon={<Volume2 className="size-4" />} title="Sound feedback" hint="Chime when a scan arrives">
          <Switch label="Sound feedback" checked={settings.soundFeedback} onChange={(soundFeedback) => onChange({ soundFeedback })} />
        </Row>
        <Row icon={<Power className="size-4" />} title="Launch at login" hint="Start with your computer">
          <Switch label="Launch at login" checked={settings.launchOnStartup} onChange={(launchOnStartup) => onChange({ launchOnStartup })} />
        </Row>
        <Row icon={<Minimize2 className="size-4" />} title="Start minimized" hint="Open quietly in the system tray">
          <Switch label="Start minimized" checked={settings.startMinimized} onChange={(startMinimized) => onChange({ startMinimized })} />
        </Row>
      </div>
    </section>
  );
}
