"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Clock3, Handshake, Lock, Plus, ShieldCheck, Trash2 } from "lucide-react";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";

import {
  Badge,
  Button,
  Card,
  ErrorState,
  Field,
  FlowNote,
  Input,
  PageSkeleton,
  SectionTitle,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useMe, usePact, useTrip } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { errorMessage } from "@/lib/utils";

export default function PactPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const pact = usePact(tripId);
  const me = useMe();
  const queryClient = useQueryClient();
  const { push } = useToasts();

  const canEdit = trip.data?.my_role === "owner" || trip.data?.my_role === "admin";

  const [mustDo, setMustDo] = useState("");
  const [flexible, setFlexible] = useState("");
  const [exceptions, setExceptions] = useState("");
  const [myLimit, setMyLimit] = useState("");
  const [times, setTimes] = useState<{ label: string; value: string }[]>([]);

  useEffect(() => {
    const data = pact.data?.pact;
    setMustDo((data?.must_do ?? []).join("\n"));
    setFlexible((data?.flexible ?? []).join("\n"));
    setExceptions((data?.exceptions ?? []).join("\n"));
    setTimes(
      Object.entries(data?.confirmed_times ?? {}).map(([label, value]) => ({
        label,
        value: String(value),
      })),
    );
    const mine = data?.individual_limits?.[me.data?.user.id || ""];
    setMyLimit(mine?.budget_limit !== undefined ? String(mine.budget_limit) : "");
  }, [pact.data, me.data?.user.id]);

  const save = useMutation({
    mutationFn: () =>
      api(`/api/trips/${tripId}/pact`, {
        method: "PUT",
        body: {
          must_do: mustDo.split("\n").map((line) => line.trim()).filter(Boolean),
          flexible: flexible.split("\n").map((line) => line.trim()).filter(Boolean),
          exceptions: exceptions.split("\n").map((line) => line.trim()).filter(Boolean),
          confirmed_times: Object.fromEntries(
            times.filter((entry) => entry.label.trim()).map((entry) => [entry.label.trim(), entry.value]),
          ),
          individual_limits: me.data?.user.id
            ? {
                [me.data.user.id]: {
                  budget_limit: myLimit === "" ? null : Number(myLimit),
                },
              }
            : {},
        },
      }),
    onSuccess: () => {
      push("Pact saved", "Conflicts with this pact will now block plan approval.", "success");
      queryClient.invalidateQueries({ queryKey: ["pact", tripId] });
    },
    onError: (error) => push("Could not save pact", errorMessage(error), "error"),
  });

  if (pact.isLoading) return <PageSkeleton />;
  if (pact.error) {
    return <ErrorState error={pact.error} retry={() => pact.refetch()} />;
  }

  const data = pact.data?.pact;
  const currency = trip.data?.currency || "EUR";

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Journey pact</p>
          <h2 className="mt-1 text-2xl">Shared expectations, written down</h2>
          <p className="mt-1 max-w-prose text-sm text-muted">
            The pact records must-dos, flexible items and meeting points. A proposal that breaks a must-do or
            personal limit cannot be approved without explicit resolution.
          </p>
        </div>
        {data ? <Badge tone="outline">Updated {new Date(data.updated_at).toLocaleDateString()}</Badge> : null}
      </div>

      {!data ? (
        <Card className="space-y-2">
          <p className="text-sm text-muted">
            No pact exists yet. {canEdit ? "Create one below." : "Ask an owner or admin to set one up."}
          </p>
        </Card>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="space-y-3">
          <SectionTitle title="Must-do" hint="Non-negotiables the plan must respect" />
          {canEdit ? (
            <Textarea
              value={mustDo}
              onChange={(event) => setMustDo(event.target.value)}
              placeholder={"One per line, e.g.\nSee the Sagrada Família"}
              aria-label="Must-do items, one per line"
            />
          ) : (
            <Checklist items={data?.must_do ?? []} empty="No must-dos recorded." />
          )}
        </Card>

        <Card className="space-y-3">
          <SectionTitle title="Flexible" hint="Nice-to-have, movable items" />
          {canEdit ? (
            <Textarea
              value={flexible}
              onChange={(event) => setFlexible(event.target.value)}
              placeholder={"One per line"}
              aria-label="Flexible items, one per line"
            />
          ) : (
            <Checklist items={data?.flexible ?? []} empty="No flexible items recorded." />
          )}
        </Card>
      </div>

      <Card className="space-y-3">
        <SectionTitle title="Confirmed meeting points" hint="Fixed times the group agreed on" />
        {canEdit ? (
          <div className="space-y-2">
            {times.map((entry, index) => (
              <div key={index} className="flex flex-wrap items-center gap-2">
                <Input
                  value={entry.label}
                  onChange={(event) =>
                    setTimes((current) =>
                      current.map((item, itemIndex) =>
                        itemIndex === index ? { ...item, label: event.target.value } : item,
                      ),
                    )
                  }
                  placeholder="What (e.g. lunch)"
                  aria-label={`Meeting point ${index + 1} label`}
                  className="flex-1"
                />
                <Input
                  type="time"
                  value={entry.value}
                  aria-label={`Meeting point ${index + 1} time`}
                  onChange={(event) =>
                    setTimes((current) =>
                      current.map((item, itemIndex) =>
                        itemIndex === index ? { ...item, value: event.target.value } : item,
                      ),
                    )
                  }
                  className="w-32"
                />
                <button
                  type="button"
                  onClick={() => setTimes((current) => current.filter((_, itemIndex) => itemIndex !== index))}
                  className="text-faint hover:text-rose"
                  aria-label="Remove meeting point"
                >
                  <Trash2 size={14} />
                </button>
              </div>
            ))}
            <Button
              type="button"
              size="sm"
              variant="secondary"
              onClick={() => setTimes((current) => [...current, { label: "", value: "12:00" }])}
            >
              <Plus size={13} /> Add meeting point
            </Button>
          </div>
        ) : Object.keys(data?.confirmed_times ?? {}).length ? (
          <div className="space-y-1.5">
            {Object.entries(data?.confirmed_times ?? {}).map(([label, value]) => (
              <div key={label} className="flex items-center justify-between rounded-xl border border-line bg-surface px-3 py-2">
                <span className="text-[12.5px] text-ink">{label}</span>
                <span className="inline-flex items-center gap-1 font-mono text-[12px] text-muted">
                  <Clock3 size={12} /> {value}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-muted">No fixed meeting points recorded.</p>
        )}
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="space-y-3">
          <SectionTitle title="Exceptions" hint="Agreed exceptions to the usual rules" />
          {canEdit ? (
            <Textarea
              value={exceptions}
              onChange={(event) => setExceptions(event.target.value)}
              placeholder="One per line"
              aria-label="Agreed exceptions, one per line"
            />
          ) : (
            <Checklist items={data?.exceptions ?? []} empty="No exceptions recorded." />
          )}
        </Card>

        <Card className="space-y-3">
          <SectionTitle title="Your private limit" hint="Only you and the pact engine see this" />
          <Field label={`Budget limit (${currency})`} hint="Leave blank for no personal limit">
            <Input
              type="number"
              min="0"
              value={myLimit}
              onChange={(event) => setMyLimit(event.target.value)}
              disabled={!canEdit}
              placeholder="No limit"
            />
          </Field>
          {!canEdit ? (
            <p className="text-[12px] leading-5 text-faint">
              Only owners and admins can edit the pact. Your limit stays private regardless.
            </p>
          ) : null}
          <FlowNote icon={<Lock size={14} />}>
            Individual limits are never shown to other members. Saving merges your limit without wiping anyone
            else&apos;s.
          </FlowNote>
        </Card>
      </div>

      {canEdit ? (
        <div className="flex flex-wrap items-center justify-between gap-2">
          <FlowNote icon={<ShieldCheck size={14} />}>
            Saving the pact does not change the confirmed itinerary. It only affects what the engine may propose
            and what approval rules apply.
          </FlowNote>
          <Button onClick={() => save.mutate()} loading={save.isPending}>
            <Handshake size={14} /> Save pact
          </Button>
        </div>
      ) : (
        <FlowNote icon={<Handshake size={14} />}>
          The pact is read-only for your role. Ask an owner or admin to make changes.
        </FlowNote>
      )}
    </div>
  );
}

function Checklist({ items, empty }: { items: string[]; empty: string }) {
  if (items.length === 0) return <p className="text-sm text-muted">{empty}</p>;
  return (
    <ul className="space-y-1.5">
      {items.map((item) => (
        <li key={item} className="flex items-start gap-2 text-[12.5px] leading-5 text-ink">
          <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-ember" />
          {item}
        </li>
      ))}
    </ul>
  );
}
