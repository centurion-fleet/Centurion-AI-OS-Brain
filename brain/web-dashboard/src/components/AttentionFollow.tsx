import { useEffect, useRef } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { embedDeckRole, useDeckVisible } from "../hooks/useDeckVisible";

function scrollFocusHome() {
  window.scrollTo(0, 0);
  document.documentElement.scrollTop = 0;
  document.body.scrollTop = 0;
}

/**
 * Clicking the Brain Focus tab always opens the Focus homepage (decisions
 * list at the top) — never a supporting-mission detail or a mid-page scroll.
 *
 * In-tab navigation (open a mission, Discovery) is left alone until the user
 * leaves Focus and comes back.
 *
 * Never run on Collab — that tab is a Kanban, not the mission deck.
 */
export function AttentionFollow() {
  const deckVisible = useDeckVisible();
  const navigate = useNavigate();
  const location = useLocation();
  const tabOpen = useRef(false);
  const pendingHomeScroll = useRef(false);

  useEffect(() => {
    if (embedDeckRole() === "collab") return;
    if (location.pathname === "/collab" || location.pathname.startsWith("/collab/")) {
      return;
    }
    if (!deckVisible) {
      tabOpen.current = false;
      pendingHomeScroll.current = false;
      return;
    }
    if (!tabOpen.current) {
      tabOpen.current = true;
      pendingHomeScroll.current = true;
      if (location.pathname !== "/") {
        navigate("/", { replace: true });
        return;
      }
    }
    if (pendingHomeScroll.current && location.pathname === "/") {
      pendingHomeScroll.current = false;
      scrollFocusHome();
      requestAnimationFrame(scrollFocusHome);
    }
  }, [deckVisible, navigate, location.pathname]);

  return null;
}
