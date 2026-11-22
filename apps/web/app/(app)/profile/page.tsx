"use client";

import { Save, Sparkles, UserRound } from "lucide-react";
import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";

import {
  Badge,
  Button,
  Card,
  ErrorState,
  Field,
  Input,
  PageHeader,
  PageSkeleton,
  Select,
  Textarea,
  Toggle,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { DNA_LABELS, cn, errorMessage } from "@/lib/utils";

const ACCESS_NEEDS = [
  "Step-free access",
  "Wheelchair user",
  "Limited walking",
  "Low vision",
  "Hearing support",
  "Quiet environments",
];
const DIETARY = ["Vegetarian", "Vegan", "Halal", "Kosher", "Gluten-free", "Nut allergy"];
const LANGUAGES = ["English", "Japanese", "Portuguese", "Spanish", "French", "German", "Hindi"];

function Chip({
  active,
  children,
  onClick,
}: {
  active: boolean;
  children: React.ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-pressed={active}
      onClick={onClick}
      className={cn(
        "rounded-full border px-3 py-1.5 text-[12px] transition-colors",
        active
          ? "border-ember bg-ember-soft text-ember"
          : "border-line bg-surface text-muted hover:border-ink/30 hover:text-ink",
      )}
    >
      {children}
    </button>
  );
}

export default function ProfilePage() {
  const me = useMe();
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);
  const [ready, setReady] = useState(false);
  const [saving, setSaving] = useState(false);
  const [savingDna, setSavingDna] = useState(false);
  const [savingAccount, setSavingAccount] = useState(false);
  const [displayName, setDisplayName] = useState("");
  const [quietMode, setQuietMode] = useState(false);
  const [locale, setLocale] = useState("en");
  const [timezone, setTimezone] = useState("UTC");
  const [dna, setDna] = useState<Record<string, number>>({});
  const [form, setForm] = useState({
    headline: "",
    bio: "",
    home_city: "",
    travel_pace: "balanced",
    budget_level: "moderate",
    budget_limit: "",
    interests: [] as string[],
    accessibility_needs: [] as string[],
    dietary: [] as string[],
    languages: ["English"],
    public_profile: false,
    allow_discovery: false,
    location_sharing: false,
  });

  useEffect(() => {
    if (!me.data || ready) return;
    const profile = me.data.profile;
    setForm({
      headline: profile.headline || "",
      bio: profile.bio || "",
      home_city: profile.home_city || "",
      travel_pace: profile.travel_pace || "balanced",
      budget_level: profile.budget_level || "moderate",
      budget_limit: profile.budget_limit ? String(profile.budget_limit) : "",
      interests: profile.interests || [],
      accessibility_needs: profile.accessibility_needs || [],
      dietary: profile.dietary || [],
      languages: profile.languages?.length ? profile.languages : ["English"],
      public_profile: profile.public_profile,
      allow_discovery: profile.allow_discovery,
      location_sharing: profile.location_sharing,
    });
    setDisplayName(me.data.user.display_name);
    setQuietMode(me.data.user.quiet_mode ?? false);
    setLocale(me.data.user.locale || "en");
    setTimezone(me.data.user.timezone || "UTC");
    setDna({ ...(me.data.dna.scores || {}) });
    setReady(true);
  }, [me.data, ready]);

  if (me.isLoading || !ready) return <PageSkeleton />;
  if (me.error || !me.data) return <ErrorState error={me.error} retry={() => me.refetch()} />;

  const toggle = (key: keyof typeof form, value: string) => {
    setForm((current) => {
      const list = current[key] as string[];
      return {
        ...current,
        [key]: list.includes(value) ? list.filter((item) => item !== value) : [...list, value],
      };
    });
  };

  const saveProfile = async () => {
    setSaving(true);
    try {
      await api("/api/users/me/profile", {
        method: "PATCH",
        body: {
          headline: form.headline || null,
          bio: form.bio || null,
          home_city: form.home_city || null,
          travel_pace: form.travel_pace,
          budget_level: form.budget_level,
          budget_limit: form.budget_limit === "" ? null : Number(form.budget_limit),
          interests: form.interests,
          accessibility_needs: form.accessibility_needs,
          dietary: form.dietary,
          languages: form.languages,
          public_profile: form.public_profile,
          allow_discovery: form.allow_discovery,
          location_sharing: form.location_sharing,
        },
      });
      await queryClient.invalidateQueries({ queryKey: ["me"] });
      push("Profile saved", "Your group sees only what you allow.", "success");
    } catch (error) {
      push("Could not save profile", errorMessage(error), "error");
    } finally {
      setSaving(false);
    }
  };

  const saveDna = async () => {
    setSavingDna(true);
    try {
      await api("/api/users/me/dna", { method: "PUT", body: { scores: dna } });
      await queryClient.invalidateQueries({ queryKey: ["me"] });
      push("Journey DNA updated", "New recommendations will use these signals.", "success");
    } catch (error) {
      push("Could not update DNA", errorMessage(error), "error");
    } finally {
      setSavingDna(false);
    }
  };

  const saveAccount = async () => {
    setSavingAccount(true);
    try {
      await api("/api/users/me/settings", {
        method: "PATCH",
        body: { display_name: displayName, quiet_mode: quietMode, locale, timezone },
      });
      await queryClient.invalidateQueries({ queryKey: ["me"] });
      push("Account settings saved", undefined, "success");
    } catch (error) {
      push("Could not save account settings", errorMessage(error), "error");
    } finally {
      setSavingAccount(false);
    }
  };

  const dimensions = me.data.dna.dimensions || Object.keys(DNA_LABELS);

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Your travel self"
        title="Journey DNA"
        description="Editable signals that shape recommendations. Not a permanent personality label, and never shown to the group as a score."
        actions={
          <Button onClick={saveDna} loading={savingDna}>
            <Save size={15} /> Save DNA
          </Button>
        }
      />

      <Card>
        <div className="flex items-center justify-between">
          <div>
            <p className="text-[13px] font-medium">Signal strength</p>
            <p className="mt-0.5 text-[12px] text-faint">
              Source: {me.data.dna.source || "explicit"} · feedback only applies with consent.
            </p>
          </div>
          <Badge tone="ember">
            <Sparkles size={10} /> 0–10
          </Badge>
        </div>
        <div className="mt-4 grid gap-x-8 gap-y-5 sm:grid-cols-2">
          {dimensions.map((dimension) => (
            <label key={dimension} className="block">
              <span className="flex items-baseline justify-between text-[12.5px]">
                <span className="font-medium">{DNA_LABELS[dimension] || dimension}</span>
                <span className="font-mono text-[12px] text-faint">{dna[dimension] ?? 5}</span>
              </span>
              <input
                type="range"
                min={0}
                max={10}
                step={1}
                value={dna[dimension] ?? 5}
                onChange={(event) => setDna({ ...dna, [dimension]: Number(event.target.value) })}
                className="mt-2 w-full accent-[rgb(var(--ember))]"
              />
            </label>
          ))}
        </div>
      </Card>

      <div className="grid gap-4 lg:grid-cols-[1.3fr_0.7fr]">
        <Card className="space-y-5">
          <div className="flex items-center gap-2">
            <UserRound size={16} className="text-ember" />
            <h2 className="text-xl">Travel profile</h2>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Home city">
              <Input value={form.home_city} onChange={(event) => setForm({ ...form, home_city: event.target.value })} />
            </Field>
            <Field label="Travel pace">
              <Select value={form.travel_pace} onChange={(event) => setForm({ ...form, travel_pace: event.target.value })}>
                <option value="slow">Slow</option>
                <option value="balanced">Balanced</option>
                <option value="fast">Fast</option>
              </Select>
            </Field>
            <Field label="Budget comfort">
              <Select value={form.budget_level} onChange={(event) => setForm({ ...form, budget_level: event.target.value })}>
                <option value="budget">Budget</option>
                <option value="moderate">Moderate</option>
                <option value="comfort">Comfort</option>
                <option value="luxury">Luxury</option>
              </Select>
            </Field>
            <Field label="Private budget ceiling" hint="Used by the engine; never shown to members.">
              <Input
                type="number"
                min={0}
                value={form.budget_limit}
                onChange={(event) => setForm({ ...form, budget_limit: event.target.value })}
                placeholder="Optional"
              />
            </Field>
          </div>
          <Field label="Headline">
            <Input
              maxLength={160}
              value={form.headline}
              onChange={(event) => setForm({ ...form, headline: event.target.value })}
            />
          </Field>
          <Field label="Bio">
            <Textarea value={form.bio} onChange={(event) => setForm({ ...form, bio: event.target.value })} />
          </Field>

          <div>
            <p className="text-[13px] font-medium">Interests</p>
            <div className="mt-2 flex flex-wrap gap-2">
              {Object.keys(DNA_LABELS).map((interest) => (
                <Chip
                  key={interest}
                  active={form.interests.includes(interest)}
                  onClick={() => toggle("interests", interest)}
                >
                  {DNA_LABELS[interest]}
                </Chip>
              ))}
            </div>
          </div>

          <div>
            <p className="text-[13px] font-medium">Accessibility needs</p>
            <p className="mt-0.5 text-[12px] text-faint">Applied as hard constraints in every engine run.</p>
            <div className="mt-2 flex flex-wrap gap-2">
              {ACCESS_NEEDS.map((need) => (
                <Chip
                  key={need}
                  active={form.accessibility_needs.includes(need)}
                  onClick={() => toggle("accessibility_needs", need)}
                >
                  {need}
                </Chip>
              ))}
            </div>
          </div>

          <div className="grid gap-5 sm:grid-cols-2">
            <div>
              <p className="text-[13px] font-medium">Dietary</p>
              <div className="mt-2 flex flex-wrap gap-2">
                {DIETARY.map((item) => (
                  <Chip key={item} active={form.dietary.includes(item)} onClick={() => toggle("dietary", item)}>
                    {item}
                  </Chip>
                ))}
              </div>
            </div>
            <div>
              <p className="text-[13px] font-medium">Languages</p>
              <div className="mt-2 flex flex-wrap gap-2">
                {LANGUAGES.map((item) => (
                  <Chip key={item} active={form.languages.includes(item)} onClick={() => toggle("languages", item)}>
                    {item}
                  </Chip>
                ))}
              </div>
            </div>
          </div>

          <div className="flex justify-end">
            <Button onClick={saveProfile} loading={saving}>
              <Save size={15} /> Save profile
            </Button>
          </div>
        </Card>

        <div className="space-y-4">
          <Card>
            <h2 className="text-xl">Account</h2>
            <div className="mt-4 space-y-4">
              <Field label="Display name">
                <Input value={displayName} onChange={(event) => setDisplayName(event.target.value)} />
              </Field>
              <Field label="Locale">
                <Select value={locale} onChange={(event) => setLocale(event.target.value)}>
                  <option value="en">English</option>
                  <option value="pt">Português</option>
                  <option value="ja">日本語</option>
                  <option value="es">Español</option>
                  <option value="fr">Français</option>
                </Select>
              </Field>
              <Field label="Timezone">
                <Input value={timezone} onChange={(event) => setTimezone(event.target.value)} placeholder="Europe/Lisbon" />
              </Field>
              <Toggle
                checked={quietMode}
                onChange={setQuietMode}
                label="Quiet mode"
                description="Only essential notifications. The next action still appears when you open a trip."
              />
            </div>
            <Button onClick={saveAccount} loading={savingAccount} className="mt-4 w-full">
              <Save size={15} /> Save account
            </Button>
          </Card>

          <Card>
            <h2 className="text-xl">Who can see what</h2>
            <div className="mt-2 divide-y divide-line">
              <Toggle
                checked={form.public_profile}
                onChange={(value) => setForm({ ...form, public_profile: value })}
                label="Public profile"
                description="Headline, home city and interests with other travellers."
              />
              <Toggle
                checked={form.allow_discovery}
                onChange={(value) => setForm({ ...form, allow_discovery: value })}
                label="Traveller discovery"
                description="Opt in to compatible traveller suggestions and connection requests."
              />
              <Toggle
                checked={form.location_sharing}
                onChange={(value) => setForm({ ...form, location_sharing: value })}
                label="Precise location"
                description="Only for nearby suggestions. Never exposed publicly."
              />
            </div>
            <p className="mt-3 text-[12px] leading-5 text-faint">
              Changing discovery settings does not retroactively reveal any past location.
            </p>
          </Card>
        </div>
      </div>
    </div>
  );
}
