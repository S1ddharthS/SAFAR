"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { ArrowRight, Compass } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";

import { Brand, ThemeToggle } from "@/components/AppShell";
import { Button, Field, Input } from "@/components/ui";
import { api } from "@/lib/api";
import { useAuth } from "@/lib/store";
import type { User } from "@/lib/types";
import { errorMessage } from "@/lib/utils";

const schema = z
  .object({
    display_name: z.string().min(2, "Use at least 2 characters").max(80),
    email: z.string().email("Enter a valid email"),
    password: z.string().min(8, "Use at least 8 characters").max(128),
    confirm: z.string(),
    terms: z.boolean().refine((value) => value, {
      message: "You must accept the terms to continue",
    }),
  })
  .refine((values) => values.password === values.confirm, {
    message: "Passwords do not match",
    path: ["confirm"],
  });

type FormValues = z.infer<typeof schema>;

export default function RegisterPage() {
  const router = useRouter();
  const setSession = useAuth((state) => state.setSession);
  const token = useAuth((state) => state.token);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (token) router.replace("/dashboard");
  }, [token, router]);

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { display_name: "", email: "", password: "", confirm: "", terms: false },
  });

  const onSubmit = async (values: FormValues) => {
    setSubmitting(true);
    setError(null);
    try {
      const result = await api<{ access_token: string; csrf_token: string; user: User }>(
        "/api/auth/register",
        {
          method: "POST",
          body: {
            display_name: values.display_name,
            email: values.email,
            password: values.password,
          },
        },
      );
      setSession(result.access_token, result.user, result.csrf_token);
      router.replace("/onboarding");
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
              "radial-gradient(circle at 25% 25%, #f0a34a 0, transparent 45%), radial-gradient(circle at 75% 75%, #5eead4 0, transparent 42%)",
          }}
          aria-hidden
        />
        <div className="relative">
          <span className="flex h-10 w-10 items-center justify-center rounded-full border border-paper/20 bg-paper/10">
            <Compass size={20} />
          </span>
          <p className="mt-8 max-w-md font-display text-3xl leading-tight">
            Tell SAFAR how you travel. It will never decide for you.
          </p>
          <p className="mt-4 max-w-md text-sm leading-6 text-paper/65">
            Journey DNA is editable, explainable and always yours. It shapes suggestions; it does
            not label you permanently.
          </p>
        </div>
        <div className="relative text-[12px] leading-5 text-paper/55">
          <p>Terms are recorded with a policy version. Personalisation, analytics, location and marketing each need separate consent.</p>
        </div>
      </div>

      <div className="flex flex-col">
        <div className="flex items-center justify-between px-5 py-4 lg:px-10">
          <Brand />
          <ThemeToggle />
        </div>
        <div className="mx-auto flex w-full max-w-md flex-1 flex-col justify-center px-5 pb-16 lg:px-0">
          <p className="eyebrow">Begin</p>
          <h1 className="mt-2 text-4xl leading-tight">Create your account</h1>
          <p className="mt-2 text-sm leading-6 text-muted">
            Two minutes now, a much better journey later.
          </p>

          <form className="mt-7 space-y-4" onSubmit={form.handleSubmit(onSubmit)} noValidate>
            <Field
              label="Display name"
              error={form.formState.errors.display_name?.message}
              htmlFor="display_name"
            >
              <Input
                id="display_name"
                autoComplete="name"
                placeholder="How your group will see you"
                {...form.register("display_name")}
              />
            </Field>
            <Field label="Email" error={form.formState.errors.email?.message} htmlFor="email">
              <Input
                id="email"
                type="email"
                autoComplete="email"
                placeholder="you@example.com"
                {...form.register("email")}
              />
            </Field>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field
                label="Password"
                hint="At least 8 characters"
                error={form.formState.errors.password?.message}
                htmlFor="password"
              >
                <Input
                  id="password"
                  type="password"
                  autoComplete="new-password"
                  {...form.register("password")}
                />
              </Field>
              <Field
                label="Confirm"
                error={form.formState.errors.confirm?.message}
                htmlFor="confirm"
              >
                <Input
                  id="confirm"
                  type="password"
                  autoComplete="new-password"
                  {...form.register("confirm")}
                />
              </Field>
            </div>

            <label className="flex items-start gap-2.5 rounded-xl border border-line bg-surface px-3.5 py-3 text-[12px] leading-5 text-muted">
              <input
                type="checkbox"
                className="mt-1 h-4 w-4 accent-[rgb(var(--ember))]"
                {...form.register("terms")}
              />
              <span>
                I agree to the SAFAR terms and privacy policy. Consent for personalisation,
                analytics, location and marketing is separate and can be changed at any time.
              </span>
            </label>
            {form.formState.errors.terms?.message ? (
              <p className="text-xs text-rose">{form.formState.errors.terms.message}</p>
            ) : null}

            {error ? (
              <p className="rounded-xl border border-rose/20 bg-rose/5 px-3 py-2 text-[12.5px] text-rose">
                {error}
              </p>
            ) : null}
            <Button type="submit" size="lg" className="w-full" loading={submitting}>
              Create account <ArrowRight size={16} />
            </Button>
          </form>

          <p className="mt-6 text-[13px] text-muted">
            Already have an account?{" "}
            <Link href="/login" className="font-medium text-ember hover:underline">
              Sign in
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}
