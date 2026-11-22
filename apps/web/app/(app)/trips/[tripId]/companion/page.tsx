"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Check, Copy, Link2, RotateCcw, ShieldCheck, Ticket, UserCheck } from "lucide-react";
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
  PageSkeleton,
  SectionTitle,
  Select,
  Stat,
} from "@/components/ui";
import { api } from "@/lib/api";
import {
  useCompanionLinks,
  useItinerary,
  useProposals,
  useTrip,
} from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { CompanionLink } from "@/lib/types";
import { formatDateTime, titleCase } from "@/lib/utils";

const STATUS_TONE: Record<CompanionLink["status"], "jade" | "neutral" | "rose" | "outline"> = {
  active: "jade",
  used: "neutral",
  expired: "outline",
  revoked: "rose",
};

export default function CompanionPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const itinerary = useItinerary(tripId);
  const proposals = useProposals(tripId, "open");
  const links = useCompanionLinks(tripId);
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);

  const [purpose, setPurpose] = useState<"vote" | "checkin">("vote");
  const [targetId, setTargetId] = useState("");
  const [ttl, setTtl] = useState(1440);
  const [created, setCreated] = useState<{ url: string; token: string } | null>(null);

  const voteTargets = proposals.data?.items ?? [];
  const checkinTargets = (itinerary.data?.items ?? []).filter(
    (item) => item.status === "confirmed",
  );
  const targets = purpose === "vote" ? voteTargets : checkinTargets;

  const create = useMutation({
    mutationFn: () =>
      api<{ link: CompanionLink; token: string; url: string; disclosure: string }>(
        `/api/trips/${tripId}/companion-links`,
        { method: "POST", body: { purpose, target_id: targetId, ttl_minutes: ttl } },
      ),
    onSuccess: (data) => {
      setCreated({ url: data.url, token: data.token });
      setTargetId("");
      push("Link created", "Copy it now — the token is shown only once.", "success");
      queryClient.invalidateQueries({ queryKey: ["companion-links", tripId] });
    },
    onError: (error: Error) => push("Could not create the link", error.message, "error"),
  });

  const revoke = useMutation({
    mutationFn: (linkId: string) =>
      api(`/api/trips/${tripId}/companion-links/${linkId}/revoke`, { method: "POST" }),
    onSuccess: () => {
      push("Link revoked", "The link can no longer be answered.", "success");
      queryClient.invalidateQueries({ queryKey: ["companion-links", tripId] });
    },
    onError: (error: Error) => push("Could not revoke", error.message, "error"),
  });

  const copy = async () => {
    if (!created) return;
    const absolute = `${window.location.origin}${created.url}`;
    try {
      await navigator.clipboard.writeText(absolute);
      push("Copied", "The companion link is on your clipboard.", "success");
    } catch {
      push("Copy failed", absolute, "error");
    }
  };

  if (trip.isLoading) return <PageSkeleton />;
  if (trip.error || !trip.data) {
    return <ErrorState error={trip.error || new Error("Trip not found")} retry={() => trip.refetch()} />;
  }

  const rows = links.data?.items ?? [];
  const active = rows.filter((row) => row.status === "active").length;
  const answers = rows.reduce((total, row) => total + row.anonymous_responses, 0);

  return (
    <div className="space-y-6">
      <div>
        <p className="eyebrow flex items-center gap-1.5">
          <Link2 size={12} /> One-Link Companion
        </p>
        <h2 className="mt-1 text-2xl">One answer, no account</h2>
        <p className="mt-1 max-w-prose text-sm text-muted">
          Share a single decision or check-in with somebody outside the trip. Each link answers one
          question once, expires on its own, and records no identity.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <Stat label="Links" value={rows.length} hint="Created for this trip" />
        <Stat label="Active" value={active} tone="jade" hint="Still answerable" />
        <Stat label="Anonymous answers" value={answers} tone="ember" hint="No identity stored" />
      </div>

      <Card className="space-y-4">
        <SectionTitle title="Create a link" hint="Scope is fixed to one target" />
        <div className="flex flex-wrap gap-2">
          <Button
            type="button"
            variant={purpose === "vote" ? "primary" : "secondary"}
            size="sm"
            onClick={() => {
              setPurpose("vote");
              setTargetId("");
            }}
          >
            <Ticket size={14} /> Vote
          </Button>
          <Button
            type="button"
            variant={purpose === "checkin" ? "primary" : "secondary"}
            size="sm"
            onClick={() => {
              setPurpose("checkin");
              setTargetId("");
            }}
          >
            <UserCheck size={14} /> Check-in
          </Button>
        </div>

        <div className="grid gap-3 sm:grid-cols-[1.6fr_1fr_auto] sm:items-end">
          <Field
            label={purpose === "vote" ? "Open decision" : "Confirmed item"}
            hint={
              purpose === "vote"
                ? "Only open decisions can be shared."
                : "Only confirmed itinerary items can be shared."
            }
          >
            <Select value={targetId} onChange={(event) => setTargetId(event.target.value)}>
              <option value="">Choose…</option>
              {targets.map((target) => (
                <option key={target.id} value={target.id}>
                  {"title" in target && target.title ? target.title : target.id}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Expires" hint="Single use regardless">
            <Select value={ttl} onChange={(event) => setTtl(Number(event.target.value))}>
              <option value={60}>In 1 hour</option>
              <option value={1440}>In 24 hours</option>
              <option value={10080}>In 7 days</option>
            </Select>
          </Field>
          <Button
            onClick={() => create.mutate()}
            disabled={!targetId || create.isPending}
            className="h-11"
          >
            {create.isPending ? "Creating…" : "Create link"}
          </Button>
        </div>

        {created ? (
          <div className="space-y-2 rounded-2xl border border-jade/30 bg-jade-soft/40 p-3.5">
            <p className="flex items-center gap-1.5 text-sm font-medium text-jade">
              <Check size={14} /> Link ready — copy it now
            </p>
            <div className="flex flex-col gap-2 sm:flex-row">
              <code className="min-w-0 flex-1 break-all rounded-xl border border-line bg-surface px-3 py-2 font-mono text-[12px] text-ink">
                {typeof window !== "undefined" ? `${window.location.origin}${created.url}` : created.url}
              </code>
              <Button type="button" variant="secondary" size="sm" onClick={copy}>
                <Copy size={14} /> Copy
              </Button>
            </div>
            <p className="text-[12px] text-muted">
              The token is not stored in readable form and is never shown again.
            </p>
          </div>
        ) : null}

        {!targets.length ? (
          <p className="text-sm text-muted">
            {purpose === "vote"
              ? "There is no open decision to share right now."
              : "No confirmed itinerary items are available yet."}
          </p>
        ) : null}
      </Card>

      <section className="space-y-3">
        <SectionTitle
          title="Your links"
          hint="Owners and admins see every link in the trip"
        />
        {links.isLoading ? (
          <PageSkeleton />
        ) : links.error ? (
          <ErrorState error={links.error} retry={() => links.refetch()} />
        ) : rows.length === 0 ? (
          <EmptyState
            title="No links yet"
            description="Create a vote or check-in link above to invite one answer without an account."
            icon={<Link2 size={24} />}
          />
        ) : (
          <div className="space-y-2.5">
            {rows.map((row) => (
              <Card key={row.id} className="space-y-2">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <Badge tone={row.purpose === "vote" ? "ember" : "neutral"}>
                        {row.purpose === "vote" ? "Vote" : "Check-in"}
                      </Badge>
                      <p className="text-sm font-medium text-ink">{row.target.title}</p>
                      <Badge tone={STATUS_TONE[row.status]}>{titleCase(row.status)}</Badge>
                    </div>
                    <p className="mt-1 text-[12px] text-faint">
                      {row.used_count}/{row.max_uses} used · expires {formatDateTime(row.expires_at)} ·{" "}
                      {row.anonymous_responses} anonymous answer(s)
                    </p>
                  </div>
                  {row.status === "active" ? (
                    <Button
                      type="button"
                      variant="secondary"
                      size="sm"
                      onClick={() => revoke.mutate(row.id)}
                      disabled={revoke.isPending}
                    >
                      <RotateCcw size={13} /> Revoke
                    </Button>
                  ) : null}
                </div>
                {Object.keys(row.response_values || {}).length ? (
                  <div className="flex flex-wrap gap-1.5">
                    {Object.entries(row.response_values).map(([value, count]) => (
                      <Badge key={value} tone="outline">
                        {titleCase(value)} · {count}
                      </Badge>
                    ))}
                  </div>
                ) : null}
              </Card>
            ))}
          </div>
        )}
      </section>

      <FlowNote icon={<ShieldCheck size={15} />}>
        Links are signed, scoped to one proposal or itinerary item, single-use and expiring. Responses
        are anonymous: no account, email, IP address or device identifier is stored. A link never
        changes the confirmed plan.
      </FlowNote>
    </div>
  );
}
