# Bed Layout SVG Rendering — Implementation Plan (Part 1)

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat slot grid in the Plan tab's Beds tab with SVG-rendered proportional bed shapes, tap interactions (plant popover, empty slot → AI), and an AI bed layout tool that suggests plant placements.

**Architecture:** SVG rendering in ERB (server-side), tap interactions via Alpine.js, new DraftBedLayoutTool for AI-assisted layouts, new endpoints for slot moves and layout application. No model changes.

**Tech Stack:** Ruby/Sinatra, ERB, inline SVG, Alpine.js (CDN), Sequel ORM

**Spec:** `docs/superpowers/specs/2026-03-17-bed-layout-editor-design.md`

**Part 2 (future):** Drag-and-drop plant reordering

---

## File Structure

```
Modified:
├── views/succession.erb              # Replace Beds tab HTML grid with SVG rendering
├── routes/succession.rb              # Add PATCH /beds/:id/swap-slots, POST /beds/:id/apply-layout
├── routes/plants.rb                  # Add PATCH /plants/:id for slot moves
├── services/planner_service.rb       # Register DraftBedLayoutTool, thread bed_layout data
├── test/routes/test_succession.rb    # Tests for new bed endpoints
├── test/routes/test_plants.rb        # Test for PATCH /plants/:id

New:
├── services/planner_tools/draft_bed_layout_tool.rb  # AI tool for bed layout suggestions
```

---

## Chunk 1: Backend — New Endpoints + AI Tool

### Task 1: Add PATCH /plants/:id for Slot Moves

**Files:**
- Modify: `routes/plants.rb` (add new route after line 79)
- Modify: `test/routes/test_plants.rb`

- [ ] **Step 1: Write test**

Add to `test/routes/test_plants.rb`:

```ruby
def test_move_plant_to_new_slot
  bed = Bed.create(garden_id: @garden.id, name: "TestBed")
  row = Row.create(bed_id: bed.id, position: 1, name: "R1")
  slot1 = Slot.create(row_id: row.id, position: 1, name: "S1")
  slot2 = Slot.create(row_id: row.id, position: 2, name: "S2")

  plant = Plant.create(
    garden_id: @garden.id,
    slot_id: slot1.id,
    variety_name: "Raf",
    crop_type: "tomato",
    lifecycle_stage: "seedling"
  )

  patch "/plants/#{plant.id}", { slot_id: slot2.id }.to_json, { "CONTENT_TYPE" => "application/json" }
  assert_equal 200, last_response.status

  plant.refresh
  assert_equal slot2.id, plant.slot_id
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_plants.rb -n test_move_plant_to_new_slot`
Expected: FAIL — route doesn't exist

- [ ] **Step 3: Implement endpoint**

Add to `routes/plants.rb`, after the `post "/plants/batch_advance"` block (around line 79):

```ruby
patch "/plants/:id" do
  content_type :json
  plant = Plant[params[:id].to_i]
  halt 404, json(error: "Plant not found") unless plant
  halt 403, json(error: "Not your plant") unless plant.garden_id == @current_garden.id

  request.body.rewind
  body = begin
    JSON.parse(request.body.read)
  rescue
    halt 400, json(error: "Invalid JSON")
  end

  if body["slot_id"]
    slot = Slot[body["slot_id"].to_i]
    halt 404, json(error: "Slot not found") unless slot
    halt 403, json(error: "Slot not in your garden") unless slot.row.bed.garden_id == @current_garden.id
    plant.update(slot_id: slot.id, updated_at: Time.now)
  end

  json plant.values
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_plants.rb -n test_move_plant_to_new_slot`
Expected: PASS

- [ ] **Step 5: Run all plant tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_plants.rb`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add routes/plants.rb test/routes/test_plants.rb
git commit -m "feat: add PATCH /plants/:id for slot moves"
```

---

### Task 2: Add Bed Swap and Apply-Layout Endpoints

**Files:**
- Modify: `routes/succession.rb` (add two new routes before the AI planner section, around line 280)
- Modify: `test/routes/test_succession.rb`

- [ ] **Step 1: Write tests**

Add to `test/routes/test_succession.rb`:

```ruby
def test_swap_slots
  bed = Bed.create(garden_id: @garden.id, name: "SwapBed")
  row = Row.create(bed_id: bed.id, position: 1, name: "R1")
  slot_a = Slot.create(row_id: row.id, position: 1, name: "A1")
  slot_b = Slot.create(row_id: row.id, position: 2, name: "B1")

  plant_a = Plant.create(garden_id: @garden.id, slot_id: slot_a.id, variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seedling")
  plant_b = Plant.create(garden_id: @garden.id, slot_id: slot_b.id, variety_name: "Basil", crop_type: "herb", lifecycle_stage: "seedling")

  patch "/beds/#{bed.id}/swap-slots", { slot_a: slot_a.id, slot_b: slot_b.id }.to_json, { "CONTENT_TYPE" => "application/json" }
  assert_equal 200, last_response.status

  plant_a.refresh
  plant_b.refresh
  assert_equal slot_b.id, plant_a.slot_id
  assert_equal slot_a.id, plant_b.slot_id
end

def test_apply_layout_fill
  bed = Bed.create(garden_id: @garden.id, name: "FillBed")
  row = Row.create(bed_id: bed.id, position: 1, name: "R1")
  slot = Slot.create(row_id: row.id, position: 1, name: "S1")

  post "/beds/#{bed.id}/apply-layout", {
    action: "fill",
    suggestions: [
      { slot_id: slot.id, variety_name: "Cherry Belle", crop_type: "radish" }
    ]
  }.to_json, { "CONTENT_TYPE" => "application/json" }

  assert_equal 200, last_response.status

  plant = Plant.where(slot_id: slot.id).first
  assert plant
  assert_equal "Cherry Belle", plant.variety_name
  assert_equal "radish", plant.crop_type
  assert_equal "seed_packet", plant.lifecycle_stage
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb -n test_swap_slots`
Expected: FAIL

- [ ] **Step 3: Implement swap-slots endpoint**

Add to `routes/succession.rb`, before the `# ── AI Planner Chat` section (around line 280):

```ruby
# ── Bed Layout Endpoints ────────────────────────────────────────────────

patch "/beds/:id/swap-slots" do
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

  slot_a = Slot[body["slot_a"].to_i]
  slot_b = Slot[body["slot_b"].to_i]
  halt 404, json(error: "Slot not found") unless slot_a && slot_b

  # Verify both slots belong to this bed
  bed_slot_ids = bed.rows.flat_map(&:slots).map(&:id)
  halt 422, json(error: "Slots don't belong to this bed") unless bed_slot_ids.include?(slot_a.id) && bed_slot_ids.include?(slot_b.id)

  # Find plants in each slot
  plant_a = slot_a.plants.find { |p| p.lifecycle_stage != "done" }
  plant_b = slot_b.plants.find { |p| p.lifecycle_stage != "done" }

  DB.transaction do
    # Use a temp null to avoid unique constraint issues
    plant_a&.update(slot_id: nil)
    plant_b&.update(slot_id: slot_a.id, updated_at: Time.now) if plant_b
    plant_a&.update(slot_id: slot_b.id, updated_at: Time.now) if plant_a
  end

  json(ok: true)
end
```

- [ ] **Step 4: Implement apply-layout endpoint**

Add right after swap-slots:

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
  bed_slot_ids = bed.rows.flat_map(&:slots).map(&:id)

  case action
  when "fill", "plan_full"
    suggestions = body["suggestions"] || []
    created = suggestions.map do |s|
      slot_id = s["slot_id"].to_i
      halt 422, json(error: "Slot #{slot_id} doesn't belong to this bed") unless bed_slot_ids.include?(slot_id)

      Plant.create(
        garden_id: @current_garden.id,
        slot_id: slot_id,
        variety_name: s["variety_name"],
        crop_type: s["crop_type"],
        lifecycle_stage: "seed_packet"
      )
    end
    json(ok: true, created: created.count)

  when "rearrange"
    moves = body["moves"] || []
    DB.transaction do
      moves.each do |m|
        plant = Plant[m["plant_id"].to_i]
        next unless plant && plant.garden_id == @current_garden.id
        to_slot = m["to_slot_id"].to_i
        halt 422, json(error: "Slot #{to_slot} doesn't belong to this bed") unless bed_slot_ids.include?(to_slot)
        plant.update(slot_id: to_slot, updated_at: Time.now)
      end
    end
    json(ok: true)

  else
    halt 400, json(error: "Unknown action: #{action}")
  end
end
```

- [ ] **Step 5: Run tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add routes/succession.rb test/routes/test_succession.rb
git commit -m "feat: add PATCH /beds/:id/swap-slots and POST /beds/:id/apply-layout"
```

---

### Task 3: Create DraftBedLayoutTool + Wire into PlannerService

**Files:**
- Create: `services/planner_tools/draft_bed_layout_tool.rb`
- Modify: `services/planner_service.rb` (register tool, thread bed_layout data)

- [ ] **Step 1: Create the tool**

Create `services/planner_tools/draft_bed_layout_tool.rb`:

```ruby
require "ruby_llm"

class DraftBedLayoutTool < RubyLLM::Tool
  description "Suggest a plant layout for a specific garden bed. Use when the user asks about what to plant in a bed, how to arrange plants, or wants a layout plan. Returns structured data that the user can preview and apply."

  param :payload, type: :string, desc: 'JSON string: { "bed_name": "BB1", "action": "fill|rearrange|plan_full", "suggestions": [{"slot_id": 42, "variety_name": "Raf", "crop_type": "tomato", "reason": "Companion to basil"}], "moves": [{"plant_id": 12, "from_slot_id": 42, "to_slot_id": 45, "reason": "Move basil next to tomatoes"}] }. Use "suggestions" for fill/plan_full, "moves" for rearrange.'

  def execute(payload:)
    parsed = JSON.parse(payload)
    Thread.current[:planner_bed_layout] = parsed

    action = parsed["action"]
    case action
    when "fill"
      count = parsed["suggestions"]&.length || 0
      "Bed layout draft stored: #{count} planting suggestions for #{parsed['bed_name']}. Present the suggestions to the user — they'll see a visual preview on the bed with an 'Apply layout' button."
    when "rearrange"
      count = parsed["moves"]&.length || 0
      "Bed layout draft stored: #{count} move suggestions for #{parsed['bed_name']}. Present the suggestions to the user — they'll see the proposed moves on the bed."
    when "plan_full"
      count = parsed["suggestions"]&.length || 0
      "Bed layout draft stored: full plan with #{count} plants for #{parsed['bed_name']}. Present the plan to the user — they'll see all suggested plants on the bed."
    else
      "Bed layout draft stored for #{parsed['bed_name']}."
    end
  rescue JSON::ParserError => e
    "Error: Invalid JSON. #{e.message}"
  end
end
```

- [ ] **Step 2: Register tool in PlannerService**

In `services/planner_service.rb`, find the tools block (around line 78-83). Add after the `.with_tool(DraftPlanTool)` line:

```ruby
.with_tool(DraftBedLayoutTool)
```

Also add the require at the top of the `chat` method (around line 71), alongside existing tool requires:

```ruby
require_relative "planner_tools/draft_bed_layout_tool"
```

- [ ] **Step 3: Thread bed_layout through send_message**

In `services/planner_service.rb`:

At line 107, after `Thread.current[:planner_draft] = nil`, add:
```ruby
Thread.current[:planner_bed_layout] = nil
```

At line 115, after `@last_draft = Thread.current[:planner_draft]`, add:
```ruby
@last_bed_layout = Thread.current[:planner_bed_layout]
```

At line 144, change the return hash from:
```ruby
{ content: content, draft: @last_draft, tool_calls: @tool_calls }
```
to:
```ruby
{ content: content, draft: @last_draft, bed_layout: @last_bed_layout, tool_calls: @tool_calls }
```

- [ ] **Step 4: Thread bed_layout through async polling**

In `routes/succession.rb`, find the async result storage (around line 354):

```ruby
PLANNER_RESULTS[request_id] = { status: "done", content: result[:content], draft: result[:draft] }
```

Change to:
```ruby
PLANNER_RESULTS[request_id] = { status: "done", content: result[:content], draft: result[:draft], bed_layout: result[:bed_layout] }
```

Also find the error handler (around line 359):
```ruby
PLANNER_RESULTS[request_id] = { status: "done", content: "Error: #{e.message}", draft: nil }
```
Change to:
```ruby
PLANNER_RESULTS[request_id] = { status: "done", content: "Error: #{e.message}", draft: nil, bed_layout: nil }
```

- [ ] **Step 5: Run all tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add services/planner_tools/draft_bed_layout_tool.rb services/planner_service.rb routes/succession.rb
git commit -m "feat: add DraftBedLayoutTool and wire bed_layout through planner pipeline"
```

---

## Chunk 2: Frontend — SVG Rendering + Interactions

### Task 4: Replace Beds Tab Grid with SVG Rendering

**Files:**
- Modify: `views/succession.erb` (lines 244-347, the Beds tab section)

**Important:** Use the `frontend-design` skill for this task.

This replaces the entire `<div x-show="tab === 'beds'">` section. The new version renders each bed as an inline SVG with proportional dimensions.

- [ ] **Step 1: Rewrite the Beds tab section**

Replace lines 244-347 of `views/succession.erb` with new SVG-based rendering. The structure:

```erb
<div x-show="tab === 'beds'" style="padding: 12px 16px;">
  <%
    beds = Bed.where(garden_id: @current_garden.id).eager(rows: {slots: :plants}).all
    arches = Arch.where(garden_id: @current_garden.id).all
    stations = IndoorStation.where(garden_id: @current_garden.id).all
  %>

  <% if beds.any? || arches.any? || stations.any? %>
    <!-- Occupancy summary pills (same as before) -->
    <div style="display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 12px;">
      <% beds.each do |bed| %>
        <% slots = bed.rows.flat_map(&:slots); filled = slots.count { |s| s.plants.any? { |p| p.lifecycle_stage != "done" } } %>
        <div style="padding: 4px 10px; background: var(--card-bg); border-radius: 8px; font-size: 11px; box-shadow: var(--card-shadow);">
          <span style="font-weight: 600; color: var(--green-900);"><%= bed.name %></span>
          <span style="color: var(--text-secondary);"><%= filled %>/<%= slots.count %></span>
        </div>
      <% end %>
    </div>
  <% end %>

  <% if beds.any? %>
    <div style="font-size: 10px; font-weight: 600; color: var(--green-900); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 8px;">Outdoor Beds</div>
    <% beds.each do |bed| %>
      <%
        rows = bed.rows.sort_by(&:position)
        all_slots = rows.flat_map(&:slots)
        total_slots = all_slots.count
        filled = all_slots.count { |s| s.plants.any? { |p| p.lifecycle_stage != "done" } }
        bed_w = (bed.width || 100).to_f
        bed_l = (bed.length || 100).to_f
        is_polygon = bed.polygon?
        canvas_color = bed.respond_to?(:canvas_color) && bed.canvas_color ? bed.canvas_color : '#e8e4df'
        # Lighten the canvas color for fill (add opacity)
        fill_color = canvas_color
      %>
      <div style="background: var(--card-bg); border-radius: var(--card-radius); padding: 12px; margin-bottom: 10px; box-shadow: var(--card-shadow);">
        <!-- Bed header -->
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
          <div>
            <div style="font-size: 14px; font-weight: 600; color: var(--green-900);"><%= bed.name %></div>
            <div style="font-size: 10px; color: var(--text-secondary);">
              <%= bed_w.round %>×<%= bed_l.round %>cm · <%= rows.count %> rows · <%= total_slots %> slots
            </div>
          </div>
          <div style="font-size: 12px; font-weight: 600; color: var(--green-900);"><%= filled %>/<%= total_slots %> <span style="font-weight: 400; color: var(--text-secondary);">filled</span></div>
        </div>

        <!-- SVG Bed -->
        <% if is_polygon %>
          <%
            points = bed.canvas_points_array
            xs = points.map { |p| p[0] }
            ys = points.map { |p| p[1] }
            min_x, max_x = xs.min, xs.max
            min_y, max_y = ys.min, ys.max
            vw = max_x - min_x
            vh = max_y - min_y
            svg_points = points.map { |p| "#{p[0] - min_x},#{p[1] - min_y}" }.join(" ")
          %>
          <svg viewBox="0 0 <%= vw %> <%= vh %>" style="width: 100%; max-height: 300px; min-height: 80px;" preserveAspectRatio="xMidYMid meet">
            <!-- Bed outline -->
            <polygon points="<%= svg_points %>" fill="<%= fill_color %>" fill-opacity="0.3" stroke="<%= fill_color %>" stroke-width="2" rx="4"/>

            <!-- Slots grid inside bounding box -->
            <% padding = 8; slot_rows = rows.count; max_cols = rows.map { |r| r.slots.count }.max %>
            <% cell_w = (vw - padding * 2).to_f / max_cols; cell_h = (vh - padding * 2).to_f / slot_rows %>
            <% rows.each_with_index do |row, ri| %>
              <% row.slots.sort_by(&:position).each_with_index do |slot, ci| %>
                <%
                  sx = padding + ci * cell_w + 2
                  sy = padding + ri * cell_h + 2
                  sw = cell_w - 4
                  sh = cell_h - 4
                  plant = slot.plants.find { |p| p.lifecycle_stage != "done" }
                  slot_fill = if plant
                    case plant.crop_type.to_s.downcase
                    when 'tomato', 'pepper', 'eggplant' then '#fecaca'
                    when 'lettuce', 'spinach', 'chard', 'kale' then '#bbf7d0'
                    when 'herb', 'basil' then '#a7f3d0'
                    when 'flower' then '#fef08a'
                    when 'cucumber', 'squash', 'melon', 'zucchini' then '#bae6fd'
                    else '#e5e7eb'
                    end
                  else
                    '#f9fafb'
                  end
                %>
                <% if plant %>
                  <a href="/plants/<%= plant.id %>" style="cursor: pointer;">
                    <rect x="<%= sx %>" y="<%= sy %>" width="<%= sw %>" height="<%= sh %>" rx="4" fill="<%= slot_fill %>" stroke="#d1d5db" stroke-width="1"/>
                    <text x="<%= sx + sw/2 %>" y="<%= sy + sh/2 - 4 %>" text-anchor="middle" font-size="<%= [sh * 0.22, 11].min %>" font-weight="500" fill="#1a2e05"><%= plant.variety_name.length > 10 ? plant.variety_name[0..8] + '…' : plant.variety_name %></text>
                    <text x="<%= sx + sw/2 %>" y="<%= sy + sh/2 + 8 %>" text-anchor="middle" font-size="<%= [sh * 0.16, 9].min %>" fill="#6b7280"><%= plant.lifecycle_stage.tr('_', ' ') %></text>
                  </a>
                <% else %>
                  <rect x="<%= sx %>" y="<%= sy %>" width="<%= sw %>" height="<%= sh %>" rx="4" fill="<%= slot_fill %>" stroke="#d1d5db" stroke-width="1" stroke-dasharray="4,2" @click="openAIForBed('<%= bed.name %>', <%= all_slots.count { |s| s.plants.none? { |p| p.lifecycle_stage != 'done' } } %>)" style="cursor: pointer;"/>
                <% end %>
              <% end %>
            <% end %>
          </svg>
        <% else %>
          <!-- Rectangular bed -->
          <svg viewBox="0 0 <%= bed_w %> <%= bed_l %>" style="width: 100%; max-height: 300px; min-height: 80px;" preserveAspectRatio="xMidYMid meet">
            <!-- Bed outline -->
            <rect x="0" y="0" width="<%= bed_w %>" height="<%= bed_l %>" rx="4" fill="<%= fill_color %>" fill-opacity="0.3" stroke="<%= fill_color %>" stroke-width="2"/>

            <!-- Slots grid -->
            <% padding = 6; slot_rows = rows.count; max_cols = rows.map { |r| r.slots.count }.max %>
            <% cell_w = (bed_w - padding * 2).to_f / max_cols; cell_h = (bed_l - padding * 2).to_f / slot_rows %>
            <% rows.each_with_index do |row, ri| %>
              <% cols_in_row = row.slots.count %>
              <% row_cell_w = (bed_w - padding * 2).to_f / cols_in_row %>
              <% row.slots.sort_by(&:position).each_with_index do |slot, ci| %>
                <%
                  sx = padding + ci * row_cell_w + 2
                  sy = padding + ri * cell_h + 2
                  sw = row_cell_w - 4
                  sh = cell_h - 4
                  plant = slot.plants.find { |p| p.lifecycle_stage != "done" }
                  slot_fill = if plant
                    case plant.crop_type.to_s.downcase
                    when 'tomato', 'pepper', 'eggplant' then '#fecaca'
                    when 'lettuce', 'spinach', 'chard', 'kale' then '#bbf7d0'
                    when 'herb', 'basil' then '#a7f3d0'
                    when 'flower' then '#fef08a'
                    when 'cucumber', 'squash', 'melon', 'zucchini' then '#bae6fd'
                    else '#e5e7eb'
                    end
                  else
                    '#f9fafb'
                  end
                %>
                <% if plant %>
                  <a href="/plants/<%= plant.id %>" style="cursor: pointer;">
                    <rect x="<%= sx %>" y="<%= sy %>" width="<%= sw %>" height="<%= sh %>" rx="4" fill="<%= slot_fill %>" stroke="#d1d5db" stroke-width="1"/>
                    <text x="<%= sx + sw/2 %>" y="<%= sy + sh/2 - 4 %>" text-anchor="middle" font-size="<%= [sh * 0.22, 11].min %>" font-weight="500" fill="#1a2e05"><%= plant.variety_name.length > 10 ? plant.variety_name[0..8] + '…' : plant.variety_name %></text>
                    <text x="<%= sx + sw/2 %>" y="<%= sy + sh/2 + 8 %>" text-anchor="middle" font-size="<%= [sh * 0.16, 9].min %>" fill="#6b7280"><%= plant.lifecycle_stage.tr('_', ' ') %></text>
                  </a>
                <% else %>
                  <rect x="<%= sx %>" y="<%= sy %>" width="<%= sw %>" height="<%= sh %>" rx="4" fill="<%= slot_fill %>" stroke="#d1d5db" stroke-width="1" stroke-dasharray="4,2" @click="openAIForBed('<%= bed.name %>', <%= all_slots.count { |s| s.plants.none? { |p| p.lifecycle_stage != 'done' } } %>)" style="cursor: pointer;"/>
                <% end %>
              <% end %>
            <% end %>
          </svg>
        <% end %>
      </div>
    <% end %>
  <% end %>

  <!-- Arches section (unchanged from current) -->
  <% if arches.any? %>
    <div style="font-size: 10px; font-weight: 600; color: #8b5cf6; text-transform: uppercase; letter-spacing: 0.5px; margin: 16px 0 8px;">Arches</div>
    <% arches.each do |arch| %>
      <div style="background: var(--card-bg); border-radius: var(--card-radius); padding: 12px; margin-bottom: 8px; box-shadow: var(--card-shadow); border-left: 3px solid #8b5cf6;">
        <div style="font-size: 13px; font-weight: 600; color: var(--green-900);"><%= arch.name %></div>
        <div style="font-size: 10px; color: var(--text-secondary);"><%= arch.respond_to?(:between_beds) ? arch.between_beds : '' %></div>
      </div>
    <% end %>
  <% end %>

  <!-- Indoor stations section (unchanged from current) -->
  <% if stations.any? %>
    <div style="font-size: 10px; font-weight: 600; color: #f59e0b; text-transform: uppercase; letter-spacing: 0.5px; margin: 16px 0 8px;">Indoor Stations</div>
    <% stations.each do |station| %>
      <div style="background: var(--card-bg); border-radius: var(--card-radius); padding: 12px; margin-bottom: 8px; box-shadow: var(--card-shadow); border-left: 3px solid #f59e0b;">
        <div style="font-size: 13px; font-weight: 600; color: var(--green-900);"><%= station.name %></div>
        <div style="font-size: 10px; color: var(--text-secondary);"><%= station.respond_to?(:station_type) ? station.station_type : 'Indoor' %></div>
        <% indoor_plants = Plant.where(indoor_station_id: station.id).exclude(lifecycle_stage: "done").all %>
        <% if indoor_plants.any? %>
          <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 2px; margin-top: 6px;">
            <% indoor_plants.each do |plant| %>
              <a href="/plants/<%= plant.id %>" style="background: #fef2f2; border-radius: 3px; padding: 3px; text-align: center; font-size: 8px; color: var(--text-secondary); text-decoration: none;">
                <%= plant.variety_name.split.first[0..2] %>
              </a>
            <% end %>
          </div>
        <% end %>
      </div>
    <% end %>
  <% end %>

  <% if beds.empty? && arches.empty? && stations.empty? %>
    <div style="text-align: center; padding: 40px 20px; color: var(--text-secondary); font-size: 14px;">
      No beds set up yet.
    </div>
  <% end %>
</div>
```

Key differences from previous version:
- Beds rendered as SVG with `viewBox` from `width × length`
- Polygon beds use `<polygon>` from `canvas_points_array`
- **Variable row widths**: each row computes its own `row_cell_w` based on `row.slots.count` — naturally handles L-shaped beds (row 1 has 3 slots = wider cells, row 2 has 2 = wider cells)
- Slot colors use saturated variants for better SVG contrast (`#fecaca` instead of `#fef2f2`)
- Plant names and stages rendered as `<text>` with dynamic font sizing
- Empty slots have dashed stroke and click handler for AI drawer
- Eager loading added: `Bed.where(...).eager(rows: {slots: :plants})`

- [ ] **Step 2: Verify page loads**

Run the app and navigate to `/succession`, click the Beds tab. Verify:
- Rectangular beds render with correct proportions (BB1 at 175×100 looks wider)
- Polygon bed (CB) renders with its custom shape
- Plant names visible inside slots
- Empty slots have dashed borders
- Tapping an empty slot opens the AI drawer

- [ ] **Step 3: Run all tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest test/routes/test_succession.rb`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add views/succession.erb
git commit -m "feat: SVG bed rendering with proportional shapes and slot grids"
```

---

### Task 5: Add AI Layout Preview to Drawer

**Files:**
- Modify: `views/succession.erb` (planTab() Alpine.js component + AI drawer section)

Extend the AI drawer to handle `bed_layout` responses and show preview overlays.

- [ ] **Step 1: Extend planTab() to handle bed_layout**

In `views/succession.erb`, find the `planTab()` function in the `<script>` block.

**Add new state property** alongside the existing `aiSending: false,` line:

```javascript
pendingLayout: null,
```

**Modify `pollForAIResponse`** — find this exact line inside the `data.status === 'done'` branch:

```javascript
this.aiMessages.push({ role: 'assistant', content: data.content, id: Date.now(), draft: data.draft });
```

Replace it with:

```javascript
this.aiMessages.push({ role: 'assistant', content: data.content, id: Date.now(), draft: data.draft });
if (data.bed_layout) this.pendingLayout = data.bed_layout;
```

Also add methods:

```javascript
async applyLayout() {
  if (!this.pendingLayout) return;
  const layout = this.pendingLayout;
  const bed = document.querySelector(`[data-bed-name="${layout.bed_name}"]`);
  // Find bed ID from the SVG element
  const bedId = bed?.dataset?.bedId;
  if (!bedId) return;

  await fetch(`/beds/${bedId}/apply-layout`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(layout)
  });
  this.pendingLayout = null;
  location.reload();
},

dismissLayout() {
  this.pendingLayout = null;
}
```

- [ ] **Step 2: Add layout preview UI in AI drawer**

After the messages area and before the input area in the drawer, add:

```erb
<!-- Layout preview -->
<template x-if="pendingLayout">
  <div style="margin: 8px 12px; padding: 10px; background: var(--green-50); border: 1px solid #dcfce7; border-radius: 8px;">
    <div style="font-size: 11px; font-weight: 600; color: var(--green-900); margin-bottom: 6px;" x-text="'Layout suggestion for ' + pendingLayout.bed_name"></div>
    <div style="font-size: 11px; color: var(--text-secondary); margin-bottom: 4px;">
      <template x-if="pendingLayout.action === 'fill' || pendingLayout.action === 'plan_full'">
        <span x-text="(pendingLayout.suggestions?.length || 0) + ' plants to add'"></span>
      </template>
      <template x-if="pendingLayout.action === 'rearrange'">
        <span x-text="(pendingLayout.moves?.length || 0) + ' moves suggested'"></span>
      </template>
    </div>
    <!-- Show suggestions list -->
    <template x-if="pendingLayout.suggestions">
      <div style="margin-bottom: 8px;">
        <template x-for="s in pendingLayout.suggestions" :key="s.slot_id">
          <div style="font-size: 10px; color: var(--text-body); padding: 2px 0;">
            <span x-text="s.variety_name"></span> <span style="color: var(--text-secondary);" x-text="'— ' + (s.reason || s.crop_type)"></span>
          </div>
        </template>
      </div>
    </template>
    <template x-if="pendingLayout.moves">
      <div style="margin-bottom: 8px;">
        <template x-for="m in pendingLayout.moves" :key="m.plant_id">
          <div style="font-size: 10px; color: var(--text-body); padding: 2px 0;" x-text="m.reason || 'Move plant'"></div>
        </template>
      </div>
    </template>
    <div style="display: flex; gap: 8px;">
      <button @click="applyLayout()" style="padding: 6px 16px; background: var(--green-900); color: white; border: none; border-radius: 8px; font-size: 12px; cursor: pointer;">Apply layout</button>
      <button @click="dismissLayout()" style="padding: 6px 16px; background: #f3f4f6; color: var(--text-secondary); border: none; border-radius: 8px; font-size: 12px; cursor: pointer;">Dismiss</button>
    </div>
  </div>
</template>
```

- [ ] **Step 3: Add data-bed-name and data-bed-id attributes to SVG bed cards**

In the bed card wrapper div, add data attributes:

Change:
```erb
<div style="background: var(--card-bg); ...">
```
To:
```erb
<div data-bed-name="<%= bed.name %>" data-bed-id="<%= bed.id %>" style="background: var(--card-bg); ...">
```

- [ ] **Step 4: Run all tests**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add views/succession.erb
git commit -m "feat: AI layout preview in drawer with apply/dismiss actions"
```

---

## Summary

| Task | What changes | Files |
|------|-------------|-------|
| 1 | PATCH /plants/:id for slot moves | routes/plants.rb, test |
| 2 | Swap-slots + apply-layout endpoints | routes/succession.rb, test |
| 3 | DraftBedLayoutTool + planner wiring | new tool, planner_service.rb, routes/succession.rb |
| 4 | SVG bed rendering (the big one) | views/succession.erb |
| 5 | AI layout preview in drawer | views/succession.erb |

Total: **5 tasks**, 2 chunks. Chunk 1 = backend (Tasks 1-3), Chunk 2 = frontend (Tasks 4-5). No model changes. All existing tests must pass.

---

## Deferred to Part 2

- **Drag-and-drop** plant reordering (long-press, ghost element, swap on drop)
- **Plant popover** on tap (Part 1 links directly to `/plants/:id` — simpler, still functional)
- **SVG overlay previews** for AI suggestions (Part 1 shows a text list in the drawer instead — same data, less visual)
- **System prompt update** for DraftBedLayoutTool (tool description is sufficient for now; can tune later)
