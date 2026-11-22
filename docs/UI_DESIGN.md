# SAFAR — UI design system

Status: implemented in `apps/web` (Phase 6, 2026-11-19). Every token below is the
value actually compiled into the application; the audit evidence is in
`docs/AUDIT.md` §16 and the visual references are in `docs/screenshots/`.

## 1. Principles

1. **Editorial, not dashboard.** Warm paper, serif display type, generous
   whitespace and ruled metadata. Data density is never used as a substitute
   for hierarchy.
2. **One primary action per surface.** Every screen answers “what next?” before
   it lists everything else.
3. **Explain before asserting.** Rankings, prices and confidence are labelled
   with their source. Estimates are called estimates; community signals are
   called community signals.
4. **Privacy is visible.** Private-to-you inputs and private memories are marked
   in the interface, not only enforced in the API.
5. **Motion is feedback, not decoration.** Transitions stay between 150–300 ms,
   never block input, and collapse under `prefers-reduced-motion`.
6. **Nothing is faked.** Empty, loading and error states reflect real request
   state; no placeholder cards stand in for unavailable data.

## 2. Foundations

### 2.1 Colour

Colour is defined as space-separated RGB channels in `app/globals.css` and
exposed through Tailwind as `rgb(var(--token) / <alpha-value>)`, so opacity
utilities work on every token.

| Token | Light | Dark | Use |
|---|---|---|---|
| `paper` | `246 241 231` | `18 17 14` | App background |
| `surface` | `255 253 248` | `27 25 21` | Cards, panels |
| `raised` | `250 246 238` | `36 33 27` | Nested/alternating surfaces |
| `ink` | `26 24 18` | `245 239 227` | Primary text, primary button |
| `muted` | `92 86 74` | `176 168 154` | Secondary text |
| `faint` | `115 107 92` | `148 140 126` | Tertiary metadata |
| `line` | `227 218 201` | `58 53 44` | Hairlines and borders |
| `ember` | `176 74 8` | `240 163 74` | Accent, focus ring, attention |
| `ember-soft` | `247 232 208` | `64 45 24` | Accent backgrounds |
| `jade` | `10 110 102` | `94 234 212` | Confirmed/healthy states |
| `jade-soft` | `212 237 231` | `18 52 47` | Confirmed backgrounds |
| `rose` | `176 26 26` | `248 113 113` | Destructive and errors only |

Measured contrast (WCAG 2.1, sRGB):

| Pair | Ratio | Result |
|---|---|---|
| ink on paper | 15.76 | AAA |
| muted on paper | 6.47 | AA |
| faint on paper | 4.68 | AA (normal text) |
| faint on raised | 4.89 | AA |
| ember on paper | 4.87 | AA |
| jade on paper | 5.43 | AA |
| rose on surface | 6.87 | AA |
| dark ink on dark paper | 16.49 | AAA |
| dark muted on dark paper | 8.01 | AAA |
| dark faint on dark paper | 5.67 | AA |

`--faint` was darkened from `124 116 101` (4.11:1 on `paper`) to `115 107 92`
after measuring it during Phase 6. Colour is never the only carrier of meaning:
status badges pair tone with a label and an icon, and destructive actions pair
rose with explicit verbs.

The only decorative colour is the fixed two-radial background wash on
`body::before` at 5–7% alpha. There are no gradients on controls, no
glassmorphism beyond the modal scrim (`backdrop-blur-[3px]`) and the sticky day
strip (`backdrop-blur-sm`).

### 2.2 Typography

| Role | Family | Size / leading | Notes |
|---|---|---|---|
| Display heading | `Iowan Old Style` stack (`font-display`) | `h1` 1.9 → 2.4rem, `h2` 1.25rem, `h3` 1.125rem | weight 500, tracking −0.018em, `text-wrap: balance` |
| Body | system sans (`font-sans`) | 14–15px / 1.5–1.75 | `prose-editorial` is 15px/1.75, max 68ch |
| Metadata | sans | 11.5–12.5px | always paired with `muted`/`faint`, tabular numbers via `.num` |
| Eyebrow | sans | 12px uppercase, tracking 0.14em (`tracking-editorial`) | one per page, above the title |
| Numerals | sans/mono | `font-variant-numeric: tabular-nums` (`.num`) | stats, prices, times |

Guidelines:

- One `h1`/page-level `h2` per screen, via `PageHeader`. Trip screens use
  `PageHeader as="h2"` because the trip title is the `h1`.
- Never shrink text below 11.5px; 10px is reserved for the day-strip
  weekday label inside a control that already has a larger label.
- Mobile form controls are forced to 16px to prevent iOS zoom-out
  (`@media (max-width: 640px)`).

### 2.3 Spacing and layout

- Base rhythm: 4px; page sections use `space-y-6` to `space-y-10`.
- Page container: `mx-auto max-w-wide px-4 py-6 sm:px-6 lg:px-10 lg:py-10`
  (`max-w-wide` = 82rem).
- App shell: fixed 16rem (`pl-64`) sidebar at `lg`; bottom tab bar below `lg`.
- Cards: `p-5 sm:p-6`; nested groups `p-4`; stacks inside cards `space-y-3` to
  `space-y-5`.
- Prose measures: `max-w-prose` (68ch) for page descriptions, `62ch` for
  reading columns.

### 2.4 Radius, elevation and texture

| Token | Value | Use |
|---|---|---|
| `rounded-full` | pill | buttons, badges, chips, filter controls |
| `rounded-3xl` | 1.5rem | cards, shells |
| `rounded-4xl` | 2rem | hero/feature panels |
| `rounded-2xl` | 1rem | nested panels, map frames |
| `rounded-xl` | 0.75rem | inline fields, list rows |
| `shadow-card` | hairline + soft 30px shadow | default card |
| `shadow-float` | 50px ambient shadow | raised overlays |
| `shadow-lift` | 70px ambient shadow | hovered cards, modals |
| `.surface-grid` | 48px line grid | only for empty/technical areas |
| `.skeleton` | shimmer gradient | loading placeholders |

Borders are 1px `line`. Elevation is used sparingly: cards rest flat, rise on
hover (`card-interactive`, −2px translate), modals use `shadow-lift`.

### 2.5 Motion

| Context | Duration | Easing |
|---|---|---|
| Colour/border hover | 200 ms | `ease-editorial` = `cubic-bezier(0.22, 1, 0.36, 1)` |
| Card lift | 300 ms | `ease-editorial` |
| Modal scrim/panel | 200/260 ms | framer-motion, `[0.22, 1, 0.36, 1]` |
| Toasts | 180–220 ms | framer-motion |
| Skeleton shimmer | 1.6 s loop | linear |

Rules: transforms never exceed 32px travel; nothing animates that the user has
to wait for; `prefers-reduced-motion: reduce` collapses all durations to 0.001ms
globally and framer-motion components pass `useReducedMotion()` to skip initial
transforms.

## 3. Component library

All primitives live in `apps/web/components/ui.tsx`. Screens compose these; they
do not restyle raw HTML.

| Component | API highlights | Accessibility contract |
|---|---|---|
| `Button` | `variant` primary/secondary/ghost/subtle/danger, `size` sm/md/lg, `loading` | `aria-busy` while loading, real `disabled`, spinner is `aria-hidden` |
| `LinkButton` | same variants, wraps `next/link` | inherits global `:focus-visible` |
| `IconButton` | required `label` | `aria-label` + `title`, 36px hit area |
| `Card` | `as` div/section/article/li, `interactive` | semantic element is caller’s choice |
| `Badge` | tone neutral/ember/jade/rose/outline | text always present; no colour-only status |
| `Input` / `Textarea` / `Select` | forwarded props | bordered, 16px on mobile, focus ring from global rule |
| `Field` | `label`, `hint`, `error`, `htmlFor` | renders `<label>`; errors as `role="alert"` |
| `Avatar` / `AvatarStack` | initials fallback, `+N` overflow | decorative images when a name is adjacent |
| `Progress` | determinate value | `role="progressbar"` with value attributes |
| `PageHeader` | `eyebrow`, `title`, `description`, `actions`, `meta`, `size`, `as` | heading level chosen per screen |
| `SectionTitle` | `title`, `hint`, `action`, `level` | h2/h3 only; never skipped |
| `EmptyState` | `title`, `description`, `icon`, `action` | explains what is missing and the next step |
| `Skeleton` / `PageSkeleton` | layout-shaped placeholders | `aria-busy`, `aria-live="polite"` |
| `ErrorState` | `error`, `retry` | `role="alert"`, retry is a real refetch |
| `Stat` | label, value, hint | value uses tabular numerals |
| `MetaRow` | icon + label + value pairs | text labels are never icon-only |
| `SegmentedControl` | generic string value | `aria-pressed` on each option |
| `Modal` | `title`, `description`, `footer`, `wide` | `role="dialog"`, `aria-modal`, labelled/described, panel focused on open (synchronously), Tab trapped, Escape closes, scroll locked, focus restored |
| `Toggle` | `checked`, `onChange`, `label`, `description` | `role="switch"`, `aria-checked`, `aria-label` |
| `ScoreBar` | label, value, accent | value repeated as text, never bar-only |
| `Toasts` | global store, tones info/success/error | container `aria-live="polite"`; errors use `role="alert"` |
| `FlowNote` | icon + prose note | non-interactive explanation band |
| `Tabs` | route links | `aria-current="page"` on the active tab |

Composites outside the library:

- `AppShell` — sidebar, mobile drawer, bottom tabs, notification badge, theme
  switch, sign out. Drawer: `role="dialog"`, `aria-label="Navigation menu"`,
  focus moved into the panel on open, Tab trapped, Escape closes, body scroll
  locked, focus returned to the trigger.
- `TripShell` — trip header, people row, primary/secondary tab strips, live
  status. Tab strips scroll horizontally on narrow screens with a partially
  visible pill as the affordance.
- `PublicHeader`, `RequireAuth`, `TripMap` (Leaflet), `CommandPalette` (⌘K),
  `OfflineBanner`.

## 4. Patterns

### 4.1 Page composition

```
PageHeader (eyebrow → title → description → actions)
  optional FlowNote (trust/privacy explanation)
  SectionTitle (h2) + content
  SectionTitle (h3) + content
  EmptyState | ErrorState | Skeleton while loading
```

Primary action sits in `PageHeader.actions` (top-right on ≥sm, stacked full-width
below). Destructive actions sit in the overflow or inside an explicit modal.

### 4.2 Cards

- One idea per card; header row (title + badge/actions), body, optional ruled
  footer with metadata.
- Media cards: 3:2 image, gradient scrim only for legibility of overlaid text,
  caption block below the image (not floating over it).
- Interactive cards are links with visible hover lift and a chevron affordance.

### 4.3 Forms

- One column by default; two columns only for short paired values (dates,
  times, cost + currency).
- Every control is inside `Field`; hints explain consequences, not repeats.
- Privacy-sensitive fields carry an explicit “private to you / never shown”
  note.
- Submit buttons show `loading` and remain disabled while empty or pending.
- Validation messages appear inline under the field with `role="alert"`.

### 4.4 Feedback

| State | Pattern |
|---|---|
| Loading | `PageSkeleton` for pages, inline `skeleton` blocks for panels, button spinner for actions |
| Empty | `EmptyState` with the real reason and a next action |
| Error | `ErrorState` with message and a retry that refetches |
| Success | Toast (top-right, auto-dismiss) + local state change (count, badge, version) |
| Offline | Persistent `OfflineBanner` + queued items surfaced on the Offline page |
| Destructive | Modal naming the object and consequence; cancel is the safe default |

### 4.5 Data trust and privacy in the UI

- Ranked suggestions always show: source (`catalog`), score, and a “Why this was
  chosen / what it may not suit” disclosure.
- Prices are labelled `catalog estimate` or `estimate`; never presented as a
  live quote.
- Community reports carry their own badge and are never styled like verified
  facts.
- Private preferences (budget comfort, notes) are marked private at the field
  and never echoed in grouped views.
- Confirmed itineraries display their version and the rule that edits are
  versioned and group-visible.

## 5. Responsive contract

Breakpoints follow Tailwind defaults; the layout supports 390, 768, 1024 and
1440px without horizontal page scrolling.

| Range | Shell | Content |
|---|---|---|
| < 640px | top bar + drawer + bottom tabs | single column, pills wrap or scroll, tables become stacked rows |
| 640–1023px | top bar + drawer | 2-column card grids, two-column form rows |
| ≥ 1024px | fixed 16rem sidebar | 3-column grids, sticky day strip, side panels |
| ≥ 1280px | sidebar + wide container | max 82rem, whitespace grows, no font inflation |

Rules: `min-w-0` on flex/grid children that contain truncating text; long
titles truncate rather than push; horizontal control strips (`overflow-x-auto`,
`hide-scrollbar`) are the only sanctioned horizontal scroll; no fixed pixel
widths above 320px.

## 6. Accessibility contract

Implemented:

- Skip link to main content.
- Global `:focus-visible` 2px ember ring with 2px offset; no focus removal.
- Semantic landmarks (`header`, `nav`, `main`), one `h1` per route, ordered
  headings.
- Every icon-only control has `aria-label`; selects have associated labels via
  `Field`.
- Toggle states exposed with `aria-pressed` (chips, modes, filters, day strip)
  or `role="switch"` + `aria-checked` (toggles).
- Live regions: toast stack (`aria-live="polite"`, error toasts `role="alert"`),
  filter result counts (`role="status"`), skeletons (`aria-busy`).
- Dialogs: focus on open, focus trap, Escape, focus restore, `aria-modal`,
  labelled by title, described by explanation.
- Reduced motion honoured globally and in framer-motion.
- Mobile inputs are 16px to suppress zoom.

Known limits: no automated axe/Lighthouse scan was executed in this
environment; checks were manual DOM inspection of every route. Icon buttons are
36px (WCAG 2.5.8 AA minimum 24px; 44px is AAA). The `faint` token now meets AA
but has less headroom than `muted`, so it is reserved for tertiary metadata.

## 7. Imagery

- Destination and trip cards use real seeded imagery from the API; there are no
  stock placeholders in shipped screens.
- 3:2 aspect for cards, 16:9 for heroes; `object-fit: cover`; scrim only under
  overlaid text.
- Alt text comes from the data (`name`, `title`); decorative duplicates are
  marked empty.

## 8. Governance

Adding a screen:

1. Compose `PageHeader`, `Card`, `SectionTitle`, `Field`, `Button` from
   `components/ui.tsx`; do not introduce new colours, radii or shadows.
2. Use tokens (`bg-surface`, `text-muted`, `border-line`), never raw hex.
3. Provide loading, empty and error states through the shared components.
4. Add `aria-pressed`/`role="switch"` for any custom toggle.
5. Verify at 390, 768, 1024 and 1440px; the page must not scroll horizontally.
6. Add the route to `docs/FEATURE_REGISTRY.md` and, if it changes a workflow,
   to the audit trail.

Known remaining UI issues are listed in `docs/AUDIT.md` §16.7.
