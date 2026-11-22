"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { CheckCircle2, Circle, ListChecks, Plus, Scale, Send, UserRound } from "lucide-react";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";

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
  SectionTitle,
  Select,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useMembers, useTasks, useTaskSummary } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { cn, errorMessage } from "@/lib/utils";

export default function TasksPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const tasks = useTasks(tripId);
  const summary = useTaskSummary(tripId);
  const members = useMembers(tripId);
  const queryClient = useQueryClient();
  const { push } = useToasts();

  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [assignee, setAssignee] = useState("");

  const people = useMemo(
    () => (members.data?.items ?? []).map((member) => ({ id: member.user?.id || "", name: member.display_name })).filter((entry) => entry.id),
    [members.data],
  );

  const nameFor = (id: string | null) => people.find((person) => person.id === id)?.name || "Unassigned";

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["tasks", tripId] });

  const createTask = useMutation({
    mutationFn: () =>
      api(`/api/trips/${tripId}/tasks`, {
        method: "POST",
        body: { title, description: description || null, assignee_id: assignee || null },
      }),
    onSuccess: () => {
      push("Task added", "Assignees can mark it done.", "success");
      setTitle("");
      setDescription("");
      setAssignee("");
      refresh();
    },
    onError: (error) => push("Could not add task", errorMessage(error), "error"),
  });

  const updateTask = useMutation({
    mutationFn: ({ taskId, body }: { taskId: string; body: Record<string, unknown> }) =>
      api(`/api/trips/${tripId}/tasks/${taskId}`, { method: "PATCH", body }),
    onSuccess: () => refresh(),
    onError: (error) => push("Could not update task", errorMessage(error), "error"),
  });

  const items = tasks.data?.items ?? [];
  const open = items.filter((task) => task.status !== "done");
  const done = items.filter((task) => task.status === "done");

  const load = summary.data?.load ?? [];

  if (tasks.isLoading) return <PageSkeleton />;
  if (tasks.error) {
    return <ErrorState error={tasks.error} retry={() => tasks.refetch()} />;
  }

  return (
    <div className="space-y-5">
      <div>
        <p className="eyebrow">Planner load</p>
        <h2 className="mt-1 text-2xl">Share the planning work</h2>
        <p className="mt-1 max-w-prose text-sm text-muted">
          Tasks keep the invisible work visible. Assign owners so one person does not carry the whole plan.
        </p>
      </div>

      <Card className="space-y-3">
        <SectionTitle
          title="Load balance"
          hint={
            summary.data
              ? `${summary.data.totals.open} open · counts from the API`
              : "Open tasks per person — a nudge, not a score"
          }
          action={<Scale size={16} className="text-faint" />}
        />
        {summary.isLoading ? (
          <p className="text-sm text-muted">Counting…</p>
        ) : load.length === 0 ? (
          <p className="text-sm text-muted">No open tasks.</p>
        ) : (
          <div className="flex flex-wrap gap-1.5">
            {load.map((entry) => (
              <Badge key={entry.key} tone={entry.open >= 3 ? "ember" : "outline"}>
                {entry.key === "unassigned" ? "Unassigned" : entry.display_name} · {entry.open}
              </Badge>
            ))}
          </div>
        )}
      </Card>

      <Card className="space-y-3">
        <SectionTitle title="Add task" />
        <form
          className="space-y-3"
          onSubmit={(event) => {
            event.preventDefault();
            if (!title.trim()) return;
            createTask.mutate();
          }}
        >
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Title">
              <Input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Book the museum tickets" />
            </Field>
            <Field label="Assign to" hint="Optional">
              <Select value={assignee} onChange={(event) => setAssignee(event.target.value)}>
                <option value="">Unassigned</option>
                {people.map((person) => (
                  <option key={person.id} value={person.id}>
                    {person.name}
                  </option>
                ))}
              </Select>
            </Field>
          </div>
          <Field label="Details" hint="Optional">
            <Textarea value={description} onChange={(event) => setDescription(event.target.value)} />
          </Field>
          <Button type="submit" loading={createTask.isPending} disabled={!title.trim()}>
            <Plus size={14} /> Add task
          </Button>
        </form>
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="space-y-3">
          <SectionTitle title="Open" action={<Badge tone="ember">{open.length}</Badge>} />
          {open.length === 0 ? (
            <EmptyState title="Nothing open" description="All caught up." icon={<ListChecks size={22} />} />
          ) : (
            <div className="space-y-2">
              {open.map((task) => (
                <TaskRow
                  key={task.id}
                  title={task.title}
                  description={task.description}
                  assigneeId={task.assignee_id}
                  assignee={nameFor(task.assignee_id)}
                  done={false}
                  onToggle={() => updateTask.mutate({ taskId: task.id, body: { status: "done" } })}
                  onAssign={(value) => updateTask.mutate({ taskId: task.id, body: { assignee_id: value || null } })}
                  people={people}
                />
              ))}
            </div>
          )}
        </Card>

        <Card className="space-y-3">
          <SectionTitle title="Done" action={<Badge tone="jade">{done.length}</Badge>} />
          {done.length === 0 ? (
            <p className="text-sm text-muted">Nothing completed yet.</p>
          ) : (
            <div className="space-y-2">
              {done.map((task) => (
                <TaskRow
                  key={task.id}
                  title={task.title}
                  description={task.description}
                  assigneeId={task.assignee_id}
                  assignee={nameFor(task.assignee_id)}
                  done
                  onToggle={() => updateTask.mutate({ taskId: task.id, body: { status: "open" } })}
                  onAssign={(value) => updateTask.mutate({ taskId: task.id, body: { assignee_id: value || null } })}
                  people={people}
                />
              ))}
            </div>
          )}
        </Card>
      </div>

      <FlowNote icon={<UserRound size={14} />}>
        Anyone can add a task. Only the assignee or an owner/admin can update it. Load counts are derived from
        open tasks, not a productivity score.
      </FlowNote>
    </div>
  );
}

function TaskRow({
  title,
  description,
  assigneeId,
  assignee,
  done,
  onToggle,
  onAssign,
  people,
}: {
  title: string;
  description: string | null;
  assigneeId: string | null;
  assignee: string;
  done: boolean;
  onToggle: () => void;
  onAssign: (value: string) => void;
  people: { id: string; name: string }[];
}) {
  return (
    <div className="rounded-2xl border border-line bg-surface p-3">
      <div className="flex items-start gap-2.5">
        <button
          type="button"
          onClick={onToggle}
          aria-pressed={done}
          aria-label={`Mark "${title}" as ${done ? "not done" : "done"}`}
          className={cn("mt-0.5", done ? "text-jade" : "text-faint hover:text-ink")}
        >
          {done ? <CheckCircle2 size={18} /> : <Circle size={18} />}
        </button>
        <div className="min-w-0 flex-1">
          <p className={cn("text-[13px] font-medium", done ? "text-muted line-through" : "text-ink")}>{title}</p>
          {description ? <p className="mt-0.5 text-[12px] leading-5 text-muted">{description}</p> : null}
          <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
            <span className="text-[10.5px] text-faint">{assignee}</span>
            {!done ? (
              <select
                value={assigneeId || ""}
                onChange={(event) => onAssign(event.target.value)}
                className="rounded-full border border-line bg-paper px-2 py-0.5 text-[10.5px] text-muted"
                aria-label="Reassign"
              >
                <option value="">Unassigned</option>
                {people.map((person) => (
                  <option key={person.id} value={person.id}>
                    {person.name}
                  </option>
                ))}
              </select>
            ) : null}
          </div>
        </div>
        {done ? <Send size={12} className="text-jade" /> : null}
      </div>
    </div>
  );
}
