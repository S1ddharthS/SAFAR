"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  BadgeCheck,
  CircleSlash,
  Image as ImageIcon,
  NotebookPen,
  PlayCircle,
  Send,
  Sparkles,
  Wand2,
} from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  FlowNote,
  Input,
  Modal,
  PageSkeleton,
  SectionTitle,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useStudio } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { Memory } from "@/lib/types";
import { cn, errorMessage, formatDateTime, titleCase } from "@/lib/utils";

interface CaptionSuggestion {
  memory_id: string;
  suggestion: string;
  ai_generated: boolean;
  approved: boolean;
  grounding: string;
  disclosure: string;
}

export default function MemoryStudioPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const studio = useStudio(tripId);
  const queryClient = useQueryClient();
  const { push } = useToasts();

  const [selected, setSelected] = useState<string[]>([]);
  const [eventOpen, setEventOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [summary, setSummary] = useState("");
  const [startAt, setStartAt] = useState("");
  const [captionFor, setCaptionFor] = useState<Memory | null>(null);
  const [caption, setCaption] = useState("");
  const [grounding, setGrounding] = useState("");

  const refresh = () => {
    queryClient.invalidateQueries({ queryKey: ["studio", tripId] });
    queryClient.invalidateQueries({ queryKey: ["memories", tripId] });
    queryClient.invalidateQueries({ queryKey: ["replay", tripId] });
  };

  const suggestEvents = useMutation({
    mutationFn: () =>
      api<{ created: unknown[]; note: string }>(`/api/trips/${tripId}/memory-studio/suggest-events`, {
        method: "POST",
      }),
    onSuccess: (result) => {
      push("Suggestions created", `${result.created.length} candidate group(s). Review before approving.`, "success");
      refresh();
    },
    onError: (error) => push("Could not suggest", errorMessage(error), "error"),
  });

  const approveEvent = useMutation({
    mutationFn: (eventId: string) =>
      api(`/api/trips/${tripId}/memory-events/${eventId}/approve`, { method: "POST" }),
    onSuccess: () => {
      push("Event approved", "It can now appear in the travel book.", "success");
      refresh();
    },
    onError: (error) => push("Could not approve", errorMessage(error), "error"),
  });

  const createEvent = useMutation({
    mutationFn: () =>
      api(`/api/trips/${tripId}/memory-events`, {
        method: "POST",
        body: {
          title,
          summary: summary || null,
          start_at: new Date(startAt).toISOString(),
          memory_ids: selected,
          status: "suggested",
        },
      }),
    onSuccess: () => {
      push("Event created", "Approve it when the story feels right.", "success");
      setEventOpen(false);
      setTitle("");
      setSummary("");
      setStartAt("");
      setSelected([]);
      refresh();
    },
    onError: (error) => push("Could not create event", errorMessage(error), "error"),
  });

  const requestCaption = useMutation({
    mutationFn: (memoryId: string) =>
      api<CaptionSuggestion>(`/api/trips/${tripId}/memories/${memoryId}/caption`, { method: "POST" }),
    onSuccess: (result) => {
      setCaption(result.suggestion);
      setGrounding(result.grounding);
    },
    onError: (error) => push("Could not draft caption", errorMessage(error), "error"),
  });

  const applyCaption = useMutation({
    mutationFn: () =>
      api(`/api/trips/${tripId}/memories/${captionFor?.id}`, {
        method: "PATCH",
        body: { caption, approved: true },
      }),
    onSuccess: () => {
      push("Caption saved", "The caption is now attributed and editable.", "success");
      setCaptionFor(null);
      setCaption("");
      setGrounding("");
      refresh();
    },
    onError: (error) => push("Could not save caption", errorMessage(error), "error"),
  });

  if (studio.isLoading) return <PageSkeleton />;
  if (studio.error || !studio.data) {
    return <ErrorState error={studio.error || new Error("Studio unavailable")} retry={() => studio.refetch()} />;
  }

  const data = studio.data;
  const disabledCapabilities = Object.entries(data.capabilities).filter(([, value]) => value === false);

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">AI Memory Studio</p>
          <h2 className="mt-1 text-2xl">Group moments, draft captions</h2>
          <p className="mt-1 max-w-prose text-sm text-muted">{data.disclosure}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="secondary" size="sm" onClick={() => suggestEvents.mutate()} loading={suggestEvents.isPending}>
            <Wand2 size={14} /> Suggest events
          </Button>
          <Button size="sm" onClick={() => setEventOpen(true)}>
            <NotebookPen size={14} /> New event
          </Button>
          <Link href={`/trips/${tripId}/memories/replay`}>
            <Button variant="secondary" size="sm">
              <PlayCircle size={14} /> Replay
            </Button>
          </Link>
        </div>
      </div>

      <Card className="space-y-4">
        <SectionTitle
          title="Events"
          hint="AI-suggested groups stay unapproved until a contributor accepts them"
          action={<Badge tone="outline">{data.events.length}</Badge>}
        />
        {data.events.length === 0 ? (
          <EmptyState
            title="No memory events yet"
            description="Suggest events from your captured memories, then review each group before approving."
            icon={<Sparkles size={22} />}
          />
        ) : (
          <div className="space-y-2">
            {data.events.map((event) => (
              <div key={event.id} className="rounded-2xl border border-line bg-surface p-3.5">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="text-[13.5px] font-medium text-ink">{event.title}</p>
                    {event.summary ? (
                      <p className="mt-0.5 text-[12px] leading-5 text-muted">{event.summary}</p>
                    ) : null}
                    <p className="mt-1 text-[12px] text-faint">
                      {formatDateTime(event.start_at)}
                      {event.end_at ? ` → ${formatDateTime(event.end_at)}` : ""} · {event.memory_ids.length} memory(ies)
                    </p>
                  </div>
                  <div className="flex items-center gap-1.5">
                    <Badge tone={event.status === "approved" ? "jade" : "ember"}>{event.status}</Badge>
                    {event.status !== "approved" ? (
                      <Button size="sm" variant="secondary" onClick={() => approveEvent.mutate(event.id)}>
                        <BadgeCheck size={13} /> Approve
                      </Button>
                    ) : null}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      <Card className="space-y-4">
        <SectionTitle
          title="Memories"
          hint="Select memories to group, or draft a grounded caption"
          action={
            selected.length ? (
              <Button size="sm" variant="subtle" onClick={() => setEventOpen(true)}>
                Group {selected.length} selected
              </Button>
            ) : null
          }
        />
        {data.memories.length === 0 ? (
          <EmptyState
            title="Nothing captured yet"
            description="Add photos, notes or voice from the timeline first."
            icon={<NotebookPen size={22} />}
          />
        ) : (
          <div className="grid gap-2 sm:grid-cols-2">
            {data.memories.map((memory) => {
              const active = selected.includes(memory.id);
              return (
                <div
                  key={memory.id}
                  className={cn(
                    "rounded-2xl border p-3.5 transition-colors",
                    active ? "border-ember bg-ember-soft/40" : "border-line bg-surface",
                  )}
                >
                  <div className="flex items-start justify-between gap-2">
                    <button
                      type="button"
                      aria-pressed={active}
                      onClick={() =>
                        setSelected((current) =>
                          current.includes(memory.id)
                            ? current.filter((id) => id !== memory.id)
                            : [...current, memory.id],
                        )
                      }
                      className="min-w-0 text-left"
                    >
                      <div className="flex flex-wrap items-center gap-1.5">
                        <Badge tone="outline">
                          {memory.kind === "photo" ? <ImageIcon size={10} /> : null}
                          {titleCase(memory.kind)}
                        </Badge>
                        {memory.ai_generated ? <Badge tone="neutral">AI</Badge> : null}
                        {active ? <Badge tone="ember">selected</Badge> : null}
                      </div>
                      <p className="mt-1 line-clamp-2 text-[12.5px] leading-5 text-ink">
                        {memory.text_content || memory.caption || `Captured ${formatDateTime(memory.captured_at)}`}
                      </p>
                      <p className="mt-1 text-[10.5px] text-faint">
                        {memory.author?.display_name || "Traveller"} · {formatDateTime(memory.captured_at)}
                      </p>
                    </button>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => {
                        setCaptionFor(memory);
                        setCaption(memory.caption || "");
                        setGrounding("");
                        requestCaption.mutate(memory.id);
                      }}
                    >
                      <Sparkles size={13} /> Caption
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Card>

      <Card className="space-y-2">
        <SectionTitle title="What this studio can do" hint="Capabilities are reported honestly" />
        <div className="flex flex-wrap gap-1.5">
          {Object.entries(data.capabilities).map(([key, value]) => (
            <Badge key={key} tone={value === false ? "outline" : "jade"}>
              {value === false ? <CircleSlash size={10} /> : <BadgeCheck size={10} />} {key.replace(/_/g, " ")}
            </Badge>
          ))}
        </div>
        {disabledCapabilities.length ? (
          <FlowNote icon={<CircleSlash size={14} />}>
            Not configured on this deployment:{" "}
            {disabledCapabilities.map(([key]) => key.replace(/_/g, " ")).join(", ")}. Suggestions use recorded
            metadata only — no invented people, feelings or places.
          </FlowNote>
        ) : null}
      </Card>

      <Modal open={eventOpen} onClose={() => setEventOpen(false)} title="Create memory event">
        <form
          className="space-y-3"
          onSubmit={(event) => {
            event.preventDefault();
            if (!title || !startAt) return;
            createEvent.mutate();
          }}
        >
          <Field label="Title">
            <Input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Sunset at the mirador" />
          </Field>
          <Field label="Summary" hint="Optional">
            <Textarea value={summary} onChange={(event) => setSummary(event.target.value)} />
          </Field>
          <Field label="Starts at">
            <Input type="datetime-local" value={startAt} onChange={(event) => setStartAt(event.target.value)} />
          </Field>
          <p className="text-[12px] text-muted">
            {selected.length} memory(ies) selected. You can change the selection from the list above.
          </p>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={() => setEventOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" loading={createEvent.isPending} disabled={!title || !startAt}>
              <Send size={14} /> Create event
            </Button>
          </div>
        </form>
      </Modal>

      <Modal
        open={Boolean(captionFor)}
        onClose={() => {
          setCaptionFor(null);
          setGrounding("");
        }}
        title="Draft caption"
      >
        <div className="space-y-3">
          <p className="text-[12px] leading-5 text-muted">
            Grounded only in capture time, optional location and the confirmed itinerary. Review before publishing.
          </p>
          <Textarea
            value={caption}
            onChange={(event) => setCaption(event.target.value)}
            aria-label="Draft caption"
          />
          {grounding ? <FlowNote icon={<Sparkles size={14} />}>{grounding}</FlowNote> : null}
          <div className="flex justify-end gap-2">
            <Button
              type="button"
              variant="secondary"
              onClick={() => captionFor && requestCaption.mutate(captionFor.id)}
              loading={requestCaption.isPending}
            >
              <Wand2 size={14} /> Regenerate
            </Button>
            <Button onClick={() => applyCaption.mutate()} loading={applyCaption.isPending} disabled={!caption}>
              <BadgeCheck size={14} /> Accept caption
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
