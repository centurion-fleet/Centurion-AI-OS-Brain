# SPEC — Premium Fedora Install Experience (Brain download → running in 2 clicks)

Status: **Draft for Cursor to plan → build**
Owner: Adrian Barkus / Titus (spec) → Cursor (implementation)
Date: 2026-08-02
Depends on: License System + Client Management Portal plan (Brain id `130758b2-3c46-4ee4-ac7e-23f9dcfe4193`, status: proceeded) — Phases 4 & 5 (phone-home API + activation screen)

---

## 1. Goal

Replace the **2-hour build-from-source support call** with a premium Fedora experience:

> Customer logs into the portal → clicks **Download for Fedora** → gets a **GPG-signed RPM** → double-clicks it → **GNOME Software** shows a verified publisher → **Install** → app appears in the menu → **first-run activation** with their license → Brain runs. Updates arrive silently via `dnf`.

Non-technical customers must never touch a terminal. This is the ranked-#1 path from `distribution-strategy.md` (native RPM first; AppImage = fallback; Flatpak = later; Snap = never).

## 2. Current state (verified 2026-08-02)

| Artifact | State | Issues found |
|---|---|---|
| `brain/linux/packaging/fedora/centurion-desktop.spec` | Half-built, exists | ⚠️ **Does NOT install the Python core** — only 2 Rust binaries + desktop file + icons + systemd unit + firewalld. The Brain is a Rust shell around the Python agent; an RPM without the Python core produces binaries that can't run. **This is the #1 gap.** |
| `brain/linux/packaging/fedora/build-rpm.sh` | Exists, functional | Tarballs whole repo (excludes target/.git — OK); `--define version` overrides spec. Needs GPG signing step. |
| `brain/linux/packaging/fedora/provision-centurion.sh` | Exists | Post-install helper (verify, firewalld, systemd enable). Should be absorbed into RPM `%post`/first-run. |
| `brain/linux/resources/com.centurion.desktop.desktop` | ✓ good | Name=Sovereign AI Brain, icon, StartupWMClass all correct |
| `brain/linux/resources/icons/` | ✓ present | hicolor sizes 16–512 + scalable |
| `brain/linux/packaging/systemd/centurion-remote.service` | ✓ exists | User unit, hardened (NoNewPrivileges, ProtectSystem) |
| `brain/linux/packaging/firewalld/centurion-remote.xml` | ✓ referenced by spec | firewalld service |
| `LICENSE` | ✓ repo root | MIT |
| Cargo.toml version | `5.2.115` | Spec hardcodes `0.14.0` — overridden by build-rpm.sh `--define`, but spec should be corrected |

**Bugs in the current spec (must fix):**
1. `URL: https://github.com/centurion-fleet/Centurion-AI-OS` — **wrong org**. Canonical repo is `https://github.com/centurion-fleet/Centurion-AI-OS` (that's what `install.sh` clones). centurion-fleet is a stale fork reference.
2. `Version: 0.14.0` hardcoded — should be `%{?version}`-driven or synced to Cargo.toml (build-rpm.sh already passes `--define version`).
3. `%post` only does `%firewalld_reload` — missing: icon theme cache rebuild, desktop database update, user-unit enablement strategy, venv/CLI install.
4. No GPG signing anywhere in the pipeline.
5. The Python core (`agent/`, `tools/`, `centurion_cli/`, `run_agent.py`, venv deps) is absent from `%files` — see gap #1.

## 3. The premium experience (requirements)

### 3.1 Portal — Get Brain page (`/account/get-brain`, website repo `TheSpaceFox/-personal-centurion-website-v5`)
- [ ] One prominent **Download for Fedora** button → serves the signed RPM for the current release
- [ ] OS/arch auto-detect (User-Agent) with manual override (Fedora 39–44, x86_64; aarch64 when available)
- [ ] Show: version, release date, release-notes link, **SHA256 checksum** (copy button)
- [ ] Publisher fingerprint shown (GPG key ID) — "Signed by Centurion Limited"
- [ ] Power-user one-liner (collapsed): `sudo dnf install ./centurion-brain-5.2.115.fc44.x86_64.rpm`
- [ ] Fallback link: AppImage (once we ship one) for non-Fedora/other distros
- [ ] **Artifact source: GitHub Releases** (public artifacts on the repo even if repo is private — approved in distribution-strategy.md). Portal links to the release asset + checksum; does NOT host binaries itself.

### 3.2 The RPM (OS repo)
- [ ] **Ships the full Brain**: Rust binaries + Python core + venv (or system site-packages layout) + desktop file + icons + systemd user unit + firewalld service
- [ ] Correct metadata: Name `centurion-brain` (product name) or keep `centurion-desktop`? — **decision needed** (see 5.2); URL → centurion-fleet org; version from Cargo.toml; License MIT; Summary "Sovereign AI Brain — your private personal AI"
- [ ] `%post`: `gtk-update-icon-cache`, `update-desktop-database`, enable `centurion-remote` user unit **for the invoking user** (design decision 5.1), write `~/.centurion/desktop-build.json` stamp
- [ ] `%preun`/`%postun`: clean reverse of the above (never delete user data — only app files)
- [ ] **GPG-signed** (`rpmsign --addsign`) with the Centurion release key; public key embedded in the app and published on the portal
- [ ] `dnf install ./centurion-brain-*.rpm` works cleanly with zero manual steps
- [ ] `desktop-file-validate` passes (already in spec)

### 3.3 First-run activation (depends on license plan Phase 4 API)
- [ ] App launches → activation screen (license code entry, or auto-provision if order marked delivered)
- [ ] On success: enable `centurion-remote` user unit, write license state, land in Chat
- [ ] Already scoped in license plan Phase 5 — **do not rebuild here**; spec only requires the RPM/portal to *reach* that screen

### 3.4 Updates
- [ ] **End state (premium):** hosted yum repo (e.g. `https://brain.1human1ai.com/fedora/`) with signed `repomd.xml`; install a `centurion.repo` file once → `dnf`/GNOME Software delivers all future updates silently
- [ ] **Interim:** in-app "Check for updates" fetches the new RPM + SHA256, verifies signature, installs via `pkexec dnf` — or simply links to the portal download
- [ ] Release process: monthly release ritual (see `release-management` skill) gains a step: build → sign → upload RPM to GitHub Releases (+ repo metadata when repo mode lands)

## 4. Build pipeline

```
release.py / release ritual
  → build-rpm.sh (fix: exclude packaging dir from tarball to avoid recursion; exclude tests/docs)
  → rpmsign --addsign (release key, passphrase via agent/CI secret)
  → upload to GitHub Releases (asset + SHA256 + fingerprint)
  → portal /account/get-brain serves link + checksum (website repo)
```

## 5. Open decisions (Cursor should flag, Adrian approves)

1. **User-unit enablement in `%post`**: `systemctl --user enable` from a root RPM post-script can't see the user session cleanly. Options: (a) first-run activation enables it (recommended — ties into 3.3), (b) `%post` runs a session-bus trick, (c) keep `provision-centurion.sh` as the documented post-install step for now. Recommend (a).
2. **RPM name**: `centurion-brain` (matches product/brand "Sovereign AI Brain", the app menu name) vs `centurion-desktop` (matches crate). Brand says Brain. Recommend rename with `Provides: centurion-desktop` for compatibility.
3. **Python core packaging**: bundle a venv inside the RPM (`/usr/lib/centurion-brain/venv`) vs install to system site-packages. Bundled venv is safer (no system pip pollution, reproducible deps) at the cost of size (~150–300MB with torch-less deps; verify). Recommend bundled venv; the systemd unit PATH already references a venv layout.
4. **Repo mode timeline**: start with GitHub-Releases download + interim updater, stand up the yum repo when >10 customers. Don't block 3.1–3.3 on it.
5. **Signing key custody**: GPG key generated once, private key in Adrian's vault + CI secret, public key published. No key in the repo.

## 6. Acceptance criteria

- [ ] Fresh Fedora 44 VM (no dev tools installed, no `~/.centurion`) → download RPM from portal → double-click → GNOME Software shows "Centurion Limited" verified publisher → Install → menu shows **Sovereign AI Brain**
- [ ] First launch: activation screen → license activates → Chat works → `systemctl --user is-active centurion-remote` = active
- [ ] `rpm -K centurion-brain-*.rpm` = OK (GPG verified)
- [ ] Portal page shows version + SHA256 that match the artifact
- [ ] Uninstall removes app files but keeps `~/.centurion` user data
- [ ] No terminal used in the entire happy path

## 7. Out of scope (for now)

- Flatpak/Flathub packaging (later, after WebKitGTK sandbox validation)
- macOS installer (Tauri 2 path — separate workstream per distribution-strategy)
- AppImage (fallback, only after RPM path is solid)
- Snap (never)
- Windows

## 8. Risks

- RPM without Python core = broken binaries shipped to customers → **gate 3.1/3.2 behind a clean-VM test** (acceptance criteria must pass before portal button goes live)
- Bundled venv size vs system packages — measure before deciding (decision 3)
- dnf repo signing is fiddly (repomd.xml.gpg) — do it once, document it, or defer to interim updater
- Release process drift: if the RPM isn't part of the monthly release ritual, it goes stale silently → add a release-pipeline checklist item

## 9. Cross-references

- `brain/linux/packaging/fedora/` — existing spec + scripts (fix in place)
- `references/distribution-strategy.md` (centurion-desktop-app skill) — Linux path ranking + GitHub Releases insight
- License plan `130758b2-3c46-4ee4-ac7e-23f9dcfe4193` — Phase 4 (phone-home API) + Phase 5 (activation screen) are prerequisites for 3.3
- `release-management` skill — monthly release ritual; add RPM step
