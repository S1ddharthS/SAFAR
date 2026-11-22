"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  AlertTriangle,
  ChevronDown,
  Gavel,
  MessageSquare,
  Plus,
  Search,
  ThumbsDown,
  ThumbsUp,
  Ticket,
  UserX,
} from "lucide-react";
import { useParams } from "next/navigation";
import { useMemo, useState, useId } from "react";

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
  PageHeader,
  PageSkeleton,
  Tabs,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useProposals, useSearch, useTrip } from "@/lib/hooks";
import { useAuth, useToasts } from "@/lib/store";
import type { Proposal } from "@/lib/types";
import { cn, formatDateTime, formatMoney, titleCase, todayIso } from "@/lib/utils";

const FILTERS = [
  { href: "open", label: "Open" },
  { href: "approved", label: "Approved" },
  { href: "rejected", label: "Rejected" },
  { href: "withdrawn", label: "Withdrawn" },
  { href: "all", label: "All" },
];

export default function VotingPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const user = useAuth((state) => state.user);
  const [status, setStatus] = useState("open");
  const proposals = useProposals(tripId, status);
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);

  const [voting, setVoting] = useState<Proposal | null>(null);
  const [voteValue, setVoteValue] = useState("yes");
  const [voteComment, setVoteComment] = useState("");
  const [creating, setCreating] = useState(false);
  const [confirming, setConfirming] = useState<{
    proposal: Proposal;
    action: "approve" | "reject";
  } | null>(null);
  const [search, setSearch] = useState("");
  const [draft, setDraft] = useState({
    title: "",
    activity_id: "",
    day: "",
    start_time: "09:00",
    summary: "",
  });

  const isAdmin = trip.data?.my_role === "owner" || trip.data?.my_role === "admin";
  const currency = trip.data?.currency || "EUR";
  const searchResults = useSearch({
    destination_id: trip.data?.destination_id || undefined,
    q: search,
    limit: 8,
  });

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: ["proposals", tripId] });
    queryClient.invalidateQueries({ queryKey: ["itinerary", tripId] });
    queryClient.invalidateQueries({ queryKey: ["trip", tripId] });
  };

  const vote = useMutation({
    mutationFn: ({ proposalId, value, comment }: { proposalId: string; value: string; comment?: string }) =>
      api(`/api/trips/${tripId}/proposals/${proposalId}/vote`, {
        method: "POST",
        body: { value, comment: comment || null },
      }),
    onSuccess: () => {
      push("Vote recorded", "Your vote is visible to the group.", "success");
      invalidate();
      setVoting(null);
      setVoteComment("");
    },
    onError: (error) => push("Could not vote", (error as Error).message, "error"),
  });

  const approve = useMutation({
    mutationFn: (proposalId: string) =>
      api(`/api/trips/${tripId}/proposals/${proposalId}/approve`, {
        method: "POST",
        body: { approval: true },
      }),
    onSuccess: () => {
      push("Approved", "The confirmed itinerary was updated with a new version.", "success");
      setConfirming(null);
      invalidate();
    },
    onError: (error) => {
      setConfirming(null);
      push("Approval blocked", (error as Error).message, "error");
    },
  });

  const reject = useMutation({
    mutationFn: (proposalId: string) =>
      api(`/api/trips/${tripId}/proposals/${proposalId}/reject`, { method: "POST" }),
    onSuccess: () => {
      push("Rejected", "The group was notified.", "success");
      setConfirming(null);
      invalidate();
    },
    onError: (error) => {
      setConfirming(null);
      push("Could not reject", (error as Error).message, "error");
    },
  });

  const withdraw = useMutation({
    mutationFn: (proposalId: string) =>
      api(`/api/trips/${tripId}/proposals/${proposalId}/withdraw`, { method: "POST" }),
    onSuccess: () => {
      push("Withdrawn", undefined, "success");
      invalidate();
    },
    onError: (error) => push("Could not withdraw", (error as Error).message, "error"),
  });

  const create = useMutation({
    mutationFn: () =>
      api(`/api/trips/${tripId}/proposals`, {
        method: "POST",
        body: {
          kind: "add_activity",
          title: draft.title,
          summary: draft.summary || null,
          activity_id: draft.activity_id,
          day: draft.day,
          start_time: draft.start_time,
        },
      }),
    onSuccess: () => {
      push("Proposal opened", "The group can now vote. Nothing changes until it's approved.", "success");
      setCreating(false);
      setDraft({ title: "", activity_id: "", day: "", start_time: "09:00", summary: "" });
      setSearch("");
      invalidate();
    },
    onError: (error) => push("Could not create proposal", (error as Error).message, "error"),
  });

  const items = proposals.data?.items ?? [];
  const selectedActivity = useMemo(
    () => searchResults.data?.items.find((entry) => entry.activity.id === draft.activity_id),
    [searchResults.data, draft.activity_id],
  );

  if (trip.isLoading) return <PageSkeleton />;
  if (trip.error || !trip.data) {
    return <ErrorState error={trip.error || new Error("Trip not found")} retry={() => trip.refetch()} />;
  }

  return (
    <div className="space-y-5">
      <PageHeader
        as="h2"
        size="md"
        eyebrow="Group decisions"
        title="Decide together"
        description="Every suggestion becomes a proposal. Votes inform the group; an owner or admin approves to change the confirmed plan."
        actions={
          <Button size="sm" onClick={() => setCreating(true)}>
            <Plus size={14} /> New proposal
          </Button>
        }
      />

      <Tabs tabs={FILTERS} active={status} />

      {proposals.isLoading ? (
        <PageSkeleton />
      ) : proposals.error ? (
        <ErrorState error={proposals.error} retry={() => proposals.refetch()} />
      ) : items.length === 0 ? (
        <EmptyState
          title={status === "open" ? "No decisions waiting" : "Nothing here"}
          description={
            status === "open"
              ? "When someone proposes a change or the engine suggests an alternative, it lands here for the group."
              : "Try another filter."
          }
          icon={<Ticket size={24} />}
        />
      ) : (
        <div className="space-y-3">
          {items.map((proposal) => {
            const voteRows: { key: string; label: string; count: number; tone: "jade" | "rose" | "neutral" }[] = [
              { key: "yes", label: "Yes", count: proposal.votes.yes, tone: "jade" },
              { key: "no", label: "No", count: proposal.votes.no, tone: "rose" },
              { key: "abstain", label: "Abstain", count: proposal.votes.abstain, tone: "neutral" },
            ];
            const cast = voteRows.reduce((total, row) => total + row.count, 0);
            const barTone = {
              jade: "bg-jade",
              rose: "bg-rose/70",
              neutral: "bg-faint/70",
            } as const;
            return (
              <Card key={proposal.id} className="space-y-4">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <Badge tone={proposal.status === "open" ? "ember" : proposal.status === "approved" ? "jade" : "outline"}>
                        {titleCase(proposal.status)}
                      </Badge>
                      <Badge tone="neutral">{titleCase(proposal.kind)}</Badge>
                      {proposal.target_day ? (
                        <span className="text-[12px] text-faint">{String(proposal.target_day).slice(0, 10)}</span>
                      ) : null}
                    </div>
                    <h3 className="mt-1.5 text-lg leading-snug">{proposal.title}</h3>
                    {proposal.summary ? (
                      <p className="mt-1 max-w-prose whitespace-pre-line text-[13px] leading-5 text-muted">
                        {proposal.summary}
                      </p>
                    ) : null}
                    <p className="mt-1.5 text-[12px] text-faint">
                      {proposal.author?.display_name || "A traveller"} ·{" "}
                      {formatDateTime(proposal.created_at)}
                      {proposal.payload?.cost_estimate
                        ? ` · est. ${formatMoney(Number(proposal.payload.cost_estimate), currency)}`
                        : ""}
                    </p>
                  </div>
                  {proposal.my_vote ? (
                    <Badge tone="jade">Your vote: {proposal.my_vote}</Badge>
                  ) : (
                    <Badge tone="outline">You haven't voted</Badge>
                  )}
                </div>

                <div>
                  <div className="grid grid-cols-3 gap-2">
                    {voteRows.map((row) => {
                      const share = cast ? Math.round((row.count / cast) * 100) : 0;
                      return (
                        <div
                          key={row.key}
                          className={cn(
                            "rounded-xl border px-3 py-2 text-center",
                            row.tone === "jade"
                              ? "border-jade/20 bg-jade-soft/50"
                              : row.tone === "rose"
                                ? "border-rose/20 bg-rose/5"
                                : "border-line bg-raised",
                          )}
                        >
                          <p className="font-display text-xl leading-none">{row.count}</p>
                          <p className="mt-1 text-[10px] uppercase tracking-editorial text-faint">
                            {row.label}
                          </p>
                          <p className="num mt-0.5 text-[11px] text-faint">{share}%</p>
                        </div>
                      );
                    })}
                  </div>
                  <div
                    className="mt-2 flex h-1.5 gap-0.5 overflow-hidden rounded-full"
                    role="img"
                    aria-label={
                      cast
                        ? `${proposal.votes.yes} yes, ${proposal.votes.no} no, ${proposal.votes.abstain} abstain`
                        : "No votes cast yet"
                    }
                  >
                    {cast ? (
                      voteRows.map((row) => (
                        <span
                          key={row.key}
                          className={cn("h-full rounded-full", barTone[row.tone])}
                          style={{ width: `${(row.count / cast) * 100}%` }}
                        />
                      ))
                    ) : (
                      <span className="h-full w-full rounded-full bg-line" />
                    )}
                  </div>
                  <p className="mt-1.5 text-[11.5px] text-faint">
                    {cast ? `${cast} vote${cast === 1 ? "" : "s"} cast` : "No votes cast yet"}
                  </p>
                </div>

                {proposal.comments.length ? (
                  <div className="space-y-2 border-t border-line pt-3">
                    {proposal.comments.map((comment) => (
                      <div key={comment.id} className="flex gap-2 text-[12.5px]">
                        <MessageSquare size={13} className="mt-0.5 shrink-0 text-faint" />
                        <p className="text-muted">
                          <span className="text-ink">{comment.user?.display_name || "Traveller"}</span>{" "}
                          ({comment.value}): {comment.comment}
                        </p>
                      </div>
                    ))}
                  </div>
                ) : null}

                <ProposalImpact tripId={tripId} proposalId={proposal.id} />

                {proposal.status === "open" ? (
                  <div className="flex flex-wrap gap-2 border-t border-line pt-3">
                    <Button
                      size="sm"
                      variant={proposal.my_vote === "yes" ? "primary" : "secondary"}
                      onClick={() => {
                        setVoting(proposal);
                        setVoteValue("yes");
                      }}
                    >
                      <ThumbsUp size={13} /> Vote
                    </Button>
                    {isAdmin ? (
                      <>
                        <Button
                          size="sm"
                          variant="subtle"
                          loading={approve.isPending && approve.variables === proposal.id}
                          onClick={() => setConfirming({ proposal, action: "approve" })}
                        >
                          <Gavel size={13} /> Approve & apply
                        </Button>
                        <Button
                          size="sm"
                          variant="ghost"
                          loading={reject.isPending && reject.variables === proposal.id}
                          onClick={() => setConfirming({ proposal, action: "reject" })}
                        >
                          <ThumbsDown size={13} /> Reject
                        </Button>
                      </>
                    ) : null}
                    {proposal.created_by === user?.id ? (
                      <Button
                        size="sm"
                        variant="ghost"
                        loading={withdraw.isPending}
                        onClick={() => withdraw.mutate(proposal.id)}
                      >
                        <UserX size={13} /> Withdraw
                      </Button>
                    ) : null}
                  </div>
                ) : null}
              </Card>
            );
          })}
        </div>
      )}

      <FlowNote icon={<AlertTriangle size={15} />}>
        Approval is blocked when a change breaks the Journey Pact or a member's hard budget limit.
        The confirmed itinerary is only rewritten after an explicit approval.
      </FlowNote>

      <Modal open={Boolean(voting)} onClose={() => setVoting(null)} title={voting?.title || "Cast your vote"}>
        {voting ? (
          <div className="space-y-4">
            <div className="grid grid-cols-3 gap-2">
              {(["yes", "abstain", "no"] as const).map((value) => (
                <button
                  key={value}
                  type="button"
                  onClick={() => setVoteValue(value)}
                  aria-pressed={voteValue === value}
                  className={cn(
                    "rounded-xl border px-3 py-3 text-sm transition-colors",
                    voteValue === value
                      ? "border-ink bg-ink text-paper"
                      : "border-line bg-surface text-muted hover:border-ink/30 hover:text-ink",
                  )}
                >
                  {titleCase(value)}
                </button>
              ))}
            </div>
            <Field label="Comment (optional)" hint="Shared with the group on this proposal.">
              <Textarea
                value={voteComment}
                onChange={(event) => setVoteComment(event.target.value)}
                placeholder="Why do you feel this way?"
              />
            </Field>
            <Button
              className="w-full"
              loading={vote.isPending}
              onClick={() =>
                vote.mutate({ proposalId: voting.id, value: voteValue, comment: voteComment })
              }
            >
              Submit vote
            </Button>
          </div>
        ) : null}
      </Modal>

      <Modal
        open={creating}
        onClose={() => setCreating(false)}
        title="Propose an activity"
        wide
      >
        <div className="space-y-3">
          <Field label="Search the catalog" hint="Only activities in this destination can be proposed.">
            <div className="relative">
              <Search size={15} className="absolute left-3 top-3.5 text-faint" />
              <Input
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Museum, viewpoint, food market…"
                className="pl-9"
              />
            </div>
          </Field>
          <div className="max-h-56 space-y-1.5 overflow-y-auto rounded-2xl border border-line p-2">
            {searchResults.isLoading ? (
              <p className="p-2 text-xs text-faint">Searching the catalog…</p>
            ) : searchResults.data?.items.length ? (
              searchResults.data.items.map((entry) => (
                <button
                  key={entry.activity.id}
                  type="button"
                  aria-pressed={draft.activity_id === entry.activity.id}
                  onClick={() =>
                    setDraft((current) => ({
                      ...current,
                      activity_id: entry.activity.id,
                      title: current.title || `Add ${entry.activity.name}`,
                    }))
                  }
                  className={cn(
                    "flex w-full items-center justify-between gap-2 rounded-xl px-3 py-2 text-left text-[13px] transition-colors",
                    draft.activity_id === entry.activity.id
                      ? "bg-ink text-paper"
                      : "hover:bg-raised",
                  )}
                >
                  <span className="truncate">{entry.activity.name}</span>
                  <span className="shrink-0 font-mono text-[10px] opacity-70">
                    {formatMoney(entry.activity.price_estimate, entry.activity.currency)}
                  </span>
                </button>
              ))
            ) : (
              <p className="p-2 text-xs text-faint">
                No catalog activities match. Adjust the destination or search terms.
              </p>
            )}
          </div>
          {selectedActivity ? (
            <p className="rounded-xl bg-raised px-3 py-2 text-[12px] text-muted">
              Selected: <span className="text-ink">{selectedActivity.activity.name}</span>
              {selectedActivity.provenance ? ` · ${selectedActivity.provenance}` : ""}
            </p>
          ) : null}
          <Field label="Proposal title">
            <Input
              value={draft.title}
              onChange={(event) => setDraft({ ...draft, title: event.target.value })}
            />
          </Field>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Day">
              <Input
                type="date"
                min={trip.data?.start_date?.slice(0, 10)}
                max={trip.data?.end_date?.slice(0, 10)}
                value={draft.day || todayIso()}
                onChange={(event) => setDraft({ ...draft, day: event.target.value })}
              />
            </Field>
            <Field label="Start time">
              <Input
                type="time"
                value={draft.start_time}
                onChange={(event) => setDraft({ ...draft, start_time: event.target.value })}
              />
            </Field>
          </div>
          <Field label="Why this?" hint="Context helps the group decide faster.">
            <Textarea
              value={draft.summary}
              onChange={(event) => setDraft({ ...draft, summary: event.target.value })}
            />
          </Field>
          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={() => setCreating(false)}>
              Cancel
            </Button>
            <Button
              loading={create.isPending}
              disabled={!draft.activity_id || !draft.title.trim()}
              onClick={() => create.mutate()}
            >
              <ChevronDown size={14} /> Open proposal
            </Button>
          </div>
        </div>
      </Modal>

      <Modal
        open={Boolean(confirming)}
        onClose={() => setConfirming(null)}
        title={confirming?.action === "approve" ? "Approve and apply?" : "Reject this proposal?"}
        description={
          confirming
            ? confirming.action === "approve"
              ? "The confirmed itinerary is rewritten as a new version for everyone in the group."
              : "The proposal closes as rejected and the author is notified."
            : undefined
        }
        footer={
          <>
            <Button variant="secondary" onClick={() => setConfirming(null)}>
              {confirming?.action === "approve" ? "Not yet" : "Keep it open"}
            </Button>
            {confirming?.action === "approve" ? (
              <Button
                loading={approve.isPending}
                onClick={() => confirming && approve.mutate(confirming.proposal.id)}
              >
                <Gavel size={14} /> Approve & apply
              </Button>
            ) : (
              <Button
                variant="danger"
                loading={reject.isPending}
                onClick={() => confirming && reject.mutate(confirming.proposal.id)}
              >
                <ThumbsDown size={14} /> Reject proposal
              </Button>
            )}
          </>
        }
      >
        <p className="text-sm leading-6 text-muted">
          {confirming?.proposal.title
            ? `“${confirming.proposal.title}”`
            : "This proposal will be closed."}{" "}
          {confirming?.action === "approve"
            ? "Approval is blocked automatically if the change breaks the Journey Pact or a member's hard budget limit."
            : "Votes already cast stay on the record."}
        </p>
      </Modal>
    </div>
  );
}

function ProposalImpact({ tripId, proposalId }: { tripId: string; proposalId: string }) {
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const detail = useQuery({
    queryKey: ["proposal-detail", tripId, proposalId],
    queryFn: () =>
      api<Proposal & {
        impact?: {
          cost_impact?: { total_delta: number; per_member_estimate: number; currency: string };
          budget_conflicts?: { reason: string; item: string }[];
          pact_conflicts?: { item: string; rule: string; resolution: string }[];
          schedule_conflicts?: {
            item: string;
            proposed?: string;
            reason: string;
            protected: boolean;
          }[];
        };
      }>(`/api/trips/${tripId}/proposals/${proposalId}`),
    enabled: open,
  });

  return (
    <div className="border-t border-line pt-3">
      <button
        type="button"
        onClick={() => setOpen((value) => !value)}
        aria-expanded={open}
        aria-controls={panelId}
        className="flex w-full items-center justify-between text-[12px] text-muted transition-colors hover:text-ink"
      >
        <span>Impact if approved</span>
        <ChevronDown
          size={14}
          className={cn("transition-transform", open ? "rotate-180" : "")}
        />
      </button>
      {open ? (
        <div id={panelId}>
        {detail.isLoading ? (
          <p className="mt-2 text-[12px] text-faint">Calculating…</p>
        ) : detail.error ? (
          <p className="mt-2 text-[12px] text-rose">{(detail.error as Error).message}</p>
        ) : detail.data?.impact ? (
          <div className="mt-2 space-y-2 rounded-xl bg-raised/60 p-3 text-[12px] text-muted">
            {detail.data.impact.cost_impact ? (
              <p>
                Cost change:{" "}
                <span className="font-mono text-ink">
                  {formatMoney(
                    detail.data.impact.cost_impact.total_delta,
                    detail.data.impact.cost_impact.currency,
                  )}
                </span>{" "}
                total · {formatMoney(detail.data.impact.cost_impact.per_member_estimate, detail.data.impact.cost_impact.currency)} per member (estimate)
              </p>
            ) : null}
            {(detail.data.impact.pact_conflicts || []).map((conflict, index) => (
              <p key={`pact-${index}`} className="text-rose">
                Pact conflict: {conflict.item} — {conflict.resolution}
              </p>
            ))}
            {(detail.data.impact.budget_conflicts || []).map((conflict, index) => (
              <p key={`budget-${index}`} className="text-rose">
                Budget: {conflict.item} — {conflict.reason}
              </p>
            ))}
            {(detail.data.impact.schedule_conflicts || []).map((conflict, index) => (
              <p key={`schedule-${index}`} className="text-rose">
                {conflict.protected ? "Protected time" : "Schedule"}: {conflict.item}
                {conflict.proposed ? ` vs ${conflict.proposed}` : ""} — {conflict.reason}
              </p>
            ))}
            {!detail.data.impact.cost_impact ? (
              <p>No cost impact recorded for this proposal.</p>
            ) : null}
          </div>
        ) : (
          <p className="mt-2 text-[12px] text-faint">No impact data returned.</p>
        )}
        </div>
      ) : null}
    </div>
  );
}
