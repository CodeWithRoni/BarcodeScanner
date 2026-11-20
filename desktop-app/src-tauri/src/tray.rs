//! System tray icon, menu and window lifecycle (hide to tray instead of quit).

use std::sync::Mutex;

use tauri::image::Image;
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager, Wry};

use crate::state::{emit_state, OverallStatus, Shared};

pub struct TrayHandles {
    status: MenuItem<Wry>,
    pause: CheckMenuItem<Wry>,
    last: Mutex<Option<(OverallStatus, usize, bool)>>,
}

pub fn show_main(app: &AppHandle) {
    #[cfg(target_os = "macos")]
    let _ = app.set_activation_policy(tauri::ActivationPolicy::Regular);
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_skip_taskbar(false);
        let _ = window.set_focus();
    }
}

pub fn hide_main(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.set_skip_taskbar(true);
        let _ = window.hide();
    }
    #[cfg(target_os = "macos")]
    let _ = app.set_activation_policy(tauri::ActivationPolicy::Accessory);
}

pub fn set_paused(app: &AppHandle, paused: bool) {
    let shared = app.state::<Shared>();
    shared.inner.lock().unwrap().config.settings.paused = paused;
    shared.save_config();
    shared.broadcast(crate::protocol::Outgoing::Status { paused });
    emit_state(app);
}

pub fn quit(app: &AppHandle) {
    app.state::<crate::discovery::MdnsHandle>().shutdown();
    app.state::<Shared>().save_history();
    app.exit(0);
}

pub fn create(app: &AppHandle) -> tauri::Result<()> {
    let paused = app.state::<Shared>().inner.lock().unwrap().config.settings.paused;
    let open = MenuItem::with_id(app, "open", "Open Dashboard", true, None::<&str>)?;
    let status = MenuItem::with_id(app, "status", "Status: Waiting", false, None::<&str>)?;
    let pause = CheckMenuItem::with_id(app, "pause", "Pause Scanning", true, paused, None::<&str>)?;
    let quit_item = MenuItem::with_id(app, "quit", "Quit BarcodeSync", true, None::<&str>)?;
    let sep1 = PredefinedMenuItem::separator(app)?;
    let sep2 = PredefinedMenuItem::separator(app)?;
    let menu = Menu::with_items(app, &[&open, &sep1, &status, &pause, &sep2, &quit_item])?;

    #[cfg(target_os = "macos")]
    let (icon, template) = (Image::from_bytes(include_bytes!("../icons/tray-template.png"))?, true);
    #[cfg(not(target_os = "macos"))]
    let (icon, template) = (Image::from_bytes(include_bytes!("../icons/tray.png"))?, false);

    TrayIconBuilder::with_id("main-tray")
        .icon(icon)
        .icon_as_template(template)
        .tooltip("BarcodeSync — Waiting for phone")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "open" => show_main(app),
            "pause" => {
                let paused = !app.state::<Shared>().inner.lock().unwrap().config.settings.paused;
                set_paused(app, paused);
            }
            "quit" => quit(app),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                show_main(tray.app_handle());
            }
        })
        .build(app)?;

    app.manage(TrayHandles { status, pause, last: Mutex::new(None) });
    Ok(())
}

/// Updates the tray status line, pause checkbox and tooltip.
pub fn refresh(app: &AppHandle, status: OverallStatus, devices: usize, paused: bool) {
    let Some(handles) = app.try_state::<TrayHandles>() else { return };
    {
        let mut last = handles.last.lock().unwrap();
        if *last == Some((status, devices, paused)) {
            return;
        }
        *last = Some((status, devices, paused));
    }
    let label = match status {
        OverallStatus::Connected if devices > 1 => format!("Status: Connected ({devices} phones)"),
        OverallStatus::Connected => "Status: Connected".to_string(),
        OverallStatus::Paused => "Status: Paused".to_string(),
        OverallStatus::Waiting => "Status: Waiting".to_string(),
    };
    let _ = handles.status.set_text(&label);
    let _ = handles.pause.set_checked(paused);
    if let Some(tray) = app.tray_by_id("main-tray") {
        let _ = tray.set_tooltip(Some(format!("BarcodeSync — {}", label.trim_start_matches("Status: "))));
    }
}
