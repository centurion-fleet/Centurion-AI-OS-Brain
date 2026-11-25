<p align="center">

```
 ██████╗███████╗███╗   ██╗████████╗██╗   ██╗██████╗ ██╗ ██████╗ ███╗   ██╗
██╔════╝██╔════╝████╗  ██║╚══██╔══╝██║   ██║██╔══██╗██║██╔═══██╗████╗  ██║
██║     █████╗  ██╔██╗ ██║   ██║   ██║   ██║██████╔╝██║██║   ██║██╔██╗ ██║
██║     ██╔══╝  ██║╚██╗██║   ██║   ██║   ██║██╔══██╗██║██║   ██║██║╚██╗██║
╚██████╗███████╗██║ ╚████║   ██║   ╚██████╔╝██║  ██║██║╚██████╔╝██║ ╚████║
 ╚═════╝╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝
```

</p>

# Centurion AI OS

<p align="center">
  <a href="https://github.com/centurion-fleet/Centurion-AI-OS-Brain"><img src="https://img.shields.io/badge/Download-Linux%20build-FFD700?style=for-the-badge" alt="Download"></a>
  <a href="https://github.com/centurion-fleet/Centurion-AI-OS-Brain/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-AGPL--3.0-green?style=for-the-badge" alt="License: AGPL-3.0"></a>
  <a href="https://www.1human1ai.com/download"><img src="https://img.shields.io/badge/Key-free-333?style=for-the-badge" alt="Get a key"></a>
</p>

**Centurion is a private AI that runs on a machine you own, in a building you control.** It is one agent with a terminal, a memory, a scheduler and a set of messaging channels, and it does the work of a colleague rather than the work of a chat window. Nothing it reads is sent to us: the model API you point it at is your commercial relationship, and your files never leave the machine.

This repository is the Brain — the general product. It is free software under **AGPL-3.0**, permanently, with no feature held back and no seat count. Three things are not free and are not in this repository: the sector editions (the trade knowledge and workflows for accountancy and for member associations), the multi-user Team layer, and having a person put it in for you. Those are what [the paid rungs](https://www.1human1ai.com/what-to-buy) buy.

**It runs on Linux.** x86_64, 8 GB of RAM at the floor and 32 GB to be comfortable, 100 GB of disk, no GPU required — a small desktop or a used office PC is the intended machine, and the model is an API call rather than a local weight. The tested path is Fedora; Debian and Ubuntu work and are not yet packaged.

**A key is not required to run it.** The software does not stop working, and it will not ask again if you say no. A key turns on updates, the community, and being helped — [get one free, in one field](https://www.1human1ai.com/key) — and the whole of that arrangement is written out at [the download page](https://www.1human1ai.com/download).

Use any model you want — [OpenRouter](https://openrouter.ai) (200+ models), [NovitaAI](https://novita.ai), [NVIDIA NIM](https://build.nvidia.com), [Xiaomi MiMo](https://platform.xiaomimimo.com), [z.ai/GLM](https://z.ai), [Kimi/Moonshot](https://platform.moonshot.ai), [MiniMax](https://www.minimax.io), [Hugging Face](https://huggingface.co), OpenAI, LM Studio, or your own endpoint. Switch with `centurion model` — no code changes, no lock-in.

<table>
<tr><td><b>A real terminal interface</b></td><td>Full TUI with multiline editing, slash-command autocomplete, conversation history, interrupt-and-redirect, and streaming tool output.</td></tr>
<tr><td><b>Lives where you do</b></td><td>Telegram, Discord, Slack, WhatsApp, Signal, and CLI — all from a single gateway process. Voice memo transcription, cross-platform conversation continuity.</td></tr>
<tr><td><b>A closed learning loop</b></td><td>Agent-curated memory with periodic nudges. Autonomous skill creation after complex tasks. Skills self-improve during use. FTS5 session search with LLM summarization for cross-session recall. <a href="https://github.com/plastic-labs/honcho">Honcho</a> dialectic user modeling. Compatible with the <a href="https://agentskills.io">agentskills.io</a> open standard.</td></tr>
<tr><td><b>Scheduled automations</b></td><td>Built-in cron scheduler with delivery to any platform. Daily reports, nightly backups, weekly audits — all in natural language, running unattended.</td></tr>
<tr><td><b>Delegates and parallelizes</b></td><td>Spawn isolated subagents for parallel workstreams. Write Python scripts that call tools via RPC, collapsing multi-step pipelines into zero-context-cost turns.</td></tr>
<tr><td><b>Runs anywhere, not just your laptop</b></td><td>Seven terminal backends — local, Docker, SSH, Singularity, Modal, Daytona, and Vercel Sandbox. Daytona and Modal offer serverless persistence — your agent's environment hibernates when idle and wakes on demand, costing nearly nothing between sessions. Run it on a $5 VPS or a GPU cluster.</td></tr>
<tr><td><b>Research-ready</b></td><td>Batch trajectory generation, trajectory compression for training the next generation of tool-calling models.</td></tr>
</table>

---

## Install

**Option 1 — the built package.** Download the current release from [Releases](../../releases/latest), check it, install it:

```bash
sha256sum centurion-brain-*.rpm          # must match the .sha256 file beside it
sudo dnf install ./centurion-brain-*.rpm
```

**Option 2 — from source.** The one-liner sets up Python, uv, Node and ripgrep, then installs the agent:

```bash
curl -fsSL https://raw.githubusercontent.com/centurion-fleet/Centurion-AI-OS-Brain/main/scripts/install.sh | bash
```

Then:

```bash
centurion setup     # pick your model provider and paste the API key
centurion           # start
```

Either way, the first thing you do is point it at a model — OpenRouter, Anthropic, OpenAI, a local endpoint, whichever you already pay for. No model is bundled.

---

## The key, the community, the docs

- **The software is free and complete without a key.** Nothing is withheld and nothing expires.
- **A key turns on three things:** updates as they ship, the community, and being helped by a person. It is free — [one field, thirty seconds](https://www.1human1ai.com/key).
- **Installation instructions and the FAQ are public** and always will be: [1human1ai.com/install](https://www.1human1ai.com/install).
- **Questions about the software belong in [Discussions](../../discussions).** A reproducible defect belongs in [Issues](../../issues) — read [CONTRIBUTING.md](CONTRIBUTING.md) first, which says what we take without a discussion and what needs one.

---

## Getting Started

```bash
centurion              # Interactive CLI — start a conversation
centurion model        # Choose your LLM provider and model
centurion tools        # Configure which tools are enabled
centurion config set   # Set individual config values
centurion gateway      # Start the messaging gateway (Telegram, Discord, etc.)
centurion setup        # Run the full setup wizard (configures everything at once)
centurion claw migrate # Migrate from OpenClaw (if coming from OpenClaw)
centurion update       # Update to the latest version
centurion doctor       # Diagnose any issues
```

---

## Centurion subscription (coming soon)

Centurion AI OS works with your own API keys today — run `centurion setup` and pick OpenRouter, Anthropic, LM Studio, or another provider.

A unified **Centurion Portal** subscription at [portal.personal-centurion.com](https://portal.personal-centurion.com) (models + hosted tools under one plan) is in development. When it launches, enable it in config with `billing.enabled: true` and use `centurion setup --portal`.

---

## CLI vs Messaging Quick Reference

Centurion AI OS has two entry points: start the terminal UI with `centurion`, or run the gateway and talk to it from Telegram, Discord, Slack, WhatsApp, Signal, or Email. Once you're in a conversation, many slash commands are shared across both interfaces.

| Action | CLI | Messaging platforms |
|---------|-----|---------------------|
| Start chatting | `centurion` | Run `centurion gateway setup` + `centurion gateway start`, then send the bot a message |
| Start fresh conversation | `/new` or `/reset` | `/new` or `/reset` |
| Change model | `/model [provider:model]` | `/model [provider:model]` |
| Set a personality | `/personality [name]` | `/personality [name]` |
| Retry or undo the last turn | `/retry`, `/undo` | `/retry`, `/undo` |
| Compress context / check usage | `/compress`, `/usage`, `/insights [--days N]` | `/compress`, `/usage`, `/insights [days]` |
| Browse skills | `/skills` or `/<skill-name>` | `/<skill-name>` |
| Interrupt current work | `Ctrl+C` or send a new message | `/stop` or send a new message |
| Platform-specific status | `/platforms` | `/status`, `/sethome` |

For the full command lists, run `centurion --help` or see the documentation section below.

---

## Documentation

Centurion AI OS documentation is in progress. Use `centurion --help`, `centurion setup`, and `centurion doctor` to get started. Config and secrets live under `~/.centurion/`.

---

## Versioning & Releases

Centurion AI OS, the **Centurion Desktop App** (Tauri/Linux), and the **CenturionAI Remote** (iPhone app) are **versioned in lockstep** — all three products carry the same version number and are released together under a single release tag.

| Version | Codename | Products |
|---------|----------|----------|
| v3.0.0 | **Centurion v3 — Mission Horizon** | Centurion AI OS + Desktop App + iPhone App |

Releases are tagged in this repository. The version number is defined in `centurion_cli/__init__.py` (`__version__`) and `pyproject.toml`. When a new release ships, the iOS app and desktop app tags or version metadata are updated to match.

---

## Migrating from OpenClaw

If you're coming from OpenClaw, Centurion AI OS can automatically import your settings, memories, skills, and API keys.

**During first-time setup:** The setup wizard (`centurion setup`) automatically detects `~/.openclaw` and offers to migrate before configuration begins.

**Anytime after install:**

```bash
centurion claw migrate              # Interactive migration (full preset)
centurion claw migrate --dry-run    # Preview what would be migrated
centurion claw migrate --preset user-data   # Migrate without secrets
centurion claw migrate --overwrite  # Overwrite existing conflicts
```

What gets imported:
- **SOUL.md** — persona file
- **Memories** — MEMORY.md and USER.md entries
- **Skills** — user-created skills → `~/.centurion/skills/openclaw-imports/`
- **Command allowlist** — approval patterns
- **Messaging settings** — platform configs, allowed users, working directory
- **API keys** — allowlisted secrets (Telegram, OpenRouter, OpenAI, Anthropic, ElevenLabs)
- **TTS assets** — workspace audio files
- **Workspace instructions** — AGENTS.md (with `--workspace-target`)

See `centurion claw migrate --help` for all options.

---

## Contributing

We welcome contributions!

Quick start for contributors:

```bash
git clone https://github.com/centurion-fleet/Centurion-AI-OS.git
cd Centurion-AI-OS
uv venv .venv --python 3.11
source .venv/bin/activate
uv pip install -e ".[all,dev]"
scripts/run_tests.sh
centurion              # start chatting
```

---

## Community

- 📚 [Skills Hub](https://agentskills.io)
- 🐛 [Issues](https://github.com/centurion-fleet/Centurion-AI-OS/issues)
- 🔌 [computer-use-linux](https://github.com/avifenesh/computer-use-linux) — Linux desktop-control MCP server for agent hosts, with AT-SPI accessibility trees, Wayland/X11 input, screenshots, and compositor window targeting.

---

Built on open-source agent infrastructure. MIT — see [LICENSE](LICENSE).
