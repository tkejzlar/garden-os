# Bed Micro-Grid Model Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Row→Slot→Plant model with a 10cm micro-grid on beds. Plants claim rectangular regions via `grid_x/y/w/h` + `bed_id`. Row and Slot tables are dropped entirely.

**Architecture:** Single migration adds grid columns + `bed_id` to plants, drops `slot_id`, drops `rows` and `slots` tables. All code referencing Row/Slot/slot_id is updated to use `bed.plants` + grid coordinates. SVG rendering draws beds as proportional grids with plant regions.

**Tech Stack:** Ruby/Sinatra, Sequel ORM, ERB, inline SVG, Alpine.js

**Spec:** `docs/superpowers/specs/2026-03-17-bed-micro-grid-design.md`

---

## File Structure

```
New:
├── db/migrations/014_add_micro_grid.rb    # Migration: grid columns, bed_id, drop rows/slots

Modified (models):
├── models/bed.rb                          # Remove Row/Slot classes, add grid methods, one_to_many :plants
├── models/plant.rb                        # Remove many_to_one :slot, add many_to_one :bed

Modified (routes):
├── routes/beds.rb                         # Rewrite for grid model (no rows/slots)
├── routes/plants.rb                       # PATCH uses bed_id + grid coords instead of slot_id
├── routes/succession.rb                   # Update bed-timeline, swap, apply-layout, occupancy

Modified (views):
├── views/beds/show.erb                    # Rewrite: micro-grid SVG instead of row/slot list
├── views/beds/index.erb                   # Update: no slot references
├── views/garden.erb                       # Update: bed.plants instead of bed.rows→slots
├── views/succession.erb                   # Update: Beds tab SVG uses grid model

Modified (services):
├── services/plan_committer.rb             # Create plants with bed_id + grid coords, no Row/Slot
├── services/planner_tools/get_beds_tool.rb    # Return grid dimensions + placed plants
├── services/planner_tools/get_plants_tool.rb  # Use plant.bed instead of slot.row.bed
├── services/planner_tools/draft_bed_layout_tool.rb # Already uses grid coords (no change needed)
├── services/planner_tools/draft_plan_tool.rb  # Update description (no more "rows/slots auto-created")

Modified (tests):
├── test/routes/test_beds.rb               # Remove Row/Slot creation
├── test/routes/test_plants.rb             # Use bed_id + grid coords
├── test/routes/test_succession.rb         # Update bed-timeline + layout tests
├── test/routes/test_planner_routes.rb     # Remove Row/Slot creation
├── test/services/test_plan_committer.rb   # Update for grid model
```

---

## Chunk 1: Migration + Model Changes

### Task 1: Create Migration

**Files:**
- Create: `db/migrations/014_add_micro_grid.rb`

- [ ] **Step 1: Determine migration number**

Run: `ls db/migrations/ | tail -1`
Use the next number after the last migration file.

- [ ] **Step 2: Write the migration**

Create `db/migrations/014_add_micro_grid.rb` (adjust number if needed):

```ruby
Sequel.migration do
  up do
    # Add grid columns and bed FK to plants
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

    # Drop old structure
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
      String :name
      Integer :position, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:slots) do
      primary_key :id
      foreign_key :row_id, :rows, on_delete: :cascade
      String :name
      Integer :position, null: false
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

- [ ] **Step 3: Run migration**

Run: `ruby -e "require_relative 'config/database'; Sequel::Migrator.run(DB, 'db/migrations')"`
Expected: Migration completes, rows/slots tables gone, plants table has new columns.

- [ ] **Step 4: Verify schema**

Run: `ruby -e "require_relative 'config/database'; puts DB.schema(:plants).map { |c| c[0] }.inspect"`
Expected: Includes `:grid_x, :grid_y, :grid_w, :grid_h, :quantity, :bed_id`, does NOT include `:slot_id`

- [ ] **Step 5: Commit**

```bash
git add db/migrations/014_add_micro_grid.rb
git commit -m "feat: migration — add grid columns + bed_id to plants, drop rows/slots"
```

---

### Task 2: Update Bed Model

**Files:**
- Modify: `models/bed.rb`

- [ ] **Step 1: Rewrite models/bed.rb**

Remove the `Row` and `Slot` class definitions. Remove `one_to_many :rows` from Bed. Add grid methods and `one_to_many :plants`. Keep Arch and IndoorStation unchanged.

The full new file:

```ruby
require "json"
require_relative "../config/database"

class Bed < Sequel::Model
  many_to_one :garden
  one_to_many :plants

  def grid_cols
    (((width || 100).to_f) / 10.0).ceil.clamp(1, 50)
  end

  def grid_rows
    (((length || 100).to_f) / 10.0).ceil.clamp(1, 50)
  end

  def canvas_points_array
    return [] unless canvas_points
    JSON.parse(canvas_points)
  rescue JSON::ParserError
    []
  end

  def canvas_points_array=(pts)
    self.canvas_points = pts.nil? || pts.empty? ? nil : pts.to_json
  end

  def placed?
    !canvas_x.nil?
  end

  def polygon?
    !canvas_points.nil?
  end
end

class Arch < Sequel::Model
  many_to_one :garden
end

class IndoorStation < Sequel::Model
  many_to_one :garden
end
```

- [ ] **Step 2: Verify model loads**

Run: `ruby -e "require_relative 'config/database'; require_relative 'models/bed'; puts Bed.first&.grid_cols"`
Expected: Prints a number (e.g., 10 for BB1 with width=100)

- [ ] **Step 3: Commit**

```bash
git add models/bed.rb
git commit -m "feat: bed model — remove Row/Slot, add grid methods, one_to_many :plants"
```

---

### Task 3: Update Plant Model

**Files:**
- Modify: `models/plant.rb`

- [ ] **Step 1: Update plant associations**

In `models/plant.rb`, find and remove:
```ruby
many_to_one :slot
```

Add:
```ruby
many_to_one :bed
```

- [ ] **Step 2: Verify model loads**

Run: `ruby -e "require_relative 'config/database'; require_relative 'models/bed'; require_relative 'models/plant'; puts Plant.first&.bed_id"`
Expected: Prints nil (no plants have bed_id assigned yet)

- [ ] **Step 3: Commit**

```bash
git add models/plant.rb
git commit -m "feat: plant model — replace many_to_one :slot with many_to_one :bed"
```

---

## Chunk 2: Routes + Services

### Task 4: Update routes/beds.rb

**Files:**
- Modify: `routes/beds.rb`
- Modify: `test/routes/test_beds.rb`

- [ ] **Step 1: Update test to use grid model**

In `test/routes/test_beds.rb`, find the test setup that creates Row/Slot objects (around lines 14-16). Replace with direct plant creation using bed_id + grid coords:

Find:
```ruby
row = Row.create(bed_id: bed.id, name: "Row A", position: 1)
slot = Slot.create(row_id: row.id, name: "Pos 1", position: 1)
Plant.create(variety_name: "Raf", crop_type: "tomato", slot_id: slot.id, garden_id: @garden.id)
```

Replace with:
```ruby
Plant.create(
  variety_name: "Raf", crop_type: "tomato",
  bed_id: bed.id, grid_x: 0, grid_y: 0, grid_w: 4, grid_h: 4, quantity: 1,
  lifecycle_stage: "seedling", garden_id: @garden.id
)
```

- [ ] **Step 2: Rewrite routes/beds.rb**

Replace the full file. The new version uses `bed.plants` instead of row/slot chains:

```ruby
require "json"

module Routes
  def self.registered(app)
    # Beds routes are registered via app.rb
  end
end

# GET /beds — index
get "/beds" do
  @beds = Bed.where(garden_id: @current_garden.id).eager(:plants).all
  @arches = Arch.where(garden_id: @current_garden.id).all
  @indoor_stations = IndoorStation.where(garden_id: @current_garden.id).all
  erb :"beds/index"
end

# GET /beds/:id — show
get "/beds/:id" do
  @bed = Bed[params[:id].to_i]
  halt 404, "Bed not found" unless @bed && @bed.garden_id == @current_garden.id
  @plants = Plant.where(bed_id: @bed.id).exclude(lifecycle_stage: "done").all
  erb :"beds/show"
end

# GET /api/beds — JSON
get "/api/beds" do
  content_type :json
  beds = Bed.where(garden_id: @current_garden.id).eager(:plants).all
  beds.map do |bed|
    active_plants = bed.plants.reject { |p| p.lifecycle_stage == "done" }
    {
      id: bed.id,
      name: bed.name,
      width_cm: bed.width,
      length_cm: bed.length,
      grid_cols: bed.grid_cols,
      grid_rows: bed.grid_rows,
      canvas_color: bed.canvas_color,
      plants: active_plants.map do |p|
        {
          id: p.id,
          variety_name: p.variety_name,
          crop_type: p.crop_type,
          lifecycle_stage: p.lifecycle_stage,
          grid_x: p.grid_x, grid_y: p.grid_y,
          grid_w: p.grid_w, grid_h: p.grid_h,
          quantity: p.quantity
        }
      end
    }
  end.to_json
end
```

- [ ] **Step 3: Run beds tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_beds.rb`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add routes/beds.rb test/routes/test_beds.rb
git commit -m "feat: rewrite routes/beds.rb for grid model — no Row/Slot"
```

---

### Task 5: Update routes/plants.rb

**Files:**
- Modify: `routes/plants.rb`
- Modify: `test/routes/test_plants.rb`

- [ ] **Step 1: Update test**

In `test/routes/test_plants.rb`, find `test_move_plant_to_new_slot` (around line 94). Replace with grid-based move:

```ruby
def test_move_plant_on_grid
  bed = Bed.create(garden_id: @garden.id, name: "TestBed", width: 100, length: 100)
  plant = Plant.create(
    garden_id: @garden.id, bed_id: bed.id,
    variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seedling",
    grid_x: 0, grid_y: 0, grid_w: 4, grid_h: 4
  )

  patch "/plants/#{plant.id}", { grid_x: 5, grid_y: 5 }.to_json, { "CONTENT_TYPE" => "application/json" }
  assert_equal 200, last_response.status

  plant.refresh
  assert_equal 5, plant.grid_x
  assert_equal 5, plant.grid_y
end
```

Also update any other tests in this file that create Row/Slot objects — search for `Row.create` or `Slot.create` and replace with direct bed_id + grid coord plant creation.

- [ ] **Step 2: Update PATCH /plants/:id endpoint**

In `routes/plants.rb`, find the `patch "/plants/:id"` block. Replace the slot_id handling with grid coordinate handling:

Find the section:
```ruby
if body["slot_id"]
  slot = Slot[body["slot_id"].to_i]
  halt 404, json(error: "Slot not found") unless slot
  halt 403, json(error: "Slot not in your garden") unless slot.row.bed.garden_id == @current_garden.id
  plant.update(slot_id: slot.id, updated_at: Time.now)
end
```

Replace with:
```ruby
updates = {}
updates[:bed_id] = body["bed_id"].to_i if body["bed_id"]
updates[:grid_x] = body["grid_x"].to_i if body["grid_x"]
updates[:grid_y] = body["grid_y"].to_i if body["grid_y"]
updates[:grid_w] = body["grid_w"].to_i if body["grid_w"]
updates[:grid_h] = body["grid_h"].to_i if body["grid_h"]
updates[:quantity] = body["quantity"].to_i if body["quantity"]
updates[:updated_at] = Time.now if updates.any?

if updates[:bed_id]
  bed = Bed[updates[:bed_id]]
  halt 404, json(error: "Bed not found") unless bed
  halt 403, json(error: "Not your bed") unless bed.garden_id == @current_garden.id
end

plant.update(updates) if updates.any?
```

- [ ] **Step 3: Run plant tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_plants.rb`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add routes/plants.rb test/routes/test_plants.rb
git commit -m "feat: PATCH /plants/:id uses grid coords instead of slot_id"
```

---

### Task 6: Update routes/succession.rb

**Files:**
- Modify: `routes/succession.rb`
- Modify: `test/routes/test_succession.rb`

- [ ] **Step 1: Update tests**

In `test/routes/test_succession.rb`:

**Update `test_bed_timeline_api`** — replace Row/Slot creation with grid plant:

Find:
```ruby
bed = Bed.create(garden_id: @garden.id, name: "BB1")
row = Row.create(bed_id: bed.id, position: 1, name: "R1")
slot = Slot.create(row_id: row.id, position: 1, name: "S1")
plant = Plant.create(
  garden_id: @garden.id, slot_id: slot.id,
```

Replace with:
```ruby
bed = Bed.create(garden_id: @garden.id, name: "BB1", width: 100, length: 175)
plant = Plant.create(
  garden_id: @garden.id, bed_id: bed.id,
  grid_x: 0, grid_y: 0, grid_w: 4, grid_h: 4,
```

Keep the rest of the test assertions but update `total_slots` assertion — the API no longer returns `total_slots`. Replace with `grid_cols` and `grid_rows`:

```ruby
assert_equal 10, bed_data["grid_cols"]
assert_equal 18, bed_data["grid_rows"]
```

**Update `test_swap_slots`** — replace with grid-based swap test:

```ruby
def test_swap_plants
  bed = Bed.create(garden_id: @garden.id, name: "SwapBed", width: 100, length: 100)
  plant_a = Plant.create(garden_id: @garden.id, bed_id: bed.id, variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seedling", grid_x: 0, grid_y: 0, grid_w: 4, grid_h: 4)
  plant_b = Plant.create(garden_id: @garden.id, bed_id: bed.id, variety_name: "Basil", crop_type: "herb", lifecycle_stage: "seedling", grid_x: 5, grid_y: 0, grid_w: 2, grid_h: 2)

  patch "/beds/#{bed.id}/swap-plants", {
    plant_a: plant_a.id, plant_b: plant_b.id
  }.to_json, { "CONTENT_TYPE" => "application/json" }
  assert_equal 200, last_response.status

  plant_a.refresh; plant_b.refresh
  # Plants swap grid positions
  assert_equal 5, plant_a.grid_x
  assert_equal 0, plant_b.grid_x
end
```

**Update `test_apply_layout_fill`** — use grid coords:

```ruby
def test_apply_layout_fill
  bed = Bed.create(garden_id: @garden.id, name: "FillBed", width: 100, length: 100)

  post "/beds/#{bed.id}/apply-layout", {
    action: "fill",
    suggestions: [
      { variety_name: "Cherry Belle", crop_type: "radish", grid_x: 0, grid_y: 0, grid_w: 1, grid_h: 10, quantity: 200 }
    ]
  }.to_json, { "CONTENT_TYPE" => "application/json" }

  assert_equal 200, last_response.status

  plant = Plant.where(bed_id: bed.id).first
  assert plant
  assert_equal "Cherry Belle", plant.variety_name
  assert_equal 0, plant.grid_x
  assert_equal 200, plant.quantity
end
```

- [ ] **Step 2: Update bed-timeline endpoint**

In `routes/succession.rb`, find the `get "/api/plan/bed-timeline"` block. Replace the row/slot-based occupancy calculation with grid-based:

Replace the beds mapping (the `beds = Bed.where(...).eager(rows: {slots: :plants}).all.map` block) with:

```ruby
beds = Bed.where(garden_id: @current_garden.id).eager(:plants).all.map do |bed|
  active_plants = bed.plants.reject { |p| p.lifecycle_stage == "done" }

  # Monthly occupancy: count placed plants active per month
  occupancy = months.map do |month_str|
    year, month = month_str.split("-").map(&:to_i)
    month_start = Date.new(year, month, 1)
    month_end = (month_start >> 1) - 1

    filled = active_plants.count do |plant|
      start_date = plant.sow_date || plant.created_at&.to_date || today
      end_date = plant.lifecycle_stage == "done" ? (plant.updated_at&.to_date || today) : season_end
      start_date <= month_end && end_date >= month_start
    end

    { month: month_str, filled: filled }
  end

  # Group plants by crop type
  crops = active_plants.group_by(&:crop_type).map do |crop, crop_plants|
    varieties = crop_plants.map(&:variety_name).uniq
    start_date = crop_plants.map { |p| p.sow_date || p.created_at&.to_date }.compact.min
    {
      crop: crop,
      varieties: varieties,
      plant_count: crop_plants.sum(&:quantity),
      periods: [{
        start: start_date&.to_s,
        end: nil,
        status: crop_plants.any? { |p| %w[planted_out producing].include?(p.lifecycle_stage) } ? "planted" : "growing"
      }]
    }
  end

  # Add succession plan projections (unchanged logic)
  SuccessionPlan.where(garden_id: @current_garden.id).all.each do |plan|
    next unless plan.target_beds_list.include?(bed.name)
    existing_tasks = Task.where(garden_id: @current_garden.id, task_type: "sow", status: "done")
      .where(Sequel.like(:title, "%#{plan.crop}%")).count

    (existing_tasks...plan.total_planned_sowings).each do |i|
      sow_date = plan.next_sowing_date(i)
      next unless sow_date
      crops << {
        crop: plan.crop, varieties: plan.varieties_list, plant_count: 1,
        periods: [{ start: sow_date.to_s, end: nil, status: "planned" }]
      }
    end
  end

  {
    bed_id: bed.id,
    bed_name: bed.name,
    grid_cols: bed.grid_cols,
    grid_rows: bed.grid_rows,
    occupancy: occupancy,
    crops: crops
  }
end
```

- [ ] **Step 3: Update swap-slots → swap-plants endpoint**

Rename and rewrite. Find the `patch "/beds/:id/swap-slots"` block. Replace entirely:

```ruby
patch "/beds/:id/swap-plants" do
  content_type :json
  bed = Bed[params[:id].to_i]
  halt 404, json(error: "Bed not found") unless bed
  halt 403, json(error: "Not your bed") unless bed.garden_id == @current_garden.id

  request.body.rewind
  body = begin
    JSON.parse(request.body.read)
  rescue
    halt 400, json(error: "Invalid JSON")
  end

  plant_a = Plant[body["plant_a"].to_i]
  plant_b = Plant[body["plant_b"].to_i]
  halt 404, json(error: "Plant not found") unless plant_a && plant_b
  halt 422, json(error: "Plants not on this bed") unless plant_a.bed_id == bed.id && plant_b.bed_id == bed.id

  # Swap grid positions
  DB.transaction do
    ax, ay, aw, ah = plant_a.grid_x, plant_a.grid_y, plant_a.grid_w, plant_a.grid_h
    plant_a.update(grid_x: plant_b.grid_x, grid_y: plant_b.grid_y, grid_w: plant_b.grid_w, grid_h: plant_b.grid_h, updated_at: Time.now)
    plant_b.update(grid_x: ax, grid_y: ay, grid_w: aw, grid_h: ah, updated_at: Time.now)
  end

  json(ok: true)
end
```

- [ ] **Step 4: Update apply-layout endpoint**

Find the `post "/beds/:id/apply-layout"` block. Replace entirely:

```ruby
post "/beds/:id/apply-layout" do
  content_type :json
  bed = Bed[params[:id].to_i]
  halt 404, json(error: "Bed not found") unless bed
  halt 403, json(error: "Not your bed") unless bed.garden_id == @current_garden.id

  request.body.rewind
  body = begin
    JSON.parse(request.body.read)
  rescue
    halt 400, json(error: "Invalid JSON")
  end

  action = body["action"]

  case action
  when "fill", "plan_full"
    suggestions = body["suggestions"] || []
    created = suggestions.map do |s|
      Plant.create(
        garden_id: @current_garden.id,
        bed_id: bed.id,
        variety_name: s["variety_name"],
        crop_type: s["crop_type"],
        grid_x: s["grid_x"]&.to_i || 0,
        grid_y: s["grid_y"]&.to_i || 0,
        grid_w: s["grid_w"]&.to_i || 1,
        grid_h: s["grid_h"]&.to_i || 1,
        quantity: s["quantity"]&.to_i || 1,
        lifecycle_stage: "seed_packet"
      )
    end
    json(ok: true, created: created.count)

  when "rearrange"
    moves = body["moves"] || []
    DB.transaction do
      moves.each do |m|
        plant = Plant[m["plant_id"].to_i]
        next unless plant && plant.garden_id == @current_garden.id && plant.bed_id == bed.id
        plant.update(
          grid_x: m["grid_x"]&.to_i,
          grid_y: m["grid_y"]&.to_i,
          grid_w: m["grid_w"]&.to_i || plant.grid_w,
          grid_h: m["grid_h"]&.to_i || plant.grid_h,
          updated_at: Time.now
        )
      end
    end
    json(ok: true)

  else
    halt 400, json(error: "Unknown action: #{action}")
  end
end
```

- [ ] **Step 5: Run succession tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add routes/succession.rb test/routes/test_succession.rb
git commit -m "feat: succession routes use grid model — bed-timeline, swap-plants, apply-layout"
```

---

### Task 7: Update Services

**Files:**
- Modify: `services/plan_committer.rb`
- Modify: `services/planner_tools/get_beds_tool.rb`
- Modify: `services/planner_tools/get_plants_tool.rb`
- Modify: `services/planner_tools/draft_plan_tool.rb`
- Modify: `test/services/test_plan_committer.rb`
- Modify: `test/routes/test_planner_routes.rb`

- [ ] **Step 1: Update plan_committer.rb**

Find lines 31-52 (the Row/Slot auto-creation logic). Replace with direct plant creation using bed_id + grid coords:

Find the section that does:
```ruby
row = Row.where(bed_id: bed.id).first
```

Replace the entire assignment-processing block with:

```ruby
# Place plants on bed grid
existing_plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
next_y = existing_plants.any? ? existing_plants.map { |p| (p.grid_y || 0) + (p.grid_h || 1) }.max : 0

assignments_for_bed.each_with_index do |a, i|
  grid_w = 3  # Default: 30cm wide
  grid_h = 3  # Default: 30cm tall
  grid_x = (i % (bed.grid_cols / grid_w)) * grid_w
  grid_y = next_y + (i / (bed.grid_cols / grid_w)) * grid_h

  Plant.create(
    garden_id: garden_id,
    bed_id: bed.id,
    variety_name: a["variety_name"],
    crop_type: a["crop_type"],
    source: a["source"],
    lifecycle_stage: "seed_packet",
    grid_x: grid_x.clamp(0, bed.grid_cols - 1),
    grid_y: grid_y.clamp(0, bed.grid_rows - 1),
    grid_w: grid_w,
    grid_h: grid_h,
    quantity: a["quantity"]&.to_i || 1
  )
end
```

- [ ] **Step 2: Update get_beds_tool.rb**

Replace the row/slot serialization with grid-based output. Find the `beds.map` block and replace:

```ruby
beds.map do |bed|
  active_plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
  {
    name: bed.name,
    width_cm: bed.width,
    length_cm: bed.length,
    grid_cols: bed.grid_cols,
    grid_rows: bed.grid_rows,
    placed_plants: active_plants.map do |p|
      {
        id: p.id,
        variety_name: p.variety_name,
        crop_type: p.crop_type,
        lifecycle_stage: p.lifecycle_stage,
        grid_x: p.grid_x, grid_y: p.grid_y,
        grid_w: p.grid_w, grid_h: p.grid_h,
        quantity: p.quantity
      }
    end
  }
end
```

- [ ] **Step 3: Update get_plants_tool.rb**

Find the slot/row/bed chain (lines 11-13):
```ruby
slot = p.slot
row = slot&.row
bed = row&.bed
```

Replace with:
```ruby
bed = p.bed
```

Update the output hash to include grid position instead of row/slot names:
```ruby
location: bed ? "#{bed.name} (#{p.grid_x},#{p.grid_y} #{p.grid_w}x#{p.grid_h})" : (p.indoor_station_id ? "indoor" : "unplaced")
```

- [ ] **Step 4: Update draft_plan_tool.rb**

In the `param :payload` description, replace `"Rows/slots are auto-created"` with `"Plants are placed on the bed grid with grid_x/y/w/h coordinates"`.

- [ ] **Step 5: Update test_plan_committer.rb**

Find the setup that creates Row/Slot (lines 9-11):
```ruby
row = Row.create(bed_id: @bed.id, name: "A", position: 1)
Slot.create(row_id: row.id, name: "Pos 1", position: 1)
Slot.create(row_id: row.id, name: "Pos 2", position: 2)
```

Remove these lines. Add width/length to bed creation if missing:
```ruby
@bed = Bed.create(garden_id: @garden.id, name: "BB1", width: 100, length: 175)
```

Update the assertion (line 27):
```ruby
assert_equal @bed.id, Plant.first.slot.row.bed.id
```
Replace with:
```ruby
assert_equal @bed.id, Plant.first.bed_id
```

- [ ] **Step 6: Update test_planner_routes.rb**

Find Row/Slot creation (lines 31-32):
```ruby
row = Row.create(bed_id: bed.id, name: "A", position: 1)
Slot.create(row_id: row.id, name: "Pos1", position: 1)
```

Remove these lines. Add width/length to bed creation. Update any assertions that reference slot_position.

- [ ] **Step 7: Run all tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`
Expected: Many tests may still fail due to view changes (Task 8-10). Services + routes tests should pass.

- [ ] **Step 8: Commit**

```bash
git add services/ test/services/ test/routes/test_planner_routes.rb
git commit -m "feat: services use grid model — plan_committer, get_beds/plants tools"
```

---

## Chunk 3: Views

### Task 8: Update views/beds/show.erb and views/beds/index.erb

**Files:**
- Modify: `views/beds/show.erb`
- Modify: `views/beds/index.erb`

- [ ] **Step 1: Rewrite views/beds/show.erb**

Replace the entire row/slot iteration with a micro-grid SVG. Read the current file first, then replace the content section with:

```erb
<h2><%= @bed.name %></h2>
<p style="color: var(--text-secondary); font-size: 12px; margin-bottom: 12px;">
  <%= @bed.width&.round %>×<%= @bed.length&.round %>cm
  · <%= @bed.grid_cols %>×<%= @bed.grid_rows %> grid
  · <%= @plants.count %> plants
</p>

<% bed_w = @bed.grid_cols * 10; bed_h = @bed.grid_rows * 10 %>
<svg viewBox="0 0 <%= bed_w %> <%= bed_h %>" style="width: 100%; max-height: 400px; min-height: 120px; background: white; border-radius: 8px;" preserveAspectRatio="xMidYMid meet">
  <!-- Bed outline -->
  <rect x="0" y="0" width="<%= bed_w %>" height="<%= bed_h %>" rx="4"
    fill="<%= @bed.canvas_color || '#e8e4df' %>" fill-opacity="0.3"
    stroke="<%= @bed.canvas_color || '#e8e4df' %>" stroke-width="2"/>

  <!-- Grid lines -->
  <% (1...@bed.grid_cols).each do |i| %>
    <line x1="<%= i*10 %>" y1="0" x2="<%= i*10 %>" y2="<%= bed_h %>" stroke="rgba(0,0,0,0.06)" stroke-width="0.5"/>
  <% end %>
  <% (1...@bed.grid_rows).each do |i| %>
    <line x1="0" y1="<%= i*10 %>" x2="<%= bed_w %>" y2="<%= i*10 %>" stroke="rgba(0,0,0,0.06)" stroke-width="0.5"/>
  <% end %>

  <!-- Plant regions -->
  <% @plants.each do |plant| %>
    <%
      px = (plant.grid_x || 0) * 10
      py = (plant.grid_y || 0) * 10
      pw = (plant.grid_w || 1) * 10
      ph = (plant.grid_h || 1) * 10
      fill = case plant.crop_type.to_s.downcase
        when 'tomato', 'pepper', 'eggplant' then '#fecaca'
        when 'lettuce', 'spinach', 'chard', 'kale' then '#bbf7d0'
        when 'herb', 'basil' then '#a7f3d0'
        when 'flower' then '#fef08a'
        when 'cucumber', 'squash', 'melon', 'zucchini' then '#bae6fd'
        else '#e5e7eb'
      end
    %>
    <a href="/plants/<%= plant.id %>">
      <rect x="<%= px + 1 %>" y="<%= py + 1 %>" width="<%= pw - 2 %>" height="<%= ph - 2 %>"
        rx="3" fill="<%= fill %>" stroke="#d1d5db" stroke-width="0.5"/>
      <text x="<%= px + pw/2 %>" y="<%= py + ph/2 - 2 %>" text-anchor="middle"
        font-size="<%= [pw * 0.15, ph * 0.2, 10].min %>" font-weight="500" fill="#1a2e05">
        <%= plant.variety_name.length > 12 ? plant.variety_name[0..10] + '..' : plant.variety_name %>
      </text>
      <% if plant.quantity > 1 %>
        <text x="<%= px + pw/2 %>" y="<%= py + ph/2 + 8 %>" text-anchor="middle"
          font-size="<%= [pw * 0.12, 8].min %>" fill="#6b7280">×<%= plant.quantity %></text>
      <% else %>
        <text x="<%= px + pw/2 %>" y="<%= py + ph/2 + 8 %>" text-anchor="middle"
          font-size="<%= [pw * 0.12, 8].min %>" fill="#6b7280"><%= plant.lifecycle_stage.tr('_', ' ') %></text>
      <% end %>
    </a>
  <% end %>
</svg>

<div style="margin-top: 12px;">
  <a href="/beds" style="color: var(--green-900); font-size: 13px;">← Back to beds</a>
</div>
```

- [ ] **Step 2: Update views/beds/index.erb**

Read the current file. Replace any references to `rd[:slots]`, `sd[:slot]` with grid-based plant data. The index page should show each bed as a card with plant count and a mini SVG preview. Simplify — the detailed SVG is on the show page.

- [ ] **Step 3: Run beds tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_beds.rb`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add views/beds/
git commit -m "feat: beds views use micro-grid SVG — show.erb rewritten, index.erb updated"
```

---

### Task 9: Update views/succession.erb Beds Tab

**Files:**
- Modify: `views/succession.erb` (Beds tab section + occupancy pills)

- [ ] **Step 1: Replace the Beds tab section**

Find the `<div x-show="tab === 'beds'"` block (around lines 244-390). Replace the outdoor beds section with micro-grid SVG rendering:

The occupancy pills change from slot-based to plant-count:
```erb
<% active = bed.plants.count { |p| p.lifecycle_stage != "done" } %>
<span style="color: var(--text-secondary);"><%= active %> plants</span>
```

Each bed card renders the micro-grid SVG (same pattern as beds/show.erb but compact):

```erb
<% beds.each do |bed| %>
  <%
    active_plants = bed.plants.reject { |p| p.lifecycle_stage == "done" }
    bed_w = bed.grid_cols * 10
    bed_h = bed.grid_rows * 10
    canvas_color = bed.canvas_color || '#e8e4df'
  %>
  <div data-bed-name="<%= bed.name %>" data-bed-id="<%= bed.id %>" style="background: var(--card-bg); border-radius: var(--card-radius); padding: 12px; margin-bottom: 10px; box-shadow: var(--card-shadow);">
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
      <div>
        <div style="font-size: 14px; font-weight: 600; color: var(--green-900);"><%= bed.name %></div>
        <div style="font-size: 10px; color: var(--text-secondary);"><%= bed.width&.round %>×<%= bed.length&.round %>cm · <%= active_plants.count %> plants</div>
      </div>
    </div>

    <svg viewBox="0 0 <%= bed_w %> <%= bed_h %>" style="width: 100%; max-height: 250px; min-height: 60px;" preserveAspectRatio="xMidYMid meet">
      <rect x="0" y="0" width="<%= bed_w %>" height="<%= bed_h %>" rx="4" fill="<%= canvas_color %>" fill-opacity="0.3" stroke="<%= canvas_color %>" stroke-width="2"/>

      <!-- Grid lines -->
      <% (1...bed.grid_cols).each do |i| %>
        <line x1="<%= i*10 %>" y1="0" x2="<%= i*10 %>" y2="<%= bed_h %>" stroke="rgba(0,0,0,0.04)" stroke-width="0.5"/>
      <% end %>
      <% (1...bed.grid_rows).each do |i| %>
        <line x1="0" y1="<%= i*10 %>" x2="<%= bed_w %>" y2="<%= i*10 %>" stroke="rgba(0,0,0,0.04)" stroke-width="0.5"/>
      <% end %>

      <!-- Plant regions -->
      <% active_plants.each do |plant| %>
        <%
          px = (plant.grid_x || 0) * 10; py = (plant.grid_y || 0) * 10
          pw = (plant.grid_w || 1) * 10; ph = (plant.grid_h || 1) * 10
          fill = case plant.crop_type.to_s.downcase
            when 'tomato', 'pepper', 'eggplant' then '#fecaca'
            when 'lettuce', 'spinach', 'chard', 'kale' then '#bbf7d0'
            when 'herb', 'basil' then '#a7f3d0'
            when 'flower' then '#fef08a'
            when 'cucumber', 'squash', 'melon', 'zucchini' then '#bae6fd'
            else '#e5e7eb'
          end
        %>
        <a href="/plants/<%= plant.id %>">
          <rect x="<%= px+1 %>" y="<%= py+1 %>" width="<%= pw-2 %>" height="<%= ph-2 %>" rx="3" fill="<%= fill %>" stroke="#d1d5db" stroke-width="0.5"/>
          <text x="<%= px+pw/2 %>" y="<%= py+ph/2 %>" text-anchor="middle" dominant-baseline="central" font-size="<%= [pw*0.15, ph*0.2, 9].min %>" font-weight="500" fill="#1a2e05"><%= plant.variety_name.length > 10 ? plant.variety_name[0..8] + '..' : plant.variety_name %></text>
        </a>
      <% end %>

      <!-- Empty area click handler -->
      <rect x="0" y="0" width="<%= bed_w %>" height="<%= bed_h %>" fill="transparent" @click="openAIForBed('<%= bed.name %>', <%= bed.grid_cols * bed.grid_rows - active_plants.sum { |p| (p.grid_w || 1) * (p.grid_h || 1) } %>)" style="cursor: pointer;"/>
    </svg>
  </div>
<% end %>
```

Also update the eager loading at the top of the Beds tab from `eager(rows: {slots: :plants})` to `eager(:plants)`.

- [ ] **Step 2: Run succession tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add views/succession.erb
git commit -m "feat: succession Beds tab uses micro-grid SVG with plant regions"
```

---

### Task 10: Update views/garden.erb

**Files:**
- Modify: `views/garden.erb`

- [ ] **Step 1: Update garden map data serialization**

Find the JSON bootstrap section (around lines 4-35) that serializes beds with `rows → slots → plants`. Replace with grid-based serialization:

The bed data should now include:
```ruby
{
  id: bed.id, name: bed.name,
  grid_cols: bed.grid_cols, grid_rows: bed.grid_rows,
  plants: bed.plants.reject { |p| p.lifecycle_stage == "done" }.map { |p|
    { id: p.id, variety_name: p.variety_name, crop_type: p.crop_type,
      grid_x: p.grid_x, grid_y: p.grid_y, grid_w: p.grid_w, grid_h: p.grid_h }
  },
  # ... keep canvas_x, canvas_y, canvas_width, canvas_height, canvas_color, canvas_points, polygon
}
```

- [ ] **Step 2: Update properties panel**

Find the "Rows / Slots" section (around lines 257-283). Replace with a "Plants" section showing grid-placed plants:

Replace the rows/slots template loops with:
```html
<template x-for="plant in selectedBed.plants" :key="plant.id">
  <div style="padding: 4px 8px; font-size: 11px; display: flex; justify-content: space-between;">
    <span x-text="plant.variety_name"></span>
    <span style="color: var(--text-secondary);" x-text="plant.grid_x + ',' + plant.grid_y + ' ' + plant.grid_w + 'x' + plant.grid_h"></span>
  </div>
</template>
```

Remove the "Edit rows & slots →" link (line 282).

- [ ] **Step 3: Update plant overlay JS**

Find the plant overlay code (around lines 493-495) that iterates `bed.rows` → `row.slots`. Replace with iteration over `bed.plants`:

```javascript
if (self.showPlants && bed.plants) {
  bed.plants.forEach(plant => {
    // Draw plant marker at bed position + grid offset
    // Scale grid coords relative to bed's canvas dimensions
  });
}
```

- [ ] **Step 4: Run all tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add views/garden.erb
git commit -m "feat: garden map uses grid model — plants instead of rows/slots"
```

---

## Summary

| Task | What changes | Files |
|------|-------------|-------|
| 1 | Migration: grid columns, bed_id, drop rows/slots | db/migrations/014_add_micro_grid.rb |
| 2 | Bed model: remove Row/Slot, add grid methods | models/bed.rb |
| 3 | Plant model: slot → bed association | models/plant.rb |
| 4 | Beds routes: grid-based API | routes/beds.rb, test |
| 5 | Plants route: grid coords | routes/plants.rb, test |
| 6 | Succession routes: timeline + layout endpoints | routes/succession.rb, test |
| 7 | Services: plan_committer + AI tools | services/*, test |
| 8 | Beds views: micro-grid SVG | views/beds/*.erb |
| 9 | Succession Beds tab: micro-grid SVG | views/succession.erb |
| 10 | Garden map: grid model | views/garden.erb |

Total: **10 tasks**, 3 chunks (migration+models, routes+services, views). Breaking change — Row/Slot tables dropped.

---

## Critical Implementation Notes (from review)

These corrections MUST be applied by implementers. They override the task descriptions above where they conflict.

### Task 4: DO NOT replace the entire routes/beds.rb

The plan's Task 4 Step 2 shows a full file replacement. **This is wrong.** Instead:
- **Preserve** all existing routes: `GET /garden`, `POST /api/beds`, `PATCH /api/beds/:id/position`, `PATCH /api/beds/:id`, `DELETE /api/beds/:id`
- **Only update** the three Row/Slot-dependent routes: `GET /beds/:id` (show), `GET /api/beds` (JSON), and `GET /garden` (data serialization)
- **Keep** the existing `class GardenApp` structure — do NOT introduce `module Routes`
- In `GET /garden`, replace the `Row.where` / `Slot.where` / `plants_by_slot` chain with `bed.plants` eager loading. The `@bed_data` structure must change from `{ bed:, rows: [{ row:, slots: [{ slot:, plant: }] }] }` to `{ bed:, plants: [...] }` matching what `garden.erb` expects
- **Keep** `GET /beds` as a redirect to `/garden` (existing behavior)

### Task 6: Timeline tab — update occupancyColor call

The Timeline tab in `succession.erb` calls `occupancyColor(m.filled, bed.total_slots)`. After this migration, `total_slots` no longer exists in the API response. Update to: `occupancyColor(m.filled, bed.grid_cols * bed.grid_rows)`. Also update `bed.total_slots` in the legend/header if referenced.

### Task 7: Preserve existing data in AI tools

- **get_beds_tool.rb**: Preserve polygon area calculations, bed_type, orientation, and arch/indoor station data. Only replace the Row/Slot serialization with grid-based plant data.
- **get_plants_tool.rb**: Keep the `bed:` and `sow_date:` output fields. Add grid position info, don't replace existing fields.
- **draft_bed_layout_tool.rb**: Update `param :payload` description to use `grid_x/y/w/h` instead of `slot_id/from_slot_id/to_slot_id`. The plan's File Structure says "no change needed" — this is wrong.
- **plan_committer.rb**: Preserve `counts[:plants] += 1` inside the plant creation loop.

### Task 8: beds/index.erb must use @beds not @bed_data

Since `GET /beds` redirects to `/garden`, the `beds/index.erb` template is only used if the redirect behavior changes. If keeping the redirect, `beds/index.erb` changes are minimal — just remove any Row/Slot references. If rendering index.erb directly (new `/beds` behavior), the template must iterate `@beds` (set by the route) with `bed.plants` for each bed.

### Task 9: SVG click handler layering fix

The transparent click-handler `<rect>` at the end of the SVG covers plant links. Fix: add `style="pointer-events: none;"` to the transparent rect, and add `style="pointer-events: auto;"` (or `pointer-events="painted"`) to each plant `<a>` element. This ensures plant links work while empty areas still trigger the AI drawer via a separate mechanism (e.g., click handler on the SVG element itself with target checking).

### Task 10: GET /garden route MUST be updated

The `GET /garden` route in `routes/beds.rb` (lines 16-36) builds `@bed_data` using `Row.where(...)`, `Slot.where(...)`. This will crash after migration. The route must be updated to build `@bed_data` using `bed.plants` instead. This is the MOST critical gap in the plan — without it the garden page is completely broken.

### Task 10: garden.erb plant overlay — coordinate mapping

The plant overlay JS needs to map grid coordinates to canvas pixel positions:
```javascript
const scaleX = bed.canvas_width / (bed.grid_cols * 10);
const scaleY = bed.canvas_height / (bed.grid_rows * 10);
const px = bed.canvas_x + plant.grid_x * 10 * scaleX;
const py = bed.canvas_y + plant.grid_y * 10 * scaleY;
const pw = plant.grid_w * 10 * scaleX;
const ph = plant.grid_h * 10 * scaleY;
```

### Task 10: garden.erb stale JS cleanup

Remove or update:
- `slotStyle()` function (lines 609-613) — replace with `plantStyle()` using same crop-type colors
- `newBed.rows = []` in `confirmNewBed()` (line 872) — replace with `newBed.plants = []`
- AI drawer context banner `selectedBed.empty_count + ' empty slots'` — update to reference grid cells
