# Centurion Brain (host apps)

Product hosts for **Sovereign AI Brain** — the machine that runs Centurion AI OS
and pairs with Centurion Remote (phones).

| Path | Role |
|------|------|
| [`linux/`](linux/) | Linux / Fedora GTK Brain (shipping) |
| [`macos/`](macos/) | macOS Brain shell (roadmap scaffold) |
| [`service/`](service/) | `centurion-remote` (:9119) + `centurion-common` wire protocol |
| [`web-dashboard/`](web-dashboard/) | Missions (Mission Deck) UI embedded in Brain |

Rust workspace root: [`Cargo.toml`](Cargo.toml) (build from this directory).

```bash
cd brain
cargo build --release -p centurion-desktop -p centurion-remote -p centurion-install-brain
```

Python Centurion AI OS stays at the **repo root** (not under `brain/`).
Remote phone apps live under [`../remote/`](../remote/).
