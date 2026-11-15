"""First run: the practice is set up in software, by clicking, with no terminal.

WHY THIS EXISTS
---------------
Everything else in the desk assumes a partner already exists. `people_invite`
requires a signed-in partner because only a partner may add people — which is
correct, and which means the FIRST partner could only be made by typing
`centurion practice-desk invite …` on the machine. That single command was the
only place a customer had to touch a terminal, and a customer who has to open one
is a customer we have lost.

So this module is the doorway: the machine boots, the screen says "this is your
practice's machine", and a partner is created by clicking. Everything after that
first partner already exists in the desk.

THREE PARTS
-----------
1. **The wizard page** — practice name, then the partner who owns it. Two fields
   a person already knows, and no password: the account is claimed by a passkey
   in the ordinary sign-in flow.
2. **An automatic certificate.** A passkey cannot be registered over plain HTTP on
   a network address, so the moment the desk serves more than this one machine it
   needs TLS. Rather than ask anyone for `--tls-cert`, the machine issues its own
   CA and leaf once and reuses them. The CA is what a staff machine installs to
   trust the practice's own address — the join step.
3. **The gate.** With no people on the machine, every route leads to the wizard.
   Not a banner, not a hint: a machine with nobody on it has not been set up yet,
   and any other screen there is a screen that cannot do anything.

WHAT THIS IS NOT
----------------
It is not a setup for the platform's own settings — model provider, API keys and
the rest live in the Brain's own settings surface. This is the practice's front
door only.
"""

from __future__ import annotations

import datetime as _dt
import ipaddress
import os
import socket
from pathlib import Path
from typing import Optional

from centurion_cli.practice_desk.store import DeskError

PRACTICE_NAME_KEY = "practice_name"
SETUP_COMPLETE_KEY = "setup_complete_at"
CA_FILENAME = "practice-ca.crt"
CERT_FILENAME = "practice-cert.pem"
KEY_FILENAME = "practice-key.pem"

# 825 days is the longest leaf a modern browser accepts without complaint.
_LEAF_DAYS = 825
_CA_DAYS = 3650


# ── the practice's own identity ──────────────────────────────────────────────


def practice_name(store) -> Optional[str]:
    """What the firm calls itself, or None before setup."""
    with store.connect() as conn:
        row = conn.execute(
            "SELECT value FROM meta WHERE key = ?", (PRACTICE_NAME_KEY,)
        ).fetchone()
    return row["value"] if row else None


def set_practice_name(store, name: str) -> str:
    name = " ".join((name or "").split())
    if not name:
        # A DeskError, not a ValueError: the middleware turns one into a sentence
        # a customer can act on, and the other into "something went wrong".
        raise DeskError("The practice needs a name before we can go on.")
    if len(name) > 120:
        raise DeskError("That name is too long for the front door.")
    with store.connect() as conn:
        conn.execute(
            "INSERT INTO meta(key, value) VALUES (?, ?)"
            " ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (PRACTICE_NAME_KEY, name),
        )
    return name


def is_set_up(store) -> bool:
    """True when at least one person exists — the only test that matters.

    Deliberately not a flag we set: a flag can say "set up" on a machine whose
    register was replaced or emptied, and then the front door opens onto nothing.
    People are the fact.
    """
    return bool(store.list_people(include_departed=True))


def mark_setup_complete(store) -> None:
    stamp = _dt.datetime.now(_dt.timezone.utc).isoformat()
    with store.connect() as conn:
        conn.execute(
            "INSERT INTO meta(key, value) VALUES (?, ?)"
            " ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (SETUP_COMPLETE_KEY, stamp),
        )


# ── the certificate the machine issues for itself ────────────────────────────


class LocalTLS:
    """The paths a TLS context needs, and whether this call minted them."""

    def __init__(self, cert: Path, key: Path, ca: Path, created: bool = False) -> None:
        self.cert = cert
        self.key = key
        self.ca = ca
        self.created = created


def _subject_alt_names(names: list[str], ips: list[str]) -> list:
    from cryptography import x509

    entries: list = []
    seen: set[str] = set()
    for name in names:
        name = (name or "").strip().lower().rstrip(".")
        if name and name not in seen:
            seen.add(name)
            entries.append(x509.DNSName(name))
    for ip in ips:
        try:
            addr = ipaddress.ip_address(ip)
        except ValueError:
            continue
        if str(addr) not in seen:
            seen.add(str(addr))
            entries.append(x509.IPAddress(addr))
    return entries


def _covers(cert_path: Path, names: list[str], ips: list[str]) -> bool:
    """Is the existing leaf still valid for every name we are about to serve on?

    Cheap and worth it: a certificate minted for yesterday's address produces a
    browser warning that reads to a principal as "this software is broken".
    """
    try:
        from cryptography import x509

        cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
        if cert.not_valid_after_utc <= _dt.datetime.now(_dt.timezone.utc):
            return False
        san = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
        have = {n.lower() for n in san.get_values_for_type(x509.DNSName)}
        have |= {str(i) for i in san.get_values_for_type(x509.IPAddress)}
        want = {n.strip().lower().rstrip(".") for n in names if n.strip()}
        want |= {str(ipaddress.ip_address(i)) for i in ips if _is_ip(i)}
        return want.issubset(have)
    except Exception:  # noqa: BLE001 — any doubt means mint again
        return False


def _is_ip(value: str) -> bool:
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return False


def ensure_local_tls(
    directory: Path,
    *,
    names: Optional[list[str]] = None,
    ips: Optional[list[str]] = None,
) -> LocalTLS:
    """Mint (once) a CA and a leaf for this machine, and return their paths.

    The CA is the artefact a staff machine installs; the leaf is what the desk
    serves. Both live beside the practice database, with the private key at 0600.
    """
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    cert_path = directory / CERT_FILENAME
    key_path = directory / KEY_FILENAME
    ca_path = directory / CA_FILENAME

    names = [n for n in (names or []) if n]
    ips = [i for i in (ips or []) if i]

    if cert_path.exists() and key_path.exists() and _covers(cert_path, names, ips):
        return LocalTLS(cert_path, key_path, ca_path, created=False)

    now = _dt.datetime.now(_dt.timezone.utc)
    hostname = socket.gethostname().split(".")[0]
    org = x509.Name([x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Centurion practice")])

    # ── the CA ──────────────────────────────────────────────────────────────
    ca_key = ec.generate_private_key(ec.SECP256R1())
    ca_name = x509.Name(
        [
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Centurion practice"),
            x509.NameAttribute(NameOID.COMMON_NAME, f"{hostname} practice CA"),
        ]
    )
    ca_cert = (
        x509.CertificateBuilder()
        .subject_name(ca_name)
        .issuer_name(ca_name)
        .public_key(ca_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - _dt.timedelta(minutes=5))
        .not_valid_after(now + _dt.timedelta(days=_CA_DAYS))
        .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=True,
                crl_sign=True,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .sign(ca_key, hashes.SHA256())
    )

    # ── the leaf ────────────────────────────────────────────────────────────
    leaf_key = ec.generate_private_key(ec.SECP256R1())
    sans = _subject_alt_names(names or [hostname, "localhost"], ips or ["127.0.0.1"])
    leaf_cert = (
        x509.CertificateBuilder()
        .subject_name(
            x509.Name(
                [
                    x509.NameAttribute(
                        NameOID.ORGANIZATION_NAME, "Centurion practice"
                    ),
                    x509.NameAttribute(
                        NameOID.COMMON_NAME, names[0] if names else hostname
                    ),
                ]
            )
        )
        .issuer_name(ca_name)
        .public_key(leaf_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - _dt.timedelta(minutes=5))
        .not_valid_after(now + _dt.timedelta(days=_LEAF_DAYS))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(x509.SubjectAlternativeName(sans), critical=False)
        .add_extension(
            x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False
        )
        .sign(ca_key, hashes.SHA256())
    )

    _write(ca_path, ca_cert.public_bytes(serialization.Encoding.PEM), 0o644)
    _write(cert_path, leaf_cert.public_bytes(serialization.Encoding.PEM), 0o644)
    _write(
        key_path,
        leaf_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ),
        0o600,
    )
    return LocalTLS(cert_path, key_path, ca_path, created=True)


def _write(path: Path, data: bytes, mode: int) -> None:
    if path.exists():
        path.unlink()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "wb") as fh:
        fh.write(data)


# ── the page ─────────────────────────────────────────────────────────────────

_CSS = """
:root{--void:#0d0f12;--plate:#16181d;--line:#2a2d34;--ink:#efeae1;--dim:#9a958c;
      --bronze:#b08d57;--bronze-dim:#7d6440;--bad:#c4675c;--good:#7fa87a}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--void);color:var(--ink);font:15px/1.55 -apple-system,BlinkMacSystemFont,
     "Segoe UI",Roboto,Helvetica,Arial,sans-serif;min-height:100vh;
     display:flex;align-items:center;justify-content:center;padding:32px 20px}
.card{width:100%;max-width:560px}
.mark{font-size:11px;letter-spacing:.18em;text-transform:uppercase;color:var(--bronze);
      font-weight:700;margin-bottom:14px}
h1{font-size:27px;line-height:1.2;font-weight:600;letter-spacing:-.01em;margin-bottom:10px}
p.lede{color:var(--dim);margin-bottom:26px}
label{display:block;font-size:12px;letter-spacing:.1em;text-transform:uppercase;
      color:var(--dim);margin-bottom:7px;font-weight:600}
input{width:100%;background:var(--plate);border:1px solid var(--line);border-radius:6px;
      color:var(--ink);padding:13px 14px;font-size:15px;margin-bottom:18px}
input:focus{outline:none;border-color:var(--bronze)}
button{width:100%;background:var(--bronze);border:0;border-radius:6px;color:#171410;
       padding:14px;font-size:15px;font-weight:650;cursor:pointer}
button:disabled{opacity:.5;cursor:default}
.step{display:none}.step.on{display:block}
.note{color:var(--dim);font-size:13px;margin-top:16px}
.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;
      background:var(--plate);border:1px solid var(--line);border-radius:6px;
      padding:12px;word-break:break-all;margin:12px 0}
.link{display:block;background:var(--plate);border:1px solid var(--bronze-dim);
      border-radius:6px;padding:14px;color:var(--ink);text-decoration:none;margin:10px 0;
      font-size:14px}
.link:hover{border-color:var(--bronze)}
.link b{display:block;color:var(--bronze);font-size:11px;letter-spacing:.12em;
        text-transform:uppercase;margin-bottom:5px}
.err{color:var(--bad);font-size:13px;margin-top:12px;min-height:18px}
.ok{color:var(--good)}
h2{font-size:17px;font-weight:600;margin:22px 0 8px}
ul{margin:0 0 0 18px;color:var(--dim)}li{margin-bottom:6px}
"""

_PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Set up your practice · Centurion</title>
<style>{css}</style></head>
<body><div class="card">
<div class="mark">Centurion · first run</div>

<section class="step on" id="s1">
  <h1>This is your practice&rsquo;s machine.</h1>
  <p class="lede">Two things and it is running. No password &mdash; you will use your
     fingerprint or face to sign in.</p>
  <label for="pname">What is the practice called?</label>
  <input id="pname" placeholder="Courtwright &amp; Co" autocomplete="organization" autofocus>
  <label for="oname">Your name</label>
  <input id="oname" placeholder="Margaret Courtwright" autocomplete="name">
  <label for="oemail">Your email</label>
  <input id="oemail" type="email" placeholder="margaret@courtwright.co.uk" autocomplete="email">
  <button id="go">Create the practice</button>
  <div class="err" id="err1"></div>
  <p class="note">You will be the first partner. A partner is the only person who can
     sign a letter to a client, so the machine will not let you leave the practice
     with nobody who can sign.</p>
</section>

<section class="step" id="s2">
  <h1>Now claim your account.</h1>
  <p class="lede">Open this link on this machine. You will be asked for your
     fingerprint or face, and that becomes your way in &mdash; there is no password
     to remember or to lose.</p>
  <div id="claim"></div>
  <p class="note">This link works once and expires in fifteen minutes. If it lapses,
     ask for another &mdash; nothing is lost.</p>
  <button id="done" style="margin-top:18px">I have claimed it</button>
</section>

<section class="step" id="s3">
  <h1 id="greet">The practice is running.</h1>
  <p class="lede">Three things worth knowing before you add your colleagues.</p>

  <h2>Add your people</h2>
  <ul><li>Inside the desk: <b>People &rarr; Invite</b>. Each person gets their own
      account and their own conversation with the machine.</li>
  <li>Each of them clicks one link in an email, uses their fingerprint, and they
      are in. No passwords, no software to install.</li></ul>

  <h2>Your other machines</h2>
  <ul><li>If a colleague works on a different computer, that computer has to trust
      this one. <a id="ca" href="/setup/ca.crt" style="color:var(--bronze)">Download the
      practice certificate</a> and double-click it on their machine &mdash; that is
      the whole step.</li></ul>

  <h2>Your backups</h2>
  <ul><li>Weekly, onto a drive you keep. The machine prints your recovery key the
      first time &mdash; that sheet is the second way into the backup and it lives in
      the safe, not on the machine.</li></ul>

  <a class="link" href="/"><b>Open the desk</b>Sign in and start work</a>
</section>

<script>
const $ = (id) => document.getElementById(id);
const show = (n) => document.querySelectorAll('.step')
  .forEach((s) => s.classList.toggle('on', s.id === 's' + n));

async function post(url, body) {{
  const r = await fetch(url, {{
    method: 'POST',
    headers: {{'Content-Type': 'application/json'}},
    body: JSON.stringify(body || {{}}),
  }});
  const data = await r.json().catch(() => ({{}}));
  if (!r.ok) throw new Error(data.error || data.detail || ('Error ' + r.status));
  return data;
}}

$('go').addEventListener('click', async () => {{
  $('err1').textContent = '';
  const btn = $('go');
  btn.disabled = true;
  try {{
    const data = await post('/api/setup/practice', {{
      practice: $('pname').value,
      name: $('oname').value,
      email: $('oemail').value,
    }});
    const a = document.createElement('a');
    a.className = 'link';
    a.href = data.link;
    a.innerHTML = '<b>Claim your account</b>' + data.link;
    $('claim').appendChild(a);
    show(2);
  }} catch (e) {{
    $('err1').textContent = e.message;
    btn.disabled = false;
  }}
}});

$('done').addEventListener('click', () => {{
  $('greet').textContent = 'The practice is running.';
  show(3);
}});

document.querySelectorAll('#pname,#oname,#oemail').forEach((el) =>
  el.addEventListener('keydown', (e) => {{ if (e.key === 'Enter') $('go').click(); }}));
</script>
</div></body></html>
"""


def page(store) -> str:
    """The wizard, with the practice name already in it when there is one."""
    name = practice_name(store) or ""
    html = _PAGE.format(css=_CSS)
    if name:
        html = html.replace(
            'placeholder="Courtwright &amp; Co"', f'value="{_escape(name)}"', 1
        )
    return html


def _escape(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )
