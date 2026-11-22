import { ArrowUpRight, MapPin } from "lucide-react";
import Link from "next/link";

import { DestinationImage } from "@/components/DestinationImage";
import { Badge, Card } from "@/components/ui";
import type { Destination } from "@/lib/types";
import { cn } from "@/lib/utils";

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const SOURCE_LABELS: Record<string, string> = {
  seed_catalog: "Curated catalog",
  official: "Official source",
  community: "Community reported",
};

export function sourceLabel(sourceType?: string | null) {
  if (!sourceType) return "Catalog";
  return SOURCE_LABELS[sourceType] ?? sourceType.replace(/_/g, " ");
}

export function monthLabel(months: number[]) {
  if (!months.length) return "Year-round";
  return months.map((month) => MONTHS[month - 1]).join(" · ");
}

export function DestinationCard({
  destination,
  className,
}: {
  destination: Destination;
  className?: string;
}) {
  return (
    <Link
      href={`/discover/${destination.id}`}
      className={cn("group block h-full rounded-3xl", className)}
    >
      <Card interactive className="flex h-full flex-col overflow-hidden p-0">
        <div className="relative aspect-[16/10] overflow-hidden">
          <DestinationImage
            name={destination.name}
            country={destination.country}
            heroImage={destination.hero_image}
            sizes="(max-width: 640px) 100vw, (max-width: 1280px) 50vw, 33vw"
            overlay="bottom"
            className="transition-transform duration-[900ms] ease-editorial group-hover:scale-[1.04]"
          />
          <div className="absolute inset-x-0 bottom-0 flex items-end justify-between gap-3 p-4">
            <div className="min-w-0">
              <p className="text-[10px] uppercase tracking-editorial text-paper/75">
                {destination.country}
              </p>
              <h3 className="mt-0.5 truncate text-[22px] leading-tight text-paper">
                {destination.name}
              </h3>
            </div>
            <span className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-paper/30 bg-paper/10 text-paper backdrop-blur transition-transform duration-300 group-hover:-translate-y-0.5">
              <ArrowUpRight size={16} />
            </span>
          </div>
        </div>

        <div className="flex flex-1 flex-col p-5">
          <p className="flex items-center gap-1 text-[12px] text-faint">
            <MapPin size={12} />
            {destination.region || destination.country}
          </p>
          <p className="mt-2.5 line-clamp-2 text-[13px] leading-6 text-muted">
            {destination.description}
          </p>
          <div className="mt-3.5 flex flex-wrap gap-1.5">
            {destination.tags.slice(0, 4).map((tag) => (
              <Badge key={tag} tone="outline">
                {tag}
              </Badge>
            ))}
          </div>
          <div className="mt-auto flex flex-wrap items-center justify-between gap-2 border-t border-line pt-3.5 text-[12px] text-faint">
            <span>
              {destination.activity_count
                ? `${destination.activity_count} curated activities`
                : "Activities in catalog"}
            </span>
            <span>{monthLabel(destination.best_months)}</span>
          </div>
        </div>
      </Card>
    </Link>
  );
}
