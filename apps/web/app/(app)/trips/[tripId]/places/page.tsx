"use client";

import { Search as SearchIcon, Sparkles, SlidersHorizontal } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";

import {
  Badge,
  Card,
  EmptyState,
  ErrorState,
  Field,
  FlowNote,
  Input,
  PageSkeleton,
  Progress,
  Select,
} from "@/components/ui";
import { useSearch, useTrip } from "@/lib/hooks";
import { cn, formatMoney, pct, titleCase } from "@/lib/utils";

const TAGS = ["culture", "food", "nature", "history", "adventure", "relaxation", "shopping", "iconic"];
const LENSES = [
  { value: "balanced", label: "Balanced" },
  { value: "local", label: "Local life" },
  { value: "quiet", label: "Quiet" },
  { value: "iconic", label: "Iconic" },
];

export default function PlacesPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const [q, setQ] = useState("");
  const [lens, setLens] = useState("balanced");
  const [maxBudget, setMaxBudget] = useState("");
  const [maxDuration, setMaxDuration] = useState("");
  const [tags, setTags] = useState<string[]>([]);
  const [indoor, setIndoor] = useState(false);
  const [accessible, setAccessible] = useState(false);

  const results = useSearch({
    destination_id: trip.data?.destination_id || undefined,
    q,
    lens,
    max_budget: maxBudget ? Number(maxBudget) : undefined,
    max_duration: maxDuration ? Number(maxDuration) : undefined,
    tags: tags.length ? tags.join(",") : undefined,
    indoor,
    accessible,
    limit: 24,
  });

  const items = useMemo(() => results.data?.items || [], [results.data]);

  if (trip.isLoading) return <PageSkeleton />;
  if (trip.error || !trip.data) {
    return <ErrorState error={trip.error || new Error("Trip not found")} retry={() => trip.refetch()} />;
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Catalog search</p>
          <h2 className="mt-1 text-2xl">Find something for {trip.data.destination_name || "the journey"}</h2>
          <p className="mt-1 max-w-prose text-sm text-muted">
            Search activities in this destination. Personal fit is an estimate from your Journey DNA,
            not a live provider score.
          </p>
        </div>
        {trip.data.destination_id ? null : (
          <Badge tone="ember">Set a destination to search</Badge>
        )}
      </div>

      <Card className="space-y-4">
        <div className="relative">
          <SearchIcon size={16} className="absolute left-3.5 top-3.5 text-faint" />
          <Input
            value={q}
            onChange={(event) => setQ(event.target.value)}
            placeholder="Museum, viewpoint, food tour…"
            className="h-11 pl-10"
          />
        </div>

        <div className="grid gap-3 sm:grid-cols-4">
          <Field label="Lens">
            <Select value={lens} onChange={(event) => setLens(event.target.value)}>
              {LENSES.map((entry) => (
                <option key={entry.value} value={entry.value}>
                  {entry.label}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Max price" hint={`${trip.data.currency} per person`}>
            <Input
              type="number"
              min="0"
              value={maxBudget}
              onChange={(event) => setMaxBudget(event.target.value)}
              placeholder="Any"
            />
          </Field>
          <Field label="Max duration" hint="minutes">
            <Input
              type="number"
              min="0"
              value={maxDuration}
              onChange={(event) => setMaxDuration(event.target.value)}
              placeholder="Any"
            />
          </Field>
          <div className="space-y-1.5">
            <span className="text-[13px] font-medium text-ink">Hard filters</span>
            <div className="flex flex-wrap gap-1.5">
              <button
                type="button"
                aria-pressed={indoor}
                onClick={() => setIndoor((value) => !value)}
                className={cn(
                  "rounded-full border px-2.5 py-1 text-[12px]",
                  indoor ? "border-ember bg-ember-soft text-ember" : "border-line bg-surface text-muted",
                )}
              >
                Indoor
              </button>
              <button
                type="button"
                aria-pressed={accessible}
                onClick={() => setAccessible((value) => !value)}
                className={cn(
                  "rounded-full border px-2.5 py-1 text-[12px]",
                  accessible ? "border-jade bg-jade-soft text-jade" : "border-line bg-surface text-muted",
                )}
              >
                Step-free
              </button>
            </div>
          </div>
        </div>

        <div className="flex flex-wrap gap-1.5">
          <span className="inline-flex items-center gap-1 text-[12px] text-faint">
            <SlidersHorizontal size={11} /> Tags
          </span>
          {TAGS.map((tag) => (
            <button
              key={tag}
              type="button"
              aria-pressed={tags.includes(tag)}
              onClick={() =>
                setTags((current) =>
                  current.includes(tag) ? current.filter((entry) => entry !== tag) : [...current, tag],
                )
              }
              className={cn(
                "rounded-full border px-2.5 py-1 text-[12px]",
                tags.includes(tag)
                  ? "border-ink bg-ink text-paper"
                  : "border-line bg-surface text-muted hover:border-ink/30 hover:text-ink",
              )}
            >
              {titleCase(tag)}
            </button>
          ))}
        </div>
      </Card>

      {results.isLoading ? (
        <PageSkeleton />
      ) : results.error ? (
        <ErrorState error={results.error} retry={() => results.refetch()} />
      ) : items.length === 0 ? (
        <EmptyState
          title="No matches"
          description="Loosen a filter or try a different lens. The catalog only contains places in this destination."
          icon={<SearchIcon size={24} />}
        />
      ) : (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-[12px] text-faint">{items.length} result(s)</p>
            {results.data?.personalised ? (
              <Badge tone="jade">
                <Sparkles size={10} /> Personalised fit
              </Badge>
            ) : (
              <Badge tone="outline">Catalog fit</Badge>
            )}
          </div>
          {items.map((entry) => (
            <Card key={entry.activity.id} className="space-y-3">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex flex-wrap gap-1.5">
                    <Badge tone="outline">{entry.provenance || "ESTIMATED"}</Badge>
                    {entry.activity.fragile ? <Badge tone="rose">Fragile place</Badge> : null}
                    {entry.activity.wheelchair_accessible === true ? (
                      <Badge tone="jade">Step-free</Badge>
                    ) : null}
                  </div>
                  <h3 className="mt-1.5 text-lg leading-snug">
                    <Link href={`/trips/${tripId}/places/${entry.activity.id}`} className="hover:text-ember">
                      {entry.activity.name}
                    </Link>
                  </h3>
                  <p className="mt-1 max-w-prose line-clamp-2 text-[13px] leading-5 text-muted">
                    {entry.activity.description}
                  </p>
                  <p className="mt-1.5 flex flex-wrap gap-x-3 text-[12px] text-faint">
                    <span>{formatMoney(entry.activity.price_estimate, entry.activity.currency)}</span>
                    <span>{entry.activity.duration_minutes} min</span>
                    <span>effort {entry.activity.effort}/5</span>
                    {entry.activity.place?.name ? <span>{entry.activity.place.name}</span> : null}
                  </p>
                </div>
                <div className="w-32 shrink-0">
                  <div className="flex items-baseline justify-between text-[12px]">
                    <span className="text-faint">Personal fit</span>
                    <span className="font-mono text-ink">{entry.personal_fit.toFixed(0)}</span>
                  </div>
                  <Progress
                    value={pct(entry.personal_fit)}
                    tone={entry.personal_fit >= 65 ? "jade" : "ember"}
                    className="mt-1"
                  />
                  {entry.similar_to ? (
                    <p className="mt-1.5 text-[10px] text-faint">Similar to {entry.similar_to}</p>
                  ) : null}
                </div>
              </div>
              {entry.respect_note ? (
                <p className="rounded-xl border border-ember/20 bg-ember-soft/40 px-3 py-2 text-[12px] leading-5 text-ember">
                  {entry.respect_note}
                </p>
              ) : null}
              <div className="flex justify-end border-t border-line pt-2.5">
                <Link
                  href={`/trips/${tripId}/places/${entry.activity.id}`}
                  className="text-[12px] text-ember hover:underline"
                >
                  Evidence, access & reports →
                </Link>
              </div>
            </Card>
          ))}
        </div>
      )}

      <FlowNote>
        {results.data?.disclosure ||
          "Catalog attributes are curated data. Personal fit is an estimate, not a live provider score."}
      </FlowNote>
    </div>
  );
}
