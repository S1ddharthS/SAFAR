"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { ArrowRight, Compass, ShieldCheck } from "lucide-react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";

import { Brand, ThemeToggle } from "@/components/AppShell";
import { Button, Field, Input } from "@/components/ui";
import { api } from "@/lib/api";
import { useAuth } from "@/lib/store";
import { errorMessage } from "@/lib/utils";
import type { User } from "@/lib/types";

const schema = z.object({
  email: z.string().email("Enter a valid email"),
  password: z.string().min(1, "Enter your password"),
});

type FormValues = z.infer<typeof schema>;

function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const next = searchParams.get("next") || "/dashboard";
  const setSession = useAuth((state) => state.setSession);
  const token = useAuth((state) => state.token);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (token) router.replace(next);
  }, [token, router, next]);

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { email: "", password: "" },
  });

  const onSubmit = async (values: FormValues) => {
    setSubmitting(true);
    setError(null);
    try {
      const result = await api<{ access_token: string; csrf_token: string; user: User }>(
        "/api/auth/login",
        { method: "POST", body: values },
      );
      setSession(result.access_token, result.user, result.csrf_token);
      router.replace(next.startsWith("/") ? next : "/dashboard");
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="grid min-h-dvh lg:grid-cols-[1fr_1.05fr]">
      <div className="relative hidden overflow-hidden border-r border-line bg-ink p-10 text-paper lg:flex lg:flex-col lg:justify-between">
        <div
          className="absolute inset-0 opacity-10"
          style={{
            backgroundImage:
              "radial-gradient(circle at 20% 20%, #f0a34a 0, transparent 45%), radial-gradient(circle at 80% 70%, #5eead4 0, transparent 45%)",
          }}
          aria-hidden
        />
        <div className="relative">
          <span className="flex h-10 w-10 items-center justify-center rounded-full border border-paper/20 bg-paper/10">
            <Compass size={20} />
          </span>
          <p className="mt-8 max-w-md font-display text-3xl leading-tight">
            A journey is not a list of places. It is a set of people, moments and decisions.
          </p>
          <p className="mt-4 max-w-md text-sm leading-6 text-paper/65">
            SAFAR keeps the group aligned without flattening anyone&apos;s preferences. The engine
            recommends; the group decides.
          </p>
        </div>
        <div className="relative space-y-3 text-[12px] text-paper/55">
          <p className="flex items-center gap-2">
            <ShieldCheck size={14} /> Private budgets and access needs stay private.
          </p>
          <p className="flex items-center gap-2">
            <ShieldCheck size={14} /> Confirmed plans never change silently.
          </p>
        </div>
      </div>

      <div className="flex flex-col">
        <div className="flex items-center justify-between px-5 py-4 lg:px-10">
          <Brand />
          <ThemeToggle />
        </div>
        <div className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center px-5 pb-16 lg:px-0">
          <p className="eyebrow">Welcome back</p>
          <h1 className="mt-2 text-4xl leading-tight">Sign in</h1>
          <p className="mt-2 text-sm leading-6 text-muted">
            Pick up the plan, check the pulse, or see what the group decided while you were away.
          </p>

          <form className="mt-7 space-y-4" onSubmit={form.handleSubmit(onSubmit)} noValidate>
            <Field label="Email" error={form.formState.errors.email?.message} htmlFor="email">
              <Input
                id="email"
                type="email"
                autoComplete="email"
                placeholder="you@example.com"
                {...form.register("email")}
              />
            </Field>
            <Field
              label="Password"
              error={form.formState.errors.password?.message}
              htmlFor="password"
            >
              <Input
                id="password"
                type="password"
                autoComplete="current-password"
                placeholder="Your password"
                {...form.register("password")}
              />
            </Field>
            {error ? (
              <p className="rounded-xl border border-rose/20 bg-rose/5 px-3 py-2 text-[12.5px] text-rose">
                {error}
              </p>
            ) : null}
            <Button type="submit" size="lg" className="w-full" loading={submitting}>
              Sign in <ArrowRight size={16} />
            </Button>
          </form>

          <div className="mt-6 rounded-2xl border border-line bg-raised/60 px-4 py-3 text-[12px] leading-5 text-muted">
            <p className="font-medium text-ink">Seeded demo workspace</p>
            <p className="mt-0.5">
              <span className="font-mono text-[12px]">mira@safar.demo</span> ·{" "}
              <span className="font-mono text-[12px]">safar-demo-123</span>
            </p>
            <p className="mt-1 text-[12px] text-faint">
              Admin of a live Kyoto trip with members, proposals, expenses and memories.
            </p>
          </div>

          <p className="mt-6 text-[13px] text-muted">
            New to SAFAR?{" "}
            <Link href="/register" className="font-medium text-ember hover:underline">
              Create an account
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={<div className="min-h-dvh" />}>
      <LoginForm />
    </Suspense>
  );
}
