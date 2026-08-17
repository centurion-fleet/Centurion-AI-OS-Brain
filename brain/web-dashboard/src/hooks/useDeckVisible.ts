import { useEffect, useState } from "react";

declare global {
  interface Window {
    __centurionDeckVisible?: boolean;
    /** GTK Focus vs Collab WebView. Unset in a normal browser. */
    __centurionDeckRole?: "focus" | "collab";
    webkit?: {
      messageHandlers?: {
        centurion?: { postMessage: (msg: string) => void };
      };
    };
  }
}

export function embedDeckRole(): "focus" | "collab" | undefined {
  if (typeof window === "undefined") return undefined;
  const role = window.__centurionDeckRole;
  if (role === "focus" || role === "collab") return role;
  return undefined;
}

/**
 * Whether the Mission Deck tab is the active Brain tab.
 * Brain injects `window.__centurionDeckVisible` + `centurion-deck-visibility`
 * events; standalone browser defaults to visible.
 */
export function useDeckVisible(): boolean {
  const [visible, setVisible] = useState(() => {
    if (typeof window === "undefined") return true;
    // This WebView is only mounted while the Collab tab is showing.
    if (window.__centurionDeckRole === "collab") return true;
    if (typeof window.__centurionDeckVisible === "boolean") {
      return window.__centurionDeckVisible;
    }
    const embedded =
      typeof window.webkit?.messageHandlers?.centurion?.postMessage ===
      "function";
    return !embedded;
  });

  useEffect(() => {
    const onVis = (ev: Event) => {
      const detail = (ev as CustomEvent<{ visible?: boolean }>).detail;
      if (typeof detail?.visible === "boolean") {
        setVisible(detail.visible);
        return;
      }
      if (typeof window.__centurionDeckVisible === "boolean") {
        setVisible(window.__centurionDeckVisible);
      }
    };
    window.addEventListener("centurion-deck-visibility", onVis);
    // UserScript defaults Focus to false until GTK confirms. Collab stays
    // visible unless GTK later suspends this WebView.
    if (window.__centurionDeckRole !== "collab") {
      if (typeof window.__centurionDeckVisible === "boolean") {
        setVisible(window.__centurionDeckVisible);
      }
    } else if (window.__centurionDeckVisible === true) {
      setVisible(true);
    }
    const t = window.setTimeout(() => {
      if (window.__centurionDeckRole === "collab") {
        if (window.__centurionDeckVisible === false) {
          // Only honor an explicit GTK suspend, not the inject default.
          return;
        }
        if (typeof window.__centurionDeckVisible === "boolean") {
          setVisible(window.__centurionDeckVisible);
        }
        return;
      }
      if (typeof window.__centurionDeckVisible === "boolean") {
        setVisible(window.__centurionDeckVisible);
      }
    }, 250);
    return () => {
      window.removeEventListener("centurion-deck-visibility", onVis);
      window.clearTimeout(t);
    };
  }, []);

  return visible;
}
