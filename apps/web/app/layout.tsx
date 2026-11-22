import type { Metadata, Viewport } from "next";
import "leaflet/dist/leaflet.css";

import "./globals.css";
import { Providers } from "./providers";

export const metadata: Metadata = {
  title: {
    default: "SAFAR — The Living Journey Network",
    template: "%s · SAFAR",
  },
  description:
    "Every Person. Every Moment. One Intelligent Journey. Collaborative trip planning where the engine recommends and the group decides.",
  applicationName: "SAFAR",
  manifest: "/manifest.webmanifest",
  icons: {
    icon: "/icon.svg",
    apple: "/icon.svg",
  },
  formatDetection: { telephone: false },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f6f1e7" },
    { media: "(prefers-color-scheme: dark)", color: "#12110e" },
  ],
};

const themeScript = `(function(){try{var raw=localStorage.getItem("safar-theme");if(!raw)return;var parsed=JSON.parse(raw);var theme=parsed&&parsed.state&&parsed.state.theme;if(theme==="dark"){document.documentElement.classList.add("dark")}}catch(e){}})();`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body className="min-h-dvh antialiased">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
