export const API_URL =
  process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "") || "http://localhost:8000";

const CSRF_COOKIE = "safar_csrf";
const CSRF_HEADER = "X-CSRF-Token";
const UNSAFE = new Set(["POST", "PUT", "PATCH", "DELETE"]);

// Access and CSRF tokens live in memory only. The refresh token is an
// HttpOnly cookie that JavaScript can never read.
let accessToken: string | null = null;
let csrfToken: string | null = null;
let refreshInFlight: Promise<boolean> | null = null;

export class ApiError extends Error {
  status: number;
  detail: unknown;

  constructor(status: number, detail: unknown) {
    const message =
      typeof detail === "string"
        ? detail
        : Array.isArray(detail)
          ? detail
              .map((item) =>
                typeof item === "object" && item && "msg" in item
                  ? String((item as { msg: unknown }).msg)
                  : String(item),
              )
              .join(" · ")
          : detail && typeof detail === "object" && "message" in detail
            ? String((detail as { message: unknown }).message)
            : `Request failed (${status})`;
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.detail = detail;
  }
}

export function setSessionTokens(access: string | null, csrf: string | null) {
  accessToken = access;
  csrfToken = csrf;
}

export function clearSessionTokens() {
  accessToken = null;
  csrfToken = null;
}

export function getAccessToken(): string | null {
  return accessToken;
}

function readCookie(name: string): string | null {
  if (typeof document === "undefined") return null;
  const match = document.cookie
    .split(";")
    .map((part) => part.trim())
    .find((part) => part.startsWith(`${name}=`));
  return match ? decodeURIComponent(match.slice(name.length + 1)) : null;
}

function currentCsrf(): string | null {
  return csrfToken || readCookie(CSRF_COOKIE);
}

export interface SessionPayload {
  access_token: string;
  csrf_token: string;
  user: unknown;
}

export async function refreshSession(): Promise<SessionPayload | null> {
  if (refreshInFlight) {
    const ok = await refreshInFlight;
    return ok ? { access_token: accessToken || "", csrf_token: csrfToken || "", user: null } : null;
  }
  refreshInFlight = (async () => {
    try {
      const response = await fetch(`${API_URL}/api/auth/refresh`, {
        method: "POST",
        credentials: "include",
        cache: "no-store",
      });
      if (!response.ok) {
        clearSessionTokens();
        return false;
      }
      const data = (await response.json()) as SessionPayload;
      setSessionTokens(data.access_token, data.csrf_token);
      return true;
    } catch {
      return false;
    } finally {
      refreshInFlight = null;
    }
  })();
  const ok = await refreshInFlight;
  return ok ? { access_token: accessToken || "", csrf_token: csrfToken || "", user: null } : null;
}

/** Restore the session from the HttpOnly refresh cookie after a page load. */
export async function bootstrapSession<T>(): Promise<T | null> {
  try {
    let response = await fetch(`${API_URL}/api/auth/me`, {
      credentials: "include",
      cache: "no-store",
    });
    if (response.status === 401) {
      if (!(await refreshSession())) return null;
      response = await fetch(`${API_URL}/api/auth/me`, {
        credentials: "include",
        cache: "no-store",
      });
    }
    if (!response.ok) return null;
    return (await response.json()) as T;
  } catch {
    return null;
  }
}

type Options = Omit<RequestInit, "body"> & { body?: unknown; raw?: boolean };

async function request<T>(path: string, options: Options, retried: boolean): Promise<T> {
  const method = (options.method || "GET").toUpperCase();
  const headers = new Headers(options.headers);
  if (options.body !== undefined && !(options.body instanceof FormData)) {
    headers.set("Content-Type", "application/json");
  }
  headers.set("Accept", "application/json");
  if (accessToken) headers.set("Authorization", `Bearer ${accessToken}`);
  const csrf = currentCsrf();
  if (UNSAFE.has(method) && csrf) headers.set(CSRF_HEADER, csrf);

  const response = await fetch(`${API_URL}${path}`, {
    ...options,
    headers,
    credentials: "include",
    body:
      options.body === undefined
        ? undefined
        : options.body instanceof FormData
          ? options.body
          : JSON.stringify(options.body),
    cache: "no-store",
  });

  if (response.status === 401 && !retried && !path.startsWith("/api/auth/")) {
    const refreshed = await refreshSession();
    if (refreshed) return request<T>(path, options, true);
    if (typeof window !== "undefined") {
      window.dispatchEvent(new Event("safar:unauthorized"));
    }
  }

  if (!response.ok) {
    let detail: unknown = response.statusText;
    try {
      const data = await response.json();
      detail = data.detail ?? data;
    } catch {
      try {
        detail = await response.text();
      } catch {
        /* ignore */
      }
    }
    throw new ApiError(response.status, detail);
  }

  if (response.status === 204) return undefined as T;
  const contentType = response.headers.get("content-type") || "";
  if (options.raw || contentType.includes("text/html") || contentType.includes("text/csv")) {
    return (await response.text()) as T;
  }
  return (await response.json()) as T;
}

export function api<T>(path: string, options: Options = {}): Promise<T> {
  return request<T>(path, options, false);
}

/** Short-lived WebSocket ticket; access tokens are never placed in localStorage. */
export async function wsUrl(tripId: string): Promise<string | null> {
  const ticket = async () => {
    const headers = new Headers();
    if (accessToken) headers.set("Authorization", `Bearer ${accessToken}`);
    const csrf = currentCsrf();
    if (csrf) headers.set(CSRF_HEADER, csrf);
    const response = await fetch(`${API_URL}/api/auth/ws-ticket`, {
      method: "POST",
      credentials: "include",
      headers,
      cache: "no-store",
    });
    if (!response.ok) return null;
    const data = (await response.json()) as { ticket: string };
    return data.ticket;
  };

  let value = await ticket();
  if (!value) {
    if (!(await refreshSession())) return null;
    value = await ticket();
  }
  if (!value) return null;
  const base = API_URL.replace(/^http/, "ws");
  return `${base}/ws/trips/${tripId}?token=${encodeURIComponent(value)}`;
}
