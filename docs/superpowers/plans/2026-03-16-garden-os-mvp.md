# GardenOS MVP Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-user garden management web app with HA integration, daily AI advisories, and calendar sync.

**Architecture:** Ruby/Sinatra REST API backed by SQLite (Sequel ORM). Frontend is server-rendered HTML with Alpine.js for interactivity and Tailwind CSS for styling — no build step. Background jobs via rufus-scheduler. HACS custom integration (Python) exposes plant sensors, calendar entity, and binary sensors to Home Assistant.

**Tech Stack:** Ruby 3.x, Sinatra, Sequel, SQLite3, Alpine.js, Tailwind (CDN), rufus-scheduler, anthropic gem, HACS (Python)

**Spec:** `garden-app-spec.md`

---

## File Structure

```
garden-os/
├── Gemfile
├── Rakefile
├── config.ru
├── app.rb                          # Sinatra app entry point + route mounting
├── config/
│   └── database.rb                 # Sequel DB connection
├── db/
│   ├── migrations/
│   │   ├── 001_create_beds.rb
│   │   ├── 002_create_plants.rb
│   │   ├── 003_create_tasks.rb
│   │   ├── 004_create_succession_plans.rb
│   │   ├── 005_create_advisories.rb
│   │   └── 006_create_stage_history.rb
│   └── seeds/
│       ├── varieties.json          # Built-in crop metadata
│       └── seed_varieties.rb       # Seed script for varieties
├── models/
│   ├── bed.rb
│   ├── plant.rb
│   ├── task.rb
│   ├── succession_plan.rb
│   ├── advisory.rb
│   └── stage_history.rb
├── .gitignore
├── routes/
│   ├── dashboard.rb
│   ├── plants.rb
│   ├── beds.rb
│   ├── tasks.rb
│   └── succession.rb
├── services/
│   ├── weather_service.rb          # HA weather entity polling
│   ├── notification_service.rb     # HA push notifications
│   ├── ai_advisory_service.rb      # Claude API daily call
│   ├── task_generator.rb           # Auto-generate tasks from plant data
│   └── scheduler.rb                # rufus-scheduler job definitions
├── views/
│   ├── layout.erb
│   ├── dashboard.erb
│   ├── plants/
│   │   ├── index.erb
│   │   └── show.erb
│   ├── beds/
│   │   ├── index.erb
│   │   └── show.erb
│   └── succession.erb
├── public/
│   ├── manifest.json               # PWA manifest
│   └── sw.js                       # Service worker (basic offline)
├── test/
│   ├── test_helper.rb
│   ├── models/
│   │   ├── test_bed.rb
│   │   ├── test_plant.rb
│   │   ├── test_task.rb
│   │   └── test_succession_plan.rb
│   ├── routes/
│   │   ├── test_dashboard.rb
│   │   ├── test_plants.rb
│   │   └── test_api.rb
│   └── services/
│       ├── test_weather_service.rb
│       ├── test_notification_service.rb
│       ├── test_ai_advisory_service.rb
│       └── test_task_generator.rb
├── hacs/                           # HACS custom integration (Python)
│   └── custom_components/
│       └── garden_os/
│           ├── __init__.py
│           ├── manifest.json
│           ├── config_flow.py
│           ├── const.py
│           ├── sensor.py
│           ├── binary_sensor.py
│           ├── calendar.py
│           └── coordinator.py      # Data update coordinator
└── docs/
    └── superpowers/
        └── plans/
            └── 2026-03-16-garden-os-mvp.md
```

---

## Phase 1: Foundation (Tasks 1–4)

### Task 1: Project Scaffold

**Files:**
- Create: `Gemfile`
- Create: `config.ru`
- Create: `Rakefile`
- Create: `app.rb`
- Create: `config/database.rb`
- Create: `test/test_helper.rb`

- [ ] **Step 1: Create Gemfile**

```ruby
# Gemfile
source "https://rubygems.org"

gem "sinatra", "~> 4.0"
gem "sinatra-contrib", "~> 4.0"
gem "puma", "~> 6.0"
gem "sequel", "~> 5.0"
gem "sqlite3", "~> 2.0"
gem "rufus-scheduler", "~> 3.9"
gem "anthropic", "~> 0.3"
gem "httpx", "~> 1.0"
gem "rake", "~> 13.0"

group :test do
  gem "minitest", "~> 5.0"
  gem "rack-test", "~> 2.0"
end
```

- [ ] **Step 2: Run bundle install**

Run: `bundle install`
Expected: Gemfile.lock created, all gems installed.

- [ ] **Step 3: Create config/database.rb**

```ruby
# config/database.rb
require "sequel"

DB = Sequel.connect(
  ENV.fetch("DATABASE_URL", "sqlite://db/garden_os.db")
)

Sequel.extension :migration
```

- [ ] **Step 4: Create app.rb (minimal Sinatra app)**

```ruby
# app.rb
require "sinatra/base"
require "sinatra/json"
require_relative "config/database"

class GardenApp < Sinatra::Base
  helpers Sinatra::JSON

  configure do
    set :views, File.join(File.dirname(__FILE__), "views")
    set :public_folder, File.join(File.dirname(__FILE__), "public")
  end

  get "/health" do
    json status: "ok"
  end
end
```

- [ ] **Step 5: Create config.ru**

```ruby
# config.ru
require_relative "app"

run GardenApp
```

- [ ] **Step 6: Create Rakefile**

```ruby
# Rakefile
require_relative "config/database"

namespace :db do
  desc "Run migrations"
  task :migrate do
    Sequel::Migrator.run(DB, "db/migrations")
    puts "Migrations complete."
  end

  desc "Rollback last migration"
  task :rollback do
    Sequel::Migrator.run(DB, "db/migrations", target: 0)
    puts "Rollback complete."
  end

  desc "Seed variety data"
  task :seed do
    require_relative "db/seeds/seed_varieties"
    puts "Seed data loaded."
  end
end
```

- [ ] **Step 7: Create test/test_helper.rb**

```ruby
# test/test_helper.rb
ENV["RACK_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite://db/garden_os_test.db"

require "minitest/autorun"
require "rack/test"
require_relative "../config/database"

Sequel::Migrator.run(DB, "db/migrations")

class GardenTest < Minitest::Test
  include Rack::Test::Methods

  def app
    GardenApp
  end

  def setup
    # Clean all tables before each test
    DB.tables.each { |t| DB[t].delete unless t == :schema_migrations }
  end
end
```

- [ ] **Step 8: Write a smoke test**

```ruby
# test/routes/test_health.rb
require_relative "../test_helper"
require_relative "../../app"

class TestHealth < GardenTest
  def test_health_endpoint
    get "/health"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "ok"
  end
end
```

- [ ] **Step 9: Run smoke test**

Run: `ruby test/routes/test_health.rb`
Expected: 1 test, 0 failures.

- [ ] **Step 10: Create .gitignore**

```gitignore
# .gitignore
db/*.db
.env
vendor/bundle
.bundle
```

- [ ] **Step 11: Commit**

```bash
git add Gemfile Gemfile.lock config.ru Rakefile app.rb config/ test/ .gitignore
git commit -m "feat: project scaffold with Sinatra, Sequel, test harness"
```

---

### Task 2: Database Migrations

**Files:**
- Create: `db/migrations/001_create_beds.rb`
- Create: `db/migrations/002_create_plants.rb`
- Create: `db/migrations/003_create_tasks.rb`
- Create: `db/migrations/004_create_succession_plans.rb`
- Create: `db/migrations/005_create_advisories.rb`
- Create: `db/migrations/006_create_stage_history.rb`

- [ ] **Step 1: Create 001_create_beds.rb**

```ruby
# db/migrations/001_create_beds.rb
Sequel.migration do
  change do
    create_table(:beds) do
      primary_key :id
      String :name, null: false, unique: true   # BB1, BB2, Corner, etc.
      String :bed_type, default: "raised"       # raised, arch, indoor
      Float :length
      Float :width
      String :orientation                        # N-S, E-W
      String :wall_type                          # stone, wood
      String :notes
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:rows) do
      primary_key :id
      foreign_key :bed_id, :beds, null: false, on_delete: :cascade
      String :name, null: false                  # Row A, Row B
      Integer :position                          # ordering within bed
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:slots) do
      primary_key :id
      foreign_key :row_id, :rows, null: false, on_delete: :cascade
      String :name, null: false                  # named positions
      Integer :position
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:arches) do
      primary_key :id
      String :name, null: false, unique: true    # A1, A2, A3, A4
      String :between_beds                       # "BB1-BB2"
      Float :gap_width
      String :spring_crop
      String :summer_crop
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:indoor_stations) do
      primary_key :id
      String :name, null: false, unique: true    # Heat mat, Grow light shelf
      String :station_type                       # heat_mat, grow_light, windowsill
      Float :target_temp
      String :notes
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
```

- [ ] **Step 2: Create 002_create_plants.rb**

```ruby
# db/migrations/002_create_plants.rb
Sequel.migration do
  change do
    create_table(:plants) do
      primary_key :id
      String :variety_name, null: false          # "Raf", "Mini Bell Trio"
      String :crop_type, null: false             # tomato, pepper, herb, flower
      String :source                             # seed company name
      foreign_key :slot_id, :slots, on_delete: :set_null
      foreign_key :indoor_station_id, :indoor_stations, on_delete: :set_null
      String :lifecycle_stage, null: false, default: "seed_packet"
      Date :sow_date
      Date :germination_date
      Date :transplant_date
      Integer :succession_group_id               # links sibling sowings
      String :notes                              # latest freeform note
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :lifecycle_stage
      index :crop_type
    end
  end
end
```

- [ ] **Step 3: Create 003_create_tasks.rb**

```ruby
# db/migrations/003_create_tasks.rb
Sequel.migration do
  change do
    create_table(:tasks) do
      primary_key :id
      String :title, null: false
      String :task_type, null: false             # sow, transplant, feed, water, harvest, etc.
      Date :due_date
      String :conditions                         # JSON string for weather gates
      String :priority, default: "should"        # must, should, could
      String :status, default: "upcoming"        # upcoming, ready, done, skipped, deferred
      String :recurrence                         # for succession sowings
      String :notes
      DateTime :completed_at
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :status
      index :due_date
    end

    create_table(:tasks_plants) do
      foreign_key :task_id, :tasks, on_delete: :cascade
      foreign_key :plant_id, :plants, on_delete: :cascade
      primary_key [:task_id, :plant_id]
    end

    create_table(:tasks_beds) do
      foreign_key :task_id, :tasks, on_delete: :cascade
      foreign_key :bed_id, :beds, on_delete: :cascade
      primary_key [:task_id, :bed_id]
    end
  end
end
```

- [ ] **Step 4: Create 004_create_succession_plans.rb**

```ruby
# db/migrations/004_create_succession_plans.rb
Sequel.migration do
  change do
    create_table(:succession_plans) do
      primary_key :id
      String :crop, null: false                  # "Lettuce", "Radish"
      String :varieties                          # JSON array of variety names
      Integer :interval_days, null: false        # days between sowings
      Date :season_start
      Date :season_end
      String :target_beds                        # JSON array of bed names
      Integer :total_planned_sowings
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
```

- [ ] **Step 5: Create 005_create_advisories.rb**

```ruby
# db/migrations/005_create_advisories.rb
Sequel.migration do
  change do
    create_table(:advisories) do
      primary_key :id
      Date :date, null: false
      String :advisory_type                      # general, plant_specific, weather
      String :content, text: true, null: false   # JSON from Claude API
      Integer :plant_id                          # optional link to specific plant
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index :date
    end
  end
end
```

- [ ] **Step 6: Create 006_create_stage_history.rb**

```ruby
# db/migrations/006_create_stage_history.rb
Sequel.migration do
  change do
    create_table(:stage_histories) do
      primary_key :id
      foreign_key :plant_id, :plants, null: false, on_delete: :cascade
      String :from_stage
      String :to_stage, null: false
      String :note
      DateTime :changed_at, default: Sequel::CURRENT_TIMESTAMP

      index :plant_id
    end
  end
end
```

- [ ] **Step 7: Run migrations**

Run: `rake db:migrate`
Expected: All 6 migrations applied. `db/garden_os.db` created with all tables.

- [ ] **Step 8: Commit**

```bash
git add db/migrations/
git commit -m "feat: database schema — beds, plants, tasks, successions, advisories, stage history"
```

---

### Task 3: Sequel Models

**Files:**
- Create: `models/bed.rb`
- Create: `models/plant.rb`
- Create: `models/task.rb`
- Create: `models/succession_plan.rb`
- Create: `models/advisory.rb`
- Create: `models/stage_history.rb`
- Create: `test/models/test_plant.rb`

- [ ] **Step 1: Write failing test for Plant model stage transitions**

```ruby
# test/models/test_plant.rb
require_relative "../test_helper"
require_relative "../../models/plant"
require_relative "../../models/stage_history"
require_relative "../../models/bed"

class TestPlant < GardenTest
  VALID_STAGES = %w[
    seed_packet pre_treating sown_indoor germinating seedling
    potted_up hardening_off planted_out producing done stratifying
  ].freeze

  def test_advance_stage
    plant = Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seed_packet")
    plant.advance_stage!("sown_indoor")

    assert_equal "sown_indoor", plant.reload.lifecycle_stage
    history = StageHistory.where(plant_id: plant.id).first
    assert_equal "seed_packet", history.from_stage
    assert_equal "sown_indoor", history.to_stage
  end

  def test_advance_stage_rejects_invalid
    plant = Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seed_packet")
    assert_raises(ArgumentError) { plant.advance_stage!("bogus") }
  end

  def test_days_in_stage
    plant = Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "germinating")
    StageHistory.create(plant_id: plant.id, to_stage: "germinating",
                        changed_at: Time.now - (5 * 86400))
    assert_equal 5, plant.days_in_stage
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby test/models/test_plant.rb`
Expected: FAIL — models not yet defined.

- [ ] **Step 3: Create all models**

```ruby
# models/bed.rb
require_relative "../config/database"

class Bed < Sequel::Model
  one_to_many :rows
end

class Row < Sequel::Model
  many_to_one :bed
  one_to_many :slots
end

class Slot < Sequel::Model
  many_to_one :row
  one_to_many :plants
end

class Arch < Sequel::Model; end

class IndoorStation < Sequel::Model; end
```

```ruby
# models/plant.rb
require_relative "../config/database"
require_relative "stage_history"

class Plant < Sequel::Model
  many_to_one :slot
  many_to_one :indoor_station
  one_to_many :stage_histories
  many_to_many :tasks

  LIFECYCLE_STAGES = %w[
    seed_packet pre_treating sown_indoor germinating seedling
    potted_up hardening_off planted_out producing done stratifying
  ].freeze

  def advance_stage!(new_stage, note: nil)
    raise ArgumentError, "Invalid stage: #{new_stage}" unless LIFECYCLE_STAGES.include?(new_stage)

    old_stage = lifecycle_stage
    DB.transaction do
      update(lifecycle_stage: new_stage, updated_at: Time.now)
      # Auto-set dates based on stage
      update(sow_date: Date.today) if new_stage == "sown_indoor" && sow_date.nil?
      update(germination_date: Date.today) if new_stage == "germinating" && germination_date.nil?
      update(transplant_date: Date.today) if new_stage == "planted_out" && transplant_date.nil?

      StageHistory.create(
        plant_id: id,
        from_stage: old_stage,
        to_stage: new_stage,
        note: note,
        changed_at: Time.now
      )
    end
    self
  end

  def days_in_stage
    last_change = StageHistory.where(plant_id: id, to_stage: lifecycle_stage)
                              .order(Sequel.desc(:changed_at)).first
    return 0 unless last_change

    ((Time.now - last_change.changed_at) / 86400).to_i
  end
end
```

```ruby
# models/task.rb
require_relative "../config/database"

class Task < Sequel::Model
  many_to_many :plants, join_table: :tasks_plants
  many_to_many :beds, join_table: :tasks_beds

  TYPES = %w[sow transplant feed water harvest build prep check order].freeze
  PRIORITIES = %w[must should could].freeze
  STATUSES = %w[upcoming ready done skipped deferred].freeze

  def complete!
    update(status: "done", completed_at: Time.now, updated_at: Time.now)
  end

  def conditions_hash
    conditions ? JSON.parse(conditions) : {}
  end
end
```

```ruby
# models/succession_plan.rb
require_relative "../config/database"

class SuccessionPlan < Sequel::Model
  def varieties_list
    varieties ? JSON.parse(varieties) : []
  end

  def target_beds_list
    target_beds ? JSON.parse(target_beds) : []
  end

  def next_sowing_date(completed_sowings_count)
    return nil unless season_start
    season_start + (interval_days * completed_sowings_count)
  end
end
```

```ruby
# models/advisory.rb
require_relative "../config/database"

class Advisory < Sequel::Model
  many_to_one :plant

  def content_hash
    JSON.parse(content)
  end
end
```

```ruby
# models/stage_history.rb
require_relative "../config/database"

class StageHistory < Sequel::Model
  many_to_one :plant
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby test/models/test_plant.rb`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add models/ test/models/
git commit -m "feat: Sequel models with plant stage transitions and history tracking"
```

---

### Task 4: Variety Seed Data

**Files:**
- Create: `db/seeds/varieties.json`
- Create: `db/seeds/seed_varieties.rb`

- [ ] **Step 1: Create varieties.json**

```json
{
  "tomato": {
    "sow_indoor_weeks_before_last_frost": 8,
    "germination_temp_min": 20,
    "germination_temp_ideal": 25,
    "germination_days_min": 5,
    "germination_days_max": 14,
    "days_to_maturity_min": 60,
    "days_to_maturity_max": 90,
    "frost_tender": true,
    "feed_from": "first_truss"
  },
  "pepper": {
    "sow_indoor_weeks_before_last_frost": 10,
    "germination_temp_min": 25,
    "germination_temp_ideal": 30,
    "germination_days_min": 7,
    "germination_days_max": 21,
    "days_to_maturity_min": 70,
    "days_to_maturity_max": 100,
    "frost_tender": true
  },
  "cucumber": {
    "sow_indoor_weeks_before_last_frost": 4,
    "germination_temp_min": 20,
    "germination_temp_ideal": 25,
    "germination_days_min": 3,
    "germination_days_max": 10,
    "days_to_maturity_min": 50,
    "days_to_maturity_max": 70,
    "frost_tender": true
  },
  "lettuce": {
    "sow_indoor_weeks_before_last_frost": 6,
    "germination_temp_min": 10,
    "germination_temp_ideal": 15,
    "germination_days_min": 3,
    "germination_days_max": 10,
    "days_to_maturity_min": 30,
    "days_to_maturity_max": 60,
    "frost_tender": false
  },
  "radish": {
    "direct_sow": true,
    "germination_temp_min": 7,
    "germination_temp_ideal": 15,
    "germination_days_min": 3,
    "germination_days_max": 7,
    "days_to_maturity_min": 25,
    "days_to_maturity_max": 35,
    "frost_tender": false
  },
  "herb": {
    "sow_indoor_weeks_before_last_frost": 8,
    "germination_temp_min": 15,
    "germination_temp_ideal": 20,
    "germination_days_min": 7,
    "germination_days_max": 21,
    "days_to_maturity_min": 60,
    "days_to_maturity_max": 90,
    "frost_tender": false
  },
  "flower": {
    "sow_indoor_weeks_before_last_frost": 6,
    "germination_temp_min": 15,
    "germination_temp_ideal": 20,
    "germination_days_min": 5,
    "germination_days_max": 14,
    "days_to_maturity_min": 60,
    "days_to_maturity_max": 90,
    "frost_tender": false
  },
  "pea": {
    "direct_sow": true,
    "germination_temp_min": 5,
    "germination_temp_ideal": 12,
    "germination_days_min": 7,
    "germination_days_max": 14,
    "days_to_maturity_min": 60,
    "days_to_maturity_max": 80,
    "frost_tender": false,
    "soil_temp_min": 5
  },
  "bean": {
    "direct_sow": true,
    "germination_temp_min": 15,
    "germination_temp_ideal": 20,
    "germination_days_min": 5,
    "germination_days_max": 10,
    "days_to_maturity_min": 50,
    "days_to_maturity_max": 70,
    "frost_tender": true
  }
}
```

- [ ] **Step 2: Create seed_varieties.rb**

```ruby
# db/seeds/seed_varieties.rb
require "json"

# Varieties are loaded from JSON and used as a lookup hash at runtime.
# No DB table needed — this is reference data baked into the app.
module Varieties
  DATA_PATH = File.join(File.dirname(__FILE__), "varieties.json")

  def self.all
    @all ||= JSON.parse(File.read(DATA_PATH))
  end

  def self.for(crop_type)
    all[crop_type.to_s.downcase]
  end

  # Prague climate defaults
  LAST_FROST_DATE = Date.new(Date.today.year, 5, 13)
  FIRST_FROST_DATE = Date.new(Date.today.year, 10, 15)
end
```

- [ ] **Step 3: Commit**

```bash
git add db/seeds/
git commit -m "feat: variety seed data with Prague climate defaults"
```

---

## Phase 2: API Routes (Tasks 5–8)

### Task 5: Dashboard Route

**Files:**
- Create: `routes/dashboard.rb`
- Create: `views/layout.erb`
- Create: `views/dashboard.erb`
- Modify: `app.rb` — register route file
- Create: `test/routes/test_dashboard.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/routes/test_dashboard.rb
require_relative "../test_helper"
require_relative "../../app"

class TestDashboard < GardenTest
  def test_dashboard_renders
    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "GardenOS"
  end

  def test_dashboard_shows_todays_tasks
    Task.create(title: "Sow lettuce", task_type: "sow",
                due_date: Date.today, status: "upcoming")
    get "/"
    assert_includes last_response.body, "Sow lettuce"
  end

  def test_dashboard_shows_germination_watch
    station = IndoorStation.create(name: "Heat mat", station_type: "heat_mat")
    plant = Plant.create(variety_name: "Raf", crop_type: "tomato",
                         lifecycle_stage: "germinating",
                         indoor_station_id: station.id,
                         sow_date: Date.today - 5)
    StageHistory.create(plant_id: plant.id, to_stage: "germinating",
                        changed_at: Time.now - (5 * 86400))
    get "/"
    assert_includes last_response.body, "Raf"
  end
end
```

- [ ] **Step 2: Run test — expect failure**

Run: `ruby test/routes/test_dashboard.rb`
Expected: FAIL — routes not defined.

- [ ] **Step 3: Create layout.erb**

```erb
<!-- views/layout.erb -->
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>GardenOS</title>
  <link rel="manifest" href="/manifest.json">
  <meta name="theme-color" content="#16a34a">
  <script src="https://cdn.tailwindcss.com"></script>
  <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
</head>
<body class="bg-stone-50 text-stone-900 min-h-screen">
  <nav class="bg-green-700 text-white px-4 py-3 flex items-center justify-between">
    <a href="/" class="text-lg font-bold">GardenOS</a>
    <div class="flex gap-4 text-sm">
      <a href="/" class="hover:underline">Dashboard</a>
      <a href="/plants" class="hover:underline">Plants</a>
      <a href="/beds" class="hover:underline">Beds</a>
      <a href="/succession" class="hover:underline">Succession</a>
    </div>
  </nav>
  <main class="max-w-4xl mx-auto px-4 py-6">
    <%= yield %>
  </main>
</body>
</html>
```

- [ ] **Step 4: Create dashboard route**

```ruby
# routes/dashboard.rb
require_relative "../models/task"
require_relative "../models/plant"
require_relative "../models/bed"
require_relative "../models/advisory"
require_relative "../models/stage_history"
require_relative "../services/weather_service"

class GardenApp
  get "/" do
    @today_tasks = Task.where(due_date: Date.today)
                       .exclude(status: "done")
                       .order(:priority).all

    @upcoming_tasks = Task.where(due_date: (Date.today + 1)..(Date.today + 7))
                          .exclude(status: "done")
                          .order(:due_date).all

    @germination_watch = Plant.where(lifecycle_stage: %w[germinating sown_indoor])
                              .all

    @advisories = Advisory.where(date: Date.today).all

    @weather = WeatherService.fetch_current

    erb :dashboard
  end
end
```

- [ ] **Step 5: Create dashboard.erb**

```erb
<!-- views/dashboard.erb -->
<h1 class="text-2xl font-bold mb-6">Good morning</h1>

<!-- Weather strip -->
<% if @weather %>
  <div class="bg-blue-50 rounded-lg p-4 mb-6">
    <div class="flex items-center justify-between">
      <div>
        <p class="font-medium text-blue-900">Now: <%= @weather[:current_temp] %>&deg;C — <%= @weather[:condition] %></p>
      </div>
    </div>
    <% if @weather[:forecast]&.any? %>
      <div class="flex gap-4 mt-2">
        <% @weather[:forecast].each do |day| %>
          <div class="text-xs text-blue-700">
            <p><%= day[:date] %></p>
            <p><%= day[:high] %>&deg; / <%= day[:low] %>&deg;</p>
            <p><%= day[:condition] %></p>
          </div>
        <% end %>
      </div>
    <% end %>
  </div>
<% else %>
  <div class="bg-blue-50 rounded-lg p-4 mb-6">
    <p class="text-sm text-blue-600">Weather data unavailable — check HA connection.</p>
  </div>
<% end %>

<!-- Frost alert (shown when frost risk detected) -->
<% if @weather&.dig(:frost_risk) %>
  <div class="bg-red-100 border border-red-300 rounded-lg p-4 mb-6">
    <p class="font-bold text-red-700">Frost warning</p>
    <% min_low = @weather[:forecast]&.map { |f| f[:low] }&.compact&.min %>
    <p class="text-sm text-red-600">Low of <%= min_low %>&deg;C forecast in next 3 days.</p>
  </div>
<% end %>

<!-- Today's tasks -->
<section class="mb-6">
  <h2 class="text-lg font-semibold mb-3">Today's tasks</h2>
  <% if @today_tasks.empty? %>
    <p class="text-stone-500">Nothing scheduled today.</p>
  <% else %>
    <ul class="space-y-2">
      <% @today_tasks.each do |task| %>
        <li class="bg-white rounded-lg p-3 shadow-sm flex items-center justify-between"
            x-data="{ done: false }">
          <div>
            <span class="font-medium"><%= task.title %></span>
            <span class="ml-2 text-xs px-2 py-0.5 rounded-full
              <%= task.priority == 'must' ? 'bg-red-100 text-red-700' :
                  task.priority == 'should' ? 'bg-yellow-100 text-yellow-700' :
                  'bg-stone-100 text-stone-600' %>">
              <%= task.priority %>
            </span>
          </div>
          <button @click="done = true; fetch('/tasks/<%= task.id %>/complete', {method: 'POST'})"
                  x-show="!done"
                  class="text-sm bg-green-600 text-white px-3 py-1 rounded hover:bg-green-700">
            Done
          </button>
          <span x-show="done" class="text-green-600 text-sm">Completed</span>
        </li>
      <% end %>
    </ul>
  <% end %>
</section>

<!-- Germination watch -->
<section class="mb-6">
  <h2 class="text-lg font-semibold mb-3">Germination watch</h2>
  <% if @germination_watch.empty? %>
    <p class="text-stone-500">Nothing germinating right now.</p>
  <% else %>
    <div class="grid grid-cols-2 gap-3">
      <% @germination_watch.each do |plant| %>
        <div class="bg-amber-50 rounded-lg p-3 border border-amber-200">
          <p class="font-medium"><%= plant.variety_name %></p>
          <p class="text-sm text-stone-600"><%= plant.crop_type %></p>
          <p class="text-sm">
            Day <strong><%= plant.days_in_stage %></strong> —
            <span class="text-amber-700"><%= plant.lifecycle_stage.tr('_', ' ') %></span>
          </p>
        </div>
      <% end %>
    </div>
  <% end %>
</section>

<!-- Upcoming this week -->
<section class="mb-6">
  <h2 class="text-lg font-semibold mb-3">Upcoming this week</h2>
  <% if @upcoming_tasks.empty? %>
    <p class="text-stone-500">Clear week ahead.</p>
  <% else %>
    <ul class="space-y-2">
      <% @upcoming_tasks.each do |task| %>
        <li class="bg-white rounded-lg p-3 shadow-sm">
          <span class="text-sm text-stone-500"><%= task.due_date.strftime("%a %b %-d") %></span>
          <span class="ml-2 font-medium"><%= task.title %></span>
        </li>
      <% end %>
    </ul>
  <% end %>
</section>

<!-- AI Insights -->
<section class="mb-6">
  <h2 class="text-lg font-semibold mb-3">AI insights</h2>
  <% if @advisories.empty? %>
    <p class="text-stone-500">No advisories today yet.</p>
  <% else %>
    <div class="space-y-2">
      <% @advisories.each do |adv| %>
        <div class="bg-purple-50 rounded-lg p-3 border border-purple-200">
          <p class="text-sm"><%= adv.content_hash["summary"] rescue adv.content %></p>
        </div>
      <% end %>
    </div>
  <% end %>
</section>
```

- [ ] **Step 6: Update app.rb to require routes and models**

```ruby
# app.rb
require "sinatra/base"
require "sinatra/json"
require_relative "config/database"

class GardenApp < Sinatra::Base
  helpers Sinatra::JSON

  configure do
    set :views, File.join(File.dirname(__FILE__), "views")
    set :public_folder, File.join(File.dirname(__FILE__), "public")
  end

  get "/health" do
    json status: "ok"
  end
end

require_relative "routes/dashboard"
```

- [ ] **Step 7: Run tests**

Run: `ruby test/routes/test_dashboard.rb`
Expected: 3 tests, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add routes/dashboard.rb views/ app.rb test/routes/test_dashboard.rb
git commit -m "feat: dashboard route with tasks, germination watch, AI insights"
```

---

### Task 6: Plants Routes (CRUD + Stage Transitions)

**Files:**
- Create: `routes/plants.rb`
- Create: `views/plants/index.erb`
- Create: `views/plants/show.erb`
- Modify: `app.rb` — require plants route
- Create: `test/routes/test_plants.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/routes/test_plants.rb
require_relative "../test_helper"
require_relative "../../app"

class TestPlants < GardenTest
  def test_plants_index
    Plant.create(variety_name: "Raf", crop_type: "tomato")
    get "/plants"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Raf"
  end

  def test_plants_show
    plant = Plant.create(variety_name: "Raf", crop_type: "tomato")
    get "/plants/#{plant.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Raf"
  end

  def test_advance_stage
    plant = Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "seed_packet")
    post "/plants/#{plant.id}/advance", stage: "sown_indoor"
    assert_equal 302, last_response.status
    assert_equal "sown_indoor", plant.reload.lifecycle_stage
  end

  def test_batch_advance
    p1 = Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "germinating")
    p2 = Plant.create(variety_name: "Roma", crop_type: "tomato", lifecycle_stage: "germinating")
    post "/plants/batch_advance", plant_ids: [p1.id, p2.id].join(","), stage: "seedling"
    assert_equal 302, last_response.status
    assert_equal "seedling", p1.reload.lifecycle_stage
    assert_equal "seedling", p2.reload.lifecycle_stage
  end

  def test_create_plant_json
    post "/api/plants", { variety_name: "Test", crop_type: "tomato" }.to_json,
         "CONTENT_TYPE" => "application/json"
    assert_equal 201, last_response.status
    assert_equal 1, Plant.count
  end
end
```

- [ ] **Step 2: Run test — expect failure**

Run: `ruby test/routes/test_plants.rb`

- [ ] **Step 3: Create plants route**

```ruby
# routes/plants.rb
require_relative "../models/plant"
require_relative "../models/bed"
require_relative "../models/stage_history"

class GardenApp
  get "/plants" do
    @plants = Plant.exclude(lifecycle_stage: "done").order(:crop_type, :variety_name).all
    @done_plants = Plant.where(lifecycle_stage: "done").all
    erb :"plants/index"
  end

  get "/plants/:id" do
    @plant = Plant[params[:id].to_i]
    halt 404, "Plant not found" unless @plant
    @history = StageHistory.where(plant_id: @plant.id).order(:changed_at).all
    erb :"plants/show"
  end

  post "/plants/:id/advance" do
    plant = Plant[params[:id].to_i]
    halt 404 unless plant
    plant.advance_stage!(params[:stage], note: params[:note])
    redirect back
  end

  post "/plants/batch_advance" do
    ids = params[:plant_ids].split(",").map(&:to_i)
    Plant.where(id: ids).all.each do |plant|
      plant.advance_stage!(params[:stage], note: params[:note])
    end
    redirect back
  end

  # JSON API
  post "/api/plants" do
    data = JSON.parse(request.body.read)
    plant = Plant.create(
      variety_name: data["variety_name"],
      crop_type: data["crop_type"],
      source: data["source"],
      lifecycle_stage: data.fetch("lifecycle_stage", "seed_packet")
    )
    status 201
    json plant.values
  end

  get "/api/plants" do
    json Plant.exclude(lifecycle_stage: "done").all.map(&:values)
  end

  get "/api/plants/:id" do
    plant = Plant[params[:id].to_i]
    halt 404 unless plant
    json plant.values.merge(
      days_in_stage: plant.days_in_stage,
      history: plant.stage_histories.map(&:values)
    )
  end
end
```

- [ ] **Step 4: Create plants/index.erb**

```erb
<!-- views/plants/index.erb -->
<div class="flex items-center justify-between mb-6">
  <h1 class="text-2xl font-bold">Plants</h1>
</div>

<!-- Batch actions -->
<div x-data="{ selected: [], batchStage: '' }" class="mb-4">
  <form method="post" action="/plants/batch_advance" x-show="selected.length > 0"
        class="bg-green-50 rounded-lg p-3 flex items-center gap-3">
    <input type="hidden" name="plant_ids" :value="selected.join(',')">
    <span class="text-sm" x-text="selected.length + ' selected'"></span>
    <select name="stage" x-model="batchStage" class="text-sm border rounded px-2 py-1">
      <option value="">Advance to...</option>
      <% Plant::LIFECYCLE_STAGES.each do |stage| %>
        <option value="<%= stage %>"><%= stage.tr('_', ' ').capitalize %></option>
      <% end %>
    </select>
    <button type="submit" :disabled="!batchStage"
            class="text-sm bg-green-600 text-white px-3 py-1 rounded disabled:opacity-50">
      Apply
    </button>
  </form>

  <!-- Group by crop type -->
  <% @plants.group_by(&:crop_type).sort.each do |crop, plants| %>
    <h2 class="text-lg font-semibold mt-6 mb-3 capitalize"><%= crop %></h2>
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
      <% plants.each do |plant| %>
        <div class="bg-white rounded-lg p-3 shadow-sm flex items-center gap-3">
          <input type="checkbox" :value="<%= plant.id %>"
                 @change="$event.target.checked ? selected.push(<%= plant.id %>) : selected = selected.filter(x => x !== <%= plant.id %>)">
          <a href="/plants/<%= plant.id %>" class="flex-1">
            <p class="font-medium"><%= plant.variety_name %></p>
            <p class="text-sm text-stone-500"><%= plant.lifecycle_stage.tr('_', ' ') %></p>
          </a>
          <!-- Quick advance button -->
          <% next_stages = Plant::LIFECYCLE_STAGES.drop(Plant::LIFECYCLE_STAGES.index(plant.lifecycle_stage).to_i + 1).first(2) %>
          <% next_stages.each do |ns| %>
            <form method="post" action="/plants/<%= plant.id %>/advance" class="inline">
              <input type="hidden" name="stage" value="<%= ns %>">
              <button class="text-xs bg-stone-100 hover:bg-stone-200 px-2 py-1 rounded">
                <%= ns.tr('_', ' ') %>
              </button>
            </form>
          <% end %>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 5: Create plants/show.erb**

```erb
<!-- views/plants/show.erb -->
<a href="/plants" class="text-sm text-green-700 hover:underline mb-4 inline-block">&larr; All plants</a>

<h1 class="text-2xl font-bold mb-1"><%= @plant.variety_name %></h1>
<p class="text-stone-500 capitalize mb-6"><%= @plant.crop_type %> — <%= @plant.lifecycle_stage.tr('_', ' ') %></p>

<!-- Stage advancement -->
<div class="bg-white rounded-lg p-4 shadow-sm mb-6">
  <h2 class="font-semibold mb-3">Advance stage</h2>
  <div class="flex flex-wrap gap-2">
    <% Plant::LIFECYCLE_STAGES.each do |stage| %>
      <% if stage == @plant.lifecycle_stage %>
        <span class="text-sm px-3 py-1 rounded-full bg-green-600 text-white"><%= stage.tr('_', ' ') %></span>
      <% else %>
        <form method="post" action="/plants/<%= @plant.id %>/advance" class="inline">
          <input type="hidden" name="stage" value="<%= stage %>">
          <button class="text-sm px-3 py-1 rounded-full bg-stone-100 hover:bg-stone-200">
            <%= stage.tr('_', ' ') %>
          </button>
        </form>
      <% end %>
    <% end %>
  </div>
</div>

<!-- Key dates -->
<div class="bg-white rounded-lg p-4 shadow-sm mb-6">
  <h2 class="font-semibold mb-3">Key dates</h2>
  <dl class="grid grid-cols-2 gap-2 text-sm">
    <dt class="text-stone-500">Sown</dt>
    <dd><%= @plant.sow_date || "—" %></dd>
    <dt class="text-stone-500">Germinated</dt>
    <dd><%= @plant.germination_date || "—" %></dd>
    <dt class="text-stone-500">Transplanted</dt>
    <dd><%= @plant.transplant_date || "—" %></dd>
    <dt class="text-stone-500">Days in stage</dt>
    <dd><%= @plant.days_in_stage %></dd>
  </dl>
</div>

<!-- Stage history timeline -->
<div class="bg-white rounded-lg p-4 shadow-sm mb-6">
  <h2 class="font-semibold mb-3">Timeline</h2>
  <% if @history.empty? %>
    <p class="text-stone-500 text-sm">No history yet.</p>
  <% else %>
    <ol class="border-l-2 border-green-300 ml-2 space-y-3">
      <% @history.each do |h| %>
        <li class="ml-4 relative">
          <div class="absolute -left-[1.35rem] top-1 w-3 h-3 rounded-full bg-green-500 border-2 border-white"></div>
          <p class="text-sm font-medium"><%= h.to_stage.tr('_', ' ').capitalize %></p>
          <p class="text-xs text-stone-500"><%= h.changed_at.strftime("%b %-d, %Y %H:%M") %></p>
          <% if h.note %>
            <p class="text-xs text-stone-600 mt-1"><%= h.note %></p>
          <% end %>
        </li>
      <% end %>
    </ol>
  <% end %>
</div>
```

- [ ] **Step 6: Add to app.rb**

Add `require_relative "routes/plants"` at the bottom of app.rb.

- [ ] **Step 7: Run tests**

Run: `ruby test/routes/test_plants.rb`
Expected: 5 tests, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add routes/plants.rb views/plants/ app.rb test/routes/test_plants.rb
git commit -m "feat: plant tracker with CRUD, stage transitions, batch operations"
```

---

### Task 7: Beds & Map Routes

**Files:**
- Create: `routes/beds.rb`
- Create: `views/beds/index.erb`
- Create: `views/beds/show.erb`
- Modify: `app.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/routes/test_beds.rb
require_relative "../test_helper"
require_relative "../../app"

class TestBeds < GardenTest
  def test_beds_index
    Bed.create(name: "BB1", bed_type: "raised")
    get "/beds"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "BB1"
  end

  def test_bed_show_with_plants
    bed = Bed.create(name: "BB1", bed_type: "raised")
    row = Row.create(bed_id: bed.id, name: "Row A", position: 1)
    slot = Slot.create(row_id: row.id, name: "Pos 1", position: 1)
    Plant.create(variety_name: "Raf", crop_type: "tomato", slot_id: slot.id)
    get "/beds/#{bed.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Raf"
  end

  def test_beds_api
    Bed.create(name: "BB1", bed_type: "raised")
    get "/api/beds"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 1, data.length
  end
end
```

- [ ] **Step 2: Run test — expect failure**

Run: `ruby test/routes/test_beds.rb`

- [ ] **Step 3: Create beds route**

```ruby
# routes/beds.rb
require_relative "../models/bed"
require_relative "../models/plant"

class GardenApp
  get "/beds" do
    @beds = Bed.all
    @arches = Arch.all
    @indoor_stations = IndoorStation.all
    # Eager-load rows→slots→plants to avoid N+1
    @bed_data = @beds.map do |bed|
      rows = Row.where(bed_id: bed.id).order(:position).all
      row_data = rows.map do |row|
        slots = Slot.where(row_id: row.id).order(:position).all
        slot_ids = slots.map(&:id)
        plants_by_slot = Plant.where(slot_id: slot_ids)
                              .exclude(lifecycle_stage: "done")
                              .all.group_by(&:slot_id)
        { row: row, slots: slots.map { |s| { slot: s, plant: plants_by_slot[s.id]&.first } } }
      end
      { bed: bed, rows: row_data }
    end
    erb :"beds/index"
  end

  get "/beds/:id" do
    @bed = Bed[params[:id].to_i]
    halt 404 unless @bed
    @rows = Row.where(bed_id: @bed.id).order(:position).all
    # Eager-load slots and plants for this bed
    row_ids = @rows.map(&:id)
    all_slots = Slot.where(row_id: row_ids).order(:position).all
    slot_ids = all_slots.map(&:id)
    @plants_by_slot = Plant.where(slot_id: slot_ids)
                           .exclude(lifecycle_stage: "done")
                           .all.group_by(&:slot_id)
    @slots_by_row = all_slots.group_by(&:row_id)
    erb :"beds/show"
  end

  get "/api/beds" do
    beds = Bed.all.map do |bed|
      rows = Row.where(bed_id: bed.id).order(:position).all.map do |row|
        slots = Slot.where(row_id: row.id).order(:position).all.map do |slot|
          plant = Plant.where(slot_id: slot.id).exclude(lifecycle_stage: "done").first
          slot.values.merge(plant: plant&.values)
        end
        row.values.merge(slots: slots)
      end
      bed.values.merge(rows: rows)
    end
    json beds
  end
end
```

- [ ] **Step 4: Create beds/index.erb (bed map)**

```erb
<!-- views/beds/index.erb -->
<h1 class="text-2xl font-bold mb-6">Garden Map</h1>

<!-- Color legend -->
<div class="flex flex-wrap gap-2 mb-4 text-xs">
  <span class="px-2 py-1 rounded bg-red-200 text-red-800">Tomato</span>
  <span class="px-2 py-1 rounded bg-orange-200 text-orange-800">Pepper</span>
  <span class="px-2 py-1 rounded bg-green-200 text-green-800">Cucumber</span>
  <span class="px-2 py-1 rounded bg-emerald-200 text-emerald-800">Herb</span>
  <span class="px-2 py-1 rounded bg-pink-200 text-pink-800">Flower</span>
  <span class="px-2 py-1 rounded bg-yellow-200 text-yellow-800">Lettuce</span>
  <span class="px-2 py-1 rounded bg-stone-200 text-stone-800">Empty</span>
</div>

<% crop_colors = {
  "tomato" => "bg-red-100 border-red-300",
  "pepper" => "bg-orange-100 border-orange-300",
  "cucumber" => "bg-green-100 border-green-300",
  "herb" => "bg-emerald-100 border-emerald-300",
  "flower" => "bg-pink-100 border-pink-300",
  "lettuce" => "bg-yellow-100 border-yellow-300"
} %>

<!-- Beds grid -->
<div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-6">
  <% @bed_data.each do |bd| %>
    <% bed = bd[:bed] %>
    <a href="/beds/<%= bed.id %>" class="block bg-white rounded-lg p-4 shadow-sm hover:shadow-md transition">
      <h2 class="font-semibold mb-2"><%= bed.name %></h2>
      <% bd[:rows].each do |rd| %>
        <div class="flex gap-1 mb-1">
          <span class="text-xs text-stone-400 w-12"><%= rd[:row].name %></span>
          <% rd[:slots].each do |sd| %>
            <% plant = sd[:plant] %>
            <% color = plant ? (crop_colors[plant.crop_type] || "bg-stone-100 border-stone-300") : "bg-stone-50 border-stone-200" %>
            <div class="w-8 h-8 rounded border text-center text-xs flex items-center justify-center <%= color %>"
                 title="<%= plant ? "#{plant.variety_name} (#{plant.lifecycle_stage.tr('_', ' ')})" : sd[:slot].name %>">
              <%= plant ? plant.variety_name[0..1] : "" %>
            </div>
          <% end %>
        </div>
      <% end %>
    </a>
  <% end %>
</div>

<!-- Arches -->
<% unless @arches.empty? %>
  <h2 class="text-lg font-semibold mb-3">Arches</h2>
  <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
    <% @arches.each do |arch| %>
      <div class="bg-white rounded-lg p-3 shadow-sm text-center">
        <p class="font-medium"><%= arch.name %></p>
        <p class="text-xs text-stone-500"><%= arch.between_beds %></p>
        <p class="text-xs">Spring: <%= arch.spring_crop || "—" %></p>
        <p class="text-xs">Summer: <%= arch.summer_crop || "—" %></p>
      </div>
    <% end %>
  </div>
<% end %>

<!-- Indoor stations -->
<% unless @indoor_stations.empty? %>
  <h2 class="text-lg font-semibold mb-3">Indoor</h2>
  <div class="grid grid-cols-2 gap-3">
    <% @indoor_stations.each do |station| %>
      <div class="bg-white rounded-lg p-3 shadow-sm">
        <p class="font-medium"><%= station.name %></p>
        <% plants = Plant.where(indoor_station_id: station.id).exclude(lifecycle_stage: "done").all %>
        <p class="text-xs text-stone-500"><%= plants.count %> plants</p>
      </div>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 5: Create beds/show.erb**

```erb
<!-- views/beds/show.erb -->
<a href="/beds" class="text-sm text-green-700 hover:underline mb-4 inline-block">&larr; Garden Map</a>

<h1 class="text-2xl font-bold mb-2"><%= @bed.name %></h1>
<p class="text-stone-500 mb-6"><%= @bed.bed_type %> — <%= @bed.orientation || "N/A" %></p>

<% @rows.each do |row| %>
  <div class="mb-4">
    <h2 class="text-sm font-semibold text-stone-500 mb-2"><%= row.name %></h2>
    <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
      <% (@slots_by_row[row.id] || []).each do |slot| %>
        <% plant = @plants_by_slot[slot.id]&.first %>
        <div class="bg-white rounded-lg p-3 shadow-sm">
          <p class="text-xs text-stone-400"><%= slot.name %></p>
          <% if plant %>
            <a href="/plants/<%= plant.id %>" class="block">
              <p class="font-medium"><%= plant.variety_name %></p>
              <p class="text-xs text-stone-600"><%= plant.lifecycle_stage.tr('_', ' ') %></p>
            </a>
          <% else %>
            <p class="text-stone-400 text-sm">Empty</p>
          <% end %>
        </div>
      <% end %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 6: Add to app.rb**

Add `require_relative "routes/beds"` at the bottom of app.rb.

- [ ] **Step 7: Run tests**

Run: `ruby test/routes/test_beds.rb`
Expected: 3 tests, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add routes/beds.rb views/beds/ app.rb test/routes/test_beds.rb
git commit -m "feat: bed map with color-coded slots and drill-down views"
```

---

### Task 8: Tasks Route + Completion

**Files:**
- Create: `routes/tasks.rb`
- Modify: `app.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/routes/test_tasks.rb
require_relative "../test_helper"
require_relative "../../app"

class TestTasks < GardenTest
  def test_complete_task
    task = Task.create(title: "Sow lettuce", task_type: "sow",
                       due_date: Date.today, status: "upcoming")
    post "/tasks/#{task.id}/complete"
    assert_equal 302, last_response.status
    assert_equal "done", task.reload.status
  end

  def test_api_tasks
    Task.create(title: "Water beds", task_type: "water",
                due_date: Date.today, status: "upcoming")
    get "/api/tasks"
    assert_equal 200, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 1, data.length
  end
end
```

- [ ] **Step 2: Run test — expect failure**

- [ ] **Step 3: Create tasks route**

```ruby
# routes/tasks.rb
require_relative "../models/task"

class GardenApp
  post "/tasks/:id/complete" do
    task = Task[params[:id].to_i]
    halt 404 unless task
    task.complete!
    redirect back
  end

  post "/tasks/:id/skip" do
    task = Task[params[:id].to_i]
    halt 404 unless task
    task.update(status: "skipped", updated_at: Time.now)
    redirect back
  end

  post "/tasks/:id/defer" do
    task = Task[params[:id].to_i]
    halt 404 unless task
    task.update(status: "deferred", updated_at: Time.now)
    redirect back
  end

  get "/api/tasks" do
    tasks = Task.exclude(status: "done")
                .order(:due_date).all
    json tasks.map(&:values)
  end

  get "/api/tasks/today" do
    tasks = Task.where(due_date: Date.today)
                .exclude(status: "done").all
    json tasks.map(&:values)
  end
end
```

- [ ] **Step 4: Add to app.rb**

Add `require_relative "routes/tasks"` at the bottom of app.rb.

- [ ] **Step 5: Run tests**

Run: `ruby test/routes/test_tasks.rb`
Expected: 2 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add routes/tasks.rb app.rb test/routes/test_tasks.rb
git commit -m "feat: task completion, skip, defer routes + JSON API"
```

---

## Phase 3: Services (Tasks 9–12)

### Task 9: Weather Service

**Files:**
- Create: `services/weather_service.rb`
- Create: `test/services/test_weather_service.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/services/test_weather_service.rb
require_relative "../test_helper"
require_relative "../../services/weather_service"

class TestWeatherService < GardenTest
  def test_parse_ha_weather_response
    mock_response = {
      "state" => "sunny",
      "attributes" => {
        "temperature" => 18.5,
        "forecast" => [
          { "datetime" => "2026-03-17", "temperature" => 15.0, "templow" => 2.0, "condition" => "cloudy" },
          { "datetime" => "2026-03-18", "temperature" => 12.0, "templow" => -1.0, "condition" => "snowy" },
          { "datetime" => "2026-03-19", "temperature" => 14.0, "templow" => 3.0, "condition" => "sunny" }
        ]
      }
    }

    weather = WeatherService.parse_forecast(mock_response)
    assert_equal 18.5, weather[:current_temp]
    assert_equal 3, weather[:forecast].length
    assert_equal true, weather[:frost_risk]  # -1.0 in forecast
  end

  def test_frost_detection
    forecast = [
      { "templow" => 3.0 },
      { "templow" => 1.0 },
      { "templow" => -2.0 }
    ]
    assert WeatherService.frost_risk?(forecast)
  end

  def test_no_frost
    forecast = [
      { "templow" => 5.0 },
      { "templow" => 3.0 }
    ]
    refute WeatherService.frost_risk?(forecast)
  end
end
```

- [ ] **Step 2: Run test — expect failure**

- [ ] **Step 3: Implement WeatherService**

```ruby
# services/weather_service.rb
require "json"
require "httpx"

class WeatherService
  HA_URL = ENV.fetch("HA_URL", "http://homeassistant.local:8123")
  HA_TOKEN = ENV.fetch("HA_TOKEN", "")
  WEATHER_ENTITY = ENV.fetch("HA_WEATHER_ENTITY", "weather.home")

  def self.fetch_current
    return nil if HA_TOKEN.empty?

    response = HTTPX.with(
      headers: {
        "Authorization" => "Bearer #{HA_TOKEN}",
        "Content-Type" => "application/json"
      }
    ).get("#{HA_URL}/api/states/#{WEATHER_ENTITY}")

    return nil unless response.status == 200
    parse_forecast(JSON.parse(response.body.to_s))
  rescue => e
    warn "WeatherService error: #{e.message}"
    nil
  end

  def self.parse_forecast(data)
    attrs = data["attributes"] || {}
    forecast = attrs["forecast"] || []

    {
      current_temp: attrs["temperature"],
      condition: data["state"],
      forecast: forecast.first(3).map do |day|
        {
          date: day["datetime"],
          high: day["temperature"],
          low: day["templow"],
          condition: day["condition"]
        }
      end,
      frost_risk: frost_risk?(forecast)
    }
  end

  def self.frost_risk?(forecast)
    forecast.any? { |day| (day["templow"] || day[:low]).to_f <= 0 }
  end
end
```

- [ ] **Step 4: Run tests**

Run: `ruby test/services/test_weather_service.rb`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add services/weather_service.rb test/services/test_weather_service.rb
git commit -m "feat: weather service with HA integration and frost detection"
```

---

### Task 10: Notification Service

**Files:**
- Create: `services/notification_service.rb`
- Create: `test/services/test_notification_service.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/services/test_notification_service.rb
require_relative "../test_helper"
require_relative "../../services/notification_service"

class TestNotificationService < GardenTest
  def test_builds_morning_brief_payload
    payload = NotificationService.morning_brief_payload(
      task_count: 3,
      weather_summary: "Sunny, 18C",
      germination_alerts: "Peppers day 5 on heat mat",
      dashboard_url: "http://garden.local:4567"
    )

    assert_equal "Garden — #{Date.today}", payload[:title]
    assert_includes payload[:message], "3 tasks today"
    assert_includes payload[:message], "Sunny, 18C"
  end

  def test_builds_frost_alert_payload
    payload = NotificationService.frost_alert_payload(
      min_temp: -2,
      when_str: "tonight",
      tender_count: 5
    )

    assert_includes payload[:title], "Frost"
    assert_includes payload[:message], "-2"
    assert_includes payload[:message], "5 tender"
  end
end
```

- [ ] **Step 2: Run test — expect failure**

- [ ] **Step 3: Implement NotificationService**

```ruby
# services/notification_service.rb
require "json"
require "httpx"
require_relative "../models/task"
require_relative "../models/plant"
require_relative "weather_service"

class NotificationService
  HA_URL = ENV.fetch("HA_URL", "http://homeassistant.local:8123")
  HA_TOKEN = ENV.fetch("HA_TOKEN", "")
  NOTIFY_SERVICE = ENV.fetch("HA_NOTIFY_SERVICE", "notify.mobile_app_toms_phone")

  def self.send!(title:, message:, data: {})
    return false if HA_TOKEN.empty?

    payload = {
      title: title,
      message: message,
      data: data
    }

    response = HTTPX.with(
      headers: {
        "Authorization" => "Bearer #{HA_TOKEN}",
        "Content-Type" => "application/json"
      }
    ).post(
      "#{HA_URL}/api/services/#{NOTIFY_SERVICE.sub('.', '/')}",
      json: payload
    )

    response.status == 200
  rescue => e
    warn "NotificationService error: #{e.message}"
    false
  end

  def self.morning_brief_payload(task_count:, weather_summary:, germination_alerts:, dashboard_url:)
    {
      title: "Garden — #{Date.today}",
      message: [
        "#{task_count} tasks today.",
        weather_summary,
        germination_alerts
      ].compact.reject(&:empty?).join("\n"),
      data: { url: dashboard_url }
    }
  end

  def self.frost_alert_payload(min_temp:, when_str:, tender_count:)
    {
      title: "Frost warning",
      message: "#{min_temp}C expected #{when_str}. #{tender_count} tender plants outside.",
      data: {
        actions: [
          { action: "FROST_ACKNOWLEDGE", title: "Got it" }
        ]
      }
    }
  end

  def self.send_morning_brief!
    tasks = Task.where(due_date: Date.today).exclude(status: "done").all
    weather = WeatherService.fetch_current
    germ_plants = Plant.where(lifecycle_stage: %w[germinating sown_indoor]).all

    weather_str = weather ? "#{weather[:condition]}, #{weather[:current_temp]}C" : "Weather unavailable"
    germ_str = germ_plants.map { |p| "#{p.variety_name} day #{p.days_in_stage}" }.join(", ")

    payload = morning_brief_payload(
      task_count: tasks.count,
      weather_summary: weather_str,
      germination_alerts: germ_str.empty? ? nil : germ_str,
      dashboard_url: ENV.fetch("APP_URL", "http://garden.local:4567")
    )

    send!(**payload)
  end
end
```

- [ ] **Step 4: Run tests**

Run: `ruby test/services/test_notification_service.rb`
Expected: 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add services/notification_service.rb test/services/test_notification_service.rb
git commit -m "feat: notification service with HA push, morning brief, frost alerts"
```

---

### Task 11: AI Advisory Service

**Files:**
- Create: `services/ai_advisory_service.rb`
- Create: `test/services/test_ai_advisory_service.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/services/test_ai_advisory_service.rb
require_relative "../test_helper"
require_relative "../../services/ai_advisory_service"

class TestAIAdvisoryService < GardenTest
  def test_builds_context_payload
    Plant.create(variety_name: "Raf", crop_type: "tomato", lifecycle_stage: "germinating",
                 sow_date: Date.today - 5)

    context = AIAdvisoryService.build_context
    assert context.key?(:plants)
    assert_equal 1, context[:plants].length
    assert_equal "Raf", context[:plants][0][:variety_name]
  end

  def test_parses_advisory_response
    mock_response = {
      "advisories" => [
        { "type" => "general", "summary" => "Good day for transplanting" },
        { "type" => "plant_specific", "plant" => "Raf", "summary" => "Check moisture" }
      ]
    }

    advisories = AIAdvisoryService.parse_response(mock_response)
    assert_equal 2, advisories.length
    assert_equal "general", advisories[0][:type]
  end

  def test_system_prompt_includes_prague
    prompt = AIAdvisoryService.system_prompt
    assert_includes prompt, "Prague"
  end
end
```

- [ ] **Step 2: Run test — expect failure**

- [ ] **Step 3: Implement AIAdvisoryService**

```ruby
# services/ai_advisory_service.rb
require "json"
require_relative "../models/plant"
require_relative "../models/task"
require_relative "../models/advisory"
require_relative "../db/seeds/seed_varieties"

class AIAdvisoryService
  def self.system_prompt
    <<~PROMPT
      You are a garden advisor for a productive vegetable garden in Prague, Czech Republic (zone 6b/7a).
      Climate: last frost ~May 13, first frost ~Oct 15. Continental climate with hot summers.

      You receive the current state of all plants, upcoming tasks, and weather forecast.
      Provide actionable, specific advisories. Focus on:
      - Germination progress (is it on track for the crop type?)
      - Weather-based timing recommendations
      - Succession sowing reminders
      - Potential issues (overdue germination, frost risk for tender plants)

      Respond with JSON only:
      {
        "advisories": [
          {"type": "general|plant_specific|weather", "plant": "name or null", "summary": "one sentence", "detail": "explanation"}
        ]
      }
    PROMPT
  end

  def self.build_context
    plants = Plant.exclude(lifecycle_stage: "done").all.map do |p|
      {
        variety_name: p.variety_name,
        crop_type: p.crop_type,
        stage: p.lifecycle_stage,
        days_in_stage: p.days_in_stage,
        sow_date: p.sow_date&.to_s
      }
    end

    tasks = Task.where(due_date: Date.today..(Date.today + 7))
                .exclude(status: "done").all.map do |t|
      { title: t.title, type: t.task_type, due: t.due_date.to_s }
    end

    weather = WeatherService.fetch_current rescue nil

    {
      date: Date.today.to_s,
      plants: plants,
      upcoming_tasks: tasks,
      weather: weather,
      variety_data: Varieties.all
    }
  end

  def self.parse_response(data)
    (data["advisories"] || []).map do |adv|
      {
        type: adv["type"],
        plant: adv["plant"],
        summary: adv["summary"],
        detail: adv["detail"]
      }
    end
  end

  def self.run_daily!
    return unless ENV["ANTHROPIC_API_KEY"]

    require "anthropic"

    context = build_context
    client = Anthropic::Client.new

    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 1024,
      system: system_prompt,
      messages: [
        { role: "user", content: JSON.pretty_generate(context) }
      ]
    )

    text = response.content.first.text
    parsed = JSON.parse(text)
    advisories = parse_response(parsed)

    advisories.each do |adv|
      plant_id = nil
      if adv[:plant]
        plant = Plant.where(variety_name: adv[:plant]).first
        plant_id = plant&.id
      end

      Advisory.create(
        date: Date.today,
        advisory_type: adv[:type],
        content: JSON.generate(adv),
        plant_id: plant_id
      )
    end

    advisories
  rescue => e
    warn "AI Advisory error: #{e.message}"
    []
  end
end
```

- [ ] **Step 4: Run tests**

Run: `ruby test/services/test_ai_advisory_service.rb`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add services/ai_advisory_service.rb test/services/test_ai_advisory_service.rb
git commit -m "feat: AI advisory service — daily Claude API call with garden context"
```

---

### Task 12: Task Generator + Scheduler

**Files:**
- Create: `services/task_generator.rb`
- Create: `services/scheduler.rb`
- Create: `test/services/test_task_generator.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/services/test_task_generator.rb
require_relative "../test_helper"
require_relative "../../services/task_generator"

class TestTaskGenerator < GardenTest
  def test_generates_succession_sowing_task
    sp = SuccessionPlan.create(
      crop: "Lettuce", varieties: '["Tre Colori"]',
      interval_days: 18, season_start: Date.today - 20,
      season_end: Date.today + 90, target_beds: '["BB1"]',
      total_planned_sowings: 8
    )

    TaskGenerator.generate_succession_tasks!
    tasks = Task.where(task_type: "sow").all
    refute_empty tasks
    assert_includes tasks.first.title, "Lettuce"
  end

  def test_generates_germination_check_tasks
    Plant.create(variety_name: "Raf", crop_type: "tomato",
                 lifecycle_stage: "germinating", sow_date: Date.today - 7)
    StageHistory.create(plant_id: Plant.first.id, to_stage: "germinating",
                        changed_at: Time.now - (7 * 86400))

    TaskGenerator.generate_germination_checks!
    tasks = Task.where(task_type: "check").all
    refute_empty tasks
  end

  def test_no_duplicate_tasks
    Task.create(title: "Sow Lettuce #2", task_type: "sow",
                due_date: Date.today + 3, status: "upcoming")
    sp = SuccessionPlan.create(
      crop: "Lettuce", varieties: '["Tre Colori"]',
      interval_days: 18, season_start: Date.today - 20,
      season_end: Date.today + 90, target_beds: '["BB1"]',
      total_planned_sowings: 8
    )

    TaskGenerator.generate_succession_tasks!
    # Should not create duplicate
    assert_equal 1, Task.where(task_type: "sow").where(Sequel.like(:title, "%Lettuce%")).count
  end
end
```

- [ ] **Step 2: Run test — expect failure**

- [ ] **Step 3: Implement TaskGenerator**

```ruby
# services/task_generator.rb
require_relative "../models/task"
require_relative "../models/plant"
require_relative "../models/succession_plan"
require_relative "../db/seeds/seed_varieties"

class TaskGenerator
  def self.generate_all!
    generate_succession_tasks!
    generate_germination_checks!
  end

  def self.generate_succession_tasks!
    SuccessionPlan.all.each do |sp|
      next if sp.season_end && sp.season_end < Date.today

      # Count existing sowing tasks for this crop
      existing = Task.where(task_type: "sow")
                     .where(Sequel.like(:title, "%#{sp.crop}%")).count

      next if existing >= sp.total_planned_sowings.to_i

      next_date = sp.next_sowing_date(existing)
      next if next_date.nil? || next_date > Date.today + 14

      # Check for existing upcoming task
      already_exists = Task.where(task_type: "sow")
                           .where(Sequel.like(:title, "%#{sp.crop}%"))
                           .exclude(status: "done")
                           .where(due_date: (next_date - 3)..(next_date + 3))
                           .any?
      next if already_exists

      beds_str = sp.target_beds_list.join(", ")
      Task.create(
        title: "Sow #{sp.crop} ##{existing + 1} — #{beds_str}",
        task_type: "sow",
        due_date: next_date,
        priority: "should",
        status: "upcoming",
        notes: "Varieties: #{sp.varieties_list.join(', ')}. Succession #{existing + 1} of #{sp.total_planned_sowings}."
      )
    end
  end

  def self.generate_germination_checks!
    Plant.where(lifecycle_stage: "germinating").all.each do |plant|
      days = plant.days_in_stage
      variety_info = Varieties.for(plant.crop_type)
      next unless variety_info

      max_days = variety_info["germination_days_max"] || 14
      # Generate check task when approaching max germination time
      if days >= (max_days * 0.7).to_i
        already_exists = Task.where(task_type: "check")
                             .where(Sequel.like(:title, "%#{plant.variety_name}%"))
                             .exclude(status: "done")
                             .any?
        next if already_exists

        Task.create(
          title: "Check #{plant.variety_name} — day #{days} germinating",
          task_type: "check",
          due_date: Date.today,
          priority: "should",
          status: "upcoming",
          notes: "Expected #{variety_info['germination_days_min']}-#{max_days} days. Currently day #{days}."
        )
      end
    end
  end
end
```

- [ ] **Step 4: Implement Scheduler**

```ruby
# services/scheduler.rb
require "rufus-scheduler"
require_relative "weather_service"
require_relative "notification_service"
require_relative "ai_advisory_service"
require_relative "task_generator"
require_relative "../models/plant"
require_relative "../db/seeds/seed_varieties"

class GardenScheduler
  def self.start!
    scheduler = Rufus::Scheduler.new

    # Daily AI advisory at 06:30
    scheduler.cron "30 6 * * *" do
      puts "[#{Time.now}] Running AI advisory..."
      AIAdvisoryService.run_daily!
    end

    # Morning brief notification at 07:00
    scheduler.cron "0 7 * * *" do
      puts "[#{Time.now}] Sending morning brief..."
      NotificationService.send_morning_brief!
    end

    # Generate tasks every 6 hours
    scheduler.cron "0 */6 * * *" do
      puts "[#{Time.now}] Generating tasks..."
      TaskGenerator.generate_all!
    end

    # Weather check every 6 hours + frost alert
    scheduler.cron "0 */6 * * *" do
      puts "[#{Time.now}] Checking weather..."
      weather = WeatherService.fetch_current
      if weather && weather[:frost_risk]
        tender_outside = Plant.where(
          lifecycle_stage: %w[hardening_off planted_out producing]
        ).all.select do |p|
          Varieties.for(p.crop_type)&.dig("frost_tender")
        end

        if tender_outside.any?
          min_temp = weather[:forecast].map { |f| f[:low] }.compact.min
          NotificationService.send!(
            **NotificationService.frost_alert_payload(
              min_temp: min_temp,
              when_str: "within 48h",
              tender_count: tender_outside.count
            )
          )
        end
      end
    end

    puts "Scheduler started."
    scheduler
  end
end
```

- [ ] **Step 5: Run tests**

Run: `ruby test/services/test_task_generator.rb`
Expected: 3 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add services/task_generator.rb services/scheduler.rb test/services/test_task_generator.rb
git commit -m "feat: task generator (succession + germination checks) and background scheduler"
```

---

## Phase 4: Succession Planner + PWA (Tasks 13–14)

### Task 13: Succession Planner View

**Files:**
- Create: `routes/succession.rb` (add to GardenApp)
- Create: `views/succession.erb`
- Create: `test/routes/test_succession.rb`
- Modify: `app.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/routes/test_succession.rb
require_relative "../test_helper"
require_relative "../../app"

class TestSuccession < GardenTest
  def test_succession_index
    get "/succession"
    assert_equal 200, last_response.status
  end

  def test_succession_shows_plan
    SuccessionPlan.create(crop: "Lettuce", varieties: '["Tre Colori"]',
                          interval_days: 18, total_planned_sowings: 8,
                          season_start: Date.today, season_end: Date.today + 90,
                          target_beds: '["BB1"]')
    get "/succession"
    assert_includes last_response.body, "Lettuce"
  end
end
```

- [ ] **Step 2: Run test — expect failure**

Run: `ruby test/routes/test_succession.rb`
Expected: FAIL — route not defined.

- [ ] **Step 3: Create succession route**

```ruby
# routes/succession.rb (add to GardenApp class)
require_relative "../models/succession_plan"
require_relative "../models/task"

class GardenApp
  get "/succession" do
    @plans = SuccessionPlan.all
    erb :succession
  end

  get "/api/succession" do
    plans = SuccessionPlan.all.map do |sp|
      completed = Task.where(task_type: "sow")
                      .where(Sequel.like(:title, "%#{sp.crop}%"))
                      .where(status: "done").count
      upcoming = Task.where(task_type: "sow")
                     .where(Sequel.like(:title, "%#{sp.crop}%"))
                     .exclude(status: "done").first

      sp.values.merge(
        completed_sowings: completed,
        next_sowing: upcoming&.values,
        next_sowing_date: sp.next_sowing_date(completed)&.to_s
      )
    end
    json plans
  end
end
```

- [ ] **Step 4: Create succession.erb**

```erb
<!-- views/succession.erb -->
<h1 class="text-2xl font-bold mb-6">Succession Planner</h1>

<% if @plans.empty? %>
  <p class="text-stone-500">No succession plans yet.</p>
<% else %>
  <div class="space-y-4">
    <% @plans.each do |plan| %>
      <% completed = Task.where(task_type: "sow")
                         .where(Sequel.like(:title, "%#{plan.crop}%"))
                         .where(status: "done").count
         total = plan.total_planned_sowings || 0
         pct = total > 0 ? (completed.to_f / total * 100).round : 0
         next_date = plan.next_sowing_date(completed) %>
      <div class="bg-white rounded-lg p-4 shadow-sm">
        <div class="flex items-center justify-between mb-2">
          <h2 class="text-lg font-semibold"><%= plan.crop %></h2>
          <span class="text-sm text-stone-500"><%= completed %>/<%= total %> sowings</span>
        </div>

        <!-- Progress bar -->
        <div class="w-full bg-stone-200 rounded-full h-3 mb-3">
          <div class="bg-green-500 h-3 rounded-full" style="width: <%= pct %>%"></div>
        </div>

        <!-- Sowing dots -->
        <div class="flex gap-2 mb-3">
          <% total.times do |i| %>
            <% if i < completed %>
              <div class="w-6 h-6 rounded-full bg-green-500 flex items-center justify-center text-white text-xs"><%= i + 1 %></div>
            <% elsif i == completed %>
              <div class="w-6 h-6 rounded-full bg-amber-400 border-2 border-amber-500 flex items-center justify-center text-xs font-bold"><%= i + 1 %></div>
            <% else %>
              <div class="w-6 h-6 rounded-full bg-stone-200 flex items-center justify-center text-stone-400 text-xs"><%= i + 1 %></div>
            <% end %>
          <% end %>
        </div>

        <div class="text-sm text-stone-600">
          <p>Every <strong><%= plan.interval_days %></strong> days — Varieties: <%= plan.varieties_list.join(", ") %></p>
          <p>Beds: <%= plan.target_beds_list.join(", ") %></p>
          <% if next_date && next_date >= Date.today %>
            <% days_until = (next_date - Date.today).to_i %>
            <p class="mt-1 font-medium text-amber-700">
              Next sowing (#<%= completed + 1 %>) in <strong><%= days_until %></strong> days (<%= next_date.strftime("%b %-d") %>)
            </p>
          <% elsif completed >= total %>
            <p class="mt-1 text-green-600 font-medium">All sowings complete!</p>
          <% end %>
        </div>
      </div>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 5: Add to app.rb**

Add `require_relative "routes/succession"` at the bottom of app.rb.

- [ ] **Step 6: Run tests**

Run: `ruby test/routes/test_succession.rb`
Expected: 2 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add routes/succession.rb views/succession.erb test/routes/test_succession.rb app.rb
git commit -m "feat: succession planner view with progress tracking and next-sowing countdown"
```

---

### Task 14: PWA Manifest + Service Worker

**Files:**
- Create: `public/manifest.json`
- Create: `public/sw.js`

- [ ] **Step 1: Create manifest.json**

```json
{
  "name": "GardenOS",
  "short_name": "Garden",
  "description": "Garden management — what to do today",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#fafaf9",
  "theme_color": "#16a34a",
  "icons": [
    {
      "src": "/icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
```

- [ ] **Step 2: Generate placeholder PWA icons**

Run: `convert -size 192x192 xc:#16a34a -fill white -gravity center -pointsize 72 -annotate 0 "G" public/icon-192.png && convert -size 512x512 xc:#16a34a -fill white -gravity center -pointsize 192 -annotate 0 "G" public/icon-512.png`

If ImageMagick is not available, create simple green square PNGs manually or use any online favicon generator. The icons must exist at `public/icon-192.png` and `public/icon-512.png` for the PWA install to work.

- [ ] **Step 3: Create service worker (basic offline page)**

```javascript
// public/sw.js
const CACHE_NAME = "gardenOS-v1";

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(["/", "/plants", "/beds", "/succession"]);
    })
  );
});

self.addEventListener("fetch", (event) => {
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
```

- [ ] **Step 4: Add service worker registration to layout.erb**

Add before `</body>` in `views/layout.erb`:

```html
<script>
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("/sw.js");
  }
</script>
```

- [ ] **Step 5: Commit**

```bash
git add public/manifest.json public/icon-192.png public/icon-512.png public/sw.js views/layout.erb
git commit -m "feat: PWA manifest, icons, and basic service worker for offline support"
```

---

## Phase 5: HACS Integration (Tasks 15–17)

> **Out of scope for MVP:** `services.yaml` (HA service calls like `advance_stage`, `log_note`) — defer to V2 once the core integration is proven.

### Task 15: HACS Integration Scaffold

**Files:**
- Create: `hacs/custom_components/garden_os/__init__.py`
- Create: `hacs/custom_components/garden_os/manifest.json`
- Create: `hacs/custom_components/garden_os/const.py`
- Create: `hacs/custom_components/garden_os/config_flow.py`
- Create: `hacs/custom_components/garden_os/coordinator.py`

- [ ] **Step 1: Create manifest.json**

```json
{
  "domain": "garden_os",
  "name": "GardenOS",
  "codeowners": ["@tkejzlar"],
  "config_flow": true,
  "dependencies": [],
  "documentation": "https://github.com/tkejzlar/garden-os",
  "iot_class": "local_polling",
  "requirements": [],
  "version": "0.1.0"
}
```

- [ ] **Step 2: Create const.py**

```python
# hacs/custom_components/garden_os/const.py
DOMAIN = "garden_os"
CONF_URL = "url"
DEFAULT_URL = "http://localhost:4567"
SCAN_INTERVAL = 300  # 5 minutes
```

- [ ] **Step 3: Create config_flow.py**

```python
# hacs/custom_components/garden_os/config_flow.py
import voluptuous as vol
from homeassistant import config_entries
from homeassistant.const import CONF_URL
from .const import DOMAIN, DEFAULT_URL

class GardenOSConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    VERSION = 1

    async def async_step_user(self, user_input=None):
        errors = {}

        if user_input is not None:
            return self.async_create_entry(
                title="GardenOS",
                data=user_input,
            )

        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema({
                vol.Required(CONF_URL, default=DEFAULT_URL): str,
            }),
            errors=errors,
        )
```

- [ ] **Step 4: Create coordinator.py**

```python
# hacs/custom_components/garden_os/coordinator.py
import logging
from datetime import timedelta
import aiohttp

from homeassistant.core import HomeAssistant
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator

from .const import SCAN_INTERVAL

_LOGGER = logging.getLogger(__name__)


class GardenOSCoordinator(DataUpdateCoordinator):
    def __init__(self, hass: HomeAssistant, url: str) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name="GardenOS",
            update_interval=timedelta(seconds=SCAN_INTERVAL),
        )
        self.api_url = url.rstrip("/")

    async def _async_update_data(self):
        async with aiohttp.ClientSession() as session:
            plants_resp = await session.get(f"{self.api_url}/api/plants")
            plants = await plants_resp.json()

            tasks_resp = await session.get(f"{self.api_url}/api/tasks")
            tasks = await tasks_resp.json()

            beds_resp = await session.get(f"{self.api_url}/api/beds")
            beds = await beds_resp.json()

            return {
                "plants": plants,
                "tasks": tasks,
                "beds": beds,
            }
```

- [ ] **Step 5: Create __init__.py**

```python
# hacs/custom_components/garden_os/__init__.py
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import CONF_URL, Platform
from homeassistant.core import HomeAssistant

from .const import DOMAIN
from .coordinator import GardenOSCoordinator

PLATFORMS = [Platform.SENSOR, Platform.BINARY_SENSOR, Platform.CALENDAR]


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    coordinator = GardenOSCoordinator(hass, entry.data[CONF_URL])
    await coordinator.async_config_entry_first_refresh()

    hass.data.setdefault(DOMAIN, {})
    hass.data[DOMAIN][entry.entry_id] = coordinator

    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    unload_ok = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unload_ok:
        hass.data[DOMAIN].pop(entry.entry_id)
    return unload_ok
```

- [ ] **Step 6: Commit**

```bash
git add hacs/
git commit -m "feat: HACS integration scaffold — config flow, coordinator, manifest"
```

---

### Task 16: HACS Sensor + Binary Sensor Entities

**Files:**
- Create: `hacs/custom_components/garden_os/sensor.py`
- Create: `hacs/custom_components/garden_os/binary_sensor.py`

- [ ] **Step 1: Create sensor.py (one entity per plant)**

```python
# hacs/custom_components/garden_os/sensor.py
from homeassistant.components.sensor import SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import GardenOSCoordinator


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    coordinator: GardenOSCoordinator = hass.data[DOMAIN][entry.entry_id]
    entities = []

    for plant in coordinator.data.get("plants", []):
        entities.append(GardenOSPlantSensor(coordinator, plant))

    async_add_entities(entities, True)


class GardenOSPlantSensor(CoordinatorEntity, SensorEntity):
    def __init__(self, coordinator: GardenOSCoordinator, plant: dict) -> None:
        super().__init__(coordinator)
        self._plant_id = plant["id"]
        self._attr_name = f"GardenOS {plant.get('crop_type', '')} {plant.get('variety_name', '')}"
        self._attr_unique_id = f"garden_os_plant_{plant['id']}"

    @property
    def native_value(self):
        for plant in self.coordinator.data.get("plants", []):
            if plant["id"] == self._plant_id:
                return plant.get("lifecycle_stage", "unknown")
        return "unknown"

    @property
    def extra_state_attributes(self):
        for plant in self.coordinator.data.get("plants", []):
            if plant["id"] == self._plant_id:
                return {
                    "variety_name": plant.get("variety_name"),
                    "crop_type": plant.get("crop_type"),
                    "sow_date": plant.get("sow_date"),
                    "days_in_stage": plant.get("days_in_stage", 0),
                }
        return {}
```

- [ ] **Step 2: Create binary_sensor.py**

```python
# hacs/custom_components/garden_os/binary_sensor.py
from homeassistant.components.binary_sensor import (
    BinarySensorDeviceClass,
    BinarySensorEntity,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import GardenOSCoordinator


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    coordinator: GardenOSCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([
        GardenOSFrostRiskSensor(coordinator),
        GardenOSSuccessionDueSensor(coordinator),
        GardenOSGerminationOverdueSensor(coordinator),
    ], True)


class GardenOSFrostRiskSensor(CoordinatorEntity, BinarySensorEntity):
    _attr_name = "GardenOS Frost Risk"
    _attr_unique_id = "garden_os_frost_risk"
    _attr_device_class = BinarySensorDeviceClass.SAFETY

    def __init__(self, coordinator: GardenOSCoordinator) -> None:
        super().__init__(coordinator)

    @property
    def is_on(self):
        # Frost risk derived from tasks with frost-related conditions
        tasks = self.coordinator.data.get("tasks", [])
        return any(
            t.get("task_type") == "check" and "frost" in t.get("title", "").lower()
            for t in tasks
        )


class GardenOSSuccessionDueSensor(CoordinatorEntity, BinarySensorEntity):
    _attr_name = "GardenOS Succession Due"
    _attr_unique_id = "garden_os_succession_due"

    def __init__(self, coordinator: GardenOSCoordinator) -> None:
        super().__init__(coordinator)

    @property
    def is_on(self):
        tasks = self.coordinator.data.get("tasks", [])
        return any(t.get("task_type") == "sow" for t in tasks)


class GardenOSGerminationOverdueSensor(CoordinatorEntity, BinarySensorEntity):
    _attr_name = "GardenOS Germination Overdue"
    _attr_unique_id = "garden_os_germination_overdue"

    def __init__(self, coordinator: GardenOSCoordinator) -> None:
        super().__init__(coordinator)

    @property
    def is_on(self):
        tasks = self.coordinator.data.get("tasks", [])
        return any(
            t.get("task_type") == "check" and "germinating" in t.get("title", "").lower()
            for t in tasks
        )
```

- [ ] **Step 3: Commit**

```bash
git add hacs/custom_components/garden_os/sensor.py hacs/custom_components/garden_os/binary_sensor.py
git commit -m "feat: HACS sensor entities (per-plant) and binary sensors (frost, succession, germination)"
```

---

### Task 17: HACS Calendar Entity

**Files:**
- Create: `hacs/custom_components/garden_os/calendar.py`

- [ ] **Step 1: Create calendar.py**

```python
# hacs/custom_components/garden_os/calendar.py
from datetime import datetime, date

from homeassistant.components.calendar import CalendarEntity, CalendarEvent
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import GardenOSCoordinator


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    coordinator: GardenOSCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([GardenOSCalendar(coordinator)], True)


class GardenOSCalendar(CoordinatorEntity, CalendarEntity):
    _attr_name = "GardenOS"
    _attr_unique_id = "garden_os_calendar"

    def __init__(self, coordinator: GardenOSCoordinator) -> None:
        super().__init__(coordinator)

    @property
    def event(self) -> CalendarEvent | None:
        tasks = self.coordinator.data.get("tasks", [])
        today = date.today().isoformat()
        today_tasks = [t for t in tasks if t.get("due_date") == today]
        if not today_tasks:
            return None
        task = today_tasks[0]
        return CalendarEvent(
            summary=task["title"],
            start=date.today(),
            end=date.today(),
        )

    async def async_get_events(
        self, hass: HomeAssistant, start_date: datetime, end_date: datetime
    ) -> list[CalendarEvent]:
        tasks = self.coordinator.data.get("tasks", [])
        events = []
        for task in tasks:
            due = task.get("due_date")
            if not due:
                continue
            task_date = date.fromisoformat(due)
            if start_date.date() <= task_date <= end_date.date():
                events.append(CalendarEvent(
                    summary=task["title"],
                    start=task_date,
                    end=task_date,
                    description=task.get("notes", ""),
                ))
        return events
```

- [ ] **Step 2: Commit**

```bash
git add hacs/custom_components/garden_os/calendar.py
git commit -m "feat: HACS calendar entity — tasks as calendar events for Google Calendar sync"
```

---

## Phase 6: Wire Up + Deploy (Tasks 18–19)

### Task 18: Wire Up config.ru with Scheduler

**Files:**
- Modify: `config.ru`
- Modify: `app.rb` — require all routes

- [ ] **Step 1: Update app.rb to load all routes**

```ruby
# app.rb (final version)
require "sinatra/base"
require "sinatra/json"
require_relative "config/database"

class GardenApp < Sinatra::Base
  helpers Sinatra::JSON

  configure do
    set :views, File.join(File.dirname(__FILE__), "views")
    set :public_folder, File.join(File.dirname(__FILE__), "public")
  end

  get "/health" do
    json status: "ok"
  end
end

require_relative "routes/dashboard"
require_relative "routes/plants"
require_relative "routes/beds"
require_relative "routes/tasks"
require_relative "routes/succession"

# JSON API endpoint combining all data for HACS
class GardenApp
  get "/api/status" do
    json(
      plants: Plant.exclude(lifecycle_stage: "done").count,
      tasks_today: Task.where(due_date: Date.today).exclude(status: "done").count,
      germinating: Plant.where(lifecycle_stage: "germinating").count
    )
  end
end
```

- [ ] **Step 2: Update config.ru to start scheduler**

```ruby
# config.ru
require_relative "app"

# Run migrations on startup
Sequel::Migrator.run(DB, "db/migrations")

# Start background scheduler (not in test)
unless ENV["RACK_ENV"] == "test"
  require_relative "services/scheduler"
  GardenScheduler.start!
end

run GardenApp
```

- [ ] **Step 3: Run full test suite**

Run: `ruby -Itest -e "Dir['test/**/*test*.rb'].each { |f| require_relative f }"`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add app.rb config.ru
git commit -m "feat: wire up all routes, scheduler, auto-migrate on startup"
```

---

### Task 19: Manual Smoke Test + Deploy Config

**Files:**
- Create: `.env.example`

- [ ] **Step 1: Create .env.example**

```bash
# .env.example
DATABASE_URL=sqlite://db/garden_os.db
HA_URL=http://homeassistant.local:8123
HA_TOKEN=your_long_lived_access_token
HA_WEATHER_ENTITY=weather.home
HA_NOTIFY_SERVICE=notify.mobile_app_toms_phone
ANTHROPIC_API_KEY=sk-ant-...
APP_URL=http://garden.local:4567
```

- [ ] **Step 2: Start the app and verify manually**

Run: `bundle exec puma -p 4567`
Verify:
- `http://localhost:4567/health` returns `{"status":"ok"}`
- `http://localhost:4567/` renders dashboard
- `http://localhost:4567/plants` renders empty plant list
- `http://localhost:4567/beds` renders empty bed map
- `http://localhost:4567/succession` renders empty succession planner

- [ ] **Step 3: Commit**

```bash
git add .env.example
git commit -m "feat: environment config example and deployment ready"
```

---

## Summary

| Phase | Tasks | What it delivers |
|-------|-------|-----------------|
| 1 — Foundation | 1–4 | Scaffold, DB, models, seed data |
| 2 — API Routes | 5–8 | Dashboard, plants, beds, tasks (full web UI) |
| 3 — Services | 9–12 | Weather, notifications, AI advisories, task generation, scheduler |
| 4 — Views | 13–14 | Succession planner, PWA |
| 5 — HACS | 15–17 | HA integration: sensors, binary sensors, calendar |
| 6 — Wire Up | 18–19 | Full integration, deploy |

Total: **19 tasks**, each independently testable and committable.
