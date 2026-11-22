"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Copy,
  Link2,
  Lock,
  Mail,
  ShieldCheck,
  Trash2,
  UserPlus,
} from "lucide-react";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";

import {
  Avatar,
  Badge,
  Button,
  Card,
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
import { useMembers, useTrip, useTripInvitations } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { errorMessage, formatDate } from "@/lib/utils";

export default function MembersPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const members = useMembers(tripId);
  const canManage = trip.data?.my_role === "owner" || trip.data?.my_role === "admin";
  const invitations = useTripInvitations(tripId, canManage);
  const queryClient = useQueryClient();
  const { push } = useToasts();

  const [inviteOpen, setInviteOpen] = useState(false);
  const [email, setEmail] = useState("");
  const [role, setRole] = useState("member");
  const [scope, setScope] = useState("full");
  const [expires, setExpires] = useState("7");
  const [invitePath, setInvitePath] = useState("");

  const self = members.data?.items.find((member) => member.is_self);
  const [budgetLimit, setBudgetLimit] = useState("");
  const [needs, setNeeds] = useState("");

  useEffect(() => {
    if (!self) return;
    setBudgetLimit(self.budget_limit !== null && self.budget_limit !== undefined ? String(self.budget_limit) : "");
    setNeeds((self.accessibility_needs ?? []).join(", "));
  }, [self?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const refresh = () => {
    queryClient.invalidateQueries({ queryKey: ["members", tripId] });
    queryClient.invalidateQueries({ queryKey: ["invitations", tripId] });
    queryClient.invalidateQueries({ queryKey: ["trip", tripId] });
  };

  const createInvite = useMutation({
    mutationFn: () =>
      api<{ token: string; path: string; role: string; scope: string }>(
        `/api/trips/${tripId}/invitations`,
        {
          method: "POST",
          body: {
            email: email || null,
            role,
            scope,
            expires_in_days: Number(expires) || 7,
          },
        },
      ),
    onSuccess: (result) => {
      const url = `${window.location.origin}${result.path}`;
      setInvitePath(url);
      push("Invitation ready", "Share the link. Invitations expire automatically.", "success");
      refresh();
    },
    onError: (error) => push("Could not invite", errorMessage(error), "error"),
  });

  const revokeInvite = useMutation({
    mutationFn: (invitationId: string) =>
      api(`/api/trips/${tripId}/invitations/${invitationId}`, { method: "DELETE" }),
    onSuccess: () => {
      push("Invitation revoked", "The link no longer works.", "info");
      refresh();
    },
    onError: (error) => push("Could not revoke", errorMessage(error), "error"),
  });

  const updateRole = useMutation({
    mutationFn: ({ memberId, nextRole }: { memberId: string; nextRole: string }) =>
      api(`/api/trips/${tripId}/members/${memberId}`, { method: "PATCH", body: { role: nextRole } }),
    onSuccess: () => {
      push("Role updated", "Role changes are audited.", "success");
      refresh();
    },
    onError: (error) => push("Could not update role", errorMessage(error), "error"),
  });

  const removeMember = useMutation({
    mutationFn: (memberId: string) =>
      api(`/api/trips/${tripId}/members/${memberId}`, { method: "DELETE" }),
    onSuccess: () => {
      push("Member removed", "They no longer see this trip.", "info");
      refresh();
    },
    onError: (error) => push("Could not remove member", errorMessage(error), "error"),
  });

  const saveSelf = useMutation({
    mutationFn: () =>
      api(`/api/trips/${tripId}/members/me`, {
        method: "PATCH",
        body: {
          budget_limit: budgetLimit === "" ? null : Number(budgetLimit),
          accessibility_needs: needs
            .split(",")
            .map((entry) => entry.trim())
            .filter(Boolean),
        },
      }),
    onSuccess: () => {
      push("Preferences saved", "Only you can see your budget and access needs.", "success");
      refresh();
    },
    onError: (error) => push("Could not save", errorMessage(error), "error"),
  });

  const copy = async (value: string) => {
    try {
      await navigator.clipboard.writeText(value);
      push("Copied", "Invitation link copied to clipboard.", "success");
    } catch {
      push("Copy failed", "Select the link manually.", "error");
    }
  };

  if (members.isLoading || trip.isLoading) return <PageSkeleton />;
  if (members.error || !members.data) {
    return <ErrorState error={members.error || new Error("Members unavailable")} retry={() => members.refetch()} />;
  }

  const people = members.data.items;
  const isOwner = trip.data?.my_role === "owner";

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Group</p>
          <h2 className="mt-1 text-2xl">{people.length} traveller(s)</h2>
          <p className="mt-1 max-w-prose text-sm text-muted">
            Roles decide who approves plan changes. Private budgets and access needs stay with each member.
          </p>
        </div>
        {canManage ? (
          <Button onClick={() => setInviteOpen(true)}>
            <UserPlus size={14} /> Invite traveller
          </Button>
        ) : null}
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        {people.map((member) => (
          <Card key={member.id} className="space-y-3">
            <div className="flex items-start justify-between gap-2">
              <div className="flex items-center gap-3">
                <Avatar name={member.display_name} size={40} />
                <div>
                  <p className="text-[14px] font-medium text-ink">
                    {member.display_name}
                    {member.is_self ? <span className="ml-1 text-[12px] text-faint">(you)</span> : null}
                  </p>
                  <p className="text-[12px] text-faint">
                    {member.user?.email || "Member"} · joined {formatDate(member.joined_at)}
                  </p>
                </div>
              </div>
              <Badge
                tone={member.role === "owner" ? "ember" : member.role === "admin" ? "jade" : "outline"}
              >
                {member.role}
              </Badge>
            </div>

            {member.is_self ? (
              <div className="space-y-2 rounded-xl border border-line bg-raised/40 p-3">
                <p className="inline-flex items-center gap-1 text-[12px] text-faint">
                  <Lock size={11} /> Private to you
                </p>
                <div className="grid gap-2 sm:grid-cols-2">
                  <Field label="Budget limit" hint={trip.data?.currency}>
                    <Input
                      type="number"
                      min="0"
                      value={budgetLimit}
                      onChange={(event) => setBudgetLimit(event.target.value)}
                      placeholder="No limit"
                    />
                  </Field>
                  <Field label="Access needs" hint="Comma separated">
                    <Input
                      value={needs}
                      onChange={(event) => setNeeds(event.target.value)}
                      placeholder="step-free, low sensory"
                    />
                  </Field>
                </div>
                <Button size="sm" variant="secondary" onClick={() => saveSelf.mutate()} loading={saveSelf.isPending}>
                  Save my preferences
                </Button>
              </div>
            ) : null}

            {canManage && !member.is_self && member.role !== "owner" ? (
              <div className="flex flex-wrap items-center gap-2 border-t border-line pt-2.5">
                <Select
                  value={member.role}
                  onChange={(event) => updateRole.mutate({ memberId: member.id, nextRole: event.target.value })}
                  aria-label={`Role for ${member.display_name}`}
                  className="h-8 w-32 text-[12px]"
                >
                  <option value="member">Member</option>
                  <option value="admin">Admin</option>
                  {isOwner ? <option value="owner">Owner</option> : null}
                </Select>
                <Button
                  size="sm"
                  variant="ghost"
                  className="text-rose"
                  onClick={() => removeMember.mutate(member.id)}
                >
                  <Trash2 size={13} /> Remove
                </Button>
              </div>
            ) : null}
          </Card>
        ))}
      </div>

      {canManage ? (
        <Card className="space-y-4">
          <SectionTitle
            title="Invitations"
            hint="Links are single-use and expire"
            action={<Badge tone="outline">{invitations.data?.items.length ?? 0}</Badge>}
          />
          {invitations.data?.items.length ? (
            <div className="space-y-2">
              {invitations.data.items.map((invitation) => {
                const link = invitation.path
                  ? `${typeof window !== "undefined" ? window.location.origin : ""}${invitation.path}`
                  : null;
                return (
                  <div
                    key={invitation.id}
                    className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-line bg-surface px-3 py-2"
                  >
                    <div className="min-w-0">
                      <p className="truncate text-[12.5px] text-ink">{invitation.email || "Shareable link"}</p>
                      <p className="text-[10.5px] text-faint">
                        {invitation.role} · {invitation.scope} · expires {formatDate(invitation.expires_at)}
                        {invitation.accepted_at ? " · accepted" : ""}
                        {invitation.expired ? " · expired" : ""}
                      </p>
                    </div>
                    <div className="flex items-center gap-1.5">
                      {link && !invitation.accepted_at ? (
                        <Button size="sm" variant="secondary" onClick={() => copy(link)}>
                          <Copy size={12} /> Copy
                        </Button>
                      ) : null}
                      <Button size="sm" variant="ghost" className="text-rose" onClick={() => revokeInvite.mutate(invitation.id)}>
                        <Trash2 size={12} />
                      </Button>
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <p className="text-sm text-muted">No active invitations.</p>
          )}
        </Card>
      ) : null}

      <FlowNote icon={<ShieldCheck size={14} />}>
        Budget limits and accessibility needs are returned only to their owner. Group members never see each
        other&apos;s private limits or needs.
      </FlowNote>

      <Modal open={inviteOpen} onClose={() => setInviteOpen(false)} title="Invite a traveller">
        <form
          className="space-y-3"
          onSubmit={(event) => {
            event.preventDefault();
            createInvite.mutate();
          }}
        >
          <Field label="Email" hint="Optional — leave blank for a shareable link">
            <Input type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="friend@example.com" />
          </Field>
          <div className="grid gap-3 sm:grid-cols-3">
            <Field label="Role">
              <Select value={role} onChange={(event) => setRole(event.target.value)}>
                <option value="member">Member</option>
                <option value="admin">Admin</option>
              </Select>
            </Field>
            <Field label="Scope">
              <Select value={scope} onChange={(event) => setScope(event.target.value)}>
                <option value="full">Full</option>
                <option value="vote">Vote</option>
                <option value="pulse">Pulse</option>
                <option value="view">View</option>
              </Select>
            </Field>
            <Field label="Expires">
              <Select value={expires} onChange={(event) => setExpires(event.target.value)}>
                <option value="1">1 day</option>
                <option value="7">7 days</option>
                <option value="14">14 days</option>
                <option value="30">30 days</option>
              </Select>
            </Field>
          </div>

          {invitePath ? (
            <div className="space-y-1.5 rounded-xl border border-jade/20 bg-jade-soft/40 p-3">
              <p className="text-[12px] font-medium text-jade">Invitation link</p>
              <div className="flex items-center gap-2">
                <Input value={invitePath} readOnly className="h-9 text-[12px]" />
                <Button type="button" size="sm" variant="secondary" onClick={() => copy(invitePath)}>
                  <Copy size={12} />
                </Button>
              </div>
            </div>
          ) : null}

          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={() => setInviteOpen(false)}>
              Close
            </Button>
            <Button type="submit" loading={createInvite.isPending}>
              <Mail size={14} /> Create invitation
            </Button>
          </div>
          <p className="text-[12px] leading-5 text-faint">
            <Link2 size={10} className="mr-1 inline" /> Invitees join as members. Only owners and admins can invite.
          </p>
        </form>
      </Modal>
    </div>
  );
}
