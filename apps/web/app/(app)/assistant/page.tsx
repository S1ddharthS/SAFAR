"use client";

import { useMutation } from "@tanstack/react-query";
import { ArrowUpRight, BookOpen, Quote, ShieldQuestion, Sparkles } from "lucide-react";
import Link from "next/link";
import { useRef, useState } from "react";

import { Badge, Button, Card, FlowNote, PageHeader, Textarea } from "@/components/ui";
import { api } from "@/lib/api";
import { useAssistantCapabilities, useTrips } from "@/lib/hooks";
import type { AssistantAnswer } from "@/lib/types";
import { errorMessage } from "@/lib/utils";

interface Turn {
  id: number;
  question: string;
  answer?: AssistantAnswer & { generated_by?: string };
  error?: string;
}

const STARTERS = [
  "What is confirmed for the first day?",
  "Who still owes money on this trip?",
  "Which proposals are waiting for a decision?",
  "Why did the engine recommend the top activity?",
];

export default function AssistantPage() {
  const capabilities = useAssistantCapabilities();
  const trips = useTrips();
  const [tripId, setTripId] = useState<string>("");
  const [message, setMessage] = useState("");
  const [turns, setTurns] = useState<Turn[]>([]);
  const counter = useRef(0);

  const ask = useMutation({
    mutationFn: (question: string) =>
      api<AssistantAnswer & { generated_by?: string }>("/api/assistant/chat", {
        method: "POST",
        body: { message: question, trip_id: tripId || null },
      }),
    onSuccess: (answer, question) => {
      setTurns((current) =>
        current.map((turn) =>
          turn.question === question && !turn.answer && !turn.error
            ? { ...turn, answer }
            : turn,
        ),
      );
    },
    onError: (error, question) => {
      setTurns((current) =>
        current.map((turn) =>
          turn.question === question && !turn.answer && !turn.error
            ? { ...turn, error: errorMessage(error) }
            : turn,
        ),
      );
    },
  });

  function submit(question: string) {
    const trimmed = question.trim();
    if (!trimmed) return;
    counter.current += 1;
    setTurns((current) => [...current, { id: counter.current, question: trimmed }]);
    setMessage("");
    ask.mutate(trimmed);
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        eyebrow="Grounded travel assistant"
        title="Ask SAFAR"
        description="Answers come from what this deployment has recorded — your plan, members, money, proposals and catalog. Nothing is invented, and limitations are stated."
      />

      <Card className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <Badge tone="jade">
              <Sparkles size={11} /> {String(capabilities.data?.generator || "grounded retrieval")}
            </Badge>
            <Badge tone="outline">No external LLM</Badge>
          </div>
          <select
            value={tripId}
            onChange={(event) => setTripId(event.target.value)}
            className="h-9 rounded-full border border-line bg-surface px-3 text-xs text-ink"
            aria-label="Trip context"
          >
            <option value="">No trip context</option>
            {(trips.data || []).map((trip) => (
              <option key={trip.id} value={trip.id}>
                {trip.name}
              </option>
            ))}
          </select>
        </div>

        {turns.length === 0 ? (
          <div className="space-y-3 py-4">
            <p className="text-sm text-muted">Try a question grounded in your journey:</p>
            <div className="flex flex-wrap gap-2">
              {STARTERS.map((starter) => (
                <button
                  key={starter}
                  onClick={() => submit(starter)}
                  className="rounded-full border border-line bg-raised px-3 py-1.5 text-left text-[12px] text-muted transition-colors hover:border-ember/40 hover:text-ink"
                >
                  {starter}
                </button>
              ))}
            </div>
          </div>
        ) : (
          <div className="space-y-5">
            {turns.map((turn) => (
              <div key={turn.id} className="space-y-3">
                <div className="flex justify-end">
                  <p className="max-w-[85%] rounded-2xl rounded-br-sm bg-ink px-4 py-2.5 text-sm text-paper">
                    {turn.question}
                  </p>
                </div>
                {turn.error ? (
                  <div className="rounded-2xl border border-rose/20 bg-rose/5 px-4 py-3 text-sm text-rose">
                    {turn.error}
                  </div>
                ) : turn.answer ? (
                  <div className="rounded-2xl rounded-bl-sm border border-line bg-raised px-4 py-3.5">
                    <p className="whitespace-pre-line text-[14px] leading-6 text-ink">
                      {turn.answer.answer}
                    </p>
                    <div className="mt-3 flex flex-wrap items-center gap-2">
                      <Badge tone="jade">{turn.answer.intent}</Badge>
                      <Badge tone="outline">
                        grounding: {turn.answer.grounding}
                      </Badge>
                    </div>
                    {turn.answer.citations.length ? (
                      <div className="mt-3 space-y-1.5 border-t border-line pt-3">
                        <p className="flex items-center gap-1.5 text-[12px] uppercase tracking-editorial text-faint">
                          <BookOpen size={12} /> Sources
                        </p>
                        {turn.answer.citations.map((citation, index) => (
                          <p key={`${citation.label}-${index}`} className="text-[12.5px] text-muted">
                            <span className="font-mono text-[10px] text-faint">
                              {citation.type}
                            </span>{" "}
                            {citation.label}
                          </p>
                        ))}
                      </div>
                    ) : null}
                    {turn.answer.limitations.length ? (
                      <div className="mt-3 space-y-1 border-t border-line pt-3">
                        <p className="flex items-center gap-1.5 text-[12px] uppercase tracking-editorial text-faint">
                          <ShieldQuestion size={12} /> Limitations
                        </p>
                        {turn.answer.limitations.map((limitation) => (
                          <p key={limitation} className="text-[12.5px] text-muted">
                            {limitation}
                          </p>
                        ))}
                      </div>
                    ) : null}
                    {turn.answer.suggested_actions.length ? (
                      <div className="mt-3 flex flex-wrap gap-2 border-t border-line pt-3">
                        {turn.answer.suggested_actions.map((action) =>
                          action.href ? (
                            <Link
                              key={action.label}
                              href={action.href}
                              className="inline-flex items-center gap-1 rounded-full border border-line bg-surface px-3 py-1 text-[12px] text-ink hover:border-ember/40"
                            >
                              {action.label} <ArrowUpRight size={12} />
                            </Link>
                          ) : (
                            <Badge key={action.label} tone="neutral">
                              {action.label}
                            </Badge>
                          ),
                        )}
                      </div>
                    ) : null}
                  </div>
                ) : (
                  <div className="rounded-2xl border border-line bg-raised px-4 py-3">
                    <span className="inline-flex gap-1">
                      <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-faint" />
                      <span
                        className="h-1.5 w-1.5 animate-bounce rounded-full bg-faint"
                        style={{ animationDelay: "120ms" }}
                      />
                      <span
                        className="h-1.5 w-1.5 animate-bounce rounded-full bg-faint"
                        style={{ animationDelay: "240ms" }}
                      />
                    </span>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}

        <form
          onSubmit={(event) => {
            event.preventDefault();
            submit(message);
          }}
          className="space-y-2 border-t border-line pt-4"
        >
          <Textarea
            value={message}
            onChange={(event) => setMessage(event.target.value)}
            placeholder="Ask about the plan, money, members or why something was recommended…"
            aria-label="Message the assistant"
            className="min-h-20"
            onKeyDown={(event) => {
              if (event.key === "Enter" && !event.shiftKey) {
                event.preventDefault();
                submit(message);
              }
            }}
          />
          <div className="flex items-center justify-between gap-2">
            <p className="text-[12px] text-faint">
              The assistant states only recorded facts, never guesses or invented travel data.
            </p>
            <Button type="submit" size="sm" loading={ask.isPending}>
              <Quote size={13} /> Ask
            </Button>
          </div>
        </form>
      </Card>

      {capabilities.data ? (
        <FlowNote>
          {String(
            capabilities.data.disclosure ||
              "Only recorded SAFAR data is used. No external model, weather or translation provider is configured.",
          )}
        </FlowNote>
      ) : null}
    </div>
  );
}
