"use client";

import { Check, ChevronLeft, ChevronRight, Sparkles } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";

import {
  Badge,
  Button,
  Card,
  ErrorState,
  Field,
  Input,
  PageSkeleton,
  Progress,
  Select,
  Textarea,
  Toggle,
} from "@/components/ui";
import { api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import { useToasts } from "@/lib/store";
import { DNA_LABELS, cn, errorMessage } from "@/lib/utils";

const INTERESTS = Object.keys(DNA_LABELS);
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

const CONSENT_COPY: Record<string, { label: string; detail: string }> = {
  personalization: {
    label: "Personalisation",
    detail: "Use your Journey DNA and feedback to rank suggestions for you.",
  },
  analytics: {
    label: "Product analytics",
    detail: "Help improve SAFAR with aggregate usage signals. Never used for ads.",
  },
  location: {
    label: "Location sharing",
    detail: "Allow precise location for nearby suggestions. Off by default and never public.",
  },
  marketing: {
    label: "Product updates",
    detail: "Occasional emails about new SAFAR features. You can opt out any time.",
  },
};

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

export default function OnboardingPage() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const push = useToasts((state) => state.push);
  const me = useMe();
  const [step, setStep] = useState(0);
  const [saving, setSaving] = useState(false);
  const [ready, setReady] = useState(false);
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
  const [dna, setDna] = useState<Record<string, number>>({});
  const [consents, setConsents] = useState<Record<string, boolean>>({
    personalization: true,
    analytics: false,
    location: false,
    marketing: false,
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
      interests: profile.interests?.length ? profile.interests : [],
      accessibility_needs: profile.accessibility_needs || [],
      dietary: profile.dietary || [],
      languages: profile.languages?.length ? profile.languages : ["English"],
      public_profile: profile.public_profile,
      allow_discovery: profile.allow_discovery,
      location_sharing: profile.location_sharing,
    });
    setDna({ ...(me.data.dna.scores || {}) });
    setConsents({
      personalization: me.data.consents?.personalization?.granted ?? true,
      analytics: me.data.consents?.analytics?.granted ?? false,
      location: me.data.consents?.location?.granted ?? false,
      marketing: me.data.consents?.marketing?.granted ?? false,
    });
    setReady(true);
  }, [me.data, ready]);

  if (me.isLoading || !ready) return <PageSkeleton />;
  if (me.error) return <ErrorState error={me.error} retry={() => me.refetch()} />;

  const toggle = (key: keyof typeof form, value: string) => {
    setForm((current) => {
      const list = current[key] as string[];
      return {
        ...current,
        [key]: list.includes(value) ? list.filter((item) => item !== value) : [...list, value],
      };
    });
  };

  const finish = async () => {
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
      await api("/api/users/me/dna", {
        method: "PUT",
        body: { scores: dna },
      });
      await api("/api/users/me/consents", {
        method: "PUT",
        body: { consents },
      });
      await queryClient.invalidateQueries({ queryKey: ["me"] });
      push("Your travel profile is ready", "Journey DNA stays editable in your profile.", "success");
      router.push("/dashboard");
    } catch (error) {
      push("Could not save your profile", errorMessage(error), "error");
    } finally {
      setSaving(false);
    }
  };

  const steps = ["Travel style", "Journey DNA", "Consent"];
  const completeness = Math.round(((step + 1) / 3) * 100);
  const activeNeeds = form.accessibility_needs.length;

  return (
    <div className="mx-auto max-w-3xl">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">Onboarding</p>
          <h1 className="mt-1 text-4xl leading-tight">Make SAFAR useful</h1>
          <p className="mt-2 max-w-xl text-sm leading-6 text-muted">
            Three short steps. Everything here is editable and private by default.
          </p>
        </div>
        <Badge tone="outline">
          <Sparkles size={11} /> Private to you
        </Badge>
      </div>

      <div className="mt-6">
        <Progress value={completeness} tone="ember" />
        <div className="mt-2 flex justify-between text-[12px] text-faint">
          {steps.map((label, index) => (
            <span key={label} className={index <= step ? "text-ink" : ""}>
              {index + 1}. {label}
            </span>
          ))}
        </div>
      </div>

      <div className="mt-6">
        {step === 0 ? (
          <Card className="space-y-6">
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="Home city" hint="Optional — used for context, never published automatically.">
                <Input
                  value={form.home_city}
                  onChange={(event) => setForm({ ...form, home_city: event.target.value })}
                  placeholder="Lisbon"
                />
              </Field>
              <Field label="Travel pace">
                <Select
                  value={form.travel_pace}
                  onChange={(event) => setForm({ ...form, travel_pace: event.target.value })}
                >
                  <option value="slow">Slow — fewer stops, more depth</option>
                  <option value="balanced">Balanced</option>
                  <option value="fast">Fast — fit more in</option>
                </Select>
              </Field>
              <Field label="Budget comfort">
                <Select
                  value={form.budget_level}
                  onChange={(event) => setForm({ ...form, budget_level: event.target.value })}
                >
                  <option value="budget">Budget</option>
                  <option value="moderate">Moderate</option>
                  <option value="comfort">Comfort</option>
                  <option value="luxury">Luxury</option>
                </Select>
              </Field>
              <Field
                label="Per-person budget ceiling"
                hint="Private. The engine uses it without showing it to the group."
              >
                <Input
                  type="number"
                  min={0}
                  inputMode="decimal"
                  value={form.budget_limit}
                  onChange={(event) => setForm({ ...form, budget_limit: event.target.value })}
                  placeholder="Optional"
                />
              </Field>
            </div>

            <Field label="Headline" hint="One line your trip group can see.">
              <Input
                value={form.headline}
                onChange={(event) => setForm({ ...form, headline: event.target.value })}
                placeholder="Slow mornings, long walks, small museums"
                maxLength={160}
              />
            </Field>
            <Field label="About your travel style">
              <Textarea
                value={form.bio}
                onChange={(event) => setForm({ ...form, bio: event.target.value })}
                placeholder="What makes a trip work for you?"
              />
            </Field>

            <div>
              <p className="text-[13px] font-medium">Interests</p>
              <p className="mt-0.5 text-xs text-faint">
                These seed your Journey DNA. You can tune every score next.
              </p>
              <div className="mt-3 flex flex-wrap gap-2">
                {INTERESTS.map((interest) => (
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
              <p className="mt-0.5 text-xs text-faint">
                Used as hard constraints. Only the label you choose is shared; details stay private.
              </p>
              <div className="mt-3 flex flex-wrap gap-2">
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
                    <Chip
                      key={item}
                      active={form.dietary.includes(item)}
                      onClick={() => toggle("dietary", item)}
                    >
                      {item}
                    </Chip>
                  ))}
                </div>
              </div>
              <div>
                <p className="text-[13px] font-medium">Languages</p>
                <div className="mt-2 flex flex-wrap gap-2">
                  {LANGUAGES.map((item) => (
                    <Chip
                      key={item}
                      active={form.languages.includes(item)}
                      onClick={() => toggle("languages", item)}
                    >
                      {item}
                    </Chip>
                  ))}
                </div>
              </div>
            </div>

            {activeNeeds > 0 ? (
              <div className="rounded-2xl border border-jade/20 bg-jade-soft/40 px-4 py-3 text-[12px] leading-5 text-jade">
                {activeNeeds} access need{activeNeeds === 1 ? "" : "s"} will be applied before
                ranking. They are never traded for a better group average.
              </div>
            ) : null}
          </Card>
        ) : null}

        {step === 1 ? (
          <Card>
            <p className="text-[13px] leading-6 text-muted">
              Journey DNA is a set of 0–10 signals, not a personality test. Move a slider to make a
              preference explicit. Feedback can refine it later — only when you consent.
            </p>
            <div className="mt-5 grid gap-x-8 gap-y-5 sm:grid-cols-2">
              {INTERESTS.map((dimension) => (
                <label key={dimension} className="block">
                  <span className="flex items-baseline justify-between text-[12.5px]">
                    <span className="font-medium">{DNA_LABELS[dimension]}</span>
                    <span className="font-mono text-[12px] text-faint">{dna[dimension] ?? 5}</span>
                  </span>
                  <input
                    type="range"
                    min={0}
                    max={10}
                    step={1}
                    value={dna[dimension] ?? 5}
                    onChange={(event) =>
                      setDna({ ...dna, [dimension]: Number(event.target.value) })
                    }
                    className="mt-2 w-full accent-[rgb(var(--ember))]"
                  />
                </label>
              ))}
            </div>
          </Card>
        ) : null}

        {step === 2 ? (
          <div className="space-y-4">
            <Card>
              <h2 className="text-xl">Who can see what</h2>
              <p className="mt-1 text-[12.5px] leading-5 text-muted">
                Private is the default. Discovery is opt-in and reciprocal.
              </p>
              <div className="mt-3 divide-y divide-line">
                <Toggle
                  checked={form.public_profile}
                  onChange={(value) => setForm({ ...form, public_profile: value })}
                  label="Public profile"
                  description="Share your headline, home city and interests with other travellers."
                />
                <Toggle
                  checked={form.allow_discovery}
                  onChange={(value) => setForm({ ...form, allow_discovery: value })}
                  label="Traveller discovery"
                  description="See compatible travellers and allow connection requests. Requires a public profile."
                />
                <Toggle
                  checked={form.location_sharing}
                  onChange={(value) => setForm({ ...form, location_sharing: value })}
                  label="Precise location"
                  description="Only used for nearby suggestions. Exact live locations are never publicly exposed."
                />
              </div>
            </Card>

            <Card>
              <h2 className="text-xl">Consent, separately</h2>
              <p className="mt-1 text-[12.5px] leading-5 text-muted">
                Each purpose needs its own answer. You can change these later in Settings.
              </p>
              <div className="mt-3 divide-y divide-line">
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
              <p className="mt-3 rounded-xl border border-line bg-raised/60 px-3 py-2 text-[12px] leading-5 text-muted">
                Terms were accepted at sign-up and recorded with a policy version. Declining
                personalisation does not disable the core planner.
              </p>
            </Card>
          </div>
        ) : null}
      </div>

      <div className="mt-6 flex items-center justify-between gap-3">
        <Button
          variant="ghost"
          onClick={() => (step === 0 ? router.push("/dashboard") : setStep(step - 1))}
        >
          <ChevronLeft size={15} /> {step === 0 ? "Skip for now" : "Back"}
        </Button>
        {step < 2 ? (
          <Button onClick={() => setStep(step + 1)}>
            Continue <ChevronRight size={15} />
          </Button>
        ) : (
          <Button onClick={finish} loading={saving}>
            <Check size={15} /> Finish setup
          </Button>
        )}
      </div>
    </div>
  );
}
