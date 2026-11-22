"use client";

import { ArrowUpRight, Feather, Route, Sparkles } from "lucide-react";
import Link from "next/link";

import {
  Badge,
  Card,
  EmptyState,
  ErrorState,
  LinkButton,
  PageHeader,
  PageSkeleton,
  Stat,
} from "@/components/ui";
import { useThread } from "@/lib/hooks";
import { formatMoney } from "@/lib/utils";

export default function ThreadPage() {
  const thread = useThread();

  if (thread.isLoading) return <PageSkeleton />;
  if (thread.error || !thread.data) {
    return <ErrorState error={thread.error} retry={() => thread.refetch()} />;
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        eyebrow="Journey Thread"
        title="What you carry forward"
        description="Traditions and favourites from journeys you consented to share. Repeat, modify or avoid them in the next trip."
        actions={
          <LinkButton href="/discover" variant="secondary" size="sm">
            Find a place
          </LinkButton>
        }
      />

      <div className="grid gap-3 sm:grid-cols-3">
        <Stat label="Completed journeys" value={thread.data.completed_trips} hint="past trips considered" />
        <Stat label="Traditions" value={thread.data.traditions.length} hint="positive signals" tone="jade" />
        <Stat label="Consent" value="Opt-in" hint="only shared feedback is used" tone="ember" />
      </div>

      {thread.data.traditions.length === 0 ? (
        <EmptyState
          icon={<Feather size={26} />}
          title="Your thread is still blank"
          description="Finish a journey and share feedback with consent. Loved and would-return signals become traditions here."
          action={<LinkButton href="/dashboard" size="sm">Open your journeys</LinkButton>}
        />
      ) : (
        <div className="space-y-3">
          {thread.data.traditions.map((tradition, index) => (
            <Card key={tradition.activity_id} className="flex items-start gap-4">
              <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-line bg-raised font-display text-[15px] text-ember">
                {index + 1}
              </span>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <h3 className="text-lg leading-snug">{tradition.name}</h3>
                  <Badge tone="jade">{tradition.sentiments.length} signal{tradition.sentiments.length === 1 ? "" : "s"}</Badge>
                </div>
                <p className="mt-1 text-[12px] text-muted">
                  {tradition.duration_minutes} min · {formatMoney(tradition.price_estimate)}
                </p>
                <p className="mt-1 text-[12px] text-faint">
                  Signals: {tradition.sentiments.join(", ").replace(/_/g, " ")}
                </p>
              </div>
              <Link
                href="/discover"
                className="shrink-0 text-faint hover:text-ink"
                aria-label={`Find something like ${tradition.name}`}
              >
                <ArrowUpRight size={16} />
              </Link>
            </Card>
          ))}
        </div>
      )}

      <Card className="bg-raised/40">
        <div className="flex gap-3">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-line bg-surface text-ember">
            <Route size={16} />
          </span>
          <div>
            <p className="text-[13.5px] font-medium">How the thread works</p>
            <p className="mt-1 text-[12px] leading-6 text-muted">{thread.data.note}</p>
            <p className="mt-2 flex items-center gap-1.5 text-[12px] text-faint">
              <Sparkles size={12} /> No private preference is exposed to other travellers.
            </p>
          </div>
        </div>
      </Card>
    </div>
  );
}
