import { useEffect, useRef } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { useDeckVisible } from "../hooks/useDeckVisible";
import { fetchOpenDecisions } from "../hooks/useOpenDecisions";

/**
 * When the Brain Focus tab becomes visible and there are open decisions
 * (the tab badge), jump straight to the mission + decision that needs you —
 * so the alert is never a mystery after a click into Focus.
 */
export function AttentionFollow() {
  const deckVisible = useDeckVisible();
  const navigate = useNavigate();
  const location = useLocation();
  const followedForVisit = useRef(false);

  useEffect(() => {
    if (!deckVisible) {
      followedForVisit.current = false;
      return;
    }
    if (followedForVisit.current) return;

    let cancelled = false;
    void (async () => {
      let open;
      try {
        open = await fetchOpenDecisions();
      } catch {
        return;
      }
      if (cancelled || open.length === 0) return;
      followedForVisit.current = true;

      const first = open.find((d) => d.mission_id) ?? open[0];
      const mid = first.mission_id;
      if (!mid) return;

      const targetPath = `/mission/${mid}`;
      const qs = `attention=${encodeURIComponent(first.id)}`;
      const alreadyHere =
        location.pathname === targetPath &&
        new URLSearchParams(location.search).get("attention") === first.id;
      if (alreadyHere) return;

      navigate(`${targetPath}?${qs}`, {
        replace: location.pathname === targetPath,
        state: {
          attentionTitle: first.title,
          attentionContext: first.context || "",
        },
      });
    })();

    return () => {
      cancelled = true;
    };
  }, [deckVisible, navigate, location.pathname, location.search]);

  return null;
}
