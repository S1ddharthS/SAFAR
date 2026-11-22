"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  AlertOctagon,
  CloudRain,
  Clock,
  DoorClosed,
  Gauge,
  Lock,
  Route,
  ShieldAlert,
  Wallet,
} from "lucide-react";
import { useParams } from "next/navigation";
import { useState } from "react";

import {
  Badge,
  Button,
  Card,
  ErrorState,
  Field,
  FlowNote,
  Input,
  PageSkeleton,
  SectionTitle,
  Select,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useItinerary, useTrip } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { RescueAnalysis } from "@/lib/types";
import { cn, formatMoney, formatTime, titleCase } from "@/lib/utils";

const KINDS = [
  { value: "rain", label: "Rain", icon: CloudRain },
  { value: "closure", label: "Closure", icon: DoorClosed },
  { value: "traffic", label: "Traffic / delay", icon: Route },
  { value: "fatigue", label: "Fatigue", icon: Gauge },
  { value: "budget", label: "Budget shock", icon: Wallet },
  { value: "time", label: "Lost time", icon: Clock },
];

export default function RescuePage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const itinerary = useItinerary(tripId);
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);
  const [kind, setKind] = useState("rain");
  const [itemId, setItemId] = useState("");
  const [extraMinutes, setExtraMinutes] = useState(45);
  const [note, setNote] = useState("");
  const [analysis, setAnalysis] = useState<RescueAnalysis | null>(null);
  const [choices, setChoices] = useState<Record<string, string>>({});

  const analyze = useMutation({
    mutationFn: () =>
      api<RescueAnalysis>(`/api/trips/${tripId}/rescue/analyze`, {
        method: "POST",
        body: {
          kind,
          item_id: itemId || null,
          extra_minutes: extraMinutes,
          note: note || null,
        },
      }),
    onSuccess: (data) => {
      setAnalysis(data);
      const defaults: Record<string, string> = {};
      for (const proposal of data.proposals || []) {
        const pick =
          proposal.options.find(
            (option) => option.activity_id === proposal.recommended_activity_id,
          ) || proposal.options.find((option) => option.activity_id);
        if (pick?.activity_id) defaults[proposal.item_id] = pick.activity_id;
      }
      setChoices(defaults);
      if (!data.proposals?.length) {
        push("No replacements found", data.message || "Nothing can be safely substituted right now.", "info");
      }
    },
    onError: (error) => push("Could not analyse", (error as Error).message, "error"),
  });

  const propose = useMutation({
    mutationFn: () => {
      const items = (analysis?.proposals || [])
        .filter((proposal) => choices[proposal.item_id])
        .map((proposal) => {
          const item = itinerary.data?.items.find((entry) => entry.id === proposal.item_id);
          return {
            item_id: proposal.item_id,
            activity_id: choices[proposal.item_id],
            day: String(item?.day || "").slice(0, 10),
            start_time: formatTime(item?.start_time) || "09:00",
          };
        });
      return api(`/api/trips/${tripId}/rescue/propose`, {
        method: "POST",
        body: {
          kind,
          item_id: itemId || null,
          extra_minutes: extraMinutes,
          note: note || null,
          items,
        },
      });
    },
    onSuccess: () => {
      push("Rescue proposal opened", "The plan changes only after the group approves.", "success");
      queryClient.invalidateQueries({ queryKey: ["proposals", tripId] });
    },
    onError: (error) => push("Could not propose", (error as Error).message, "error"),
  });

  if (trip.isLoading || itinerary.isLoading) return <PageSkeleton />;
  if (trip.error || !trip.data) {
    return <ErrorState error={trip.error || new Error("Trip not found")} retry={() => trip.refetch()} />;
  }

  const items = itinerary.data?.items ?? [];
  const currency = trip.data.currency;
  const selectedCount = Object.values(choices).filter(Boolean).length;

  return (
    <div className="space-y-6">
      <div>
        <p className="eyebrow">Trip Rescue · disruption recovery</p>
        <h2 className="mt-1 text-2xl">Something changed. Here's the plan.</h2>
        <p className="mt-1 max-w-prose text-sm text-muted">
          Describe the disruption and the engine finds the safest substitutions that still respect
          every hard constraint. Nothing is applied until the group approves.
        </p>
      </div>

      <Card className="space-y-4">
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
          {KINDS.map(({ value, label, icon: Icon }) => (
            <button
              key={value}
              type="button"
              aria-pressed={kind === value}
              onClick={() => setKind(value)}
              className={cn(
                "flex flex-col items-center gap-1.5 rounded-2xl border px-2 py-3 text-[12px] transition-colors",
                kind === value
                  ? "border-ink bg-ink text-paper"
                  : "border-line bg-surface text-muted hover:border-ember/40 hover:text-ink",
              )}
            >
              <Icon size={17} />
              {label}
            </button>
          ))}
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Affected item (optional)" hint="Leave empty to analyse the whole day.">
            <Select value={itemId} onChange={(event) => setItemId(event.target.value)}>
              <option value="">Whole plan</option>
              {items.map((item) => (
                <option key={item.id} value={item.id}>
                  {String(item.day).slice(0, 10)} · {item.title}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Extra delay (minutes)" hint="Used for delays and lost time.">
            <Input
              type="number"
              min="0"
              max="600"
              step="5"
              value={extraMinutes}
              onChange={(event) => setExtraMinutes(Number(event.target.value))}
            />
          </Field>
        </div>
        <Field label="What happened? (optional)">
          <Textarea
            value={note}
            onChange={(event) => setNote(event.target.value)}
            placeholder="Storm rolled in; the museum closed early…"
            className="min-h-20"
          />
        </Field>
        <Button loading={analyze.isPending} onClick={() => analyze.mutate()}>
          <ShieldAlert size={14} /> Analyse recovery options
        </Button>
      </Card>

      {analysis ? (
        <div className="space-y-4">
          <Card className="space-y-2 border-ember/30">
            <div className="flex flex-wrap items-center gap-2">
              <Badge tone="ember">
                <AlertOctagon size={11} /> {analysis.disruption?.label || titleCase(kind)}
              </Badge>
              <Badge tone="outline">{analysis.affected?.length || 0} affected item(s)</Badge>
              {analysis.consequences ? (
                <Badge tone={analysis.consequences.cost_delta > 0 ? "rose" : "jade"}>
                  {analysis.consequences.cost_delta >= 0 ? "+" : ""}
                  {formatMoney(analysis.consequences.cost_delta, currency)} cost
                </Badge>
              ) : null}
            </div>
            {analysis.disruption?.note ? (
              <p className="text-[13px] text-muted">{analysis.disruption.note}</p>
            ) : null}
            {analysis.message ? (
              <p className="text-[13px] text-muted">{analysis.message}</p>
            ) : null}
          </Card>

          {(analysis.protected || []).length ? (
            <Card className="space-y-2 border-jade/30">
              <div className="flex items-center gap-2">
                <Lock size={14} className="text-jade" />
                <h3 className="text-sm font-medium text-ink">Protected time left untouched</h3>
              </div>
              <p className="text-[12.5px] text-muted">
                Trip Rescue will not replace or move these reserved blocks.
              </p>
              <div className="flex flex-wrap gap-2">
                {(analysis.protected || []).map((entry) => (
                  <span
                    key={entry.item_id}
                    className="rounded-xl border border-line bg-raised/60 px-3 py-1.5 text-[12.5px]"
                  >
                    <span className="font-mono text-[12px] text-faint">
                      {formatTime(entry.start_time)}
                    </span>{" "}
                    <span className="text-ink">{entry.title}</span>
                  </span>
                ))}
              </div>
            </Card>
          ) : null}

          {(analysis.affected || []).length ? (
            <section className="space-y-2">
              <SectionTitle title="What is affected" hint="This is the domino: what breaks and why." />
              {analysis.affected.map((entry) => (
                <div
                  key={entry.item_id}
                  className="rounded-2xl border border-line bg-surface px-4 py-3"
                >
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-sm text-ink">{entry.title}</p>
                    <span className="font-mono text-[12px] text-faint">{entry.start_time}</span>
                  </div>
                  <p className="mt-0.5 text-[12px] text-muted">{entry.reason}</p>
                </div>
              ))}
            </section>
          ) : null}

          {(analysis.proposals || []).length ? (
            <section className="space-y-3">
              <SectionTitle
                title="Suggested replacements"
                hint="Pick a replacement for each item, then open a single rescue proposal."
                action={
                  <Button
                    size="sm"
                    loading={propose.isPending}
                    disabled={selectedCount === 0}
                    onClick={() => propose.mutate()}
                  >
                    Propose {selectedCount} change(s)
                  </Button>
                }
              />
              {analysis.proposals.map((proposal) => {
                const replacements = proposal.options.filter((option) => option.activity_id);
                return (
                  <Card key={proposal.item_id} className="space-y-3">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div>
                        <p className="text-[12px] uppercase tracking-editorial text-faint">
                          Replacing
                        </p>
                        <p className="text-sm text-ink">
                          {proposal.original_activity?.name || proposal.title}
                        </p>
                        <p className="mt-0.5 text-[12px] text-muted">{proposal.reason}</p>
                      </div>
                      <span className="font-mono text-[12px] text-faint">
                        {proposal.day} · {formatTime(proposal.start_time)}
                      </span>
                    </div>
                    <div className="grid gap-2 sm:grid-cols-2">
                      {replacements.map((option) => {
                        const selected = choices[proposal.item_id] === option.activity_id;
                        return (
                          <button
                            key={option.activity_id}
                            type="button"
                            aria-pressed={selected}
                            onClick={() =>
                              setChoices((current) => ({
                                ...current,
                                [proposal.item_id]: option.activity_id as string,
                              }))
                            }
                            className={cn(
                              "rounded-2xl border px-3 py-2.5 text-left transition-colors",
                              selected
                                ? "border-ink bg-ink text-paper"
                                : "border-line bg-surface hover:border-ember/40",
                            )}
                          >
                            <div className="flex items-center justify-between gap-2">
                              <p className="text-[13px] font-medium">{option.name}</p>
                              <Badge tone={option.source === "shadowplan" ? "jade" : "outline"}>
                                {option.source === "shadowplan" ? "Backup" : "Engine"}
                              </Badge>
                            </div>
                            <p
                              className={cn(
                                "mt-0.5 text-[12px]",
                                selected ? "text-paper/70" : "text-muted",
                              )}
                            >
                              {formatMoney(option.price ?? 0, currency)} ·{" "}
                              {option.duration ?? "—"} min
                              {option.score != null ? ` · score ${option.score.toFixed(0)}` : ""}
                            </p>
                            {option.note ? (
                              <p
                                className={cn(
                                  "mt-0.5 text-[11.5px] leading-4",
                                  selected ? "text-paper/60" : "text-faint",
                                )}
                              >
                                {option.note}
                              </p>
                            ) : null}
                          </button>
                        );
                      })}
                    </div>
                    {!replacements.length ? (
                      <p className="text-[12.5px] text-rose">
                        No safe replacement fits this slot without touching protected time or the
                        next item.
                      </p>
                    ) : null}
                  </Card>
                );
              })}
            </section>
          ) : null}

          {analysis.consequences ? (
            <Card className="space-y-2">
              <h3 className="text-lg">Consequences if applied</h3>
              <div className="flex flex-wrap gap-x-4 gap-y-1 text-[12.5px] text-muted">
                <span>
                  Cost delta {formatMoney(analysis.consequences.cost_delta, currency)}
                </span>
                <span>
                  Duration delta {analysis.consequences.duration_delta_minutes} min
                </span>
                <span>{analysis.consequences.time_saved_or_lost}</span>
              </div>
              {analysis.consequences.pact_conflicts?.length ? (
                <p className="text-[12px] text-rose">
                  {analysis.consequences.pact_conflicts.length} Journey Pact conflict(s) must be
                  resolved before approval.
                </p>
              ) : null}
            </Card>
          ) : null}

          {analysis.disclosure ? (
            <p className="text-[12px] text-faint">{analysis.disclosure}</p>
          ) : null}
        </div>
      ) : null}

      <FlowNote icon={<ShieldAlert size={15} />}>
        Trip Rescue never touches the confirmed plan directly. Every replacement becomes a proposal
        for the group to approve.
      </FlowNote>
    </div>
  );
}
