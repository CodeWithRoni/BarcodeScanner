//! Application state: persisted configuration, live connections, scan history
//! and the snapshot that is pushed to the React dashboard.

use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

use rand::distr::Alphanumeric;
use rand::Rng;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager};
use tokio::sync::mpsc::UnboundedSender;

use crate::protocol::{desktop_platform, now_ms, Outgoing, DEFAULT_WS_PORT};

const MAX_HISTORY: usize = 2000;
const MAX_SEEN_MESSAGES: usize = 4096;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum OutputMode {
    #[default]
    Keyboard,
    Clipboard,
    Log,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    pub output_mode: OutputMode,
    pub auto_enter: bool,
    pub sound_feedback: bool,
    pub start_minimized: bool,
    pub launch_on_startup: bool,
    pub paused: bool,
    pub port: u16,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            output_mode: OutputMode::Keyboard,
            auto_enter: true,
            sound_feedback: true,
            start_minimized: false,
            launch_on_startup: false,
            paused: false,
            port: DEFAULT_WS_PORT,
        }
    }
}

/// Partial settings update sent from the dashboard.
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SettingsPatch {
    pub output_mode: Option<OutputMode>,
    pub auto_enter: Option<bool>,
    pub sound_feedback: Option<bool>,
    pub start_minimized: Option<bool>,
    pub launch_on_startup: Option<bool>,
    pub paused: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrustedDevice {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub last_seen: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Config {
    pub device_id: String,
    pub pairing_token: String,
    pub settings: Settings,
    pub trusted: Vec<TrustedDevice>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            device_id: uuid::Uuid::new_v4().to_string(),
            pairing_token: new_token(),
            settings: Settings::default(),
            trusted: Vec::new(),
        }
    }
}

pub fn new_token() -> String {
    rand::rng().sample_iter(&Alphanumeric).take(32).map(char::from).collect()
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectedDevice {
    pub conn_id: String,
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub app_version: String,
    pub address: String,
    pub connected_at: u64,
    pub last_seen: u64,
    pub latency_ms: Option<u64>,
    pub scan_count: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingRequest {
    pub request_id: String,
    pub conn_id: String,
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub app_version: String,
    pub address: String,
    pub requested_at: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NearbyDevice {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub address: String,
    pub last_seen: u64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Delivery {
    Typed,
    Copied,
    Logged,
    Paused,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanEntry {
    pub id: String,
    pub code: String,
    pub format: String,
    pub timestamp: u64,
    pub received_at: u64,
    pub device_id: String,
    pub device_name: String,
    pub delivery: Delivery,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerInfo {
    pub desktop_name: String,
    pub device_id: String,
    pub platform: String,
    pub app_version: String,
    pub host: String,
    pub ips: Vec<String>,
    pub port: u16,
    pub ws_running: bool,
    pub mdns_active: bool,
    pub udp_active: bool,
    pub pairing_uri: String,
    pub qr_svg: String,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OverallStatus {
    Connected,
    Waiting,
    Paused,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub status: OverallStatus,
    pub settings: Settings,
    pub server: ServerInfo,
    pub devices: Vec<ConnectedDevice>,
    pub pending: Vec<PairingRequest>,
    pub nearby: Vec<NearbyDevice>,
    pub trusted: Vec<TrustedDevice>,
}

/// Handle used to push frames to one WebSocket connection.
#[derive(Clone)]
pub struct ConnHandle {
    pub tx: UnboundedSender<ConnCommand>,
}

#[derive(Debug, Clone)]
pub enum ConnCommand {
    Send(Outgoing),
    Close,
}

pub struct Inner {
    pub config: Config,
    pub desktop_name: String,
    pub ips: Vec<String>,
    pub port: u16,
    pub ws_running: bool,
    pub mdns_active: bool,
    pub udp_active: bool,
    pub server_error: Option<String>,
    pub conns: HashMap<String, ConnHandle>,
    pub devices: HashMap<String, ConnectedDevice>,
    pub pending: Vec<PairingRequest>,
    pub nearby: HashMap<String, NearbyDevice>,
    pub history: VecDeque<ScanEntry>,
    seen_order: VecDeque<String>,
    seen_set: HashSet<String>,
}

pub struct Shared {
    pub inner: Mutex<Inner>,
    config_path: PathBuf,
    history_path: PathBuf,
}

impl Shared {
    pub fn load(app: &AppHandle) -> Self {
        let dir = app
            .path()
            .app_config_dir()
            .unwrap_or_else(|_| std::env::temp_dir().join("barcodesync"));
        let _ = fs::create_dir_all(&dir);
        let config_path = dir.join("config.json");
        let history_path = dir.join("history.json");

        let config: Config = fs::read_to_string(&config_path)
            .ok()
            .and_then(|raw| serde_json::from_str(&raw).ok())
            .unwrap_or_default();
        let history: VecDeque<ScanEntry> = fs::read_to_string(&history_path)
            .ok()
            .and_then(|raw| serde_json::from_str::<Vec<ScanEntry>>(&raw).ok())
            .map(|v| v.into_iter().take(MAX_HISTORY).collect())
            .unwrap_or_default();

        let desktop_name = gethostname::gethostname()
            .to_string_lossy()
            .trim_end_matches(".local")
            .to_string();
        let port = config.settings.port;

        let shared = Self {
            inner: Mutex::new(Inner {
                config,
                desktop_name: if desktop_name.is_empty() { "Desktop".into() } else { desktop_name },
                ips: crate::discovery::local_ipv4s(),
                port,
                ws_running: false,
                mdns_active: false,
                udp_active: false,
                server_error: None,
                conns: HashMap::new(),
                devices: HashMap::new(),
                pending: Vec::new(),
                nearby: HashMap::new(),
                history,
                seen_order: VecDeque::new(),
                seen_set: HashSet::new(),
            }),
            config_path,
            history_path,
        };
        shared.save_config();
        shared
    }

    pub fn save_config(&self) {
        let raw = {
            let inner = self.inner.lock().unwrap();
            serde_json::to_string_pretty(&inner.config)
        };
        if let Ok(raw) = raw {
            write_atomic(&self.config_path, raw.as_bytes());
        }
    }

    pub fn save_history(&self) {
        let raw = {
            let inner = self.inner.lock().unwrap();
            serde_json::to_string(&inner.history)
        };
        if let Ok(raw) = raw {
            write_atomic(&self.history_path, raw.as_bytes());
        }
    }

    pub fn snapshot(&self) -> Snapshot {
        let inner = self.inner.lock().unwrap();
        inner.snapshot()
    }

    pub fn history(&self) -> Vec<ScanEntry> {
        self.inner.lock().unwrap().history.iter().cloned().collect()
    }

    /// Returns `true` the first time a message id is seen.
    pub fn mark_message_seen(&self, message_id: &str) -> bool {
        let mut inner = self.inner.lock().unwrap();
        if inner.seen_set.contains(message_id) {
            return false;
        }
        inner.seen_set.insert(message_id.to_string());
        inner.seen_order.push_back(message_id.to_string());
        while inner.seen_order.len() > MAX_SEEN_MESSAGES {
            if let Some(old) = inner.seen_order.pop_front() {
                inner.seen_set.remove(&old);
            }
        }
        true
    }

    pub fn push_history(&self, entry: ScanEntry) {
        let mut inner = self.inner.lock().unwrap();
        inner.history.push_front(entry);
        while inner.history.len() > MAX_HISTORY {
            inner.history.pop_back();
        }
    }

    /// Sends a frame to every authenticated connection.
    pub fn broadcast(&self, frame: Outgoing) {
        let inner = self.inner.lock().unwrap();
        for conn_id in inner.devices.keys() {
            if let Some(handle) = inner.conns.get(conn_id) {
                let _ = handle.tx.send(ConnCommand::Send(frame.clone()));
            }
        }
    }
}

impl Inner {
    pub fn status(&self) -> OverallStatus {
        if self.config.settings.paused {
            OverallStatus::Paused
        } else if !self.devices.is_empty() {
            OverallStatus::Connected
        } else {
            OverallStatus::Waiting
        }
    }

    pub fn primary_host(&self) -> String {
        self.ips.first().cloned().unwrap_or_else(|| "127.0.0.1".to_string())
    }

    pub fn pairing_uri(&self) -> String {
        let host = self.primary_host();
        let alt: Vec<&str> = self.ips.iter().skip(1).map(String::as_str).collect();
        let mut uri = format!(
            "barcodesync://pair?v=1&host={}&port={}&token={}&id={}&name={}&platform={}",
            host,
            self.port,
            self.config.pairing_token,
            self.config.device_id,
            percent_encode(&self.desktop_name),
            desktop_platform()
        );
        if !alt.is_empty() {
            uri.push_str("&alt=");
            uri.push_str(&alt.join(","));
        }
        uri
    }

    pub fn server_info(&self) -> ServerInfo {
        let pairing_uri = self.pairing_uri();
        let qr_svg = qrcode::QrCode::new(pairing_uri.as_bytes())
            .map(|code| {
                code.render::<qrcode::render::svg::Color>()
                    .min_dimensions(232, 232)
                    .quiet_zone(true)
                    .dark_color(qrcode::render::svg::Color("#0b0d12"))
                    .light_color(qrcode::render::svg::Color("#ffffff"))
                    .build()
            })
            .unwrap_or_default();
        ServerInfo {
            desktop_name: self.desktop_name.clone(),
            device_id: self.config.device_id.clone(),
            platform: desktop_platform().to_string(),
            app_version: env!("CARGO_PKG_VERSION").to_string(),
            host: self.primary_host(),
            ips: self.ips.clone(),
            port: self.port,
            ws_running: self.ws_running,
            mdns_active: self.mdns_active,
            udp_active: self.udp_active,
            pairing_uri,
            qr_svg,
            error: self.server_error.clone(),
        }
    }

    pub fn snapshot(&self) -> Snapshot {
        let mut devices: Vec<ConnectedDevice> = self.devices.values().cloned().collect();
        devices.sort_by_key(|d| d.connected_at);
        let connected_ids: HashSet<&str> = devices.iter().map(|d| d.device_id.as_str()).collect();
        let mut nearby: Vec<NearbyDevice> = self
            .nearby
            .values()
            .filter(|n| !connected_ids.contains(n.device_id.as_str()))
            .cloned()
            .collect();
        nearby.sort_by(|a, b| a.device_name.cmp(&b.device_name));
        Snapshot {
            status: self.status(),
            settings: self.config.settings.clone(),
            server: self.server_info(),
            devices,
            pending: self.pending.clone(),
            nearby,
            trusted: self.config.trusted.clone(),
        }
    }

    pub fn remember_trusted(&mut self, device_id: &str, device_name: &str, platform: &str) {
        let now = now_ms();
        if let Some(existing) = self.config.trusted.iter_mut().find(|t| t.device_id == device_id) {
            existing.device_name = device_name.to_string();
            existing.platform = platform.to_string();
            existing.last_seen = now;
        } else {
            self.config.trusted.push(TrustedDevice {
                device_id: device_id.to_string(),
                device_name: device_name.to_string(),
                platform: platform.to_string(),
                last_seen: now,
            });
        }
    }
}

/// Pushes the latest snapshot to the dashboard and refreshes the tray.
pub fn emit_state(app: &AppHandle) {
    let shared = app.state::<Shared>();
    let snapshot = shared.snapshot();
    crate::tray::refresh(app, snapshot.status, snapshot.devices.len(), snapshot.settings.paused);
    let _ = app.emit("state", snapshot);
}

fn write_atomic(path: &PathBuf, bytes: &[u8]) {
    let tmp = path.with_extension("tmp");
    if fs::write(&tmp, bytes).is_ok() && fs::rename(&tmp, path).is_err() {
        let _ = fs::write(path, bytes);
    }
}

pub fn percent_encode(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for byte in input.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(byte as char),
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::percent_encode;

    #[test]
    fn encodes_names() {
        assert_eq!(percent_encode("Roni's PC"), "Roni%27s%20PC");
        assert_eq!(percent_encode("রনি"), "%E0%A6%B0%E0%A6%A8%E0%A6%BF");
    }
}
