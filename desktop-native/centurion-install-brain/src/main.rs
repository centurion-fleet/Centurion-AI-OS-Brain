//! Terminal-free Get Brain installer (Fedora / GNOME).
//!
//! Double-click `Install-Brain` in the extracted archive. Shows a GTK progress
//! window, runs `install.sh`, then a success or error screen — no Terminal.

#![cfg_attr(not(target_os = "linux"), allow(dead_code))]

#[cfg(target_os = "linux")]
fn main() {
    linux::run();
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("Install-Brain is Linux-only. Build and ship it from a Linux host.");
    std::process::exit(1);
}

#[cfg(target_os = "linux")]
mod linux {
    use gtk4::gio::ApplicationFlags;
    use gtk4::glib::{self, ControlFlow};
    use gtk4::prelude::*;
    use gtk4::{
        Align, Application, ApplicationWindow, Box as GtkBox, Button, Label, Orientation, Spinner,
    };
    use std::env;
    use std::path::{Path, PathBuf};
    use std::process::{Command, Stdio};
    use std::sync::mpsc;
    use std::time::Duration;

    const APP_ID: &str = "com.centurion.install-brain";

    enum InstallEvent {
        Done { ok: bool, detail: String },
    }

    pub fn run() {
        let application = Application::builder()
            .application_id(APP_ID)
            .flags(ApplicationFlags::NON_UNIQUE)
            .build();

        application.connect_activate(build_ui);

        let args: Vec<String> = vec![];
        application.run_with_args(&args);
    }

    fn build_ui(app: &Application) {
        let here = resolve_here();
        let install_sh = here.join("install.sh");

        let window = ApplicationWindow::builder()
            .application(app)
            .title("Install Sovereign AI Brain")
            .default_width(480)
            .default_height(220)
            .resizable(false)
            .build();

        let root = GtkBox::new(Orientation::Vertical, 16);
        root.set_margin_top(28);
        root.set_margin_bottom(28);
        root.set_margin_start(28);
        root.set_margin_end(28);

        let title = Label::builder()
            .label("Installing Sovereign AI Brain")
            .halign(Align::Start)
            .xalign(0.0)
            .build();
        title.add_css_class("title-2");
        root.append(&title);

        let status = Label::builder()
            .label("Keeping your existing Centurion settings. This takes a moment…")
            .wrap(true)
            .halign(Align::Start)
            .xalign(0.0)
            .build();
        root.append(&status);

        let spinner = Spinner::new();
        spinner.set_halign(Align::Start);
        spinner.start();
        root.append(&spinner);

        window.set_child(Some(&root));
        window.present();

        if !install_sh.is_file() {
            show_finished(
                &window,
                false,
                "Install could not start",
                &format!(
                    "Could not find install.sh next to Install-Brain.\n\nLooked in:\n{}",
                    here.display()
                ),
            );
            return;
        }

        let (tx, rx) = mpsc::channel::<InstallEvent>();
        let here_thread = here.clone();
        std::thread::spawn(move || {
            let result = run_install_script(&here_thread, &install_sh);
            let _ = tx.send(match result {
                Ok(detail) => InstallEvent::Done { ok: true, detail },
                Err(detail) => InstallEvent::Done { ok: false, detail },
            });
        });

        let window_c = window.clone();
        glib::timeout_add_local(Duration::from_millis(80), move || match rx.try_recv() {
            Ok(InstallEvent::Done { ok, detail }) => {
                if ok {
                    show_finished(
                        &window_c,
                        true,
                        "Sovereign AI Brain is installed",
                        &format!(
                            "{detail}\n\nOpen it from Applications as “Sovereign AI Brain”.\nDo not open it from Downloads."
                        ),
                    );
                } else {
                    show_finished(&window_c, false, "Install did not complete", &detail);
                }
                ControlFlow::Break
            }
            Err(mpsc::TryRecvError::Empty) => ControlFlow::Continue,
            Err(mpsc::TryRecvError::Disconnected) => {
                show_finished(
                    &window_c,
                    false,
                    "Install stopped unexpectedly",
                    "The installer closed before finishing. Try again, or contact your advisor.",
                );
                ControlFlow::Break
            }
        });
    }

    fn show_finished(window: &ApplicationWindow, ok: bool, heading: &str, body: &str) {
        let root = GtkBox::new(Orientation::Vertical, 16);
        root.set_margin_top(28);
        root.set_margin_bottom(28);
        root.set_margin_start(28);
        root.set_margin_end(28);

        let title = Label::builder()
            .label(heading)
            .wrap(true)
            .halign(Align::Start)
            .xalign(0.0)
            .build();
        title.add_css_class("title-2");
        root.append(&title);

        let detail = Label::builder()
            .label(body)
            .wrap(true)
            .halign(Align::Start)
            .xalign(0.0)
            .selectable(true)
            .build();
        if !ok {
            detail.add_css_class("error");
        }
        root.append(&detail);

        let close = Button::with_label(if ok { "Done" } else { "Close" });
        close.set_halign(Align::End);
        if ok {
            close.add_css_class("suggested-action");
        }
        let window_c = window.clone();
        close.connect_clicked(move |_| {
            window_c.close();
        });
        root.append(&close);

        window.set_title(Some(if ok {
            "Install complete"
        } else {
            "Install failed"
        }));
        window.set_child(Some(&root));
    }

    fn run_install_script(here: &Path, install_sh: &Path) -> Result<String, String> {
        let _ = Command::new("chmod")
            .args(["+x", &install_sh.to_string_lossy()])
            .status();

        let log_fallback = here.join("install-brain.log");
        let output = Command::new("bash")
            .arg(install_sh)
            .current_dir(here)
            .env("CENTURION_GUI_INSTALL", "1")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .map_err(|e| format!("Could not start install.sh: {e}"))?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        let combined = format!("{stdout}{stderr}");
        let _ = std::fs::write(&log_fallback, combined.as_bytes());

        if output.status.success() {
            return Ok(extract_success_summary(&combined)
                .unwrap_or_else(|| "Your Centurion data was kept.".to_owned()));
        }

        Err(extract_error_summary(&combined).unwrap_or_else(|| {
            format!(
                "Installer exited with {}.\n\n{}",
                output.status,
                tail_lines(&combined, 12)
            )
        }))
    }

    fn extract_success_summary(text: &str) -> Option<String> {
        for line in text.lines().rev() {
            let t = line.trim();
            if t.starts_with("Installed Sovereign AI Brain") {
                return Some(t.to_owned());
            }
        }
        if text.contains("Installed:") {
            return Some("Installed successfully. Your Centurion settings were kept.".to_owned());
        }
        None
    }

    fn extract_error_summary(text: &str) -> Option<String> {
        for line in text.lines().rev() {
            let t = line.trim();
            if let Some(rest) = t.strip_prefix("ERROR: ") {
                return Some(rest.to_owned());
            }
        }
        None
    }

    fn tail_lines(text: &str, n: usize) -> String {
        let lines: Vec<&str> = text.lines().collect();
        let start = lines.len().saturating_sub(n);
        lines[start..].join("\n")
    }

    fn resolve_here() -> PathBuf {
        if let Ok(exe) = env::current_exe() {
            let canonical = exe.canonicalize().unwrap_or(exe);
            if let Some(dir) = canonical.parent() {
                return dir.to_path_buf();
            }
        }
        env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
    }
}
