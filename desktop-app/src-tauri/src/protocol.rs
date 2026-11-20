//! Strictly typed JSON wire protocol shared with the mobile app.
//!
//! Every frame is a JSON object with a `type` discriminator. Field names are
//! camelCase on the wire.

use serde::{Deserialize, Serialize};

/// mDNS service type advertised by the desktop app.
pub const SERVICE_TYPE: &str = "_barcodesync._tcp.local.";
/// UDP port the desktop listens on for `discover` broadcasts.
pub const DISCOVERY_PORT: u16 = 47810;
/// Default WebSocket port (the server walks forward if it is taken).
pub const DEFAULT_WS_PORT: u16 = 47800;
/// Protocol revision, bumped on breaking changes.
pub const PROTOCOL_VERSION: u32 = 1;

/// Frames sent by the mobile app.
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", rename_all_fields = "camelCase")]
pub enum Incoming {
    Handshake {
        device_id: String,
        device_name: String,
        platform: String,
        app_version: String,
        #[serde(default)]
        pairing_token: Option<String>,
    },
    Scan {
        message_id: String,
        code: String,
        #[serde(default = "default_format")]
        format: String,
        #[serde(default)]
        timestamp: u64,
    },
    Ping {
        #[serde(default)]
        timestamp: u64,
    },
    Pong {
        #[serde(default)]
        timestamp: u64,
    },
    Bye {},
}

fn default_format() -> String {
    "unknown".to_string()
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum HandshakeStatus {
    Accepted,
    Pending,
    Rejected,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AckStatus {
    Ok,
    Duplicate,
    Paused,
    Unauthorized,
    Error,
}

/// Frames sent by the desktop app.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case", rename_all_fields = "camelCase")]
pub enum Outgoing {
    HandshakeAck {
        status: HandshakeStatus,
        device_id: String,
        device_name: String,
        platform: String,
        app_version: String,
        protocol_version: u32,
        paused: bool,
        #[serde(skip_serializing_if = "Option::is_none")]
        pairing_token: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        reason: Option<String>,
    },
    Ack {
        message_id: String,
        status: AckStatus,
        #[serde(skip_serializing_if = "Option::is_none")]
        detail: Option<String>,
    },
    Ping {
        timestamp: u64,
    },
    Pong {
        timestamp: u64,
    },
    Status {
        paused: bool,
    },
}

/// UDP `discover` datagram broadcast by the mobile app.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DiscoverPacket {
    #[serde(rename = "type")]
    pub kind: String,
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
}

/// UDP `announce` reply sent back to the mobile app.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AnnouncePacket {
    #[serde(rename = "type")]
    pub kind: &'static str,
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub app_version: String,
    pub protocol_version: u32,
    pub port: u16,
    pub ips: Vec<String>,
}

pub fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

pub fn desktop_platform() -> &'static str {
    match std::env::consts::OS {
        "windows" => "windows",
        "macos" => "macos",
        _ => "linux",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_handshake() {
        let raw = r#"{"type":"handshake","deviceId":"a","deviceName":"Pixel","platform":"android","appVersion":"1.0.0","pairingToken":"t"}"#;
        match serde_json::from_str::<Incoming>(raw).unwrap() {
            Incoming::Handshake { device_name, pairing_token, .. } => {
                assert_eq!(device_name, "Pixel");
                assert_eq!(pairing_token.as_deref(), Some("t"));
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn parses_scan_and_serializes_ack() {
        let raw = r#"{"type":"scan","messageId":"m1","code":"4006381333931","format":"ean13","timestamp":1}"#;
        assert!(matches!(serde_json::from_str::<Incoming>(raw).unwrap(), Incoming::Scan { .. }));
        let ack = Outgoing::Ack { message_id: "m1".into(), status: AckStatus::Ok, detail: None };
        assert_eq!(serde_json::to_string(&ack).unwrap(), r#"{"type":"ack","messageId":"m1","status":"ok"}"#);
    }
}
