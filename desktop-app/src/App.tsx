import { AlertTriangle, Loader2 } from "lucide-react";
import { DevicesCard } from "./components/DevicesCard";
import { Header } from "./components/Header";
import { PairingCard } from "./components/PairingCard";
import { QuickSettings } from "./components/QuickSettings";
import { ScanHistory } from "./components/ScanHistory";
import { Toasts } from "./components/Toasts";
import { useBackend } from "./hooks/useBackend";
import { useTheme } from "./hooks/useTheme";
import { api } from "./lib/api";

export default function App() {
  const theme = useTheme();
  const { snapshot, history, toasts, freshIds, fatal, dismiss, run, updateSettings, clearHistory } = useBackend();

  return (
    <div className="relative flex h-full flex-col overflow-hidden">
      <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
        <div className="absolute -top-40 left-1/4 h-80 w-[36rem] rounded-full bg-indigo-400/15 blur-3xl dark:bg-indigo-500/10" />
        <div className="absolute -right-24 -bottom-40 h-80 w-[30rem] rounded-full bg-violet-400/10 blur-3xl dark:bg-violet-500/[0.07]" />
      </div>

      <div className="relative flex h-full flex-col">
        <Header snapshot={snapshot} theme={theme.preference} onCycleTheme={theme.cycle} onHide={() => void run(api.hideWindow)} />

        {fatal ? (
          <div className="flex flex-1 items-center justify-center p-8">
            <div className="card max-w-md p-6 text-center">
              <AlertTriangle className="mx-auto size-8 text-amber-500" />
              <div className="mt-3 text-[15px] font-semibold">Dashboard unavailable</div>
              <p className="mt-1 text-[13px] text-zinc-500 dark:text-zinc-400">{fatal}</p>
            </div>
          </div>
        ) : !snapshot ? (
          <div className="flex flex-1 items-center justify-center text-zinc-400">
            <Loader2 className="size-6 animate-spin" />
          </div>
        ) : (
          <main className="grid min-h-0 flex-1 grid-cols-[minmax(340px,400px)_1fr] gap-4 p-4">
            <div className="flex min-h-0 flex-col gap-4 overflow-y-auto pr-0.5">
              <DevicesCard
                devices={snapshot.devices}
                pending={snapshot.pending}
                nearby={snapshot.nearby}
                onRespond={(requestId, accept) => void run(() => api.respondPairing(requestId, accept), accept ? "Phone paired" : undefined)}
                onDisconnect={(deviceId, forget) => void run(() => api.disconnectDevice(deviceId, forget), forget ? "Phone forgotten" : "Disconnected")}
              />
              <QuickSettings settings={snapshot.settings} onChange={(patch) => void updateSettings(patch)} />
              <PairingCard
                server={snapshot.server}
                onCopy={(text, label) => void run(() => api.copyText(text), label)}
                onReset={() => void run(api.resetPairing, "New pairing code issued")}
              />
            </div>
            <div className="flex min-h-0 flex-col">
              <ScanHistory
                history={history}
                freshIds={freshIds}
                onCopy={(code) => void run(() => api.copyText(code))}
                onClear={() => void clearHistory()}
                onExport={async () => {
                  const result = await run(api.exportHistory);
                  if (result) void run(async () => undefined, `Exported ${result.count.toLocaleString()} scans`);
                }}
              />
            </div>
          </main>
        )}
      </div>

      <Toasts toasts={toasts} onDismiss={dismiss} />
    </div>
  );
}
