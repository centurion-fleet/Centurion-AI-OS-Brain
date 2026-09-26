#!/usr/bin/env python3
"""Build the two-page illustrated 'Conjunction — how to use it' PDF.

Run with /usr/bin/python3 (weasyprint lives there, not in the venv).
House tokens: ink #110C09 · paper #FAFAF9 · accent #433830 · muted #5E534A
              bronze #b08d57 · border #EAE7E0
"""
import os

from weasyprint import HTML

OUT = os.path.expanduser("~/.centurion/document_cache/conjunction-how-to-use.pdf")

CSS = """
@page {
  size: A4;
  margin: 16mm 16mm 15mm 16mm;
  @bottom-left  { content: "Centurion · Conjunction"; font-family: "Liberation Sans", sans-serif;
                  font-size: 7.5pt; color: #968D86; }
  @bottom-right { content: "page " counter(page) " of " counter(pages);
                  font-family: "Liberation Sans", sans-serif; font-size: 7.5pt; color: #968D86; }
}
@page :first { @bottom-left { content: ""; } @bottom-right { content: ""; } }
body { background: #FAFAF9; color: #110C09;
       font-family: "Liberation Sans", "DejaVu Sans", Arial, sans-serif;
       font-size: 9.6pt; line-height: 1.4; margin: 0; }
h1 { font-family: "Liberation Serif", Georgia, serif; font-size: 24pt; line-height: 1.1;
     margin: 0 0 5px 0; }
h2 { font-family: "Liberation Serif", Georgia, serif; font-size: 13pt; margin: 13px 0 2px 0;
     padding-top: 7px; border-top: 1px solid #EAE7E0; break-after: avoid; }
.mast { font-size: 7.8pt; letter-spacing: 2.2px; text-transform: uppercase; color: #b08d57;
        margin: 0 0 9px 0; }
.sub { color: #5E534A; font-size: 10.5pt; margin: 0; }
.rule { height: 2px; background: #433830; width: 44px; margin: 10px 0 12px 0; }
p { margin: 5px 0; }
table { width: 100%; border-collapse: collapse; margin: 8px 0 4px 0; break-inside: avoid; }
td { border-bottom: 1px solid #EAE7E0; padding: 4px 8px 4px 0; vertical-align: top; }
td.n { width: 24px; color: #b08d57; font-family: "Liberation Serif", Georgia, serif;
       font-weight: bold; }
figure { margin: 8px 0 10px 0; break-inside: avoid; }
figcaption { font-size: 8.4pt; color: #5E534A; margin-top: 5px; }
.box { border: 1px solid #EAE7E0; border-left: 3px solid #b08d57; background: #FFFFFF;
       padding: 8px 10px; margin: 8px 0; break-inside: avoid; }
.box .t { font-size: 7.8pt; letter-spacing: 1.6px; text-transform: uppercase; color: #b08d57;
          margin-bottom: 4px; }
.quiet { color: #5E534A; font-size: 9pt; }
.newpage { break-before: page; }
"""

# ---------------------------------------------------------------- figure 1
FIG1 = """
<figure>
<svg viewBox="0 0 520 196" width="100%" xmlns="http://www.w3.org/2000/svg">
  <rect x="0" y="0" width="520" height="196" fill="#FFFFFF" stroke="#EAE7E0"/>
  <text x="18" y="22" font-family="Liberation Sans" font-size="9" letter-spacing="1.6"
        fill="#b08d57">THE INSTRUMENT</text>
  <ellipse cx="260" cy="120" rx="176" ry="66" fill="none" stroke="#b08d57" stroke-width="1.2"
           stroke-dasharray="5 6" opacity="0.75"/>
  <ellipse cx="260" cy="120" rx="132" ry="49" fill="none" stroke="#8A9099" stroke-width="1.6"/>
  <circle cx="260" cy="120" r="34" fill="none" stroke="#433830" stroke-width="1"/>
  <circle cx="260" cy="120" r="5" fill="#433830"/>
  <text x="260" y="104" text-anchor="middle" font-family="Liberation Sans" font-size="7.5"
        letter-spacing="1.4" fill="#5E534A">THE STILL</text>
  <text x="260" y="145" text-anchor="middle" font-family="Liberation Sans" font-size="7.5"
        letter-spacing="1.4" fill="#5E534A">CENTRE — YOU</text>
  <circle cx="392" cy="120" r="5.5" fill="#C2C8D2"/>
  <circle cx="260" cy="54" r="5" fill="none" stroke="#b08d57" stroke-width="1.6"/>
  <circle cx="128" cy="120" r="5" fill="none" stroke="#b08d57" stroke-width="1.6"/>
  <text x="404" y="124" font-family="Liberation Sans" font-size="8" fill="#5E534A">STEEL · the other Centurion</text>
  <text x="404" y="140" font-family="Liberation Sans" font-size="8" fill="#5E534A">(empty until paired)</text>
  <text x="18" y="176" font-family="Liberation Sans" font-size="8.2" fill="#8A9099">BRONZE</text>
  <text x="70" y="176" font-family="Liberation Sans" font-size="8.2" fill="#8A9099">your Centurion's ring</text>
  <text x="200" y="176" font-family="Liberation Sans" font-size="8.2" fill="#8A9099">·</text>
  <text x="212" y="176" font-family="Liberation Sans" font-size="8.2" fill="#8A9099">STRUCK seals on delivery</text>
  <text x="352" y="176" font-family="Liberation Sans" font-size="8.2" fill="#8A9099">·</text>
  <text x="364" y="176" font-family="Liberation Sans" font-size="8.2" fill="#8A9099">WAITING shouts</text>
</svg>
<figcaption>One intention, two rings, one human in the middle. Steel stays empty until you pair a second Centurion.</figcaption>
</figure>
"""

# ---------------------------------------------------------------- figure 2
def project_row(y: int, name: str, humans: str, centurions: str, selected: bool) -> str:
    """One project row. Built with f-strings only — %-formatting breaks on the SVG's 100%."""
    bar = "#b08d57" if selected else "#EAE7E0"
    bg = "#FFFDF8" if selected else "#FFFFFF"
    dot = "" if not selected else f'<circle cx="497" cy="{y + 16}" r="4" fill="#b08d57"/>'
    return (
        f'<rect x="0" y="{y}" width="520" height="38" fill="{bg}" stroke="#EAE7E0"/>'
        f'<rect x="0" y="{y}" width="3.5" height="38" fill="{bar}"/>'
        f'<text x="14" y="{y + 16}" font-family="Liberation Sans" font-size="9.4" '
        f'fill="#110C09">{name}</text>'
        f'<text x="14" y="{y + 29}" font-family="Liberation Sans" font-size="8" '
        f'fill="#5E534A">{humans}</text>'
        f'<text x="266" y="{y + 22}" font-family="Liberation Sans" font-size="8" '
        f'fill="#5E534A">{centurions}</text>'
        f'{dot}'
    )


FIG2 = """
<figure>
<svg viewBox="0 0 520 158" width="100%" xmlns="http://www.w3.org/2000/svg">
  <text x="0" y="14" font-family="Liberation Sans" font-size="8.4" letter-spacing="1.6"
        fill="#b08d57">PROJECT</text>
  <text x="266" y="14" font-family="Liberation Sans" font-size="8.4" letter-spacing="1.6"
        fill="#b08d57">CENTURIONS</text>
  __ROWS__
  <text x="0" y="150" font-family="Liberation Sans" font-size="8" fill="#5E534A">The bronze dot means something is waiting on you in that project — you see it without switching.</text>
</svg>
<figcaption>Example. Three projects, one person, three sets of hands. The selected one fills the screen.</figcaption>
</figure>
""".replace("__ROWS__",
    project_row(22, "Website project", "You \u00b7 Anna", "Yours \u00b7 Aria", False)
    + project_row(60, "Rollout project", "You \u00b7 Ben", "Yours \u00b7 Bram", True)
    + project_row(98, "Research project", "You \u00b7 Chloe", "Yours \u00b7 Circe", False))

# ---------------------------------------------------------------- figure 3
def verb(y: int, label: str, colour: str, flow: list) -> str:
    parts = ['<text x="0" y="%d" font-family="Liberation Sans" font-size="8.6" '
             'letter-spacing="1.2" fill="%s">%s</text>' % (y + 11, colour, label)]
    x = 74
    for i, (txt, style) in enumerate(flow):
        if i:
            parts.append('<path d="M %d %d l 9 0 m -4 -4 l 4 4 l -4 4" fill="none" '
                         'stroke="#8A9099" stroke-width="1.2"/>' % (x - 16, y + 7))
        fill = {"solid": "#FBF3E6", "plain": "#FFFFFF", "ink": "#F0EDE8"}.get(style, "#FFFFFF")
        stroke = "#b08d57" if style == "solid" else "#D8D3CA"
        parts.append('<rect x="%d" y="%d" width="%d" height="22" rx="3" fill="%s" '
                     'stroke="%s"/>' % (x, y - 4, max(74, len(txt) * 5 + 12), fill, stroke))
        parts.append('<text x="%d" y="%d" font-family="Liberation Sans" font-size="8" '
                     'fill="#110C09">%s</text>' % (x + 7, y + 11, txt))
        x += max(74, len(txt) * 5 + 12) + 16
    return "".join(parts)


FIG3 = """
<figure>
<svg viewBox="0 0 520 128" width="100%" xmlns="http://www.w3.org/2000/svg">
  <rect x="0" y="0" width="520" height="128" fill="#FFFFFF" stroke="#EAE7E0"/>
  __V1__
  __V2__
  __V3__
  <text x="0" y="122" font-family="Liberation Sans" font-size="8" fill="#5E534A">Nothing leaves Waiting on you until you decide. Silence is the only real failure.</text>
</svg>
<figcaption>What each verb actually does. Only Proceed moves the item — and even then it moves into
<em>In hand</em>, not into <em>Struck</em>.</figcaption>
</figure>
""".replace("__V1__", verb(14, "PROCEED", "#b08d57", [("starts the work", "solid"),
        ("in hand", "plain"), ("delivered", "plain"), ("bead seals", "ink")])
).replace("__V2__", verb(50, "DISCUSS", "#5E534A", [("thread on the item", "plain"),
        ("item stays put", "ink"), ("your Centurion replies", "plain")])
).replace("__V3__", verb(86, "HOLD", "#5E534A", [("stays visible", "plain"),
        ("marked held", "ink")]))

# ---------------------------------------------------------------- page 1
P1 = """
<div class="mast">Centurion &middot; Conjunction</div>
<h1>How to use Conjunction</h1>
<div class="sub">Watching two Centurions work one intention &mdash; without having to keep up.</div>
<div class="rule"></div>

<p>Humans are slow but hold the vision and the decision making skills. Centurions are fast and hold the hands. Conjunction keeps you
in the only seat that matters &mdash; <b>the decisions</b> &mdash; while the work moves at a pace no
person can follow line by line. It shows four things, and nothing else.</p>

<table>
  <tr><td class="n">01</td><td><b>STRUCK</b> &mdash; work delivered and verified. A bead seals only when
  the work is actually done, never on a claim.</td></tr>
  <tr><td class="n">02</td><td><b>IN HAND</b> &mdash; what is moving now, and whose hands. Items you
  approved are named here, with the Centurion carrying them.</td></tr>
  <tr><td class="n">03</td><td><b>NEXT</b> &mdash; the agreed order, numbered.</td></tr>
  <tr><td class="n">04</td><td><b>WAITING ON YOU</b> &mdash; the only section allowed to shout. Each item
  asks you to <b>Proceed</b>, <b>Discuss</b>, or <b>Hold</b>.</td></tr>
</table>

""" + FIG1 + """

<h2>One project at a time</h2>

<p>A Conjunction is not one board for one pair. A Conjunction is a <b>project</b>: a named intention
with a defined membership &mdash; the humans in it, and the Centurion each of them brings. You will be
a member of several at once, and one switch moves you between them.</p>

""" + FIG2 + """

<p>Each project is its own Conjunction with its own register, its own queue, its own rings. You see the
projects you are a member of, and inside each you see only what that project shares &mdash;
<b>membership is the boundary</b>.</p>
"""

# ---------------------------------------------------------------- page 2
P2 = """
<div class="newpage"></div>
<h2>Using it, step by step</h2>

<table>
  <tr><td class="n">1</td><td><b>Pick your project.</b> The project name sits in the masthead &mdash; tap
  it to switch. A dot beside a name means something is waiting on you <i>there</i>.</td></tr>
  <tr><td class="n">2</td><td><b>Read Waiting on you first.</b> Nothing else on the page is allowed to
  shout. If that section is empty, every open question has been answered.</td></tr>
  <tr><td class="n">3</td><td><b>Answer it.</b> <b>Proceed</b> hands the work over and the item moves into
  In hand, with the Centurion named against it. <b>Discuss</b> opens a thread on that item and the item
  <b>stays where it is</b> &mdash; your Centurion answers in the same thread. <b>Hold</b> keeps it visible,
  marked held.</td></tr>
  <tr><td class="n">4</td><td><b>Or just talk to your Centurion.</b> Page, Telegram and the app all write
  into the <b>same</b> thread on the same item &mdash; one discussion, three doors. You never have to
  remember which one you used.</td></tr>
  <tr><td class="n">5</td><td><b>Watch In hand.</b> That is where your approvals sit while they are worked:
  <i>waiting to be picked up</i>, then <i>with your Centurion</i>. If something sits with no movement, that
  is the signal to ask about it.</td></tr>
  <tr><td class="n">6</td><td><b>Struck is the only number that never moves on a decision.</b> Approving is
  not delivering. A bead seals when the work is done and verified.</td></tr>
</table>

""" + FIG3 + """

<h2>The rule that keeps it safe</h2>

<p>With more than one project, the one dangerous mistake is answering in the wrong one. So the project
name is always on screen, each project carries its own accent, and every decision records which project
it belonged to. You should never have to wonder whose work you just approved.</p>

<div class="box">
  <div class="t">The short version</div>
  <p style="margin:0">Conjunction shows you your <b>next move</b>, and the pace of everything else. It is
  not a view of the work &mdash; it is the view of what needs <i>you</i>. The only real failure is silence:
  something waiting that you cannot see.</p>
</div>

<p class="quiet">Centurion AI Agent Limited &middot; this sheet describes Conjunction as designed for the
Brain and the iPhone Remote.</p>
"""


def build() -> None:
    doc = ("<!doctype html><html><head><meta charset='utf-8'><style>" + CSS
           + "</style></head><body>" + P1 + P2 + "</body></html>")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    HTML(string=doc).write_pdf(OUT)
    print("wrote", OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    build()
