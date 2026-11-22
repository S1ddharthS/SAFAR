"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { ArrowRight, Compass } from "lucide-react";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";

import {
  Badge,
  Button,
  Card,
  Field,
  Input,
  PageHeader,
  Select,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useDestinations } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import type { Trip } from "@/lib/types";
import { errorMessage, formatDate, todayIso } from "@/lib/utils";

function addDays(iso: string, days: number) {
  const date = new Date(`${iso}T12:00:00`);
  date.setDate(date.getDate() + days);
  return date.toISOString().slice(0, 10);
}

const schema = z
  .object({
    name: z.string().min(2, "Give the journey a name").max(120),
    description: z.string().max(2000).optional(),
    destination_id: z.string().optional(),
    start_date: z.string().min(1, "Choose a start date"),
    end_date: z.string().min(1, "Choose an end date"),
    group_size: z.coerce.number().int().min(2, "At least 2 travellers").max(12),
    budget_total: z.string().optional(),
    currency: z.string().min(3).max(8),
  })
  .refine((values) => values.end_date >= values.start_date, {
    message: "End date must be on or after the start date",
    path: ["end_date"],
  });

type FormValues = z.infer<typeof schema>;

function NewTripForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const destinations = useDestinations();
  const push = useToasts((state) => state.push);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const presetDestination = searchParams.get("destination_id") || "";
  const presetName = searchParams.get("destination_name") || "";
  const today = todayIso();

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: "",
      description: "",
      destination_id: presetDestination,
      start_date: addDays(today, 30),
      end_date: addDays(today, 34),
      group_size: 4,
      budget_total: "",
      currency: "EUR",
    },
  });

  useEffect(() => {
    if (presetName && !form.getValues("name")) {
      form.setValue("name", `${presetName}, together`);
    }
  }, [presetName, form]);

  const start = form.watch("start_date");
  const end = form.watch("end_date");

  const onSubmit = async (values: FormValues) => {
    setSubmitting(true);
    setError(null);
    try {
      const trip = await api<Trip>("/api/trips", {
        method: "POST",
        body: {
          name: values.name,
          description: values.description || null,
          destination_id: values.destination_id || null,
          destination_name:
            destinations.data?.find((item) => item.id === values.destination_id)?.name || null,
          start_date: values.start_date,
          end_date: values.end_date,
          group_size: values.group_size,
          budget_total: values.budget_total ? Number(values.budget_total) : null,
          currency: values.currency,
        },
      });
      push("Journey created", "Invite the group and share a Pulse when you are ready.", "success");
      router.push(`/trips/${trip.id}/members`);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  const nights =
    start && end
      ? Math.max(0, Math.round((new Date(`${end}T12:00:00`).getTime() - new Date(`${start}T12:00:00`).getTime()) / 86400000))
      : 0;

  return (
    <div className="mx-auto max-w-3xl">
      <PageHeader
        eyebrow="New journey"
        title="Start with the shape of the trip"
        description="You can change every field later. The itinerary stays untouched until the group approves a proposal."
      />
      <form onSubmit={form.handleSubmit(onSubmit)} className="mt-6 space-y-4" noValidate>
        <Card className="space-y-4">
          <Field label="Journey name" error={form.formState.errors.name?.message}>
            <Input placeholder="Kyoto in the rain" {...form.register("name")} />
          </Field>
          <Field label="Description" hint="Optional. A sentence the group will understand.">
            <Textarea placeholder="Slow days, tea, gardens, one big walk." {...form.register("description")} />
          </Field>
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Destination" hint="Leave open if you have not decided.">
              <Select {...form.register("destination_id")}>
                <option value="">Open destination</option>
                {(destinations.data ?? []).map((destination) => (
                  <option key={destination.id} value={destination.id}>
                    {destination.name}, {destination.country}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Group size" error={form.formState.errors.group_size?.message}>
              <Input type="number" min={2} max={12} {...form.register("group_size")} />
            </Field>
            <Field label="Start date" error={form.formState.errors.start_date?.message}>
              <Input type="date" {...form.register("start_date")} />
            </Field>
            <Field label="End date" error={form.formState.errors.end_date?.message}>
              <Input type="date" {...form.register("end_date")} />
            </Field>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Shared budget" hint="Optional total for the group. Individual limits stay private.">
              <Input type="number" min={0} placeholder="3200" {...form.register("budget_total")} />
            </Field>
            <Field label="Currency">
              <Select {...form.register("currency")}>
                <option value="EUR">EUR</option>
                <option value="USD">USD</option>
                <option value="GBP">GBP</option>
                <option value="JPY">JPY</option>
                <option value="INR">INR</option>
              </Select>
            </Field>
          </div>
        </Card>

        <Card className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <p className="text-[10px] uppercase tracking-editorial text-faint">Summary</p>
            <p className="mt-1 text-[14px]">
              {start && end ? `${formatDate(start)} → ${formatDate(end)}` : "Choose your dates"}
            </p>
            <p className="mt-1 text-[12px] text-muted">
              {nights} night{nights === 1 ? "" : "s"} ·{" "}
              {destinations.data?.find((item) => item.id === form.watch("destination_id"))?.name ||
                "open destination"}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Badge tone="outline">No silent plan changes</Badge>
            <Badge tone="jade">Private by default</Badge>
          </div>
        </Card>

        {error ? (
          <p className="rounded-xl border border-rose/20 bg-rose/5 px-3 py-2 text-[12.5px] text-rose">
            {error}
          </p>
        ) : null}

        <div className="flex items-center justify-between">
          <p className="text-[12px] leading-5 text-faint">
            Creating a trip makes you the owner. You can invite admins and members next.
          </p>
          <Button type="submit" size="lg" loading={submitting}>
            Create journey <ArrowRight size={16} />
          </Button>
        </div>
      </form>

      <div className="mt-8 flex items-start gap-3 rounded-2xl border border-line bg-raised/50 p-4 text-[12px] leading-5 text-muted">
        <Compass size={16} className="mt-0.5 text-ember" />
        <p>
          SAFAR will not add activities on its own. Once the group joins, the engine can suggest
          three possible days. Each one becomes a proposal that the group explicitly approves.
        </p>
      </div>
    </div>
  );
}

export default function NewTripPage() {
  return (
    <Suspense fallback={<div />}>
      <NewTripForm />
    </Suspense>
  );
}
