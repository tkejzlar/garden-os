# GardenOS Frontend Redesign — Design Spec

> Redesign the GardenOS frontend from functional-but-plain Tailwind templates to a polished, mobile-first garden management UI that's delightful to open every morning.

---

## Design Direction: Earthy & Warm

**Palette:**
- Background gradient: `#f0fdf4` (green-50) → `#fefce8` (yellow-50) → `#fffbeb` (amber-50)
- Cards: white with subtle shadow (`box-shadow: 0 1px 3px rgba(0,0,0,0.06)`)
- Primary text: `#1a2e05` (near-black green)
- Secondary text: `#6b7280` (gray-500)
- Active/accent: `#365314` (green-900)
- Alert amber: `#d97706` border-left, `#fef3c7` background
- Alert red (frost): `#fef2f2` bg, `#991b1b` text
- Success/check: `#86efac` (green-300)
- Warning (overdue germination): `#ea580c` (orange-600)

**Typography:**
- System font stack: `system-ui, -apple-system, sans-serif`
- Headings: bold, tight letter-spacing (-0.5px)
- Section labels: 11px uppercase, 1px letter-spacing, gray-500
- Body: 13-14px, #1f2937

**Card style:**
- `border-radius: 12px`
- White background
- Subtle shadow
- 14-16px padding

**Icons:**
- Lucide icon set (MIT, SVG, https://lucide.dev)
- Pin to version: `https://unpkg.com/lucide@0.460.0`
- 22px size in tab bar
- stroke-width: 1.8
- Active: `#365314` (green-900), Inactive: `#9ca3af` (gray-400)

**Gradient placement:**
- Applied to `<body>` element, replacing the current `bg-stone-50`
- Bottom tab bar and cards are white, floating above the gradient
- The gradient is the "canvas" — everything else sits on top of it

---

## Navigation: Bottom Tab Bar

Fixed bottom tab bar, always visible. 4 tabs:

| Tab | Icon (Lucide) | Route |
|-----|--------------|-------|
| Home | `home` | `/` |
| Plants | `leaf` | `/plants` |
| Beds | `layout-grid` | `/beds` |
| Succession | `trending-up` | `/succession` |

- Active tab: dark green icon + bold label
- Inactive tab: gray icon + gray label
- Tab label font: 9px, uppercase not needed (just regular weight)
- **Remove the current top `<nav>` bar entirely** — replace with per-page header (logo + date)
- Logo + date appear in the page header area, not a persistent nav bar

---

## Dashboard (`/`)

### Header
- Logo (🌱 + "GardenOS") left-aligned, date right-aligned
- Greeting: "Good morning ☀️" (or afternoon/evening based on time)

### Alert Banner (conditional)
- Only renders when there's an active alert (frost risk, overdue germination, etc.)
- Left border accent (amber for warning, red for critical)
- Icon + title + subtitle
- Hidden on calm days — dashboard feels peaceful when nothing is wrong

### Summary Strip
2x2 grid on narrow screens (< 375px), 4-column row on wider screens:

| Card | Content | Color |
|------|---------|-------|
| Temperature | Current temp + condition | Green |
| Tasks | Count of today's tasks | Amber |
| Seeds | Count of germinating plants | Orange |
| This week | Count of upcoming tasks | Green |

### Segmented Tabs
iOS-style segmented control with 4 tabs:

**Tasks tab (default):**
- Today's tasks with 36px circle checkboxes (green border)
- Task title, subtitle (context: days, location, succession info)
- Priority badge: must (red-100), should (amber-100), could (gray-100)
- Tap checkbox → POST to complete, checkbox fills with checkmark
- "This week" section below with date + task preview (lower opacity)
- **Empty state:** "Nothing to do today — enjoy the garden." with a leaf illustration or subtle icon

**Seeds tab:**
- Germination watch cards
- Each card: variety name, crop type, days-in-stage
- Progress bar showing days vs expected germination range
- Bar color: green (on track), orange (approaching max), red (overdue)
- **Empty state:** "No seeds germinating right now."

**Weather tab:**
- Current conditions (large temp display)
- 3-day forecast with highs/lows/conditions
- Frost risk indicator if applicable
- **Error state:** If weather unavailable, show "Can't reach Home Assistant" with muted text — not an alert, just informational
- **Summary strip fallback:** Temperature card shows "—" when weather data is unavailable

**Insights tab:**
- AI advisories for today
- Each advisory as a card with summary text
- Plant-specific advisories link to the plant detail
- **Empty state:** "No advisories yet today." (normal before the 6:30am cron runs)

---

## Plants Page (`/plants`)

### List View
- Grouped by crop type (collapsible sections)
- Each plant card: variety name, current stage as text, quick-advance buttons
- Batch selection: checkboxes appear, batch action bar slides up from bottom
- Stage shown as colored text (not badge): green for growing stages, gray for done
- **Empty state:** "No plants yet. Add your first plant to get started."

### Plant Detail (`/plants/:id`)

**Top half — Actions:**
- Current stage prominently displayed
- Next likely stages as large tap buttons (e.g., "Mark as germinated", "Potted up")
- Only show 2-3 most likely next stages, not all 11

**Bottom half — Timeline:**
- Vertical timeline with stage history
- Each entry: stage name, date, optional note
- Key dates summary: sown, germinated, transplanted

**Key dates card:**
- Sow date, germination date, transplant date
- Days in current stage

---

## Beds Page (`/beds`)

### Garden Map
- Color-coded grid: each crop type has a consistent color
- Bed cards with nested row → slot grid
- Tap a bed → drill into bed detail
- **Arches section:** Card per arch showing name, between_beds, spring/summer crop assignments. Same card style as beds.
- **Indoor stations section:** Card per station showing name, type, plant count currently assigned. Tap to see plants at that station.

### Bed Detail (`/beds/:id`)
- Rows with slot cards
- Each slot shows plant name + stage or "Empty"
- Tap plant → goes to plant detail

---

## Succession Page (`/succession`)

- Each plan as a card with progress bar and numbered dots
- Completed sowings: green dots
- Current/next: amber dot
- Future: gray dots
- Next sowing countdown: "in X days (date)"
- Varieties and target beds listed
- **Empty state:** "No succession plans set up yet."

---

## Interaction Patterns

**Task completion:**
- Tap circle checkbox → immediate POST, checkbox fills green with checkmark, task text gets strikethrough
- No undo mechanism — keep it simple. If tapped by mistake, task can be found in a future "completed" view.

**Stage advancement (plant detail):**
- Tap stage button → POST → page refreshes with new stage
- Auto-sets dates (sow_date, germination_date, etc.)
- Only show next 2-3 stages in the lifecycle sequence, not all 11. The backend `Plant::LIFECYCLE_STAGES` array defines order — show the next stages after the current one.

**Batch operations (plants list):**
- Explicit "Select" button in the page header to enter batch mode
- In batch mode: checkboxes appear on each plant card, action bar slides up from bottom
- Action bar: "3 selected — Advance to: [dropdown] [Apply]"
- Tap "Select" again (or "Cancel") to exit batch mode

---

## Technical Approach

- **No build step** — continue using Tailwind CDN + Alpine.js CDN
- **Lucide icons** — load via CDN: `https://unpkg.com/lucide@0.460.0` (pinned version)
- **Alpine.js tabs** — `x-data` for tab state on dashboard
- **Server-rendered** — ERB templates, no client-side routing
- **CSS custom properties** — define palette as CSS variables in layout for consistency
- **Responsive** — mobile-first, single column. On tablet/desktop, summary strip and tabs can be wider

---

## What's NOT changing

- Backend routes and API — all existing endpoints stay the same
- Data model — no schema changes
- Test suite — route tests still pass (they test response codes and content, not styling)
- Service worker and PWA manifest — keep as-is
