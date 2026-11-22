"use client";

import {
  ArrowRight,
  ArrowUpRight,
  CalendarDays,
  Compass,
  Globe2,
  Plus,
  Sparkles,
  Ticket,
  Users,
} from "lucide-react";
import Link from "next/link";
import { useMemo } from "react";

import { DestinationCard } from "@/components/DestinationCard";
import { DestinationImage } from "@/components/DestinationImage";
import {
  Badge,
  Card,
  EmptyState,
  LinkButton,
  PageHeader,
  PageSkeleton,
  SectionTitle,
  Stat,
} from "@/components/ui";
import { useDestinations, useMe, useThread, useTrip, useTripActivity, useTrips } from "@/lib/hooks";
import {
  DNA_LABELS,
  daysBetween,
  daysUntil,
  formatDate,
  formatMoney,
  titleCase,
  tripPhase,
} from "@/lib/utils";
import type { Trip } from "@/lib/types";

function TripCard({ trip }: { trip: Trip }) {
  const live = tripPhase(trip) === "Happening now";
  return (
    <Link href={`/trips/${trip.id}`} className="group block h-full rounded-3xl">
      <Card interactive className="flex h-full flex-col overflow-hidden p-0">
        <div className="relative h-36 overflow-hidden">
          <DestinationImage
            name={trip.destination_name}
            sizes="(max-width: 640px) 100vw, (max-width: 1280px) 50vw, 33vw"
            overlay="bottom"
            className="transition-transform duration-[900ms] ease-editorial group-hover:scale-[1.04]"
          />
          <div className="absolute inset-x-0 bottom-0 flex items-end justify-between gap-2 p-3.5">
            <span className="text-[10px] uppercase tracking-editorial text-paper/80">
              {trip.destination_name || "Destination open"}
            </span>
            <span className="inline-flex h-8 w-8 items-center justify-center rounded-full border border-paper/30 bg-paper/10 text-paper backdrop-blur transition-transform duration-300 group-hover:-translate-y-0.5">
              <ArrowUpRight size={14} />
            </span>
          </div>
        </div>
        <div className="flex flex-1 flex-col p-5">
          <div className="flex items-start justify-between gap-2">
            <h3 className="text-xl leading-snug">{trip.name}</h3>
            <Badge tone={live ? "jade" : trip.status === "completed" ? "outline" : "ember"}>
              {tripPhase(trip)}
            </Badge>
          </div>
          <p className="mt-2.5 flex items-center gap-1.5 text-[12px] text-muted">
            <CalendarDays size={13} className="text-faint" />
            {formatDate(trip.start_date)} → {formatDate(trip.end_date)}
          </p>
          <p className="mt-1.5 flex items-center gap-1.5 text-[12px] text-muted">
            <Users size={13} className="text-faint" />
            {trip.member_count ?? trip.group_size} travellers
            {trip.my_role ? ` · you are ${trip.my_role}` : ""}
          </p>
          <div className="mt-auto flex items-center justify-between border-t border-line pt-3 text-[12px] text-faint">
            <span>
              {trip.budget_total
                ? `${formatMoney(trip.budget_total, trip.currency)} shared budget`
                : "Shared budget open"}
            </span>
          </div>
        </div>
      </Card>
    </Link>
  );
}

export default function DashboardPage() {
  const trips = useTrips();
  const me = useMe();
  const thread = useThread();
  const destinations = useDestinations();
  const all = trips.data ?? [];
  const upcoming = all.filter((trip) => daysUntil(trip.start_date) > 0);
  const past = all.filter((trip) => trip.status === "completed" || daysUntil(trip.end_date) < 0);
  const spotlight = all.find((trip) => tripPhase(trip) === "Happening now") || upcoming[0];
  const spotlightTrip = useTrip(spotlight?.id);
  const activity = useTripActivity(spotlight?.id);

  const dna = me.data?.dna.scores ?? {};
  const topDna = useMemo(
    () => Object.entries(dna).sort((a, b) => b[1] - a[1]).slice(0, 4),
    [dna],
  );
  const suggested = useMemo(() => {
    const items = destinations.data ?? [];
    const interests = Object.entries(dna)
      .sort((a, b) => b[1] - a[1])
      .filter(([, score]) => score >= 55)
      .map(([key]) => key);
    if (!interests.length) return items.slice(0, 3);
    return [...items]
      .map((item) => ({
        item,
        score: item.tags.filter((tag) => interests.includes(tag)).length,
      }))
      .sort((a, b) => b.score - a.score)
      .slice(0, 3)
      .map((entry) => entry.item);
  }, [destinations.data, dna]);

  if (trips.isLoading) return <PageSkeleton />;

  const name = me.data?.user.display_name || "traveller";

  const startIn = spotlight ? daysUntil(spotlight.start_date) : 0;
  const endIn = spotlight ? daysUntil(spotlight.end_date) : 0;
  const isActive = startIn <= 0 && endIn >= 0;
  const dateValue = !spotlight
    ? 0
    : startIn > 0
      ? startIn
      : isActive
        ? daysBetween(spotlight.start_date, spotlight.end_date) - endIn
        : -endIn;
  const dateHint =
    startIn > 0 ? "days until departure" : isActive ? "days into the journey" : "days since it ended";

  return (
    <div className="space-y-10">
      <PageHeader
        eyebrow={new Intl.DateTimeFormat("en", {
          weekday: "long",
          day: "numeric",
          month: "long",
        }).format(new Date())}
        title={`Welcome back, ${name.split(" ")[0]}.`}
        description="One clear next action per journey — not a wall of alerts."
        actions={
          <>
            <LinkButton href="/discover" variant="secondary" size="md">
              <Globe2 size={15} /> Discover
            </LinkButton>
            <LinkButton href="/trips/new" size="md">
              <Plus size={15} /> New journey
            </LinkButton>
          </>
        }
      />

      {spotlight ? (
        <Card className="overflow-hidden p-0">
          <div className="relative flex min-h-[17rem] flex-col justify-between p-5 sm:min-h-[19rem] sm:p-7">
            <DestinationImage
              name={spotlight.destination_name}
              sizes="(max-width: 1024px) 100vw, 62vw"
              priority
              overlay="bottom"
            />
            <div className="relative z-10 flex flex-wrap items-center gap-2">
              <span className="rounded-full border border-paper/25 bg-ink/35 px-2.5 py-1 text-[10.5px] uppercase tracking-editorial text-paper backdrop-blur">
                {tripPhase(spotlight)}
              </span>
              <span className="text-[11.5px] text-paper/75">
                {spotlight.destination_name || "Destination open"}
              </span>
            </div>
            <div className="relative z-10">
              <h2 className="max-w-[20ch] text-[2rem] leading-[1.1] text-paper sm:text-4xl">
                {spotlight.name}
              </h2>
              <p className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[12.5px] text-paper/80">
                <span className="inline-flex items-center gap-1.5">
                  <CalendarDays size={13} /> {formatDate(spotlight.start_date)} →{" "}
                  {formatDate(spotlight.end_date)}
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <Users size={13} /> {spotlight.member_count ?? spotlight.group_size} travellers
                </span>
              </p>
            </div>
          </div>

          <div className="grid lg:grid-cols-[1.35fr_1fr]">
            <div className="border-b border-line p-5 sm:p-7 lg:border-b-0 lg:border-r">
              {spotlightTrip.data?.next_action ? (
                <>
                  <p className="eyebrow flex items-center gap-1.5">
                    <Sparkles size={12} /> Your next step
                  </p>
                  <h3 className="mt-1.5 text-xl">{spotlightTrip.data.next_action.title}</h3>
                  <p className="mt-1 max-w-prose text-[13px] leading-6 text-muted">
                    {spotlightTrip.data.next_action.reason}
                  </p>
                  <div className="mt-4">
                    <LinkButton href={spotlightTrip.data.next_action.href} size="md">
                      {spotlightTrip.data.next_action.kind === "vote"
                        ? "Open decisions"
                        : "Continue"}
                      <ArrowRight size={15} />
                    </LinkButton>
                  </div>
                </>
              ) : (
                <p className="text-sm leading-6 text-muted">
                  Nothing needs you right now. Open the workspace to see the group&apos;s latest
                  state.
                </p>
              )}
              <div className="mt-4 flex flex-wrap gap-2">
                <LinkButton href={`/trips/${spotlight.id}/itinerary`} variant="secondary" size="sm">
                  <CalendarDays size={14} /> Plan
                </LinkButton>
                <LinkButton href={`/trips/${spotlight.id}/voting`} variant="secondary" size="sm">
                  <Ticket size={14} /> Decisions
                </LinkButton>
                <LinkButton href={`/trips/${spotlight.id}/engine`} variant="secondary" size="sm">
                  <Sparkles size={14} /> Engine
                </LinkButton>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3 p-5 sm:p-7">
              <Stat label="Dates" value={dateValue} hint={dateHint} />
              <Stat
                label="Travellers"
                value={spotlight.member_count ?? spotlight.group_size}
                hint="active members"
                tone="jade"
              />
              <Stat
                label="Budget"
                value={
                  spotlight.budget_total
                    ? formatMoney(spotlight.budget_total, spotlight.currency)
                    : "Open"
                }
                hint="shared total"
              />
              <Stat
                label="Role"
                value={titleCase(spotlight.my_role || "member")}
                hint="your access"
                tone="ember"
              />
            </div>
          </div>
        </Card>
      ) : null}

      {suggested.length ? (
        <section className="space-y-4">
          <SectionTitle
            title="Where your interests point"
            hint="A tag-overlap heuristic from your Journey DNA — not a ranking of the places themselves."
            action={
              <Link href="/discover" className="text-[12px] text-ember hover:underline">
                All destinations
              </Link>
            }
          />
          <div className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
            {suggested.map((destination) => (
              <DestinationCard key={destination.id} destination={destination} />
            ))}
          </div>
        </section>
      ) : null}

      <section className="space-y-4">
        <SectionTitle
          title="Your journeys"
          hint={`${all.length} workspace${all.length === 1 ? "" : "s"} in your network`}
          action={
            <Link href="/trips/new" className="text-[12px] text-ember hover:underline">
              Create one
            </Link>
          }
        />
        {all.length === 0 ? (
          <EmptyState
            icon={<Compass size={26} />}
            title="No journeys yet"
            description="Create a trip, set the dates and invite the group. SAFAR will help you find a day everyone can say yes to."
            action={
              <LinkButton href="/trips/new" size="sm">
                Start a journey
              </LinkButton>
            }
          />
        ) : (
          <div className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
            {all.slice(0, 6).map((trip) => (
              <TripCard key={trip.id} trip={trip} />
            ))}
          </div>
        )}
      </section>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="flex flex-col">
          <SectionTitle title="Journey DNA" hint="The signals behind your recommendations" level={2} />
          {topDna.length ? (
            <div className="grid grid-cols-2 gap-2.5">
              {topDna.map(([dimension, value]) => (
                <div
                  key={dimension}
                  className="rounded-2xl border border-line bg-raised/50 px-3.5 py-3"
                >
                  <p className="text-[11px] uppercase tracking-editorial text-faint">
                    {DNA_LABELS[dimension] || dimension}
                  </p>
                  <p className="num mt-1 font-display text-2xl">{Math.round(value)}</p>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm leading-6 text-muted">Set up your interests to seed Journey DNA.</p>
          )}
          <div className="mt-auto pt-4">
            <LinkButton href="/profile" variant="secondary" size="sm">
              Tune your DNA
            </LinkButton>
          </div>
        </Card>

        <Card className="flex flex-col">
          <SectionTitle
            title="Recent activity"
            hint={spotlight ? spotlight.name : "Across your journeys"}
            level={2}
          />
          {activity.isLoading ? (
            <div className="space-y-3" aria-hidden>
              <div className="skeleton h-4 w-2/3" />
              <div className="skeleton h-4 w-1/2" />
              <div className="skeleton h-4 w-3/5" />
            </div>
          ) : activity.data?.items?.length ? (
            <ol className="space-y-3">
              {activity.data.items.slice(0, 5).map((event) => (
                <li key={event.id} className="flex gap-2.5">
                  <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-ember/70" />
                  <div className="min-w-0">
                    <p className="text-[12.5px] leading-5 text-ink">
                      {titleCase(event.action.replace(/\./g, " "))}
                    </p>
                    <p className="text-[11.5px] text-faint">
                      {titleCase(event.entity_type.replace(/_/g, " "))} ·{" "}
                      {new Date(event.created_at).toLocaleString()}
                    </p>
                  </div>
                </li>
              ))}
            </ol>
          ) : (
            <p className="text-sm leading-6 text-muted">
              Activity appears here as the group plans, votes and updates the journey.
            </p>
          )}
          {spotlight ? (
            <div className="mt-auto pt-4">
              <LinkButton href={`/trips/${spotlight.id}`} variant="secondary" size="sm">
                Open workspace <ArrowRight size={13} />
              </LinkButton>
            </div>
          ) : null}
        </Card>

        <Card className="flex flex-col">
          <SectionTitle title="Journey Thread" hint="What you loved, carried forward" level={2} />
          {thread.isLoading ? (
            <div className="space-y-3" aria-hidden>
              <div className="skeleton h-10 w-full" />
              <div className="skeleton h-10 w-full" />
            </div>
          ) : thread.data?.traditions.length ? (
            <ul className="space-y-2.5">
              {thread.data.traditions.slice(0, 3).map((tradition) => (
                <li
                  key={tradition.activity_id}
                  className="flex items-center justify-between gap-3 rounded-2xl border border-line bg-raised/40 px-3.5 py-2.5"
                >
                  <div className="min-w-0">
                    <p className="truncate text-[13px] font-medium">{tradition.name}</p>
                    <p className="text-[11.5px] text-faint">
                      {tradition.sentiments.length} positive signal
                      {tradition.sentiments.length === 1 ? "" : "s"}
                    </p>
                  </div>
                  <Badge tone="jade">Carry forward</Badge>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm leading-6 text-muted">
              Complete a journey and share feedback to build a thread of traditions worth repeating.
            </p>
          )}
          <div className="mt-auto pt-4">
            <LinkButton href="/thread" variant="secondary" size="sm">
              See the thread
            </LinkButton>
          </div>
        </Card>
      </div>

      {past.length ? (
        <section className="space-y-4">
          <SectionTitle title="Past journeys" hint="Replay the days and keep the story" />
          <div className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
            {past.slice(0, 3).map((trip) => (
              <TripCard key={trip.id} trip={trip} />
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
