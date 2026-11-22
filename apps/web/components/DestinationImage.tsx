import Image from "next/image";

import { destinationAlt, destinationImage } from "@/lib/imagery";
import { cn } from "@/lib/utils";

export function DestinationImage({
  name,
  country,
  heroImage,
  sizes,
  priority,
  className,
  overlay,
}: {
  name?: string | null;
  country?: string | null;
  heroImage?: string | null;
  sizes: string;
  priority?: boolean;
  className?: string;
  overlay?: "bottom" | "none";
}) {
  return (
    <>
      <Image
        src={destinationImage(name, country, heroImage)}
        alt={destinationAlt(name, country)}
        fill
        sizes={sizes}
        priority={priority}
        className={cn("object-cover", className)}
      />
      {overlay === "bottom" ? (
        <span
          aria-hidden
          className="absolute inset-0 bg-gradient-to-t from-ink/75 via-ink/15 to-transparent"
        />
      ) : null}
    </>
  );
}
