"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Activity, BatteryCharging, Clock, Compass, EyeOff, Send, ShieldCheck, Users } from "lucide-react";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  FlowNote,
  Input,
  PageSkeleton,
  Progress,
  SectionTitle,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { usePulse } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { Pulse } from "@/lib/types";
import { cn, formatDate, titleCase, todayIso } from "@/lib/utils";

const ENERGY_LABELS = ["Very low", "Low", "Steady", "Good", "Full of energy"];
const INTERESTS = ["culture", "food", "nature", "adventure", "shopping", "relaxation", "history", "local"];
const PREFS = ["indoor", "outdoor", "walkable", "iconic", "quiet", "lively"];

export default function PulsePage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const pulse = usePulse(tripId);
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);
  const [day, setDay] = useState(todayIso());
  const [form, setForm] = useState({
    energy: 3,
    interests: [] as string[],
    available_minutes: 240,
    budget_comfort: 3,
    radius_km: 10,
    activity_prefs: [] as string[],
    note: "",
  });
  const [affected, setAffected] = useState<{ item_id: string; title: string; reasons: string[] }[]>([]);
  const [compassNote, setCompassNote] = useState("");

  useEffect(() => {
    const requested = new URLSearchParams(window.location.search).get("date");
    if (requested && /^\d{4}-\d{2}-\d{2}$/.test(requested)) {
      setDay(requested);
    }
  }, []);

  useEffect(() => {
    const mine = pulse.data?.my_pulse;
    if (mine) {
      setForm({
        energy: mine.energy,
        interests: mine.interests || [],
        available_minutes: mine.available_minutes ?? 240,
        budget_comfort: mine.budget_comfort ?? 3,
        radius_km: mine.radius_km ?? 10,
        activity_prefs: mine.activity_prefs || [],
        note: mine.note || "",
      });
    }
  }, [pulse.data]);

  const save = useMutation({
    mutationFn: () =>
      api<{
        affected_items: { item_id: string; title: string; reasons: string[] }[];
        constraint_compass: { summary: string; note: string };
      }>(`/api/trips/${tripId}/pulse`, {
        method: "PUT",
        body: {
          pulse_date: day,
          energy: form.energy,
          interests: form.interests,
          available_minutes: form.available_minutes || null,
          budget_comfort: form.budget_comfort,
          radius_km: form.radius_km,
          activity_prefs: form.activity_prefs,
          note: form.note || null,
        },
      }),
    onSuccess: (data) => {
      setAffected(data.affected_items || []);
      setCompassNote(`${data.constraint_compass.summary} ${data.constraint_compass.note}`);
      push("Pulse shared", "Today's recommendations will respect these limits.", "success");
      queryClient.invalidateQueries({ queryKey: ["pulse", tripId] });
      queryClient.invalidateQueries({ queryKey: ["engine", tripId] });
    },
    onError: (error) => push("Could not save pulse", (error as Error).message, "error"),
  });

  function toggle(list: string[], value: string) {
    return list.includes(value) ? list.filter((entry) => entry !== value) : [...list, value];
  }

  if (pulse.isLoading) return <PageSkeleton />;
  if (pulse.error || !pulse.data) {
    return <ErrorState error={pulse.error} retry={() => pulse.refetch()} />;
  }

  const data = pulse.data;
  const others = data.items.filter((item) => !item.is_self);
  const mine = data.my_pulse;

  return (
    <div className="space-y-6">
      <div>
        <p className="eyebrow">Trip Pulse · {formatDate(day)}</p>
        <h2 className="mt-1 text-2xl">How is today?</h2>
        <p className="mt-1 max-w-prose text-sm text-muted">
          Share the minimum the group needs: energy, available time and what you feel like. Budget
          comfort and notes stay private to you.
        </p>
      </div>

      <div className="grid gap-4 lg:grid-cols-[1.1fr_1fr]">
        <Card className="space-y-5">
          <div className="flex items-center justify-between">
            <h3 className="text-lg">Your pulse</h3>
            {mine ? <Badge tone="jade">Shared</Badge> : <Badge tone="ember">Not shared</Badge>}
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between text-[13px]">
              <span className="flex items-center gap-1.5 text-ink">
                <BatteryCharging size={14} className="text-ember" /> Energy
              </span>
              <span className="text-muted">{ENERGY_LABELS[form.energy - 1]}</span>
            </div>
            <input
              type="range"
              min="1"
              max="5"
              value={form.energy}
              onChange={(event) => setForm({ ...form, energy: Number(event.target.value) })}
              className="w-full accent-ember"
              aria-label="Energy"
            />
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between text-[13px]">
              <span className="flex items-center gap-1.5 text-ink">
                <Clock size={14} className="text-ember" /> Time available
              </span>
              <span className="text-muted">{form.available_minutes} min</span>
            </div>
            <input
              type="range"
              min="30"
              max="720"
              step="30"
              value={form.available_minutes}
              onChange={(event) =>
                setForm({ ...form, available_minutes: Number(event.target.value) })
              }
              className="w-full accent-ember"
              aria-label="Available minutes"
            />
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between text-[13px]">
              <span className="flex items-center gap-1.5 text-ink">
                <Compass size={14} className="text-ember" /> Radius willing to travel
              </span>
              <span className="text-muted">{form.radius_km} km</span>
            </div>
            <input
              type="range"
              min="1"
              max="40"
              value={form.radius_km}
              onChange={(event) => setForm({ ...form, radius_km: Number(event.target.value) })}
              className="w-full accent-ember"
              aria-label="Radius in kilometres"
            />
          </div>

          <div className="space-y-2">
            <p className="text-[13px] text-ink">Interests today</p>
            <div className="flex flex-wrap gap-1.5">
              {INTERESTS.map((interest) => (
                <button
                  key={interest}
                  type="button"
                  aria-pressed={form.interests.includes(interest)}
                  onClick={() => setForm({ ...form, interests: toggle(form.interests, interest) })}
                  className={cn(
                    "rounded-full border px-2.5 py-1 text-[12px] transition-colors",
                    form.interests.includes(interest)
                      ? "border-ember bg-ember-soft text-ember"
                      : "border-line bg-surface text-muted hover:border-ink/30 hover:text-ink",
                  )}
                >
                  {titleCase(interest)}
                </button>
              ))}
            </div>
          </div>

          <div className="space-y-2">
            <p className="text-[13px] text-ink">Prefer</p>
            <div className="flex flex-wrap gap-1.5">
              {PREFS.map((pref) => (
                <button
                  key={pref}
                  type="button"
                  aria-pressed={form.activity_prefs.includes(pref)}
                  onClick={() =>
                    setForm({ ...form, activity_prefs: toggle(form.activity_prefs, pref) })
                  }
                  className={cn(
                    "rounded-full border px-2.5 py-1 text-[12px] transition-colors",
                    form.activity_prefs.includes(pref)
                      ? "border-jade bg-jade-soft text-jade"
                      : "border-line bg-surface text-muted hover:border-ink/30 hover:text-ink",
                  )}
                >
                  {titleCase(pref)}
                </button>
              ))}
            </div>
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between text-[13px]">
              <span className="flex items-center gap-1.5 text-ink">
                <EyeOff size={14} className="text-ember" /> Budget comfort
              </span>
              <span className="inline-flex items-center gap-1 text-[12px] text-faint">
                private to you
              </span>
            </div>
            <div className="grid grid-cols-5 gap-1">
              {[1, 2, 3, 4, 5].map((value) => (
                <button
                  key={value}
                  type="button"
                  aria-pressed={form.budget_comfort === value}
                  aria-label={`Budget comfort ${value} of 5`}
                  onClick={() => setForm({ ...form, budget_comfort: value })}
                  className={cn(
                    "rounded-lg border py-1.5 text-xs transition-colors",
                    form.budget_comfort === value
                      ? "border-ink bg-ink text-paper"
                      : "border-line bg-surface text-muted",
                  )}
                >
                  {value}
                </button>
              ))}
            </div>
            <p className="text-[12px] text-faint">Never shown to other members.</p>
          </div>

          <Field label="Private note" hint="Only you see this. The engine uses it; the group cannot.">
            <Textarea
              value={form.note}
              onChange={(event) => setForm({ ...form, note: event.target.value })}
              placeholder="Feeling a bit tired after yesterday…"
              className="min-h-20"
            />
          </Field>

          <Button className="w-full" loading={save.isPending} onClick={() => save.mutate()}>
            <Send size={14} /> {mine ? "Update my pulse" : "Share my pulse"}
          </Button>
        </Card>

        <div className="space-y-4">
          <Card className="space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-lg">Group pulse</h3>
              <span className="inline-flex items-center gap-1 text-[12px] text-faint">
                <Users size={12} /> {data.coverage.shared}/{data.coverage.members} shared
              </span>
            </div>
            <Progress value={data.coverage.shared} max={Math.max(1, data.coverage.members)} tone="jade" />
            {others.length === 0 ? (
              <EmptyState
                title="No one else has shared yet"
                description="Pulses are optional. The engine still respects hard constraints from profiles."
                icon={<Activity size={22} />}
              />
            ) : (
              <div className="space-y-3">
                {others.map((item: Pulse) => (
                  <div key={item.id} className="rounded-2xl border border-line bg-raised/60 p-3">
                    <div className="flex items-center justify-between">
                      <p className="text-sm text-ink">{item.author?.display_name || "Traveller"}</p>
                      <span className="font-mono text-[10px] text-faint">energy {item.energy}/5</span>
                    </div>
                    <div className="mt-1.5 flex flex-wrap gap-1">
                      {(item.interests || []).map((interest) => (
                        <span
                          key={interest}
                          className="rounded-full bg-surface px-2 py-0.5 text-[10.5px] text-muted"
                        >
                          {interest}
                        </span>
                      ))}
                      {item.available_minutes ? (
                        <span className="rounded-full bg-surface px-2 py-0.5 text-[10.5px] text-muted">
                          {item.available_minutes} min
                        </span>
                      ) : null}
                    </div>
                  </div>
                ))}
              </div>
            )}
            <p className="text-[12px] leading-5 text-faint">{data.privacy}</p>
          </Card>

          {affected.length || compassNote ? (
            <Card className="space-y-3 border-ember/30">
              <div className="flex items-center gap-2">
                <Compass size={16} className="text-ember" />
                <h3 className="text-lg">Constraint Compass</h3>
              </div>
              <p className="text-[13px] leading-5 text-muted">{compassNote}</p>
              {affected.map((item) => (
                <div key={item.item_id} className="rounded-xl border border-rose/20 bg-rose/5 p-3">
                  <p className="text-[13px] font-medium text-ink">{item.title}</p>
                  <ul className="mt-1 space-y-0.5 text-[12px] text-muted">
                    {item.reasons.map((reason) => (
                      <li key={reason}>· {reason}</li>
                    ))}
                  </ul>
                </div>
              ))}
              <p className="text-[12px] text-faint">
                Today-only check. Nothing was changed in the confirmed plan.
              </p>
            </Card>
          ) : null}

          <FlowNote icon={<ShieldCheck size={15} />}>
            Pulse values are used for today's recommendations only. Budget comfort and personal
            notes never leave your account.
          </FlowNote>
        </div>
      </div>
    </div>
  );
}
