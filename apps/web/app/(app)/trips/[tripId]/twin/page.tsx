"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ArrowLeftRight, Check, GitCompare, Plus, Search, Scale, X } from "lucide-react";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";

import {
  Badge,
  Button,
  Card,
  ErrorState,
  Field,
  FlowNote,
  Input,
  LinkButton,
  PageSkeleton,
  SectionTitle,
  Stat,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useItinerary, useSearch, useTrip } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { TwinComparison } from "@/lib/types";
import { cn, formatMoney, todayIso } from "@/lib/utils";

export default function TwinPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const itinerary = useItinerary(tripId);
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);
  const [day, setDay] = useState(todayIso());
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<string[]>([]);
  const [comparison, setComparison] = useState<TwinComparison | null>(null);
  const search = useSearch({
    destination_id: trip.data?.destination_id || undefined,
    q: query,
    limit: 12,
  });

  const [negotiation, setNegotiation] = useState<{
    status: string;
    message?: string;
    compromise?: { name: string; minimum_fit: number; average_fit: number };
    alternative?: { name: string; minimum_fit: number; average_fit: number };
    who_benefits?: string;
    who_compromises?: string;
    trade_offs?: string[];
    disclosure?: string;
  } | null>(null);
  const [sideA, setSideA] = useState<string[]>([]);
  const [sideB, setSideB] = useState<string[]>([]);

  const compare = useMutation({
    mutationFn: () =>
      api<TwinComparison>(`/api/trips/${tripId}/twin/compare`, {
        method: "POST",
        body: { activity_ids: selected, day },
      }),
    onSuccess: (data) => {
      setComparison(data);
      push("Comparison ready", "Read-only. Nothing has changed in the plan.", "success");
    },
    onError: (error) => push("Could not compare", (error as Error).message, "error"),
  });

  const adopt = useMutation({
    mutationFn: () =>
      api(`/api/trips/${tripId}/twin/propose`, {
        method: "POST",
        body: { activity_ids: selected, day },
      }),
    onSuccess: () => {
      push("Proposal opened", "The group decides whether to adopt the alternative.", "success");
      queryClient.invalidateQueries({ queryKey: ["proposals", tripId] });
    },
    onError: (error) => push("Could not propose", (error as Error).message, "error"),
  });

  const negotiate = useMutation({
    mutationFn: () =>
      api<typeof negotiation>(`/api/trips/${tripId}/negotiate`, {
        method: "POST",
        body: { option_a: sideA, option_b: sideB, for_date: day },
      }),
    onSuccess: (data) => setNegotiation(data),
    onError: (error) => push("Could not negotiate", (error as Error).message, "error"),
  });

  const dayActivities = useMemo(
    () =>
      (itinerary.data?.items || []).filter(
        (item) => String(item.day).slice(0, 10) === day && item.activity_id,
      ),
    [itinerary.data, day],
  );

  if (trip.isLoading) return <PageSkeleton />;
  if (trip.error || !trip.data) {
    return <ErrorState error={trip.error || new Error("Trip not found")} retry={() => trip.refetch()} />;
  }

  const currency = trip.data.currency;
  const toggle = (id: string) =>
    setSelected((current) =>
      current.includes(id) ? current.filter((entry) => entry !== id) : [...current, id].slice(0, 16),
    );

  const catalog = search.data?.items || [];
  const byId = new Map(catalog.map((entry) => [entry.activity.id, entry.activity]));

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Trip Twin · read-only comparison</p>
          <h2 className="mt-1 text-2xl">Compare before you commit</h2>
          <p className="mt-1 max-w-prose text-sm text-muted">
            Build an alternative day and compare fit, cost, time and travel against the confirmed
            plan. Adopting it creates a proposal — never a silent change.
          </p>
        </div>
        <LinkButton href={`/trips/${tripId}/engine`} variant="secondary" size="sm">
          <ArrowLeftRight size={14} /> Back to engine
        </LinkButton>
      </div>

      <Card className="space-y-3">
        <div className="grid gap-3 sm:grid-cols-[auto_1fr_auto] sm:items-end">
          <Field label="Compare the day of">
            <Input
              type="date"
              value={day}
              min={trip.data.start_date.slice(0, 10)}
              max={trip.data.end_date.slice(0, 10)}
              onChange={(event) => setDay(event.target.value)}
              className="w-40"
            />
          </Field>
          <Field label="Search activities for the alternative">
            <div className="relative">
              <Search size={15} className="absolute left-3 top-3.5 text-faint" />
              <Input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Add activities to the alternative"
                className="pl-9"
              />
            </div>
          </Field>
          <Button
            loading={compare.isPending}
            disabled={selected.length === 0}
            onClick={() => compare.mutate()}
          >
            <GitCompare size={14} /> Compare
          </Button>
        </div>

        {dayActivities.length ? (
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="text-[12px] text-faint">In the confirmed day:</span>
            {dayActivities.map((item) => (
              <button
                key={item.id}
                type="button"
                aria-pressed={Boolean(item.activity_id && selected.includes(item.activity_id))}
                onClick={() => item.activity_id && toggle(item.activity_id)}
                className={cn(
                  "rounded-full border px-2.5 py-1 text-[12px]",
                  item.activity_id && selected.includes(item.activity_id)
                    ? "border-ink bg-ink text-paper"
                    : "border-line bg-surface text-muted hover:border-ink/30 hover:text-ink",
                )}
              >
                {item.title}
              </button>
            ))}
          </div>
        ) : null}

        {selected.length ? (
          <div className="flex flex-wrap items-center gap-1.5 rounded-xl bg-raised/60 p-2">
            <span className="text-[12px] text-faint">Alternative ({selected.length}/16):</span>
            {selected.map((id) => (
              <span
                key={id}
                className="inline-flex items-center gap-1 rounded-full border border-line bg-surface px-2.5 py-0.5 text-[12px] text-ink"
              >
                {byId.get(id)?.name || "Activity"}
                <button
                  type="button"
                  onClick={() => toggle(id)}
                  aria-label={`Remove ${byId.get(id)?.name || "activity"} from the alternative list`}
                >
                  <X size={11} />
                </button>
              </span>
            ))}
          </div>
        ) : null}

        {search.isLoading ? (
          <p className="text-xs text-faint">Searching…</p>
        ) : catalog.length ? (
          <div className="grid gap-1.5 sm:grid-cols-2">
            {catalog.slice(0, 8).map((entry) => {
              const active = selected.includes(entry.activity.id);
              return (
                <button
                  key={entry.activity.id}
                  type="button"
                  aria-pressed={active}
                  onClick={() => toggle(entry.activity.id)}
                  className={cn(
                    "flex items-center justify-between gap-2 rounded-xl border px-3 py-2 text-left text-[12.5px]",
                    active
                      ? "border-ember bg-ember-soft/60 text-ink"
                      : "border-line bg-surface text-muted hover:border-ink/30",
                  )}
                >
                  <span className="truncate">{entry.activity.name}</span>
                  <span className="shrink-0 font-mono text-[10px]">
                    {formatMoney(entry.activity.price_estimate, entry.activity.currency)}
                  </span>
                </button>
              );
            })}
          </div>
        ) : null}
      </Card>

      {comparison ? (
        <div className="space-y-4">
          <div className="grid gap-3 md:grid-cols-2">
            {[comparison.confirmed_plan, comparison.alternative_plan].map((plan, index) => (
              <Card key={plan.name} className={index === 1 ? "border-ember/40" : ""}>
                <div className="flex items-center justify-between">
                  <h3 className="text-lg">{plan.name}</h3>
                  <Badge tone={index === 0 ? "outline" : "ember"}>
                    {plan.items.length} items
                  </Badge>
                </div>
                <div className="mt-3 grid grid-cols-2 gap-2">
                  <Stat label="Group fit" value={plan.average_group_fit ?? "—"} tone="jade" />
                  <Stat label="Min fit" value={plan.minimum_member_fit ?? "—"} />
                  <Stat label="Cost" value={formatMoney(plan.total_cost, currency)} />
                  <Stat label="Travel" value={`${plan.total_travel_minutes} min`} />
                </div>
                <ul className="mt-3 space-y-1 text-[12.5px] text-muted">
                  {plan.items.map((item) => (
                    <li key={item.activity_id} className="flex justify-between gap-2">
                      <span className="truncate">{item.name}</span>
                      <span className="shrink-0 font-mono text-[10px] text-faint">
                        {formatMoney(item.cost, currency)} · {item.travel_minutes}m travel
                      </span>
                    </li>
                  ))}
                  {plan.items.length === 0 ? <li>No activity on this day.</li> : null}
                </ul>
              </Card>
            ))}
          </div>

          <Card className="space-y-3">
            <h3 className="text-lg">Trade-offs</h3>
            <ul className="space-y-1.5 text-[13px] leading-5 text-muted">
              {comparison.trade_offs.map((tradeoff) => (
                <li key={tradeoff}>· {tradeoff}</li>
              ))}
            </ul>
            <div className="flex flex-wrap gap-2 border-t border-line pt-3">
              <Badge tone="jade">+{comparison.diff.added.length} added</Badge>
              <Badge tone="rose">−{comparison.diff.removed.length} removed</Badge>
              <Badge tone="outline">{comparison.diff.kept.length} kept</Badge>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button loading={adopt.isPending} onClick={() => adopt.mutate()}>
                <Check size={14} /> Propose this alternative
              </Button>
              <span className="self-center text-[12px] text-faint">{comparison.disclosure}</span>
            </div>
          </Card>
        </div>
      ) : null}

      <section className="space-y-3">
        <SectionTitle
          title="Fair Trade"
          hint="Two competing options, one fair compromise. The trade-off is stated, not hidden."
        />
        <div className="grid gap-3 md:grid-cols-2">
          {[
            { title: "Option A", list: sideA, set: setSideA },
            { title: "Option B", list: sideB, set: setSideB },
          ].map(({ title, list, set }) => (
            <Card key={title} className="space-y-2">
              <p className="text-sm font-medium text-ink">{title}</p>
              <div className="flex flex-wrap gap-1.5">
                {list.map((id) => (
                  <span
                    key={id}
                    className="inline-flex items-center gap-1 rounded-full border border-line bg-raised px-2.5 py-0.5 text-[12px]"
                  >
                    {byId.get(id)?.name || "Activity"}
                    <button
                      type="button"
                      onClick={() => set(list.filter((entry) => entry !== id))}
                      aria-label={`Remove ${byId.get(id)?.name || "activity"} from ${title}`}
                    >
                      <X size={11} />
                    </button>
                  </span>
                ))}
                {list.length === 0 ? <span className="text-[12px] text-faint">Pick from the catalog below.</span> : null}
              </div>
              <div className="flex flex-wrap gap-1">
                {catalog.slice(0, 6).map((entry) => (
                  <button
                    key={entry.activity.id}
                    onClick={() => set([...new Set([...list, entry.activity.id])])}
                    className="inline-flex items-center gap-1 rounded-full border border-line bg-surface px-2 py-0.5 text-[10.5px] text-muted hover:border-ember/40 hover:text-ink"
                  >
                    <Plus size={10} /> {entry.activity.name}
                  </button>
                ))}
              </div>
            </Card>
          ))}
        </div>
        <Button
          variant="secondary"
          loading={negotiate.isPending}
          disabled={sideA.length === 0 || sideB.length === 0}
          onClick={() => negotiate.mutate()}
        >
          <Scale size={14} /> Find the fair compromise
        </Button>

        {negotiation ? (
          negotiation.status === "compromise_ready" && negotiation.compromise ? (
            <Card className="space-y-2 border-jade/30">
              <h3 className="text-lg">Compromise: {negotiation.compromise.name}</h3>
              <div className="flex flex-wrap gap-3 text-[12.5px] text-muted">
                <span>Min fit {negotiation.compromise.minimum_fit}/100</span>
                <span>Avg fit {negotiation.compromise.average_fit}/100</span>
                {negotiation.alternative ? (
                  <span>
                    vs {negotiation.alternative.name} at {negotiation.alternative.minimum_fit}/100
                  </span>
                ) : null}
              </div>
              {negotiation.who_benefits ? (
                <p className="text-[12.5px] leading-5 text-muted">{negotiation.who_benefits}</p>
              ) : null}
              {negotiation.who_compromises ? (
                <p className="text-[12.5px] leading-5 text-muted">{negotiation.who_compromises}</p>
              ) : null}
              <ul className="space-y-1 text-[12px] text-muted">
                {(negotiation.trade_offs || []).map((tradeoff) => (
                  <li key={tradeoff}>· {tradeoff}</li>
                ))}
              </ul>
              <p className="text-[12px] text-faint">{negotiation.disclosure}</p>
            </Card>
          ) : (
            <Card className="border-ember/30">
              <p className="text-sm text-ink">{negotiation.message || "Negotiation needs more options."}</p>
            </Card>
          )
        ) : null}
      </section>

      <FlowNote icon={<GitCompare size={15} />}>
        Comparisons and compromises are read-only analytics. Adopting an alternative opens a proposal
        and requires group approval.
      </FlowNote>
    </div>
  );
}
