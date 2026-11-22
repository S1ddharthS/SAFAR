"use client";

import { ArrowLeft, LogOut, Send, Users } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";

import {
  Avatar,
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  Input,
  PageSkeleton,
  SectionTitle,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useCircle } from "@/lib/hooks";
import { useAuth, useToasts } from "@/lib/store";
import { errorMessage, formatDateTime } from "@/lib/utils";

export default function CircleDetailPage() {
  const params = useParams<{ circleId: string }>();
  const circleId = typeof params?.circleId === "string" ? params.circleId : "";
  const circle = useCircle(circleId || undefined);
  const queryClient = useQueryClient();
  const user = useAuth((state) => state.user);
  const push = useToasts((state) => state.push);
  const [joining, setJoining] = useState(false);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [posting, setPosting] = useState(false);

  if (circle.isLoading) return <PageSkeleton />;
  if (circle.error || !circle.data) {
    return <ErrorState error={circle.error} retry={() => circle.refetch()} />;
  }
  const data = circle.data;

  const join = async () => {
    setJoining(true);
    try {
      await api(`/api/circles/${circleId}/join`, {
        method: data.joined ? "DELETE" : "POST",
      });
      await queryClient.invalidateQueries({ queryKey: ["circle", circleId] });
      await queryClient.invalidateQueries({ queryKey: ["circles"] });
      push(data.joined ? "Left circle" : "Joined circle", undefined, "success");
    } catch (error) {
      push("Could not update membership", errorMessage(error), "error");
    } finally {
      setJoining(false);
    }
  };

  const createPost = async () => {
    if (title.trim().length < 2 || body.trim().length < 2) return;
    setPosting(true);
    try {
      await api(`/api/circles/${circleId}/posts`, {
        method: "POST",
        body: { title, body },
      });
      setTitle("");
      setBody("");
      await queryClient.invalidateQueries({ queryKey: ["circle", circleId] });
      push("Post published", "Visible to circle members.", "success");
    } catch (error) {
      push("Could not publish", errorMessage(error), "error");
    } finally {
      setPosting(false);
    }
  };

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <Link href="/circles" className="inline-flex items-center gap-1.5 text-[12px] text-muted hover:text-ink">
        <ArrowLeft size={14} /> All circles
      </Link>

      <div className="rounded-4xl border border-line bg-surface p-6 sm:p-8">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="max-w-2xl">
            <p className="eyebrow">Travel circle</p>
            <h1 className="mt-2 text-4xl leading-tight">{data.name}</h1>
            <p className="mt-3 text-[13px] leading-6 text-muted">{data.description}</p>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              {data.interests.map((interest) => (
                <Badge key={interest}>{interest}</Badge>
              ))}
              <Badge tone="outline">
                <Users size={10} /> {data.member_count} members
              </Badge>
            </div>
          </div>
          <Button variant={data.joined ? "secondary" : "primary"} onClick={join} loading={joining}>
            {data.joined ? (
              <>
                <LogOut size={15} /> Leave
              </>
            ) : (
              <>Join circle</>
            )}
          </Button>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-[1.5fr_0.5fr]">
        <div className="space-y-4">
          <SectionTitle title="Circle posts" hint="Shared with this circle only" />
          {data.posts.length === 0 ? (
            <EmptyState title="No posts yet" description="Start a thoughtful thread for the circle." />
          ) : (
            data.posts.map((post) => (
              <Card key={post.id}>
                <div className="flex items-center gap-2.5">
                  <Avatar name={post.author?.display_name} size={30} />
                  <div>
                    <p className="text-[12.5px] font-medium">{post.author?.display_name || "Member"}</p>
                    <p className="text-[10.5px] text-faint">{formatDateTime(post.created_at)}</p>
                  </div>
                  {post.status !== "published" ? (
                    <Badge tone="rose" className="ml-auto">
                      {post.status}
                    </Badge>
                  ) : null}
                </div>
                <h3 className="mt-3 text-lg leading-snug">{post.title}</h3>
                <p className="mt-1.5 whitespace-pre-line text-[12.5px] leading-6 text-muted">
                  {post.body}
                </p>
              </Card>
            ))
          )}
        </div>

        <div className="space-y-4">
          <Card>
            <SectionTitle title="New post" hint="Be specific and generous" />
            <div className="space-y-3">
              <Field label="Title">
                <Input
                  maxLength={160}
                  value={title}
                  onChange={(event) => setTitle(event.target.value)}
                  placeholder="A quiet garden in eastern Kyoto"
                />
              </Field>
              <Field label="Post">
                <Textarea
                  value={body}
                  onChange={(event) => setBody(event.target.value)}
                  placeholder="What did you learn that another traveller could use?"
                />
              </Field>
              <Button
                onClick={createPost}
                loading={posting}
                disabled={title.trim().length < 2 || body.trim().length < 2}
                className="w-full"
              >
                <Send size={14} /> Publish
              </Button>
            </div>
          </Card>

          <Card>
            <SectionTitle title="Members" />
            <ul className="space-y-2">
              {data.members.map((member) => (
                <li key={member.user_id} className="flex items-center gap-2.5">
                  <Avatar name={member.display_name} size={28} />
                  <span className="min-w-0 flex-1 truncate text-[12.5px]">{member.display_name}</span>
                  {member.user_id === user?.id ? <Badge tone="ember">You</Badge> : null}
                  <Badge tone="outline">{member.role}</Badge>
                </li>
              ))}
            </ul>
          </Card>
        </div>
      </div>
    </div>
  );
}
