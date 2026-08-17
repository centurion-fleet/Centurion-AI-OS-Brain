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
    if (typeof window.__centurionDeckVisible === "boolean") {
      return window.__centurionDeckVisible;
    }
    const embedded =
      typeof window.webkit?.messageHandlers?.centurion?.postMessage ===
      "function";
    return !embedded;
  });

  useEffect(() => {
    // Sync after mount — LoadFinished may have set the flag before React listened.
    if (typeof window.__centurionDeckVisible === "boolean") {
      setVisible(window.__centurionDeckVisible);
    }
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
    // Late inject from GTK after first paint.
    const t = window.setTimeout(() => {
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
