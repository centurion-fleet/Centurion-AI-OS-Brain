import { useCallback, useRef, useState } from "react";
import type { BridgeResponse } from "../types/life";

export class BridgeError extends Error {
  code?: string;
  constructor(message: string, code?: string) {
    super(message);
    this.name = "BridgeError";
    this.code = code;
  }
}

/** POST /api/bridge → remote_bridge stdio action */
export async function bridgeCall<T extends BridgeResponse = BridgeResponse>(
  action: string,
  params: Record<string, unknown> = {},
): Promise<T> {
  const res = await fetch("/api/bridge", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action, ...params }),
  });
  const data = (await res.json()) as BridgeResponse;
  if (!res.ok || data.ok === false) {
    const err = data as { error?: string; message?: string; code?: string };
    throw new BridgeError(
      err.error || err.message || `Bridge failed (${res.status})`,
      err.code,
    );
  }
  return data as T;
}

export function useBridge() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inflight = useRef(0);

  const call = useCallback(
    async <T extends BridgeResponse = BridgeResponse>(
      action: string,
      params: Record<string, unknown> = {},
    ): Promise<T> => {
      inflight.current += 1;
      setLoading(true);
      setError(null);
      try {
        return await bridgeCall<T>(action, params);
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        setError(msg);
        throw e;
      } finally {
        inflight.current -= 1;
        if (inflight.current <= 0) {
          inflight.current = 0;
          setLoading(false);
        }
      }
    },
    [],
  );

  return { call, loading, error, setError };
}
