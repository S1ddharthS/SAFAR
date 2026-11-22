"use client";

import { useEffect, useRef } from "react";

import type { Map as LeafletMap, Marker } from "leaflet";

export interface MapMarker {
  id: string;
  lat: number;
  lon: number;
  title: string;
  subtitle?: string;
  tone?: "ember" | "jade" | "ink";
}

export function TripMap({
  center,
  markers,
  zoom = 12,
  onSelect,
  height = 420,
}: {
  center: { lat: number; lon: number };
  markers: MapMarker[];
  zoom?: number;
  onSelect?: (id: string) => void;
  height?: number;
}) {
  const container = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const markerRefs = useRef<Record<string, Marker>>({});
  const selectRef = useRef(onSelect);
  selectRef.current = onSelect;

  useEffect(() => {
    let cancelled = false;
    let map: LeafletMap | null = null;
    (async () => {
      const L = (await import("leaflet")).default;
      if (cancelled || !container.current) return;
      map = L.map(container.current, {
        center: [center.lat, center.lon],
        zoom,
        zoomControl: true,
        attributionControl: true,
      });
      L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      }).addTo(map);
      mapRef.current = map;
    })();
    return () => {
      cancelled = true;
      mapRef.current?.remove();
      mapRef.current = null;
      markerRefs.current = {};
    };
    // Center and zoom are initial values; updates handled in the marker effect.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const L = (await import("leaflet")).default;
      const map = mapRef.current;
      if (cancelled || !map) return;

      Object.values(markerRefs.current).forEach((marker) => marker.remove());
      markerRefs.current = {};

      const border = { ember: "#b45309", jade: "#0f766e", ink: "#17150f" };

      markers.forEach((marker) => {
        const color = border[marker.tone || "ember"];
        const icon = L.divIcon({
          className: "",
          html: `<span style="display:block;width:14px;height:14px;border-radius:9999px;background:${color};border:3px solid #fffdf8;box-shadow:0 2px 8px rgba(0,0,0,.35)"></span>`,
          iconSize: [14, 14],
          iconAnchor: [7, 7],
        });
        const instance = L.marker([marker.lat, marker.lon], { icon })
          .addTo(map)
          .bindTooltip(
            `<strong>${escapeHtml(marker.title)}</strong>${
              marker.subtitle ? `<br/><span>${escapeHtml(marker.subtitle)}</span>` : ""
            }`,
            { direction: "top", offset: [0, -8] },
          );
        instance.on("click", () => selectRef.current?.(marker.id));
        markerRefs.current[marker.id] = instance;
      });

      if (markers.length > 0) {
        const bounds = L.latLngBounds(markers.map((marker) => [marker.lat, marker.lon]));
        map.fitBounds(bounds.pad(0.25), { maxZoom: 14 });
      } else {
        map.setView([center.lat, center.lon], zoom);
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [JSON.stringify(markers)]);

  return (
    <div
      ref={container}
      style={{ height }}
      className="z-0 w-full overflow-hidden rounded-3xl border border-line bg-raised"
      role="application"
      aria-label="Trip map"
    />
  );
}

function escapeHtml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
