/**
 * Test-only browser shims.
 *
 * Recent Node versions can run jsdom without a `--localstorage-file`, in which
 * case `window.localStorage` is absent. Zustand's persist middleware falls back
 * to an undefined storage and then fails on `setItem`. Production browsers are
 * unaffected; this file only supplies an in-memory Storage for unit tests.
 */

class MemoryStorage implements Storage {
  private readonly entries = new Map<string, string>();

  get length(): number {
    return this.entries.size;
  }

  clear(): void {
    this.entries.clear();
  }

  getItem(key: string): string | null {
    return this.entries.has(key) ? (this.entries.get(key) as string) : null;
  }

  key(index: number): string | null {
    return Array.from(this.entries.keys())[index] ?? null;
  }

  removeItem(key: string): void {
    this.entries.delete(key);
  }

  setItem(key: string, value: string): void {
    this.entries.set(String(key), String(value));
  }
}

function hasLocalStorage(value: unknown): value is Storage {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as Storage).getItem === "function" &&
    typeof (value as Storage).setItem === "function"
  );
}

if (typeof globalThis !== "undefined" && !hasLocalStorage(globalThis.localStorage)) {
  const storage = new MemoryStorage();
  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: storage,
  });
  if (typeof window !== "undefined") {
    Object.defineProperty(window, "localStorage", {
      configurable: true,
      value: storage,
    });
  }
}
