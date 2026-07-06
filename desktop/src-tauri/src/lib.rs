use tauri::Manager;

/// System tray menu handler — Quit and Show
fn build_tray_menu(app: &tauri::AppHandle) -> tauri::menu::Menu<tauri::Wry> {
    use tauri::menu::*;
    let menu = MenuBuilder::new(app)
        .text("show-window", "Show Centurion")
        .separator()
        .text("quit", "Quit")
        .build()
        .unwrap();

    // Handle tray menu events
    app.on_menu_event(move |app_handle, event| {
        match event.id().as_ref() {
            "quit" => {
                app_handle.exit(0);
            }
            "show-window" => {
                if let Some(window) = app_handle.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            _ => {}
        }
    });

    menu
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .setup(|app| {
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
