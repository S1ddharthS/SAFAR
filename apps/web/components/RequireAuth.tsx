"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";

import { PageSkeleton } from "@/components/ui";
import { useAuth } from "@/lib/store";

export function RequireAuth({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const user = useAuth((state) => state.user);
  const hydrated = useAuth((state) => state.hydrated);
  const [waited, setWaited] = useState(false);

  useEffect(() => {
    const timer = window.setTimeout(() => setWaited(true), 700);
    return () => window.clearTimeout(timer);
  }, []);

  useEffect(() => {
    if (!hydrated && !waited) return;
    if (!user) {
      const next = encodeURIComponent(pathname || "/dashboard");
      router.replace(`/login?next=${next}`);
    }
  }, [hydrated, waited, user, pathname, router]);

  if (!user) {
    return (
      <div className="mx-auto max-w-wide px-4 py-12">
        <PageSkeleton />
      </div>
    );
  }

  return <>{children}</>;
}
