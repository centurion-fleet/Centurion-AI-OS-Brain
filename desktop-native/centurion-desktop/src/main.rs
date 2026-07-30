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
    clippy::needless_pass_by_value,
    clippy::too_many_lines
)]
mod bridge_client;
#[cfg(target_os = "linux")]
#[allow(
    dead_code,
    unused_imports,
    clippy::assigning_clones,
    clippy::map_unwrap_or,
    clippy::needless_pass_by_value,
    clippy::too_many_lines
)]
mod chat_page;
#[cfg(target_os = "linux")]
#[allow(
    dead_code,
    unused_imports,
    clippy::assigning_clones,
    clippy::map_unwrap_or,
    clippy::needless_pass_by_value,
    clippy::too_many_lines
)]
mod home_page;
#[cfg(target_os = "linux")]
#[allow(
    dead_code,
    unused_imports,
    clippy::assigning_clones,
    clippy::map_unwrap_or,
    clippy::needless_pass_by_value,
    clippy::too_many_lines
)]
mod mission_deck_page;
#[cfg(target_os = "linux")]
#[allow(
    dead_code,
    unused_imports,
    clippy::assigning_clones,
    clippy::map_unwrap_or,
    clippy::needless_pass_by_value,
    clippy::too_many_lines
)]
mod interviews;

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
    use std::cell::{Cell, RefCell};
    use std::collections::HashMap;
    use std::io::Write;
    use std::path::PathBuf;
    use std::process::{Child, Command, Stdio};
    use std::rc::Rc;
    use std::sync::Mutex;

    const APP_ID: &str = "com.centurion.desktop";

    /// Cached result of the last update check — drives Settings (!) without
    /// re-running `centurion update --check` on the 5s attention poll.
    #[derive(Debug, Default, Clone)]
    struct UpdateAttentionState {
        available: bool,
        detail: String,
    }

    fn update_attention_state() -> &'static Mutex<UpdateAttentionState> {
        static STATE: Mutex<UpdateAttentionState> = Mutex::new(UpdateAttentionState {
            available: false,
            detail: String::new(),
        });
        &STATE
    }

    fn remember_update_check(payload: &UpdateCheckPayload) {
        let mut state = update_attention_state()
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        match payload.status.as_str() {
            "update_available" => {
                let ver = payload
                    .screen_checkout_version
                    .as_deref()
                    .filter(|s| !s.trim().is_empty())
                    .or_else(|| payload.os_version.as_deref())
                    .unwrap_or("newer");
                state.available = true;
                state.detail = format!(
                    "Sovereign AI Brain update available ({ver}) — open Check for update below"
                );
            }
            "up_to_date" => {
                state.available = false;
                state.detail.clear();
            }
            _ => {}
        }
    }

    fn clear_update_attention() {
        let mut state = update_attention_state()
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        state.available = false;
        state.detail.clear();
    }

    fn load_update_attention() -> Option<(bool, String)> {
        let state = update_attention_state()
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if state.available {
            Some((true, state.detail.clone()))
        } else {
            None
        }
    }

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
        #[serde(default)]
        catalog: Option<serde_json::Value>,
        result: Option<serde_json::Value>,
        message: Option<String>,
        #[serde(default)]
        summary: Option<String>,
        code: Option<String>,
        #[serde(default)]
        configured: Option<bool>,
        #[serde(default)]
        connector_id: Option<String>,
    }

    #[derive(Clone, Debug)]
    struct ThinkingConnectorOption {
        id: String,
        display_name: String,
        needs_key: bool,
        best_for: String,
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
        branch_behind: u64,
        #[serde(default)]
        os_version: Option<String>,
        #[serde(default)]
        message: Option<String>,
        #[serde(default)]
        recommended_command: Option<String>,
        /// "full" (OS + screen) or "rebuild_screen" (local checkout newer than binary).
        #[serde(default)]
        update_action: Option<String>,
        #[serde(default)]
        screen_rebuild_available: bool,
        #[serde(default)]
        screen_checkout_version: Option<String>,
        #[serde(default)]
        screen_installed_version: Option<String>,
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
                    crate::chat_page::resolve_centurion_home(),
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
        crate::bridge_client::warm_bridge_daemon_async();
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
        // Amber Horizon — force dark so Chat / Settings match Mission Deck.
        adw::StyleManager::default().set_color_scheme(adw::ColorScheme::ForceDark);

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

    /// True when at least one iPhone is approved or waiting for approval.
    fn any_iphones_linked() -> bool {
        let output = Command::new(centurion_remote_bin())
            .args(["devices", "--json"])
            .output();
        let listing = output
            .ok()
            .filter(|output| output.status.success())
            .and_then(|output| serde_json::from_slice::<DeviceListing>(&output.stdout).ok());
        match listing {
            Some(listing) => !listing.approved.is_empty() || !listing.pending.is_empty(),
            None => false,
        }
    }

    #[derive(Debug, Default, Clone)]
    struct LinkAddresses {
        lan_ips: Vec<String>,
    }

    fn is_tailscale_cgnat(ip: &str) -> bool {
        let parts: Vec<u8> = ip
            .split('.')
            .filter_map(|part| part.parse().ok())
            .collect();
        parts.len() == 4 && parts[0] == 100 && (64..=127).contains(&parts[1])
    }

    /// LAN-only discovery. Prefer wired ethernet when both Wi‑Fi and eth are up.
    /// Away access uses a Centurion-hosted relay later — not Tailscale / advertise-host in Unbox QR.
    fn discover_link_addresses() -> LinkAddresses {
        let mut addresses = LinkAddresses::default();
        let mut ethernet_ips = Vec::new();
        let mut other_ips = Vec::new();

        // Prefer `ip -o -4 addr show` so we can rank eth* / enp* / eno* ahead of wlan*.
        if let Ok(output) = Command::new("ip")
            .args(["-o", "-4", "addr", "show"])
            .output()
        {
            if output.status.success() {
                for line in String::from_utf8_lossy(&output.stdout).lines() {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    // Format: INDEX: IFACE    inet ADDR/MASK …
                    if parts.len() < 4 {
                        continue;
                    }
                    let iface = parts[1];
                    let addr_cidr = parts[3];
                    let ip = addr_cidr.split('/').next().unwrap_or("");
                    if ip.is_empty()
                        || ip.starts_with("127.")
                        || is_tailscale_cgnat(ip)
                        || ip.contains(':')
                    {
                        continue;
                    }
                    let wired = iface.starts_with("eth")
                        || iface.starts_with("enp")
                        || iface.starts_with("eno")
                        || iface.starts_with("enx");
                    if wired {
                        if !ethernet_ips.iter().any(|existing: &String| existing == ip) {
                            ethernet_ips.push(ip.to_owned());
                        }
                    } else if !other_ips.iter().any(|existing: &String| existing == ip) {
                        other_ips.push(ip.to_owned());
                    }
                }
            }
        }

        if ethernet_ips.is_empty() && other_ips.is_empty() {
            if let Ok(output) = Command::new("hostname").args(["-I"]).output() {
                if output.status.success() {
                    for token in String::from_utf8_lossy(&output.stdout).split_whitespace() {
                        if token.contains(':')
                            || token.starts_with("127.")
                            || is_tailscale_cgnat(token)
                        {
                            continue;
                        }
                        if !other_ips.iter().any(|existing| existing == token) {
                            other_ips.push(token.to_owned());
                        }
                    }
                }
            }
        }

        addresses.lan_ips.extend(ethernet_ips);
        addresses.lan_ips.extend(other_ips);
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

    fn centurion_remote_bin() -> String {
        std::env::var("HOME")
            .ok()
            .map(|home| format!("{home}/.local/bin/centurion-remote"))
            .filter(|path| PathBuf::from(path).is_file())
            .unwrap_or_else(|| "centurion-remote".to_owned())
    }

    #[derive(Debug, Clone)]
    struct MintedPairing {
        id: String,
        connection_string: String,
        qr_png: Vec<u8>,
    }

    /// Host for Unbox & Go QR — always a LAN IPv4, never tunnel advertise-host.
    fn resolve_lan_pairing_host() -> String {
        let addresses = discover_link_addresses();
        addresses
            .lan_ips
            .first()
            .cloned()
            .unwrap_or_else(|| "127.0.0.1".to_owned())
    }

    fn mint_remote_pairing() -> Result<MintedPairing, String> {
        // Unbox QR always embeds the LAN address so the phone pairs on Wi‑Fi
        // without depending on a tunnel hostname.
        let host = resolve_lan_pairing_host();

        let output = Command::new(centurion_remote_bin())
            .args(["remote-pair", "--host", &host, "--json", "--include-qr"])
            .output()
            .map_err(|error| format!("Could not run centurion-remote: {error}"))?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!(
                "centurion-remote remote-pair failed: {}",
                stderr.trim()
            ));
        }
        let value: serde_json::Value = serde_json::from_slice(&output.stdout)
            .map_err(|error| format!("Invalid remote-pair JSON: {error}"))?;
        let connection = value
            .get("connection_string")
            .and_then(|v| v.as_str())
            .map(str::to_owned)
            .ok_or_else(|| "remote-pair response missing connection_string".to_owned())?;
        let id = value
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_owned();
        let qr_b64 = value
            .get("qr_png_base64")
            .and_then(|v| v.as_str())
            .ok_or_else(|| "remote-pair response missing qr_png_base64".to_owned())?;
        let qr_png = glib::base64_decode(qr_b64);
        if qr_png.is_empty() {
            return Err("Could not decode QR PNG from remote-pair".to_owned());
        }
        Ok(MintedPairing {
            id,
            connection_string: connection,
            qr_png,
        })
    }

    fn revoke_remote_pairing_token(id: &str) {
        if id.is_empty() {
            return;
        }
        let _ = Command::new(centurion_remote_bin())
            .args(["remote-revoke", id])
            .output();
    }

    fn qr_image_from_png(png: &[u8], pixel_size: i32) -> gtk::Image {
        // glib 0.22: `Bytes::from` only accepts borrowed slices; owned data
        // must use `from_owned` (requires Send — Vec<u8> is fine).
        let bytes = glib::Bytes::from_owned(png.to_vec());
        match gtk::gdk::Texture::from_bytes(&bytes) {
            Ok(texture) => {
                let image = gtk::Image::from_paintable(Some(&texture));
                image.set_pixel_size(pixel_size);
                image
            }
            Err(_) => gtk::Image::from_icon_name("image-missing"),
        }
    }

    /// Apply a mint result to the QR window widgets (main-thread only).
    fn apply_pairing_mint_result(
        minted: Result<MintedPairing, String>,
        qr_holder: &gtk::Box,
        status: &gtk::Label,
        text_reveal: &gtk::Label,
        token_id: &RefCell<String>,
        connection: &RefCell<String>,
    ) {
        match minted {
            Ok(minted) => {
                let previous = token_id.borrow().clone();
                if !previous.is_empty() && previous != minted.id {
                    revoke_remote_pairing_token(&previous);
                }
                *token_id.borrow_mut() = minted.id;
                *connection.borrow_mut() = minted.connection_string.clone();
                while let Some(child) = qr_holder.first_child() {
                    qr_holder.remove(&child);
                }
                qr_holder.append(&qr_image_from_png(&minted.qr_png, 360));
                status.set_label("Point your iPhone camera at this QR code");
                if text_reveal.is_visible() {
                    text_reveal.set_label(&minted.connection_string);
                }
            }
            Err(error) => {
                let plain = if error.contains("not found") {
                    "Could not create a pairing code. Is Centurion installed on this brain?"
                        .to_owned()
                } else {
                    "Could not create a pairing code. Try again in a moment.".to_owned()
                };
                status.set_label(&plain);
            }
        }
    }

    /// Full-screen QR pairing page: scan-first UX with auto-rotated tokens.
    /// Minting stays on the GTK main thread (no idle_add / Send wrappers).
    fn brain_welcome_marker_path() -> std::path::PathBuf {
        std::path::PathBuf::from(crate::chat_page::resolve_centurion_home())
            .join("brain_welcome_seen")
    }

    fn brain_welcome_seen() -> bool {
        brain_welcome_marker_path().is_file()
    }

    fn mark_brain_welcome_seen() {
        let path = brain_welcome_marker_path();
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::write(path, b"1\n");
    }

    /// First-run narrative: what a Centurion *is* (partner), not pairing theatre.
    fn show_brain_welcome_dialog(parent: &adw::ApplicationWindow) {
        let body = "This computer is your Sovereign — a private partner that thinks with you, \
keeps your data here, and stays on your mission.\n\n\
Chat is the conversation. Focus is the command center: mission stack, plans, and decisions. \
Settings is how you shape Soul, memory, and thinking.\n\n\
An iPhone remote is optional later — only when you want the Brain in your pocket. \
For now, sit here and meet your Centurion.";
        let dialog = adw::AlertDialog::builder()
            .heading("Welcome to your Centurion")
            .body(body)
            .close_response("begin")
            .default_response("begin")
            .build();
        dialog.add_response("begin", "Begin");
        dialog.add_response("pair", "Pair iPhone later");
        dialog.set_response_appearance("begin", adw::ResponseAppearance::Suggested);
        let parent_for_pair = parent.clone();
        dialog.connect_response(None, move |_d, response| {
            mark_brain_welcome_seen();
            if response == "pair" {
                show_pairing_qr_window(&parent_for_pair);
            }
        });
        dialog.present(Some(parent));
    }

    fn show_pairing_qr_window(parent: &adw::ApplicationWindow) {
        let window = adw::Window::builder()
            .title("Link iPhone")
            .transient_for(parent)
            .modal(true)
            .default_width(720)
            .default_height(960)
            .build();

        let content = gtk::Box::new(gtk::Orientation::Vertical, 16);
        content.set_margin_top(40);
        content.set_margin_bottom(40);
        content.set_margin_start(40);
        content.set_margin_end(40);
        content.set_halign(gtk::Align::Center);
        content.set_valign(gtk::Align::Center);

        content.append(
            &gtk::Label::builder()
                .label("Link your iPhone")
                .css_classes(["title-1"])
                .build(),
        );
        content.append(
            &gtk::Label::builder()
                .label("Open Sovereign AI Remote on this Wi‑Fi → Scan this code")
                .css_classes(["title-3"])
                .wrap(true)
                .justify(gtk::Justification::Center)
                .build(),
        );

        let qr_holder = gtk::Box::new(gtk::Orientation::Vertical, 0);
        qr_holder.set_halign(gtk::Align::Center);
        content.append(&qr_holder);

        let status = gtk::Label::builder()
            .label("Preparing pairing code…")
            .css_classes(["dim-label"])
            .wrap(true)
            .justify(gtk::Justification::Center)
            .build();
        content.append(&status);

        let text_reveal = gtk::Label::builder()
            .label("")
            .selectable(true)
            .wrap(true)
            .justify(gtk::Justification::Center)
            .visible(false)
            .build();
        content.append(&text_reveal);

        let actions = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        actions.set_halign(gtk::Align::Center);
        let copy = gtk::Button::with_label("Copy code");
        copy.add_css_class("flat");
        let show_text = gtk::Button::with_label("Show text");
        show_text.add_css_class("flat");
        let refresh = gtk::Button::with_label("Refresh code");
        refresh.add_css_class("suggested-action");
        let done = gtk::Button::with_label("Done");
        actions.append(&copy);
        actions.append(&show_text);
        actions.append(&refresh);
        actions.append(&done);
        content.append(&actions);

        content.append(
            &gtk::Label::builder()
                .label(
                    "The code refreshes every few minutes. Paste remains available if the camera cannot be used.",
                )
                .css_classes(["dim-label"])
                .wrap(true)
                .justify(gtk::Justification::Center)
                .build(),
        );

        let header = adw::HeaderBar::new();
        let toolbar = adw::ToolbarView::new();
        toolbar.add_top_bar(&header);
        toolbar.set_content(Some(&content));
        window.set_content(Some(&toolbar));

        let token_id = Rc::new(RefCell::new(String::new()));
        let connection = Rc::new(RefCell::new(String::new()));

        let remint = Rc::new({
            let qr_holder = qr_holder.clone();
            let status = status.clone();
            let text_reveal = text_reveal.clone();
            let token_id = token_id.clone();
            let connection = connection.clone();
            move || {
                apply_pairing_mint_result(
                    mint_remote_pairing(),
                    &qr_holder,
                    &status,
                    &text_reveal,
                    &token_id,
                    &connection,
                );
            }
        });

        remint();

        copy.connect_clicked({
            let connection = connection.clone();
            move |_| {
                let text = connection.borrow().clone();
                if text.starts_with("token:") {
                    copy_to_clipboard(&text);
                }
            }
        });
        show_text.connect_clicked({
            let text_reveal = text_reveal.clone();
            let connection = connection.clone();
            move |button| {
                if text_reveal.is_visible() {
                    text_reveal.set_visible(false);
                    button.set_label("Show text");
                } else {
                    text_reveal.set_label(&connection.borrow());
                    text_reveal.set_visible(true);
                    button.set_label("Hide text");
                }
            }
        });
        refresh.connect_clicked({
            let remint = remint.clone();
            move |_| remint()
        });
        done.connect_clicked({
            let window = window.clone();
            move |_| window.close()
        });

        // Rotate every 3 minutes. `_local` keeps the closure on the GTK thread
        // (widgets are !Send — do not use idle_add / timeout_add without _local).
        glib::timeout_add_seconds_local(180, {
            let window = window.clone();
            let remint = remint.clone();
            move || {
                if !window.is_visible() {
                    return glib::ControlFlow::Break;
                }
                remint();
                glib::ControlFlow::Continue
            }
        });

        // Unbox: dismiss full-screen QR once an iPhone is linked.
        glib::timeout_add_seconds_local(2, {
            let window = window.clone();
            let status = status.clone();
            move || {
                if !window.is_visible() {
                    return glib::ControlFlow::Break;
                }
                if any_iphones_linked() {
                    status.set_label("iPhone linked — you can close this screen.");
                    window.close();
                    return glib::ControlFlow::Break;
                }
                glib::ControlFlow::Continue
            }
        });

        window.connect_close_request({
            let token_id = token_id.clone();
            move |_| {
                let _ = token_id;
                glib::Propagation::Proceed
            }
        });

        window.fullscreen();
        window.present();
    }

    fn refresh_link_addresses(container: &gtk::Box, parent: Option<&adw::ApplicationWindow>) {
        while let Some(child) = container.first_child() {
            container.remove(&child);
        }

        container.append(
            &gtk::Label::builder()
                .label("Optional iPhone remote")
                .css_classes(["title-4"])
                .xalign(0.0)
                .build(),
        );

        container.append(
            &gtk::Label::builder()
                .label(
                    "The Brain on this desk is the product. Pairing an iPhone is optional convenience \
on the same Wi‑Fi — scan only when you want a thin remote.",
                )
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );

        let link = gtk::Button::with_label("Show pairing QR");
        link.add_css_class("suggested-action");
        link.set_margin_top(4);
        if let Some(parent) = parent {
            let parent = parent.clone();
            link.connect_clicked(move |_| show_pairing_qr_window(&parent));
        } else {
            link.set_sensitive(false);
        }
        container.append(&link);

        let addresses = discover_link_addresses();
        if let Some(lan) = addresses.lan_ips.first() {
            container.append(
                &gtk::Label::builder()
                    .label("On your network")
                    .css_classes(["title-4"])
                    .xalign(0.0)
                    .margin_top(12)
                    .build(),
            );
            container.append(&build_link_address_row(
                "LAN address",
                &format!("{lan}:9119"),
                false,
            ));
        }

        container.append(
            &gtk::Label::builder()
                .label(
                    "Away-from-home access comes later via a Centurion-hosted relay — no router setup for Unbox.",
                )
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .margin_top(8)
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
        refresh_link_addresses(&link_addresses, None);
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

        let devices_section = gtk::Box::new(gtk::Orientation::Vertical, 12);
        let devices_heading = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        devices_heading.append(
            &gtk::Label::builder()
                .label("Connected Devices")
                .css_classes(["title-2"])
                .xalign(0.0)
                .build(),
        );
        let devices_attention_mark = gtk::Label::builder()
            .label("(!)")
            .css_classes(["centurion-attention-mark"])
            .visible(false)
            .hexpand(true)
            .xalign(0.0)
            .build();
        devices_heading.append(&devices_attention_mark);
        let refresh_devices_button = gtk::Button::from_icon_name("view-refresh-symbolic");
        refresh_devices_button.set_tooltip_text(Some("Refresh devices"));
        devices_heading.append(&refresh_devices_button);
        devices_section.append(&devices_heading);
        devices_section.append(
            &gtk::Label::builder()
                .label(
                    "Link flow: show the pairing QR under Status above → scan in Sovereign AI Remote → approve the iPhone here. Review or revoke anytime.",
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
        devices_section.append(&device_list);

        let settings = gtk::Box::new(gtk::Orientation::Vertical, 16);
        settings.set_margin_top(32);
        settings.set_margin_start(32);
        settings.set_margin_end(32);
        settings.set_margin_bottom(32);
        settings.append(
            &gtk::Label::builder()
                .label("Settings")
                .css_classes(["title-1"])
                .xalign(0.0)
                .build(),
        );

        let settings_attention_banner = gtk::Box::new(gtk::Orientation::Vertical, 4);
        settings_attention_banner.add_css_class("centurion-attention-banner");
        settings_attention_banner.set_visible(false);
        settings.append(&settings_attention_banner);

        settings.append(
            &gtk::Label::builder()
                .label("Status")
                .css_classes(["title-2"])
                .xalign(0.0)
                .margin_top(8)
                .build(),
        );
        settings.append(&status_card);
        settings.append(&devices_section);

        // Each section is its own PreferencesGroup. Earlier we appended section
        // labels to the page *before* a single list, so Autonomy/Soul/Telegram
        // visually sat under "Support Tools" and the middle headers looked empty.
        let brain_group = adw::PreferencesGroup::builder()
            .title("Brain")
            .description("Sovereign AI Brain version, updates, and how your Centurion thinks")
            .build();
        let pairing_settings_row = adw::ActionRow::builder()
            .title("Remote pairing")
            .subtitle(
                "Show the pairing QR for Sovereign AI Remote (same Wi‑Fi). Approve the phone under Connected Devices above.",
            )
            .icon_name("network-wireless-symbolic")
            .activatable(true)
            .build();
        brain_group.add(&pairing_settings_row);
        brain_group.add(
            &adw::ActionRow::builder()
                .title("Version")
                .subtitle(&format!(
                    "Sovereign AI Brain {}",
                    env!("CARGO_PKG_VERSION")
                ))
                .icon_name("dialog-information-symbolic")
                .build(),
        );
        let update_row = adw::ActionRow::builder()
            .title("Check for update")
            .subtitle("Check whether a newer Sovereign AI Brain is available")
            .icon_name("software-update-available-symbolic")
            .build();
        let update_attention_mark = gtk::Label::builder()
            .label("(!)")
            .css_classes(["centurion-attention-mark"])
            .visible(false)
            .valign(gtk::Align::Center)
            .build();
        update_row.add_suffix(&update_attention_mark);
        let update_check_button = gtk::Button::with_label("Check");
        update_check_button.add_css_class("suggested-action");
        update_check_button.set_valign(gtk::Align::Center);
        let rebuild_screen_button = gtk::Button::with_label("Rebuild Brain");
        rebuild_screen_button.set_tooltip_text(Some(
            "Rebuild Sovereign AI Brain from the Centurion folder on this computer (does not need an iPhone).",
        ));
        rebuild_screen_button.set_valign(gtk::Align::Center);
        update_row.add_suffix(&rebuild_screen_button);
        update_row.add_suffix(&update_check_button);
        brain_group.add(&update_row);

        let thinking_settings_row = adw::ActionRow::builder()
            .title("How your Centurion thinks")
            .subtitle("Checking thinking service…")
            .icon_name("preferences-system-symbolic")
            .build();
        let thinking_attention_mark = gtk::Label::builder()
            .label("(!)")
            .css_classes(["centurion-attention-mark"])
            .visible(false)
            .valign(gtk::Align::Center)
            .build();
        thinking_settings_row.add_suffix(&thinking_attention_mark);
        let restore_thinking_button = gtk::Button::with_label("Restore");
        restore_thinking_button.set_tooltip_text(Some("Restore last working thinking setup"));
        restore_thinking_button.set_valign(gtk::Align::Center);
        let change_thinking_button = gtk::Button::with_label("Change");
        change_thinking_button.set_tooltip_text(Some(
            "Choose your thinking service and access code for this brain.",
        ));
        change_thinking_button.add_css_class("suggested-action");
        change_thinking_button.set_valign(gtk::Align::Center);
        thinking_settings_row.add_suffix(&restore_thinking_button);
        thinking_settings_row.add_suffix(&change_thinking_button);
        brain_group.add(&thinking_settings_row);

        let backup_thinking_row = adw::ActionRow::builder()
            .title("Backup Thinking Services")
            .subtitle("No backup thinking services configured.")
            .icon_name("view-list-symbolic")
            .build();
        brain_group.add(&backup_thinking_row);
        let fleet_peer_row = adw::ActionRow::builder()
            .title("Fleet peer")
            .subtitle("Add peers and ping across machines (moved from Focus).")
            .icon_name("network-server-symbolic")
            .build();
        let fleet_peer_button = gtk::Button::with_label("Configure");
        fleet_peer_button.set_valign(gtk::Align::Center);
        fleet_peer_row.add_suffix(&fleet_peer_button);
        brain_group.add(&fleet_peer_row);
        let plugins_row = adw::ActionRow::builder()
            .title("Installed plugins")
            .subtitle("Agent plugins on this Brain — manage here, not on Focus.")
            .icon_name("application-x-addon-symbolic")
            .build();
        let plugins_button = gtk::Button::with_label("View");
        plugins_button.set_valign(gtk::Align::Center);
        plugins_row.add_suffix(&plugins_button);
        brain_group.add(&plugins_row);
        let ops_row = adw::ActionRow::builder()
            .title("Scheduled & board")
            .subtitle("Cron jobs and kanban glance — desk ops, not Focus pulse.")
            .icon_name("view-list-symbolic")
            .build();
        let ops_button = gtk::Button::with_label("View");
        ops_button.set_valign(gtk::Align::Center);
        ops_row.add_suffix(&ops_button);
        brain_group.add(&ops_row);
        let collab_connect_row = adw::ActionRow::builder()
            .title("Collaborations")
            .subtitle("Local boards on this Brain — no portal tokens. Focus stays offline.")
            .icon_name("system-users-symbolic")
            .build();
        let collab_connect_button = gtk::Button::with_label("New board");
        collab_connect_button.add_css_class("suggested-action");
        collab_connect_button.set_valign(gtk::Align::Center);
        collab_connect_row.add_suffix(&collab_connect_button);
        brain_group.add(&collab_connect_row);
        settings.append(&brain_group);

        let gateway_group = adw::PreferencesGroup::builder()
            .title("Messaging Gateway")
            .description("Telegram and other platforms for this Brain")
            .build();
        let gateway_row = adw::ActionRow::builder()
            .title("Gateway")
            .subtitle("Checking…")
            .icon_name("network-workgroup-symbolic")
            .build();
        let gateway_start_btn = gtk::Button::with_label("Start");
        gateway_start_btn.set_valign(gtk::Align::Center);
        let gateway_stop_btn = gtk::Button::with_label("Stop");
        gateway_stop_btn.set_valign(gtk::Align::Center);
        let gateway_restart_btn = gtk::Button::with_label("Restart");
        gateway_restart_btn.set_valign(gtk::Align::Center);
        gateway_row.add_suffix(&gateway_start_btn);
        gateway_row.add_suffix(&gateway_stop_btn);
        gateway_row.add_suffix(&gateway_restart_btn);
        gateway_group.add(&gateway_row);
        settings.append(&gateway_group);
        let gateway_platform_list = gtk::ListBox::new();
        gateway_platform_list.add_css_class("boxed-list");
        gateway_platform_list.set_margin_start(32);
        gateway_platform_list.set_margin_end(32);
        gateway_platform_list.set_margin_bottom(8);
        settings.append(&gateway_platform_list);

        let you_group = adw::PreferencesGroup::builder()
            .title("You & Oversight")
            .description("Autonomy, personality, memory, and reporting")
            .build();
        let autonomy_row = adw::ActionRow::builder()
            .title("Autonomy Level")
            .subtitle("Balanced (default) — follow with light interpretation")
            .icon_name("preferences-desktop-symbolic")
            .build();
        let autonomy_button = gtk::Button::with_label("Adjust");
        autonomy_button.set_valign(gtk::Align::Center);
        autonomy_row.add_suffix(&autonomy_button);
        you_group.add(&autonomy_row);

        let life_mission_row = adw::ActionRow::builder()
            .title("Life Mission")
            .subtitle("What you're building toward — shown on Focus; edit here.")
            .icon_name("emblem-favorite-symbolic")
            .build();
        let life_mission_edit_button = gtk::Button::with_label("Edit");
        life_mission_edit_button.set_valign(gtk::Align::Center);
        life_mission_row.add_suffix(&life_mission_edit_button);
        you_group.add(&life_mission_row);

        let mission_stack_row = adw::ActionRow::builder()
            .title("Mission Stack")
            .subtitle("Primary, supporting, dreams — open the Focus tab")
            .icon_name("view-list-symbolic")
            .build();
        let mission_stack_button = gtk::Button::with_label("Open tab");
        mission_stack_button.set_valign(gtk::Align::Center);
        mission_stack_button.add_css_class("suggested-action");
        mission_stack_row.add_suffix(&mission_stack_button);
        you_group.add(&mission_stack_row);

        let mission_discover_row = adw::ActionRow::builder()
            .title("Mission Discovery")
            .subtitle("Ceremonial interview to set your Life Mission")
            .icon_name("compass-symbolic")
            .build();
        let mission_discover_button = gtk::Button::with_label("Begin");
        mission_discover_button.add_css_class("suggested-action");
        mission_discover_button.set_valign(gtk::Align::Center);
        mission_discover_row.add_suffix(&mission_discover_button);
        you_group.add(&mission_discover_row);

        let about_you_row = adw::ActionRow::builder()
            .title("About You")
            .subtitle("Story, values, and challenges for your Sovereign")
            .icon_name("user-info-symbolic")
            .build();
        let about_you_button = gtk::Button::with_label("Interview");
        about_you_button.set_valign(gtk::Align::Center);
        about_you_row.add_suffix(&about_you_button);
        you_group.add(&about_you_row);

        let soul_row = adw::ActionRow::builder()
            .title("Your Sovereign's Soul")
            .subtitle("Personality and rules for your Centurion")
            .icon_name("emoji-people-symbolic")
            .build();
        let soul_shape_button = gtk::Button::with_label("Shape");
        soul_shape_button.add_css_class("suggested-action");
        soul_shape_button.set_valign(gtk::Align::Center);
        let soul_button = gtk::Button::with_label("View / Edit");
        soul_button.set_valign(gtk::Align::Center);
        soul_row.add_suffix(&soul_shape_button);
        soul_row.add_suffix(&soul_button);
        you_group.add(&soul_row);

        let memory_horizon_row = adw::ActionRow::builder()
            .title("Memory Horizon")
            .subtitle("How your Centurion remembers — Hot Cache, Session Recall, Vault")
            .icon_name("view-grid-symbolic")
            .build();
        let memory_horizon_button = gtk::Button::with_label("View");
        memory_horizon_button.set_valign(gtk::Align::Center);
        memory_horizon_row.add_suffix(&memory_horizon_button);
        you_group.add(&memory_horizon_row);

        let oversight_row = adw::ActionRow::builder()
            .title("Reporting & Oversight")
            .subtitle("Report cadence and confirmation preferences")
            .icon_name("eye-open-negative-filled-symbolic")
            .build();
        let oversight_button = gtk::Button::with_label("Adjust");
        oversight_button.set_valign(gtk::Align::Center);
        oversight_row.add_suffix(&oversight_button);
        you_group.add(&oversight_row);

        let privacy_row = adw::ActionRow::builder()
            .title("Privacy & Trust")
            .subtitle("What stays on this computer, and how partnership works")
            .icon_name("security-high-symbolic")
            .activatable(true)
            .build();
        you_group.add(&privacy_row);

        let pulse_pref_row = adw::ActionRow::builder()
            .title("Focus attention")
            .subtitle("Prefer opening Focus on decisions when something needs you")
            .icon_name("emblem-important-symbolic")
            .build();
        let pulse_pref_switch = gtk::Switch::builder().valign(gtk::Align::Center).build();
        pulse_pref_switch.set_active(load_decision_first_pref());
        pulse_pref_row.add_suffix(&pulse_pref_switch);
        you_group.add(&pulse_pref_row);

        let skills_row = adw::ActionRow::builder()
            .title("Skills & tools")
            .subtitle("What this Brain can use (read-only)")
            .icon_name("applications-engineering-symbolic")
            .build();
        let skills_button = gtk::Button::with_label("View");
        skills_button.set_valign(gtk::Align::Center);
        skills_row.add_suffix(&skills_button);
        you_group.add(&skills_row);

        let license_row = adw::ActionRow::builder()
            .title("License")
            .subtitle("Product entitlement for this Brain")
            .icon_name("dialog-password-symbolic")
            .build();
        let license_button = gtk::Button::with_label("Status");
        license_button.set_valign(gtk::Align::Center);
        license_row.add_suffix(&license_button);
        let license_enabled = run_bridge_action("license_status", serde_json::json!({}))
            .and_then(|p| {
                p.pointer("/status/enabled")
                    .or_else(|| p.get("enabled"))
                    .and_then(|v| v.as_bool())
            })
            .unwrap_or(false);
        license_row.set_visible(license_enabled);
        you_group.add(&license_row);

        let beneficiary_row = adw::ActionRow::builder()
            .title("Family Beneficiary")
            .subtitle("Nominate family and track colleague referrals")
            .icon_name("avatar-default-symbolic")
            .build();
        let beneficiary_button = gtk::Button::with_label("Open");
        beneficiary_button.set_valign(gtk::Align::Center);
        beneficiary_row.add_suffix(&beneficiary_button);
        let beneficiary_active = run_bridge_action("beneficiary_snapshot", serde_json::json!({}))
            .map(|p| {
                let s = p.get("snapshot").unwrap_or(&p);
                let enabled = s
                    .get("enabled")
                    .or_else(|| s.get("program_active"))
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                let has_family = s
                    .get("family_beneficiary_first_name")
                    .or_else(|| s.pointer("/family/first_name"))
                    .and_then(|v| v.as_str())
                    .map(|v| !v.trim().is_empty())
                    .unwrap_or(false);
                enabled || has_family
            })
            .unwrap_or(false);
        beneficiary_row.set_visible(beneficiary_active);
        you_group.add(&beneficiary_row);

        settings.append(&you_group);

        let transition_group = adw::PreferencesGroup::builder()
            .title("Transition")
            .description("One-time moves from earlier Centurion setups")
            .build();
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
        transition_group.add(&telegram_history_row);
        settings.append(&transition_group);

        let support_group = adw::PreferencesGroup::builder()
            .title("Support Tools")
            .description("Health checks and help for your advisor")
            .build();
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
        let fix_thinking_row = adw::ActionRow::builder()
            .title("Fix Thinking Service")
            .subtitle("Catalog → access code → apply → probe")
            .icon_name("emblem-ok-symbolic")
            .build();
        let auto_fix_row = adw::ActionRow::builder()
            .title("Try auto-fix")
            .subtitle("Safe recovery for common thinking/config issues")
            .icon_name("tools-check-symbolic")
            .build();
        let health_check_button = gtk::Button::with_label("Run");
        health_check_button.set_valign(gtk::Align::Center);
        let bundle_button = gtk::Button::with_label("Generate");
        bundle_button.set_valign(gtk::Align::Center);
        let lookup_button = gtk::Button::with_label("Look Up");
        lookup_button.set_valign(gtk::Align::Center);
        let fix_thinking_button = gtk::Button::with_label("Fix");
        fix_thinking_button.add_css_class("suggested-action");
        fix_thinking_button.set_valign(gtk::Align::Center);
        let auto_fix_button = gtk::Button::with_label("Run");
        auto_fix_button.set_valign(gtk::Align::Center);
        support_health_row.add_suffix(&health_check_button);
        support_bundle_row.add_suffix(&bundle_button);
        support_lookup_row.add_suffix(&lookup_button);
        fix_thinking_row.add_suffix(&fix_thinking_button);
        auto_fix_row.add_suffix(&auto_fix_button);
        support_group.add(&support_health_row);
        support_group.add(&fix_thinking_row);
        support_group.add(&auto_fix_row);
        support_group.add(&support_bundle_row);
        support_group.add(&support_lookup_row);

        let adrian_row = adw::ActionRow::builder()
            .title("Talk to Adrian")
            .subtitle("Mission-first guidance from Centurion's creator — over the internet")
            .icon_name("avatar-default-symbolic")
            .build();
        let adrian_button = gtk::Button::with_label("Open");
        adrian_button.set_valign(gtk::Align::Center);
        adrian_row.add_suffix(&adrian_button);
        support_group.add(&adrian_row);
        settings.append(&support_group);

        // ScrolledWindow only scrolls if the child keeps its natural height.
        // vexpand/fill on the child clips content instead of scrolling (Brain
        // touch screens then look like Settings just "ends" mid-row).
        settings.set_vexpand(false);
        settings.set_hexpand(true);
        settings.set_valign(gtk::Align::Start);

        let settings_scroll = gtk::ScrolledWindow::builder()
            .child(&settings)
            .vexpand(true)
            .hexpand(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .vscrollbar_policy(gtk::PolicyType::Automatic)
            .kinetic_scrolling(true)
            .overlay_scrolling(false) // always show a scrollbar so scroll is discoverable on touch
            .min_content_height(240)
            .build();

        let (chat, chat_handle) = build_chat_page();

        let stack = gtk::Stack::builder()
            .transition_type(gtk::StackTransitionType::Crossfade)
            .transition_duration(180)
            .vexpand(true)
            .hexpand(true)
            .build();

        chat_handle.set_on_open_focus(Rc::new({
            let stack = stack.clone();
            move || {
                stack.set_visible_child_name("missions");
            }
        }));

        let attention_sink: Rc<RefCell<Rc<dyn Fn(u32)>>> =
            Rc::new(RefCell::new(Rc::new(|_: u32| {})));
        let (home, home_handle) = {
            let stack = stack.clone();
            let chat_handle = chat_handle.clone();
            let attention_sink_for_hooks = attention_sink.clone();
            // Mission Deck (React / WebKit) replaces the legacy GTK Missions surface.
            crate::mission_deck_page::build(crate::home_page::HomeHooks {
                on_ask_about: Rc::new(
                    move |topic: crate::chat_page::DiscussTopic, kickoff: String| {
                        chat_handle.seed_discuss_topic(topic, &kickoff);
                        stack.set_visible_child_name("chat");
                    },
                ),
                on_attention_changed: Rc::new(move |n: u32| {
                    (attention_sink_for_hooks.borrow())(n);
                }),
            })
        };

        stack.add_titled(&chat, Some("chat"), "Chat");
        stack.add_titled(&home, Some("missions"), "Focus");
        stack.add_titled(&settings_scroll, Some("settings"), "Settings");
        stack.set_visible_child_name("chat");
        chat.set_vexpand(true);
        home.set_vexpand(true);
        settings_scroll.set_vexpand(true);
        settings_scroll.set_hexpand(true);

        let (tab_bar, tab_badges_ui) = build_attention_tab_bar(
            &stack,
            &[("chat", "Chat"), ("missions", "Focus"), ("settings", "Settings")],
        );

        let refresh_settings_attention_ui = {
            let banner = settings_attention_banner.clone();
            let thinking_settings_row = thinking_settings_row.clone();
            let thinking_attention_mark = thinking_attention_mark.clone();
            let devices_section = devices_section.clone();
            let devices_attention_mark = devices_attention_mark.clone();
            let fix_thinking_row = fix_thinking_row.clone();
            let update_row = update_row.clone();
            let update_attention_mark = update_attention_mark.clone();
            Rc::new(move |items: Vec<SettingsAttentionItem>| {
                rebuild_settings_attention_banner(&banner, &items);
                let thinking = items
                    .iter()
                    .any(|i| matches!(i, SettingsAttentionItem::Thinking { .. }));
                let remotes = items
                    .iter()
                    .any(|i| matches!(i, SettingsAttentionItem::RemotesOffline { .. }));
                let update = items
                    .iter()
                    .any(|i| matches!(i, SettingsAttentionItem::UpdateAvailable { .. }));
                thinking_attention_mark.set_visible(thinking);
                if thinking {
                    thinking_settings_row.add_css_class("centurion-needs-attention");
                    fix_thinking_row.add_css_class("centurion-needs-attention");
                } else {
                    thinking_settings_row.remove_css_class("centurion-needs-attention");
                    fix_thinking_row.remove_css_class("centurion-needs-attention");
                }
                devices_attention_mark.set_visible(remotes);
                if remotes {
                    devices_section.add_css_class("centurion-needs-attention");
                } else {
                    devices_section.remove_css_class("centurion-needs-attention");
                }
                update_attention_mark.set_visible(update);
                if update {
                    update_row.add_css_class("centurion-needs-attention");
                    if let Some((_, detail)) = load_update_attention() {
                        update_row.set_subtitle(&detail);
                    }
                } else {
                    update_row.remove_css_class("centurion-needs-attention");
                }
            }) as Rc<dyn Fn(Vec<SettingsAttentionItem>)>
        };

        let refresh_home_badge = {
            let tab_badges_ui = tab_badges_ui.clone();
            let home_handle = home_handle.clone();
            Rc::new(move || {
                let n = home_handle.attention_count();
                if n > 0 {
                    tab_badges_ui.set_badge("missions", Some(&n.to_string()));
                } else {
                    tab_badges_ui.set_badge("missions", None);
                }
            }) as Rc<dyn Fn()>
        };
        let apply_settings_badge = {
            let tab_badges_ui = tab_badges_ui.clone();
            let refresh_settings_attention_ui = refresh_settings_attention_ui.clone();
            Rc::new(move |items: Vec<SettingsAttentionItem>| {
                let needs = !items.is_empty();
                if needs {
                    tab_badges_ui.set_badge("settings", Some("!"));
                } else {
                    tab_badges_ui.set_badge("settings", None);
                }
                refresh_settings_attention_ui(items);
            }) as Rc<dyn Fn(Vec<SettingsAttentionItem>)>
        };
        let refresh_settings_badge = {
            let apply_settings_badge = apply_settings_badge.clone();
            Rc::new(move || {
                // Probe off the UI thread; apply when ready.
                let apply_settings_badge = apply_settings_badge.clone();
                let (tx, rx) = std::sync::mpsc::channel::<Vec<SettingsAttentionItem>>();
                std::thread::spawn(move || {
                    let _ = tx.send(settings_attention_items());
                });
                glib::timeout_add_local(std::time::Duration::from_millis(40), move || {
                    match rx.try_recv() {
                        Ok(items) => {
                            apply_settings_badge(items);
                            glib::ControlFlow::Break
                        }
                        Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                        Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                    }
                });
            }) as Rc<dyn Fn()>
        };
        let refresh_chat_badge = {
            let tab_badges_ui = tab_badges_ui.clone();
            let chat_handle = chat_handle.clone();
            Rc::new(move || {
                let n = chat_handle.attention_count();
                if n > 0 {
                    tab_badges_ui.set_badge("chat", Some("!"));
                } else {
                    tab_badges_ui.set_badge("chat", None);
                }
            }) as Rc<dyn Fn()>
        };
        let refresh_stack_badges = {
            let refresh_home_badge = refresh_home_badge.clone();
            let refresh_settings_badge = refresh_settings_badge.clone();
            let refresh_chat_badge = refresh_chat_badge.clone();
            Rc::new(move || {
                refresh_home_badge();
                refresh_settings_badge();
                refresh_chat_badge();
            }) as Rc<dyn Fn()>
        };
        *attention_sink.borrow_mut() = {
            let refresh_home_badge = refresh_home_badge.clone();
            Rc::new(move |_n: u32| {
                refresh_home_badge();
            })
        };
        chat_handle.set_on_attention_changed({
            let refresh_chat_badge = refresh_chat_badge.clone();
            Rc::new(move |_n: u32| {
                refresh_chat_badge();
            })
        });
        refresh_stack_badges();

        // Update check is deferred off critical path — only hourly after first
        // hour, or when the user opens Settings → Update. Avoids git/PyPI WAN
        // during Brain startup.
        {
            let update_row2 = update_row.clone();
            let refresh_settings_badge2 = refresh_settings_badge.clone();
            glib::timeout_add_seconds_local(3600, move || {
                probe_update_attention_async(update_row2.clone(), refresh_settings_badge2.clone());
                glib::ControlFlow::Continue
            });
        }

        let poll_list = device_list.clone();
        let poll_stack = stack.clone();
        let poll_settings_badge = refresh_settings_badge.clone();
        glib::timeout_add_seconds_local(5, move || {
            if poll_stack.visible_child_name().as_deref() == Some("settings") {
                refresh_devices(&poll_list);
            }
            // Light poll for Settings (!) — probes run off the UI thread.
            poll_settings_badge();
            glib::ControlFlow::Continue
        });
        let tab_refresh_list = device_list.clone();
        let tab_badges = refresh_stack_badges.clone();
        let tab_home_handle = home_handle.clone();
        stack.connect_visible_child_name_notify(move |stack| {
            if stack.visible_child_name().as_deref() == Some("settings") {
                refresh_devices(&tab_refresh_list);
            }
            let missions_visible = stack.visible_child_name().as_deref() == Some("missions");
            // Pause Mission Deck WebView + polls while Chat/Settings is active.
            tab_home_handle.notify_tab_visible(missions_visible);
            // Soft refresh (visibility inject) — do not hard-reload the WebView.
            if missions_visible {
                tab_home_handle.refresh();
            }
            tab_badges();
        });
        // Default tab is Chat — suspend Deck immediately after wire-up.
        home_handle.notify_tab_visible(false);

        let switcher = tab_bar;
        let header = adw::HeaderBar::new();
        header.set_title_widget(Some(&switcher));
        // Ensure DE window buttons (minimize/maximize/close) are available.
        header.set_show_start_title_buttons(true);
        header.set_show_end_title_buttons(true);
        let toolbar = adw::ToolbarView::new();
        toolbar.add_top_bar(&header);
        toolbar.set_content(Some(&stack));

        let window = adw::ApplicationWindow::builder()
            .application(application)
            .title("Sovereign AI Brain")
            .default_width(980)
            .default_height(700)
            .resizable(true)
            .content(&toolbar)
            .build();
        install_window_size_controls(&header, &window);

        let update_status = {
            let status_title = status_title.clone();
            let status_detail = status_detail.clone();
            let link_addresses = link_addresses.clone();
            let window = window.clone();
            let supervisor = supervisor.clone();
            move || match supervisor.borrow_mut().ensure_running() {
                Ok(()) => {
                    status_title.set_label("Your Centurion is ready");
                    status_detail.set_label(
                        "On the same Wi‑Fi, open Sovereign AI Remote and scan the pairing QR.",
                    );
                    refresh_link_addresses(&link_addresses, Some(&window));
                }
                Err(error) => {
                    status_title.set_label("Your Centurion needs attention");
                    status_detail.set_label(&error);
                    refresh_link_addresses(&link_addresses, Some(&window));
                }
            }
        };

        update_status();
        // First-run: teach what a Centurion is. Pairing QR is opt-in, not the product story.
        if !brain_welcome_seen() && !any_iphones_linked() {
            let window = window.clone();
            glib::timeout_add_local_once(std::time::Duration::from_millis(400), move || {
                show_brain_welcome_dialog(&window);
            });
        }
        // Defer Settings row fills until after first paint so cold-start Chat
        // is not blocked by provider/bridge probes.
        {
            let thinking_detail = thinking_detail.clone();
            let thinking_settings_row = thinking_settings_row.clone();
            let backup_thinking_row = backup_thinking_row.clone();
            let autonomy_row = autonomy_row.clone();
            let soul_row = soul_row.clone();
            let memory_horizon_row = memory_horizon_row.clone();
            let oversight_row = oversight_row.clone();
            glib::idle_add_local_once(move || {
                let thinking_detail = thinking_detail.clone();
                let thinking_settings_row = thinking_settings_row.clone();
                let backup_thinking_row = backup_thinking_row.clone();
                let autonomy_row = autonomy_row.clone();
                let soul_row = soul_row.clone();
                let memory_horizon_row = memory_horizon_row.clone();
                let oversight_row = oversight_row.clone();
                let (tx, rx) = std::sync::mpsc::channel::<(
                    Option<serde_json::Value>,
                    Option<serde_json::Value>,
                    Option<serde_json::Value>,
                    Option<String>,
                )>();
                std::thread::spawn(move || {
                    let soul = run_bridge_action("soul_get", serde_json::json!({}));
                    let oversight = run_bridge_action("oversight_get", serde_json::json!({}));
                    let horizon =
                        run_bridge_action("memory_horizon_snapshot", serde_json::json!({}));
                    let thinking_line = run_provider_command(&["status", "--skip-probe"]).and_then(
                        |response| {
                            response.status.map(|status| {
                                let model = status.model;
                                if model.is_empty() {
                                    status.provider
                                } else {
                                    format!("{} · {}", status.provider, model)
                                }
                            })
                        },
                    );
                    let _ = tx.send((soul, oversight, horizon, thinking_line));
                });
                refresh_backup_thinking_services(&backup_thinking_row);
                refresh_autonomy_row(&autonomy_row);
                glib::timeout_add_local(std::time::Duration::from_millis(40), move || {
                    match rx.try_recv() {
                        Ok((soul, oversight, horizon, thinking_line)) => {
                            if let Some(line) = thinking_line {
                                thinking_detail.set_label(&line);
                                thinking_settings_row.set_subtitle(&line);
                            }
                            // Reuse the existing row appliers (they re-read via
                            // bridge daemon — cheap once warm).
                            let _ = (soul, oversight, horizon);
                            refresh_soul_row(&soul_row);
                            refresh_memory_horizon_row(&memory_horizon_row);
                            refresh_oversight_row(&oversight_row);
                            glib::ControlFlow::Break
                        }
                        Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                        Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                            refresh_thinking_status(&thinking_detail, &thinking_settings_row);
                            refresh_soul_row(&soul_row);
                            refresh_memory_horizon_row(&memory_horizon_row);
                            refresh_oversight_row(&oversight_row);
                            glib::ControlFlow::Break
                        }
                    }
                });
            });
        }
        let thinking_poll_detail = thinking_detail.clone();
        let thinking_poll_row = thinking_settings_row.clone();
        let backup_poll_row = backup_thinking_row.clone();
        let autonomy_poll_row = autonomy_row.clone();
        let soul_poll_row = soul_row.clone();
        let memory_horizon_poll_row = memory_horizon_row.clone();
        let oversight_poll_row = oversight_row.clone();
        glib::timeout_add_seconds_local(30, move || {
            let thinking_poll_detail = thinking_poll_detail.clone();
            let thinking_poll_row = thinking_poll_row.clone();
            let backup_poll_row = backup_poll_row.clone();
            let autonomy_poll_row = autonomy_poll_row.clone();
            let soul_poll_row = soul_poll_row.clone();
            let memory_horizon_poll_row = memory_horizon_poll_row.clone();
            let oversight_poll_row = oversight_poll_row.clone();
            // Run bridge I/O on a worker so the GTK main loop stays responsive.
            // (Daemon makes each call cheap; we still must not block UI on it.)
            let (tx, rx) = std::sync::mpsc::channel::<(
                Option<serde_json::Value>,
                Option<serde_json::Value>,
                Option<serde_json::Value>,
                Option<String>,
                Option<String>,
            )>();
            std::thread::spawn(move || {
                let soul = run_bridge_action("soul_get", serde_json::json!({}));
                let oversight = run_bridge_action("oversight_get", serde_json::json!({}));
                let horizon =
                    run_bridge_action("memory_horizon_snapshot", serde_json::json!({}));
                let thinking_line = run_provider_command(&["status", "--skip-probe"]).and_then(
                    |response| {
                        let status = response.status?;
                        let plain = match status.health.as_str() {
                            "ok" => "Working normally".to_owned(),
                            "degraded" => "May be slow".to_owned(),
                            _ => "Needs attention".to_owned(),
                        };
                        let mut line = format!("{plain} — {}", status.health_message);
                        if status.last_good_available && status.health != "ok" {
                            line.push_str(" Last working setup is available.");
                        }
                        Some(line)
                    },
                );
                let backup_line = run_support_command(&["backups"]).map(|response| {
                    let backups = response
                        .result
                        .as_ref()
                        .and_then(|value| value.get("backups"))
                        .and_then(|value| value.as_array())
                        .cloned()
                        .unwrap_or_default();
                    if backups.is_empty() {
                        "No backup thinking services configured.".to_owned()
                    } else {
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
                            format!("{} backup thinking service(s) configured.", backups.len())
                        } else {
                            labels.join(" · ")
                        }
                    }
                });
                let _ = tx.send((soul, oversight, horizon, thinking_line, backup_line));
            });
            glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
                match rx.try_recv() {
                    Ok((soul, oversight, horizon, thinking_line, backup_line)) => {
                        if let Some(line) = thinking_line {
                            thinking_poll_detail.set_label(&line);
                            thinking_poll_row.set_subtitle(&line);
                        }
                        if let Some(line) = backup_line {
                            backup_poll_row.set_subtitle(&line);
                        }
                        if let Some(payload) = oversight.as_ref() {
                            let level = payload
                                .pointer("/oversight/autonomy_level")
                                .and_then(|v| v.as_str())
                                .unwrap_or("balanced");
                            autonomy_poll_row.set_subtitle(autonomy_label(level));
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
                            oversight_poll_row.set_subtitle(&format!(
                                "{cadence_label} · ask before initiative: {}",
                                if ask { "on" } else { "off" }
                            ));
                        }
                        if let Some(payload) = soul {
                            apply_soul_row_subtitle(&soul_poll_row, &payload);
                        }
                        if let Some(payload) = horizon {
                            apply_memory_horizon_row_subtitle(
                                &memory_horizon_poll_row,
                                &payload,
                            );
                        }
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                }
            });
            glib::ControlFlow::Continue
        });
        restore_thinking_button.connect_clicked({
            let thinking_settings_row = thinking_settings_row.clone();
            let thinking_detail = thinking_detail.clone();
            move |_| {
                if let Some(response) = run_provider_command(&["restore"]) {
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
                    refresh_thinking_status(&thinking_detail, &thinking_settings_row);
                }
            }
        });
        change_thinking_button.connect_clicked({
            let thinking_settings_row = thinking_settings_row.clone();
            let thinking_detail = thinking_detail.clone();
            let window = window.clone();
            move |_| show_change_thinking_dialog(&window, &thinking_settings_row, &thinking_detail)
        });
        let backup_manage_button = gtk::Button::with_label("Details");
        backup_manage_button.set_valign(gtk::Align::Center);
        backup_thinking_row.add_suffix(&backup_manage_button);
        backup_manage_button.connect_clicked({
            let window = window.clone();
            let backup_thinking_row = backup_thinking_row.clone();
            move |_| show_backup_thinking_dialog(&window, &backup_thinking_row)
        });
        fleet_peer_button.connect_clicked({
            let window = window.clone();
            move |_| show_fleet_peer_dialog(&window)
        });
        plugins_button.connect_clicked({
            let window = window.clone();
            move |_| show_plugins_list_dialog(&window)
        });
        ops_button.connect_clicked({
            let window = window.clone();
            move |_| show_ops_glance_dialog(&window)
        });
        collab_connect_button.connect_clicked({
            let window = window.clone();
            let home_handle = home_handle.clone();
            move |_| {
                crate::home_page::show_connect_collab_dialog(
                    &window,
                    Rc::new({
                        let home_handle = home_handle.clone();
                        move || home_handle.refresh()
                    }),
                );
            }
        });
        pairing_settings_row.connect_activated({
            let window = window.clone();
            move |_| {
                show_pairing_qr_window(&window);
            }
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
        soul_shape_button.connect_clicked({
            let window = window.clone();
            let soul_row = soul_row.clone();
            move |_| {
                crate::interviews::show_soul_interview(
                    &window,
                    Rc::new({
                        let soul_row = soul_row.clone();
                        move || refresh_soul_row(&soul_row)
                    }),
                );
            }
        });
        life_mission_edit_button.connect_clicked({
            let window = window.clone();
            let home_handle = home_handle.clone();
            move |_| {
                let current = run_bridge_action("mission_get", serde_json::json!({}))
                    .and_then(|r| {
                        if r.get("ok").and_then(|v| v.as_bool()) == Some(true) {
                            r.get("mission")
                                .and_then(|m| m.get("statement"))
                                .and_then(|v| v.as_str())
                                .map(|s| s.to_owned())
                        } else {
                            None
                        }
                    })
                    .unwrap_or_default();
                crate::home_page::show_mission_edit_dialog(
                    &window,
                    &current,
                    Rc::new({
                        let home_handle = home_handle.clone();
                        move || home_handle.refresh()
                    }),
                );
            }
        });
        mission_stack_button.connect_clicked({
            let stack = stack.clone();
            move |_| {
                stack.set_visible_child_name("missions");
            }
        });
        mission_discover_button.connect_clicked({
            let window = window.clone();
            let home_handle = home_handle.clone();
            move |_| {
                crate::interviews::show_mission_discovery(
                    &window,
                    Rc::new({
                        let home_handle = home_handle.clone();
                        move || home_handle.refresh()
                    }),
                );
            }
        });
        about_you_button.connect_clicked({
            let window = window.clone();
            let home_handle = home_handle.clone();
            move |_| {
                crate::interviews::show_about_you_interview(
                    &window,
                    Rc::new({
                        let home_handle = home_handle.clone();
                        move || home_handle.refresh()
                    }),
                );
            }
        });
        privacy_row.connect_activated({
            let window = window.clone();
            move |_| crate::interviews::show_privacy_trust_dialog(&window)
        });
        pulse_pref_switch.connect_active_notify(|sw| {
            save_decision_first_pref(sw.is_active());
        });
        skills_button.connect_clicked({
            let window = window.clone();
            move |_| show_skills_tools_dialog(&window)
        });
        license_button.connect_clicked({
            let window = window.clone();
            move |_| show_license_dialog(&window)
        });
        beneficiary_button.connect_clicked({
            let window = window.clone();
            move |_| show_beneficiary_dialog(&window)
        });
        gateway_start_btn.connect_clicked({
            let gateway_row = gateway_row.clone();
            let gateway_platform_list = gateway_platform_list.clone();
            move |_| {
                let _ = run_bridge_action("gateway_start", serde_json::json!({}));
                refresh_gateway_ui(&gateway_row, &gateway_platform_list);
            }
        });
        gateway_stop_btn.connect_clicked({
            let gateway_row = gateway_row.clone();
            let gateway_platform_list = gateway_platform_list.clone();
            move |_| {
                let _ = run_bridge_action("gateway_stop", serde_json::json!({}));
                refresh_gateway_ui(&gateway_row, &gateway_platform_list);
            }
        });
        gateway_restart_btn.connect_clicked({
            let gateway_row = gateway_row.clone();
            let gateway_platform_list = gateway_platform_list.clone();
            move |_| {
                let _ = run_bridge_action("gateway_restart", serde_json::json!({}));
                refresh_gateway_ui(&gateway_row, &gateway_platform_list);
            }
        });
        refresh_gateway_ui(&gateway_row, &gateway_platform_list);
        fix_thinking_button.connect_clicked({
            let window = window.clone();
            let thinking_settings_row = thinking_settings_row.clone();
            let thinking_detail = thinking_detail.clone();
            move |_| show_change_thinking_dialog(&window, &thinking_settings_row, &thinking_detail)
        });
        auto_fix_button.connect_clicked({
            let window = window.clone();
            move |_| show_support_auto_fix_dialog(&window)
        });
        memory_horizon_button.connect_clicked({
            let window = window.clone();
            let memory_horizon_row = memory_horizon_row.clone();
            let stack = stack.clone();
            let chat_handle = chat_handle.clone();
            move |_| {
                show_memory_horizon_dialog(
                    &window,
                    &memory_horizon_row,
                    Rc::new({
                        let stack = stack.clone();
                        let chat_handle = chat_handle.clone();
                        move |title: String, detail: String| {
                            chat_handle.seed_discuss_topic(
                                crate::chat_page::DiscussTopic::horizon(&title, &detail),
                                &detail,
                            );
                            stack.set_visible_child_name("chat");
                        }
                    }),
                )
            }
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
            let refresh_settings_badge = refresh_settings_badge.clone();
            move |_| {
                show_update_check_dialog(&window, &update_row, refresh_settings_badge.clone())
            }
        });
        rebuild_screen_button.connect_clicked({
            let window = window.clone();
            let update_row = update_row.clone();
            let refresh_settings_badge = refresh_settings_badge.clone();
            move |_| {
                run_screen_rebuild(&window, &update_row, refresh_settings_badge.clone())
            }
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
            let thinking_detail = thinking_detail.clone();
            move || {
                open_adrian_dialog(&window, &stack, &thinking_settings_row, &thinking_detail)
            }
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
            let thinking_settings_row = thinking_settings_row.clone();
            let thinking_detail = thinking_detail.clone();
            move |_| show_get_help_dialog(&window, &thinking_settings_row, &thinking_detail)
        });
        restart.connect_clicked({
            let link_addresses = link_addresses.clone();
            let window = window.clone();
            move |_| {
                let result = supervisor.borrow_mut().restart();
                match result {
                    Ok(()) => {
                        status_title.set_label("Your Centurion is ready");
                        status_detail.set_label(
                            "The private desk connection has restarted. Use Link iPhone under Settings if you need a fresh pairing QR.",
                        );
                        refresh_link_addresses(&link_addresses, Some(&window));
                    }
                    Err(error) => {
                        status_title.set_label("Restart did not complete");
                        status_detail.set_label(&error);
                        refresh_link_addresses(&link_addresses, Some(&window));
                    }
                }
            }
        });

        chat_handle.set_on_fix_thinking(Rc::new({
            let window = window.clone();
            let thinking_settings_row = thinking_settings_row.clone();
            let thinking_detail = thinking_detail.clone();
            move || {
                show_change_thinking_dialog(&window, &thinking_settings_row, &thinking_detail);
            }
        }));

        window.present();
    }

    fn build_chat_page() -> (gtk::Box, crate::chat_page::ChatHandle) {
        let (page, handle) = crate::chat_page::build();
        page.set_vexpand(true);
        page.set_hexpand(true);
        (page, handle)
    }

    /// Explicit size controls — some Linux DEs only show Close on client-side
    /// decorations. Pack Minimize / Maximize / Fullscreen on the left so the
    /// owner can tile or expand the Brain window like a normal desktop app.
    fn install_window_size_controls(header: &adw::HeaderBar, window: &adw::ApplicationWindow) {
        let minimize = gtk::Button::from_icon_name("window-minimize-symbolic");
        minimize.set_tooltip_text(Some("Minimize"));
        minimize.add_css_class("flat");
        minimize.connect_clicked({
            let window = window.clone();
            move |_| {
                window.minimize();
            }
        });

        let maximize = gtk::Button::from_icon_name("window-maximize-symbolic");
        maximize.set_tooltip_text(Some("Maximize / Restore"));
        maximize.add_css_class("flat");
        maximize.connect_clicked({
            let window = window.clone();
            move |_| {
                if window.is_maximized() {
                    window.unmaximize();
                } else {
                    window.maximize();
                }
            }
        });

        let fullscreen = gtk::Button::from_icon_name("view-fullscreen-symbolic");
        fullscreen.set_tooltip_text(Some("Full screen"));
        fullscreen.add_css_class("flat");
        fullscreen.connect_clicked({
            let window = window.clone();
            let fullscreen = fullscreen.clone();
            move |_| {
                if window.is_fullscreen() {
                    window.unfullscreen();
                    fullscreen.set_icon_name("view-fullscreen-symbolic");
                    fullscreen.set_tooltip_text(Some("Full screen"));
                } else {
                    window.fullscreen();
                    fullscreen.set_icon_name("view-restore-symbolic");
                    fullscreen.set_tooltip_text(Some("Exit full screen"));
                }
            }
        });

        header.pack_start(&minimize);
        header.pack_start(&maximize);
        header.pack_start(&fullscreen);
    }

    fn settings_needs_attention() -> bool {
        !settings_attention_items().is_empty()
    }

    #[derive(Debug, Clone)]
    enum SettingsAttentionItem {
        Thinking { detail: String },
        RemotesOffline { count: usize },
        UpdateAvailable { detail: String },
    }

    fn settings_attention_items() -> Vec<SettingsAttentionItem> {
        // iPhone You tab "!": thinking unhealthy / unavailable, remotes
        // previously linked but now offline, or a Brain update waiting.
        // Use --skip-probe so the 5s tab-badge poll stays light; update
        // availability is cached from Check / background probe.
        let mut items = Vec::new();
        if let Some((_, detail)) = load_update_attention() {
            items.push(SettingsAttentionItem::UpdateAvailable { detail });
        }
        let thinking_attention = match run_provider_command(&["status", "--skip-probe"]) {
            Some(response) => match response.status {
                Some(status) => {
                    if status.health != "ok" {
                        items.push(SettingsAttentionItem::Thinking {
                            detail: format!(
                                "Thinking service is {} — open Fix Thinking Service or Change Thinking.",
                                status.health
                            ),
                        });
                        true
                    } else {
                        false
                    }
                }
                None => {
                    items.push(SettingsAttentionItem::Thinking {
                        detail: "Thinking service status is unavailable — open Fix Thinking Service."
                            .to_owned(),
                    });
                    true
                }
            },
            None => {
                items.push(SettingsAttentionItem::Thinking {
                    detail: "Thinking service status is unavailable — open Fix Thinking Service."
                        .to_owned(),
                });
                true
            }
        };
        let _ = thinking_attention;

        let centurion_remote = std::env::var("HOME")
            .ok()
            .map(|home| format!("{home}/.local/bin/centurion-remote"))
            .filter(|path| std::path::Path::new(path).is_file())
            .unwrap_or_else(|| "centurion-remote".to_owned());
        let listing = Command::new(&centurion_remote)
            .args(["devices", "--json"])
            .output()
            .ok()
            .filter(|output| output.status.success())
            .and_then(|output| serde_json::from_slice::<DeviceListing>(&output.stdout).ok());
        if let Some(listing) = listing {
            if !listing.approved.is_empty()
                && listing.approved.iter().all(|device| !device.connected)
            {
                items.push(SettingsAttentionItem::RemotesOffline {
                    count: listing.approved.len(),
                });
            }
        }
        items
    }

    fn rebuild_settings_attention_banner(banner: &gtk::Box, items: &[SettingsAttentionItem]) {
        while let Some(child) = banner.first_child() {
            banner.remove(&child);
        }
        if items.is_empty() {
            banner.set_visible(false);
            return;
        }
        banner.set_visible(true);
        let title_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        title_row.append(
            &gtk::Label::builder()
                .label("(!)")
                .css_classes(["centurion-attention-mark"])
                .build(),
        );
        title_row.append(
            &gtk::Label::builder()
                .label("Needs your attention")
                .css_classes(["centurion-attention-banner-title"])
                .xalign(0.0)
                .hexpand(true)
                .build(),
        );
        banner.append(&title_row);
        for item in items {
            let text = match item {
                SettingsAttentionItem::Thinking { detail } => format!("• {detail}"),
                SettingsAttentionItem::RemotesOffline { count } => format!(
                    "• Linked remote{s} offline ({count}) — check Connected Devices above",
                    s = if *count == 1 { "" } else { "s" },
                    count = count
                ),
                SettingsAttentionItem::UpdateAvailable { detail } => format!("• {detail}"),
            };
            banner.append(
                &gtk::Label::builder()
                    .label(&text)
                    .css_classes(["centurion-attention-item"])
                    .xalign(0.0)
                    .wrap(true)
                    .build(),
            );
        }
    }

    /// Tab titles stay ink; badge mark (!) / (N) is red — global attention chrome.
    #[derive(Clone)]
    struct AttentionTabBar {
        badges: Rc<RefCell<HashMap<String, gtk::Label>>>,
    }

    impl AttentionTabBar {
        fn set_badge(&self, tab: &str, mark: Option<&str>) {
            let badges = self.badges.borrow();
            let Some(badge) = badges.get(tab) else {
                return;
            };
            match mark {
                Some(m) if !m.trim().is_empty() => {
                    badge.set_label(&format!("({m})"));
                    badge.set_visible(true);
                }
                _ => {
                    badge.set_label("");
                    badge.set_visible(false);
                }
            }
        }
    }

    fn build_attention_tab_bar(
        stack: &gtk::Stack,
        tabs: &[(&str, &str)],
    ) -> (gtk::Box, AttentionTabBar) {
        let bar = gtk::Box::new(gtk::Orientation::Horizontal, 4);
        bar.add_css_class("centurion-tab-bar");
        bar.set_halign(gtk::Align::Center);

        let badges: Rc<RefCell<HashMap<String, gtk::Label>>> =
            Rc::new(RefCell::new(HashMap::new()));
        let buttons: Rc<RefCell<HashMap<String, gtk::ToggleButton>>> =
            Rc::new(RefCell::new(HashMap::new()));
        let mut group_leader: Option<gtk::ToggleButton> = None;

        for &(name, title) in tabs {
            let btn = gtk::ToggleButton::new();
            btn.add_css_class("centurion-tab");
            if let Some(leader) = group_leader.as_ref() {
                btn.set_group(Some(leader));
            } else {
                group_leader = Some(btn.clone());
            }

            let content = gtk::Box::new(gtk::Orientation::Horizontal, 4);
            content.append(
                &gtk::Label::builder()
                    .label(title)
                    .css_classes(["centurion-tab-title"])
                    .build(),
            );
            let badge = gtk::Label::builder()
                .label("")
                .css_classes(["centurion-tab-badge"])
                .visible(false)
                .build();
            content.append(&badge);
            btn.set_child(Some(&content));

            let stack_c = stack.clone();
            let name_owned = name.to_owned();
            btn.connect_clicked(move |_| {
                stack_c.set_visible_child_name(&name_owned);
            });

            badges.borrow_mut().insert(name.to_owned(), badge);
            buttons.borrow_mut().insert(name.to_owned(), btn.clone());
            bar.append(&btn);
        }

        let buttons_sync = buttons.clone();
        stack.connect_visible_child_name_notify(move |stack| {
            let visible = stack
                .visible_child_name()
                .map(|s| s.as_str().to_owned())
                .unwrap_or_default();
            for (name, btn) in buttons_sync.borrow().iter() {
                let on = name == &visible;
                if btn.is_active() != on {
                    btn.set_active(on);
                }
            }
        });
        if let Some(btn) = buttons.borrow().get("chat") {
            btn.set_active(true);
        }

        (bar, AttentionTabBar { badges })
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
            let short_id = if device.fingerprint.len() > 10 {
                format!(
                    "{}…{}",
                    &device.fingerprint[..6],
                    &device.fingerprint[device.fingerprint.len().saturating_sub(4)..]
                )
            } else {
                device.fingerprint.clone()
            };
            let row = adw::ActionRow::builder()
                .title(&device.name)
                .subtitle(format!("Waiting for your approval · {short_id}"))
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
            let short_id = if device.fingerprint.len() > 10 {
                format!(
                    "{}…{}",
                    &device.fingerprint[..6],
                    &device.fingerprint[device.fingerprint.len().saturating_sub(4)..]
                )
            } else {
                device.fingerprint.clone()
            };
            let subtitle = if device.connected {
                format!(
                    "Online · {}",
                    device.peer.as_deref().unwrap_or(&short_id)
                )
            } else {
                format!("Approved · {short_id}")
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
            let device_name = device.name.clone();
            let list_refresh = list.clone();
            let remote = centurion_remote.clone();
            revoke.connect_clicked(move |button| {
                let confirm = adw::AlertDialog::builder()
                    .heading("Remove this iPhone?")
                    .body(&format!(
                        "Remove {device_name}? They’ll need a new pairing code to link again."
                    ))
                    .close_response("cancel")
                    .default_response("revoke")
                    .build();
                confirm.add_response("cancel", "Cancel");
                confirm.add_response("revoke", "Remove");
                confirm.set_response_appearance("revoke", adw::ResponseAppearance::Destructive);
                let parent_widget = button.root();
                let button = button.clone();
                let fingerprint = fingerprint.clone();
                let list_refresh = list_refresh.clone();
                let remote = remote.clone();
                confirm.connect_response(None, move |_dialog, response| {
                    if response != "revoke" {
                        return;
                    }
                    button.set_sensitive(false);
                    let revoked = Command::new(&remote)
                        .args(["revoke", &fingerprint])
                        .status()
                        .is_ok_and(|status| status.success());
                    if revoked {
                        refresh_devices(&list_refresh);
                        let done = adw::AlertDialog::builder()
                            .heading("iPhone removed")
                            .body("They’ll need a new pairing code to link again.")
                            .close_response("ok")
                            .build();
                        done.add_response("ok", "OK");
                        done.present(button.root().as_ref());
                    } else {
                        button.set_sensitive(true);
                    }
                });
                confirm.present(parent_widget.as_ref());
            });
            row.add_suffix(&revoke);
            list.append(&row);
        }

        if show_no_devices {
            list.append(
                &adw::ActionRow::builder()
                    .title("No iPhones linked yet")
                    .subtitle("Scan the pairing QR in Settings → Status with Sovereign AI Remote (same Wi‑Fi).")
                    .icon_name("phone-symbolic")
                    .build(),
            );
        } else if show_no_connected {
            list.append(
                &adw::ActionRow::builder()
                    .title("No iPhones connected right now")
                    .subtitle("Approved devices appear here when Sovereign AI Remote links again.")
                    .icon_name("phone-disabled-symbolic")
                    .build(),
            );
        }
    }

    fn centurion_binary() -> String {
        crate::chat_page::resolve_centurion_cli()
    }

    fn prepare_centurion_cli() -> Command {
        let mut command = Command::new(centurion_binary());
        command.env("CENTURION_HOME", crate::chat_page::resolve_centurion_home());
        if let Ok(repo) = std::env::var("CENTURION_AI_REPO") {
            let trimmed = repo.trim();
            if !trimmed.is_empty() {
                let root = PathBuf::from(trimmed);
                command.env("CENTURION_AI_REPO", trimmed);
                if root.is_dir() {
                    command.current_dir(&root);
                }
                return command;
            }
        }
        if let Ok(root) = resolve_centurion_repo_root() {
            command.env("CENTURION_AI_REPO", root.as_os_str());
            command.current_dir(&root);
        }
        command
    }

    fn run_provider_command(args: &[&str]) -> Option<ProviderCliResponse> {
        // `--json` belongs on the parent `provider` parser, before the subcommand.
        let rest: Vec<&str> = args.iter().copied().filter(|a| *a != "--json").collect();
        let mut command_args = vec!["provider", "--json"];
        command_args.extend_from_slice(&rest);
        let output = prepare_centurion_cli()
            .args(command_args)
            .output()
            .ok()?;
        // Parse JSON even when exit status is non-zero so callers can show
        // structured failure messages (e.g. blocked OpenRouter, missing key).
        serde_json::from_slice(&output.stdout).ok()
    }

    fn run_provider_save_key(connector_id: &str, access_code: &str) -> Option<ProviderCliResponse> {
        let mut child = prepare_centurion_cli()
            .args(["provider", "--json", "save-key", connector_id, "-"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .ok()?;
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(access_code.as_bytes());
        }
        let output = child.wait_with_output().ok()?;
        serde_json::from_slice(&output.stdout).ok()
    }

    fn run_support_command(args: &[&str]) -> Option<ProviderCliResponse> {
        // `--json` belongs on the parent `support` parser, before the subcommand.
        let rest: Vec<&str> = args.iter().copied().filter(|a| *a != "--json").collect();
        let mut command_args = vec!["support", "--json"];
        command_args.extend_from_slice(&rest);
        let output = prepare_centurion_cli()
            .args(command_args)
            .output()
            .ok()?;
        // Parse even on non-zero exit so lookup/health can surface `message`.
        serde_json::from_slice(&output.stdout).ok()
    }

    fn run_update_check() -> Option<UpdateCheckPayload> {
        let output = prepare_centurion_cli()
            .args([
                "update",
                "--check",
                "--json",
                "--screen-version",
                env!("CARGO_PKG_VERSION"),
            ])
            .output()
            .ok()?;
        // Parse JSON even when exit status is non-zero (network / unavailable).
        serde_json::from_slice(&output.stdout).ok()
    }

    /// Resolve the Centurion AI OS checkout that contains `install-user.sh`.
    fn resolve_centurion_repo_root() -> Result<PathBuf, String> {
        let candidates: Vec<PathBuf> = {
            let mut list = Vec::new();
            if let Ok(env_root) = std::env::var("CENTURION_AI_REPO") {
                let trimmed = env_root.trim();
                if !trimmed.is_empty() {
                    list.push(PathBuf::from(trimmed));
                }
            }
            if let Ok(home) = std::env::var("HOME") {
                let home = PathBuf::from(home);
                list.push(home.join("Centurion-AI-OS").join("Centurion-AI-OS"));
                list.push(home.join("Centurion-AI-OS"));
                list.push(home.join(".centurion").join("Centurion-AI-OS"));
            }
            list
        };

        for root in candidates {
            let script = root
                .join("desktop-native")
                .join("scripts")
                .join("install-user.sh");
            if script.is_file() {
                return Ok(root);
            }
        }
        Err(
            "Could not find the Centurion software folder on this brain.\n\n\
             Ask your advisor to install the Centurion checkout, then try again."
                .to_owned(),
        )
    }

    fn run_os_update() -> Result<String, String> {
        let output = prepare_centurion_cli()
            // Brain Settings must not re-apply a dirty autostash over the
            // just-pulled release — that was breaking install-user.sh rebuilds.
            .args(["update", "-y", "--no-restore-stash"])
            .output()
            .map_err(|error| error.to_string())?;
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        if output.status.success() {
            Ok(if stdout.is_empty() {
                "Brain software update finished.".to_owned()
            } else {
                stdout
            })
        } else {
            Err(if !stderr.is_empty() {
                stderr
            } else if !stdout.is_empty() {
                stdout
            } else {
                "Brain software update failed.".to_owned()
            })
        }
    }

    /// Drop local dirt under desktop-native so the screen rebuild matches HEAD.
    fn reset_desktop_native_sources(repo_root: &PathBuf) {
        let _ = Command::new("git")
            .args([
                "-C",
                &repo_root.to_string_lossy(),
                "checkout",
                "--",
                "desktop-native",
            ])
            .output();
        let _ = Command::new("git")
            .args([
                "-C",
                &repo_root.to_string_lossy(),
                "clean",
                "-fd",
                "--",
                "desktop-native",
            ])
            .output();
    }

    fn truncate_update_error(raw: &str) -> String {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            return "Sovereign AI Brain update failed.".to_owned();
        }
        let lines: Vec<&str> = trimmed.lines().collect();
        if lines.len() <= 40 {
            return trimmed.to_owned();
        }
        let tail = lines[lines.len().saturating_sub(40)..].join("\n");
        format!(
            "… (showing last 40 lines)\n{tail}\n\nFull log: ~/.centurion/logs/desktop-build.log"
        )
    }

    /// Prefer a richer blob for support: real rustc errors first, then log tail.
    fn enrich_update_error_for_support(raw: &str) -> String {
        let mut body = truncate_update_error(raw);
        let log_path = PathBuf::from(crate::chat_page::resolve_centurion_home())
            .join("logs")
            .join("desktop-build.log");
        if let Ok(contents) = std::fs::read_to_string(&log_path) {
            // Strip ANSI so `error[E…]:` lines match even when color was forced.
            let plain: String = {
                let mut out = String::with_capacity(contents.len());
                let mut chars = contents.chars().peekable();
                while let Some(c) = chars.next() {
                    if c == '\u{1b}' {
                        if chars.peek() == Some(&'[') {
                            chars.next();
                            while let Some(x) = chars.next() {
                                if x.is_ascii_alphabetic() {
                                    break;
                                }
                            }
                        }
                        continue;
                    }
                    out.push(c);
                }
                out
            };
            let error_lines: Vec<&str> = plain
                .lines()
                .filter(|line| {
                    let t = line.trim_start();
                    t.starts_with("error[")
                        || t.starts_with("error:")
                        || t.starts_with("error :")
                })
                .collect();
            if !error_lines.is_empty() {
                let start = error_lines.len().saturating_sub(80);
                body.push_str("\n\n—— rustc errors (from desktop-build.log) ——\n");
                body.push_str(&error_lines[start..].join("\n"));
            }
            let lines: Vec<&str> = plain.lines().collect();
            if !lines.is_empty() {
                let tail = lines[lines.len().saturating_sub(40)..].join("\n");
                body.push_str("\n\n—— desktop-build.log (last 40 lines) ——\n");
                body.push_str(&tail);
            }
        }
        format!(
            "Sovereign AI Brain {}\n\n{body}\n",
            env!("CARGO_PKG_VERSION")
        )
    }

    fn copy_text_to_clipboard(text: &str) {
        if let Some(display) = gtk::gdk::Display::default() {
            display.clipboard().set_text(text);
        }
    }

    /// Error dialog with selectable text + Copy — so owners can paste failures for support.
    fn show_copyable_error_dialog(
        parent: &adw::ApplicationWindow,
        heading: &str,
        body: &str,
    ) {
        let view = gtk::TextView::builder()
            .editable(false)
            .cursor_visible(false)
            .wrap_mode(gtk::WrapMode::WordChar)
            .hexpand(true)
            .vexpand(true)
            .build();
        view.add_css_class("centurion-error-log");
        view.buffer().set_text(body);
        let scroll = gtk::ScrolledWindow::builder()
            .child(&view)
            .min_content_height(240)
            .min_content_width(460)
            .hscrollbar_policy(gtk::PolicyType::Automatic)
            .vscrollbar_policy(gtk::PolicyType::Automatic)
            .build();
        let dialog = adw::AlertDialog::builder()
            .heading(heading)
            .body("Copy this error and send it for support — that makes fixes much faster.")
            .extra_child(&scroll)
            .close_response("ok")
            .default_response("copy")
            .build();
        dialog.add_response("copy", "Copy error");
        dialog.add_response("ok", "OK");
        dialog.set_response_appearance("copy", adw::ResponseAppearance::Suggested);
        let body_owned = body.to_owned();
        dialog.connect_response(None, move |_dialog, response| {
            if response == "copy" {
                copy_text_to_clipboard(&body_owned);
            }
        });
        dialog.present(Some(parent));
    }

    fn run_native_brain_install(repo_root: &PathBuf) -> Result<(), String> {
        reset_desktop_native_sources(repo_root);
        let script = repo_root
            .join("desktop-native")
            .join("scripts")
            .join("install-user.sh");
        if !script.is_file() {
            return Err(format!(
                "Update script missing at {}.",
                script.display()
            ));
        }
        let home = crate::chat_page::resolve_centurion_home();
        let script_arg = script.to_string_lossy().replace('\'', "'\\''");
        let repo_arg = repo_root.to_string_lossy().replace('\'', "'\\''");
        let home_arg = home.replace('\'', "'\\''");
        let shell_cmd = format!(
            "export CENTURION_AI_REPO='{repo_arg}' CENTURION_HOME='{home_arg}'; \
             exec bash '{script_arg}'"
        );
        let output = Command::new("bash")
            .arg("-lc")
            .arg(shell_cmd)
            .output()
            .map_err(|error| format!("Could not start Sovereign AI Brain update: {error}"))?;
        if output.status.success() {
            Ok(())
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
            let combined = if !stderr.is_empty() {
                stderr
            } else if !stdout.is_empty() {
                stdout
            } else {
                "Sovereign AI Brain update failed.".to_owned()
            };
            Err(truncate_update_error(&combined))
        }
    }

    fn restart_centurion_remote_best_effort() {
        let _ = Command::new("systemctl")
            .args(["--user", "restart", "centurion-remote.service"])
            .output();
    }

    /// Rebuild only Sovereign AI Brain + remote from the local checkout (no OS update).
    fn run_screen_rebuild_pipeline() -> Result<String, String> {
        let repo_root = resolve_centurion_repo_root()?;
        run_native_brain_install(&repo_root)?;
        restart_centurion_remote_best_effort();
        Ok(format!(
            "Sovereign AI Brain rebuilt from {}.\n\nQuit and reopen Sovereign AI Brain to load it.\n\
             Brain Chat is local on this computer — no iPhone pairing required.",
            repo_root.display()
        ))
    }

    fn run_screen_rebuild(
        parent: &adw::ApplicationWindow,
        update_row: &adw::ActionRow,
        on_attention: Rc<dyn Fn()>,
    ) {
        // No progress AlertDialog — stacking a modal then replacing it left
        // response buttons dead on the Brain (Wayland / touch). Subtitle is enough.
        update_row.set_subtitle("Rebuilding Sovereign AI Brain…");
        let parent_for_result = parent.clone();
        let update_row_for_result = update_row.clone();
        let on_attention = on_attention.clone();
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(run_screen_rebuild_pipeline());
        });
        glib::timeout_add_local(std::time::Duration::from_millis(100), move || {
            match rx.try_recv() {
                Ok(result) => {
                    match result {
                        Ok(body) => {
                            clear_update_attention();
                            on_attention();
                            update_row_for_result
                                .set_subtitle("Rebuild finished — quit to load the new Brain");
                            let done = adw::AlertDialog::builder()
                                .heading("Sovereign AI Brain rebuilt")
                                .body(&body)
                                .close_response("later")
                                .default_response("quit")
                                .build();
                            done.add_response("later", "Later");
                            done.add_response("quit", "Quit now");
                            done.set_response_appearance(
                                "quit",
                                adw::ResponseAppearance::Suggested,
                            );
                            let parent_for_quit = parent_for_result.clone();
                            done.connect_response(None, move |_dialog, response| {
                                if response == "quit" {
                                    if let Some(app) = parent_for_quit.application() {
                                        app.quit();
                                    } else {
                                        parent_for_quit.close();
                                    }
                                }
                            });
                            done.present(Some(&parent_for_result));
                        }
                        Err(error) => {
                            update_row_for_result.set_subtitle("Sovereign AI Brain rebuild failed");
                            show_copyable_error_dialog(
                                &parent_for_result,
                                "Sovereign AI Brain rebuild failed",
                                &enrich_update_error_for_support(&error),
                            );
                        }
                    }
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    update_row_for_result.set_subtitle("Sovereign AI Brain rebuild failed");
                    glib::ControlFlow::Break
                }
            }
        });
    }

    /// Full Brain update: OS package, then desktop + remote binaries.
    fn run_full_brain_update_pipeline() -> Result<String, String> {
        let os_result = run_os_update();
        let repo_root = resolve_centurion_repo_root()?;
        let install_result = run_native_brain_install(&repo_root);
        if install_result.is_ok() {
            restart_centurion_remote_best_effort();
        }
        match (os_result, install_result) {
            (Ok(os_message), Ok(())) => Ok(format!(
                "{os_message}\n\nSovereign AI Brain and the private connection were rebuilt."
            )),
            (Err(os_err), Ok(())) => Ok(format!(
                "Sovereign AI Brain and the private connection were rebuilt.\n\n\
                 Brain software git update did not finish: {os_err}\n\
                 If Chat and Soul look correct, you can ignore the git step."
            )),
            (Err(os_err), Err(install_err)) => Err(format!(
                "{install_err}\n\nGit update also failed:\n{os_err}"
            )),
            (Ok(os_message), Err(install_err)) => Err(format!(
                "{install_err}\n\n(Git step reported: {os_message})"
            )),
        }
    }

    fn show_update_check_dialog(
        parent: &adw::ApplicationWindow,
        update_row: &adw::ActionRow,
        on_attention: Rc<dyn Fn()>,
    ) {
        update_row.set_subtitle("Checking for updates…");
        let parent = parent.clone();
        let update_row = update_row.clone();
        let on_attention = on_attention.clone();
        // Worker thread must not capture GTK widgets (!Send). Poll the result
        // on the main loop instead of glib::idle_add_once from the worker.
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(run_update_check());
        });
        glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
            match rx.try_recv() {
                Ok(payload) => {
                    present_update_check_result(&parent, &update_row, payload, on_attention.clone());
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    present_update_check_result(&parent, &update_row, None, on_attention.clone());
                    glib::ControlFlow::Break
                }
            }
        });
    }

    /// Quiet background probe — updates Settings (!) without a dialog.
    fn probe_update_attention_async(update_row: adw::ActionRow, on_attention: Rc<dyn Fn()>) {
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(run_update_check());
        });
        glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
            match rx.try_recv() {
                Ok(Some(payload)) => {
                    remember_update_check(&payload);
                    if payload.status == "update_available" {
                        let os_version = payload.os_version.as_deref().unwrap_or("newer");
                        let ver = payload
                            .screen_checkout_version
                            .as_deref()
                            .filter(|s| !s.trim().is_empty())
                            .unwrap_or(os_version);
                        update_row.set_subtitle(&format!(
                            "Sovereign AI Brain update available ({ver})"
                        ));
                    } else if payload.status == "up_to_date" {
                        let os_version = payload
                            .os_version
                            .as_deref()
                            .unwrap_or(env!("CARGO_PKG_VERSION"));
                        update_row.set_subtitle(&format!(
                            "Sovereign AI Brain {os_version} — up to date"
                        ));
                    }
                    on_attention();
                    glib::ControlFlow::Break
                }
                Ok(None) => glib::ControlFlow::Break,
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            }
        });
    }

    fn present_update_check_result(
        parent: &adw::ApplicationWindow,
        update_row: &adw::ActionRow,
        payload: Option<UpdateCheckPayload>,
        on_attention: Rc<dyn Fn()>,
    ) {
        let Some(payload) = payload else {
            update_row.set_subtitle("Could not check for updates.");
            let dialog = adw::AlertDialog::builder()
                .heading("Check for update")
                .body(
                    "Could not check for updates on this brain.\n\n\
                     Make sure Centurion is installed, then try again.",
                )
                .close_response("ok")
                .build();
            dialog.add_response("ok", "OK");
            dialog.present(Some(parent));
            return;
        };

        remember_update_check(&payload);
        on_attention();

        let os_version = payload.os_version.as_deref().unwrap_or("unknown");
        let message = payload
            .message
            .clone()
            .unwrap_or_else(|| "Check complete.".to_owned());

        match payload.status.as_str() {
            "up_to_date" => {
                update_row.set_subtitle(&format!("Sovereign AI Brain {os_version} — up to date"));
                let dialog = adw::AlertDialog::builder()
                    .heading("You're up to date")
                    .body(&format!(
                        "Sovereign AI Brain is current (v{os_version}).\n\n{message}\n\n\
                         If Chat or Settings still look wrong, rebuild Sovereign AI Brain from \
                         the Centurion folder on this computer (no iPhone needed)."
                    ))
                    .close_response("ok")
                    .default_response("rebuild")
                    .build();
                dialog.add_response("ok", "OK");
                dialog.add_response("rebuild", "Rebuild Brain");
                dialog.set_response_appearance("rebuild", adw::ResponseAppearance::Suggested);
                let parent_for_cb = parent.clone();
                let update_row_for_cb = update_row.clone();
                let on_attention_cb = on_attention.clone();
                dialog.connect_response(None, move |_dialog, response| {
                    if response == "rebuild" {
                        let parent = parent_for_cb.clone();
                        let update_row = update_row_for_cb.clone();
                        let on_attention = on_attention_cb.clone();
                        glib::idle_add_local_once(move || {
                            run_screen_rebuild(&parent, &update_row, on_attention);
                        });
                    }
                });
                dialog.present(Some(parent));
            }
            "update_available" => {
                let action = payload
                    .update_action
                    .as_deref()
                    .unwrap_or("full");
                let screen_only = action == "rebuild_screen"
                    || (payload.screen_rebuild_available && payload.behind == 0);
                if screen_only {
                    update_row.set_subtitle(&format!(
                        "Sovereign AI Brain update available ({})",
                        payload
                            .screen_checkout_version
                            .as_deref()
                            .unwrap_or(os_version)
                    ));
                    let body = format!(
                        "{message}\n\nRebuild Sovereign AI Brain from the Centurion folder on this \
                         computer. No published main update is required."
                    );
                    let dialog = adw::AlertDialog::builder()
                        .heading("Sovereign AI Brain update available")
                        .body(&body)
                        .close_response("cancel")
                        .default_response("rebuild")
                        .build();
                    dialog.add_response("cancel", "Not now");
                    dialog.add_response("rebuild", "Rebuild Brain");
                    dialog.set_response_appearance(
                        "rebuild",
                        adw::ResponseAppearance::Suggested,
                    );
                    let parent_for_cb = parent.clone();
                    let update_row_for_cb = update_row.clone();
                    let on_attention_cb = on_attention.clone();
                    dialog.connect_response(None, move |_dialog, response| {
                        if response == "rebuild" {
                            let parent = parent_for_cb.clone();
                            let update_row = update_row_for_cb.clone();
                            let on_attention = on_attention_cb.clone();
                            glib::idle_add_local_once(move || {
                                run_screen_rebuild(&parent, &update_row, on_attention);
                            });
                        }
                    });
                    dialog.present(Some(parent));
                } else {
                    update_row.set_subtitle(&format!(
                        "Sovereign AI Brain update available (v{os_version})"
                    ));
                    let body = format!(
                        "{message}\n\nA Sovereign AI Brain update is available. This updates the \
                         Centurion software on this computer and rebuilds the Brain app. It may \
                         take several minutes; Sovereign AI Remote may briefly disconnect."
                    );
                    let dialog = adw::AlertDialog::builder()
                        .heading("Sovereign AI Brain update available")
                        .body(&body)
                        .close_response("cancel")
                        .default_response("update")
                        .build();
                    dialog.add_response("cancel", "Not now");
                    dialog.add_response("update", "Update now");
                    dialog.set_response_appearance("update", adw::ResponseAppearance::Suggested);
                    let parent_for_cb = parent.clone();
                    let update_row_for_cb = update_row.clone();
                    let on_attention_cb = on_attention.clone();
                    dialog.connect_response(None, move |_dialog, response| {
                        if response == "update" {
                            let parent = parent_for_cb.clone();
                            let update_row = update_row_for_cb.clone();
                            let on_attention = on_attention_cb.clone();
                            glib::idle_add_local_once(move || {
                                run_full_brain_update(&parent, &update_row, on_attention);
                            });
                        }
                    });
                    dialog.present(Some(parent));
                }
            }
            _ => {
                update_row.set_subtitle("Updates managed outside this app");
                let dialog = adw::AlertDialog::builder()
                    .heading("Cannot update from this app")
                    .body(&format!(
                        "{message}\n\nAsk your advisor if updates are managed for this brain."
                    ))
                    .close_response("ok")
                    .build();
                dialog.add_response("ok", "OK");
                dialog.present(Some(parent));
            }
        }
    }

    /// One-confirm full Brain update (OS + desktop + remote).
    fn run_full_brain_update(
        parent: &adw::ApplicationWindow,
        update_row: &adw::ActionRow,
        on_attention: Rc<dyn Fn()>,
    ) {
        update_row.set_subtitle("Updating Sovereign AI Brain…");
        let parent_for_result = parent.clone();
        let update_row_for_result = update_row.clone();
        let on_attention = on_attention.clone();
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(run_full_brain_update_pipeline());
        });
        glib::timeout_add_local(std::time::Duration::from_millis(100), move || {
            match rx.try_recv() {
                Ok(result) => {
                    match result {
                        Ok(body) => {
                            clear_update_attention();
                            on_attention();
                            update_row_for_result
                                .set_subtitle("Update finished — quit to load the new Brain");
                            let done = adw::AlertDialog::builder()
                                .heading("Update complete")
                                .body(&format!(
                                    "{body}\n\nQuit and reopen Sovereign AI Brain to load the update. \
                                     Sovereign AI Remote may reconnect automatically."
                                ))
                                .close_response("later")
                                .default_response("quit")
                                .build();
                            done.add_response("later", "Later");
                            done.add_response("quit", "Quit now");
                            done.set_response_appearance(
                                "quit",
                                adw::ResponseAppearance::Suggested,
                            );
                            let parent_for_quit = parent_for_result.clone();
                            done.connect_response(None, move |_dialog, response| {
                                if response == "quit" {
                                    if let Some(app) = parent_for_quit.application() {
                                        app.quit();
                                    } else {
                                        parent_for_quit.close();
                                    }
                                }
                            });
                            done.present(Some(&parent_for_result));
                        }
                        Err(error) => {
                            update_row_for_result.set_subtitle("Update failed");
                            show_copyable_error_dialog(
                                &parent_for_result,
                                "Update failed",
                                &enrich_update_error_for_support(&error),
                            );
                        }
                    }
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    update_row_for_result.set_subtitle("Update failed");
                    glib::ControlFlow::Break
                }
            }
        });
    }

    fn run_telegram_summary(args: &[&str]) -> Option<serde_json::Value> {
        let mut command_args = vec!["telegram", "import"];
        command_args.extend_from_slice(args);
        command_args.push("--json");
        let output = prepare_centurion_cli()
            .args(command_args)
            .output()
            .ok()?;
        // Parse JSON even when exit status is non-zero (no Telegram history found).
        serde_json::from_slice(&output.stdout).ok()
    }

    fn bridge_python() -> String {
        crate::chat_page::resolve_bridge_python()
    }

    fn run_bridge_action(action: &str, extra: serde_json::Value) -> Option<serde_json::Value> {
        crate::chat_page::run_bridge_action(action, extra)
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
        apply_soul_row_subtitle(row, &payload);
    }

    fn apply_soul_row_subtitle(row: &adw::ActionRow, payload: &serde_json::Value) {
        if payload.get("ok").and_then(|v| v.as_bool()) != Some(true) {
            let message = payload
                .get("message")
                .or_else(|| payload.get("error"))
                .and_then(|v| v.as_str())
                .unwrap_or("Could not read your Sovereign's Soul.");
            row.set_subtitle(message);
            return;
        }
        let name = payload
            .pointer("/soul/name")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim();
        let summary = payload
            .pointer("/soul/personalitySummary")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim();
        if !name.is_empty() {
            if summary.is_empty() {
                row.set_subtitle(&format!("{name} — tap to shape Soul"));
            } else {
                let clipped: String = summary.chars().take(48).collect();
                row.set_subtitle(&format!("{name} · {clipped}"));
            }
            return;
        }
        if summary.is_empty() {
            let exists = payload
                .pointer("/soul/exists")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            row.set_subtitle(if exists {
                "Soul document on this Centurion — set a Name"
            } else {
                "Not set yet — give your Centurion a name"
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
        apply_memory_horizon_row_subtitle(row, &payload);
    }

    fn apply_memory_horizon_row_subtitle(row: &adw::ActionRow, payload: &serde_json::Value) {
        if payload.get("ok").and_then(|v| v.as_bool()) != Some(true) {
            let message = payload
                .get("message")
                .and_then(|v| v.as_str())
                .unwrap_or("Could not read Memory Horizon.");
            row.set_subtitle(message);
            return;
        }
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
        if let Some(cont) = payload.get("snapshot").and_then(|s| s.get("continuity")) {
            let target = cont
                .get("last_digest_target")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let skip = cont
                .get("last_digest_skip_reason")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            if !target.is_empty() {
                let base = row.subtitle().map(|s| s.to_string()).unwrap_or_default();
                row.set_subtitle(&format!("{base} · Continuity → {target}"));
            } else if !skip.is_empty() {
                let base = row.subtitle().map(|s| s.to_string()).unwrap_or_default();
                row.set_subtitle(&format!("{base} · {skip}"));
            }
        }
    }

    fn show_memory_horizon_dialog(
        parent: &adw::ApplicationWindow,
        row: &adw::ActionRow,
        on_ask: Rc<dyn Fn(String, String)>,
    ) {
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

        let continuity = snapshot
            .get("continuity")
            .cloned()
            .unwrap_or(serde_json::json!({}));
        let cont_prefetch = continuity
            .get("continuity_prefetch")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        let cont_digest = continuity
            .get("session_end_digest")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        let last_digest_at = continuity
            .get("last_digest_at")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let last_digest_target = continuity
            .get("last_digest_target")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let last_digest_skip = continuity
            .get("last_digest_skip_reason")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let continuity_status = {
            let mut lines = vec![format!(
                "Prefetch on first turn: {} · Session-end digest: {}",
                if cont_prefetch { "on" } else { "off" },
                if cont_digest { "on" } else { "off" },
            )];
            if !last_digest_at.is_empty() {
                let target = if last_digest_target.is_empty() {
                    "unknown"
                } else {
                    last_digest_target
                };
                lines.push(format!("Last digest: {last_digest_at} → {target}"));
            } else {
                lines.push("Last digest: none yet".to_owned());
            }
            if !last_digest_skip.is_empty() {
                lines.push(last_digest_skip.to_owned());
            }
            lines.join("\n")
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
Grow with durable notes (propose → commit). Passphrase stays on this computer.\n\n\
Being · Continuity\n\
{continuity_status}",
            hot_fill * 100.0,
            format_bytes_short(recall_db),
            format_bytes_short(recall_free),
            recall_fill * 100.0,
        );

        let digest_note = if last_digest_target.eq_ignore_ascii_case("vault") {
            "Recent continuity digests landed in Vault."
        } else if last_digest_target.eq_ignore_ascii_case("hot_cache")
            || last_digest_target.eq_ignore_ascii_case("hot-cache")
            || last_digest_target.eq_ignore_ascii_case("hot")
        {
            "Recent continuity digests landed in Hot Cache (Vault was unavailable)."
        } else if !last_digest_target.is_empty() {
            "See Continuity above for where the last digest was stored."
        } else {
            "No continuity digest yet — digests appear after a session ends."
        };
        let body = format!("{body}\n\n{digest_note}");

        let dialog = adw::AlertDialog::builder()
            .heading("Memory Horizon")
            .body(&body)
            .close_response("close")
            .build();
        dialog.add_response("close", "Close");
        dialog.add_response("hot", "Discuss Hot Cache");
        dialog.add_response("vault", "Discuss Vault");
        if vault_enabled && !vault_init {
            dialog.add_response("vault_setup", "Set up Vault");
        } else if vault_enabled && vault_init && !vault_unlocked {
            dialog.add_response("vault_unlock", "How to unlock Vault");
        }
        dialog.set_default_response(Some("close"));
        let row = row.clone();
        dialog.connect_response(None, move |_dialog, response| {
            refresh_memory_horizon_row(&row);
            match response {
                "hot" => on_ask(
                    "Hot Cache".to_owned(),
                    format!(
                        "Snapshot: {hot_used}/{hot_limit} chars ({:.0}% full); MEMORY {mem_chars}/{mem_limit}; YOU {user_chars}/{user_limit}.\n\nLet's discuss my Hot Cache — what's filling it, what to curate, and whether continuity digests should stay there or move to Vault.",
                        hot_fill * 100.0
                    ),
                ),
                "vault" => on_ask(
                    "Vault".to_owned(),
                    format!(
                        "Snapshot: {}\n\nLet's discuss my Vault — setup, unlock, and what durable notes belong there vs Hot Cache.",
                        vault_status.as_str()
                    ),
                ),
                "vault_setup" => on_ask(
                    "Set up Vault".to_owned(),
                    format!(
                        "Snapshot: {}\n\nHelp me set up and initialize Vault on this computer for durable memory.",
                        vault_status.as_str()
                    ),
                ),
                "vault_unlock" => on_ask(
                    "Unlock Vault".to_owned(),
                    format!(
                        "Snapshot: {}\n\nVault is locked on this computer. Walk me through unlocking it safely with my passphrase.",
                        vault_status.as_str()
                    ),
                ),
                _ => {}
            }
        });
        dialog.present(Some(parent));
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

        let dialog = adw::AlertDialog::builder()
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
        let autonomy_row = autonomy_row.clone();
        let oversight_row = oversight_row.clone();
        dialog.connect_response(None, move |dialog, response| {
            if matches!(response, "strict" | "balanced" | "proactive" | "high") {
                match run_bridge_action(
                    "oversight_put",
                    serde_json::json!({
                        "oversight": { "autonomy_level": response },
                        "apply_level_preset": true,
                    }),
                ) {
                    Some(payload) if payload.get("ok").and_then(|v| v.as_bool()) == Some(true) => {
                        refresh_autonomy_row(&autonomy_row);
                        refresh_oversight_row(&oversight_row);
                    }
                    Some(payload) => {
                        let message = payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .unwrap_or("Could not save autonomy level.");
                        autonomy_row.set_subtitle(message);
                    }
                    None => {
                        autonomy_row.set_subtitle("Could not save autonomy level.");
                    }
                }
            }
            dialog.close();
        });
        dialog.present(Some(parent));
    }

    fn show_soul_dialog(parent: &adw::ApplicationWindow, soul_row: &adw::ActionRow) {
        let payload = match run_bridge_action("soul_get", serde_json::json!({})) {
            Some(payload) if payload.get("ok").and_then(|v| v.as_bool()) == Some(true) => payload,
            Some(payload) => {
                let message = payload
                    .get("message")
                    .or_else(|| payload.get("error"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("Could not read your Sovereign's Soul from disk.");
                let fail = adw::AlertDialog::builder()
                    .heading("Could not load Soul")
                    .body(&format!(
                        "{message}\n\nYour Soul file was not changed. \
                         Try restarting Sovereign AI Brain after an update."
                    ))
                    .close_response("ok")
                    .build();
                fail.add_response("ok", "OK");
                fail.present(Some(parent));
                return;
            }
            None => {
                let fail = adw::AlertDialog::builder()
                    .heading("Could not load Soul")
                    .body(
                        "The Brain bridge did not respond. Your Soul file on disk was not \
                         changed — close Settings, run install-user.sh again if you just \
                         updated, then reopen Soul.",
                    )
                    .close_response("ok")
                    .build();
                fail.add_response("ok", "OK");
                fail.present(Some(parent));
                return;
            }
        };
        let soul = payload
            .get("soul")
            .cloned()
            .unwrap_or_else(|| serde_json::json!({}));
        let name = {
            let structured = soul
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim()
                .to_owned();
            if !structured.is_empty() && !structured.eq_ignore_ascii_case("centurion") {
                structured
            } else {
                let resolved = soul
                    .get("resolvedName")
                    .or_else(|| soul.get("displayName"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim()
                    .to_owned();
                if !resolved.is_empty() && !resolved.eq_ignore_ascii_case("centurion") {
                    resolved
                } else {
                    String::new()
                }
            }
        };
        let markdown = soul
            .get("markdown")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_owned();

        let name_entry = gtk::Entry::builder()
            .text(&name)
            .placeholder_text("Required — e.g. Titus")
            .hexpand(true)
            .build();

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
            .min_content_height(240)
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
                    "Name your Centurion — this is who they are every time they answer. \
                     The Name field is required (e.g. Titus). The Soul below shapes how \
                     they speak and behave. Changes apply on the next message.",
                )
                .wrap(true)
                .xalign(0.0)
                .build(),
        );
        let soul_path = soul
            .get("path")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_owned();
        let profile_name = soul
            .get("profileName")
            .and_then(|v| v.as_str())
            .unwrap_or("default")
            .trim()
            .to_owned();
        if !soul_path.is_empty() {
            let location = if profile_name.is_empty() || profile_name == "default" {
                format!("This profile's Soul file: {soul_path}")
            } else {
                format!("Profile “{profile_name}” Soul file: {soul_path}")
            };
            content.append(
                &gtk::Label::builder()
                    .label(&location)
                    .wrap(true)
                    .xalign(0.0)
                    .css_classes(["caption", "dim-label"])
                    .build(),
            );
            content.append(
                &gtk::Label::builder()
                    .label(
                        "Each profile has its own Soul. Save Titus here only while this \
                         profile is active — Chat will not borrow Soul from another profile.",
                    )
                    .wrap(true)
                    .xalign(0.0)
                    .css_classes(["caption", "dim-label"])
                    .build(),
            );
        }
        content.append(
            &gtk::Label::builder()
                .label("Name")
                .xalign(0.0)
                .css_classes(["caption", "dim-label"])
                .build(),
        );
        content.append(&name_entry);
        content.append(
            &gtk::Label::builder()
                .label("Soul document")
                .xalign(0.0)
                .css_classes(["caption", "dim-label"])
                .build(),
        );
        content.append(&scrolled);

        let dialog = adw::AlertDialog::builder()
            .heading("Your Sovereign's Soul")
            .close_response("cancel")
            .extra_child(&content)
            .build();
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("save", "Save Changes");
        dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
        dialog.set_default_response(Some("save"));
        let soul_row = soul_row.clone();
        // Clone for the 'static response callback — a bare `&parent` does not
        // compile on Linux (borrowed data escapes; broke Brain rebuilds in v5.2.25).
        let parent_for_warn = parent.clone();
        dialog.connect_response(None, move |dialog, response| {
            if response == "save" {
                let (start, end) = buffer.bounds();
                let text = buffer.text(&start, &end, false);
                let name_text = name_entry.text().to_string();
                let trimmed_name = name_text.trim();
                if trimmed_name.is_empty() || trimmed_name.eq_ignore_ascii_case("centurion") {
                    soul_row.set_subtitle(
                        "Set a personal Name (e.g. Titus) — then Save again.",
                    );
                    let warn = adw::AlertDialog::builder()
                        .heading("Name required")
                        .body(
                            "Type a personal name in the Name field (for example Titus). \
                             Without it, Chat can only answer as Centurion.",
                        )
                        .close_response("ok")
                        .build();
                    warn.add_response("ok", "OK");
                    warn.present(Some(&parent_for_warn));
                    return;
                }
                match run_bridge_action(
                    "soul_put",
                    serde_json::json!({
                        "soul": { "name": trimmed_name },
                        "markdown": text.as_str(),
                    }),
                ) {
                    Some(payload) if payload.get("ok").and_then(|v| v.as_bool()) == Some(true) => {
                        // Prior chat turns may have claimed Hermes — clear the
                        // Brain session so the next message loads the new Soul cleanly.
                        crate::chat_page::clear_desktop_chat_session();
                        refresh_soul_row(&soul_row);
                    }
                    Some(payload) => {
                        let message = payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .unwrap_or("Could not save your Sovereign's Soul.");
                        soul_row.set_subtitle(message);
                    }
                    None => {
                        soul_row.set_subtitle("Could not save your Sovereign's Soul.");
                    }
                }
            }
            dialog.close();
        });
        dialog.present(Some(parent));
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

        let dialog = adw::AlertDialog::builder()
            .heading("Reporting & Oversight")
            .close_response("cancel")
            .extra_child(&content)
            .build();
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("save", "Save");
        dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
        dialog.set_default_response(Some("save"));

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
                match run_bridge_action(
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
                ) {
                    Some(payload)
                        if payload.get("ok").and_then(|v| v.as_bool()) == Some(true) =>
                    {
                        refresh_oversight_row(&oversight_row);
                        refresh_autonomy_row(&autonomy_row);
                    }
                    Some(payload) => {
                        let message = payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .unwrap_or("Could not save oversight preferences.");
                        oversight_row.set_subtitle(message);
                    }
                    None => {
                        oversight_row.set_subtitle("Could not save oversight preferences.");
                    }
                }
            }
            dialog.close();
        });
        dialog.present(Some(parent));
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

        let dialog = adw::AlertDialog::builder()
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
        let row = row.clone();
        let parent_for_cb = parent.clone();
        dialog.connect_response(None, move |_dialog, response| {
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
                        let done = adw::AlertDialog::builder()
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
                        done.present(Some(&parent_for_cb));
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
        });
        dialog.present(Some(parent));
    }

    fn refresh_thinking_status(detail: &gtk::Label, settings_row: &adw::ActionRow) {
        // Auto refresh never live-probes providers (was ~12s cold start).
        // Explicit health Check uses refresh_thinking_status_inner(..., false).
        refresh_thinking_status_inner(detail, settings_row, true);
    }

    fn refresh_thinking_status_inner(
        detail: &gtk::Label,
        settings_row: &adw::ActionRow,
        skip_probe: bool,
    ) {
        let args: &[&str] = if skip_probe {
            &["status", "--skip-probe"]
        } else {
            &["status"]
        };
        let Some(response) = run_provider_command(args) else {
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
        let Some(response) = run_support_command(&["backups"]) else {
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

    fn decision_first_pref_path() -> std::path::PathBuf {
        std::path::PathBuf::from(crate::chat_page::resolve_centurion_home())
            .join("brain_decision_first")
    }

    fn load_decision_first_pref() -> bool {
        std::fs::read_to_string(decision_first_pref_path())
            .map(|s| s.trim() == "1" || s.trim().eq_ignore_ascii_case("true"))
            .unwrap_or(true)
    }

    fn save_decision_first_pref(enabled: bool) {
        let path = decision_first_pref_path();
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::write(path, if enabled { b"1\n" as &[u8] } else { b"0\n" });
    }

    fn refresh_gateway_ui(row: &adw::ActionRow, platform_list: &gtk::ListBox) {
        while let Some(child) = platform_list.first_child() {
            platform_list.remove(&child);
        }
        let Some(payload) = run_bridge_action("gateway_status", serde_json::json!({})) else {
            row.set_subtitle("Could not read gateway status.");
            return;
        };
        if payload.get("ok").and_then(|v| v.as_bool()) != Some(true) {
            row.set_subtitle(
                payload
                    .get("message")
                    .and_then(|v| v.as_str())
                    .unwrap_or("Gateway status unavailable."),
            );
            return;
        }
        let running = payload
            .pointer("/status/running")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let state = payload
            .pointer("/status/gateway_state")
            .and_then(|v| v.as_str())
            .unwrap_or(if running { "running" } else { "stopped" });
        row.set_subtitle(&format!(
            "{} — {}",
            if running { "Running" } else { "Stopped" },
            state
        ));
        let platforms = payload
            .pointer("/status/platforms")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        if platforms.is_empty() {
            platform_list.append(
                &adw::ActionRow::builder()
                    .title("No messaging platforms configured")
                    .subtitle("Use centurion setup or config.yaml to add Telegram/Discord/etc.")
                    .build(),
            );
            return;
        }
        for plat in platforms {
            let name = plat
                .get("name")
                .or_else(|| plat.get("label"))
                .and_then(|v| v.as_str())
                .unwrap_or("platform")
                .to_owned();
            let enabled = plat
                .get("enabled")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let connected = plat
                .get("connected")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let status = plat
                .get("status")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_owned();
            let plat_row = adw::ActionRow::builder()
                .title(&name)
                .subtitle(&format!(
                    "{}{}",
                    if connected { "Connected" } else { "Not connected" },
                    if status.is_empty() {
                        String::new()
                    } else {
                        format!(" · {status}")
                    }
                ))
                .build();
            let toggle = gtk::Switch::builder()
                .active(enabled)
                .valign(gtk::Align::Center)
                .build();
            let platform_name = name.clone();
            let list_for_cb = platform_list.clone();
            let status_row = row.clone();
            toggle.connect_active_notify(move |sw| {
                let _ = run_bridge_action(
                    "gateway_platform_set",
                    serde_json::json!({
                        "platform": platform_name,
                        "enabled": sw.is_active(),
                        "restart": true,
                    }),
                );
                let list_for_cb = list_for_cb.clone();
                let status_row = status_row.clone();
                glib::timeout_add_local_once(std::time::Duration::from_millis(400), move || {
                    refresh_gateway_ui(&status_row, &list_for_cb);
                });
            });
            plat_row.add_suffix(&toggle);
            platform_list.append(&plat_row);
        }
    }

    fn show_support_auto_fix_dialog(parent: &adw::ApplicationWindow) {
        let payload = run_bridge_action("support_auto_fix", serde_json::json!({}));
        let (heading, body) = match payload {
            Some(p) if p.get("ok").and_then(|v| v.as_bool()) == Some(true) => (
                "Auto-fix finished",
                p.get("message")
                    .and_then(|v| v.as_str())
                    .unwrap_or("Recovery steps completed.")
                    .to_owned(),
            ),
            Some(p) => (
                "Auto-fix could not finish",
                p.get("message")
                    .and_then(|v| v.as_str())
                    .unwrap_or("See health check for details.")
                    .to_owned(),
            ),
            None => (
                "Auto-fix unavailable",
                "Could not reach the support bridge.".to_owned(),
            ),
        };
        let dialog = adw::AlertDialog::builder()
            .heading(heading)
            .body(&body)
            .close_response("ok")
            .build();
        dialog.add_response("ok", "OK");
        dialog.present(Some(parent));
    }


    fn show_skills_tools_dialog(parent: &adw::ApplicationWindow) {
        let payload = run_bridge_action("tools_skills_snapshot", serde_json::json!({}));
        let body = match payload {
            Some(p) if p.get("ok").and_then(|v| v.as_bool()) == Some(true) => {
                let tools = p
                    .get("toolsets")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                let skills = p
                    .get("skills")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                let mut lines = vec![
                    "Enabled for this Brain (read-only). Changes take effect next session unless you use CLI --now.".to_owned(),
                    String::new(),
                    "Toolsets:".to_owned(),
                ];
                if tools.is_empty() {
                    lines.push("• (none listed)".to_owned());
                } else {
                    for t in tools.iter().take(40) {
                        let name = t.as_str().unwrap_or("?");
                        lines.push(format!("• {name}"));
                    }
                }
                lines.push(String::new());
                lines.push("Skills:".to_owned());
                if skills.is_empty() {
                    lines.push("• (none listed — bundled skills load as needed)".to_owned());
                } else {
                    for s in skills.iter().take(40) {
                        let name = s
                            .as_str()
                            .or_else(|| s.get("name").and_then(|v| v.as_str()))
                            .unwrap_or("?");
                        lines.push(format!("• {name}"));
                    }
                }
                lines.join("\n")
            }
            Some(p) => p
                .get("message")
                .and_then(|v| v.as_str())
                .unwrap_or("Could not list skills/tools.")
                .to_owned(),
            None => "Could not reach the bridge.".to_owned(),
        };
        let dialog = adw::AlertDialog::builder()
            .heading("Skills & tools")
            .body(&body)
            .close_response("close")
            .build();
        dialog.add_response("close", "Close");
        dialog.present(Some(parent));
    }

    fn show_license_dialog(parent: &adw::ApplicationWindow) {
        let payload = run_bridge_action("license_status", serde_json::json!({}));
        let can_redeem = payload
            .as_ref()
            .and_then(|p| p.get("ok").and_then(|v| v.as_bool()))
            == Some(true);
        let body = match &payload {
            Some(p) => {
                let enabled = p
                    .pointer("/status/enabled")
                    .or_else(|| p.get("enabled"))
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                if !enabled {
                    "License enforcement is off on this Brain (BYOK / contributor mode). No key required.".to_owned()
                } else {
                    let state = p
                        .pointer("/status/state")
                        .or_else(|| p.get("state"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("unknown");
                    let plan = p
                        .pointer("/status/plan")
                        .or_else(|| p.get("plan"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    let expires = p
                        .pointer("/status/expires_at")
                        .or_else(|| p.get("expires_at"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    let message = p
                        .get("message")
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    let mut lines = vec![format!("Status: {state}")];
                    if !plan.is_empty() {
                        lines.push(format!("Plan: {plan}"));
                    }
                    if !expires.is_empty() {
                        lines.push(format!("Expires: {expires}"));
                    }
                    if !message.is_empty() {
                        lines.push(message.to_owned());
                    }
                    lines.join("\n")
                }
            }
            None => "Could not read license status.".to_owned(),
        };
        let dialog = adw::AlertDialog::builder()
            .heading("License")
            .body(&body)
            .close_response("close")
            .build();
        dialog.add_response("close", "Close");
        if can_redeem
            && payload
                .as_ref()
                .and_then(|p| {
                    p.pointer("/status/enabled")
                        .or_else(|| p.get("enabled"))
                        .and_then(|v| v.as_bool())
                })
                .unwrap_or(false)
        {
            dialog.add_response("trial", "Start trial");
            dialog.add_response("activate", "Activate");
            dialog.add_response("redeem", "Redeem code");
        }
        dialog.add_response("fingerprint", "Machine id");
        let parent_for_cb = parent.clone();
        dialog.connect_response(None, move |_d, response| match response {
            "fingerprint" => {
                let result = run_bridge_action("license_fingerprint", serde_json::json!({}));
                let fp = result
                    .as_ref()
                    .and_then(|p| p.get("fingerprint").and_then(|v| v.as_str()))
                    .unwrap_or("(unavailable)")
                    .to_owned();
                let msg = format!(
                    "Share this machine id with support if they ask for it:\n\n{fp}"
                );
                if result
                    .as_ref()
                    .and_then(|p| p.get("ok").and_then(|v| v.as_bool()))
                    == Some(true)
                {
                    copy_text_to_clipboard(&fp);
                }
                let done = adw::AlertDialog::builder()
                    .heading("Machine id")
                    .body(&format!("{msg}\n\nCopied to clipboard when available."))
                    .close_response("ok")
                    .build();
                done.add_response("ok", "OK");
                done.present(Some(&parent_for_cb));
            }
            "trial" => {
                let result = run_bridge_action(
                    "license_activate",
                    serde_json::json!({ "tier": "trial", "days": 14 }),
                );
                let msg = result
                    .as_ref()
                    .and_then(|p| p.get("message").and_then(|v| v.as_str()))
                    .unwrap_or("Trial activation finished.")
                    .to_owned();
                let done = adw::AlertDialog::builder()
                    .heading("Trial")
                    .body(&msg)
                    .close_response("ok")
                    .build();
                done.add_response("ok", "OK");
                done.present(Some(&parent_for_cb));
            }
            "activate" | "redeem" => {
                let is_activate = response == "activate";
                let entry = gtk::Entry::builder()
                    .placeholder_text(if is_activate {
                        "Activation code"
                    } else {
                        "License or redeem code"
                    })
                    .hexpand(true)
                    .build();
                let redeem = adw::AlertDialog::builder()
                    .heading(if is_activate {
                        "Activate license"
                    } else {
                        "Redeem license"
                    })
                    .extra_child(&entry)
                    .close_response("cancel")
                    .default_response("ok")
                    .build();
                redeem.add_response("cancel", "Cancel");
                redeem.add_response("ok", if is_activate { "Activate" } else { "Redeem" });
                redeem.set_response_appearance("ok", adw::ResponseAppearance::Suggested);
                let parent_for_redeem = parent_for_cb.clone();
                let parent_for_present = parent_for_cb.clone();
                redeem.connect_response(None, move |_d, resp| {
                    if resp != "ok" {
                        return;
                    }
                    let code = entry.text().trim().to_string();
                    let result = if is_activate {
                        run_bridge_action(
                            "license_activate",
                            serde_json::json!({ "tier": "paid", "code": code }),
                        )
                    } else {
                        run_bridge_action(
                            "license_redeem",
                            serde_json::json!({ "token": code }),
                        )
                    };
                    let msg = result
                        .as_ref()
                        .and_then(|p| p.get("message").and_then(|v| v.as_str()))
                        .unwrap_or(if is_activate {
                            "Activation finished."
                        } else {
                            "Redeem finished."
                        })
                        .to_owned();
                    let done = adw::AlertDialog::builder()
                        .heading(if is_activate { "Activate" } else { "Redeem" })
                        .body(&msg)
                        .close_response("ok")
                        .build();
                    done.add_response("ok", "OK");
                    done.present(Some(&parent_for_redeem));
                });
                redeem.present(Some(&parent_for_present));
            }
            _ => {}
        });
        dialog.present(Some(parent));
    }

    fn show_beneficiary_dialog(parent: &adw::ApplicationWindow) {
        let snapshot = run_bridge_action("beneficiary_snapshot", serde_json::json!({}));
        let summary = match snapshot.as_ref().and_then(|p| p.get("snapshot")).or(snapshot.as_ref())
        {
            Some(s) => {
                let family = s
                    .get("family_beneficiary_first_name")
                    .or_else(|| s.pointer("/family/first_name"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let colleague = s
                    .get("colleague_note")
                    .or_else(|| s.get("colleague_email"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let mut lines = Vec::new();
                if family.is_empty() {
                    lines.push("No family beneficiary nominated yet.".to_owned());
                } else {
                    lines.push(format!("Family beneficiary: {family}"));
                }
                if !colleague.is_empty() {
                    lines.push(format!("Colleague referral: {colleague}"));
                }
                lines.join("\n")
            }
            None => "Could not load Family Beneficiary state.".to_owned(),
        };
        let first = gtk::Entry::builder()
            .placeholder_text("Family beneficiary first name")
            .hexpand(true)
            .build();
        let colleague = gtk::Entry::builder()
            .placeholder_text("Colleague referral note / email")
            .hexpand(true)
            .build();
        let form = gtk::Box::new(gtk::Orientation::Vertical, 8);
        form.append(
            &gtk::Label::builder()
                .label(&summary)
                .wrap(true)
                .xalign(0.0)
                .selectable(true)
                .build(),
        );
        form.append(&first);
        form.append(&colleague);
        let dialog = adw::AlertDialog::builder()
            .heading("Family Beneficiary")
            .body("Nominate a family member or record a colleague referral.")
            .extra_child(&form)
            .close_response("close")
            .build();
        dialog.add_response("close", "Close");
        dialog.add_response("family", "Save family");
        dialog.add_response("colleague", "Submit colleague");
        dialog.connect_response(None, move |_d, response| {
            match response {
                "family" => {
                    let name = first.text().trim().to_string();
                    let _ = run_bridge_action(
                        "beneficiary_set_family_member",
                        serde_json::json!({ "first_name": name }),
                    );
                }
                "colleague" => {
                    let note = colleague.text().trim().to_string();
                    let _ = run_bridge_action(
                        "beneficiary_submit_colleague",
                        serde_json::json!({ "note": note, "email": note }),
                    );
                }
                _ => {}
            }
        });
        dialog.present(Some(parent));
    }

    fn show_fleet_peer_dialog(parent: &adw::ApplicationWindow) {
        let form = gtk::Box::new(gtk::Orientation::Vertical, 8);
        let peers_box = gtk::Box::new(gtk::Orientation::Vertical, 6);
        if let Some(resp) = run_bridge_action("fleet_status", serde_json::json!({})) {
            if resp.get("ok").and_then(|v| v.as_bool()) == Some(true) {
                let peers = resp
                    .get("peers")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                if peers.is_empty() {
                    peers_box.append(
                        &gtk::Label::builder()
                            .label("No peers yet — add one below.")
                            .wrap(true)
                            .xalign(0.0)
                            .css_classes(["dim-label"])
                            .build(),
                    );
                } else {
                    for peer in peers.iter().take(12) {
                        let name = peer
                            .get("name")
                            .or_else(|| peer.get("id"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("peer");
                        let status = peer
                            .get("status")
                            .and_then(|v| v.as_str())
                            .unwrap_or("unknown");
                        let address = peer
                            .get("address")
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        let peer_id = peer
                            .get("id")
                            .or_else(|| peer.get("name"))
                            .and_then(|v| v.as_str())
                            .unwrap_or(name)
                            .to_owned();
                        let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                        row.append(
                            &gtk::Label::builder()
                                .label(&format!("{name} · {status}"))
                                .xalign(0.0)
                                .hexpand(true)
                                .wrap(true)
                                .build(),
                        );
                        if !address.is_empty() {
                            row.set_tooltip_text(Some(address));
                        }
                        let ping = gtk::Button::with_label("Ping");
                        ping.add_css_class("flat");
                        let parent_w = parent.clone();
                        ping.connect_clicked(move |_| {
                            let payload = run_bridge_action(
                                "fleet_ping",
                                serde_json::json!({ "peer_id": peer_id }),
                            );
                            let ok = payload
                                .as_ref()
                                .and_then(|p| p.get("ok").and_then(|v| v.as_bool()))
                                .unwrap_or(false);
                            let message = payload
                                .as_ref()
                                .and_then(|p| p.get("message").and_then(|v| v.as_str()))
                                .unwrap_or(if ok {
                                    "Ping sent."
                                } else {
                                    "Ping failed."
                                })
                                .to_owned();
                            let result = adw::AlertDialog::builder()
                                .heading(if ok { "Ping" } else { "Ping failed" })
                                .body(&message)
                                .close_response("ok")
                                .build();
                            result.add_response("ok", "OK");
                            result.present(Some(&parent_w));
                        });
                        row.append(&ping);
                        peers_box.append(&row);
                    }
                }
            }
        }
        form.append(&peers_box);
        form.append(
            &gtk::Label::builder()
                .label("Add a peer")
                .xalign(0.0)
                .css_classes(["heading"])
                .build(),
        );
        let id_entry = gtk::Entry::builder()
            .placeholder_text("Peer id (e.g. cent-002)")
            .hexpand(true)
            .build();
        let name_entry = gtk::Entry::builder()
            .placeholder_text("Display name (e.g. Eve)")
            .hexpand(true)
            .build();
        let address_entry = gtk::Entry::builder()
            .placeholder_text("Address (http://host:8642)")
            .hexpand(true)
            .build();
        let token_entry = gtk::PasswordEntry::builder()
            .placeholder_text("Shared FLEET_AUTH_TOKEN")
            .show_peek_icon(true)
            .hexpand(true)
            .build();
        form.append(&id_entry);
        form.append(&name_entry);
        form.append(&address_entry);
        form.append(&token_entry);
        let dialog = adw::AlertDialog::builder()
            .heading("Fleet peer")
            .body(
                "Peers and ping live here (moved off Focus). Add another Centurion’s \
LAN or public address and the shared fleet token.",
            )
            .extra_child(&form)
            .close_response("cancel")
            .default_response("save")
            .build();
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("save", "Save");
        dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
        let parent_for_result = parent.clone();
        dialog.connect_response(None, move |_d, response| {
            if response != "save" {
                return;
            }
            let peer_id = id_entry.text().trim().to_string();
            let name = name_entry.text().trim().to_string();
            let address = address_entry.text().trim().to_string();
            let token = token_entry.text().trim().to_string();
            let payload = run_bridge_action(
                "fleet_peer_put",
                serde_json::json!({
                    "peer_id": peer_id,
                    "name": name,
                    "address": address,
                    "auth_token": token,
                }),
            );
            let message = payload
                .as_ref()
                .and_then(|p| p.get("message").and_then(|v| v.as_str()))
                .unwrap_or("Could not save fleet peer.")
                .to_owned();
            let ok = payload
                .as_ref()
                .and_then(|p| p.get("ok").and_then(|v| v.as_bool()))
                .unwrap_or(false);
            let result = adw::AlertDialog::builder()
                .heading(if ok { "Peer saved" } else { "Could not save peer" })
                .body(&message)
                .close_response("ok")
                .build();
            result.add_response("ok", "OK");
            result.present(Some(&parent_for_result));
        });
        dialog.present(Some(parent));
    }

    fn show_ops_glance_dialog(parent: &adw::ApplicationWindow) {
        let body = match run_bridge_action("ops_glance", serde_json::json!({})) {
            Some(p) if p.get("ok").and_then(|v| v.as_bool()) == Some(true) => {
                let mut lines = Vec::new();
                let cron = p
                    .get("cron")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                let kanban = p
                    .get("kanban")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                if cron.is_empty() && kanban.is_empty() {
                    "No upcoming jobs or board tasks right now.\n\n\
Schedule work with cron or kanban; this glance stays in Settings, not Focus."
                        .to_owned()
                } else {
                    if !cron.is_empty() {
                        lines.push("Scheduled jobs".to_owned());
                        for job in cron.iter().take(20) {
                            let name = job
                                .get("name")
                                .and_then(|v| v.as_str())
                                .unwrap_or("(job)");
                            let next = job
                                .get("next_run")
                                .and_then(|v| v.as_str())
                                .unwrap_or("");
                            let schedule = job
                                .get("schedule")
                                .and_then(|v| v.as_str())
                                .unwrap_or("");
                            let detail = if !next.is_empty() {
                                format!("next {next}")
                            } else if !schedule.is_empty() {
                                schedule.to_owned()
                            } else {
                                "scheduled".to_owned()
                            };
                            lines.push(format!("• {name} — {detail}"));
                        }
                        lines.push(String::new());
                    }
                    if !kanban.is_empty() {
                        lines.push("Board".to_owned());
                        for task in kanban.iter().take(20) {
                            let title = task
                                .get("title")
                                .and_then(|v| v.as_str())
                                .unwrap_or("(task)");
                            let status = task
                                .get("status")
                                .and_then(|v| v.as_str())
                                .unwrap_or("");
                            lines.push(format!("• {title} — {status}"));
                        }
                    }
                    lines.join("\n")
                }
            }
            Some(p) => p
                .get("message")
                .and_then(|v| v.as_str())
                .unwrap_or("Could not load ops glance.")
                .to_owned(),
            None => "Could not reach the ops bridge.".to_owned(),
        };
        let dialog = adw::AlertDialog::builder()
            .heading("Scheduled & board")
            .body(&body)
            .close_response("close")
            .build();
        dialog.add_response("close", "Close");
        dialog.present(Some(parent));
    }

    fn show_plugins_list_dialog(parent: &adw::ApplicationWindow) {
        let payload = run_bridge_action("plugin_list", serde_json::json!({}));
        let body = match payload {
            Some(p) if p.get("ok").and_then(|v| v.as_bool()) == Some(true) => {
                let plugins = p
                    .get("plugins")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                if plugins.is_empty() {
                    "No plugins discovered yet.\n\n\
Agent plugins live under ~/.centurion/plugins and extend tools/hooks — \
they do not automatically add Brain UI. See developer-guide/client-plugins.md."
                        .to_owned()
                } else {
                    let mut lines = vec![
                        "Agent plugins on this Brain:".to_owned(),
                        String::new(),
                    ];
                    for plug in plugins.iter().take(40) {
                        let name = plug
                            .get("name")
                            .and_then(|v| v.as_str())
                            .unwrap_or("(unnamed)");
                        let kind = plug.get("kind").and_then(|v| v.as_str()).unwrap_or("");
                        let enabled = plug
                            .get("enabled")
                            .and_then(|v| v.as_bool())
                            .unwrap_or(false);
                        let state = if enabled { "on" } else { "off" };
                        lines.push(format!("• {name} [{kind}] — {state}"));
                    }
                    lines.push(String::new());
                    lines.push(
                        "Enabling a plugin for the agent does not add GTK panels yet."
                            .to_owned(),
                    );
                    lines.join("\n")
                }
            }
            Some(p) => p
                .get("message")
                .and_then(|v| v.as_str())
                .unwrap_or("Could not list plugins.")
                .to_owned(),
            None => "Could not reach the plugin bridge.".to_owned(),
        };
        let dialog = adw::AlertDialog::builder()
            .heading("Installed plugins")
            .body(&body)
            .close_response("close")
            .build();
        dialog.add_response("close", "Close");
        dialog.present(Some(parent));
    }

    fn show_backup_thinking_dialog(parent: &adw::ApplicationWindow, row: &adw::ActionRow) {
        let body = match run_support_command(&["backups"]) {
            Some(response) => {
                let backups = response
                    .result
                    .as_ref()
                    .and_then(|result| result.get("backups"))
                    .and_then(|value| value.as_array())
                    .cloned()
                    .unwrap_or_default();
                if backups.is_empty() {
                    "No backup thinking services are configured yet.\n\n\
                     Backups come from your fallback thinking chain in Centurion config. \
                     Set a primary service under How your Centurion thinks → Change, then ask your \
                     advisor to add fallbacks if you want automatic failover."
                        .to_owned()
                } else {
                    let mut lines = vec![
                        "These services stand by if your primary thinking service is unavailable:"
                            .to_owned(),
                        String::new(),
                    ];
                    for entry in &backups {
                        let label = entry
                            .get("label")
                            .and_then(|v| v.as_str())
                            .unwrap_or("Backup");
                        let provider = entry
                            .get("provider")
                            .and_then(|v| v.as_str())
                            .unwrap_or("?");
                        let model = entry.get("model").and_then(|v| v.as_str()).unwrap_or("?");
                        lines.push(format!("• {label} ({provider} / {model})"));
                    }
                    lines.join("\n")
                }
            }
            None => "Could not read backup thinking services. Is Centurion AI OS installed?"
                .to_owned(),
        };
        let dialog = adw::AlertDialog::builder()
            .heading("Backup Thinking Services")
            .body(&body)
            .close_response("close")
            .build();
        dialog.add_response("close", "Close");
        dialog.set_default_response(Some("close"));
        let row = row.clone();
        dialog.connect_response(None, move |dialog, _| {
            refresh_backup_thinking_services(&row);
            dialog.close();
        });
        dialog.present(Some(parent));
    }

    fn show_change_thinking_dialog(
        parent: &adw::ApplicationWindow,
        settings_row: &adw::ActionRow,
        detail: &gtk::Label,
    ) {
        show_change_thinking_dialog_inner(parent, settings_row, detail, None);
    }

    fn show_change_thinking_dialog_inner(
        parent: &adw::ApplicationWindow,
        settings_row: &adw::ActionRow,
        detail: &gtk::Label,
        initial_error: Option<String>,
    ) {
        let connectors_raw = run_provider_command(&["catalog"]);
        let active_connector_id = connectors_raw
            .as_ref()
            .and_then(|response| response.catalog.as_ref())
            .and_then(|catalog| catalog.get("active_connector_id"))
            .and_then(|value| value.as_str())
            .map(str::to_owned);
        let connectors: Vec<ThinkingConnectorOption> = connectors_raw
            .and_then(|response| response.catalog)
            .and_then(|catalog| {
                catalog
                    .get("text_models")
                    .and_then(|value| value.as_array())
                    .cloned()
            })
            .unwrap_or_default()
            .into_iter()
            .filter_map(|row| {
                let id = row.get("id")?.as_str()?.to_owned();
                let display_name = row
                    .get("display_name")
                    .and_then(|v| v.as_str())
                    .unwrap_or(id.as_str())
                    .to_owned();
                let needs_key = row
                    .get("needs_key")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(true);
                let best_for = row
                    .get("best_for")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_owned();
                Some(ThinkingConnectorOption {
                    id,
                    display_name,
                    needs_key,
                    best_for,
                })
            })
            .collect();

        if connectors.is_empty() {
            let dialog = adw::AlertDialog::builder()
                .heading("Change thinking service")
                .body("Could not load the curated thinking-service catalog. Is Centurion AI OS installed?")
                .close_response("ok")
                .build();
            dialog.add_response("ok", "OK");
            dialog.present(Some(parent));
            return;
        }

        let labels: Vec<&str> = connectors
            .iter()
            .map(|connector| connector.display_name.as_str())
            .collect();
        let service_drop = gtk::DropDown::from_strings(&labels);
        let mut initial = 0_u32;
        if let Some(active_id) = active_connector_id.as_deref() {
            if let Some(index) = connectors.iter().position(|c| c.id == active_id) {
                initial = index as u32;
            }
        } else {
            for (index, connector) in connectors.iter().enumerate() {
                // Prefer a row that already has an access code configured.
                if !connector.needs_key {
                    initial = index as u32;
                    break;
                }
            }
        }
        service_drop.set_selected(initial);

        let hint = gtk::Label::builder()
            .xalign(0.0)
            .wrap(true)
            .css_classes(["dim-label"])
            .build();
        let key_entry = gtk::PasswordEntry::builder()
            .placeholder_text("Access code from your thinking-service account")
            .show_peek_icon(true)
            .build();
        let key_label = gtk::Label::builder()
            .label("Access code")
            .xalign(0.0)
            .build();

        let update_hint = {
            let hint = hint.clone();
            let key_entry = key_entry.clone();
            let connectors = connectors.clone();
            Rc::new(move |selected: u32| {
                let Some(connector) = connectors.get(selected as usize) else {
                    return;
                };
                if connector.needs_key {
                    key_entry.set_placeholder_text(
                        Some("Access code from your thinking-service account"),
                    );
                    if connector.best_for.is_empty() {
                        hint.set_label(
                            "This service needs an access code saved on this brain.",
                        );
                    } else {
                        hint.set_label(&format!(
                            "{} — paste the access code below (saved only on this brain).",
                            connector.best_for
                        ));
                    }
                } else {
                    key_entry.set_placeholder_text(Some(
                        "Optional — paste a new access code to update",
                    ));
                    if connector.best_for.is_empty() {
                        hint.set_label("Access code already saved on this brain.");
                    } else {
                        hint.set_label(&format!(
                            "{} — access code already on this brain.",
                            connector.best_for
                        ));
                    }
                }
            })
        };
        update_hint(initial);
        service_drop.connect_selected_notify({
            let update_hint = Rc::clone(&update_hint);
            move |dropdown| update_hint(dropdown.selected())
        });

        let dialog = adw::AlertDialog::builder()
            .heading("Change thinking service")
            .body(
                "Pick a curated thinking service. Access codes are saved only on this brain — never kept on your iPhone.",
            )
            .close_response("cancel")
            .default_response("apply")
            .build();
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("apply", "Apply");
        dialog.set_response_appearance("apply", adw::ResponseAppearance::Suggested);

        let extra = gtk::Box::new(gtk::Orientation::Vertical, 8);
        let error_label = gtk::Label::builder()
            .label(initial_error.as_deref().unwrap_or(""))
            .xalign(0.0)
            .wrap(true)
            .css_classes(["error"])
            .visible(initial_error.is_some())
            .build();
        extra.append(&gtk::Label::builder().label("Service").xalign(0.0).build());
        extra.append(&service_drop);
        extra.append(&hint);
        extra.append(&key_label);
        extra.append(&key_entry);
        extra.append(&error_label);
        dialog.set_extra_child(Some(&extra));
        dialog.present(Some(parent));

        let settings_row = settings_row.clone();
        let detail = detail.clone();
        let parent = parent.clone();
        dialog.connect_response(None, move |dialog, response| {
            if response != "apply" {
                dialog.close();
                return;
            }
            // AlertDialog closes after a response — on failure, reopen
            // with the error so the owner can correct the access code without hunting Settings.
            let reopen_with_error = {
                let parent = parent.clone();
                let settings_row = settings_row.clone();
                let detail = detail.clone();
                move |message: String| {
                    glib::idle_add_local_once(move || {
                        show_change_thinking_dialog_inner(
                            &parent,
                            &settings_row,
                            &detail,
                            Some(message),
                        );
                    });
                }
            };

            let selected = service_drop.selected() as usize;
            let Some(connector) = connectors.get(selected) else {
                dialog.close();
                reopen_with_error("Pick a thinking service.".to_owned());
                return;
            };
            let access_code = key_entry.text().to_string();
            if connector.needs_key && access_code.trim().is_empty() {
                dialog.close();
                reopen_with_error("Access code is required for this thinking service.".to_owned());
                return;
            }
            if !access_code.trim().is_empty() {
                match run_provider_save_key(&connector.id, access_code.trim()) {
                    Some(save_response) if save_response.ok => {}
                    Some(save_response) => {
                        let message = save_response
                            .message
                            .unwrap_or_else(|| "Could not save access code.".to_owned());
                        dialog.close();
                        reopen_with_error(message);
                        return;
                    }
                    None => {
                        dialog.close();
                        reopen_with_error("Could not save access code.".to_owned());
                        return;
                    }
                }
            }
            if let Some(apply_response) =
                run_provider_command(&["apply-connector", &connector.id, "--json"])
            {
                let message = apply_response
                    .message
                    .or_else(|| {
                        apply_response.result.and_then(|value| {
                            value
                                .get("message")
                                .and_then(|m| m.as_str())
                                .map(str::to_owned)
                        })
                    })
                    .unwrap_or_else(|| {
                        if apply_response.ok {
                            "Thinking service updated.".to_owned()
                        } else {
                            "Could not apply thinking service change.".to_owned()
                        }
                    });
                if apply_response.ok {
                    settings_row.set_subtitle(&message);
                    refresh_thinking_status(&detail, &settings_row);
                    dialog.close();
                } else {
                    dialog.close();
                    reopen_with_error(message);
                }
            } else {
                dialog.close();
                reopen_with_error("Could not apply thinking service change.".to_owned());
            }
        });
    }

    fn show_get_help_dialog(
        parent: &adw::ApplicationWindow,
        thinking_settings_row: &adw::ActionRow,
        thinking_detail: &gtk::Label,
    ) {
        let health_body = if let Some(response) = run_support_command(&["health"]) {
            let ok = response.ok;
            response
                .message
                .or(response.summary)
                .filter(|text| !text.trim().is_empty())
                .unwrap_or_else(|| {
                    if ok {
                        "Health check completed.".to_owned()
                    } else {
                        "Health check could not complete.".to_owned()
                    }
                })
        } else {
            "Could not run health check. Is Centurion AI OS installed?".to_owned()
        };
        let dialog = adw::AlertDialog::builder()
            .heading("Get Help")
            .body(&format!(
                "{health_body}\n\nNext step: try auto-fix for common thinking/config issues, or open Fix Thinking Service to choose a provider and access code."
            ))
            .close_response("close")
            .default_response("autofix")
            .build();
        dialog.add_response("close", "Close");
        dialog.add_response("autofix", "Try auto-fix");
        dialog.add_response("fix", "Fix Thinking");
        dialog.set_response_appearance("autofix", adw::ResponseAppearance::Suggested);
        let parent_for_cb = parent.clone();
        let thinking_settings_row = thinking_settings_row.clone();
        let thinking_detail = thinking_detail.clone();
        dialog.connect_response(None, move |_d, response| match response {
            "autofix" => show_support_auto_fix_dialog(&parent_for_cb),
            "fix" => {
                show_change_thinking_dialog(&parent_for_cb, &thinking_settings_row, &thinking_detail)
            }
            _ => {}
        });
        dialog.present(Some(parent));
    }

    fn show_support_health_dialog(parent: &adw::ApplicationWindow) {
        let body = if let Some(response) = run_support_command(&["health"]) {
            let ok = response.ok;
            response
                .message
                .or(response.summary)
                .filter(|text| !text.trim().is_empty())
                .unwrap_or_else(|| {
                    if ok {
                        "Health check completed.".to_owned()
                    } else {
                        "Health check could not complete.".to_owned()
                    }
                })
        } else {
            "Could not run health check. Is Centurion AI OS installed?".to_owned()
        };
        let dialog = adw::AlertDialog::builder()
            .heading("Health Check")
            .body(&body)
            .close_response("ok")
            .build();
        dialog.add_response("ok", "OK");
        dialog.present(Some(parent));
    }

    fn show_support_bundle_dialog(parent: &adw::ApplicationWindow) {
        let (heading, body) = if let Some(response) = run_support_command(&["bundle"]) {
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
        let dialog = adw::AlertDialog::builder()
            .heading(&heading)
            .body(&body)
            .close_response("ok")
            .build();
        dialog.add_response("ok", "OK");
        dialog.present(Some(parent));
    }

    fn show_support_lookup_dialog(parent: &adw::ApplicationWindow) {
        let dialog = adw::AlertDialog::builder()
            .heading("Look Up Support Code")
            .body("Enter the support code from an iPhone or a previous bundle.")
            .close_response("cancel")
            .default_response("lookup")
            .build();
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("lookup", "Look Up");
        let code_entry = gtk::Entry::builder().placeholder_text("ABC-123").build();
        dialog.set_extra_child(Some(&code_entry));
        let parent = parent.clone();
        dialog.present(Some(&parent));

        dialog.connect_response(None, move |_dialog, response| {
            if response != "lookup" {
                return;
            }
            let code = code_entry.text().to_string();
            let result_dialog = match run_support_command(&["show", &code]) {
                Some(cli_response) if cli_response.ok => {
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
                    adw::AlertDialog::builder()
                        .heading(format!("Support Code {code}"))
                        .body(&body)
                        .close_response("ok")
                        .build()
                }
                Some(cli_response) => adw::AlertDialog::builder()
                    .heading("Support Code Not Found")
                    .body(
                        cli_response
                            .message
                            .unwrap_or_else(|| "That code is missing or has expired.".to_owned())
                            .as_str(),
                    )
                    .close_response("ok")
                    .build(),
                None => adw::AlertDialog::builder()
                    .heading("Support Code Not Found")
                    .body("That code is missing or has expired.")
                    .close_response("ok")
                    .build(),
            };
            result_dialog.add_response("ok", "OK");
            result_dialog.present(Some(&parent));
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
        thinking_detail: &gtk::Label,
    ) {
        let stack = stack.clone();
        let window = window.clone();
        let dialog_window = window.clone();
        let thinking_settings_row = thinking_settings_row.clone();
        let thinking_detail = thinking_detail.clone();
        let hooks = AdrianDialogHooks {
            build_context: Rc::new(build_adrian_context),
            on_action: Rc::new(move |action_id: &str| match action_id {
                "open_connect" => stack.set_visible_child_name("settings"),
                "open_get_help" => {
                    show_get_help_dialog(&window, &thinking_settings_row, &thinking_detail)
                }
                "try_auto_fix" => show_support_auto_fix_dialog(&window),
                "open_mission" => stack.set_visible_child_name("missions"),
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
