# Multi-Garden Support — Design Spec

> Support multiple independent gardens (e.g., "Home" in Prague and "Cottage" elsewhere). Each garden has its own beds, plants, tasks, and succession plans. Seed inventory is shared.

---

## Data Model

### New table: `gardens`

```
gardens
├── id (primary key)
├── name (string, not null, unique)
├── location (string, optional) — "Prague", "Countryside"
├── climate_zone (string, optional) — "6b/7a"
├── created_at
```

### Add `garden_id` FK to existing tables

| Table | FK | On Delete | Notes |
|-------|-----|-----------|-------|
| `beds` | `garden_id` (not null) | CASCADE | Arches + indoor_stations also get garden_id |
| `arches` | `garden_id` (not null) | CASCADE | Physically located in a garden |
| `indoor_stations` | `garden_id` (not null) | CASCADE | Each garden has its own indoor setup |
| `plants` | `garden_id` (not null) | CASCADE | Denormalized for query convenience (also reachable via slot→row→bed) |
| `tasks` | `garden_id` (not null) | CASCADE | |
| `succession_plans` | `garden_id` (not null) | CASCADE | |
| `planner_messages` | `garden_id` (not null) | CASCADE | Per-garden conversations |
| `advisories` | `garden_id` (not null) | CASCADE | Daily AI advisory is per-garden |

### Transitively scoped (no garden_id needed)

- `rows` — FK to beds (CASCADE) → implicitly per-garden
- `slots` — FK to rows (CASCADE) → implicitly per-garden
- `tasks_plants` — join table, cascades from tasks + plants
- `tasks_beds` — join table, cascades from tasks + beds
- `photos` — FK to plant (SET NULL) → implicitly per-garden
- `harvests` — FK to plant (CASCADE) → implicitly per-garden
- `stage_histories` — FK to plant (CASCADE) → implicitly per-garden

### NOT scoped to garden (global)

- `seed_packets` — physical objects shared across gardens
- `seed_catalog_entries` — reference data

### Migration strategy

1. Create `gardens` table
2. Insert default gardens: "Home" (id=1) and "Cottage" (id=2)
3. Add `garden_id` column (nullable initially) to: beds, arches, indoor_stations, plants, tasks, succession_plans, planner_messages, advisories
4. Backfill all existing rows with `garden_id = 1` (Home)
5. Use Sequel's `set_column_not_null` to add NOT NULL constraint (Sequel handles SQLite's table-rebuild requirement automatically)
6. Drop unique index on `beds.name`, replace with composite unique on `(garden_id, name)`

---

## Active Garden Selection

**Cookie-based:** Store `active_garden_id` in a browser cookie (`httponly`, `SameSite=Lax`). All routes read this cookie to scope queries.

**Sinatra before filter:**
```ruby
before do
  garden_id = request.cookies["garden_id"]&.to_i || 1
  @current_garden = Garden[garden_id] || Garden.first
  @gardens = Garden.order(:name).all  # for the switcher dropdown
end
```

**Switch route:**
```
POST /gardens/switch/:id → sets cookie, redirects to referrer or /
```

---

## UI: Garden Switcher

**Location:** In the layout, visible on every page. Next to the logo in each page's header area.

```
🌱 GardenOS · Home ▾
```

**Implementation:** Alpine.js dropdown in `layout.erb`. The `@gardens` array and `@current_garden` are available in every template via the before filter. ERB renders the dropdown options server-side.

---

## Query Scoping

Every route that queries garden-scoped tables must filter by `@current_garden.id`:

```ruby
# Example:
Plant.where(garden_id: @current_garden.id).exclude(lifecycle_stage: "done").all
Bed.where(garden_id: @current_garden.id).all
Task.where(garden_id: @current_garden.id, due_date: Date.today).all
```

**Dashboard:** Tasks, plants, germination watch for active garden only.
**Garden/Beds:** Beds, arches, indoor stations for active garden.
**Plants:** Plants for active garden.
**Plan:** Succession plans, planner messages for active garden.
**Seeds:** ALL seed packets (global — not scoped).

---

## Background Jobs / Services

**Task generator:** Iterates over ALL gardens, generates tasks for each.
**AI advisory:** Runs once per garden — each garden gets its own advisory set.
**Morning brief notification:** Aggregates across all gardens (or sends one per garden).
**Weather:** Shared (same HA instance, same location for now).

```ruby
# In scheduler.rb:
Garden.all.each do |garden|
  AIAdvisoryService.run_daily!(garden_id: garden.id)
  TaskGenerator.generate_all!(garden_id: garden.id)
end
```

---

## AI Planner

**System prompt** includes the active garden name and location.
**Tools scoped:** `get_beds`, `get_plants`, `get_succession_plans` filter by `@current_garden.id`.
**Not scoped:** `get_seed_inventory` returns all seeds.
**Planner messages** are per-garden — switching gardens shows a different conversation.

---

## HACS / API

**`/api/status`:** Scoped to active garden (via cookie). HACS integration continues to work — it reports for whichever garden the browser cookie is set to.
**`/api/beds`, `/api/plants`, `/api/tasks`:** All scoped to active garden.

---

## Test Strategy

**Test helper update:** `setup` method creates a default garden and sets `@garden`:
```ruby
def setup
  DB.tables.each { |t| DB[t].delete unless [:schema_migrations, :schema_info].include?(t) }
  @garden = Garden.create(name: "Test", created_at: Time.now)
end
```

**Existing tests:** All tests that create Beds, Plants, Tasks, SuccessionPlans need `garden_id: @garden.id` added to their `create` calls. This is mechanical — find/replace across test files.

**Cookie simulation:** Tests that use `get`/`post` via Rack::Test set the cookie:
```ruby
set_cookie "garden_id=#{@garden.id}"
```

---

## Garden Management

**For now:** Two gardens seeded by migration. No UI to create/delete — YAGNI.
**Future:** `GET /settings` page with garden CRUD.

---

## What's NOT changing

- URL structure — no `/gardens/:id/` prefix, clean routes
- Seed inventory — completely global
- Weather/notifications — shared HA config
- Route names — identical, just scoped by cookie
