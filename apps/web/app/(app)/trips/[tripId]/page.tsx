"use client";

import {
  ArrowRight,
  CalendarDays,
  Clock,
  Compass,
  MapPin,
  ShieldCheck,
  Sparkles,
  Ticket,
  Users,
  Waypoints,
} from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";

import {
  Avatar,
  Badge,
  Card,
  EmptyState,
  ErrorState,
  FlowNote,
  LinkButton,
  PageSkeleton,
  Progress,
  SectionTitle,
  Stat,
} from "@/components/ui";
import {
  useItinerary,
  useMembers,
  usePact,
  useProposals,
  useTrip,
  useTripActivity,
} from "@/lib/hooks";
import { useAuth } from "@/lib/store";
import {
  daysBetween,
  daysUntil,
  formatDay,
  formatMoney,
  formatTime,
  titleCase,
} from "@/lib/utils";

export default function TripOverviewPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const itinerary = useItinerary(tripId);
  const members = useMembers(tripId);
  const proposals = useProposals(tripId, "open");
  const pact = usePact(tripId);
  const activity = useTripActivity(tripId);
  const user = useAuth((state) => state.user);

  if (trip.isLoading) return <PageSkeleton />;
  if (trip.error || !trip.data) {
    return <ErrorState error={trip.error || new Error("Trip not found")} retry={() => trip.refetch()} />;
  }

  const data = trip.data;
  const plan = itinerary.data;
  const items = plan?.items ?? [];
  const open = proposals.data?.items ?? [];
  const people = members.data?.items ?? [];
  const days = Math.max(1, daysBetween(data.start_date, data.end_date));
  const perPerson = data.budget_total ? data.budget_total / Math.max(1, data.member_count || 1) : null;
  const spend = plan?.totals?.cost ?? 0;
  const spendShare = perPerson ? Math.min(100, (spend / (perPerson * days)) * 100) : 0;

  const byDay = new Map<string, typeof items>();
  items.forEach((item) => {
    const key = String(item.day).slice(0, 10);
    byDay.set(key, [...(byDay.get(key) ?? []), item]);
  });

  const nextAction = data.next_action;
  const isOwner = data.my_role === "owner" || data.my_role === "admin";

  return (
    <div className="space-y-8">
      {nextAction ? (
        <Card className="relative overflow-hidden border-ember/30 bg-ember-soft/30">
          <span aria-hidden className="absolute inset-y-0 left-0 w-1 bg-ember/70" />
          <div className="relative z-10 flex flex-col gap-4 pl-2 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p className="eyebrow flex items-center gap-1.5">
                <Sparkles size={12} /> Your next step
              </p>
              <h2 className="mt-1.5 text-2xl">{nextAction.title}</h2>
              <p className="mt-1 max-w-prose text-sm text-muted">{nextAction.reason}</p>
            </div>
            <LinkButton href={nextAction.href} size="lg" className="shrink-0">
              {nextAction.kind === "vote" ? "Open decisions" : "Continue"}
              <ArrowRight size={16} />
            </LinkButton>
          </div>
        </Card>
      ) : null}

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Days" value={days} hint={`${formatDay(data.start_date)} · ${daysUntil(data.start_date) > 0 ? `in ${daysUntil(data.start_date)} days` : "underway"}`} />
        <Stat label="Confirmed" value={items.length} hint={`${byDay.size} day(s) planned`} tone="jade" />
        <Stat
          label="Open decisions"
          value={open.length}
          hint={open.length ? "Needs the group" : "Nothing waiting"}
          tone={open.length ? "ember" : "ink"}
        />
        <Stat
          label="Group"
          value={`${data.member_count ?? people.length}/${data.group_size}`}
          hint={isOwner ? "Invite more people" : "Travellers active"}
        />
      </div>

      {data.description ? (
        <p className="max-w-prose text-[15px] leading-7 text-muted">{data.description}</p>
      ) : null}

      <div className="grid gap-6 lg:grid-cols-[1.5fr_1fr]">
        <section className="space-y-4">
          <SectionTitle
            title="The plan so far"
            hint="Only confirmed items appear here. Changes always go through the group."
            action={
              <Link href={`/trips/${tripId}/itinerary`} className="text-xs text-ember hover:underline">
                Open itinerary
              </Link>
            }
          />
          {itinerary.isLoading ? (
            <PageSkeleton />
          ) : byDay.size === 0 ? (
            <EmptyState
              title="No confirmed plan yet"
              description="Start with the engine: it recommends activities that satisfy every hard constraint, then the group decides."
              icon={<Compass size={24} />}
              action={
                <LinkButton href={`/trips/${tripId}/engine`} size="sm">
                  <Sparkles size={14} /> Generate options
                </LinkButton>
              }
            />
          ) : (
            <div className="space-y-4">
              {[...byDay.entries()].slice(0, 4).map(([day, dayItems]) => (
                <Card key={day} className="space-y-3">
                  <div className="flex items-baseline justify-between gap-2">
                    <h3 className="text-lg">{formatDay(day)}</h3>
                    <span className="text-[12px] text-faint">{dayItems.length} item(s)</span>
                  </div>
                  <div className="space-y-2.5">
                    {dayItems.map((item) => (
                      <div key={item.id} className="flex items-start gap-3">
                        <span className="mt-0.5 inline-flex w-14 shrink-0 items-center gap-1 font-mono text-[12px] text-faint">
                          <Clock size={11} /> {formatTime(item.start_time)}
                        </span>
                        <div className="min-w-0 flex-1 border-l border-line pl-3">
                          <p className="truncate text-sm text-ink">{item.title}</p>
                          <p className="mt-0.5 flex flex-wrap items-center gap-x-2 text-[12px] text-faint">
                            {item.is_protected ? (
                              <span className="inline-flex items-center gap-0.5 text-jade">
                                <ShieldCheck size={11} /> Protected
                              </span>
                            ) : null}
                            {item.activity?.duration_minutes ? (
                              <span>{item.activity.duration_minutes} min</span>
                            ) : null}
                            {item.cost_estimate ? (
                              <span>{formatMoney(item.cost_estimate, data.currency)}</span>
                            ) : null}
                          </p>
                        </div>
                      </div>
                    ))}
                  </div>
                </Card>
              ))}
              {byDay.size > 4 ? (
                <LinkButton href={`/trips/${tripId}/itinerary`} variant="secondary" size="sm">
                  See all {byDay.size} planned days
                </LinkButton>
              ) : null}
            </div>
          )}
        </section>

        <div className="space-y-4">
          <Card className="space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-lg">Travellers</h3>
              <Link href={`/trips/${tripId}/members`} className="text-xs text-ember hover:underline">
                {isOwner ? "Invite" : "View"}
              </Link>
            </div>
            <div className="space-y-3">
              {people.slice(0, 6).map((member) => (
                <div key={member.id} className="flex items-center gap-2.5">
                  <Avatar name={member.display_name} size={32} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm text-ink">
                      {member.display_name}
                      {member.is_self ? <span className="ml-1 text-[12px] text-faint">(you)</span> : null}
                    </p>
                    <p className="text-[12px] text-faint">
                      {titleCase(member.role)}
                      {member.user?.id === user?.id ? " · private limits" : ""}
                    </p>
                  </div>
                  {member.is_self && member.budget_limit ? (
                    <Badge tone="outline">{formatMoney(member.budget_limit, data.currency)}</Badge>
                  ) : null}
                </div>
              ))}
              {people.length === 0 ? <p className="text-sm text-muted">No active members yet.</p> : null}
            </div>
            <p className="text-[12px] leading-5 text-faint">
              Budget limits and access needs are private to each traveller.
            </p>
          </Card>

          <Card className="space-y-3">
            <h3 className="text-lg">Money</h3>
            {perPerson ? (
              <>
                <div className="flex items-baseline justify-between text-sm">
                  <span className="text-muted">Planned per person</span>
                  <span className="font-mono text-ink">{formatMoney(spend / Math.max(1, data.member_count || 1), data.currency)}</span>
                </div>
                <div className="flex items-baseline justify-between text-sm">
                  <span className="text-muted">Trip budget share</span>
                  <span className="font-mono text-ink">{formatMoney(perPerson, data.currency)}</span>
                </div>
                <Progress value={spendShare} tone={spendShare > 90 ? "ember" : "jade"} />
                <p className="text-[12px] text-faint">
                  Estimates from catalog prices. Actual expenses are tracked separately.
                </p>
              </>
            ) : (
              <p className="text-sm text-muted">No trip budget set. Expenses still track real spend.</p>
            )}
            <LinkButton href={`/trips/${tripId}/expenses`} variant="secondary" size="sm">
              Expenses & settlements
            </LinkButton>
          </Card>

          {pact.data?.pact ? (
            <Card className="space-y-3">
              <div className="flex items-center justify-between">
                <h3 className="text-lg">Journey Pact</h3>
                <Link href={`/trips/${tripId}/pact`} className="text-xs text-ember hover:underline">
                  Edit
                </Link>
              </div>
              <div className="flex flex-wrap gap-1.5">
                {(pact.data.pact.must_do || []).map((rule) => (
                  <Badge key={rule} tone="jade">
                    Must · {rule}
                  </Badge>
                ))}
                {(pact.data.pact.flexible || []).slice(0, 4).map((rule) => (
                  <Badge key={rule} tone="neutral">
                    {rule}
                  </Badge>
                ))}
              </div>
            </Card>
          ) : null}

          <Card className="space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="text-lg">Live activity</h3>
              <span className="text-[12px] text-faint">latest</span>
            </div>
            {(activity.data?.items ?? []).slice(0, 4).map((event) => (
              <div key={event.id} className="flex gap-2.5 text-[12.5px]">
                <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-ember/60" />
                <div>
                  <p className="text-ink">{titleCase(event.action.replace(/\./g, " "))}</p>
                  <p className="text-[12px] text-faint">{new Date(event.created_at).toLocaleString()}</p>
                </div>
              </div>
            ))}
            {!activity.data?.items?.length ? (
              <p className="text-sm text-muted">Activity will appear as the group plans.</p>
            ) : null}
          </Card>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {[
          {
            href: `/trips/${tripId}/pulse`,
            icon: Waypoints,
            title: "Trip Pulse",
            copy: "Share today's energy, time and interests — privately.",
          },
          {
            href: `/trips/${tripId}/voting`,
            icon: Ticket,
            title: "Decisions",
            copy: "Vote on proposals and approve changes as a group.",
          },
          {
            href: `/trips/${tripId}/map`,
            icon: MapPin,
            title: "Map & nearby",
            copy: "See the plan on the map and what's close by.",
          },
          {
            href: `/trips/${tripId}/more`,
            icon: Users,
            title: "Everything else",
            copy: "Twin, rescue, insights, memories, capsules and more.",
          },
        ].map(({ href, icon: Icon, title, copy }) => (
          <Link
            key={href}
            href={href}
            className="group rounded-3xl border border-line bg-surface p-4 transition-colors hover:border-ember/40"
          >
            <Icon size={18} className="text-ember" strokeWidth={1.8} />
            <p className="mt-3 text-sm font-medium text-ink">{title}</p>
            <p className="mt-1 text-[12px] leading-5 text-muted">{copy}</p>
          </Link>
        ))}
      </div>

      <FlowNote icon={<Compass size={15} />}>
        The engine recommends; the group decides. Nothing on this page changes the confirmed plan
        silently — every change needs an explicit group decision.
      </FlowNote>
    </div>
  );
}
