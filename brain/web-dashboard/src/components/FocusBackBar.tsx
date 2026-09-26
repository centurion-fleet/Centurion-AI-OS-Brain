import { Link } from "react-router-dom";

/** Sticky 44pt back control so Focus detail never looks like the landing page. */
export function FocusBackBar({
  eyebrow,
  title,
}: {
  eyebrow?: string;
  title?: string;
}) {
  return (
    <div className="sticky top-0 z-20 -mx-4 mb-6 border-b border-border bg-canvas/95 px-4 py-3 backdrop-blur-md sm:-mx-6 sm:px-6">
      <Link
        to="/"
        className="inline-flex min-h-11 items-center gap-2 rounded-full bg-accent px-4 py-2 text-sm font-semibold text-[var(--on-accent)] transition hover:brightness-110"
      >
        <span aria-hidden>←</span>
        Back to Stillpoint
      </Link>
      {(eyebrow || title) && (
        <p className="mt-3 text-[11px] font-semibold uppercase tracking-[0.16em] text-amber-soft">
          {eyebrow}
          {eyebrow && title ? " · " : ""}
          {title}
        </p>
      )}
    </div>
  );
}
