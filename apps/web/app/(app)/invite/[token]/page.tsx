"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { CalendarDays, Check, MailQuestion, Users } from "lucide-react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";

import {
  Badge,
  Button,
  Card,
  ErrorState,
  FlowNote,
  LinkButton,
  PageSkeleton,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useInvitation } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { formatDate, titleCase } from "@/lib/utils";

export default function InvitationPage() {
  const params = useParams<{ token: string }>();
  const token = typeof params?.token === "string" ? params.token : "";
  const invitation = useInvitation(token);
  const router = useRouter();
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);

  const accept = useMutation({
    mutationFn: () => api<{ id: string }>(`/api/invitations/${token}/accept`, { method: "POST" }),
    onSuccess: (trip) => {
      queryClient.invalidateQueries({ queryKey: ["trips"] });
      push("You're in", "The journey now appears on your dashboard.", "success");
      router.replace(`/trips/${trip.id}`);
    },
    onError: (error) => push("Could not join", (error as Error).message, "error"),
  });

  if (invitation.isLoading) return <PageSkeleton />;
  if (invitation.error || !invitation.data) {
    return (
      <div className="mx-auto max-w-lg py-10">
        <ErrorState
          error={invitation.error || new Error("This invitation could not be found")}
          retry={() => invitation.refetch()}
        />
        <div className="mt-4">
          <LinkButton href="/dashboard" variant="secondary" size="sm">
            Back to dashboard
          </LinkButton>
        </div>
      </div>
    );
  }

  const data = invitation.data;
  const alreadyMember = data.already_member;
  const invitationUsed = data.accepted && !data.already_member && !data.accepted_by_you;

  return (
    <div className="mx-auto max-w-xl space-y-6 py-6">
      <div className="text-center">
        <p className="eyebrow">Journey invitation</p>
        <h1 className="mt-2 text-balance text-4xl leading-[1.06]">{data.trip.name}</h1>
        <p className="mt-2 text-sm text-muted">
          {data.invited_by ? `${data.invited_by} invited you to join.` : "You have been invited to join."}
        </p>
      </div>

      <Card className="space-y-4">
        <div className="flex flex-wrap gap-2">
          <Badge tone="ember">{titleCase(data.role)}</Badge>
          <Badge tone="outline">{titleCase(data.scope)} access</Badge>
          {alreadyMember ? <Badge tone="jade">Already a member</Badge> : null}
        </div>

        <dl className="grid gap-3 text-sm sm:grid-cols-2">
          <div>
            <dt className="text-[12px] uppercase tracking-editorial text-faint">Destination</dt>
            <dd className="mt-0.5 flex items-center gap-1.5 text-ink">
              <MailQuestion size={14} className="text-faint" />
              {data.trip.destination_name || "Open"}
            </dd>
          </div>
          <div>
            <dt className="text-[12px] uppercase tracking-editorial text-faint">Dates</dt>
            <dd className="mt-0.5 flex items-center gap-1.5 text-ink">
              <CalendarDays size={14} className="text-faint" />
              {formatDate(data.trip.start_date)} → {formatDate(data.trip.end_date)}
            </dd>
          </div>
          <div>
            <dt className="text-[12px] uppercase tracking-editorial text-faint">Group</dt>
            <dd className="mt-0.5 flex items-center gap-1.5 text-ink">
              <Users size={14} className="text-faint" />
              {data.trip.member_count} of {data.trip.group_size} places filled
            </dd>
          </div>
          <div>
            <dt className="text-[12px] uppercase tracking-editorial text-faint">Expires</dt>
            <dd className="mt-0.5 text-ink">{formatDate(data.expires_at)}</dd>
          </div>
        </dl>

        {alreadyMember ? (
          <LinkButton href={`/trips/${data.trip.id}`} size="lg" className="w-full">
            <Check size={16} /> Open the journey
          </LinkButton>
        ) : invitationUsed ? (
          <div className="rounded-xl border border-line bg-surface px-4 py-3 text-sm text-muted">
            This invitation has already been used. Ask the trip owner for a new link.
          </div>
        ) : (
          <Button
            size="lg"
            className="w-full"
            loading={accept.isPending}
            onClick={() => accept.mutate()}
          >
            Accept and join
          </Button>
        )}
        <p className="text-center text-[12px] text-faint">
          Not for you?{" "}
          <Link href="/dashboard" className="text-ember hover:underline">
            Return to your dashboard
          </Link>
        </p>
      </Card>

      <FlowNote>
        Joining shows the shared plan and group decisions. Your budget limit, accessibility needs and
        private memories stay private to you unless you choose to share them.
      </FlowNote>
    </div>
  );
}
