export type OutputMode = "keyboard" | "clipboard" | "log";
export type OverallStatus = "connected" | "waiting" | "paused";
export type Delivery = "typed" | "copied" | "logged" | "paused" | "failed";

export interface Settings {
  outputMode: OutputMode;
  autoEnter: boolean;
  soundFeedback: boolean;
  startMinimized: boolean;
  launchOnStartup: boolean;
  paused: boolean;
  port: number;
}

export type SettingsPatch = Partial<Omit<Settings, "port">>;

export interface ServerInfo {
  desktopName: string;
  deviceId: string;
  platform: string;
  appVersion: string;
  host: string;
  ips: string[];
  port: number;
  wsRunning: boolean;
  mdnsActive: boolean;
  udpActive: boolean;
  pairingUri: string;
  qrSvg: string;
  error: string | null;
}

export interface ConnectedDevice {
  connId: string;
  deviceId: string;
  deviceName: string;
  platform: string;
  appVersion: string;
  address: string;
  connectedAt: number;
  lastSeen: number;
  latencyMs: number | null;
  scanCount: number;
}

export interface PairingRequest {
  requestId: string;
  connId: string;
  deviceId: string;
  deviceName: string;
  platform: string;
  appVersion: string;
  address: string;
  requestedAt: number;
}

export interface NearbyDevice {
  deviceId: string;
  deviceName: string;
  platform: string;
  address: string;
  lastSeen: number;
}

export interface TrustedDevice {
  deviceId: string;
  deviceName: string;
  platform: string;
  lastSeen: number;
}

export interface Snapshot {
  status: OverallStatus;
  settings: Settings;
  server: ServerInfo;
  devices: ConnectedDevice[];
  pending: PairingRequest[];
  nearby: NearbyDevice[];
  trusted: TrustedDevice[];
}

export interface ScanEntry {
  id: string;
  code: string;
  format: string;
  timestamp: number;
  receivedAt: number;
  deviceId: string;
  deviceName: string;
  delivery: Delivery;
  error?: string;
}
