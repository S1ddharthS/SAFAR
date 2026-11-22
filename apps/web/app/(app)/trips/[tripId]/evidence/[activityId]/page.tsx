import { redirect } from "next/navigation";

export default async function EvidenceRedirect({
  params,
}: {
  params: Promise<{ tripId: string; activityId: string }>;
}) {
  const { tripId, activityId } = await params;
  redirect(`/trips/${tripId}/places/${activityId}`);
}
