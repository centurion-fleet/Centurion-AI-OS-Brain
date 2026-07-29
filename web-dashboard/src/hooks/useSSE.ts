import { useEffect, useRef, useState } from "react";
import type { Thought } from "../types/life";

export interface UseSSEOptions {
  /** Max thoughts kept in memory */
  limit?: number;
  enabled?: boolean;
}

/**
 * Live thought stream via EventSource → /api/stream (local poll SSE).
 */
export function useSSE(options: UseSSEOptions = {}) {
  const { limit = 80, enabled = true } = options;
  const [thoughts, setThoughts] = useState<Thought[]>([]);
  const [connected, setConnected] = useState(false);
  const [streamError, setStreamError] = useState<string | null>(null);
  const seen = useRef(new Set<string>());

  useEffect(() => {
    if (!enabled) return;

    const es = new EventSource("/api/stream");
    setConnected(false);

    es.onopen = () => {
      setConnected(true);
      setStreamError(null);
    };

    es.addEventListener("thought", (ev) => {
      try {
        const t = JSON.parse((ev as MessageEvent).data) as Thought;
        const id = t.id || `${t.created_at}:${t.summary}`;
        if (seen.current.has(id)) return;
        seen.current.add(id);
        setThoughts((prev) => {
          const next = [t, ...prev];
          return next.slice(0, limit);
        });
      } catch {
        /* ignore malformed */
      }
    });

    es.addEventListener("error", (ev) => {
      try {
        const data = JSON.parse((ev as MessageEvent).data) as {
          message?: string;
        };
        if (data.message) setStreamError(data.message);
      } catch {
        /* browser native error event has no data */
      }
    });

    es.onerror = () => {
      setConnected(false);
    };

    return () => {
      es.close();
      setConnected(false);
    };
  }, [enabled, limit]);

  const clear = () => {
    seen.current.clear();
    setThoughts([]);
  };

  return { thoughts, connected, streamError, clear };
}
