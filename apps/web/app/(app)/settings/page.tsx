"use client";

import { Download, Lock, ShieldAlert, Trash2, UserX } from "lucide-react";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";

import {
  Badge,
  Button,
  Card,
  ErrorState,
  Field,
  Input,
  Modal,
  PageHeader,
  PageSkeleton,
  SectionTitle,
  Toggle,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import { useAuth, useTheme, useToasts } from "@/lib/store";
import { errorMessage } from "@/lib/utils";

const CONSENT_COPY: Record<string, { label: string; detail: string }> = {
  personalization: {
    label: "Personalisation",
    detail: "Use your Journey DNA and feedback to shape recommendations.",
  },
  analytics: {
    label: "Product analytics",
    detail: "Aggregate usage signals to improve SAFAR. Never sold or used for ads.",
  },
  location: {
    label: "Location sharing",
    detail: "Allow precise location for nearby suggestions. Never publicly exposed.",
  },
  marketing: {
    label: "Product updates",
    detail: "Occasional feature emails. Independent from using the planner.",
  },
};

type BlockItem = { user: { id: string; display_name: string }; created_at: string };

export default function SettingsPage() {
  const me = useMe();
  const router = useRouter();
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);
  const logout = useAuth((state) => state.logout);
  const theme = useTheme((state) => state.theme);
  const setTheme = useTheme((state) => state.setTheme);
  const [consents, setConsents] = useState<Record<string, boolean>>({});
  const [saving, setSaving] = useState(false);
  const [blocks, setBlocks] = useState<BlockItem[]>([]);
  const [blockId, setBlockId] = useState("");
  const [deleting, setDeleting] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleteConfirm, setDeleteConfirm] = useState("");
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!me.data || ready) return;
    setConsents({
      personalization: me.data.consents?.personalization?.granted ?? false,
      analytics: me.data.consents?.analytics?.granted ?? false,
      location: me.data.consents?.location?.granted ?? false,
      marketing: me.data.consents?.marketing?.granted ?? false,
    });
    setReady(true);
  }, [me.data, ready]);

  const loadBlocks = useCallback(async () => {
    try {
      const result = await api<{ items: BlockItem[] }>("/api/users/me/blocks");
      setBlocks(result.items);
    } catch {
      /* non-critical */
    }
  }, []);

  useEffect(() => {
    loadBlocks();
  }, [loadBlocks]);

  if (me.isLoading || !ready) return <PageSkeleton />;
  if (me.error || !me.data) return <ErrorState error={me.error} retry={() => me.refetch()} />;

  const saveConsents = async () => {
    setSaving(true);
    try {
      await api("/api/users/me/consents", { method: "PUT", body: { consents } });
      await queryClient.invalidateQueries({ queryKey: ["me"] });
      push("Consent saved", "Each purpose is recorded with a policy version.", "success");
    } catch (error) {
      push("Could not save consent", errorMessage(error), "error");
    } finally {
      setSaving(false);
    }
  };

  const exportData = async () => {
    try {
      const data = await api<Record<string, unknown>>("/api/users/me/export");
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = `safar-export-${new Date().toISOString().slice(0, 10)}.json`;
      anchor.click();
      URL.revokeObjectURL(url);
      push("Export downloaded", "Private information about other members is excluded.", "success");
    } catch (error) {
      push("Export failed", errorMessage(error), "error");
    }
  };

  const blockUser = async () => {
    if (!blockId.trim()) return;
    try {
      await api(`/api/users/me/blocks/${blockId.trim()}`, { method: "POST" });
      setBlockId("");
      await loadBlocks();
      push("Traveller blocked", "They will not appear in discovery or connection suggestions.", "success");
    } catch (error) {
      push("Could not block", errorMessage(error), "error");
    }
  };

  const unblock = async (id: string) => {
    try {
      await api(`/api/users/me/blocks/${id}`, { method: "DELETE" });
      await loadBlocks();
      push("Unblocked", undefined, "success");
    } catch (error) {
      push("Could not unblock", errorMessage(error), "error");
    }
  };

  const deleteAccount = async () => {
    if (deleteConfirm !== "DELETE") return;
    setDeleting(true);
    try {
      await api("/api/users/me", { method: "DELETE" });
      logout();
      queryClient.clear();
      push("Account anonymised", "Your media is hidden and personal fields are cleared.", "success");
      router.push("/");
    } catch (error) {
      push("Could not delete account", errorMessage(error), "error");
    } finally {
      setDeleting(false);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Settings"
        title="Privacy, consent and control"
        description="Your data is yours. Each purpose has its own switch, and exports do not reveal other members' private information."
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <SectionTitle
            title="Consent"
            hint={`Policy version ${me.data.policy_version}`}
            action={<Badge tone="jade">Recorded</Badge>}
          />
          <div className="divide-y divide-line">
            {Object.entries(CONSENT_COPY).map(([key, copy]) => (
              <Toggle
                key={key}
                checked={Boolean(consents[key])}
                onChange={(value) => setConsents({ ...consents, [key]: value })}
                label={copy.label}
                description={copy.detail}
              />
            ))}
          </div>
          <Button onClick={saveConsents} loading={saving} className="mt-4 w-full">
            Save consent
          </Button>
          <p className="mt-3 flex gap-2 text-[12px] leading-5 text-faint">
            <Lock size={13} className="mt-0.5 shrink-0" />
            Declining personalisation keeps the planner usable. Only feedback you consent to can
            update Journey DNA.
          </p>
        </Card>

        <div className="space-y-4">
          <Card>
            <SectionTitle title="Appearance" hint="Saved on this device" />
            <div className="grid grid-cols-2 gap-2">
              {(["light", "dark"] as const).map((option) => (
                <button
                  key={option}
                  type="button"
                  aria-pressed={theme === option}
                  onClick={() => setTheme(option)}
                  className={`rounded-2xl border p-4 text-left text-[13px] capitalize transition-colors ${
                    theme === option
                      ? "border-ember bg-ember-soft/60 text-ember"
                      : "border-line bg-surface text-muted hover:text-ink"
                  }`}
                >
                  {option} theme
                  <span className="mt-1 block text-[12px] opacity-70">
                    {option === "light" ? "Warm paper" : "Ink and ember"}
                  </span>
                </button>
              ))}
            </div>
          </Card>

          <Card>
            <SectionTitle title="Data export" hint="Machine-readable JSON" />
            <p className="text-[12.5px] leading-6 text-muted">
              Download your profile, consents, trips, memories, expenses paid and consented
              activity feedback. Other members&apos; private details are excluded.
            </p>
            <Button variant="secondary" onClick={exportData} className="mt-3">
              <Download size={15} /> Download my data
            </Button>
          </Card>
        </div>
      </div>

      <Card>
        <SectionTitle title="Blocked travellers" hint="Blocks apply to discovery and connection requests" />
        <div className="flex flex-col gap-2 sm:flex-row">
          <Input
            value={blockId}
            onChange={(event) => setBlockId(event.target.value)}
            placeholder="Traveller user ID"
            className="sm:flex-1"
          />
          <Button variant="secondary" onClick={blockUser}>
            <UserX size={15} /> Block
          </Button>
        </div>
        <ul className="mt-4 space-y-2">
          {blocks.length === 0 ? (
            <li className="rounded-xl border border-dashed border-line px-3 py-4 text-[12px] text-faint">
              No blocked travellers.
            </li>
          ) : (
            blocks.map((item) => (
              <li
                key={item.user.id}
                className="flex items-center justify-between gap-3 rounded-xl border border-line bg-raised/40 px-3.5 py-2.5"
              >
                <div>
                  <p className="text-[13px] font-medium">{item.user.display_name}</p>
                  <p className="font-mono text-[10px] text-faint">{item.user.id}</p>
                </div>
                <Button size="sm" variant="ghost" onClick={() => unblock(item.user.id)}>
                  Unblock
                </Button>
              </li>
            ))
          )}
        </ul>
      </Card>

      <Card className="border-rose/20">
        <SectionTitle title="Danger zone" hint="Destructive and irreversible in this workspace" />
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="max-w-lg">
            <p className="text-[13px] font-medium">Delete and anonymise my account</p>
            <p className="mt-1 text-[12px] leading-5 text-muted">
              Personal profile fields are cleared, memories are hidden, blocks are removed and the
              account is anonymised. Administrator accounts must transfer ownership first.
            </p>
          </div>
          <Button variant="danger" onClick={() => setDeleteOpen(true)} disabled={me.data.user.is_admin}>
            <Trash2 size={15} /> Delete account
          </Button>
        </div>
        {me.data.user.is_admin ? (
          <p className="mt-3 flex items-center gap-2 text-[12px] text-rose">
            <ShieldAlert size={14} /> This account is an administrator and cannot be deleted until
            ownership is transferred.
          </p>
        ) : null}
      </Card>

      <Modal open={deleteOpen} onClose={() => setDeleteOpen(false)} title="Delete your account?">
        <div className="space-y-4">
          <p className="text-[13px] leading-6 text-muted">
            This anonymises your account and hides your media. It cannot be undone. Type{" "}
            <span className="font-mono text-ink">DELETE</span> to confirm.
          </p>
          <Field label="Type DELETE">
            <Input value={deleteConfirm} onChange={(event) => setDeleteConfirm(event.target.value)} />
          </Field>
          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={() => setDeleteOpen(false)}>
              Cancel
            </Button>
            <Button
              variant="danger"
              onClick={deleteAccount}
              loading={deleting}
              disabled={deleteConfirm !== "DELETE"}
            >
              Delete account
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
