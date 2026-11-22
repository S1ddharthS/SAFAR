"use client";

import { useParams } from "next/navigation";
import { useMemo, useState } from "react";
import { Compass, Footprints, MapPin, Navigation, Search } from "lucide-react";
import Link from "next/link";

import { TripMap, type MapMarker } from "@/components/TripMap";
import {
  Badge,
  Card,
  ErrorState,
  FlowNote,
  Input,
  PageSkeleton,
  Select,
  SectionTitle,
} from "@/components/ui";
import { useItinerary, useNearby, useTrip } from "@/lib/hooks";
import { formatMoney, titleCase } from "@/lib/utils";

export default function MapPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const itinerary = useItinerary(tripId);
  const [radius, setRadius] = useState(5);
  const [category, setCategory] = useState("");
  const [query, setQuery] = useState("");
  const nearby = useNearby(tripId, radius);

  const center = useMemo(
    () => ({ lat: trip.data?.base_lat || 0, lon: trip.data?.base_lon || 0 }),
    [trip.data],
  );

  const planMarkers: MapMarker[] = useMemo(
    () =>
      (itinerary.data?.items || [])
        .filter((item) => item.activity?.place)
        .map((item) => ({
          id: `item-${item.id}`,
          lat: item.activity!.place!.lat,
          lon: item.activity!.place!.lon,
          title: item.title,
          subtitle: `${String(item.day).slice(0, 10)} · ${item.start_time.slice(0, 5)}`,
          tone: "ember" as const,
        })),
    [itinerary.data],
  );

  const nearbyItems = useMemo(
    () =>
      (nearby.data?.items || []).filter((entry) => {
        const place = entry.activity.place;
        if (!place) return false;
        if (category && place.category.toLowerCase() !== category.toLowerCase()) return false;
        if (query && !entry.activity.name.toLowerCase().includes(query.toLowerCase())) return false;
        return true;
      }),
    [nearby.data, category, query],
  );

  const nearbyMarkers: MapMarker[] = nearbyItems
    .filter((entry) => entry.activity.place)
    .map((entry) => ({
      id: `nearby-${entry.activity.id}`,
      lat: entry.activity.place!.lat,
      lon: entry.activity.place!.lon,
      title: entry.activity.name,
      subtitle: `${entry.distance_km} km · ~${entry.travel_minutes} min`,
      tone: "jade" as const,
    }));

  if (trip.isLoading || itinerary.isLoading) return <PageSkeleton />;
  if (trip.error || !trip.data) {
    return <ErrorState error={trip.error || new Error("Trip not found")} retry={() => trip.refetch()} />;
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Map & nearby</p>
          <h2 className="mt-1 text-2xl">Where the journey happens</h2>
          <p className="mt-1 max-w-prose text-sm text-muted">
            The confirmed plan and catalog places within a radius of the shared trip base. Distances
            are straight-line estimates — not live routing, and never a live member location.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Select
            value={radius}
            onChange={(event) => setRadius(Number(event.target.value))}
            className="h-9 w-32"
            aria-label="Radius"
          >
            {[2, 5, 10, 20, 35].map((value) => (
              <option key={value} value={value}>
                {value} km radius
              </option>
            ))}
          </Select>
          <Select
            value={category}
            onChange={(event) => setCategory(event.target.value)}
            className="h-9 w-36"
            aria-label="Category"
          >
            <option value="">All categories</option>
            {["museum", "park", "market", "viewpoint", "restaurant", "landmark"].map((value) => (
              <option key={value} value={value}>
                {titleCase(value)}
              </option>
            ))}
          </Select>
        </div>
      </div>

      <Card className="p-0">
        {center.lat || center.lon ? (
          <TripMap
            center={center}
            markers={[...planMarkers, ...nearbyMarkers]}
            height={440}
          />
        ) : (
          <div className="px-6 py-16 text-center text-sm text-muted">
            This journey has no destination base yet. Set a destination to see the map.
          </div>
        )}
      </Card>

      <div className="flex flex-wrap items-center gap-3 text-[12px] text-faint">
        <span className="inline-flex items-center gap-1.5">
          <span className="h-2.5 w-2.5 rounded-full bg-ember" /> Confirmed plan
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className="h-2.5 w-2.5 rounded-full bg-jade" /> Nearby catalog
        </span>
        <span className="inline-flex items-center gap-1.5">
          <Navigation size={12} /> Base: {center.lat.toFixed(3)}, {center.lon.toFixed(3)}
        </span>
      </div>

      <section className="space-y-3">
        <SectionTitle
          title="Nearby places"
          hint={`${nearbyItems.length} within ${radius} km`}
          action={
            <div className="relative">
              <Search size={14} className="absolute left-3 top-2.5 text-faint" />
              <Input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Filter by name"
                className="h-9 w-44 pl-8"
              />
            </div>
          }
        />
        {nearby.isLoading ? (
          <PageSkeleton />
        ) : nearby.error ? (
          <ErrorState error={nearby.error} retry={() => nearby.refetch()} />
        ) : nearbyItems.length === 0 ? (
          <p className="rounded-2xl border border-dashed border-line px-4 py-8 text-center text-sm text-muted">
            Nothing in the catalog matches this filter. Try a larger radius.
          </p>
        ) : (
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {nearbyItems.map((entry) => (
              <div
                key={entry.activity.id}
                className="rounded-2xl border border-line bg-surface p-3.5"
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="truncate text-sm text-ink">{entry.activity.name}</p>
                    <p className="mt-0.5 flex items-center gap-1 text-[12px] text-faint">
                      <MapPin size={11} /> {entry.activity.place?.category || "place"}
                    </p>
                  </div>
                  <Badge tone="jade">
                    <Footprints size={10} /> {entry.distance_km} km
                  </Badge>
                </div>
                <p className="mt-2 line-clamp-2 text-[12px] leading-5 text-muted">
                  {entry.activity.description}
                </p>
                <div className="mt-2.5 flex items-center justify-between">
                  <span className="font-mono text-[12px] text-faint">
                    {formatMoney(entry.activity.price_estimate, entry.activity.currency)} ·{" "}
                    {entry.activity.duration_minutes} min
                  </span>
                  <Link
                    href={`/trips/${tripId}/places/${entry.activity.id}`}
                    className="text-[12px] text-ember hover:underline"
                  >
                    Details →
                  </Link>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <FlowNote icon={<Compass size={15} />}>
        {nearby.data?.disclosure ||
          "Distances are straight-line estimates. Travel times are not live ETAs, and exact live member locations are never exposed."}
      </FlowNote>
    </div>
  );
}
