# AI Garden Management Tools — Design Spec

## Problem

The AI planner can create plants and succession plans via `draft_plan`, but cannot modify or remove existing data. This means redesigns pile duplicates, the AI can't clean up its own mistakes, and users must manually fix what the AI breaks. The AI itself has logged 10 feature requests for these capabilities.

## Scope

Four themes, implemented as new RubyLLM planner tools that operate directly on the DB (no draft/commit flow — immediate execution with confirmation in the chat).

---

## Theme 1: Core CRUD Tools

### `ClearBedTool`
- **Params:** `bed_name` (required)
- **Action:** Destroys all plants on the bed (cascade deletes history, harvests, task links)
- **Returns:** count of removed plants
- **Prompt guidance:** "Use when the user wants to start a bed from scratch"

### `RemovePlantsTool`
- **Params:** `bed_name` (required), `filter` (required — one of: `variety_name`, `crop_type`, or `plant_ids` array)
- **Action:** Destroys matching plants on the bed
- **Returns:** count removed, list of what was removed
- **Prompt guidance:** "Use to clean up duplicates or remove specific varieties"

### `MovePlantTool`
- **Params:** `plant_id` (required), `target_bed_name` (required)
- **Action:** Updates `bed_id` to the target bed. Auto-assigns grid position using the same cursor logic as PlanCommitter (stack below existing plants).
- **Returns:** confirmation with new position

### `UpdatePlantTool`
- **Params:** `plant_id` (required), plus optional: `grid_x`, `grid_y`, `grid_w`, `grid_h`, `quantity`, `variety_name`, `crop_type`
- **Action:** Updates the specified fields
- **Returns:** updated plant summary

### `DeleteSuccessionPlanTool`
- **Params:** `crop` (required), optional `target_bed` to narrow scope
- **Action:** Finds and destroys matching SuccessionPlan records. Also deletes associated pending sow tasks (status != "done").
- **Returns:** count of plans and tasks removed

---

## Theme 2: Layout Primitives

Enhance how the AI places plants on beds with structured placement patterns, replacing the current "dump in next available slot" approach.

### `PlaceRowTool`
- **Params:** `bed_name`, `variety_name`, `crop_type`, `row_y` (grid row to place at), `count` (number of plants), `spacing` (optional override in grid cells), `source` (optional)
- **Action:** Creates `count` plants in a horizontal row at `row_y`, evenly spaced starting from x=0. Uses `Plant.default_grid_size` for width if spacing not specified.
- **Returns:** count created, row position

### `PlaceColumnTool`
- **Params:** `bed_name`, `variety_name`, `crop_type`, `col_x` (grid column), `count`, `spacing` (optional), `source` (optional)
- **Action:** Creates `count` plants in a vertical column at `col_x`.
- **Returns:** count created, column position

### `PlaceSingleTool`
- **Params:** `bed_name`, `variety_name`, `crop_type`, `grid_x`, `grid_y`, `grid_w` (optional), `grid_h` (optional), `quantity` (optional, default 1), `source` (optional)
- **Action:** Creates one plant record at exact position.
- **Returns:** plant summary

### `PlaceBorderTool`
- **Params:** `bed_name`, `variety_name`, `crop_type`, `edges` (array: `"front"`, `"back"`, `"left"`, `"right"`), `spacing` (optional), `source` (optional)
- **Action:** Places plants along the specified edges of the bed. "front" = row 0, "back" = last row, "left" = col 0, "right" = last col. Skips cells already occupied.
- **Returns:** count placed, which edges

### `PlaceFillTool`
- **Params:** `bed_name`, `variety_name`, `crop_type`, `region` (optional: `{ from_x, from_y, to_x, to_y }` — defaults to entire bed), `spacing` (optional), `source` (optional)
- **Action:** Fills the region with plants at proper spacing, skipping occupied cells.
- **Returns:** count placed

These tools give the AI vocabulary for potager-style layouts: "row of lettuce across the front", "column of tomatoes up the back", "border of marigolds", "fill remaining space with basil".

---

## Theme 3: Bed Metadata & Zones

### DB Migration: `bed_zones` table
```
id, bed_id, name (string, e.g. "rear strip", "front edge", "trellis lane"),
from_x, from_y, to_x, to_y (grid coordinates defining the zone rectangle),
purpose (string, e.g. "tall crops", "border flowers", "trellis"),
notes (string),
created_at
```

Zones are persistent rectangles within a bed that carry intent metadata. They don't constrain placement — they inform the AI's decisions.

### DB Migration: `bed_metadata` fields on beds table
Add columns:
- `sun_exposure` (string: "full", "partial", "shade")
- `wind_exposure` (string: "sheltered", "moderate", "exposed")
- `irrigation` (string: "drip", "manual", "sprinkler", "none")
- `front_edge` (string: "south", "north", "east", "west", "path" — which side faces the viewer/path)

These are simple descriptive fields the AI can read via `get_beds` and use for smarter placement.

### `ManageZonesTool`
- **Params:** `bed_name`, `action` ("create" | "list" | "delete"), plus zone fields for create
- **Action:** CRUD on bed_zones for the given bed
- **Returns:** zone list or confirmation

### `UpdateBedMetadataTool`
- **Params:** `bed_name`, plus optional metadata fields
- **Action:** Updates bed metadata fields
- **Returns:** updated bed summary

### Updates to `GetBedsTool`
Include zones and metadata in the bed data returned to the AI, so it can reason about "put tall crops in the rear zone" or "this bed faces south, put heat-lovers here".

---

## Theme 4: Operational Features

### Duplicate Detection in `DraftPlanTool`
Before storing the draft, check for overlapping assignments:
- Same variety + same bed already exists as an active plant → warn in the tool response: "Note: BB1 already has 3 Raf tomatoes. This draft adds 3 more. The user should confirm."
- Return a `warnings` array in the draft response so the frontend can display them.

### `DeduplicateBedTool`
- **Params:** `bed_name` (required)
- **Action:** Finds plants with identical `variety_name` + `crop_type` on the bed. Keeps the one with the most history (stage transitions), deletes the rest. Re-packs grid positions to eliminate gaps.
- **Returns:** count of duplicates removed, remaining plant summary

### Conflict Detection in System Prompt
Update the system prompt to instruct the AI: "Before calling draft_plan, check if any of your proposed assignments duplicate plants already on the target beds. If so, mention it and ask the user whether to replace or add."

### Plant Notes
The Plant model already has a `notes` field. Add a tool so the AI can set design-intent notes on plants.

### `SetPlantNotesTool`
- **Params:** `plant_id` or (`bed_name` + `variety_name`), `notes` (string)
- **Action:** Updates the plant's notes field
- **Returns:** confirmation

---

## System Prompt Updates

Add to the planner system prompt:

```
GARDEN MANAGEMENT: You now have tools to modify the garden directly:
- clear_bed, remove_plants, move_plant, update_plant — manage existing plants
- delete_succession_plan — remove succession schedules and their pending tasks
- place_row, place_column, place_single, place_border, place_fill — precise layout placement
- manage_zones, update_bed_metadata — bed organization and metadata
- deduplicate_bed — clean up duplicate assignments
- set_plant_notes — annotate plants with design intent

When redesigning:
1. First clear or deduplicate beds that need it
2. Then use placement tools for intentional layouts
3. Check for duplicates before adding new plants
4. Set notes on plants that have specific design intent (e.g., "let spill over edge")

These tools execute immediately — no draft/commit needed. Confirm with the user before bulk destructive operations like clear_bed.
```

---

## SSE Refresh Event

After any tool that modifies data (all CRUD and placement tools), the tool sets `Thread.current[:planner_needs_refresh] = true`. The PlannerService checks this after each tool call cycle and sends a `{ type: "refresh" }` SSE event. The frontend `AIDrawer` handles this by calling `onDraftApplied()` to refresh bed/plant data.

---

## Implementation Order

1. **Phase 1 — Core CRUD:** ClearBed, RemovePlants, MovePlant, UpdatePlant, DeleteSuccessionPlan + SSE refresh + prompt updates
2. **Phase 2 — Layout Primitives:** PlaceRow, PlaceColumn, PlaceSingle, PlaceBorder, PlaceFill
3. **Phase 3 — Bed Metadata & Zones:** Migration, ManageZones, UpdateBedMetadata, GetBedsTool updates
4. **Phase 4 — Operational:** DraftPlan duplicate warnings, DeduplicateBed, SetPlantNotes, prompt conflict detection

Each phase is independently deployable and useful.
