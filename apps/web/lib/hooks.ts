"use client";

import { useQuery } from "@tanstack/react-query";

import { api } from "./api";
import type {
  AdminStats,
  AssistantAnswer,
  Branch,
  Circle,
  CircleDetail,
  CompanionLink,
  Contributor,
  DNA,
  Destination,
  DestinationDetail,
  EngineBatch,
  Expense,
  ExpensesResponse,
  GroundRequest,
  Itinerary,
  Me,
  MemoriesResponse,
  Member,
  Mission,
  NearbyItem,
  NotificationItem,
  OpportunityClock,
  Pact,
  PlaceDetail,
  Proposal,
  PulseResponse,
  ReplayResponse,
  SearchItem,
  Shadowplan,
  Studio,
  Task,
  TaskSummary,
  ThreadResponse,
  Trip,
} from "./types";

export function useMe(enabled = true) {
  return useQuery({
    queryKey: ["me"],
    queryFn: () => api<Me>("/api/users/me"),
    enabled,
    staleTime: 60_000,
  });
}

export function useTrips() {
  return useQuery({
    queryKey: ["trips"],
    queryFn: async () => {
      const data = await api<{ items: Trip[] } | Trip[]>("/api/trips");
      return Array.isArray(data) ? data : data.items;
    },
  });
}

export function useTrip(tripId: string | undefined) {
  return useQuery({
    queryKey: ["trip", tripId],
    queryFn: () => api<Trip>(`/api/trips/${tripId}`),
    enabled: Boolean(tripId),
  });
}

export function useMembers(tripId: string | undefined) {
  return useQuery({
    queryKey: ["members", tripId],
    queryFn: () => api<{ items: Member[] }>(`/api/trips/${tripId}/members`),
    enabled: Boolean(tripId),
  });
}

export function useItinerary(tripId: string | undefined) {
  return useQuery({
    queryKey: ["itinerary", tripId],
    queryFn: () => api<Itinerary>(`/api/trips/${tripId}/itinerary`),
    enabled: Boolean(tripId),
  });
}

export function useProposals(tripId: string | undefined, status = "all") {
  return useQuery({
    queryKey: ["proposals", tripId, status],
    queryFn: () => api<{ items: Proposal[] }>(`/api/trips/${tripId}/proposals?status=${status}`),
    enabled: Boolean(tripId),
  });
}

export function usePulse(tripId: string | undefined) {
  return useQuery({
    queryKey: ["pulse", tripId],
    queryFn: () => api<PulseResponse>(`/api/trips/${tripId}/pulse`),
    enabled: Boolean(tripId),
  });
}

export function useEngine(tripId: string | undefined, mode?: string) {
  return useQuery({
    queryKey: ["engine", tripId, mode || "latest"],
    queryFn: () =>
      api<EngineBatch>(
        `/api/trips/${tripId}/engine/latest${mode ? `?mode=${mode}` : ""}`,
      ),
    enabled: Boolean(tripId),
  });
}

export function useExpenses(tripId: string | undefined) {
  return useQuery({
    queryKey: ["expenses", tripId],
    queryFn: () => api<{ items: Expense[]; totals: Record<string, number | string> }>(`/api/trips/${tripId}/expenses`),
    enabled: Boolean(tripId),
  });
}

export function useBalances(tripId: string | undefined) {
  return useQuery({
    queryKey: ["balances", tripId],
    queryFn: () => api<ExpensesResponse>(`/api/trips/${tripId}/expenses/balances`),
    enabled: Boolean(tripId),
  });
}

export function useMemories(tripId: string | undefined) {
  return useQuery({
    queryKey: ["memories", tripId],
    queryFn: () => api<MemoriesResponse>(`/api/trips/${tripId}/memories`),
    enabled: Boolean(tripId),
  });
}

export function useStudio(tripId: string | undefined) {
  return useQuery({
    queryKey: ["studio", tripId],
    queryFn: () => api<Studio>(`/api/trips/${tripId}/memory-studio`),
    enabled: Boolean(tripId),
  });
}

export function useReplay(tripId: string | undefined) {
  return useQuery({
    queryKey: ["replay", tripId],
    queryFn: () => api<ReplayResponse>(`/api/trips/${tripId}/replay`),
    enabled: Boolean(tripId),
  });
}

export function usePact(tripId: string | undefined) {
  return useQuery({
    queryKey: ["pact", tripId],
    queryFn: () => api<{ pact: Pact | null }>(`/api/trips/${tripId}/pact`),
    enabled: Boolean(tripId),
  });
}

export function useTasks(tripId: string | undefined) {
  return useQuery({
    queryKey: ["tasks", tripId],
    queryFn: () => api<{ items: Task[] }>(`/api/trips/${tripId}/tasks`),
    enabled: Boolean(tripId),
  });
}

export function useTaskSummary(tripId: string | undefined) {
  return useQuery({
    queryKey: ["tasks", tripId, "summary"],
    queryFn: () => api<TaskSummary>(`/api/trips/${tripId}/tasks/summary`),
    enabled: Boolean(tripId),
  });
}

export function useBranches(tripId: string | undefined) {
  return useQuery({
    queryKey: ["branches", tripId],
    queryFn: () => api<{ items: Branch[] }>(`/api/trips/${tripId}/branches`),
    enabled: Boolean(tripId),
  });
}

export function useShadowplans(tripId: string | undefined) {
  return useQuery({
    queryKey: ["shadowplans", tripId],
    queryFn: () => api<{ items: Shadowplan[] }>(`/api/trips/${tripId}/shadowplans`),
    enabled: Boolean(tripId),
  });
}

export function useMissions(tripId: string | undefined) {
  return useQuery({
    queryKey: ["missions", tripId],
    queryFn: () => api<{ items: Mission[]; note: string }>(`/api/trips/${tripId}/missions`),
    enabled: Boolean(tripId),
  });
}

export function useDestinations() {
  return useQuery({
    queryKey: ["destinations"],
    queryFn: async () => {
      const data = await api<{ items: Destination[] } | Destination[]>("/api/destinations");
      return Array.isArray(data) ? data : data.items;
    },
  });
}

export function useDestination(destinationId: string | undefined) {
  return useQuery({
    queryKey: ["destination", destinationId],
    queryFn: () => api<DestinationDetail>(`/api/destinations/${destinationId}`),
    enabled: Boolean(destinationId),
  });
}

export function useSearch(params: Record<string, string | number | boolean | undefined>) {
  const query = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== "" && value !== false) query.set(key, String(value));
  });
  const qs = query.toString();
  return useQuery({
    queryKey: ["search", qs],
    queryFn: () => api<{ lens: string; items: SearchItem[]; personalised: boolean; disclosure: string }>(`/api/activities/search?${qs}`),
    enabled: Boolean(params.destination_id),
  });
}

export function useCircles() {
  return useQuery({
    queryKey: ["circles"],
    queryFn: () => api<{ items: Circle[]; disclosure: string }>("/api/circles"),
  });
}

export function useCircle(circleId: string | undefined) {
  return useQuery({
    queryKey: ["circle", circleId],
    queryFn: () => api<CircleDetail>(`/api/circles/${circleId}`),
    enabled: Boolean(circleId),
  });
}

export function useContributors() {
  return useQuery({
    queryKey: ["contributors"],
    queryFn: () => api<{ items: Contributor[]; disclosure: string }>("/api/contributors"),
  });
}

export function useNotifications() {
  return useQuery({
    queryKey: ["notifications"],
    queryFn: () => api<{ unread: number; items: NotificationItem[] }>("/api/users/me/notifications"),
    refetchInterval: 60_000,
  });
}

export function useThread() {
  return useQuery({
    queryKey: ["thread"],
    queryFn: () => api<ThreadResponse>("/api/users/me/thread"),
  });
}

export function useDNA() {
  return useQuery({
    queryKey: ["dna"],
    queryFn: () => api<DNA>("/api/users/me/dna"),
  });
}

export function useNearby(tripId: string | undefined, radius = 5) {
  return useQuery({
    queryKey: ["nearby", tripId, radius],
    queryFn: () =>
      api<{ base: { lat: number; lon: number; source: string }; radius_km: number; items: NearbyItem[]; disclosure: string }>(
        `/api/trips/${tripId}/nearby?radius_km=${radius}`,
      ),
    enabled: Boolean(tripId),
  });
}

export function usePlaceDetail(tripId: string | undefined, activityId: string | null) {
  return useQuery({
    queryKey: ["place", tripId, activityId],
    queryFn: () => api<PlaceDetail>(`/api/trips/${tripId}/places/${activityId}`),
    enabled: Boolean(tripId && activityId),
  });
}

export function useGroundRequests(tripId: string | undefined) {
  return useQuery({
    queryKey: ["ground", tripId],
    queryFn: () => api<{ items: GroundRequest[] }>(`/api/trips/${tripId}/ground-requests`),
    enabled: Boolean(tripId),
  });
}

export function useAdminStats(enabled: boolean) {
  return useQuery({
    queryKey: ["admin", "stats"],
    queryFn: () => api<AdminStats>("/api/admin/stats"),
    enabled,
  });
}

export function useAssistantCapabilities() {
  return useQuery({
    queryKey: ["assistant", "capabilities"],
    queryFn: () => api<Record<string, unknown>>("/api/assistant/capabilities"),
  });
}

export function useAssistantAnswer() {
  return useQuery<AssistantAnswer>({
    queryKey: ["assistant", "empty"],
    queryFn: () => Promise.reject(new Error("not configured")),
    enabled: false,
  });
}

export function useInspirations(tripId: string | undefined) {
  return useQuery({
    queryKey: ["inspirations", tripId],
    queryFn: () => api<{ items: import("./types").InspirationItem[] }>(`/api/trips/${tripId}/inspirations`),
    enabled: Boolean(tripId),
  });
}

export function useMaterialWatches(tripId: string | undefined) {
  return useQuery({
    queryKey: ["watches", tripId],
    queryFn: () =>
      api<{ items: import("./types").MaterialWatchItem[]; note: string }>(
        `/api/trips/${tripId}/material-watch`,
      ),
    enabled: Boolean(tripId),
  });
}

export function useCapsules(tripId: string | undefined) {
  return useQuery({
    queryKey: ["capsules", tripId],
    queryFn: () => api<{ items: import("./types").CapsuleItem[] }>(`/api/trips/${tripId}/capsules`),
    enabled: Boolean(tripId),
  });
}

export function useTripActivity(tripId: string | undefined) {
  return useQuery({
    queryKey: ["activity", tripId],
    queryFn: () =>
      api<{ items: import("./types").TripActivityEvent[] }>(`/api/trips/${tripId}/activity`),
    enabled: Boolean(tripId),
  });
}

export function usePlaceReports(
  tripId: string | undefined,
  activityId: string | null | undefined,
  days = 90,
) {
  return useQuery({
    queryKey: ["place-reports", tripId, activityId, days],
    queryFn: () =>
      api<{ items: import("./types").PlaceReportItem[]; window_days: number; disclosure: string }>(
        `/api/trips/${tripId}/place-reports?activity_id=${activityId}&days=${days}`,
      ),
    enabled: Boolean(tripId && activityId),
  });
}

export function useInvitation(token: string | undefined) {
  return useQuery({
    queryKey: ["invitation", token],
    queryFn: () =>
      api<{
        trip: {
          id: string;
          name: string;
          destination_name: string;
          start_date: string;
          end_date: string;
          group_size: number;
          member_count: number;
        };
        role: string;
        scope: string;
        invited_by: string | null;
        expires_at: string;
        already_member: boolean;
        accepted: boolean;
        accepted_by_you: boolean;
        email_bound: boolean;
      }>(`/api/invitations/${token}`),
    enabled: Boolean(token),
    retry: false,
  });
}

export function useTripInvitations(tripId: string | undefined, enabled: boolean) {
  return useQuery({
    queryKey: ["invitations", tripId],
    queryFn: () =>
      api<{
        items: {
          id: string;
          email: string | null;
          role: string;
          scope: string;
          expires_at: string;
          accepted_at: string | null;
          created_at: string;
          expired?: boolean;
          path?: string;
        }[];
      }>(`/api/trips/${tripId}/invitations`),
    enabled: Boolean(tripId) && enabled,
  });
}

export function useAbuseReports(enabled: boolean, status = "open") {
  return useQuery({
    queryKey: ["abuse-reports", status],
    queryFn: () =>
      api<{
        items: {
          id: string;
          reporter: { id: string; display_name: string } | null;
          target_type: string;
          target_id: string | null;
          target_user_id: string | null;
          reason: string;
          status: string;
          created_at: string;
        }[];
      }>(`/api/admin/abuse-reports?status=${status}`),
    enabled,
  });
}

export function useEngineBatches(tripId: string | undefined) {
  return useQuery({
    queryKey: ["engine-batches", tripId],
    queryFn: () =>
      api<{
        items: {
          id: string;
          mode: string;
          mode_meta: { label: string; intent: string };
          for_date: string;
          created_at: string;
          summary: string | null;
        }[];
      }>(`/api/trips/${tripId}/engine/batches`),
    enabled: Boolean(tripId),
  });
}

export function useOfflineSnapshot(tripId: string | undefined) {
  return useQuery({
    queryKey: ["offline", tripId],
    queryFn: () =>
      api<{
        generated_at: string;
        stale_after: string;
        trip: {
          id: string;
          name: string;
          destination: string;
          start_date: string;
          end_date: string;
          currency: string;
          base: { lat: number; lon: number };
        };
        confirmed_version: number;
        items: {
          id: string;
          day: string;
          start_time: string;
          title: string;
          cost_estimate: number;
          is_protected: boolean;
          place: { name: string; address: string | null; lat: number; lon: number } | null;
        }[];
        members: { id: string; display_name: string; role: string }[];
        pact: { must_do: string[]; flexible: string[]; confirmed_times: Record<string, string> } | null;
        disclosure: string;
      }>(`/api/trips/${tripId}/offline`),
    enabled: Boolean(tripId),
  });
}

export function useSyncQueue(tripId: string | undefined) {
  return useQuery({
    queryKey: ["sync", tripId],
    queryFn: () =>
      api<{
        items: {
          client_id: string;
          operation: string;
          status: string;
          applied_at: string | null;
          created_at: string;
        }[];
      }>(`/api/trips/${tripId}/sync`),
    enabled: Boolean(tripId),
  });
}

export function useSerendipity() {
  return useQuery({
    queryKey: ["serendipity"],
    queryFn: () =>
      api<{
        eligible: boolean;
        reason?: string;
        matches: import("./types").TravellerMatch[];
        disclosure: string;
      }>("/api/serendipity/matches"),
  });
}

export function useConnectionRequests() {
  return useQuery({
    queryKey: ["connection-requests"],
    queryFn: () =>
      api<{ items: import("./types").ConnectionRequestItem[]; disclosure: string }>(
        "/api/serendipity/requests",
      ),
  });
}

export function useBlocks() {
  return useQuery({
    queryKey: ["blocks"],
    queryFn: () =>
      api<{ items: { user: { id: string; display_name: string }; created_at: string }[] }>(
        "/api/users/me/blocks",
      ),
  });
}

export function useOpportunityClock(tripId: string | undefined, on?: string) {
  return useQuery({
    queryKey: ["opportunity-clock", tripId, on || "auto"],
    queryFn: () =>
      api<OpportunityClock>(
        `/api/trips/${tripId}/opportunity-clock${on ? `?on=${encodeURIComponent(on)}` : ""}`,
      ),
    enabled: Boolean(tripId),
  });
}

export function useCompanionLinks(tripId: string | undefined) {
  return useQuery({
    queryKey: ["companion-links", tripId],
    queryFn: () =>
      api<{ items: CompanionLink[]; disclosure: string }>(
        `/api/trips/${tripId}/companion-links`,
      ),
    enabled: Boolean(tripId),
  });
}
