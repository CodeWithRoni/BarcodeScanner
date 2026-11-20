//! Output engine: keyboard emulation, clipboard copy or log-only.

use enigo::{Direction, Enigo, Key, Keyboard, Settings as EnigoSettings};
use tauri::AppHandle;
use tauri_plugin_clipboard_manager::ClipboardExt;
use tokio::sync::oneshot;

use crate::state::{Delivery, OutputMode};

/// Normalises a payload before it is typed: unifies line endings and drops
/// control characters other than newline and tab.
pub fn sanitize(code: &str) -> String {
    code.replace("\r\n", "\n")
        .replace('\r', "\n")
        .chars()
        .filter(|c| !c.is_control() || *c == '\n' || *c == '\t')
        .collect()
}

fn type_text(text: &str, auto_enter: bool) -> Result<(), String> {
    let mut enigo = Enigo::new(&EnigoSettings::default()).map_err(|e| format!("keyboard unavailable: {e}"))?;
    let mut lines = text.split('\n').peekable();
    while let Some(line) = lines.next() {
        if !line.is_empty() {
            enigo.text(line).map_err(|e| format!("typing failed: {e}"))?;
        }
        if lines.peek().is_some() {
            enigo.key(Key::Return, Direction::Click).map_err(|e| format!("typing failed: {e}"))?;
        }
    }
    if auto_enter {
        enigo.key(Key::Return, Direction::Click).map_err(|e| format!("enter failed: {e}"))?;
    }
    Ok(())
}

/// Delivers a scanned payload using the configured output mode.
///
/// Keyboard emulation runs on the main thread, which macOS requires for
/// synthesising input events; other platforms are happy there too.
pub async fn deliver(app: &AppHandle, mode: OutputMode, code: &str, auto_enter: bool) -> Result<Delivery, String> {
    let text = sanitize(code);
    match mode {
        OutputMode::Log => Ok(Delivery::Logged),
        OutputMode::Clipboard => app
            .clipboard()
            .write_text(text)
            .map(|_| Delivery::Copied)
            .map_err(|e| format!("clipboard failed: {e}")),
        OutputMode::Keyboard => {
            let (tx, rx) = oneshot::channel();
            app.run_on_main_thread(move || {
                let _ = tx.send(type_text(&text, auto_enter));
            })
            .map_err(|e| format!("main thread unavailable: {e}"))?;
            rx.await.map_err(|_| "keyboard task dropped".to_string())??;
            Ok(Delivery::Typed)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::sanitize;

    #[test]
    fn sanitizes_payload() {
        assert_eq!(sanitize("A\r\nB\u{0007}C\rD"), "A\nBC\nD");
    }
}
