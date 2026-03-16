# Harvest Log Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Harvest model, routes, inline UI form, and AI context enrichment so users can log harvests per plant and the AI can reference harvest history.
**Architecture:** A new `harvests` table with `ON DELETE CASCADE` FK to `plants` mirrors the `stage_histories` pattern. A `Harvest` Sequel model is added to `Plant` as a `one_to_many` association. Routes follow the existing split between HTML form posts and JSON API endpoints, all inside `GardenApp`. The plant detail view gains an Alpine.js-toggled inline form and a merged timeline that interleaves stage transitions with harvest entries.
**Tech Stack:** Sequel (SQLite migrations), Sinatra, ERB, Alpine.js (already in layout), Minitest + Rack::Test.
**Spec:** `docs/superpowers/specs/2026-03-16-v2-features.md` — Section 1

---

## Task 1 — Migration + Model

### 1.1 Create `db/migrations/007_create_harvests.rb`

- [ ] Create the file `db/migrations/007_create_harvests.rb` with the following content:

```ruby
Sequel.migration do
  change do
    create_table(:harvests) do
      primary_key :id
      foreign_key :plant_id, :plants, null: false, on_delete: :cascade
      Date :date, null: false, default: Sequel::CURRENT_DATE
      String :quantity, null: false   # enum: small | medium | large | huge
      String :notes
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      index :plant_id
    end
  end
end
```

### 1.2 Create `models/harvest.rb`

- [ ] Create the file `models/harvest.rb` with the following content:

```ruby
require_relative "../config/database"

class Harvest < Sequel::Model
  QUANTITIES = %w[small medium large huge].freeze

  many_to_one :plant

  def validate
    super
    errors.add(:quantity, "must be one of: #{QUANTITIES.join(', ')}") unless QUANTITIES.include?(quantity)
    errors.add(:date, "is required") if date.nil?
    errors.add(:plant_id, "is required") if plant_id.nil?
  end
end
```

### 1.3 Update `models/plant.rb` — add association and require

- [ ] Edit `models/plant.rb`: add `require_relative "harvest"` at the top alongside the existing requires, and add `one_to_many :harvests` to the model body.

The updated file header and association block:

```ruby
require_relative "../config/database"
require_relative "stage_history"
require_relative "harvest"

class Plant < Sequel::Model
  many_to_one :slot
  many_to_one :indoor_station
  one_to_many :stage_histories
  one_to_many :harvests
  many_to_many :tasks
  # ... rest of model unchanged
```

### 1.4 Run the migration and verify

- [ ] Run:

```bash
bundle exec rake db:migrate
```

Expected output includes:

```
Running migrations on garden_os.db
007_create_harvests.rb (up)
```

- [ ] Verify schema:

```bash
sqlite3 db/garden_os.db ".schema harvests"
```

Expected output:

```
CREATE TABLE `harvests` (`id` integer NOT NULL PRIMARY KEY AUTOINCREMENT, `plant_id` integer NOT NULL REFERENCES `plants` ON DELETE CASCADE, `date` date NOT NULL, `quantity` varchar(255) NOT NULL, `notes` varchar(255), `created_at` datetime, `plant_id_index` );
```

### 1.5 Commit

```bash
git add db/migrations/007_create_harvests.rb models/harvest.rb models/plant.rb
git commit -m "feat: add Harvest model and migration (007_create_harvests)"
```

---

## Task 2 — Routes + Tests

### 2.1 Update `routes/plants.rb`

- [ ] Add `require_relative "../models/harvest"` at the top of `routes/plants.rb`.

- [ ] Add two new routes after the existing `post "/plants/:id/advance"` block:

```ruby
post "/plants/:id/harvests" do
  plant = Plant[params[:id].to_i]
  halt 404 unless plant

  harvest = Harvest.new(
    plant_id: plant.id,
    date:     params[:date].to_s.empty? ? Date.today : Date.parse(params[:date]),
    quantity: params[:quantity],
    notes:    params[:notes].to_s.strip.then { |n| n.empty? ? nil : n }
  )

  if harvest.valid?
    harvest.save
  else
    # Re-render show with error — simple approach consistent with existing redirect pattern
    @plant   = plant
    @history = StageHistory.where(plant_id: plant.id).order(:changed_at).all
    @harvests = Harvest.where(plant_id: plant.id).order(Sequel.desc(:date)).all
    @harvest_error = harvest.errors.full_messages.join(", ")
    return erb :"plants/show"
  end

  redirect "/plants/#{plant.id}"
end

get "/api/plants/:id/harvests" do
  plant = Plant[params[:id].to_i]
  halt 404 unless plant

  harvests = Harvest.where(plant_id: plant.id).order(Sequel.desc(:date)).all.map do |h|
    {
      id:         h.id,
      date:       h.date.to_s,
      quantity:   h.quantity,
      notes:      h.notes,
      created_at: h.created_at.to_s
    }
  end

  json harvests
end
```

- [ ] Also update the existing `get "/plants/:id"` route to load harvests so the view can render them:

```ruby
get "/plants/:id" do
  @plant    = Plant[params[:id].to_i]
  halt 404, "Plant not found" unless @plant
  @history  = StageHistory.where(plant_id: @plant.id).order(:changed_at).all
  @harvests = Harvest.where(plant_id: @plant.id).order(Sequel.desc(:date)).all
  erb :"plants/show"
end
```

### 2.2 Add tests to `test/routes/test_plants.rb`

- [ ] Append the following test cases to the `TestPlants` class in `test/routes/test_plants.rb`:

```ruby
  # --- Harvest routes ---

  def test_log_harvest_creates_record
    plant = Plant.create(variety_name: "San Marzano", crop_type: "tomato")
    post "/plants/#{plant.id}/harvests", quantity: "large", date: "2026-03-16", notes: "First pick"
    assert_equal 302, last_response.status
    assert_equal 1, Harvest.where(plant_id: plant.id).count
    h = Harvest.where(plant_id: plant.id).first
    assert_equal "large",      h.quantity
    assert_equal "First pick", h.notes
    assert_equal Date.new(2026, 3, 16), h.date
  end

  def test_log_harvest_defaults_date_to_today
    plant = Plant.create(variety_name: "San Marzano", crop_type: "tomato")
    post "/plants/#{plant.id}/harvests", quantity: "small"
    assert_equal 302, last_response.status
    h = Harvest.where(plant_id: plant.id).first
    assert_equal Date.today, h.date
  end

  def test_log_harvest_invalid_quantity_returns_200
    plant = Plant.create(variety_name: "San Marzano", crop_type: "tomato")
    post "/plants/#{plant.id}/harvests", quantity: "enormous"
    assert_equal 200, last_response.status
    assert_equal 0, Harvest.where(plant_id: plant.id).count
  end

  def test_log_harvest_unknown_plant_returns_404
    post "/plants/99999/harvests", quantity: "small"
    assert_equal 404, last_response.status
  end

  def test_api_harvests_returns_json_array
    plant = Plant.create(variety_name: "San Marzano", crop_type: "tomato")
    Harvest.create(plant_id: plant.id, date: Date.today, quantity: "medium")
    Harvest.create(plant_id: plant.id, date: Date.today - 1, quantity: "small")
    get "/api/plants/#{plant.id}/harvests"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 2,        data.length
    assert_equal "medium", data.first["quantity"]   # ordered desc by date
    assert_equal "small",  data.last["quantity"]
  end

  def test_api_harvests_unknown_plant_returns_404
    get "/api/plants/99999/harvests"
    assert_equal 404, last_response.status
  end

  def test_plant_show_includes_harvest_section
    plant = Plant.create(variety_name: "San Marzano", crop_type: "tomato")
    Harvest.create(plant_id: plant.id, date: Date.today, quantity: "huge", notes: "Bumper crop")
    get "/plants/#{plant.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Log harvest"
    assert_includes last_response.body, "Bumper crop"
    assert_includes last_response.body, "huge"
  end
```

### 2.3 Run tests and verify they pass

- [ ] Run:

```bash
rm -f db/garden_os_test.db && bundle exec ruby -Itest test/routes/test_plants.rb
```

Expected output (all tests pass):

```
Run options: --seed XXXX

# Running:

.........

Finished in X.XXXXXX, XX.XXXX runs/s, XX.XXXX assertions/s.

9 runs, 14 assertions, 0 failures, 0 errors, 0 skips
```

### 2.4 Commit

```bash
git add routes/plants.rb test/routes/test_plants.rb
git commit -m "feat: add POST /plants/:id/harvests and GET /api/plants/:id/harvests routes + tests"
```

---

## Task 3 — Plant Detail UI

### 3.1 Update `views/plants/show.erb`

- [ ] Replace the entire contents of `views/plants/show.erb` with the following. Changes from the current file:
  - Add Alpine.js `x-data` wrapper div around the page (uses `x-data="{ showHarvestForm: false }"`)
  - Add "Log harvest" card below the Actions card
  - Update the Timeline card to merge `@history` stage transitions and `@harvests` harvest entries in chronological order, rendered together

```erb
<% # Build a merged, sorted timeline of stage transitions and harvests
   timeline = []
   @history.each do |h|
     timeline << { type: :stage, at: h.changed_at, entry: h }
   end
   @harvests.each do |h|
     timeline << { type: :harvest, at: h.date.to_time, entry: h }
   end
   timeline.sort_by! { |t| t[:at] }
%>

<div x-data="{ showHarvestForm: false }">

<!-- Back Link -->
<a href="/plants" class="text-sm hover:underline mb-5 inline-block" style="color: var(--green-900);">
  &larr; All plants
</a>

<!-- Page Header -->
<div class="mb-5">
  <h1 class="text-2xl font-bold" style="color: var(--text-primary); letter-spacing: -0.5px;">
    <%= @plant.variety_name %>
  </h1>
  <p class="text-sm capitalize mt-1" style="color: var(--text-secondary);">
    <%= @plant.crop_type %> &mdash; <%= @plant.lifecycle_stage.tr('_', ' ') %>
  </p>
</div>

<!-- Actions Card -->
<div class="mb-4 px-4 py-4" style="background: white; border-radius: var(--card-radius); box-shadow: var(--card-shadow);">
  <p style="font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; font-weight: 600; color: var(--gray-500);" class="mb-3">
    Current Stage
  </p>
  <div class="mb-4">
    <span class="inline-block px-3 py-1 text-sm font-semibold text-white rounded-full"
          style="background: #16a34a;">
      <%= @plant.lifecycle_stage.tr('_', ' ').capitalize %>
    </span>
  </div>

  <% next_stages = Plant::LIFECYCLE_STAGES.drop(Plant::LIFECYCLE_STAGES.index(@plant.lifecycle_stage).to_i + 1).first(3) %>
  <% unless next_stages.empty? %>
    <p style="font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; font-weight: 600; color: var(--gray-500);" class="mb-2">
      Advance To
    </p>
    <div class="flex flex-col gap-2">
      <% next_stages.each_with_index do |stage, i| %>
        <form method="post" action="/plants/<%= @plant.id %>/advance">
          <input type="hidden" name="stage" value="<%= stage %>">
          <button type="submit"
                  class="w-full text-left px-4 py-3 rounded-xl font-medium text-sm transition hover:opacity-90"
                  style="<%= i == 0 ? "background: var(--green-900); color: white;" : "background: #f3f4f6; color: var(--text-primary);" %>">
            <%= stage.tr('_', ' ').capitalize %>
          </button>
        </form>
      <% end %>
    </div>
  <% end %>
</div>

<!-- Key Dates Card -->
<div class="mb-4 px-4 py-4" style="background: white; border-radius: var(--card-radius); box-shadow: var(--card-shadow);">
  <p style="font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; font-weight: 600; color: var(--gray-500);" class="mb-3">
    Key Dates
  </p>
  <div class="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
    <div>
      <p style="font-size: 11px; color: var(--gray-500);">Sown</p>
      <p class="font-medium" style="color: var(--text-primary);">
        <%= @plant.sow_date || "—" %>
      </p>
    </div>
    <div>
      <p style="font-size: 11px; color: var(--gray-500);">Germinated</p>
      <p class="font-medium" style="color: var(--text-primary);">
        <%= @plant.germination_date || "—" %>
      </p>
    </div>
    <div>
      <p style="font-size: 11px; color: var(--gray-500);">Transplanted</p>
      <p class="font-medium" style="color: var(--text-primary);">
        <%= @plant.transplant_date || "—" %>
      </p>
    </div>
    <div>
      <p style="font-size: 11px; color: var(--gray-500);">Days in stage</p>
      <p class="font-medium" style="color: var(--text-primary);">
        <%= @plant.days_in_stage %>
      </p>
    </div>
  </div>
</div>

<!-- Log Harvest Card -->
<div class="mb-4 px-4 py-4" style="background: white; border-radius: var(--card-radius); box-shadow: var(--card-shadow);">
  <div class="flex items-center justify-between mb-1">
    <p style="font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; font-weight: 600; color: var(--gray-500);">
      Harvest
    </p>
    <button type="button"
            @click="showHarvestForm = !showHarvestForm"
            class="text-sm font-semibold px-3 py-1 rounded-full transition hover:opacity-80"
            style="background: var(--green-900); color: white;">
      <span x-text="showHarvestForm ? 'Cancel' : 'Log harvest'">Log harvest</span>
    </button>
  </div>

  <% if defined?(@harvest_error) && @harvest_error %>
    <p class="text-sm mt-2" style="color: #dc2626;">Error: <%= @harvest_error %></p>
  <% end %>

  <!-- Inline harvest form — shown/hidden by Alpine -->
  <div x-show="showHarvestForm" x-transition class="mt-4">
    <form method="post" action="/plants/<%= @plant.id %>/harvests">
      <!-- Quantity buttons -->
      <p class="text-xs font-semibold mb-2" style="color: var(--text-secondary);">How much?</p>
      <div class="grid grid-cols-4 gap-2 mb-4">
        <% %w[small medium large huge].each do |qty| %>
          <label class="flex flex-col items-center cursor-pointer">
            <input type="radio" name="quantity" value="<%= qty %>" class="sr-only" required
                   x-data x-bind:id="'qty-<%= qty %>'">
            <span class="w-full text-center px-2 py-2 rounded-xl text-sm font-semibold border-2 transition"
                  style="border-color: #d1d5db; background: #f9fafb; color: var(--text-primary);"
                  x-bind:style="$el.previousElementSibling.checked ? 'border-color: #16a34a; background: #dcfce7; color: #15803d;' : ''">
              <%= qty.capitalize %>
            </span>
          </label>
        <% end %>
      </div>

      <!-- Notes field -->
      <div class="mb-4">
        <label class="text-xs font-semibold block mb-1" style="color: var(--text-secondary);">
          Notes <span style="color: var(--gray-400);">(optional)</span>
        </label>
        <input type="text" name="notes" placeholder="e.g. first red tomatoes from bed 2"
               class="w-full px-3 py-2 text-sm rounded-xl border"
               style="border-color: #d1d5db; color: var(--text-primary); background: white;">
      </div>

      <!-- Date field -->
      <div class="mb-4">
        <label class="text-xs font-semibold block mb-1" style="color: var(--text-secondary);">
          Date
        </label>
        <input type="date" name="date" value="<%= Date.today %>"
               class="w-full px-3 py-2 text-sm rounded-xl border"
               style="border-color: #d1d5db; color: var(--text-primary); background: white;">
      </div>

      <button type="submit"
              class="w-full px-4 py-3 rounded-xl font-semibold text-sm transition hover:opacity-90"
              style="background: var(--green-900); color: white;">
        Save harvest
      </button>
    </form>
  </div>

  <!-- Harvest count summary -->
  <% unless @harvests.empty? %>
    <p class="text-sm mt-3" style="color: var(--text-secondary);">
      <%= @harvests.count %> harvest<%= @harvests.count == 1 ? "" : "s" %> logged
    </p>
  <% end %>
</div>

<!-- Timeline Card (stage transitions + harvests merged) -->
<div class="px-4 py-4" style="background: white; border-radius: var(--card-radius); box-shadow: var(--card-shadow);">
  <p style="font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; font-weight: 600; color: var(--gray-500);" class="mb-3">
    Timeline
  </p>
  <% if timeline.empty? %>
    <p class="text-sm" style="color: var(--text-secondary);">No history yet.</p>
  <% else %>
    <ol class="relative" style="border-left: 2px solid #86efac; margin-left: 8px; padding-left: 0;">
      <% timeline.each do |entry| %>
        <% is_harvest = entry[:type] == :harvest %>
        <li class="relative pb-4 last:pb-0" style="padding-left: 20px;">
          <!-- Circle dot: green for stage, amber for harvest -->
          <div class="absolute rounded-full"
               style="width: 10px; height: 10px;
                      background: <%= is_harvest ? '#d97706' : '#16a34a' %>;
                      border: 2px solid white;
                      left: -6px; top: 4px;
                      box-shadow: 0 0 0 1px <%= is_harvest ? '#d97706' : '#16a34a' %>;">
          </div>

          <% if is_harvest %>
            <% h = entry[:entry] %>
            <p class="text-sm font-semibold" style="color: var(--text-primary);">
              Harvested &mdash; <%= h.quantity.capitalize %>
            </p>
            <p class="text-xs mt-0.5" style="color: var(--text-secondary);">
              <%= h.date.strftime("%b %-d, %Y") %>
            </p>
            <% if h.notes %>
              <p class="text-xs mt-1" style="color: var(--text-body);">
                <%= h.notes %>
              </p>
            <% end %>
          <% else %>
            <% h = entry[:entry] %>
            <p class="text-sm font-semibold" style="color: var(--text-primary);">
              <%= h.to_stage.tr('_', ' ').capitalize %>
            </p>
            <p class="text-xs mt-0.5" style="color: var(--text-secondary);">
              <%= h.changed_at.strftime("%b %-d, %Y %H:%M") %>
            </p>
            <% if h.note %>
              <p class="text-xs mt-1" style="color: var(--text-body);">
                <%= h.note %>
              </p>
            <% end %>
          <% end %>
        </li>
      <% end %>
    </ol>
  <% end %>
</div>

</div><%# end x-data wrapper %>
```

### 3.2 Verify the view renders

- [ ] Run the full test suite to confirm nothing regressed:

```bash
rm -f db/garden_os_test.db && bundle exec ruby -Itest test/routes/test_plants.rb
```

Expected: all tests pass, 0 failures.

- [ ] Optional manual smoke test:

```bash
bundle exec ruby app.rb
# Open http://localhost:4567/plants/<id> in browser
# Tap "Log harvest" — form should expand
# Select a quantity, add a note, save — should redirect and show harvest in timeline
```

### 3.3 Commit

```bash
git add views/plants/show.erb
git commit -m "feat: add Log Harvest inline form and harvest timeline to plant detail view"
```

---

## Task 4 — AI Context

### 4.1 Update `services/ai_advisory_service.rb`

- [ ] Add `require_relative "../models/harvest"` at the top of the file alongside the existing requires.

- [ ] In `build_context`, replace the `plants` mapping block so it includes a `harvest_counts` hash per plant. The full updated method:

```ruby
def self.build_context
  plants = Plant.exclude(lifecycle_stage: "done").all.map do |p|
    harvest_rows = Harvest.where(plant_id: p.id).all
    harvest_counts = harvest_rows.group_by(&:quantity).transform_values(&:count)
    total_harvests = harvest_rows.count

    {
      variety_name:   p.variety_name,
      crop_type:      p.crop_type,
      stage:          p.lifecycle_stage,
      days_in_stage:  p.days_in_stage,
      sow_date:       p.sow_date&.to_s,
      total_harvests: total_harvests,
      harvest_counts: harvest_counts   # e.g. {"small"=>2, "large"=>1}
    }
  end

  tasks = Task.where(due_date: Date.today..(Date.today + 7))
              .exclude(status: "done").all.map do |t|
    { title: t.title, type: t.task_type, due: t.due_date.to_s }
  end

  weather = WeatherService.fetch_current rescue nil

  {
    date:           Date.today.to_s,
    plants:         plants,
    upcoming_tasks: tasks,
    weather:        weather,
    variety_data:   Varieties.all
  }
end
```

### 4.2 Add test to `test/services/test_ai_advisory_service.rb`

- [ ] Read the existing `test/services/test_ai_advisory_service.rb` first to understand its structure, then append a test that verifies `build_context` includes harvest data:

```ruby
def test_build_context_includes_harvest_counts
  plant = Plant.create(variety_name: "Marmande", crop_type: "tomato", lifecycle_stage: "producing")
  Harvest.create(plant_id: plant.id, date: Date.today, quantity: "large")
  Harvest.create(plant_id: plant.id, date: Date.today, quantity: "large")
  Harvest.create(plant_id: plant.id, date: Date.today, quantity: "small")

  context = AIAdvisoryService.build_context
  plant_ctx = context[:plants].find { |p| p[:variety_name] == "Marmande" }

  refute_nil plant_ctx
  assert_equal 3,              plant_ctx[:total_harvests]
  assert_equal 2,              plant_ctx[:harvest_counts]["large"]
  assert_equal 1,              plant_ctx[:harvest_counts]["small"]
end
```

### 4.3 Run tests and verify

- [ ] Run:

```bash
rm -f db/garden_os_test.db && bundle exec ruby -Itest test/services/test_ai_advisory_service.rb
```

Expected: all tests pass, 0 failures.

### 4.4 Commit

```bash
git add services/ai_advisory_service.rb test/services/test_ai_advisory_service.rb
git commit -m "feat: include harvest counts per plant in AI advisory context"
```

---

## Final Verification

- [ ] Run the complete test suite to confirm all tasks compose correctly:

```bash
rm -f db/garden_os_test.db && bundle exec rake test
```

Expected output: all test files pass, 0 failures, 0 errors.

- [ ] Confirm the migration sequence is intact:

```bash
bundle exec rake db:migrate
sqlite3 db/garden_os.db "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
```

Expected output includes `harvests` alongside all existing tables.
