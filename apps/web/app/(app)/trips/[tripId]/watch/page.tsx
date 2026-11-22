"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { BellRing, Eye, Radar, RefreshCw, Trash2 } from "lucide-react";
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
  PageSkeleton,
  SectionTitle,
  Select,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useMaterialWatches, useSearch, useTrip } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { errorMessage, formatDateTime, formatMoney, titleCase } from "@/lib/utils";

const FIELDS = [
  { value: "opening_hours", label: "Opening hours" },
  { value: "price_estimate", label: "Price" },
  { value: "wheelchair_accessible", label: "Step-free access" },
];

const DAY_LABELS: Record<string, string> = {
  mon: "Mon",
  tue: "Tue",
  wed: "Wed",
  thu: "Thu",
  fri: "Fri",
  sat: "Sat",
  sun: "Sun",
};

// Seeded rows store the raw value, new rows store {value}, changed rows store
// {value, previous}. Normalise both shapes so the card never shows raw JSON.
function describeWatchValue(field: string, raw: Record<string, unknown>): string {
  const stored = "value" in raw ? raw.value : raw;
  if (stored === null || stored === undefined) return "unknown";
  if (field === "wheelchair_accessible") {
    if (stored === true) return "step-free";
    if (stored === false) return "not step-free";
    return "unknown";
  }
  if (field === "price_estimate") {
    if (typeof stored === "number") return formatMoney(stored);
    if (stored === null) return "unknown";
    return String(stored);
  }
  if (typeof stored === "object" && !Array.isArray(stored)) {
    const entries = Object.entries(stored as Record<string, unknown>);
    const hours = entries.filter(([key]) => key in DAY_LABELS);
    if (hours.length) {
      const distinct = new Set(hours.map(([, value]) => String(value)));
      if (distinct.size === 1) return `Every day ${hours[0][1]}`;
      return hours.map(([day, value]) => `${DAY_LABELS[day]} ${value}`).join(" · ");
    }
    if (!entries.length) return "unknown";
    return entries.map(([key, value]) => `${titleCase(key)} ${String(value)}`).join(" · ");
  }
  return String(stored);
}

export default function WatchPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const watches = useMaterialWatches(tripId);
  const catalog = useSearch({ destination_id: trip.data?.destination_id || undefined, limit: 60 });
  const queryClient = useQueryClient();
  const { push } = useToasts();

  const [activityId, setActivityId] = useState("");
  const [field, setField] = useState("opening_hours");
  const [checkResult, setCheckResult] = useState<{ checked: number; changed: unknown[]; unchanged: number; note: string } | null>(null);

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["watches", tripId] });

  const addWatch = useMutation({
    mutationFn: () =>
      api(`/api/trips/${tripId}/material-watch`, {
        method: "POST",
        body: { activity_id: activityId, field },
      }),
    onSuccess: () => {
      push("Watching", "You are alerted only when the value actually changes.", "success");
      setActivityId("");
      refresh();
    },
    onError: (error) => push("Could not add watch", errorMessage(error), "error"),
  });

  const removeWatch = useMutation({
    mutationFn: (watchId: string) =>
      api(`/api/trips/${tripId}/material-watch/${watchId}`, { method: "DELETE" }),
    onSuccess: () => {
      push("Watch removed", undefined, "info");
      refresh();
    },
    onError: (error) => push("Could not remove", errorMessage(error), "error"),
  });

  const checkNow = useMutation({
    mutationFn: () =>
      api<{ checked: number; changed: unknown[]; unchanged: number; note: string }>(
        `/api/trips/${tripId}/material-watch/check`,
        { method: "POST" },
      ),
    onSuccess: (result) => {
      setCheckResult(result);
      push(
        "Check complete",
        `${result.changed.length} change(s) across ${result.checked} watch(es).`,
        result.changed.length ? "success" : "info",
      );
      refresh();
    },
    onError: (error) => push("Check failed", errorMessage(error), "error"),
  });

  if (watches.isLoading) return <PageSkeleton />;
  if (watches.error || !watches.data) {
    return <ErrorState error={watches.error || new Error("Watches unavailable")} retry={() => watches.refetch()} />;
  }

  const items = watches.data.items;

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Material Change Watch</p>
          <h2 className="mt-1 text-2xl">Alert on changes that matter</h2>
          <p className="mt-1 max-w-prose text-sm text-muted">{watches.data.note}</p>
        </div>
        <Button variant="secondary" onClick={() => checkNow.mutate()} loading={checkNow.isPending}>
          <RefreshCw size={14} /> Check now
        </Button>
      </div>

      {checkResult ? (
        <FlowNote icon={<BellRing size={14} />}>
          Checked {checkResult.checked} · changed {checkResult.changed.length} · unchanged {checkResult.unchanged}.{" "}
          {checkResult.note}
        </FlowNote>
      ) : null}

      <Card className="space-y-3">
        <SectionTitle title="Add a watch" hint="Only fields recorded in the catalog can be tracked" />
        <form
          className="flex flex-col gap-2 sm:flex-row sm:items-end"
          onSubmit={(event) => {
            event.preventDefault();
            if (!activityId) return;
            addWatch.mutate();
          }}
        >
          <Field label="Activity">
            <Select value={activityId} onChange={(event) => setActivityId(event.target.value)}>
              <option value="">Choose an activity…</option>
              {(catalog.data?.items ?? []).map((entry) => (
                <option key={entry.activity.id} value={entry.activity.id}>
                  {entry.activity.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Field">
            <Select value={field} onChange={(event) => setField(event.target.value)}>
              {FIELDS.map((entry) => (
                <option key={entry.value} value={entry.value}>
                  {entry.label}
                </option>
              ))}
            </Select>
          </Field>
          <Button type="submit" loading={addWatch.isPending} disabled={!activityId}>
            <Eye size={14} /> Watch
          </Button>
        </form>
      </Card>

      {items.length === 0 ? (
        <EmptyState
          title="Nothing watched yet"
          description="Track opening hours, price or step-free access. SAFAR alerts only when the recorded value changes."
          icon={<Radar size={24} />}
        />
      ) : (
        <div className="space-y-2">
          {items.map((watch) => (
            <Card key={watch.id} className="flex flex-wrap items-center justify-between gap-3">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-1.5">
                  <Badge tone={watch.status === "changed" ? "ember" : watch.status === "target_missing" ? "rose" : "jade"}>
                    {titleCase(watch.status)}
                  </Badge>
                  <Badge tone="outline">{titleCase(watch.field)}</Badge>
                </div>
                <p className="mt-1 text-[13px] font-medium text-ink">{watch.activity_name || "Activity"}</p>
                <p className="text-[12px] text-faint">
                  Last value: {describeWatchValue(watch.field, watch.last_value)}
                  {watch.last_checked_at ? ` · checked ${formatDateTime(watch.last_checked_at)}` : " · never checked"}
                </p>
              </div>
              <button
                type="button"
                onClick={() => removeWatch.mutate(watch.id)}
                className="text-faint hover:text-rose"
                aria-label="Remove watch"
              >
                <Trash2 size={15} />
              </button>
            </Card>
          ))}
        </div>
      )}

      <FlowNote icon={<Radar size={14} />}>
        Alerts never change your confirmed plan. If a watched fact changes, review it and decide whether to
        propose an update.
      </FlowNote>
    </div>
  );
}
