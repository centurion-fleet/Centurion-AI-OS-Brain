use tauri::Manager;
use tauri_plugin_shell::ShellExt;

/// System tray menu handler — Quit, Show, Restart Backend
fn build_tray_menu(app: &tauri::AppHandle) -> tauri::menu::Menu<tauri::Wry> {
    use tauri::menu::*;
    let menu = MenuBuilder::new(app)
        .text("show-window", "Show Centurion")
        .text("restart-backend", "Restart Backend")
        .separator()
        .text("quit", "Quit")
        .build()
        .unwrap();

    menu
}

#[tauri::command]
fn get_centurion_status() -> String {
    // Simple status check
    "running".to_string()
}

fn start_python_backend(app: &tauri::AppHandle) {
    let resource_dir = app.path().resource_dir().unwrap_or_default();
    let project_root = resource_dir.parent().unwrap_or(&resource_dir);

    // Try to find the Python backend in dev mode vs bundled
    let backend_script = if cfg!(debug_assertions) {
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join("centurion_cli")
            .join("web_server.py")
    } else {
        resource_dir.join("centurion_cli").join("web_server.py")
    };

    // Start Bonjour advertisement
    let _ = app.shell()
        .command("python3")
        .args(["-m", "centurion_cli.web_server", "--port", "9119"])
        .spawn();

    println!("[Centurion] Python backend started on :9119");
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![get_centurion_status])
        .setup(|app| {
            // Start the Python backend on launch
            start_python_backend(app.handle());

            // Set up system tray
            let _tray = tauri::tray::TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&build_tray_menu(app.handle()))
                .tooltip("Centurion OS Desktop")
                .on_tray_icon_event(|tray, event| {
                    if let tauri::tray::TrayIconEvent::DoubleClick { .. } = event {
                        if let Some(window) = tray.app_handle().get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                })
                .build(app)?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running Centurion OS Desktop");
}
