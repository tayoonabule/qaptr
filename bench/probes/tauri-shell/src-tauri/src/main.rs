use std::env;
use std::fs::OpenOptions;
use std::io::Write;
use tauri::Manager;

#[cfg(target_os = "macos")]
#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    fn CGPreflightScreenCaptureAccess() -> bool;
    fn CGRequestScreenCaptureAccess() -> bool;
}

fn append_line(path_var: &str, fallback: &str, line: &str) {
    let path = env::var_os(path_var).unwrap_or_else(|| fallback.into());
    let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) else {
        return;
    };
    let _ = writeln!(file, "{line}");
}

#[tauri::command]
fn record_paint() {
    append_line(
        "QAPTR_U3_PAINT_FILE",
        "/tmp/qaptr-u3-tauri-paint",
        &format!(
            "{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        ),
    );
}

#[tauri::command]
fn screen_capture_permission() -> String {
    #[cfg(target_os = "macos")]
    {
        let before = unsafe { CGPreflightScreenCaptureAccess() };
        let requested = if env::var("QAPTR_U3_REQUEST_TCC").as_deref() == Ok("1") {
            unsafe { CGRequestScreenCaptureAccess() }
        } else {
            false
        };
        let after = unsafe { CGPreflightScreenCaptureAccess() };
        let record = format!(
            "before={} requested={} after={} pid={}",
            before as u8,
            requested as u8,
            after as u8,
            std::process::id()
        );
        append_line("QAPTR_U3_TCC_FILE", "/tmp/qaptr-u3-tauri-tcc", &record);
        record
    }
    #[cfg(not(target_os = "macos"))]
    {
        "unsupported".to_string()
    }
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            record_paint,
            screen_capture_permission
        ])
        .setup(|app| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.set_title("Qaptr Tauri Shell");
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running Tauri application");
}
