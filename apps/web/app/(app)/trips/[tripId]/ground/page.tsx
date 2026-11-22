"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { HelpCircle, MessageCircle, Send, ShieldQuestion } from "lucide-react";
import { useParams } from "next/navigation";
import { useState } from "react";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  FlowNote,
  PageSkeleton,
  SectionTitle,
  Select,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useGroundRequests, useSearch, useTrip } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { errorMessage, formatDateTime } from "@/lib/utils";

export default function GroundPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const requests = useGroundRequests(tripId);
  const catalog = useSearch({ destination_id: trip.data?.destination_id || undefined, limit: 60 });
  const queryClient = useQueryClient();
  const { push } = useToasts();

  const [activityId, setActivityId] = useState("");
  const [question, setQuestion] = useState("");
  const [answerFor, setAnswerFor] = useState<string | null>(null);
  const [observation, setObservation] = useState("");
  const [confidence, setConfidence] = useState("0.6");

  const activityName = (id: string | null) =>
    id ? catalog.data?.items.find((entry) => entry.activity.id === id)?.activity.name || "Activity" : "Place";

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["ground", tripId] });

  const ask = useMutation({
    mutationFn: () =>
      api(`/api/trips/${tripId}/ground-requests`, {
        method: "POST",
        body: { activity_id: activityId, question },
      }),
    onSuccess: () => {
      push("Question sent", "Local contributors can answer with observations.", "success");
      setQuestion("");
      setActivityId("");
      refresh();
    },
    onError: (error) => push("Could not ask", errorMessage(error), "error"),
  });

  const respond = useMutation({
    mutationFn: (requestId: string) =>
      api(`/api/trips/${tripId}/ground-requests/${requestId}/responses`, {
        method: "POST",
        body: { observation, confidence: Number(confidence) || 0.5 },
      }),
    onSuccess: () => {
      push("Observation shared", "It stays unverified until moderated.", "success");
      setObservation("");
      setAnswerFor(null);
      refresh();
    },
    onError: (error) => push("Could not answer", errorMessage(error), "error"),
  });

  if (requests.isLoading) return <PageSkeleton />;
  if (requests.error || !requests.data) {
    return <ErrorState error={requests.error || new Error("Ground requests unavailable")} retry={() => requests.refetch()} />;
  }

  const items = requests.data.items;

  return (
    <div className="space-y-5">
      <div>
        <p className="eyebrow">Ask the ground</p>
        <h2 className="mt-1 text-2xl">Questions for people who are there</h2>
        <p className="mt-1 max-w-prose text-sm text-muted">
          Opt-in local contributors for this destination can answer with observations. Answers are unverified
          until moderated.
        </p>
      </div>

      <Card className="space-y-3">
        <SectionTitle title="Ask a question" hint="Be specific and answerable" />
        <form
          className="space-y-3"
          onSubmit={(event) => {
            event.preventDefault();
            if (!activityId || question.trim().length < 5) return;
            ask.mutate();
          }}
        >
          <Field label="About which activity?">
            <Select value={activityId} onChange={(event) => setActivityId(event.target.value)}>
              <option value="">Choose an activity…</option>
              {(catalog.data?.items ?? []).map((entry) => (
                <option key={entry.activity.id} value={entry.activity.id}>
                  {entry.activity.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Question">
            <Textarea
              value={question}
              onChange={(event) => setQuestion(event.target.value)}
              placeholder="Is the north entrance open on Sundays?"
            />
          </Field>
          <Button type="submit" loading={ask.isPending} disabled={!activityId || question.trim().length < 5}>
            <Send size={14} /> Send question
          </Button>
        </form>
      </Card>

      {items.length === 0 ? (
        <EmptyState
          title="No questions yet"
          description="Ask the ground when you need a current, local observation."
          icon={<HelpCircle size={24} />}
        />
      ) : (
        <div className="space-y-3">
          {items.map((request) => (
            <Card key={request.id} className="space-y-3">
              <div className="flex flex-wrap items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="text-[14px] font-medium text-ink">{request.question}</p>
                  <p className="text-[12px] text-faint">
                    {activityName(request.activity_id)} · {formatDateTime(request.created_at)}
                  </p>
                </div>
                <Badge tone={request.status === "answered" ? "jade" : "ember"}>{request.status}</Badge>
              </div>

              {request.responses.length ? (
                <div className="space-y-2">
                  {request.responses.map((response) => (
                    <div key={response.id} className="rounded-xl border border-line bg-surface px-3 py-2">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <Badge tone={response.verified ? "jade" : "ember"}>{response.provenance}</Badge>
                        <span className="text-[10.5px] text-faint">
                          {formatDateTime(response.observed_at)} · confidence {Math.round(response.confidence * 100)}%
                        </span>
                      </div>
                      <p className="mt-1 text-[12px] leading-5 text-muted">{response.observation}</p>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-[12px] text-faint">Waiting for a local contributor.</p>
              )}

              {answerFor === request.id ? (
                <form
                  className="space-y-2 rounded-xl border border-line bg-raised/40 p-3"
                  onSubmit={(event) => {
                    event.preventDefault();
                    if (observation.trim().length < 5) return;
                    respond.mutate(request.id);
                  }}
                >
                  <Field label="What did you observe?">
                    <Textarea value={observation} onChange={(event) => setObservation(event.target.value)} />
                  </Field>
                  <Field label="Confidence">
                    <Select value={confidence} onChange={(event) => setConfidence(event.target.value)}>
                      <option value="0.4">Low</option>
                      <option value="0.6">Medium</option>
                      <option value="0.8">High</option>
                    </Select>
                  </Field>
                  <div className="flex gap-2">
                    <Button type="submit" size="sm" loading={respond.isPending}>
                      Share observation
                    </Button>
                    <Button type="button" size="sm" variant="secondary" onClick={() => setAnswerFor(null)}>
                      Cancel
                    </Button>
                  </div>
                </form>
              ) : (
                <Button size="sm" variant="secondary" onClick={() => setAnswerFor(request.id)}>
                  <MessageCircle size={13} /> Answer as a local contributor
                </Button>
              )}
            </Card>
          ))}
        </div>
      )}

      <FlowNote icon={<ShieldQuestion size={14} />}>
        Only opted-in contributors for this destination can answer. A single observation never becomes verified
        information automatically, and exact live locations are never exposed.
      </FlowNote>
    </div>
  );
}
