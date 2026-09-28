#!/usr/bin/env python3
"""Two owner-facing sheets, for Brain 7.0.4 ("Vox").

  1. connect-your-centurions.pdf  — hand to Steve: update, make reachable, connect.
  2. using-the-collaboration.pdf  — hand to both owners: what the link does once made.

Run with /usr/bin/python3 (weasyprint lives there, not in the venv).
House tokens shared with the Conjunction sheet: ink #110C09, paper #FAFAF9,
accent #433830, muted #5E534A, bronze #b08d57, border #EAE7E0.

The shared secret is deliberately NOT printed on either sheet — a document that
carries a credential is a credential. Both parties copy it from their own screen.
"""
import os

from weasyprint import HTML

OUT_DIR = os.path.expanduser("~/.centurion/document_cache")

CSS = """
@page {
  size: A4;
  margin: 13mm 14mm 12mm 14mm;
  @bottom-left  { content: "Centurion \\00b7 Sovereign AI Brain 7.0.4"; font-family: "Liberation Sans", sans-serif;
                  font-size: 7.5pt; color: #968D86; }
  @bottom-right { content: "page " counter(page) " of " counter(pages);
                  font-family: "Liberation Sans", sans-serif; font-size: 7.5pt; color: #968D86; }
}
@page :first { @bottom-left { content: ""; } @bottom-right { content: ""; } }
body { background: #FAFAF9; color: #110C09;
       font-family: "Liberation Sans", "DejaVu Sans", Arial, sans-serif;
       font-size: 8.2pt; line-height: 1.2; margin: 0; }
h1 { font-family: "Liberation Serif", Georgia, serif; font-size: 19pt; line-height: 1.08;
     margin: 0 0 3px 0; }
h2 { font-family: "Liberation Serif", Georgia, serif; font-size: 11pt; margin: 7px 0 1px 0;
     padding-top: 4px; border-top: 1px solid #EAE7E0; break-after: avoid; }
.mast { font-size: 7.6pt; letter-spacing: 2.2px; text-transform: uppercase; color: #b08d57;
        margin: 0 0 7px 0; }
.sub { color: #5E534A; font-size: 10pt; margin: 0; }
.rule { height: 2px; background: #433830; width: 44px; margin: 8px 0 9px 0; }
p { margin: 4px 0; }
ol, ul { margin: 4px 0 4px 0; padding-left: 16px; }
li { margin: 2px 0; }
table { width: 100%; border-collapse: collapse; margin: 6px 0 3px 0; break-inside: avoid; }
td { border-bottom: 1px solid #EAE7E0; padding: 3px 8px 3px 0; vertical-align: top; }
td.n { width: 24px; color: #b08d57; font-family: "Liberation Serif", Georgia, serif;
       font-weight: bold; }
.box { background: #FBF3E6; border: 1px solid #EFE2CB; border-radius: 6px;
       padding: 7px 10px; margin: 8px 0; break-inside: avoid; }
.box .t { font-size: 8pt; letter-spacing: 1.3px; text-transform: uppercase;
          color: #b08d57; margin-bottom: 3px; }
.say { font-family: "Liberation Mono", monospace; font-size: 8.6pt; background: #F2EFEA;
       padding: 1px 4px; border-radius: 3px; }
.quiet { color: #5E534A; font-size: 8.6pt; }
.keep { break-inside: avoid; }
.newpage { break-before: page; }
"""

# ── Sheet 1 ────────────────────────────────────────────────────────────────
CONNECT = """
<div class="mast">Centurion &middot; Sovereign AI Brain 7.0.4</div>
<h1>Connect your Centurion to Kim's</h1>
<div class="sub">Update first. Then two Centurions on the same WiFi learn to talk.</div>
<div class="rule"></div>

<p>Everything is here, in order, and nothing needs a terminal. If a step asks for a password,
that is the Fedora installer asking &mdash; not the Brain.</p>

<p class="quiet">The two machines: yours is <b>Eve</b>, Kim's is <b>Mikki</b>. Both run this
sheet. One side connected alone is a half-link, and it behaves exactly like a broken one.</p>

<div class="box">
  <div class="t">Before anything &mdash; two ten-second checks</div>
  <p style="margin:0 0 4px 0"><b>1. Is the Gateway running?</b> On each machine open the
  <b>You</b> tab (the right-hand tab at the top &mdash; that is where everything is set up), find
  the <b>This Brain</b> group, and look at the <b>Gateway</b> row inside it. It should read as
  running. If it does not, or it will not start, press <b>Start</b> next to it &mdash; the Brain
  sets that service up itself if it is missing, so Start now works even on a machine that has never
  had it. Making a Brain reachable restarts that service, which is why it has to be running.</p>
  <p style="margin:0"><b>2. Both machines must be on 7.0.4 or later.</b> The version is printed on
  the Brain's opening screen. If a machine is older, do step 1 first. The <b>Start</b> button was
  repaired in 7.0.3; the part that lets two connected Centurions send each other anything was
  repaired in 7.0.4. On an older Brain you can end up pressing a button that never changes, or
  finishing the connection and finding no message box to use at all.</p>
</div>

<h2>1 &middot; Update the Brain</h2>
<table>
  <tr><td class="n">1</td><td>Open <b>Sovereign AI Brain</b>. If it offers an update, take it. If it
  does not, carry on &mdash; the download below is the same thing.</td></tr>
  <tr><td class="n">2</td><td>Go to <b>personalcenturion.com</b> &rarr; sign in &rarr;
  <b>Account &rarr; Get Brain</b>, and download the installer.</td></tr>
  <tr><td class="n">3</td><td>In <b>Downloads</b>, double-click the file ending
  <span class="say">.rpm</span>. If asked, choose <b>Open with Software Install</b>.</td></tr>
  <tr><td class="n">4</td><td>Press <b>Install</b>, enter your password if asked, and wait.</td></tr>
  <tr><td class="n">5</td><td>Open <b>Sovereign AI Brain</b> from Activities. Do this on
  <b>both</b> machines.</td></tr>
</table>

<div class="box">
  <div class="t">If Software warns you</div>
  <p style="margin:0">It may say <i>Potentially Unsafe &mdash; provided by a third party</i>. That is
  Software's standard note for anything that did not come from Fedora's own store. It is expected,
  it is not a virus warning, and the installer is signed by Centurion AI Agent Limited.</p>
</div>

<h2>2 &middot; Make each Brain reachable &mdash; on both machines</h2>
<p>This is the step that was failing before. Do it on <b>both</b> machines. Each produces two
values &mdash; an <b>address</b> and a <b>secret</b> &mdash; which you then swap. Order does not
matter.</p>
<table>
  <tr><td class="n">1</td><td>Open the <b>You</b> tab, then <b>This Brain</b>, then
  <b>Connect another Centurion</b>.</td></tr>
  <tr><td class="n">2</td><td>In the top half, press <b>Make this Centurion reachable</b>.</td></tr>
  <tr><td class="n">3</td><td><b>Wait, and leave the window alone for a minute or two.</b> The Brain
  restarts its own service, and that restart is allowed to take a while &mdash; the screen is
  watching for it. Pressing the button again does not speed it up.</td></tr>
  <tr><td class="n">4</td><td>When it is ready the line reads: <i>&ldquo;This Centurion is reachable.
  Give the two values above to the other person.&rdquo;</i> The <b>address</b> and <b>secret</b> are
  now shown there, each with a <b>Copy</b> button.</td></tr>
  <tr><td class="n">5</td><td>Send both values to the other person &mdash; address and secret. They
  are not a password for you to keep; they are an invitation. Use <b>Copy</b>, never retype.</td></tr>
</table>

<h2>3 &middot; Connect to theirs &mdash; on both machines</h2>
<p>Each machine has to connect to the other, so do this on <b>both</b>.</p>
<table>
  <tr><td class="n">1</td><td>On the same screen, in the lower half, type the <b>address</b> they
  sent you.</td></tr>
  <tr><td class="n">2</td><td>Type their <b>secret</b> &mdash; the long code, not the address.
  (Spaces are how it reads aloud; they are ignored.)</td></tr>
  <tr><td class="n">3</td><td>Give it a <b>name</b> if you like &mdash; otherwise the address
  becomes the name.</td></tr>
  <tr><td class="n">4</td><td>Press <b>Connect</b>.</td></tr>
</table>

<p>You will get one of two answers, and the screen does not soften them:</p>
<ul>
  <li><b>&ldquo;&hellip; is connected and answered. Both Centurions can reach each other now.&rdquo;</b>
  &mdash; done. The link was proved, not assumed.</li>
  <li><b>&ldquo;Saved, but it did not answer&hellip;&rdquo;</b> &mdash; the two values are stored but
  the other Brain did not reply. Usual causes: the other machine has not finished step 2, or has not
  restarted since. Finish step 2 on <i>their</i> machine, then press <b>Connect</b> again here.</li>
</ul>

<div class="box">
  <div class="t">One thing to know</div>
  <p style="margin:0">The address is a local one (it looks like <span class="say">192.168.x.x</span>).
  It only works when both machines are on the <b>same WiFi</b>. Same WiFi needs nothing changed on
  the router. If the two machines are ever on different networks, a port must be forwarded &mdash;
  that is the one part Centurion cannot do for you.</p>
</div>

<p class="quiet">Connected? Then read the second sheet, <b>Using the collaboration</b> &mdash; that is
what the link is actually for.</p>
"""

# ── Sheet 2 ────────────────────────────────────────────────────────────────
USE_IT = """
<div class="mast">Centurion &middot; Sovereign AI Brain 7.0.4</div>
<h1>Using the collaboration</h1>
<div class="sub">What your Centurion does once it is connected to another owner's.</div>
<div class="rule"></div>

<p>Two Centurions that are connected can <b>send each other messages</b>, and each owner reads
them. That is the collaboration. It lives on the same screen you paired on, so there is nothing new
to find.</p>

<h2>Where it is</h2>
<p><b>You</b> tab &rarr; <b>This Brain</b> &rarr; <b>Connect another Centurion</b> &mdash; the screen
you already used. Once you have
connected to someone, two more sections appear <b>underneath</b> the pair.</p>

<h2>The two sections</h2>
<table>
  <tr><td class="n">1</td><td><b>Messages from other Centurions</b> &mdash; what Eve or Mikki has
  sent you, newest first. Anything new is in <b>bold</b> and carries a <b>Got it</b> button. Press it
  when you have read and dealt with the message; it stops being new.</td></tr>
  <tr><td class="n">2</td><td><b>Send something to the other Centurion</b> &mdash; pick them by
  name, give it a subject, write the message, press <b>Send</b>. The subject is what they see first,
  so make it say the job: <i>&ldquo;Check the pricing sheet&rdquo;</i>.</td></tr>
</table>

<p class="quiet">The <b>Send</b> box only appears once you have connected to someone. If you cannot
see it, the connecting steps are not finished yet &mdash; that is the order, not a fault.</p>

<div class="box">
  <div class="t">What this is &mdash; and what it is not</div>
  <p style="margin:0 0 4px 0">Your Centurions can <b>exchange messages that you read and act
  on</b>. A message arrives in the inbox above, you read it, and you decide what happens next.</p>
  <p style="margin:0">What they do <b>not</b> yet do is act on each other's messages by themselves.
  Nothing is sent behind your back and nothing is approved without you. The hand on the wheel stays
  yours.</p>
</div>

<div class="box">
  <div class="t">Before you send anything sensitive</div>
  <p style="margin:0">Messages between two Centurions travel over your own network and are
  <b>authenticated</b> &mdash; another machine cannot post into your Brain without the secret. They
  are not yet <b>encrypted</b> in transit. So keep client names, medical details, figures and
  passwords out of the messages themselves for now, and put those in a document you hand over
  another way. Treat the link like a shared office noticeboard: fine for the work, not for the
  secrets.</p>
</div>

<h2>The one-screen habit</h2>
<p>Open <b>You &rarr; This Brain &rarr; Connect another Centurion</b> when you and the other person
start a piece
of work together, and again when you finish one. Everything either of you sends lands in one place,
and both of you can see the same list. There is no separate app and no separate account.</p>

<h2>If it does not work</h2>
<table>
  <tr><td class="n">&mdash;</td><td><b>No Send box, and no messages section.</b> Either you are not
  connected yet, or this machine is older than 7.0.4. Check the pairing first &mdash; both machines
  have to do those steps. If you are connected and the box is still missing, the machine you are
  looking at needs the update: the part that draws it was repaired in 7.0.4.</td></tr>
  <tr><td class="n">&mdash;</td><td><b>&ldquo;Could not send.&rdquo;</b> The other machine is asleep,
  closed, or off the network. Nothing is lost: it stays in the outbox and goes when the Brain is
  reachable again. Check the other person's machine is on and on the same WiFi.</td></tr>
  <tr><td class="n">&mdash;</td><td><b>&ldquo;No answer. Check both machines are on&hellip;&rdquo;</b>
  The other Brain is not replying. Confirm it is switched on, its Gateway row shows as running, and
  that both machines are on the same WiFi.</td></tr>
  <tr><td class="n">&mdash;</td><td><b>A message you sent has not appeared on their side.</b>
  Press <b>Test</b> next to their name on the pair list. That proves the link from your end and tells
  you whether the problem is the link or the other machine.</td></tr>
</table>

<p class="quiet">Centurion AI Agent Limited &middot; if a step does not do what this sheet says it
will, that is worth reporting &mdash; the failure we care about most is one that leaves you
guessing.</p>
"""


def build(name: str, body: str) -> None:
    doc = ("<!doctype html><html><head><meta charset='utf-8'><style>" + CSS
           + "</style></head><body>" + body + "</body></html>")
    out = os.path.join(OUT_DIR, name)
    os.makedirs(OUT_DIR, exist_ok=True)
    HTML(string=doc).write_pdf(out)
    print(f"wrote {out}  {os.path.getsize(out)} bytes")


if __name__ == "__main__":
    build("connect-your-centurions.pdf", CONNECT)
    build("using-the-collaboration.pdf", USE_IT)
