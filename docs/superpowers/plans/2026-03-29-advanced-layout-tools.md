# Advanced Layout & Composition Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the AI planner spatial intelligence for potager-style garden design — zone placement, alignment, mirroring, polygon-aware fitting, empty-space analysis, and decorative composition rules, plus frontend preview enhancements.

**Architecture:** New RubyLLM tool classes in `services/planner_tools/` following existing patterns. A `point_in_polygon?` helper on the Bed model enables polygon-aware placement across all tools. Frontend enhancements in `BedCanvas.tsx` and `PlantRect.tsx` add polygon clipping, quantity badges, and notes indicators.

**Tech Stack:** Ruby/Sinatra, Sequel ORM, RubyLLM tools, Minitest, React/TypeScript, SVG

---

## File Map

**New files:**
- `services/planner_tools/place_in_zone_tool.rb`
- `services/planner_tools/align_plants_tool.rb`
- `services/planner_tools/group_edit_tool.rb`
- `services/planner_tools/place_band_tool.rb`
- `services/planner_tools/copy_layout_tool.rb`
- `services/planner_tools/get_empty_space_tool.rb`
- `test/services/test_planner_spatial_tools.rb`
- `test/services/test_planner_advanced_tools.rb`
- `test/models/test_bed_polygon.rb`

**Modified files:**
- `models/bed.rb` — add `point_in_polygon?` method
- `services/planner_tools/place_row_tool.rb` — add polygon check
- `services/planner_tools/place_column_tool.rb` — add polygon check
- `services/planner_tools/place_fill_tool.rb` — add polygon check
- `services/planner_tools/place_border_tool.rb` — add polygon check
- `services/planner_service.rb` — register new tools, update prompt
- `routes/beds.rb` — include `notes` in plant JSON
- `src/lib/api.ts` — add `notes` to BedPlant interface
- `src/components/bed/PlantRect.tsx` — quantity badge, notes indicator
- `src/components/bed/BedCanvas.tsx` — polygon clipping

---

## Phase A: Core Spatial Tools

### Task 1: PlaceInZoneTool

**Files:**
- Create: `services/planner_tools/place_in_zone_tool.rb`
- Create: `test/services/test_planner_spatial_tools.rb`

- [ ] **Step 1: Write the test**

Create `test/services/test_planner_spatial_tools.rb`:

```ruby
require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/bed_zone"
require_relative "../../models/plant"
require_relative "../../services/planner_tools/place_in_zone_tool"

class TestPlaceInZoneTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    @zone = BedZone.create(bed_id: @bed.id, name: "rear", from_x: 0, from_y: 36, to_x: 24, to_y: 48, purpose: "tall crops", created_at: Time.now)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_fill_zone
    tool = PlaceInZoneTool.new
    tool.execute(bed_name: "BB1", zone_name: "rear", variety_name: "Tomato", crop_type: "tomato", strategy: "fill")
    plants = Plant.where(bed_id: @bed.id).all
    assert plants.length > 0
    plants.each do |p|
      assert p.grid_x >= 0 && p.grid_x < 24, "x=#{p.grid_x} should be in zone"
      assert p.grid_y >= 36 && p.grid_y < 48, "y=#{p.grid_y} should be in zone"
    end
  end

  def test_center_zone
    tool = PlaceInZoneTool.new
    tool.execute(bed_name: "BB1", zone_name: "rear", variety_name: "Squash", crop_type: "squash", strategy: "center")
    plants = Plant.where(bed_id: @bed.id).all
    assert_equal 1, plants.length
  end

  def test_row_in_zone
    tool = PlaceInZoneTool.new
    tool.execute(bed_name: "BB1", zone_name: "rear", variety_name: "Lettuce", crop_type: "lettuce", strategy: "row")
    plants = Plant.where(bed_id: @bed.id).all
    assert plants.length > 0
    ys = plants.map(&:grid_y).uniq
    assert_equal 1, ys.length, "All plants should be in same row"
  end

  def test_unknown_zone
    tool = PlaceInZoneTool.new
    result = tool.execute(bed_name: "BB1", zone_name: "nope", variety_name: "X", crop_type: "x", strategy: "fill")
    assert_includes result, "not found"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_spatial_tools.rb`
Expected: FAIL — PlaceInZoneTool not defined

- [ ] **Step 3: Write PlaceInZoneTool**

Create `services/planner_tools/place_in_zone_tool.rb`:

```ruby
require "ruby_llm"
require "set"
require_relative "../../models/bed"
require_relative "../../models/bed_zone"
require_relative "../../models/plant"

class PlaceInZoneTool < RubyLLM::Tool
  description "Place plants within a named bed zone. Strategies: 'fill' (fill zone), 'row' (horizontal row through center), 'column' (vertical column through center), 'border' (along zone edges), 'center' (one plant centered)."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :zone_name, type: :string, desc: "Name of the zone within the bed"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type"
  param :strategy, type: :string, desc: '"fill", "row", "column", "border", or "center"'
  param :spacing, type: :string, desc: "Grid cells between plants (optional, uses crop default)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, zone_name:, variety_name:, crop_type:, strategy:, spacing: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed
    return "Error: bed_zones table not available" unless DB.table_exists?(:bed_zones)

    zone = BedZone.where(bed_id: bed.id, name: zone_name).first
    return "Error: zone '#{zone_name}' not found on #{bed_name}" unless zone

    gw, gh = Plant.default_grid_size(crop_type)
    step_x = spacing ? spacing.to_i : gw
    step_y = spacing ? spacing.to_i : gh

    existing = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all
    occupied = Set.new
    existing.each do |p|
      (p.grid_x...(p.grid_x + p.grid_w)).each do |cx|
        (p.grid_y...(p.grid_y + p.grid_h)).each do |cy|
          occupied.add([cx, cy])
        end
      end
    end

    positions = case strategy
    when "fill"
      pos = []
      y = zone.from_y
      while y + gh <= zone.to_y
        x = zone.from_x
        while x + gw <= zone.to_x
          overlap = (x...(x + gw)).any? { |cx| (y...(y + gh)).any? { |cy| occupied.include?([cx, cy]) } }
          pos << [x, y] unless overlap
          x += step_x
        end
        y += step_y
      end
      pos
    when "row"
      mid_y = zone.from_y + (zone.to_y - zone.from_y - gh) / 2
      pos = []
      x = zone.from_x
      while x + gw <= zone.to_x
        pos << [x, mid_y] unless occupied.include?([x, mid_y])
        x += step_x
      end
      pos
    when "column"
      mid_x = zone.from_x + (zone.to_x - zone.from_x - gw) / 2
      pos = []
      y = zone.from_y
      while y + gh <= zone.to_y
        pos << [mid_x, y] unless occupied.include?([mid_x, y])
        y += step_y
      end
      pos
    when "border"
      pos = []
      x = zone.from_x
      while x + gw <= zone.to_x
        pos << [x, zone.from_y] unless occupied.include?([x, zone.from_y])
        y_bot = zone.to_y - gh
        pos << [x, y_bot] unless occupied.include?([x, y_bot]) || y_bot == zone.from_y
        x += step_x
      end
      y = zone.from_y + step_y
      while y + gh <= zone.to_y - gh
        pos << [zone.from_x, y] unless occupied.include?([zone.from_x, y])
        x_r = zone.to_x - gw
        pos << [x_r, y] unless occupied.include?([x_r, y]) || x_r == zone.from_x
        y += step_y
      end
      pos.uniq
    when "center"
      cx = zone.from_x + (zone.to_x - zone.from_x - gw) / 2
      cy = zone.from_y + (zone.to_y - zone.from_y - gh) / 2
      overlap = (cx...(cx + gw)).any? { |x| (cy...(cy + gh)).any? { |y| occupied.include?([x, y]) } }
      overlap ? [] : [[cx, cy]]
    else
      return "Error: strategy must be 'fill', 'row', 'column', 'border', or 'center'"
    end

    positions.each do |x, y|
      Plant.create(
        garden_id: garden_id, bed_id: bed.id,
        variety_name: variety_name, crop_type: crop_type, source: source,
        lifecycle_stage: "seed_packet",
        grid_x: x, grid_y: y, grid_w: gw, grid_h: gh, quantity: 1
      )
    end

    Thread.current[:planner_needs_refresh] = true
    "Placed #{positions.length} #{variety_name} in zone '#{zone_name}' (#{strategy}) on #{bed_name}."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_spatial_tools.rb`
Expected: 4 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/place_in_zone_tool.rb test/services/test_planner_spatial_tools.rb
git commit -m "feat: PlaceInZoneTool — place plants within named bed zones"
```

---

### Task 2: AlignPlantsTool

**Files:**
- Create: `services/planner_tools/align_plants_tool.rb`
- Modify: `test/services/test_planner_spatial_tools.rb`

- [ ] **Step 1: Write the test**

Append to `test/services/test_planner_spatial_tools.rb`:

```ruby
require_relative "../../services/planner_tools/align_plants_tool"

class TestAlignPlantsTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 2, grid_y: 5, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Pepper", crop_type: "pepper", grid_x: 10, grid_y: 3, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Basil", crop_type: "herb", grid_x: 7, grid_y: 20, grid_w: 4, grid_h: 4)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_align_left
    tool = AlignPlantsTool.new
    tool.execute(bed_name: "BB1", operation: "align-left")
    plants = Plant.where(bed_id: @bed.id).all
    assert plants.all? { |p| p.grid_x == 2 }, "All should align to leftmost x=2"
  end

  def test_align_top
    tool = AlignPlantsTool.new
    tool.execute(bed_name: "BB1", operation: "align-top")
    plants = Plant.where(bed_id: @bed.id).all
    assert plants.all? { |p| p.grid_y == 3 }, "All should align to topmost y=3"
  end

  def test_distribute_h
    tool = AlignPlantsTool.new
    tool.execute(bed_name: "BB1", operation: "distribute-h")
    plants = Plant.where(bed_id: @bed.id).order(:grid_x).all
    xs = plants.map(&:grid_x)
    gaps = xs.each_cons(2).map { |a, b| b - a }
    assert gaps.length >= 1
    assert gaps.uniq.length <= 2, "Gaps should be roughly equal (rounding allowed)"
  end

  def test_filter_by_crop_type
    tool = AlignPlantsTool.new
    tool.execute(bed_name: "BB1", operation: "align-left", filter_crop_type: "tomato")
    tomato = Plant.where(bed_id: @bed.id, crop_type: "tomato").first
    pepper = Plant.where(bed_id: @bed.id, crop_type: "pepper").first
    assert_equal 2, tomato.grid_x, "Tomato unchanged (already at 2)"
    assert_equal 10, pepper.grid_x, "Pepper should NOT be affected"
  end

  def test_compact
    tool = AlignPlantsTool.new
    tool.execute(bed_name: "BB1", operation: "compact")
    plants = Plant.where(bed_id: @bed.id).order(:grid_y, :grid_x).all
    assert plants.first.grid_x == 0 || plants.first.grid_y == 0, "Should pack toward origin"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_spatial_tools.rb`
Expected: FAIL — AlignPlantsTool not defined

- [ ] **Step 3: Write AlignPlantsTool**

Create `services/planner_tools/align_plants_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class AlignPlantsTool < RubyLLM::Tool
  description "Align or distribute existing plants on a bed. Operations: align-left, align-right, align-top, align-bottom, center-h, center-v, distribute-h, distribute-v, compact."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :operation, type: :string, desc: '"align-left", "align-right", "align-top", "align-bottom", "center-h", "center-v", "distribute-h", "distribute-v", "compact"'
  param :filter_variety, type: :string, desc: "Only affect plants with this variety (optional)"
  param :filter_crop_type, type: :string, desc: "Only affect plants with this crop type (optional)"

  def execute(bed_name:, operation:, filter_variety: nil, filter_crop_type: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    scope = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done")
    scope = scope.where(variety_name: filter_variety) if filter_variety
    scope = scope.where(crop_type: filter_crop_type) if filter_crop_type
    plants = scope.all
    return "No matching plants on #{bed_name}" if plants.empty?

    case operation
    when "align-left"
      min_x = plants.map(&:grid_x).min
      plants.each { |p| p.update(grid_x: min_x, updated_at: Time.now) }

    when "align-right"
      max_right = plants.map { |p| p.grid_x + p.grid_w }.max
      plants.each { |p| p.update(grid_x: max_right - p.grid_w, updated_at: Time.now) }

    when "align-top"
      min_y = plants.map(&:grid_y).min
      plants.each { |p| p.update(grid_y: min_y, updated_at: Time.now) }

    when "align-bottom"
      max_bottom = plants.map { |p| p.grid_y + p.grid_h }.max
      plants.each { |p| p.update(grid_y: max_bottom - p.grid_h, updated_at: Time.now) }

    when "center-h"
      plants.each do |p|
        cx = (bed.grid_cols - p.grid_w) / 2
        p.update(grid_x: cx.clamp(0, bed.grid_cols - p.grid_w), updated_at: Time.now)
      end

    when "center-v"
      plants.each do |p|
        cy = (bed.grid_rows - p.grid_h) / 2
        p.update(grid_y: cy.clamp(0, bed.grid_rows - p.grid_h), updated_at: Time.now)
      end

    when "distribute-h"
      sorted = plants.sort_by(&:grid_x)
      return "Need 2+ plants to distribute" if sorted.length < 2
      total_plant_w = sorted.sum(&:grid_w)
      total_space = bed.grid_cols - total_plant_w
      gap = total_space.to_f / (sorted.length - 1)
      x = 0
      sorted.each_with_index do |p, i|
        p.update(grid_x: x.round.clamp(0, bed.grid_cols - p.grid_w), updated_at: Time.now)
        x += p.grid_w + gap
      end

    when "distribute-v"
      sorted = plants.sort_by(&:grid_y)
      return "Need 2+ plants to distribute" if sorted.length < 2
      total_plant_h = sorted.sum(&:grid_h)
      total_space = bed.grid_rows - total_plant_h
      gap = total_space.to_f / (sorted.length - 1)
      y = 0
      sorted.each_with_index do |p, i|
        p.update(grid_y: y.round.clamp(0, bed.grid_rows - p.grid_h), updated_at: Time.now)
        y += p.grid_h + gap
      end

    when "compact"
      sorted = plants.sort_by { |p| [p.grid_y, p.grid_x] }
      cursor_x = 0
      cursor_y = 0
      row_h = 0
      sorted.each do |p|
        if cursor_x + p.grid_w > bed.grid_cols
          cursor_x = 0
          cursor_y += row_h
          row_h = 0
        end
        p.update(grid_x: cursor_x, grid_y: cursor_y, updated_at: Time.now)
        cursor_x += p.grid_w
        row_h = [row_h, p.grid_h].max
      end

    else
      return "Error: unknown operation '#{operation}'"
    end

    Thread.current[:planner_needs_refresh] = true
    "#{operation}: adjusted #{plants.length} plants on #{bed_name}."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_spatial_tools.rb`
Expected: 9 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/align_plants_tool.rb test/services/test_planner_spatial_tools.rb
git commit -m "feat: AlignPlantsTool — align, distribute, compact plants on beds"
```

---

### Task 3: GroupEditTool

**Files:**
- Create: `services/planner_tools/group_edit_tool.rb`
- Modify: `test/services/test_planner_spatial_tools.rb`

- [ ] **Step 1: Write the test**

Append to `test/services/test_planner_spatial_tools.rb`:

```ruby
require_relative "../../services/planner_tools/group_edit_tool"

class TestGroupEditTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 5, grid_y: 10, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 15, grid_y: 10, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Basil", crop_type: "herb", grid_x: 0, grid_y: 0, grid_w: 4, grid_h: 4)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_group_move
    tool = GroupEditTool.new
    tool.execute(bed_name: "BB1", action: "move", filter_crop_type: "tomato", dx: "3", dy: "-2")
    tomatoes = Plant.where(bed_id: @bed.id, crop_type: "tomato").all
    assert_equal [8, 18], tomatoes.map(&:grid_x).sort
    assert tomatoes.all? { |p| p.grid_y == 8 }
    basil = Plant.where(bed_id: @bed.id, crop_type: "herb").first
    assert_equal 0, basil.grid_x, "Basil should not move"
  end

  def test_group_resize
    tool = GroupEditTool.new
    tool.execute(bed_name: "BB1", action: "resize", filter_crop_type: "tomato", grid_w: "8", grid_h: "8")
    tomatoes = Plant.where(bed_id: @bed.id, crop_type: "tomato").all
    assert tomatoes.all? { |p| p.grid_w == 8 && p.grid_h == 8 }
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_spatial_tools.rb`
Expected: FAIL — GroupEditTool not defined

- [ ] **Step 3: Write GroupEditTool**

Create `services/planner_tools/group_edit_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class GroupEditTool < RubyLLM::Tool
  description "Move or resize multiple plants at once. Filter by variety or crop type. Move shifts all matching plants by dx/dy grid cells. Resize sets new grid_w/grid_h."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :action, type: :string, desc: '"move" or "resize"'
  param :filter_variety, type: :string, desc: "Only affect this variety (optional)"
  param :filter_crop_type, type: :string, desc: "Only affect this crop type (optional)"
  param :dx, type: :string, desc: "Horizontal shift in grid cells (move only)"
  param :dy, type: :string, desc: "Vertical shift in grid cells (move only)"
  param :grid_w, type: :string, desc: "New width in grid cells (resize only)"
  param :grid_h, type: :string, desc: "New height in grid cells (resize only)"

  def execute(bed_name:, action:, filter_variety: nil, filter_crop_type: nil, dx: nil, dy: nil, grid_w: nil, grid_h: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    scope = Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done")
    scope = scope.where(variety_name: filter_variety) if filter_variety
    scope = scope.where(crop_type: filter_crop_type) if filter_crop_type
    plants = scope.all
    return "No matching plants on #{bed_name}" if plants.empty?

    case action
    when "move"
      shift_x = dx ? dx.to_i : 0
      shift_y = dy ? dy.to_i : 0
      return "Error: provide dx and/or dy for move" if shift_x == 0 && shift_y == 0
      plants.each do |p|
        new_x = (p.grid_x + shift_x).clamp(0, bed.grid_cols - p.grid_w)
        new_y = (p.grid_y + shift_y).clamp(0, bed.grid_rows - p.grid_h)
        p.update(grid_x: new_x, grid_y: new_y, updated_at: Time.now)
      end
    when "resize"
      updates = {}
      updates[:grid_w] = grid_w.to_i if grid_w
      updates[:grid_h] = grid_h.to_i if grid_h
      return "Error: provide grid_w and/or grid_h for resize" if updates.empty?
      updates[:updated_at] = Time.now
      plants.each { |p| p.update(updates) }
    else
      return "Error: action must be 'move' or 'resize'"
    end

    Thread.current[:planner_needs_refresh] = true
    "#{action}: updated #{plants.length} plants on #{bed_name}."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_spatial_tools.rb`
Expected: 11 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/group_edit_tool.rb test/services/test_planner_spatial_tools.rb
git commit -m "feat: GroupEditTool — batch move/resize plants by filter"
```

---

### Task 4: PlaceBandTool

**Files:**
- Create: `services/planner_tools/place_band_tool.rb`
- Modify: `test/services/test_planner_spatial_tools.rb`

- [ ] **Step 1: Write the test**

Append to `test/services/test_planner_spatial_tools.rb`:

```ruby
require_relative "../../services/planner_tools/place_band_tool"

class TestPlaceBandTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_horizontal_band
    tool = PlaceBandTool.new
    tool.execute(bed_name: "BB1", variety_name: "Radish", crop_type: "radish", orientation: "horizontal", position: "10", thickness: "4", quantity: "50")
    plant = Plant.where(bed_id: @bed.id).first
    assert_equal 0, plant.grid_x
    assert_equal 10, plant.grid_y
    assert_equal 24, plant.grid_w  # full bed width (120cm / 5cm = 24 cols)
    assert_equal 4, plant.grid_h
    assert_equal 50, plant.quantity
  end

  def test_vertical_band
    tool = PlaceBandTool.new
    tool.execute(bed_name: "BB1", variety_name: "Carrot", crop_type: "carrot", orientation: "vertical", position: "5", thickness: "3", quantity: "30")
    plant = Plant.where(bed_id: @bed.id).first
    assert_equal 5, plant.grid_x
    assert_equal 0, plant.grid_y
    assert_equal 3, plant.grid_w
    assert_equal 48, plant.grid_h  # full bed height (240cm / 5cm = 48 rows)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_spatial_tools.rb`
Expected: FAIL — PlaceBandTool not defined

- [ ] **Step 3: Write PlaceBandTool**

Create `services/planner_tools/place_band_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class PlaceBandTool < RubyLLM::Tool
  description "Place a wide band/strip of dense planting — like a seed row or salad mix block. Creates one plant record with a large rectangular footprint and high quantity. Good for broadcast-sown crops (radish, mesclun, carrot)."

  param :bed_name, type: :string, desc: "Exact bed name"
  param :variety_name, type: :string, desc: "Variety to plant"
  param :crop_type, type: :string, desc: "Crop type"
  param :orientation, type: :string, desc: '"horizontal" or "vertical"'
  param :position, type: :string, desc: "Grid row (horizontal) or column (vertical) to start the band"
  param :thickness, type: :string, desc: "Band width in grid cells (optional, uses crop default height)"
  param :length, type: :string, desc: "Band length in cells (optional, defaults to full bed width/height)"
  param :quantity, type: :string, desc: "Number of plants this band represents (optional, default 1)"
  param :source, type: :string, desc: "Seed source (optional)"

  def execute(bed_name:, variety_name:, crop_type:, orientation:, position:, thickness: nil, length: nil, quantity: nil, source: nil)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    gw, gh = Plant.default_grid_size(crop_type)
    pos = position.to_i

    case orientation
    when "horizontal"
      band_w = length ? length.to_i : bed.grid_cols
      band_h = thickness ? thickness.to_i : gh
      x = 0
      y = pos
    when "vertical"
      band_w = thickness ? thickness.to_i : gw
      band_h = length ? length.to_i : bed.grid_rows
      x = pos
      y = 0
    else
      return "Error: orientation must be 'horizontal' or 'vertical'"
    end

    plant = Plant.create(
      garden_id: garden_id, bed_id: bed.id,
      variety_name: variety_name, crop_type: crop_type, source: source,
      lifecycle_stage: "seed_packet",
      grid_x: x, grid_y: y,
      grid_w: band_w.clamp(1, bed.grid_cols),
      grid_h: band_h.clamp(1, bed.grid_rows),
      quantity: quantity ? quantity.to_i : 1
    )

    Thread.current[:planner_needs_refresh] = true
    "Placed #{orientation} band of #{variety_name} at position #{pos}, size #{plant.grid_w}x#{plant.grid_h}, quantity #{plant.quantity}."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_spatial_tools.rb`
Expected: 13 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/place_band_tool.rb test/services/test_planner_spatial_tools.rb
git commit -m "feat: PlaceBandTool — wide seed-row/strip placement for broadcast crops"
```

---

### Task 5: Register Phase A Tools + Update Prompt

**Files:**
- Modify: `services/planner_service.rb`

- [ ] **Step 1: Add requires after the existing tool requires (after line 28)**

```ruby
require_relative "planner_tools/place_in_zone_tool"
require_relative "planner_tools/align_plants_tool"
require_relative "planner_tools/group_edit_tool"
require_relative "planner_tools/place_band_tool"
```

- [ ] **Step 2: Add `.with_tool` registrations after `.with_tool(DeduplicateSuccessionPlansTool)` (after line 176)**

```ruby
        .with_tool(PlaceInZoneTool)
        .with_tool(AlignPlantsTool)
        .with_tool(GroupEditTool)
        .with_tool(PlaceBandTool)
```

- [ ] **Step 3: Update system prompt**

In the LAYOUT TOOLS section, add:

```
      - place_in_zone: Place plants within a named zone (fill, row, column, border, center)
      - align_plants: Align/distribute plants (align-left/right/top/bottom, center-h/v, distribute-h/v, compact)
      - group_edit: Batch move (dx/dy) or resize plants by variety/crop filter
      - place_band: Wide seed-row or block for broadcast-sown crops (radish, mesclun)
```

- [ ] **Step 4: Commit**

```bash
git add services/planner_service.rb
git commit -m "feat: register Phase A spatial tools and update prompt"
```

---

## Phase B: Advanced Layout

### Task 6: CopyLayoutTool

**Files:**
- Create: `services/planner_tools/copy_layout_tool.rb`
- Create: `test/services/test_planner_advanced_tools.rb`

- [ ] **Step 1: Write the test**

Create `test/services/test_planner_advanced_tools.rb`:

```ruby
require_relative "../test_helper"
require_relative "../../models/bed"
require_relative "../../models/plant"
require_relative "../../services/planner_tools/copy_layout_tool"

class TestCopyLayoutTool < GardenTest
  def setup
    super
    @bed1 = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    @bed2 = Bed.create(name: "BB2", bed_type: "raised", garden_id: @garden.id, width: 120, length: 240)
    Plant.create(garden_id: @garden.id, bed_id: @bed1.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    Plant.create(garden_id: @garden.id, bed_id: @bed1.id, variety_name: "Basil", crop_type: "herb", grid_x: 10, grid_y: 10, grid_w: 4, grid_h: 4)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_copy_layout
    tool = CopyLayoutTool.new
    tool.execute(source_bed: "BB1", target_bed: "BB2", mode: "copy")
    target_plants = Plant.where(bed_id: @bed2.id).all
    assert_equal 2, target_plants.length
    assert target_plants.any? { |p| p.variety_name == "Tomato" && p.grid_x == 0 }
    assert target_plants.any? { |p| p.variety_name == "Basil" && p.grid_x == 10 }
  end

  def test_mirror_horizontal
    tool = CopyLayoutTool.new
    tool.execute(source_bed: "BB1", target_bed: "BB2", mode: "mirror-h")
    target_plants = Plant.where(bed_id: @bed2.id).all
    tomato = target_plants.find { |p| p.variety_name == "Tomato" }
    # BB2 has 24 cols, tomato is 6 wide at x=0 → mirrored x = 24 - 0 - 6 = 18
    assert_equal 18, tomato.grid_x
  end

  def test_mirror_vertical
    tool = CopyLayoutTool.new
    tool.execute(source_bed: "BB1", target_bed: "BB2", mode: "mirror-v")
    target_plants = Plant.where(bed_id: @bed2.id).all
    tomato = target_plants.find { |p| p.variety_name == "Tomato" }
    # BB2 has 48 rows, tomato is 6 tall at y=0 → mirrored y = 48 - 0 - 6 = 42
    assert_equal 42, tomato.grid_y
  end

  def test_clear_target
    Plant.create(garden_id: @garden.id, bed_id: @bed2.id, variety_name: "Old", crop_type: "flower", grid_x: 0, grid_y: 0, grid_w: 4, grid_h: 4)
    tool = CopyLayoutTool.new
    tool.execute(source_bed: "BB1", target_bed: "BB2", mode: "copy", clear_target: "true")
    target_plants = Plant.where(bed_id: @bed2.id).all
    assert_equal 2, target_plants.length
    assert target_plants.none? { |p| p.variety_name == "Old" }
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_advanced_tools.rb`
Expected: FAIL — CopyLayoutTool not defined

- [ ] **Step 3: Write CopyLayoutTool**

Create `services/planner_tools/copy_layout_tool.rb`:

```ruby
require "ruby_llm"
require_relative "../../models/bed"
require_relative "../../models/plant"

class CopyLayoutTool < RubyLLM::Tool
  description "Copy or mirror a bed's plant layout to another bed. Modes: 'copy' (same positions), 'mirror-h' (flip left-right), 'mirror-v' (flip top-bottom). Optionally clear target bed first."

  param :source_bed, type: :string, desc: "Bed to copy from"
  param :target_bed, type: :string, desc: "Bed to copy to"
  param :mode, type: :string, desc: '"copy", "mirror-h", or "mirror-v"'
  param :clear_target, type: :string, desc: '"true" to clear target bed first (optional)'

  def execute(source_bed:, target_bed:, mode:, clear_target: nil)
    garden_id = Thread.current[:current_garden_id]
    src = Bed.where(name: source_bed, garden_id: garden_id).first
    return "Error: source bed '#{source_bed}' not found" unless src
    tgt = Bed.where(name: target_bed, garden_id: garden_id).first
    return "Error: target bed '#{target_bed}' not found" unless tgt

    src_plants = Plant.where(bed_id: src.id).exclude(lifecycle_stage: "done").all
    return "No plants on #{source_bed} to copy" if src_plants.empty?

    if clear_target == "true"
      Plant.where(bed_id: tgt.id).exclude(lifecycle_stage: "done").all.each(&:destroy)
    end

    created = 0
    src_plants.each do |p|
      case mode
      when "copy"
        new_x = p.grid_x
        new_y = p.grid_y
      when "mirror-h"
        new_x = tgt.grid_cols - p.grid_x - p.grid_w
        new_y = p.grid_y
      when "mirror-v"
        new_x = p.grid_x
        new_y = tgt.grid_rows - p.grid_y - p.grid_h
      else
        return "Error: mode must be 'copy', 'mirror-h', or 'mirror-v'"
      end

      next if new_x < 0 || new_y < 0 || new_x + p.grid_w > tgt.grid_cols || new_y + p.grid_h > tgt.grid_rows

      Plant.create(
        garden_id: garden_id, bed_id: tgt.id,
        variety_name: p.variety_name, crop_type: p.crop_type, source: p.source,
        lifecycle_stage: "seed_packet",
        grid_x: new_x, grid_y: new_y, grid_w: p.grid_w, grid_h: p.grid_h,
        quantity: p.quantity
      )
      created += 1
    end

    Thread.current[:planner_needs_refresh] = true
    "#{mode}: copied #{created} plants from #{source_bed} to #{target_bed}."
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_advanced_tools.rb`
Expected: 4 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/copy_layout_tool.rb test/services/test_planner_advanced_tools.rb
git commit -m "feat: CopyLayoutTool — copy/mirror layouts between beds"
```

---

### Task 7: GetEmptySpaceTool

**Files:**
- Create: `services/planner_tools/get_empty_space_tool.rb`
- Modify: `test/services/test_planner_advanced_tools.rb`

- [ ] **Step 1: Write the test**

Append to `test/services/test_planner_advanced_tools.rb`:

```ruby
require_relative "../../services/planner_tools/get_empty_space_tool"

class TestGetEmptySpaceTool < GardenTest
  def setup
    super
    @bed = Bed.create(name: "BB1", bed_type: "raised", garden_id: @garden.id, width: 60, length: 60)
    # 12x12 grid. Place a 6x6 tomato in top-left → 75% empty
    Plant.create(garden_id: @garden.id, bed_id: @bed.id, variety_name: "Tomato", crop_type: "tomato", grid_x: 0, grid_y: 0, grid_w: 6, grid_h: 6)
    Thread.current[:current_garden_id] = @garden.id
  end

  def test_reports_empty_space
    tool = GetEmptySpaceTool.new
    result = tool.execute(bed_name: "BB1")
    assert_includes result, "75%"
    assert_includes result, "108"  # 144 total - 36 occupied = 108 empty
  end

  def test_fully_empty_bed
    Plant.where(bed_id: @bed.id).all.each(&:destroy)
    tool = GetEmptySpaceTool.new
    result = tool.execute(bed_name: "BB1")
    assert_includes result, "100%"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/test_planner_advanced_tools.rb`
Expected: FAIL — GetEmptySpaceTool not defined

- [ ] **Step 3: Write GetEmptySpaceTool**

Create `services/planner_tools/get_empty_space_tool.rb`:

```ruby
require "ruby_llm"
require "set"
require_relative "../../models/bed"
require_relative "../../models/plant"

class GetEmptySpaceTool < RubyLLM::Tool
  description "Report empty space on a bed — total empty percentage and largest contiguous gaps with their positions. Use before placing to understand what fits where."

  param :bed_name, type: :string, desc: "Exact bed name"

  def execute(bed_name:)
    garden_id = Thread.current[:current_garden_id]
    bed = Bed.where(name: bed_name, garden_id: garden_id).first
    return "Error: bed '#{bed_name}' not found" unless bed

    cols = bed.grid_cols
    rows = bed.grid_rows
    total = cols * rows

    occupied = Set.new
    Plant.where(bed_id: bed.id).exclude(lifecycle_stage: "done").all.each do |p|
      (p.grid_x...(p.grid_x + p.grid_w)).each do |cx|
        (p.grid_y...(p.grid_y + p.grid_h)).each do |cy|
          occupied.add([cx, cy]) if cx < cols && cy < rows
        end
      end
    end

    empty_count = total - occupied.length
    pct = ((empty_count.to_f / total) * 100).round(0)

    # Find largest empty rectangles using greedy scan
    gaps = find_gaps(cols, rows, occupied)

    lines = ["#{bed_name}: #{pct}% empty (#{empty_count} of #{total} cells, grid #{cols}x#{rows})"]
    if gaps.any?
      lines << "Largest gaps:"
      gaps.first(5).each do |g|
        area = g[:w] * g[:h]
        lines << "  (#{g[:x]},#{g[:y]})→(#{g[:x] + g[:w]},#{g[:y] + g[:h]}): #{area} cells (#{g[:w]}x#{g[:h]})"
      end
    end

    lines.join("\n")
  end

  private

  def find_gaps(cols, rows, occupied)
    # Build boolean grid (true = free)
    free = Array.new(rows) { |r| Array.new(cols) { |c| !occupied.include?([c, r]) } }

    gaps = []
    visited = Set.new

    # Scan for rectangular gaps using greedy expansion
    rows.times do |y|
      cols.times do |x|
        next unless free[y][x] && !visited.include?([x, y])

        # Expand right
        max_w = 0
        while x + max_w < cols && free[y][x + max_w]
          max_w += 1
        end

        # Expand down maintaining width
        max_h = 0
        while y + max_h < rows
          row_ok = (x...(x + max_w)).all? { |cx| free[y + max_h][cx] }
          break unless row_ok
          max_h += 1
        end

        if max_w > 0 && max_h > 0
          gaps << { x: x, y: y, w: max_w, h: max_h }
          # Mark as visited
          (x...(x + max_w)).each do |cx|
            (y...(y + max_h)).each do |cy|
              visited.add([cx, cy])
            end
          end
        end
      end
    end

    gaps.sort_by { |g| -(g[:w] * g[:h]) }
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/test_planner_advanced_tools.rb`
Expected: 6 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add services/planner_tools/get_empty_space_tool.rb test/services/test_planner_advanced_tools.rb
git commit -m "feat: GetEmptySpaceTool — report empty space and gaps on beds"
```

---

### Task 8: Polygon-Aware Placement

**Files:**
- Modify: `models/bed.rb`
- Create: `test/models/test_bed_polygon.rb`
- Modify: `services/planner_tools/place_row_tool.rb`
- Modify: `services/planner_tools/place_column_tool.rb`
- Modify: `services/planner_tools/place_fill_tool.rb`
- Modify: `services/planner_tools/place_border_tool.rb`
- Modify: `services/planner_tools/place_in_zone_tool.rb`

- [ ] **Step 1: Write the test for point_in_polygon?**

Create `test/models/test_bed_polygon.rb`:

```ruby
require_relative "../test_helper"
require_relative "../../models/bed"

class TestBedPolygon < GardenTest
  def test_rectangular_bed_always_true
    bed = Bed.create(name: "R1", bed_type: "raised", garden_id: @garden.id, width: 100, length: 100)
    assert bed.point_in_polygon?(5, 5)
    assert bed.point_in_polygon?(0, 0)
  end

  def test_triangle_inside
    # Triangle: (0,0), (100,0), (50,100) — in canvas coords
    bed = Bed.create(name: "T1", bed_type: "raised", garden_id: @garden.id,
      canvas_points: [[0, 0], [100, 0], [50, 100]].to_json)
    # Center of triangle should be inside (grid coords: 50/5=10, 33/5≈6)
    assert bed.point_in_polygon?(10, 6)
  end

  def test_triangle_outside
    bed = Bed.create(name: "T2", bed_type: "raised", garden_id: @garden.id,
      canvas_points: [[0, 0], [100, 0], [50, 100]].to_json)
    # Top-right corner of bounding box is outside the triangle
    assert_equal false, bed.point_in_polygon?(19, 1)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/test_bed_polygon.rb`
Expected: FAIL — point_in_polygon? not defined

- [ ] **Step 3: Add point_in_polygon? to Bed model**

In `models/bed.rb`, add after the `polygon?` method (before the `end` of the Bed class):

```ruby
  # Ray-casting point-in-polygon test.
  # grid_x, grid_y are in 5cm grid cells. Converts to canvas coords using bounding box.
  def point_in_polygon?(grid_x, grid_y)
    return true unless polygon?
    pts = canvas_points_array
    return true if pts.length < 3

    # Convert grid coords to canvas coords
    xs = pts.map { |p| p[0] }
    ys = pts.map { |p| p[1] }
    min_x, max_x = xs.min, xs.max
    min_y, max_y = ys.min, ys.max
    poly_w = max_x - min_x
    poly_h = max_y - min_y
    return true if poly_w == 0 || poly_h == 0

    # Cell center in canvas coords
    cx = min_x + (grid_x * 5.0 + 2.5) * poly_w / (grid_cols * 5.0)
    cy = min_y + (grid_y * 5.0 + 2.5) * poly_h / (grid_rows * 5.0)

    # Ray-casting algorithm
    inside = false
    j = pts.length - 1
    pts.length.times do |i|
      xi, yi = pts[i]
      xj, yj = pts[j]
      if ((yi > cy) != (yj > cy)) && (cx < (xj - xi) * (cy - yi) / (yj - yi) + xi)
        inside = !inside
      end
      j = i
    end
    inside
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/models/test_bed_polygon.rb`
Expected: 3 tests, 0 failures

- [ ] **Step 5: Update placement tools with polygon checking**

In each of these 5 files, add a polygon check before creating a plant. The pattern is the same — add `next unless bed.point_in_polygon?(x, y)` before the `Plant.create` call.

**`services/planner_tools/place_row_tool.rb`** — inside the `n.times` loop, before `Plant.create`:

```ruby
      next unless bed.point_in_polygon?(x, y)
```

**`services/planner_tools/place_column_tool.rb`** — same pattern inside the `n.times` loop:

```ruby
      next unless bed.point_in_polygon?(x, y)
```

**`services/planner_tools/place_fill_tool.rb`** — inside the inner `while` loop, after the overlap check, before `Plant.create`:

```ruby
        unless overlap
          next unless bed.point_in_polygon?(x, y)
```

**`services/planner_tools/place_border_tool.rb`** — after building positions, before the `positions.each` create loop:

```ruby
    positions.select! { |x, y| bed.point_in_polygon?(x, y) }
```

**`services/planner_tools/place_in_zone_tool.rb`** — after building positions, before the `positions.each` create loop:

```ruby
    positions.select! { |x, y| bed.point_in_polygon?(x, y) }
```

- [ ] **Step 6: Commit**

```bash
git add models/bed.rb test/models/test_bed_polygon.rb services/planner_tools/place_row_tool.rb services/planner_tools/place_column_tool.rb services/planner_tools/place_fill_tool.rb services/planner_tools/place_border_tool.rb services/planner_tools/place_in_zone_tool.rb
git commit -m "feat: polygon-aware placement — point_in_polygon? on Bed, skip cells outside polygon"
```

---

### Task 9: Register Phase B Tools + Update Prompt

**Files:**
- Modify: `services/planner_service.rb`

- [ ] **Step 1: Add requires after Phase A requires**

```ruby
require_relative "planner_tools/copy_layout_tool"
require_relative "planner_tools/get_empty_space_tool"
```

- [ ] **Step 2: Add `.with_tool` registrations**

```ruby
        .with_tool(CopyLayoutTool)
        .with_tool(GetEmptySpaceTool)
```

- [ ] **Step 3: Update system prompt**

Add to the LAYOUT TOOLS section:

```
      - copy_layout: Copy or mirror (horizontal/vertical) a bed layout to another bed
      - get_empty_space: Report empty space percentage and largest gaps on a bed

      POLYGON BEDS: Placement tools automatically skip cells outside polygon
      bed shapes. You don't need to worry about this — just place normally
      and the system handles it.
```

- [ ] **Step 4: Commit**

```bash
git add services/planner_service.rb
git commit -m "feat: register Phase B tools (copy layout, empty space) and update prompt"
```

---

## Phase C: Decorative Composition Rules

### Task 10: Update System Prompt with Design Principles

**Files:**
- Modify: `services/planner_service.rb`

- [ ] **Step 1: Add design principles to system prompt**

After the LAYOUT TOOLS section and before the BED ZONES section, add:

```
      DESIGN PRINCIPLES for potager/ornamental layouts:
      - BACK TO FRONT: Tall crops (tomato, corn, sunflower) in rear rows (high y).
        Medium crops in middle. Low/trailing crops at front edge (low y).
      - SYMMETRY: For "beautiful" or "potager" requests, mirror key structural
        plants at equal spacing. Use place_border for symmetric edges.
      - FOCAL POINTS: Place one bold specimen (large squash, artichoke,
        sunflower) at center or front corners as visual anchor.
      - COLOR RHYTHM: Alternate leaf textures/colors. Interleave purple (basil,
        kale), silver, or flowering herbs between green crops.
      - EDGE DISCIPLINE: Use one variety consistently along an edge. Don't mix
        3 varieties in the front row.
      - REPETITION: Repeat the same variety at regular intervals for rhythm.
        Three identical plants in a diagonal reads as intentional design.
      - NEGATIVE SPACE: Use get_empty_space before placing. Don't fill every
        cell — some breathing room makes the design feel intentional.
```

- [ ] **Step 2: Commit**

```bash
git add services/planner_service.rb
git commit -m "feat: decorative composition rules in AI planner prompt"
```

---

## Phase D: Frontend Enhancements

### Task 11: Add Notes to BedPlant API

**Files:**
- Modify: `routes/beds.rb`
- Modify: `src/lib/api.ts`

- [ ] **Step 1: Add `notes` to plant JSON in beds route**

In `routes/beds.rb`, in the `get "/api/beds"` handler (around line 56-59), add `notes: p.notes` to the plant hash:

```ruby
        plants: active_plants.map { |p|
          { id: p.id, variety_name: p.variety_name, crop_type: p.crop_type,
            lifecycle_stage: p.lifecycle_stage,
            grid_x: p.grid_x, grid_y: p.grid_y, grid_w: p.grid_w, grid_h: p.grid_h,
            quantity: p.quantity, notes: p.notes }
        }
```

- [ ] **Step 2: Add `notes` to BedPlant TypeScript interface**

In `src/lib/api.ts`, add to the `BedPlant` interface (after `quantity: number`):

```typescript
  notes: string | null
```

- [ ] **Step 3: Commit**

```bash
git add routes/beds.rb src/lib/api.ts
git commit -m "feat: include plant notes in bed API response"
```

---

### Task 12: PlantRect Enhancements — Quantity Badge + Notes Indicator

**Files:**
- Modify: `src/components/bed/PlantRect.tsx`

- [ ] **Step 1: Add quantity badge and notes indicator**

In `src/components/bed/PlantRect.tsx`, add after the variety name `<text>` element (around line 237, before the closing `</g>`):

```tsx
      {plant.quantity > 1 && pw >= 10 && (
        <g>
          <circle
            cx={px + pw - 4}
            cy={py + 4}
            r={3.5}
            fill={color}
            fillOpacity={0.8}
          />
          <text
            x={px + pw - 4}
            y={py + 4}
            textAnchor="middle"
            dominantBaseline="central"
            fontSize={4}
            fontWeight={700}
            fill="white"
            style={{ pointerEvents: 'none', userSelect: 'none' }}
          >
            {plant.quantity > 99 ? '99+' : plant.quantity}
          </text>
        </g>
      )}
      {plant.notes && pw >= 10 && (
        <text
          x={px + pw - 3}
          y={py + ph - 3}
          textAnchor="middle"
          dominantBaseline="central"
          fontSize={5}
          style={{ pointerEvents: 'none', userSelect: 'none' }}
        >
          💬
        </text>
      )}
```

Note: The `plant.notes` check requires adding `notes` to the `PlantRectProps` — but `PlantRect` already receives the full `BedPlant` object which now has `notes` from Task 11.

- [ ] **Step 2: Commit**

```bash
git add src/components/bed/PlantRect.tsx
git commit -m "feat: quantity badge and notes indicator on plant rectangles"
```

---

### Task 13: BedCanvas Polygon Clipping

**Files:**
- Modify: `src/components/bed/BedCanvas.tsx`

- [ ] **Step 1: Add SVG clipPath for polygon beds**

In `src/components/bed/BedCanvas.tsx`, after building `outlineEl` for polygon beds (around line 181), add a clipPath definition:

```tsx
  // Build clip path for polygon beds
  let clipId: string | undefined
  let clipDef: React.ReactNode = null
  if (bed.canvas_points && bed.canvas_points.length > 2) {
    clipId = `bed-clip-${bed.id}`
    const xs = bed.canvas_points.map((p) => p[0])
    const ys = bed.canvas_points.map((p) => p[1])
    const minX = Math.min(...xs)
    const minY = Math.min(...ys)
    const polyW = Math.max(...xs) - minX
    const polyH = Math.max(...ys) - minY
    const scaleX = w / polyW
    const scaleY = h / polyH
    const clipPts = bed.canvas_points
      .map((p) => `${(p[0] - minX) * scaleX},${(p[1] - minY) * scaleY}`)
      .join(' ')
    clipDef = (
      <defs>
        <clipPath id={clipId}>
          <polygon points={clipPts} />
        </clipPath>
      </defs>
    )
  }
```

Then in the SVG return, wrap the grid lines and plants in a group with the clip path. In the SVG `<svg>` element, add `{clipDef}` after the opening tag, and wrap the grid + plants content in `<g clipPath={clipId ? \`url(#${clipId})\` : undefined}>`.

Find the section in the return where grid lines and PlantRect components are rendered. Wrap them:

```tsx
        {clipDef}
        {outlineEl}
        <g clipPath={clipId ? `url(#${clipId})` : undefined}>
          {gridLines}
          {/* ... ghost, drop target, plants ... */}
        </g>
```

Read the full return statement of BedCanvas to find the exact structure before making this edit.

- [ ] **Step 2: Commit**

```bash
git add src/components/bed/BedCanvas.tsx
git commit -m "feat: SVG polygon clipping for bed canvas — plants clipped to polygon shape"
```

---

### Task 14: Run Full Test Suite + Push

- [ ] **Step 1: Run all new tests**

```bash
ruby -Itest -e "Dir['test/services/test_planner_*.rb', 'test/models/test_bed_polygon.rb'].each { |f| require_relative f }"
```

Expected: All pass

- [ ] **Step 2: Run TypeScript check**

```bash
npx tsc --noEmit
```

Expected: No errors

- [ ] **Step 3: Push**

```bash
git push
```
