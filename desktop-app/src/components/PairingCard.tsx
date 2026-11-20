import { useState } from "react";
import { Copy, KeyRound, QrCode, RotateCcw } from "lucide-react";
import type { ServerInfo } from "../lib/types";
import { CardHeader, cx, Dot } from "./ui";

export function PairingCard({
  server,
  onCopy,
  onReset,
}: {
  server: ServerInfo;
  onCopy: (text: string, label: string) => void;
  onReset: () => void;
}) {
  const [confirming, setConfirming] = useState(false);
  const address = `${server.host}:${server.port}`;
  const qr = server.qrSvg ? `data:image/svg+xml;utf8,${encodeURIComponent(server.qrSvg)}` : "";

  return (
    <section className="card">
      <CardHeader title="Pair a phone" icon={<QrCode className="size-3.5" />} />
      <div className="flex gap-4 px-5 pb-5">
        <div className="relative shrink-0 self-start rounded-2xl bg-white p-2.5 shadow-sm ring-1 ring-zinc-200 dark:ring-white/10">
          {qr ? (
            <img src={qr} alt="Pairing QR code" className="size-[132px] [image-rendering:pixelated]" draggable={false} />
          ) : (
            <div className="size-[132px] animate-pulse rounded-lg bg-zinc-100" />
          )}
          <span className="pointer-events-none absolute -inset-px rounded-2xl ring-1 ring-accent-500/0 transition hover:ring-accent-500/40" />
        </div>
        <div className="flex min-w-0 flex-1 flex-col">
          <p className="text-[12.5px] leading-relaxed text-zinc-500 dark:text-zinc-400">
            Phones on this Wi-Fi find this computer automatically. If your router blocks discovery, tap <span className="font-medium text-zinc-700 dark:text-zinc-200">Scan pairing code</span> in the app.
          </p>
          <div className="mt-3 flex items-center gap-2 rounded-lg border border-zinc-200 bg-zinc-50 px-2.5 py-1.5 dark:border-white/10 dark:bg-white/[0.03]">
            <span className="font-mono text-[12.5px] font-medium selectable">{address}</span>
            <button className="icon-btn ml-auto size-6" title="Copy address" onClick={() => onCopy(address, "Address copied")}>
              <Copy className="size-3.5" />
            </button>
          </div>
          {server.ips.length > 1 && (
            <div className="mt-1 truncate font-mono text-[11px] text-zinc-400 selectable" title={server.ips.join(", ")}>
              also {server.ips.slice(1).join(", ")}
            </div>
          )}
          <div className="mt-auto flex flex-wrap items-center gap-x-3 gap-y-1 pt-3 text-[11px] text-zinc-500 dark:text-zinc-400">
            <span className="inline-flex items-center gap-1.5">
              <Dot tone={server.wsRunning ? "green" : "rose"} /> WebSocket
            </span>
            <span className="inline-flex items-center gap-1.5">
              <Dot tone={server.mdnsActive ? "green" : "zinc"} /> mDNS
            </span>
            <span className="inline-flex items-center gap-1.5">
              <Dot tone={server.udpActive ? "green" : "zinc"} /> UDP
            </span>
            <button
              className={cx("btn ml-auto h-6 px-2 text-[11.5px]", confirming ? "btn-danger" : "btn-ghost")}
              onClick={() => {
                if (confirming) {
                  onReset();
                  setConfirming(false);
                } else {
                  setConfirming(true);
                  window.setTimeout(() => setConfirming(false), 4000);
                }
              }}
              title="Issue a new pairing code and forget all phones"
            >
              {confirming ? <KeyRound className="size-3" /> : <RotateCcw className="size-3" />}
              {confirming ? "Confirm reset" : "Reset"}
            </button>
          </div>
          {server.error && <div className="mt-2 text-[11.5px] text-rose-600 dark:text-rose-400">{server.error}</div>}
        </div>
      </div>
    </section>
  );
}
