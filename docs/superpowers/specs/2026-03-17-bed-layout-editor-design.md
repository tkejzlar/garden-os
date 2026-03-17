# Bed Layout Editor — Design Spec

**Date:** 2026-03-17
**Status:** Approved
**Scope:** Replace flat slot grids in the Beds tab with SVG-rendered proportional bed shapes, drag-and-drop plant placement, and AI-suggested layouts.

---

## Overview

The Beds tab currently renders each bed as a generic grid of rows × slots. This redesign replaces those grids with **inline SVGs** that reflect each bed's actual proportions (length × width) and shape (rectangles or polygons via `canvas_points`). Plants are shown as positioned elements inside the SVG, and users can drag plants between slots or ask the AI to suggest layouts.

No model changes. The existing Row → Slot → Plant structure is preserved — the SVG is a visual layer on top of the same data.

## Component 1: SVG Bed Rendering

Each bed card in the Beds tab renders an inline SVG instead of a CSS grid.

### Rectangular Beds

For beds where `polygon?` is false:

- SVG `viewBox` set to `0 0 {width} {length}` (using the bed's physical dimensions)
- Bed outline: `<rect>` with 4px rounded corners, filled with `canvas_color` (or a default earthy color if null)
- Stroke: 1.5px solid, slightly darker than fill
- The SVG scales to fit the card width while maintaining aspect ratio

### Polygon Beds

For beds where `polygon?` is true:

- SVG `viewBox` computed from the bounding box of `canvas_points_array`
- Bed outline: `<polygon>` with points from `canvas_points_array`
- Same fill/stroke treatment as rectangles

### Slot Positioning

Slots are positioned inside the bed SVG as a grid:

- Divide the bed into `rows.count` horizontal bands
- Within each band, divide into `row.slots.count` equal cells
- Each slot renders as a rounded `<rect>` with padding inside its cell

For polygon beds: slots use the same grid logic within the bounding box. Slots that fall mostly outside the polygon are still rendered (the polygon clips the bed outline, but slots are positioned by the grid — rare edge case since most polygon beds are close to rectangular).

### Slot Appearance

**Occupied slot:**
- Fill: crop-type color (same mapping as current: nightshade=#fef2f2, leafy=#f0fdf4, herb=#ecfdf5, flower=#fefce8, cucurbit=#f0f9ff, default=#f9fafb)
- `<text>` element: variety name (truncated if needed), centered
- `<text>` element below: lifecycle stage in smaller font
- Rounded rect with subtle shadow filter

**Empty slot:**
- Fill: #f9fafb with dashed stroke (#d1d5db)
- Cursor: pointer (tappable)

### Responsive Sizing

- SVG width: 100% of card
- SVG height: auto (from viewBox aspect ratio)
- Minimum height: 80px (so very narrow beds aren't too squished)
- Maximum height: 300px (so very tall beds don't dominate the page)

### Data Source

All data comes from server-side ERB — no API call needed. Same as current Beds tab: beds, rows, slots, plants are all loaded in the template.

---

## Component 2: Plant Interaction

### Tap Plant (Popover)

Tapping an occupied slot shows a popover (Alpine.js managed):

- Variety name (bold)
- Crop type · lifecycle stage
- Days in stage
- "View plant →" link to `/plants/:id`
- "Move" button → enters drag mode for this plant

Popover dismisses on tap outside or on a close button.

### Tap Empty Slot (AI Drawer)

Tapping an empty slot opens the AI drawer with context:

```javascript
openAIForBed(bedName, emptySlotCount)
```

This already exists from the Plan tab redesign. The context banner shows "Beds tab → BB1, 2 empty slots".

### Drag and Drop

Long-press (300ms) on an occupied slot starts drag mode:

1. **Lift:** The plant's SVG rect scales up slightly (1.1×) and gets a drop shadow
2. **Drag:** On touch/mouse move, a ghost element follows the pointer. Valid drop targets (other slots in the same bed) highlight with a green dashed border
3. **Drop on empty slot:** Move the plant — `PATCH /plants/:id { slot_id: newSlotId }`
4. **Drop on occupied slot:** Swap both plants — `PATCH /beds/:id/swap-slots { slot_a: id1, slot_b: id2 }`
5. **Drop outside / cancel:** Return to original position, no change

**Implementation:** Alpine.js `x-data` on each bed SVG tracks `dragging: { plantId, fromSlotId }` and `dragOver: slotId`. Touch events (`touchstart`, `touchmove`, `touchend`) and mouse events (`mousedown`, `mousemove`, `mouseup`) handled.

### New Endpoints

`PATCH /plants/:id` — already exists for stage advancement, extend to accept `slot_id` update.

`PATCH /beds/:id/swap-slots` — new endpoint:

```json
Request: { "slot_a": 42, "slot_b": 57 }
Response: { "ok": true }
```

Swaps the plant assignments of two slots. If one is empty, it's just a move. Validates both slots belong to the bed.

---

## Component 3: AI Layout Actions

The AI drawer gains a new tool (`DraftBedLayoutTool`) that returns structured layout suggestions instead of just text.

### New Tool: DraftBedLayoutTool

Registered in `PlannerService` alongside existing tools. The AI calls it when the user asks about a specific bed's layout.

**Input (from AI):**

```json
{
  "bed_name": "BB1",
  "action": "fill" | "rearrange" | "plan_full",
  "suggestions": [
    { "slot_id": 42, "variety_name": "Raf", "crop_type": "tomato", "reason": "Companion to basil in adjacent slot" },
    { "slot_id": 43, "variety_name": "Genovese", "crop_type": "herb", "reason": "Basil companion for tomatoes" }
  ]
}
```

For "rearrange" action, suggestions include `from_slot_id` and `to_slot_id` instead:

```json
{
  "action": "rearrange",
  "moves": [
    { "plant_id": 12, "from_slot_id": 42, "to_slot_id": 45, "reason": "Move basil next to tomatoes" }
  ]
}
```

**Output:** Stored in `Thread.current[:planner_bed_layout]`, returned alongside the chat response (similar to `draft_payload`).

### Preview Overlay

When the AI returns a layout suggestion, the Beds tab shows a **preview overlay** on the affected bed's SVG:

- **Fill suggestions:** Ghost plants appear in empty slots with dashed borders and 50% opacity. Each shows the suggested variety name.
- **Rearrange suggestions:** Arrows drawn between from → to slots showing proposed moves.
- **Full plan:** All slots show ghost plants.

Below the bed SVG, two buttons appear:
- **"Apply layout"** → `POST /beds/:id/apply-layout` with the suggestion payload
- **"Dismiss"** → clears the preview

### Apply Layout Endpoint

`POST /beds/:id/apply-layout`

```json
Request: {
  "action": "fill",
  "suggestions": [
    { "slot_id": 42, "variety_name": "Raf", "crop_type": "tomato" },
    { "slot_id": 43, "variety_name": "Genovese", "crop_type": "herb" }
  ]
}
```

For "fill" and "plan_full": creates Plant records for each suggestion with `slot_id`, `variety_name`, `crop_type`, `lifecycle_stage: "seed_packet"`, `garden_id`.

For "rearrange": updates `slot_id` on existing Plant records.

Validates all slots belong to the bed. Returns updated bed data for re-render.

---

## What Changes

### Files Modified

| File | Change |
|------|--------|
| `views/succession.erb` | Replace Beds tab slot grid with SVG rendering + drag handlers |
| `routes/succession.rb` | Add `PATCH /beds/:id/swap-slots` and `POST /beds/:id/apply-layout` |
| `routes/plants.rb` | Extend `PATCH /plants/:id` to accept `slot_id` |
| `services/planner_service.rb` | Register `DraftBedLayoutTool` |

### New Files

| File | Purpose |
|------|---------|
| `services/planner_tools/draft_bed_layout_tool.rb` | AI tool for structured bed layout suggestions |

### No Model Changes

The Row → Slot → Plant data model is unchanged. SVG rendering and drag-and-drop are purely view-layer. The apply-layout endpoint creates/moves Plants using existing model methods.

---

## Data Flow

```
Beds tab loads
  → ERB iterates beds, rows, slots, plants (server-side)
  → For each bed: renders inline SVG with viewBox from length×width
  → Slots positioned as grid inside SVG
  → Plants shown as colored rects with text

User drags plant to another slot
  → Alpine.js tracks drag state
  → On drop: PATCH /plants/:id or PATCH /beds/:id/swap-slots
  → Page reloads (or Alpine re-renders if we inline the response)

User taps empty slot
  → AI drawer opens with bed context
  → User asks "what should I plant here?"
  → AI calls DraftBedLayoutTool → returns structured suggestions
  → Preview overlay renders ghost plants on SVG
  → User taps "Apply" → POST /beds/:id/apply-layout
  → Page reloads with new plants
```

---

## Design Constraints

- **No external libraries** — SVG is native, drag via Alpine.js touch/mouse events
- **Mobile-first** — touch drag (long-press to start), responsive SVG sizing
- **Earthy & Warm palette** — bed fills use `canvas_color`, slots use crop-type colors
- **Existing test suite** — all tests must pass
- **Progressive enhancement** — beds render correctly even without JS (just no drag/AI)
