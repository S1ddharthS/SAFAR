const DESTINATION_IMAGES = [
  "/images/destinations/kyoto.jpg",
  "/images/destinations/lisbon.jpg",
  "/images/destinations/reykjavik.jpg",
  "/images/destinations/coast.jpg",
];

const MATCHERS: { test: RegExp; src: string }[] = [
  { test: /kyoto|japan|kansai/i, src: "/images/destinations/kyoto.jpg" },
  { test: /lisbon|lisboa|portugal/i, src: "/images/destinations/lisbon.jpg" },
  { test: /reykjav|iceland/i, src: "/images/destinations/reykjavik.jpg" },
  { test: /coast|shore|sea|island/i, src: "/images/destinations/coast.jpg" },
];

function hash(value: string) {
  let total = 0;
  for (let index = 0; index < value.length; index += 1) {
    total = (total * 31 + value.charCodeAt(index)) >>> 0;
  }
  return total;
}

export const HERO_IMAGE = "/images/hero-journey.jpg";

export function destinationImage(
  name?: string | null,
  country?: string | null,
  heroImage?: string | null,
) {
  if (heroImage) return heroImage;
  const haystack = `${name ?? ""} ${country ?? ""}`;
  const match = MATCHERS.find((entry) => entry.test.test(haystack));
  if (match) return match.src;
  return DESTINATION_IMAGES[hash(haystack || "safar") % DESTINATION_IMAGES.length];
}

export function destinationAlt(name?: string | null, country?: string | null) {
  if (!name) return "Destination";
  return country ? `${name}, ${country}` : name;
}
