"use client";

import { create } from "zustand";
import { persist } from "zustand/middleware";

import { clearSessionTokens, setSessionTokens } from "./api";
import type { User } from "./types";

interface AuthState {
  token: string | null;
  user: User | null;
  hydrated: boolean;
  setSession: (token: string, user: User, csrf?: string | null) => void;
  setUser: (user: User) => void;
  logout: () => void;
  setHydrated: (value: boolean) => void;
}

// Session state is memory-only; the refresh token stays in an HttpOnly cookie.
export const useAuth = create<AuthState>()((set) => ({
  token: null,
  user: null,
  hydrated: false,
  setSession: (token, user, csrf = null) => {
    setSessionTokens(token, csrf);
    set({ token, user });
  },
  setUser: (user) => set({ user }),
  logout: () => {
    clearSessionTokens();
    set({ token: null, user: null });
  },
  setHydrated: (value) => set({ hydrated: value }),
}));

type Theme = "light" | "dark";

interface ThemeState {
  theme: Theme;
  setTheme: (theme: Theme) => void;
  toggle: () => void;
}

function applyTheme(theme: Theme) {
  if (typeof document === "undefined") return;
  document.documentElement.classList.toggle("dark", theme === "dark");
}

export const useTheme = create<ThemeState>()(
  persist(
    (set, get) => ({
      theme: "light",
      setTheme: (theme) => {
        applyTheme(theme);
        set({ theme });
      },
      toggle: () => {
        const next = get().theme === "light" ? "dark" : "light";
        applyTheme(next);
        set({ theme: next });
      },
    }),
    {
      name: "safar-theme",
      onRehydrateStorage: () => (state) => {
        if (state) applyTheme(state.theme);
      },
    },
  ),
);

export function applyStoredTheme() {
  if (typeof window === "undefined") return;
  try {
    const raw = window.localStorage.getItem("safar-theme");
    if (!raw) return;
    const parsed = JSON.parse(raw) as { state?: { theme?: Theme } };
    const theme = parsed.state?.theme;
    if (theme) document.documentElement.classList.toggle("dark", theme === "dark");
  } catch {
    /* ignore */
  }
}

interface Toast {
  id: number;
  title: string;
  description?: string;
  tone: "success" | "error" | "info";
}

interface ToastState {
  toasts: Toast[];
  push: (title: string, description?: string, tone?: Toast["tone"]) => void;
  dismiss: (id: number) => void;
}

export const useToasts = create<ToastState>((set) => ({
  toasts: [],
  push: (title, description, tone = "info") => {
    const id = Date.now() + Math.random();
    set((state) => ({ toasts: [...state.toasts, { id, title, description, tone }] }));
    if (typeof window !== "undefined") {
      window.setTimeout(() => {
        set((state) => ({ toasts: state.toasts.filter((toast) => toast.id !== id) }));
      }, 4200);
    }
  },
  dismiss: (id) =>
    set((state) => ({ toasts: state.toasts.filter((toast) => toast.id !== id) })),
}));

interface OfflineState {
  queue: {
    client_id: string;
    operation: "memory_create";
    payload: Record<string, unknown>;
    trip_id: string;
    created_at: string;
  }[];
  enqueue: (tripId: string, payload: Record<string, unknown>) => void;
  clear: (ids: string[]) => void;
}

export const useOffline = create<OfflineState>()(
  persist(
    (set) => ({
      queue: [],
      enqueue: (tripId, payload) =>
        set((state) => ({
          queue: [
            ...state.queue,
            {
              client_id: `offline-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
              operation: "memory_create",
              payload,
              trip_id: tripId,
              created_at: new Date().toISOString(),
            },
          ],
        })),
      clear: (ids) =>
        set((state) => ({
          queue: state.queue.filter((item) => !ids.includes(item.client_id)),
        })),
    }),
    { name: "safar-offline" },
  ),
);
