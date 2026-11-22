"use client";

import {
  Accessibility,
  CalendarDays,
  CheckCircle2,
  Clock3,
  Compass,
  MapPin,
  Search,
  Sparkles,
  Ticket,
  Wallet,
  X,
} from "lucide-react";
import { useParams } from "next/navigation";
import { useId, useMemo, useState } from "react";

import { DestinationImage } from "@/components/DestinationImage";
import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  Input,
  LinkButton,
  PageSkeleton,
  Progress,
  Select,
  Toggle,
} from "@/components/ui";
import { useDestination, useSearch } from "@/lib/hooks";
import type { SearchItem } from "@/lib/types";
import { formatDate, formatMoney, titleCase } from "@/lib/utils";

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function provenanceTone(provenance?: string) {
  if (provenance === "VERIFIED") return "jade" as const;
  if (provenance === "REPORTED") return "ember" as const;
  if (provenance === "UNKNOWN") return "outline" as const;
  return "neutral" as const;
}

function ActivityCard({ item }: { item: SearchItem }) {
  const [open, setOpen] = useState(false);
  const evidenceId = useId();
  const activity = item.activity;
  return (
    <Card interactive className="p-0">
      <div className="p-5">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0"> 
            <div className="flex flex-wrap items-center gap-1.5">
              <Badge tone={provenanceTone(item.provenance)}>{item.provenance || "ESTIMATED"}</Badge>
              {activity.iconic ? <Badge tone="ember">Iconic</Badge> : null}
              {activity.indoor ? <Badge>Indoor</Badge> : <Badge tone="outline">Outdoor</Badge>}
              {activity.wheelchair_accessible === true ? (
                <Badge tone="jade">
                  <Accessibility size={10} /> Step-free
                </Badge>
              ) : activity.wheelchair_accessible === false ? (
                <Badge tone="rose">Access barriers</Badge>
              ) : null}
            </div>
            <h3 className="mt-2 text-xl leading-snug">{activity.name}</h3>
            <p className="mt-1 flex items-center gap-1 text-[12px] text-faint">
              <MapPin size={12} /> {activity.place?.address || activity.place?.name || activity.destination?.name}
            </p>
          </div>
          <div className="w-24 shrink-0 text-right">
            <p className="text-[10px] uppercase tracking-editorial text-faint">Personal fit</p>
            <p className="font-display text-2xl leading-tight text-ember">
              {Math.round(item.personal_fit)}
            </p>
            <Progress
              value={item.personal_fit}
              tone={item.personal_fit >= 70 ? "jade" : "ember"}
              className="mt-1"
            />
          </div>
        </div>

        <p className="mt-3 text-[12.5px] leading-6 text-muted">{activity.description}</p>

        <div className="mt-4 grid grid-cols-2 gap-2 text-[12px] text-muted sm:grid-cols-4">
          <span className="inline-flex items-center gap-1.5">
            <Wallet size={13} className="text-faint" />
            {formatMoney(activity.price_estimate, activity.currency)}
          </span>
          <span className="inline-flex items-center gap-1.5">
            <Clock3 size={13} className="text-faint" />
            {activity.duration_minutes} min
          </span>
          <span className="inline-flex items-center gap-1.5">
            <Sparkles size={13} className="text-faint" />
            Effort {activity.effort}/5
          </span>
          <span className="inline-flex items-center gap-1.5">
            <CheckCircle2 size={13} className="text-faint" />
            {titleCase(item.catalog_freshness?.label || "unknown freshness")}
          </span>
        </div>

        <div className="mt-3 flex flex-wrap gap-1.5">
          {activity.tags.slice(0, 5).map((tag) => (
            <Badge key={tag}>{tag}</Badge>
          ))}
        </div>

        {item.respect_note ? (
          <p className="mt-3 rounded-xl border border-jade/20 bg-jade-soft/30 px-3 py-2 text-[12px] leading-5 text-jade">
            Respect note: {item.respect_note}
          </p>
        ) : null}

        <button
          type="button"
          onClick={() => setOpen((value) => !value)}
          aria-expanded={open}
          aria-controls={evidenceId}
          className="mt-3 text-[12px] font-medium text-ember hover:underline"
        >
          {open ? "Hide evidence" : "Show evidence and access detail"}
        </button>
      </div>

      {open ? (
        <div
          id={evidenceId}
          className="border-t border-line bg-raised/40 p-5 text-[12px] leading-6 text-muted"
        >
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <p className="text-[10px] uppercase tracking-editorial text-faint">Evidence</p>
              <p className="mt-1">
                Source: {activity.source_type || "unknown"}
                {activity.last_verified_at
                  ? ` · last checked ${formatDate(activity.last_verified_at)}`
                  : " · no verification date"}
              </p>
              <p className="mt-1">
                {item.similar_to
                  ? `Similar to ${item.similar_to} (${Math.round((item.similarity || 0) * 100)}% similarity).`
                  : "No similarity claim recorded."}
              </p>
            </div>
            <div>
              <p className="text-[10px] uppercase tracking-editorial text-faint">Access chain</p>
              {activity.access_chain ? (
                <ul className="mt-1 space-y-1">
                  {Object.entries(activity.access_chain)
                    .slice(0, 5)
                    .map(([stage, value]) => (
                      <li key={stage}>
                        <span className="text-ink">{titleCase(stage)}:</span>{" "}
                        {typeof value === "string"
                          ? value
                          : `${titleCase(value.status || "unknown")} — ${value.detail || ""}`}
                      </li>
                    ))}
                </ul>
              ) : (
                <p className="mt-1">No stage-by-stage access record. Treat access as UNKNOWN.</p>
              )}
            </div>
          </div>
          <div className="mt-3">
            <p className="text-[10px] uppercase tracking-editorial text-faint">Opening hours</p>
            {activity.opening_hours ? (
              <p className="mt-1">
                {Object.entries(activity.opening_hours)
                  .map(([day, hours]) => `${day}: ${hours}`)
                  .join(" · ")}
              </p>
            ) : (
              <p className="mt-1">Not recorded.</p>
            )}
          </div>
          <p className="mt-2 text-[12px] text-faint">
            Personal fit is an estimate from Journey DNA, not a live provider score. Verify hours
            before relying on them.
          </p>
        </div>
      ) : null}
    </Card>
  );
}

export default function DestinationPage() {
  const params = useParams<{ destinationId: string }>();
  const destinationId = typeof params?.destinationId === "string" ? params.destinationId : "";
  const destination = useDestination(destinationId || undefined);
  const [q, setQ] = useState("");
  const [lens, setLens] = useState("balanced");
  const [maxBudget, setMaxBudget] = useState("");
  const [maxDuration, setMaxDuration] = useState("");
  const [indoor, setIndoor] = useState(false);
  const [accessible, setAccessible] = useState(false);
  const [tags, setTags] = useState("");

  const searchParams = useMemo(
    () => ({
      destination_id: destinationId,
      q: q || undefined,
      lens,
      max_budget: maxBudget || undefined,
      max_duration: maxDuration || undefined,
      indoor: indoor || undefined,
      accessible: accessible || undefined,
      tags: tags || undefined,
      limit: 30,
    }),
    [destinationId, q, lens, maxBudget, maxDuration, indoor, accessible, tags],
  );
  const search = useSearch(searchParams);

  if (destination.isLoading) return <PageSkeleton />;
  if (destination.error || !destination.data) {
    return (
      <ErrorState error={destination.error || new Error("Destination not found")} retry={() => destination.refetch()} />
    );
  }
  const data = destination.data;
  const activeFilters =
    (q ? 1 : 0) +
    (lens !== "balanced" ? 1 : 0) +
    (maxBudget ? 1 : 0) +
    (maxDuration ? 1 : 0) +
    (indoor ? 1 : 0) +
    (accessible ? 1 : 0) +
    (tags ? 1 : 0);

  function clearFilters() {
    setQ("");
    setLens("balanced");
    setMaxBudget("");
    setMaxDuration("");
    setIndoor(false);
    setAccessible(false);
    setTags("");
  }

  return (
    <div className="space-y-6">
      <div className="overflow-hidden rounded-4xl border border-line">
        <div className="relative flex min-h-[19rem] flex-col justify-end p-6 sm:min-h-[23rem] sm:p-8">
          <DestinationImage
            name={data.name}
            country={data.country}
            heroImage={data.hero_image}
            sizes="(max-width: 1024px) 100vw, 82rem"
            priority
            overlay="bottom"
          />
          <div className="relative z-10 max-w-2xl">
            <p className="text-[10.5px] uppercase tracking-editorial text-paper/70">
              {data.country}
              {data.region ? ` · ${data.region}` : ""}
            </p>
            <h1 className="mt-2 text-balance text-4xl leading-[1.05] text-paper sm:text-[3.4rem]">
              {data.name}
            </h1>
            <p className="mt-3 max-w-xl text-[13.5px] leading-6 text-paper/85">
              {data.description}
            </p>
            <div className="mt-4 flex flex-wrap gap-1.5">
              {data.tags.map((tag) => (
                <span
                  key={tag}
                  className="rounded-full border border-paper/25 bg-paper/10 px-2.5 py-[3px] text-[11.5px] font-medium text-paper backdrop-blur"
                >
                  {tag}
                </span>
              ))}
            </div>
          </div>
          <div className="relative z-10 mt-6 flex flex-wrap items-end justify-between gap-3">
            <p className="inline-flex items-center gap-1.5 text-[12px] text-paper/70">
              <CalendarDays size={13} />
              Best months:{" "}
              {data.best_months.length
                ? data.best_months.map((month) => MONTHS[month - 1]).join(" · ")
                : "year-round"}
            </p>
            <LinkButton
              href={`/trips/new?destination_id=${data.id}&destination_name=${encodeURIComponent(data.name)}`}
              size="lg"
            >
              <Compass size={16} /> Plan a journey here
            </LinkButton>
          </div>
        </div>
      </div>
      <p className="-mt-2 px-1 text-[11px] text-faint">
        Editorial imagery · catalog data is curated, not live inventory.
      </p>

      <div className="grid gap-4 lg:grid-cols-[280px_1fr]">
        <Card className="h-fit space-y-4 lg:sticky lg:top-6">
          <div className="flex items-start justify-between gap-2">
            <div>
              <p className="text-[13px] font-medium">Filter the catalog</p>
              <p className="mt-0.5 text-[12px] text-faint">Filters apply before ranking.</p>
            </div>
            {activeFilters ? (
              <Button variant="ghost" size="sm" onClick={clearFilters}>
                <X size={13} /> Clear
              </Button>
            ) : null}
          </div>
          <Field label="Search">
            <div className="relative">
              <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-faint" />
              <Input
                className="pl-9"
                value={q}
                onChange={(event) => setQ(event.target.value)}
                placeholder="Tea, garden, market…"
                aria-label="Search activities in this destination"
              />
            </div>
          </Field>
          <Field label="Lens">
            <Select value={lens} onChange={(event) => setLens(event.target.value)}>
              <option value="balanced">Balanced</option>
              <option value="iconic">Iconic first</option>
              <option value="similar">Similar finds</option>
            </Select>
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Max price">
              <Input
                type="number"
                min={0}
                value={maxBudget}
                onChange={(event) => setMaxBudget(event.target.value)}
                placeholder="Any"
              />
            </Field>
            <Field label="Max minutes">
              <Input
                type="number"
                min={15}
                step={15}
                value={maxDuration}
                onChange={(event) => setMaxDuration(event.target.value)}
                placeholder="Any"
              />
            </Field>
          </div>
          <Field label="Tags" hint="Comma-separated, e.g. food, history">
            <Input value={tags} onChange={(event) => setTags(event.target.value)} placeholder="food, history" />
          </Field>
          <div className="divide-y divide-line">
            <Toggle checked={indoor} onChange={setIndoor} label="Indoor only" />
            <Toggle
              checked={accessible}
              onChange={setAccessible}
              label="Step-free only"
              description="Unknown access is excluded rather than assumed."
            />
          </div>
        </Card>

        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <p className="text-[12px] text-faint">
              {search.isLoading
                ? "Searching the catalog…"
                : `${search.data?.items.length ?? 0} activities · lens ${search.data?.lens || lens}`}
            </p>
            <Badge tone="outline">
              <Ticket size={10} /> Group decision required
            </Badge>
          </div>
          {search.error ? <ErrorState error={search.error} retry={() => search.refetch()} /> : null}
          {!search.isLoading && (search.data?.items.length ?? 0) === 0 ? (
            <EmptyState
              icon={<Search size={24} />}
              title="No activities match these filters"
              description="Relax a filter or clear the search. Unknown accessibility is never shown as step-free."
            />
          ) : null}
          <div className="space-y-4">
            {(search.data?.items ?? []).map((item) => (
              <ActivityCard key={item.activity.id} item={item} />
            ))}
          </div>
          {search.data?.disclosure ? (
            <p className="rounded-2xl border border-line bg-raised/50 px-4 py-3 text-[12px] leading-5 text-muted">
              {search.data.disclosure}
            </p>
          ) : null}
        </div>
      </div>
    </div>
  );
}
