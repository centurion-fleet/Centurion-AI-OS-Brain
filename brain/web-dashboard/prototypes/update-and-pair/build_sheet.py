#!/usr/bin/env python3
"""Build the 2-page 'Update and pair your Brain' sheet for Steve and Kim.

Run with /usr/bin/python3 (weasyprint lives there, not in the venv).
House tokens shared with the Conjunction sheet: ink #110C09, paper #FAFAF9,
accent #433830, muted #5E534A, bronze #b08d57, border #EAE7E0.
"""
import os

from weasyprint import HTML

OUT = os.path.expanduser("~/.centurion/document_cache/update-and-pair.pdf")

CSS = """
@page {
  size: A4;
  margin: 13mm 14mm 12mm 14mm;
  @bottom-left  { content: "Centurion \\00b7 Update and pair"; font-family: "Liberation Sans", sans-serif;
                  font-size: 7.5pt; color: #968D86; }
  @bottom-right { content: "page " counter(page) " of " counter(pages);
                  font-family: "Liberation Sans", sans-serif; font-size: 7.5pt; color: #968D86; }
}
@page :first { @bottom-left { content: ""; } @bottom-right { content: ""; } }
body { background: #FAFAF9; color: #110C09;
       font-family: "Liberation Sans", "DejaVu Sans", Arial, sans-serif;
       font-size: 8.9pt; line-height: 1.27; margin: 0; }
h1 { font-family: "Liberation Serif", Georgia, serif; font-size: 21pt; line-height: 1.1;
     margin: 0 0 4px 0; }
h2 { font-family: "Liberation Serif", Georgia, serif; font-size: 12pt; margin: 10px 0 2px 0;
     padding-top: 6px; border-top: 1px solid #EAE7E0; break-after: avoid; }
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
.newpage { break-before: page; }
.keep { break-inside: avoid; }
.k { color: #b08d57; font-weight: bold; }
"""

P1 = """
<div class="mast">Centurion &middot; Sovereign AI Brain</div>
<h1>Update your Brain, then pair it</h1>
<div class="sub">One update per machine. Then two Brains on the same WiFi learn to talk.</div>
<div class="rule"></div>

<p>This is everything, in order. Nothing here needs a terminal. If a step asks for your
password, it is the Fedora installer asking, not the Brain.</p>

<p class="quiet">Two machines: Steve's Centurion is <b>Eve</b>, Kim's is <b>Mikki</b>.</p>

<div class="box">
  <div class="t">Before you start &mdash; one thing to glance at</div>
  <p style="margin:0">On each machine, open <b>Settings &rarr; This Brain</b> and look at the
  <b>Gateway</b> row. It must show as running. Making a Brain reachable works by restarting that
  service, so if it is not there to restart, nothing binds, and the button waits forever. If it is
  not running, press <b>Start</b> next to it.</p>
</div>

<h2>1 &middot; Update the Brain</h2>

<table>
  <tr><td class="n">1</td><td>Open <b>Sovereign AI Brain</b>. If it offers an update, take it.
  If not, carry on &mdash; the download below is the same thing.</td></tr>
  <tr><td class="n">2</td><td>Go to <b>personalcenturion.com</b> &rarr; sign in &rarr;
  <b>Account &rarr; Get Brain</b>, and download the installer.</td></tr>
  <tr><td class="n">3</td><td>In your <b>Downloads</b> folder, double-click the file ending
  <span class="say">.rpm</span>. If asked, choose <b>Open with Software Install</b>.</td></tr>
  <tr><td class="n">4</td><td>Press <b>Install</b>, enter your password if asked, and wait for
  it to finish.</td></tr>
  <tr><td class="n">5</td><td>Open <b>Sovereign AI Brain</b> from Activities. That is the update
  done. Do this once on each machine.</td></tr>
</table>

<div class="box">
  <div class="t">If Software warns you</div>
  <p style="margin:0">It may say <i>Potentially Unsafe &mdash; provided by a third party</i>.
  That is Software's standard note for any program that did not come from Fedora's own store.
  It is expected, it is not a virus warning, and the installer itself is signed by Centurion AI
  Agent Limited.</p>
</div>

<h2>2 &middot; Make each Brain reachable</h2>

<p>Do this on <b>both</b> machines. Each one produces two values &mdash; an address and a secret
&mdash; which you swap. Order does not matter.</p>

<table>
  <tr><td class="n">1</td><td>Open <b>Settings &rarr; Connect another Centurion</b>.</td></tr>
  <tr><td class="n">2</td><td>In the top half, press <b>Make this Centurion reachable</b>.</td></tr>
  <tr><td class="n">3</td><td>Wait. When it is ready the line reads:
  <i>&ldquo;This Centurion is reachable. Give the two values above to the other person.&rdquo;</i></td></tr>
  <tr><td class="n">4</td><td>Send both values to the other person &mdash; the address and the
  secret. They are not a password for you to keep; they are an invitation.</td></tr>
</table>

<p class="quiet">Same WiFi is the easy case: nothing needs changing on the router. If the two
machines are ever on different networks, a port must be forwarded &mdash; that is the one part
Centurion cannot do for you.</p>

<h2>3 &middot; Connect to theirs &mdash; on both machines</h2>

<p>Each machine has to connect to the other, so do this on <b>both</b>. One side alone is a
half-link, and it behaves exactly like a broken one.</p>

<table>
  <tr><td class="n">1</td><td>On the same screen, in the lower half, type the
  <b>address</b> they sent you.</td></tr>
  <tr><td class="n">2</td><td>Type their <b>secret</b>. (Spaces are how it reads aloud;
  they are ignored.)</td></tr>
  <tr><td class="n">3</td><td>Give it a <b>name</b> if you like &mdash; otherwise the address
  becomes the name.</td></tr>
  <tr><td class="n">4</td><td>Press <b>Connect</b>.</td></tr>
</table>

<p>You will get one of two answers, and the screen does not soften them:</p>

<ul>
  <li><b>&ldquo;&hellip; is connected and answered. Both Centurions can reach each other now.&rdquo;</b>
  &mdash; done. The link was proved, not assumed.</li>
  <li><b>&ldquo;Saved, but it did not answer&hellip;&rdquo;</b> &mdash; the two values are stored but
  the other Brain did not reply. Usual causes: the other machine has not finished step 2, or it has
  not restarted since. Finish step 2 on <i>their</i> machine, then press Connect again here.</li>
</ul>

<div class="keep">
<h2>4 &middot; Talk to each other</h2>

<p>Once a Centurion is connected, that same screen &mdash; <b>Settings &rarr; Connect another
Centurion</b> &mdash; grows two more sections underneath the pair. This is the collaboration.</p>

<table>
  <tr><td class="n">1</td><td><b>Messages from other Centurions</b> &mdash; what Eve or Mikki has
  sent you. Anything new is in bold and carries a <b>Got it</b> button.</td></tr>
  <tr><td class="n">2</td><td><b>Send something to the other Centurion</b> &mdash; pick them by
  name, give it a subject, write the message, press <b>Send</b>.</td></tr>
</table>

<p class="quiet">The <b>Send</b> box only appears once you have connected to someone. If you
cannot see it, step 3 is not finished &mdash; that is the order, not a fault.</p>

<div class="box">
  <div class="t">What this is &mdash; and what it is not</div>
  <p style="margin:0">Your Centurions can <b>exchange messages that you read and act on</b>. A
  message arrives in the inbox above, you read it, and you decide what happens next. What they do
  not yet do is act on each other's messages by themselves &mdash; the hand on the wheel stays
  yours. Say it that way if anyone asks, because the screen will not oversell it and neither
  should we.</p>
</div>
</div>
"""

P2 = """
<h2>What you now have</h2>

<p>Two things, and they are one idea seen twice. <b>Conjunction</b> is for work that involves
another person &mdash; a project, with their Centurion and yours. <b>Stillpoint</b> is the same
instrument for your own life, where you and your Centurion work alone.</p>

<p>Conjunction answers <i>&ldquo;what needs me across my projects&rdquo;</i>. Stillpoint answers
<i>&ldquo;am I working on the right thing at all&rdquo;</i>.</p>

<h2>The registers &mdash; the same words on both screens</h2>

<table>
  <tr><td class="n">01</td><td><b>STRUCK</b> &mdash; delivered and verified. A bead seals on the
  work, never on a claim.</td></tr>
  <tr><td class="n">02</td><td><b>IN HAND</b> &mdash; moving now, and whose hands it is in.
  Yours are named here with your Centurion against them.</td></tr>
  <tr><td class="n">03</td><td><b>NEXT</b> &mdash; the agreed order, numbered.</td></tr>
  <tr><td class="n">04</td><td><b>ALIGNED</b> &mdash; <i>Stillpoint only.</i> What is moving that
  traces to your stated purpose, and what your purpose asks for that nothing is moving on.</td></tr>
  <tr><td class="n">05</td><td><b>WAITING ON YOU</b> &mdash; the only section allowed to shout.
  This is your decision queue, and the aim is for it to be short.</td></tr>
</table>

<div class="newpage"></div>
<h2>Three words you will use every day</h2>

<table>
  <tr><td class="n">&rarr;</td><td><b>Proceed</b> &mdash; hands the work over and the item moves
  into <i>In hand</i>. Approving is not delivering; it does not appear in <i>Struck</i> until the
  work is actually done.</td></tr>
  <tr><td class="n">&#9679;</td><td><b>Discuss</b> &mdash; opens a thread on that item. The item
  <b>stays exactly where it is</b> and your Centurion answers in the same thread.</td></tr>
  <tr><td class="n">&#8214;</td><td><b>Hold</b> &mdash; keeps it visible, marked held.</td></tr>
</table>

<div class="box">
  <div class="t">The one habit worth building</div>
  <p style="margin:0">Read <b>Waiting on you</b> first, every time. Nothing else on either screen
  is allowed to interrupt you. If that section is empty, everything open has been answered
  &mdash; and that is the goal, not a quiet day. The measure of the instrument is how few
  decisions needed you, not how many you made.</p>
</div>

<h2>Where to put things</h2>

<table>
  <tr><td class="n">&#9679;</td><td><b>Everything about your life and purpose</b> &mdash;
  Stillpoint. Discovery writes the centre; dreams below the fold feed it.</td></tr>
  <tr><td class="n">&#9679;</td><td><b>Anything shared with another person's Centurion</b> &mdash;
  Conjunction. One project at a time; the project name sits in the masthead.</td></tr>
  <tr><td class="n">&#9679;</td><td><b>Settings, licences, accounts</b> &mdash; <b>You</b>, in the
  Brain. Never on the phone: the phone is for capturing thoughts and orders, not for configuring
  things.</td></tr>
</table>

<h2>If something does not work</h2>

<table>
  <tr><td class="n">&mdash;</td><td><b>&ldquo;Still not reachable&hellip;&rdquo;</b> after waiting on
  the reachable button. The listener binds when the Brain's gateway restarts, so the restart has to
  actually happen. Go to <b>Settings &rarr; This Brain</b>, press <b>Restart</b> next to
  <b>Gateway</b>, then reopen <b>Connect another Centurion</b>.</td></tr>
  <tr><td class="n">&mdash;</td><td><b>&ldquo;Reached the machine, but it refused our token&rdquo;</b>
  &mdash; you are talking to the other Brain, but the secrets differ. Send the two values again and
  re-enter <b>their</b> secret exactly; the long code, not the address.</td></tr>
  <tr><td class="n">&mdash;</td><td><b>&ldquo;Reached the machine, but it has no fleet endpoint&rdquo;</b>
  &mdash; that Brain is on an older version. Both machines must be updated before they can pair.</td></tr>
  <tr><td class="n">&mdash;</td><td><b>&ldquo;Could not reach it&rdquo;</b> &mdash; the two machines
  are not seeing each other. Confirm both are on the same WiFi and that the other person has finished
  step 2 and restarted.</td></tr>
  <tr><td class="n">&mdash;</td><td><b>Nothing appears in Waiting on you</b> &mdash; that is the
  good state, not a fault. It means nothing is currently waiting for a decision from you.</td></tr>
</table>

<p class="quiet">Centurion AI Agent Limited &middot; if a step does not do what this sheet says it
will, that is worth reporting &mdash; the failure we care about most is one that leaves you
guessing.</p>
"""


def build() -> None:
    doc = ("<!doctype html><html><head><meta charset='utf-8'><style>" + CSS
           + "</style></head><body>" + P1 + P2 + "</body></html>")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    HTML(string=doc).write_pdf(OUT)
    print("wrote", OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    build()
