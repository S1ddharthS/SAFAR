"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  BadgeCheck,
  CircleHelp,
  Clock3,
  MapPin,
  Send,
  ShieldCheck,
  Sparkles,
  ThumbsUp,
  TriangleAlert,
} from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";

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
  Progress,
  SectionTitle,
  Select,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useMe, usePlaceDetail, useTrip } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { ExpectationResult, PlaceReportCategory } from "@/lib/types";
import { cn, errorMessage, formatDate, formatMoney, todayIso } from "@/lib/utils";

const REPORT_CATEGORIES = [
  { value: "crowd", label: "Crowd level" },
  { value: "queue", label: "Queue / wait" },
  { value: "closure", label: "Open / closed" },
  { value: "accessibility", label: "Accessibility" },
  { value: "price", label: "Price" },
  { value: "parking", label: "Parking" },
  { value: "road", label: "Road / path" },
  { value: "quality", label: "Quality" },
];

const SOURCE_TYPES = [
  { value: "community", label: "Community observation" },
  { value: "estimated", label: "My estimate" },
  { value: "unknown", label: "Uncertain source" },
];

const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

const STATUS_TONE: Record<string, "neutral" | "ember" | "jade" | "rose" | "outline"> = {
  VERIFIED: "jade",
  REPORTED: "ember",
  ESTIMATED: "neutral",
  UNKNOWN: "outline",
};

export default function PlaceDetailPage() {
  const params = useParams<{ tripId: string; activityId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const activityId = typeof params?.activityId === "string" ? params.activityId : "";
  const trip = useTrip(tripId);
  const me = useMe();
  const detail = usePlaceDetail(tripId, activityId);
  const queryClient = useQueryClient();
  const { push } = useToasts();

  const [category, setCategory] = useState("crowd");
  const [level, setLevel] = useState("moderate");
  const [minutes, setMinutes] = useState("20");
  const [closed, setClosed] = useState(false);
  const [amount, setAmount] = useState("");
  const [detailText, setDetailText] = useState("");
  const [note, setNote] = useState("");
  const [sourceType, setSourceType] = useState("community");
  const [observedAt, setObservedAt] = useState(todayIso());

  const [claim, setClaim] = useState("");
  const [expectation, setExpectation] = useState<ExpectationResult | null>(null);

  const [proposeOpen, setProposeOpen] = useState(false);
  const [proposeDay, setProposeDay] = useState("");
  const [proposeTime, setProposeTime] = useState("10:00");

  const isAdmin = me.data?.user.is_admin === true;

  useEffect(() => {
    if (!proposeDay && trip.data) setProposeDay(trip.data.start_date.slice(0, 10));
  }, [trip.data, proposeDay]);

  const refreshPlace = () => {
    queryClient.invalidateQueries({ queryKey: ["place", tripId, activityId] });
    queryClient.invalidateQueries({ queryKey: ["place-reports", tripId, activityId] });
  };

  const submitReport = useMutation({
    mutationFn: () => {
      const value: Record<string, unknown> = {};
      if (category === "crowd") value.level = level;
      else if (category === "queue") value.minutes = Number(minutes) || 0;
      else if (category === "closure") value.closed = closed;
      else if (category === "price") value.amount = Number(amount) || 0;
      else value.detail = detailText;
      return api(`/api/trips/${tripId}/place-reports`, {
        method: "POST",
        body: {
          activity_id: activityId,
          category,
          value,
          note: note || null,
          observed_at: `${observedAt}T12:00:00`,
          source_type: sourceType,
        },
      });
    },
    onSuccess: () => {
      push("Observation shared", "Community reports are unverified until moderated.", "success");
      setNote("");
      setAmount("");
      setDetailText("");
      refreshPlace();
    },
    onError: (error) => push("Could not save report", errorMessage(error), "error"),
  });

  const markHelpful = useMutation({
    mutationFn: (reportId: string) =>
      api(`/api/trips/${tripId}/place-reports/${reportId}/helpful`, { method: "POST" }),
    onSuccess: () => {
      push("Marked helpful", "Helpful marks do not verify a report.", "info");
      refreshPlace();
    },
    onError: (error) => push("Could not mark", errorMessage(error), "error"),
  });

  const verifyReport = useMutation({
    mutationFn: (reportId: string) =>
      api<{ provenance_note?: string }>(
        `/api/admin/place-reports/${reportId}/verify?verify=true`,
        { method: "POST" },
      ),
    onSuccess: (data) => {
      push(
        "Moderator check recorded",
        data.provenance_note || "It now ranks above unverified community reports.",
        "success",
      );
      refreshPlace();
    },
    onError: (error) => push("Could not verify", errorMessage(error), "error"),
  });

  const runExpectation = useMutation({
    mutationFn: () =>
      api<ExpectationResult>(`/api/trips/${tripId}/places/${activityId}/expectation`, {
        method: "POST",
        body: { claim },
      }),
    onSuccess: (result) => setExpectation(result),
    onError: (error) => push("Check failed", errorMessage(error), "error"),
  });

  const proposeActivity = useMutation({
    mutationFn: () =>
      api(`/api/trips/${tripId}/proposals`, {
        method: "POST",
        body: {
          kind: "add_activity",
          title: `Add ${detail.data?.activity.name ?? "activity"}`,
          summary: "Proposed from the place evidence page. Group decides before it joins the plan.",
          activity_id: activityId,
          day: proposeDay,
          start_time: proposeTime,
        },
      }),
    onSuccess: () => {
      push("Proposal created", "The group can now vote. Confirmed plans never change silently.", "success");
      setProposeOpen(false);
      queryClient.invalidateQueries({ queryKey: ["proposals", tripId] });
      queryClient.invalidateQueries({ queryKey: ["itinerary", tripId] });
    },
    onError: (error) => push("Could not propose", errorMessage(error), "error"),
  });

  const activity = detail.data?.activity;
  const reports = detail.data?.reports;
  const categories = useMemo(
    () => reports?.categories ?? [],
    [reports],
  );

  if (detail.isLoading) return <PageSkeleton />;
  if (detail.error || !detail.data || !activity) {
    return (
      <div className="space-y-4">
        <ErrorState error={detail.error || new Error("Place not found")} retry={() => detail.refetch()} />
        <Link href={`/trips/${tripId}/places`} className="inline-flex items-center gap-1 text-sm text-ember">
          <ArrowLeft size={14} /> Back to catalog
        </Link>
      </div>
    );
  }

  const evidence = detail.data.evidence;
  const access = detail.data.access_chain;
  const crowd = detail.data.crowd_forecast;

  return (
    <div className="space-y-6">
      <Link href={`/trips/${tripId}/places`} className="inline-flex items-center gap-1 text-sm text-ember">
        <ArrowLeft size={14} /> Back to catalog
      </Link>

      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <div className="flex flex-wrap gap-1.5">
            <Badge tone={STATUS_TONE[detail.data.catalog_freshness.label?.toUpperCase()] || "outline"}>
              {detail.data.catalog_freshness.label}
            </Badge>
            {activity.fragile ? <Badge tone="rose">Fragile place</Badge> : null}
            {activity.wheelchair_accessible === true ? <Badge tone="jade">Step-free</Badge> : null}
            {activity.indoor ? <Badge tone="outline">Indoor</Badge> : null}
          </div>
          <h1 className="mt-2 text-balance text-3xl leading-tight">{activity.name}</h1>
          <p className="mt-1 max-w-prose text-sm leading-6 text-muted">{activity.description}</p>
          <p className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-[12px] text-faint">
            <span className="inline-flex items-center gap-1">
              <MapPin size={13} /> {activity.place?.name || activity.destination?.name || "Location recorded"}
            </span>
            <span className="inline-flex items-center gap-1">
              <Clock3 size={13} /> {activity.duration_minutes} min · effort {activity.effort}/5
            </span>
            <span>{formatMoney(activity.price_estimate, activity.currency)}</span>
            {detail.data.catalog_freshness.last_verified_at ? (
              <span>Verified {formatDate(detail.data.catalog_freshness.last_verified_at)}</span>
            ) : null}
          </p>
        </div>
        <div className="flex flex-col gap-2">
          <Button onClick={() => setProposeOpen(true)}>
            <Sparkles size={14} /> Propose to group
          </Button>
          <Badge tone="outline">Estimates only · not live data</Badge>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="space-y-4">
          <SectionTitle title="Evidence passport" hint="What is verified, reported, estimated or unknown" />
          <div className="space-y-2">
            {evidence.sources.length === 0 ? (
              <p className="text-sm text-muted">No catalog sources recorded.</p>
            ) : (
              evidence.sources.map((source) => (
                <div
                  key={`${source.entity}-${source.name}`}
                  className="flex items-center justify-between rounded-xl border border-line bg-surface px-3 py-2"
                >
                  <div>
                    <p className="text-[13px] font-medium text-ink">{source.entity.replace(/_/g, " ")}</p>
                    <p className="text-[12px] text-faint">{source.name || "unknown source"}</p>
                  </div>
                  <Badge tone={source.is_live ? "jade" : "outline"}>
                    {source.is_live ? "Live" : source.last_verified_at ? "Recorded" : "Unverified"}
                  </Badge>
                </div>
              ))
            )}
          </div>
          {evidence.cost_assumption ? (
            <p className="rounded-xl border border-line bg-raised/50 px-3 py-2 text-[12px] text-muted">
              Cost: {formatMoney(evidence.cost_assumption.value, evidence.cost_assumption.currency)} ·{" "}
              {evidence.cost_assumption.basis}
            </p>
          ) : null}
          {evidence.travel_assumption ? (
            <p className="text-[12px] leading-5 text-faint">{evidence.travel_assumption}</p>
          ) : null}
          {evidence.unknowns.length ? (
            <div>
              <p className="text-[12px] uppercase tracking-editorial text-faint">Still unknown</p>
              <ul className="mt-1 space-y-1">
                {evidence.unknowns.map((item) => (
                  <li key={item} className="flex items-start gap-1.5 text-[12px] text-muted">
                    <CircleHelp size={13} className="mt-0.5 shrink-0 text-faint" /> {item}
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
          <FlowNote icon={<ShieldCheck size={14} />}>
            {evidence.disclosure || "Missing data stays unknown. We never invent travel facts."}
          </FlowNote>
        </Card>

        <Card className="space-y-4">
          <SectionTitle title="Access chain" hint="Step-by-step access from transit to return" />
          <div className="flex flex-wrap gap-2">
            <Badge tone="jade">{access.summary.verified_stages} verified</Badge>
            <Badge tone={access.summary.reported_barriers ? "rose" : "outline"}>
              {access.summary.reported_barriers} barrier(s)
            </Badge>
            <Badge tone="outline">{access.summary.unknown_stages} unknown</Badge>
          </div>
          <ol className="space-y-2">
            {access.stages.map((stage) => (
              <li key={stage.stage} className="flex gap-3">
                <span
                  className={cn(
                    "mt-1 h-2 w-2 shrink-0 rounded-full",
                    stage.status === "verified"
                      ? "bg-jade"
                      : stage.status === "barrier" || stage.status === "limited"
                        ? "bg-rose"
                        : stage.status === "reported"
                          ? "bg-ember"
                          : "bg-faint",
                  )}
                />
                <div className="min-w-0">
                  <p className="text-[13px] font-medium text-ink">
                    {stage.label}{" "}
                    <span className="ml-1 text-[10px] uppercase tracking-wide text-faint">{stage.status}</span>
                  </p>
                  <p className="text-[12px] leading-5 text-muted">{stage.detail || "No information recorded."}</p>
                </div>
              </li>
            ))}
          </ol>
          <FlowNote icon={<TriangleAlert size={14} />}>
            {access.disclosure || "Do not assume step-free access without evidence."}
          </FlowNote>
        </Card>
      </div>

      <Card className="space-y-4">
        <SectionTitle
          title="Crowd forecast"
          hint="Built only from enough observed reports — never invented"
          action={<Badge tone={crowd.status === "predicted" ? "jade" : "outline"}>{crowd.status.replace(/_/g, " ")}</Badge>}
        />
        {crowd.status !== "predicted" || !crowd.predicted?.forecasts?.length ? (
          <div className="space-y-2">
            <p className="text-sm text-muted">{crowd.message || "Not enough data to forecast crowds."}</p>
            {crowd.observed ? (
              <p className="text-[12px] text-faint">
                {crowd.observed.reports_used} recent usable report
                {crowd.observed.reports_used === 1 ? "" : "s"} ·{" "}
                {crowd.observed.reports_seen} seen in the last{" "}
                {crowd.threshold?.window_days ?? 180} days
                {crowd.observed.excluded_stale
                  ? ` · ${crowd.observed.excluded_stale} too old`
                  : ""}
              </p>
            ) : null}
            {crowd.latest_observation ? (
              <div className="rounded-xl border border-line bg-surface px-3 py-2 text-[12px] text-muted">
                Latest observation: {crowd.latest_observation.source_label || crowd.latest_observation.source_type} ·{" "}
                {formatDate(crowd.latest_observation.observed_at)}
              </div>
            ) : null}
          </div>
        ) : (
          <div className="space-y-3">
            <div className="rounded-xl border border-line bg-raised/50 px-3 py-2">
              <p className="text-[11px] uppercase tracking-editorial text-faint">Observed</p>
              <p className="mt-0.5 text-[12px] leading-5 text-muted">
                {crowd.observed?.reports_used ?? 0} recent reports used
                {crowd.observed?.range
                  ? ` · level ${Math.round(crowd.observed.range.min * 100)}–${Math.round(crowd.observed.range.max * 100)}%`
                  : ""}
                {crowd.observed?.excluded_outliers
                  ? ` · ${crowd.observed.excluded_outliers} outlier${crowd.observed.excluded_outliers === 1 ? "" : "s"} ignored`
                  : ""}
                {crowd.observed?.excluded_stale
                  ? ` · ${crowd.observed.excluded_stale} too old`
                  : ""}
              </p>
            </div>
            {crowd.predicted?.forecasts.map((forecast) => (
              <div key={`${forecast.weekday}-${forecast.bucket}`} className="space-y-1">
                <div className="flex flex-wrap items-center justify-between gap-2 text-[12px]">
                  <span className="flex items-center gap-1.5 text-muted">
                    {WEEKDAYS[forecast.weekday]} · {forecast.bucket}
                    {forecast.fallback ? <Badge tone="outline">{forecast.granularity?.replace(/_/g, " ")}</Badge> : null}
                    {forecast.stale ? <Badge tone="ember">stale</Badge> : null}
                  </span>
                  <span className="font-mono text-[12px] text-faint">
                    {Math.round(forecast.expected_level * 100)}%
                    {forecast.interval_80
                      ? ` (${Math.round(forecast.interval_80[0] * 100)}–${Math.round(forecast.interval_80[1] * 100)}%)`
                      : ` · ±${Math.round(forecast.spread * 100)}`}
                    {" · "}
                    {forecast.reports} reports
                    {forecast.confidence_label
                      ? ` · ${forecast.confidence_label} confidence`
                      : typeof forecast.confidence === "number"
                        ? ` · ${Math.round(forecast.confidence * 100)}% confidence`
                        : ""}
                  </span>
                </div>
                <Progress
                  value={forecast.expected_level * 100}
                  tone={forecast.expected_level >= 0.7 ? "ember" : "jade"}
                />
              </div>
            ))}
            <p className="text-[12px] text-faint">{crowd.disclosure}</p>
          </div>
        )}
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="space-y-4">
          <SectionTitle title="What travellers reported" hint="Community observations, weighted by freshness" />
          {!reports?.has_data || categories.length === 0 ? (
            <EmptyState
              title="No reports yet"
              description="Be the first to share what you observed. Reports stay unverified until moderated."
              icon={<CircleHelp size={22} />}
            />
          ) : (
            <div className="space-y-4">
              {categories.map((entry) => (
                <ReportCategoryBlock
                  key={entry.category}
                  entry={entry}
                  isAdmin={isAdmin}
                  onHelpful={(id) => markHelpful.mutate(id)}
                  onVerify={(id) => verifyReport.mutate(id)}
                />
              ))}
            </div>
          )}
        </Card>

        <Card className="space-y-4">
          <SectionTitle title="Share an observation" hint="Only report what you actually saw" />
          <form
            className="space-y-3"
            onSubmit={(event) => {
              event.preventDefault();
              submitReport.mutate();
            }}
          >
            <div className="grid gap-3 sm:grid-cols-2">
              <Field label="Category">
                <Select value={category} onChange={(event) => setCategory(event.target.value)}>
                  {REPORT_CATEGORIES.map((item) => (
                    <option key={item.value} value={item.value}>
                      {item.label}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="Source">
                <Select value={sourceType} onChange={(event) => setSourceType(event.target.value)}>
                  {SOURCE_TYPES.map((item) => (
                    <option key={item.value} value={item.value}>
                      {item.label}
                    </option>
                  ))}
                  {isAdmin ? <option value="official">Official (moderator)</option> : null}
                </Select>
              </Field>
            </div>

            {category === "crowd" ? (
              <Field label="Crowd level">
                <Select value={level} onChange={(event) => setLevel(event.target.value)}>
                  <option value="low">Low</option>
                  <option value="moderate">Moderate</option>
                  <option value="high">High</option>
                  <option value="very_high">Very high</option>
                </Select>
              </Field>
            ) : category === "queue" ? (
              <Field label="Wait time (minutes)">
                <Input
                  type="number"
                  min="0"
                  value={minutes}
                  onChange={(event) => setMinutes(event.target.value)}
                />
              </Field>
            ) : category === "closure" ? (
              <Field label="Is it open?">
                <Select
                  value={closed ? "closed" : "open"}
                  onChange={(event) => setClosed(event.target.value === "closed")}
                >
                  <option value="open">Open</option>
                  <option value="closed">Closed</option>
                </Select>
              </Field>
            ) : category === "price" ? (
              <Field label={`Amount (${activity.currency})`}>
                <Input
                  type="number"
                  min="0"
                  value={amount}
                  onChange={(event) => setAmount(event.target.value)}
                  placeholder="0"
                />
              </Field>
            ) : (
              <Field label="What did you observe?">
                <Input value={detailText} onChange={(event) => setDetailText(event.target.value)} />
              </Field>
            )}

            <div className="grid gap-3 sm:grid-cols-2">
              <Field label="Observed on">
                <Input
                  type="date"
                  max={todayIso()}
                  value={observedAt}
                  onChange={(event) => setObservedAt(event.target.value)}
                />
              </Field>
              <Field label="Note" hint="Optional context">
                <Input value={note} onChange={(event) => setNote(event.target.value)} placeholder="Short note" />
              </Field>
            </div>

            <Button type="submit" loading={submitReport.isPending} className="w-full sm:w-auto">
              <Send size={14} /> Share observation
            </Button>
            <p className="text-[12px] leading-5 text-faint">
              Reports are unverified community observations, not official facts. Older reports carry less weight.
            </p>
          </form>
        </Card>
      </div>

      <Card className="space-y-4">
        <SectionTitle title="Expectation check" hint="Test a belief against recorded evidence, not vibes" />
        <form
          className="flex flex-col gap-2 sm:flex-row"
          onSubmit={(event) => {
            event.preventDefault();
            if (claim.trim().length < 3) return;
            runExpectation.mutate();
          }}
        >
          <Input
            value={claim}
            onChange={(event) => setClaim(event.target.value)}
            placeholder='"It is free and never crowded"'
            className="flex-1"
          />
          <Button type="submit" variant="secondary" loading={runExpectation.isPending}>
            <BadgeCheck size={14} /> Check claim
          </Button>
        </form>

        {expectation ? (
          <div className="space-y-3">
            <div className="flex flex-wrap items-center gap-2">
              <Badge tone={expectation.verdict === "supported_by_recorded_sources" ? "jade" : "ember"}>
                {expectation.verdict.replace(/_/g, " ")}
              </Badge>
              <span className="text-[12px] text-muted">{expectation.claim}</span>
            </div>
            <div className="space-y-2">
              {expectation.evidence.length === 0 ? (
                <p className="text-sm text-muted">No recorded evidence matches this claim.</p>
              ) : (
                expectation.evidence.map((item) => (
                  <div key={item.item} className="rounded-xl border border-line bg-surface px-3 py-2">
                    <div className="flex items-center justify-between gap-2">
                      <p className="text-[13px] font-medium text-ink">{item.item}</p>
                      <Badge tone={STATUS_TONE[item.status] || "outline"}>{item.status}</Badge>
                    </div>
                    <p className="mt-1 text-[12px] leading-5 text-muted">{item.detail}</p>
                  </div>
                ))
              )}
            </div>
            <div className="grid gap-2 sm:grid-cols-2">
              <div>
                <p className="text-[12px] uppercase tracking-editorial text-faint">Limitations</p>
                <ul className="mt-1 space-y-1">
                  {expectation.limitations.map((item) => (
                    <li key={item} className="text-[12px] leading-5 text-muted">
                      · {item}
                    </li>
                  ))}
                </ul>
              </div>
              <div>
                <p className="text-[12px] uppercase tracking-editorial text-faint">Unknowns</p>
                <ul className="mt-1 space-y-1">
                  {expectation.unknowns.map((item) => (
                    <li key={item} className="text-[12px] leading-5 text-muted">
                      · {item}
                    </li>
                  ))}
                </ul>
              </div>
            </div>
          </div>
        ) : (
          <FlowNote icon={<CircleHelp size={14} />}>
            Try a claim like &quot;it is free&quot;, &quot;it is crowded&quot;, &quot;it is open today&quot; or &quot;it is
            step-free&quot; to see which parts are supported, estimated or unknown.
          </FlowNote>
        )}
      </Card>

      <Modal open={proposeOpen} onClose={() => setProposeOpen(false)} title={`Propose ${activity.name}`}>
        <form
          className="space-y-3"
          onSubmit={(event) => {
            event.preventDefault();
            proposeActivity.mutate();
          }}
        >
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Day">
              <Input
                type="date"
                min={trip.data?.start_date?.slice(0, 10)}
                max={trip.data?.end_date?.slice(0, 10)}
                value={proposeDay}
                onChange={(event) => setProposeDay(event.target.value)}
              />
            </Field>
            <Field label="Start time">
              <Input type="time" value={proposeTime} onChange={(event) => setProposeTime(event.target.value)} />
            </Field>
          </div>
          <Textarea
            value={detailText}
            onChange={(event) => setDetailText(event.target.value)}
            placeholder="Why this? (optional note for the group)"
          />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={() => setProposeOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" loading={proposeActivity.isPending} disabled={!proposeDay}>
              <Sparkles size={14} /> Create proposal
            </Button>
          </div>
          <p className="text-[12px] leading-5 text-faint">
            This creates a proposal. The confirmed plan only changes after group voting and owner/admin approval.
          </p>
        </form>
      </Modal>
    </div>
  );
}

function ReportCategoryBlock({
  entry,
  isAdmin,
  onHelpful,
  onVerify,
}: {
  entry: PlaceReportCategory;
  isAdmin: boolean;
  onHelpful: (id: string) => void;
  onVerify: (id: string) => void;
}) {
  return (
    <div className="rounded-2xl border border-line bg-surface p-3.5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-[13px] font-medium capitalize text-ink">{entry.category}</p>
        <div className="flex flex-wrap items-center gap-1.5">
          <Badge tone={STATUS_TONE[entry.status] || "outline"}>{entry.status}</Badge>
          <Badge tone="outline">{entry.reports_count} report(s)</Badge>
          <Badge tone="outline">{entry.freshness_label}</Badge>
        </div>
      </div>
      <p className="mt-1 text-[12px] text-faint">
        {entry.source_label} · latest {formatDate(entry.latest_observed_at)}
      </p>
      <div className="mt-2 space-y-2">
        {entry.reports.map((report) => (
          <div key={report.id} className="rounded-xl border border-line bg-paper px-3 py-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="text-[12px] text-muted">
                {describeValue(report.value)} {report.note ? `· ${report.note}` : ""}
              </span>
              <div className="flex items-center gap-1.5">
                {report.verification === "official_verified" ? (
                  <Badge tone="jade">official · verified</Badge>
                ) : report.verification === "moderator_verified" ? (
                  <Badge tone="outline">moderator-checked</Badge>
                ) : report.verified ? (
                  <Badge tone="outline">verified</Badge>
                ) : null}
                <button
                  type="button"
                  onClick={() => onHelpful(report.id)}
                  className="inline-flex items-center gap-1 rounded-full border border-line px-2 py-0.5 text-[10.5px] text-muted hover:border-ink/30 hover:text-ink"
                >
                  <ThumbsUp size={10} /> Helpful
                </button>
                {isAdmin && !report.verified ? (
                  <button
                    type="button"
                    onClick={() => onVerify(report.id)}
                    className="inline-flex items-center gap-1 rounded-full border border-jade/30 px-2 py-0.5 text-[10.5px] text-jade hover:bg-jade-soft"
                  >
                    <BadgeCheck size={10} /> Verify
                  </button>
                ) : null}
              </div>
            </div>
            <p className="mt-0.5 text-[10.5px] text-faint">
              {report.provenance} · {formatDate(report.observed_at)} · confidence {Math.round(report.confidence * 100)}%
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}

function describeValue(value: Record<string, unknown>) {
  if ("level" in value) return `Level: ${String(value.level)}`;
  if ("minutes" in value) return `Wait: ${String(value.minutes)} min`;
  if ("closed" in value) return value.closed ? "Closed" : "Open";
  if ("amount" in value) return `Price: ${String(value.amount)}`;
  if ("status" in value) return `Status: ${String(value.status)}`;
  if ("detail" in value) return String(value.detail);
  const keys = Object.keys(value);
  if (keys.length === 0) return "Observation";
  return keys.map((key) => `${key}: ${String(value[key])}`).join(", ");
}
