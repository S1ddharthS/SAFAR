"use client";

import {
  Banknote,
  Bell,
  Clock,
  CloudOff,
  Compass,
  Fingerprint,
  GitBranch,
  Handshake,
  HelpCircle,
  Link2,
  MapPinned,
  MessageSquare,
  NotebookPen,
  Radar,
  Scale,
  Sparkles,
  Target,
  Users,
  Wand2,
} from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import type { ReactNode } from "react";

import { Badge, Card, FlowNote } from "@/components/ui";
import { useTrip } from "@/lib/hooks";

interface Entry {
  href: string;
  title: string;
  description: string;
  icon: ReactNode;
  badge?: string;
}

export default function MorePage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const base = `/trips/${tripId}`;

  const groups: { title: string; hint: string; entries: Entry[] }[] = [
    {
      title: "Decide & adapt",
      hint: "Change the plan without losing trust",
      entries: [
        {
          href: `${base}/twin`,
          title: "Trip Twin",
          description: "Compare the confirmed plan with an alternative, line by line.",
          icon: <Fingerprint size={17} />,
        },
        {
          href: `${base}/rescue`,
          title: "Trip Rescue",
          description: "Rain, closures, fatigue, budget or time — see replacements.",
          icon: <CloudOff size={17} />,
        },
        {
          href: `${base}/opportunity`,
          title: "Opportunity Clock",
          description: "What still fits today, read against opening hours and travel estimates.",
          icon: <Clock size={17} />,
        },
        {
          href: `${base}/insights`,
          title: "Plan intelligence",
          description: "Fragility, effort budget, domino map, shadowplans and capsules.",
          icon: <Radar size={17} />,
        },
        {
          href: `${base}/watch`,
          title: "Material Change Watch",
          description: "Alert when hours, prices or step-free status actually change.",
          icon: <Bell size={17} />,
        },
      ],
    },
    {
      title: "Group",
      hint: "Roles, expectations and shared work",
      entries: [
        {
          href: `${base}/members`,
          title: "Members & invites",
          description: "Roles, invitation links and your private preferences.",
          icon: <Users size={17} />,
        },
        {
          href: `${base}/companion`,
          title: "One-Link Companion",
          description: "One anonymous vote or check-in answer, without an account.",
          icon: <Link2 size={17} />,
        },
        {
          href: `${base}/pact`,
          title: "Journey pact",
          description: "Must-dos, flexible items and confirmed meeting points.",
          icon: <Handshake size={17} />,
        },
        {
          href: `${base}/tasks`,
          title: "Planner tasks",
          description: "Share planning work and balance the load.",
          icon: <Scale size={17} />,
        },
        {
          href: `${base}/branches`,
          title: "Branch & rejoin",
          description: "Split the group and reunite at a fixed time and place.",
          icon: <GitBranch size={17} />,
        },
      ],
    },
    {
      title: "Explore",
      hint: "Discovery grounded in evidence",
      entries: [
        {
          href: `${base}/places`,
          title: "Catalog search",
          description: "Search activities with hard filters and honest fit scores.",
          icon: <Compass size={17} />,
        },
        {
          href: `${base}/map`,
          title: "Map & nearby",
          description: "See the plan and nearby places on a map.",
          icon: <MapPinned size={17} />,
        },
        {
          href: `${base}/inspirations`,
          title: "Dream import",
          description: "Import text, links or image URLs as candidates.",
          icon: <Wand2 size={17} />,
        },
        {
          href: `${base}/ground`,
          title: "Ask the ground",
          description: "Ask opt-in local contributors for current observations.",
          icon: <HelpCircle size={17} />,
        },
        {
          href: `${base}/missions`,
          title: "Missions",
          description: "Optional, self-reported travel challenges.",
          icon: <Target size={17} />,
        },
      ],
    },
    {
      title: "Record & remember",
      hint: "The journey after the journey",
      entries: [
        {
          href: `${base}/memories`,
          title: "Memory timeline",
          description: "Notes, photos and voice with per-memory privacy.",
          icon: <NotebookPen size={17} />,
        },
        {
          href: `${base}/memories/studio`,
          title: "Memory Studio",
          description: "Group memories into events and draft grounded captions.",
          icon: <Sparkles size={17} />,
        },
        {
          href: `${base}/memories/replay`,
          title: "Journey replay & book",
          description: "Replay the days and export a printable travel book.",
          icon: <Banknote size={17} />,
        },
        {
          href: `${base}/offline`,
          title: "Offline & sync",
          description: "Snapshot the confirmed plan and sync offline captures.",
          icon: <CloudOff size={17} />,
        },
        {
          href: `${base}/assistant`,
          title: "Ask SAFAR",
          description: "Grounded answers about this trip only.",
          icon: <MessageSquare size={17} />,
        },
      ],
    },
  ];

  return (
    <div className="space-y-5">
      <div>
        <p className="eyebrow">Everything else</p>
        <h2 className="mt-1 text-2xl">{trip.data?.name || "Trip"} tools</h2>
        <p className="mt-1 max-w-prose text-sm text-muted">
          Every tool here reads or proposes. The confirmed itinerary only changes through proposals, voting and
          owner/admin approval.
        </p>
      </div>

      {groups.map((group) => (
        <div key={group.title} className="space-y-2.5">
          <div className="flex items-baseline justify-between gap-3">
            <h3 className="text-lg">{group.title}</h3>
            <span className="text-[12px] text-faint">{group.hint}</span>
          </div>
          <div className="grid gap-2.5 sm:grid-cols-2">
            {group.entries.map((entry) => (
              <Link key={entry.href} href={entry.href}>
                <Card className="flex h-full items-start gap-3">
                  <span className="mt-0.5 inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-line bg-raised text-ember">
                    {entry.icon}
                  </span>
                  <div className="min-w-0">
                    <div className="flex items-center gap-1.5">
                      <p className="text-[13.5px] font-medium text-ink">{entry.title}</p>
                      {entry.badge ? <Badge tone="outline">{entry.badge}</Badge> : null}
                    </div>
                    <p className="mt-0.5 text-[12px] leading-5 text-muted">{entry.description}</p>
                  </div>
                </Card>
              </Link>
            ))}
          </div>
        </div>
      ))}

      <FlowNote icon={<Sparkles size={14} />}>
        Prefer the main tabs for Overview, Plan, Decide, Pulse, Engine, Map, Memories and Money. This hub collects
        the deeper tools without crowding the trip header.
      </FlowNote>
    </div>
  );
}
