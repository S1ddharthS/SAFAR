"use client";

import { Bell, CheckCheck } from "lucide-react";
import Link from "next/link";
import { useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  PageHeader,
  PageSkeleton,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useNotifications } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { errorMessage, formatDateTime, titleCase } from "@/lib/utils";

export default function NotificationsPage() {
  const notifications = useNotifications();
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);
  const [busy, setBusy] = useState(false);

  if (notifications.isLoading) return <PageSkeleton />;
  if (notifications.error) {
    return <ErrorState error={notifications.error} retry={() => notifications.refetch()} />;
  }

  const items = notifications.data?.items ?? [];
  const unread = notifications.data?.unread ?? 0;

  const mark = async (id: string) => {
    try {
      await api(`/api/users/me/notifications/${id}/read`, { method: "POST", body: { read: true } });
      await queryClient.invalidateQueries({ queryKey: ["notifications"] });
    } catch (error) {
      push("Could not mark as read", errorMessage(error), "error");
    }
  };

  const markAll = async () => {
    setBusy(true);
    try {
      await api("/api/users/me/notifications/read-all", { method: "POST" });
      await queryClient.invalidateQueries({ queryKey: ["notifications"] });
    } catch (error) {
      push("Could not mark all as read", errorMessage(error), "error");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        eyebrow="Notifications"
        title="Only what needs you"
        description="Quiet mode and the Decision Load Governor keep this list short. Notifications never reveal private member data."
        actions={
          <Button variant="secondary" size="sm" onClick={markAll} loading={busy}>
            <CheckCheck size={14} /> Mark all read
          </Button>
        }
      />

      <div className="flex items-center gap-2">
        <Badge tone={unread > 0 ? "ember" : "outline"}>{unread} unread</Badge>
        <Badge tone="outline">{items.length} total</Badge>
      </div>

      {items.length === 0 ? (
        <EmptyState
          icon={<Bell size={26} />}
          title="Nothing waiting"
          description="When a proposal opens, a member joins or a tracked fact changes, it will appear here."
        />
      ) : (
        <div className="space-y-2">
          {items.map((item) => (
            <Card
              key={item.id}
              className={`p-0 ${item.read ? "opacity-80" : "border-ember/30"}`}
            >
              <div className="flex gap-3 p-4">
                <span
                  className={`mt-1 h-2 w-2 shrink-0 rounded-full ${
                    item.read ? "bg-line" : "bg-ember"
                  }`}
                />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge tone={item.read ? "outline" : "ember"}>{titleCase(item.kind)}</Badge>
                    <span className="text-[12px] text-faint">{formatDateTime(item.created_at)}</span>
                  </div>
                  <p className="mt-1.5 text-[14px] font-medium">{item.title}</p>
                  {item.body ? (
                    <p className="mt-0.5 text-[12.5px] leading-5 text-muted">{item.body}</p>
                  ) : null}
                  <div className="mt-2 flex flex-wrap items-center gap-3 text-[12px]">
                    {item.link ? (
                      <Link href={item.link} className="font-medium text-ember hover:underline">
                        Open
                      </Link>
                    ) : null}
                    {!item.read ? (
                      <button onClick={() => mark(item.id)} className="text-muted hover:text-ink">
                        Mark read
                      </button>
                    ) : null}
                  </div>
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
