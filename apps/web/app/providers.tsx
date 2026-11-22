"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

import { Toasts } from "@/components/ui";
import { bootstrapSession } from "@/lib/api";
import { applyStoredTheme, useAuth } from "@/lib/store";
import type { User } from "@/lib/types";

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 15_000,
            retry: 1,
            refetchOnWindowFocus: true,
          },
        },
      }),
  );
  const router = useRouter();
  const logout = useAuth((state) => state.logout);
  const token = useAuth((state) => state.token);
  const setUser = useAuth((state) => state.setUser);
  const setHydrated = useAuth((state) => state.setHydrated);

  useEffect(() => {
    applyStoredTheme();
  }, []);

  useEffect(() => {
    let cancelled = false;
    bootstrapSession<User>()
      .then((user) => {
        if (cancelled) return;
        if (user) setUser(user);
      })
      .finally(() => {
        if (!cancelled) setHydrated(true);
      });
    return () => {
      cancelled = true;
    };
  }, [setUser, setHydrated]);

  useEffect(() => {
    const onUnauthorized = () => {
      if (!useAuth.getState().user) return;
      logout();
      const path = window.location.pathname;
      if (!path.startsWith("/login") && !path.startsWith("/register")) {
        router.replace(`/login?next=${encodeURIComponent(path)}`);
      }
    };
    window.addEventListener("safar:unauthorized", onUnauthorized);
    return () => window.removeEventListener("safar:unauthorized", onUnauthorized);
  }, [logout, router]);

  useEffect(() => {
    if (process.env.NODE_ENV !== "production") return;
    if (!("serviceWorker" in navigator)) return;
    const register = () => {
      navigator.serviceWorker.register("/sw.js").catch(() => undefined);
    };
    window.addEventListener("load", register);
    return () => window.removeEventListener("load", register);
  }, []);

  useEffect(() => {
    if (!token) return;
    const ping = () => {
      fetch(`${process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000"}/api/health`, {
        method: "GET",
      }).catch(() => undefined);
    };
    window.addEventListener("online", ping);
    return () => window.removeEventListener("online", ping);
  }, [token]);

  return (
    <QueryClientProvider client={queryClient}>
      {children}
      <Toasts />
    </QueryClientProvider>
  );
}
