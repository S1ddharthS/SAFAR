"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Brain,
  Check,
  ChevronDown,
  Compass,
  Gauge,
  Lightbulb,
  RefreshCw,
  ShieldAlert,
  Sparkles,
  Truck,
  Wand2,
} from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useId, useState } from "react";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  FlowNote,
  Input,
  LinkButton,
  Modal,
  PageHeader,
  PageSkeleton,
  Progress,
  ScoreBar,
  SectionTitle,
  Select,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useEngine, useTrip } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { EngineBatch, RecommendationItem } from "@/lib/types";
import { cn, formatMoney, titleCase, todayIso } from "@/lib/utils";

const MODES = [
  {
    id: "everyone_wins",
    label: "Everyone Wins",
    intent: "Maximise suitability for the whole group while protecting the least-served member.",
  },
  {
    id: "your_turn",
    label: "Your Turn",
    intent: "Weight the choice toward members the current plan represents least.",
  },
  {
    id: "surprise_us",
    label: "Surprise Us",
    intent: "Prefer unfamiliar but relevant experiences that still satisfy every hard constraint.",
  },
];

const SENTIMENTS = [
  { value: "loved", label: "Loved it" },
  { value: "would_return", label: "Would return" },
  { value: "okay", label: "It's okay" },
  { value: "not_for_me", label: "Not for me" },
  { value: "too_expensive", label: "Too expensive" },
  { value: "too_far", label: "Too far" },
];

function questionKey(tripId: string, forDate: string, question: string) {
  let hash = 0;
  for (let index = 0; index < question.length; index += 1) {
    hash = (hash * 31 + question.charCodeAt(index)) | 0;
  }
  return `${tripId}:${forDate}:${hash}`;
}

export default function EnginePage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const [mode, setMode] = useState("everyone_wins");
  const [forDate, setForDate] = useState(todayIso());
  const [limit, setLimit] = useState(6);
  const engine = useEngine(tripId, mode);
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);
  const [proposing, setProposing] = useState<RecommendationItem | null>(null);
  const [proposalDraft, setProposalDraft] = useState({ day: "", start_time: "09:00" });
  const [consent, setConsent] = useState(true);
  const [dismissedQuestions, setDismissedQuestions] = useState<string[]>([]);

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(`safar-engine-questions:${tripId}`);
      setDismissedQuestions(raw ? JSON.parse(raw) : []);
    } catch {
      setDismissedQuestions([]);
    }
  }, [tripId]);

  const generate = useMutation({
    mutationFn: () =>
      api<EngineBatch>(`/api/trips/${tripId}/engine/recommend`, {
        method: "POST",
        body: { mode, for_date: forDate, limit },
      }),
    onSuccess: () => {
      push("Options generated", "Compare, give feedback, or propose one for the group.", "success");
      queryClient.invalidateQueries({ queryKey: ["engine", tripId] });
    },
    onError: (error) => push("Engine could not generate", (error as Error).message, "error"),
  });

  const feedback = useMutation({
    mutationFn: ({ recId, sentiment }: { recId: string; sentiment: string }) =>
      api<{ note: string }>(`/api/trips/${tripId}/recommendations/${recId}/feedback`, {
        method: "POST",
        body: { sentiment, consented: consent },
      }),
    onSuccess: (data) => {
      push("Feedback saved", data.note, "success");
      queryClient.invalidateQueries({ queryKey: ["engine", tripId] });
    },
    onError: (error) => push("Could not save feedback", (error as Error).message, "error"),
  });

  const propose = useMutation({
    mutationFn: ({ recId, day, start_time }: { recId: string; day: string; start_time: string }) =>
      api(`/api/trips/${tripId}/recommendations/${recId}/propose`, {
        method: "POST",
        body: { day, start_time },
      }),
    onSuccess: () => {
      push("Proposal opened", "Nothing is confirmed until the group approves it.", "success");
      setProposing(null);
      queryClient.invalidateQueries({ queryKey: ["proposals", tripId] });
      queryClient.invalidateQueries({ queryKey: ["engine", tripId] });
    },
    onError: (error) => push("Could not propose", (error as Error).message, "error"),
  });

  if (trip.isLoading) return <PageSkeleton />;
  if (trip.error || !trip.data) {
    return <ErrorState error={trip.error || new Error("Trip not found")} retry={() => trip.refetch()} />;
  }

  const batch = engine.data;
  const currency = trip.data.currency;
  const activeMode = MODES.find((entry) => entry.id === mode);
  const clarifyingQuestion = batch?.meta?.clarifying_question || null;
  const currentQuestionKey = clarifyingQuestion
    ? questionKey(tripId, String(batch?.for_date || ""), clarifyingQuestion)
    : null;
  const showQuestion = Boolean(
    currentQuestionKey && !dismissedQuestions.includes(currentQuestionKey),
  );

  function dismissQuestion() {
    if (!currentQuestionKey) return;
    const next = Array.from(new Set([...dismissedQuestions, currentQuestionKey]));
    setDismissedQuestions(next);
    try {
      window.localStorage.setItem(`safar-engine-questions:${tripId}`, JSON.stringify(next));
    } catch {
      // Private browsing can block storage; the dismissal still applies this session.
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        as="h2"
        size="md"
        eyebrow={`Group Experience Engine · ${batch?.model_version?.replace("safar-group-engine-", "v") ?? "v1.5"}`}
        title="Three ways to spend a day"
        description="Every option satisfies each member's hard constraints — budget, accessibility, available time and radius. Private inputs filter results without being exposed."
        actions={
          <>
            <LinkButton href={`/trips/${tripId}/twin`} variant="secondary" size="sm">
              <Compass size={14} /> Trip Twin
            </LinkButton>
            <LinkButton href={`/trips/${tripId}/rescue`} variant="secondary" size="sm">
              <ShieldAlert size={14} /> Trip Rescue
            </LinkButton>
          </>
        }
      />

      <div>
        <div className="grid gap-3 sm:grid-cols-3">
          {MODES.map((entry, index) => {
            const active = entry.id === mode;
            const Icon =
              entry.id === "everyone_wins"
                ? Gauge
                : entry.id === "your_turn"
                  ? Lightbulb
                  : Wand2;
            return (
              <button
                key={entry.id}
                type="button"
                onClick={() => setMode(entry.id)}
                aria-pressed={active}
                className={cn(
                  "group relative overflow-hidden rounded-3xl border p-5 text-left transition-all",
                  active
                    ? "border-ink bg-ink text-paper shadow-lift"
                    : "border-line bg-surface text-ink hover:border-ember/40 hover:shadow-card",
                )}
              >
                <div className="flex items-center justify-between">
                  <span
                    className={cn(
                      "inline-flex h-9 w-9 items-center justify-center rounded-full border",
                      active
                        ? "border-paper/25 bg-paper/10 text-paper"
                        : "border-line bg-raised text-ember",
                    )}
                  >
                    <Icon size={16} strokeWidth={1.8} />
                  </span>
                  <span
                    className={cn(
                      "font-mono text-[11px]",
                      active ? "text-paper/55" : "text-faint",
                    )}
                  >
                    0{index + 1}
                  </span>
                </div>
                <p className="mt-3 text-[15px] font-medium">{entry.label}</p>
                <p
                  className={cn(
                    "mt-1.5 text-[12px] leading-5",
                    active ? "text-paper/70" : "text-muted",
                  )}
                >
                  {entry.intent}
                </p>
                {active ? (
                  <span className="mt-3 inline-flex items-center gap-1 text-[11.5px] text-paper/80">
                    <Check size={12} /> Selected
                  </span>
                ) : null}
              </button>
            );
          })}
        </div>
        <p className="mt-2.5 flex flex-wrap gap-x-5 gap-y-1 px-1 text-[11.5px] text-faint">
          <span>
            <span className="text-ink">Average fit</span> — group mean
          </span>
          <span>
            <span className="text-ink">Minimum fit</span> — the least-served member
          </span>
          <span>
            <span className="text-ink">Fairness spread</span> — the gap between the two
          </span>
        </p>
      </div>

      <Card className="flex flex-col gap-3 sm:flex-row sm:items-end">
        <Field label="For the day of" className="sm:w-44">
          <Input
            type="date"
            value={forDate}
            min={trip.data.start_date.slice(0, 10)}
            max={trip.data.end_date.slice(0, 10)}
            onChange={(event) => setForDate(event.target.value)}
          />
        </Field>
        <Field label="Options" className="sm:w-28">
          <Select value={limit} onChange={(event) => setLimit(Number(event.target.value))}>
            {[3, 4, 6, 8, 10, 12].map((value) => (
              <option key={value} value={value}>
                {value}
              </option>
            ))}
          </Select>
        </Field>
        <div className="sm:ml-auto sm:text-right">
          <p className="mb-1.5 hidden text-[11.5px] text-faint sm:block">
            Mode · {activeMode?.label}
          </p>
          <Button
            loading={generate.isPending}
            onClick={() => generate.mutate()}
            className="w-full sm:w-auto"
          >
            {generate.isPending ? (
              <RefreshCw size={14} className="animate-spin" />
            ) : (
              <Sparkles size={14} />
            )}
            Generate {activeMode?.label || "options"}
          </Button>
        </div>
      </Card>

      {showQuestion && clarifyingQuestion ? (
        <Card className="border-ember/30 bg-ember-soft/40">
          <div className="flex gap-2.5">
            <Lightbulb size={16} className="mt-0.5 shrink-0 text-ember" />
            <div className="min-w-0">
              <p className="text-sm font-medium text-ink">One question could change this</p>
              <p className="mt-1 text-[13px] leading-5 text-muted">{clarifyingQuestion}</p>
              <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1">
                <Link
                  href={`/trips/${tripId}/pulse?date=${String(batch?.for_date || forDate)}`}
                  className="text-[12px] text-ember hover:underline"
                >
                  Answer with Trip Pulse →
                </Link>
                <button
                  onClick={dismissQuestion}
                  className="text-[12px] text-faint hover:text-ink"
                >
                  Not now
                </button>
              </div>
              <p className="mt-1 text-[11.5px] text-faint">
                Your answer is only used for this day's recommendations. Dismissing hides this
                prompt for this day.
              </p>
            </div>
          </div>
        </Card>
      ) : null}

      {engine.isLoading ? (
        <PageSkeleton />
      ) : engine.error ? (
        <ErrorState error={engine.error} retry={() => engine.refetch()} />
      ) : !batch || batch.items.length === 0 ? (
        <EmptyState
          title="No options yet"
          description={
            batch?.message ||
            "Generate a batch and the engine will explain every choice, including what it could not verify."
          }
          icon={<Brain size={24} />}
          action={
            <Button size="sm" loading={generate.isPending} onClick={() => generate.mutate()}>
              <Sparkles size={14} /> Generate options
            </Button>
          }
        />
      ) : (
        <>
          <SectionTitle
            title={`${batch.mode_meta?.label || titleCase(batch.mode)} · ${batch.for_date}`}
            hint={
              batch.meta?.disclosure ||
              "Catalog attributes are curated. Travel times are straight-line estimates."
            }
            action={
              <Badge tone="outline">
                {batch.meta?.eligible_count ?? batch.items.length} eligible ·{" "}
                {batch.meta?.excluded_count ?? 0} excluded
              </Badge>
            }
          />
          <div className="space-y-3">
            {batch.items.map((item) => (
              <RecommendationCard
                key={item.id}
                item={item}
                currency={currency}
                consent={consent}
                onConsent={setConsent}
                feedbackPending={feedback.isPending && feedback.variables?.recId === item.id}
                onFeedback={(sentiment) => feedback.mutate({ recId: item.id, sentiment })}
                onPropose={() => {
                  setProposalDraft({ day: batch.for_date, start_time: "09:00" });
                  setProposing(item);
                }}
              />
            ))}
          </div>

          {batch.meta ? (
            <Card className="space-y-3">
              <h3 className="text-lg">How this was ranked</h3>
              <div className="grid gap-2 sm:grid-cols-2">
                {Object.entries(batch.meta)
                  .filter(
                    ([key, value]) =>
                      [
                        "members_count",
                        "pulse_coverage",
                        "candidate_count",
                        "planned_excluded",
                        "ranking_formula",
                        "target_member",
                      ].includes(key) &&
                      value !== null &&
                      value !== undefined &&
                      value !== "",
                  )
                  .map(([key, value]) => (
                    <div key={key} className="rounded-xl border border-line bg-raised/60 px-3 py-2">
                      <p className="text-[10px] uppercase tracking-editorial text-faint">
                        {titleCase(key)}
                      </p>
                      <p className="mt-0.5 text-[12.5px] text-muted">{String(value)}</p>
                    </div>
                  ))}
              </div>
              {(batch.meta.hard_constraints || []).length ? (
                <p className="text-[12px] leading-5 text-faint">
                  Hard constraints always applied: {(batch.meta.hard_constraints || []).join(", ")}.
                </p>
              ) : null}
              {batch.meta.evaluation ? (
                <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
                  {[
                    {
                      key: "Fairness (Jain)",
                      value: batch.meta.evaluation.fairness.jain_index.toFixed(2),
                      hint: `Least-served member ${batch.meta.evaluation.fairness.least_served_member_mean_fit.toFixed(0)}/100`,
                    },
                    {
                      key: "Satisfaction",
                      value: `${batch.meta.evaluation.satisfaction.mean_average_fit.toFixed(0)}/100`,
                      hint: `Minimum fit ${batch.meta.evaluation.satisfaction.mean_minimum_fit.toFixed(0)}/100`,
                    },
                    {
                      key: "Constraint violations",
                      value: String(batch.meta.evaluation.constraints.violations),
                      hint: `${batch.meta.evaluation.constraints.excluded} excluded before ranking`,
                    },
                    {
                      key: "Diversity",
                      value: `${batch.meta.evaluation.diversity.unique_tags} tags`,
                      hint: `Similarity ${batch.meta.evaluation.diversity.mean_pairwise_similarity.toFixed(2)}`,
                    },
                  ].map((entry) => (
                    <div
                      key={entry.key}
                      className="rounded-xl border border-line bg-raised/60 px-3 py-2"
                    >
                      <p className="text-[10px] uppercase tracking-editorial text-faint">
                        {entry.key}
                      </p>
                      <p className="num mt-0.5 font-mono text-[13px] text-ink">{entry.value}</p>
                      <p className="text-[10.5px] leading-4 text-faint">{entry.hint}</p>
                    </div>
                  ))}
                </div>
              ) : null}
              {batch.meta.feedback_learning ? (
                <p className="text-[11.5px] leading-5 text-faint">
                  {batch.meta.feedback_learning.enabled
                    ? `Consented feedback used: ${batch.meta.feedback_learning.applied_activities} activit${batch.meta.feedback_learning.applied_activities === 1 ? "y" : "ies"}, capped at ±${batch.meta.feedback_learning.max_adjustment.toFixed(0)} points. Individual sentiments are never shown.`
                    : "Feedback learning is off for groups smaller than three, so one person's taste cannot be presented as group intelligence."}
                </p>
              ) : null}
              {batch.meta.protected_time?.protected_items?.length ? (
                <div className="rounded-xl border border-jade/30 bg-jade-soft/30 px-3 py-2">
                  <p className="text-[12px] font-medium text-jade">Protected time kept</p>
                  <p className="mt-0.5 text-[12.5px] leading-5 text-muted">
                    {batch.meta.protected_time.protected_items
                      .map((entry) => `${entry.start}–${entry.end} ${entry.title}`)
                      .join(" · ")}
                  </p>
                  <p className="mt-1 text-[11.5px] text-faint">
                    Suggestions only use the free windows left in the day
                    {batch.meta.protected_time.free_windows.length
                      ? `: ${batch.meta.protected_time.free_windows
                          .map((entry) => `${entry.start}–${entry.end}`)
                          .join(", ")}`
                      : "."}
                  </p>
                </div>
              ) : null}
              {batch.meta.exclusion_reasons && Object.keys(batch.meta.exclusion_reasons).length ? (
                <div className="flex flex-wrap gap-1.5">
                  {Object.entries(batch.meta.exclusion_reasons).map(([reason, count]) => (
                    <Badge key={reason} tone="neutral">
                      {reason}: {count}
                    </Badge>
                  ))}
                </div>
              ) : null}
            </Card>
          ) : null}
        </>
      )}

      <FlowNote icon={<Compass size={15} />}>
        The engine recommends; the group decides. Proposing an option opens a vote — the confirmed
        itinerary changes only after an owner or admin approves.
      </FlowNote>

      <Modal
        open={Boolean(proposing)}
        onClose={() => setProposing(null)}
        title={proposing ? `Propose ${proposing.activity?.name}` : "Propose an option"}
      >
        {proposing ? (
          <div className="space-y-3">
            <p className="text-[13px] leading-5 text-muted">
              This creates a proposal for the group. Voting and approval happen on the Decide page.
            </p>
            <div className="grid gap-3 sm:grid-cols-2">
              <Field label="Day">
                <Input
                  type="date"
                  value={proposalDraft.day}
                  min={trip.data.start_date.slice(0, 10)}
                  max={trip.data.end_date.slice(0, 10)}
                  onChange={(event) =>
                    setProposalDraft({ ...proposalDraft, day: event.target.value })
                  }
                />
              </Field>
              <Field label="Start time">
                <Input
                  type="time"
                  value={proposalDraft.start_time}
                  onChange={(event) =>
                    setProposalDraft({ ...proposalDraft, start_time: event.target.value })
                  }
                />
              </Field>
            </div>
            <Button
              className="w-full"
              loading={propose.isPending}
              onClick={() =>
                propose.mutate({
                  recId: proposing.id,
                  day: proposalDraft.day,
                  start_time: proposalDraft.start_time,
                })
              }
            >
              Open proposal
            </Button>
          </div>
        ) : null}
      </Modal>
    </div>
  );
}

function RecommendationCard({
  item,
  currency,
  consent,
  onConsent,
  onFeedback,
  onPropose,
  feedbackPending,
}: {
  item: RecommendationItem;
  currency: string;
  consent: boolean;
  onConsent: (value: boolean) => void;
  onFeedback: (sentiment: string) => void;
  onPropose: () => void;
  feedbackPending?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [feedbackOpen, setFeedbackOpen] = useState(false);
  const disclosureId = useId();
  const activity = item.activity;
  const explanation = item.explanation;

  return (
    <Card className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex min-w-0 gap-4">
          <div className="hidden shrink-0 pt-0.5 sm:block">
            <p className="font-display text-[2rem] leading-none text-ink">
              {String(item.rank).padStart(2, "0")}
            </p>
            <p className="mt-1 text-[10px] uppercase tracking-editorial text-faint">Rank</p>
          </div>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <Badge tone="ember" className="sm:hidden">
                #{item.rank}
              </Badge>
              {item.rank === 1 ? <Badge tone="jade">Top fit</Badge> : null}
              <span className="num font-mono text-[12px] text-faint">
                score {item.score.toFixed(0)}
              </span>
              {activity?.indoor ? <Badge tone="outline">Indoor</Badge> : null}
              {activity?.fragile ? <Badge tone="rose">Fragile place</Badge> : null}
              {item.my_feedback ? (
                <Badge tone="jade">{titleCase(item.my_feedback)}</Badge>
              ) : null}
            </div>
            <h3 className="mt-1.5 text-xl leading-snug">
              {activity?.name || "Catalog activity"}
            </h3>
            <p className="mt-1 max-w-prose text-[13px] leading-6 text-muted">
              {explanation?.summary || activity?.description}
            </p>
            <p className="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-[12px] text-faint">
              <span className="num">
                {formatMoney(explanation?.estimated_cost ?? activity?.price_estimate, currency)}
              </span>
              <span>{explanation?.duration_minutes ?? activity?.duration_minutes} min</span>
              {explanation ? (
                <>
                  <span className="inline-flex items-center gap-1">
                    <Truck size={11} /> {explanation.travel_minutes} min travel ·{" "}
                    {explanation.distance_km.toFixed(1)} km
                  </span>
                  <span>Freshness: {explanation.data_freshness?.label}</span>
                </>
              ) : null}
            </p>
          </div>
        </div>
        <div className="flex shrink-0 gap-2">
          <Button size="sm" onClick={onPropose}>
            Propose
          </Button>
        </div>
      </div>

      {item.respect?.fragile ? (
        <div className="rounded-2xl border border-rose/30 bg-rose/5 px-3.5 py-2.5 text-[12.5px] leading-5">
          <p className="font-medium text-ink">Respect guidance for this place</p>
          <p className="mt-0.5 text-muted">
            {item.respect.status === "guidance_recorded" && item.respect.guidance
              ? item.respect.guidance
              : "No respect guidance has been recorded for this fragile place yet. Check locally before visiting and keep to marked paths."}
          </p>
        </div>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-3">
        <ScoreBar label="Average fit" value={item.average_fit} />
        <ScoreBar label="Minimum fit" value={item.minimum_fit} tone="jade" />
        <ScoreBar
          label="Fairness spread"
          value={item.fairness_spread}
          max={100}
          tone="ink"
          suffix={`${item.fairness_spread.toFixed(0)} spread`}
        />
      </div>

      <button
        type="button"
        onClick={() => setOpen((value) => !value)}
        aria-expanded={open}
        aria-controls={disclosureId}
        className="flex w-full items-center justify-between border-t border-line pt-3 text-[12px] text-muted transition-colors hover:text-ink"
      >
        <span>Why this was chosen · what it may not suit</span>
        <ChevronDown
          size={14}
          className={cn("transition-transform", open ? "rotate-180" : "")}
        />
      </button>

      {open && explanation ? (
        <div id={disclosureId} className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <p className="text-[12px] uppercase tracking-editorial text-faint">Why selected</p>
              <ul className="mt-1.5 space-y-1 text-[12.5px] leading-5 text-muted">
                {(explanation.why_selected || []).map((reason) => (
                  <li key={reason}>· {reason}</li>
                ))}
              </ul>
              {explanation.selection &&
              (explanation.selection.diversity_penalty ||
                explanation.selection.feedback_adjustment) ? (
                <p className="mt-2 text-[11px] leading-5 text-faint">
                  {explanation.selection.feedback_adjustment
                    ? `Feedback nudge ${explanation.selection.feedback_adjustment > 0 ? "+" : ""}${explanation.selection.feedback_adjustment.toFixed(1)} · `
                    : null}
                  {explanation.selection.diversity_penalty
                    ? `Diversity demotion −${explanation.selection.diversity_penalty.toFixed(1)} · `
                    : null}
                  {explanation.selection.note}
                </p>
              ) : null}
            </div>
            <div>
              <p className="text-[12px] uppercase tracking-editorial text-faint">Suits</p>
              <ul className="mt-1.5 space-y-1 text-[12.5px] leading-5 text-muted">
                {(explanation.suits || []).map((reason) => (
                  <li key={reason}>· {reason}</li>
                ))}
              </ul>
            </div>
            <div>
              <p className="text-[12px] uppercase tracking-editorial text-faint">May not prefer</p>
              <ul className="mt-1.5 space-y-1 text-[12.5px] leading-5 text-muted">
                {(explanation.may_not_prefer || []).map((reason) => (
                  <li key={reason}>· {reason}</li>
                ))}
              </ul>
            </div>
            <div>
              <p className="text-[12px] uppercase tracking-editorial text-faint">Unknowns</p>
              <ul className="mt-1.5 space-y-1 text-[12.5px] leading-5 text-muted">
                {(explanation.uncertainties || []).map((reason) => (
                  <li key={reason}>· {reason}</li>
                ))}
              </ul>
            </div>
          </div>

          <div className="space-y-1.5">
            <p className="text-[12px] uppercase tracking-editorial text-faint">Constraints checked</p>
            {(explanation.constraints_checked || []).map((constraint) => (
              <div
                key={constraint.constraint}
                className="flex items-start gap-2 rounded-xl border border-line bg-raised/60 px-3 py-2 text-[12px]"
              >
                <Badge tone={constraint.status === "satisfied" ? "jade" : "ember"}>
                  {constraint.constraint}
                </Badge>
                <span className="text-muted">{constraint.detail}</span>
              </div>
            ))}
          </div>

          <div>
            <p className="text-[12px] uppercase tracking-editorial text-faint">Anonymous member fits</p>
            <div className="mt-1.5 flex gap-1.5">
              {(explanation.member_fits_anonymous || []).map((fit, index) => (
                <div key={index} className="flex-1">
                  <Progress value={fit} tone={fit >= 70 ? "jade" : "ember"} />
                  <p className="mt-1 text-center font-mono text-[10px] text-faint">{fit.toFixed(0)}</p>
                </div>
              ))}
            </div>
            <p className="mt-1 text-[10.5px] text-faint">
              Anonymous by design — identities are never attached to fits.
              {explanation.target_member ? ` Target this round: ${explanation.target_member}.` : ""}
            </p>
          </div>
        </div>
      ) : null}

      <div className="border-t border-line pt-3">
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-[12px] uppercase tracking-editorial text-faint">Was this a fit?</span>
          <div role="group" aria-label="Your feedback" className="flex flex-wrap gap-1.5">
            {SENTIMENTS.map((sentiment) => (
              <button
                key={sentiment.value}
                type="button"
                aria-pressed={item.my_feedback === sentiment.value}
                disabled={feedbackPending}
                onClick={() => onFeedback(sentiment.value)}
                className={cn(
                  "rounded-full border px-2.5 py-1 text-[12px] transition-colors disabled:opacity-60",
                  item.my_feedback === sentiment.value
                    ? "border-ink bg-ink text-paper"
                    : "border-line bg-surface text-muted hover:border-ink/30 hover:text-ink",
                )}
              >
                {sentiment.label}
              </button>
            ))}
          </div>
          <button
            type="button"
            onClick={() => setFeedbackOpen((value) => !value)}
            aria-expanded={feedbackOpen}
            aria-controls={`${disclosureId}-consent`}
            className="ml-auto text-[12px] text-ember hover:underline"
          >
            Consent
          </button>
        </div>
        {feedbackOpen ? (
          <label
            id={`${disclosureId}-consent`}
            className="mt-2 flex items-start gap-2 rounded-xl border border-line bg-raised/60 p-2.5 text-[12px] leading-5 text-muted"
          >
            <input
              type="checkbox"
              checked={consent}
              onChange={(event) => onConsent(event.target.checked)}
              className="mt-0.5 accent-ember"
            />
            <span>
              Allow this feedback to shape my Journey DNA. When off, the sentiment is saved privately
              but my DNA does not change.
            </span>
          </label>
        ) : null}
      </div>
    </Card>
  );
}
