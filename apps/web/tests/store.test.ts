import { beforeEach, describe, expect, it } from "vitest";

import { useOffline, useToasts } from "@/lib/store";

beforeEach(() => {
  useOffline.setState({ queue: [] });
  useToasts.setState({ toasts: [] });
});

describe("offline queue", () => {
  it("stores captures with a unique client id and clears only settled ids", () => {
    useOffline.getState().enqueue("trip-1", { text_content: "First note" });
    useOffline.getState().enqueue("trip-1", { text_content: "Second note" });

    const queue = useOffline.getState().queue;
    expect(queue).toHaveLength(2);
    expect(queue[0].client_id).not.toBe(queue[1].client_id);
    expect(queue[0].operation).toBe("memory_create");
    expect(queue[0].trip_id).toBe("trip-1");

    useOffline.getState().clear([queue[0].client_id]);
    expect(useOffline.getState().queue).toHaveLength(1);
    expect(useOffline.getState().queue[0].payload.text_content).toBe("Second note");
  });
});

describe("toasts", () => {
  it("pushes and dismisses by id", () => {
    useToasts.getState().push("Saved", "Memory stored", "success");
    const [toast] = useToasts.getState().toasts;
    expect(toast.title).toBe("Saved");
    expect(toast.tone).toBe("success");

    useToasts.getState().dismiss(toast.id);
    expect(useToasts.getState().toasts).toHaveLength(0);
  });
});
