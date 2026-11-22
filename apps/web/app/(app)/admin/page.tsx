"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ShieldCheck, SlidersHorizontal } from "lucide-react";
import { useState } from "react";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  FlowNote,
  Input,
  PageHeader,
  PageSkeleton,
  SectionTitle,
  Select,
  Stat,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useAbuseReports, useAdminStats, useMe } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { formatDateTime, titleCase } from "@/lib/utils";

const STATUS_TABS = [
  { href: "open", label: "Open" },
  { href: "resolved", label: "Resolved" },
  { href: "dismissed", label: "Dismissed" },
  { href: "all", label: "All" },
];

export default function AdminPage() {
  const me = useMe();
  const isAdmin = Boolean(me.data?.user.is_admin);
  const stats = useAdminStats(isAdmin);
  const [status, setStatus] = useState("open");
  const reports = useAbuseReports(isAdmin, status);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);

  const decide = useMutation({
    mutationFn: ({ id, decision }: { id: string; decision: "dismiss" | "hide_content" | "warn" }) =>
      api(`/api/admin/abuse-reports/${id}/decide`, {
        method: "POST",
        body: { decision, note: notes[id] || null },
      }),
    onSuccess: () => {
      push("Moderation recorded", "The reporter was notified without revealing reviewer identity.", "success");
      queryClient.invalidateQueries({ queryKey: ["abuse-reports"] });
      queryClient.invalidateQueries({ queryKey: ["admin"] });
    },
    onError: (error) => push("Could not record decision", (error as Error).message, "error"),
  });

  if (me.isLoading) return <PageSkeleton />;
  if (!isAdmin) {
    return (
      <EmptyState
        title="Admins only"
        description="This area is limited to platform administrators. If you believe you should have access, contact the operator of this deployment."
        icon={<ShieldCheck size={26} />}
        action={
          <a href="/dashboard" className="text-sm text-ember hover:underline">
            Back to dashboard
          </a>
        }
      />
    );
  }

  return (
    <div className="space-y-8">
      <PageHeader
        eyebrow="Platform stewardship"
        title="Admin"
        description="Moderation queues, verification and ecosystem health. Admin actions are audited; reviewer identity is never exposed to reporters."
      />

      {stats.isLoading ? (
        <PageSkeleton />
      ) : stats.error ? (
        <ErrorState error={stats.error} retry={() => stats.refetch()} />
      ) : (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
          <Stat label="Travellers" value={stats.data?.users ?? 0} />
          <Stat label="Journeys" value={stats.data?.trips ?? 0} />
          <Stat label="Open proposals" value={stats.data?.proposals_open ?? 0} tone="ember" />
          <Stat label="Engine batches" value={stats.data?.recommendation_batches ?? 0} />
          <Stat label="Memories" value={stats.data?.memories ?? 0} />
          <Stat label="Expenses" value={stats.data?.expenses ?? 0} />
          <Stat label="Place reports" value={stats.data?.place_reports ?? 0} />
          <Stat
            label="Open reports"
            value={stats.data?.open_abuse_reports ?? 0}
            tone={stats.data?.open_abuse_reports ? "rose" : "jade"}
          />
          <Stat label="Audit events" value={stats.data?.audit_events ?? 0} />
          <Stat label="Memberships" value={stats.data?.memberships ?? 0} />
        </div>
      )}

      <section>
        <SectionTitle
          title="Abuse reports"
          hint="Review reports, hide content where appropriate, or warn accounts."
          action={
            <Select
              value={status}
              onChange={(event) => setStatus(event.target.value)}
              className="h-9 w-36"
              aria-label="Filter reports"
            >
              {STATUS_TABS.map((tab) => (
                <option key={tab.href} value={tab.href}>
                  {tab.label}
                </option>
              ))}
            </Select>
          }
        />

        {reports.isLoading ? (
          <PageSkeleton />
        ) : reports.error ? (
          <ErrorState error={reports.error} retry={() => reports.refetch()} />
        ) : !reports.data?.items.length ? (
          <EmptyState
            title="Nothing waiting"
            description="No reports match this filter. The queue is clear."
            icon={<SlidersHorizontal size={24} />}
          />
        ) : (
          <div className="space-y-3">
            {reports.data.items.map((report) => (
              <Card key={report.id} className="space-y-3">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <Badge tone={report.status === "open" ? "ember" : "outline"}>
                        {titleCase(report.status)}
                      </Badge>
                      <Badge tone="neutral">{titleCase(report.target_type)}</Badge>
                      {report.target_id ? (
                        <span className="font-mono text-[10px] text-faint">{report.target_id}</span>
                      ) : null}
                    </div>
                    <p className="mt-2 text-sm leading-6 text-ink">{report.reason}</p>
                    <p className="mt-1 text-[12px] text-faint">
                      Reported by {report.reporter?.display_name || "a traveller"} ·{" "}
                      {formatDateTime(report.created_at)}
                    </p>
                  </div>
                </div>

                {report.status === "open" ? (
                  <div className="space-y-2 rounded-2xl border border-line bg-raised/60 p-3">
                    <Input
                      placeholder="Optional note for the account holder (warnings only)"
                      value={notes[report.id] || ""}
                      onChange={(event) =>
                        setNotes((current) => ({ ...current, [report.id]: event.target.value }))
                      }
                    />
                    <div className="flex flex-wrap gap-2">
                      <Button
                        size="sm"
                        variant="danger"
                        loading={decide.isPending}
                        onClick={() => decide.mutate({ id: report.id, decision: "hide_content" })}
                        disabled={!report.target_id || !["post", "memory"].includes(report.target_type)}
                      >
                        Hide content
                      </Button>
                      <Button
                        size="sm"
                        variant="secondary"
                        loading={decide.isPending}
                        onClick={() => decide.mutate({ id: report.id, decision: "warn" })}
                      >
                        Warn account
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        loading={decide.isPending}
                        onClick={() => decide.mutate({ id: report.id, decision: "dismiss" })}
                      >
                        Dismiss
                      </Button>
                    </div>
                  </div>
                ) : null}
              </Card>
            ))}
          </div>
        )}
      </section>

      <FlowNote>
        Place reports can be verified from the place detail screen by an admin. Verification raises
        confidence, but community observations stay labelled as reported until a source supports them.
      </FlowNote>
    </div>
  );
}
