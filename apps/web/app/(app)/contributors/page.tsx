"use client";

import { BadgeCheck, MapPin, MessageSquare, Sparkles } from "lucide-react";
import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";

import {
  Avatar,
  Badge,
  Button,
  Card,
  EmptyState,
  Field,
  Input,
  PageHeader,
  PageSkeleton,
  Select,
  Textarea,
  Toggle,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useContributors, useDestinations } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { errorMessage } from "@/lib/utils";

export default function ContributorsPage() {
  const contributors = useContributors();
  const destinations = useDestinations();
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);
  const [open, setOpen] = useState(false);
  const [destinationId, setDestinationId] = useState("");
  const [bio, setBio] = useState("");
  const [expertise, setExpertise] = useState("");
  const [accepts, setAccepts] = useState(true);
  const [saving, setSaving] = useState(false);

  if (contributors.isLoading) return <PageSkeleton />;
  const items = contributors.data?.items ?? [];

  const become = async () => {
    if (!destinationId) {
      push("Choose a destination", "Contributors answer for one destination.", "error");
      return;
    }
    setSaving(true);
    try {
      await api("/api/contributors", {
        method: "POST",
        body: {
          destination_id: destinationId,
          bio: bio || null,
          expertise: expertise
            .split(",")
            .map((item) => item.trim())
            .filter(Boolean),
          accepts_requests: accepts,
        },
      });
      await queryClient.invalidateQueries({ queryKey: ["contributors"] });
      setOpen(false);
      push("Contributor profile saved", "Verification is granted by moderators, not self-declared.", "success");
    } catch (error) {
      push("Could not save", errorMessage(error), "error");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-7">
      <PageHeader
        eyebrow="Local contributors"
        title="People who know the ground"
        description="Opt-in travellers who answer specific questions about a destination. They are not official tourism authorities, and their observations stay REPORTED until moderated."
        actions={
          <Button variant={open ? "secondary" : "primary"} onClick={() => setOpen((value) => !value)}>
            {open ? "Close" : "Become a contributor"}
          </Button>
        }
      />

      {open ? (
        <Card className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Destination">
              <Select value={destinationId} onChange={(event) => setDestinationId(event.target.value)}>
                <option value="">Choose a destination</option>
                {(destinations.data ?? []).map((destination) => (
                  <option key={destination.id} value={destination.id}>
                    {destination.name}, {destination.country}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Expertise" hint="Comma-separated, e.g. markets, step-free routes">
              <Input value={expertise} onChange={(event) => setExpertise(event.target.value)} />
            </Field>
          </div>
          <Field label="Short bio">
            <Textarea value={bio} onChange={(event) => setBio(event.target.value)} />
          </Field>
          <Toggle
            checked={accepts}
            onChange={setAccepts}
            label="Accept ground requests"
            description="Trip members can ask you specific, place-based questions."
          />
          <div className="flex justify-end">
            <Button onClick={become} loading={saving}>
              Save contributor profile
            </Button>
          </div>
        </Card>
      ) : null}

      {items.length === 0 ? (
        <EmptyState
          icon={<MapPin size={26} />}
          title="No contributors yet"
          description="Contributors are opt-in. Ask a local traveller to share what they know, then verify it together."
        />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {items.map((contributor) => (
            <Card key={contributor.id} className="flex h-full flex-col">
              <div className="flex items-start gap-3">
                <Avatar name={contributor.user?.display_name} size={44} />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-1.5">
                    <p className="truncate text-[15px] font-medium">
                      {contributor.user?.display_name}
                    </p>
                    {contributor.verified ? <BadgeCheck size={15} className="text-jade" /> : null}
                  </div>
                  <p className="text-[12px] text-faint">
                    {contributor.destination?.name}, {contributor.destination?.country}
                  </p>
                </div>
              </div>
              <p className="mt-3 line-clamp-4 text-[12.5px] leading-5 text-muted">
                {contributor.bio || "No bio yet."}
              </p>
              <div className="mt-3 flex flex-wrap gap-1.5">
                {contributor.expertise.slice(0, 4).map((item) => (
                  <Badge key={item}>{item}</Badge>
                ))}
              </div>
              <div className="mt-auto flex flex-wrap items-center gap-2 border-t border-line pt-3">
                <Badge tone={contributor.verified ? "jade" : "outline"}>
                  {contributor.verified ? "Verified contributor" : "Unverified"}
                </Badge>
                <Badge tone={contributor.accepts_requests ? "ember" : "outline"}>
                  <MessageSquare size={10} />
                  {contributor.accepts_requests ? "Open to questions" : "Not accepting"}
                </Badge>
              </div>
            </Card>
          ))}
        </div>
      )}

      <div className="flex items-start gap-3 rounded-2xl border border-line bg-raised/50 p-4 text-[12px] leading-5 text-muted">
        <Sparkles size={16} className="mt-0.5 shrink-0 text-ember" />
        <p>{contributors.data?.disclosure}</p>
      </div>
    </div>
  );
}
