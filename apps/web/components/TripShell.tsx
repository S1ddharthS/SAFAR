"use client";

import {
  CalendarDays,
  CircleDollarSign,
  Compass,
  LayoutDashboard,
  Map,
  MoreHorizontal,
  NotebookPen,
  Sparkles,
  Ticket,
  Users,
  Waypoints,
} from "lucide-react";
import Link from "next/link";
import { useParams, usePathname } from "next/navigation";

import { Avatar, Badge, ErrorState, LinkButton, PageSkeleton } from "@/components/ui";
import { useMembers, useTrip } from "@/lib/hooks";
import { useTripSocket } from "@/lib/realtime";
import { cn, formatDate, tripPhase } from "@/lib/utils";

const TABS = [
  { href: "", label: "Overview", icon: LayoutDashboard },
  { href: "/itinerary", label: "Plan", icon: CalendarDays },
  { href: "/voting", label: "Decide", icon: Ticket },
  { href: "/pulse", label: "Pulse", icon: Waypoints },
  { href: "/engine", label: "Engine", icon: Sparkles },
  { href: "/map", label: "Map", icon: Map },
  { href: "/memories", label: "Memories", icon: NotebookPen },
  { href: "/expenses", label: "Money", icon: CircleDollarSign },
  { href: "/more", label: "More", icon: MoreHorizontal },
];

export function TripShell({ children }: { children: React.ReactNode }) {
  const params = useParams<{ tripId: string }>();
  const pathname = usePathname();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const members = useMembers(tripId);
  const { status } = useTripSocket(tripId);

  if (trip.isLoading) {
    return (
      <div className="mx-auto max-w-wide px-4 py-8">
        <PageSkeleton />
      </div>
    );
  }
  if (trip.error || !trip.data) {
    return (
      <div className="mx-auto max-w-wide px-4 py-8">
        <ErrorState error={trip.error || new Error("Trip not found")} retry={() => trip.refetch()} />
        <div className="mt-4">
          <LinkButton href="/dashboard" variant="secondary" size="sm">
            Back to dashboard
          </LinkButton>
        </div>
      </div>
    );
  }

  const data = trip.data;
  const base = `/trips/${tripId}`;
  const people = members.data?.items ?? [];
  const canInvite = data.my_role === "owner" || data.my_role === "admin";
  const activeTab = (href: string) => {
    if (!href) return pathname === base;
    return pathname === `${base}${href}` || pathname.startsWith(`${base}${href}/`);
  };

  return (
    <div>
      <header className="border-b border-line pb-4">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="min-w-0">
            <div className="flex items-center gap-2 text-[12px] text-faint">
              <Link href="/dashboard" className="hover:text-ink">
                Dashboard
              </Link>
              <span>/</span>
              <span className="truncate">{data.destination_name || "Journey"}</span>
            </div>
            <h1 className="mt-1 text-balance text-3xl leading-[1.08] sm:text-[2.6rem]">
              {data.name}
            </h1>
            <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-2 text-[12.5px] text-muted">
              <span className="inline-flex items-center gap-1.5">
                <CalendarDays size={14} className="text-faint" />
                {formatDate(data.start_date)} → {formatDate(data.end_date)}
              </span>
              <span className="inline-flex items-center gap-1.5">
                <Compass size={14} className="text-faint" />
                {data.destination_name || "Destination open"}
              </span>
              <Badge tone={data.status === "active" ? "jade" : "outline"}>{tripPhase(data)}</Badge>
              <span
                className={cn(
                  "inline-flex items-center gap-1.5 text-[12px]",
                  status === "live" ? "text-jade" : status === "connecting" ? "text-ember" : "text-faint",
                )}
                title="Trip workspace live channel"
              >
                <span
                  className={cn(
                    "h-1.5 w-1.5 rounded-full",
                    status === "live"
                      ? "bg-jade"
                      : status === "connecting"
                        ? "animate-pulse bg-ember"
                        : "bg-faint",
                  )}
                />
                {status === "live" ? "Live" : status === "connecting" ? "Connecting" : "Solo view"}
              </span>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <LinkButton href={`${base}/assistant`} variant="secondary" size="sm">
              <Sparkles size={14} /> Ask SAFAR
            </LinkButton>
            <LinkButton href={`${base}/members`} variant={canInvite ? "primary" : "secondary"} size="sm">
              <Users size={14} /> {people.length} {canInvite ? "· Invite" : "members"}
            </LinkButton>
          </div>
        </div>

        <div className="mt-4 flex items-center gap-3">
          <div className="flex -space-x-2">
            {people.slice(0, 5).map((member) => (
              <Avatar
                key={member.id}
                name={member.display_name}
                size={28}
                className="ring-2 ring-paper"
              />
            ))}
          </div>
          {people.length > 5 ? (
            <span className="text-[12px] text-faint">+{people.length - 5} more</span>
          ) : null}
          <span className="ml-auto hidden text-[12px] text-faint sm:block">
            Engine recommends · Group decides
          </span>
        </div>

        <nav className="hide-scrollbar -mx-4 mt-4 flex gap-1 overflow-x-auto px-4 sm:mx-0 sm:px-0">
          {TABS.map((tab) => {
            const Icon = tab.icon;
            const active = activeTab(tab.href);
            return (
              <Link
                key={tab.href}
                href={`${base}${tab.href}`}
                className={cn(
                  "inline-flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-1.5 text-[12.5px] transition-colors",
                  active
                    ? "border-ink bg-ink text-paper"
                    : "border-line bg-surface text-muted hover:border-ink/30 hover:text-ink",
                )}
              >
                <Icon size={14} strokeWidth={1.8} />
                {tab.label}
              </Link>
            );
          })}
        </nav>
      </header>

      <div className="pt-6">{children}</div>
    </div>
  );
}
