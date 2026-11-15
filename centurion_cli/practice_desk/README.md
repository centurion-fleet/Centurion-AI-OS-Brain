# Practice desk

The signed-in browser client for the Practice edition. One named person per
session, a passkey instead of a password, and a register of who asked what.

Built as Build A and Build B of `~/centurion/business/SIGNUM-WEB-DESIGN-v1.0.pdf`:
one user and one private thread, then shared client threads, the assignment
register, the drafts queue a partner signs from, and capability narrowed by role.

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

Other verbs: `people`, `role --email … --role …`, `deadlines`,
`suspend --email … [--status …]`, `revoke --email …`, `audit`.
`--db PATH` on any verb points at a different register.

## ⚠️ The one deployment fact that surprises everybody

**A browser will not register a passkey over plain HTTP on a network address.**
`https://` and `http://localhost` are secure contexts; a bare LAN IP on port 8765
is not, and the browser refuses before the request leaves the machine.

So: `serve` binds to loopback without TLS, and **refuses** any other bind unless
`--tls-cert` and `--tls-key` are supplied. For a practice, the answer is a real
hostname with a real certificate (or a private CA installed on their machines),
reached over the practice network or a private link — never published to the
open internet.

This is the only thing blocking a second person on their own machine. It is a
naming decision (one hostname), not a code problem.

## What the licence decides, not this code

Seats. `store.capacity_refusal()` asks `current_edition().refusal(...)`, so the
sentence a partner reads when they try to add an eleventh person is the same
sentence that appears in the agreement. There is no second copy of the number.

On a Brain edition (one named user) the second invite is refused in the licence's
own words: *"the second user is a second machine, not a setting."*

## Two things a role must not be able to do

**An administrator cannot grant a role.** Administrators keep the machine; a
partner holds the signature and the client files. A role route open to
administrators would let the machine's keeper promote themselves — privilege
escalation with a friendly label — so `/api/people/role` refuses anyone who is
not a partner, in the route, not only in the UI.

**The last partner who can sign cannot be demoted.** The refusal names the
consequence rather than the rule: *"Demoting them would leave the practice with
nobody who may sign."* A partner who has been invited but not yet enrolled counts
as a signer, because they can sign the moment they enrol; a suspended one does
not.

## The record

Every admission, invitation, role change, suspension, assignment, refusal,
prepared draft and signature is written to `audit` and readable two ways:

- **In the desk**, under *People → The record*, newest first, with names resolved
  rather than ids. Someone who has left keeps their name on their rows; an id
  that no longer resolves prints as `departed seat`, never blank.
- **From the terminal**, `centurion practice-desk audit --limit 40`.

A refusal is recorded too — including a refusal to open a client's files. The
attempt is the interesting part, not only the success.

## First run — the customer never sees a terminal

⚠️ **Nothing below is for a customer.** The commands in "Run it" are for
development and for us. The product's own first run is a page:

On a machine with nobody on it, **every route leads to `/setup`** — a two-field
wizard: the practice's name, then the partner who owns it. It creates the first
partner by clicking, because every other way of creating a person needs a
signed-in partner and a brand-new machine has none. The wizard refuses to run a
second time, so it can never be used to sidestep `people_invite`.

The account is then claimed with a passkey in the ordinary sign-in flow. No
password is set, written down, or shared at any point.

### The certificate is issued by the machine

A passkey cannot be registered over plain HTTP on a network address, so a desk
serving anything but loopback needs TLS. Nobody is asked for a certificate: on
first network bind, `serve()` mints a CA and a leaf for this machine, writes them
beside the practice database (`tls/`, key at `0600`), and reuses them on every
later boot — reissuing only when the address changes or the leaf expires.

**The join step for a colleague's machine is one download and one double-click:**
`/setup/ca.crt`. Installing it is what makes that machine trust this one.

## What is deliberately missing

- **Clients chased / hours returned.** The panes return `null` with a stated
  reason rather than a zero. There is no correspondence register and no work log
  behind them yet, and a confident zero over a register that was never written is
  a lie a partner will act on.
- **A public name.** The machine can only issue a certificate for names and
  addresses it actually holds; reaching a practice from outside its own network
  is a tunnel question (the practice's tunnel, not ours) and is not built.

## Tests

```bash
./venv/bin/python -m pytest tests/practice_desk -q
```

91 tests. The four worth knowing about:

- `test_webauthn.py` builds the ceremony with a software authenticator — real
  P-256 keys, real DER signatures, real COSE layout — and then breaks exactly
  one thing per refusal test. A check that quietly stopped firing fails a test.
- `test_the_desk_refuses_a_post_that_did_not_come_from_the_desk` and
  `test_today_reports_unmeasured_panes_as_null_never_zero` guard the two
  invariants that matter commercially: a cookie is not authorisation for a POST,
  and an unreadable register is not an empty one.
- `test_desk_html.py` runs `node --check` over the desk's own script and asserts
  every element the script reaches for exists. A renamed id is a control that
  looks live and does nothing — the one failure this desk is not allowed to have.
