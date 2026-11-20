import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { save } from "@tauri-apps/plugin-dialog";
import type { ScanEntry, SettingsPatch, Snapshot } from "./types";

export const isTauri = (): boolean => typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

export const api = {
  getSnapshot: () => invoke<Snapshot>("get_snapshot"),
  getHistory: () => invoke<ScanEntry[]>("get_history"),
  updateSettings: (patch: SettingsPatch) => invoke<Snapshot>("update_settings", { patch }),
  respondPairing: (requestId: string, accept: boolean) => invoke<void>("respond_pairing", { requestId, accept }),
  disconnectDevice: (deviceId: string, forget: boolean) => invoke<void>("disconnect_device", { deviceId, forget }),
  resetPairing: () => invoke<void>("reset_pairing"),
  clearHistory: () => invoke<void>("clear_history"),
  copyText: (text: string) => invoke<void>("copy_text", { text }),
  hideWindow: () => invoke<void>("hide_window"),
  quitApp: () => invoke<void>("quit_app"),

  async exportHistory(): Promise<{ path: string; count: number } | null> {
    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
    const path = await save({
      title: "Export scan history",
      defaultPath: `barcodesync-scans-${stamp}.csv`,
      filters: [
        { name: "CSV spreadsheet", extensions: ["csv"] },
        { name: "JSON", extensions: ["json"] },
        { name: "Plain text (codes only)", extensions: ["txt"] },
      ],
    });
    if (!path) return null;
    const count = await invoke<number>("export_history", { path });
    return { path, count };
  },

  onState: (cb: (s: Snapshot) => void): Promise<UnlistenFn> => listen<Snapshot>("state", (e) => cb(e.payload)),
  onScan: (cb: (s: ScanEntry) => void): Promise<UnlistenFn> => listen<ScanEntry>("scan", (e) => cb(e.payload)),
};

export function errorMessage(err: unknown): string {
  if (typeof err === "string") return err;
  if (err instanceof Error) return err.message;
  return "Something went wrong";
}
