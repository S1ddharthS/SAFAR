import { describe, expect, it } from "vitest";

import {
  cn,
  daysBetween,
  errorMessage,
  formatDate,
  formatMoney,
  formatTime,
  initials,
  pct,
  titleCase,
  todayIso,
} from "@/lib/utils";

describe("formatting", () => {
  it("formats money and tolerates missing values", () => {
    expect(formatMoney(12.5, "EUR")).toContain("12.5");
    expect(formatMoney(null)).toBe("—");
    expect(formatMoney(Number.NaN)).toBe("—");
  });

  it("formats dates and rejects invalid input", () => {
    expect(formatDate(null)).toBe("—");
    expect(formatDate("not-a-date")).toBe("—");
    expect(formatDate("2026-04-03")).toContain("2026");
  });

  it("trims times to HH:MM", () => {
    expect(formatTime("09:30:00")).toBe("09:30");
    expect(formatTime(null)).toBe("");
  });
});

describe("trip maths", () => {
  it("counts a trip's days inclusively", () => {
    expect(daysBetween("2026-04-01", "2026-04-01")).toBe(1);
    expect(daysBetween("2026-04-01", "2026-04-04")).toBe(4);
    expect(daysBetween("2026-04-04", "2026-04-01")).toBe(1);
  });

  it("returns an ISO date for today", () => {
    expect(todayIso()).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});

describe("display helpers", () => {
  it("builds initials and falls back safely", () => {
    expect(initials("Aiko Tanaka")).toBe("AT");
    expect(initials("Mira")).toBe("M");
    expect(initials(null)).toBe("?");
  });

  it("humanises snake case", () => {
    expect(titleCase("step_free_access")).toBe("Step Free Access");
  });

  it("clamps percentages", () => {
    expect(pct(50, 100)).toBe(50);
    expect(pct(-10, 100)).toBe(0);
    expect(pct(150, 100)).toBe(100);
    expect(pct(null)).toBe(0);
  });

  it("merges class names", () => {
    expect(cn("px-2", "px-4")).toBe("px-4");
  });
});

describe("errors", () => {
  it("reads messages without inventing detail", () => {
    expect(errorMessage(new Error("Network down"))).toBe("Network down");
    expect(errorMessage("Denied")).toBe("Denied");
    expect(errorMessage({})).toBe("Something went wrong. Please try again.");
  });
});
