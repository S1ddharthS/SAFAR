"use client";

import { useMutation } from "@tanstack/react-query";
import { ArrowUpRight, Bot, MessageSquare, ShieldCheck, Sparkles, User } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useRef, useState } from "react";

import {
  Badge,
  Button,
  Card,
  FlowNote,
  Input,
  PageSkeleton,
  SectionTitle,
  Select,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useAssistantCapabilities, useTrip } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { AssistantAnswer } from "@/lib/types";
import { cn, errorMessage } from "@/lib/utils";

interface Turn {
  role: "you" | "safar";
  text: string;
  answer?: AssistantAnswer;
}

const STARTERS = [
  "What is confirmed for day one?",
  "Who owes whom after the expenses?",
  "What open proposals need a decision?",
  "What did the engine recommend and why?",
  "Is the museum step-free?",
  "What is the plan if it rains?",
];

export default function TripAssistantPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const capabilities = useAssistantCapabilities();
  const { push } = useToasts();

  const [turns, setTurns] = useState<Turn[]>([]);
  const [message, setMessage] = useState("");
  const [language, setLanguage] = useState("auto");
  const endRef = useRef<HTMLDivElement>(null);

  const ask = useMutation({
    mutationFn: (text: string) =>
      api<AssistantAnswer>(`/api/trips/${tripId}/assistant`, {
        method: "POST",
        body: { message: text, language: language === "auto" ? undefined : language },
      }),
    onSuccess: (answer, text) => {
      setTurns((current) => [...current, { role: "you", text }, { role: "safar", text: answer.answer, answer }]);
      setMessage("");
      window.setTimeout(() => endRef.current?.scrollIntoView({ behavior: "smooth" }), 50);
    },
    onError: (error) => push("Assistant error", errorMessage(error), "error"),
  });

  const send = (text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;
    ask.mutate(trimmed);
  };

  if (trip.isLoading) return <PageSkeleton />;

  const caps = capabilities.data as
    | {
        generator?: string;
        disclosure?: string;
        external_llm?: boolean;
        translation?: boolean;
        translation_mode?: string;
        languages?: string[];
        language_names?: Record<string, string>;
        weather?: boolean;
        answer_sources?: string[];
      }
    | undefined;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Ask SAFAR</p>
          <h2 className="mt-1 text-2xl">Grounded answers about {trip.data?.name || "this trip"}</h2>
          <p className="mt-1 max-w-prose text-sm text-muted">
            Answers come only from what SAFAR has recorded for this trip, assembled with local language
            templates. No external AI model. Weather is labelled as predicted when a provider is configured.
          </p>
        </div>
        <div className="flex flex-wrap gap-1.5">
          <Badge tone="outline">{caps?.generator || "grounded retrieval"}</Badge>
          {caps?.external_llm === false ? <Badge tone="jade">No external LLM</Badge> : null}
          {caps?.translation ? <Badge tone="neutral">{caps.languages?.length || 8} languages</Badge> : null}
          {caps?.weather === false ? <Badge tone="outline">No weather</Badge> : null}
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-[1fr_18rem]">
        <Card className="flex min-h-[26rem] flex-col gap-3">
          <SectionTitle title="Conversation" action={<MessageSquare size={16} className="text-faint" />} />
          <div className="flex-1 space-y-3 overflow-y-auto pr-1">
            {turns.length === 0 ? (
              <div className="flex h-full flex-col items-center justify-center gap-2 py-10 text-center">
                <Sparkles size={26} className="text-ember" />
                <p className="text-sm text-muted">Ask about the plan, budget, members, proposals or recommendations.</p>
                <div className="mt-2 flex flex-wrap justify-center gap-1.5">
                  {STARTERS.slice(0, 4).map((starter) => (
                    <button
                      key={starter}
                      type="button"
                      onClick={() => send(starter)}
                      className="rounded-full border border-line bg-surface px-2.5 py-1 text-[12px] text-muted hover:border-ink/30 hover:text-ink"
                    >
                      {starter}
                    </button>
                  ))}
                </div>
              </div>
            ) : (
              turns.map((turn, index) => (
                <div
                  key={index}
                  className={cn(
                    "flex gap-2",
                    turn.role === "you" ? "flex-row-reverse" : "flex-row",
                  )}
                >
                  <span
                    className={cn(
                      "mt-0.5 inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full border",
                      turn.role === "you" ? "border-ink bg-ink text-paper" : "border-ember/30 bg-ember-soft text-ember",
                    )}
                  >
                    {turn.role === "you" ? <User size={13} /> : <Bot size={13} />}
                  </span>
                  <div
                    className={cn(
                      "max-w-[85%] rounded-2xl border px-3.5 py-2.5 text-[12.5px] leading-6",
                      turn.role === "you"
                        ? "border-ink/10 bg-ink text-paper"
                        : "border-line bg-surface text-ink",
                    )}
                  >
                    <p className="whitespace-pre-line">{turn.text}</p>
                    {turn.answer?.language ? (
                      <div className="mt-1.5 flex flex-wrap items-center gap-1">
                        <Badge tone="outline">{turn.answer.language.name}</Badge>
                        {turn.answer.requires_approval ? <Badge tone="ember">Proposal only</Badge> : null}
                        {turn.answer.mutation === "none" ? (
                          <span className="text-[10px] text-faint">No itinerary change made</span>
                        ) : null}
                      </div>
                    ) : null}
                    {turn.answer?.suggested_actions?.length ? (
                      <div className="mt-2 flex flex-wrap gap-1.5">
                        {turn.answer.suggested_actions.map((action) => {
                          const href = action.href?.replace(/\/evidence\//, "/places/");
                          return href ? (
                            <Link
                              key={action.label}
                              href={href}
                              className="inline-flex items-center gap-1 rounded-full border border-line bg-paper px-2 py-0.5 text-[10.5px] text-ember hover:bg-ember-soft"
                            >
                              {action.label} <ArrowUpRight size={10} />
                            </Link>
                          ) : (
                            <Badge key={action.label} tone="outline">
                              {action.label}
                            </Badge>
                          );
                        })}
                      </div>
                    ) : null}
                    {turn.answer?.citations?.length ? (
                      <div className="mt-2 flex flex-wrap gap-1 border-t border-line pt-1.5">
                        {turn.answer.citations.slice(0, 4).map((citation, citationIndex) => (
                          <span key={`${citation.label}-${citationIndex}`} className="text-[10px] text-faint">
                            {citation.label}
                          </span>
                        ))}
                      </div>
                    ) : null}
                    {turn.answer?.limitations?.length ? (
                      <p className="mt-1.5 text-[10.5px] text-ember">{turn.answer.limitations.join(" · ")}</p>
                    ) : null}
                  </div>
                </div>
              ))
            )}
            <div ref={endRef} />
          </div>

          <div className="flex flex-wrap items-center gap-2 border-t border-line pt-3">
            <label className="text-[11px] text-faint" htmlFor="assistant-language">
              Reply language
            </label>
            <Select
              id="assistant-language"
              value={language}
              onChange={(event) => setLanguage(event.target.value)}
              className="h-8 w-auto min-w-[9.5rem] px-2.5 py-1 text-[12px]"
              aria-label="Reply language"
            >
              <option value="auto">Auto-detect</option>
              {(caps?.languages ?? []).map((code) => (
                <option key={code} value={code}>
                  {caps?.language_names?.[code] || code.toUpperCase()}
                </option>
              ))}
            </Select>
            <span className="text-[10.5px] text-faint">Local templates, no vendor translation.</span>
          </div>

          <form
            className="flex items-center gap-2"
            onSubmit={(event) => {
              event.preventDefault();
              send(message);
            }}
          >
            <Input
              value={message}
              onChange={(event) => setMessage(event.target.value)}
              placeholder="Ask about this trip…"
              className="flex-1"
            />
            <Button type="submit" loading={ask.isPending} disabled={!message.trim()}>
              Ask
            </Button>
          </form>
        </Card>

        <div className="space-y-3">
          <Card className="space-y-2">
            <SectionTitle title="Suggested questions" />
            <div className="space-y-1.5">
              {STARTERS.map((starter) => (
                <button
                  key={starter}
                  type="button"
                  onClick={() => send(starter)}
                  className="block w-full rounded-xl border border-line bg-surface px-2.5 py-1.5 text-left text-[12px] text-muted hover:border-ink/30 hover:text-ink"
                >
                  {starter}
                </button>
              ))}
            </div>
          </Card>

          <Card className="space-y-2">
            <SectionTitle title="What it can cite" />
            <ul className="space-y-1">
              {(caps?.answer_sources ?? []).map((source) => (
                <li key={source} className="text-[12px] leading-5 text-muted">
                  · {source}
                </li>
              ))}
            </ul>
            <FlowNote icon={<ShieldCheck size={14} />}>
              {caps?.disclosure || "Answers state only what SAFAR has recorded and label limitations."}
            </FlowNote>
          </Card>
        </div>
      </div>
    </div>
  );
}
