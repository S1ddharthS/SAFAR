"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { GitBranch, MapPin, Plus, Route, Users } from "lucide-react";
import { useParams } from "next/navigation";
import { useState } from "react";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  FlowNote,
  Input,
  Modal,
  PageSkeleton,
  SectionTitle,
  Select,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useBranches, useMembers, useSearch, useTrip } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { cn, errorMessage, formatDateTime } from "@/lib/utils";

interface Feasibility {
  status: string;
  distance_km?: number;
  travel_minutes?: number;
  note?: string;
}

export default function BranchesPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const branches = useBranches(tripId);
  const members = useMembers(tripId);
  const catalog = useSearch({ destination_id: trip.data?.destination_id || undefined, limit: 60 });
  const queryClient = useQueryClient();
  const { push } = useToasts();

  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [selected, setSelected] = useState<string[]>([]);
  const [activityId, setActivityId] = useState("");
  const [reunionAt, setReunionAt] = useState("");
  const [reunionPlace, setReunionPlace] = useState("");
  const [feasibility, setFeasibility] = useState<Feasibility | null>(null);

  const memberName = (memberId: string) =>
    members.data?.items.find((member) => member.id === memberId)?.display_name || "Member";
  const activityName = (activityId: string | null) => {
    if (!activityId) return null;
    return catalog.data?.items.find((item) => item.activity.id === activityId)?.activity.name || "Catalog activity";
  };

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["branches", tripId] });

  const createBranch = useMutation({
    mutationFn: () =>
      api<{ id: string; feasibility: Feasibility }>(`/api/trips/${tripId}/branches`, {
        method: "POST",
        body: {
          name,
          member_ids: selected,
          activity_id: activityId || null,
          reunion_at: reunionAt ? new Date(reunionAt).toISOString() : null,
          reunion_place: reunionPlace || null,
        },
      }),
    onSuccess: (result) => {
      setFeasibility(result.feasibility);
      push("Branch created", result.feasibility.note || "The group can split and rejoin.", "success");
      setName("");
      setSelected([]);
      setActivityId("");
      setReunionAt("");
      setReunionPlace("");
      refresh();
    },
    onError: (error) => push("Could not create branch", errorMessage(error), "error"),
  });

  if (branches.isLoading) return <PageSkeleton />;
  if (branches.error) {
    return <ErrorState error={branches.error} retry={() => branches.refetch()} />;
  }

  const items = branches.data?.items ?? [];

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Branch & rejoin</p>
          <h2 className="mt-1 text-2xl">Split the group, keep the plan</h2>
          <p className="mt-1 max-w-prose text-sm text-muted">
            Let travellers pursue different activities, then rejoin at a fixed time and place. Reunion travel
            time is estimated, not live routed.
          </p>
        </div>
        <Button onClick={() => setOpen(true)}>
          <Plus size={14} /> New branch
        </Button>
      </div>

      {feasibility ? (
        <FlowNote icon={<Route size={14} />}>
          Latest branch: {feasibility.status.replace(/_/g, " ")}
          {feasibility.distance_km !== undefined ? ` · ${feasibility.distance_km.toFixed(1)} km` : ""}
          {feasibility.travel_minutes !== undefined ? ` · ~${feasibility.travel_minutes} min` : ""}
          {feasibility.note ? ` · ${feasibility.note}` : ""}
        </FlowNote>
      ) : null}

      {items.length === 0 ? (
        <EmptyState
          title="No branches yet"
          description="Create a branch when part of the group wants a different activity but everyone reunites later."
          icon={<GitBranch size={24} />}
        />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {items.map((branch) => (
            <Card key={branch.id} className="space-y-3">
              <div className="flex items-start justify-between gap-2">
                <div>
                  <p className="text-[14px] font-medium text-ink">{branch.name}</p>
                  <p className="text-[12px] text-faint">{formatDateTime(branch.reunion_at)}</p>
                </div>
                <Badge tone={branch.status === "proposed" ? "ember" : "jade"}>{branch.status}</Badge>
              </div>

              <div className="flex flex-wrap gap-1.5">
                {branch.member_ids.map((memberId) => (
                  <Badge key={memberId} tone="neutral">
                    {memberName(memberId)}
                  </Badge>
                ))}
                {branch.member_ids.length === 0 ? <span className="text-[12px] text-faint">No members yet</span> : null}
              </div>

              <div className="space-y-1 text-[12px] text-muted">
                {activityName(branch.activity_id) ? (
                  <p className="inline-flex items-center gap-1">
                    <Users size={12} className="text-faint" /> {activityName(branch.activity_id)}
                  </p>
                ) : null}
                {branch.reunion_place ? (
                  <p className="inline-flex items-center gap-1">
                    <MapPin size={12} className="text-faint" /> Rejoin at {branch.reunion_place}
                  </p>
                ) : null}
              </div>
            </Card>
          ))}
        </div>
      )}

      <FlowNote icon={<GitBranch size={14} />}>
        Branches never change the confirmed itinerary by themselves. They record how the group splits and
        rejoins; reunion feasibility is shown as an estimate.
      </FlowNote>

      <Modal open={open} onClose={() => setOpen(false)} title="Create a branch" wide>
        <form
          className="space-y-3"
          onSubmit={(event) => {
            event.preventDefault();
            if (!name.trim()) return;
            createBranch.mutate();
          }}
        >
          <Field label="Branch name">
            <Input value={name} onChange={(event) => setName(event.target.value)} placeholder="Museum crew" />
          </Field>

          <div className="space-y-1.5">
            <p className="text-[13px] font-medium text-ink">Members on this branch</p>
            <div className="flex flex-wrap gap-1.5">
              {(members.data?.items ?? []).map((member) => {
                const active = selected.includes(member.id);
                return (
                  <button
                    key={member.id}
                    type="button"
                    aria-pressed={active}
                    onClick={() =>
                      setSelected((current) =>
                        current.includes(member.id)
                          ? current.filter((id) => id !== member.id)
                          : [...current, member.id],
                      )
                    }
                    className={cn(
                      "rounded-full border px-2.5 py-1 text-[12px]",
                      active ? "border-ink bg-ink text-paper" : "border-line bg-surface text-muted",
                    )}
                  >
                    {member.display_name}
                  </button>
                );
              })}
            </div>
          </div>

          <Field label="Branch activity" hint="Optional — chosen from this destination">
            <Select value={activityId} onChange={(event) => setActivityId(event.target.value)}>
              <option value="">No specific activity</option>
              {(catalog.data?.items ?? []).map((entry) => (
                <option key={entry.activity.id} value={entry.activity.id}>
                  {entry.activity.name}
                </option>
              ))}
            </Select>
          </Field>

          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Rejoin at">
              <Input type="datetime-local" value={reunionAt} onChange={(event) => setReunionAt(event.target.value)} />
            </Field>
            <Field label="Rejoin place">
              <Input
                value={reunionPlace}
                onChange={(event) => setReunionPlace(event.target.value)}
                placeholder="Café at the square"
              />
            </Field>
          </div>

          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" loading={createBranch.isPending} disabled={!name.trim()}>
              <GitBranch size={14} /> Create branch
            </Button>
          </div>
        </form>
      </Modal>
    </div>
  );
}
