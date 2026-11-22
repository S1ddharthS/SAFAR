"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  CloudOff,
  CloudUpload,
  Download,
  MapPin,
  RefreshCw,
  Shield,
  Wifi,
  WifiOff,
} from "lucide-react";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  FlowNote,
  PageSkeleton,
  SectionTitle,
  Stat,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useOfflineSnapshot, useSyncQueue } from "@/lib/hooks";
import { useOffline, useToasts } from "@/lib/store";
import { errorMessage, formatDate, formatDateTime, formatMoney } from "@/lib/utils";

interface SyncResult {
  client_id: string;
  status: string;
  reason?: string;
  id?: string;
}

export default function OfflinePage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const snapshot = useOfflineSnapshot(tripId);
  const serverQueue = useSyncQueue(tripId);
  const offline = useOffline();
  const queryClient = useQueryClient();
  const { push } = useToasts();

  const [online, setOnline] = useState(true);
  const [results, setResults] = useState<SyncResult[]>([]);

  useEffect(() => {
    setOnline(navigator.onLine);
    const update = () => setOnline(navigator.onLine);
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);

  const queued = offline.queue.filter((item) => item.trip_id === tripId);

  const sync = useMutation({
    mutationFn: () =>
      api<SyncResult[]>(`/api/trips/${tripId}/sync`, {
        method: "POST",
        body: queued.map((item) => ({
          client_id: item.client_id,
          operation: item.operation,
          payload: item.payload,
        })),
      }),
    onSuccess: (data) => {
      setResults(data);
      const settled = data.filter((entry) => entry.status === "applied" || entry.status === "skipped");
      offline.clear(settled.map((entry) => entry.client_id));
      const rejected = data.filter((entry) => entry.status === "rejected");
      push(
        "Sync complete",
        `${settled.length} applied, ${rejected.length} rejected.`,
        rejected.length ? "error" : "success",
      );
      queryClient.invalidateQueries({ queryKey: ["sync", tripId] });
      queryClient.invalidateQueries({ queryKey: ["memories", tripId] });
      queryClient.invalidateQueries({ queryKey: ["offline", tripId] });
    },
    onError: (error) => push("Sync failed", errorMessage(error), "error"),
  });

  const downloadSnapshot = () => {
    if (!snapshot.data) return;
    const blob = new Blob([JSON.stringify(snapshot.data, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `safar-offline-${tripId}.json`;
    link.click();
    URL.revokeObjectURL(url);
  };

  if (snapshot.isLoading) return <PageSkeleton />;
  if (snapshot.error || !snapshot.data) {
    return <ErrorState error={snapshot.error || new Error("Snapshot unavailable")} retry={() => snapshot.refetch()} />;
  }

  const data = snapshot.data;
  const isStale = new Date(data.stale_after).getTime() < Date.now();

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Offline</p>
          <h2 className="mt-1 text-2xl">The plan, without a signal</h2>
          <p className="mt-1 max-w-prose text-sm text-muted">
            Snapshot the confirmed plan, members and meeting points. Private budgets, access needs and private
            memories are excluded.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Badge tone={online ? "jade" : "ember"}>
            {online ? <Wifi size={10} /> : <WifiOff size={10} />} {online ? "Online" : "Offline"}
          </Badge>
          <Button variant="secondary" size="sm" onClick={downloadSnapshot}>
            <Download size={14} /> Download JSON
          </Button>
          <Button
            size="sm"
            onClick={() => sync.mutate()}
            loading={sync.isPending}
            disabled={!queued.length || !online}
          >
            <CloudUpload size={14} /> Sync queue
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        <Stat label="Confirmed items" value={data.items.length} tone="ink" />
        <Stat label="Members" value={data.members.length} tone="ember" />
        <Stat label="Queued" value={queued.length} tone={queued.length ? "ember" : "jade"} />
        <Stat label="Version" value={`v${data.confirmed_version}`} tone="ink" />
      </div>

      <FlowNote icon={isStale ? <CloudOff size={14} /> : <Shield size={14} />}>
        Generated {formatDateTime(data.generated_at)} · stale after {formatDateTime(data.stale_after)}.
        {isStale ? " This snapshot is stale — refresh before relying on it." : " Refresh before travelling if the plan changed."}
      </FlowNote>

      {queued.length ? (
        <Card className="space-y-3">
          <SectionTitle title="Waiting to sync" hint="Captured while offline — review before sending" />
          <div className="space-y-2">
            {queued.map((item) => (
              <div key={item.client_id} className="rounded-xl border border-line bg-surface px-3 py-2">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <Badge tone="ember">{item.operation.replace(/_/g, " ")}</Badge>
                  <span className="text-[10.5px] text-faint">{formatDateTime(item.created_at)}</span>
                </div>
                <p className="mt-1 line-clamp-2 text-[12px] text-muted">
                  {String((item.payload as { text_content?: string }).text_content || "Offline capture")}
                </p>
              </div>
            ))}
          </div>
          {results.length ? (
            <div className="space-y-1">
              {results.map((entry) => (
                <p key={entry.client_id} className="text-[12px] text-muted">
                  {entry.client_id.slice(-6)} · {entry.status}
                  {entry.reason ? ` — ${entry.reason}` : ""}
                </p>
              ))}
            </div>
          ) : null}
        </Card>
      ) : (
        <EmptyState
          title="Nothing queued"
          description="Memories saved offline from the timeline appear here until synced."
          icon={<CloudOff size={24} />}
        />
      )}

      <Card className="space-y-3">
        <SectionTitle
          title="Snapshot"
          hint={`${data.trip.destination} · ${formatDate(data.trip.start_date)} → ${formatDate(data.trip.end_date)}`}
          action={
            <Button size="sm" variant="ghost" onClick={() => snapshot.refetch()}>
              <RefreshCw size={13} /> Refresh
            </Button>
          }
        />
        <div className="space-y-1.5">
          {data.items.map((item) => (
            <div key={item.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-line bg-surface px-2.5 py-1.5 text-[12px]">
              <span className="text-ink">
                {formatDate(item.day)} · {item.start_time} · {item.title}
              </span>
              <span className="flex items-center gap-2 text-[10.5px] text-faint">
                {item.place?.name ? (
                  <span className="inline-flex items-center gap-0.5">
                    <MapPin size={10} /> {item.place.name}
                  </span>
                ) : null}
                <span>{formatMoney(item.cost_estimate, data.trip.currency)}</span>
                {item.is_protected ? <Badge tone="jade">protected</Badge> : null}
              </span>
            </div>
          ))}
          {data.items.length === 0 ? <p className="text-sm text-muted">No confirmed items to snapshot yet.</p> : null}
        </div>
        {data.pact ? (
          <div className="flex flex-wrap gap-1.5">
            {data.pact.must_do.map((entry) => (
              <Badge key={entry} tone="neutral">
                must: {entry}
              </Badge>
            ))}
            {Object.entries(data.pact.confirmed_times).map(([label, time]) => (
              <Badge key={label} tone="outline">
                {label} {time}
              </Badge>
            ))}
          </div>
        ) : null}
        <FlowNote icon={<Shield size={14} />}>{data.disclosure}</FlowNote>
      </Card>

      <Card className="space-y-3">
        <SectionTitle title="Sync history" hint="Server view of your offline captures" />
        {serverQueue.data?.items.length ? (
          <div className="space-y-1.5">
            {serverQueue.data.items.map((entry) => (
              <div key={entry.client_id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-line bg-surface px-2.5 py-1.5">
                <span className="text-[12px] text-muted">
                  {entry.operation.replace(/_/g, " ")} · {entry.client_id.slice(-8)}
                </span>
                <span className="flex items-center gap-2 text-[10.5px] text-faint">
                  <Badge tone={entry.status === "applied" ? "jade" : entry.status === "rejected" ? "rose" : "outline"}>
                    {entry.status}
                  </Badge>
                  {entry.applied_at ? formatDateTime(entry.applied_at) : "pending"}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-muted">Nothing synced yet.</p>
        )}
      </Card>
    </div>
  );
}
