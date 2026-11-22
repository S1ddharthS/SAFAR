"use client";

import { Compass, Globe2, Search, SlidersHorizontal, Sparkles, X } from "lucide-react";
import { useMemo, useState } from "react";

import { DestinationCard } from "@/components/DestinationCard";
import {
  Button,
  Card,
  EmptyState,
  Input,
  LinkButton,
  PageHeader,
  PageSkeleton,
  Select,
} from "@/components/ui";
import { useDestinations, useMe } from "@/lib/hooks";
import { cn } from "@/lib/utils";

type SortKey = "fit" | "name" | "activities" | "season";

const SORTS: { value: SortKey; label: string }[] = [
  { value: "fit", label: "Best interest match" },
  { value: "name", label: "Name (A–Z)" },
  { value: "activities", label: "Most activities" },
  { value: "season", label: "Best this month" },
];

export default function DiscoverPage() {
  const destinations = useDestinations();
  const me = useMe();
  const [query, setQuery] = useState("");
  const [tag, setTag] = useState<string | null>(null);
  const [region, setRegion] = useState("all");
  const [sort, setSort] = useState<SortKey>("fit");

  const dna = me.data?.dna.scores ?? {};
  const topInterests = useMemo(
    () =>
      Object.entries(dna)
        .sort((a, b) => b[1] - a[1])
        .filter(([, score]) => score >= 55)
        .map(([key]) => key),
    [dna],
  );

  const items = useMemo(() => destinations.data ?? [], [destinations.data]);

  const tags = useMemo(() => {
    const counts = new Map<string, number>();
    items.forEach((item) => item.tags.forEach((t) => counts.set(t, (counts.get(t) ?? 0) + 1)));
    return [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([value]) => value);
  }, [items]);

  const regions = useMemo(
    () => [...new Set(items.map((item) => item.country))].sort(),
    [items],
  );

  const scored = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const month = new Date().getMonth() + 1;
    return items
      .filter((item) => {
        if (needle) {
          const haystack = `${item.name} ${item.country} ${item.region ?? ""} ${item.tags.join(" ")} ${item.description}`.toLowerCase();
          if (!haystack.includes(needle)) return false;
        }
        if (tag && !item.tags.includes(tag)) return false;
        if (region !== "all" && item.country !== region) return false;
        return true;
      })
      .map((item) => {
        const match = item.tags.filter((t) => topInterests.includes(t)).length;
        const fit = topInterests.length ? Math.round((match / Math.max(topInterests.length, item.tags.length)) * 100) : 0;
        const inSeason = item.best_months.length === 0 || item.best_months.includes(month);
        return { item, fit, inSeason, match };
      })
      .sort((a, b) => {
        if (sort === "name") return a.item.name.localeCompare(b.item.name);
        if (sort === "activities") return (b.item.activity_count ?? 0) - (a.item.activity_count ?? 0);
        if (sort === "season") return Number(b.inSeason) - Number(a.inSeason) || b.match - a.match;
        return b.match - a.match || (b.item.activity_count ?? 0) - (a.item.activity_count ?? 0);
      });
  }, [items, query, tag, region, sort, topInterests]);

  if (destinations.isLoading) return <PageSkeleton />;

  const activeFilters = (query ? 1 : 0) + (tag ? 1 : 0) + (region !== "all" ? 1 : 0);

  return (
    <div className="space-y-7">
      <PageHeader
        eyebrow="Discovery"
        title="Places with provenance"
        description="A curated catalog of destinations, each with its source and freshness attached. Interest match is a simple tag overlap with your Journey DNA — a heuristic, not a rating of the place."
        actions={
          <LinkButton href="/trips/new" variant="secondary" size="md">
            <Compass size={15} /> Plan from scratch
          </LinkButton>
        }
      />

      <Card className="space-y-4">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <div className="relative flex-1">
            <Search
              size={16}
              aria-hidden
              className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-faint"
            />
            <Input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search places, countries or interests"
              aria-label="Search destinations"
              className="pl-10"
            />
          </div>
          <div className="flex gap-2">
            <Select
              aria-label="Filter by country"
              value={region}
              onChange={(event) => setRegion(event.target.value)}
              className="min-w-[9rem]"
            >
              <option value="all">All countries</option>
              {regions.map((country) => (
                <option key={country} value={country}>
                  {country}
                </option>
              ))}
            </Select>
            <Select
              aria-label="Sort destinations"
              value={sort}
              onChange={(event) => setSort(event.target.value as SortKey)}
              className="min-w-[11rem]"
            >
              {SORTS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </Select>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          <span className="mr-1 inline-flex items-center gap-1 text-[11.5px] uppercase tracking-editorial text-faint">
            <SlidersHorizontal size={12} /> Interests
          </span>
          <button
            type="button"
            onClick={() => setTag(null)}
            aria-pressed={tag === null}
            className={cn(
              "rounded-full border px-3 py-1 text-[12px] transition-colors",
              tag === null
                ? "border-ember/40 bg-ember-soft text-ember"
                : "border-line bg-surface text-muted hover:border-ink/25 hover:text-ink",
            )}
          >
            All
          </button>
          {tags.map((value) => (
            <button
              key={value}
              type="button"
              onClick={() => setTag(tag === value ? null : value)}
              aria-pressed={tag === value}
              className={cn(
                "rounded-full border px-3 py-1 text-[12px] transition-colors",
                tag === value
                  ? "border-ember/40 bg-ember-soft text-ember"
                  : "border-line bg-surface text-muted hover:border-ink/25 hover:text-ink",
              )}
            >
              {value}
              {topInterests.includes(value) ? <span className="ml-1 text-ember">·</span> : null}
            </button>
          ))}
          {activeFilters ? (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                setQuery("");
                setTag(null);
                setRegion("all");
              }}
            >
              <X size={13} /> Clear {activeFilters}
            </Button>
          ) : null}
        </div>
      </Card>

      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className="text-[12.5px] text-muted" role="status" aria-live="polite">
          {scored.length} of {items.length} destination{items.length === 1 ? "" : "s"}
          {tag ? ` · tagged “${tag}”` : ""}
        </p>
        <p className="text-[12px] text-faint">
          Dots mark interests you scored highly in your Journey DNA.
        </p>
      </div>

      {items.length === 0 ? (
        <EmptyState
          icon={<Globe2 size={26} />}
          title="No destinations in the catalog yet"
          description="Ask an administrator to seed the catalog, or create a trip with an open destination."
          action={
            <LinkButton href="/trips/new" size="sm">
              Create a trip
            </LinkButton>
          }
        />
      ) : scored.length === 0 ? (
        <EmptyState
          icon={<Search size={24} />}
          title="Nothing matches those filters"
          description="Try a broader search, another interest, or clear the filters to see the whole catalog."
          action={
            <Button
              variant="secondary"
              size="sm"
              onClick={() => {
                setQuery("");
                setTag(null);
                setRegion("all");
              }}
            >
              Clear filters
            </Button>
          }
        />
      ) : (
        <div className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
          {scored.map(({ item }) => (
            <DestinationCard key={item.id} destination={item} />
          ))}
        </div>
      )}

      <Card className="border-dashed bg-raised/40">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <div className="max-w-prose">
            <p className="eyebrow">How discovery stays honest</p>
            <div className="mt-2 grid gap-3 sm:grid-cols-3">
              {[
                {
                  title: "Personal fit",
                  copy: "Tag overlap with your Journey DNA. A heuristic, never a live provider score.",
                },
                {
                  title: "Catalog freshness",
                  copy: "Prices and hours are labelled ESTIMATED unless a verified report exists.",
                },
                {
                  title: "Respect notes",
                  copy: "Fragile places carry guidance so discovery does not become extraction.",
                },
              ].map((item) => (
                <div key={item.title}>
                  <p className="flex items-center gap-1.5 text-[13px] font-medium text-ink">
                    <Sparkles size={13} className="text-ember" /> {item.title}
                  </p>
                  <p className="mt-1 text-[12px] leading-5 text-muted">{item.copy}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </Card>
    </div>
  );
}
