"use client";

import { Clock, Compass, Info, MapPin, Route, ShieldCheck } from "lucide-react";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";

import {
  Badge,
  Card,
  EmptyState,
  ErrorState,
  Field,
  FlowNote,
  Input,
  PageSkeleton,
  SectionTitle,
  Stat,
} from "@/components/ui";
import { useOpportunityClock, useTrip } from "@/lib/hooks";
import { formatDay, formatMoney, todayIso } from "@/lib/utils";

const STATUS_LABEL: Record<string, string> = {
  open_now: "Open now",
  later_today: "Later today",
  no_window: "No gap today",
  window_missed: "Window passed",
  closed_today: "Closed today",
  unknown: "Hours unknown",
};

const STATUS_TONE: Record<
  string,
  "jade" | "ember" | "neutral" | "rose" | "outline"
> = {
  open_now: "jade",
  later_today: "ember",
  no_window: "neutral",
  window_missed: "neutral",
  closed_today: "rose",
  unknown: "outline",
};

export default function OpportunityClockPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const [day, setDay] = useState("");
  const clock = useOpportunityClock(tripId, day || undefined);

  useEffect(() => {
    if (day || !trip.data) return;
    const today = todayIso();
    const inside = today >= trip.data.start_date && today <= trip.data.end_date;
    setDay(inside ? today : trip.data.start_date);
  }, [day, trip.data]);

  if (trip.isLoading) return <PageSkeleton />;
  if (trip.error || !trip.data) {
    return <ErrorState error={trip.error || new Error("Trip not found")} retry={() => trip.refetch()} />;
  }

  return (
    <div className="space-y-6">
      <div>
        <p className="eyebrow flex items-center gap-1.5">
          <Clock size={12} /> Opportunity Clock
        </p>
        <h2 className="mt-1 text-2xl">What still fits today</h2>
        <p className="mt-1 max-w-prose text-sm text-muted">
          A read-only check of the confirmed plan against catalog opening hours and estimated travel.
          It proposes nothing and changes nothing.
        </p>
      </div>

      <Card className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <Field label="Check a day" hint="Any date inside this trip">
          <Input
            type="date"
            value={day}
            min={trip.data.start_date}
            max={trip.data.end_date}
            onChange={(event) => setDay(event.target.value)}
          />
        </Field>
        {clock.data?.available ? (
          <div className="flex flex-wrap gap-2">
            <Badge tone="outline">{formatDay(clock.data.date)}</Badge>
            {clock.data.now ? <Badge tone="ember">Local check at {clock.data.now}</Badge> : null}
            <Badge tone="neutral">{clock.data.planned_count} planned item(s)</Badge>
          </div>
        ) : null}
      </Card>

      {clock.isLoading ? (
        <PageSkeleton />
      ) : clock.error ? (
        <ErrorState error={clock.error} retry={() => clock.refetch()} />
      ) : !clock.data?.available ? (
        <EmptyState
          title="No destination yet"
          description={clock.data?.reason || "Add a destination to evaluate the day."}
          icon={<Compass size={24} />}
        />
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <Stat label="Open now" value={clock.data.summary.open_now} tone="jade" hint="Fits the current gap" />
            <Stat label="Later today" value={clock.data.summary.later_today} tone="ember" hint="A gap remains" />
            <Stat
              label="Closed"
              value={clock.data.summary.closed_today ?? 0}
              hint="Catalog says closed"
            />
            <Stat label="Unknown hours" value={clock.data.summary.unknown_hours} hint="Not guessed" />
          </div>

          <Card className="space-y-3">
            <SectionTitle
              title="Free gaps"
              hint="Between confirmed items, 08:00–22:00"
            />
            {(clock.data.free_windows ?? []).length ? (
              <div className="flex flex-wrap gap-2">
                {clock.data.free_windows?.map((window) => (
                  <Badge key={`${window.start}-${window.end}`} tone="outline">
                    {window.start}–{window.end} · {window.minutes} min
                  </Badge>
                ))}
              </div>
            ) : (
              <p className="text-sm text-muted">No usable gap remains on this day.</p>
            )}
            <p className="text-[12px] text-faint">{clock.data.explanation}</p>
          </Card>

          <section className="space-y-3">
            <SectionTitle
              title="Catalog options"
              hint="Opening hours from the catalog; travel is an estimate"
            />
            {clock.data.items.length === 0 ? (
              <EmptyState
                title="Nothing to compare"
                description="Every catalog activity for this destination is already on the confirmed plan for this day."
                icon={<ShieldCheck size={24} />}
              />
            ) : (
              <div className="space-y-2.5">
                {clock.data.items.map((item) => (
                  <Card key={item.activity_id} className="space-y-2">
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-2">
                          <p className="text-sm font-medium text-ink">{item.name}</p>
                          <Badge tone={STATUS_TONE[item.status] || "neutral"}>
                            {STATUS_LABEL[item.status] || item.status}
                          </Badge>
                          <Badge tone="outline">{item.provenance}</Badge>
                        </div>
                        {item.place_name ? (
                          <p className="mt-0.5 flex items-center gap-1 text-[12px] text-faint">
                            <MapPin size={11} /> {item.place_name}
                          </p>
                        ) : null}
                      </div>
                      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[12px] text-muted">
                        <span className="inline-flex items-center gap-1">
                          <Clock size={11} /> {item.duration_minutes} min
                        </span>
                        <span className="inline-flex items-center gap-1">
                          <Route size={11} /> ~{item.travel_minutes_estimate} min
                        </span>
                        {item.price_estimate ? (
                          <span className="font-mono">
                            {formatMoney(item.price_estimate, item.currency)}
                          </span>
                        ) : null}
                      </div>
                    </div>
                    <p className="text-[12.5px] leading-5 text-muted">{item.explanation}</p>
                    <p className="text-[12px] text-faint">
                      Catalog hours for this weekday:{" "}
                      <span className="font-mono">
                        {item.opening_hours_today || "not recorded"}
                      </span>
                      {item.last_verified_at
                        ? ` · catalog verified ${item.last_verified_at.slice(0, 10)}`
                        : " · not independently verified"}
                    </p>
                  </Card>
                ))}
              </div>
            )}
          </section>

          <FlowNote icon={<Info size={15} />}>{clock.data.disclosure}</FlowNote>
        </>
      )}
    </div>
  );
}
