"use client";

import { motion } from "framer-motion";
import {
  Accessibility,
  ArrowRight,
  BadgeCheck,
  Brain,
  CalendarCheck,
  CircleDollarSign,
  Compass,
  Feather,
  Layers,
  MapPinned,
  Radio,
  ShieldCheck,
  Sparkles,
  Ticket,
  Users,
  Wallet,
  Waypoints,
} from "lucide-react";
import Link from "next/link";

import { PublicHeader } from "@/components/PublicHeader";
import { Badge, Card, LinkButton } from "@/components/ui";

const modes = [
  {
    label: "Everyone Wins",
    copy: "Rank by the average fit, then protect the member with the lowest fit. No one is left out of a good day.",
    icon: Users,
    tone: "jade" as const,
  },
  {
    label: "Your Turn",
    copy: "Give one member a day that reflects their tastes — while still honouring every hard constraint.",
    icon: Sparkles,
    tone: "ember" as const,
  },
  {
    label: "Surprise Us",
    copy: "Add novelty to the ranking without breaking budgets, access needs, radius or available time.",
    icon: Compass,
    tone: "neutral" as const,
  },
];

const clusters = [
  {
    title: "Group decisions that stay fair",
    icon: Users,
    items: [
      "Fairness engine with protected minimum fit",
      "Hard constraints enforced before ranking",
      "Proposals, votes, comments and versions",
      "Journey Pact and must-do protection",
    ],
  },
  {
    title: "A living plan, not a static list",
    icon: Waypoints,
    items: [
      "Trip Pulse adapts the day to energy and time",
      "Trip Twin compares alternatives read-only",
      "Trip Rescue repairs disruptions as proposals",
      "Fragility, domino and effort budgets",
    ],
  },
  {
    title: "Discover with provenance",
    icon: MapPinned,
    items: [
      "Catalog search with personal fit, labelled as estimate",
      "Place Pulse community reports with freshness",
      "Access Chain across every journey stage",
      "Respect filters and fragile-place notes",
    ],
  },
  {
    title: "Money without awkwardness",
    icon: CircleDollarSign,
    items: [
      "Expenses with equal, weighted or custom splits",
      "Settlement suggestions from real balances",
      "Cost-shock guard before approval",
      "Private budgets, aggregate fairness",
    ],
  },
  {
    title: "Memories worth keeping",
    icon: Feather,
    items: [
      "Private or trip-visible capture",
      "AI Memory Studio from recorded metadata",
      "Journey Replay and printable travel book",
      "Offline capture with idempotent sync",
    ],
  },
  {
    title: "A companion that stays grounded",
    icon: Brain,
    items: [
      "Deterministic grounded retrieval assistant",
      "Citations to SAFAR records only",
      "Explicit limitations, no invented facts",
      "One clear next action at a time",
    ],
  },
];

const honesty = [
  {
    title: "Provenance is visible",
    copy: "Every place fact is labelled VERIFIED, REPORTED, ESTIMATED or UNKNOWN, with freshness where available.",
    icon: BadgeCheck,
  },
  {
    title: "Estimates are not facts",
    copy: "Travel times, personal fit and crowd forecasts state their method and uncertainty. Community reports never become verified automatically.",
    icon: Radio,
  },
  {
    title: "The plan is protected",
    copy: "Nothing changes a confirmed itinerary silently. Engine suggestions, Twin adoption and Rescue repairs all become proposals.",
    icon: ShieldCheck,
  },
  {
    title: "Privacy is a constraint",
    copy: "Budgets and accessibility needs stay private. Meetups need mutual acceptance. Exports and deletion are yours to control.",
    icon: Accessibility,
  },
];

function SectionLabel({ children }: { children: React.ReactNode }) {
  return <p className="eyebrow">{children}</p>;
}

export default function LandingPage() {
  return (
    <div>
      <PublicHeader />

      <main>
        <section className="relative overflow-hidden border-b border-line">
          <div className="surface-grid absolute inset-0 opacity-50" aria-hidden />
          <div className="relative mx-auto grid max-w-wide gap-12 px-4 py-16 sm:px-6 lg:grid-cols-[1.08fr_0.92fr] lg:px-10 lg:py-24">
            <div>
              <motion.div
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5 }}
              >
                <Badge tone="ember" className="mb-5">
                  <Sparkles size={11} /> The Living Journey Network
                </Badge>
                <h1 className="max-w-3xl text-balance font-display text-[2.9rem] leading-[0.98] tracking-[-0.03em] sm:text-6xl lg:text-[4.4rem]">
                  Every Person.
                  <br />
                  Every Moment.
                  <br />
                  <span className="italic text-ember">One Intelligent Journey.</span>
                </h1>
                <p className="mt-6 max-w-xl text-[15.5px] leading-7 text-muted">
                  SAFAR is a collaborative travel platform where the group experience engine
                  recommends and the group decides. It plans around real constraints, protects
                  privacy, labels uncertainty and turns every journey into a story worth keeping.
                </p>
                <div className="mt-8 flex flex-wrap items-center gap-3">
                  <LinkButton href="/register" size="lg">
                    Start your journey <ArrowRight size={16} />
                  </LinkButton>
                  <LinkButton href="/login" variant="secondary" size="lg">
                    Enter a workspace
                  </LinkButton>
                </div>
                <p className="mt-4 text-[12px] text-faint">
                  Mobile-first · installable PWA · works with an offline capture queue
                </p>
              </motion.div>
            </div>

            <motion.div
              initial={{ opacity: 0, y: 24 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.6, delay: 0.15 }}
              className="relative"
            >
              <div className="card overflow-hidden p-0">
                <div className="border-b border-line bg-raised/70 px-5 py-4">
                  <div className="flex items-center justify-between">
                    <p className="text-[12px] uppercase tracking-editorial text-faint">
                      Group decision · Kyoto
                    </p>
                    <Badge tone="jade">Live</Badge>
                  </div>
                  <p className="mt-1 font-display text-xl">A day everyone can say yes to</p>
                </div>
                <div className="space-y-4 p-5">
                  {[
                    {
                      icon: Ticket,
                      label: "Proposal",
                      title: "Add Okochi Sanso Garden",
                      copy: "Suggested by the engine. 4 of 5 members responded. Owner approval still required.",
                    },
                    {
                      icon: ShieldCheck,
                      label: "Hard constraints",
                      title: "Step-free route verified",
                      copy: "Aiko's accessibility need is applied before ranking — never traded for a better average.",
                    },
                    {
                      icon: Wallet,
                      label: "Budget check",
                      title: "€18 each · within comfort",
                      copy: "Private budgets are checked without exposing them to the group.",
                    },
                  ].map((row) => {
                    const Icon = row.icon;
                    return (
                      <div key={row.title} className="flex gap-3.5">
                        <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-line bg-surface text-ember">
                          <Icon size={16} />
                        </span>
                        <div>
                          <p className="text-[10px] uppercase tracking-editorial text-faint">
                            {row.label}
                          </p>
                          <p className="text-[13.5px] font-medium">{row.title}</p>
                          <p className="mt-0.5 text-[12px] leading-5 text-muted">{row.copy}</p>
                        </div>
                      </div>
                    );
                  })}
                  <div className="rounded-2xl border border-ember/20 bg-ember-soft/70 px-3.5 py-2.5 text-[12px] text-ember">
                    The engine recommends. The group decides. Nothing is applied until approval.
                  </div>
                </div>
              </div>
              <div className="absolute -bottom-6 -left-4 hidden rounded-2xl border border-line bg-surface px-4 py-3 shadow-lift sm:block">
                <p className="text-[10px] uppercase tracking-editorial text-faint">Momentum</p>
                <p className="mt-0.5 text-[12.5px] text-muted">One next action, never a wall of alerts.</p>
              </div>
            </motion.div>
          </div>
        </section>

        <section id="principles" className="border-b border-line py-16 lg:py-20">
          <div className="mx-auto max-w-wide px-4 sm:px-6 lg:px-10">
            <div className="max-w-2xl">
              <SectionLabel>The core rule</SectionLabel>
              <h2 className="mt-2 text-balance text-3xl leading-tight sm:text-4xl">
                Three ways to spend a day. One guarantee: the plan respects everyone.
              </h2>
              <p className="mt-3 text-sm leading-6 text-muted">
                The Group Experience Engine ranks catalog activities after enforcing every
                member&apos;s hard constraints — budget ceiling, radius, available time, effort and
                step-free access. Fairness is a first-class outcome, not an afterthought.
              </p>
            </div>
            <div className="mt-8 grid gap-4 md:grid-cols-3">
              {modes.map((mode, index) => {
                const Icon = mode.icon;
                return (
                  <Card key={mode.label} className="relative">
                    <div className="flex items-center justify-between">
                      <span className="flex h-10 w-10 items-center justify-center rounded-full border border-line bg-raised text-ink">
                        <Icon size={18} />
                      </span>
                      <span className="font-mono text-[12px] text-faint">0{index + 1}</span>
                    </div>
                    <p className="mt-4 font-display text-xl">{mode.label}</p>
                    <p className="mt-2 text-[13px] leading-6 text-muted">{mode.copy}</p>
                    <div className="mt-4">
                      <Badge tone={mode.tone}>Mode</Badge>
                    </div>
                  </Card>
                );
              })}
            </div>
          </div>
        </section>

        <section id="capabilities" className="border-b border-line bg-surface/40 py-16 lg:py-20">
          <div className="mx-auto max-w-wide px-4 sm:px-6 lg:px-10">
            <div className="flex flex-wrap items-end justify-between gap-6">
              <div className="max-w-2xl">
                <SectionLabel>Built for the whole journey</SectionLabel>
                <h2 className="mt-2 text-balance text-3xl leading-tight sm:text-4xl">
                  Before, during and after — the network remembers what matters.
                </h2>
              </div>
              <div className="text-right">
                <p className="font-display text-4xl text-ember">49</p>
                <p className="text-[12px] uppercase tracking-editorial text-faint">
                  features in the registry
                </p>
              </div>
            </div>

            <div className="mt-9 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {clusters.map((cluster) => {
                const Icon = cluster.icon;
                return (
                  <Card key={cluster.title} className="h-full">
                    <span className="flex h-10 w-10 items-center justify-center rounded-2xl border border-line bg-raised text-ember">
                      <Icon size={18} />
                    </span>
                    <h3 className="mt-4 text-lg leading-snug">{cluster.title}</h3>
                    <ul className="mt-3 space-y-2">
                      {cluster.items.map((item) => (
                        <li key={item} className="flex gap-2 text-[12.5px] leading-5 text-muted">
                          <span className="mt-2 h-1 w-1 shrink-0 rounded-full bg-ember" />
                          {item}
                        </li>
                      ))}
                    </ul>
                  </Card>
                );
              })}
            </div>
          </div>
        </section>

        <section id="honesty" className="border-b border-line py-16 lg:py-20">
          <div className="mx-auto max-w-wide px-4 sm:px-6 lg:px-10">
            <div className="grid gap-10 lg:grid-cols-[0.8fr_1.2fr]">
              <div>
                <SectionLabel>A product you can interrogate</SectionLabel>
                <h2 className="mt-2 text-balance text-3xl leading-tight sm:text-4xl">
                  Trust is a feature, not a slogan.
                </h2>
                <p className="mt-3 text-sm leading-6 text-muted">
                  SAFAR never dresses an estimate up as a verified fact. Every recommendation,
                  report and forecast shows where it came from and what it does not know.
                </p>
                <div className="mt-6 flex flex-wrap gap-2">
                  <Badge tone="jade">VERIFIED</Badge>
                  <Badge tone="ember">REPORTED</Badge>
                  <Badge>ESTIMATED</Badge>
                  <Badge tone="outline">UNKNOWN</Badge>
                </div>
              </div>
              <div className="grid gap-4 sm:grid-cols-2">
                {honesty.map((item) => {
                  const Icon = item.icon;
                  return (
                    <div key={item.title} className="rounded-3xl border border-line bg-surface p-5">
                      <Icon size={18} className="text-ember" />
                      <p className="mt-3 text-[15px] font-medium">{item.title}</p>
                      <p className="mt-1.5 text-[12.5px] leading-5 text-muted">{item.copy}</p>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        </section>

        <section className="py-16 lg:py-20">
          <div className="mx-auto max-w-wide px-4 sm:px-6 lg:px-10">
            <div className="relative overflow-hidden rounded-4xl border border-line bg-ink px-6 py-12 text-paper sm:px-10 lg:px-14">
              <div
                className="absolute inset-0 opacity-[0.08]"
                style={{
                  backgroundImage:
                    "radial-gradient(circle at 20% 20%, #f0a34a 0, transparent 45%), radial-gradient(circle at 80% 80%, #5eead4 0, transparent 40%)",
                }}
                aria-hidden
              />
              <div className="relative flex flex-wrap items-end justify-between gap-8">
                <div className="max-w-xl">
                  <p className="text-[12px] uppercase tracking-editorial text-paper/60">
                    Your next journey
                  </p>
                  <h2 className="mt-2 text-balance text-3xl leading-tight sm:text-4xl">
                    Plan less. Experience more. Bring everyone with you.
                  </h2>
                  <p className="mt-3 text-sm leading-6 text-paper/70">
                    Create a trip, invite the group, share a Pulse and let the engine offer a day
                    that works for every person around the table.
                  </p>
                </div>
                <div className="flex flex-wrap gap-3">
                  <LinkButton
                    href="/register"
                    size="lg"
                    className="border-paper bg-paper text-ink hover:bg-paper/90"
                  >
                    Create an account <ArrowRight size={16} />
                  </LinkButton>
                  <LinkButton
                    href="/login"
                    size="lg"
                    variant="ghost"
                    className="border border-paper/25 text-paper hover:bg-paper/10"
                  >
                    Sign in
                  </LinkButton>
                </div>
              </div>
            </div>
          </div>
        </section>
      </main>

      <footer className="border-t border-line py-8">
        <div className="mx-auto flex max-w-wide flex-col gap-4 px-4 text-[12px] text-faint sm:flex-row sm:items-center sm:justify-between sm:px-6 lg:px-10">
          <p>SAFAR · The Living Journey Network · Every Person. Every Moment. One Intelligent Journey.</p>
          <div className="flex flex-wrap gap-4">
            <Link href="/login" className="hover:text-ink">
              Sign in
            </Link>
            <Link href="/register" className="hover:text-ink">
              Create account
            </Link>
            <Link href="/settings" className="hover:text-ink">
              Privacy
            </Link>
            <span>Grounded assistant · no external AI configured</span>
          </div>
        </div>
      </footer>
    </div>
  );
}
