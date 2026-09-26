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
mod bridge_actions;
mod discuss;
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
#[allow(dead_code, unused_imports, clippy::too_many_lines)]
mod service_freshness;

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
    use std::sync::{Mutex, OnceLock};

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
                    "Sovereign AI Brain update available ({ver}) — tap Update below"
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

    fn you_page_box() -> gtk::Box {
        let page = gtk::Box::new(gtk::Orientation::Vertical, 16);
        page.set_margin_top(32);
        page.set_margin_start(32);
        page.set_margin_end(32);
        page.set_margin_bottom(32);
        page.set_vexpand(false);
        page.set_hexpand(true);
        page.set_valign(gtk::Align::Start);
        page
    }

    fn you_scroll_page(
        title: &str,
        tag: &str,
        child: &impl gtk::prelude::IsA<gtk::Widget>,
        show_back: bool,
    ) -> adw::NavigationPage {
        let scroll = gtk::ScrolledWindow::builder()
            .child(child)
            .vexpand(true)
            .hexpand(true)
            .hscrollbar_policy(gtk::PolicyType::Never)
            .vscrollbar_policy(gtk::PolicyType::Automatic)
            .kinetic_scrolling(true)
            .overlay_scrolling(false)
            .min_content_height(240)
            .build();
        let toolbar = adw::ToolbarView::new();
        if show_back {
            let header = adw::HeaderBar::new();
            // Keep the NavigationView back control — hiding start buttons
            // made Connect / You subpages look like a dead end.
            header.set_show_end_title_buttons(false);
            header.set_show_start_title_buttons(true);
            toolbar.add_top_bar(&header);
        }
        toolbar.set_content(Some(&scroll));
        adw::NavigationPage::with_tag(&toolbar, title, tag)
    }

    fn you_hub_link(title: &str, subtitle: &str, icon: &str) -> adw::ActionRow {
        let row = adw::ActionRow::builder()
            .title(title)
            .subtitle(subtitle)
            .icon_name(icon)
            .activatable(true)
            .build();
        let chevron = gtk::Image::from_icon_name("go-next-symbolic");
        chevron.add_css_class("dim-label");
        row.add_suffix(&chevron);
        row
    }

    fn bind_you_link(row: &adw::ActionRow, nav: &adw::NavigationView, tag: &'static str) {
        let nav_row = nav.clone();
        // ActionRow click emits `activated` (same as pairing). `activate` is
        // only the keyboard keybinding, so the hub rows looked dead.
        row.connect_activated(move |_| {
            nav_row.push_by_tag(tag);
        });
        // Suffix button is a second path — some GTK builds swallow row activation
        // when the hub lives outside a PreferencesPage.
        let open = gtk::Button::with_label("Open");
        open.set_valign(gtk::Align::Center);
        open.add_css_class("flat");
        open.set_size_request(64, 44);
        let nav_btn = nav.clone();
        open.connect_clicked(move |_| {
            nav_btn.push_by_tag(tag);
        });
        row.add_suffix(&open);
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
        signup_url: String,
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

            // iPhone pairing helper — optional. Brain Chat / Thinking use the
            // Python bridge + `centurion` CLI, not this binary. Get Brain used
            // to omit it; never fail the whole desk with ENOENT (os error 2).
            let Some(centurion_remote) = centurion_remote_bin() else {
                return Ok(());
            };

            let child = Command::new(&centurion_remote)
                .arg("serve")
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::inherit())
                .env(
                    "CENTURION_HOME",
                    crate::bridge_actions::resolve_centurion_home(),
                )
                .spawn()
                .map_err(|error| {
                    format!("Could not start the iPhone pairing helper: {error}")
                })?;
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

        application.connect_startup(|_| {
            load_brand_css();
            // Match .desktop Icon= / AppStream id so the dash and window
            // chrome use the Brain mark (not the generic missing-icon cog).
            gtk::Window::set_default_icon_name(APP_ID);
        });
        application.connect_activate(move |application| {
            // An upgrade replaces the files but does not restart the services
            // that are already in memory. Do that here rather than asking the
            // owner to reboot.
            crate::service_freshness::refresh_services_in_background(installed_version());
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
        // Paper & bronze — force dark so Chat / Settings match Mission Deck.
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
        let Some(bin) = centurion_remote_bin() else {
            return false;
        };
        let output = Command::new(bin).args(["devices", "--json"]).output();
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

    /// Path to the optional iPhone pairing helper. `None` when not installed —
    /// common for early Get Brain desktop-only packages. Never invent a bare
    /// `"centurion-remote"` name that fails spawn with ENOENT.
    fn centurion_remote_bin() -> Option<String> {
        if let Ok(home) = std::env::var("HOME") {
            let path = format!("{home}/.local/bin/centurion-remote");
            if PathBuf::from(&path).is_file() {
                return Some(path);
            }
        }
        which_on_path("centurion-remote").map(|p| p.to_string_lossy().into_owned())
    }

    fn which_on_path(name: &str) -> Option<PathBuf> {
        let path = std::env::var_os("PATH")?;
        for dir in std::env::split_paths(&path) {
            let candidate = dir.join(name);
            if candidate.is_file() {
                return Some(candidate);
            }
        }
        None
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
        let bin = centurion_remote_bin().ok_or_else(|| {
            "iPhone pairing helper is not installed yet. Re-run Install Brain from your Get Brain download, then try again.".to_owned()
        })?;

        let output = Command::new(bin)
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
        let Some(bin) = centurion_remote_bin() else {
            return;
        };
        let _ = Command::new(bin).args(["remote-revoke", id]).output();
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
                // Say why, in plain English. The helper's own sentence already
                // tells the owner what to do next; a flat "Could not …" made a
                // half-installed Brain look identical to a passing hiccup.
                let plain = if error.contains("not installed") || error.contains("Install Brain") {
                    error
                } else if error.contains("remote-pair failed") {
                    "Could not create a pairing code — the pairing helper on this brain \
refused. Try again in a moment; if it keeps happening, open Get Help and run a \
health check."
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
        std::path::PathBuf::from(crate::bridge_actions::resolve_centurion_home())
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

    fn smooth_transfer_pending_path() -> std::path::PathBuf {
        std::path::PathBuf::from(crate::bridge_actions::resolve_centurion_home())
            .join("smooth_transfer_pending")
    }

    fn smooth_transfer_seen_path() -> std::path::PathBuf {
        std::path::PathBuf::from(crate::bridge_actions::resolve_centurion_home())
            .join("smooth_transfer_seen")
    }

    fn smooth_transfer_pending() -> bool {
        smooth_transfer_pending_path().is_file() && !smooth_transfer_seen_path().is_file()
    }

    fn mark_smooth_transfer_seen() {
        let seen = smooth_transfer_seen_path();
        if let Some(parent) = seen.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::write(&seen, b"1\n");
        let _ = std::fs::remove_file(smooth_transfer_pending_path());
        // Avoid stacking the first-run Welcome ceremony after a Smooth Transfer.
        mark_brain_welcome_seen();
    }

    /// True when this Brain was installed from a Get Brain (Smooth Transfer)
    /// archive. `customer-install.sh` stamps `install: smooth-transfer` and
    /// `git_rev: smooth-transfer`; a real dev build (`install-user.sh`) writes
    /// neither. On smooth-transfer installs there is no checkout to update or
    /// rebuild from — updates arrive via the portal — so the in-app
    /// Check/Rebuild controls are hidden.
    fn is_smooth_transfer_install() -> bool {
        let stamp = std::path::PathBuf::from(crate::bridge_actions::resolve_centurion_home())
            .join("desktop-build.json");
        let Ok(text) = std::fs::read_to_string(&stamp) else {
            return false;
        };
        text.contains("\"install\": \"smooth-transfer\"")
            || text.contains("\"git_rev\": \"smooth-transfer\"")
    }

    /// Installed version: prefer the install stamp (the truth for the running
    /// Brain — e.g. a Get Brain archive stamped 5.2.116 whose binary was built
    /// from a 5.2.115 source tree), falling back to the baked binary version
    /// for dev builds with no stamp.
    fn installed_version() -> String {
        let stamp = std::path::PathBuf::from(crate::bridge_actions::resolve_centurion_home())
            .join("desktop-build.json");
        if let Ok(text) = std::fs::read_to_string(&stamp) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                if let Some(ver) = json.get("version").and_then(|v| v.as_str()) {
                    if !ver.is_empty() && ver != "unknown" {
                        return ver.to_owned();
                    }
                }
            }
        }
        env!("CARGO_PKG_VERSION").to_owned()
    }

    /// After Get Brain install.sh: confirm data was kept; do not rewrite Soul/Mission.
    fn show_transfer_complete_dialog(parent: &adw::ApplicationWindow) {
        let body = "Your Soul, chats, and settings are still on this machine.\n\n\
Open Chat to continue where you left off. Pair Sovereign AI Remote for iPhone \
with the QR on this desk (same Wi‑Fi). Linux Brain remains the desk product.";
        let dialog = adw::AlertDialog::builder()
            .heading("Transfer complete")
            .body(body)
            .close_response("continue")
            .default_response("continue")
            .build();
        dialog.add_response("continue", "Continue");
        dialog.set_response_appearance("continue", adw::ResponseAppearance::Suggested);
        dialog.connect_response(None, move |_d, _response| {
            mark_smooth_transfer_seen();
        });
        dialog.present(Some(parent));
    }

    /// First-run narrative: what a Centurion *is* (partner), not pairing theatre.
    ///
    /// This is the only orientation a new owner gets, so it names the two setup
    /// steps that make the Centurion theirs — and offers them from here rather
    /// than leaving them buried in Settings. Shaping the Sovereign first is what
    /// turns an appliance into a partner; a new owner who never finds it runs a
    /// stranger's Centurion.
    fn show_brain_welcome_dialog(parent: &adw::ApplicationWindow) {
        let body = "This computer is your Sovereign — a private partner that thinks with you, \
keeps your data here, and stays on your mission.\n\n\
Chat is the conversation. Focus is the command center: mission stack, Missions, and decisions. \
Settings is how you shape Soul, memory, and thinking.\n\n\
Two short interviews come first, and you can start either from here: Shape your Sovereign \\
(its story and values) and Mission Discovery (what you are building toward). Both also live \\
in Settings, under Soul and Focus. Everything else already works — your licence is on this \\
machine and nothing else needs setting up.
An iPhone remote is optional later — only when you want the Brain in your pocket. \
For now, sit here and meet your Centurion.";
        let dialog = adw::AlertDialog::builder()
            .heading("Welcome to your Centurion")
            .body(body)
            .close_response("begin")
            .default_response("begin")
            .build();
        dialog.add_response("begin", "Begin");
        dialog.add_response("shape", "Shape your Sovereign");
        dialog.add_response("pair", "Pair iPhone later");
        dialog.set_response_appearance("shape", adw::ResponseAppearance::Suggested);
        let parent_for_pair = parent.clone();
        let parent_for_shape = parent.clone();
        dialog.connect_response(None, move |_d, response| {
            mark_brain_welcome_seen();
            if response == "pair" {
                show_pairing_qr_window(&parent_for_pair);
            } else if response == "shape" {
                crate::interviews::show_soul_interview(&parent_for_shape, Rc::new(|| {}));
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
                .label("On your iPhone, open Sovereign AI Remote (same Wi‑Fi) → Scan this code")
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
        let addresses = discover_link_addresses();
        apply_link_addresses(container, parent, &addresses);
    }

    /// Render the static copy immediately, then fill the LAN row once interface
    /// discovery (which shells out) finishes on a worker.
    fn refresh_link_addresses_async(
        container: &gtk::Box,
        parent: Option<&adw::ApplicationWindow>,
    ) {
        apply_link_addresses(container, parent, &LinkAddresses::default());
        let container = container.clone();
        let parent = parent.cloned();
        let (tx, rx) = std::sync::mpsc::channel::<LinkAddresses>();
        std::thread::spawn(move || {
            let _ = tx.send(discover_link_addresses());
        });
        glib::timeout_add_local(std::time::Duration::from_millis(40), move || {
            match rx.try_recv() {
                Ok(addresses) => {
                    apply_link_addresses(&container, parent.as_ref(), &addresses);
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            }
        });
    }

    fn apply_link_addresses(
        container: &gtk::Box,
        parent: Option<&adw::ApplicationWindow>,
        addresses: &LinkAddresses,
    ) {
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
                    "Pair Sovereign AI Remote for iPhone with the QR on this desk (same Wi‑Fi). \
The Brain here is the product; the phone is the remote.",
                )
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );

        let link = gtk::Button::with_label("Show pairing QR");
        // Outline by default — Updates (above Status) owns the solid primary CTA.
        link.set_margin_top(4);
        if let Some(parent) = parent {
            let parent = parent.clone();
            link.connect_clicked(move |_| show_pairing_qr_window(&parent));
        } else {
            link.set_sensitive(false);
        }
        container.append(&link);

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
                    "Away-from-home chat: turn on Settings → Chat from anywhere after pairing. Same App Store app; no router setup for Unbox.",
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
        refresh_link_addresses_async(&link_addresses, None);
        status_card.append(&link_addresses);

        status_card.append(&thinking_title);
        status_card.append(&thinking_detail);

        let restart = gtk::Button::with_label("Restart desk link");
        restart.set_tooltip_text(Some(
            "Restarts the optional iPhone pairing helper. Chat and Thinking do not need this.",
        ));
        // Outline — desk restart is secondary to checking for Brain updates.
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
                .hexpand(true)
                .build(),
        );
        let refresh_devices_button = gtk::Button::from_icon_name("view-refresh-symbolic");
        refresh_devices_button.set_tooltip_text(Some("Refresh devices"));
        devices_heading.append(&refresh_devices_button);
        devices_section.append(&devices_heading);
        devices_section.append(
            &gtk::Label::builder()
                .label(
                    "Show the pairing QR anytime to link Sovereign AI Remote on the same Wi‑Fi. Approve under Connected Devices below — nothing is wrong if no phone is linked yet.",
                )
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );
        let device_list = gtk::ListBox::new();
        device_list.add_css_class("boxed-list");
        let devices_fp = Rc::new(RefCell::new(String::new()));
        refresh_devices_async(&device_list, &devices_fp);
        let refresh_list = device_list.clone();
        let refresh_fp = devices_fp.clone();
        refresh_devices_button.connect_clicked(move |_| {
            refresh_fp.borrow_mut().clear();
            refresh_devices_async(&refresh_list, &refresh_fp);
        });
        devices_section.append(&device_list);

        let settings = gtk::Box::new(gtk::Orientation::Vertical, 16);
        settings.set_margin_top(32);
        settings.set_margin_start(32);
        settings.set_margin_end(32);
        settings.set_margin_bottom(32);
        settings.append(
            &gtk::Label::builder()
                .label("You")
                .css_classes(["title-1"])
                .xalign(0.0)
                .build(),
        );
        let hub_pair_button = gtk::Button::with_label("Pair Remote");
        hub_pair_button.add_css_class("suggested-action");
        hub_pair_button.set_halign(gtk::Align::Start);
        hub_pair_button.set_size_request(-1, 44);
        hub_pair_button.set_tooltip_text(Some(
            "Show the pairing QR for Sovereign AI Remote on the same Wi‑Fi.",
        ));
        settings.append(&hub_pair_button);

        let settings_attention_banner = gtk::Box::new(gtk::Orientation::Vertical, 4);
        settings_attention_banner.add_css_class("centurion-attention-banner");
        settings_attention_banner.set_visible(false);
        settings.append(&settings_attention_banner);

        // Shared map with iPhone You: You → Your Sovereign → Connect → This Brain →
        // Collaborations → Family & friends → Privacy & Trust → Help & about.
        // Smooth Transfer (Get Brain) installs have no checkout to update or
        // rebuild from — updates arrive via the portal. Keep the row (it shows
        // the installed version) but drop the Check/Rebuild controls.
        let smooth_transfer_install = is_smooth_transfer_install();
        let installed_version = installed_version();
        let connect_group = adw::PreferencesGroup::builder()
            .title("Connect")
            .description("Pair Sovereign AI Remote on the same Wi‑Fi")
            .build();
        let this_brain_group = adw::PreferencesGroup::builder()
            .title("This Brain")
            .description(if smooth_transfer_install {
                "Installed from a Get Brain download — newer versions arrive through your portal"
            } else {
                "Updates, gateway, Anywhere, and desk tools"
            })
            .build();
        let update_row = adw::ActionRow::builder()
            .title(&format!("Sovereign AI Brain {installed_version}"))
            .subtitle(if smooth_transfer_install {
                "Updates arrive through Account → Get Brain on the portal"
            } else {
                "Check for a newer build, or rebuild from the Centurion folder on this computer"
            })
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
        // Outline until an update is available — then solid suggested-action.
        style_update_cta_button(&update_check_button, false);
        update_check_button.set_valign(gtk::Align::Center);
        let rebuild_screen_button = gtk::Button::with_label("Rebuild");
        rebuild_screen_button.set_tooltip_text(Some(
            "Rebuild Sovereign AI Brain from the Centurion folder on this computer (does not need an iPhone).",
        ));
        rebuild_screen_button.set_valign(gtk::Align::Center);
        if smooth_transfer_install {
            update_check_button.set_visible(false);
            rebuild_screen_button.set_visible(false);
        }
        update_row.add_suffix(&rebuild_screen_button);
        update_row.add_suffix(&update_check_button);
        let pairing_settings_row = adw::ActionRow::builder()
            .title("Remote pairing")
            .subtitle(
                "Show the pairing QR anytime to link Sovereign AI Remote on the same Wi‑Fi. Approve under Connected Devices below.",
            )
            .icon_name("network-wireless-symbolic")
            .activatable(true)
            .build();
        let pairing_qr_button = gtk::Button::with_label("Show QR");
        pairing_qr_button.add_css_class("suggested-action");
        pairing_qr_button.set_valign(gtk::Align::Center);
        pairing_qr_button.set_size_request(-1, 44);
        pairing_settings_row.add_suffix(&pairing_qr_button);
        connect_group.add(&pairing_settings_row);

        // --- You: person, mission, soul ---
        let you_group = adw::PreferencesGroup::builder()
            .title("You")
            .description("Life Mission, Soul, and how much freedom your Centurion has")
            .build();
        let sovereign_group = adw::PreferencesGroup::builder()
            .title("Your Sovereign")
            .description("How your Centurion thinks, remembers, and reports back")
            .build();
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
        sovereign_group.add(&thinking_settings_row);
        let backup_thinking_row = adw::ActionRow::builder()
            .title("Backup Thinking Services")
            .subtitle("No backup thinking services configured.")
            .icon_name("view-list-symbolic")
            .build();
        sovereign_group.add(&backup_thinking_row);

        let life_mission_row = adw::ActionRow::builder()
            .title("Life Mission")
            .subtitle("What you're building toward — shown on Focus; edit here.")
            .icon_name("emblem-favorite-symbolic")
            .build();
        let life_mission_edit_button = gtk::Button::with_label("Edit");
        life_mission_edit_button.set_valign(gtk::Align::Center);
        life_mission_row.add_suffix(&life_mission_edit_button);
        you_group.add(&life_mission_row);
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
        let autonomy_row = adw::ActionRow::builder()
            .title("Autonomy Level")
            .subtitle("Balanced (default) — follow with light interpretation")
            .icon_name("preferences-desktop-symbolic")
            .build();
        let autonomy_button = gtk::Button::with_label("Adjust");
        autonomy_button.set_valign(gtk::Align::Center);
        autonomy_row.add_suffix(&autonomy_button);
        you_group.add(&autonomy_row);
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

        let memory_horizon_row = adw::ActionRow::builder()
            .title("Memory Horizon")
            .subtitle("How your Centurion remembers — Hot Cache, Session Recall, Vault")
            .icon_name("view-grid-symbolic")
            .build();
        let memory_horizon_button = gtk::Button::with_label("View");
        memory_horizon_button.set_valign(gtk::Align::Center);
        memory_horizon_row.add_suffix(&memory_horizon_button);
        sovereign_group.add(&memory_horizon_row);
        settings.append(&you_group);

        let collaborations_group = adw::PreferencesGroup::builder()
            .title("Collaborations")
            .description("Boards on this Brain, and linking to another Centurion over your network")
            .build();
        let family_group = adw::PreferencesGroup::builder()
            .title("Family &amp; friends")
            .description("Nominate family and track colleague referrals")
            .build();
        family_group.set_visible(false);
        let privacy_group = adw::PreferencesGroup::builder()
            .title("Privacy &amp; Trust")
            .description("What stays on this computer, and how partnership works")
            .build();
        let oversight_row = adw::ActionRow::builder()
            .title("Reporting &amp; Oversight")
            .subtitle("Report cadence and confirmation preferences")
            .icon_name("eye-open-negative-filled-symbolic")
            .build();
        let oversight_button = gtk::Button::with_label("Adjust");
        oversight_button.set_valign(gtk::Align::Center);
        oversight_row.add_suffix(&oversight_button);
        sovereign_group.add(&oversight_row);
        let privacy_row = adw::ActionRow::builder()
            .title("Privacy &amp; Trust")
            .subtitle("What stays on this computer, and how partnership works")
            .icon_name("security-high-symbolic")
            .activatable(true)
            .build();
        privacy_group.add(&privacy_row);

        let pulse_pref_row = adw::ActionRow::builder()
            .title("Prefer Focus on decisions")
            .subtitle("Open Focus when something needs your attention")
            .icon_name("emblem-important-symbolic")
            .build();
        let pulse_pref_switch = gtk::Switch::builder().valign(gtk::Align::Center).build();
        pulse_pref_switch.set_active(load_decision_first_pref());
        pulse_pref_row.add_suffix(&pulse_pref_switch);
        privacy_group.add(&pulse_pref_row);
        // Orphaned vs Mission Deck routing — hide from customer Settings.
        pulse_pref_row.set_visible(false);

        // --- Messaging & research ---
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
        this_brain_group.add(&gateway_row);
        let gateway_platform_list = gtk::ListBox::new();
        gateway_platform_list.add_css_class("boxed-list");
        gateway_platform_list.set_margin_bottom(8);

        let anywhere_row = adw::ActionRow::builder()
            .title("Anywhere")
            .subtitle("Checking…")
            .icon_name("network-wireless-symbolic")
            .build();
        let anywhere_switch = gtk::Switch::builder().valign(gtk::Align::Center).build();
        anywhere_row.add_suffix(&anywhere_switch);
        this_brain_group.add(&anywhere_row);

        // Refresh Anywhere switch off the UI thread.
        {
            let anywhere_row = anywhere_row.clone();
            let anywhere_switch = anywhere_switch.clone();
            let (tx, rx) = std::sync::mpsc::channel::<(bool, String)>();
            std::thread::spawn(move || {
                let resp = run_bridge_action(
                    "remote_relay_status",
                    serde_json::json!({}),
                );
                let (enabled, subtitle) = anywhere_relay_subtitle(resp.as_ref());
                let _ = tx.send((enabled, subtitle));
            });
            glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
                match rx.try_recv() {
                    Ok((enabled, subtitle)) => {
                        anywhere_switch.set_active(enabled);
                        anywhere_row.set_subtitle(&subtitle);
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                }
            });
        }
        {
            let anywhere_row = anywhere_row.clone();
            let anywhere_switch = anywhere_switch.clone();
            anywhere_switch.connect_state_set(move |switch, state| {
                let anywhere_row = anywhere_row.clone();
                let switch = switch.clone();
                let action = if state {
                    "remote_relay_enable"
                } else {
                    "remote_relay_disable"
                };
                let (tx, rx) = std::sync::mpsc::channel::<Result<(bool, String), String>>();
                std::thread::spawn(move || {
                    let resp = run_bridge_action(action, serde_json::json!({}));
                    let ok = resp
                        .as_ref()
                        .and_then(|v| v.get("ok"))
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false);
                    if !ok {
                        let msg = resp
                            .as_ref()
                            .and_then(|v| v.get("message").or_else(|| v.get("error")))
                            .and_then(|v| v.as_str())
                            .unwrap_or("Could not update Anywhere.")
                            .to_owned();
                        let _ = tx.send(Err(msg));
                        return;
                    }
                    let (enabled, subtitle) = anywhere_relay_subtitle(resp.as_ref());
                    let _ = tx.send(Ok((enabled, subtitle)));
                });
                glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
                    match rx.try_recv() {
                        Ok(Ok((enabled, subtitle))) => {
                            switch.set_active(enabled);
                            anywhere_row.set_subtitle(&subtitle);
                            glib::ControlFlow::Break
                        }
                        Ok(Err(msg)) => {
                            switch.set_active(!state);
                            anywhere_row.set_subtitle(&msg);
                            glib::ControlFlow::Break
                        }
                        Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                        Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                            switch.set_active(!state);
                            glib::ControlFlow::Break
                        }
                    }
                });
                glib::Propagation::Stop
            });
        }

        let firecrawl_row = adw::ActionRow::builder()
            .title("Firecrawl")
            .subtitle("Checking…")
            .icon_name("system-search-symbolic")
            .build();
        let firecrawl_button = gtk::Button::with_label("Add key");
        firecrawl_button.set_tooltip_text(Some(
            "Save a Firecrawl API key on this brain for research-heavy web search and scraping.",
        ));
        firecrawl_button.add_css_class("suggested-action");
        firecrawl_button.set_valign(gtk::Align::Center);
        firecrawl_row.add_suffix(&firecrawl_button);
        this_brain_group.add(&firecrawl_row);

        let fleet_peer_row = adw::ActionRow::builder()
            .title("Connect another Centurion")
            .subtitle("Link two Centurions on the same network so they can work together.")
            .icon_name("network-server-symbolic")
            .build();
        let fleet_peer_button = gtk::Button::with_label("Connect");
        fleet_peer_button.set_valign(gtk::Align::Center);
        fleet_peer_row.add_suffix(&fleet_peer_button);
        this_brain_group.add(&fleet_peer_row);
        let plugins_row = adw::ActionRow::builder()
            .title("Installed plugins")
            .subtitle("View only — agent plugins already on this Brain.")
            .icon_name("application-x-addon-symbolic")
            .build();
        let plugins_button = gtk::Button::with_label("View");
        plugins_button.set_valign(gtk::Align::Center);
        plugins_row.add_suffix(&plugins_button);
        this_brain_group.add(&plugins_row);
        let ops_row = adw::ActionRow::builder()
            .title("Scheduled &amp; board")
            .subtitle("View only — next cron jobs and board glance.")
            .icon_name("view-list-symbolic")
            .build();
        let ops_button = gtk::Button::with_label("View");
        ops_button.set_valign(gtk::Align::Center);
        ops_row.add_suffix(&ops_button);
        this_brain_group.add(&ops_row);
        let collab_connect_row = adw::ActionRow::builder()
            .title("Collaborations")
            .subtitle(
                "The instrument: what has been struck, what is in hand and by whom, and what is waiting on you. Open it to decide; boards, pairing and invite are one tap inside.",
            )
            .icon_name("system-users-symbolic")
            .build();
        let collab_connect_button = gtk::Button::with_label("Open");
        collab_connect_button.add_css_class("suggested-action");
        collab_connect_button.set_valign(gtk::Align::Center);
        collab_connect_row.add_suffix(&collab_connect_button);
        collaborations_group.add(&collab_connect_row);

        let help_group = adw::PreferencesGroup::builder()
            .title("Help &amp; about")
            .description("Health checks, support codes, and Talk to Adrian")
            .build();
        let skills_row = adw::ActionRow::builder()
            .title("Skills &amp; tools")
            .subtitle("Self-built trusted · hub is inspiration only")
            .icon_name("applications-engineering-symbolic")
            .build();
        let skills_button = gtk::Button::with_label("Open");
        skills_button.set_valign(gtk::Align::Center);
        skills_row.add_suffix(&skills_button);
        this_brain_group.add(&skills_row);
        let license_row = adw::ActionRow::builder()
            .title("License")
            .subtitle("Product entitlement for this Brain")
            .icon_name("dialog-password-symbolic")
            .build();
        let license_button = gtk::Button::with_label("Status");
        license_button.set_valign(gtk::Align::Center);
        license_row.add_suffix(&license_button);
        // Entitlement is a bridge round-trip — stay hidden until the deferred
        // Settings fill answers, so build_window never blocks on it.
        license_row.set_visible(false);
        this_brain_group.add(&license_row);
        let beneficiary_row = adw::ActionRow::builder()
            .title("Family Beneficiary")
            .subtitle("Nominate family and track colleague referrals")
            .icon_name("avatar-default-symbolic")
            .build();
        let beneficiary_button = gtk::Button::with_label("Open");
        beneficiary_button.set_valign(gtk::Align::Center);
        beneficiary_row.add_suffix(&beneficiary_button);
        beneficiary_row.set_visible(false);
        family_group.add(&beneficiary_row);

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
        this_brain_group.add(&telegram_history_row);
        this_brain_group.add(&update_row);

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
        help_group.add(&support_health_row);
        help_group.add(&fix_thinking_row);
        help_group.add(&auto_fix_row);
        help_group.add(&support_bundle_row);
        help_group.add(&support_lookup_row);

        let adrian_row = adw::ActionRow::builder()
            .title("Talk to Adrian")
            .subtitle("Mission-first guidance from Centurion's creator — over the internet")
            .icon_name("avatar-default-symbolic")
            .build();
        let adrian_button = gtk::Button::with_label("Open");
        adrian_button.set_valign(gtk::Align::Center);
        adrian_row.add_suffix(&adrian_button);
        help_group.add(&adrian_row);

        let hub_menu = adw::PreferencesGroup::builder().build();
        let sovereign_link = you_hub_link(
            "Your Sovereign",
            "Thinking, memory, reporting",
            "preferences-system-symbolic",
        );
        let collab_link = you_hub_link(
            "Collaborations",
            "Shared work boards on this Brain",
            "system-users-symbolic",
        );
        let family_hub_row = you_hub_link(
            "Family &amp; friends",
            "Nominate family and track colleague referrals",
            "avatar-default-symbolic",
        );
        family_hub_row.set_visible(false);
        let connect_link = you_hub_link(
            "Connect",
            "Pairing, devices, and link status",
            "network-wireless-symbolic",
        );
        let this_brain_link = you_hub_link(
            "This Brain",
            "Gateway, updates, desk",
            "video-display-symbolic",
        );
        let privacy_link = you_hub_link(
            "Privacy &amp; Trust",
            "What stays on this computer",
            "security-high-symbolic",
        );
        let help_link = you_hub_link(
            "Help &amp; about",
            "Health checks, support, Talk to Adrian",
            "dialog-information-symbolic",
        );
        hub_menu.add(&sovereign_link);
        hub_menu.add(&collab_link);
        hub_menu.add(&family_hub_row);
        hub_menu.add(&connect_link);
        hub_menu.add(&this_brain_link);
        hub_menu.add(&privacy_link);
        hub_menu.add(&help_link);
        settings.append(&hub_menu);

        let sovereign_page = you_page_box();
        sovereign_page.append(&sovereign_group);
        let connect_page = you_page_box();
        connect_page.append(&connect_group);
        connect_page.append(&status_card);
        connect_page.append(&devices_section);
        let this_brain_page = you_page_box();
        this_brain_page.append(&this_brain_group);
        this_brain_page.append(&gateway_platform_list);
        let collab_page = you_page_box();
        collab_page.append(&collaborations_group);
        let family_page = you_page_box();
        family_page.append(&family_group);
        let privacy_page = you_page_box();
        privacy_page.append(&privacy_group);
        let help_page = you_page_box();
        help_page.append(&help_group);

        settings.set_vexpand(false);
        settings.set_hexpand(true);
        settings.set_valign(gtk::Align::Start);

        let you_nav = adw::NavigationView::new();
        you_nav.set_vexpand(true);
        you_nav.set_hexpand(true);
        you_nav.add(&you_scroll_page("You", "hub", &settings, false));
        you_nav.add(&you_scroll_page(
            "Your Sovereign",
            "sovereign",
            &sovereign_page,
            true,
        ));
        you_nav.add(&you_scroll_page(
            "Collaborations",
            "collaborations",
            &collab_page,
            true,
        ));
        you_nav.add(&you_scroll_page(
            "Family & friends",
            "family",
            &family_page,
            true,
        ));
        you_nav.add(&you_scroll_page("Connect", "connect", &connect_page, true));
        you_nav.add(&you_scroll_page(
            "This Brain",
            "this-brain",
            &this_brain_page,
            true,
        ));
        you_nav.add(&you_scroll_page(
            "Privacy & Trust",
            "privacy",
            &privacy_page,
            true,
        ));
        you_nav.add(&you_scroll_page("Help & about", "help", &help_page, true));
        bind_you_link(&sovereign_link, &you_nav, "sovereign");
        bind_you_link(&collab_link, &you_nav, "collaborations");
        bind_you_link(&family_hub_row, &you_nav, "family");
        bind_you_link(&connect_link, &you_nav, "connect");
        bind_you_link(&this_brain_link, &you_nav, "this-brain");
        bind_you_link(&privacy_link, &you_nav, "privacy");
        bind_you_link(&help_link, &you_nav, "help");
        let settings_scroll = you_nav;

        let stack = gtk::Stack::builder()
            .transition_type(gtk::StackTransitionType::Crossfade)
            .transition_duration(80)
            .vexpand(true)
            .hexpand(true)
            .build();

        let attention_sink: Rc<RefCell<Rc<dyn Fn(u32)>>> =
            Rc::new(RefCell::new(Rc::new(|_: u32| {})));
        let collab_attention_sink: Rc<RefCell<Rc<dyn Fn(u32)>>> =
            Rc::new(RefCell::new(Rc::new(|_: u32| {})));
        let (home, home_handle) = {
            let attention_sink_for_hooks = attention_sink.clone();
            // Mission Deck (React / WebKit) replaces the legacy GTK Missions surface.
            crate::mission_deck_page::build(crate::home_page::HomeHooks {
                // Chat was removed from the Brain in v6.0.0. The deck still emits
                // its "discuss" affordance; it is intentionally inert for now.
                on_ask_about: Rc::new(|_topic: crate::discuss::DiscussTopic, _kickoff: String| {}),
                on_attention_changed: Rc::new(move |n: u32| {
                    (attention_sink_for_hooks.borrow())(n);
                }),
            })
        };

        let (collab, collab_handle) = {
            let collab_attention_sink = collab_attention_sink.clone();
            crate::mission_deck_page::build_collab(crate::home_page::HomeHooks {
                on_ask_about: Rc::new(|_topic: crate::discuss::DiscussTopic, _kickoff: String| {}),
                on_attention_changed: Rc::new(move |n: u32| {
                    (collab_attention_sink.borrow())(n);
                }),
            })
        };

        stack.add_titled(&home, Some("missions"), "Focus");
        stack.add_titled(&collab, Some("collab"), "Conjunction");
        stack.add_titled(&settings_scroll, Some("settings"), "You");
        stack.set_visible_child_name("missions");
        home.set_vexpand(true);
        collab.set_vexpand(true);
        settings_scroll.set_vexpand(true);
        settings_scroll.set_hexpand(true);

        let (tab_bar, tab_badges_ui) = build_attention_tab_bar(
            &stack,
            &[
                ("missions", "Focus"),
                ("collab", "Conjunction"),
                ("settings", "You"),
            ],
        );

        let refresh_settings_attention_ui = {
            let banner = settings_attention_banner.clone();
            let thinking_settings_row = thinking_settings_row.clone();
            let thinking_attention_mark = thinking_attention_mark.clone();
            let fix_thinking_row = fix_thinking_row.clone();
            let update_row = update_row.clone();
            let update_attention_mark = update_attention_mark.clone();
            let update_check_button = update_check_button.clone();
            Rc::new(move |items: Vec<SettingsAttentionItem>| {
                rebuild_settings_attention_banner(&banner, &items);
                let thinking = items
                    .iter()
                    .any(|i| matches!(i, SettingsAttentionItem::Thinking { .. }));
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
                update_attention_mark.set_visible(update);
                style_update_cta_button(&update_check_button, update);
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
        let refresh_collab_badge = {
            let tab_badges_ui = tab_badges_ui.clone();
            let collab_handle = collab_handle.clone();
            Rc::new(move || {
                let n = collab_handle.attention_count();
                if n > 0 {
                    tab_badges_ui.set_badge("collab", Some(&n.to_string()));
                } else {
                    tab_badges_ui.set_badge("collab", None);
                }
            }) as Rc<dyn Fn()>
        };
        let apply_settings_badge = {
            let tab_badges_ui = tab_badges_ui.clone();
            let refresh_settings_attention_ui = refresh_settings_attention_ui.clone();
            let attention_fp = Rc::new(RefCell::new(String::new()));
            Rc::new(move |items: Vec<SettingsAttentionItem>| {
                let fp = format!("{items:?}");
                if *attention_fp.borrow() == fp {
                    return;
                }
                *attention_fp.borrow_mut() = fp;
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
        let refresh_stack_badges = {
            let refresh_home_badge = refresh_home_badge.clone();
            let refresh_collab_badge = refresh_collab_badge.clone();
            let refresh_settings_badge = refresh_settings_badge.clone();
            Rc::new(move || {
                refresh_home_badge();
                refresh_collab_badge();
                refresh_settings_badge();
            }) as Rc<dyn Fn()>
        };
        *attention_sink.borrow_mut() = {
            let refresh_home_badge = refresh_home_badge.clone();
            Rc::new(move |_n: u32| {
                refresh_home_badge();
            })
        };
        *collab_attention_sink.borrow_mut() = {
            let refresh_collab_badge = refresh_collab_badge.clone();
            Rc::new(move |_n: u32| {
                refresh_collab_badge();
            })
        };
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

        // One bundle so every Settings fill is a single worker pass.
        let settings_rows = SettingsRows {
            thinking_detail: thinking_detail.clone(),
            thinking_row: thinking_settings_row.clone(),
            backup_row: backup_thinking_row.clone(),
            autonomy_row: autonomy_row.clone(),
            soul_row: soul_row.clone(),
            memory_horizon_row: memory_horizon_row.clone(),
            oversight_row: oversight_row.clone(),
            license_row: license_row.clone(),
            beneficiary_row: beneficiary_row.clone(),
            family_group: family_group.clone(),
            family_hub_row: family_hub_row.clone(),
            firecrawl_row: firecrawl_row.clone(),
            firecrawl_button: firecrawl_button.clone(),
        };

        let poll_list = device_list.clone();
        let poll_stack = stack.clone();
        let poll_settings_badge = refresh_settings_badge.clone();
        let poll_devices_fp = devices_fp.clone();
        let poll_tick = Rc::new(Cell::new(0u32));
        glib::timeout_add_seconds_local(5, move || {
            let on_settings = poll_stack.visible_child_name().as_deref() == Some("settings");
            if on_settings {
                refresh_devices_async(&poll_list, &poll_devices_fp);
            }
            // The badge probe shells out twice — keep the 5s cadence only while
            // Settings is on screen and drop to ~1/min elsewhere. Probes still
            // run off the UI thread.
            let tick = poll_tick.get().wrapping_add(1);
            poll_tick.set(tick);
            if on_settings || tick % 12 == 0 {
                poll_settings_badge();
            }
            glib::ControlFlow::Continue
        });
        let tab_refresh_list = device_list.clone();
        let tab_devices_fp = devices_fp.clone();
        let tab_home_badge = refresh_home_badge.clone();
        let tab_collab_badge = refresh_collab_badge.clone();
        let tab_home_handle = home_handle.clone();
        let tab_collab_handle = collab_handle.clone();
        let tab_settings_rows = settings_rows.clone();
        stack.connect_visible_child_name_notify(move |stack| {
            if stack.visible_child_name().as_deref() == Some("settings") {
                refresh_devices_async(&tab_refresh_list, &tab_devices_fp);
                // Settings rows only refresh while the tab is up — catch up now.
                refresh_settings_rows_async(&tab_settings_rows, true);
            }
            let missions_visible = stack.visible_child_name().as_deref() == Some("missions");
            let collab_visible = stack.visible_child_name().as_deref() == Some("collab");
            tab_home_handle.notify_tab_visible(missions_visible);
            tab_collab_handle.notify_tab_visible(collab_visible);
            if missions_visible {
                tab_home_handle.refresh();
            }
            if collab_visible {
                tab_collab_handle.refresh();
            }
            tab_home_badge();
            tab_collab_badge();
        });
        home_handle.notify_tab_visible(false);
        collab_handle.notify_tab_visible(false);

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
                        "This Brain works on its own. To pair an iPhone: open Sovereign AI Remote on the same Wi‑Fi and scan the pairing QR.",
                    );
                    refresh_link_addresses_async(&link_addresses, Some(&window));
                }
                Err(error) => {
                    status_title.set_label("Your Centurion needs attention");
                    status_detail.set_label(&error);
                    refresh_link_addresses_async(&link_addresses, Some(&window));
                }
            }
        };

        // Starting the remote listener shells out — run it once the window is
        // on screen so present() is never behind CLI/TCP work.
        glib::idle_add_local_once(move || update_status());
        // Smooth Transfer (Get Brain install) or first-run welcome — never both.
        if smooth_transfer_pending() {
            let window = window.clone();
            glib::timeout_add_local(std::time::Duration::from_millis(400), move || {
                show_transfer_complete_dialog(&window);
                glib::ControlFlow::Break
            });
        } else if !brain_welcome_seen() {
            let window = window.clone();
            let (tx, rx) = std::sync::mpsc::channel::<bool>();
            std::thread::spawn(move || {
                let _ = tx.send(any_iphones_linked());
            });
            glib::timeout_add_local(std::time::Duration::from_millis(400), move || {
                match rx.try_recv() {
                    Ok(linked) => {
                        if !linked {
                            show_brain_welcome_dialog(&window);
                        }
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                }
            });
        }
        // Defer Settings row fills until after first paint so cold-start Chat
        // is not blocked by provider/bridge probes.
        {
            let settings_rows = settings_rows.clone();
            glib::idle_add_local_once(move || {
                refresh_settings_rows_async(&settings_rows, false);
            });
        }
        {
            let poll_settings_rows = settings_rows.clone();
            let poll_settings_stack = stack.clone();
            glib::timeout_add_seconds_local(30, move || {
                // Settings rows are only visible on the Settings tab — don't pay
                // for provider/bridge probes while Chat or Focus is up.
                if poll_settings_stack.visible_child_name().as_deref() == Some("settings") {
                    refresh_settings_rows_async(&poll_settings_rows, true);
                }
                glib::ControlFlow::Continue
            });
        }
        restore_thinking_button.connect_clicked({
            let thinking_settings_row = thinking_settings_row.clone();
            let thinking_detail = thinking_detail.clone();
            move |button| {
                button.set_sensitive(false);
                thinking_settings_row.set_subtitle("Restoring last working setup…");
                let button = button.clone();
                let thinking_settings_row = thinking_settings_row.clone();
                let thinking_detail = thinking_detail.clone();
                crate::bridge_actions::run_bridge_async(
                    || {
                        let response = run_provider_command(&["restore"]);
                        let status = run_provider_command(&["status", "--skip-probe"]);
                        (response, status)
                    },
                    move |(response, status)| {
                        button.set_sensitive(true);
                        let Some(response) = response else {
                            thinking_settings_row
                                .set_subtitle("Could not restore the last working setup.");
                            return;
                        };
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
                        if let Some(status) = status.and_then(|response| response.status) {
                            apply_thinking_status(&thinking_detail, &thinking_settings_row, status);
                        }
                    },
                );
            }
        });
        change_thinking_button.connect_clicked({
            let thinking_settings_row = thinking_settings_row.clone();
            let thinking_detail = thinking_detail.clone();
            let window = window.clone();
            move |_| show_change_thinking_dialog(&window, &thinking_settings_row, &thinking_detail)
        });
        firecrawl_button.connect_clicked({
            let window = window.clone();
            let firecrawl_row = firecrawl_row.clone();
            let firecrawl_button = firecrawl_button.clone();
            move |_| {
                show_firecrawl_key_dialog(&window, &firecrawl_row, &firecrawl_button);
            }
        });
        let backup_manage_button = gtk::Button::with_label("Change");
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
            let stack = stack.clone();
            move |_| {
                stack.set_visible_child_name("collab");
            }
        });
        pairing_settings_row.connect_activated({
            let window = window.clone();
            move |_| {
                show_pairing_qr_window(&window);
            }
        });
        pairing_qr_button.connect_clicked({
            let window = window.clone();
            move |_| show_pairing_qr_window(&window)
        });
        hub_pair_button.connect_clicked({
            let window = window.clone();
            move |_| show_pairing_qr_window(&window)
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
                // Open immediately — load the current statement into the dialog
                // async so Settings never waits on the bridge before present().
                crate::home_page::show_mission_edit_dialog(
                    &window,
                    "",
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
            move |_| {
                show_skills_tools_dialog(&window, Rc::new(|_t: String, _d: String| {}))
            }
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
            let window = window.clone();
            let gateway_row = gateway_row.clone();
            let gateway_platform_list = gateway_platform_list.clone();
            let gateway_start_btn = gateway_start_btn.clone();
            let gateway_stop_btn = gateway_stop_btn.clone();
            let gateway_restart_btn = gateway_restart_btn.clone();
            move |_| {
                run_gateway_lifecycle_with_feedback(
                    &window,
                    &gateway_row,
                    &gateway_platform_list,
                    &gateway_start_btn,
                    &gateway_stop_btn,
                    &gateway_restart_btn,
                    "start",
                );
            }
        });
        gateway_stop_btn.connect_clicked({
            let window = window.clone();
            let gateway_row = gateway_row.clone();
            let gateway_platform_list = gateway_platform_list.clone();
            let gateway_start_btn = gateway_start_btn.clone();
            let gateway_stop_btn = gateway_stop_btn.clone();
            let gateway_restart_btn = gateway_restart_btn.clone();
            move |_| {
                run_gateway_lifecycle_with_feedback(
                    &window,
                    &gateway_row,
                    &gateway_platform_list,
                    &gateway_start_btn,
                    &gateway_stop_btn,
                    &gateway_restart_btn,
                    "stop",
                );
            }
        });
        gateway_restart_btn.connect_clicked({
            let window = window.clone();
            let gateway_row = gateway_row.clone();
            let gateway_platform_list = gateway_platform_list.clone();
            let gateway_start_btn = gateway_start_btn.clone();
            let gateway_stop_btn = gateway_stop_btn.clone();
            let gateway_restart_btn = gateway_restart_btn.clone();
            move |_| {
                run_gateway_lifecycle_with_feedback(
                    &window,
                    &gateway_row,
                    &gateway_platform_list,
                    &gateway_start_btn,
                    &gateway_stop_btn,
                    &gateway_restart_btn,
                    "restart",
                );
            }
        });
        // Defer Channels fill until Settings is shown — Chat cold open must not
        // pay for gateway_status while the user is still on Chat.
        {
            let window = window.clone();
            let gateway_row = gateway_row.clone();
            let gateway_platform_list = gateway_platform_list.clone();
            let gateway_loaded = Rc::new(Cell::new(false));
            stack.connect_visible_child_name_notify({
                let gateway_loaded = gateway_loaded.clone();
                move |stack| {
                    if stack.visible_child_name().as_deref() != Some("settings") {
                        return;
                    }
                    if gateway_loaded.replace(true) {
                        return;
                    }
                    refresh_gateway_ui_async(&window, &gateway_row, &gateway_platform_list);
                }
            });
        }
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
            move |_| {
                show_memory_horizon_dialog(&window, &memory_horizon_row, Rc::new(|_t: String, _d: String| {}))
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
                        if centurion_remote_bin().is_none() {
                            status_title.set_label("Your Centurion is ready");
                            status_detail.set_label(
                                "Chat uses your Centurion on this computer. The iPhone pairing helper is not installed yet — that does not block Chat.",
                            );
                        } else {
                            status_title.set_label("Your Centurion is ready");
                            status_detail.set_label(
                                "The private desk connection has restarted. Use Link iPhone under Settings if you need a fresh pairing QR.",
                            );
                        }
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

        window.present();
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

    /// Outline "Check" until an update is waiting; solid "Update" when it is.
    fn style_update_cta_button(button: &gtk::Button, update_available: bool) {
        if update_available {
            button.set_label("Update");
            button.add_css_class("suggested-action");
            button.set_tooltip_text(Some(
                "A newer Sovereign AI Brain build is available — install it now.",
            ));
        } else {
            button.set_label("Check");
            button.remove_css_class("suggested-action");
            button.set_tooltip_text(Some(
                "Check for a newer Sovereign AI Brain build on this computer.",
            ));
        }
    }

    fn settings_needs_attention() -> bool {
        !settings_attention_items().is_empty()
    }

    #[derive(Debug, Clone)]
    enum SettingsAttentionItem {
        Thinking { detail: String },
        UpdateAvailable { detail: String },
    }

    fn settings_attention_items() -> Vec<SettingsAttentionItem> {
        // Settings tab "!": thinking unhealthy / unavailable, or a Brain update waiting.
        // Linked remotes are expected; do not badge Settings solely for zero remotes.
        // Prefer the daemon snapshot so the 5s tab-badge poll does not spawn
        // a heavy provider CLI. Older daemons fall back to provider_status,
        // then finally to the CLI.
        let mut items = Vec::new();
        if let Some((_, detail)) = load_update_attention() {
            items.push(SettingsAttentionItem::UpdateAvailable { detail });
        }
        let bridge_thinking = cached_settings_snapshot()
            .filter(|payload| payload.get("ok").and_then(|v| v.as_bool()) == Some(true))
            .and_then(|payload| payload.get("thinking").cloned())
            .filter(|thinking| thinking.is_object() && thinking.get("health").is_some())
            .or_else(|| {
                run_bridge_action("provider_status", serde_json::json!({ "skip_probe": true }))
                    .filter(|payload| payload.get("ok").and_then(|v| v.as_bool()) == Some(true))
                    .and_then(|payload| payload.get("status").cloned())
                    .filter(|status| status.is_object() && status.get("health").is_some())
            });
        let cli_status = if bridge_thinking.is_none() {
            run_provider_command(&["status", "--skip-probe"]).and_then(|response| response.status)
        } else {
            None
        };
        let health = bridge_thinking
            .as_ref()
            .and_then(|thinking| thinking.get("health"))
            .and_then(|value| value.as_str())
            .map(str::to_owned)
            .or_else(|| cli_status.as_ref().map(|status| status.health.clone()));
        let health_message = bridge_thinking
            .as_ref()
            .and_then(|thinking| thinking.get("health_message"))
            .and_then(|value| value.as_str())
            .filter(|message| !message.trim().is_empty())
            .map(str::to_owned)
            .or_else(|| {
                cli_status
                    .as_ref()
                    .map(|status| status.health_message.clone())
                    .filter(|message| !message.trim().is_empty())
            });
        match health.as_deref() {
            Some("ok") => {}
            Some(health) => {
                let detail =
                    health_message.unwrap_or_else(|| format!("Thinking service is {health}."));
                items.push(SettingsAttentionItem::Thinking {
                    detail: format!("{detail} Open Fix Thinking Service or Change Thinking."),
                });
            }
            None => {
                items.push(SettingsAttentionItem::Thinking {
                    detail: "Thinking service status is unavailable — open Fix Thinking Service."
                        .to_owned(),
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

    /// Tab titles stay ink; badge is a bronze count pill — not a red error mark.
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
                    badge.set_label(m);
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

    fn refresh_devices_async(list: &gtk::ListBox, fingerprint: &Rc<RefCell<String>>) {
        let list = list.clone();
        let fingerprint = fingerprint.clone();
        let (tx, rx) = std::sync::mpsc::channel::<(String, Option<DeviceListing>, String)>();
        std::thread::spawn(move || {
            let centurion_remote = std::env::var("HOME")
                .ok()
                .map(|home| format!("{home}/.local/bin/centurion-remote"))
                .filter(|path| std::path::Path::new(path).is_file())
                .unwrap_or_else(|| "centurion-remote".to_owned());
            let output = Command::new(&centurion_remote)
                .args(["devices", "--json"])
                .output();
            let (raw, listing) = match output {
                Ok(output) if output.status.success() => {
                    let raw = String::from_utf8_lossy(&output.stdout).to_string();
                    let listing = serde_json::from_str::<DeviceListing>(&raw).ok();
                    (raw, listing)
                }
                _ => (String::new(), None),
            };
            let _ = tx.send((raw, listing, centurion_remote));
        });
        glib::timeout_add_local(std::time::Duration::from_millis(40), move || {
            match rx.try_recv() {
                Ok((raw, listing, remote)) => {
                    if !raw.is_empty() && *fingerprint.borrow() == raw {
                        return glib::ControlFlow::Break;
                    }
                    *fingerprint.borrow_mut() = raw;
                    populate_devices_list(&list, listing, &remote);
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            }
        });
    }

    fn refresh_devices(list: &gtk::ListBox) {
        // Sync path for approve/revoke callbacks — force rebuild.
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
        populate_devices_list(list, listing, &centurion_remote);
    }

    fn populate_devices_list(
        list: &gtk::ListBox,
        listing: Option<DeviceListing>,
        centurion_remote: &str,
    ) {
        while let Some(child) = list.first_child() {
            list.remove(&child);
        }

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
            let remote = centurion_remote.to_owned();
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
            let remote = centurion_remote.to_owned();
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
                    .subtitle("On your iPhone, scan the pairing QR in Settings → Status with Sovereign AI Remote (same Wi‑Fi).")
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
        crate::bridge_actions::resolve_centurion_cli()
    }

    fn prepare_centurion_cli() -> Command {
        let mut command = Command::new(centurion_binary());
        command.env("CENTURION_HOME", crate::bridge_actions::resolve_centurion_home());
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

    /// Run one `provider` CLI command, keeping the reason it failed.
    ///
    /// The plain `run_provider_command` throws that reason away, which is how a
    /// customer saw only "Could not set backup thinking service." with no cause.
    /// Any dialog that reports failure must use this one.
    fn run_provider_command_result(args: &[&str]) -> Result<ProviderCliResponse, String> {
        // `--json` belongs on the parent `provider` parser, before the subcommand.
        let rest: Vec<&str> = args.iter().copied().filter(|a| *a != "--json").collect();
        let mut command_args = vec!["provider", "--json"];
        command_args.extend_from_slice(&rest);
        let output = prepare_centurion_cli()
            .args(command_args)
            .output()
            .map_err(|error| {
                format!(
                    "Centurion could not run its own thinking-service command on this brain \
({error}).\n\nRe-run Install Brain from your Get Brain download, then try again."
                )
            })?;
        // Parse JSON even when exit status is non-zero so callers can show
        // structured failure messages (e.g. blocked OpenRouter, missing key).
        serde_json::from_slice::<ProviderCliResponse>(&output.stdout).map_err(|_| {
            "Centurion's thinking-service command did not answer in a form the app could \
read.\n\nRe-run Install Brain from your Get Brain download, then try again."
                .to_owned()
        })
    }

    fn run_provider_command(args: &[&str]) -> Option<ProviderCliResponse> {
        run_provider_command_result(args).ok()
    }

    /// Save a thinking-service access code, keeping the reason if it fails.
    fn run_provider_save_key(
        connector_id: &str,
        access_code: &str,
    ) -> Result<ProviderCliResponse, String> {
        let mut child = prepare_centurion_cli()
            .args(["provider", "--json", "save-key", connector_id, "-"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|error| {
                format!(
                    "Centurion could not reach its own command on this brain ({error}).\n\n\
Re-run Install Brain from your Get Brain download, then try again."
                )
            })?;
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(access_code.as_bytes());
        }
        let output = child.wait_with_output().map_err(|error| {
            format!(
                "Centurion could not finish saving the access code ({error}).\n\n\
Try again in a moment."
            )
        })?;
        serde_json::from_slice::<ProviderCliResponse>(&output.stdout).map_err(|_| {
            "Centurion did not confirm the access code was saved.\n\nTry again in a moment."
                .to_owned()
        })
    }

    /// Run one `support` CLI command, keeping the reason it failed.
    fn run_support_command_result(args: &[&str]) -> Result<ProviderCliResponse, String> {
        // `--json` belongs on the parent `support` parser, before the subcommand.
        let rest: Vec<&str> = args.iter().copied().filter(|a| *a != "--json").collect();
        let mut command_args = vec!["support", "--json"];
        command_args.extend_from_slice(&rest);
        let output = prepare_centurion_cli()
            .args(command_args)
            .output()
            .map_err(|error| {
                format!(
                    "Centurion could not run its own support command on this brain \
({error}).\n\nIs Centurion installed? Re-run Install Brain from your Get Brain \
download, then try again."
                )
            })?;
        // Parse even on non-zero exit so lookup/health can surface `message`.
        serde_json::from_slice::<ProviderCliResponse>(&output.stdout).map_err(|_| {
            "Centurion's support command did not answer in a form the app could read.\n\n\
Re-run Install Brain from your Get Brain download, then try again."
                .to_owned()
        })
    }

    fn run_support_command(args: &[&str]) -> Option<ProviderCliResponse> {
        run_support_command_result(args).ok()
    }

    fn run_update_check_result() -> Result<UpdateCheckPayload, String> {
        let screen_version = installed_version();
        let output = prepare_centurion_cli()
            .arg("update")
            .arg("--check")
            .arg("--json")
            .arg("--screen-version")
            .arg(&screen_version)
            .output()
            .map_err(|error| {
                format!(
                    "Centurion could not run its own update checker on this brain \
({error}).\n\nIs Centurion installed? Re-run Install Brain from your Get Brain \
download, then try again."
                )
            })?;
        // Parse JSON even when exit status is non-zero (network / unavailable).
        serde_json::from_slice::<UpdateCheckPayload>(&output.stdout).map_err(|_| {
            "Centurion's update checker did not answer in a form the app could read.\n\n\
Is Centurion installed? Re-run Install Brain from your Get Brain download, then try again."
                .to_owned()
        })
    }

    fn run_update_check() -> Option<UpdateCheckPayload> {
        run_update_check_result().ok()
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
                .join("brain")
                .join("linux")
                .join("scripts")
                .join("install-user.sh");
            if script.is_file() {
                return Ok(root);
            }
            let legacy = root
                .join("desktop-native")
                .join("scripts")
                .join("install-user.sh");
            if legacy.is_file() {
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
        let log_path = PathBuf::from(crate::bridge_actions::resolve_centurion_home())
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
            installed_version()
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
        let home = crate::bridge_actions::resolve_centurion_home();
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
            let _ = tx.send(run_update_check_result());
        });
        glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
            match rx.try_recv() {
                Ok(payload) => {
                    present_update_check_result(&parent, &update_row, payload, on_attention.clone());
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    present_update_check_result(
                        &parent,
                        &update_row,
                        Err("The update check did not finish — the Brain stopped answering. \
Close Settings and try Check for update again."
                            .to_owned()),
                        on_attention.clone(),
                    );
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
        payload: Result<UpdateCheckPayload, String>,
        on_attention: Rc<dyn Fn()>,
    ) {
        let payload = match payload {
            Ok(payload) => payload,
            Err(reason) => {
                update_row.set_subtitle("Could not check for updates.");
                let dialog = adw::AlertDialog::builder()
                    .heading("Check for update")
                    .body(format!(
                        "{reason}\n\nCould not check for updates on this brain. \
Make sure Centurion is installed, then try again."
                    ))
                    .close_response("ok")
                    .build();
                dialog.add_response("ok", "OK");
                dialog.present(Some(parent));
                return;
            }
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

    fn run_telegram_summary(args: &[&str]) -> Result<serde_json::Value, String> {
        let mut command_args = vec!["telegram", "import"];
        command_args.extend_from_slice(args);
        command_args.push("--json");
        let output = prepare_centurion_cli()
            .args(command_args)
            .output()
            .map_err(|error| {
                format!(
                    "Centurion could not run its own Telegram history reader on this brain \
({error}).\n\nIs Centurion installed? Re-run Install Brain from your Get Brain \
download, then try again."
                )
            })?;
        // Parse JSON even when exit status is non-zero (no Telegram history found).
        serde_json::from_slice::<serde_json::Value>(&output.stdout).map_err(|_| {
            "Centurion's Telegram history reader did not answer in a form the app could \
read.\n\nIs Centurion installed? Re-run Install Brain from your Get Brain download, \
then try again."
                .to_owned()
        })
    }

    fn bridge_python() -> String {
        crate::bridge_actions::resolve_bridge_python()
    }

    
    fn anywhere_relay_subtitle(resp: Option<&serde_json::Value>) -> (bool, String) {
        let enabled = resp
            .and_then(|v| v.get("enabled"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let online = resp
            .and_then(|v| v.get("presence"))
            .and_then(|v| v.get("online"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let ws_ok = resp
            .and_then(|v| v.get("websockets_installed"))
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        let pipe_ready = resp
            .and_then(|v| v.get("realtime_pipe_ready"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let last_error = resp
            .and_then(|v| v.get("presence"))
            .and_then(|v| v.get("last_error"))
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty());
        let hint = resp
            .and_then(|v| v.get("hint"))
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty());
        let url_configured = resp
            .and_then(|v| v.get("supabase_url_configured"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let subtitle = if enabled && !ws_ok {
            last_error
                .or(hint)
                .unwrap_or("On — install Away deps (Check for update / remote-relay)")
                .to_owned()
        } else if enabled && pipe_ready {
            "On — Away pipe ready (home Wi‑Fi still preferred when nearby)".to_owned()
        } else if enabled && online {
            "On — Brain presence live on Centurion cloud".to_owned()
        } else if enabled && !url_configured {
            last_error
                .unwrap_or("On — Centurion cloud did not return Realtime endpoints")
                .to_owned()
        } else if enabled {
            last_error
                .unwrap_or("On — waiting for relay presence")
                .to_owned()
        } else {
            "Off — home Wi‑Fi / Desktop only (most private)".to_owned()
        };
        (enabled, subtitle)
    }

fn run_bridge_action(action: &str, extra: serde_json::Value) -> Option<serde_json::Value> {
        crate::bridge_actions::run_bridge_action(action, extra)
    }

    /// Like `run_bridge_action`, but keeps the reason it failed, so a dialog
    /// can show the cause instead of a bare "Could not …" shrug.
    fn run_bridge_action_result(
        action: &str,
        extra: serde_json::Value,
    ) -> Result<serde_json::Value, String> {
        crate::bridge_actions::run_bridge_action_result(action, extra)
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
        apply_autonomy_row_subtitle(row, &payload);
    }

    fn apply_autonomy_row_subtitle(row: &adw::ActionRow, payload: &serde_json::Value) {
        let level = payload
            .pointer("/oversight/autonomy_level")
            .and_then(|v| v.as_str())
            .unwrap_or("balanced");
        row.set_subtitle(autonomy_label(level));
    }

    /// Every Settings row filled by the deferred / periodic bridge pass.
    #[derive(Clone)]
    struct SettingsRows {
        thinking_detail: gtk::Label,
        thinking_row: adw::ActionRow,
        backup_row: adw::ActionRow,
        autonomy_row: adw::ActionRow,
        soul_row: adw::ActionRow,
        memory_horizon_row: adw::ActionRow,
        oversight_row: adw::ActionRow,
        license_row: adw::ActionRow,
        beneficiary_row: adw::ActionRow,
        family_group: adw::PreferencesGroup,
        family_hub_row: adw::ActionRow,
        firecrawl_row: adw::ActionRow,
        firecrawl_button: gtk::Button,
    }

    /// Worker-side payloads for `SettingsRows` — everything here is `Send`, so
    /// the bridge / CLI round-trips happen off the GTK thread.
    struct SettingsFill {
        soul: Option<serde_json::Value>,
        oversight: Option<serde_json::Value>,
        horizon: Option<serde_json::Value>,
        thinking_line: Option<String>,
        backup_line: String,
        license_visible: bool,
        beneficiary_visible: bool,
        firecrawl_configured: bool,
        firecrawl_line: String,
    }

    /// TTL-cache the raw settings_snapshot ~45s so Settings reopen + attention
    /// badge polls share one bridge round-trip.
    fn cached_settings_snapshot() -> Option<serde_json::Value> {
        use std::sync::Mutex;
        use std::time::{Duration, Instant};
        struct Cache {
            at: Instant,
            value: serde_json::Value,
        }
        static CACHE: OnceLock<Mutex<Option<Cache>>> = OnceLock::new();
        let lock = CACHE.get_or_init(|| Mutex::new(None));
        if let Ok(guard) = lock.lock() {
            if let Some(hit) = guard.as_ref() {
                if hit.at.elapsed() < Duration::from_secs(45) {
                    return Some(hit.value.clone());
                }
            }
        }
        let snap =
            run_bridge_action("settings_snapshot", serde_json::json!({ "skip_probe": true }))?;
        if snap.get("ok").and_then(|v| v.as_bool()) != Some(true) {
            return Some(snap);
        }
        if let Ok(mut guard) = lock.lock() {
            *guard = Some(Cache {
                at: Instant::now(),
                value: snap.clone(),
            });
        }
        Some(snap)
    }

    /// `plain_health` picks the plain-language health phrasing used by the
    /// background poll; the first fill shows provider · model instead.
    fn collect_settings_fill(plain_health: bool) -> SettingsFill {
        // Prefer one bridge round-trip (no centurion CLI spawn). Fall back to
        // the legacy multi-call path when the daemon is older.

        if let Some(snap) = cached_settings_snapshot() {
            if snap.get("ok").and_then(|v| v.as_bool()) == Some(true) {
                let thinking = snap.get("thinking").cloned().unwrap_or(serde_json::Value::Null);
                let thinking_line = thinking.as_object().map(|t| {
                    let provider = t
                        .get("provider")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_owned();
                    let model = t.get("model").and_then(|v| v.as_str()).unwrap_or("");
                    let health = t.get("health").and_then(|v| v.as_str()).unwrap_or("ok");
                    let health_message = t
                        .get("health_message")
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    let last_good = t
                        .get("last_good_available")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false);
                    if !plain_health {
                        return if model.is_empty() {
                            provider
                        } else {
                            format!("{provider} · {model}")
                        };
                    }
                    let plain = match health {
                        "ok" => "Working normally",
                        "degraded" => "May be slow",
                        _ => "Needs attention",
                    };
                    let mut line = format!("{plain} — {health_message}");
                    if last_good && health != "ok" {
                        line.push_str(" Last working setup is available.");
                    }
                    line
                });

                let backups = snap
                    .get("backups")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                let backup_line = if backups.is_empty() {
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
                };
                let soul = snap.get("soul").cloned().map(|s| {
                    serde_json::json!({ "ok": true, "soul": s })
                });
                let oversight = snap.get("oversight").cloned().map(|o| {
                    serde_json::json!({ "ok": true, "oversight": o })
                });
                let horizon = snap.get("horizon").cloned().map(|h| {
                    serde_json::json!({ "ok": true, "snapshot": h })
                });
                let license_visible = snap
                    .pointer("/status/enabled")
                    .or_else(|| snap.get("enabled"))
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                let beneficiary_visible = {
                    let b = snap.get("beneficiary").unwrap_or(&serde_json::Value::Null);
                    let enabled = b
                        .get("enabled")
                        .or_else(|| b.get("program_active"))
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false);
                    let has_family = b
                        .get("family_beneficiary_first_name")
                        .or_else(|| b.pointer("/family/first_name"))
                        .and_then(|v| v.as_str())
                        .map(|v| !v.trim().is_empty())
                        .unwrap_or(false);
                    enabled || has_family
                };
                let (firecrawl_configured, firecrawl_line) =
                    firecrawl_status_from_value(snap.get("firecrawl"));
                return SettingsFill {
                    soul,
                    oversight,
                    horizon,
                    thinking_line,
                    backup_line,
                    license_visible,
                    beneficiary_visible,
                    firecrawl_configured,
                    firecrawl_line,
                };
            }
        }

        // Legacy fallback — older bridge without settings_snapshot.
        let soul = run_bridge_action("soul_get", serde_json::json!({}));
        let oversight = run_bridge_action("oversight_get", serde_json::json!({}));
        let horizon = run_bridge_action("memory_horizon_snapshot", serde_json::json!({}));
        let thinking_line =
            run_provider_command(&["status", "--skip-probe"]).and_then(|response| {
                let status = response.status?;
                if !plain_health {
                    return Some(if status.model.is_empty() {
                        status.provider
                    } else {
                        format!("{} · {}", status.provider, status.model)
                    });
                }
                let plain = match status.health.as_str() {
                    "ok" => "Working normally",
                    "degraded" => "May be slow",
                    _ => "Needs attention",
                };
                let mut line = format!("{plain} — {}", status.health_message);
                if status.last_good_available && status.health != "ok" {
                    line.push_str(" Last working setup is available.");
                }
                Some(line)
            });
        let (firecrawl_configured, firecrawl_line) = firecrawl_status_from_bridge();
        SettingsFill {
            soul,
            oversight,
            horizon,
            thinking_line,
            backup_line: backup_thinking_subtitle(),
            license_visible: license_entitlement_enabled(),
            beneficiary_visible: beneficiary_program_active(),
            firecrawl_configured,
            firecrawl_line,
        }
    }

    fn firecrawl_status_from_value(value: Option<&serde_json::Value>) -> (bool, String) {
        let configured = value
            .and_then(|v| v.get("configured"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let line = if configured {
            "API key saved on this brain — ready for research scraping.".to_owned()
        } else {
            "Not set — get a key at https://www.firecrawl.dev/".to_owned()
        };
        (configured, line)
    }

    fn firecrawl_status_from_bridge() -> (bool, String) {
        let payload = run_bridge_action(
            "tool_env_get",
            serde_json::json!({ "key": "FIRECRAWL_API_KEY" }),
        );
        firecrawl_status_from_value(payload.as_ref())
    }

    fn apply_settings_fill(rows: &SettingsRows, fill: SettingsFill) {
        if let Some(line) = fill.thinking_line {
            rows.thinking_detail.set_label(&line);
            rows.thinking_row.set_subtitle(&line);
        }
        rows.backup_row.set_subtitle(&fill.backup_line);
        match fill.soul.as_ref() {
            Some(payload) => apply_soul_row_subtitle(&rows.soul_row, payload),
            None => rows
                .soul_row
                .set_subtitle("Could not read your Sovereign's Soul."),
        }
        match fill.horizon.as_ref() {
            Some(payload) => apply_memory_horizon_row_subtitle(&rows.memory_horizon_row, payload),
            None => rows
                .memory_horizon_row
                .set_subtitle("Could not read Memory Horizon."),
        }
        match fill.oversight.as_ref() {
            Some(payload) => {
                apply_autonomy_row_subtitle(&rows.autonomy_row, payload);
                apply_oversight_row_subtitle(&rows.oversight_row, payload);
            }
            None => {
                rows.autonomy_row.set_subtitle("Could not read autonomy level.");
                rows.oversight_row
                    .set_subtitle("Could not read reporting preferences.");
            }
        }
        rows.license_row.set_visible(fill.license_visible);
        rows.beneficiary_row.set_visible(fill.beneficiary_visible);
        rows.family_group.set_visible(fill.beneficiary_visible);
        rows.family_hub_row.set_visible(fill.beneficiary_visible);
        rows.firecrawl_row.set_subtitle(&fill.firecrawl_line);
        rows.firecrawl_button.set_label(if fill.firecrawl_configured {
            "Update"
        } else {
            "Add key"
        });
    }

    /// One worker pass for every Settings row — no bridge I/O on the UI thread.
    fn refresh_settings_rows_async(rows: &SettingsRows, plain_health: bool) {
        let rows = rows.clone();
        let (tx, rx) = std::sync::mpsc::channel::<SettingsFill>();
        std::thread::spawn(move || {
            let _ = tx.send(collect_settings_fill(plain_health));
        });
        glib::timeout_add_local(std::time::Duration::from_millis(40), move || {
            match rx.try_recv() {
                Ok(fill) => {
                    apply_settings_fill(&rows, fill);
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            }
        });
    }

    fn license_entitlement_enabled() -> bool {
        run_bridge_action("license_status", serde_json::json!({}))
            .and_then(|p| {
                p.pointer("/status/enabled")
                    .or_else(|| p.get("enabled"))
                    .and_then(|v| v.as_bool())
            })
            .unwrap_or(false)
    }

    fn beneficiary_program_active() -> bool {
        run_bridge_action("beneficiary_snapshot", serde_json::json!({}))
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
            .unwrap_or(false)
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
        apply_oversight_row_subtitle(row, &payload);
    }

    fn apply_oversight_row_subtitle(row: &adw::ActionRow, payload: &serde_json::Value) {
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
        let parent = parent.clone();
        let autonomy_row = autonomy_row.clone();
        let oversight_row = oversight_row.clone();
        // Skeleton dialog appears after worker returns current level — never block UI.
        crate::bridge_actions::run_bridge_action_async(
            "oversight_get",
            serde_json::json!({}),
            move |payload| {
                let current = payload
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
                        let level = response.to_owned();
                        let autonomy_row = autonomy_row.clone();
                        let oversight_row = oversight_row.clone();
                        crate::bridge_actions::run_bridge_async(
                            move || {
                                crate::bridge_actions::run_bridge_action(
                                    "oversight_put",
                                    serde_json::json!({
                                        "oversight": { "autonomy_level": level },
                                        "apply_level_preset": true,
                                    }),
                                )
                            },
                            move |payload| match payload {
                                Some(payload)
                                    if payload.get("ok").and_then(|v| v.as_bool())
                                        == Some(true) =>
                                {
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
                            },
                        );
                    }
                    dialog.close();
                });
                dialog.present(Some(&parent));
            },
        );
    }

    fn show_soul_dialog(parent: &adw::ApplicationWindow, soul_row: &adw::ActionRow) {
        let payload = match run_bridge_action_result("soul_get", serde_json::json!({})) {
            Ok(payload) if payload.get("ok").and_then(|v| v.as_bool()) == Some(true) => payload,
            Ok(payload) => {
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
            Err(error) => {
                let fail = adw::AlertDialog::builder()
                    .heading("Could not load Soul")
                    .body(format!(
                        "{error}\n\nYour Soul file on disk was not changed — close Settings, \
run install-user.sh again if you just updated, then reopen Soul."
                    ))
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
        content.add_css_class("centurion-dialog-body");
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
        content.add_css_class("centurion-dialog-body");
        content.set_margin_top(12);
        content.set_margin_bottom(12);
        content.set_margin_start(12);
        content.set_margin_end(12);
        content.append(
            &gtk::Label::builder()
                .label("Changes apply on the next conversation.")
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );
        content.append(&list);

        let dialog = adw::AlertDialog::builder()
            .heading("Reporting &amp; Oversight")
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
        let (heading, body, can_bring) = match &preview {
            Ok(value) if value.get("ok").and_then(|v| v.as_bool()) == Some(true) => {
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
            Ok(value) => (
                "No Telegram history found".to_owned(),
                value
                    .get("message")
                    .and_then(|v| v.as_str())
                    .unwrap_or("No Telegram bot DM session was found on this Centurion.")
                    .to_owned(),
                false,
            ),
            Err(error) => (
                "Could not check Telegram history".to_owned(),
                format!(
                    "{error}\n\nRun `centurion telegram import --dry-run` on this \
computer if you need more detail."
                ),
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
                let bring_result = run_telegram_summary(&[]);
                if let Err(ref error) = bring_result {
                    let first_line = error.split('\n').next().unwrap_or(error).trim();
                    row.set_subtitle(&format!(
                        "Could not bring over Telegram history: {first_line}"
                    ));
                    return;
                }
                if let Ok(result) = bring_result {
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
        apply_thinking_status(detail, settings_row, status);
    }

    fn apply_thinking_status(
        detail: &gtk::Label,
        settings_row: &adw::ActionRow,
        status: ProviderStatusPayload,
    ) {
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
        row.set_subtitle(&backup_thinking_subtitle());
    }

    /// Worker-safe: reads the backup list and renders it as row subtitle text.
    fn backup_thinking_subtitle() -> String {
        let Some(response) = run_support_command(&["backups"]) else {
            return "Could not read backup thinking services.".to_owned();
        };
        let backups = response
            .result
            .as_ref()
            .and_then(|value| value.get("backups"))
            .and_then(|value| value.as_array())
            .cloned()
            .unwrap_or_default();
        if backups.is_empty() {
            return "No backup thinking services configured.".to_owned();
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
            format!("{} backup thinking service(s) configured.", backups.len())
        } else {
            labels.join(" · ")
        }
    }

    fn decision_first_pref_path() -> std::path::PathBuf {
        std::path::PathBuf::from(crate::bridge_actions::resolve_centurion_home())
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

    /// Platform error text arrives from the gateway. Some of it still names a
    /// terminal command (e.g. WhatsApp's "run `centurion whatsapp` to pair"),
    /// and our own rule is that no customer journey contains a terminal step.
    /// Keep the honest state, drop the command, and point at the in-app control
    /// that does the same job (the Connect WhatsApp wizard behind the row's
    /// Connect / Reconnect button).
    fn translate_platform_error(error_message: &str) -> String {
        let lower = error_message.to_ascii_lowercase();
        let names_command = lower.contains("centurion whatsapp")
            || lower.contains("centurion telegram")
            || lower.contains("centurion gateway")
            || error_message.contains("run `");
        if !names_command {
            return error_message.to_owned();
        }
        if lower.contains("whatsapp") {
            return if lower.contains("pair") {
                "WhatsApp is enabled but not paired — tap Connect to link your phone."
                    .to_owned()
            } else {
                "WhatsApp needs attention — tap Connect to link your phone again.".to_owned()
            };
        }
        "This channel needs attention — open its settings here to fix it.".to_owned()
    }

    fn gateway_platform_subtitle(
        configured: bool,
        connected: bool,
        state: &str,
        status: &str,
        error_message: &str,
    ) -> String {
        if !configured {
            return "Not configured".to_owned();
        }
        let state_l = state.to_ascii_lowercase();
        let primary = if connected || state_l == "connected" {
            "Connected".to_owned()
        } else if state_l == "connecting" {
            "Connecting…".to_owned()
        } else if state_l == "retrying" {
            "Retrying…".to_owned()
        } else if state_l == "fatal" {
            "Failed".to_owned()
        } else if !error_message.is_empty() {
            "Not connected".to_owned()
        } else if !status.is_empty()
            && status != "enabled"
            && status != "disabled"
            && status != "not configured"
        {
            // Prefer runtime status text (may already include error).
            return status.to_owned();
        } else {
            "Not connected".to_owned()
        };
        if !error_message.is_empty() && !connected {
            format!("{primary} · {}", translate_platform_error(error_message))
        } else if !status.is_empty()
            && status != primary
            && status != "enabled"
            && status != "disabled"
            && !status.starts_with(&primary)
        {
            format!("{primary} · {status}")
        } else {
            primary
        }
    }

    fn summarize_gateway_lifecycle(
        operation: &str,
        life: Result<&serde_json::Value, &String>,
        status: Option<&serde_json::Value>,
    ) -> (String, String) {
        let verb = match operation {
            "start" => "start",
            "stop" => "stop",
            _ => "restart",
        };
        let life_ok = life
            .as_ref()
            .ok()
            .and_then(|p| p.get("ok"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        if !life_ok {
            let msg = match &life {
                Ok(p) => p
                    .get("message")
                    .or_else(|| p.get("error"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("Could not complete the gateway request."),
                Err(error) => error.as_str(),
            };
            return (
                format!("Gateway {verb} failed"),
                msg.to_owned(),
            );
        }
        let Some(status) = status else {
            return (
                format!("Gateway {verb}"),
                "Request sent, but status could not be read yet.".to_owned(),
            );
        };
        let running = status
            .pointer("/status/running")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let mut parts = Vec::new();
        parts.push(if running {
            "Gateway is running".to_owned()
        } else {
            "Gateway is stopped".to_owned()
        });
        if let Some(platforms) = status
            .pointer("/status/platforms")
            .and_then(|v| v.as_array())
        {
            for key in ["telegram", "whatsapp", "api_server"] {
                let Some(plat) = platforms.iter().find(|p| {
                    p.get("name")
                        .and_then(|v| v.as_str())
                        .map(|n| n.eq_ignore_ascii_case(key))
                        .unwrap_or(false)
                }) else {
                    continue;
                };
                if !plat
                    .get("enabled")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false)
                {
                    continue;
                }
                let label = match key {
                    "telegram" => "Telegram",
                    "whatsapp" => "WhatsApp",
                    _ => "Remote Control",
                };
                let connected = plat
                    .get("connected")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                let state = plat
                    .get("state")
                    .or_else(|| plat.get("status"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let err = plat
                    .get("error_message")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                if connected {
                    parts.push(format!("{label} connected"));
                } else if !err.is_empty() {
                    parts.push(format!("{label}: {err}"));
                } else if !state.is_empty() {
                    parts.push(format!("{label} {state}"));
                } else {
                    parts.push(format!("{label} not connected"));
                }
            }
        }
        let heading = match operation {
            "start" => "Gateway started",
            "stop" => "Gateway stopped",
            _ => "Gateway restarted",
        };
        (heading.to_owned(), parts.join("\n"))
    }

    fn run_gateway_lifecycle_with_feedback(
        parent: &adw::ApplicationWindow,
        row: &adw::ActionRow,
        platform_list: &gtk::ListBox,
        start_btn: &gtk::Button,
        stop_btn: &gtk::Button,
        restart_btn: &gtk::Button,
        operation: &str,
    ) {
        let busy = match operation {
            "start" => "Starting…",
            "stop" => "Stopping…",
            _ => "Restarting…",
        };
        row.set_subtitle(busy);
        start_btn.set_sensitive(false);
        stop_btn.set_sensitive(false);
        restart_btn.set_sensitive(false);

        let want_running = operation != "stop";
        let op = operation.to_owned();
        let action = format!("gateway_{op}");
        let (tx, rx) = std::sync::mpsc::channel::<(
            Result<serde_json::Value, String>,
            Option<serde_json::Value>,
        )>();
        std::thread::spawn(move || {
            let life = run_bridge_action_result(&action, serde_json::json!({}));
            let mut last = run_bridge_action("gateway_status", serde_json::json!({}));
            for _ in 0..25 {
                std::thread::sleep(std::time::Duration::from_secs(1));
                let status = run_bridge_action("gateway_status", serde_json::json!({}));
                if let Some(ref s) = status {
                    last = Some(s.clone());
                    let running = s
                        .pointer("/status/running")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false);
                    if running != want_running {
                        continue;
                    }
                    if !want_running {
                        break;
                    }
                    let still_connecting = s
                        .pointer("/status/platforms")
                        .and_then(|v| v.as_array())
                        .map(|arr| {
                            arr.iter().any(|p| {
                                let name = p
                                    .get("name")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("")
                                    .to_ascii_lowercase();
                                if !matches!(name.as_str(), "telegram" | "whatsapp" | "api_server")
                                {
                                    return false;
                                }
                                if !p
                                    .get("enabled")
                                    .and_then(|v| v.as_bool())
                                    .unwrap_or(false)
                                {
                                    return false;
                                }
                                let state = p
                                    .get("state")
                                    .or_else(|| p.get("status"))
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("")
                                    .to_ascii_lowercase();
                                state == "connecting"
                            })
                        })
                        .unwrap_or(false);
                    if !still_connecting {
                        break;
                    }
                }
            }
            let _ = tx.send((life, last));
        });

        let parent = parent.clone();
        let row = row.clone();
        let platform_list = platform_list.clone();
        let start_btn = start_btn.clone();
        let stop_btn = stop_btn.clone();
        let restart_btn = restart_btn.clone();
        let op_for_ui = op.clone();
        glib::timeout_add_local(std::time::Duration::from_millis(100), move || {
            match rx.try_recv() {
                Ok((life, status)) => {
                    apply_gateway_ui(&parent, &row, &platform_list, status.clone());
                    start_btn.set_sensitive(true);
                    stop_btn.set_sensitive(true);
                    restart_btn.set_sensitive(true);
                    let (heading, body) =
                        summarize_gateway_lifecycle(&op_for_ui, life.as_ref(), status.as_ref());
                    let dialog = adw::AlertDialog::builder()
                        .heading(&heading)
                        .body(&body)
                        .close_response("ok")
                        .build();
                    dialog.add_response("ok", "OK");
                    dialog.present(Some(&parent));
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    start_btn.set_sensitive(true);
                    stop_btn.set_sensitive(true);
                    restart_btn.set_sensitive(true);
                    row.set_subtitle("Gateway status unavailable.");
                    glib::ControlFlow::Break
                }
            }
        });
    }

    fn refresh_gateway_ui(
        parent: &adw::ApplicationWindow,
        row: &adw::ActionRow,
        platform_list: &gtk::ListBox,
    ) {
        let payload = run_bridge_action("gateway_status", serde_json::json!({}));
        apply_gateway_ui(parent, row, platform_list, payload);
    }

    /// Same as `refresh_gateway_ui`, with the bridge round-trip on a worker so
    /// window build / present never waits on it.
    fn refresh_gateway_ui_async(
        parent: &adw::ApplicationWindow,
        row: &adw::ActionRow,
        platform_list: &gtk::ListBox,
    ) {
        let parent = parent.clone();
        let row = row.clone();
        let platform_list = platform_list.clone();
        let (tx, rx) = std::sync::mpsc::channel::<Option<serde_json::Value>>();
        std::thread::spawn(move || {
            let _ = tx.send(run_bridge_action("gateway_status", serde_json::json!({})));
        });
        glib::timeout_add_local(std::time::Duration::from_millis(40), move || {
            match rx.try_recv() {
                Ok(payload) => {
                    apply_gateway_ui(&parent, &row, &platform_list, payload);
                    glib::ControlFlow::Break
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
            }
        });
    }

    fn apply_gateway_ui(
        parent: &adw::ApplicationWindow,
        row: &adw::ActionRow,
        platform_list: &gtk::ListBox,
        payload: Option<serde_json::Value>,
    ) {
        while let Some(child) = platform_list.first_child() {
            platform_list.remove(&child);
        }
        let Some(payload) = payload else {
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
        // Settings only surfaces the three messaging surfaces we want end users
        // to manage here — Telegram, Centurion Remote Control (api_server), WhatsApp.
        const SETTINGS_GATEWAY_PLATFORMS: &[&str] = &["telegram", "api_server", "whatsapp"];
        let platforms = payload
            .pointer("/status/platforms")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        let mut by_name: std::collections::HashMap<String, serde_json::Value> =
            std::collections::HashMap::new();
        for plat in platforms {
            let key = plat
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_ascii_lowercase();
            if SETTINGS_GATEWAY_PLATFORMS.contains(&key.as_str()) {
                by_name.insert(key, plat);
            }
        }
        for &key in SETTINGS_GATEWAY_PLATFORMS {
            let configured = by_name.contains_key(key);
            let (enabled, connected, state, status, error_message) = match by_name.get(key) {
                Some(plat) => (
                    plat.get("enabled")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                    plat.get("connected")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                    plat.get("state")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_owned(),
                    plat.get("status")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_owned(),
                    plat.get("error_message")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_owned(),
                ),
                None => (
                    false,
                    false,
                    String::new(),
                    "not configured".to_owned(),
                    String::new(),
                ),
            };
            let title = match key {
                "telegram" => "Telegram",
                "api_server" => "Centurion Remote Control",
                "whatsapp" => "WhatsApp",
                _ => key,
            };
            let subtitle = if key == "api_server" && !configured {
                "Not paired yet — tap Pair for the Remote QR (same Wi‑Fi).".to_owned()
            } else {
                gateway_platform_subtitle(
                    configured,
                    connected,
                    &state,
                    &status,
                    &error_message,
                )
            };
            let plat_row = adw::ActionRow::builder()
                .title(title)
                .subtitle(&subtitle)
                .build();

            // Setup actions — customers must not need a terminal.
            if key == "telegram" {
                let setup = gtk::Button::with_label(if configured {
                    "Update token"
                } else {
                    "Add token"
                });
                setup.set_valign(gtk::Align::Center);
                setup.add_css_class("suggested-action");
                let parent_w = parent.clone();
                let status_row = row.clone();
                let list_for_cb = platform_list.clone();
                setup.connect_clicked(move |_| {
                    show_telegram_token_dialog(&parent_w, &status_row, &list_for_cb);
                });
                plat_row.add_suffix(&setup);
            } else if key == "whatsapp" {
                let paired = configured
                    && (connected
                        || status.to_ascii_lowercase().contains("connected")
                        || status.to_ascii_lowercase().contains("ready"));
                let setup = gtk::Button::with_label(if paired {
                    "Reconnect"
                } else {
                    "Connect"
                });
                setup.set_valign(gtk::Align::Center);
                setup.add_css_class("suggested-action");
                let parent_w = parent.clone();
                let status_row = row.clone();
                let list_for_cb = platform_list.clone();
                let clear_session = paired;
                setup.connect_clicked(move |_| {
                    show_whatsapp_connect_wizard(
                        &parent_w,
                        &status_row,
                        &list_for_cb,
                        clear_session,
                    );
                });
                plat_row.add_suffix(&setup);
            } else if key == "api_server" {
                // Pairing lives under Updates → Remote pairing; surface the same
                // QR here so the Channels row does not look dead next to Telegram/WhatsApp.
                let setup = gtk::Button::with_label(if configured {
                    "Show QR"
                } else {
                    "Pair"
                });
                setup.set_valign(gtk::Align::Center);
                setup.add_css_class("suggested-action");
                setup.set_tooltip_text(Some(
                    "Open the Remote pairing QR (same Wi‑Fi). Approve under Connected Devices.",
                ));
                let parent_w = parent.clone();
                setup.connect_clicked(move |_| {
                    show_pairing_qr_window(&parent_w);
                });
                plat_row.add_suffix(&setup);
            }

            let toggle = gtk::Switch::builder()
                .active(enabled)
                .valign(gtk::Align::Center)
                .build();
            toggle.set_sensitive(configured);
            let platform_name = key.to_owned();
            let list_for_cb = platform_list.clone();
            let status_row = row.clone();
            let parent_w = parent.clone();
            if configured {
                toggle.connect_active_notify(move |sw| {
                    let enabled = sw.is_active();
                    // Optimistic UI — keep the switch where the user put it while we work.
                    sw.set_sensitive(false);
                    let platform_name = platform_name.clone();
                    let list_for_cb = list_for_cb.clone();
                    let status_row = status_row.clone();
                    let parent_w = parent_w.clone();
                    let sw = sw.clone();
                    crate::bridge_actions::run_bridge_action_async(
                        "gateway_platform_set",
                        serde_json::json!({
                            "platform": platform_name,
                            "enabled": enabled,
                            "restart": true,
                        }),
                        move |_payload: Option<serde_json::Value>| {
                            sw.set_sensitive(true);
                            refresh_gateway_ui_async(&parent_w, &status_row, &list_for_cb);
                        },
                    );
                });
            }
            plat_row.add_suffix(&toggle);
            platform_list.append(&plat_row);
        }
    }

    fn show_telegram_token_dialog(
        parent: &adw::ApplicationWindow,
        gateway_row: &adw::ActionRow,
        platform_list: &gtk::ListBox,
    ) {
        let dialog = adw::AlertDialog::builder()
            .heading("Telegram bot token")
            .body(
                "Create a bot with @BotFather in Telegram, copy the token, and paste it here. \
The token stays in ~/.centurion/.env on this machine only.",
            )
            .close_response("cancel")
            .default_response("save")
            .build();
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("save", "Save");
        dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);

        let extra = gtk::Box::new(gtk::Orientation::Vertical, 10);
        extra.add_css_class("centurion-dialog-body");
        let note = gtk::Label::builder()
            .label("In Telegram: open @BotFather → /newbot → copy the token.")
            .wrap(true)
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build();
        let key_entry = gtk::PasswordEntry::builder()
            .placeholder_text("123456:ABC-DEF…")
            .show_peek_icon(true)
            .build();
        extra.append(&note);
        extra.append(
            &gtk::Label::builder()
                .label("Bot token")
                .xalign(0.0)
                .build(),
        );
        extra.append(&key_entry);
        dialog.set_extra_child(Some(&extra));
        dialog.present(Some(parent));

        let parent = parent.clone();
        let gateway_row = gateway_row.clone();
        let platform_list = platform_list.clone();
        dialog.connect_response(None, move |dialog, response| {
            if response != "save" {
                dialog.close();
                return;
            }
            let token = key_entry.text().to_string();
            dialog.close();
            if token.trim().is_empty() {
                let fail = adw::AlertDialog::builder()
                    .heading("Token required")
                    .body("Paste the bot token from @BotFather, then try again.")
                    .close_response("ok")
                    .build();
                fail.add_response("ok", "OK");
                fail.present(Some(&parent));
                return;
            }
            let token = token.trim().to_owned();
            let parent = parent.clone();
            let gateway_row = gateway_row.clone();
            let platform_list = platform_list.clone();
            crate::bridge_actions::run_bridge_async(
                move || {
                    crate::bridge_actions::run_bridge_action_result(
                        "telegram_configure",
                        serde_json::json!({
                            "token": token,
                            "restart": true,
                        }),
                    )
                },
                move |result: Result<serde_json::Value, String>| {
                    // The reason matters. `run_bridge_action` drops it, which is
                    // how a real client saw only "Could not save token" with no
                    // cause: a bridge that never answered and a handler that
                    // refused both arrived as the same shrug.
                    let payload = match result {
                        Ok(payload) => payload,
                        Err(err) => {
                            let fail = adw::AlertDialog::builder()
                                .heading("Could not save token")
                                .body(format!(
                                    "{err}\n\nIf that came after a long pause the token may \
already be saved — reopen this window and check the Telegram row before trying again."
                                ))
                                .close_response("ok")
                                .build();
                            fail.add_response("ok", "OK");
                            fail.present(Some(&parent));
                            return;
                        }
                    };
                    let ok = payload
                        .get("ok")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false);
                    if ok {
                        refresh_gateway_ui_async(&parent, &gateway_row, &platform_list);
                        let done = adw::AlertDialog::builder()
                            .heading("Telegram connected")
                            .body(
                                "Bot token saved. Start the gateway if it is stopped, then message your bot.",
                            )
                            .close_response("ok")
                            .build();
                        done.add_response("ok", "OK");
                        done.present(Some(&parent));
                        return;
                    }
                    let message = payload
                        .get("message")
                        .or_else(|| payload.get("error"))
                        .and_then(|v| v.as_str())
                        .map(str::to_owned)
                        .unwrap_or_else(|| "Could not save Telegram bot token.".to_owned());
                    let fail = adw::AlertDialog::builder()
                        .heading("Could not save token")
                        .body(&message)
                        .close_response("ok")
                        .build();
                    fail.add_response("ok", "OK");
                    fail.present(Some(&parent));
                },
            );
        });
    }

    fn show_whatsapp_connect_wizard(
        parent: &adw::ApplicationWindow,
        gateway_row: &adw::ActionRow,
        platform_list: &gtk::ListBox,
        clear_session: bool,
    ) {
        let win = adw::Window::builder()
            .transient_for(parent)
            .modal(true)
            .default_width(520)
            .default_height(640)
            .title("Connect WhatsApp")
            .build();
        let header = adw::HeaderBar::new();
        let close_btn = gtk::Button::with_label("Close");
        header.pack_start(&close_btn);

        let stack = gtk::Stack::builder()
            .transition_type(gtk::StackTransitionType::SlideLeftRight)
            .vhomogeneous(false)
            .build();

        // --- Intro: why WhatsApp + how linking works ---
        let intro = gtk::Box::new(gtk::Orientation::Vertical, 14);
        intro.set_margin_top(20);
        intro.set_margin_bottom(20);
        intro.set_margin_start(28);
        intro.set_margin_end(28);
        intro.append(
            &gtk::Label::builder()
                .label("Why WhatsApp is a great channel")
                .css_classes(["title-2"])
                .xalign(0.0)
                .wrap(true)
                .build(),
        );
        intro.append(
            &gtk::Label::builder()
                .label(
                    "WhatsApp is the most personal, always-on messaging app people already live in. \
No new app to install, no desktop required, no mental overhead — Centurion shows up in the same \
thread where family and close contacts chat. It is familiar, trusted, and carries rich context \
(voice notes, images, documents).\n\n\
For a sovereign personal AI, that is the difference between a tool you open and a presence you \
talk to. The agent comes to the human's current — rather than asking the human to come to it.",
                )
                .wrap(true)
                .xalign(0.0)
                .build(),
        );
        intro.append(
            &gtk::Label::builder()
                .label("How connection works")
                .css_classes(["title-3"])
                .xalign(0.0)
                .margin_top(8)
                .build(),
        );
        intro.append(
            &gtk::Label::builder()
                .label(
                    "You scan a QR code from this brain. Centurion runs as a WhatsApp client on \
your own hardware — messages stay in your perimeter. No cloud relay, no third party reading the thread.\n\n\
On your phone: WhatsApp → Settings → Linked devices → Link a device. After you scan, this wizard \
waits until Connected ✓ appears, then registers WhatsApp as a home channel.",
                )
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );
        let continue_btn = gtk::Button::with_label("Continue to QR");
        continue_btn.add_css_class("suggested-action");
        continue_btn.set_halign(gtk::Align::Start);
        continue_btn.set_margin_top(8);
        intro.append(&continue_btn);
        let intro_scroll = gtk::ScrolledWindow::builder()
            .vexpand(true)
            .hexpand(true)
            .child(&intro)
            .build();
        stack.add_named(&intro_scroll, Some("intro"));

        // --- QR scan step ---
        let qr_page = gtk::Box::new(gtk::Orientation::Vertical, 12);
        qr_page.set_margin_top(20);
        qr_page.set_margin_bottom(20);
        qr_page.set_margin_start(28);
        qr_page.set_margin_end(28);
        qr_page.append(
            &gtk::Label::builder()
                .label("Link a device")
                .css_classes(["title-2"])
                .xalign(0.0)
                .build(),
        );
        qr_page.append(
            &gtk::Label::builder()
                .label(
                    "1. Open WhatsApp on your phone\n\
2. Go to Settings → Linked devices → Link a device\n\
3. Scan the QR code below",
                )
                .wrap(true)
                .xalign(0.0)
                .build(),
        );
        let qr_status = gtk::Label::builder()
            .label("Preparing a secure QR on this brain…")
            .wrap(true)
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build();
        qr_page.append(&qr_status);
        let qr_holder = gtk::Box::new(gtk::Orientation::Vertical, 8);
        qr_holder.set_halign(gtk::Align::Center);
        qr_holder.set_vexpand(true);
        qr_page.append(&qr_holder);
        let regenerate_btn = gtk::Button::with_label("Regenerate QR");
        regenerate_btn.set_halign(gtk::Align::Center);
        regenerate_btn.set_sensitive(false);
        qr_page.append(&regenerate_btn);
        qr_page.append(
            &gtk::Label::builder()
                .label("If the code expires or looks blank, tap Regenerate QR.")
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );
        let qr_scroll = gtk::ScrolledWindow::builder()
            .vexpand(true)
            .hexpand(true)
            .child(&qr_page)
            .build();
        stack.add_named(&qr_scroll, Some("qr"));

        // --- Done step ---
        let done_page = gtk::Box::new(gtk::Orientation::Vertical, 12);
        done_page.set_margin_top(20);
        done_page.set_margin_bottom(20);
        done_page.set_margin_start(28);
        done_page.set_margin_end(28);
        done_page.append(
            &gtk::Label::builder()
                .label("Connected ✓")
                .css_classes(["title-2"])
                .xalign(0.0)
                .build(),
        );
        let done_identity = gtk::Label::builder()
            .label("WhatsApp is now a home channel for this Centurion.")
            .wrap(true)
            .xalign(0.0)
            .build();
        done_page.append(&done_identity);
        done_page.append(
            &gtk::Label::builder()
                .label(
                    "Your phone must stay online for the link to remain active \
(WhatsApp requirement). Keep WhatsApp installed and connected on that phone.",
                )
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );
        let test_btn = gtk::Button::with_label("Send a test message");
        test_btn.add_css_class("suggested-action");
        test_btn.set_halign(gtk::Align::Start);
        test_btn.set_margin_top(8);
        done_page.append(&test_btn);
        let done_finish = gtk::Button::with_label("Done");
        done_finish.set_halign(gtk::Align::Start);
        done_page.append(&done_finish);
        let done_scroll = gtk::ScrolledWindow::builder()
            .vexpand(true)
            .hexpand(true)
            .child(&done_page)
            .build();
        stack.add_named(&done_scroll, Some("done"));
        stack.set_visible_child_name("intro");

        let toolbar = adw::ToolbarView::new();
        toolbar.add_top_bar(&header);
        toolbar.set_content(Some(&stack));
        win.set_content(Some(&toolbar));

        let pairing_started = Rc::new(Cell::new(false));
        let clear_on_start = Rc::new(Cell::new(clear_session));
        let last_qr = Rc::new(RefCell::new(String::new()));
        let linked_display = Rc::new(RefCell::new(String::new()));
        let poll_active = Rc::new(Cell::new(false));
        let tick = Rc::new(Cell::new(0u32));

        let start_pairing = Rc::new({
            let qr_status = qr_status.clone();
            let qr_holder = qr_holder.clone();
            let regenerate_btn = regenerate_btn.clone();
            let pairing_started = pairing_started.clone();
            let clear_on_start = clear_on_start.clone();
            let last_qr = last_qr.clone();
            let poll_active = poll_active.clone();
            let tick = tick.clone();
            move || {
                poll_active.set(true);
                tick.set(0);
                while let Some(child) = qr_holder.first_child() {
                    qr_holder.remove(&child);
                }
                last_qr.borrow_mut().clear();
                qr_status.set_label("Preparing a secure QR on this brain…");
                regenerate_btn.set_sensitive(false);
                let clear = clear_on_start.get();
                // After the first start, regenerates clear the session so Baileys
                // can mint a fresh QR instead of reusing a dead one.
                clear_on_start.set(true);
                pairing_started.set(true);
                let qr_status = qr_status.clone();
                let regenerate_btn = regenerate_btn.clone();
                crate::bridge_actions::run_bridge_action_async(
                    "whatsapp_pair_start",
                    serde_json::json!({ "clear_session": clear }),
                    move |payload: Option<serde_json::Value>| {
                        if let Some(p) = payload {
                            if p.get("ok").and_then(|v| v.as_bool()) != Some(true) {
                                let msg = p
                                    .get("message")
                                    .or_else(|| p.get("error"))
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("Could not start WhatsApp pairing.");
                                qr_status.set_label(msg);
                            }
                        } else {
                            qr_status
                                .set_label("Could not reach the local bridge to start pairing.");
                        }
                        regenerate_btn.set_sensitive(true);
                    },
                );
            }
        });

        continue_btn.connect_clicked({
            let stack = stack.clone();
            let start_pairing = start_pairing.clone();
            let pairing_started = pairing_started.clone();
            move |_| {
                stack.set_visible_child_name("qr");
                if !pairing_started.get() {
                    start_pairing();
                }
            }
        });

        regenerate_btn.connect_clicked({
            let start_pairing = start_pairing.clone();
            move |_| start_pairing()
        });

        // Poll while the QR page is active (or until paired / closed).
        // Bridge I/O stays off the GTK thread — only apply results on the UI loop.
        let status_c = qr_status.clone();
        let qr_holder_c = qr_holder.clone();
        let gateway_row_c = gateway_row.clone();
        let platform_list_c = platform_list.clone();
        let parent_c = parent.clone();
        let win_c = win.clone();
        let stack_c = stack.clone();
        let done_identity_c = done_identity.clone();
        let linked_display_c = linked_display.clone();
        let last_qr_c = last_qr.clone();
        let poll_active_c = poll_active.clone();
        let tick_c = tick.clone();
        let poll_in_flight = Rc::new(Cell::new(false));
        let poll_in_flight_c = poll_in_flight.clone();
        glib::timeout_add_local(std::time::Duration::from_millis(1200), move || {
            if !win_c.is_visible() {
                crate::bridge_actions::run_bridge_action_async(
                    "whatsapp_pair_cancel",
                    serde_json::json!({}),
                    |_| {},
                );
                return glib::ControlFlow::Break;
            }
            if !poll_active_c.get() {
                return glib::ControlFlow::Continue;
            }
            // Once we reach the done page, stop pairing work but keep the window.
            if stack_c.visible_child_name().as_deref() == Some("done") {
                return glib::ControlFlow::Continue;
            }
            if poll_in_flight_c.get() {
                return glib::ControlFlow::Continue;
            }
            poll_in_flight_c.set(true);
            let status_c = status_c.clone();
            let qr_holder_c = qr_holder_c.clone();
            let gateway_row_c = gateway_row_c.clone();
            let platform_list_c = platform_list_c.clone();
            let parent_c = parent_c.clone();
            let stack_c = stack_c.clone();
            let done_identity_c = done_identity_c.clone();
            let linked_display_c = linked_display_c.clone();
            let last_qr_c = last_qr_c.clone();
            let poll_active_c = poll_active_c.clone();
            let tick_c = tick_c.clone();
            let poll_in_flight_c = poll_in_flight_c.clone();
            crate::bridge_actions::run_bridge_action_async(
                "whatsapp_pair_status",
                serde_json::json!({}),
                move |payload: Option<serde_json::Value>| {
                    poll_in_flight_c.set(false);
                    let Some(payload) = payload else {
                        return;
                    };
                    let state = payload
                        .get("state")
                        .and_then(|v| v.as_str())
                        .unwrap_or("idle");
                    let message = payload
                        .get("message")
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    if !message.is_empty() && stack_c.visible_child_name().as_deref() == Some("qr") {
                        status_c.set_label(message);
                    }
                    if payload
                        .get("paired")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false)
                        || state == "paired"
                    {
                        while let Some(child) = qr_holder_c.first_child() {
                            qr_holder_c.remove(&child);
                        }
                        let display = payload
                            .get("display")
                            .or_else(|| payload.get("identity"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("your WhatsApp account");
                        *linked_display_c.borrow_mut() = display.to_owned();
                        let jid = payload
                            .get("identity")
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        let identity_line = if jid.is_empty() {
                            format!(
                                "Linked number: {display}\nMessages to this account now route into Centurion."
                            )
                        } else {
                            format!(
                                "Linked identity: {display}\nWhatsApp JID: {jid}\n\
Messages to this account now route into your Centurion conversation."
                            )
                        };
                        done_identity_c.set_label(&identity_line);
                        status_c.set_label("Starting messaging gateway…");
                        refresh_gateway_ui_async(&parent_c, &gateway_row_c, &platform_list_c);
                        let status_c2 = status_c.clone();
                        crate::bridge_actions::run_bridge_action_async(
                            "gateway_start",
                            serde_json::json!({}),
                            move |_| {
                                status_c2.set_label("WhatsApp linked.");
                            },
                        );
                        stack_c.set_visible_child_name("done");
                        return;
                    }
                    if let Some(b64) = payload.get("qr_png_base64").and_then(|v| v.as_str()) {
                        if *last_qr_c.borrow() != b64 {
                            *last_qr_c.borrow_mut() = b64.to_owned();
                            let png = glib::base64_decode(b64);
                            if !png.is_empty() {
                                while let Some(child) = qr_holder_c.first_child() {
                                    qr_holder_c.remove(&child);
                                }
                                qr_holder_c.append(&qr_image_from_png(&png, 300));
                            }
                        }
                    }
                    let n = tick_c.get().saturating_add(1);
                    tick_c.set(n);
                    if n > 0 && n % 50 == 0 && stack_c.visible_child_name().as_deref() == Some("qr")
                    {
                        // ~60s hint — WhatsApp QR codes expire.
                        status_c.set_label(
                            "Still waiting for a scan. If the QR looks expired, tap Regenerate QR.",
                        );
                    }
                    if n > 250 {
                        status_c.set_label(
                            "Pairing timed out. Tap Regenerate QR to try again, or Close and return later.",
                        );
                        crate::bridge_actions::run_bridge_action_async(
                            "whatsapp_pair_cancel",
                            serde_json::json!({}),
                            |_| {},
                        );
                        poll_active_c.set(false);
                    }
                },
            );
            glib::ControlFlow::Continue
        });

        test_btn.connect_clicked({
            let parent = parent.clone();
            let linked_display = linked_display.clone();
            move |_| {
                crate::bridge_actions::run_bridge_action_async(
                    "gateway_start",
                    serde_json::json!({}),
                    |_| {},
                );
                let who = linked_display.borrow().clone();
                let body = if who.is_empty() {
                    "Open WhatsApp on your phone and send yourself a short message \
(or message this Centurion account). You should get a reply in the same thread once the gateway is running."
                        .to_owned()
                } else {
                    format!(
                        "Open WhatsApp and send a short message to {who} \
(or message yourself if this is your own number). Centurion should reply in that thread once the gateway is running."
                    )
                };
                let dialog = adw::AlertDialog::builder()
                    .heading("Try a test message")
                    .body(&body)
                    .close_response("ok")
                    .build();
                dialog.add_response("ok", "OK");
                dialog.present(Some(&parent));
            }
        });

        done_finish.connect_clicked({
            let win = win.clone();
            move |_| win.close()
        });

        close_btn.connect_clicked({
            let win = win.clone();
            let stack = stack.clone();
            move |_| {
                if stack.visible_child_name().as_deref() != Some("done") {
                    crate::bridge_actions::run_bridge_action_async(
                        "whatsapp_pair_cancel",
                        serde_json::json!({}),
                        |_| {},
                    );
                }
                win.close();
            }
        });
        win.connect_close_request({
            let stack = stack.clone();
            move |_| {
                if stack.visible_child_name().as_deref() != Some("done") {
                    crate::bridge_actions::run_bridge_action_async(
                        "whatsapp_pair_cancel",
                        serde_json::json!({}),
                        |_| {},
                    );
                }
                glib::Propagation::Proceed
            }
        });
        win.present();
    }

    fn show_support_auto_fix_dialog(parent: &adw::ApplicationWindow) {
        let payload = run_bridge_action_result("support_auto_fix", serde_json::json!({}));
        let (heading, body) = match payload {
            Ok(p) if p.get("ok").and_then(|v| v.as_bool()) == Some(true) => (
                "Auto-fix finished",
                p.get("message")
                    .and_then(|v| v.as_str())
                    .unwrap_or("Recovery steps completed.")
                    .to_owned(),
            ),
            Ok(p) => (
                "Auto-fix could not finish",
                p.get("message")
                    .and_then(|v| v.as_str())
                    .unwrap_or("See health check for details.")
                    .to_owned(),
            ),
            Err(error) => ("Auto-fix unavailable", error),
        };
        let dialog = adw::AlertDialog::builder()
            .heading(heading)
            .body(&body)
            .close_response("ok")
            .build();
        dialog.add_response("ok", "OK");
        dialog.present(Some(parent));
    }


    fn show_skills_tools_dialog(
        parent: &adw::ApplicationWindow,
        open_chat: Rc<dyn Fn(String, String)>,
    ) {
        let payload = run_bridge_action_result("tools_skills_snapshot", serde_json::json!({}));
        let (body, hub_blocked) = match payload {
            Ok(p) if p.get("ok").and_then(|v| v.as_bool()) == Some(true) => {
                let tools = p
                    .get("toolsets")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                let self_built = p
                    .get("self_built")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                let bundled = p
                    .get("bundled")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                let hub_ref = p
                    .get("hub_reference")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                let allow_hub = p
                    .pointer("/policy/allow_public_hub")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                let mut lines = vec![
                    if allow_hub {
                        "Policy: public hub installs are allowed on this Brain. Prefer creating local skills when you can."
                            .to_owned()
                    } else {
                        "Policy: only trust skills this Brain built. Public hub installs are blocked — search for inspiration, then ask Centurion to create a fresh local skill."
                            .to_owned()
                    },
                    String::new(),
                    "Self-built (trusted):".to_owned(),
                ];
                if self_built.is_empty() {
                    lines.push("• (none yet — ask Centurion to create one)".to_owned());
                } else {
                    for s in self_built.iter().take(24) {
                        let name = s
                            .get("name")
                            .and_then(|v| v.as_str())
                            .unwrap_or("?");
                        lines.push(format!("• {name}"));
                    }
                }
                lines.push(String::new());
                lines.push("Reference only (do not trust — ask Centurion to rewrite locally):".to_owned());
                let mut ref_count = 0usize;
                for s in bundled.iter().chain(hub_ref.iter()).take(24) {
                    let name = s
                        .get("name")
                        .and_then(|v| v.as_str())
                        .unwrap_or("?");
                    let bucket = s
                        .get("bucket")
                        .and_then(|v| v.as_str())
                        .unwrap_or("reference");
                    lines.push(format!("• {name} ({bucket})"));
                    ref_count += 1;
                }
                if ref_count == 0 {
                    lines.push("• (none listed — bundled skills may still load as needed)".to_owned());
                }
                lines.push(String::new());
                lines.push("Toolsets:".to_owned());
                if tools.is_empty() {
                    lines.push("• (none listed)".to_owned());
                } else {
                    for t in tools.iter().take(24) {
                        let name = t.as_str().unwrap_or("?");
                        lines.push(format!("• {name}"));
                    }
                }
                (lines.join("\n"), !allow_hub)
            }
            Ok(p) => (
                p.get("message")
                    .and_then(|v| v.as_str())
                    .unwrap_or("Could not list skills/tools.")
                    .to_owned(),
                true,
            ),
            Err(error) => (error, true),
        };
        let dialog = adw::AlertDialog::builder()
            .heading("Skills &amp; tools")
            .body(&body)
            .close_response("close")
            .default_response("create")
            .build();
        dialog.add_response("close", "Close");
        dialog.add_response("create", "Ask Centurion to create a skill…");
        dialog.set_response_appearance("create", adw::ResponseAppearance::Suggested);
        let _ = hub_blocked;
        let open_chat = open_chat.clone();
        dialog.connect_response(None, move |_d, response| {
            if response != "create" {
                return;
            }
            let title = "Create a local skill".to_owned();
            let detail = "Please create a fresh local skill for this Brain using skill_manage \
(action='create'). Do not install community/public hub skills. I may describe inspiration \
from elsewhere, but only save a skill this Centurion writes on this machine.\n\n\
What capability should the skill cover?\n\n"
                .to_owned();
            open_chat(title, detail);
        });
        dialog.present(Some(parent));
    }

    fn show_license_dialog(parent: &adw::ApplicationWindow) {
        let payload = match run_bridge_action_result("license_status", serde_json::json!({})) {
            Ok(payload) => Some(payload),
            Err(error) => {
                let dialog = adw::AlertDialog::builder()
                    .heading("License")
                    .body(format!("{error}\n\nCould not read license status."))
                    .close_response("close")
                    .build();
                dialog.add_response("close", "Close");
                dialog.present(Some(parent));
                return;
            }
        };
        let can_redeem = payload
            .as_ref()
            .and_then(|p| p.get("ok").and_then(|v| v.as_bool()))
            == Some(true);
        let body = match &payload {
            Some(p) => {
                let enabled = p
                    .pointer("/status/enabled")
                    .or_else(|| p.pointer("/license/enabled"))
                    .or_else(|| p.get("enabled"))
                    .and_then(|v| v.as_bool())
                    .unwrap_or(true);
                if !enabled {
                    "License enforcement is off on this Brain (BYOK / contributor mode). No key required.".to_owned()
                } else {
                    let state = p
                        .pointer("/status/state")
                        .or_else(|| p.pointer("/license/state"))
                        .or_else(|| p.get("state"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("unknown");
                    let plan = p
                        .pointer("/status/plan")
                        .or_else(|| p.pointer("/license/tier"))
                        .or_else(|| p.get("plan"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    let expires = p
                        .pointer("/status/expires_at")
                        .or_else(|| p.get("expires_at"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    let message = p
                        .pointer("/license/message")
                        .or_else(|| p.get("message"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    let paid = p
                        .pointer("/license/balance_paid_gbp")
                        .and_then(|v| v.as_f64());
                    let target = p
                        .pointer("/license/balance_target_gbp")
                        .and_then(|v| v.as_f64());
                    let mut lines = vec![format!("Status: {state}")];
                    if !plan.is_empty() {
                        lines.push(format!("Plan: {plan}"));
                    }
                    if let (Some(pmt), Some(tgt)) = (paid, target) {
                        if tgt > 0.0 {
                            lines.push(format!("Rent-to-own: £{pmt:.0} of £{tgt:.0}"));
                        }
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
                let outcome = run_bridge_action_result(
                    "license_activate",
                    serde_json::json!({ "tier": "trial", "days": 14 }),
                );
                let payload = match outcome {
                    Ok(payload) => payload,
                    Err(reason) => {
                        let fail = adw::AlertDialog::builder()
                            .heading("Trial could not start")
                            .body(format!(
                                "{reason}\n\nOpen Get Help in Settings and create a Support Code, \
then support can check the licence service on this machine and you can try again."
                            ))
                            .close_response("ok")
                            .build();
                        fail.add_response("ok", "OK");
                        fail.present(Some(&parent_for_cb));
                        return;
                    }
                };
                let ok = payload
                    .get("ok")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                if ok {
                    let msg = payload
                        .get("message")
                        .and_then(|v| v.as_str())
                        .unwrap_or("Trial activation finished.")
                        .to_owned();
                    let done = adw::AlertDialog::builder()
                        .heading("Trial")
                        .body(&msg)
                        .close_response("ok")
                        .build();
                    done.add_response("ok", "OK");
                    done.present(Some(&parent_for_cb));
                } else {
                    let reason = payload
                        .get("message")
                        .or_else(|| payload.get("error"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("The Brain did not confirm the trial was started.");
                    let fail = adw::AlertDialog::builder()
                        .heading("Trial could not start")
                        .body(format!(
                            "{reason}\n\nOpen Get Help in Settings and create a Support Code, \
then support can check the licence service on this machine and you can try again."
                        ))
                        .close_response("ok")
                        .build();
                    fail.add_response("ok", "OK");
                    fail.present(Some(&parent_for_cb));
                }
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
                    let outcome = if is_activate {
                        run_bridge_action_result(
                            "license_activate",
                            // Code-driven: server returns real tier/state (not a synthetic "paid").
                            serde_json::json!({ "tier": "code", "code": code }),
                        )
                    } else {
                        run_bridge_action_result(
                            "license_redeem",
                            serde_json::json!({ "token": code }),
                        )
                    };
                    let verb = if is_activate { "activate" } else { "redeem" };
                    let payload = match outcome {
                        Ok(payload) => payload,
                        Err(reason) => {
                            let fail = adw::AlertDialog::builder()
                                .heading(format!("Could not {verb} the license"))
                                .body(format!(
                                    "{reason}\n\nCheck the code was copied complete, then try \
again. If it still fails, open Get Help in Settings and create a Support Code."
                                ))
                                .close_response("ok")
                                .build();
                            fail.add_response("ok", "OK");
                            fail.present(Some(&parent_for_redeem));
                            return;
                        }
                    };
                    let ok = payload
                        .get("ok")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false);
                    if ok {
                        let msg = payload
                            .get("message")
                            .and_then(|v| v.as_str())
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
                    } else {
                        let reason = payload
                            .get("message")
                            .or_else(|| payload.get("error"))
                            .and_then(|v| v.as_str())
                            .unwrap_or(if is_activate {
                                "The Brain did not confirm the activation."
                            } else {
                                "The Brain did not confirm the redeem."
                            });
                        let fail = adw::AlertDialog::builder()
                            .heading(format!("Could not {verb} the license"))
                            .body(format!(
                                "{reason}\n\nCheck the code was copied complete, then try again. \
If it still fails, open Get Help in Settings and create a Support Code."
                            ))
                            .close_response("ok")
                            .build();
                        fail.add_response("ok", "OK");
                        fail.present(Some(&parent_for_redeem));
                    }
                });
                redeem.present(Some(&parent_for_present));
            }
            _ => {}
        });
        dialog.present(Some(parent));
    }

    fn show_beneficiary_dialog(parent: &adw::ApplicationWindow) {
        let snapshot = run_bridge_action_result("beneficiary_snapshot", serde_json::json!({}));
        let summary = match snapshot
            .as_ref()
            .ok()
            .and_then(|p| p.get("snapshot"))
            .or_else(|| snapshot.as_ref().ok())
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
            None => match &snapshot {
                Err(error) => format!("Could not load Family Beneficiary state — {error}"),
                Ok(_) => "Could not load Family Beneficiary state.".to_owned(),
            },
        };
        let first = gtk::Entry::builder()
            .placeholder_text("Family beneficiary first name")
            .hexpand(true)
            .build();
        let colleague_name = gtk::Entry::builder()
            .placeholder_text("Colleague name")
            .hexpand(true)
            .build();
        let colleague_email = gtk::Entry::builder()
            .placeholder_text("Colleague email")
            .hexpand(true)
            .build();
        let colleague_phone = gtk::Entry::builder()
            .placeholder_text("Colleague phone")
            .hexpand(true)
            .build();
        let attest = gtk::CheckButton::with_label(
            "This is a friend or colleague, not a family member",
        );
        let form = gtk::Box::new(gtk::Orientation::Vertical, 8);
        form.append(
            &gtk::Label::builder()
                .label(&summary)
                .wrap(true)
                .xalign(0.0)
                .selectable(true)
                .build(),
        );
        form.append(
            &gtk::Label::builder()
                .label("Nominations and colleague leads sync to DrivenAction when this Brain is configured.")
                .wrap(true)
                .xalign(0.0)
                .css_classes(["dim-label"])
                .build(),
        );
        form.append(&first);
        form.append(&colleague_name);
        form.append(&colleague_email);
        form.append(&colleague_phone);
        form.append(&attest);
        let dialog = adw::AlertDialog::builder()
            .heading("Family Beneficiary")
            .body("Nominate a family member, or capture a colleague lead (name plus email or phone).")
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
                    let _ = run_bridge_action(
                        "beneficiary_submit_colleague",
                        serde_json::json!({
                            "name": colleague_name.text().trim().to_string(),
                            "email": colleague_email.text().trim().to_string(),
                            "phone": colleague_phone.text().trim().to_string(),
                            "non_family_attested": attest.is_active(),
                        }),
                    );
                }
                _ => {}
            }
        });
        dialog.present(Some(parent));
    }

    /// Group a secret into fours so it can be read aloud over a phone line
    /// without losing your place. Display only — Copy takes the raw value.
    fn group_for_reading(value: &str) -> String {
        let mut out = String::with_capacity(value.len() + value.len() / 4);
        for (i, ch) in value.chars().enumerate() {
            if i > 0 && i % 4 == 0 {
                out.push(' ');
            }
            out.push(ch);
        }
        out
    }

    fn section_heading(text: &str) -> gtk::Label {
        gtk::Label::builder()
            .label(text)
            .xalign(0.0)
            .css_classes(["heading"])
            .build()
    }

    fn hint(text: &str) -> gtk::Label {
        gtk::Label::builder()
            .label(text)
            .wrap(true)
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build()
    }

    /// A row showing one value with a Copy button. The label shows the readable
    /// form; Copy takes the raw value, because a secret with spaces in it will
    /// not be accepted on the other side.
    fn secret_row(title: &str, raw: &str, readable: bool) -> gtk::Box {
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
        let shown = if readable { group_for_reading(raw) } else { raw.to_owned() };
        labels.append(
            &gtk::Label::builder()
                .label(&shown)
                .selectable(true)
                .wrap(true)
                .xalign(0.0)
                .build(),
        );
        row.append(&labels);
        let copy = gtk::Button::with_label("Copy");
        copy.add_css_class("flat");
        copy.set_valign(gtk::Align::Center);
        let raw_owned = raw.to_owned();
        copy.connect_clicked(move |_| copy_to_clipboard(&raw_owned));
        row.append(&copy);
        row
    }

    /// Redraw the two values this Centurion hands out.
    ///
    /// Called once when the screen opens, and again the moment reachability is
    /// switched on. Without the redraw the customer presses the button, the
    /// Brain starts listening, and the values they are supposed to read out
    /// stay blank — indistinguishable from a dead button.
    fn fill_peer_values(container: &gtk::Box, address: &str, secret: &str) {
        while let Some(child) = container.first_child() {
            container.remove(&child);
        }
        if address.is_empty() {
            container.append(&hint(
                "This Centurion is not reachable yet — press the button below, and \
leave the Brain open.",
            ));
        } else {
            container.append(&secret_row("Address", address, false));
        }
        if secret.is_empty() {
            container.append(&hint(
                "No shared secret yet — press the button below to create one.",
            ));
        } else {
            container.append(&secret_row("Secret", secret, true));
            container.append(&hint(
                "The secret is shown in groups of four so it can be read aloud. Copy takes \
the whole thing. Both Centurions must use the same secret.",
            ));
        }
    }

    /// Restart the Brain's gateway so settings saved from this screen take
    /// effect. The listener only binds when the gateway starts, so without this
    /// the values sit on disk and nothing changes until the customer restarts.
    fn restart_gateway_best_effort() -> bool {
        for unit in ["centurion-gateway.service", "centurion-gateway"] {
            let ok = std::process::Command::new("systemctl")
                .args(["--user", "restart", unit])
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
            if ok {
                return true;
            }
        }
        false
    }

    /// Connect another Centurion on the same network.
    ///
    /// One screen, two halves: what THIS Brain hands out, and where the other
    /// Brain's details go. The previous dialog only accepted peer details and
    /// told the customer to fetch them from "Collaborations → Invite another
    /// owner → Make this Brain reachable" — a screen that does not exist — so
    /// neither side could produce the two values, and a live call had nowhere
    /// to go.
    fn show_fleet_peer_dialog(parent: &adw::ApplicationWindow) {
        let form = gtk::Box::new(gtk::Orientation::Vertical, 14);
        form.set_width_request(560);

        let status = run_bridge_action("fleet_peer_status", serde_json::json!({}));
        let get_str = |key: &str| -> String {
            status
                .as_ref()
                .and_then(|p| p.get(key).and_then(|v| v.as_str()))
                .unwrap_or("")
                .to_owned()
        };
        let my_address = get_str("address");
        let my_secret = get_str("secret");
        let listening = status
            .as_ref()
            .and_then(|p| p.get("listening").and_then(|v| v.as_bool()))
            .unwrap_or(false);

        // ---- 1. What this Centurion gives out ---------------------------
        //
        // Built into its own box and refreshed in place: the values only exist
        // AFTER the button is pressed, so a screen that renders them once at
        // open shows "not reachable yet" for ever — the customer presses the
        // button, the Brain starts listening, and the two values they need are
        // still blank. That reads as "the button does nothing".
        form.append(&section_heading("1 · Give these two values to the other person"));
        let values_box = gtk::Box::new(gtk::Orientation::Vertical, 6);
        form.append(&values_box);
        fill_peer_values(&values_box, &my_address, &my_secret);

        let status_line = hint(if listening {
            "This Centurion is reachable on your network."
        } else {
            "Not reachable yet — press the button below, and leave the Brain open."
        });
        form.append(&status_line);

        let enable_button = gtk::Button::with_label("Make this Centurion reachable");
        enable_button.add_css_class("suggested-action");
        enable_button.set_halign(gtk::Align::Start);
        enable_button.set_visible(!listening);
        form.append(&enable_button);

        // ---- 2. The other Centurion's values ----------------------------
        form.append(&section_heading("2 · Enter the other person's two values"));
        form.append(&hint(
            "They give you the same two values from the same screen on their machine. \
The name is just so you can tell your Centurions apart — anything readable will do.",
        ));
        let name_entry = gtk::Entry::builder()
            .placeholder_text("Their name (e.g. Eve)")
            .hexpand(true)
            .build();
        let address_entry = gtk::Entry::builder()
            .placeholder_text("Their address (e.g. http://192.168.10.42:18789)")
            .hexpand(true)
            .build();
        let secret_entry = gtk::PasswordEntry::builder()
            .placeholder_text("Their secret (spaces are ignored)")
            .show_peek_icon(true)
            .hexpand(true)
            .build();
        form.append(&name_entry);
        form.append(&address_entry);
        form.append(&secret_entry);

        // ---- Existing peers ---------------------------------------------
        if let Some(resp) = run_bridge_action("fleet_status", serde_json::json!({})) {
            let peers = resp
                .get("peers")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default();
            if !peers.is_empty() {
                form.append(&section_heading("Already connected"));
                for peer in peers.iter().take(12) {
                    let name = peer
                        .get("name")
                        .or_else(|| peer.get("id"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("peer");
                    let peer_status = peer
                        .get("status")
                        .and_then(|v| v.as_str())
                        .unwrap_or("unknown");
                    let peer_id = peer
                        .get("id")
                        .or_else(|| peer.get("name"))
                        .and_then(|v| v.as_str())
                        .unwrap_or(name)
                        .to_owned();
                    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                    row.append(
                        &gtk::Label::builder()
                            .label(&format!("{name} · {peer_status}"))
                            .xalign(0.0)
                            .hexpand(true)
                            .wrap(true)
                            .build(),
                    );
                    let ping = gtk::Button::with_label("Test");
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
                                "That Centurion answered."
                            } else {
                                "No answer. Check both machines are on the same network."
                            })
                            .to_owned();
                        let result = adw::AlertDialog::builder()
                            .heading(if ok { "Reachable" } else { "Not reachable" })
                            .body(&message)
                            .close_response("ok")
                            .build();
                        result.add_response("ok", "OK");
                        result.present(Some(&parent_w));
                    });
                    row.append(&ping);
                    form.append(&row);
                }
            }
        }

        // ---- Messages from other Centurions --------------------------------
        let inbox_resp = run_bridge_action("fleet_inbox", serde_json::json!({ "limit": 25 }));
        let messages = inbox_resp
            .as_ref()
            .and_then(|p| p.get("messages").and_then(|v| v.as_array()))
            .cloned()
            .unwrap_or_default();
        let unread = inbox_resp
            .as_ref()
            .and_then(|p| p.get("unread").and_then(|v| v.as_u64()))
            .unwrap_or(0);

        form.append(&section_heading(&if unread > 0 {
            format!("Messages from other Centurions — {unread} new")
        } else {
            "Messages from other Centurions".to_owned()
        }));

        if messages.is_empty() {
            form.append(&hint(
                "Nothing here yet. When another Centurion sends you something, it arrives on \
        this screen.",
            ));
        } else {
            for msg in messages.iter().take(10) {
                let from = msg
                    .get("sender_name")
                    .and_then(|v| v.as_str())
                    .unwrap_or("another Centurion");
                let subject = msg
                    .get("subject")
                    .and_then(|v| v.as_str())
                    .unwrap_or("(no subject)");
                let body = msg.get("body").and_then(|v| v.as_str()).unwrap_or("");
                let mid = msg
                    .get("message_id")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_owned();
                let is_read = msg.get("read").and_then(|v| v.as_bool()).unwrap_or(false);

                let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                let shown = if body.trim().is_empty() {
                    format!("{from} · {subject}")
                } else {
                    format!("{from} · {subject}\n{}", body.trim())
                };
                let label = gtk::Label::builder()
                    .label(&shown)
                    .xalign(0.0)
                    .hexpand(true)
                    .wrap(true)
                    .build();
                if !is_read {
                    label.add_css_class("heading");
                }
                row.append(&label);
                if !is_read {
                    let done = gtk::Button::with_label("Got it");
                    done.add_css_class("flat");
                    done.set_valign(gtk::Align::Start);
                    done.connect_clicked(move |b| {
                        let _ = run_bridge_action(
                            "fleet_mark_read",
                            serde_json::json!({ "message_id": mid }),
                        );
                        b.set_sensitive(false);
                        b.set_label("Read");
                    });
                    row.append(&done);
                }
                form.append(&row);
            }
        }

        // ---- Send something -------------------------------------------------
        let peers_resp = run_bridge_action("fleet_status", serde_json::json!({}));
        let peer_names: Vec<String> = peers_resp
            .as_ref()
            .and_then(|p| p.get("peers").and_then(|v| v.as_array()))
            .map(|arr| {
                arr.iter()
                    .filter_map(|p| p.get("name").and_then(|v| v.as_str()).map(str::to_owned))
                    .collect()
            })
            .unwrap_or_default();

        if !peer_names.is_empty() {
            form.append(&section_heading("Send something to the other Centurion"));
            let name_refs: Vec<&str> = peer_names.iter().map(String::as_str).collect();
            let picker = gtk::DropDown::from_strings(&name_refs);
            let subject_entry = gtk::Entry::builder()
                .placeholder_text("Subject (e.g. Check the pricing sheet)")
                .hexpand(true)
                .build();
            let body_view = gtk::TextView::builder()
                .wrap_mode(gtk::WrapMode::WordChar)
                .build();
            body_view.set_size_request(-1, 90);
            let body_frame = gtk::Frame::builder().child(&body_view).build();
            form.append(&picker);
            form.append(&subject_entry);
            form.append(&body_frame);
            let send_button = gtk::Button::with_label("Send");
            send_button.add_css_class("suggested-action");
            send_button.set_halign(gtk::Align::Start);
            form.append(&send_button);
            let send_status = hint("");
            form.append(&send_status);

            let parent_for_send = parent.clone();
            let peer_names_for_send = peer_names.clone();
            send_button.connect_clicked(move |b| {
                let to = peer_names_for_send
                    .get(picker.selected() as usize)
                    .cloned()
                    .unwrap_or_default();
                let subject = subject_entry.text().trim().to_owned();
                let buf = body_view.buffer();
                let body = buf
                    .text(&buf.start_iter(), &buf.end_iter(), false)
                    .trim()
                    .to_owned();
                if body.is_empty() {
                    send_status.set_label("Write the message first.");
                    return;
                }
                b.set_sensitive(false);
                let payload = run_bridge_action(
                    "fleet_send",
                    serde_json::json!({ "peer_id": to, "subject": subject, "body": body }),
                );
                let delivered = payload
                    .as_ref()
                    .and_then(|p| p.get("delivered").and_then(|v| v.as_bool()))
                    .unwrap_or(false);
                let message = payload
                    .as_ref()
                    .and_then(|p| p.get("message").and_then(|v| v.as_str()))
                    .unwrap_or("Could not send.")
                    .to_owned();
                send_status.set_label(&message);
                // Only celebrate a delivery the Brain can prove.
                if delivered {
                    let ok_dialog = adw::AlertDialog::builder()
                        .heading("Sent")
                        .body(&message)
                        .close_response("ok")
                        .build();
                    ok_dialog.add_response("ok", "OK");
                    ok_dialog.present(Some(&parent_for_send));
                }
                b.set_sensitive(true);
            });
        }

        let dialog = adw::AlertDialog::builder()
            .heading("Connect another Centurion")
            .body(
                "Two Centurions on the same network can work together. Swap the two values \
above with the other person — one set each way — then press Connect.",
            )
            .extra_child(&form)
            .close_response("cancel")
            .default_response("connect")
            .build();
        dialog.add_response("cancel", "Close");
        dialog.add_response("connect", "Connect");
        dialog.set_response_appearance("connect", adw::ResponseAppearance::Suggested);

        // Turning reachability on, then waiting for the listener to actually
        // bind. The restart happens off the main thread; the wait polls so the
        // window stays responsive.
        enable_button.connect_clicked({
            let status_line = status_line.clone();
            let enable_button = enable_button.clone();
            let values_box = values_box.clone();
            move |_| {
                enable_button.set_sensitive(false);
                status_line.set_label("Turning this on — the Brain will restart in a moment…");

                // Write the settings, and show what came back immediately. The
                // two values only exist after this call, so without the redraw
                // the customer presses the button and the screen still says
                // "not reachable yet" — which reads as a dead button.
                let enable = run_bridge_action("fleet_peer_enable", serde_json::json!({}));
                if let Some(ref resp) = enable {
                    let address = resp.get("address").and_then(|v| v.as_str()).unwrap_or("");
                    let secret = resp.get("secret").and_then(|v| v.as_str()).unwrap_or("");
                    fill_peer_values(&values_box, address, secret);
                    if resp.get("ok").and_then(|v| v.as_bool()) != Some(true) {
                        let detail = resp
                            .get("message")
                            .or_else(|| resp.get("error"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("It did not say why.");
                        status_line.set_label(&format!("Could not turn this on — {detail}"));
                        enable_button.set_sensitive(true);
                        return;
                    }
                }

                std::thread::spawn(|| {
                    restart_gateway_best_effort();
                });
                // The poll runs repeatedly, so it needs its own handles.
                let status_line_inner = status_line.clone();
                let enable_button_inner = enable_button.clone();
                let values_box_inner = values_box.clone();
                let ticks = std::cell::Cell::new(0u32);
                let retried = std::cell::Cell::new(false);
                glib::timeout_add_local(std::time::Duration::from_secs(1), move || {
                    ticks.set(ticks.get() + 1);
                    if let Some(p) = run_bridge_action("fleet_peer_status", serde_json::json!({})) {
                        let address = p.get("address").and_then(|v| v.as_str()).unwrap_or("");
                        let secret = p.get("secret").and_then(|v| v.as_str()).unwrap_or("");
                        if !address.is_empty() || !secret.is_empty() {
                            fill_peer_values(&values_box_inner, address, secret);
                        }
                        if p.get("listening").and_then(|v| v.as_bool()) == Some(true) {
                            status_line_inner.set_label(
                                "This Centurion is reachable. Give the two values above to \
the other person.",
                            );
                            enable_button_inner.set_visible(false);
                            return glib::ControlFlow::Break;
                        }
                    }
                    // The first restart can land while the old gateway is still
                    // shutting down, so give it one more try before giving up.
                    if ticks.get() == 15 && !retried.get() {
                        retried.set(true);
                        std::thread::spawn(|| {
                            restart_gateway_best_effort();
                        });
                    }
                    if ticks.get() >= 90 {
                        status_line_inner.set_label(
                            "Still not reachable. The two values above are saved. Open Settings \
→ This Brain, press Restart next to Gateway, then reopen this screen.",
                        );
                        enable_button_inner.set_sensitive(true);
                        return glib::ControlFlow::Break;
                    }
                    glib::ControlFlow::Continue
                });
            }
        });

        let parent_for_result = parent.clone();
        dialog.connect_response(None, move |_d, response| {
            if response != "connect" {
                return;
            }
            let name = name_entry.text().trim().to_string();
            let address = address_entry.text().trim().to_string();
            // Spaces are how the secret reads aloud; strip them before saving.
            let secret = secret_entry
                .text()
                .chars()
                .filter(|c| !c.is_whitespace())
                .collect::<String>();
            if address.is_empty() || secret.is_empty() {
                let missing = adw::AlertDialog::builder()
                    .heading("Two values needed")
                    .body(
                        "Enter the other Centurion's address and secret — both come from the \
same screen on their machine, under “1 · Give these two values to the other person”.",
                    )
                    .close_response("ok")
                    .build();
                missing.add_response("ok", "OK");
                missing.present(Some(&parent_for_result));
                return;
            }
            // The peer id is an internal label; derive it rather than asking.
            let derived_id = if name.is_empty() {
                address
                    .trim_start_matches("http://")
                    .trim_start_matches("https://")
                    .replace([':', '/', '.'], "-")
            } else {
                name.to_lowercase().replace(' ', "-")
            };
            let payload = run_bridge_action_result(
                "fleet_peer_put",
                serde_json::json!({
                    "peer_id": derived_id,
                    "name": if name.is_empty() { derived_id.clone() } else { name.clone() },
                    "address": address,
                    "auth_token": secret,
                }),
            );
            let saved = payload
                .as_ref()
                .ok()
                .and_then(|p| p.get("ok").and_then(|v| v.as_bool()))
                .unwrap_or(false);
            if !saved {
                let message = match &payload {
                    Ok(p) => p
                        .get("message")
                        .and_then(|v| v.as_str())
                        .unwrap_or("Could not save that Centurion.")
                        .to_owned(),
                    Err(error) => error.clone(),
                };
                let failed = adw::AlertDialog::builder()
                    .heading("Could not connect")
                    .body(&message)
                    .close_response("ok")
                    .build();
                failed.add_response("ok", "OK");
                failed.present(Some(&parent_for_result));
                return;
            }
            // Saved — now prove the link rather than assuming it.
            let ping = run_bridge_action(
                "fleet_ping",
                serde_json::json!({ "peer_id": derived_id }),
            );
            let reached = ping
                .as_ref()
                .and_then(|p| p.get("ok").and_then(|v| v.as_bool()))
                .unwrap_or(false);
            let detail = ping
                .as_ref()
                .and_then(|p| p.get("message").and_then(|v| v.as_str()))
                .unwrap_or("")
                .to_owned();
            let body = if reached {
                format!(
                    "{} is connected and answered. Both Centurions can reach each other now.",
                    if name.is_empty() { "The other Centurion" } else { &name }
                )
            } else {
                format!(
                    "Saved, but it did not answer{}. Check both machines are on the same \
network, and that the other person has pressed “Make this Centurion reachable”.",
                    if detail.is_empty() { String::new() } else { format!(" — {detail}") }
                )
            };
            let result = adw::AlertDialog::builder()
                .heading(if reached { "Connected" } else { "Saved, not yet answering" })
                .body(&body)
                .close_response("ok")
                .build();
            result.add_response("ok", "OK");
            result.present(Some(&parent_for_result));
        });
        dialog.present(Some(parent));
    }

    fn show_ops_glance_dialog(parent: &adw::ApplicationWindow) {
        let body = match run_bridge_action_result("ops_glance", serde_json::json!({})) {
            Ok(p) if p.get("ok").and_then(|v| v.as_bool()) == Some(true) => {
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
            Ok(p) => p
                .get("message")
                .and_then(|v| v.as_str())
                .unwrap_or("Could not load ops glance.")
                .to_owned(),
            Err(error) => error,
        };
        let dialog = adw::AlertDialog::builder()
            .heading("Scheduled &amp; board")
            .body(&body)
            .close_response("close")
            .build();
        dialog.add_response("close", "Close");
        dialog.present(Some(parent));
    }

    fn show_plugins_list_dialog(parent: &adw::ApplicationWindow) {
        let payload = run_bridge_action_result("plugin_list", serde_json::json!({}));
        let body = match payload {
            Ok(p) if p.get("ok").and_then(|v| v.as_bool()) == Some(true) => {
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
            Ok(p) => p
                .get("message")
                .and_then(|v| v.as_str())
                .unwrap_or("Could not list plugins.")
                .to_owned(),
            Err(error) => error,
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
        show_backup_thinking_dialog_inner(parent, row, None);
    }

    fn show_backup_thinking_dialog_inner(
        parent: &adw::ApplicationWindow,
        row: &adw::ActionRow,
        initial_error: Option<String>,
    ) {
        let loading = adw::AlertDialog::builder()
            .heading("Backup Thinking")
            .body("Loading services…")
            .close_response("cancel")
            .build();
        loading.add_response("cancel", "Cancel");
        let cancelled = Rc::new(Cell::new(false));
        loading.connect_response(None, {
            let cancelled = cancelled.clone();
            move |_, _| cancelled.set(true)
        });
        loading.present(Some(parent));

        let parent = parent.clone();
        let row = row.clone();
        crate::bridge_actions::run_bridge_async(
            || run_provider_command_result(&["catalog"]),
            move |catalog_result| {
                if cancelled.get() {
                    return;
                }
                loading.close();
                show_backup_thinking_dialog_loaded(&parent, &row, initial_error, catalog_result);
            },
        );
    }

    fn show_backup_thinking_dialog_loaded(
        parent: &adw::ApplicationWindow,
        row: &adw::ActionRow,
        initial_error: Option<String>,
        catalog_result: Result<ProviderCliResponse, String>,
    ) {
        let connectors: Vec<ThinkingConnectorOption> = catalog_result
            .as_ref()
            .ok()
            .and_then(|response| response.catalog.as_ref())
            .and_then(|catalog| {
                catalog
                    .get("text_models")
                    .and_then(|value| value.as_array())
                    .cloned()
            })
            .unwrap_or_default()
            .into_iter()
            .filter_map(|entry| thinking_connector_from_row(&entry))
            .collect();

        if connectors.is_empty() {
            let reason = match &catalog_result {
                Ok(_) => "Centurion did not return any thinking services.".to_owned(),
                Err(reason) => reason.clone(),
            };
            let dialog = adw::AlertDialog::builder()
                .heading("Backup Thinking")
                .body(format!(
                    "Could not load the curated thinking-service catalog.\n\n{reason}"
                ))
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
        for (index, connector) in connectors.iter().enumerate() {
            if !connector.needs_key {
                initial = index as u32;
                break;
            }
        }
        service_drop.set_selected(initial);

        let slot_drop = gtk::DropDown::from_strings(&["Backup #1", "Backup #2"]);
        slot_drop.set_selected(0);

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
        let get_key = gtk::LinkButton::with_label("", "Get a key");
        get_key.set_halign(gtk::Align::Start);
        get_key.set_visible(false);

        let update_hint = {
            let hint = hint.clone();
            let key_entry = key_entry.clone();
            let get_key = get_key.clone();
            let connectors = connectors.clone();
            Rc::new(move |selected: u32| {
                let Some(connector) = connectors.get(selected as usize) else {
                    return;
                };
                if connector.signup_url.is_empty() {
                    get_key.set_visible(false);
                } else {
                    get_key.set_uri(&connector.signup_url);
                    get_key.set_label("Get a key");
                    get_key.set_visible(true);
                }
                if connector.needs_key {
                    key_entry.set_placeholder_text(Some(
                        "Access code from your thinking-service account",
                    ));
                    if connector.best_for.is_empty() {
                        hint.set_label(
                            "This backup needs an access code saved on this brain.",
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

        let current_subtitle = row
            .subtitle()
            .filter(|subtitle| !subtitle.trim().is_empty())
            .map(|subtitle| subtitle.to_string())
            .unwrap_or_else(|| "Not configured".to_owned());
        let dialog = adw::AlertDialog::builder()
            .heading("Backup Thinking")
            .body(&format!(
                "If your primary thinking service goes offline, Chat keeps working on a backup \
so you can fix Thinking without being stuck.\n\nCurrently: {current_subtitle}"
            ))
            .close_response("cancel")
            .default_response("apply")
            .build();
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("clear", "Clear slot");
        dialog.add_response("apply", "Set backup");
        dialog.set_response_appearance("apply", adw::ResponseAppearance::Suggested);
        dialog.set_response_appearance("clear", adw::ResponseAppearance::Destructive);

        let extra = gtk::Box::new(gtk::Orientation::Vertical, 8);
        let error_label = gtk::Label::builder()
            .label(initial_error.as_deref().unwrap_or(""))
            .xalign(0.0)
            .wrap(true)
            .css_classes(["error"])
            .visible(initial_error.is_some())
            .build();
        extra.append(&gtk::Label::builder().label("Slot").xalign(0.0).build());
        extra.append(&slot_drop);
        extra.append(&gtk::Label::builder().label("Service").xalign(0.0).build());
        extra.append(&service_drop);
        extra.append(&hint);
        extra.append(&get_key);
        extra.append(&key_label);
        extra.append(&key_entry);
        extra.append(&error_label);
        dialog.set_extra_child(Some(&extra));
        dialog.present(Some(parent));

        let row = row.clone();
        let parent = parent.clone();
        dialog.connect_response(None, move |dialog, response| {
            if response == "cancel" {
                dialog.close();
                return;
            }

            let reopen_with_error: Rc<dyn Fn(String)> = Rc::new({
                let parent = parent.clone();
                let row = row.clone();
                move |message: String| {
                    let parent = parent.clone();
                    let row = row.clone();
                    glib::idle_add_local_once(move || {
                        show_backup_thinking_dialog_inner(&parent, &row, Some(message));
                    });
                }
            });

            let slot = (slot_drop.selected() as u32) + 1;
            let slot_str = slot.to_string();

            if response == "clear" {
                dialog.close();
                row.set_subtitle("Clearing backup thinking service…");
                let row = row.clone();
                let reopen_with_error = reopen_with_error.clone();
                crate::bridge_actions::run_bridge_async(
                    move || match run_provider_command_result(&[
                        "remove-backup",
                        "--slot",
                        slot_str.as_str(),
                    ]) {
                        Ok(clear_response) if clear_response.ok => Ok(backup_thinking_subtitle()),
                        Ok(clear_response) => Err(clear_response
                            .message
                            .filter(|text| !text.trim().is_empty())
                            .unwrap_or_else(|| "Could not clear backup slot.".to_owned())),
                        Err(reason) => Err(format!("Could not clear backup slot — {reason}")),
                    },
                    move |result: Result<String, String>| match result {
                        Ok(subtitle) => row.set_subtitle(&subtitle),
                        Err(message) => reopen_with_error(message),
                    },
                );
                return;
            }

            if response != "apply" {
                dialog.close();
                return;
            }

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
            let connector_id = connector.id.clone();
            let access_code = access_code.trim().to_owned();
            dialog.close();
            row.set_subtitle("Setting backup thinking service…");
            let row = row.clone();
            crate::bridge_actions::run_bridge_async(
                move || {
                    if !access_code.is_empty() {
                        match run_provider_save_key(&connector_id, &access_code) {
                            Ok(save_response) if save_response.ok => {}
                            Ok(save_response) => {
                                return Err(save_response
                                    .message
                                    .unwrap_or_else(|| "Could not save access code.".to_owned()));
                            }
                            Err(reason) => {
                                return Err(format!("Could not save access code — {reason}"))
                            }
                        }
                    }
                    let apply_args = [
                        "apply-connector",
                        connector_id.as_str(),
                        "--as-backup",
                        "--slot",
                        slot_str.as_str(),
                    ];
                    let apply_response = match run_provider_command_result(&apply_args) {
                        Ok(response) => response,
                        Err(reason) => {
                            return Err(format!("Could not set backup thinking service — {reason}"));
                        }
                    };
                    let ok = apply_response.ok;
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
                            if ok {
                                format!("Backup #{slot} updated.")
                            } else {
                                "Could not set backup thinking service.".to_owned()
                            }
                        });
                    if !ok {
                        return Err(message);
                    }
                    Ok((message, backup_thinking_subtitle()))
                },
                move |result: Result<(String, String), String>| match result {
                    Ok((message, subtitle)) => {
                        row.set_subtitle(if subtitle.is_empty() {
                            &message
                        } else {
                            &subtitle
                        });
                    }
                    Err(message) => reopen_with_error(message),
                },
            );
        });
    }

    fn show_change_thinking_dialog(
        parent: &adw::ApplicationWindow,
        settings_row: &adw::ActionRow,
        detail: &gtk::Label,
    ) {
        show_change_thinking_dialog_inner(parent, settings_row, detail, None);
    }

    const FIRECRAWL_KEY_URL: &str = "https://www.firecrawl.dev/";

    fn thinking_signup_url(provider: &str, key_env: &str, catalog_url: &str) -> String {
        let catalog = catalog_url.trim();
        if !catalog.is_empty() {
            return catalog.to_owned();
        }
        match key_env {
            "OPENAI_API_KEY" => "https://platform.openai.com/api-keys".to_owned(),
            "ANTHROPIC_API_KEY" => "https://console.anthropic.com/settings/keys".to_owned(),
            "GEMINI_API_KEY" | "GOOGLE_API_KEY" => "https://aistudio.google.com/apikey".to_owned(),
            "DEEPSEEK_API_KEY" => "https://platform.deepseek.com/api_keys".to_owned(),
            "XAI_API_KEY" => "https://console.x.ai/".to_owned(),
            _ => match provider {
                "openai-api" | "openai" => "https://platform.openai.com/api-keys".to_owned(),
                "anthropic" => "https://console.anthropic.com/settings/keys".to_owned(),
                "gemini" | "google" => "https://aistudio.google.com/apikey".to_owned(),
                "deepseek" => "https://platform.deepseek.com/api_keys".to_owned(),
                "xai" => "https://console.x.ai/".to_owned(),
                _ => String::new(),
            },
        }
    }

    fn thinking_connector_from_row(row: &serde_json::Value) -> Option<ThinkingConnectorOption> {
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
        let provider = row.get("provider").and_then(|v| v.as_str()).unwrap_or("");
        let key_env = row.get("key_env").and_then(|v| v.as_str()).unwrap_or("");
        let catalog_url = row.get("signup_url").and_then(|v| v.as_str()).unwrap_or("");
        Some(ThinkingConnectorOption {
            id,
            display_name,
            needs_key,
            best_for,
            signup_url: thinking_signup_url(provider, key_env, catalog_url),
        })
    }

    fn show_firecrawl_key_dialog(
        parent: &adw::ApplicationWindow,
        row: &adw::ActionRow,
        button: &gtk::Button,
    ) {
        let dialog = adw::AlertDialog::builder()
            .heading("Firecrawl API key")
            .body(
                "Paste your Firecrawl key to power research-heavy web search and scraping on this brain. \
The key stays in ~/.centurion/.env on this machine only.",
            )
            .close_response("cancel")
            .default_response("save")
            .build();
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("save", "Save");
        dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);

        let extra = gtk::Box::new(gtk::Orientation::Vertical, 10);
        let note = gtk::Label::builder()
            .label(
                "Source your key at https://www.firecrawl.dev/ — sign in, open the dashboard, then API Keys.",
            )
            .wrap(true)
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build();
        let link = gtk::LinkButton::with_label(FIRECRAWL_KEY_URL, "Open firecrawl.dev");
        link.set_uri(FIRECRAWL_KEY_URL);
        link.set_halign(gtk::Align::Start);
        let key_entry = gtk::PasswordEntry::builder()
            .placeholder_text("fc-… Firecrawl API key")
            .show_peek_icon(true)
            .build();
        extra.append(&note);
        extra.append(&link);
        extra.append(
            &gtk::Label::builder()
                .label("API key")
                .xalign(0.0)
                .build(),
        );
        extra.append(&key_entry);
        dialog.set_extra_child(Some(&extra));
        dialog.present(Some(parent));

        let parent = parent.clone();
        let row = row.clone();
        let button = button.clone();
        dialog.connect_response(None, move |dialog, response| {
            if response != "save" {
                dialog.close();
                return;
            }
            let key = key_entry.text().to_string();
            dialog.close();
            if key.trim().is_empty() {
                let fail = adw::AlertDialog::builder()
                    .heading("API key required")
                    .body(
                        "Paste your Firecrawl API key from https://www.firecrawl.dev/ \
(Dashboard → API Keys), then try again.",
                    )
                    .close_response("ok")
                    .build();
                fail.add_response("ok", "OK");
                fail.present(Some(&parent));
                return;
            }
            let key = key.trim().to_owned();
            let row = row.clone();
            let button = button.clone();
            let parent = parent.clone();
            crate::bridge_actions::run_bridge_action_async(
                "tool_env_set",
                serde_json::json!({
                    "key": "FIRECRAWL_API_KEY",
                    "value": key,
                }),
                move |payload: Option<serde_json::Value>| {
                    let ok = payload
                        .as_ref()
                        .and_then(|p| p.get("ok"))
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false);
                    if ok {
                        let configured = payload
                            .as_ref()
                            .and_then(|p| p.get("configured"))
                            .and_then(|v| v.as_bool())
                            .unwrap_or(true);
                        row.set_subtitle(if configured {
                            "API key saved on this brain — ready for research scraping."
                        } else {
                            "Not set — get a key at https://www.firecrawl.dev/"
                        });
                        button.set_label(if configured { "Update" } else { "Add key" });
                        return;
                    }
                    let message = payload
                        .as_ref()
                        .and_then(|p| {
                            p.get("message")
                                .or_else(|| p.get("error"))
                                .and_then(|v| v.as_str())
                                .map(str::to_owned)
                        })
                        .unwrap_or_else(|| "Could not save Firecrawl API key.".to_owned());
                    let fail = adw::AlertDialog::builder()
                        .heading("Could not save key")
                        .body(&message)
                        .close_response("ok")
                        .build();
                    fail.add_response("ok", "OK");
                    fail.present(Some(&parent));
                },
            );
        });
    }

    fn show_change_thinking_dialog_inner(
        parent: &adw::ApplicationWindow,
        settings_row: &adw::ActionRow,
        detail: &gtk::Label,
        initial_error: Option<String>,
    ) {
        let loading = adw::AlertDialog::builder()
            .heading("Change thinking service")
            .body("Loading services…")
            .close_response("cancel")
            .build();
        loading.add_response("cancel", "Cancel");
        let cancelled = Rc::new(Cell::new(false));
        loading.connect_response(None, {
            let cancelled = cancelled.clone();
            move |_, _| cancelled.set(true)
        });
        loading.present(Some(parent));

        let parent = parent.clone();
        let settings_row = settings_row.clone();
        let detail = detail.clone();
        crate::bridge_actions::run_bridge_async(
            || run_provider_command_result(&["catalog"]),
            move |catalog_result| {
                if cancelled.get() {
                    return;
                }
                loading.close();
                show_change_thinking_dialog_loaded(
                    &parent,
                    &settings_row,
                    &detail,
                    initial_error,
                    catalog_result,
                );
            },
        );
    }

    fn show_change_thinking_dialog_loaded(
        parent: &adw::ApplicationWindow,
        settings_row: &adw::ActionRow,
        detail: &gtk::Label,
        initial_error: Option<String>,
        catalog_result: Result<ProviderCliResponse, String>,
    ) {
        let active_connector_id = catalog_result
            .as_ref()
            .ok()
            .and_then(|response| response.catalog.as_ref())
            .and_then(|catalog| catalog.get("active_connector_id"))
            .and_then(|value| value.as_str())
            .map(str::to_owned);
        let connectors: Vec<ThinkingConnectorOption> = catalog_result
            .as_ref()
            .ok()
            .and_then(|response| response.catalog.as_ref())
            .and_then(|catalog| {
                catalog
                    .get("text_models")
                    .and_then(|value| value.as_array())
                    .cloned()
            })
            .unwrap_or_default()
            .into_iter()
            .filter_map(|row| thinking_connector_from_row(&row))
            .collect();

        if connectors.is_empty() {
            let reason = match &catalog_result {
                Ok(_) => "Centurion did not return any thinking services.".to_owned(),
                Err(reason) => reason.clone(),
            };
            let dialog = adw::AlertDialog::builder()
                .heading("Change thinking service")
                .body(format!(
                    "Could not load the curated thinking-service catalog.\n\n{reason}"
                ))
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
        let get_key = gtk::LinkButton::with_label("", "Get a key");
        get_key.set_halign(gtk::Align::Start);
        get_key.set_visible(false);

        let update_hint = {
            let hint = hint.clone();
            let key_entry = key_entry.clone();
            let get_key = get_key.clone();
            let connectors = connectors.clone();
            Rc::new(move |selected: u32| {
                let Some(connector) = connectors.get(selected as usize) else {
                    return;
                };
                if connector.signup_url.is_empty() {
                    get_key.set_visible(false);
                } else {
                    get_key.set_uri(&connector.signup_url);
                    get_key.set_label("Get a key");
                    get_key.set_visible(true);
                }
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
        extra.append(&get_key);
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
            let reopen_with_error: Rc<dyn Fn(String)> = Rc::new({
                let parent = parent.clone();
                let settings_row = settings_row.clone();
                let detail = detail.clone();
                move |message: String| {
                    let parent = parent.clone();
                    let settings_row = settings_row.clone();
                    let detail = detail.clone();
                    glib::idle_add_local_once(move || {
                        show_change_thinking_dialog_inner(
                            &parent,
                            &settings_row,
                            &detail,
                            Some(message),
                        );
                    });
                }
            });

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
            let connector_id = connector.id.clone();
            let access_code = access_code.trim().to_owned();
            dialog.close();
            settings_row.set_subtitle("Applying thinking service…");
            let settings_row = settings_row.clone();
            let detail = detail.clone();
            crate::bridge_actions::run_bridge_async(
                move || {
                    if !access_code.is_empty() {
                        match run_provider_save_key(&connector_id, &access_code) {
                            Ok(save_response) if save_response.ok => {}
                            Ok(save_response) => {
                                return Err(save_response
                                    .message
                                    .unwrap_or_else(|| "Could not save access code.".to_owned()));
                            }
                            Err(reason) => {
                                return Err(format!("Could not save access code — {reason}"))
                            }
                        }
                    }
                    let apply_response = match run_provider_command_result(&[
                        "apply-connector",
                        connector_id.as_str(),
                    ]) {
                        Ok(response) => response,
                        Err(reason) => {
                            return Err(format!("Could not apply thinking service change — {reason}"));
                        }
                    };
                    let ok = apply_response.ok;
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
                            if ok {
                                "Thinking service updated.".to_owned()
                            } else {
                                "Could not apply thinking service change.".to_owned()
                            }
                        });
                    if !ok {
                        return Err(message);
                    }
                    let status = run_provider_command(&["status", "--skip-probe"])
                        .and_then(|response| response.status);
                    Ok((message, status))
                },
                move |result: Result<(String, Option<ProviderStatusPayload>), String>| match result
                {
                    Ok((_message, Some(status))) => {
                        apply_thinking_status(&detail, &settings_row, status);
                    }
                    Ok((message, None)) => {
                        settings_row.set_subtitle(&message);
                        detail.set_label(&message);
                    }
                    Err(message) => reopen_with_error(message),
                },
            );
        });
    }

    fn show_get_help_dialog(
        parent: &adw::ApplicationWindow,
        thinking_settings_row: &adw::ActionRow,
        thinking_detail: &gtk::Label,
    ) {
        let health_body = match run_support_command_result(&["health"]) {
            Ok(response) => {
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
            }
            Err(reason) => reason,
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
        let body = match run_support_command_result(&["health"]) {
            Ok(response) => {
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
            }
            Err(reason) => reason,
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
        let (heading, body) = match run_support_command_result(&["bundle"]) {
            Ok(response) => {
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
                        match response.message.filter(|text| !text.trim().is_empty()) {
                            Some(reason) => format!(
                                "Could not create a support code — {reason}\n\nTry again in a \
moment. If it keeps failing, ask your advisor for help."
                            ),
                            None => "Could not create a support code. Try again in a moment, then \
ask your advisor for help."
                                .to_owned(),
                        },
                    )
                }
            }
            Err(reason) => (
                "Support Bundle".to_owned(),
                format!(
                    "Could not create a support code — {reason}\n\nTry again in a moment, then \
ask your advisor for help."
                ),
            ),
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
            let result_dialog = match run_support_command_result(&["show", &code]) {
                Ok(cli_response) if cli_response.ok => {
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
                Ok(cli_response) => adw::AlertDialog::builder()
                    .heading("Support Code Not Found")
                    .body(
                        cli_response
                            .message
                            .unwrap_or_else(|| "That code is missing or has expired.".to_owned())
                            .as_str(),
                    )
                    .close_response("ok")
                    .build(),
                Err(reason) => adw::AlertDialog::builder()
                    .heading("Support Code Not Found")
                    .body(format!(
                        "Could not look up that code — {reason}\n\nCheck the code was copied \
complete, then try again."
                    ))
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
            app_version: installed_version(),
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
