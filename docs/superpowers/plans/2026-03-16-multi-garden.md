# Multi-Garden Support Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scope all garden data (beds, plants, tasks, succession plans) to a selectable garden, with a cookie-based garden switcher in the UI. Seed inventory stays global.

**Architecture:** New `gardens` table + `garden_id` FK on 8 existing tables. A Sinatra `before` filter reads the active garden from a cookie. All queries scope by `@current_garden.id`. Layout gets a garden switcher dropdown. Tests create a default garden in setup.

**Tech Stack:** Sequel migrations, Sinatra before filter, browser cookies, Alpine.js dropdown

**Spec:** `docs/superpowers/specs/2026-03-16-multi-garden.md`

---

## File Structure

```
Modified/Created:
├── db/migrations/013_create_gardens.rb              # NEW — gardens table + garden_id on 8 tables
├── models/garden.rb                                  # NEW
├── models/bed.rb                                     # MODIFY — add garden association
├── models/plant.rb                                   # MODIFY — add garden association
├── models/task.rb                                    # MODIFY — add garden association
├── models/succession_plan.rb                         # MODIFY — add garden association
├── models/advisory.rb                                # MODIFY — add garden association
├── models/planner_message.rb                         # MODIFY — add garden association
├── app.rb                                            # MODIFY — before filter for @current_garden
├── routes/dashboard.rb                               # MODIFY — scope queries
├── routes/plants.rb                                  # MODIFY — scope queries
├── routes/beds.rb                                    # MODIFY — scope queries
├── routes/tasks.rb                                   # MODIFY — scope queries
├── routes/succession.rb                              # MODIFY — scope queries
├── routes/photos.rb                                  # MODIFY — scope queries
├── views/layout.erb                                  # MODIFY — garden switcher dropdown
├── services/planner_service.rb                       # MODIFY — garden in system prompt + tool scoping
├── services/planner_tools/get_beds_tool.rb           # MODIFY — scope by garden
├── services/planner_tools/get_plants_tool.rb         # MODIFY — scope by garden
├── services/planner_tools/get_succession_plans_tool.rb # MODIFY — scope by garden
├── services/task_generator.rb                        # MODIFY — iterate per garden
├── services/ai_advisory_service.rb                   # MODIFY — run per garden
├── services/plan_committer.rb                        # MODIFY — set garden_id on created records
├── test/test_helper.rb                               # MODIFY — create default garden in setup
├── test/**/*.rb                                      # MODIFY — add garden_id to all creates (25 files)
```

---

### Task 1: Migration — Gardens Table + garden_id on Existing Tables

**Files:**
- Create: `db/migrations/013_create_gardens.rb`
- Create: `models/garden.rb`

- [ ] **Step 1: Create migration**

```ruby
# db/migrations/013_create_gardens.rb
Sequel.migration do
  up do
    # 1. Create gardens table
    create_table(:gardens) do
      primary_key :id
      String :name, null: false, unique: true
      String :location
      String :climate_zone
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    # 2. Seed default gardens
    self[:gardens].insert(name: "Home", location: "Prague", climate_zone: "6b/7a")
    self[:gardens].insert(name: "Cottage")

    # 3. Add garden_id to scoped tables (nullable first for backfill)
    %i[beds arches indoor_stations plants tasks succession_plans planner_messages advisories].each do |table|
      alter_table(table) do
        add_column :garden_id, Integer
      end
    end

    # 4. Backfill all existing rows to garden 1 (Home)
    home_id = self[:gardens].where(name: "Home").get(:id)
    %i[beds arches indoor_stations plants tasks succession_plans planner_messages advisories].each do |table|
      self[table].update(garden_id: home_id)
    end

    # 5. Add NOT NULL + FK constraints
    %i[beds arches indoor_stations plants tasks succession_plans planner_messages advisories].each do |table|
      alter_table(table) do
        set_column_not_null :garden_id
        add_foreign_key_constraint(:garden_id, :gardens, on_delete: :cascade, name: :"fk_#{table}_garden")
        add_index :garden_id, name: :"idx_#{table}_garden_id"
      end
    end

    # 6. Replace beds unique index: name → (garden_id, name)
    alter_table(:beds) do
      drop_index :name, name: :beds_name_key rescue nil
      add_unique_constraint [:garden_id, :name], name: :beds_garden_name_unique
    end
  end

  down do
    %i[beds arches indoor_stations plants tasks succession_plans planner_messages advisories].each do |table|
      alter_table(table) do
        drop_column :garden_id
      end
    end
    drop_table(:gardens)
  end
end
```

- [ ] **Step 2: Create Garden model**

```ruby
# models/garden.rb
require_relative "../config/database"

class Garden < Sequel::Model
  one_to_many :beds
  one_to_many :plants
  one_to_many :tasks
  one_to_many :succession_plans
  one_to_many :planner_messages
  one_to_many :advisories
end
```

- [ ] **Step 3: Run migration**

Run: `rake db:migrate`

- [ ] **Step 4: Commit**

```bash
git add db/migrations/013_create_gardens.rb models/garden.rb
git commit -m "feat: gardens table + garden_id FK on 8 tables, backfill existing data to Home"
```

---

### Task 2: Before Filter + Garden Switcher Route

**Files:**
- Modify: `app.rb` — add before filter
- Modify: `models/bed.rb`, `models/plant.rb`, `models/task.rb`, `models/succession_plan.rb`, `models/advisory.rb`, `models/planner_message.rb` — add `many_to_one :garden`

- [ ] **Step 1: Add before filter to app.rb**

Add after the `configure` blocks, before `get "/health"`:

```ruby
  before do
    require_relative "models/garden"
    garden_id = request.cookies["garden_id"]&.to_i
    @current_garden = (garden_id && Garden[garden_id]) || Garden.first
    @gardens = Garden.order(:name).all
  end

  post "/gardens/switch/:id" do
    require_relative "models/garden"
    garden = Garden[params[:id].to_i]
    halt 404 unless garden
    response.set_cookie("garden_id", value: garden.id.to_s, path: "/", httponly: true, same_site: :lax)
    redirect back
  end
```

- [ ] **Step 2: Add `many_to_one :garden` to all scoped models**

Add `many_to_one :garden` to: `models/bed.rb`, `models/plant.rb`, `models/task.rb`, `models/succession_plan.rb`, `models/advisory.rb`, `models/planner_message.rb`.

Also add `many_to_one :garden` to `Arch` and `IndoorStation` in `models/bed.rb`.

- [ ] **Step 3: Commit**

```bash
git add app.rb models/
git commit -m "feat: before filter sets @current_garden from cookie, garden switcher route"
```

---

### Task 3: Update Test Helper + Fix All Tests

**Files:**
- Modify: `test/test_helper.rb`
- Modify: ALL 25 test files

This is the biggest task — every test that creates a Bed, Plant, Task, SuccessionPlan, Arch, IndoorStation, PlannerMessage, or Advisory needs `garden_id`.

- [ ] **Step 1: Update test_helper.rb**

```ruby
# test/test_helper.rb
ENV["RACK_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite://db/garden_os_test.db"

require "minitest/autorun"
require "rack/test"
require_relative "../config/database"

if Dir["db/migrations/*.rb"].any?
  Sequel::Migrator.run(DB, "db/migrations", allow_missing_migration_files: true)
end

require_relative "../models/garden"

class GardenTest < Minitest::Test
  include Rack::Test::Methods

  def app
    GardenApp
  end

  def setup
    DB.tables.each { |t| DB[t].delete unless [:schema_migrations, :schema_info].include?(t) }
    @garden = Garden.create(name: "Test Garden", created_at: Time.now)
    set_cookie "garden_id=#{@garden.id}"
  end
end
```

- [ ] **Step 2: Find and update all test files**

Every `Bed.create(...)`, `Plant.create(...)`, `Task.create(...)`, `SuccessionPlan.create(...)`, `IndoorStation.create(...)`, `Arch.create(...)`, `PlannerMessage.create(...)`, and `Advisory.create(...)` call needs `garden_id: @garden.id` added.

This is mechanical — search each test file for `.create(` calls on these models and add the parameter.

Also: route tests that create beds/plants need to pass garden_id. For JSON API routes, include it in the payload. For form POSTs, the before filter will use the cookie.

- [ ] **Step 3: Run full test suite**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`
Expected: All 146 tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/
git commit -m "feat: tests create default garden, all model creates include garden_id"
```

---

### Task 4: Scope All Routes

**Files:**
- Modify: `routes/dashboard.rb`
- Modify: `routes/plants.rb`
- Modify: `routes/beds.rb`
- Modify: `routes/tasks.rb`
- Modify: `routes/succession.rb`
- Modify: `routes/photos.rb`
- Modify: `services/plan_committer.rb`
- Modify: `services/planner_service.rb`
- Modify: `services/planner_tools/get_beds_tool.rb`
- Modify: `services/planner_tools/get_plants_tool.rb`
- Modify: `services/planner_tools/get_succession_plans_tool.rb`

Every query on a garden-scoped model needs `.where(garden_id: @current_garden.id)` added. Every `create` call needs `garden_id: @current_garden.id`.

- [ ] **Step 1: Scope dashboard.rb**

All queries for tasks, plants, advisories add `.where(garden_id: @current_garden.id)`.

- [ ] **Step 2: Scope plants.rb**

Plant queries, Plant.create, and the `/api/plants` endpoint.

- [ ] **Step 3: Scope beds.rb**

Bed queries, Bed.create, garden route, API endpoints. Arch and IndoorStation queries too.

- [ ] **Step 4: Scope tasks.rb**

Task queries and API endpoints.

- [ ] **Step 5: Scope succession.rb**

SuccessionPlan queries, PlannerMessage queries, and the planner routes. The `/succession/planner/ask` route must pass `garden_id` to PlannerService.

- [ ] **Step 6: Scope photos.rb**

Plant lookups when uploading/viewing photos.

- [ ] **Step 7: Scope plan_committer.rb**

`PlanCommitter.commit!` needs to receive `garden_id` and pass it to all `Plant.create`, `SuccessionPlan.create`, `Task.create` calls.

- [ ] **Step 8: Scope planner tools**

`GetBedsTool`, `GetPlantsTool`, `GetSuccessionPlansTool` need access to the current garden_id. Pass it via `Thread.current[:current_garden_id]` (set in the route before calling PlannerService).

- [ ] **Step 9: Update planner system prompt**

Include the garden name:
```ruby
"You are planning for the \"#{@current_garden.name}\" garden#{@current_garden.location ? " in #{@current_garden.location}" : ""}..."
```

- [ ] **Step 10: Run full test suite**

Run: `rm -f db/garden_os_test.db && ruby -Itest -e "Dir['test/**/*test*.rb'].sort.each { |f| require_relative f }"`

- [ ] **Step 11: Commit**

```bash
git add routes/ services/
git commit -m "feat: all routes and services scoped to active garden"
```

---

### Task 5: Garden Switcher UI

**Files:**
- Modify: `views/layout.erb`

- [ ] **Step 1: Add garden switcher to layout**

In `layout.erb`, add an Alpine.js dropdown in the `<main>` area (before `<%= yield %>`), visible on every page:

```erb
<!-- Garden Switcher -->
<div x-data="{ open: false }" class="mb-4 flex items-center gap-2">
  <span class="text-lg">🌱</span>
  <span class="font-bold" style="color: var(--green-900);">GardenOS</span>
  <span style="color: var(--gray-400);">·</span>
  <div class="relative">
    <button @click="open = !open" class="flex items-center gap-1 font-semibold text-sm"
            style="color: var(--green-900);">
      <%= @current_garden&.name || "Garden" %>
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 12 15 18 9"/></svg>
    </button>
    <div x-show="open" @click.away="open = false" x-transition
         class="absolute left-0 mt-1 rounded-lg overflow-hidden z-50 min-w-[140px]"
         style="background: white; box-shadow: 0 4px 12px rgba(0,0,0,0.12); border: 1px solid #e5e7eb;">
      <% @gardens&.each do |g| %>
        <form method="post" action="/gardens/switch/<%= g.id %>" class="block">
          <button type="submit" class="w-full text-left px-3 py-2 text-sm flex items-center justify-between hover:bg-gray-50"
                  style="color: var(--text-primary);">
            <%= g.name %>
            <% if g.id == @current_garden&.id %>
              <span style="color: var(--green-900);">✓</span>
            <% end %>
          </button>
        </form>
      <% end %>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Run tests + manual verify**

- [ ] **Step 3: Commit**

```bash
git add views/layout.erb
git commit -m "feat: garden switcher dropdown in layout — visible on every page"
```

---

### Task 6: Background Jobs — Per-Garden Iteration

**Files:**
- Modify: `services/task_generator.rb`
- Modify: `services/ai_advisory_service.rb`
- Modify: `services/scheduler.rb`

- [ ] **Step 1: Update TaskGenerator**

`generate_all!` and `generate_for_plan!` need to accept and use `garden_id`:

```ruby
def self.generate_all!(garden_id: nil)
  if garden_id
    generate_succession_tasks!(garden_id: garden_id)
    generate_germination_checks!(garden_id: garden_id)
  else
    Garden.all.each { |g| generate_all!(garden_id: g.id) }
  end
end
```

Scope all queries by garden_id when provided.

- [ ] **Step 2: Update AIAdvisoryService**

`run_daily!` accepts `garden_id:`, scopes plant/task queries, stores `garden_id` on the advisory.

- [ ] **Step 3: Update scheduler.rb**

Iterate over all gardens for daily advisory and task generation:

```ruby
scheduler.cron "30 6 * * *" do
  Garden.all.each { |g| AIAdvisoryService.run_daily!(garden_id: g.id) }
end

scheduler.cron "0 */6 * * *" do
  Garden.all.each { |g| TaskGenerator.generate_all!(garden_id: g.id) }
end
```

- [ ] **Step 4: Run tests**

- [ ] **Step 5: Commit**

```bash
git add services/
git commit -m "feat: background jobs iterate per garden for advisories and task generation"
```

---

## Summary

| Task | What | Complexity | Files |
|------|------|-----------|-------|
| 1 | Migration + Garden model | Medium | 2 new files |
| 2 | Before filter + model associations | Small | app.rb + 6 models |
| 3 | Fix test helper + all 25 test files | Large (mechanical) | 26 files |
| 4 | Scope all routes + services | Large | 11 files |
| 5 | Garden switcher UI | Small | layout.erb |
| 6 | Background jobs per-garden | Small | 3 service files |

**Total: 6 tasks.** Tasks 1-3 are sequential (each depends on previous). Tasks 4-6 can run after Task 3.

**After completion:**
- Open the app → see "GardenOS · Home ▾" in the header
- Click the dropdown → switch to "Cottage"
- All beds, plants, tasks, plans now show only Cottage data
- Seeds tab shows all seeds (shared)
- Planner conversation is per-garden
