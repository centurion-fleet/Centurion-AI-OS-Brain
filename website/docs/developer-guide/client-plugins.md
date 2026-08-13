# Client plugins vs agent plugins

Centurion has three plugin surfaces. They are **not** interchangeable.

| Surface | Where it runs | What it extends | How users install |
|---------|---------------|-----------------|-------------------|
| **Agent plugins** | Python agent / CLI / gateway | Tools, hooks, slash commands, providers, skills | `~/.centurion/plugins/`, pip entry points, `centurion plugins` |
| **Dashboard plugins** | Web dashboard (`centurion dashboard`) | Sidebar widgets via `plugins/*/dashboard/manifest.json` | Same plugin tree; dashboard discovers manifests |
| **Client plugins (Brain)** | Linux GTK Brain (`brain/` (linux host under `brain/linux/`)) | Settings rows / Home cards (v0: list only) | Same manifests; Brain reads via bridge `plugin_list` |

## What `centurion plugins` does **not** do

Enabling a plugin for the agent does **not** automatically add UI to Sovereign AI Brain.
Until a client extension point exists for that plugin kind, Brain remains a fixed
bridge action surface (`soul_*`, `mission_*`, `plans_*`, `fleet_*`, …).

## Client plugin seam v0

Brain Settings → **Installed plugins** calls bridge action `plugin_list`, which
returns PluginManager discovery results (name, kind, enabled, description).

v0 is **read-only**: list + status. Future work may add a thin Home card or
Settings row driven by a `client` / `brain` section in `plugin.yaml`, reusing
the dashboard manifest discovery pattern — not embedding full PluginManager
inside Rust.

## Authoring guidance

1. Prefer **agent plugins** for tools, memory, and model providers.
2. Prefer **dashboard manifests** for web-only widgets.
3. Do not assume GTK Brain will load arbitrary Python UI code.
4. If you need Brain UI, propose a bridge action + declarative manifest first.
