#[cfg(target_os = "linux")]
mod linux {
    use adw::prelude::*;
    use gtk4 as gtk;
    use libadwaita as adw;
    use serde::Deserialize;
    use std::cell::RefCell;
    use std::process::{Child, Command, Stdio};
    use std::rc::Rc;

    const APP_ID: &str = "com.centurion.desktop";

    #[derive(Default)]
    struct RemoteSupervisor {
        child: Option<Child>,
    }

    #[derive(Debug, Deserialize)]
    struct DeviceListing {
        approved: Vec<DeviceEntry>,
        pending: Vec<DeviceEntry>,
    }

    #[derive(Debug, Deserialize)]
    struct DeviceEntry {
        fingerprint: String,
        name: String,
        #[serde(default)]
        connected: bool,
        #[serde(default)]
        peer: Option<String>,
    }

    impl RemoteSupervisor {
        fn ensure_running(&mut self) -> Result<(), String> {
            if remote_listener_active() {
                return Ok(());
            }

            if let Some(child) = self.child.as_mut() {
                if child
                    .try_wait()
                    .map_err(|error| error.to_string())?
                    .is_none()
                {
                    return Ok(());
                }
            }

            let centurion_remote = std::env::var("HOME")
                .ok()
                .map(|home| format!("{home}/.local/bin/centurion-remote"))
                .filter(|path| std::path::Path::new(path).is_file())
                .unwrap_or_else(|| "centurion-remote".to_owned());

            let child = Command::new(&centurion_remote)
                .arg("serve")
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::inherit())
                .env(
                    "CENTURION_HOME",
                    std::env::var("CENTURION_HOME").unwrap_or_else(|_| {
                        format!(
                            "{}/.centurion",
                            std::env::var("HOME").unwrap_or_else(|_| ".".to_owned())
                        )
                    }),
                )
                .spawn()
                .map_err(|error| format!("Could not start your Centurion: {error}"))?;
            self.child = Some(child);
            Ok(())
        }

        fn restart(&mut self) -> Result<(), String> {
            if let Some(mut child) = self.child.take() {
                let _ = child.kill();
                let _ = child.wait();
            }
            self.ensure_running()
        }
    }

    pub fn run() {
        let application = adw::Application::builder().application_id(APP_ID).build();
        let supervisor = Rc::new(RefCell::new(RemoteSupervisor::default()));

        application.connect_startup(|_| load_brand_css());
        application.connect_activate(move |application| {
            build_window(application, supervisor.clone());
        });
        application.run();
    }

    fn app_icon_image(size: i32) -> gtk::Image {
        let bytes = glib::Bytes::from_static(include_bytes!(
            "../../resources/icons/hicolor/256x256/apps/com.centurion.desktop.png"
        ));
        let texture = gtk::gdk::Texture::from_bytes(&bytes)
            .expect("Centurion app icon should load");
        let image = gtk::Image::from_paintable(Some(&texture));
        image.set_pixel_size(size);
        image
    }

    fn load_brand_css() {
        let provider = gtk::CssProvider::new();
        provider.load_from_string(include_str!("../../resources/centurion.css"));
        gtk::style_context_add_provider_for_display(
            &gtk::gdk::Display::default().expect("GTK display"),
            &provider,
            gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }

    fn remote_listener_active() -> bool {
        use std::net::{SocketAddr, TcpStream};
        use std::time::Duration;
        let address: SocketAddr = "127.0.0.1:9119".parse().expect("loopback port");
        TcpStream::connect_timeout(&address, Duration::from_millis(300)).is_ok()
    }

    fn build_window(application: &adw::Application, supervisor: Rc<RefCell<RemoteSupervisor>>) {
        if let Some(window) = application.active_window() {
            window.present();
            return;
        }

        let status_title = gtk::Label::builder()
            .label("Your Centurion is starting…")
            .css_classes(["centurion-hero"])
            .wrap(true)
            .build();
        let status_detail = gtk::Label::builder()
            .label("Preparing the private connection for your iPhone.")
            .css_classes(["dim-label"])
            .wrap(true)
            .build();

        let status_card = gtk::Box::new(gtk::Orientation::Vertical, 12);
        status_card.add_css_class("centurion-card");
        status_card.append(&app_icon_image(72));
        status_card.append(&status_title);
        status_card.append(&status_detail);

        let restart = gtk::Button::with_label("Restart Centurion");
        restart.add_css_class("suggested-action");
        restart.set_size_request(-1, 44);
        status_card.append(&restart);

        let home = gtk::Box::new(gtk::Orientation::Vertical, 24);
        home.set_margin_top(32);
        home.set_margin_bottom(32);
        home.set_margin_start(32);
        home.set_margin_end(32);
        home.append(&status_card);

        let devices = gtk::Box::new(gtk::Orientation::Vertical, 16);
        devices.set_margin_top(32);
        devices.set_margin_start(32);
        devices.set_margin_end(32);
        let devices_heading = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        devices_heading.append(
            &gtk::Label::builder()
                .label("Connected Devices")
                .css_classes(["title-1"])
                .xalign(0.0)
                .hexpand(true)
                .build(),
        );
        let refresh_devices_button = gtk::Button::from_icon_name("view-refresh-symbolic");
        refresh_devices_button.set_tooltip_text(Some("Refresh devices"));
        devices_heading.append(&refresh_devices_button);
        devices.append(&devices_heading);
        devices.append(
            &gtk::Label::builder()
                .label(
                    "Approved iPhones will appear here. You can review or revoke them at any time.",
                )
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );
        let device_list = gtk::ListBox::new();
        device_list.add_css_class("boxed-list");
        refresh_devices(&device_list);
        let refresh_list = device_list.clone();
        refresh_devices_button.connect_clicked(move |_| refresh_devices(&refresh_list));
        devices.append(&device_list);

        let settings = gtk::Box::new(gtk::Orientation::Vertical, 16);
        settings.set_margin_top(32);
        settings.set_margin_start(32);
        settings.set_margin_end(32);
        settings.append(
            &gtk::Label::builder()
                .label("Settings")
                .css_classes(["title-1"])
                .xalign(0.0)
                .build(),
        );
        let settings_list = gtk::ListBox::new();
        settings_list.add_css_class("boxed-list");
        settings_list.append(
            &adw::ActionRow::builder()
                .title("Private network")
                .subtitle("Your Centurion is discoverable only on this local network.")
                .icon_name("network-wireless-symbolic")
                .build(),
        );
        settings_list.append(
            &adw::ActionRow::builder()
                .title("Version")
                .subtitle(env!("CARGO_PKG_VERSION"))
                .icon_name("dialog-information-symbolic")
                .build(),
        );
        settings.append(&settings_list);

        let chat = build_chat_page();

        let stack = gtk::Stack::builder()
            .transition_type(gtk::StackTransitionType::Crossfade)
            .transition_duration(180)
            .build();
        stack.add_titled(&home, Some("home"), "Home");
        stack.add_titled(&chat, Some("chat"), "Chat");
        stack.add_titled(&devices, Some("devices"), "Devices");
        stack.add_titled(&settings, Some("settings"), "Settings");

        let poll_list = device_list.clone();
        let poll_stack = stack.clone();
        glib::timeout_add_seconds_local(5, move || {
            if poll_stack.visible_child_name().as_deref() == Some("devices") {
                refresh_devices(&poll_list);
            }
            glib::ControlFlow::Continue
        });
        let tab_refresh_list = device_list.clone();
        stack.connect_visible_child_name_notify(move |stack| {
            if stack.visible_child_name().as_deref() == Some("devices") {
                refresh_devices(&tab_refresh_list);
            }
        });

        let switcher = gtk::StackSwitcher::builder().stack(&stack).build();
        let header = adw::HeaderBar::new();
        header.set_title_widget(Some(&switcher));
        let toolbar = adw::ToolbarView::new();
        toolbar.add_top_bar(&header);
        toolbar.set_content(Some(&stack));

        let window = adw::ApplicationWindow::builder()
            .application(application)
            .title("Centurion")
            .default_width(980)
            .default_height(700)
            .content(&toolbar)
            .build();

        let update_status = {
            let status_title = status_title.clone();
            let status_detail = status_detail.clone();
            let supervisor = supervisor.clone();
            move || match supervisor.borrow_mut().ensure_running() {
                Ok(()) => {
                    status_title.set_label("Your Centurion is ready");
                    status_detail
                        .set_label("Your iPhone can find this Centurion on the private network.");
                }
                Err(error) => {
                    status_title.set_label("Your Centurion needs attention");
                    status_detail.set_label(&error);
                }
            }
        };

        update_status();
        restart.connect_clicked(move |_| {
            let result = supervisor.borrow_mut().restart();
            match result {
                Ok(()) => {
                    status_title.set_label("Your Centurion is ready");
                    status_detail.set_label("The private iPhone connection has restarted safely.");
                }
                Err(error) => {
                    status_title.set_label("Restart did not complete");
                    status_detail.set_label(&error);
                }
            }
        });

        window.present();
    }

    fn build_chat_page() -> gtk::Box {
        use gio::prelude::*;
        use vte4::prelude::TerminalExtManual;
        use vte4::TerminalExt;

        let container = gtk::Box::new(gtk::Orientation::Vertical, 12);
        container.set_margin_top(16);
        container.set_margin_bottom(16);
        container.set_margin_start(16);
        container.set_margin_end(16);
        container.set_vexpand(true);
        container.set_hexpand(true);

        container.append(
            &gtk::Label::builder()
                .label("Your Centurion")
                .css_classes(["title-1"])
                .xalign(0.0)
                .build(),
        );
        container.append(
            &gtk::Label::builder()
                .label("Talk with your Centurion here — the same conversation you would have on this computer.")
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );

        let scrolled = gtk::ScrolledWindow::builder()
            .vexpand(true)
            .hexpand(true)
            .focusable(true)
            .build();
        let terminal = vte4::Terminal::new();
        terminal.set_vexpand(true);
        terminal.set_hexpand(true);
        terminal.set_cursor_blink_mode(vte4::CursorBlinkMode::On);
        terminal.set_input_enabled(true);
        scrolled.set_child(Some(&terminal));
        container.append(&scrolled);

        let chat_spawned = Rc::new(RefCell::new(false));
        let spawn_chat = {
            let terminal = terminal.clone();
            let chat_spawned = chat_spawned.clone();
            move || {
                if *chat_spawned.borrow() {
                    return;
                }
                *chat_spawned.borrow_mut() = true;

                let mut envv: Vec<String> = std::env::vars()
                    .map(|(key, value)| format!("{key}={value}"))
                    .collect();
                envv.push("CENTURION_TUI_INLINE=1".to_owned());
                envv.push("CENTURION_TUI_DISABLE_MOUSE=1".to_owned());
                let env_refs: Vec<&str> = envv.iter().map(String::as_str).collect();

                terminal.spawn_async(
                    vte4::PtyFlags::DEFAULT,
                    None::<&str>,
                    &["centurion", "--tui"],
                    &env_refs,
                    glib::SpawnFlags::SEARCH_PATH,
                    || {},
                    -1,
                    None::<&gio::Cancellable>,
                    |_result| {},
                );
            }
        };

        spawn_chat();
        container
    }

    fn refresh_devices(list: &gtk::ListBox) {
        while let Some(child) = list.first_child() {
            list.remove(&child);
        }

        let centurion_remote = std::env::var("HOME")
            .ok()
            .map(|home| format!("{home}/.local/bin/centurion-remote"))
            .filter(|path| std::path::Path::new(path).is_file())
            .unwrap_or_else(|| "centurion-remote".to_owned());

        let output = Command::new(&centurion_remote)
            .args(["devices", "--json"])
            .output();
        let listing = output
            .ok()
            .filter(|output| output.status.success())
            .and_then(|output| serde_json::from_slice::<DeviceListing>(&output.stdout).ok());

        let Some(listing) = listing else {
            list.append(
                &adw::ActionRow::builder()
                    .title("Device status unavailable")
                    .subtitle("Start your Centurion, then refresh.")
                    .icon_name("dialog-warning-symbolic")
                    .build(),
            );
            return;
        };

        let pending = listing.pending;
        let approved = listing.approved;
        let show_no_devices = pending.is_empty() && approved.is_empty();
        let show_no_connected = !approved.is_empty()
            && pending.is_empty()
            && approved.iter().all(|device| !device.connected);

        for device in pending {
            let row = adw::ActionRow::builder()
                .title(&device.name)
                .subtitle(format!("Waiting for your approval · {}", device.fingerprint))
                .icon_name("phone-symbolic")
                .build();
            let approve = gtk::Button::with_label("Approve");
            approve.add_css_class("suggested-action");
            approve.set_valign(gtk::Align::Center);
            let fingerprint = device.fingerprint;
            let name = device.name;
            let list_refresh = list.clone();
            let remote = centurion_remote.clone();
            approve.connect_clicked(move |button| {
                button.set_sensitive(false);
                let approved = Command::new(&remote)
                    .args(["approve", &fingerprint, "--name", &name])
                    .status()
                    .is_ok_and(|status| status.success());
                if approved {
                    refresh_devices(&list_refresh);
                } else {
                    button.set_sensitive(true);
                }
            });
            row.add_suffix(&approve);
            list.append(&row);
        }

        for device in approved {
            let subtitle = if device.connected {
                format!(
                    "Connected · {} · {}",
                    device.peer.as_deref().unwrap_or("unknown"),
                    device.fingerprint
                )
            } else {
                format!("Approved · {}", device.fingerprint)
            };
            let row = adw::ActionRow::builder()
                .title(&device.name)
                .subtitle(&subtitle)
                .icon_name(if device.connected {
                    "phone-symbolic"
                } else {
                    "phone-disabled-symbolic"
                })
                .build();
            let revoke = gtk::Button::with_label("Revoke");
            revoke.add_css_class("destructive-action");
            revoke.set_valign(gtk::Align::Center);
            let fingerprint = device.fingerprint;
            let list_refresh = list.clone();
            let remote = centurion_remote.clone();
            revoke.connect_clicked(move |button| {
                button.set_sensitive(false);
                let revoked = Command::new(&remote)
                    .args(["revoke", &fingerprint])
                    .status()
                    .is_ok_and(|status| status.success());
                if revoked {
                    refresh_devices(&list_refresh);
                } else {
                    button.set_sensitive(true);
                }
            });
            row.add_suffix(&revoke);
            list.append(&row);
        }

        if show_no_devices {
            list.append(
                &adw::ActionRow::builder()
                    .title("No iPhones connected")
                    .subtitle("Open Connect in CenturionAI Remote on the same network.")
                    .icon_name("phone-symbolic")
                    .build(),
            );
        } else if show_no_connected {
            list.append(
                &adw::ActionRow::builder()
                    .title("No iPhones connected right now")
                    .subtitle("Approved devices will appear here when they link from your iPhone.")
                    .icon_name("phone-disabled-symbolic")
                    .build(),
            );
        }
    }
}

#[cfg(target_os = "linux")]
fn main() {
    linux::run();
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("Centurion Desktop is a native Linux application.");
}
