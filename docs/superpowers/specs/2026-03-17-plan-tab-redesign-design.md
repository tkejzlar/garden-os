# Plan Tab Redesign — Design Spec

**Date:** 2026-03-17
**Status:** Approved
**Scope:** Plan tab (`/succession` route, `views/succession.erb`) — redesign layout, add bed timeline, improve task view, context-aware AI drawer

---

## Overview

The Plan tab currently stacks four sections vertically: AI chat, plan cards, task timeline, and a basic succession Gantt chart. This creates excessive scrolling, hides important information below the fold, and lacks bed occupancy visualization — the most-requested feature.

The redesign replaces the vertical stack with a **summary strip + tabbed interface** and adds a **context-aware AI drawer** that slides up from a floating action button.

## Architecture

Pure view-layer rewrite of `views/succession.erb` plus one new API endpoint. No model changes. Alpine.js for all interactivity, no external chart libraries.

### Layout Structure

```
┌─────────────────────────────┐
│ Summary Strip (always visible) │
│ [due this week] [overdue] [done] │
├─────────────────────────────┤
│ [Tasks]  [Timeline]  [Beds]  │  ← Tab bar
├─────────────────────────────┤
│                             │
│   Active tab content        │
│   (full remaining viewport) │
│                             │
├─────────────────────────────┤
│                         [✦] │  ← AI FAB (floating action button)
└─────────────────────────────┘
```

Alpine.js state on the page:

```javascript
{
  tab: 'tasks',           // 'tasks' | 'timeline' | 'beds'
  aiOpen: false,          // drawer visibility
  aiContext: {},           // assembled from current view state
  expandedBeds: [],       // bed IDs expanded in timeline
  timelineZoom: 'month',  // 'month' | 'week'
}
```

---

## Component 1: Summary Strip

Always visible at the top. Shows key plan stats at a glance.

**Data needed (from route):**
- `@due_this_week_count` — tasks due within 7 days
- `@overdue_count` — tasks past due date, not done
- `@done_count` / `@total_task_count` — completion progress
- `@total_plants` — total plant count
- `@succession_count` — total succession plan count

**Visual:**
- Gradient background (green → yellow, matching app palette)
- Title: "Season Plan" with subtitle "N plants · N successions"
- Three stat cards in a row: "This week" (count), "Overdue" (count, orange if > 0), "Done" (done/total)

---

## Component 2: Tasks Tab

Default active tab. Shows all plan tasks grouped by urgency.

**Groups (in order):**
1. **Overdue** — red accent, left border, urgent styling. Only shown if overdue tasks exist.
2. **This week** — normal cards, priority badges visible.
3. **Later** — faded/lower opacity, smaller cards. Loads progressively on scroll.

**Task card anatomy:**
```
┌──────────────────────────────────┐
│ ○  Task title                [must] │
│    Due date · Bed name              │
└──────────────────────────────────┘
```

- Circular checkbox (22px): green border, tap → POST `/tasks/:id/complete`, strikethrough + fade animation
- Priority badge: `must` (red bg), `should` (amber bg), `could` (gray bg) — only shown if priority set
- Relative dates: "Tomorrow", "2 days overdue", "Mar 25"
- Bed name shown if task has bed associations

**Data source:** Existing `@all_tasks` and `@done_tasks` from the succession route, re-grouped client-side by Alpine.js based on due date vs today.

---

## Component 3: Timeline Tab

Bed occupancy heat-map showing what's planted in each bed across the season.

### Heat-Map View (default, collapsed)

One horizontal bar per bed. Color intensity = slots filled / total slots for that time period.

```
         Mar  Apr  May  Jun  Jul  Aug  Sep
BB1  ▸  [░░░][▓▓▓][███][███][███][▓▓▓][░░░]
BB2  ▸  [░░░][░░░][▓▓▓][▓▓▓][▓▓▓][░░░][░░░]
SB1  ▸  [▓▓▓][▓▓▓][▓▓▓][░░░][░░░][░░░][░░░]
SB2  ▸  [░░░][▓▓▓][▓▓▓][▓▓▓][░░░][░░░][░░░]
```

**Intensity scale:**
- `rgba(34,197,94, 0.05)` — empty (0% filled)
- `rgba(34,197,94, 0.3)` — partial
- `rgba(34,197,94, 0.6)` — full or near-full

**Legend:** Empty | Partial | Full | Planned (dashed border)

### Expanded View (tap a bed)

Tapping a bed name (▸ → ▾) expands it inline to show per-crop rows:

```
SB1  ▾  [▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓]  ← occupancy bar
  Lettuce  [███][███][┄┄┄][┄┄┄]           ← solid = planted, dashed = planned
  Radish   [██][┄┄]                        ← succession blocks
```

- Crop name on left, horizontal bars per succession/planting
- Solid fill = planted/growing
- Dashed border + light fill = planned but not yet sown
- Multiple plants of same crop shown as one bar with `×N` count

### Controls

- **Zoom toggle:** Month (default, season overview) / Week (detailed, horizontal scroll)
- **Today marker:** Red vertical line with "Today" label
- **Time window:** Season start to season end (derived from earliest to latest task/plan dates), padded 2 weeks each side

### New API Endpoint

`GET /api/plan/bed-timeline`

Returns bed occupancy data aggregated by time period:

```json
{
  "today": "2026-03-17",
  "season_start": "2026-03-01",
  "season_end": "2026-10-01",
  "beds": [
    {
      "bed_id": 1,
      "bed_name": "BB1",
      "total_slots": 6,
      "occupancy": [
        { "month": "2026-03", "filled": 0 },
        { "month": "2026-04", "filled": 2 },
        { "month": "2026-05", "filled": 6 },
        ...
      ],
      "crops": [
        {
          "crop": "Tomato",
          "varieties": ["Raf", "San Marzano", "Cherokee Purple"],
          "plant_count": 5,
          "periods": [
            { "start": "2026-04-15", "end": "2026-09-30", "status": "planted" }
          ]
        },
        {
          "crop": "Basil",
          "varieties": ["Genovese"],
          "plant_count": 1,
          "periods": [
            { "start": "2026-05-01", "end": "2026-09-15", "status": "planned" }
          ]
        }
      ]
    }
  ]
}
```

The endpoint aggregates:
- Plants currently assigned to bed slots (via Slot → Plant)
- Succession plan targets (via SuccessionPlan.target_beds)
- Task bed associations (via tasks_beds join)

### Occupancy Rules

A plant **occupies** a slot from its earliest dated stage (sow_date or first stage_history entry) until its lifecycle_stage becomes `"done"` or `"removed"`. Plants without a `"done"` stage are assumed to occupy the slot through the end of the season window.

There is no harvest date or days-to-maturity field in the current model. Rather than adding one, the heat-map uses this simple rule:
- **Slot is occupied** if the plant in it has `lifecycle_stage != "done"`
- **Slot becomes free** when the plant is advanced to `"done"`
- **Planned occupancy** (from succession plans) uses `season_start` + `interval_days` × sowing_number to project future slot usage, shown with dashed styling

For the `occupancy[].filled` monthly count: iterate each bed's slots, count how many have a plant that was active during that month (between first stage date and done date, or season end if not done).

---

## Component 4: Beds Tab

Current spatial snapshot — what's in each bed right now.

### Occupancy Summary (top)

Compact row of bed pills showing fill status:

```
[BB1 6/6] [BB2 4/6] [SB1 2/4] [SB2 3/4] [Corner 2/5]
```

### Bed Cards (grouped)

Three sections:

**Outdoor Beds:**
Each bed as a card with its actual Row → Slot grid rendered faithfully:
- Card header: bed name, bed type, slot count (filled/total)
- Grid: one row per `Row`, slots rendered proportionally
- Variable slot counts per row supported (flex layout, each row independent)
- Slot colors by crop type (existing color scheme: red=nightshade, green=leafy, yellow=flower, etc.)
- Empty slots: dashed border, gray background
- Tap a filled slot → navigates to `/plants/:id`
- Tap an empty slot → opens AI drawer with context "SB1 has empty slots"

**Arches:**
Cards with purple left accent border:
- Arch name, "Between X ↔ Y" subtitle
- Spring crop → Summer crop display
- Current crop highlighted

**Indoor Stations:**
Cards with amber left accent border:
- Station name, type, cell count
- Dense grid (4+ columns) for propagation trays
- Each cell: abbreviated plant name or empty

### Handling Irregular Layouts

The Row → Slot model naturally handles irregularity:
- **L-shaped beds:** Row 1 has 3 slots, Row 2 has 2 slots — each row renders with its own slot count
- **Triangular corners:** Rows with decreasing slot counts
- **Single-row beds:** Just one row of slots
- **Dense propagation trays:** Indoor stations render as tight grids (grid-template-columns based on slot count)

No special polygon rendering needed — the grid structure implicitly communicates shape through variable row widths.

---

## Component 5: AI Drawer

Context-aware slide-up drawer triggered by the floating action button (✦).

### Trigger
- Green circular FAB, 44px, bottom-right corner, always visible
- Tap → drawer slides up from bottom (80-85% viewport height)
- Swipe down or tap backdrop → dismisses
- Switching tabs while drawer is open: drawer stays open, context banner updates to reflect the new tab

### Context Assembly

When the drawer opens, Alpine.js assembles context from current state:

```javascript
getAIContext() {
  const ctx = { view: this.tab };
  if (this.tab === 'beds' && this.selectedBed) {
    ctx.bed_id = this.selectedBed.id;
    ctx.bed_name = this.selectedBed.name;
    ctx.empty_slots = this.selectedBed.empty_count;
    ctx.current_plants = this.selectedBed.plants;
  }
  if (this.tab === 'timeline' && this.expandedBeds.length) {
    ctx.expanded_beds = this.expandedBeds;
  }
  return ctx;
}
```

### Context Banner

Top of drawer shows what the AI sees:

```
┌─────────────────────────────────┐
│ Context: Beds tab → SB1          │
│ 2 empty slots · Lettuce active   │
└─────────────────────────────────┘
```

### Quick Action Chips

Contextual suggestions below the banner, based on current view:

- **Tasks tab:** "What should I do this week?" / "Reprioritize my tasks"
- **Timeline tab:** "Any gaps I should fill?" / "Plan next month"
- **Beds tab (with selected bed):** "What should I plant here?" / "Rotation suggestions"
- **Beds tab (general):** "Plan my whole season" / "Which beds have space?"

### Chat Interface

- Message history (existing planner_messages, same storage)
- Text input with send button
- AI responses rendered as markdown (existing marked.js)
- Draft cards with "Create this plan" button (existing commit flow)

### Backend Change

Modify `POST /succession/planner/ask` to accept optional context:

```json
{
  "message": "What should I plant in the empty slots?",
  "context": {
    "view": "beds",
    "bed_id": 3,
    "bed_name": "SB1",
    "empty_slots": 2,
    "current_plants": ["Tre Colori", "Qualitas"]
  }
}
```

**How context is injected:** The context is prepended to the **user message text** before passing to `PlannerService.send_message(text)`. This avoids modifying the memoized system prompt or breaking chat history continuity. The context becomes a natural part of the conversation:

```ruby
# In the route handler:
context_prefix = if params[:context]
  ctx = params[:context]
  "[Context: viewing #{ctx['view']} tab" +
    (ctx['bed_name'] ? ", bed #{ctx['bed_name']}, #{ctx['empty_slots']} empty slots" : "") +
  "] "
else
  ""
end
PlannerService.send_message(context_prefix + params[:message])
```

This way the AI sees the context inline with the user's question, and the existing chat history mechanism works unchanged.

---

## What Gets Removed

- **Top-level AI chat section** — replaced by the drawer
- **Plan cards section** — plan info absorbed into summary strip stats and timeline
- **Separate succession Gantt** — replaced by bed occupancy timeline (same information, organized by bed instead of by crop)
- **Task timeline by month** — replaced by Tasks tab with urgency grouping (more actionable)
- **Quick add task form** — can be added as a future AI drawer action

---

## Files Changed

| File | Change |
|------|--------|
| `views/succession.erb` | Full rewrite — new tabbed layout with all components |
| `routes/succession.rb` | Add summary counts to route locals, add `/api/plan/bed-timeline` endpoint |
| `services/planner_service.rb` | Accept and use context parameter in prompts |

No new files. No model changes. No migration needed.

**Note on Arch/IndoorStation cards:** The Arch and IndoorStation models are minimal. The Beds tab renders what data exists (name, between_beds for arches, station_type for indoor). If fields like spring_crop/summer_crop don't exist on the Arch model, those card elements are omitted — the cards degrade gracefully to showing just the name and relationship.

---

## Data Flow

```
User opens /succession
  → Route computes: tasks, plans, bed data, summary counts
  → Template renders: summary strip + tab structure + Alpine.js state
  → Alpine.js initializes with tab='tasks', fetches timeline data lazily

User switches to Timeline tab
  → fetch('/api/plan/bed-timeline') → renders heat-map bars
  → User taps bed → expandedBeds.push(id) → shows per-crop rows

User switches to Beds tab
  → Renders from server-side data (beds, rows, slots, plants)
  → Grouped by type: outdoor, arches, indoor

User taps ✦ FAB
  → AI drawer slides up
  → Context assembled from Alpine state
  → Context banner shows current view info
  → Quick action chips shown
  → User sends message → POST /succession/planner/ask with context
  → Poll for response → render in drawer
```

---

## Design Constraints

- **No external chart libraries** — all visualization with CSS + Alpine.js
- **Mobile-first** — designed for phone use in the garden
- **Earthy & Warm palette** — existing CSS variables from layout.erb
- **Progressive enhancement** — timeline data fetched lazily, tasks tab works immediately
- **Existing test suite** — all 32 tests must pass (pure view changes shouldn't break)
- **Empty states** — each tab shows a helpful message when no data exists (e.g., "No plantings yet — use the AI planner to get started")
