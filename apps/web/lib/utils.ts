import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatMoney(value: number | null | undefined, currency = "EUR") {
  if (value === null || value === undefined || Number.isNaN(value)) return "—";
  try {
    return new Intl.NumberFormat("en", {
      style: "currency",
      currency,
      maximumFractionDigits: 2,
    }).format(value);
  } catch {
    return `${currency} ${value.toFixed(2)}`;
  }
}

export function formatDate(value: string | Date | null | undefined, options?: Intl.DateTimeFormatOptions) {
  if (!value) return "—";
  const date = typeof value === "string" ? new Date(value) : value;
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("en", {
    day: "numeric",
    month: "short",
    year: "numeric",
    ...options,
  }).format(date);
}

export function formatDay(value: string | Date, options?: Intl.DateTimeFormatOptions) {
  const date = typeof value === "string" ? new Date(`${value.slice(0, 10)}T12:00:00`) : value;
  return new Intl.DateTimeFormat("en", {
    weekday: "long",
    day: "numeric",
    month: "long",
    ...options,
  }).format(date);
}

export function formatTime(value: string | null | undefined) {
  if (!value) return "";
  return value.slice(0, 5);
}

export function formatDateTime(value: string | null | undefined) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("en", {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

export function daysBetween(start: string, end: string) {
  const a = new Date(`${start.slice(0, 10)}T12:00:00`).getTime();
  const b = new Date(`${end.slice(0, 10)}T12:00:00`).getTime();
  return Math.max(1, Math.round((b - a) / 86400000) + 1);
}

export function todayIso() {
  const now = new Date();
  const offset = now.getTimezoneOffset() * 60000;
  return new Date(now.getTime() - offset).toISOString().slice(0, 10);
}

export function daysUntil(start: string) {
  const target = new Date(`${start.slice(0, 10)}T12:00:00`).getTime();
  const today = new Date(`${todayIso()}T12:00:00`).getTime();
  return Math.round((target - today) / 86400000);
}

export function tripPhase(trip: { start_date: string; end_date: string; status?: string }) {
  if (trip.status === "completed") return "Completed";
  const start = daysUntil(trip.start_date);
  const end = daysUntil(trip.end_date);
  if (start > 0) return `In ${start} day${start === 1 ? "" : "s"}`;
  if (end >= 0) return "Happening now";
  return "Past";
}

export function initials(name?: string | null) {
  if (!name) return "?";
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}

export function titleCase(value: string) {
  return value
    .replace(/_/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

export function pct(value: number | null | undefined, max = 100) {
  if (value === null || value === undefined) return 0;
  return Math.max(0, Math.min(100, (value / max) * 100));
}

export function errorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  return "Something went wrong. Please try again.";
}

export const SENTIMENTS = [
  { value: "loved", label: "Loved it" },
  { value: "would_return", label: "Would return" },
  { value: "okay", label: "It was okay" },
  { value: "not_for_me", label: "Not for me" },
  { value: "too_expensive", label: "Too expensive" },
  { value: "too_far", label: "Too far" },
];

export const DNA_LABELS: Record<string, string> = {
  culture: "Culture",
  adventure: "Adventure",
  food: "Food",
  nature: "Nature",
  photography: "Photography",
  shopping: "Shopping",
  history: "History",
  relaxation: "Relaxation",
  luxury: "Comfort",
  budget: "Budget sense",
  outdoor: "Outdoors",
  local: "Local life",
};
