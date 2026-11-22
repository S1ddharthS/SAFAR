"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Check,
  Compass,
  Download,
  FileText,
  Image as ImageIcon,
  Link2,
  Sparkles,
  Upload,
  Wand2,
  X,
} from "lucide-react";
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
  PageSkeleton,
  SectionTitle,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useInspirations, useTrip } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { InspirationCandidate, InspirationExtraction, InspirationItem } from "@/lib/types";
import { errorMessage, formatDateTime, titleCase } from "@/lib/utils";

const SOURCES = [
  { value: "text", label: "Pasted text" },
  { value: "link", label: "Link" },
  { value: "image_url", label: "Image" },
];

const SOURCE_LABELS: Record<string, string> = {
  text: "your text",
  link_metadata: "link metadata",
  ocr: "image OCR",
  url_path: "link path",
};

export default function InspirationsPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const inspirations = useInspirations(tripId);
  const queryClient = useQueryClient();
  const { push } = useToasts();

  const [sourceType, setSourceType] = useState("text");
  const [content, setContent] = useState("");
  const [mediaUrl, setMediaUrl] = useState<string | null>(null);
  const [uploadedName, setUploadedName] = useState<string | null>(null);
  const [latest, setLatest] = useState<InspirationItem | null>(null);

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["inspirations", tripId] });

  const uploadImage = useMutation({
    mutationFn: (file: File) => {
      const data = new FormData();
      data.append("file", file);
      return api<{ media_url: string; media_type: string; bytes: number }>(
        `/api/trips/${tripId}/media`,
        { method: "POST", body: data },
      );
    },
    onSuccess: (result) => {
      setMediaUrl(result.media_url);
      push("Image uploaded", "It stays on this server and is read locally.", "success");
    },
    onError: (error) => {
      setMediaUrl(null);
      push("Could not upload the image", errorMessage(error), "error");
    },
  });

  const importDream = useMutation({
    mutationFn: () =>
      api<{ id: string; extraction: InspirationExtraction }>(
        `/api/trips/${tripId}/inspirations`,
        {
          method: "POST",
          body: {
            source_type: sourceType,
            content:
              content.trim() ||
              (uploadedName ? `Uploaded image: ${uploadedName}` : "Uploaded image"),
            media_url: sourceType === "image_url" ? mediaUrl : null,
          },
        },
      ),
    onSuccess: (result) => {
      setLatest({
        id: result.id,
        source_type: sourceType,
        content: content.trim() || uploadedName || "Uploaded image",
        status: "extracted",
        extracted: result.extraction,
        created_at: new Date().toISOString(),
      });
      push("Inspiration saved", "Review each candidate before proposing anything.", "success");
      setContent("");
      setMediaUrl(null);
      setUploadedName(null);
      refresh();
    },
    onError: (error) => push("Could not import", errorMessage(error), "error"),
  });

  const review = useMutation({
    mutationFn: (input: { candidateId: string; decision: "accept" | "reject" }) =>
      api<{ id: string; status: string; extraction: InspirationExtraction }>(
        `/api/trips/${tripId}/inspirations/${latest?.id}/review`,
        {
          method: "POST",
          body: { candidate_id: input.candidateId, decision: input.decision },
        },
      ),
    onSuccess: (result) => {
      setLatest((current) =>
        current ? { ...current, status: result.status, extracted: result.extraction } : current,
      );
      refresh();
    },
    onError: (error) => push("Could not save the decision", errorMessage(error), "error"),
  });

  const propose = useMutation({
    mutationFn: (entry: { id: string; name: string }) =>
      api(`/api/trips/${tripId}/proposals`, {
        method: "POST",
        body: {
          kind: "add_activity",
          title: `Add ${entry.name}`,
          summary: "Proposed from the Dream Import. Group decides before the plan changes.",
          activity_id: entry.id,
          day: trip.data?.start_date?.slice(0, 10),
          start_time: "10:00",
        },
      }),
    onSuccess: () => {
      push("Proposal created", "The group can vote. Nothing is changed silently.", "success");
      queryClient.invalidateQueries({ queryKey: ["proposals", tripId] });
    },
    onError: (error) => push("Could not propose", errorMessage(error), "error"),
  });

  if (inspirations.isLoading) return <PageSkeleton />;
  if (inspirations.error || !inspirations.data) {
    return <ErrorState error={inspirations.error || new Error("Inspirations unavailable")} retry={() => inspirations.refetch()} />;
  }

  const items = inspirations.data.items;
  const canImport =
    sourceType === "image_url"
      ? Boolean(mediaUrl) || content.trim().length >= 2
      : content.trim().length >= 2;

  return (
    <div className="space-y-5">
      <div>
        <p className="eyebrow">Dream import</p>
        <h2 className="mt-1 text-2xl">Bring the inspiration in</h2>
        <p className="mt-1 max-w-prose text-sm text-muted">
          Paste text, a link or an image. Extraction proposes destinations, activities, dates and
          budgets. Nothing is added to the plan automatically, and every candidate needs your review.
        </p>
      </div>

      <Card className="space-y-3">
        <SectionTitle title="Import inspiration" />
        <div className="flex flex-wrap gap-1.5">
          {SOURCES.map((source) => {
            const Icon =
              source.value === "image_url" ? ImageIcon : source.value === "link" ? Link2 : Wand2;
            return (
              <button
                key={source.value}
                type="button"
                aria-pressed={sourceType === source.value}
                onClick={() => {
                  setSourceType(source.value);
                  setLatest(null);
                }}
                className={
                  sourceType === source.value
                    ? "inline-flex items-center gap-1 rounded-full border border-ink bg-ink px-3 py-1 text-[12px] text-paper"
                    : "inline-flex items-center gap-1 rounded-full border border-line bg-surface px-3 py-1 text-[12px] text-muted hover:border-ink/30 hover:text-ink"
                }
              >
                <Icon size={12} /> {source.label}
              </button>
            );
          })}
        </div>

        {sourceType === "image_url" ? (
          <div className="space-y-2">
            <Field
              label="Upload an image"
              hint="The file stays on this server. OCR runs locally when installed."
            >
              <label className="flex min-h-11 cursor-pointer items-center gap-2 rounded-xl border border-dashed border-line bg-surface px-3 py-2 text-[12.5px] text-muted hover:border-ink/30 hover:text-ink">
                <Upload size={14} />
                <span>{uploadedName ? uploadedName : "Choose a PNG, JPEG or WebP image"}</span>
                <input
                  type="file"
                  accept="image/png,image/jpeg,image/webp"
                  className="sr-only"
                  onChange={(event) => {
                    const file = event.target.files?.[0];
                    if (!file) return;
                    setUploadedName(file.name);
                    setMediaUrl(null);
                    uploadImage.mutate(file);
                  }}
                />
              </label>
            </Field>
            {uploadImage.isPending ? <p className="text-[12px] text-muted">Uploading…</p> : null}
            <Field
              label="Or describe the image"
              hint="Text is matched even when OCR is unavailable."
            >
              <Textarea
                value={content}
                onChange={(event) => setContent(event.target.value)}
                placeholder="A screenshot of a Tokyo food itinerary with a ¥20,000 budget…"
              />
            </Field>
          </div>
        ) : (
          <Field label={sourceType === "text" ? "What inspired you?" : "URL"}>
            {sourceType === "text" ? (
              <Textarea
                value={content}
                onChange={(event) => setContent(event.target.value)}
                placeholder="Kyoto for 5 days in March, food markets, quiet temples, budget under €900…"
              />
            ) : (
              <Input
                value={content}
                onChange={(event) => setContent(event.target.value)}
                placeholder="https://…"
              />
            )}
          </Field>
        )}

        <Button
          onClick={() => importDream.mutate()}
          loading={importDream.isPending}
          disabled={!canImport || uploadImage.isPending}
        >
          <Download size={14} /> Import
        </Button>
      </Card>

      {latest ? (
        <ExtractionCard
          item={latest}
          reviewPending={review.isPending}
          onReview={(candidateId, decision) => review.mutate({ candidateId, decision })}
          onPropose={(entry) => propose.mutate(entry)}
          proposing={propose.isPending}
        />
      ) : null}

      {items.length === 0 ? (
        <EmptyState
          title="No inspirations yet"
          description="Import a travel note, a link or an image to see candidate matches."
          icon={<Sparkles size={24} />}
        />
      ) : (
        <div className="space-y-3">
          <SectionTitle title="History" hint={`${items.length} imported`} />
          {items.map((item) => (
            <div key={item.id} className="rounded-2xl border border-line bg-surface p-3.5">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex flex-wrap items-center gap-1.5">
                  <Badge tone="outline">
                    {item.source_type === "image_url" ? "Image" : titleCase(item.source_type)}
                  </Badge>
                  <Badge tone={item.status === "reviewed" ? "jade" : "neutral"}>
                    {titleCase(item.status)}
                  </Badge>
                  {item.extracted.review ? (
                    <span className="text-[10.5px] text-faint">
                      {item.extracted.review.accepted} accepted · {item.extracted.review.rejected}{" "}
                      rejected · {item.extracted.review.pending} pending
                    </span>
                  ) : null}
                </div>
                <span className="text-[10.5px] text-faint">{formatDateTime(item.created_at)}</span>
              </div>
              <p className="mt-1.5 line-clamp-2 text-[12.5px] leading-5 text-muted">
                {item.content}
              </p>
              {item.extracted.matches?.length ? (
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {item.extracted.matches.slice(0, 8).map((match) => (
                    <Badge
                      key={match.candidate_id || `${match.type}-${match.name}`}
                      tone={
                        match.decision === "accept"
                          ? "jade"
                          : match.decision === "reject"
                            ? "neutral"
                            : match.type === "activity"
                              ? "jade"
                              : "neutral"
                      }
                    >
                      {match.name} · {Math.round(match.confidence * 100)}%
                    </Badge>
                  ))}
                </div>
              ) : null}
            </div>
          ))}
        </div>
      )}

      <FlowNote icon={<Compass size={14} />}>
        Extraction is deterministic matching over the text you supply. Link reading is optional and off
        by default; image OCR runs locally and never uploads your file. No content is sent to an AI
        model.
      </FlowNote>
    </div>
  );
}

function ExtractionCard({
  item,
  reviewPending,
  onReview,
  onPropose,
  proposing,
}: {
  item: InspirationItem;
  reviewPending: boolean;
  onReview: (candidateId: string, decision: "accept" | "reject") => void;
  onPropose: (entry: { id: string; name: string }) => void;
  proposing: boolean;
}) {
  const matches = item.extracted?.matches ?? [];
  const providers = item.extracted?.metadata?.providers ?? [];
  const link = item.extracted?.metadata?.link;
  const ocr = item.extracted?.metadata?.ocr;
  const review = item.extracted?.review;

  return (
    <Card className="space-y-3 border-jade/20">
      <SectionTitle
        title="Extraction"
        hint="Suggestions only — accept, reject, then propose"
        action={
          <Badge tone={review && review.pending === 0 ? "jade" : "outline"}>
            {review ? `${review.pending} pending` : "needs confirmation"}
          </Badge>
        }
      />

      {link?.title || link?.description ? (
        <div className="rounded-xl border border-line bg-surface px-3 py-2">
          <p className="text-[10px] uppercase tracking-wide text-faint">
            Page metadata · reported by the site
          </p>
          {link.title ? <p className="text-[12.5px] font-medium text-ink">{link.title}</p> : null}
          {link.description ? (
            <p className="mt-0.5 text-[12px] text-muted">{link.description}</p>
          ) : null}
          {link.site_name ? (
            <p className="mt-0.5 text-[10.5px] text-faint">{link.site_name}</p>
          ) : null}
        </div>
      ) : null}

      {ocr?.available ? (
        <div className="rounded-xl border border-line bg-surface px-3 py-2">
          <p className="text-[10px] uppercase tracking-wide text-faint">
            Image text · machine-read
          </p>
          <p className="mt-0.5 text-[12px] leading-5 text-muted">{ocr.preview}</p>
          <p className="mt-1 text-[10.5px] text-faint">
            OCR can misread. Confirm every candidate.
          </p>
        </div>
      ) : null}

      {matches.length === 0 ? (
        <p className="text-sm text-muted">
          No catalog matches found. Try naming a destination or activity explicitly.
        </p>
      ) : (
        <div className="space-y-2">
          {matches.map((match) => (
            <CandidateRow
              key={match.candidate_id || `${match.type}-${match.name}`}
              match={match}
              disabled={reviewPending}
              onReview={onReview}
              onPropose={onPropose}
              proposing={proposing}
            />
          ))}
        </div>
      )}

      {providers.length ? (
        <div className="space-y-1">
          {providers.map((provider) => (
            <p key={provider.provider} className="text-[11px] text-faint">
              {provider.ok ? "Used" : "Not used"} · {provider.provider}:{" "}
              {provider.ok
                ? `${provider.provenance}${provider.attribution ? ` · ${provider.attribution}` : ""}`
                : provider.message}
            </p>
          ))}
        </div>
      ) : null}

      {item.extracted?.notes?.length ? (
        <ul className="space-y-1">
          {item.extracted.notes.map((note) => (
            <li key={note} className="text-[12px] text-muted">
              · {note}
            </li>
          ))}
        </ul>
      ) : null}
      {item.extracted?.limitations?.length ? (
        <FlowNote icon={<Sparkles size={14} />}>
          {item.extracted.limitations.join(" ")}
        </FlowNote>
      ) : null}
    </Card>
  );
}

function CandidateRow({
  match,
  disabled,
  onReview,
  onPropose,
  proposing,
}: {
  match: InspirationCandidate;
  disabled: boolean;
  onReview: (candidateId: string, decision: "accept" | "reject") => void;
  onPropose: (entry: { id: string; name: string }) => void;
  proposing: boolean;
}) {
  const decided = match.decision === "accept" || match.decision === "reject";
  return (
    <div className="rounded-xl border border-line bg-surface px-3 py-2">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-[12.5px] font-medium text-ink">
            {match.name}{" "}
            <span className="ml-1 text-[10px] uppercase tracking-wide text-faint">{match.type}</span>
          </p>
          <p className="text-[12px] text-muted">{match.evidence}</p>
          <div className="mt-1 flex flex-wrap items-center gap-1.5">
            <Badge tone={match.confidence >= 0.8 ? "jade" : "outline"}>
              {Math.round(match.confidence * 100)}%
            </Badge>
            {match.source ? (
              <span className="text-[10.5px] text-faint">
                from {SOURCE_LABELS[match.source] || match.source}
              </span>
            ) : null}
            {match.source_span?.text ? (
              <span className="inline-flex items-center gap-1 text-[10.5px] text-faint">
                <FileText size={10} /> “{match.source_span.text}”
              </span>
            ) : null}
            {match.provenance ? (
              <span className="text-[10px] uppercase tracking-wide text-faint">
                {match.provenance}
              </span>
            ) : null}
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-1.5">
          {decided ? (
            <Badge tone={match.decision === "accept" ? "jade" : "neutral"}>
              {match.decision === "accept" ? "accepted" : "rejected"}
            </Badge>
          ) : (
            <>
              <Button
                size="sm"
                variant="secondary"
                disabled={disabled || !match.candidate_id}
                onClick={() => match.candidate_id && onReview(match.candidate_id, "accept")}
              >
                <Check size={12} /> Accept
              </Button>
              <Button
                size="sm"
                variant="ghost"
                disabled={disabled || !match.candidate_id}
                onClick={() => match.candidate_id && onReview(match.candidate_id, "reject")}
              >
                <X size={12} /> Reject
              </Button>
            </>
          )}
          {match.type === "activity" && match.id ? (
            <Button
              size="sm"
              variant="subtle"
              loading={proposing}
              onClick={() => onPropose({ id: match.id as string, name: match.name })}
            >
              Propose
            </Button>
          ) : null}
        </div>
      </div>
    </div>
  );
}
