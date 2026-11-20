//! Zero-config LAN discovery: mDNS advertisement (`_barcodesync._tcp.local.`)
//! plus a UDP broadcast responder for networks where multicast is filtered.

use std::net::{IpAddr, Ipv4Addr};
use std::sync::Mutex;
use std::time::Duration;

use mdns_sd::{ServiceDaemon, ServiceInfo};
use tauri::{AppHandle, Manager};
use tokio::net::UdpSocket;

use crate::protocol::{
    desktop_platform, now_ms, AnnouncePacket, DiscoverPacket, DISCOVERY_PORT, PROTOCOL_VERSION, SERVICE_TYPE,
};
use crate::state::{emit_state, NearbyDevice, Shared};

const NEARBY_TTL_MS: u64 = 10_000;

/// Keeps the mDNS daemon alive for the lifetime of the app.
#[derive(Default)]
pub struct MdnsHandle {
    pub daemon: Mutex<Option<(ServiceDaemon, String)>>,
}

impl MdnsHandle {
    pub fn shutdown(&self) {
        if let Some((daemon, fullname)) = self.daemon.lock().unwrap().take() {
            if let Ok(rx) = daemon.unregister(&fullname) {
                let _ = rx.recv_timeout(Duration::from_millis(500));
            }
            let _ = daemon.shutdown();
        }
    }
}

/// Private, non-loopback IPv4 addresses, primary route first.
pub fn local_ipv4s() -> Vec<String> {
    let mut ips: Vec<Ipv4Addr> = Vec::new();
    if let Ok(IpAddr::V4(primary)) = local_ip_address::local_ip() {
        if usable(&primary) {
            ips.push(primary);
        }
    }
    if let Ok(ifaces) = local_ip_address::list_afinet_netifas() {
        for (name, ip) in ifaces {
            let lname = name.to_lowercase();
            let virtual_iface = ["docker", "veth", "vbox", "vmnet", "vethernet", "br-", "utun", "tailscale", "zt"]
                .iter()
                .any(|p| lname.starts_with(p) || lname.contains("virtual") || lname.contains("hyper-v"));
            if let IpAddr::V4(v4) = ip {
                if usable(&v4) && !virtual_iface && !ips.contains(&v4) {
                    ips.push(v4);
                }
            }
        }
    }
    ips.into_iter().map(|ip| ip.to_string()).collect()
}

fn usable(ip: &Ipv4Addr) -> bool {
    !ip.is_loopback() && !ip.is_link_local() && !ip.is_unspecified() && !ip.is_multicast()
}

fn instance_name(desktop_name: &str, device_id: &str) -> String {
    let clean: String = desktop_name
        .chars()
        .filter(|c| c.is_alphanumeric() || *c == ' ' || *c == '-' || *c == '_')
        .take(40)
        .collect();
    let suffix: String = device_id.chars().take(4).collect();
    let base = if clean.trim().is_empty() { "BarcodeSync Desktop".to_string() } else { clean.trim().to_string() };
    format!("{base} ({suffix})")
}

/// Registers the mDNS service. Returns `true` on success.
pub fn start_mdns(app: &AppHandle) -> bool {
    let shared = app.state::<Shared>();
    let (name, device_id, port) = {
        let inner = shared.inner.lock().unwrap();
        (inner.desktop_name.clone(), inner.config.device_id.clone(), inner.port)
    };

    let daemon = match ServiceDaemon::new() {
        Ok(d) => d,
        Err(err) => {
            eprintln!("[mdns] daemon failed: {err}");
            return false;
        }
    };
    let host_label: String = name
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_lowercase() } else { '-' })
        .collect();
    let host_name = format!("{}-barcodesync.local.", host_label.trim_matches('-'));
    let version = env!("CARGO_PKG_VERSION").to_string();
    let proto = PROTOCOL_VERSION.to_string();
    let properties = [
        ("id", device_id.as_str()),
        ("name", name.as_str()),
        ("platform", desktop_platform()),
        ("ver", version.as_str()),
        ("proto", proto.as_str()),
    ];
    let info = match ServiceInfo::new(SERVICE_TYPE, &instance_name(&name, &device_id), &host_name, "", port, &properties[..]) {
        Ok(info) => info.enable_addr_auto(),
        Err(err) => {
            eprintln!("[mdns] service info failed: {err}");
            return false;
        }
    };
    let fullname = info.get_fullname().to_string();
    if let Err(err) = daemon.register(info) {
        eprintln!("[mdns] register failed: {err}");
        return false;
    }
    *app.state::<MdnsHandle>().daemon.lock().unwrap() = Some((daemon, fullname));
    true
}

/// Answers UDP `discover` broadcasts with an `announce` datagram and tracks
/// nearby phones so they show up on the dashboard before connecting.
pub async fn run_udp_responder(app: AppHandle) {
    let socket = match UdpSocket::bind(("0.0.0.0", DISCOVERY_PORT)).await {
        Ok(s) => s,
        Err(err) => {
            eprintln!("[udp] bind {DISCOVERY_PORT} failed: {err}");
            return;
        }
    };
    let _ = socket.set_broadcast(true);
    {
        let shared = app.state::<Shared>();
        shared.inner.lock().unwrap().udp_active = true;
    }
    emit_state(&app);

    let mut buf = vec![0u8; 2048];
    loop {
        let (len, from) = match socket.recv_from(&mut buf).await {
            Ok(v) => v,
            Err(err) => {
                eprintln!("[udp] recv failed: {err}");
                tokio::time::sleep(Duration::from_millis(500)).await;
                continue;
            }
        };
        let Ok(packet) = serde_json::from_slice::<DiscoverPacket>(&buf[..len]) else { continue };
        if packet.kind != "discover" {
            continue;
        }

        let reply = {
            let shared = app.state::<Shared>();
            let mut inner = shared.inner.lock().unwrap();
            inner.nearby.insert(
                packet.device_id.clone(),
                NearbyDevice {
                    device_id: packet.device_id.clone(),
                    device_name: truncate(&packet.device_name, 64),
                    platform: truncate(&packet.platform, 16),
                    address: from.ip().to_string(),
                    last_seen: now_ms(),
                },
            );
            AnnouncePacket {
                kind: "announce",
                device_id: inner.config.device_id.clone(),
                device_name: inner.desktop_name.clone(),
                platform: desktop_platform().to_string(),
                app_version: env!("CARGO_PKG_VERSION").to_string(),
                protocol_version: PROTOCOL_VERSION,
                port: inner.port,
                ips: inner.ips.clone(),
            }
        };
        if let Ok(bytes) = serde_json::to_vec(&reply) {
            let _ = socket.send_to(&bytes, from).await;
        }
        emit_state(&app);
    }
}

/// Periodically prunes stale nearby devices and refreshes local IPs so the
/// pairing QR code follows Wi-Fi changes.
pub async fn run_housekeeping(app: AppHandle) {
    let mut tick = tokio::time::interval(Duration::from_secs(3));
    loop {
        tick.tick().await;
        let changed = {
            let shared = app.state::<Shared>();
            let mut inner = shared.inner.lock().unwrap();
            let now = now_ms();
            let before = inner.nearby.len();
            inner.nearby.retain(|_, n| now.saturating_sub(n.last_seen) < NEARBY_TTL_MS);
            let ips = local_ipv4s();
            let ips_changed = ips != inner.ips;
            if ips_changed {
                inner.ips = ips;
            }
            before != inner.nearby.len() || ips_changed
        };
        if changed {
            emit_state(&app);
        }
    }
}

pub fn truncate(input: &str, max: usize) -> String {
    input.chars().filter(|c| !c.is_control()).take(max).collect()
}
