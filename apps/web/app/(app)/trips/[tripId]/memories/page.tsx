"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Camera,
  CloudOff,
  Image as ImageIcon,
  Lock,
  MapPin,
  Mic,
  NotebookPen,
  PlayCircle,
  Shield,
  Sparkles,
  Trash2,
  Users,
} from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useRef, useState } from "react";

import {
  Avatar,
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  FlowNote,
  IconButton,
  LinkButton,
  Modal,
  PageHeader,
  PageSkeleton,
  Select,
  Textarea,
} from "@/components/ui";
import { API_URL, api } from "@/lib/api";
import { useMemories } from "@/lib/hooks";
import { useAuth, useOffline, useToasts } from "@/lib/store";
import type { Memory } from "@/lib/types";
import { cn, errorMessage, formatDate, formatDateTime, titleCase } from "@/lib/utils";

const KINDS = [
  { value: "text", label: "Note" },
  { value: "photo", label: "Photo" },
  { value: "video", label: "Video" },
  { value: "voice", label: "Voice" },
];

function resolveMedia(url: string) {
  return url.startsWith("/media/") ? `${API_URL}${url}` : url;
}

export default function MemoriesPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const timeline = useMemories(tripId);
  const queryClient = useQueryClient();
  const { push } = useToasts();
  const { user } = useAuth();
  const offline = useOffline();

  const [text, setText] = useState("");
  const [kind, setKind] = useState("text");
  const [visibility, setVisibility] = useState("trip");
  const [saveOffline, setSaveOffline] = useState(false);
  const [media, setMedia] = useState<{ url: string; type: string } | null>(null);
  const [uploading, setUploading] = useState(false);
  const [removing, setRemoving] = useState<Memory | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  const refresh = () => {
    queryClient.invalidateQueries({ queryKey: ["memories", tripId] });
    queryClient.invalidateQueries({ queryKey: ["studio", tripId] });
    queryClient.invalidateQueries({ queryKey: ["replay", tripId] });
  };

  const createMemory = useMutation({
    mutationFn: () =>
      api<Memory>(`/api/trips/${tripId}/memories`, {
        method: "POST",
        body: {
          kind,
          text_content: text || null,
          media_url: media?.url || null,
          media_type: media?.type || null,
          visibility,
          captured_at: new Date().toISOString(),
        },
      }),
    onSuccess: () => {
      push("Memory saved", "It will appear on the timeline and replay.", "success");
      setText("");
      setMedia(null);
      setKind("text");
      refresh();
    },
    onError: (error) => push("Could not save memory", errorMessage(error), "error"),
  });

  const removeMemory = useMutation({
    mutationFn: (memoryId: string) =>
      api(`/api/trips/${tripId}/memories/${memoryId}`, { method: "DELETE" }),
    onSuccess: () => {
      push("Memory removed", "It is hidden from every shared view.", "info");
      setRemoving(null);
      refresh();
    },
    onError: (error) => push("Could not remove", errorMessage(error), "error"),
  });

  const handleUpload = async (file: File) => {
    setUploading(true);
    try {
      const form = new FormData();
      form.append("file", file);
      const result = await api<{ media_url: string; media_type: string }>(
        `/api/trips/${tripId}/media`,
        { method: "POST", body: form },
      );
      setMedia({ url: result.media_url, type: result.media_type });
      if (result.media_type.startsWith("image/")) setKind("photo");
      else if (result.media_type.startsWith("video/")) setKind("video");
      else setKind("voice");
      push("Uploaded", "Attach a memory to share it.", "success");
    } catch (error) {
      push("Upload failed", errorMessage(error), "error");
    } finally {
      setUploading(false);
    }
  };

  const handleSubmit = () => {
    const isOffline = typeof navigator !== "undefined" && !navigator.onLine;
    if (saveOffline || isOffline) {
      offline.enqueue(tripId, {
        kind,
        text_content: text || null,
        media_url: media?.url || null,
        media_type: media?.type || null,
        visibility,
        captured_at: new Date().toISOString(),
        client_id: `offline-${Date.now()}`,
      });
      push("Saved offline", "It will sync when you reconnect from the Offline page.", "info");
      setText("");
      setMedia(null);
      setKind("text");
      return;
    }
    createMemory.mutate();
  };

  if (timeline.isLoading) return <PageSkeleton />;
  if (timeline.error || !timeline.data) {
    return <ErrorState error={timeline.error || new Error("Timeline unavailable")} retry={() => timeline.refetch()} />;
  }

  const data = timeline.data;

  return (
    <div className="space-y-6">
      <PageHeader
        as="h2"
        size="md"
        eyebrow="Memory timeline"
        title={`${data.total} moment${data.total === 1 ? "" : "s"} recorded`}
        description={data.permissions}
        actions={
          <>
            <LinkButton href={`/trips/${tripId}/memories/studio`} variant="secondary" size="sm">
              <Sparkles size={14} /> Memory studio
            </LinkButton>
            <LinkButton href={`/trips/${tripId}/memories/replay`} variant="secondary" size="sm">
              <PlayCircle size={14} /> Journey replay
            </LinkButton>
          </>
        }
      />

      <Card className="space-y-5">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <div>
            <h3 className="text-lg">Capture a moment</h3>
            <p className="mt-0.5 text-[12.5px] text-muted">
              Notes, photos and voice — private until you share.
            </p>
          </div>
          {media ? <Badge tone="outline">1 attachment</Badge> : null}
        </div>

        <div className="grid gap-5 lg:grid-cols-[1fr_19rem]">
          <div className="space-y-3.5">
            <div role="group" aria-label="Memory type" className="flex flex-wrap gap-1.5">
              {KINDS.map((entry) => (
                <button
                  key={entry.value}
                  type="button"
                  onClick={() => setKind(entry.value)}
                  aria-pressed={kind === entry.value}
                  className={cn(
                    "rounded-full border px-3 py-1 text-[12px] transition-colors",
                    kind === entry.value
                      ? "border-ink bg-ink text-paper"
                      : "border-line bg-surface text-muted hover:border-ink/30 hover:text-ink",
                  )}
                >
                  {entry.label}
                </button>
              ))}
              <button
                type="button"
                onClick={() => fileRef.current?.click()}
                className="inline-flex items-center gap-1 rounded-full border border-line bg-surface px-3 py-1 text-[12px] text-muted transition-colors hover:border-ink/30 hover:text-ink"
              >
                <Camera size={13} />{" "}
                {uploading ? "Uploading…" : media ? "Replace media" : "Add media"}
              </button>
              <input
                ref={fileRef}
                type="file"
                accept="image/jpeg,image/png,image/webp,video/mp4,audio/mpeg,audio/ogg,audio/wav,audio/webm"
                className="hidden"
                onChange={(event) => {
                  const file = event.target.files?.[0];
                  if (file) handleUpload(file);
                  event.target.value = "";
                }}
              />
            </div>

            {media ? (
              media.type.startsWith("image/") ? (
                <div className="relative overflow-hidden rounded-xl border border-line">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={resolveMedia(media.url)}
                    alt="Attachment preview"
                    className="h-36 w-full object-cover"
                  />
                  <button
                    type="button"
                    onClick={() => setMedia(null)}
                    className="absolute right-2 top-2 rounded-full bg-ink/70 px-2 py-1 text-[11px] text-paper backdrop-blur hover:bg-ink"
                  >
                    Remove
                  </button>
                </div>
              ) : (
                <div className="flex items-center justify-between gap-2 rounded-xl border border-line bg-surface px-3 py-2 text-[12px] text-muted">
                  <span className="inline-flex items-center gap-1.5">
                    {memoryIcon(kind)} {media.type}
                  </span>
                  <button
                    type="button"
                    className="text-rose hover:underline"
                    onClick={() => setMedia(null)}
                  >
                    remove
                  </button>
                </div>
              )
            ) : null}

            <Field label="The moment" htmlFor="memory-text">
              <Textarea
                id="memory-text"
                value={text}
                onChange={(event) => setText(event.target.value)}
                placeholder="What just happened? Keep it honest and specific."
              />
            </Field>
          </div>

          <div className="space-y-3 self-start rounded-2xl border border-line bg-raised/40 p-4">
            <Field label="Visibility" hint="Private memories need explicit permission to share">
              <Select value={visibility} onChange={(event) => setVisibility(event.target.value)}>
                <option value="trip">Trip members</option>
                <option value="private">Only me</option>
              </Select>
            </Field>
            <button
              type="button"
              onClick={() => setSaveOffline((value) => !value)}
              aria-pressed={saveOffline}
              className={cn(
                "inline-flex w-full items-center justify-center gap-1.5 rounded-xl border px-3 py-2.5 text-[12.5px] transition-colors",
                saveOffline
                  ? "border-ember bg-ember-soft text-ember"
                  : "border-line bg-surface text-muted hover:border-ink/30 hover:text-ink",
              )}
            >
              <CloudOff size={14} /> {saveOffline ? "Will save offline" : "Save for offline sync"}
            </button>
            <p className="text-[11.5px] leading-5 text-faint">
              {visibility === "private" ? (
                <span className="inline-flex items-start gap-1 text-ember">
                  <Lock size={11} className="mt-1 shrink-0" /> Private — only you until you grant
                  access.
                </span>
              ) : (
                <span className="inline-flex items-start gap-1">
                  <Users size={11} className="mt-1 shrink-0" /> Shared with active trip members.
                </span>
              )}
            </p>
            <Button
              className="w-full"
              onClick={handleSubmit}
              loading={createMemory.isPending || uploading}
              disabled={!text && !media}
            >
              <NotebookPen size={14} /> Save memory
            </Button>
          </div>
        </div>
      </Card>

      {offline.queue.filter((item) => item.trip_id === tripId).length ? (
        <FlowNote icon={<CloudOff size={14} />}>
          {offline.queue.filter((item) => item.trip_id === tripId).length} memory(ies) waiting to sync.{" "}
          <Link href={`/trips/${tripId}/offline`} className="text-ember hover:underline">
            Open offline queue →
          </Link>
        </FlowNote>
      ) : null}

      {data.days.length === 0 ? (
        <EmptyState
          title="No memories yet"
          description="Capture the first moment. Photos, notes and voice stay private until you share them."
          icon={<NotebookPen size={24} />}
        />
      ) : (
        <div className="space-y-7">
          {data.days.map((day) => {
            const date = new Date(`${day.date}T12:00:00`);
            return (
              <div key={day.date} className="space-y-3">
                <div className="flex items-center gap-3">
                  <span className="flex h-10 w-10 shrink-0 flex-col items-center justify-center rounded-full border border-line bg-surface">
                    <span className="font-display text-[15px] leading-none">
                      {date.getDate()}
                    </span>
                    <span className="text-[9px] uppercase tracking-editorial text-faint">
                      {date.toLocaleDateString("en", { month: "short" })}
                    </span>
                  </span>
                  <div className="min-w-0">
                    <p className="font-display text-lg leading-none">{formatDate(day.date)}</p>
                    <p className="mt-1 text-[11.5px] text-faint">
                      {day.memories.length} moment{day.memories.length === 1 ? "" : "s"}
                    </p>
                  </div>
                  <span className="h-px flex-1 bg-line" />
                </div>
                <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
                  {day.memories.map((memory) => (
                    <MemoryCard
                      key={memory.id}
                      memory={memory}
                      isMine={memory.user_id === user?.id}
                      onDelete={() => setRemoving(memory)}
                    />
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      )}

      <Modal
        open={Boolean(removing)}
        onClose={() => setRemoving(null)}
        title="Remove this memory?"
        description="It disappears from the timeline, replay and any shared view. Private memories are never included in snapshots."
        footer={
          <>
            <Button variant="secondary" onClick={() => setRemoving(null)}>
              Keep it
            </Button>
            <Button
              variant="danger"
              loading={removeMemory.isPending}
              onClick={() => removing && removeMemory.mutate(removing.id)}
            >
              <Trash2 size={14} /> Remove memory
            </Button>
          </>
        }
      >
        <p className="text-sm leading-6 text-muted">
          {removing?.text_content
            ? `“${removing.text_content.slice(0, 140)}${removing.text_content.length > 140 ? "…" : ""}”`
            : "This attachment will be removed from every view."}
        </p>
      </Modal>

      <FlowNote icon={<Shield size={14} />}>
        Private memories are excluded from offline snapshots, replay and travel books unless their owner
        grants access. AI captions are suggestions until you accept them.
      </FlowNote>
    </div>
  );
}

function memoryIcon(kind: string) {
  if (kind === "photo") return <ImageIcon size={13} />;
  if (kind === "voice") return <Mic size={13} />;
  if (kind === "video") return <PlayCircle size={13} />;
  return <NotebookPen size={13} />;
}

function MemoryCard({
  memory,
  isMine,
  onDelete,
}: {
  memory: Memory;
  isMine: boolean;
  onDelete: () => void;
}) {
  const mediaUrl = memory.media_url ? resolveMedia(memory.media_url) : null;
  const isImage = memory.media_type?.startsWith("image/") && mediaUrl;
  const privateMemory = memory.visibility === "private";

  return (
    <article
      className={cn(
        "group flex flex-col overflow-hidden rounded-3xl border bg-surface transition-shadow hover:shadow-card",
        privateMemory ? "border-ember/30" : "border-line",
      )}
    >
      {isImage ? (
        <div className="relative overflow-hidden">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={mediaUrl}
            alt={memory.caption || "Trip memory"}
            loading="lazy"
            className="h-48 w-full object-cover transition-transform duration-700 ease-editorial group-hover:scale-[1.03]"
          />
        </div>
      ) : mediaUrl ? (
        <div className="flex items-center gap-2 border-b border-line bg-raised px-3.5 py-2 text-[12px] text-muted">
          {memoryIcon(memory.kind)} {memory.media_type || "Attachment"}
        </div>
      ) : null}
      <div className="flex flex-1 flex-col gap-2 p-4">
        <div className="flex flex-wrap items-center gap-1.5">
          <Badge tone="outline">{titleCase(memory.kind)}</Badge>
          {privateMemory ? (
            <Badge tone="ember">
              <Lock size={10} /> Private
            </Badge>
          ) : (
            <Badge tone="jade">
              <Users size={10} /> Trip
            </Badge>
          )}
          {memory.ai_generated ? <Badge tone="neutral">AI captioned</Badge> : null}
        </div>
        {memory.text_content ? (
          <p className="whitespace-pre-line text-[13.5px] leading-6 text-ink">{memory.text_content}</p>
        ) : null}
        {memory.caption ? (
          <p className="rounded-xl bg-raised/60 px-3 py-2 text-[12px] italic leading-5 text-muted">
            {memory.caption}
          </p>
        ) : null}
        <div className="mt-auto flex items-center gap-2.5 border-t border-line pt-3">
          <Avatar name={memory.author?.display_name || "Traveller"} size={24} />
          <p className="min-w-0 flex-1 text-[11.5px] leading-5 text-faint">
            <span className="block truncate text-muted">
              {memory.author?.display_name || "Traveller"}
            </span>
            {formatDateTime(memory.captured_at)}
            {memory.lat !== null && memory.lon !== null ? (
              <span className="ml-1.5 inline-flex items-center gap-0.5">
                <MapPin size={10} /> pinned
              </span>
            ) : null}
          </p>
          {isMine ? (
            <IconButton
              label="Remove memory"
              onClick={onDelete}
              className="hover:bg-rose/10 hover:text-rose"
            >
              <Trash2 size={13} />
            </IconButton>
          ) : null}
        </div>
      </div>
    </article>
  );
}
