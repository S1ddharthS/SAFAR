"use client";

import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { AlertTriangle, X } from "lucide-react";
import Link from "next/link";
import type {
  ButtonHTMLAttributes,
  ComponentProps,
  InputHTMLAttributes,
  KeyboardEvent as ReactKeyboardEvent,
  ReactNode,
  SelectHTMLAttributes,
  TextareaHTMLAttributes,
} from "react";
import { useEffect, useId, useRef } from "react";

import { useToasts } from "@/lib/store";
import { cn, errorMessage, initials } from "@/lib/utils";

type ButtonVariant = "primary" | "secondary" | "ghost" | "danger" | "subtle";
type ButtonSize = "sm" | "md" | "lg";

const buttonVariants: Record<ButtonVariant, string> = {
  primary: "bg-ink text-paper hover:bg-ink/90 active:translate-y-px border border-ink",
  secondary:
    "bg-surface text-ink border border-line hover:border-ink/35 hover:bg-raised active:translate-y-px",
  ghost: "bg-transparent text-ink hover:bg-ink/5 border border-transparent",
  danger: "bg-rose text-white hover:bg-rose/90 border border-rose",
  subtle: "bg-ember-soft text-ember border border-ember/20 hover:bg-ember-soft/70",
};

const buttonSizes: Record<ButtonSize, string> = {
  sm: "h-8 px-3 text-[12.5px] rounded-full gap-1.5",
  md: "h-10 px-4 text-sm rounded-full gap-2",
  lg: "h-12 px-6 text-[15px] rounded-full gap-2",
};

export function Button({
  variant = "primary",
  size = "md",
  className,
  loading,
  children,
  type = "button",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant;
  size?: ButtonSize;
  loading?: boolean;
}) {
  return (
    <button
      type={type}
      aria-busy={loading || undefined}
      className={cn(
        "inline-flex shrink-0 items-center justify-center whitespace-nowrap font-medium transition-[background-color,border-color,color,transform,opacity] duration-200 ease-editorial disabled:cursor-not-allowed disabled:opacity-50",
        buttonVariants[variant],
        buttonSizes[size],
        className,
      )}
      disabled={props.disabled || loading}
      {...props}
    >
      {loading ? (
        <span
          aria-hidden
          className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-current border-t-transparent"
        />
      ) : null}
      {children}
    </button>
  );
}

export function LinkButton({
  href,
  variant = "primary",
  size = "md",
  className,
  children,
  ...rest
}: {
  href: string;
  variant?: ButtonVariant;
  size?: ButtonSize;
  className?: string;
  children: ReactNode;
} & Omit<ComponentProps<typeof Link>, "href" | "className" | "children">) {
  return (
    <Link
      href={href}
      className={cn(
        "inline-flex shrink-0 items-center justify-center whitespace-nowrap font-medium transition-[background-color,border-color,color,transform] duration-200 ease-editorial",
        buttonVariants[variant],
        buttonSizes[size],
        className,
      )}
      {...rest}
    >
      {children}
    </Link>
  );
}

export function IconButton({
  label,
  className,
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { label: string }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      className={cn(
        "inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-muted transition-colors hover:bg-ink/5 hover:text-ink disabled:opacity-50",
        className,
      )}
      {...props}
    >
      {children}
    </button>
  );
}

export function Card({
  className,
  children,
  as: Tag = "div",
  interactive,
}: {
  className?: string;
  children: ReactNode;
  as?: "div" | "section" | "article" | "li";
  interactive?: boolean;
}) {
  return (
    <Tag className={cn("card p-5 sm:p-6", interactive && "card-interactive", className)}>
      {children}
    </Tag>
  );
}

export function Badge({
  children,
  tone = "neutral",
  className,
}: {
  children: ReactNode;
  tone?: "neutral" | "ember" | "jade" | "rose" | "outline";
  className?: string;
}) {
  const tones = {
    neutral: "bg-raised text-muted border-line",
    ember: "bg-ember-soft text-ember border-ember/25",
    jade: "bg-jade-soft text-jade border-jade/25",
    rose: "bg-rose/10 text-rose border-rose/25",
    outline: "bg-transparent text-muted border-line",
  };
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-full border px-2.5 py-[3px] text-[11.5px] font-medium leading-4",
        tones[tone],
        className,
      )}
    >
      {children}
    </span>
  );
}

export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        "h-11 w-full rounded-xl border border-line bg-surface px-3.5 text-sm text-ink transition-colors placeholder:text-faint hover:border-ink/25 focus:border-ember focus:outline-none focus:ring-2 focus:ring-ember/20 disabled:cursor-not-allowed disabled:bg-raised disabled:text-muted aria-[invalid=true]:border-rose",
        className,
      )}
      {...props}
    />
  );
}

export function Textarea({ className, ...props }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      className={cn(
        "min-h-28 w-full resize-y rounded-xl border border-line bg-surface px-3.5 py-3 text-sm leading-6 text-ink transition-colors placeholder:text-faint hover:border-ink/25 focus:border-ember focus:outline-none focus:ring-2 focus:ring-ember/20 disabled:cursor-not-allowed disabled:bg-raised disabled:text-muted",
        className,
      )}
      {...props}
    />
  );
}

export function Select({
  className,
  children,
  style,
  ...props
}: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={cn(
        "h-11 w-full appearance-none rounded-xl border border-line bg-surface bg-[length:16px] bg-[right_0.85rem_center] bg-no-repeat px-3.5 pr-9 text-sm text-ink transition-colors hover:border-ink/25 focus:border-ember focus:outline-none focus:ring-2 focus:ring-ember/20 disabled:cursor-not-allowed disabled:bg-raised disabled:text-muted",
        className,
      )}
      style={{
        backgroundImage:
          "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 24 24' fill='none' stroke='%236b6559' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='m6 9 6 6 6-6'/%3E%3C/svg%3E\")",
        ...style,
      }}
      {...props}
    >
      {children}
    </select>
  );
}

export function Field({
  label,
  hint,
  error,
  children,
  htmlFor,
  className,
}: {
  label: string;
  hint?: string;
  error?: string;
  children: ReactNode;
  htmlFor?: string;
  className?: string;
}) {
  const body = (
    <>
      <span className="block text-[13px] font-medium text-ink">{label}</span>
      {children}
      {hint ? <span className="block text-[12px] leading-5 text-muted">{hint}</span> : null}
      {error ? (
        <span className="block text-[12px] leading-5 text-rose" role="alert">
          {error}
        </span>
      ) : null}
    </>
  );
  if (htmlFor) {
    return (
      <div className={cn("space-y-1.5", className)}>
        <label htmlFor={htmlFor} className="block space-y-1.5">
          {body}
        </label>
      </div>
    );
  }
  return <label className={cn("block space-y-1.5", className)}>{body}</label>;
}

export function Avatar({
  name,
  size = 36,
  className,
}: {
  name?: string | null;
  size?: number;
  className?: string;
}) {
  return (
    <span
      aria-hidden
      className={cn(
        "inline-flex shrink-0 items-center justify-center rounded-full border border-line bg-raised font-display text-ink",
        className,
      )}
      style={{ width: size, height: size, fontSize: size * 0.36 }}
      title={name || "Member"}
    >
      {initials(name)}
    </span>
  );
}

export function AvatarStack({
  names,
  max = 4,
  size = 28,
  className,
}: {
  names: (string | null | undefined)[];
  max?: number;
  size?: number;
  className?: string;
}) {
  const shown = names.slice(0, max);
  const rest = names.length - shown.length;
  return (
    <div className={cn("flex items-center", className)}>
      {shown.map((name, index) => (
        <span key={`${name}-${index}`} className="-ml-2 rounded-full ring-2 ring-surface first:ml-0">
          <Avatar name={name} size={size} />
        </span>
      ))}
      {rest > 0 ? (
        <span
          className="-ml-2 inline-flex items-center justify-center rounded-full border border-line bg-raised font-mono text-[11px] text-muted ring-2 ring-surface"
          style={{ width: size, height: size }}
        >
          +{rest}
        </span>
      ) : null}
      <span className="sr-only">{names.filter(Boolean).join(", ")}</span>
    </div>
  );
}

export function Progress({
  value,
  max = 100,
  tone = "ember",
  className,
}: {
  value: number;
  max?: number;
  tone?: "ember" | "jade" | "ink";
  className?: string;
}) {
  const width = Math.max(0, Math.min(100, (value / max) * 100));
  const tones = { ember: "bg-ember", jade: "bg-jade", ink: "bg-ink" };
  return (
    <span
      role="progressbar"
      aria-valuenow={Math.round(value)}
      aria-valuemin={0}
      aria-valuemax={max}
      className={cn("block h-1.5 w-full overflow-hidden rounded-full bg-line", className)}
    >
      <span
        className={cn(
          "block h-full rounded-full transition-all duration-500 ease-editorial",
          tones[tone],
        )}
        style={{ width: `${width}%` }}
      />
    </span>
  );
}

export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
  meta,
  className,
  size = "lg",
  as: Heading = "h1",
}: {
  eyebrow?: string;
  title: string;
  description?: string;
  actions?: ReactNode;
  meta?: ReactNode;
  className?: string;
  size?: "lg" | "md";
  as?: "h1" | "h2";
}) {
  return (
    <div
      className={cn(
        "flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between",
        size === "lg" ? "gap-5" : "gap-3",
        className,
      )}
    >
      <div className="min-w-0 space-y-2">
        {eyebrow ? <p className="eyebrow">{eyebrow}</p> : null}
        <Heading
          className={cn(
            "text-balance leading-[1.08]",
            size === "lg" ? "text-[1.9rem] sm:text-[2.4rem]" : "text-2xl sm:text-[1.7rem]",
          )}
        >
          {title}
        </Heading>
        {description ? (
          <p className="max-w-prose text-sm leading-6 text-muted">{description}</p>
        ) : null}
        {meta ? <div className="pt-0.5">{meta}</div> : null}
      </div>
      {actions ? (
        <div className="flex flex-wrap items-center gap-2 sm:justify-end">{actions}</div>
      ) : null}
    </div>
  );
}

export function SectionTitle({
  title,
  hint,
  action,
  level = 2,
  className,
}: {
  title: string;
  hint?: string;
  action?: ReactNode;
  level?: 2 | 3;
  className?: string;
}) {
  const Heading = level === 2 ? "h2" : "h3";
  return (
    <div className={cn("mb-4 flex items-end justify-between gap-4", className)}>
      <div className="min-w-0">
        <Heading className={level === 2 ? "text-xl leading-tight" : "text-lg leading-tight"}>
          {title}
        </Heading>
        {hint ? <p className="mt-1 text-[12.5px] leading-5 text-muted">{hint}</p> : null}
      </div>
      {action ? <div className="shrink-0">{action}</div> : null}
    </div>
  );
}

export function EmptyState({
  title,
  description,
  action,
  icon,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
  icon?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center gap-3 rounded-3xl border border-dashed border-line bg-surface/60 px-6 py-12 text-center">
      {icon ? (
        <span className="inline-flex h-11 w-11 items-center justify-center rounded-2xl border border-line bg-raised text-ember">
          {icon}
        </span>
      ) : null}
      <h3 className="text-lg">{title}</h3>
      {description ? (
        <p className="max-w-sm text-[13px] leading-6 text-muted">{description}</p>
      ) : null}
      {action ? <div className="pt-1">{action}</div> : null}
    </div>
  );
}

export function Skeleton({ className }: { className?: string }) {
  return <div className={cn("skeleton h-4 w-full", className)} />;
}

export function PageSkeleton() {
  return (
    <div className="space-y-5" aria-busy="true" aria-live="polite">
      <span className="sr-only">Loading</span>
      <Skeleton className="h-7 w-48" />
      <Skeleton className="h-4 w-72 max-w-full" />
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Skeleton className="h-24" />
        <Skeleton className="h-24" />
        <Skeleton className="h-24" />
        <Skeleton className="h-24" />
      </div>
      <Skeleton className="h-52" />
    </div>
  );
}

export function ErrorState({ error, retry }: { error: unknown; retry?: () => void }) {
  return (
    <div role="alert" className="rounded-3xl border border-rose/20 bg-rose/5 p-5 sm:p-6">
      <div className="flex items-start gap-3">
        <span className="mt-0.5 inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-rose/10 text-rose">
          <AlertTriangle size={16} />
        </span>
        <div className="min-w-0">
          <p className="text-sm font-medium text-ink">We could not load this yet.</p>
          <p className="mt-1 text-[13px] leading-5 text-muted">{errorMessage(error)}</p>
          {retry ? (
            <Button variant="secondary" size="sm" className="mt-3" onClick={retry}>
              Try again
            </Button>
          ) : null}
        </div>
      </div>
    </div>
  );
}

export function Stat({
  label,
  value,
  hint,
  tone = "ink",
  icon,
}: {
  label: string;
  value: ReactNode;
  hint?: string;
  tone?: "ink" | "ember" | "jade" | "rose";
  icon?: ReactNode;
}) {
  const tones = { ink: "text-ink", ember: "text-ember", jade: "text-jade", rose: "text-rose" };
  return (
    <div className="rounded-2xl border border-line bg-surface px-4 py-3.5">
      <div className="flex items-center justify-between gap-2">
        <p className="text-[11px] uppercase tracking-editorial text-muted">{label}</p>
        {icon ? <span className="text-faint">{icon}</span> : null}
      </div>
      <p className={cn("num mt-1.5 font-display text-[1.6rem] leading-none", tones[tone])}>
        {value}
      </p>
      {hint ? <p className="mt-2 text-[11.5px] leading-4 text-muted">{hint}</p> : null}
    </div>
  );
}

export function MetaRow({
  items,
  className,
}: {
  items: (ReactNode | null | false | undefined)[];
  className?: string;
}) {
  const visible = items.filter(Boolean);
  if (!visible.length) return null;
  return (
    <div className={cn("meta-dot", className)}>
      {visible.map((item, index) => (
        <span key={index} className="inline-flex items-center gap-1">
          {item}
        </span>
      ))}
    </div>
  );
}

export function SegmentedControl<T extends string>({
  options,
  value,
  onChange,
  label,
  size = "md",
  className,
}: {
  options: { value: T; label: string; icon?: ReactNode; disabled?: boolean }[];
  value: T;
  onChange: (value: T) => void;
  label: string;
  size?: "sm" | "md";
  className?: string;
}) {
  const handleKeyDown = (event: ReactKeyboardEvent<HTMLDivElement>) => {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    const buttons = Array.from(
      event.currentTarget.querySelectorAll<HTMLButtonElement>("[data-segment]"),
    ).filter((button) => !button.disabled);
    if (!buttons.length) return;
    event.preventDefault();
    const currentIndex = buttons.indexOf(document.activeElement as HTMLButtonElement);
    let nextIndex = currentIndex;
    if (event.key === "ArrowLeft") nextIndex = (currentIndex - 1 + buttons.length) % buttons.length;
    if (event.key === "ArrowRight") nextIndex = (currentIndex + 1) % buttons.length;
    if (event.key === "Home") nextIndex = 0;
    if (event.key === "End") nextIndex = buttons.length - 1;
    const next = buttons[nextIndex];
    next?.focus();
    const nextValue = next?.dataset.value as T | undefined;
    if (nextValue) onChange(nextValue);
  };

  return (
    <div
      role="group"
      aria-label={label}
      onKeyDown={handleKeyDown}
      className={cn(
        "hide-scrollbar flex gap-1 overflow-x-auto rounded-full border border-line bg-raised/70 p-1",
        className,
      )}
    >
      {options.map((option) => {
        const active = option.value === value;
        return (
          <button
            key={option.value}
            type="button"
            data-segment
            data-value={option.value}
            aria-pressed={active}
            disabled={option.disabled}
            onClick={() => onChange(option.value)}
            className={cn(
              "inline-flex shrink-0 items-center justify-center gap-1.5 rounded-full font-medium transition-colors disabled:opacity-40",
              size === "sm" ? "h-8 px-3 text-[12.5px]" : "h-9 px-4 text-[13px]",
              active ? "bg-surface text-ink shadow-card" : "text-muted hover:text-ink",
            )}
          >
            {option.icon}
            {option.label}
          </button>
        );
      })}
    </div>
  );
}

export function Modal({
  open,
  onClose,
  title,
  description,
  children,
  wide,
  footer,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  description?: string;
  children: ReactNode;
  wide?: boolean;
  footer?: ReactNode;
}) {
  const reduce = useReducedMotion();
  const panelRef = useRef<HTMLDivElement>(null);
  const restoreRef = useRef<HTMLElement | null>(null);
  const titleId = useId();
  const descriptionId = useId();

  useEffect(() => {
    if (!open) return;
    restoreRef.current = document.activeElement as HTMLElement | null;
    const panel = panelRef.current;

    const focusables = () =>
      Array.from(
        panel?.querySelectorAll<HTMLElement>(
          'a[href],button:not([disabled]),textarea:not([disabled]),input:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])',
        ) ?? [],
      ).filter((node) => node.offsetParent !== null);

    panel?.focus({ preventScroll: true });

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        onClose();
        return;
      }
      if (event.key !== "Tab") return;
      const nodes = focusables();
      if (!nodes.length) {
        event.preventDefault();
        return;
      }
      const index = nodes.indexOf(document.activeElement as HTMLElement);
      if (event.shiftKey && index <= 0) {
        event.preventDefault();
        nodes[nodes.length - 1].focus();
      } else if (!event.shiftKey && (index === -1 || index === nodes.length - 1)) {
        event.preventDefault();
        nodes[0].focus();
      }
    };

    window.addEventListener("keydown", onKeyDown);
    const previousOverflow = document.body.style.overflow;
    const previousPadding = document.body.style.paddingRight;
    const scrollbar = window.innerWidth - document.documentElement.clientWidth;
    document.body.style.overflow = "hidden";
    if (scrollbar > 0) document.body.style.paddingRight = `${scrollbar}px`;

    return () => {
      window.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = previousOverflow;
      document.body.style.paddingRight = previousPadding;
      if (restoreRef.current?.isConnected) restoreRef.current.focus();
    };
  }, [open, onClose]);

  return (
    <AnimatePresence>
      {open ? (
        <motion.div
          className="fixed inset-0 z-50 flex items-end justify-center bg-ink/45 p-0 backdrop-blur-[3px] sm:items-center sm:p-6"
          initial={reduce ? false : { opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={reduce ? { opacity: 1 } : { opacity: 0 }}
          transition={{ duration: 0.2 }}
          onClick={(event) => {
            if (event.target === event.currentTarget) onClose();
          }}
        >
          <motion.div
            ref={panelRef}
            role="dialog"
            aria-modal="true"
            aria-labelledby={titleId}
            aria-describedby={description ? descriptionId : undefined}
            tabIndex={-1}
            initial={reduce ? false : { y: 32, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={reduce ? { opacity: 1 } : { y: 20, opacity: 0 }}
            transition={{ duration: 0.26, ease: [0.22, 1, 0.36, 1] }}
            className={cn(
              "flex max-h-[92vh] w-full flex-col overflow-hidden rounded-t-3xl border border-line bg-paper shadow-lift outline-none sm:rounded-3xl",
              wide ? "sm:max-w-2xl" : "sm:max-w-lg",
            )}
          >
            <div className="flex items-start justify-between gap-4 border-b border-line px-5 py-4 sm:px-6">
              <div className="min-w-0">
                <h2 id={titleId} className="text-xl leading-tight">
                  {title}
                </h2>
                {description ? (
                  <p id={descriptionId} className="mt-1 text-[12.5px] leading-5 text-muted">
                    {description}
                  </p>
                ) : null}
              </div>
              <IconButton label="Close dialog" onClick={onClose} className="-mr-2 -mt-1">
                <X size={18} />
              </IconButton>
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 py-4 sm:px-6 sm:py-5">
              {children}
            </div>
            {footer ? (
              <div className="border-t border-line bg-surface/60 px-5 py-3.5 sm:px-6">
                {footer}
              </div>
            ) : null}
          </motion.div>
        </motion.div>
      ) : null}
    </AnimatePresence>
  );
}

export function Toggle({
  checked,
  onChange,
  label,
  description,
}: {
  checked: boolean;
  onChange: (value: boolean) => void;
  label: string;
  description?: string;
}) {
  return (
    <div className="flex items-start justify-between gap-4 py-3">
      <div className="min-w-0">
        <p className="text-sm font-medium text-ink">{label}</p>
        {description ? (
          <p className="mt-0.5 text-[12.5px] leading-5 text-muted">{description}</p>
        ) : null}
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        onClick={() => onChange(!checked)}
        className={cn(
          "relative mt-0.5 h-6 w-11 shrink-0 rounded-full border transition-colors",
          checked ? "border-ember bg-ember" : "border-line bg-line",
        )}
      >
        <span
          aria-hidden
          className={cn(
            "absolute top-0.5 h-5 w-5 rounded-full bg-surface shadow transition-transform duration-200 ease-editorial",
            checked ? "translate-x-[22px]" : "translate-x-0.5",
          )}
        />
      </button>
    </div>
  );
}

export function ScoreBar({
  label,
  value,
  max = 10,
  tone = "ember",
  suffix,
}: {
  label: string;
  value: number;
  max?: number;
  tone?: "ember" | "jade" | "ink";
  suffix?: string;
}) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-baseline justify-between gap-2 text-[12px]">
        <span className="text-muted">{label}</span>
        <span className="num font-mono text-[12px] text-ink">{suffix ?? value.toFixed(0)}</span>
      </div>
      <Progress value={value} max={max} tone={tone} />
    </div>
  );
}

export function Toasts() {
  const { toasts, dismiss } = useToasts();
  const reduce = useReducedMotion();
  return (
    <div
      aria-label="Notifications"
      aria-live="polite"
      className="pointer-events-none fixed inset-x-3 bottom-[calc(4.75rem+env(safe-area-inset-bottom))] z-[60] flex flex-col items-center gap-2 sm:bottom-6 sm:left-auto sm:right-6 sm:items-end"
    >
      <AnimatePresence initial={false}>
        {toasts.slice(-4).map((toast) => (
          <motion.div
            key={toast.id}
            role={toast.tone === "error" ? "alert" : "status"}
            initial={reduce ? false : { opacity: 0, y: 12, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={reduce ? { opacity: 0 } : { opacity: 0, y: 8, scale: 0.98 }}
            transition={{ duration: 0.22, ease: [0.22, 1, 0.36, 1] }}
            className={cn(
              "pointer-events-auto w-full max-w-sm overflow-hidden rounded-2xl border bg-surface shadow-lift",
              toast.tone === "error" ? "border-rose/30" : "border-line",
            )}
          >
            <div className="flex items-start justify-between gap-3 px-4 py-3">
              <div className="min-w-0">
                <p
                  className={cn(
                    "text-sm font-medium",
                    toast.tone === "error"
                      ? "text-rose"
                      : toast.tone === "success"
                        ? "text-jade"
                        : "text-ink",
                  )}
                >
                  {toast.title}
                </p>
                {toast.description ? (
                  <p className="mt-0.5 text-[12.5px] leading-5 text-muted">{toast.description}</p>
                ) : null}
              </div>
              <IconButton
                label="Dismiss notification"
                onClick={() => dismiss(toast.id)}
                className="-mr-2 -mt-1 h-7 w-7"
              >
                <X size={14} />
              </IconButton>
            </div>
            <span
              aria-hidden
              className={cn(
                "block h-0.5 w-full",
                toast.tone === "error"
                  ? "bg-rose/50"
                  : toast.tone === "success"
                    ? "bg-jade/50"
                    : "bg-ember/40",
              )}
            />
          </motion.div>
        ))}
      </AnimatePresence>
    </div>
  );
}

export function FlowNote({ children, icon }: { children: ReactNode; icon?: ReactNode }) {
  return (
    <div className="flex gap-2.5 rounded-2xl border border-line bg-raised/60 p-3.5 text-[12.5px] leading-5 text-muted">
      {icon ? <span className="mt-0.5 shrink-0 text-ember">{icon}</span> : null}
      <div className="min-w-0">{children}</div>
    </div>
  );
}

export function Tabs({
  tabs,
  active,
  label = "Section",
}: {
  tabs: { href: string; label: string; count?: number }[];
  active: string;
  label?: string;
}) {
  return (
    <nav
      aria-label={label}
      className="hide-scrollbar -mx-4 flex gap-1 overflow-x-auto px-4 sm:mx-0 sm:px-0"
    >
      {tabs.map((tab) => {
        const isActive = tab.href === active;
        return (
          <Link
            key={tab.href}
            href={tab.href}
            aria-current={isActive ? "page" : undefined}
            className={cn(
              "inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-full border px-3.5 text-[13px] transition-colors",
              isActive
                ? "border-ink bg-ink text-paper"
                : "border-line bg-surface text-muted hover:border-ink/30 hover:text-ink",
            )}
          >
            {tab.label}
            {tab.count !== undefined ? (
              <span
                className={cn(
                  "num font-mono text-[11px]",
                  isActive ? "text-paper/70" : "text-faint",
                )}
              >
                {tab.count}
              </span>
            ) : null}
          </Link>
        );
      })}
    </nav>
  );
}
