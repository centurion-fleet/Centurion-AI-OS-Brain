import { Link } from "react-router-dom";
import { embedDeckRole } from "../hooks/useDeckVisible";

/**
 * Back control for the Collaborate screen.
 *
 * ── WHY THIS EXISTS ────────────────────────────────────────────────────────────
 * The Conjunction tab in the Brain is a WebView onto a **static page**
 * (`conjunction.html`), and that page links on to the React screen at `/collab`
 * ("Boards & pairing →", and "Pair a second Centurion →"). Clicking either moved
 * the WebView off `conjunction.html` — and there was no way back:
 *
 *   • the tab still reads **Conjunction**, so the screen no longer matches its label;
 *   • `App.tsx` renders `<Collab />` and NOTHING ELSE when `embedDeckRole()` is
 *     `"collab"` — no `<BrowserRouter>`, so there is no route to navigate to;
 *   • the Collab screen had no back control of its own.
 *
 * The owner was simply stuck in Collaborate with no exit. Reported 28 Sep 2026:
 * *"I fell into the Collaborate menu and could not get out."*
 *
 * ── WHY IT IS TWO BRANCHES ─────────────────────────────────────────────────────
 * Embedded (`role === "collab"`) there is **no router**, so a react-router `<Link>`
 * would throw. The tab's home is the static page, so a plain anchor is both correct
 * and the only thing that works. Standalone (someone at `/collab` in a browser) the
 * router IS mounted, so it returns them to the deck's landing screen.
 *
 * Same visual language as `FocusBackBar` deliberately — one back affordance in the
 * app, not two that look like different systems.
 */
export function ConjunctionBackBar() {
  const embedded = embedDeckRole() === "collab";

  return (
    <div className="sticky top-0 z-20 -mx-4 mb-6 border-b border-border bg-canvas/95 px-4 py-3 backdrop-blur-md sm:-mx-6 sm:px-6">
      {embedded ? (
        <a
          href="/conjunction.html"
          className="inline-flex min-h-11 items-center gap-2 rounded-full bg-accent px-4 py-2 text-sm font-semibold text-[var(--on-accent)] transition hover:brightness-110"
        >
          <span aria-hidden>←</span>
          Back to Conjunction
        </a>
      ) : (
        <Link
          to="/"
          className="inline-flex min-h-11 items-center gap-2 rounded-full bg-accent px-4 py-2 text-sm font-semibold text-[var(--on-accent)] transition hover:brightness-110"
        >
          <span aria-hidden>←</span>
          Back to Stillpoint
        </Link>
      )}
    </div>
  );
}
