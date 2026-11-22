"use client";

import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import {
  Bell,
  Compass,
  Globe2,
  LayoutDashboard,
  LogOut,
  Menu,
  Moon,
  Orbit,
  Settings,
  ShieldCheck,
  Sparkles,
  Sun,
  UserRound,
  Users,
  X,
} from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";

import { Avatar, LinkButton } from "@/components/ui";
import { api } from "@/lib/api";
import { useMe, useNotifications } from "@/lib/hooks";
import { useAuth, useTheme } from "@/lib/store";
import { cn } from "@/lib/utils";

const PRIMARY_NAV = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/discover", label: "Discover", icon: Globe2 },
  { href: "/connections", label: "Connections", icon: Users },
  { href: "/circles", label: "Circles", icon: Orbit },
  { href: "/assistant", label: "Assistant", icon: Sparkles },
];

const SECONDARY_NAV = [
  { href: "/notifications", label: "Notifications", icon: Bell },
  { href: "/profile", label: "Journey DNA", icon: UserRound },
  { href: "/settings", label: "Settings", icon: Settings },
];

const NAV = [...PRIMARY_NAV, ...SECONDARY_NAV];

const MOBILE_NAV = [
  { href: "/dashboard", label: "Home", icon: LayoutDashboard },
  { href: "/discover", label: "Discover", icon: Globe2 },
  { href: "/assistant", label: "Ask", icon: Sparkles },
  { href: "/profile", label: "You", icon: UserRound },
];

export function Brand({ compact = false }: { compact?: boolean }) {
  return (
    <Link href="/dashboard" className="flex items-center gap-2.5" aria-label="SAFAR home">
      <span className="relative flex h-9 w-9 items-center justify-center rounded-full border border-ember/40 bg-ember-soft text-ember">
        <Compass size={19} strokeWidth={1.8} />
      </span>
      {compact ? null : (
        <span className="leading-tight">
          <span className="block font-display text-[19px] tracking-[0.18em]">SAFAR</span>
          <span className="block text-[10px] uppercase tracking-editorial text-muted">
            Living Journey Network
          </span>
        </span>
      )}
    </Link>
  );
}

export function ThemeToggle({ className }: { className?: string }) {
  const theme = useTheme((state) => state.theme);
  const toggle = useTheme((state) => state.toggle);
  return (
    <button
      type="button"
      onClick={toggle}
      className={cn(
        "inline-flex h-9 w-9 items-center justify-center rounded-full border border-line bg-surface text-muted transition-colors hover:text-ink",
        className,
      )}
      aria-label={theme === "dark" ? "Switch to light theme" : "Switch to dark theme"}
    >
      {theme === "dark" ? <Sun size={16} /> : <Moon size={16} />}
    </button>
  );
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const queryClient = useQueryClient();
  const user = useAuth((state) => state.user);
  const setUser = useAuth((state) => state.setUser);
  const logout = useAuth((state) => state.logout);
  const me = useMe(Boolean(user));
  const notifications = useNotifications();
  const [drawer, setDrawer] = useState(false);
  const [online, setOnline] = useState(true);
  const drawerRef = useRef<HTMLElement>(null);
  const restoreRef = useRef<HTMLElement | null>(null);
  const reduceMotion = useReducedMotion();

  const closeDrawer = () => setDrawer(false);

  useEffect(() => {
    if (me.data?.user) setUser(me.data.user);
  }, [me.data?.user, setUser]);

  useEffect(() => {
    setDrawer(false);
  }, [pathname]);

  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    update();
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);

  useEffect(() => {
    if (!drawer) return;
    restoreRef.current = document.activeElement as HTMLElement | null;
    const panel = drawerRef.current;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setDrawer(false);
        return;
      }
      if (event.key !== "Tab" || !panel) return;
      const nodes = Array.from(
        panel.querySelectorAll<HTMLElement>(
          'a[href],button:not([disabled]),input:not([disabled]),[tabindex]:not([tabindex="-1"])',
        ),
      ).filter((node) => node.offsetParent !== null);
      if (!nodes.length) return;
      const index = nodes.indexOf(document.activeElement as HTMLElement);
      if (event.shiftKey && index <= 0) {
        event.preventDefault();
        nodes[nodes.length - 1].focus();
      } else if (!event.shiftKey && (index === -1 || index === nodes.length - 1)) {
        event.preventDefault();
        nodes[0].focus();
      }
    };
    panel?.querySelector<HTMLElement>('a[href],button:not([disabled])')?.focus({ preventScroll: true });
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", onKeyDown);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", onKeyDown);
      if (restoreRef.current?.isConnected) restoreRef.current.focus();
    };
  }, [drawer]);

  const unread = notifications.data?.unread ?? 0;
  const meUser = me.data?.user || user;

  const signOut = () => {
    api("/api/auth/logout", { method: "POST" }).catch(() => undefined);
    logout();
    queryClient.clear();
    router.push("/");
  };

  const isActive = (href: string) =>
    pathname === href || (href !== "/dashboard" && pathname.startsWith(`${href}/`));

  const navLink = (item: (typeof NAV)[number], onNavigate?: () => void) => {
    const active = isActive(item.href);
    const Icon = item.icon;
    return (
      <Link
        key={item.href}
        href={item.href}
        onClick={onNavigate}
        aria-current={active ? "page" : undefined}
        className={cn(
          "group relative flex min-h-10 items-center gap-3 rounded-xl px-3 py-2 text-[13.5px] transition-colors",
          active ? "bg-ink text-paper" : "text-muted hover:bg-ink/5 hover:text-ink",
        )}
      >
        <Icon
          size={17}
          strokeWidth={active ? 2 : 1.7}
          className={active ? "text-ember" : "text-faint group-hover:text-ink"}
        />
        <span className="flex-1">{item.label}</span>
        {item.href === "/notifications" && unread > 0 ? (
          <span
            className={cn(
              "num rounded-full px-1.5 py-0.5 font-mono text-[11px]",
              active ? "bg-paper/20 text-paper" : "bg-ember-soft text-ember",
            )}
          >
            {unread}
          </span>
        ) : null}
        {active ? (
          <span aria-hidden className="absolute inset-y-2 -left-4 w-0.5 rounded-full bg-ember" />
        ) : null}
      </Link>
    );
  };

  const adminLink = (onNavigate?: () => void) => {
    if (!meUser?.is_admin) return null;
    return (
      <Link
        href="/admin"
        onClick={onNavigate}
        aria-current={pathname.startsWith("/admin") ? "page" : undefined}
        className={cn(
          "mt-1 flex min-h-10 items-center gap-3 rounded-xl px-3 py-2 text-[13.5px] transition-colors",
          pathname.startsWith("/admin")
            ? "bg-ink text-paper"
            : "text-muted hover:bg-ink/5 hover:text-ink",
        )}
      >
        <ShieldCheck size={17} className="text-faint" /> Admin
      </Link>
    );
  };

  return (
    <div className="min-h-dvh">
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:absolute focus:left-3 focus:top-3 focus:z-[100] focus:rounded-full focus:bg-ink focus:px-4 focus:py-2 focus:text-sm focus:text-paper"
      >
        Skip to content
      </a>

      <aside className="fixed inset-y-0 left-0 z-40 hidden w-64 flex-col border-r border-line bg-paper/95 px-4 py-6 backdrop-blur lg:flex">
        <div className="px-2">
          <Brand />
        </div>
        <div className="mt-7">
          <LinkButton href="/trips/new" size="md" className="w-full">
            <Compass size={15} /> New journey
          </LinkButton>
        </div>
        <nav aria-label="Main navigation" className="mt-7 flex flex-1 flex-col gap-0.5 overflow-y-auto">
          <p className="mb-1.5 px-3 text-[10.5px] font-medium uppercase tracking-editorial text-muted">
            Workspace
          </p>
          {PRIMARY_NAV.map((item) => navLink(item))}
          {adminLink()}
          <div className="my-3 h-px bg-line" />
          <p className="mb-1.5 px-3 text-[10.5px] font-medium uppercase tracking-editorial text-muted">
            You
          </p>
          {SECONDARY_NAV.map((item) => navLink(item))}
        </nav>
        <div className="mt-4 space-y-3 border-t border-line pt-4">
          <div className="flex items-center gap-2.5 rounded-2xl border border-line bg-surface px-3 py-2.5">
            <Avatar name={meUser?.display_name} size={34} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-[13px] font-medium">{meUser?.display_name}</p>
              <p className="truncate text-[11.5px] text-muted">{meUser?.email}</p>
            </div>
            <ThemeToggle />
          </div>
          <div className="flex items-center justify-between gap-2 px-1 text-[11.5px] text-muted">
            <span className="inline-flex items-center gap-1.5">
              <span className={cn("h-1.5 w-1.5 rounded-full", online ? "bg-jade" : "bg-rose")} />
              {online ? "Online" : "Offline — captures are queued"}
            </span>
            <button
              type="button"
              onClick={signOut}
              className="inline-flex min-h-8 items-center gap-1.5 rounded-full px-2 text-[11.5px] text-muted transition-colors hover:bg-ink/5 hover:text-ink"
            >
              <LogOut size={12} /> Sign out
            </button>
          </div>
        </div>
      </aside>

      <header className="sticky top-0 z-30 flex items-center justify-between gap-3 border-b border-line bg-paper/90 px-4 py-3 backdrop-blur lg:hidden">
        <Brand compact />
        <div className="flex items-center gap-2">
          <Link
            href="/notifications"
            className="relative inline-flex h-10 w-10 items-center justify-center rounded-full border border-line bg-surface text-muted"
            aria-label={unread ? `Notifications, ${unread} unread` : "Notifications"}
          >
            <Bell size={16} />
            {unread > 0 ? (
              <span className="num absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-ember px-1 font-mono text-[10px] text-paper">
                {unread}
              </span>
            ) : null}
          </Link>
          <ThemeToggle />
          <button
            type="button"
            onClick={() => setDrawer(true)}
            className="inline-flex h-10 w-10 items-center justify-center rounded-full border border-line bg-surface text-muted"
            aria-label="Open menu"
            aria-expanded={drawer}
            aria-controls="mobile-menu"
          >
            <Menu size={17} />
          </button>
        </div>
      </header>

      <main id="main-content" className="pb-24 lg:pb-12 lg:pl-64">
        <div className="mx-auto max-w-wide px-4 py-6 sm:px-6 lg:px-10 lg:py-10">{children}</div>
      </main>

      <nav
        aria-label="Mobile navigation"
        className="fixed inset-x-0 bottom-0 z-30 flex items-stretch justify-around border-t border-line bg-paper/95 px-2 pb-[max(0.25rem,env(safe-area-inset-bottom))] backdrop-blur lg:hidden"
      >
        {MOBILE_NAV.map((item) => {
          const active = isActive(item.href);
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "relative flex min-h-14 flex-1 flex-col items-center justify-center gap-1 text-[10.5px]",
                active ? "text-ink" : "text-muted",
              )}
            >
              <span
                aria-hidden
                className={cn(
                  "absolute top-1.5 h-0.5 w-6 rounded-full transition-opacity",
                  active ? "bg-ember opacity-100" : "opacity-0",
                )}
              />
              <Icon size={19} strokeWidth={active ? 2.1 : 1.7} />
              {item.label}
            </Link>
          );
        })}
      </nav>

      <AnimatePresence>
        {drawer ? (
          <motion.div
            className="fixed inset-0 z-50 lg:hidden"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.18 }}
          >
            <div
              aria-hidden
              className="absolute inset-0 bg-ink/40 backdrop-blur-[2px]"
              onClick={() => setDrawer(false)}
            />
            <motion.aside
              ref={drawerRef}
              id="mobile-menu"
              role="dialog"
              aria-modal="true"
              aria-label="Navigation menu"
              tabIndex={-1}
              className="absolute inset-y-0 left-0 flex w-[86%] max-w-xs flex-col border-r border-line bg-paper px-4 py-5 focus:outline-none"
              initial={{ x: "-100%" }}
              animate={{ x: 0 }}
              exit={{ x: "-100%" }}
              transition={reduceMotion ? { duration: 0 } : { type: "spring", stiffness: 380, damping: 34 }}
            >
              <div className="flex items-center justify-between">
                <Brand />
                <button
                  type="button"
                  onClick={closeDrawer}
                  className="inline-flex h-9 w-9 items-center justify-center rounded-full border border-line text-muted transition-colors hover:text-ink"
                  aria-label="Close menu"
                >
                  <X size={16} />
                </button>
              </div>
              <LinkButton href="/trips/new" size="md" className="mt-6 w-full">
                <Compass size={15} /> New journey
              </LinkButton>
              <nav
                aria-label="Menu navigation"
                className="mt-6 flex flex-1 flex-col gap-0.5 overflow-y-auto"
              >
                <p className="mb-1.5 px-3 text-[10.5px] font-medium uppercase tracking-editorial text-muted">
                  Workspace
                </p>
                {PRIMARY_NAV.map((item) => navLink(item, closeDrawer))}
                {adminLink(closeDrawer)}
                <div className="my-3 h-px bg-line" />
                <p className="mb-1.5 px-3 text-[10.5px] font-medium uppercase tracking-editorial text-muted">
                  You
                </p>
                {SECONDARY_NAV.map((item) => navLink(item, closeDrawer))}
              </nav>
              <div className="mt-4 space-y-2 border-t border-line pt-4">
                <div className="flex items-center gap-2.5 rounded-2xl border border-line bg-surface px-3 py-2.5">
                  <Avatar name={meUser?.display_name} size={32} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[13px] font-medium">{meUser?.display_name}</p>
                    <p className="truncate text-[11.5px] text-muted">{meUser?.email}</p>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setDrawer(false);
                    signOut();
                  }}
                  className="flex min-h-10 w-full items-center gap-2 rounded-xl px-3 text-[13px] text-muted transition-colors hover:bg-rose/10 hover:text-rose"
                >
                  <LogOut size={16} /> Sign out
                </button>
              </div>
            </motion.aside>
          </motion.div>
        ) : null}
      </AnimatePresence>
    </div>
  );
}
