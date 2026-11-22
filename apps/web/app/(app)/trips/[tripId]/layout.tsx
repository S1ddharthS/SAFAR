import { TripShell } from "@/components/TripShell";

export default function TripLayout({ children }: { children: React.ReactNode }) {
  return <TripShell>{children}</TripShell>;
}
