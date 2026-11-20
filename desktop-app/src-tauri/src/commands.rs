//! Tauri commands invoked by the React dashboard.

use std::fs;

use tauri::{AppHandle, Manager, State};
use tauri_plugin_autostart::ManagerExt;
use tauri_plugin_clipboard_manager::ClipboardExt;

use crate::protocol::HandshakeStatus;
use crate::server::{admit, handshake_ack};
use crate::state::{emit_state, new_token, ConnCommand, ScanEntry, SettingsPatch, Shared, Snapshot};

#[tauri::command]
pub fn get_snapshot(shared: State<'_, Shared>) -> Snapshot {
    shared.snapshot()
}

#[tauri::command]
pub fn get_history(shared: State<'_, Shared>) -> Vec<ScanEntry> {
    shared.history()
}

#[tauri::command]
pub fn update_settings(app: AppHandle, shared: State<'_, Shared>, patch: SettingsPatch) -> Result<Snapshot, String> {
    if let Some(enabled) = patch.launch_on_startup {
        let launcher = app.autolaunch();
        let result = if enabled { launcher.enable() } else { launcher.disable() };
        result.map_err(|e| format!("Could not change launch-at-login: {e}"))?;
    }
    let paused_change = {
        let mut inner = shared.inner.lock().unwrap();
        let s = &mut inner.config.settings;
        if let Some(v) = patch.output_mode {
            s.output_mode = v;
        }
        if let Some(v) = patch.auto_enter {
            s.auto_enter = v;
        }
        if let Some(v) = patch.sound_feedback {
            s.sound_feedback = v;
        }
        if let Some(v) = patch.start_minimized {
            s.start_minimized = v;
        }
        if let Some(v) = patch.launch_on_startup {
            s.launch_on_startup = v;
        }
        match patch.paused {
            Some(v) if v != s.paused => {
                s.paused = v;
                Some(v)
            }
            _ => None,
        }
    };
    shared.save_config();
    if let Some(paused) = paused_change {
        shared.broadcast(crate::protocol::Outgoing::Status { paused });
    }
    emit_state(&app);
    Ok(shared.snapshot())
}

#[tauri::command]
pub fn respond_pairing(app: AppHandle, shared: State<'_, Shared>, request_id: String, accept: bool) -> Result<(), String> {
    let (request, handle) = {
        let mut inner = shared.inner.lock().unwrap();
        let pos = inner
            .pending
            .iter()
            .position(|p| p.request_id == request_id)
            .ok_or("This pairing request has expired")?;
        let request = inner.pending.remove(pos);
        let handle = inner.conns.get(&request.conn_id).cloned();
        (request, handle)
    };
    let Some(handle) = handle else {
        emit_state(&app);
        return Err("The phone disconnected before it could be approved".into());
    };
    if accept {
        admit(
            &app,
            &request.conn_id,
            &request.address,
            &request.device_id,
            &request.device_name,
            &request.platform,
            &request.app_version,
        );
        let _ = handle.tx.send(ConnCommand::Send(handshake_ack(&app, HandshakeStatus::Accepted, true, None)));
    } else {
        let _ = handle.tx.send(ConnCommand::Send(handshake_ack(
            &app,
            HandshakeStatus::Rejected,
            false,
            Some("Pairing was declined on the desktop".into()),
        )));
        let _ = handle.tx.send(ConnCommand::Close);
    }
    emit_state(&app);
    Ok(())
}

#[tauri::command]
pub fn disconnect_device(app: AppHandle, shared: State<'_, Shared>, device_id: String, forget: bool) {
    {
        let mut inner = shared.inner.lock().unwrap();
        let conns: Vec<String> = inner
            .devices
            .iter()
            .filter(|(_, d)| d.device_id == device_id)
            .map(|(cid, _)| cid.clone())
            .collect();
        for cid in conns {
            if let Some(handle) = inner.conns.get(&cid) {
                let _ = handle.tx.send(ConnCommand::Close);
            }
            inner.devices.remove(&cid);
        }
        if forget {
            inner.config.trusted.retain(|t| t.device_id != device_id);
        }
    }
    if forget {
        shared.save_config();
    }
    emit_state(&app);
}

/// Issues a new pairing token, forgets all phones and drops live sessions.
#[tauri::command]
pub fn reset_pairing(app: AppHandle, shared: State<'_, Shared>) {
    {
        let mut inner = shared.inner.lock().unwrap();
        inner.config.pairing_token = new_token();
        inner.config.trusted.clear();
        for handle in inner.conns.values() {
            let _ = handle.tx.send(ConnCommand::Close);
        }
        inner.devices.clear();
        inner.pending.clear();
    }
    shared.save_config();
    emit_state(&app);
}

#[tauri::command]
pub fn clear_history(app: AppHandle, shared: State<'_, Shared>) {
    shared.inner.lock().unwrap().history.clear();
    shared.save_history();
    emit_state(&app);
}

fn csv_field(value: &str) -> String {
    if value.contains([',', '"', '\n', '\r']) {
        format!("\"{}\"", value.replace('"', "\"\""))
    } else {
        value.to_string()
    }
}

/// Writes the scan history to `path` as CSV, JSON or plain text (by extension).
#[tauri::command]
pub fn export_history(shared: State<'_, Shared>, path: String) -> Result<usize, String> {
    let history = shared.history();
    let lower = path.to_lowercase();
    let body = if lower.ends_with(".json") {
        serde_json::to_string_pretty(&history).map_err(|e| e.to_string())?
    } else if lower.ends_with(".txt") {
        history.iter().map(|e| e.code.as_str()).collect::<Vec<_>>().join("\n")
    } else {
        let mut out = String::from("timestamp,code,format,device,delivery\n");
        for e in &history {
            out.push_str(&format!(
                "{},{},{},{},{}\n",
                e.timestamp,
                csv_field(&e.code),
                csv_field(&e.format),
                csv_field(&e.device_name),
                serde_json::to_value(e.delivery).ok().and_then(|v| v.as_str().map(String::from)).unwrap_or_default()
            ));
        }
        out
    };
    fs::write(&path, body).map_err(|e| format!("Could not write file: {e}"))?;
    Ok(history.len())
}

#[tauri::command]
pub fn copy_text(app: AppHandle, text: String) -> Result<(), String> {
    app.clipboard().write_text(text).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn hide_window(app: AppHandle) {
    crate::tray::hide_main(&app);
}

#[tauri::command]
pub fn quit_app(app: AppHandle) {
    crate::tray::quit(&app);
}

/// Keeps the persisted launch-at-login flag in sync with the OS.
pub fn sync_autostart(app: &AppHandle) {
    let enabled = app.autolaunch().is_enabled().unwrap_or(false);
    let shared = app.state::<Shared>();
    let changed = {
        let mut inner = shared.inner.lock().unwrap();
        let changed = inner.config.settings.launch_on_startup != enabled;
        inner.config.settings.launch_on_startup = enabled;
        changed
    };
    if changed {
        shared.save_config();
    }
}
