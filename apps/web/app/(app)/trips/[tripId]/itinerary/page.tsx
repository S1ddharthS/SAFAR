"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  CalendarDays,
  Check,
  Clock,
  History,
  Lock,
  Pencil,
  Plus,
  ShieldCheck,
  Sparkles,
  Trash2,
  Users,
} from "lucide-react";
import { useParams } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  FlowNote,
  IconButton,
  Input,
  LinkButton,
  Modal,
  PageHeader,
  PageSkeleton,
  SectionTitle,
  Select,
  Stat,
  Textarea,
  Toggle,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useItinerary, useMembers, useTrip } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { ItineraryItem } from "@/lib/types";
import { cn, formatDay, formatMoney, formatTime, todayIso } from "@/lib/utils";

function eachDay(start: string, end: string) {
  const days: string[] = [];
  const cursor = new Date(`${start.slice(0, 10)}T12:00:00`);
  const last = new Date(`${end.slice(0, 10)}T12:00:00`);
  while (cursor <= last && days.length < 60) {
    days.push(cursor.toISOString().slice(0, 10));
    cursor.setDate(cursor.getDate() + 1);
  }
  return days;
}

export default function ItineraryPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const itinerary = useItinerary(tripId);
  const members = useMembers(tripId);
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);

  const days = useMemo(
    () => (trip.data ? eachDay(trip.data.start_date, trip.data.end_date) : []),
    [trip.data],
  );
  const [selectedDay, setSelectedDay] = useState(todayIso());
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<ItineraryItem | null>(null);
  const [removing, setRemoving] = useState<ItineraryItem | null>(null);
  const [showVersions, setShowVersions] = useState(false);
  const activeDayRef = useRef<HTMLButtonElement>(null);
  const [draft, setDraft] = useState({
    title: "",
    day: "",
    start_time: "09:00",
    end_time: "",
    cost_estimate: "",
    notes: "",
    is_protected: false,
  });

  const isAdmin = trip.data?.my_role === "owner" || trip.data?.my_role === "admin";
  const currency = trip.data?.currency || "EUR";

  const items = itinerary.data?.items ?? [];
  const byDay = useMemo(() => {
    const map = new Map<string, ItineraryItem[]>();
    items.forEach((item) => {
      const key = String(item.day).slice(0, 10);
      map.set(key, [...(map.get(key) ?? []), item]);
    });
    return map;
  }, [items]);

  const effectiveDay = days.includes(selectedDay)
    ? selectedDay
    : days.includes(todayIso())
      ? todayIso()
      : days[0];

  const save = useMutation({
    mutationFn: (payload: Record<string, unknown>) =>
      editing
        ? api(`/api/trips/${tripId}/itinerary/items/${editing.id}`, {
            method: "PATCH",
            body: payload,
          })
        : api(`/api/trips/${tripId}/itinerary/items`, { method: "POST", body: payload }),
    onSuccess: () => {
      push(editing ? "Item updated" : "Item added", "A new plan version was recorded.", "success");
      queryClient.invalidateQueries({ queryKey: ["itinerary", tripId] });
      queryClient.invalidateQueries({ queryKey: ["trip", tripId] });
      setAdding(false);
      setEditing(null);
    },
    onError: (error) => push("Could not save", (error as Error).message, "error"),
  });

  const remove = useMutation({
    mutationFn: (itemId: string) =>
      api(`/api/trips/${tripId}/itinerary/items/${itemId}`, { method: "DELETE" }),
    onSuccess: () => {
      push("Item removed", "The change is versioned and visible to the group.", "success");
      setRemoving(null);
      queryClient.invalidateQueries({ queryKey: ["itinerary", tripId] });
    },
    onError: (error) => push("Could not remove", (error as Error).message, "error"),
  });

  const attendance = useMutation({
    mutationFn: ({ itemId, status }: { itemId: string; status: string }) =>
      api(`/api/trips/${tripId}/itinerary/items/${itemId}/attendance`, {
        method: "POST",
        body: { status },
      }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["itinerary", tripId] }),
    onError: (error) => push("Could not update", (error as Error).message, "error"),
  });

  function openAdd(day: string) {
    setEditing(null);
    setDraft({
      title: "",
      day,
      start_time: "09:00",
      end_time: "",
      cost_estimate: "",
      notes: "",
      is_protected: false,
    });
    setAdding(true);
  }

  function openReserve(day: string) {
    setEditing(null);
    setDraft({
      title: "Reserved free time",
      day,
      start_time: "09:00",
      end_time: "10:30",
      cost_estimate: "",
      notes: "Held open for rest, wandering, or the group's own plans.",
      is_protected: true,
    });
    setAdding(true);
  }

  function openEdit(item: ItineraryItem) {
    setEditing(item);
    setDraft({
      title: item.title,
      day: String(item.day).slice(0, 10),
      start_time: formatTime(item.start_time),
      end_time: formatTime(item.end_time),
      cost_estimate: item.cost_estimate ? String(item.cost_estimate) : "",
      notes: item.notes || "",
      is_protected: item.is_protected,
    });
    setAdding(true);
  }

  function submit() {
    if (!draft.title.trim()) {
      push("A title is required", undefined, "error");
      return;
    }
    if (draft.is_protected && !draft.end_time) {
      push(
        "Protected time needs an end time",
        "Reserve a start and end so the block is unambiguous.",
        "error",
      );
      return;
    }
    const payload: Record<string, unknown> = {
      day: draft.day || effectiveDay,
      start_time: draft.start_time,
      end_time: draft.end_time || null,
      title: draft.title.trim(),
      notes: draft.notes || null,
      cost_estimate: draft.cost_estimate ? Number(draft.cost_estimate) : null,
      is_protected: draft.is_protected,
    };
    if (editing) delete payload.day;
    save.mutate(payload);
  }

  useEffect(() => {
    activeDayRef.current?.scrollIntoView({ inline: "center", block: "nearest" });
  }, [effectiveDay]);

  if (trip.isLoading || itinerary.isLoading) return <PageSkeleton />;
  if (trip.error || !trip.data) {
    return <ErrorState error={trip.error || new Error("Trip not found")} retry={() => trip.refetch()} />;
  }
  if (itinerary.error || !itinerary.data) {
    return <ErrorState error={itinerary.error} retry={() => itinerary.refetch()} />;
  }

  const dayItems = byDay.get(effectiveDay) ?? [];
  const plan = itinerary.data;
  const people = members.data?.items ?? [];

  return (
    <div className="space-y-6">
      <PageHeader
        as="h2"
        size="md"
        eyebrow="Confirmed itinerary"
        title="The shared plan"
        description={`Version ${plan.confirmed_version}. Every edit is recorded and the group is notified.`}
        actions={
          <>
            <Button variant="secondary" size="sm" onClick={() => setShowVersions(true)}>
              <History size={14} /> Versions
            </Button>
            {isAdmin ? (
              <>
                <Button variant="secondary" size="sm" onClick={() => openReserve(effectiveDay)}>
                  <Lock size={14} /> Reserve time
                </Button>
                <Button size="sm" onClick={() => openAdd(effectiveDay)}>
                  <Plus size={14} /> Add item
                </Button>
              </>
            ) : (
              <LinkButton href={`/trips/${tripId}/voting`} variant="secondary" size="sm">
                Suggest a change
              </LinkButton>
            )}
          </>
        }
      />

      <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-4">
        <Stat label="Items" value={plan.totals.items ?? items.length} />
        <Stat label="Planned days" value={plan.totals.days ?? byDay.size} />
        <Stat label="Protected" value={plan.totals.protected_items ?? 0} tone="jade" />
        <Stat
          label="Est. cost"
          value={formatMoney(plan.totals.cost, currency)}
          hint="catalog estimates"
        />
      </div>

      <div className="sticky top-[3.9rem] z-20 -mx-4 border-y border-line bg-paper/92 px-4 py-2 backdrop-blur-sm sm:mx-0 sm:rounded-2xl sm:border sm:px-2 lg:top-2">
        <div
          role="group"
          aria-label="Trip days"
          className="hide-scrollbar flex gap-1.5 overflow-x-auto"
        >
          {days.map((day) => {
            const count = byDay.get(day)?.length ?? 0;
            const active = day === effectiveDay;
            const isToday = day === todayIso();
            const date = new Date(`${day}T12:00:00`);
            return (
              <button
                key={day}
                ref={active ? activeDayRef : undefined}
                type="button"
                onClick={() => setSelectedDay(day)}
                aria-pressed={active}
                className={cn(
                  "flex min-w-[4.4rem] shrink-0 flex-col items-center rounded-xl px-3 py-1.5 transition-colors",
                  active
                    ? "bg-ink text-paper"
                    : "text-muted hover:bg-ink/5 hover:text-ink",
                )}
              >
                <span className="text-[10px] uppercase tracking-editorial opacity-70">
                  {isToday ? "Today" : date.toLocaleDateString("en", { weekday: "short" })}
                </span>
                <span className="mt-0.5 flex items-baseline gap-1">
                  <span className="font-display text-[19px] leading-none">{date.getDate()}</span>
                  <span className="text-[10px] uppercase opacity-60">
                    {date.toLocaleDateString("en", { month: "short" })}
                  </span>
                </span>
                <span className="mt-1 flex h-1 items-center gap-0.5" aria-hidden>
                  {Array.from({ length: Math.min(count, 3) }).map((_, index) => (
                    <span
                      key={index}
                      className={cn(
                        "h-1 w-1 rounded-full",
                        active ? "bg-paper/70" : "bg-ember/60",
                      )}
                    />
                  ))}
                </span>
                <span className="sr-only">
                  {count} item{count === 1 ? "" : "s"}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      <div className="space-y-3">
        <SectionTitle
          title={formatDay(effectiveDay)}
          hint={
            dayItems.length
              ? `${dayItems.length} confirmed item${dayItems.length === 1 ? "" : "s"}${
                  dayItems.some((item) => item.is_protected)
                    ? ` · ${dayItems.filter((item) => item.is_protected).length} protected`
                    : ""
                } · ${formatMoney(
                  dayItems.reduce((total, item) => total + (item.cost_estimate ?? 0), 0),
                  currency,
                )} estimated`
              : "Nothing confirmed for this day"
          }
          action={
            isAdmin ? (
              <Button variant="ghost" size="sm" onClick={() => openAdd(effectiveDay)}>
                <Plus size={13} /> Add
              </Button>
            ) : null
          }
        />

        {dayItems.length === 0 ? (
          <EmptyState
            title="This day is open"
            description="Ask the group engine for options, or add a confirmed activity if you manage this journey."
            icon={<CalendarDays size={24} />}
            action={
              <LinkButton href={`/trips/${tripId}/engine`} size="sm" variant="secondary">
                Open the engine
              </LinkButton>
            }
          />
        ) : (
          <ol className="space-y-3">
            {dayItems.map((item) => {
              const pending =
                attendance.isPending && attendance.variables?.itemId === item.id;
              return (
                <li
                  key={item.id}
                  className="grid grid-cols-[3.1rem_1fr] gap-3 sm:grid-cols-[4.25rem_1fr] sm:gap-4"
                >
                  <div className="pt-4 text-right">
                    <p className="font-mono text-[12px] text-ink">{formatTime(item.start_time)}</p>
                    {item.end_time ? (
                      <p className="mt-0.5 font-mono text-[11px] text-faint">
                        {formatTime(item.end_time)}
                      </p>
                    ) : null}
                  </div>
                  <div className="relative border-l border-line pl-4 sm:pl-5">
                    <span
                      aria-hidden
                      className={cn(
                        "absolute -left-[5px] top-[1.4rem] h-2.5 w-2.5 rounded-full ring-4 ring-paper",
                        item.is_protected ? "bg-jade" : "bg-ember",
                      )}
                    />
                    <Card
                      className={cn(
                        "space-y-3",
                        item.is_protected && "border-jade/35 bg-jade-soft/20",
                      )}
                    >
                      <div className="flex flex-wrap items-start justify-between gap-2">
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            {item.is_protected ? (
                              <Badge tone="jade">
                                <Lock size={10} /> Protected time
                              </Badge>
                            ) : null}
                            {item.activity?.tags?.[0] ? (
                              <Badge tone="outline">{item.activity.tags[0]}</Badge>
                            ) : null}
                          </div>
                          <h3 className="mt-1.5 text-lg leading-snug">{item.title}</h3>
                          {item.notes ? (
                            <p className="mt-1 max-w-prose text-[13px] leading-6 text-muted">
                              {item.notes}
                            </p>
                          ) : null}
                          <p className="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-[12px] text-faint">
                            <span className="num">{formatMoney(item.cost_estimate, currency)}</span>
                            {item.activity?.duration_minutes ? (
                              <span className="inline-flex items-center gap-1">
                                <Clock size={11} /> {item.activity.duration_minutes} min
                              </span>
                            ) : null}
                            {item.activity?.place?.name ? (
                              <span>{item.activity.place.name}</span>
                            ) : null}
                          </p>
                        </div>
                        {isAdmin ? (
                          <div className="flex gap-1">
                            <IconButton label="Edit item" onClick={() => openEdit(item)}>
                              <Pencil size={14} />
                            </IconButton>
                            <IconButton
                              label="Remove item"
                              onClick={() => setRemoving(item)}
                              className="hover:bg-rose/10 hover:text-rose"
                            >
                              <Trash2 size={14} />
                            </IconButton>
                          </div>
                        ) : null}
                      </div>

                      <div className="flex flex-wrap items-center gap-2 border-t border-line pt-3">
                        <span className="inline-flex items-center gap-1 text-[12px] text-faint">
                          <Users size={12} /> {item.attendance?.in ?? people.length} in
                          {item.attendance?.join_later
                            ? ` · ${item.attendance.join_later} joining later`
                            : ""}
                        </span>
                        <div
                          role="group"
                          aria-label={`Attendance for ${item.title}`}
                          className="ml-auto flex gap-1.5"
                        >
                          {(["in", "join_later", "out"] as const).map((status) => {
                            const active = item.attendance?.my_status === status;
                            return (
                              <button
                                key={status}
                                type="button"
                                aria-pressed={active}
                                disabled={pending}
                                onClick={() => attendance.mutate({ itemId: item.id, status })}
                                className={cn(
                                  "rounded-full border px-2.5 py-1 text-[12px] transition-colors disabled:opacity-60",
                                  active
                                    ? "border-jade bg-jade-soft text-jade"
                                    : "border-line bg-surface text-muted hover:border-ink/30 hover:text-ink",
                                )}
                              >
                                {status === "in"
                                  ? "I'm in"
                                  : status === "out"
                                    ? "Skip"
                                    : "Join later"}
                              </button>
                            );
                          })}
                        </div>
                      </div>
                    </Card>
                  </div>
                </li>
              );
            })}
          </ol>
        )}
      </div>

      <FlowNote icon={<ShieldCheck size={15} />}>
        Confirmed items change only through an explicit edit or an approved proposal — never
        silently. Protected time is respected by the engine and rescue flows.
      </FlowNote>

      <Modal
        open={adding}
        onClose={() => {
          setAdding(false);
          setEditing(null);
        }}
        title={editing ? "Edit confirmed item" : "Add a confirmed item"}
      >
        <div className="space-y-3">
          <Field label="Title">
            <Input
              value={draft.title}
              onChange={(event) => setDraft({ ...draft, title: event.target.value })}
              placeholder="Sunset walk along the river"
            />
          </Field>
          <div className="grid gap-3 sm:grid-cols-3">
            <Field label="Day">
              <Select
                value={draft.day || effectiveDay}
                onChange={(event) => setDraft({ ...draft, day: event.target.value })}
                disabled={Boolean(editing)}
              >
                {days.map((day) => (
                  <option key={day} value={day}>
                    {formatDay(day)}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Start time">
              <Input
                type="time"
                value={draft.start_time}
                onChange={(event) => setDraft({ ...draft, start_time: event.target.value })}
              />
            </Field>
            <Field
              label="End time"
              hint={draft.is_protected ? "Required for protected time" : "Optional"}
            >
              <Input
                type="time"
                value={draft.end_time}
                onChange={(event) => setDraft({ ...draft, end_time: event.target.value })}
              />
            </Field>
          </div>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Estimated cost per person" hint={`${currency} · catalog estimate`}>
              <Input
                type="number"
                min="0"
                step="0.5"
                value={draft.cost_estimate}
                onChange={(event) => setDraft({ ...draft, cost_estimate: event.target.value })}
              />
            </Field>
          </div>
          <Field label="Notes">
            <Textarea
              value={draft.notes}
              onChange={(event) => setDraft({ ...draft, notes: event.target.value })}
              placeholder="Meeting point, ticket notes, accessibility details…"
            />
          </Field>
          <div className="rounded-2xl border border-line px-3">
            <Toggle
              label="Protect this time"
              description="Protected time is never moved or replaced by the engine without group approval."
              checked={draft.is_protected}
              onChange={(value) => setDraft({ ...draft, is_protected: value })}
            />
          </div>
          <div className="flex justify-end gap-2 pt-1">
            <Button
              variant="secondary"
              onClick={() => {
                setAdding(false);
                setEditing(null);
              }}
            >
              Cancel
            </Button>
            <Button onClick={submit} loading={save.isPending}>
              <Check size={14} /> {editing ? "Save change" : "Add item"}
            </Button>
          </div>
        </div>
      </Modal>

      <Modal
        open={Boolean(removing)}
        onClose={() => setRemoving(null)}
        title="Remove this item?"
        description={
          removing
            ? `“${removing.title}” will be removed from the confirmed plan. The change is versioned and visible to the group.`
            : undefined
        }
        footer={
          <>
            <Button variant="secondary" onClick={() => setRemoving(null)}>
              Keep it
            </Button>
            <Button
              variant="danger"
              loading={remove.isPending}
              onClick={() => removing && remove.mutate(removing.id)}
            >
              <Trash2 size={14} /> Remove item
            </Button>
          </>
        }
      >
        <p className="text-sm leading-6 text-muted">
          Attendance and notes recorded against this item go with it. This cannot be undone from
          this screen.
        </p>
      </Modal>

      <Modal open={showVersions} onClose={() => setShowVersions(false)} title="Plan versions" wide>
        <div className="space-y-3">
          {(plan.versions || []).map((version) => (
            <div
              key={version.id}
              className="rounded-2xl border border-line bg-raised/60 px-4 py-3"
            >
              <div className="flex items-center justify-between gap-2">
                <p className="text-sm font-medium text-ink">Version {version.version}</p>
                <span className="text-[12px] text-faint">
                  {new Date(version.created_at).toLocaleString()}
                </span>
              </div>
              <p className="mt-0.5 text-[12.5px] text-muted">{version.note || "Plan updated"}</p>
              <p className="mt-1 text-[12px] text-faint">
                {Array.isArray(version.snapshot)
                  ? `${version.snapshot.length} ${version.snapshot.length === 1 ? "item" : "items"} captured`
                  : ""}
              </p>
            </div>
          ))}
          {!plan.versions?.length ? (
            <p className="text-sm text-muted">No versions recorded yet.</p>
          ) : null}
        </div>
      </Modal>
    </div>
  );
}
