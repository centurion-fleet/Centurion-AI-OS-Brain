"""
Bonjour/mDNS advertisement for iPhone discovery.

Advertises ``_centurion._tcp`` on the local network so the Centurion
iOS app can discover this device without any configuration, cloud
lookup, or central server.

This is the foundation of Centurion's zero-configuration security:
if the iPhone can't reach your network, it can't even see your
Centurion exists.
"""

import logging
import socket
import threading
from typing import Optional

_log = logging.getLogger(__name__)

_SERVICE_TYPE = "_centurion._tcp"
_SERVICE_NAME = "Centurion OS Desktop"
_PORT = 9119

_advertiser: Optional[threading.Thread] = None
_stop_event = threading.Event()


def _get_local_ip() -> str:
    """Get the primary local IP address for advertising."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0.1)
        # Doesn't actually connect — just used to determine the local IP
        s.connect(("10.255.255.255", 1))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def start_advertisement(port: int = _PORT):
    """
    Start advertising this Centurion via mDNS/Bonjour.

    Runs in a background daemon thread. Advertises the service
    type ``_centurion._tcp`` so the iOS app can discover it.

    Called automatically by ``start_server()`` — no manual invocation needed.
    """
    global _advertiser

    if _advertiser and _advertiser.is_alive():
        return  # Already advertising

    _stop_event.clear()

    def _run():
        try:
            from zeroconf import IPVersion, ServiceInfo, Zeroconf

            local_ip = _get_local_ip()
            hostname = socket.gethostname()
            fqdn = f"{hostname}.local."

            info = ServiceInfo(
                type_=_SERVICE_TYPE,
                name=f"{_SERVICE_NAME}.{_SERVICE_TYPE}",
                addresses=[socket.inet_aton(local_ip)],
                port=port,
                properties={
                    "version": "0.1.0",
                    "hostname": hostname,
                },
                server=fqdn,
            )

            zc = Zeroconf(ip_version=IPVersion.V4Only)
            zc.register_service(info)
            _log.info(
                "Bonjour: advertising %s on %s:%d as %s",
                _SERVICE_TYPE, local_ip, port, _SERVICE_NAME,
            )

            # Wait until told to stop
            _stop_event.wait()

            zc.unregister_service(info)
            zc.close()
            _log.info("Bonjour: advertisement stopped")

        except ImportError:
            _log.warning(
                "Bonjour advertisement requires zeroconf: "
                "pip install zeroconf"
            )
        except Exception as exc:
            _log.warning("Bonjour advertisement failed: %s", exc)

    _advertiser = threading.Thread(target=_run, daemon=True, name="bonjour")
    _advertiser.start()


def stop_advertisement():
    """Stop the Bonjour advertisement."""
    _stop_event.set()
