"use client";

import { Lock, Sparkles, UserPlus, Users } from "lucide-react";
import Link from "next/link";
import { useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import {
  Avatar,
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  Input,
  Modal,
  PageHeader,
  PageSkeleton,
  SectionTitle,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useConnectionRequests, useSerendipity } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { TravellerMatch } from "@/lib/types";
import { errorMessage, formatDateTime, titleCase } from "@/lib/utils";

export default function ConnectionsPage() {
  const serendipity = useSerendipity();
  const requests = useConnectionRequests();
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);
  const [selected, setSelected] = useState<TravellerMatch | null>(null);
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  const [deciding, setDeciding] = useState<string | null>(null);

  const refresh = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["serendipity"] }),
      queryClient.invalidateQueries({ queryKey: ["connection-requests"] }),
      queryClient.invalidateQueries({ queryKey: ["notifications"] }),
    ]);
  };

  const sendRequest = async () => {
    if (!selected) return;
    setSending(true);
    try {
      await api("/api/serendipity/requests", {
        method: "POST",
        body: { to_user_id: selected.user.id, message: message || null },
      });
      setSelected(null);
      setMessage("");
      await refresh();
      push("Request sent", "Contact only opens after the other traveller accepts.", "success");
    } catch (error) {
      push("Could not send request", errorMessage(error), "error");
    } finally {
      setSending(false);
    }
  };

  const decide = async (id: string, accept: boolean) => {
    setDeciding(id);
    try {
      await api(`/api/serendipity/requests/${id}/decide`, {
        method: "POST",
        body: { accept },
      });
      await refresh();
      push(
        accept ? "Connection accepted" : "Request declined",
        accept ? "Meet in public places and share only what you choose." : undefined,
        "success",
      );
    } catch (error) {
      push("Could not decide", errorMessage(error), "error");
    } finally {
      setDeciding(null);
    }
  };

  if (serendipity.isLoading || requests.isLoading) return <PageSkeleton />;
  if (serendipity.error) {
    return <ErrorState error={serendipity.error} retry={() => serendipity.refetch()} />;
  }

  const matches = serendipity.data?.matches ?? [];
  const items = requests.data?.items ?? [];
  const incoming = items.filter((item) => item.direction === "incoming" && item.status === "pending");

  return (
    <div className="space-y-7">
      <PageHeader
        eyebrow="Serendipity"
        title="Compatible travellers"
        description="Opt-in, reciprocal and privacy-first. No exact location or contact detail is ever exposed. Meeting requires mutual acceptance."
        actions={
          <Link href="/settings" className="text-[12px] text-ember hover:underline">
            Discovery settings
          </Link>
        }
      />

      {!serendipity.data?.eligible ? (
        <Card>
          <div className="flex items-start gap-3">
            <span className="flex h-10 w-10 items-center justify-center rounded-full border border-line bg-raised text-ember">
              <Lock size={17} />
            </span>
            <div>
              <p className="text-[14px] font-medium">Discovery is currently off</p>
              <p className="mt-1 max-w-lg text-[12.5px] leading-6 text-muted">
                {serendipity.data?.reason}
              </p>
              <Link href="/profile" className="mt-2 inline-block text-[12px] font-medium text-ember hover:underline">
                Enable discovery in your profile
              </Link>
            </div>
          </div>
        </Card>
      ) : null}

      {incoming.length > 0 ? (
        <section>
          <SectionTitle title="Waiting for your answer" hint="Only you can accept or decline" />
          <div className="space-y-2">
            {incoming.map((request) => (
              <Card key={request.id} className="flex flex-wrap items-center gap-3">
                <Avatar name={request.from_user?.display_name} size={40} />
                <div className="min-w-0 flex-1">
                  <p className="text-[14px] font-medium">{request.from_user?.display_name}</p>
                  <p className="text-[12px] text-faint">{formatDateTime(request.created_at)}</p>
                  {request.message ? (
                    <p className="mt-1 text-[12px] leading-5 text-muted">“{request.message}”</p>
                  ) : null}
                </div>
                <div className="flex gap-2">
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => decide(request.id, false)}
                    loading={deciding === request.id}
                  >
                    Decline
                  </Button>
                  <Button size="sm" onClick={() => decide(request.id, true)} loading={deciding === request.id}>
                    Accept
                  </Button>
                </div>
              </Card>
            ))}
          </div>
        </section>
      ) : null}

      <section>
        <SectionTitle
          title="Suggested travellers"
          hint={serendipity.data?.disclosure || "Matches are heuristic and never expose private data."}
          action={<Badge tone="outline">{matches.length} matches</Badge>}
        />
        {matches.length === 0 ? (
          <EmptyState
            icon={<Users size={26} />}
            title="No compatible travellers yet"
            description="Matches appear when there is a destination, interest or date overlap with another opted-in traveller."
          />
        ) : (
          <div className="grid gap-4 sm:grid-cols-2">
            {matches.map((match) => (
              <Card key={match.user.id} className="flex flex-col">
                <div className="flex items-start gap-3">
                  <Avatar name={match.user.display_name} size={44} />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-start justify-between gap-2">
                      <p className="text-[15px] font-medium">{match.user.display_name}</p>
                      <Badge tone="ember">{Math.round(match.score)}</Badge>
                    </div>
                    <p className="text-[12px] text-faint">
                      {match.user.headline || match.user.home_city || "Traveller"}
                    </p>
                  </div>
                </div>
                <ul className="mt-3 space-y-1">
                  {match.reasons.map((reason) => (
                    <li key={reason} className="flex gap-2 text-[12px] leading-5 text-muted">
                      <span className="mt-2 h-1 w-1 shrink-0 rounded-full bg-ember" />
                      {reason}
                    </li>
                  ))}
                </ul>
                <div className="mt-3 flex flex-wrap gap-1.5">
                  {match.shared_interests.slice(0, 4).map((interest) => (
                    <Badge key={interest}>{interest}</Badge>
                  ))}
                </div>
                <p className="mt-3 flex items-start gap-1.5 text-[10.5px] leading-4 text-faint">
                  <Lock size={11} className="mt-0.5 shrink-0" /> {match.privacy}
                </p>
                <Button size="sm" className="mt-4" onClick={() => setSelected(match)}>
                  <UserPlus size={14} /> Request contact
                </Button>
              </Card>
            ))}
          </div>
        )}
      </section>

      <section>
        <SectionTitle title="Your requests" hint={requests.data?.disclosure} />
        {items.length === 0 ? (
          <p className="rounded-2xl border border-dashed border-line px-4 py-6 text-center text-[12.5px] text-faint">
            No connection requests yet.
          </p>
        ) : (
          <div className="space-y-2">
            {items.map((request) => (
              <Card key={request.id} className="flex flex-wrap items-center gap-3">
                <Avatar
                  name={
                    request.direction === "incoming"
                      ? request.from_user?.display_name
                      : request.to_user?.display_name
                  }
                  size={36}
                />
                <div className="min-w-0 flex-1">
                  <p className="text-[13.5px] font-medium">
                    {request.direction === "incoming" ? "From " : "To "}
                    {request.direction === "incoming"
                      ? request.from_user?.display_name
                      : request.to_user?.display_name}
                  </p>
                  <p className="text-[12px] text-faint">
                    {formatDateTime(request.created_at)} · {titleCase(request.direction)}
                  </p>
                </div>
                <Badge
                  tone={
                    request.status === "accepted"
                      ? "jade"
                      : request.status === "pending"
                        ? "ember"
                        : "outline"
                  }
                >
                  {titleCase(request.status)}
                </Badge>
              </Card>
            ))}
          </div>
        )}
      </section>

      <div className="flex items-start gap-3 rounded-2xl border border-line bg-raised/50 p-4 text-[12px] leading-5 text-muted">
        <Sparkles size={16} className="mt-0.5 shrink-0 text-ember" />
        <p>
          Matching is based on shared destinations, interests, travel dates and Journey DNA
          similarity. It is an estimate, not a claim that you will get along. You can block anyone,
          and blocks remove them from discovery.
        </p>
      </div>

      <Modal open={Boolean(selected)} onClose={() => setSelected(null)} title="Request contact">
        {selected ? (
          <div className="space-y-4">
            <div className="flex items-center gap-3 rounded-2xl border border-line bg-raised/40 p-3">
              <Avatar name={selected.user.display_name} size={40} />
              <div>
                <p className="text-[14px] font-medium">{selected.user.display_name}</p>
                <p className="text-[12px] text-faint">{selected.user.headline || "Traveller"}</p>
              </div>
            </div>
            <Field label="Optional message" hint="Do not include phone numbers or live location.">
              <Textarea
                value={message}
                onChange={(event) => setMessage(event.target.value)}
                maxLength={500}
                placeholder="We overlap in Kyoto — would you like to compare notes on gardens?"
              />
            </Field>
            <p className="rounded-xl border border-line bg-raised/50 px-3 py-2 text-[12px] leading-5 text-muted">
              Contact details are only exchanged after mutual acceptance. Meet in public places.
            </p>
            <div className="flex justify-end gap-2">
              <Button variant="secondary" onClick={() => setSelected(null)}>
                Cancel
              </Button>
              <Button onClick={sendRequest} loading={sending}>
                <UserPlus size={15} /> Send request
              </Button>
            </div>
          </div>
        ) : null}
      </Modal>
    </div>
  );
}
