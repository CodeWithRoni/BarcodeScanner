//! BarcodeSync desktop: receives scans from the companion phone app over the
//! local network and types, copies or logs them.

mod commands;
mod discovery;
mod injector;
mod protocol;
mod server;
mod state;
mod tray;

use tauri::{Manager, WindowEvent};
use tauri_plugin_autostart::MacosLauncher;

use crate::state::{emit_state, Shared};

pub const AUTOSTART_FLAG: &str = "--autostart";

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            tray::show_main(app);
        }))
        .plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, Some(vec![AUTOSTART_FLAG])))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .setup(|app| {
            let handle = app.handle().clone();
            app.manage(Shared::load(&handle));
            app.manage(discovery::MdnsHandle::default());
            commands::sync_autostart(&handle);
            tray::create(&handle)?;

            let start_minimized = app.state::<Shared>().inner.lock().unwrap().config.settings.start_minimized;
            if start_minimized {
                tray::hide_main(&handle);
            } else {
                tray::show_main(&handle);
            }

            tauri::async_runtime::spawn(async move {
                if let Some(listener) = server::bind(&handle).await {
                    let ok = discovery::start_mdns(&handle);
                    handle.state::<Shared>().inner.lock().unwrap().mdns_active = ok;
                    emit_state(&handle);
                    let udp = handle.clone();
                    tauri::async_runtime::spawn(discovery::run_udp_responder(udp));
                    let house = handle.clone();
                    tauri::async_runtime::spawn(discovery::run_housekeeping(house));
                    server::run(handle, listener).await;
                } else {
                    emit_state(&handle);
                }
            });
            Ok(())
        })
        .on_window_event(|window, event| match event {
            WindowEvent::CloseRequested { api, .. } => {
                api.prevent_close();
                tray::hide_main(window.app_handle());
            }
            WindowEvent::Resized(_) if window.is_minimized().unwrap_or(false) => {
                tray::hide_main(window.app_handle());
            }
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_snapshot,
            commands::get_history,
            commands::update_settings,
            commands::respond_pairing,
            commands::disconnect_device,
            commands::reset_pairing,
            commands::clear_history,
            commands::export_history,
            commands::copy_text,
            commands::hide_window,
            commands::quit_app,
        ])
        .build(tauri::generate_context!())
        .expect("error while building BarcodeSync")
        .run(|app, event| {
            if let tauri::RunEvent::ExitRequested { api, code, .. } = event {
                // Keep running in the tray when the last window is hidden; only an
                // explicit Quit (which passes an exit code) terminates the process.
                if code.is_none() {
                    api.prevent_exit();
                } else {
                    app.state::<discovery::MdnsHandle>().shutdown();
                }
            }
        });
}
