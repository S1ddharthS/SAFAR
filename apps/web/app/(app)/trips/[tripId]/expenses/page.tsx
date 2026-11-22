"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeftRight,
  Download,
  Receipt,
  Scale,
  Trash2,
  Wallet,
} from "lucide-react";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  FlowNote,
  Input,
  Modal,
  PageSkeleton,
  SectionTitle,
  Select,
  Stat,
  Textarea,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useBalances, useExpenses, useMembers, useTrip } from "@/lib/hooks";
import { useAuth, useToasts } from "@/lib/store";
import { cn, errorMessage, formatDate, formatMoney, titleCase, todayIso } from "@/lib/utils";

const CATEGORIES = ["food", "transport", "stay", "activity", "shopping", "other"];
const SPLITS = [
  { value: "equal", label: "Split equally" },
  { value: "weights", label: "Weighted" },
  { value: "custom", label: "Custom amounts" },
];

interface Draft {
  userId: string;
  included: boolean;
  weight: string;
  share: string;
}

export default function ExpensesPage() {
  const params = useParams<{ tripId: string }>();
  const tripId = typeof params?.tripId === "string" ? params.tripId : "";
  const trip = useTrip(tripId);
  const expenses = useExpenses(tripId);
  const balances = useBalances(tripId);
  const members = useMembers(tripId);
  const queryClient = useQueryClient();
  const { user } = useAuth();
  const { push } = useToasts();

  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [category, setCategory] = useState("food");
  const [amount, setAmount] = useState("");
  const [paidBy, setPaidBy] = useState("");
  const [incurredOn, setIncurredOn] = useState(todayIso());
  const [notes, setNotes] = useState("");
  const [split, setSplit] = useState("equal");
  const [draft, setDraft] = useState<Draft[]>([]);

  const people = useMemo(
    () => (members.data?.items ?? []).filter((member) => member.user),
    [members.data],
  );

  const openModal = () => {
    setDraft(
      (members.data?.items ?? []).map((member) => ({
        userId: member.user?.id || member.id,
        included: true,
        weight: "1",
        share: "",
      })),
    );
    setPaidBy(user?.id || "");
    setOpen(true);
  };

  const refresh = () => {
    queryClient.invalidateQueries({ queryKey: ["expenses", tripId] });
    queryClient.invalidateQueries({ queryKey: ["balances", tripId] });
  };

  const createExpense = useMutation({
    mutationFn: () => {
      const participants = draft
        .filter((entry) => entry.included)
        .map((entry) => ({
          user_id: entry.userId,
          weight: split === "weights" ? Number(entry.weight) || 1 : 1,
          share_amount: split === "custom" ? Number(entry.share) || 0 : null,
        }));
      return api(`/api/trips/${tripId}/expenses`, {
        method: "POST",
        body: {
          title,
          category,
          amount: Number(amount),
          currency: trip.data?.currency,
          paid_by: paidBy || undefined,
          incurred_on: incurredOn,
          notes: notes || null,
          split,
          participants,
        },
      });
    },
    onSuccess: () => {
      push("Expense added", "Balances and settlements updated.", "success");
      setOpen(false);
      setTitle("");
      setAmount("");
      setNotes("");
      refresh();
    },
    onError: (error) => push("Could not add expense", errorMessage(error), "error"),
  });

  const removeExpense = useMutation({
    mutationFn: (expenseId: string) =>
      api(`/api/trips/${tripId}/expenses/${expenseId}`, { method: "DELETE" }),
    onSuccess: () => {
      push("Expense removed", "It no longer affects balances.", "info");
      refresh();
    },
    onError: (error) => push("Could not remove", errorMessage(error), "error"),
  });

  const downloadCsv = async () => {
    try {
      const csv = await api<string>(`/api/trips/${tripId}/expenses/export`, { raw: true });
      const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `${trip.data?.name || "trip"}-expenses.csv`;
      link.click();
      URL.revokeObjectURL(url);
    } catch (error) {
      push("Export failed", errorMessage(error), "error");
    }
  };

  if (expenses.isLoading) return <PageSkeleton />;
  if (expenses.error || !expenses.data) {
    return <ErrorState error={expenses.error || new Error("Expenses unavailable")} retry={() => expenses.refetch()} />;
  }

  const data = expenses.data;
  const totals = data.totals;
  const currency = String(totals.currency || trip.data?.currency || "EUR");
  const spent = Number(totals.spent || 0);
  const budget = totals.trip_budget as number | null | undefined;
  const remaining = totals.remaining as number | null | undefined;

  const customTotal = draft
    .filter((entry) => entry.included)
    .reduce((sum, entry) => sum + (Number(entry.share) || 0), 0);

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Money</p>
          <h2 className="mt-1 text-2xl">Track spending, settle fairly</h2>
          <p className="mt-1 max-w-prose text-sm text-muted">
            SAFAR tracks and suggests settlements. It never moves money.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="secondary" size="sm" onClick={downloadCsv}>
            <Download size={14} /> Export CSV
          </Button>
          <Button size="sm" onClick={openModal}>
            <Receipt size={14} /> Add expense
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        <Stat label="Spent" value={formatMoney(spent, currency)} tone="ink" />
        <Stat label="Entries" value={Number(totals.count || 0)} tone="ember" />
        <Stat
          label="Trip budget"
          value={budget ? formatMoney(budget, currency) : "—"}
          tone="ink"
          hint="Shared budget, not private limits"
        />
        <Stat
          label="Remaining"
          value={remaining === null || remaining === undefined ? "—" : formatMoney(remaining, currency)}
          tone={remaining !== null && remaining !== undefined && remaining < 0 ? "rose" : "jade"}
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="space-y-4">
          <SectionTitle title="Balances" hint="Net position per traveller" action={<Scale size={16} className="text-faint" />} />
          {balances.data?.balances.length ? (
            <div className="space-y-2">
              {balances.data.balances.map((balance) => (
                <div
                  key={balance.user_id}
                  className="flex items-center justify-between rounded-xl border border-line bg-surface px-3 py-2"
                >
                  <span className="text-[13px] text-ink">{balance.display_name}</span>
                  <span
                    className={cn(
                      "font-mono text-[12.5px]",
                      balance.net > 0.01 ? "text-jade" : balance.net < -0.01 ? "text-rose" : "text-faint",
                    )}
                  >
                    {balance.net > 0.01 ? "+" : ""}
                    {formatMoney(balance.net, currency)}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-muted">No balances yet. Add the first expense.</p>
          )}
          <FlowNote icon={<Wallet size={14} />}>
            {balances.data?.disclosure || "Tracking only — SAFAR does not move money."}
          </FlowNote>
        </Card>

        <Card className="space-y-4">
          <SectionTitle title="Suggested settlements" hint="Fewest transfers to balance the group" />
          {balances.data?.settlements.length ? (
            <div className="space-y-2">
              {balances.data.settlements.map((settlement, index) => (
                <div
                  key={`${settlement.from_user_id}-${settlement.to_user_id}-${index}`}
                  className="flex items-center justify-between rounded-xl border border-line bg-surface px-3 py-2"
                >
                  <span className="inline-flex items-center gap-1.5 text-[12.5px] text-muted">
                    {settlement.from_name}
                    <ArrowLeftRight size={12} className="text-faint" />
                    {settlement.to_name}
                  </span>
                  <span className="font-mono text-[12.5px] text-ink">{formatMoney(settlement.amount, currency)}</span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-muted">Everyone is settled up.</p>
          )}
          <FlowNote icon={<ArrowLeftRight size={14} />}>
            Settlements are suggestions based on recorded expenses. Confirm transfers outside SAFAR.
          </FlowNote>
        </Card>
      </div>

      <Card className="space-y-4">
        <SectionTitle title="Expenses" hint={`${data.items.length} recorded`} />
        {data.items.length === 0 ? (
          <EmptyState
            title="No expenses yet"
            description="Add the first shared cost. Everyone sees the same balances."
            icon={<Receipt size={24} />}
          />
        ) : (
          <div className="space-y-2">
            {data.items.map((expense) => (
              <div key={expense.id} className="rounded-2xl border border-line bg-surface p-3.5">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <Badge tone="outline">{titleCase(expense.category)}</Badge>
                      <span className="text-[10.5px] text-faint">{formatDate(expense.incurred_on)}</span>
                    </div>
                    <p className="mt-1 text-[13.5px] font-medium text-ink">{expense.title}</p>
                    <p className="text-[12px] text-muted">
                      Paid by {expense.payer?.display_name || "member"} · {expense.participants.length} participant(s)
                    </p>
                    {expense.notes ? <p className="mt-0.5 text-[12px] text-faint">{expense.notes}</p> : null}
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="font-mono text-[14px] text-ink">{formatMoney(expense.amount, expense.currency)}</span>
                    <button
                      type="button"
                      onClick={() => removeExpense.mutate(expense.id)}
                      className="text-faint hover:text-rose"
                      aria-label="Remove expense"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                </div>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {expense.participants.map((participant) => (
                    <Badge key={participant.id} tone="neutral">
                      {participant.user?.display_name || participant.guest_name || "Guest"}
                      {" · "}
                      {formatMoney(participant.share_amount, expense.currency)}
                    </Badge>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      <Modal open={open} onClose={() => setOpen(false)} title="Add expense" wide>
        <form
          className="space-y-3"
          onSubmit={(event) => {
            event.preventDefault();
            createExpense.mutate();
          }}
        >
          <Field label="Title">
            <Input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Dinner at the harbour" />
          </Field>
          <div className="grid gap-3 sm:grid-cols-3">
            <Field label="Amount">
              <Input
                type="number"
                min="0"
                step="0.01"
                value={amount}
                onChange={(event) => setAmount(event.target.value)}
                placeholder="0.00"
              />
            </Field>
            <Field label="Category">
              <Select value={category} onChange={(event) => setCategory(event.target.value)}>
                {CATEGORIES.map((entry) => (
                  <option key={entry} value={entry}>
                    {titleCase(entry)}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Date">
              <Input type="date" value={incurredOn} onChange={(event) => setIncurredOn(event.target.value)} />
            </Field>
          </div>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Paid by">
              <Select value={paidBy} onChange={(event) => setPaidBy(event.target.value)}>
                <option value="">Me</option>
                {people.map((member) => (
                  <option key={member.id} value={member.user?.id || member.id}>
                    {member.display_name}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Split">
              <Select value={split} onChange={(event) => setSplit(event.target.value)}>
                {SPLITS.map((entry) => (
                  <option key={entry.value} value={entry.value}>
                    {entry.label}
                  </option>
                ))}
              </Select>
            </Field>
          </div>

          <div className="space-y-1.5">
            <p className="text-[13px] font-medium text-ink">Participants</p>
            <div className="space-y-1.5">
              {draft.map((entry, index) => {
                const member = members.data?.items.find(
                  (item) => (item.user?.id || item.id) === entry.userId,
                );
                return (
                  <div
                    key={entry.userId}
                    className="flex flex-wrap items-center gap-2 rounded-xl border border-line bg-surface px-2.5 py-1.5"
                  >
                    <label className="flex flex-1 items-center gap-2 text-[12.5px] text-ink">
                      <input
                        type="checkbox"
                        checked={entry.included}
                        onChange={(event) =>
                          setDraft((current) =>
                            current.map((item, itemIndex) =>
                              itemIndex === index ? { ...item, included: event.target.checked } : item,
                            ),
                          )
                        }
                      />
                      {member?.display_name || "Member"}
                    </label>
                    {split === "weights" && entry.included ? (
                      <Input
                        type="number"
                        min="0.1"
                        step="0.1"
                        value={entry.weight}
                        aria-label={`Split weight for ${member?.display_name || "member"}`}
                        onChange={(event) =>
                          setDraft((current) =>
                            current.map((item, itemIndex) =>
                              itemIndex === index ? { ...item, weight: event.target.value } : item,
                            ),
                          )
                        }
                        className="h-8 w-20"
                      />
                    ) : null}
                    {split === "custom" && entry.included ? (
                      <Input
                        type="number"
                        min="0"
                        step="0.01"
                        value={entry.share}
                        aria-label={`Custom share for ${member?.display_name || "member"}`}
                        onChange={(event) =>
                          setDraft((current) =>
                            current.map((item, itemIndex) =>
                              itemIndex === index ? { ...item, share: event.target.value } : item,
                            ),
                          )
                        }
                        className="h-8 w-24"
                        placeholder="0.00"
                      />
                    ) : null}
                  </div>
                );
              })}
            </div>
            {split === "custom" ? (
              <p
                className={cn(
                  "text-[12px]",
                  Math.abs(customTotal - Number(amount || 0)) > 0.01 ? "text-rose" : "text-jade",
                )}
              >
                Custom shares total {formatMoney(customTotal, currency)} of {formatMoney(Number(amount || 0), currency)}
              </p>
            ) : null}
          </div>

          <Field label="Notes" hint="Optional">
            <Textarea value={notes} onChange={(event) => setNotes(event.target.value)} />
          </Field>

          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" loading={createExpense.isPending} disabled={!title || !amount}>
              <Receipt size={14} /> Add expense
            </Button>
          </div>
        </form>
      </Modal>
    </div>
  );
}
