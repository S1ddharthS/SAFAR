"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Activity,
  AlertTriangle,
  Camera,
  Footprints,
  GitBranch,
  Radar,
  ShieldAlert,
  Timer,
  Waypoints,
} from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";

import {
  Badge,
  Button,
  Card,
  ErrorState,
  Field,
  FlowNote,
  Input,
  PageSkeleton,
  Progress,
  SectionTitle,
  Select,
  Stat,
} from "@/components/ui";
import { api } from "@/lib/api";
import {
  useCapsules,
  useItinerary,
  useSearch,
  useShadowplans,
  useTrip,
} from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { cn, errorMessage, formatDate, formatDateTime } from "@/lib/utils";

interface Fragility {
  resilience_score: number | null;
  label: string;
  summary: { comfortable: number; tight: number; risky: number };
  disclosure?: string;
  days: {
    day: string;
    legs: {
      item_id: string;
      title: string;
      start_time: string;
      end_time: string;
      buffer_minutes: number | null;
      buffer_status: string;
      travel_minutes: number;
      travel_km: number;
      protected: boolean;
    }[];
    alternative_timings: { item_id: string; suggestion: string; minutes: number }[];
  }[];
}

interface Domino {
  day: string;
  disruption: { item_id: string; title: string; delay_minutes: number };
  affected: { item_id: string; title: string; slip_minutes: number; new_start: string; is_source: boolean; protected: boolean }[];
  unaffected: { item_id: string; title: string; reason: string }[];
  minimum_repairs_needed: number;
  repair_options: { item_id: string; title: string; options: string[] }[];
  disclosure?: string;
}

interface Effort {
  effort_points: number;
  effort_level: string;
  walking_km_estimate: number;
  walking_minutes_estimate: number;
  transitions: number;
  protected_rest_minutes: number;
  heat_exposure: string;
  accessibility_note: string;
  disclosure: string;
}

export default function InsightsPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const itinerary = useItinerary(tripId);
  const shadowplans = useShadowplans(tripId);
  const capsules = useCapsules(tripId);
  const catalog = useSearch({ destination_id: trip.data?.destination_id || undefined, limit: 60 });
  const queryClient = useQueryClient();
  const { push } = useToasts();

  const [dominoItem, setDominoItem] = useState("");
  const [delay, setDelay] = useState("45");

  const fragility = useQuery({
    queryKey: ["fragility", tripId],
    queryFn: () => api<Fragility>(`/api/trips/${tripId}/fragility`),
    enabled: Boolean(tripId),
  });
  const effort = useQuery({
    queryKey: ["effort", tripId],
    queryFn: () => api<Effort>(`/api/trips/${tripId}/effort`),
    enabled: Boolean(tripId),
  });
  const domino = useQuery({
    queryKey: ["domino", tripId, dominoItem, delay],
    queryFn: () =>
      api<Domino>(`/api/trips/${tripId}/domino?item_id=${dominoItem}&delay_minutes=${Number(delay) || 0}`),
    enabled: Boolean(tripId && dominoItem),
    retry: false,
  });

  const [shadowItem, setShadowItem] = useState("");
  const [shadowBackup, setShadowBackup] = useState("");
  const [shadowNotes, setShadowNotes] = useState("");
  const [ttl, setTtl] = useState("72");

  const refresh = () => {
    queryClient.invalidateQueries({ queryKey: ["shadowplans", tripId] });
    queryClient.invalidateQueries({ queryKey: ["capsules", tripId] });
  };

  const createShadow = useMutation({
    mutationFn: () =>
      api(`/api/trips/${tripId}/shadowplans`, {
        method: "POST",
        body: { item_id: shadowItem, backup_activity_id: shadowBackup, notes: shadowNotes || null },
      }),
    onSuccess: () => {
      push("Shadowplan saved", "A backup exists without changing the confirmed plan.", "success");
      setShadowItem("");
      setShadowBackup("");
      setShadowNotes("");
      refresh();
    },
    onError: (error) => push("Could not save shadowplan", errorMessage(error), "error"),
  });

  const createCapsule = useMutation({
    mutationFn: () =>
      api(`/api/trips/${tripId}/capsules`, { method: "POST", body: { ttl_hours: Number(ttl) || 72 } }),
    onSuccess: () => {
      push("Capsule created", "It goes stale automatically after the TTL.", "success");
      refresh();
    },
    onError: (error) => push("Could not create capsule", errorMessage(error), "error"),
  });

  const items = itinerary.data?.items ?? [];

  if (itinerary.isLoading) return <PageSkeleton />;

  const backupName = (activityId: string) =>
    catalog.data?.items.find((entry) => entry.activity.id === activityId)?.activity.name || "Backup activity";

  return (
    <div className="space-y-6">
      <div>
        <p className="eyebrow">Plan intelligence</p>
        <h2 className="mt-1 text-2xl">Fragility, effort, dominoes and backups</h2>
        <p className="mt-1 max-w-prose text-sm text-muted">
          These tools read the confirmed plan. None of them change it — every change still goes through a
          proposal and approval.
        </p>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="space-y-4">
          <SectionTitle
            title="Fragility radar"
            hint="How much buffer each day actually has"
            action={<Radar size={16} className="text-faint" />}
          />
          {fragility.isLoading ? (
            <p className="text-sm text-muted">Analysing buffers…</p>
          ) : fragility.error ? (
            <ErrorState error={fragility.error} retry={() => fragility.refetch()} />
          ) : fragility.data ? (
            <div className="space-y-3">
              <div className="flex items-end justify-between gap-3">
                <div>
                  <p className="font-display text-3xl leading-none">
                    {fragility.data.resilience_score === null ? "—" : fragility.data.resilience_score}
                    <span className="text-sm text-faint"> /100</span>
                  </p>
                  <p className="mt-1 text-[12px] text-muted">{fragility.data.label}</p>
                </div>
                <div className="flex gap-1.5">
                  <Badge tone="jade">{fragility.data.summary.comfortable} comfy</Badge>
                  <Badge tone="ember">{fragility.data.summary.tight} tight</Badge>
                  <Badge tone="rose">{fragility.data.summary.risky} risky</Badge>
                </div>
              </div>
              {fragility.data.resilience_score !== null ? (
                <Progress
                  value={fragility.data.resilience_score}
                  tone={fragility.data.resilience_score >= 70 ? "jade" : "ember"}
                />
              ) : null}
              <div className="space-y-2">
                {fragility.data.days.map((day) => (
                  <details key={day.day} className="rounded-xl border border-line bg-surface px-3 py-2">
                    <summary className="cursor-pointer text-[12.5px] font-medium text-ink">
                      {formatDate(day.day)}
                      <span className="ml-2 text-[10.5px] font-normal text-faint">
                        {day.legs.length} leg(s)
                        {day.alternative_timings.length ? ` · ${day.alternative_timings.length} suggestion(s)` : ""}
                      </span>
                    </summary>
                    <div className="mt-2 space-y-1.5">
                      {day.legs.map((leg) => (
                        <div key={leg.item_id} className="flex items-center justify-between gap-2 text-[12px]">
                          <span className="text-muted">
                            {leg.start_time} · {leg.title}
                            {leg.protected ? " · protected" : ""}
                          </span>
                          <span
                            className={cn(
                              "font-mono",
                              leg.buffer_status === "comfortable"
                                ? "text-jade"
                                : leg.buffer_status === "tight"
                                  ? "text-ember"
                                  : "text-rose",
                            )}
                          >
                            {leg.buffer_minutes === null ? "—" : `${leg.buffer_minutes}m`}
                          </span>
                        </div>
                      ))}
                      {day.alternative_timings.map((alt) => (
                        <p key={alt.item_id} className="rounded-lg bg-ember-soft/40 px-2 py-1 text-[12px] text-ember">
                          {alt.suggestion}
                        </p>
                      ))}
                    </div>
                  </details>
                ))}
              </div>
              {fragility.data.disclosure ? (
                <FlowNote icon={<ShieldAlert size={14} />}>{fragility.data.disclosure}</FlowNote>
              ) : null}
            </div>
          ) : null}
        </Card>

        <Card className="space-y-4">
          <SectionTitle title="Effort budget" hint="How demanding the plan is" action={<Footprints size={16} className="text-faint" />} />
          {effort.isLoading ? (
            <p className="text-sm text-muted">Measuring effort…</p>
          ) : effort.error ? (
            <ErrorState error={effort.error} retry={() => effort.refetch()} />
          ) : effort.data ? (
            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-2">
                <Stat label="Effort" value={effort.data.effort_level} tone="ember" hint={`${effort.data.effort_points} points`} />
                <Stat label="Walking" value={`${effort.data.walking_km_estimate} km`} tone="ink" hint={`~${effort.data.walking_minutes_estimate} min`} />
                <Stat label="Transitions" value={effort.data.transitions} tone="ink" />
                <Stat label="Protected rest" value={`${effort.data.protected_rest_minutes} min`} tone="jade" />
              </div>
              <p className="text-[12px] leading-5 text-muted">{effort.data.accessibility_note}</p>
              <FlowNote icon={<Activity size={14} />}>{effort.data.disclosure}</FlowNote>
            </div>
          ) : null}
        </Card>
      </div>

      <Card className="space-y-4">
        <SectionTitle title="Domino map" hint="What one delay does to the rest of the day" action={<Waypoints size={16} className="text-faint" />} />
        <div className="grid gap-3 sm:grid-cols-[1fr_auto]">
          <Field label="If this item is disrupted">
            <Select value={dominoItem} onChange={(event) => setDominoItem(event.target.value)}>
              <option value="">Choose an item…</option>
              {items.map((item) => (
                <option key={item.id} value={item.id}>
                  {formatDate(item.day)} · {item.start_time} · {item.title}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Delay (minutes)">
            <Input type="number" min="0" max="600" value={delay} onChange={(event) => setDelay(event.target.value)} className="w-28" />
          </Field>
        </div>

        {!dominoItem ? (
          <p className="text-sm text-muted">Pick an item to see how a delay propagates.</p>
        ) : domino.isLoading ? (
          <p className="text-sm text-muted">Tracing the chain…</p>
        ) : domino.error ? (
          <ErrorState error={domino.error} retry={() => domino.refetch()} />
        ) : domino.data ? (
          <div className="space-y-3">
            <div className="flex flex-wrap items-center gap-1.5">
              <Badge tone="rose">
                <Timer size={10} /> {domino.data.disruption.title} +{domino.data.disruption.delay_minutes}m
              </Badge>
              <Badge tone="outline">{domino.data.affected.length} affected</Badge>
              <Badge tone="jade">{domino.data.unaffected.length} absorbed</Badge>
            </div>
            <div className="space-y-2">
              {domino.data.affected.map((entry) => (
                <div
                  key={entry.item_id}
                  className={cn(
                    "rounded-xl border px-3 py-2",
                    entry.is_source ? "border-rose/30 bg-rose/5" : "border-ember/20 bg-ember-soft/30",
                  )}
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="text-[12px] text-ink">
                      {entry.title} {entry.protected ? <Badge tone="jade">protected</Badge> : null}
                    </span>
                    <span className="font-mono text-[12px] text-muted">
                      +{entry.slip_minutes}m → {entry.new_start}
                    </span>
                  </div>
                </div>
              ))}
              {domino.data.unaffected.length ? (
                <p className="text-[12px] text-faint">
                  Absorbed by buffers: {domino.data.unaffected.map((entry) => entry.title).join(", ")}
                </p>
              ) : null}
            </div>
            {domino.data.repair_options.length ? (
              <div className="space-y-1.5">
                <p className="text-[12px] uppercase tracking-editorial text-faint">Repair options</p>
                {domino.data.repair_options.map((repair) => (
                  <div key={repair.item_id} className="rounded-xl border border-line bg-surface px-3 py-2">
                    <p className="text-[12px] font-medium text-ink">{repair.title}</p>
                    <ul className="mt-1 space-y-0.5">
                      {repair.options.map((option) => (
                        <li key={option} className="text-[12px] text-muted">
                          · {option}
                        </li>
                      ))}
                    </ul>
                  </div>
                ))}
              </div>
            ) : null}
            {domino.data.disclosure ? <p className="text-[12px] text-faint">{domino.data.disclosure}</p> : null}
          </div>
        ) : null}
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="space-y-3">
          <SectionTitle title="Shadowplans" hint="Backups that never touch the confirmed plan" action={<GitBranch size={16} className="text-faint" />} />
          {shadowplans.data?.items.length ? (
            <div className="space-y-2">
              {shadowplans.data.items.map((plan) => {
                const item = items.find((entry) => entry.id === plan.item_id);
                return (
                  <div key={plan.id} className="rounded-xl border border-line bg-surface px-3 py-2">
                    <p className="text-[12px] text-ink">
                      If <span className="font-medium">{item?.title || "item"}</span> fails →{" "}
                      {backupName(plan.backup_activity_id)}
                    </p>
                    <p className="text-[10.5px] text-faint">
                      {String(plan.readiness?.status || "ready")} · {formatDateTime(plan.created_at)}
                    </p>
                    {plan.notes ? <p className="mt-0.5 text-[12px] text-muted">{plan.notes}</p> : null}
                  </div>
                );
              })}
            </div>
          ) : (
            <p className="text-sm text-muted">No backups yet.</p>
          )}
          <form
            className="space-y-2 border-t border-line pt-3"
            onSubmit={(event) => {
              event.preventDefault();
              createShadow.mutate();
            }}
          >
            <Field label="If this item fails">
              <Select value={shadowItem} onChange={(event) => setShadowItem(event.target.value)}>
                <option value="">Choose an item…</option>
                {items.map((item) => (
                  <option key={item.id} value={item.id}>
                    {formatDate(item.day)} · {item.title}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Use this backup">
              <Select value={shadowBackup} onChange={(event) => setShadowBackup(event.target.value)}>
                <option value="">Choose an activity…</option>
                {(catalog.data?.items ?? []).map((entry) => (
                  <option key={entry.activity.id} value={entry.activity.id}>
                    {entry.activity.name}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Note" hint="Optional">
              <Input value={shadowNotes} onChange={(event) => setShadowNotes(event.target.value)} placeholder="Why this backup" />
            </Field>
            <Button type="submit" size="sm" variant="secondary" loading={createShadow.isPending} disabled={!shadowItem || !shadowBackup}>
              Save shadowplan
            </Button>
          </form>
        </Card>

        <Card className="space-y-3">
          <SectionTitle title="Journey capsules" hint="Shareable snapshots that expire" action={<Camera size={16} className="text-faint" />} />
          {capsules.data?.items.length ? (
            <div className="space-y-2">
              {capsules.data.items.map((capsule) => (
                <div key={capsule.id} className="rounded-xl border border-line bg-surface px-3 py-2">
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-[12px] text-ink">Capsule {capsule.id.slice(0, 8)}</p>
                    <Badge tone={capsule.stale ? "rose" : "jade"}>{capsule.stale ? "stale" : "fresh"}</Badge>
                  </div>
                  <p className="text-[10.5px] text-faint">
                    Created {formatDateTime(capsule.created_at)} · stale after {formatDateTime(capsule.stale_after)}
                  </p>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-muted">No capsules yet.</p>
          )}
          <div className="flex items-end gap-2 border-t border-line pt-3">
            <Field label="TTL (hours)">
              <Input type="number" min="1" max="720" value={ttl} onChange={(event) => setTtl(event.target.value)} className="w-28" />
            </Field>
            <Button size="sm" variant="secondary" onClick={() => createCapsule.mutate()} loading={createCapsule.isPending}>
              Create capsule
            </Button>
          </div>
          <FlowNote icon={<Camera size={14} />}>
            Capsules snapshot the confirmed plan and meeting points only. Private budgets and private memories are
            never included.
          </FlowNote>
        </Card>
      </div>

      <Link href={`/trips/${tripId}/watch`} className="block">
        <Card className="flex items-center justify-between gap-3">
          <div>
            <p className="text-[14px] font-medium text-ink">Material Change Watch</p>
            <p className="text-[12px] text-muted">Track opening hours, prices and step-free status.</p>
          </div>
          <Badge tone="ember">
            <AlertTriangle size={10} /> Open
          </Badge>
        </Card>
      </Link>
    </div>
  );
}
