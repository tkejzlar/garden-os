# AI Garden Management Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the AI planner tools to modify, delete, reorganize, and precisely place plants — turning it from a read-only advisor into a full garden management agent.

**Architecture:** New RubyLLM tool classes in `services/planner_tools/` that operate directly on the DB via existing Sequel models. A refresh mechanism signals the frontend to reload after mutations. A new migration adds bed zones and metadata.

**Tech Stack:** Ruby/Sinatra, Sequel ORM, SQLite, RubyLLM tools, Minitest

---

## File Map

**New files:**
- `services/planner_tools/clear_bed_tool.rb` — clear all plants from a bed
- `services/planner_tools/remove_plants_tool.rb` — remove plants by variety/crop/id
- `services/planner_tools/move_plant_tool.rb` — move plant to different bed
- `services/planner_tools/update_plant_tool.rb` — edit plant fields
- `services/planner_tools/delete_succession_plan_tool.rb` — remove succession plans + pending tasks
- `services/planner_tools/place_row_tool.rb` — place plants in a horizontal row
- `services/planner_tools/place_column_tool.rb` — place plants in a vertical column
- `services/planner_tools/place_single_tool.rb` — place one plant at exact position
- `services/planner_tools/place_border_tool.rb` — place plants along bed edges
- `services/planner_tools/place_fill_tool.rb` — fill region with plants at spacing
- `services/planner_tools/manage_zones_tool.rb` — CRUD for bed zones
- `services/planner_tools/update_bed_metadata_tool.rb` — update bed metadata fields
- `services/planner_tools/deduplicate_bed_tool.rb` — remove duplicate plants on a bed
- `services/planner_tools/set_plant_notes_tool.rb` — set design-intent notes on plants
- `db/migrations/020_add_bed_zones_and_metadata.rb` — migration for zones table + bed metadata columns
- `models/bed_zone.rb` — BedZone model
- `test/services/test_planner_crud_tools.rb` — tests for Phase 1 tools
- `test/services/test_planner_layout_tools.rb` — tests for Phase 2 tools
- `test/services/test_planner_zone_tools.rb` — tests for Phase 3 tools
- `test/services/test_planner_operational_tools.rb` — tests for Phase 4 tools

**Modified files:**
- `services/planner_service.rb` — register all new tools, add refresh mechanism, update system prompt
- `services/planner_tools/draft_plan_tool.rb` — add duplicate detection warnings
- `services/planner_tools/get_beds_tool.rb` — include zones and metadata in output
- `models/bed.rb` — add zone association, metadata accessors
- `src/components/AIDrawer.tsx` — handle `refresh` SSE event

---

## Phase 1: Core CRUD Tools

### Task 1: SSE Refresh Mechanism

**Files:**
- Modify: `services/planner_service.rb`
- Modify: `src/components/AIDrawer.tsx`

- [ ] **Step 1: Add refresh detection to PlannerService**

In `services/planner_service.rb`, after the streaming response completes (line 191-198 area), check for a thread-local refresh flag and emit it as an SSE event. Modify `send_message_streaming`:

```ruby
# In send_message_streaming, after the existing draft/bed_layout event sends (line 197-198):
block.call({ type: "refresh" }) if Thread.current[:planner_needs_refresh] && block
```

- [ ] **Step 2: Handle refresh event in AIDrawer**

In `src/components/AIDrawer.tsx`, add a handler in the `streamPlanner` callback (around line 91):

```tsx
} else if (event.type === 'refresh') {
  onDraftApplied?.()
```

- [ ] **Step 3: Commit**

```bash
git add services/planner_service.rb src/components/AIDrawer.tsx
git commit -m "feat: SSE refresh event for AI planner tool mutations"
```

---

### Task 2: ClearBedTool

**Files:**
- Create: `services/planner_tools/clear_bed_tool.rb`
- Create: `test/services/test_planner_crud_tools.rb`

- [ ] **Step 1: Write the test**

Create `test/services/test_planner_crud_tools.rb`:

```ruby
require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/plant"
require_relative "../../services/planner_tools/clear_bed_tool"

class TestClearBedTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Basil", crop_type: "herb", grid_x: 6, grid_y: 0, grid_w: 4, grid_h: 4)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_clears_all_plants
    tool = ClearBedTool.new
    result = tool.execute(bed_name: "BB1")
    assert_includes result, "2"
    assert_equal 0, Plant.where(bed_id: @bed.id).count
  end

  def test_clears_sets_refresh_flag
    tool = ClearBedTool.new
    tool.execute(bed_name: "BB1")
    assert Thread.current[:planner_needs_refresh]
  end

  def test_unknown_bed_returns_error
    tool = ClearBedTool.new
    result = tool.execute(bed_name: "NOPE")
    assert_includes result, "not found"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_crud_tools.rb`
Expected: FAIL — ClearBedTool not defined

- [ ] **Step 3: Write ClearBedTool**

Create `services/planner_tools/clear_bed_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class ClearBedTool < RubyLLM::Tool
  description "Remove ALL plants from a bed. Use when the user wants to start a bed from scratch or redesign it completely. Confirm with the user before calling this."

  param :bed_name, type: :string, desc: "Exact bed name as returned by get_beds"

  def execute(bed_name:)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
    count = plants.length
    plants.each(&:destroy)

    Thread.current[:planner_needs_refresh] = true
    "Cleared #{count} plants from #{bed_name}."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_crud_tools.rb`
Expected: 3 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/clear_bed_tool.rb test/services/test_planner_crud_tools.rb
git commit -m "feat: ClearBedTool — AI can clear all plants from a bed"
```

---

### Task 3: RemovePlantsTool

**Files:**
- Create: `services/planner_tools/remove_plants_tool.rb`
- Modify: `test/services/test_planner_crud_tools.rb`

- [ ] **Step 1: Write the tests**

Append to `test/services/test_planner_crud_tools.rb`:

```ruby
require_relative "../../services/planner_tools/remove_plants_tool"

class TestRemovePlantsTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 6, grid_y: 0, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Basil", crop_type: "herb", grid_x: 0, grid_y: 6, grid_w: 4, grid_h: 4)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_remove_by_variety
    tool = RemovePlantsTool.new
    result = tool.execute(bed_name: "BB1", variety_name: "Raf")
    assert_includes result, "2"
    assert_equal 1, Plant.where(bed_id: @bed.id).count
    assert_equal "Basil", Plant.where(bed_id: @bed.id).first.variety_name
  end

  def test_remove_by_crop_type
    tool = RemovePlantsTool.new
    result = tool.execute(bed_name: "BB1", crop_type: "herb")
    assert_includes result, "1"
    assert_equal 2, Plant.where(bed_id: @bed.id).count
  end

  def test_remove_sets_refresh
    tool = RemovePlantsTool.new
    tool.execute(bed_name: "BB1", variety_name: "Raf")
    assert Thread.current[:planner_needs_refresh]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_crud_tools.rb`
Expected: FAIL — RemovePlantsTool not defined

- [ ] **Step 3: Write RemovePlantsTool**

Create `services/planner_tools/remove_plants_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class RemovePlantsTool < RubyLLM::Tool
  description "Remove specific plants from a bed by variety name, crop type, or plant IDs. Use for targeted cleanup — removing duplicates, unwanted varieties, etc."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Remove all plants with this variety name (optional)"
  param :crop_type, type: :string, desc: "Remove all plants with this crop type (optional)"
  param :plant_ids, type: :string, desc: "JSON array of plant IDs to remove (optional)"

  def execute(bed_name:, variety_name: nil, crop_type: nil, plant_ids: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    scope = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done")

    if plant_ids
      ids = JSON.parse(plant_ids) rescue []
      scope = scope.where(id: ids)
    elsif variety_name
      scope = scope.where(variety_name: variety_name)
    elsif crop_type
      scope = scope.where(crop_type: crop_type)
    else
      return "Error: provide variety_name, crop_type, or plant_ids"
    end

    plants = scope.all
    count = plants.length
    removed = plants.map { |p| "#{p.variety_name} (#{p.crop_type})" }
    plants.each(&:destroy)

    Thread.current[:planner_needs_refresh] = true
    "Removed #{count} plants from #{bed_name}: #{removed.join(', ')}"
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_crud_tools.rb`
Expected: 6 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/remove_plants_tool.rb test/services/test_planner_crud_tools.rb
git commit -m "feat: RemovePlantsTool — AI can remove specific plants from beds"
```

---

### Task 4: MovePlantTool

**Files:**
- Create: `services/planner_tools/move_plant_tool.rb`
- Modify: `test/services/test_planner_crud_tools.rb`

- [ ] **Step 1: Write the tests**

Append to `test/services/test_planner_crud_tools.rb`:

```ruby
require_relative "../../services/planner_tools/move_plant_tool"

class TestMovePlantTool < GardenTest
  def setup
    super
    @bed1 = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    @bed2 = Bed.create(name: "SB1", bed_type: "raised", garden_id: @garden.id, width: 100, length: 200)
    @plant = Plant.create(garden_id: @garden.id, bed_id: @bed1.id, variety_name: "Raf", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_moves_plant_to_new_bed
    tool = MovePlantTool.new
    result = tool.execute(plant_id: @plant.id.to_s, target_bed_name: "SB1")
    assert_includes result, "SB1"
    @plant.refresh
    assert_equal @bed2.id, @plant.bed_id
  end

  def test_auto_places_on_target_bed
    Plant.create(garden_id: @garden.id, bed_id: @bed2.id, variety_name: "Basil", crop_type: "herb", grid_x: 0, grid_y: 0, grid_w: 4, grid_h: 4)
    tool = MovePlantTool.new
    tool.execute(plant_id: @plant.id.to_s, target_bed_name: "SB1")
    @plant.refresh
    assert @plant.grid_y >= 4, "Should be placed below existing plant"
  end

  def test_invalid_plant
    tool = MovePlantTool.new
    result = tool.execute(plant_id: "99999", target_bed_name: "SB1")
    assert_includes result, "not found"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_crud_tools.rb`
Expected: FAIL — MovePlantTool not defined

- [ ] **Step 3: Write MovePlantTool**

Create `services/planner_tools/move_plant_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class MovePlantTool < RubyLLM::Tool
  description "Move a plant from its current bed to a different bed. Auto-places it below existing plants on the target bed."

  param :plant_id, type: :string, desc: "ID of the plant to move"
  param :target_bed_name, type: :string, desc: "Name of the destination bed"

  def execute(plant_id:, target_bed_name:)
    garden_id = Thread.current[:current_garden_id]
    plant = Plant[plant_id.to_i]
    return "Error: plant not found" unless plant && plant.garden_id == garden_id

    bed = Bed.where(name: target_bed_name, garden_id: garden_id).first
    return "Error: bed '#{target_bed_name}' not found" unless bed

    # Auto-place below existing plants
    existing = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
    next_y = existing.any? ? existing.map { |p| (p.grid_y || 0) + (p.grid_h || 1) }.max : 0

    plant.update(
      bed_id: bed.id,
      grid_x: 0,
      grid_y: next_y.clamp(0, bed.grid_rows - 1),
      updated_at: Time.now
    )

    Thread.current[:planner_needs_refresh] = true
    "Moved #{plant.variety_name} (#{plant.crop_type}) to #{target_bed_name} at row #{next_y}."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_crud_tools.rb`
Expected: 9 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/move_plant_tool.rb test/services/test_planner_crud_tools.rb
git commit -m "feat: MovePlantTool — AI can move plants between beds"
```

---

### Task 5: UpdatePlantTool

**Files:**
- Create: `services/planner_tools/update_plant_tool.rb`
- Modify: `test/services/test_planner_crud_tools.rb`

- [ ] **Step 1: Write the test**

Append to `test/services/test_planner_crud_tools.rb`:

```ruby
require_relative "../../services/planner_tools/update_plant_tool"

class TestUpdatePlantTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    @plant = Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6, quantity: 1)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_updates_grid_position
    tool = UpdatePlantTool.new
    result = tool.execute(plant_id: @plant.id.to_s, grid_x: "10", grid_y: "5")
    @plant.refresh
    assert_equal 10, @plant.grid_x
    assert_equal 5, @plant.grid_y
  end

  def test_updates_quantity
    tool = UpdatePlantTool.new
    tool.execute(plant_id: @plant.id.to_s, quantity: "3")
    @plant.refresh
    assert_equal 3, @plant.quantity
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_crud_tools.rb`
Expected: FAIL — UpdatePlantTool not defined

- [ ] **Step 3: Write UpdatePlantTool**

Create `services/planner_tools/update_plant_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/plant"

class UpdatePlantTool < RubyLLM::Tool
  description "Update a plant's grid position, size, quantity, or names. Use for fine-tuning placement after initial layout."

  param :plant_id, type: :string, desc: "ID of the plant to update"
  param :grid_x, type: :string, desc: "New grid column (optional)"
  param :grid_y, type: :string, desc: "New grid row (optional)"
  param :grid_w, type: :string, desc: "New grid width in cells (optional)"
  param :grid_h, type: :string, desc: "New grid height in cells (optional)"
  param :quantity, type: :string, desc: "New quantity (optional)"
  param :variety_name, type: :string, desc: "New variety name (optional)"
  param :crop_type, type: :string, desc: "New crop type (optional)"

  def execute(plant_id:, grid_x: nil, grid_y: nil, grid_w: nil, grid_h: nil, quantity: nil, variety_name: nil, crop_type: nil)
    garden_id = Thread.current[:current_garden_id]
    plant = Plant[plant_id.to_i]
    return "Error: plant not found" unless plant && plant.garden_id == garden_id

    updates = {}
    updates[:grid_x] = grid_x.to_i if grid_x
    updates[:grid_y] = grid_y.to_i if grid_y
    updates[:grid_w] = grid_w.to_i if grid_w
    updates[:grid_h] = grid_h.to_i if grid_h
    updates[:quantity] = quantity.to_i if quantity
    updates[:variety_name] = variety_name if variety_name
    updates[:crop_type] = crop_type if crop_type
    updates[:updated_at] = Time.now

    return "Error: nothing to update" if updates.length == 1 # only updated_at

    plant.update(updates)
    Thread.current[:planner_needs_refresh] = true
    "Updated #{plant.variety_name}: #{updates.reject { |k, _| k == :updated_at }.map { |k, v| "#{k}=#{v}" }.join(', ')}"
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_crud_tools.rb`
Expected: 11 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/update_plant_tool.rb test/services/test_planner_crud_tools.rb
git commit -m "feat: UpdatePlantTool — AI can update plant position, size, quantity"
```

---

### Task 6: DeleteSuccessionPlanTool

**Files:**
- Create: `services/planner_tools/delete_succession_plan_tool.rb`
- Modify: `test/services/test_planner_crud_tools.rb`

- [ ] **Step 1: Write the test**

Append to `test/services/test_planner_crud_tools.rb`:

```ruby
require_relative "../../services/planner_tools/delete_succession_plan_tool"
require_relative "../../models/succession_plan"
require_relative "../../models/task"

class TestDeleteSuccessionPlanTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    @plan = SuccessionPlan.create(
      garden_id: @garden.id, crop: "Lettuce", varieties: '["Tre Colori"]',
      interval_days: 14, season_start: Date.new(2026, 4, 1), season_end: Date.new(2026, 9, 30),
      total_planned_sowings: 5, target_beds: '["BB1"]'
    )
    Task.create(garden_id: @garden.id, title: "Sow Lettuce #1", task_type: "sow", status: "upcoming", due_date: Date.new(2026, 4, 1))
    Task.create(garden_id: @garden.id, title: "Sow Lettuce #2", task_type: "sow", status: "done", due_date: Date.new(2026, 4, 15))
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_deletes_plan_and_pending_tasks
    tool = DeleteSuccessionPlanTool.new
    result = tool.execute(crop: "Lettuce")
    assert_equal 0, SuccessionPlan.where(garden_id: @garden.id, crop: "Lettuce").count
    # Only pending tasks deleted, done tasks kept
    assert_equal 1, Task.where(garden_id: @garden.id).count
    assert_equal "done", Task.first.status
  end

  def test_unknown_crop
    tool = DeleteSuccessionPlanTool.new
    result = tool.execute(crop: "Mango")
    assert_includes result, "No succession plans found"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_crud_tools.rb`
Expected: FAIL — DeleteSuccessionPlanTool not defined

- [ ] **Step 3: Write DeleteSuccessionPlanTool**

Create `services/planner_tools/delete_succession_plan_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/succession_plan"
require_relative "../../models/task"

class DeleteSuccessionPlanTool < RubyLLM::Tool
  description "Delete succession plan(s) for a crop and their pending (not yet completed) sow tasks. Completed tasks are preserved."

  param :crop, type: :string, desc: "Crop name to delete plans for (e.g., 'Lettuce')"
  param :target_bed, type: :string, desc: "Optional: only delete plans targeting this bed"

  def execute(crop:, target_bed: nil)
    garden_id = Thread.current[:current_garden_id]
    plans = SuccessionPlan.where(garden_id: garden_id, crop: crop).all

    if target_bed
      plans = plans.select { |p| p.target_beds_list.include?(target_bed) }
    end

    return "No succession plans found for '#{crop}'" if plans.empty?

    plan_count = plans.length
    task_count = 0

    DB.transaction do
      # Delete pending sow tasks matching this crop
      pending_tasks = Task.where(garden_id: garden_id, task_type: "sow")
        .where(Sequel.like(:title, "%#{crop}%"))
        .exclude(status: "done").all
      task_count = pending_tasks.length
      pending_tasks.each(&:destroy)

      plans.each(&:destroy)
    end

    Thread.current[:planner_needs_refresh] = true
    "Deleted #{plan_count} succession plan(s) for #{crop} and #{task_count} pending sow tasks."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_crud_tools.rb`
Expected: 13 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/delete_succession_plan_tool.rb test/services/test_planner_crud_tools.rb
git commit -m "feat: DeleteSuccessionPlanTool — AI can remove succession plans + pending tasks"
```

---

### Task 7: Register Phase 1 Tools + Update System Prompt

**Files:**
- Modify: `services/planner_service.rb`

- [ ] **Step 1: Add requires and tool registrations**

In `services/planner_service.rb`, add requires after the existing tool requires (after line 12):

```ruby
require_relative "planner_tools/clear_bed_tool"
require_relative "planner_tools/remove_plants_tool"
require_relative "planner_tools/move_plant_tool"
require_relative "planner_tools/update_plant_tool"
require_relative "planner_tools/delete_succession_plan_tool"
```

In the `chat` method, add `.with_tool` calls after `.with_tool(RequestFeatureTool)`:

```ruby
        .with_tool(ClearBedTool)
        .with_tool(RemovePlantsTool)
        .with_tool(MovePlantTool)
        .with_tool(UpdatePlantTool)
        .with_tool(DeleteSuccessionPlanTool)
```

- [ ] **Step 2: Update system prompt**

In the system prompt (the `<<~PROMPT` block), replace the existing SELF-REPORTING section with:

```ruby
      GARDEN MANAGEMENT: You have tools to modify the garden directly:
      - clear_bed: Remove ALL plants from a bed (confirm with user first!)
      - remove_plants: Remove specific plants by variety, crop type, or IDs
      - move_plant: Move a plant to a different bed
      - update_plant: Change a plant's grid position, size, or quantity
      - delete_succession_plan: Remove succession schedules and their pending tasks

      These tools execute immediately — no draft/commit flow. Always confirm
      with the user before bulk destructive operations like clear_bed.

      When redesigning a bed:
      1. First clear or remove unwanted plants
      2. Then use draft_plan or draft_bed_layout to add new ones
      3. Check for duplicates before adding

      SELF-REPORTING: If the user asks you to do something you lack a tool for,
      call request_feature to log it. Tell the user: "I can't do that yet —
      I've logged a feature request for [capability]."
```

- [ ] **Step 3: Commit**

```bash
git add services/planner_service.rb
git commit -m "feat: register Phase 1 CRUD tools and update system prompt"
```

---

## Phase 2: Layout Primitives

### Task 8: PlaceRowTool

**Files:**
- Create: `services/planner_tools/place_row_tool.rb`
- Create: `test/services/test_planner_layout_tools.rb`

- [ ] **Step 1: Write the test**

Create `test/services/test_planner_layout_tools.rb`:

```ruby
require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/plant"
require_relative "../../services/planner_tools/place_row_tool"

class TestPlaceRowTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_places_row_of_plants
    tool = PlaceRowTool.new
    result = tool.execute(bed_name: "BB1", variety_name: "Lettuce", crop_type: "lettuce", row_y: "0", count: "5")
    plants = Plant.where(bed_id: @bed.id).all
    assert_equal 5, plants.length
    assert plants.all? { |p| p.grid_y == 0 }, "All plants should be at row 0"
    xs = plants.map(&:grid_x).sort
    assert_equal xs, xs.uniq, "No overlapping x positions"
  end

  def test_respects_custom_spacing
    tool = PlaceRowTool.new
    tool.execute(bed_name: "BB1", variety_name: "Tomato", crop_type: "tomato", row_y: "0", count: "3", spacing: "8")
    plants = Plant.where(bed_id: @bed.id).order(:grid_x).all
    assert_equal [0, 8, 16], plants.map(&:grid_x)
  end

  def test_unknown_bed
    tool = PlaceRowTool.new
    result = tool.execute(bed_name: "NOPE", variety_name: "X", crop_type: "x", row_y: "0", count: "1")
    assert_includes result, "not found"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_layout_tools.rb`
Expected: FAIL — PlaceRowTool not defined

- [ ] **Step 3: Write PlaceRowTool**

Create `services/planner_tools/place_row_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class PlaceRowTool < RubyLLM::Tool
  description "Place plants in a horizontal row across a bed. Great for row-sowing patterns like lettuce rows or onion borders."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type (e.g., lettuce, tomato)"
  param :row_y, type: :string, desc: "Grid row position (0 = top/front of bed)"
  param :count, type: :string, desc: "Number of plants to place"
  param :spacing, type: :string, desc: "Grid cells between plants (optional, uses crop default)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, variety_name:, crop_type:, row_y:, count:, spacing: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    gw, gh = Plant.default_grid_size(crop_type)
    step = spacing ? spacing.to_i : gw
    n = count.to_i
    y = row_y.to_i

    created = 0
    n.times do |i|
      x = i * step
      break if x + gw > bed.grid_cols # stop if we'd go off the bed

      Plant.create(
        garden_id: garden_id, bed_id: bed.id,
        variety_name: variety_name, crop_type: crop_type, source: source,
        lifecycle_stage: "seed_packet",
        grid_x: x, grid_y: y, grid_w: gw, grid_h: gh, quantity: 1
      )
      created += 1
    end

    Thread.current[:planner_needs_refresh] = true
    "Placed #{created} #{variety_name} in a row at y=#{y} on #{bed_name}."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_layout_tools.rb`
Expected: 3 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/place_row_tool.rb test/services/test_planner_layout_tools.rb
git commit -m "feat: PlaceRowTool — AI can place plants in horizontal rows"
```

---

### Task 9: PlaceColumnTool

**Files:**
- Create: `services/planner_tools/place_column_tool.rb`
- Modify: `test/services/test_planner_layout_tools.rb`

- [ ] **Step 1: Write the test**

Append to `test/services/test_planner_layout_tools.rb`:

```ruby
require_relative "../../services/planner_tools/place_column_tool"

class TestPlaceColumnTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_places_column_of_plants
    tool = PlaceColumnTool.new
    result = tool.execute(bed_name: "BB1", variety_name: "Tomato", crop_type: "tomato", col_x: "0", count: "4")
    plants = Plant.where(bed_id: @bed.id).all
    assert_equal 4, plants.length
    assert plants.all? { |p| p.grid_x == 0 }, "All plants should be at col 0"
  end

  def test_respects_custom_spacing
    tool = PlaceColumnTool.new
    tool.execute(bed_name: "BB1", variety_name: "Tomato", crop_type: "tomato", col_x: "0", count: "3", spacing: "10")
    plants = Plant.where(bed_id: @bed.id).order(:grid_y).all
    assert_equal [0, 10, 20], plants.map(&:grid_y)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_layout_tools.rb`
Expected: FAIL — PlaceColumnTool not defined

- [ ] **Step 3: Write PlaceColumnTool**

Create `services/planner_tools/place_column_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class PlaceColumnTool < RubyLLM::Tool
  description "Place plants in a vertical column down a bed. Great for tall crops along the back or trellised plants."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type"
  param :col_x, type: :string, desc: "Grid column position (0 = left edge)"
  param :count, type: :string, desc: "Number of plants"
  param :spacing, type: :string, desc: "Grid cells between plants (optional, uses crop default)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, variety_name:, crop_type:, col_x:, count:, spacing: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    gw, gh = Plant.default_grid_size(crop_type)
    step = spacing ? spacing.to_i : gh
    n = count.to_i
    x = col_x.to_i

    created = 0
    n.times do |i|
      y = i * step
      break if y + gh > bed.grid_rows

      Plant.create(
        garden_id: garden_id, bed_id: bed.id,
        variety_name: variety_name, crop_type: crop_type, source: source,
        lifecycle_stage: "seed_packet",
        grid_x: x, grid_y: y, grid_w: gw, grid_h: gh, quantity: 1
      )
      created += 1
    end

    Thread.current[:planner_needs_refresh] = true
    "Placed #{created} #{variety_name} in a column at x=#{x} on #{bed_name}."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_layout_tools.rb`
Expected: 5 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/place_column_tool.rb test/services/test_planner_layout_tools.rb
git commit -m "feat: PlaceColumnTool — AI can place plants in vertical columns"
```

---

### Task 10: PlaceSingleTool

**Files:**
- Create: `services/planner_tools/place_single_tool.rb`
- Modify: `test/services/test_planner_layout_tools.rb`

- [ ] **Step 1: Write the test**

Append to `test/services/test_planner_layout_tools.rb`:

```ruby
require_relative "../../services/planner_tools/place_single_tool"

class TestPlaceSingleTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_places_single_plant_at_exact_position
    tool = PlaceSingleTool.new
    tool.execute(bed_name: "BB1", variety_name: "Courgette", crop_type: "zucchini", grid_x: "10", grid_y: "5")
    plant = Plant.where(bed_id: @bed.id).first
    assert_equal 10, plant.grid_x
    assert_equal 5, plant.grid_y
    assert_equal "Courgette", plant.variety_name
  end

  def test_custom_size_and_quantity
    tool = PlaceSingleTool.new
    tool.execute(bed_name: "BB1", variety_name: "Radish", crop_type: "radish", grid_x: "0", grid_y: "0", grid_w: "4", grid_h: "4", quantity: "20")
    plant = Plant.where(bed_id: @bed.id).first
    assert_equal 4, plant.grid_w
    assert_equal 4, plant.grid_h
    assert_equal 20, plant.quantity
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_layout_tools.rb`
Expected: FAIL — PlaceSingleTool not defined

- [ ] **Step 3: Write PlaceSingleTool**

Create `services/planner_tools/place_single_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class PlaceSingleTool < RubyLLM::Tool
  description "Place a single plant at an exact grid position on a bed. Use for precise specimen placement or anchoring corners."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type"
  param :grid_x, type: :string, desc: "Grid column position"
  param :grid_y, type: :string, desc: "Grid row position"
  param :grid_w, type: :string, desc: "Width in grid cells (optional, uses crop default)"
  param :grid_h, type: :string, desc: "Height in grid cells (optional, uses crop default)"
  param :quantity, type: :string, desc: "Number of plants in this cell (optional, default 1)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, variety_name:, crop_type:, grid_x:, grid_y:, grid_w: nil, grid_h: nil, quantity: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    dw, dh = Plant.default_grid_size(crop_type)

    plant = Plant.create(
      garden_id: garden_id, bed_id: bed.id,
      variety_name: variety_name, crop_type: crop_type, source: source,
      lifecycle_stage: "seed_packet",
      grid_x: grid_x.to_i, grid_y: grid_y.to_i,
      grid_w: grid_w ? grid_w.to_i : dw,
      grid_h: grid_h ? grid_h.to_i : dh,
      quantity: quantity ? quantity.to_i : 1
    )

    Thread.current[:planner_needs_refresh] = true
    "Placed #{variety_name} at (#{plant.grid_x}, #{plant.grid_y}) on #{bed_name}, size #{plant.grid_w}x#{plant.grid_h}."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_layout_tools.rb`
Expected: 7 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/place_single_tool.rb test/services/test_planner_layout_tools.rb
git commit -m "feat: PlaceSingleTool — AI can place plants at exact grid positions"
```

---

### Task 11: PlaceBorderTool

**Files:**
- Create: `services/planner_tools/place_border_tool.rb`
- Modify: `test/services/test_planner_layout_tools.rb`

- [ ] **Step 1: Write the test**

Append to `test/services/test_planner_layout_tools.rb`:

```ruby
require_relative "../../services/planner_tools/place_border_tool"

class TestPlaceBorderTool < GardenTest
  def setup
    super
    # 60cm x 60cm bed = 12x12 grid
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 60, length: 60)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_places_front_border
    tool = PlaceBorderTool.new
    tool.execute(bed_name: "BB1", variety_name: "Marigold", crop_type: "flower", edges: '["front"]')
    plants = Plant.where(bed_id: @bed.id).all
    assert plants.length > 0
    assert plants.all? { |p| p.grid_y == 0 }, "Front border should be at row 0"
  end

  def test_places_multiple_edges
    tool = PlaceBorderTool.new
    tool.execute(bed_name: "BB1", variety_name: "Onion", crop_type: "onion", edges: '["front", "back"]')
    plants = Plant.where(bed_id: @bed.id).all
    ys = plants.map(&:grid_y).uniq.sort
    assert_includes ys, 0, "Should have front row"
    max_y = @bed.grid_rows - Plant.default_grid_size("onion")[1]
    assert ys.any? { |y| y >= max_y - 1 }, "Should have back row"
  end

  def test_skips_occupied_cells
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    tool = PlaceBorderTool.new
    tool.execute(bed_name: "BB1", variety_name: "Marigold", crop_type: "flower", edges: '["front"]')
    plants = Plant.where(bed_id: @bed.id, variety_name: "Marigold").all
    assert plants.all? { |p| p.grid_x >= 6 }, "Should skip occupied cells"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_layout_tools.rb`
Expected: FAIL — PlaceBorderTool not defined

- [ ] **Step 3: Write PlaceBorderTool**

Create `services/planner_tools/place_border_tool.rb`:

```ruby
require "ruby_llm"
require "json"
require_relative "../../models/bed"
require_relative "../../models/plant"

class PlaceBorderTool < RubyLLM::Tool
  description "Place plants along the edges of a bed. Use for ornamental borders, companion planting edges, or pest-deterrent rings. Skips cells already occupied."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type"
  param :edges, type: :string, desc: 'JSON array of edges: "front" (y=0), "back" (y=max), "left" (x=0), "right" (x=max)'
  param :spacing, type: :string, desc: "Grid cells between plants (optional, uses crop default)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, variety_name:, crop_type:, edges:, spacing: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    edge_list = JSON.parse(edges) rescue []
    return "Error: edges must be a JSON array" if edge_list.empty?

    gw, gh = Plant.default_grid_size(crop_type)
    step_x = spacing ? spacing.to_i : gw
    step_y = spacing ? spacing.to_i : gh

    # Build occupied cell set
    existing = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
    occupied = Set.new
    existing.each do |p|
      (p.grid_x...(p.grid_x + p.grid_w)).each do |cx|
        (p.grid_y...(p.grid_y + p.grid_h)).each do |cy|
          occupied.add([cx, cy])
        end
      end
    end

    positions = []

    edge_list.each do |edge|
      case edge
      when "front"
        x = 0
        while x + gw <= bed.grid_cols
          positions << [x, 0] unless occupied.include?([x, 0])
          x += step_x
        end
      when "back"
        y = bed.grid_rows - gh
        x = 0
        while x + gw <= bed.grid_cols
          positions << [x, y] unless occupied.include?([x, y])
          x += step_x
        end
      when "left"
        y = 0
        while y + gh <= bed.grid_rows
          positions << [0, y] unless occupied.include?([0, y])
          y += step_y
        end
      when "right"
        x = bed.grid_cols - gw
        y = 0
        while y + gh <= bed.grid_rows
          positions << [x, y] unless occupied.include?([x, y])
          y += step_y
        end
      end
    end

    positions.uniq!
    positions.each do |x, y|
      Plant.create(
        garden_id: garden_id, bed_id: bed.id,
        variety_name: variety_name, crop_type: crop_type, source: source,
        lifecycle_stage: "seed_packet",
        grid_x: x, grid_y: y, grid_w: gw, grid_h: gh, quantity: 1
      )
    end

    Thread.current[:planner_needs_refresh] = true
    "Placed #{positions.length} #{variety_name} along #{edge_list.join(', ')} edge(s) of #{bed_name}."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_layout_tools.rb`
Expected: 10 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/place_border_tool.rb test/services/test_planner_layout_tools.rb
git commit -m "feat: PlaceBorderTool — AI can place plants along bed edges"
```

---

### Task 12: PlaceFillTool

**Files:**
- Create: `services/planner_tools/place_fill_tool.rb`
- Modify: `test/services/test_planner_layout_tools.rb`

- [ ] **Step 1: Write the test**

Append to `test/services/test_planner_layout_tools.rb`:

```ruby
require_relative "../../services/planner_tools/place_fill_tool"

class TestPlaceFillTool < GardenTest
  def setup
    super
    # 60cm x 60cm = 12x12 grid
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 60, length: 60)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_fills_entire_bed
    tool = PlaceFillTool.new
    tool.execute(bed_name: "BB1", variety_name: "Radish", crop_type: "radish")
    plants = Plant.where(bed_id: @bed.id).all
    # radish = 2x2 cells, 12x12 grid = 6x6 = 36 plants
    assert_equal 36, plants.length
  end

  def test_fills_specific_region
    tool = PlaceFillTool.new
    tool.execute(bed_name: "BB1", variety_name: "Lettuce", crop_type: "lettuce", region: '{"from_x":0,"from_y":0,"to_x":8,"to_y":8}')
    plants = Plant.where(bed_id: @bed.id).all
    assert plants.all? { |p| p.grid_x < 8 && p.grid_y < 8 }
  end

  def test_skips_occupied_cells
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    tool = PlaceFillTool.new
    tool.execute(bed_name: "BB1", variety_name: "Radish", crop_type: "radish")
    plants = Plant.where(bed_id: @bed.id, variety_name: "Radish").all
    # Should not overlap the tomato
    plants.each do |p|
      refute(p.grid_x < 6 && p.grid_y < 6, "Should not overlap tomato at (#{p.grid_x}, #{p.grid_y})")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_layout_tools.rb`
Expected: FAIL — PlaceFillTool not defined

- [ ] **Step 3: Write PlaceFillTool**

Create `services/planner_tools/place_fill_tool.rb`:

```ruby
require "ruby_llm"
require "json"
require_relative "../../models/bed"
require_relative "../../models/plant"

class PlaceFillTool < RubyLLM::Tool
  description "Fill a bed (or region within a bed) with plants at proper spacing, skipping occupied cells. Use for dense planting of herbs, greens, or root crops."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type"
  param :region, type: :string, desc: 'Optional JSON: {"from_x":0,"from_y":0,"to_x":10,"to_y":10}. Defaults to entire bed.'
  param :spacing, type: :string, desc: "Grid cells between plants (optional, uses crop default)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, variety_name:, crop_type:, region: nil, spacing: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    gw, gh = Plant.default_grid_size(crop_type)
    step_x = spacing ? spacing.to_i : gw
    step_y = spacing ? spacing.to_i : gh

    if region
      r = JSON.parse(region) rescue {}
      from_x = r["from_x"]&.to_i || 0
      from_y = r["from_y"]&.to_i || 0
      to_x = r["to_x"]&.to_i || bed.grid_cols
      to_y = r["to_y"]&.to_i || bed.grid_rows
    else
      from_x, from_y = 0, 0
      to_x, to_y = bed.grid_cols, bed.grid_rows
    end

    # Build occupied cell set
    existing = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
    occupied = Set.new
    existing.each do |p|
      (p.grid_x...(p.grid_x + p.grid_w)).each do |cx|
        (p.grid_y...(p.grid_y + p.grid_h)).each do |cy|
          occupied.add([cx, cy])
        end
      end
    end

    created = 0
    y = from_y
    while y + gh <= to_y
      x = from_x
      while x + gw <= to_x
        # Check if any cell in this plant's footprint is occupied
        overlap = (x...(x + gw)).any? { |cx| (y...(y + gh)).any? { |cy| occupied.include?([cx, cy]) } }
        unless overlap
          Plant.create(
            garden_id: garden_id, bed_id: bed.id,
            variety_name: variety_name, crop_type: crop_type, source: source,
            lifecycle_stage: "seed_packet",
            grid_x: x, grid_y: y, grid_w: gw, grid_h: gh, quantity: 1
          )
          created += 1
        end
        x += step_x
      end
      y += step_y
    end

    Thread.current[:planner_needs_refresh] = true
    "Filled #{bed_name} with #{created} #{variety_name} (#{crop_type}) at #{step_x}x#{step_y} spacing."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_layout_tools.rb`
Expected: 13 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/place_fill_tool.rb test/services/test_planner_layout_tools.rb
git commit -m "feat: PlaceFillTool — AI can fill bed regions with plants at spacing"
```

---

### Task 13: Register Phase 2 Tools + Update Prompt

**Files:**
- Modify: `services/planner_service.rb`

- [ ] **Step 1: Add requires and registrations**

In `services/planner_service.rb`, add after the Phase 1 requires:

```ruby
require_relative "planner_tools/place_row_tool"
require_relative "planner_tools/place_column_tool"
require_relative "planner_tools/place_single_tool"
require_relative "planner_tools/place_border_tool"
require_relative "planner_tools/place_fill_tool"
```

In the `chat` method, add after the Phase 1 `.with_tool` calls:

```ruby
        .with_tool(PlaceRowTool)
        .with_tool(PlaceColumnTool)
        .with_tool(PlaceSingleTool)
        .with_tool(PlaceBorderTool)
        .with_tool(PlaceFillTool)
```

- [ ] **Step 2: Update system prompt with layout instructions**

Add to the system prompt after the GARDEN MANAGEMENT section:

```
      LAYOUT TOOLS: For precise, intentional bed designs:
      - place_row: Horizontal row of plants (e.g., row of lettuce across front)
      - place_column: Vertical column (e.g., tomatoes up the back)
      - place_single: One plant at exact position (e.g., courgette in corner)
      - place_border: Plants along edges (e.g., marigold border on front+sides)
      - place_fill: Fill a region with plants at spacing (e.g., radishes in remaining space)

      For potager-style layouts, use these tools instead of draft_plan:
      1. Clear the bed if needed
      2. Place tall crops in back rows (place_column or place_row at high y)
      3. Place medium crops in middle
      4. Place borders/edges with place_border
      5. Fill remaining space with place_fill
      These tools skip occupied cells, so order matters — place large items first.
```

- [ ] **Step 3: Commit**

```bash
git add services/planner_service.rb
git commit -m "feat: register Phase 2 layout tools and update prompt"
```

---

## Phase 3: Bed Metadata & Zones

### Task 14: Database Migration

**Files:**
- Create: `db/migrations/020_add_bed_zones_and_metadata.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrations/020_add_bed_zones_and_metadata.rb`:

```ruby
Sequel.migration do
  change do
    # Bed metadata columns
    alter_table(:beds) do
      add_column :sun_exposure, String    # full, partial, shade
      add_column :wind_exposure, String   # sheltered, moderate, exposed
      add_column :irrigation, String      # drip, manual, sprinkler, none
      add_column :front_edge, String      # south, north, east, west, path
    end

    # Bed zones — named rectangles within a bed
    create_table(:bed_zones) do
      primary_key :id
      foreign_key :bed_id, :beds, on_delete: :cascade, null: false
      String :name, null: false           # e.g. "rear strip", "trellis lane"
      Integer :from_x, null: false
      Integer :from_y, null: false
      Integer :to_x, null: false
      Integer :to_y, null: false
      String :purpose                     # tall crops, border, trellis, etc.
      String :notes
      DateTime :created_at
    end
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `ruby -e "require_relative 'config/database'; Sequel::Migrator.run(DB, 'db/migrations')"`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add db/migrations/020_add_bed_zones_and_metadata.rb
git commit -m "feat: migration for bed zones and metadata columns"
```

---

### Task 15: BedZone Model

**Files:**
- Create: `models/bed_zone.rb`
- Modify: `models/bed.rb`

- [ ] **Step 1: Create BedZone model**

Create `models/bed_zone.rb`:

```ruby
require_relative "../config/database"

class BedZone < Sequel::Model(:bed_zones)
  many_to_one :bed
end
```

- [ ] **Step 2: Add association to Bed model**

In `models/bed.rb`, add after the existing `one_to_many :plants` line:

```ruby
    one_to_many :bed_zones
```

- [ ] **Step 3: Commit**

```bash
git add models/bed_zone.rb models/bed.rb
git commit -m "feat: BedZone model and bed association"
```

---

### Task 16: ManageZonesTool

**Files:**
- Create: `services/planner_tools/manage_zones_tool.rb`
- Create: `test/services/test_planner_zone_tools.rb`

- [ ] **Step 1: Write the test**

Create `test/services/test_planner_zone_tools.rb`:

```ruby
require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/bed_zone"
require_relative "../../services/planner_tools/manage_zones_tool"

class TestManageZonesTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_create_zone
    tool = ManageZonesTool.new
    result = tool.execute(bed_name: "BB1", action: "create", name: "rear strip", from_x: "0", from_y: "40", to_x: "24", to_y: "48", purpose: "tall crops")
    assert_includes result, "rear strip"
    assert_equal 1, BedZone.where(bed_id: @bed.id).count
  end

  def test_list_zones
    BedZone.create(bed_id: @bed.id, name: "front edge", from_x: 0, from_y: 0, to_x: 24, to_y: 4, purpose: "border flowers", created_at: Time.now)
    tool = ManageZonesTool.new
    result = tool.execute(bed_name: "BB1", action: "list")
    assert_includes result, "front edge"
  end

  def test_delete_zone
    zone = BedZone.create(bed_id: @bed.id, name: "temp", from_x: 0, from_y: 0, to_x: 10, to_y: 10, created_at: Time.now)
    tool = ManageZonesTool.new
    tool.execute(bed_name: "BB1", action: "delete", name: "temp")
    assert_equal 0, BedZone.where(bed_id: @bed.id).count
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_zone_tools.rb`
Expected: FAIL — ManageZonesTool not defined

- [ ] **Step 3: Write ManageZonesTool**

Create `services/planner_tools/manage_zones_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/bed_zone"

class ManageZonesTool < RubyLLM::Tool
  description "Create, list, or delete named zones within a bed. Zones define areas like 'rear strip' or 'trellis lane' with a purpose — they help you plan smarter layouts."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :action, type: :string, desc: '"create", "list", or "delete"'
  param :name, type: :string, desc: "Zone name (required for create/delete)"
  param :from_x, type: :string, desc: "Start grid column (create only)"
  param :from_y, type: :string, desc: "Start grid row (create only)"
  param :to_x, type: :string, desc: "End grid column (create only)"
  param :to_y, type: :string, desc: "End grid row (create only)"
  param :purpose, type: :string, desc: "Zone purpose, e.g. 'tall crops', 'border' (create only)"
  param :notes, type: :string, desc: "Additional notes (create only)"

  def execute(bed_name:, action:, name: nil, from_x: nil, from_y: nil, to_x: nil, to_y: nil, purpose: nil, notes: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    case action
    when "create"
      return "Error: name, from_x, from_y, to_x, to_y required" unless name && from_x && from_y && to_x && to_y
      BedZone.create(
        bed_id: bed.id, name: name,
        from_x: from_x.to_i, from_y: from_y.to_i,
        to_x: to_x.to_i, to_y: to_y.to_i,
        purpose: purpose, notes: notes,
        created_at: Time.now
      )
      Thread.current[:planner_needs_refresh] = true
      "Created zone '#{name}' on #{bed_name} (#{from_x},#{from_y})→(#{to_x},#{to_y}), purpose: #{purpose || 'general'}."

    when "list"
      zones = BedZone.where(bed_id: bed.id).all
      return "No zones defined for #{bed_name}" if zones.empty?
      zones.map { |z| "- #{z.name}: (#{z.from_x},#{z.from_y})→(#{z.to_x},#{z.to_y}) — #{z.purpose || 'no purpose set'}" }.join("\n")

    when "delete"
      return "Error: name required" unless name
      zone = BedZone.where(bed_id: bed.id, name: name).first
      return "Error: zone '#{name}' not found on #{bed_name}" unless zone
      zone.destroy
      Thread.current[:planner_needs_refresh] = true
      "Deleted zone '#{name}' from #{bed_name}."

    else
      "Error: action must be 'create', 'list', or 'delete'"
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_zone_tools.rb`
Expected: 3 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/manage_zones_tool.rb test/services/test_planner_zone_tools.rb
git commit -m "feat: ManageZonesTool — AI can create/list/delete bed zones"
```

---

### Task 17: UpdateBedMetadataTool

**Files:**
- Create: `services/planner_tools/update_bed_metadata_tool.rb`
- Modify: `test/services/test_planner_zone_tools.rb`

- [ ] **Step 1: Write the test**

Append to `test/services/test_planner_zone_tools.rb`:

```ruby
require_relative "../../services/planner_tools/update_bed_metadata_tool"

class TestUpdateBedMetadataTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_updates_metadata
    tool = UpdateBedMetadataTool.new
    tool.execute(bed_name: "BB1", sun_exposure: "full", front_edge: "south", irrigation: "drip")
    @bed.refresh
    assert_equal "full", @bed.sun_exposure
    assert_equal "south", @bed.front_edge
    assert_equal "drip", @bed.irrigation
  end

  def test_unknown_bed
    tool = UpdateBedMetadataTool.new
    result = tool.execute(bed_name: "NOPE", sun_exposure: "full")
    assert_includes result, "not found"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_zone_tools.rb`
Expected: FAIL — UpdateBedMetadataTool not defined

- [ ] **Step 3: Write UpdateBedMetadataTool**

Create `services/planner_tools/update_bed_metadata_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"

class UpdateBedMetadataTool < RubyLLM::Tool
  description "Update a bed's environmental metadata — sun exposure, wind, irrigation, and which edge faces the viewer/path. This helps you make better planting decisions."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :sun_exposure, type: :string, desc: '"full", "partial", or "shade" (optional)'
  param :wind_exposure, type: :string, desc: '"sheltered", "moderate", or "exposed" (optional)'
  param :irrigation, type: :string, desc: '"drip", "manual", "sprinkler", or "none" (optional)'
  param :front_edge, type: :string, desc: '"south", "north", "east", "west", or "path" — which side faces viewer (optional)'

  def execute(bed_name:, sun_exposure: nil, wind_exposure: nil, irrigation: nil, front_edge: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    updates = {}
    updates[:sun_exposure] = sun_exposure if sun_exposure
    updates[:wind_exposure] = wind_exposure if wind_exposure
    updates[:irrigation] = irrigation if irrigation
    updates[:front_edge] = front_edge if front_edge

    return "Error: provide at least one field to update" if updates.empty?

    bed.update(updates)
    Thread.current[:planner_needs_refresh] = true
    "Updated #{bed_name}: #{updates.map { |k, v| "#{k}=#{v}" }.join(', ')}."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_zone_tools.rb`
Expected: 5 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/update_bed_metadata_tool.rb test/services/test_planner_zone_tools.rb
git commit -m "feat: UpdateBedMetadataTool — AI can set bed sun/wind/irrigation/orientation"
```

---

### Task 18: Update GetBedsTool to Include Zones and Metadata

**Files:**
- Modify: `services/planner_tools/get_beds_tool.rb`

- [ ] **Step 1: Add zones and metadata to bed output**

In `services/planner_tools/get_beds_tool.rb`, add `require_relative "../../models/bed_zone"` at the top.

Then in the bed hash (around line 39-51), add after `total_plants: plants.length`:

```ruby
        zones: BedZone.where(bed_id: bed.id).all.map { |z|
          { name: z.name, from_x: z.from_x, from_y: z.from_y, to_x: z.to_x, to_y: z.to_y, purpose: z.purpose, notes: z.notes }
        },
        sun_exposure: bed.sun_exposure,
        wind_exposure: bed.wind_exposure,
        irrigation: bed.irrigation,
        front_edge: bed.front_edge,
```

- [ ] **Step 2: Commit**

```bash
git add services/planner_tools/get_beds_tool.rb
git commit -m "feat: GetBedsTool returns zones and bed metadata for AI context"
```

---

### Task 19: Register Phase 3 Tools + Update Prompt

**Files:**
- Modify: `services/planner_service.rb`

- [ ] **Step 1: Add requires and registrations**

In `services/planner_service.rb`, add after the Phase 2 requires:

```ruby
require_relative "planner_tools/manage_zones_tool"
require_relative "planner_tools/update_bed_metadata_tool"
```

In the `chat` method, add after the Phase 2 `.with_tool` calls:

```ruby
        .with_tool(ManageZonesTool)
        .with_tool(UpdateBedMetadataTool)
```

- [ ] **Step 2: Update system prompt with zone/metadata instructions**

Add to the system prompt:

```
      BED ZONES & METADATA: Beds can have named zones (e.g., "rear strip" for
      tall crops, "front edge" for borders) and environmental metadata (sun,
      wind, irrigation, front_edge). Use get_beds to see existing zones and
      metadata. Use manage_zones to define zones, update_bed_metadata to set
      environmental info. When placing plants, respect zones — put tall crops
      in rear zones, borders in front edge zones, etc.
```

- [ ] **Step 3: Commit**

```bash
git add services/planner_service.rb
git commit -m "feat: register Phase 3 zone/metadata tools and update prompt"
```

---

## Phase 4: Operational Features

### Task 20: Duplicate Detection in DraftPlanTool

**Files:**
- Modify: `services/planner_tools/draft_plan_tool.rb`

- [ ] **Step 1: Add duplicate detection**

Replace the `execute` method in `services/planner_tools/draft_plan_tool.rb`:

```ruby
  def execute(payload:)
    parsed = JSON.parse(payload)
    Thread.current[:planner_draft] = parsed

    a = parsed["assignments"]&.length || 0
    s = parsed["successions"]&.length || 0
    t = parsed["tasks"]&.length || 0

    # Check for duplicate assignments
    warnings = []
    garden_id = Thread.current[:current_garden_id]
    (parsed["assignments"] || []).each do |assignment|
      bed = Bed.where(name: assignment["bed_name"], garden_id: garden_id).first
      next unless bed
      existing = Plant.where(
        bed_id: bed.id,
        variety_name: assignment["variety_name"],
        crop_type: assignment["crop_type"]
      ).exclude(lifecycle_stage: "done").count
      if existing > 0
        warnings << "#{assignment['bed_name']} already has #{existing} #{assignment['variety_name']} (#{assignment['crop_type']})"
      end
    end

    msg = "Draft stored: #{a} plant assignments, #{s} succession schedules, #{t} tasks."
    msg += " WARNINGS: #{warnings.join('; ')}. Ask the user whether to replace or add." if warnings.any?
    msg += " Present a summary to the user — they'll see a visual card with a 'Create this plan' button."
    msg
  rescue JSON::ParserError => e
    "Error: Invalid JSON. #{e.message}"
  end
```

- [ ] **Step 2: Commit**

```bash
git add services/planner_tools/draft_plan_tool.rb
git commit -m "feat: DraftPlanTool warns about duplicate plant assignments"
```

---

### Task 21: DeduplicateBedTool

**Files:**
- Create: `services/planner_tools/deduplicate_bed_tool.rb`
- Create: `test/services/test_planner_operational_tools.rb`

- [ ] **Step 1: Write the test**

Create `test/services/test_planner_operational_tools.rb`:

```ruby
require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/plant"
require_relative "../../services/planner_tools/deduplicate_bed_tool"

class TestDeduplicateBedTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_removes_duplicates_keeps_oldest
    p1 = Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6, created_at: Time.now - 100)
    p2 = Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 6, grid_y: 0, grid_w: 6, grid_h: 6, created_at: Time.now)
    p3 = Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Basil", crop_type: "herb", grid_x: 0, grid_y: 6, grid_w: 4, grid_h: 4, created_at: Time.now)

    tool = DeduplicateBedTool.new
    result = tool.execute(bed_name: "BB1")
    assert_includes result, "1"  # 1 duplicate removed
    assert_equal 2, Plant.where(bed_id: @bed.id).count
    # The older one (p1) should be kept
    assert Plant[p1.id], "Oldest should survive"
    assert_nil Plant[p2.id], "Newer duplicate should be removed"
    assert Plant[p3.id], "Non-duplicate should survive"
  end

  def test_no_duplicates
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Raf", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    tool = DeduplicateBedTool.new
    result = tool.execute(bed_name: "BB1")
    assert_includes result, "No duplicates"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_operational_tools.rb`
Expected: FAIL — DeduplicateBedTool not defined

- [ ] **Step 3: Write DeduplicateBedTool**

Create `services/planner_tools/deduplicate_bed_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class DeduplicateBedTool < RubyLLM::Tool
  description "Find and remove duplicate plants on a bed (same variety + crop type). Keeps the oldest of each group. Use after repeated draft applications that created duplicates."

  param :bed_name, type: :string, desc: "Exact bed name"

  def execute(bed_name:)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    plants = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").order(:created_at).all
    groups = plants.group_by { |p| [p.variety_name, p.crop_type] }

    removed = 0
    groups.each do |_key, group|
      next if group.length <= 1
      # Keep the first (oldest), destroy the rest
      group[1..].each do |dup|
        dup.destroy
        removed += 1
      end
    end

    return "No duplicates found on #{bed_name}." if removed == 0

    Thread.current[:planner_needs_refresh] = true
    "Removed #{removed} duplicate(s) from #{bed_name}. Kept oldest of each variety."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_operational_tools.rb`
Expected: 2 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/deduplicate_bed_tool.rb test/services/test_planner_operational_tools.rb
git commit -m "feat: DeduplicateBedTool — AI can clean up duplicate plant assignments"
```

---

### Task 22: SetPlantNotesTool

**Files:**
- Create: `services/planner_tools/set_plant_notes_tool.rb`
- Modify: `test/services/test_planner_operational_tools.rb`

- [ ] **Step 1: Write the test**

Append to `test/services/test_planner_operational_tools.rb`:

```ruby
require_relative "../../services/planner_tools/set_plant_notes_tool"

class TestSetPlantNotesTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    @plant = Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Courgette", crop_type: "zucchini", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 8)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_set_notes_by_id
    tool = SetPlantNotesTool.new
    tool.execute(plant_id: @plant.id.to_s, notes: "Let spill over front edge")
    @plant.refresh
    assert_equal "Let spill over front edge", @plant.notes
  end

  def test_set_notes_by_bed_and_variety
    tool = SetPlantNotesTool.new
    tool.execute(bed_name: "BB1", variety_name: "Courgette", notes: "Train toward path")
    @plant.refresh
    assert_equal "Train toward path", @plant.notes
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_operational_tools.rb`
Expected: FAIL — SetPlantNotesTool not defined

- [ ] **Step 3: Write SetPlantNotesTool**

Create `services/planner_tools/set_plant_notes_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class SetPlantNotesTool < RubyLLM::Tool
  description "Set design-intent notes on a plant. Use to annotate placement decisions like 'let spill over edge' or 'harvest before canopy closes'. Find by plant ID or bed+variety."

  param :plant_id, type: :string, desc: "Plant ID (optional if bed_name+variety_name given)"
  param :bed_name, type: :string, desc: "Bed name (optional if plant_id given)"
  param :variety_name, type: :string, desc: "Variety name (optional if plant_id given)"
  param :notes, type: :string, desc: "The note to set"

  def execute(notes:, plant_id: nil, bed_name: nil, variety_name: nil)
    garden_id = Thread.current[:current_garden_id]

    if plant_id
      plant = Plant[plant_id.to_i]
      return "Error: plant not found" unless plant && plant.garden_id == garden_id
    elsif bed_name && variety_name
      bed = Bed.where(name: bed_name, garden_id: garden_id).first
      return "Error: bed '#{bed_name}' not found" unless bed
      plant = Plant.where(bed_id: bed.id, variety_name: variety_name).exclude(lifecycle_stage: "done").first
      return "Error: #{variety_name} not found on #{bed_name}" unless plant
    else
      return "Error: provide plant_id or bed_name+variety_name"
    end

    plant.update(notes: notes, updated_at: Time.now)
    "Set note on #{plant.variety_name}: \"#{notes}\""
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_operational_tools.rb`
Expected: 4 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/set_plant_notes_tool.rb test/services/test_planner_operational_tools.rb
git commit -m "feat: SetPlantNotesTool — AI can annotate plants with design intent"
```

---

### Task 23: Register Phase 4 Tools + Final Prompt Update

**Files:**
- Modify: `services/planner_service.rb`

- [ ] **Step 1: Add requires and registrations**

In `services/planner_service.rb`, add after the Phase 3 requires:

```ruby
require_relative "planner_tools/deduplicate_bed_tool"
require_relative "planner_tools/set_plant_notes_tool"
```

In the `chat` method, add after the Phase 3 `.with_tool` calls:

```ruby
        .with_tool(DeduplicateBedTool)
        .with_tool(SetPlantNotesTool)
```

- [ ] **Step 2: Update system prompt with operational instructions**

Add to the system prompt:

```
      OPERATIONAL TOOLS:
      - deduplicate_bed: Remove duplicate plants (same variety+crop) on a bed
      - set_plant_notes: Annotate plants with design intent (e.g., "let spill over edge")

      Before calling draft_plan, check if proposed assignments duplicate plants
      already on target beds. If duplicates exist, mention them and ask whether
      to replace (clear first) or add more.
```

- [ ] **Step 3: Commit**

```bash
git add services/planner_service.rb
git commit -m "feat: register Phase 4 operational tools and final prompt update"
```

---

### Task 24: Run Full Test Suite

- [ ] **Step 1: Run all tests**

Run: `ruby -Itest -e "Dir['test/**/*test*.rb'].each { |f| require_relative f }"`
Expected: All tests pass, 0 failures

- [ ] **Step 2: Run just the new planner tool tests**

Run: `ruby -Itest test/services/test_planner_crud_tools.rb test/services/test_planner_layout_tools.rb test/services/test_planner_zone_tools.rb test/services/test_planner_operational_tools.rb`
Expected: All pass

- [ ] **Step 3: Commit any fixes if needed**

---

### Task 25: Deploy and Verify

- [ ] **Step 1: Push to main**

```bash
git push
```

- [ ] **Step 2: Verify feature requests API still works**

```bash
curl -s https://garden.lightinmeadows.com/api/feature-requests | python3 -m json.tool
```

- [ ] **Step 3: Test the AI planner with a redesign request**

Open the AI drawer and try: "Clear BB1 and redesign it with tomatoes in the back row, basil border on front, and fill remaining space with lettuce"

The AI should:
1. Call `clear_bed` for BB1
2. Call `place_row` or `place_column` for tomatoes
3. Call `place_border` for basil
4. Call `place_fill` for lettuce
