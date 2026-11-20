//! WebSocket server that phones connect to (`ws://<desktop-ip>:<port>`).

use std::net::SocketAddr;
use std::time::{Duration, Instant};

use futures_util::{SinkExt, StreamExt};
use tauri::{AppHandle, Emitter, Manager};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;

use crate::discovery::truncate;
use crate::injector;
use crate::protocol::{
    desktop_platform, now_ms, AckStatus, HandshakeStatus, Incoming, Outgoing, PROTOCOL_VERSION,
};
use crate::state::{
    emit_state, ConnCommand, ConnHandle, ConnectedDevice, Delivery, PairingRequest, ScanEntry, Shared,
};

const HEARTBEAT: Duration = Duration::from_secs(5);
const IDLE_TIMEOUT: Duration = Duration::from_secs(16);
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);
const MAX_FRAME: usize = 64 * 1024;
const MAX_CODE_LEN: usize = 8192;

/// Binds the listener (walking forward from the configured port if needed).
pub async fn bind(app: &AppHandle) -> Option<TcpListener> {
    let preferred = app.state::<Shared>().inner.lock().unwrap().config.settings.port;
    for offset in 0..20u16 {
        let port = preferred.saturating_add(offset);
        match TcpListener::bind(("0.0.0.0", port)).await {
            Ok(listener) => {
                let shared = app.state::<Shared>();
                let mut inner = shared.inner.lock().unwrap();
                inner.port = port;
                inner.ws_running = true;
                inner.server_error = None;
                return Some(listener);
            }
            Err(err) => eprintln!("[ws] port {port} unavailable: {err}"),
        }
    }
    let shared = app.state::<Shared>();
    shared.inner.lock().unwrap().server_error =
        Some(format!("Could not open a network port between {} and {}", preferred, preferred.saturating_add(19)));
    None
}

pub async fn run(app: AppHandle, listener: TcpListener) {
    loop {
        match listener.accept().await {
            Ok((stream, addr)) => {
                let _ = stream.set_nodelay(true);
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    handle_connection(app, stream, addr).await;
                });
            }
            Err(err) => {
                eprintln!("[ws] accept failed: {err}");
                tokio::time::sleep(Duration::from_millis(250)).await;
            }
        }
    }
}

#[derive(PartialEq, Eq)]
enum Phase {
    AwaitingHandshake,
    AwaitingApproval,
    Authenticated,
}

struct Peer {
    device_id: String,
    device_name: String,
}

async fn handle_connection(app: AppHandle, stream: TcpStream, addr: SocketAddr) {
    let config = tokio_tungstenite::tungstenite::protocol::WebSocketConfig::default()
        .max_message_size(Some(MAX_FRAME))
        .max_frame_size(Some(MAX_FRAME));
    let ws = match tokio_tungstenite::accept_async_with_config(stream, Some(config)).await {
        Ok(ws) => ws,
        Err(err) => {
            eprintln!("[ws] handshake with {addr} failed: {err}");
            return;
        }
    };
    let (mut sink, mut source) = ws.split();
    let conn_id = uuid::Uuid::new_v4().to_string();
    let (tx, mut rx) = mpsc::unbounded_channel::<ConnCommand>();
    app.state::<Shared>()
        .inner
        .lock()
        .unwrap()
        .conns
        .insert(conn_id.clone(), ConnHandle { tx: tx.clone() });

    let writer = tauri::async_runtime::spawn(async move {
        while let Some(cmd) = rx.recv().await {
            match cmd {
                ConnCommand::Send(frame) => {
                    let Ok(text) = serde_json::to_string(&frame) else { continue };
                    if sink.send(Message::text(text)).await.is_err() {
                        break;
                    }
                }
                ConnCommand::Close => {
                    let _ = sink.send(Message::Close(None)).await;
                    break;
                }
            }
        }
        let _ = sink.close().await;
    });

    let mut phase = Phase::AwaitingHandshake;
    let mut peer: Option<Peer> = None;
    let started = Instant::now();
    let mut last_seen = Instant::now();
    let mut heartbeat = tokio::time::interval(HEARTBEAT);
    heartbeat.tick().await;

    loop {
        tokio::select! {
            frame = source.next() => {
                let Some(Ok(frame)) = frame else { break };
                last_seen = Instant::now();
                let text = match frame {
                    Message::Text(t) => t.to_string(),
                    Message::Binary(b) => String::from_utf8_lossy(&b).to_string(),
                    Message::Close(_) => break,
                    _ => continue,
                };
                let Ok(msg) = serde_json::from_str::<Incoming>(&text) else { continue };
                if !process(&app, &conn_id, &addr, &tx, msg, &mut phase, &mut peer).await {
                    break;
                }
            }
            _ = heartbeat.tick() => {
                if phase == Phase::AwaitingHandshake && started.elapsed() > HANDSHAKE_TIMEOUT {
                    break;
                }
                if last_seen.elapsed() > IDLE_TIMEOUT {
                    eprintln!("[ws] {addr} timed out");
                    break;
                }
                let _ = tx.send(ConnCommand::Send(Outgoing::Ping { timestamp: now_ms() }));
            }
        }
    }

    let _ = tx.send(ConnCommand::Close);
    drop(tx);
    {
        let shared = app.state::<Shared>();
        let mut inner = shared.inner.lock().unwrap();
        inner.conns.remove(&conn_id);
        inner.devices.remove(&conn_id);
        inner.pending.retain(|p| p.conn_id != conn_id);
    }
    let _ = tokio::time::timeout(Duration::from_secs(2), writer).await;
    emit_state(&app);
}

fn send(tx: &mpsc::UnboundedSender<ConnCommand>, frame: Outgoing) {
    let _ = tx.send(ConnCommand::Send(frame));
}

/// Builds the handshake reply describing this desktop.
pub fn handshake_ack(app: &AppHandle, status: HandshakeStatus, with_token: bool, reason: Option<String>) -> Outgoing {
    let shared = app.state::<Shared>();
    let inner = shared.inner.lock().unwrap();
    Outgoing::HandshakeAck {
        status,
        device_id: inner.config.device_id.clone(),
        device_name: inner.desktop_name.clone(),
        platform: desktop_platform().to_string(),
        app_version: env!("CARGO_PKG_VERSION").to_string(),
        protocol_version: PROTOCOL_VERSION,
        paused: inner.config.settings.paused,
        pairing_token: if with_token { Some(inner.config.pairing_token.clone()) } else { None },
        reason,
    }
}

/// Registers an authenticated device and persists it as trusted.
pub fn admit(app: &AppHandle, conn_id: &str, address: &str, device_id: &str, name: &str, platform: &str, version: &str) {
    let shared = app.state::<Shared>();
    {
        let mut inner = shared.inner.lock().unwrap();
        // A phone reconnecting replaces its stale session.
        let stale: Vec<String> = inner
            .devices
            .iter()
            .filter(|(cid, d)| d.device_id == device_id && cid.as_str() != conn_id)
            .map(|(cid, _)| cid.clone())
            .collect();
        for cid in stale {
            inner.devices.remove(&cid);
            if let Some(handle) = inner.conns.get(&cid) {
                let _ = handle.tx.send(ConnCommand::Close);
            }
        }
        let now = now_ms();
        inner.devices.insert(
            conn_id.to_string(),
            ConnectedDevice {
                conn_id: conn_id.to_string(),
                device_id: device_id.to_string(),
                device_name: name.to_string(),
                platform: platform.to_string(),
                app_version: version.to_string(),
                address: address.to_string(),
                connected_at: now,
                last_seen: now,
                latency_ms: None,
                scan_count: 0,
            },
        );
        inner.pending.retain(|p| p.conn_id != conn_id);
        inner.nearby.remove(device_id);
        inner.remember_trusted(device_id, name, platform);
    }
    shared.save_config();
}

async fn process(
    app: &AppHandle,
    conn_id: &str,
    addr: &SocketAddr,
    tx: &mpsc::UnboundedSender<ConnCommand>,
    msg: Incoming,
    phase: &mut Phase,
    peer: &mut Option<Peer>,
) -> bool {
    match msg {
        Incoming::Handshake { device_id, device_name, platform, app_version, pairing_token } => {
            if *phase == Phase::Authenticated {
                return true;
            }
            let device_id = truncate(&device_id, 64);
            let device_name = truncate(&device_name, 64);
            let platform = truncate(&platform, 16);
            let app_version = truncate(&app_version, 32);
            if device_id.is_empty() {
                send(tx, handshake_ack(app, HandshakeStatus::Rejected, false, Some("missing deviceId".into())));
                return false;
            }
            let token_ok = {
                let shared = app.state::<Shared>();
                let inner = shared.inner.lock().unwrap();
                pairing_token.as_deref().is_some_and(|t| constant_time_eq(t, &inner.config.pairing_token))
            };
            *peer = Some(Peer { device_id: device_id.clone(), device_name: device_name.clone() });
            if token_ok {
                admit(app, conn_id, &addr.ip().to_string(), &device_id, &device_name, &platform, &app_version);
                *phase = Phase::Authenticated;
                send(tx, handshake_ack(app, HandshakeStatus::Accepted, true, None));
            } else {
                {
                    let shared = app.state::<Shared>();
                    let mut inner = shared.inner.lock().unwrap();
                    inner.pending.retain(|p| p.device_id != device_id);
                    inner.pending.push(PairingRequest {
                        request_id: uuid::Uuid::new_v4().to_string(),
                        conn_id: conn_id.to_string(),
                        device_id,
                        device_name,
                        platform,
                        app_version,
                        address: addr.ip().to_string(),
                        requested_at: now_ms(),
                    });
                }
                *phase = Phase::AwaitingApproval;
                send(tx, handshake_ack(app, HandshakeStatus::Pending, false, Some("Approve this phone on the desktop".into())));
                let _ = app.emit("pairing-request", ());
            }
            emit_state(app);
            true
        }
        Incoming::Scan { message_id, code, format, timestamp } => {
            if *phase == Phase::AwaitingApproval {
                // Approval may have been granted from the dashboard since the last frame.
                let approved = app.state::<Shared>().inner.lock().unwrap().devices.contains_key(conn_id);
                if approved {
                    *phase = Phase::Authenticated;
                }
            }
            if *phase != Phase::Authenticated {
                send(tx, Outgoing::Ack { message_id, status: AckStatus::Unauthorized, detail: None });
                return true;
            }
            let shared = app.state::<Shared>();
            if !shared.mark_message_seen(&message_id) {
                send(tx, Outgoing::Ack { message_id, status: AckStatus::Duplicate, detail: None });
                return true;
            }
            if code.is_empty() || code.len() > MAX_CODE_LEN {
                send(tx, Outgoing::Ack { message_id, status: AckStatus::Error, detail: Some("invalid payload".into()) });
                return true;
            }
            let (mode, auto_enter, paused, device_name, device_id) = {
                let mut inner = shared.inner.lock().unwrap();
                let s = inner.config.settings.clone();
                let (name, id) = match inner.devices.get_mut(conn_id) {
                    Some(d) => {
                        d.scan_count += 1;
                        d.last_seen = now_ms();
                        (d.device_name.clone(), d.device_id.clone())
                    }
                    None => peer
                        .as_ref()
                        .map(|p| (p.device_name.clone(), p.device_id.clone()))
                        .unwrap_or_default(),
                };
                (s.output_mode, s.auto_enter, s.paused, name, id)
            };

            let (delivery, error, status) = if paused {
                (Delivery::Paused, None, AckStatus::Paused)
            } else {
                match injector::deliver(app, mode, &code, auto_enter).await {
                    Ok(d) => (d, None, AckStatus::Ok),
                    Err(e) => (Delivery::Failed, Some(e), AckStatus::Error),
                }
            };
            send(tx, Outgoing::Ack { message_id: message_id.clone(), status, detail: error.clone() });

            let entry = ScanEntry {
                id: message_id,
                code,
                format: truncate(&format, 24),
                timestamp: if timestamp == 0 { now_ms() } else { timestamp },
                received_at: now_ms(),
                device_id,
                device_name,
                delivery,
                error,
            };
            shared.push_history(entry.clone());
            let _ = app.emit("scan", entry);
            emit_state(app);
            let handle = app.clone();
            tauri::async_runtime::spawn_blocking(move || handle.state::<Shared>().save_history());
            true
        }
        Incoming::Ping { timestamp } => {
            send(tx, Outgoing::Pong { timestamp });
            true
        }
        Incoming::Pong { timestamp } => {
            if timestamp > 0 {
                let latency = now_ms().saturating_sub(timestamp);
                let shared = app.state::<Shared>();
                let mut inner = shared.inner.lock().unwrap();
                if let Some(d) = inner.devices.get_mut(conn_id) {
                    d.latency_ms = Some(latency);
                    d.last_seen = now_ms();
                }
                drop(inner);
                emit_state(app);
            }
            true
        }
        Incoming::Bye {} => false,
    }
}

fn constant_time_eq(a: &str, b: &str) -> bool {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}
