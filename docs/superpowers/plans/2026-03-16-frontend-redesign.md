# Frontend Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking. **Use the frontend-design skill** for each view template task.

**Goal:** Redesign all GardenOS view templates from plain Tailwind to the Earthy & Warm design system with bottom tab bar, summary strip dashboard, and polished mobile-first UI.

**Architecture:** Pure view-layer rewrite. No backend changes. ERB templates + Tailwind CDN + Alpine.js CDN + Lucide icons CDN. CSS custom properties for the design system palette.

**Tech Stack:** Tailwind CSS (CDN), Alpine.js (CDN), Lucide icons (CDN, pinned v0.460.0)

**Spec:** `docs/superpowers/specs/2026-03-16-frontend-redesign.md`

---

## File Structure

All changes are to existing view files plus one new CSS file:

```
Modified:
├── views/
│   ├── layout.erb              # New design system: gradient, CSS vars, bottom tab bar, Lucide, remove top nav
│   ├── dashboard.erb           # Summary strip + segmented tabs (Alpine.js)
│   ├── plants/
│   │   ├── index.erb           # Earthy cards, grouped list, batch select mode
│   │   └── show.erb            # Actions top + timeline bottom
│   ├── beds/
│   │   ├── index.erb           # Earthy garden map, arches, indoor stations
│   │   └── show.erb            # Earthy bed detail with slot cards
│   └── succession.erb          # Earthy progress cards with dots
```

---

### Task 1: Layout — Design System Foundation

**Files:**
- Modify: `views/layout.erb`

This is the foundation — every other task depends on it.

- [ ] **Step 1: Rewrite layout.erb**

Replace the entire file. The new layout must:
- Remove the top `<nav>` bar entirely
- Add CSS custom properties for the full Earthy & Warm palette
- Set body background to the green→yellow→amber gradient
- Add Lucide icons CDN (pinned `https://unpkg.com/lucide@0.460.0`)
- Add a fixed bottom tab bar with Lucide SVG icons (home, leaf, layout-grid, trending-up)
- Use Alpine.js `x-data` on `<body>` to track current page for active tab highlighting
- Add `padding-bottom: 72px` to `<main>` so content doesn't hide behind the tab bar
- Keep the PWA manifest link and service worker registration
- Keep Tailwind CDN and Alpine.js CDN

The bottom tab bar HTML structure:
```html
<nav class="fixed bottom-0 left-0 right-0 bg-white border-t border-gray-200 flex" style="padding: 8px 0 env(safe-area-inset-bottom, 12px); box-shadow: 0 -2px 8px rgba(0,0,0,0.04);">
  <!-- 4 tab links with Lucide icons, active state based on current path -->
</nav>
```

Active tab detection: pass `request.path_info` from Sinatra to the template as a local, or use a simple ERB check like `<%= request.path_info == '/' ? 'color: var(--green-900); font-weight: 600' : 'color: var(--gray-400)' %>`.

CSS custom properties to define in a `<style>` block:
```
--green-900: #365314;
--green-50: #f0fdf4;
--yellow-50: #fefce8;
--amber-50: #fffbeb;
--gray-400: #9ca3af;
--gray-500: #6b7280;
--text-primary: #1a2e05;
--text-secondary: #6b7280;
--card-shadow: 0 1px 3px rgba(0,0,0,0.06);
--card-radius: 12px;
--alert-amber-bg: #fef3c7;
--alert-amber-border: #d97706;
--alert-red-bg: #fef2f2;
--alert-red-text: #991b1b;
--success: #86efac;
--warning: #ea580c;
```

- [ ] **Step 2: Verify all existing pages still render**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`
Expected: All 32 tests pass (no backend changes).

- [ ] **Step 3: Commit**

```bash
git add views/layout.erb
git commit -m "feat: design system foundation — earthy palette, bottom tab bar, Lucide icons"
```

---

### Task 2: Dashboard — Summary Strip + Tabbed Interface

**Files:**
- Modify: `views/dashboard.erb`
- Modify: `routes/dashboard.rb` (minor — pass extra counts to template)

The dashboard is the most complex view — it needs the summary strip, segmented tabs with Alpine.js, and conditional alert banner.

- [ ] **Step 1: Update dashboard route to pass summary counts**

Add these instance variables to the `get "/"` route in `routes/dashboard.rb`:
```ruby
@germination_count = @germination_watch.count
@upcoming_count = @upcoming_tasks.count
@today_count = @today_tasks.count
```

These power the summary strip numbers without extra queries.

- [ ] **Step 2: Rewrite dashboard.erb**

Replace the entire file. The new dashboard must have:

**Header section:**
- 🌱 GardenOS logo left, date right
- Time-aware greeting ("Good morning/afternoon/evening")

**Alert banner (conditional):**
- Only render if `@weather&.dig(:frost_risk)` is true
- Amber left border, frost icon, temp info
- Hidden entirely on calm days

**Summary strip:**
- 4 cards in a `grid grid-cols-2 sm:grid-cols-4` layout
- Card 1: current temp (or "—" if no weather) + condition label
- Card 2: today's task count
- Card 3: germinating count
- Card 4: upcoming this week count
- Each card: white bg, 12px rounded corners, centered big number + small label

**Segmented tabs (Alpine.js):**
```html
<div x-data="{ tab: 'tasks' }">
  <!-- Tab bar: 4 buttons -->
  <div class="flex bg-black/5 rounded-xl p-1 mb-4">
    <button @click="tab = 'tasks'" :class="tab === 'tasks' ? 'bg-white shadow-sm font-semibold text-green-900' : 'text-gray-500'" class="flex-1 py-2 text-xs rounded-lg transition-all">Tasks</button>
    <!-- ... Seeds, Weather, Insights buttons ... -->
  </div>

  <!-- Tab panels -->
  <div x-show="tab === 'tasks'">...</div>
  <div x-show="tab === 'seeds'">...</div>
  <div x-show="tab === 'weather'">...</div>
  <div x-show="tab === 'insights'">...</div>
</div>
```

**Tasks panel:**
- Each task: white card, 36px circle checkbox (green border), title, subtitle, priority badge
- Checkbox: `@click` → fetch POST to `/tasks/:id/complete`, then visually strikethrough
- "This week" section below with lighter opacity upcoming tasks
- Empty state: "Nothing to do today — enjoy the garden."

**Seeds panel:**
- Germination watch cards with progress bars
- Progress bar width = `(days_in_stage / expected_max_days) * 100%`
- Bar color: green < 70%, orange 70-100%, red > 100%
- Empty state: "No seeds germinating right now."

**Weather panel:**
- Large temp display with condition
- 3-day forecast cards
- Error state: "Can't reach Home Assistant" if `@weather.nil?`

**Insights panel:**
- Advisory cards with summary text
- Empty state: "No advisories yet today."

- [ ] **Step 3: Run tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`
Expected: All tests pass. Dashboard tests check for content like "GardenOS", "Sow lettuce", "Raf" — these should still be present in the new HTML.

- [ ] **Step 4: Commit**

```bash
git add views/dashboard.erb routes/dashboard.rb
git commit -m "feat: dashboard redesign — summary strip, tabbed interface, earthy palette"
```

---

### Task 3: Plants List — Grouped Cards with Batch Mode

**Files:**
- Modify: `views/plants/index.erb`

- [ ] **Step 1: Rewrite plants/index.erb**

The new plants list must have:
- Page header: "Plants" title + "Select" button (toggles batch mode)
- Plants grouped by crop type with section headings
- Each plant card: white, 12px rounded, variety name, stage as colored text, quick-advance buttons for next 2 stages
- Batch mode (Alpine.js `x-data="{ selectMode: false, selected: [] }"`):
  - Toggle with "Select" button
  - Checkboxes appear on each card
  - Bottom action bar slides up: "N selected — Advance to: [dropdown] [Apply]"
- Empty state: "No plants yet."

- [ ] **Step 2: Run tests**

Run: `rm -f db/garden_os_test.db && ruby test/routes/test_plants.rb`
Expected: 5 tests pass. Tests check for "Raf" in response body — must still be present.

- [ ] **Step 3: Commit**

```bash
git add views/plants/index.erb
git commit -m "feat: plants list redesign — grouped cards, batch select mode"
```

---

### Task 4: Plant Detail — Actions + Timeline

**Files:**
- Modify: `views/plants/show.erb`

- [ ] **Step 1: Rewrite plants/show.erb**

The new plant detail must have:
- Back link to `/plants`
- Variety name as large heading, crop type + current stage below
- **Actions section (top):** Current stage highlighted, next 2-3 stages as large tap buttons (forms posting to `/plants/:id/advance`)
- **Key dates card:** Sow date, germination date, transplant date, days in stage
- **Timeline section (bottom):** Vertical timeline with green left border, circle markers at each stage transition, date + optional note

- [ ] **Step 2: Run tests**

Run: `rm -f db/garden_os_test.db && ruby test/routes/test_plants.rb`

- [ ] **Step 3: Commit**

```bash
git add views/plants/show.erb
git commit -m "feat: plant detail redesign — actions top, timeline bottom"
```

---

### Task 5: Beds — Garden Map + Detail

**Files:**
- Modify: `views/beds/index.erb`
- Modify: `views/beds/show.erb`

- [ ] **Step 1: Rewrite beds/index.erb**

The new beds page must have:
- "Garden Map" heading
- Color legend for crop types (same colors as before, but styled as small pills)
- Bed cards: white, 12px rounded, bed name heading, nested row→slot grid with color-coded cells
- **Arches section:** Cards showing name, between_beds, spring/summer crop
- **Indoor stations section:** Cards showing name, station type, plant count
- Tap a bed → `/beds/:id`

- [ ] **Step 2: Rewrite beds/show.erb**

- Back link to `/beds`
- Bed name heading, bed type + orientation
- Rows with slot cards: white, rounded, plant name + stage or "Empty"
- Tap plant → `/plants/:id`

- [ ] **Step 3: Run tests**

Run: `rm -f db/garden_os_test.db && ruby test/routes/test_beds.rb`
Expected: 3 tests pass.

- [ ] **Step 4: Commit**

```bash
git add views/beds/
git commit -m "feat: beds redesign — earthy garden map, arches, indoor stations"
```

---

### Task 6: Succession — Progress Cards

**Files:**
- Modify: `views/succession.erb`

- [ ] **Step 1: Rewrite succession.erb**

The new succession page must have:
- "Succession Planner" heading
- Each plan as a white card: crop name, completed/total count, progress bar, numbered dots (green=done, amber=next, gray=future), interval + varieties + beds info, next sowing countdown
- Empty state: "No succession plans set up yet."

- [ ] **Step 2: Run tests**

Run: `rm -f db/garden_os_test.db && ruby test/routes/test_succession.rb`
Expected: 2 tests pass.

- [ ] **Step 3: Commit**

```bash
git add views/succession.erb
git commit -m "feat: succession redesign — earthy progress cards with sowing dots"
```

---

## Summary

| Task | What changes | Files |
|------|-------------|-------|
| 1 | Design system: gradient, CSS vars, bottom tab bar, Lucide | layout.erb |
| 2 | Dashboard: summary strip, segmented tabs, alerts | dashboard.erb, routes/dashboard.rb |
| 3 | Plants list: grouped cards, batch select mode | plants/index.erb |
| 4 | Plant detail: actions top, timeline bottom | plants/show.erb |
| 5 | Beds: earthy garden map + detail | beds/index.erb, beds/show.erb |
| 6 | Succession: earthy progress cards | succession.erb |

Total: **6 tasks**, pure view-layer changes. All 32 existing tests must continue passing after each task.
