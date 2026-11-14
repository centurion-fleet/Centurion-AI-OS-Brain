# Practice desk

The signed-in browser client for the Practice edition. One named person per
session, a passkey instead of a password, and a record of who asked what.

This is **Build A** of `~/centurion/business/SIGNUM-WEB-DESIGN-v1.0.pdf`: one
user, one passkey, one private thread, computed deadlines, and the register that
makes a seat a real thing. Client threads and the Firm panel are Build B and are
not here.

## Run it

```bash
# 1. the sample practice (fictional clients) — optional, for demonstrations
centurion practice-desk demo

# 2. admit the first person and get a one-time link
centurion practice-desk invite --name "Adrian Barkus" \
    --email adrian@firm.example --role partner --origin http://127.0.0.1:8765

# 3. serve
centurion practice-desk serve \
    --host 127.0.0.1 --port 8765 \
    --origin http://127.0.0.1:8765 --rp-id 127.0.0.1 --library ~/centurion/practice/library
```

`python -m centurion_cli.practice_desk <verb>` does the same thing if the CLI is not
on PATH.

Open the link, enrol a passkey, and the desk opens on **Today**.

Other verbs: `people`, `deadlines`, `suspend --email … [--status …]`,
`revoke --email …`, `audit`. `--db PATH` on any verb points at a different
register.

## ⚠️ The one deployment fact that surprises everybody

**A browser will not register a passkey over plain HTTP on a network address.**
`https://` and `http://localhost` are secure contexts; a bare LAN IP on port 8765
is not, and the browser refuses before the request leaves the machine.

So: `serve` binds to loopback without TLS, and **refuses** any other bind unless
`--tls-cert` and `--tls-key` are supplied. For a practice, the answer is a real
hostname with a real certificate (or a private CA installed on their machines),
reached over the practice network or a private link — never published to the
open internet.

## What the licence decides, not this code

Seats. `store.capacity_refusal()` asks `current_edition().refusal(...)`, so the
sentence a partner reads when they try to add an eleventh person is the same
sentence that appears in the agreement. There is no second copy of the number.

## What is deliberately missing

- **Client threads and the Firm panel.** Build B, and they follow the drafts
  register — a Firm panel with no drafts to show is empty furniture.
- **Drafts awaiting signature / clients chased / hours returned.** The panes
  return `null` with a stated reason rather than a zero. A confident zero over a
  register that was never written is a lie a partner will act on.
- **Per-role toolsets.** A browser session currently carries the Brain's full
  toolset. Narrowing it by role (no shell, no writes outside the library, for a
  non-partner) is a design decision awaiting a ruling, not an oversight.

## Tests

```bash
./venv/bin/python -m pytest tests/practice_desk -q
```

63 tests. The two worth knowing about:

- `test_webauthn.py` builds the ceremony with a software authenticator — real
  P-256 keys, real DER signatures, real COSE layout — and then breaks exactly
  one thing per refusal test. A check that quietly stopped firing fails a test.
- `test_the_desk_refuses_a_post_that_did_not_come_from_the_desk` and
  `test_today_reports_unmeasured_panes_as_null_never_zero` guard the two
  invariants that matter commercially: a cookie is not authorisation for a POST,
  and an unreadable register is not an empty one.
