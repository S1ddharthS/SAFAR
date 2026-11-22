"use client";

import { ArrowUpRight, Orbit, Users } from "lucide-react";
import Link from "next/link";

import {
  Badge,
  Card,
  EmptyState,
  PageHeader,
  PageSkeleton,
  SectionTitle,
} from "@/components/ui";
import { useCircles } from "@/lib/hooks";

export default function CirclesPage() {
  const circles = useCircles();
  if (circles.isLoading) return <PageSkeleton />;

  const items = circles.data?.items ?? [];

  return (
    <div className="space-y-7">
      <PageHeader
        eyebrow="Travel circles"
        title="Small groups, shared obsessions"
        description="Circles are public communities around a theme. Joining makes you a member; posting shares with the circle, not the open internet."
      />

      {items.length === 0 ? (
        <EmptyState
          icon={<Orbit size={26} />}
          title="No circles yet"
          description="Circles appear here once the catalog is seeded or a member creates one."
        />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {items.map((circle) => (
            <Link key={circle.id} href={`/circles/${circle.id}`} className="group block">
              <Card className="flex h-full flex-col">
                <div className="flex items-start justify-between gap-2">
                  <span className="flex h-10 w-10 items-center justify-center rounded-2xl border border-line bg-raised text-ember">
                    <Orbit size={18} />
                  </span>
                  <Badge tone={circle.joined ? "jade" : "outline"}>
                    {circle.joined ? "Joined" : "Open"}
                  </Badge>
                </div>
                <h2 className="mt-4 text-xl leading-snug">{circle.name}</h2>
                <p className="mt-2 line-clamp-3 text-[12.5px] leading-5 text-muted">
                  {circle.description}
                </p>
                <div className="mt-3 flex flex-wrap gap-1.5">
                  {circle.interests.slice(0, 3).map((interest) => (
                    <Badge key={interest}>{interest}</Badge>
                  ))}
                </div>
                <div className="mt-auto flex items-center justify-between border-t border-line pt-3 text-[12px] text-faint">
                  <span className="inline-flex items-center gap-1.5">
                    <Users size={13} /> {circle.member_count} members
                  </span>
                  <ArrowUpRight
                    size={15}
                    className="transition-transform group-hover:-translate-y-0.5 group-hover:text-ink"
                  />
                </div>
              </Card>
            </Link>
          ))}
        </div>
      )}

      <div>
        <SectionTitle title="What a circle is not" hint="Respect by design" />
        <div className="grid gap-3 sm:grid-cols-3">
          {[
            { title: "Not a broadcasting channel", copy: "Posts stay inside the circle and can be moderated." },
            { title: "Not a location feed", copy: "No exact live location or private itinerary is exposed." },
            { title: "Not a popularity contest", copy: "Circles organise interests; they do not rank people." },
          ].map((item) => (
            <div key={item.title} className="rounded-2xl border border-line bg-surface p-4">
              <p className="text-[13px] font-medium">{item.title}</p>
              <p className="mt-1 text-[12px] leading-5 text-muted">{item.copy}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
