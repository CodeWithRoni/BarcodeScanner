import { useCallback, useEffect, useRef, useState } from "react";
import { api, errorMessage, isTauri } from "../lib/api";
import { playError, playSuccess } from "../lib/sound";
import type { ScanEntry, SettingsPatch, Snapshot } from "../lib/types";

export interface Toast {
  id: string;
  kind: "scan" | "success" | "error" | "info";
  title: string;
  body?: string;
  mono?: boolean;
}

export function useBackend() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [history, setHistory] = useState<ScanEntry[]>([]);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [freshIds, setFreshIds] = useState<Set<string>>(new Set());
  const [fatal, setFatal] = useState<string | null>(null);
  const soundRef = useRef(true);

  const dismiss = useCallback((id: string) => setToasts((t) => t.filter((x) => x.id !== id)), []);

  const notify = useCallback(
    (toast: Omit<Toast, "id">, ttl = 3200) => {
      const id = crypto.randomUUID();
      setToasts((t) => [...t.slice(-3), { ...toast, id }]);
      window.setTimeout(() => dismiss(id), ttl);
    },
    [dismiss],
  );

  useEffect(() => {
    if (snapshot) soundRef.current = snapshot.settings.soundFeedback;
  }, [snapshot]);

  useEffect(() => {
    if (!isTauri()) {
      setFatal("BarcodeSync's dashboard must run inside the desktop app. Start it with `npm run tauri dev`.");
      return;
    }
    let disposed = false;
    const unlisteners: Array<() => void> = [];

    (async () => {
      try {
        const [snap, hist] = await Promise.all([api.getSnapshot(), api.getHistory()]);
        if (disposed) return;
        setSnapshot(snap);
        setHistory(hist);
        unlisteners.push(await api.onState((s) => setSnapshot(s)));
        unlisteners.push(
          await api.onScan((entry) => {
            setHistory((h) => [entry, ...h.filter((x) => x.id !== entry.id)].slice(0, 2000));
            setFreshIds((s) => new Set(s).add(entry.id));
            window.setTimeout(
              () =>
                setFreshIds((s) => {
                  const next = new Set(s);
                  next.delete(entry.id);
                  return next;
                }),
              1200,
            );
            const failed = entry.delivery === "failed";
            if (soundRef.current) (failed ? playError : playSuccess)();
            notify(
              failed
                ? { kind: "error", title: "Couldn't deliver scan", body: entry.error ?? entry.code }
                : {
                    kind: "scan",
                    title:
                      entry.delivery === "typed"
                        ? "Typed into focused app"
                        : entry.delivery === "copied"
                          ? "Copied to clipboard"
                          : entry.delivery === "paused"
                            ? "Received while paused"
                            : "Scan received",
                    body: entry.code,
                    mono: true,
                  },
            );
          }),
        );
      } catch (err) {
        if (!disposed) setFatal(errorMessage(err));
      }
    })();

    return () => {
      disposed = true;
      unlisteners.forEach((u) => u());
    };
  }, [notify]);

  const run = useCallback(
    async <T,>(action: () => Promise<T>, success?: string): Promise<T | undefined> => {
      try {
        const result = await action();
        if (success) notify({ kind: "success", title: success }, 2200);
        return result;
      } catch (err) {
        notify({ kind: "error", title: errorMessage(err) }, 4200);
        return undefined;
      }
    },
    [notify],
  );

  const updateSettings = useCallback(
    async (patch: SettingsPatch) => {
      setSnapshot((s) => (s ? { ...s, settings: { ...s.settings, ...patch } } : s));
      const next = await run(() => api.updateSettings(patch));
      if (next) setSnapshot(next);
      else setSnapshot(await api.getSnapshot());
    },
    [run],
  );

  const clearHistory = useCallback(async () => {
    await run(api.clearHistory, "History cleared");
    setHistory([]);
  }, [run]);

  return { snapshot, history, toasts, freshIds, fatal, notify, dismiss, run, updateSettings, clearHistory };
}
