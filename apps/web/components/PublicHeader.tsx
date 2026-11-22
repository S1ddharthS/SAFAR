"use client";

import { Compass } from "lucide-react";
import Link from "next/link";

import { ThemeToggle } from "@/components/AppShell";
import { LinkButton } from "@/components/ui";

export function PublicHeader() {
  return (
    <header className="sticky top-0 z-30 border-b border-line/80 bg-paper/85 backdrop-blur">
      <div className="mx-auto flex max-w-wide items-center justify-between gap-4 px-4 py-3 sm:px-6 lg:px-10">
        <Link href="/" className="flex items-center gap-2.5">
          <span className="flex h-9 w-9 items-center justify-center rounded-full border border-ember/40 bg-ember-soft text-ember">
            <Compass size={19} strokeWidth={1.8} />
          </span>
          <span className="leading-tight">
            <span className="block font-display text-[18px] tracking-[0.2em]">SAFAR</span>
            <span className="block text-[9px] uppercase tracking-editorial text-faint">
              Living Journey Network
            </span>
          </span>
        </Link>
        <nav className="hidden items-center gap-6 text-[13px] text-muted md:flex">
          <a href="#principles" className="hover:text-ink">
            Principles
          </a>
          <a href="#capabilities" className="hover:text-ink">
            Capabilities
          </a>
          <a href="#honesty" className="hover:text-ink">
            Honesty
          </a>
        </nav>
        <div className="flex items-center gap-2">
          <ThemeToggle />
          <LinkButton href="/login" variant="ghost" size="sm">
            Sign in
          </LinkButton>
          <LinkButton href="/register" size="sm">
            Start a journey
          </LinkButton>
        </div>
      </div>
    </header>
  );
}
