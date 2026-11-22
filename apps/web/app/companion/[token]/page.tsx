"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import { Check, Clock, Link2, Lock, MapPin, Send, ShieldCheck } from "lucide-react";
import { useParams } from "next/navigation";
import { useState } from "react";

import {
  Badge,
  Button,
  Card,
  ErrorState,
  PageSkeleton,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { errorMessage, formatDay, titleCase } from "@/lib/utils";

interface CompanionContext {
  purpose: "vote" | "checkin";
  question: string;
  options: string[];
  trip: { name: string; destination_name: string };
  target: {
    kind: string;
    id: string;
    title: string;
    summary?: string | null;
    status: string;
    day?: string | null;
    start_time?: string | null;
    registered_votes?: Record<string, number>;
  };
  expires_at: string;
  remaining_uses: number;
  anonymous_responses: number;
  disclosure: string;
}

const OPTION_LABEL: Record<string, string> = {
  yes: "Yes, I support it",
  no: "No",
  abstain: "Abstain",
  in: "I'll be there",
  out: "I can't make it",
  join_later: "I'll join later",
};

export default function CompanionAnswerPage() {
  const params = useParams<{ token: string }>();
  const token = typeof params?.token === "string" ? params.token : "";
  const [choice, setChoice] = useState("");
  const [comment, setComment] = useState("");
  const [done, setDone] = useState("");

  const context = useQuery({
    queryKey: ["companion-context", token],
    queryFn: () =>
      api<CompanionContext>(`/api/companion/${encodeURIComponent(token)}`),
    enabled: Boolean(token),
    retry: false,
  });

  const submit = useMutation({
    mutationFn: () =>
      api<{ message: string }>(
        `/api/companion/${encodeURIComponent(token)}/respond`,
        { method: "POST", body: { value: choice, comment: comment || null } },
      ),
    onSuccess: (data) => setDone(data.message),
  });

  return (
    <main id="main-content" className="mx-auto flex min-h-dvh w-full max-w-xl flex-col justify-center px-4 py-10">
      <div className="mb-6 flex items-center gap-2">
        <span className="inline-flex h-8 w-8 items-center justify-center rounded-full bg-ink text-[13px] font-medium text-paper">
          S
        </span>
        <span className="text-sm font-medium tracking-wide">SAFAR</span>
        <Badge tone="outline" className="ml-auto">
          <Lock size={11} /> No account needed
        </Badge>
      </div>

      {context.isLoading ? (
        <PageSkeleton />
      ) : context.error ? (
        <Card className="space-y-3 text-center">
          <span className="mx-auto inline-flex h-11 w-11 items-center justify-center rounded-full bg-raised text-ember">
            <Link2 size={20} />
          </span>
          <h1 className="text-xl">This link cannot be used</h1>
          <p className="text-sm text-muted">
            {errorMessage(context.error)} Links are single-use and expire, so ask the trip organiser
            for a fresh one.
          </p>
          <ErrorState error={context.error} retry={() => context.refetch()} />
        </Card>
      ) : context.data && done ? (
        <Card className="space-y-3 text-center">
          <span className="mx-auto inline-flex h-11 w-11 items-center justify-center rounded-full bg-jade-soft text-jade">
            <Check size={22} />
          </span>
          <h1 className="text-xl">Answer recorded</h1>
          <p className="text-sm text-muted">{done}</p>
          <p className="text-[12px] text-faint">
            You can close this page. Nothing about you was stored with the answer.
          </p>
        </Card>
      ) : context.data ? (
        <div className="space-y-4">
          <Card className="space-y-3">
            <div className="flex flex-wrap items-center gap-2">
              <Badge tone={context.data.purpose === "vote" ? "ember" : "jade"}>
                {context.data.purpose === "vote" ? "One decision" : "One check-in"}
              </Badge>
              <span className="text-[12px] text-faint">{context.data.trip.name}</span>
            </div>
            {context.data.trip.destination_name ? (
              <p className="flex items-center gap-1.5 text-[12px] text-muted">
                <MapPin size={12} /> {context.data.trip.destination_name}
              </p>
            ) : null}
            <h1 className="text-2xl leading-tight">{context.data.target.title}</h1>
            {context.data.target.summary ? (
              <p className="text-sm leading-6 text-muted">{context.data.target.summary}</p>
            ) : null}
            {context.data.target.day ? (
              <p className="flex flex-wrap items-center gap-2 text-[12px] text-faint">
                <Clock size={12} />
                {formatDay(context.data.target.day)}
                {context.data.target.start_time ? ` · ${context.data.target.start_time}` : ""}
              </p>
            ) : null}
            {context.data.target.registered_votes ? (
              <div className="flex flex-wrap gap-1.5">
                {Object.entries(context.data.target.registered_votes).map(([value, count]) => (
                  <Badge key={value} tone="outline">
                    {titleCase(value)} · {count}
                  </Badge>
                ))}
              </div>
            ) : null}
          </Card>

          <Card className="space-y-3">
            <p className="text-sm font-medium text-ink">{context.data.question}</p>
            <div className="grid gap-2">
              {context.data.options.map((option) => (
                <button
                  key={option}
                  type="button"
                  onClick={() => setChoice(option)}
                  aria-pressed={choice === option}
                  className={
                    choice === option
                      ? "rounded-2xl border border-ink bg-ink px-4 py-3 text-left text-sm text-paper"
                      : "rounded-2xl border border-line bg-surface px-4 py-3 text-left text-sm text-ink hover:border-ink/30"
                  }
                >
                  {OPTION_LABEL[option] || titleCase(option)}
                </button>
              ))}
            </div>
            <Textarea
              rows={3}
              maxLength={500}
              placeholder="Optional note (visible anonymously to the organiser)"
              value={comment}
              onChange={(event) => setComment(event.target.value)}
            />
            <Button
              className="w-full"
              disabled={!choice || submit.isPending}
              onClick={() => submit.mutate()}
            >
              <Send size={15} /> {submit.isPending ? "Sending…" : "Send my answer"}
            </Button>
            {submit.error ? (
              <p className="text-sm text-rose">{errorMessage(submit.error)}</p>
            ) : null}
            <p className="text-[12px] leading-5 text-faint">
              This link can be answered once. Your name, email, IP address and device are not
              recorded.
            </p>
          </Card>

          <p className="flex items-start gap-2 px-1 text-[12px] leading-5 text-faint">
            <ShieldCheck size={14} className="mt-0.5 shrink-0 text-jade" />
            {context.data.disclosure}
          </p>
        </div>
      ) : null}
    </main>
  );
}
