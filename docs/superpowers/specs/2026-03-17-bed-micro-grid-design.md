# Bed Micro-Grid Model Redesign — Design Spec

**Date:** 2026-03-17
**Status:** Approved
**Scope:** Replace Row→Slot→Plant model with a 10cm micro-grid on beds. Plants claim rectangular regions on the grid. Supports both individual plants (1 tomato in a 4×4 area) and mass plantings (200 carrots in a 1×10 strip).

---

## Overview

The current data model uses Row → Slot → Plant, where each slot holds one plant. This doesn't reflect physical reality: a 100×175cm bed with 11 tomatoes shouldn't be 1 row × 11 slots — it should be a 2D space where plants occupy areas proportional to their spacing needs.

The new model gives each bed a computed micro-grid (1 cell = 10cm × 10cm) and each plant a rectangular region on that grid, plus a quantity for mass plantings.

**This is a breaking change.** Existing plant grid positions are cleared (clean break). Row and Slot tables are dropped.

---

## Data Model Changes

### Bed Model

No new columns. Grid dimensions are computed from existing `length` and `width`:

```ruby
# In Bed model
def grid_cols
  w = (width || 100).to_f
  (w / 10.0).ceil.clamp(1, 50)
end

def grid_rows
  l = (length || 100).to_f
  (l / 10.0).ceil.clamp(1, 50)
end
```

Examples:
- BB1 (100×175cm) → 10 cols × 18 rows
- SB1 (150×75cm) → 15 cols × 8 rows
- Slope beds (50×50cm) → 5 cols × 5 rows

Clamped to 50 max to prevent absurdly large grids.

### Plant Model

**New columns** (migration):
- `grid_x` (Integer, nullable) — column position (0-based)
- `grid_y` (Integer, nullable) — row position (0-based)
- `grid_w` (Integer, default: 1) — width in cells
- `grid_h` (Integer, default: 1) — height in cells
- `quantity` (Integer, default: 1) — how many specimens in this region

**Dropped column:**
- `slot_id` — foreign key to slots table, set to null then column dropped

**Examples:**
| Plant | grid_x | grid_y | grid_w | grid_h | quantity | Meaning |
|-------|--------|--------|--------|--------|----------|---------|
| Raf tomato | 0 | 0 | 4 | 4 | 1 | 1 plant in 40×40cm area |
| Cherokee Purple | 4 | 0 | 4 | 4 | 1 | 1 plant next to Raf |
| Basil companion | 8 | 0 | 2 | 2 | 3 | 3 basil in 20×20cm |
| Carrot row | 0 | 8 | 1 | 10 | 200 | 200 seeds in 10×100cm strip |
| Lettuce patch | 2 | 8 | 4 | 4 | 16 | 16 lettuce in 40×40cm |

**Plants without grid position** (`grid_x` nil): belong to the garden but aren't placed on any bed yet (e.g., seedlings on a windowsill tracked via `indoor_station_id`).

### Dropped Tables

Migration drops `slots` table then `rows` table (in that order due to foreign keys).

### Indoor Stations

`indoor_station_id` on Plant remains unchanged. Indoor stations don't use the grid — they're for seedlings not yet placed in beds. A plant can have `indoor_station_id` set (it's on a shelf) and `grid_x` nil (not placed in a bed yet), then later get `grid_x/y` set and `indoor_station_id` cleared when transplanted out.

---

## Migration

Single migration that:

1. Adds `grid_x`, `grid_y`, `grid_w`, `grid_h`, `quantity` to plants
2. Sets `slot_id` to null on all plants
3. Drops `slots` table
4. Drops `rows` table
5. Removes `slot_id` column from plants

```ruby
Sequel.migration do
  up do
    # Add grid columns and bed FK
    alter_table(:plants) do
      add_column :grid_x, Integer
      add_column :grid_y, Integer
      add_column :grid_w, Integer, default: 1
      add_column :grid_h, Integer, default: 1
      add_column :quantity, Integer, default: 1
      add_foreign_key :bed_id, :beds, on_delete: :set_null
    end

    # Clear slot assignments (clean break)
    self[:plants].update(slot_id: nil)

    # Drop old tables
    alter_table(:plants) do
      drop_foreign_key :slot_id
    end
    drop_table(:slots)
    drop_table(:rows)
  end

  down do
    create_table(:rows) do
      primary_key :id
      foreign_key :bed_id, :beds, on_delete: :cascade
      Integer :position, null: false
      String :name
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:slots) do
      primary_key :id
      foreign_key :row_id, :rows, on_delete: :cascade
      Integer :position, null: false
      String :name
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    alter_table(:plants) do
      add_foreign_key :slot_id, :slots, on_delete: :set_null
      drop_foreign_key :bed_id
      drop_column :grid_x
      drop_column :grid_y
      drop_column :grid_w
      drop_column :grid_h
      drop_column :quantity
    end
    # Note: rollback is destructive — no plant position data is restored
  end
end
```

---

## Model Changes

### Bed Model

Remove `one_to_many :rows`. Add grid methods and plant relationship:

```ruby
class Bed < Sequel::Model
  many_to_one :garden

  def grid_cols
    (((width || 100).to_f) / 10.0).ceil.clamp(1, 50)
  end

  def grid_rows
    (((length || 100).to_f) / 10.0).ceil.clamp(1, 50)
  end

  one_to_many :plants  # plants placed on this bed via bed_id FK
end
```

Updated Plant model:
```ruby
many_to_one :bed  # replaces many_to_one :slot
```

### Row/Slot Models

Deleted entirely from `models/bed.rb`. The Row and Slot class definitions are removed.

### Arch/IndoorStation Models

Unchanged. IndoorStation plants continue to use `indoor_station_id`.

---

## SVG Rendering

Each bed card renders an inline SVG showing the micro-grid:

**Grid dimensions:** `viewBox="0 0 {grid_cols * 10} {grid_rows * 10}"` (in cm units for clean math)

**Layers (bottom to top):**
1. Bed outline — rect or polygon, filled with `canvas_color` at 30% opacity
2. Grid lines — faint 1px lines every 10 units (every cell), color `rgba(0,0,0,0.06)`
3. Plant regions — colored rounded rects at `(grid_x*10, grid_y*10, grid_w*10, grid_h*10)`
4. Plant labels — variety name centered in region, quantity badge if > 1

**Plant region appearance:**
- Fill: crop-type color (saturated variants)
- Stroke: 1px darker shade
- Corner radius: 3-4px
- Text: variety name centered, font sized proportionally to region
- Quantity badge: small circle in corner with count (if quantity > 1)
- Lifecycle indicator: subtle icon or colored dot for stage

**Empty cells:** transparent (grid lines visible). Tapping an empty area opens AI drawer.

**Responsive:** SVG scales to card width, `max-height: 300px`, `preserveAspectRatio="xMidYMid meet"`.

---

## Affected Code

### Files Modified

| File | Change |
|------|--------|
| `models/bed.rb` | Remove Row/Slot classes, add `grid_cols`/`grid_rows` methods, add `one_to_many :plants` |
| `models/plant.rb` | Remove `many_to_one :slot`, add `many_to_one :bed`, remove slot-related refs |
| `views/succession.erb` | Rewrite Beds tab SVG to use micro-grid rendering |
| `routes/succession.rb` | Update bed-timeline API, swap-slots endpoint, apply-layout endpoint for new model |
| `routes/plants.rb` | Update PATCH /plants/:id for grid placement instead of slot_id |
| `routes/beds.rb` | Full update: index builds bed data from `bed.plants` not rows/slots, show renders grid not row/slot lists, JSON API returns grid dimensions |
| `views/beds/index.erb` | Replace slot-based rendering with grid-based plant display |
| `views/beds/show.erb` | Full rewrite: replace row/slot iteration with micro-grid SVG (same renderer as succession.erb Beds tab) |
| `views/garden.erb` | Update canvas plant markers: replace `bed.rows`/`row.slots` iteration with `bed.plants` grid-based rendering, remove "Edit rows & slots" links |
| `services/planner_tools/draft_bed_layout_tool.rb` | Update payload to use grid coordinates |
| `services/planner_tools/get_beds_tool.rb` | Update to return grid dimensions instead of row/slot counts |
| `services/plan_committer.rb` | Update plant creation to use bed_id + grid coords instead of slot assignment |
| `test/routes/test_succession.rb` | Update bed-timeline and swap/layout tests to use grid model |
| `test/routes/test_plants.rb` | Update move test to use bed_id + grid coords instead of slot_id |
| `test/routes/test_beds.rb` | Update to not create Row/Slot |
| `test/routes/test_planner_routes.rb` | Update: creates Row/Slot objects that need to be removed |

### New Files

| File | Purpose |
|------|---------|
| `db/migrations/0XX_add_micro_grid.rb` | Migration: add grid columns, bed_id, drop rows/slots |

### Deleted Code

- `Row` class definition (in `models/bed.rb`)
- `Slot` class definition (in `models/bed.rb`)
- All Row/Slot creation in tests
- `bed.rows`, `row.slots`, `slot.plants` association chains throughout codebase

---

## Task Generation

The `quantity` field feeds into task descriptions:

- `quantity: 1` → "Sow 1 Raf tomato seed indoors"
- `quantity: 200` → "Sow 200 Nantes carrot seeds (direct sow, row in BB1)"
- `quantity: 16` → "Sow 16 Tre Colori lettuce seeds"

The existing TaskGenerator and plan committer use this when creating sow tasks.

---

## AI Planner Updates

The DraftBedLayoutTool payload changes to include grid coordinates:

```json
{
  "bed_name": "BB1",
  "action": "fill",
  "suggestions": [
    {
      "variety_name": "Raf",
      "crop_type": "tomato",
      "grid_x": 0, "grid_y": 0, "grid_w": 4, "grid_h": 4,
      "quantity": 1,
      "reason": "Needs 40cm spacing, placed in corner"
    },
    {
      "variety_name": "Nantes",
      "crop_type": "carrot",
      "grid_x": 0, "grid_y": 8, "grid_w": 1, "grid_h": 10,
      "quantity": 200,
      "reason": "Dense row planting along the edge"
    }
  ]
}
```

The GetBedsTool returns grid dimensions so the AI knows the available space:

```json
{
  "name": "BB1",
  "width_cm": 100,
  "length_cm": 175,
  "grid_cols": 10,
  "grid_rows": 18,
  "placed_plants": [
    { "variety_name": "Raf", "grid_x": 0, "grid_y": 0, "grid_w": 4, "grid_h": 4 }
  ]
}
```

---

## Design Constraints

- **10cm cell resolution** — fixed, not configurable per bed
- **No overlap validation in model** — overlap checking done at the view/API level, not enforced by DB constraints (too complex for SQLite)
- **Clean break** — existing slot assignments cleared, plants need to be re-placed
- **Mobile-first** — SVG grid tappable on phone, regions large enough to read
- **Existing tests** — many tests create Row/Slot objects and will need updating
