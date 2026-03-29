# Advanced Layout & Composition Tools — Design Spec

## Problem

The AI planner has basic CRUD and placement tools, but lacks the spatial intelligence for potager-style garden design. It can't align plants, mirror layouts between beds, fit rows into polygon shapes, or reason about empty space. Design intent (symmetry, focal points, visual rhythm) lives only in the user's head.

## Scope

9 capabilities, implemented as planner tools and prompt enhancements. Organized by complexity.

---

## 1. Zone-Relative Placement

### `PlaceInZoneTool`

Place plants within a named bed zone using a strategy.

- **Params:** `bed_name`, `zone_name`, `variety_name`, `crop_type`, `strategy`, `spacing` (optional), `source` (optional)
- **Strategies:**
  - `fill` — fill the zone at crop spacing, skip occupied cells
  - `row` — single horizontal row through the vertical center of the zone
  - `column` — single vertical column through the horizontal center
  - `border` — along zone edges (top, bottom, left, right)
  - `center` — single plant centered in the zone
- **Action:** Looks up zone coords (`from_x/y`, `to_x/y`), then places plants within that rectangle using the same occupied-cell-skipping logic as PlaceFillTool/PlaceBorderTool.
- **Returns:** count placed, zone name

---

## 2. Align & Distribute

### `AlignPlantsTool`

Align or distribute existing plants on a bed.

- **Params:** `bed_name`, `operation`, `filter_variety` (optional), `filter_crop_type` (optional)
- **Operations:**
  - `align-left` — set all matching plants' `grid_x` to the minimum `grid_x` in the group
  - `align-right` — set all to the maximum `grid_x + grid_w - own_grid_w`
  - `align-top` — set all `grid_y` to minimum `grid_y`
  - `align-bottom` — set all `grid_y` to maximum
  - `center-h` — center plants horizontally within bed width
  - `center-v` — center plants vertically within bed height
  - `distribute-h` — evenly space plants horizontally (fix y, spread x)
  - `distribute-v` — evenly space plants vertically (fix x, spread y)
  - `compact` — remove gaps, pack plants together top-left to bottom-right
- **Action:** Finds matching plants, computes new positions, updates `grid_x`/`grid_y`.
- **Filter:** If no filter given, operates on ALL active plants on the bed. If variety or crop_type given, only those.
- **Returns:** count of plants moved

---

## 3. Group Move & Resize

### `GroupEditTool`

Move or resize multiple plants at once by filter.

- **Params:** `bed_name`, `action` ("move" | "resize"), `filter_variety` (optional), `filter_crop_type` (optional), `dx` (optional), `dy` (optional), `grid_w` (optional), `grid_h` (optional)
- **Actions:**
  - `move` — shift all matching plants by `dx`, `dy` grid cells (relative move). Clamp to bed bounds.
  - `resize` — set `grid_w`/`grid_h` on all matching plants.
- **Returns:** count of plants modified

---

## 4. Seed-Row / Band Placement

### `PlaceBandTool`

Place a wide horizontal or vertical band of dense planting — like a seed row or a block of salad mix. Unlike PlaceRowTool (which places individual plants in a line), this creates a single plant record with a large rectangular footprint and high quantity.

- **Params:** `bed_name`, `variety_name`, `crop_type`, `orientation` ("horizontal" | "vertical"), `position` (grid row or column to start), `thickness` (band width in grid cells, default: crop height), `length` (band length in cells, default: full bed width/height), `quantity` (number of plants this band represents), `source` (optional)
- **Action:** Creates one Plant record with the band dimensions as `grid_w`/`grid_h` and the given quantity.
- **Returns:** plant summary with position and size

This is good for broadcast-sown crops (radish, mesclun, carrot) where individual plant positions don't matter — just the area.

---

## 5. Mirror & Copy

### `CopyLayoutTool`

Copy or mirror a bed's plant layout to another bed (or within the same bed).

- **Params:** `source_bed`, `target_bed`, `mode` ("copy" | "mirror-h" | "mirror-v"), `clear_target` (boolean, default false)
- **Modes:**
  - `copy` — duplicate all plants with same grid positions. If target bed is smaller, skip plants that don't fit.
  - `mirror-h` — horizontal mirror (flip x: `new_x = target_cols - source_x - source_w`)
  - `mirror-v` — vertical mirror (flip y: `new_y = target_rows - source_y - source_h`)
- **Action:** Optionally clears target bed first. Creates new Plant records on target bed with transformed positions. Uses source plants' variety/crop/spacing.
- **Returns:** count of plants copied

---

## 6. Polygon-Aware Row Fitting

This is an enhancement to existing placement tools, not a new tool.

### Point-in-Polygon Helper

Add a `Bed#point_in_polygon?(x, y)` method that returns true if the grid cell center falls within the bed's polygon shape. For rectangular beds, always returns true.

```ruby
def point_in_polygon?(grid_x, grid_y)
  return true unless polygon?
  pts = canvas_points_array
  return true if pts.length < 3
  # Convert grid coords to canvas coords (grid cell = 5cm)
  # Use ray-casting algorithm
  ...
end
```

### Update Placement Tools

Add polygon checking to PlaceRowTool, PlaceColumnTool, PlaceFillTool, PlaceBorderTool, and PlaceInZoneTool. Before placing a plant at `(x, y)`, call `bed.point_in_polygon?(x, y)` and skip if outside.

This means a crescent-shaped bed won't get plants placed in the empty corners of its bounding rectangle.

---

## 7. Negative-Space Planning

### `GetEmptySpaceTool`

Report where empty space is on a bed.

- **Params:** `bed_name`
- **Action:** Build the occupied grid, then find contiguous empty rectangular regions (greedy largest-rectangle algorithm). Also compute total empty cell count and percentage.
- **Returns:** JSON summary:
  ```
  Total: 45% empty (216 of 480 cells)
  Largest gaps:
  - (0,0)→(12,8): 96 cells — could fit 4 tomatoes or 24 radishes
  - (18,20)→(24,30): 60 cells — could fit 2 squash
  ```
- **Prompt guidance:** The AI uses this to reason about what fits where before placing. "Let me check what space is available..." → calls GetEmptySpace → proposes placement.

---

## 8. Decorative Composition Rules

This is a **system prompt enhancement**, not a tool. Add to the planner system prompt:

```
DESIGN PRINCIPLES for potager/ornamental layouts:
- BACK TO FRONT: Tall crops (tomato, corn, sunflower) go in rear rows.
  Medium crops in middle. Low/trailing crops at front edge.
- SYMMETRY: When the user wants a "beautiful" or "potager" layout,
  mirror key structural plants (e.g., tomatoes at equal spacing).
  Use place_border for symmetric edge planting.
- FOCAL POINTS: Place one bold specimen (large squash, artichoke,
  sunflower) at center or front corners as a visual anchor.
- COLOR RHYTHM: Alternate leaf textures and colors. Don't cluster
  all green together — interleave with purple (basil, kale), silver
  (artemisia), or flowering herbs.
- EDGE DISCIPLINE: Borders should use one variety consistently along
  an edge. Don't mix 3 varieties in the front row.
- REPETITION: Repeat the same variety at regular intervals for rhythm.
  Three identical plants in a diagonal reads as intentional design.
```

---

## 9. Higher-Fidelity Bed Preview

This is **frontend work** in `BedCanvas.tsx` and related components.

### Improvements:
1. **Plant labels** — show variety name (or crop icon) inside each plant rectangle when there's room. Currently just colored rectangles.
2. **Quantity badge** — for plants with `quantity > 1`, show a small badge count.
3. **Notes indicator** — show a small icon (speech bubble) on plants that have notes set.
4. **Polygon clipping** — clip the grid and plants to the actual polygon shape using SVG `<clipPath>` with the polygon points, so plants outside the polygon are visually hidden.
5. **Empty space highlight** — optional mode showing unoccupied cells in a subtle pattern (diagonal lines or lighter shade).

### Implementation:
- Polygon clipping: wrap the grid/plants SVG group in a `<clipPath>` derived from `bed.canvas_points`
- Plant labels: render text inside `PlantRect` when `grid_w * CELL >= 20` (enough room)
- Quantity badge: small circle in top-right corner of PlantRect
- Notes indicator: small icon in bottom-right corner

---

## Implementation Order

1. **Phase A — Core spatial tools:** PlaceInZone, AlignPlants, GroupEdit, PlaceBand (4 tools)
2. **Phase B — Advanced layout:** CopyLayout, GetEmptySpace, polygon helper + placement updates (2 tools + enhancement)
3. **Phase C — Intelligence:** Decorative composition rules (prompt only)
4. **Phase D — Frontend:** Bed preview enhancements (BedCanvas changes)

Each phase is independently deployable.
