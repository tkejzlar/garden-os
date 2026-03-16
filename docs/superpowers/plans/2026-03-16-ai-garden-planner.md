# AI Garden Planner Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a conversational AI planning assistant in the Plan tab that helps design the garden season — from crop goals to bed assignments, succession schedules, and sowing tasks.

**Architecture:** Chat UI (Alpine.js) in the Plan tab sends messages to PlannerService (ruby_llm with tool calling). The AI queries garden data via registered tools and produces structured draft plans. Users review and iterate in conversation, then commit the plan to the database in one transaction.

**Tech Stack:** ruby_llm (tool calling), Alpine.js (chat UI), Sequel (persistence), existing Sinatra routes

**Spec:** `docs/superpowers/specs/2026-03-16-ai-garden-planner.md`

---

## File Structure

```
New/Modified:
├── db/migrations/012_create_planner_messages.rb  # NEW
├── models/planner_message.rb                      # NEW
├── services/planner_service.rb                    # NEW — orchestrates LLM conversation
├── services/planner_tools/                        # NEW — one file per tool
│   ├── get_beds_tool.rb
│   ├── get_seed_inventory_tool.rb
│   ├── get_plants_tool.rb
│   ├── get_succession_plans_tool.rb
│   ├── get_weather_tool.rb
│   └── draft_plan_tool.rb
├── services/plan_committer.rb                     # NEW — commits draft to DB
├── routes/succession.rb                           # MODIFY — add planner routes
├── views/succession.erb                           # MODIFY — add chat UI above Gantt
├── app.rb                                         # MODIFY — require new route files if needed
├── test/services/test_planner_service.rb          # NEW
├── test/services/test_plan_committer.rb           # NEW
├── test/routes/test_planner_routes.rb             # NEW
```

---

### Task 1: Migration + PlannerMessage Model

**Files:**
- Create: `db/migrations/012_create_planner_messages.rb`
- Create: `models/planner_message.rb`

- [ ] **Step 1: Create migration**

```ruby
# db/migrations/012_create_planner_messages.rb
Sequel.migration do
  change do
    create_table(:planner_messages) do
      primary_key :id
      String :role, null: false         # "user", "assistant", "system"
      String :content, text: true, null: false
      String :draft_payload, text: true  # JSON, nullable
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
```

- [ ] **Step 2: Create model**

```ruby
# models/planner_message.rb
require_relative "../config/database"

class PlannerMessage < Sequel::Model
  def draft?
    !draft_payload.nil? && !draft_payload.empty?
  end

  def draft_data
    draft? ? JSON.parse(draft_payload) : nil
  end
end
```

- [ ] **Step 3: Run migrations**

Run: `rake db:migrate`

- [ ] **Step 4: Commit**

```bash
git add db/migrations/012_create_planner_messages.rb models/planner_message.rb
git commit -m "feat: planner_messages table and model"
```

---

### Task 2: Planner Tools — Data Query Tools

**Files:**
- Create: `services/planner_tools/get_beds_tool.rb`
- Create: `services/planner_tools/get_seed_inventory_tool.rb`
- Create: `services/planner_tools/get_plants_tool.rb`
- Create: `services/planner_tools/get_succession_plans_tool.rb`
- Create: `services/planner_tools/get_weather_tool.rb`

Each tool is a ruby_llm `RubyLLM::Tool` subclass. They query the DB and return JSON.

- [ ] **Step 1: Create GetBedsTool**

```ruby
# services/planner_tools/get_beds_tool.rb
require_relative "../../models/bed"
require_relative "../../models/plant"

class GetBedsTool < RubyLLM::Tool
  description "Get all garden beds with dimensions, rows, slots, and which plants are currently assigned to each slot"

  def execute
    beds = Bed.all.map do |bed|
      rows = Row.where(bed_id: bed.id).order(:position).all.map do |row|
        slots = Slot.where(row_id: row.id).order(:position).all.map do |slot|
          plant = Plant.where(slot_id: slot.id).exclude(lifecycle_stage: "done").first
          {
            position: slot.position,
            name: slot.name,
            plant: plant ? { variety_name: plant.variety_name, crop_type: plant.crop_type, stage: plant.lifecycle_stage } : nil
          }
        end
        { name: row.name, slots: slots }
      end

      {
        name: bed.name,
        bed_type: bed.bed_type,
        length: bed.length,
        width: bed.width,
        orientation: bed.orientation,
        rows: rows,
        total_slots: rows.sum { |r| r[:slots].length },
        occupied_slots: rows.sum { |r| r[:slots].count { |s| s[:plant] } }
      }
    end

    # Also include arches and indoor stations
    arches = Arch.all.map { |a| { name: a.name, between_beds: a.between_beds, spring_crop: a.spring_crop, summer_crop: a.summer_crop } }
    indoor = IndoorStation.all.map { |s| { name: s.name, type: s.station_type, target_temp: s.target_temp } }

    JSON.generate({ beds: beds, arches: arches, indoor_stations: indoor })
  end
end
```

- [ ] **Step 2: Create GetSeedInventoryTool**

```ruby
# services/planner_tools/get_seed_inventory_tool.rb
require_relative "../../models/seed_packet"

class GetSeedInventoryTool < RubyLLM::Tool
  description "Get all seed packets the user has — variety names, crop types, sources, and growing notes"

  def execute
    packets = SeedPacket.order(:crop_type, :variety_name).all.map do |p|
      { variety_name: p.variety_name, crop_type: p.crop_type, source: p.source, notes: p.notes }
    end
    JSON.generate({ seed_packets: packets, total: packets.length })
  end
end
```

- [ ] **Step 3: Create GetPlantsTool**

```ruby
# services/planner_tools/get_plants_tool.rb
require_relative "../../models/plant"

class GetPlantsTool < RubyLLM::Tool
  description "Get all active plants currently being grown — variety, stage, location, days in stage"

  def execute
    plants = Plant.exclude(lifecycle_stage: "done").all.map do |p|
      slot = p.slot
      row = slot&.row
      bed = row&.bed
      {
        variety_name: p.variety_name,
        crop_type: p.crop_type,
        stage: p.lifecycle_stage,
        days_in_stage: p.days_in_stage,
        bed: bed&.name,
        row: row&.name,
        sow_date: p.sow_date&.to_s
      }
    end
    JSON.generate({ plants: plants, total: plants.length })
  end
end
```

- [ ] **Step 4: Create GetSuccessionPlansTool**

```ruby
# services/planner_tools/get_succession_plans_tool.rb
require_relative "../../models/succession_plan"
require_relative "../../models/task"

class GetSuccessionPlansTool < RubyLLM::Tool
  description "Get existing succession planting schedules with their completion status"

  def execute
    plans = SuccessionPlan.all.map do |sp|
      completed = Task.where(task_type: "sow")
                      .where(Sequel.like(:title, "%#{sp.crop}%"))
                      .where(status: "done").count
      {
        crop: sp.crop,
        varieties: sp.varieties_list,
        interval_days: sp.interval_days,
        season_start: sp.season_start&.to_s,
        season_end: sp.season_end&.to_s,
        total_planned: sp.total_planned_sowings,
        completed: completed,
        target_beds: sp.target_beds_list
      }
    end
    JSON.generate({ succession_plans: plans })
  end
end
```

- [ ] **Step 5: Create GetWeatherTool**

```ruby
# services/planner_tools/get_weather_tool.rb
require_relative "../weather_service"

class GetWeatherTool < RubyLLM::Tool
  description "Get current weather conditions and 3-day forecast for the garden location"

  def execute
    weather = WeatherService.fetch_current
    if weather
      JSON.generate(weather)
    else
      JSON.generate({ error: "Weather data unavailable" })
    end
  end
end
```

- [ ] **Step 6: Commit**

```bash
git add services/planner_tools/
git commit -m "feat: planner AI tools — get_beds, get_seeds, get_plants, get_successions, get_weather"
```

---

### Task 3: DraftPlanTool

**Files:**
- Create: `services/planner_tools/draft_plan_tool.rb`

- [ ] **Step 1: Create DraftPlanTool**

```ruby
# services/planner_tools/draft_plan_tool.rb
class DraftPlanTool < RubyLLM::Tool
  description "Create a draft garden plan with bed assignments, succession schedules, and tasks. The user will see a visual preview and can request changes before committing. Call this when you have a complete plan ready to present."

  param :payload, type: :string, desc: "JSON string containing: summary (string), assignments (array of {bed_name, row_name, slot_position, variety_name, crop_type, source}), successions (array of {crop, varieties, interval_days, season_start, season_end, total_sowings, target_beds}), tasks (array of {title, task_type, due_date, priority, notes, related_beds})"

  def execute(payload:)
    parsed = JSON.parse(payload)
    Thread.current[:planner_draft] = parsed
    "Draft plan stored with #{parsed['assignments']&.length || 0} bed assignments, #{parsed['successions']&.length || 0} succession schedules, and #{parsed['tasks']&.length || 0} tasks. Present the summary to the user. They will see a visual preview and can click 'Create this plan' to commit it, or ask for changes."
  rescue JSON::ParserError => e
    "Error: Invalid JSON in payload. Please fix and try again: #{e.message}"
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add services/planner_tools/draft_plan_tool.rb
git commit -m "feat: DraftPlanTool — stores structured plan via Thread.current"
```

---

### Task 4: PlannerService

**Files:**
- Create: `services/planner_service.rb`
- Create: `test/services/test_planner_service.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/services/test_planner_service.rb
require_relative "../test_helper"
require_relative "../../services/planner_service"

class TestPlannerService < GardenTest
  def test_system_prompt_includes_prague
    service = PlannerService.new
    assert_includes service.system_prompt, "Prague"
  end

  def test_saves_user_message
    PlannerService.new  # ensure message table exists
    PlannerMessage.create(role: "user", content: "test", created_at: Time.now)
    assert_equal 1, PlannerMessage.where(role: "user").count
  end

  def test_clear_messages
    PlannerMessage.create(role: "user", content: "test", created_at: Time.now)
    PlannerMessage.create(role: "assistant", content: "reply", created_at: Time.now)
    PlannerMessage.delete
    assert_equal 0, PlannerMessage.count
  end
end
```

- [ ] **Step 2: Create PlannerService**

```ruby
# services/planner_service.rb
require "json"
require_relative "../config/ruby_llm"
require_relative "../models/planner_message"
require_relative "planner_tools/get_beds_tool"
require_relative "planner_tools/get_seed_inventory_tool"
require_relative "planner_tools/get_plants_tool"
require_relative "planner_tools/get_succession_plans_tool"
require_relative "planner_tools/get_weather_tool"
require_relative "planner_tools/draft_plan_tool"

class PlannerService
  attr_reader :last_draft

  def self.model_id  = ENV.fetch("GARDEN_AI_MODEL", "gpt-4o")
  def self.provider
    m = model_id
    if m.start_with?("claude") then :anthropic
    elsif m.start_with?("gemini") then :gemini
    else :openai
    end
  end

  def initialize
    @last_draft = nil
    @chat = RubyLLM.chat(model: self.class.model_id, provider: self.class.provider, assume_model_exists: true)
      .with_instructions(system_prompt)
      .with_tool(GetBedsTool)
      .with_tool(GetSeedInventoryTool)
      .with_tool(GetPlantsTool)
      .with_tool(GetSuccessionPlansTool)
      .with_tool(GetWeatherTool)
      .with_tool(DraftPlanTool)

    # Replay conversation history so the AI has context
    PlannerMessage.order(:created_at).all.each do |msg|
      @chat.messages << { role: msg.role, content: msg.content }
    end
  end

  def system_prompt
    <<~PROMPT
      You are a garden planning consultant for a productive vegetable garden in Prague,
      Czech Republic (zone 6b/7a, last frost ~May 13, first frost ~Oct 15, continental climate).

      ALWAYS use the available tools to look up the garden's actual data before making
      recommendations. Don't assume — check the beds, seeds, and existing plants.

      CRITICAL: When referencing beds, rows, or slots in your draft_plan, use ONLY the
      exact names and positions returned by get_beds. Never invent bed or row names.

      When the user describes what they want to grow, help them create a complete plan:
      1. First, check what beds are available and their dimensions
      2. Check what seeds they already have
      3. Propose bed assignments considering: sun exposure, spacing, companion planting,
         crop rotation, and the user's preferences
      4. Set up succession schedules for crops that benefit from them
      5. Create a task timeline with sowing dates (indoor + outdoor), transplant dates,
         and other key milestones

      When you have a complete plan, call the draft_plan tool with ALL the structured data.
      The user will see a visual preview and can request changes before committing.

      Be conversational, practical, and opinionated. If the user asks for something that
      doesn't make horticultural sense, say so and suggest alternatives.

      Prague climate notes:
      - Indoor sowing: Feb-April (peppers early Feb, tomatoes early March)
      - Last frost: ~May 13 (Ice Saints)
      - Transplant tender crops: after May 15
      - Growing season: May-October
      - First frost: ~Oct 15
    PROMPT
  end

  def send_message(user_text)
    PlannerMessage.create(role: "user", content: user_text, created_at: Time.now)

    Thread.current[:planner_draft] = nil

    response = @chat.ask(user_text)

    @last_draft = Thread.current[:planner_draft]

    PlannerMessage.create(
      role: "assistant",
      content: response.content,
      draft_payload: @last_draft ? JSON.generate(@last_draft) : nil,
      created_at: Time.now
    )

    { content: response.content, draft: @last_draft }
  rescue => e
    warn "PlannerService error: #{e.message}"
    PlannerMessage.create(role: "assistant", content: "Sorry, I encountered an error. Please try again.", created_at: Time.now)
    { content: "Sorry, I encountered an error: #{e.message}", draft: nil }
  end
end
```

- [ ] **Step 3: Run tests**

Run: `rm -f db/garden_os_test.db && ruby test/services/test_planner_service.rb`
Expected: 3 tests, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add services/planner_service.rb test/services/test_planner_service.rb
git commit -m "feat: PlannerService — LLM conversation with tool calling and history replay"
```

---

### Task 5: PlanCommitter — Draft to Database

**Files:**
- Create: `services/plan_committer.rb`
- Create: `test/services/test_plan_committer.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/services/test_plan_committer.rb
require_relative "../test_helper"
require_relative "../../services/plan_committer"

class TestPlanCommitter < GardenTest
  def setup
    super
    # Create a bed with rows and slots for testing
    @bed = Bed.create(name: "BB1", bed_type: "raised")
    row = Row.create(bed_id: @bed.id, name: "A", position: 1)
    Slot.create(row_id: row.id, name: "Pos 1", position: 1)
    Slot.create(row_id: row.id, name: "Pos 2", position: 2)
  end

  def test_commit_assignments
    draft = {
      "assignments" => [
        { "bed_name" => "BB1", "row_name" => "A", "slot_position" => 1,
          "variety_name" => "Raf", "crop_type" => "tomato", "source" => "Reinsaat" }
      ],
      "successions" => [],
      "tasks" => []
    }
    result = PlanCommitter.commit!(draft)
    assert result[:success]
    assert_equal 1, result[:created][:plants]
    assert_equal "Raf", Plant.first.variety_name
    assert_equal @bed.id, Plant.first.slot.row.bed.id
  end

  def test_commit_successions
    draft = {
      "assignments" => [],
      "successions" => [
        { "crop" => "Lettuce", "varieties" => ["Tre Colori"], "interval_days" => 18,
          "season_start" => "2026-04-01", "season_end" => "2026-09-30",
          "total_sowings" => 4, "target_beds" => ["BB1"] }
      ],
      "tasks" => []
    }
    result = PlanCommitter.commit!(draft)
    assert result[:success]
    assert_equal 1, result[:created][:succession_plans]
    assert_equal "Lettuce", SuccessionPlan.first.crop
  end

  def test_commit_tasks
    draft = {
      "assignments" => [],
      "successions" => [],
      "tasks" => [
        { "title" => "Sow peppers", "task_type" => "sow",
          "due_date" => "2026-03-01", "priority" => "must",
          "related_beds" => ["BB1"] }
      ]
    }
    result = PlanCommitter.commit!(draft)
    assert result[:success]
    assert_equal 1, result[:created][:tasks]
    assert_equal "Sow peppers", Task.first.title
  end

  def test_validates_bed_names
    draft = {
      "assignments" => [
        { "bed_name" => "NONEXISTENT", "variety_name" => "Raf", "crop_type" => "tomato" }
      ],
      "successions" => [],
      "tasks" => []
    }
    result = PlanCommitter.commit!(draft)
    refute result[:success]
    assert_includes result[:errors].first, "NONEXISTENT"
  end

  def test_empty_draft
    result = PlanCommitter.commit!({ "assignments" => [], "successions" => [], "tasks" => [] })
    assert result[:success]
    assert_equal 0, Plant.count
  end
end
```

- [ ] **Step 2: Create PlanCommitter**

```ruby
# services/plan_committer.rb
require "json"
require_relative "../models/bed"
require_relative "../models/plant"
require_relative "../models/task"
require_relative "../models/succession_plan"
require_relative "task_generator"

class PlanCommitter
  def self.commit!(draft)
    assignments = draft["assignments"] || []
    successions = draft["successions"] || []
    tasks       = draft["tasks"] || []

    # Validate bed references
    errors = validate_beds(assignments, tasks)
    return { success: false, errors: errors } if errors.any?

    counts = { plants: 0, succession_plans: 0, tasks: 0 }

    DB.transaction do
      # Create plants from assignments
      assignments.each do |a|
        bed = Bed.where(name: a["bed_name"]).first
        row = bed ? Row.where(bed_id: bed.id, name: a["row_name"]).first : nil
        slot = row ? Slot.where(row_id: row.id, position: a["slot_position"]).first : nil

        Plant.create(
          variety_name: a["variety_name"],
          crop_type: a["crop_type"],
          source: a["source"],
          slot_id: slot&.id,
          lifecycle_stage: "seed_packet"
        )
        counts[:plants] += 1
      end

      # Create succession plans + generate tasks
      successions.each do |s|
        plan = SuccessionPlan.create(
          crop: s["crop"],
          varieties: (s["varieties"] || []).to_json,
          interval_days: s["interval_days"].to_i,
          season_start: s["season_start"] ? Date.parse(s["season_start"]) : nil,
          season_end: s["season_end"] ? Date.parse(s["season_end"]) : nil,
          total_planned_sowings: s["total_sowings"].to_i,
          target_beds: (s["target_beds"] || []).to_json
        )
        TaskGenerator.generate_for_plan!(plan)
        counts[:succession_plans] += 1
        counts[:tasks] += Task.where(task_type: "sow")
                              .where(Sequel.like(:title, "%#{plan.crop}%")).count
      end

      # Create explicit tasks
      tasks.each do |t|
        task = Task.create(
          title: t["title"],
          task_type: t["task_type"] || "sow",
          due_date: t["due_date"] ? Date.parse(t["due_date"]) : nil,
          priority: t["priority"] || "should",
          status: "upcoming",
          notes: t["notes"]
        )
        (t["related_beds"] || []).each do |bed_name|
          bed = Bed.where(name: bed_name).first
          DB[:tasks_beds].insert(task_id: task.id, bed_id: bed.id) if bed
        end
        counts[:tasks] += 1
      end
    end

    { success: true, created: counts }
  rescue => e
    { success: false, errors: ["Commit failed: #{e.message}"] }
  end

  private

  def self.validate_beds(assignments, tasks)
    errors = []
    bed_names = (assignments.map { |a| a["bed_name"] } +
                 tasks.flat_map { |t| t["related_beds"] || [] }).compact.uniq

    bed_names.each do |name|
      errors << "Bed '#{name}' not found" unless Bed.where(name: name).any?
    end

    errors
  end
end
```

- [ ] **Step 3: Run tests**

Run: `rm -f db/garden_os_test.db && ruby test/services/test_plan_committer.rb`
Expected: 5 tests, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add services/plan_committer.rb test/services/test_plan_committer.rb
git commit -m "feat: PlanCommitter — validates and commits draft plans to DB in a transaction"
```

---

### Task 6: Planner Routes

**Files:**
- Modify: `routes/succession.rb`
- Create: `test/routes/test_planner_routes.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/routes/test_planner_routes.rb
require_relative "../test_helper"
require_relative "../../app"

class TestPlannerRoutes < GardenTest
  def test_planner_message_requires_content
    post "/succession/planner/message", {}.to_json, "CONTENT_TYPE" => "application/json"
    assert_equal 400, last_response.status
  end

  def test_delete_messages
    PlannerMessage.create(role: "user", content: "test", created_at: Time.now)
    delete "/succession/planner/messages"
    assert_equal 200, last_response.status
    assert_equal 0, PlannerMessage.count
  end

  def test_commit_validates_draft
    post "/succession/planner/commit",
      { draft_payload: { "assignments" => [{ "bed_name" => "FAKE" }], "successions" => [], "tasks" => [] } }.to_json,
      "CONTENT_TYPE" => "application/json"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    refute data["success"]
    assert_includes data["errors"].first, "FAKE"
  end

  def test_commit_creates_records
    bed = Bed.create(name: "BB1", bed_type: "raised")
    row = Row.create(bed_id: bed.id, name: "A", position: 1)
    Slot.create(row_id: row.id, name: "Pos1", position: 1)

    draft = {
      "assignments" => [
        { "bed_name" => "BB1", "row_name" => "A", "slot_position" => 1,
          "variety_name" => "Raf", "crop_type" => "tomato" }
      ],
      "successions" => [],
      "tasks" => []
    }
    post "/succession/planner/commit",
      { draft_payload: draft }.to_json,
      "CONTENT_TYPE" => "application/json"

    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert data["success"]
    assert_equal 1, Plant.count
  end
end
```

- [ ] **Step 2: Add planner routes to routes/succession.rb**

Add these routes to the GardenApp class in `routes/succession.rb`:

```ruby
  # ── AI Planner Chat ──────────────────────────────────────────────────────

  post "/succession/planner/message" do
    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    message = body["message"].to_s.strip
    halt 400, json(error: "message required") if message.empty?

    require_relative "../services/planner_service"
    service = PlannerService.new
    result = service.send_message(message)

    json({
      content: result[:content],
      draft: result[:draft]
    })
  end

  post "/succession/planner/commit" do
    request.body.rewind
    body = begin
      JSON.parse(request.body.read)
    rescue
      halt 400, json(error: "Invalid JSON")
    end

    draft = body["draft_payload"]
    halt 400, json(error: "draft_payload required") unless draft.is_a?(Hash)

    require_relative "../services/plan_committer"
    result = PlanCommitter.commit!(draft)
    json result
  end

  delete "/succession/planner/messages" do
    require_relative "../models/planner_message"
    PlannerMessage.delete
    json(success: true)
  end
```

Also update the `get "/succession"` route to load planner messages:

```ruby
  get "/succession" do
    @plans = SuccessionPlan.all
    require_relative "../models/planner_message"
    @planner_messages = PlannerMessage.order(:created_at).all
    erb :succession
  end
```

- [ ] **Step 3: Run tests**

Run: `rm -f db/garden_os_test.db && ruby test/routes/test_planner_routes.rb`
Expected: 4 tests, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add routes/succession.rb test/routes/test_planner_routes.rb
git commit -m "feat: planner routes — message, commit, clear conversation"
```

---

### Task 7: Chat UI in Plan Tab

**Files:**
- Modify: `views/succession.erb`

This is the largest UI task. The chat goes above the existing plan management UI and Gantt chart.

- [ ] **Step 1: Add chat UI to views/succession.erb**

Add at the TOP of the file (before the existing plan management section):

The chat section uses Alpine.js `x-data` with:
- `messages` array loaded from `@planner_messages`
- `input` text field
- `sending` boolean for loading state
- `chatOpen` boolean for collapse toggle
- `async sendMessage()` — POST to `/succession/planner/message`
- `async commitDraft(payload)` — POST to `/succession/planner/commit`
- `async clearChat()` — DELETE `/succession/planner/messages`

**Chat message rendering:**
- User messages: right-aligned green bubbles
- AI messages: left-aligned white cards
- Draft messages: special card with bed assignment summary, task list, "Create this plan" button
- Loading: spinner with "Thinking..." text

**The Alpine.js component structure:**

```html
<div x-data="plannerChat()" class="mb-6">
  <!-- Header -->
  <div class="flex items-center justify-between mb-3">
    <button @click="chatOpen = !chatOpen" class="flex items-center gap-2">
      <h2 class="text-lg font-semibold" style="color: var(--text-primary);">Garden Planner</h2>
      <span x-text="chatOpen ? '▼' : '▶'" class="text-xs" style="color: var(--gray-400);"></span>
    </button>
    <button x-show="chatOpen" @click="clearChat()" class="text-xs" style="color: var(--gray-400);">New chat</button>
  </div>

  <!-- Chat area -->
  <div x-show="chatOpen" x-transition>
    <!-- Messages -->
    <div x-ref="chatMessages" class="space-y-3 mb-3 overflow-y-auto" style="max-height: 50vh;">
      <template x-for="msg in messages" :key="msg.id || msg.created_at">
        <!-- User message -->
        <div x-show="msg.role === 'user'" class="flex justify-end">
          <div class="rounded-xl px-4 py-2 text-sm max-w-[80%]" style="background: #d1fae5; color: var(--text-primary);" x-text="msg.content"></div>
        </div>
        <!-- AI message -->
        <div x-show="msg.role === 'assistant'" class="flex justify-start">
          <div class="rounded-xl px-4 py-3 text-sm max-w-[85%]" style="background: white; box-shadow: var(--card-shadow);">
            <div x-html="msg.content.replace(/\n/g, '<br>')"></div>
            <!-- Draft card if present -->
            <template x-if="msg.draft">
              <div class="mt-3 p-3 rounded-lg" style="background: #f0fdf4; border: 1px solid #bbf7d0;">
                <p class="text-xs font-semibold mb-2" style="color: #166534;">Plan Draft</p>
                <p class="text-xs mb-1" x-text="(msg.draft.assignments?.length || 0) + ' bed assignments'"></p>
                <p class="text-xs mb-1" x-text="(msg.draft.successions?.length || 0) + ' succession schedules'"></p>
                <p class="text-xs mb-2" x-text="(msg.draft.tasks?.length || 0) + ' tasks'"></p>
                <button @click="commitDraft(msg.draft)" :disabled="msg.committed"
                  class="text-xs px-3 py-1.5 rounded-lg font-medium"
                  :style="msg.committed ? 'background: #d1fae5; color: #166534;' : 'background: var(--green-900); color: white;'"
                  x-text="msg.committed ? 'Plan created ✓' : 'Create this plan'">
                </button>
              </div>
            </template>
          </div>
        </div>
      </template>
      <!-- Thinking indicator -->
      <div x-show="sending" class="flex justify-start">
        <div class="rounded-xl px-4 py-3 text-sm flex items-center gap-2" style="background: white; box-shadow: var(--card-shadow); color: var(--gray-500);">
          <svg width="14" height="14" viewBox="0 0 16 16" style="animation: spin 0.8s linear infinite;">
            <circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-width="2" stroke-dasharray="28" stroke-dashoffset="8" stroke-linecap="round"/>
          </svg>
          Thinking...
        </div>
      </div>
    </div>

    <!-- Input -->
    <div class="flex gap-2">
      <input type="text" x-model="input" @keydown.enter="sendMessage()"
             placeholder="What would you like to grow?"
             class="flex-1 rounded-xl px-4 py-2.5 text-sm border"
             style="border-color: #e5e7eb;" :disabled="sending">
      <button @click="sendMessage()" :disabled="sending || !input.trim()"
              class="px-4 py-2.5 rounded-xl text-sm font-medium"
              style="background: var(--green-900); color: white;">
        Send
      </button>
    </div>
  </div>
</div>
```

**The Alpine.js component function (in a `<script>` block):**

```javascript
function plannerChat() {
  return {
    messages: window.__PLANNER_MESSAGES__ || [],
    input: '',
    sending: false,
    chatOpen: true,

    async sendMessage() {
      const text = this.input.trim();
      if (!text || this.sending) return;

      this.messages.push({ role: 'user', content: text, created_at: Date.now() });
      this.input = '';
      this.sending = true;
      this.scrollToBottom();

      try {
        const resp = await fetch('/succession/planner/message', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: text })
        });
        const data = await resp.json();
        this.messages.push({
          role: 'assistant',
          content: data.content,
          draft: data.draft,
          created_at: Date.now()
        });
      } catch(e) {
        this.messages.push({ role: 'assistant', content: 'Sorry, something went wrong.', created_at: Date.now() });
      }
      this.sending = false;
      this.scrollToBottom();
    },

    async commitDraft(draft) {
      try {
        const resp = await fetch('/succession/planner/commit', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ draft_payload: draft })
        });
        const data = await resp.json();
        if (data.success) {
          // Mark the draft message as committed
          const msg = this.messages.find(m => m.draft === draft);
          if (msg) msg.committed = true;
          // Reload the page to refresh Gantt + plan cards
          setTimeout(() => window.location.reload(), 1000);
        } else {
          alert('Failed to create plan: ' + (data.errors || []).join(', '));
        }
      } catch(e) {
        alert('Error creating plan');
      }
    },

    async clearChat() {
      if (!confirm('Start a new planning conversation?')) return;
      await fetch('/succession/planner/messages', { method: 'DELETE' });
      this.messages = [];
    },

    scrollToBottom() {
      this.$nextTick(() => {
        const el = this.$refs.chatMessages;
        if (el) el.scrollTop = el.scrollHeight;
      });
    }
  };
}
```

**Data bootstrap (in the ERB, before the Alpine component):**

```erb
<script>
  window.__PLANNER_MESSAGES__ = <%= @planner_messages.map { |m|
    { role: m.role, content: m.content, draft: m.draft_data, created_at: m.created_at.to_i }
  }.to_json %>;
</script>
```

- [ ] **Step 2: Run full test suite**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add views/succession.erb
git commit -m "feat: planner chat UI — conversational AI garden planning in Plan tab"
```

---

## Summary

| Task | What | Files | Complexity |
|------|------|-------|------------|
| 1 | Migration + PlannerMessage model | migration, model | Small |
| 2 | 5 data query tools | services/planner_tools/*.rb | Small (repetitive) |
| 3 | DraftPlanTool | services/planner_tools/draft_plan_tool.rb | Small |
| 4 | PlannerService (LLM orchestration) | services/planner_service.rb | Medium |
| 5 | PlanCommitter (draft → DB) | services/plan_committer.rb | Medium |
| 6 | Planner routes | routes/succession.rb | Small |
| 7 | Chat UI in Plan tab | views/succession.erb | Medium-Large |

**Total: 7 tasks.**

**After completion, the flow is:**
1. Go to Plan tab → chat with the garden planner
2. "I want to grow 20 tomato varieties, succession lettuce, and herbs"
3. AI calls `get_beds` + `get_seed_inventory` → proposes a plan
4. Plan draft appears as a visual card in the chat
5. "Move peppers to Corner instead" → AI revises, calls `draft_plan` again
6. Click "Create this plan" → all Plants, SuccessionPlans, Tasks created
7. Gantt chart populates, Plants tab shows your new plants, Dashboard shows today's tasks
