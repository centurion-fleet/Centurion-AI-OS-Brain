"""centurion vault — init, unlock, lock, status, proposals, commit, reject.

Offline sealed long-term memory CLI. No network.
"""

from __future__ import annotations

import argparse
import getpass
import sys
from typing import Optional

from centurion_constants import display_centurion_home


def build_parser(subparsers: argparse._SubParsersAction) -> argparse.ArgumentParser:
    parser = subparsers.add_parser(
        "vault",
        help="Offline sealed long-term memory (Vault)",
        description=(
            "Manage Centurion Vault — encrypted local long-term memory.\n"
            "100% offline. No cloud sync. Passphrase unlock required."
        ),
    )
    sub = parser.add_subparsers(dest="vault_command")

    sub.add_parser("init", help="Create Vault key + empty database")
    sub.add_parser("unlock", help="Unlock Vault for this process (prompts passphrase)")
    sub.add_parser("lock", help="Lock Vault and clear FTS plaintext index")
    sub.add_parser("status", help="Show Vault lock state and counts")
    sub.add_parser("proposals", help="List pending proposals")

    commit_p = sub.add_parser("commit", help="Commit a pending proposal")
    commit_p.add_argument("proposal_id", help="Proposal UUID")

    reject_p = sub.add_parser("reject", help="Reject a pending proposal")
    reject_p.add_argument("proposal_id", help="Proposal UUID")

    search_p = sub.add_parser("search", help="Hybrid search (requires unlock)")
    search_p.add_argument("query", help="Search query")
    search_p.add_argument(
        "--type",
        dest="memory_type",
        choices=["core", "experiential", "pattern"],
        default=None,
    )
    search_p.add_argument("--limit", type=int, default=8)

    install_p = sub.add_parser(
        "install-model",
        help="Download the offline embedding GGUF once (operator-initiated)",
    )
    install_p.add_argument(
        "--url",
        default="",
        help="Optional HTTPS URL to a GGUF file (must match expected checksum)",
    )
    install_p.add_argument(
        "--force",
        action="store_true",
        help="Re-download even if the model file already exists",
    )

    return parser


def _prompt_passphrase(confirm: bool = False) -> str:
    pw = getpass.getpass("Vault passphrase: ")
    if confirm:
        pw2 = getpass.getpass("Confirm passphrase: ")
        if pw != pw2:
            print("  Passphrases do not match.", file=sys.stderr)
            sys.exit(1)
    if len(pw) < 8:
        print("  Passphrase must be at least 8 characters.", file=sys.stderr)
        sys.exit(1)
    return pw


def vault_command(args: argparse.Namespace) -> None:
    cmd = getattr(args, "vault_command", None)
    if not cmd:
        print(
            f"\n  Vault lives at {display_centurion_home()}/vault/\n"
            "  Commands: init | unlock | lock | status | proposals | "
            "commit | reject | search\n"
        )
        return

    from agent.vault import (
        VaultCryptoError,
        initialize,
        is_initialized,
        lock_shared,
        open_vault,
    )

    if cmd == "init":
        if is_initialized():
            print(
                f"\n  Vault already initialized at {display_centurion_home()}/vault/\n"
            )
            return
        print("\n  Creating offline Vault (AES-256-GCM, Scrypt-wrapped key).")
        print("  Threat model: protects disk while locked; not a hostile OS while unlocked.\n")
        pw = _prompt_passphrase(confirm=True)
        try:
            vault = initialize(pw)
        except VaultCryptoError as exc:
            print(f"  ✗ {exc}\n", file=sys.stderr)
            sys.exit(1)
        st = vault.status()
        print(f"  ✓ Vault initialized at {st['vault_dir']}")
        print("  Unlocked for this process. Run `centurion vault lock` when done.\n")
        return

    if cmd == "status":
        vault = open_vault()
        st = vault.status()
        print(f"\n  Vault: {st['vault_dir']}")
        print(f"  Key present: {st['key_present']}")
        print(f"  Unlocked:    {st['unlocked']}")
        print(f"  Embedder:    {st['embedder']}")
        print(f"  Entries:     {st['total_entries']} "
              f"(core={st['counts']['core']}, "
              f"experiential={st['counts']['experiential']}, "
              f"pattern={st['counts']['pattern']})")
        print(f"  Pending:     {st['pending_proposals']}\n")
        return

    if cmd == "lock":
        lock_shared()
        # Also lock a freshly opened store so FTS clears if shared was None
        vault = open_vault()
        vault.lock()
        print("\n  ✓ Vault locked. FTS plaintext index cleared.\n")
        return

    if cmd == "unlock":
        if not is_initialized():
            print("\n  Vault not initialized. Run: centurion vault init\n")
            sys.exit(1)
        pw = _prompt_passphrase()
        try:
            vault = open_vault(pw)
        except Exception as exc:
            print(f"  ✗ {exc}\n", file=sys.stderr)
            sys.exit(1)
        print(f"\n  ✓ Vault unlocked ({vault.status()['total_entries']} entries).\n")
        return

    if cmd == "install-model":
        # Needs no Vault access at all — it only downloads the embedder GGUF.
        # Handled before the unlock block, which previously prompted for a
        # passphrase and then died with EOFError when run non-interactively.
        _install_embedding_model(
            url=getattr(args, "url", "") or "",
            force=bool(getattr(args, "force", False)),
        )
        return

    # Remaining commands need unlock
    vault = open_vault()
    if not vault.is_unlocked:
        pw = _prompt_passphrase()
        try:
            vault.unlock(pw)
        except Exception as exc:
            print(f"  ✗ {exc}\n", file=sys.stderr)
            sys.exit(1)

    if cmd == "proposals":
        props = vault.list_proposals()
        if not props:
            print("\n  No pending proposals.\n")
            return
        print(f"\n  Pending proposals ({len(props)}):")
        for p in props:
            preview = p.text[:72] + ("…" if len(p.text) > 72 else "")
            print(f"    {p.id}  [{p.memory_type.value}]  {preview}")
        print()
        return

    if cmd == "commit":
        try:
            entry = vault.commit(args.proposal_id)
        except Exception as exc:
            print(f"  ✗ {exc}\n", file=sys.stderr)
            sys.exit(1)
        print(f"\n  ✓ Committed entry {entry.id} [{entry.memory_type.value}]\n")
        return

    if cmd == "reject":
        try:
            vault.reject(args.proposal_id)
        except Exception as exc:
            print(f"  ✗ {exc}\n", file=sys.stderr)
            sys.exit(1)
        print(f"\n  ✓ Rejected proposal {args.proposal_id}\n")
        return

    if cmd == "search":
        hits = vault.search(
            args.query,
            memory_type=getattr(args, "memory_type", None),
            limit=getattr(args, "limit", 8),
        )
        if not hits:
            print("\n  No matches.\n")
            return
        print(f"\n  Results ({len(hits)}):")
        for h in hits:
            print(f"    [{h.score:.3f}] {h.memory_type.value}  {h.id}")
            print(f"           {h.snippet}")
        print()
        return

    print(f"  Unknown vault command: {cmd}", file=sys.stderr)
    sys.exit(1)


# Pinned offline embedder — checksum is the integrity gate after download.
_DEFAULT_MODEL_URL = (
    "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/"
    "nomic-embed-text-v1.5.Q4_K_M.gguf"
)
# Empty expected hash allows first install; set when a release pins a known file.
_EXPECTED_SHA256 = ""


def _install_embedding_model(*, url: str = "", force: bool = False) -> None:
    """Operator-initiated one-time download of the local GGUF embedder."""
    import hashlib
    import urllib.request

    from agent.vault.paths import (
        DEFAULT_MODEL_FILENAME,
        ensure_vault_dir,
        model_path,
        models_dir,
        secure_file,
    )

    ensure_vault_dir()
    models_dir().mkdir(parents=True, exist_ok=True)
    dest = model_path(DEFAULT_MODEL_FILENAME)
    sha_path = dest.with_suffix(dest.suffix + ".sha256")

    if dest.exists() and not force:
        print(f"\n  Model already present: {dest}")
        print("  Use --force to re-download.\n")
        return

    source = (url or _DEFAULT_MODEL_URL).strip()
    if not source.startswith("https://"):
        print("  ✗ Model URL must be https://", file=sys.stderr)
        sys.exit(1)

    print(f"\n  Downloading offline embedding model…")
    print(f"  {source}")
    tmp = dest.with_suffix(".partial")
    try:
        urllib.request.urlretrieve(source, tmp)  # noqa: S310 — operator-initiated HTTPS
    except Exception as exc:
        print(f"  ✗ Download failed: {exc}\n", file=sys.stderr)
        if tmp.exists():
            tmp.unlink()
        sys.exit(1)

    digest = hashlib.sha256(tmp.read_bytes()).hexdigest()
    if _EXPECTED_SHA256 and digest != _EXPECTED_SHA256:
        tmp.unlink(missing_ok=True)
        print(
            f"  ✗ Checksum mismatch.\n    got:  {digest}\n    want: {_EXPECTED_SHA256}\n",
            file=sys.stderr,
        )
        sys.exit(1)

    tmp.replace(dest)
    secure_file(dest)
    sha_path.write_text(digest + "\n", encoding="utf-8")
    secure_file(sha_path)
    print(f"  ✓ Installed {dest.name}")
    print(f"  SHA-256: {digest}")
    print("  Runtime stays offline after this one-time install.\n")
