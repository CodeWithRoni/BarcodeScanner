import { useEffect, useState } from "react";
import { Check, Gauge, Radio, ShieldQuestion, Smartphone, Unplug, Wifi, X } from "lucide-react";
import type { ConnectedDevice, NearbyDevice, PairingRequest } from "../lib/types";
import { duration, platformLabel } from "../lib/format";
import { CardHeader, cx, Dot } from "./ui";

function useNow(intervalMs = 1000) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), intervalMs);
    return () => window.clearInterval(id);
  }, [intervalMs]);
  return now;
}

function LatencyBadge({ latency, lastSeen, now }: { latency: number | null; lastSeen: number; now: number }) {
  const stale = now - lastSeen > 11000;
  const tone = stale ? "rose" : latency === null ? "zinc" : latency < 60 ? "green" : latency < 200 ? "amber" : "rose";
  const cls = {
    green: "text-emerald-600 dark:text-emerald-400",
    amber: "text-amber-600 dark:text-amber-400",
    rose: "text-rose-600 dark:text-rose-400",
    zinc: "text-zinc-500",
  }[tone];
  return (
    <span className={cx("inline-flex items-center gap-1.5 font-mono text-[11.5px] tabular-nums", cls)}>
      <span className="relative flex size-1.5">
        <span key={lastSeen} className="absolute inline-flex size-full rounded-full bg-current opacity-60 animate-ping-slow [animation-iteration-count:1]" />
        <span className="relative inline-flex size-1.5 rounded-full bg-current" />
      </span>
      {stale ? "no heartbeat" : latency === null ? "measuring…" : `${latency} ms`}
    </span>
  );
}

function DeviceRow({ device, now, onDisconnect }: { device: ConnectedDevice; now: number; onDisconnect: (forget: boolean) => void }) {
  return (
    <div className="group relative overflow-hidden rounded-xl border border-zinc-200/80 bg-gradient-to-br from-white to-zinc-50 p-4 animate-fade-in dark:border-white/[0.07] dark:from-white/[0.05] dark:to-white/[0.01]">
      <div className="pointer-events-none absolute -top-10 -right-10 size-32 rounded-full bg-emerald-400/10 blur-2xl" />
      <div className="flex items-start gap-3">
        <div className="relative flex size-11 shrink-0 items-center justify-center rounded-xl bg-zinc-900 text-white shadow-md dark:bg-white dark:text-zinc-900">
          <Smartphone className="size-5" />
          <span className="absolute -right-0.5 -bottom-0.5 rounded-full ring-2 ring-white dark:ring-[#14151a]">
            <Dot tone="green" />
          </span>
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="truncate text-[14px] font-semibold">{device.deviceName}</span>
            <span className="rounded-md bg-zinc-100 px-1.5 py-0.5 text-[10.5px] font-medium text-zinc-600 dark:bg-white/[0.07] dark:text-zinc-300">
              {platformLabel(device.platform)}
            </span>
          </div>
          <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-[12px] text-zinc-500 dark:text-zinc-400">
            <span className="inline-flex items-center gap-1 font-mono selectable">
              <Wifi className="size-3" />
              {device.address}
            </span>
            <LatencyBadge latency={device.latencyMs} lastSeen={device.lastSeen} now={now} />
          </div>
        </div>
        <div className="flex gap-1 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
          <button className="icon-btn size-7" title="Disconnect" onClick={() => onDisconnect(false)}>
            <Unplug className="size-3.5" />
          </button>
          <button className="icon-btn size-7 hover:!text-rose-500" title="Disconnect and forget" onClick={() => onDisconnect(true)}>
            <X className="size-3.5" />
          </button>
        </div>
      </div>
      <div className="mt-3 grid grid-cols-3 gap-2 border-t border-zinc-200/70 pt-3 text-[11.5px] dark:border-white/[0.06]">
        <Stat label="Scans" value={device.scanCount.toLocaleString()} />
        <Stat label="Session" value={duration(now - device.connectedAt)} />
        <Stat label="App" value={`v${device.appVersion}`} />
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-zinc-400 dark:text-zinc-500">{label}</div>
      <div className="mt-0.5 font-medium tabular-nums text-zinc-800 dark:text-zinc-200">{value}</div>
    </div>
  );
}

function PendingRow({ req, onRespond }: { req: PairingRequest; onRespond: (accept: boolean) => void }) {
  return (
    <div className="flex items-center gap-3 rounded-xl border border-accent-500/30 bg-accent-500/[0.06] p-3 animate-toast-in">
      <div className="flex size-9 items-center justify-center rounded-lg bg-accent-500/15 text-accent-600 dark:text-accent-400">
        <ShieldQuestion className="size-[18px]" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="truncate text-[13px] font-semibold" title={req.deviceName}>
          {req.deviceName}
        </div>
        <div className="truncate text-[11.5px] text-zinc-500 dark:text-zinc-400">
          Wants to pair · {platformLabel(req.platform)} · <span className="font-mono">{req.address}</span>
        </div>
      </div>
      <button className="btn btn-ghost h-7 px-2.5" onClick={() => onRespond(false)}>
        Decline
      </button>
      <button className="btn btn-primary h-7 px-2.5" onClick={() => onRespond(true)}>
        <Check className="size-3.5" /> Allow
      </button>
    </div>
  );
}

function Radar() {
  return (
    <div className="relative flex size-24 items-center justify-center">
      {[0, 0.6, 1.2].map((delay) => (
        <span
          key={delay}
          className="absolute inset-0 rounded-full border border-accent-500/40 animate-ping-slow"
          style={{ animationDelay: `${delay}s`, animationDuration: "2.4s" }}
        />
      ))}
      <div className="relative flex size-12 items-center justify-center rounded-full bg-accent-500/10 text-accent-500 ring-1 ring-accent-500/30">
        <Radio className="size-5" />
      </div>
    </div>
  );
}

export function DevicesCard({
  devices,
  pending,
  nearby,
  onRespond,
  onDisconnect,
}: {
  devices: ConnectedDevice[];
  pending: PairingRequest[];
  nearby: NearbyDevice[];
  onRespond: (requestId: string, accept: boolean) => void;
  onDisconnect: (deviceId: string, forget: boolean) => void;
}) {
  const now = useNow();
  const empty = devices.length === 0 && pending.length === 0;
  return (
    <section className="card">
      <CardHeader
        title="Connected phone"
        icon={<Smartphone className="size-3.5" />}
        action={
          devices.length > 0 && (
            <span className="inline-flex items-center gap-1 text-[11.5px] text-zinc-500">
              <Gauge className="size-3" /> 5s heartbeat
            </span>
          )
        }
      />
      <div className="space-y-2.5 px-5 pb-5">
        {pending.map((req) => (
          <PendingRow key={req.requestId} req={req} onRespond={(a) => onRespond(req.requestId, a)} />
        ))}
        {devices.map((d) => (
          <DeviceRow key={d.connId} device={d} now={now} onDisconnect={(forget) => onDisconnect(d.deviceId, forget)} />
        ))}
        {empty && (
          <div className="flex flex-col items-center rounded-xl border border-dashed border-zinc-300/80 px-4 py-6 text-center dark:border-white/10">
            <Radar />
            <div className="mt-3 text-[13.5px] font-semibold">Looking for your phone…</div>
            <p className="mt-1 max-w-[260px] text-[12.5px] leading-relaxed text-zinc-500 dark:text-zinc-400">
              Open BarcodeSync on your phone on the same Wi-Fi, or scan the pairing code.
            </p>
          </div>
        )}
        {nearby.length > 0 && (
          <div className="pt-1">
            <div className="mb-1.5 text-[11px] font-medium text-zinc-400 dark:text-zinc-500">Nearby on this network</div>
            <div className="flex flex-wrap gap-1.5">
              {nearby.map((n) => (
                <span
                  key={n.deviceId}
                  className="inline-flex items-center gap-1.5 rounded-full border border-zinc-200 bg-white px-2.5 py-1 text-[11.5px] animate-fade-in dark:border-white/10 dark:bg-white/[0.03]"
                >
                  <Dot tone="amber" pulse />
                  {n.deviceName}
                  <span className="text-zinc-400">{platformLabel(n.platform)}</span>
                </span>
              ))}
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
