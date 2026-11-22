import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "SAFAR — The Living Journey Network",
    short_name: "SAFAR",
    description:
      "Every Person. Every Moment. One Intelligent Journey. Collaborative trip planning where the engine recommends and the group decides.",
    start_url: "/dashboard",
    scope: "/",
    display: "standalone",
    orientation: "portrait",
    background_color: "#f6f1e7",
    theme_color: "#f6f1e7",
    icons: [
      {
        src: "/icon.svg",
        sizes: "any",
        type: "image/svg+xml",
        purpose: "any",
      },
      {
        src: "/icon-maskable.svg",
        sizes: "any",
        type: "image/svg+xml",
        purpose: "maskable",
      },
    ],
    shortcuts: [
      { name: "Dashboard", url: "/dashboard" },
      { name: "Discover", url: "/discover" },
      { name: "Assistant", url: "/assistant" },
    ],
  };
}
