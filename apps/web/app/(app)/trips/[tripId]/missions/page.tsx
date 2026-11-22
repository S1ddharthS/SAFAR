"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { BadgeCheck, CircleSlash, Compass, Sparkles, Target, UserPlus } from "lucide-react";
import { useParams } from "next/navigation";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  FlowNote,
  PageSkeleton,
  SectionTitle,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useMissions, useTrip } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { errorMessage, titleCase } from "@/lib/utils";

const CONSTRAINT_CHIPS: Record<string, (value: unknown) => string | null> = {
  max_cost: (value) => (typeof value === "number" ? `Cost ≤ ${value}` : null),
  max_effort: (value) => (typeof value === "number" ? `Effort ≤ ${value}/5` : null),
  tag: (value) => (typeof value === "string" && value ? `Focus: ${titleCase(value)}` : null),
  respect_accessibility: (value) => (value === true ? "Respects access needs" : null),
  // Already shown as a badge or spelled out in the description.
  optional: () => null,
  suggested_activity: () => null,
};

function constraintChips(constraints: Record<string, unknown>): string[] {
  return Object.entries(constraints)
    .map(([key, value]) => {
      const formatter = CONSTRAINT_CHIPS[key];
      if (formatter) return formatter(value);
      return typeof value === "object" && value !== null ? null : `${titleCase(key)}: ${String(value)}`;
    })
    .filter((chip): chip is string => Boolean(chip));
}

export default function MissionsPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const missions = useMissions(tripId);
  const trip = useTrip(tripId);
  const queryClient = useQueryClient();
  const { push } = useToasts();
  const canDisable = trip.data?.my_role === "owner" || trip.data?.my_role === "admin";

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["missions", tripId] });

  const act = useMutation({
    mutationFn: ({ missionId, action }: { missionId: string; action: "join" | "complete" | "disable" }) =>
      api(`/api/trips/${tripId}/missions/${missionId}/${action}`, { method: "POST" }),
    onSuccess: (_result, variables) => {
      const copy = {
        join: "Mission joined — optional, never required.",
        complete: "Marked complete (self-reported).",
        disable: "Mission disabled for this trip.",
      } as const;
      push("Mission updated", copy[variables.action], "success");
      refresh();
    },
    onError: (error) => push("Could not update mission", errorMessage(error), "error"),
  });

  if (missions.isLoading) return <PageSkeleton />;
  if (missions.error || !missions.data) {
    return <ErrorState error={missions.error || new Error("Missions unavailable")} retry={() => missions.refetch()} />;
  }

  const items = missions.data.items;

  return (
    <div className="space-y-5">
      <div>
        <p className="eyebrow">Optional missions</p>
        <h2 className="mt-1 text-2xl">Small challenges, low pressure</h2>
        <p className="mt-1 max-w-prose text-sm text-muted">
          Missions are generated from this trip and are always optional. Completion is self-reported — SAFAR
          never verifies it.
        </p>
      </div>

      <FlowNote icon={<Sparkles size={14} />}>{missions.data.note}</FlowNote>

      {items.length === 0 ? (
        <EmptyState
          title="No missions right now"
          description="Missions appear as the trip takes shape. They are never mandatory."
          icon={<Compass size={24} />}
        />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {items.map((mission) => {
            const done = mission.my_status === "completed";
            const joined = mission.my_status === "joined" || done;
            const disabled = mission.status === "disabled";
            const chips = constraintChips(mission.constraints ?? {});
            return (
              <Card key={mission.id} className="space-y-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-1.5">
                      {mission.optional ? <Badge tone="outline">optional</Badge> : null}
                      {mission.self_reported ? <Badge tone="neutral">self-reported</Badge> : null}
                      {disabled ? <Badge tone="rose">disabled</Badge> : null}
                    </div>
                    <p className="mt-1.5 text-[14px] font-medium text-ink">{mission.title}</p>
                    <p className="mt-0.5 text-[12px] leading-5 text-muted">{mission.description}</p>
                  </div>
                  <Target size={18} className="shrink-0 text-faint" />
                </div>

                {chips.length ? (
                  <div className="flex flex-wrap gap-1.5">
                    {chips.map((chip) => (
                      <Badge key={chip} tone="neutral">
                        {chip}
                      </Badge>
                    ))}
                  </div>
                ) : null}

                <div className="flex flex-wrap items-center gap-2 border-t border-line pt-2.5">
                  {done ? (
                    <Badge tone="jade">
                      <BadgeCheck size={11} /> completed
                    </Badge>
                  ) : (
                    <>
                      {!joined ? (
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() => act.mutate({ missionId: mission.id, action: "join" })}
                          disabled={disabled}
                        >
                          <UserPlus size={13} /> Join
                        </Button>
                      ) : null}
                      <Button
                        size="sm"
                        onClick={() => act.mutate({ missionId: mission.id, action: "complete" })}
                        disabled={disabled}
                      >
                        <BadgeCheck size={13} /> Mark done
                      </Button>
                    </>
                  )}
                  {canDisable && !disabled ? (
                    <Button
                      size="sm"
                      variant="ghost"
                      className="ml-auto text-muted"
                      onClick={() => act.mutate({ missionId: mission.id, action: "disable" })}
                    >
                      <CircleSlash size={13} /> Disable
                    </Button>
                  ) : null}
                </div>
              </Card>
            );
          })}
        </div>
      )}

      <SectionTitle title="How missions stay honest" hint="" />
      <FlowNote icon={<BadgeCheck size={14} />}>
        Missions are generated from recorded trip data. Joining and completing are personal actions; nothing is
        shared as verified information, and any mission can be disabled by an owner or admin.
      </FlowNote>
    </div>
  );
}
