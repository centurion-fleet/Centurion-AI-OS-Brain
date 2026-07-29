import { useEffect, useState } from "react";

declare global {
  interface Window {
    __centurionDeckVisible?: boolean;
    webkit?: {
      messageHandlers?: {
        centurion?: { postMessage: (msg: string) => void };
      };
    };
  }
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
    return () => window.removeEventListener("centurion-deck-visibility", onVis);
  }, []);

  return visible;
}
