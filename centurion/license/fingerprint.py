"""Hardware / install identity fingerprint for license binding.

v1 composite (no TPM required):
  install_id + OS machine id + SMBIOS/board serial (when readable)
  + optional Desktop remote pubkey fingerprint
"""

from __future__ import annotations

import hashlib
import logging
import platform
import subprocess
from pathlib import Path
from typing import Dict, Optional

logger = logging.getLogger(__name__)


def _safe_read_text(path: Path) -> Optional[str]:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore").strip()
        return text or None
    except OSError:
        return None


def _macos_platform_uuid() -> Optional[str]:
    try:
        out = subprocess.check_output(
            ["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
            stderr=subprocess.DEVNULL,
            timeout=5,
        ).decode("utf-8", errors="ignore")
    except (OSError, subprocess.SubprocessError):
        return None
    for line in out.splitlines():
        if "IOPlatformUUID" in line:
            # "IOPlatformUUID" = "XXXXXXXX-...."
            parts = line.split("=", 1)
            if len(parts) == 2:
                return parts[1].strip().strip('"')
    return None


def _linux_machine_id() -> Optional[str]:
    for candidate in (Path("/etc/machine-id"), Path("/var/lib/dbus/machine-id")):
        value = _safe_read_text(candidate)
        if value:
            return value
    return None


def _windows_machine_guid() -> Optional[str]:
    try:
        import winreg  # type: ignore

        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"SOFTWARE\Microsoft\Cryptography",
        )
        try:
            value, _ = winreg.QueryValueEx(key, "MachineGuid")
            return str(value).strip() or None
        finally:
            winreg.CloseKey(key)
    except Exception:
        return None


def os_machine_id() -> Optional[str]:
    system = platform.system().lower()
    if system == "darwin":
        return _macos_platform_uuid()
    if system == "linux":
        return _linux_machine_id()
    if system == "windows":
        return _windows_machine_guid()
    return None


def board_serial() -> Optional[str]:
    """Best-effort SMBIOS / board serial. Empty when unavailable."""
    system = platform.system().lower()
    if system == "linux":
        for candidate in (
            Path("/sys/class/dmi/id/board_serial"),
            Path("/sys/class/dmi/id/product_uuid"),
        ):
            value = _safe_read_text(candidate)
            if value and value.lower() not in {"none", "not specified", "to be filled by o.e.m."}:
                return value
    if system == "darwin":
        try:
            out = subprocess.check_output(
                ["system_profiler", "SPHardwareDataType"],
                stderr=subprocess.DEVNULL,
                timeout=8,
            ).decode("utf-8", errors="ignore")
        except (OSError, subprocess.SubprocessError):
            return None
        for line in out.splitlines():
            if "Serial Number" in line:
                parts = line.split(":", 1)
                if len(parts) == 2:
                    return parts[1].strip() or None
    return None


def remote_pubkey_fingerprint() -> Optional[str]:
    """Optional Desktop remote device fingerprint from devices.json."""
    try:
        from centurion_constants import get_centurion_home

        devices = get_centurion_home() / "remote" / "devices.json"
        if not devices.exists():
            return None
        import json

        data = json.loads(devices.read_text(encoding="utf-8"))
        # Prefer first approved device fingerprint if present.
        approved = data.get("approved") or data.get("devices") or []
        if isinstance(approved, dict):
            for entry in approved.values():
                if isinstance(entry, dict) and entry.get("fingerprint"):
                    return str(entry["fingerprint"])
        elif isinstance(approved, list):
            for entry in approved:
                if isinstance(entry, dict) and entry.get("fingerprint"):
                    return str(entry["fingerprint"])
    except Exception as exc:
        logger.debug("remote fingerprint unavailable: %s", exc)
    return None


def collect_identity_parts(
    *,
    install_id: Optional[str] = None,
    include_remote: bool = True,
) -> Dict[str, str]:
    """Return the named components that feed the fingerprint hash."""
    if install_id is None:
        try:
            from centurion_cli.cloud_client import get_install_id

            install_id = get_install_id()
        except Exception:
            install_id = "unknown"

    parts: Dict[str, str] = {
        "install_id": str(install_id or "unknown"),
    }
    mid = os_machine_id()
    if mid:
        parts["os_machine_id"] = mid
    serial = board_serial()
    if serial:
        parts["board_serial"] = serial
    if include_remote:
        remote_fp = remote_pubkey_fingerprint()
        if remote_fp:
            parts["remote_pubkey_fp"] = remote_fp
    # Stable hostname is intentionally NOT included — too easy to spoof/change.
    parts["platform"] = platform.system().lower()
    return parts


def compute_fingerprint(
    *,
    install_id: Optional[str] = None,
    include_remote: bool = True,
    parts: Optional[Dict[str, str]] = None,
) -> str:
    """SHA-256 hex digest of the sorted identity composite."""
    identity = parts if parts is not None else collect_identity_parts(
        install_id=install_id,
        include_remote=include_remote,
    )
    # Deterministic canonical form.
    lines = [f"{k}={identity[k]}" for k in sorted(identity.keys())]
    blob = "\n".join(lines).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def fingerprint_short(fingerprint: Optional[str] = None) -> str:
    fp = fingerprint or compute_fingerprint()
    return fp[:16]
