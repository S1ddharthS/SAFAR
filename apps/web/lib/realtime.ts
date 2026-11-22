"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";

import { wsUrl } from "@/lib/api";

type Status = "idle" | "connecting" | "live" | "closed";

export function useTripSocket(tripId: string | undefined) {
  const queryClient = useQueryClient();
  const [status, setStatus] = useState<Status>("idle");
  const [lastEvent, setLastEvent] = useState<{ type: string; at: number } | null>(null);
  const retry = useRef(0);

  useEffect(() => {
    if (!tripId) return;
    let socket: WebSocket | null = null;
    let heartbeat: number | undefined;
    let reconnect: number | undefined;
    let disposed = false;

    const connect = async () => {
      setStatus("connecting");
      const url = await wsUrl(tripId);
      if (!url || disposed) {
        setStatus("closed");
        return;
      }
      socket = new WebSocket(url);

      socket.onopen = () => {
        retry.current = 0;
        setStatus("live");
        heartbeat = window.setInterval(() => {
          if (socket?.readyState === WebSocket.OPEN) socket.send("ping");
        }, 30_000);
      };

      socket.onmessage = (event) => {
        try {
          const payload = JSON.parse(event.data) as { type?: string };
          const type = payload.type || "update";
          if (type === "pong" || type === "connected") return;
          setLastEvent({ type, at: Date.now() });
          queryClient.invalidateQueries({
            predicate: (query) =>
              query.queryKey[1] === tripId ||
              query.queryKey[0] === "trips" ||
              query.queryKey[0] === "notifications",
          });
        } catch {
          /* ignore malformed frames */
        }
      };

      socket.onclose = () => {
        window.clearInterval(heartbeat);
        if (disposed) return;
        setStatus("closed");
        retry.current = Math.min(retry.current + 1, 5);
        reconnect = window.setTimeout(connect, 1500 * retry.current);
      };

      socket.onerror = () => {
        socket?.close();
      };
    };

    connect();
    return () => {
      disposed = true;
      window.clearInterval(heartbeat);
      window.clearTimeout(reconnect);
      socket?.close();
      setStatus("idle");
    };
  }, [tripId, queryClient]);

  return { status, lastEvent };
}
