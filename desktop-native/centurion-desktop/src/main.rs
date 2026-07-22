#[cfg(target_os = "linux")]
#[allow(
    dead_code,
    unused_imports,
    clippy::map_unwrap_or,
    clippy::too_many_lines
)]
mod adrian;
#[cfg(target_os = "linux")]
#[allow(
    dead_code,
    unused_imports,
    clippy::assigning_clones,
    clippy::needless_pass_by_value,
    clippy::too_many_lines
)]
mod adrian_dialog;

#[cfg(target_os = "linux")]
#[allow(
    dead_code,
    unused_imports,
    clippy::assigning_clones,
    clippy::map_unwrap_or,
    clippy::match_same_arms,
    clippy::match_wildcard_for_single_variants,
    clippy::needless_borrow,
    clippy::needless_borrows_for_generic_args,
    clippy::needless_pass_by_value,
    clippy::redundant_closure_for_method_calls,
    clippy::too_many_lines
)]
mod linux {
    use crate::adrian::AdrianChatContext;
    use crate::adrian_dialog::{AdrianDialogHooks, show_adrian_dialog};
    use adw::prelude::*;
    use gtk4 as gtk;
    use libadwaita as adw;
    use serde::Deserialize;
    use std::cell::RefCell;
    use std::io::Write;
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

    #[derive(Debug, Deserialize)]
    struct ProviderStatusPayload {
        provider: String,
        model: String,
        health: String,
        health_message: String,
        #[serde(default)]
        last_good_available: bool,
    }

    #[derive(Debug, Deserialize)]
    struct ProviderCliResponse {
        ok: bool,
        status: Option<ProviderStatusPayload>,
        options: Option<serde_json::Value>,
        result: Option<serde_json::Value>,
        message: Option<String>,
        code: Option<String>,
    }

    #[derive(Debug, Deserialize)]
    struct UpdateCheckPayload {
        ok: bool,
        #[serde(default)]
        method: Option<String>,
        status: String,
        #[serde(default)]
        behind: u64,
        #[serde(default)]
        os_version: Option<String>,
        #[serde(default)]
        message: Option<String>,
        #[serde(default)]
        recommended_command: Option<String>,
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
        let texture =
            gtk::gdk::Texture::from_bytes(&bytes).expect("Centurion app icon should load");
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

    #[derive(Debug, Default, Clone)]
    struct LinkAddresses {
        magic_dns: Option<String>,
        tailscale_ip: Option<String>,
        lan_ips: Vec<String>,
    }

    fn is_tailscale_ip(ip: &str) -> bool {
        let parts: Vec<u8> = ip
            .split('.')
            .filter_map(|part| part.parse().ok())
            .collect();
        parts.len() == 4 && parts[0] == 100 && (64..=127).contains(&parts[1])
    }

    fn discover_link_addresses() -> LinkAddresses {
        let mut addresses = LinkAddresses::default();

        if let Ok(output) = Command::new("tailscale").args(["ip", "-4"]).output() {
            if output.status.success() {
                let ip = String::from_utf8_lossy(&output.stdout).trim().to_owned();
                if !ip.is_empty() {
                    addresses.tailscale_ip = Some(ip);
                }
            }
        }

        if let Ok(output) = Command::new("tailscale")
            .args(["status", "--json"])
            .output()
        {
            if output.status.success() {
                if let Ok(value) = serde_json::from_slice::<serde_json::Value>(&output.stdout) {
                    if addresses.magic_dns.is_none() {
                        if let Some(dns) = value
                            .get("Self")
                            .and_then(|self_node| self_node.get("DNSName"))
                            .and_then(|v| v.as_str())
                        {
                            let trimmed = dns.trim_end_matches('.').to_owned();
                            if !trimmed.is_empty() {
                                addresses.magic_dns = Some(trimmed);
                            }
                        }
                    }
                    if addresses.tailscale_ip.is_none() {
                        if let Some(ip) = value
                            .get("Self")
                            .and_then(|self_node| self_node.get("TailscaleIPs"))
                            .and_then(|ips| ips.as_array())
                            .and_then(|ips| ips.first())
                            .and_then(|v| v.as_str())
                        {
                            addresses.tailscale_ip = Some(ip.to_owned());
                        }
                    }
                }
            }
        }

        if let Ok(output) = Command::new("hostname").args(["-I"]).output() {
            if output.status.success() {
                for token in String::from_utf8_lossy(&output.stdout).split_whitespace() {
                    if token.contains(':') || token.starts_with("127.") {
                        continue;
                    }
                    if is_tailscale_ip(token) {
                        if addresses.tailscale_ip.is_none() {
                            addresses.tailscale_ip = Some(token.to_owned());
                        }
                        continue;
                    }
                    if !addresses.lan_ips.iter().any(|existing| existing == token) {
                        addresses.lan_ips.push(token.to_owned());
                    }
                }
            }
        }

        addresses
    }

    fn copy_to_clipboard(text: &str) {
        if let Some(display) = gtk::gdk::Display::default() {
            display.clipboard().set_text(text);
        }
    }

    fn build_link_address_row(title: &str, value: &str, _primary: bool) -> gtk::Box {
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        row.set_hexpand(true);
        let labels = gtk::Box::new(gtk::Orientation::Vertical, 2);
        labels.set_hexpand(true);
        labels.append(
            &gtk::Label::builder()
                .label(title)
                .css_classes(["dim-label"])
                .xalign(0.0)
                .build(),
        );
        labels.append(
            &gtk::Label::builder()
                .label(value)
                .selectable(true)
                .xalign(0.0)
                .build(),
        );
        row.append(&labels);
        let copy = gtk::Button::with_label("Copy");
        copy.add_css_class("flat");
        copy.set_valign(gtk::Align::Center);
        let value_owned = value.to_owned();
        copy.connect_clicked(move |_| copy_to_clipboard(&value_owned));
        row.append(&copy);
        row
    }

    fn refresh_link_addresses(container: &gtk::Box) {
        while let Some(child) = container.first_child() {
            container.remove(&child);
        }

        container.append(
            &gtk::Label::builder()
                .label("iPhone link address")
                .css_classes(["title-4"])
                .xalign(0.0)
                .build(),
        );

        let addresses = discover_link_addresses();
        let mut showed_primary = false;

        if let Some(dns) = addresses.magic_dns.as_deref() {
            container.append(&build_link_address_row(
                "Tailscale (preferred)",
                dns,
                true,
            ));
            showed_primary = true;
        } else if let Some(ip) = addresses.tailscale_ip.as_deref() {
            container.append(&build_link_address_row(
                "Tailscale (preferred)",
                ip,
                true,
            ));
            showed_primary = true;
        }

        if showed_primary {
            if let (Some(dns), Some(ip)) = (
                addresses.magic_dns.as_deref(),
                addresses.tailscale_ip.as_deref(),
            ) {
                if dns != ip {
                    container.append(&build_link_address_row("Tailscale IP", ip, false));
                }
            }
        } else {
            container.append(
                &gtk::Label::builder()
                    .label(
                        "Tailscale is not detected. Install and sign in on this Centurion for the preferred iPhone link.",
                    )
                    .wrap(true)
                    .xalign(0.0)
                    .css_classes(["dim-label"])
                    .build(),
            );
        }

        if let Some(lan) = addresses.lan_ips.first() {
            container.append(&build_link_address_row(
                "Wi‑Fi fallback",
                &format!("{lan}:9119"),
                false,
            ));
        }

        container.append(
            &gtk::Label::builder()
                .label(
                    "Allow TCP 9119 on the Tailscale interface (firewall). Crypto Chat stays on your private mesh — not a company relay.",
                )
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .margin_top(4)
                .build(),
        );
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
        let thinking_title = gtk::Label::builder()
            .label("Thinking service")
            .css_classes(["title-4"])
            .xalign(0.0)
            .build();
        let thinking_detail = gtk::Label::builder()
            .label("Checking your Centurion's thinking service…")
            .css_classes(["dim-label"])
            .wrap(true)
            .xalign(0.0)
            .build();

        let status_card = gtk::Box::new(gtk::Orientation::Vertical, 12);
        status_card.add_css_class("centurion-card");
        status_card.append(&app_icon_image(72));
        status_card.append(&status_title);
        status_card.append(&status_detail);

        let link_addresses = gtk::Box::new(gtk::Orientation::Vertical, 8);
        link_addresses.set_margin_top(8);
        refresh_link_addresses(&link_addresses);
        status_card.append(&link_addresses);

        status_card.append(&thinking_title);
        status_card.append(&thinking_detail);

        let restart = gtk::Button::with_label("Restart Centurion");
        restart.add_css_class("suggested-action");
        restart.set_size_request(-1, 44);
        status_card.append(&restart);

        let support_links = gtk::Box::new(gtk::Orientation::Horizontal, 16);
        support_links.set_halign(gtk::Align::Center);
        support_links.set_margin_top(8);
        let get_help_link = gtk::Button::with_label("Get Help");
        get_help_link.add_css_class("flat");
        get_help_link.add_css_class("link");
        let talk_to_adrian_link = gtk::Button::with_label("Talk to Adrian");
        talk_to_adrian_link.add_css_class("flat");
        talk_to_adrian_link.add_css_class("link");
        support_links.append(&get_help_link);
        support_links.append(&talk_to_adrian_link);
        status_card.append(&support_links);

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
                .title("Private mesh")
                .subtitle(
                    "Prefer Tailscale MagicDNS for iPhone linking. Same Wi‑Fi is a local fallback only.",
                )
                .icon_name("network-wireless-symbolic")
                .build(),
        );
        settings_list.append(
            &adw::ActionRow::builder()
                .title("Version")
                .subtitle(&format!(
                    "Desktop app {} — Centurion AI OS updates separately below",
                    env!("CARGO_PKG_VERSION")
                ))
                .icon_name("dialog-information-symbolic")
                .build(),
        );
        let update_row = adw::ActionRow::builder()
            .title("Check for updates")
            .subtitle("Updates Centurion AI OS on this brain (not this desktop app binary)")
            .icon_name("software-update-available-symbolic")
            .build();
        let update_check_button = gtk::Button::with_label("Check");
        update_check_button.add_css_class("suggested-action");
        update_check_button.set_valign(gtk::Align::Center);
        update_row.add_suffix(&update_check_button);
        settings_list.append(&update_row);

        let thinking_settings_row = adw::ActionRow::builder()
            .title("Thinking Service")
            .subtitle("Checking thinking service…")
            .icon_name("preferences-system-symbolic")
            .build();
        let restore_thinking_button = gtk::Button::with_label("Restore last working setup");
        restore_thinking_button.add_css_class("suggested-action");
        restore_thinking_button.set_valign(gtk::Align::Center);
        let change_thinking_button = gtk::Button::with_label("Change Thinking Service");
        change_thinking_button.set_valign(gtk::Align::Center);
        thinking_settings_row.add_suffix(&restore_thinking_button);
        thinking_settings_row.add_suffix(&change_thinking_button);
        settings_list.append(&thinking_settings_row);

        let backup_thinking_row = adw::ActionRow::builder()
            .title("Backup Thinking Services")
            .subtitle("No backup thinking services configured.")
            .icon_name("view-list-symbolic")
            .build();
        settings_list.append(&backup_thinking_row);

        let setup_thinking_row = adw::ActionRow::builder()
            .title("Set up how your Centurion thinks")
            .subtitle("Run centurion setup on this computer for first-time configuration.")
            .icon_name("system-run-symbolic")
            .build();
        settings_list.append(&setup_thinking_row);

        settings.append(
            &gtk::Label::builder()
                .label("You & Oversight")
                .css_classes(["title-4"])
                .xalign(0.0)
                .margin_top(12)
                .build(),
        );
        let autonomy_row = adw::ActionRow::builder()
            .title("Autonomy Level")
            .subtitle("Balanced (default) — follow with light interpretation")
            .icon_name("preferences-desktop-symbolic")
            .build();
        let autonomy_button = gtk::Button::with_label("Adjust");
        autonomy_button.set_valign(gtk::Align::Center);
        autonomy_row.add_suffix(&autonomy_button);
        settings_list.append(&autonomy_row);

        let soul_row = adw::ActionRow::builder()
            .title("Your Sovereign's Soul")
            .subtitle("Personality and rules for your Centurion")
            .icon_name("emoji-people-symbolic")
            .build();
        let soul_button = gtk::Button::with_label("View / Edit");
        soul_button.set_valign(gtk::Align::Center);
        soul_row.add_suffix(&soul_button);
        settings_list.append(&soul_row);

        let memory_horizon_row = adw::ActionRow::builder()
            .title("Memory Horizon")
            .subtitle("How your Centurion remembers — Hot Cache, Session Recall, Vault")
            .icon_name("view-grid-symbolic")
            .build();
        let memory_horizon_button = gtk::Button::with_label("View");
        memory_horizon_button.set_valign(gtk::Align::Center);
        memory_horizon_row.add_suffix(&memory_horizon_button);
        settings_list.append(&memory_horizon_row);

        let oversight_row = adw::ActionRow::builder()
            .title("Reporting & Oversight")
            .subtitle("Report cadence and confirmation preferences")
            .icon_name("eye-open-negative-filled-symbolic")
            .build();
        let oversight_button = gtk::Button::with_label("Adjust");
        oversight_button.set_valign(gtk::Align::Center);
        oversight_row.add_suffix(&oversight_button);
        settings_list.append(&oversight_row);

        settings.append(
            &gtk::Label::builder()
                .label("Transition")
                .css_classes(["title-4"])
                .xalign(0.0)
                .margin_top(12)
                .build(),
        );
        let telegram_history_row = adw::ActionRow::builder()
            .title("Bring over Telegram history")
            .subtitle(
                "One-time for the early Centurions that started on the Telegram bot — keeps history on this brain.",
            )
            .icon_name("mail-send-receive-symbolic")
            .build();
        let telegram_bring_button = gtk::Button::with_label("Bring over");
        telegram_bring_button.set_valign(gtk::Align::Center);
        telegram_history_row.add_suffix(&telegram_bring_button);
        settings_list.append(&telegram_history_row);

        settings.append(
            &gtk::Label::builder()
                .label("Support Tools")
                .css_classes(["title-4"])
                .xalign(0.0)
                .margin_top(12)
                .build(),
        );
        let support_health_row = adw::ActionRow::builder()
            .title("Run Health Check")
            .subtitle("Check thinking service and configuration")
            .icon_name("emblem-system-symbolic")
            .build();
        let support_bundle_row = adw::ActionRow::builder()
            .title("Generate Support Bundle")
            .subtitle("Create a support code for your advisor")
            .icon_name("dialog-information-symbolic")
            .build();
        let support_lookup_row = adw::ActionRow::builder()
            .title("Look Up Support Code")
            .subtitle("Open a saved support bundle by code")
            .icon_name("system-search-symbolic")
            .build();
        let health_check_button = gtk::Button::with_label("Run");
        health_check_button.set_valign(gtk::Align::Center);
        let bundle_button = gtk::Button::with_label("Generate");
        bundle_button.set_valign(gtk::Align::Center);
        let lookup_button = gtk::Button::with_label("Look Up");
        lookup_button.set_valign(gtk::Align::Center);
        support_health_row.add_suffix(&health_check_button);
        support_bundle_row.add_suffix(&bundle_button);
        support_lookup_row.add_suffix(&lookup_button);
        settings_list.append(&support_health_row);
        settings_list.append(&support_bundle_row);
        settings_list.append(&support_lookup_row);

        let adrian_row = adw::ActionRow::builder()
            .title("Talk to Adrian")
            .subtitle("Mission-first guidance from Centurion's creator — over the internet")
            .icon_name("avatar-default-symbolic")
            .build();
        let adrian_button = gtk::Button::with_label("Open");
        adrian_button.set_valign(gtk::Align::Center);
        adrian_row.add_suffix(&adrian_button);
        settings_list.append(&adrian_row);

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
            .title("Sovereign AI Brain")
            .default_width(980)
            .default_height(700)
            .content(&toolbar)
            .build();

        let update_status = {
            let status_title = status_title.clone();
            let status_detail = status_detail.clone();
            let link_addresses = link_addresses.clone();
            let supervisor = supervisor.clone();
            move || match supervisor.borrow_mut().ensure_running() {
                Ok(()) => {
                    status_title.set_label("Your Centurion is ready");
                    status_detail.set_label(
                        "Copy the Tailscale address below into CenturionAI Remote, or use Find my Centurion on Wi‑Fi as a fallback.",
                    );
                    refresh_link_addresses(&link_addresses);
                }
                Err(error) => {
                    status_title.set_label("Your Centurion needs attention");
                    status_detail.set_label(&error);
                    refresh_link_addresses(&link_addresses);
                }
            }
        };

        update_status();
        refresh_thinking_status(&thinking_detail, &thinking_settings_row);
        refresh_backup_thinking_services(&backup_thinking_row);
        refresh_autonomy_row(&autonomy_row);
        refresh_soul_row(&soul_row);
        refresh_memory_horizon_row(&memory_horizon_row);
        refresh_oversight_row(&oversight_row);
        let thinking_poll_detail = thinking_detail.clone();
        let thinking_poll_row = thinking_settings_row.clone();
        let backup_poll_row = backup_thinking_row.clone();
        let autonomy_poll_row = autonomy_row.clone();
        let soul_poll_row = soul_row.clone();
        let memory_horizon_poll_row = memory_horizon_row.clone();
        let oversight_poll_row = oversight_row.clone();
        glib::timeout_add_seconds_local(30, move || {
            refresh_thinking_status(&thinking_poll_detail, &thinking_poll_row);
            refresh_backup_thinking_services(&backup_poll_row);
            refresh_autonomy_row(&autonomy_poll_row);
            refresh_soul_row(&soul_poll_row);
            refresh_memory_horizon_row(&memory_horizon_poll_row);
            refresh_oversight_row(&oversight_poll_row);
            glib::ControlFlow::Continue
        });
        restore_thinking_button.connect_clicked({
            let thinking_settings_row = thinking_settings_row.clone();
            move |_| {
                if let Some(response) = run_provider_command(&["restore", "--json"]) {
                    let message = response
                        .message
                        .or_else(|| {
                            response.result.and_then(|value| {
                                value
                                    .get("message")
                                    .and_then(|m| m.as_str())
                                    .map(str::to_owned)
                            })
                        })
                        .unwrap_or_else(|| "Restore finished.".to_owned());
                    thinking_settings_row.set_subtitle(&message);
                }
            }
        });
        change_thinking_button.connect_clicked({
            let thinking_settings_row = thinking_settings_row.clone();
            let thinking_detail = thinking_detail.clone();
            let window = window.clone();
            move |_| show_change_thinking_dialog(&window, &thinking_settings_row, &thinking_detail)
        });
        autonomy_button.connect_clicked({
            let window = window.clone();
            let autonomy_row = autonomy_row.clone();
            let oversight_row = oversight_row.clone();
            move |_| show_autonomy_dialog(&window, &autonomy_row, &oversight_row)
        });
        soul_button.connect_clicked({
            let window = window.clone();
            let soul_row = soul_row.clone();
            move |_| show_soul_dialog(&window, &soul_row)
        });
        memory_horizon_button.connect_clicked({
            let window = window.clone();
            let memory_horizon_row = memory_horizon_row.clone();
            move |_| show_memory_horizon_dialog(&window, &memory_horizon_row)
        });
        oversight_button.connect_clicked({
            let window = window.clone();
            let oversight_row = oversight_row.clone();
            let autonomy_row = autonomy_row.clone();
            move |_| show_oversight_dialog(&window, &oversight_row, &autonomy_row)
        });
        health_check_button.connect_clicked({
            let window = window.clone();
            move |_| show_support_health_dialog(&window)
        });
        update_check_button.connect_clicked({
            let window = window.clone();
            let update_row = update_row.clone();
            move |_| show_update_check_dialog(&window, &update_row)
        });
        bundle_button.connect_clicked({
            let window = window.clone();
            move |_| show_support_bundle_dialog(&window)
        });
        lookup_button.connect_clicked({
            let window = window.clone();
            move |_| show_support_lookup_dialog(&window)
        });
        telegram_bring_button.connect_clicked({
            let window = window.clone();
            let telegram_history_row = telegram_history_row.clone();
            move |_| show_telegram_history_dialog(&window, &telegram_history_row)
        });
        let open_adrian = {
            let window = window.clone();
            let stack = stack.clone();
            let thinking_settings_row = thinking_settings_row.clone();
            move || open_adrian_dialog(&window, &stack, &thinking_settings_row)
        };
        adrian_button.connect_clicked({
            let open_adrian = open_adrian.clone();
            move |_| open_adrian()
        });
        talk_to_adrian_link.connect_clicked({
            let open_adrian = open_adrian.clone();
            move |_| open_adrian()
        });
        get_help_link.connect_clicked({
            let window = window.clone();
            move |_| show_support_health_dialog(&window)
        });
        restart.connect_clicked({
            let link_addresses = link_addresses.clone();
            move |_| {
                let result = supervisor.borrow_mut().restart();
                match result {
                    Ok(()) => {
                        status_title.set_label("Your Centurion is ready");
                        status_detail.set_label(
                            "The private iPhone connection has restarted. Prefer the Tailscale address below.",
                        );
                        refresh_link_addresses(&link_addresses);
                    }
                    Err(error) => {
                        status_title.set_label("Restart did not complete");
                        status_detail.set_label(&error);
                        refresh_link_addresses(&link_addresses);
                    }
                }
            }
        });

        window.present();
    }

    fn build_chat_page() -> gtk::Box {
        use gio::prelude::*;
        use vte4::TerminalExt;
        use vte4::prelude::TerminalExtManual;

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
                .subtitle(format!(
                    "Waiting for your approval · {}",
                    device.fingerprint
                ))
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

    fn centurion_binary() -> String {
        std::env::var("HOME")
            .ok()
            .map(|home| format!("{home}/.local/bin/centurion"))
            .filter(|path| std::path::Path::new(path).is_file())
            .unwrap_or_else(|| "centurion".to_owned())
    }

    fn run_provider_command(args: &[&str]) -> Option<ProviderCliResponse> {
        let mut command_args = vec!["provider"];
        command_args.extend_from_slice(args);
        let output = Command::new(centurion_binary())
            .args(command_args)
            .output()
            .ok()
            .filter(|output| output.status.success())?;
        serde_json::from_slice(&output.stdout).ok()
    }

    fn run_support_command(args: &[&str]) -> Option<ProviderCliResponse> {
        let mut command_args = vec!["support"];
        command_args.extend_from_slice(args);
        let output = Command::new(centurion_binary())
            .args(command_args)
            .output()
            .ok()
            .filter(|output| output.status.success())?;
        serde_json::from_slice(&output.stdout).ok()
    }

    fn run_update_check() -> Option<UpdateCheckPayload> {
        let output = Command::new(centurion_binary())
            .args(["update", "--check", "--json"])
            .output()
            .ok()?;
        // Parse JSON even when exit status is non-zero (network / unavailable).
        serde_json::from_slice(&output.stdout).ok()
    }

    fn run_os_update() -> Result<String, String> {
        let output = Command::new(centurion_binary())
            .args(["update", "-y"])
            .output()
            .map_err(|error| error.to_string())?;
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        if output.status.success() {
            Ok(if stdout.is_empty() {
                "Centurion AI OS update finished. Restart this app if the desktop shell looks stale."
                    .to_owned()
            } else {
                stdout
            })
        } else {
            Err(if !stderr.is_empty() {
                stderr
            } else if !stdout.is_empty() {
                stdout
            } else {
                "Update failed.".to_owned()
            })
        }
    }

    fn show_update_check_dialog(parent: &adw::ApplicationWindow, update_row: &adw::ActionRow) {
        update_row.set_subtitle("Checking for Centurion AI OS updates…");
        let Some(payload) = run_update_check() else {
            update_row.set_subtitle("Could not check for updates.");
            let dialog = adw::MessageDialog::builder()
                .heading("Check for updates")
                .body(
                    "Could not run `centurion update --check --json`.\n\n\
                     Make sure `centurion` is installed on this brain.",
                )
                .close_response("ok")
                .build();
            dialog.add_response("ok", "OK");
            dialog.set_transient_for(Some(parent));
            dialog.present();
            return;
        };

        let os_version = payload
            .os_version
            .as_deref()
            .unwrap_or("unknown");
        let message = payload
            .message
            .clone()
            .unwrap_or_else(|| "Check complete.".to_owned());
        let footnote = "This updates Centurion AI OS on this brain — not the Sovereign AI Brain \
desktop app binary. To rebuild the desktop app, run desktop-native/scripts/install-user.sh \
(or your Fedora RPM path).";

        match payload.status.as_str() {
            "up_to_date" => {
                update_row.set_subtitle(&format!("Centurion AI OS {os_version} — up to date"));
                let dialog = adw::MessageDialog::builder()
                    .heading("You're up to date")
                    .body(&format!("{message}\n\nOS version: {os_version}\n\n{footnote}"))
                    .close_response("ok")
                    .build();
                dialog.add_response("ok", "OK");
                dialog.set_transient_for(Some(parent));
                dialog.present();
            }
            "update_available" => {
                update_row.set_subtitle(&format!(
                    "Update available for Centurion AI OS {os_version}"
                ));
                let body = format!(
                    "{message}\n\nOS version: {os_version}\n\n\
                     Updating may take several minutes and can restart services.\n\n{footnote}"
                );
                let dialog = adw::MessageDialog::builder()
                    .heading("Update available")
                    .body(&body)
                    .close_response("cancel")
                    .default_response("update")
                    .build();
                dialog.add_response("cancel", "Not now");
                dialog.add_response("update", "Update now");
                dialog.set_response_appearance("update", adw::ResponseAppearance::Suggested);
                dialog.set_transient_for(Some(parent));
                let parent = parent.clone();
                let update_row = update_row.clone();
                dialog.connect_response(None, move |dialog, response| {
                    if response != "update" {
                        dialog.close();
                        return;
                    }
                    dialog.close();
                    confirm_and_run_os_update(&parent, &update_row);
                });
                dialog.present();
            }
            _ => {
                let cmd = payload
                    .recommended_command
                    .as_deref()
                    .unwrap_or("centurion update");
                update_row.set_subtitle("Updates managed outside this app");
                let dialog = adw::MessageDialog::builder()
                    .heading("Cannot update from this app")
                    .body(&format!("{message}\n\nUse:\n{cmd}\n\n{footnote}"))
                    .close_response("ok")
                    .build();
                dialog.add_response("ok", "OK");
                dialog.set_transient_for(Some(parent));
                dialog.present();
            }
        }
    }

    fn confirm_and_run_os_update(parent: &adw::ApplicationWindow, update_row: &adw::ActionRow) {
        let confirm = adw::MessageDialog::builder()
            .heading("Update Centurion AI OS?")
            .body(
                "This updates Centurion AI OS on this brain and may take several minutes. \
                 Services such as the gateway may restart.\n\n\
                 The Sovereign AI Brain desktop app binary is not rebuilt by this action.",
            )
            .close_response("cancel")
            .default_response("confirm")
            .build();
        confirm.add_response("cancel", "Cancel");
        confirm.add_response("confirm", "Update now");
        confirm.set_response_appearance("confirm", adw::ResponseAppearance::Suggested);
        confirm.set_transient_for(Some(parent));
        let parent = parent.clone();
        let update_row = update_row.clone();
        confirm.connect_response(None, move |dialog, response| {
            if response != "confirm" {
                dialog.close();
                return;
            }
            dialog.close();
            update_row.set_subtitle("Updating Centurion AI OS…");
            let progress = adw::MessageDialog::builder()
                .heading("Updating…")
                .body("Please wait. This can take several minutes.")
                .close_response("ok")
                .build();
            progress.add_response("ok", "Hide");
            progress.set_transient_for(Some(&parent));
            progress.present();

            let parent_for_result = parent.clone();
            let update_row_for_result = update_row.clone();
            let progress_for_result = progress.clone();
            std::thread::spawn(move || {
                let result = run_os_update();
                glib::idle_add_once(move || {
                    progress_for_result.close();
                    match result {
                        Ok(body) => {
                            update_row_for_result
                                .set_subtitle("Centurion AI OS update finished");
                            let done = adw::MessageDialog::builder()
                                .heading("Update complete")
                                .body(&format!(
                                    "{body}\n\n\
                                     Restart Sovereign AI Brain if the desktop shell looks stale. \
                                     Rebuild the desktop app with install-user.sh only when you \
                                     need a new GTK build."
                                ))
                                .close_response("ok")
                                .build();
                            done.add_response("ok", "OK");
                            done.set_transient_for(Some(&parent_for_result));
                            done.present();
                        }
                        Err(error) => {
                            update_row_for_result.set_subtitle("Update failed");
                            let fail = adw::MessageDialog::builder()
                                .heading("Update failed")
                                .body(&error)
                                .close_response("ok")
                                .build();
                            fail.add_response("ok", "OK");
                            fail.set_transient_for(Some(&parent_for_result));
                            fail.present();
                        }
                    }
                });
            });
        });
        confirm.present();
    }

    fn run_telegram_summary(args: &[&str]) -> Option<serde_json::Value> {
        let mut command_args = vec!["telegram", "import"];
        command_args.extend_from_slice(args);
        command_args.push("--json");
        let output = Command::new(centurion_binary())
            .args(command_args)
            .output()
            .ok()?;
        // Parse JSON even when exit status is non-zero (no Telegram history found).
        serde_json::from_slice(&output.stdout).ok()
    }

    fn bridge_python() -> String {
        std::env::var("CENTURION_PYTHON")
            .ok()
            .filter(|p| !p.is_empty())
            .unwrap_or_else(|| "python3".to_owned())
    }

    fn run_bridge_action(action: &str, extra: serde_json::Value) -> Option<serde_json::Value> {
        let mut body = serde_json::Map::new();
        body.insert("id".to_owned(), serde_json::json!("desktop-settings"));
        body.insert("action".to_owned(), serde_json::Value::String(action.to_owned()));
        if let serde_json::Value::Object(map) = extra {
            for (key, value) in map {
                body.insert(key, value);
            }
        }
        let payload = serde_json::Value::Object(body).to_string();
        let mut child = Command::new(bridge_python())
            .args(["-m", "centurion_cli.remote_bridge"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .ok()?;
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(payload.as_bytes()).ok()?;
        }
        let output = child.wait_with_output().ok()?;
        if !output.status.success() && output.stdout.is_empty() {
            return None;
        }
        serde_json::from_slice(&output.stdout).ok()
    }

    fn autonomy_label(level: &str) -> &'static str {
        match level {
            "strict" => "Strict — follow instructions exactly, minimal initiative",
            "balanced" => "Balanced — follow with light interpretation",
            "proactive" => "Proactive — suggest improvements and take small actions",
            "high" => "High Autonomy — maximum freedom within boundaries",
            _ => "Balanced — follow with light interpretation",
        }
    }

    fn refresh_autonomy_row(row: &adw::ActionRow) {
        let Some(payload) = run_bridge_action("oversight_get", serde_json::json!({})) else {
            row.set_subtitle("Could not read autonomy level.");
            return;
        };
        let level = payload
            .pointer("/oversight/autonomy_level")
            .and_then(|v| v.as_str())
            .unwrap_or("balanced");
        row.set_subtitle(autonomy_label(level));
    }

    fn refresh_soul_row(row: &adw::ActionRow) {
        let Some(payload) = run_bridge_action("soul_get", serde_json::json!({})) else {
            row.set_subtitle("Could not read your Sovereign's Soul.");
            return;
        };
        let summary = payload
            .pointer("/soul/personalitySummary")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim();
        if summary.is_empty() {
            let exists = payload
                .pointer("/soul/exists")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            row.set_subtitle(if exists {
                "Soul document on this Centurion"
            } else {
                "Not set yet — shape personality and rules"
            });
        } else {
            let clipped: String = summary.chars().take(72).collect();
            row.set_subtitle(&clipped);
        }
    }

    fn format_bytes_short(bytes: u64) -> String {
        const KB: f64 = 1024.0;
        const MB: f64 = KB * 1024.0;
        const GB: f64 = MB * 1024.0;
        let n = bytes as f64;
        if n >= GB {
            format!("{:.1} GB", n / GB)
        } else if n >= MB {
            format!("{:.0} MB", n / MB)
        } else if n >= KB {
            format!("{:.0} KB", n / KB)
        } else {
            format!("{bytes} B")
        }
    }

    fn refresh_memory_horizon_row(row: &adw::ActionRow) {
        let Some(payload) = run_bridge_action("memory_horizon_snapshot", serde_json::json!({})) else {
            row.set_subtitle("Could not read Memory Horizon.");
            return;
        };
        let hot = payload
            .pointer("/snapshot/hot_cache/fill_ratio")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        let sessions = payload
            .pointer("/snapshot/session_recall/sessions")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        let vault_enabled = payload
            .pointer("/snapshot/vault/enabled")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let vault_init = payload
            .pointer("/snapshot/vault/initialized")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let vault_label = if !vault_enabled || !vault_init {
            "Vault off"
        } else if payload
            .pointer("/snapshot/vault/unlocked")
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            "Vault ready"
        } else {
            "Vault locked"
        };
        row.set_subtitle(&format!(
            "Hot Cache {:.0}% · {sessions} conversations · {vault_label}",
            hot * 100.0
        ));
    }

    fn show_memory_horizon_dialog(parent: &adw::ApplicationWindow, row: &adw::ActionRow) {
        let snapshot = run_bridge_action("memory_horizon_snapshot", serde_json::json!({}))
            .and_then(|p| p.get("snapshot").cloned())
            .unwrap_or_else(|| serde_json::json!({}));

        let hot = snapshot.get("hot_cache").cloned().unwrap_or(serde_json::json!({}));
        let recall = snapshot
            .get("session_recall")
            .cloned()
            .unwrap_or(serde_json::json!({}));
        let vault = snapshot.get("vault").cloned().unwrap_or(serde_json::json!({}));

        let hot_used = hot.get("used_chars").and_then(|v| v.as_u64()).unwrap_or(0);
        let hot_limit = hot.get("limit_chars").and_then(|v| v.as_u64()).unwrap_or(3575);
        let hot_fill = hot.get("fill_ratio").and_then(|v| v.as_f64()).unwrap_or(0.0);
        let mem_chars = hot.get("memory_chars").and_then(|v| v.as_u64()).unwrap_or(0);
        let mem_limit = hot.get("memory_limit").and_then(|v| v.as_u64()).unwrap_or(2200);
        let user_chars = hot.get("user_chars").and_then(|v| v.as_u64()).unwrap_or(0);
        let user_limit = hot.get("user_limit").and_then(|v| v.as_u64()).unwrap_or(1375);

        let sessions = recall.get("sessions").and_then(|v| v.as_u64()).unwrap_or(0);
        let messages = recall.get("messages").and_then(|v| v.as_u64()).unwrap_or(0);
        let recall_db = recall.get("db_bytes").and_then(|v| v.as_u64()).unwrap_or(0);
        let recall_free = recall.get("free_bytes").and_then(|v| v.as_u64()).unwrap_or(0);
        let recall_fill = recall.get("fill_ratio").and_then(|v| v.as_f64()).unwrap_or(0.0);

        let vault_enabled = vault.get("enabled").and_then(|v| v.as_bool()).unwrap_or(false);
        let vault_init = vault
            .get("initialized")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let vault_unlocked = vault.get("unlocked").and_then(|v| v.as_bool()).unwrap_or(false);
        let vault_entries = vault
            .get("total_entries")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        let vault_db = vault.get("db_bytes").and_then(|v| v.as_u64()).unwrap_or(0);
        let vault_fill = vault.get("fill_ratio").and_then(|v| v.as_f64()).unwrap_or(0.0);
        let core = vault
            .pointer("/counts/core")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        let experiential = vault
            .pointer("/counts/experiential")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        let pattern = vault
            .pointer("/counts/pattern")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);

        let vault_status = if !vault_enabled || !vault_init {
            "Off — not set up yet".to_owned()
        } else if vault_unlocked {
            format!(
                "Unlocked · {vault_entries} notes · {} used · Core {core} · Experience {experiential} · Pattern {pattern} · disk fill {:.0}%",
                format_bytes_short(vault_db),
                vault_fill * 100.0
            )
        } else {
            format!(
                "Locked · {vault_entries} notes · {} on disk — unlock on this computer",
                format_bytes_short(vault_db)
            )
        };

        let body = format!(
            "Three layers on this Sovereign. Hot Cache is a software budget (not hardware RAM). \
Session Recall and Vault grow with use and share disk space here.\n\n\
Near · Hot Cache\n\
{hot_used}/{hot_limit} chars ({:.0}% full)\n\
MEMORY {mem_chars}/{mem_limit} · YOU {user_chars}/{user_limit}\n\
To make room: ask your Centurion to curate essentials — not a product upgrade.\n\n\
Mid · Session Recall\n\
{sessions} conversations · {messages} messages\n\
{} used · {} free on this computer ({:.0}% of used+free)\n\
Grows as you chat. If disk is high, ask about pruning older sessions.\n\n\
Far · Vault\n\
{vault_status}\n\
Grow with durable notes (propose → commit). Passphrase stays on this computer.",
            hot_fill * 100.0,
            format_bytes_short(recall_db),
            format_bytes_short(recall_free),
            recall_fill * 100.0,
        );

        let dialog = adw::MessageDialog::builder()
            .heading("Memory Horizon")
            .body(&body)
            .close_response("close")
            .build();
        dialog.add_response("close", "Close");
        dialog.set_default_response(Some("close"));
        dialog.set_transient_for(Some(parent));
        let row = row.clone();
        dialog.connect_response(None, move |dialog, _| {
            refresh_memory_horizon_row(&row);
            dialog.close();
        });
        dialog.present();
    }

    fn refresh_oversight_row(row: &adw::ActionRow) {
        let Some(payload) = run_bridge_action("oversight_get", serde_json::json!({})) else {
            row.set_subtitle("Could not read reporting preferences.");
            return;
        };
        let cadence = payload
            .pointer("/oversight/report_cadence")
            .and_then(|v| v.as_str())
            .unwrap_or("when_needed");
        let ask = payload
            .pointer("/oversight/ask_before_initiative")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        let cadence_label = match cadence {
            "off" => "Off",
            "daily" => "Daily",
            "after_significant_actions" => "After significant actions",
            _ => "When needed",
        };
        row.set_subtitle(&format!(
            "{cadence_label} · ask before initiative: {}",
            if ask { "on" } else { "off" }
        ));
    }

    fn show_autonomy_dialog(
        parent: &adw::ApplicationWindow,
        autonomy_row: &adw::ActionRow,
        oversight_row: &adw::ActionRow,
    ) {
        let current = run_bridge_action("oversight_get", serde_json::json!({}))
            .and_then(|p| {
                p.pointer("/oversight/autonomy_level")
                    .and_then(|v| v.as_str())
                    .map(str::to_owned)
            })
            .unwrap_or_else(|| "balanced".to_owned());

        let dialog = adw::MessageDialog::builder()
            .heading("Autonomy Level")
            .body(
                "How much freedom your Centurion has. Changes apply on the next conversation.\n\n\
                 Strict — follow exactly\n\
                 Balanced — light interpretation (default)\n\
                 Proactive — suggest and take small actions\n\
                 High Autonomy — maximum freedom within boundaries",
            )
            .close_response("cancel")
            .build();
        dialog.add_response("cancel", "Cancel");
        for (id, label) in [
            ("strict", "Strict"),
            ("balanced", "Balanced"),
            ("proactive", "Proactive"),
            ("high", "High Autonomy"),
        ] {
            dialog.add_response(id, label);
            if id == current {
                dialog.set_response_appearance(id, adw::ResponseAppearance::Suggested);
                dialog.set_default_response(Some(id));
            }
        }
        dialog.set_transient_for(Some(parent));
        let autonomy_row = autonomy_row.clone();
        let oversight_row = oversight_row.clone();
        dialog.connect_response(None, move |dialog, response| {
            if matches!(response, "strict" | "balanced" | "proactive" | "high") {
                let _ = run_bridge_action(
                    "oversight_put",
                    serde_json::json!({
                        "oversight": { "autonomy_level": response },
                        "apply_level_preset": true,
                    }),
                );
                refresh_autonomy_row(&autonomy_row);
                refresh_oversight_row(&oversight_row);
            }
            dialog.close();
        });
        dialog.present();
    }

    fn show_soul_dialog(parent: &adw::ApplicationWindow, soul_row: &adw::ActionRow) {
        let markdown = run_bridge_action("soul_get", serde_json::json!({}))
            .and_then(|p| {
                p.pointer("/soul/markdown")
                    .and_then(|v| v.as_str())
                    .map(str::to_owned)
            })
            .unwrap_or_default();

        let buffer = gtk::TextBuffer::new(None::<&gtk::TextTagTable>);
        buffer.set_text(&markdown);
        let view = gtk::TextView::builder()
            .buffer(&buffer)
            .wrap_mode(gtk::WrapMode::WordChar)
            .monospace(true)
            .editable(true)
            .build();
        let scrolled = gtk::ScrolledWindow::builder()
            .child(&view)
            .min_content_height(280)
            .min_content_width(480)
            .hexpand(true)
            .vexpand(true)
            .build();

        let content = gtk::Box::new(gtk::Orientation::Vertical, 8);
        content.set_margin_top(12);
        content.set_margin_bottom(12);
        content.set_margin_start(12);
        content.set_margin_end(12);
        content.append(
            &gtk::Label::builder()
                .label(
                    "This changes how your Centurion speaks and behaves. \
                     Changes may take time to fully take effect — they apply on the next conversation.",
                )
                .wrap(true)
                .xalign(0.0)
                .build(),
        );
        content.append(&scrolled);

        let dialog = adw::MessageDialog::builder()
            .heading("Your Sovereign's Soul")
            .close_response("cancel")
            .extra_child(&content)
            .build();
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("save", "Save Changes");
        dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
        dialog.set_default_response(Some("save"));
        dialog.set_transient_for(Some(parent));
        let soul_row = soul_row.clone();
        dialog.connect_response(None, move |dialog, response| {
            if response == "save" {
                let (start, end) = buffer.bounds();
                let text = buffer.text(&start, &end, false);
                let _ = run_bridge_action(
                    "soul_put",
                    serde_json::json!({ "markdown": text.as_str() }),
                );
                refresh_soul_row(&soul_row);
            }
            dialog.close();
        });
        dialog.present();
    }

    fn show_oversight_dialog(
        parent: &adw::ApplicationWindow,
        oversight_row: &adw::ActionRow,
        autonomy_row: &adw::ActionRow,
    ) {
        let snapshot = run_bridge_action("oversight_get", serde_json::json!({}))
            .and_then(|p| p.get("oversight").cloned())
            .unwrap_or_else(|| serde_json::json!({}));
        let cadence = snapshot
            .get("report_cadence")
            .and_then(|v| v.as_str())
            .unwrap_or("when_needed")
            .to_owned();
        let ask = snapshot
            .get("ask_before_initiative")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        let dangerous = snapshot
            .get("confirm_dangerous_commands")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        let external = snapshot
            .get("confirm_external_actions")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);

        let cadence_model = gtk::StringList::new(&[
            "off",
            "when_needed",
            "daily",
            "after_significant_actions",
        ]);
        let cadence_drop = gtk::DropDown::from_strings(&[
            "Off",
            "When needed",
            "Daily",
            "After significant actions",
        ]);
        let selected = match cadence.as_str() {
            "off" => 0_u32,
            "daily" => 2,
            "after_significant_actions" => 3,
            _ => 1,
        };
        cadence_drop.set_selected(selected);
        let _ = cadence_model;

        let ask_switch = gtk::Switch::builder().active(ask).valign(gtk::Align::Center).build();
        let dangerous_switch = gtk::Switch::builder()
            .active(dangerous)
            .valign(gtk::Align::Center)
            .build();
        let external_switch = gtk::Switch::builder()
            .active(external)
            .valign(gtk::Align::Center)
            .build();

        let list = gtk::ListBox::new();
        list.add_css_class("boxed-list");

        let cadence_row = adw::ActionRow::builder()
            .title("Report cadence")
            .subtitle("How often your Centurion reports back")
            .build();
        cadence_row.add_suffix(&cadence_drop);
        list.append(&cadence_row);

        let ask_row = adw::ActionRow::builder()
            .title("Ask before taking initiative")
            .build();
        ask_row.add_suffix(&ask_switch);
        ask_row.set_activatable_widget(Some(&ask_switch));
        list.append(&ask_row);

        let dangerous_row = adw::ActionRow::builder()
            .title("Confirm dangerous commands")
            .build();
        dangerous_row.add_suffix(&dangerous_switch);
        dangerous_row.set_activatable_widget(Some(&dangerous_switch));
        list.append(&dangerous_row);

        let external_row = adw::ActionRow::builder()
            .title("Confirm external actions")
            .build();
        external_row.add_suffix(&external_switch);
        external_row.set_activatable_widget(Some(&external_switch));
        list.append(&external_row);

        let content = gtk::Box::new(gtk::Orientation::Vertical, 8);
        content.set_margin_top(12);
        content.set_margin_bottom(12);
        content.set_margin_start(12);
        content.set_margin_end(12);
        content.append(
            &gtk::Label::builder()
                .label("Changes apply on the next conversation.")
                .xalign(0.0)
                .build(),
        );
        content.append(&list);

        let dialog = adw::MessageDialog::builder()
            .heading("Reporting & Oversight")
            .close_response("cancel")
            .extra_child(&content)
            .build();
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("save", "Save");
        dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
        dialog.set_default_response(Some("save"));
        dialog.set_transient_for(Some(parent));

        let oversight_row = oversight_row.clone();
        let autonomy_row = autonomy_row.clone();
        dialog.connect_response(None, move |dialog, response| {
            if response == "save" {
                let cadence_value = match cadence_drop.selected() {
                    0 => "off",
                    2 => "daily",
                    3 => "after_significant_actions",
                    _ => "when_needed",
                };
                let _ = run_bridge_action(
                    "oversight_put",
                    serde_json::json!({
                        "oversight": {
                            "report_cadence": cadence_value,
                            "ask_before_initiative": ask_switch.is_active(),
                            "confirm_dangerous_commands": dangerous_switch.is_active(),
                            "confirm_external_actions": external_switch.is_active(),
                        },
                        "apply_level_preset": false,
                    }),
                );
                refresh_oversight_row(&oversight_row);
                refresh_autonomy_row(&autonomy_row);
            }
            dialog.close();
        });
        dialog.present();
    }

    fn show_telegram_history_dialog(parent: &adw::ApplicationWindow, row: &adw::ActionRow) {
        let preview = run_telegram_summary(&["--dry-run"]);
        let (heading, body, can_bring) = match preview.as_ref() {
            Some(value) if value.get("ok").and_then(|v| v.as_bool()) == Some(true) => {
                let messages = value
                    .get("message_count")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0);
                let files = value
                    .get("file_count")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0);
                let missing = value
                    .get("missing_file_count")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0);
                (
                    "Bring over Telegram history".to_owned(),
                    format!(
                        "Found a Telegram bot conversation on this Centurion:\n\n\
                         {messages} messages · {files} files\
                         {}\n\n\
                         This is a one-time transition for early Centurions. \
                         History is saved on this brain — not sent through CenturionAI Remote.",
                        if missing > 0 {
                            format!(" ({missing} attachments missing)")
                        } else {
                            String::new()
                        }
                    ),
                    true,
                )
            }
            Some(value) => (
                "No Telegram history found".to_owned(),
                value
                    .get("message")
                    .and_then(|v| v.as_str())
                    .unwrap_or("No Telegram bot DM session was found on this Centurion.")
                    .to_owned(),
                false,
            ),
            None => (
                "Could not check Telegram history".to_owned(),
                "Run `centurion telegram import --dry-run` on this computer if you need more detail."
                    .to_owned(),
                false,
            ),
        };

        let dialog = adw::MessageDialog::builder()
            .heading(&heading)
            .body(&body)
            .close_response("cancel")
            .build();
        dialog.add_response("cancel", if can_bring { "Cancel" } else { "OK" });
        if can_bring {
            dialog.add_response("bring", "Bring over");
            dialog.set_response_appearance("bring", adw::ResponseAppearance::Suggested);
            dialog.set_default_response(Some("bring"));
        } else {
            dialog.set_default_response(Some("cancel"));
        }
        dialog.set_transient_for(Some(parent));
        let row = row.clone();
        dialog.connect_response(None, move |dialog, response| {
            if response == "bring" {
                if let Some(result) = run_telegram_summary(&[]) {
                    let ok = result.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
                    let messages = result
                        .get("message_count")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);
                    let path = result
                        .get("manifest_path")
                        .and_then(|v| v.as_str())
                        .filter(|s| !s.is_empty())
                        .or_else(|| result.get("bundle_path").and_then(|v| v.as_str()))
                        .unwrap_or("");
                    if ok {
                        row.set_subtitle(&format!(
                            "Brought over {messages} messages — saved on this Centurion."
                        ));
                        let done = adw::MessageDialog::builder()
                            .heading("Telegram history saved")
                            .body(if path.is_empty() {
                                format!("Brought over {messages} messages onto this Centurion.")
                            } else {
                                format!(
                                    "Brought over {messages} messages onto this Centurion.\n\nSaved at:\n{path}"
                                )
                            })
                            .close_response("ok")
                            .build();
                        done.add_response("ok", "OK");
                        done.set_transient_for(dialog.transient_for().as_ref());
                        done.present();
                    } else {
                        let message = result
                            .get("message")
                            .and_then(|v| v.as_str())
                            .unwrap_or("Bring-over failed.");
                        row.set_subtitle(message);
                    }
                } else {
                    row.set_subtitle("Could not bring over Telegram history.");
                }
            }
            dialog.close();
        });
        dialog.present();
    }

    fn refresh_thinking_status(detail: &gtk::Label, settings_row: &adw::ActionRow) {
        let Some(response) = run_provider_command(&["status", "--json"]) else {
            detail.set_label("Thinking service status is unavailable.");
            settings_row.set_subtitle("Could not read thinking service status.");
            return;
        };
        let Some(status) = response.status else {
            detail.set_label("Thinking service status is unavailable.");
            settings_row.set_subtitle("Could not read thinking service status.");
            return;
        };
        let plain = match status.health.as_str() {
            "ok" => "Working normally".to_owned(),
            "degraded" => "May be slow".to_owned(),
            _ => "Needs attention".to_owned(),
        };
        let mut line = format!("{plain} — {}", status.health_message);
        if status.last_good_available && status.health != "ok" {
            line.push_str(" Last working setup is available.");
        }
        detail.set_label(&line);
        settings_row.set_subtitle(&line);
    }

    fn refresh_backup_thinking_services(row: &adw::ActionRow) {
        let Some(response) = run_support_command(&["backups", "--json"]) else {
            row.set_subtitle("Could not read backup thinking services.");
            return;
        };
        let Some(result) = response.result else {
            row.set_subtitle("No backup thinking services configured.");
            return;
        };
        let backups = result
            .get("backups")
            .and_then(|value| value.as_array())
            .cloned()
            .unwrap_or_default();
        if backups.is_empty() {
            row.set_subtitle("No backup thinking services configured.");
            return;
        }
        let labels: Vec<String> = backups
            .iter()
            .filter_map(|entry| {
                entry
                    .get("label")
                    .and_then(|label| label.as_str())
                    .map(str::to_owned)
            })
            .collect();
        if labels.is_empty() {
            let subtitle = format!("{} backup thinking service(s) configured.", backups.len());
            row.set_subtitle(&subtitle);
        } else {
            let subtitle = labels.join(" · ");
            row.set_subtitle(&subtitle);
        }
    }

    fn show_change_thinking_dialog(
        parent: &adw::ApplicationWindow,
        settings_row: &adw::ActionRow,
        detail: &gtk::Label,
    ) {
        let dialog = adw::MessageDialog::builder()
            .heading("Change thinking service")
            .body("Enter a provider slug and model id. Centurion validates before applying.")
            .close_response("cancel")
            .default_response("apply")
            .build();
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("apply", "Validate and apply");
        dialog.set_response_appearance("apply", adw::ResponseAppearance::Suggested);

        let provider_entry = gtk::Entry::builder().placeholder_text("openrouter").build();
        let model_entry = gtk::Entry::builder()
            .placeholder_text("anthropic/claude-sonnet-4")
            .build();

        let extra = gtk::Box::new(gtk::Orientation::Vertical, 8);
        extra.append(&gtk::Label::builder().label("Provider").xalign(0.0).build());
        extra.append(&provider_entry);
        extra.append(&gtk::Label::builder().label("Model").xalign(0.0).build());
        extra.append(&model_entry);
        dialog.set_extra_child(Some(&extra));
        dialog.set_transient_for(Some(parent));
        dialog.present();

        let settings_row = settings_row.clone();
        let detail = detail.clone();
        dialog.connect_response(None, move |dialog, response| {
            if response != "apply" {
                dialog.close();
                return;
            }
            let provider = provider_entry.text().to_string();
            let model = model_entry.text().to_string();
            if provider.trim().is_empty() || model.trim().is_empty() {
                settings_row.set_subtitle("Provider and model are required.");
                dialog.close();
                return;
            }
            if let Some(response) = run_provider_command(&["set", &provider, &model, "--json"]) {
                let message = response
                    .result
                    .and_then(|value| {
                        value
                            .get("message")
                            .and_then(|m| m.as_str())
                            .map(str::to_owned)
                    })
                    .unwrap_or_else(|| "Thinking service updated.".to_owned());
                settings_row.set_subtitle(&message);
                refresh_thinking_status(&detail, &settings_row);
            } else {
                settings_row.set_subtitle("Could not apply thinking service change.");
            }
            dialog.close();
        });
    }

    fn show_support_health_dialog(parent: &adw::ApplicationWindow) {
        let body = if let Some(response) = run_support_command(&["health", "--json"]) {
            response
                .message
                .or_else(|| {
                    response.result.and_then(|value| {
                        value
                            .get("summary")
                            .and_then(|m| m.as_str())
                            .map(str::to_owned)
                    })
                })
                .unwrap_or_else(|| "Health check completed.".to_owned())
        } else {
            "Could not run health check.".to_owned()
        };
        let dialog = adw::MessageDialog::builder()
            .heading("Health Check")
            .body(&body)
            .close_response("ok")
            .build();
        dialog.add_response("ok", "OK");
        dialog.set_transient_for(Some(parent));
        dialog.present();
    }

    fn show_support_bundle_dialog(parent: &adw::ApplicationWindow) {
        let (heading, body) = if let Some(response) = run_support_command(&["bundle", "--json"]) {
            if let Some(code) = response.code {
                (
                    "Support Code".to_owned(),
                    format!(
                        "{}\n\nShare this code with your advisor:\n\n{code}",
                        response
                            .message
                            .unwrap_or_else(|| "Support bundle created.".to_owned())
                    ),
                )
            } else {
                (
                    "Support Bundle".to_owned(),
                    "Could not create a support code.".to_owned(),
                )
            }
        } else {
            (
                "Support Bundle".to_owned(),
                "Could not create a support code.".to_owned(),
            )
        };
        let dialog = adw::MessageDialog::builder()
            .heading(&heading)
            .body(&body)
            .close_response("ok")
            .build();
        dialog.add_response("ok", "OK");
        dialog.set_transient_for(Some(parent));
        dialog.present();
    }

    fn show_support_lookup_dialog(parent: &adw::ApplicationWindow) {
        let dialog = adw::MessageDialog::builder()
            .heading("Look Up Support Code")
            .body("Enter the support code from an iPhone or a previous bundle.")
            .close_response("cancel")
            .default_response("lookup")
            .build();
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("lookup", "Look Up");
        let code_entry = gtk::Entry::builder().placeholder_text("ABC-123").build();
        dialog.set_extra_child(Some(&code_entry));
        dialog.set_transient_for(Some(parent));
        dialog.present();

        dialog.connect_response(None, move |dialog, response| {
            if response != "lookup" {
                dialog.close();
                return;
            }
            let code = code_entry.text().to_string();
            let result_dialog =
                if let Some(cli_response) = run_support_command(&["show", &code, "--json"]) {
                    let body = cli_response
                        .message
                        .filter(|text| !text.trim().is_empty())
                        .or_else(|| {
                            cli_response.result.and_then(|bundle| {
                                bundle
                                    .get("summary_plain")
                                    .and_then(|s| s.as_str())
                                    .map(str::to_owned)
                            })
                        })
                        .unwrap_or_else(|| "Support bundle found.".to_owned());
                    adw::MessageDialog::builder()
                        .heading(format!("Support Code {code}"))
                        .body(&body)
                        .close_response("ok")
                        .build()
                } else {
                    adw::MessageDialog::builder()
                        .heading("Support Code Not Found")
                        .body("That code is missing or has expired.")
                        .close_response("ok")
                        .build()
                };
            result_dialog.add_response("ok", "OK");
            result_dialog.set_transient_for(dialog.transient_for().as_ref());
            result_dialog.present();
            dialog.close();
        });
    }

    fn build_adrian_context() -> AdrianChatContext {
        let connection_state = if remote_listener_active() {
            "connected"
        } else {
            "disconnected"
        };
        let (thinking_health, thinking_message) =
            if let Some(response) = run_provider_command(&["status", "--json"]) {
                if let Some(status) = response.status {
                    let health = match status.health.as_str() {
                        "ok" => "working_normally",
                        "degraded" => "needs_attention",
                        _ => "needs_attention",
                    };
                    (health.to_owned(), status.health_message)
                } else {
                    ("unknown".to_owned(), String::new())
                }
            } else {
                ("unknown".to_owned(), String::new())
            };
        AdrianChatContext {
            app_version: env!("CARGO_PKG_VERSION").to_owned(),
            connection_state: connection_state.to_owned(),
            thinking_health,
            thinking_message,
            has_mission: false,
            active_target_count: 0,
            mission_summary: String::new(),
            support_code: String::new(),
        }
    }

    fn open_adrian_dialog(
        window: &adw::ApplicationWindow,
        stack: &gtk::Stack,
        thinking_settings_row: &adw::ActionRow,
    ) {
        let stack = stack.clone();
        let window = window.clone();
        let dialog_window = window.clone();
        let thinking_settings_row = thinking_settings_row.clone();
        let hooks = AdrianDialogHooks {
            build_context: Rc::new(build_adrian_context),
            on_action: Rc::new(move |action_id: &str| match action_id {
                "open_connect" => stack.set_visible_child_name("home"),
                "open_get_help" => show_support_health_dialog(&window),
                "try_auto_fix" => {
                    if let Some(response) = run_provider_command(&["restore", "--json"]) {
                        let message = response
                            .message
                            .or_else(|| {
                                response.result.and_then(|value| {
                                    value
                                        .get("message")
                                        .and_then(|m| m.as_str())
                                        .map(str::to_owned)
                                })
                            })
                            .unwrap_or_else(|| "Restore finished.".to_owned());
                        thinking_settings_row.set_subtitle(&message);
                    }
                }
                "open_mission" => stack.set_visible_child_name("chat"),
                _ => {}
            }),
        };
        show_adrian_dialog(&dialog_window, hooks);
    }
}

#[cfg(target_os = "linux")]
fn main() {
    linux::run();
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("Sovereign AI Brain is a native Linux application.");
}
