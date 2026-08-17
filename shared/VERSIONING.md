# Centurion v5 version lockstep

All customer-facing products share the same **5.x.y** and release together.

| Product | Version source |
|---------|----------------|
| Centurion AI OS | `centurion_cli/__init__.py` → `__version__` |
| Centurion AI OS | `pyproject.toml` → `project.version` |
| Brain (Rust workspace) | `brain/Cargo.toml` → `workspace.package.version` |
| Centurion Remote (iOS) | `remote/ios/CenturionApp/project.yml` → `MARKETING_VERSION` |
| Desktop Tauri (archived) | `archive/desktop-tauri/` — not shipping |
| Sales / Help sites | external repos — must match OS tip **5.3.0** |

Before any release tag: bump every row that still ships to the same **5.x.y**.
