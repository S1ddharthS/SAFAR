"use client";

import { useMutation } from "@tanstack/react-query";
import {
  BookOpen,
  CalendarDays,
  Clock3,
  Image as ImageIcon,
  Lock,
  NotebookPen,
  PlayCircle,
  Users,
} from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  FlowNote,
  PageSkeleton,
  SectionTitle,
  Stat,
} from "@/components/ui";
import { API_URL, api } from "@/lib/api";
import { useReplay } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { Memory } from "@/lib/types";
import { errorMessage, formatDate, formatTime, titleCase } from "@/lib/utils";

export default function ReplayPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const replay = useReplay(tripId);
  const { push } = useToasts();

  const openBook = useMutation({
    mutationFn: () => api<string>(`/api/trips/${tripId}/travel-book`, { raw: true }),
    onSuccess: (html) => {
      const blob = new Blob([html], { type: "text/html" });
      const url = URL.createObjectURL(blob);
      window.open(url, "_blank", "noopener,noreferrer");
      window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
    },
    onError: (error) => push("Could not build travel book", errorMessage(error), "error"),
  });

  if (replay.isLoading) return <PageSkeleton />;
  if (replay.error || !replay.data) {
    return <ErrorState error={replay.error || new Error("Replay unavailable")} retry={() => replay.refetch()} />;
  }

  const data = replay.data;
  const recordedDays = data.days.filter((day) => day.items.length || day.memories.length || day.events.length);

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Journey replay</p>
          <h2 className="mt-1 text-2xl">{data.trip.name}</h2>
          <p className="mt-1 max-w-prose text-sm text-muted">
            {formatDate(data.trip.start_date)} → {formatDate(data.trip.end_date)} · {data.trip.destination}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button onClick={() => openBook.mutate()} loading={openBook.isPending}>
            <BookOpen size={14} /> Open travel book
          </Button>
          <Link href={`/trips/${tripId}/memories`}>
            <Button variant="secondary" size="sm">
              <NotebookPen size={14} /> Timeline
            </Button>
          </Link>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
        <Stat label="Days" value={data.stats.days_recorded} tone="ink" />
        <Stat label="Memories" value={data.stats.memories} tone="ember" />
        <Stat label="Media" value={data.stats.media} tone="jade" />
        <Stat label="Events" value={data.stats.approved_events} tone="ink" />
        <Stat label="Contributors" value={data.stats.contributors} tone="ember" />
      </div>

      <FlowNote icon={<Lock size={14} />}>{data.permissions}</FlowNote>

      {recordedDays.length === 0 ? (
        <EmptyState
          title="Nothing to replay yet"
          description="Capture memories and confirm itinerary items to build the story of this journey."
          icon={<PlayCircle size={24} />}
        />
      ) : (
        <div className="space-y-4">
          {data.days.map((day) => {
            if (!day.items.length && !day.memories.length && !day.events.length) return null;
            const captions = new Map(day.captions.map((entry) => [entry.memory_id, entry.caption]));
            return (
              <Card key={day.date} className="space-y-4">
                <SectionTitle
                  title={formatDate(day.date)}
                  action={
                    <div className="flex gap-1.5">
                      <Badge tone="outline">
                        <CalendarDays size={10} /> {day.items.length} plan
                      </Badge>
                      <Badge tone="outline">
                        <ImageIcon size={10} /> {day.memories.length} memories
                      </Badge>
                    </div>
                  }
                />

                {day.items.length ? (
                  <ol className="space-y-1.5">
                    {day.items.map((item) => (
                      <li key={item.id} className="flex items-center gap-2 text-[12.5px]">
                        <span className="inline-flex w-14 shrink-0 items-center gap-1 font-mono text-[12px] text-faint">
                          <Clock3 size={11} /> {formatTime(item.start_time)}
                        </span>
                        <span className="text-ink">{item.title}</span>
                        {item.protected ? <Badge tone="jade">protected</Badge> : null}
                      </li>
                    ))}
                  </ol>
                ) : null}

                {day.events.length ? (
                  <div className="space-y-1.5">
                    {day.events.map((event) => (
                      <div key={event.id} className="rounded-xl border border-jade/20 bg-jade-soft/40 px-3 py-2">
                        <p className="text-[12.5px] font-medium text-ink">{event.title}</p>
                        {event.summary ? <p className="text-[12px] text-muted">{event.summary}</p> : null}
                      </div>
                    ))}
                  </div>
                ) : null}

                {day.memories.length ? (
                  <div className="grid gap-2 sm:grid-cols-2">
                    {day.memories.map((memory) => (
                      <ReplayMemory key={memory.id} memory={memory} caption={captions.get(memory.id)} />
                    ))}
                  </div>
                ) : null}
              </Card>
            );
          })}
        </div>
      )}

      <FlowNote icon={<Users size={14} />}>{data.format_note}</FlowNote>
    </div>
  );
}

function ReplayMemory({ memory, caption }: { memory: Memory; caption?: string }) {
  const mediaUrl =
    memory.media_url && memory.media_url.startsWith("/media/") ? `${API_URL}${memory.media_url}` : memory.media_url;
  const isImage = memory.media_type?.startsWith("image/") && mediaUrl;

  return (
    <div className="overflow-hidden rounded-xl border border-line bg-surface">
      {isImage ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={mediaUrl} alt={caption || "Memory"} className="h-36 w-full object-cover" />
      ) : null}
      <div className="space-y-1 p-3">
        <div className="flex items-center gap-1.5">
          <Badge tone="outline">{titleCase(memory.kind)}</Badge>
          {memory.visibility === "private" ? (
            <Badge tone="ember">
              <Lock size={9} /> private
            </Badge>
          ) : null}
        </div>
        <p className="line-clamp-3 text-[12px] leading-5 text-ink">
          {caption || memory.caption || memory.text_content || "A captured moment."}
        </p>
        <p className="text-[10.5px] text-faint">
          {memory.author?.display_name || "Traveller"}
          {memory.ai_generated ? " · AI caption" : ""}
        </p>
      </div>
    </div>
  );
}
